// Settings → Symbols: the watchlist.
//
// Search adds any symbol Yahoo knows -- stock, index, ETF, crypto, currency,
// future. The list below is the watchlist in display order: drag to reorder,
// star to put a symbol on the tape, edit the short label the tape prints.
// Unstarred symbols stay on the watchlist only.
//
// The whole list is stored as one JSON string (cfg_symbols); the ListModel
// here is the editable copy and is written back on every change.
//
// Saving follows the pattern described at the top of configScreener.qml: on
// Apply, a list this page did not change is re-read from the live
// configuration, and a symbol the detail card's "+ Watchlist" added while
// the page was open is kept alongside this page's edits.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

KCM.SimpleKCM {
    id: page

    property string cfg_symbols

    ListModel { id: watch }

    // Load once, then the model leads and the string follows.
    property bool loaded: false
    function fill() {
        let list = []
        try { list = JSON.parse(cfg_symbols) } catch (e) {}
        watch.clear()
        for (const s of (Array.isArray(list) ? list : []))
            if (s && s.symbol)
                watch.append({ symbol: s.symbol, label: s.label || s.symbol,
                               name: s.name || "", star: !!s.star })
    }
    Component.onCompleted: {
        fill()
        loaded = true
        snapshot()
    }

    // ── saving without undoing the pop-up (configScreener.qml explains) ──
    property var opened: ({})
    function liveConfig() {
        try { return Plasmoid.configuration || null } catch (e) { return null }
    }
    function snapshot() {
        const c = liveConfig()
        if (!c) return
        const o = {}
        for (const k of c.keys()) if (("cfg_" + k) in page) o[k] = page["cfg_" + k]
        opened = o
    }
    function saveConfig() {
        const c = liveConfig()
        if (!c) return
        const before = cfg_symbols
        for (const k of c.keys()) {
            const p = "cfg_" + k
            if (!(p in page) || !(k in opened)) continue
            if (page[p] === opened[k]) page[p] = c[k]
            else if (k === "symbols") page[p] = mergeSymbols(opened[k], page[p], c[k])
        }
        if (cfg_symbols !== before) fill()
        snapshot()
    }
    // This page's list, plus any symbol added elsewhere while it was open.
    function mergeSymbols(base, mine, theirs) {
        let b, m, t
        try {
            b = JSON.parse(base || "[]"); m = JSON.parse(mine || "[]"); t = JSON.parse(theirs || "[]")
        } catch (e) { return mine }
        if (!Array.isArray(m) || !Array.isArray(t)) return mine
        if (!Array.isArray(b)) b = []
        const has = (l, sym) => l.some(s => s && s.symbol === sym)
        return JSON.stringify(m.concat(t.filter(s => s && !has(b, s.symbol) && !has(m, s.symbol))))
    }
    function save() {
        if (!loaded) return
        const list = []
        for (let i = 0; i < watch.count; i++) {
            const s = watch.get(i)
            list.push({ symbol: s.symbol, label: s.label, name: s.name, star: s.star })
        }
        cfg_symbols = JSON.stringify(list)
    }
    function has(symbol) {
        for (let i = 0; i < watch.count; i++)
            if (watch.get(i).symbol === symbol) return true
        return false
    }

    // A tape label from a Yahoo symbol: ^GSPC -> GSPC, BTC-USD -> BTC,
    // EURUSD=X -> EURUSD. Editable afterwards.
    function defaultLabel(symbol) {
        return symbol.replace(/^\^/, "").replace(/-USD$/, "").replace(/=X$/, "")
    }
    function add(q) {
        if (has(q.symbol)) return
        // Yahoo pads some names with runs of spaces; collapse them.
        const name = String(q.shortname || q.longname || q.symbol).replace(/\s+/g, " ").trim()
        watch.append({ symbol: q.symbol, label: defaultLabel(q.symbol), name: name, star: false })
        save()
        search.text = ""
    }

    // ── search ───────────────────────────────────────────────────────────
    // Yahoo's search endpoint, debounced so typing does not fire a request
    // per keystroke. The User-Agent header is required: without it Yahoo
    // answers with an empty body.
    property var results: []
    property bool searching: false
    property var pending: null

    Timer {
        id: debounce
        interval: 350
        onTriggered: page.runSearch(search.text.trim())
    }
    function runSearch(q) {
        if (pending) pending.abort()
        if (q.length === 0) { results = []; searching = false; return }
        const x = new XMLHttpRequest()
        pending = x
        searching = true
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE || x !== pending) return
            searching = false
            pending = null
            try {
                results = (JSON.parse(x.responseText).quotes || [])
                    .filter(r => r.symbol && r.quoteType)
            } catch (e) {
                results = []
            }
        }
        x.open("GET", "https://query1.finance.yahoo.com/v1/finance/search?q="
               + encodeURIComponent(q) + "&quotesCount=10&newsCount=0")
        x.setRequestHeader("User-Agent", "Mozilla/5.0")
        x.send()
    }
    function kind(t) {
        return ({ EQUITY: i18n("Stock"), ETF: i18n("ETF"), INDEX: i18n("Index"),
                  CRYPTOCURRENCY: i18n("Crypto"), CURRENCY: i18n("Currency"),
                  FUTURE: i18n("Future"), MUTUALFUND: i18n("Fund"),
                  OPTION: i18n("Option") })[t] || t
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // The tape's Themes entry: not a ticker but a slot that fills with
        // the tickers of the themes running hot on the screener (Settings →
        // Tape sets which and how many). Star it and drag it like any symbol.
        QQC2.Button {
            visible: !page.has("@themes")
            icon.name: "list-add"
            text: i18n("Add the Themes entry (beta): hot-theme tickers from the screener")
            onClicked: {
                watch.append({ symbol: "@themes", label: i18n("Themes"), name: i18n("Tickers on the themes running hot on the screener"), star: true })
                page.save()
            }
            QQC2.ToolTip.text: i18n("Adds a slot to the tape that fills with tickers from themes running hot on your screener. Tune it under Settings → Tape.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        Kirigami.SearchField {
            id: search
            Layout.fillWidth: true
            placeholderText: i18n("Add a ticker, index, crypto or currency…")
            onTextChanged: debounce.restart()
            // Enter adds the top result.
            onAccepted: if (page.results.length > 0) page.add(page.results[0])
            QQC2.ToolTip.text: i18n("Search Yahoo for a ticker, index, crypto or currency (Enter adds the top match)")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }

        // Search results; hidden while the field is empty.
        ColumnLayout {
            Layout.fillWidth: true
            visible: search.text.trim().length > 0
            spacing: 0

            QQC2.Label {
                visible: !page.searching && page.results.length === 0
                text: i18n("No matches")
                opacity: 0.7
            }
            Repeater {
                model: page.results
                delegate: QQC2.ItemDelegate {
                    id: hit
                    required property var modelData
                    // Already listed: greyed, but left hoverable so the
                    // tooltip can say why it does nothing.
                    readonly property bool listed: page.has(modelData.symbol)
                    Layout.fillWidth: true
                    opacity: listed ? 0.5 : 1
                    onClicked: if (!listed) page.add(modelData)
                    QQC2.ToolTip.text: listed ? i18n("Already on your watchlist") : i18n("Add to the watchlist")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing
                        // Remote text (Yahoo's): always plain, never markup.
                        QQC2.Label {
                            text: modelData.symbol
                            textFormat: Text.PlainText
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            text: modelData.shortname || modelData.longname || ""
                            textFormat: Text.PlainText
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        QQC2.Label {
                            text: page.kind(modelData.quoteType)
                                  + (modelData.exchDisp ? " · " + modelData.exchDisp : "")
                            textFormat: Text.PlainText
                            opacity: 0.7
                        }
                        Kirigami.Icon {
                            source: hit.listed ? "checkmark" : "list-add"
                            implicitWidth: Kirigami.Units.iconSizes.small
                            implicitHeight: Kirigami.Units.iconSizes.small
                        }
                    }
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: i18n("★ = on the tape; the rest are watchlist only. Drag the handle on the left to reorder. The label is what the tape prints.")
            opacity: 0.7
        }

        // ── the watchlist ───────────────────────────────────────────────
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.preferredHeight: contentHeight
            interactive: false
            model: watch
            reuseItems: false

            // Each row sits in a holder. While a row is dragged the handle
            // lifts it out of the list; the holder keeps its slot, so the
            // row drops back into place. A row with no holder loses its
            // slot and lands drawn over another one.
            delegate: Item {
                id: holder
                required property int index
                required property string symbol
                required property string label
                required property string name
                required property bool star
                width: ListView.view.width
                implicitHeight: row.implicitHeight

                QQC2.ItemDelegate {
                    id: row
                    width: holder.width
                    down: false
                    hoverEnabled: true

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.ListItemDragHandle {
                            listItem: row
                            listView: list
                            onMoveRequested: (oldIndex, newIndex) => watch.move(oldIndex, newIndex, 1)
                            onDropped: page.save()
                            HoverHandler { id: handleHover }
                            QQC2.ToolTip.text: i18n("Drag to change the order on the tape and watchlist")
                            QQC2.ToolTip.visible: handleHover.hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.ToolButton {
                            icon.name: holder.star ? "starred-symbolic" : "non-starred-symbolic"
                            icon.color: holder.star ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor
                            checkable: true
                            checked: holder.star
                            onToggled: { watch.setProperty(holder.index, "star", checked); page.save() }
                            QQC2.ToolTip.text: holder.star ? i18n("On the tape: click to keep it on the watchlist only")
                                                        : i18n("Watchlist only: click to put it on the tape")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            QQC2.Label {
                                text: holder.symbol === "@themes" ? i18n("Themes (beta)") : holder.symbol
                                textFormat: Text.PlainText
                                font.bold: true
                            }
                            QQC2.Label {
                                Layout.fillWidth: true
                                text: holder.name
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                            }
                        }
                        QQC2.TextField {
                            id: labelField
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                            text: holder.label
                            placeholderText: i18n("Label")
                            onEditingFinished: {
                                const t = text.trim() || page.defaultLabel(holder.symbol)
                                if (t !== holder.label) { watch.setProperty(holder.index, "label", t); page.save() }
                                else text = Qt.binding(() => holder.label)
                            }
                            QQC2.ToolTip.text: i18n("What the tape prints for this symbol. Leave empty to use the symbol.")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-delete-remove"
                            onClicked: { watch.remove(holder.index, 1); page.save() }
                            QQC2.ToolTip.text: i18n("Remove from the watchlist")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                    }
                }
            }
        }

        QQC2.Label {
            visible: watch.count === 0
            text: i18n("The watchlist is empty. Search above to add a symbol.")
            opacity: 0.7
        }
    }
}
