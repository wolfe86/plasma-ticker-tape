// The Calendar tab: the week's economic releases and earnings, by day.
//
// Data from the engine's `calendar` (the scanner's
// calendar_events.py, through the bridge). Economic events show their time
// in New York time, the consensus, the previous figure and -- once it has
// printed -- the actual. Earnings show before the open or after the close,
// the EPS estimate, last year's figure and, once reported, the actual and
// the surprise. A dot marks how much an event matters, by the scanner's own
// ranking. Clicking a reporter opens its detail view.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: cal

    required property var engine
    signal open(var entry)

    property string show: "all"           // all | econ | earnings
    spacing: 0

    // Days from today, weekends dropped unless something is on them.
    readonly property var days: (engine.calendar || []).filter(d => {
        const wd = new Date(d.date + "T12:00:00").getDay()
        return (wd !== 0 && wd !== 6) || (d.events && d.events.length)
    })

    function dayTitle(iso) {
        const d = new Date(iso + "T12:00:00")
        const today = new Date(); today.setHours(12, 0, 0, 0)
        const diff = Math.round((d - today) / 86400000)
        const name = Qt.formatDate(d, "ddd, MMM d")
        return diff === 0 ? i18n("Today · %1", name) : diff === 1 ? i18n("Tomorrow · %1", name) : name
    }
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
    // Economic events first, by time; then reporters, best first.
    function shown(events) {
        const ev = (events || []).filter(e => show === "all" || e.kind === show)
        const econ = ev.filter(e => e.kind === "econ").sort((a, b) => String(a.when).localeCompare(String(b.when)))
        return econ.concat(ev.filter(e => e.kind === "earnings"))
    }

    // ── filter, status, refresh ─────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        Repeater {
            model: [ { key: "all", text: i18n("All") }, { key: "econ", text: i18n("Economic") },
                     { key: "earnings", text: i18n("Earnings") } ]
            PlasmaComponents3.ToolButton {
                required property var modelData
                text: modelData.text
                checkable: true
                checked: cal.show === modelData.key
                onClicked: cal.show = modelData.key
            }
        }
        Item { Layout.fillWidth: true }
        PlasmaComponents3.Label {
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: cal.engine.calendarLoading ? i18n("Updating…")
                : isNaN(cal.engine.calendarAt.getTime()) ? ""
                : i18n("Nasdaq calendar · %1", Qt.formatTime(cal.engine.calendarAt, "h:mm ap"))
        }
        PlasmaComponents3.ToolButton {
            icon.name: "view-refresh"
            enabled: !cal.engine.calendarLoading
            onClicked: cal.engine.refreshCalendar()
            PlasmaComponents3.ToolTip { text: i18n("Refresh the calendar (takes about half a minute)") }
        }
    }
    Kirigami.Separator { Layout.fillWidth: true }

    PlasmaComponents3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

        ListView {
            id: list
            model: cal.days
            clip: true
            spacing: Kirigami.Units.smallSpacing

            delegate: ColumnLayout {
                id: day
                required property var modelData
                width: ListView.view.width
                spacing: 0
                readonly property var rows: cal.shown(modelData.events)

                PlasmaExtras.Heading {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    level: 4
                    text: cal.dayTitle(day.modelData.date)
                }
                PlasmaComponents3.Label {
                    visible: day.modelData.events === null || day.rows.length === 0
                    Layout.leftMargin: Kirigami.Units.largeSpacing
                    opacity: 0.6
                    text: day.modelData.events === null ? i18n("Calendar feed could not be read")
                                                        : i18n("Nothing scheduled")
                }

                Repeater {
                    model: day.rows
                    delegate: PlasmaComponents3.ItemDelegate {
                        id: ev
                        required property var modelData
                        readonly property bool earn: modelData.kind === "earnings"
                        Layout.fillWidth: true
                        enabled: true
                        onClicked: if (earn && modelData.ticker)
                            cal.open({ symbol: modelData.ticker, label: modelData.ticker,
                                       name: modelData.name || modelData.ticker, star: false })

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.largeSpacing

                            // How much it matters.
                            Rectangle {
                                Layout.preferredWidth: Kirigami.Units.smallSpacing * 2
                                Layout.preferredHeight: width
                                radius: width / 2
                                color: cal.importance(ev.modelData.score)
                            }
                            // When: a time for a release; before the open or after the close for a report.
                            PlasmaComponents3.Label {
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5
                                font.family: Kirigami.Theme.fixedWidthFont.family
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                text: ev.earn ? ({ bmo: i18n("Pre-mkt"), amc: i18n("After close") })[ev.modelData.session] || i18n("Time n/a")
                                              : cal.etTime(ev.modelData.when) || i18n("All day")
                                opacity: 0.8
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    spacing: Kirigami.Units.smallSpacing
                                    PlasmaComponents3.Label {
                                        text: ev.earn ? ev.modelData.ticker : ev.modelData.label
                                        font.bold: true
                                        font.underline: ev.earn
                                    }
                                    Kirigami.Icon {
                                        visible: !!ev.modelData.on_watchlist
                                        source: "starred-symbolic"
                                        color: Kirigami.Theme.neutralTextColor
                                        isMask: true
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    }
                                }
                                PlasmaComponents3.Label {
                                    visible: ev.earn
                                    Layout.fillWidth: true
                                    text: (ev.modelData.name || "") + (ev.modelData.mcap ? " · " + cal.big(ev.modelData.mcap) : "")
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                }
                            }
                            // The numbers: expected, previous, actual.
                            ColumnLayout {
                                spacing: 0
                                PlasmaComponents3.Label {
                                    Layout.alignment: Qt.AlignRight
                                    font.family: Kirigami.Theme.fixedWidthFont.family
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    text: (ev.earn ? i18n("EPS est %1", cal.figure(ev.modelData.expected))
                                                   : i18n("Exp %1", cal.figure(ev.modelData.expected)))
                                          + " · " + i18n("Prev %1", cal.figure(ev.modelData.previous))
                                }
                                PlasmaComponents3.Label {
                                    visible: ev.modelData.actual !== null && ev.modelData.actual !== undefined && ev.modelData.actual !== ""
                                    Layout.alignment: Qt.AlignRight
                                    font.family: Kirigami.Theme.fixedWidthFont.family
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    font.bold: true
                                    text: i18n("Actual %1", cal.figure(ev.modelData.actual))
                                          + (ev.modelData.surprise !== null && ev.modelData.surprise !== undefined
                                             ? " · " + i18n("surprise %1", ev.modelData.surprise) : "")
                                }
                            }
                        }
                    }
                }
            }

            PlasmaComponents3.Label {
                anchors.centerIn: parent
                visible: list.count === 0
                opacity: 0.7
                text: cal.engine.calendarLoading ? i18n("Loading the calendar… (about half a minute)")
                                                 : i18n("Calendar not loaded yet")
            }
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        font: Kirigami.Theme.smallFont
        opacity: 0.6
        wrapMode: Text.WordWrap
        text: i18n("Times are New York time. Dot: red = market-moving, amber = notable, grey = minor. Click a reporter for its chart and figures.")
    }
}
