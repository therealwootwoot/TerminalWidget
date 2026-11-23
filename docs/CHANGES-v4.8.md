# TerminalWidget v4.8 – Chart and layout

- **Log scale**: Y key, chart right-click menu, or `SCALE LOG` / `SCALE LIN`. The price axis, all lines, levels and the crosshair use it. A small "log" label marks it.
- **Ex-dividend markers**: blue diamonds at the bottom of the chart show past ex-dividend days (hover shows the amount).
- **Next earnings date** in the top right of the chart when it is within 30 days.
- **Compact / Ticker bar**: choose what it shows (Settings → Layout → "Compact / Ticker zeigt ...", or `BAR`):
  - the absolute day change
  - pre/after-market prices
  - the mini chart
  - the market status, or today's depot result instead
- **Edit in the portfolio table**: select the Stück or EK cell and type (or press F2). This changes the position directly, without a booking. Ctrl+Z undoes it.
- **Update check**: the About window now reads `version.json` from the repository, so no Git tags are needed. A test keeps the file in line with the widget version.
- Fix: with MACD in the lower panel, hovering no longer shows an RSI value.
