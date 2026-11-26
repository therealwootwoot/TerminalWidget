# TerminalWidget V7.0 – Design & UI

Design and UI only: no new data sources, no data format change. New config keys are added automatically; saved settings are never changed silently. Decisions: see the Powershell Widget project (roadmap-to-v7-decisions).

## Done so far
- **Design tokens**: one scale for spacing (4 / 8 / 12 / 16 / 24), radii (4 / 8 / 12), type sizes and motion times (at most 150 ms); `Get-Token 'surface.card'` reads colours from the palette. New palette tokens: disabled text, accent hover / pressed / subtle, text on accent – all derived from the base accent, so any Windows accent works. WCAG contrast helpers.
- **Menus**: all context and tray menus use one renderer (rounded hover, theme colours, check mark in the accent colour, separators from the border colour).
- **Status bar** (Settings → Design, on by default): data age, market state, privacy mode. Hidden in the small bar layouts.
- **In-app messages** ("toasts", on by default): short messages like "Layout gespeichert" appear bottom right in the window; click to close. Alerts still use the tray.
- **Per-monitor DPI** (on by default): the widget is DPI aware per monitor (Windows 10 1703+). When the window moves to a monitor with another scaling it restarts after a second, so everything is sharp and correctly sized. Can be switched off in Settings → Design.
- **Fresh is the default style for new installs**; existing settings stay as they are.
- **Toggle switches** instead of check boxes in the settings window (still real check boxes underneath).
- **Buttons**: focus ring (2 px accent, keyboard focus only) and a pressed state.
- **Smoke test**: contrast of every theme (text 4.5 : 1, muted text and accent 3 : 1).

- **The UI script is split** into `TerminalWidget.ps1` (start, storage, config) and 12 parts in `ui\` (`02-Data.ps1` … `13-Startup.ps1`). The parts are dot-sourced in the old order and run in the same scope, so nothing behaves differently. Keep the `ui` folder next to the script.
- **Watchlist group chips** above the list replace the drop-down: click = show group, + = new group, right click = delete, drag a ticker onto a chip = add it to the group. Too many groups move behind a … chip.
- **Day change as a pill** (Settings → Design, off by default): coloured background in the watchlist and portfolio.
- **Chart legends are clickable**: a click on BB20, SMA / EMA or VWAP hides that indicator (the button under the chart switches it back on).
- **Analyse → Wertentwicklung**: key figure tiles (value, result, return p.a., dividends, period) above the summary; green / red only for gains / losses.
- **Heatmap**: rounded tiles with a small gap.

- **Button hover fade** (150 ms, only when motion is on – follows Windows animation setting and Settings → Design).
- **High contrast**: follows the Windows high-contrast mode automatically (can be switched off).
- **Heatmap** has a colour legend.
- **Layout command `LAYOUT FOCUS`** and a new page "Neu in V7" in the welcome tour.
- **Drop-down items** use the theme (hover colour, selected row).
- **Signal gauge** in the ticker analysis: day and week signal on a red-grey-green scale.
- **CSV import**: step indicator (Datei, Spalten, Prüfen, Import).
- **CI**: screenshot report (same / changed / new vs. `docs/shots-baseline-<shell>.json`) in the job summary and a contact sheet as artifact.

## Not done yet (from the V7 roadmap)
Segmented control and slider, closed drop-downs drawn by the app, indicator panes (title, card style, draggable divider), allocation donut, dot plots and valuation band, unified hover card, one common dialog template, settings mini live preview, replacing the remaining hard-coded colours by tokens, number roll-over and page fade, focus rings on all controls, accessible names / tab order check, GDI handle and timing checks in the smoke test. These can follow in V7.1.

## Tests
- Pester: scale on the 4 px grid, grid rounding, contrast ratio, accent states, token map, status bar text.
