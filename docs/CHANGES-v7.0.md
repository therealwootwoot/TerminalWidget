# TerminalWidget V7.0 – Design & UI (in progress)

Design and UI only: no new data sources, no data format change. New config keys are added automatically; saved settings are never changed silently. Decisions: see the Powershell Widget project (roadmap-to-v7-decisions).

## Done so far
- **Design tokens**: one scale for spacing (4 / 8 / 12 / 16 / 24), radii (4 / 8 / 12), type sizes and motion times (at most 150 ms); `Get-Token 'surface.card'` reads colours from the palette. New palette tokens: disabled text, accent hover / pressed / subtle, text on accent – all derived from the base accent, so any Windows accent works. WCAG contrast helpers.
- **Menus**: all context and tray menus use one renderer (rounded hover, theme colours, check mark in the accent colour, separators from the border colour).
- **Status bar** (Settings → Design, on by default): data age, market state, privacy mode. Hidden in the small bar layouts.
- **In-app messages** ("toasts", on by default): short messages like "Layout gespeichert" appear bottom right in the window; click to close. Alerts still use the tray.
- **Per-monitor DPI** (on by default): the widget is DPI aware per monitor (Windows 10 1703+). When the window moves to a monitor with another scaling it restarts after a second, so everything is sharp and correctly sized. Can be switched off in Settings → Design.
- **Fresh is the default style for new installs**; existing settings stay as they are.

## Not done yet (from the V7 roadmap)
Owner-drawn controls (toggles, segmented control, chips, drop-downs), watchlist chips / sparklines / inline bars, chart legend chips and indicator panes, Analyse KPI tiles / donut / heatmap, signal gauge and dot plots, one dialog template and the import wizard, settings live preview, motion (hover fades, number roll-over), focus rings and the high-contrast auto-switch, layout preset "Focus", new welcome tour, screenshot comparison in CI.

## Tests
- Pester: scale on the 4 px grid, grid rounding, contrast ratio, accent states, token map, status bar text.
