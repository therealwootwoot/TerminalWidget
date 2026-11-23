# Terminal Widget v4.0 - upgrade notes

Formerly "Financial Terminal Widget" (v3.0.1). Platform: Windows, Windows PowerShell 5.1 (launcher default) or PowerShell 7. No new dependencies.

## Files (keep in one folder)

| File | Role |
|---|---|
| `TerminalWidget.ps1` | UI, data refresh, events |
| `TerminalWidget.Core.ps1` | Pure logic (dot-sourced at start); must sit next to the widget |
| `TerminalWidget.Core.Tests.ps1` | Pester 5 tests for the Core |
| `TerminalWidget_Start.bat` | Launcher (hidden window, Windows PowerShell 5.1 by full path) |
| `.github/workflows/tests.yml` | Optional: runs parse check + Pester on Windows PowerShell 5.1 and 7 in GitHub Actions |

The `.ps1` files are **UTF-8 with BOM** (real umlauts now). Windows PowerShell 5.1 reads files without a BOM as ANSI, so keep the BOM when you edit them. VS Code: "Save with Encoding > UTF-8 with BOM".

## v4.0.1 (fix)

- Windows PowerShell 5.1 logged two `[ERROR] ... FindSystemTimeZoneById ... "America/New_York" wurde ... nicht gefunden` lines at every start. These were harmless because the fallback worked, but they were misleading. The Windows time-zone id is now tried first, and expected lookup failures are no longer logged. New test for it.
- Update: replace `TerminalWidget.ps1`, `TerminalWidget.Core.ps1` and `TerminalWidget.Core.Tests.ps1`. Data and settings are unchanged.
- Tested by the user on Windows PowerShell 5.1.19041: v4.0 ran 131 of 131 Pester tests green, the widget runs, the v3 data was migrated and the quote cache works.

## Important: v3.0.1 did not start in Windows PowerShell 5.1

The `NvidiaWidget.Core.ps1` you had contained a "v3.1 PHASE 1" block with the PowerShell-7-only operator `??`. Windows PowerShell 5.1, which the launcher uses, cannot parse that file, so the widget failed at startup. The block also called six functions that don't exist anywhere (`Get-Str`, `Set-StatusText`, `Save-WidgetConfig`, `Set-ActiveTicker`, `Save-PortfolioPosition`, `Request-ChartRedraw`). Nothing called the block, so v4.0 removes it. The new CI parse check under 5.1 catches this kind of error.

## Upgrade from v3.0 / v3.0.1

