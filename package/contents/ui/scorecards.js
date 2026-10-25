// Scorecards: named sets of rules a screen can score its rows against.
// Shared by the engine (ScreenerEngine.qml), the settings pages
// (configScorecards.qml, configScreener.qml) and the table (Screener.qml).
//
// A scorecard, as stored in the `scorecards` setting (a JSON array):
//   { id, name, rules: [ { name, measure, op, value, value2 } ] }
// `name` on a rule is the short label shown when it fails ("float").
.pragma library

// What a rule can test. `kind` decides the comparisons offered:
//   number -- at least / at most / between
//   flag   -- yes (the row has it)
//   level  -- at most / at least (an ordered rating; the measure has `levels`)
var measures = [
    { key: "price",      name: "Price",                  kind: "number", unit: "$" },
    { key: "change",     name: "Change on the day",      kind: "number", unit: "%" },
    { key: "gap",        name: "Gap",                    kind: "number", unit: "%" },
    { key: "volume",     name: "Volume",                 kind: "number", unit: "shares" },
    { key: "rvol",       name: "Day RVOL",               kind: "number", unit: "×" },
    { key: "rvol5",      name: "5-min RVOL",             kind: "number", unit: "%" },
    { key: "float",      name: "Float",                  kind: "number", unit: "shares" },
    { key: "shortFloat", name: "Short % of float",       kind: "number", unit: "%" },
    { key: "marketCap",  name: "Market cap",             kind: "number", unit: "$" },
    { key: "newsAge",    name: "Headline within",        kind: "number", unit: "hours" },
    { key: "catalyst",   name: "Press-wire news, 2 days", kind: "flag" },
    { key: "dilution",   name: "Dilution rating",        kind: "level", levels: ["LOW", "MEDIUM", "HIGH", "EXTREME"] },
    // The theme the row belongs to, and how hot that theme is (themes.js).
    // `themeStatus` is ordered worst to best, so "at least building" is a
    // rule; the rest are plain numbers.
    { key: "themeStatus",  name: "Theme",                 kind: "level", levels: ["burnt", "quiet", "building", "hot"] },
    { key: "themeMembers", name: "Theme members today",   kind: "number", unit: "stocks" },
    { key: "themeRan",     name: "Theme members that ran", kind: "number", unit: "stocks" },
    { key: "themeFollow",  name: "Theme follow-through",  kind: "number", unit: "%" },
    { key: "themeMove",    name: "Theme median peak",     kind: "number", unit: "%" },
    { key: "themeLift",    name: "Theme vs its baseline", kind: "number", unit: "×" },
    { key: "themeStreak",  name: "Theme day",             kind: "number", unit: "days" },
    { key: "themeShells",  name: "Theme serial issuers",  kind: "number", unit: "%" },
    { key: "themeFreshPct", name: "Theme names new to it", kind: "number", unit: "%" },
    // The row's sector (or a crypto pair's category), heat-mapped the same way.
    { key: "sectorStatus",  name: "Sector",                kind: "level", levels: ["burnt", "quiet", "building", "hot"] },
    { key: "sectorMembers", name: "Sector members today",  kind: "number", unit: "stocks" },
    { key: "sectorRan",     name: "Sector members that ran", kind: "number", unit: "stocks" },
    { key: "sectorFollow",  name: "Sector follow-through", kind: "number", unit: "%" },
    { key: "sectorMove",    name: "Sector median peak",    kind: "number", unit: "%" },
    // Long-term fundamentals (SEC filings, through the scanner).
    { key: "p1", name: "5-year P/E under 22.5",            kind: "flag" },
    { key: "p2", name: "ROIC 9% or more",                  kind: "flag" },
    { key: "p3", name: "Share count falling (5 yrs)",      kind: "flag" },
    { key: "p4", name: "Free cash flow growing",           kind: "flag" },
    { key: "p5", name: "Net income growing",               kind: "flag" },
    { key: "p6", name: "Revenue growing",                  kind: "flag" },
    { key: "p7", name: "LT liabilities under 5× FCF",      kind: "flag" },
    { key: "p8", name: "Price / FCF under 22.5",           kind: "flag" }
]
var ops = {
    number: [ { key: ">=", name: "at least" }, { key: "<=", name: "at most" }, { key: "between", name: "between" } ],
    flag:   [ { key: "yes", name: "yes" } ],
    level:  [ { key: "<=", name: "at most" }, { key: ">=", name: "at least" } ]
}
// Kept for callers that still name it; a measure now carries its own `levels`.
var levels = ["LOW", "MEDIUM", "HIGH", "EXTREME"]

