"""
Market lists and per-symbol facts scraped from public pages:

  get_premarket_gainers()  stockanalysis.com's premarket gainers
  get_finviz(ticker)       float, short interest, relative volume and recent
                           headlines from the symbol's Finviz quote page
  fetch(url)               the shared GET, with browser headers and backoff
"""

import re
import sys
import time
import urllib.request
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")

ET = ZoneInfo("America/New_York")


def fetch(url, retries=3, timeout=25):
    """GET with a browser UA and simple backoff."""
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={
                "User-Agent": UA,
                "Accept": "text/html,application/json,*/*",
                "Accept-Language": "en-US,en;q=0.9",
            })
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read().decode("utf-8", errors="ignore")
        except Exception as e:
            if attempt == retries - 1:
                print(f"  ! fetch failed {url}: {e}", file=sys.stderr)
                return ""
            time.sleep(2 * (attempt + 1))
    return ""


def _field(block, key, numeric=True):
    """Pull one key out of a JS object literal block."""
    if numeric:
        m = re.search(rf'\b{key}:(-?[\d.eE+]+)', block)
        if not m:
            return None
        try:
            return float(m.group(1))
        except ValueError:
            return None
    m = re.search(rf'\b{key}:"((?:[^"\\]|\\.)*)"', block)
    return m.group(1).replace('\\"', '"') if m else None


def get_premarket_gainers():
    """
    Extract the gainer records from the SvelteKit payload embedded in the page.

    Parsed record-by-record rather than as one JSON blob: the payload is JS object
    notation (unquoted keys, occasional undefined/nulls) and a single malformed
    value would otherwise throw away the whole list.
    """
    html = fetch("https://stockanalysis.com/markets/premarket/gainers/")
    if not html:
        return []

    blocks = re.findall(r'\{no:\d+,[^{}]*\}', html)
    if not blocks:
        print("  ! could not locate embedded data payload", file=sys.stderr)
        return []

    out, seen = [], set()
    for b in blocks:
        tkr = _field(b, "s", numeric=False)
        if not tkr or tkr in seen:
            continue
        seen.add(tkr)
        out.append({
            "s": tkr,
            "n": _field(b, "n", numeric=False) or "",
            "premarketChangePercent": _field(b, "premarketChangePercent"),
            "premarketPrice": _field(b, "premarketPrice"),
            "premarketVolume": _field(b, "premarketVolume"),
            "marketCap": _field(b, "marketCap"),
        })
    return out


def parse_num(s):
    """Finviz numbers: '125.06M', '19.90%', '2,115.66', '-'."""
    if not s or s.strip() in ("-", "", "N/A"):
        return None
    s = s.strip().replace(",", "").replace("%", "")
    mult = 1
    if s and s[-1] in "KMBT":
        mult = {"K": 1e3, "M": 1e6, "B": 1e9, "T": 1e12}[s[-1]]
        s = s[:-1]
    try:
        return float(s) * mult
    except ValueError:
        return None


FINVIZ_FIELDS = ["Shs Float", "Shs Outstand", "Short Float", "Short Ratio",
                 "Market Cap", "Rel Volume", "Avg Volume", "Volume", "Price"]

COUNTRIES = ("USA|China|Hong Kong|Singapore|Israel|Canada|Cayman Islands|Germany|"
             "Netherlands|United Kingdom|Malaysia|Taiwan|South Korea|Japan|Australia|"
             "India|Brazil|Greece|Ireland|Switzerland|France|Sweden|Norway|Denmark")


def get_finviz(ticker):
    """Scrape float, short interest, country, sector from a Finviz quote page."""
    html = fetch(f"https://finviz.com/quote.ashx?t={ticker}")
    if not html:
        return {}

    cells = re.findall(r"<td[^>]*>(.*?)</td>", html, re.S)
    clean = []
    for c in cells:
        t = re.sub(r"<[^>]+>", "", c)
        for a, b in (("&amp;", "&"), ("&nbsp;", " "), ("&#39;", "'"), ("&quot;", '"')):
            t = t.replace(a, b)
        clean.append(t.strip())

    out = {}
    for i, c in enumerate(clean):
        if c in FINVIZ_FIELDS and i + 1 < len(clean) and c not in out:
            out[c] = clean[i + 1]

    cm = re.search(rf"\b({COUNTRIES})\b", html)
    out["Country"] = cm.group(1) if cm else ""

    out["news"] = parse_finviz_news(html)

    sm = re.search(r'screener\.ashx\?v=\d+&f=sec_[^"]*"[^>]*>([^<]+)<', html)
    out["Sector"] = sm.group(1).strip() if sm else ""
    return out


# Wire services that carry company press releases. Finviz also lists articles and
# commentary (Yahoo, Moby, GuruFocus...); those are left out on purpose.
PR_WIRES = ("newswire", "business wire", "accesswire", "newsfile", "mediawire")


def parse_finviz_news(html):
    """
    News rows from a Finviz quote page, as dicts with an ET datetime.

    Finviz stamps rows in ET and only prints the date on the first row of each
    day ("Sep-16-26 04:15PM", or "Today 06:30AM"); later rows carry just the time.
    Returns None when the news table is missing, so a failed page is never read
    as "no news".
    """
    i = html.find('id="news-table"')
    if i < 0:
        return None
    j = html.find("</table>", i)
    today = datetime.now(ET).date()
    out, day = [], None
    for tr in re.findall(r"<tr.*?</tr>", html[i:j], re.S):
        tds = re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)
        a = re.search(r'<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>', tr, re.S)
        src = re.search(r"<span>\((.*?)\)</span>", tr)
        if not tds or not a:
            continue
        stamp = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", tds[0])).strip()
        parts = stamp.split(" ")
        try:
            if len(parts) == 2:
                if parts[0] == "Today":
                    day = today
                elif parts[0] == "Yesterday":
                    day = today - timedelta(days=1)
                else:
                    day = datetime.strptime(parts[0], "%b-%d-%y").date()
            t = datetime.strptime(parts[-1], "%I:%M%p").time()
        except ValueError:
            continue
        if day is None:
            continue
        title = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", a.group(2))).strip()
        for x, y in (("&amp;", "&"), ("&#39;", "'"), ("&quot;", '"'), ("&nbsp;", " ")):
            title = title.replace(x, y)
        url = a.group(1)
        if url.startswith("/"):
            url = "https://finviz.com" + url
        out.append({
            "dt": datetime.combine(day, t, tzinfo=ET),
            "source": src.group(1) if src else "",
            "title": title,
            "url": url,
        })
    return out
