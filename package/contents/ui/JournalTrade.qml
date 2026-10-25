// One option trade from the journal (Workspace.qml): what it is, when it
// opened and for how much, and either a way to close it or how it ended.
// Shown on a quote card's Options tab and on the pop-up's Journal tab.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: jt

    required property var ws
    required property var trade
    // What closing it would bring in now (dollars, + received), if known.
    property real markHint: NaN
    readonly property bool open: !(trade.closed > 0)
    spacing: 0

    function money(v) { return (v < 0 ? "-$" : "$") + Math.abs(v).toLocaleString(Qt.locale(), "f", 2) }

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            font.bold: true
            elide: Text.ElideRight
            text: jt.ws.tradeLabel(jt.trade)
        }
        PlasmaComponents3.Label {
            visible: !jt.open
            font.bold: true
            font.family: Kirigami.Theme.fixedWidthFont.family
            color: jt.trade.result >= 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
            text: jt.open ? "" : jt.money(jt.trade.result)
        }
        PlasmaComponents3.ToolButton {
            icon.name: jt.open ? "edit-delete" : "edit-undo"
            onClicked: jt.open ? jt.ws.deleteTrade(jt.trade.id) : jt.ws.reopenTrade(jt.trade.id)
            PlasmaComponents3.ToolTip { text: jt.open ? i18n("Delete this trade from the journal") : i18n("Reopen: undo the close") }
        }
    }
    PlasmaComponents3.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        font: Kirigami.Theme.smallFont
        opacity: 0.75
        text: i18n("Opened %1 ET, %2 %3", jt.ws.etStamp(jt.trade.opened), jt.trade.cost >= 0 ? i18n("paid") : i18n("received"),
                   jt.money(Math.abs(jt.trade.cost)))
              + (jt.open ? "" : " · " + i18n("closed %1 ET for %2", jt.ws.etStamp(jt.trade.closed), jt.money(jt.trade.exitValue)))
              + (jt.trade.notes ? " · " + jt.trade.notes : "")
    }
    RowLayout {
        visible: jt.open
        PlasmaComponents3.Label { text: i18n("Close for"); font: Kirigami.Theme.smallFont }
        PlasmaComponents3.TextField {
            id: exitField
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
            placeholderText: isFinite(jt.markHint) ? jt.markHint.toFixed(2) : i18n("dollars")
            validator: DoubleValidator {}
            PlasmaComponents3.ToolTip { text: i18n("What closing it brings in, in dollars for the whole position: negative if you pay to close (a sold option bought back). Empty uses the chain's mid prices shown greyed, where known.") }
        }
        PlasmaComponents3.Button {
            text: i18n("Close")
            enabled: exitField.text !== "" || isFinite(jt.markHint)
            onClicked: jt.ws.closeTrade(jt.trade.id, exitField.text !== "" ? parseFloat(exitField.text) : jt.markHint)
        }
    }
    Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }
}
