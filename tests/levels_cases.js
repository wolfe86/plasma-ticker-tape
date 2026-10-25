// Cases for levels.js, run by test_levels.py through run_cases.js.
// Bars are 1-minute bars from 09:31 ET (the time is kept simple: minute n of
// the day is t = n * 60000, and etMin reads it back).
const et = t => Math.floor(t / 60000)
function bars(from, list) { return list.map((x, i) => ({ t: (from + i) * 60000, o: x[0], h: x[1], l: x[2], c: x[3] })) }
const R = o => Object.assign(rule({}), { levelSource: "auto", autoLevels: ["pdl"] }, o || {})
const daily = { pdh: 12, pdl: 10, pdc: 11 }

// 1. Above the prior-day low, trades through it, back above within 10 min.
let b = bars(600, [[10.5,10.6,10.4,10.5], [10.5,10.5,9.9,9.95], [9.95,10.0,9.9,9.98], [9.98,10.2,9.97,10.15]])
let f = scan(b, et, daily, [], R(), 0)
check("fail and rebound fires once", f.length === 1, f)
check("it names the level", f.length === 1 && f[0].key === "pdl" && f[0].name === "Prior-day low" && f[0].level === 10, f)
check("it fires on the rebound bar", f.length === 1 && f[0].t === 603 * 60000, f)
check("it records the fail time", f.length === 1 && f[0].failT === 601 * 60000, f)

// 2. A dip inside the buffer is not a fail (0.1% of 10 = 0.01).
b = bars(600, [[10.5,10.6,10.4,10.5], [10.2,10.2,9.995,10.0], [10.0,10.3,10.0,10.2]])
check("a dip inside the buffer does not arm", scan(b, et, daily, [], R(), 0).length === 0)

// 3. "close" mode: a wick below does not fail; a close below does.
b = bars(600, [[10.5,10.6,10.4,10.5], [10.5,10.5,9.8,10.1], [10.1,10.3,10.0,10.2]])
check("close mode ignores a wick", scan(b, et, daily, [], R({ failBy: "close" }), 0).length === 0)
b = bars(600, [[10.5,10.6,10.4,10.5], [10.5,10.5,9.8,9.9], [9.9,10.3,9.9,10.2]])
check("close mode: close below then close above fires", scan(b, et, daily, [], R({ failBy: "close" }), 0).length === 1)

// 4. Too slow: back above after the rebound window.
const slow = [[10.5,10.6,10.4,10.5], [10.5,10.5,9.8,9.9]]
for (let i = 0; i < 12; i++) slow.push([9.9,9.95,9.85,9.9])
slow.push([9.9,10.3,9.9,10.2])
check("a rebound after the window does not fire", scan(bars(600, slow), et, daily, [], R({ reboundMinutes: 10 }), 0).length === 0)

// 5. Hold: two closes above are needed; a close back below resets it.
b = bars(600, [[10.5,10.6,10.4,10.5], [10.5,10.5,9.8,9.9], [9.9,10.2,9.9,10.1], [10.1,10.1,9.9,9.95], [9.95,10.2,9.95,10.1], [10.1,10.3,10.05,10.2]])
f = scan(b, et, daily, [], R({ holdBars: 2 }), 0)
check("hold 2 fires on the second close above in a row", f.length === 1 && f[0].t === 605 * 60000, f)

// 6. After an alert the level waits before it can arm again.
b = bars(600, [[10.5,10.6,10.4,10.5], [10.5,10.5,9.8,9.9], [9.9,10.3,9.9,10.2], [10.2,10.2,9.8,9.9], [9.9,10.3,9.9,10.2]])
check("no second alert inside the cooldown", scan(b, et, daily, [], R({ reboundMinutes: 10 }), 0).length === 1)

// 7. Bars before fromT set the state but do not alert.
b = bars(600, [[10.5,10.6,10.4,10.5], [10.5,10.5,9.8,9.9], [9.9,10.3,9.9,10.2]])
check("an alert before fromT is not returned", scan(b, et, daily, [], R(), 603 * 60000).length === 0)
check("an alert at fromT is returned", scan(b, et, daily, [], R(), 602 * 60000).length === 1)

// 8. Never above the level: no fail.
b = bars(600, [[9.5,9.6,9.4,9.5], [9.5,9.6,9.3,9.4], [9.4,10.3,9.4,10.2]])
check("a stock that was never above the level does not arm", scan(b, et, daily, [], R(), 0).length === 0)

// 9. Session low: undercut the morning low and reclaim it.
b = bars(570, [[20,20.2,19.5,19.8], [19.8,20.4,19.7,20.3], [20.3,20.5,20.1,20.4], [20.4,20.4,19.3,19.4], [19.4,19.8,19.35,19.7]])
f = scan(b, et, null, [], R({ autoLevels: ["lod"] }), 0)
check("session low undercut and reclaim fires at the old low", f.length === 1 && f[0].key === "lod" && f[0].level === 19.5, f)

// 10. Premarket high, in the regular session: break above it, fail back
// under it, reclaim it.
b = bars(565, [[5,5.5,4.9,5.4], [5.4,5.45,5.2,5.3], [5.3,5.4,5.25,5.35], [5.35,5.4,5.3,5.38], [5.38,5.42,5.3,5.4],
               [5.4,5.7,5.4,5.65], [5.65,5.66,5.3,5.35], [5.35,5.6,5.35,5.58]])
