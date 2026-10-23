// The screener's engine: no UI, runs for as long as the widget does, so the
// alert feeds keep collecting whichever view is on screen.
//
// The starting Running Up settings were calibrated on 2026-10-22 against a
// reference list of momentum alerts: every one had risen about 3% or more
// within the previous one to two minutes (smallest +2.9%, KRRO), at any
// price ($0.46 SHFS to $60.70 FEIM), green or red on the day (FEIM -11%,
// HOST -4.9%), and volume did not gate it (NCPL fired at a 5-minute RVOL of
// 126%).
//
// SCREENS are the user's to define (Settings → Screeners; screens.js holds the
// shape and the starting list). Each is one of:
//   running -- Running Up: the price is `runPct`% or more above its lowest
//              point in the last `runWindow` minutes, and at a new high for
//              that window.
//   hod     -- High of Day: the price passes the session's high so far.
//   ranked  -- a live list: the pool's top `rankCount` by `rankBy`, rebuilt
//              every pass.
//   value   -- a long-term list: US companies worth `valueCapMin` or more,
//              scored on eight fundamental checks from SEC filings (the
//              scanner's pillars.py, through the bridge, once a
//              day per company) and on their daily trend -- price against
//              the 50-day average, the 50-day against the 200-day, and
//              whether the 50-day is turning up. See "Long-term value".
// Any screen can carry filters (price, change, gap, volume, RVOL, market
// cap, float, short interest, news age) and a scorecard. Every screen reads
// the same pass, so adding screens adds nothing for Yahoo to answer.
//
// The starting High of Day screen is limited to moving small caps ($1-$20,
// up 10%+): without that the whole market's routine late-day highs flood it
// (31 in 3.5 minutes on 2026-10-22, all large caps), and the moves worth
// seeing on that day's reference list were all $3-$16 and up 15-37%.
//
// THE POOL is the active market, not a shortlist: US-listed common stock
// (no OTC, units, warrants, rights or preferreds) trading `poolMinVolume`+
// shares today or averaging `poolMinAvg`+ a day -- about 3,000 stocks -- from
// a paged Yahoo screen every 5 minutes, plus the premarket or after-hours
// gainers from the scanner (contents/code/scannerbridge.py), which
// catches a thin stock waking up before the screen sees its volume.
//
// THE PASS, every `passSeconds` (30): the whole pool through Yahoo's batch
// quote endpoint, 200 symbols a request. Each stock's price and volume are
// kept for the last few minutes, and the triggers read that history. If
// Yahoo refuses (a 429 or an error), the pass slows down, doubling to at
// most 2 minutes, and speeds back up once it is answered again.
//
// SESSIONS (ET, weekdays): premarket 04:00-09:30, regular 09:30-16:00,
// after hours 16:00-20:00. The clock is worked out here from the time of
// day; Yahoo supplies only the UTC offset. Market holidays are not known.
//
// VOLUME. Yahoo's quotes carry the regular session's volume only.
//   premarket -- volume, and its 5-minute RVOL, come from the scanner's
//     premarket list where a stock is on it; otherwise not known. Alerts
//     fire on price, which is all the trigger needs.
//   regular -- the quote's running volume; 5-minute RVOL is the growth over
//     the last 5 minutes against an average 5 minutes of the stock's normal
//     day (its 3-month average over 78). Some platforms measure against the
//     same time of day instead, so their figures differ; the same order of
//     magnitude.
//   after hours -- the regular session's volume; no 5-minute figure.
//
// PER ALERTED STOCK, once and then every 15 minutes: float, short interest,
// dilution risk (SEC EDGAR via the scanner's dilution.py -- context, never a
// filter) and the catalyst check, merged into its rows as they arrive.

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import QtQuick.LocalStorage
import "sounds.js" as Sounds
import "screens.js" as Screens
import "scorecards.js" as Scorecards

