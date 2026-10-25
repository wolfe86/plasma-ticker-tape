import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("Symbols")
        icon: "view-list-details"
        source: "configSymbols.qml"
    }
    ConfigCategory {
        name: i18n("Screeners")
        icon: "view-filter"
        source: "configScreener.qml"
    }
    ConfigCategory {
        name: i18n("Scorecards")
        icon: "view-task"
        source: "configScorecards.qml"
    }
    ConfigCategory {
        name: i18n("Themes")
        icon: "color-picker"
        source: "configThemes.qml"
    }
    ConfigCategory {
        name: i18n("Tape")
        icon: "preferences-desktop-display"
        source: "configTape.qml"
    }
    ConfigCategory {
        name: i18n("Performance")
        icon: "speedometer"
        source: "configPerformance.qml"
    }
    ConfigCategory {
        name: i18n("Data")
        icon: "folder-network"
        source: "configData.qml"
    }
}
