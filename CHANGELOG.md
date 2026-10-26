# Changelog

Newest first. Versions follow `package/metadata.json`.

## 1.4.1 (beta)

### Fixed
- **The panel froze after an hour or so of a busy session** (95% CPU, memory climbing past 2 GB). The 1.4 theme rules were worked out again for every alert row on every refresh, in every open window, and a day's alerts on one screen came to 1,700 rows. Each stock's theme and sector are now worked out once per data update and shared by its rows, each theme's reading once per change to the tally, and a screen's rows are rebuilt only when its alerts, facts, news, themes or settings change (and at least every 10 seconds).
- Debian 13 (Plasma 6.3): the monospace font the widget asks Kirigami for is not there, so every price, time and figure logged `TypeError: Cannot read property 'family' of undefined`, dozens of times a minute. The widget now falls back to the system's monospace font.

## 1.4.0 (beta)

A beta release, like 1.3: themes rebuilt as patterns judged on their record, premarket levels from Nasdaq, screenshots on the Journal tab and the quote window, and the Options features switched off until they are ready. Everything new here has had days of real use, not weeks.

### Removed
- **Options, for now.** The quote card's Options tab and trade builder, the Unusual options screen type, the OI lines on charts, IV, IV rank and the priced-in earnings move, the options settings and the journal's option trades are switched off: they were not ready. The code stays, behind the `optionsFeature` setting (off), so it can come back. The Journal tab keeps notes and screenshots.

### Added
- **Premarket levels**: every stock up 5% or more premarket, and every stock on the premarket gainers list, is looked up on Nasdaq from 04:00 ET and kept fresh each minute: its premarket high, low and real share volume. The volume filters and RVOL use the real premarket volume, the "above session low" filter uses the real premarket low, and High of Day counts the premarket high until it is broken, in the premarket and the regular session. Saved per session, so a restart keeps them. New **PM high** and **PM low** columns.
- A premarket alert whose filters fail on a stock with no fresh levels is looked up at once and tested again, instead of being dropped for unknown volume.
- A note under the screener when Yahoo is refusing requests and checks have slowed down.
- **PM run %**: how far a stock got from the prior close to its premarket high, fixed at the open. A column, a rank measure, and **PM run** and **PM volume** filters, so a screen can list the premarket's runners and set them beside the session's change. **PM volume** column (off until ticked in Columns).
- A stock with no catalyst yet has its news checked every minute from :00 to :05 and :30 to :35 past each hour, when most press releases drop, instead of every 15 minutes.
- The row tooltip gives the headline's time, source and age under the headline.
- A stock's quote card opened without a screen (the symbol box, recent tickers, a linked click) shows the first scorecard with live rules (Small-cap momentum to start), scored on the stock's latest quote, instead of only the long-term fundamentals.
- **Float** on the quote card moved up into the Quote figures beside volume, and reads the float the screener scores on (Finviz's, else Yahoo's) instead of Yahoo's alone, which is often missing for small caps.
- Sector icons are always grey, on the screener, quote cards, News and Calendar; only themes are heat-coloured. A sector the size of Healthcare has two +30% runners most days, so its heat said nothing.
- **Themes are patterns** (beta): headline words, Finviz industries, and traits that must all hold (news or no news in 24 hours, foreign, float, price, market cap, recently listed), set per theme in Settings → Themes. A stock joins every theme it fits; its row shows the hottest. New starters, added once to a saved list: **No-news runners**, **Foreign low-float** (non-US, float ≤ 10M) and **Oil & gas**; **Drones & defense** also takes the Aerospace & Defense industry.
- Icons **nonews** (a newspaper crossed out) and **globe**, for No-news runners and Foreign low-float. The anonymous figure stays crypto's Privacy icon.
- **Screenshots on the Journal tab**: Ctrl+V or Paste screenshot saves the clipboard's picture in the export folder's `screenshots/`, named by the time and an optional ticker, docked or in a window. The tab shows every screenshot of the day from that folder, and the Markdown journal export lists them.
- **Quote screenshots**: the camera button is on quote windows too. It saves the card as shown, named `…_SYMBOL_quote.png`, in the export folder's `screenshots/`, beside the chart shots.
- **Runs 5 days** column: how many of the last 5 sessions a stock ran on, and the row tooltip lists them ("Ran on 2 of the last 5 sessions: +77% Mon 10-26, +144% Thu 10-23").
- A stock Finviz has no page for (AZTR on 2026-10-26) gets Google News's newest story for its news icon, and Yahoo's company profile for its sector, industry and country.
- **Docs**: the themes guide rewritten for patterns and the record ([docs/themes.md](docs/themes.md)); the trading desk guide without Options and with the Journal tab's screenshots ([docs/workspace.md](docs/workspace.md)); a new demo video and an animated GIF of it; screenshots of a trading desk, two widget windows, the quote and chart windows, linked and unlinked TradingView windows and the Journal tab, taken on a live desktop.
- `tests/test_theme_rules.py`: the theme rules on made-up sessions.
- Hovering the score badge lists the scorecard's rules, each marked passed, missed or not known, with its target and the row's figure.

