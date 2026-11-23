# Terminal Widget

A desktop stock widget for Windows written in PowerShell (WinForms). It runs anywhere from a small ticker strip up to a terminal-style layout with chart, watchlist, alerts and portfolio. Quotes come from Yahoo Finance. No installation and no dependencies.

![Tests](../../actions/workflows/tests.yml/badge.svg)

## Start

1. Keep all files in one folder.
2. Double-click `TerminalWidget_Start.bat`. It starts Windows PowerShell 5.1 with a hidden console.

Your data (settings, portfolio, alerts, transactions, profiles, event dates) lives in `%LOCALAPPDATA%\TerminalWidget`, never in this folder. When upgrading from v3 ("Financial Terminal Widget") it is copied over automatically; see [docs/UPGRADE-v4.0.md](docs/UPGRADE-v4.0.md). What changed in each version: [v4.2](docs/CHANGES-v4.2.md), [v4.1](docs/CHANGES-v4.1.md).

## Files

| File | Role |
|---|---|
| `TerminalWidget.ps1` | UI, data refresh, events |
| `TerminalWidget.Core.ps1` | Pure logic (no UI, no network); dot-sourced at start |
| `TerminalWidget.Core.Tests.ps1` | Pester 5 tests for the Core |
| `TerminalWidget_Start.bat` | Launcher |
| `.github/workflows/tests.yml` | CI: parse check, encoding check and Pester on Windows PowerShell 5.1 and PowerShell 7 |

## Keyboard

`L` layout, `C` compact, `P` portfolio analysis, `G` glossary, `H` all shortcuts, `T` theme, `W` currency, `1`-`6` time range, `F11` fullscreen chart.

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
