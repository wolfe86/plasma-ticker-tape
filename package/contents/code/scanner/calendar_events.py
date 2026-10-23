"""
The economic and earnings calendar from Nasdaq's public calendar API.

Economic events are an allowlist (ECON_RULES), scored so the market-moving
releases sort first. Earnings are filtered to the companies the user cares
about -- see cared_for() and Settings → Data.

Two quirks of the economic feed: it answers with the day *before* the one
asked for, and stamps its times at a fixed UTC-4 rather than GMT.
"""

import json
import math
import os
import re
import sys
from datetime import date, datetime, time as dtime, timedelta, timezone
from zoneinfo import ZoneInfo

import cache
import settings

ET = ZoneInfo("America/New_York")

ECON_URL = "https://api.nasdaq.com/api/calendar/economicevents?date={day}"
EARN_URL = "https://api.nasdaq.com/api/calendar/earnings?date={day}"

UA = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")
HEADERS = {"User-Agent": UA, "Accept": "application/json"}

# See the module docstring: the feed's day offset and fixed UTC-4 stamps.
ECON_QUERY_OFFSET = timedelta(days=1)
FEED_TZ = timezone(timedelta(hours=-4))

# A consensus a week out does not move; today's actuals do.
TTL_AHEAD = 6 * 3600
TTL_TODAY = 600

COUNTRY = "United States"

# Where a reporter's sort score switches from the small-cap scale to the
# large-cap one (see _earn_score). Sorting only; who is listed is cared_for().
LARGE_CAP_FLOOR = 50e9


# --- What counts, and what it is worth -------------------------------------
#
# Ordered: the first pattern to match wins, so `Core CPI` is scored before the
# rule for `CPI` can claim it. Anything unmatched scores nothing and is
# dropped -- the allowlist is the whole filter.
#
# `family` collapses one real-world release that the feed splits into several
# rows. The employment report arrives as Nonfarm Payrolls, Unemployment Rate
# and Average Hourly Earnings at the same 08:30; it is one event and gets one
# line, the highest-scoring member of its family that day.

ECON_RULES = [
    (r"\bfomc\s+statement\b",                      "fed_decision", 100, "FOMC statement"),
    (r"\binterest\s+rate\s+decision\b",            "fed_decision", 100, "Fed rate decision"),
    (r"\bfomc\s+press\s+conference\b",             "fed_decision",  95, "Fed press conference"),
    (r"\bcore\s+cpi\b",                            "cpi",           90, None),
    (r"\bcpi\b|\bconsumer\s+price\s+index\b",      "cpi",           88, None),
    (r"\bnonfarm\s+payrolls?\b",                   "jobs_report",   88, "Nonfarm Payrolls"),
    (r"\bcore\s+pce\b",                            "pce",           85, None),
    (r"\bpce\s+price\s+index\b",                   "pce",           83, None),
    (r"\bunemployment\s+rate\b",                   "jobs_report",   80, None),
    (r"\baverage\s+hourly\s+earnings\b",           "jobs_report",   78, None),
    (r"\bcore\s+ppi\b",                            "ppi",           74, None),
    (r"\bppi\b|\bproducer\s+price\s+index\b",      "ppi",           73, None),
    (r"\bcore\s+retail\s+sales\b",                 "retail",        71, None),
    (r"\bretail\s+sales\b",                        "retail",        72, None),
    (r"\bgdp\b",                                   "gdp",           70, None),
    # "PMI" required on purpose: the feed also carries the ISM sub-indices
    # (Employment, New Orders, Prices), and a sub-index scoring the same as the
    # headline would win the family on a coin toss and report the wrong number.
    (r"\bism\s+manufacturing\s+pmi\b",             "ism_mfg",       66, None),
    (r"\bism\s+(non-?manufacturing|services)\s+pmi\b", "ism_svc",   65, None),
    (r"\bfomc\s+(meeting\s+)?minutes\b",           "fed_minutes",   62, "FOMC minutes"),
    # Below TIER1: real numbers, but not ones to lead a day with. They fill a
    # day that has nothing above them, one at a time.
    (r"\binitial\s+jobless\s+claims\b",            "claims",        40, None),
    (r"\bconsumer\s+confidence\b",                 "confidence",    36, None),
    (r"\bmichigan\s+consumer\s+sentiment\b",       "sentiment",     35, None),
    (r"\bcore\s+durable\s+goods\s+orders\b",       "durables",      31, None),
    (r"\bdurable\s+goods\s+orders\b",              "durables",      30, None),
    (r"\bhousing\s+starts\b",                      "housing",       30, None),
    (r"\bbuilding\s+permits\b",                    "housing",       29, None),
    # Tier-2: they fill out the day, they never lead it.
    (r"\badp\s+employment\b|\badp\s+nonfarm\b",    "adp",           45, None),
    (r"\brichmond\s+(manufacturing|services)\b",   "richmond",      28, None),
    (r"\bphiladelphia\s+fed\b",                    "philly_fed",    28, None),
    (r"\bempire\s+state\b",                        "empire",        28, None),
    (r"\b(kc|kansas\s+city|dallas|chicago)\s+fed\b", "regional_fed", 26, None),
    (r"\b\d+-(year|month)\s+(note|bond)\s+auction\b", "auction",    25, None),
    (r"\bm2\b|\bmoney\s+supply\b",                 "money_supply",  22, None),
    (r"\b\d+-week\s+bill\s+(announcement|auction)\b", "bills",      20, None),
]
ECON_RULES = [(re.compile(p, re.I), fam, sc, lbl) for p, fam, sc, lbl in ECON_RULES]

