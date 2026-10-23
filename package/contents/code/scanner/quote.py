"""
One stock's quote (price, name, share count) from CNBC's public quote
service, cached for five minutes.
"""

import json
import sys
import urllib.parse

import cache

UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")

URL = ("https://quote.cnbc.com/quote-html-webservice/restQuote/symbolType/symbol"
       "?symbols={sym}&requestMethod=itv&noform=1&partnerId=2&fund=1"
       "&exthrs=1&output=json")

SUFFIX = {"K": 1e3, "M": 1e6, "B": 1e9, "T": 1e12}


def _num(s):
    """'98.874B' / '397.50M' / '248.74' / '1,234.5' -> float, or None."""
    if s is None:
        return None
    s = str(s).strip().replace(",", "").replace("$", "").replace("%", "")
    if not s or s in ("-", "--", "N/A", "UNCH"):
        return None
    mult = 1.0
    if s[-1].upper() in SUFFIX:
        mult = SUFFIX[s[-1].upper()]
        s = s[:-1]
    try:
        return float(s) * mult
    except ValueError:
        return None


def get(ticker):
    """Quote dict, or None.

    Keys: price, change_pct, mcap, shares, name, pe, fpe, eps, state.
    """
    sym = ticker.upper().strip()
    try:
        body = cache.fetch(URL.format(sym=urllib.parse.quote(sym)),
                           cache.TTL_QUOTE,
                           headers={"User-Agent": UA,
                                    "Accept": "application/json"},
                           timeout=20)
        d = json.loads(body)
        q = d["FormattedQuoteResult"]["FormattedQuote"][0]
    except Exception as e:
        print(f"  ! quote failed for {sym}: {e}", file=sys.stderr)
        return None

    if q.get("code") not in (0, "0", None):
        return None
    price = _num(q.get("last"))
    if price is None:
        return None
    return {
        "symbol": q.get("symbol", sym),
        # Day change as a percent. Needed by the rule check, which must not
        # fall back to Finviz -- its Change column is not among the fields
        # parsed there, so it silently read as None and failed the 10% pillar
        # for a stock that closed +230%.
        "change_pct": _num((q.get("change_pct") or "").replace("+", "")),
        "name": q.get("name") or q.get("shortName") or sym,
        "price": price,
        "mcap": _num(q.get("mktcapView")),
        "shares": _num(q.get("sharesout")),
        "pe": _num(q.get("pe")),
        "fpe": _num(q.get("fpe")),
        "eps": _num(q.get("eps")),
        "state": q.get("curmktstatus", ""),
    }
