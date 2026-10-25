// Settings → Tape: how the strip moves and looks.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_scrollSpeed: speed.value
    property alias cfg_tapeWidth: stripWidth.value
    property alias cfg_fearLine: fear.value
    property alias cfg_pollSeconds: poll.value
    property string cfg_tapeThemeStatus: "hot"
    property alias cfg_tapeThemeMax: themeMax.value
    property string cfg_tapeThemeMark: "name"
    property alias cfg_tapeThemeDrop: themeDrop.value
    property alias cfg_tapeThemePreview: themePreview.checked
    property alias cfg_tapeAbove200: above200.checked
    property alias cfg_ema200ShortHistory: shortHist.checked

    // A whole number typed into a box ("45 s" -> 45); the old value when
    // there is none, so stray typing changes nothing.
    function typedInt(text, old) {
        const m = String(text || "").match(/-?\d+/)
        return m ? parseInt(m[0]) : old
    }

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: speed
            Kirigami.FormData.label: i18n("Scroll speed:")
            from: 5
            to: 150
            stepSize: 5
            editable: true
            validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
            textFromValue: (v, locale) => i18n("%1 px/s", v)
            valueFromText: (text, locale) => page.typedInt(text, speed.value)
            QQC2.ToolTip.text: i18n("How fast the tape moves, in pixels per second")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.SpinBox {
            id: stripWidth
            Kirigami.FormData.label: i18n("Strip width:")
            from: 4
            to: 60
            editable: true
            validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
            textFromValue: (v, locale) => i18n("%1 grid units", v)
            valueFromText: (text, locale) => page.typedInt(text, stripWidth.value)
            QQC2.ToolTip.text: i18n("Width on the panel. One grid unit is about one line of text high (~18 px).")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.SpinBox {
            id: poll
            Kirigami.FormData.label: i18n("Watchlist prices refresh every:")
            from: 15
            to: 900
            stepSize: 15
            editable: true
            validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
            textFromValue: (v, locale) => i18n("%1 s", v)
            valueFromText: (text, locale) => page.typedInt(text, poll.value)
            QQC2.ToolTip.text: i18n("How often the tape, the watchlist and an open detail card re-quote. The screener's timing is under Settings → Performance.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: fear
            Kirigami.FormData.label: i18n("VIX fear line:")
            from: 5
            to: 90
            editable: true
            validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
            valueFromText: (text, locale) => page.typedInt(text, fear.value)
            QQC2.ToolTip.text: i18n("VIX (the market's fear gauge) shows red at or above this level, green below it.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("VIX shows red at or above this level, green below it. Applies to ^VIX only; other symbols are green up, red down.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Themes on the tape (beta)") }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Show tickers of themes:")
            implicitContentWidthPolicy: QQC2.ComboBox.WidestText
            model: [i18n("Hot themes only"), i18n("Hot and building themes")]
            currentIndex: cfg_tapeThemeStatus === "building" ? 1 : 0
            onActivated: index => cfg_tapeThemeStatus = index ? "building" : "hot"
            QQC2.ToolTip.text: i18n("Building: more of its stocks moving than usual. Hot: enough of them have run (set under Settings → Themes).")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.SpinBox {
            id: themeMax
            Kirigami.FormData.label: i18n("At most:")
            from: 1
            to: 30
            editable: true
            validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
            textFromValue: (v, locale) => i18n("%1 tickers", v)
            valueFromText: (text, locale) => page.typedInt(text, themeMax.value)
            QQC2.ToolTip.text: i18n("Most tickers the Themes entry shows at once")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        RowLayout {
            Kirigami.FormData.label: i18n("A ticker leaves when:")
            QQC2.SpinBox {
                id: themeDrop
                from: 5
                to: 80
                stepSize: 5
                editable: true
                validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
                textFromValue: (v, locale) => i18n("%1%", v)
                valueFromText: (text, locale) => page.typedInt(text, themeDrop.value)
                QQC2.ToolTip.text: i18n("A theme ticker leaves the tape once it is this far below the highest price it reached today.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Label { text: i18n("below its session high") }
        }
        QQC2.CheckBox {
            id: above200
            Kirigami.FormData.label: i18n("200-day EMA:")
            text: i18n("Only tickers above their 200-day EMA")
            QQC2.ToolTip.text: i18n("Only tickers above their 200-day exponential moving average (EMA), a long-term trend line. Tickers whose EMA isn't fetched yet wait.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.CheckBox {
            id: shortHist
            Kirigami.FormData.label: ""
            text: i18n("Let through stocks with under 200 sessions of history")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            QQC2.ToolTip.text: i18n("A recent listing has no 200-day EMA yet. Also applies to the screener's filter \"Price above its 200-day EMA\".")
        }
        QQC2.CheckBox {
            id: themePreview
            Kirigami.FormData.label: i18n("Replay:")
            text: i18n("Outside market hours, show the last session's theme tickers")
            QQC2.ToolTip.text: i18n("Prices are the latest known, not live.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Before each ticker:")
            implicitContentWidthPolicy: QQC2.ComboBox.WidestText
            readonly property var keys: ["name", "icon", "both"]
            model: [i18n("The theme's name"), i18n("The theme's icon"), i18n("Icon and name")]
            currentIndex: Math.max(0, keys.indexOf(cfg_tapeThemeMark || "name"))
            onActivated: index => cfg_tapeThemeMark = keys[index]
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            QQC2.ToolTip.text: i18n("The name comes with a dot in the theme's heat colour; the icon is the theme's own, coloured by heat. A theme with no ticker running always shows its name.")
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("Needs the Themes entry starred in Symbols. During a session, a strong theme's tickers show while they are still running; one leaves once it falls the set distance below its high. A strong theme with nothing running holds the slot itself (its name and state) until a ticker runs again or the theme fades. Out of hours, you see the themes that have been strong. Only themes, not sectors, and only stocks from screens with \"Its stocks build the theme and sector heat\" ticked (Settings → Screeners).")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
    }
}
