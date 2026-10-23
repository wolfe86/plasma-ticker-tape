"""
Market headlines from the Seeking Alpha, MarketWatch and CNBC desks, and
per-company headlines from Finviz.
"""

import re
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import market

ET = ZoneInfo("America/New_York")

# (label, url, market_only). `market_only` marks a desk that carries nothing
# but market and company news, so its items need no filtering at all.
NEWS_FEEDS = [
    ("Seeking Alpha", "https://seekingalpha.com/market_currents.xml", True),
    ("MarketWatch", "https://feeds.content.dowjones.io/public/rss/mw_topstories", True),
    ("MarketWatch", "https://feeds.content.dowjones.io/public/rss/mw_bulletins", True),
    ("CNBC", "https://www.cnbc.com/id/100003114/device/rss/rss.html", False),
    ("CNBC", "https://www.cnbc.com/id/10000664/device/rss/rss.html", False),
]

MAX_AGE_HOURS = 48      # older than this is not "recent" by any reading
DEFAULT_N = 5

# Applied only to the general-news desks, which are business channels carrying
# a minority of politics and human interest. A **droplist** rather than an
# allowlist, because the default there is already business: on the day this was
# written CNBC's Economy desk led with French wine production and its Top News
# desk with a dinner guest list, while genuinely market-moving items ("Jamie
# Dimon says hyperscaler AI spending could hit $1 trillion") carry no keyword a
# reasonable allowlist would have held. Naming the noise is the smaller and
# more honest list; extend it when something slips through.
NOISE = re.compile(
    r"\b(election|midterm|campaign trail|senator|congressman|congresswoman|"
    r"impeach|indict|pardon|dinner|wedding|royal|celebrity|recipe|"
    r"vacation|travel guide|holiday gift|horoscope|obituary|"
    r"super bowl|nfl|nba|world cup|olympic|movie review|box office)\b", re.I)


def _norm(title):
    """A title reduced to what two feeds would agree on, for deduplication."""
    return re.sub(r"[^a-z0-9]", "", (title or "").lower())[:60]


def headlines(limit=DEFAULT_N, hours=MAX_AGE_HOURS):
    """
    The most recent market headlines, newest first, deduplicated across feeds.

    A dead feed costs its own items and nothing else -- `market.feed_items`
    returns an empty list rather than raising, so the command still answers
    from whatever is reachable.
    """
    now = datetime.now(ET)
    cutoff = now - timedelta(hours=hours)
    seen, out = set(), []
    for source, url, market_only in NEWS_FEEDS:
        for n in market.feed_items(source, url):
            dt = n["dt"].astimezone(ET)
            if dt < cutoff or dt > now + timedelta(hours=2):
                # Future stamps happen; a feed an hour ahead is a clock
                # problem, a feed a day ahead is wrong and is dropped.
                continue
            if not market_only and NOISE.search(n["title"]):
                continue
            key = _norm(n["title"])
            if not key or key in seen:
                continue
            seen.add(key)
            out.append({**n, "dt": dt})
    out.sort(key=lambda n: n["dt"], reverse=True)
    return out[:limit]


# Recency buckets, in days: today's headlines first, then the week's, then
# the month's. Today is its own bucket by calendar date rather than by 24 hours, because "today's news" means
# today's session, not the last twenty-four hours.
BUCKETS = ((None, "today"), (7, "this week"), (30, "this month"))


def age_bucket(dt, now=None):
    """0 today, 1 this week, 2 this month, 3 older."""
    now = now or datetime.now(ET)
    dt = dt.astimezone(ET)
    if dt.date() == now.date():
        return 0
    days = (now - dt).total_seconds() / 86400
    for i, (limit, _) in enumerate(BUCKETS):
        if limit is not None and days <= limit:
            return i
    return len(BUCKETS)


def ticker(sym, limit=DEFAULT_N):
    """
    Headlines for one company: newest first, but never at the cost of showing
    something that is not about the company at all.

    Two competing requirements, resolved by ordering the keys rather than
    picking a winner:

      * **Recency leads.** Today's headlines outrank the week's, the week's
        outrank the month's.
      * **Relevance breaks ties.** Inside a bucket the company's own
        announcements come first, then headlines naming it, then commentary
        that merely mentions it -- which is still tagged as such, because a
        ticker's Finviz page carries plenty of it. Newest-first *alone* once
        put an Autodesk story at the top of ADBE's page; bucketing keeps that
        fix while letting fresh news win.

    `fundamentals.recent_news()` is asked for more rows than are wanted so
    there is something to re-rank -- it sorts relevance-first.
    """
    import fundamentals
    import quote

    sym = sym.upper().strip()
    q = quote.get(sym) or {}
    rows = fundamentals.recent_news(sym, q.get("name", ""), limit=limit * 5)
    now = datetime.now(ET)
    rows.sort(key=lambda n: (age_bucket(n["dt"], now),
                             0 if n.get("is_company_news") else 1,
                             -n["dt"].timestamp()))
    return q, rows[:limit]
