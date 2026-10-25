// Settings → Scorecards: named rule sets a screen can score its rows with.
// Add, duplicate, rename, delete and reorder scorecards; add, edit, reorder
// and remove each one's rules. The shape and the measures are in
// scorecards.js. Which screen uses which scorecard is set on the Screeners
// page.
//
// Saving follows the pattern described at the top of configScreener.qml:
// a setting this page did not change is re-read from the live configuration
// on Apply, so a scorecard the engine adds meanwhile is not undone.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import "scorecards.js" as Scorecards

KCM.SimpleKCM {
    id: page

    property string cfg_scorecards
    // Read only to build the starting scorecard the first time.
    property real cfg_screenPriceMin
    property real cfg_screenPriceMax

    property var list: []
    property int sel: 0
    readonly property var cur: list[sel] || null
    readonly property var rules: cur && Array.isArray(cur.rules) ? cur.rules : []

    function loadList() {
        return Scorecards.load({ scorecards: cfg_scorecards,
            screenPriceMin: cfg_screenPriceMin, screenPriceMax: cfg_screenPriceMax })
    }
    Component.onCompleted: {
        list = loadList()
        snapshot()
    }

    // ── saving without undoing the engine (configScreener.qml explains) ──
    property var opened: ({})
    function liveConfig() {
        try { return Plasmoid.configuration || null } catch (e) { return null }
    }
    function snapshot() {
        const c = liveConfig()
        if (!c) return
        const o = {}
        for (const k of c.keys()) if (("cfg_" + k) in page) o[k] = page["cfg_" + k]
        opened = o
    }
    function saveConfig() {
        const c = liveConfig()
        if (!c) return
        for (const k of c.keys()) {
            const p = "cfg_" + k
            if (!(p in page) || !(k in opened)) continue
            if (page[p] === opened[k]) page[p] = c[k]
            else if (k === "scorecards") page[p] = mergeCards(opened[k], page[p], c[k])
        }
        if (cfg_scorecards !== JSON.stringify(list)) {
            const id = cur ? cur.id : ""
            list = loadList()
            const i = list.findIndex(x => x.id === id)
            sel = i >= 0 ? i : Math.max(0, Math.min(sel, list.length - 1))
        }
        snapshot()
    }
    // This page's list, plus any scorecard added elsewhere while it was open
    // (the engine adds Deep Value 8 once).
    function mergeCards(base, mine, theirs) {
        let b, m, t
        try {
            b = JSON.parse(base || "[]"); m = JSON.parse(mine || "[]"); t = JSON.parse(theirs || "[]")
        } catch (e) { return mine }
        if (!Array.isArray(m) || !Array.isArray(t)) return mine
        if (!Array.isArray(b)) b = []
        const has = (l, id) => l.some(c => c && c.id === id)
        return JSON.stringify(m.concat(t.filter(c => c && !has(b, c.id) && !has(m, c.id))))
    }

    function commit(l) {
        list = l
        cfg_scorecards = JSON.stringify(l)
    }
    function setCard(key, value) {
        const l = list.slice()
        const c = Object.assign({}, l[sel])
        c[key] = value
        l[sel] = c
        commit(l)
    }
    function setRule(i, changes) {
        const r = rules.slice()
        r[i] = Object.assign({}, r[i], changes)
        setCard("rules", r)
    }
    function addRule() {
        setCard("rules", rules.concat([{ name: i18n("rule"), measure: "price", op: ">=", value: 1 }]))
    }
    function removeRule(i) {
        const r = rules.slice()
        r.splice(i, 1)
        setCard("rules", r)
    }
    function moveRule(i, d) {
        const to = i + d
        if (to < 0 || to >= rules.length) return
        const r = rules.slice()
        const [x] = r.splice(i, 1)
        r.splice(to, 0, x)
        setCard("rules", r)
    }
    function addCard(copyOf) {
        const c = copyOf ? JSON.parse(JSON.stringify(copyOf)) : { rules: [] }
        c.id = Scorecards.newId()
        c.name = copyOf ? i18n("%1 copy", copyOf.name) : i18n("New scorecard")
        const l = list.slice()
        l.splice(sel + 1, 0, c)
        commit(l)
        sel = sel + 1
    }
    function removeCard() {
        if (list.length < 2) return
        const l = list.slice()
        l.splice(sel, 1)
        // Move the selection first, so nothing reads a card that has gone.
        sel = Math.min(sel, l.length - 1)
        commit(l)
    }

    // What each measure means, for the Measure box's tooltip.
    readonly property var measureTips: ({
        price: i18n("The last price, in the screen's currency."),
        change: i18n("% change from yesterday's close."),
        gap: i18n("% between yesterday's close and today's open."),
        volume: i18n("Shares traded today."),
        rvol: i18n("Day RVOL (relative volume): today's volume ÷ the stock's normal daily volume. 2× = twice the usual."),
        rvol5: i18n("5-min RVOL: the last 5 minutes' volume as a % of a normal 5 minutes (200% = twice the usual)."),
        float: i18n("Float: the shares available to trade. Looked up after a stock appears."),
        shortFloat: i18n("Shares sold short, as a % of the float."),
        marketCap: i18n("Market cap: what the whole company is worth, in the screen's currency."),
        newsAge: i18n("Hours since the stock's newest headline."),
        catalyst: i18n("Press-wire news, 2 days: a press release in the last 2 days."),
        dilution: i18n("Dilution rating from SEC filings: how likely the company is to sell new shares. LOW < MEDIUM < HIGH < EXTREME."),
        themeStatus: i18n("How hot the stock's theme is: burnt < quiet < building < hot. A stock with no theme fails."),
        themeMembers: i18n("How many stocks are in the theme today."),
        themeRan: i18n("How many of the theme's stocks ran today."),
        themeFollow: i18n("Theme follow-through: % of the theme's stocks that ran today."),
        themeMove: i18n("The median of the theme's stocks' best move today, in %."),
        themeLift: i18n("Theme vs its baseline: how many times more of its stocks ran than usual (×)."),
        themeStreak: i18n("How many sessions in a row the theme has had a stock run."),
        themeShells: i18n("Theme serial issuers: % of its stocks that often sell new shares."),
        themeFreshPct: i18n("Theme names new to it: % of today's stocks not seen in it before."),
        sectorStatus: i18n("How hot the stock's sector is: burnt < quiet < building < hot. A stock with no sector fails."),
        sectorMembers: i18n("How many stocks are in the sector today."),
        sectorRan: i18n("How many of the sector's stocks ran today."),
        sectorFollow: i18n("Sector follow-through: % of the sector's stocks that ran today."),
        sectorMove: i18n("The median of the sector's stocks' best move today, in %."),
        p1: i18n("5-year P/E under 22.5: the price against average earnings over 5 years. From SEC filings."),
        p2: i18n("ROIC: return on invested capital, 9% or more. From SEC filings."),
        p3: i18n("Fewer shares outstanding than 5 years ago. From SEC filings."),
        p4: i18n("Free cash flow (the cash the business actually generates) growing. From SEC filings."),
        p5: i18n("Net income growing. From SEC filings."),
        p6: i18n("Revenue growing. From SEC filings."),
        p7: i18n("LT liabilities under 5× FCF: long-term debts under 5 years of free cash flow. From SEC filings."),
        p8: i18n("Price ÷ free cash flow under 22.5. From SEC filings.")
    })

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("A scorecard is a set of rules each row is checked against. The table shows how many it passes, a dot per rule, and the names of the ones it missed. Pick a screen's scorecard on the Screeners page.")
            opacity: 0.8
        }

        // ── which scorecard ─────────────────────────────────────────────
        // A picker row above the editor rather than a list beside it, so the
        // page holds together at any dialog width.
        // A Flow, so the buttons wrap onto a second line in a narrow dialog.
        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Scorecard:"); height: picker.height; verticalAlignment: Text.AlignVCenter }
            QQC2.ComboBox {
                id: picker
                width: Kirigami.Units.gridUnit * 12
                model: page.list.map(c => c.name)
                currentIndex: page.sel
                onActivated: index => page.sel = index
                QQC2.ToolTip.text: i18n("The scorecard edited below")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.ToolButton { icon.name: "list-add"; text: i18n("Add"); onClicked: page.addCard(null)
                QQC2.ToolTip.text: i18n("New empty scorecard")
                QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
            QQC2.ToolButton { icon.name: "edit-copy"; text: i18n("Duplicate"); enabled: !!page.cur; onClicked: page.addCard(page.cur)
                QQC2.ToolTip.text: i18n("Copy this scorecard")
                QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
            QQC2.ToolButton { icon.name: "edit-delete"; text: i18n("Delete"); enabled: page.list.length > 1; onClicked: page.removeCard()
                QQC2.ToolTip.text: i18n("Delete this scorecard (screens using it fall back to none)")
                QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
        }
        Kirigami.Separator { Layout.fillWidth: true }

        Item {
            Layout.fillWidth: true
            implicitHeight: editor.implicitHeight
            // ── the selected scorecard ──────────────────────────────────
            ColumnLayout {
                id: editor
                width: parent.width
                visible: !!page.cur
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    QQC2.Label { text: i18n("Name:") }
                    QQC2.TextField {
                        id: cardName
                        Layout.fillWidth: true
                        placeholderText: i18n("Shown in the Screeners page's scorecard list")
                        readonly property string stored: page.cur ? page.cur.name : ""
                        text: stored
                        onEditingFinished: {
                            if (page.cur && text.trim() && text !== page.cur.name) page.setCard("name", text.trim())
                            else text = Qt.binding(() => cardName.stored)
                        }
                        QQC2.ToolTip.text: i18n("Shown in the Screeners page's scorecard list")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }

                Kirigami.Heading { level: 5; text: i18n("Rules"); Layout.topMargin: Kirigami.Units.smallSpacing }

                // The model is a count, not the rules themselves, so editing a
                // rule redraws that row's values without rebuilding every row
                // (and the field being typed in keeps its focus).
                Repeater {
                    model: page.rules.length
                    delegate: RowLayout {
                        id: rrow
                        required property int index
                        readonly property var rule: page.rules[index] || ({})
                        readonly property var m: Scorecards.measure(rule.measure)
                        readonly property var levels: m.levels || Scorecards.levels
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.TextField {
                            id: ruleName
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                            readonly property string stored: rrow.rule.name || ""
                            text: stored
                            placeholderText: i18n("label")
                            onEditingFinished: {
                                if (text.trim() && text !== rrow.rule.name) page.setRule(rrow.index, { name: text.trim() })
                                else text = Qt.binding(() => ruleName.stored)
                            }
                            QQC2.ToolTip.text: i18n("Short label, shown when a row misses this rule")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.ComboBox {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 9.5
                            model: Scorecards.measures.map(x => x.name)
                            currentIndex: Scorecards.measures.findIndex(x => x.key === rrow.rule.measure)
                            onActivated: index => {
                                const nm = Scorecards.measures[index]
                                // A rating starts one step below its top:
                                // "at most HIGH" dilution, "at least building"
                                // for a theme or sector (higher is better).
                                const op = nm.kind === "level" && nm.key !== "dilution" ? ">="
                                         : Scorecards.ops[nm.kind][0].key
                                page.setRule(rrow.index, { measure: nm.key, op: op,
                                    value: nm.kind === "level" ? nm.levels[nm.levels.length - 2] : nm.kind === "flag" ? undefined : 0,
                                    value2: undefined })
                            }
                            QQC2.ToolTip.text: page.measureTips[rrow.m.key] || rrow.m.name
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.ComboBox {
                            visible: rrow.m.kind !== "flag"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5
                            model: Scorecards.ops[rrow.m.kind].map(x => x.name)
                            currentIndex: Math.max(0, Scorecards.ops[rrow.m.kind].findIndex(x => x.key === rrow.rule.op))
                            onActivated: index => {
                                const op = Scorecards.ops[rrow.m.kind][index].key
                                const c = { op: op }
                                // "between" starts as a band of one value, not
                                // an open end that fails every row.
                                if (op === "between" && typeof rrow.rule.value2 !== "number")
                                    c.value2 = typeof rrow.rule.value === "number" ? rrow.rule.value : 0
                                page.setRule(rrow.index, c)
                            }
                            QQC2.ToolTip.text: i18n("How the row's figure compares with the value")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        // Value(s): numbers take K, M and B.
                        QQC2.TextField {
                            id: ruleValue
                            visible: rrow.m.kind === "number"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.3
                            readonly property string stored: Scorecards.fmt(rrow.rule.value)
                            text: stored
                            onEditingFinished: {
                                const v = page.parseNum(text)
                                if (v !== null && v !== rrow.rule.value) page.setRule(rrow.index, { value: v })
                                else text = Qt.binding(() => ruleValue.stored)
                            }
                            QQC2.ToolTip.text: i18n("Numbers take K, M and B (10M). The unit is on the right.")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.Label { visible: rrow.m.kind === "number" && rrow.rule.op === "between"; text: "–" }
                        QQC2.TextField {
                            id: ruleValue2
                            visible: rrow.m.kind === "number" && rrow.rule.op === "between"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.3
                            readonly property string stored: Scorecards.fmt(rrow.rule.value2)
                            text: stored
                            onEditingFinished: {
                                const v = page.parseNum(text)
                                if (v !== null && v !== rrow.rule.value2) page.setRule(rrow.index, { value2: v })
                                else text = Qt.binding(() => ruleValue2.stored)
                            }
                            QQC2.ToolTip.text: i18n("The top of the band. Numbers take K, M and B (10M).")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.Label { visible: rrow.m.kind === "number"; text: rrow.m.unit || ""; opacity: 0.7 }
                        // The rating's own steps: burnt…hot for a theme or
                        // sector, LOW…EXTREME for dilution.
                        QQC2.ComboBox {
                            visible: rrow.m.kind === "level"
                            implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                            model: rrow.levels
                            currentIndex: Math.max(0, rrow.levels.indexOf(rrow.rule.value))
                            onActivated: index => page.setRule(rrow.index, { value: rrow.levels[index] })
                            QQC2.ToolTip.text: i18n("Theme or sector: burnt < quiet < building < hot. Dilution: LOW < MEDIUM < HIGH < EXTREME.")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        Item { Layout.fillWidth: true }
                        QQC2.ToolButton { icon.name: "go-up"; enabled: rrow.index > 0; onClicked: page.moveRule(rrow.index, -1)
                            QQC2.ToolTip.text: i18n("Move rule up")
                            QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
                        QQC2.ToolButton { icon.name: "go-down"; enabled: rrow.index < page.rules.length - 1; onClicked: page.moveRule(rrow.index, 1)
                            QQC2.ToolTip.text: i18n("Move rule down (the order of the rules is the order of the dots)")
                            QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
                        QQC2.ToolButton { icon.name: "edit-delete-remove"; onClicked: page.removeRule(rrow.index)
                            QQC2.ToolTip.text: i18n("Remove this rule"); QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
                    }
                }
                QQC2.Button {
                    icon.name: "list-add"
                    text: i18n("Add rule")
                    onClicked: page.addRule()
                    QQC2.ToolTip.text: i18n("Adds a rule (Price at least 1) to edit")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: i18n("Numbers take K, M and B (10M). A figure not known yet (float before it is looked up, say) counts as missed and shows with a question mark.")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }
            }
        }
    }

    // "10M" -> 10000000; "" -> null.
    function parseNum(text) {
        const m = String(text || "").trim().replace(/[$,%×\s]/g, "").match(/^(-?[\d.]+)([kmb])?$/i)
        if (!m) return null
        const v = parseFloat(m[1]) * ({ k: 1e3, m: 1e6, b: 1e9 }[(m[2] || "").toLowerCase()] || 1)
        return isFinite(v) ? v : null
    }
}
