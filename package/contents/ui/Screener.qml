// The Screener tab: one of the engine's three feeds as a table.
//
// A momentum-scanner table:
// time, symbol with a news marker, price, volume, float, both relative
// volumes, gap, change from close, short interest -- plus the screen's
// scorecard, naming the rules a row missed, and a label column. Cells are heat-coloured: the
// smaller the float and the bigger the move, the brighter the cell.
//
// Clicking a row opens the symbol's detail view (chart, figures, news),
// where it can be added to the watchlist.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "scorecards.js" as Scorecards
import "themes.js" as Themes
import "screens.js" as Screens

ColumnLayout {
    id: scr

    required property var engine
    signal open(var entry)

    // The screen shown: the one last picked, or the first if that one has
    // since been deleted.
    readonly property var current: engine.screen(Plasmoid.configuration.screenerView) || engine.screens[0] || null
    readonly property string feed: current ? current.id : ""
    readonly property bool alertFeed: !!current && current.type !== "ranked" && current.type !== "value" && current.type !== "hunter"
    readonly property bool isHunter: !!current && current.type === "hunter"
    readonly property bool isValue: !!current && current.type === "value"
    // The screen's scorecard (Settings → Scorecards), or null for none.
    readonly property var card: current ? engine.scorecard(current.scorecard) : null
    readonly property bool scored: !!card
    readonly property bool compactScore: Plasmoid.configuration.scoreCompact
    readonly property var themeIcons: {
        try { return JSON.parse(Plasmoid.configuration.themeIcons || "{}") } catch (e) { return ({}) }
    }
    // A row's detail view. The screen's scorecard and the row go along, so
    // the detail view can show the row rule by rule.
    function openRow(r) {
        open({ symbol: r.symbol, label: r.symbol, name: r.name || r.symbol, star: false,
               scorecard: current ? current.scorecard : "", currency: r.currency || "USD", row: r })
    }
    // ── right-click on a row ──
    // Make a theme from its headline, pin it to a theme, or set its sector.
    // Writes the same settings Settings → Themes edits; history re-tags itself.
    property var menuRow: null
    readonly property var myThemes: Themes.loadThemes(Plasmoid.configuration)
    readonly property var mySectors: Themes.loadSectors(Plasmoid.configuration)
    function saveThemes(l) { Plasmoid.configuration.customThemes = JSON.stringify(l) }
    function togglePin(themeId, sym) {
        saveThemes(myThemes.map(th => {
            if (th.id !== themeId) return th
            // A pin counts from today on (themes.js, dated pins).
            return Themes.togglePin(th, sym, th.market === "crypto" ? scr.engine.cryptoDay : scr.engine.sessionDay)
        }))
    }
    function setSector(sym, id) {
        let m = {}
        try { m = JSON.parse(Plasmoid.configuration.sectorOverrides || "{}") } catch (e) {}
        if (id) m[sym] = id; else delete m[sym]
        Plasmoid.configuration.sectorOverrides = JSON.stringify(m)
    }
    // A headline's likely key words: the longer ones that are not filler,
    // tickers or numbers. A starting point to edit, not a verdict.
    readonly property var fillerWords: ["announces", "announced", "reports", "reported", "company", "companies", "inc", "corp",
        "corporation", "limited", "holdings", "group", "with", "from", "that", "this", "their", "into", "after", "about",
        "over", "under", "first", "quarter", "results", "update", "provides", "shares", "stock", "today", "agreement",
        "strategic", "pricing", "offering", "million", "billion", "nasdaq", "nyse", "investors", "update", "receives"]
    function keyWords(headline) {
        const seen = {}
        return String(headline || "").toLowerCase().replace(/[^a-z0-9\- ]/g, " ").split(/\s+/)
            .filter(w => w.length >= 5 && !/\d/.test(w) && fillerWords.indexOf(w) < 0 && !seen[w] && (seen[w] = true))
            .sort((a, b) => b.length - a.length).slice(0, 3)
    }
    PlasmaComponents3.Menu {
        id: rowMenu
        PlasmaComponents3.MenuItem {
            enabled: !!scr.menuRow && !!scr.menuRow.newsTitle
            text: i18n("New theme from this headline…")
            onTriggered: newTheme.openFor(scr.menuRow)
        }
        // Separate menus, not nested ones: Plasma's Menu sizes each entry to
        // a parent a nested submenu's entry does not have yet (a TypeError in
        // Menu.qml on every start, 2026-10-24).
        PlasmaComponents3.MenuItem {
            enabled: !!scr.menuRow
            text: scr.menuRow ? i18n("Pin %1 to a theme…", scr.menuRow.symbol) : ""
            onTriggered: pinMenu.popup()
        }
        PlasmaComponents3.MenuItem {
            enabled: !!scr.menuRow
            text: scr.menuRow ? i18n("Set %1's sector…", scr.menuRow.symbol) : ""
            onTriggered: sectorMenu.popup()
        }
    }
    PlasmaComponents3.Menu {
        id: pinMenu
        title: scr.menuRow ? i18n("Pin %1 to a theme", scr.menuRow.symbol) : ""
        Instantiator {
            model: scr.myThemes.filter(th => (th.market || "stocks") === (scr.isCrypto ? "crypto" : "stocks"))
            delegate: PlasmaComponents3.MenuItem {
                required property var modelData
                text: modelData.name
                checkable: true
                checked: !!scr.menuRow && Themes.hasPin(modelData, scr.menuRow.symbol)
                onTriggered: scr.togglePin(modelData.id, scr.menuRow.symbol)
            }
            onObjectAdded: (index, object) => pinMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => pinMenu.removeItem(object)
        }
    }
    PlasmaComponents3.Menu {
        id: sectorMenu
        title: scr.menuRow ? i18n("Set %1's sector", scr.menuRow.symbol) : ""
        PlasmaComponents3.MenuItem {
            text: i18n("As Finviz has it")
            onTriggered: scr.setSector(scr.menuRow.symbol, "")
        }
        Instantiator {
            model: Themes.sectorCatalog.map(s => ({ id: s.id, name: s.name }))
                   .concat(scr.mySectors.map(s => ({ id: s.id, name: s.name + " " + i18n("(yours)") })))
            delegate: PlasmaComponents3.MenuItem {
                required property var modelData
                text: modelData.name
                checkable: true
                checked: !!scr.menuRow && !!scr.menuRow.sector && scr.menuRow.sector.id === modelData.id
                onTriggered: scr.setSector(scr.menuRow.symbol, modelData.id)
            }
            onObjectAdded: (index, object) => sectorMenu.insertItem(index + 1, object)
            onObjectRemoved: (index, object) => sectorMenu.removeItem(object)
        }
    }

    // The new-theme form: name, the headline words to watch for (pre-filled,
    // to edit), an icon. The ticker is pinned to it too.
    PlasmaComponents3.Popup {
        id: newTheme
        property var row: null
        x: Math.round((scr.width - width) / 2)
        y: Kirigami.Units.gridUnit * 3
        width: Math.min(scr.width - Kirigami.Units.gridUnit * 2, Kirigami.Units.gridUnit * 24)
        modal: true
        focus: true
        function openFor(r) {
            row = r
            ntName.text = ""
            ntWords.text = scr.keyWords(r.newsTitle).join(", ")
            ntGlyph.currentIndex = Math.max(0, Themes.glyphNames.indexOf("dot"))
            open()
            ntName.forceActiveFocus()
        }
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.8
                textFormat: Text.PlainText
                text: newTheme.row ? newTheme.row.symbol + ": " + newTheme.row.newsTitle : ""
            }
            PlasmaComponents3.TextField {
                id: ntName
                Layout.fillWidth: true
                placeholderText: i18n("Theme name, e.g. Crypto treasury")
            }
            PlasmaComponents3.TextField {
                id: ntWords
                Layout.fillWidth: true
                placeholderText: i18n("Headline words, comma-separated")
            }
            RowLayout {
                PlasmaComponents3.Label { text: i18n("Icon:") }
                PlasmaComponents3.ComboBox { id: ntGlyph; model: Themes.glyphNames; implicitWidth: Kirigami.Units.gridUnit * 7; implicitHeight: ntName.implicitHeight }
                ThemeGlyph {
                    theme: ({ id: "preview", glyph: Themes.glyphNames[ntGlyph.currentIndex] })
                    status: "hot"
                    ramp: Plasmoid.configuration.themeRamp
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents3.Button { text: i18n("Cancel"); onClicked: newTheme.close() }
                PlasmaComponents3.Button {
                    text: i18n("Create")
                    enabled: ntName.text.trim() !== "" && ntWords.text.trim() !== ""
                    onClicked: {
                        const words = ntWords.text.split(",").map(w => w.trim()).filter(w => w)
                        scr.saveThemes(scr.myThemes.concat([{
                            id: "t-" + ntName.text.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-") + "-" + Date.now().toString(36),
                            name: ntName.text.trim(), glyph: Themes.glyphNames[ntGlyph.currentIndex], words: words,
                            tickers: [{ symbol: newTheme.row.symbol,
                                        from: newTheme.row.market === "crypto" ? scr.engine.cryptoDay : scr.engine.sessionDay }],
                            market: newTheme.row.market === "crypto" ? "crypto" : "stocks",
                            ramp: "", on: true }]))
                        newTheme.close()
                    }
                }
            }
        }
    }
    // Over a theme glyph, its tooltip shows instead of the row's.
    property bool themeHover: false
    // The rows, rebuilt at most once a second and only while this tab is on
    // screen. Facts arrive a hundred times a minute; rebuilding the table on
    // each one, hidden or not, cost plasmashell hundreds of megabytes.
    property var rows: []
    // The table's model. Updated in place while the rows keep their order: a new
    // model redraws the table from its top, which showed as a twitch every second.
    ListModel { id: rowsModel }
    function syncRows() {
        const same = rowsModel.count === rows.length
                     && rows.every((r, i) => rowsModel.get(i).modelData.symbol === r.symbol)
        if (same) rows.forEach((r, i) => rowsModel.set(i, { modelData: r }))
        else { rowsModel.clear(); rows.forEach(r => rowsModel.append({ modelData: r })) }
    }
    // Sectors for the rows on screen: only alert-screen stocks get the full
    // facts look-up, so a ranked or value list asks for the rest here (the
    // engine queues them, 15 at a time, at most hourly each).
    Timer {
        interval: 20000; repeat: true; triggeredOnStart: true
        running: scr.visible && Plasmoid.configuration.sectorsOn && scr.columns.some(c => c.key === "theme")
        onTriggered: scr.engine.lookupGroups(scr.rows.map(r => r.symbol).filter(s => !(scr.engine.info[s] || {}).sector), true)
    }
    function refreshRows() {
        if (!visible) return
        const list = engine.rows(feed)
        if (showsValue) engine.wantValue(list.filter(r => !engine.valueData[r.symbol]).slice(0, 60).map(r => r.symbol))
        rows = sorted(list)
        syncRows()
    }
    Timer { id: rowsSoon; interval: 1000; onTriggered: scr.refreshRows() }
    Connections {
        target: scr.engine
        function onFeedsChanged() { rowsSoon.start() }
        function onRankedChanged() { rowsSoon.start() }
        function onInfoChanged() { rowsSoon.start() }
        function onValueDataChanged() { rowsSoon.start() }
    }
    onFeedChanged: refreshRows()
    onSortSpecChanged: refreshRows()
    // The screen's own settings changed (its Score ≥, say): show it now.
    onCurrentChanged: refreshRows()
    onShowsValueChanged: refreshRows()

    // ── sorting ──────────────────────────────────────────────────────────
    // Click a heading to sort by it, again to reverse, a third time to go
    // back to the screen's own order. Kept per screen in `screenerSort`
    // ({screen id: {key, asc}}).
    readonly property var sortAll: {
        try { return JSON.parse(Plasmoid.configuration.screenerSort || "{}") } catch (e) { return {} }
    }
    readonly property var sortSpec: sortAll[feed] || null
    function sortBy(key) {
        const all = Object.assign({}, sortAll)
        const cur = all[feed]
        // Names read A→Z first; numbers biggest first.
        const textual = key === "symbol" || key === "tags" || key === "missed"
        if (!cur || cur.key !== key) all[feed] = { key: key, asc: textual }
        else if (cur.asc === textual) all[feed] = { key: key, asc: !textual }
        else delete all[feed]
        Plasmoid.configuration.screenerSort = JSON.stringify(all)
    }
    function sortValue(r, key) {
        switch (key) {
        case "time":     return r.time
        case "symbol":   return r.symbol
        case "tags":     return r.tags || ""
        case "missed":   return (r.failed || []).length
        case "short":    return has(r.shortShares) ? r.shortShares : r.shortFloat
        case "dilution": return r.dilution ? ["LOW", "MEDIUM", "HIGH", "EXTREME"].indexOf(r.dilution.risk) : NaN
        // Hottest first, then the bigger cluster; none last.
        // One column: the theme when there is one, else the sector -- hottest first either way.
        case "theme":    return r.theme ? r.themeStatus * 1000 + (r.themeMembers || 0)
                              : r.sector ? r.sectorStatus * 1000 + (r.sectorMembers || 0) : -1
        }
        return r[key]
    }
    function sorted(list) {
        const s = sortSpec
        if (!s) return list
        const dir = s.asc ? 1 : -1
        return list.slice().sort((a, b) => {
            const x = sortValue(a, s.key), y = sortValue(b, s.key)
            // Rows without the figure go last whichever way it runs.
            const xs = typeof x === "string", okx = xs || has(x), oky = typeof y === "string" || has(y)
            if (!okx || !oky) return okx ? -1 : oky ? 1 : 0
            return xs ? dir * String(x).localeCompare(String(y)) : dir * (x - y)
        })
    }
    // The toolbar's "Score ≥": the screen's scoreMin filter, set in place.
    function setScoreMin(n) {
        const list = engine.screens.map(s => s.id !== feed ? s : Object.assign({}, s, {
            filters: Object.assign({}, s.filters, { scoreMin: n > 0 ? n : undefined }) }))
        for (const s of list) if (s.filters && s.filters.scoreMin === undefined) delete s.filters.scoreMin
        Plasmoid.configuration.screens = JSON.stringify(list)
    }
    onVisibleChanged: refreshRows()
    Component.onCompleted: refreshRows()
    spacing: 0

    // ── screen picker, then status and tools ─────────────────────────────
    // Two rows: the screen buttons wrap at any pop-up width, and the tools
    // (Score ≥, Columns, reset, mute) get a row of their own -- on one row
    // they ran off the edge of a narrow pop-up.
    // The tools row and the footer legend can be folded away (▴ / ▾ at the
    // end of the screen buttons) to keep the pane clean; remembered in
    // `screenerTools`.
    readonly property bool tools: Plasmoid.configuration.screenerTools
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: 0
        Flow {
            Layout.fillWidth: true
            spacing: 0
            // One button per screen, in the order set in Settings → Screeners.
            Repeater {
                model: scr.engine.screens
                PlasmaComponents3.ToolButton {
                    required property var modelData
                    text: modelData.name
                    checkable: true
                    checked: scr.feed === modelData.id
                    onClicked: Plasmoid.configuration.screenerView = modelData.id
                }
            }
        }
        PlasmaComponents3.ToolButton {
            Layout.alignment: Qt.AlignTop
            icon.name: scr.tools ? "arrow-up" : "arrow-down"
            onClicked: Plasmoid.configuration.screenerTools = !scr.tools
            PlasmaComponents3.ToolTip { text: scr.tools ? i18n("Hide the tools and legend") : i18n("Show the tools: Score ≥, Columns, reset, sound") }
        }
    }
    RowLayout {
        visible: scr.tools && !scr.isHunter
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            textFormat: Text.PlainText
            text: scr.isValue
                ? (scr.engine.valueUniverse.length
                   ? i18n("Fundamentals: %1 of %2 companies checked today", scr.engine.valueDone, scr.engine.valueUniverse.length)
                   : i18n("Finding companies…"))
                : scr.alertFeed
                ? i18n("%1 watched · %2", scr.engine.candidates.length, scr.engine.source || i18n("waiting"))
                : i18n(scr.current.rankLow ? "Bottom %1 by %2 · %3 watched" : "Top %1 by %2 · %3 watched", scr.current.rankCount || 25,
                       ({ change: i18n("change %"), gap: i18n("gap %"), volume: i18n("volume"),
                          rvol: i18n("day RVOL"), rvol5: i18n("5-min RVOL") })[scr.current.rankBy || "change"],
                       scr.engine.candidates.length)
        }
        RowLayout {
            visible: scr.scored
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents3.Label { text: i18n("Score ≥"); opacity: 0.8 }
            PlasmaComponents3.SpinBox {
                from: 0
                to: scr.card ? scr.card.rules.length : 0
                value: scr.current && scr.current.filters && scr.current.filters.scoreMin ? scr.current.filters.scoreMin : 0
                onValueModified: scr.setScoreMin(value)
                PlasmaComponents3.ToolTip { text: i18n("Show only rows passing at least this many of the scorecard's rules (0 shows all)") }
            }
        }
        // Which columns this screen shows.
        PlasmaComponents3.ToolButton {
            id: columnsButton
            icon.name: "view-list-details"
            text: i18n("Columns")
            onClicked: columnsMenu.popup(columnsButton, 0, columnsButton.height)
            PlasmaComponents3.ToolTip { text: i18n("Choose this screen's columns") }
        }
        PlasmaComponents3.Menu {
            id: columnsMenu
            // Items are added through an Instantiator: a menu's items cannot
            // come from a Repeater.
            Instantiator {
                model: scr.allColumns.filter(c => scr.possible(c))
                delegate: PlasmaComponents3.MenuItem {
                    required property var modelData
                    text: (modelData.title || i18n("Label")).replace(/\n/g, " ")
                          + (modelData.on === "value" ? "  · " + i18n("value") : modelData.on === "momentum" ? "  · " + i18n("momentum") : "")
                    checkable: true
                    checked: scr.isShown(modelData)
                    onTriggered: scr.toggleColumn(modelData.key, checked)
                }
                onObjectAdded: (index, object) => columnsMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => columnsMenu.removeItem(object)
            }
            PlasmaComponents3.MenuSeparator { visible: scr.scored }
            // Every screen: the score as its coloured count alone. The dots
            // say which rules passed; the Missed column says the same in words.
            PlasmaComponents3.MenuItem {
                visible: scr.scored
                text: i18n("Compact score (number only)")
                checkable: true
                checked: Plasmoid.configuration.scoreCompact
                onTriggered: Plasmoid.configuration.scoreCompact = checked
            }
        }
        PlasmaComponents3.ToolButton {
            visible: !!scr.layoutAll[scr.feed]
            icon.name: "view-restore"
            onClicked: {
                const all = Object.assign({}, scr.layoutAll)
                delete all[scr.feed]
                Plasmoid.configuration.screenerLayout = JSON.stringify(all)
            }
            PlasmaComponents3.ToolTip { text: i18n("Reset this screen's columns to their defaults") }
        }
        PlasmaComponents3.ToolButton {
            visible: scr.alertFeed
            icon.name: Plasmoid.configuration.alertSound ? "audio-volume-high" : "audio-volume-muted"
            onClicked: Plasmoid.configuration.alertSound = !Plasmoid.configuration.alertSound
            PlasmaComponents3.ToolTip {
                text: Plasmoid.configuration.alertSound ? i18n("Alert sound on: click to mute")
                                                        : i18n("Muted: click to turn the alert sound on")
            }
        }
    }

    // ── columns ──────────────────────────────────────────────────────────
    // key, heading, width in grid units. Time only on the alert feeds.
    // Every column, in the default order; `w` is the default width in grid
    // units. Time and the label column only exist on the alert feeds.
    // `on`: which screens show it -- "momentum" (alert and ranked screens),
    // "value" (long-term value lists), or both when absent.
    readonly property var allColumns: [
        { key: "time",    title: Plasmoid.configuration.timesLocal ? i18n("Time") : i18n("Time (ET)"), w: 6.4, alert: true },
        { key: "symbol",  title: i18n("Symbol"),         w: 4.6 },
        { key: "theme",   title: i18n("Theme\nbeta"),    w: 2.8 },
        { key: "score",   title: i18n("Score"),          w: 4.4 },
        { key: "price",   title: i18n("Price"),          w: 4.2 },
        { key: "volume",  title: i18n("Volume"),         w: 4.6, on: "momentum" },
        { key: "float",   title: i18n("Float"),          w: 4.2, on: "momentum" },
        { key: "rvol",    title: i18n("RVOL\nday"),      w: 3.4, on: "momentum" },
        { key: "rvol5",   title: i18n("RVOL\n5 min %"),  w: 4.4, on: "momentum" },
        { key: "gap",     title: i18n("Gap\n%"),         w: 3.2, on: "momentum" },
        { key: "change",  title: i18n("Change\n%"),      w: 3.4 },
        { key: "short",   title: i18n("Short\ninterest"), w: 4.2, on: "momentum" },
        { key: "marketCap", title: i18n("Market\ncap"),  w: 4.4, on: "value" },
        { key: "pe5",     title: i18n("5-yr\nP/E"),      w: 3.6, on: "value" },
        { key: "pfcf",    title: i18n("Price\n/ FCF"),   w: 3.6, on: "value" },
        { key: "roic",    title: i18n("ROIC\n%"),        w: 3.4, on: "value" },
        { key: "vs50",    title: i18n("vs 50-day\n%"),   w: 4.2, on: "value" },
        { key: "trend",   title: i18n("50 vs 200\n%"),   w: 4.2, on: "value" },
        { key: "maSlope", title: i18n("50-day\nslope %"), w: 4.2, on: "value" },
        { key: "offHigh", title: i18n("Under 52w\nhigh %"), w: 4.4, on: "value" },
        { key: "off52",   title: i18n("Off 52w\nlow %"), w: 4.2, on: "value" },
        { key: "dilution", title: i18n("Dilution"),      w: 5.0 },
        { key: "missed",  title: i18n("Missed"),         w: 7.5 },
        { key: "tags",    title: "",                     w: 6.5, alert: true }
    ]

    // Each screen's own layout -- which columns, their order and widths --
    // saved as JSON {screen id: {shown: [keys], order: [keys], widths: {key:
    // grid units}}} in the `screenerLayout` setting. Without `shown` a
    // screen shows its type's default set: momentum columns on alert and
    // ranked screens, value columns on value lists. `seen` lists every column
    // that existed when the layout was saved: a column added since is shown
    // by its default and placed after its neighbour in the default order,
    // not hidden because an older `shown` list never named it.
    readonly property var layoutAll: {
        try { return JSON.parse(Plasmoid.configuration.screenerLayout || "{}") } catch (e) { return {} }
    }
    readonly property var layout: layoutAll[feed] || ({})
    // A column this screen can show at all: Time and the label belong to
    // alert screens, Score and Missed need a scorecard.
    // Crypto has no float, short interest, gap, 5-minute volume or
    // filings, so those columns are not offered on a crypto screen.
    readonly property bool isCrypto: Screens.isCrypto(current)
    readonly property var stockColumns: ["float", "rvol5", "gap", "short", "dilution", "pe5", "pfcf", "roic", "vs50", "trend", "maSlope", "offHigh", "off52"]
    function possible(c) {
        return (!c.alert || alertFeed) && ((c.key !== "score" && c.key !== "missed") || scored)
            && (c.key !== "theme" || Plasmoid.configuration.themesOn || Plasmoid.configuration.sectorsOn)
            && !(isCrypto && stockColumns.indexOf(c.key) >= 0)
    }
    function defaultShown(c) { return isCrypto && c.key === "marketCap" ? true : !c.on || c.on === (isValue ? "value" : "momentum") }
    // Layouts saved before `seen` existed (before 2026-10-24) knew every
    // column except these.
    // Their saved place is ignored too: an older Columns menu appended a
    // newly ticked column at the far end, past the horizontal scroll.
    readonly property var addedLater: ["theme"]
    function seenBy(key) { return layout.seen ? layout.seen.indexOf(key) >= 0 : addedLater.indexOf(key) < 0 }
    function isShown(c) {
        if (!layout.shown || !seenBy(c.key)) return defaultShown(c)
        return layout.shown.indexOf(c.key) >= 0
    }
    readonly property var columns: {
        const order = (layout.order || []).filter(k => layout.seen || addedLater.indexOf(k) < 0)
        const widths = layout.widths || {}
        const known = allColumns.filter(c => order.indexOf(c.key) >= 0)
                                .sort((a, b) => order.indexOf(a.key) - order.indexOf(b.key))
        // A column the order does not name goes after its neighbour in the
        // default order (Sector after Symbol), else at the end.
        const all = known.slice()
        allColumns.forEach((c, i) => {
            if (order.indexOf(c.key) >= 0) return
            let at = -1
            for (let j = i - 1; j >= 0 && at < 0; j--) at = all.findIndex(x => x.key === allColumns[j].key)
            if (at >= 0 && order.length) all.splice(at + 1, 0, c)
            else all.push(c)
        })
        return all
            .filter(c => possible(c) && isShown(c))
            // The score column fits its scorecard's dots unless resized by hand;
            // compact, it fits the number alone, whatever its width with dots.
            .map(c => Object.assign({}, c, { w: Math.max(minWidth(c), c.key === "score" && compactScore ? 2.6
                : widths[c.key] > 0 ? widths[c.key]
                : c.key === "score" && card ? Math.max(c.w, 2.6 + card.rules.length * 0.5) : c.w) }))
    }
    // ── minimum column widths ──
    // A column never narrower than its heading and its usual figure, so
    // numbers and headings do not elide ("910....", "Sym...") however the
    // widths were saved. Measured in the fonts the table draws with, so it
    // holds at any font size. In grid units, like the widths.
    // (The fonts are read here, on the table: Kirigami.Theme inside a
    // FontMetrics, which is not an Item, gives other sizes.)
    readonly property real headPad: 2
    readonly property real cellPoints: Kirigami.Theme.smallFont.pointSize
    readonly property string monoFamily: Kirigami.Theme.fixedWidthFont.family
    readonly property string textFamily: Kirigami.Theme.defaultFont.family
    FontMetrics { id: cellFm; font.family: scr.monoFamily; font.pointSize: scr.cellPoints }
    FontMetrics { id: symFm; font.family: scr.monoFamily; font.pointSize: scr.cellPoints; font.bold: true }
    FontMetrics { id: headFm; font.family: scr.textFamily; font.pointSize: scr.cellPoints; font.bold: true }
    // The widest figure a column usually holds; tags and missed wrap or elide.
    readonly property var sampleText: ({
        time: "00:00:00 pm", price: "00000.00", volume: "000.00M", float: "000.00M", rvol: "000.00",
        rvol5: "00,000", gap: "-000.00", change: "-000.00", short: "000.00M", marketCap: "000.00B",
        pe5: "-000.0", pfcf: "-000.0", roic: "-000.0", vs50: "-000.00", trend: "-000.00", maSlope: "-000.00",
        offHigh: "-000.00", off52: "000.00", dilution: "EXTREME"
    })
    function minWidth(c) {
        // Read the metrics' heights so a binding calling this re-runs when
        // the fonts change (advanceWidth() alone is not tracked).
        if (!(cellFm.height + symFm.height + headFm.height > 0)) return 1.5
        const pad = Kirigami.Units.smallSpacing * 2
        const sorted = sortSpec && sortSpec.key === c.key ? " ▼" : ""
        const head = Math.max(...String(c.title || "").split("\n").map(l => headFm.advanceWidth(l)))
                     + headFm.advanceWidth(sorted) + headPad * 2 + 6
        let body = 0
        if (c.key === "symbol") body = symFm.advanceWidth("XXXXX") + Kirigami.Units.iconSizes.small + pad
        else if (c.key === "score") body = Kirigami.Units.gridUnit * 1.6 + pad
        else if (c.key === "theme") body = Kirigami.Units.iconSizes.small + pad
        else if (sampleText[c.key]) body = cellFm.advanceWidth(sampleText[c.key]) + pad
        return Math.max(1.5, head, body) / Kirigami.Units.gridUnit
    }
    // Shows or hides one column on this screen (the Columns menu).
    function toggleColumn(key, on) {
        const shown = allColumns.filter(c => possible(c) && isShown(c)).map(c => c.key).filter(k => k !== key)
        if (on) shown.push(key)
        saveThis({ shown: shown })
    }
    // Value columns need the company's fundamentals; ask for them.
    readonly property bool showsValue: columns.some(c => c.on === "value")
    function saveThis(changes) {
        const all = Object.assign({}, layoutAll)
        all[feed] = Object.assign({}, layout, changes, { seen: allColumns.map(c => c.key) })
        Plasmoid.configuration.screenerLayout = JSON.stringify(all)
    }
    function saveLayout(order, widths) { saveThis({ order: order, widths: widths }) }
    // Moves a column; `from` and `to` index the columns shown. Hidden ones
    // (Time and the label on Top Gainers) keep their place in the full order.
    function moveColumn(from, to) {
        if (from === to) return
        const shown = columns.map(c => c.key)
        const key = shown[from]
        const full = (layout.order && layout.order.length ? layout.order.slice() : allColumns.map(c => c.key))
        for (const c of allColumns) if (full.indexOf(c.key) < 0) full.push(c.key)
        full.splice(full.indexOf(key), 1)
        const before = shown.filter(k => k !== key)[to]      // the column it lands in front of
        const at = before === undefined ? full.length : full.indexOf(before)
        full.splice(at, 0, key)
        saveLayout(full, layout.widths || {})
    }
    function resizeColumn(key, units) {
        const widths = Object.assign({}, layout.widths || {})
        widths[key] = Math.max(1.5, Math.round(units * 10) / 10)
        saveLayout(layout.order || allColumns.map(c => c.key), widths)
    }

    // A price at the precision it needs: a coin at $0.000012, or priced in
    // bitcoin, is not "0.00". The currency's sign leads when it is not the
    // dollar, so a converted screen cannot be misread.
    function fmtPrice(v) {
        const a = Math.abs(v)
        // Never exponent notation: four significant digits as plain decimals.
        return a >= 1 ? v.toFixed(2) : a >= 0.01 ? v.toFixed(4)
             : a > 0 ? v.toFixed(Math.min(14, 3 - Math.floor(Math.log10(a)))) : "0"
    }
    function money(r, v) { return (r.currency && r.currency !== "USD" ? r.currencySym : "") + fmtPrice(v) }
    function big(v) {
        if (!(v > 0)) return "—"
        if (v >= 1e9) return (v / 1e9).toFixed(2) + "B"
        if (v >= 1e6) return (v / 1e6).toFixed(2) + "M"
        if (v >= 1e3) return (v / 1e3).toFixed(2) + "K"
        return Math.round(v).toString()
    }
    // "Dilution HIGH: S-3 filed 2026-10-13 · last offering 424B3 2026-08-27"
    function dilutionText(d) {
        if (!d || d.risk === "UNKNOWN") return ""
        const sh = d.shelves && d.shelves[0], of = d.offerings && d.offerings[0]
        return i18n("Dilution %1", d.risk)
             + (sh ? ": " + i18n("%1 filed %2", sh.form, sh.date) : "")
             + (of ? " · " + i18n("last offering %1 %2", of.form, of.date) : "")
             + (d.flags && d.flags.length ? " (" + d.flags.join("; ") + ")" : "")
    }
    // A figure that is really there. Alerts come back from the database as
    // JSON, where a missing figure (NaN) was saved as null -- and the global
    // isFinite(null) is true, which showed missing figures as 0.
    function has(v) { return typeof v === "number" && Number.isFinite(v) }
    function pct(v) { return has(v) ? v.toFixed(2) : "—" }

    // Alert times in New York time, as the exchange and trading platforms show
    // them ("02:38:31 pm"), whatever the desktop's own time zone. The offset
    // is the engine's, which follows daylight saving from Yahoo.
    // Settings → Screeners can show them in the desktop's own time zone.
    function etTime(ms) {
        const local = Plasmoid.configuration.timesLocal
        const d = local ? new Date(ms) : new Date(ms + engine.etOffset * 1000)
        if (local) d.setTime(ms - d.getTimezoneOffset() * 60000)
        const h = d.getUTCHours(), two = n => String(n).padStart(2, "0")
        return two(h % 12 || 12) + ":" + two(d.getUTCMinutes()) + ":" + two(d.getUTCSeconds())
             + (h < 12 ? " am" : " pm")
    }

    // One dot per rule of the screen's scorecard, in its order, filled
    // where the row passed it.
    function passed(r, rule) {
        return !(r.failed || []).some(f => f === rule.name || f === rule.name + "?")
    }
    // Green when every rule passed, light green one short, amber from 60%,
    // red below.
    function scoreColour(n, total) {
        if (!(total > 0)) return Kirigami.Theme.disabledTextColor
        return n >= total ? Kirigami.Theme.positiveTextColor
             : n >= total - 1 ? Qt.tint(Kirigami.Theme.positiveTextColor, Qt.rgba(1, 1, 0, 0.35))
             : n / total >= 0.6 ? Kirigami.Theme.neutralTextColor
             : Kirigami.Theme.negativeTextColor
    }
    function cell(r, key) {
        switch (key) {
        case "time":
            return etTime(r.time)
                 + (r.count > 1 ? "\n" + i18n("%1 in %2s", r.count, Math.round((r.time - r.first) / 1000)) : "")
        case "symbol": return r.symbol
        case "price":  return has(r.price) ? money(r, r.price) : "—"
        case "volume": return (r.market === "crypto" && has(r.volume) ? (r.currencySym || "$") : "") + big(r.volume)
        case "float":  return big(r.float)
        case "rvol":   return has(r.rvol) ? r.rvol.toFixed(2) : "—"
        case "rvol5":  return has(r.rvol5) ? Math.round(r.rvol5).toLocaleString(Qt.locale(), "f", 0) : "—"
        case "gap":    return pct(r.gap)
        case "change": return pct(r.change)
        case "short":  return r.shortShares > 0 ? big(r.shortShares)
                            : (has(r.shortFloat) ? r.shortFloat.toFixed(1) + "%" : "—")
        case "score":  return ""          // drawn as a badge in the row delegate
        case "missed": return r.failed.length ? r.failed.join(" ") : "—"
        case "tags":   return r.tags || ""
        case "marketCap": return (r.currency && r.currency !== "USD" && has(r.marketCap) ? r.currencySym : "") + big(r.marketCap)
        case "pe5":    return has(r.pe5) ? r.pe5.toFixed(1) : "—"
        case "pfcf":   return has(r.pfcf) ? r.pfcf.toFixed(1) : "—"
        case "roic":   return has(r.roic) ? r.roic.toFixed(1) : "—"
        case "vs50":   return pct(r.vs50)
        case "trend":  return pct(r.trend)
        case "maSlope": return pct(r.maSlope)
        case "off52":  return pct(r.off52)
        case "offHigh": return pct(r.offHigh)
        case "dilution": return r.dilution && r.dilution.risk !== "UNKNOWN" ? r.dilution.risk : "—"
        }
        return ""
    }

    // Heat: a theme colour at an opacity that grows with the reading.
    function heat(r, key) {
        const pos = Kirigami.Theme.positiveTextColor, neg = Kirigami.Theme.negativeTextColor
        const tint = (c, a) => Qt.rgba(c.r, c.g, c.b, Math.max(0, Math.min(0.75, a)))
        switch (key) {
        case "float":
            // Brightest for the tiniest floats.
            if (!(r.float > 0)) return "transparent"
            if (r.float < 2e6)  return tint(Kirigami.Theme.highlightColor, 0.75)
            if (r.float < 10e6) return tint(Kirigami.Theme.highlightColor, 0.45)
            if (r.float < 20e6) return tint(pos, 0.3)
            return "transparent"
        case "gap":
        case "change": {
            const v = key === "gap" ? r.gap : r.change
            if (!has(v) || v === 0) return "transparent"
            return v > 0 ? tint(pos, 0.15 + v / 80) : tint(neg, 0.15 + -v / 20)
        }
        case "rvol":   return has(r.rvol) && r.rvol >= 1 ? tint(pos, Math.log10(r.rvol) / 2.5) : "transparent"
        case "rvol5":  return has(r.rvol5) && r.rvol5 >= 100 ? tint(pos, Math.log10(r.rvol5 / 100) / 3) : "transparent"
        // Long-term value: cheap reads green, recovering trend reads green.
        case "pe5":
        case "pfcf": {
            const v = key === "pe5" ? r.pe5 : r.pfcf
            return has(v) && v > 0 && v < 22.5 ? tint(pos, 0.15 + (22.5 - v) / 40) : "transparent"
        }
        case "vs50":
        case "maSlope": {
            const v = key === "vs50" ? r.vs50 : r.maSlope
            return !has(v) || v === 0 ? "transparent" : v > 0 ? tint(pos, 0.15 + v / 20) : tint(neg, 0.15 + -v / 20)
        }
        case "dilution": {
            const k = r.dilution && r.dilution.risk
            return k === "EXTREME" ? tint(neg, 0.6) : k === "HIGH" ? tint(Kirigami.Theme.neutralTextColor, 0.5)
                 : k === "MEDIUM" ? tint(Kirigami.Theme.neutralTextColor, 0.2) : "transparent"
        }
        }
        return "transparent"
    }

    // The table is usually wider than the pop-up, so it scrolls sideways
    // as a whole -- header and rows together -- by the scrollbar, by
    // Shift + mouse wheel, or by a sideways swipe on a touchpad. Plasma keeps
    // a pop-up at the size it was first shown (or dragged to), so widening it
    // from here does not stick; the scroll is what makes every column
    // reachable.
    readonly property real tableWidth: columns.reduce((a, c) => a + c.w, 0) * Kirigami.Units.gridUnit
                                       + Kirigami.Units.smallSpacing * 2
    HunterView {
        visible: scr.isHunter
        Layout.fillWidth: true
        Layout.fillHeight: true
        engine: scr.engine
        market: scr.current && scr.current.market === "crypto" ? "crypto" : "stocks"
        onOpen: entry => scr.open(entry)
    }
    Item {
        visible: !scr.isHunter
        Layout.fillWidth: true
        Layout.fillHeight: true

        Flickable {
            id: hscroll
            anchors.fill: parent
            contentWidth: Math.max(width, scr.tableWidth)
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            PlasmaComponents3.ScrollBar.horizontal: PlasmaComponents3.ScrollBar {
                id: hbar
                policy: hscroll.contentWidth > hscroll.width ? PlasmaComponents3.ScrollBar.AlwaysOn
                                                             : PlasmaComponents3.ScrollBar.AlwaysOff
            }

            ColumnLayout {
                width: hscroll.contentWidth
                height: hscroll.height - (hbar.visible ? hbar.height : 0)
                spacing: 0

                // Header row. Drag a heading sideways to move its column (a
                // bar marks where it will land); drag a heading's right edge
                // to resize it. Both are saved.
                Item {
                    id: header
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    implicitWidth: headRow.width
                    implicitHeight: Kirigami.Units.gridUnit * 2.6
                    property int dragFrom: -1
                    property int dropAt: -1

                    // Where a drop at x (in header coordinates) lands: before
                    // the first column whose middle is right of x.
                    function slotAt(x) {
                        let edge = 0
                        for (let i = 0; i < scr.columns.length; i++) {
                            const w = Kirigami.Units.gridUnit * scr.columns[i].w
                            if (x < edge + w / 2) return i
                            edge += w
                        }
                        return scr.columns.length
                    }
                    function slotX(i) {
                        let edge = 0
                        for (let k = 0; k < i; k++) edge += Kirigami.Units.gridUnit * scr.columns[k].w
                        return edge
                    }

                    Row {
                        id: headRow
                        Repeater {
                            model: scr.columns
                            Item {
                                id: head
                                required property var modelData
                                required property int index
                                // Live width while its edge is dragged.
                                property real liveW: Kirigami.Units.gridUnit * modelData.w
                                width: liveW
                                height: header.height
                                onModelDataChanged: liveW = Kirigami.Units.gridUnit * modelData.w

                                Rectangle {
                                    anchors.fill: parent
                                    color: Kirigami.Theme.highlightColor
                                    opacity: header.dragFrom === head.index ? 0.25 : (move.containsMouse ? 0.08 : 0)
                                }
                                PlasmaComponents3.Label {
                                    anchors.fill: parent
                                    anchors.leftMargin: scr.headPad
                                    anchors.rightMargin: scr.headPad + 6     // clear of the resize edge
                                    text: head.modelData.title
                                          + (scr.sortSpec && scr.sortSpec.key === head.modelData.key
                                             ? (scr.sortSpec.asc ? " ▲" : " ▼") : "")
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                // Drag to move.
                                MouseArea {
                                    id: move
                                    anchors.fill: parent
                                    anchors.rightMargin: 6
                                    hoverEnabled: true
                                    preventStealing: true
                                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    property real pressX
                                    onPressed: mouse => { header.dragFrom = head.index; pressX = mouse.x }
                                    onPositionChanged: mouse => {
                                        if (pressed) header.dropAt = header.slotAt(mapToItem(header, mouse.x, 0).x)
                                    }
                                    onReleased: mouse => {
                                        const from = header.dragFrom, to = header.dropAt
                                        header.dragFrom = -1
                                        header.dropAt = -1
                                        // Barely moved: a click, which sorts.
                                        if (Math.abs(mouse.x - pressX) < 5) { scr.sortBy(head.modelData.key); return }
                                        if (to >= 0 && to !== from && to !== from + 1)
                                            scr.moveColumn(from, to > from ? to - 1 : to)
                                    }
                                }
                                // Drag the right edge to resize.
                                MouseArea {
                                    anchors.right: parent.right
                                    width: 6
                                    height: parent.height
                                    preventStealing: true
                                    cursorShape: Qt.SplitHCursor
                                    property real startX
                                    property real startW
                                    onPressed: mouse => { startX = mapToItem(header, mouse.x, 0).x; startW = head.liveW }
                                    onPositionChanged: mouse => {
                                        if (pressed) head.liveW = Math.max(Kirigami.Units.gridUnit * 1.5,
                                                                           startW + mapToItem(header, mouse.x, 0).x - startX)
                                    }
                                    onReleased: scr.resizeColumn(head.modelData.key, head.liveW / Kirigami.Units.gridUnit)
                                    Rectangle {
                                        anchors.right: parent.right
                                        width: 1
                                        height: parent.height * 0.6
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: Kirigami.Theme.disabledTextColor
                                        opacity: 0.5
                                    }
                                }
                            }
                        }
                    }
                    // Where a dragged column will land.
                    Rectangle {
                        visible: header.dragFrom >= 0 && header.dropAt >= 0
                        x: header.slotX(header.dropAt) - 1
                        width: 3
                        height: header.height
                        color: Kirigami.Theme.highlightColor
                    }
                }
                Kirigami.Separator { Layout.fillWidth: true }

                PlasmaComponents3.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

                    ListView {
                        id: table
                        model: rowsModel
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: MouseArea {
                            id: rowItem
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: Kirigami.Units.gridUnit * (modelData.count > 1 ? 2.2 : 1.5)
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            // Right-click: make a theme from the headline, pin the
                            // ticker to one, or set its sector.
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) { scr.menuRow = modelData; rowMenu.popup(); return }
                                scr.openRow(modelData)
                            }

                            Rectangle {
                                anchors.fill: parent
                                color: rowItem.containsMouse ? Kirigami.Theme.hoverColor
                                     : rowItem.index % 2 ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g,
                                                                   Kirigami.Theme.textColor.b, 0.04)
                                     : "transparent"
                                opacity: rowItem.containsMouse ? 0.4 : 1
                            }

                            Row {
                                x: Kirigami.Units.smallSpacing
                                height: parent.height
                                Repeater {
                                    model: scr.columns
                                    // One cell. It loads only what it shows: the score
                                    // badge in the score column, ticker and news marker in
                                    // the symbol column, one text label everywhere else.
                                    // (Every cell once carried a hidden badge and icon as
                                    // well; their size changes kept re-laying the rows
                                    // out, which held plasmashell at 100% CPU.)
                                    Rectangle {
                                        id: cellBox
                                        required property var modelData
                                        readonly property string key: modelData.key
                                        width: Kirigami.Units.gridUnit * modelData.w
                                        height: rowItem.height - 1
                                        color: scr.heat(rowItem.modelData, key)

                                        Loader {
                                            anchors.fill: parent
                                            anchors.leftMargin: Kirigami.Units.smallSpacing
                                            anchors.rightMargin: Kirigami.Units.smallSpacing
                                            sourceComponent: cellBox.key === "score" ? badgeCell
                                                           : cellBox.key === "symbol" ? symbolCell
                                                           : cellBox.key === "theme" ? themeCell
                                                           : textCell
                                        }

                                        Component {
                                            id: textCell
                                            PlasmaComponents3.Label {
                                                textFormat: Text.PlainText
                                                text: scr.cell(rowItem.modelData, cellBox.key)
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                font.family: cellBox.key === "tags" || cellBox.key === "missed"
                                                             ? Kirigami.Theme.defaultFont.family
                                                             : Kirigami.Theme.fixedWidthFont.family
                                                horizontalAlignment: cellBox.key === "tags" || cellBox.key === "missed"
                                                                     ? Text.AlignLeft : Text.AlignRight
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                                maximumLineCount: 2
                                            }
                                        }
                                        // The theme glyph: which story the row belongs
                                        // to, filled and coloured by how hot that story
                                        // is. Fixed size, because a cell that resizes
                                        // itself re-lays out every row (see above).
                                        Component {
                                            id: themeCell
                                            // The theme's glyph when the stock has one, else its sector's.
                                            Item {
                                                readonly property bool isTheme: !!rowItem.modelData.theme
                                                readonly property var th: rowItem.modelData.theme || rowItem.modelData.sector
                                                readonly property var heat: isTheme ? rowItem.modelData.themeHeat : rowItem.modelData.sectorHeat
                                                ThemeGlyph {
                                                    id: glyph
                                                    anchors.centerIn: parent
                                                    theme: parent.th || null
                                                    status: parent.heat ? parent.heat.status : "quiet"
                                                    ramp: Plasmoid.configuration.themeRamp
                                                    icons: scr.themeIcons
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    acceptedButtons: Qt.NoButton
                                                    onContainsMouseChanged: scr.themeHover = containsMouse
                                                    // A row scrolled away under the pointer must not leave it set.
                                                    Component.onDestruction: if (containsMouse) scr.themeHover = false
                                                    PlasmaComponents3.ToolTip {
                                                        visible: parent.containsMouse && !!glyph.visible
                                                        text: rowItem.modelData.theme && rowItem.modelData.themeHeat
                                                              ? i18n("Theme: %1", Themes.explain(rowItem.modelData.theme.name,
                                                                               rowItem.modelData.themeHeat,
                                                                               scr.engine.themeTune))
                                                              : rowItem.modelData.sector && rowItem.modelData.sectorHeat
                                                              ? i18n("Sector (no theme): %1", Themes.explain(rowItem.modelData.sector.name,
                                                                               rowItem.modelData.sectorHeat, scr.engine.themeTune))
                                                                + (rowItem.modelData.sectorBreakdown ? "\n" + i18n("Today: %1", rowItem.modelData.sectorBreakdown) : "")
                                                              : ""
                                                    }
                                                }
                                            }
                                        }
                                        Component {
                                            id: symbolCell
                                            Item {
                                                PlasmaComponents3.Label {
                                                    anchors.left: parent.left
                                                    anchors.right: newsIcon.visible ? newsIcon.left : parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    textFormat: Text.PlainText
                                                    text: rowItem.modelData.symbol
                                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                    font.family: Kirigami.Theme.fixedWidthFont.family
                                                    font.bold: true
                                                    font.underline: true
                                                    elide: Text.ElideRight
                                                }
                                                // News marker: a headline in the last 24 hours,
                                                // coloured by how fresh it is -- red under 1 hour,
                                                // orange under 4, yellow under 24.
                                                Kirigami.Icon {
                                                    id: newsIcon
                                                    readonly property real age: Date.now() - (rowItem.modelData.newsTime || 0)
                                                    visible: !!rowItem.modelData.newsTime && age < 24 * 3600000
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: Kirigami.Units.iconSizes.small
                                                    height: width
                                                    source: "news-subscribe"
                                                    color: age < 3600000 ? "#e8413c" : age < 4 * 3600000 ? "#f39c1f" : "#f4d03f"
                                                    isMask: true
                                                }
                                            }
                                        }
                                        Component {
                                            id: badgeCell
                                            // The count of rules passed, coloured red to amber
                                            // to green, and a dot per rule of the screen's
                                            // scorecard, filled where it passed.
                                            Item {
                                                Rectangle {
                                                    id: badge
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.horizontalCenter: scr.compactScore ? parent.horizontalCenter : undefined
                                                    width: Kirigami.Units.gridUnit * 1.6
                                                    height: Kirigami.Units.gridUnit * 1.05
                                                    radius: height / 2
                                                    color: scr.scoreColour(rowItem.modelData.score, rowItem.modelData.total)
                                                    PlasmaComponents3.Label {
                                                        anchors.centerIn: parent
                                                        text: rowItem.modelData.score
                                                        font.bold: true
                                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                        color: "black"
                                                    }
                                                }
                                                Row {
                                                    visible: !scr.compactScore
                                                    anchors.left: badge.right
                                                    anchors.leftMargin: Kirigami.Units.smallSpacing
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: 2
                                                    Repeater {
                                                        model: scr.card ? scr.card.rules : []
                                                        Rectangle {
                                                            required property var modelData
                                                            readonly property bool ok: scr.passed(rowItem.modelData, modelData)
                                                            width: Kirigami.Units.gridUnit * 0.38
                                                            height: width
                                                            radius: width / 2
                                                            color: ok ? scr.scoreColour(rowItem.modelData.score, rowItem.modelData.total) : "transparent"
                                                            border.width: 1
                                                            border.color: ok ? color : Kirigami.Theme.disabledTextColor
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            PlasmaComponents3.ToolTip {
                                // The newest headline, and what is behind the
                                // dilution rating.
                                readonly property string dil: rowItem.modelData.dilution
                                    ? scr.dilutionText(rowItem.modelData.dilution) : ""
                                visible: rowItem.containsMouse && !scr.themeHover && (rowItem.modelData.newsTitle || dil) !== ""
                                text: [rowItem.modelData.newsTitle || "", dil].filter(t => t).join("\n\n")
                                delay: Kirigami.Units.toolTipDelay
                            }
                        }

                    }
                }
            }
        }

        WheelHandler {
            acceptedModifiers: Qt.ShiftModifier
            onWheel: event => {
                const d = event.angleDelta.y || event.angleDelta.x
                hscroll.contentX = Math.max(0, Math.min(hscroll.contentWidth - hscroll.width,
                                                        hscroll.contentX - d))
            }
        }

        PlasmaComponents3.Label {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 4
            visible: table.count === 0
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: scr.isValue ? i18n("No companies pass yet. The first check of their filings runs in the background and takes a while; companies appear as they qualify.")
                : !scr.alertFeed ? i18n("Filling on the next pass…")
                : scr.isCrypto ? i18n("No alerts in the last 24 hours. Watching %1 Coinbase pairs; the feed fills as they move.",
                                      Object.keys(scr.engine.cproducts).length)
                : scr.engine.currentPhase === "closed" ? i18n("Market closed: alerts resume when trading does")
                : i18n("No alerts yet. Watching %1 symbols; the feed fills as they move.",
                       scr.engine.candidates.length)
        }
    }

    // A scanner problem, shown whether or not the tools are open.
    PlasmaComponents3.Label {
        visible: scr.engine.bridgeError !== ""
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        font: Kirigami.Theme.smallFont
        color: Kirigami.Theme.neutralTextColor
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: scr.engine.bridgeError
    }
    PlasmaComponents3.Label {
        visible: scr.tools
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        font: Kirigami.Theme.smallFont
        opacity: 0.6
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: (scr.scored ? scr.card.name + ": " + scr.card.rules.map(Scorecards.describe).join(" · ") + ". " : "")
              + (scr.isValue ? i18n("Fundamentals from SEC filings, rechecked daily; price and averages live.") : "")
              + (scr.alertFeed && scr.engine.feedsDay && scr.engine.feedsDay !== scr.engine.sessionDay
                 ? i18n(" Last session's alerts (%1); they clear when the next session's first alert fires.",
                        Qt.formatDate(new Date(scr.engine.feedsDay + "T12:00:00"), "ddd d MMM")) : "")
              + (!scr.alertFeed && scr.engine.currentPhase === "closed" ? i18n(" Market closed: prices are the last session's close, refreshed every 15 minutes.") : "")
              + (!scr.alertFeed ? "" : ({
                  pre: i18n("Premarket: volume is the running premarket total; RVOL 5 min is against this premarket's average 5 minutes."),
                  regular: i18n("RVOL 5 min is against an average 5 minutes of the stock's normal day."),
                  post: i18n("After hours: no minute-by-minute volume, so Running Up fires on the price rise alone and RVOL 5 min shows —."),
                  overnight: i18n("Overnight session: volume is not known, so volume filters fall back to change, and change is from the last close.")
              })[scr.engine.currentPhase] || "")
    }
}
