// Settings → Workspace: the detached window, the screen buttons' highlight,
// the active ticker's history and where exports go. Every setting here is
// this page's alone; the pop-up never writes them, so plain aliases do.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property alias cfg_tabFlashSeconds: flash.value
    property alias cfg_hotkeyWindow: hotkey.checked
    property alias cfg_exportFolder: folder.text
    property alias cfg_recentCount: recentBox.value
    property alias cfg_quoteFollowsClicks: quoteFollows.checked
    property alias cfg_aboutChars: aboutBox.value
    property real cfg_optAccountSize
    property real cfg_optRiskPct
    property real cfg_optWalkAway
    property real cfg_optRate
    property alias cfg_optExpiryDays: expiryDays.value
    property real cfg_optStrikePct
    property alias cfg_ivRecord: ivRecord.checked
    // Options are switched off for now (main.xml `optionsFeature`).
    property bool cfg_optionsFeature
    readonly property bool optionsOn: cfg_optionsFeature

    // A money or percent box: typed text in, the stored number out.
    component NumberField: QQC2.TextField {
        id: nf
        property real value
        property string prefix: ""
        property string suffix: ""
        signal edited(real v)
        Layout.preferredWidth: Kirigami.Units.gridUnit * 6
        Layout.maximumWidth: Kirigami.Units.gridUnit * 6
        text: prefix + Number(value).toLocaleString(Qt.locale("C"), "f", value % 1 ? 2 : 0) + suffix
        onEditingFinished: {
            const v = parseFloat(text.replace(/[^0-9.\-]/g, ""))
            if (isFinite(v) && v >= 0) edited(v)
            text = Qt.binding(() => nf.prefix + Number(nf.value).toLocaleString(Qt.locale("C"), "f", nf.value % 1 ? 2 : 0) + nf.suffix)
        }
        QQC2.ToolTip.visible: hovered && QQC2.ToolTip.text !== ""
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
    }
    property alias cfg_chartRefreshSeconds: chartRefresh.value

    FolderDialog {
        id: folderDialog
        onAccepted: folder.text = decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, ""))
    }

    Kirigami.FormLayout {
        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Screen buttons") }
        RowLayout {
            Kirigami.FormData.label: i18n("Light a screen's button for:")
            QQC2.SpinBox {
                id: flash
                from: 0; to: 600
                editable: true
                QQC2.ToolTip.text: i18n("After each alert, the screen's button lights up in its colour (Settings → Screeners) for this long, so the screen that alerted can be seen at a glance. 0 turns it off. The count of alerts not yet looked at stays until the screen is opened.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Label { text: i18n("seconds after an alert") }
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Detached window") }
        QQC2.CheckBox {
            id: hotkey
            Kirigami.FormData.label: i18n("Keyboard shortcut:")
            text: i18n("Shows and hides the window, not the pop-up")
            QQC2.ToolTip.text: i18n("The shortcut itself is set on the Keyboard Shortcuts page of these settings. With this on it opens the detached window, brings it to the front, or closes it.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Pop the window out with the button in the pop-up's header. Its size is remembered. On Wayland the window system decides where a new window opens; a KWin window rule (right-click the title bar → More Actions → Configure Special Window Settings) can keep it in one place.")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Active ticker") }
        RowLayout {
            Kirigami.FormData.label: i18n("Recent tickers kept:")
            QQC2.SpinBox {
                id: recentBox
                from: 0; to: 30
                editable: true
                QQC2.ToolTip.text: i18n("The symbols last opened, shown as buttons on the quote card to jump back to.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
        QQC2.CheckBox {
            id: quoteFollows
            Kirigami.FormData.label: i18n("Quote window:")
            text: i18n("Clicked tickers open there, and the list stays")
            QQC2.ToolTip.text: i18n("Pop a quote card out with its window button. While a linked quote window is open, clicking a ticker on any tab shows it in that window and in every linked chart window, and the screener or watchlist stays where it was. Off: a click opens the quote card in the pop-up, as without the window.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Company description:")
            QQC2.SpinBox {
                id: aboutBox
                from: 0; to: 2000; stepSize: 20
                editable: true
                QQC2.ToolTip.text: i18n("The description on a stock's quote card: its first sentence, cut at this many characters. 0 shows the first two lines instead. Click the description to read all of it.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Label { text: i18n("characters of the first sentence") }
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Charts") }
        RowLayout {
            Kirigami.FormData.label: i18n("Reload the bars every:")
            QQC2.SpinBox {
                id: chartRefresh
                from: 0; to: 3600
                editable: true
                QQC2.ToolTip.text: i18n("How often a chart on screen (on a quote card or in a chart window) fetches its bars again. 0 = only when opened or when the bar size changes. Each reload is one request to Yahoo per chart.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Label { text: i18n("seconds") }
        }
        Item { visible: page.optionsOn; Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Options") }
        NumberField {
            visible: page.optionsOn
            Kirigami.FormData.label: i18n("Account size:")
            prefix: "$"
            value: page.cfg_optAccountSize
            onEdited: v => page.cfg_optAccountSize = v
            QQC2.ToolTip.text: i18n("For position sizing on a quote card's Options tab.")
        }
        NumberField {
            visible: page.optionsOn
            Kirigami.FormData.label: i18n("Risk per trade:")
            suffix: "%"
            value: page.cfg_optRiskPct
            onEdited: v => page.cfg_optRiskPct = v
            QQC2.ToolTip.text: i18n("The share of the account one trade may lose. The Options tab says how many of a position fit it.")
        }
        NumberField {
            visible: page.optionsOn
            Kirigami.FormData.label: i18n("Daily walk-away:")
            prefix: "$"
            value: page.cfg_optWalkAway
            onEdited: v => page.cfg_optWalkAway = v
            QQC2.ToolTip.text: i18n("The amount at which you stop trading for the day. The Options tab shows a position's worst case as a share of it. 0 hides that.")
        }
        NumberField {
            visible: page.optionsOn
            Kirigami.FormData.label: i18n("Interest rate:")
            suffix: "%"
            value: page.cfg_optRate
            onEdited: v => page.cfg_optRate = v
            QQC2.ToolTip.text: i18n("The risk-free rate used to price options (Black-Scholes), a year. A 3-month Treasury yield is the usual choice.")
        }
        RowLayout {
            visible: page.optionsOn
            Kirigami.FormData.label: i18n("Expiry alerts:")
            QQC2.SpinBox {
                id: expiryDays
                from: 0; to: 60
                editable: true
                QQC2.ToolTip.text: i18n("A desktop notification once a day for an open journal trade this close to expiry. 0 turns it off.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Label { text: i18n("days before expiry") }
        }
        RowLayout {
            visible: page.optionsOn
            Kirigami.FormData.label: i18n("Strike alerts:")
            NumberField {
                suffix: "%"
                value: page.cfg_optStrikePct
                onEdited: v => page.cfg_optStrikePct = v
                QQC2.ToolTip.text: i18n("A desktop notification once a day when the stock comes within this % of a strike of an open journal trade. 0 turns it off.")
            }
            QQC2.Label { text: i18n("from a strike") }
        }
        QQC2.CheckBox {
            visible: page.optionsOn
            id: ivRecord
            Kirigami.FormData.label: i18n("IV rank:")
            text: i18n("Record the watchlist's implied volatility each day")
            QQC2.ToolTip.text: i18n("Once a trading day after 10:00 New York time, each watchlist stock's at-the-money IV (the nearest expiry a week or more out), kept a year. IV rank needs 20 days recorded; until then the card says how many it has. Yahoo has no IV history to start from.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.Label {
            visible: page.optionsOn
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Option chains are Yahoo's free data, delayed about 15 minutes. Pricing, Greeks and odds are Black-Scholes without dividends: a guide, not a quote.")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Export") }
        RowLayout {
            Kirigami.FormData.label: i18n("Alert exports go to:")
            QQC2.TextField {
                id: folder
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                placeholderText: i18n("Documents/Plasma Ticker Tape")
                QQC2.ToolTip.text: i18n("Leave empty for the Plasma Ticker Tape folder in Documents. ~ is the home folder. One file per day, alerts-YYYY-MM-DD.csv, replaced on each export.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Button {
                icon.name: "folder-open"
                text: i18n("Choose…")
                onClicked: folderDialog.open()
            }
        }
    }
}
