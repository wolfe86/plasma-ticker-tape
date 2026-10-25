// Yahoo symbols as TradingView names them, and the chart addresses.
//
// Stocks and ETFs are the same on both ("AAPL"; TradingView finds the
// exchange). Indices, currencies, futures and crypto pairs are not: Yahoo's
// "^GSPC" is TradingView's "SP:SPX", "BTC-USD" is a Coinbase pair, "EUR=X"
// (euros per dollar) is the USD/EUR rate. Anything not known here goes over
// as typed, without Yahoo's "^", and TradingView's own search box can fix it.
.pragma library

var known = {
    "^GSPC": "SP:SPX", "^SPX": "SP:SPX", "^IXIC": "NASDAQ:IXIC", "^NDX": "NASDAQ:NDX", "^DJI": "DJ:DJI",
    "^RUT": "TVC:RUT", "^SOX": "NASDAQ:SOX", "^VIX": "CBOE:VIX", "^TNX": "TVC:TNX", "^FTSE": "TVC:UKX",
    "^GDAXI": "XETR:DAX", "^N225": "TVC:NI225", "^HSI": "TVC:HSI", "DX-Y.NYB": "TVC:DXY",
    "ES=F": "CME_MINI:ES1!", "NQ=F": "CME_MINI:NQ1!", "YM=F": "CBOT_MINI:YM1!", "RTY=F": "CME_MINI:RTY1!",
    "CL=F": "NYMEX:CL1!", "NG=F": "NYMEX:NG1!", "GC=F": "COMEX:GC1!", "SI=F": "COMEX:SI1!", "HG=F": "COMEX:HG1!",
    "ZN=F": "CBOT:ZN1!", "BZ=F": "NYMEX:BB1!"
}

function symbol(yahoo) {
    const s = String(yahoo || "").toUpperCase()
    if (known[s]) return known[s]
    // A coin against the dollar: Coinbase's pair.
    let m = s.match(/^([A-Z0-9]{1,15})-USD$/)
    if (m) return "COINBASE:" + m[1] + "USD"
    m = s.match(/^([A-Z0-9]{1,15})-(EUR|GBP|USDT|USDC|BTC|ETH)$/)
    if (m) return "COINBASE:" + m[1] + m[2]
    // "EURUSD=X" is the pair as written; "EUR=X" is dollars into euros.
    m = s.match(/^([A-Z]{6})=X$/)
    if (m) return "FX:" + m[1]
    m = s.match(/^([A-Z]{3})=X$/)
    if (m) return "FX_IDC:USD" + m[1]
    // Class shares: Yahoo's BRK-B is TradingView's BRK.B.
    if (/^[A-Z]{1,5}-[A-Z]$/.test(s)) return s.replace("-", ".")
    return s.replace(/^\^/, "")
}

// A bar size key from the chart's buttons ("1m", "5m", "1h", "1D"...) as
// TradingView's interval: minutes as a number, or D / W.
function interval(key) {
    const k = String(key || "")
    const m = k.match(/^(\d+)m$/)
    if (m) return m[1]
    if (k === "1h") return "60"
    return ({ "1D": "5", "5D": "15", "1M": "60", "6M": "D", "1Y": "D", "5Y": "W" })[k] || "D"
}

// `layout`: a saved chart layout's id (the part after /chart/ in its
// address), so a window reopens its own layout -- which TradingView autosaves.
function pageUrl(yahoo, key, layout) {
    return "https://www.tradingview.com/chart/" + (layout ? encodeURIComponent(layout) + "/" : "") + "?symbol=" + encodeURIComponent(symbol(yahoo))
         + "&interval=" + encodeURIComponent(interval(key))
}

// JavaScript that switches the open chart page to another symbol and bar
// size in place, through the page's own TradingViewApi (checked
// 2026-10-25): no reload, so no "leave this page?" prompt and nothing on the
// chart is lost. Returns "ok", or "no" when the page has no such API.
function switchScript(yahoo, key) {
    return "(function(){try{var c=window.TradingViewApi.activeChart();c.setSymbol(" + JSON.stringify(symbol(yahoo))
         + ");c.setResolution(" + JSON.stringify(interval(key)) + ");return 'ok'}catch(e){return 'no'}})()"
}

// The same for the bar size alone: an unlinked window whose symbol was
// changed in TradingView's own search keeps it.
function resolutionScript(key) {
    return "(function(){try{window.TradingViewApi.activeChart().setResolution(" + JSON.stringify(interval(key))
         + ");return 'ok'}catch(e){return 'no'}})()"
}

// The embeddable chart, which needs no account. `dark` follows the desktop.
function widgetHtml(yahoo, key, dark) {
    const cfg = {
        autosize: true, symbol: symbol(yahoo), interval: interval(key), timezone: "America/New_York",
        theme: dark ? "dark" : "light", style: "1", locale: "en", allow_symbol_change: true,
        withdateranges: true, hide_side_toolbar: false, details: true, container_id: "tv"
    }
    return "<!doctype html><html><head><meta charset='utf-8'><style>html,body,#tv{margin:0;height:100%;background:"
         + (dark ? "#131722" : "#ffffff") + "}</style></head><body><div id='tv'></div>"
         + "<script src='https://s3.tradingview.com/tv.js'></script>"
         + "<script>new TradingView.widget(" + JSON.stringify(cfg) + ");</script></body></html>"
}