# Checked before the rules, so a speaker or a survey can never be mistaken for
# the thing it is named after: "FOMC Member Williams Speaks" must not score as
# an FOMC event, and "Atlanta Fed GDPNow" is a nowcast, not the GDP release.
#
# The second group are companions the feed publishes alongside a headline
# release. They are real numbers, but they are not *the* number: GDP Sales is
# final sales and GDP Price Index is the deflator, neither of which is the GDP
# print the market trades. One line per release means picking the headline.
ECON_DROP = re.compile(
    r"cftc|redbook|baker hughes|api weekly|gdpnow|"
    r"balance sheet|mortgage|refinanc|reserve balances|"
    r"leading index|current account|"
    r"private nonfarm payrolls|government payrolls|manufacturing payrolls|"
    r"u6 unemployment|gdp price index|gdp sales", re.I)

# Fed speakers are dropped, with one mechanical exception: the Chair and the
# Vice Chair. "Significant" is a judgement, so the exception is a name test,
# which can be checked.
#
# This keys off how the feed *labels* the row, not who holds the office: on
# 2026-09-22 Nasdaq published Vice Chair Philip Jefferson as "Fed Governor
# Jefferson Speaks", so he did not match and was dropped. If the Vice Chair
# matters regardless of Nasdaq's wording, this needs a name list instead.
FED_PRINCIPAL = re.compile(
    r"\b(fed(eral\s+reserve)?\s+chair(man|woman)?|vice\s+chair|powell)\b", re.I)
SPEAKER = re.compile(r"speaks|speech", re.I)

# An earnings date on a name passed in `watchlist` is a live catalyst on
# something being watched, so it outranks its size.
GAPPER_BONUS = 15


