// Settings → Performance: how often the widget asks for data, and how much.
//
// The presets fill in every control below them; touching any control makes
// it "Custom". Full is how the widget always ran and suits a desktop; Light
// is for a laptop or a metered connection. Measured 2026-10-24 on the
// developer's machine: the widget's own code is ~0.6 % of one core and
// ~76 MB; the stock check is the network cost -- ~73 KB per 200 stocks
// (~48 KB with "only the fields used"), ~3.5 GB over a 04:00-20:00 day at
// 30 s, every stock every pass.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_perfPreset: "full"
    property alias cfg_passSeconds: passSec.value
    property alias cfg_smartPoll: smart.checked
    property alias cfg_smartRestMinutes: rest.value
    property alias cfg_poolMinutes: pool.value
    property alias cfg_poolClosedMinutes: poolClosed.value
    property alias cfg_closedPassMinutes: closedPass.value
    property alias cfg_cryptoPassSeconds: crypto.value
    property alias cfg_newsPollSeconds: news.value
    property alias cfg_quoteFields: fields.checked
    property alias cfg_valueMinutes: valueBatch.value

    readonly property var presets: ({
        full:     { passSeconds: 30, smartPoll: false, smartRestMinutes: 5,  poolMinutes: 5,  poolClosedMinutes: 5,
                    closedPassMinutes: 15, cryptoPassSeconds: 30,  newsPollSeconds: 60,  quoteFields: true, valueMinutes: 2 },
        balanced: { passSeconds: 30, smartPoll: true,  smartRestMinutes: 5,  poolMinutes: 10, poolClosedMinutes: 30,
                    closedPassMinutes: 30, cryptoPassSeconds: 60,  newsPollSeconds: 120, quoteFields: true, valueMinutes: 5 },
        light:    { passSeconds: 60, smartPoll: true,  smartRestMinutes: 10, poolMinutes: 15, poolClosedMinutes: 60,
                    closedPassMinutes: 60, cryptoPassSeconds: 120, newsPollSeconds: 300, quoteFields: true, valueMinutes: 15 }
    })
    readonly property var presetKeys: ["full", "balanced", "light", "custom"]
    // Set while a preset is being applied, so the controls' own change
    // handlers do not flip the choice to Custom.
    property bool applying: false
    function apply(key) {
        const p = presets[key]
        if (!p) return
        applying = true
        passSec.value = p.passSeconds; smart.checked = p.smartPoll; rest.value = p.smartRestMinutes
        pool.value = p.poolMinutes; poolClosed.value = p.poolClosedMinutes; closedPass.value = p.closedPassMinutes
        crypto.value = p.cryptoPassSeconds; news.value = p.newsPollSeconds; fields.checked = p.quoteFields
        valueBatch.value = p.valueMinutes
        cfg_perfPreset = key
        applying = false
    }
    function touched() { if (!applying && ready) cfg_perfPreset = "custom" }
    property bool ready: false
    Component.onCompleted: ready = true

    // A whole number typed into a box ("45 s" -> 45); the old value when
    // there is none, so stray typing changes nothing.
    function typedInt(text, old) {
        const m = String(text || "").match(/-?\d+/)
        return m ? parseInt(m[0]) : old
    }

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Preset:")
            implicitContentWidthPolicy: QQC2.ComboBox.WidestText
            model: [i18n("Full — every stock every pass (desktop)"), i18n("Balanced — fewer checks out of hours"),
                    i18n("Light — laptop or metered connection"), i18n("Custom")]
            currentIndex: Math.max(0, page.presetKeys.indexOf(page.cfg_perfPreset))
            // Custom keeps the settings below as they are.
            onActivated: index => { if (index < 3) page.apply(page.presetKeys[index]); else page.cfg_perfPreset = "custom" }
            QQC2.ToolTip.text: i18n("Presets fill in everything below. Changing any setting below switches to Custom.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.Label {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("The stock check is the cost that matters: about 3.5 GB of data over a trading day on Full. The widget's own processing is small (well under 1% of one core). Changes apply when you press Apply.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Stocks") }

        QQC2.SpinBox {
            id: passSec
            Kirigami.FormData.label: i18n("Check prices every:")
            // 120 s is the most the setting stores (config/main.xml).
            from: 10; to: 120; stepSize: 5
            editable: true
            validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
            textFromValue: (v, locale) => i18n("%1 s", v)
            valueFromText: (text, locale) => page.typedInt(text, passSec.value)
            onValueModified: page.touched()
            QQC2.ToolTip.text: i18n("How often the screener re-prices the stocks it watches during market hours (10 to 120 seconds).")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.Label {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("Running Up compares each check with the last few minutes, so a longer gap catches fewer, slower runs. Under 30 s risks Yahoo refusing for a while; the widget slows itself down if it does.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        QQC2.CheckBox {
            id: smart
            Kirigami.FormData.label: i18n("Smart checking:")
            text: i18n("Each check, only the stocks your alert screens could catch")
            onToggled: page.touched()
            QQC2.ToolTip.text: i18n("Between full checks, ask only for stocks whose price and size could match an alert screen. Saves data; ranked lists update more slowly.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.SpinBox {
            id: rest
            Kirigami.FormData.label: i18n("…and every stock every:")
            enabled: smart.checked
            from: 1; to: 60
            editable: true
            validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
            textFromValue: (v, locale) => i18n("%1 min", v)
            valueFromText: (text, locale) => page.typedInt(text, rest.value)
            onValueModified: page.touched()
            QQC2.ToolTip.text: i18n("With smart checking on, how often a full check of every watched stock still runs.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.Label {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("Read from your alert screens' price and market-cap filters, with room either side: a $2B cap on Running Up leaves the large caps to the slower full check. Ranked lists like Top Gainers then refresh at the slower pace.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        QQC2.CheckBox {
            id: fields
            Kirigami.FormData.label: i18n("Smaller requests:")
            text: i18n("Ask Yahoo only for the fields the widget uses (about a third less data)")
            onToggled: page.touched()
            QQC2.ToolTip.text: i18n("Leaves out quote fields the widget never shows. Nothing visible changes.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Rebuild the list of stocks to watch every:")
            QQC2.SpinBox {
                id: pool
                from: 1; to: 60
                editable: true
                validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
                textFromValue: (v, locale) => i18n("%1 min", v)
                valueFromText: (text, locale) => page.typedInt(text, pool.value)
                onValueModified: page.touched()
                QQC2.ToolTip.text: poolTip.text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Label { text: i18n("while trading") }
        }
        RowLayout {
            Kirigami.FormData.label: ""
            QQC2.SpinBox {
                id: poolClosed
                from: 1; to: 240
                editable: true
                validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
                textFromValue: (v, locale) => i18n("%1 min", v)
                valueFromText: (text, locale) => page.typedInt(text, poolClosed.value)
                onValueModified: page.touched()
                QQC2.ToolTip.text: poolTip.text
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Label { text: i18n("while closed") }
            QtObject {
                id: poolTip
                readonly property string text: i18n("Re-finds which stocks meet the volume rules at the top of Settings → Screeners.")
            }
        }
        QQC2.SpinBox {
            id: closedPass
            Kirigami.FormData.label: i18n("While closed, check prices every:")
            from: 1; to: 240
            editable: true
            validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
            textFromValue: (v, locale) => i18n("%1 min", v)
            valueFromText: (text, locale) => page.typedInt(text, closedPass.value)
            onValueModified: page.touched()
            QQC2.ToolTip.text: i18n("Outside market hours prices barely move, so the screener checks less often.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Everything else") }

        RowLayout {
            Kirigami.FormData.label: i18n("Crypto, check every:")
            QQC2.SpinBox {
                id: crypto
                from: 10; to: 600; stepSize: 5
                editable: true
                validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
                textFromValue: (v, locale) => i18n("%1 s", v)
                valueFromText: (text, locale) => page.typedInt(text, crypto.value)
                onValueModified: page.touched()
                QQC2.ToolTip.text: i18n("How often crypto prices are checked from Coinbase. Only while a crypto screen is on.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Label { text: i18n("(only with a crypto screen)"); opacity: 0.7 }
        }
        QQC2.SpinBox {
            id: news
            Kirigami.FormData.label: i18n("Your news sources, every:")
            from: 15; to: 900; stepSize: 15
            editable: true
            validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
            textFromValue: (v, locale) => i18n("%1 s", v)
            valueFromText: (text, locale) => page.typedInt(text, news.value)
            onValueModified: page.touched()
            QQC2.ToolTip.text: i18n("Your own feeds (Settings → Data). The built-in market desks refresh every 3 minutes.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Long-term value checks, a batch every:")
            QQC2.SpinBox {
                id: valueBatch
                from: 1; to: 120
                editable: true
                validator: RegularExpressionValidator { regularExpression: /[^\d]*\d*[^\d]*/ }
                textFromValue: (v, locale) => i18n("%1 min", v)
                valueFromText: (text, locale) => page.typedInt(text, valueBatch.value)
                onValueModified: page.touched()
                QQC2.ToolTip.text: i18n("How often the next batch of companies is scored from SEC filings for the long-term value lists.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
        QQC2.Label {
            Kirigami.FormData.label: ""
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("Each batch scores up to 40 companies from SEC filings, only while a long-term value screen exists. At 2 minutes or less the batches run back to back until every company is scored.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
    }
}
