// The pop-up, opened by left-clicking the tape. Its tabs:
//   Watchlist -- the whole watchlist (below).
//   Screener  -- the screener feeds (Screener.qml, fed by ScreenerEngine.qml).
//   Calendar  -- the week's economic releases and earnings (Calendar.qml).
//   News      -- recent headlines from the screens and the market (News.qml).
//   Journal   -- the option trades and notes logged from quote cards
//                (JournalView.qml).
// The same content runs in the detached window (TickerWindow.qml).
//
// One row per symbol in settings order -- starred or not -- with its label
// and name, the day's price line, the price and today's change, and the
// day's range. The rows come from the feeds main.qml already fetches.
// Clicking a row swaps the list for that symbol's detail view (Detail.qml),
// which fetches its own chart; closing the pop-up returns to the list.
// The rows are edited in place too: drag the handle to reorder, click the
// star for the tape, the remove button to drop one -- all written to the
// same `symbols` setting as Settings → Symbols, which follows them live.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaExtras.Representation {
    id: pop

    // The PlasmoidItem in main.qml: its symbols, feeds and formatting.
    required property var ticker
    readonly property var ws: ticker.workspace
    // In the detached window (TickerWindow.qml) rather than the panel's
    // pop-up: the header docks back instead of popping out, and closing the
    // pop-up does not reset it.
    property bool inWindow: false
    // A widget window's id (WidgetWindow.qml), "" for the pop-up and the
    // detached window: such a window keeps its own screen on the Screener
    // tab, and has no dock-back.
    property string windowId: ""
    // The screen the Screener tab shows here.
    readonly property string screenId: screenerTab.feed
    // On screen now: the pop-up open, or the window shown. A screen being
    // looked at does not count unread alerts.
    property bool shownNow: ticker.expanded

    // The settings entry whose detail view is showing, or null for the list.
    // Whatever opens here becomes the active ticker, which unpinned chart
    // windows follow (Workspace.qml).
    property var detail: null
    onDetailChanged: if (detail) ws.setActive(detail)
    // ── the watchlist's order ──
    // The rows come from a ListModel of symbols kept in step with the
    // watchlist, so a dragged row can move live (Kirigami's drag handle
    // moves model rows); the new order is written on the drop, to the same
    // `symbols` setting Settings → Symbols edits.
    ListModel { id: watchModel }
    property bool watchDragging: false
    function syncWatch() {
        if (watchDragging) return
        const want = ticker.symbols.map(s => s.symbol)
        let same = watchModel.count === want.length
        for (let i = 0; same && i < want.length; i++) same = watchModel.get(i).symbol === want[i]
        if (same) return
        watchModel.clear()
        for (const sym of want) watchModel.append({ symbol: sym })
    }
    function dropWatch() {
        const order = []
        for (let i = 0; i < watchModel.count; i++) order.push(watchModel.get(i).symbol)
        watchDragging = false
        ticker.reorderSymbols(order)
        syncWatch()
    }
    Connections {
        target: pop.ticker
        function onSymbolsChanged() { pop.syncWatch() }
    }
    Component.onCompleted: syncWatch()

    // A ticker clicked in a list. In a window it opens in the quote window
    // (made if there is none), and in the pop-up too while a linked one is
    // open (`quoteFollowsClicks`); either way the linked chart windows follow
    // and the list stays. Otherwise the card opens here.
    function open(e) {
        if (!e || !e.symbol) return
        if (inWindow) ws.openQuote(e)
        else if (ws.quoteLinked && Plasmoid.configuration.quoteFollowsClicks) ws.setActive(e)
        else detail = e
    }
    // 0 = Watchlist, 1 = Screener, 2 = Calendar, 3 = News, 4 = Journal.
    // Kept while the pop-up is closed.
    property int tab: 0
    Connections {
        target: pop.ticker
        function onExpandedChanged() { if (!pop.ticker.expanded && !pop.inWindow) pop.detail = null }
    }

    // The screener's table needs about twice the watchlist's width.
    Layout.minimumWidth: Kirigami.Units.gridUnit * 24
    Layout.preferredWidth: Kirigami.Units.gridUnit * (detail !== null ? 28 : tab === 1 ? 59 : tab >= 2 ? 36 : 28)
    Layout.preferredHeight: Math.min(Math.max(list.contentHeight, Kirigami.Units.gridUnit * 26)
                                     + header.implicitHeight + footer.implicitHeight,
                                     Kirigami.Units.gridUnit * 32)
    collapseMarginsHint: true
    // The dialog's own margins are collapsed so the headings run edge to
    // edge; the content keeps a small margin of its own, or text touches
    // the pop-up's left edge.
    readonly property real sideMargin: Kirigami.Units.smallSpacing

    header: PlasmaExtras.PlasmoidHeading {
        // The tabs and the buttons share a row when there is room for both;
        // narrower, the buttons take a row of their own above the tabs, so
        // the tab names are not squeezed onto two lines (Matt, 2026-10-26).
        GridLayout {
            id: headRow
            anchors.fill: parent
            readonly property bool oneRow: width >= Kirigami.Units.gridUnit * 44
            columns: oneRow ? 2 : 1
            rowSpacing: 0
            columnSpacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.TabBar {
                Layout.fillWidth: true
                Layout.row: headRow.oneRow ? 0 : 1
                Layout.column: 0
                currentIndex: pop.tab
                onCurrentIndexChanged: { pop.tab = currentIndex; pop.detail = null }
                PlasmaComponents3.TabButton { text: i18n("Watchlist") }
                // The alerts not yet looked at, across every screen.
                PlasmaComponents3.TabButton {
                    text: pop.ws.unreadTotal > 0 ? i18n("Screener (%1)", pop.ws.unreadTotal) : i18n("Screener")
                }
                PlasmaComponents3.TabButton { text: i18n("Calendar") }
                PlasmaComponents3.TabButton { text: i18n("News") }
                PlasmaComponents3.TabButton { text: i18n("Journal") }
            }
            RowLayout {
                Layout.row: 0
                Layout.column: headRow.oneRow ? 1 : 0
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: 0
                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: pop.ticker.pollAll()
                    PlasmaComponents3.ToolTip { text: i18n("Refresh now") }
                }
                // Saved layouts: the screens shown, their columns and sorts, the
                // chart settings and the chart windows.
                PlasmaComponents3.ToolButton {
                    id: layoutsButton
                    icon.name: "bookmarks"
                    onClicked: layoutsMenu.popup(layoutsButton, 0, layoutsButton.height)
                    PlasmaComponents3.ToolTip { text: i18n("Layouts: save this setup, or switch to a saved one") }
                }
                // TradingView's chart for the active ticker, in a window.
                PlasmaComponents3.ToolButton {
                    icon.name: "office-chart-line-stacked"
                    onClicked: pop.ws.newTradingView()
                    PlasmaComponents3.ToolTip { text: i18n("A TradingView chart in a new window, following the symbol you open. Click again for another, at the next bar size. Sign in from its window or Settings → Data.") }
                }
                // The first pop-out is the detached window; every one after it
                // is another window on this tab and screen (WidgetWindow.qml).
                PlasmaComponents3.ToolButton {
                    icon.name: "window-new"
                    onClicked: {
                        if (pop.inWindow) pop.ws.openWidgetWindow(pop.tab, pop.screenId)
                        else pop.ticker.popOut(pop.tab, pop.screenId)
                    }
                    PlasmaComponents3.ToolTip { text: pop.inWindow ? i18n("Pop this tab out into another window, so several tabs or screens can be watched at once")
                                                                   : i18n("Pop out into a window you can resize and keep open. Press again for another window on this tab.") }
                }
                PlasmaComponents3.ToolButton {
                    visible: pop.inWindow && !pop.windowId
                    icon.name: "view-restore"
                    onClicked: pop.ticker.dockBack()
                    PlasmaComponents3.ToolTip { text: i18n("Dock back to the panel") }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "internet-web-browser"
                    onClicked: Qt.openUrlExternally("https://finance.yahoo.com/markets/")
                    PlasmaComponents3.ToolTip { text: i18n("Open Yahoo Markets") }
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "configure"
                    onClicked: Plasmoid.internalAction("configure").trigger()
                    PlasmaComponents3.ToolTip { text: i18n("Settings: symbols, screeners, tape and more") }
                }
            }
        }
    }

    // ── layouts ──
    // Separate menus rather than nested ones: Plasma's Menu sizes a nested
    // submenu's entries before it has a parent (see Screener.qml).
    PlasmaComponents3.Menu {
        id: layoutsMenu
        PlasmaComponents3.MenuItem {
            icon.name: "bookmark-new"
            text: i18n("Save this layout…")
            onTriggered: saveLayout.openIt()
        }
        PlasmaComponents3.MenuItem {
            visible: pop.ws.presetNames.length > 0
            icon.name: "edit-delete"
            text: i18n("Delete a layout…")
            onTriggered: deleteMenu.popup()
        }
        PlasmaComponents3.MenuSeparator { visible: pop.ws.presetNames.length > 0 }
        Instantiator {
            model: pop.ws.presetNames
            delegate: PlasmaComponents3.MenuItem {
                required property string modelData
                text: modelData
                onTriggered: pop.ws.loadPreset(modelData)
            }
            onObjectAdded: (index, object) => layoutsMenu.insertItem(index + 3, object)
            onObjectRemoved: (index, object) => layoutsMenu.removeItem(object)
        }
    }
    PlasmaComponents3.Menu {
        id: deleteMenu
        Instantiator {
            model: pop.ws.presetNames
            delegate: PlasmaComponents3.MenuItem {
                required property string modelData
                text: i18n("Delete %1", modelData)
                onTriggered: pop.ws.deletePreset(modelData)
            }
            onObjectAdded: (index, object) => deleteMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => deleteMenu.removeItem(object)
        }
    }
    PlasmaComponents3.Popup {
        id: saveLayout
        x: Math.round((pop.width - width) / 2)
        y: Kirigami.Units.gridUnit * 3
        width: Math.min(pop.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 20)
        modal: true
        focus: true
        function openIt() { layoutName.text = ""; open(); layoutName.forceActiveFocus() }
        function save() {
            if (!layoutName.text.trim()) return
            pop.ws.savePreset(layoutName.text)
            close()
        }
        contentItem: ColumnLayout {
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.8
                text: i18n("Saves which screens are on, their columns, sorts and mutes, the screen on show, the chart settings and the open chart windows. A name in use is replaced.")
            }
            PlasmaComponents3.TextField {
                id: layoutName
                Layout.fillWidth: true
                placeholderText: i18n("Layout name, e.g. Premarket")
                onAccepted: saveLayout.save()
            }
            RowLayout {
                Item { Layout.fillWidth: true }
                PlasmaComponents3.Button { text: i18n("Cancel"); onClicked: saveLayout.close() }
                PlasmaComponents3.Button { text: i18n("Save"); enabled: layoutName.text.trim() !== ""; onClicked: saveLayout.save() }
            }
        }
    }

    footer: PlasmaExtras.PlasmoidHeading {
        position: PlasmaComponents3.ToolBar.Footer
        PlasmaComponents3.Label {
            anchors.fill: parent
            horizontalAlignment: Text.AlignRight
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: isNaN(pop.ticker.updated.getTime()) ? i18n("Waiting for Yahoo…")
                : i18n("Yahoo Finance · updated %1", Qt.formatTime(pop.ticker.updated, "hh:mm"))
        }
    }

    // The detail view scrolls: with every quote figure, or a page of
    // headlines, it is taller than the pop-up.
    Loader {
        anchors.fill: parent
        anchors.leftMargin: pop.sideMargin
        anchors.rightMargin: pop.sideMargin
        active: pop.detail !== null
        sourceComponent: PlasmaComponents3.ScrollView {
            id: detailScroll
            PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff
            contentWidth: availableWidth
            Detail {
                width: detailScroll.availableWidth
                ticker: pop.ticker
                entry: pop.detail
                onBack: pop.detail = null
                onGo: e => pop.detail = e
            }
        }
    }

    JournalView {
        anchors.fill: parent
        anchors.leftMargin: pop.sideMargin
        anchors.rightMargin: pop.sideMargin
        visible: pop.detail === null && pop.tab === 4
        ws: pop.ws
        onOpen: entry => pop.open(entry)
    }

    News {
        anchors.fill: parent
        anchors.leftMargin: pop.sideMargin
        anchors.rightMargin: pop.sideMargin
        visible: pop.detail === null && pop.tab === 3
        engine: pop.ticker.screener
        onOpen: entry => pop.open(entry)
    }

    Calendar {
        anchors.fill: parent
        anchors.leftMargin: pop.sideMargin
        anchors.rightMargin: pop.sideMargin
        visible: pop.detail === null && pop.tab === 2
        engine: pop.ticker.screener
        onOpen: entry => pop.open(entry)
    }

    Screener {
        id: screenerTab
        anchors.fill: parent
        anchors.leftMargin: pop.sideMargin
        anchors.rightMargin: pop.sideMargin
        visible: pop.detail === null && pop.tab === 1
        engine: pop.ticker.screener
        ws: pop.ws
        viewKey: pop.windowId ? "window-" + pop.windowId : pop.inWindow ? "window" : "popup"
        ownScreen: pop.windowId !== ""
        screenId: pop.windowId && pop.ws.widgetWindow(pop.windowId) ? pop.ws.widgetWindow(pop.windowId).screen || "" : ""
        onScreenPicked: id => pop.ws.updateWidgetWindow(pop.windowId, { screen: id })
        onScreen: pop.shownNow && visible
        onOpen: entry => pop.open(entry)
    }

    // A quick look-up: a symbol typed here opens its detail view without
    // joining the watchlist. Same as a headline's ticker (News.openStock).
    PlasmaComponents3.TextField {
        id: lookup
        visible: pop.detail === null && pop.tab === 0
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: pop.sideMargin
        anchors.rightMargin: pop.sideMargin
        anchors.topMargin: Kirigami.Units.smallSpacing
        anchors.bottomMargin: Kirigami.Units.smallSpacing
        placeholderText: i18n("Look up a symbol: AIRE, ^GSPC, BTC-USD…")
        clearButtonShown: true
        onAccepted: {
            const typed = text
            text = ""
            pop.ws.resolve(typed, e => pop.open(e))
        }
    }

    PlasmaComponents3.ScrollView {
        anchors.top: lookup.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: pop.sideMargin
        anchors.rightMargin: pop.sideMargin
        visible: pop.detail === null && pop.tab === 0

        ListView {
            id: list
            model: watchModel
            reuseItems: false
            clip: true

            PlasmaExtras.PlaceholderMessage {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: list.count === 0
                iconName: "office-chart-line"
                text: i18n("The watchlist is empty")
                helpfulAction: Kirigami.Action {
                    icon.name: "list-add"
                    text: i18n("Add symbols…")
                    onTriggered: Plasmoid.internalAction("configure").trigger()
                }
            }

            // Each row sits in a holder, as in Settings → Symbols: while a
            // row is dragged the handle lifts it out of the list and the
            // holder keeps its slot.
            delegate: Item {
                id: holder
                required property int index
                required property string symbol
                width: ListView.view.width
                implicitHeight: row.implicitHeight

                PlasmaComponents3.ItemDelegate {
                    id: row
                    width: holder.width
                    // Kirigami's drag handle presses the row as it lifts it.
                    down: false
                    readonly property var s: pop.ticker.symbols.find(x => x.symbol === holder.symbol)
                                             || { symbol: holder.symbol, label: holder.symbol, name: "", star: false }
                    readonly property var f: pop.ticker.feed(s.symbol)
                    readonly property bool known: f.value !== null
                    readonly property bool up: known && f.pct >= 0
                    // Green or red for the row. VIX takes its colour from the
                    // fear line, as on the tape -- VIX rising is not good news.
                    readonly property bool good: s.symbol === pop.ticker.fearSymbol
                                                 ? f.value < Plasmoid.configuration.fearLine : up
                    readonly property color dirColour: !known || f.stale ? Kirigami.Theme.disabledTextColor
                                                     : good ? Kirigami.Theme.positiveTextColor
                                                            : Kirigami.Theme.negativeTextColor

                    onClicked: pop.open(s)

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing

                        // Drag to reorder the watchlist and the tape; faint
                        // until the pointer is on the row.
                        Kirigami.ListItemDragHandle {
                            listItem: row
                            listView: list
                            opacity: row.hovered || pop.watchDragging ? 1 : 0.25
                            onMoveRequested: (oldIndex, newIndex) => { pop.watchDragging = true; watchModel.move(oldIndex, newIndex, 1) }
                            onDropped: pop.dropWatch()
                            HoverHandler { id: gripHover }
                            PlasmaComponents3.ToolTip {
                                visible: gripHover.hovered && !pop.watchDragging
                                text: i18n("Drag to change the order on the watchlist and the tape")
                            }
                        }
                        // On the tape or not: click the star to change it. An
                        // empty star shows while the pointer is on the row.
                        Kirigami.Icon {
                            source: row.s.star ? "starred-symbolic" : "non-starred-symbolic"
                            color: row.s.star ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                            opacity: row.s.star ? 1 : row.hovered ? 0.6 : 0
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Kirigami.Units.smallSpacing
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pop.ticker.setStar(row.s.symbol, !row.s.star)
                            }
                            HoverHandler { id: starHover }
                            PlasmaComponents3.ToolTip {
                                visible: starHover.hovered
                                text: row.s.star ? i18n("On the tape: click to take it off") : i18n("Click to put it on the tape")
                            }
                        }

                        // The same width hints in every row, whatever the name's
                        // length, so the price lines stack in a column.
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 6
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                            spacing: 0
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: row.s.label || row.s.symbol
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: row.s.name || row.s.symbol
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                                elide: Text.ElideRight
                            }
                        }

                        // The day's price line, with the previous close dashed
                        // across it: above the dashes is up on the day.
                        Canvas {
                            id: spark
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 1.6
                            readonly property var points: row.f.spark || []
                            readonly property real base: row.f.meta ? row.f.meta.chartPreviousClose : NaN
                            readonly property color colour: row.dirColour
                            onPointsChanged: requestPaint()
                            onColourChanged: requestPaint()
                            onWidthChanged: requestPaint()

                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                const p = points
                                if (p.length < 2) return
                                let lo = Math.min(...p), hi = Math.max(...p)
                                if (!isNaN(base)) { lo = Math.min(lo, base); hi = Math.max(hi, base) }
                                const span = hi - lo || 1
                                const pad = 2
                                const y = v => pad + (height - 2 * pad) * (1 - (v - lo) / span)
                                const x = i => width * i / (p.length - 1)

                                if (!isNaN(base)) {
                                    ctx.strokeStyle = pop.ticker.hex(Kirigami.Theme.disabledTextColor)
                                    ctx.lineWidth = 1
                                    ctx.setLineDash([2, 3])
                                    ctx.beginPath()
                                    ctx.moveTo(0, Math.round(y(base)) + 0.5)
                                    ctx.lineTo(width, Math.round(y(base)) + 0.5)
                                    ctx.stroke()
                                    ctx.setLineDash([])
                                }
                                ctx.strokeStyle = pop.ticker.hex(colour)
                                ctx.lineWidth = 1.5
                                ctx.lineJoin = "round"
                                ctx.beginPath()
                                ctx.moveTo(x(0), y(p[0]))
                                for (let i = 1; i < p.length; i++) ctx.lineTo(x(i), y(p[i]))
                                ctx.stroke()
                            }
                        }

                        // Price over today's change, both in the row's colour.
                        ColumnLayout {
                            spacing: 0
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                font.bold: true
                                font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace")
                                text: row.known ? pop.ticker.format(row.f, row.f.value) : "--"
                                color: row.dirColour
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace")
                                text: !row.known ? ""
                                    : (row.up ? "▲ +" : "▼ ") + row.f.pct.toFixed(2) + "%"
                                      + (row.f.stale ? " " + i18n("stale") : "")
                                color: row.dirColour
                            }
                        }

                        // The day's high over its low.
                        ColumnLayout {
                            spacing: 0
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            readonly property var m: row.f.meta
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                                text: parent.m && typeof parent.m.regularMarketDayHigh === "number"
                                      ? i18n("H %1", pop.ticker.format(row.f, parent.m.regularMarketDayHigh)) : ""
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                                text: parent.m && typeof parent.m.regularMarketDayLow === "number"
                                      ? i18n("L %1", pop.ticker.format(row.f, parent.m.regularMarketDayLow)) : ""
                            }
                        }

                        // Off the watchlist, while the pointer is on the row.
                        // Always takes its space, so the columns stay put.
                        PlasmaComponents3.ToolButton {
                            icon.name: "list-remove"
                            opacity: row.hovered ? 1 : 0
                            enabled: row.hovered
                            onClicked: pop.ticker.removeSymbol(row.s.symbol)
                            PlasmaComponents3.ToolTip { text: i18n("Remove %1 from the watchlist", row.s.label || row.s.symbol) }
                        }
                    }
                }
            }
        }
    }
}
