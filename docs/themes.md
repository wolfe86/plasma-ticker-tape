# Themes and sectors (beta)

A **theme** is a story that moves several stocks at once: a treasury company buying bitcoin, a run of drone contracts, a rare-earth push. The widget groups stocks by theme, scores each theme **hot, building, quiet or burnt** from what its members actually did that day, and shows the result on the tape, the screener and the Theme Hunter.

A **sector** is the fallback: every stock has one, so a sector that keeps heating up is a cue to look for the story behind it. Sectors are Finviz's eleven groups for stocks and CoinGecko's categories for crypto.

Themes are set up in **Settings → Themes**. The starter set (crypto treasury, Bitcoin miners, AI, nuclear and SMR, power and grid, critical minerals, drones and defense, space, cannabis) is there to edit or delete.

---

## 1. Setting up your first theme

1. Open **Settings → Themes** and click **Add a theme**.
2. Give it a name, for example *Rare earths*.
3. Pick a glyph. It is the icon the theme shows on the tape and the screener.
4. In the **Headline words** field, list the words a catalyst headline would contain (see section 2).
5. Optionally, in the **Pinned tickers** field, list tickers that belong to the theme whatever their headlines say.
6. Keep **Stocks** or switch to **Crypto**, depending on what the theme is about.
7. Tick the box at the start of the row so the theme is on.

Then wait for a stock to get a headline that matches. Its row in the screener gets the theme's glyph in the **Theme** column, and hovering over the glyph explains why.

![Settings → Themes: the theme and sector settings, with the icon colours and each sector's icon](screenshots/themes-settings.png)

![Settings → Themes: your themes, each with its glyph, headline words and pinned tickers](screenshots/themes-custom.png)

To see theme tickers on the tape as well, add the Themes entry in **Settings → Symbols** (the button **Add the Themes entry (beta)**). It is starred by default, so it sits on the tape as a slot that fills with the tickers of themes running hot.

---

## 2. How a stock joins a theme

Each stock is placed on the first rule that fits, in this order:

1. **Pinned.** The ticker is listed in the theme's pinned tickers. A pin counts from the day it was made, so earlier days are not rewritten.
2. **Headline words.** The stock's newest headline contains one of the theme's words. The first theme in the list that matches wins.
3. **Sticky.** The headline matched a theme recently. The stock stays on that theme for **10 sessions** (adjustable), so follow-up news without the magic words still counts.
4. **Sector.** No theme fits, so the stock is counted in its sector instead.

### Writing headline words

| Syntax | Matches | Example |
|---|---|---|
| `word` | the word as a whole word | `uranium` matches "uranium", not "uraniumite" |
| `word*` | any word starting with `word` | `drone*` matches "drone", "drones", "drone strike" |
| `a \| b` | either term | `eth \| sol` matches either |
| `a + b` | both terms in one headline, within 60 characters | `treasury + bitcoin` |

Keep words specific. `ai` on its own matches far too much, so the starter AI theme uses longer phrases such as "large language" and "data center*".

---

## 3. Reading the heat

Every day a theme gets a status from its members' best moves that day:

| Status | Colour | What it means |
|---|---|---|
| **Hot** | red (heat ramp) | At least **2 members ran** (up 30% or more at some point during the day), and at least **2 times** the number expected from the theme's recent days. |
| **Building** | amber | At least **1 member ran**, at least **2 members** are on it, and the runners are at least **1.5 times** what is expected. |
| **Quiet** | grey | Nothing that qualifies. |
| **Burnt** | blue, crossed out | It was hot, and nothing in it has run for **30 days** (adjustable). |

"Expected" is the theme's own recent average, scaled to how many members it has today. The first five sessions have no baseline yet, so a theme is judged on its runner count alone.

Hot and building themes show filled glyphs on the tape. Quiet and burnt themes show outlines.

### Which screens feed themes

Only stocks from screens that **feed the themes** count. Alert screens such as Running Up and High of Day do so by default. The list screens (Top Gainers, Top Losers, Deep Value) do not. You can change this for each screen under **Settings → Screeners**, with the option **Its stocks build the theme and sector heat**.

### The tape

Theme tickers reach the tape only when the **Themes** entry is starred in **Settings → Symbols**. Then **Settings → Tape** controls the rest:

| Setting | Default | What it does |
|---|---|---|
| **Show tickers of themes** | Hot themes only | Choose **Hot and building themes** to include building ones. |
| **At most** | 10 tickers | The most theme tickers on the tape at once. |
| **A ticker leaves when** | 20% below its session high | A running stock drops off once it fades this far from its peak. |
| **Only tickers above their 200-day EMA** | on | Keeps only stocks trading above their 200-day average. |
| **Replay** (outside market hours, show the last session's theme tickers) | off | Turn on to see the last session's theme tickers after the close. |
| **Before each ticker** | The theme's name | What comes before each ticker: the theme's name, its icon, or both. |

During a session, a strong theme's tickers show while they are still running. A strong theme with nothing running keeps its slot, under its name and state, until a ticker runs again or the theme fades.

![Settings → Tape: the theme section, with theme tickers set to hot and building themes](screenshots/settings-tape.png)

---

## 4. Theme Hunter

The **Theme Hunter** screen lists:
- the hot and building themes and sectors, with their members
- the runners no theme claims yet

If a sector keeps heating up and its runners share a headline, that is the next theme to define. Open one of its runners, read the headline, and list its words in a new theme.

---

## 5. Settings that change how themes behave

| Setting | Default | What it does |
|---|---|---|
| **Stays on a theme for** | 10 sessions | How long a stock stays on a theme after its headline last matched. |
| **Burnt after** (shown as "days with no runner") | 30 days | Days with no runner before a theme that was hot turns burnt. Range 1 to 90. |
| Tape: **Show tickers of themes** (Settings → Tape) | Hot themes only | Which themes' stocks appear on the tape. |

Colours are set under **Settings → Themes**: a colour scheme for the icons ("Icon colours"), and a colour per theme or sector if you want one.

---

## 6. Tips

- **Start with pins** for a company you already know is in a theme. Headlines come and go; pins stay.
- **Check the hover text** on the Theme column. It shows the status, runners, expected count and the reason.
- **Expect quiet.** Most themes will be quiet most of the time. That is the design: a theme should only light up when something happens.
- **Mind the day.** Crypto themes run on UTC days. Stock themes follow the US session.

---

## 7. Limits

- Themes come from headlines, so a theme is only as good as its words. A catalyst that the words miss will not show.
- Ranking uses each day's best move, read while the stock was on a screen. A stock that was never on a screen that day cannot count.
- This is a beta. The rules may change; the glyphs and the settings are the stable part.
- Themes are a way to notice patterns, not a recommendation to trade them.
