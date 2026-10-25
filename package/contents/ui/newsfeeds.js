// News sources the user adds in Settings → Data: any RSS or Atom feed, or a
// JSON API with a field map, each with an optional request header for a
// paid feed's key. Fetched from the widget itself (QML's XMLHttpRequest), so
// a key goes only in the request header -- never on a command line, where
// other users of the machine could read it.
//
// A source, as stored in the `newsSources` setting (a JSON array):
//   { name, url, kind: "rss" | "json", on: bool,
//     header: "Name: value" or "",
//     map: { items, title, time, link, tickers, source } }  -- json only;
//          dotted paths into the response ("data.items", "headline")
//
// Every item comes out as {title, url, source, time (ms), tickers: [...], image}.
.pragma library

// Feed text to plain text. Entities are decoded first and tags come off
// last, so an escaped "&lt;img src=...&gt;" in a title is removed rather
// than turned into live markup (2026-10-24: the other order made it an
// <img> the widget would load). "&amp;lt;" still ends as the text "&lt;".
function stripTags(s) {
    return String(s || "")
        .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
        .replace(/&(lt|gt|quot|apos|nbsp|amp|#\d+|#x[0-9a-f]+);/gi, (m, e) => {
            const k = e.toLowerCase()
            if (k[0] === "#") {
                const n = k[1] === "x" ? parseInt(k.slice(2), 16) : +k.slice(1)
                return n > 0 && n < 0x110000 ? String.fromCodePoint(n) : ""
            }
            return { lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", amp: "&" }[k]
        })
        .replace(/<[^>]*>/g, "")
        .replace(/\s+/g, " ").trim()
}
// Pictures come from the web only: no file:, data: or other schemes.
function webUrl(u) { return /^https?:\/\//i.test(String(u || "")) ? String(u) : "" }
// A feed reply past this is abandoned rather than parsed (2026-10-24).
var maxReply = 8 * 1024 * 1024

// RFC 822 ("Fri, 23 Oct 2026 14:05:00 -0400" or "... GMT"), ISO 8601, or
// epoch seconds or milliseconds. NaN when it cannot be placed in time.
var months = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 }
var zones = { gmt: 0, ut: 0, utc: 0, z: 0, est: -300, edt: -240, cst: -360, cdt: -300, mst: -420, mdt: -360, pst: -480, pdt: -420 }
function parseTime(v) {
    if (typeof v === "number") return v < 1e12 ? v * 1000 : v
    const s = String(v || "").trim()
    if (!s) return NaN
    if (/^\d{9,13}$/.test(s)) return parseTime(+s)
    const m = s.match(/^(?:\w{3},\s*)?(\d{1,2})\s+(\w{3})\w*\s+(\d{2,4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Za-z]{1,3})?/)
    if (m) {
        const mon = months[m[2].toLowerCase()]
        if (mon === undefined) return NaN
        let y = +m[3]
        if (y < 100) y += 2000
        let off = 0
        const z = m[7] || "GMT"
        if (/^[+-]\d{4}$/.test(z)) off = (z[0] === "-" ? -1 : 1) * (+z.slice(1, 3) * 60 + +z.slice(3, 5))
        else off = zones[z.toLowerCase()] || 0
        return Date.UTC(y, mon, +m[1], +m[4], +m[5], +(m[6] || 0)) - off * 60000
    }
    const t = Date.parse(s)
    return isFinite(t) ? t : NaN
}

// Tickers a headline names. Only forms that are unambiguous in a headline:
// $AAPL, an exchange prefix "(NASDAQ: AAPL)", or a bare "(AAPL)" that is
// not one of the capitalised words headlines put in brackets.
var notTickers = ["CEO", "CFO", "COO", "CTO", "FDA", "SEC", "FTC", "DOJ", "EPA", "AI", "ETF", "IPO", "USD", "EPS",
                  "GDP", "CPI", "PPI", "FOMC", "FED", "ECB", "BOE", "BOJ", "OPEC", "EU", "UK", "US", "USA", "PDF",
                  "AM", "PM", "ET", "PT", "EST", "EDT", "Q1", "Q2", "Q3", "Q4", "FY", "YOY", "QOQ", "NYSE", "LLC",
                  "INC", "LTD", "PLC", "ADR", "ADS", "ATM", "M&A", "R&D", "ESG", "API", "LNG", "EV", "IT"]
function tickersIn(text, exchangeOnly) {
    const out = []
    const add = s => { s = s.toUpperCase(); if (out.indexOf(s) < 0 && notTickers.indexOf(s) < 0) out.push(s) }
    const t = String(text || "")
    let m
    const dollar = /\$([A-Za-z]{1,6})\b/g
    while (!exchangeOnly && (m = dollar.exec(t))) add(m[1])
    const exch = /\((?:NASDAQ|NYSE(?:\s*American|\s*Arca|\s*MKT)?|AMEX|OTC(?:QB|QX|\s*Markets)?|CBOE|TSX(?:V)?)\s*:\s*([A-Za-z.]{1,6})\)/gi
    while ((m = exch.exec(t))) add(m[1])
    const bare = /\(([A-Z]{2,5})\)/g
    while (!exchangeOnly && (m = bare.exec(t))) add(m[1])
    return out
}

// <item> (RSS) and <entry> (Atom).
function parseXml(text, sourceName) {
    const out = []
    const body = String(text || "")
    const blocks = body.match(/<item[\s>][\s\S]*?<\/item>/g) || body.match(/<entry[\s>][\s\S]*?<\/entry>/g) || []
    for (const b of blocks) {
        const tag = name => { const m = b.match(new RegExp("<" + name + "(?:\\s[^>]*)?>([\\s\\S]*?)</" + name + ">")); return m ? m[1] : "" }
        const title = stripTags(tag("title"))
        let link = stripTags(tag("link"))
        if (!link) { const m = b.match(/<link[^>]*href="([^"]+)"/); link = m ? m[1] : "" }
        const time = parseTime(stripTags(tag("pubDate") || tag("published") || tag("updated") || tag("dc:date")))
        if (!title || !isFinite(time)) continue
        const cats = (b.match(/<category[^>]*domain="[^"]*\/symbol\/([A-Za-z.\-]{1,10})"/g) || [])
                         .map(c => c.replace(/.*\/symbol\/([^"]+)".*/, "$1").toUpperCase())
            .concat((b.match(/<category[^>]*>[\s\S]*?<\/category>/g) || []).map(c => stripTags(c)))
            .concat((b.match(/<category[^>]*term="([^"]+)"/g) || []).map(c => c.replace(/.*term="([^"]+)".*/, "$1")))
            .filter(c => /^\$?[A-Z]{1,6}$/.test(c)).map(c => c.replace("$", ""))
        // Press releases name the ticker in the body, "(NASDAQ: ACME)", not the
        // headline; only that unambiguous form is read from the body.
        const tickers = tickersIn(title)
        for (const c of cats.concat(tickersIn(stripTags(tag("description") || tag("summary") || tag("content")), true)))
            if (tickers.indexOf(c) < 0) tickers.push(c)
        out.push({ title: title, url: link, source: sourceName, time: time, tickers: tickers, image: imageIn(b) })
    }
    return out
}

// A feed item's picture: media:content or media:thumbnail, an image
// enclosure, or the first <img> in its description. "" when there is none.
function imageIn(b) {
    const m = b.match(/<media:(?:content|thumbnail)[^>]*url="([^"]+)"/)
           || b.match(/<enclosure[^>]*url="([^"]+)"[^>]*type="image/)
           || b.match(/<enclosure[^>]*type="image[^"]*"[^>]*url="([^"]+)"/)
           || b.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').match(/<img[^>]*src="(https?:[^"]+)"/)
    return m ? webUrl(m[1].replace(/&amp;/g, "&")) : ""
}

// An article's preview picture, from its page's og:image (or twitter:image)
// -- what a link shows when shared. Only the top of the page is read: the
// request is dropped as soon as the tag or the end of <head> is seen, or
// after 400 KB. `done(url)`, "" when there is none. Returns {cancel()}.
function pageImage(url, done) {
    const x = new XMLHttpRequest()
    let finished = false
    const finish = v => { if (finished) return; finished = true; done(v); try { x.abort() } catch (e) {} }
    const look = () => {
        const t = x.responseText || ""
        const m = t.match(/<meta[^>]+(?:property|name)=["'](?:og:image|twitter:image)(?::src)?["'][^>]*content=["']([^"']+)["']/i)
               || t.match(/<meta[^>]+content=["']([^"']+)["'][^>]*(?:property|name)=["'](?:og:image|twitter:image)["']/i)
        if (m) return finish(webUrl(m[1].replace(/&amp;/g, "&")))
        if (t.indexOf("</head>") >= 0 || t.length > 400000) return finish("")
    }
    x.onreadystatechange = () => {
        if (x.readyState === XMLHttpRequest.LOADING) look()
        else if (x.readyState === XMLHttpRequest.DONE) { look(); finish("") }
    }
    x.open("GET", url)
    x.setRequestHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36")
    x.send()
    // A page that never answers is given up by the caller's watchdog.
    return { cancel: () => finish("") }
}

function path(obj, p) {
    if (!p) return undefined
    let v = obj
    for (const k of String(p).split(".")) { if (v === null || v === undefined) return undefined; v = v[k] }
    return v
}
function parseJson(text, sourceName, map) {
    let obj
    try { obj = JSON.parse(text) } catch (e) { return [] }
    const m = map || {}
    const list = m.items ? path(obj, m.items) : obj
    if (!Array.isArray(list)) return []
    const out = []
    for (const it of list) {
        const title = stripTags(path(it, m.title || "title"))
        const time = parseTime(path(it, m.time || "time"))
        if (!title || !isFinite(time)) continue
        let tk = path(it, m.tickers || "tickers")
        if (typeof tk === "string") tk = tk.split(/[,\s]+/)
        tk = (Array.isArray(tk) ? tk : []).map(x => String(typeof x === "object" && x ? (x.symbol || x.ticker || x.name || "") : x)
                                                           .toUpperCase().replace("$", "")).filter(x => /^[A-Z][A-Z0-9.\-]{0,9}$/.test(x))
        for (const x of tickersIn(title)) if (tk.indexOf(x) < 0) tk.push(x)
        const im = path(it, m.image || "image")
        out.push({ title: title, url: String(path(it, m.link || "url") || ""),
                   source: String(path(it, m.source || "") || sourceName), time: time, tickers: tk,
                   image: typeof im === "string" && /^https?:\/\//i.test(im) ? im : "" })
    }
    return out
}

function parse(source, text) {
    return source.kind === "json" ? parseJson(text, source.name, source.map) : parseXml(text, source.name)
}

function load(cfg) {
    try {
        const l = JSON.parse(cfg.newsSources || "[]")
        if (Array.isArray(l)) return l
    } catch (e) {}
    return []
}

// "https://a.example:8443/x" -> "https://a.example:8443", lower-cased.
function originOf(u) {
    const m = String(u || "").match(/^([a-z][a-z0-9+.\-]*:\/\/[^\/?#]*)/i)
    return m ? m[1].toLowerCase() : ""
}

// One source's request, header and all. `done(items, error)`.
// A header (a paid feed's key) goes only over https, and only to the
// source's own address: a reply that was redirected to another site is
// dropped, since the request that followed the redirect may have carried
// the header there (2026-10-24).
function fetch(source, done) {
    const x = new XMLHttpRequest()
    const h = String(source.header || "")
    const i = h.indexOf(":")
    if (i > 0 && !/^https:\/\//i.test(String(source.url || ""))) {
        done([], "a source with a header needs an https:// address")
        return x
    }
    let finished = false
    const finish = (items, err) => { if (finished) return; finished = true; done(items, err) }
    x.onreadystatechange = () => {
        if (x.readyState === XMLHttpRequest.LOADING) {
            if ((x.responseText || "").length > maxReply) { finish([], "reply too large"); x.abort() }
            return
        }
        if (x.readyState !== XMLHttpRequest.DONE) return
        if (x.status < 200 || x.status >= 300) { finish([], "HTTP " + x.status); return }
        const landed = x.responseURL
        if (i > 0 && landed && originOf(landed) !== originOf(source.url)) {
            finish([], "redirected to another site; not used")
            return
        }
        if ((x.responseText || "").length > maxReply) { finish([], "reply too large"); return }
        const items = parse(source, x.responseText)
        finish(items, items.length ? "" : "no items with a title and a time")
    }
    x.open("GET", source.url)
    x.setRequestHeader("User-Agent", "Mozilla/5.0")
    if (i > 0) x.setRequestHeader(h.slice(0, i).trim(), h.slice(i + 1).trim())
    x.send()
    return x
}

// A crypto pair ("BTC-USD") is named in headlines by its base ("BTC").
function matches(item, sym) {
    const base = sym.replace(/-USD$/, "")
    return item.tickers.indexOf(sym) >= 0 || item.tickers.indexOf(base) >= 0
}
