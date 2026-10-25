// Options: the maths and the readings taken from a chain. No data here; the
// chain comes from Yahoo (OptionsView.qml), legs from the trade builder.
//
// PRICING is Black-Scholes for European options on a stock without
// dividends: close enough for the Greeks and probabilities of US equity
// options a trader reads at a glance, not for pricing early exercise or
// dividend effects. Rates and volatility are annual (0.045, 0.36); time is
// in years.
//
// A LEG is {type: "call" | "put" | "stock", side: 1 (buy) | -1 (sell),
// strike, premium (per share), qty (contracts, or shares for stock), expiry
// (ms), iv (annual, optional)}. Contracts are 100 shares.
//
// FROM A CHAIN (Yahoo's v7 options: per contract strike, bid, ask,
// lastPrice, volume, openInterest, impliedVolatility):
//   atmIv          -- the call's and put's IV at the strike nearest the price
//   expectedMove   -- the at-the-money straddle's mid price: the move the
//                     market prices in by that expiry, ± dollars and %
//   maxPain        -- the strike where option holders, by open interest,
//                     would collect least at expiry
//   oiLevels       -- the strikes with the most open interest
//   unusual        -- contracts trading far more than their open interest
.pragma library

var multiplier = 100

// ── normal distribution ──
function normPdf(x) { return Math.exp(-x * x / 2) / Math.sqrt(2 * Math.PI) }
// Abramowitz and Stegun 26.2.17, accurate to about 7.5e-8.
function normCdf(x) {
    const k = 1 / (1 + 0.2316419 * Math.abs(x))
    const poly = k * (0.319381530 + k * (-0.356563782 + k * (1.781477937 + k * (-1.821255978 + k * 1.330274429))))
    const p = 1 - normPdf(x) * poly
    return x >= 0 ? p : 1 - p
}

// ── Black-Scholes ──
// Price and Greeks per share. theta is per calendar day, vega per 1 point
// of volatility (0.01), rho per 1 point of rate.
function bs(type, S, K, T, r, sigma) {
    if (!(S > 0 && K > 0)) return null
    const call = type === "call"
    if (!(T > 0) || !(sigma > 0)) {
        const intrinsic = Math.max(0, call ? S - K : K - S)
        return { price: intrinsic, delta: intrinsic > 0 ? (call ? 1 : -1) : 0, gamma: 0, theta: 0, vega: 0, rho: 0, d1: NaN, d2: NaN }
    }
    const sq = sigma * Math.sqrt(T)
    const d1 = (Math.log(S / K) + (r + sigma * sigma / 2) * T) / sq
    const d2 = d1 - sq
    const disc = Math.exp(-r * T)
    const price = call ? S * normCdf(d1) - K * disc * normCdf(d2) : K * disc * normCdf(-d2) - S * normCdf(-d1)
    const delta = call ? normCdf(d1) : normCdf(d1) - 1
    const gamma = normPdf(d1) / (S * sq)
    const thetaYear = -S * normPdf(d1) * sigma / (2 * Math.sqrt(T)) + (call ? -r * K * disc * normCdf(d2) : r * K * disc * normCdf(-d2))
    const vega = S * normPdf(d1) * Math.sqrt(T) / 100
    const rho = (call ? K * T * disc * normCdf(d2) : -K * T * disc * normCdf(-d2)) / 100
    return { price: price, delta: delta, gamma: gamma, theta: thetaYear / 365, vega: vega, rho: rho, d1: d1, d2: d2 }
}

// The volatility that prices the option at `price`, by bisection; NaN if
// the price is outside what any volatility gives.
function impliedVol(type, price, S, K, T, r) {
    if (!(price > 0 && T > 0)) return NaN
    let lo = 0.001, hi = 5
    const f = v => bs(type, S, K, T, r, v).price - price
    if (f(lo) > 0 || f(hi) < 0) return NaN
    for (let i = 0; i < 100; i++) {
        const mid = (lo + hi) / 2
        if (f(mid) > 0) hi = mid; else lo = mid
        if (hi - lo < 1e-6) break
    }
    return (lo + hi) / 2
}

// Chance the option finishes in the money (risk-neutral): N(d2) for a call,
// N(-d2) for a put.
function probItm(type, S, K, T, r, sigma) {
    if (!(T > 0 && sigma > 0)) return (type === "call" ? S > K : S < K) ? 1 : 0
    const d2 = (Math.log(S / K) + (r - sigma * sigma / 2) * T) / (sigma * Math.sqrt(T))
    return type === "call" ? normCdf(d2) : normCdf(-d2)
}

