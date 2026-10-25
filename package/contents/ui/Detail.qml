// The detail view: one symbol, opened by clicking its row in the pop-up.
//
// The price and today's change over two tabs:
//   Overview -- a chart with range buttons (1D to 5Y), then the quote figures
//               Yahoo's own quote page shows (previous close, bid/ask, ranges,
//               volume, market cap, P/E, EPS, earnings date, dividend, target)
//               plus float, short interest and ownership. Only the figures
//               Yahoo has for this kind of symbol are shown.
//   News     -- the latest headlines: for a stock or ETF from the premarket
//               scanner's per-ticker news (Finviz), otherwise Google News.
// The pop-up scrolls, so the whole view is reachable however tall it gets.
//
// The chart is plotted by bar, not by clock time: nights and weekends do not
// leave flat gaps, the way most trading charts draw it. Every range draws the
// same way, as a line or as candles (the Candles button, remembered in the
// `chartCandles` setting), with a volume strip; the intraday bar sizes (1m to
// 1h) add premarket, after hours and VWAP. The scroll wheel zooms around the
// pointer and dragging moves the chart left and right.
// Price levels: double-click the chart to add one at that price. Trend lines:
// the Line button, then click the two ends. Right-click either to remove it.
// Both are kept per symbol (see "levels" below); a trend line is pinned to
// times and prices, so it stays put through zooming and bar-size changes.
// The price scale on the right: the wheel stretches it, dragging moves it,
// a double-click fits it to the bars again.
//
// The card follows its `entry`: a symbol typed into its look-up box, or one
// of the recent tickers under the title, opens in place (`go`), and a chart
// window bound to the active ticker reloads when it changes. With
// `chartOnly` it is just the chart and its controls, for the chart windows
// (ChartWindow.qml). The bars reload every `chartRefreshSeconds` while the
// card is on screen, keeping the view on the newest bar unless it was moved.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import QtQuick.LocalStorage
import "scorecards.js" as Scorecards
import "themes.js" as Themes
import "newsfeeds.js" as NewsFeeds
import "screens.js" as Screens
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: detail

    required property var ticker
    required property var entry       // {symbol, label, name, star} from settings
    signal back()
    // Another symbol, to open in this card's place.
    signal go(var entry)
    readonly property var ws: ticker.workspace
    // Just the chart, its price line and its controls (a chart window).
    property bool chartOnly: false
    // The card in a quote window (ChartWindow.qml, kind "quote"): no chart
    // (the chart windows have it), no back button and no pop-out button.
    property bool inWindow: false
    // In a quote window: whether it follows the active ticker, so a chart
    // opened from it does too (unlinked, the chart keeps this symbol).
    property bool linked: true

    readonly property var f: ticker.feed(entry.symbol)
    readonly property var m: f.meta || ({})
    readonly property bool known: f.value !== null

    spacing: Kirigami.Units.smallSpacing

    // ── the chart data ───────────────────────────────────────────────────
    // Range → bar size. Each pair was checked against Yahoo on 2026-10-22
    // for an index and for bitcoin.
    //
    // The intraday bar sizes come after, shown on their own row: each
    // fetches as much history as Yahoo serves at that size, premarket and
    // after hours included, and opens on the newest `bars` of them; dragging
    // right goes back through the rest. Limits checked 2026-10-23: 1-minute
    // bars for 7 days, 5- to 30-minute for 60 days (1mo is the widest named
    // range inside that), hourly for 2 years.
    //
    // The named ranges fetch more history than they show (`fetch`), and open
    // on their own span (`sessions` trading days, or `days` calendar days):
    // a 200-bar EMA needs 200 bars behind the first one drawn, and 1D alone
    // has about 79. Zooming out shows the extra.
    // `tip` is the button's tooltip: 1M (a month) and 1m (one-minute bars)
    // look alike on the buttons.
    readonly property var ranges: [
        { key: "1D", range: "1d",  interval: "5m",  fetch: "5d",  sessions: 1, tip: i18n("1 day, 5-minute bars") },
        { key: "5D", range: "5d",  interval: "15m", fetch: "1mo", sessions: 5, tip: i18n("5 days, 15-minute bars") },
        { key: "1M", range: "1mo", interval: "60m", fetch: "3mo", days: 30, tip: i18n("1 month, hourly bars") },
        { key: "6M", range: "6mo", interval: "1d",  fetch: "2y",  days: 182, tip: i18n("6 months, daily bars") },
        { key: "1Y", range: "1y",  interval: "1d",  fetch: "2y",  days: 365, tip: i18n("1 year, daily bars") },
        { key: "5Y", range: "5y",  interval: "1wk", fetch: "10y", days: 1826, tip: i18n("5 years, weekly bars") },
        { key: "1m",  range: "7d",  interval: "1m",  intraday: true, tip: i18n("1-minute bars, last 7 days") },
        { key: "5m",  range: "1mo", interval: "5m",  intraday: true, tip: i18n("5-minute bars, last month") },
        { key: "15m", range: "1mo", interval: "15m", intraday: true, tip: i18n("15-minute bars, last month") },
        { key: "30m", range: "1mo", interval: "30m", intraday: true, tip: i18n("30-minute bars, last month") },
        { key: "1h",  range: "1y",  interval: "60m", intraday: true, tip: i18n("Hourly bars, last year") }
    ]
    readonly property int bars: 90           // intraday bars on screen at first
    property int rangeIndex: 0
    readonly property bool intraday: !!ranges[rangeIndex].intraday
    // Candles or a line, for every range alike.
    readonly property bool candles: Plasmoid.configuration.chartCandles
    // Every bar fetched, and the window of them on screen: `viewFrom` is
    // the first bar shown, `viewCount` how many. Zooming changes the count,
    // dragging the start.
    property var full: ({ t: [], o: [], h: [], l: [], c: [], v: [], w: [] })
    property int viewFrom: 0
    property int viewCount: 0
    readonly property int fullCount: full.c.length
    function win(a) { return a.slice(viewFrom, viewFrom + viewCount) }
    readonly property var times: win(full.t)
    readonly property var closes: win(full.c)
    readonly property var opens: win(full.o)
    readonly property var highs: win(full.h)
    readonly property var lows: win(full.l)
    readonly property var vols: win(full.v)
    readonly property var vwap: win(full.w)  // NaN where there is no volume yet
    // ── overlays ──
    // EMAs over every bar fetched, so the line on screen is already settled.
    // Each length has a fixed colour; its button is drawn in it, as a legend.
    readonly property var emaLengths: [9, 20, 50, 200]
    readonly property var emaColours: ({ 9: "#f2c94c", 20: "#2dd4bf", 50: "#a78bfa", 200: "#fb923c" })
    readonly property var emasOn: String(Plasmoid.configuration.chartEmas || "").split(",")
                                      .map(Number).filter(n => emaLengths.indexOf(n) >= 0)
    function toggleEma(n) {
        const on = emasOn.indexOf(n) >= 0 ? emasOn.filter(x => x !== n) : emasOn.concat([n])
        Plasmoid.configuration.chartEmas = on.sort((a, b) => a - b).join(",")
    }
    readonly property var emas: {
        const out = {}
        for (const n of emasOn) out[n] = win(ema(full.c, n))
        return out
    }
    // NaN until `n` bars exist, seeded with their simple average.
    function ema(c, n) {
        const out = new Array(c.length).fill(NaN)
        if (c.length < n) return out
        let e = 0
        for (let i = 0; i < n; i++) e += c[i]
        e /= n
        out[n - 1] = e
        const k = 2 / (n + 1)
        for (let i = n; i < c.length; i++) { e = c[i] * k + e * (1 - k); out[i] = e }
        return out
    }
    // VWAP wherever the bars are minutes or hours; it restarts each day.
    readonly property bool minuteBars: /^\d+m$/.test(ranges[rangeIndex].interval)
    readonly property bool showVwap: minuteBars && Plasmoid.configuration.chartVwap
    readonly property bool showVolume: Plasmoid.configuration.chartVolume
    readonly property int minBars: 10
    // Zoom by `factor` (under 1 is in), keeping the bar at `at` (0-1 across
    // the chart) under the pointer.
    // The window may run past the newest bar, leaving empty space on the
    // right to draw into, but always keeps `keepBars` of them on screen.
    readonly property int keepBars: 5
    readonly property int maxFrom: Math.max(0, fullCount - Math.min(keepBars, fullCount))
    function zoom(factor, at) {
        if (fullCount < 2) return
        const n = Math.max(Math.min(minBars, fullCount), Math.min(fullCount, Math.round(viewCount * factor)))
        if (n === viewCount) return
        const anchor = viewFrom + at * viewCount
        viewCount = n
        viewFrom = Math.max(0, Math.min(maxFrom, Math.round(anchor - at * n)))
    }
    function pan(barsBy) {
        viewFrom = Math.max(0, Math.min(maxFrom, viewFrom + barsBy))
    }
    property bool loading: false
    property bool failed: false
    property var request: null

    // `keep`: a refresh of the same range -- the view stays where it was,
    // moving on with the newest bar if it was showing it, and a failed
    // refresh keeps the bars it has.
    function load(keep) {
        if (inWindow) return
        if (request) request.abort()
        const r = ranges[rangeIndex]
        const x = new XMLHttpRequest()
        const was = keep && fullCount > 1 ? { from: viewFrom, count: viewCount, total: fullCount } : null
        request = x
        loading = true
        failed = false
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE || request !== x) return
            request = null
            loading = false
            try {
                const res = JSON.parse(x.responseText).chart.result[0]
                const q = res.indicators.quote[0]
                const t = [], c = [], o = [], h = [], l = [], vo = [], vw = []
                // VWAP runs from each day's first bar. Yahoo reports no
                // volume for premarket bars, so it starts with the first bar
                // that has some -- in practice the regular open.
                let day = "", pv = 0, vsum = 0
                // Drop bars with no trade rather than draw a dip to zero.
                res.timestamp.forEach((ts, i) => {
                    const cl = q.close[i]
                    if (typeof cl !== "number") return
                    const num = (a, d) => typeof a[i] === "number" ? a[i] : d
                    const op = num(q.open, cl), hi = num(q.high, cl), lo = num(q.low, cl), vol = num(q.volume, 0)
                    const d = new Date((ts + (res.meta.gmtoffset || 0)) * 1000).toISOString().slice(0, 10)
                    if (d !== day) { day = d; pv = 0; vsum = 0 }
                    pv += (hi + lo + cl) / 3 * vol
                    vsum += vol
                    t.push(ts * 1000); c.push(cl); o.push(op); h.push(Math.max(hi, op, cl)); l.push(Math.min(lo, op, cl))
                    vo.push(vol); vw.push(vsum > 0 ? pv / vsum : NaN)
                })
                if (c.length < 2) throw "too few points"
                // Intraday opens on the newest bars; a named range on its
                // own span, with the warm-up history before it off screen.
                let n = c.length
                if (r.intraday) n = Math.min(bars, c.length)
                else if (r.sessions) {
                    const off = (res.meta.gmtoffset || 0) * 1000
                    const dayOf = ms => new Date(ms + off).toISOString().slice(0, 10)
                    const keep = new Set()
                    for (let i = t.length - 1; i >= 0 && keep.size <= r.sessions; i--) {
                        keep.add(dayOf(t[i]))
                        if (keep.size <= r.sessions) n = t.length - i
                    }
                } else if (r.days) {
                    const from = t[t.length - 1] - r.days * 86400000
                    n = t.filter(x => x >= from).length
                }
                n = Math.max(Math.min(minBars, c.length), n)
                if (was) {
                    // At the newest bar: stay there as bars arrive. Moved
                    // back: stay on the same bars.
                    const atEnd = was.from + was.count >= was.total - 1
                    n = Math.max(Math.min(minBars, c.length), Math.min(c.length, was.count))
                    viewCount = n
                    viewFrom = atEnd ? Math.max(0, c.length - n) : Math.max(0, Math.min(c.length - Math.min(keepBars, c.length), was.from))
                } else {
                    viewCount = n
                    viewFrom = c.length - n
                }
                full = { t: t, o: o, h: h, l: l, c: c, v: vo, w: vw }
            } catch (e) {
                if (was) return
                // A Coinbase pair Yahoo does not chart: Coinbase's own candles.
                if (ticker.screener.isCryptoSymbol(entry.symbol)) { loadCoinbase(r); return }
                failed = true
                viewFrom = 0; viewCount = 0
                full = { t: [], o: [], h: [], l: [], c: [], v: [], w: [] }
            }
        }
        x.open("GET", "https://query1.finance.yahoo.com/v8/finance/chart/"
               + encodeURIComponent(entry.symbol) + "?range=" + (r.fetch || r.range) + "&interval=" + r.interval
               + (r.intraday ? "&includePrePost=true" : ""))
        x.setRequestHeader("User-Agent", "Mozilla/5.0")
        x.send()
    }
    onRangeIndexChanged: { autoScale = true; load() }
    // Live bars: reloaded while the card is on screen. Coinbase-only pairs
    // reload whole, as they were drawn.
    Timer {
        interval: Math.max(5, Plasmoid.configuration.chartRefreshSeconds) * 1000
        repeat: true
        running: Plasmoid.configuration.chartRefreshSeconds > 0 && detail.visible && !detail.inWindow
                 && !!detail.Window.window && detail.Window.window.visible && detail.tab === 0
        onTriggered: if (!detail.loading) detail.load(true)
    }

    // ── Coinbase candles ──
    // For crypto pairs Yahoo has no chart for. Coinbase's public candles
    // come in six sizes (1, 5, 15, 60 minutes, 6 hours, a day), 300 to a
    // request, newest first; `pages` requests go back far enough to settle a
    // 200-bar EMA, `agg` joins bars for sizes Coinbase lacks (30 minutes,
    // weekly), and `show` is how many open on screen. Crypto never closes, so
    // a "day" is 24 hours and VWAP restarts at UTC midnight.
    readonly property var coinbaseSpec: ({
        "1D":  { g: 300,   pages: 2, show: 288 },
        "5D":  { g: 900,   pages: 3, show: 480 },
        "1M":  { g: 3600,  pages: 4, show: 720 },
        "6M":  { g: 86400, pages: 2, show: 182 },
        "1Y":  { g: 86400, pages: 2, show: 365 },
        "5Y":  { g: 86400, pages: 7, show: 261, agg: 7 },
        "1m":  { g: 60,    pages: 2 },
        "5m":  { g: 300,   pages: 3 },
        "15m": { g: 900,   pages: 2 },
        "30m": { g: 900,   pages: 4, agg: 2 },
        "1h":  { g: 3600,  pages: 2 }
    })
    function loadCoinbase(r) {
        const spec = coinbaseSpec[r.key]
        if (!spec) { failed = true; return }
        const rows = []
        loading = true
        const page = (k, end) => {
            const start = end - 300 * spec.g
            const x = new XMLHttpRequest()
            request = x
            x.onreadystatechange = () => {
                if (x.readyState !== XMLHttpRequest.DONE || request !== x) return
                let got = null
                try { got = JSON.parse(x.responseText) } catch (e) {}
                if (Array.isArray(got)) for (const b of got) rows.push(b)
                if (Array.isArray(got) && got.length && k + 1 < spec.pages) page(k + 1, start)
                else { request = null; loading = false; finishCoinbase(rows, spec, r) }
            }
            x.open("GET", "https://api.exchange.coinbase.com/products/" + encodeURIComponent(entry.symbol)
                   + "/candles?granularity=" + spec.g
                   + "&start=" + new Date(start * 1000).toISOString() + "&end=" + new Date(end * 1000).toISOString())
            x.setRequestHeader("User-Agent", "Mozilla/5.0")
            x.send()
        }
        page(0, Math.floor(Date.now() / 1000))
    }
    // rows: [time s, low, high, open, close, volume], any order, may repeat.
    function finishCoinbase(rows, spec, r) {
        const seen = {}
        let bars = rows.filter(b => !seen[b[0]] && (seen[b[0]] = true)).sort((a, b) => a[0] - b[0])
        const agg = spec.agg || 1
        if (agg > 1) {
            const out = []
            for (let i = bars.length % agg; i < bars.length; i += agg) {
                const g = bars.slice(i, i + agg)
                out.push([g[0][0], Math.min(...g.map(b => b[1])), Math.max(...g.map(b => b[2])),
                          g[0][3], g[g.length - 1][4], g.reduce((s, b) => s + b[5], 0)])
            }
            bars = out
        }
        if (bars.length < 2) {
            failed = true
            viewFrom = 0; viewCount = 0
            full = { t: [], o: [], h: [], l: [], c: [], v: [], w: [] }
            return
        }
        const t = [], o = [], h = [], l = [], c = [], vo = [], vw = []
        let day = "", pv = 0, vsum = 0
        for (const b of bars) {
            const d = new Date(b[0] * 1000).toISOString().slice(0, 10)
            if (d !== day) { day = d; pv = 0; vsum = 0 }
            pv += (b[1] + b[2] + b[4]) / 3 * b[5]
            vsum += b[5]
            t.push(b[0] * 1000); l.push(b[1]); h.push(b[2]); o.push(b[3]); c.push(b[4]); vo.push(b[5])
            vw.push(vsum > 0 ? pv / vsum : NaN)
        }
        const n = Math.max(Math.min(minBars, c.length), Math.min(c.length, spec.show || bars))
        viewCount = n
        viewFrom = c.length - n
        full = { t: t, o: o, h: h, l: l, c: c, v: vo, w: vw }
    }
    // The price scale: fitted to the bars on screen until the user stretches or
    // moves it on the right edge, then held at `scaleLo`-`scaleHi`.
    property bool autoScale: true
    property real scaleLo: 0
    property real scaleHi: 1

    // ── price levels ─────────────────────────────────────────────────────
    // Horizontal lines the user draws, kept per symbol in a small SQLite
    // database (Qt's LocalStorage, beside the screener's alerts).
    property var levels: []
    property var levelDb: null
    function openLevels() {
        if (levelDb) return true
        try {
            levelDb = LocalStorage.openDatabaseSync("MarketTickerLevels", "1.0", "Market Ticker chart levels", 1000000)
            levelDb.transaction(tx => {
                tx.executeSql("CREATE TABLE IF NOT EXISTS levels (symbol TEXT, price REAL)")
                tx.executeSql("CREATE TABLE IF NOT EXISTS trends (symbol TEXT, t1 REAL, p1 REAL, t2 REAL, p2 REAL)")
            })
            return true
        } catch (e) { levelDb = null; return false }
    }
    function loadLevels() {
        if (!openLevels()) return
        levelDb.readTransaction(tx => {
            const rs = tx.executeSql("SELECT price FROM levels WHERE symbol = ? ORDER BY price DESC", [entry.symbol])
            const out = []
            for (let i = 0; i < rs.rows.length; i++) out.push(rs.rows.item(i).price)
            levels = out
            const tr = tx.executeSql("SELECT t1, p1, t2, p2 FROM trends WHERE symbol = ?", [entry.symbol])
            const lines = []
            for (let i = 0; i < tr.rows.length; i++) {
                const r = tr.rows.item(i)
                lines.push({ t1: r.t1, p1: r.p1, t2: r.t2, p2: r.p2 })
            }
            trends = lines
        })
    }
    property var trends: []                  // [{t1, p1, t2, p2}], times in ms
    property bool drawing: false             // the Line button is on
    property var pending: null               // the first end, {t, p}, once clicked
    onDrawingChanged: pending = null
    function addTrend(a, b) {
        if (!openLevels() || a.t === b.t) return
        levelDb.transaction(tx => tx.executeSql("INSERT INTO trends VALUES (?, ?, ?, ?, ?)",
                                                [entry.symbol, a.t, a.p, b.t, b.p]))
        loadLevels()
    }
    function removeTrend(l) {
        if (!openLevels()) return
        levelDb.transaction(tx => tx.executeSql("DELETE FROM trends WHERE symbol = ? AND t1 = ? AND p1 = ? AND t2 = ? AND p2 = ?",
                                                [entry.symbol, l.t1, l.p1, l.t2, l.p2]))
        loadLevels()
    }
    // The usual time between bars: the median of the last 20 gaps. Not the
    // last gap alone -- Yahoo stamps the newest bar with its latest trade,
    // so that gap is short, and premarket bars with no trade are missing.
    readonly property real barGap: {
        const a = full.t, g = []
        for (let i = Math.max(1, a.length - 20); i < a.length; i++) g.push(a[i] - a[i - 1])
        g.sort((x, y) => x - y)
        return g.length ? g[g.length >> 1] : 60000
    }
    // A time as a bar position (fractional) in the fetched bars, so a line
    // drawn on one bar size lands in the same place on another. Beyond the
    // first or last bar it runs on at the usual bar spacing.
    function barOf(t) {
        const a = full.t, n = a.length
        if (n < 2) return 0
        if (t <= a[0]) return (t - a[0]) / barGap
        if (t >= a[n - 1]) return n - 1 + (t - a[n - 1]) / barGap
        let lo = 0, hi = n - 1
        while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (a[mid] <= t) lo = mid; else hi = mid }
        return lo + (t - a[lo]) / (a[hi] - a[lo])
    }
    function addLevel(price) {
        if (!openLevels() || !(price > 0)) return
        // Rounded to the tick the quote is shown in, so the label is the level.
        const v = Number(ticker.format(f, price).replace(/[^0-9.\-]/g, "")) || price
        levelDb.transaction(tx => tx.executeSql("INSERT INTO levels VALUES (?, ?)", [entry.symbol, v]))
        loadLevels()
    }
    function removeLevel(price) {
        if (!openLevels()) return
        levelDb.transaction(tx => tx.executeSql("DELETE FROM levels WHERE symbol = ? AND price = ?", [entry.symbol, price]))
        loadLevels()
    }
    // A symbol opened from the screener is not on the watchlist, so the
    // tape is not fetching its quote; without it the view has no price and
    // does not know it is a stock (the SEC button, the scanner's news and the
    // dilution line all key off that). Fetched here instead, on the tape's
    // schedule, along with the figures.
    readonly property bool onWatchlist: ticker.symbols.some(s => s.symbol === entry.symbol)
    function refresh() {
        if (!onWatchlist) ticker.fetch(entry.symbol)
        if (!chartOnly) loadSummary()
    }
    // Everything for the symbol in `entry`, from scratch: on opening, and
    // again whenever the entry changes to another symbol.
    property string loadedSymbol: ""
    function reloadAll() {
        if (!entry || !entry.symbol) return
        loadedSymbol = entry.symbol
        if (request) { request.abort(); request = null }
        full = { t: [], o: [], h: [], l: [], c: [], v: [], w: [] }
        viewFrom = 0; viewCount = 0
        autoScale = true; failed = false
        drawing = false; pending = null
        summary = null; summaryFailed = false; summaryRetried = false; cryptoText = ""
        news = []; newsSource = ""; newsFailed = false; newsLoading = false
        dil = null; localValue = null; valueLoading = false
        optIv = null; earnMove = null; optLines = null
        about.expanded = false
        if (entry.tab !== undefined && !chartOnly) tab = entry.tab
        load(); refresh(); loadLevels()
        if (!chartOnly) {
            if (f.type === "EQUITY") loadDilution()
            loadAbout()
            if (tab === 1) loadNews()
        }
        loadOptions()
    }
    onEntryChanged: if (entry && entry.symbol !== loadedSymbol) reloadAll()
    Component.onCompleted: if (loadedSymbol === "") reloadAll()
    Timer {
        interval: detail.ticker.pollSeconds * 1000
        running: true
        repeat: true
        onTriggered: detail.refresh()
    }

    // ── dilution ─────────────────────────────────────────────────────────
    // Shelf registrations and offerings from SEC EDGAR, rated by the
    // scanner's dilution.py (through the screener's bridge). The
    // screener may already hold it; otherwise it is asked for once.
    property var dil: null
    readonly property string kind: f.type || ""
    onKindChanged: { loadOptions(); if (chartOnly) return; if (kind === "EQUITY" && !dil) loadDilution(); loadAbout() }

    // ── options readings ─────────────────────────────────────────────────
    // For a stock or fund: its at-the-money IV and IV rank and the move
    // priced in through its next earnings, in the figures; and, with
    // `chartOptionLines`, its biggest open-interest strikes and max pain on
    // the chart. From Yahoo's chain, delayed (Workspace.qml).
    readonly property bool optionable: kind === "EQUITY" || kind === "ETF"
    property var optIv: null
    property var earnMove: null
    property var optLines: null
    readonly property real earningsAt: {
        const e = summary && summary.calendarEvents && summary.calendarEvents.earnings
        const d = e && e.earningsDate && e.earningsDate[0]
        return d && typeof d.raw === "number" ? d.raw * 1000 : NaN
    }
    onEarningsAtChanged: if (optionable && !chartOnly) { const sym = entry.symbol; ws.earningsMove(sym, earningsAt, m => { if (current(sym)) detail.earnMove = m }) }
    function loadOptions() {
        if (!optionable) return
        const sym = entry.symbol
        if (!chartOnly) ws.ivInfo(sym, x => { if (current(sym)) detail.optIv = x })
        if (Plasmoid.configuration.chartOptionLines) ws.optionLevels(sym, x => { if (current(sym)) detail.optLines = x })
    }
    Connections {
        target: Plasmoid.configuration
        function onChartOptionLinesChanged() { if (Plasmoid.configuration.chartOptionLines) detail.loadOptions(); else detail.optLines = null }
    }
    // A reply still for this card: the card is open and on the same symbol.
    // Since a card opens another symbol in place, a slow reply for the last
    // one must not land on the new one, nor on a card that has closed.
    function current(sym) {
        try { return !!detail && !!detail.entry && detail.entry.symbol === sym } catch (e) { return false }
    }
    function loadDilution() {
        const sym = entry.symbol
        const known = ticker.screener.info[sym]
        if (known && known.dilution) { dil = known.dilution; return }
        if (!/^[A-Z][A-Z0-9.\-]{0,9}$/.test(sym)) return
        ticker.screener.bridgeRun(["dilution", sym], out => { if (current(sym) && out && out[sym]) detail.dil = out[sym] }, 60, true)
    }

    property int tab: 0
    onTabChanged: if (tab === 1 && news.length === 0 && !newsLoading) loadNews()

    // ── the quote figures ────────────────────────────────────────────────
    // Yahoo's quoteSummary, four modules in one call. Every value arrives as
    // {raw, fmt}, and `fmt` is already formatted the way Yahoo's page shows
    // it (5.14T, 0.45%, 2026-11-17), so it is used as given. Refreshed with
    // each poll of the tape, so the figures stay as live as the price.
    property var summary: null
    property bool summaryFailed: false
    property bool summaryRetried: false
    // Yahoo's company profile (assetProfile): empty for an index, currency or crypto pair.
    // A coin's description comes from CoinGecko, looked up once per coin.
    property string cryptoText: ""
    readonly property string aboutText: (summary && summary.assetProfile
                                         ? String(summary.assetProfile.longBusinessSummary || "") : "") || cryptoText
    function loadAbout() {
        const sym = entry.symbol
        if (kind === "CRYPTOCURRENCY") ticker.screener.cryptoAbout(sym, t => { if (current(sym)) detail.cryptoText = t })
    }

    function loadSummary() {
        const sym = entry.symbol
        ticker.withCrumb(c => {
            if (!current(sym)) return
            ticker.yget("https://query2.finance.yahoo.com/v10/finance/quoteSummary/"
                        + encodeURIComponent(sym)
                        + "?modules=summaryDetail,defaultKeyStatistics,financialData,calendarEvents,assetProfile"
                        + "&crumb=" + encodeURIComponent(c), x => {
                if (!current(sym)) return
                if (x.status === 401 && !summaryRetried) {
                    // Crumb expired: fetch a fresh one, once.
                    summaryRetried = true
                    ticker.crumb = ""
                    loadSummary()
                    return
                }
                try {
                    summary = JSON.parse(x.responseText).quoteSummary.result[0]
                    summaryFailed = false
                    summaryRetried = false
                } catch (e) {
                    summaryFailed = true
                }
            })
        })
    }

    // `fmt` of one field, or "" when Yahoo has none for this symbol.
    function v(module, key, full) {
        const m = summary && summary[module]
        const f = m && m[key]
        if (!f || typeof f !== "object" || f.raw === undefined) return ""
        return (full && f.longFmt) || f.fmt || String(f.raw)
    }
    function pair(a, b, sep) { return a && b ? a + (sep || " - ") + b : "" }

    // The figures, in Yahoo's order, grouped. Rows with no value are dropped,
    // so an index shows a short list and a stock the full one.
    readonly property var sections: {
        const sd = "summaryDetail", ks = "defaultKeyStatistics", fd = "financialData"
        const ce = summary && summary.calendarEvents && summary.calendarEvents.earnings
        const earn = ce && ce.earningsDate ? ce.earningsDate.map(d => d.fmt).join(" - ")
                   + (ce.isEarningsDateEstimate ? " (est.)" : "") : ""
        const rec = summary && summary[fd] && summary[fd].recommendationKey
        const out = [
            { title: i18n("Quote"), rows: [
                [i18n("Previous Close"), v(sd, "previousClose")],
                [i18n("Open"), v(sd, "open")],
                [i18n("Bid"), pair(v(sd, "bid"), v(sd, "bidSize"), " x ")],
                [i18n("Ask"), pair(v(sd, "ask"), v(sd, "askSize"), " x ")],
                [i18n("Day's Range"), pair(v(sd, "dayLow"), v(sd, "dayHigh"))],
                [i18n("52 Week Range"), pair(v(sd, "fiftyTwoWeekLow"), v(sd, "fiftyTwoWeekHigh"))],
                [i18n("Volume"), v(sd, "volume", true)],
                [i18n("Avg. Volume"), v(sd, "averageVolume", true)],
                [i18n("Volume (24h)"), v(sd, "volume24Hr")],
                [i18n("Market Cap"), v(sd, "marketCap")],
                [i18n("Beta (5Y Monthly)"), v(sd, "beta")],
                [i18n("Beta (3Y)"), v(ks, "beta3Year")],
                [i18n("PE Ratio (TTM)"), v(sd, "trailingPE")],
                [i18n("EPS (TTM)"), v(ks, "trailingEps")],
                [i18n("Earnings Date"), earn],
                [i18n("Earnings Move (priced in)"), earnMove ? "±$" + earnMove.dollars.toFixed(2) + " (" + earnMove.pct.toFixed(1) + "%) "
                                                    + i18n("by %1", Qt.formatDate(new Date(earnMove.expiry), "d MMM")) : ""],
                [i18n("Implied Volatility"), optIv ? (optIv.iv * 100).toFixed(1) + "%" : ""],
                [i18n("IV Rank (1 year)"), !optIv ? "" : isFinite(optIv.rank) ? String(Math.round(optIv.rank))
                                           : i18np("after 20 days (1 recorded)", "after 20 days (%1 recorded)", optIv.days)],
                [i18n("Forward Dividend & Yield"), pair(v(sd, "dividendRate"), v(sd, "dividendYield") && "(" + v(sd, "dividendYield") + ")", " ")],
                [i18n("Ex-Dividend Date"), v(sd, "exDividendDate")],
                [i18n("Yield"), v(sd, "yield")],
                [i18n("Net Assets"), v(sd, "totalAssets")],
                [i18n("NAV"), v(sd, "navPrice")],
                [i18n("YTD Return"), v(ks, "ytdReturn")],
                [i18n("1y Target Est"), v(fd, "targetMeanPrice")],
                [i18n("Circulating Supply"), v(sd, "circulatingSupply")],
                [i18n("Max Supply"), v(sd, "maxSupply")]
            ]},
            { title: i18n("Shares and short interest"), rows: [
                [i18n("Float"), v(ks, "floatShares")],
                [i18n("Shares Outstanding"), v(ks, "sharesOutstanding")],
                [i18n("Short % of Float"), v(ks, "shortPercentOfFloat")],
                [i18n("Short Ratio (days)"), v(ks, "shortRatio")],
                [i18n("Shares Short"), v(ks, "sharesShort")],
                [i18n("Short Interest Date"), v(ks, "dateShortInterest")],
                [i18n("Held by Insiders"), v(ks, "heldPercentInsiders")],
                [i18n("Held by Institutions"), v(ks, "heldPercentInstitutions")]
            ]},
            { title: i18n("Trend and valuation"), rows: [
                [i18n("50-Day Average"), v(sd, "fiftyDayAverage")],
                [i18n("200-Day Average"), v(sd, "twoHundredDayAverage")],
                [i18n("52-Week Change"), v(ks, "52WeekChange")],
                [i18n("All-Time High"), v(sd, "allTimeHigh")],
                [i18n("All-Time Low"), v(sd, "allTimeLow")],
                [i18n("Forward P/E"), v(sd, "forwardPE")],
                [i18n("Price/Book"), v(ks, "priceToBook")],
                [i18n("Analyst Rating"), rec ? rec.replace(/_/g, " ") + (v(fd, "recommendationMean") ? " (" + v(fd, "recommendationMean") + ")" : "") : ""],
                [i18n("Analysts"), v(fd, "numberOfAnalystOpinions")],
                [i18n("Target Range"), pair(v(fd, "targetLowPrice"), v(fd, "targetHighPrice"))]
            ]}
        ]
        return out.map(sec => ({ title: sec.title, rows: sec.rows.filter(r => r[1]) }))
                  .filter(sec => sec.rows.length > 0)
    }

    // ── the news ─────────────────────────────────────────────────────────
    // Two sources, best first:
    //
    //   Stocks and ETFs -- the scanner's `news.ticker()`, through the
    //     screener's bridge (`tickernews`): Finviz's per-ticker headlines,
    //     ranked newest day first and the company's own news first within a
    //     day. The symbol is checked against a strict pattern before it
    //     reaches the shell.
    //   Everything else, or if the scanner is missing or fails -- Google
    //     News search RSS, newest first. Yahoo's own per-symbol feed was
    //     tried first (2026-10-22) and is too loose for big names: NVDA's
    //     came back mostly as other companies' earnings-call summaries.
    //
    // For Google the query is the company name plus the ticker for a stock,
    // the ticker for an ETF (fund names are long and generic), and the name
    // for anything else ("S&P 500", "Bitcoin").
    property var news: []
    property string newsSource: ""
    property bool newsLoading: false
    property bool newsFailed: false

    function loadNews() {
        newsLoading = true
        newsFailed = false
        const scanner = (kind === "EQUITY" || kind === "ETF")
                        && /^[A-Za-z0-9.\-]{1,12}$/.test(entry.symbol)
        if (!scanner) { loadGoogleNews(); return }
        const sym = entry.symbol
        ticker.screener.bridgeRun(["tickernews", sym], out => {
            if (!detail.current(sym)) return
            let rows = (Array.isArray(out) ? out : []).filter(n => n.title && n.link)
            // The scanner flags whether each headline is about the company.
            // For a big name the rest is mostly other companies' coverage
            // that merely mentions it, so it is shown only to fill out a
            // short list.
            const own = rows.filter(n => n.company)
            if (own.length >= 5) rows = own
            if (rows.length === 0) { detail.loadGoogleNews(); return }
            detail.news = detail.withMine(rows).slice(0, 20)
            detail.newsSource = "Finviz"
            detail.newsLoading = false
            detail.newsFailed = false
        }, 30, true)
    }
    // Settings → Data: "en-US", "de-DE", "en-GB"...
    function googleEdition() {
        const loc = String(Plasmoid.configuration.newsLocale || "en-US").trim()
        const lang = loc.split("-")[0] || "en", country = (loc.split("-")[1] || "US").toUpperCase()
        return "&hl=" + encodeURIComponent(loc) + "&gl=" + country + "&ceid=" + country + ":" + lang
    }
    function newsQuery() {
        const name = String(m.longName || m.shortName || entry.name || entry.symbol)
            .replace(/,?\s+(Inc\.?|Incorporated|Corporation|Corp\.?|Company|Co\.?|Ltd\.?|Limited|plc|Holdings?|Group|S\.A\.|N\.V\.|USD)$/i, "")
            .replace(/,?\s+(Inc\.?|Corporation|Corp\.?|Ltd\.?|plc)$/i, "")
        switch (kind) {
        case "EQUITY": return '"' + name + '" OR ' + entry.symbol
        case "ETF":    return entry.symbol
        default:       return '"' + String(entry.name || name) + '"'
        }
    }
    function decode(t) {
        return String(t).replace(/<!\[CDATA\[|\]\]>/g, "")
            .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(n))
            .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCharCode(parseInt(n, 16)))
            .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">").replace(/&amp;/g, "&")
    }
    function loadGoogleNews() {
        newsLoading = true
        newsFailed = false
        const sym = entry.symbol
        ticker.yget("https://news.google.com/rss/search?q="
                    + encodeURIComponent(newsQuery() + " when:7d")
                    + googleEdition(), x => {
            if (!current(sym)) return
            newsLoading = false
            const items = String(x.responseText || "").split("<item>").slice(1).map(it => {
                const get = tag => { const r = it.match(new RegExp("<" + tag + "[^>]*>([\\s\\S]*?)</" + tag + ">")); return r ? decode(r[1]).trim() : "" }
                const source = get("source")
                let title = get("title")
                // Google appends " - Source" to every title; the source has its own line.
                if (source && title.endsWith(" - " + source)) title = title.slice(0, -(source.length + 3))
                return { title: title, link: get("link"), source: source, time: Date.parse(get("pubDate")) }
            }).filter(n => n.title && n.link && !isNaN(n.time))
            items.sort((a, b) => b.time - a.time)
            news = withMine(items).slice(0, 20)
            newsSource = "Google News"
            newsFailed = news.length === 0
        })
    }
    // Your own news sources' headlines naming this symbol, merged in by time.
    function withMine(rows) {
        const mine = ticker.screener.customNews.filter(it => NewsFeeds.matches(it, entry.symbol))
            .map(it => ({ title: it.title, link: it.url, source: it.source, time: it.time, company: true }))
        if (!mine.length) return rows
        const seen = {}
        return mine.concat(rows).sort((a, b) => b.time - a.time)
            .filter(n => { const k = n.title.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 60); return !seen[k] && (seen[k] = true) })
    }
    function ago(ms) {
        const mins = Math.round((Date.now() - ms) / 60000)
        if (mins < 60) return i18n("%1m ago", Math.max(1, mins))
        if (mins < 60 * 24) return i18n("%1h ago", Math.round(mins / 60))
        return i18n("%1d ago", Math.round(mins / 1440))
    }
    // A source's colour, the same as the News tab's, for its initial.
    function sourceColor(name) {
        let h = 0
        for (const c of String(name)) h = (h * 31 + c.charCodeAt(0)) % 360
        return Qt.hsla(h / 360, 0.45, 0.45, 1)
    }

    // Over one day the line is measured against yesterday's close, as on
    // the tape; over longer ranges, against where the range began.
    // Intraday bar sizes span several days, so they have no baseline.
    readonly property real refLevel: intraday ? NaN
                                     : rangeIndex === 0 && typeof m.chartPreviousClose === "number"
                                     ? m.chartPreviousClose
                                     : (closes.length ? closes[0] : NaN)
    readonly property real rangeChange: closes.length ? closes[closes.length - 1] - refLevel : 0
    readonly property color lineColour: closes.length === 0 ? Kirigami.Theme.disabledTextColor
                                      : rangeChange >= 0 ? Kirigami.Theme.positiveTextColor
                                                         : Kirigami.Theme.negativeTextColor

    function stamp(ms) {
        const d = new Date(ms)
        switch (ranges[rangeIndex].key) {
        case "1D": case "1m": case "5m": case "15m": return Qt.formatTime(d, "hh:mm")
        case "5D": case "30m": case "1h": return Qt.formatDateTime(d, "ddd hh:mm")
        case "1Y": return Qt.formatDate(d, "MMM d, yyyy")
        case "5Y": return Qt.formatDate(d, "MMM yyyy")
        default:   return Qt.formatDate(d, "MMM d")
        }
    }
    function num(v) {
        return typeof v === "number" ? ticker.format(f, v) : "--"
    }

    // ── title row ───────────────────────────────────────────────────────
    RowLayout {
        visible: !detail.chartOnly
        Layout.fillWidth: true
        PlasmaComponents3.ToolButton {
            visible: !detail.inWindow
            icon.name: "go-previous"
            onClicked: detail.back()
            PlasmaComponents3.ToolTip { text: i18n("Back") }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaExtras.Heading {
                    Layout.fillWidth: !themeTag.visible && !sectorTag.visible
                    Layout.maximumWidth: implicitWidth
                    Layout.minimumWidth: 0
                    level: 3
                    // Styled text: the label and symbol are escaped, so markup
                    // in either shows as typed rather than rendering.
                    text: detail.ticker.esc(detail.entry.label || detail.entry.symbol)
                          + "  <font size='-1' color='" + detail.ticker.hex(Kirigami.Theme.disabledTextColor) + "'>"
                          + detail.ticker.esc(detail.entry.symbol) + "</font>"
                    textFormat: Text.StyledText
                    elide: Text.ElideRight
                }
                // The theme, as on the screener: the glyph coloured by how hot
                // the story is, and its name and state in words. Only for
                // symbols the screener has looked up (it needs the industry).
                RowLayout {
                    id: themeTag
                    readonly property var tf: detail.ticker.screener.themeFields(detail.entry.symbol)
                    readonly property string st: tf.themeHeat ? tf.themeHeat.status : "quiet"
                    readonly property color col: Themes.colour(st, (tf.theme && tf.theme.ramp) || Plasmoid.configuration.themeRamp)
                    visible: !!tf.theme
                    spacing: 2
                    ThemeGlyph {
                        theme: themeTag.tf.theme || null
                        status: themeTag.st
                        ramp: Plasmoid.configuration.themeRamp
                        icons: { try { return JSON.parse(Plasmoid.configuration.themeIcons || "{}") } catch (e) { return ({}) } }
                    }
                    PlasmaComponents3.Label {
                        text: themeTag.tf.theme ? themeTag.tf.theme.name + " · " + themeTag.st + " · " + i18n("beta") : ""
                        font: Kirigami.Theme.smallFont
                        color: themeTag.st === "quiet" ? Kirigami.Theme.disabledTextColor : themeTag.col
                    }
                    HoverHandler { id: themeHover }
                    PlasmaComponents3.ToolTip {
                        visible: themeHover.hovered
                        text: themeTag.tf.theme && themeTag.tf.themeHeat
                              ? Themes.explain(themeTag.tf.theme.name, themeTag.tf.themeHeat, detail.ticker.screener.themeTune) : ""
                    }
                }
                // The sector, heat-coloured the same way, with today's industry mix.
                RowLayout {
                    id: sectorTag
                    readonly property var sf: detail.ticker.screener.sectorFields(detail.entry.symbol)
                    readonly property string st: sf.sectorHeat ? sf.sectorHeat.status : "quiet"
                    readonly property color col: Themes.colour(st, (sf.sector && sf.sector.ramp) || Plasmoid.configuration.themeRamp)
                    visible: !!sf.sector
                    spacing: 2
                    ThemeGlyph {
                        theme: sectorTag.sf.sector || null
                        status: sectorTag.st
                        ramp: Plasmoid.configuration.themeRamp
                        icons: { try { return JSON.parse(Plasmoid.configuration.themeIcons || "{}") } catch (e) { return ({}) } }
                    }
                    PlasmaComponents3.Label {
                        text: sectorTag.sf.sector ? sectorTag.sf.sector.name + " · " + sectorTag.st : ""
                        font: Kirigami.Theme.smallFont
                        color: sectorTag.st === "quiet" ? Kirigami.Theme.disabledTextColor : sectorTag.col
                    }
                    HoverHandler { id: sectorHover }
                    PlasmaComponents3.ToolTip {
                        visible: sectorHover.hovered
                        text: sectorTag.sf.sector && sectorTag.sf.sectorHeat
                              ? Themes.explain(sectorTag.sf.sector.name, sectorTag.sf.sectorHeat, detail.ticker.screener.themeTune)
                                + (sectorTag.sf.sectorBreakdown ? "\n" + i18n("Today: %1", sectorTag.sf.sectorBreakdown) : "")
                              : ""
                    }
                }
                Item { Layout.fillWidth: true; visible: themeTag.visible || sectorTag.visible }
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: [detail.m.longName || detail.entry.name, detail.m.fullExchangeName, detail.m.currency]
                      .filter(x => x).join(" · ")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                elide: Text.ElideRight
            }
        }
        // Opened from the screener, a symbol may not be on the watchlist yet.
        // Added unstarred: watchlist only, as from settings.
        PlasmaComponents3.ToolButton {
            visible: !detail.ticker.symbols.some(s => s.symbol === detail.entry.symbol)
            icon.name: "list-add"
            text: i18n("Watchlist")
            onClicked: {
                const list = detail.ticker.allSymbols.slice()     // keeps the Themes entry
                list.push({ symbol: detail.entry.symbol, label: detail.entry.symbol.replace(/^\^/, ""),
                            name: detail.m.shortName || detail.m.longName || detail.entry.name || detail.entry.symbol,
                            star: false })
                Plasmoid.configuration.symbols = JSON.stringify(list)
            }
            PlasmaComponents3.ToolTip { text: i18n("Add to the watchlist") }
        }
        // On the watchlist: on the tape or not, and off the list again.
        readonly property var listed: detail.ticker.symbols.find(s => s.symbol === detail.entry.symbol) || null
        PlasmaComponents3.ToolButton {
            visible: !!parent.listed
            icon.name: parent.listed && parent.listed.star ? "starred-symbolic" : "non-starred-symbolic"
            icon.color: parent.listed && parent.listed.star ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
            onClicked: detail.ticker.setStar(detail.entry.symbol, !parent.listed.star)
            PlasmaComponents3.ToolTip { text: parent.parent.listed && parent.parent.listed.star ? i18n("On the tape: click to take it off (it stays on the watchlist)") : i18n("Put it on the tape") }
        }
        PlasmaComponents3.ToolButton {
            visible: !!parent.listed
            icon.name: "list-remove"
            onClicked: detail.ticker.removeSymbol(detail.entry.symbol)
            PlasmaComponents3.ToolTip { text: i18n("Remove from the watchlist") }
        }
        // For a stock: its filings on BamSEC -- shelf registrations (S-3),
        // offering prospectuses (424B) and the rest. A ticker search opens
        // straight on the company when the ticker is unique, else on the list
        // of matches. Anything else -- index, currency, crypto -- opens on
        // Yahoo's quote page (Yahoo lists coins such as XMR-USD that Coinbase does not).
        PlasmaComponents3.ToolButton {
            readonly property bool sec: detail.kind === "EQUITY"
            icon.name: "internet-web-browser"
            onClicked: Qt.openUrlExternally(sec
                ? "https://www.bamsec.com/search?q=" + encodeURIComponent(detail.entry.symbol)
                : "https://finance.yahoo.com/quote/" + encodeURIComponent(detail.entry.symbol))
            PlasmaComponents3.ToolTip {
                text: parent.sec ? i18n("BamSEC filings: S-3 shelves, 424B offerings and the rest")
                                 : i18n("Open on Yahoo Finance")
            }
        }
    }

    // ── another symbol ──────────────────────────────────────────────────
    // Type a symbol to open it here, or pick one of the recent tickers. The
    // card shown is the active ticker, which unpinned chart windows follow.
    RowLayout {
        visible: !detail.chartOnly
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents3.TextField {
            id: goField
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            placeholderText: i18n("Symbol…")
            onAccepted: {
                const typed = text
                text = ""
                detail.ws.resolve(typed, e => detail.go(e))
            }
            PlasmaComponents3.ToolTip { text: i18n("Type a symbol and press Enter to open it here: AIRE, ^GSPC, BTC") }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: detail.ws.recent.filter(r => r.symbol !== detail.entry.symbol)
                PlasmaComponents3.ToolButton {
                    required property var modelData
                    text: String(modelData.label || modelData.symbol).replace(/^\^/, "")
                    font: Kirigami.Theme.smallFont
                    onClicked: detail.go({ symbol: modelData.symbol, label: modelData.label || modelData.symbol,
                                           name: modelData.name || modelData.symbol, star: false })
                    PlasmaComponents3.ToolTip { text: parent.modelData.name || parent.modelData.symbol }
                }
            }
        }
    }

    // ── price and change ────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing
        // In a chart window the title row is hidden: the symbol leads here.
        PlasmaComponents3.Label {
            visible: detail.chartOnly
            textFormat: Text.PlainText
            text: String(detail.entry.label || detail.entry.symbol)
            font.bold: true
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
        }
        PlasmaComponents3.Label {
            text: detail.known ? detail.num(detail.f.value) : "--"
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.8
            font.bold: true
            font.family: Kirigami.Theme.fixedWidthFont.family
        }
        // Opened from a screen in another currency: the price in it too.
        PlasmaComponents3.Label {
            readonly property string cur: detail.entry.currency || "USD"
            readonly property real k: cur === "USD" ? NaN : detail.ticker.screener.rate(cur)
            readonly property var def: Screens.currencies.find(c => c.key === cur) || null
            visible: detail.known && isFinite(k) && !!def && (detail.f.currency || "USD") === "USD"
            text: visible ? "≈ " + def.sym + (detail.f.value * k >= 1 ? (detail.f.value * k).toFixed(2)
                                                 : (detail.f.value * k).toPrecision(4)) : ""
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.2
            font.family: Kirigami.Theme.fixedWidthFont.family
            opacity: 0.8
        }
        PlasmaComponents3.Label {
            visible: detail.known
            readonly property bool up: detail.f.pct >= 0
            text: (up ? "▲ +" : "▼ ") + (detail.f.pct || 0).toFixed(2) + "% "
                  + detail.ticker.period(detail.f).toLowerCase()
                  + (detail.f.stale ? " · " + i18n("stale") : "")
            color: detail.f.stale ? Kirigami.Theme.disabledTextColor
                 : up ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
            font.family: Kirigami.Theme.fixedWidthFont.family
        }
        Item { Layout.fillWidth: true }
        // Change over the range shown, when it is longer than a day.
        PlasmaComponents3.Label {
            visible: detail.rangeIndex > 0 && !detail.intraday && detail.closes.length > 0
            text: i18n("%1: %2%", detail.ranges[detail.rangeIndex].key,
                       ((detail.rangeChange >= 0 ? "+" : "")
                        + (detail.rangeChange / detail.refLevel * 100).toFixed(2)))
            color: detail.lineColour
            font.family: Kirigami.Theme.fixedWidthFont.family
        }
    }

    // ── dilution line ───────────────────────────────────────────────────
    // "Dilution EXTREME · S-3 filed 2026-10-13 · last offering 424B3
    // 2026-08-27 (56 days ago) · serial issuer". Clicking opens EDGAR.
    PlasmaComponents3.Label {
        id: dilLine
        visible: !detail.chartOnly && detail.dil !== null && detail.dil.risk !== "UNKNOWN"
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        wrapMode: Text.WordWrap
        textFormat: Text.StyledText
        font: Kirigami.Theme.smallFont
        readonly property var d: detail.dil || ({})
        readonly property color riskColour: d.risk === "EXTREME" ? Kirigami.Theme.negativeTextColor
                                          : d.risk === "HIGH" || d.risk === "MEDIUM" ? Kirigami.Theme.neutralTextColor
                                          : Kirigami.Theme.positiveTextColor
        text: {
            if (!visible) return ""
            const sh = (d.shelves || [])[0], of = (d.offerings || [])[0]
            // Styled text: the scanner's words are escaped before going in.
            const e = t => detail.ticker.esc(t)
            const parts = [i18n("Dilution") + " <b><font color='" + detail.ticker.hex(riskColour) + "'>" + e(d.risk) + "</font></b>"]
            parts.push(sh ? e(i18n("%1 filed %2", sh.form, sh.date)) : i18n("no shelf in 12 months"))
            if (of) parts.push(e(i18n("last offering %1 %2", of.form, of.date))
                               + (d.daysSinceOffering !== null && d.daysSinceOffering !== undefined
                                  ? " " + e(i18n("(%1 days ago)", d.daysSinceOffering)) : ""))
            const extra = (d.flags || []).filter(f => !f.startsWith("live shelf") && !f.startsWith("sold stock")).map(e)
            return parts.concat(extra).join(" · ")
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Qt.openUrlExternally("https://www.bamsec.com/search?q=" + encodeURIComponent(detail.entry.symbol))
        }
    }

    // ── tabs ────────────────────────────────────────────────────────────
    PlasmaComponents3.TabBar {
        visible: !detail.chartOnly
        Layout.fillWidth: true
        currentIndex: detail.tab
        onCurrentIndexChanged: detail.tab = currentIndex
        PlasmaComponents3.TabButton { text: i18n("Overview") }
        PlasmaComponents3.TabButton { text: i18n("News") }
        PlasmaComponents3.TabButton { text: i18n("Options"); enabled: detail.optionable }
        PlasmaComponents3.TabButton {
            readonly property int n: detail.ws.notes.filter(x => x.symbol === detail.entry.symbol).length
            text: n ? i18n("Notes (%1)", n) : i18n("Notes")
        }
    }
    Loader {
        active: detail.tab === 2 && detail.optionable && !detail.chartOnly
        visible: active
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        sourceComponent: OptionsView {
            ticker: detail.ticker
            symbol: detail.entry.symbol
            price: detail.f.value > 0 ? detail.f.value : NaN
            earningsAt: detail.earningsAt
        }
    }
    Loader {
        active: detail.tab === 3 && !detail.chartOnly
        visible: active
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        sourceComponent: NotesView { ws: detail.ws; symbol: detail.entry.symbol }
    }

    // ── about the company ───────────────────────────────────────────────
    // Yahoo's business summary: its first sentence, cut at `aboutChars`
    // (Settings → Workspace; 0 = two lines); a click shows the rest.
    readonly property string aboutShort: {
        const t = aboutText, n = Plasmoid.configuration.aboutChars
        if (!(n > 0)) return t
        const m = t.match(/^.*?[.!?](?=\s+[A-Z]|$)/)
        const first = m ? m[0] : t
        return first.length <= n ? first : first.slice(0, n).replace(/\s+\S*$/, "") + "…"
    }
    PlasmaComponents3.Label {
        id: about
        visible: !detail.chartOnly && detail.tab === 0 && detail.aboutText.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        textFormat: Text.PlainText
        text: expanded ? detail.aboutText : detail.aboutShort
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.8
        elide: Text.ElideRight
        maximumLineCount: expanded || Plasmoid.configuration.aboutChars > 0 ? 999 : 2
        property bool expanded: false
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: about.expanded = !about.expanded
        }
    }

    // ── range buttons ───────────────────────────────────────────────────
    RowLayout {
        visible: detail.tab === 0 && !detail.inWindow
        Layout.alignment: Qt.AlignHCenter
        spacing: 0
        Repeater {
            model: detail.ranges
            PlasmaComponents3.ToolButton {
                required property var modelData
                required property int index
                visible: !modelData.intraday
                text: modelData.key
                checkable: true
                checked: detail.rangeIndex === index
                onClicked: detail.rangeIndex = index
                PlasmaComponents3.ToolTip { text: parent.modelData.tip }
            }
        }
    }
    RowLayout {
        visible: detail.tab === 0 && !detail.inWindow
        Layout.alignment: Qt.AlignHCenter
        spacing: 0
        PlasmaComponents3.ToolButton {
            text: i18n("Candles")
            icon.name: "office-chart-bar"
            checkable: true
            checked: detail.candles
            onClicked: Plasmoid.configuration.chartCandles = !detail.candles
            PlasmaComponents3.ToolTip { text: i18n("Candlesticks; off draws a line chart") }
        }
        PlasmaComponents3.ToolButton {
            text: detail.pending ? i18n("Click the other end") : i18n("Draw line")
            icon.name: "draw-line"
            checkable: true
            checked: detail.drawing
            onClicked: detail.drawing = !detail.drawing
            PlasmaComponents3.ToolTip { text: i18n("Draw a trend line: click two points. Double-click the chart to add a price level; right-click removes the nearest level or line.") }
        }
        // A chart of its own window, at this bar size, following the active
        // ticker; and TradingView's chart in a window.
        PlasmaComponents3.ToolButton {
            icon.name: "window-new"
            onClicked: detail.ws.openChart("chart", "", detail.ranges[detail.rangeIndex].key)
            PlasmaComponents3.ToolTip { text: i18n("Open this chart in a window of its own. It follows the symbol you open next; pin it to keep this one.") }
        }
        PlasmaComponents3.ToolButton {
            text: i18n("TV")
            icon.name: "office-chart-line-stacked"
            onClicked: detail.ws.openChart("tv", "", detail.ranges[detail.rangeIndex].key)
            PlasmaComponents3.ToolTip { text: i18n("Open TradingView's chart for this symbol in a window, with its own indicators and drawing tools") }
        }
        Kirigami.Separator { Layout.fillHeight: true }
        Repeater {
            model: detail.ranges
            PlasmaComponents3.ToolButton {
                required property var modelData
                required property int index
                visible: !!modelData.intraday
                text: modelData.key
                checkable: true
                checked: detail.rangeIndex === index
                onClicked: detail.rangeIndex = index
                PlasmaComponents3.ToolTip { text: parent.modelData.tip }
            }
        }
    }

    // Overlays: EMAs in their line colours, VWAP and volume. Remembered for
    // every chart.
    RowLayout {
        visible: detail.tab === 0 && !detail.inWindow
        Layout.alignment: Qt.AlignHCenter
        spacing: 0
        PlasmaComponents3.Label { text: i18n("EMA"); opacity: 0.7; font: Kirigami.Theme.smallFont }
        Repeater {
            model: detail.emaLengths
            PlasmaComponents3.ToolButton {
                required property int modelData
                readonly property bool on: detail.emasOn.indexOf(modelData) >= 0
                checkable: true
                checked: on
                onClicked: detail.toggleEma(modelData)
                contentItem: PlasmaComponents3.Label {
                    text: parent.modelData
                    color: parent.on ? detail.emaColours[parent.modelData] : Kirigami.Theme.disabledTextColor
                    font.bold: parent.on
                    horizontalAlignment: Text.AlignHCenter
                }
                PlasmaComponents3.ToolTip {
                    text: detail.fullCount < modelData
                        ? i18n("%1-bar EMA: this range has only %2 bars", modelData, detail.fullCount)
                        : i18n("%1-bar exponential moving average", modelData)
                }
            }
        }
        Kirigami.Separator { Layout.fillHeight: true }
        PlasmaComponents3.ToolButton {
            text: i18n("VWAP")
            checkable: true
            checked: Plasmoid.configuration.chartVwap
            enabled: detail.minuteBars
            onClicked: Plasmoid.configuration.chartVwap = !Plasmoid.configuration.chartVwap
            PlasmaComponents3.ToolTip { text: detail.minuteBars ? i18n("Volume-weighted average price, from each day's first traded bar") : i18n("VWAP needs minute or hour bars") }
        }
        PlasmaComponents3.ToolButton {
            visible: detail.optionable
            text: i18n("OI")
            checkable: true
            checked: Plasmoid.configuration.chartOptionLines
            onClicked: Plasmoid.configuration.chartOptionLines = !Plasmoid.configuration.chartOptionLines
            PlasmaComponents3.ToolTip { text: i18n("Options: the three strikes with the most open interest and the max-pain strike, for the nearest expiry a week or more out (Yahoo, delayed)") }
        }
        PlasmaComponents3.ToolButton {
            text: i18n("Volume")
            checkable: true
            checked: Plasmoid.configuration.chartVolume
            onClicked: Plasmoid.configuration.chartVolume = !Plasmoid.configuration.chartVolume
            PlasmaComponents3.ToolTip { text: i18n("Show volume bars under the chart") }
        }
    }

    // ── the chart ───────────────────────────────────────────────────────
    Item {
        visible: detail.tab === 0 && !detail.inWindow
        Layout.fillWidth: true
        Layout.fillHeight: detail.chartOnly
        Layout.preferredHeight: Kirigami.Units.gridUnit * 16

        Canvas {
            id: chart
            anchors.fill: parent
            // Room on the right for the price labels and below for dates.
            readonly property real plotRight: width - Kirigami.Units.gridUnit * 3.5
            readonly property real plotBottom: height - Kirigami.Units.gridUnit * 1.2
            readonly property real plotTop: Kirigami.Units.smallSpacing
            readonly property var p: detail.closes
            readonly property bool hasVol: detail.showVolume && detail.vols.some(v => v > 0)
            // The bottom fifth of the plot is the volume strip, when there is
            // volume to show.
            readonly property real priceBottom: hasVol ? plotTop + (plotBottom - plotTop) * 0.8 : plotBottom
            // Levels outside the bars' range are not stretched into view;
            // the scale follows the price.
            readonly property real fitLo: !p.length ? 0
                : Math.min(...(detail.candles ? detail.lows : p), isNaN(detail.refLevel) ? Infinity : detail.refLevel)
            readonly property real fitHi: !p.length ? 1
                : Math.max(...(detail.candles ? detail.highs : p), isNaN(detail.refLevel) ? -Infinity : detail.refLevel)
            readonly property real lo: detail.autoScale ? fitLo : detail.scaleLo
            readonly property real hi: detail.autoScale ? fitHi : detail.scaleHi
            // The price ladder: about six evenly spaced, round prices.
            readonly property var ticks: {
                const span = hi - lo
                if (!(span > 0)) return []
                const raw = span / 6, mag = Math.pow(10, Math.floor(Math.log10(raw)))
                const step = [1, 2, 2.5, 5, 10].map(k => k * mag).find(x => x >= raw)
                const out = []
                for (let v = Math.ceil(lo / step) * step; v <= hi + step * 1e-9; v += step) out.push(v)
                return out
            }
            // Where a trend line's end sits on screen.
            function tx(t) { return slot * (detail.barOf(t) - detail.viewFrom + 0.5) }
            function py(v) { return plotTop + (priceBottom - plotTop) * (1 - (v - lo) / ((hi - lo) || 1)) }
            function priceAt(y) { return lo + (1 - (y - plotTop) / ((priceBottom - plotTop) || 1)) * (hi - lo) }
            // Each bar has a slot across the plot, candle or line point alike,
            // so zooming and dragging move both the same way. The slots are
            // the window's, so past the newest bar they are empty space.
            readonly property real slot: plotRight / Math.max(1, detail.viewCount)
            function px(i) { return slot * (i + 0.5) }
            function barAt(x) { return Math.floor(x / slot) }

            onPChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            Connections {
                target: detail
                function onLevelsChanged() { chart.requestPaint() }
                function onTrendsChanged() { chart.requestPaint() }
                function onPendingChanged() { chart.requestPaint() }
                function onAutoScaleChanged() { chart.requestPaint() }
                function onScaleLoChanged() { chart.requestPaint() }
                function onScaleHiChanged() { chart.requestPaint() }
                function onCandlesChanged() { chart.requestPaint() }
                function onEmasChanged() { chart.requestPaint() }
                function onShowVwapChanged() { chart.requestPaint() }
                function onShowVolumeChanged() { chart.requestPaint() }
                function onOptLinesChanged() { chart.requestPaint() }
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                if (p.length < 2) return
                const line = detail.ticker.hex(detail.lineColour)
                const up = detail.ticker.hex(Kirigami.Theme.positiveTextColor)
                const down = detail.ticker.hex(Kirigami.Theme.negativeTextColor)

                // Price ladder: faint gridlines at the ticks.
                ctx.strokeStyle = detail.ticker.hex(Kirigami.Theme.disabledTextColor)
                ctx.globalAlpha = 0.25
                ctx.lineWidth = 1
                for (const tv of ticks) {
                    const yg = Math.round(py(tv)) + 0.5
                    if (yg < plotTop || yg > priceBottom) continue
                    ctx.beginPath(); ctx.moveTo(0, yg); ctx.lineTo(plotRight, yg); ctx.stroke()
                }
                ctx.globalAlpha = 1
                // Volume, below the price area -- before the clip, which would
                // otherwise cut it away.
                const w = Math.max(1, Math.min(slot * 0.7, Kirigami.Units.gridUnit))
                if (hasVol) {
                    const vmax = Math.max(...detail.vols) || 1
                    for (let i = 0; i < p.length; i++) {
                        const hv = (plotBottom - priceBottom - 2) * detail.vols[i] / vmax
                        ctx.fillStyle = detail.closes[i] >= detail.opens[i] ? up : down
                        ctx.globalAlpha = 0.45
                        ctx.fillRect(px(i) - w / 2, plotBottom - hv, w, hv)
                    }
                    ctx.globalAlpha = 1
                }
                // Everything priced is kept inside the price area, so a
                // stretched scale does not draw over the volume or the labels.
                ctx.save()
                ctx.beginPath(); ctx.rect(0, plotTop, plotRight, priceBottom - plotTop); ctx.clip()

                // Levels first, so the bars draw over them.
                ctx.strokeStyle = detail.ticker.hex(Kirigami.Theme.neutralTextColor)
                ctx.lineWidth = 1
                for (const lv of detail.levels) {
                    if (lv < lo || lv > hi) continue
                    const yl = Math.round(py(lv)) + 0.5
                    ctx.beginPath(); ctx.moveTo(0, yl); ctx.lineTo(plotRight, yl); ctx.stroke()
                }

                // Options: open-interest strikes and max pain, dash-dotted.
                if (detail.optLines) {
                    ctx.strokeStyle = "#a78bfa"
                    ctx.lineWidth = 1
                    ctx.setLineDash([6, 3, 1, 3])
                    for (const k of detail.optLines.levels.map(x => x.strike).concat(isFinite(detail.optLines.pain) ? [detail.optLines.pain] : [])) {
                        if (k < lo || k > hi) continue
                        const yk = Math.round(py(k)) + 0.5
                        ctx.beginPath(); ctx.moveTo(0, yk); ctx.lineTo(plotRight, yk); ctx.stroke()
                    }
                    ctx.setLineDash([])
                }

                // Baseline, dashed: previous close on 1D, range start otherwise.
                if (!isNaN(detail.refLevel)) {
                    ctx.strokeStyle = detail.ticker.hex(Kirigami.Theme.disabledTextColor)
                    ctx.lineWidth = 1
                    ctx.setLineDash([3, 4])
                    ctx.beginPath()
                    const yb = Math.round(py(detail.refLevel)) + 0.5
                    ctx.moveTo(0, yb)
                    ctx.lineTo(plotRight, yb)
                    ctx.stroke()
                    ctx.setLineDash([])
                }

                if (detail.candles) {
                    for (let i = 0; i < p.length; i++) {
                        const o = detail.opens[i], c = detail.closes[i]
                        const col = c >= o ? up : down
                        const x = Math.round(px(i)) + 0.5
                        ctx.strokeStyle = col
                        ctx.beginPath(); ctx.moveTo(x, py(detail.highs[i])); ctx.lineTo(x, py(detail.lows[i])); ctx.stroke()
                        const yt = py(Math.max(o, c)), yb = py(Math.min(o, c))
                        ctx.fillStyle = col
                        ctx.fillRect(x - w / 2, yt, w, Math.max(1, yb - yt))
                    }
                } else {
                    // Soft fill under the line.
                    const grad = ctx.createLinearGradient(0, plotTop, 0, priceBottom)
                    grad.addColorStop(0, Qt.rgba(detail.lineColour.r, detail.lineColour.g, detail.lineColour.b, 0.25))
                    grad.addColorStop(1, Qt.rgba(detail.lineColour.r, detail.lineColour.g, detail.lineColour.b, 0))
                    ctx.fillStyle = grad
                    ctx.beginPath()
                    ctx.moveTo(px(0), priceBottom)
                    for (let i = 0; i < p.length; i++) ctx.lineTo(px(i), py(p[i]))
                    ctx.lineTo(px(p.length - 1), priceBottom)
                    ctx.closePath()
                    ctx.fill()

                    ctx.strokeStyle = line
                    ctx.lineWidth = 1.5
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(px(0), py(p[0]))
                    for (let i = 1; i < p.length; i++) ctx.lineTo(px(i), py(p[i]))
                    ctx.stroke()
                }

                // EMAs, over the bars.
                ctx.lineWidth = 1.25
                for (const n of detail.emasOn) {
                    const e = detail.emas[n] || []
                    ctx.strokeStyle = detail.emaColours[n]
                    ctx.beginPath()
                    let pen = false
                    for (let i = 0; i < e.length; i++) {
                        if (!(e[i] > 0)) { pen = false; continue }
                        if (pen) ctx.lineTo(px(i), py(e[i])); else ctx.moveTo(px(i), py(e[i]))
                        pen = true
                    }
                    ctx.stroke()
                }

                // VWAP, on minute and hour bars, where there has been volume
                // to weight it.
                if (detail.showVwap) {
                    ctx.strokeStyle = detail.ticker.hex(Kirigami.Theme.highlightColor)
                    ctx.lineWidth = 1.25
                    ctx.beginPath()
                    let pen = false
                    for (let i = 0; i < p.length; i++) {
                        const v = detail.vwap[i]
                        if (!(v > 0)) { pen = false; continue }
                        // A new day restarts the line rather than joining it.
                        if (pen && i > 0 && new Date(detail.times[i]).getDate() !== new Date(detail.times[i - 1]).getDate()) pen = false
                        if (pen) ctx.lineTo(px(i), py(v)); else ctx.moveTo(px(i), py(v))
                        pen = true
                    }
                    ctx.stroke()
                }

                // Trend lines, over the bars; the one being drawn runs from
                // its first end to the pointer.
                ctx.strokeStyle = detail.ticker.hex(Kirigami.Theme.neutralTextColor)
                ctx.lineWidth = 1.5
                for (const l of detail.trends) {
                    ctx.beginPath(); ctx.moveTo(tx(l.t1), py(l.p1)); ctx.lineTo(tx(l.t2), py(l.p2)); ctx.stroke()
                }
                if (detail.pending && hover.containsMouse) {
                    ctx.setLineDash([4, 3])
                    ctx.beginPath(); ctx.moveTo(tx(detail.pending.t), py(detail.pending.p)); ctx.lineTo(hover.mouseX, hover.mouseY); ctx.stroke()
                    ctx.setLineDash([])
                }
                ctx.restore()
            }
        }

        // Axis labels as ordinary text, so they take the theme's font.
        Repeater {
            model: chart.p.length > 1 ? chart.ticks : []
            PlasmaComponents3.Label {
                required property real modelData
                readonly property real yv: chart.py(modelData)
                visible: yv >= chart.plotTop && yv <= chart.priceBottom
                x: chart.plotRight + Kirigami.Units.smallSpacing
                y: yv - height / 2
                text: detail.num(modelData)
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }
        // The first and last bar's time; the read-out takes their place
        // while the pointer is over the chart.
        PlasmaComponents3.Label {
            visible: chart.p.length > 1 && !hover.overBar
            x: 0
            y: chart.plotBottom + 2
            text: detail.times.length ? detail.stamp(detail.times[0]) : ""
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        PlasmaComponents3.Label {
            visible: chart.p.length > 1 && !hover.overBar
            x: chart.plotRight - width
            y: chart.plotBottom + 2
            text: detail.times.length ? detail.stamp(detail.times[detail.times.length - 1]) : ""
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        // Hover read-out: crosshair lines, the pointer's price on the scale, and
        // the bar's figures and time along the bottom.
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            // Dragging moves the chart; keep the pop-up's scroll view from
            // taking the drag, and the wheel, while over the chart.
            preventStealing: true
            property real dragX: NaN
            property real dragCarry: 0
            onPressed: mouse => { if (mouse.button === Qt.LeftButton) { dragX = mouse.x; dragCarry = 0 } }
            onReleased: dragX = NaN
            onPositionChanged: mouse => {
                if (detail.pending) chart.requestPaint()
                if (detail.drawing || isNaN(dragX) || !(mouse.buttons & Qt.LeftButton)) return
                // Whole bars only; the remainder carries to the next move.
                dragCarry += (dragX - mouse.x) / chart.slot
                dragX = mouse.x
                const step = dragCarry > 0 ? Math.floor(dragCarry) : Math.ceil(dragCarry)
                if (step !== 0) { detail.pan(step); dragCarry -= step }
            }
            // Wheel up zooms in around the pointer; a sideways wheel or
            // trackpad swipe moves the chart.
            onWheel: wheel => {
                if (wheel.angleDelta.x !== 0 && Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y))
                    detail.pan(Math.round(-wheel.angleDelta.x / 120 * Math.max(1, detail.viewCount / 10)))
                else if (wheel.angleDelta.y !== 0)
                    detail.zoom(wheel.angleDelta.y > 0 ? 0.8 : 1.25, Math.max(0, Math.min(1, wheel.x / chart.plotRight)))
                wheel.accepted = true
            }
            readonly property int bar: chart.p.length < 2 ? -1
                : Math.max(0, Math.min(chart.p.length - 1, chart.barAt(mouseX)))
            readonly property bool active: containsMouse && bar >= 0 && mouseX <= chart.plotRight
            // Over a bar rather than the empty space past the newest one.
            readonly property bool overBar: active && chart.barAt(mouseX) < chart.p.length
            readonly property bool inPrice: mouseY >= chart.plotTop && mouseY <= chart.priceBottom
            // Double-click adds a level at that price; right-click removes
            // the level nearest the pointer, if one is within a few pixels.
            onDoubleClicked: mouse => {
                if (mouse.button === Qt.LeftButton && !detail.drawing && inPrice && chart.p.length > 1) detail.addLevel(chart.priceAt(mouse.y))
            }
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton) {
                    // Drawing a trend line: the first click sets one end,
                    // the second the other, and the Line button turns off.
                    if (!detail.drawing || !inPrice || chart.p.length < 2) return
                    // Between bars, the time is interpolated from the slot.
                    // Past the newest bar, in the empty space, it runs on at
                    // the usual bar spacing -- the inverse of barOf().
                    const frac = mouse.x / chart.slot - 0.5 + detail.viewFrom
                    const last = detail.fullCount - 1
                    const i0 = Math.max(0, Math.min(last - 1, Math.floor(frac)))
                    const t = frac >= last ? detail.full.t[last] + (frac - last) * detail.barGap
                            : detail.full.t[i0] + (frac - i0) * (detail.full.t[i0 + 1] - detail.full.t[i0])
                    const pt = { t: t, p: chart.priceAt(mouse.y) }
                    if (!detail.pending) detail.pending = pt
                    else { detail.addTrend(detail.pending, pt); detail.drawing = false }
                    return
                }
                // Right-click removes the level or trend line nearest the
                // pointer, if one is within a few pixels.
                let best = null, gap = Kirigami.Units.smallSpacing * 2
                for (const lv of detail.levels) {
                    const g = Math.abs(chart.py(lv) - mouse.y)
                    if (g <= gap) { gap = g; best = { level: lv } }
                }
                for (const l of detail.trends) {
                    const x1 = chart.tx(l.t1), y1 = chart.py(l.p1), x2 = chart.tx(l.t2), y2 = chart.py(l.p2)
                    const dx = x2 - x1, dy = y2 - y1, len2 = dx * dx + dy * dy || 1
                    const k = Math.max(0, Math.min(1, ((mouse.x - x1) * dx + (mouse.y - y1) * dy) / len2))
                    const g = Math.hypot(mouse.x - (x1 + k * dx), mouse.y - (y1 + k * dy))
                    if (g <= gap) { gap = g; best = { trend: l } }
                }
                if (best && best.trend) detail.removeTrend(best.trend)
                else if (best) detail.removeLevel(best.level)
            }
        }
        // The price scale on the right edge: the wheel stretches or squashes
        // it around the pointer, dragging moves it, a double-click fits it to
        // the bars again. Over the scale only; the chart keeps its own wheel.
        MouseArea {
            x: chart.plotRight
            y: chart.plotTop
            width: chart.width - chart.plotRight
            height: chart.priceBottom - chart.plotTop
            preventStealing: true
            cursorShape: Qt.SizeVerCursor
            property real dragY: NaN
            function hold() {
                if (detail.autoScale) { detail.scaleLo = chart.fitLo; detail.scaleHi = chart.fitHi; detail.autoScale = false }
            }
            onWheel: wheel => {
                if (wheel.angleDelta.y !== 0 && chart.p.length > 1) {
                    hold()
                    const at = chart.priceAt(wheel.y + y)
                    const k = wheel.angleDelta.y > 0 ? 0.8 : 1.25
                    detail.scaleLo = at - (at - detail.scaleLo) * k
                    detail.scaleHi = at + (detail.scaleHi - at) * k
                }
                wheel.accepted = true
            }
            onPressed: mouse => { dragY = mouse.y; hold() }
            onReleased: dragY = NaN
            onPositionChanged: mouse => {
                if (isNaN(dragY)) return
                const per = (detail.scaleHi - detail.scaleLo) / ((chart.priceBottom - chart.plotTop) || 1)
                const d = (mouse.y - dragY) * per
                detail.scaleLo += d; detail.scaleHi += d
                dragY = mouse.y
            }
            onDoubleClicked: detail.autoScale = true
        }
        // Each level's price on the right edge, over the axis labels.
        Repeater {
            model: detail.levels
            Rectangle {
                required property real modelData
                visible: chart.p.length > 1 && modelData >= chart.lo && modelData <= chart.hi
                x: chart.plotRight + 1
                y: Math.round(chart.py(modelData)) - height / 2
                width: lvText.implicitWidth + Kirigami.Units.smallSpacing * 2
                height: lvText.implicitHeight
                radius: 2
                color: Kirigami.Theme.neutralTextColor
                PlasmaComponents3.Label {
                    id: lvText
                    anchors.centerIn: parent
                    text: detail.num(parent.modelData)
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.backgroundColor
                }
            }
        }
        // Each option line's label at the left edge: "OI 350 (12K)", "max pain 345".
        Repeater {
            model: !detail.optLines ? [] : detail.optLines.levels.map(x => ({ k: x.strike, t: i18n("OI %1 (%2)", x.strike, x.total >= 1000 ? (x.total / 1000).toFixed(0) + "K" : x.total) }))
                                     .concat(isFinite(detail.optLines.pain) ? [{ k: detail.optLines.pain, t: i18n("max pain %1", detail.optLines.pain) }] : [])
            PlasmaComponents3.Label {
                required property var modelData
                visible: chart.p.length > 1 && modelData.k >= chart.lo && modelData.k <= chart.hi
                x: 2
                y: Math.round(chart.py(modelData.k)) - height
                text: modelData.t
                color: "#a78bfa"
                font: Kirigami.Theme.smallFont
            }
        }
        Rectangle {
            visible: hover.overBar
            x: hover.active ? Math.round(chart.px(hover.bar)) : 0
            y: chart.plotTop
            width: 1
            height: chart.plotBottom - chart.plotTop
            color: Kirigami.Theme.textColor
            opacity: 0.4
        }
        // The pointer's price: a horizontal line and its price on the scale,
        // so a level or a line end can be placed exactly.
        Rectangle {
            visible: hover.active && hover.inPrice
            x: 0
            y: hover.active ? Math.round(hover.mouseY) : 0
            width: chart.plotRight
            height: 1
            color: Kirigami.Theme.textColor
            opacity: 0.4
        }
        Rectangle {
            visible: hover.active && hover.inPrice
            x: chart.plotRight + 1
            y: hover.active ? Math.round(hover.mouseY) - height / 2 : 0
            width: cursorPrice.implicitWidth + Kirigami.Units.smallSpacing * 2
            height: cursorPrice.implicitHeight
            radius: 2
            color: Kirigami.Theme.textColor
            z: 2
            PlasmaComponents3.Label {
                id: cursorPrice
                anchors.centerIn: parent
                text: hover.active ? detail.num(chart.priceAt(hover.mouseY)) : ""
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.backgroundColor
            }
        }
        Rectangle {
            width: Kirigami.Units.smallSpacing * 2
            height: width
            radius: width / 2
            color: detail.lineColour
            visible: hover.overBar && !detail.candles
            x: hover.active ? chart.px(hover.bar) - width / 2 : 0
            y: hover.active ? chart.py(chart.p[hover.bar]) - height / 2 : 0
        }
        Rectangle {
            visible: hover.overBar
            color: Kirigami.Theme.backgroundColor
            border.color: Kirigami.Theme.disabledTextColor
            radius: Kirigami.Units.cornerRadius
            width: readout.implicitWidth + Kirigami.Units.largeSpacing
            height: readout.implicitHeight + Kirigami.Units.smallSpacing
            x: hover.active ? Math.min(chart.plotRight - width, Math.max(0, chart.px(hover.bar) - width / 2)) : 0
            // Below the plot, in the time row, so it never covers the bars.
            y: chart.plotBottom + 1
            PlasmaComponents3.Label {
                id: readout
                anchors.centerIn: parent
                font: Kirigami.Theme.smallFont
                text: !hover.active ? ""
                    : detail.candles
                      ? i18n("O %1  H %2  L %3  C %4", detail.num(detail.opens[hover.bar]), detail.num(detail.highs[hover.bar]),
                             detail.num(detail.lows[hover.bar]), detail.num(detail.closes[hover.bar]))
                        + (detail.vols[hover.bar] > 0 ? "  ·  " + i18n("Vol %1", Math.round(detail.vols[hover.bar]).toLocaleString(Qt.locale(), "f", 0)) : "")
                        + "  ·  " + detail.stamp(detail.times[hover.bar])
                      : detail.num(chart.p[hover.bar]) + "  ·  " + detail.stamp(detail.times[hover.bar])
            }
        }

        PlasmaComponents3.BusyIndicator {
            anchors.centerIn: parent
            visible: detail.loading && chart.p.length === 0
            running: visible
        }
        PlasmaComponents3.Label {
            anchors.centerIn: parent
            visible: detail.failed && !detail.loading
            text: i18n("No chart data from Yahoo for this range")
            opacity: 0.7
        }
    }

    // ── pop the card out ──
    // Under the chart, at the right: the card without its chart in a window
    // of its own (a quote window), and the list back here. While the window
    // is linked, tickers clicked in the lists open in it. In the quote
    // window, where there is no chart, the row offers the chart windows
    // instead: the widget's own chart and TradingView's, following the
    // active ticker (or this window's symbol, if it is unlinked).
    RowLayout {
        visible: !detail.chartOnly && detail.tab === 0
        Layout.fillWidth: true
        Layout.rightMargin: Kirigami.Units.largeSpacing
        Item { Layout.fillWidth: true }
        PlasmaComponents3.ToolButton {
            visible: !detail.inWindow
            icon.name: "window-new"
            text: i18n("Quote")
            onClicked: {
                detail.ws.openQuote(detail.entry, true)
                detail.back()
            }
            PlasmaComponents3.ToolTip { text: i18n("Pop the quote card out into a window of its own, without the chart. It follows the tickers you click, along with the linked chart windows, and the list stays here.") }
        }
        PlasmaComponents3.ToolButton {
            visible: detail.inWindow
            icon.name: "window-new"
            text: i18n("Chart")
            onClicked: detail.ws.openChart("chart", detail.linked ? "" : detail.entry.symbol, "5m")
            PlasmaComponents3.ToolTip { text: i18n("Open the chart in a window of its own, at 5-minute bars. It follows the symbol you open next, as this card does.") }
        }
        PlasmaComponents3.ToolButton {
            visible: detail.inWindow
            icon.name: "office-chart-line-stacked"
            text: i18n("TV")
            onClicked: detail.ws.openChart("tv", detail.linked ? "" : detail.entry.symbol, "5m")
            PlasmaComponents3.ToolTip { text: i18n("Open TradingView's chart for this symbol in a window, with its own indicators and drawing tools") }
        }
    }

    // ── the screen's scorecard, rule by rule ────────────────────────────
    // Opened from a screen with a scorecard: each rule with the row's
    // figure, the target and whether it passed. The figures are the ones
    // the screen listed, with the latest float, news and dilution merged
    // in. A scorecard made only of the long-term checks is shown by the
    // fundamentals section below instead.
    readonly property var card: entry.scorecard ? ticker.screener.scorecard(entry.scorecard) : null
    readonly property var cardRow: entry.row ? ticker.screener.withFacts(entry.row) : null
    readonly property bool cardShown: !!card && !!cardRow && card.rules.some(r => !/^p[1-8]$/.test(r.measure))
    readonly property var cardScore: cardShown ? Scorecards.score(card, cardRow) : null
    ColumnLayout {
        visible: !detail.chartOnly && detail.tab === 0 && detail.cardShown
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        PlasmaExtras.Heading {
            level: 5
            opacity: 0.8
            text: detail.cardShown && detail.cardScore ? i18n("%1: %2 of %3 rules pass", detail.card.name,
                                          detail.cardScore.score, detail.cardScore.total) : ""
        }
        Repeater {
            model: detail.cardShown ? detail.card.rules : []
            delegate: RowLayout {
                id: ruleRow
                required property var modelData
                readonly property var pass: Scorecards.test(modelData, detail.cardRow)
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    text: ruleRow.pass === true ? "✓" : ruleRow.pass === false ? "✗" : "?"
                    color: ruleRow.pass === true ? Kirigami.Theme.positiveTextColor
                         : ruleRow.pass === false ? Kirigami.Theme.negativeTextColor
                         : Kirigami.Theme.disabledTextColor
                    font.bold: true
                    Layout.preferredWidth: Kirigami.Units.gridUnit
                }
                // The name gives way first; the value and target keep their
                // width, so a long target never runs into the value.
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                    textFormat: Text.PlainText
                    text: Scorecards.measure(ruleRow.modelData.measure).name
                    elide: Text.ElideRight
                }
                PlasmaComponents3.Label {
                    Layout.minimumWidth: implicitWidth
                    textFormat: Text.PlainText
                    text: Scorecards.valueText(ruleRow.modelData, detail.cardRow)
                    font.family: Kirigami.Theme.fixedWidthFont.family
                }
                PlasmaComponents3.Label {
                    Layout.preferredWidth: Math.max(Kirigami.Units.gridUnit * 5, implicitWidth)
                    Layout.minimumWidth: Math.max(Kirigami.Units.gridUnit * 5, implicitWidth)
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    horizontalAlignment: Text.AlignRight
                    textFormat: Text.PlainText
                    text: i18n("target %1", Scorecards.targetText(ruleRow.modelData))
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }
            }
        }
        PlasmaComponents3.Label {
            visible: !!detail.entry.row && !!detail.entry.row.time
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.6
            text: i18n("Price, change and volume as at the alert; float, news and dilution as known now.")
        }
    }

    // ── long-term fundamentals ──────────────────────────────────────────
    // The eight checks from SEC filings (the scanner's
    // pillars.py), each with its figure and target. Known already for
    // companies in a long-term value list; otherwise worked out on request.
    // Hidden when the screen's own scorecard is showing, so a quote opened
    // from a screen shows that screen's card and no other.
    readonly property var value: {
        const v = ticker.screener.valueData[entry.symbol]
        return v && !v.failed ? v : localValue
    }
    property var localValue: null
    property bool valueLoading: false
    function checkValue() {
        const q = ticker.screener.quotes[entry.symbol]
        const price = q ? q.price : f.value
        if (!(price > 0) || !/^[A-Z][A-Z0-9.\-]{0,9}$/.test(entry.symbol)) return
        valueLoading = true
        const sym = entry.symbol
        ticker.screener.bridgeRun(["value", sym + ":" + price + ":" + (q && q.shares > 0 ? q.shares : "")], out => {
            if (!current(sym)) return
            detail.valueLoading = false
            if (out && out[sym]) detail.localValue = out[sym]
        }, 120, true)
    }
    ColumnLayout {
        visible: !detail.chartOnly && detail.tab === 0 && detail.kind === "EQUITY" && !detail.cardShown
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            PlasmaExtras.Heading {
                level: 5
                text: detail.value ? i18n("Long-term fundamentals: %1 of %2 checks pass", detail.value.passed, detail.value.scored)
                                   : i18n("Long-term fundamentals")
                opacity: 0.8
            }
            Item { Layout.fillWidth: true }
            PlasmaComponents3.ToolButton {
                visible: !detail.value
                enabled: !detail.valueLoading
                icon.name: "view-refresh"
                text: detail.valueLoading ? i18n("Checking filings…") : i18n("Check")
                onClicked: detail.checkValue()
                PlasmaComponents3.ToolTip { text: i18n("Look up this company's SEC filings now") }
            }
        }
        Repeater {
            model: detail.value ? detail.value.pillars : []
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    text: modelData.passed === true ? "✓" : modelData.passed === false ? "✗" : "?"
                    color: modelData.passed === true ? Kirigami.Theme.positiveTextColor
                         : modelData.passed === false ? Kirigami.Theme.negativeTextColor
                         : Kirigami.Theme.disabledTextColor
                    font.bold: true
                    Layout.preferredWidth: Kirigami.Units.gridUnit
                }
                // As above: the name gives way, value and target do not overlap.
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                    textFormat: Text.PlainText
                    text: modelData.name
                    elide: Text.ElideRight
                }
                PlasmaComponents3.Label {
                    Layout.minimumWidth: implicitWidth
                    textFormat: Text.PlainText
                    text: modelData.value
                    font.family: Kirigami.Theme.fixedWidthFont.family
                }
                PlasmaComponents3.Label {
                    Layout.preferredWidth: Math.max(Kirigami.Units.gridUnit * 5, implicitWidth)
                    Layout.minimumWidth: Math.max(Kirigami.Units.gridUnit * 5, implicitWidth)
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    horizontalAlignment: Text.AlignRight
                    textFormat: Text.PlainText
                    text: i18n("target %1", modelData.target)
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }
            }
        }
        PlasmaComponents3.Label {
            visible: !!detail.value
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.6
            text: i18n("From SEC filings, five fiscal years; P/E and price/FCF use today's price. ? = not in the filings.")
        }
    }

    // ── the figures ─────────────────────────────────────────────────────
    // Two label/value pairs per line, as on Yahoo's quote page.
    Repeater {
        model: detail.tab === 0 && !detail.chartOnly ? detail.sections : []
        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.topMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            PlasmaExtras.Heading {
                level: 5
                text: modelData.title
                opacity: 0.8
            }
            GridLayout {
                id: grid
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing * 2
                rowSpacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: modelData.rows
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        PlasmaComponents3.Label {
                            textFormat: Text.PlainText
                            text: modelData[0]
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        PlasmaComponents3.Label {
                            textFormat: Text.PlainText
                            text: modelData[1]
                            font.family: Kirigami.Theme.fixedWidthFont.family
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }
    PlasmaComponents3.Label {
        visible: !detail.chartOnly && detail.tab === 0 && detail.sections.length === 0
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        horizontalAlignment: Text.AlignHCenter
        text: detail.summaryFailed ? i18n("Yahoo did not return the quote figures") : i18n("Loading figures…")
        opacity: 0.7
    }

    // ── the news tab ────────────────────────────────────────────────────
    Repeater {
        model: detail.tab === 1 ? detail.news : []
        delegate: PlasmaComponents3.ItemDelegate {
            id: card
            required property var modelData
            Layout.fillWidth: true
            // The same card as the News tab: picture (or source initial), headline, source and age.
            readonly property string picture: modelData.image || detail.ticker.screener.articleImages[modelData.link] || ""
            // Feed links are only opened as web pages, never another scheme.
            onClicked: if (/^https?:\/\//i.test(modelData.link)) Qt.openUrlExternally(modelData.link)
            Component.onCompleted: if (Plasmoid.configuration.newsImages && !modelData.image && modelData.link) detail.ticker.screener.wantImage(modelData.link)

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                Item {
                    visible: Plasmoid.configuration.newsImages
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                    Rectangle {
                        anchors.fill: parent
                        radius: Kirigami.Units.cornerRadius
                        visible: img.status !== Image.Ready
                        color: detail.sourceColor(card.modelData.source)
                        opacity: 0.35
                    }
                    PlasmaComponents3.Label {
                        anchors.centerIn: parent
                        visible: img.status !== Image.Ready
                        textFormat: Text.PlainText
                        text: String(card.modelData.source || "?").charAt(0).toUpperCase()
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
                        font.bold: true
                        opacity: 0.8
                    }
                    // A plain clipped Image, as on the News tab.
                    Item {
                        anchors.fill: parent
                        clip: true
                        Image {
                            id: img
                            anchors.fill: parent
                            source: card.picture
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: Kirigami.Units.gridUnit * 9
                            visible: status === Image.Ready
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing / 2
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: card.modelData.title
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        font.weight: Font.DemiBold
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: card.modelData.source + " · " + detail.ago(card.modelData.time)
                    }
                }
            }
        }
    }
    PlasmaComponents3.BusyIndicator {
        Layout.alignment: Qt.AlignHCenter
        visible: detail.tab === 1 && detail.newsLoading
        running: visible
    }
    PlasmaComponents3.Label {
        visible: detail.tab === 1 && !detail.newsLoading && detail.newsFailed
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.largeSpacing
        horizontalAlignment: Text.AlignHCenter
        text: i18n("No headlines found in the last week")
        opacity: 0.7
    }
    PlasmaComponents3.ToolButton {
        visible: detail.tab === 1 && detail.news.length > 0
        Layout.alignment: Qt.AlignHCenter
        icon.name: "view-refresh"
        text: i18n("Refresh headlines · %1", detail.newsSource)
        onClicked: detail.loadNews()
    }
}
