// Watchlist key levels: the fail-and-rebound rule, on 1-minute bars.
//
// A level is a price that matters for the day: the prior day's high, low or
// close, the premarket's high or low, the session's high or low so far, or a
// level drawn on the symbol's chart (double-click the chart). The rule:
//
//   1. FAIL -- the price was at or above the level on the previous bar, and
//      now trades (or, with `failBy` "close", closes) below it by more than
//      the buffer. The setup is armed, at that level's price.
//   2. REBOUND -- within `reboundMinutes` of the fail, the price is back
//      above the level: any trade above it, or a close above it with
//      "close".
//   3. HOLD -- if `holdBars` is set, that many 1-minute bars in a row must
//      close above the level before it alerts; a close back below starts the
//      count again. With 0 it alerts on the rebound.
//   An armed setup lapses `armedMinutes` after the fail. After an alert the
//   same level waits `reboundMinutes` before it can arm again.
//
// Running levels (the session's and the premarket's high and low) are taken
// from the bars before the previous one, and fixed at the price they had
// when the setup armed. A stock is never above its own running high, so the
// previous bar is left out: a bar that closes above the earlier high is a
// breakout, and dropping back under that high is the fail. Undercutting the
// low and reclaiming it compares against the low that was undercut, not the
// new one.
//
// Outside the regular session trading is thin and a single stray trade can
// draw a long wick, or even set a bar's close (SPY 2026-10-23 17:01 ET: a
// 1-minute close of 728.67 on no volume, between bars at 760.95 and 760.96).
// So in premarket and after hours:
//   - the fail and the rebound are judged on 1-minute closes whatever
//     `failBy` says; "trade" applies to the regular session;
//   - a bad print is dropped: a close more than `spikeTimes` the stock's
//     usual 1-minute move away from the previous close (the median of its
//     last 30 moves, and at least `spikeMin`) whose next bar opens back
//     within that of the previous close. Measured against the stock's own
//     moves, a small cap's 5% minute stays; SPY's 4% does not.
//
// Pure functions, shared by the engine (LevelWatch.qml) and the tests
// (tests/test_levels.py).
.pragma library

var kinds = [
    { key: "pdh", name: "Prior-day high" },
    { key: "pdl", name: "Prior-day low" },
    { key: "pdc", name: "Prior-day close" },
    { key: "pmh", name: "Premarket high" },
    { key: "pml", name: "Premarket low" },
    { key: "hod", name: "Session high" },
    { key: "lod", name: "Session low" }
]
function kindName(key) {
    if (String(key).indexOf("m:") === 0) return "Chart level"
    const k = kinds.find(x => x.key === key)
    return k ? k.name : key
}

// The settings a levels screen carries, with their starting values.
var defaults = {
    levelSource: "both",          // "auto" | "manual" | "both"
    autoLevels: ["pdh", "pdl", "pdc", "pmh", "pml", "lod"],
    failBuffer: 0.1,
    failUnit: "pct",              // "pct" of the level | "cents"
    failBy: "trade",              // "trade" | "close"
    reboundMinutes: 10,
    holdBars: 0,
    armedMinutes: 30
}
function rule(screen) {
    const r = {}
    for (const k in defaults) r[k] = screen && screen[k] !== undefined && screen[k] !== null ? screen[k] : defaults[k]
    if (!Array.isArray(r.autoLevels)) r.autoLevels = defaults.autoLevels.slice()
    return r
}
function buffer(r, level) {
    const b = Math.max(0, Number(r.failBuffer) || 0)
    return r.failUnit === "cents" ? b / 100 : level * b / 100
}

// The ET session minute a bar sits in: before 570 (09:30) is premarket,
// 570-959 the regular session, 960 on after hours.
var openMin = 570
var closeMin = 960
var spikeTimes = 8
var spikeMin = 0.01

