# TerminalWidget 7.3 - Clarity

Builds on 7.1.1. No new data sources, no data format or config change.

- Portfolio: the "EK" and "Kurs" headers name the base currency.
- Analyse: the "Rendite p.a." tile says why it shows "-" (XIRR needs 30 days since the first booking).
- Analyse > Wertentwicklung: the text under the tiles no longer repeats them. It keeps the benchmark line and says that the values use daily closes and the exchange rate history, so they can differ from the main window. The text is grey.
- Analyse chart: the base currency is shown above the value axis.
- Alarms: grey placeholder text in the ticker, value and note inputs (visible while empty).
- Status bar: says why data is refreshed less often ("Märkte zu - Abfrage alle N min" or a Yahoo pause). The market status is now only in the header.

## Narrow windows
- Header: the ticker name is cut off with "..." and the market status switches to a short form.
- Toolbar: the command button gets shorter and the rate bar shows fewer exchange rates (since 7.1.1).

## To check on the real PC
The visual changes were not looked at on a screen yet.
