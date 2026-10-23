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

ColumnLayout {
    id: scr

    required property var engine
    signal open(var entry)

    // The screen shown: the one last picked, or the first if that one has
    // since been deleted.
    readonly property var current: engine.screen(Plasmoid.configuration.screenerView) || engine.screens[0] || null
    readonly property string feed: current ? current.id : ""
    readonly property bool alertFeed: !!current && current.type !== "ranked" && current.type !== "value"
    readonly property bool isValue: !!current && current.type === "value"
    // The screen's scorecard (Settings → Scorecards), or null for none.
    readonly property var card: current ? engine.scorecard(current.scorecard) : null
    readonly property bool scored: !!card
    // The rows, rebuilt at most once a second and only while this tab is on
    // screen. Facts arrive a hundred times a minute; rebuilding the table on
    // each one, hidden or not, cost plasmashell hundreds of megabytes.
    property var rows: []
    function refreshRows() {
        if (!visible) return
        const list = engine.rows(feed)
        if (showsValue) engine.wantValue(list.filter(r => !engine.valueData[r.symbol]).slice(0, 60).map(r => r.symbol))
        rows = sorted(list)
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
        visible: scr.tools
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font: Kirigami.Theme.smallFont
            opacity: 0.7
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
        { key: "time",    title: i18n("Time (ET)"),      w: 6.4, alert: true },
        { key: "symbol",  title: i18n("Symbol"),         w: 4.6 },
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
    // ranked screens, value columns on value lists. Columns `order` does not
    // name keep their default place at the end.
    readonly property var layoutAll: {
        try { return JSON.parse(Plasmoid.configuration.screenerLayout || "{}") } catch (e) { return {} }
    }
    readonly property var layout: layoutAll[feed] || ({})
    // A column this screen can show at all: Time and the label belong to
    // alert screens, Score and Missed need a scorecard.
    function possible(c) {
        return (!c.alert || alertFeed) && ((c.key !== "score" && c.key !== "missed") || scored)
    }
    function defaultShown(c) { return !c.on || c.on === (isValue ? "value" : "momentum") }
    function isShown(c) { return layout.shown ? layout.shown.indexOf(c.key) >= 0 : defaultShown(c) }
    readonly property var columns: {
        const order = layout.order || []
        const widths = layout.widths || {}
        const known = allColumns.filter(c => order.indexOf(c.key) >= 0)
                                .sort((a, b) => order.indexOf(a.key) - order.indexOf(b.key))
        const rest = allColumns.filter(c => order.indexOf(c.key) < 0)
        return known.concat(rest)
            .filter(c => possible(c) && isShown(c))
            // The score column fits its scorecard's dots unless resized by hand.
            .map(c => Object.assign({}, c, { w: widths[c.key] > 0 ? widths[c.key]
                : c.key === "score" && card ? Math.max(c.w, 2.6 + card.rules.length * 0.5) : c.w }))
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
        all[feed] = Object.assign({}, layout, changes)
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
    function etTime(ms) {
        const d = new Date(ms + engine.etOffset * 1000)
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
        case "price":  return has(r.price) ? r.price.toFixed(2) : "—"
        case "volume": return big(r.volume)
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
        case "marketCap": return big(r.marketCap)
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
    Item {
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
                                    anchors.rightMargin: 4
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
                        model: scr.rows
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: MouseArea {
                            id: rowItem
                            required property var modelData
                            required property int index
                            width: ListView.view.width
                            height: Kirigami.Units.gridUnit * (modelData.count > 1 ? 2.2 : 1.5)
                            hoverEnabled: true
                            // The screen's scorecard and this row go along, so the
                            // detail view can show the row rule by rule.
                            onClicked: scr.open({ symbol: modelData.symbol, label: modelData.symbol,
                                                  name: modelData.name || modelData.symbol, star: false,
                                                  scorecard: scr.current ? scr.current.scorecard : "",
                                                  row: modelData })

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
                                                           : cellBox.key === "symbol" ? symbolCell : textCell
                                        }

                                        Component {
                                            id: textCell
                                            PlasmaComponents3.Label {
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
                                        Component {
                                            id: symbolCell
                                            Item {
                                                PlasmaComponents3.Label {
                                                    anchors.left: parent.left
                                                    anchors.right: newsIcon.visible ? newsIcon.left : parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
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
                                visible: rowItem.containsMouse && (rowItem.modelData.newsTitle || dil) !== ""
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
                : scr.engine.currentPhase === "closed" ? i18n("Market closed: alerts resume at 04:00 ET premarket")
                : i18n("No alerts yet. Watching %1 symbols; the feed fills as they move.",
                       scr.engine.candidates.length)
        }
    }

    PlasmaComponents3.Label {
        visible: scr.tools
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        font: Kirigami.Theme.smallFont
        opacity: 0.6
        wrapMode: Text.WordWrap
        text: (scr.scored ? scr.card.name + ": " + scr.card.rules.map(Scorecards.describe).join(" · ") + ". " : "")
              + (scr.isValue ? i18n("Fundamentals from SEC filings, rechecked daily; price and averages live.") : "")
              + (!scr.alertFeed ? "" : ({
                  pre: i18n("Premarket: volume is the running premarket total; RVOL 5 min is against this premarket's average 5 minutes."),
                  regular: i18n("RVOL 5 min is against an average 5 minutes of the stock's normal day."),
                  post: i18n("After hours: no minute-by-minute volume, so Running Up fires on the price rise alone and RVOL 5 min shows —.")
              })[scr.engine.currentPhase] || "")
    }
}
