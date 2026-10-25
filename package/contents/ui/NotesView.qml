// The quote card's Notes tab: notes on this symbol, jotted during the
// session, each optionally tied to one of its journal trades, with
// screenshots if wanted. Kept in the journal database (Workspace.qml) and
// exported with it.
//
// Screenshots: copy one (Spectacle, or Print Screen), then Ctrl+V in the
// note box or the Paste screenshot button. Each is saved as a PNG in
// <export folder>/screenshots/ at once, shown under the box, and joins the
// note when it is added; the journal export shows it inline.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: nv

    required property var ws
    required property string symbol
    readonly property var openTrades: ws.trades.filter(t => t.symbol === nv.symbol && !(t.closed > 0))
    readonly property var mine: ws.notes.filter(n => n.symbol === nv.symbol)
    spacing: Kirigami.Units.smallSpacing

    // Screenshots saved for the note being written.
    property var pending: []
    property string pasteNote: ""
    // `quiet`: from Ctrl+V, which also pastes text -- a clipboard with no
    // picture on it is then not worth a word.
    function paste(quiet) {
        nv.ws.pasteImage(nv.symbol, (path, why) => {
            if (path) { nv.pending = nv.pending.concat([path]); nv.pasteNote = ""; return }
            if (quiet && why === "none") return
            nv.pasteNote = why === "none" ? i18n("There is no picture on the clipboard. Copy a screenshot first (Spectacle: Copy to clipboard).")
                         : why === "tool" ? i18n("Pasting screenshots needs the wl-clipboard package (Wayland) or xclip (X11).")
                         : i18n("Could not save the screenshot in %1", nv.ws.shotDir)
        })
    }

    PlasmaComponents3.TextArea {
        id: text
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 4
        wrapMode: TextEdit.Wrap
        placeholderText: i18n("A note on %1: what you saw, why you're in or out… Ctrl+V pastes a screenshot too.", nv.symbol)
        // Not accepted, so text on the clipboard still pastes as usual.
        Keys.onPressed: event => { if (event.matches(StandardKey.Paste)) nv.paste(true) }
    }
    NoteImages {
        paths: nv.pending
        removable: true
        onRemoved: path => nv.pending = nv.pending.filter(p => p !== path)
    }
    PlasmaComponents3.Label {
        visible: nv.pasteNote !== ""
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.neutralTextColor
        text: nv.pasteNote
    }
    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents3.ComboBox {
            id: tradeBox
            // Fixed sizes: Plasma's ComboBox otherwise measures itself in a loop.
            implicitWidth: Kirigami.Units.gridUnit * 14
            implicitHeight: addNote.implicitHeight
            Layout.fillWidth: true
            visible: nv.openTrades.length > 0
            model: [i18n("Not tied to a trade")].concat(nv.openTrades.map(t => nv.ws.tradeLabel(t)))
            PlasmaComponents3.ToolTip { text: i18n("Tie the note to an open trade: it is listed under that trade in the journal export") }
        }
        Item { Layout.fillWidth: !tradeBox.visible }
        PlasmaComponents3.Button {
            icon.name: "edit-paste"
            text: i18n("Paste screenshot")
            onClicked: nv.paste(false)
            PlasmaComponents3.ToolTip { text: i18n("Saves the picture on the clipboard as a PNG in %1 and adds it to this note", nv.ws.shotDir) }
        }
        PlasmaComponents3.Button {
            id: addNote
            icon.name: "list-add"
            text: i18n("Add note")
            enabled: text.text.trim() !== "" || nv.pending.length > 0
            onClicked: {
                const t = tradeBox.visible && tradeBox.currentIndex > 0 ? nv.openTrades[tradeBox.currentIndex - 1].id : ""
                nv.ws.addNote(nv.symbol, text.text, t, nv.pending)
                text.text = ""
                nv.pending = []
                nv.pasteNote = ""
            }
        }
    }
    Repeater {
        model: nv.mine
        ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: nv.ws.etStamp(modelData.time) + " ET"
                          + (modelData.trade ? " · " + (nv.ws.trades.find(t => t.id === modelData.trade) ? nv.ws.tradeLabel(nv.ws.trades.find(t => t.id === modelData.trade)) : "") : "")
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "edit-delete"
                    onClicked: nv.ws.deleteNote(modelData.id)
                    PlasmaComponents3.ToolTip { text: i18n("Delete this note") }
                }
            }
            PlasmaComponents3.Label {
                visible: modelData.text !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: modelData.text
            }
            NoteImages { paths: modelData.images || [] }
            Kirigami.Separator { Layout.fillWidth: true; Layout.topMargin: Kirigami.Units.smallSpacing }
        }
    }
    PlasmaComponents3.Label {
        visible: nv.mine.length === 0
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        opacity: 0.6
        text: i18n("No notes on %1 yet.", nv.symbol)
    }
}
