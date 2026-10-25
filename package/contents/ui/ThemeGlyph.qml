// One theme's glyph, as the screener, the detail card and Settings → Themes
// draw it: the built-in glyph (solid when live, outline when not, crossed
// out when burnt), or the icon chosen for that theme in Settings → Themes --
// tinted by the heat, or in its own colours inside a heat-coloured ring, with
// the same cross-out over it when burnt. Only the one variant in use is
// created, so a table of these costs one item per cell.

import QtQuick
import org.kde.kirigami as Kirigami
import "themes.js" as Themes

Item {
    id: glyph

    property var theme: null              // {id, glyph, unnamed}, or null for none
    property string status: "quiet"       // hot | building | burnt | quiet
    property string ramp: "heat"
    property var icons: ({})              // the themeIcons setting, parsed
    property real size: Kirigami.Units.iconSizes.small

    readonly property var custom: theme ? Themes.custom(theme, icons) : null
    // A theme or sector of yours may carry its own colours (its `ramp`).
    readonly property string rampKey: (theme && theme.ramp) || ramp
    readonly property color col: Themes.colour(status, rampKey)
    // A custom icon cannot be drawn as an outline, so quiet fades it instead.
    readonly property real fade: status === "quiet" ? 0.7 : 1

    implicitWidth: size
    implicitHeight: size
    visible: !!theme

    Loader {
        anchors.fill: parent
        sourceComponent: !glyph.theme ? null
                       : !glyph.custom ? builtIn
                       : glyph.custom.keep ? ringed : tinted
    }
    Component {
        id: builtIn
        Image {
            sourceSize.width: 32
            sourceSize.height: 32
            smooth: true
            source: Themes.icon(Themes.glyphName(glyph.theme, glyph.icons), Themes.colour(glyph.status, glyph.rampKey), Themes.filled(glyph.status),
                                Themes.crossed(glyph.status), Themes.edge(glyph.status, glyph.rampKey))
        }
    }
    Component {
        id: tinted
        Kirigami.Icon {
            source: Themes.iconSource(glyph.custom.icon)
            isMask: true
            color: glyph.col
            opacity: glyph.fade
        }
    }
    Component {
        id: ringed
        Item {
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: Math.max(1.5, width / 10)
                border.color: glyph.col
            }
            Kirigami.Icon {
                anchors.centerIn: parent
                width: parent.width * 0.68
                height: width
                source: Themes.iconSource(glyph.custom.icon)
                opacity: glyph.fade
            }
        }
    }
    // Burnt, over a custom icon: the built-in glyphs carry their own.
    Image {
        anchors.fill: parent
        visible: !!glyph.custom && Themes.crossed(glyph.status)
        sourceSize.width: 32
        sourceSize.height: 32
        source: visible ? Themes.crossIcon(Themes.colour(glyph.status, glyph.rampKey)) : ""
    }
}
