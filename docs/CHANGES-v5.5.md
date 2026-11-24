# TerminalWidget v5.5 – Polish, depot extras, robustness

No data format change. New files in the data folder: `notes.json` (ticker notes, in backups and exports) and `daily_cache.json` (daily prices, a cache that is safe to delete). New config keys are added automatically.

## Notes per ticker
- Free text per ticker (thesis, reason for buying, goals): right-click a ticker → **Notiz ...**, the **Notiz** button in the ticker analysis, or `NVDA NOTE` (`NVDA NOTE Cloud-Wachstum` saves straight away).
- The hover card shows the first two lines.
- Notes go into backups and the data export. Cash, savings plans and drawings were missing from the data ZIP export before and are now included too.

## Robustness
- `HEALTH`: checks the data files, write access, backup age, data source (live vs. cache), icon / number fonts, errors in the log, start time, memory and requests in the last hour.
- `DIAG` (also Settings → Sonstiges): diagnostics ZIP with the log, the settings **without** access data or personal lists, the health report and version info. No depot data.
- Start time is written to the log.

## Quick wins
- **Privacy mode** (F9) now also covers the Analyse window (grids, sums, chart axis and hover) and the yearly report.
- **Dialogs remember their place** (and size): Cash, savings plans, news / info windows, Analyse, ticker analysis, glossary, transactions, alert log, yearly report, notes. If that screen is gone, the dialog opens centred again.
- **Export**: in the Analyse window, *Export ▾* saves the current page as an HTML report or a CSV for Excel, or as an image. The chart menu has *Chart als Bild kopieren / speichern* and *Ganzes Fenster als Bild kopieren*; command `IMG` (`IMG SAVE`, `IMG WIN`).
- **Loading skeleton**: tickers without a quote yet show soft grey bars instead of "...".
- **Stale price**: while the exchange is open, a price that has not been updated for a while gets a clock symbol (◷) and a warning colour.

## Chart
- **Percent axis** (chart menu or `SCALE PCT`): the axis shows the change from the first visible bar.
- **Support / resistance** from the daily prices (the same as in the ticker analysis) as optional lines (chart menu).
- **Ctrl + drag** zooms into the marked range; `Z` or the chart menu resets it. A plain drag still measures.
- New drawings: **zone** (rectangle, e.g. a buy zone) and **text note** (`DRAW R`, `DRAW N`, chart menu → Zeichnen).
- **Fullscreen toolbar** (top right): line, trend line, Fibonacci, zone, text, zoom reset, close.

## Depot extras
- **Savings plans**: *Dynamik %* raises the amount every full year since the start; *Pause* skips months (e.g. `7, 8` or `Jul, Aug`, not booked later). The *Jetzt* column shows the next amount.
- **Scenario per sector or currency** (Analyse → Beitrag): besides *Markt (Beta)*, e.g. "Sektor: Technology −25 %" or "Währung: USD −10 %".
- **Dividend income** (Analyse → *Einkommen*): received dividends per month and year as a colour calendar, with year totals, monthly average and change to the prior year.

## Ticker analysis – first step
- **Signal column** in the watchlist (hidden by default, header right-click): the signal score of the ticker analysis, coloured, with the summary as a tooltip.
- **Daily cache**: daily prices and signals per ticker are fetched once a day and shared by the signal column and the support / resistance lines. This is the base for v5.7 and V6.

## Broker import (Trading212)
- Columns are now recognised: *No. of shares*, *Withholding tax*, *Exchange rate*, *Currency (Total)*, *Currency conversion fee* and other fee columns.
- Fractional shares are kept exactly.
- Fees in the account currency are converted into the price currency with the row's exchange rate, but only if the row's numbers agree. Otherwise a note is shown.
- Dividends are booked gross in the instrument currency (shares × per share), with the withholding tax as the fee.
- **Deposits, withdrawals and interest on cash** go into the cash account, if it is switched on, and duplicates are skipped. A backup is made before the import.
- An anonymised sample file is included in `testdata/trading212-history-sample.csv`.
- Computershare / EquatePlus: still on hold (waiting for an export sample).

## Look & feel
- Fresh style: the navigation tabs are soft pills, and the active one has an accent underline.

## Moved to a later release
- Watchlist groups as tabs, rounded owner-drawn ticker search / drop-downs, and dividers in the Standard layout (all three need a layout rework of the header; planned for v5.7).
- Country weights vs. MSCI World: the Allocation page already shows countries; the MSCI comparison needs a data source and moves to V6.

## Tests
- New Pester tests: notes, health, diagnostics config, privacy mask, CSV / HTML export, dialog placement, percent axis, zoom window, zones, daily cache, signal column, pause months, plan increase, group scenario, dividend calendar, Trading212 sample.
- New UI smoke steps for all of the above, plus 7 screenshots (privacy, percent axis, support / resistance, zone + text, fullscreen toolbar, dividend calendar, Fresh tabs + skeleton).