def _clean(v):
    """Feed values carry HTML entities and use '&nbsp;' for 'nothing yet'."""
    if v is None:
        return None
    s = re.sub(r"&[a-z]+;|&#\d+;", " ", str(v).replace("&amp;", "&"))
    s = re.sub(r"<[^>]+>", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    # The earnings feed writes "N/A" where a company has no year-ago figure --
    # a newly listed name, or one that changed its fiscal calendar. That is an
    # absent value, not a value, and printing it as one is worse than a dash.
    return None if s.upper() in ("", "N/A", "-", "--") else s


def _val(s):
    """'196K' / '1,730K' / '0.3%' / '($1.08)' / '$54.78' -> float, or None."""
    if s is None:
        return None
    s = str(s).strip()
    neg = s.startswith("(") and s.endswith(")")
    s = s.strip("()").replace(",", "").replace("%", "").replace("$", "").strip()
    mult = 1.0
    if s and s[-1] in "KMBT":
        mult = {"K": 1e3, "M": 1e6, "B": 1e9, "T": 1e12}[s[-1]]
        s = s[:-1]
    try:
        v = float(s) * mult
    except ValueError:
        return None
    return -v if neg else v


def _fetch(url, day):
    """
    Cached GET returning the feed's `rows`, or **None** when it could not be read.

    `[]` and `None` are different answers and must stay that way: `[]` is
    "the feed answered and nothing is scheduled", `None` is "the feed did not
    answer". Returning `[]` for both would show a dead feed as "Nothing
    scheduled" -- a confident claim about a day nobody had checked.
    """
    ttl = TTL_AHEAD if day > date.today() else TTL_TODAY
    try:
        body = cache.fetch(url, ttl, headers=HEADERS, timeout=25)
        data = (json.loads(body) or {}).get("data") or {}
        return data.get("rows") or []
    except Exception as e:
        print(f"  ! calendar fetch failed ({url.split('?')[0]}, {day}): {e}",
              file=sys.stderr)
        return None


def _score_econ(name):
    """(family, score, label) for an event name, or None when it does not count."""
    if not name:
        return None
    # Speakers are decided first, so "FOMC Member Williams Speaks" can never
    # fall through to the `fomc` rules and score as an FOMC event.
    if SPEAKER.search(name):
        return ("fed_speaker", 55, name) if FED_PRINCIPAL.search(name) else None
    if ECON_DROP.search(name):
        return None
    for rx, family, score, label in ECON_RULES:
        if rx.search(name):
            return family, score, label or name
    return None


def _when(day, hhmm):
    """The feed's fixed-UTC-4 stamp as a real ET datetime. None when unparseable."""
    if not hhmm:
        return None
    m = re.match(r"^(\d{1,2}):(\d{2})$", hhmm.strip())
    if not m:
        return None
    try:
        naive = datetime.combine(day, dtime(int(m.group(1)), int(m.group(2))))
    except ValueError:
        return None
    return naive.replace(tzinfo=FEED_TZ).astimezone(ET)


def economic(day):
    """
    The scored US economic events for one calendar day, best first.

    One line per real release: where the feed splits a release into several
    rows, or repeats one in two units (Building Permits in millions and again
    as a percentage), the highest-scoring row wins and the rest are dropped.
    """
    rows = _fetch(ECON_URL.format(day=day + ECON_QUERY_OFFSET), day)
    if rows is None:
        return None
    best = {}
    for r in rows:
        if _clean(r.get("country")) != COUNTRY:
            continue
        name = _clean(r.get("eventName"))
        scored = _score_econ(name)
        if not scored:
            continue
        family, score, label = scored
        ev = {
            "kind": "econ", "date": day, "family": family, "score": float(score),
            "label": label, "when": _when(day, _clean(r.get("gmt"))),
            "expected": _clean(r.get("consensus")),
            "previous": _clean(r.get("previous")),
            "actual": _clean(r.get("actual")),
            "ticker": None, "session": None, "mcap": None, "surprise": None,
        }
        # A row carrying a consensus is the one the desk quotes; prefer it when
        # two rows of a family tie on score.
        rank = (ev["score"], 1 if ev["expected"] else 0)
        if family not in best or rank > best[family][0]:
            best[family] = (rank, ev)
    out = [ev for _, ev in best.values()]
    out.sort(key=lambda e: (-e["score"], e["when"] or datetime.max.replace(tzinfo=ET)))
    return out


SESSION = {"time-pre-market": "bmo", "time-after-hours": "amc"}


EARN_BASE = 20.0           # a reporter with no size signal still earns its line


def _earn_score(mcap):
    """
    $50B -> 75, $1T -> 85 for the names big enough to move the tape; below the
    large-cap floor, $1M -> 20 rising to 50 as the floor is approached.

    Size decides only where a reporter sorts, never whether it is listed
    (that is cared_for()). Nothing below the floor can outrank a tier-1
    economic release.
    """
    if not mcap:
        return EARN_BASE
    if mcap < LARGE_CAP_FLOOR:
        span = math.log10(LARGE_CAP_FLOOR / 1e6)
        grown = math.log10(max(mcap, 1e6) / 1e6)
        return max(EARN_BASE, min(50.0, EARN_BASE + 30.0 * grown / span))
    span = math.log10(1e12 / LARGE_CAP_FLOOR)
    return max(75.0, min(85.0, 75.0 + 10.0 * math.log10(mcap / LARGE_CAP_FLOOR) / span))


def _researched():
    """
    Tickers with a folder in Settings → Data → Research folder: subfolders
    named by ticker, in the folder itself or one level down (so both
    Research/AMD and Research/Investing/AMD count).
    """
    out = set()
    root = settings.RESEARCH_DIR
    if not root:
        return out
    try:
        tops = [e for e in os.scandir(root) if e.is_dir()]
    except OSError:
        return out
    for e in tops:
        if re.fullmatch(r"[A-Z]{1,5}", e.name):
            out.add(e.name)
        try:
            for sub in os.scandir(e.path):
                if sub.is_dir() and re.fullmatch(r"[A-Z]{1,5}", sub.name):
                    out.add(sub.name)
        except OSError:
            pass
    return out


def cared_for(ev, researched=None, focus=None):
    """
    Is this reporter worth a line? Yes if it is on `watchlist`, at or above
    the big-company floor, has a research folder, or is on the always-show
    list -- all three set in Settings → Data.
    """
    if ev.get("on_watchlist"):
        return True
    if (ev.get("mcap") or 0) >= settings.EARNINGS_MIN_CAP:
        return True
    t = ev.get("ticker")
    researched = _researched() if researched is None else researched
    focus = settings.EARNINGS_TICKERS if focus is None else focus
    return t in researched or t in focus


def earnings(day, watchlist=()):
    """
    The day's reporters worth a line -- see cared_for(). `watchlist` adds
    tickers for this call only, and ranks them up.
    """
    watch = {t.upper() for t in watchlist or ()}
    rows = _fetch(EARN_URL.format(day=day), day)
    if rows is None:
        return None
    out = []
    for r in rows:
        tick = (_clean(r.get("symbol")) or "").upper()
        if not tick:
            continue
        mcap = _val(_clean(r.get("marketCap")))
        score = _earn_score(mcap)
        on_watch = tick in watch
        session = SESSION.get(_clean(r.get("time")) or "")
        out.append({
            "kind": "earnings", "date": day, "family": f"earn:{tick}",
            "score": score + (GAPPER_BONUS if on_watch else 0),
            "label": tick, "name": _clean(r.get("name")), "when": None,
            "expected": _clean(r.get("epsForecast")),
            "previous": _clean(r.get("lastYearEPS")),
            "actual": _clean(r.get("eps")),
            "surprise": _clean(r.get("surprise")),
            "ticker": tick, "session": session, "mcap": mcap,
            "on_watchlist": on_watch,
        })
    researched, focus = _researched(), settings.EARNINGS_TICKERS
    out = [e for e in out if cared_for(e, researched, focus)]
    return sorted(out, key=lambda e: (-e["score"], e["ticker"]))


def day_events(day, watchlist=()):
    """
    Everything worth a line on one day, best first.

    Every scored economic event earns its line, and so does every reporter
    cared_for() keeps. `None` when either feed could not be read -- see
    `_fetch`.
    """
    econ = economic(day)
    earn = earnings(day, watchlist)
    if econ is None or earn is None:
        return None
    return sorted(econ + earn, key=lambda e: -e["score"])


def week(start=None, days=7, watchlist=()):
    """[(date, [events])] from `start`, weekends included but usually empty."""
    start = start or date.today()
    return [(start + timedelta(days=i),
             day_events(start + timedelta(days=i), watchlist))
            for i in range(days)]
