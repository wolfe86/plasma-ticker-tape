// The News tab: recent headlines in one list, newest first, grouped by when.
//
//   Your screens -- the newest headline of each stock that alerted on any
//                   screen today, where that headline is under 24 hours old
//                   -- or, while the market is closed, since the last
//                   session began (the facts look-up the screener already
//                   does).
//   Market       -- the market desks the scanner reads (Seeking
//                   Alpha, MarketWatch, CNBC), refreshed every 3 minutes.
//   Your feeds   -- your own sources (Settings → Data), when there are any.
//
// Each headline is a card: a picture (the feed's own, else the article's
// preview image, fetched only for cards on screen -- `newsImages`), the
// headline, the stocks it names as chips, their sector and theme glyphs
// (GroupIcons), the source and its age. The same story from two places is
// shown once. The search box filters by words, ticker or source -- and when
// what is typed is a ticker or a company name ("adobe"), that company's own
// news is fetched too (Yahoo's symbol search, then the scanner's per-ticker
// news, as its detail card shows it) and listed under "News for ADBE".
//
// Clicking a card opens the article; a ticker chip opens the stock's detail
// view.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: news

    required property var engine
    signal open(var entry)

    property string show: "all"           // all | screens | market | mine
    property string query: ""
    readonly property bool pictures: Plasmoid.configuration.newsImages
    // The company the search names, and its news: {query, symbol, name,
    // items, loading}, or null.
    property var lookup: null
    spacing: 0

    // How far back "Your screens" reaches: a day while the market trades;
    // while it is closed, back to the start (04:00 ET premarket) of the last
    // weekday session, if that is further -- a day's window left the tab
    // empty all weekend. Market holidays are not known (same as the clock).
    readonly property bool closed: engine.currentPhase === "closed"
    function since() {
        const day = Date.now() - 24 * 3600000
        if (!closed) return day
        const e = engine
        let t = Date.now() / 1000
        if (e.etMinutes(t) < e.preStart) t -= 86400
        const wd = s => new Date((s + e.etOffset) * 1000).getUTCDay()
        while (wd(t) === 0 || wd(t) === 6) t -= 86400
        const start = (t - ((t + e.etOffset) % 86400 + 86400) % 86400 + e.preStart * 60) * 1000
        return Math.min(day, start)
    }
    // Screen headlines: one per stock, its newest, if inside that window.
    readonly property var screenItems: {
        const info = engine.info
        const from = since()
        let all = []
        for (const id in engine.feeds) all = all.concat(engine.feeds[id])
        const seen = {}
        const out = []
        for (const a of all) {
            if (seen[a.symbol]) continue
            seen[a.symbol] = true
            const n = info[a.symbol] || {}
            if (!n.newsTitle || !n.newsTime || n.newsTime < from) continue
            out.push({ symbols: [a.symbol], name: n.name || a.name || "", title: n.newsTitle,
                       source: n.newsSource || "", url: n.newsUrl || "", time: n.newsTime, kind: "screens", image: "" })
        }
        return out
    }
    readonly property var items: {
        const market = (engine.marketNews || []).map(h => ({ title: h.title, url: h.url, source: h.source, time: h.time,
                                                             symbols: h.tickers || [], image: h.image || "", kind: "market" }))
        const mine = (engine.customNews || []).map(h => ({ title: h.title, url: h.url, source: h.source, time: h.time,
                                                           symbols: h.tickers || [], image: h.image || "", kind: "mine" }))
        const list = show === "screens" ? screenItems : show === "market" ? market : show === "mine" ? mine
                   : screenItems.concat(market, mine)
        // One card per story: the same headline from two places merges,
        // keeping every ticker either named.
        const byKey = {}, out = []
        for (const it of list) {
            const k = String(it.title).toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 60)
            const had = byKey[k]
            if (had) { for (const s of it.symbols) if (had.symbols.indexOf(s) < 0) had.symbols.push(s); if (!had.image) had.image = it.image; continue }
            const c = Object.assign({}, it, { symbols: it.symbols.slice() })
            byKey[k] = c
            out.push(c)
        }
        const q = query.trim().toLowerCase()
        const shown = !q ? out : out.filter(it => it.title.toLowerCase().indexOf(q) >= 0
            || String(it.source).toLowerCase().indexOf(q) >= 0
            || it.symbols.some(s => s.toLowerCase() === q.replace("$", "")))
        shown.sort((a, b) => b.time - a.time)
        const out2 = shown.map(it => Object.assign(it, { bucket: bucketOf(it.time) }))
        // The searched company's own news, after the matches already listed.
        const l = lookup
        if (q && l && l.query === q && l.items.length) {
            const head = i18n("News for %1 · %2", l.symbol, l.name)
            for (const it of l.items) {
                const k = String(it.title).toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 60)
                if (byKey[k] && shown.indexOf(byKey[k]) >= 0) continue
                out2.push(Object.assign({}, it, { symbols: it.symbols.slice(), bucket: head }))
            }
        }
        return out2
    }

    function bucketOf(ms) {
        const age = Date.now() - ms
        if (age < 3600000) return i18n("Last hour")
        const d = new Date(ms), t = new Date()
        if (d.toDateString() === t.toDateString()) return i18n("Earlier today")
        t.setDate(t.getDate() - 1)
        if (d.toDateString() === t.toDateString()) return i18n("Yesterday")
        return i18n("Older")
    }
    function ago(ms) {
        const mins = Math.round((Date.now() - ms) / 60000)
        if (mins < 60) return i18n("%1m ago", Math.max(1, mins))
        if (mins < 60 * 24) return i18n("%1h ago", Math.round(mins / 60))
        return i18n("%1d ago", Math.round(mins / 1440))
    }
    // A steady colour per source, for the picture's stand-in.
    function sourceColor(name) {
        let h = 0
        for (const c of String(name)) h = (h * 31 + c.charCodeAt(0)) % 360
        return Qt.hsla(h / 360, 0.45, 0.45, 1)
    }
    // ── company search ──────────────────────────────────────────────────
    // After typing stops: Yahoo's symbol search turns the words into a US
    // stock or fund (the first one without an exchange suffix, so ADBE, not
    // ADB.DE or a future), then its news comes from the scanner -- the
    // company's own headlines first, as on its detail card. Only the newest
    // search's answer is kept.
    onQueryChanged: { lookup = null; searchTimer.restart() }
    Timer {
        id: searchTimer
        interval: 700
        onTriggered: news.searchCompany(news.query.trim().toLowerCase())
    }
    function searchCompany(q) {
        if (q.replace("$", "").length < 2) return
        lookup = { query: q, symbol: "", name: "", items: [], loading: true }
        engine.ticker.yget("https://query2.finance.yahoo.com/v1/finance/search?quotesCount=6&newsCount=0&q="
                           + encodeURIComponent(q.replace("$", "")), x => {
            if (!lookup || lookup.query !== q) return
            let pick = null
            try {
                pick = (JSON.parse(x.responseText).quotes || []).find(r =>
                    (r.quoteType === "EQUITY" || r.quoteType === "ETF")
                    && /^[A-Z0-9\-]{1,6}$/.test(r.symbol || ""))
            } catch (e) {}
            if (!pick) { lookup = { query: q, symbol: "", name: "", items: [], loading: false }; return }
            const sym = pick.symbol
            const name = pick.shortname || pick.longname || sym
            lookup = { query: q, symbol: sym, name: name, items: [], loading: true }
            engine.bridgeRun(["tickernews", sym], out => {
                if (!lookup || lookup.query !== q) return
                let rows = (Array.isArray(out) ? out : []).filter(n => n.title && n.link)
                const own = rows.filter(n => n.company)
                if (own.length >= 5) rows = own
                lookup = { query: q, symbol: sym, name: name, loading: false,
                           items: rows.slice(0, 20).map(n => ({ title: n.title, url: n.link, source: n.source || "",
                                                                 time: n.time, symbols: [sym], image: "", kind: "lookup" })) }
            }, 30, true)
        })
    }

    function openStock(sym) { open({ symbol: sym, label: sym, name: sym, star: false }) }

    // Sector look-ups for the stocks the cards name, gathered and sent in
    // one go rather than one helper call per card.
    property var pendingLookups: []
    function wantGroups(syms) {
        for (const s of syms) if (pendingLookups.indexOf(s) < 0) pendingLookups.push(s)
        lookupTimer.restart()
    }
    Timer {
        id: lookupTimer
        interval: 600
        onTriggered: { news.engine.lookupGroups(news.pendingLookups); news.pendingLookups = [] }
    }

    // ── filter, search, status ──────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.topMargin: Kirigami.Units.smallSpacing
        Repeater {
            model: [ { key: "all", text: i18n("All"), tip: i18n("Every headline, newest first") },
                     { key: "screens", text: i18n("Your screens"), tip: i18n("Headlines for stocks on your screens") },
                     { key: "market", text: i18n("Market"), tip: i18n("Market desks") } ]
                   .concat(news.engine.newsSources.length ? [{ key: "mine", text: i18n("Your feeds"), tip: i18n("Your own sources") }] : [])
            PlasmaComponents3.ToolButton {
                required property var modelData
                text: modelData.text
                checkable: true
                checked: news.show === modelData.key
                onClicked: news.show = modelData.key
                PlasmaComponents3.ToolTip { text: parent.modelData.tip }
            }
        }
        Item { Layout.fillWidth: true }
        PlasmaComponents3.ToolButton {
            icon.name: "view-refresh"
            onClicked: { news.engine.refreshMarketNews(); news.engine.refreshCustomNews() }
            PlasmaComponents3.ToolTip { text: i18n("Refresh the headlines") }
        }
    }
    PlasmaExtras.SearchField {
        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.smallSpacing
        Layout.rightMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: Kirigami.Units.smallSpacing
        placeholderText: i18n("Search headlines, a ticker or a source…")
        onTextChanged: news.query = text
    }
    Kirigami.Separator { Layout.fillWidth: true }

    PlasmaComponents3.ScrollView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

        ListView {
            id: list
            model: news.items
            clip: true
            reuseItems: false

            section.property: "bucket"
            section.delegate: PlasmaExtras.Heading {
                required property string section
                width: ListView.view.width
                level: 5
                opacity: 0.7
                topPadding: Kirigami.Units.smallSpacing * 2
                bottomPadding: Kirigami.Units.smallSpacing
                leftPadding: Kirigami.Units.smallSpacing * 2
                textFormat: Text.PlainText
                text: section
            }

            delegate: PlasmaComponents3.ItemDelegate {
                id: card
                required property var modelData
                width: ListView.view.width
                readonly property string picture: modelData.image || news.engine.articleImages[modelData.url] || ""
                enabled: !!modelData.url || modelData.symbols.length > 0
                // Feed links are only opened as web pages, never another scheme.
                onClicked: modelData.url ? (/^https?:\/\//i.test(modelData.url) && Qt.openUrlExternally(modelData.url))
                                         : news.openStock(modelData.symbols[0])
                Component.onCompleted: {
                    if (news.pictures && !modelData.image && modelData.url) news.engine.wantImage(modelData.url)
                    if (modelData.symbols.length) news.wantGroups(modelData.symbols.slice(0, 3))
                }

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    // The picture, or the source's initial on its colour.
                    Item {
                        visible: news.pictures
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                        Rectangle {
                            anchors.fill: parent
                            radius: Kirigami.Units.cornerRadius
                            visible: img.status !== Image.Ready
                            color: news.sourceColor(card.modelData.source)
                            opacity: 0.35
                        }
                        PlasmaComponents3.Label {
                            anchors.centerIn: parent
                            visible: img.status !== Image.Ready
                            textFormat: Text.PlainText
                            text: String(card.modelData.source || "?").charAt(0).toUpperCase()
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.6
                            font.bold: true
                            opacity: 0.8
                        }
                        // A plain clipped Image: Kirigami's ShadowedImage draws through a
                        // shader that did not paint at all in testing.
                        Item {
                            anchors.fill: parent
                            clip: true
                            Image {
                                id: img
                                anchors.fill: parent
                                source: card.picture
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: Kirigami.Units.gridUnit * 9
                                visible: status === Image.Ready
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        spacing: Kirigami.Units.smallSpacing / 2
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: card.modelData.title
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            font.weight: Font.DemiBold
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            // The stocks it names: open their detail view.
                            Repeater {
                                model: card.modelData.symbols.slice(0, 3)
                                delegate: Rectangle {
                                    id: chip
                                    required property string modelData
                                    implicitWidth: chipRow.implicitWidth + Kirigami.Units.smallSpacing * 2
                                    implicitHeight: chipRow.implicitHeight + 2
                                    radius: height / 2
                                    color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g,
                                                   Kirigami.Theme.highlightColor.b, chipHover.hovered ? 0.45 : 0.22)
                                    RowLayout {
                                        id: chipRow
                                        anchors.centerIn: parent
                                        spacing: 2
                                        PlasmaComponents3.Label {
                                            textFormat: Text.PlainText
                                            text: chip.modelData
                                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                                            font.bold: true
                                        }
                                        GroupIcons {
                                            engine: news.engine
                                            symbol: chip.modelData
                                            headline: card.modelData.title
                                            size: Kirigami.Units.iconSizes.small * 0.8
                                        }
                                    }
                                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: news.openStock(chip.modelData) }
                                    PlasmaComponents3.ToolTip { visible: chipHover.hovered; textFormat: Text.PlainText; text: i18n("Open %1's chart and figures", chip.modelData) }
                                }
                            }
                            // A headline naming no stock can still carry one of your themes.
                            GroupIcons {
                                visible: card.modelData.symbols.length === 0 && (showSector || showTheme)
                                engine: news.engine
                                headline: card.modelData.title
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                text: [card.modelData.source, news.ago(card.modelData.time),
                                       card.modelData.kind === "screens" ? i18n("from your screens")
                                       : card.modelData.kind === "mine" ? i18n("your feed") : ""]
                                      .filter(t => t).join(" · ")
                            }
                        }
                    }
                }
            }

            PlasmaComponents3.Label {
                anchors.centerIn: parent
                width: parent.width - Kirigami.Units.gridUnit * 4
                visible: list.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: 0.7
                textFormat: Text.PlainText
                text: news.lookup && news.lookup.loading ? i18n("Looking for news on “%1”…", news.query)
                    : news.query ? i18n("No headlines match “%1”.", news.query)
                    : news.show === "screens" ? (news.closed ? i18n("No headlines since the last session began for the stocks on your screens.")
                                                             : i18n("No headlines in the last day for the stocks on your screens yet."))
                    : i18n("Loading headlines…")
            }
        }
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        font: Kirigami.Theme.smallFont
        opacity: 0.6
        elide: Text.ElideRight
        textFormat: Text.PlainText
        // What the list is: the search, or the filter, then the count.
        readonly property string desks: isNaN(news.engine.marketNewsAt.getTime()) ? i18n("Market desks loading…")
                                        : i18n("Market desks · %1", Qt.formatTime(news.engine.marketNewsAt, "h:mm ap"))
        readonly property string what: {
            const q = news.query.trim()
            const l = news.lookup
            if (q) return l && l.symbol && l.query === q.toLowerCase() ? i18n("Search “%1” · News for %2", q, l.symbol)
                                                                      : i18n("Search “%1”", q)
            if (news.show === "screens") return news.closed ? i18n("Your screens · since the last session")
                                                            : i18n("Your screens · last 24 hours")
            if (news.show === "market") return desks
            if (news.show === "mine") return i18n("Your feeds")
            return i18n("All sources") + " · " + desks
        }
        text: what + " · " + i18np("%1 headline", "%1 headlines", list.count)
    }
}
