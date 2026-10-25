# Changelog

Newest first. Versions follow `package/metadata.json`.

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
