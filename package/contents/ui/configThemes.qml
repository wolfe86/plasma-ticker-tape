// Settings → Themes: what counts as a live theme, and how the glyph is coloured.
//
// The numbers here are the ones worth arguing with. They decide when a group
// of runners becomes a theme, and when a theme that ran is called dead -- and
// the right values are a matter of what the board has actually been doing, so
// they are settings rather than constants.

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.iconthemes as KIconThemes
import org.kde.plasma.plasmoid
import QtQuick.LocalStorage
import "themes.js" as Themes

KCM.SimpleKCM {
    id: page

    // Every key this page declares, it edits. Plasma 6.8 writes back each
    // one on Apply, so a key the pop-up can also change (customThemes: Pin
    // to a theme, New theme from this headline; sectorOverrides: Set
    // sector) would be overwritten with the copy this page opened with.
    // saveConfig() below hands those back the live value unless this page
    // changed them itself.
    property string cfg_themeRamp: "heat"
    property alias cfg_themesOn: themesOn.checked
    property alias cfg_sectorsOn: sectorsOn.checked
    property string cfg_sectorOverrides: ""
    // Written from the controls rather than bound to them: a two-way binding
    // on one JSON string that several controls feed would loop.
    property string cfg_themeTuning: ""
    property string cfg_customThemes: ""
    property string cfg_customSectors: ""
    property string cfg_themeIcons: ""
    property int cfg_themeDeadDays: 30
    property int cfg_themeStickySessions: 10

    property bool themesDirty: false
    property bool overridesDirty: false
    // Plasma calls this before it writes the page's cfg_ values.
    function saveConfig() {
        let live = null
        try { live = Plasmoid.configuration } catch (e) {}
        if (live) {
            if (!themesDirty) cfg_customThemes = live.customThemes
            if (!overridesDirty) cfg_sectorOverrides = live.sectorOverrides
        }
        themesDirty = false
        overridesDirty = false
    }

    // ── sector overrides: {"TICKER": "s-energy"} ──
    readonly property var overrides: {
        try { return JSON.parse(cfg_sectorOverrides || "{}") } catch (e) { return ({}) }
    }
    function setOverride(sym, id) {
        const m = Object.assign({}, overrides)
        if (id) m[sym] = id; else delete m[sym]
        cfg_sectorOverrides = JSON.stringify(m)
        overridesDirty = true
    }

    // ── your themes and sectors ──
    // Both lists are written whole on every change. The themes setting is
    // empty until first saved, which means the starter set (themes.js); once
    // saved, an empty list means none.
    readonly property var myThemes: Themes.loadThemes({ customThemes: cfg_customThemes })
    readonly property var mySectors: Themes.loadSectors({ customSectors: cfg_customSectors })
    function commitThemes(l) { cfg_customThemes = JSON.stringify(l); themesDirty = true }
    function commitSectors(l) { cfg_customSectors = JSON.stringify(l) }
    function setGroup(kind, i, changes) {
        const l = (kind === "theme" ? myThemes : mySectors).slice()
        l[i] = Object.assign({}, l[i], changes)
        kind === "theme" ? commitThemes(l) : commitSectors(l)
    }
    function removeGroup(kind, i) {
        const l = (kind === "theme" ? myThemes : mySectors).filter((x, k) => k !== i)
        kind === "theme" ? commitThemes(l) : commitSectors(l)
    }
    function slug(name, prefix) { return prefix + String(name || "new").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") + "-" + Date.now().toString(36) }
    function addTheme() { commitThemes(myThemes.concat([{ id: slug("theme", "t-"), name: i18n("New theme"), glyph: "dot", words: [], tickers: [], market: "stocks", ramp: "", on: true }])) }
    function addSector() { commitSectors(mySectors.concat([{ id: slug("sector", "u-"), name: i18n("New sector"), glyph: "dot", industries: [], tickers: [], ramp: "", on: true }])) }
    function splitList(s, upper) { return String(s || "").split(",").map(x => x.trim()).filter(x => x).map(x => upper ? x.toUpperCase() : x) }
    // A pin counts from the day it is made (so history before it is not
    // re-tagged); the New York date, as the sessions are filed.
    function today() { return new Date(Date.now() - 4 * 3600000).toISOString().slice(0, 10) }
    readonly property var rampChoices: [{ key: "", text: i18n("Default colours") }, { key: "heat", text: i18n("Heat") },
                                        { key: "market", text: i18n("Market") }, { key: "violet", text: i18n("Violet (not colour-blind safe)") }]
    // Finviz's sectors and yours, for the overrides.
    readonly property var sectorChoices: Themes.sectorCatalog.map(s => ({ id: s.id, name: s.name }))
                                           .concat(mySectors.map(s => ({ id: s.id, name: s.name + " (" + i18n("yours") + ")" })))
    // The Finviz industries the widget has seen (learned from looked-up
    // stocks, kept beside the alerts), to pick from. Empty if not readable.
    // Remote text, shown in a list that renders markup: tags are dropped.
    readonly property var knownIndustries: {
        try {
            const db = LocalStorage.openDatabaseSync("MarketTickerAlerts", "1.0", "Market Ticker screener alerts", 20000000)
            const out = []
            db.readTransaction(tx => {
                const rs = tx.executeSql("SELECT industry, sector FROM industrysectors ORDER BY industry")
                for (let i = 0; i < rs.rows.length; i++) {
                    const s = Themes.sectorById(rs.rows.item(i).sector)
                    out.push({ industry: String(rs.rows.item(i).industry || "").replace(/[<>&]/g, ""), sector: s ? s.name : "" })
                }
            })
            return out
        } catch (e) { return [] }
    }

    // ── icons ──
    // {theme id: {icon, keep}}, written whole on every change.
    readonly property var icons: {
        try { return JSON.parse(cfg_themeIcons || "{}") } catch (e) { return ({}) }
    }
    function setIcon(id, changes) {
        const m = Object.assign({}, icons)
        m[id] = Object.assign({}, m[id] || { keep: false }, changes)
        cfg_themeIcons = JSON.stringify(m)
    }
    function resetIcon(id) {
        const m = Object.assign({}, icons)
        delete m[id]
        cfg_themeIcons = JSON.stringify(m)
    }
    // Sectors and crypto categories, for their icons. Stock and crypto
    // groups are listed apart: the two never share a board or a history.
    readonly property var cryptoRows: Themes.cryptoCatalog.map(t => ({ id: t.id, name: t.name, glyph: t.glyph }))
    readonly property var sectorRows: Themes.sectorCatalog.map(t => ({ id: t.id, name: t.name, glyph: t.glyph }))
    // The row the icon dialog is choosing for.
    property string editing: ""
    function chooseIcon(id) { editing = id; iconDialog.open() }

    // One of your themes or sectors, in the editor. The Repeater's model is
    // the list's length, not the list, so editing a field does not rebuild
    // every row (and lose the keyboard focus); the row reads its group by
    // index. `kind` comes from the column it sits in.
    Component {
        id: groupEditor
        ColumnLayout {
            id: ged
            required property int index
            readonly property string kind: parent && parent.kind ? parent.kind : "theme"
            readonly property var g: (kind === "sector" ? page.mySectors : page.myThemes)[index] || ({})
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            RowLayout {
                Layout.fillWidth: true
                QQC2.CheckBox {
                    checked: ged.g.on !== false
                    onToggled: {
                        page.setGroup(ged.kind, ged.index, { on: checked })
                        checked = Qt.binding(() => ged.g.on !== false)
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: ged.kind === "theme"
                        ? i18n("Use this theme. Off keeps it here but nothing is tagged with it.")
                        : i18n("Use this sector. Off keeps it here but nothing is tagged with it.")
                }
                ThemeGlyph {
                    theme: ged.g
                    status: "hot"
                    ramp: ged.g.ramp || page.cfg_themeRamp || "heat"
                    icons: page.icons
                    size: Kirigami.Units.iconSizes.smallMedium
                }
                QQC2.TextField {
                    Layout.fillWidth: false
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 6
                    readonly property string stored: ged.g.name || ""
                    onStoredChanged: if (!activeFocus) text = stored
                    Component.onCompleted: text = stored
                    onEditingFinished: if (text !== ged.g.name) page.setGroup(ged.kind, ged.index, { name: text })
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Its name, as the tooltips and the Theme Hunter show it")
                }
                QQC2.ComboBox {
                    model: Themes.glyphNames
                    currentIndex: Math.max(0, Themes.glyphNames.indexOf(ged.g.glyph || "dot"))
                    onActivated: index => {
                        page.setGroup(ged.kind, ged.index, { glyph: Themes.glyphNames[index] })
                        currentIndex = Qt.binding(() => Math.max(0, Themes.glyphNames.indexOf(ged.g.glyph || "dot")))
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Built-in icon")
                }
                QQC2.ToolButton {
                    icon.name: "document-edit"
                    onClicked: page.chooseIcon(ged.g.id)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Your own icon instead (icon theme or a file)")
                }
                QQC2.ComboBox {
                    model: page.rampChoices.map(r => r.text)
                    currentIndex: Math.max(0, page.rampChoices.findIndex(r => r.key === (ged.g.ramp || "")))
                    onActivated: index => {
                        page.setGroup(ged.kind, ged.index, { ramp: page.rampChoices[index].key })
                        currentIndex = Qt.binding(() => Math.max(0, page.rampChoices.findIndex(r => r.key === (ged.g.ramp || ""))))
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Colours for this one only (Default = the Icon colours setting)")
                }
                QQC2.ToolButton {
                    icon.name: "edit-delete"
                    onClicked: page.removeGroup(ged.kind, ged.index)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Delete (Cancel undoes it before Apply)")
                }
            }
            RowLayout {
                visible: ged.kind === "theme"
                Layout.fillWidth: true
                QQC2.ComboBox {
                    model: [i18n("Stocks"), i18n("Crypto")]
                    currentIndex: ged.g.market === "crypto" ? 1 : 0
                    onActivated: index => {
                        page.setGroup(ged.kind, ged.index, { market: index ? "crypto" : "stocks" })
                        currentIndex = Qt.binding(() => ged.g.market === "crypto" ? 1 : 0)
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Which board this theme watches")
                }
                QQC2.TextField {
                    Layout.fillWidth: true
                    readonly property string stored: (ged.g.words || []).join(", ")
                    onStoredChanged: if (!activeFocus) text = stored
                    Component.onCompleted: text = stored
                    placeholderText: i18n("Headline words, comma-separated: nuclear, drone*, eth | sol + treasury")
                    onEditingFinished: page.setGroup(ged.kind, ged.index, { words: page.splitList(text, false) })
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("A stock joins when its newest headline contains any of these, as whole words. drone* matches any ending (drones); eth | sol matches either; eth + holdings needs both within 60 characters.")
                }
            }
            // A pattern beyond headline words (2026-10-26): Finviz industries
            // (either these or the words will do), and traits that must all hold.
            RowLayout {
                visible: ged.kind === "theme" && ged.g.market !== "crypto"
                Layout.fillWidth: true
                QQC2.TextField {
                    Layout.fillWidth: true
                    readonly property string stored: (ged.g.industries || []).join(", ")
                    onStoredChanged: if (!activeFocus) text = stored
                    Component.onCompleted: text = stored
                    placeholderText: i18n("Or Finviz industries, comma-separated: Oil & Gas E&P")
                    onEditingFinished: page.setGroup(ged.kind, ged.index, { industries: page.splitList(text, false) })
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("A stock in one of these industries joins, headline or not. With words too, either will do.")
                }
            }
            GridLayout {
                visible: ged.kind === "theme" && ged.g.market !== "crypto"
                Layout.fillWidth: true
                columns: 4
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Kirigami.Units.smallSpacing
                readonly property var w: ged.g.when || ({})
                function setW(k, v) {
                    const w = Object.assign({}, ged.g.when || {})
                    if (v === "" || v === 0 || v === false || v === undefined) delete w[k]
                    else w[k] = v
                    page.setGroup(ged.kind, ged.index, { when: w })
                }
                QQC2.ComboBox {
                    id: newsBox
                    model: [i18n("News: either"), i18n("No news in 24 h"), i18n("News in 24 h")]
                    currentIndex: parent.w.news === "none" ? 1 : parent.w.news === "some" ? 2 : 0
                    onActivated: index => {
                        parent.setW("news", ["", "none", "some"][index])
                        currentIndex = Qt.binding(() => parent.w.news === "none" ? 1 : parent.w.news === "some" ? 2 : 0)
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Only stocks with no headline in the last 24 hours (a stock not yet looked up does not count), or only ones with one")
                }
                QQC2.CheckBox {
                    text: i18n("Foreign")
                    checked: !!parent.w.foreign
                    onToggled: { parent.setW("foreign", checked); checked = Qt.binding(() => !!parent.w.foreign) }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Only companies based outside the US (Finviz's country, else Yahoo's)")
                }
                QQC2.SpinBox {
                    from: 0; to: 500; editable: true
                    value: Math.round((parent.w.floatMax || 0) / 1e6)
                    textFromValue: (v, locale) => v ? i18n("float ≤ %1M", v) : i18n("any float")
                    valueFromText: text => parseInt(String(text).replace(/[^0-9]/g, "")) || 0
                    onValueModified: parent.setW("floatMax", value * 1e6)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Only floats at or under this many million shares (0 = any)")
                }
                QQC2.SpinBox {
                    from: 0; to: 3650; stepSize: 30; editable: true
                    value: parent.w.ipoDays || 0
                    textFromValue: (v, locale) => v ? i18n("listed ≤ %1 days", v) : i18n("any listing date")
                    valueFromText: text => parseInt(String(text).replace(/[^0-9]/g, "")) || 0
                    onValueModified: parent.setW("ipoDays", value)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Only stocks that started trading within this many days: recent IPOs (0 = any)")
                }
                QQC2.SpinBox {
                    from: 0; to: 1000; editable: true
                    value: parent.w.priceMin || 0
                    textFromValue: (v, locale) => v ? i18n("price ≥ $%1", v) : i18n("any low price")
                    valueFromText: text => parseInt(String(text).replace(/[^0-9]/g, "")) || 0
                    onValueModified: parent.setW("priceMin", value)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Only prices at or over this (0 = any)")
                }
                QQC2.SpinBox {
                    from: 0; to: 1000; editable: true
                    value: parent.w.priceMax || 0
                    textFromValue: (v, locale) => v ? i18n("price ≤ $%1", v) : i18n("any high price")
                    valueFromText: text => parseInt(String(text).replace(/[^0-9]/g, "")) || 0
                    onValueModified: parent.setW("priceMax", value)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Only prices at or under this (0 = any)")
                }
                QQC2.SpinBox {
                    from: 0; to: 100000; stepSize: 100; editable: true
                    value: Math.round((parent.w.capMax || 0) / 1e6)
                    textFromValue: (v, locale) => v ? i18n("cap ≤ $%1M", v) : i18n("any market cap")
                    valueFromText: text => parseInt(String(text).replace(/[^0-9]/g, "")) || 0
                    onValueModified: parent.setW("capMax", value * 1e6)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Only market caps at or under this many million dollars (0 = any)")
                }
            }
            RowLayout {
                visible: ged.kind === "sector"
                Layout.fillWidth: true
                QQC2.TextField {
                    Layout.fillWidth: true
                    readonly property string stored: (ged.g.industries || []).join(", ")
                    onStoredChanged: if (!activeFocus) text = stored
                    Component.onCompleted: text = stored
                    placeholderText: i18n("Finviz industries, comma-separated: Software - Application")
                    onEditingFinished: page.setGroup(ged.kind, ged.index, { industries: page.splitList(text, false) })
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Every stock Finviz puts in one of these industries joins this sector")
                }
                QQC2.ComboBox {
                    visible: page.knownIndustries.length > 0
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                    model: [i18n("Add an industry…")].concat(page.knownIndustries.map(k => k.industry + (k.sector ? " (" + k.sector + ")" : "")))
                    onActivated: index => {
                        if (index > 0) {
                            const ind = page.knownIndustries[index - 1].industry
                            const l = (ged.g.industries || []).filter(x => x !== ind).concat([ind])
                            page.setGroup(ged.kind, ged.index, { industries: l })
                        }
                        currentIndex = 0
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Industries Finviz has given the stocks the widget has looked up so far")
                }
            }
            QQC2.TextField {
                Layout.fillWidth: true
                readonly property string stored: (ged.kind === "theme" ? Themes.pinSymbols(ged.g) : (ged.g.tickers || [])).join(", ")
                onStoredChanged: if (!activeFocus) text = stored
                Component.onCompleted: text = stored
                placeholderText: ged.kind === "theme" ? i18n("Pinned tickers, comma-separated (optional): always on this theme")
                                                      : i18n("Tickers, comma-separated: ADBE, INTU")
                onEditingFinished: {
                    const l = page.splitList(text, true)
                    page.setGroup(ged.kind, ged.index, { tickers: ged.kind === "theme" ? Themes.setPins(ged.g, l, page.today()) : l })
                }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: ged.kind === "theme"
                    ? i18n("Always on this theme, whatever the headline, from the day you add them. Days before that keep their own tagging.")
                    : i18n("Always in this sector, whatever Finviz says")
            }
            Kirigami.Separator { Layout.fillWidth: true }
        }
    }

    // One group's row in the icon lists.
    Component {
        id: iconRow
        RowLayout {
            id: irow
            required property var modelData
            readonly property var mine: page.icons[modelData.id] || null
            spacing: Kirigami.Units.smallSpacing
            // As it will look hot, quiet and burnt.
            Repeater {
                model: [["hot", i18n("How it looks when hot")], ["quiet", i18n("How it looks when quiet")],
                        ["burnt", i18n("How it looks when burnt (dead)")]]
                ThemeGlyph {
                    required property var modelData
                    theme: irow.modelData
                    status: modelData[0]
                    ramp: page.cfg_themeRamp || "heat"
                    icons: page.icons
                    size: Kirigami.Units.iconSizes.smallMedium
                    HoverHandler { id: previewHover }
                    QQC2.ToolTip.visible: previewHover.hovered
                    QQC2.ToolTip.text: modelData[1]
                }
            }
            QQC2.Label {
                text: modelData.name
                textFormat: Text.PlainText
                Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                elide: Text.ElideRight
            }
            QQC2.ComboBox {
                model: Themes.glyphNames
                currentIndex: Math.max(0, Themes.glyphNames.indexOf(Themes.glyphName(modelData, page.icons)))
                onActivated: index => page.setIcon(modelData.id, { glyph: Themes.glyphNames[index] })
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Pick a glyph from the library")
            }
            QQC2.Button {
                icon.name: "document-edit"
                text: i18n("Change…")
                onClicked: page.chooseIcon(modelData.id)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Pick an icon from your icon theme or from a file")
            }
            QQC2.CheckBox {
                text: i18n("Keep its colours")
                enabled: !!(mine && mine.icon)
                checked: !!mine && !!mine.keep
                onToggled: page.setIcon(modelData.id, { keep: checked })
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("For a full-colour icon: shown as it is, with the heat as a ring around it. Off, the icon is tinted by the heat, which suits single-colour icons.")
            }
            QQC2.ToolButton {
                visible: !!mine
                icon.name: "edit-undo"
                onClicked: page.resetIcon(modelData.id)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Back to the built-in glyph")
            }
        }
    }

    KIconThemes.IconDialog {
        id: iconDialog
        onAccepted: if (page.editing && iconName) page.setIcon(page.editing, { icon: iconName })
    }

    readonly property var rampKeys: ["heat", "market", "violet"]
    // The live tuning, for the help text's numbers.
    readonly property var tuned: Themes.tune({ themeTuning: cfg_themeTuning, themeDeadDays: cfg_themeDeadDays,
                                               themeStickySessions: cfg_themeStickySessions })

    // The page's controls, merged into what is stored: keys this page does
    // not show (keepDays, minHistory, window) keep a hand-set value, and the
    // ones retired on 2026-10-24 (minMembers, hotFollow, coldTrips,
    // burnWindow) are dropped.
    function pushTuning() {
        if (!ready) return
        const t = Themes.tune({ themeTuning: cfg_themeTuning })
        const o = {}
        for (const k of ["ranPct", "noNewsPct", "runRvol", "hotDays", "hotWindow", "stayDays", "liftX",
                         "keepDays", "minHistory", "window"]) o[k] = t[k]
        let stored = {}
        try { stored = JSON.parse(cfg_themeTuning || "{}") } catch (e) {}
        // keepDays as stored, not as stretched to cover the dead line.
        o.keepDays = typeof stored.keepDays === "number" ? stored.keepDays : Themes.defaults.keepDays
        o.ranPct    = ranPct.value
        o.noNewsPct = noNewsPct.value
        o.runRvol   = runRvol.value
        o.hotDays   = hotDays.value
        o.hotWindow = hotWindow.value
        o.stayDays  = stayDays.value
        o.liftX     = lift.value / 10
        cfg_themeTuning = JSON.stringify(o)
    }
    property bool ready: false
    Component.onCompleted: {
        const t = Themes.tune({ themeTuning: cfg_themeTuning })
        ranPct.value    = t.ranPct
        noNewsPct.value = t.noNewsPct
        runRvol.value   = t.runRvol
        hotWindow.value = t.hotWindow
        hotDays.value   = t.hotDays
        stayDays.value  = t.stayDays
        lift.value      = Math.round(t.liftX * 10)
        ramp.currentIndex = Math.max(0, rampKeys.indexOf(cfg_themeRamp || "heat"))
        ready = true
    }

    Kirigami.FormLayout {
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 28
            visible: true
            type: Kirigami.MessageType.Warning
            text: i18n("Themes and sectors are a beta. The readings have not yet been checked against weeks of live trading, so the defaults below are a starting point and will change. Treat an icon's colour as a prompt to look, not a signal.")
        }
        QQC2.CheckBox {
            id: themesOn
            Kirigami.FormData.label: i18n("Themes:")
            text: i18n("Show theme icons and keep their history")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Show theme icons, keep their history, and feed the tape's Themes entry and the Theme Hunter")
        }
        QQC2.CheckBox {
            id: sectorsOn
            Kirigami.FormData.label: i18n("Sectors:")
            text: i18n("Show sector icons, coloured by heat, and keep their history")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Show sector icons coloured by how active the sector is, and keep their history")
        }
        QQC2.Label {
            Kirigami.FormData.label: ""
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("Every stock shows its sector, whatever its headline. A sector that keeps turning up on your screens heats up the same way a theme does: the cue to look for the common catalyst, then name it as a theme. For crypto, the sector is the coin's CoinGecko category.")
            font: Kirigami.Theme.smallFont
            opacity: 0.75
        }
        QQC2.ComboBox {
            id: ramp
            Kirigami.FormData.label: i18n("Icon colours:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 22
            textRole: "text"
            valueRole: "key"
            model: [
                { key: "heat",   text: i18n("Heat — grey, amber, red") },
                { key: "market", text: i18n("Market — grey, amber, green (red is kept for falling prices)") },
                { key: "violet", text: i18n("Violet — grey, lilac, magenta (not colour-blind safe)") }
            ]
            onActivated: index => page.cfg_themeRamp = page.rampKeys[index]
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Colours for quiet → building → hot. Burnt (dead) is a crossed-out blue outline in every one.")
        }
        // What the colours mean, with the numbers set below.
        QQC2.Label {
            Kirigami.FormData.label: ""
            text: Themes.legend(page.tuned, page.cfg_themeRamp || "heat")
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            opacity: 0.75
            font: Kirigami.Theme.smallFont
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Icons") }

        ColumnLayout {
            Kirigami.FormData.label: i18n("Sector icons:")
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: page.sectorRows
                delegate: iconRow
            }
        }
        ColumnLayout {
            Kirigami.FormData.label: i18n("Crypto sector icons:")
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: page.cryptoRows
                delegate: iconRow
            }
        }
        QQC2.Label {
            Kirigami.FormData.label: ""
            text: i18n("Any icon from the icon theme, or Browse for a file: SVG stays sharp at this size, PNG works if it is simple and square. Single-colour icons (the -symbolic ones, Font Awesome, Material, Tabler) are tinted by the heat like the built-in glyphs; tick \"Keep its colours\" for a full-colour one. A custom icon is faded when quiet rather than drawn as an outline, and crossed out when burnt.")
            wrapMode: Text.WordWrap
            opacity: 0.75
            font: Kirigami.Theme.smallFont
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }
        // A ticker Finviz files in the wrong sector, set by hand. Beats
        // Finviz, and is what the history records from then on.
        QQC2.Label {
            Kirigami.FormData.label: ""
            text: i18n("Sector overrides: put a ticker in a different sector from the one Finviz gives it. Applies from now on; the history records your choice.")
            wrapMode: Text.WordWrap
            opacity: 0.75
            font: Kirigami.Theme.smallFont
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }
        ColumnLayout {
            Kirigami.FormData.label: i18n("Sector overrides:")
            spacing: Kirigami.Units.smallSpacing
            Repeater {
                model: Object.keys(page.overrides).sort()
                RowLayout {
                    id: orow
                    required property string modelData
                    QQC2.Label {
                        text: orow.modelData
                        textFormat: Text.PlainText
                        font.bold: true
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                    }
                    QQC2.ComboBox {
                        model: page.sectorChoices.map(s => s.name)
                        currentIndex: Math.max(0, page.sectorChoices.findIndex(s => s.id === page.overrides[orow.modelData]))
                        onActivated: index => page.setOverride(orow.modelData, page.sectorChoices[index].id)
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18n("The sector this ticker goes in")
                    }
                    QQC2.ToolButton {
                        icon.name: "edit-delete"
                        onClicked: page.setOverride(orow.modelData, "")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.text: i18n("Back to Finviz's sector")
                    }
                }
            }
            RowLayout {
                QQC2.TextField {
                    id: overrideTicker
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                    placeholderText: i18n("Ticker")
                    validator: RegularExpressionValidator { regularExpression: /[A-Za-z][A-Za-z0-9.\-]{0,9}/ }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("A ticker Finviz puts in the wrong sector")
                }
                QQC2.ComboBox {
                    id: overrideSector
                    model: page.sectorChoices.map(s => s.name)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("The sector it should be in")
                }
                QQC2.Button {
                    icon.name: "list-add"
                    text: i18n("Set")
                    enabled: overrideTicker.text.trim() !== ""
                    onClicked: {
                        page.setOverride(overrideTicker.text.trim().toUpperCase(), page.sectorChoices[overrideSector.currentIndex].id)
                        overrideTicker.text = ""
                    }
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Put this ticker in the chosen sector")
                }
            }
        }
        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Your sectors") }
        QQC2.Label {
            Kirigami.FormData.label: ""
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.WordWrap
            text: i18n("What a company is, in your own words: a sector of Finviz industries (every company in them joins) and tickers you add by hand. Its stocks show its icon instead of Finviz's sector, and it heats up like one. Past days are re-tagged when you change it.")
            font: Kirigami.Theme.smallFont
            opacity: 0.75
        }
        ColumnLayout {
            readonly property string kind: "sector"
            Kirigami.FormData.label: i18n("Sectors:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.largeSpacing
            Repeater { model: page.mySectors.length; delegate: groupEditor }
            QQC2.Button {
                icon.name: "list-add"
                text: i18n("Add a sector")
                onClicked: page.addSector()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Add an empty sector to fill in")
            }
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Your themes") }
        QQC2.Label {
            Kirigami.FormData.label: ""
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.WordWrap
            text: i18n("A theme is a pattern among the runners: headline words (AI, drones), an industry (oil and gas), traits (no news; foreign with a small float), or a mix. Words or industries say what it is about; traits must all hold. A stock joins every theme it fits, or one you pin it to, and stays on a headline's theme for a while after (below). Its row shows the hottest. The ones here to start with are examples: change, switch off or delete them.")
            font: Kirigami.Theme.smallFont
            opacity: 0.75
        }
        ColumnLayout {
            readonly property string kind: "theme"
            Kirigami.FormData.label: i18n("Themes:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 28
            spacing: Kirigami.Units.largeSpacing
            Repeater { model: page.myThemes.length; delegate: groupEditor }
            QQC2.Label {
                visible: page.myThemes.length === 0
                text: i18n("No themes: add one, or go back to the starter set.")
                opacity: 0.6
            }
            RowLayout {
                QQC2.Button {
                    icon.name: "list-add"
                    text: i18n("Add a theme")
                    onClicked: page.addTheme()
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Add an empty theme to fill in")
                }
                QQC2.Button {
                    icon.name: "edit-reset"
                    text: i18n("Back to the starter themes")
                    onClicked: page.commitThemes(JSON.parse(JSON.stringify(Themes.starterThemes)))
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: i18n("Replaces your themes with the starter set (Cancel undoes it before Apply)")
                }
            }
        }
        QQC2.SpinBox {
            id: sticky
            Kirigami.FormData.label: i18n("Stays on a theme for:")
            from: 0; to: 60
            editable: true
            value: page.cfg_themeStickySessions
            textFromValue: (v, locale) => i18np("%1 session after its headline", "%1 sessions after its headline", v)
            valueFromText: text => parseInt(text)
            onValueModified: page.cfg_themeStickySessions = value
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Once a headline puts a stock on a theme, it stays on it for this many sessions, so its follow-up news need not repeat the words. Another theme's words move it. 0 = only while the headline matches. Default 10.")
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("What counts as a theme") }

        QQC2.SpinBox {
            id: ranPct
            Kirigami.FormData.label: i18n("A runner is up:")
            from: 5; to: 300; stepSize: 5
            editable: true
            textFromValue: (v, locale) => i18n("+%1% on the day", v)
            valueFromText: text => parseInt(String(text).replace(/^\+/, ""))
            onValueChanged: page.pushTuning()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("A stock with news counts as a runner if it was up this much at any point in the day, premarket included. Default +30%.")
        }
        QQC2.SpinBox {
            id: noNewsPct
            Kirigami.FormData.label: i18n("…with no news:")
            from: 5; to: 500; stepSize: 5
            editable: true
            textFromValue: (v, locale) => i18n("+%1% on the day", v)
            valueFromText: text => parseInt(String(text).replace(/^\+/, ""))
            onValueChanged: page.pushTuning()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("A stock with no headline in the last 24 hours needs this much, since +30% on nothing is ordinary for a small cap. Default +60%.")
        }
        QQC2.SpinBox {
            id: runRvol
            Kirigami.FormData.label: i18n("…on volume of:")
            from: 0; to: 50
            editable: true
            textFromValue: (v, locale) => v ? i18n("%1× usual or more", v) : i18n("any volume")
            valueFromText: text => parseInt(text) || 0
            onValueChanged: page.pushTuning()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Its best relative volume on the day must reach this; a move on thin volume does not count. Before the open a stock's relative volume is often not known yet, and then it is not held against it. Default 5×.")
        }
        QQC2.SpinBox {
            id: hotDays
            Kirigami.FormData.label: i18n("Hot when runners on:")
            from: 1; to: hotWindow.value
            editable: true
            textFromValue: (v, locale) => i18np("%1 session", "%1 sessions", v)
            valueFromText: text => parseInt(text)
            onValueChanged: page.pushTuning()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("A theme is hot once its stocks have run on this many of the last sessions (next). Default 3.")
        }
        QQC2.SpinBox {
            id: hotWindow
            Kirigami.FormData.label: i18n("…of the last:")
            from: 1; to: 30
            editable: true
            textFromValue: (v, locale) => i18np("%1 session", "%1 sessions", v)
            valueFromText: text => parseInt(text)
            onValueChanged: page.pushTuning()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("The sessions a theme's record is read over. Default 5, a week.")
        }
        QQC2.SpinBox {
            id: stayDays
            Kirigami.FormData.label: i18n("Stays hot on:")
            from: 1; to: hotDays.value
            editable: true
            textFromValue: (v, locale) => i18np("%1 session with runners", "%1 sessions with runners", v)
            valueFromText: text => parseInt(text)
            onValueChanged: page.pushTuning()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Once hot, a theme stays hot while its stocks run on this many of the last sessions: a theme that lasts weeks has quiet days. Default 1.")
        }
        QQC2.SpinBox {
            id: lift
            Kirigami.FormData.label: i18n("…and beats its usual by:")
            from: 10; to: 100; stepSize: 5
            editable: true
            textFromValue: (v, locale) => i18n("%1×", (v / 10).toFixed(1))
            valueFromText: text => Math.round(parseFloat(text) * 10)
            onValueChanged: page.pushTuning()
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("To go hot, a theme must also have runners more often than it usually does, by this much. This keeps a broad pattern like \"no news\", which has a runner most weeks, from going hot every week. Default 1.5×.")
        }
        QQC2.Label {
            Kirigami.FormData.label: ""
            text: i18n("Building (amber): a runner in the last %1 sessions. A theme's usual rate is only used once it has %2 sessions of history; until then the record alone decides.", hotWindow.value, page.tuned.minHistory)
            wrapMode: Text.WordWrap
            opacity: 0.75
            font: Kirigami.Theme.smallFont
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("When a theme is dead") }

        QQC2.SpinBox {
            id: dead
            Kirigami.FormData.label: i18n("Dead after:")
            from: 1; to: 90
            editable: true
            value: page.cfg_themeDeadDays
            textFromValue: (v, locale) => i18np("%1 day with no runner", "%1 days with no runner", v)
            valueFromText: text => parseInt(text)
            onValueModified: page.cfg_themeDeadDays = value
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("A theme that was hot is burnt (dead) once none of its stocks has run for this many days. Until then it reads quiet, and its tooltip says when it last ran. Default 14.")
        }
        QQC2.Label {
            Kirigami.FormData.label: ""
            text: i18n("Judged on finished sessions only: a session still running can make a theme hotter, never dead.")
            wrapMode: Text.WordWrap
            opacity: 0.75
            font: Kirigami.Theme.smallFont
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
        }
    }
}
