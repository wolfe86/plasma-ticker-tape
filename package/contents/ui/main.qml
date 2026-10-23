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
    readonly property var symbols: {
        try { return JSON.parse(Plasmoid.configuration.symbols) } catch (e) { return [] }
    }
    readonly property var starred: symbols.filter(s => s.star)
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
                // last number and grey it out.
                f.stale = true
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

    readonly property string tapeText: {
        if (starred.length === 0)
            return "<font color='" + hex(Kirigami.Theme.disabledTextColor) + "'>"
                 + "No&nbsp;symbols&nbsp;starred&nbsp;for&nbsp;the&nbsp;tape</font>" + sep
        return starred.map(s => segment(s, feed(s.symbol))).join(sep) + sep
    }

    // ── the tooltip ──────────────────────────────────────────────────────
    // Every symbol on the tape, not whichever is passing. The change figure
    // is the level now minus the level at the start of the period.
    toolTipMainText: "Markets"
    toolTipTextFormat: Text.RichText
    toolTipSubText: {
        let rows = ""
        for (const s of starred) {
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
                        font.family: Kirigami.Theme.fixedWidthFont.family
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
