// The workspace: what the panel pop-up, the detached window and the chart
// windows share besides the engine. No UI of its own; main.qml makes one.
//
//   Unread and highlight -- each alert screen counts the alerts that came in
//     while no view was showing it, and lights its button for
//     `tabFlashSeconds` after each alert. A view says what it shows with
//     setViewing(); looking at a screen clears its count.
//   Mute per screen -- the speaker beside each screen's button
//     (`mutedScreens`; the engine's play() reads the same setting).
//   The active ticker -- the symbol last opened anywhere: a screener row, the
//     watchlist, a typed symbol, a headline's chip. Chart windows that are
//     not pinned follow it. `recentTickers` keeps the last few.
//   Layouts -- named snapshots of the screener and chart settings
//     (`layoutPresets`), saved and restored from the pop-up's header.
//   Export -- every alert of the session on show, as CSV, for the trade
//     journal. Times in New York time.

import QtQuick
import QtCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import QtQuick.LocalStorage
import "screens.js" as Screens
import "options.js" as Options

Item {
    id: ws

    required property var ticker          // main.qml
    readonly property var engine: ticker.screener
    readonly property var cfg: Plasmoid.configuration

    function parse(text, fallback) {
        try { const v = JSON.parse(text || ""); return v === null || v === undefined ? fallback : v } catch (e) { return fallback }
    }

    // ── unread and highlight ─────────────────────────────────────────────
    property var unread: ({})             // screen id -> alerts not yet seen
    property var flashAt: ({})            // screen id -> when it last alerted (ms)
    property var viewing: ({})            // view key -> screen id it shows, "" for none
    property real now: Date.now()
    readonly property int unreadTotal: Object.keys(unread).filter(id => engine.screen(id)).reduce((a, id) => a + unread[id], 0)

    function setViewing(key, id) {
        if ((viewing[key] || "") === (id || "")) return
        const v = Object.assign({}, viewing)
        if (id) v[key] = id; else delete v[key]
        viewing = v
        if (id) clearUnread(id)
    }
    function shown(id) {
        for (const k in viewing) if (viewing[k] === id) return true
        return false
    }
    function clearUnread(id) {
        if (!unread[id]) return
        const u = Object.assign({}, unread)
        delete u[id]
        unread = u
    }
    // Lit: alerted within the last `tabFlashSeconds`. Reads `now`, which
    // ticks only while something is lit.
    function lit(id) {
        const s = cfg.tabFlashSeconds
        return s > 0 && now - (flashAt[id] || 0) < s * 1000
    }
    Connections {
        target: ws.engine
        function onAlerted(feed) {
            const t = Date.now()
            const f = Object.assign({}, ws.flashAt)
            f[feed] = t
            ws.flashAt = f
            ws.now = t
            if (!ws.shown(feed)) {
                const u = Object.assign({}, ws.unread)
                u[feed] = (u[feed] || 0) + 1
                ws.unread = u
            }
        }
    }
    Timer {
        interval: 500
        repeat: true
        running: ws.cfg.tabFlashSeconds > 0
                 && Object.keys(ws.flashAt).some(id => ws.now - ws.flashAt[id] < ws.cfg.tabFlashSeconds * 1000 + 1000)
        onTriggered: ws.now = Date.now()
    }

    // ── mute per screen ──────────────────────────────────────────────────
    readonly property var muted: { const l = parse(cfg.mutedScreens, []); return Array.isArray(l) ? l : [] }
    function isMuted(id) { return muted.indexOf(id) >= 0 }
    function toggleMute(id) {
        cfg.mutedScreens = JSON.stringify(isMuted(id) ? muted.filter(x => x !== id) : muted.concat([id]))
    }
    // Screens that alert, and so have a sound to mute and an unread count.
    function alerting(sc) { return !!sc && (sc.type === "running" || sc.type === "hod" || sc.type === "levels" || sc.type === "uoa") }

    // ── the active ticker ────────────────────────────────────────────────
    // An entry as the pop-up opens it: {symbol, label, name, ...}.
    property var active: null
    readonly property var recent: { const l = parse(cfg.recentTickers, []); return Array.isArray(l) ? l : [] }
    function setActive(e) {
        if (!e || !e.symbol) return
        active = e
        const n = cfg.recentCount
        const r = [{ symbol: e.symbol, label: e.label || e.symbol, name: e.name || e.symbol }]
                  .concat(recent.filter(x => x.symbol !== e.symbol)).slice(0, Math.max(0, n))
        const text = JSON.stringify(r)
        if (text !== cfg.recentTickers) cfg.recentTickers = text
    }
    // A typed symbol, as an entry. Coinbase trades a coin against USD as
    // "BTC-USD": a plain symbol with such a pair opens as the coin; a symbol
    // with a suffix opens as typed; otherwise a stock if Yahoo has a price
    // for it, else the Yahoo crypto pair (Monero is not on Coinbase).
    function resolve(typed, done) {
        const t = String(typed || "").trim().toUpperCase()
        if (!t.length || !/^[A-Z0-9.^=\-]{1,20}$/.test(t)) return
        const open = sym => done({ symbol: sym, label: sym, name: sym, star: false })
        if (Object.keys(engine.cproducts).length === 0) engine.refreshCryptoProducts(true)
        if (/[-^=]/.test(t)) return open(t)
        if (engine.cproducts[t + "-USD"]) return open(t + "-USD")
        ticker.yget("https://query1.finance.yahoo.com/v8/finance/chart/" + encodeURIComponent(t) + "?range=1d&interval=1d", x => {
            let priced = false
            try { priced = (JSON.parse(x.responseText).chart.result[0].meta.regularMarketPrice || 0) > 0 } catch (e) {}
            open(priced ? t : t + "-USD")
        })
    }

    // ── chart windows ────────────────────────────────────────────────────
    // `chartWindows` lists the open ones (ChartWindow.qml); main.qml makes a
    // window per id. `chartIds` changes only when a window opens or closes,
    // so saving one window's size or range does not rebuild the others.
    readonly property var chartWindows: { const l = parse(cfg.chartWindows, []); return Array.isArray(l) ? l.filter(c => c && c.id) : [] }
    property var chartIds: []
    onChartWindowsChanged: {
        const ids = chartWindows.map(c => c.id)
        if (ids.join(",") !== chartIds.join(",")) chartIds = ids
    }
    function chart(id) { return chartWindows.find(c => c.id === id) || null }
    // The TradingView windows' shared web profile (TvProfile.qml), made the
    // first time one opens and kept for the widget's life.
    readonly property var tvProfile: tvProfileLoader.item
    Loader {
        id: tvProfileLoader
        active: false
        source: "TvProfile.qml"
    }
    function wantTvProfile() { tvProfileLoader.active = true; return tvProfileLoader.item }
    // kind "chart", "tv" or "quote"; symbol "" follows the active ticker.
    // `extra`: more fields for the window, e.g. {signIn: time}.
    function openChart(kind, symbol, range, extra) {
        const e = symbol ? (recent.find(r => r.symbol === symbol) || { symbol: symbol }) : null
        // A number for its title ("TradingView 2 · AAPL"): the lowest free
        // one, so a KWin window rule can put each window back on its monitor.
        const used = chartWindows.map(c => c.n)
        let n = 1
        while (used.indexOf(n) >= 0) n++
        const c = Object.assign({ id: "c" + Date.now().toString(36), n: n, kind: kind === "tv" || kind === "quote" ? kind : "chart", symbol: symbol || "",
                                  label: e ? e.label || symbol : "", name: e ? e.name || symbol : "", range: range || "5m" }, extra || {})
        cfg.chartWindows = JSON.stringify(chartWindows.concat([c]))
    }
    function updateChart(id, changes) {
        let changed = false
        const l = chartWindows.map(c => {
            if (c.id !== id) return c
            const n = Object.assign({}, c, changes)
            if (JSON.stringify(n) !== JSON.stringify(c)) changed = true
            return n
        })
        if (changed) cfg.chartWindows = JSON.stringify(l)
    }
    function closeChart(id) { cfg.chartWindows = JSON.stringify(chartWindows.filter(c => c.id !== id)) }
    // A TradingView window, opened on the sign-in page if `signIn`: the open
    // one if there is one, else a new one following the active ticker.
    function openTradingView(signIn) {
        const tv = chartWindows.find(c => c.kind === "tv")
        if (tv) updateChart(tv.id, { signIn: signIn ? Date.now() : 0, raise: Date.now() })
        else openChart("tv", "", "5m", signIn ? { signIn: Date.now() } : {})
    }
    // ── the quote window ──
    // A quote card in a window (ChartWindow.qml, kind "quote"). While a
    // linked one is open, the pop-up's clicks go to it (`quoteFollowsClicks`);
    // a widget window's clicks always do (Popup.open), opening one if needed.
    readonly property bool quoteLinked: chartWindows.some(c => c.kind === "quote" && !c.symbol)
    // Shows `e` in the linked quote window, made if there is none; `raise`
    // brings it forward (its pop-out button), a list click does not, so the
    // list keeps the keyboard and the mouse.
    function openQuote(e, raise) {
        setActive(e)
        const q = chartWindows.find(c => c.kind === "quote" && !c.symbol)
        if (!q) openChart("quote", "", "1D")
        else if (raise) updateChart(q.id, { raise: Date.now() })
    }

    // ── widget windows ───────────────────────────────────────────────────
    // More of the pop-up in windows (WidgetWindow.qml), beside the detached
    // window (TickerWindow.qml): every pop-out after the first opens one, on
    // the tab and screen it was pressed on. `widgetWindows` lists them:
    // {id, n, tab, screen, w, h}; main.qml makes a window per id.
    readonly property var widgetWindows: { const l = parse(cfg.widgetWindows, []); return Array.isArray(l) ? l.filter(c => c && c.id) : [] }
    property var widgetIds: []
    onWidgetWindowsChanged: {
        const ids = widgetWindows.map(c => c.id)
        if (ids.join(",") !== widgetIds.join(",")) widgetIds = ids
    }
    function widgetWindow(id) { return widgetWindows.find(c => c.id === id) || null }
    function openWidgetWindow(tab, screen) {
        const used = widgetWindows.map(c => c.n)
        let n = 2                      // the detached window is the first
        while (used.indexOf(n) >= 0) n++
        cfg.widgetWindows = JSON.stringify(widgetWindows.concat([{ id: "w" + Date.now().toString(36), n: n, tab: tab || 0, screen: screen || "" }]))
    }
    function updateWidgetWindow(id, changes) {
        let changed = false
        const l = widgetWindows.map(c => {
            if (c.id !== id) return c
            const n = Object.assign({}, c, changes)
            if (JSON.stringify(n) !== JSON.stringify(c)) changed = true
            return n
        })
        if (changed) cfg.widgetWindows = JSON.stringify(l)
    }
    function closeWidgetWindow(id) { cfg.widgetWindows = JSON.stringify(widgetWindows.filter(c => c.id !== id)) }

    // A TradingView window always, even with one open (the pop-up's
    // button): several can be open, one per bar size.
    function newTradingView() {
        const open = chartWindows.filter(c => c.kind === "tv").map(c => c.range)
        const next = ["5m", "1m", "15m", "1h", "1Y", "5Y"].find(k => open.indexOf(k) < 0) || "5m"
        openChart("tv", "", next)
    }
    // Settings → Workspace asks through a setting: the pages cannot reach
    // the widget's objects.
    Connections {
        target: Plasmoid.configuration
        function onTvSignInRequestChanged() { if (ws.cfg.tvSignInRequest) ws.openTradingView(true) }
    }

    // ── layouts ──────────────────────────────────────────────────────────
    // A layout carries these settings as they are, plus which screens are on.
    readonly property var presetKeys: ["screenerLayout", "screenerSort", "screenerView", "screenerTools", "scoreCompact",
                                       "mutedScreens", "chartEmas", "chartCandles", "chartVwap", "chartVolume",
                                       "chartWindows", "widgetWindows"]
    readonly property var presets: { const p = parse(cfg.layoutPresets, {}); return p && typeof p === "object" && !Array.isArray(p) ? p : {} }
    readonly property var presetNames: Object.keys(presets).sort((a, b) => a.localeCompare(b))
    function savePreset(name) {
        name = String(name || "").trim()
        if (!name) return
        const snap = {}
        for (const k of presetKeys) if (k in cfg) snap[k] = cfg[k]
        const on = {}
        for (const s of Screens.load(cfg)) on[s.id] = s.on !== false
        snap.screensOn = on
        const all = Object.assign({}, presets)
        all[name] = snap
        cfg.layoutPresets = JSON.stringify(all)
    }
    function loadPreset(name) {
        const snap = presets[name]
        if (!snap) return
        for (const k of presetKeys) if (k in snap && k in cfg && cfg[k] !== snap[k]) cfg[k] = snap[k]
        // Screens added since the layout was saved stay as they are.
        if (snap.screensOn) {
            const list = Screens.load(cfg).map(s => s.id in snap.screensOn
                ? Object.assign({}, s, { on: !!snap.screensOn[s.id] }) : s)
            const text = JSON.stringify(list)
            if (text !== cfg.screens) cfg.screens = text
        }
    }
    function deletePreset(name) {
        const all = Object.assign({}, presets)
        delete all[name]
        cfg.layoutPresets = JSON.stringify(all)
    }

    // ── export ───────────────────────────────────────────────────────────
    // Every alert screen's rows for the session on show (crypto: the last 24
    // hours), oldest first, one CSV file per day:
    // <folder>/alerts-<YYYY-MM-DD>.csv. Written through the shell, base64
    // in single quotes, so nothing in a headline can reach the command.
    readonly property string documents: String(StandardPaths.writableLocation(StandardPaths.DocumentsLocation)).replace(/^file:\/\//, "")
    readonly property string exportDir: {
        const own = String(cfg.exportFolder || "").trim()
        if (!own) return documents + "/Plasma Ticker Tape"
        return own.replace(/^~(?=\/|$)/, documents.replace(/\/Documents$/, ""))
    }
    property string exportNote: ""
    property string exportedFile: ""
    function csvCell(v) {
        const s = v === null || v === undefined || (typeof v === "number" && !isFinite(v)) ? "" : String(v)
        return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s
    }
    // "2026-10-26", "09:41:07" in New York time.
    function etParts(ms) {
        const d = new Date(ms + engine.etOffset * 1000).toISOString()
        return [d.slice(0, 10), d.slice(11, 19)]
    }
    function exportRows() {
        const out = []
        for (const sc of engine.screens) {
            if (!alerting(sc)) continue
            for (const r of engine.rows(sc.id)) out.push({ sc: sc, r: r })
        }
        return out.sort((a, b) => a.r.time - b.r.time)
    }
    function exportCsv() {
        const rows = exportRows()
        if (!rows.length) { exportNote = i18n("No alerts to export yet."); exportedFile = ""; return }
        const head = ["date_et", "time_et", "screen", "market", "symbol", "price_usd", "change_pct", "gap_pct", "volume",
                      "float", "rvol_day", "rvol_5min_pct", "short_float_pct", "score", "score_of", "alerts_folded",
                      "level", "detail", "headline"]
        const lines = [head.join(",")]
        const num = (v, d) => typeof v === "number" && isFinite(v) ? (d === undefined ? v : Number(v.toFixed(d))) : ""
        for (const x of rows) {
            const r = x.r, et = etParts(r.time)
            lines.push([et[0], et[1], x.sc.name, r.market === "crypto" ? "crypto" : "stocks", r.symbol,
                        num(r.priceUsd !== undefined ? r.priceUsd : r.price, 6), num(r.change, 2), num(r.gap, 2), num(r.volume),
                        num(r.float), num(r.rvol, 2), num(r.rvol5, 0), num(r.shortFloat, 2),
                        r.score === null || r.score === undefined ? "" : r.score, r.total || "", r.count || 1,
                        r.levelName ? r.levelName + " " + r.level : r.contract || "", r.detailText || "", r.newsTitle || ""].map(csvCell).join(","))
        }
        const day = etParts(rows[rows.length - 1].r.time)[0]
        writeFile(exportDir, "alerts-" + day + ".csv", lines.join("\n") + "\n", (ok, path) => {
            exportedFile = ok ? path : ""
            exportNote = ok ? i18np("Saved 1 alert to %2", "Saved %1 alerts to %2", rows.length, path)
                            : i18n("Could not write to %1", exportDir)
        })
    }

    // ── option chains ────────────────────────────────────────────────────
    // Yahoo's free chain (v7 options, crumb needed): every contract's bid,
    // ask, last, volume, open interest and implied volatility, delayed about
    // 15 minutes. Kept 5 minutes per symbol and expiry and shared by the
    // Options tab, the chart's open-interest lines and the IV record.
    // done(chain) with {expirations: [s], strikes, quote, calls, puts,
    // expiration: s} or null.
    property var chains: ({})
    function optionChain(sym, expiration, done) {
        const key = sym + "|" + (expiration || "")
        const hit = chains[key]
        if (hit && Date.now() - hit.at < 5 * 60000) { done(hit.chain); return }
        const ask = retried => ticker.withCrumb(c => {
            ticker.yget("https://query2.finance.yahoo.com/v7/finance/options/" + encodeURIComponent(sym)
                        + "?crumb=" + encodeURIComponent(c) + (expiration ? "&date=" + expiration : ""), x => {
                if (x.status === 401 && !retried) { ticker.crumb = ""; ask(true); return }
                let chain = null
                try {
                    const r = JSON.parse(x.responseText).optionChain.result[0]
                    const o = r.options && r.options[0]
                    if (o) chain = { expirations: r.expirationDates || [], strikes: r.strikes || [], quote: r.quote || {},
                                     calls: o.calls || [], puts: o.puts || [], expiration: o.expirationDate }
                } catch (e) {}
                if (chain) { const n = Object.assign({}, chains); n[key] = { at: Date.now(), chain: chain }; chains = n }
                done(chain)
            })
        })
        ask(false)
    }

    // ── the journal ──────────────────────────────────────────────────────
    // Option trades and notes, in the widget's own database
    // (MarketTickerJournal, beside the alerts). Times are kept in ms and
    // shown and exported in New York time, as the trade journal keeps them.
    //   trade -- {id, symbol, opened, closed (0 while open), legs (options.js
    //            legs, JSON), cost (dollars: + paid, - received), exitValue,
    //            result (dollars), notes}
    //   note  -- {id, symbol, time, text, trade (a trade's id or "")}
    //   ivhist -- one at-the-money IV per symbol per ET day, for IV rank.
    property var journalDb: null
    property var trades: []               // newest first
    property var notes: []                // newest first
    function openJournal() {
        if (journalDb) return true
        try {
            journalDb = LocalStorage.openDatabaseSync("MarketTickerJournal", "1.0", "Plasma Ticker Tape journal", 5000000)
            journalDb.transaction(tx => {
                tx.executeSql("CREATE TABLE IF NOT EXISTS trades (id TEXT PRIMARY KEY, symbol TEXT, opened INTEGER, closed INTEGER, legs TEXT, cost REAL, exitValue REAL, result REAL, notes TEXT)")
                tx.executeSql("CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY, symbol TEXT, time INTEGER, text TEXT, trade TEXT)")
                tx.executeSql("CREATE TABLE IF NOT EXISTS ivhist (symbol TEXT, day TEXT, iv REAL, PRIMARY KEY (symbol, day))")
            })
            // Screenshots on notes (added in 1.3): a JSON array of file paths.
            // A database from before has no such column yet.
            try { journalDb.transaction(tx => tx.executeSql("ALTER TABLE notes ADD COLUMN images TEXT")) } catch (e) {}
            return true
        } catch (e) {
            console.warn("marketticker: journal database unavailable:", e)
            journalDb = null
            return false
        }
    }
    function loadJournal() {
        if (!openJournal()) return
        journalDb.readTransaction(tx => {
            const t = [], n = []
            const rs = tx.executeSql("SELECT * FROM trades ORDER BY opened DESC")
            for (let i = 0; i < rs.rows.length; i++) {
                const r = Object.assign({}, rs.rows.item(i))
                try { r.legs = JSON.parse(r.legs || "[]") } catch (e) { r.legs = [] }
                t.push(r)
            }
            const ns = tx.executeSql("SELECT * FROM notes ORDER BY time DESC")
            for (let i = 0; i < ns.rows.length; i++) {
                const r = Object.assign({}, ns.rows.item(i))
                try { r.images = JSON.parse(r.images || "[]") } catch (e) { r.images = [] }
                if (!Array.isArray(r.images)) r.images = []
                n.push(r)
            }
            trades = t
            notes = n
        })
    }
    Component.onCompleted: { chartIds = chartWindows.map(c => c.id); loadJournal() }
    function newId(p) { return p + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36) }
    function addTrade(symbol, legs, cost, note) {
        if (!openJournal() || !legs.length) return ""
        const id = newId("t")
        journalDb.transaction(tx => tx.executeSql("INSERT INTO trades VALUES (?, ?, ?, 0, ?, ?, NULL, NULL, ?)",
                                                  [id, symbol, Date.now(), JSON.stringify(legs), cost, note || ""]))
        loadJournal()
        return id
    }
    // Closed with what closing it brought in (dollars, + received).
    function closeTrade(id, exitValue) {
        const t = trades.find(x => x.id === id)
        if (!t || !openJournal()) return
        journalDb.transaction(tx => tx.executeSql("UPDATE trades SET closed = ?, exitValue = ?, result = ? WHERE id = ?",
                                                  [Date.now(), exitValue, exitValue - t.cost, id]))
        loadJournal()
    }
    function reopenTrade(id) {
        if (!openJournal()) return
        journalDb.transaction(tx => tx.executeSql("UPDATE trades SET closed = 0, exitValue = NULL, result = NULL WHERE id = ?", [id]))
        loadJournal()
    }
    function deleteTrade(id) {
        if (!openJournal()) return
        journalDb.transaction(tx => {
            tx.executeSql("DELETE FROM trades WHERE id = ?", [id])
            tx.executeSql("UPDATE notes SET trade = '' WHERE trade = ?", [id])
        })
        loadJournal()
    }
    // `images`: screenshots saved by pasteImage(), as file paths. A note
    // may be only screenshots.
    function addNote(symbol, text, trade, images) {
        text = String(text || "").trim()
        const pics = Array.isArray(images) ? images.filter(x => x) : []
        if ((!text && !pics.length) || !openJournal()) return
        journalDb.transaction(tx => tx.executeSql("INSERT INTO notes (id, symbol, time, text, trade, images) VALUES (?, ?, ?, ?, ?, ?)",
                                                  [newId("n"), symbol, Date.now(), text, trade || "", JSON.stringify(pics)]))
        loadJournal()
    }
    function deleteNote(id) {
        if (!openJournal()) return
        journalDb.transaction(tx => tx.executeSql("DELETE FROM notes WHERE id = ?", [id]))
        loadJournal()
    }
    function tradeLabel(t) {
        const legs = (t.legs || []).map(l => (l.side < 0 ? "-" : "+") + l.qty + " "
            + (l.type === "stock" ? i18n("shares") : (l.strike + (l.type === "call" ? "C" : "P") + " "
               + Qt.formatDate(new Date(l.expiry), "MMM d"))))
        return t.symbol + " " + legs.join(" / ")
    }
    // "2026-10-26 09:41" in New York time.
    function etStamp(ms) { const p = etParts(ms); return p[0] + " " + p[1].slice(0, 5) }
    // The journal as Markdown, for the trade journal: the trades opened or
    // closed on `day` (an ET date; empty = every day) and that day's notes.
    function exportJournal(day) {
        const inDay = ms => !day || (ms > 0 && etParts(ms)[0] === day)
        const money = v => (v < 0 ? "-$" : "$") + Math.abs(v).toFixed(2)
        const t = trades.filter(x => inDay(x.opened) || inDay(x.closed)).slice().reverse()
        const n = notes.filter(x => inDay(x.time)).slice().reverse()
        const lines = ["# Options journal" + (day ? " — " + day : ""), "",
                       i18n("Times in New York time (ET). Exported from Plasma Ticker Tape."), ""]
        lines.push("## " + i18n("Trades"), "")
        if (!t.length) lines.push(i18n("None."), "")
        for (const x of t) {
            lines.push("### " + tradeLabel(x))
            lines.push("- " + i18n("Opened: %1, %2 %3", etStamp(x.opened), x.cost >= 0 ? i18n("paid") : i18n("received"), money(Math.abs(x.cost))))
            if (x.closed > 0) lines.push("- " + i18n("Closed: %1, value %2, result **%3**", etStamp(x.closed), money(x.exitValue), money(x.result)))
            else lines.push("- " + i18n("Open"))
            if (x.notes) lines.push("- " + i18n("Note: %1", x.notes))
            for (const k of notes.filter(m => m.trade === x.id).slice().reverse()) {
                lines.push("- " + etStamp(k.time) + ": " + (k.text || i18n("(screenshot)")))
                for (const p of k.images || []) lines.push("  " + mdImage(p))
            }
            lines.push("")
        }
        lines.push("## " + i18n("Notes"), "")
        const loose = n.filter(m => !m.trade)
        if (!loose.length) lines.push(i18n("None."))
        for (const k of loose) {
            lines.push("- " + etStamp(k.time) + " **" + k.symbol + "**: " + (k.text || i18n("(screenshot)")))
            for (const p of k.images || []) lines.push("  " + mdImage(p))
        }
        const name = "journal-" + (day || "all") + ".md"
        writeFile(exportDir, name, lines.join("\n") + "\n", (ok, path) => {
            exportedFile = ok ? path : ""
            exportNote = ok ? i18n("Journal saved to %1", path) : i18n("Could not write to %1", exportDir)
        })
    }

    // A screenshot as Markdown, for the journal file in `exportDir`: by its
    // path from there when it is inside it (screenshots/…), else as a file
    // address.
    function mdImage(path) {
        const p = String(path)
        const base = exportDir.replace(/\/+$/, "") + "/"
        const where = p.indexOf(base) === 0 ? p.slice(base.length) : "file://" + p
        return "![" + p.replace(/^.*\//, "") + "](" + encodeURI(where) + ")"
    }

    // ── screenshots ──────────────────────────────────────────────────────
    // A picture on the clipboard, saved as a PNG in <export folder>/
    // screenshots/ for a journal note: through wl-paste (the wl-clipboard
    // package) on Wayland, else xclip. The name is the time in New York and
    // the symbol: 2026-10-26_094107-312_JYD.png.
    // done(path) with the saved file, or done("", why) -- why is "none" (no
    // image on the clipboard), "tool" (neither program installed) or "fail".
    readonly property string shotDir: exportDir.replace(/\/+$/, "") + "/screenshots"
    // A new file's path there: New York date and time, then the symbol and
    // an optional tag ("chart-5m").
    function shotPath(symbol, tag) {
        const et = etParts(Date.now())
        const clean = x => String(x || "").replace(/[^A-Za-z0-9.=-]/g, "")
        return shotDir + "/" + et[0] + "_" + et[1].replace(/:/g, "") + "-" + String(Date.now() % 1000).padStart(3, "0") + "_"
               + (clean(symbol) || "note") + (clean(tag) ? "_" + clean(tag) : "") + ".png"
    }
    function pasteImage(symbol, done) {
        const path = shotPath(symbol, "")
        const tmp = path + ".part"
        const cmd = "mkdir -p " + shq(shotDir) + " || exit 5; "
            + "if command -v wl-paste >/dev/null 2>&1 && [ -n \"$WAYLAND_DISPLAY\" ] && wl-paste --list-types 2>/dev/null | grep -qx image/png; then "
            + "wl-paste --no-newline --type image/png > " + shq(tmp) + "; "
            + "elif command -v xclip >/dev/null 2>&1 && xclip -selection clipboard -t TARGETS -o 2>/dev/null | grep -qx image/png; then "
            + "xclip -selection clipboard -t image/png -o > " + shq(tmp) + "; "
            + "elif ! command -v wl-paste >/dev/null 2>&1 && ! command -v xclip >/dev/null 2>&1; then echo tool; exit 3; "
            + "else echo none; exit 4; fi; "
            + "if [ -s " + shq(tmp) + " ]; then mv -f " + shq(tmp) + " " + shq(path) + "; else rm -f " + shq(tmp) + "; echo fail; exit 6; fi"
        run(cmd, (ok, out) => done(ok ? path : "", ok ? "" : (String(out).trim() || "fail")))
    }

    // ── implied volatility history ───────────────────────────────────────
    function recordIv(symbol, iv) {
        if (!(iv > 0) || !cfg.ivRecord || !openJournal()) return
        const day = etParts(Date.now())[0]
        journalDb.transaction(tx => {
            tx.executeSql("INSERT OR REPLACE INTO ivhist VALUES (?, ?, ?)", [symbol, day, iv])
            tx.executeSql("DELETE FROM ivhist WHERE day < ?", [etParts(Date.now() - 400 * 86400000)[0]])
        })
    }
    function ivHistory(symbol) {
        if (!openJournal()) return []
        const out = []
        journalDb.readTransaction(tx => {
            const rs = tx.executeSql("SELECT iv FROM ivhist WHERE symbol = ? AND day >= ? ORDER BY day",
                                     [symbol, etParts(Date.now() - 366 * 86400000)[0]])
            for (let i = 0; i < rs.rows.length; i++) out.push(rs.rows.item(i).iv)
        })
        return out
    }
    // Once a trading day, after 10:00 ET: each watchlist stock's at-the-money
    // IV from its nearest expiry a week or more out.
    property string ivDay: ""
    Timer {
        interval: 15 * 60000
        repeat: true
        triggeredOnStart: true
        running: ws.cfg.ivRecord && ws.engine.currentPhase === "regular"
        onTriggered: {
            const day = ws.etParts(Date.now())[0]
            if (ws.ivDay === day || ws.engine.etMinutes(Date.now() / 1000) < 600) return
            ws.ivDay = day
            const syms = ws.ticker.symbols.map(s => s.symbol).filter(s => /^[A-Z][A-Z0-9.\-]{0,9}$/.test(s))
            for (const sym of syms) ws.recordIvFor(sym)
        }
    }
    function recordIvFor(sym) { ivInfo(sym, x => { if (x) recordIv(sym, x.iv) }) }
    // A symbol's at-the-money IV from its nearest expiry a week or more out
    // (the one recorded), with its rank: done({iv, rank, days, chain}) or null.
    function ivInfo(sym, done) {
        optionChain(sym, "", first => {
            if (!first) { done(null); return }
            const S = first.quote.regularMarketPrice
            const week = Date.now() / 1000 + 6 * 86400
            const exp = first.expirations.find(e => e >= week)
            const finish = c => {
                const iv = Options.atmIv(c.calls, c.puts, S)
                const h = ivHistory(sym)
                done(iv > 0 ? { iv: iv, rank: Options.ivRank(iv, h, 20), days: h.length, chain: c } : null)
            }
            if (!exp || exp === first.expiration) finish(first)
            else optionChain(sym, exp, c => c ? finish(c) : done(null))
        })
    }
    // The move priced in through an earnings date (ms): the at-the-money
    // straddle of the first expiry on or after it. done({dollars, pct,
    // expiry}) or null.
    function earningsMove(sym, at, done) {
        if (!(at > Date.now() - 86400000)) { done(null); return }
        optionChain(sym, "", first => {
            const exp = first ? first.expirations.find(e => e * 1000 >= at - 12 * 3600000) : null
            if (!exp) { done(null); return }
            optionChain(sym, exp, c => {
                const m = c ? Options.expectedMove(c.calls, c.puts, c.quote.regularMarketPrice || first.quote.regularMarketPrice) : null
                done(m ? Object.assign({ expiry: exp * 1000 }, m) : null)
            })
        })
    }
    // The strikes with the most open interest and max pain, for the nearest
    // expiry a week or more out: done({levels: [{strike, total}], pain,
    // expiry}) or null.
    function optionLevels(sym, done) {
        ivInfo(sym, x => {
            if (!x) { done(null); return }
            done({ levels: Options.oiLevels(x.chain.calls, x.chain.puts, 3), pain: Options.maxPain(x.chain.calls, x.chain.puts),
                   expiry: x.chain.expiration * 1000 })
        })
    }

    // ── expiry alerts ────────────────────────────────────────────────────
    // Open journal trades with options: a desktop notification once a day
    // when the nearest expiry is `optExpiryDays` away or less, and once a
    // day per strike when the stock comes within `optStrikePct` % of a
    // strike of the trade.
    property var warned: ({})
    Timer {
        interval: 5 * 60000
        repeat: true
        triggeredOnStart: true
        running: ws.trades.some(t => !(t.closed > 0) && (t.legs || []).some(l => l.type !== "stock"))
        onTriggered: ws.checkExpiries()
    }
    function checkExpiries() {
        const day = etParts(Date.now())[0]
        for (const t of trades) {
            if (t.closed > 0) continue
            const opts = (t.legs || []).filter(l => l.type !== "stock" && l.expiry > 0)
            if (!opts.length) continue
            const soonest = Math.min(...opts.map(l => l.expiry))
            const days = (soonest - Date.now()) / 86400000
            const k1 = t.id + "|exp|" + day
            if (cfg.optExpiryDays > 0 && days <= cfg.optExpiryDays && !warned[k1]) {
                warned[k1] = true
                notify(i18n("%1 expires soon", tradeLabel(t)),
                       days <= 0 ? i18n("Expiring today.") : i18np("1 day to expiry.", "%1 days to expiry.", Math.ceil(days)))
            }
            if (!(cfg.optStrikePct > 0)) continue
            withPrice(t.symbol, S => {
                for (const l of opts) {
                    const k2 = t.id + "|k" + l.strike + "|" + day
                    if (warned[k2] || !(S > 0) || Math.abs(S / l.strike - 1) * 100 > cfg.optStrikePct) continue
                    warned[k2] = true
                    notify(i18n("%1 near the %2 strike", t.symbol, l.strike),
                           i18n("%1 at %2, within %3% of the %4 %5 in %6.", t.symbol, S.toFixed(2), cfg.optStrikePct,
                                l.strike, l.type === "call" ? i18n("call") : i18n("put"), tradeLabel(t)))
                }
            })
        }
    }
    function withPrice(sym, done) {
        const f = ticker.feed(sym)
        if (f.value > 0 && !f.stale) { done(f.value); return }
        ticker.yget("https://query1.finance.yahoo.com/v8/finance/chart/" + encodeURIComponent(sym) + "?range=1d&interval=1d", x => {
            let p = NaN
            try { p = JSON.parse(x.responseText).chart.result[0].meta.regularMarketPrice } catch (e) {}
            done(p)
        })
    }
    // A desktop notification, with the alert sound setting respected by
    // the notification system itself.
    function notify(title, body) {
        run("notify-send -a " + shq("Plasma Ticker Tape") + " -i office-chart-line " + shq(title) + " " + shq(body))
    }

    // ── the shell ────────────────────────────────────────────────────────
    property var waiting: ({})
    property int seq: 0
    P5Support.DataSource {
        id: sh
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            const done = ws.waiting[source]
            delete ws.waiting[source]
            if (done) done(data["exit code"] === 0, String(data["stdout"] || ""))
        }
    }
    function run(cmd, done) {
        const c = cmd + " # ws" + Date.now() + "." + (seq++)
        waiting[c] = done || (() => {})
        sh.connectSource(c)
    }
    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    // Writes `text` to dir/name through a temporary file, in pieces small
    // enough for one command line each.
    function writeFile(dir, name, text, done) {
        const path = dir.replace(/\/+$/, "") + "/" + name
        const tmp = path + ".part"
        // UTF-8 bytes, then base64 (Qt.btoa of a plain string is deprecated).
        const bin = unescape(encodeURIComponent(text))
        const bytes = new Array(bin.length)
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
        const b64 = String(Qt.btoa(bytes))       // a plain array: a Uint8Array comes back empty
        const pieces = []
        for (let i = 0; i < b64.length; i += 60000) pieces.push(b64.slice(i, i + 60000))
        const step = k => {
            if (k === pieces.length) { run("mv -f " + shq(tmp) + " " + shq(path), ok => done(ok, path)); return }
            run("printf '%s' " + shq(pieces[k]) + " | base64 -d >> " + shq(tmp), ok => ok ? step(k + 1) : done(false, path))
        }
        run("mkdir -p " + shq(dir) + " && : > " + shq(tmp), ok => ok ? step(0) : done(false, path))
    }
}
