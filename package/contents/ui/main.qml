// Plasma Ticker Tape: a market ticker tape for the Plasma panel.
//
// A continuously scrolling strip of instruments, each with its level and a
// green or red triangle for the day's direction. Hover pauses the tape and the
// tooltip carries the full figures; left-click opens the watchlist pop-up
// (Popup.qml), middle-click opens Yahoo Markets.
//
// WHAT IT SHOWS is the watchlist in the widget's settings (Configure Plasma
// Ticker Tape… → Symbols): every symbol there is fetched, and the starred ones run
// on the tape. The list is stored as JSON in the `symbols` config key; see
// contents/config/main.xml for its shape and the default seven.
//
// FETCHING is Yahoo's chart endpoint, called directly with XMLHttpRequest --
// one source for every kind of symbol, and no curl or jq. Each call asks for
// the day in 5-minute bars, so the same request carries the quote and the
// price line the pop-up draws. A request still in
// flight when the next poll comes round is aborted and replaced, so a stalled
// fetch can never stack up one per poll.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "themes.js" as Themes

PlasmoidItem {
    id: root

    // Viewport width, scroll speed in px/s, repaint rate, and poll interval,
    // all but the repaint rate from settings (Tape tab). The tape is a
    // fixed-width viewport, so nothing it does inside can move its
    // neighbours on the panel.
    readonly property int tapeWidth: Kirigami.Units.gridUnit * Plasmoid.configuration.tapeWidth
    readonly property real speed: Plasmoid.configuration.scrollSpeed
    readonly property int fps: 25
    readonly property int pollSeconds: Plasmoid.configuration.pollSeconds

    // Gap between instruments. The tape string ENDS with one, and that
    // trailing copy is the wrap gap, so the seam looks like every other join.
    // Spaces on the tape are written as &nbsp; -- styled text collapses runs
    // of plain spaces -- and only in the TEXT: a space inside a tag must stay
    // a space or the tag stops being one.
    readonly property string sep: "&nbsp;".repeat(5)

    // ── formatting ───────────────────────────────────────────────────────
    // Indices keep whole units with separators: ten points is most of a
    // normal day on the S&P, so compact "7.65K" would sit frozen for hours.
    function commafy(n) {
        return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
    }
    // 81446 -> "81.45K". Thresholds are the ROUNDED boundaries, so 999999
    // becomes "1.00M" rather than "1000.00K".
    function compact(n) {
        if (n >= 999995) return (n / 1e6).toFixed(2) + "M"
        if (n >= 999.995) return (n / 1000).toFixed(2) + "K"
        return n.toFixed(2)
    }
    // The format follows what Yahoo says the symbol IS, so anything added in
    // settings formats sensibly without being told: big indices in whole
    // points, crypto compact in dollars, stocks and funds in dollars, and
    // everything else (VIX, DXY, currencies, futures) as a plain level.
    function format(f, v) {
        switch (f.type) {
        case "INDEX":          return v >= 1000 ? commafy(v) : v.toFixed(2)
        case "CRYPTOCURRENCY": return "$" + compact(v)
        case "EQUITY":
        case "ETF":
        case "MUTUALFUND":     return (f.currency === "USD" ? "$" : "") + v.toFixed(2)
        default:               return v.toFixed(2)
        }
    }
    // Crypto trades round the clock, so its change is over 24 hours.
    function period(f) { return f.type === "CRYPTOCURRENCY" ? "24h" : "Today" }

    // VIX is coloured by LEVEL, not direction -- it is the fear gauge, so red
    // means fear (at or above the fear line in settings) and green means
    // calm. The arrow still shows which way it moved today.
    readonly property string fearSymbol: "^VIX"

    // ── the watchlist ────────────────────────────────────────────────────
    // Parsed from settings; a corrupt value shows an empty tape rather than
    // breaking the widget.
    // `allSymbols` is the list as saved, including the tape's Themes entry
    // ("@themes", which expands into the tickers of the themes running hot);
    // `symbols` is the real ones, which are fetched and make the watchlist.
    readonly property string themesEntry: "@themes"
    readonly property var allSymbols: {
        try { return JSON.parse(Plasmoid.configuration.symbols) } catch (e) { return [] }
    }
    readonly property var symbols: allSymbols.filter(s => s.symbol !== themesEntry)
    readonly property var starred: allSymbols.filter(s => s.star)
    // Edited from the watchlist rows and the quote card as well as from
    // Settings → Symbols: on the tape or not, and off the watchlist.
    function setStar(sym, on) {
        const list = allSymbols.map(s => s.symbol === sym ? Object.assign({}, s, { star: !!on }) : s)
        Plasmoid.configuration.symbols = JSON.stringify(list)
    }
    function removeSymbol(sym) {
        Plasmoid.configuration.symbols = JSON.stringify(allSymbols.filter(s => s.symbol !== sym))
    }
    // A new order for the watchlist (its symbols, the Themes entry left
    // where it was), from a drag in the pop-up.
    function reorderSymbols(order) {
        const real = order.map(sym => allSymbols.find(s => s.symbol === sym && s.symbol !== themesEntry)).filter(s => s)
        for (const s of allSymbols) if (s.symbol !== themesEntry && order.indexOf(s.symbol) < 0) real.push(s)
        const ti = allSymbols.findIndex(s => s.symbol === themesEntry)
        if (ti >= 0) real.splice(Math.min(ti, real.length), 0, allSymbols[ti])
        const text = JSON.stringify(real)
        if (text !== Plasmoid.configuration.symbols) Plasmoid.configuration.symbols = text
    }
    readonly property var themeTape: screenerEngine.tapeThemeTickers()
    onSymbolsChanged: pollAll()

    // Last-known reading per symbol, keyed by symbol. Replaced wholesale on
    // each update so the bindings below (tape text, tooltip) re-evaluate.
    // `meta` keeps Yahoo's whole meta block for the pop-up to come.
    property var feeds: ({})
    function feed(sym) {
        return feeds[sym] || { value: null, pct: null, stale: false, type: "", currency: "" }
    }

    // ── fetching ─────────────────────────────────────────────────────────
    // The User-Agent is not optional: without it Yahoo answers with an empty
    // body (verified 2026-09-01, still true 2026-10-22).
    property var inFlight: ({})
    // When the last reply landed, for the pop-up's footer.
    property date updated

    function fetch(sym) {
        if (inFlight[sym]) inFlight[sym].abort()
        const x = new XMLHttpRequest()
        inFlight[sym] = x
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE || inFlight[sym] !== x) return
            delete inFlight[sym]
            const f = Object.assign({}, feed(sym))
            try {
                const r = JSON.parse(x.responseText).chart.result[0]
                const m = r.meta
                if (typeof m.regularMarketPrice !== "number") throw "no price"
                f.value = m.regularMarketPrice
                // Yahoo's percent is against the previous close; derive it if
                // a symbol type ever arrives without one.
                f.pct = typeof m.regularMarketChangePercent === "number"
                      ? m.regularMarketChangePercent
                      : (m.regularMarketPrice / m.chartPreviousClose - 1) * 100
                f.type = m.instrumentType || ""
                f.currency = m.currency || ""
                f.meta = m
                // The day's closes for the sparkline. Yahoo leaves a null
                // for a bar with no trades; drop those rather than draw a
                // dip to zero.
                const q = r.indicators.quote[0]
                f.spark = (q && q.close ? q.close : []).filter(v => typeof v === "number")
                f.stale = false
            } catch (e) {
                // Request failed or the endpoint changed shape: keep the
                // last number and grey it out -- unless it is a Coinbase
                // pair Yahoo does not carry (most small coins), which the
                // crypto screener already has a live quote for.
                const cq = root.screener.cquotes[sym]
                if (!cq && /^[A-Z0-9]{1,15}-USD$/.test(sym)) { coinbaseQuote(sym, f); return }
                if (cq) {
                    f.value = cq.price
                    f.pct = cq.change
                    f.type = "CRYPTOCURRENCY"
                    f.currency = "USD"
                    f.meta = { longName: cq.name, shortName: cq.name, fullExchangeName: "Coinbase", currency: "USD",
                               instrumentType: "CRYPTOCURRENCY", chartPreviousClose: cq.price / (1 + cq.change / 100) }
                    f.spark = f.spark || []
                    f.stale = false
                } else f.stale = true
            }
            const next = Object.assign({}, root.feeds)
            next[sym] = f
            root.feeds = next
            root.updated = new Date()
        }
        x.open("GET", "https://query1.finance.yahoo.com/v8/finance/chart/"
               + encodeURIComponent(sym) + "?interval=5m&range=1d")
        x.setRequestHeader("User-Agent", "Mozilla/5.0")
        x.send()
    }

    // A Coinbase pair Yahoo does not carry, with no crypto screen on to
    // quote it (PEPE-USD showed "--", 2026-10-24): Coinbase's own 24-hour
    // figures, and its 5-minute candles for the sparkline. Keeps the last
    // number, greyed, when Coinbase has no such pair either.
    function coinbaseQuote(sym, f) {
        const done = () => {
            const next = Object.assign({}, root.feeds)
            next[sym] = f
            root.feeds = next
            root.updated = new Date()
        }
        yget("https://api.exchange.coinbase.com/products/" + encodeURIComponent(sym) + "/stats", x => {
            let d = null
            try { d = JSON.parse(x.responseText) } catch (e) {}
            const last = d ? +d.last : NaN, open = d ? +d.open : NaN
            if (!(last > 0)) { f.stale = true; done(); return }
            f.value = last
            f.pct = open > 0 ? (last / open - 1) * 100 : 0
            f.type = "CRYPTOCURRENCY"
            f.currency = "USD"
            f.meta = { longName: sym, shortName: sym, fullExchangeName: "Coinbase", currency: "USD",
                       instrumentType: "CRYPTOCURRENCY", chartPreviousClose: open > 0 ? open : last }
            f.stale = false
            yget("https://api.exchange.coinbase.com/products/" + encodeURIComponent(sym) + "/candles?granularity=300", y => {
                let c = null
                try { c = JSON.parse(y.responseText) } catch (e) {}
                // Newest first, [time, low, high, open, close, volume]; a day of them.
                f.spark = Array.isArray(c) ? c.slice(0, 288).reverse().map(b => +b[4]).filter(v => v > 0) : (f.spark || [])
                done()
            })
        })
    }

    // ── the quote token ("crumb") ─────────────────────────────────────────
    // Yahoo's fuller quote endpoint (the detail view's figures) answers 401
    // unless the request carries a session cookie and the matching crumb.
    // The cookie comes from any fc.yahoo.com page (it answers 404 but sets
    // the cookie, which Qt's network layer keeps); the crumb then comes from
    // getcrumb. Fetched once and shared; a 401 later means it expired, and
    // the caller clears `crumb` and asks again. Verified 2026-10-22.
    property string crumb: ""
    property var crumbWaiters: null

    function yget(url, done) {
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => { if (x.readyState === XMLHttpRequest.DONE) done(x) }
        x.open("GET", url)
        x.setRequestHeader("User-Agent", "Mozilla/5.0")
        x.send()
        return x
    }
    function withCrumb(done) {
        if (crumb) { done(crumb); return }
        if (crumbWaiters) { crumbWaiters.push(done); return }
        crumbWaiters = [done]
        yget("https://fc.yahoo.com", () => {
            yget("https://query1.finance.yahoo.com/v1/test/getcrumb", x => {
                const c = x.status === 200 ? String(x.responseText).trim() : ""
                // A crumb is a short token; anything else is an error page.
                crumb = c.length > 0 && c.length < 40 ? c : ""
                const waiting = crumbWaiters
                crumbWaiters = null
                for (const w of waiting) w(crumb)
            })
        })
    }

    function pollAll() {
        for (const s of symbols) fetch(s.symbol)
    }

    Timer {
        interval: root.pollSeconds * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollAll()
    }

    // ── the tape ─────────────────────────────────────────────────────────
    // Up and down use the theme's positive/negative colours: here the colour
    // IS the reading, so it must read as plainly green and red. A stale
    // reading greys its direction too -- an arrow left green beside a grey
    // number would claim the one thing a stale reading cannot.
    //
    // Colours go into the markup as plain #rrggbb. A theme colour dropped
    // into a string as-is is not a form StyledText understands, and the
    // whole tape then renders in the default text colour.
    function hex(c) {
        return "#" + [c.r, c.g, c.b].map(x => Math.round(x * 255).toString(16).padStart(2, "0")).join("")
    }
    // Labels come from settings, so they are escaped before going into
    // styled text: a bare ampersand would blank the whole tape, not one label.
    function esc(t) {
        return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;")
                        .replace(/>/g, "&gt;").replace(/ /g, "&nbsp;")
    }
    function segment(s, f) {
        const dim = hex(Kirigami.Theme.disabledTextColor)
        const sym = "<font color='" + dim + "'>" + esc(s.label || s.symbol) + "</font>&nbsp;"
        if (f.value === null)
            return sym + "<font color='" + dim + "'>--</font>"
        const up = f.pct >= 0
        const good = s.symbol === fearSymbol ? f.value < Plasmoid.configuration.fearLine : up
        const colour = f.stale ? dim
                     : hex(good ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor)
        return sym + "<font color='" + colour + "'><b>"
             + format(f, f.value) + "&nbsp;" + (up ? "\u25B2" : "\u25BC") + "</b></font>"
    }

    // The theme's glyph inline in the tape, in its heat colour, at the
    // tape's text height (Settings → Tape → Mark: Icon or Both). StyledText's
    // <img> loads the same self-contained SVG the screener draws; a custom
    // icon that is a file is shown as it is, one from the icon theme cannot
    // be drawn inside styled text and falls back to the built-in glyph.
    readonly property var themeIcons: {
        try { return JSON.parse(Plasmoid.configuration.themeIcons || "{}") } catch (e) { return ({}) }
    }
    readonly property int tapeIconPx: Math.round(tapeMetrics.height * 0.85)
    FontMetrics { id: tapeMetrics; font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace"); font.pointSize: Kirigami.Theme.defaultFont.pointSize }
    function themeImg(theme, status) {
        const heat = Themes.colour(status, (theme && theme.ramp) || Plasmoid.configuration.themeRamp)
        const own = theme ? Themes.custom(theme, themeIcons) : null
        // A file path goes in as a URL, each part encoded, so a ', #, % or ?
        // in it cannot end the attribute or cut the path short.
        const src = own && String(own.icon).charAt(0) === "/"
                  ? "file://" + String(own.icon).split("/").map(encodeURIComponent).join("/").replace(/'/g, "%27")
                  : Themes.icon(theme ? Themes.glyphName(theme, themeIcons) : "dot", heat, Themes.filled(status),
                                Themes.crossed(status), Themes.edge(status, (theme && theme.ramp) || Plasmoid.configuration.themeRamp))
        return "<img src='" + src + "' width='" + tapeIconPx + "' height='" + tapeIconPx + "' align='middle'>"
    }
    readonly property string themeMark: Plasmoid.configuration.tapeThemeMark || "name"
    // A theme's heat in words, translated: the engine's statuses are keys.
    function statusLabel(s) {
        return ({ hot: i18n("hot"), building: i18n("building"), quiet: i18n("quiet"), burnt: i18n("burnt") })[s] || String(s || "")
    }
    // The Themes entry's segments: a dot in the theme's heat colour, the
    // theme's name if wanted, the ticker, its price and direction. While no
    // theme is hot it says so, so the entry is visibly working.
    function themeSegments() {
        const dim = hex(Kirigami.Theme.disabledTextColor)
        if (!themeTape.length)
            return ["<font color='" + dim + "'>" + esc(i18n("Themes: none %1", Plasmoid.configuration.tapeThemeStatus === "building" ? i18n("strong") : i18n("hot"))) + "</font>"]
        return themeTape.map(r => {
            const heat = Themes.colour(r.status, (r.theme && r.theme.ramp) || Plasmoid.configuration.themeRamp)
            // A strong theme with no running ticker: the theme holds the slot.
            // A theme with nothing running always shows its name: without a
            // ticker, the name is the information.
            if (r.kind === "theme")
                return (themeMark === "name" ? "<font color='" + heat + "'>\u25CF</font>" : themeImg(r.theme, r.status))
                     + "&nbsp;<font color='" + heat + "'>" + esc(r.theme.name) + "</font>&nbsp;"
                     + "<font color='" + dim + "'>" + esc(statusLabel(r.status) + (r.streak > 1 ? " · " + i18n("day %1", r.streak) : "")) + "</font>"
            const up = r.change >= 0
            const px = !(r.price > 0) ? "--" : r.price >= 1 ? r.price.toFixed(2) : r.price.toPrecision(4)
            return (themeMark === "name" ? "<font color='" + heat + "'>\u25CF</font>" : themeImg(r.theme, r.status)) + "&nbsp;"
                 + (themeMark !== "icon" ? "<font color='" + heat + "'>" + esc(r.theme.name) + "</font>&nbsp;" : "")
                 + "<font color='" + dim + "'>" + esc(r.symbol.replace(/-USD$/, "")) + "</font>&nbsp;"
                 + "<font color='" + hex(up ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor) + "'><b>"
                 + px + "&nbsp;" + (up ? "\u25B2" : "\u25BC") + "</b></font>"
        })
    }
    readonly property string tapeText: {
        if (starred.length === 0)
            return "<font color='" + hex(Kirigami.Theme.disabledTextColor) + "'>"
                 + "No&nbsp;symbols&nbsp;starred&nbsp;for&nbsp;the&nbsp;tape</font>" + sep
        let parts = []
        for (const s of starred) parts = parts.concat(s.symbol === themesEntry ? themeSegments() : [segment(s, feed(s.symbol))])
        return parts.join(sep) + sep
    }

    // ── the tooltip ──────────────────────────────────────────────────────
    // Every symbol on the tape, not whichever is passing. The change figure
    // is the level now minus the level at the start of the period.
    toolTipMainText: "Markets"
    toolTipTextFormat: Text.RichText
    toolTipSubText: {
        let rows = ""
        for (const s of starred) {
            if (s.symbol === themesEntry) {
                const names = Array.from(new Set(themeTape.map(r => r.theme.name)))
                rows += "<tr><td>" + esc(i18n("Themes")) + "</td><td colspan='3'>&nbsp;&nbsp;"
                      + (names.length ? esc(names.map(n => {
                            const tick = themeTape.filter(r => r.theme.name === n && r.kind === "ticker").map(r => r.symbol)
                            const th = themeTape.find(r => r.theme.name === n)
                            return n + " (" + statusLabel(th.status) + "): " + (tick.length ? tick.join(", ") : i18n("no ticker running now"))
                        }).join(" · "))
                                      : esc(i18n("none strong"))) + "</td></tr>"
                continue
            }
            const f = feed(s.symbol)
            let cells = "<td>" + esc(s.name || s.symbol) + "</td>"
            if (f.value === null) {
                cells += "<td align='right'>--</td><td></td><td></td>"
            } else {
                const opened = f.value / (1 + f.pct / 100)
                const diff = f.value - opened
                cells += "<td align='right'>&nbsp;&nbsp;" + format(f, f.value) + "</td>"
                       + "<td align='right'>&nbsp;&nbsp;" + (f.pct >= 0 ? "+" : "") + f.pct.toFixed(2) + "%</td>"
                       + "<td align='right'>&nbsp;&nbsp;(" + (diff >= 0 ? "+" : "-")
                       + format(f, Math.abs(diff)) + ", " + period(f) + ")"
                       + (f.stale ? " stale" : "") + "</td>"
            }
            rows += "<tr>" + cells + "</tr>"
        }
        return "<table>" + rows + "</table><br>Hover pauses · click for the watchlist · middle-click opens Yahoo Markets"
    }

    // The tape on the panel; the watchlist pop-up when it is clicked, and on
    // its own wherever the widget is placed full size (desktop,
    // plasmawindowed).
    compactRepresentation: tape
    fullRepresentation: Popup { ticker: root }

    // The screener runs from start-up, not from when its tab is opened, so
    // its alert feeds are already collecting the first time they are viewed.
    readonly property alias screener: screenerEngine
    ScreenerEngine {
        id: screenerEngine
        ticker: root
    }
    // What the pop-up and the windows share: unread counts, mutes, the
    // active ticker, layouts, export (Workspace.qml).
    readonly property alias workspace: workspaceItem
    Workspace {
        id: workspaceItem
        ticker: root
    }

    // ── the detached window ──────────────────────────────────────────────
    // The pop-up's content in a window of its own, resizable and kept open
    // beside other programs (TickerWindow.qml). Loaded only while open.
    // The widget's keyboard shortcut (Settings → Keyboard Shortcuts) shows
    // and hides it instead of the pop-up while `hotkeyWindow` is on.
    activationTogglesExpanded: !Plasmoid.configuration.hotkeyWindow
    Connections {
        target: Plasmoid
        function onActivated() {
            if (!Plasmoid.configuration.hotkeyWindow) return
            if (Plasmoid.configuration.windowOpen && windowLoader.item && !windowLoader.item.active)
                windowLoader.item.raiseUp()
            else Plasmoid.configuration.windowOpen = !Plasmoid.configuration.windowOpen
        }
    }
    // The pop-up's pop-out button: the detached window, or with that open,
    // another window on the pop-up's tab and screen (WidgetWindow.qml).
    function popOut(tab, screen) {
        root.expanded = false
        if (Plasmoid.configuration.windowOpen && windowLoader.item) workspaceItem.openWidgetWindow(tab, screen)
        else Plasmoid.configuration.windowOpen = true
    }
    function dockBack() {
        Plasmoid.configuration.windowOpen = false
        root.expanded = true
    }
    Loader {
        id: windowLoader
        active: Plasmoid.configuration.windowOpen
        sourceComponent: TickerWindow { ticker: root }
    }
    // The chart windows (ChartWindow.qml), one per entry in `chartWindows`;
    // reopened after a restart. The model is a ListModel changed one window
    // at a time: given the list of ids as an array, the Instantiator rebuilt
    // every window whenever one opened or closed.
    ListModel { id: chartModel }
    function syncCharts() {
        const ids = workspaceItem.chartIds
        for (let i = chartModel.count - 1; i >= 0; i--)
            if (ids.indexOf(chartModel.get(i).chartId) < 0) chartModel.remove(i)
        for (const id of ids) {
            let found = false
            for (let i = 0; i < chartModel.count && !found; i++) found = chartModel.get(i).chartId === id
            if (!found) chartModel.append({ chartId: id })
        }
    }
    Connections {
        target: workspaceItem
        function onChartIdsChanged() { root.syncCharts() }
    }
    Instantiator {
        id: chartWindows
        model: chartModel
        // ChartWindow's required `chartId` is filled from the model's role.
        delegate: ChartWindow { ticker: root }
        Component.onCompleted: root.syncCharts()
    }
    // The widget windows (WidgetWindow.qml), one per entry in
    // `widgetWindows`, made the same way.
    ListModel { id: widgetModel }
    function syncWidgetWindows() {
        const ids = workspaceItem.widgetIds
        for (let i = widgetModel.count - 1; i >= 0; i--)
            if (ids.indexOf(widgetModel.get(i).windowId) < 0) widgetModel.remove(i)
        for (const id of ids) {
            let found = false
            for (let i = 0; i < widgetModel.count && !found; i++) found = widgetModel.get(i).windowId === id
            if (!found) widgetModel.append({ windowId: id })
        }
    }
    Connections {
        target: workspaceItem
        function onWidgetIdsChanged() { root.syncWidgetWindows() }
    }
    Instantiator {
        model: widgetModel
        delegate: WidgetWindow { ticker: root }
        Component.onCompleted: root.syncWidgetWindows()
    }

    Component {
        id: tape
        Item {
            id: cell
            Layout.minimumWidth: root.tapeWidth
            Layout.preferredWidth: root.tapeWidth
            Layout.maximumWidth: root.tapeWidth
            Layout.fillHeight: true
            clip: true

            // Scroll offset, advanced by a timer rather than an animation so a
            // tape whose width changes on a price update carries on from where it
            // was instead of jumping back to the start.
            property real offset: 0

            Row {
                x: -cell.offset
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    // Two copies end to end: as the first scrolls off the left,
                    // the second is already in place behind it.
                    model: 2
                    Text {
                        id: copy
                        text: root.tapeText
                        textFormat: Text.StyledText
                        color: Kirigami.Theme.textColor
                        font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace")
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize
                        onImplicitWidthChanged: if (index === 0) cell.loopWidth = implicitWidth
                        Component.onCompleted: if (index === 0) cell.loopWidth = implicitWidth
                    }
                }
            }
            property real loopWidth: 1

            Timer {
                interval: 1000 / root.fps
                running: !mouse.containsMouse
                repeat: true
                onTriggered: cell.offset = (cell.offset + root.speed / root.fps) % Math.max(1, cell.loopWidth)
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onClicked: mouseEvent => {
                    if (mouseEvent.button === Qt.MiddleButton)
                        Qt.openUrlExternally("https://finance.yahoo.com/markets/")
                    else
                        root.expanded = !root.expanded
                }
            }
        }
    }
}