// An ordered rating's steps, or null when the measure is not one.
function levelsOf(key) {
    const m = measure(key)
    return m && m.levels ? m.levels : null
}
// A rule's target as a position in that order, so "at least building" and
// "at most HIGH" both compare as numbers.
function levelIndex(key, v) {
    const L = levelsOf(key)
    if (!L) return v
    const i = L.indexOf(v)
    return i >= 0 ? i : (typeof v === "number" ? v : -1)
}

function measure(key) {
    for (let i = 0; i < measures.length; i++) if (measures[i].key === key) return measures[i]
    return measures[0]
}
function known(v) { return typeof v === "number" && isFinite(v) }

// The figure a rule tests, or undefined when it is not known yet.
function figure(r, key) {
    if (key === "newsAge") return r.newsTime ? (Date.now() - r.newsTime) / 3600000 : (r.factsKnown ? Infinity : undefined)
    if (key === "catalyst") return r.factsKnown ? !!r.catalyst : undefined
    if (/^p[1-8]$/.test(key)) {
        // From the value look-up: true / false, or unknown ("not recorded").
        const p = (r.value && r.value.pillars || []).find(x => "p" + x.n === key)
        return p && p.passed !== null && p.passed !== undefined ? p.passed : undefined
    }
    if (key === "dilution") {
        const i = r.dilution ? levelIndex("dilution", r.dilution.risk) : -1
        return i >= 0 ? i : undefined
    }
    // A row with no theme fails every theme rule rather than passing it by
    // default: "the theme is hot" must not be true of a stock that has none.
    if (key.indexOf("theme") === 0 && !r.theme) return undefined
    if (key.indexOf("sector") === 0 && !r.sector) return undefined
    return known(r[key]) ? r[key] : undefined
}

// Does row `r` pass one rule? true / false, or undefined when unknown.
function test(rule, r) {
    const v = figure(r, rule.measure)
    if (v === undefined) return undefined
    switch (rule.op) {
    case ">=":      return v >= levelIndex(rule.measure, rule.value)
    case "<=":      return v <= levelIndex(rule.measure, rule.value)
    case "between": return v >= rule.value && v <= rule.value2
    case "yes":     return v === true
    }
    return undefined
}

// {score, total, failed}: rules passed, rules in all, and the names of the
// ones that did not -- "float?" where the figure is not known yet, which
// counts as not passed.
function score(card, r) {
    const failed = []
    let passed = 0
    for (let i = 0; i < card.rules.length; i++) {
        const rule = card.rules[i]
        const t = test(rule, r)
        if (t === true) passed++
        else failed.push(t === undefined ? rule.name + "?" : rule.name)
    }
    return { score: passed, total: card.rules.length, failed: failed }
}

// "price $1–$20", "float ≤ 10M", "news" -- for the table's footer.
function describe(rule) {
    const m = measure(rule.measure)
    const f = v => (m.unit === "$" ? "$" : "") + fmt(v) + (m.unit === "%" ? "%" : m.unit === "×" ? "×" : m.unit === "hours" ? " h" : "")
    switch (rule.op) {
    case ">=":      return rule.name + " ≥ " + (levelsOf(rule.measure) ? rule.value : f(rule.value))
    case "<=":      return rule.name + " ≤ " + (levelsOf(rule.measure) ? rule.value : f(rule.value))
    case "between": return rule.name + " " + f(rule.value) + "–" + f(rule.value2)
    }
    return rule.name
}
// A rule's figure for row `r`, as shown beside the rule in the detail view.
function valueText(rule, r) {
    const v = r[rule.measure]
    switch (rule.measure) {
    case "price":      return known(v) ? "$" + v.toFixed(2) : "not known"
    case "change":
    case "gap":
    case "shortFloat": return known(v) ? (v >= 0 && rule.measure !== "shortFloat" ? "+" : "") + v.toFixed(1) + "%" : "not known"
    case "rvol":       return known(v) ? v.toFixed(2) + "×" : "not known"
    case "rvol5":      return known(v) ? Math.round(v) + "%" : "not known"
    case "volume":
    case "float":      return known(v) ? fmt(v) : "not known"
    case "marketCap":  return known(v) ? "$" + fmt(v) : "not known"
    case "newsAge":    return r.newsTime ? Math.round((Date.now() - r.newsTime) / 3600000) + " h ago" : (r.factsKnown ? "none" : "not known")
    case "catalyst":   return r.factsKnown ? (r.catalyst ? "yes" : "none in 2 days") : "not known"
    case "dilution":   return r.dilution ? r.dilution.risk : "not known"
    case "themeStatus":   return r.theme && r.themeHeat
                                 ? r.theme.name + " — " + r.themeHeat.status : "no theme"
    case "themeMembers":
    case "themeRan":
    case "themeStreak":   return r.theme ? String(v) : "no theme"
    case "themeFollow":
    case "themeShells":
    case "themeFreshPct": return r.theme && known(v) ? Math.round(v) + "%" : "no theme"
    case "themeMove":     return r.theme && known(v) ? "+" + Math.round(v) + "%" : "no theme"
    case "themeLift":     return r.theme && known(v) ? (Math.round(v * 10) / 10) + "×" : "no baseline yet"
    case "sectorStatus":  return r.sector && r.sectorHeat ? r.sector.name + " — " + r.sectorHeat.status : "no sector"
    case "sectorMembers":
    case "sectorRan":     return r.sector ? String(v) : "no sector"
    case "sectorFollow":  return r.sector && known(v) ? Math.round(v) + "%" : "no sector"
    case "sectorMove":    return r.sector && known(v) ? "+" + Math.round(v) + "%" : "no sector"
    }
    if (/^p[1-8]$/.test(rule.measure)) {
        const p = (r.value && r.value.pillars || []).find(x => "p" + x.n === rule.measure)
        return p ? String(p.value) : "not known"
    }
    return ""
}
// A rule's target in words: "$1–$20", "≥ 10%", "≤ 10M", "yes".
function targetText(rule) {
    const d = describe(rule)
    return d.indexOf(rule.name) === 0 ? d.slice(rule.name.length).trim() || "yes" : d
}

