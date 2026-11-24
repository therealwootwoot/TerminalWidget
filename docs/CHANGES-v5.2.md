# TerminalWidget v5.2 – Design update

No data format change. Everything new can be switched in **Settings → Design** (and the theme / accent in **Darstellung**).

## Two styles: Refined and Fresh (`STYLE`, Settings → Design → Stil)
- **Refined** (default): the familiar layout, cleaner – rounded buttons, softer lines, quieter frames.
- **Fresh**: the lists and the chart sit on **rounded cards** with more space between them, buttons without plain borders, a slim accent line under the header that fades out, calmer list headers.
- `STYLE` switches between the two, `STYLE FRESH` / `STYLE REFINED` picks one. Changes apply immediately.

## Chart
- Softer grid (dotted in Fresh), lighter frame.
- The area under the line fades in three steps in the line colour (stronger in Fresh); round line joins.
- Last price: a dotted guide to the axis, a dot with a soft halo on the last point, and a rounded price tag.
- Crosshair tags and the hover box (HUD) are rounded; the HUD and the measure label have a soft shadow.

## Lists
- Only horizontal row lines, in a softer colour.
- **Row height**: Kompakt / Normal / Bequem (Settings → Design), also in the Analyse and ticker-analysis windows.
- **Zebra rows** (optional): every second row slightly lighter.
- Fresh: list headers in the card colour with muted text and a little inner padding.

## Icons
- Segoe Fluent Icons (Windows 11) or Segoe MDL2 Assets (Windows 10) on the header buttons (refresh, settings, pin, minimise), the portfolio menu button, the alert “+” and the fullscreen button.
- Icons in the tray menu, the chart menu and the right-click menu of tickers.
- Settings → Design → “Symbole auf Knöpfen und in Menüs” switches back to text; without the icon font the text stays automatically.

## Themes and colours
- New theme **Graphite**: neutral grey without the blue tint, close to the Windows 11 dark look (`THEME GRAPHITE`, T cycles through it).
- Accent colour **Windows**: takes the accent colour set in Windows (Personalisation → Colours).
- One warning colour per theme (amber; darker in Light, yellow in Terminal) for earnings badges, pre-market, warnings, alerts.

## Ticker bar (Compact layout)
- Speed Langsam / Normal / Schnell, smoother movement (about 60 steps a second), soft fade at both ends.

## Fixes
- Ticker analysis: the fundamentals were lost when they were stored (all values showed “-”). Fixed and covered by a test.
- Ticker analysis: the “Kennzahlen” title no longer slides under the left title when the window is narrower than the screen.

## Tests
- 4 new Pester tests (style numbers, Windows accent colour, ticker bar speed, stored fundamentals); theme cycle includes Graphite.
- The UI smoke test switches Refined / Fresh with `STYLE`, checks icons, row heights, zebra, Graphite, the Windows accent and icons off, and takes **screenshots** of the main window (Terminal, Standard, Compact) and of the ticker analysis, settings and analysis windows – saved as a CI artifact and in the test log.
