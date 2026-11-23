# TerminalWidget v4.2 – Dividends, earnings dates, buy dates

## Buy dates
- **New position → asks for the buy date.** Saving a new position in the portfolio editor opens a small date picker (default today). The buy is booked with that date, so value history, XIRR and the yearly report start at the right point.
- **Analysis → Wertentwicklung → "Kaufdaten ..."** lists
  - positions (or parts of them) that have **no buy booking** – enter a date and an *opening booking* ("Anfangsbestand (nachgetragen)") is added. The price is chosen so your average cost stays the same; the position itself is not changed.
  - **editor bookings** (dated the day you typed them in) – enter the real date to move them.
- Dates before a stock split are converted automatically: a buy of 100 NVDA in 2023 is stored as 10 shares at 10× the price (the units of that day), so the 2024 10:1 split is applied correctly afterwards.
- Accepted date formats: `TT.MM.JJJJ`, `T.M.JJ`, `JJJJ-MM-TT`, `TT/MM/JJJJ`.

## Dividends page (Analysis → "Dividenden")
- Per position: payment rhythm (monthly / quarterly / half-yearly / yearly, detected from history), last dividend, dividend per year, **yield**, **yield on cost**, **expected income next 12 months** (in the analysis base currency), next ex-date, pay date, quarterly figures.
- Ex-dates announced by Yahoo are shown exactly; otherwise they are estimated from the rhythm and marked with `~` (grey).
- Dividends that stopped (no payment for 1.5 cycles) are marked "ausgesetzt?" in amber and left out of the forecast.
- Monthly bar chart of the expected payments for the next 12 months.
- Summary: expected income (total and per month), portfolio yield, yield on cost, dividends **received this year** (from your bookings), number of payers.
- Forecast = last 12 months' payments per share × today's share count, gross, at today's exchange rates.

## Earnings dates
- Quarterly-figure and dividend dates are fetched from Yahoo (quoteSummary) for portfolio, watchlist and the active ticker, about once a day, in the background (10 min schedule, max. 15 symbols per run).
- **Orange ticker** in portfolio and watchlist = quarterly figures within 7 days (tooltip with the date). The header shows "Zahlen morgen · Name".
- **Tray notice the day before** (or on the day) for portfolio positions. Settings → Benachrichtigungen → "Hinweis am Vortag von Quartalszahlen" (on by default).
- New data file `events.json` (included in backups).

## Other
- Split events for opening bookings are loaded with the complete history (`range=max`) and no longer replaced by the shorter analysis window.
- New glossary entries: Dividendenrendite, Yield on Cost, Ex-Tag, Dividendenprognose, Quartalszahlen, Anfangsbestand.
