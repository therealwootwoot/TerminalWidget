# TerminalWidget v5.0 – Depot, Chart, Workspace

Data format version 5: on the first start the widget makes a backup of all data files (`backups\vor_v5_migration...`) before anything is written. New files per depot: `cash.json`, `savingsplans.json`.

## Stage A – Depot

### Cash account (Portfolio ▾ → Cash-Konto, or `CASH`)
- Tick "Cash-Konto für dieses Depot führen" and enter today's balance. From then on, new buys subtract shares × price + fee, sales add proceeds − fee, dividends add the net amount. Bookings that existed before you switched it on are not counted again.
- Buttons for deposits, withdrawals, interest and fees, plus "Stand setzen" (enter the balance from your bank; the difference is booked as a correction).
- The list shows every movement (trades greyed). Foreign currencies are converted at today's rate.
- The portfolio summary shows "Cash: … (Gesamt …)", Analyse → Aufteilung shows cash as its own slice, and Zielgewichte can invest it.

### Risiko page in Analyse (`RISK`)
- Time-weighted return p.a., return in the period, volatility p.a., Sharpe ratio (risk-free rate adjustable, default 2 %), max drawdown with its dates, beta and correlation vs. the benchmark, best and worst day – for the depot and the benchmark side by side.
- Deposits and withdrawals are taken out of the returns, so buying more doesn't look like a gain.
- Correlation table of up to 12 positions (daily returns of the last 12 months), coloured red (move together) to blue (move opposite).
- Uses the period chosen on the Wertentwicklung page (6M / 1J / 3J / Max).

### Zielgewichte / Rebalancing (`REBAL`)
- Enter a target % per position. The page shows the current share, the drift, and what to buy or sell (amount and shares) and the share afterwards.
- "Neues Geld" and (optionally) the cash account are invested too. "Nur kaufen" never sells: the money goes to the most underweight positions.
- Positions without a target are left alone. Targets are saved per depot. "Gleich verteilen" sets equal weights.
- A suggestion without fees and taxes – not investment advice.

### Sparpläne (Portfolio ▾ → Sparpläne, or `SPAR`)
- Ticker, amount, fee, currency, day of month (1–28), start month. On the due day a buy is booked at that day's close (weekend: the trading day before). Months the widget missed are booked on the next start (up to 24).
- Shown in the transaction history with the note "Sparplan …"; a tray notice says how many were booked.

### Heatmap (`HEAT`)
- The depot as tiles: size = share of the depot, colour = today's change (stronger from ±3 %). Switch to the watchlist (equal tiles). Click a tile to open the ticker.

### Other
- New menu ▾ next to "Transaktion" in the portfolio: Cash-Konto, Sparpläne, Rebalancing, Risiko, Heatmap.
- The Analyse window is wider (seven pages).
- Glossary entries: Sharpe, Max. Drawdown, Volatilität, Beta, Rebalancing, Cash-Konto.
- Tests: 9 new Pester tests (cash movements and balance, flow-adjusted returns, risk statistics, beta / correlation, rebalancing, savings plan dates, treemap); the UI smoke test switches the cash account on, books a real savings plan and opens the new pages with loaded data.

## Stage B – Chart

### Drawing tools (chart right-click → Zeichnen, key `D`, or `DRAW H` / `DRAW T` / `DRAW F`)
- **Horizontal line**: one click. **Trend line**: click start and end; it continues to the right edge. **Fibonacci**: click the start and the end of a move; levels 0 / 23.6 / 38.2 / 50 / 61.8 / 78.6 / 100 % with prices.
- While drawing a trend line or Fibonacci, a dashed line follows the mouse. Esc or a right-click cancels.
- Drawings are saved per ticker (`drawings.json`) as time + price in the ticker's own currency, so they stay in place when you zoom, change the timeframe or the display currency.
- Right-click a drawing: **Alarm auf diese Linie** (horizontal line → price alert above / below; trend line → an alert that moves along the line and fires when the price crosses it), delete it, or delete all drawings of the ticker. `DRAW CLEAR` does the same.

### Own trades in the chart
- Your buys (green ▲ below the price) and sales (red ▼ above) of the active ticker at the booked price and day. Hover shows date, shares, price and note. Switch off in the chart menu ("Eigene Käufe / Verkäufe anzeigen").
- Ex-dividend markers now show the amount on hover too.

### Compare up to 3 tickers
- `MSFT CMP` adds MSFT to the comparison, the same command again removes it; up to 3 at once (pink, cyan, violet lines with their own % labels). `CMP` alone or "Vergleich entfernen" clears all. The watchlist / portfolio right-click "Im Chart vergleichen" adds too.

### Heikin-Ashi candles
- `K` or the chart-type button now cycles Linie → Kerzen → Heikin-Ashi. The candles are smoothed; price tags, the crosshair and the period return keep using the real prices.

### Fixes
- An alert pause (v4.9.5) is no longer lost when the widget restarts.

### Tests
- 8 new Pester tests (time ↔ bar mapping, Fibonacci, line hit test, trend line alerts, Heikin-Ashi, chart type cycle, comparison list); the UI smoke test draws all three kinds with real mouse clicks, finds them with a right-click hit test, creates line alerts, books a trade and renders it, cycles the chart types with K and loads three comparisons.

## Stage C – Workspace

### Draggable dividers (Terminal layout)
- Drag the gap between the chart and the lists up or down to change the chart height; drag the gap between Watchlist and Portfolio (when side by side) to share the width differently. Double-click a divider = default sizes. Saved.

### Watchlist groups
- New drop-down next to the watchlist title: **Alle** or one of your groups (e.g. Tech, ETFs, Dividenden), with the number of tickers. "+ Neue Gruppe ..." creates one, "Gruppe löschen" removes the shown group (the tickers stay in the watchlist).
- Right-click a ticker → **Zu Gruppe**: tick / untick groups or create a new one with this ticker. A ticker can be in several groups. Drag & drop ordering works inside a group too.

### Hover card
- Rest the mouse on a ticker in the watchlist or portfolio: a card shows name, price and day change, the day range, a 52-week bar, the 5-day line, your position (amounts hidden in privacy mode), the next earnings date and the analyst view. Off in Settings → Erklärungen.

### Settings search
- "Suchen:" at the bottom of the settings window: matching settings light up, the rest fades (umlauts are folded, so "grosse" finds "Größe").

### Back where you were
- A list shown as a full page (Terminal) and an open Analyse window come back after a restart; `P` opens Analyse on the page you used last.

### Tests
- 4 new Pester tests (divider percentage, split widths, groups, settings search); the UI smoke test drags the chart height, checks the full-page memory, filters the watchlist by a group via the right-click menu and shows / hides the hover card.
