# Plasma Ticker Tape

A market ticker tape for the KDE Plasma 6 panel, with a full trading pop-up behind it: a watchlist, live market screeners with alerts and scorecards, candlestick charts with drawing tools, an economic and earnings calendar, and market news.

![The ticker tape scrolling on a Plasma panel, beside the system tray and clock](docs/screenshots/tape.gif)

*On the panel at its default width and speed. [Watch it as video (MP4)](docs/screenshots/tape.mp4).*

![A tour of the widget at three times speed: the watchlist, a quote card, chart and TradingView windows, the screener, the journal and the settings](docs/demo.gif)

*A tour at 3× speed. **▶ [Watch the full 3-minute demo at normal speed (MP4)](docs/demo.mp4)**: every tab, the quote card, the chart, quote and TradingView windows, screenshots, the screener and themes, and the settings.*

**New in 1.4 (beta):** themes are patterns, judged on a week of runners, not one morning; premarket highs and lows from Nasdaq; a repeat-runner column; screenshots pasted on the Journal tab and saved from the quote window. See [what's new](#new-in-14-beta) and **[the themes guide](docs/themes.md)**.

**New in 1.3:** pop it all out into a trading desk of windows (scanners, a quote window, linked chart windows, TradingView) that follow the ticker you click. See **[the trading desk guide](docs/workspace.md)**.

No account, no API key, no telemetry. Everything runs on your machine.

---

## What it does

### The tape

A scrolling strip on your panel: each symbol's price and a green ▲ or red ▼ for the day. **VIX turns red** at your fear line (20 by default). Hover pauses it and shows the full figures. Left-click opens the pop-up. Middle-click opens Yahoo Markets.

![Clicking the tape drops down the pop-up: Watchlist, Screener, Calendar, News and Journal](docs/screenshots/popup.gif)

*Click the tape and the pop-up drops down from the panel. [Watch it as video (MP4)](docs/screenshots/popup.mp4).*

### Watchlist

Stocks, indices, ETFs, crypto, currencies and futures. Each has its price, the day's change and range, and an intraday sparkline. Click a row's star to put it on the tape, drag its handle to reorder, or hover it and click remove to drop it. Settings → Symbols shows the same list.

**Look up any symbol** with the box at the top of the tab: type it and press Enter, and its card opens without joining your watchlist. Use Yahoo's symbols, such as `AIRE`, `^GSPC` or `BTC-USD`. A plain coin symbol such as `BTC` opens the coin when one exists.

![Watchlist](docs/screenshots/watchlist.png)

### Screener

Several thousand actively traded US stocks, checked every 30 seconds by default. Five starting screens, all editable, and you can add your own:

| Screen | What it finds |
|---|---|
| **Running Up** | A stock up 3%+ off its low of the last 2 minutes, at a new high for that window |
| **High of Day** | A stock breaking the session's high |
| **Top Gainers / Top Losers** | The day's biggest movers, live |
| **Deep Value Recovery** | Companies worth $2B+ passing 6 or more of 8 long-term fundamental checks, price to free cash flow among them, at least 15% below their 52-week high and back above their 50-day average |

A ranked screen on **PM run %** (prior close to premarket high, fixed at the open) beside **Change %** shows which stocks ran premarket and which in the session.

Each alert row carries float, short interest, relative volume, a **dilution rating** from SEC filings, the stock's **theme**, and a **scorecard**: your rules, scored live. Hover the score for each rule, passed, missed or not known yet, with the stock's figure. Hover a row for its newest headline with the time it dropped, and the sessions it ran on lately. Each screen can have its own alert sound.

![Running Up alerts, each scored against the small-cap momentum scorecard](docs/screenshots/screener.png)

### Detail view

Click any symbol anywhere to get:
- **A chart.** Line or candles, 1D to 5Y, plus intraday 1m / 5m / 15m / 30m / 1h bars with premarket and after hours, VWAP and a volume strip.
- **Zoom and pan.** The scroll wheel zooms, dragging pans, and the price scale stretches.
- **Drawing tools.** Double-click for a price level, or use the Line button for trend lines. Both are saved per symbol.
- **A short description** of the company (Yahoo's company profile), or of the coin (CoinGecko). Click it to read all of it.
- **Figures.** The full quote, float and short interest, and the dilution line.
- **Filings.** The globe button opens the stock's filings on [BamSEC](https://www.bamsec.com/), where shelf registrations and offerings show first. Crypto and index buttons open Yahoo's quote page.
- **The 8 long-term checks.** 5-year P/E, ROIC, share count, FCF / earnings / revenue growth, long-term liabilities to FCF, and price to FCF.
- **The scorecard**, rule by rule: the screen's, or for a card opened from the symbol box or a click elsewhere, the first scorecard with live rules (Small-cap momentum to start).
- **News** for that company.
- **Notes**: your notes on the symbol, with pasted screenshots, for the journal.

### Calendar and News

The week's market-moving economic releases (CPI, jobs, Fed, PMI and more) with expected, previous and actual figures. Earnings come with EPS estimates for **the companies you choose** (see [Settings → Data](#data)). The News tab carries the market desks plus headlines for every stock on your screens.

- **Calendar: Day, Week or Month.** Day lists the releases in time order with a *now* line through today, then the reporters before the open and after the close. Week puts Monday to Friday side by side, with a weekend day added when it has releases. Month is a grid of weekdays with importance dots, the day's biggest release and how many report; click a day to open it.
- **Read the release.** An economic release links to its publisher's page (Federal Reserve, BLS, BEA, Census Bureau and others). An earnings report that has printed links to its press release on SEC EDGAR (needs the SEC contact).
- **News as cards.** Each headline has a picture (the feed's own, else the article's preview image), the stocks it names as chips, and its source and age. The same story from two places shows once. Filter by *Your screens*, *Market* or *Your feeds*.
- **Company search.** Type a ticker or a company name ("adobe") in the News search box and that company's own news is listed too.

### New in 1.4 (beta)

> [!NOTE]
> **1.4 is a beta release**, like 1.3. The themes, premarket levels and screenshots are days old. Expect the theme rules and defaults to change as they are checked against weeks of live trading, and please report what you find in the [issues](https://github.com/wolfe86/plasma-ticker-tape/issues).

**Themes are patterns.** A theme is whatever the runners have in common: headline words (AI, drones), a Finviz industry (oil and gas), traits such as no news, foreign, float, price, market cap or a recent IPO, or a mix. New starters: **No-news runners**, **Foreign low-float** and **Oil & gas**. A stock can be on several themes; its row shows the hottest. **The full guide is [docs/themes.md](docs/themes.md).**

- **Heat from the record.** A runner is a member up 30% on the day (60% with no news) on 5× its usual volume. A theme is **hot** once it has runners on 3 of the last 5 sessions, more often than it usually does, and stays hot while they keep coming; **building** with a runner in the last 5; **burnt** after 14 days with none. Every number is a setting.
- **Sector icons are always grey.** Only themes are heat-coloured.
- **Runs 5 days.** A column with how many of the last five sessions a stock ran on, and its tooltip lists them.
- **Top Gainers feeds the themes** as well as the alert screens.

**Premarket.**

- **Premarket highs and lows from Nasdaq**, real-time and consolidated, for every stock up 5% or more premarket, refreshed each minute from 04:00 New York time. The volume filters and RVOL use the real premarket volume; High of Day counts the premarket high until it breaks. New columns **PM high**, **PM low**, **PM run %** and **PM volume**; rank a screen by premarket run to list the premarket's runners.
- **News at the half hour.** A stock without a catalyst has its news checked every minute from :00 to :05 and :30 to :35, when most releases drop.

**Screenshots and the journal.**

- **Paste screenshots on the Journal tab**, docked or in a window (Ctrl+V or **Paste screenshot**). The tab shows every screenshot of the day, and the journal export lists them.
- **A camera button on the quote window**, as on the chart windows.
- **Float on the quote card**, beside volume, and the scorecard on any stock's card.

**Fixes.** Arranged screener columns stay put when an update adds a column. A narrow pop-up or window puts its buttons on a row above the tabs. A stock Finviz has no page for gets its news from Google News and its sector from Yahoo.

**Removed for now: Options.** The Options tab, the trade builder, the Unusual options screen, the option figures and option trades in the journal are switched off. They were not ready, and will come back when they are.

| A trading desk | The Journal tab |
|---|---|
| ![A trading desk: a broker's Level 2 and order windows, a linked quote window, a widget window on the watchlist and another on Running Up](docs/screenshots/trading-desk.png) | ![The Journal tab: today's screenshots as thumbnails, with the ticker box and Paste screenshot](docs/screenshots/journal.png) |

### New in 1.3 (beta)

**The trading desk.** Everything pops out into windows that work together. The full guide, with the window rules that put each window back on its monitor, is in **[docs/workspace.md](docs/workspace.md)**.

- **As many windows as you want.** The pop-out button opens the pop-up in a window; press it again for another window on the tab and screen you are looking at: Running Up in one, Crypto 24h High in a second, the calendar in a third. Each keeps its own tab, screen and size, and they come back after a restart.
- **A quote window.** The **Quote** button under a card's chart pops the card out without its chart: search, recent tickers, + Watchlist (or star and remove), the tabs, the scorecard and the figures, and a camera button.
- **Chart windows**, the widget's own or **TradingView's**, as many as you like, one per bar size. TradingView's are its full chart page with its own indicators, and signing in is optional: **Settings → Data → Sign in to TradingView…** opens TradingView's own page; the widget never sees your password. Needs Qt WebEngine.
- **One active ticker.** Click a ticker in any popped-out window and the quote window and every **linked** chart follow it, while your list stays put. **Unlink** a window to keep its own symbol.
- **Screenshots.** A camera button on every chart window saves the chart as a PNG at once. On a card's Notes tab, Ctrl+V pastes a screenshot into the note.
- **Layouts.** Save the screens, columns, sorts, mutes, chart settings and every open window under a name, and switch between them (the bookmark button).

| Two widget windows | Quote window | Chart window |
|---|---|---|
| ![Two widget windows side by side, each on its own alert screen](docs/screenshots/screener-windows.png) | ![The quote window: the card without its chart](docs/screenshots/quote-window.png) | ![A linked widget chart window on 5-minute candles](docs/screenshots/chart-window.png) |

| Linked TradingView windows | Unlinked TradingView windows |
|---|---|
| ![Four linked TradingView windows at different bar sizes following one ticker](docs/screenshots/tradingview-linked.png) | ![Four unlinked TradingView windows, each on its own ticker](docs/screenshots/tradingview-unlinked.png) |

- **Journal and notes.** A Notes tab on every card, with pasted screenshots, and a Journal tab with the day's notes. They export as Markdown with New York times, screenshots inline. (1.3's Options tab and option trades are switched off in 1.4.)

**Screens and alerts.**

- **Screen buttons that say which screen alerted.** Each alert screen's button counts the alerts you haven't looked at and lights up in the screen's colour for a few seconds after each one. A speaker beside it mutes that screen alone.
- **Watchlist key-level alerts.** A new screen type: alerts when a watchlist stock falls through a key level (the prior day's high, low or close, the premarket high or low, the session high or low, or a level drawn on its chart) and climbs back above it in time. Every part of the rule is a setting.
- **Short squeeze figures.** Days to cover as a screener column and filter, beside short interest.
- **Export alerts to CSV** for your trade journal, with New York times.

### New in 1.2 (beta)

- **Themes and sectors (beta).** Each stock is matched to a theme, the pattern behind its run, or else shown with its sector. Set them up in **Settings → Themes**; right-click a screener row to make a theme from its headline, pin the ticker to one, or set its sector. 1.4 changed how themes match and heat: see [docs/themes.md](docs/themes.md).
- **The Theme column.** One column on the screener: the theme's glyph when the stock has one, else its sector's in grey, the theme coloured by how hot it is. Hover it for why. Sort it to put the hottest first.
- **Theme Hunter (beta).** A screen of its own: hot themes, hot sectors, and the runners no theme claims yet: runners under a heating sector that share a headline are the next theme to define.
- **Crypto screens.** Crypto Running Up, Crypto 24h High and Crypto Gainers watch Coinbase pairs around the clock. Add them from **Settings → Screeners**.
- **Currencies.** Any screen can show its figures in US dollars, euros, pounds, yen, Canadian or Australian dollars, Swiss francs, bitcoin or ether.
- **Performance presets.** **Settings → Performance**: *Full* (every stock every pass, for a desktop), *Balanced*, or *Light* (a laptop or a metered connection), or set each control yourself.
- **Scorecards know themes.** A scorecard rule can test the row's theme or sector: its heat, how many members it has today, how many ran.

| Calendar: day | Calendar: week | Calendar: month |
|---|---|---|
| ![The calendar's day view: releases in time order, then the reporters](docs/screenshots/calendar.png) | ![The calendar's week view: Monday to Friday side by side](docs/screenshots/calendar-week.png) | ![The calendar's month view: a grid with importance dots](docs/screenshots/calendar-month.png) |

| News |
|---|
| ![The News tab: market desks and headlines for the stocks on your screens, as cards](docs/screenshots/news.png) |

---

## Install

**You need:**
- KDE Plasma 6. Developed and tested on Plasma 6.8 with Qt 6.12 (Arch Linux); earlier 6.x releases have not been tested yet, so reports either way are welcome.
- On Debian, install the Qt modules the widget loads: `sudo apt install qml6-module-qtquick-localstorage qml6-module-qtquick-dialogs` (tested on Debian 13). Arch includes them in its Qt packages.
- Python 3, for the scanner features: float, short interest, per-stock news, the dilution rating, the calendar and the long-term value lists. Standard library only, nothing to `pip install`. Without it, prices, alerts, charts, crypto and your own news sources still work, and the screener says what is missing.
- For alert sounds, any one of `pw-play` (PipeWire), `paplay` (PulseAudio), `canberra-gtk-play` or `ffplay`, picked automatically, or your own player command in Settings → Screeners. Optional.
- For TradingView chart windows, Qt WebEngine: `qt6-webengine` (Arch) or `qml6-module-qtwebengine` (Debian, Ubuntu). Optional; without it the window says what to install, and the widget's own charts still work.
- To paste screenshots on the Journal tab and into notes, `wl-clipboard` on Wayland (`sudo pacman -S wl-clipboard`, `sudo apt install wl-clipboard`) or `xclip` on X11. Optional.

```bash
git clone https://github.com/wolfe86/plasma-ticker-tape.git
cd plasma-ticker-tape
kpackagetool6 --type Plasma/Applet --install package
```

Then right-click the panel → **Add Widgets** → search **Plasma Ticker Tape** → drag it onto the panel.

**Update** after a `git pull`:

```bash
kpackagetool6 --type Plasma/Applet --upgrade package
kquitapp6 plasmashell && kstart plasmashell
```

The second line restarts the panel so it loads the new version.

**Remove:**

```bash
kpackagetool6 --type Plasma/Applet --remove org.wolfe.marketticker
```

### First run

| When | What happens |
|---|---|
| At once | The tape scrolls the starting symbols |
| ~30 s | The screener's stock pool is built and the first check runs |
| ~1 min | Top Gainers and Top Losers fill |
| ~1 min | The calendar loads |
| Tens of minutes | Deep Value Recovery checks the companies worth $2B or more in batches. The first full pass takes as long as the SEC takes to answer, so the list fills in gradually |

---

## Settings

Right-click the tape → **Configure Plasma Ticker Tape…**

| Page | What you set |
|---|---|
| **Symbols** | Your watchlist. Search to add, ★ to put on the tape, drag to reorder. The Watchlist tab edits the same list |
| **Screeners** | The stock pool, and every screen: type, trigger, filters, scorecard and sound |
| **Scorecards** | Named rule sets, for example *price $2–$20, up 10%+, relative volume 5×+, float under 20M, news today* |
| **Themes** (beta) | Your themes and sectors: their words, industries, traits, pinned tickers and icons, what counts as a runner and how heat is scored. See [docs/themes.md](docs/themes.md) |
| **Workspace** | The detached window, the screen buttons' highlight, recent tickers, the quote window, the company description's length, chart refresh, and where exports and screenshots go. See the [trading desk guide](docs/workspace.md#7-settings--workspace) |
| **Tape** | Scroll speed, width, refresh rate, the VIX fear line |
| **Performance** | How often the widget asks for data, and how much: Full, Balanced, Light or Custom |
| **Data** | Where the data comes from, which earnings you care about (below), and TradingView: full chart page or embedded chart, and **Sign in to TradingView…** |

| Symbols | Screeners | Scorecards |
|---|---|---|
| ![Settings → Symbols: the watchlist with stars and tape labels](docs/screenshots/settings-symbols.png) | ![Settings → Screeners: the stock pool and the Running Up screen's trigger](docs/screenshots/settings-screeners.png) | ![Settings → Scorecards: the small-cap momentum rules](docs/screenshots/settings-scorecards.png) |

| Tape | About |
|---|---|
| ![Settings → Tape: scroll speed, width, refresh, the VIX fear line and the theme tickers on the tape](docs/screenshots/settings-tape.png) | ![Settings → About: the version, licence and links](docs/screenshots/settings-about.png) |

| Themes (beta) | Performance |
|---|---|---|
| ![Settings → Themes: your themes, each with its glyph, headline words and pinned tickers](docs/screenshots/themes-custom.png) | ![Settings → Performance: the presets and how often each check runs](docs/screenshots/settings-performance.png) |

The theme settings are explained in the [themes guide](docs/themes.md).

### Data

![Settings → Data, filled in with an example user's details](docs/screenshots/settings-data.png)

| Setting | What it does |
|---|---|
| **Scanner folder** | Leave empty to use the scanner that ships with the widget. To change how lists, news and the calendar are gathered, copy `package/contents/code/scanner/` anywhere, edit it, and point this at your copy |
| **SEC contact** | Your name and email, for example `Jane Doe jane@example.com`. SEC EDGAR requires every program to identify itself ([SEC fair access](https://www.sec.gov/os/accessing-edgar-data)). It is sent **only to sec.gov**. Leave it empty and the dilution rating and the 8 long-term checks stay off |
| **Always list companies worth** | Every company at least this big shows on the earnings calendar. Default $40B |
| **Research folder** | Optional. Any subfolder named by a ticker (1 to 5 letters), in this folder or one level down, puts that company on the calendar. For example `Research/AMD` or `Research/Investing/AMD`. Handy if you keep notes per stock |
| **Always list these tickers** | Optional. Tickers you always want to see, separated by spaces or commas |
| **TradingView windows** | *Full chart page* (TradingView's own page; signing in is optional) or the embedded chart, which needs no account |
| **TradingView account** | **Sign in to TradingView…** opens TradingView's own sign-in page in a TradingView window, and shows whether you are signed in. The widget never sees or keeps your password |
| **Google News edition** | The language and country for a card's news when the scanner has none, for example `en-US` or `de-DE` |
| **Market desks** | The built-in market headlines on the News tab: Seeking Alpha, MarketWatch and CNBC, refreshed every 3 minutes |
| **Pictures** | Show a picture beside each headline: the feed's own, else the article's preview image |
| **Your sources** | Your own RSS or Atom feeds for the News tab, checked on the interval set under Settings → Performance |

**Which earnings show up is up to you.** Every reporter that matches none of these three is left off, so the calendar shows the companies you follow instead of the hundreds that report each week. Set the floor to $0 to see every reporter.

---

## Where the data comes from

| Data | Source |
|---|---|
| Stock prices, charts, quotes, the screener's stock pool, index and ETF figures | Yahoo Finance (unofficial endpoints) |
| Company descriptions on stock cards | Yahoo Finance (company profile) |
| Crypto prices, crypto screens | Coinbase's public exchange data |
| Crypto coins Coinbase does not list, such as Monero | Yahoo Finance (`-USD` pairs) |
| Crypto categories (themes), coin descriptions and coin lookups | CoinGecko's public API (free tier, rate-limited) |
| Premarket and after-hours gainers | stockanalysis.com |
| Float, short interest, relative volume, per-stock headlines | Finviz |
| Dilution (shelves, offerings) and the 8 fundamental checks | SEC EDGAR |
| Economic and earnings calendar | Nasdaq's public calendar |
| Market news | Seeking Alpha, MarketWatch and CNBC RSS feeds |
| Company names for news ranking | CNBC quotes |
| News for non-stock symbols | Google News RSS |
| Filings link on a stock card | [BamSEC](https://www.bamsec.com/) (opens in your browser; nothing is fetched from it) |
| Premarket high, low and volume | Nasdaq's quote API (unofficial endpoint, real-time consolidated), for stocks up 5% or more premarket |
| News and sector for a stock Finviz has no page for | Google News search and Yahoo's company profile |
| Watchlist key levels | Yahoo Finance 1-minute and daily bars |
| TradingView chart windows | TradingView's own chart page or embeddable chart, in a web view |

> [!WARNING]
> **Not every source is official.** SEC EDGAR, Coinbase and CoinGecko publish APIs for this kind of data. Yahoo Finance, Finviz, stockanalysis.com, Nasdaq's calendar, the news feeds and Google News do not offer a documented public API for it, so they can change or stop answering without notice, and a screen or column will go empty until the scanner is updated. Quotes may be delayed. Check each site's terms for your own use. This project is not affiliated with any of them.

> [!CAUTION]
> **Not investment advice.** This is a tool for watching the market. Its screens, scores and ratings are mechanical filters, not recommendations.

---

## Privacy and security

- **Nothing is sent anywhere except the data sources above**, and the links you click on a card (BamSEC, Yahoo), which open in your browser. No telemetry, no accounts.
- **Your settings stay local.** They live in Plasma's config (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`). The day's alerts, fundamentals results and your chart lines are kept in Qt's local database under `~/.local/share/plasmashell/QML/OfflineStorage/`. Downloads are cached in `~/.cache/market-ticker/`, capped at 200 MB.
- **The scanner runs as you.** The widget runs `python3` on the scanner folder you choose, so only point it at code you trust.
- **Settings reach the scanner through a private file**, readable only by you, and never appear on a command line. Symbols are quoted when a scanner command is built, and the scanner accepts only ticker-shaped arguments.
- **Links from news feeds open only if they are web addresses** (`http://` or `https://`).
- **Your journal stays local.** Notes are kept in the same local database folder as the alerts. Exports are written only where you set (**Settings → Workspace**; Documents/Plasma Ticker Tape by default).
- **TradingView windows are a web page.** They load TradingView's site, which sets its own cookies; they are kept in the widget's own web storage (`~/.local/share/plasmashell/QtWebEngine/plasma-ticker-tape`). If you sign in, you do it on TradingView's page; the widget never reads or stores your password. TradingView's terms apply.
- **Screenshots stay local.** The camera button and pasted screenshots are saved as PNGs in `screenshots/` in your export folder. The clipboard is read only when you paste on the Journal tab or into a note (Ctrl+V or **Paste screenshot**), and only for a picture.
- **Expiry alerts use your desktop's notifications** (`notify-send`).
- **Your own news feeds** (Settings → Data) can send a header you type, which is saved in plain text in Plasma's config file. Use feeds you trust.

---

## How it is built

```
CHANGELOG.md                   what changed in each version
package/
├── metadata.json              the widget's name, version, licence
└── contents/
    ├── config/                every setting and its default; the settings pages
    ├── ui/                    QML and JavaScript: the tape, pop-up, windows, screener engine, chart, calendar, news, journal, themes and icons (and the options code, switched off)
    └── code/
        ├── scannerbridge.py   what the widget calls; prints one line of JSON
        └── scanner/           the data gathering: lists, Finviz, SEC, calendar, news
tests/                         offline checks: icons, the scanner bridge, documentation links, key levels, theme rules and option maths
```

The tape, the screener and the news search talk to their sources directly from QML (Yahoo Finance, CoinGecko, Coinbase, Google News). The premarket levels come from Nasdaq through `scannerbridge.py prelevels`. The scanner's lists, Finviz, SEC EDGAR, the calendar and the headline feeds go through `scannerbridge.py`. You can run it by hand to see exactly what the widget gets:

```bash
python3 package/contents/code/scannerbridge.py "" calendar 3
MARKET_TICKER_SEC_CONTACT="Jane Doe jane@example.com" \
  python3 package/contents/code/scannerbridge.py "" value KO:62.5:
```

The `""` means the built-in scanner. Any failure prints `{"error": …}`, and the widget leaves that column or screen empty.

### Tests

```bash
python3 tests/test_glyphs.py
python3 tests/test_docs.py
python3 tests/test_levels.py
python3 tests/test_options.py
python3 tests/test_theme_rules.py
```

`test_theme_rules.py` checks the 1.4 theme rules on made-up sessions: pattern matching, the runner test, and hot, building, staying hot and burnt. `test_levels.py` runs the key-level rule (fail, rebound, hold, lapse, bad prints after hours) on made-up bars and on SPY's 2026-10-23 after-hours bad print. `test_options.py` checks the option maths against textbook Black-Scholes values and the payoff, break-even, sizing and chain readings on small cases. Both need Node.js and are skipped without it.

`test_glyphs.py` checks that every icon in the library is valid SVG, that every theme and sector points at an icon that exists, and that the scanner bridge compiles and reports errors as JSON. Its icon checks need [Node.js](https://nodejs.org/) and are skipped without it. `test_docs.py` checks that every image and link in the documentation points at a file that exists. The tests run offline; they do not call any data source.

### Troubleshooting

```bash
journalctl --user -b | grep -i marketticker
```

shows the widget's own warnings, such as a failure to open its database or to save theme history. A failed scanner request does not appear there: the column or screen it feeds stays empty.

---

## Changes

Version history is in [CHANGELOG.md](CHANGELOG.md).

## Licence

[GPL-2.0-or-later](LICENSE). © 2026 Matt Wolfe.