Item {
    id: eng

    required property var ticker          // main.qml: yget, withCrumb
    readonly property var cfg: Plasmoid.configuration
    readonly property string bridge: String(Qt.resolvedUrl("../code/scannerbridge.py")).replace(/^file:\/\//, "")

    // New York's offset from UTC in seconds, from Yahoo's meta.gmtoffset so
    // daylight saving follows by itself. -14400 (EDT) until the first reply.
    property int etOffset: -14400
    // Minutes since midnight ET, and the ET date, for a time in seconds.
    function etMinutes(t) { const d = new Date((t + etOffset) * 1000); return d.getUTCHours() * 60 + d.getUTCMinutes() }
    function etDay(t) { return new Date((t + etOffset) * 1000).toISOString().slice(0, 10) }
    readonly property int preStart: 4 * 60
    readonly property int openAt: 9 * 60 + 30
    readonly property int closeAt: 16 * 60
    readonly property int postEnd: 20 * 60

    // The session as a property, so views can bind to it; kept current by
    // the minute timer below.
    property string currentPhase: phase()

    function phase() {
        const now = Date.now() / 1000
        const weekday = new Date((now + etOffset) * 1000).getUTCDay()
        if (weekday === 0 || weekday === 6) return "closed"
        const m = etMinutes(now)
        if (m < preStart) return "closed"
        if (m < openAt) return "pre"
        if (m < closeAt) return "regular"
        if (m < postEnd) return "post"
        return "closed"
    }

    property var candidates: []           // the pool: symbols watched each pass
    property var pmVol: ({})              // symbol -> [{t, v}] running premarket volume
    property var info: ({})               // symbol -> slow-moving facts
    property var hist: ({})               // symbol -> [{t, p, v}] recent passes
    property var quotes: ({})             // symbol -> latest quote figures
    readonly property var screens: Screens.load(cfg)
    property var feeds: ({})              // screen id -> alerts, newest first
    property var ranked: ({})             // screen id -> ranked rows, best first
    function screen(id) { return screens.find(s => s.id === id) || null }
    property date updated
    property string source: ""            // what the pool is made of
    property int passMs: cfg.passSeconds * 1000   // grows while Yahoo refuses

    signal alerted(string feed)

    // ── scorecards ────────────────────────────────────────────────────────
    // Named rule sets (Settings → Scorecards; scorecards.js). A screen names
    // the one it scores its rows with, or none.
    readonly property var scorecards: Scorecards.load(cfg)
    function scorecard(id) { return id ? Scorecards.find(scorecards, id) : null }

    // The label column. Size bands and the short-interest line are this
    // widget's own.
    function tags(r) {
        const t = []
        if (r.float > 0) t.push(r.float < 10e6 ? "Low float" : r.float < 100e6 ? "Medium float" : "High float")
        if (r.shortFloat >= 20) t.push("High SI")
        return t.join(" · ")
    }

    // ── the scanner bridge ────────────────────────────────────────────────
    property var waiting: ({})            // command -> callback
    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source)
            const done = eng.waiting[source]
            delete eng.waiting[source]
            let out = null
            try { out = JSON.parse(String(data["stdout"] || "")) } catch (e) {}
            if (out && out.error) out = null
            if (done) done(out)
        }
    }
    // One shell word, single-quoted: Settings → Data values are typed in, so
    // they are never pasted into a command bare.
    function shq(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }
    function bridgeRun(args, done, seconds) {
        // Settings → Data reach the scanner as environment variables
        // (code/scanner/settings.py). The trailing comment makes every call
        // a new source.
        const cmd = "env"
                  + " MARKET_TICKER_SEC_CONTACT=" + shq(cfg.secContact)
                  + " MARKET_TICKER_EARNINGS_MIN_CAP=" + shq(cfg.earningsMinCap)
                  + " MARKET_TICKER_RESEARCH_DIR=" + shq(cfg.researchDir)
                  + " MARKET_TICKER_EARNINGS_TICKERS=" + shq(cfg.earningsTickers)
                  + " timeout " + (seconds || 60) + " python3 " + shq(bridge) + " " + shq(cfg.scannerDir)
                  + " " + args + " # " + Date.now()
        waiting[cmd] = done
        exec.connectSource(cmd)
    }
    // Each screen has its own sound (Settings → Screeners), so which one
    // fired can be told by ear, whether or not the pop-up is open. The
    // pop-up's mute button silences them all. One sound per screen for a
    // burst of alerts, not one per alert.
    property var lastSound: ({})
    function play(id) {
        const sc = screen(id)
        const path = sc ? sc.sound : ""
        if (!cfg.alertSound || !path) return
        const now = Date.now()
        if (now - (lastSound[id] || 0) < 5000) return
        lastSound[id] = now
        exec.connectSource(Sounds.command(path) + " # " + now)
    }

    // ── the pool ──────────────────────────────────────────────────────────
    // Common stock only. Nasdaq's fifth letter marks units (U), warrants (W)
    // and rights (R) -- SPAC pieces that trade thin and set off alerts on a
    // few hundred shares -- and Yahoo writes preferred shares as "-P"
    // (AHT-PD is Ashford Hospitality's Series D preferred).
    function validSymbol(s) {
        return /^[A-Z][A-Z0-9.\-]{0,9}$/.test(s) && !/^[A-Z]{4}[UWR]$/.test(s) && !/-P[A-Z]?$/.test(s)
    }

    // Every minute: New York's UTC offset, and in
    // premarket or after hours the scanner's list -- its symbols join the
    // pool, and its premarket volumes feed the volume columns.
    function refreshMinute() {
        // Facts (float, short interest, news, dilution) for every stock in
        // the feeds -- including alerts restored from the database, which
        // never passed through raise() -- the 60 most recent, refreshed every
        // 15 minutes by refreshInfo's own staleness check.
        let all = []
        for (const id in feeds) all = all.concat(feeds[id])
        all.sort((a, b) => b.time - a.time)
        const inFeeds = Array.from(new Set(all.map(a => a.symbol))).slice(0, 60)
        if (inFeeds.length) refreshInfo(inFeeds)
        ticker.yget("https://query1.finance.yahoo.com/v8/finance/chart/SPY?interval=1d&range=1d", x => {
            try {
                const off = JSON.parse(x.responseText).chart.result[0].meta.gmtoffset
                if (typeof off === "number") etOffset = off
            } catch (e) {}
        })
        const ph = phase()
        if (ph === "pre" || ph === "post") {
            bridgeRun(ph === "pre" ? "premarket" : "afterhours", out => {
                if (!Array.isArray(out)) return
                const now = Date.now()
                if (ph === "pre") {
                    for (const g of out) {
                        if (!(g.volume > 0)) continue
                        const h = (pmVol[g.symbol] || []).filter(x => now - x.t < 30 * 60000)
                        h.push({ t: now, v: g.volume })
                        pmVol[g.symbol] = h
                    }
                }
                extra = out.map(g => g.symbol).filter(validSymbol)
                candidates = Array.from(new Set(pool.concat(extra, valueUniverse)))
            })
        } else {
            extra = []
        }
    }

    // Every 5 minutes: the pool, a paged Yahoo screen of the active market.
    property var pool: []
    property var extra: []
    property var building: []
    function refreshPool() {
        building = []
        poolPage(0)
    }
    function poolPage(offset) {
        ticker.withCrumb(c => {
            const x = new XMLHttpRequest()
            x.onreadystatechange = () => {
                if (x.readyState !== XMLHttpRequest.DONE) return
                if (x.status === 401) { ticker.crumb = ""; finishPool(); return }
                let res = null
                try { res = JSON.parse(x.responseText).finance.result[0] } catch (e) {}
                if (!res) { finishPool(); return }
                building = building.concat(res.quotes.map(q => q.symbol).filter(validSymbol))
                // 250 a page, up to 5,000 stocks.
                if (offset + 250 < Math.min(res.total, 5000)) poolPage(offset + 250)
                else finishPool()
            }
            x.open("POST", "https://query1.finance.yahoo.com/v1/finance/screener?crumb=" + encodeURIComponent(c))
            x.setRequestHeader("User-Agent", "Mozilla/5.0")
            x.setRequestHeader("Content-Type", "application/json")
            const exch = ["NMS", "NCM", "NGM", "NYQ", "ASE"]
                .map(e => ({ operator: "eq", operands: ["exchange", e] }))
            x.send(JSON.stringify({
                offset: offset, size: 250, sortField: "dayvolume", sortType: "DESC", quoteType: "EQUITY",
                query: { operator: "AND", operands: [
                    { operator: "eq", operands: ["region", "us"] },
                    { operator: "or", operands: exch },
                    { operator: "or", operands: [
                        { operator: "gt", operands: ["dayvolume", cfg.poolMinVolume] },
                        { operator: "gt", operands: ["avgdailyvol3m", cfg.poolMinAvg] }
                    ]}
                ]}
            }))
        })
    }
    function finishPool() {
        // A failed first page keeps the old pool rather than emptying it.
        if (building.length > 0) pool = building
        building = []
        candidates = Array.from(new Set(pool.concat(extra, valueUniverse)))
        source = i18n("active market")
    }

    // ── slow facts per candidate ──────────────────────────────────────────
    function refreshInfo(symbols) {
        const stale = (symbols || candidates).filter(s => !info[s] || Date.now() - info[s].at > 15 * 60000)
        if (stale.length === 0) return
        // Mark now, so an overlapping round does not ask twice.
        const next = Object.assign({}, info)
        for (const s of stale) next[s] = Object.assign({}, next[s] || {}, { at: Date.now() })
        info = next

        // In batches of 15, so one bridge call stays well inside its
        // 60-second timeout even when Finviz is slow.
        for (let i = 0; i < stale.length; i += 15) bridgeFacts(stale.slice(i, i + 15))
        yahooFacts(stale)
    }
    function bridgeFacts(stale) {
        bridgeRun("dilution " + stale.join(" "), out => {
            if (!out) return
            const n = Object.assign({}, info)
            for (const s in out) n[s] = Object.assign({}, n[s], { dilution: out[s] })
            info = n
        })
        bridgeRun("stocks " + stale.join(" "), out => {
            if (!out) return
            const n = Object.assign({}, info)
            for (const s in out) {
                const o = out[s]
                n[s] = Object.assign({}, n[s], {
                    finvizFloat: o.float, shortFloat: o.shortFloat,
                    catalyst: o.catalyst, newsTime: o.newsTime,
                    newsTitle: o.newsTitle, newsSource: o.newsSource, newsUrl: o.newsUrl || "",
                    scanner: true
                })
            }
            info = n
        })
    }
    function yahooFacts(stale) {
        ticker.withCrumb(c => {
            for (const s of stale) {
                ticker.yget("https://query2.finance.yahoo.com/v10/finance/quoteSummary/" + encodeURIComponent(s)
                            + "?modules=summaryDetail,defaultKeyStatistics,price&crumb=" + encodeURIComponent(c), x => {
                    try {
                        const r = JSON.parse(x.responseText).quoteSummary.result[0]
                        const raw = (m, k) => r[m] && r[m][k] && typeof r[m][k].raw === "number" ? r[m][k].raw : NaN
                        const n = Object.assign({}, info)
                        n[s] = Object.assign({}, n[s], {
                            name: (r.price && (r.price.shortName || r.price.longName)) || "",
                            yahooFloat: raw("defaultKeyStatistics", "floatShares"),
                            shortShares: raw("defaultKeyStatistics", "sharesShort"),
                            yahooShortFloat: raw("defaultKeyStatistics", "shortPercentOfFloat") * 100,
                            avgVol: raw("summaryDetail", "averageDailyVolume10Day") || raw("summaryDetail", "averageVolume")
                        })
                        info = n
                    } catch (e) {}
                })
            }
        })
    }

    // ── the pass ──────────────────────────────────────────────────────────
    property bool passing: false
    function pass() {
        const ph = phase()
        if (ph === "closed" || passing || candidates.length === 0) return
        passing = true
        const batches = []
        for (let i = 0; i < candidates.length; i += 200) batches.push(candidates.slice(i, i + 200))
        let failed = false
        // One request at a time: gentler on Yahoo, and a pass of ~15
        // takes a few seconds.
        const next = i => {
            if (i >= batches.length) {
                passing = false
                // Back off while Yahoo refuses; recover once it answers.
                passMs = failed ? Math.min(passMs * 2, 120000) : cfg.passSeconds * 1000
                buildRanked()
                updated = new Date()
                return
            }
            ticker.withCrumb(c => {
                ticker.yget("https://query1.finance.yahoo.com/v7/finance/quote?crumb=" + encodeURIComponent(c)
                            + "&symbols=" + batches[i].map(encodeURIComponent).join(","), x => {
                    if (x.status === 401) ticker.crumb = ""
                    let qs = null
                    try { qs = JSON.parse(x.responseText).quoteResponse.result } catch (e) {}
                    if (!qs) failed = true
                    else for (const q of qs) take(q, ph)
                    next(i + 1)
                })
            })
        }
        next(0)
    }

    // One stock's quote: record it, then test the triggers.
    function take(q, ph) {
        const sym = q.symbol
        // The price that is trading now: premarket, regular or after hours.
        const price = ph === "pre" && q.preMarketPrice > 0 ? q.preMarketPrice
                    : ph === "post" && q.postMarketPrice > 0 ? q.postMarketPrice
                    : q.regularMarketPrice
        if (!(price > 0)) return
        const now = Date.now()
        const pm = pmVol[sym] || []
        const volume = ph === "pre" ? (pm.length ? pm[pm.length - 1].v : NaN) : q.regularMarketVolume
        const avg = q.averageDailyVolume3Month || q.averageDailyVolume10Day
        // Premarket, Yahoo's regular-session fields still describe
        // yesterday: regularMarketPrice is yesterday's close and
        // regularMarketPreviousClose the close before it (AARD 2026-10-23:
        // $3.95 and $4.41), so yesterday's close is regularMarketPrice.
        const prev = ph === "pre" ? q.regularMarketPrice : q.regularMarketPreviousClose
        // Change is from yesterday's close, except after hours, where it is
        // from today's close -- the usual meaning once the session has ended.
        const ref = ph === "post" ? q.regularMarketPrice : prev

        let h = hist[sym]
        const first = !h
        h = (h || []).filter(x => now - x.t < 6 * 60000)
        h.push({ t: now, p: price, v: volume })
        hist[sym] = h

        // 5-minute volume: the growth of the running total over ~5 minutes.
        let rvol5 = NaN
        const back = h.filter(x => now - x.t >= 4.5 * 60000).pop()
        if (back && Number.isFinite(volume) && Number.isFinite(back.v)) {
            const vol5 = (volume - back.v) * 5 * 60000 / (now - back.t)
            let avg5 = NaN
            if (ph === "regular") avg5 = avg > 0 ? avg / 78 : NaN
            else if (ph === "pre") {
                const mins = etMinutes(now / 1000) - preStart
                if (mins >= 10) avg5 = volume / mins * 5
            }
            if (avg5 > 0) rvol5 = vol5 / avg5 * 100
        }

        const r = {
            symbol: sym, name: q.shortName || q.longName || "",
            price: price,
            change: ref > 0 ? (price / ref - 1) * 100 : NaN,
            gap: q.regularMarketOpen > 0 && prev > 0 && ph !== "pre"
                 ? (q.regularMarketOpen / prev - 1) * 100 : (prev > 0 ? (price / prev - 1) * 100 : NaN),
            volume: volume,
            rvol: avg > 0 && Number.isFinite(volume) ? volume / avg : NaN,
            rvol5: rvol5,
            marketCap: q.marketCap,
            ma50: q.fiftyDayAverage, ma200: q.twoHundredDayAverage,
            low52: q.fiftyTwoWeekLow, high52: q.fiftyTwoWeekHigh,
            shares: q.sharesOutstanding
        }
        quotes[sym] = r

        // The session's low so far: Yahoo's day low in regular hours,
        // otherwise the lowest price seen this session.
        const sessionLow = ph === "regular" && q.regularMarketDayLow > 0 ? q.regularMarketDayLow : NaN
        const low = Math.min(seenLow[sym] === undefined ? Infinity : seenLow[sym],
                             Number.isFinite(sessionLow) ? sessionLow : price, price)
        seenLow[sym] = low
        r.offLow = low > 0 ? (price / low - 1) * 100 : NaN

        // The session's high so far. Regular hours: Yahoo's day high, which
        // includes this price. Otherwise the highest price seen this session.
        const st = seenHigh[sym]
        const sessionHigh = ph === "regular" && q.regularMarketDayHigh > 0 ? q.regularMarketDayHigh : NaN
        if (first || st === undefined) {
            // First sight: seed, never alert -- a stock already up 40% at
            // start-up is not running up this instant.
            seenHigh[sym] = Number.isFinite(sessionHigh) ? sessionHigh : price
            return
        }

        // Each alert screen tests this pass against its own trigger and
        // quote-level filters.
        const prior = st
        const newHigh = price > prior
        for (const sc of screens) {
            if (sc.type === "running") {
                // `runPct`% above the window's low, at the window's high, and
                // above this stock's last alert on this screen if that was
                // recent -- so a stall is not re-alerted, a fresh run is.
                const winMs = (sc.runWindow || 2) * 60000
                const win = h.filter(x => now - x.t <= winMs)
                if (win.length < 2) continue
                const lo = Math.min(...win.map(x => x.p))
                const hi = Math.max(...win.slice(0, -1).map(x => x.p))
                const key = sc.id + ":" + sym
                const last = lastRun[key]
                if ((price / lo - 1) * 100 >= (sc.runPct || 3) && price > hi
                        && !(last && now - last.t < winMs && price <= last.p)
                        && Screens.passes(sc, r, "quote")) {
                    lastRun[key] = { t: now, p: price }
                    raise(sc.id, r)
                }
            } else if (sc.type === "hod") {
                if (newHigh && Screens.passes(sc, r, "quote")) raise(sc.id, r)
            }
        }
        seenHigh[sym] = Math.max(prior, Number.isFinite(sessionHigh) ? sessionHigh : price, price)
    }

    // Ranked screens, rebuilt at the end of every pass from all the quotes.
    // Twice the rows are kept, so rows the facts filters drop can be filled.
    function buildRanked() {
        const next = {}
        const all = Object.values(quotes)
        for (const sc of screens) {
            if (sc.type === "value") { next[sc.id] = valueRows(sc); continue }
            if (sc.type !== "ranked") continue
            const by = sc.rankBy || "change"
            const n = sc.rankCount || 25
            const dir = sc.rankLow ? -1 : 1
            const list = all.filter(r => Number.isFinite(r[by]) && Screens.passes(sc, r, "quote"))
                            .sort((a, b) => dir * (b[by] - a[by])).slice(0, n * 2)
            next[sc.id] = list
            for (const r of list.slice(0, n))
                if (!info[r.symbol] && wanted.indexOf(r.symbol) < 0) wanted = wanted.concat([r.symbol])
        }
        ranked = next
    }
    property var seenHigh: ({})           // symbol -> session high so far
    property var seenLow: ({})            // symbol -> session low so far
    property var lastRun: ({})            // symbol -> {t, p} of its last Running Up alert

    // Facts for alerted stocks are asked for in small batches, not one
    // bridge call per alert.
    property var wanted: []
    Timer {
        interval: 5000; running: eng.wanted.length > 0
        onTriggered: { const w = eng.wanted; eng.wanted = []; eng.refreshInfo(w) }
    }

    // Every alert is its own row: a stock that runs up again shows again.
    // Only alerts on the same symbol within 4 seconds fold into one row that
    // counts them ("2 in 3s") -- a stock moving that fast would otherwise
    // fill the feed. With a pass every 30 seconds this is rare.
    function raise(feed, r) {
        if (!info[r.symbol] && wanted.indexOf(r.symbol) < 0) wanted = wanted.concat([r.symbol])
        const list = (feeds[feed] || []).slice()
        const now = Date.now()
        const a = Object.assign({}, r, { time: now, first: now, count: 1 })
        const top = list[0]
        if (top && top.symbol === r.symbol && a.time - top.time <= 4000) {
            a.first = top.first
            a.count = top.count + 1
            list[0] = a
            store(feed, a, top.time)
        } else {
            list.unshift(a)
            store(feed, a)
        }
        if (list.length > 3000) list.length = 3000
        const f = Object.assign({}, feeds); f[feed] = list; feeds = f
        updated = new Date()
        alerted(feed)
        play(feed)
    }

    // ── keeping the day's alerts ──────────────────────────────────────────
    // Alerts stay for the day and clear at local midnight. They are kept in
    // a small SQLite database (Qt's LocalStorage, under
    // ~/.local/share/plasmashell/QML/OfflineStorage/) so a Plasma restart or a
    // reboot does not empty the feeds. Not the widget's settings: those live
    // in the panel's shared config file, and a day of alerts written there on
    // every alert would bloat and churn it.
    property string day: ""
    property var db: null

    function openDb() {
        if (db) return true
        try {
            db = LocalStorage.openDatabaseSync("MarketTickerAlerts", "1.0", "Market Ticker screener alerts", 20000000)
            db.transaction(tx => tx.executeSql(
                "CREATE TABLE IF NOT EXISTS alerts (day TEXT, feed TEXT, time INTEGER, row TEXT)"))
            return true
        } catch (e) {
            console.warn("marketticker: alert database unavailable:", e)
            db = null
            return false
        }
    }
    // Saves an alert; `replaces` is the time of a row it was folded into.
    function store(feed, a, replaces) {
        if (!openDb()) return
        db.transaction(tx => {
            if (replaces !== undefined)
                tx.executeSql("DELETE FROM alerts WHERE day = ? AND feed = ? AND time = ?", [day, feed, replaces])
            tx.executeSql("INSERT INTO alerts VALUES (?, ?, ?, ?)", [day, feed, a.time, JSON.stringify(a)])
        })
    }
    // Today's alerts back from the database, newest first; older days are
    // deleted. Re-checked on the way in, so a symbol a later rule excludes
    // does not come back.
    function restore() {
        if (!openDb()) return
        migrate()
        db.transaction(tx => {
            tx.executeSql("DELETE FROM alerts WHERE day <> ?", [day])
            const rs = tx.executeSql("SELECT feed, row FROM alerts WHERE day = ? ORDER BY time DESC", [day])
            const f = {}
            for (let i = 0; i < rs.rows.length; i++) {
                let a
                try { a = JSON.parse(rs.rows.item(i).row) } catch (e) { continue }
                if (!validSymbol(a.symbol)) continue
                const id = rs.rows.item(i).feed
                ;(f[id] = f[id] || []).push(a)
            }
            feeds = f
        })
    }

    // Alerts saved the old way (the `alertLog` setting, used on 2026-10-22
    // before this database) are carried across once, then that key is
    // emptied. That log was keyed by the ET date.
    function migrate() {
        if (!cfg.alertLog) return
        try {
            const log = JSON.parse(cfg.alertLog)
            if (log.day === day) {
                for (const a of (log.running || []).slice().reverse()) store("running", a)
                for (const a of (log.hod || []).slice().reverse()) store("hod", a)
            }
        } catch (e) {}
        Plasmoid.configuration.alertLog = ""
    }

    // Local midnight starts both feeds clean.
    function rollDay() {
        const d = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if (d === day) return
        const first = day === ""
        day = d
        hist = ({}); seenHigh = ({}); seenLow = ({}); lastRun = ({}); pmVol = ({})
        if (first) restore()                  // start-up: bring today's back
        else { feeds = ({}); restore() }
    }
    // Premarket opens a new session: the overnight highs and histories go.
    property string lastPhase: ""
    onCurrentPhaseChanged: {
        if (lastPhase !== "" && currentPhase !== lastPhase) { hist = ({}); seenHigh = ({}); seenLow = ({}); lastRun = ({}) }
        lastPhase = currentPhase
    }

    // ── long-term value ───────────────────────────────────────────────────
    // The universe: US companies worth `valueCapMin` or more (about 1,500
    // at $2B), from a Yahoo screen refreshed every 6 hours; they join the
    // pool so every pass quotes them. Their fundamentals -- eight checks
    // from SEC filings, computed by the scanner's pillars.py with
    // today's price -- are worked through in batches of 40, one batch at a
    // time, and redone once a day per company (filings change quarterly).
    // The first full run takes a while; results are kept in the alert
    // database, so a restart does not repeat it.
    property var valueUniverse: []
    property var valueData: ({})          // symbol -> {passed, scored, pillars, at}
    property var maSlope: ({})            // symbol -> {pct, at}: 50-day average's change over 10 sessions
    property bool valueBusy: false
    // Companies with results from the last day, for the status line.
    readonly property int valueDone: Object.keys(valueData).filter(s => Date.now() - valueData[s].at <= 24 * 3600000).length

    function refreshValueUniverse(offset, acc) {
        offset = offset || 0
        acc = acc || []
        ticker.withCrumb(c => {
            const x = new XMLHttpRequest()
            x.onreadystatechange = () => {
                if (x.readyState !== XMLHttpRequest.DONE) return
                let res = null
                try { res = JSON.parse(x.responseText).finance.result[0] } catch (e) {}
                if (!res) { if (acc.length) valueUniverse = acc; return }
                acc = acc.concat(res.quotes.map(q => q.symbol).filter(validSymbol))
                if (offset + 250 < Math.min(res.total, 3000)) refreshValueUniverse(offset + 250, acc)
                else { valueUniverse = acc; candidates = Array.from(new Set(candidates.concat(acc))) }
            }
            x.open("POST", "https://query1.finance.yahoo.com/v1/finance/screener?crumb=" + encodeURIComponent(c))
            x.setRequestHeader("User-Agent", "Mozilla/5.0")
            x.setRequestHeader("Content-Type", "application/json")
            const exch = ["NMS", "NCM", "NGM", "NYQ", "ASE"]
                .map(e => ({ operator: "eq", operands: ["exchange", e] }))
            x.send(JSON.stringify({
                offset: offset, size: 250, sortField: "intradaymarketcap", sortType: "DESC", quoteType: "EQUITY",
                query: { operator: "AND", operands: [
                    { operator: "eq", operands: ["region", "us"] },
                    { operator: "or", operands: exch },
                    { operator: "gt", operands: ["intradaymarketcap", cfg.valueCapMin] }
                ]}
            }))
        })
    }

    // Symbols a scorecard asked fundamentals for (rows() via wantValue),
    // ahead of the value universe. Asked once each.
    property var valueWanted: []
    property var valueAsked: ({})
    function wantValue(syms) {
        const add = syms.filter(s => !valueAsked[s] && validSymbol(s))
        if (!add.length) return
        for (const s of add) valueAsked[s] = true
        valueWanted = valueWanted.concat(add)
        if (!valueBusy) valueSoon.start()
    }

    // The next batch: wanted symbols first, then companies with a quote and
    // no result from today.
    function valueWork() {
        if (valueBusy || (!hasValueScreen() && !valueWanted.length)) return
        const day = 24 * 3600000, now = Date.now()
        const wanted = valueWanted.filter(s => quotes[s]).slice(0, 40)
        valueWanted = valueWanted.filter(s => wanted.indexOf(s) < 0)
        const due = wanted.concat(hasValueScreen()
            ? valueUniverse.filter(s => quotes[s] && wanted.indexOf(s) < 0 && (!valueData[s] || now - valueData[s].at > day))
            : []).slice(0, 40)
        if (!due.length) return
        valueBusy = true
        const args = due.map(s => s + ":" + quotes[s].price + ":" + (quotes[s].shares > 0 ? quotes[s].shares : ""))
        bridgeRun("value " + args.join(" "), out => {
            valueBusy = false
            if (!out) return
            const next = Object.assign({}, valueData)
            for (const s in out) {
                next[s] = Object.assign(out[s], { at: Date.now() })
                storeValue(s, next[s])
            }
            valueData = next
            valueSoon.start()                 // straight on to the next batch
        }, 300)
    }
    Timer { id: valueSoon; interval: 3000; onTriggered: eng.valueWork() }
    function hasValueScreen() { return screens.some(s => s.type === "value") }

    // The 50-day average's direction, from a year of daily closes, for the
    // companies close to qualifying: most checks pass and the price is back
    // above a 50-day that is still under the 200-day. Twice a day each.
    function slopeWork() {
        const now = Date.now()
        const near = Object.keys(valueData).filter(s => {
            const q = quotes[s], v = valueData[s]
            return q && v.passed >= 5 && q.price > q.ma50 && q.ma50 < q.ma200
                && (!maSlope[s] || now - maSlope[s].at > 12 * 3600000)
        }).slice(0, 20)
        for (const s of near) {
            ticker.yget("https://query1.finance.yahoo.com/v8/finance/chart/" + encodeURIComponent(s)
                        + "?interval=1d&range=1y", x => {
                try {
                    const c = JSON.parse(x.responseText).chart.result[0].indicators.quote[0].close
                                  .filter(v => typeof v === "number")
                    if (c.length < 70) return
                    const sma = end => c.slice(end - 50, end).reduce((a, b) => a + b, 0) / 50
                    const m = Object.assign({}, maSlope)
                    m[s] = { pct: (sma(c.length) / sma(c.length - 10) - 1) * 100, at: Date.now() }
                    maSlope = m
                } catch (e) {}
            })
        }
    }

    // The rows of a value screen: every company with a result and a quote,
    // its figures, the trend checks, then the screen's filters; most checks
    // passed first, and among equals the earliest in its recovery (closest
    // above its 50-day) first.
    function num(text) {
        const m = String(text || "").match(/-?[\d.]+/)
        return m ? parseFloat(m[0]) : NaN
    }
    // The value figures for one row (a quote, or an alert carrying one):
    // fundamentals where the company has been checked, the trend from its
    // moving averages. Used by value lists and by any screen showing these
    // columns.
    function valueFields(q) {
        const v = valueData[q.symbol] || null
        const pill = n => (v && v.pillars || []).find(p => p.n === n) || {}
        const slope = maSlope[q.symbol]
        return {
            value: v,
            valuePassed: v ? v.passed : NaN,
            valueScored: v ? v.scored : NaN,
            pe5: num(pill(1).value), roic: num(pill(2).value), pfcf: num(pill(8).value),
            vs50: q.ma50 > 0 ? (q.price / q.ma50 - 1) * 100 : NaN,
            trend: q.ma50 > 0 && q.ma200 > 0 ? (q.ma50 / q.ma200 - 1) * 100 : NaN,
            off52: q.low52 > 0 ? (q.price / q.low52 - 1) * 100 : NaN,
            offHigh: q.high52 > 0 ? (1 - q.price / q.high52) * 100 : NaN,
            maSlope: slope ? slope.pct : NaN,
            valuationOk: pill(1).passed === true && pill(8).passed === true,
            pfcfOk: pill(8).passed === true,
            above50: q.ma50 > 0 ? q.price > q.ma50 : undefined,
            below200: q.ma50 > 0 && q.ma200 > 0 ? q.ma50 < q.ma200 : undefined,
            turningUp: slope ? slope.pct > 0 : undefined
        }
    }
    function valueRows(sc) {
        const out = []
        for (const s in valueData) {
            const q = quotes[s]
            if (!q) continue
            const r = Object.assign({}, q, valueFields(q))
            if (Screens.passes(sc, r, "quote")) out.push(r)
        }
        out.sort((a, b) => (b.valuePassed - a.valuePassed) || (a.vs50 - b.vs50))
        return out.slice(0, (sc.rankCount || 50) * 2)
    }

    function storeValue(sym, v) {
        if (!openDb()) return
        db.transaction(tx => {
            tx.executeSql("CREATE TABLE IF NOT EXISTS value (symbol TEXT PRIMARY KEY, at INTEGER, row TEXT)")
            tx.executeSql("INSERT OR REPLACE INTO value VALUES (?, ?, ?)", [sym, v.at, JSON.stringify(v)])
        })
    }
    function restoreValue() {
        if (!openDb()) return
        db.transaction(tx => {
            tx.executeSql("CREATE TABLE IF NOT EXISTS value (symbol TEXT PRIMARY KEY, at INTEGER, row TEXT)")
            // Older than a week is dropped rather than kept as if current.
            tx.executeSql("DELETE FROM value WHERE at < ?", [Date.now() - 7 * 24 * 3600000])
            const rs = tx.executeSql("SELECT symbol, row FROM value")
            const v = {}
            for (let i = 0; i < rs.rows.length; i++) {
                try { v[rs.rows.item(i).symbol] = JSON.parse(rs.rows.item(i).row) } catch (e) {}
            }
            valueData = v
        })
    }

    // The Deep Value Recovery screen and the Deep Value 8 scorecard joined
    // the starting lists on 2026-10-22. Screens or scorecards saved before
    // that get them added once; `valueAdded` records it, so deleting them
    // later sticks.
    function addValueScreenOnce() {
        // A saved Deep Value screen still on the first rules gets the
        // current ones (screens.js, deepValue); one the user has edited keeps
        // theirs.
        if (cfg.screens) {
            try {
                const l = JSON.parse(cfg.screens)
                const dv = Array.isArray(l) ? l.find(s => s.id === "deepvalue") : null
                if (dv && JSON.stringify(dv.filters) === JSON.stringify(Screens.deepValueFiltersV1)) {
                    dv.filters = Screens.deepValueFilters()
                    Plasmoid.configuration.screens = JSON.stringify(l)
                }
            } catch (e) {}
        }
        // Since 2026-10-22, Top Gainers and Top Losers show the value
        // columns (they serve long-term investing, not day trades). Set once;
        // a screen whose columns were already chosen is left alone.
        if (!cfg.rankedValueColumns) {
            try {
                const all = JSON.parse(cfg.screenerLayout || "{}")
                const shown = ["symbol", "score", "price", "change", "volume", "marketCap", "pe5", "pfcf",
                               "roic", "vs50", "trend", "offHigh", "off52", "dilution", "missed"]
                for (const id of ["gainers", "losers"]) if (!all[id]) all[id] = { shown: shown }
                Plasmoid.configuration.screenerLayout = JSON.stringify(all)
            } catch (e) {}
            Plasmoid.configuration.rankedValueColumns = true
        }
        // Top Losers joined the starting list the same day; added once too.
        if (cfg.screens && !cfg.losersAdded) {
            try {
                const l = JSON.parse(cfg.screens)
                if (Array.isArray(l) && !l.some(s => s.id === "losers")) {
                    const at = l.findIndex(s => s.id === "gainers")
                    l.splice(at >= 0 ? at + 1 : l.length, 0, Screens.topLosers())
                    Plasmoid.configuration.screens = JSON.stringify(l)
                }
            } catch (e) {}
        }
        Plasmoid.configuration.losersAdded = true
        if (cfg.valueAdded) return
        if (cfg.screens) {
            try {
                const l = JSON.parse(cfg.screens)
                if (Array.isArray(l) && !l.some(s => s.id === "deepvalue")) {
                    l.push(Screens.deepValue())
                    Plasmoid.configuration.screens = JSON.stringify(l)
                }
            } catch (e) {}
        }
        if (cfg.scorecards) {
            try {
                const l = JSON.parse(cfg.scorecards)
                if (Array.isArray(l) && !l.some(c => c.id === "deepvalue")) {
                    l.push(Scorecards.deepValue())
                    Plasmoid.configuration.scorecards = JSON.stringify(l)
                }
            } catch (e) {}
        }
        Plasmoid.configuration.valueAdded = true
    }

    Timer {
        interval: 6 * 3600000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { eng.addValueScreenOnce(); eng.restoreValue(); if (eng.hasValueScreen()) eng.refreshValueUniverse() }
    }
    Timer {
        interval: 120000; running: true; repeat: true
        onTriggered: { eng.valueWork(); eng.slopeWork() }
    }

    // ── market news ───────────────────────────────────────────────────────
    // The newest market headlines from the scanner's news.py
    // (Seeking Alpha, MarketWatch and CNBC desks), every 3 minutes, for the
    // News tab. [{title, url, source, time}], newest first.
    property var marketNews: []
    property date marketNewsAt
    function refreshMarketNews() {
        bridgeRun("marketnews 40", out => {
            if (Array.isArray(out)) { marketNews = out; marketNewsAt = new Date() }
        })
    }
    Timer {
        interval: 3 * 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: eng.refreshMarketNews()
    }

    // ── the calendar ──────────────────────────────────────────────────────
    // The economic and earnings calendar for the next 7 days, from the
    // scanner's calendar_events.py through the bridge: its own
    // allowlist of economic events (CPI, jobs, rates, the Fed) and its
    // choice of reporters. [{date, events: [...] | null}]; null for a day
    // whose feed could not be read. Every 15 minutes, which also brings in
    // actual figures as they print. A week takes about 30 seconds to fetch.
    property var calendar: null
    property date calendarAt
    property bool calendarLoading: false
    function refreshCalendar() {
        if (calendarLoading) return
        calendarLoading = true
        bridgeRun("calendar 7", out => {
            calendarLoading = false
            if (Array.isArray(out)) { calendar = out; calendarAt = new Date() }
        }, 150)
    }
    Timer {
        interval: 15 * 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: eng.refreshCalendar()
    }

    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { eng.currentPhase = eng.phase(); eng.rollDay(); eng.refreshMinute() }
    }
    Timer {
        interval: 300000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: eng.refreshPool()
    }
    Timer {
        interval: eng.passMs; running: true; repeat: true
        onTriggered: eng.pass()
    }

    // Rows for a screen. An alert keeps the figures it fired with; the slow
    // facts -- float, short interest, news, dilution -- are merged in as they
    // arrive, the facts filters applied once they have, and the screen's
    // scorecard with them.
    function withFacts(g) {
        const n = info[g.symbol] || {}
        const fl = n.finvizFloat > 0 ? n.finvizFloat : n.yahooFloat
        const r = Object.assign({}, g, {
            name: g.name || n.name || "",
            float: fl > 0 ? fl : NaN,
            shortFloat: n.shortFloat >= 0 ? n.shortFloat : n.yahooShortFloat,
            shortShares: n.shortShares,
            catalyst: !!n.catalyst,
            newsTime: n.newsTime || null,
            newsTitle: n.newsTitle || "",
            dilution: n.dilution || null,
            factsKnown: !!n.scanner
        }, valueFields(g))
        r.tags = tags(r)
        return r
    }
    function rows(id) {
        const sc = screen(id)
        if (!sc) return []
        const listed = sc.type === "ranked" || sc.type === "value"
        const card = scorecard(sc.scorecard)
        let list = ((listed ? ranked[id] : feeds[id]) || []).map(withFacts)
        // A scorecard with fundamental checks: look them up for rows that
        // have none yet (any company, not only the $2B+ value universe).
        if (card && card.rules.some(r => /^p[1-8]$/.test(r.measure)))
            wantValue(list.slice(0, listed ? (sc.rankCount || 25) * 2 : 60).filter(r => !valueData[r.symbol]).map(r => r.symbol))
        list = list.map(r => Object.assign(r, card ? Scorecards.score(card, r) : { score: null, total: 0, failed: [] }))
                   .filter(r => Screens.passes(sc, r, "facts"))
        if (listed) list = list.slice(0, sc.rankCount || 25)
        return list
    }
}
