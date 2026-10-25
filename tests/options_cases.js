// Cases for options.js, run by test_options.py through run_cases.js.
const near = (a, b, tol) => Math.abs(a - b) <= (tol === undefined ? 1e-3 : tol)

// Black-Scholes against the textbook example (Hull): S 42, K 40, r 10%,
// sigma 20%, T 0.5 -> call 4.76, put 0.81.
let c = bs("call", 42, 40, 0.5, 0.1, 0.2), p = bs("put", 42, 40, 0.5, 0.1, 0.2)
check("call price", near(c.price, 4.76, 0.01), c.price)
check("put price", near(p.price, 0.81, 0.01), p.price)
check("put-call parity", near(c.price - p.price, 42 - 40 * Math.exp(-0.05), 1e-6))
check("call delta", near(c.delta, 0.7791, 1e-3), c.delta)
check("put delta = call delta - 1", near(p.delta, c.delta - 1, 1e-9))
check("gamma equal for call and put", near(c.gamma, p.gamma, 1e-12))
check("vega positive and per point", c.vega > 0 && c.vega < 0.2, c.vega)
check("theta of a long call is negative", c.theta < 0, c.theta)
check("normCdf(0) = 0.5", near(normCdf(0), 0.5, 1e-7))
check("normCdf(1.96) = 0.975", near(normCdf(1.96), 0.975, 1e-4))
check("implied vol round trip", near(impliedVol("call", c.price, 42, 40, 0.5, 0.1), 0.2, 1e-4))
check("expired option is intrinsic", bs("put", 30, 40, 0, 0.05, 0.3).price === 10)

// A long call: cost 2.50, strike 100, one contract.
const exp = Date.UTC(2026, 11, 18)
const longCall = [{ type: "call", side: 1, strike: 100, premium: 2.5, qty: 1, expiry: exp }]
check("long call cost", netCost(longCall) === 250)
check("long call payoff at 90", payoff(longCall, 90) === -250)
check("long call payoff at 110", near(payoff(longCall, 110), 750))
let be = breakevens(longCall, 100)
check("long call breakeven 102.50", be.length === 1 && near(be[0], 102.5, 0.01), be)
let ex = extremes(longCall, 100)
check("long call: unlimited upside, loss capped at premium", ex.best === Infinity && near(ex.worst, -250), ex)

// A bull call spread: buy 100 call at 3, sell 105 call at 1 -> debit 2.
const spread = [{ type: "call", side: 1, strike: 100, premium: 3, qty: 1, expiry: exp },
                { type: "call", side: -1, strike: 105, premium: 1, qty: 1, expiry: exp }]
check("spread debit", near(netCost(spread), 200))
ex = extremes(spread, 102)
check("spread max profit 300, max loss 200", near(ex.best, 300) && near(ex.worst, -200), ex)
be = breakevens(spread, 102)
check("spread breakeven 102", be.length === 1 && near(be[0], 102, 0.01), be)

// A short put: credit; the most it can lose is strike minus credit.
const shortPut = [{ type: "put", side: -1, strike: 50, premium: 2, qty: 1, expiry: exp }]
ex = extremes(shortPut, 55)
check("short put: max profit the credit, max loss to zero", near(ex.best, 200) && near(ex.worst, -4800), ex)
// A short call: unlimited loss.
check("short call: unlimited loss", extremes([{ type: "call", side: -1, strike: 50, premium: 2, qty: 1, expiry: exp }], 50).worst === -Infinity)

// Probabilities.
check("ATM call ITM near 0.5", near(probItm("call", 100, 100, 0.25, 0, 0.3), 0.47, 0.02))
const pp = probProfit(longCall, 100, 0.25, 0, 0.3)
check("long call profit chance below its ITM chance", pp > 0 && pp < probItm("call", 100, 100, 0.25, 0, 0.3), pp)
check("deep ITM long stock-like call profit chance high", probProfit([{ type: "call", side: 1, strike: 50, premium: 50.5, qty: 1, expiry: exp }], 100, 0.25, 0, 0.3) < 0.55)

// Greeks of a position: a long call's delta in shares.
const g = greeks(longCall, 100, exp - 0.25 * 365 * 86400000, 0, 0.3)
check("position delta of one ATM call ~55 shares", g.delta > 45 && g.delta < 65, g)
check("position theta negative", g.theta < 0, g)

// Sizing: $5,000 account, 2% risk = $100; a lot losing at most $250 -> 0 lots.
check("sizing: no lot fits", sizing(5000, 2, -250).lots === 0)
check("sizing: 4 lots of $25 risk", sizing(5000, 2, -25).lots === 4)
check("sizing: unlimited loss gives 0", sizing(5000, 2, -Infinity).lots === 0)

// Chain readings.
const calls = [{ strike: 95, bid: 6, ask: 6.4, openInterest: 100, volume: 10, impliedVolatility: 0.32 },
               { strike: 100, bid: 2.9, ask: 3.1, openInterest: 900, volume: 5000, impliedVolatility: 0.30 },
               { strike: 105, bid: 1, ask: 1.2, openInterest: 300, volume: 20, impliedVolatility: 0.29 }]
const puts = [{ strike: 95, bid: 1, ask: 1.1, openInterest: 800, volume: 30, impliedVolatility: 0.33 },
              { strike: 100, bid: 2.8, ask: 3.0, openInterest: 400, volume: 15, impliedVolatility: 0.31 },
              { strike: 105, bid: 6, ask: 6.3, openInterest: 50, volume: 2, impliedVolatility: 0.30 }]
check("ATM IV averages the call and put", near(atmIv(calls, puts, 100.4), 0.305))
const em = expectedMove(calls, puts, 100)
check("expected move is the ATM straddle", em && near(em.dollars, 5.9) && near(em.pct, 5.9), em)
// Max pain: payout at 95 = calls 0 + puts(100: 400*5 + 105: 50*10) = 2500;
// at 100 = calls 100*5 + puts 50*5 = 750; at 105 = calls 100*10+900*5 + puts 0 = 5500.
check("max pain is 100", maxPain(calls, puts) === 100, maxPain(calls, puts))
const oi = oiLevels(calls, puts, 2)
check("OI levels: 100 then 95", oi.length === 2 && oi[0].strike === 100 && oi[1].strike === 95, oi)
const un = unusual(calls, puts, 1000, 3)
check("unusual: the 100 call trading 5.6x its OI", un.length === 1 && un[0].strike === 100 && un[0].type === "call", un)
check("IV rank needs history", isNaN(ivRank(0.3, [0.2, 0.4], 20)))
const hist = []
for (let i = 0; i < 25; i++) hist.push(0.2 + i * 0.01)
check("IV rank in range", near(ivRank(0.32, hist, 20), (0.32 - 0.2) / (0.44 - 0.2) * 100, 1e-6), ivRank(0.32, hist, 20))
