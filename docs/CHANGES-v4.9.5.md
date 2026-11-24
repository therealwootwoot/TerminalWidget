# TerminalWidget v4.9.5 – Polish

## News tab
- **Day move only once**: the "+31,2 %" marker sits on the newest item of each ticker, not on every row.
- **Mute a source**: right-click an item → "Quelle ausblenden". Settings → Nachrichten → "Ausgeblendete Quellen zeigen" brings them all back. The right-click menu also opens the article, copies the link or opens the ticker.
- **Alarm-Wörter**: Settings → Nachrichten, e.g. `downgrade, gewinnwarnung, übernahme`. A new headline with such a word about a ticker in the depot (optionally also the watchlist) gives a tray notice and a phone push (if set up), and goes into the alert history. Each headline only once; at most 3 per load.
- **Full source name** on hover over the source column.
- News requests wait for the same rate-limit pause as the price refresh, and a rate limit on the news pauses both.

## Main window
- **Status dot** left of the status line: green = data OK, amber = pause or a bit old, red = no connection. Hover explains it. While all markets are closed, older data still counts as OK.
- **Ctrl+Y** redoes the last undo (30 seconds); Ctrl+Z works again after it.
- **Price flash fades** out over about half a second instead of switching off.
- **Tray icon** in the colour of today's depot result (green / red / grey). Settings → Farben und Fenster; without positions it follows the active ticker as before.
- **Short portfolio**: with up to 3 positions, a hint with "+ Kauf buchen ..." and "Broker-CSV importieren ..." fills the empty area.

## Portfolio
- **Beitrag heute**: new column with how much each position added to or took from today's depot result (sortable; hide it via right-click on a column header).
- **Privacy mode (F9 or `PRIV`)**: shares, values, P/L amounts and today's contribution become dots; percentages stay. Also the summary line, the Compact depot line and the tray tooltip. The Portfolio tab shows "Portfolio ••" while it is on; editing is blocked until F9 again.
- **Summary line**: realized result of this year, with the dividend part shown separately ("2026: +120,00 real. (Div. +35,00)").

## Watchlist and data
- **Analysts**: mean price target vs. price and the consensus (Kauf / Halten / ...) from Yahoo. New column "Analysten" (switch on via right-click on a column header) and in `DES` (target, range, recommendation, number of analysts). Fetched once a day together with the earnings dates.
- **52-week bar** in the "52W-H" column: the dot shows where the price sits between the year's low and high (green near the high, red near the low). Hover shows low and high.
- **Recent tickers**: the ticker search lists the last 10 opened tickers first (↺). Company names from saved profiles are searched too.

## Alerts
- **Pause an alert**: right-click in the alert list → 1 hour, 4 hours or until tomorrow 08:00; "Pause beenden" ends it. Paused alerts show `[ZZZ]` and the end time.
- **Right-click a ticker** in the watchlist or portfolio: open chart, create an alert, book a buy/sell, news tab for this ticker, compare in the chart, description (DES), remove from the watchlist.

## Chart
- The previous-close line (already in 1D) now has a "Vortag 66,40" label, also shows in 5D, and can be switched off in the chart's right-click menu.

## Everyday use
- **Ctrl+C** in the watchlist, portfolio or news list copies the whole table (visible columns, tab-separated) for Excel or an email.

## Tests
- 13 new Pester tests (movers, muting, keywords, health, flash fade, direction, privacy, analyst parsing, 52-week position, snooze, TSV); the UI smoke test covers muting, keyword notices, privacy mode, undo + redo, alert pause, the analyst column, row actions, table copy, the previous-close toggle and the status dot.
