// The quote card's Options tab, for a stock or fund: its option chain from
// Yahoo (delayed about 15 minutes), the readings taken from it, a trade
// builder with its payoff, Greeks, odds and size, and the journal of this
// symbol's option trades. The maths is options.js.
//
//   Readings -- at-the-money IV and its rank among the IVs recorded for the
//     symbol (Workspace.qml records one a day for the watchlist), the move
//     the market prices in by the chosen expiry and by the expiry after the
//     next earnings, max pain, and the strikes with the most open interest.
//   Chain -- strikes around the price for one expiry: bid, ask, open
//     interest and IV each side; in-the-money shaded. Click a side to add a
//     bought contract at the ask, right-click to add a sold one at the bid.
//   Builder -- the legs; each can be edited. Below them: what it costs, the
//     best and worst outcome at expiry, the break-evens, the chance of a
//     profit and of finishing in the money, the position's Greeks, the
//     payoff chart (at expiry, and today's value dashed), and how many fit
//     the risk set under Settings → Workspace.
//   Journal -- "Log this trade" saves the legs and what they cost; open
//     trades are closed here with what closing them brought in.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import "options.js" as Options

ColumnLayout {
    id: ov
    objectName: "optionsView"

    required property var ticker
    required property string symbol
    required property real price          // the underlying, live
    property real earningsAt: NaN         // the next earnings date (ms), if known
    readonly property var ws: ticker.workspace
    readonly property var cfg: Plasmoid.configuration
    readonly property real rate: cfg.optRate / 100
    spacing: Kirigami.Units.smallSpacing

    // ── the chain ──
    property var chain: null
    property var expirations: []
    property int expIndex: 0
    property bool loading: false
    property bool failed: false
    readonly property real spot: price > 0 ? price : chain && chain.quote ? chain.quote.regularMarketPrice || NaN : NaN
    function load(exp) {
        loading = true
        failed = false
        ws.optionChain(symbol, exp || "", c => {
            loading = false
            if (!c) { failed = true; return }
            if (!expirations.length) expirations = c.expirations
            chain = c
            if (!exp) expIndex = Math.max(0, expirations.indexOf(c.expiration))
            hist = ws.ivHistory(symbol)
            // The nearest expiry a week out is the one recorded for IV rank.
            if (c.expiration * 1000 - Date.now() >= 6 * 86400000) ws.recordIv(symbol, atm)
        })
    }
    onExpIndexChanged: if (chain && expirations[expIndex] !== chain.expiration) load(expirations[expIndex])
    onSymbolChanged: { chain = null; expirations = []; expIndex = 0; legs = []; earnMove = null; load("") }
    Component.onCompleted: load("")
    // The chain is a snapshot; refresh it with the tab.
    Timer { interval: 5 * 60000; repeat: true; running: ov.visible; onTriggered: if (ov.chain) ov.load(ov.chain.expiration) }

    readonly property var calls: chain ? chain.calls : []
    readonly property var puts: chain ? chain.puts : []
    readonly property real expiryMs: chain ? chain.expiration * 1000 : NaN
    readonly property real atm: chain ? Options.atmIv(calls, puts, spot) : NaN
    property var hist: []
    readonly property real rank: Options.ivRank(atm, hist, 20)
    readonly property var move: chain ? Options.expectedMove(calls, puts, spot) : null
    readonly property real pain: chain ? Options.maxPain(calls, puts) : NaN
    readonly property var topOi: chain ? Options.oiLevels(calls, puts, 3) : []

    // The move priced in through the next earnings: the first expiry on or
    // after the report.
    property var earnMove: null
    property real earnExpiry: NaN
    onEarningsAtChanged: loadEarnMove()
    onExpirationsChanged: loadEarnMove()
    function loadEarnMove() {
        if (!(earningsAt > Date.now() - 86400000) || !expirations.length) return
        const exp = expirations.find(e => e * 1000 >= earningsAt - 12 * 3600000)
        if (!exp) return
        earnExpiry = exp * 1000
        ws.optionChain(symbol, exp, c => { if (c) earnMove = Options.expectedMove(c.calls, c.puts, ov.spot) })
    }

    function money(v) {
        if (v === Infinity) return i18n("unlimited")
        if (v === -Infinity) return i18n("unlimited loss")
        return (v < 0 ? "-$" : "$") + Math.abs(v).toLocaleString(Qt.locale(), "f", 2)
    }
    function pct(v) { return isFinite(v) ? (v * 100).toFixed(1) + "%" : "—" }
    function day(ms) { return Qt.formatDate(new Date(ms), "ddd d MMM yyyy") }
    function shortDay(ms) { return Qt.formatDate(new Date(ms), "d MMM") }

    // ── readings ──
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        visible: !!ov.chain
        text: [
            i18n("IV %1 at the %2 expiry", ov.pct(ov.atm), ov.shortDay(ov.expiryMs)),
            // The rank compares like with like: the expiry a week or more out is the one recorded.
            ov.expiryMs - Date.now() < 6 * 86400000 ? "" : isFinite(ov.rank) ? i18n("IV rank %1", Math.round(ov.rank))
                : i18np("IV rank after 20 days recorded (1 so far)", "IV rank after 20 days recorded (%1 so far)", ov.hist.length),
            ov.move ? i18n("priced-in move by %1: ±$%2 (%3%)", ov.shortDay(ov.expiryMs), ov.move.dollars.toFixed(2), ov.move.pct.toFixed(1)) : "",
            isFinite(ov.pain) ? i18n("max pain $%1", ov.pain) : "",
            ov.topOi.length ? i18n("most open interest: %1", ov.topOi.map(x => "$" + x.strike + " (" + x.total.toLocaleString(Qt.locale(), "f", 0) + ")").join(", ")) : ""
        ].filter(x => x).join(" · ")
    }
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: !!ov.earnMove
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        color: Kirigami.Theme.neutralTextColor
        text: ov.earnMove ? i18n("Earnings %1: the market prices in ±$%2 (%3%) by the %4 expiry.", ov.shortDay(ov.earningsAt),
                                 ov.earnMove.dollars.toFixed(2), ov.earnMove.pct.toFixed(1), ov.shortDay(ov.earnExpiry)) : ""
    }

    // ── expiry ──
    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents3.Label { text: i18n("Expiry:") }
        PlasmaComponents3.ComboBox {
            // Fixed sizes: sized to its text, Plasma's ComboBox measured
            // itself in a loop (as on the screener's new-theme form).
            implicitWidth: Kirigami.Units.gridUnit * 14
            implicitHeight: refreshChain.implicitHeight
            Layout.preferredWidth: implicitWidth
            model: ov.expirations.map(e => ov.day(e * 1000) + " · " + i18np("%1 day", "%1 days", Math.max(0, Math.ceil((e * 1000 - Date.now()) / 86400000))))
            currentIndex: ov.expIndex
            onActivated: index => ov.expIndex = index
        }
        PlasmaComponents3.ToolButton {
            id: refreshChain
            icon.name: "view-refresh"
            enabled: !ov.loading
            onClicked: ov.load(ov.chain ? ov.chain.expiration : "")
            PlasmaComponents3.ToolTip { text: i18n("Fetch the chain again (Yahoo, delayed about 15 minutes)") }
        }
    }
    PlasmaComponents3.BusyIndicator { Layout.alignment: Qt.AlignHCenter; visible: ov.loading && !ov.chain; running: visible }
    PlasmaComponents3.Label {
        visible: ov.failed && !ov.chain
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: i18n("Yahoo returned no options for %1.", ov.symbol)
    }

    // ── chain table ──
    // Strikes around the price: the nearest 8 each side.
    readonly property var strikes: {
        if (!chain) return []
        const all = Array.from(new Set(calls.map(c => c.strike).concat(puts.map(p => p.strike)))).sort((a, b) => a - b)
        let at = all.findIndex(k => k >= spot)
        if (at < 0) at = all.length
        return all.slice(Math.max(0, at - 8), at + 8)
    }
    function contract(list, k) { return list.find(c => c.strike === k) || null }
    readonly property real cellW: Math.max(Kirigami.Units.gridUnit * 3, cellFm.advanceWidth("00000.00") + Kirigami.Units.smallSpacing * 2)
    FontMetrics { id: cellFm; font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace"); font.pointSize: Kirigami.Theme.smallFont.pointSize }
    readonly property var sideKeys: ["bid", "ask", "openInterest", "impliedVolatility"]
    function cellText(c, key) {
        if (!c) return ""
        const v = c[key]
        if (key === "impliedVolatility") return v > 0 ? (v * 100).toFixed(0) + "%" : ""
        if (key === "openInterest") return v > 0 ? (v >= 10000 ? (v / 1000).toFixed(0) + "K" : String(v)) : ""
        return v > 0 ? v.toFixed(2) : ""
    }
    // A contract as a leg: bought at the ask, sold at the bid (mid if the
    // side is empty).
    function addContract(type, c, side) {
        if (!c) return
        const p = side > 0 ? (c.ask > 0 ? c.ask : Options.mid(c)) : (c.bid > 0 ? c.bid : Options.mid(c))
        if (!(p > 0)) return
        legs = legs.concat([{ type: type, side: side, strike: c.strike, premium: Math.round(p * 100) / 100, qty: 1,
                              expiry: ov.expiryMs, iv: c.impliedVolatility > 0.01 ? c.impliedVolatility : NaN }])
    }

    ColumnLayout {
        visible: ov.strikes.length > 0
        Layout.alignment: Qt.AlignHCenter
        spacing: 0
        RowLayout {
            spacing: 0
            PlasmaComponents3.Label { Layout.preferredWidth: ov.cellW * 4; horizontalAlignment: Text.AlignHCenter; text: i18n("Calls"); font.bold: true }
            Item { Layout.preferredWidth: ov.cellW * 1.3 }
            PlasmaComponents3.Label { Layout.preferredWidth: ov.cellW * 4; horizontalAlignment: Text.AlignHCenter; text: i18n("Puts"); font.bold: true }
        }
        RowLayout {
            spacing: 0
            Repeater {
                model: [i18n("Bid"), i18n("Ask"), i18n("OI"), i18n("IV")]
                PlasmaComponents3.Label { required property string modelData; Layout.preferredWidth: ov.cellW; rightPadding: Kirigami.Units.smallSpacing; horizontalAlignment: Text.AlignRight; text: modelData; font: Kirigami.Theme.smallFont; opacity: 0.7 }
            }
            PlasmaComponents3.Label { Layout.preferredWidth: ov.cellW * 1.3; horizontalAlignment: Text.AlignHCenter; text: i18n("Strike"); font: Kirigami.Theme.smallFont; opacity: 0.7 }
            Repeater {
                model: [i18n("Bid"), i18n("Ask"), i18n("OI"), i18n("IV")]
                PlasmaComponents3.Label { required property string modelData; Layout.preferredWidth: ov.cellW; rightPadding: Kirigami.Units.smallSpacing; horizontalAlignment: Text.AlignRight; text: modelData; font: Kirigami.Theme.smallFont; opacity: 0.7 }
            }
        }
        Repeater {
            model: ov.strikes
            RowLayout {
                id: strikeRow
                required property real modelData
                readonly property var c: ov.contract(ov.calls, modelData)
                readonly property var p: ov.contract(ov.puts, modelData)
                spacing: 0
                // Calls: in the money below the price.
                MouseArea {
                    Layout.preferredWidth: ov.cellW * 4
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    onClicked: mouse => ov.addContract("call", strikeRow.c, mouse.button === Qt.RightButton ? -1 : 1)
                    Rectangle { anchors.fill: parent; color: Kirigami.Theme.positiveTextColor; opacity: strikeRow.modelData < ov.spot ? 0.12 : 0 }
                    Rectangle { anchors.fill: parent; color: Kirigami.Theme.hoverColor; opacity: parent.containsMouse ? 0.35 : 0 }
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: ov.sideKeys
                            PlasmaComponents3.Label {
                                required property string modelData
                                width: ov.cellW
                                rightPadding: Kirigami.Units.smallSpacing
                                horizontalAlignment: Text.AlignRight
                                text: ov.cellText(strikeRow.c, modelData)
                                font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace")
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                    }
                    PlasmaComponents3.ToolTip {
                        visible: parent.containsMouse && !!strikeRow.c
                        text: strikeRow.c ? i18n("%1 call: last %2, volume %3. Click to buy at the ask, right-click to sell at the bid.",
                                                 strikeRow.modelData, strikeRow.c.lastPrice, strikeRow.c.volume || 0) : ""
                    }
                }
                PlasmaComponents3.Label {
                    Layout.preferredWidth: ov.cellW * 1.3
                    horizontalAlignment: Text.AlignHCenter
                    text: strikeRow.modelData
                    font.bold: true
                    font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace")
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: ov.topOi.some(x => x.strike === strikeRow.modelData) ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                }
                // Puts: in the money above the price.
                MouseArea {
                    Layout.preferredWidth: ov.cellW * 4
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    onClicked: mouse => ov.addContract("put", strikeRow.p, mouse.button === Qt.RightButton ? -1 : 1)
                    Rectangle { anchors.fill: parent; color: Kirigami.Theme.negativeTextColor; opacity: strikeRow.modelData > ov.spot ? 0.12 : 0 }
                    Rectangle { anchors.fill: parent; color: Kirigami.Theme.hoverColor; opacity: parent.containsMouse ? 0.35 : 0 }
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: ov.sideKeys
                            PlasmaComponents3.Label {
                                required property string modelData
                                width: ov.cellW
                                rightPadding: Kirigami.Units.smallSpacing
                                horizontalAlignment: Text.AlignRight
                                text: ov.cellText(strikeRow.p, modelData)
                                font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace")
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                    }
                    PlasmaComponents3.ToolTip {
                        visible: parent.containsMouse && !!strikeRow.p
                        text: strikeRow.p ? i18n("%1 put: last %2, volume %3. Click to buy at the ask, right-click to sell at the bid.",
                                                 strikeRow.modelData, strikeRow.p.lastPrice, strikeRow.p.volume || 0) : ""
                    }
                }
            }
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: ov.cellW * 9.3
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.6
            text: i18n("Yahoo, delayed about 15 minutes. Shaded: in the money. Amber strikes: the most open interest. Click a side to buy, right-click to sell.")
        }
    }

    // ── the trade builder ──
    property var legs: []
    function setLeg(i, changes) {
        const l = legs.slice()
        l[i] = Object.assign({}, l[i], changes)
        legs = l
    }
    readonly property bool hasLegs: legs.length > 0
    readonly property real tYears: hasLegs ? Math.max(0, (Math.min(...legs.filter(l => l.type !== "stock").map(l => l.expiry).concat([Infinity])) - Date.now()) / (365 * 86400000)) : 0
    readonly property real ivFor: atm > 0 ? atm : 0.3
    readonly property real cost: hasLegs ? Options.netCost(legs) : 0
    readonly property var ext: hasLegs && spot > 0 ? Options.extremes(legs, spot) : null
    readonly property var be: hasLegs && spot > 0 ? Options.breakevens(legs, spot) : []
    readonly property real pop: hasLegs && spot > 0 && isFinite(tYears) ? Options.probProfit(legs, spot, tYears, rate, ivFor) : NaN
    readonly property var gk: hasLegs && spot > 0 ? Options.greeks(legs, spot, Date.now(), rate, ivFor) : null
    readonly property var single: legs.length === 1 && legs[0].type !== "stock" ? legs[0] : null
    readonly property real itm: single && spot > 0 ? Options.probItm(single.type, spot, single.strike, tYears, rate, single.iv > 0 ? single.iv : ivFor) : NaN
    // Sizing: the whole position is one lot.
    readonly property var size: ext ? Options.sizing(cfg.optAccountSize, cfg.optRiskPct, ext.worst) : null

    PlasmaExtras.Heading { level: 5; text: i18n("Trade builder"); opacity: 0.8; Layout.topMargin: Kirigami.Units.smallSpacing }
    Repeater {
        model: ov.legs
        Flow {
            id: legRow
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.ComboBox {
                implicitWidth: Kirigami.Units.gridUnit * 4.5
                implicitHeight: refreshChain.implicitHeight
                model: [i18n("Buy"), i18n("Sell")]
                currentIndex: legRow.modelData.side < 0 ? 1 : 0
                onActivated: i => ov.setLeg(legRow.index, { side: i === 1 ? -1 : 1 })
            }
            PlasmaComponents3.SpinBox {
                from: 1; to: 9999
                value: legRow.modelData.qty
                onValueModified: ov.setLeg(legRow.index, { qty: value })
                PlasmaComponents3.ToolTip { text: legRow.modelData.type === "stock" ? i18n("Shares") : i18n("Contracts (100 shares each)") }
            }
            PlasmaComponents3.Label {
                height: parent.children[0].height
                verticalAlignment: Text.AlignVCenter
                textFormat: Text.PlainText
                text: legRow.modelData.type === "stock" ? i18n("shares at")
                    : i18n("%1 %2 %3 at", ov.shortDay(legRow.modelData.expiry), legRow.modelData.strike,
                           legRow.modelData.type === "call" ? i18n("call") : i18n("put"))
            }
            PlasmaComponents3.TextField {
                width: Kirigami.Units.gridUnit * 4
                text: (legRow.modelData.type === "stock" ? legRow.modelData.strike : legRow.modelData.premium).toFixed(2)
                validator: DoubleValidator { bottom: 0 }
                onEditingFinished: {
                    const v = parseFloat(text)
                    if (v >= 0) ov.setLeg(legRow.index, legRow.modelData.type === "stock" ? { strike: v } : { premium: v })
                }
                PlasmaComponents3.ToolTip { text: legRow.modelData.type === "stock" ? i18n("Price per share") : i18n("Premium per share; the contract is 100×") }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "edit-delete-remove"
                onClicked: ov.legs = ov.legs.filter((x, i) => i !== legRow.index)
                PlasmaComponents3.ToolTip { text: i18n("Remove this leg") }
            }
        }
    }
    RowLayout {
        PlasmaComponents3.ToolButton {
            icon.name: "list-add"
            text: i18n("Shares")
            enabled: ov.spot > 0
            onClicked: ov.legs = ov.legs.concat([{ type: "stock", side: 1, strike: Math.round(ov.spot * 100) / 100, premium: 0, qty: 100, expiry: 0 }])
            PlasmaComponents3.ToolTip { text: i18n("Add 100 shares at the current price, for a covered call or a protective put") }
        }
        PlasmaComponents3.ToolButton {
            visible: ov.hasLegs
            icon.name: "edit-clear-all"
            text: i18n("Clear")
            onClicked: ov.legs = []
        }
        PlasmaComponents3.Label {
            visible: !ov.hasLegs
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Click a contract in the chain above to start.")
        }
    }

    // ── results ──
    GridLayout {
        visible: ov.hasLegs && !!ov.ext
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing * 2
        rowSpacing: Kirigami.Units.smallSpacing
        Repeater {
            model: !ov.ext ? [] : [
                [ov.cost >= 0 ? i18n("Cost (debit)") : i18n("Received (credit)"), ov.money(Math.abs(ov.cost))],
                [i18n("Best at expiry"), ov.money(ov.ext.best)],
                [i18n("Worst at expiry"), ov.money(ov.ext.worst)],
                [i18n("Break-even"), ov.be.length ? ov.be.map(x => "$" + x.toFixed(2)).join(", ") : "—"],
                [i18n("Chance of a profit"), ov.pct(ov.pop)],
                [i18n("Chance it finishes in the money"), ov.pct(ov.itm)],
                [i18n("Delta (shares)"), ov.gk ? ov.gk.delta.toFixed(1) : "—"],
                [i18n("Gamma (shares per $1)"), ov.gk ? ov.gk.gamma.toFixed(3) : "—"],
                [i18n("Theta (per day)"), ov.gk ? ov.money(ov.gk.theta) : "—"],
                [i18n("Vega (per vol point)"), ov.gk ? ov.money(ov.gk.vega) : "—"]
            ].filter(r => r[1] !== "—" || r[0] !== i18n("Chance it finishes in the money"))
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                PlasmaComponents3.Label { text: modelData[0]; opacity: 0.7; Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText }
                PlasmaComponents3.Label { text: modelData[1]; font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace"); textFormat: Text.PlainText }
            }
        }
    }
    PlasmaComponents3.Label {
        visible: ov.hasLegs && !!ov.size
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: !ov.size ? "" : !isFinite(ov.ext.worst)
            ? i18n("Sizing: the loss is unlimited, so no size fits a fixed risk. Cap it with a bought leg.")
            : i18n("Sizing: %1% of %2 is %3 a trade. This position can lose %4, so %5 fit. One full loss is %6% of your %7 walk-away.",
                   ov.cfg.optRiskPct, ov.money(ov.cfg.optAccountSize), ov.money(ov.size.budget),
                   ov.money(Math.abs(Math.min(0, ov.ext.worst))), i18np("1 lot", "%1 lots", ov.size.lots),
                   ov.cfg.optWalkAway > 0 ? Math.round(Math.abs(Math.min(0, ov.ext.worst)) / ov.cfg.optWalkAway * 100) : "—",
                   ov.money(ov.cfg.optWalkAway))
        color: ov.size && ov.size.lots < 1 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
    }
    PlasmaComponents3.Label {
        visible: ov.hasLegs
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        opacity: 0.6
        text: i18n("Black-Scholes with each contract's own IV (else %1), a %2% rate and no dividends; odds are the market's, from its IV, not a forecast.",
                   ov.pct(ov.ivFor), ov.cfg.optRate)
    }

    // ── payoff ──
    Canvas {
        id: payoffChart
        visible: ov.hasLegs && ov.spot > 0
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 10
        readonly property var rg: ov.hasLegs && ov.spot > 0 ? Options.range(ov.legs, ov.spot) : null
        onRgChanged: requestPaint()
        onWidthChanged: requestPaint()
        Connections { target: ov; function onLegsChanged() { payoffChart.requestPaint() } }
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!rg) return
            const n = 160, xs = [], atExp = [], now = []
            for (let i = 0; i <= n; i++) {
                const x = rg.lo + (rg.hi - rg.lo) * i / n
                xs.push(x)
                atExp.push(Options.payoff(ov.legs, x))
                now.push(Options.valueAt(ov.legs, x, Date.now(), ov.rate, ov.ivFor))
            }
            const all = atExp.concat(now)
            let lo = Math.min(0, ...all), hi = Math.max(0, ...all)
            const pad = (hi - lo) * 0.08 || 1
            lo -= pad; hi += pad
            const W = width, H = height
            const X = v => (v - rg.lo) / (rg.hi - rg.lo) * W
            const Y = v => H - (v - lo) / (hi - lo) * H
            const hex = c => ov.ticker.hex(c)
            // Profit above zero green, loss red, as a soft fill.
            ctx.fillStyle = hex(Kirigami.Theme.positiveTextColor); ctx.globalAlpha = 0.12
            ctx.fillRect(0, 0, W, Y(0))
            ctx.fillStyle = hex(Kirigami.Theme.negativeTextColor)
            ctx.fillRect(0, Y(0), W, H - Y(0))
            ctx.globalAlpha = 1
            ctx.strokeStyle = hex(Kirigami.Theme.disabledTextColor); ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(0, Math.round(Y(0)) + 0.5); ctx.lineTo(W, Math.round(Y(0)) + 0.5); ctx.stroke()
            // The price now.
            ctx.setLineDash([3, 3])
            ctx.beginPath(); ctx.moveTo(Math.round(X(ov.spot)) + 0.5, 0); ctx.lineTo(Math.round(X(ov.spot)) + 0.5, H); ctx.stroke()
            // Today's value, dashed.
            ctx.strokeStyle = hex(Kirigami.Theme.highlightColor); ctx.lineWidth = 1.25
            ctx.beginPath()
            for (let i = 0; i <= n; i++) { if (i) ctx.lineTo(X(xs[i]), Y(now[i])); else ctx.moveTo(X(xs[i]), Y(now[i])) }
            ctx.stroke()
            ctx.setLineDash([])
            // At expiry.
            ctx.strokeStyle = hex(Kirigami.Theme.textColor); ctx.lineWidth = 2
            ctx.beginPath()
            for (let i = 0; i <= n; i++) { if (i) ctx.lineTo(X(xs[i]), Y(atExp[i])); else ctx.moveTo(X(xs[i]), Y(atExp[i])) }
            ctx.stroke()
            // Break-evens.
            ctx.fillStyle = hex(Kirigami.Theme.neutralTextColor)
            for (const b of ov.be) { ctx.beginPath(); ctx.arc(X(b), Y(0), 3.5, 0, Math.PI * 2); ctx.fill() }
        }
        PlasmaComponents3.Label {
            anchors.left: parent.left; anchors.bottom: parent.bottom
            visible: !!parent.rg
            text: parent.rg ? "$" + parent.rg.lo.toFixed(0) : ""
            font: Kirigami.Theme.smallFont; opacity: 0.7
        }
        PlasmaComponents3.Label {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            visible: !!parent.rg
            text: parent.rg ? "$" + parent.rg.hi.toFixed(0) : ""
            font: Kirigami.Theme.smallFont; opacity: 0.7
        }
        PlasmaComponents3.Label {
            anchors.right: parent.right; anchors.top: parent.top
            text: i18n("solid: at expiry · dashed: today")
            font: Kirigami.Theme.smallFont; opacity: 0.7
        }
    }

    // ── log it ──
    RowLayout {
        visible: ov.hasLegs
        Layout.fillWidth: true
        PlasmaComponents3.TextField {
            id: tradeNote
            Layout.fillWidth: true
            placeholderText: i18n("Why this trade (optional)")
        }
        PlasmaComponents3.Button {
            icon.name: "document-save"
            text: i18n("Log this trade")
            onClicked: {
                ov.ws.addTrade(ov.symbol, ov.legs, ov.cost, tradeNote.text)
                tradeNote.text = ""
            }
            PlasmaComponents3.ToolTip { text: i18n("Saves the legs and what they cost to the journal (the Journal tab, and the Notes tab here)") }
        }
    }

    // ── this symbol's trades ──
    readonly property var mine: ws.trades.filter(t => t.symbol === ov.symbol)
    PlasmaExtras.Heading { visible: ov.mine.length > 0; level: 5; text: i18n("Journal: %1", ov.symbol); opacity: 0.8; Layout.topMargin: Kirigami.Units.smallSpacing }
    Repeater {
        model: ov.mine
        JournalTrade {
            required property var modelData
            Layout.fillWidth: true
            ws: ov.ws
            trade: modelData
            // What closing it would bring in now, from this chain's mid
            // prices where the legs are in it.
            markHint: {
                if (!(ov.spot > 0) || !ov.chain) return NaN
                let v = 0
                for (const l of modelData.legs) {
                    if (l.type === "stock") { v += l.side * l.qty * ov.spot; continue }
                    if (l.expiry !== ov.expiryMs) return NaN
                    const c = ov.contract(l.type === "call" ? ov.calls : ov.puts, l.strike)
                    const m = Options.mid(c)
                    if (!isFinite(m)) return NaN
                    v += l.side * l.qty * 100 * m
                }
                return Math.round(v * 100) / 100
            }
        }
    }
}
