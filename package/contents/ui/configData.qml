// Settings → Data: the scanner the screener's bridge runs (code/scanner/ by
// default) and what it is told -- the SEC contact, and which companies'
// earnings the calendar lists. Passed to the scanner as environment
// variables on every call (ScreenerEngine.qml, `bridgeRun`).
//
// And your own news sources (newsfeeds.js): RSS, Atom or a JSON API, each
// with an optional request header for a paid feed's key, and a Test button.

import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import "newsfeeds.js" as NewsFeeds

KCM.SimpleKCM {
    id: page
    property alias cfg_scannerDir: scannerDir.text
    property string cfg_newsSources: ""
    property alias cfg_newsBuiltins: builtins.checked
    property alias cfg_newsImages: newsImages.checked
    property alias cfg_newsLocale: newsLocale.text

    // ── news sources ──
    readonly property var sources: NewsFeeds.load({ newsSources: cfg_newsSources })
    function commit(l) { cfg_newsSources = JSON.stringify(l) }
    function setSource(i, changes) {
        const l = sources.slice()
        l[i] = Object.assign({}, l[i], changes)
        commit(l)
    }
    function setMap(i, key, value) {
        const m = Object.assign({}, sources[i].map || {})
        if (value) m[key] = value; else delete m[key]
        setSource(i, { map: m })
    }
    // Test results by the source's address, {text, ok}: a result stays
    // with its source when another row is deleted, and goes when the
    // address changes.
    property var tests: ({})
    function test(i) {
        const url = sources[i].url
        const t = Object.assign({}, tests); t[url] = { text: i18n("Fetching…"), ok: true }; tests = t
        NewsFeeds.fetch(sources[i], (items, err) => {
            const named = items.filter(it => it.tickers.length).length
            const r = Object.assign({}, tests)
            r[url] = items.length
                ? { ok: true, text: i18n("%1 headlines, %2 name a ticker. Newest: %3", items.length, named,
                                         items.slice().sort((a, b) => b.time - a.time)[0].title) }
                : { ok: false, text: i18n("Nothing usable: %1",
                                          /^HTTP 0\b/.test(String(err)) ? i18n("could not reach the address") : err) }
            tests = r
        })
    }

    property alias cfg_secContact: secContact.text
    property alias cfg_researchDir: researchDir.text
    property alias cfg_earningsTickers: earningsTickers.text
    property real cfg_earningsMinCap

    // A number typed into a box: "40", "40B", "500M", "$1.5B or more".
    // null when there is no number in it.
    function typedNum(text) {
        const m = String(text || "").replace(/,/g, "").match(/(-?\d+(?:\.\d+)?)\s*([kmb])?(?![a-z])/i)
        if (!m) return null
        const v = parseFloat(m[1]) * ({ k: 1e3, m: 1e6, b: 1e9 }[(m[2] || "").toLowerCase()] || 1)
        return isFinite(v) ? v : null
    }

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
                QQC2.ToolTip.text: i18n("The folder of Python code that gathers the lists, news and calendar. Leave empty for the one that ships with the widget.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Button {
                icon.name: "folder-open"
                onClicked: browse(scannerDir)
                QQC2.ToolTip.text: i18n("Choose a folder")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                Accessible.name: i18n("Choose a folder")
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
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
            placeholderText: i18n("Jane Doe jane@example.com")
            QQC2.ToolTip.text: i18n("Your name and email, which SEC EDGAR requires of every program that reads its filings")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.Label {
            Layout.fillWidth: true
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
            id: minCap
            Kirigami.FormData.label: i18n("Always list companies worth:")
            from: 0
            to: 5000
            stepSize: 5
            editable: true
            validator: RegularExpressionValidator { regularExpression: /[^\d]*-?[\d.,]*\s*[kKmMbB]?[^\d]*/ }
            value: Math.round(cfg_earningsMinCap / 1e9)
            onValueModified: cfg_earningsMinCap = value * 1e9
            textFromValue: (v, locale) => i18n("$%1B or more", v)
            // In billions: "40" and "40B" are both $40B; "500M" rounds to $1B.
            valueFromText: (text, locale) => {
                const v = page.typedNum(text)
                if (v === null) return minCap.value
                return Math.round(/\d\s*[kmb](?![a-z])/i.test(text) ? v / 1e9 : v)
            }
            QQC2.ToolTip.text: i18n("Every company reporting with at least this market cap is listed. 0 lists all.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Research folder:")
            QQC2.TextField {
                id: researchDir
                Layout.minimumWidth: Kirigami.Units.gridUnit * 18
                placeholderText: i18n("Optional")
                QQC2.ToolTip.text: i18n("A folder whose subfolders are named by ticker. Each one puts that company's earnings on the calendar.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Button {
                icon.name: "folder-open"
                onClicked: browse(researchDir)
                QQC2.ToolTip.text: i18n("Choose a folder")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                Accessible.name: i18n("Choose a folder")
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
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
            QQC2.ToolTip.text: i18n("Tickers separated by commas or spaces; their earnings always show on the calendar.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            text: i18n("Every other reporter is left off, so the calendar shows the companies you follow rather than every company reporting that day.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("News sources") }

        QQC2.TextField {
            id: newsLocale
            Kirigami.FormData.label: i18n("Google News edition:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 6
            placeholderText: "en-US"
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            QQC2.ToolTip.text: i18n("Language and country for the news a quote shows when the scanner has none: en-US, en-GB, de-DE, fr-FR…")
        }
        QQC2.CheckBox {
            id: builtins
            Kirigami.FormData.label: i18n("Market desks:")
            text: i18n("Seeking Alpha, MarketWatch and CNBC (built in, refreshed every 3 minutes)")
            QQC2.ToolTip.text: i18n("Market-wide headlines for the News tab, from three built-in feeds.")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
        }
        QQC2.CheckBox {
            id: newsImages
            Kirigami.FormData.label: i18n("Pictures:")
            text: i18n("Show a picture beside each headline")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            QQC2.ToolTip.text: i18n("The feed's own picture where it has one, else the article's preview image — read from the top of its page, only for headlines on screen.")
        }
        ColumnLayout {
            Kirigami.FormData.label: i18n("Your sources:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 26
            spacing: Kirigami.Units.largeSpacing
            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Checked on the interval set under Settings → Performance.")
                opacity: 0.7
            }
            // The model is a count, not the sources themselves, so editing a
            // field redraws that row's values without rebuilding every row
            // (and the field being typed in keeps its focus).
            Repeater {
                model: page.sources.length
                ColumnLayout {
                    id: src
                    required property int index
                    readonly property var s: page.sources[index] || ({})
                    readonly property bool json: s.kind === "json"
                    readonly property var result: page.tests[s.url || ""]
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    RowLayout {
                        Layout.fillWidth: true
                        QQC2.CheckBox {
                            checked: src.s.on !== false
                            onToggled: page.setSource(src.index, { on: checked })
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            QQC2.ToolTip.text: i18n("Use this source")
                        }
                        QQC2.TextField {
                            Layout.fillWidth: true
                            text: src.s.name || ""
                            placeholderText: i18n("Name, shown beside its headlines")
                            onEditingFinished: if (text !== (src.s.name || "")) page.setSource(src.index, { name: text })
                            QQC2.ToolTip.text: i18n("Shown beside this source's headlines")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.ComboBox {
                            implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                            model: [i18n("RSS or Atom"), i18n("JSON API")]
                            currentIndex: src.json ? 1 : 0
                            onActivated: index => page.setSource(src.index, { kind: index ? "json" : "rss" })
                            QQC2.ToolTip.text: i18n("RSS or Atom: an ordinary news feed. JSON API: a data service; fill in where its fields are below.")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.Button {
                            icon.name: "media-playback-start"
                            text: i18n("Test")
                            enabled: !!src.s.url
                            onClicked: page.test(src.index)
                            QQC2.ToolTip.text: i18n("Fetch it now and show what was found")
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-delete"
                            onClicked: page.commit(page.sources.filter((s, i) => i !== src.index))
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            QQC2.ToolTip.text: i18n("Remove this source")
                            Accessible.name: i18n("Remove this source")
                        }
                    }
                    QQC2.TextField {
                        Layout.fillWidth: true
                        text: src.s.url || ""
                        placeholderText: src.json ? i18n("https://api.example.com/v1/news?symbols=…") : i18n("https://www.example.com/feed.rss")
                        onEditingFinished: if (text.trim() !== (src.s.url || "")) page.setSource(src.index, { url: text.trim() })
                        QQC2.ToolTip.text: i18n("The feed's web address")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    Kirigami.PasswordField {
                        Layout.fillWidth: true
                        text: src.s.header || ""
                        placeholderText: i18n("Header, for a paid feed: e.g. Authorization: Bearer abc123 (optional)")
                        onEditingFinished: if (text.trim() !== (src.s.header || "")) page.setSource(src.index, { header: text.trim() })
                        QQC2.ToolTip.text: i18n("Only for a paid feed that needs a key: the whole header line its instructions give, name and value.")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    // Where the fields are in a JSON response: dotted paths.
                    GridLayout {
                        visible: src.json
                        Layout.fillWidth: true
                        columns: 3
                        Repeater {
                            model: [
                                { key: "items",   hint: i18n("List (empty = the whole reply), e.g. data.items") },
                                { key: "title",   hint: i18n("Headline field (default: title)") },
                                { key: "time",    hint: i18n("Time field (default: time)") },
                                { key: "link",    hint: i18n("Link field (default: url)") },
                                { key: "tickers", hint: i18n("Tickers field (default: tickers)") },
                                { key: "source",  hint: i18n("Publisher field (optional)") }
                            ]
                            QQC2.TextField {
                                required property var modelData
                                Layout.fillWidth: true
                                text: (src.s.map || {})[modelData.key] || ""
                                placeholderText: modelData.hint
                                onEditingFinished: if (text.trim() !== ((src.s.map || {})[modelData.key] || "")) page.setMap(src.index, modelData.key, text.trim())
                                QQC2.ToolTip.text: modelData.hint
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            }
                        }
                    }
                    // The feed's own text: shown plain, never as markup.
                    QQC2.Label {
                        visible: !!src.result
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: src.result ? src.result.text : ""
                        color: src.result && !src.result.ok ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        font: Kirigami.Theme.smallFont
                    }
                    Kirigami.Separator { Layout.fillWidth: true }
                }
            }
            QQC2.Button {
                icon.name: "list-add"
                text: i18n("Add a source")
                onClicked: page.commit(page.sources.concat([{ name: "", url: "", kind: "rss", on: true, header: "" }]))
                QQC2.ToolTip.text: i18n("Add an empty source to fill in")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.WordWrap
            text: i18n("Any RSS or Atom feed works as it is; for a JSON API, fill in where the list, headline and time sit in its reply (dotted paths, like data.items). Headlines are matched to tickers by $TICKER, (NASDAQ: TICKER) or the feed's own ticker field, and a newer one replaces a screener row's headline, its news filter and its theme. Sources are checked on a timer, not pushed: a streaming feed needs more than a widget.")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.WordWrap
            text: i18n("A header is saved in plain text in this widget's settings file (~/.config/plasma-org.kde.plasma.desktop-appletsrc), like every other setting. It is sent in the request header, and only to an https:// address. If that address redirects elsewhere, Qt forwards the header with the request, so only use headers with sources you trust; the reply from the other site is discarded.")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.neutralTextColor
        }
    }
}
