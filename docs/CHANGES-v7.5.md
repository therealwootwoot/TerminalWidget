# TerminalWidget 7.5 - UI completion

Builds on 7.3. No new data sources and no data format change. Two new settings: `PortSimOpen`, `WatchDetail`.

- Focus ring for text fields and tables (2 px accent line). It also shows when you click into them.
- Button focus ring fixed: the 7.0 code read a protected .NET property, which PowerShell returns as empty. The ring now shows when a button has focus without having been clicked.
- Standard dialog template for the small dialogs: compare ticker, one-line text input, buy date, Compact / Ticker options (which now also has "Abbrechen").
- Portfolio: the top-up / target price calculator is closed by default. "Nachkauf-Rechner" opens it. "Transaktion", the menu, "Historie" and "Analyse" are now in one row, so the closed editor is lower and the list is taller.
- Watchlist: the alarm column grows with the window (252 to 420 px).
- Watchlist: wide views (from about 1200 px, scaled) show details for the selected ticker; the "Details" button hides them.

## Not done
- Page fade on tab change. WinForms has no way to fade a panel with its controls; a screenshot overlay would fade through the background colour and then show the new page, which is likely to look like flicker. The roadmap allowed dropping it in that case. This was not tried on a screen.
- Screenshot baseline file.
- The large tool windows (analysis, import, history, reports) keep their own layout.

## To check on the real PC
None of the visual changes were looked at on a screen yet.
