// A widget window: another copy of the pop-up in a window of its own,
// beside the detached window (TickerWindow.qml). The pop-out button opens
// one once the detached window is open -- from the pop-up, the detached
// window or another widget window -- on the tab and screen it was pressed
// on, so Running Up, Crypto 24h High and the calendar can each have a
// window.
//
// Each keeps its own tab and its own screen on the Screener tab, and its
// size, in `widgetWindows` (Workspace.qml), so the set comes back after a
// restart and a saved layout carries it. It has no dock-back: closing it
// closes it. A ticker clicked in it opens in the quote window (Popup.open),
// and the linked chart windows follow.

import QtQuick
import QtQuick.Window
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

Window {
    id: ww

    required property var ticker          // main.qml
    required property string windowId
    readonly property var ws: ticker.workspace
    readonly property var spec: ws.widgetWindow(windowId) || ({})
    readonly property var tabNames: [i18n("Watchlist"), i18n("Screener"), i18n("Calendar"), i18n("News"), i18n("Journal")]
    readonly property var shownScreen: full.tab === 1 ? ticker.screener.screen(full.screenId) : null

    // Its number first, so a KWin window rule can match "Plasma Ticker Tape 2"
    // and put it back on its monitor (Wayland does not let a program place
    // its own windows).
    title: i18n("Plasma Ticker Tape") + (spec.n ? " " + spec.n : "") + " · "
           + (shownScreen ? shownScreen.name : tabNames[full.tab] || "")
    color: Kirigami.Theme.backgroundColor
    minimumWidth: Kirigami.Units.gridUnit * 24
    minimumHeight: Kirigami.Units.gridUnit * 16

    Component.onCompleted: {
        full.tab = spec.tab || 0
        width = Math.max(minimumWidth, spec.w || Plasmoid.configuration.windowWidth)
        height = Math.max(minimumHeight, spec.h || Plasmoid.configuration.windowHeight)
        show()
        raise()
        requestActivate()
    }
    onWidthChanged: saveSoon.restart()
    onHeightChanged: saveSoon.restart()
    Timer {
        id: saveSoon
        interval: 800
        onTriggered: if (ww.visible && ww.visibility !== Window.FullScreen && ww.visibility !== Window.Maximized)
                         ww.ws.updateWidgetWindow(ww.windowId, { w: ww.width, h: ww.height })
    }
    onClosing: close => ww.ws.closeWidgetWindow(ww.windowId)

    Item {
        anchors.fill: parent
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false
        Rectangle { anchors.fill: parent; color: Kirigami.Theme.backgroundColor }

        Popup {
            id: full
            anchors.fill: parent
            ticker: ww.ticker
            inWindow: true
            windowId: ww.windowId
            shownNow: ww.visible
            onTabChanged: ww.ws.updateWidgetWindow(ww.windowId, { tab: tab })
        }
    }
}
