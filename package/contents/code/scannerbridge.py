#!/usr/bin/env python3
"""
Bridge from the Plasma Ticker Tape widget to its scanner (contents/code/scanner/
by default, or the folder set in Settings → Data).

The widget runs this through Plasma's "executable" engine and reads one line
of JSON from stdout. The scanner's settings arrive in a JSON file only this
user can read, named by MARKET_TICKER_SETTINGS (see load_settings), and are
handed on as environment variables; see scanner/settings.py. A manual run
can export the variables instead.

  premarket          stockanalysis.com's premarket gainers. The site answers
                     plain requests with a Cloudflare challenge (2026-10-22);
                     the scanner's fetch, with fuller browser headers, gets
                     through.
  afterhours         The same site's after-hours gainers (its URL is
                     /markets/afterhours/gainers/, checked 2026-10-22).
  prelevels SYM [..] Per symbol, today's premarket high, low and share
                     volume from Nasdaq's extended-trading page.
  stocks SYM [SYM..] Per symbol, from the symbol's Finviz page: float, short
                     float, relative volume, and the newest headline -- plus
                     whether a press-wire release landed in the last two
                     days (the catalyst check).

  dilution SYM [..]  Per symbol, from SEC EDGAR through the scanner's
                     dilution.py: shelf registrations (S-3/F-3/S-1/F-1) and
                     share offerings (424B, less the bond prospectuses)
                     filed in the last 12 months, and the
                     scanner's own risk rating (dilution.dilution_risk:
                     EXTREME / HIGH / MEDIUM / LOW). Context, not a filter.

  calendar [DAYS]     The economic and earnings calendar from today, through
                     the scanner's calendar_events.py (Nasdaq's public
                     calendar): the scanner's allowlist of economic events
                     and the reporters chosen in Settings → Data, best first
                     per day.

  marketnews [N]      The newest market headlines from the scanner's news.py
                     (Seeking Alpha, MarketWatch and CNBC desks, de-duplicated
                     across them), newest first.

  value SYM:PRICE:SHARES [..]
                     Long-term fundamentals per symbol from the scanner's
                     pillars.py (SEC EDGAR company facts): eight checks --
                     5-year P/E, ROIC, share count, FCF / earnings / revenue
                     growth, long-term liabilities to FCF, price to FCF --
                     each with its value, target and pass / fail / unknown.
                     Price and shares come from the widget's own quotes.

  tickernews SYM     One company's Finviz headlines, newest day first and
                     the company's own news first within a day (the detail
                     view's News tab).

  dilution and value need an SEC contact (Settings → Data); without one
  they answer {"error": ...} and the widget leaves those columns empty.

Usage:scannerbridge.py <scanner scripts dir> premarket
       scannerbridge.py <scanner scripts dir> afterhours
       scannerbridge.py <scanner scripts dir> stocks STAK XLAB ...
       scannerbridge.py <scanner scripts dir> dilution STAK XLAB ...
       scannerbridge.py <scanner scripts dir> calendar 7
       scannerbridge.py <scanner scripts dir> marketnews 40
       scannerbridge.py <scanner scripts dir> value KO:62.5:4300000000 ...
       scannerbridge.py <scanner scripts dir> tickernews AMD

An empty <scanner scripts dir> means the bundled scanner/ folder.

Any failure prints {"error": ...} and exits 0, so the widget falls back to
its own sources instead of reading a traceback as data.
"""

import json
import os
import re
import sys
from datetime import datetime, timedelta


def premarket(pm):
    return [{"symbol": g["s"], "name": g.get("n") or "",
             "price": g.get("premarketPrice"),
             "change": g.get("premarketChangePercent"),
             "volume": g.get("premarketVolume"),
             "marketCap": g.get("marketCap")}
            for g in pm.get_premarket_gainers()]


def _nasdaq_num(text):
    """'$3.02 (07:27:19 AM)' -> 3.02, '2,516,965' -> 2516965.0, else None."""
    m = re.match(r"\s*\$?([\d,]+(?:\.\d+)?)", str(text or ""))
    return float(m.group(1).replace(",", "")) if m else None


def prelevels(symbols):
    """
    Today's premarket high, low and share volume per symbol, from Nasdaq's
    extended-trading page (consolidated tape, real time, the whole session
    from 04:00 ET). Yahoo's quotes carry neither premarket volume nor the
    premarket range, so without this the widget only knows the range it has
    watched itself, which a restart loses. One request per symbol, six at a
    time; Nasdaq answered in 1-3 s each (2026-10-26).
    """
    import urllib.request
    from concurrent.futures import ThreadPoolExecutor

    def one(sym):
        url = ("https://api.nasdaq.com/api/quote/" + sym
               + "/extended-trading?markettype=pre&assetclass=stocks&time=0")
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                          "(KHTML, like Gecko) Chrome/130.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*"})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                d = json.load(r).get("data") or {}
            rows = (d.get("infoTable") or {}).get("rows") or []
        except Exception:
            return sym, None
        row = rows[0] if rows else {}
        hi, lo = _nasdaq_num(row.get("highPrice")), _nasdaq_num(row.get("lowPrice"))
        vol = _nasdaq_num(row.get("volume")) or 0
        # No premarket trades yet: known to be none, not unknown.
        return sym, {"hi": hi if hi and lo else None, "lo": lo if hi and lo else None, "vol": vol}

    with ThreadPoolExecutor(max_workers=6) as ex:
        return {s: v for s, v in ex.map(one, symbols) if v is not None}


