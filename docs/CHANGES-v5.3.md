# TerminalWidget v5.3 – Settings pages, style findable, quick access

No data format change. Three new config keys (`SettingsPage`, `SettingsW`, `SettingsH`) are added automatically.

## The style is easy to find now
- The setting was in a long settings window that did not fit on a 768 px screen.
- **Stil** now sits at the very top of **Settings → Design**, as two cards: *Refined – wie gewohnt, feiner* and *Fresh – Karten, mehr Luft*. A click switches, and the main window shows the result straight away.
- Also without the settings window: **layout menu** (top right: “Stil: Refined / Stil: Fresh”), **tray menu** (“Stil”), and the `STYLE` command as before.
- The settings search finds it as “Stil”, “Style”, “Fresh” and “Refined”.

## Settings window with pages
- A list on the left with eight pages: **Darstellung, Design, Layout, Daten & Aktualisierung, Alarme & Benachrichtigungen, Depot, Tastatur & Befehle, Sonstiges**. Each page scrolls on its own; the window can be resized.
- Settings that belong together stay together (Design: style, theme, accent, row height, zebra, icons, rounded corners).
- New on the **Depot** page: currency (Auto / EUR / USD / CHF / GBP), risk-free rate for the Sharpe ratio, and buttons that save and open the cash account, savings plans, CSV import and target weights.
- Window size and the last open page are remembered. First open: Design.
- **Live preview**: style, theme, accent, row height and zebra rows change the main window while you choose; Cancel puts everything back.

## Search, markers, reset
- The search (Ctrl+F in the window) looks through all pages: it opens the page with hits, the list on the left counts the hits per page, a page title (“tastatur”, “depot”) jumps to that page. Enter no longer presses OK.
- A **dot** in front of a setting = changed from the default (the tooltip names the default). A dot in the page list = this page has changes.
- **Seite zurücksetzen** puts the settings of the current page back to the default; saved only with OK.

## Settings as a file
- Settings → Sonstiges → **Einstellungen exportieren / importieren**, e.g. for a new PC.
- Only settings travel: no depots, alerts, transactions, window positions, and not the phone-push token (it is encrypted for this Windows user). Import makes a backup first and restarts the widget.

## Ctrl+K reaches everything
- Typing three letters or more also offers **settings** (`SET ZEBRA-ZEILEN ...` opens the window on the right page with the setting highlighted) and **menu entries** of the tray, layout and chart menus (`MENU DURCHKLICKEN ...`).
- `SET <words>` and `MENU <name>` work as commands, too.

## Not in this release
- Reacting to a DPI change when the window moves to a monitor with different scaling (WM_DPICHANGED): the widget is “system DPI aware”, so Windows does not send that message, and all sizes are computed once at start. Needs a decision, see the roadmap.

## Tests
- 9 new Pester tests: the eight pages, search incl. “fresh” not landing on “Data & refresh”, hit counts and page choice, “changed” comparison, settings export / import with type checks, Ctrl+K entries.
- UI smoke test: pages, window height vs. screen, style search from another page, live preview, marker and reset, `SET ZEBRA`, settings index, `MENU` from the layout and tray menus, settings file round trip; screenshots of the Design page and of a search.
