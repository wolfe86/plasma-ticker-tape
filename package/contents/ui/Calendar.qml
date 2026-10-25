// The Calendar tab: economic releases and earnings, as a day, a week or a
// month.
//
// Data from the engine's `calendarDays` (the scanner's calendar_events.py,
// through the bridge). The tab tells the engine which span it is showing
// (`wantCalendar`) and the engine fetches any day of it not yet held.
//
//   Day   -- one day as a list: the economic releases in time order with a
//            "now" line through today, then the reporters before the open
//            and after the close, with expected, previous and actual.
//   Week  -- Monday to Friday side by side (a weekend day too, when
//            something is on it): release cards by time, reporters below.
//   Month -- a calendar grid of weekdays: importance dots, the day's
//            biggest release and how many report. Click a day to open it.
//
// A dot marks how much an event matters, by the scanner's own ranking.
// Clicking a reporter opens its detail view. Sector and theme glyphs sit
// beside reporters (GroupIcons; looked up for the day or week on screen),
// and a release links to where it is published: an economic release to its
// agency's page, a printed earnings report to its press release on SEC
// EDGAR. Times are New York time. The
// view is remembered (`calendarView`); the date always opens on today
// (the coming Monday at a weekend).

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: cal

    required property var engine
    signal open(var entry)

    property string show: "all"           // all | econ | earnings
    readonly property string view: Plasmoid.configuration.calendarView || "week"
    property date anchor: home()
    spacing: 0

    // ── dates ───────────────────────────────────────────────────────────
    function noon(d) { const x = new Date(d); x.setHours(12, 0, 0, 0); return x }
    function iso(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    function addDays(d, n) { const x = noon(d); x.setDate(x.getDate() + n); return x }
    function monday(d) { return addDays(d, -((d.getDay() + 6) % 7)) }
    function weekend(d) { return d.getDay() === 0 || d.getDay() === 6 }
    // Where "Today" lands: today, or on a weekend the coming Monday -- the
    // week just ended is not what anyone opens the calendar for on a Sunday.
    function home() {
        const d = noon(new Date())
        return weekend(d) ? addDays(d, d.getDay() === 6 ? 2 : 1) : d
    }
    property date now: new Date()
    readonly property string todayIso: iso(now)
    Timer {
        interval: 60000; repeat: true; running: cal.visible; triggeredOnStart: true
        onTriggered: cal.now = new Date()
    }

    // The span on screen, in whole weeks so stepping a day stays in hand.
    readonly property var span: {
        if (view === "month") {
            const first = new Date(anchor.getFullYear(), anchor.getMonth(), 1, 12)
            const last = new Date(anchor.getFullYear(), anchor.getMonth() + 1, 0, 12)
            const start = monday(first)
            const end = addDays(monday(last), 6)
            return { start: start, days: Math.round((end - start) / 86400000) + 1 }
        }
        return { start: monday(anchor), days: 7 }
    }
    readonly property string spanKey: iso(span.start) + ":" + span.days
    onSpanKeyChanged: engine.wantCalendar(iso(span.start), span.days)
    Component.onCompleted: engine.wantCalendar(iso(span.start), span.days)

    function setView(v) { Plasmoid.configuration.calendarView = v }
    function step(dir) {
        if (view === "month") {
            // The anchor keeps its day of the month (cut to the month's
            // length), so Week or Day opened from here is not the 1st; the
            // month holding today lands back on today.
            const first = new Date(anchor.getFullYear(), anchor.getMonth() + dir, 1, 12)
            const t = noon(now), h = home()
            if (first.getFullYear() === t.getFullYear() && first.getMonth() === t.getMonth()) {
                anchor = h.getMonth() === t.getMonth() ? h : t
            } else {
                const last = new Date(first.getFullYear(), first.getMonth() + 1, 0, 12).getDate()
                anchor = new Date(first.getFullYear(), first.getMonth(), Math.min(anchor.getDate(), last), 12)
            }
        } else if (view === "week") {
            anchor = addDays(anchor, 7 * dir)
        } else {
            // Weekends are skipped unless something is on them.
            let d = addDays(anchor, dir)
            while (weekend(d) && !(raw(iso(d)) || []).length) d = addDays(d, dir)
            anchor = d
        }
    }
    function openDay(d) { anchor = noon(d); setView("day") }

    readonly property string title: {
        if (view === "month") return Qt.formatDate(anchor, "MMMM yyyy")
        if (view === "week") {
            const a = span.start, b = addDays(span.start, 4)
            return Qt.formatDate(a, "MMM d") + " – "
                 + (a.getMonth() === b.getMonth() ? Qt.formatDate(b, "d") : Qt.formatDate(b, "MMM d"))
        }
        const d = Qt.formatDate(anchor, "ddd, MMM d")
        const diff = Math.round((anchor - noon(now)) / 86400000)
        return diff === 0 ? i18n("Today · %1", d) : diff === 1 ? i18n("Tomorrow · %1", d)
             : diff === -1 ? i18n("Yesterday · %1", d) : d
    }

    // ── events ──────────────────────────────────────────────────────────
    // undefined = not fetched yet, null = the feed could not be read.
    function raw(day) { return engine.calendarDays[day] }
    function econOf(events) {
        return (events || []).filter(e => e.kind === "econ" && show !== "earnings")
            .sort((a, b) => String(a.when || "~").localeCompare(String(b.when || "~")))
    }
    function earnOf(events) {
        return (events || []).filter(e => e.kind === "earnings" && show !== "econ")
    }
    function countOn(d) { const ev = raw(iso(d)); return econOf(ev).length + earnOf(ev).length }
    function hasActual(e) { return e.actual !== null && e.actual !== undefined && e.actual !== "" }
    function past(e) {
        if (e.date < todayIso) return true
        if (e.date > todayIso) return false
        if (e.kind === "econ") return !!e.when && Date.parse(e.when) <= now.getTime()
        return hasActual(e)
    }

    // ── formatting ──────────────────────────────────────────────────────
    function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    // "2026-10-28T14:00:00-04:00" -> "2:00 pm", read as New York time.
    function etTime(iso) {
        if (!iso) return ""
        const m = String(iso).match(/T(\d\d):(\d\d)/)
        if (!m) return ""
        const h = parseInt(m[1])
        return (h % 12 || 12) + ":" + m[2] + (h < 12 ? " am" : " pm")
    }
    function big(v) {
        if (!(v > 0)) return ""
        if (v >= 1e12) return "$" + (v / 1e12).toFixed(2) + "T"
        if (v >= 1e9) return "$" + (v / 1e9).toFixed(1) + "B"
        if (v >= 1e6) return "$" + (v / 1e6).toFixed(0) + "M"
        return "$" + Math.round(v)
    }
    function figure(v) { return v === null || v === undefined || v === "" ? "—" : String(v) }
    function importance(score) {
        return score >= 90 ? Kirigami.Theme.negativeTextColor
             : score >= 70 ? Kirigami.Theme.neutralTextColor
             : Kirigami.Theme.disabledTextColor
    }
    function sessionText(s) {
        return ({ bmo: i18n("before the open"), amc: i18n("after the close") })[s] || i18n("time not given")
    }
    // "18.50K" -> 18500, "$1.27" -> 1.27, "-0.2%" -> -0.2; NaN if not a number.
    function num(v) {
        const m = String(v === null || v === undefined ? "" : v).replace(/,/g, "").match(/(-?\d+(?:\.\d+)?)\s*([KMBT])?/i)
        if (!m) return NaN
        return parseFloat(m[1]) * (({ K: 1e3, M: 1e6, B: 1e9, T: 1e12 })[(m[2] || "").toUpperCase()] || 1)
    }
    // Actual against expected: 1 above, -1 below, 0 level or not comparable.
    function versus(e) {
        const a = num(e.actual), x = num(e.expected)
        return isNaN(a) || isNaN(x) ? 0 : a > x ? 1 : a < x ? -1 : 0
    }
    function arrow(e) { const v = versus(e); return v > 0 ? " ▲" : v < 0 ? " ▼" : "" }
    // Earnings: above the estimate is a beat, green; below a miss, red.
    // Economic: above or below the consensus is marked, not judged -- a hot
    // CPI is "above" and good for nobody.
    function actualText(e) {
        return i18n("Actual %1", figure(e.actual)) + arrow(e)
             + (e.surprise !== null && e.surprise !== undefined && e.surprise !== "" ? " · " + i18n("surprise %1%", e.surprise) : "")
    }
    function actualColor(e) {
        const v = versus(e)
        if (e.kind !== "earnings" || !hasActual(e) || v === 0) return Kirigami.Theme.textColor
        return v > 0 ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
    }
    function tip(e) {
        const head = e.kind === "earnings"
            ? e.ticker + " · " + (e.name || "") + (e.mcap ? " · " + big(e.mcap) : "") + "\n" + i18n("Reports %1", sessionText(e.session))
            : e.label + "\n" + (etTime(e.when) ? i18n("%1 New York", etTime(e.when)) : i18n("All day"))
        const nums = (e.kind === "earnings" ? i18n("EPS est %1", figure(e.expected)) : i18n("Expected %1", figure(e.expected)))
                   + " · " + i18n("Previous %1", figure(e.previous))
        const l = linkOf(e)
        return head + "\n" + nums + (hasActual(e) ? "\n" + actualText(e) : "")
             + (l ? "\n" + (e.kind === "econ" ? i18n("Release: %1", l.source) : i18n("Press release: %1", l.source)) : "")
    }
    // Where to read it: the agency's page for a release, the press release
    // on EDGAR for a reporter that has printed. {url, source} or null.
    function linkOf(e) {
        if (e.kind === "econ") return e.link ? { url: e.link, source: e.source || "" } : null
        const u = engine.calendarReleases[e.ticker + ":" + e.date]
        return u ? { url: u, source: i18n("SEC EDGAR") } : null
    }
    function openLink(e) {
        const l = linkOf(e)
        if (l && /^https?:\/\//i.test(l.url)) Qt.openUrlExternally(l.url)
    }
    // Sector look-ups for the reporters on screen, and their press releases
    // once printed. A month asks only for this week and next.
    function requestLookups() {
        let days = []
        if (view === "day") days = [iso(anchor)]
        else {
            const from = view === "week" ? span.start : monday(noon(now))
            for (let i = 0; i < (view === "week" ? 7 : 14); i++) days.push(iso(addDays(from, i)))
        }
        const ticks = [], rel = []
        for (const d of days) for (const e of raw(d) || []) {
            if (e.kind !== "earnings" || !e.ticker) continue
            ticks.push(e.ticker)
            if (hasActual(e) || e.date < todayIso) rel.push(e.ticker + ":" + e.date)
        }
        engine.lookupGroups(ticks)
        if (view !== "month") engine.wantReleases(rel)
    }
    Timer { id: lookups; interval: 800; onTriggered: cal.requestLookups() }
    onViewChanged: lookups.restart()
    onAnchorChanged: lookups.restart()
    Connections {
        target: cal.engine
        function onCalendarDaysChanged() { lookups.restart() }
    }

    function openReporter(e) {
        if (e.ticker) cal.open({ symbol: e.ticker, label: e.ticker, name: e.name || e.ticker, star: false })
    }

    // ── toolbar ─────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        Repeater {
            model: [ { key: "day", text: i18n("Day") }, { key: "week", text: i18n("Week") },
                     { key: "month", text: i18n("Month") } ]
            PlasmaComponents3.ToolButton {
                required property var modelData
                text: modelData.text
                checkable: true
                checked: cal.view === modelData.key
                onClicked: cal.setView(modelData.key)
            }
        }
        Item { Layout.fillWidth: true }
        PlasmaComponents3.ToolButton {
            icon.name: "go-previous"
            onClicked: cal.step(-1)
            PlasmaComponents3.ToolTip { text: cal.view === "month" ? i18n("Previous month") : cal.view === "week" ? i18n("Previous week") : i18n("Previous day") }
        }
        PlasmaComponents3.ToolButton {
            text: i18n("Today")
            onClicked: cal.anchor = cal.home()
        }
        PlasmaComponents3.ToolButton {
            icon.name: "go-next"
            onClicked: cal.step(1)
            PlasmaComponents3.ToolTip { text: cal.view === "month" ? i18n("Next month") : cal.view === "week" ? i18n("Next week") : i18n("Next day") }
        }
        PlasmaComponents3.ToolButton {
            icon.name: "view-refresh"
            enabled: !cal.engine.calendarLoading
            onClicked: cal.engine.refreshCalendar()
            PlasmaComponents3.ToolTip { text: i18n("Refresh what is on screen") }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing * 2
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        PlasmaExtras.Heading {
            level: 4
            text: cal.title
        }
        Item { Layout.fillWidth: true }
        Repeater {
            model: [ { key: "all", text: i18n("All"), tip: "" }, { key: "econ", text: i18n("Economic"), tip: "" },
                     { key: "earnings", text: i18n("Earnings"), tip: i18n("Companies chosen under Settings → Data") } ]
            PlasmaComponents3.ToolButton {
                required property var modelData
                text: modelData.text
                font: Kirigami.Theme.smallFont
                checkable: true
                checked: cal.show === modelData.key
                onClicked: cal.show = modelData.key
                PlasmaComponents3.ToolTip { text: parent.modelData.tip }
            }
        }
    }
    Kirigami.Separator { Layout.fillWidth: true }

    Loader {
        Layout.fillWidth: true
        Layout.fillHeight: true
        sourceComponent: cal.view === "month" ? monthView : cal.view === "day" ? dayView : weekView
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        font: Kirigami.Theme.smallFont
        opacity: 0.6
        wrapMode: Text.WordWrap
        text: (cal.engine.calendarLoading ? i18n("Loading from Nasdaq… a new month takes up to a minute.")
              : isNaN(cal.engine.calendarAt.getTime()) ? i18n("Calendar not loaded yet.")
              : i18n("Nasdaq calendar · %1.", Qt.formatTime(cal.engine.calendarAt, "h:mm ap")))
              + " " + i18n("New York time. Dot: red = market-moving, amber = notable, grey = minor.")
    }

    // ── shared pieces ───────────────────────────────────────────────────
    component Dot: Rectangle {
        property real score: 0
        implicitWidth: Kirigami.Units.smallSpacing * 2
        implicitHeight: implicitWidth
        radius: width / 2
        color: cal.importance(score)
    }
    // Why a day is empty: still loading, unreadable, or nothing on it.
    component DayNote: PlasmaComponents3.Label {
        property var events
        property bool hasRows: false
        visible: events === undefined || events === null || !hasRows
        opacity: 0.6
        font: Kirigami.Theme.smallFont
        color: events === null ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        text: events === undefined ? i18n("Loading…") : events === null ? i18n("Feed could not be read") : i18n("Nothing scheduled")
    }
    component NowLine: RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing
        PlasmaComponents3.Label {
            text: i18n("now")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.highlightColor
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 2
            color: Kirigami.Theme.highlightColor
        }
    }

    // One event as a list row (day view).
    component EventRow: PlasmaComponents3.ItemDelegate {
        id: row
        property var event: ({})
        readonly property bool earn: event.kind === "earnings"
        Layout.fillWidth: true
        opacity: cal.past(event) && !cal.hasActual(event) ? 0.55 : 1
        onClicked: if (earn) cal.openReporter(event)
        PlasmaComponents3.ToolTip { textFormat: Text.PlainText; text: cal.tip(row.event) }

        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Dot { score: row.event.score || 0 }
            PlasmaComponents3.Label {
                visible: !row.earn
                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                font.family: Kirigami.Theme.fixedWidthFont.family
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: cal.etTime(row.event.when) || i18n("All day")
                opacity: 0.8
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    // Its own width, shrinking (and eliding) only when the row is short.
                    PlasmaComponents3.Label {
                        Layout.preferredWidth: implicitWidth
                        Layout.minimumWidth: Math.min(implicitWidth, Kirigami.Units.gridUnit * 3)
                        textFormat: Text.PlainText
                        text: row.earn ? row.event.ticker : row.event.label
                        font.bold: true
                        font.underline: row.earn
                        elide: Text.ElideRight
                    }
                    GroupIcons {
                        engine: cal.engine
                        symbol: row.earn ? row.event.ticker : ""
                        headline: row.earn ? "" : row.event.label
                    }
                    Item { Layout.fillWidth: true }
                }
                PlasmaComponents3.Label {
                    visible: row.earn
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: (row.event.name || "") + (row.event.mcap ? " · " + cal.big(row.event.mcap) : "")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }
            ColumnLayout {
                spacing: 0
                PlasmaComponents3.Label {
                    Layout.alignment: Qt.AlignRight
                    font.family: Kirigami.Theme.fixedWidthFont.family
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    textFormat: Text.PlainText
                    text: (row.earn ? i18n("EPS est %1", cal.figure(row.event.expected))
                                    : i18n("Exp %1", cal.figure(row.event.expected)))
                          + " · " + i18n("Prev %1", cal.figure(row.event.previous))
                }
                PlasmaComponents3.Label {
                    visible: cal.hasActual(row.event)
                    Layout.alignment: Qt.AlignRight
                    font.family: Kirigami.Theme.fixedWidthFont.family
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    font.bold: true
                    color: cal.actualColor(row.event)
                    textFormat: Text.PlainText
                    text: cal.actualText(row.event)
                }
            }
            PlasmaComponents3.ToolButton {
                readonly property var link: cal.linkOf(row.event)
                opacity: link ? 1 : 0
                enabled: !!link
                icon.name: "link"
                onClicked: cal.openLink(row.event)
                PlasmaComponents3.ToolTip {
                    textFormat: Text.PlainText
                    text: parent.link ? (row.earn ? i18n("Read the press release on %1", parent.link.source)
                                                  : i18n("Read the release at %1", parent.link.source)) : ""
                }
            }
        }
    }

    // ── day ─────────────────────────────────────────────────────────────
    Component {
        id: dayView
        PlasmaComponents3.ScrollView {
            id: dv
            PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff
            readonly property string day: cal.iso(cal.anchor)
            readonly property var events: cal.raw(day)
            readonly property var econ: cal.econOf(events)
            readonly property var earn: cal.earnOf(events)
            // Index of the first release still to come, for the "now" line;
            // -1 on any day but today.
            readonly property int nowAt: {
                if (day !== cal.todayIso) return -1
                const i = econ.findIndex(e => !cal.past(e))
                return i < 0 ? econ.length : i
            }

            ColumnLayout {
                width: dv.availableWidth
                spacing: 0

                DayNote {
                    Layout.margins: Kirigami.Units.largeSpacing
                    events: dv.events
                    hasRows: dv.econ.length + dv.earn.length > 0
                }

                PlasmaExtras.Heading {
                    visible: dv.econ.length > 0
                    Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    level: 5
                    opacity: 0.7
                    text: i18n("Economic")
                }
                Repeater {
                    model: dv.econ
                    delegate: ColumnLayout {
                        id: er
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 0
                        NowLine { visible: er.index === dv.nowAt }
                        EventRow { event: er.modelData }
                    }
                }
                NowLine { visible: dv.econ.length > 0 && dv.nowAt === dv.econ.length }

                Repeater {
                    model: ["bmo", "amc", ""]
                    delegate: ColumnLayout {
                        id: grp
                        required property string modelData
                        readonly property var rows: dv.earn.filter(e => (e.session || "") === modelData)
                        visible: rows.length > 0
                        Layout.fillWidth: true
                        spacing: 0
                        PlasmaExtras.Heading {
                            Layout.leftMargin: Kirigami.Units.smallSpacing * 2
                            Layout.topMargin: Kirigami.Units.largeSpacing
                            level: 5
                            opacity: 0.7
                            text: i18n("Earnings, %1", cal.sessionText(grp.modelData))
                        }
                        Repeater {
                            model: grp.rows
                            delegate: EventRow { required property var modelData; event: modelData }
                        }
                    }
                }
            }
        }
    }

    // ── week ────────────────────────────────────────────────────────────
    Component {
        id: weekView
        PlasmaComponents3.ScrollView {
            id: wv
            PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff
            // Monday to Friday, plus a weekend day that has something on it.
            readonly property var days: {
                const out = []
                for (let i = 0; i < 7; i++) {
                    const d = cal.addDays(cal.span.start, i)
                    if (i < 5 || cal.countOn(d)) out.push(d)
                }
                return out
            }
            readonly property real colWidth: (availableWidth - Kirigami.Units.smallSpacing * (days.length + 1)) / days.length

            RowLayout {
                x: Kirigami.Units.smallSpacing
                width: wv.availableWidth - Kirigami.Units.smallSpacing * 2
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: wv.days
                    delegate: ColumnLayout {
                        id: col
                        required property var modelData
                        readonly property string day: cal.iso(modelData)
                        readonly property bool today: day === cal.todayIso
                        readonly property var events: cal.raw(day)
                        readonly property var econ: cal.econOf(events)
                        readonly property var earn: cal.earnOf(events)
                        readonly property int earnShown: 8
                        Layout.preferredWidth: wv.colWidth
                        Layout.maximumWidth: wv.colWidth
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing
                        opacity: day < cal.todayIso ? 0.7 : 1

                        // The day's heading: today stands out; click opens the day.
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: head.implicitHeight + Kirigami.Units.smallSpacing * 2
                            radius: Kirigami.Units.cornerRadius
                            color: col.today ? cal.tint(Kirigami.Theme.highlightColor, 0.4)
                                 : headHover.hovered ? cal.tint(Kirigami.Theme.highlightColor, 0.15)
                                 : cal.tint(Kirigami.Theme.textColor, 0.07)
                            PlasmaComponents3.Label {
                                id: head
                                anchors.centerIn: parent
                                text: Qt.formatDate(col.modelData, "ddd d")
                                font.bold: true
                            }
                            HoverHandler { id: headHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: cal.openDay(col.modelData) }
                        }
                        DayNote {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            events: col.events
                            hasRows: col.econ.length + col.earn.length > 0
                        }
                        // Release cards, by time.
                        Repeater {
                            model: col.econ
                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: cardText.implicitHeight + Kirigami.Units.smallSpacing * 2
                                radius: Kirigami.Units.cornerRadius
                                color: cal.tint(Kirigami.Theme.textColor, cardHover.hovered ? 0.12 : 0.05)
                                opacity: cal.past(modelData) && !cal.hasActual(modelData) ? 0.6 : 1
                                Rectangle {
                                    width: 3
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    radius: 1.5
                                    color: cal.importance(card.modelData.score)
                                }
                                ColumnLayout {
                                    id: cardText
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                              leftMargin: Kirigami.Units.smallSpacing + 3; rightMargin: Kirigami.Units.smallSpacing }
                                    spacing: 0
                                    PlasmaComponents3.Label {
                                        Layout.fillWidth: true
                                        text: cal.etTime(card.modelData.when) || i18n("All day")
                                        font.family: Kirigami.Theme.fixedWidthFont.family
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        opacity: 0.7
                                    }
                                    PlasmaComponents3.Label {
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: card.modelData.label
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        font.bold: card.modelData.score >= 70
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                    PlasmaComponents3.Label {
                                        visible: cal.hasActual(card.modelData)
                                        Layout.fillWidth: true
                                        textFormat: Text.PlainText
                                        text: cal.figure(card.modelData.actual) + cal.arrow(card.modelData)
                                        font.family: Kirigami.Theme.fixedWidthFont.family
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        elide: Text.ElideRight
                                    }
                                }
                                HoverHandler { id: cardHover; cursorShape: cal.linkOf(card.modelData) ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                TapHandler { onTapped: cal.openLink(card.modelData) }
                                PlasmaComponents3.ToolTip {
                                    visible: cardHover.hovered
                                    textFormat: Text.PlainText
                                    text: cal.tip(card.modelData) + (cal.linkOf(card.modelData) ? "\n" + i18n("Click to read it.") : "")
                                }
                            }
                        }
                        // Reporters, best first; the rest behind "+N", which opens the day.
                        PlasmaComponents3.Label {
                            visible: col.earn.length > 0
                            Layout.fillWidth: true
                            Layout.topMargin: Kirigami.Units.smallSpacing
                            text: i18n("Earnings")
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                        }
                        Flow {
                            visible: col.earn.length > 0
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            Repeater {
                                model: col.earn.slice(0, col.earnShown)
                                delegate: Row {
                                    id: tk
                                    required property var modelData
                                    spacing: 1
                                    GroupIcons {
                                        anchors.verticalCenter: parent.verticalCenter
                                        engine: cal.engine
                                        symbol: tk.modelData.ticker
                                        size: Kirigami.Units.iconSizes.small * 0.8
                                    }
                                    PlasmaComponents3.Label {
                                        textFormat: Text.PlainText
                                        text: tk.modelData.ticker
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        font.bold: true
                                        font.underline: tkHover.hovered
                                        color: cal.actualColor(tk.modelData)
                                        HoverHandler { id: tkHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: cal.openReporter(tk.modelData) }
                                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: cal.openLink(tk.modelData) }
                                        PlasmaComponents3.ToolTip {
                                            visible: tkHover.hovered
                                            textFormat: Text.PlainText
                                            text: cal.tip(tk.modelData) + "\n" + (cal.linkOf(tk.modelData)
                                                  ? i18n("Click for the chart; right-click for the press release.") : i18n("Click for the chart."))
                                        }
                                    }
                                }
                            }
                            PlasmaComponents3.Label {
                                visible: col.earn.length > col.earnShown
                                text: i18n("+%1", col.earn.length - col.earnShown)
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                opacity: 0.7
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: cal.openDay(col.modelData) }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── month ───────────────────────────────────────────────────────────
    Component {
        id: monthView
        ColumnLayout {
            id: mv
            spacing: 0
            readonly property int weeks: Math.round(cal.span.days / 7)
            readonly property int month: cal.anchor.getMonth()

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                Repeater {
                    model: 5
                    PlasmaComponents3.Label {
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName(index + 1, Locale.ShortFormat)
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                    }
                }
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                Layout.rightMargin: Kirigami.Units.smallSpacing
                columns: 5
                rowSpacing: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.smallSpacing
                Repeater {
                    // Weekdays only; a weekend with something on it shows on its Friday.
                    model: mv.weeks * 5
                    delegate: Rectangle {
                        id: cell
                        required property int index
                        readonly property date cellDate: cal.addDays(cal.span.start, Math.floor(index / 5) * 7 + index % 5)
                        readonly property string day: cal.iso(cellDate)
                        readonly property bool today: day === cal.todayIso
                        readonly property bool inMonth: cellDate.getMonth() === mv.month
                        readonly property var events: cal.raw(day)
                        readonly property var econ: cal.econOf(events)
                        readonly property var earn: cal.earnOf(events)
                        readonly property var ranked: econ.slice().sort((a, b) => b.score - a.score)
                        // The day's reporters whose sector or theme is hot or
                        // building, one glyph per group (those looked up so far).
                        readonly property var hotGroups: {
                            const seen = {}, out = []
                            for (const e of earn) {
                                const g = cal.engine.groupsFor(e.ticker, "")
                                // Theme when it has one, else sector -- the screener's rule.
                                for (const p of [g.theme ? [g.theme, g.themeHeat] : [g.sector, g.sectorHeat]]) {
                                    if (!p[0] || !p[1] || (p[1].status !== "hot" && p[1].status !== "building") || seen[p[0].id]) continue
                                    seen[p[0].id] = true
                                    out.push({ group: p[0], status: p[1].status, ticker: e.ticker })
                                }
                            }
                            return out
                        }
                        readonly property int weekendCount: index % 5 !== 4 ? 0
                            : cal.countOn(cal.addDays(cellDate, 1)) + cal.countOn(cal.addDays(cellDate, 2))
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 1
                        Layout.minimumHeight: Kirigami.Units.gridUnit * 3.2
                        radius: Kirigami.Units.cornerRadius
                        color: cellHover.hovered ? cal.tint(Kirigami.Theme.highlightColor, 0.2)
                             : cal.tint(Kirigami.Theme.textColor, inMonth ? 0.06 : 0.02)
                        border.width: today ? 2 : 0
                        border.color: Kirigami.Theme.highlightColor
                        opacity: !inMonth ? 0.4 : day < cal.todayIso ? 0.7 : 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                PlasmaComponents3.Label {
                                    text: cell.cellDate.getDate()
                                    font.bold: cell.today
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    color: cell.today ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
                                }
                                Item { Layout.fillWidth: true }
                                PlasmaComponents3.Label {
                                    visible: cell.events === undefined || cell.events === null
                                    text: cell.events === null ? "!" : "…"
                                    color: cell.events === null ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    opacity: 0.7
                                }
                                Repeater {
                                    model: cell.ranked.slice(0, 4)
                                    Dot { required property var modelData; score: modelData.score }
                                }
                            }
                            PlasmaComponents3.Label {
                                visible: cell.ranked.length > 0
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: cell.ranked.length ? cell.ranked[0].label : ""
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                font.bold: cell.ranked.length > 0 && cell.ranked[0].score >= 70
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                visible: cell.earn.length > 0
                                Layout.fillWidth: true
                                spacing: 1
                                // "12 earnings", or "12 E" when the cell is too
                                // narrow for it (the day's tooltip lists them).
                                PlasmaComponents3.Label {
                                    id: earnCount
                                    Layout.fillWidth: true
                                    readonly property string full: i18np("%1 earning", "%1 earnings", cell.earn.length)
                                    TextMetrics { id: earnFull; font: earnCount.font; text: earnCount.full }
                                    text: earnFull.advanceWidth <= width ? full
                                        : i18nc("earnings count, short form for a narrow calendar cell", "%1 E", cell.earn.length)
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    opacity: 0.65
                                    elide: Text.ElideRight
                                }
                                Repeater {
                                    model: cell.hotGroups.slice(0, 3)
                                    ThemeGlyph {
                                        required property var modelData
                                        theme: modelData.group
                                        status: modelData.status
                                        ramp: Plasmoid.configuration.themeRamp
                                        size: Kirigami.Units.iconSizes.small * 0.8
                                        icons: { try { return JSON.parse(Plasmoid.configuration.themeIcons || "{}") } catch (e) { return ({}) } }
                                    }
                                }
                            }
                            PlasmaComponents3.Label {
                                visible: cell.weekendCount > 0
                                Layout.fillWidth: true
                                text: i18n("+ weekend")
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                opacity: 0.65
                            }
                            Item { Layout.fillHeight: true }
                        }
                        HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: cal.openDay(cell.cellDate) }
                        PlasmaComponents3.ToolTip {
                            visible: cellHover.hovered && (cell.econ.length + cell.earn.length) > 0
                            textFormat: Text.PlainText
                            text: cell.econ.map(e => (cal.etTime(e.when) || i18n("All day")) + "  " + e.label
                                                     + (cal.hasActual(e) ? "  → " + e.actual + cal.arrow(e) : "")).join("\n")
                                  + (cell.earn.length ? (cell.econ.length ? "\n" : "") + i18n("Earnings: %1",
                                     cell.earn.slice(0, 12).map(e => e.ticker).join(" ") + (cell.earn.length > 12 ? " …" : "")) : "")
                                  + cell.hotGroups.map(h => "\n" + i18n("%1 %2 · %3 (beta)", h.group.name, h.status, h.ticker)).join("")
                        }
                    }
                }
            }
            Item { implicitHeight: Kirigami.Units.smallSpacing }
        }
    }
}
