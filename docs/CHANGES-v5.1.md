# TerminalWidget v5.1 – Automatic currency, more analysis

No data format change (still version 5). Event data is fetched once more after the update so the fundamentals are filled in.

## Automatic currency
- New currency mode **Auto** (the default): every price is shown in the currency the ticker trades in – ABBN.SW in CHF, SAP.DE in EUR, NVDA in USD, VOD.L in GBP. That applies to the header price, the chart (price axis, cost line, alert lines, drawings, own trades, CSV export), the watchlist, the ticker search, the ticker bar, the hover card, DES and the movers list.
- Depot values, sums, the portfolio, the tray line and Analyse stay in your **base currency**.
- The currency button / `W` now cycles **Auto → EUR → USD → CHF → GBP**. Choosing a fixed currency switches Auto off and makes it the base currency; choose your base currency first, then Auto.
- Price alerts are entered in the currency the price is shown in (the alert dialog says which).
- Before Yahoo has answered for a new ticker, the currency is taken from the exchange suffix (.SW, .DE, .L, .TO, .T, …).

## Ticker analysis (`NVDA TA` / `NVDA FA`, right-click a ticker, chart menu)
One window per ticker, left technical, right fundamental:
- **Technical signals** from two years of daily prices: trend vs. SMA 200 / 50 / 20, golden / death cross with its age, RSI 14, MACD with the direction of the histogram, Bollinger %B, momentum 3 / 6 / 12 months, position in the 52-week range, average daily range (ATR), volume compared with usual. Each row is coloured positive / negative / neutral; the summary counts them ("überwiegend positiv / gemischt / überwiegend negativ").
- **Support and resistance**: swing highs and lows of the last year, grouped, with the number of touches; drawn as dashed lines in the 12-month chart with SMA 50 / 200.
- **Fundamentals**: market cap, P/E (trailing and forward), PEG, P/S, P/B, EV/EBITDA, dividend yield, payout ratio, gross / operating / net margin, return on equity, revenue and earnings growth, debt to equity, current ratio, free cash flow, beta.
- **Comparison**: the median of your other tickers (depot + watchlist) in the same sector, when there are at least two; each value is marked better / similar / weaker. Without peers a few absolute rules apply (PEG under 1, current ratio under 1, shrinking revenue, …).
- A summary of classic indicators – not investment advice.

## Analyse: new page "Beitrag"
- **Contribution per position** in the chosen period (6M / 1J / 3J / Max): start value, buys, sales, dividends, end value, contribution (end + sales + dividends − start − buys), the position's return (modified Dietz) and its share of the depot result. Sorted from the biggest gain to the biggest loss, with a total.
- **Dividends of the next 12 months** (projection from the Dividenden page) and per month.
- **Scenario**: "Markt −20 %" (adjustable −60 … +60 %): each position moves by its beta × that value. Beta against your benchmark over the last 12 months, otherwise Yahoo's beta, otherwise 1.0 (marked). Shows the estimated change per position and for the depot.

## Analyse: new page "Vergleich"
- **Depot against up to 6 indices** (default EUNL.DE, ^GSPC, ^GDAXI, ^ATX; editable), all converted to your base currency, as % lines from the start of the period. The depot line is time-weighted, so buying more does not look like a gain.
- Table per line: return in the period, p.a., volatility, max. drawdown, **rolling 12-month return** now and its worst / best value over the whole history.
- **Sectors vs. MSCI World**: your depot's sector weights against the MSCI World (sector weights of the iShares MSCI World ETF, URTH, loaded once per session), with the difference in percentage points. ETFs and positions without a sector are listed as "Andere".
- The period buttons now exist on Beitrag and Vergleich too and switch all pages together; Basis / Benchmark / Neu laden moved to the second row of the window.

## Tests
- 9 new Pester tests (currency guess and W cycle, contribution, per-ticker value series, time-weighted index, rolling returns, scenario, support / resistance and signals, fundamentals and peer comparison, sector comparison).
- The UI smoke test switches Auto / EUR and checks header and chart currency for SAP.DE (EUR) and NVDA (USD), opens Beitrag (incl. scenario and period switch), Vergleich (index lines, sector table) and the ticker analysis for MSFT with real data, and looks inside each window before it closes.
