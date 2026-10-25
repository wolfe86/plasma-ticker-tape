// Settings → Screeners: the market pool every screen reads, and the screens
// themselves -- add, duplicate, delete, reorder, and edit each one's type,
// trigger, filters, scorecard and sound. The shape of a screen and the
// starting list are in screens.js.
//
// The list is edited as a JS array (`list`) and written back to the
// `screens` setting as JSON on every change.
//
// ── Saving without undoing the pop-up ───────────────────────────────────
// Plasma 6.8 (AppletConfiguration.qml) builds a settings page with a `cfg_`
// copy of every setting it declares. On Apply or OK it calls the page's
// saveConfig() first, then writes every declared `cfg_` value back. The
// pop-up and the engine change some of the same settings while the page is
// open -- the speaker button, Score ≥, a screen added once by an upgrade --
// and a plain copy would put the old value back. So, on every page that
// shares a setting with the pop-up (Screeners, Symbols, Scorecards, Themes):
//   1. declare only the settings the page edits, or must read to work;
//   2. `opened` keeps each one's value as the page opened (or last saved);
//   3. saveConfig() re-reads from the live configuration every setting the
//      page did not change, and merges the ones both sides changed.
// The live configuration is `Plasmoid.configuration`, the same map Plasma's
// dialog saves into.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import QtQuick.Dialogs
import "sounds.js" as Sounds
import "screens.js" as Screens
import "scorecards.js" as Scorecards

