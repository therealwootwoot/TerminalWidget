# TerminalWidget v5.7 – Analysis without new providers

No data format change. New file in the data folder: `fund_history.json` (valuation snapshots, one per ticker and day). New config keys are added automatically.

## Ticker analysis
- **Daily and weekly signals**: the signal table has a *Woche* column, with the same indicators calculated on weekly bars (+ / − / ·; the tooltip has the value). Below it, **one plain-language sentence** for both time frames, e.g. "Kurzfristig negativ, mittelfristig positiv: eher ein Rücksetzer im längeren Aufwärtstrend."
- **Own peer group** (`NVDA PEER AMD INTC TSM`, or the *Vergleichsgruppe ...* button): the *Vergleich* column then uses the median of these tickers instead of your tickers of the same sector. Fundamentals of peers outside your depot / watchlist are loaded on demand. `NVDA PEER -` switches back to the sector.
- **Valuation vs. own history**: from now on, one snapshot per day is kept for P/E, forward P/E, P/S, P/B, EV/EBITDA and dividend yield. After 20 days, the fundamentals table shows today's value against the median, the range and a rank (cheap / usual / expensive vs. its own history).

## Signals over time
- **Signal-change notes**: once a day, the daily data of the depot (or depot + watchlist) is checked. You get a note (tray, phone push if set up) when a ticker's signal turns *überwiegend positiv* / *negativ*, or when the price crosses yesterday's support / resistance. Settings → Alarme & Benachrichtigungen → *Hinweis bei Signal-Wechsel* (Depot / Depot + Watchlist / Aus).
- **Chart markers**: with *Unterstützung / Widerstand* switched on, the 50/200-day crossings (golden / death cross) from the daily data are shown as triangles at the bottom of the chart.

## News
- **Own RSS / Atom feeds** (Settings → Daten & Aktualisierung, one address per line): their headlines join the news tab. A headline that contains the name of one of your tickers is assigned to that ticker (filter Depot / Watchlist / ticker). Feeds are read with DTDs and external entities switched off.

## Accessibility
- New theme **Contrast** (`THEME CONTRAST`, T cycles through it): black, white text, yellow accent, clearly visible borders.
- Icon buttons get an accessible name for screen readers (taken from their tooltip).

## Provider layer (groundwork)
- New data requests (daily bars, news search) are built in one place (`Get-ProviderUrl` in Core); V6 adds Twelve Data / Finnhub behind the same call. No change in behaviour.
- `HEALTH` shows the requests of the last hour **per data source** (Yahoo, each RSS feed) – the base for request budgets in V6.

## Moved to a later release
- English for messages, tooltips and the glossary (a large text job – the window texts are English already).
- Thumbnails in the news hover.
- Watchlist groups as tabs, rounded owner-drawn drop-downs, dividers in the Standard layout, focus outlines.
- Scenarios and peer groups on the Analyse *Vergleich* page.

## Tests
- 9 new Pester tests: weekly bars, the time-frame sentence, signal changes, 50/200 crossings, peer lists, valuation snapshots and rank, RSS / Atom parsing (incl. a DTD / entity attempt), feed merge with ticker names, provider URLs; theme cycle includes Contrast.
- UI smoke test: ticker analysis with weekly column, peer group and valuation history (screenshot), signal-change alert on / off, Contrast theme with chart markers (screenshot), requests per data source in HEALTH.
