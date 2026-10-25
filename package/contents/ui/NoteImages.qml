// A note's screenshots as thumbnails (NotesView.qml, JournalView.qml):
// click one to open the picture in the desktop's image viewer. With
// `removable`, each has a button to take it off a note not yet added (the
// file stays in the screenshots folder).

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Flow {
    id: ni

    property var paths: []
    property bool removable: false
    signal removed(string path)

    Layout.fillWidth: true
    visible: paths.length > 0
    spacing: Kirigami.Units.smallSpacing

    Repeater {
        model: ni.paths
        Rectangle {
            id: thumb
            required property string modelData
            width: Kirigami.Units.gridUnit * 8
            height: Kirigami.Units.gridUnit * 5
            color: "transparent"
            border.color: Kirigami.Theme.disabledTextColor
            border.width: 1
            radius: 2
            clip: true
            Image {
                anchors.fill: parent
                anchors.margins: 1
                source: "file://" + encodeURI(thumb.modelData)
                // Decoded small: a full-screen capture is several megabytes
                // as pixels.
                sourceSize.width: Kirigami.Units.gridUnit * 16
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally("file://" + encodeURI(thumb.modelData))
            }
            PlasmaComponents3.ToolButton {
                visible: ni.removable
                anchors.top: parent.top
                anchors.right: parent.right
                icon.name: "edit-delete-remove"
                onClicked: ni.removed(thumb.modelData)
                PlasmaComponents3.ToolTip { text: i18n("Take this screenshot off the note") }
            }
        }
    }
}