### Changed
- **Theme heat comes from the record** (beta): a theme is hot once its stocks have run on 3 of the last 5 sessions, more often than it usually does, and stays hot while they run on at least 1 of the last 5; building is a runner in the last 5; burnt is 14 days with none (was 30). A runner is +30% on the day (+60% with no news in 24 hours) on 5× its usual volume or more. All of these are settings. The tooltip lists each session's runners, marks the day's top gainer, and shows how much of their peak the runners kept at 10:00 and now.
- Top Gainers feeds the theme tally by default.
- A stock that joins a theme partway through the day brings its best move and volume of the day from its other groups, instead of starting from its current move.
- A "no news" theme shows on a row only when that stock ran; a quiet stock with no headline shows its sector.

### Fixed
- In a narrow pop-up or window the header buttons (refresh, layouts, TradingView, pop-out, Yahoo, settings) take a row of their own above the tabs, instead of squeezing the tab names onto two lines.
- A column added by an update no longer appears in the middle of a screen you have arranged (moved, resized or picked columns on): it waits, unticked, in Columns. Any change you make to a layout now records which columns are on show, so later updates cannot change them.
- A move over +200% joins the theme tally only once the next pass confirms it (single bad quotes filed HKPD +1910% and three others on 2026-10-26).
- Premarket RVOL compares like with like again: the list volume against the average, not the larger Nasdaq premarket volume (which held High of Day's RVOL filter shut for a few minutes on 2026-10-26).
- A stock-list refresh that Yahoo refused part-way replaced the whole list with the pages it got, dropping thinner stocks (WORX ran +30% premarket on 2026-10-26 with no alert). A partial refresh now adds to the old list.

## 1.3.0 (beta)

A beta release: everything below is new and has had only a few hours of real use. The Options tab, its trade builder and the option figures are beta in their own right.

### Added
- **Detached window**: the pop-up's content in a resizable window (pop-out button in the header), with its size kept, dock back to the panel, and the widget's keyboard shortcut to show and hide it. Settings → Workspace.
- **Screen buttons**: a count of alerts not yet looked at, a highlight in the screen's colour after each alert (how long: Settings → Workspace; the colour: Settings → Screeners), and a speaker beside each alert screen to mute it alone. The Screener tab shows the total.
- **Layouts**: save and restore the screens on show, columns, sorts, mutes, chart settings and chart windows.
- **CSV export** of every alert screen's alerts for the session, times in New York time.
- **Active ticker and recent tickers**: a symbol box and the recent tickers on every quote card; the card opens the new symbol in place.
- **Chart windows**, any number, each with its own bar size, following the active ticker or pinned to a symbol, kept across restarts. Charts on screen reload their bars every `chartRefreshSeconds` (30 by default).
- **Quote window**: the **Quote** button under a card's chart pops the card out into a window of its own, without the chart (search, recent tickers, + Watchlist, Overview, News, Options and Notes, scorecard and figures, and Chart and TV buttons to open a chart window), Linked or Unlinked like the chart windows and kept across restarts. A ticker clicked in any popped-out window opens in it (making one if needed), the linked chart windows follow, and the list stays in place. In the panel's pop-up the same happens while a linked quote window is open (Settings → Workspace → Quote window).
- **More widget windows**: with the detached window open, the pop-out button (in the pop-up or any window) opens another window on the tab and screen it was pressed on, each keeping its own tab, screen and size, kept across restarts and in layouts.
- **TradingView chart windows** (beta): TradingView's full chart page or its embeddable chart, with optional sign-in on TradingView's own page and a signed-in or signed-out status. Needs Qt WebEngine.
- **Watchlist key levels**, a new alert screen type: fail-and-rebound alerts on the prior day's high, low and close, the premarket and session highs and lows, and the levels drawn on a chart, with the buffer, close-or-trade, rebound window, hold and armed time as settings. Outside the regular session it reads 1-minute closes and drops one-bar bad prints.
- **Options tab** (beta) on stock and fund cards: the chain by expiry, IV, IV rank (from IVs the widget records daily), priced-in moves by expiry and through earnings, max pain and open-interest strikes; a trade builder with cost, best and worst case, break-evens, chance of profit and of finishing in the money, Greeks, a payoff chart and position sizing against Settings → Workspace's account, risk and walk-away.
- **Watchlist edits without Settings**: drag a watchlist row by its handle to reorder the watchlist and the tape, click its star to put it on the tape or take it off, and its remove button (shown on hover) to drop it; a quote card for a watchlist symbol has the same star and remove buttons beside + Watchlist. Settings → Symbols follows these edits while it is open, merging them with its own unsaved changes.
- **Chart screenshots**: a camera button on every chart window (the widget's chart and TradingView's) saves a PNG of the chart at once in the export folder's `screenshots/`, named by time, symbol and bar size; a folder button then opens it.
- **Screenshots in notes**: Ctrl+V or **Paste screenshot** on a card's Notes tab saves the picture on the clipboard as a PNG in the export folder's `screenshots/` and adds it to the note, shown as a thumbnail (click to open); the journal export shows it inline. Needs `wl-clipboard` (Wayland) or `xclip` (X11).
- **Journal**: log option trades from the builder, close them with what closing brought in, see realised results; a **Journal** tab in the pop-up and a **Notes** tab on every card; Markdown export; desktop notifications near expiry and near a strike.
- **Unusual options**, a new alert screen type for the watchlist: contracts trading far more than their open interest.
- **Days to cover** column (off until ticked in Columns) and filter.
- **Option lines on the chart** (OI button), and IV, IV rank and the priced-in earnings move in the card's figures.
- **Calendar**: the Day view shows each upcoming reporter's priced-in move.
- **Company description length**: the first sentence, cut at a set length (Settings → Workspace).
- **Trading desk guide** in [docs/workspace.md](docs/workspace.md): the windows, linked and unlinked, where a click goes, layouts and the KWin rules that put each window back on its monitor, screenshots, the journal and Options tab, and Settings → Workspace.
- **Screenshots** of the quote window, chart and TradingView windows, a widget window, the Options tab, a note with a screenshot, and Settings → Workspace.
- Tests: `tests/test_levels.py` and `tests/test_options.py`.

### Changed
- A ticker clicked in a popped-out window opens in the quote window instead of replacing the list; in the panel pop-up it does so only while a linked quote window is open (Settings → Workspace → Quote window).
- The watchlist tab edits the watchlist directly (drag, star, remove), and Settings → Symbols follows those edits while it is open. Before, edits made elsewhere while Settings was open were lost on Apply, except added symbols.
- New settings: Settings → Workspace (screen buttons, detached window, active ticker and quote window, charts, options, export). TradingView's choices are on Settings → Data.

## 1.2.1

### Fixed
- The widget failed to load on Debian and other distributions whose Plasma rejects `textFormat` on tooltips. It is removed from those tooltips; the text is shown as plain text.
- Debian and Ubuntu need the `qml6-module-qtquick-localstorage` and `qml6-module-qtquick-dialogs` packages. The README now lists them.

## 1.2.0 (beta)

The first release after 1.0.1. Everything below is the 1.2 work.

### Added
- **Themes and sectors** (beta): stocks and crypto are grouped by the story behind them, scored hot, building, quiet or burnt. Set up in Settings → Themes.
- **Theme column** on the screener, Theme Hunter screen, and theme conditions for scorecards.
- **Crypto screens**: Crypto Running Up, Crypto 24h High and Crypto Gainers, on Coinbase pairs.
- **Crypto themes** from CoinGecko's categories. The taxonomy is saved in the widget's database and refreshed weekly, so it is not fetched on every start. A coin outside CoinGecko's top 1,000 by market cap gets one lookup of its own.
- **Company descriptions** on the Overview tab of each quote card, from Yahoo's company profile. Coins get CoinGecko's description. Click the text to show all of it.
- **Symbol lookup** at the top of the Watchlist tab: type a symbol and press Enter to open its card without adding it to the watchlist. Plain coin symbols such as `BTC` open the Coinbase pair when one exists, otherwise Yahoo's `-USD` pair.
- **Icon library**: new glyphs (tower, vault, anonymous figure, drone, tank, AI chip, bitcoin, mining card, cannabis leaf). Sectors, crypto categories and built-in themes can pick any library glyph in Settings → Themes.
- **Currencies** on any screen: US dollars, euros, pounds, yen, Canadian and Australian dollars, Swiss francs, bitcoin or ether.
- **Performance presets**: Full, Balanced, Light or Custom.
- **Filings link** on each stock's card: opens its filings on BamSEC.
- **Theme guide** in [docs/themes.md](docs/themes.md): setting up a theme, how a stock joins one, how the heat is read, and the tape settings.
- **Screenshots** of the 1.2 calendar (day, week and month), news, themes and tape settings.

### Changed
- The news list on a stock's card uses the same card layout as the News tab.
- Theme names in Settings → Themes have a fixed width.
- The tape's theme icons follow the glyph chosen for each theme.

### Fixed
- The filings link on the card and the dilution line sent a ticker to SEC EDGAR's CIK field, which EDGAR no longer accepts. Both now open BamSEC.
- Crypto symbols that Coinbase does not list (Monero, for example) now resolve through Yahoo.
- Crypto icons no longer depend on a live lookup each time the widget starts.
- The scanner bridge prints a usage message when run without arguments, instead of a Python error.
- Screener rows keep their place while live data updates, instead of jumping to the top or flickering once a second.

## 1.0.1

- Quote card shows only the opening screen's scorecard.

## 1.0

- First public release.
