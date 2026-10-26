// A chart window: one symbol's chart, in a window of its own, opened from
// the chart's window button (or TradingView's, the TV button) on a quote
// card. Several can be open, each at its own bar size -- 1-minute, 5-minute
// and daily side by side, say.
//
// A window follows the active ticker (whatever was opened last: a screener
// row, the watchlist, a typed symbol) until it is pinned, and then keeps its
// symbol. Each window's symbol, bar size and size are kept in
// `chartWindows` (Workspace.qml), so the set comes back after a restart, and
// a saved layout carries it.
//
// kind "chart" is the widget's own chart (Detail.qml with chartOnly);
// kind "tv" is TradingView's (TradingViewView.qml), loaded only if Qt
// WebEngine is installed;
// kind "quote" is the whole quote card (Detail.qml with inWindow), opened
// from the card's window button. While a linked one is open, tickers
// clicked in the pop-up's lists show here instead of in the pop-up
// (Popup.open), so the list stays.

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Window {
    id: cw

    required property var ticker
    required property string chartId
    readonly property var ws: ticker.workspace
    readonly property var spec: ws.chart(chartId) || ({})
    readonly property bool tv: spec.kind === "tv"
    readonly property bool quote: spec.kind === "quote"
    readonly property bool pinned: !!spec.symbol
    // The symbol on show: the pinned one, else the active ticker, else the
    // first on the watchlist.
    readonly property var entry: pinned ? { symbol: spec.symbol, label: spec.label || spec.symbol, name: spec.name || spec.symbol, star: false }
                               : ws.active ? ws.active
                               : (ticker.symbols[0] || { symbol: "^GSPC", label: "S&P 500", name: "S&P 500", star: false })
    readonly property string rangeKey: spec.range || "5m"

    // Which chart it is, first: the widget's own chart, or TradingView's.
    // Its number stays with it, so a KWin window rule can match "TradingView 2"
    // and put the window back on its monitor (Wayland does not let a program
    // place its own windows).
    readonly property string kindName: tv ? i18n("TradingView") : quote ? i18n("Quote") : i18n("Widget chart")
    title: kindName + (spec.n ? " " + spec.n : "") + " · "
           + String(entry.label || entry.symbol) + (tv || quote ? "" : " · " + rangeKey) + (pinned ? " · " + i18n("unlinked") : "")
    color: Kirigami.Theme.backgroundColor
    minimumWidth: Kirigami.Units.gridUnit * 16
    minimumHeight: Kirigami.Units.gridUnit * 10

    Component.onCompleted: {
        width = Math.max(minimumWidth, spec.w || Kirigami.Units.gridUnit * (quote ? 30 : 40))
        height = Math.max(minimumHeight, spec.h || Kirigami.Units.gridUnit * (quote ? 38 : 26))
        show()
        raise()
    }
    onWidthChanged: saveSoon.restart()
    onHeightChanged: saveSoon.restart()
    Timer {
        id: saveSoon
        interval: 800
        onTriggered: if (cw.visible && cw.visibility !== Window.FullScreen && cw.visibility !== Window.Maximized)
                         cw.ws.updateChart(cw.chartId, { w: cw.width, h: cw.height })
    }
    onClosing: close => cw.ws.closeChart(cw.chartId)
    // Asked to come forward, or to open TradingView's sign-in page (from
    // Settings → Workspace or the pop-up).
    readonly property real raiseAt: spec.raise || 0
    onRaiseAtChanged: if (raiseAt) { show(); raise(); requestActivate() }
    readonly property real signInAt: spec.signIn || 0
    onSignInAtChanged: doSignIn()
    function doSignIn() {
        if (!signInAt || !tvLoader.item) return
        tvLoader.item.signIn()
        show(); raise(); requestActivate()
        // Later, not while the list of windows is being read (a binding loop).
        Qt.callLater(() => cw.ws.updateChart(cw.chartId, { signIn: 0 }))
    }

    Rectangle { anchors.fill: parent; color: Kirigami.Theme.backgroundColor }

    // ── screenshots ──
    property string shotNote: ""
    property string lastShot: ""
    function shoot() {
        const target = quote ? quoteLoader : tv ? tvLoader : chartLoader
        const path = ws.shotPath(entry.symbol, quote ? "quote" : (tv ? "tv-" : "chart-") + rangeKey)
        ws.run("mkdir -p " + ws.shq(ws.shotDir), ok => {
            if (!ok) { shotNote = i18n("Could not make %1", ws.shotDir); shotClear.restart(); return }
            target.grabToImage(r => {
                const saved = r.saveToFile(path)
                if (saved) lastShot = path
                shotNote = saved ? i18n("Saved %1", path.replace(/^.*\//, "")) : i18n("Could not save the screenshot")
                shotClear.restart()
            })
        })
    }
    Timer { id: shotClear; interval: 6000; onTriggered: cw.shotNote = "" }
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        // ── the window's bar ──
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            // What this window is, as a badge: the two kinds look alike at a glance.
            Rectangle {
                implicitWidth: kindLabel.implicitWidth + Kirigami.Units.largeSpacing
                implicitHeight: kindLabel.implicitHeight + Kirigami.Units.smallSpacing
                radius: 3
                color: cw.tv ? "#2962ff" : Kirigami.Theme.highlightColor
                PlasmaComponents3.Label {
                    id: kindLabel
                    anchors.centerIn: parent
                    text: cw.kindName + (cw.spec.n ? " " + cw.spec.n : "")
                    font.bold: true
                    color: "white"
                }
            }
            // Linked: follows the active ticker. Unlinked: keeps its own
            // symbol, so several windows can watch different tickers.
            PlasmaComponents3.ToolButton {
                icon.name: cw.pinned ? "remove-link" : "link"
                checkable: true
                checked: !cw.pinned
                text: cw.pinned ? i18n("Unlinked") : i18n("Linked")
                onClicked: cw.ws.updateChart(cw.chartId, cw.pinned
                    ? { symbol: "", label: "", name: "" }
                    : { symbol: cw.entry.symbol, label: cw.entry.label || cw.entry.symbol, name: cw.entry.name || cw.entry.symbol })
                PlasmaComponents3.ToolTip {
                    text: cw.pinned ? i18n("Unlinked: this window keeps %1. Click to link it again: it then follows whatever you open next.", cw.entry.symbol)
                                    : i18n("Linked: this window follows the symbol you open anywhere. Click to unlink it and keep %1 here.", cw.entry.symbol)
                }
            }
            // Another symbol for this window alone: unlinks it.
            // (A quote window has the card's own box instead.)
            PlasmaComponents3.TextField {
                id: windowSymbol
                visible: !cw.quote
                implicitWidth: Kirigami.Units.gridUnit * 6
                placeholderText: i18n("Symbol…")
                onAccepted: {
                    const typed = text
                    text = ""
                    cw.ws.resolve(typed, e => cw.ws.updateChart(cw.chartId, { symbol: e.symbol, label: e.label || e.symbol, name: e.name || e.symbol }))
                }
                PlasmaComponents3.ToolTip { text: i18n("Type a symbol for this window only and press Enter. The window is unlinked, so it keeps it while the others follow what you open.") }
            }
            // TradingView's bar size, kept per window, so several windows
            // can each hold a time frame while they follow the same symbol.
            Repeater {
                model: cw.tv ? [{ k: "1m", t: "1m" }, { k: "5m", t: "5m" }, { k: "15m", t: "15m" }, { k: "1h", t: "1h" },
                                { k: "1Y", t: i18n("Day") }, { k: "5Y", t: i18n("Week") }] : []
                PlasmaComponents3.ToolButton {
                    required property var modelData
                    text: modelData.t
                    checkable: true
                    checked: cw.rangeKey === modelData.k
                    onClicked: cw.ws.updateChart(cw.chartId, { range: modelData.k })
                    PlasmaComponents3.ToolTip { text: i18n("Bar size for this window; kept when the symbol changes") }
                }
            }
            Item { Layout.fillWidth: true }
            // TradingView: who is signed in, and a way to sign in.
            PlasmaComponents3.Label {
                visible: cw.tv && !!tvLoader.item && Plasmoid.configuration.tvMode !== "widget"
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: !tvLoader.item ? "" : tvLoader.item.signedIn === null ? i18n("Checking sign-in…")
                      : tvLoader.item.signedIn ? (tvLoader.item.user ? i18n("Signed in as %1", tvLoader.item.user) : i18n("Signed in"))
                      : i18n("Not signed in")
            }
            // Shown until TradingView says it is signed in, so it is there
            // even while the page is still loading.
            PlasmaComponents3.ToolButton {
                visible: cw.tv && !!tvLoader.item && Plasmoid.configuration.tvMode !== "widget" && tvLoader.item.signedIn !== true
                icon.name: "im-user-online"
                text: i18n("Sign in")
                onClicked: tvLoader.item.signIn()
                PlasmaComponents3.ToolTip { text: i18n("Opens TradingView's own sign-in page here. Optional: the chart works without an account. The widget never sees or saves your password.") }
            }
            PlasmaComponents3.ToolButton {
                visible: cw.tv && !!tvLoader.item
                icon.name: "view-refresh"
                onClicked: tvLoader.item.reloadChart()
                PlasmaComponents3.ToolTip { text: i18n("Reload the chart") }
            }
            // A picture of the chart, saved at once in the screenshots
            // folder the journal's notes use (Workspace.shotDir).
            PlasmaComponents3.Label {
                visible: cw.shotNote !== ""
                font: Kirigami.Theme.smallFont
                opacity: 0.8
                text: cw.shotNote
            }
            PlasmaComponents3.ToolButton {
                icon.name: "camera-photo"
                onClicked: cw.shoot()
                PlasmaComponents3.ToolTip {
                    text: cw.quote ? i18n("Save a screenshot of this quote, as shown, in %1", cw.ws.shotDir)
                                   : i18n("Save a screenshot of this chart in %1", cw.ws.shotDir)
                }
            }
            PlasmaComponents3.ToolButton {
                visible: cw.lastShot !== ""
                icon.name: "folder-open"
                onClicked: Qt.openUrlExternally("file://" + encodeURI(cw.ws.shotDir))
                PlasmaComponents3.ToolTip { text: i18n("Open the screenshots folder") }
            }
        }

        // ── the widget's own chart ──
        Loader {
            id: chartLoader
            // Its own background, under the chart: a screenshot of the
            // Loader alone would otherwise be see-through.
            Rectangle { anchors.fill: parent; z: -1; color: Kirigami.Theme.backgroundColor }
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Hidden as well as inactive: an empty Loader still takes its
            // share of the height.
            visible: active
            active: !cw.tv && !cw.quote
            sourceComponent: Detail {
                ticker: cw.ticker
                entry: cw.entry
                chartOnly: true
                rangeIndex: Math.max(0, ranges.findIndex(r => r.key === cw.rangeKey))
                onRangeIndexChanged: cw.ws.updateChart(cw.chartId, { range: ranges[rangeIndex].key })
            }
        }

        // ── the quote card ──
        // A symbol picked on the card (its box, a recent ticker) is the
        // active ticker while linked, so the linked charts follow it too;
        // unlinked, it is this window's alone.
        Loader {
            id: quoteLoader
            // Its own background, for the screenshot (as the chart's).
            Rectangle { anchors.fill: parent; z: -1; color: Kirigami.Theme.backgroundColor }
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: active
            active: cw.quote
            sourceComponent: PlasmaComponents3.ScrollView {
                id: quoteScroll
                PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff
                contentWidth: availableWidth
                Detail {
                    width: quoteScroll.availableWidth
                    ticker: cw.ticker
                    entry: cw.entry
                    inWindow: true
                    linked: !cw.pinned
                    rangeIndex: Math.max(0, ranges.findIndex(r => r.key === cw.rangeKey))
                    onRangeIndexChanged: cw.ws.updateChart(cw.chartId, { range: ranges[rangeIndex].key })
                    onGo: e => {
                        if (cw.pinned) cw.ws.updateChart(cw.chartId, { symbol: e.symbol, label: e.label || e.symbol, name: e.name || e.symbol })
                        else cw.ws.setActive(e)
                    }
                }
            }
        }

        // ── TradingView's ──
        Loader {
            id: tvLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: active
            active: cw.tv
            source: "TradingViewView.qml"
            onLoaded: {
                item.webProfile = cw.ws.wantTvProfile()
                item.layoutId = cw.spec.tvLayout || ""
                item.layoutSaved.connect(id => cw.ws.updateChart(cw.chartId, { tvLayout: id }))
                item.rangeKey = Qt.binding(() => cw.rangeKey)
                item.mode = Qt.binding(() => Plasmoid.configuration.tvMode === "widget" ? "widget" : "page")
                item.dark = Qt.binding(() => Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark)
                item.symbol = Qt.binding(() => cw.entry.symbol)       // last: it loads the page
                cw.doSignIn()
            }
        }
        PlasmaComponents3.Label {
            visible: cw.tv && tvLoader.status === Loader.Error
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Kirigami.Units.largeSpacing
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            text: i18n("TradingView charts need Qt WebEngine, which is not installed: the qt6-webengine package (Arch), or qml6-module-qtwebengine (Debian and Ubuntu).")
        }
        // In embedded mode there is no account to sign in to.
        PlasmaComponents3.Label {
            visible: cw.tv && Plasmoid.configuration.tvMode === "widget" && cw.signInAt > 0
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            wrapMode: Text.WordWrap
            text: i18n("The embedded chart has no sign-in. To use your TradingView account, choose \"Full chart page\" under Settings → Data → TradingView windows.")
        }
    }
}
