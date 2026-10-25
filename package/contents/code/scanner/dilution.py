"""
Shelf registrations and offerings from SEC EDGAR, and the dilution rating
the widget shows beside a stock. Context, not a filter.
"""

import json
import re
import time
import urllib.request
from datetime import datetime
from html import unescape

import settings

CACHE = settings.CACHE_DIR

# SEC requires a descriptive UA with contact info, and <10 req/sec.
SEC_UA = {"User-Agent": settings.SEC_CONTACT}
SEC_DELAY = 0.15

# A reply past this size is refused rather than read into memory: one
# runaway or hostile answer must not stall the widget (2026-10-24).
# EDGAR's companyfacts runs to several MB for a large company.
MAX_REPLY = 64 * 1024 * 1024


def _read_capped(r, limit=MAX_REPLY):
    body = r.read(limit + 1)
    if len(body) > limit:
        raise ValueError(f"reply over {limit // 1048576} MB")
    return body


SHELF_FORMS = ("S-3", "F-3", "S-1", "F-1")          # authorization to sell later
OFFERING_FORMS = ("424B",)                           # actually selling now (or bonds: see share_offerings)


def _get(url, headers=None, timeout=25, retries=3):
    if not (headers or settings.SEC_CONTACT):
        raise RuntimeError("SEC contact not set (Settings → Data)")
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=headers or SEC_UA)
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return _read_capped(r).decode("utf-8", errors="ignore")
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


# What a 424B prospectus sells, read from its cover page. A 424B5 is filed
# for a bond issue as well as a share sale: NVIDIA's of 2026-06-17 is
# $25,000,000,000 of notes due 2028-2056, which rated a $4T company
# "Dilution HIGH" (2026-10-24). Convertible notes count as shares: they
# turn into stock.
_EQUITY = re.compile(r"shares of (?:our |its )?(?:class [a-z] )?(?:common|ordinary)|ordinary shares|"
                     r"american depositary|\bADSs?\b|pre-funded|warrants? to purchase|\bconvertible\b|"
                     r"common stock", re.I)
_DEBT = re.compile(r"\bnotes? due\b|\bdebentures?\b|\bsenior (?:unsecured )?notes\b|\bbonds? due\b|"
                   r"%\s*notes\b|\bmedium-term notes\b|\bstructured notes?\b|\bcertificates of deposit\b|"
                   r"\b(?:the|your|these) notes\b|\bnotes linked\b|\bautocallable\b|\bpricing supplement\b|"
                   r"\bstructured investments\b", re.I)
KIND_SAMPLE = 8          # 424Bs read per company per call, newest first


def offering_kind(cik, accession, document):
    """
    "debt", "equity" or "unknown" for one 424B filing, from the start of its
    main document (the cover page; at most 256 KB is read). Cached for good:
    a filing never changes.
    """
    CACHE.mkdir(parents=True, exist_ok=True)
    p = CACHE / "offering_kinds.json"
    try:
        known = json.loads(p.read_text())
    except Exception:
        known = {}
    if accession in known:
        return known[accession]
    url = (f"https://www.sec.gov/Archives/edgar/data/{int(cik)}/"
           f"{accession.replace('-', '')}/{document}")
    try:
        req = urllib.request.Request(url, headers=SEC_UA)
        with urllib.request.urlopen(req, timeout=20) as r:
            head = r.read(256 * 1024).decode("utf-8", errors="ignore")
    except Exception:
        return "unknown"            # not cached: asked again next time
    finally:
        time.sleep(SEC_DELAY)
    text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", unescape(head)))
    # The cover: the first 4,000 characters. Whichever kind it names first
    # is what is being sold -- a bond cover may still say "our common stock
    # is listed on...". A bank's structured notes come as a "pricing
    # supplement".
    cover = text[:4000]
    debt, equity = _DEBT.search(cover), _EQUITY.search(cover)
    if equity and (not debt or equity.start() < debt.start() or "convertible" in cover.lower()):
        kind = "equity"
    elif debt:
        kind = "debt"
    else:
        kind = "unknown"
    known[accession] = kind
    try:
        p.write_text(json.dumps(known))
    except Exception:
        pass
    return kind


def share_offerings(cik, offers):
    """
    The 424B filings in `offers` ({form, date, accession, document}, newest
    first) that sell shares, each with its `kind`. The newest KIND_SAMPLE
    are read; a company whose sample is all debt (a bank's structured notes,
    say) is taken as a bond issuer and the rest are left out, otherwise the
    rest count as share offerings, unread ("unknown").
    """
    sample = offers[:KIND_SAMPLE]
    kinds = [offering_kind(cik, o["accession"], o["document"]) if o.get("accession") and o.get("document")
             else "unknown" for o in sample]
    out = [dict(o, kind=k) for o, k in zip(sample, kinds) if k != "debt"]
    if len(offers) > KIND_SAMPLE and not all(k == "debt" for k in kinds):
        out.extend(dict(o, kind="unknown") for o in offers[KIND_SAMPLE:])
    return out


def dilution_risk(p):
    """
    Collapse the filing profile into a trust signal.

    The trader question is: can this company dump shares into my spike?
      EXTREME - sold stock within 90 days AND has a live shelf
      HIGH    - sold within 180 days, or a serial issuer (5+ offerings/yr)
                (one offering of unknown kind with no shelf: MEDIUM)
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
    # One offering, no shelf in the last year, and nothing to say it sold
    # shares rather than bonds: not enough for HIGH (2026-10-24).
    lone = oc == 1 and not sc and p.get("last_kind", "equity") == "unknown"
    if ((dso is not None and dso <= 180) or oc >= 5) and not lone:
        return "HIGH", flags
    if sc > 0 or lone:
        return "MEDIUM", flags
    return "LOW", flags