f = scan(b, et, null, [], R({ autoLevels: ["pmh"] }), 0)
check("premarket high: breakout, fail under it, reclaim fires", f.length === 1 && f[0].key === "pmh" && f[0].level === 5.5, f)

// 10b. Session high: a breakout bar, a drop back under the old high, a reclaim.
b = bars(600, [[8,8.5,7.9,8.4], [8.4,8.45,8.2,8.3], [8.3,8.8,8.3,8.75], [8.75,8.76,8.3,8.35], [8.35,8.7,8.35,8.65]])
f = scan(b, et, null, [], R({ autoLevels: ["hod"] }), 0)
check("session high: failed breakout reclaimed fires at the old high", f.length === 1 && f[0].key === "hod" && f[0].level === 8.5, f)

// 11. Chart levels, and the source switch.
b = bars(600, [[31,31.2,30.9,31.1], [31.1,31.1,29.8,29.9], [29.9,30.4,29.9,30.3]])
f = scan(b, et, daily, [30], R({ levelSource: "manual" }), 0)
check("a chart level fires as a chart level", f.length === 1 && f[0].name === "Chart level" && f[0].level === 30, f)
check("auto only ignores chart levels", scan(b, et, daily, [30], R({ levelSource: "auto" }), 0).length === 0)

// 12. Cents buffer.
b = bars(600, [[10.5,10.6,10.4,10.5], [10.5,10.5,9.96,10.0], [10.0,10.3,10.0,10.2]])
check("a 5-cent buffer ignores a 4-cent dip", scan(b, et, daily, [], R({ failUnit: "cents", failBuffer: 5 }), 0).length === 0)
check("a 3-cent buffer counts a 4-cent dip", scan(b, et, daily, [], R({ failUnit: "cents", failBuffer: 3 }), 0).length === 1)

// 13. Lapses after armedMinutes even inside a long rebound window.
const lapse = [[10.5,10.6,10.4,10.5], [10.5,10.5,9.8,9.9]]
for (let i = 0; i < 6; i++) lapse.push([9.9,9.95,9.85,9.9])
lapse.push([9.9,10.3,9.9,10.2])
check("an armed setup lapses", scan(bars(600, lapse), et, daily, [], R({ reboundMinutes: 30, armedMinutes: 5 }), 0).length === 0)

// 14. Prior day from daily bars skips today.
const dd = [{ t: 1, h: 9, l: 8, c: 8.5 }, { t: 2, h: 12, l: 10, c: 11 }, { t: 3, h: 13, l: 11, c: 12 }]
const pd = priorDay(dd, t => ["2026-10-22", "2026-10-23", "2026-10-26"][t - 1], "2026-10-26")
check("prior day skips today's bar", pd && pd.pdh === 12 && pd.pdl === 10 && pd.pdc === 11, pd)

// 15. SPY 2026-10-23 after hours, as Yahoo has it: a zero-volume close of
// 728.67 between bars at 760.95 and 760.96 is a bad print, not a fail.
const spy = [[761.09,761.15,761.09,761.15], [761.12,761.12,759.97,761.12], [761.16,761.16,761.02,761.02],
             [760.96,761.05,760.95,761.04], [760.98,760.98,760.87,760.95], [761.0,761.0,760.9,760.97],
             [760.97,761.0,760.9,760.99], [760.99,761.05,760.95,761.0], [761.0,761.05,760.98,761.02],
             [761.02,761.04,760.97,760.98], [760.98,761.0,760.94,760.96], [760.96,760.99,760.94,760.95],
             [760.95,760.95,728.6713,728.6713], [760.96,761.1,759.97,761.03], [761.1,762.0,761.03,761.55]]
b = bars(1016, spy)
check("an after-hours bad print does not fire", scan(b, et, { pdh: 0, pdl: 759.91, pdc: 0 }, [], R(), 0).length === 0)
check("the bad print is replaced by a flat bar", clean(b, et)[12].c === 760.95, clean(b, et)[12])
// The same bars in the regular session: there the drop is taken as given.
b = bars(700, spy)
check("in the regular session the same drop counts", scan(b, et, { pdh: 0, pdl: 759.91, pdc: 0 }, [], R(), 0).length === 1)
// A small cap's genuine 6% premarket minute, against its usual 1-2%, stays.
const sc = []
for (let i = 0; i < 12; i++) sc.push(i % 2 ? [4.0,4.08,3.96,4.06] : [4.06,4.1,3.98,4.0])
b = bars(480, sc.concat([[4.0,4.02,3.74,3.76], [3.78,4.1,3.78,4.08]]))
check("a small cap's real premarket drop and reclaim fires", scan(b, et, { pdh: 0, pdl: 3.95, pdc: 0 }, [], R(), 0).length === 1)

// 16. Premarket: a close through the level and a close back above fire.
b = bars(500, busy0 = [[4.0,4.12,3.97,4.05], [4.05,4.1,3.80,3.90], [3.9,4.2,3.9,4.15]])
check("premarket judges on closes", scan(b, et, { pdh: 0, pdl: 3.95, pdc: 0 }, [], R(), 0).length === 1)
b = bars(500, [[4.0,4.12,3.97,4.05], [4.05,4.1,3.70,4.0], [4.0,4.2,4.0,4.15]])
check("a premarket wick alone does not arm", scan(b, et, { pdh: 0, pdl: 3.95, pdc: 0 }, [], R(), 0).length === 0)
