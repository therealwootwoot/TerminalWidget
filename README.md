# Terminal Widget

A desktop stock widget for Windows written in PowerShell (WinForms). It runs anywhere from a small ticker strip up to a terminal-style layout with chart, watchlist, alerts and portfolio. Quotes come from Yahoo Finance. No installation and no dependencies.

![Tests](../../actions/workflows/tests.yml/badge.svg)

## Start

1. Keep all files (and the `ui` folder) together.
2. Double-click `TerminalWidget_Start.bat`. It starts Windows PowerShell 5.1 with a hidden console.

Your data (settings, portfolio, alerts, transactions, profiles, event dates, alert history) lives in `%LOCALAPPDATA%\TerminalWidget`, never in this folder. When upgrading from v3 ("Financial Terminal Widget") it is copied over automatically; see [docs/UPGRADE-v4.0.md](docs/UPGRADE-v4.0.md). What changed in each version: [V11.6](docs/CHANGES-v11.6.md), [V11.4](docs/CHANGES-v11.4.md), [V11.2](docs/CHANGES-v11.2.md), [V11.0](docs/CHANGES-v11.0.md), [V10.8](docs/CHANGES-v10.8.md), [V10.6](docs/CHANGES-v10.6.md), [V10.4](docs/CHANGES-v10.4.md), [V10.2](docs/CHANGES-v10.2.md), [V10.0](docs/CHANGES-v10.0.md), [V9.0](docs/CHANGES-v9.0.md), [V8.0](docs/CHANGES-v8.0.md), [V7.7](docs/CHANGES-v7.7.md), [V7.5.1](docs/CHANGES-v7.5.1.md), [V7.5](docs/CHANGES-v7.5.md), [V7.3](docs/CHANGES-v7.3.md), [V7.1.1](docs/CHANGES-v7.1.1.md), [V7.1](docs/CHANGES-v7.1.md), [V7.0](docs/CHANGES-v7.0.md), [V6.0](docs/CHANGES-v6.0.md), [v5.7](docs/CHANGES-v5.7.md), [v5.5](docs/CHANGES-v5.5.md), [v5.3](docs/CHANGES-v5.3.md), [v5.2](docs/CHANGES-v5.2.md), [v5.1](docs/CHANGES-v5.1.md), [v5.0](docs/CHANGES-v5.0.md), [v4.9.5](docs/CHANGES-v4.9.5.md), [v4.9](docs/CHANGES-v4.9.md), [v4.8](docs/CHANGES-v4.8.md), [v4.4-4.7](docs/CHANGES-v4.4-4.7.md), [v4.3](docs/CHANGES-v4.3.md), [v4.2](docs/CHANGES-v4.2.md), [v4.1](docs/CHANGES-v4.1.md).

## Files

| File | Role |
|---|---|
| `TerminalWidget.ps1` | Start, storage, config; loads the parts in `ui\` in order |
| `ui\*.ps1` | The rest of the UI, data refresh and events, split into 12 parts (V7.0) |
| `TerminalWidget.Core.ps1` | Pure logic (no UI, no network); dot-sourced at start |
| `TerminalWidget.Core.Tests.ps1` | Pester 5 tests for the Core |
| `TerminalWidget_Start.bat` | Launcher |
| `.github/workflows/tests.yml` | CI: parse check, encoding check and Pester on Windows PowerShell 5.1 and PowerShell 7 |

## Keyboard

`F1`-`F4` chart / portfolio / watchlist / news, `F6` overview, `F9` privacy mode, `Ctrl+C` copy a list, `L` layout, `C` compact, `P` portfolio analysis, `G` glossary, `H` all shortcuts, `T` theme, `W` currency, `1`-`6` time range, `F11` fullscreen chart.

## Tests

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck   # once
Import-Module Pester -MinimumVersion 5.0 -Force
Invoke-Pester .\TerminalWidget.Core.Tests.ps1 -Output Detailed
```

GitHub Actions runs the same tests on every push, on both PowerShell versions.

## Rules for changes

- The `.ps1` files are **UTF-8 with BOM** and CRLF. Windows PowerShell 5.1 reads files without a BOM as ANSI. CI fails without the BOM.
- Stay **Windows PowerShell 5.1 compatible**: no `??`, `?.`, `&&`, `||`, ternary `? :`, `ConvertFrom-Json -AsHashtable`. CI parses every file with 5.1.
- New pure logic goes into `TerminalWidget.Core.ps1`, with tests.

## Disclaimer

For personal information only, not investment or tax advice. The yearly report is a helper calculation. Your bank's or broker's statements are authoritative. Data from Yahoo Finance can be delayed or wrong.
