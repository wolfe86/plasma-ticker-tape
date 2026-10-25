// TradingView's chart in a web view, for a TradingView chart window
// (ChartWindow.qml). Loaded through a Loader there, so a system without Qt
// WebEngine (the qt6-webengine package; qml6-module-qtwebengine on Debian)
// still loads the widget and the window just says what is missing.
//
// Two modes (`tvMode`, Settings → Data):
//   page   -- TradingView's full chart page: every indicator and drawing
//             tool, and with an account its saved layouts. Signing in is
//             done on TradingView's own page, in this view; the widget never
//             sees or stores the password. The session cookie is kept in this
//             widget's own web profile, so it survives a restart.
//   widget -- TradingView's embeddable chart, which needs no account.
// Another symbol or bar size is switched in place through the page's own
// TradingViewApi (tradingview.js `switchScript`), so the page does not
// reload and nothing drawn on it is lost. Only if that fails is the page
// reloaded, and then TradingView's "leave this page?" prompt is answered
// for it.
//
// LAYOUTS: TradingView autosaves a chart layout once it has a name (its
// Save button, signed in). When the page's address turns into a saved
// layout's (/chart/<id>/), the window keeps that id (`layoutId`, saved in
// `chartWindows` as `tvLayout`) and opens that layout from then on.

import QtQuick
import QtWebEngine
import org.kde.plasma.plasmoid
import "tradingview.js" as TV

