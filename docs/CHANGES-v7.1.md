# TerminalWidget V7.1 - Design & UI (second part)

Builds on V7.0 (branch `v7.0`). Design and UI only: no new data sources, no data format change. One new config key: `PaneDivider` (share of the main chart, default 0.72).

## New
- **Segmented control** in the settings for short choices (language, moving average, lower chart field, row height, ticker speed, signal alerts). Keys Left / Right work.
- **Slider** next to the number field for the opacity (still exact input by number).
- **Drop-downs with rounded closed box** (accent border on hover / focus) in the main window and settings.
- **Indicator pane**: the divider between chart and RSI / MACD pane can be dragged (saved); in the Fresh style the pane is a rounded card.
- **Allocation donut** in Analyse > Aufteilung (small shares merged into "Rest"), colours derived from the accent.
- **Dot plot** per key figure in the ticker analysis (column "Lage"): your value among the peers, median tick.
- **Valuation band**: fair-price range from the P/E history (20th to 80th percentile) with the current price; green = below, red = above.
- **One info card look**: hover card = card surface, border, rounded (like toasts and menus).
- **Dialog template** (`New-StandardDialog`): title + subtitle, 16 px margins, primary button bottom right, Enter / Esc, inline error line. Used by the text input dialogs (new depot: empty / too long name is shown inline).
- **Settings preview** on the Design page: card, price, pill, buttons and switches in the current style, theme and accent, live.
- **Number roll-over** of the header price (150 ms, only when motion is on and the move is under 20 %).
- **Status bar**: requests per minute.
- **Tokens**: the fixed colours (busy, ruler / drawings, series colours) are palette tokens now (`Busy`, `Mark`, `Violet`, `Pink`, `Cyan`, `Lime`, `Blue`, `Neutral`).
- **Accessibility**: accessible names for buttons and inputs, tab order in dialogs follows the reading order.

## Tests
- Pester: donut slices, dot plot, valuation band, pane layout, segment layout, roll values, status bar request rate.
- UI smoke: new controls and the dialog template, divider hit test, accessibility note, GDI note (the CI runner reports 0 GDI objects, so that check only protects against large leaks on a real desktop).
- CI: screenshot report and contact sheet (from V7.0).

## Not done
- Page fade when switching tabs.
- News thumbnail in the info card (needs images from a new source).
- Focus ring for plain text boxes and grids (caret and selection stay the visual cue).
- Screenshot baseline: the CI reports changes only once `docs/shots-baseline-<shell>.json` exists (copy `_hashes.json` from a good run).
- Appearance has not been checked on a real screen by me - please look at status bar, chips, donut, divider and the settings page.
