// The News tab: recent headlines in one list, newest first, from two places.
//
//   Your screens -- the newest headline of each stock that alerted on any
//                   screen today, where that headline is under 24 hours old
//                   (the facts look-up the screener already does).
//   Market       -- the market desks the scanner reads (Seeking
//                   Alpha, MarketWatch, CNBC), refreshed every 3 minutes.
//
// Clicking a headline opens the article; the ticker chip on a screen
// headline opens the stock's detail view.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: news

    required property var engine
    signal open(var entry)

    property string show: "all"           // all | screens | market
    spacing: 0

    // Screen headlines: one per stock, its newest, if under a day old.
    readonly property var screenItems: {
        const info = engine.info
        let all = []
        for (const id in engine.feeds) all = all.concat(engine.feeds[id])
        const seen = {}
        const out = []
        for (const a of all) {
            if (seen[a.symbol]) continue
            seen[a.symbol] = true
            const n = info[a.symbol] || {}
            if (!n.newsTitle || !n.newsTime || Date.now() - n.newsTime > 24 * 3600000) continue
            out.push({ symbol: a.symbol, name: n.name || a.name || "", title: n.newsTitle,
                       source: n.newsSource || "", url: n.newsUrl || "", time: n.newsTime, kind: "screens" })
        }
        return out
    }
    readonly property var items: {
        const market = (engine.marketNews || []).map(h => Object.assign({ kind: "market" }, h))
        const list = show === "screens" ? screenItems : show === "market" ? market : screenItems.concat(market)
        return list.slice().sort((a, b) => b.time - a.time)
    }

    function ago(ms) {
        const mins = Math.round((Date.now() - ms) / 60000)
        if (mins < 60) return i18n("%1m ago", Math.max(1, mins))
        if (mins < 60 * 24) return i18n("%1h ago", Math.round(mins / 60))
        return i18n("%1d ago", Math.round(mins / 1440))
    }

    // ── filter and status ───────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: Kirigami.Units.smallSpacing
        Repeater {
            model: [ { key: "all", text: i18n("All") }, { key: "screens", text: i18n("Your screens") },
                     { key: "market", text: i18n("Market") } ]
            PlasmaComponents3.ToolButton {
                required property var modelData
                text: modelData.text
                checkable: true
                checked: news.show === modelData.key
                onClicked: news.show = modelData.key
            }
        }
        Item { Layout.fillWidth: true }
        PlasmaComponents3.Label {
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: isNaN(news.engine.marketNewsAt.getTime()) ? i18n("Loading…")
                : i18n("Market desks · %1", Qt.formatTime(news.engine.marketNewsAt, "h:mm ap"))
        }
        PlasmaComponents3.ToolButton {
            icon.name: "view-refresh"
            onClicked: news.engine.refreshMarketNews()
            PlasmaComponents3.ToolTip { text: i18n("Refresh the market headlines") }
        }
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

            delegate: PlasmaComponents3.ItemDelegate {
                id: row
                required property var modelData
                width: ListView.view.width
                enabled: !!modelData.url || !!modelData.symbol
                // Feed links are only opened as web pages, never another scheme.
                onClicked: modelData.url ? (/^https?:\/\//i.test(modelData.url) && Qt.openUrlExternally(modelData.url))
                                         : news.open({ symbol: modelData.symbol, label: modelData.symbol,
                                                       name: modelData.name || modelData.symbol, star: false })

                contentItem: RowLayout {
                    spacing: Kirigami.Units.largeSpacing

                    // The stock it is about, for a screen headline: opens its detail view.
                    PlasmaComponents3.Button {
                        visible: row.modelData.kind === "screens"
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                        text: row.modelData.symbol || ""
                        font.bold: true
                        flat: true
                        onClicked: news.open({ symbol: row.modelData.symbol, label: row.modelData.symbol,
                                               name: row.modelData.name || row.modelData.symbol, star: false })
                        PlasmaComponents3.ToolTip { text: i18n("Open %1's chart and figures", row.modelData.symbol || "") }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: row.modelData.title
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                            text: [row.modelData.source, news.ago(row.modelData.time),
                                   row.modelData.kind === "screens" ? i18n("from your screens") : ""]
                                  .filter(t => t).join(" · ")
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
                text: news.show === "screens"
                    ? i18n("No headlines in the last day for the stocks on your screens yet.")
                    : i18n("Loading headlines…")
            }
        }
    }
}
