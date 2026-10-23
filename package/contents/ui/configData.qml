// Settings → Data: the scanner the screener's bridge runs (code/scanner/ by
// default) and what it is told -- the SEC contact, and which companies'
// earnings the calendar lists. Passed to the scanner as environment
// variables on every call (ScreenerEngine.qml, `bridgeRun`).

import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_scannerDir: scannerDir.text
    property alias cfg_secContact: secContact.text
    property alias cfg_researchDir: researchDir.text
    property alias cfg_earningsTickers: earningsTickers.text
    property real cfg_earningsMinCap

    // The folder chooser fills whichever field asked for it.
    property var folderTarget: null
    FolderDialog {
        id: folderDialog
        onAccepted: folderTarget.text = decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, ""))
    }
    function browse(field) {
        folderTarget = field
        folderDialog.open()
    }

    Kirigami.FormLayout {
        RowLayout {
            Kirigami.FormData.label: i18n("Scanner folder:")
            QQC2.TextField {
                id: scannerDir
                Layout.minimumWidth: Kirigami.Units.gridUnit * 18
                placeholderText: i18n("Built-in (code/scanner)")
            }
            QQC2.Button {
                icon.name: "folder-open"
                onClicked: browse(scannerDir)
            }
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("Leave empty to use the scanner that ships with the widget. Point it at your own copy to change how the lists, news and calendar are gathered.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.TextField {
            id: secContact
            Kirigami.FormData.label: i18n("SEC contact:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 18
            placeholderText: i18n("Your Name you@example.com")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("SEC EDGAR asks every program to identify itself with a name and an email. It is sent only to sec.gov. Without it, dilution risk and the long-term value checks stay empty.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Item {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Earnings calendar")
        }

        QQC2.SpinBox {
            Kirigami.FormData.label: i18n("Always list companies worth:")
            from: 0
            to: 5000
            stepSize: 5
            value: Math.round(cfg_earningsMinCap / 1e9)
            onValueModified: cfg_earningsMinCap = value * 1e9
            textFromValue: (v, locale) => i18n("$%1B or more", v)
            valueFromText: (text, locale) => parseInt(String(text).replace(/[^0-9]/g, ""))
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Research folder:")
            QQC2.TextField {
                id: researchDir
                Layout.minimumWidth: Kirigami.Units.gridUnit * 18
                placeholderText: i18n("Optional")
            }
            QQC2.Button {
                icon.name: "folder-open"
                onClicked: browse(researchDir)
            }
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("Any subfolder named by a ticker, in this folder or one level down (Research/AMD, or Research/Investing/AMD), puts that company's earnings on the calendar.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        QQC2.TextField {
            id: earningsTickers
            Kirigami.FormData.label: i18n("Always list these tickers:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 18
            placeholderText: i18n("e.g. AMD, NVDA, KO")
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("Every other reporter is left off, so the calendar shows the companies you follow rather than every company reporting that day.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
    }
}
