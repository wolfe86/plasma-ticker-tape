"""
Shelf registrations and offerings from SEC EDGAR, and the dilution rating
the widget shows beside a stock. Context, not a filter.
"""

import json
import time
import urllib.request
from datetime import datetime

import settings

CACHE = settings.CACHE_DIR

# SEC requires a descriptive UA with contact info, and <10 req/sec.
SEC_UA = {"User-Agent": settings.SEC_CONTACT}
SEC_DELAY = 0.15

SHELF_FORMS = ("S-3", "F-3", "S-1", "F-1")          # authorization to sell later
OFFERING_FORMS = ("424B",)                           # actually selling now


def _get(url, headers=None, timeout=25, retries=3):
    if not (headers or settings.SEC_CONTACT):
        raise RuntimeError("SEC contact not set (Settings → Data)")
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=headers or SEC_UA)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.read().decode("utf-8", errors="ignore")
        except Exception as e:
            last = e
            time.sleep(1.5 * (i + 1))
    raise last


def load_cik_map(max_age_days=7):
    """Ticker -> zero-padded CIK. Cached; the file is ~800KB."""
    CACHE.mkdir(parents=True, exist_ok=True)
    p = CACHE / "cik_map.json"
    fresh = p.exists() and (
        datetime.now() - datetime.fromtimestamp(p.stat().st_mtime)
    ).days < max_age_days
    if fresh:
        try:
            return json.loads(p.read_text())
        except Exception:
            pass
    try:
        raw = json.loads(_get("https://www.sec.gov/files/company_tickers.json"))
        m = {v["ticker"].upper(): str(v["cik_str"]).zfill(10) for v in raw.values()}
        p.write_text(json.dumps(m))
        return m
    except Exception:
        return json.loads(p.read_text()) if p.exists() else {}


def dilution_risk(p):
    """
    Collapse the filing profile into a trust signal.

    The trader question is: can this company dump shares into my spike?
      EXTREME - sold stock within 90 days AND has a live shelf
      HIGH    - sold within 180 days, or a serial issuer (5+ offerings/yr)
      MEDIUM  - shelf on file but not recently fired
      LOW     - no shelf, no offerings on file
    """
    sc = p.get("shelf_count")
    oc = p.get("offering_count") or 0
    dso = p.get("days_since_offering")

    if sc is None:
        return "UNKNOWN", []

    flags = []
    if dso is not None and dso <= 90:
        flags.append(f"sold stock {dso}d ago")
    if oc >= 5:
        flags.append(f"serial issuer ({oc} offerings/12mo)")
    if sc and sc > 0:
        flags.append(f"live shelf ({sc})")
    if p.get("rs_detected"):
        flags.append(f"reverse split ~1-for-{p['rs_ratio']:.0f} "
                     f"(since {p['rs_asof']})")

    if dso is not None and dso <= 90 and sc > 0:
        return "EXTREME", flags
    if (dso is not None and dso <= 180) or oc >= 5:
        return "HIGH", flags
    if sc > 0:
        return "MEDIUM", flags
    return "LOW", flags
