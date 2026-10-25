# Changelog

Newest first. Versions follow `package/metadata.json`.

## 1.3.0 (beta)

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
- **Options tab** on stock and fund cards: the chain by expiry, IV, IV rank (from IVs the widget records daily), priced-in moves by expiry and through earnings, max pain and open-interest strikes; a trade builder with cost, best and worst case, break-evens, chance of profit and of finishing in the money, Greeks, a payoff chart and position sizing against Settings → Workspace's account, risk and walk-away.
- **Watchlist edits without Settings**: drag a watchlist row by its handle to reorder the watchlist and the tape, click its star to put it on the tape or take it off, and its remove button (shown on hover) to drop it; a quote card for a watchlist symbol has the same star and remove buttons beside + Watchlist. Settings → Symbols follows these edits while it is open, merging them with its own unsaved changes.
- **Chart screenshots**: a camera button on every chart window (the widget's chart and TradingView's) saves a PNG of the chart at once in the export folder's `screenshots/`, named by time, symbol and bar size; a folder button then opens it.
- **Screenshots in notes**: Ctrl+V or **Paste screenshot** on a card's Notes tab saves the picture on the clipboard as a PNG in the export folder's `screenshots/` and adds it to the note, shown as a thumbnail (click to open); the journal export shows it inline. Needs `wl-clipboard` (Wayland) or `xclip` (X11).
- **Journal**: log option trades from the builder, close them with what closing brought in, see realised results; a **Journal** tab in the pop-up and a **Notes** tab on every card; Markdown export; desktop notifications near expiry and near a strike.
- **Unusual options**, a new alert screen type for the watchlist: contracts trading far more than their open interest.
- **Days to cover** column (off until ticked in Columns) and filter.
- **Option lines on the chart** (OI button), and IV, IV rank and the priced-in earnings move in the card's figures.
- **Calendar**: the Day view shows each upcoming reporter's priced-in move.
- **Company description length**: the first sentence, cut at a set length (Settings → Workspace).
- Tests: `tests/test_levels.py` and `tests/test_options.py`.

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
