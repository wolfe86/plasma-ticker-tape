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
