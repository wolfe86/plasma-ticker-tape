// The pop-up, opened by left-clicking the tape. Two tabs:
//   Watchlist -- the whole watchlist (below).
//   Screener  -- the screener feeds (Screener.qml, fed by ScreenerEngine.qml).
//   Calendar  -- the week's economic releases and earnings (Calendar.qml).
//   News      -- recent headlines from the screens and the market (News.qml).
//
// One row per symbol in settings order -- starred or not -- with its label
// and name, the day's price line, the price and today's change, and the
// day's range. The rows come from the feeds main.qml already fetches.
// Clicking a row swaps the list for that symbol's detail view (Detail.qml),
// which fetches its own chart; closing the pop-up returns to the list.

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

    // The settings entry whose detail view is showing, or null for the list.
    property var detail: null
    // 0 = Watchlist, 1 = Screener, 2 = Calendar, 3 = News. Kept while the
    // pop-up is closed.
    property int tab: 0
    Connections {
        target: pop.ticker
        function onExpandedChanged() { if (!pop.ticker.expanded) pop.detail = null }
    }

    // The screener's table needs about twice the watchlist's width.
    Layout.minimumWidth: Kirigami.Units.gridUnit * 24
    Layout.preferredWidth: Kirigami.Units.gridUnit * (detail !== null ? 28 : tab === 1 ? 59 : tab >= 2 ? 36 : 28)
    Layout.preferredHeight: Math.min(Math.max(list.contentHeight, Kirigami.Units.gridUnit * 26)
                                     + header.implicitHeight + footer.implicitHeight,
                                     Kirigami.Units.gridUnit * 32)
    collapseMarginsHint: true

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent
            PlasmaComponents3.TabBar {
                Layout.fillWidth: true
                currentIndex: pop.tab
                onCurrentIndexChanged: { pop.tab = currentIndex; pop.detail = null }
                PlasmaComponents3.TabButton { text: i18n("Watchlist") }
                PlasmaComponents3.TabButton { text: i18n("Screener") }
                PlasmaComponents3.TabButton { text: i18n("Calendar") }
                PlasmaComponents3.TabButton { text: i18n("News") }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                onClicked: pop.ticker.pollAll()
                PlasmaComponents3.ToolTip { text: i18n("Refresh now") }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "internet-web-browser"
                onClicked: Qt.openUrlExternally("https://finance.yahoo.com/markets/")
                PlasmaComponents3.ToolTip { text: i18n("Open Yahoo Markets") }
            }
            PlasmaComponents3.ToolButton {
                icon.name: "configure"
                onClicked: Plasmoid.internalAction("configure").trigger()
                PlasmaComponents3.ToolTip { text: i18n("Add, remove and star symbols") }
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
            }
        }
    }

    News {
        anchors.fill: parent
        visible: pop.detail === null && pop.tab === 3
        engine: pop.ticker.screener
        onOpen: entry => pop.detail = entry
    }

    Calendar {
        anchors.fill: parent
        visible: pop.detail === null && pop.tab === 2
        engine: pop.ticker.screener
        onOpen: entry => pop.detail = entry
    }

    Screener {
        anchors.fill: parent
        visible: pop.detail === null && pop.tab === 1
        engine: pop.ticker.screener
        onOpen: entry => pop.detail = entry
    }

    PlasmaComponents3.ScrollView {
        anchors.fill: parent
        visible: pop.detail === null && pop.tab === 0

        ListView {
            id: list
            model: pop.ticker.symbols
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

            delegate: PlasmaComponents3.ItemDelegate {
                id: row
                required property var modelData
                readonly property var s: modelData
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

                width: ListView.view.width
                onClicked: pop.detail = s

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    // On the tape or not.
                    Kirigami.Icon {
                        source: "starred-symbolic"
                        color: Kirigami.Theme.neutralTextColor
                        opacity: row.s.star ? 1 : 0
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
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
                            text: row.s.label || row.s.symbol
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
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
                            font.family: Kirigami.Theme.fixedWidthFont.family
                            text: row.known ? pop.ticker.format(row.f, row.f.value) : "--"
                            color: row.dirColour
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            font.family: Kirigami.Theme.fixedWidthFont.family
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
                }
            }
        }
    }
}
