# TerminalWidget 7.1.1 - Startup diagnosis and fixes

Builds on 7.1 (branch `v7.1`). No new data sources, no data format or config change.

## Diagnosis
- The log shows how long the main script and each `ui\` part (02-12) take to load. `13-Startup` runs the message loop; its time is only part of "window shown after".
- HEALTH shows the same times ("Startzeit je Teil").
- HEALTH counts only log errors since the current start (still within the last 400 lines).

## Fixes
- Compact / Ticker bar a little wider (760 / 600 instead of 698 / 576) so the layout button and market status have room.
- Layout button wider; the pin button is narrower in exchange.
- Shorter watchlist title (the hint stays in the tooltip) and shorter sort entries.
- Wider "valid until" drop-down in the alarm panel (the note field is narrower).
- Wider settings navigation.
- The exchange rate bar shows as many pairs as fit; all rates stay in the tooltip.
- RSI is drawn below its label row, so the line no longer runs over the label or the top edge.
- HEALTH / help text window: app icon and dark scrollbars.
- Portfolio editor shows numbers with the system's decimal separator; comma and point are both accepted.

## To check on the real PC
The visual fixes were not looked at on a screen yet.
