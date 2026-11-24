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
