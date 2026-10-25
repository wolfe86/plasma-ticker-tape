// Watchlist key-level alerts: the "levels" screens (Settings → Screeners,
// type "Alert: watchlist key levels"). The rule itself is levels.js; this
// fetches what it reads and raises its alerts through the engine, so they
// land in the screen's feed like any other alert -- with its sound, its
// button's highlight and count, and the CSV export.
//
// WHAT IS WATCHED: the watchlist's symbols, except crypto and currencies
// (they have no sessions), plus each levels screen's own extra tickers.
//
// FETCHING, every minute from 04:00 to 20:00 ET on trading days: each
// symbol's 1-minute bars for today, premarket included (Yahoo's chart
// endpoint, one request a symbol, three at a time), and once a day its
// daily bars for the prior session's high, low and close. Chart levels come
// from the levels drawn on the symbol's chart (the MarketTickerLevels
// database the quote card writes). Only completed bars are judged, so an
// alert comes a minute or two after the move.
//
// A restart does not repeat the day's alerts: only bars after the widget
// started can alert, though the bars before still arm a setup.

import QtQuick
import QtQuick.LocalStorage
import "levels.js" as Levels
import "screens.js" as Screens

Item {
    id: lw

    required property var engine
    required property var ticker
    readonly property var screens: engine.screens.filter(s => s.type === "levels")
    readonly property bool on: screens.length > 0

    // A symbol worth watching: anything Yahoo charts with sessions.
    function watchable(sym) { return !/-USD$|=X$/.test(sym) && /^[A-Z0-9.^=\-]{1,20}$/.test(sym) }
    function extras(sc) {
        return String(sc.levelTickers || "").toUpperCase().split(/[\s,;]+/).filter(t => t && watchable(t))
    }
    readonly property var symbols: {
        const out = []
        for (const s of ticker.symbols) if (watchable(s.symbol) && out.indexOf(s.symbol) < 0) out.push(s.symbol)
        for (const sc of screens) for (const t of extras(sc)) if (out.indexOf(t) < 0) out.push(t)
        return out
    }
    function screenWatches(sc, sym) {
        return extras(sc).indexOf(sym) >= 0 || (sc.levelWatchlist !== false && ticker.symbols.some(s => s.symbol === sym))
    }

    property var bars: ({})       // symbol -> today's completed 1-minute bars
    property var daily: ({})      // symbol -> {day, pdh, pdl, pdc}
    property var raised: ({})     // "screen|symbol|level|t" -> true
    property real startedAt: Date.now()
    property string day: ""

    readonly property bool live: on && (engine.currentPhase === "pre" || engine.currentPhase === "regular" || engine.currentPhase === "post")
    Timer {
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: lw.live
        onTriggered: lw.pull()
    }

    function etMin(ms) { return engine.etMinutes(ms / 1000) }
    function etDay(ms) { return engine.etDay(ms / 1000) }

    // ── fetching ──
    property var queue: []
    property int busy: 0
    function pull() {
        const today = etDay(Date.now())
        if (today !== day) { day = today; bars = ({}); raised = ({}) }
        queue = symbols.slice()
        pump()
    }
    function pump() {
        while (busy < 3 && queue.length) {
            const sym = queue.shift()
            busy++
            fetchSym(sym, () => { busy--; pump() })
        }
    }
    function fetchSym(sym, done) {
        const d = daily[sym]
        if (!d || d.day !== day) {
            ticker.yget("https://query1.finance.yahoo.com/v8/finance/chart/" + encodeURIComponent(sym) + "?range=10d&interval=1d", x => {
                try {
                    const r = JSON.parse(x.responseText).chart.result[0], q = r.indicators.quote[0]
                    const rows = r.timestamp.map((ts, i) => ({ t: ts * 1000, h: q.high[i], l: q.low[i], c: q.close[i] }))
                    const p = Levels.priorDay(rows, ms => lw.etDay(ms), lw.day)
                    const next = Object.assign({}, lw.daily)
                    next[sym] = Object.assign({ day: lw.day }, p || {})
                    lw.daily = next
                } catch (e) {}
                fetchBars(sym, done)
            })
        } else fetchBars(sym, done)
    }
    function fetchBars(sym, done) {
        ticker.yget("https://query1.finance.yahoo.com/v8/finance/chart/" + encodeURIComponent(sym)
                    + "?range=1d&interval=1m&includePrePost=true", x => {
            try {
                const r = JSON.parse(x.responseText).chart.result[0], q = r.indicators.quote[0]
                const now = Date.now()
                const list = []
                r.timestamp.forEach((ts, i) => {
                    const c = q.close[i]
                    if (typeof c !== "number") return
                    const t = ts * 1000
                    // Completed bars only: the newest is still forming.
                    if (t + 60000 > now) return
                    if (lw.etDay(t) !== lw.day) return
                    const o = typeof q.open[i] === "number" ? q.open[i] : c
                    const h = typeof q.high[i] === "number" ? q.high[i] : c
                    const l = typeof q.low[i] === "number" ? q.low[i] : c
                    list.push({ t: t, o: o, h: Math.max(h, o, c), l: Math.min(l, o, c), c: c })
                })
                const next = Object.assign({}, lw.bars)
                next[sym] = list
                lw.bars = next
                lw.judge(sym)
            } catch (e) {}
            done()
        })
    }

    // ── chart levels ──
    property var levelDb: null
    function manualLevels(sym) {
        try {
            if (!levelDb) levelDb = LocalStorage.openDatabaseSync("MarketTickerLevels", "1.0", "Market Ticker chart levels", 1000000)
            const out = []
            levelDb.readTransaction(tx => {
                // The table is made by the quote card on first use.
                const rs = tx.executeSql("SELECT price FROM levels WHERE symbol = ?", [sym])
                for (let i = 0; i < rs.rows.length; i++) out.push(rs.rows.item(i).price)
            })
            return out
        } catch (e) { return [] }
    }

    // ── judging ──
    function judge(sym) {
        const list = bars[sym] || []
        if (list.length < 2) return
        const d = daily[sym]
        const pd = d && d.pdh > 0 ? d : null
        const manual = manualLevels(sym)
        for (const sc of screens) {
            if (!screenWatches(sc, sym)) continue
            const r = Levels.rule(sc)
            for (const f of Levels.scan(list, ms => lw.etMin(ms), pd, manual, r, startedAt - 60000)) {
                const key = sc.id + "|" + sym + "|" + f.key + "|" + f.t
                if (raised[key]) continue
                raised[key] = true
                const feed = ticker.feed(sym)
                // The day's change: the tape's for a watchlist symbol, else
                // from the prior close.
                const change = typeof feed.pct === "number" ? feed.pct : pd && pd.pdc > 0 ? (f.price / pd.pdc - 1) * 100 : NaN
                const row = {
                    symbol: sym, market: "stocks",
                    name: (feed.meta && (feed.meta.shortName || feed.meta.longName)) || sym,
                    price: f.price,
                    change: change,
                    levelName: f.name, level: f.level,
                    failTime: f.failT, failLow: f.failLow, barTime: f.t
                }
                row.detailText = setupText(row)
                if (Screens.passes(sc, engine.inCurrency(sc, row), "quote")) engine.raise(sc.id, row)
            }
        }
    }
    // "under at 10:01 (low 9.80), back above at 10:03" -- the level itself
    // is its own column. Times in New York time.
    function hhmm(ms) { const d = new Date(ms + engine.etOffset * 1000); return d.toISOString().slice(11, 16) }
    function px(v) { return v >= 1 ? v.toFixed(2) : v.toPrecision(4) }
    function setupText(r) {
        return i18n("under at %1 (low %2), back above at %3", hhmm(r.failTime), px(r.failLow), hhmm(r.barTime))
    }
}
