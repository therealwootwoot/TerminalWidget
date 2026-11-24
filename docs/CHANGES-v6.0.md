# TerminalWidget V6.0 – Data & analysis

No data format change (schema stays 5: all new data lives in new files). New files in the data folder: `provider_cache.json` (Finnhub answers, one day per ticker). New config keys are added automatically.

## What the free tiers deliver (checked November 2026)
- **Twelve Data, free Basic plan**: 8 requests per minute, 800 per day, **US markets only**, no earnings data. The widget uses it for daily prices when Yahoo has none.
- **Finnhub, free**: 60 requests per minute. Basic financials with yearly / quarterly series, earnings surprises (last 4 quarters), recommendation trends, earnings calendar. Candles and price targets may be paid – the provider test finds out with your key.
- European listings (e.g. SAP.DE, EUNL.DE) are not covered by either free tier; they stay on Yahoo.
- **Country weights vs. MSCI World**: no free source found (ETF country data is paid on both providers). Not built; the Allocation page keeps showing your own countries.

## Data & sources
- **Own API keys** in Settings → Daten & Aktualisierung (Twelve Data, Finnhub). They are stored encrypted for your Windows user (like the phone-push token), never written to the log or the diagnostics ZIP, and left out of the settings export.
- **Provider test** (`PROV` or the button next to the keys): probes every endpoint with your key and shows what works. Only what tested OK is used; untested endpoints are tried once.
- **Fallback for daily prices**: when Yahoo returns no history (ticker analysis, daily cache / signals), the widget tries Twelve Data, then Finnhub (US tickers).
- **Request budget**: Twelve Data max 7 per minute / 780 per day, Finnhub max 55 per minute (a little below the plans). A request that would exceed the budget is skipped with a message ("Tageslimit erreicht – wieder ab morgen"). The day count survives restarts.
- `HEALTH` shows per provider: key yes / no, which data is usable, requests today.

## Improved ticker analysis (with a Finnhub key, US stocks)
- **Figures over the years**: P/E, P/S, P/B, margins, ROE, EPS, current ratio, debt / equity for the last 5 years ("25.1 → 28.4 → 31.0 (2021–2025)").
- **Valuation vs. history on the provider's quarterly data**: today's P/E, P/S, P/B against years of quarters, not just the snapshots collected since v5.7.
- **Earnings history**: EPS actual vs. estimate, surprise in %, and the **price reaction** from the last close before the report to the first close after it (report dates from the Finnhub earnings calendar, prices from the daily history; "amc" = after the close).
- **Analyst trend**: buy / hold / sell now vs. 3 months ago, the average score and "more positive / more negative / unchanged". Price target (mean, range) if your key can get it.
- Without a key, US tickers show a short hint where to add one.
- Answers are cached per ticker and day (`provider_cache.json`), so opening the window again costs no requests.

## Tests
- 9 new Pester tests: symbol mapping, key redaction, provider errors (incl. Twelve Data's HTTP-200 errors), Twelve Data / Finnhub bars, budget, yearly + quarterly series, earnings surprise with price reaction, analyst trend, provider report.
- UI smoke test (no real keys in CI): log redaction, key round trip, ticker analysis with sample Finnhub answers (screenshot), budget skip, provider lines in HEALTH.
