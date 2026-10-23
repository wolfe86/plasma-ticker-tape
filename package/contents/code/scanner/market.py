"""
RSS feed parsing shared by the news module.
"""

import re
import sys
import urllib.request
from html import unescape

UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")


def _get(url, timeout=25, referer=None):
    """GET returning text, or None. Never raises."""
    headers = {"User-Agent": UA, "Accept": "application/json, text/html, */*"}
    if referer:
        headers["Referer"] = referer
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.read().decode("utf-8", errors="ignore")
    except Exception as e:
        print(f"  ! fetch failed {url.split('?')[0]}: {e}", file=sys.stderr)
        return None


def _strip(s):
    """
    RSS text to plain text: unwrap CDATA, drop tags, decode entities.

    Entities are decoded with `html.unescape` rather than a hand-written table,
    which only covered the named ones -- MarketWatch stamps its titles with
    numeric entities, so "Meta's stock" arrived as "Meta&#x2019;s stock".
    The order matters: CDATA and tags come off first, so a decoded entity can
    never produce something that then reads as markup.
    """
    s = re.sub(r"<!\[CDATA\[(.*?)\]\]>", r"\1", s, flags=re.S)
    s = re.sub(r"<[^>]+>", "", s)
    return re.sub(r"\s+", " ", unescape(s)).strip()


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
        out.append({"dt": dt, "title": title,
                    "url": _strip(lm.group(1)) if lm else "", "source": source})
    return out

