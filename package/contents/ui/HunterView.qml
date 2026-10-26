// The Theme Hunter screen (beta): themes and sectors ranked by heat, and the
// runners no theme claims yet. The way it is meant to be used (Matt,
// 2026-10-24): a sector keeps heating up, the runners under it share a
// headline, and that is the theme to define in Settings → Themes.
//
// Reads ScreenerEngine.hunterBoard(); no filters or scorecard of its own.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "themes.js" as Themes
import "screens.js" as Screens

PlasmaComponents3.ScrollView {
    id: hunter

    // Rows wrap to the width, so no sideways scrolling; leaving the bar
    // automatic made it flicker on and off (a binding loop in ScrollView).
    PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

    required property var engine
    required property string market          // "stocks" | "crypto"
    signal open(var entry)

    // Rebuilt whenever the tally moves: the binding tracks what
    // hunterBoard() reads (themeLive, themeHist, themeLastDay...).
    // Only while on screen: hidden (any other screen or tab), the board and
    // its rows cost plasmashell ~165 MB and ~2% CPU, rebuilt on every pass
    // for nobody (2026-10-24).
    readonly property var board: visible ? engine.hunterBoard(market) : ({ themes: [], sectors: [], unclaimed: [] })
    readonly property var icons: {
        try { return JSON.parse(Plasmoid.configuration.themeIcons || "{}") } catch (e) { return ({}) }
    }
    // The screens whose stocks this board counts.
    readonly property var sources: engine.screens.filter(s => (s.market === "crypto" ? "crypto" : "stocks") === market
                                                             && s.type !== "hunter" && Screens.feedsThemes(s)).map(s => s.name)
    property var expanded: ({})
    function toggle(id) { const e = Object.assign({}, expanded); e[id] = !e[id]; expanded = e }

    // ▁▂▃▅▇ from member counts, oldest first.
    function spark(ns) {
        if (!ns || !ns.length) return ""
        const max = Math.max.apply(null, ns.concat([1])), bars = "▁▂▃▄▅▆▇█"
        return ns.map(n => bars[Math.min(7, Math.round(n / max * 7))]).join("")
    }
    function pct(v) { return isFinite(v) ? (v >= 0 ? "+" : "") + Math.round(v) + "%" : "—" }

    ColumnLayout {
        width: hunter.availableWidth
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.margins: Kirigami.Units.smallSpacing
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Beta. Ranked by heat, hottest first. A sector heating up with runners that share a headline is a theme to define in Settings → Themes.")
                  + (hunter.engine.currentPhase === "closed" && hunter.market !== "crypto" ? " " + i18n("Market closed: showing each one's last session.") : "")
                  + "\n" + (hunter.sources.length ? i18n("Built from: %1 (Settings → Screeners).", hunter.sources.join(", "))
                                                   : i18n("No screen builds themes: tick one in Settings → Screeners."))
        }

        // ── one section: a heading and its ranked rows ──
        Component {
            id: groupRow
            ColumnLayout {
                id: grow
                required property var modelData
                readonly property var g: modelData
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents3.ItemDelegate {
                    id: gdel
                    Layout.fillWidth: true
                    onClicked: hunter.toggle(grow.g.id)
                    // The numbers behind the colour, and what the colours mean.
                    PlasmaComponents3.ToolTip {
                        visible: gdel.hovered
                        text: Themes.explain(grow.g.name, grow.g.heat, hunter.engine.themeTune,
                                             grow.g.ramp || Plasmoid.configuration.themeRamp)
                    }
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing
                        ThemeGlyph {
                            theme: grow.g
                            status: grow.g.status
                            ramp: Plasmoid.configuration.themeRamp
                            icons: hunter.icons
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            RowLayout {
                                PlasmaComponents3.Label { text: grow.g.name; font.bold: true; textFormat: Text.PlainText }
                                PlasmaComponents3.Label {
                                    text: grow.g.status === "burnt" ? i18n("BURNT (dead)") : grow.g.status.toUpperCase()
                                    color: grow.g.status === "quiet" ? Kirigami.Theme.disabledTextColor
                                         : Themes.colour(grow.g.status, grow.g.ramp || Plasmoid.configuration.themeRamp)
                                    font: Kirigami.Theme.smallFont
                                }
                                PlasmaComponents3.Label {
                                    visible: grow.g.day !== ""
                                    text: grow.g.day ? Qt.formatDate(new Date(grow.g.day + "T12:00:00"), "ddd d MMM") : ""
                                    font: Kirigami.Theme.smallFont
                                    opacity: 0.6
                                }
                                Item { Layout.fillWidth: true }
                                // One session is a single solid block, which
                                // reads as a broken element: shown from two.
                                PlasmaComponents3.Label {
                                    visible: (grow.g.trend || []).length >= 2
                                    text: hunter.spark(grow.g.trend)
                                    font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace")
                                    opacity: 0.7
                                    HoverHandler { id: trendHover }
                                    PlasmaComponents3.ToolTip {
                                        visible: trendHover.hovered
                                        text: i18n("Members per session, oldest first, empty sessions included")
                                    }
                                }
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                textFormat: Text.PlainText
                                font: Kirigami.Theme.smallFont
                                opacity: 0.8
                                text: i18n("%1 members · %2 ran · median %3 · best %4 %5", grow.g.n, grow.g.ran,
                                           hunter.pct(grow.g.med), hunter.pct(grow.g.top), grow.g.leader)
                                      + (grow.g.streak ? " · " + i18n("day %1", grow.g.streak) : "")
                                      + (grow.g.heat && grow.g.heat.why && grow.g.status !== "hot" ? " · " + grow.g.heat.why : "")
                                      + (grow.g.breakdown ? "\n" + grow.g.breakdown : "")
                                      + (grow.g.cooling.length ? "\n" + i18n("Cooling signs (for information): %1", grow.g.cooling.join(", ")) : "")
                            }
                        }
                    }
                }
                // Its members, best first; a ticker opens its chart.
                Flow {
                    visible: !!hunter.expanded[grow.g.id]
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.gridUnit * 2
                    spacing: 2
                    Repeater {
                        model: hunter.expanded[grow.g.id] ? grow.g.members : []
                        PlasmaComponents3.ToolButton {
                            required property var modelData
                            // A button's label renders markup; a symbol is never meant to.
                            text: String(modelData.symbol).replace(/[<>&]/g, "") + " " + hunter.pct(modelData.peak)
                            onClicked: hunter.open({ symbol: modelData.symbol, label: modelData.symbol, name: modelData.symbol, star: false })
                        }
                    }
                }
            }
        }

        Kirigami.Heading {
            level: 4
            Layout.margins: Kirigami.Units.smallSpacing
            text: i18n("Themes, hottest first")
        }
        PlasmaComponents3.Label {
            visible: hunter.board.themes.length === 0
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            wrapMode: Text.WordWrap
            opacity: 0.6
            text: hunter.market === "crypto"
                  ? i18n("No crypto themes yet: define one in Settings → Themes. Watch the categories below meanwhile.")
                  : i18n("No theme has members yet. Watch the sectors and the unclaimed runners below.")
        }
        Repeater { model: hunter.board.themes; delegate: groupRow }

        Kirigami.Heading {
            level: 4
            Layout.margins: Kirigami.Units.smallSpacing
            text: hunter.market === "crypto" ? i18n("Categories, hottest first") : i18n("Sectors, hottest first")
        }
        PlasmaComponents3.Label {
            visible: hunter.board.sectors.length === 0
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            wrapMode: Text.WordWrap
            opacity: 0.6
            text: i18n("Nothing yet: sectors fill as stocks reach your screens while the market trades.")
        }
        Repeater { model: hunter.board.sectors; delegate: groupRow }

        Kirigami.Heading {
            level: 4
            Layout.margins: Kirigami.Units.smallSpacing
            text: i18n("Unclaimed runners")
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.6
            text: hunter.board.unclaimed.length
                  ? i18n("Ran %1 or more and no theme claims them. Shared words in these headlines are a theme waiting for a name.", "+" + hunter.engine.themeTune.ranPct + "%")
                  : i18n("None: every runner is on a theme, or nothing has run yet.")
        }
        Repeater {
            model: hunter.board.unclaimed
            ColumnLayout {
                id: urow
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.smallSpacing
                spacing: 0
                RowLayout {
                    ThemeGlyph {
                        theme: urow.modelData
                        status: urow.modelData.status
                        ramp: Plasmoid.configuration.themeRamp
                        icons: hunter.icons
                    }
                    PlasmaComponents3.Label { text: urow.modelData.name; font.bold: true; textFormat: Text.PlainText }
                }
                Repeater {
                    model: urow.modelData.rows
                    PlasmaComponents3.ItemDelegate {
                        id: urun
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.gridUnit * 1.5
                        onClicked: hunter.open({ symbol: modelData.symbol, label: modelData.symbol, name: modelData.symbol, star: false })
                        contentItem: RowLayout {
                            PlasmaComponents3.Label {
                                text: urun.modelData.symbol
                                textFormat: Text.PlainText
                                font.bold: true
                                font.family: (Kirigami.Theme.fixedWidthFont ? Kirigami.Theme.fixedWidthFont.family : "monospace")
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                            }
                            PlasmaComponents3.Label {
                                text: hunter.pct(urun.modelData.peak)
                                color: Kirigami.Theme.positiveTextColor
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: urun.modelData.headline || i18n("no headline")
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                font: Kirigami.Theme.smallFont
                                opacity: urun.modelData.headline ? 0.9 : 0.5
                            }
                        }
                    }
                }
            }
        }
    }
}