Item {
    id: tvv

    // Set by the window once loaded (a Loader with a source cannot set
    // required properties).
    property string symbol: ""            // Yahoo's
    property string rangeKey: "5m"        // a chart range key
    property string layoutId: ""          // a saved TradingView layout, or ""
    signal layoutSaved(string id)
    // A chart page has loaded and its TradingViewApi is there.
    property bool pageReady: false
    // A navigation the widget started: TradingView's "leave this page?"
    // prompt is answered for it.
    property bool ourNav: false
    property string mode: "page"
    property bool dark: true
    // Signed in to TradingView, as its page reports it; null until known.
    property var signedIn: null
    property string user: ""

    // The widget's one shared web profile (TvProfile.qml), set by the
    // window. The page is made only once it is set: a view starts on the
    // default profile and cannot be moved to another afterwards.
    property var webProfile: null
    readonly property var view: viewLoader.item
    property bool signInWanted: false
    onViewChanged: if (view) { if (signInWanted) signIn(); else show() }

    function show() {
        if (!symbol || !view) return
        if (mode === "widget") { signedIn = null; view.loadHtml(TV.widgetHtml(symbol, rangeKey, dark), "https://www.tradingview.com/"); return }
        if (pageReady) {
            view.runJavaScript(TV.switchScript(symbol, rangeKey), r => { if (r !== "ok") tvv.load() })
            return
        }
        load()
    }
    function load() {
        if (!view) return
        pageReady = false
        signedIn = null
        ourNav = true
        view.url = TV.pageUrl(symbol, rangeKey, layoutId)
    }
    function signIn() {
        if (mode === "widget") return
        if (!view) { signInWanted = true; return }
        signInWanted = false
        pageReady = false
        ourNav = true
        view.url = "https://www.tradingview.com/accounts/signin/"
    }
    // Who is signed in, kept in the settings so Settings → Data can say
    // ("" signed out). Never the password.
    onSignedInChanged: if (signedIn !== null && mode !== "widget") {
        const u = signedIn ? (user || "yes") : ""
        if (Plasmoid.configuration.tvUser !== u) Plasmoid.configuration.tvUser = u
    }
    function reloadChart() { load() }
    onSymbolChanged: show()
    onModeChanged: show()
    // A new bar size changes only the bar size (see resolutionScript).
    onRangeKeyChanged: {
        if (pageReady && view && mode !== "widget") view.runJavaScript(TV.resolutionScript(rangeKey), r => { if (r !== "ok") tvv.load() })
        else show()
    }

    // TradingView's pages say who is signed in, in a global they set
    // themselves; read once a page has loaded.
    function checkUser() {
        if (!view) return
        // `is_authenticated` is the answer: signed out, `user.username` is
        // "Guest" (checked 2026-10-25).
        view.runJavaScript("(function(){try{var a=window.is_authenticated===true,u=window.user||{};return JSON.stringify({auth: a, name: a ? (u.username||'') : ''})}catch(e){return ''}})()", r => {
            try { const o = JSON.parse(r); tvv.signedIn = o.auth; tvv.user = o.name || "" } catch (e) {}
        })
    }

    Loader {
        id: viewLoader
        anchors.fill: parent
        active: !!tvv.webProfile
        sourceComponent: WebEngineView {
        profile: tvv.webProfile
        onLoadingChanged: req => {
            // The page sets who is signed in as it starts up, so ask again a
            // few seconds after it has loaded.
            if (req.status !== WebEngineView.LoadStartedStatus) tvv.ourNav = false
            if (req.status === WebEngineView.LoadSucceededStatus && /tradingview\.com/.test(String(req.url))) { tvv.checkUser(); recheck.tries = 0; recheck.restart() }
            if (req.status === WebEngineView.LoadSucceededStatus && /\/chart\//.test(String(req.url))) { pagePoll.tries = 0; pagePoll.restart() }
            // Signed in on the sign-in page: back to the chart.
            if (req.status === WebEngineView.LoadSucceededStatus && /\/accounts\/signin/.test(String(req.url))) waitSignIn.start()
        }
        // Links that open a new window (news, ideas) go to the browser.
        onNewWindowRequested: req => Qt.openUrlExternally(req.requestedUrl)
        // "Leave this page?" on a reload the widget started: yes. Anything
        // else TradingView asks is shown as usual.
        onJavaScriptDialogRequested: req => {
            if (req.type === JavaScriptDialogRequest.DialogTypeBeforeUnload && tvv.ourNav) {
                req.accepted = true
                req.dialogAccept()
            }
        }
        }
    }
    // Who is signed in, asked again until the page answers (it sets it as it
    // starts up), up to a minute.
    Timer {
        id: recheck
        property int tries: 0
        interval: 4000
        repeat: true
        onTriggered: { if (tvv.signedIn !== null || ++tries > 15) stop(); else tvv.checkUser() }
    }
    // Once the chart page is up: is its API there (then symbols switch in
    // place), and has the layout been saved under a name (then the window
    // keeps its id)?
    Timer {
        id: pagePoll
        property int tries: 0
        interval: 2000
        repeat: true
        onTriggered: {
            if (!tvv.view) return
            tries++
            tvv.view.runJavaScript("JSON.stringify({api: !!(window.TradingViewApi && window.TradingViewApi.activeChart), path: location.pathname})", r => {
                let o = null
                try { o = JSON.parse(r) } catch (e) { return }
                if (o.api && !tvv.pageReady) {
                    tvv.pageReady = true
                    // The page may have opened on a symbol since changed.
                    tvv.view.runJavaScript(TV.switchScript(tvv.symbol, tvv.rangeKey), () => {})
                }
                const m = String(o.path).match(/^\/chart\/([A-Za-z0-9]+)\/?$/)
                if (m && m[1] !== tvv.layoutId) tvv.layoutSaved(m[1])
            })
            // Fast at first, then every 10 s to notice a layout being saved.
            if (tries > 10) interval = 10000
        }
    }
    // While the sign-in page is open, check every few seconds whether it
    // has signed in, and return to the chart when it has.
    Timer {
        id: waitSignIn
        interval: 3000
        repeat: true
        onTriggered: {
            if (!tvv.view || !/\/accounts\/signin/.test(String(tvv.view.url))) { stop(); return }
            tvv.checkUser()
            if (tvv.signedIn) { stop(); tvv.show() }
        }
    }
}
