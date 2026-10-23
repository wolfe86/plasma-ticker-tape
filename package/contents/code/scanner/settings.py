"""
The scanner's settings, read from the environment.

The widget sets these from Settings → Data on every call (see
ScreenerEngine.qml, `bridgeRun`); a manual run can export them by hand.

  MARKET_TICKER_CACHE           Where downloaded data is cached.
                                Default: $XDG_CACHE_HOME/market-ticker,
                                else ~/.cache/market-ticker.
  MARKET_TICKER_SEC_CONTACT     The User-Agent sent to SEC EDGAR, which its
                                fair-access policy requires to name the
                                requester and a contact, e.g.
                                "Jane Doe jane@example.com". Empty turns the
                                dilution and long-term value features off.
  MARKET_TICKER_EARNINGS_MIN_CAP  Market cap at and above which every
                                reporter is listed in the earnings calendar.
                                Default 40000000000 ($40B).
  MARKET_TICKER_RESEARCH_DIR    Optional. A folder whose subfolders are named
                                by ticker (looked for in it and one level
                                down, e.g. Investing/AMD); those tickers'
                                earnings are always listed.
  MARKET_TICKER_EARNINGS_TICKERS  Optional. Tickers, separated by spaces or
                                commas, whose earnings are always listed.
"""

import os
from pathlib import Path


def _env(name):
    return os.environ.get(name, "").strip()


CACHE_DIR = Path(_env("MARKET_TICKER_CACHE")
                 or Path(_env("XDG_CACHE_HOME") or Path.home() / ".cache") / "market-ticker")

SEC_CONTACT = _env("MARKET_TICKER_SEC_CONTACT")

try:
    EARNINGS_MIN_CAP = float(_env("MARKET_TICKER_EARNINGS_MIN_CAP") or 40e9)
except ValueError:
    EARNINGS_MIN_CAP = 40e9

RESEARCH_DIR = _env("MARKET_TICKER_RESEARCH_DIR")

EARNINGS_TICKERS = {t.upper() for t in _env("MARKET_TICKER_EARNINGS_TICKERS").replace(",", " ").split()}
