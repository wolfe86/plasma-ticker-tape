# Security policy

## Reporting a vulnerability

Please report security problems **privately**, not in a public issue:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Describe what you found, how to reproduce it, and what it affects.

Only the maintainer sees the report. This is a personal project maintained in spare time, so there is no promised response time; valid reports are fixed as time allows, and reporters are credited in the fix unless they would rather not be.

## What is in scope

- The widget in `package/`, including the scanner it runs (`package/contents/code/`)
- Anything that lets outside data, a setting or a news link run a command, read or write files outside the widget's own cache, or leak the user's settings

Out of scope: the third-party data sources themselves (Yahoo Finance, Finviz, stockanalysis.com, Nasdaq, SEC EDGAR and the news feeds) and how they answer.

## Supported versions

Only the latest release is supported. Fixes ship as a new release.

## Trust model: settings run as you

The widget runs with your desktop user's rights, and some settings are, by design, instructions to run something. Anyone who can change your Plasma settings can already run programs as you, so these are not treated as vulnerabilities — but you should know what they do:

- **Sound player** (Settings → Data) is a command line. The widget runs it, with the sound file's path added, to play an alert sound. Whatever you type there runs as you.
- **Scanner folder** (Settings → Data) is a folder of Python code. The widget's bridge imports the scanner's modules from it in place of the built-in ones, so any `.py` file there named like a scanner module runs as you. Point it only at a folder you control.

## What the widget does to keep outside data out

- **Symbols and other data from Yahoo, Nasdaq and Finviz never reach a shell bare.** Every argument to the scanner bridge is quoted on its own, symbols are checked against the shape of a ticker before use, and the bridge itself drops any argument outside `A–Z 0–9 . : -`.
- **Settings → Data travel in a file, not on a command line.** The SEC contact, research folder and earnings settings are written to a file readable only by you (under `$XDG_RUNTIME_DIR`, else `~/.cache`) and read from there by the bridge, so other users of the machine cannot see them with `ps`. While they are being rewritten after a change, they are briefly on the command line of that one write.
- **Headlines are plain text.** Feed and scanner text has its entities decoded before any markup is stripped, so an escaped tag in a headline is removed rather than turned into live markup. Pictures are taken only from `http://` and `https://` addresses.
- **News source headers** (a paid feed's key) are sent only over `https://`. A reply that was redirected to another site is thrown away. Note that the request that followed the redirect has already carried the header there — Qt's network layer forwards custom headers across redirects and the widget cannot stop it — so give a key only to a source whose address you trust not to redirect.
- **Downloads are capped:** a scanner reply over 16 MB (64 MB for SEC filings data) and a news-source reply over 8 MB is abandoned rather than read into memory.