// ── a position ──
function years(expiry, now) { return Math.max(0, (expiry - now) / (365 * 86400000)) }
function units(l) { return (l.type === "stock" ? 1 : multiplier) * (l.qty || 0) * (l.side || 1) }
// What the position cost to open: positive is paid (a debit), negative
// received (a credit). In dollars.
function netCost(legs) {
    return legs.reduce((a, l) => a + units(l) * (l.type === "stock" ? l.strike : l.premium || 0), 0)
}
// Profit or loss at expiry with the stock at S, in dollars.
function payoff(legs, S) {
    let v = 0
    for (const l of legs) {
        const value = l.type === "stock" ? S : l.type === "call" ? Math.max(0, S - l.strike) : Math.max(0, l.strike - S)
        v += units(l) * value
    }
    return v - netCost(legs)
}
// Profit or loss now (or at `when`), priced with each leg's volatility.
function valueAt(legs, S, when, r, fallbackIv) {
    let v = 0
    for (const l of legs) {
        if (l.type === "stock") { v += units(l) * S; continue }
        const T = years(l.expiry, when)
        const p = bs(l.type, S, l.strike, T, r, l.iv > 0 ? l.iv : fallbackIv)
        v += units(l) * (p ? p.price : 0)
    }
    return v - netCost(legs)
}
// The position's Greeks, in dollars: delta in shares-equivalent dollars per
// $1 move, gamma per $1, theta per day, vega per vol point.
function greeks(legs, S, now, r, fallbackIv) {
    const g = { delta: 0, gamma: 0, theta: 0, vega: 0 }
    for (const l of legs) {
        if (l.type === "stock") { g.delta += units(l); continue }
        const p = bs(l.type, S, l.strike, years(l.expiry, now), r, l.iv > 0 ? l.iv : fallbackIv)
        if (!p) continue
        g.delta += units(l) * p.delta
        g.gamma += units(l) * p.gamma
        g.theta += units(l) * p.theta
        g.vega += units(l) * p.vega
    }
    return g
}
// The prices the payoff is worked out over: wide enough to show every
// strike and a good move either way.
function range(legs, S) {
    const ks = legs.filter(l => l.strike > 0).map(l => l.strike).concat([S])
    const lo = Math.min(...ks), hi = Math.max(...ks)
    const pad = Math.max((hi - lo) * 0.5, S * 0.25)
    return { lo: Math.max(0, lo - pad), hi: hi + pad }
}
// Break-even prices at expiry: where the payoff crosses zero.
function breakevens(legs, S) {
    const rg = range(legs, S), n = 2000, out = []
    let px = rg.lo, pv = payoff(legs, px)
    for (let i = 1; i <= n; i++) {
        const x = rg.lo + (rg.hi - rg.lo) * i / n, v = payoff(legs, x)
        if ((pv < 0 && v >= 0) || (pv > 0 && v <= 0)) out.push(Math.round((px + (x - px) * (-pv / ((v - pv) || 1))) * 100) / 100)
        px = x; pv = v
    }
    return out
}
// Best and worst outcome at expiry. Unlimited when the payoff keeps rising
// (or falling) past the widest strike: a long call, a short call, stock.
function extremes(legs, S) {
    const rg = range(legs, S)
    let best = -Infinity, worst = Infinity
    for (let i = 0; i <= 400; i++) {
        const v = payoff(legs, rg.lo + (rg.hi - rg.lo) * i / 400)
        best = Math.max(best, v); worst = Math.min(worst, v)
    }
    // Slope beyond the highest strike: calls and stock keep it moving.
    const up = legs.reduce((a, l) => a + (l.type === "put" ? 0 : units(l)), 0)
    const down = payoff(legs, 0)          // a put's worth is capped at the strike
    worst = Math.min(worst, down)
    best = Math.max(best, down)
    return { best: up > 0 ? Infinity : best, worst: up < 0 ? -Infinity : worst }
}
// Chance of any profit at expiry, from the lognormal spread the volatility
// implies (risk-neutral, rate r). Integrated over the payoff range.
function probProfit(legs, S, T, r, sigma) {
    if (!(T > 0 && sigma > 0)) return payoff(legs, S) > 0 ? 1 : 0
    const rg = range(legs, S)
    const lo = Math.max(1e-6, Math.min(rg.lo, S * Math.exp(-6 * sigma * Math.sqrt(T))))
    const hi = Math.max(rg.hi, S * Math.exp(6 * sigma * Math.sqrt(T)))
    const n = 4000, mu = Math.log(S) + (r - sigma * sigma / 2) * T, sd = sigma * Math.sqrt(T)
    let p = 0, prevCdf = normCdf((Math.log(lo) - mu) / sd)
    for (let i = 1; i <= n; i++) {
        const a = lo + (hi - lo) * (i - 1) / n, b = lo + (hi - lo) * i / n
        const c = normCdf((Math.log(b) - mu) / sd)
        if (payoff(legs, (a + b) / 2) > 0) p += c - prevCdf
        prevCdf = c
    }
    if (payoff(legs, hi * 2) > 0) p += 1 - prevCdf
    return Math.max(0, Math.min(1, p))
}
// How many contracts (or lots of the whole position) fit the risk:
// `account` × `riskPct` % ÷ the most one lot can lose. 0 when one lot
// already risks more, or when the loss is unlimited.
function sizing(account, riskPct, worstPerLot) {
    const budget = account * riskPct / 100
    if (!(budget > 0) || !isFinite(worstPerLot)) return { budget: budget, lots: 0 }
    const loss = Math.abs(Math.min(0, worstPerLot))
    return { budget: budget, lots: loss > 0 ? Math.floor(budget / loss) : 0 }
}

