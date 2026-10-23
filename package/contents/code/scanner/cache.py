"""
A small disk cache for HTTP bodies, so slow-moving data (SEC filings, the
earnings calendar, quotes) is not fetched again on every call. Lives in
settings.CACHE_DIR and is pruned oldest-first past MAX_BYTES.

Stdlib only.
"""

import hashlib
import json
import os
import sys
import time
import urllib.request

import settings

DIR = settings.CACHE_DIR / "http"
TTL_QUOTE = 300              # price: stale by seconds, but 5 minutes is fine

# EDGAR companyfacts documents are several MB each -- ADBE's is ~5MB -- so a few
# dozen companies would otherwise quietly fill a gigabyte.
MAX_BYTES = 200 * 1024 * 1024
PRUNE_EVERY = 25             # writes between size checks

_mem = {}
_writes = 0


def _path(url):
    return DIR / (hashlib.sha256(url.encode()).hexdigest()[:32] + ".json")


def _read(p):
    try:
        d = json.loads(p.read_text())
        return d["t"], d["body"]
    except Exception:
        return None, None


def fetch(url, ttl, headers=None, timeout=25, fetcher=None):
    """
    Return the body for `url`, from memory, then disk, then the network.

    `fetcher(url)` overrides how a miss is fetched, so callers that already have
    a compliant requester (dilution's SEC user agent) keep using it.
    """
    now = time.time()

    hit = _mem.get(url)
    if hit and now - hit[0] < ttl:
        return hit[1]

    p = _path(url)
    stamp, body = _read(p) if p.exists() else (None, None)
    if stamp is not None and now - stamp < ttl:
        _mem[url] = (stamp, body)
        return body

    try:
        if fetcher:
            fresh = fetcher(url)
        else:
            req = urllib.request.Request(url, headers=headers or {})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                fresh = r.read().decode("utf-8", errors="ignore")
    except Exception as e:
        if body is not None:
            # Stale beats nothing: the upstream is down, the numbers are a day
            # old, and the caller is better off with them than with an error.
            age = int((now - stamp) / 3600)
            print(f"  ! {url.split('?')[0]} failed ({e}); using cache {age}h old",
                  file=sys.stderr)
            return body
        raise

    _mem[url] = (now, fresh)
    try:
        DIR.mkdir(parents=True, exist_ok=True)
        tmp = p.with_suffix(".tmp")
        tmp.write_text(json.dumps({"t": now, "url": url, "body": fresh}))
        os.replace(tmp, p)          # atomic, so a crash cannot leave a half file
        global _writes
        _writes += 1
        if _writes % PRUNE_EVERY == 0:
            prune()
    except Exception as e:
        print(f"  ! cache write failed: {e}", file=sys.stderr)
    return fresh


def prune(max_bytes=MAX_BYTES):
    """Evict oldest-first until the cache fits. Returns bytes removed."""
    if not DIR.exists():
        return 0
    files = sorted(DIR.glob("*.json"), key=lambda f: f.stat().st_mtime)
    total = sum(f.stat().st_size for f in files)
    removed = 0
    for f in files:
        if total - removed <= max_bytes:
            break
        try:
            sz = f.stat().st_size
            f.unlink()
            removed += sz
        except OSError:
            continue
    return removed