KCM.SimpleKCM {
    id: page

    property string cfg_screens
    property alias cfg_poolMinVolume: poolVol.value
    property alias cfg_poolMinAvg: poolAvg.value
    property alias cfg_alertSound: sound.checked
    property alias cfg_soundPlayer: soundPlayer.text
    property alias cfg_timesLocal: timesLocal.checked
    property real cfg_valueCapMin
    property real cfg_screenPriceMin
    property real cfg_screenPriceMax
    // The scorecards, for the picker; edited on the Scorecards page.
    property string cfg_scorecards
    readonly property var cards: Scorecards.load({ scorecards: cfg_scorecards,
        screenPriceMin: cfg_screenPriceMin, screenPriceMax: cfg_screenPriceMax })
    // Read only to build the starting list the first time.
    property real cfg_runPct
    property int cfg_runWindow
    property real cfg_hodMinChange
    property real cfg_hodMinRvol
    property string cfg_runSound
    property string cfg_hodSound

    property var list: []
    property int sel: 0
    onSelChanged: currencyNote = ""
    readonly property var cur: list[sel] || null

    function loadCfg() {
        return { screens: cfg_screens, runPct: cfg_runPct, runWindow: cfg_runWindow,
                 screenPriceMin: cfg_screenPriceMin, screenPriceMax: cfg_screenPriceMax,
                 hodMinChange: cfg_hodMinChange, hodMinRvol: cfg_hodMinRvol,
                 runSound: cfg_runSound, hodSound: cfg_hodSound }
    }
    Component.onCompleted: {
        list = Screens.load(loadCfg())
        snapshot()
    }

    // ── saving without undoing the pop-up (see the top of this file) ──
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
        for (const k of c.keys()) {
            const p = "cfg_" + k
            if (!(p in page) || !(k in opened)) continue
            if (page[p] === opened[k]) page[p] = c[k]
            else if (k === "screens") page[p] = mergeScreens(opened[k], page[p], c[k])
        }
        if (cfg_screens !== JSON.stringify(list)) {
            const id = cur ? cur.id : ""
            list = Screens.load(loadCfg())
            const i = list.findIndex(s => s.id === id)
            sel = i >= 0 ? i : Math.max(0, Math.min(sel, list.length - 1))
        }
        snapshot()
    }
    // Three-way merge of the screens list: this page's edits win, but a
    // field (or filter) only the pop-up changed -- Score ≥, say -- keeps the
    // pop-up's value, and a screen the engine added meanwhile is kept.
    function mergeScreens(base, mine, theirs) {
        let b, m, t
        try {
            b = JSON.parse(base || "[]"); m = JSON.parse(mine || "[]"); t = JSON.parse(theirs || "[]")
        } catch (e) { return mine }
        if (!Array.isArray(m) || !Array.isArray(t)) return mine
        if (!Array.isArray(b)) b = []
        const byId = (l, id) => l.find(s => s && s.id === id)
        const same = (x, y) => JSON.stringify(x) === JSON.stringify(y)
        const take = (out, k, mineV, baseV, theirV) => {
            if (same(mineV, baseV) && !same(theirV, baseV)) {
                if (theirV === undefined) delete out[k]; else out[k] = theirV
            }
        }
        const out = m.map(s => {
            const bs = byId(b, s.id), ts = byId(t, s.id)
            if (!bs || !ts) return s
            const r = Object.assign({}, s)
            for (const k of new Set(Object.keys(bs).concat(Object.keys(ts))))
                if (k !== "filters") take(r, k, s[k], bs[k], ts[k])
            const bf = bs.filters || {}, tf = ts.filters || {}, f = Object.assign({}, s.filters || {})
            for (const k of new Set(Object.keys(bf).concat(Object.keys(tf))))
                take(f, k, (s.filters || {})[k], bf[k], tf[k])
            r.filters = f
            return r
        })
        for (const ts of t) if (ts && !byId(b, ts.id) && !byId(m, ts.id)) out.push(ts)
        return JSON.stringify(out)
    }

    function commit(l) {
        list = l
        cfg_screens = JSON.stringify(l)
    }
    function setFields(changes) {
        const l = list.slice()
        l[sel] = Object.assign({}, l[sel], changes)
        commit(l)
    }
    function setField(key, value) {
        const c = {}
        c[key] = value
        setFields(c)
    }
    function setFilter(key, value) {
        const f = Object.assign({}, cur.filters || {})
        if (value === null || value === undefined) delete f[key]
        else f[key] = value
        setField("filters", f)
    }
    function add(copyOf) {
        const s = copyOf ? JSON.parse(JSON.stringify(copyOf))
                         : { type: "running", runPct: 3, runWindow: 2, filters: {}, scorecard: "", sound: "" }
        s.id = Screens.newId()
        s.name = copyOf ? i18n("%1 copy", copyOf.name) : i18n("New screen")
        const l = list.slice()
        l.splice(sel + 1, 0, s)
        commit(l)
        sel = sel + 1
    }
    function remove() {
        if (list.length < 2) return
        const l = list.slice()
        l.splice(sel, 1)
        sel = Math.min(sel, l.length - 1)
        commit(l)
    }
    function move(d) {
        const to = sel + d
        if (to < 0 || to >= list.length) return
        const l = list.slice()
        const [s] = l.splice(sel, 1)
        l.splice(to, 0, s)
        commit(l)
        sel = to
    }
    // The type, with the row count that suits it: a ranked list shows 25,
    // a long-term value list 50, and the engine cuts at what is saved.
    function setType(t) {
        if (!cur || cur.type === t) return
        const c = { type: t }
        if (t === "ranked") c.rankCount = 25
        else if (t === "value") c.rankCount = 50
        setFields(c)
    }

    // A number typed into a box: "100K", "2.5M", "1,000,000 shares", "2B".
    // null when there is no number in it.
    function typedNum(text) {
        const m = String(text || "").replace(/,/g, "").match(/(-?\d+(?:\.\d+)?)\s*([kmb])?(?![a-z])/i)
        if (!m) return null
        const v = parseFloat(m[1]) * ({ k: 1e3, m: 1e6, b: 1e9 }[(m[2] || "").toLowerCase()] || 1)
        return isFinite(v) ? v : null
    }

    // What a filter box starts at when it is ticked while empty, so a tick
    // never saves 0 ("price at most 0" would hide every row).
    readonly property var seeds: ({
        priceMin: 1, priceMax: 20, changeMin: 10, changeMax: -10, gapMin: 5,
        volumeMin: 1e6, noVolChangeMin: 20, noVolBounceMin: 20, rvolMin: 2, rvol5Min: 200,
        capMin: 300e6, capMax: 2e9, floatMin: 1e6, floatMax: 20e6, shortMin: 10,
        newsHours: 24, scoreMin: 3, valueMin: 6, offHighMin: 15
    })
    // Settings-page wording for filters whose screens.js label is jargon.
    readonly property var filterLabels: ({
        noVolChangeMin: i18n("…or let through without volume if up at least"),
        noVolBounceMin: i18n("…or let through without volume if above today's low by")
    })
    function filterLabel(d) {
        if (Screens.isCrypto(cur)) return Screens.filterLabel(d, cur)
        return filterLabels[d.key] || d.label
    }
    readonly property var filterTips: ({
        priceMin: i18n("In the screen's currency."),
        priceMax: i18n("In the screen's currency."),
        changeMin: i18n("% change from yesterday's close."),
        changeMax: i18n("% change from yesterday's close."),
        gapMin: i18n("% between yesterday's close and today's open."),
        volumeMin: i18n("Shares traded today. Before the open many stocks have no volume figure; those are hidden unless one of the two options below lets them through."),
        noVolChangeMin: i18n("Used with Volume at least: a stock with too little or unknown volume still passes if it's up this much on the day."),
        noVolBounceMin: i18n("Used with Volume at least: lets a stock that is red on the day through once it has bounced this far (%) off today's low."),
        rvolMin: i18n("RVOL (relative volume): today's volume ÷ the stock's normal daily volume. 2× = twice the usual."),
        rvol5Min: i18n("Last 5 minutes' volume as a % of a normal 5 minutes (200% = twice the usual). Passes where it isn't known yet."),
        capMin: i18n("Market cap, in the screen's currency. Type 300M or 2B."),
        capMax: i18n("Market cap, in the screen's currency. Type 300M or 2B."),
        floatMin: i18n("Float: the shares available to trade. Looked up after a stock appears; the row hides once the figure is known and fails."),
        floatMax: i18n("Float: the shares available to trade. Looked up after a stock appears; the row hides once the figure is known and fails."),
        shortMin: i18n("Shares sold short, as a % of the float. Looked up after a stock appears."),
        newsHours: i18n("Hides the row once its news look-up shows no headline in this many hours."),
        scoreMin: i18n("How many of this screen's scorecard rules a row must pass (the same as Score ≥ in the pop-up)."),
        valueMin: i18n("Of the 8 checks from SEC filings (the Deep Value 8 scorecard)."),
        pfcfPass: i18n("Price is under 22.5× free cash flow (FCF: the cash the business actually generates)."),
        valuation: i18n("5-year P/E under 22.5, and price / free cash flow under 22.5."),
        offHighMin: i18n("How far (%) the price sits under its highest point of the last 52 weeks."),
        above50: i18n("Price above its 50-day average."),
        below200: i18n("The 50-day average hasn't yet crossed above the 200-day: an early recovery."),
        turningUp: i18n("The 50-day average has started rising."),
        aboveEma200: i18n("Price above its 200-day exponential moving average (EMA), a long-term trend line. The row stays hidden until the EMA is fetched. Stocks with under 200 sessions of history follow the setting under Settings → Tape.")
    })
    readonly property var cryptoTips: ({
        changeMin: i18n("% change over the last 24 hours."),
        changeMax: i18n("% change over the last 24 hours."),
        volumeMin: i18n("Value traded over the last 24 hours, in the screen's currency."),
        rvolMin: i18n("The last 24 hours' volume ÷ its 30-day daily average. 2× = twice the usual."),
        capMin: i18n("Market cap from CoinGecko, in the screen's currency. Type 300M or 2B."),
        capMax: i18n("Market cap from CoinGecko, in the screen's currency. Type 300M or 2B.")
    })
    function filterTip(key) {
        return (Screens.isCrypto(cur) && cryptoTips[key]) || filterTips[key] || ""
    }

    // Plays a sound for the preview buttons.
    P5Support.DataSource {
        id: player
        engine: "executable"
        connectedSources: []
        onNewData: source => disconnectSource(source)
    }
    function preview(path) {
        if (path) player.connectSource(Sounds.command(path, soundPlayer.text) + " # " + Date.now())
    }
    // ── changing a screen's currency ──
    // Its money filters (price, market cap, and a crypto screen's dollar
    // volume) are rescaled at today's rate, so "$1M volume" becomes about
    // ₿12.5 rather than ₿1,000,000. Rates from Yahoo's chart endpoint, which
    // needs no sign-in: "EUR=X" is euros per dollar, "BTC-USD" dollars per
    // bitcoin. The figures are converted first and the currency set with
    // them; without a rate nothing changes, so a dollar figure is never read
    // as bitcoin.
    property string currencyNote: ""
    function usdRate(key, done) {
        if (key === "USD") { done(1); return }
        const crypto = Screens.currencies.find(c => c.key === key).crypto
        const x = new XMLHttpRequest()
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE) return
            let p = NaN
            try { p = JSON.parse(x.responseText).chart.result[0].meta.regularMarketPrice } catch (e) {}
            done(p > 0 ? (crypto ? 1 / p : p) : NaN)
        }
        x.open("GET", "https://query1.finance.yahoo.com/v8/finance/chart/" + (crypto ? key + "-USD" : key + "=X") + "?range=1d&interval=1d")
        x.setRequestHeader("User-Agent", "Mozilla/5.0")
        x.send()
    }
    function round4(v) { return v === 0 ? 0 : Number(v.toPrecision(6)) }
    function changeCurrency(to) {
        const s = cur, from = Screens.currencyOf(s).key
        if (to === from) return
        const keys = ["priceMin", "priceMax", "capMin", "capMax"].concat(Screens.isCrypto(s) ? ["volumeMin"] : [])
        const set = keys.filter(k => typeof (s.filters || {})[k] === "number" && s.filters[k] > 0)
        if (!set.length) { setField("currency", to); currencyNote = ""; return }
        const id = s.id
        currencyNote = i18n("Fetching today's rate…")
        usdRate(from, rf => usdRate(to, rt => {
            const i = list.findIndex(x => x.id === id)
            if (i < 0) return
            if (!(rf > 0 && rt > 0)) {
                if (i === sel) {
                    currencyNote = i18n("Could not fetch today's rate, so the currency was left as %1. Try again in a moment.", from)
                    currencyBox.currentIndex = Qt.binding(() => currencyBox.indexNow())
                }
                return
            }
            const l = list.slice()
            const sc = Object.assign({}, l[i])
            const f = Object.assign({}, sc.filters)
            for (const k of set) f[k] = round4(f[k] / rf * rt)
            sc.filters = f
            sc.currency = to
            l[i] = sc
            commit(l)
            if (i === sel) currencyNote = i18n("Price, market-cap and volume filters converted to %1 at today's rate.", to)
        }))
    }

    // A sound file of the user's own, for the selected screen.
    FileDialog {
        id: soundFile
        nameFilters: [i18n("Sound files (*.oga *.ogg *.wav *.flac *.mp3)"), i18n("All files (*)")]
        onAccepted: {
            const path = decodeURIComponent(String(selectedFile).replace(/^file:\/\//, ""))
            page.setField("sound", path)
            page.preview(path)
        }
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // ── the market ──────────────────────────────────────────────────
        Kirigami.FormLayout {
            Layout.fillWidth: true
            Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Stocks to watch (shared by every stock screen)") }
            QQC2.SpinBox {
                id: poolVol
                Kirigami.FormData.label: i18n("Trading today at least:")
                from: 0; to: 10000000; stepSize: 50000
                editable: true
                validator: RegularExpressionValidator { regularExpression: /[^\d]*-?[\d.,]*\s*[kKmMbB]?[^\d]*/ }
                textFromValue: (v, locale) => i18n("%1 shares", Screens.fmtNum(v))
                valueFromText: (text, locale) => { const v = page.typedNum(text); return v === null ? poolVol.value : Math.round(v) }
                QQC2.ToolTip.text: i18n("A stock is watched if it has traded this many shares today, or averages the amount below. Lower numbers watch more stocks and use more data. Type 100K or 2M.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.SpinBox {
                id: poolAvg
                Kirigami.FormData.label: i18n("…or averaging at least:")
                from: 0; to: 10000000; stepSize: 50000
                editable: true
                validator: RegularExpressionValidator { regularExpression: /[^\d]*-?[\d.,]*\s*[kKmMbB]?[^\d]*/ }
                textFromValue: (v, locale) => i18n("%1 shares a day", Screens.fmtNum(v))
                valueFromText: (text, locale) => { const v = page.typedNum(text); return v === null ? poolAvg.value : Math.round(v) }
                QQC2.ToolTip.text: i18n("Average daily volume over the last 3 months. Type 300K or 1M.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.TextField {
                id: valueCap
                Kirigami.FormData.label: i18n("Long-term value lists, smallest company:")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                readonly property string stored: "$" + Screens.fmtNum(page.cfg_valueCapMin) + "+"
                text: stored
                onEditingFinished: {
                    const v = Screens.parseNum(text.replace("+", ""))
                    if (v > 0) page.cfg_valueCapMin = v
                    text = Qt.binding(() => valueCap.stored)
                }
                QQC2.ToolTip.text: i18n("In US dollars. Type 500M or 2B.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.CheckBox {
                id: sound
                Kirigami.FormData.label: i18n("Alert sounds:")
                text: i18n("Play alert sounds")
                QQC2.ToolTip.text: i18n("The speaker button in the pop-up switches this too.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.TextField {
                id: soundPlayer
                Kirigami.FormData.label: i18n("Sound player:")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                placeholderText: i18n("Automatic: pw-play, paplay, canberra-gtk-play or ffplay")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                QQC2.ToolTip.text: i18n("Leave empty to use whichever is installed. Otherwise a command, with %f where the sound file goes (e.g. aplay -q %f).")
            }
            QQC2.CheckBox {
                id: timesLocal
                Kirigami.FormData.label: i18n("Alert times:")
                text: i18n("In my own time zone")
                QQC2.ToolTip.text: i18n("Off shows New York time, as the exchanges do.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.WordWrap
                text: i18n("US-listed common stock at any price, through Yahoo — several thousand at these settings. All screens share one price check, so adding screens costs nothing extra. How often it runs is under Settings → Performance.")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }

        // ── the screens ─────────────────────────────────────────────────
        // ── which screen ────────────────────────────────────────────────
        // A picker row above the editor rather than a list beside it, so the
        // page holds together at any dialog width.
        Kirigami.Separator { Layout.fillWidth: true }
        // A Flow, so the buttons wrap onto a second line in a narrow dialog.
        Flow {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            QQC2.Label { text: i18n("Screen:"); height: picker.height; verticalAlignment: Text.AlignVCenter }
            QQC2.ComboBox {
                id: picker
                width: Kirigami.Units.gridUnit * 12
                model: page.list.map(s => s.on === false ? i18n("%1 (off)", s.name) : s.name)
                currentIndex: page.sel
                onActivated: index => page.sel = index
                QQC2.ToolTip.text: i18n("The screen edited below. \"(off)\" screens are kept here but hidden in the pop-up.")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.ToolButton { icon.name: "list-add"; text: i18n("Add"); onClicked: page.add(null)
                QQC2.ToolTip.text: i18n("Add a new Running Up screen after this one")
                QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
            QQC2.ToolButton { icon.name: "edit-copy"; text: i18n("Duplicate"); enabled: !!page.cur; onClicked: page.add(page.cur)
                QQC2.ToolTip.text: i18n("Copy this screen and its settings")
                QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
            QQC2.ToolButton { icon.name: "edit-delete"; text: i18n("Delete"); enabled: page.list.length > 1; onClicked: page.remove()
                QQC2.ToolTip.text: i18n("Delete this screen (Cancel undoes it before Apply)")
                QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
            // Three crypto screens to start from, once.
            QQC2.ToolButton {
                visible: !page.list.some(s => Screens.isCrypto(s))
                icon.name: "list-add"
                text: i18n("Add crypto screens")
                onClicked: { page.commit(page.list.concat(Screens.cryptoStarters())); page.sel = page.list.length - 3 }
                QQC2.ToolTip.text: i18n("Crypto Running Up, Crypto 24h High and Crypto Gainers, from Coinbase, around the clock")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            }
            QQC2.ToolButton { icon.name: "go-up"; enabled: page.sel > 0; onClicked: page.move(-1)
                QQC2.ToolTip.text: i18n("Move this screen's button left in the pop-up")
                QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
            QQC2.ToolButton { icon.name: "go-down"; enabled: page.sel < page.list.length - 1; onClicked: page.move(1)
                QQC2.ToolTip.text: i18n("Move this screen's button right in the pop-up")
                QQC2.ToolTip.visible: hovered; QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: screenForm.implicitHeight
            // ── the selected screen ─────────────────────────────────────
            Kirigami.FormLayout {
                id: screenForm
                width: parent.width
                visible: !!page.cur

                QQC2.CheckBox {
                    Kirigami.FormData.label: i18n("In the widget:")
                    text: i18n("Show and run this screen")
                    checked: !!page.cur && page.cur.on !== false
                    onToggled: page.setField("on", checked)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    QQC2.ToolTip.text: i18n("Off keeps this screen here but hides its button and stops it running. With no crypto screen on, crypto prices aren't checked.")
                }
                QQC2.CheckBox {
                    Kirigami.FormData.label: i18n("Themes (beta):")
                    visible: !!page.cur && page.cur.type !== "hunter"
                    text: i18n("Its stocks build the theme and sector heat")
                    checked: !!page.cur && Screens.feedsThemes(page.cur)
                    onToggled: page.setField("feedsThemes", checked)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    QQC2.ToolTip.text: i18n("Count this screen's stocks toward theme and sector heat (the coloured icons and the Theme Hunter). Off by default for ranked and value lists, whose large companies would drown out small-cap stories.")
                }
                QQC2.TextField {
                    id: nameField
                    Kirigami.FormData.label: i18n("Name:")
                    placeholderText: i18n("Shown on the screen's button")
                    readonly property string stored: page.cur ? page.cur.name : ""
                    text: stored
                    onEditingFinished: {
                        if (page.cur && text.trim() && text !== page.cur.name) page.setField("name", text.trim())
                        else text = Qt.binding(() => nameField.stored)
                    }
                    QQC2.ToolTip.text: i18n("Shown on the screen's button in the pop-up")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                QQC2.ComboBox {
                    Kirigami.FormData.label: i18n("Market:")
                    implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                    model: Screens.markets.map(m => m.name)
                    currentIndex: page.cur && Screens.isCrypto(page.cur) ? 1 : 0
                    onActivated: index => {
                        const c = { market: Screens.markets[index].key }
                        // No long-term value list for crypto: no filings to read.
                        if (index === 1 && page.cur.type === "value") { c.type = "running"; c.rankCount = undefined }
                        page.setFields(c)
                    }
                    QQC2.ToolTip.text: i18n("US stocks through Yahoo, or crypto pairs through Coinbase around the clock. Crypto has no long-term value lists, so a value list switched to crypto becomes Running Up.")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                QQC2.ComboBox {
                    id: currencyBox
                    Kirigami.FormData.label: i18n("Currency:")
                    implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                    readonly property var choices: Screens.currencies
                    function indexNow() { return Math.max(0, choices.findIndex(c => c.key === Screens.currencyOf(page.cur).key)) }
                    model: choices.map(c => c.key + " — " + c.name)
                    currentIndex: indexNow()
                    onActivated: index => page.changeCurrency(choices[index].key)
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    QQC2.ToolTip.text: i18n("Prices and market caps (and crypto volume) show in this currency, and the filters use it too. Changing it converts the price, cap and crypto-volume filters at today's rate; if the rate can't be fetched, the currency stays as it was. Stock volume stays in shares.")
                }
                QQC2.Label {
                    visible: page.currencyNote !== ""
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 20
                    wrapMode: Text.WordWrap
                    text: page.currencyNote
                    font: Kirigami.Theme.smallFont
                    color: Kirigami.Theme.neutralTextColor
                }
                QQC2.ComboBox {
                    Kirigami.FormData.label: i18n("Type:")
                    implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                    readonly property var choices: Screens.types.filter(t => !(Screens.isCrypto(page.cur) && t.key === "value"))
                    model: choices.map(t => t.name)
                    currentIndex: page.cur ? choices.findIndex(t => t.key === page.cur.type) : 0
                    onActivated: index => page.setType(choices[index].key)
                    QQC2.ToolTip.text: i18n("Running up: alerts when a price jumps fast. New high of day: alerts on each new daily high. Ranked list: a live top-N table. Long-term value list: companies scored on SEC filings. Theme Hunter: themes ranked by heat.")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                // Running up
                RowLayout {
                    visible: !!page.cur && page.cur.type === "running"
                    Kirigami.FormData.label: i18n("Alert when up:")
                    QQC2.TextField {
                        id: runPctField
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3.5
                        readonly property string stored: page.cur ? Screens.fmtNum(page.cur.runPct) : ""
                        text: stored
                        onEditingFinished: {
                            const v = Screens.parseNum(text)
                            if (v > 0 && v !== page.cur.runPct) page.setField("runPct", v)
                            else text = Qt.binding(() => runPctField.stored)
                        }
                        QQC2.ToolTip.text: runTip.text
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    QQC2.Label { text: i18n("% from its low, within") }
                    QQC2.SpinBox {
                        id: runWindowBox
                        from: 1; to: 10
                        editable: true
                        validator: RegularExpressionValidator { regularExpression: /[^\d]*-?[\d.,]*\s*[kKmMbB]?[^\d]*/ }
                        valueFromText: (text, locale) => { const v = page.typedNum(text); return v === null ? runWindowBox.value : Math.round(v) }
                        value: page.cur && page.cur.runWindow ? page.cur.runWindow : 2
                        onValueModified: page.setField("runWindow", value)
                        QQC2.ToolTip.text: runTip.text
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    QQC2.Label { text: i18n("min") }
                    QtObject {
                        id: runTip
                        readonly property string text: i18n("Alerts when the price is at least this % above its lowest point in the last N minutes, and at the highest point in that window.")
                    }
                }
                // Ranked
                RowLayout {
                    visible: !!page.cur && page.cur.type === "ranked"
                    Kirigami.FormData.label: i18n("Top:")
                    QQC2.SpinBox {
                        id: rankBox
                        from: 5; to: 100
                        editable: true
                        validator: RegularExpressionValidator { regularExpression: /[^\d]*-?[\d.,]*\s*[kKmMbB]?[^\d]*/ }
                        valueFromText: (text, locale) => { const v = page.typedNum(text); return v === null ? rankBox.value : Math.round(v) }
                        value: page.cur && page.cur.rankCount ? page.cur.rankCount : 25
                        onValueModified: page.setField("rankCount", value)
                        QQC2.ToolTip.text: rankTip.text
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    QQC2.Label { text: i18n("by") }
                    QQC2.ComboBox {
                        implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                        model: Screens.rankMeasures.map(m => m.name)
                        currentIndex: page.cur ? Math.max(0, Screens.rankMeasures.findIndex(m => m.key === (page.cur.rankBy || "change"))) : 0
                        onActivated: index => page.setField("rankBy", Screens.rankMeasures[index].key)
                        QQC2.ToolTip.text: rankTip.text
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    QQC2.ComboBox {
                        implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                        model: [i18n("highest first"), i18n("lowest first")]
                        currentIndex: page.cur && page.cur.rankLow ? 1 : 0
                        onActivated: index => page.setField("rankLow", index === 1)
                        QQC2.ToolTip.text: i18n("Highest first makes a top list (like Top Gainers); lowest first a bottom list (like Top Losers).")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    QtObject {
                        id: rankTip
                        readonly property string text: i18n("Shows the top N stocks by this measure. RVOL (relative volume) = today's volume compared with the stock's normal volume.")
                    }
                }

                RowLayout {
                    visible: !!page.cur && page.cur.type === "value"
                    Kirigami.FormData.label: i18n("Show up to:")
                    QQC2.SpinBox {
                        id: valueCountBox
                        from: 5; to: 200
                        editable: true
                        validator: RegularExpressionValidator { regularExpression: /[^\d]*-?[\d.,]*\s*[kKmMbB]?[^\d]*/ }
                        valueFromText: (text, locale) => { const v = page.typedNum(text); return v === null ? valueCountBox.value : Math.round(v) }
                        value: page.cur && page.cur.rankCount ? page.cur.rankCount : 50
                        onValueModified: page.setField("rankCount", value)
                        QQC2.ToolTip.text: i18n("How many companies to list, most checks passed first.")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    QQC2.Label { text: i18n("companies, most checks passed first") }
                }

                // A Theme Hunter reads the theme tally: no filters, scorecard or sound.
                readonly property bool hunterScreen: !!page.cur && page.cur.type === "hunter"
                QQC2.Label {
                    visible: screenForm.hunterScreen
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 20
                    wrapMode: Text.WordWrap
                    text: i18n("A Theme Hunter ranks themes and sectors by heat and lists the runners no theme claims. It has no filters, scorecard or sound; the readings are tuned under Settings → Themes.")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }
                Item { visible: !screenForm.hunterScreen; Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Filters") }
                Repeater {
                    model: Screens.filterDefs
                    RowLayout {
                        id: frow
                        required property var modelData
                        readonly property var value: page.cur && page.cur.filters ? page.cur.filters[modelData.key] : undefined
                        readonly property bool on: typeof value === "number"
                        readonly property bool flag: modelData.op === "flag"
                        readonly property string tip: page.filterTip(modelData.key)
                        // Fundamental and trend filters belong to long-term value lists.
                        visible: !!page.cur && !screenForm.hunterScreen && (!modelData.value || page.cur.type === "value")
                                 && !(Screens.isCrypto(page.cur) && Screens.stocksOnly.indexOf(modelData.key) >= 0)
                        Kirigami.FormData.label: page.filterLabel(modelData) + ":"
                        QQC2.CheckBox {
                            checked: frow.on
                            // Ticked with an empty or unreadable box: the
                            // filter's starting value, never 0.
                            onToggled: {
                                if (!checked) { page.setFilter(frow.modelData.key, null); return }
                                if (frow.flag) { page.setFilter(frow.modelData.key, 1); return }
                                const v = Screens.parseNum(field.text)
                                const seed = page.seeds[frow.modelData.key]
                                page.setFilter(frow.modelData.key, v !== null ? v : (seed !== undefined ? seed : 1))
                            }
                            QQC2.ToolTip.text: frow.tip
                            QQC2.ToolTip.visible: hovered && frow.tip !== ""
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.TextField {
                            id: field
                            visible: !frow.flag
                            enabled: frow.on
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            readonly property string stored: frow.on ? Screens.fmtNum(frow.value) : ""
                            text: stored
                            placeholderText: frow.modelData.unit === "shares" || frow.modelData.key.startsWith("cap") ? "10M" : "0"
                            onEditingFinished: {
                                const v = Screens.parseNum(text)
                                if (v !== null && v !== frow.value) page.setFilter(frow.modelData.key, v)
                                else text = Qt.binding(() => field.stored)
                            }
                            QQC2.ToolTip.text: frow.tip
                            QQC2.ToolTip.visible: hovered && frow.tip !== ""
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        QQC2.Label { visible: !frow.flag; text: Screens.filterUnit(frow.modelData, page.cur) || ""; opacity: 0.7 }
                    }
                }
                QQC2.Label {
                    visible: !screenForm.hunterScreen
                    Layout.fillWidth: true
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 20
                    wrapMode: Text.WordWrap
                    text: Screens.isCrypto(page.cur)
                          ? i18n("Numbers take K, M and B (10M). Crypto volume is in dollars over the last 24 hours; change is over the last 24 hours; market cap comes from CoinGecko.")
                          : i18n("Numbers take K, M and B (10M). Float, short interest and news are looked up after a stock appears; those filters let a row through until its figure arrives, then hide it if it fails. Yes/no checks, like the 200-day EMA, hide a row until the figure is known. Whether a stock with under 200 sessions of history passes the EMA check is set under Settings → Tape, and applies here too.")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }

                Item { visible: !screenForm.hunterScreen; Kirigami.FormData.isSection: true; Kirigami.FormData.label: i18n("Scorecard and sound") }
                QQC2.ComboBox {
                    visible: !screenForm.hunterScreen
                    Kirigami.FormData.label: i18n("Scorecard:")
                    implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                    model: [i18n("None")].concat(page.cards.map(c => c.name))
                    currentIndex: {
                        if (!page.cur || !page.cur.scorecard) return 0
                        const c = Scorecards.find(page.cards, page.cur.scorecard)
                        return c ? page.cards.indexOf(c) + 1 : 0
                    }
                    onActivated: index => page.setField("scorecard", index === 0 ? "" : page.cards[index - 1].id)
                    QQC2.ToolTip.text: i18n("Scores each row against this scorecard and adds the Score column. Edit scorecards on the Scorecards page (press Apply there before choosing a new one here).")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
                // Ranked and long-term value lists never alert, so no sound.
                RowLayout {
                    visible: !!page.cur && page.cur.type !== "ranked" && page.cur.type !== "value" && !screenForm.hunterScreen
                    Kirigami.FormData.label: i18n("Alert sound:")
                    QQC2.ComboBox {
                        // The built-in sounds, the screen's own file if it has
                        // one, and a way to choose a file.
                        readonly property string own: page.cur && page.cur.sound && !Sounds.list.some(s => s.path === page.cur.sound) ? page.cur.sound : ""
                        implicitContentWidthPolicy: QQC2.ComboBox.WidestText
                        model: Sounds.list.map(s => s.name).concat(own ? [i18n("Own: %1", Sounds.name(own))] : [], [i18n("Choose a file…")])
                        currentIndex: !page.cur ? 0 : own ? Sounds.list.length
                                    : Math.max(0, Sounds.list.findIndex(s => s.path === (page.cur.sound || "")))
                        onActivated: index => {
                            if (index === count - 1) { soundFile.open(); return }
                            if (index >= Sounds.list.length) return
                            page.setField("sound", Sounds.list[index].path)
                            page.preview(Sounds.list[index].path)
                        }
                        QQC2.ToolTip.text: i18n("Sound played when this screen alerts")
                        QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                    QQC2.Button {
                        icon.name: "media-playback-start"
                        enabled: !!page.cur && !!page.cur.sound
                        onClicked: page.preview(page.cur.sound)
                        QQC2.ToolTip.text: i18n("Play this sound"); QQC2.ToolTip.visible: hovered
                        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    }
                }
            }
        }
    }
}