// ── readings from a chain ──
function mid(c) {
    if (!c) return NaN
    if (c.bid > 0 && c.ask > 0) return (c.bid + c.ask) / 2
    return c.lastPrice > 0 ? c.lastPrice : NaN
}
function nearest(list, S) {
    let best = null
    for (const c of list || []) if (!best || Math.abs(c.strike - S) < Math.abs(best.strike - S)) best = c
    return best
}
function atmIv(calls, puts, S) {
    const c = nearest(calls, S), p = nearest(puts, S)
    const vals = [c, p].filter(x => x && x.impliedVolatility > 0.01 && x.impliedVolatility < 5).map(x => x.impliedVolatility)
    return vals.length ? vals.reduce((a, b) => a + b, 0) / vals.length : NaN
}
function expectedMove(calls, puts, S) {
    const c = nearest(calls, S)
    const p = c ? (puts || []).find(x => x.strike === c.strike) : null
    const m = mid(c) + mid(p)
    return isFinite(m) && S > 0 ? { dollars: m, pct: m / S * 100, strike: c.strike } : null
}
function maxPain(calls, puts) {
    const strikes = Array.from(new Set((calls || []).concat(puts || []).map(c => c.strike))).sort((a, b) => a - b)
    let best = NaN, least = Infinity
    for (const K of strikes) {
        let pay = 0
        for (const c of calls || []) pay += (c.openInterest || 0) * Math.max(0, K - c.strike)
        for (const p of puts || []) pay += (p.openInterest || 0) * Math.max(0, p.strike - K)
        if (pay < least) { least = pay; best = K }
    }
    return best
}
// [{strike, calls, puts, total}] by open interest, most first.
function oiLevels(calls, puts, n) {
    const by = {}
    for (const c of calls || []) (by[c.strike] = by[c.strike] || { strike: c.strike, calls: 0, puts: 0 }).calls += c.openInterest || 0
    for (const p of puts || []) (by[p.strike] = by[p.strike] || { strike: p.strike, calls: 0, puts: 0 }).puts += p.openInterest || 0
    return Object.values(by).map(x => Object.assign(x, { total: x.calls + x.puts })).filter(x => x.total > 0)
                 .sort((a, b) => b.total - a.total).slice(0, n || 5)
}
// Contracts with volume at least `minVolume` and at least `ratio` times
// their open interest (new positions, not old ones changing hands).
function unusual(calls, puts, minVolume, ratio) {
    const out = []
    const take = (list, type) => {
        for (const c of list || []) {
            const v = c.volume || 0, oi = c.openInterest || 0
            if (v >= minVolume && v >= ratio * Math.max(1, oi)) out.push(Object.assign({ type: type, ratio: v / Math.max(1, oi) }, c))
        }
    }
    take(calls, "call")
    take(puts, "put")
    return out.sort((a, b) => b.volume * mid(b) - a.volume * mid(a))
}
// Where IV sits in its own range over the days recorded: 0 the lowest seen,
// 100 the highest. `history` is [iv]; NaN with fewer than `minDays`.
function ivRank(iv, history, minDays) {
    const h = (history || []).filter(x => x > 0)
    if (!(iv > 0) || h.length < (minDays || 20)) return NaN
    const lo = Math.min(...h, iv), hi = Math.max(...h, iv)
    return hi > lo ? (iv - lo) / (hi - lo) * 100 : 50
}