1. Quit the running widget (tray icon > Beenden). If you forget, v4.0 detects the old instance and offers to stop it.
2. Put the four v4.0 files into a folder (the old folder is fine). The old `nvidia_widget.ps1` etc. can stay; v4.0 doesn't use them.
3. Start with `TerminalWidget_Start.bat`.
4. On the first start v4.0:
   - **copies** `config.json`, `portfolio.json`, `alerts.json`, `transactions.json` and the caches from `%LOCALAPPDATA%\NvidiaWidgetV2` to `%LOCALAPPDATA%\TerminalWidget`. The old folder is not changed.
   - backs the copied files up to `%LOCALAPPDATA%\TerminalWidget\backups\<timestamp>_vor_v4_migration\` before the schema-4 migration.
   - replaces an autostart shortcut "Financial Widget.lnk" that points to `nvidia_widget.ps1` with "Terminal Widget.lnk".
   - shows "Daten aus v3 übernommen" in the status line.

## Rollback to v3.0

Start the old `NVDA_Start.bat`. v3.0 still works on its untouched `NvidiaWidgetV2` folder. Changes made in v4.0 (new bookings, alerts) are not in that folder; copy the JSON files back by hand if you need them (v3.0 ignores the new config keys). If you rolled back the autostart: delete "Terminal Widget.lnk" in the Startup folder and enable autostart in v3.0 again. Note: v3.0.1 itself needs the `??` fix (or the v3.0 Core) to start in Windows PowerShell 5.1.

## New in v4.0

**Rename.** Files, window title ("Terminal Widget v4.0"), tray text, data folder, mutex and autostart shortcut.

**Layouts, from a simple ticker to a terminal.** Use the layout button at the top right (formerly "Compact"), the tray menu "Layout", or the **L** key (next layout). **C** still toggles between Compact and the last big layout, and **Esc** leaves a small bar.

| Layout | Shows |
|---|---|
| Ticker | Borderless strip: ticker, price, change, 5-day mini chart. Accent frame, draggable. |
| Compact | The v3 bar with market status and optional scrolling tape |
| Standard | The v3 window with tabs |
| Terminal | Chart on top, watchlist/alerts and portfolio below at the same time. Side by side when the window is wide enough (about 1550 px at 100 % scaling, e.g. maximized on a 1920 screen), otherwise one of them, chosen with the Portfolio / Watch tab buttons |

Settings > "Layout und Fenster": layout, window opacity (30-100 %), which panels Terminal shows, chart height in Terminal. The panel choice is also in the layout menu. Standard and Terminal each remember their own window size.

New theme **Terminal** (amber on black), also on the T key.

**Hover explanations.**
- Glossary of 43 terms (RSI, SMA, VWAP, Bollinger, EK, G/V, Anteil, 52W-H, Re-Arm, Vor-/Nachbörse, Layouts, ...). Open it with **G** or Settings > "Glossar öffnen". It is searchable.
- Tooltips in three levels: **Aus / Kurz / Ausführlich** ("Ausführlich" adds the explanation of the term), plus an adjustable delay. Settings > "Erklärungen".
- Explanations on the grid column headers (watchlist and portfolio).
- In the chart: rest the mouse on the legend (SMA, VWAP, BB20, comparison), the range badge, the RSI label, EK / alert line tags, the PRE/POST shading or the zoom hint.

**Quick wins.**
- Starts with the last known quotes (`quote_cache.json`) instead of an empty window. Cached prices are grey with a tooltip "Kurs aus dem Cache", and alerts never fire on cached quotes.
- Refreshes right after the PC wakes up. A 1-second timer gap of 90 s or more counts as a wake-up and also ends an old rate-limit pause.
- Status line: grey = fresh, amber = older than 2 refresh intervals (at least 45 s), red = offline or older than 10 intervals (at least 5 min).
- Real umlauts in the whole UI.
- **Jahresreport** (Portfolio > Historie... > "Jahresreport..."): realized gains/losses and dividends of a year in a base currency (EUR/USD/CHF/GBP). Every booking uses the FX rate of its own date, loaded once per session from Yahoo (EURxxx=X, daily). The cost basis is kept as a moving average in the base currency, so currency gains are included. Dividends show gross, withheld tax/fees and net. Rows where no history was available use today's rate and are marked "~". CSV export included. This is a helper calculation, not tax advice.

## Behaviour changes

| Change | Effect | Migration |
|---|---|---|
| Data folder `%LOCALAPPDATA%\TerminalWidget` | v3 and v4 data diverge after the upgrade | Automatic copy, old folder untouched |
| Mutex `Local\TerminalWidget_v4_Mutex` + detection of the v3 mutex | v3 and v4 can't run at the same time | Dialog offers to stop the old one |
| Header button "Compact" is now the layout menu | One click opens the menu instead of toggling | C key unchanged |
| `config.json`: `SchemaVersion` = 4, new keys `Layout`, `LastFullLayout`, `TerminalShowWatch`, `TerminalShowPortfolio`, `TerminalChartPct`, `TerminalBottom`, `TerminalW/H`, `Opacity`, `TooltipMode`, `TooltipDelayMs`, `ReportBase` | v3 ignores them | Automatic, backup first |
| Alerts are not evaluated on cached quotes | No false alarms right after the start | None |
| Files are UTF-8 with BOM (were pure ASCII) | Umlauts display correctly | Keep the BOM when editing |

## Testing checklist

### Done here (no Windows / PowerShell available)
- [x] Bracket/string balance of all `.ps1` files with a PowerShell-aware checker (strings, here-strings, `$( )`, comments). It found a real error during development, an extra `)` in two converted tooltip calls. It confirmed the `??` and undefined-function problems in the uploaded v3.0.1 Core.
- [x] No PowerShell-7-only syntax (`??`, `?.`, `&&`, `||`, ternary, `-AsHashtable`, `-Parallel`) in any file
- [x] Every called `Verb-Noun` command is defined or a built-in cmdlet; no function is defined in both Core and widget
- [x] Every glossary key used by the UI exists (also a Pester test)
- [x] Expected values of the new report and Terminal-layout tests checked against an independent Python port
- [x] Encoding: `.ps1` = UTF-8 with BOM + CRLF, launcher = ASCII + CRLF

### Still to run on Windows (none of these have been executed)
- [ ] `Invoke-Pester .\TerminalWidget.Core.Tests.ps1` passes on PowerShell 5.1 and 7 (or push to GitHub with the workflow)
- [ ] Start via `TerminalWidget_Start.bat`: window appears, no errors in `%LOCALAPPDATA%\TerminalWidget\widget.log`
- [ ] First start with v3 data: data copied, `backups\..._vor_v4_migration` exists, `config.json` has `"SchemaVersion": 4`, old folder unchanged, status "Daten aus v3 übernommen"
- [ ] Start while v3 is running: dialog "Die alte Version ... läuft noch", Yes stops it and v4 starts
- [ ] Autostart: old "Financial Widget.lnk" replaced by "Terminal Widget.lnk"; enable/disable in Settings works
- [ ] Umlauts display correctly everywhere (title, buttons, dialogs, help, tooltips, CSV in Excel)
- [ ] Layout button: menu shows 4 layouts with the current one checked; each layout looks right; L cycles; C toggles; Esc leaves Ticker/Compact
- [ ] Ticker: borderless strip with accent frame, draggable by the header, price + mini chart visible
- [ ] Terminal: chart top, both lists side by side on a wide/maximized window, one list (switchable via the tabs) when narrow; panel options in the layout menu and the settings work; chart-height % works
- [ ] Standard and Terminal remember separate window sizes; maximize remembered
- [ ] Opacity slider changes the window transparency
- [ ] Theme "Terminal" (amber) looks right; T cycles Dark > OLED > Light > Terminal
- [ ] Tooltip modes: Aus = none (also no grid / chart tips), Kurz = one line, Ausführlich = with explanation; delay applied
- [ ] Chart: rest the mouse on SMA/VWAP/BB20/RSI label/range badge/EK line tag: explanation appears and disappears when moving away; also in fullscreen (F11)
- [ ] Glossary (G): search filters, selecting a term shows the text
- [ ] Restart the widget: quotes appear immediately in grey, turn normal after the first refresh; no alert fires at startup
- [ ] Sleep the PC for 2+ minutes and wake it: log "Resume detected", quotes refresh at once
- [ ] Pull the network cable: status turns red ("Offline"); reconnect: back to grey
- [ ] Jahresreport: year/base preselected, FX history loads ("Lade Wechselkursverlauf"), rows and totals plausible against your broker statement, "~" rows only if FX history failed, CSV opens in Excel
- [ ] Regression: alerts (incl. RSI/SMA), transactions, rebuild, compare, zoom/measure, fullscreen, compact tape, tray hide/restore, currency switch, settings OK/Cancel
