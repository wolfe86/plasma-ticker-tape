// Screens: what each one is, the filters a screen can use, and the starting
// list. Shared by the engine (ScreenerEngine.qml), the settings page
// (configScreener.qml) and the table (Screener.qml).
//
// A screen, as stored in the `screens` setting (a JSON array):
//   { id, name,
//     type:      "running" | "hod" | "ranked" | "value",
//     runPct, runWindow,        // running: rise % within minutes
//     rankBy, rankCount,        // ranked: measure and how many rows
//     rankLow,                  // ranked: true lists the lowest first
//     filters:   { key: number } -- see filterDefs; a missing key is off
//     scorecard: "" (none) or a scorecard's id (scorecards.js)
//     sound:     a path from sounds.js, or "" }
.pragma library

var types = [
    { key: "running", name: "Alert: running up" },
    { key: "hod",     name: "Alert: new high of day" },
    { key: "ranked",  name: "Ranked list" },
    { key: "value",   name: "Long-term value list" }
]

var rankMeasures = [
    { key: "change", name: "Change %" },
    { key: "gap",    name: "Gap %" },
    { key: "volume", name: "Volume" },
    { key: "rvol",   name: "Day RVOL" },
    { key: "rvol5",  name: "5-min RVOL" }
]

// `measure` is the row field tested. `facts` marks a figure that arrives
// after the alert (Finviz/Yahoo look-ups): such a filter passes until the
// figure is known, then hides the row if it fails. A quote figure that is
// not known (no premarket volume, say) also passes rather than blocking.
var filterDefs = [
    { key: "priceMin",  label: "Price at least",          measure: "price",      op: ">=", unit: "$" },
    { key: "priceMax",  label: "Price at most",           measure: "price",      op: "<=", unit: "$" },
    { key: "changeMin", label: "Change on the day ≥",     measure: "change",     op: ">=", unit: "%" },
    { key: "changeMax", label: "Change on the day ≤",     measure: "change",     op: "<=", unit: "%" },
    { key: "gapMin",    label: "Gap at least",            measure: "gap",        op: ">=", unit: "%" },
    // Volume must be known to pass: premarket it is known only for stocks
    // on the scanner's list, which is what makes it the filter
    // that separates a stock really trading from a thin quote ticking.
    { key: "volumeMin", label: "Volume at least",         measure: "volume",     op: ">=", unit: "shares", required: true },
    // The way past "Volume at least" for a stock whose volume is not known
    // (premarket, anything off the scanner's top-20 lists): it passes if it
    // is up this much on the day. Only read alongside volumeMin.
    { key: "noVolChangeMin", label: "…or, volume short, change ≥", measure: "change", op: "novol", unit: "%" },
    // The same way past it for a bounce: a stock red on the day but this far
    // above its session low (AARD 2026-10-23, $2.30 to $2.90 while -27%).
    { key: "noVolBounceMin", label: "…or, volume short, above session low ≥", measure: "offLow", op: "novol", unit: "%" },
    { key: "rvolMin",   label: "Day RVOL at least",       measure: "rvol",       op: ">=", unit: "×" },
    // Premarket, 5-minute volume is known only for stocks on the premarket
    // scanner's list; where it is not known the filter passes.
    { key: "rvol5Min",  label: "5-min RVOL at least",     measure: "rvol5",      op: ">=", unit: "%" },
    { key: "capMin",    label: "Market cap at least",     measure: "marketCap",  op: ">=", unit: "$" },
    { key: "capMax",    label: "Market cap at most",      measure: "marketCap",  op: "<=", unit: "$" },
    { key: "floatMin",  label: "Float at least",          measure: "float",      op: ">=", unit: "shares", facts: true },
    { key: "floatMax",  label: "Float at most",           measure: "float",      op: "<=", unit: "shares", facts: true },
    { key: "shortMin",  label: "Short % of float ≥",      measure: "shortFloat", op: ">=", unit: "%", facts: true },
    { key: "newsHours", label: "News within",             measure: "newsTime",   op: "age", unit: "hours", facts: true },
    // The screen's own scorecard: rows passing fewer rules are hidden.
    { key: "scoreMin",  label: "Scorecard score at least", measure: "score",     op: ">=", unit: "rules", facts: true },
    // Long-term value list only. Fundamentals from SEC filings; the trend
    // checks from the daily moving averages.
    { key: "valueMin",   label: "Fundamental checks passed ≥", measure: "valuePassed", op: ">=", unit: "of 8", value: true },
    { key: "pfcfPass",   label: "Price / FCF check passes", measure: "pfcfOk",      op: "flag", value: true },
    { key: "valuation",  label: "Both valuation checks pass", measure: "valuationOk", op: "flag", value: true },
    { key: "offHighMin", label: "Below 52-week high by ≥",  measure: "offHigh",      op: ">=", unit: "%", value: true },
    { key: "above50",    label: "Price above 50-day avg",  measure: "above50",      op: "flag", value: true },
    { key: "below200",   label: "50-day still below 200-day", measure: "below200",  op: "flag", value: true },
    { key: "turningUp",  label: "50-day avg turning up",   measure: "turningUp",    op: "flag", value: true }
]

function known(v) { return typeof v === "number" && isFinite(v) }

