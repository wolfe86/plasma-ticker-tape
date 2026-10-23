// Settings → Screeners: the market pool every screen reads, and the screens
// themselves -- add, duplicate, delete, reorder, and edit each one's type,
// trigger, filters, scorecard and sound. The shape of a screen and the
// starting list are in screens.js.
//
// The list is edited as a JS array (`list`) and written back to the
// `screens` setting as JSON on every change.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as P5Support
import "sounds.js" as Sounds
import "screens.js" as Screens
import "scorecards.js" as Scorecards

KCM.SimpleKCM {
    id: page

    property string cfg_screens
    property alias cfg_poolMinVolume: poolVol.value
    property alias cfg_poolMinAvg: poolAvg.value
    property alias cfg_passSeconds: passSec.value
    property alias cfg_alertSound: sound.checked
    property real cfg_valueCapMin
    property bool cfg_valueAdded
    property bool cfg_losersAdded
    property real cfg_screenPriceMin
    property real cfg_screenPriceMax
    // The scorecards, for the picker; edited on the Scorecards page.
    property string cfg_scorecards
    readonly property var cards: Scorecards.load({ scorecards: cfg_scorecards,
        screenPriceMin: cfg_screenPriceMin, screenPriceMax: cfg_screenPriceMax })
    // Read only to build the starting list the first time.
    property real cfg_runPct
    property int cfg_runWindow
    property real cfg_hodMinChange
    property real cfg_hodMinRvol
    property string cfg_runSound
    property string cfg_hodSound
    // Set from the pop-up; declared so the page does not warn about them.
    property string cfg_screenerView
    property string cfg_screenerLayout
    property string cfg_screenerSort
    property bool cfg_screenerTools
    property bool cfg_rankedValueColumns

    property var list: []
    property int sel: 0
    readonly property var cur: list[sel] || null

    Component.onCompleted: {
        list = Screens.load({
            screens: cfg_screens, runPct: cfg_runPct, runWindow: cfg_runWindow,
            screenPriceMin: cfg_screenPriceMin, screenPriceMax: cfg_screenPriceMax,
            hodMinChange: cfg_hodMinChange, hodMinRvol: cfg_hodMinRvol,
            runSound: cfg_runSound, hodSound: cfg_hodSound
        })
    }
    function commit(l) {
        list = l
        cfg_screens = JSON.stringify(l)
    }
    function setField(key, value) {
        const l = list.slice()
        const s = Object.assign({}, l[sel])
        s[key] = value
        l[sel] = s
        commit(l)
    }
    function setFilter(key, value) {
        const f = Object.assign({}, cur.filters || {})
        if (value === null || value === undefined) delete f[key]
        else f[key] = value
        setField("filters", f)
    }
    function add(copyOf) {
        const s = copyOf ? JSON.parse(JSON.stringify(copyOf))
                         : { type: "running", runPct: 3, runWindow: 2, filters: {}, scorecard: "", sound: "" }
        s.id = Screens.newId()
        s.name = copyOf ? i18n("%1 copy", copyOf.name) : i18n("New screen")
        const l = list.slice()
        l.splice(sel + 1, 0, s)
        commit(l)
        sel = sel + 1
    }
    function remove() {
        if (list.length < 2) return
        const l = list.slice()
        l.splice(sel, 1)
        commit(l)
        sel = Math.min(sel, l.length - 1)
    }
    function move(d) {
        const to = sel + d
        if (to < 0 || to >= list.length) return
        const l = list.slice()
        const [s] = l.splice(sel, 1)
        l.splice(to, 0, s)
        commit(l)
        sel = to
    }

    // Plays a sound for the preview buttons.
    P5Support.DataSource {
        id: player
        engine: "executable"
        connectedSources: []
        onNewData: source => disconnectSource(source)
    }
    function preview(path) {
        if (path) player.connectSource(Sounds.command(path) + " # " + Date.now())
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // ── the market ──────────────────────────────────────────────────
        Kirigami.FormLayout {
            Layout.fillWidth: true
            Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Market: what every screen watches") }
            QQC2.SpinBox {
                id: poolVol
                Kirigami.FormData.label: i18n("Trading today at least:")
                from: 0; to: 10000000; stepSize: 50000
                textFromValue: (v, locale) => i18n("%1 shares", Screens.fmtNum(v))
                valueFromText: (text, locale) => Screens.parseNum(text.replace(/shares/i, "")) || 0
            }
            QQC2.SpinBox {
                id: poolAvg
                Kirigami.FormData.label: i18n("…or averaging at least:")
                from: 0; to: 10000000; stepSize: 50000
                textFromValue: (v, locale) => i18n("%1 a day", Screens.fmtNum(v))
                valueFromText: (text, locale) => Screens.parseNum(text.replace(/a day/i, "")) || 0
            }
            QQC2.SpinBox {
                id: passSec
                Kirigami.FormData.label: i18n("Check every:")
                from: 15; to: 120; stepSize: 5
                textFromValue: (v, locale) => i18n("%1 s", v)
                valueFromText: (text, locale) => parseInt(text)
            }
            QQC2.TextField {
                Kirigami.FormData.label: i18n("Long-term lists, companies worth:")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                text: "$" + Screens.fmtNum(page.cfg_valueCapMin) + "+"
                onEditingFinished: { const v = Screens.parseNum(text.replace("+", "")); if (v > 0) page.cfg_valueCapMin = v }
            }
            QQC2.CheckBox {
                id: sound
                Kirigami.FormData.label: i18n("Alert sounds:")
                text: i18n("On (the pop-up's mute button switches this)")
            }
            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.WordWrap
                text: i18n("US-listed common stock at any price, about 4,000 at the defaults, through Yahoo. Every screen reads the same check, so more screens cost nothing extra. Faster than 30 s risks Yahoo refusing; the widget slows itself if it does.")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }

        // ── the screens ─────────────────────────────────────────────────
        // ── which screen ────────────────────────────────────────────────
        // A picker row above the editor rather than a list beside it, so the
        // page holds together at any dialog width.
        Kirigami.Separator { Layout.fillWidth: true }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Label { text: i18n("Screen:") }
            QQC2.ComboBox {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                model: page.list.map(s => s.name)
                currentIndex: page.sel
                onActivated: index => page.sel = index
            }
            QQC2.ToolButton { icon.name: "list-add"; text: i18n("Add"); onClicked: page.add(null) }
            QQC2.ToolButton { icon.name: "edit-copy"; text: i18n("Duplicate"); enabled: !!page.cur; onClicked: page.add(page.cur) }
            QQC2.ToolButton { icon.name: "edit-delete"; text: i18n("Delete"); enabled: page.list.length > 1; onClicked: page.remove() }
            QQC2.ToolButton { icon.name: "go-up"; enabled: page.sel > 0; onClicked: page.move(-1)
                QQC2.ToolTip.text: i18n("Move earlier in the pop-up"); QQC2.ToolTip.visible: hovered }
            QQC2.ToolButton { icon.name: "go-down"; enabled: page.sel < page.list.length - 1; onClicked: page.move(1)
                QQC2.ToolTip.text: i18n("Move later in the pop-up"); QQC2.ToolTip.visible: hovered }
            Item { Layout.fillWidth: true }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: screenForm.implicitHeight
            // ── the selected screen ─────────────────────────────────────
            Kirigami.FormLayout {
                id: screenForm
                width: parent.width
                visible: !!page.cur

                QQC2.TextField {
                    Kirigami.FormData.label: i18n("Name:")
                    text: page.cur ? page.cur.name : ""
                    onEditingFinished: if (page.cur && text.trim() && text !== page.cur.name) page.setField("name", text.trim())
                }
                QQC2.ComboBox {
                    Kirigami.FormData.label: i18n("Type:")
                    model: Screens.types.map(t => t.name)
                    currentIndex: page.cur ? Screens.types.findIndex(t => t.key === page.cur.type) : 0
                    onActivated: index => page.setField("type", Screens.types[index].key)
                }

                // Running up
                RowLayout {
                    visible: !!page.cur && page.cur.type === "running"
                    Kirigami.FormData.label: i18n("Alert when up:")
                    QQC2.TextField {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                        text: page.cur ? Screens.fmtNum(page.cur.runPct) : ""
                        onEditingFinished: { const v = Screens.parseNum(text); if (v > 0) page.setField("runPct", v) }
                    }
                    QQC2.Label { text: i18n("% from its low, within") }
                    QQC2.SpinBox {
                        from: 1; to: 10
                        value: page.cur && page.cur.runWindow ? page.cur.runWindow : 2
                        onValueModified: page.setField("runWindow", value)
                    }
                    QQC2.Label { text: i18n("min") }
                }
                // Ranked
                RowLayout {
                    visible: !!page.cur && page.cur.type === "ranked"
                    Kirigami.FormData.label: i18n("Top:")
                    QQC2.SpinBox {
                        from: 5; to: 100
                        value: page.cur && page.cur.rankCount ? page.cur.rankCount : 25
                        onValueModified: page.setField("rankCount", value)
                    }
                    QQC2.Label { text: i18n("by") }
                    QQC2.ComboBox {
                        model: Screens.rankMeasures.map(m => m.name)
                        currentIndex: page.cur ? Math.max(0, Screens.rankMeasures.findIndex(m => m.key === (page.cur.rankBy || "change"))) : 0
                        onActivated: index => page.setField("rankBy", Screens.rankMeasures[index].key)
                    }
                    QQC2.ComboBox {
                        model: [i18n("highest first"), i18n("lowest first")]
                        currentIndex: page.cur && page.cur.rankLow ? 1 : 0
                        onActivated: index => page.setField("rankLow", index === 1)
                    }
                }

                RowLayout {
                    visible: !!page.cur && page.cur.type === "value"
                    Kirigami.FormData.label: i18n("Show up to:")
                    QQC2.SpinBox {
                        from: 5; to: 200
                        value: page.cur && page.cur.rankCount ? page.cur.rankCount : 50
                        onValueModified: page.setField("rankCount", value)
                    }
                    QQC2.Label { text: i18n("companies, most checks passed first") }
                }

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Filters") }
                Repeater {
                    model: Screens.filterDefs
                    RowLayout {
                        id: frow
                        required property var modelData
                        readonly property var value: page.cur && page.cur.filters ? page.cur.filters[modelData.key] : undefined
                        readonly property bool on: typeof value === "number"
                        readonly property bool flag: modelData.op === "flag"
                        // Fundamental and trend filters belong to long-term value lists.
                        visible: !!page.cur && (!modelData.value || page.cur.type === "value")
                        Kirigami.FormData.label: modelData.label + ":"
                        QQC2.CheckBox {
                            checked: frow.on
                            onToggled: page.setFilter(frow.modelData.key,
                                checked ? (frow.flag ? 1 : (Screens.parseNum(field.text) || 0)) : null)
                        }
                        QQC2.TextField {
                            id: field
                            visible: !frow.flag
                            enabled: frow.on
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            text: frow.on ? Screens.fmtNum(frow.value) : ""
                            placeholderText: frow.modelData.unit === "shares" || frow.modelData.key.startsWith("cap") ? "10M" : "0"
                            onEditingFinished: { const v = Screens.parseNum(text); if (v !== null) page.setFilter(frow.modelData.key, v) }
                        }
                        QQC2.Label { visible: !frow.flag; text: frow.modelData.unit || ""; opacity: 0.7 }
                    }
                }
                QQC2.Label {
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 20
                    wrapMode: Text.WordWrap
                    text: i18n("Numbers take K, M and B (10M). Float, short interest and news are looked up after a stock alerts, so those filters hide a row once its figure arrives.")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }

                Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Scorecard and sound") }
                QQC2.ComboBox {
                    Kirigami.FormData.label: i18n("Scorecard:")
                    model: [i18n("None")].concat(page.cards.map(c => c.name))
                    currentIndex: {
                        if (!page.cur || !page.cur.scorecard) return 0
                        const c = Scorecards.find(page.cards, page.cur.scorecard)
                        return c ? page.cards.indexOf(c) + 1 : 0
                    }
                    onActivated: index => page.setField("scorecard", index === 0 ? "" : page.cards[index - 1].id)
                }
                RowLayout {
                    visible: !!page.cur && page.cur.type !== "ranked"
                    Kirigami.FormData.label: i18n("Alert sound:")
                    QQC2.ComboBox {
                        model: Sounds.list.map(s => s.name)
                        currentIndex: page.cur ? Math.max(0, Sounds.list.findIndex(s => s.path === (page.cur.sound || ""))) : 0
                        onActivated: index => { page.setField("sound", Sounds.list[index].path); page.preview(Sounds.list[index].path) }
                    }
                    QQC2.Button {
                        icon.name: "media-playback-start"
                        enabled: !!page.cur && !!page.cur.sound
                        onClicked: page.preview(page.cur.sound)
                        QQC2.ToolTip.text: i18n("Play"); QQC2.ToolTip.visible: hovered
                    }
                }
            }
        }
    }
}
