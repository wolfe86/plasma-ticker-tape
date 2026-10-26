// The pop-up's Journal tab: every option trade logged from a quote card's
// Options tab, open ones first, with the realised result today, this week
// and overall, today's screenshots and today's notes. Exported as Markdown
// for the trade journal (times in New York time).
//
// Screenshots (Matt, 2026-10-26: "docked or not, I want to save screenshots
// here. Just by copy/paste"): Ctrl+V on this tab, or Paste screenshot, saves
// the picture on the clipboard in <export folder>/screenshots/ named by the
// time and the ticker typed beside the button. The list shows every
// screenshot of the day in that folder, whichever window saved it.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: jv

    required property var ws
    signal open(var entry)
    spacing: Kirigami.Units.smallSpacing
    Layout.leftMargin: Kirigami.Units.smallSpacing

    property int filter: 0                // 0 all, 1 open, 2 closed
    // Option trades come from the Options tab, switched off for now
    // (`optionsFeature`): the tab is then screenshots and notes.
    readonly property bool trades: !!ws.cfg.optionsFeature
    readonly property string today: ws.etParts(Date.now())[0]
    readonly property var shown: ws.trades.filter(t => filter === 0 || (filter === 1) === !(t.closed > 0))
                                          .sort((a, b) => (!(a.closed > 0) - !(b.closed > 0)) * -1 || b.opened - a.opened)
    function realised(since) {
        return ws.trades.filter(t => t.closed > 0 && t.closed >= since).reduce((a, t) => a + (t.result || 0), 0)
    }
    function money(v) { return (v < 0 ? "-$" : "$") + Math.abs(v).toLocaleString(Qt.locale(), "f", 2) }
    // The start of today and of this week (Monday) in New York time, as ms.
    readonly property real dayStart: Date.parse(today + "T00:00:00Z") - ws.engine.etOffset * 1000
    readonly property real weekStart: dayStart - ((new Date(today + "T12:00:00Z").getUTCDay() + 6) % 7) * 86400000

    property string pasteNote: ""
    function paste(quiet) {
        const sym = shotSymbol.text.trim().toUpperCase()
        jv.ws.pasteImage(sym ? sym + "_trade" : "trade", (path, why) => {
            if (path) { jv.pasteNote = i18n("Saved %1", path.replace(/^.*\//, "")); jv.ws.loadDayShots(); return }
            if (quiet && why === "none") return
            jv.pasteNote = why === "none" ? i18n("There is no picture on the clipboard. Copy a screenshot first (Spectacle: Copy to clipboard).")
                         : why === "tool" ? i18n("Pasting screenshots needs the wl-clipboard package (Wayland) or xclip (X11).")
                         : i18n("Could not save the screenshot in %1", jv.ws.shotDir)
        })
    }
    // Ctrl+V anywhere on this tab while it is showing (not while typing in
    // the ticker box, which pastes text as usual).
    Shortcut {
        sequences: [StandardKey.Paste]
        enabled: jv.visible && !shotSymbol.activeFocus
        onActivated: jv.paste(false)
    }
    onVisibleChanged: if (visible) ws.loadDayShots()
    Timer { interval: 60000; repeat: true; running: jv.visible; onTriggered: jv.ws.loadDayShots() }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Repeater {
            model: jv.trades ? [i18n("All"), i18n("Open"), i18n("Closed")] : []
            PlasmaComponents3.ToolButton {
                required property string modelData
                required property int index
                text: modelData
                checkable: true
                checked: jv.filter === index
                onClicked: jv.filter = index
            }
        }
        Item { Layout.fillWidth: true }
        PlasmaComponents3.ToolButton {
            icon.name: "document-export"
            text: i18n("Today")
            onClicked: jv.ws.exportJournal(jv.today)
            PlasmaComponents3.ToolTip { text: jv.trades ? i18n("Save today's trades and notes as Markdown in %1", jv.ws.exportDir)
                                                        : i18n("Save today's notes and screenshots as Markdown in %1", jv.ws.exportDir) }
        }
        PlasmaComponents3.ToolButton {
            icon.name: "document-export"
            text: i18n("All")
            onClicked: jv.ws.exportJournal("")
            PlasmaComponents3.ToolTip { text: i18n("Save the whole journal as Markdown in %1", jv.ws.exportDir) }
        }
    }
    PlasmaComponents3.Label {
        visible: jv.trades
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: i18n("Realised today %1 · this week %2 · overall %3 · %4 open", jv.money(jv.realised(jv.dayStart)),
                   jv.money(jv.realised(jv.weekStart)), jv.money(jv.realised(0)),
                   jv.ws.trades.filter(t => !(t.closed > 0)).length)
    }
    RowLayout {
        visible: jv.ws.exportNote !== ""
        Layout.fillWidth: true
        PlasmaComponents3.Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; font: Kirigami.Theme.smallFont; textFormat: Text.PlainText; text: jv.ws.exportNote }
        PlasmaComponents3.ToolButton { visible: jv.ws.exportedFile !== ""; icon.name: "folder-open"; onClicked: Qt.openUrlExternally("file://" + jv.ws.exportDir) }
        PlasmaComponents3.ToolButton { icon.name: "window-close"; onClicked: jv.ws.exportNote = "" }
    }

    PlasmaComponents3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff
        contentWidth: availableWidth
        ColumnLayout {
            width: parent.width
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: jv.trades ? jv.shown : []
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0
                    PlasmaComponents3.ToolButton {
                        text: i18n("Open %1", modelData.symbol)
                        font: Kirigami.Theme.smallFont
                        icon.name: "office-chart-line"
                        onClicked: jv.open({ symbol: modelData.symbol, label: modelData.symbol, name: modelData.symbol, star: false, tab: 2 })
                    }
                    JournalTrade { Layout.fillWidth: true; ws: jv.ws; trade: modelData }
                }
            }
            PlasmaComponents3.Label {
                visible: jv.trades && jv.shown.length === 0
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("No trades here yet. Build one on a stock's Options tab (open a stock, then Options) and press Log this trade.")
            }
            PlasmaExtras.Heading {
                level: 5
                text: i18n("Today's screenshots")
                opacity: 0.8
                Layout.topMargin: jv.trades ? Kirigami.Units.largeSpacing : 0
            }
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.TextField {
                    id: shotSymbol
                    implicitWidth: Kirigami.Units.gridUnit * 6
                    placeholderText: i18n("Ticker")
                    PlasmaComponents3.ToolTip { text: i18n("Optional: the ticker the screenshot is about, for its file name") }
                }
                PlasmaComponents3.Button {
                    icon.name: "edit-paste"
                    text: i18n("Paste screenshot")
                    onClicked: jv.paste(false)
                    PlasmaComponents3.ToolTip { text: i18n("Save the picture on the clipboard in %1 (Ctrl+V on this tab does the same)", jv.ws.shotDir) }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "folder-open"
                    onClicked: Qt.openUrlExternally("file://" + encodeURI(jv.ws.shotDir))
                    PlasmaComponents3.ToolTip { text: i18n("Open the screenshots folder") }
                }
                Item { Layout.fillWidth: true }
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.8
                text: jv.pasteNote !== "" ? jv.pasteNote
                    : i18n("Copy a screenshot (Spectacle: Copy to clipboard), then Ctrl+V here.")
            }
            NoteImages { paths: jv.ws.dayShots }
            PlasmaComponents3.Label {
                visible: jv.ws.dayShots.length === 0
                opacity: 0.6
                text: i18n("None yet today.")
            }
            PlasmaExtras.Heading {
                level: 5
                text: i18n("Today's notes")
                opacity: 0.8
                Layout.topMargin: Kirigami.Units.largeSpacing
            }
            Repeater {
                model: jv.ws.notes.filter(n => n.time >= jv.dayStart)
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                        text: jv.ws.etStamp(parent.modelData.time).slice(11) + "  " + parent.modelData.symbol + ": " + parent.modelData.text
                    }
                    NoteImages { paths: parent.modelData.images || [] }
                }
            }
            PlasmaComponents3.Label {
                visible: !jv.ws.notes.some(n => n.time >= jv.dayStart)
                opacity: 0.6
                text: i18n("None yet. Add notes on a stock's Notes tab.")
            }
        }
    }
}