// Does row `r` pass the screen's filters? `stage` is "quote" (at alert
// time) or "facts" (once look-ups have arrived).
function passes(screen, r, stage) {
    const f = screen.filters || {}
    for (let i = 0; i < filterDefs.length; i++) {
        const d = filterDefs[i]
        const want = f[d.key]
        if (!known(want) || !!d.facts !== (stage === "facts")) continue
        if (d.op === "flag") {
            // A trend or valuation check must be known to pass.
            if (r[d.measure] !== true) return false
            continue
        }
        if (d.op === "age") {
            // Only judged once the news look-up has run.
            if (!r.factsKnown) continue
            if (!r.newsTime || Date.now() - r.newsTime > want * 3600000) return false
            continue
        }
        const v = r[d.measure]
        if (d.op === "novol") continue          // read by volumeMin below
        // volumeMin's ways past: the premarket list's volume is missing for
        // most stocks and lags for the rest (YMAT 2026-10-23: 6,576 on the
        // list against 5.95M traded), so a stock short of the volume, known
        // or not, still passes on its change or its bounce off the low.
        if (d.key === "volumeMin" && !(known(v) && v >= want)) {
            if (known(f.noVolChangeMin) && known(r.change) && r.change >= f.noVolChangeMin) continue
            if (known(f.noVolBounceMin) && known(r.offLow) && r.offLow >= f.noVolBounceMin) continue
            return false
        }
        if (!known(v)) {
            if (d.required) return false
            continue
        }
        if (d.op === ">=" && !(v >= want)) return false
        if (d.op === "<=" && !(v <= want)) return false
    }
    return true
}

// "10M" -> 10000000, "1.5" -> 1.5, "" -> null.
function parseNum(text) {
    const m = String(text || "").trim().replace(/[$,%×\s]/g, "").match(/^(-?[\d.]+)([kmb])?$/i)
    if (!m) return null
    const mult = { k: 1e3, m: 1e6, b: 1e9 }[(m[2] || "").toLowerCase()] || 1
    const v = parseFloat(m[1]) * mult
    return isFinite(v) ? v : null
}
// 10000000 -> "10M", 1.5 -> "1.5".
function fmtNum(v) {
    if (!known(v)) return ""
    const a = Math.abs(v)
    const trim = x => String(Math.round(x * 100) / 100)
    if (a >= 1e9) return trim(v / 1e9) + "B"
    if (a >= 1e6) return trim(v / 1e6) + "M"
    if (a >= 1e3 && v % 1000 === 0) return trim(v / 1e3) + "K"
    return trim(v)
}

// The starting list, from the settings the three fixed screens used before
// screens could be edited, so nothing changes until the user changes it.
function defaults(cfg) {
    return [
        { id: "running", name: "Running Up", type: "running",
          runPct: cfg.runPct, runWindow: cfg.runWindow,
          filters: {}, scorecard: "momentum", sound: cfg.runSound },
        { id: "hod", name: "High of Day", type: "hod",
          filters: { priceMin: cfg.screenPriceMin, priceMax: cfg.screenPriceMax,
                     changeMin: cfg.hodMinChange, rvolMin: cfg.hodMinRvol },
          scorecard: "momentum", sound: cfg.hodSound },
        { id: "gainers", name: "Top Gainers", type: "ranked",
          rankBy: "change", rankCount: 25,
          filters: {}, scorecard: "", sound: "" },
        topLosers(),
        deepValue()
    ]
}

// The inverse of Top Gainers: the pool's biggest fallers on the day.
function topLosers() {
    return { id: "losers", name: "Top Losers", type: "ranked", rankBy: "change", rankLow: true,
             rankCount: 25, filters: {}, scorecard: "", sound: "" }
}

// Long-term: companies whose fundamentals mostly pass, cheap on price to
// free cash flow, beaten down (15%+ under the 52-week high) and starting to
// recover (back above the 50-day average).
//
// Changed 2026-10-22, the day it was built. The first rules also required
// both valuation checks, the 50-day still under the 200-day and the 50-day
// sloping up -- and threw out ADBE (8/8, P/FCF 10.7, 26% off its high,
// back above its 50-day): the 50-day lags the price by weeks, so an early
// recovery still shows a falling, just-crossed average. The 5-year P/E
// check also runs high on software, where stock pay and write-offs depress
// reported earnings, so price to free cash flow is the cheapness test.
// Both stricter rules remain as filters to tick.
function deepValue() {
    return { id: "deepvalue", name: "Deep Value Recovery", type: "value", rankCount: 50,
             filters: deepValueFilters(), scorecard: "deepvalue", sound: "" }
}
function deepValueFilters() { return { valueMin: 6, pfcfPass: 1, offHighMin: 15, above50: 1 } }
// The rules the screen first shipped with, for updating saved copies.
var deepValueFiltersV1 = { valueMin: 6, valuation: 1, above50: 1, below200: 1, turningUp: 1 }

function load(cfg) {
    try {
        const list = JSON.parse(cfg.screens || "[]")
        if (Array.isArray(list) && list.length) return list
    } catch (e) {}
    return defaults(cfg)
}

function newId() {
    return "s" + Date.now().toString(36)
}