function fmt(v) {
    if (!known(v)) return ""
    const a = Math.abs(v), trim = x => String(Math.round(x * 100) / 100)
    if (a >= 1e9) return trim(v / 1e9) + "B"
    if (a >= 1e6) return trim(v / 1e6) + "M"
    if (a >= 1e3 && v % 1000 === 0) return trim(v / 1e3) + "K"
    return trim(v)
}

// The starting scorecard: small-cap momentum, the rules the trade
// journal's rule check scores (premarket-scanner trade_stats.py) with the
// price band from the older settings.
function defaults(cfg) {
    return [ {
        id: "momentum", name: "Small-cap momentum",
        rules: [
            { name: "price", measure: "price",    op: "between", value: cfg.screenPriceMin || 1, value2: cfg.screenPriceMax || 20 },
            { name: "chg",   measure: "change",   op: ">=", value: 10 },
            { name: "RVOL",  measure: "rvol",     op: ">=", value: 5 },
            { name: "float", measure: "float",    op: "<=", value: 10e6 },
            { name: "news",  measure: "catalyst", op: "yes" }
        ]
    }, deepValue(), themeCard() ]
}
// The theme scorecard: is the story this row belongs to actually live? Each
// rule is one of the readings behind the theme glyph, so a row can be scored
// on its theme the way a value name is scored on its fundamentals.
//
// `themeStatus >= building` does most of the work; the rest say why, and are
// what to loosen or tighten while the thing is being tuned.
function themeCard() {
    return { id: "theme", name: "Theme heat", rules: [
        { name: "live",    measure: "themeStatus",   op: ">=", value: "building" },
        { name: "members", measure: "themeMembers",  op: ">=", value: 2 },
        { name: "ran",     measure: "themeFollow",   op: ">=", value: 40 },
        { name: "move",    measure: "themeMove",     op: ">=", value: 30 },
        { name: "fresh",   measure: "themeFreshPct", op: ">=", value: 50 },
        { name: "shells",  measure: "themeShells",   op: "<=", value: 50 }
    ] }
}
// The long-term value scorecard: eight fundamental checks from SEC filings.
function deepValue() {
    return { id: "deepvalue", name: "Deep Value 8", rules: [
        { name: "P/E",      measure: "p1", op: "yes" },
        { name: "ROIC",     measure: "p2", op: "yes" },
        { name: "shares",   measure: "p3", op: "yes" },
        { name: "FCF",      measure: "p4", op: "yes" },
        { name: "earnings", measure: "p5", op: "yes" },
        { name: "revenue",  measure: "p6", op: "yes" },
        { name: "debt",     measure: "p7", op: "yes" },
        { name: "P/FCF",    measure: "p8", op: "yes" }
    ] }
}

function load(cfg) {
    try {
        const list = JSON.parse(cfg.scorecards || "[]")
        // A hand-edited card may have no rules list; it scores as having none.
        const l = Array.isArray(list) ? list.filter(c => c && typeof c === "object")
            .map(c => Array.isArray(c.rules) ? c : Object.assign({}, c, { rules: [] })) : []
        if (l.length) return l
    } catch (e) {}
    return defaults(cfg)
}
function find(list, id) {
    for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i]
    return null
}
function newId() { return "c" + Date.now().toString(36) }
