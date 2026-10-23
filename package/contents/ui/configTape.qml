// Settings → Tape: how the strip moves and looks.

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_scrollSpeed: speed.value
    property alias cfg_tapeWidth: stripWidth.value
    property alias cfg_fearLine: fear.value
    property alias cfg_pollSeconds: poll.value

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: speed
            Kirigami.FormData.label: i18n("Scroll speed:")
            from: 5
            to: 150
            stepSize: 5
            textFromValue: (v, locale) => i18n("%1 px/s", v)
            valueFromText: (text, locale) => parseInt(text)
        }
        QQC2.SpinBox {
            id: stripWidth
            Kirigami.FormData.label: i18n("Strip width:")
            from: 4
            to: 60
            textFromValue: (v, locale) => i18n("%1 units", v)
            valueFromText: (text, locale) => parseInt(text)
        }
        QQC2.SpinBox {
            id: poll
            Kirigami.FormData.label: i18n("Refresh every:")
            from: 15
            to: 900
            stepSize: 15
            textFromValue: (v, locale) => i18n("%1 s", v)
            valueFromText: (text, locale) => parseInt(text)
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.SpinBox {
            id: fear
            Kirigami.FormData.label: i18n("VIX fear line:")
            from: 5
            to: 90
        }
        QQC2.Label {
            text: i18n("VIX shows red at or above this level, green below it.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
    }
}