def afterhours(pm):
    import re
    html = pm.fetch("https://stockanalysis.com/markets/afterhours/gainers/")
    out, seen = [], set()
    for b in re.findall(r"\{no:\d+,[^{}]*\}", html or ""):
        sym = pm._field(b, "s", numeric=False)
        if not sym or sym in seen:
            continue
        seen.add(sym)
        out.append({"symbol": sym, "name": pm._field(b, "n", numeric=False) or "",
                    "price": pm._field(b, "postmarketPrice"),
                    "change": pm._field(b, "postmarketChangePercent"),
                    "date": pm._field(b, "postmarketDate", numeric=False)})
    return out


def stocks(pm, symbols):
    now = datetime.now(pm.ET) if hasattr(pm, "ET") else None
    out = {}
    for sym in symbols:
        try:
            fv = pm.get_finviz(sym) or {}
        except Exception:
            continue
        news = [n for n in (fv.get("news") or []) if n.get("dt")]
        news.sort(key=lambda n: n["dt"], reverse=True)
        cutoff = (now or news[0]["dt"]) - timedelta(days=2) if news else None
        wire = [n for n in news
                if n["dt"] >= cutoff
                and any(w in (n.get("source") or "").lower() for w in pm.PR_WIRES)]
        top = news[0] if news else None
        out[sym] = {
            "float": pm.parse_num(fv.get("Shs Float")),
            "shortFloat": pm.parse_num(fv.get("Short Float")),
            "rvol": pm.parse_num(fv.get("Rel Volume")),
            # The theme column's raw material. Finviz's industry is the useful
            # one -- "Oil & Gas Midstream", "Other Industrial Metals & Mining" --
            # where the sector is only one of eleven buckets. Both come off a
            # page already being fetched, so neither costs a request.
            "sector": fv.get("Sector", ""),
            "industry": fv.get("Industry", ""),
            # Where the company is based: the "foreign" trait of a theme pattern.
            "country": fv.get("Country", ""),
            "newsTime": int(top["dt"].timestamp() * 1000) if top else None,
            "newsTitle": top.get("title") if top else "",
            "newsSource": top.get("source") if top else "",
            "newsUrl": top.get("url") if top else "",
            "catalyst": bool(wire),
        }
    return out


def dilution(symbols):
    """dilution.sec_profile's logic, keeping each filing's form type so the
    widget can say "S-3" rather than only "shelf"; the rating is the
    scanner's own dilution_risk()."""
    import time
    import dilution as dl
    cik_map = dl.load_cik_map()
    cutoff = (datetime.now() - timedelta(days=365)).strftime("%Y-%m-%d")
    out = {}
    for sym in symbols:
        cik = cik_map.get(sym)
        if not cik:
            out[sym] = {"risk": "UNKNOWN", "flags": [], "shelves": [], "offerings": []}
            continue
        try:
            d = json.loads(dl._get(f"https://data.sec.gov/submissions/CIK{cik}.json"))
        except Exception:
            continue
        time.sleep(dl.SEC_DELAY)
        rec = d.get("filings", {}).get("recent", {})
        shelves, offers = [], []
        n = len(rec.get("form", []))
        col = lambda k: rec.get(k) or [""] * n
        for form, date, acc, doc in zip(col("form"), col("filingDate"), col("accessionNumber"), col("primaryDocument")):
            if date < cutoff:
                continue
            if form.startswith(dl.SHELF_FORMS):
                shelves.append({"form": form, "date": date})
            elif form.startswith(dl.OFFERING_FORMS):
                offers.append({"form": form, "date": date, "accession": acc, "document": doc})
        # Bond prospectuses (a 424B5 is filed for notes too) are not share
        # offerings: the scanner reads each cover where it can.
        offers.sort(key=lambda f: f["date"], reverse=True)
        if hasattr(dl, "share_offerings"):
            offers = dl.share_offerings(cik, offers)
        last_offer = max((o["date"] for o in offers), default=None)
        profile = {
            "shelf_count": len(shelves),
            "offering_count": len(offers),
            "days_since_offering": (datetime.now() - datetime.strptime(last_offer, "%Y-%m-%d")).days
                                   if last_offer else None,
            "last_kind": offers[0].get("kind", "equity") if offers else None,
        }
        for o in offers:
            o.pop("accession", None)
            o.pop("document", None)
        risk, flags = dl.dilution_risk(profile)
        out[sym] = {"cik": cik, "risk": risk, "flags": flags,
                    "shelves": sorted(shelves, key=lambda f: f["date"], reverse=True),
                    "offerings": sorted(offers, key=lambda f: f["date"], reverse=True),
                    "daysSinceOffering": profile["days_since_offering"]}
    return out


