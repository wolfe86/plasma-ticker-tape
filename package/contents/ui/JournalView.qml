// The pop-up's Journal tab: every option trade logged from a quote card's
// Options tab, open ones first, with the realised result today, this week
// and overall, and today's notes. Exported as Markdown for the trade
// journal (times in New York time).

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

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Repeater {
            model: [i18n("All"), i18n("Open"), i18n("Closed")]
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
            PlasmaComponents3.ToolTip { text: i18n("Save today's trades and notes as Markdown in %1", jv.ws.exportDir) }
        }
        PlasmaComponents3.ToolButton {
            icon.name: "document-export"
            text: i18n("All")
            onClicked: jv.ws.exportJournal("")
            PlasmaComponents3.ToolTip { text: i18n("Save the whole journal as Markdown in %1", jv.ws.exportDir) }
        }
    }
    PlasmaComponents3.Label {
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
                model: jv.shown
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
                visible: jv.shown.length === 0
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.largeSpacing
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("No trades here yet. Build one on a stock's Options tab (open a stock, then Options) and press Log this trade.")
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