// The bars with bad prints outside the regular session dropped (see the top
// of this file). A dropped bar is replaced by a flat one at the previous
// close, so the minute is still there.
function clean(bars, etMin) {
    const out = []
    const moves = []
    for (let i = 0; i < bars.length; i++) {
        const b = bars[i], prev = out[i - 1], next = bars[i + 1]
        let x = b
        const m = etMin(b.t)
        if (prev && next && (m < openMin || m >= closeMin) && moves.length >= 10) {
            const sorted = moves.slice(-30).sort((p, q) => p - q)
            const lim = Math.max(spikeMin, spikeTimes * sorted[sorted.length >> 1])
            if (Math.abs(b.c / prev.c - 1) > lim && Math.abs(next.o / prev.c - 1) <= lim)
                x = { t: b.t, o: prev.c, h: prev.c, l: prev.c, c: prev.c }
        }
        if (prev && prev.c > 0) moves.push(Math.abs(x.c / prev.c - 1))
        out.push(x)
    }
    return out
}
// bars:   today's completed 1-minute bars, oldest first: [{t (ms), o, h, l, c}]
// etMin:  function(t ms) -> minutes into the ET day
// daily:  {pdh, pdl, pdc} or null
// manual: [prices] drawn on the chart
// fromT:  only alerts on bars at or after this time are returned (earlier
//         bars still set the state, so a setup armed before a restart counts)
// Returns [{key, name, level, failT, failPrice, t, price}].
function scan(bars, etMin, daily, manual, r, fromT) {
    const fires = []
    if (!bars || bars.length < 2) return fires
    const useAuto = r.levelSource !== "manual", useManual = r.levelSource !== "auto"
    const want = {}
    for (const k of r.autoLevels) want[k] = true
    const st = {}
    let pmh = -Infinity, pml = Infinity, hod = -Infinity, lod = Infinity
    const reboundMs = r.reboundMinutes * 60000, armedMs = r.armedMinutes * 60000
    const hold = Math.max(0, Math.round(r.holdBars) || 0)
    bars = clean(bars, etMin)

    for (let i = 1; i < bars.length; i++) {
        const b = bars[i], prev = bars[i - 1], m = etMin(b.t)
        // Running levels from the bars before the previous one.
        if (i >= 2) {
            const old = bars[i - 2], om = etMin(old.t)
            if (om < openMin) { pmh = Math.max(pmh, old.h); pml = Math.min(pml, old.l) }
            else if (om < closeMin) { hod = Math.max(hod, old.h); lod = Math.min(lod, old.l) }
        }

        const levels = []
        if (useAuto) {
            if (daily) {
                if (want.pdh && daily.pdh > 0) levels.push({ key: "pdh", price: daily.pdh })
                if (want.pdl && daily.pdl > 0) levels.push({ key: "pdl", price: daily.pdl })
                if (want.pdc && daily.pdc > 0) levels.push({ key: "pdc", price: daily.pdc })
            }
            // The premarket's levels are levels once there is a premarket.
            if (want.pmh && isFinite(pmh)) levels.push({ key: "pmh", price: pmh })
            if (want.pml && isFinite(pml)) levels.push({ key: "pml", price: pml })
            // The session's, from the regular session only.
            if (m >= openMin && m < closeMin) {
                if (want.hod && isFinite(hod)) levels.push({ key: "hod", price: hod })
                if (want.lod && isFinite(lod)) levels.push({ key: "lod", price: lod })
            }
        }
        if (useManual) for (const p of (manual || [])) if (p > 0) levels.push({ key: "m:" + p, price: p })

        const byClose = r.failBy === "close" || m < openMin || m >= closeMin
        for (const L of levels) {
            const s = st[L.key] || (st[L.key] = { armed: null, hold: 0, cool: -Infinity })
            if (s.armed && b.t - s.armed.t > armedMs) { s.armed = null; s.hold = 0 }
            if (!s.armed) {
                if (b.t - s.cool < reboundMs) continue
                const buf = buffer(r, L.price)
                const broke = byClose ? b.c < L.price - buf : b.l < L.price - buf
                if (prev.c >= L.price && broke) s.armed = { t: b.t, price: L.price, low: b.l }
                continue
            }
            const level = s.armed.price
            s.armed.low = Math.min(s.armed.low, b.l)
            const back = byClose ? b.c > level : b.h > level
            if (s.hold > 0 || (back && b.t - s.armed.t <= reboundMs)) {
                if (hold === 0) { fire(L.key, s, b, b.c > level ? b.c : level) }
                else if (b.c > level) { s.hold++; if (s.hold >= hold) fire(L.key, s, b, b.c) }
                else s.hold = 0
            }
        }
    }
    function fire(key, s, b, price) {
        if (b.t >= fromT) fires.push({ key: key, name: kindName(key), level: s.armed.price, failT: s.armed.t,
                                       failLow: s.armed.low, t: b.t, price: price })
        s.armed = null
        s.hold = 0
        s.cool = b.t
    }
    return fires
}

// The prior session's high, low and close from daily bars (oldest first,
// [{t, h, l, c}]), skipping today's: `today` is the ET date.
function priorDay(daily, etDay, today) {
    for (let i = daily.length - 1; i >= 0; i--) {
        const d = daily[i]
        if (etDay(d.t) < today && d.h > 0 && d.l > 0 && d.c > 0) return { pdh: d.h, pdl: d.l, pdc: d.c }
    }
    return null
}
