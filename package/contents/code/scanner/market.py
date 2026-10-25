"""
RSS feed parsing shared by the news module.
"""

import re
import sys
import urllib.request
from html import unescape

UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")

# A reply past this size is refused rather than read into memory: one
# runaway or hostile answer must not stall the widget (2026-10-24).
MAX_REPLY = 16 * 1024 * 1024


def _read_capped(r, limit=MAX_REPLY):
    body = r.read(limit + 1)
    if len(body) > limit:
        raise ValueError(f"reply over {limit // 1048576} MB")
    return body


def _get(url, timeout=25, referer=None):
    """GET returning text, or None. Never raises."""
    headers = {"User-Agent": UA, "Accept": "application/json, text/html, */*"}
    if referer:
        headers["Referer"] = referer
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return _read_capped(r).decode("utf-8", errors="ignore")
    except Exception as e:
        print(f"  ! fetch failed {url.split('?')[0]}: {e}", file=sys.stderr)
        return None


def _strip(s):
    """
    RSS text to plain text: unwrap CDATA, decode entities, drop tags.

    Entities are decoded with `html.unescape` rather than a hand-written table,
    which only covered the named ones -- MarketWatch stamps its titles with
    numeric entities, so "Meta's stock" arrived as "Meta&#x2019;s stock".
    The order matters: entities are decoded first and tags come off last, so
    an escaped `&lt;img src=...&gt;` in a title is removed rather than turned
    into live markup the widget would render (2026-10-24).
    """
    s = re.sub(r"<!\[CDATA\[(.*?)\]\]>", r"\1", s, flags=re.S)
    s = re.sub(r"<[^>]+>", "", unescape(s))
    return re.sub(r"\s+", " ", s).strip()


def feed_items(source, url, timeout=20):
    """
    Every `<item>` in an RSS feed as {dt, title, url, source}, unsorted.

    Items without a title or a parseable timestamp are dropped: a headline
    that cannot be placed in time is useless.
    """
    from email.utils import parsedate_to_datetime

    body = _get(url, timeout=timeout)
    if not body:
        return []
    out = []
    for item in re.findall(r"<item>(.*?)</item>", body, re.S):
        m = re.search(r"<title>(.*?)</title>", item, re.S)
        title = _strip(m.group(1)) if m else ""
        lm = re.search(r"<link>(.*?)</link>", item, re.S)
        dm = re.search(r"<pubDate>(.*?)</pubDate>", item, re.S)
        if not title or not dm:
            continue
        try:
            dt = parsedate_to_datetime(_strip(dm.group(1)))
        except (TypeError, ValueError):
            continue
        if dt.tzinfo is None:
            continue
        # A picture, where the feed carries one (MarketWatch: media:content),
        # and the tickers a feed tags (Seeking Alpha: a category whose domain
        # ends /symbol/TSLA).
        im = (re.search(r"<media:(?:content|thumbnail)[^>]*url=\"([^\"]+)\"", item)
              or re.search(r"<enclosure[^>]*url=\"([^\"]+)\"[^>]*type=\"image", item))
        tickers = [t.upper() for t in re.findall(r"<category[^>]*domain=\"[^\"]*/symbol/([A-Za-z.\-]{1,10})\"", item)]
        image = _strip(im.group(1)) if im else ""
        if not re.match(r"https?://", image, re.I):
            image = ""                  # web pictures only: no file:, data: or the like
        out.append({"dt": dt, "title": title,
                    "url": _strip(lm.group(1)) if lm else "", "source": source,
                    "image": image,
                    "tickers": list(dict.fromkeys(tickers))})
    return out

