// The detached window: the pop-up's content in a window of its own, opened
// with the pop-up's "Pop out" button and closed with "Dock back" or the
// window's own close button. Resizable, tiles and full-screens like any
// window, and stays open beside Level 2 and charts. Every tab, as in the
// pop-up (Popup.qml with inWindow set).
// Its size is kept (`windowWidth`/`windowHeight`), and so is the place on
// screen where the window system lets a program set it: X11 does, Wayland
// places windows itself (a KWin window rule can pin it there).
// (A compact one-line alert strip was tried in 1.3 and removed 2026-10-25.)

import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

Window {
    id: win

    required property var ticker          // main.qml
    readonly property var cfg: Plasmoid.configuration
    readonly property bool canPlace: Qt.platform.pluginName === "xcb"
    readonly property alias popup: full

    title: i18n("Plasma Ticker Tape")
    color: Kirigami.Theme.backgroundColor
    minimumWidth: Kirigami.Units.gridUnit * 24
    minimumHeight: Kirigami.Units.gridUnit * 16
    function raiseUp() {
        show()
        raise()
        requestActivate()
    }
    Component.onCompleted: {
        width = Math.max(minimumWidth, cfg.windowWidth)
        height = Math.max(minimumHeight, cfg.windowHeight)
        if (canPlace && cfg.windowX >= 0 && cfg.windowY >= 0) { x = cfg.windowX; y = cfg.windowY }
        raiseUp()
    }
    // Sizes are saved a moment after the last change, so dragging an edge
    // does not write the settings on every pixel.
    onWidthChanged: saveSoon.restart()
    onHeightChanged: saveSoon.restart()
    onXChanged: if (canPlace) saveSoon.restart()
    onYChanged: if (canPlace) saveSoon.restart()
    Timer {
        id: saveSoon
        interval: 800
        onTriggered: {
            if (!win.visible || win.visibility === Window.FullScreen || win.visibility === Window.Maximized) return
            if (win.cfg.windowWidth !== win.width) win.cfg.windowWidth = win.width
            if (win.cfg.windowHeight !== win.height) win.cfg.windowHeight = win.height
            if (win.canPlace) {
                if (win.cfg.windowX !== win.x) win.cfg.windowX = win.x
                if (win.cfg.windowY !== win.y) win.cfg.windowY = win.y
            }
        }
    }
    onClosing: close => win.cfg.windowOpen = false

    Item {
        anchors.fill: parent
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false
        Rectangle { anchors.fill: parent; color: Kirigami.Theme.backgroundColor }

        Popup {
            id: full
            anchors.fill: parent
            ticker: win.ticker
            inWindow: true
            shownNow: win.visible
        }
    }
}