def calendar(days, start=None):
    """`days` from `start` (YYYY-MM-DD; default today)."""
    import calendar_events as ce
    from datetime import date

    def plain(v):
        # Dates and times as ISO text; everything else as JSON has it.
        return v.isoformat() if hasattr(v, "isoformat") else v

    out = []
    for day, events in ce.week(start=date.fromisoformat(start) if start else None, days=days):
        out.append({"date": day.isoformat(),
                    "events": None if events is None
                    else [{k: plain(v) for k, v in e.items()} for e in events]})
    return out


def releases(args):
    """TICKER:YYYY-MM-DD ... -> {TICKER: url or None}, the earnings release on EDGAR."""
    import calendar_events as ce
    from datetime import date
    out = {}
    for a in args:
        tick, _, day = a.partition(":")
        try:
            out[tick.upper()] = ce.earnings_release(tick, date.fromisoformat(day))
        except Exception:
            out[tick.upper()] = None
    return out


def marketnews(n):
    import news
    return [{"title": h["title"], "url": h.get("url") or "", "source": h.get("source") or "",
             "time": int(h["dt"].timestamp() * 1000),
             "image": h.get("image") or "", "tickers": h.get("tickers") or []}
            for h in news.headlines(limit=n)]


def value(args):
    import pillars
    out = {}
    for a in args:
        sym, _, rest = a.partition(":")
        price, _, shares = rest.partition(":")
        try:
            q = {"price": float(price)} if price else {}
            if shares:
                q["shares"] = float(shares)
            r = pillars.analyse(sym, quote=q or None)
        except Exception:
            continue
        out[sym] = {
            "passed": r.get("passed"), "scored": r.get("scored"),
            "insufficient": bool(r.get("insufficient")),
            "pillars": [{"n": p.n, "name": p.name, "target": p.target, "value": p.value,
                         "passed": p.passed} for p in r.get("pillars") or []],
        }
    return out


def tickernews(sym):
    import news
    _, rows = news.ticker(sym, 40)
    return [{"title": r["title"], "link": r.get("url") or "", "source": r.get("source") or "",
             "time": int(r["dt"].timestamp() * 1000), "company": bool(r.get("is_company_news"))}
            for r in rows]


# Every argument after the command is a symbol, a SYMBOL:PRICE:SHARES or
# TICKER:DATE triple, a count or a date: upper case, digits, ".", ":" and
# "-" cover them all. Anything else is dropped before it reaches a scanner.
# The widget quotes each argument and checks symbols itself; this is the
# second line, for a symbol that came from Yahoo, Nasdaq or Finviz.
ARG = re.compile(r"[A-Z0-9.:\-]{1,40}")


def clean_args(args):
    return [a for a in (str(x).upper() for x in args) if ARG.fullmatch(a)]


def load_settings():
    """Settings → Data, from the file the widget writes (MARKET_TICKER_SETTINGS,
    readable by this user only), so they never sit on a command line where
    `ps` shows them. A manual run can still export the variables by hand."""
    path = os.environ.get("MARKET_TICKER_SETTINGS", "")
    if not path or not os.path.isfile(path):
        return
    with open(path, encoding="utf-8") as f:
        values = json.load(f)
    for k, v in (values or {}).items():
        if k.startswith("MARKET_TICKER_") and isinstance(v, str):
            os.environ[k] = v


def main():
    if len(sys.argv) < 3:
        print(json.dumps({"error": "usage: scannerbridge.py SCANNER_FOLDER_OR_EMPTY COMMAND [ARGS...]"}))
        return
    try:
        load_settings()
        sys.path.insert(0, sys.argv[1] or os.path.join(os.path.dirname(os.path.abspath(__file__)), "scanner"))
        import premarket_report as pm
        cmd = sys.argv[2]
        args = clean_args(sys.argv[3:])
        if cmd in ("dilution", "value", "releases") and not os.environ.get("MARKET_TICKER_SEC_CONTACT", "").strip():
            raise RuntimeError("SEC contact not set (Settings → Data)")
        if cmd == "premarket":
            result = premarket(pm)
        elif cmd == "afterhours":
            result = afterhours(pm)
        elif cmd == "prelevels":
            result = prelevels(args)
        elif cmd == "dilution":
            result = dilution(args)
        elif cmd == "calendar":
            result = calendar(int(args[0]) if args else 7,
                              args[1] if len(args) > 1 else None)
        elif cmd == "releases":
            result = releases(args)
        elif cmd == "marketnews":
            result = marketnews(int(args[0]) if args else 40)
        elif cmd == "value":
            result = value(args)
        elif cmd == "tickernews":
            if not args:
                raise ValueError("no valid symbol")
            result = tickernews(args[0])
        elif cmd == "stocks":
            result = stocks(pm, args)
        else:
            result = {"error": "unknown command " + cmd}
    except Exception as e:
        result = {"error": repr(e)}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
