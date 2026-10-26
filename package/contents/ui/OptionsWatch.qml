// Unusual options activity on the watchlist: the "uoa" screens (Settings →
// Screeners, type "Alert: unusual options (watchlist)"). Every 15 minutes in
// the regular session it reads the option chains of the watched stocks --
// the nearest `uoaExpiries` expiries, from Yahoo, delayed about 15 minutes
// -- and alerts on each contract trading at least `uoaMinVolume` contracts,
// `uoaRatio` times its open interest or more, worth `uoaMinNotional` dollars
// or more (volume × mid price × 100). Trading well past the open interest
// means new positions are being opened, not old ones closed.
//
// The whole market is out of reach this way: one request per stock and
// expiry. So it watches the watchlist, plus each screen's own tickers.
// A contract alerts once a day, and again if its volume doubles.

import QtQuick
import "options.js" as Options
import "screens.js" as Screens

Item {
    id: uw

    required property var engine
    required property var ticker
    readonly property var screens: engine.screens.filter(s => s.type === "uoa")
    readonly property bool on: screens.length > 0
    readonly property bool live: on && !!engine.cfg.optionsFeature && engine.currentPhase === "regular"

    function watchable(sym) { return /^[A-Z][A-Z0-9.\-]{0,9}$/.test(sym) && !/-USD$/.test(sym) }
    function extras(sc) { return String(sc.levelTickers || "").toUpperCase().split(/[\s,;]+/).filter(t => t && watchable(t)) }
    function screenWatches(sc, sym) {
        return extras(sc).indexOf(sym) >= 0 || (sc.levelWatchlist !== false && ticker.symbols.some(s => s.symbol === sym))
    }
    readonly property var symbols: {
        const out = []
        for (const s of ticker.symbols) if (watchable(s.symbol) && out.indexOf(s.symbol) < 0) out.push(s.symbol)
        for (const sc of screens) for (const t of extras(sc)) if (out.indexOf(t) < 0) out.push(t)
        return out
    }

    property var seen: ({})        // "screen|contractSymbol" -> volume when it last alerted, today
    property string day: ""
    Timer {
        interval: 15 * 60000
        repeat: true
        triggeredOnStart: true
        running: uw.live
        onTriggered: uw.pull()
    }
    property var queue: []
    property int busy: 0
    function pull() {
        const today = engine.etDay(Date.now() / 1000)
        if (today !== day) { day = today; seen = ({}) }
        queue = symbols.slice()
        pump()
    }
    function pump() {
        while (busy < 2 && queue.length) {
            const sym = queue.shift()
            busy++
            scan(sym, () => { busy--; pump() })
        }
    }
    readonly property int expiries: Math.max(1, ...screens.map(s => s.uoaExpiries || 2))
    function scan(sym, done) {
        const ws = ticker.workspace
        ws.optionChain(sym, "", first => {
            if (!first) { done(); return }
            const exps = first.expirations.slice(0, expiries)
            let left = exps.length
            const chains = []
            if (!left) { done(); return }
            for (const e of exps) {
                const take = c => { if (c) chains.push(c); if (--left === 0) { judge(sym, chains); done() } }
                if (e === first.expiration) take(first); else ws.optionChain(sym, e, take)
            }
        })
    }
    function judge(sym, chains) {
        for (const sc of screens) {
            if (!screenWatches(sc, sym)) continue
            const minVol = sc.uoaMinVolume || 500, ratio = sc.uoaRatio || 3, minNotional = sc.uoaMinNotional || 50000
            const n = Math.max(1, sc.uoaExpiries || 2)
            for (const c of chains.slice(0, n)) {
                const S = c.quote.regularMarketPrice
                for (const u of Options.unusual(c.calls, c.puts, minVol, ratio)) {
                    const m = Options.mid(u)
                    const notional = u.volume * (isFinite(m) ? m : 0) * Options.multiplier
                    if (notional < minNotional) continue
                    const key = sc.id + "|" + u.contractSymbol
                    if (seen[key] && u.volume < seen[key] * 2) continue
                    seen[key] = u.volume
                    const exp = Qt.formatDate(new Date(u.expiration * 1000), "d MMM")
                    const row = {
                        symbol: sym, market: "stocks", name: c.quote.shortName || sym,
                        price: S, change: c.quote.regularMarketChangePercent,
                        contract: u.strike + (u.type === "call" ? "C " : "P ") + exp,
                        optType: u.type, strike: u.strike, expiry: u.expiration * 1000,
                        optVolume: u.volume, openInterest: u.openInterest || 0, voi: u.ratio,
                        notional: notional, optMid: m, optIv: u.impliedVolatility
                    }
                    const what = i18n("%1 %2 %3", u.strike, u.type === "call" ? i18n("call") : i18n("put"), exp)
                    const vol = u.volume.toLocaleString(Qt.locale(), "f", 0)
                    const tail = i18n("about $%1 at %2, IV %3%", Math.round(notional).toLocaleString(Qt.locale(), "f", 0),
                                      isFinite(m) ? m.toFixed(2) : "?", u.impliedVolatility > 0 ? Math.round(u.impliedVolatility * 100) : "?")
                    // No open interest yet: every contract traded is new.
                    row.detailText = (u.openInterest || 0) > 0
                        ? i18n("%1: %2 traded against %3 open (%4×), %5", what, vol, u.openInterest.toLocaleString(Qt.locale(), "f", 0), u.ratio.toFixed(1), tail)
                        : i18n("%1: %2 traded, no open interest before today, %3", what, vol, tail)
                    if (Screens.passes(sc, engine.inCurrency(sc, row), "quote")) engine.raise(sc.id, row)
                }
            }
        }
    }
}
