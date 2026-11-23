# TerminalWidget v4.4 – v4.7

## v4.4 – Command line and terminal functions
- **Command line** (Ctrl+K, numpad `/`, or the `> Befehl` button in the bar under the header), with autocomplete, Tab to complete and a list of recent commands. Bloomberg-style:

  | Command | What it does |
  |---|---|
  | `NVDA` | open the ticker |
  | `NVDA GP 1Y` | chart, optional range |
  | `NVDA DES` | description: profile, key figures, dates, your position |
  | `NVDA N` | news (Yahoo Finance; double-click opens the article) |
  | `NVDA DVD` | 10-year dividend history with yield, frequency and your yearly income |
  | `NVDA EE` | upcoming earnings / ex-date / pay date |
  | `NVDA ALRT TRAIL 8` | create an alert (`>= 150`, `TAG- 3`, `EK+ 20`, `52H`, `VOL 2`, `RSI+ 70`, `SMA+`, `DTAG- 2` ...) |
  | `NVDA WL` / `NVDA CMP` / `NVDA TX` | add to watchlist / compare / book a transaction |
  | `PORT`, `ANA`, `DVD`, `CAL`, `TOP`, `FX`, `LOG`, `REP` | portfolio, analysis, portfolio dividends, event calendar, today's winners/losers, exchange rates, alert history, yearly report |
  | `TF 3M`, `LAYOUT TERMINAL`, `THEME OLED`, `SET`, `PUSH`, `GLOS`, `HELP`, `ABOUT` | range, layout, theme, settings ... |

- **About** dialog with version, paths and an update check (GitHub tags).
- The **tray tooltip** shows today's portfolio result in a second line.
- **Less polling while markets are closed**: when every market you watch is closed, quotes are fetched only every 10 minutes (Settings → Aktualisierung; 0 = off). F5 refreshes at any time.

## v4.5 – Depots, CSV import, backups
- **Several depots** (e.g. second broker, paper trading): selector at the top of the portfolio tab (create / rename / delete), or `PF <name>`. Each depot has its own positions and bookings; alerts and company data are shared.
- **Broker CSV import** (`IMP`, or *Import* in the transaction history):
  - detects the delimiter and skips text above the table
  - recognises the columns of common German and English exports (Datum/Date, Typ/Type, ISIN/Symbol, Stück/Quantity, Kurs/Price, Betrag/Amount, Gebühr/Fee, Steuer/Tax, Währung/Currency); the mapping can be changed
  - reads 1.234,56 as well as 1,234.56
  - looks up ISINs on Yahoo, with a preferred exchange (e.g. Xetra)
  - leaves out bookings that are already there
  - can recalculate the positions from the bookings afterwards
- **Daily automatic backup** (the last 20 are kept, depots included) and a **restore** dialog (`BAK`, or Settings → Wiederherstellen).
- **Export / import** all data as a ZIP (Settings), e.g. to move to another PC. The Telegram token has to be entered again there.
- **Portable mode** (Settings → Portabel machen): the data moves to a `data` folder next to the script, so the widget can run from a USB stick.

## v4.6 – Customisation
- **Columns**: right-click a column header in the watchlist / portfolio to show or hide columns, drag headers to reorder them. Order, widths and visibility are remembered.
- **Indicators**: EMA instead of SMA, MACD (12/26/9) instead of RSI in the lower panel (Settings → Indikatoren, or `IND MACD` / `IND EMA`).
- **Colours**: schemes for up/down including colour-blind safe blue/orange, or your own colours; optional ▲▼ arrows; your own accent colour; a coloured background behind the day change in the header; price cells briefly flash when the price changes.
- **Global hotkey** (default Ctrl+Alt+W, Settings): show / hide the widget from any program.
- **Click-through** (tray menu or `CT`): the mouse passes through the widget to the window behind it. The hotkey brings it back.
- The window **snaps to screen edges**.
- **Undo** instead of confirmations: deleting an alert, a position or a watchlist ticker can be reverted with **Ctrl+Z** for 10 seconds.
- **Own layouts**: `LAYOUT SAVE <name>` stores layout, theme, colours, chart settings and window options; `LAYOUT <name>` restores them, `LAYOUT DEL <name>` deletes.
- **Welcome tour** on the first start (again with `TOUR`).

## v4.7 – Quality and language
- **UI smoke test in CI**: the real widget is started on Windows PowerShell 5.1 and PowerShell 7. It switches layouts, tabs and themes, runs commands, opens and closes every dialog, switches depots, and tests undo, click-through, backups and the English mode. Any programming error fails the build.
- **English user interface** (Settings → Sprache → English, after a restart): windows, buttons, column headers, menus, the command list and the help are in English. Messages, hover explanations and the glossary stay German.

## Not done, and why
- **Stooq as a second data source**: since early 2026 Stooq needs an API key (obtained via a CAPTCHA) and has a daily limit. A fallback without your own key is therefore no longer possible. The widget keeps using Yahoo with the query1/query2 fallback and the quote cache.
- **Log scale, choosing the metrics of the Compact/Ticker layouts, editing directly in the grid**: these would touch the chart and layout code in many places. They stay on the roadmap.
- **Splitting the script into several files**: no benefit for using the widget. The new smoke test now provides the safety net the split was meant to give.
