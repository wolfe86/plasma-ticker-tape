// Settings → Scorecards: named rule sets a screen can score its rows with.
// Add, duplicate, rename, delete and reorder scorecards; add, edit, reorder
// and remove each one's rules. The shape and the measures are in
// scorecards.js. Which screen uses which scorecard is set on the Screeners
// page.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
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

    Component.onCompleted: list = Scorecards.load({
        scorecards: cfg_scorecards, screenPriceMin: cfg_screenPriceMin, screenPriceMax: cfg_screenPriceMax })

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
        const rules = cur.rules.slice()
        rules[i] = Object.assign({}, rules[i], changes)
        setCard("rules", rules)
    }
    function addRule() {
        setCard("rules", cur.rules.concat([{ name: i18n("rule"), measure: "price", op: ">=", value: 1 }]))
    }
    function removeRule(i) {
        const rules = cur.rules.slice()
        rules.splice(i, 1)
        setCard("rules", rules)
    }
    function moveRule(i, d) {
        const to = i + d
        if (to < 0 || to >= cur.rules.length) return
        const rules = cur.rules.slice()
        const [r] = rules.splice(i, 1)
        rules.splice(to, 0, r)
        setCard("rules", rules)
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
        commit(l)
        sel = Math.min(sel, l.length - 1)
    }

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
        RowLayout {
            Layout.fillWidth: true
            QQC2.Label { text: i18n("Scorecard:") }
            QQC2.ComboBox {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                model: page.list.map(c => c.name)
                currentIndex: page.sel
                onActivated: index => page.sel = index
            }
            QQC2.ToolButton { icon.name: "list-add"; text: i18n("Add"); onClicked: page.addCard(null) }
            QQC2.ToolButton { icon.name: "edit-copy"; text: i18n("Duplicate"); enabled: !!page.cur; onClicked: page.addCard(page.cur) }
            QQC2.ToolButton { icon.name: "edit-delete"; text: i18n("Delete"); enabled: page.list.length > 1; onClicked: page.removeCard() }
            Item { Layout.fillWidth: true }
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
                        Layout.fillWidth: true
                        text: page.cur ? page.cur.name : ""
                        onEditingFinished: if (page.cur && text.trim() && text !== page.cur.name) page.setCard("name", text.trim())
                    }
                }

                Kirigami.Heading { level: 5; text: i18n("Rules"); Layout.topMargin: Kirigami.Units.smallSpacing }

                Repeater {
                    model: page.cur ? page.cur.rules : []
                    delegate: RowLayout {
                        id: rrow
                        required property var modelData
                        required property int index
                        readonly property var m: Scorecards.measure(modelData.measure)
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.TextField {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                            text: rrow.modelData.name
                            placeholderText: i18n("label")
                            onEditingFinished: if (text.trim() && text !== rrow.modelData.name) page.setRule(rrow.index, { name: text.trim() })
                            QQC2.ToolTip.text: i18n("Short label, shown when a row misses this rule")
                            QQC2.ToolTip.visible: hovered
                        }
                        QQC2.ComboBox {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 9.5
                            model: Scorecards.measures.map(x => x.name)
                            currentIndex: Scorecards.measures.findIndex(x => x.key === rrow.modelData.measure)
                            onActivated: index => {
                                const nm = Scorecards.measures[index]
                                const op = Scorecards.ops[nm.kind][0].key
                                page.setRule(rrow.index, { measure: nm.key, op: op,
                                    value: nm.kind === "level" ? "MEDIUM" : nm.kind === "flag" ? undefined : 0,
                                    value2: undefined })
                            }
                        }
                        QQC2.ComboBox {
                            visible: rrow.m.kind !== "flag"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5
                            model: Scorecards.ops[rrow.m.kind].map(x => x.name)
                            currentIndex: Math.max(0, Scorecards.ops[rrow.m.kind].findIndex(x => x.key === rrow.modelData.op))
                            onActivated: index => page.setRule(rrow.index, { op: Scorecards.ops[rrow.m.kind][index].key })
                        }
                        // Value(s): numbers take K, M and B.
                        QQC2.TextField {
                            visible: rrow.m.kind === "number"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.3
                            text: Scorecards.fmt(rrow.modelData.value)
                            onEditingFinished: { const v = parseNum(text); if (v !== null) page.setRule(rrow.index, { value: v }) }
                        }
                        QQC2.Label { visible: rrow.m.kind === "number" && rrow.modelData.op === "between"; text: "–" }
                        QQC2.TextField {
                            visible: rrow.m.kind === "number" && rrow.modelData.op === "between"
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 3.3
                            text: Scorecards.fmt(rrow.modelData.value2)
                            onEditingFinished: { const v = parseNum(text); if (v !== null) page.setRule(rrow.index, { value2: v }) }
                        }
                        QQC2.Label { visible: rrow.m.kind === "number"; text: rrow.m.unit || ""; opacity: 0.7 }
                        QQC2.ComboBox {
                            visible: rrow.m.kind === "level"
                            model: Scorecards.levels
                            currentIndex: Math.max(0, Scorecards.levels.indexOf(rrow.modelData.value))
                            onActivated: index => page.setRule(rrow.index, { value: Scorecards.levels[index] })
                        }
                        Item { Layout.fillWidth: true }
                        QQC2.ToolButton { icon.name: "go-up"; enabled: rrow.index > 0; onClicked: page.moveRule(rrow.index, -1) }
                        QQC2.ToolButton { icon.name: "go-down"; enabled: rrow.index < page.cur.rules.length - 1; onClicked: page.moveRule(rrow.index, 1) }
                        QQC2.ToolButton { icon.name: "edit-delete-remove"; onClicked: page.removeRule(rrow.index)
                            QQC2.ToolTip.text: i18n("Remove this rule"); QQC2.ToolTip.visible: hovered }
                    }
                }
                QQC2.Button {
                    icon.name: "list-add"
                    text: i18n("Add rule")
                    onClicked: page.addRule()
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
