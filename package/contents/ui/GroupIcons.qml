// One glyph for a stock, heat-coloured, as the Calendar and News tabs show
// it beside a ticker or a headline: its theme when it matches one, else its
// sector -- the same rule as the screener's Theme column (the engine's
// groupsFor(), drawn with ThemeGlyph). Hover for the names and the heat. Nothing shows while the
// Themes / Sectors switches are off or the stock has not been looked up.
//
//   symbol   -- the stock; "" for a headline that names none
//   headline -- read for the theme instead of the stock's newest headline
//   hotOnly  -- show a glyph only while its group is hot or building

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "themes.js" as Themes

RowLayout {
    id: gi

    required property var engine
    property string symbol: ""
    property string headline: ""
    property bool hotOnly: false
    property real size: Kirigami.Units.iconSizes.small

    readonly property var g: engine.groupsFor(symbol, headline)
    readonly property string sectorStatus: g.sectorHeat ? g.sectorHeat.status : "quiet"
    readonly property string themeStatus: g.themeHeat ? g.themeHeat.status : "quiet"
    function live(st) { return st === "hot" || st === "building" }
    readonly property bool showTheme: !!g.theme && (!hotOnly || live(themeStatus))
    readonly property bool showSector: !g.theme && !!g.sector && (!hotOnly || live(sectorStatus))
    readonly property var icons: { try { return JSON.parse(Plasmoid.configuration.themeIcons || "{}") } catch (e) { return ({}) } }

    spacing: 1
    visible: showSector || showTheme

    ThemeGlyph {
        visible: gi.showSector
        theme: gi.showSector ? gi.g.sector : null
        status: gi.sectorStatus
        ramp: Plasmoid.configuration.themeRamp
        icons: gi.icons
        size: gi.size
    }
    ThemeGlyph {
        visible: gi.showTheme
        theme: gi.showTheme ? gi.g.theme : null
        status: gi.themeStatus
        ramp: Plasmoid.configuration.themeRamp
        icons: gi.icons
        size: gi.size
    }
    HoverHandler { id: hover }
    // The names, each one's heat and why, then what the colours mean.
    function line(label, grp, heat) {
        const st = heat ? heat.status : "quiet"
        return i18n("%1: %2 · %3", label, grp.name, st.toUpperCase()) + (heat && heat.why ? " (" + heat.why + ")" : "")
    }
    PlasmaComponents3.ToolTip {
        visible: hover.hovered
        text: [gi.showSector ? gi.line(i18n("Sector"), gi.g.sector, gi.g.sectorHeat) : "",
               gi.showTheme ? gi.line(i18n("Theme"), gi.g.theme, gi.g.themeHeat) : ""]
              .filter(t => t).join("\n") + " " + i18n("(beta)")
              + "\n\n" + Themes.legend(gi.engine.themeTune, Plasmoid.configuration.themeRamp)
    }
}
