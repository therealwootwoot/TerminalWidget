# Terminal Widget v4.1 - portfolio analytics

Update from v4.0.x: replace the three `.ps1` files (or `git pull`). Data and settings carry over unchanged. New data file: `profiles.json` (sector/country per ticker), which is included in backups.

## Portfolio analysis (P key or Portfolio > "Analyse")

A resizable window with three pages:

**Wertentwicklung (value history)**
- Depot value over time, **rebuilt from your bookings** (buys, sells, dividends) with Yahoo's daily closes since your first booking. The base currency is selectable, and each booking uses the FX rate of its own date.
- **Netto investiert:** buys minus sale proceeds, so you can see when the curve is above what you put in.
- **Benchmark as a shadow portfolio:** every buy and sell is replayed on the same day with the same amount in the benchmark. The default is EUNL.DE (iShares Core MSCI World, Xetra, EUR); any Yahoo symbol works (e.g. `^GSPC`, `^ATX`), and an empty field turns it off. This compares fairly: same money, same timing.
- Ranges 6M / 1J / 3J / Max, with a hover line showing date, values and result.
- Summary: value, net invested, dividends, result, **XIRR p.a.** (money-weighted return), the same for the benchmark, and the difference in percentage points.
- Positions entered without bookings (or with more shares than booked) can't be rebuilt. They're listed with the missing share count.

**Rendite (returns)** per position and in total: value, cost basis (moving average at booking-date FX, buy fees included), unrealized, realized, dividends, total, total %, XIRR p.a. (from 30 days of holding). Closed positions are shown grey. Positions without bookings use the editor's EK at today's FX and get no XIRR.

**Aufteilung (allocation)** by position, currency, sector or country, as bars:
- **Concentration warning:** groups above the threshold (default 20 %, adjustable) turn amber, with a dashed line marking the threshold.
- Sector and country come from Yahoo. The cookie + crumb flow tries quoteSummary; if Yahoo refuses (this happens in the EU sometimes), the sector still comes from the search API and the country must be set by hand.
- Each position's sector and country can be **overridden by typing in the grid** (manual values in blue); clearing the cell returns to the automatic value. ETFs/funds, crypto and indices get their own group.
- Profiles are fetched at most every 30 days per ticker; "Neu laden" forces a refresh.

## Stock splits (fix, affects v4.0)

Bookings from before a split (e.g. NVIDIA 10:1 on 2024-06-10) are now converted with the split ratio:
- **Jahresreport:** a sale after a split of shares bought before it is no longer capped at the pre-split count with a warning; the result is correct.
- **Position neu berechnen:** shares and EK are converted, and the preview names the splits it applied.
- **Analysis:** history and holdings use split-adjusted units.

Split events come from Yahoo (`events=split`) and are cached for the session.

## Other

- 8 new glossary terms (XIRR, Netto investiert, Benchmark, Unrealisiert, Gesamtergebnis, Aufteilung, Klumpenrisiko, Aktiensplit), on the new controls and column headers.
- Portfolio panel: "Historie" and "Analyse" side by side. Help (H) lists P.
- CI: actions/checkout v5, upload-artifact v5.

## Tests

- Pester covers the new Core logic: ledger, XIRR (checked against an independent solver), value history, benchmark shadow, splits in rebuild/report/history, Yahoo parsing, allocation, profiles. 155/155 green in CI on Windows PowerShell 5.1 and PowerShell 7 for the Core part.
- **Not tested automatically:** the analysis window (WinForms UI) and the live Yahoo requests (crumb, histories). Please check:
  - [ ] P opens the window; "Lade Kursverläufe ..." then the curve appears
  - [ ] Curve, net invested and benchmark plausible; hover shows values; 6M/1J/3J/Max work
  - [ ] Rendite: values match the portfolio tab (apart from FX timing); Summe row; XIRR plausible
  - [ ] Aufteilung: Position/Währung/Sektor/Land; sector/country filled (log: "Yahoo crumb obtained" or "not available"); typing a sector updates the bars; clearing returns to automatic; threshold changes colours
  - [ ] Base currency switch and a different benchmark (e.g. `^GSPC`) + Enter reload
  - [ ] Jahresreport / Position neu berechnen for a split stock with bookings before the split
  - [ ] Theme switch: the "Analyse" button follows the theme
