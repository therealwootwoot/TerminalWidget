# ==============================================================================
# TerminalWidget.ps1 - Terminal Widget v4.0 (formerly "Financial Terminal Widget")
# ------------------------------------------------------------------------------
# Files (keep together in one folder):
#   TerminalWidget.ps1             this script (UI, data, events)
#   TerminalWidget.Core.ps1        pure logic, dot-sourced at start
#   TerminalWidget.Core.Tests.ps1  Pester 5 tests:  Invoke-Pester .\TerminalWidget.Core.Tests.ps1
#   TerminalWidget_Start.bat       launcher (hidden window)
# Platform: Windows, Windows PowerShell 5.1 or PowerShell 7 (WinForms).
# Encoding: UTF-8 WITH BOM (Windows PowerShell 5.1 reads BOM-less files as ANSI
# and would garble the umlauts). Keep the BOM when editing.
# ------------------------------------------------------------------------------
# v4.0.1 fix:
#  - Windows PowerShell 5.1: no more "FindSystemTimeZoneById ... America/New_York
#    nicht gefunden" errors in widget.log at every start (the Windows time zone
#    id is tried first; expected lookup failures are not logged)
#
# v4.0 changes:
#  Rename
#  - Files, window title, data folder (%LOCALAPPDATA%\TerminalWidget), mutex
#    and autostart shortcut renamed. On the first start the data is COPIED
#    from NvidiaWidgetV2 (the old folder is left untouched for a rollback),
#    then backed up before the schema-4 migration. A running v3.x instance is
#    detected and can be stopped; an old autostart shortcut is replaced.
#  Layouts
#  - Four presets, layout button in the header / tray menu / L key:
#    Ticker (borderless strip: price + mini chart), Compact (bar + tape),
#    Standard (tabs), Terminal (chart on top, watchlist and portfolio at the
#    same time below; side by side when wide enough)
#  - Terminal theme (amber on black), window opacity, Terminal panel options
#  Hover explanations
#  - Glossary of ~40 terms; tooltips in three levels (off / short / detailed)
#    with adjustable delay; explanations on grid column headers and on the
#    chart legend (SMA, VWAP, BB, RSI, range badge, levels); glossary window (G)
#  Quick wins
#  - Starts with the last known quotes (quote_cache.json, shown grey until
#    the first refresh) instead of an empty window
#  - Refresh right after the PC wakes up (timer gap detection)
#  - Status: amber when older than 2 intervals, red when offline / very old
#  - Real umlauts in the UI
#  - Yearly report: realized gains/losses and dividends in a base currency,
#    converted at the FX rate of each booking date (history dialog)
#  - Fix: the v3.0.1 Core file contained PowerShell-7-only code (??) and did
#    not load in Windows PowerShell 5.1 (the launcher's host); removed
#
# v3.0.1 fixes:
#  - Settings (gear button) crashed with "Das Argument kann nicht an den
#    Parameter Path gebunden werden ..." where Windows reports no Startup
#    folder (seen on Windows Server 2022): autostart path now has a fallback
#  - Errors in any button/event handler are logged + shown in the status line
#    instead of the WinForms "Unbehandelte Ausnahme" dialog
#
# v3.0 changes (major version: reliability + data integrity):
#  Fixes
#  - Alarm panel: the "Bedingung" dropdown was empty on every fresh start
#    (list was defined after the combo box was filled) -> alerts could only
#    be created via the chart context menu. Lists now come from Core functions.
#  - Positions in currencies other than EUR/USD/CHF (e.g. GBP booked via the
#    transaction dialog) were silently turned into EUR on load. Any ISO code
#    is kept now; a one-time check reports positions already affected.
#  - Portfolio editor no longer overwrites a GBP/other position currency with
#    whatever the currency box happened to show.
#  - Symbol lookups no longer pump DoEvents (re-entrant clicks while waiting);
#    typed tickers are resolved in the background, known ones instantly.
#  - Alarm sound no longer blocks the UI (system sound instead of Console.Beep)
#  New
#  - GBP as display currency (header, W key, settings)
#  - Transaction history: "Position neu berechnen" (replay of all buys/sells,
#    average cost, preview before applying); offered after deleting a booking
#  - Settings: "Backup jetzt" (copy of all data files) and "Log oeffnen"
#  - Automatic backup of the data files before the v3 schema migration
#  - Empty states: hints in the alarm list and the empty portfolio
#  - Alarm value field explains its unit per condition (tooltip)
#  Maintenance
#  - Version in one place ($script:AppVersion); config carries SchemaVersion
#  - CSV exports escape text fields (separator, quotes, formula injection)
#  - Grids of hidden tabs are no longer rebuilt on every refresh
#  - More pure logic + Pester tests in NvidiaWidget.Core.ps1
#
# v2.9 changes:
#  Chart
#  - Cost basis (EK) of the position and price alerts drawn as levels; levels
#    outside the visible range get an edge marker with an arrow
#  - Right-click in the price area: "Alarm: >= / <= <price under the mouse>"
#  - Ctrl + wheel zooms around the mouse, Shift + wheel pans, Z resets
#  - Drag with the left mouse button measures change, %, bars and duration
#  - Comparison ticker (X / context menu) as a %-performance line, HUD shows it
#  Alerts
#  - New conditions: RSI >= / <= (1h), > SMA / < SMA (price vs. fast SMA, 1h)
#  - Optional re-arm (15m / 1h / 4h / 1 day) once the condition is false again
#  - Note per alert (shown in list + notification)
#  Market hours
#  - Rule-based holiday calendars (incl. Easter) for NYSE/Nasdaq, Xetra, SIX,
#    LSE and Wiener Boerse: status "Feiertag (...)", correct next open,
#    upcoming holidays in the tooltip
#  Watchlist / portfolio
#  - Header click sorts (3rd click = own order), sort glyphs
#  - Watchlist order by drag & drop or Alt+Up/Down
#  - Transactions: buy / sell / dividend incl. fees, realized P/L, history
#    window with filter, delete and CSV export; realized P/L in the summary
#  Robustness / maintenance
#  - Automatic fallback query1 <-> query2.finance.yahoo.com (sticky)
#  - Pure logic moved to NvidiaWidget.Core.ps1 + Pester tests
#  - Settings: "Mit Windows starten" (shortcut in the Startup folder)
#
# v2.8 changes:
#  Performance
#  - Data refresh runs in a background RunspacePool (HTTP + JSON parsing off
#    the UI thread): no more DoEvents re-entrancy, window stays responsive
#  - Live ticker/watchlist search is asynchronous as well
#  - Chart is rendered once into a cached bitmap; crosshair/HUD are drawn as a
#    light overlay -> smooth mouse tracking, no full re-render per mouse move
#  - Chart re-render only when its content changed (signature check)
#  - Intraday merge via SortedDictionary (no Sort-Object), session repair and
#    currency conversion in ONE pass over the last 2 days only, FX factor
#    computed once per series instead of 4 calls per bar
#  Fixes
#  - Status bar shows the FX pairs relevant for the display currency
#    (EUR/USD, USD/CHF, GBP/... incl. portfolio currencies), all in tooltip
#  - Maximized state is remembered (start + restore from tray)
#  - Window is pulled back on screen after size restore / monitor change
#  - HUD width measured from its text (was fixed, long values were cut off)
#  - DST-aware session math via exchange time zone (pre/post classification
#    of cached bars and "opens at" countdown were 1 h off around DST switches)
#  - Daily bars no longer classified as pre-market (whole chart was shaded
#    for exchanges that stamp daily bars at midnight)
#  New
#  - Crosshair with price tag (right axis), time tag (bottom axis), RSI value
#    in the RSI pane, close marker; HUD shows bar change % and volume
#  - Settings dialog (gear button / key S): intervals, indicator periods,
#    RSI levels, theme/accent, notifications, compact tape, data folder
#  - Watchlist: 5D sparkline column
#  - Compact mode: scrolling ticker tape (click = open, hover = pause)
#
# v2.7 changes:
#  - Window is resizable / maximizable (size is remembered), layout follows
#  - Chart fullscreen window: F11, double-click on chart, "Vollbild" button
#    or context menu. Esc / F11 / double-click closes. Keys 1-6 = timeframe
#  - Fix: File.Replace got "" instead of null as backup path (PowerShell turns
#    $null into "" for string args) -> "Der Pfad hat ein ungueltiges Format"
#  - Status bar shows "Stand" (time of last successful data refresh) and
#    turns amber when data is stale; refreshed every second
#  - Chart toggle buttons sized to their text (labels were cut off)
#  - Bar sessions are re-classified after merging with the cache (fixes
#    double "PRE" labels / dark stripes), implausible ext-hours wicks clipped
#  - Range badge says what the % refers to (vs. previous close / period)
#  - Watchlist & portfolio columns fill the grid width (BTC price was cut off)
#
# v2.6 changes:
#  - Market hours: live status (Offen / Pre / Post / Zu / 24/7) with countdown,
#    trading hours in local time as tooltip, optional "market open" balloon
#  - Pre-market & after-hours quotes (header + "Ext %" watchlist column)
#  - 1D chart can include extended hours (shaded), toggle "Ext (E)"
#  - VWAP / day change / RSI only use regular-session bars
#  - Header: absolute day change, ext quote line, draggable labels,
#    double-click price = copy; tray icon shows up/down colour
#  - Portfolio: day P/L in summary; alerts on day change % (Tag% >= / <=)
#  - Ctrl+F = ticker search, H = shortcut help, window position saved on move
#  - Fixes: ISE no longer killed by the single-instance guard, cached bars no
#    longer modified by live ticks, theme switch in compact mode, cache pruning
#
# v2.5 changes:
#  - Day change now uses the real previous session close (was 5-day change)
#  - Refresh requests during a running refresh are queued instead of dropped
#  - Grids keep selection/scroll on refresh; portfolio editor no longer reset
#  - Live FX for every currency in use (not just USD/CHF/GBP), warns if missing
#  - VWAP resets per trading session (5D)
#  - Ticker dropdown no longer pops open on startup / window activation
#  - Atomic JSON saves, URL-encoded symbols, locale-tolerant number input
#  - Confirmations before deleting, rate-limit (HTTP 429) backoff, log file
#  - Watchlist-only tickers refreshed less often to reduce API load
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Web

try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32WidgetHelperV26 {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);

    [DllImport("user32.dll")]
    public static extern bool ReleaseCapture();

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
"@ -ErrorAction Stop
    [void][Win32WidgetHelperV26]::SetProcessDPIAware()
} catch {
    # Already loaded in current PowerShell session
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# v3.0.1: an exception in any event handler (button click etc.) used to pop up
# the WinForms "Unbehandelte Ausnahme" dialog. Now it is logged and shown in
# the status line; the widget keeps running. Must be set before the first window.
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        try {
            $ex = $e.Exception
            $where = if ($ex -is [System.Management.Automation.IContainsErrorRecord] -and $ex.ErrorRecord.InvocationInfo) { " @ line $($ex.ErrorRecord.InvocationInfo.ScriptLineNumber)" } else { "" }
            Write-WidgetLog ("UI handler error{0}: {1}" -f $where, $ex.Message) "ERROR"
            Set-TransientStatus ("Fehler: {0} (Details im Log)" -f $ex.Message) 8
        } catch { }
    })
} catch { }

# Pure logic (indicators, parsing, market hours, holidays) lives in a separate
# file so it can be unit-tested with Pester without starting the UI (v2.9)
$script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$script:CorePath = Join-Path $script:ScriptDir "TerminalWidget.Core.ps1"
if (-not (Test-Path $script:CorePath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "TerminalWidget.Core.ps1 fehlt.`r`n`r`nDie Datei muss im selben Ordner liegen wie das Widget-Skript:`r`n$($script:ScriptDir)",
        "Terminal Widget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
try {
    . $script:CorePath
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "TerminalWidget.Core.ps1 konnte nicht geladen werden:`r`n$($_.Exception.Message)`r`n`r`nBitte die Dateien des Widgets erneut kopieren (Core und Widget müssen dieselbe Version haben).",
        "Terminal Widget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
if (-not (Get-Command Get-LayoutNames -ErrorAction SilentlyContinue)) {
    [System.Windows.Forms.MessageBox]::Show(
        "TerminalWidget.Core.ps1 ist veraltet (v4.0 erwartet).`r`n`r`nBitte Core- und Widget-Datei aus derselben Version verwenden.",
        "Terminal Widget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}

$script:AppVersion    = "4.0.1"
$script:SchemaVersion = 4
$script:AppTitle      = "Terminal Widget v$($script:AppVersion)"

# ==============================================================================
# Part 1: Storage Paths, Atomic Persistence & Config Migration
# ==============================================================================
$script:DataDir       = Join-Path $env:LOCALAPPDATA "TerminalWidget"
$script:OldDataDir    = Join-Path $env:LOCALAPPDATA "NvidiaWidgetV2"   # v2.x / v3.x
$script:ConfigPath    = Join-Path $script:DataDir "config.json"
$script:PortfolioPath = Join-Path $script:DataDir "portfolio.json"
$script:AlertsPath    = Join-Path $script:DataDir "alerts.json"
$script:CachePath     = Join-Path $script:DataDir "intraday_cache.json"
$script:QuoteCachePath = Join-Path $script:DataDir "quote_cache.json"

$script:LogPath       = Join-Path $script:DataDir "widget.log"

if (-not (Test-Path $script:DataDir)) {
    New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
}

# Lightweight rolling log (window runs hidden, so errors would otherwise be invisible)
function Write-WidgetLog {
    param([string]$Message, [string]$Level = "INFO")
    try {
        if ((Test-Path $script:LogPath) -and ((Get-Item $script:LogPath).Length -gt 1MB)) {
            Move-Item -Path $script:LogPath -Destination "$($script:LogPath).old" -Force
        }
        $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
        [System.IO.File]::AppendAllText($script:LogPath, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch { }
}

# v4.0: data folder moved. Copy (never move) the v3 data on the first start, so
# the old version keeps working on its own folder.
$script:MigratedFromOld = $false
try {
    $migAction = Get-DataMigrationAction -NewHasConfig (Test-Path $script:ConfigPath) -OldHasConfig (Test-Path (Join-Path $script:OldDataDir "config.json"))
    if ($migAction -eq "CopyFromOld") {
        foreach ($fn in (Get-DataFileNames)) {
            $src = Join-Path $script:OldDataDir $fn
            if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $script:DataDir $fn) -Force }
        }
        $script:MigratedFromOld = $true
        Write-WidgetLog "Data copied from $($script:OldDataDir) (old folder left unchanged)"
    }
} catch {
    Write-WidgetLog "Copying the v3 data failed: $($_.Exception.Message)" "ERROR"
}

# Single-Instance Mutex Guard. v4.0 has its own mutex; a running v2.x/v3.x
# (old mutex name) is detected as well, it works on the old data folder.
Write-WidgetLog ("Script start (PID {0}, PowerShell {1}, {2})" -f $PID, $PSVersionTable.PSVersion, $PSCommandPath)
$script:MutexCreated = $false
$script:AppMutex = New-Object System.Threading.Mutex($true, "Local\TerminalWidget_v4_Mutex", [ref]$script:MutexCreated)
$script:OldInstanceRunning = $false
try {
    $oldMx = $null
    if ([System.Threading.Mutex]::TryOpenExisting("Local\NvidiaFinancialWidgetV2_Mutex", [ref]$oldMx)) {
        $script:OldInstanceRunning = $true
        $oldMx.Dispose()
    }
} catch { }
if (-not $script:MutexCreated -or $script:OldInstanceRunning) {
    Write-WidgetLog ("Another instance is running (v4: {0}, old version: {1})" -f (-not $script:MutexCreated), $script:OldInstanceRunning) "WARN"
    # The window runs hidden, so show boxes on top of everything
    $mbTop = [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly
    $others = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='powershell_ise.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $PID -and ($_.CommandLine -like '*TerminalWidget.ps1*' -or $_.CommandLine -like '*nvidia_widget*') })
    # (powershell_ise.exe is NOT matched blindly any more: killing an unrelated
    #  ISE window would lose unsaved scripts)
    Write-WidgetLog ("Candidate instances: " + (($others | ForEach-Object { "$($_.Name)#$($_.ProcessId)" }) -join ", "))

    if ($others.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Das Widget ist noch aktiv, aber kein Widget-Prozess wurde gefunden.`r`n`r`nLäuft es evtl. in VS Code, der PowerShell ISE oder einem offenen PowerShell-Fenster? Dieses Fenster schließen - oder Windows ab- und wieder anmelden.",
            "Widget aktiv",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1, $mbTop
        ) | Out-Null
        exit
    }

    $who = if ($script:OldInstanceRunning) { "Die alte Version (Financial Widget v3) läuft noch." } else { "Das Terminal Widget läuft bereits (evtl. versteckt im System Tray)." }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "$who`r`n`r`n[Ja] = Laufende Instanz beenden und diese starten`r`n[Nein] = Abbrechen",
        "Widget aktiv",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button1, $mbTop
    )
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { exit }

    foreach ($o in $others) {
        try { Stop-Process -Id $o.ProcessId -Force -ErrorAction Stop; Write-WidgetLog "Stopped $($o.Name)#$($o.ProcessId)" }
        catch { Write-WidgetLog "Could not stop $($o.ProcessId): $($_.Exception.Message)" "WARN" }
    }

    # Take over the mutex once the old process is gone. A killed owner leaves
    # it "abandoned": WaitOne then throws, but we still own it.
    $acquired = [bool]$script:MutexCreated
    if (-not $acquired) {
        try { $acquired = $script:AppMutex.WaitOne(5000) }
        catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    }

    if (-not $acquired) {
        Write-WidgetLog "Could not acquire mutex after stopping old instance" "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "Die laufende Instanz konnte nicht beendet werden.`r`nBitte Windows ab- und wieder anmelden und erneut starten.",
            "Widget aktiv",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1, $mbTop
        ) | Out-Null
        exit
    }
    # A v3 instance that was just stopped may have written its data after
    # our copy: copy again (only if this start did the migration)
    if ($script:MigratedFromOld -and $script:OldInstanceRunning) {
        Start-Sleep -Milliseconds 500
        foreach ($fn in (Get-DataFileNames)) {
            $src = Join-Path $script:OldDataDir $fn
            if (Test-Path $src) { try { Copy-Item -Path $src -Destination (Join-Path $script:DataDir $fn) -Force } catch { } }
        }
        Write-WidgetLog "Data copied again after stopping the old version"
    }
}
Write-WidgetLog "Mutex acquired, building UI"

function Save-JsonState {
    param([string]$Path, $Data)
    $tmpPath = "$Path.tmp"
    try {
        # -InputObject (not the pipeline) so arrays with 0/1 items stay JSON arrays
        $json = ConvertTo-Json -InputObject $Data -Depth 8
        if ($null -eq $json) { $json = "" }
        [System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.Encoding]::UTF8)
        if ([System.IO.File]::Exists($Path)) {
            try {
                # Atomic swap on NTFS. [NullString]::Value, NOT $null: PowerShell
                # passes $null as "" to string parameters, and an empty backup
                # path throws "Der Pfad hat ein ungueltiges Format".
                [System.IO.File]::Replace($tmpPath, $Path, [NullString]::Value)
            } catch {
                # Fallback (e.g. file briefly locked by AV / indexer)
                [System.IO.File]::Copy($tmpPath, $Path, $true)
                Remove-Item -Path $tmpPath -Force -ErrorAction SilentlyContinue
            }
        } else {
            [System.IO.File]::Move($tmpPath, $Path)
        }
    } catch {
        Write-WidgetLog "Failed to save state to ${Path}: $($_.Exception.Message)" "ERROR"
    }
}

function Load-JsonState {
    param([string]$Path, $DefaultValue)
    if (Test-Path $Path) {
        try {
            $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                return ($raw | ConvertFrom-Json)
            }
        } catch {
            # Backup corrupt JSON once instead of silently losing it
            $bak = "$Path.corrupt_$(Get-Date -Format 'yyyyMMddHHmmss')"
            try { Copy-Item -Path $Path -Destination $bak -Force } catch { }
            Write-WidgetLog "Corrupt JSON in ${Path}, backed up to $bak" "WARN"
        }
    }
    return $DefaultValue
}

# Backups (v3.0): before the schema migration and on demand from the settings
$script:BackupDir = Join-Path $script:DataDir "backups"

function Backup-DataFiles {
    # Copies config/portfolio/alerts/transactions (not the intraday cache) to
    # backups\<timestamp>_<reason>\ and keeps the newest 10 backups.
    # Returns the backup folder, or "" when there was nothing to copy / it failed.
    param([string]$Reason = "manuell")
    try {
        $files = @(@("config.json", "portfolio.json", "alerts.json", "transactions.json") |
            ForEach-Object { Join-Path $script:DataDir $_ } | Where-Object { Test-Path $_ })
        if ($files.Count -eq 0) { return "" }
        $safe = ($Reason -replace '[^A-Za-z0-9_.-]', '_')
        $dest = Join-Path $script:BackupDir ("{0}_{1}" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $safe)
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        foreach ($f in $files) { Copy-Item -Path $f -Destination $dest -Force }
        $all = @(Get-ChildItem -Path $script:BackupDir -Directory | Sort-Object Name -Descending)
        if ($all.Count -gt 10) {
            $all | Select-Object -Skip 10 | ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Write-WidgetLog "Backup created: $dest"
        return $dest
    } catch {
        Write-WidgetLog "Backup failed: $($_.Exception.Message)" "ERROR"
        return ""
    }
}

$defaultConfig = [PSCustomObject]@{
    SchemaVersion         = $script:SchemaVersion
    CurrencyNoticeKey     = ""
    ActiveTicker          = "NVDA"
    ActiveTab             = "Chart"
    Currency              = "EUR"
    ChartType             = "Line"
    ShowVolume            = $true
    CompactMode           = $false
    TopMost               = $true
    ShowRsi               = $true
    ShowSma               = $true
    ShowVwap              = $true
    ShowBollinger         = $false
    ShowExtended          = $true
    NotifyMarketOpen      = $true
    SmaFastPeriod         = 20
    SmaSlowPeriod         = 50
    RsiPeriod             = 14
    RsiOverbought         = 70
    RsiOversold           = 30
    Theme                 = "Dark"
    AccentColor           = "Sky"
    ShowTrayNotifications = $true
    HttpTimeoutSeconds    = 8
    RefreshSeconds        = 15
    SlowRefreshSeconds    = 60
    Timeframe             = "1d"
    PortfolioSort         = "ValueDesc"
    WindowX               = 100
    WindowY               = 100
    WindowW               = 0
    WindowH               = 0
    WindowMaximized       = $false
    CompactTape           = $true
    ShowLevels            = $true
    CompareTicker         = ""
    Autostart             = $false
    # v4.0
    Layout                = "Standard"        # Ticker / Compact / Standard / Terminal
    LastFullLayout        = "Standard"        # where C / Expand returns to
    TerminalShowWatch     = $true
    TerminalShowPortfolio = $true
    TerminalChartPct      = 55
    TerminalBottom        = "Watchlist"       # bottom panel when only one fits
    TerminalW             = 0                 # remembered client size of the Terminal layout
    TerminalH             = 0
    Opacity               = 100
    TooltipMode           = "Short"           # Off / Short / Long
    TooltipDelayMs        = 400
    ReportBase            = "EUR"
    Watchlist            = @("NVDA", "ABBN.SW", "MSFT", "AAPL", "AMD", "AMZN", "AVGO")
}

$script:Config = Load-JsonState -Path $script:ConfigPath -DefaultValue $defaultConfig

# Schema migration (v3.0 / v4.0): back up the existing data files once, BEFORE
# anything is rewritten. v4 only adds config keys; the files stay readable by
# v3.0 (in v4.0 they live in the new data folder anyway).
$cfgSchema = 0
if ($null -ne $script:Config.PSObject.Properties["SchemaVersion"]) { $cfgSchema = [int]$script:Config.SchemaVersion }
if ((Test-Path $script:ConfigPath) -and $cfgSchema -lt $script:SchemaVersion) {
    $bk = Backup-DataFiles -Reason ("vor_v{0}_migration" -f $script:SchemaVersion)
    Write-WidgetLog ("Migrating data from schema {0} to {1} (backup: {2})" -f $cfgSchema, $script:SchemaVersion, $(if ($bk) { $bk } else { "none" }))
}

# Ensure all default properties exist on loaded config (schema migration)
foreach ($prop in $defaultConfig.PSObject.Properties) {
    if ($null -eq $script:Config.PSObject.Properties[$prop.Name]) {
        $script:Config | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    }
}
$script:Config.SchemaVersion = $script:SchemaVersion

# Sanitize Watchlist & Settings
if ($null -eq $script:Config.Watchlist -or @($script:Config.Watchlist).Count -eq 0) {
    $script:Config.Watchlist = @("NVDA", "ABBN.SW", "MSFT", "AAPL", "AMD", "AMZN")
} else {
    $cleanWl = New-Object System.Collections.Generic.List[string]
    foreach ($w in $script:Config.Watchlist) {
        if (-not [string]::IsNullOrWhiteSpace($w)) {
            $u = $w.Trim().ToUpper()
            if (-not $cleanWl.Contains($u)) { [void]$cleanWl.Add($u) }
        }
    }
    $script:Config.Watchlist = if ($cleanWl.Count -gt 0) { $cleanWl.ToArray() } else { @("NVDA") }
}

if ([string]::IsNullOrWhiteSpace($script:Config.ActiveTicker)) { $script:Config.ActiveTicker = $script:Config.Watchlist[0] }
if ([string]$script:Config.Currency -notin @(Get-DisplayCurrencies)) { $script:Config.Currency = "EUR" }
if ($script:Config.ChartType -notin @("Line", "Candle")) { $script:Config.ChartType = "Line" }
if ($script:Config.ActiveTab -notin @("Chart", "Portfolio", "Watchlist")) { $script:Config.ActiveTab = "Chart" }
if ($script:Config.Theme -notin @(Get-ThemeNames)) { $script:Config.Theme = "Dark" }
# v4.0 layouts: a v3 config only knows CompactMode
if ($script:Config.PSObject.Properties["Layout"] -and $cfgSchema -lt 4 -and [bool]$script:Config.CompactMode) { $script:Config.Layout = "Compact" }
if ([string]$script:Config.Layout -notin @(Get-LayoutNames)) { $script:Config.Layout = "Standard" }
if ([string]$script:Config.LastFullLayout -notin @("Standard", "Terminal")) { $script:Config.LastFullLayout = "Standard" }
$script:Config.CompactMode = Test-CompactLayout $script:Config.Layout
if ([string]$script:Config.TooltipMode -notin @((Get-TooltipModes).Keys)) { $script:Config.TooltipMode = "Short" }
$script:Config.TooltipDelayMs   = [math]::Max(0, [math]::Min(5000, [int]$script:Config.TooltipDelayMs))
$script:Config.Opacity          = [math]::Max(30, [math]::Min(100, [int]$script:Config.Opacity))
$script:Config.TerminalChartPct = [math]::Max(25, [math]::Min(80, [int]$script:Config.TerminalChartPct))
if ([string]$script:Config.TerminalBottom -notin @("Watchlist", "Portfolio")) { $script:Config.TerminalBottom = "Watchlist" }
if (-not (Get-NormalizedCurrencyCode ([string]$script:Config.ReportBase))) { $script:Config.ReportBase = "EUR" }
if ($script:Config.AccentColor -notin @("Sky", "Amber", "Violet")) { $script:Config.AccentColor = "Sky" }
if ([int]$script:Config.RefreshSeconds -lt 5) { $script:Config.RefreshSeconds = 15 }
if ([int]$script:Config.SlowRefreshSeconds -lt [int]$script:Config.RefreshSeconds) { $script:Config.SlowRefreshSeconds = [math]::Max(60, [int]$script:Config.RefreshSeconds) }
if ([int]$script:Config.SmaFastPeriod -lt 2) { $script:Config.SmaFastPeriod = 20 }
if ([int]$script:Config.SmaSlowPeriod -lt 5) { $script:Config.SmaSlowPeriod = 50 }
if ([int]$script:Config.RsiPeriod -lt 2) { $script:Config.RsiPeriod = 14 }

# Portfolio Holdings
$script:Portfolio = @{}
$rawPortfolio = Load-JsonState -Path $script:PortfolioPath -DefaultValue $null
if ($null -ne $rawPortfolio) {
    foreach ($prop in $rawPortfolio.PSObject.Properties) {
        if ($null -ne $prop.Value) {
            # v3.0: keep any ISO currency (v2.9 forced everything but EUR/USD/CHF to EUR)
            $pCurr = Get-NormalizedCurrencyCode ([string]$prop.Value.Currency)
            if (-not $pCurr) { $pCurr = "EUR" }
            $script:Portfolio[$prop.Name.ToUpper()] = [PSCustomObject]@{
                Ticker    = $prop.Name.ToUpper()
                Shares    = [double]$prop.Value.Shares
                AvgPrice  = [double]$prop.Value.AvgPrice
                Currency  = $pCurr
                BuyAmount = [double]$prop.Value.BuyAmount
                TargetAvg = [double]$prop.Value.TargetAvg
            }
        }
    }
}

# Global Alerts
$script:Alerts = New-Object System.Collections.Generic.List[PSObject]
$rawAlerts = Load-JsonState -Path $script:AlertsPath -DefaultValue @()
foreach ($a in $rawAlerts) {
    if ($null -ne $a -and $a.Ticker) {
        $script:Alerts.Add([PSCustomObject]@{
            Id          = [string]$a.Id
            Ticker      = [string]$a.Ticker.ToUpper()
            Condition   = [string]$a.Condition
            TargetPrice = [double]$a.TargetPrice
            Currency    = if ($a.Currency) { [string]$a.Currency } else { "EUR" }
            Triggered   = [bool]$a.Triggered
            # v2.9: note, automatic re-arm (minutes, 0 = off) and trigger time
            Note        = if ($a.Note) { [string]$a.Note } else { "" }
            RearmMin    = [int]$a.RearmMin
            TriggeredAt = if ($a.TriggeredAt) { [string]$a.TriggeredAt } else { "" }
        })
    }
}

# Transaction history (v2.9): buys / sells / dividends with realized P/L
$script:TransactionsPath = Join-Path $script:DataDir "transactions.json"
$script:Transactions = New-Object System.Collections.Generic.List[PSObject]
foreach ($t in @(Load-JsonState -Path $script:TransactionsPath -DefaultValue @())) {
    if ($null -ne $t -and $t.Ticker -and $t.Type) {
        $script:Transactions.Add([PSCustomObject]@{
            Id       = if ($t.Id) { [string]$t.Id } else { [Guid]::NewGuid().ToString("N") }
            Date     = [string]$t.Date
            Ticker   = ([string]$t.Ticker).ToUpper()
            Type     = [string]$t.Type
            Shares   = [double]$t.Shares
            Price    = [double]$t.Price
            Fee      = [double]$t.Fee
            Currency = if ($t.Currency) { [string]$t.Currency } else { "EUR" }
            Realized = [double]$t.Realized
            Note     = [string]$t.Note
        })
    }
}

# Persistent Intraday Cache
$script:IntradayCache = @{}
$rawCache = Load-JsonState -Path $script:CachePath -DefaultValue $null
if ($null -ne $rawCache) {
    foreach ($prop in $rawCache.PSObject.Properties) {
        $pts = New-Object System.Collections.Generic.List[PSObject]
        foreach ($pt in $prop.Value) {
            if ($null -ne $pt -and $pt.Close -gt 0) {
                $pts.Add([PSCustomObject]@{
                    Ts     = [long]$pt.Ts
                    Open   = if ($pt.Open) { [double]$pt.Open } else { [double]$pt.Close }
                    High   = [double]$pt.High
                    Low    = [double]$pt.Low
                    Close  = [double]$pt.Close
                    Volume = if ($pt.Volume) { [long]$pt.Volume } else { 0 }
                    Sess   = if ($pt.Sess) { [string]$pt.Sess } else { "R" }
                    Ext    = [bool]$pt.Ext
                })
            }
        }
        $script:IntradayCache[$prop.Name.ToUpper()] = $pts
    }
}

function Prune-IntradayCache {
    # Drop bars older than 5 days for EVERY ticker (Merge only prunes the active one)
    $cutoffMs = [DateTimeOffset]::UtcNow.AddDays(-5).ToUnixTimeMilliseconds()
    foreach ($key in @($script:IntradayCache.Keys)) {
        $kept = New-Object System.Collections.Generic.List[PSObject]
        foreach ($pt in $script:IntradayCache[$key]) {
            if ($null -ne $pt -and [long]$pt.Ts -ge $cutoffMs) { $kept.Add($pt) }
        }
        if ($kept.Count -eq 0) { $script:IntradayCache.Remove($key) } else { $script:IntradayCache[$key] = $kept }
    }
}
Prune-IntradayCache

function Merge-IntradayPoints {
    param([string]$Ticker, [array]$NewPoints)
    # SortedDictionary keeps the minute buckets ordered: no Sort-Object over
    # thousands of PSObjects on every poll any more
    $bucketMap = New-Object 'System.Collections.Generic.SortedDictionary[long,object]'
    $cutoffMs = [DateTimeOffset]::UtcNow.AddDays(-5).ToUnixTimeMilliseconds()

    if ($script:IntradayCache.ContainsKey($Ticker)) {
        foreach ($old in $script:IntradayCache[$Ticker]) {
            if ($null -ne $old -and [long]$old.Ts -ge $cutoffMs -and $old.Close -gt 0) {
                $bucketMap[[long][math]::Floor([long]$old.Ts / 60000.0)] = $old
            }
        }
    }
    foreach ($np in $NewPoints) {
        if ($null -ne $np -and [long]$np.Ts -ge $cutoffMs -and $np.Close -gt 0) {
            $bucketMap[[long][math]::Floor([long]$np.Ts / 60000.0)] = $np
        }
    }

    $list = New-Object System.Collections.Generic.List[PSObject]
    foreach ($item in $bucketMap.Values) { $list.Add($item) }
    $script:IntradayCache[$Ticker] = $list
    return $list
}

# ==============================================================================
# Part 2: Parallel HttpClient, Multi-FX & Technical Indicators
# ==============================================================================
$script:HttpHandler = New-Object System.Net.Http.HttpClientHandler
$script:HttpHandler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
$script:HttpClient = New-Object System.Net.Http.HttpClient($script:HttpHandler)
$script:HttpClient.Timeout = [TimeSpan]::FromSeconds([math]::Max(3, [int]$script:Config.HttpTimeoutSeconds))
$script:HttpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

# Fallback rates (EUR -> X). Every currency actually in use is refreshed live;
# currencies listed in FxLive have a confirmed live rate.
$script:FxFromEur = @{
    "EUR" = 1.0000
    "USD" = 1.0950
    "CHF" = 0.9400
    "GBP" = 0.8350
    "CAD" = 1.5200
    "JPY" = 165.00
}
$script:FxLive    = New-Object System.Collections.Generic.HashSet[string]
[void]$script:FxLive.Add("EUR")
$script:FxMissing = New-Object System.Collections.Generic.HashSet[string]

# Rate limiting / slow refresh bookkeeping
$script:BackoffUntil      = [DateTime]::MinValue
$script:BackoffLevel      = 0
$script:LastRateLimited   = $false
$script:LastSlowRefresh   = [DateTime]::MinValue
$script:RefreshPending    = $false
$script:RefreshPendingForce = $false
$script:RefreshStarted    = [DateTime]::MinValue
$script:TransientStatus   = ""
$script:TransientUntil    = [DateTime]::MinValue
$script:ActiveGmtOffset   = 0
$script:LastCacheSave     = [DateTime]::MinValue
$script:ActiveSeriesKey   = ""
$script:LastDataTime      = $null
$script:FsForm            = $null
$script:FsCanvas          = $null

function Get-ChartUrl {
    param([string]$Symbol, [string]$Interval, [string]$Range, [switch]$PrePost)
    # Encode ^ & / etc. but keep "=" (legal in a path, used by FX symbols like EURUSD=X)
    $enc = [Uri]::EscapeDataString($Symbol).Replace("%3D", "=")
    $url = "https://query1.finance.yahoo.com/v8/finance/chart/${enc}?interval=$Interval&range=$Range"
    if ($PrePost) { $url += "&includePrePost=true" }
    return $url
}

# (market hours, time zones and holiday calendars: see NvidiaWidget.Core.ps1)

$script:IsRefreshing      = $false
$script:IsClosing         = $false
$script:LastFetchWarning  = ""
$script:LastFetchOffline  = $false
$script:QuoteStore        = @{}
$script:SparklineStore    = @{}
$script:ActiveSeries      = @()
$script:ActiveRsiSeries   = @()
$script:ActiveSma20       = @()
$script:ActiveSma50       = @()
$script:ActiveVwap        = @()
$script:ActiveBbUpper     = @()
$script:ActiveBbLower     = @()
$script:ActivePrevClose   = 0.0
$script:ActiveNativeCurr  = "USD"
$script:ActiveLongName    = ""
$script:ActiveLoadError   = ""

# ------------------------------------------------------------------------------
# Quote cache (v4.0): the last known quotes, sparklines and FX rates, so the
# window does not start empty. Cached quotes carry FromCache = $true (shown
# grey) until the first refresh replaces them. Cached FX rates are NOT marked
# live, so the status line still says when a rate is only a fallback.
# ------------------------------------------------------------------------------
$script:LastQuoteCacheSave = [DateTime]::MinValue

function Save-QuoteCache {
    try {
        $entries = New-Object System.Collections.Generic.List[PSObject]
        foreach ($k in @($script:QuoteStore.Keys)) {
            $q = $script:QuoteStore[$k]
            if ($null -eq $q -or [bool]$q.FromCache) { continue }
            $e = ConvertTo-QuoteCacheEntry -Quote $q -Spark $script:SparklineStore[$k]
            if ($null -ne $e) { $entries.Add($e) }
        }
        if ($entries.Count -eq 0) { return }
        $fx = [ordered]@{}
        foreach ($c in @($script:FxLive)) { if ($script:FxFromEur.ContainsKey($c)) { $fx[$c] = [double]$script:FxFromEur[$c] } }
        Save-JsonState -Path $script:QuoteCachePath -Data ([PSCustomObject]@{ SavedAt = (Get-Date).ToString("o"); Fx = $fx; Quotes = $entries.ToArray() })
        $script:LastQuoteCacheSave = Get-Date
    } catch {
        Write-WidgetLog "Saving the quote cache failed: $($_.Exception.Message)" "WARN"
    }
}

function Load-QuoteCache {
    $raw = Load-JsonState -Path $script:QuoteCachePath -DefaultValue $null
    if ($null -eq $raw) { return }
    $n = 0
    try {
        if ($null -ne $raw.Fx) {
            foreach ($prop in $raw.Fx.PSObject.Properties) {
                $c = Get-NormalizedCurrencyCode $prop.Name
                $r = ConvertFrom-JsonNumber $prop.Value 0.0
                if ($c -and $c -ne "EUR" -and $r -gt 0) { $script:FxFromEur[$c] = $r }
            }
        }
        foreach ($e in @($raw.Quotes)) {
            $q = ConvertFrom-QuoteCacheEntry -Entry $e
            if ($null -eq $q) { continue }
            $script:QuoteStore[$q.Ticker] = $q
            $sp = @(@($e.Spark) | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
            if ($sp.Count -ge 2) { $script:SparklineStore[$q.Ticker] = [double[]]$sp }
            $n++
        }
        Write-WidgetLog "Quote cache loaded: $n quotes (from $($raw.SavedAt))"
    } catch {
        Write-WidgetLog "Loading the quote cache failed: $($_.Exception.Message)" "WARN"
    }
}
Load-QuoteCache

function Invoke-ParallelFetch {
    # Synchronous fetch, only for the few interactive lookups that need an
    # answer right away (symbol resolve in dialogs / on Save). v3.0: no more
    # DoEvents while waiting - it let the user click into half-finished
    # handlers (re-entrancy). The wait is bounded by a cancellation timeout.
    param([string[]]$Urls, [int]$TimeoutSec = 6)
    $results = @{}
    if ($script:IsClosing -or -not $Urls -or $Urls.Count -eq 0) { return $results }

    $batch = @($Urls | Where-Object { $_ } | Select-Object -Unique)
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter([TimeSpan]::FromSeconds([math]::Max(2, $TimeoutSec)))
    $oldCursor = [System.Windows.Forms.Cursor]::Current
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $tasks = @{}
        foreach ($u in $batch) {
            try { $tasks[$u] = $script:HttpClient.GetAsync($u, $cts.Token) }
            catch { $results[$u] = $null }
        }

        $allTasks = [System.Threading.Tasks.Task[]]@($tasks.Values)
        if ($allTasks.Count -gt 0) {
            try { [void][System.Threading.Tasks.Task]::WaitAll($allTasks) }
            catch {
                # Individual HTTP task failures / cancellations handled below
            }
        }

        foreach ($u in $batch) {
            $t = $tasks[$u]
            $results[$u] = $null
            if ($null -ne $t -and $t.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $resp = $t.Result
                try {
                    $code = [int]$resp.StatusCode
                    if ($resp.IsSuccessStatusCode) {
                        # Content is already buffered (ResponseContentRead), so .Result does not block
                        $body = $resp.Content.ReadAsStringAsync().Result
                        $results[$u] = ($body | ConvertFrom-Json)
                    } elseif ($code -eq 429) {
                        $script:LastRateLimited = $true
                        Write-WidgetLog "HTTP 429 (rate limited): $u" "WARN"
                    } elseif ($code -ne 404) {
                        Write-WidgetLog "HTTP ${code}: $u" "WARN"
                    }
                } catch {
                    Write-WidgetLog "Parse error for ${u}: $($_.Exception.Message)" "WARN"
                } finally {
                    $resp.Dispose()
                }
            } elseif ($null -ne $t -and $t.IsFaulted) {
                $inner = if ($t.Exception -and $t.Exception.InnerException) { $t.Exception.InnerException.Message } else { "unknown" }
                Write-WidgetLog "Request failed: $u ($inner)" "WARN"
            } elseif ($null -ne $t -and $t.IsCanceled) {
                Write-WidgetLog "Request timed out: $u" "WARN"
            }
        }
    } finally {
        [System.Windows.Forms.Cursor]::Current = $oldCursor
        $cts.Dispose()
    }
    return $results
}

# ------------------------------------------------------------------------------
# Background fetch worker (v2.8)
# HTTP requests AND JSON parsing run in a RunspacePool; the UI thread only gets
# the parsed objects via a completion callback. No DoEvents, no re-entrancy and
# no frozen window while Yahoo is slow. Invoke-ParallelFetch above is still used
# for the few synchronous lookups (symbol resolve on Enter / Save).
# ------------------------------------------------------------------------------
$script:FetchWorkerScript = {
    param($Client, [string[]]$Urls, [int]$MaxConc, [hashtable]$Fallbacks, [string[]]$KnownFx, [bool]$AutoFx, $Box, $Shared)

    $results = @{}
    $logs    = New-Object System.Collections.Generic.List[string]
    # Retry = URLs that failed in a way another Yahoo host might not (timeout,
    # connection error, 5xx, 401/403). 404 / 429 are not retried.
    $state   = @{ RateLimited = $false; Retry = (New-Object System.Collections.Generic.HashSet[string]) }
    if ($MaxConc -lt 1) { $MaxConc = 4 }

    function Fetch-UrlBatch {
        param([string[]]$List)
        $uniq = @($List | Where-Object { $_ -and -not $results.ContainsKey($_) } | Select-Object -Unique)
        for ($i = 0; $i -lt $uniq.Count; $i += $MaxConc) {
            if ($Shared.Cancel) { return }
            $end = [math]::Min($i + $MaxConc - 1, $uniq.Count - 1)
            $batch = @($uniq[$i..$end])
            $tasks = @{}
            foreach ($u in $batch) {
                try { $tasks[$u] = $Client.GetAsync($u) }
                catch { $logs.Add("WARN|Request start failed: $u ($($_.Exception.Message))") }
            }
            $arr = [System.Threading.Tasks.Task[]]@($tasks.Values)
            if ($arr.Count -gt 0) {
                try {
                    while (-not [System.Threading.Tasks.Task]::WaitAll($arr, 100)) {
                        if ($Shared.Cancel) { return }
                    }
                } catch {
                    # individual failures are handled per task below
                }
            }
            foreach ($u in $batch) {
                $results[$u] = $null
                $t = $tasks[$u]
                if ($null -eq $t) { continue }
                if ($t.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                    $resp = $t.Result
                    try {
                        $code = [int]$resp.StatusCode
                        if ($resp.IsSuccessStatusCode) {
                            $body = $resp.Content.ReadAsStringAsync().Result
                            $results[$u] = ($body | ConvertFrom-Json)
                        } elseif ($code -eq 429) {
                            $state.RateLimited = $true
                            $logs.Add("WARN|HTTP 429 (rate limited): $u")
                        } elseif ($code -ne 404) {
                            $logs.Add("WARN|HTTP ${code}: $u")
                            [void]$state.Retry.Add($u)
                        }
                    } catch {
                        $logs.Add("WARN|Parse error for ${u}: $($_.Exception.Message)")
                    } finally {
                        $resp.Dispose()
                    }
                } elseif ($t.IsFaulted) {
                    $inner = if ($t.Exception -and $t.Exception.InnerException) { $t.Exception.InnerException.Message } else { "unknown" }
                    $logs.Add("WARN|Request failed: $u ($inner)")
                    [void]$state.Retry.Add($u)
                } elseif ($t.IsCanceled) {
                    $logs.Add("WARN|Request timed out / cancelled: $u")
                    [void]$state.Retry.Add($u)
                }
            }
        }
    }

    # Yahoo host fallback (v2.9): query1 <-> query2. Results are always stored
    # under the ORIGINAL url; the host that worked last time is tried first.
    function Fetch-Mapped {
        param([string[]]$Orig, [string]$HostName)
        $map = @{}
        foreach ($o in $Orig) { if ($o) { $map[($o -replace '://query[12]\.', "://$HostName.")] = $o } }
        Fetch-UrlBatch -List @($map.Keys)
        foreach ($k in @($map.Keys)) {
            $o = $map[$k]
            if ($k -eq $o) { continue }
            if ($null -ne $results[$k] -or -not $results.ContainsKey($o)) { $results[$o] = $results[$k] }
            if ($state.Retry.Contains($k)) { [void]$state.Retry.Add($o) }
            [void]$results.Remove($k)
        }
    }
    $primaryHost = if ($Shared.PreferQ2) { "query2" } else { "query1" }
    $altHost     = if ($Shared.PreferQ2) { "query1" } else { "query2" }

    Fetch-Mapped -Orig $Urls -HostName $primaryHost
    $retry = @($Urls | Where-Object { $_ -and $null -eq $results[$_] -and $state.Retry.Contains($_) } | Select-Object -Unique)
    if ($retry.Count -gt 0 -and -not $Shared.Cancel) {
        foreach ($u in $retry) { [void]$state.Retry.Remove($u) }
        Fetch-Mapped -Orig $retry -HostName $altHost
        $recovered = @($retry | Where-Object { $null -ne $results[$_] }).Count
        if ($recovered -gt 0) {
            $Shared.PreferQ2 = ($altHost -eq "query2")
            $logs.Add("INFO|Yahoo host fallback: $recovered/$($retry.Count) via $altHost, next requests start with $altHost")
        }
    }

    # Fallback URLs (e.g. 1D chart of an EU stock before the open: <2 bars -> 5m/5d)
    if ($null -ne $Fallbacks -and $Fallbacks.Count -gt 0 -and -not $Shared.Cancel) {
        $fb = New-Object System.Collections.Generic.List[string]
        foreach ($prim in @($Fallbacks.Keys)) {
            $valid = 0
            try {
                foreach ($v in $results[$prim].chart.result[0].indicators.quote[0].close) {
                    if ($null -ne $v -and [double]$v -gt 0) { $valid++ }
                }
            } catch { }
            if ($valid -lt 2) { $fb.Add([string]$Fallbacks[$prim]) }
        }
        if ($fb.Count -gt 0) { Fetch-Mapped -Orig $fb.ToArray() -HostName $primaryHost }
    }

    # Currencies seen for the first time: fetch their EUR rate in the same job
    $extraFx = @{}
    if ($AutoFx -and -not $Shared.Cancel) {
        $known = New-Object System.Collections.Generic.HashSet[string]
        [void]$known.Add("EUR")
        foreach ($k in $KnownFx) { if ($k) { [void]$known.Add([string]$k) } }
        foreach ($u in @($results.Keys)) {
            $raw = $null
            try { $raw = [string]$results[$u].chart.result[0].meta.currency } catch { }
            if ([string]::IsNullOrEmpty($raw)) { continue }
            $c = if ($raw -ceq "GBp" -or $raw -ceq "GBX") { "GBP" } elseif ($raw -ceq "ZAc") { "ZAR" } elseif ($raw -ceq "ILA") { "ILS" } else { $raw.ToUpper() }
            if ($c -notmatch '^[A-Z]{3}$' -or $known.Contains($c)) { continue }
            [void]$known.Add($c)
            # identical to Get-ChartUrl -Symbol "EUR$c=X" -Interval 1d -Range 1d
            $extraFx[$c] = "https://query1.finance.yahoo.com/v8/finance/chart/EUR${c}=X?interval=1d&range=1d"
        }
        if ($extraFx.Count -gt 0) { Fetch-Mapped -Orig @($extraFx.Values) -HostName $primaryHost }
    }

    $Box.Results     = $results
    $Box.Logs        = $logs.ToArray()
    $Box.RateLimited = [bool]$state.RateLimited
    $Box.ExtraFx     = $extraFx
}

$script:WorkerShared = [hashtable]::Synchronized(@{ Cancel = $false; PreferQ2 = $false })
$script:FetchJobs    = New-Object System.Collections.Generic.List[PSObject]
$script:WorkerPool   = $null
try {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $script:WorkerPool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 3, $iss, $Host)
    $script:WorkerPool.Open()
    Write-WidgetLog "Background fetch worker ready"
} catch {
    Write-WidgetLog "RunspacePool unavailable, using synchronous fetch: $($_.Exception.Message)" "WARN"
    $script:WorkerPool = $null
}

$script:JobTimer = New-Object System.Windows.Forms.Timer
$script:JobTimer.Interval = 40

function Complete-FetchJob {
    param($Job)
    $box = $Job.Box
    if ($null -ne $box.Logs) {
        foreach ($l in $box.Logs) {
            $parts = [string]$l -split '\|', 2
            if ($parts.Count -eq 2) { Write-WidgetLog $parts[1] $parts[0] } else { Write-WidgetLog ([string]$l) "WARN" }
        }
    }
    if ($null -eq $box.Results) { $box.Results = @{} }
    if ($null -eq $box.ExtraFx) { $box.ExtraFx = @{} }
    if ($script:IsClosing -or $null -eq $Job.OnComplete) { return }
    try {
        & $Job.OnComplete $box $Job.Context
    } catch {
        Write-WidgetLog "Fetch callback failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
    }
}

function Pump-FetchJobs {
    if ($script:FetchJobs.Count -eq 0) { $script:JobTimer.Stop(); return }
    $done = @($script:FetchJobs | Where-Object { $_.Async.IsCompleted })
    foreach ($job in $done) {
        [void]$script:FetchJobs.Remove($job)
        try { [void]$job.PS.EndInvoke($job.Async) }
        catch { Write-WidgetLog "Fetch worker failed: $($_.Exception.Message)" "ERROR" }
        try { $job.PS.Dispose() } catch { }
        Complete-FetchJob -Job $job
    }
    if ($script:FetchJobs.Count -eq 0) { $script:JobTimer.Stop() }
}
$script:JobTimer.Add_Tick({ Pump-FetchJobs })

function Start-FetchJob {
    # Fire-and-forget fetch; $OnComplete runs later ON THE UI THREAD with
    # ($Box, $Context). $Box.Results maps url -> parsed JSON (or $null).
    param(
        [string[]]$Urls,
        [scriptblock]$OnComplete,
        $Context = $null,
        [hashtable]$Fallbacks = @{},
        [string[]]$KnownFx = @(),
        [switch]$AutoFx,
        [int]$MaxConcurrency = 4
    )
    if ($script:IsClosing) { return }
    $box = [hashtable]::Synchronized(@{ Results = $null; Logs = $null; RateLimited = $false; ExtraFx = $null })
    $job = [PSCustomObject]@{ PS = $null; Async = $null; Box = $box; Context = $Context; OnComplete = $OnComplete }

    if ($null -eq $script:WorkerPool) {
        # Fallback: same worker code, synchronously on the UI thread
        try { & $script:FetchWorkerScript $script:HttpClient $Urls $MaxConcurrency $Fallbacks $KnownFx ([bool]$AutoFx) $box $script:WorkerShared }
        catch { Write-WidgetLog "Synchronous fetch failed: $($_.Exception.Message)" "ERROR" }
        Complete-FetchJob -Job $job
        return
    }

    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $script:WorkerPool
    [void]$ps.AddScript($script:FetchWorkerScript.ToString())
    [void]$ps.AddArgument($script:HttpClient)
    [void]$ps.AddArgument([string[]]$Urls)
    [void]$ps.AddArgument($MaxConcurrency)
    [void]$ps.AddArgument($Fallbacks)
    [void]$ps.AddArgument([string[]]$KnownFx)
    [void]$ps.AddArgument([bool]$AutoFx)
    [void]$ps.AddArgument($box)
    [void]$ps.AddArgument($script:WorkerShared)
    $job.PS = $ps
    $job.Async = $ps.BeginInvoke()
    $script:FetchJobs.Add($job)
    if (-not $script:JobTimer.Enabled) { $script:JobTimer.Start() }
}

function Stop-FetchWorker {
    # Called on shutdown: make running jobs bail out fast, then release the pool
    $script:WorkerShared.Cancel = $true
    try { $script:JobTimer.Stop() } catch { }
    try { $script:HttpClient.CancelPendingRequests() } catch { }
    foreach ($job in @($script:FetchJobs)) {
        try { [void]$job.Async.AsyncWaitHandle.WaitOne(1500) } catch { }
        try { $job.PS.Dispose() } catch { }
    }
    $script:FetchJobs.Clear()
    if ($null -ne $script:WorkerPool) { try { $script:WorkerPool.Dispose() } catch { } }
}


function Convert-CurrencyValue {
    param([double]$Amount, [string]$FromCurrency, [string]$ToCurrency)
    if ($Amount -eq 0) { return 0.0 }
    $norm = Normalize-CurrencyAndPrice -Price $Amount -RawCurrency $FromCurrency
    $val  = $norm.Price
    $from = $norm.Currency
    $to   = if ($ToCurrency) { $ToCurrency.ToUpper() } else { "EUR" }

    if ($from -eq $to) { return $val }

    foreach ($cc in @($from, $to)) {
        if (-not $script:FxLive.Contains($cc)) { [void]$script:FxMissing.Add($cc) }
    }
    $fromRate = if ($script:FxFromEur.ContainsKey($from) -and $script:FxFromEur[$from] -gt 0) { $script:FxFromEur[$from] } else { 1.0 }
    $toRate   = if ($script:FxFromEur.ContainsKey($to)   -and $script:FxFromEur[$to]   -gt 0) { $script:FxFromEur[$to] }   else { 1.0 }

    return (($val / $fromRate) * $toRate)
}







function Get-SearchUrl {
    param([string]$Query)
    $encoded = [System.Web.HttpUtility]::UrlEncode($Query.Trim())
    return "https://query1.finance.yahoo.com/v1/finance/search?q=$encoded&quotesCount=12&newsCount=0"
}

# (ConvertFrom-YahooSearch, Get-ChartResult and Select-ResolvedSymbol live in
#  NvidiaWidget.Core.ps1 since v3.0)

# Raw input -> resolved symbol, for this session (v3.0). "NVIDIA" is looked up
# once; known symbols (quotes, watchlist, portfolio) need no network at all.
$script:ResolveCache = @{}
$script:ResolveSeq   = 0

function Get-KnownSymbol {
    param([string]$Raw)
    $u = ([string]$Raw).Trim().ToUpper()
    if (-not $u) { return "" }
    if ($script:ResolveCache.ContainsKey($u)) { return [string]$script:ResolveCache[$u] }
    if ($script:QuoteStore.ContainsKey($u) -or $script:Portfolio.ContainsKey($u) -or (@($script:Config.Watchlist) -contains $u)) { return $u }
    return ""
}

function Get-ResolveUrls {
    param([string]$Clean)
    return @{ Probe = (Get-ChartUrl -Symbol $Clean -Interval "1d" -Range "1d"); Search = (Get-SearchUrl -Query $Clean) }
}

function Complete-SymbolResolve {
    # Shared by the synchronous and the background path; caches only answers
    # that came from Yahoo (offline the raw input is used but not remembered)
    param([string]$Clean, $ProbeJson, $SearchJson)
    $hits = @(ConvertFrom-YahooSearch -Json $SearchJson)
    $sym = Select-ResolvedSymbol -Raw $Clean -ProbeJson $ProbeJson -SearchItems $hits
    if ($sym -and ($null -ne $ProbeJson -or $null -ne $SearchJson)) { $script:ResolveCache[$Clean] = $sym }
    return $sym
}

function Resolve-BestSymbol {
    # Synchronous (bounded wait, no DoEvents). Used by dialogs and Save
    # buttons; the ticker search box resolves in the background instead.
    param([string]$RawInput)
    $clean = ([string]$RawInput).Trim().ToUpper()
    if ([string]::IsNullOrWhiteSpace($clean)) { return "" }
    $known = Get-KnownSymbol -Raw $clean
    if ($known) { return $known }

    $u = Get-ResolveUrls -Clean $clean
    $res = Invoke-ParallelFetch -Urls @($u.Probe, $u.Search)
    return (Complete-SymbolResolve -Clean $clean -ProbeJson $res[$u.Probe] -SearchJson $res[$u.Search])
}

function Confirm-Action {
    param([string]$Text, [string]$Title = "Bestätigen")
    # Pass the form as owner so the box never hides behind the TopMost widget
    $owner = if ($null -ne $form -and -not $form.IsDisposed) { $form } else { $null }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        $owner, $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    return ($ans -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Set-TransientStatus {
    param([string]$Text, [int]$Seconds = 5)
    $script:TransientStatus = $Text
    $script:TransientUntil  = (Get-Date).AddSeconds($Seconds)
    if ($null -ne $lblStatus) {
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(245, 158, 11)
        $lblStatus.Text = $Text
    }
}

function Add-SymbolToWatchlist {
    param([string]$RawSymbol, [switch]$SwitchToChart)
    $resolved = Resolve-BestSymbol -RawInput $RawSymbol
    if ([string]::IsNullOrWhiteSpace($resolved)) { return $false }

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($w in $script:Config.Watchlist) {
        if (-not [string]::IsNullOrWhiteSpace($w)) {
            $u = $w.Trim().ToUpper()
            if (-not $list.Contains($u)) { [void]$list.Add($u) }
        }
    }
    if (-not $list.Contains($resolved)) {
        [void]$list.Add($resolved)
        $script:Config.Watchlist = $list.ToArray()
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
    }
    if ($SwitchToChart) {
        Set-ActiveTab -TabName "Chart"
        Switch-ActiveTicker -NewTicker $resolved -SkipResolve $true
    } else {
        Refresh-AllMarketData
        Update-AllUiViews
    }
    return $true
}

function Remove-SymbolFromWatchlist {
    param([string]$Symbol, [bool]$AskConfirm = $true)
    $u = $Symbol.Trim().ToUpper()
    if ([string]::IsNullOrWhiteSpace($u)) { return $false }
    if (@($script:Config.Watchlist) -notcontains $u) { return $false }
    if ($AskConfirm -and -not (Confirm-Action -Text "'$u' aus der Watchlist entfernen?" -Title "Watchlist")) {
        return $false
    }

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($w in $script:Config.Watchlist) {
        if (-not [string]::IsNullOrWhiteSpace($w) -and $w.Trim().ToUpper() -ne $u) {
            [void]$list.Add($w.Trim().ToUpper())
        }
    }
    if ($list.Count -lt 1) {
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            "Mindestens ein Ticker muss in der Watchlist verbleiben.",
            "Hinweis",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return $false
    }

    $script:Config.Watchlist = $list.ToArray()
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    if ($script:Config.ActiveTicker.ToUpper() -eq $u) {
        Switch-ActiveTicker -NewTicker $list[0] -SkipResolve $true
    } else {
        Update-AllUiViews
    }
    return $true
}


function Get-MetaPrevCloseFallback {
    param($Meta, [double]$RawMarket)
    if ($null -ne $Meta.previousClose -and [double]$Meta.previousClose -gt 0) { return [double]$Meta.previousClose }
    if ($null -ne $Meta.chartPreviousClose -and [double]$Meta.chartPreviousClose -gt 0) { return [double]$Meta.chartPreviousClose }
    return $RawMarket
}

function Update-FxFromResults {
    param([hashtable]$FxUrlMap, [hashtable]$Fetched)
    foreach ($cCode in @($FxUrlMap.Keys)) {
        $fxRes = Get-ChartResult $Fetched[$FxUrlMap[$cCode]]
        if ($null -ne $fxRes -and $null -ne $fxRes.meta.regularMarketPrice -and [double]$fxRes.meta.regularMarketPrice -gt 0) {
            $script:FxFromEur[$cCode] = [double]$fxRes.meta.regularMarketPrice
            [void]$script:FxLive.Add($cCode)
            [void]$script:FxMissing.Remove($cCode)
        }
    }
}

function Get-QuoteTiers {
    # Priority tier: refreshed every poll. Slow tier: watchlist-only tickers.
    $active = $script:Config.ActiveTicker.ToUpper()
    $prio = New-Object System.Collections.Generic.HashSet[string]
    [void]$prio.Add($active)
    foreach ($p in $script:Portfolio.Keys) { [void]$prio.Add($p.ToUpper()) }
    # (re-arming alerts need fresh data too, even while triggered)
    foreach ($a in $script:Alerts) { if (-not $a.Triggered -or [int]$a.RearmMin -gt 0) { [void]$prio.Add($a.Ticker.ToUpper()) } }
    $slow = New-Object System.Collections.Generic.HashSet[string]
    foreach ($w in $script:Config.Watchlist) {
        $u = $w.ToUpper()
        if (-not $prio.Contains($u)) { [void]$slow.Add($u) }
    }
    foreach ($a in $script:Alerts) { $u = $a.Ticker.ToUpper(); if (-not $prio.Contains($u)) { [void]$slow.Add($u) } }
    return @{ Prio = $prio; Slow = $slow }
}

function Refresh-AllMarketData {
    # v2.8: asynchronous. Builds the request plan, hands it to the background
    # worker and returns immediately; Complete-MarketRefresh applies the result
    # on the UI thread (and runs alerts + UI update) when the data is in.
    param([switch]$Force)
    if ($script:IsClosing) { return }
    if ($script:IsRefreshing) {
        # A refresh is in flight: remember the request, it runs right after
        $script:RefreshPending = $true
        if ($Force) { $script:RefreshPendingForce = $true }
        return
    }
    # (rate-limit backoff is applied by the poll timer only, so user actions
    #  like switching ticker still load immediately)
    $plan = $null
    try {
        $plan = New-RefreshPlan -Force:$Force
    } catch {
        Write-WidgetLog "Refresh plan failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
        return
    }
    $script:IsRefreshing   = $true
    $script:RefreshStarted = Get-Date
    Update-RefreshIndicator
    Start-FetchJob -Urls $plan.Urls -Fallbacks $plan.Fallbacks -KnownFx $plan.KnownFx -AutoFx -Context $plan -OnComplete {
        param($Box, $Plan)
        Complete-MarketRefresh -Box $Box -Plan $Plan
    }
}

function Update-RefreshIndicator {
    if ($null -eq $btnRefreshNow -or $btnRefreshNow.IsDisposed) { return }
    $btnRefreshNow.ForeColor = if ($script:IsRefreshing) { [System.Drawing.Color]::FromArgb(245, 158, 11) } else { $script:Pal.Accent }
}

function Complete-MarketRefresh {
    param($Box, $Plan)
    try {
        Apply-RefreshResults -Box $Box -Plan $Plan
    } catch {
        Write-WidgetLog "Refresh failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
    } finally {
        $script:IsRefreshing = $false
    }
    if ($script:IsClosing) { return }
    # v4.0: keep the quote cache fresh (every 2 minutes)
    if (((Get-Date) - $script:LastQuoteCacheSave).TotalSeconds -ge 120 -and $null -ne $script:LastDataTime) { Save-QuoteCache }
    try {
        Evaluate-GlobalAlerts
        Update-AllUiViews
    } catch {
        Write-WidgetLog "UI update after refresh failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
    }
    Update-RefreshIndicator
    if ($script:RefreshPending) {
        $f = [bool]$script:RefreshPendingForce
        $script:RefreshPending = $false
        $script:RefreshPendingForce = $false
        Refresh-AllMarketData -Force:$f
    }
}

function New-RefreshPlan {
    param([switch]$Force)
    # Snapshot of what this refresh is for (user may change it mid-flight)
    $active   = $script:Config.ActiveTicker.ToUpper()
    $tf       = [string]$script:Config.Timeframe
    $dispCurr = [string]$script:Config.Currency
    $extCfg   = [bool]$script:Config.ShowExtended
    $useExt   = $extCfg -and $tf -eq "1d"
    $tfParams = Get-TimeframeParams -Tf $tf
    $now      = Get-Date

    $slowDue = $Force -or $script:Config.ActiveTab -eq "Watchlist" -or
               (($now - $script:LastSlowRefresh).TotalSeconds -ge [int]$script:Config.SlowRefreshSeconds)

    $tiers = Get-QuoteTiers
    $allTickers = New-Object System.Collections.Generic.HashSet[string]
    foreach ($s in $tiers.Prio) { [void]$allTickers.Add($s) }
    foreach ($s in $tiers.Slow) {
        # Slow tier only when due, but always fetch symbols we have no quote for yet
        if ($slowDue -or -not $script:QuoteStore.ContainsKey($s)) { [void]$allTickers.Add($s) }
    }

    # FX: every currency in use (quotes, portfolio, alerts, display)
    $fxNeeded = New-Object System.Collections.Generic.HashSet[string]
    foreach ($c in @("USD", "CHF", "GBP", $dispCurr)) { [void]$fxNeeded.Add($c) }
    foreach ($q in $script:QuoteStore.Values) { [void]$fxNeeded.Add([string]$q.Currency) }
    foreach ($p in $script:Portfolio.Values) { [void]$fxNeeded.Add([string]$p.Currency) }
    # (percent alerts store "%" as currency - not an FX symbol)
    # (only price alerts carry a real currency; "%", "RSI", "SMA" are markers)
    foreach ($a in $script:Alerts) { if ((Get-AlertKind $a.Condition) -eq "PRICE" -and [string]$a.Currency -match '^[A-Z]{3}$') { [void]$fxNeeded.Add([string]$a.Currency) } }
    foreach ($c in $script:FxMissing) { [void]$fxNeeded.Add($c) }
    [void]$fxNeeded.Remove("EUR")

    $fxUrlMap = @{}
    foreach ($c in $fxNeeded) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        # FX moves slowly: only on slow ticks, or when we have no live rate yet
        if ($slowDue -or -not $script:FxLive.Contains($c)) {
            $fxUrlMap[$c] = Get-ChartUrl -Symbol "EUR$c=X" -Interval "1d" -Range "1d"
        }
    }

    $activeChartUrl = Get-ChartUrl -Symbol $active -Interval $tfParams.Interval -Range $tfParams.Range -PrePost:$useExt
    $fallbackUrl = ""
    $fallbacks = @{}
    if ($tf -eq "1d") {
        # EU/CH exchanges before the open have no 2m bars for "today" yet
        $fallbackUrl = Get-ChartUrl -Symbol $active -Interval "5m" -Range "5d" -PrePost:$useExt
        $fallbacks[$activeChartUrl] = $fallbackUrl
    }

    $urlList = New-Object System.Collections.Generic.List[string]
    foreach ($u in $fxUrlMap.Values) { $urlList.Add($u) }
    $urlList.Add($activeChartUrl)

    # Comparison ticker: same interval/range as the active chart
    $compare = ([string]$script:Config.CompareTicker).ToUpper()
    $compareUrl = ""
    if ($compare -and $compare -ne $active) {
        $compareUrl = Get-ChartUrl -Symbol $compare -Interval $tfParams.Interval -Range $tfParams.Range -PrePost:$useExt
        $urlList.Add($compareUrl)
    } else {
        $compare = ""
    }

    $quoteUrlMap = @{}
    foreach ($sym in $allTickers) {
        # includePrePost: extended-hours bars give the pre-/after-market quote;
        # they are filtered out again for day change, sparkline and RSI
        $qUrl = Get-ChartUrl -Symbol $sym -Interval "1h" -Range "5d" -PrePost
        $quoteUrlMap[$sym] = $qUrl
        if (-not $urlList.Contains($qUrl)) { $urlList.Add($qUrl) }
    }

    $knownFx = New-Object System.Collections.Generic.List[string]
    foreach ($c in $script:FxLive) { $knownFx.Add($c) }
    foreach ($c in $fxUrlMap.Keys) { if (-not $knownFx.Contains($c)) { $knownFx.Add($c) } }

    return @{
        Active         = $active
        Tf             = $tf
        DispCurr       = $dispCurr
        ExtCfg         = $extCfg
        UseExt         = $useExt
        SeriesKey      = "$active|$tf|$dispCurr|$useExt"
        Now            = $now
        SlowDue        = [bool]$slowDue
        AllTickers     = @($allTickers)
        FxUrlMap       = $fxUrlMap
        QuoteUrlMap    = $quoteUrlMap
        ActiveChartUrl = $activeChartUrl
        FallbackUrl    = $fallbackUrl
        Fallbacks      = $fallbacks
        Compare        = $compare
        CompareUrl     = $compareUrl
        Urls           = $urlList.ToArray()
        KnownFx        = $knownFx.ToArray()
    }
}

function Update-QuoteFromResult {
    # 2. Quote + 5D sparkline + quick RSI (hourly bars) for one symbol
    param([string]$Sym, $R, [int]$RsiPeriod)
    $meta = $R.meta
    $rawMarket = if ($null -ne $meta.regularMarketPrice) { [double]$meta.regularMarketPrice } else { 0.0 }
    if ($rawMarket -le 0) { return }

    $rawCurr = if ($meta.currency) { [string]$meta.currency } else { "USD" }
    $normP = Normalize-CurrencyAndPrice -Price $rawMarket -RawCurrency $rawCurr
    $price = $normP.Price
    $curr  = $normP.Currency
    $unit  = (Normalize-CurrencyAndPrice -Price 1.0 -RawCurrency $rawCurr).Price   # 1.0 or 0.01 (GBp, ZAc, ILA)

    $tp = Get-TradingPeriodInfo -Meta $meta
    $rawPrev = Get-SessionPrevClose -Result $R -Tp $tp
    if ($null -eq $rawPrev -or $rawPrev -le 0) { $rawPrev = Get-MetaPrevCloseFallback -Meta $meta -RawMarket $rawMarket }
    $prev   = [double]$rawPrev * $unit
    $pct    = if ($prev -gt 0) { (($price - $prev) / $prev) * 100.0 } else { 0.0 }
    $high52 = if ($null -ne $meta.fiftyTwoWeekHigh -and [double]$meta.fiftyTwoWeekHigh -gt 0) { [double]$meta.fiftyTwoWeekHigh * $unit } else { 0.0 }
    $low52  = if ($null -ne $meta.fiftyTwoWeekLow  -and [double]$meta.fiftyTwoWeekLow  -gt 0) { [double]$meta.fiftyTwoWeekLow  * $unit } else { 0.0 }

    $sparkList = New-Object System.Collections.Generic.List[double]
    $extPrice = 0.0
    $extSess  = ""
    $extTs    = 0L
    if ($null -ne $R.indicators -and $null -ne $R.indicators.quote -and @($R.indicators.quote).Count -gt 0 -and $null -ne $R.indicators.quote[0].close -and $null -ne $R.timestamp) {
        $tsArr = @($R.timestamp)
        $clArr = @($R.indicators.quote[0].close)
        $nBars = [math]::Min($tsArr.Count, $clArr.Count)
        for ($k = 0; $k -lt $nBars; $k++) {
            $v = $clArr[$k]
            if ($null -ne $v -and [double]$v -gt 0 -and (Get-BarSession -TsSec ([long]$tsArr[$k]) -Tp $tp) -eq "R") {
                $sparkList.Add([double]$v * $unit)
            }
        }
        # The newest valid bar decides whether there is a pre-/after-market quote
        if ($null -ne $tp -and ($tp.HasPre -or $tp.HasPost)) {
            for ($k = $nBars - 1; $k -ge 0; $k--) {
                $v = $clArr[$k]
                if ($null -ne $v -and [double]$v -gt 0) {
                    $sess = Get-BarSession -TsSec ([long]$tsArr[$k]) -Tp $tp
                    if ($sess -ne "R") {
                        $extPrice = [double]$v * $unit
                        $extSess  = $sess
                        $extTs    = [long]$tsArr[$k]
                    }
                    break
                }
            }
        }
    }
    $extPct = if ($extPrice -gt 0 -and $price -gt 0) { (($extPrice - $price) / $price) * 100.0 } else { 0.0 }
    if ($price -gt 0 -and ($sparkList.Count -eq 0 -or [math]::Abs($sparkList[$sparkList.Count - 1] - $price) -gt 0.00001)) {
        $sparkList.Add($price)
    }
    $sparkArr = $sparkList.ToArray()
    $script:SparklineStore[$Sym] = $sparkArr

    # Hourly SMA (fast period) for the "Kurs > / < SMA" alerts
    $smaArr = Compute-Sma -Prices $sparkArr -Period ([int]$script:Config.SmaFastPeriod)
    $smaH = [double]::NaN
    if ($smaArr.Count -gt 0) { $smaH = $smaArr[$smaArr.Count - 1] }

    $rsiArr = Compute-Rsi -Prices $sparkArr -Period $RsiPeriod
    $lastRsi = [double]::NaN
    for ($k = $rsiArr.Count - 1; $k -ge 0; $k--) {
        if (-not [double]::IsNaN($rsiArr[$k])) { $lastRsi = $rsiArr[$k]; break }
    }

    $script:QuoteStore[$Sym] = [PSCustomObject]@{
        Ticker     = $Sym
        LongName   = if ($meta.shortName) { [string]$meta.shortName } else { $Sym }
        Price      = $price
        PrevClose  = $prev
        ChangePct  = $pct
        Currency   = $curr
        High52     = $high52
        Low52      = $low52
        Rsi14      = $lastRsi
        SmaFastH   = $smaH
        ExtPrice   = $extPrice
        ExtPct     = $extPct
        ExtSession = $extSess
        ExtTs      = $extTs
        Tp         = $tp
        Meta       = (New-MetaLite $meta)
        UpdatedAt  = (Get-Date)
    }
}

function Apply-RefreshResults {
    param($Box, $Plan)
    $active   = $Plan.Active
    $tf       = $Plan.Tf
    $dispCurr = $Plan.DispCurr
    $useExt   = $Plan.UseExt
    $fetched  = $Box.Results
    $script:LastRateLimited = [bool]$Box.RateLimited

    $failedCount = 0
    foreach ($u in $Plan.Urls) {
        if ($null -eq $fetched[$u]) { $failedCount++ }
    }
    if ($failedCount -lt $Plan.Urls.Count) { $script:LastDataTime = Get-Date }

    # 1. FX rates (planned ones + currencies the worker discovered on the way)
    Update-FxFromResults -FxUrlMap $Plan.FxUrlMap -Fetched $fetched
    if ($Box.ExtraFx.Count -gt 0) { Update-FxFromResults -FxUrlMap $Box.ExtraFx -Fetched $fetched }

    # 2. Quotes
    $rsiPeriod = [int]$script:Config.RsiPeriod
    foreach ($sym in $Plan.AllTickers) {
        $r = Get-ChartResult $fetched[$Plan.QuoteUrlMap[$sym]]
        if ($null -ne $r) { Update-QuoteFromResult -Sym $sym -R $r -RsiPeriod $rsiPeriod }
    }
    if ($Plan.SlowDue) { $script:LastSlowRefresh = $Plan.Now }

    # Status / rate-limit backoff
    if ($script:LastRateLimited) {
        $script:BackoffLevel = [math]::Min(5, $script:BackoffLevel + 1)
        $waitSec = [math]::Min(300, 30 * [math]::Pow(2, $script:BackoffLevel - 1))
        $script:BackoffUntil = (Get-Date).AddSeconds($waitSec)
        Write-WidgetLog "Rate limited, pausing auto-refresh for $waitSec s" "WARN"
    } else {
        $script:BackoffLevel = 0
    }
    $script:LastFetchOffline = ($failedCount -eq $Plan.Urls.Count -and -not $script:LastRateLimited)
    $script:LastFetchWarning = if ($script:LastRateLimited) {
        "Rate-Limit: Pause bis {0:HH:mm:ss}" -f $script:BackoffUntil
    } elseif ($failedCount -eq $Plan.Urls.Count) {
        "Offline / API nicht erreichbar"
    } elseif ($failedCount -gt 0) {
        "Teilweise veraltete Daten ($failedCount Fehler)"
    } else {
        ""
    }

    # The user switched ticker/timeframe/currency while we were fetching:
    # don't paint stale chart data, refresh again for the new selection.
    if ($active -ne $script:Config.ActiveTicker.ToUpper() -or $tf -ne $script:Config.Timeframe -or $dispCurr -ne $script:Config.Currency -or $Plan.ExtCfg -ne [bool]$script:Config.ShowExtended) {
        $script:RefreshPending = $true
        return
    }

    # 3. Active ticker chart series (with fallback for EU/CH exchanges)
    $res0 = Get-ChartResult $fetched[$Plan.ActiveChartUrl]
    $validCount = 0
    if ($null -ne $res0 -and $null -ne $res0.indicators -and $null -ne $res0.indicators.quote -and @($res0.indicators.quote).Count -gt 0 -and $null -ne $res0.indicators.quote[0].close) {
        foreach ($v in $res0.indicators.quote[0].close) {
            if ($null -ne $v -and [double]$v -gt 0) { $validCount++ }
        }
    }
    if ($tf -eq "1d" -and $validCount -lt 2 -and $Plan.FallbackUrl) {
        $fbR = Get-ChartResult $fetched[$Plan.FallbackUrl]
        if ($null -ne $fbR) { $res0 = $fbR }
    }

    if ($null -ne $res0 -and $null -ne $res0.indicators -and $null -ne $res0.indicators.quote -and @($res0.indicators.quote).Count -gt 0) {
        Build-ActiveChartSeries -Res0 $res0 -Plan $Plan
        $cmpRes = if ($Plan.CompareUrl) { Get-ChartResult $fetched[$Plan.CompareUrl] } else { $null }
        Build-CompareSeries -R $cmpRes -Plan $Plan
    } elseif ($script:ActiveSeriesKey -eq $Plan.SeriesKey -and @($script:ActiveSeries).Count -ge 2) {
        # Transient fetch failure: keep showing the last good chart (status bar warns)
    } else {
        $script:ActiveSeries    = @()
        $script:ActiveRsiSeries = @()
        $script:ActiveSma20     = @()
        $script:ActiveSma50     = @()
        $script:ActiveVwap      = @()
        $script:ActiveBbUpper   = @()
        $script:ActiveBbLower   = @()
        $script:ActiveLongName  = $active
        $script:ActiveLoadError = "Keine Kursdaten für '$active' gefunden."
    }
}

$script:ActiveCompare = @()
$script:CompareSig    = ""

function Build-CompareSeries {
    # Aligns the comparison ticker's closes to the active series (last known
    # close at or before each bar; daily charts are matched by calendar day)
    param($R, $Plan)
    if (-not $Plan.Compare -or $null -eq $R -or $null -eq $R.timestamp -or $null -eq $R.indicators) {
        # keep the previous line on a transient failure of the same comparison
        if (-not $Plan.Compare) { $script:ActiveCompare = @(); $script:CompareSig = "" }
        return
    }
    $tsArr = @($R.timestamp)
    $clArr = @($R.indicators.quote[0].close)
    $m = [math]::Min($tsArr.Count, $clArr.Count)
    $cTs = New-Object System.Collections.Generic.List[long]
    $cCl = New-Object System.Collections.Generic.List[double]
    for ($k = 0; $k -lt $m; $k++) {
        if ($null -ne $clArr[$k] -and [double]$clArr[$k] -gt 0) { $cTs.Add([long]$tsArr[$k] * 1000); $cCl.Add([double]$clArr[$k]) }
    }
    $ser = @($script:ActiveSeries)
    $n = $ser.Count
    $out = New-Object double[] $n
    $daily = $Plan.Tf -in @("3mo", "6mo", "1y")
    if ($daily) {
        $byDay = @{}
        for ($k = 0; $k -lt $cTs.Count; $k++) { $byDay[[long][math]::Floor($cTs[$k] / 86400000.0)] = $cCl[$k] }
        $last = [double]::NaN
        for ($i = 0; $i -lt $n; $i++) {
            $dk = [long][math]::Floor([long]$ser[$i].Ts / 86400000.0)
            if ($byDay.ContainsKey($dk)) { $last = [double]$byDay[$dk] }
            $out[$i] = $last
        }
    } else {
        $j = 0
        $last = [double]::NaN
        for ($i = 0; $i -lt $n; $i++) {
            $t = [long]$ser[$i].Ts
            while ($j -lt $cTs.Count -and $cTs[$j] -le $t) { $last = $cCl[$j]; $j++ }
            $out[$i] = $last
        }
    }
    $script:ActiveCompare = $out
    $script:CompareSig = "{0}|{1}|{2}" -f $Plan.Compare, $n, $(if ($n -gt 0) { $out[$n - 1] } else { 0 })
}

function Set-CompareTicker {
    param([string]$Symbol)
    $sym = $Symbol.Trim().ToUpper()
    if ($sym) { $sym = Resolve-BestSymbol -RawInput $sym }
    $script:Config.CompareTicker = $sym
    $script:ActiveCompare = @()
    $script:CompareSig = ""
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    if ($sym) { Set-TransientStatus "Vergleich mit $sym wird geladen..." 3 } else { Set-TransientStatus "Vergleich entfernt" 2 }
    Refresh-AllMarketData
    Update-AllUiViews
}

function Show-CompareDialog {
    $p = $script:Pal
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Vergleichen mit"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false; $dlg.ShowInTaskbar = $false
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $dlg.BackColor = $p.BodyBg; $dlg.ForeColor = $p.Text; $dlg.Font = $fontUi
    $dlg.TopMost = $true
    $dlg.ClientSize = New-Object System.Drawing.Size((S 320), (S 112))

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.SetBounds((S 12), (S 12), (S 296), (S 18))
    $lbl.Text = "Ticker (Kursentwicklung in % ab Chartbeginn):"
    $dlg.Controls.Add($lbl)

    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.SetBounds((S 12), (S 34), (S 296), (S 24))
    $cb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    $cb.BackColor = $p.Input; $cb.ForeColor = $p.Text; $cb.Font = $fontMono
    foreach ($sug in @("QQQ", "SPY", "^GSPC", "^NDX", "SOXX", "^GDAXI", "^SSMI", "^ATX", "BTC-USD")) { [void]$cb.Items.Add($sug) }
    foreach ($w in $script:Config.Watchlist) { if (-not $cb.Items.Contains($w)) { [void]$cb.Items.Add($w) } }
    $cb.Text = if ($script:Config.CompareTicker) { [string]$script:Config.CompareTicker } else { "QQQ" }
    $dlg.Controls.Add($cb)

    $ok = New-Object System.Windows.Forms.Button
    $ok.SetBounds((S 118), (S 72), (S 92), (S 28))
    Style-FlatButton -Btn $ok -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $ok.Text = "Vergleichen"
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($ok)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.SetBounds((S 216), (S 72), (S 92), (S 28))
    Style-FlatButton -Btn $cancel -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $cancel.Text = "Abbrechen"
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($cancel)
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel

    $owner = if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed) { $script:FsForm } else { $form }
    $res = $dlg.ShowDialog($owner)
    $txt = $cb.Text
    $dlg.Dispose()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($txt)) {
        Set-CompareTicker -Symbol $txt
    }
}

function ConvertTo-DisplayBars {
    # One pass: optional session repair (1D) + currency conversion -> NEW objects
    # (the intraday cache is never modified).
    #  - Repair: session re-derived from the bar time with the current trading
    #    period (cached bars may have been classified without it), and
    #    extended-hours wicks clipped to the body when they stick out > 1 %
    #    (single off-exchange prints produced long spikes in the post-market)
    param([array]$Bars, $Tp, [double]$Factor, [bool]$Repair)
    $out = New-Object System.Collections.Generic.List[PSObject]
    foreach ($b in $Bars) {
        if ($null -eq $b) { continue }
        $sess = [string]$b.Sess
        if ($Repair -and $null -ne $Tp) { $sess = Get-BarSession -TsSec ([long][math]::Floor([double]$b.Ts / 1000.0)) -Tp $Tp }
        if ([string]::IsNullOrEmpty($sess)) { $sess = "R" }
        $isExt = ($sess -ne "R")
        $o  = [double]$b.Open
        $cl = [double]$b.Close
        $hi = [double]$b.High
        $lo = [double]$b.Low
        if ($Repair -and $isExt) {
            $bodyHi = [math]::Max($o, $cl)
            $bodyLo = [math]::Min($o, $cl)
            if ($hi -gt ($bodyHi * 1.01)) { $hi = $bodyHi }
            if ($lo -lt ($bodyLo * 0.99)) { $lo = $bodyLo }
        }
        $out.Add([PSCustomObject]@{
            Ts     = [long]$b.Ts
            Open   = $o * $Factor
            High   = $hi * $Factor
            Low    = $lo * $Factor
            Close  = $cl * $Factor
            Volume = [long]$b.Volume
            Sess   = $sess
            Ext    = $isExt
        })
    }
    return $out.ToArray()
}

function Build-ActiveChartSeries {
    param($Res0, $Plan)
    $active   = $Plan.Active
    $tf       = $Plan.Tf
    $dispCurr = $Plan.DispCurr
    $useExt   = $Plan.UseExt
    $is1d     = ($tf -eq "1d")

    $script:ActiveLoadError = ""
    $meta0 = $Res0.meta
    $rawCurr0 = if ($meta0.currency) { [string]$meta0.currency } else { "USD" }
    $rawMkt0  = if ($null -ne $meta0.regularMarketPrice) { [double]$meta0.regularMarketPrice } else { 0.0 }
    $normMeta = Normalize-CurrencyAndPrice -Price $rawMkt0 -RawCurrency $rawCurr0
    $unit     = (Normalize-CurrencyAndPrice -Price 1.0 -RawCurrency $rawCurr0).Price

    $script:ActiveNativeCurr = $normMeta.Currency
    $script:ActiveLongName   = if ($meta0.shortName) { [string]$meta0.shortName } else { $active }
    $script:ActiveGmtOffset  = if ($null -ne $meta0.gmtoffset) { [int]$meta0.gmtoffset } else { 0 }
    $tp0 = Get-TradingPeriodInfo -Meta $meta0

    # Previous session close: same source as the header/watchlist day change
    if ($script:QuoteStore.ContainsKey($active) -and $script:QuoteStore[$active].PrevClose -gt 0) {
        $normPrev = [double]$script:QuoteStore[$active].PrevClose
    } else {
        $rawPrev = $null
        if ($is1d -and $null -ne $meta0.chartPreviousClose -and [double]$meta0.chartPreviousClose -gt 0) {
            # for range=1d, chartPreviousClose IS yesterday's close
            $rawPrev = [double]$meta0.chartPreviousClose
        }
        if ($null -eq $rawPrev) { $rawPrev = Get-SessionPrevClose -Result $Res0 -Tp $tp0 }
        if ($null -eq $rawPrev -or $rawPrev -le 0) { $rawPrev = Get-MetaPrevCloseFallback -Meta $meta0 -RawMarket $rawMkt0 }
        $normPrev = [double]$rawPrev * $unit
    }
    # One FX factor for the whole series (was: 4 function calls per bar)
    $fxFactor = Convert-CurrencyValue -Amount 1.0 -FromCurrency $script:ActiveNativeCurr -ToCurrency $dispCurr
    $script:ActivePrevClose = $normPrev * $fxFactor

    $timestamps = $Res0.timestamp
    $quoteObj   = $Res0.indicators.quote[0]
    $parsedPts  = New-Object System.Collections.Generic.List[PSObject]
    if ($null -ne $timestamps) {
        $tsArr = @($timestamps)
        $cArr  = @($quoteObj.close)
        $oArr  = if ($null -ne $quoteObj.open)   { @($quoteObj.open) }   else { @() }
        $hArr  = if ($null -ne $quoteObj.high)   { @($quoteObj.high) }   else { @() }
        $lArr  = if ($null -ne $quoteObj.low)    { @($quoteObj.low) }    else { @() }
        $vArr  = if ($null -ne $quoteObj.volume) { @($quoteObj.volume) } else { @() }
        $nTs   = [math]::Min($tsArr.Count, $cArr.Count)
        for ($i = 0; $i -lt $nTs; $i++) {
            $cVal = $cArr[$i]
            if ($null -eq $cVal -or [double]$cVal -le 0) { continue }
            $cD   = [double]$cVal
            $oVal = if ($i -lt $oArr.Count -and $null -ne $oArr[$i]) { [double]$oArr[$i] } else { $cD }
            $hVal = if ($i -lt $hArr.Count -and $null -ne $hArr[$i]) { [double]$hArr[$i] } else { $cD }
            $lVal = if ($i -lt $lArr.Count -and $null -ne $lArr[$i]) { [double]$lArr[$i] } else { $cD }
            $vVal = if ($i -lt $vArr.Count -and $null -ne $vArr[$i]) { [long]$vArr[$i] } else { 0L }
            # Sessions only matter for intraday 1D bars. Daily bars of some
            # exchanges are stamped at midnight and were shaded as "PRE".
            $sVal = if ($is1d) { Get-BarSession -TsSec ([long]$tsArr[$i]) -Tp $tp0 } else { "R" }
            $parsedPts.Add([PSCustomObject]@{
                Ts     = ([long]$tsArr[$i]) * 1000
                Open   = $oVal * $unit
                High   = $hVal * $unit
                Low    = $lVal * $unit
                Close  = $cD * $unit
                Volume = $vVal
                Sess   = $sVal
                Ext    = ($sVal -ne "R")
            })
        }
    }

    # Live tick / patched last bar are kept apart from the bar data so they
    # never pollute the cache. The meta price is the REGULAR price: never apply
    # it on top of an extended-hours bar.
    $liveTick = $null
    $patchBar = $null
    $lastIsExt = ($parsedPts.Count -gt 0 -and $parsedPts[$parsedPts.Count - 1].Ext)
    if ($normMeta.Price -gt 0 -and -not $lastIsExt) {
        $mp = $normMeta.Price
        $mktTs = if ($null -ne $meta0.regularMarketTime -and [long]$meta0.regularMarketTime -gt 0) {
            ([long]$meta0.regularMarketTime) * 1000
        } else {
            [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        }
        $lastTs = if ($parsedPts.Count -gt 0) { $parsedPts[$parsedPts.Count - 1].Ts } else { 0 }
        $lastClose = if ($parsedPts.Count -gt 0) { $parsedPts[$parsedPts.Count - 1].Close } else { -1.0 }

        if ($mktTs -gt $lastTs -and [math]::Abs($mp - $lastClose) -gt 0.00001) {
            $liveTick = [PSCustomObject]@{ Ts = $mktTs; Open = $mp; High = $mp; Low = $mp; Close = $mp; Volume = 0; Sess = "R"; Ext = $false }
        } elseif ($parsedPts.Count -gt 0) {
            $lb = $parsedPts[$parsedPts.Count - 1]
            $patchBar = [PSCustomObject]@{
                Ts     = $lb.Ts
                Open   = $lb.Open
                High   = [math]::Max($lb.High, $mp)
                Low    = [math]::Min($lb.Low, $mp)
                Close  = $mp
                Volume = $lb.Volume
                Sess   = $lb.Sess
                Ext    = $lb.Ext
            }
        }
    }

    if ($is1d) {
        # @(...) because PowerShell unrolls the returned List into a plain array
        $merged = @(Merge-IntradayPoints -Ticker $active -NewPoints $parsedPts.ToArray())
        # Persist the cache at most once a minute (was: every poll)
        if (((Get-Date) - $script:LastCacheSave).TotalSeconds -ge 60) {
            Prune-IntradayCache
            Save-JsonState -Path $script:CachePath -Data $script:IntradayCache
            $script:LastCacheSave = Get-Date
        }
        $dispArr = @()
        if ($merged.Count -ge 2) {
            # Last trading session in exchange time (not local PC date). If that
            # day only has pre-market bars so far, the previous session is shown
            # as well (otherwise the chart is nearly empty).
            # Only the last two exchange days are repaired/converted (was: the
            # whole 5-day cache on every poll).
            $offS = [double]$script:ActiveGmtOffset
            $nM = $merged.Count
            $days = New-Object long[] $nM
            for ($k = 0; $k -lt $nM; $k++) {
                $days[$k] = [long][math]::Floor(((([long]$merged[$k].Ts) / 1000.0) + $offS) / 86400.0)
            }
            $lastDay = $days[$nM - 1]
            $prevDay = [long]::MinValue
            for ($k = 0; $k -lt $nM; $k++) {
                if ($days[$k] -lt $lastDay -and $days[$k] -gt $prevDay) { $prevDay = $days[$k] }
            }
            $fromDay = if ($prevDay -ne [long]::MinValue) { $prevDay } else { $lastDay }
            $cand = New-Object System.Collections.Generic.List[PSObject]
            $candDays = New-Object System.Collections.Generic.List[long]
            for ($k = 0; $k -lt $nM; $k++) {
                if ($days[$k] -ge $fromDay) { $cand.Add($merged[$k]); $candDays.Add($days[$k]) }
            }
            $candConv = @(ConvertTo-DisplayBars -Bars $cand.ToArray() -Tp $tp0 -Factor $fxFactor -Repair $true)
            $lastDayHasReg = $false
            for ($k = 0; $k -lt $candConv.Count; $k++) {
                if ($candDays[$k] -eq $lastDay -and -not $candConv[$k].Ext) { $lastDayHasReg = $true; break }
            }
            $startDay = if (-not $lastDayHasReg -and $prevDay -ne [long]::MinValue) { $prevDay } else { $lastDay }
            $sel = New-Object System.Collections.Generic.List[PSObject]
            for ($k = 0; $k -lt $candConv.Count; $k++) {
                if ($candDays[$k] -ge $startDay -and ($useExt -or -not $candConv[$k].Ext)) { $sel.Add($candConv[$k]) }
            }
            $dispArr = if ($sel.Count -ge 2) { $sel.ToArray() } else { $candConv }
        } else {
            $dispArr = @(ConvertTo-DisplayBars -Bars $merged -Tp $tp0 -Factor $fxFactor -Repair $true)
        }
    } else {
        $dispArr = @(ConvertTo-DisplayBars -Bars $parsedPts.ToArray() -Tp $null -Factor $fxFactor -Repair $false)
    }

    $dispArr = @($dispArr)
    if ($null -ne $patchBar -and $dispArr.Count -gt 0 -and $dispArr[$dispArr.Count - 1].Ts -eq $patchBar.Ts) {
        $dispArr[$dispArr.Count - 1] = @(ConvertTo-DisplayBars -Bars @($patchBar) -Tp $null -Factor $fxFactor -Repair $false)[0]
    }
    if ($null -ne $liveTick) {
        $dispArr = $dispArr + @(ConvertTo-DisplayBars -Bars @($liveTick) -Tp $null -Factor $fxFactor -Repair $false)
    }

    $closeArr = New-Object double[] $dispArr.Count
    for ($k = 0; $k -lt $dispArr.Count; $k++) { $closeArr[$k] = [double]$dispArr[$k].Close }

    $script:ActiveSeries    = $dispArr
    $script:ActiveRsiSeries = Compute-Rsi -Prices $closeArr -Period ([int]$script:Config.RsiPeriod)
    $script:ActiveSma20     = Compute-Sma -Prices $closeArr -Period ([int]$script:Config.SmaFastPeriod)
    $script:ActiveSma50     = Compute-Sma -Prices $closeArr -Period ([int]$script:Config.SmaSlowPeriod)
    $script:ActiveVwap      = Compute-Vwap -Series $dispArr -GmtOffsetSec $script:ActiveGmtOffset
    $bb                     = Compute-BollingerBands -Prices $closeArr -Period ([int]$script:Config.SmaFastPeriod) -Multiplier 2.0
    $script:ActiveBbUpper   = $bb.Upper
    $script:ActiveBbLower   = $bb.Lower
    $script:ActiveSeriesKey = $Plan.SeriesKey
}

# ==============================================================================
# Part 3: Theme Engine, DPI Helper & Cached GDI+ Chart Renderer
# ==============================================================================
$script:DpiScale = 1.0
function S {
    param([double]$Px)
    return [int][math]::Round($Px * $script:DpiScale)
}

function Enable-DoubleBuffering {
    param([System.Windows.Forms.Control]$Control)
    $prop = $Control.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]"Instance,NonPublic")
    if ($null -ne $prop) { $prop.SetValue($Control, $true, $null) }
}

$script:HoverIndex = -1

# Palette & Cached GDI+ Resources
$colGreen = [System.Drawing.Color]::FromArgb(16, 185, 129)
$colRed   = [System.Drawing.Color]::FromArgb(244, 63, 94)

$fontTicker = New-Object System.Drawing.Font("Consolas", 10.5, [System.Drawing.FontStyle]::Bold)
$fontPrice  = New-Object System.Drawing.Font("Consolas", 13.0, [System.Drawing.FontStyle]::Bold)
$fontUi     = New-Object System.Drawing.Font("Segoe UI", 8.5)
$fontUiBold = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$fontMono   = New-Object System.Drawing.Font("Consolas", 8.5)
$fontAxis   = New-Object System.Drawing.Font("Consolas", 8.0)
$fontBadge  = New-Object System.Drawing.Font("Consolas", 8.0, [System.Drawing.FontStyle]::Bold)

$script:GdiCache = @{}

function Get-ThemeColors {
    $accent = switch ($script:Config.AccentColor) {
        "Amber"  { [System.Drawing.Color]::FromArgb(245, 158, 11) }
        "Violet" { [System.Drawing.Color]::FromArgb(168, 85, 247) }
        default  { [System.Drawing.Color]::FromArgb(56, 189, 248) }
    }

    switch ($script:Config.Theme) {
        "Terminal" {
            # v4.0: amber on black, in the spirit of the classic terminals
            $amberAcc = if ($script:Config.AccentColor -eq "Sky") { [System.Drawing.Color]::FromArgb(255, 159, 28) } else { $accent }
            return @{
                HeaderBg = [System.Drawing.Color]::FromArgb(0, 0, 0)
                BodyBg   = [System.Drawing.Color]::FromArgb(6, 6, 6)
                PanelBg  = [System.Drawing.Color]::FromArgb(0, 0, 0)
                Card     = [System.Drawing.Color]::FromArgb(12, 10, 6)
                Input    = [System.Drawing.Color]::FromArgb(28, 22, 10)
                Hover    = [System.Drawing.Color]::FromArgb(60, 44, 12)
                Grid     = [System.Drawing.Color]::FromArgb(36, 28, 12)
                Border   = [System.Drawing.Color]::FromArgb(84, 60, 18)
                Text     = [System.Drawing.Color]::FromArgb(255, 196, 82)
                Muted    = [System.Drawing.Color]::FromArgb(176, 128, 52)
                Accent   = $amberAcc
                DwmCap   = 0x00000000
                DwmBdr   = 0x00123C54
                DwmDark  = 1
            }
        }
        "OLED" {
            return @{
                HeaderBg = [System.Drawing.Color]::FromArgb(0, 0, 0)
                BodyBg   = [System.Drawing.Color]::FromArgb(8, 10, 14)
                PanelBg  = [System.Drawing.Color]::FromArgb(4, 6, 9)
                Card     = [System.Drawing.Color]::FromArgb(14, 18, 24)
                Input    = [System.Drawing.Color]::FromArgb(22, 28, 38)
                Hover    = [System.Drawing.Color]::FromArgb(34, 42, 56)
                Grid     = [System.Drawing.Color]::FromArgb(24, 30, 40)
                Border   = [System.Drawing.Color]::FromArgb(38, 48, 64)
                Text     = [System.Drawing.Color]::FromArgb(244, 247, 252)
                Muted    = [System.Drawing.Color]::FromArgb(140, 155, 175)
                Accent   = $accent
                DwmCap   = 0x00000000
                DwmBdr   = 0x00403026
                DwmDark  = 1
            }
        }
        "Light" {
            return @{
                HeaderBg = [System.Drawing.Color]::FromArgb(241, 245, 249)
                BodyBg   = [System.Drawing.Color]::FromArgb(248, 250, 252)
                PanelBg  = [System.Drawing.Color]::FromArgb(255, 255, 255)
                Card     = [System.Drawing.Color]::FromArgb(255, 255, 255)
                Input    = [System.Drawing.Color]::FromArgb(226, 232, 240)
                Hover    = [System.Drawing.Color]::FromArgb(203, 213, 225)
                Grid     = [System.Drawing.Color]::FromArgb(226, 232, 240)
                Border   = [System.Drawing.Color]::FromArgb(203, 213, 225)
                Text     = [System.Drawing.Color]::FromArgb(15, 23, 42)
                Muted    = [System.Drawing.Color]::FromArgb(100, 116, 139)
                Accent   = if ($script:Config.AccentColor -eq "Sky") { [System.Drawing.Color]::FromArgb(2, 132, 199) } else { $accent }
                DwmCap   = 0x00F9F5F1
                DwmBdr   = 0x00E1D5CB
                DwmDark  = 0
            }
        }
        default {
            return @{
                HeaderBg = [System.Drawing.Color]::FromArgb(11, 15, 22)
                BodyBg   = [System.Drawing.Color]::FromArgb(20, 27, 38)
                PanelBg  = [System.Drawing.Color]::FromArgb(16, 22, 32)
                Card     = [System.Drawing.Color]::FromArgb(26, 35, 48)
                Input    = [System.Drawing.Color]::FromArgb(32, 43, 59)
                Hover    = [System.Drawing.Color]::FromArgb(44, 58, 80)
                Grid     = [System.Drawing.Color]::FromArgb(34, 44, 60)
                Border   = [System.Drawing.Color]::FromArgb(46, 59, 78)
                Text     = [System.Drawing.Color]::FromArgb(238, 243, 249)
                Muted    = [System.Drawing.Color]::FromArgb(148, 163, 184)
                Accent   = $accent
                DwmCap   = 0x00160F0B
                DwmBdr   = 0x004E3B2E
                DwmDark  = 1
            }
        }
    }
}

$script:Pal = Get-ThemeColors

function Rebuild-GdiCache {
    foreach ($val in $script:GdiCache.Values) {
        if ($null -ne $val -and $val -is [System.IDisposable]) { $val.Dispose() }
    }
    $script:GdiCache.Clear()
    $p = $script:Pal

    $script:GdiCache["bgBrush"]       = New-Object System.Drawing.SolidBrush($p.BodyBg)
    $script:GdiCache["panelBrush"]    = New-Object System.Drawing.SolidBrush($p.PanelBg)
    $script:GdiCache["gridPen"]       = New-Object System.Drawing.Pen($p.Grid, 1)
    $script:GdiCache["sepPen"]        = New-Object System.Drawing.Pen($p.Border, 1)
    $script:GdiCache["axisTextBrush"] = New-Object System.Drawing.SolidBrush($p.Muted)
    $script:GdiCache["msgBrush"]      = New-Object System.Drawing.SolidBrush($p.Text)
    $script:GdiCache["volUpBrush"]    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(48, 16, 185, 129))
    $script:GdiCache["volDownBrush"]  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(48, 244, 63, 94))

    $dash = New-Object System.Drawing.Pen($p.Muted, 1)
    $dash.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $script:GdiCache["dashPen"] = $dash

    $cross = New-Object System.Drawing.Pen($p.Text, 1)
    $cross.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $script:GdiCache["crossPen"] = $cross

    $script:GdiCache["penUp"]      = New-Object System.Drawing.Pen($colGreen, 1.1)
    $script:GdiCache["penDown"]    = New-Object System.Drawing.Pen($colRed, 1.1)
    $script:GdiCache["brUp"]       = New-Object System.Drawing.SolidBrush($colGreen)
    $script:GdiCache["brDown"]     = New-Object System.Drawing.SolidBrush($colRed)
    $script:GdiCache["lineUp"]     = New-Object System.Drawing.Pen($colGreen, 1.9)
    $script:GdiCache["lineDown"]   = New-Object System.Drawing.Pen($colRed, 1.9)
    $script:GdiCache["sparkUp"]    = New-Object System.Drawing.Pen($colGreen, 1.4)
    $script:GdiCache["sparkDown"]  = New-Object System.Drawing.Pen($colRed, 1.4)

    $script:GdiCache["sma20Pen"]   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(250, 204, 21), 1.3)
    $script:GdiCache["sma50Pen"]   = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(192, 132, 252), 1.3)
    $script:GdiCache["sma20Br"]    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(250, 204, 21))
    $script:GdiCache["sma50Br"]    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(192, 132, 252))

    $vwapPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(249, 115, 22), 1.3)
    $vwapPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::DashDot
    $script:GdiCache["vwapPen"]    = $vwapPen
    $script:GdiCache["vwapBr"]     = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(249, 115, 22))

    $bbPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(130, 56, 189, 248), 1.0)
    $bbPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
    $script:GdiCache["bbPen"]      = $bbPen
    $script:GdiCache["bbBr"]       = New-Object System.Drawing.SolidBrush($p.Accent)

    $obPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(130, 244, 63, 94), 1)
    $obPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
    $osPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(130, 16, 185, 129), 1)
    $osPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
    $script:GdiCache["obPen"]      = $obPen
    $script:GdiCache["osPen"]      = $osPen

    $script:GdiCache["rsiPenAcc"]  = New-Object System.Drawing.Pen($p.Accent, 1.5)
    $script:GdiCache["rsiPenUp"]   = New-Object System.Drawing.Pen($colGreen, 1.5)
    $script:GdiCache["rsiPenDown"] = New-Object System.Drawing.Pen($colRed, 1.5)
    $script:GdiCache["rsiBrAcc"]   = New-Object System.Drawing.SolidBrush($p.Accent)

    $script:GdiCache["hudBg"]      = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(238, $p.HeaderBg.R, $p.HeaderBg.G, $p.HeaderBg.B))
    $script:GdiCache["hudFg"]      = New-Object System.Drawing.SolidBrush($p.Text)
    # Comparison ticker line (pink: distinct from up/down, SMA, VWAP, BB)
    $script:GdiCache["cmpPen"]     = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(236, 72, 153), 1.5)
    $script:GdiCache["cmpBr"]      = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(236, 72, 153))
    # Crosshair axis tags: inverted colours, readable in every theme
    $script:GdiCache["crossTagBg"] = New-Object System.Drawing.SolidBrush($p.Text)
    $script:GdiCache["crossTagFg"] = New-Object System.Drawing.SolidBrush($p.HeaderBg)
    $script:GdiCache["tagTextBr"]  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(12, 17, 24))
    $extAlpha = if ($script:Config.Theme -eq "Light") { 34 } else { 26 }
    $script:GdiCache["extBrush"]   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($extAlpha, $p.Muted.R, $p.Muted.G, $p.Muted.B))
}

Rebuild-GdiCache

function Draw-MiniSparkline {
    param(
        [System.Drawing.Graphics]$g,
        [System.Drawing.Rectangle]$Rect,
        [double[]]$Values
    )
    if (-not $Values -or $Values.Count -lt 2) { return }
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $minV = [double]::MaxValue
    $maxV = [double]::MinValue
    foreach ($v in $Values) {
        if ($v -lt $minV) { $minV = $v }
        if ($v -gt $maxV) { $maxV = $v }
    }
    $span = if (($maxV - $minV) -gt 0.0001) { $maxV - $minV } else { 1.0 }

    $padX = 4
    $padY = 4
    $w = $Rect.Width - (2 * $padX)
    $h = $Rect.Height - (2 * $padY)
    if ($w -lt 10 -or $h -lt 6) { return }

    $n = $Values.Count
    $pts = New-Object System.Drawing.PointF[] $n
    for ($i = 0; $i -lt $n; $i++) {
        $x = $Rect.Left + $padX + (($i / [double]($n - 1)) * $w)
        $y = $Rect.Bottom - $padY - ((($Values[$i] - $minV) / $span) * $h)
        $pts[$i] = New-Object System.Drawing.PointF([float]$x, [float]$y)
    }

    $isUp = ($Values[$n - 1] -ge $Values[0])
    $pen = if ($isUp) { $script:GdiCache["sparkUp"] } else { $script:GdiCache["sparkDown"] }
    $g.DrawLines($pen, $pts)
}

function Get-ActiveSeriesKey {
    $useExt = [bool]$script:Config.ShowExtended -and $script:Config.Timeframe -eq "1d"
    return ("{0}|{1}|{2}|{3}" -f $script:Config.ActiveTicker.ToUpper(), $script:Config.Timeframe, $script:Config.Currency, $useExt)
}

function Render-ChartAndRsi {
    param(
        [System.Drawing.Graphics]$g,
        [System.Drawing.Rectangle]$Bounds
    )
    # v2.8: draws the STATIC chart only (into a cached bitmap). Crosshair, axis
    # tags and HUD are drawn per mouse move by Render-ChartOverlay using the
    # geometry left in $script:LastChartLayout.
    $script:LastChartLayout = $null
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $c = $script:GdiCache
    $g.FillRectangle($c["bgBrush"], $Bounds)

    # v4.0: hit areas of legend texts for the hover explanations
    $legends = New-Object System.Collections.Generic.List[PSObject]
    $addLeg = {
        param([string]$Txt, [double]$Lx, [double]$Ly, [string]$Key, $Font = $fontAxis)
        $lsz = $g.MeasureString($Txt, $Font)
        $legends.Add([PSCustomObject]@{ R = (New-Object System.Drawing.RectangleF([float]$Lx, [float]$Ly, [float]$lsz.Width, [float]$lsz.Height)); Key = $Key })
    }

    $rightAxisWidth = S 68
    $padLeft = S 10
    $padTop  = S 6
    $padBot  = S 18
    $showRsi = [bool]$script:Config.ShowRsi
    $gapY    = if ($showRsi) { S 8 } else { 0 }

    $plotWidth = $Bounds.Width - $padLeft - $rightAxisWidth
    $totalH    = $Bounds.Height - $padTop - $padBot - $gapY
    if ($plotWidth -lt 80 -or $totalH -lt 90) { return }

    $priceH = if ($showRsi) { [int]([math]::Floor($totalH * 0.72)) } else { $totalH }
    $rsiH   = $totalH - $priceH

    $priceRect = New-Object System.Drawing.Rectangle($padLeft, $padTop, $plotWidth, $priceH)
    $g.FillRectangle($c["panelBrush"], $priceRect)
    $g.DrawRectangle($c["sepPen"], $priceRect)

    $series = $script:ActiveSeries
    # Never draw a series that belongs to a different ticker/timeframe/currency
    $wantKey = Get-ActiveSeriesKey
    if (-not $series -or $series.Count -lt 2 -or $script:ActiveSeriesKey -ne $wantKey) {
        $statusTxt = if ($script:ActiveLoadError) { $script:ActiveLoadError } else { "Lade Kursdaten / Cache..." }
        $g.DrawString($statusTxt, $fontBadge, $c["msgBrush"], ($padLeft + (S 16)), ($padTop + (S 20)))
        return
    }

    # Zoom / pan (v2.9): draw only the visible window of the series. Indicators
    # are computed on the full series and sliced, so they stay correct.
    $totalN = $series.Count
    $view = Get-ChartView -Total $totalN
    $s0 = [int]$view.Start
    $s1 = [int]$view.End
    if ($s0 -gt 0 -or $s1 -lt ($totalN - 1)) { $series = @($series[$s0..$s1]) }
    $vSma20 = Get-ArraySlice $script:ActiveSma20   $s0 $s1
    $vSma50 = Get-ArraySlice $script:ActiveSma50   $s0 $s1
    $vVwap  = Get-ArraySlice $script:ActiveVwap    $s0 $s1
    $vBbU   = Get-ArraySlice $script:ActiveBbUpper $s0 $s1
    $vBbL   = Get-ArraySlice $script:ActiveBbLower $s0 $s1
    $vRsi   = Get-ArraySlice $script:ActiveRsiSeries $s0 $s1
    $vCmpRaw = Get-ArraySlice $script:ActiveCompare $s0 $s1

    $n = $series.Count

    # Comparison ticker as a %-performance line in price space (rebased to the
    # first visible bar where both have data)
    $cmpVals = $null
    $cmpPct  = $null
    $cmpSym  = [string]$script:Config.CompareTicker
    if ($cmpSym -and @($vCmpRaw).Count -eq $n) {
        $bIdx = -1
        for ($i = 0; $i -lt $n; $i++) {
            if (-not [double]::IsNaN([double]$vCmpRaw[$i]) -and [double]$vCmpRaw[$i] -gt 0 -and [double]$series[$i].Close -gt 0) { $bIdx = $i; break }
        }
        if ($bIdx -ge 0) {
            $cmpVals = New-Object double[] $n
            $cmpPct  = New-Object double[] $n
            $baseC = [double]$vCmpRaw[$bIdx]
            $baseP = [double]$series[$bIdx].Close
            for ($i = 0; $i -lt $n; $i++) {
                $cv = [double]$vCmpRaw[$i]
                if ($i -lt $bIdx -or [double]::IsNaN($cv) -or $cv -le 0) { $cmpVals[$i] = [double]::NaN; $cmpPct[$i] = [double]::NaN; continue }
                $cmpVals[$i] = $baseP * ($cv / $baseC)
                $cmpPct[$i]  = (($cv / $baseC) - 1.0) * 100.0
            }
        }
    }
    $isCandle = ($script:Config.ChartType -eq "Candle")
    $minP = [double]::MaxValue
    $maxP = [double]::MinValue
    $rawLow = [double]::MaxValue
    $rawHigh = [double]::MinValue
    $maxVol = 0L

    for ($i = 0; $i -lt $n; $i++) {
        $lo = if ($isCandle) { $series[$i].Low } else { $series[$i].Close }
        $hi = if ($isCandle) { $series[$i].High } else { $series[$i].Close }
        if ($lo -lt $minP) { $minP = $lo }
        if ($hi -gt $maxP) { $maxP = $hi }
        if ($series[$i].Low  -lt $rawLow)  { $rawLow  = $series[$i].Low }
        if ($series[$i].High -gt $rawHigh) { $rawHigh = $series[$i].High }
        if ($series[$i].Volume -gt $maxVol) { $maxVol = $series[$i].Volume }

        if ($script:Config.ShowSma) {
            if ($i -lt $vSma20.Count -and -not [double]::IsNaN($vSma20[$i])) {
                if ($vSma20[$i] -lt $minP) { $minP = $vSma20[$i] }
                if ($vSma20[$i] -gt $maxP) { $maxP = $vSma20[$i] }
            }
            if ($i -lt $vSma50.Count -and -not [double]::IsNaN($vSma50[$i])) {
                if ($vSma50[$i] -lt $minP) { $minP = $vSma50[$i] }
                if ($vSma50[$i] -gt $maxP) { $maxP = $vSma50[$i] }
            }
        }
        if ($script:Config.ShowVwap -and $script:Config.Timeframe -in @("1d", "5d")) {
            if ($i -lt $vVwap.Count -and -not [double]::IsNaN($vVwap[$i])) {
                if ($vVwap[$i] -lt $minP) { $minP = $vVwap[$i] }
                if ($vVwap[$i] -gt $maxP) { $maxP = $vVwap[$i] }
            }
        }
        if ($null -ne $cmpVals -and -not [double]::IsNaN($cmpVals[$i])) {
            if ($cmpVals[$i] -lt $minP) { $minP = $cmpVals[$i] }
            if ($cmpVals[$i] -gt $maxP) { $maxP = $cmpVals[$i] }
        }
        if ($script:Config.ShowBollinger) {
            if ($i -lt $vBbL.Count -and -not [double]::IsNaN($vBbL[$i])) {
                if ($vBbL[$i] -lt $minP) { $minP = $vBbL[$i] }
                if ($vBbU[$i] -gt $maxP) { $maxP = $vBbU[$i] }
            }
        }
    }
    if ($script:ActivePrevClose -gt 0 -and $script:Config.Timeframe -eq "1d") {
        if ($script:ActivePrevClose -lt $minP) { $minP = $script:ActivePrevClose }
        if ($script:ActivePrevClose -gt $maxP) { $maxP = $script:ActivePrevClose }
    }
    if ($maxP -eq $minP) { $maxP += 1.0; $minP -= 1.0 }
    $padRange = ($maxP - $minP) * 0.08
    $minP -= $padRange
    $maxP += $padRange
    $spanP = $maxP - $minP

    # Horizontal Grid & Right Y-Axis
    $gridSteps = 5
    for ($s = 0; $s -le $gridSteps; $s++) {
        $frac = $s / [double]$gridSteps
        $y = [int]($priceRect.Bottom - ($frac * $priceRect.Height))
        $val = $minP + ($frac * $spanP)
        $g.DrawLine($c["gridPen"], $priceRect.Left, $y, $priceRect.Right, $y)
        $g.DrawString(("{0:N2}" -f $val), $fontAxis, $c["axisTextBrush"], ($priceRect.Right + (S 6)), ($y - (S 6)))
    }

    # Extended-hours shading (pre-/after-market bars in the 1D chart)
    $hasExtBars = $false
    for ($i = 0; $i -lt $n; $i++) { if ($series[$i].Ext) { $hasExtBars = $true; break } }
    if ($hasExtBars) {
        $stepX = $priceRect.Width / [double]($n - 1)
        $i = 0
        while ($i -lt $n) {
            if ($series[$i].Ext) {
                $j = $i
                while (($j + 1) -lt $n -and $series[$j + 1].Ext -and $series[$j + 1].Sess -eq $series[$i].Sess) { $j++ }
                $x1 = [math]::Max([double]$priceRect.Left, $priceRect.Left + ($i * $stepX) - ($stepX / 2.0))
                $x2 = [math]::Min([double]$priceRect.Right, $priceRect.Left + ($j * $stepX) + ($stepX / 2.0))
                if ($x2 -gt $x1) {
                    $g.FillRectangle($c["extBrush"], [float]$x1, [float]$priceRect.Top, [float]($x2 - $x1), [float]$priceRect.Height)
                    $lbl = if ($series[$i].Sess -eq "PRE") { "PRE" } else { "POST" }
                    if (($x2 - $x1) -ge (S 30)) {
                        $g.DrawString($lbl, $fontAxis, $c["axisTextBrush"], [float]($x1 + (S 3)), [float]($priceRect.Bottom - (S 14)))
                        & $addLeg $lbl ($x1 + (S 3)) ($priceRect.Bottom - (S 14)) "EXT"
                    }
                }
                $i = $j + 1
            } else {
                $i++
            }
        }
    }

    # Volume Histogram Overlay
    if ($script:Config.ShowVolume -and $maxVol -gt 0) {
        $volMaxH = [double]$priceRect.Height * 0.22
        $barStep = $priceRect.Width / [double]$n
        $barW = [math]::Max(1, [int][math]::Floor($barStep * 0.65))

        for ($i = 0; $i -lt $n; $i++) {
            if ($series[$i].Volume -gt 0) {
                $vx = [int]($priceRect.Left + (($i / [double]($n - 1)) * $priceRect.Width) - ($barW / 2))
                $vh = [int][math]::Max(1, (($series[$i].Volume / [double]$maxVol) * $volMaxH))
                $vy = $priceRect.Bottom - $vh
                $vBrush = if ($series[$i].Close -ge $series[$i].Open) { $c["volUpBrush"] } else { $c["volDownBrush"] }
                $g.FillRectangle($vBrush, $vx, $vy, $barW, $vh)
            }
        }
    }

    # Previous Close Dashed Line (1D)
    if ($script:ActivePrevClose -gt 0 -and $script:Config.Timeframe -eq "1d") {
        $prevY = [int]($priceRect.Bottom - ((($script:ActivePrevClose - $minP) / $spanP) * $priceRect.Height))
        if ($prevY -ge $priceRect.Top -and $prevY -le $priceRect.Bottom) {
            $g.DrawLine($c["dashPen"], $priceRect.Left, $prevY, $priceRect.Right, $prevY)
        }
    }

    # Price Coordinates
    $pts = New-Object System.Drawing.PointF[] $n
    for ($i = 0; $i -lt $n; $i++) {
        $x = $priceRect.Left + (($i / [double]($n - 1)) * $priceRect.Width)
        $y = $priceRect.Bottom - ((($series[$i].Close - $minP) / $spanP) * $priceRect.Height)
        $pts[$i] = New-Object System.Drawing.PointF([float]$x, [float]$y)
    }

    $basePrice = if ($script:Config.Timeframe -eq "1d" -and $script:ActivePrevClose -gt 0) { $script:ActivePrevClose } else { $series[0].Close }
    $isPositive = ($series[$n - 1].Close -ge $basePrice)
    $lineColor = if ($isPositive) { $colGreen } else { $colRed }

    if ($isCandle) {
        $stepPx = $priceRect.Width / [double]$n
        $bodyW  = [math]::Max(2, [math]::Min(12, [int][math]::Floor($stepPx * 0.68)))

        for ($i = 0; $i -lt $n; $i++) {
            $cx = [int]$pts[$i].X
            $yOpen  = [int]($priceRect.Bottom - ((($series[$i].Open  - $minP) / $spanP) * $priceRect.Height))
            $yClose = [int]$pts[$i].Y
            $yHigh  = [int]($priceRect.Bottom - ((($series[$i].High  - $minP) / $spanP) * $priceRect.Height))
            $yLow   = [int]($priceRect.Bottom - ((($series[$i].Low   - $minP) / $spanP) * $priceRect.Height))

            $bull = ($series[$i].Close -ge $series[$i].Open)
            $wPen = if ($bull) { $c["penUp"] } else { $c["penDown"] }
            $bBr  = if ($bull) { $c["brUp"] }  else { $c["brDown"] }

            $g.DrawLine($wPen, $cx, $yHigh, $cx, $yLow)
            $topY  = [math]::Min($yOpen, $yClose)
            $rectH = [math]::Max(1, [math]::Abs($yClose - $yOpen))
            $g.FillRectangle($bBr, ($cx - [int]($bodyW / 2)), $topY, $bodyW, $rectH)
        }
    } else {
        $fillTop = if ($isPositive) { [System.Drawing.Color]::FromArgb(55, 16, 185, 129) } else { [System.Drawing.Color]::FromArgb(55, 244, 63, 94) }
        $fillBot = [System.Drawing.Color]::FromArgb(4, $script:Pal.PanelBg.R, $script:Pal.PanelBg.G, $script:Pal.PanelBg.B)

        $polyPts = New-Object System.Drawing.PointF[] ($n + 2)
        for ($i = 0; $i -lt $n; $i++) { $polyPts[$i] = $pts[$i] }
        $polyPts[$n]     = New-Object System.Drawing.PointF([float]$pts[$n - 1].X, [float]$priceRect.Bottom)
        $polyPts[$n + 1] = New-Object System.Drawing.PointF([float]$pts[0].X, [float]$priceRect.Bottom)

        $gradBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.Point($priceRect.Left, $priceRect.Top)),
            (New-Object System.Drawing.Point($priceRect.Left, $priceRect.Bottom)),
            $fillTop,
            $fillBot
        )
        $g.FillPolygon($gradBrush, $polyPts)
        $gradBrush.Dispose()

        $pricePen = if ($isPositive) { $c["lineUp"] } else { $c["lineDown"] }
        $g.DrawLines($pricePen, $pts)
    }

    $leftLegendOffset = S 6

    # Optional Bollinger Bands (20, 2)
    if ($script:Config.ShowBollinger) {
        $bbUpPts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $bbLoPts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        for ($i = 0; $i -lt $n; $i++) {
            $x = $pts[$i].X
            if ($i -lt $vBbU.Count -and -not [double]::IsNaN($vBbU[$i])) {
                $yu = $priceRect.Bottom - ((($vBbU[$i] - $minP) / $spanP) * $priceRect.Height)
                $yl = $priceRect.Bottom - ((($vBbL[$i] - $minP) / $spanP) * $priceRect.Height)
                $bbUpPts.Add((New-Object System.Drawing.PointF([float]$x, [float]$yu)))
                $bbLoPts.Add((New-Object System.Drawing.PointF([float]$x, [float]$yl)))
            }
        }
        if ($bbUpPts.Count -ge 2) {
            $g.DrawLines($c["bbPen"], $bbUpPts.ToArray())
            $g.DrawLines($c["bbPen"], $bbLoPts.ToArray())
        }
        $g.DrawString("BB20", $fontAxis, $c["bbBr"], ($priceRect.Left + $leftLegendOffset), ($priceRect.Top + (S 4)))
        & $addLeg "BB20" ($priceRect.Left + $leftLegendOffset) ($priceRect.Top + (S 4)) "BB"
        $leftLegendOffset += S 38
    }

    # Optional SMA Fast & Slow Overlay
    if ($script:Config.ShowSma) {
        $sma20Pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $sma50Pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        for ($i = 0; $i -lt $n; $i++) {
            $x = $pts[$i].X
            if ($i -lt $vSma20.Count -and -not [double]::IsNaN($vSma20[$i])) {
                $y20 = $priceRect.Bottom - ((($vSma20[$i] - $minP) / $spanP) * $priceRect.Height)
                $sma20Pts.Add((New-Object System.Drawing.PointF([float]$x, [float]$y20)))
            }
            if ($i -lt $vSma50.Count -and -not [double]::IsNaN($vSma50[$i])) {
                $y50 = $priceRect.Bottom - ((($vSma50[$i] - $minP) / $spanP) * $priceRect.Height)
                $sma50Pts.Add((New-Object System.Drawing.PointF([float]$x, [float]$y50)))
            }
        }
        if ($sma20Pts.Count -ge 2) { $g.DrawLines($c["sma20Pen"], $sma20Pts.ToArray()) }
        if ($sma50Pts.Count -ge 2) { $g.DrawLines($c["sma50Pen"], $sma50Pts.ToArray()) }

        $s1Lbl = "SMA$($script:Config.SmaFastPeriod)"
        $s2Lbl = "SMA$($script:Config.SmaSlowPeriod)"
        $g.DrawString($s1Lbl, $fontAxis, $c["sma20Br"], ($priceRect.Left + $leftLegendOffset), ($priceRect.Top + (S 4)))
        $g.DrawString($s2Lbl, $fontAxis, $c["sma50Br"], ($priceRect.Left + $leftLegendOffset + (S 44)), ($priceRect.Top + (S 4)))
        & $addLeg $s1Lbl ($priceRect.Left + $leftLegendOffset) ($priceRect.Top + (S 4)) "SMA"
        & $addLeg $s2Lbl ($priceRect.Left + $leftLegendOffset + (S 44)) ($priceRect.Top + (S 4)) "SMA"
        $leftLegendOffset += S 92
    }

    # Optional Intraday VWAP Overlay
    if ($script:Config.ShowVwap -and $script:Config.Timeframe -in @("1d", "5d")) {
        $vwapPts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        for ($i = 0; $i -lt $n; $i++) {
            if ($i -lt $vVwap.Count -and -not [double]::IsNaN($vVwap[$i])) {
                $yv = $priceRect.Bottom - ((($vVwap[$i] - $minP) / $spanP) * $priceRect.Height)
                $vwapPts.Add((New-Object System.Drawing.PointF([float]$pts[$i].X, [float]$yv)))
            }
        }
        if ($vwapPts.Count -ge 2) {
            $g.DrawLines($c["vwapPen"], $vwapPts.ToArray())
            $g.DrawString("VWAP", $fontAxis, $c["vwapBr"], ($priceRect.Left + $leftLegendOffset), ($priceRect.Top + (S 4)))
            & $addLeg "VWAP" ($priceRect.Left + $leftLegendOffset) ($priceRect.Top + (S 4)) "VWAP"
            $leftLegendOffset += S 40
        }
    }

    # Comparison line
    if ($null -ne $cmpVals) {
        $cPts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $lastPct = [double]::NaN
        for ($i = 0; $i -lt $n; $i++) {
            if ([double]::IsNaN($cmpVals[$i])) { continue }
            $yc = $priceRect.Bottom - ((($cmpVals[$i] - $minP) / $spanP) * $priceRect.Height)
            $cPts.Add((New-Object System.Drawing.PointF([float]$pts[$i].X, [float]$yc)))
            $lastPct = $cmpPct[$i]
        }
        if ($cPts.Count -ge 2) { $g.DrawLines($c["cmpPen"], $cPts.ToArray()) }
        if (-not [double]::IsNaN($lastPct)) {
            $cLbl = "vs {0} {1}{2:N2}%" -f $cmpSym, $(if ($lastPct -ge 0) { "+" } else { "" }), $lastPct
            $g.DrawString($cLbl, $fontAxis, $c["cmpBr"], ($priceRect.Left + $leftLegendOffset), ($priceRect.Top + (S 4)))
            & $addLeg $cLbl ($priceRect.Left + $leftLegendOffset) ($priceRect.Top + (S 4)) "COMPARE"
            $leftLegendOffset += [int][math]::Ceiling($g.MeasureString($cLbl, $fontAxis).Width) + (S 8)
        }
    }

    # Period Range & Return Info Badge (always: the hover HUD now sits below it)
    if ($basePrice -gt 0) {
        $periodPct = (($series[$n - 1].Close - $basePrice) / $basePrice) * 100.0
        $pSign = if ($periodPct -ge 0) { "+" } else { "" }
        # Say what the % refers to (with ext hours on, the last bar is Pre/Post)
        $refTxt = if ($script:Config.Timeframe -eq "1d" -and $script:ActivePrevClose -gt 0) { "vs. Vortag" } elseif ($s0 -gt 0 -or $s1 -lt ($totalN - 1)) { "Ausschnitt" } else { "Zeitraum" }
        if ($series[$n - 1].Ext) { $refTxt += $(if ($series[$n - 1].Sess -eq "PRE") { ", inkl. Pre" } else { ", inkl. Post" }) }
        $rangeInfo = "{0} | L:{1:N2} H:{2:N2} | {3}{4:N2}% {5}" -f $script:Config.Timeframe.ToUpper(), $rawLow, $rawHigh, $pSign, $periodPct, $refTxt
        $g.DrawString($rangeInfo, $fontAxis, $c["axisTextBrush"], ($priceRect.Left + $leftLegendOffset), ($priceRect.Top + (S 4)))
        & $addLeg $rangeInfo ($priceRect.Left + $leftLegendOffset) ($priceRect.Top + (S 4)) "RANGE"
    }

    # Position cost basis (EK) and price alerts of this ticker as levels
    if ([bool]$script:Config.ShowLevels) {
        Draw-ChartLevels -g $g -PriceRect $priceRect -MinP $minP -SpanP $spanP -Legends $legends
    }

    # Right Y-Axis Current Price Pill Tag
    $lastY = [int]$pts[$n - 1].Y
    $tagH  = S 18
    $tagRect = New-Object System.Drawing.Rectangle(($priceRect.Right + 2), ($lastY - [int]($tagH / 2)), ($rightAxisWidth - 4), $tagH)
    $tagBrush = New-Object System.Drawing.SolidBrush($lineColor)
    $g.FillRectangle($tagBrush, $tagRect)
    $g.DrawString(("{0:N2}" -f $series[$n - 1].Close), $fontBadge, $c["tagTextBr"], ($tagRect.Left + 3), ($tagRect.Top + 2))
    $tagBrush.Dispose()

    $bottomAxisAnchor = $priceRect.Bottom
    $rsiRectL = $null

    # Optional RSI Sub-Panel
    if ($showRsi -and $rsiH -ge (S 42)) {
        $rsiRect = New-Object System.Drawing.Rectangle($padLeft, ($padTop + $priceH + $gapY), $plotWidth, $rsiH)
        $g.FillRectangle($c["panelBrush"], $rsiRect)
        $g.DrawRectangle($c["sepPen"], $rsiRect)

        $obVal = [double]$script:Config.RsiOverbought
        $osVal = [double]$script:Config.RsiOversold
        $yOb = [int]($rsiRect.Bottom - (($obVal / 100.0) * $rsiRect.Height))
        $y50 = [int]($rsiRect.Bottom - (0.50 * $rsiRect.Height))
        $yOs = [int]($rsiRect.Bottom - (($osVal / 100.0) * $rsiRect.Height))

        $g.DrawLine($c["obPen"], $rsiRect.Left, $yOb, $rsiRect.Right, $yOb)
        $g.DrawLine($c["gridPen"], $rsiRect.Left, $y50, $rsiRect.Right, $y50)
        $g.DrawLine($c["osPen"], $rsiRect.Left, $yOs, $rsiRect.Right, $yOs)

        $g.DrawString("$obVal", $fontAxis, $c["axisTextBrush"], ($rsiRect.Right + (S 6)), ($yOb - (S 6)))
        $g.DrawString("$osVal", $fontAxis, $c["axisTextBrush"], ($rsiRect.Right + (S 6)), ($yOs - (S 6)))

        $rsiArr = $vRsi
        $validRsiPts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $lastRsiVal = [double]::NaN

        if ($null -ne $rsiArr -and $rsiArr.Count -eq $n) {
            for ($i = 0; $i -lt $n; $i++) {
                $rv = $rsiArr[$i]
                if (-not [double]::IsNaN($rv)) {
                    $clamped = [math]::Max(0.0, [math]::Min(100.0, $rv))
                    $rx = $rsiRect.Left + (($i / [double]($n - 1)) * $rsiRect.Width)
                    $ry = $rsiRect.Bottom - (($clamped / 100.0) * $rsiRect.Height)
                    $validRsiPts.Add((New-Object System.Drawing.PointF([float]$rx, [float]$ry)))
                    $lastRsiVal = $rv
                }
            }
        }

        $rPeriod = [int]$script:Config.RsiPeriod
        if ($validRsiPts.Count -ge 2) {
            $rsiPen = if ($lastRsiVal -ge $obVal) { $c["rsiPenDown"] } elseif ($lastRsiVal -le $osVal) { $c["rsiPenUp"] } else { $c["rsiPenAcc"] }
            $g.DrawLines($rsiPen, $validRsiPts.ToArray())

            $rsiLblBrush = if ($lastRsiVal -ge $obVal) { $c["brDown"] } elseif ($lastRsiVal -le $osVal) { $c["brUp"] } else { $c["rsiBrAcc"] }
            $g.DrawString(("RSI({0}): {1:N1}" -f $rPeriod, $lastRsiVal), $fontBadge, $rsiLblBrush, ($rsiRect.Left + (S 6)), ($rsiRect.Top + 3))
            & $addLeg ("RSI({0}): {1:N1}" -f $rPeriod, $lastRsiVal) ($rsiRect.Left + (S 6)) ($rsiRect.Top + 3) "RSI" $fontBadge
        } else {
            $g.DrawString("RSI(${rPeriod}): n/a", $fontAxis, $c["axisTextBrush"], ($rsiRect.Left + (S 6)), ($rsiRect.Top + 3))
        }
        $bottomAxisAnchor = $rsiRect.Bottom
        $rsiRectL = $rsiRect
    }

    # X-Axis Timestamps
    $idxList = @(0, [int]([math]::Floor(($n - 1) / 2)), ($n - 1))
    foreach ($idx in $idxList) {
        $dt = [DateTimeOffset]::FromUnixTimeMilliseconds($series[$idx].Ts).ToLocalTime()
        $fmt = if ($script:Config.Timeframe -in @("1d", "5d")) { "dd.MM HH:mm" } else { "dd.MM.yy" }
        $tStr = $dt.ToString($fmt)
        $tx = [int]$pts[$idx].X - (S 24)
        if ($tx -lt $priceRect.Left) { $tx = $priceRect.Left }
        if ($tx -gt ($priceRect.Right - (S 68))) { $tx = $priceRect.Right - (S 68) }
        $g.DrawString($tStr, $fontAxis, $c["axisTextBrush"], $tx, ($bottomAxisAnchor + 3))
    }

    if ($s0 -gt 0 -or $s1 -lt ($totalN - 1)) {
        $zTxt = "Zoom {0}/{1} Bars | Strg+Rad zoomt, Umschalt+Rad schiebt, Z = alles" -f $n, $totalN
        $g.DrawString($zTxt, $fontAxis, $c["axisTextBrush"], ($priceRect.Left + (S 6)), ($priceRect.Bottom - (S 30)))
        & $addLeg $zTxt ($priceRect.Left + (S 6)) ($priceRect.Bottom - (S 30)) "ZOOM"
    }

    # Geometry for the overlay (crosshair / axis tags / HUD) and mouse hit-testing
    $script:LastChartLayout = @{
        ViewStart      = $s0
        Total          = $totalN
        Series         = $series
        Rsi            = $vRsi
        CmpPct         = $cmpPct
        CmpSym         = $cmpSym
        PriceRect      = $priceRect
        RsiRect        = $rsiRectL
        BottomAxis     = $bottomAxisAnchor
        MinP           = $minP
        SpanP          = $spanP
        Pts            = $pts
        N              = $n
        IsCandle       = $isCandle
        RightAxisWidth = $rightAxisWidth
        OffsetY        = 0
        Legends        = $legends.ToArray()
    }
}


# Visible window of the chart (0 = whole series). Reset on ticker/timeframe change.
$script:ViewCount  = 0
$script:ViewOffset = 0
$script:ViewKey    = ""
$script:Measure    = @{ Active = $false; Dragging = $false; A = -1; B = -1; X0 = 0; Key = "" }

function Get-ChartView {
    param([int]$Total)
    $key = Get-ActiveSeriesKey
    if ($key -ne $script:ViewKey) {
        $script:ViewKey = $key
        $script:ViewCount = 0
        $script:ViewOffset = 0
    }
    if ([int]$script:ViewCount -le 0 -or [int]$script:ViewCount -ge $Total) { return @{ Start = 0; End = ($Total - 1) } }
    $cnt = [math]::Max(2, [int]$script:ViewCount)
    $off = [math]::Max(0, [math]::Min([int]$script:ViewOffset, $Total - $cnt))
    $end = $Total - 1 - $off
    return @{ Start = ($end - $cnt + 1); End = $end }
}

function Refresh-ChartView {
    Update-ChartCacheSignature
    $pnlChartCanvas.Invalidate()
    if ($null -ne $script:FsCanvas -and -not $script:FsCanvas.IsDisposed) { $script:FsCanvas.Invalidate() }
}

function Reset-ChartZoom {
    $script:ViewCount = 0
    $script:ViewOffset = 0
    Refresh-ChartView
}

function Zoom-Chart {
    # Ctrl + wheel: zoom around the bar under the mouse
    param([System.Windows.Forms.Control]$Canvas, [int]$Delta, [int]$X)
    $N = @($script:ActiveSeries).Count
    if ($N -lt 12 -or $script:ActiveSeriesKey -ne (Get-ActiveSeriesKey)) { return }
    $v = Get-ChartView -Total $N
    $cnt = $v.End - $v.Start + 1
    $rel = 1.0
    $L = Get-CanvasLayout -Canvas $Canvas
    if ($null -ne $L -and $L.PriceRect.Width -gt 0) {
        $rel = [math]::Max(0.0, [math]::Min(1.0, ($X - $L.PriceRect.Left) / [double]$L.PriceRect.Width))
    }
    $anchor = $v.Start + ($rel * ($cnt - 1))
    $factor = if ($Delta -gt 0) { 0.8 } else { 1.25 }
    $newCnt = [int][math]::Round($cnt * $factor)
    if ($newCnt -eq $cnt) { $newCnt += $(if ($Delta -gt 0) { -1 } else { 1 }) }
    $newCnt = [math]::Max(10, $newCnt)
    if ($newCnt -ge $N) { Reset-ChartZoom; return }
    $newStart = [int][math]::Round($anchor - ($rel * ($newCnt - 1)))
    $newStart = [math]::Max(0, [math]::Min($N - $newCnt, $newStart))
    $script:ViewCount = $newCnt
    $script:ViewOffset = $N - 1 - ($newStart + $newCnt - 1)
    $script:HoverIndex = -1
    Refresh-ChartView
}

function Pan-Chart {
    # Shift + wheel: move the zoomed window (+1 = newer, -1 = older)
    param([int]$Dir)
    $N = @($script:ActiveSeries).Count
    if ([int]$script:ViewCount -le 0 -or $N -lt 2) { return }
    $step = [math]::Max(1, [int][math]::Round([int]$script:ViewCount * 0.1))
    $script:ViewOffset = [math]::Max(0, [math]::Min($N - [int]$script:ViewCount, [int]$script:ViewOffset - ($Dir * $step)))
    $script:HoverIndex = -1
    Refresh-ChartView
}

function Get-CanvasLayout {
    param([System.Windows.Forms.Control]$Canvas)
    $key = if ($null -ne $script:FsCanvas -and [object]::ReferenceEquals($Canvas, $script:FsCanvas)) { "fs" } else { "main" }
    $ent = $script:ChartBmpCache[$key]
    if ($null -eq $ent) { return $null }
    return $ent.Layout
}

function Clear-ChartMeasure {
    $script:Measure = @{ Active = $false; Dragging = $false; A = -1; B = -1; X0 = 0; Key = "" }
    Refresh-ChartView
}

function Format-LevelPrice {
    # Sensible rounding for a price picked with the mouse
    param([double]$P, [switch]$Raw)
    $dec = if ($P -ge 1000) { 1 } elseif ($P -ge 1) { 2 } else { 4 }
    $r = [math]::Round($P, $dec)
    if ($Raw) { return $r.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
    return $r.ToString("N$dec")
}

function Get-ChartLevels {
    # EK of the position + price alerts of the active ticker, in display currency
    $sym  = $script:Config.ActiveTicker.ToUpper()
    $curr = $script:Config.Currency
    $out = @()
    if ($script:Portfolio.ContainsKey($sym)) {
        $pp = $script:Portfolio[$sym]
        if ($pp.AvgPrice -gt 0) {
            $ek = Convert-CurrencyValue -Amount $pp.AvgPrice -FromCurrency $pp.Currency -ToCurrency $curr
            $out += [PSCustomObject]@{ Price = $ek; Label = ("EK {0:N2}" -f $ek); Kind = "EK"; Hit = $false }
        }
    }
    foreach ($a in $script:Alerts) {
        if ($a.Ticker -ne $sym -or (Get-AlertKind $a.Condition) -ne "PRICE") { continue }
        $lv = Convert-CurrencyValue -Amount $a.TargetPrice -FromCurrency $a.Currency -ToCurrency $curr
        $out += [PSCustomObject]@{ Price = $lv; Label = ("Alarm {0} {1:N2}" -f $a.Condition, $lv); Kind = "AL"; Hit = [bool]$a.Triggered }
    }
    return $out
}

function Draw-ChartLevels {
    param([System.Drawing.Graphics]$g, [System.Drawing.Rectangle]$PriceRect, [double]$MinP, [double]$SpanP, $Legends = $null)
    $levels = @(Get-ChartLevels)
    if ($levels.Count -eq 0) { return }
    $amber = [System.Drawing.Color]::FromArgb(245, 158, 11)
    $topY = $PriceRect.Top + (S 4)
    $botY = $PriceRect.Bottom - (S 18)
    foreach ($lv in $levels) {
        $colr = if ($lv.Kind -eq "EK") { $script:Pal.Accent } elseif ($lv.Hit) { $script:Pal.Muted } else { $amber }
        $txt = $lv.Label
        $ly = $PriceRect.Bottom - ((([double]$lv.Price - $MinP) / $SpanP) * $PriceRect.Height)
        $sz = $g.MeasureString($txt, $fontAxis)
        $tw = [int][math]::Ceiling($sz.Width) + (S 6)
        $th = S 15
        $br = New-Object System.Drawing.SolidBrush($colr)
        $fg = $script:GdiCache["tagTextBr"]
        try {
            if ($ly -ge $PriceRect.Top -and $ly -le $PriceRect.Bottom) {
                $pen = New-Object System.Drawing.Pen($colr, 1)
                $pen.DashStyle = if ($lv.Kind -eq "EK") { [System.Drawing.Drawing2D.DashStyle]::DashDotDot } else { [System.Drawing.Drawing2D.DashStyle]::Dash }
                $g.DrawLine($pen, $PriceRect.Left, [float]$ly, $PriceRect.Right, [float]$ly)
                $pen.Dispose()
                # tag just above the line, right side of the plot
                $tx = $PriceRect.Right - $tw - (S 4)
                $ty = [int]$ly - $th - 1
                if ($ty -lt $PriceRect.Top) { $ty = [int]$ly + 1 }
                $g.FillRectangle($br, $tx, $ty, $tw, $th)
                $g.DrawString($txt, $fontAxis, $fg, ($tx + (S 3)), ($ty + 1))
                if ($null -ne $Legends) { $Legends.Add([PSCustomObject]@{ R = (New-Object System.Drawing.RectangleF([float]$tx, [float]$ty, [float]$tw, [float]$th)); Key = $(if ($lv.Kind -eq "EK") { "EK" } else { "LEVELS" }) }) }
            } else {
                # off-screen: small marker at the edge with an arrow
                $arrow = if ($ly -lt $PriceRect.Top) { [string][char]0x25B2 } else { [string][char]0x25BC }
                $txt2 = "$txt $arrow"
                $tw2 = [int][math]::Ceiling($g.MeasureString($txt2, $fontAxis).Width) + (S 6)
                $tx = $PriceRect.Right - $tw2 - (S 4)
                if ($ly -lt $PriceRect.Top) { $ty = $topY; $topY += $th + 2 } else { $ty = $botY; $botY -= $th + 2 }
                $g.FillRectangle($br, $tx, $ty, $tw2, $th)
                $g.DrawString($txt2, $fontAxis, $fg, ($tx + (S 3)), ($ty + 1))
                if ($null -ne $Legends) { $Legends.Add([PSCustomObject]@{ R = (New-Object System.Drawing.RectangleF([float]$tx, [float]$ty, [float]$tw2, [float]$th)); Key = "LEVELS" }) }
            }
        } finally {
            $br.Dispose()
        }
    }
}


function Render-ChartOverlay {
    # Drawn on top of the cached chart bitmap on every paint: cheap enough for
    # smooth mouse tracking (the old version re-rendered the whole chart).
    param([System.Drawing.Graphics]$g, $L)
    if ($null -eq $L) { return }
    $series = $L.Series          # visible window (zoom), same as the bitmap
    $n  = [int]$L.N
    $c  = $script:GdiCache
    $pr = $L.PriceRect
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    # Measure tool (left mouse drag): change between two bars
    $m = $script:Measure
    if ($m.Active -and $m.Key -eq $script:ActiveSeriesKey) {
        $la = [int]$m.A - [int]$L.ViewStart
        $lb = [int]$m.B - [int]$L.ViewStart
        if ($la -ge 0 -and $lb -ge 0 -and $la -lt $n -and $lb -lt $n -and $la -ne $lb) {
            Draw-ChartMeasure -g $g -L $L -Series $series -IdxA $la -IdxB $lb
        }
    }

    $hi = [int]$script:HoverIndex
    if ($hi -lt 0 -or $hi -ge $n -or @($series).Count -ne $n) { return }

    $hx = [int]$L.Pts[$hi].X
    $cy = [float]$L.Pts[$hi].Y
    $my = [int]$script:HoverY - [int]$L.OffsetY
    $inPrice = ($my -ge $pr.Top -and $my -le $pr.Bottom)
    $rr = $L.RsiRect
    $inRsi = ($null -ne $rr -and $my -ge $rr.Top -and $my -le $rr.Bottom)

    # Vertical line through the bar, horizontal line follows the mouse
    $g.DrawLine($c["crossPen"], $hx, $pr.Top, $hx, $L.BottomAxis)
    $hy = if ($inPrice) { $my } else { [int]$cy }
    $g.DrawLine($c["crossPen"], $pr.Left, $hy, $pr.Right, $hy)

    # Marker on the close of the hovered bar
    $mk = [float](S 3)
    $g.FillEllipse($c["hudFg"], ([float]$hx - $mk), ($cy - $mk), (2 * $mk), (2 * $mk))

    # Y-axis tag: price at the horizontal line
    $tagH = S 18
    $tagW = [int]$L.RightAxisWidth - 4
    $yVal = [double]$L.MinP + ((($pr.Bottom - $hy) / [double]$pr.Height) * [double]$L.SpanP)
    $tagRect = New-Object System.Drawing.Rectangle(($pr.Right + 2), ($hy - [int]($tagH / 2)), $tagW, $tagH)
    $g.FillRectangle($c["crossTagBg"], $tagRect)
    $g.DrawString(("{0:N2}" -f $yVal), $fontBadge, $c["crossTagFg"], ($tagRect.Left + 3), ($tagRect.Top + 2))

    # RSI pane: horizontal line + value tag at the mouse
    if ($inRsi -and $rr.Height -gt 0) {
        $g.DrawLine($c["crossPen"], $rr.Left, $my, $rr.Right, $my)
        $rVal = (($rr.Bottom - $my) / [double]$rr.Height) * 100.0
        $rTag = New-Object System.Drawing.Rectangle(($rr.Right + 2), ($my - [int]($tagH / 2)), $tagW, $tagH)
        $g.FillRectangle($c["crossTagBg"], $rTag)
        $g.DrawString(("{0:N1}" -f $rVal), $fontBadge, $c["crossTagFg"], ($rTag.Left + 3), ($rTag.Top + 2))
    }

    # X-axis tag: date/time of the hovered bar
    $hPt = $series[$hi]
    $fmt = if ($script:Config.Timeframe -in @("1d", "5d")) { "ddd dd.MM HH:mm" } else { "ddd dd.MM.yy" }
    $tStr = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$hPt.Ts).ToLocalTime().ToString($fmt)
    $tSz = $g.MeasureString($tStr, $fontAxis)
    $tW = [int]$tSz.Width + (S 8)
    $tX = [math]::Max($pr.Left, [math]::Min(($hx - [int]($tW / 2)), ($pr.Right - $tW)))
    $tRect = New-Object System.Drawing.Rectangle($tX, ($L.BottomAxis + 1), $tW, (S 16))
    $g.FillRectangle($c["crossTagBg"], $tRect)
    $g.DrawString($tStr, $fontAxis, $c["crossTagFg"], ($tRect.Left + (S 4)), ($tRect.Top + 1))

    # HUD (below the legend row, so legends + range badge stay readable)
    $hDt = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$hPt.Ts).ToLocalTime().ToString("dd.MM HH:mm")
    if ($hPt.Ext) { $hDt += $(if ($hPt.Sess -eq "PRE") { " Pre" } else { " Post" }) }
    $hRsi = ""
    $rArr = $L.Rsi
    if ($null -ne $rArr -and $hi -lt @($rArr).Count -and -not [double]::IsNaN([double]$rArr[$hi])) {
        $hRsi = " | RSI {0:N1}" -f [double]$rArr[$hi]
    }
    if ($null -ne $L.CmpPct -and $hi -lt @($L.CmpPct).Count -and -not [double]::IsNaN([double]$L.CmpPct[$hi])) {
        $cp = [double]$L.CmpPct[$hi]
        $hRsi += " | {0} {1}{2:N2}%" -f $L.CmpSym, $(if ($cp -ge 0) { "+" } else { "" }), $cp
    }
    $hVol = if ([long]$hPt.Volume -gt 0) { " | Vol " + (Format-CompactNumber ([double]$hPt.Volume)) } else { "" }
    $hChg = ""
    if ($hi -gt 0 -and [double]$series[$hi - 1].Close -gt 0) {
        $chg = (([double]$hPt.Close - [double]$series[$hi - 1].Close) / [double]$series[$hi - 1].Close) * 100.0
        $hChg = " ({0}{1:N2}%)" -f $(if ($chg -ge 0) { "+" } else { "" }), $chg
    }
    $hudTxt = if ($L.IsCandle) {
        "{0} | O:{1:N2} H:{2:N2} L:{3:N2} C:{4:N2}{5}{6}{7}" -f $hDt, $hPt.Open, $hPt.High, $hPt.Low, $hPt.Close, $hChg, $hVol, $hRsi
    } else {
        "{0} | C: {1:N2} {2}{3}{4}{5}" -f $hDt, $hPt.Close, $script:Config.Currency, $hChg, $hVol, $hRsi
    }
    $hudSz = $g.MeasureString($hudTxt, $fontAxis)
    $hudW = [int][math]::Ceiling($hudSz.Width) + (S 10)
    $hudH = S 20
    $hudX = $pr.Right - $hudW - (S 6)
    if ($hudX -lt ($pr.Left + 6)) { $hudX = $pr.Left + 6 }
    $hudRect = New-Object System.Drawing.Rectangle($hudX, ($pr.Top + (S 22)), $hudW, $hudH)
    $g.FillRectangle($c["hudBg"], $hudRect)
    $g.DrawRectangle($c["sepPen"], $hudRect)
    $g.DrawString($hudTxt, $fontAxis, $c["hudFg"], ($hudRect.Left + 5), ($hudRect.Top + 3))
}

function Draw-ChartMeasure {
    param([System.Drawing.Graphics]$g, $L, $Series, [int]$IdxA, [int]$IdxB)
    $pr = $L.PriceRect
    if ($IdxB -lt $IdxA) { $t = $IdxA; $IdxA = $IdxB; $IdxB = $t }
    $pa = $L.Pts[$IdxA]
    $pb = $L.Pts[$IdxB]
    $ca = [double]$Series[$IdxA].Close
    $cb = [double]$Series[$IdxB].Close
    if ($ca -le 0) { return }
    $d = $cb - $ca
    $pct = ($d / $ca) * 100.0
    $up = ($d -ge 0)
    $col = if ($up) { $colGreen } else { $colRed }
    $fill = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(36, $col.R, $col.G, $col.B))
    $pen  = New-Object System.Drawing.Pen($col, 1.5)
    $lblBr = New-Object System.Drawing.SolidBrush($col)
    try {
        $g.FillRectangle($fill, [float]$pa.X, [float]$pr.Top, [float]([math]::Max(1.0, $pb.X - $pa.X)), [float]$pr.Height)
        $g.DrawLine($pen, $pa, $pb)
        $g.FillEllipse($lblBr, ($pa.X - 3), ($pa.Y - 3), 6, 6)
        $g.FillEllipse($lblBr, ($pb.X - 3), ($pb.Y - 3), 6, 6)
        $secs = [long](([long]$Series[$IdxB].Ts - [long]$Series[$IdxA].Ts) / 1000)
        $txt = "{0}{1:N2} ({0}{2:N2}%) | {3} Bars | {4}" -f $(if ($up) { "+" } else { "" }), $d, $pct, ($IdxB - $IdxA), (Format-Duration $secs)
        $sz = $g.MeasureString($txt, $fontBadge)
        $w = [int][math]::Ceiling($sz.Width) + (S 10)
        $h = S 20
        $x = [int](($pa.X + $pb.X) / 2) - [int]($w / 2)
        $x = [math]::Max($pr.Left + 2, [math]::Min($x, $pr.Right - $w - 2))
        $y = [int][math]::Min($pa.Y, $pb.Y) - $h - (S 6)
        if ($y -lt ($pr.Top + (S 44))) { $y = [int][math]::Max($pa.Y, $pb.Y) + (S 6) }
        $g.FillRectangle($lblBr, $x, $y, $w, $h)
        $g.DrawString($txt, $fontBadge, $script:GdiCache["tagTextBr"], ($x + (S 5)), ($y + (S 3)))
    } finally {
        $fill.Dispose(); $pen.Dispose(); $lblBr.Dispose()
    }
}

# ------------------------------------------------------------------------------
# Chart bitmap cache: the static chart is rendered once per data/setting change
# and blitted on every paint; only the overlay is drawn live.
# ------------------------------------------------------------------------------
$script:ChartVersion    = 0
$script:ChartSignature  = ""
$script:ChartBmpCache   = @{}
$script:LastChartLayout = $null
$script:HoverY          = -1

function Update-ChartCacheSignature {
    # Bumps the version only when something the static chart shows changed
    # (alerts / status / tray updates no longer force a full re-render)
    $cfg = $script:Config
    $ser = $script:ActiveSeries
    $serId = 0
    $lastTs = 0L
    $lastC = 0.0
    if ($null -ne $ser -and @($ser).Count -gt 0) {
        $serId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($ser)
        $lastTs = [long]$ser[@($ser).Count - 1].Ts
        $lastC = [double]$ser[@($ser).Count - 1].Close
    }
    $sig = @(
        $serId, @($ser).Count, $lastTs, $lastC, $script:ActiveSeriesKey, $script:ActiveLoadError, $script:ActivePrevClose,
        $cfg.ChartType, $cfg.ShowVolume, $cfg.ShowSma, $cfg.ShowVwap, $cfg.ShowBollinger, $cfg.ShowRsi, $cfg.ShowExtended,
        $cfg.Theme, $cfg.AccentColor, $cfg.Timeframe, $cfg.Currency, $cfg.ActiveTicker,
        $cfg.SmaFastPeriod, $cfg.SmaSlowPeriod, $cfg.RsiPeriod, $cfg.RsiOverbought, $cfg.RsiOversold,
        $lblLivePrice.Text, $lblDayChange.Text, $lblDayAbs.Text, $lblExtQuote.Text, $lblHeaderName.Text,
        $cfg.ShowLevels, (@(Get-ChartLevels | ForEach-Object { "{0:N4}{1}{2}" -f $_.Price, $_.Kind, $_.Hit }) -join ","),
        $cfg.CompareTicker, $script:CompareSig, $script:ViewCount, $script:ViewOffset
    ) -join "|"
    if ($sig -ne $script:ChartSignature) {
        $script:ChartSignature = $sig
        $script:ChartVersion++
    }
}

function Remove-ChartBitmap {
    param([string]$Key)
    $ent = $script:ChartBmpCache[$Key]
    if ($null -ne $ent -and $null -ne $ent.Bmp) { try { $ent.Bmp.Dispose() } catch { } }
    $script:ChartBmpCache.Remove($Key)
}

function Paint-ChartCanvas {
    param([System.Windows.Forms.Control]$Canvas, [System.Drawing.Graphics]$G, [bool]$Fullscreen)
    $key = if ($Fullscreen) { "fs" } else { "main" }
    $w = $Canvas.ClientSize.Width
    $h = $Canvas.ClientSize.Height
    if ($w -lt 2 -or $h -lt 2) { return }
    $ent = $script:ChartBmpCache[$key]
    if ($null -eq $ent -or $ent.Version -ne $script:ChartVersion -or $ent.W -ne $w -or $ent.H -ne $h) {
        Remove-ChartBitmap -Key $key
        $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
        $bg = [System.Drawing.Graphics]::FromImage($bmp)
        $layout = $null
        try {
            $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
            if ($Fullscreen) { Render-FullscreenChart -g $bg -Bounds $rect } else { Render-ChartAndRsi -g $bg -Bounds $rect }
            $layout = $script:LastChartLayout
        } catch {
            Write-WidgetLog "Chart render failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
        } finally {
            $bg.Dispose()
        }
        $ent = @{ Bmp = $bmp; Version = $script:ChartVersion; W = $w; H = $h; Layout = $layout }
        $script:ChartBmpCache[$key] = $ent
    }
    $G.DrawImageUnscaled($ent.Bmp, 0, 0)
    if ($null -ne $ent.Layout -and ($script:HoverIndex -ge 0 -or $script:Measure.Active)) {
        $oy = [float]$ent.Layout.OffsetY
        if ($oy -ne 0) { $G.TranslateTransform(0, $oy) }
        try { Render-ChartOverlay -g $G -L $ent.Layout }
        catch { Write-WidgetLog "Chart overlay failed: $($_.Exception.Message)" "WARN" }
        finally { if ($oy -ne 0) { $G.ResetTransform() } }
    }
}

# ==============================================================================
# Part 4: Cohesive Multi-View GUI + Theme & Tooltip Support
# ==============================================================================
$script:DropArrow = [string][char]0x25BC
$script:SuppressSearchEvent = $false
$script:SuppressWlSearchEvent = $false

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.InitialDelay = 400
$toolTip.ReshowDelay = 150

# ------------------------------------------------------------------------------
# Hover explanations (v4.0). Static controls are registered with Set-Tip (text
# + optional glossary key) so a change of the tooltip mode can rebuild them;
# dialogs and tooltips that change all the time use Set-DynTip.
# ------------------------------------------------------------------------------
$script:TipReg = @{}

function Get-TipModeNow { return [string]$script:Config.TooltipMode }

function Set-Tip {
    param([System.Windows.Forms.Control]$Ctl, [string]$Text, [string]$Key = "")
    if ($null -eq $Ctl) { return }
    $script:TipReg[$Ctl] = @{ Text = $Text; Key = $Key }
    $toolTip.SetToolTip($Ctl, (Get-TooltipText -Text $Text -Key $Key -Mode (Get-TipModeNow)))
}

function Set-DynTip {
    param([System.Windows.Forms.Control]$Ctl, [string]$Text, [string]$Key = "")
    if ($null -eq $Ctl -or $Ctl.IsDisposed) { return }
    $toolTip.SetToolTip($Ctl, (Get-TooltipText -Text $Text -Key $Key -Mode (Get-TipModeNow)))
}

function Get-GlossaryShort {
    param([string]$Key, [string]$Prefix = "")
    $g = Get-GlossaryEntry $Key
    if ($null -eq $g) { return $Prefix }
    $txt = if ((Get-TipModeNow) -eq "Long") { $g.Long } else { $g.Short }
    if ($Prefix) { return ($Prefix + "`r`n" + $txt) }
    return ($g.Term + ": " + $txt)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = $script:AppTitle
$form.BackColor = $script:Pal.BodyBg
$form.ForeColor = $script:Pal.Text
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
$form.MaximizeBox = $true
$form.KeyPreview = $true
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual

function Apply-DwmTitlebarTheme {
    if ($form.IsHandleCreated) {
        try {
            $darkMode = [int]$script:Pal.DwmDark
            [void][Win32WidgetHelperV26]::DwmSetWindowAttribute($form.Handle, 20, [ref]$darkMode, 4)
            $captionColor = [int]$script:Pal.DwmCap
            [void][Win32WidgetHelperV26]::DwmSetWindowAttribute($form.Handle, 35, [ref]$captionColor, 4)
            $borderColor = [int]$script:Pal.DwmBdr
            [void][Win32WidgetHelperV26]::DwmSetWindowAttribute($form.Handle, 34, [ref]$borderColor, 4)
        } catch { }
    }
}

$form.Add_HandleCreated({ Apply-DwmTitlebarTheme })

$gInit = $form.CreateGraphics()
$script:DpiScale = [math]::Max(1.0, ($gInit.DpiX / 96.0))
$gInit.Dispose()

$virtBounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$initX = [int]$script:Config.WindowX
$initY = [int]$script:Config.WindowY
if ($initX -lt $virtBounds.Left -or $initX -gt ($virtBounds.Right - 200)) { $initX = 80 }
if ($initY -lt $virtBounds.Top  -or $initY -gt ($virtBounds.Bottom - 120)) { $initY = 80 }
$form.Location = New-Object System.Drawing.Point($initX, $initY)

function Style-FlatButton {
    param(
        [System.Windows.Forms.Button]$Btn,
        [System.Drawing.Color]$BgColor,
        [System.Drawing.Color]$FgColor,
        [System.Drawing.Color]$BorderColor
    )
    $Btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Btn.FlatAppearance.BorderSize = 1
    $Btn.FlatAppearance.BorderColor = $BorderColor
    $Btn.FlatAppearance.MouseOverBackColor = $script:Pal.Hover
    $Btn.BackColor = $BgColor
    $Btn.ForeColor = $FgColor
    $Btn.UseMnemonic = $false
    $Btn.Cursor = [System.Windows.Forms.Cursors]::Hand
}

$form.ClientSize = New-Object System.Drawing.Size((S 780), (S 560))
# The design size is the minimum; the window can only grow from there
$script:MinFormSize = $form.Size
$form.MinimumSize = $script:MinFormSize
$form.TopMost = [bool]$script:Config.TopMost

# System Tray Icon
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = [System.Drawing.SystemIcons]::Application
$trayIcon.Text = "Terminal Widget v$($script:AppVersion)"
$trayIcon.Visible = $true

$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miShow    = $trayMenu.Items.Add("Anzeigen / Wiederherstellen")
$miLayout  = New-Object System.Windows.Forms.ToolStripMenuItem("Layout")
foreach ($ln in @("Ticker", "Compact", "Standard", "Terminal")) {
    $tmi = New-Object System.Windows.Forms.ToolStripMenuItem($ln)
    $tmi.Tag = $ln
    $tmi.Add_Click({
        param($sender, $e)
        $form.Show()
        Apply-Layout ([string]$sender.Tag)
    })
    [void]$miLayout.DropDownItems.Add($tmi)
}
[void]$trayMenu.Items.Add($miLayout)
$miRefresh = $trayMenu.Items.Add("Jetzt aktualisieren (F5)")
[void]$trayMenu.Items.Add("-")
$miExit    = $trayMenu.Items.Add("Beenden")
$trayIcon.ContextMenuStrip = $trayMenu

function Style-DataGrid {
    param([System.Windows.Forms.DataGridView]$Grid)
    $Grid.BackgroundColor = $script:Pal.Card
    $Grid.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $Grid.GridColor = $script:Pal.Border
    $Grid.RowHeadersVisible = $false
    $Grid.AllowUserToAddRows = $false
    $Grid.AllowUserToDeleteRows = $false
    $Grid.AllowUserToResizeRows = $false
    $Grid.ReadOnly = $true
    $Grid.MultiSelect = $false
    $Grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $Grid.EnableHeadersVisualStyles = $false
    $Grid.ColumnHeadersBorderStyle = [System.Windows.Forms.DataGridViewHeaderBorderStyle]::Single
    $Grid.ColumnHeadersHeight = S 26
    $Grid.RowTemplate.Height = S 25

    $hdrStyle = New-Object System.Windows.Forms.DataGridViewCellStyle
    $hdrStyle.BackColor = $script:Pal.Input
    $hdrStyle.ForeColor = $script:Pal.Accent
    $hdrStyle.Font = $fontUiBold
    $Grid.ColumnHeadersDefaultCellStyle = $hdrStyle

    $cellStyle = New-Object System.Windows.Forms.DataGridViewCellStyle
    $cellStyle.BackColor = $script:Pal.Card
    $cellStyle.ForeColor = $script:Pal.Text
    $cellStyle.SelectionBackColor = $script:Pal.Hover
    $cellStyle.SelectionForeColor = $script:Pal.Text
    $cellStyle.Font = $fontMono
    $Grid.DefaultCellStyle = $cellStyle
}

# ==============================================================================
# ROW 1: DISTINCT FULL-WIDTH TOP HEADER
# ==============================================================================
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Location = New-Object System.Drawing.Point(0, 0)
$pnlHeader.Size = New-Object System.Drawing.Size((S 780), (S 48))
$pnlHeader.BackColor = $script:Pal.HeaderBg
$pnlHeader.Add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen($script:Pal.Border, 1)
    if ([string]$script:Config.Layout -eq "Ticker") {
        # borderless strip (v4.0): frame it so it stands out from the desktop
        $pen.Color = $script:Pal.Accent
        $e.Graphics.DrawRectangle($pen, 0, 0, ($sender.Width - 1), ($sender.Height - 1))
    } else {
        $e.Graphics.DrawLine($pen, 0, ($sender.Height - 1), $sender.Width, ($sender.Height - 1))
    }
    $pen.Dispose()
})
# Drag the borderless-feeling window by its header (also via the header labels)
$script:HeaderDragHandler = {
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        [void][Win32WidgetHelperV26]::ReleaseCapture()
        [void][Win32WidgetHelperV26]::SendMessage($form.Handle, 0xA1, 0x2, 0)
    }
}
$pnlHeader.Add_MouseDown($script:HeaderDragHandler)
$form.Controls.Add($pnlHeader)

# Primary Ticker Selector Dropdown
$pnlTickerBox = New-Object System.Windows.Forms.Panel
$pnlTickerBox.Location = New-Object System.Drawing.Point((S 12), (S 10))
$pnlTickerBox.Size = New-Object System.Drawing.Size((S 142), (S 28))
$pnlTickerBox.BackColor = $script:Pal.Input
$pnlTickerBox.Add_Paint({
    param($sender, $e)
    $pen = New-Object System.Drawing.Pen($script:Pal.Accent, 1)
    $e.Graphics.DrawRectangle($pen, 0, 0, ($sender.Width - 1), ($sender.Height - 1))
    $pen.Dispose()
})
$pnlHeader.Controls.Add($pnlTickerBox)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point((S 8), (S 5))
$txtSearch.Size = New-Object System.Drawing.Size((S 104), (S 18))
$txtSearch.BackColor = $script:Pal.Input
$txtSearch.ForeColor = $script:Pal.Accent
$txtSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$txtSearch.Font = $fontTicker
$txtSearch.Text = $script:Config.ActiveTicker
$pnlTickerBox.Controls.Add($txtSearch)
Set-Tip $txtSearch "Ticker eingeben oder aus Watchlist wählen (Pfeil Links/Rechts blättert)"

$btnTickerDrop = New-Object System.Windows.Forms.Button
$btnTickerDrop.Location = New-Object System.Drawing.Point((S 115), (S 1))
$btnTickerDrop.Size = New-Object System.Drawing.Size((S 26), (S 26))
$btnTickerDrop.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnTickerDrop.FlatAppearance.BorderSize = 0
$btnTickerDrop.BackColor = $script:Pal.Input
$btnTickerDrop.ForeColor = $script:Pal.Accent
$btnTickerDrop.Font = $fontUiBold
$btnTickerDrop.Text = $script:DropArrow
$btnTickerDrop.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlTickerBox.Controls.Add($btnTickerDrop)

# Live Price (+ extended-hours quote below) & Day Change (+ absolute below)
$lblLivePrice = New-Object System.Windows.Forms.Label
$lblLivePrice.Location = New-Object System.Drawing.Point((S 162), (S 3))
$lblLivePrice.Size = New-Object System.Drawing.Size((S 138), (S 24))
$lblLivePrice.Font = $fontPrice
$lblLivePrice.ForeColor = $script:Pal.Text
$lblLivePrice.Text = "--.-- $($script:Config.Currency)"
$pnlHeader.Controls.Add($lblLivePrice)
Set-Tip $lblLivePrice "Doppelklick = Kurs kopieren" "PRICE"

$lblExtQuote = New-Object System.Windows.Forms.Label
$lblExtQuote.Location = New-Object System.Drawing.Point((S 164), (S 28))
$lblExtQuote.Size = New-Object System.Drawing.Size((S 138), (S 16))
$lblExtQuote.Font = $fontAxis
$lblExtQuote.ForeColor = $script:Pal.Muted
$lblExtQuote.AutoEllipsis = $true
$lblExtQuote.Text = ""
$pnlHeader.Controls.Add($lblExtQuote)

$lblDayChange = New-Object System.Windows.Forms.Label
$lblDayChange.Location = New-Object System.Drawing.Point((S 304), (S 7))
$lblDayChange.Size = New-Object System.Drawing.Size((S 82), (S 18))
$lblDayChange.Font = $fontMono
$lblDayChange.ForeColor = $colGreen
$lblDayChange.Text = "+0.00%"
$pnlHeader.Controls.Add($lblDayChange)
Set-Tip $lblDayChange "Tagesänderung in %" "DAYCHG"

$lblDayAbs = New-Object System.Windows.Forms.Label
$lblDayAbs.Location = New-Object System.Drawing.Point((S 304), (S 28))
$lblDayAbs.Size = New-Object System.Drawing.Size((S 82), (S 16))
$lblDayAbs.Font = $fontAxis
$lblDayAbs.ForeColor = $script:Pal.Muted
$lblDayAbs.Text = ""
$pnlHeader.Controls.Add($lblDayAbs)
Set-Tip $lblDayAbs "Absolute Tagesänderung in Anzeigewährung" "DAYCHG"

# Company Name + Market Status in Header (Sparkline in Compact Mode)
$lblHeaderName = New-Object System.Windows.Forms.Label
$lblHeaderName.Location = New-Object System.Drawing.Point((S 390), (S 7))
$lblHeaderName.Size = New-Object System.Drawing.Size((S 150), (S 17))
$lblHeaderName.Font = $fontUi
$lblHeaderName.ForeColor = $script:Pal.Muted
$lblHeaderName.AutoEllipsis = $true
$lblHeaderName.Text = ""
$pnlHeader.Controls.Add($lblHeaderName)

$lblMarketStatus = New-Object System.Windows.Forms.Label
$lblMarketStatus.Location = New-Object System.Drawing.Point((S 390), (S 26))
$lblMarketStatus.Size = New-Object System.Drawing.Size((S 150), (S 17))
$lblMarketStatus.Font = $fontUiBold
$lblMarketStatus.ForeColor = $script:Pal.Muted
$lblMarketStatus.AutoEllipsis = $true
$lblMarketStatus.Text = ""
$pnlHeader.Controls.Add($lblMarketStatus)

foreach ($dragLbl in @($lblExtQuote, $lblDayChange, $lblDayAbs, $lblHeaderName, $lblMarketStatus)) {
    $dragLbl.Add_MouseDown($script:HeaderDragHandler)
}

$picCompactSpark = New-Object System.Windows.Forms.PictureBox
$picCompactSpark.Location = New-Object System.Drawing.Point((S 390), (S 11))
$picCompactSpark.Size = New-Object System.Drawing.Size((S 74), (S 26))
$picCompactSpark.BackColor = $script:Pal.BodyBg
$picCompactSpark.Visible = $false
$pnlHeader.Controls.Add($picCompactSpark)
Set-Tip $picCompactSpark "" "SPARK"

# ------------------------------------------------------------------------------
# Compact-mode ticker tape (v2.8): watchlist + portfolio scroll below the bar.
# Rendered once into a bitmap per data change; the 30 ms timer only moves it.
# Hover = pause, click = switch to that ticker.
# ------------------------------------------------------------------------------
$pnlTape = New-Object System.Windows.Forms.Panel
$pnlTape.Location = New-Object System.Drawing.Point(0, (S 48))
$pnlTape.Size = New-Object System.Drawing.Size((S 698), (S 22))
$pnlTape.BackColor = $script:Pal.HeaderBg
$pnlTape.Visible = $false
$pnlTape.Cursor = [System.Windows.Forms.Cursors]::Hand
Enable-DoubleBuffering -Control $pnlTape
$form.Controls.Add($pnlTape)
Set-Tip $pnlTape "Klick = Ticker im Chart öffnen | Maus darüber = anhalten"

$script:TapeBitmap    = $null
$script:TapeItems     = @()
$script:TapeOffset    = 0.0
$script:TapeHover     = $false
$script:TapeSignature = ""

function Update-TickerTape {
    if (-not $pnlTape.Visible) { return }
    $p = $script:Pal
    $curr = $script:Config.Currency
    $syms = New-Object System.Collections.Generic.List[string]
    foreach ($w in $script:Config.Watchlist) { $u = ([string]$w).ToUpper(); if (-not $syms.Contains($u)) { $syms.Add($u) } }
    foreach ($k in $script:Portfolio.Keys) { $u = ([string]$k).ToUpper(); if (-not $syms.Contains($u)) { $syms.Add($u) } }

    $segs = New-Object System.Collections.Generic.List[PSObject]
    $sig = "{0}|{1}|{2}" -f $script:Config.Theme, $script:Config.AccentColor, $curr
    foreach ($sym in $syms) {
        if (-not $script:QuoteStore.ContainsKey($sym)) { continue }
        $q = $script:QuoteStore[$sym]
        $px = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $curr
        $pct = [double]$q.ChangePct
        $segs.Add([PSCustomObject]@{ Sym = $sym; Price = ("{0:N2}" -f $px); Pct = ("{0}{1:N2}%" -f $(if ($pct -ge 0) { "+" } else { "" }), $pct); Up = ($pct -ge 0) })
        $sig += "|{0}:{1:N2}:{2:N2}" -f $sym, $px, $pct
    }
    if ($sig -eq $script:TapeSignature -and $null -ne $script:TapeBitmap) { return }
    $script:TapeSignature = $sig

    $old = $script:TapeBitmap
    $script:TapeBitmap = $null
    $script:TapeItems = @()
    if ($null -ne $old) { $old.Dispose() }
    if ($segs.Count -eq 0) { $pnlTape.Invalidate(); return }

    $flags = [System.Windows.Forms.TextFormatFlags]::NoPadding -bor [System.Windows.Forms.TextFormatFlags]::SingleLine
    $gap  = S 6
    $sepW = S 26
    $h = [math]::Max(1, $pnlTape.ClientSize.Height)
    $total = 0
    foreach ($sg in $segs) {
        $sg | Add-Member -NotePropertyName W1 -NotePropertyValue ([System.Windows.Forms.TextRenderer]::MeasureText($sg.Sym, $fontUiBold, [System.Drawing.Size]::Empty, $flags).Width) -Force
        $sg | Add-Member -NotePropertyName W2 -NotePropertyValue ([System.Windows.Forms.TextRenderer]::MeasureText($sg.Price, $fontMono, [System.Drawing.Size]::Empty, $flags).Width) -Force
        $sg | Add-Member -NotePropertyName W3 -NotePropertyValue ([System.Windows.Forms.TextRenderer]::MeasureText($sg.Pct, $fontMono, [System.Drawing.Size]::Empty, $flags).Width) -Force
        $total += $sg.W1 + $gap + $sg.W2 + $gap + $sg.W3 + $sepW
    }
    $bmp = New-Object System.Drawing.Bitmap([int]$total, [int]$h, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $items = New-Object System.Collections.Generic.List[PSObject]
    try {
        $g.Clear($p.HeaderBg)
        $x = 0
        $dotBr = New-Object System.Drawing.SolidBrush($p.Border)
        foreach ($sg in $segs) {
            $x0 = $x
            $yS = [int](($h - [System.Windows.Forms.TextRenderer]::MeasureText($sg.Sym, $fontUiBold, [System.Drawing.Size]::Empty, $flags).Height) / 2)
            $yM = [int](($h - [System.Windows.Forms.TextRenderer]::MeasureText($sg.Price, $fontMono, [System.Drawing.Size]::Empty, $flags).Height) / 2)
            [System.Windows.Forms.TextRenderer]::DrawText($g, $sg.Sym, $fontUiBold, (New-Object System.Drawing.Point($x, $yS)), $p.Accent, $flags)
            $x += $sg.W1 + $gap
            [System.Windows.Forms.TextRenderer]::DrawText($g, $sg.Price, $fontMono, (New-Object System.Drawing.Point($x, $yM)), $p.Text, $flags)
            $x += $sg.W2 + $gap
            [System.Windows.Forms.TextRenderer]::DrawText($g, $sg.Pct, $fontMono, (New-Object System.Drawing.Point($x, $yM)), $(if ($sg.Up) { $colGreen } else { $colRed }), $flags)
            $x += $sg.W3
            $d = [float](S 2)
            $g.FillEllipse($dotBr, [float]($x + ($sepW / 2.0) - $d), [float](($h / 2.0) - $d), (2 * $d), (2 * $d))
            $x += $sepW
            $items.Add([PSCustomObject]@{ Sym = $sg.Sym; X0 = $x0; X1 = $x })
        }
        $dotBr.Dispose()
    } finally {
        $g.Dispose()
    }
    $script:TapeBitmap = $bmp
    $script:TapeItems = $items.ToArray()
    if ($script:TapeOffset -ge $bmp.Width) { $script:TapeOffset = 0.0 }
    $pnlTape.Invalidate()
}

$pnlTape.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.Clear($script:Pal.HeaderBg)
    $bmp = $script:TapeBitmap
    $pw = $sender.ClientSize.Width
    if ($null -eq $bmp) {
        [System.Windows.Forms.TextRenderer]::DrawText($g, "Kurse werden geladen...", $fontUi, (New-Object System.Drawing.Point((S 8), (S 3))), $script:Pal.Muted)
    } elseif ($bmp.Width -le $pw) {
        $g.DrawImageUnscaled($bmp, 0, 0)          # everything fits: no scrolling
    } else {
        $x = -[int]$script:TapeOffset
        while ($x -lt $pw) { $g.DrawImageUnscaled($bmp, $x, 0); $x += $bmp.Width }
    }
    $g.DrawLine($script:GdiCache["sepPen"], 0, 0, $pw, 0)
})
$pnlTape.Add_MouseEnter({ $script:TapeHover = $true })
$pnlTape.Add_MouseLeave({ $script:TapeHover = $false })
$pnlTape.Add_MouseClick({
    param($sender, $e)
    $bmp = $script:TapeBitmap
    if ($null -eq $bmp -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $xx = if ($bmp.Width -le $sender.ClientSize.Width) { $e.X } else { ($e.X + [int]$script:TapeOffset) % $bmp.Width }
    foreach ($it in $script:TapeItems) {
        if ($xx -ge $it.X0 -and $xx -lt $it.X1) {
            if ($it.Sym -ne $script:Config.ActiveTicker.ToUpper()) { Switch-ActiveTicker -NewTicker $it.Sym -SkipResolve $true }
            break
        }
    }
})

$tapeTimer = New-Object System.Windows.Forms.Timer
$tapeTimer.Interval = 30
$tapeTimer.Add_Tick({
    $bmp = $script:TapeBitmap
    if ($script:TapeHover -or $null -eq $bmp -or -not $pnlTape.Visible -or -not $form.Visible) { return }
    if ($bmp.Width -le $pnlTape.ClientSize.Width) { return }
    $script:TapeOffset = ($script:TapeOffset + $script:DpiScale) % $bmp.Width
    $pnlTape.Invalidate()
})

function Update-TapeTimer {
    $run = [bool]$script:Config.CompactMode -and [bool]$script:Config.CompactTape -and -not $script:IsClosing
    if ($run -and -not $tapeTimer.Enabled) { $tapeTimer.Start() }
    elseif (-not $run -and $tapeTimer.Enabled) { $tapeTimer.Stop() }
}

$picCompactSpark.Add_Paint({
    param($sender, $e)
    $sym = $script:Config.ActiveTicker.ToUpper()
    if ($script:SparklineStore.ContainsKey($sym)) {
        Draw-MiniSparkline -g $e.Graphics -Rect $sender.ClientRectangle -Values $script:SparklineStore[$sym]
    }
})

# Right-Aligned Header Controls
$btnCurrency = New-Object System.Windows.Forms.Button
$btnCurrency.Location = New-Object System.Drawing.Point((S 544), (S 11))
$btnCurrency.Size = New-Object System.Drawing.Size((S 62), (S 26))
Style-FlatButton -Btn $btnCurrency -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Accent
$btnCurrency.Font = $fontUiBold
$btnCurrency.Text = "$($script:Config.Currency) $script:DropArrow"
$pnlHeader.Controls.Add($btnCurrency)
Set-Tip $btnCurrency "Anzeigewährung wechseln (Taste W)" "FX"

$btnPin = New-Object System.Windows.Forms.Button
$btnPin.Location = New-Object System.Drawing.Point((S 612), (S 11))
$btnPin.Size = New-Object System.Drawing.Size((S 44), (S 26))
$btnPin.Font = $fontUiBold
$btnPin.Text = "Pin"
$pnlHeader.Controls.Add($btnPin)
Set-Tip $btnPin "Immer im Vordergrund (Always on Top)" "PIN"

$btnCompact = New-Object System.Windows.Forms.Button
$btnCompact.Location = New-Object System.Drawing.Point((S 662), (S 11))
$btnCompact.Size = New-Object System.Drawing.Size((S 74), (S 26))
Style-FlatButton -Btn $btnCompact -BgColor $script:Pal.Input -FgColor $script:Pal.Text -BorderColor $script:Pal.Border
$btnCompact.Font = $fontUi
$btnCompact.Text = "Standard $script:DropArrow"
$pnlHeader.Controls.Add($btnCompact)

# v4.0: the former "Compact" button opens the layout menu
$layoutMenu = New-Object System.Windows.Forms.ContextMenuStrip
foreach ($ln in (Get-LayoutNames)) {
    $lmi = New-Object System.Windows.Forms.ToolStripMenuItem($ln)
    $lmi.Tag = "Layout:$ln"
    [void]$layoutMenu.Items.Add($lmi)
}
[void]$layoutMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$lmiWatch = New-Object System.Windows.Forms.ToolStripMenuItem("Terminal: Watchlist & Alarme")
$lmiWatch.Tag = "Opt:Watch"
[void]$layoutMenu.Items.Add($lmiWatch)
$lmiPort = New-Object System.Windows.Forms.ToolStripMenuItem("Terminal: Portfolio")
$lmiPort.Tag = "Opt:Portfolio"
[void]$layoutMenu.Items.Add($lmiPort)
Set-Tip $btnCompact "Layout wählen: Ticker / Compact / Standard / Terminal (L = nächstes, C = Compact)" "LAYOUT"

$btnTray = New-Object System.Windows.Forms.Button
$btnTray.Location = New-Object System.Drawing.Point((S 742), (S 11))
$btnTray.Size = New-Object System.Drawing.Size((S 26), (S 26))
Style-FlatButton -Btn $btnTray -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnTray.Font = $fontUiBold
$btnTray.Text = "_"
$pnlHeader.Controls.Add($btnTray)
Set-Tip $btnTray "In den System Tray minimieren"

# Currency Dropdown Popup
$lstCurrencyDropdown = New-Object System.Windows.Forms.ListBox
$lstCurrencyDropdown.Location = New-Object System.Drawing.Point((S 544), (S 40))
$lstCurrencyDropdown.Size = New-Object System.Drawing.Size((S 62), (S 66))
$lstCurrencyDropdown.BackColor = $script:Pal.Input
$lstCurrencyDropdown.ForeColor = $script:Pal.Text
$lstCurrencyDropdown.Font = $fontUiBold
$lstCurrencyDropdown.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$lstCurrencyDropdown.ItemHeight = S 20
$lstCurrencyDropdown.Visible = $false
foreach ($dc in (Get-DisplayCurrencies)) { [void]$lstCurrencyDropdown.Items.Add($dc) }
$lstCurrencyDropdown.Height = ($lstCurrencyDropdown.Items.Count * (S 20)) + (S 6)
$form.Controls.Add($lstCurrencyDropdown)
$lstCurrencyDropdown.BringToFront()

# Ticker Dropdown Popup
$lstTickerDropdown = New-Object System.Windows.Forms.ListBox
$lstTickerDropdown.Location = New-Object System.Drawing.Point((S 12), (S 40))
$lstTickerDropdown.Size = New-Object System.Drawing.Size((S 388), (S 185))
$lstTickerDropdown.BackColor = $script:Pal.Card
$lstTickerDropdown.ForeColor = $script:Pal.Text
$lstTickerDropdown.Font = $fontMono
$lstTickerDropdown.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$lstTickerDropdown.ItemHeight = S 20
$lstTickerDropdown.Visible = $false
$form.Controls.Add($lstTickerDropdown)
$lstTickerDropdown.BringToFront()

# ==============================================================================
# ROW 2: NAVIGATION BAR (3 Tabs + Refresh Controls + Theme Cycle + FX Status)
# ==============================================================================
$pnlNav = New-Object System.Windows.Forms.Panel
$pnlNav.Location = New-Object System.Drawing.Point((S 12), (S 56))
$pnlNav.Size = New-Object System.Drawing.Size((S 756), (S 32))
$pnlNav.BackColor = $script:Pal.BodyBg
$form.Controls.Add($pnlNav)

$tabButtons = @{}
$tabDefs = @(
    @{ Key = "Chart";     Label = "Chart (F1)";         W = 88  },
    @{ Key = "Portfolio"; Label = "Portfolio (F2)";     W = 104 },
    @{ Key = "Watchlist"; Label = "Watch & Alarm (F3)"; W = 138 }
)
$tabX = 0
foreach ($td in $tabDefs) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($tabX, (S 2))
    $b.Size = New-Object System.Drawing.Size((S $td.W), (S 27))
    Style-FlatButton -Btn $b -BgColor $script:Pal.Card -FgColor $script:Pal.Text -BorderColor $script:Pal.Border
    $b.Font = $fontUiBold
    $b.Text = $td.Label
    $b.Tag = $td.Key
    $pnlNav.Controls.Add($b)
    $tabButtons[$td.Key] = $b
    $tabX += (S ($td.W + 5))
}

$btnRefreshNow = New-Object System.Windows.Forms.Button
$btnRefreshNow.Location = New-Object System.Drawing.Point((S 346), (S 2))
$btnRefreshNow.Size = New-Object System.Drawing.Size((S 30), (S 27))
Style-FlatButton -Btn $btnRefreshNow -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnRefreshNow.Font = $fontUiBold
$btnRefreshNow.Text = [string][char]0x21BB
$pnlNav.Controls.Add($btnRefreshNow)
Set-Tip $btnRefreshNow "Marktdaten jetzt aktualisieren (F5)" "REFRESH"

$cmbRefresh = New-Object System.Windows.Forms.ComboBox
$cmbRefresh.Location = New-Object System.Drawing.Point((S 380), (S 4))
$cmbRefresh.Size = New-Object System.Drawing.Size((S 58), (S 24))
$cmbRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbRefresh.BackColor = $script:Pal.Input
$cmbRefresh.ForeColor = $script:Pal.Muted
$cmbRefresh.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbRefresh.Font = $fontMono
[void]$cmbRefresh.Items.Add("10s")
[void]$cmbRefresh.Items.Add("15s")
[void]$cmbRefresh.Items.Add("30s")
[void]$cmbRefresh.Items.Add("60s")
$curRefStr = "$($script:Config.RefreshSeconds)s"
if ($cmbRefresh.Items.IndexOf($curRefStr) -lt 0) { [void]$cmbRefresh.Items.Add($curRefStr) }   # custom value from the settings dialog
$refIdx = $cmbRefresh.Items.IndexOf($curRefStr)
$cmbRefresh.SelectedIndex = if ($refIdx -ge 0) { $refIdx } else { 1 }
$pnlNav.Controls.Add($cmbRefresh)
Set-Tip $cmbRefresh "Auto-Refresh Intervall" "REFRESH"

$btnThemeCycle = New-Object System.Windows.Forms.Button
$btnThemeCycle.Location = New-Object System.Drawing.Point((S 442), (S 2))
$btnThemeCycle.Size = New-Object System.Drawing.Size((S 54), (S 27))
Style-FlatButton -Btn $btnThemeCycle -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnThemeCycle.Font = $fontUi
$btnThemeCycle.Text = $script:Config.Theme
$pnlNav.Controls.Add($btnThemeCycle)
Set-Tip $btnThemeCycle "Theme wechseln: Dark / OLED / Light / Terminal (Taste T)" "THEME"

$btnSettings = New-Object System.Windows.Forms.Button
$btnSettings.Location = New-Object System.Drawing.Point((S 500), (S 2))
$btnSettings.Size = New-Object System.Drawing.Size((S 30), (S 27))
Style-FlatButton -Btn $btnSettings -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnSettings.Font = $fontUiBold
$btnSettings.Text = [string][char]0x2699
$pnlNav.Controls.Add($btnSettings)
Set-Tip $btnSettings "Einstellungen (Taste S)"

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point((S 534), (S 6))
$lblStatus.Size = New-Object System.Drawing.Size((S 222), (S 20))
$lblStatus.Font = $fontMono
$lblStatus.ForeColor = $script:Pal.Muted
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblStatus.AutoEllipsis = $true
$lblStatus.Text = "USD 1.0950 | CHF 0.9400"
$pnlNav.Controls.Add($lblStatus)
Set-Tip $lblStatus "Wechselkurse und Stand der letzten Aktualisierung" "STAND"

# ==============================================================================
# VIEW 1: CHART VIEW
# ==============================================================================
$viewChart = New-Object System.Windows.Forms.Panel
$viewChart.Location = New-Object System.Drawing.Point((S 12), (S 92))
$viewChart.Size = New-Object System.Drawing.Size((S 756), (S 456))
$viewChart.BackColor = $script:Pal.BodyBg
$form.Controls.Add($viewChart)

$pnlChartCanvas = New-Object System.Windows.Forms.Panel
$pnlChartCanvas.Location = New-Object System.Drawing.Point(0, 0)
$pnlChartCanvas.Size = New-Object System.Drawing.Size((S 756), (S 420))
$pnlChartCanvas.BackColor = $script:Pal.BodyBg
Enable-DoubleBuffering -Control $pnlChartCanvas
$viewChart.Controls.Add($pnlChartCanvas)

$chartContextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$cmiCopyPrice = $chartContextMenu.Items.Add("Aktuellen Kurs kopieren")
$cmiAddWatch  = $chartContextMenu.Items.Add("Aktiven Ticker zur Watchlist hinzufügen")
$cmiExportCsv = $chartContextMenu.Items.Add("Chartdaten als CSV exportieren")
$cmiFullscreen = $chartContextMenu.Items.Add("Chart im Vollbild (F11)")
[void]$chartContextMenu.Items.Add("-")
$cmiCompare    = $chartContextMenu.Items.Add("Vergleichen mit ... (X)")
$cmiCompareOff = $chartContextMenu.Items.Add("Vergleich entfernen")
$cmiZoomReset  = $chartContextMenu.Items.Add("Zoom zurücksetzen (Z)")
$cmiLevels     = New-Object System.Windows.Forms.ToolStripMenuItem("EK- und Alarmlinien anzeigen")
$cmiLevels.CheckOnClick = $true
$cmiLevels.Checked = [bool]$script:Config.ShowLevels
[void]$chartContextMenu.Items.Add($cmiLevels)
# "Alarm here" goes on top; its text is set when the menu opens
$cmiAlertHere = New-Object System.Windows.Forms.ToolStripMenuItem("Alarm hier setzen")
$chartContextMenu.Items.Insert(0, $cmiAlertHere)
$chartContextMenu.Items.Insert(1, (New-Object System.Windows.Forms.ToolStripSeparator))
$script:CtxPrice = [double]::NaN
$pnlChartCanvas.ContextMenuStrip = $chartContextMenu

$pnlChartControls = New-Object System.Windows.Forms.Panel
$pnlChartControls.Location = New-Object System.Drawing.Point(0, (S 422))
$pnlChartControls.Size = New-Object System.Drawing.Size((S 756), (S 34))
$pnlChartControls.BackColor = $script:Pal.BodyBg
$viewChart.Controls.Add($pnlChartControls)

$tfButtons = @{}
$tfList   = @("1d", "5d", "1mo", "3mo", "6mo", "1y")
$tfLabels = @("1D", "5D", "1M", "3M", "6M", "1Y")
for ($t = 0; $t -lt $tfList.Count; $t++) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Location = New-Object System.Drawing.Point((S ($t * 36)), (S 4))
    $btn.Size = New-Object System.Drawing.Size((S 33), (S 25))
    Style-FlatButton -Btn $btn -BgColor $script:Pal.Card -FgColor $script:Pal.Text -BorderColor $script:Pal.Border
    $btn.Font = $fontUiBold
    $btn.Text = $tfLabels[$t]
    $btn.Tag = $tfList[$t]
    $pnlChartControls.Controls.Add($btn)
    $tfButtons[$tfList[$t]] = $btn
    Set-Tip $btn ("Zeitraum {0} (Taste {1})" -f $tfLabels[$t], ($t + 1)) "TF"
}

$btnChartType = New-Object System.Windows.Forms.Button
$btnChartType.Location = New-Object System.Drawing.Point((S 222), (S 4))
$btnChartType.Size = New-Object System.Drawing.Size((S 70), (S 25))
$btnChartType.Font = $fontUiBold
$btnChartType.Text = "Kerzen"
$pnlChartControls.Controls.Add($btnChartType)
Set-Tip $btnChartType "Linien- / Kerzenchart umschalten (Taste K)" "CANDLE"

$btnToggleVol = New-Object System.Windows.Forms.Button
$btnToggleVol.Location = New-Object System.Drawing.Point((S 296), (S 4))
$btnToggleVol.Size = New-Object System.Drawing.Size((S 50), (S 25))
$btnToggleVol.Font = $fontUiBold
$btnToggleVol.Text = "Volumen"
$pnlChartControls.Controls.Add($btnToggleVol)
Set-Tip $btnToggleVol "Volumen-Histogramm ein-/ausblenden (Taste V)" "VOL"

$btnToggleSma = New-Object System.Windows.Forms.Button
$btnToggleSma.Location = New-Object System.Drawing.Point((S 350), (S 4))
$btnToggleSma.Size = New-Object System.Drawing.Size((S 58), (S 25))
$btnToggleSma.Font = $fontUiBold
$btnToggleSma.Text = "SMA"
$pnlChartControls.Controls.Add($btnToggleSma)
Set-Tip $btnToggleSma "Gleitende Durchschnitte SMA $($script:Config.SmaFastPeriod)/$($script:Config.SmaSlowPeriod) (Taste M)" "SMA"

$btnToggleVwap = New-Object System.Windows.Forms.Button
$btnToggleVwap.Location = New-Object System.Drawing.Point((S 412), (S 4))
$btnToggleVwap.Size = New-Object System.Drawing.Size((S 62), (S 25))
$btnToggleVwap.Font = $fontUiBold
$btnToggleVwap.Text = "VWAP"
$pnlChartControls.Controls.Add($btnToggleVwap)
Set-Tip $btnToggleVwap "Intraday VWAP Benchmark ein-/ausblenden (Taste A)" "VWAP"

$btnToggleBb = New-Object System.Windows.Forms.Button
$btnToggleBb.Location = New-Object System.Drawing.Point((S 478), (S 4))
$btnToggleBb.Size = New-Object System.Drawing.Size((S 46), (S 25))
$btnToggleBb.Font = $fontUiBold
$btnToggleBb.Text = "BB"
$pnlChartControls.Controls.Add($btnToggleBb)
Set-Tip $btnToggleBb "Bollinger Bänder ein-/ausblenden (Taste B)" "BB"

$btnToggleRsi = New-Object System.Windows.Forms.Button
$btnToggleRsi.Location = New-Object System.Drawing.Point((S 528), (S 4))
$btnToggleRsi.Size = New-Object System.Drawing.Size((S 70), (S 25))
$btnToggleRsi.Font = $fontUiBold
$btnToggleRsi.Text = "RSI-$($script:Config.RsiPeriod)"
$pnlChartControls.Controls.Add($btnToggleRsi)
Set-Tip $btnToggleRsi "Relative Strength Index Sub-Panel (Taste R)" "RSI"

$btnToggleExt = New-Object System.Windows.Forms.Button
$btnToggleExt.Location = New-Object System.Drawing.Point((S 602), (S 4))
$btnToggleExt.Size = New-Object System.Drawing.Size((S 62), (S 25))
$btnToggleExt.Font = $fontUiBold
$btnToggleExt.Text = "Ext"
$pnlChartControls.Controls.Add($btnToggleExt)
Set-Tip $btnToggleExt "Vor-/Nachbörse im 1D-Chart anzeigen (Taste E)" "EXT"

$btnExportCsv = New-Object System.Windows.Forms.Button
$btnExportCsv.Location = New-Object System.Drawing.Point((S 668), (S 4))
$btnExportCsv.Size = New-Object System.Drawing.Size((S 88), (S 25))
Style-FlatButton -Btn $btnExportCsv -BgColor $script:Pal.Card -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnExportCsv.Font = $fontUi
$btnExportCsv.Text = "CSV"
$pnlChartControls.Controls.Add($btnExportCsv)
Set-Tip $btnExportCsv "Aktuelle Chart-Zeitreihe als CSV speichern"

$btnFullscreen = New-Object System.Windows.Forms.Button
$btnFullscreen.Size = New-Object System.Drawing.Size((S 70), (S 25))
Style-FlatButton -Btn $btnFullscreen -BgColor $script:Pal.Card -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnFullscreen.Font = $fontUi
$btnFullscreen.Text = "Vollbild"
$pnlChartControls.Controls.Add($btnFullscreen)
Set-Tip $btnFullscreen "Chart im Vollbild (F11 oder Doppelklick auf den Chart)"


# Chart button bar: toggles sized to their text, CSV + Vollbild right-aligned
$script:ChartToggleButtons = @($btnChartType, $btnToggleVol, $btnToggleSma, $btnToggleVwap, $btnToggleBb, $btnToggleRsi, $btnToggleExt)
function Update-ChartControlsLayout {
    $bx = S 222
    foreach ($b in $script:ChartToggleButtons) {
        $bw = [System.Windows.Forms.TextRenderer]::MeasureText($b.Text, $b.Font).Width + (S 16)
        $b.SetBounds($bx, (S 4), $bw, (S 25))
        $bx += $bw + (S 4)
    }
    $fw = [System.Windows.Forms.TextRenderer]::MeasureText($btnFullscreen.Text, $btnFullscreen.Font).Width + (S 18)
    $btnFullscreen.SetBounds(($pnlChartControls.ClientSize.Width - $fw), (S 4), $fw, (S 25))
    $cw = [System.Windows.Forms.TextRenderer]::MeasureText($btnExportCsv.Text, $btnExportCsv.Font).Width + (S 18)
    $btnExportCsv.SetBounds(($btnFullscreen.Left - (S 4) - $cw), (S 4), $cw, (S 25))
}
Update-ChartControlsLayout

$pnlChartCanvas.Add_Paint({
    param($sender, $e)
    Paint-ChartCanvas -Canvas $sender -G $e.Graphics -Fullscreen $false
})

# Shared by the normal chart and the fullscreen chart (x-axis layout is identical)
function Get-HoverIndexAt {
    param($L, [int]$X)
    $pr = $L.PriceRect
    if ($L.N -lt 2 -or $X -lt $pr.Left -or $X -gt $pr.Right) { return -1 }
    $rel = ($X - $pr.Left) / [double]$pr.Width
    $idx = [int][math]::Round($rel * ($L.N - 1))
    return [math]::Max(0, [math]::Min($L.N - 1, $idx))
}

# v4.0: explanation when the mouse rests on a chart legend / badge / level tag
$script:LegendTipKey = ""
function Update-ChartLegendTip {
    param([System.Windows.Forms.Control]$Canvas, $L, [int]$X, [int]$Y)
    $mode = Get-TipModeNow
    if ($mode -eq "Off" -or $null -eq $L -or $null -eq $L.Legends) { return }
    $py = [float]($Y - [int]$L.OffsetY)
    $hit = $null
    foreach ($lg in @($L.Legends)) { if ($lg.R.Contains([float]$X, $py)) { $hit = $lg; break } }
    $id = if ($null -ne $hit) { "{0}|{1}|{2}" -f $hit.Key, [int]$hit.R.X, [int]$hit.R.Y } else { "" }
    if ($id -eq $script:LegendTipKey) { return }
    $script:LegendTipKey = $id
    if ($null -eq $hit) { $toolTip.Hide($Canvas); return }
    $txt = Get-TooltipText -Text "" -Key $hit.Key -Mode $mode
    if (-not $txt) { return }
    $dur = if ($mode -eq "Long") { 30000 } else { 10000 }
    $toolTip.Show($txt, $Canvas, [int]($X + (S 14)), [int]($Y + (S 18)), [int]$dur)
}

$script:ChartMouseMoveHandler = {
    param($sender, $e)
    # Hit-testing uses the geometry of the bitmap that is actually on screen
    $L = Get-CanvasLayout -Canvas $sender
    if ($null -eq $L) { return }
    Update-ChartLegendTip -Canvas $sender -L $L -X $e.X -Y $e.Y
    $idx = Get-HoverIndexAt -L $L -X $e.X
    $m = $script:Measure
    if ($m.Dragging -and $idx -ge 0) {
        if ([math]::Abs($e.X - $m.X0) -gt (S 4)) {
            $m.Active = $true
            $m.B = [int]$L.ViewStart + $idx
        }
    }
    if ($idx -ne $script:HoverIndex -or ($idx -ge 0 -and $e.Y -ne $script:HoverY)) {
        $script:HoverIndex = $idx
        $script:HoverY = $e.Y
        $sender.Invalidate()
    }
}
$script:ChartMouseDownHandler = {
    param($sender, $e)
    $L = Get-CanvasLayout -Canvas $sender
    if ($null -eq $L) { return }
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        # price under the mouse for "Alarm hier setzen"
        $my = $e.Y - [int]$L.OffsetY
        $pr = $L.PriceRect
        $script:CtxPrice = if ($my -ge $pr.Top -and $my -le $pr.Bottom -and $pr.Height -gt 0) {
            [double]$L.MinP + ((($pr.Bottom - $my) / [double]$pr.Height) * [double]$L.SpanP)
        } else { [double]::NaN }
        return
    }
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $idx = Get-HoverIndexAt -L $L -X $e.X
        $script:Measure = @{ Active = $false; Dragging = ($idx -ge 0); A = ([int]$L.ViewStart + $idx); B = ([int]$L.ViewStart + $idx); X0 = $e.X; Key = $script:ActiveSeriesKey }
        $sender.Invalidate()
    }
}
$script:ChartMouseUpHandler = {
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:Measure.Dragging = $false
        $sender.Invalidate()
    }
}
$script:ChartMouseLeaveHandler = {
    param($sender, $e)
    $script:HoverIndex = -1
    if ($script:LegendTipKey) { $script:LegendTipKey = ""; try { $toolTip.Hide($sender) } catch { } }
    $sender.Invalidate()
}
$script:ChartWheelHandler = {
    param($sender, $e)
    $mods = [System.Windows.Forms.Control]::ModifierKeys
    if (($mods -band [System.Windows.Forms.Keys]::Control) -eq [System.Windows.Forms.Keys]::Control) {
        Zoom-Chart -Canvas $sender -Delta $e.Delta -X $e.X
        return
    }
    if (($mods -band [System.Windows.Forms.Keys]::Shift) -eq [System.Windows.Forms.Keys]::Shift) {
        Pan-Chart -Dir $(if ($e.Delta -gt 0) { -1 } else { 1 })
        return
    }
    $curIdx = $tfList.IndexOf($script:Config.Timeframe)
    if ($curIdx -lt 0) { $curIdx = 0 }
    if ($e.Delta -gt 0 -and $curIdx -gt 0) {
        Set-Timeframe -Tf $tfList[$curIdx - 1]
    } elseif ($e.Delta -lt 0 -and $curIdx -lt ($tfList.Count - 1)) {
        Set-Timeframe -Tf $tfList[$curIdx + 1]
    }
}
$pnlChartCanvas.Add_MouseMove($script:ChartMouseMoveHandler)
$pnlChartCanvas.Add_MouseDown($script:ChartMouseDownHandler)
$pnlChartCanvas.Add_MouseUp($script:ChartMouseUpHandler)
$pnlChartCanvas.Add_MouseLeave($script:ChartMouseLeaveHandler)
$pnlChartCanvas.Add_MouseWheel($script:ChartWheelHandler)
$pnlChartCanvas.Add_DoubleClick({ Toggle-ChartFullscreen })
$btnFullscreen.Add_Click({ Toggle-ChartFullscreen })

function Set-Timeframe {
    param([string]$Tf)
    if ($tfList -notcontains $Tf) { return }
    $script:Config.Timeframe = $Tf
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Refresh-AllMarketData
    Update-AllUiViews
}

# ------------------------------------------------------------------------------
# Fullscreen chart window (borderless, covers the monitor the widget is on)
# ------------------------------------------------------------------------------
function Render-FullscreenChart {
    param([System.Drawing.Graphics]$g, [System.Drawing.Rectangle]$Bounds)
    $p = $script:Pal
    $stripH = S 40
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    # Header strip: reuses the texts/colours of the main window header
    $hdrBr = New-Object System.Drawing.SolidBrush($p.HeaderBg)
    $g.FillRectangle($hdrBr, 0, 0, $Bounds.Width, $stripH)
    $hdrBr.Dispose()
    $g.DrawLine($script:GdiCache["sepPen"], 0, ($stripH - 1), $Bounds.Width, ($stripH - 1))

    $parts = @(
        @($script:Config.ActiveTicker.ToUpper(), $fontPrice, $p.Accent),
        @($lblLivePrice.Text, $fontPrice, $p.Text),
        @($lblDayChange.Text, $fontMono, $lblDayChange.ForeColor),
        @($lblDayAbs.Text, $fontMono, $p.Muted),
        @($lblExtQuote.Text, $fontMono, $lblExtQuote.ForeColor),
        @($lblHeaderName.Text, $fontUi, $p.Muted),
        @($lblMarketStatus.Text, $fontUiBold, $lblMarketStatus.ForeColor)
    )
    $tx = S 12
    foreach ($part in $parts) {
        $txt = [string]$part[0]
        if ([string]::IsNullOrEmpty($txt)) { continue }
        $sz = [System.Windows.Forms.TextRenderer]::MeasureText($g, $txt, $part[1])
        $ty = [int](($stripH - $sz.Height) / 2)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $txt, $part[1], (New-Object System.Drawing.Point($tx, $ty)), $part[2])
        $tx += $sz.Width + (S 12)
    }
    $hint = "Esc / F11 / Doppelklick = schließen  |  1-6 / Rad = Zeitraum  |  Strg+Rad = Zoom  |  Ziehen = Messen  |  Pfeile = Ticker"
    $hs = [System.Windows.Forms.TextRenderer]::MeasureText($g, $hint, $fontUi)
    $hx = $Bounds.Width - $hs.Width - (S 12)
    if ($hx -gt ($tx + (S 20))) {
        [System.Windows.Forms.TextRenderer]::DrawText($g, $hint, $fontUi, (New-Object System.Drawing.Point($hx, [int](($stripH - $hs.Height) / 2))), $p.Muted)
    }

    # The chart renderer draws from (0,0): shift it below the strip
    $g.TranslateTransform(0, [float]$stripH)
    try {
        Render-ChartAndRsi -g $g -Bounds (New-Object System.Drawing.Rectangle(0, 0, $Bounds.Width, ($Bounds.Height - $stripH)))
        if ($null -ne $script:LastChartLayout) { $script:LastChartLayout.OffsetY = $stripH }
    } finally {
        $g.ResetTransform()
    }
}

function Close-ChartFullscreen {
    $fsf = $script:FsForm
    $script:FsForm = $null
    $script:FsCanvas = $null
    $script:HoverIndex = -1
    if ($null -ne $fsf -and -not $fsf.IsDisposed) { $fsf.Close() }
    Remove-ChartBitmap -Key "fs"
    if (-not $form.IsDisposed -and $form.Visible) { $form.Activate(); $pnlChartCanvas.Invalidate() }
}

function Toggle-ChartFullscreen {
    if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed) { Close-ChartFullscreen; return }
    $scr = [System.Windows.Forms.Screen]::FromControl($form)

    $fs = New-Object System.Windows.Forms.Form
    $fs.Text = "Chart - " + $script:Config.ActiveTicker
    $fs.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $fs.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $fs.Bounds = $scr.Bounds
    $fs.BackColor = $script:Pal.BodyBg
    $fs.KeyPreview = $true
    $fs.ShowInTaskbar = $false
    $fs.TopMost = $true
    $fs.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None

    $cv = New-Object System.Windows.Forms.Panel
    $cv.Dock = [System.Windows.Forms.DockStyle]::Fill
    $cv.BackColor = $script:Pal.BodyBg
    Enable-DoubleBuffering -Control $cv
    $cv.ContextMenuStrip = $chartContextMenu
    $cv.Add_Paint({
        param($sender, $e)
        Paint-ChartCanvas -Canvas $sender -G $e.Graphics -Fullscreen $true
    })
    $cv.Add_MouseMove($script:ChartMouseMoveHandler)
    $cv.Add_MouseDown($script:ChartMouseDownHandler)
    $cv.Add_MouseUp($script:ChartMouseUpHandler)
    $cv.Add_MouseLeave($script:ChartMouseLeaveHandler)
    $cv.Add_MouseWheel($script:ChartWheelHandler)
    $cv.Add_DoubleClick({ Close-ChartFullscreen })
    $fs.Controls.Add($cv)

    # Left/Right would otherwise be eaten as focus navigation
    $fs.Add_PreviewKeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Left -or $e.KeyCode -eq [System.Windows.Forms.Keys]::Right) { $e.IsInputKey = $true }
    })
    $fs.Add_KeyDown($script:GlobalKeyHandler)
    $fs.Add_FormClosed({
        $script:FsForm = $null
        $script:FsCanvas = $null
        $script:HoverIndex = -1
        Remove-ChartBitmap -Key "fs"
    })

    $script:FsForm = $fs
    $script:FsCanvas = $cv
    $script:HoverIndex = -1
    $fs.Show($form)
    $fs.Activate()
}

# ==============================================================================
# VIEW 2: PORTFOLIO VIEW
# ==============================================================================
$viewPortfolio = New-Object System.Windows.Forms.Panel
$viewPortfolio.Location = New-Object System.Drawing.Point((S 12), (S 92))
$viewPortfolio.Size = New-Object System.Drawing.Size((S 756), (S 456))
$viewPortfolio.BackColor = $script:Pal.Card
$viewPortfolio.Visible = $false
$form.Controls.Add($viewPortfolio)

$lblPortSummary = New-Object System.Windows.Forms.Label
$lblPortSummary.Location = New-Object System.Drawing.Point((S 10), (S 8))
$lblPortSummary.Size = New-Object System.Drawing.Size((S 544), (S 22))
$lblPortSummary.Font = $fontMono
$lblPortSummary.ForeColor = $script:Pal.Text
$lblPortSummary.Text = "Depotwert: 0.00 $($script:Config.Currency) | Gesamt G/V: +0.00 $($script:Config.Currency) (+0.00%)"
$viewPortfolio.Controls.Add($lblPortSummary)

$cmbPortSort = New-Object System.Windows.Forms.ComboBox
$cmbPortSort.Location = New-Object System.Drawing.Point((S 560), (S 6))
$cmbPortSort.Size = New-Object System.Drawing.Size((S 188), (S 24))
$cmbPortSort.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbPortSort.BackColor = $script:Pal.Input
$cmbPortSort.ForeColor = $script:Pal.Text
$cmbPortSort.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbPortSort.Font = $fontUi
[void]$cmbPortSort.Items.Add("Sort: Positionswert (ab)")
[void]$cmbPortSort.Items.Add("Sort: Gesamt G/V % (ab)")
[void]$cmbPortSort.Items.Add("Sort: Tagesänderung %")
[void]$cmbPortSort.Items.Add("Sort: Ticker (A-Z)")
$cmbPortSort.SelectedIndex = 0
$viewPortfolio.Controls.Add($cmbPortSort)

$dgvPortfolio = New-Object System.Windows.Forms.DataGridView
$dgvPortfolio.Location = New-Object System.Drawing.Point((S 8), (S 34))
$dgvPortfolio.Size = New-Object System.Drawing.Size((S 740), (S 286))
Style-DataGrid -Grid $dgvPortfolio
Enable-DoubleBuffering -Control $dgvPortfolio

[void]$dgvPortfolio.Columns.Add("Ticker", "Ticker")
[void]$dgvPortfolio.Columns.Add("Spark",  "5D Trend")
[void]$dgvPortfolio.Columns.Add("Shares", "Stück")
[void]$dgvPortfolio.Columns.Add("Avg",    "EK")
[void]$dgvPortfolio.Columns.Add("Price",  "Kurs")
[void]$dgvPortfolio.Columns.Add("Val",    "Wert")
[void]$dgvPortfolio.Columns.Add("Weight", "Anteil")
[void]$dgvPortfolio.Columns.Add("Pnl",    "G/V Gesamt")
[void]$dgvPortfolio.Columns.Add("Day",    "Tag %")

$dgvPortfolio.Columns[0].Width = S 68
$dgvPortfolio.Columns[1].Width = S 82
$dgvPortfolio.Columns[2].Width = S 66
$dgvPortfolio.Columns[3].Width = S 74
$dgvPortfolio.Columns[4].Width = S 74
$dgvPortfolio.Columns[5].Width = S 92
$dgvPortfolio.Columns[6].Width = S 56
$dgvPortfolio.Columns[7].Width = S 146
$dgvPortfolio.Columns[8].Width = S 68
$viewPortfolio.Controls.Add($dgvPortfolio)


# Shared sparkline cell painter (portfolio column 1 = "5D Trend", watchlist "Spark")
$script:SparkCellPainter = {
    param($sender, $e)
    if ($e.RowIndex -ge 0 -and $e.ColumnIndex -ge 0 -and $sender.Columns[$e.ColumnIndex].Name -eq "Spark") {
        $e.PaintBackground($e.ClipBounds, ($e.State -band [System.Windows.Forms.DataGridViewElementStates]::Selected) -ne 0)
        $sym = [string]$sender.Rows[$e.RowIndex].Cells[0].Value
        if ($sym -and $script:SparklineStore.ContainsKey($sym)) {
            Draw-MiniSparkline -g $e.Graphics -Rect $e.CellBounds -Values $script:SparklineStore[$sym]
        }
        $e.Handled = $true
    }
}

$pnlPortBottom = New-Object System.Windows.Forms.Panel
$pnlPortBottom.Location = New-Object System.Drawing.Point((S 8), (S 326))
$pnlPortBottom.Size = New-Object System.Drawing.Size((S 740), (S 122))
$pnlPortBottom.BackColor = $script:Pal.HeaderBg
$viewPortfolio.Controls.Add($pnlPortBottom)

$script:PortInputLabels = New-Object System.Collections.Generic.List[System.Windows.Forms.Label]
$script:PortInputBoxes  = New-Object System.Collections.Generic.List[System.Windows.Forms.TextBox]

function New-PortInput {
    param([string]$LabelText, [int]$X, [int]$Y, [int]$W)
    $l = New-Object System.Windows.Forms.Label
    $l.Location = New-Object System.Drawing.Point((S $X), (S $Y))
    $l.Size = New-Object System.Drawing.Size((S $W), (S 16))
    $l.Font = $fontUi
    $l.ForeColor = $script:Pal.Muted
    $l.Text = $LabelText
    $pnlPortBottom.Controls.Add($l)
    $script:PortInputLabels.Add($l)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point((S $X), (S ($Y + 17)))
    $tb.Size = New-Object System.Drawing.Size((S $W), (S 22))
    $tb.BackColor = $script:Pal.Input
    $tb.ForeColor = $script:Pal.Text
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tb.Font = $fontMono
    $pnlPortBottom.Controls.Add($tb)
    $script:PortInputBoxes.Add($tb)
    return $tb
}

$txtPortTicker = New-PortInput -LabelText "Ticker:"       -X 8   -Y 8 -W 74
$txtPortShares = New-PortInput -LabelText "Stück:"       -X 88  -Y 8 -W 72
$txtPortAvg    = New-PortInput -LabelText "EK-Kurs:"      -X 166 -Y 8 -W 82

$lblPortCurr = New-Object System.Windows.Forms.Label
$lblPortCurr.Location = New-Object System.Drawing.Point((S 254), (S 8))
$lblPortCurr.Size = New-Object System.Drawing.Size((S 58), (S 16))
$lblPortCurr.Font = $fontUi
$lblPortCurr.ForeColor = $script:Pal.Muted
$lblPortCurr.Text = "EK-Währ.:"
$pnlPortBottom.Controls.Add($lblPortCurr)
$script:PortInputLabels.Add($lblPortCurr)

$cmbPortCurr = New-Object System.Windows.Forms.ComboBox
$cmbPortCurr.Location = New-Object System.Drawing.Point((S 254), (S 25))
$cmbPortCurr.Size = New-Object System.Drawing.Size((S 58), (S 22))
$cmbPortCurr.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbPortCurr.BackColor = $script:Pal.Input
$cmbPortCurr.ForeColor = $script:Pal.Accent
$cmbPortCurr.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbPortCurr.Font = $fontMono
foreach ($dc in (Get-DisplayCurrencies)) { [void]$cmbPortCurr.Items.Add($dc) }
$cmbPortCurr.SelectedIndex = [math]::Max(0, $cmbPortCurr.Items.IndexOf($script:Config.Currency))
$pnlPortBottom.Controls.Add($cmbPortCurr)

function Select-CurrencyInCombo {
    # Selects $Code in a currency combo box and ADDS it first if missing, so a
    # position in e.g. SEK is never saved back with a different currency (v3.0)
    param([System.Windows.Forms.ComboBox]$Combo, [string]$Code)
    $c = Get-NormalizedCurrencyCode $Code
    if (-not $c) { return }
    $idx = $Combo.Items.IndexOf($c)
    if ($idx -lt 0) { $idx = $Combo.Items.Add($c) }
    $Combo.SelectedIndex = $idx
}

$txtPortBuyAmt = New-PortInput -LabelText "Nachkauf:"     -X 318 -Y 8 -W 96
$txtPortTarget = New-PortInput -LabelText "Oder Ziel-EK:" -X 420 -Y 8 -W 98
Set-Tip $txtPortAvg "EK-Kurs je Stück in der EK-Währung" "EK"
Set-Tip $txtPortBuyAmt "Betrag in Anzeigewährung für die Nachkauf-Simulation" "NACHKAUF"
Set-Tip $txtPortTarget "Gewünschter neuer EK in Anzeigewährung" "TARGETEK"

$btnPortSave = New-Object System.Windows.Forms.Button
$btnPortSave.Location = New-Object System.Drawing.Point((S 528), (S 24))
$btnPortSave.Size = New-Object System.Drawing.Size((S 122), (S 24))
Style-FlatButton -Btn $btnPortSave -BgColor $script:Pal.Input -FgColor $colGreen -BorderColor $script:Pal.Border
$btnPortSave.Font = $fontUiBold
$btnPortSave.Text = "Position speichern"
$pnlPortBottom.Controls.Add($btnPortSave)

$btnPortDel = New-Object System.Windows.Forms.Button
$btnPortDel.Location = New-Object System.Drawing.Point((S 656), (S 24))
$btnPortDel.Size = New-Object System.Drawing.Size((S 74), (S 24))
Style-FlatButton -Btn $btnPortDel -BgColor $script:Pal.Input -FgColor $colRed -BorderColor $script:Pal.Border
$btnPortDel.Font = $fontUiBold
$btnPortDel.Text = "Löschen"
$pnlPortBottom.Controls.Add($btnPortDel)

$btnPortTx = New-Object System.Windows.Forms.Button
$btnPortTx.Location = New-Object System.Drawing.Point((S 610), (S 56))
$btnPortTx.Size = New-Object System.Drawing.Size((S 120), (S 26))
Style-FlatButton -Btn $btnPortTx -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnPortTx.Font = $fontUiBold
$btnPortTx.Text = "Transaktion..."
$pnlPortBottom.Controls.Add($btnPortTx)
Set-Tip $btnPortTx "Kauf / Verkauf / Dividende buchen (realisierter G/V wird gespeichert)" "TX"

$btnPortHist = New-Object System.Windows.Forms.Button
$btnPortHist.Location = New-Object System.Drawing.Point((S 610), (S 88))
$btnPortHist.Size = New-Object System.Drawing.Size((S 120), (S 26))
Style-FlatButton -Btn $btnPortHist -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnPortHist.Font = $fontUi
$btnPortHist.Text = "Historie..."
$pnlPortBottom.Controls.Add($btnPortHist)
Set-Tip $btnPortHist "Alle Transaktionen, realisierter G/V, CSV-Export, Jahresreport" "REALIZED"

$lblNachkaufOut = New-Object System.Windows.Forms.Label
$lblNachkaufOut.Location = New-Object System.Drawing.Point((S 8), (S 54))
$lblNachkaufOut.Size = New-Object System.Drawing.Size((S 596), (S 62))
$lblNachkaufOut.Font = $fontMono
$lblNachkaufOut.ForeColor = $script:Pal.Text
$lblNachkaufOut.Text = "Position wählen oder Ticker, Stück & EK eintragen für Live-Nachkauf-Simulation."
$pnlPortBottom.Controls.Add($lblNachkaufOut)

# ==============================================================================
# VIEW 3: WATCHLIST & ALARME VIEW
# ==============================================================================
$viewWatch = New-Object System.Windows.Forms.Panel
$viewWatch.Location = New-Object System.Drawing.Point((S 12), (S 92))
$viewWatch.Size = New-Object System.Drawing.Size((S 756), (S 456))
$viewWatch.BackColor = $script:Pal.Card
$viewWatch.Visible = $false
$form.Controls.Add($viewWatch)

$lblWlTitle = New-Object System.Windows.Forms.Label
$lblWlTitle.Location = New-Object System.Drawing.Point((S 10), (S 8))
$lblWlTitle.Size = New-Object System.Drawing.Size((S 350), (S 20))
$lblWlTitle.Font = $fontUiBold
$lblWlTitle.ForeColor = $script:Pal.Accent
$lblWlTitle.Text = "Watchlist (Ziehen = Reihenfolge | Entf = Löschen)"
$viewWatch.Controls.Add($lblWlTitle)

$btnWlAddActive = New-Object System.Windows.Forms.Button
$btnWlAddActive.Location = New-Object System.Drawing.Point((S 366), (S 6))
$btnWlAddActive.Size = New-Object System.Drawing.Size((S 122), (S 24))
Style-FlatButton -Btn $btnWlAddActive -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnWlAddActive.Font = $fontUiBold
$btnWlAddActive.Text = "+ Aktiven Ticker"
$viewWatch.Controls.Add($btnWlAddActive)

$txtWlSearch = New-Object System.Windows.Forms.TextBox
$txtWlSearch.Location = New-Object System.Drawing.Point((S 8), (S 36))
$txtWlSearch.Size = New-Object System.Drawing.Size((S 280), (S 24))
$txtWlSearch.BackColor = $script:Pal.Input
$txtWlSearch.ForeColor = $script:Pal.Text
$txtWlSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtWlSearch.Font = $fontMono
$viewWatch.Controls.Add($txtWlSearch)

$btnWlAddSearch = New-Object System.Windows.Forms.Button
$btnWlAddSearch.Location = New-Object System.Drawing.Point((S 294), (S 35))
$btnWlAddSearch.Size = New-Object System.Drawing.Size((S 110), (S 25))
Style-FlatButton -Btn $btnWlAddSearch -BgColor $script:Pal.Input -FgColor $colGreen -BorderColor $script:Pal.Border
$btnWlAddSearch.Font = $fontUiBold
$btnWlAddSearch.Text = "+ Suchen / Add"
$viewWatch.Controls.Add($btnWlAddSearch)

$btnWlRemove = New-Object System.Windows.Forms.Button
$btnWlRemove.Location = New-Object System.Drawing.Point((S 410), (S 35))
$btnWlRemove.Size = New-Object System.Drawing.Size((S 78), (S 25))
Style-FlatButton -Btn $btnWlRemove -BgColor $script:Pal.Input -FgColor $colRed -BorderColor $script:Pal.Border
$btnWlRemove.Font = $fontUiBold
$btnWlRemove.Text = "Entfernen"
$viewWatch.Controls.Add($btnWlRemove)

$lstWlSearchDropdown = New-Object System.Windows.Forms.ListBox
$lstWlSearchDropdown.Location = New-Object System.Drawing.Point((S 8), (S 62))
$lstWlSearchDropdown.Size = New-Object System.Drawing.Size((S 396), (S 165))
$lstWlSearchDropdown.BackColor = $script:Pal.HeaderBg
$lstWlSearchDropdown.ForeColor = $script:Pal.Text
$lstWlSearchDropdown.Font = $fontMono
$lstWlSearchDropdown.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$lstWlSearchDropdown.ItemHeight = S 20
$lstWlSearchDropdown.Visible = $false
$viewWatch.Controls.Add($lstWlSearchDropdown)
$lstWlSearchDropdown.BringToFront()

$dgvWatchlist = New-Object System.Windows.Forms.DataGridView
$dgvWatchlist.Location = New-Object System.Drawing.Point((S 8), (S 66))
$dgvWatchlist.Size = New-Object System.Drawing.Size((S 480), (S 382))
Style-DataGrid -Grid $dgvWatchlist
Enable-DoubleBuffering -Control $dgvWatchlist

[void]$dgvWatchlist.Columns.Add("Sym",    "Ticker")
[void]$dgvWatchlist.Columns.Add("Spark",  "5D")
[void]$dgvWatchlist.Columns.Add("Price",  "Kurs")
[void]$dgvWatchlist.Columns.Add("Day",    "Tag %")
[void]$dgvWatchlist.Columns.Add("Ext",    "Ext %")
[void]$dgvWatchlist.Columns.Add("Rsi",    "RSI 1h")
[void]$dgvWatchlist.Columns.Add("Dist",   "52W-H")
[void]$dgvWatchlist.Columns.Add("Market", "Markt")

# Design widths = minimum widths (sum fits the 480 px grid incl. scrollbar)
$dgvWatchlist.Columns["Sym"].Width    = S 64
$dgvWatchlist.Columns["Spark"].Width  = S 44
$dgvWatchlist.Columns["Price"].Width  = S 92
$dgvWatchlist.Columns["Day"].Width    = S 58
$dgvWatchlist.Columns["Ext"].Width    = S 54
$dgvWatchlist.Columns["Rsi"].Width    = S 44
$dgvWatchlist.Columns["Dist"].Width   = S 54
$dgvWatchlist.Columns["Market"].Width = S 56

function Apply-GridColumnTips {
    # Column header explanations (v4.0: from the glossary, follow the tooltip mode)
    $wl = @{ Spark = "SPARK"; Price = "PRICE"; Day = "DAYPCT"; Ext = "EXT"; Rsi = "RSI"; Dist = "HIGH52"; Market = "MARKET" }
    foreach ($k in $wl.Keys) { $dgvWatchlist.Columns[$k].ToolTipText = Get-GlossaryShort -Key $wl[$k] }
    $dgvWatchlist.Columns["Rsi"].ToolTipText = Get-GlossaryShort -Key "RSI" -Prefix ("RSI-{0} auf Stundenbasis" -f $script:Config.RsiPeriod)
    $pf = @{ Spark = "SPARK"; Avg = "EK"; Price = "PRICE"; Weight = "WEIGHT"; Pnl = "PNL"; Day = "DAYPCT" }
    foreach ($k in $pf.Keys) { $dgvPortfolio.Columns[$k].ToolTipText = Get-GlossaryShort -Key $pf[$k] }
}
Apply-GridColumnTips
# Programmatic: header click sorts via Step-GridSort (rows are rebuilt on every refresh)
foreach ($col in $dgvWatchlist.Columns) { $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::Programmatic }
$dgvWatchlist.AllowDrop = $true
$viewWatch.Controls.Add($dgvWatchlist)
$dgvPortfolio.Add_CellPainting($script:SparkCellPainter)
$dgvWatchlist.Add_CellPainting($script:SparkCellPainter)

$lblAlTitle = New-Object System.Windows.Forms.Label
$lblAlTitle.Location = New-Object System.Drawing.Point((S 496), (S 8))
$lblAlTitle.Size = New-Object System.Drawing.Size((S 252), (S 20))
$lblAlTitle.Font = $fontUiBold
$lblAlTitle.ForeColor = $script:Pal.Accent
$lblAlTitle.Text = "Alarme (Doppelklick = Reset)"
$viewWatch.Controls.Add($lblAlTitle)

$txtAlertTicker = New-Object System.Windows.Forms.TextBox
$txtAlertTicker.Location = New-Object System.Drawing.Point((S 496), (S 36))
$txtAlertTicker.Size = New-Object System.Drawing.Size((S 58), (S 24))
$txtAlertTicker.BackColor = $script:Pal.Input
$txtAlertTicker.ForeColor = $script:Pal.Text
$txtAlertTicker.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtAlertTicker.Font = $fontMono
$txtAlertTicker.Text = $script:Config.ActiveTicker
$viewWatch.Controls.Add($txtAlertTicker)

$cmbAlertCond = New-Object System.Windows.Forms.ComboBox
$cmbAlertCond.Location = New-Object System.Drawing.Point((S 557), (S 36))
$cmbAlertCond.Size = New-Object System.Drawing.Size((S 70), (S 24))
$cmbAlertCond.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbAlertCond.BackColor = $script:Pal.Input
$cmbAlertCond.ForeColor = $script:Pal.Text
$cmbAlertCond.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbAlertCond.Font = $fontMono
# v3.0: from Core - in v2.9 $script:AlertConditions was still $null here (it
# was defined ~750 lines further down), so this list stayed empty
$script:AlertConditions = @(Get-AlertConditions)
foreach ($ac in $script:AlertConditions) { [void]$cmbAlertCond.Items.Add($ac) }
$cmbAlertCond.SelectedIndex = 0
$cmbAlertCond.DropDownWidth = S 90
$viewWatch.Controls.Add($cmbAlertCond)
Set-Tip $cmbAlertCond "Wann soll der Alarm auslösen?" "ALERTCOND"

$txtAlertPrice = New-Object System.Windows.Forms.TextBox
$txtAlertPrice.Location = New-Object System.Drawing.Point((S 630), (S 36))
$txtAlertPrice.Size = New-Object System.Drawing.Size((S 52), (S 24))
$txtAlertPrice.BackColor = $script:Pal.Input
$txtAlertPrice.ForeColor = $script:Pal.Text
$txtAlertPrice.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtAlertPrice.Font = $fontMono
$viewWatch.Controls.Add($txtAlertPrice)

$btnAddAlert = New-Object System.Windows.Forms.Button
$btnAddAlert.Location = New-Object System.Drawing.Point((S 685), (S 35))
$btnAddAlert.Size = New-Object System.Drawing.Size((S 34), (S 25))
Style-FlatButton -Btn $btnAddAlert -BgColor $script:Pal.Input -FgColor $colGreen -BorderColor $script:Pal.Border
$btnAddAlert.Font = $fontUiBold
$btnAddAlert.Text = "+"
$viewWatch.Controls.Add($btnAddAlert)
Set-Tip $btnAddAlert "Alarm hinzufügen (Enter im Preisfeld)"

$btnDelAlert = New-Object System.Windows.Forms.Button
$btnDelAlert.Location = New-Object System.Drawing.Point((S 722), (S 35))
$btnDelAlert.Size = New-Object System.Drawing.Size((S 26), (S 25))
Style-FlatButton -Btn $btnDelAlert -BgColor $script:Pal.Input -FgColor $colRed -BorderColor $script:Pal.Border
$btnDelAlert.Font = $fontUiBold
$btnDelAlert.Text = "x"
$viewWatch.Controls.Add($btnDelAlert)
Set-Tip $btnDelAlert "Markierten Alarm löschen (Entf in der Liste)"

# Row 2: note + automatic re-arm
$txtAlertNote = New-Object System.Windows.Forms.TextBox
$txtAlertNote.Location = New-Object System.Drawing.Point((S 496), (S 66))
$txtAlertNote.Size = New-Object System.Drawing.Size((S 168), (S 24))
$txtAlertNote.BackColor = $script:Pal.Input
$txtAlertNote.ForeColor = $script:Pal.Text
$txtAlertNote.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtAlertNote.Font = $fontMono
$txtAlertNote.MaxLength = 60
$viewWatch.Controls.Add($txtAlertNote)
Set-Tip $txtAlertNote "Notiz zum Alarm (optional, erscheint im Hinweis)"

$cmbAlertRearm = New-Object System.Windows.Forms.ComboBox
$cmbAlertRearm.Location = New-Object System.Drawing.Point((S 668), (S 66))
$cmbAlertRearm.Size = New-Object System.Drawing.Size((S 80), (S 24))
$cmbAlertRearm.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbAlertRearm.BackColor = $script:Pal.Input
$cmbAlertRearm.ForeColor = $script:Pal.Text
$cmbAlertRearm.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbAlertRearm.Font = $fontMono
$script:RearmChoices = [ordered]@{ "einmalig" = 0; "R 15m" = 15; "R 1h" = 60; "R 4h" = 240; "R 1T" = 1440 }
foreach ($rk in $script:RearmChoices.Keys) { [void]$cmbAlertRearm.Items.Add($rk) }
$cmbAlertRearm.SelectedIndex = 0
$viewWatch.Controls.Add($cmbAlertRearm)
Set-Tip $cmbAlertRearm "Wieder scharf schalten: nach der Wartezeit, sobald die Bedingung nicht mehr erfüllt ist" "REARM"

$lstAlerts = New-Object System.Windows.Forms.ListBox
$lstAlerts.Location = New-Object System.Drawing.Point((S 496), (S 94))
$lstAlerts.Size = New-Object System.Drawing.Size((S 252), (S 354))
$lstAlerts.BackColor = $script:Pal.Input
$lstAlerts.ForeColor = $script:Pal.Text
$lstAlerts.Font = $fontMono
$lstAlerts.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$viewWatch.Controls.Add($lstAlerts)

# ==============================================================================
# Resizable window: anchors inside the views + layout of header/nav/views
# (the form never gets smaller than the design size, so anchors stay sane)
# ==============================================================================
$aT = [System.Windows.Forms.AnchorStyles]::Top
$aB = [System.Windows.Forms.AnchorStyles]::Bottom
$aL = [System.Windows.Forms.AnchorStyles]::Left
$aR = [System.Windows.Forms.AnchorStyles]::Right
$anchorAll = $aT -bor $aB -bor $aL -bor $aR

# Chart view
$pnlChartCanvas.Anchor   = $anchorAll
$pnlChartControls.Anchor = $aB -bor $aL -bor $aR

# Portfolio view
$lblPortSummary.Anchor = $aT -bor $aL -bor $aR
$cmbPortSort.Anchor    = $aT -bor $aR
$dgvPortfolio.Anchor   = $anchorAll
$pnlPortBottom.Anchor  = $aB -bor $aL -bor $aR
$lblNachkaufOut.Anchor = $aT -bor $aL -bor $aR
$btnPortTx.Anchor   = $aT -bor $aR
$btnPortHist.Anchor = $aT -bor $aR

# Watchlist view: list grows, alarm column keeps its width on the right
$dgvWatchlist.Anchor = $anchorAll
foreach ($ctl in @($lblAlTitle, $txtAlertTicker, $cmbAlertCond, $txtAlertPrice, $btnAddAlert, $btnDelAlert, $txtAlertNote, $cmbAlertRearm)) { $ctl.Anchor = $aT -bor $aR }
$lstAlerts.Anchor = $aT -bor $aB -bor $aR

# Columns stretch with the grid; design widths are the minimum (no more "55.772,28...")
foreach ($grid in @($dgvWatchlist, $dgvPortfolio)) {
    foreach ($col in $grid.Columns) {
        $col.MinimumWidth = $col.Width
        $col.FillWeight = [float]$col.Width
    }
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
}

$script:ViewOn = @{}

function Update-TabHighlight {
    $p = $script:Pal
    foreach ($k in $tabButtons.Keys) {
        $b = $tabButtons[$k]
        if ([bool]$script:ViewOn[$k]) {
            Style-FlatButton -Btn $b -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
        } else {
            Style-FlatButton -Btn $b -BgColor $p.Card -FgColor $p.Text -BorderColor $p.Border
        }
    }
}

function Set-ViewVisibility {
    # v4.0: which views are shown (Standard: one tab, Terminal: several).
    # Kept in $script:ViewOn because Control.Visible reads $false while the
    # window itself is hidden (startup, tray).
    param([hashtable]$On)
    $old = (@("Chart", "Portfolio", "Watchlist") | ForEach-Object { [bool]$script:ViewOn[$_] }) -join ","
    $script:ViewOn = $On
    $viewChart.Visible     = [bool]$On["Chart"]
    $viewPortfolio.Visible = [bool]$On["Portfolio"]
    $viewWatch.Visible     = [bool]$On["Watchlist"]
    Update-TabHighlight
    $new = (@("Chart", "Portfolio", "Watchlist") | ForEach-Object { [bool]$script:ViewOn[$_] }) -join ","
    # a view that just appeared may have missed refreshes while hidden
    if ($new -ne $old -and $script:StartupDone -and $form.Visible) { Update-VisibleTabContent }
}

function Update-MainLayout {
    if ([bool]$script:Config.CompactMode -or $form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }
    $W = $form.ClientSize.Width
    $H = $form.ClientSize.Height
    if ($W -lt (S 400) -or $H -lt (S 300)) { return }

    # Header: right-hand buttons stick to the right edge
    $pnlHeader.Width = $W
    $btnTray.Left     = $W - (S 38)
    $btnCompact.Left  = $W - (S 118)
    $btnPin.Left      = $W - (S 168)
    $btnCurrency.Left = $W - (S 236)
    $lstCurrencyDropdown.Left = $btnCurrency.Left
    $nameW = [math]::Max((S 80), $btnCurrency.Left - (S 394))
    $lblHeaderName.Width   = $nameW
    $lblMarketStatus.Width = $nameW

    # Navigation bar: status text uses the extra width
    $pnlNav.Width = $W - (S 24)
    $lblStatus.SetBounds((S 534), (S 6), ($pnlNav.Width - (S 534)), (S 20))

    $vx = S 12
    $vy = S 92
    $vw = $W - (S 24)
    $vh = $H - (S 92) - (S 12)
    if ([string]$script:Config.Layout -eq "Terminal") {
        # v4.0: chart on top, watchlist / portfolio below (side by side when wide enough)
        $r = Get-TerminalLayoutRects -X $vx -Y $vy -W $vw -H $vh -ChartPct ([double]$script:Config.TerminalChartPct) `
            -ShowWatch ([bool]$script:Config.TerminalShowWatch) -ShowPortfolio ([bool]$script:Config.TerminalShowPortfolio) `
            -ActiveBottom ([string]$script:Config.TerminalBottom) -PanelMinW (S 756) -Gap (S 8) -MinBottomH (S 300) -MinChartH (S 160)
        $on = @{}
        foreach ($pair in @(@("Chart", $viewChart), @("Watchlist", $viewWatch), @("Portfolio", $viewPortfolio))) {
            $rect = $r.($pair[0])
            if ($null -ne $rect) {
                $pair[1].SetBounds([int]$rect[0], [int]$rect[1], [int]$rect[2], [int]$rect[3])
                $on[$pair[0]] = $true
            }
        }
        Set-ViewVisibility $on
    } else {
        foreach ($v in @($viewChart, $viewPortfolio, $viewWatch)) { $v.SetBounds($vx, $vy, $vw, $vh) }
        Set-ViewVisibility @{ ([string]$script:Config.ActiveTab) = $true }
    }
    Update-ChartControlsLayout
    $pnlChartCanvas.Invalidate()
}

# ==============================================================================
# Logic & Theme Application Functions
# ==============================================================================
function Apply-TooltipMode {
    # v4.0: Off / Short / Long + delay; rebuilds every registered tooltip
    $mode = Get-TipModeNow
    $toolTip.Active = ($mode -ne "Off")
    $toolTip.InitialDelay = [int]$script:Config.TooltipDelayMs
    $toolTip.ReshowDelay = [math]::Max(50, [int]([int]$script:Config.TooltipDelayMs / 3))
    $toolTip.AutoPopDelay = if ($mode -eq "Long") { 30000 } else { 10000 }
    foreach ($c in @($script:TipReg.Keys)) {
        if ($c.IsDisposed) { $script:TipReg.Remove($c); continue }
        $t = $script:TipReg[$c]
        $toolTip.SetToolTip($c, (Get-TooltipText -Text $t.Text -Key $t.Key -Mode $mode))
    }
    foreach ($grid in @($dgvWatchlist, $dgvPortfolio)) { $grid.ShowCellToolTips = ($mode -ne "Off") }
    Apply-GridColumnTips
    # dynamic tooltips are rebuilt on their next update
    $script:LastStatusTip = ""
    $script:LastFxTip = ""
}

function Apply-ThemeToAllControls {
    $script:Pal = Get-ThemeColors
    Rebuild-GdiCache
    Apply-DwmTitlebarTheme
    $p = $script:Pal

    $form.BackColor = $p.BodyBg
    $form.ForeColor = $p.Text
    $pnlHeader.BackColor = $p.HeaderBg
    $pnlTickerBox.BackColor = $p.Input
    $txtSearch.BackColor = $p.Input
    $txtSearch.ForeColor = $p.Accent
    $btnTickerDrop.BackColor = $p.Input
    $btnTickerDrop.ForeColor = $p.Accent
    $lblLivePrice.ForeColor = $p.Text
    $lblHeaderName.ForeColor = $p.Muted
    $lblDayAbs.ForeColor = $p.Muted
    $script:LastTrayIconKey = ""
    $picCompactSpark.BackColor = $p.BodyBg

    Style-FlatButton -Btn $btnCurrency -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Accent
    Style-FlatButton -Btn $btnCompact  -BgColor $p.Input -FgColor $p.Text   -BorderColor $p.Border
    Style-FlatButton -Btn $btnTray     -BgColor $p.Input -FgColor $p.Muted  -BorderColor $p.Border
    Style-FlatButton -Btn $btnPin `
        -BgColor $(if ($script:Config.TopMost) { $p.Accent } else { $p.Input }) `
        -FgColor $(if ($script:Config.TopMost) { $p.HeaderBg } else { $p.Text }) `
        -BorderColor $(if ($script:Config.TopMost) { $p.Accent } else { $p.Border })

    $lstCurrencyDropdown.BackColor = $p.Input
    $lstCurrencyDropdown.ForeColor = $p.Text
    $lstTickerDropdown.BackColor   = $p.Card
    $lstTickerDropdown.ForeColor   = $p.Text

    $pnlNav.BackColor = $p.BodyBg
    Style-FlatButton -Btn $btnRefreshNow -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $cmbRefresh.BackColor = $p.Input
    $cmbRefresh.ForeColor = $p.Muted
    Style-FlatButton -Btn $btnThemeCycle -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $btnThemeCycle.Text = $script:Config.Theme
    Style-FlatButton -Btn $btnSettings -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $pnlTape.BackColor = $p.HeaderBg
    $script:TapeSignature = ""
    $lblStatus.ForeColor = $p.Muted

    $viewChart.BackColor = $p.BodyBg
    $pnlChartCanvas.BackColor = $p.BodyBg
    $pnlChartControls.BackColor = $p.BodyBg
    Style-FlatButton -Btn $btnExportCsv -BgColor $p.Card -FgColor $p.Muted -BorderColor $p.Border
    Style-FlatButton -Btn $btnFullscreen -BgColor $p.Card -FgColor $p.Muted -BorderColor $p.Border
    if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed) {
        $script:FsForm.BackColor = $p.BodyBg
        $script:FsCanvas.BackColor = $p.BodyBg
    }

    $viewPortfolio.BackColor = $p.Card
    $cmbPortSort.BackColor = $p.Input
    $cmbPortSort.ForeColor = $p.Text
    Style-DataGrid -Grid $dgvPortfolio
    $pnlPortBottom.BackColor = $p.HeaderBg
    foreach ($lbl in $script:PortInputLabels) { $lbl.ForeColor = $p.Muted }
    foreach ($tb  in $script:PortInputBoxes)  { $tb.BackColor = $p.Input; $tb.ForeColor = $p.Text }
    $cmbPortCurr.BackColor = $p.Input
    $cmbPortCurr.ForeColor = $p.Accent
    Style-FlatButton -Btn $btnPortSave -BgColor $p.Input -FgColor $colGreen -BorderColor $p.Border
    Style-FlatButton -Btn $btnPortDel  -BgColor $p.Input -FgColor $colRed   -BorderColor $p.Border
    Style-FlatButton -Btn $btnPortTx   -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    Style-FlatButton -Btn $btnPortHist -BgColor $p.Input -FgColor $p.Muted  -BorderColor $p.Border
    $lblNachkaufOut.ForeColor = $p.Text

    $viewWatch.BackColor = $p.Card
    $lblWlTitle.ForeColor = $p.Accent
    $lblAlTitle.ForeColor = $p.Accent
    Style-FlatButton -Btn $btnWlAddActive -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $txtWlSearch.BackColor = $p.Input; $txtWlSearch.ForeColor = $p.Text
    Style-FlatButton -Btn $btnWlAddSearch -BgColor $p.Input -FgColor $colGreen -BorderColor $p.Border
    Style-FlatButton -Btn $btnWlRemove    -BgColor $p.Input -FgColor $colRed   -BorderColor $p.Border
    $lstWlSearchDropdown.BackColor = $p.HeaderBg; $lstWlSearchDropdown.ForeColor = $p.Text
    Style-DataGrid -Grid $dgvWatchlist

    $txtAlertTicker.BackColor = $p.Input; $txtAlertTicker.ForeColor = $p.Text
    $cmbAlertCond.BackColor   = $p.Input; $cmbAlertCond.ForeColor   = $p.Text
    $txtAlertPrice.BackColor  = $p.Input; $txtAlertPrice.ForeColor  = $p.Text
    $txtAlertNote.BackColor   = $p.Input; $txtAlertNote.ForeColor   = $p.Text
    $cmbAlertRearm.BackColor  = $p.Input; $cmbAlertRearm.ForeColor  = $p.Text
    Style-FlatButton -Btn $btnAddAlert -BgColor $p.Input -FgColor $colGreen -BorderColor $p.Border
    Style-FlatButton -Btn $btnDelAlert -BgColor $p.Input -FgColor $colRed   -BorderColor $p.Border
    $lstAlerts.BackColor = $p.Input; $lstAlerts.ForeColor = $p.Text

    Set-ActiveTab -TabName $script:Config.ActiveTab
    Update-AllUiViews
    $pnlHeader.Invalidate()
    $pnlTickerBox.Invalidate()
}




function Set-ActiveCurrency {
    param([string]$NewCurrency)
    $c = $NewCurrency.Trim().ToUpper()
    if ($c -notin @(Get-DisplayCurrencies)) { return }
    $script:Config.Currency = $c
    $btnCurrency.Text = "$c $script:DropArrow"
    $lstCurrencyDropdown.Visible = $false
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Refresh-AllMarketData
    Update-AllUiViews
}

function Populate-TickerDropdown {
    param([string]$FilterText = "", [array]$SearchHits = @())
    # keep the highlighted entry when the async Yahoo hits arrive a moment later
    $prevSel = if ($lstTickerDropdown.Visible -and $null -ne $lstTickerDropdown.SelectedItem) { [string]$lstTickerDropdown.SelectedItem.Symbol } else { "" }
    $lstTickerDropdown.BeginUpdate()
    $lstTickerDropdown.Items.Clear()
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $curr = $script:Config.Currency
    $fUpper = $FilterText.Trim().ToUpper()

    $localSymbols = New-Object System.Collections.Generic.List[string]
    foreach ($w in $script:Config.Watchlist) { [void]$localSymbols.Add($w.ToUpper()) }
    foreach ($p in $script:Portfolio.Keys) {
        if (-not $localSymbols.Contains($p.ToUpper())) { [void]$localSymbols.Add($p.ToUpper()) }
    }

    foreach ($sym in $localSymbols) {
        $q = if ($script:QuoteStore.ContainsKey($sym)) { $script:QuoteStore[$sym] } else { $null }
        $nameStr = if ($q -and $q.LongName) { $q.LongName } else { $sym }
        if ($fUpper.Length -gt 0 -and $sym -notlike "*$fUpper*" -and $nameStr.ToUpper() -notlike "*$fUpper*") {
            continue
        }
        [void]$seen.Add($sym)
        if ($q) {
            $pConv = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $curr
            $sign  = if ($q.ChangePct -ge 0) { "+" } else { "" }
            $disp  = "{0,-9} | {1,8:N2} {2} ({3}{4:N1}%) | {5}" -f $sym, $pConv, $curr, $sign, $q.ChangePct, $nameStr
        } else {
            $disp  = "{0,-9} | {1}" -f $sym, $nameStr
        }
        [void]$lstTickerDropdown.Items.Add([PSCustomObject]@{ Symbol = $sym; Display = $disp })
    }

    foreach ($h in $SearchHits) {
        if ($null -ne $h -and -not $seen.Contains($h.Symbol)) {
            [void]$seen.Add($h.Symbol)
            [void]$lstTickerDropdown.Items.Add($h)
        }
    }

    $lstTickerDropdown.DisplayMember = "Display"
    $lstTickerDropdown.EndUpdate()
    if ($lstTickerDropdown.Items.Count -gt 0) {
        $selIdx = 0
        if ($prevSel) {
            for ($i = 0; $i -lt $lstTickerDropdown.Items.Count; $i++) {
                if ([string]$lstTickerDropdown.Items[$i].Symbol -eq $prevSel) { $selIdx = $i; break }
            }
        }
        $lstTickerDropdown.SelectedIndex = $selIdx
        $rowsVisible = [math]::Min(9, [math]::Max(2, $lstTickerDropdown.Items.Count))
        $lstTickerDropdown.Height = ($rowsVisible * (S 20)) + (S 6)
        $lstTickerDropdown.Visible = $true
        $lstTickerDropdown.BringToFront()
    } else {
        $lstTickerDropdown.Visible = $false
    }
}

function Set-ActiveTab {
    param([string]$TabName)
    if ($TabName -notin @("Chart", "Portfolio", "Watchlist")) { $TabName = "Chart" }
    $script:Config.ActiveTab = $TabName
    # Terminal: the Portfolio / Watch tabs pick the lower panel when only one fits
    if ($TabName -in @("Portfolio", "Watchlist")) { $script:Config.TerminalBottom = $TabName }
    $lstTickerDropdown.Visible   = $false
    $lstCurrencyDropdown.Visible = $false
    $lstWlSearchDropdown.Visible = $false
    if ([bool]$script:Config.CompactMode) {
        # small bars never show views (a theme switch used to re-show them)
        Set-ViewVisibility @{}
    } else {
        Update-MainLayout
    }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    # the tab that just became visible may have missed refreshes while hidden
    if ($form.Visible -and $script:StartupDone) { Update-VisibleTabContent }
}

function Update-VisibleTabContent {
    if ($viewPortfolio.Visible) {
        Refresh-PortfolioGrid
        Update-NachkaufSimulation
    }
    if ($viewWatch.Visible) { Refresh-WatchlistAndAlerts }
}

function Ensure-FormOnScreen {
    # The restored size could push the window past the right/bottom edge (or
    # the monitor it was on is gone): pull it back into the working area
    if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) { return }
    $center = New-Object System.Drawing.Point(($form.Left + [int]($form.Width / 2)), ($form.Top + [int]($form.Height / 2)))
    $wa = [System.Windows.Forms.Screen]::FromPoint($center).WorkingArea
    $x = [math]::Max($wa.Left, [math]::Min($form.Left, $wa.Right - $form.Width))
    $y = [math]::Max($wa.Top,  [math]::Min($form.Top,  $wa.Bottom - $form.Height))
    if ($x -ne $form.Left -or $y -ne $form.Top) {
        $form.Location = New-Object System.Drawing.Point($x, $y)
    }
}

function Get-LayoutLabel {
    param([string]$Layout)
    return ("{0} {1}" -f $Layout, $script:DropArrow)
}

function Update-LayoutButton {
    $btnCompact.Text = Get-LayoutLabel ([string]$script:Config.Layout)
    foreach ($it in $layoutMenu.Items) {
        if ($it -is [System.Windows.Forms.ToolStripMenuItem] -and $it.Tag -is [string]) {
            $tag = [string]$it.Tag
            if ($tag -like "Layout:*") { $it.Checked = ($tag -eq ("Layout:" + $script:Config.Layout)) }
            elseif ($tag -eq "Opt:Watch") { $it.Checked = [bool]$script:Config.TerminalShowWatch }
            elseif ($tag -eq "Opt:Portfolio") { $it.Checked = [bool]$script:Config.TerminalShowPortfolio }
        }
    }
}

function Get-FullLayoutClientSize {
    # Remembered client size of Standard / Terminal (never below the design
    # size, never above the screen). Terminal starts at 85 % of the screen.
    param([string]$Layout)
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $maxW = [math]::Max((S 780), $wa.Width - (S 20))
    $maxH = [math]::Max((S 560), $wa.Height - (S 40))
    if ($Layout -eq "Terminal") {
        $w = [int]$script:Config.TerminalW
        $h = [int]$script:Config.TerminalH
        if ($w -le 0) { $w = [int]($wa.Width * 0.85) }
        if ($h -le 0) { $h = [int]($wa.Height * 0.85) }
        $minH = [math]::Min((S 760), $maxH)
        return (New-Object System.Drawing.Size([math]::Min([math]::Max((S 780), $w), $maxW), [math]::Min([math]::Max($minH, $h), $maxH)))
    }
    return (New-Object System.Drawing.Size([math]::Min([math]::Max((S 780), [int]$script:Config.WindowW), $maxW), [math]::Min([math]::Max((S 560), [int]$script:Config.WindowH), $maxH)))
}

function Save-WindowSize {
    # Client size of the CURRENT full layout (Standard and Terminal are separate)
    if ([bool]$script:Config.CompactMode -or $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) { return }
    if ([string]$script:Config.Layout -eq "Terminal") {
        $script:Config.TerminalW = $form.ClientSize.Width
        $script:Config.TerminalH = $form.ClientSize.Height
    } else {
        $script:Config.WindowW = $form.ClientSize.Width
        $script:Config.WindowH = $form.ClientSize.Height
    }
}

function Apply-Layout {
    # v4.0: Ticker / Compact / Standard / Terminal (replaces Apply-CompactMode)
    param([string]$Layout)
    if ($Layout -notin @(Get-LayoutNames)) { $Layout = "Standard" }
    if ($script:StartupDone) { Save-WindowSize }
    $script:Config.Layout = $Layout
    $isCompact = Test-CompactLayout $Layout
    $isTicker  = ($Layout -eq "Ticker")
    $script:Config.CompactMode = $isCompact
    if (-not $isCompact) { $script:Config.LastFullLayout = $Layout }
    $lstTickerDropdown.Visible   = $false
    $lstCurrencyDropdown.Visible = $false
    $lstWlSearchDropdown.Visible = $false

    if ($isCompact) {
        # Small bars: fixed size. Ticker = borderless strip with price + mini chart.
        $form.WindowState     = [System.Windows.Forms.FormWindowState]::Normal
        $form.MinimumSize     = [System.Drawing.Size]::Empty
        $form.MaximizeBox     = $false
        $form.FormBorderStyle = if ($isTicker) { [System.Windows.Forms.FormBorderStyle]::None } else { [System.Windows.Forms.FormBorderStyle]::FixedSingle }
        $pnlNav.Visible = $false
        Set-ViewVisibility @{}

        $barW = if ($isTicker) { S 576 } else { S 698 }
        $pnlHeader.Size = New-Object System.Drawing.Size($barW, (S 48))
        $lblHeaderName.Visible   = $false
        $picCompactSpark.Visible = $true
        $lblMarketStatus.Visible = -not $isTicker
        $lblMarketStatus.Location = New-Object System.Drawing.Point((S 470), (S 16))
        $lblMarketStatus.Size     = New-Object System.Drawing.Size((S 124), (S 17))
        $btnCurrency.Visible = $false
        $btnPin.Visible      = $false
        $btnCompact.Location = New-Object System.Drawing.Point($(if ($isTicker) { S 470 } else { S 598 }), (S 11))
        $btnCompact.Size     = New-Object System.Drawing.Size((S 64), (S 26))
        $btnTray.Location    = New-Object System.Drawing.Point($(if ($isTicker) { S 538 } else { S 666 }), (S 11))
        # Optional ticker tape (watchlist + portfolio) below the compact bar
        $useTape = (-not $isTicker) -and [bool]$script:Config.CompactTape
        $pnlTape.SetBounds(0, (S 48), $barW, (S 22))
        $pnlTape.Visible = $useTape
        $form.ClientSize = New-Object System.Drawing.Size($barW, ((S 48) + $(if ($useTape) { S 22 } else { 0 })))
        Update-TickerTape
        Ensure-FormOnScreen
    } else {
        $pnlTape.Visible = $false
        $pnlHeader.Size = New-Object System.Drawing.Size((S 780), (S 48))
        $lblHeaderName.Visible   = $true
        $lblMarketStatus.Visible = $true
        $picCompactSpark.Visible = $false
        $lblMarketStatus.Location = New-Object System.Drawing.Point((S 390), (S 26))
        $lblMarketStatus.Size     = New-Object System.Drawing.Size((S 150), (S 17))
        $btnCurrency.Visible = $true
        $btnPin.Visible      = $true
        $btnCompact.Location = New-Object System.Drawing.Point((S 662), (S 11))
        $btnCompact.Size     = New-Object System.Drawing.Size((S 74), (S 26))
        $btnTray.Location    = New-Object System.Drawing.Point((S 742), (S 11))

        $pnlNav.Visible = $true
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
        $form.MaximizeBox     = $true
        $form.MinimumSize     = $script:MinFormSize
        $form.ClientSize      = Get-FullLayoutClientSize -Layout $Layout
        Ensure-FormOnScreen
        Set-ActiveTab -TabName $script:Config.ActiveTab
        Update-MainLayout
    }
    try { $form.Opacity = [math]::Max(0.3, [math]::Min(1.0, [double]$script:Config.Opacity / 100.0)) } catch { }
    Update-LayoutButton
    Update-TapeTimer
    $pnlHeader.Invalidate()
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
}

function Apply-CompactMode {
    # kept for older call sites: compact on = Compact, off = last big layout
    param([bool]$IsCompact)
    if ($IsCompact) { Apply-Layout "Compact" } else { Apply-Layout ([string]$script:Config.LastFullLayout) }
}

function Toggle-CompactLayout {
    # C key / tray: between the small bar and the last big layout
    if ([bool]$script:Config.CompactMode) { Apply-Layout ([string]$script:Config.LastFullLayout) } else { Apply-Layout "Compact" }
}

function Update-NachkaufSimulation {
    $sym = $txtPortTicker.Text.Trim().ToUpper()
    if ([string]::IsNullOrWhiteSpace($sym)) { $sym = $script:Config.ActiveTicker.ToUpper() }
    $dispCurr = $script:Config.Currency
    $posCurr  = if ($cmbPortCurr.SelectedItem) { [string]$cmbPortCurr.SelectedItem } else { $dispCurr }

    $mktPrice = 0.0
    if ($script:QuoteStore.ContainsKey($sym)) {
        $q = $script:QuoteStore[$sym]
        $mktPrice = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $dispCurr
    }

    $shares    = Parse-DecimalInput $txtPortShares.Text
    $rawAvg    = Parse-DecimalInput $txtPortAvg.Text
    $avgPrice  = Convert-CurrencyValue -Amount $rawAvg -FromCurrency $posCurr -ToCurrency $dispCurr
    $buyAmount = Parse-DecimalInput $txtPortBuyAmt.Text
    $targetAvg = Parse-DecimalInput $txtPortTarget.Text

    if ($mktPrice -le 0) {
        $lblNachkaufOut.Text = "Ticker '$sym': Aktueller Marktpreis wird geladen oder unbekannt."
        return
    }

    $lines = New-Object System.Collections.Generic.List[string]
    if ($shares -gt 0 -and $avgPrice -gt 0) {
        $curVal = $shares * $mktPrice
        $pnlAbs = ($mktPrice - $avgPrice) * $shares
        $pnlPct = (($mktPrice - $avgPrice) / $avgPrice) * 100.0
        $sign   = if ($pnlAbs -ge 0) { "+" } else { "" }
        $lines.Add(("{0,-8} | Akt. Wert: {1:N2} {2} | G/V: {3}{4:N2} {2} ({3}{5:N2}%)" -f $sym, $curVal, $dispCurr, $sign, $pnlAbs, $pnlPct))
    } else {
        $lines.Add(("{0,-8} | Aktueller Marktkurs: {1:N2} {2}" -f $sym, $mktPrice, $dispCurr))
    }

    if ($buyAmount -gt 0) {
        $addShares = $buyAmount / $mktPrice
        $newTotalShares = $shares + $addShares
        $newTotalCost = ($shares * $avgPrice) + $buyAmount
        $newAvg = if ($newTotalShares -gt 0) { $newTotalCost / $newTotalShares } else { $mktPrice }
        $diffAvg = if ($avgPrice -gt 0) { $newAvg - $avgPrice } else { 0.0 }
        $lines.Add(("Nachkauf {0:N2} {1} -> +{2:N3} Stk | Gesamt: {3:N3} Stk | Neuer EK: {4:N2} {1} ({5:+0.00;-0.00;0.00})" -f $buyAmount, $dispCurr, $addShares, $newTotalShares, $newAvg, $diffAvg))
    } elseif ($targetAvg -gt 0 -and $shares -gt 0 -and $avgPrice -gt 0) {
        $denom = $targetAvg - $mktPrice
        if ([math]::Abs($denom) -gt 0.0001) {
            $reqShares = ($shares * ($avgPrice - $targetAvg)) / $denom
            if ($reqShares -gt 0) {
                $reqCap = $reqShares * $mktPrice
                $lines.Add(("Für Ziel-EK {0:N2} {1} erforderlich: {2:N2} {1} ({3:N3} Stk zum Kurs {4:N2})" -f $targetAvg, $dispCurr, $reqCap, $reqShares, $mktPrice))
            } else {
                $lines.Add("Ziel-EK liegt nicht zwischen aktuellem EK und Marktkurs.")
            }
        }
    } else {
        $lines.Add("Tipp: 'Nachkauf' ($dispCurr) ODER 'Ziel-EK' ($dispCurr) eingeben für Live-Simulation.")
    }

    $lblNachkaufOut.Text = ($lines -join "`r`n")
}

# Grid rebuild helpers: keep selection + scroll position across refreshes and
# suppress SelectionChanged while rows are re-created (it used to overwrite
# the portfolio editor with row 0 on every poll).
$script:SuppressGridSelection = $false

function Save-GridState {
    param([System.Windows.Forms.DataGridView]$Grid)
    $sel = $null
    if ($Grid.SelectedRows.Count -gt 0) { $sel = [string]$Grid.SelectedRows[0].Cells[0].Value }
    $first = -1
    try { $first = $Grid.FirstDisplayedScrollingRowIndex } catch { }
    return @{ Selected = $sel; First = $first }
}

function Restore-GridState {
    param([System.Windows.Forms.DataGridView]$Grid, [hashtable]$State)
    $Grid.ClearSelection()
    if ($State.Selected) {
        foreach ($row in $Grid.Rows) {
            if ([string]$row.Cells[0].Value -eq $State.Selected) {
                $row.Selected = $true
                try { $Grid.CurrentCell = $row.Cells[0] } catch { }
                break
            }
        }
    }
    if ($State.First -ge 0 -and $Grid.Rows.Count -gt 0) {
        try { $Grid.FirstDisplayedScrollingRowIndex = [math]::Min($State.First, $Grid.Rows.Count - 1) } catch { }
    }
}

function Refresh-PortfolioGrid {
    $curr = $script:Config.Currency
    $rows = New-Object System.Collections.Generic.List[PSObject]
    $totVal  = 0.0
    $totCost = 0.0
    $totDay  = 0.0
    $totPrev = 0.0

    foreach ($sym in $script:Portfolio.Keys) {
        $p = $script:Portfolio[$sym]
        $avgConv = Convert-CurrencyValue -Amount $p.AvgPrice -FromCurrency $p.Currency -ToCurrency $curr
        $mktConv = $avgConv
        $dayPct  = 0.0
        if ($script:QuoteStore.ContainsKey($sym)) {
            $q = $script:QuoteStore[$sym]
            $mktConv = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $curr
            $dayPct  = $q.ChangePct
            if ($q.PrevClose -gt 0) {
                $prevConv = Convert-CurrencyValue -Amount $q.PrevClose -FromCurrency $q.Currency -ToCurrency $curr
                $totDay  += $p.Shares * ($mktConv - $prevConv)
                $totPrev += $p.Shares * $prevConv
            }
        }
        $val    = $p.Shares * $mktConv
        $cost   = $p.Shares * $avgConv
        $pnlAbs = $val - $cost
        $pnlPct = if ($cost -gt 0) { ($pnlAbs / $cost) * 100.0 } else { 0.0 }

        $totVal  += $val
        $totCost += $cost

        $rows.Add([PSCustomObject]@{
            Ticker = $sym
            Shares = $p.Shares
            Avg    = $avgConv
            Price  = $mktConv
            Value  = $val
            PnlAbs = $pnlAbs
            PnlPct = $pnlPct
            DayPct = $dayPct
        })
    }

    $pfMap = @{ "Ticker" = "Ticker"; "Shares" = "Shares"; "Avg" = "Avg"; "Price" = "Price"; "Val" = "Value"; "Weight" = "Value"; "Pnl" = "PnlPct"; "Day" = "DayPct" }
    $sorted = if ($script:PfSort.Col -and $pfMap.ContainsKey($script:PfSort.Col)) {
        $rows | Sort-Object -Property $pfMap[$script:PfSort.Col] -Descending:([bool]$script:PfSort.Desc)
    } else { switch ($cmbPortSort.SelectedIndex) {
        1 { $rows | Sort-Object PnlPct -Descending }
        2 { $rows | Sort-Object DayPct -Descending }
        3 { $rows | Sort-Object Ticker }
        default { $rows | Sort-Object Value -Descending }
    } }

    $gridState = Save-GridState -Grid $dgvPortfolio
    $script:SuppressGridSelection = $true
    try {
    $dgvPortfolio.Rows.Clear()
    foreach ($r in $sorted) {
        $sign   = if ($r.PnlAbs -ge 0) { "+" } else { "" }
        $dSign  = if ($r.DayPct -ge 0) { "+" } else { "" }
        $weight = if ($totVal -gt 0) { ($r.Value / $totVal) * 100.0 } else { 0.0 }
        $idx = $dgvPortfolio.Rows.Add(
            $r.Ticker,
            "",
            ("{0:N2}" -f $r.Shares),
            ("{0:N2}" -f $r.Avg),
            ("{0:N2}" -f $r.Price),
            ("{0:N2} {1}" -f $r.Value, $curr),
            ("{0:N1}%" -f $weight),
            ("{0}{1:N2} ({0}{2:N1}%)" -f $sign, $r.PnlAbs, $r.PnlPct),
            ("{0}{1:N2}%" -f $dSign, $r.DayPct)
        )
        $dgvPortfolio.Rows[$idx].Cells[7].Style.ForeColor = if ($r.PnlAbs -ge 0) { $colGreen } else { $colRed }
        $dgvPortfolio.Rows[$idx].Cells[8].Style.ForeColor = if ($r.DayPct -ge 0) { $colGreen } else { $colRed }
    }
    Restore-GridState -Grid $dgvPortfolio -State $gridState
    } finally {
        $script:SuppressGridSelection = $false
    }

    $totPnl = $totVal - $totCost
    $totPct = if ($totCost -gt 0) { ($totPnl / $totCost) * 100.0 } else { 0.0 }
    $tSign  = if ($totPnl -ge 0) { "+" } else { "" }
    $lblPortSummary.ForeColor = if ($totPnl -ge 0) { $colGreen } else { $colRed }
    $dPct  = if ($totPrev -gt 0) { ($totDay / $totPrev) * 100.0 } else { 0.0 }
    $dSign = if ($totDay -ge 0) { "+" } else { "" }
    $realYear = Get-RealizedTotal -Year (Get-Date).Year
    $realAll  = Get-RealizedTotal
    $realTxt  = if ([math]::Abs($realYear) -gt 0.004) { " | Real. {0}: {1:+0.00;-0.00}" -f (Get-Date).Year, $realYear } else { "" }
    $lblPortSummary.Text = ("Depot: {0:N2} {1} | G/V: {2}{3:N2} ({2}{4:N2}%) | Heute: {5}{6:N2} ({5}{7:N2}%){8}" -f $totVal, $curr, $tSign, $totPnl, $totPct, $dSign, $totDay, $dPct, $realTxt)
    if ($script:Portfolio.Count -eq 0) {
        # Empty state (v3.0)
        $lblPortSummary.ForeColor = $script:Pal.Muted
        $lblPortSummary.Text = "Noch keine Positionen - unten Ticker, Stück und EK eintragen oder 'Transaktion...' buchen."
    }
    Set-DynTip $lblPortSummary ("Investiert: {0:N2} {1}`r`nG/V gesamt (offen): {2}{3:N2} {1}`r`nG/V heute:  {4}{5:N2} {1}`r`nRealisiert {6}: {7:+0.00;-0.00} {1}`r`nRealisiert gesamt: {8:+0.00;-0.00} {1}" -f $totCost, $curr, $tSign, $totPnl, $dSign, $totDay, (Get-Date).Year, $realYear, $realAll) "REALIZED"
}

# Header-click sorting (v2.9). Col = "" -> manual order (drag & drop possible)
$script:WlSort = @{ Col = ""; Desc = $false }
$script:PfSort = @{ Col = ""; Desc = $false }

function Get-WatchlistSortValue {
    param([string]$Col, $Q, [long]$NowSec)
    switch ($Col) {
        "Price"  { return [double](Convert-CurrencyValue -Amount $Q.Price -FromCurrency $Q.Currency -ToCurrency $script:Config.Currency) }
        "Day"    { return [double]$Q.ChangePct }
        "Ext"    { if ($Q.ExtPrice -gt 0) { return [double]$Q.ExtPct } else { return [double]::MinValue } }
        "Rsi"    { if ([double]::IsNaN([double]$Q.Rsi14)) { return [double]::MinValue } else { return [double]$Q.Rsi14 } }
        "Dist"   { if ($Q.High52 -gt 0) { return (([double]$Q.Price - $Q.High52) / $Q.High52) } else { return [double]::MinValue } }
        "Spark"  {
            $sp = $script:SparklineStore[$Q.Ticker]
            if ($null -ne $sp -and @($sp).Count -ge 2 -and $sp[0] -gt 0) { return (($sp[@($sp).Count - 1] / $sp[0]) - 1.0) }
            return [double]::MinValue
        }
        "Market" {
            $ms = Get-MarketState -Tp $Q.Tp -NowSec $NowSec
            $rank = @{ "REGULAR" = 4; "OPEN24" = 3; "PRE" = 2; "POST" = 1 }
            if ($null -ne $ms -and $rank.ContainsKey($ms.State)) { return [double]$rank[$ms.State] }
            return 0.0
        }
    }
    return 0.0
}

function Get-WatchlistOrder {
    $syms = @($script:Config.Watchlist | ForEach-Object { ([string]$_).ToUpper() })
    $col = [string]$script:WlSort.Col
    if (-not $col) { return $syms }
    if ($col -eq "Sym") {
        return @($syms | Sort-Object -Descending:([bool]$script:WlSort.Desc))
    }
    $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $withQ = @()
    $noQ = @()
    foreach ($u in $syms) {
        if ($script:QuoteStore.ContainsKey($u)) {
            $withQ += [PSCustomObject]@{ Sym = $u; Key = (Get-WatchlistSortValue -Col $col -Q $script:QuoteStore[$u] -NowSec $nowSec) }
        } else { $noQ += $u }
    }
    $sorted = @($withQ | Sort-Object -Property Key -Descending:([bool]$script:WlSort.Desc) | ForEach-Object { $_.Sym })
    return @($sorted + $noQ)
}

function Set-GridSortGlyph {
    param([System.Windows.Forms.DataGridView]$Grid, [hashtable]$Sort)
    foreach ($col in $Grid.Columns) {
        $col.HeaderCell.SortGlyphDirection = if ($col.Name -eq $Sort.Col) {
            if ($Sort.Desc) { [System.Windows.Forms.SortOrder]::Descending } else { [System.Windows.Forms.SortOrder]::Ascending }
        } else { [System.Windows.Forms.SortOrder]::None }
    }
}

function Step-GridSort {
    # 1st click: sort (text ascending, numbers descending), 2nd: reverse, 3rd: off
    param([hashtable]$Sort, [string]$Col, [string[]]$TextCols)
    if ($Sort.Col -ne $Col) {
        $Sort.Col = $Col
        $Sort.Desc = -not ($TextCols -contains $Col)
        $Sort.Step = 1
    } elseif ([int]$Sort.Step -eq 1) {
        $Sort.Desc = -not $Sort.Desc
        $Sort.Step = 2
    } else {
        $Sort.Col = ""
        $Sort.Step = 0
    }
}

function Move-WatchlistSymbol {
    # Manual order: move one symbol to a new index (drag & drop / Alt+arrows)
    param([string]$Symbol, [int]$NewIndex)
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($w in $script:Config.Watchlist) { $list.Add(([string]$w).ToUpper()) }
    $old = $list.IndexOf($Symbol.ToUpper())
    if ($old -lt 0) { return }
    $NewIndex = [math]::Max(0, [math]::Min($list.Count - 1, $NewIndex))
    if ($NewIndex -eq $old) { return }
    $list.RemoveAt($old)
    $list.Insert($NewIndex, $Symbol.ToUpper())
    $script:Config.Watchlist = $list.ToArray()
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Refresh-WatchlistAndAlerts
    foreach ($row in $dgvWatchlist.Rows) {
        if ([string]$row.Cells[0].Value -eq $Symbol.ToUpper()) { $dgvWatchlist.ClearSelection(); $row.Selected = $true; try { $dgvWatchlist.CurrentCell = $row.Cells[0] } catch { }; break }
    }
}

function Refresh-WatchlistAndAlerts {
    $curr = $script:Config.Currency
    $obVal = [double]$script:Config.RsiOverbought
    $osVal = [double]$script:Config.RsiOversold
    $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $gridState = Save-GridState -Grid $dgvWatchlist
    $script:SuppressGridSelection = $true
    try {
    $dgvWatchlist.Rows.Clear()

    foreach ($sym in (Get-WatchlistOrder)) {
        $uSym = $sym.ToUpper()
        if ($script:QuoteStore.ContainsKey($uSym)) {
            $q = $script:QuoteStore[$uSym]
            $pConv = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $curr
            $sign  = if ($q.ChangePct -ge 0) { "+" } else { "" }
            $rsiStr = if (-not [double]::IsNaN($q.Rsi14)) { "{0:N1}" -f $q.Rsi14 } else { "-" }
            $distStr = if ($q.High52 -gt 0) { "{0:N1}%" -f ((($q.Price - $q.High52) / $q.High52) * 100.0) } else { "-" }
            $extStr = if ($q.ExtPrice -gt 0) { "{0}{1:N2}%" -f $(if ($q.ExtPct -ge 0) { "+" } else { "" }), $q.ExtPct } else { "-" }
            $ms = Get-MarketState -Tp $q.Tp -NowSec $nowSec
            $mStr = if ($null -ne $ms) { $ms.Short } else { "-" }
            $idx = $dgvWatchlist.Rows.Add(
                $uSym,
                "",
                ("{0:N2} {1}" -f $pConv, $curr),
                ("{0}{1:N2}%" -f $sign, $q.ChangePct),
                $extStr,
                $rsiStr,
                $distStr,
                $mStr
            )
            $row = $dgvWatchlist.Rows[$idx]
            $row.Cells["Day"].Style.ForeColor = if ($q.ChangePct -ge 0) { $colGreen } else { $colRed }
            if ([bool]$q.FromCache) {
                $row.Cells["Price"].Style.ForeColor = $script:Pal.Muted
                $row.Cells["Price"].ToolTipText = "Kurs aus dem Cache (Stand {0}) - wird gerade aktualisiert" -f $q.UpdatedAt.ToString("dd.MM. HH:mm")
            }
            if ($q.ExtPrice -gt 0) {
                $row.Cells["Ext"].Style.ForeColor = if ($q.ExtPct -ge 0) { $colGreen } else { $colRed }
                $row.Cells["Ext"].ToolTipText = "{0}: {1:N2} {2}" -f $(if ($q.ExtSession -eq "PRE") { "Vorbörse" } else { "Nachbörse" }), (Convert-CurrencyValue -Amount $q.ExtPrice -FromCurrency $q.Currency -ToCurrency $curr), $curr
            }
            if (-not [double]::IsNaN($q.Rsi14)) {
                if ($q.Rsi14 -ge $obVal) { $row.Cells["Rsi"].Style.ForeColor = $colRed }
                elseif ($q.Rsi14 -le $osVal) { $row.Cells["Rsi"].Style.ForeColor = $colGreen }
            }
            if ($null -ne $ms) {
                $row.Cells["Market"].Style.ForeColor = Get-MarketStateColor $ms.State
                $row.Cells["Market"].ToolTipText = Get-MarketHoursTooltip -Tp $q.Tp
            }
            if ($uSym -eq $script:Config.ActiveTicker.ToUpper()) {
                $row.Cells[0].Style.ForeColor = $script:Pal.Accent
            }
        } else {
            [void]$dgvWatchlist.Rows.Add($uSym, "", "...", "-", "-", "-", "-", "-")
        }
    }
    Restore-GridState -Grid $dgvWatchlist -State $gridState
    } finally {
        $script:SuppressGridSelection = $false
    }

    $alSel = $lstAlerts.SelectedIndex
    $lstAlerts.BeginUpdate()
    $lstAlerts.Items.Clear()
    foreach ($a in $script:Alerts) {
        [void]$lstAlerts.Items.Add((Format-AlertLine -Alert $a))
    }
    if ($script:Alerts.Count -eq 0) {
        # Empty state (v3.0). Index-based delete/toggle handlers check
        # idx < $script:Alerts.Count, so these lines can never be acted on.
        [void]$lstAlerts.Items.Add("Noch keine Alarme.")
        [void]$lstAlerts.Items.Add("Ticker, Bedingung, Wert -> '+'")
        [void]$lstAlerts.Items.Add("oder Rechtsklick in den Chart.")
        $alSel = -1
    }
    if ($alSel -ge 0 -and $alSel -lt $lstAlerts.Items.Count) { $lstAlerts.SelectedIndex = $alSel }
    $lstAlerts.EndUpdate()
}



function Get-AlertState {
    # Current value of what an alert watches + whether its condition is met.
    # Ok = $false when there is no data (yet) for the ticker.
    param($Alert)
    $res = @{ Ok = $false; Value = [double]::NaN; Met = $false; Text = "" }
    if (-not $script:QuoteStore.ContainsKey($Alert.Ticker)) { return $res }
    $q = $script:QuoteStore[$Alert.Ticker]
    # v4.0: never fire on a cached quote from the last session
    if ([bool]$q.FromCache) { return $res }
    $cond = [string]$Alert.Condition
    switch (Get-AlertKind $cond) {
        "PCT" {
            $v = [double]$q.ChangePct
            $op = $cond.Substring(4).Trim()
            $res.Ok = $true; $res.Value = $v
            $res.Met = ($op -eq ">=" -and $v -ge $Alert.TargetPrice) -or ($op -eq "<=" -and $v -le $Alert.TargetPrice)
            $res.Text = "Tagesänderung {0:+0.00;-0.00}% (Ziel {1} {2:N2}%)" -f $v, $op, $Alert.TargetPrice
        }
        "RSI" {
            $v = [double]$q.Rsi14
            if ([double]::IsNaN($v)) { return $res }
            $op = $cond.Substring(3).Trim()
            $res.Ok = $true; $res.Value = $v
            $res.Met = ($op -eq ">=" -and $v -ge $Alert.TargetPrice) -or ($op -eq "<=" -and $v -le $Alert.TargetPrice)
            $res.Text = "RSI-{0} (1h) {1:N1} (Ziel {2} {3:N1})" -f $script:Config.RsiPeriod, $v, $op, $Alert.TargetPrice
        }
        "SMA" {
            $sma = [double]$q.SmaFastH
            if ([double]::IsNaN($sma) -or $sma -le 0) { return $res }
            $dist = (([double]$q.Price / $sma) - 1.0) * 100.0
            $res.Ok = $true; $res.Value = $dist
            $res.Met = if ($cond -like ">*") { [double]$q.Price -gt $sma } else { [double]$q.Price -lt $sma }
            $res.Text = "Kurs {0:N2} vs. SMA{1} (1h) {2:N2} ({3:+0.00;-0.00}%)" -f $q.Price, $script:Config.SmaFastPeriod, $sma, $dist
        }
        default {
            $v = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $Alert.Currency
            $res.Ok = $true; $res.Value = $v
            $res.Met = ($cond -eq ">=" -and $v -ge $Alert.TargetPrice) -or ($cond -eq "<=" -and $v -le $Alert.TargetPrice)
            $res.Text = "Kurs {0:N2} {1} (Ziel {2} {3:N2})" -f $v, $Alert.Currency, $cond, $Alert.TargetPrice
        }
    }
    return $res
}


function Format-AlertLine {
    param($Alert)
    $flag = if ($Alert.Triggered) { "[HIT]" } else { "[ACT]" }
    $body = switch (Get-AlertKind $Alert.Condition) {
        "PCT"   { "{0} {1:N2}%" -f $Alert.Condition, $Alert.TargetPrice }
        "RSI"   { "{0} {1:N0}" -f $Alert.Condition, $Alert.TargetPrice }
        "SMA"   { "{0}{1}" -f $Alert.Condition, $script:Config.SmaFastPeriod }
        default { "{0} {1:N2} {2}" -f $Alert.Condition, $Alert.TargetPrice, $Alert.Currency }
    }
    $re = if ([int]$Alert.RearmMin -gt 0) { " (R{0})" -f (Format-RearmLabel ([int]$Alert.RearmMin)) } else { "" }
    $note = if ($Alert.Note) { " - " + $Alert.Note } else { "" }
    return ("{0} {1,-8} {2}{3}{4}" -f $flag, $Alert.Ticker, $body, $re, $note)
}

function Add-WidgetAlert {
    # Central place to create an alert (alert panel + chart context menu)
    param([string]$Ticker, [string]$Condition, [double]$Target, [string]$Currency, [string]$Note = "", [int]$RearmMin = 0, [switch]$NoConfirm)
    $a = [PSCustomObject]@{
        Id          = [Guid]::NewGuid().ToString("N")
        Ticker      = $Ticker.ToUpper()
        Condition   = $Condition
        TargetPrice = $Target
        Currency    = $Currency
        Triggered   = $false
        Note        = $Note
        RearmMin    = $RearmMin
        TriggeredAt = ""
    }
    if (-not $NoConfirm) {
        $st = Get-AlertState -Alert $a
        if ($st.Ok -and $st.Met -and -not (Confirm-Action -Text ("Bedingung ist bereits erfüllt:`r`n{0}`r`nAlarm würde sofort auslösen. Trotzdem anlegen?" -f $st.Text) -Title "Alarm")) {
            return $false
        }
    }
    $script:Alerts.Add($a)
    Save-JsonState -Path $script:AlertsPath -Data $script:Alerts.ToArray()
    return $true
}

function Evaluate-GlobalAlerts {
    $changed = $false
    $now = Get-Date
    foreach ($a in $script:Alerts) {
        $st = Get-AlertState -Alert $a
        if (-not $st.Ok) { continue }
        if ($a.Triggered) {
            # Re-arm: after the wait time AND once the condition is no longer met
            # (hysteresis - otherwise it would fire again on every poll)
            if ([int]$a.RearmMin -gt 0 -and -not $st.Met) {
                $at = [DateTime]::MinValue
                $okAt = [DateTime]::TryParse([string]$a.TriggeredAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$at)
                if (-not $okAt -or ($now - $at).TotalMinutes -ge [int]$a.RearmMin) {
                    $a.Triggered = $false
                    $changed = $true
                    Write-WidgetLog "Alert re-armed: $($a.Ticker) $($a.Condition)"
                }
            }
            continue
        }
        if ($st.Met) {
            $a.Triggered = $true
            $a.TriggeredAt = $now.ToString("o")
            $changed = $true
            Write-WidgetLog "Alert hit: $($a.Ticker) $($st.Text)"
            if ($script:Config.ShowTrayNotifications) {
                # v3.0: async system sound (Console.Beep blocked the UI thread
                # and throws on machines without a beep device)
                try { [System.Media.SystemSounds]::Exclamation.Play() } catch { }
                $msg = "{0}: {1}" -f $a.Ticker, $st.Text
                if ($a.Note) { $msg += "`r`n" + $a.Note }
                $trayIcon.ShowBalloonTip(6000, "Alarm: $($a.Ticker)", $msg, [System.Windows.Forms.ToolTipIcon]::Info)
            }
        }
    }
    if ($changed) {
        Save-JsonState -Path $script:AlertsPath -Data $script:Alerts.ToArray()
    }
}

# ------------------------------------------------------------------------------
# Market status line (refreshed every second by $uiTimer for the countdown)
# ------------------------------------------------------------------------------
$script:LastStatusTip   = ""
$script:LastPriceTip    = ""
$script:LastMarketState = @{}
$script:LastTrayIconKey = ""
$script:TrayIconHandle  = [IntPtr]::Zero

function Get-MarketStateColor {
    param([string]$State)
    switch ($State) {
        "REGULAR" { return $colGreen }
        "OPEN24"  { return $colGreen }
        "PRE"     { return [System.Drawing.Color]::FromArgb(245, 158, 11) }
        "POST"    { return [System.Drawing.Color]::FromArgb(168, 85, 247) }
        default   { return $script:Pal.Muted }
    }
}

function Update-MarketStatusUi {
    if ($script:IsClosing -or $form.IsDisposed) { return }
    $sym = $script:Config.ActiveTicker.ToUpper()
    $q = if ($script:QuoteStore.ContainsKey($sym)) { $script:QuoteStore[$sym] } else { $null }
    if ($null -eq $q -or $null -eq $q.Tp) {
        $lblMarketStatus.Text = ""
        return
    }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $ms = Get-MarketState -Tp $q.Tp -NowSec $now
    $dot = [string][char]0x25CF
    $left = [long]$ms.NextSec - $now
    $txt = switch ($ms.State) {
        "OPEN24"  { "$dot Handel 24/7" }
        "REGULAR" { "$dot Offen - zu in " + (Format-Duration $left) }
        "PRE"     { "$dot Pre - Handel in " + (Format-Duration $left) }
        "POST"    { "$dot Post - Ende in " + (Format-Duration $left) }
        default {
            $zu = if ($ms.Holiday) { "$dot Feiertag ($($ms.Holiday))" } else { "$dot Zu" }
            if ($left -lt 43200) { "$zu - öffnet in " + (Format-Duration $left) }
            else { "$zu - öffnet " + (Format-LocalTime $ms.NextSec) }
        }
    }
    if ($lblMarketStatus.Text -ne $txt) { $lblMarketStatus.Text = $txt }
    $lblMarketStatus.ForeColor = Get-MarketStateColor $ms.State

    $tip = Get-MarketHoursTooltip -Tp $q.Tp
    if ($ms.State -eq "CLOSED") { $tip += "`r`nNächste Eröffnung: " + (Format-LocalTime $ms.NextSec) }
    if ($tip -ne $script:LastStatusTip) {
        Set-DynTip $lblMarketStatus $tip $(if ($ms.Holiday) { "HOLIDAY" } else { "MARKET" })
        $script:LastStatusTip = $tip
    }
}

function Check-MarketOpenNotifications {
    # Balloon once per exchange when its regular session starts
    if (-not $script:Config.ShowTrayNotifications -or -not $script:Config.NotifyMarketOpen) { return }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $syms = New-Object System.Collections.Generic.List[string]
    $syms.Add($script:Config.ActiveTicker.ToUpper())
    foreach ($k in $script:Portfolio.Keys) { if (-not $syms.Contains($k)) { $syms.Add($k) } }
    $opened = @{}
    foreach ($sym in $syms) {
        if (-not $script:QuoteStore.ContainsKey($sym)) { continue }
        $q = $script:QuoteStore[$sym]
        if ($null -eq $q.Tp -or $q.Tp.Is247) { continue }
        $key = if ($q.Tp.Exchange) { $q.Tp.Exchange } else { "{0}|{1}" -f $q.Tp.TzName, $q.Tp.RegStartTod }
        $st = (Get-MarketState -Tp $q.Tp -NowSec $now).State
        if ($opened.ContainsKey($key)) { $opened[$key] += ", $sym"; continue }
        if ($script:LastMarketState.ContainsKey($key) -and $script:LastMarketState[$key] -ne "REGULAR" -and $st -eq "REGULAR") {
            $opened[$key] = $sym
        }
        $script:LastMarketState[$key] = $st
    }
    foreach ($k in $opened.Keys) {
        $trayIcon.ShowBalloonTip(5000, "Handelsstart: $k", "Regulärer Handel hat begonnen ($($opened[$k]))", [System.Windows.Forms.ToolTipIcon]::Info)
    }
}

function Update-TrayIcon {
    # Small up/down triangle in the tray & title bar instead of the generic app icon
    param([string]$Key)
    if ($Key -eq $script:LastTrayIconKey) { return }
    $script:LastTrayIconKey = $Key
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)
        $colr = switch ($Key) { "up" { $colGreen } "down" { $colRed } default { [System.Drawing.Color]::FromArgb(148, 163, 184) } }
        $br = New-Object System.Drawing.SolidBrush($colr)
        if ($Key -eq "up") {
            $g.FillPolygon($br, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF(8, 1)), (New-Object System.Drawing.PointF(15, 14)), (New-Object System.Drawing.PointF(1, 14))))
        } elseif ($Key -eq "down") {
            $g.FillPolygon($br, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF(1, 2)), (New-Object System.Drawing.PointF(15, 2)), (New-Object System.Drawing.PointF(8, 15))))
        } else {
            $g.FillEllipse($br, 2, 2, 12, 12)
        }
        $br.Dispose()
    } finally { $g.Dispose() }
    $hIcon = $bmp.GetHicon()
    $bmp.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $oldHandle = $script:TrayIconHandle
    $trayIcon.Icon = $icon
    $form.Icon = $icon
    $script:TrayIconHandle = $hIcon
    if ($oldHandle -ne [IntPtr]::Zero) { [void][Win32WidgetHelperV26]::DestroyIcon($oldHandle) }
}

$script:LastFxTip = ""
function Get-RelevantFxPairs {
    # Every currency in use (display, portfolio, quotes) against the display
    # currency, in market convention (EUR/USD, EUR/CHF, USD/CHF, ...)
    $disp = [string]$script:Config.Currency
    $used = New-Object System.Collections.Generic.HashSet[string]
    foreach ($c in @("USD", "CHF", "EUR")) { [void]$used.Add($c) }
    foreach ($p in $script:Portfolio.Values) { if ($p.Currency) { [void]$used.Add([string]$p.Currency) } }
    foreach ($q in $script:QuoteStore.Values) { if ($q.Currency) { [void]$used.Add([string]$q.Currency) } }
    [void]$used.Remove($disp)
    $prio = @{ "USD" = 0; "EUR" = 1; "CHF" = 2; "GBP" = 3 }
    $ordered = @($used | Sort-Object @{ Expression = { if ($prio.ContainsKey($_)) { $prio[$_] } else { 9 } } }, @{ Expression = { $_ } })
    $rDisp = if ($script:FxFromEur.ContainsKey($disp)) { [double]$script:FxFromEur[$disp] } else { 0.0 }
    $out = @()
    foreach ($c in $ordered) {
        if (-not $script:FxFromEur.ContainsKey($c) -or $rDisp -le 0) { continue }
        $rC = [double]$script:FxFromEur[$c]
        if ($rC -le 0) { continue }
        if ($disp -eq "EUR")   { $pair = "EUR/$c";    $rate = $rC }
        elseif ($c -eq "EUR")  { $pair = "EUR/$disp"; $rate = $rDisp }
        else                   { $pair = "$c/$disp";  $rate = $rDisp / $rC }
        $out += [PSCustomObject]@{ Pair = $pair; Rate = $rate; Live = ($script:FxLive.Contains($c) -and $script:FxLive.Contains($disp)) }
    }
    return $out
}

function Update-StatusLine {
    # Called by every UI update AND by the 1-second timer, so transient messages
    # expire on time and the "Stand" age colour stays current.
    if ($script:IsClosing -or $form.IsDisposed) { return }
    $p = $script:Pal
    $amber = [System.Drawing.Color]::FromArgb(245, 158, 11)
    $fxMissingList = @($script:FxMissing | Where-Object { $_ -and $_ -ne "EUR" -and -not $script:FxLive.Contains($_) } | Sort-Object)
    if ($script:TransientStatus -and (Get-Date) -lt $script:TransientUntil) {
        $txt = $script:TransientStatus; $colr = $amber
    } elseif (-not [string]::IsNullOrWhiteSpace($script:LastFetchWarning)) {
        # v4.0: offline = red, partial errors / rate limit = amber
        $txt = $script:LastFetchWarning
        $colr = if ($script:LastFetchOffline) { $colRed } else { $amber }
    } elseif ($fxMissingList.Count -gt 0) {
        $txt = "Kein Live-FX: " + ($fxMissingList -join ", ") + " (Werte ungenau)"; $colr = $amber
    } else {
        # Rates that matter for the display currency (was: always USD + CHF)
        $pairs = @(Get-RelevantFxPairs)
        $shown = @($pairs | Select-Object -First 3 | ForEach-Object { "{0} {1:N4}" -f $_.Pair, $_.Rate })
        # Time of the last successful refresh, NOT a clock
        $stand = if ($null -ne $script:LastDataTime) { $script:LastDataTime.ToString("HH:mm:ss") } else { "--:--:--" }
        $txt = if ($shown.Count -gt 0) { ($shown -join " | ") + " | Stand $stand" } else { "Stand $stand" }
        $tip = "Wechselkurse (Anzeige in $($script:Config.Currency)):"
        foreach ($fp in $pairs) { $tip += "`r`n  {0,-8} {1:N4}{2}" -f $fp.Pair, $fp.Rate, $(if ($fp.Live) { "" } else { "  (Fallback)" }) }
        $tip += "`r`nStand = Uhrzeit der letzten erfolgreichen Datenaktualisierung (gelb = veraltet)"
        if ($tip -ne $script:LastFxTip) { Set-DynTip $lblStatus $tip "FX"; $script:LastFxTip = $tip }
        # v4.0: amber after 2 intervals, red when very old (see Get-StalenessLevel)
        $age = if ($null -eq $script:LastDataTime) { [double]::NaN } else { ((Get-Date) - $script:LastDataTime).TotalSeconds }
        $lvl = Get-StalenessLevel -AgeSec $age -RefreshSec ([int]$script:Config.RefreshSeconds)
        $colr = switch ($lvl) { "ERR" { $colRed } "WARN" { $amber } default { $p.Muted } }
    }
    # v4.0: explain a rate-limit pause / offline state when hovering the status
    $warnKey = if ($script:LastRateLimited -and $txt -eq $script:LastFetchWarning) { "RATELIMIT" } elseif ($txt -eq $script:LastFetchWarning -and $txt) { "STAND" } else { "" }
    if ($warnKey -and $script:LastFxTip -ne "warn:$warnKey") { Set-DynTip $lblStatus $txt $warnKey; $script:LastFxTip = "warn:$warnKey" }
    if ($lblStatus.Text -ne $txt) { $lblStatus.Text = $txt }
    if ($lblStatus.ForeColor -ne $colr) { $lblStatus.ForeColor = $colr }
}

function Update-AllUiViews {
    if ($script:IsClosing -or $form.IsDisposed) { return }
    $sym  = $script:Config.ActiveTicker.ToUpper()
    $curr = $script:Config.Currency
    $p    = $script:Pal
    $btnCurrency.Text = "$curr $script:DropArrow"

    if (-not $txtSearch.Focused) {
        $script:SuppressSearchEvent = $true
        $txtSearch.Text = $sym
        $script:SuppressSearchEvent = $false
    }

    foreach ($k in $tfButtons.Keys) {
        $btn = $tfButtons[$k]
        if ($k -eq $script:Config.Timeframe) {
            Style-FlatButton -Btn $btn -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
        } else {
            Style-FlatButton -Btn $btn -BgColor $p.Card -FgColor $p.Text -BorderColor $p.Border
        }
    }

    $togglePairs = @(
        @{ Btn = $btnChartType;  Active = ($script:Config.ChartType -eq "Candle") },
        @{ Btn = $btnToggleVol;  Active = [bool]$script:Config.ShowVolume },
        @{ Btn = $btnToggleSma;  Active = [bool]$script:Config.ShowSma },
        @{ Btn = $btnToggleVwap; Active = [bool]$script:Config.ShowVwap },
        @{ Btn = $btnToggleBb;   Active = [bool]$script:Config.ShowBollinger },
        @{ Btn = $btnToggleRsi;  Active = [bool]$script:Config.ShowRsi },
        @{ Btn = $btnToggleExt;  Active = [bool]$script:Config.ShowExtended }
    )
    foreach ($tp in $togglePairs) {
        if ($tp.Active) {
            Style-FlatButton -Btn $tp.Btn -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
        } else {
            Style-FlatButton -Btn $tp.Btn -BgColor $p.Card -FgColor $p.Text -BorderColor $p.Border
        }
    }

    if ($script:QuoteStore.ContainsKey($sym)) {
        $q = $script:QuoteStore[$sym]
        $dispPrice = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $curr
        $sign = if ($q.ChangePct -ge 0) { "+" } else { "" }
        $col  = if ($q.ChangePct -ge 0) { $colGreen } else { $colRed }

        $lblLivePrice.Text = "{0:N2} {1}" -f $dispPrice, $curr
        # v4.0: a quote from the cache of the last session is shown grey
        $fromCache = [bool]$q.FromCache
        $lblLivePrice.ForeColor = if ($fromCache) { $p.Muted } else { $p.Text }
        $priceTip = if ($fromCache) { "Kurs aus dem Cache (Stand {0}) - wird gerade aktualisiert" -f $q.UpdatedAt.ToString("dd.MM. HH:mm") } else { "Doppelklick = Kurs kopieren" }
        if ($priceTip -ne $script:LastPriceTip) { Set-Tip $lblLivePrice $priceTip $(if ($fromCache) { "CACHE" } else { "PRICE" }); $script:LastPriceTip = $priceTip }
        $lblDayChange.ForeColor = $col
        $lblDayChange.Text = "{0}{1:N2}%" -f $sign, $q.ChangePct
        $dispPrev = Convert-CurrencyValue -Amount $q.PrevClose -FromCurrency $q.Currency -ToCurrency $curr
        $lblDayAbs.Text = if ($q.PrevClose -gt 0) { "{0}{1:N2} {2}" -f $sign, ($dispPrice - $dispPrev), $curr } else { "" }
        $lblHeaderName.Text = "{0} ({1})" -f $q.LongName, $q.Currency

        # Pre-/after-market quote below the price
        if ($q.ExtPrice -gt 0) {
            $extDisp = Convert-CurrencyValue -Amount $q.ExtPrice -FromCurrency $q.Currency -ToCurrency $curr
            $eSign = if ($q.ExtPct -ge 0) { "+" } else { "" }
            $eLbl  = if ($q.ExtSession -eq "PRE") { "Pre" } else { "Post" }
            $lblExtQuote.Text = "{0} {1:N2} {2}{3:N2}%" -f $eLbl, $extDisp, $eSign, $q.ExtPct
            $lblExtQuote.ForeColor = if ($q.ExtPct -ge 0) { $colGreen } else { $colRed }
            $eWhen = [DateTimeOffset]::FromUnixTimeSeconds([long]$q.ExtTs).ToLocalTime().ToString("ddd HH:mm")
            Set-DynTip $lblExtQuote ("{0} {1:N2} {2} ({3}{4:N2}% vs. Schluss) - Stand {5}" -f $(if ($q.ExtSession -eq "PRE") { "Vorbörse" } else { "Nachbörse" }), $extDisp, $curr, $eSign, $q.ExtPct, $eWhen) "EXT"
        } else {
            $lblExtQuote.Text = ""
        }

        $ms = Get-MarketState -Tp $q.Tp -NowSec ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        $stateTxt = if ($null -ne $ms) { " " + $ms.Short } else { "" }
        $tt = "{0}: {1:N2} {2} ({3}{4:N2}%){5}" -f $sym, $dispPrice, $curr, $sign, $q.ChangePct, $stateTxt
        $trayIcon.Text = if ($tt.Length -gt 63) { $tt.Substring(0, 63) } else { $tt }
        Update-TrayIcon -Key $(if ($q.ChangePct -ge 0) { "up" } else { "down" })
    } else {
        $lblLivePrice.Text = "--.-- $curr"
        $lblDayChange.ForeColor = $p.Muted
        $lblDayChange.Text = "0.00%"
        $lblDayAbs.Text = ""
        $lblExtQuote.Text = ""
        $lblHeaderName.Text = $sym
        Update-TrayIcon -Key "none"
    }
    Update-MarketStatusUi

    Update-StatusLine

    # Hidden in tray: only header/tray tooltip matter, skip the grid rebuilds.
    # v3.0: only the VISIBLE tab is rebuilt; Set-ActiveTab refreshes a tab
    # when it is shown.
    if ($form.Visible) { Update-VisibleTabContent }
    if ([bool]$script:Config.CompactMode) { Update-TickerTape }
    # Static chart bitmap is only re-rendered when its content really changed
    Update-ChartCacheSignature
    $pnlChartCanvas.Invalidate()
    $picCompactSpark.Invalidate()
    if ($null -ne $script:FsCanvas -and -not $script:FsCanvas.IsDisposed) { $script:FsCanvas.Invalidate() }
}

function Switch-ActiveTicker {
    param([string]$NewTicker, [bool]$SkipResolve = $false)
    $raw = $NewTicker.Trim().ToUpper()
    if ([string]::IsNullOrWhiteSpace($raw)) { return }

    $lstTickerDropdown.Visible   = $false
    $lstWlSearchDropdown.Visible = $false

    if (-not $SkipResolve) {
        $known = Get-KnownSymbol -Raw $raw
        if ($known) { $raw = $known; $SkipResolve = $true }
    }
    if (-not $SkipResolve) {
        # v3.0: unknown input is resolved in the background (was: synchronous
        # lookup + DoEvents). A newer switch supersedes this one via ResolveSeq.
        $script:ResolveSeq++
        $lblHeaderName.Text = "Suche $raw..."
        $u = Get-ResolveUrls -Clean $raw
        Start-FetchJob -Urls @($u.Probe, $u.Search) -MaxConcurrency 2 -Context @{ Raw = $raw; Seq = $script:ResolveSeq; Probe = $u.Probe; Search = $u.Search } -OnComplete {
            param($Box, $Ctx)
            if ($Ctx.Seq -ne $script:ResolveSeq) { return }
            $sym = Complete-SymbolResolve -Clean $Ctx.Raw -ProbeJson $Box.Results[$Ctx.Probe] -SearchJson $Box.Results[$Ctx.Search]
            if ($null -eq $Box.Results[$Ctx.Probe] -and $null -eq $Box.Results[$Ctx.Search]) {
                Set-TransientStatus "Symbolsuche nicht erreichbar - verwende '$($Ctx.Raw)'" 4
            }
            if ($sym) { Switch-ActiveTicker -NewTicker $sym -SkipResolve $true }
        }
        return
    }
    $script:ResolveSeq++   # a direct switch cancels a pending background lookup
    $clean = $raw

    $script:Config.ActiveTicker = $clean
    $script:ActiveSeries        = @()
    $script:ActiveLoadError     = ""
    $lblHeaderName.Text         = "Lade $clean..."
    $script:HoverIndex          = -1
    Update-ChartCacheSignature
    $pnlChartCanvas.Invalidate()

    $script:SuppressSearchEvent = $true
    $txtSearch.Text = $clean
    $script:SuppressSearchEvent = $false

    $txtAlertTicker.Text = $clean
    $txtPortTicker.Text  = $clean
    if ($script:Portfolio.ContainsKey($clean)) {
        $p = $script:Portfolio[$clean]
        $txtPortShares.Text = $p.Shares.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        $txtPortAvg.Text    = $p.AvgPrice.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        Select-CurrencyInCombo -Combo $cmbPortCurr -Code $p.Currency
        $txtPortBuyAmt.Text = if ($p.BuyAmount -gt 0) { $p.BuyAmount.ToString([System.Globalization.CultureInfo]::InvariantCulture) } else { "" }
        $txtPortTarget.Text = if ($p.TargetAvg -gt 0) { $p.TargetAvg.ToString([System.Globalization.CultureInfo]::InvariantCulture) } else { "" }
    } else {
        $txtPortShares.Text = ""; $txtPortAvg.Text = ""; $txtPortBuyAmt.Text = ""; $txtPortTarget.Text = ""
        $cIdx = $cmbPortCurr.Items.IndexOf($script:Config.Currency)
        if ($cIdx -ge 0) { $cmbPortCurr.SelectedIndex = $cIdx }
    }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Refresh-AllMarketData
    Update-AllUiViews
}

# ==============================================================================
# Events & Keyboard Shortcuts
# ==============================================================================
foreach ($k in $tabButtons.Keys) {
    $tabButtons[$k].Add_Click({
        param($sender, $e)
        Set-ActiveTab -TabName ([string]$sender.Tag)
    })
}

foreach ($k in $tfButtons.Keys) {
    $tfButtons[$k].Add_Click({
        param($sender, $e)
        Set-Timeframe -Tf ([string]$sender.Tag)
    })
}

$btnChartType.Add_Click({
    $script:Config.ChartType = if ($script:Config.ChartType -eq "Candle") { "Line" } else { "Candle" }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

$btnToggleVol.Add_Click({
    $script:Config.ShowVolume = -not $script:Config.ShowVolume
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

$btnToggleSma.Add_Click({
    $script:Config.ShowSma = -not $script:Config.ShowSma
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

$btnToggleVwap.Add_Click({
    $script:Config.ShowVwap = -not $script:Config.ShowVwap
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

$btnToggleBb.Add_Click({
    $script:Config.ShowBollinger = -not $script:Config.ShowBollinger
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

$btnToggleRsi.Add_Click({
    $script:Config.ShowRsi = -not $script:Config.ShowRsi
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

function Toggle-ExtendedHours {
    $script:Config.ShowExtended = -not [bool]$script:Config.ShowExtended
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    if ($script:Config.Timeframe -ne "1d") {
        Set-TransientStatus ("Vor-/Nachbörse {0} (wirkt im 1D-Chart)" -f $(if ($script:Config.ShowExtended) { "an" } else { "aus" })) 4
        Update-AllUiViews
        return
    }
    $script:ActiveSeries = @()
    Update-AllUiViews
    Refresh-AllMarketData
    Update-AllUiViews
}

# ------------------------------------------------------------------------------
# Transactions (v2.9): buy / sell / dividend with realized P/L. Amounts are in
# the position currency; realized P/L is converted with the CURRENT FX rate.
# ------------------------------------------------------------------------------
function Save-Transactions {
    Save-JsonState -Path $script:TransactionsPath -Data $script:Transactions.ToArray()
}

function Add-TransactionRecord {
    param([string]$Type, [string]$Ticker, [double]$Shares, [double]$Price, [double]$Fee, [string]$Currency, [string]$Date, [double]$Realized = 0.0, [string]$Note = "")
    $script:Transactions.Add([PSCustomObject]@{
        Id       = [Guid]::NewGuid().ToString("N")
        Date     = if ($Date) { $Date } else { (Get-Date).ToString("yyyy-MM-dd") }
        Ticker   = $Ticker.ToUpper()
        Type     = $Type
        Shares   = $Shares
        Price    = $Price
        Fee      = $Fee
        Currency = $Currency
        Realized = $Realized
        Note     = $Note
    })
    Save-Transactions
}

function Get-RealizedTotal {
    # Sum of realized P/L in the display currency (optionally one year only)
    param([int]$Year = 0)
    $curr = $script:Config.Currency
    $sum = 0.0
    foreach ($t in $script:Transactions) {
        if ($Year -gt 0 -and -not ([string]$t.Date).StartsWith([string]$Year)) { continue }
        if ([double]$t.Realized -ne 0) { $sum += Convert-CurrencyValue -Amount $t.Realized -FromCurrency $t.Currency -ToCurrency $curr }
    }
    return $sum
}

function Invoke-Transaction {
    # Applies a transaction to the position and logs it. Returns an error text or "".
    param([string]$Type, [string]$Ticker, [double]$Shares, [double]$Price, [double]$Fee, [string]$Currency, [string]$Date, [string]$Note)
    $sym = $Ticker.ToUpper()
    $pos = if ($script:Portfolio.ContainsKey($sym)) { $script:Portfolio[$sym] } else { $null }
    switch ($Type) {
        "Kauf" {
            if ($Shares -le 0 -or $Price -le 0) { return "Stück und Kurs müssen größer als 0 sein." }
            if ($null -eq $pos) {
                $avg = (($Shares * $Price) + $Fee) / $Shares
                $script:Portfolio[$sym] = [PSCustomObject]@{ Ticker = $sym; Shares = $Shares; AvgPrice = $avg; Currency = $Currency; BuyAmount = 0.0; TargetAvg = 0.0 }
            } else {
                # buy in the position currency (cost basis incl. fees)
                $px  = Convert-CurrencyValue -Amount $Price -FromCurrency $Currency -ToCurrency $pos.Currency
                $fee = Convert-CurrencyValue -Amount $Fee -FromCurrency $Currency -ToCurrency $pos.Currency
                $newSh = $pos.Shares + $Shares
                $pos.AvgPrice = (($pos.Shares * $pos.AvgPrice) + ($Shares * $px) + $fee) / $newSh
                $pos.Shares = $newSh
                $Currency = $pos.Currency; $Price = $px; $Fee = $fee
            }
            Add-TransactionRecord -Type "Kauf" -Ticker $sym -Shares $Shares -Price $Price -Fee $Fee -Currency $Currency -Date $Date -Note $Note
        }
        "Verkauf" {
            if ($null -eq $pos) { return "Keine Position '$sym' vorhanden." }
            if ($Shares -le 0 -or $Price -le 0) { return "Stück und Kurs müssen größer als 0 sein." }
            if ($Shares -gt ($pos.Shares + 0.000001)) { return ("Nur {0:N4} Stück im Bestand." -f $pos.Shares) }
            $px  = Convert-CurrencyValue -Amount $Price -FromCurrency $Currency -ToCurrency $pos.Currency
            $fee = Convert-CurrencyValue -Amount $Fee -FromCurrency $Currency -ToCurrency $pos.Currency
            $realized = (($px - $pos.AvgPrice) * $Shares) - $fee
            $pos.Shares = $pos.Shares - $Shares
            Add-TransactionRecord -Type "Verkauf" -Ticker $sym -Shares $Shares -Price $px -Fee $fee -Currency $pos.Currency -Date $Date -Realized $realized -Note $Note
            if ($pos.Shares -le 0.000001) { $script:Portfolio.Remove($sym) }
        }
        "Dividende" {
            if ($Price -le 0) { return "Bitte den Dividendenbetrag (gesamt, brutto) als 'Betrag' eingeben." }
            $tc = if ($null -ne $pos) { $pos.Currency } else { $Currency }
            $amt = Convert-CurrencyValue -Amount $Price -FromCurrency $Currency -ToCurrency $tc
            $fee = Convert-CurrencyValue -Amount $Fee -FromCurrency $Currency -ToCurrency $tc
            Add-TransactionRecord -Type "Dividende" -Ticker $sym -Shares $Shares -Price $amt -Fee $fee -Currency $tc -Date $Date -Realized ($amt - $fee) -Note $Note
        }
        default { return "Unbekannter Typ '$Type'." }
    }
    Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
    return ""
}

function New-DialogForm {
    param([string]$Title, [int]$W, [int]$H)
    $p = $script:Pal
    $d = New-Object System.Windows.Forms.Form
    $d.Text = $Title
    $d.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.ShowInTaskbar = $false
    $d.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $d.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $d.BackColor = $p.BodyBg; $d.ForeColor = $p.Text; $d.Font = $fontUi
    $d.TopMost = $form.TopMost
    $d.ClientSize = New-Object System.Drawing.Size($W, $H)
    return $d
}

function Show-TransactionDialog {
    param([string]$Ticker = "")
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Transaktion erfassen" -W (S 360) -H (S 330)
    $rowY = @{ Y = (S 14) }
    $addRow = {
        param([string]$Label, [System.Windows.Forms.Control]$Ctl)
        $l = New-Object System.Windows.Forms.Label
        $l.SetBounds((S 14), ($rowY.Y + (S 3)), (S 120), (S 18))
        $l.Text = $Label
        $dlg.Controls.Add($l)
        $Ctl.SetBounds((S 140), $rowY.Y, (S 204), (S 24))
        $dlg.Controls.Add($Ctl)
        $rowY.Y += S 32
    }
    $newTb = {
        param([string]$Text)
        $t = New-Object System.Windows.Forms.TextBox
        $t.BackColor = $p.Input; $t.ForeColor = $p.Text; $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle; $t.Font = $fontMono
        $t.Text = $Text
        return $t
    }
    $cbType = New-Object System.Windows.Forms.ComboBox
    $cbType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbType.BackColor = $p.Input; $cbType.ForeColor = $p.Text; $cbType.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    foreach ($tt in @("Kauf", "Verkauf", "Dividende")) { [void]$cbType.Items.Add($tt) }
    $cbType.SelectedIndex = 0
    & $addRow "Typ" $cbType

    $dtp = New-Object System.Windows.Forms.DateTimePicker
    $dtp.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
    $dtp.Value = Get-Date
    & $addRow "Datum" $dtp

    $tbSym = & $newTb $Ticker.ToUpper()
    & $addRow "Ticker" $tbSym
    $tbSh  = & $newTb ""
    & $addRow "Stück" $tbSh
    $tbPx  = & $newTb ""
    & $addRow "Kurs je Stück" $tbPx
    $lblPx = $dlg.Controls[$dlg.Controls.Count - 2]
    $tbFee = & $newTb ""
    & $addRow "Gebühren" $tbFee

    $cbCur = New-Object System.Windows.Forms.ComboBox
    $cbCur.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbCur.BackColor = $p.Input; $cbCur.ForeColor = $p.Accent; $cbCur.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    foreach ($cc in (Get-DisplayCurrencies)) { [void]$cbCur.Items.Add($cc) }
    $preCur = if ($Ticker -and $script:Portfolio.ContainsKey($Ticker.ToUpper())) { $script:Portfolio[$Ticker.ToUpper()].Currency } else { $script:Config.Currency }
    $cbCur.SelectedIndex = 0
    Select-CurrencyInCombo -Combo $cbCur -Code $preCur
    & $addRow "Währung" $cbCur

    $tbNote = & $newTb ""
    & $addRow "Notiz" $tbNote

    $info = New-Object System.Windows.Forms.Label
    $info.SetBounds((S 14), $rowY.Y, (S 330), (S 32))
    $info.ForeColor = $p.Muted
    $dlg.Controls.Add($info)

    $script:TxDlg = @{ Dlg = $dlg; Type = $cbType; Sym = $tbSym; Sh = $tbSh; Px = $tbPx; Fee = $tbFee; Cur = $cbCur; Note = $tbNote; Date = $dtp; Info = $info; LblPx = $lblPx }
    $cbType.Add_SelectedIndexChanged({
        $t = $script:TxDlg
        $isDiv = ([string]$t.Type.SelectedItem -eq "Dividende")
        $t.LblPx.Text = if ($isDiv) { "Betrag gesamt" } else { "Kurs je Stück" }
        $t.Info.Text = switch ([string]$t.Type.SelectedItem) {
            "Kauf"      { "Kauf erhöht den Bestand; der EK wird inkl. Gebühren neu berechnet." }
            "Verkauf"   { "Realisierter G/V = (Kurs - EK) x Stück - Gebühren." }
            "Dividende" { "Stück optional. Betrag brutto; Gebühren/Steuern werden abgezogen." }
        }
    })
    $cbType.SelectedIndex = 1; $cbType.SelectedIndex = 0   # fire once for the info text

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.SetBounds((S 154), ($rowY.Y + (S 40)), (S 92), (S 28))
    Style-FlatButton -Btn $btnOk -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnOk.Text = "Buchen"
    $btnOk.Add_Click({
        $t = $script:TxDlg
        foreach ($tb in @($t.Sh, $t.Px, $t.Fee)) {
            if (-not (Test-DecimalInput $tb.Text)) { $t.Info.ForeColor = $colRed; $t.Info.Text = "Ungültige Zahl: '$($tb.Text)'"; return }
        }
        if ([string]::IsNullOrWhiteSpace($t.Sym.Text)) { $t.Info.ForeColor = $colRed; $t.Info.Text = "Bitte einen Ticker eingeben."; return }
        $sym = $t.Sym.Text.Trim().ToUpper()
        if (-not $script:Portfolio.ContainsKey($sym)) { $sym = Resolve-BestSymbol -RawInput $sym }
        $err = Invoke-Transaction -Type ([string]$t.Type.SelectedItem) -Ticker $sym -Shares (Parse-DecimalInput $t.Sh.Text) -Price (Parse-DecimalInput $t.Px.Text) `
            -Fee (Parse-DecimalInput $t.Fee.Text) -Currency ([string]$t.Cur.SelectedItem) -Date ($t.Date.Value.ToString("yyyy-MM-dd")) -Note $t.Note.Text.Trim()
        if ($err) { $t.Info.ForeColor = $colRed; $t.Info.Text = $err; return }
        $t.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $t.Dlg.Close()
    })
    $dlg.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.SetBounds((S 252), ($rowY.Y + (S 40)), (S 92), (S 28))
    Style-FlatButton -Btn $btnCancel -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $btnCancel.Text = "Abbrechen"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCancel)
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel
    $dlg.ClientSize = New-Object System.Drawing.Size((S 360), ($rowY.Y + (S 82)))

    $res = $dlg.ShowDialog($form)
    $script:TxDlg = $null
    $dlg.Dispose()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-TransientStatus "Transaktion gebucht" 3
        Refresh-AllMarketData
        Update-AllUiViews
    }
}

function Show-TransactionHistory {
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Transaktionshistorie" -W (S 760) -H (S 440)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 600), (S 300))

    $cbFilter = New-Object System.Windows.Forms.ComboBox
    $cbFilter.SetBounds((S 12), (S 10), (S 140), (S 24))
    $cbFilter.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbFilter.BackColor = $p.Input; $cbFilter.ForeColor = $p.Text; $cbFilter.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    [void]$cbFilter.Items.Add("Alle Ticker")
    foreach ($tk in @($script:Transactions | ForEach-Object { $_.Ticker } | Sort-Object -Unique)) { [void]$cbFilter.Items.Add($tk) }
    $cbFilter.SelectedIndex = 0
    $dlg.Controls.Add($cbFilter)

    $lblSum = New-Object System.Windows.Forms.Label
    $lblSum.SetBounds((S 164), (S 13), (S 584), (S 20))
    $lblSum.Font = $fontMono
    $lblSum.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $dlg.Controls.Add($lblSum)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.SetBounds((S 12), (S 42), (S 736), (S 346))
    $grid.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    Style-DataGrid -Grid $grid
    foreach ($cd in @(@("Date", "Datum", 84), @("Type", "Typ", 72), @("Ticker", "Ticker", 72), @("Shares", "Stück", 70), @("Price", "Kurs/Betrag", 86),
                      @("Fee", "Gebühr", 64), @("Cur", "Whg", 44), @("Real", "Realisiert", 92), @("Note", "Notiz", 120), @("Id", "Id", 10))) {
        $ci = $grid.Columns.Add($cd[0], $cd[1])
        $grid.Columns[$ci].Width = S $cd[2]
        $grid.Columns[$ci].FillWeight = [float](S $cd[2])
    }
    $grid.Columns["Id"].Visible = $false
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dlg.Controls.Add($grid)

    $btnDel = New-Object System.Windows.Forms.Button
    $btnDel.SetBounds((S 12), (S 398), (S 120), (S 28))
    $btnDel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    Style-FlatButton -Btn $btnDel -BgColor $p.Input -FgColor $colRed -BorderColor $p.Border
    $btnDel.Text = "Eintrag löschen"
    $dlg.Controls.Add($btnDel)
    $btnCsv = New-Object System.Windows.Forms.Button
    $btnCsv.SetBounds((S 140), (S 398), (S 110), (S 28))
    $btnCsv.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    Style-FlatButton -Btn $btnCsv -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $btnCsv.Text = "CSV export"
    $dlg.Controls.Add($btnCsv)
    # v3.0: rebuild the position of the selected / filtered ticker from its bookings
    $btnRebuild = New-Object System.Windows.Forms.Button
    $btnRebuild.SetBounds((S 258), (S 398), (S 170), (S 28))
    $btnRebuild.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    Style-FlatButton -Btn $btnRebuild -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnRebuild.Text = "Position neu berechnen"
    $dlg.Controls.Add($btnRebuild)
    # v4.0: yearly report (realized G/V + dividends at the FX rate of each booking date)
    $btnReport = New-Object System.Windows.Forms.Button
    $btnReport.SetBounds((S 436), (S 398), (S 130), (S 28))
    $btnReport.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    Style-FlatButton -Btn $btnReport -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnReport.Text = "Jahresreport..."
    $btnReport.Add_Click({ Show-YearReport -Owner $script:TxHist.Dlg })
    $dlg.Controls.Add($btnReport)
    Set-DynTip $btnReport "Realisierte G/V und Dividenden eines Jahres, mit dem Wechselkurs am Buchungstag" "REPORT"
    Set-DynTip $btnRebuild "Bestand und EK des markierten (oder gefilterten) Tickers aus allen Kauf-/Verkaufsbuchungen neu berechnen - mit Vorschau" "REBUILD"
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.SetBounds((S 638), (S 398), (S 110), (S 28))
    $btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    Style-FlatButton -Btn $btnClose -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnClose.Text = "Schließen"
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnClose)
    $dlg.CancelButton = $btnClose

    $script:TxHist = @{ Grid = $grid; Filter = $cbFilter; Sum = $lblSum; Dlg = $dlg }
    $fill = {
        $h = $script:TxHist
        $flt = [string]$h.Filter.SelectedItem
        $curr = $script:Config.Currency
        $h.Grid.Rows.Clear()
        $sumAll = 0.0; $sumYear = 0.0
        $yr = [string](Get-Date).Year
        foreach ($t in @($script:Transactions | Sort-Object Date -Descending)) {
            if ($flt -ne "Alle Ticker" -and $t.Ticker -ne $flt) { continue }
            $realDisp = if ([double]$t.Realized -ne 0) { Convert-CurrencyValue -Amount $t.Realized -FromCurrency $t.Currency -ToCurrency $curr } else { 0.0 }
            $sumAll += $realDisp
            if (([string]$t.Date).StartsWith($yr)) { $sumYear += $realDisp }
            $ri = $h.Grid.Rows.Add($t.Date, $t.Type, $t.Ticker, ("{0:N4}" -f $t.Shares), ("{0:N2}" -f $t.Price), ("{0:N2}" -f $t.Fee), $t.Currency,
                $(if ([double]$t.Realized -ne 0) { "{0:+0.00;-0.00}" -f $t.Realized } else { "" }), $t.Note, $t.Id)
            if ([double]$t.Realized -ne 0) { $h.Grid.Rows[$ri].Cells["Real"].Style.ForeColor = if ($t.Realized -ge 0) { $colGreen } else { $colRed } }
        }
        $h.Sum.Text = "Realisiert {0}: {1:+0.00;-0.00} {2}  |  gesamt: {3:+0.00;-0.00} {2}  (zum aktuellen Kurs umgerechnet)" -f $yr, $sumYear, $curr, $sumAll
        $h.Sum.ForeColor = if ($sumAll -ge 0) { $colGreen } else { $colRed }
    }
    $script:TxHist.Fill = $fill
    $cbFilter.Add_SelectedIndexChanged({ & $script:TxHist.Fill })
    $btnDel.Add_Click({
        $h = $script:TxHist
        if ($h.Grid.SelectedRows.Count -eq 0) { return }
        $id = [string]$h.Grid.SelectedRows[0].Cells["Id"].Value
        $delSym = [string]$h.Grid.SelectedRows[0].Cells["Ticker"].Value
        $delType = [string]$h.Grid.SelectedRows[0].Cells["Type"].Value
        if (-not (Confirm-Action -Text "Eintrag löschen?`r`n`r`nDer Bestand wird nicht automatisch geändert; im nächsten Schritt kannst du die Position aus den verbleibenden Buchungen neu berechnen lassen." -Title "Transaktion")) { return }
        for ($i = $script:Transactions.Count - 1; $i -ge 0; $i--) { if ($script:Transactions[$i].Id -eq $id) { $script:Transactions.RemoveAt($i) } }
        Save-Transactions
        & $h.Fill
        # v3.0: offer the recalculation right away (buys/sells only)
        if ($delType -in @("Kauf", "Verkauf") -and $delSym) {
            if (Invoke-PositionRebuild -Ticker $delSym -Owner $h.Dlg) { Update-AllUiViews }
        }
    })
    $btnRebuild.Add_Click({
        $h = $script:TxHist
        $sym = ""
        if ($h.Grid.SelectedRows.Count -gt 0) { $sym = [string]$h.Grid.SelectedRows[0].Cells["Ticker"].Value }
        if (-not $sym -and [string]$h.Filter.SelectedItem -ne "Alle Ticker") { $sym = [string]$h.Filter.SelectedItem }
        if (-not $sym) {
            [System.Windows.Forms.MessageBox]::Show($h.Dlg, "Bitte eine Buchung markieren oder oben einen Ticker wählen.", "Position neu berechnen",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        if (Invoke-PositionRebuild -Ticker $sym -Owner $h.Dlg) { Update-AllUiViews }
    })
    $btnCsv.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "CSV Datei (*.csv)|*.csv"
        $sfd.FileName = "transaktionen_{0}.csv" -f (Get-Date -Format "yyyyMMdd")
        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add("Datum;Typ;Ticker;Stück;Kurs/Betrag;Gebühr;Währung;Realisiert;Notiz")
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            foreach ($t in @($script:Transactions | Sort-Object Date)) {
                # v3.0: text fields escaped (quotes, line breaks, formula injection)
                $lines.Add(("{0};{1};{2};{3};{4};{5};{6};{7};{8}" -f $t.Date, $t.Type, (ConvertTo-CsvField $t.Ticker), ([double]$t.Shares).ToString($inv), ([double]$t.Price).ToString($inv), ([double]$t.Fee).ToString($inv), $t.Currency, ([double]$t.Realized).ToString($inv), (ConvertTo-CsvField ([string]$t.Note))))
            }
            [System.IO.File]::WriteAllLines($sfd.FileName, $lines, [System.Text.Encoding]::UTF8)
        }
        $sfd.Dispose()
    })
    & $fill
    [void]$dlg.ShowDialog($form)
    $script:TxHist = $null
    $dlg.Dispose()
}

function Invoke-PositionRebuild {
    # v3.0: replays all buys/sells of one ticker (average cost, see Core) and -
    # after a preview - replaces the position. Returns $true when it changed.
    param([string]$Ticker, $Owner = $null)
    $sym = ([string]$Ticker).Trim().ToUpper()
    if (-not $sym) { return $false }
    $own = if ($null -ne $Owner) { $Owner } else { $form }
    $title = "Position neu berechnen"
    $r = Get-PositionFromTransactions -Transactions $script:Transactions.ToArray() -Ticker $sym
    if ($null -eq $r) {
        [System.Windows.Forms.MessageBox]::Show($own, "Für $sym gibt es keine Kauf-/Verkaufsbuchungen.", $title,
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return $false
    }
    $old = if ($script:Portfolio.ContainsKey($sym)) { $script:Portfolio[$sym] } else { $null }
    $oldTxt = if ($null -ne $old) { "{0:N4} Stk @ {1:N4} {2}" -f $old.Shares, $old.AvgPrice, $old.Currency } else { "keine Position" }
    $newTxt = if ($r.Shares -gt 0) { "{0:N4} Stk @ {1:N4} {2}" -f $r.Shares, $r.AvgPrice, $r.Currency } else { "0 Stk - Position wird entfernt" }
    $notes = ""
    if ($r.Skipped -gt 0) { $notes += "`r`n- {0} Buchung(en) übersprungen (andere Währung als {1} oder Stück/Kurs = 0)" -f $r.Skipped, $r.Currency }
    if ($r.Clamped) { $notes += "`r`n- Ein Verkauf war größer als der Bestand und wurde begrenzt" }
    $msg = ("{0}: aus {1} Buchung(en) neu berechnen (Durchschnittskosten)?`r`n`r`nAktuell:  {2}`r`nNeu:      {3}{4}`r`n`r`nHinweis: Werte, die im Portfolio-Editor direkt überschrieben wurden, sind nicht als Buchung erfasst und gehen dabei verloren." -f $sym, $r.Used, $oldTxt, $newTxt, $notes)
    $ans = [System.Windows.Forms.MessageBox]::Show($own, $msg, $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }

    if ($r.Shares -le 0) {
        [void]$script:Portfolio.Remove($sym)
    } else {
        $script:Portfolio[$sym] = [PSCustomObject]@{
            Ticker    = $sym
            Shares    = [double]$r.Shares
            AvgPrice  = [double]$r.AvgPrice
            Currency  = [string]$r.Currency
            BuyAmount = $(if ($null -ne $old) { [double]$old.BuyAmount } else { 0.0 })
            TargetAvg = $(if ($null -ne $old) { [double]$old.TargetAvg } else { 0.0 })
        }
    }
    Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
    Write-WidgetLog ("Position rebuilt from transactions: {0} {1} -> {2}" -f $sym, $oldTxt, $newTxt)
    Set-TransientStatus "Position $sym neu berechnet" 3
    return $true
}

# ------------------------------------------------------------------------------
# Yearly report (v4.0). FX histories (EURxxx=X, daily) are loaded once per
# session and currency; the calculation itself is Get-RealizedReport (Core).
# ------------------------------------------------------------------------------
$script:FxHistCache = @{}

function Get-ReportYears {
    # Years with bookings (newest first) + the current year; default = newest
    # year with a sale or dividend
    $years = New-Object System.Collections.Generic.HashSet[int]
    [void]$years.Add((Get-Date).Year)
    $def = 0
    foreach ($t in $script:Transactions) {
        $d = [string]$t.Date
        if ($d -match '^(\d{4})-') {
            $y = [int]$Matches[1]
            [void]$years.Add($y)
            if ([string]$t.Type -in @("Verkauf", "Dividende") -and $y -gt $def) { $def = $y }
        }
    }
    if ($def -eq 0) { $def = (Get-Date).Year }
    return @{ Years = @($years | Sort-Object -Descending); Default = $def }
}

function Show-YearReport {
    param($Owner = $null)
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Jahresreport - realisierte Gewinne/Verluste und Dividenden" -W (S 940) -H (S 540)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 760), (S 400))
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right

    $mkLbl = {
        param([string]$T, [int]$X, [int]$Y, [int]$W)
        $l = New-Object System.Windows.Forms.Label
        $l.SetBounds($X, $Y, $W, (S 18))
        $l.Text = $T
        $dlg.Controls.Add($l)
        return $l
    }
    [void](& $mkLbl "Jahr:" (S 12) (S 15) (S 36))
    $cbYear = New-Object System.Windows.Forms.ComboBox
    $cbYear.SetBounds((S 50), (S 12), (S 80), (S 24))
    $cbYear.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbYear.BackColor = $p.Input; $cbYear.ForeColor = $p.Text; $cbYear.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ry = Get-ReportYears
    foreach ($y in $ry.Years) { [void]$cbYear.Items.Add([string]$y) }
    $cbYear.SelectedIndex = [math]::Max(0, $cbYear.Items.IndexOf([string]$ry.Default))
    $dlg.Controls.Add($cbYear)

    [void](& $mkLbl "Basiswährung:" (S 144) (S 15) (S 92))
    $cbBase = New-Object System.Windows.Forms.ComboBox
    $cbBase.SetBounds((S 238), (S 12), (S 70), (S 24))
    $cbBase.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbBase.BackColor = $p.Input; $cbBase.ForeColor = $p.Accent; $cbBase.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    foreach ($c in (Get-DisplayCurrencies)) { [void]$cbBase.Items.Add($c) }
    Select-CurrencyInCombo -Combo $cbBase -Code ([string]$script:Config.ReportBase)
    if ($cbBase.SelectedIndex -lt 0) { $cbBase.SelectedIndex = 0 }
    $dlg.Controls.Add($cbBase)

    $btnCalc = New-Object System.Windows.Forms.Button
    $btnCalc.SetBounds((S 320), (S 10), (S 100), (S 27))
    Style-FlatButton -Btn $btnCalc -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnCalc.Text = "Berechnen"
    $dlg.Controls.Add($btnCalc)

    $lblInfo = & $mkLbl "" (S 430) (S 15) (S 498)
    $lblInfo.Anchor = $aT -bor $aL -bor $aR
    $lblInfo.AutoEllipsis = $true
    $lblInfo.ForeColor = $p.Muted

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.SetBounds((S 12), (S 44), (S 916), (S 340))
    $grid.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Style-DataGrid -Grid $grid
    foreach ($cd in @(@("Date", "Datum", 82), @("Ticker", "Ticker", 76), @("Type", "Typ", 72), @("Shares", "Stück", 70), @("Cur", "Whg", 44),
                      @("Amount", "Betrag (Whg)", 96), @("Proceeds", "Erlös", 92), @("Cost", "Einstand", 92), @("Fee", "Gebühr/Steuer", 96), @("Result", "Ergebnis", 96), @("Approx", "", 22))) {
        $ci = $grid.Columns.Add($cd[0], $cd[1])
        $grid.Columns[$ci].Width = S $cd[2]
        $grid.Columns[$ci].FillWeight = [float](S $cd[2])
        $grid.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    }
    $grid.Columns["Proceeds"].ToolTipText = "Verkaufserlös bzw. Dividende brutto, in Basiswährung zum Kurs am Buchungstag"
    $grid.Columns["Cost"].ToolTipText = "Anteiliger Einstand (gleitender Durchschnitt in Basiswährung, Kaufgebühren enthalten)"
    $grid.Columns["Fee"].ToolTipText = "Verkaufsgebühr bzw. bei Dividenden einbehaltene Steuer/Gebühr"
    $grid.Columns["Approx"].ToolTipText = "~ = aktueller statt historischer Wechselkurs"
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dlg.Controls.Add($grid)

    $lblSum = New-Object System.Windows.Forms.Label
    $lblSum.SetBounds((S 12), (S 390), (S 700), (S 96))
    $lblSum.Anchor = $aB -bor $aL -bor $aR
    $lblSum.Font = $fontMono
    $dlg.Controls.Add($lblSum)

    $lblNote = New-Object System.Windows.Forms.Label
    $lblNote.SetBounds((S 12), (S 490), (S 700), (S 34))
    $lblNote.Anchor = $aB -bor $aL -bor $aR
    $lblNote.ForeColor = $p.Muted
    $lblNote.Text = "Hilfsrechnung aus deinen Buchungen, keine Steuerberatung. Maßgeblich sind die Abrechnungen bzw. Steuerreports deiner Bank/deines Brokers."
    $dlg.Controls.Add($lblNote)

    $btnCsv = New-Object System.Windows.Forms.Button
    $btnCsv.SetBounds((S 722), (S 496), (S 100), (S 28))
    $btnCsv.Anchor = $aB -bor $aR
    Style-FlatButton -Btn $btnCsv -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $btnCsv.Text = "CSV export"
    $btnCsv.Enabled = $false
    $dlg.Controls.Add($btnCsv)
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.SetBounds((S 828), (S 496), (S 100), (S 28))
    $btnClose.Anchor = $aB -bor $aR
    Style-FlatButton -Btn $btnClose -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $btnClose.Text = "Schließen"
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnClose)
    $dlg.CancelButton = $btnClose

    $script:RepCtl = @{ Dlg = $dlg; Year = $cbYear; Base = $cbBase; Grid = $grid; Info = $lblInfo; Sum = $lblSum; Csv = $btnCsv; Calc = $btnCalc; Report = $null }

    $render = {
        param($Rep)
        $rc = $script:RepCtl
        if ($null -eq $rc -or $rc.Dlg.IsDisposed) { return }
        $rc.Report = $Rep
        $rc.Grid.Rows.Clear()
        foreach ($r in $Rep.Rows) {
            $ri = $rc.Grid.Rows.Add($r.Date, $r.Ticker, $r.Type, $(if ($r.Type -eq "Verkauf") { "{0:N4}" -f $r.Shares } else { "" }), $r.Currency,
                ("{0:N2}" -f $r.Amount), ("{0:N2}" -f $r.Proceeds), $(if ($r.Type -eq "Verkauf") { "{0:N2}" -f $r.Cost } else { "" }), ("{0:N2}" -f $r.Fee),
                ("{0:+0.00;-0.00;0.00}" -f $r.Result), $(if ($r.Approx) { "~" } else { "" }))
            $rc.Grid.Rows[$ri].Cells["Result"].Style.ForeColor = if ($r.Result -ge 0) { $colGreen } else { $colRed }
        }
        $t = $Rep.Totals
        $b = $Rep.Base
        $rc.Sum.Text = (("Verkäufe:  Gewinne {0,12:N2}   Verluste {1,12:N2}   Saldo {2,12:N2} {6}`r`n" +
                         "            (Verkaufsgebühren enthalten: {3:N2} {6})`r`n" +
                         "Dividenden: brutto  {4,12:N2}   Abzüge  {5,12:N2}   netto {7,12:N2} {6}`r`n" +
                         "Gesamt (Saldo Verkäufe + Dividenden netto): {8:+0.00;-0.00;0.00} {6}") -f
                         $t.Gains, $t.Losses, $t.SellNet, $t.SellFees, $t.DividendsGross, $t.DividendFees, $b, $t.DividendsNet, $t.Net)
        $rc.Sum.ForeColor = if ($t.Net -ge 0) { $colGreen } else { $colRed }
        $rows = @($Rep.Rows).Count
        $rc.Info.ForeColor = if (@($Rep.Warnings).Count -gt 0) { [System.Drawing.Color]::FromArgb(245, 158, 11) } else { $script:Pal.Muted }
        $rc.Info.Text = if (@($Rep.Warnings).Count -gt 0) { (@($Rep.Warnings) -join " | ") } else { "{0} Buchung(en) in {1}" -f $rows, $Rep.Year }
        Set-DynTip $rc.Info (@($Rep.Warnings) -join "`r`n")
        $rc.Csv.Enabled = ($rows -gt 0)
        $rc.Calc.Enabled = $true
    }
    $script:RepCtl.Render = $render

    $btnCalc.Add_Click({
        $rc = $script:RepCtl
        $year = [int][string]$rc.Year.SelectedItem
        $base = [string]$rc.Base.SelectedItem
        $script:Config.ReportBase = $base
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        $txs = $script:Transactions.ToArray()
        $need = @(Get-ReportCurrencies -Transactions $txs -Year $year -Base $base | Where-Object { -not $script:FxHistCache.ContainsKey($_) -or [int]$script:FxHistCache[$_].ToYear -lt $year })
        $fallback = @{}
        foreach ($k in $script:FxFromEur.Keys) { $fallback[$k] = [double]$script:FxFromEur[$k] }
        $compute = {
            param([int]$Y, [string]$B, $Txs, $Fb)
            $hist = @{}
            foreach ($k in $script:FxHistCache.Keys) { if ($null -ne $script:FxHistCache[$k].Hist) { $hist[$k] = $script:FxHistCache[$k].Hist } }
            $rep = Get-RealizedReport -Transactions $Txs -Year $Y -Base $B -History $hist -FallbackFromEur $Fb
            & $script:RepCtl.Render $rep
        }
        $script:RepCtl.Compute = $compute
        if ($need.Count -eq 0) { & $compute $year $base $txs $fallback; return }

        # Daily FX history from the earliest booking up to the end of the year
        $first = Get-EarliestBookingDate -Transactions $txs
        $from = if ($first) { [DateTime]::ParseExact($first, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture).AddDays(-10) } else { New-Object DateTime($year, 1, 1) }
        $to = (New-Object DateTime($year, 12, 31)).AddDays(2)
        if ($to -gt (Get-Date)) { $to = Get-Date }
        $p1 = ([DateTimeOffset]$from).ToUnixTimeSeconds()
        $p2 = ([DateTimeOffset]$to).ToUnixTimeSeconds()
        $urls = @{}
        foreach ($c in $need) { $urls[$c] = "https://query1.finance.yahoo.com/v8/finance/chart/EUR${c}=X?interval=1d&period1=$p1&period2=$p2" }
        $rc.Calc.Enabled = $false
        $rc.Info.ForeColor = $script:Pal.Muted
        $rc.Info.Text = "Lade Wechselkursverlauf: " + ($need -join ", ") + " ..."
        Start-FetchJob -Urls @($urls.Values) -MaxConcurrency 3 -Context @{ Urls = $urls; Year = $year; Base = $base; Txs = $txs; Fb = $fallback } -OnComplete {
            param($Box, $Ctx)
            foreach ($c in @($Ctx.Urls.Keys)) {
                $h = ConvertFrom-YahooFxHistory -Json $Box.Results[$Ctx.Urls[$c]]
                if ($null -ne $h) { $script:FxHistCache[$c] = @{ Hist = $h; ToYear = $Ctx.Year } }
                else { Write-WidgetLog "FX history for $c not available" "WARN" }
            }
            if ($null -eq $script:RepCtl) { return }
            & $script:RepCtl.Compute $Ctx.Year $Ctx.Base $Ctx.Txs $Ctx.Fb
        }
    })

    $btnCsv.Add_Click({
        $rc = $script:RepCtl
        $rep = $rc.Report
        if ($null -eq $rep) { return }
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "CSV Datei (*.csv)|*.csv"
        $sfd.FileName = "jahresreport_{0}_{1}.csv" -f $rep.Year, $rep.Base
        if ($sfd.ShowDialog($rc.Dlg) -eq [System.Windows.Forms.DialogResult]::OK) {
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add(("Datum;Typ;Ticker;Stück;Währung;Betrag;Erlös {0};Einstand {0};Gebühr/Steuer {0};Ergebnis {0};Näherung" -f $rep.Base))
            foreach ($r in $rep.Rows) {
                $lines.Add(("{0};{1};{2};{3};{4};{5};{6};{7};{8};{9};{10}" -f $r.Date, $r.Type, (ConvertTo-CsvField $r.Ticker), ([double]$r.Shares).ToString($inv), $r.Currency,
                    ([math]::Round([double]$r.Amount, 4)).ToString($inv), ([math]::Round([double]$r.Proceeds, 2)).ToString($inv), ([math]::Round([double]$r.Cost, 2)).ToString($inv),
                    ([math]::Round([double]$r.Fee, 2)).ToString($inv), ([math]::Round([double]$r.Result, 2)).ToString($inv), $(if ($r.Approx) { "ja" } else { "" })))
            }
            $t = $rep.Totals
            $lines.Add("")
            foreach ($pair in @(@("Gewinne Verkäufe", $t.Gains), @("Verluste Verkäufe", $t.Losses), @("Saldo Verkäufe", $t.SellNet), @("Verkaufsgebühren (enthalten)", $t.SellFees),
                                @("Dividenden brutto", $t.DividendsGross), @("Dividenden Abzüge", $t.DividendFees), @("Dividenden netto", $t.DividendsNet), @("Gesamt", $t.Net))) {
                $lines.Add(("{0};{1}" -f $pair[0], ([math]::Round([double]$pair[1], 2)).ToString($inv)))
            }
            foreach ($w in @($rep.Warnings)) { $lines.Add(("Hinweis;{0}" -f (ConvertTo-CsvField $w))) }
            [System.IO.File]::WriteAllLines($sfd.FileName, $lines, [System.Text.Encoding]::UTF8)
            Set-TransientStatus "Jahresreport exportiert" 3
        }
        $sfd.Dispose()
    })

    $own = if ($null -ne $Owner) { $Owner } else { $form }
    $dlg.Add_Shown({ $script:RepCtl.Calc.PerformClick() })
    [void]$dlg.ShowDialog($own)
    $script:RepCtl = $null
    $dlg.Dispose()
}

function Show-CurrencyMismatchNotice {
    # v3.0: positions whose currency contradicts their own bookings were most
    # likely hit by the v2.9 load bug (non EUR/USD/CHF -> EUR, amount kept).
    # Nothing is changed automatically; the notice repeats only if the list changes.
    $mm = @(Find-PositionCurrencyMismatch -Portfolio $script:Portfolio -Transactions $script:Transactions.ToArray())
    if ($mm.Count -eq 0) { return }
    foreach ($m in $mm) { Write-WidgetLog ("Currency mismatch: {0} position in {1}, bookings in {2}" -f $m.Ticker, $m.PositionCurrency, $m.TransactionCurrencies) "WARN" }
    $key = (@($mm | ForEach-Object { "{0}:{1}>{2}" -f $_.Ticker, $_.TransactionCurrencies, $_.PositionCurrency }) -join "|")
    if ($key -eq [string]$script:Config.CurrencyNoticeKey) { return }
    $script:Config.CurrencyNoticeKey = $key
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    $lines = @($mm | ForEach-Object { "  {0}: Position in {1}, Buchungen in {2}" -f $_.Ticker, $_.PositionCurrency, $_.TransactionCurrencies }) -join "`r`n"
    $txt = "Bei diesen Positionen passt die Währung nicht zu den eigenen Buchungen:`r`n`r`n$lines`r`n`r`n" +
           "Wahrscheinliche Ursache: v2.9 hat beim Laden jede Währung außer EUR/USD/CHF auf EUR gesetzt (der EK-Betrag blieb gleich, nur die Währung wurde falsch).`r`n`r`n" +
           "Korrektur: Portfolio > 'Historie...' > Ticker markieren > 'Position neu berechnen' - oder im Portfolio-Editor die richtige Währung wählen und speichern.`r`n`r`n" +
           "Dieser Hinweis erscheint erst wieder, wenn sich die Liste ändert."
    [System.Windows.Forms.MessageBox]::Show($form, $txt, "Daten prüfen - $($script:AppTitle)",
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

# ------------------------------------------------------------------------------
# Autostart (v2.9): shortcut in the user's Startup folder
# ------------------------------------------------------------------------------
function Get-AutostartDir {
    # v3.0.1: GetFolderPath("Startup") returns "" on some Windows Server / RDS
    # profiles; Join-Path "" then threw and crashed the settings dialog.
    # Fallback: the standard per-user Startup folder; "" if even that is unknown.
    $dir = [Environment]::GetFolderPath("Startup")
    if ([string]::IsNullOrWhiteSpace($dir) -and $env:APPDATA) {
        $dir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
    }
    if ([string]::IsNullOrWhiteSpace($dir)) { return "" }
    return $dir
}

function Get-AutostartPath {
    $dir = Get-AutostartDir
    if (-not $dir) { return "" }
    return (Join-Path $dir "Terminal Widget.lnk")
}

function Update-OldAutostart {
    # v4.0: the v3 shortcut ("Financial Widget.lnk") starts nvidia_widget.ps1.
    # Replace it with a shortcut to this script (only when this runs from a file).
    $dir = Get-AutostartDir
    if (-not $dir) { return }
    $old = Join-Path $dir "Financial Widget.lnk"
    if (-not (Test-Path -LiteralPath $old) -or [string]::IsNullOrEmpty($PSCommandPath)) { return }
    try {
        $sh = New-Object -ComObject WScript.Shell
        try { $args0 = [string]$sh.CreateShortcut($old).Arguments } finally { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
        if ($args0 -notlike "*nvidia_widget*") { return }
        $err = Set-Autostart -Enable $true
        if ($err) { Write-WidgetLog "Autostart migration failed: $err" "WARN"; return }
        Remove-Item -LiteralPath $old -Force
        $script:Config.Autostart = $true
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        Write-WidgetLog "Autostart shortcut of v3 replaced by '$(Get-AutostartPath)'"
    } catch {
        Write-WidgetLog "Autostart migration failed: $($_.Exception.Message)" "WARN"
    }
}

function Test-Autostart {
    $lnk = Get-AutostartPath
    if (-not $lnk) { return $false }
    return (Test-Path -LiteralPath $lnk)
}

function Set-Autostart {
    # Returns "" on success, otherwise an error text
    param([bool]$Enable)
    $lnk = Get-AutostartPath
    if (-not $lnk) { return "Autostart-Ordner ist auf diesem System nicht verfügbar." }
    try {
        # the fallback folder may not exist yet on a fresh server profile
        $lnkDir = Split-Path -Parent $lnk
        if ($Enable -and -not (Test-Path -LiteralPath $lnkDir)) { New-Item -ItemType Directory -Path $lnkDir -Force | Out-Null }
        if (-not $Enable) {
            if (Test-Path $lnk) { Remove-Item -Path $lnk -Force }
            return ""
        }
        $scriptPath = $PSCommandPath
        if ([string]::IsNullOrEmpty($scriptPath)) { return "Skriptpfad unbekannt (aus einer Datei starten, nicht aus dem Editor)." }
        # same host as now (powershell.exe / pwsh.exe); from the ISE: powershell.exe
        $exe = (Get-Process -Id $PID).Path
        if ([string]::IsNullOrEmpty($exe) -or $exe -like "*powershell_ise*") { $exe = Join-Path $PSHOME "powershell.exe" }
        $sh = New-Object -ComObject WScript.Shell
        try {
            $sc = $sh.CreateShortcut($lnk)
            $sc.TargetPath = $exe
            $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
            $sc.WorkingDirectory = Split-Path -Parent $scriptPath
            $sc.WindowStyle = 7
            $sc.Description = "Terminal Widget"
            $sc.Save()
        } finally {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh)
        }
        Write-WidgetLog "Autostart shortcut created: $lnk"
        return ""
    } catch {
        Write-WidgetLog "Autostart change failed: $($_.Exception.Message)" "ERROR"
        return $_.Exception.Message
    }
}

# ------------------------------------------------------------------------------
# Settings dialog (v2.8): everything that used to be config.json-only
# ------------------------------------------------------------------------------
function Show-SettingsDialog {
    # v4.0: two columns (left: data / indicators / look / system, right: layout
    # and explanations)
    $p   = $script:Pal
    $cfg = $script:Config
    $lay = @{ Y = (S 12); X = 0; MaxY = 0 }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Einstellungen - $($script:AppTitle)"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $dlg.BackColor = $p.BodyBg
    $dlg.ForeColor = $p.Text
    $dlg.Font = $fontUi
    $dlg.TopMost = $form.TopMost
    $dlg.KeyPreview = $true
    $dlg.ClientSize = New-Object System.Drawing.Size((S 860), (S 400))
    $dlg.Add_HandleCreated({
        param($sender, $e)
        try {
            $dm = [int]$script:Pal.DwmDark
            [void][Win32WidgetHelperV26]::DwmSetWindowAttribute($sender.Handle, 20, [ref]$dm, 4)
        } catch { }
    })

    $newColumn = {
        param([int]$X)
        if ($lay.Y -gt $lay.MaxY) { $lay.MaxY = $lay.Y }
        $lay.X = $X
        $lay.Y = S 12
    }
    $addSection = {
        param([string]$Text)
        $l = New-Object System.Windows.Forms.Label
        $l.Location = New-Object System.Drawing.Point(($lay.X + (S 14)), ($lay.Y + (S 4)))
        $l.Size = New-Object System.Drawing.Size((S 400), (S 18))
        $l.Font = $fontUiBold
        $l.ForeColor = $p.Accent
        $l.Text = $Text
        $dlg.Controls.Add($l)
        $lay.Y += S 26
    }
    $addNum = {
        param([string]$Label, [int]$Min, [int]$Max, [int]$Value, [string]$Tip = "", [string]$TipKey = "", [int]$Step = 1)
        $l = New-Object System.Windows.Forms.Label
        $l.Location = New-Object System.Drawing.Point(($lay.X + (S 26)), ($lay.Y + (S 3)))
        $l.Size = New-Object System.Drawing.Size((S 258), (S 18))
        $l.Text = $Label
        $dlg.Controls.Add($l)
        $n = New-Object System.Windows.Forms.NumericUpDown
        $n.Location = New-Object System.Drawing.Point(($lay.X + (S 292)), $lay.Y)
        $n.Size = New-Object System.Drawing.Size((S 112), (S 22))
        $n.Minimum = $Min
        $n.Maximum = $Max
        $n.Increment = [math]::Max(1, $Step)
        $n.Value = [math]::Max($Min, [math]::Min($Max, $Value))
        $n.BackColor = $p.Input
        $n.ForeColor = $p.Text
        $n.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $n.Font = $fontMono
        $n.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Right
        $dlg.Controls.Add($n)
        if ($Tip -or $TipKey) { Set-DynTip $l $Tip $TipKey; Set-DynTip $n $Tip $TipKey }
        $lay.Y += S 29
        return $n
    }
    $addCombo = {
        param([string]$Label, [string[]]$Items, [string]$Value, [string]$Tip = "", [string]$TipKey = "")
        $l = New-Object System.Windows.Forms.Label
        $l.Location = New-Object System.Drawing.Point(($lay.X + (S 26)), ($lay.Y + (S 3)))
        $l.Size = New-Object System.Drawing.Size((S 258), (S 18))
        $l.Text = $Label
        $dlg.Controls.Add($l)
        $cb = New-Object System.Windows.Forms.ComboBox
        $cb.Location = New-Object System.Drawing.Point(($lay.X + (S 292)), $lay.Y)
        $cb.Size = New-Object System.Drawing.Size((S 112), (S 22))
        $cb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $cb.BackColor = $p.Input
        $cb.ForeColor = $p.Text
        foreach ($it in $Items) { [void]$cb.Items.Add($it) }
        $cb.SelectedIndex = [math]::Max(0, $cb.Items.IndexOf($Value))
        $dlg.Controls.Add($cb)
        if ($Tip -or $TipKey) { Set-DynTip $l $Tip $TipKey; Set-DynTip $cb $Tip $TipKey }
        $lay.Y += S 29
        return $cb
    }
    $addCheck = {
        param([string]$Label, [bool]$Value, [string]$Tip = "", [string]$TipKey = "")
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Location = New-Object System.Drawing.Point(($lay.X + (S 26)), $lay.Y)
        $c.Size = New-Object System.Drawing.Size((S 390), (S 22))
        $c.Text = $Label
        $c.Checked = $Value
        $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $c.ForeColor = $p.Text
        $dlg.Controls.Add($c)
        if ($Tip -or $TipKey) { Set-DynTip $c $Tip $TipKey }
        $lay.Y += S 25
        return $c
    }

    # ---- left column ----
    & $addSection "Aktualisierung"
    $nRefresh = & $addNum "Intervall (Sekunden)" 5 600 ([int]$cfg.RefreshSeconds) "Aktiver Ticker, Portfolio und aktive Alarme" "REFRESH"
    $nSlow    = & $addNum "Nur-Watchlist-Ticker (Sekunden)" 15 1800 ([int]$cfg.SlowRefreshSeconds) "Ticker, die nur in der Watchlist stehen, und Wechselkurse" "REFRESH"
    $nHttp    = & $addNum "HTTP-Timeout (Sekunden, ab Neustart)" 3 60 ([int]$cfg.HttpTimeoutSeconds)

    & $addSection "Indikatoren"
    $nSmaF  = & $addNum "SMA schnell (auch Bollinger-Periode)" 2 200 ([int]$cfg.SmaFastPeriod) "" "SMA"
    $nSmaS  = & $addNum "SMA langsam" 3 400 ([int]$cfg.SmaSlowPeriod) "" "SMA"
    $nRsi   = & $addNum "RSI-Periode" 2 100 ([int]$cfg.RsiPeriod) "" "RSI"
    $nRsiOb = & $addNum "RSI überkauft ab" 51 99 ([int]$cfg.RsiOverbought) "" "RSI"
    $nRsiOs = & $addNum "RSI überverkauft bis" 1 49 ([int]$cfg.RsiOversold) "" "RSI"

    & $addSection "Darstellung"
    $cbTheme  = & $addCombo "Theme" @(Get-ThemeNames) ([string]$cfg.Theme) "" "THEME"
    $cbAccent = & $addCombo "Akzentfarbe" @("Sky", "Amber", "Violet") ([string]$cfg.AccentColor)
    $chkTop   = & $addCheck "Immer im Vordergrund" ([bool]$cfg.TopMost) "" "PIN"
    $chkTape  = & $addCheck "Laufleiste (Watchlist) im Compact-Layout" ([bool]$cfg.CompactTape)

    & $addSection "Benachrichtigungen"
    $chkTray  = & $addCheck "Tray-Hinweis + Ton bei Alarmen" ([bool]$cfg.ShowTrayNotifications)
    $chkOpen  = & $addCheck "Hinweis bei Handelsstart (Börsen im Portfolio / aktiver Ticker)" ([bool]$cfg.NotifyMarketOpen)

    & $addSection "System"
    $autoNow  = Test-Autostart
    $chkAuto  = & $addCheck "Mit Windows starten (Verknüpfung im Autostart-Ordner)" $autoNow

    # ---- right column ----
    & $newColumn (S 430)
    & $addSection "Layout und Fenster"
    $cbLayout = & $addCombo "Layout" @(Get-LayoutNames) ([string]$cfg.Layout) "Auch über den Layout-Button rechts oben oder Taste L" "LAYOUT"
    $nOpacity = & $addNum "Deckkraft (%)" 30 100 ([int]$cfg.Opacity) "" "OPACITY" 5
    $chkTWatch = & $addCheck "Terminal: Watchlist und Alarme anzeigen" ([bool]$cfg.TerminalShowWatch) "" "LAYOUT"
    $chkTPort  = & $addCheck "Terminal: Portfolio anzeigen" ([bool]$cfg.TerminalShowPortfolio) "" "LAYOUT"
    $nTChart   = & $addNum "Terminal: Chart-Höhe (%)" 25 80 ([int]$cfg.TerminalChartPct) "Anteil des Charts an der Fensterhöhe; der Rest gehört den Listen" "LAYOUT" 5

    & $addSection "Erklärungen (Maus darüber)"
    $modes = Get-TooltipModes
    $cbTip = & $addCombo "Ausführlichkeit" @($modes.Values) ([string]$modes[[string]$cfg.TooltipMode]) "" "TOOLTIPS"
    $nTipDelay = & $addNum "Verzögerung (Millisekunden)" 0 3000 ([int]$cfg.TooltipDelayMs) "Wie lange die Maus stillstehen muss, bis der Hinweis erscheint" "TOOLTIPS" 100
    $btnGloss = New-Object System.Windows.Forms.Button
    $btnGloss.SetBounds(($lay.X + (S 26)), $lay.Y, (S 150), (S 26))
    Style-FlatButton -Btn $btnGloss -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnGloss.Text = "Glossar öffnen (G)"
    $btnGloss.Add_Click({ Show-GlossaryDialog })
    $dlg.Controls.Add($btnGloss)
    $lay.Y += S 34
    & $newColumn 0

    $by = $lay.MaxY + (S 12)
    $btnDir = New-Object System.Windows.Forms.Button
    $btnDir.SetBounds((S 14), $by, (S 130), (S 28))
    Style-FlatButton -Btn $btnDir -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $btnDir.Text = "Datenordner öffnen"
    $btnDir.Add_Click({ try { Start-Process -FilePath "explorer.exe" -ArgumentList "`"$($script:DataDir)`"" } catch { } })
    $dlg.Controls.Add($btnDir)
    Set-DynTip $btnDir $script:DataDir

    # v3.0: manual backup + log access (the window runs hidden, errors only go to the log)
    $btnBackup = New-Object System.Windows.Forms.Button
    $btnBackup.SetBounds((S 150), $by, (S 110), (S 28))
    Style-FlatButton -Btn $btnBackup -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $btnBackup.Text = "Backup jetzt"
    $btnBackup.Add_Click({
        $dest = Backup-DataFiles -Reason "manuell"
        $owner = if ($null -ne $script:SettingsCtl) { $script:SettingsCtl.Dlg } else { $form }
        $txt = if ($dest) { "Backup erstellt:`r`n$dest`r`n`r`n(Es werden die letzten 10 Backups behalten.)" } else { "Backup fehlgeschlagen oder keine Daten vorhanden - siehe Log." }
        [System.Windows.Forms.MessageBox]::Show($owner, $txt, "Backup", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    })
    $dlg.Controls.Add($btnBackup)
    Set-DynTip $btnBackup "Kopie von Einstellungen, Portfolio, Alarmen und Transaktionen in $($script:BackupDir)" "BACKUP"

    $btnLog = New-Object System.Windows.Forms.Button
    $btnLog.SetBounds((S 266), $by, (S 100), (S 28))
    Style-FlatButton -Btn $btnLog -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $btnLog.Text = "Log öffnen"
    $btnLog.Add_Click({
        if (Test-Path $script:LogPath) { try { Start-Process -FilePath "notepad.exe" -ArgumentList "`"$($script:LogPath)`"" } catch { } }
    })
    $dlg.Controls.Add($btnLog)
    Set-DynTip $btnLog $script:LogPath

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.SetBounds((S 752), $by, (S 94), (S 28))
    Style-FlatButton -Btn $btnCancel -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $btnCancel.Text = "Abbrechen"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCancel)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.SetBounds((S 652), $by, (S 94), (S 28))
    Style-FlatButton -Btn $btnOk -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnOk.Font = $fontUiBold
    $btnOk.Text = "OK"
    # (handlers reach the controls through script scope, not via the caller's locals)
    $script:SettingsCtl = @{ Dlg = $dlg; SmaF = $nSmaF; SmaS = $nSmaS; Slow = $nSlow; Refresh = $nRefresh }
    $btnOk.Add_Click({
        $sc = $script:SettingsCtl
        if ($sc.SmaF.Value -ge $sc.SmaS.Value) {
            [System.Windows.Forms.MessageBox]::Show($sc.Dlg, "SMA schnell muss kleiner als SMA langsam sein.", "Einstellungen",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        if ($sc.Slow.Value -lt $sc.Refresh.Value) { $sc.Slow.Value = $sc.Refresh.Value }
        $sc.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $sc.Dlg.Close()
    })
    $dlg.Controls.Add($btnOk)
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel
    $dlg.ClientSize = New-Object System.Drawing.Size((S 860), ($by + (S 42)))

    $res = $dlg.ShowDialog($form)
    $script:SettingsCtl = $null
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) { $dlg.Dispose(); return }

    $needRefresh = ([int]$nSmaF.Value -ne [int]$cfg.SmaFastPeriod) -or ([int]$nSmaS.Value -ne [int]$cfg.SmaSlowPeriod) -or ([int]$nRsi.Value -ne [int]$cfg.RsiPeriod)
    $cfg.RefreshSeconds        = [int]$nRefresh.Value
    $cfg.SlowRefreshSeconds    = [int]$nSlow.Value
    $cfg.HttpTimeoutSeconds    = [int]$nHttp.Value
    $cfg.SmaFastPeriod         = [int]$nSmaF.Value
    $cfg.SmaSlowPeriod         = [int]$nSmaS.Value
    $cfg.RsiPeriod             = [int]$nRsi.Value
    $cfg.RsiOverbought         = [int]$nRsiOb.Value
    $cfg.RsiOversold           = [int]$nRsiOs.Value
    $cfg.Theme                 = [string]$cbTheme.SelectedItem
    $cfg.AccentColor           = [string]$cbAccent.SelectedItem
    $cfg.TopMost               = [bool]$chkTop.Checked
    $cfg.CompactTape           = [bool]$chkTape.Checked
    $cfg.ShowTrayNotifications = [bool]$chkTray.Checked
    $cfg.NotifyMarketOpen      = [bool]$chkOpen.Checked
    # v4.0
    $newLayout                 = [string]$cbLayout.SelectedItem
    $cfg.Opacity               = [int]$nOpacity.Value
    $cfg.TerminalShowWatch     = [bool]$chkTWatch.Checked
    $cfg.TerminalShowPortfolio = [bool]$chkTPort.Checked
    $cfg.TerminalChartPct      = [int]$nTChart.Value
    foreach ($mk in $modes.Keys) { if ($modes[$mk] -eq [string]$cbTip.SelectedItem) { $cfg.TooltipMode = $mk } }
    $cfg.TooltipDelayMs        = [int]$nTipDelay.Value
    $autoWanted = [bool]$chkAuto.Checked
    $dlg.Dispose()
    if ($autoWanted -ne $autoNow) {
        $aErr = Set-Autostart -Enable $autoWanted
        if ($aErr) {
            [System.Windows.Forms.MessageBox]::Show($form, "Autostart konnte nicht geändert werden:`r`n$aErr", "Einstellungen",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    }
    $cfg.Autostart = Test-Autostart

    # Apply
    $pollTimer.Interval = [int]$cfg.RefreshSeconds * 1000
    $refStr = "$($cfg.RefreshSeconds)s"
    if ($cmbRefresh.Items.IndexOf($refStr) -lt 0) { [void]$cmbRefresh.Items.Add($refStr) }
    $cmbRefresh.SelectedIndex = $cmbRefresh.Items.IndexOf($refStr)
    $form.TopMost = [bool]$cfg.TopMost
    $btnToggleRsi.Text = "RSI-$($cfg.RsiPeriod)"
    Set-Tip $btnToggleSma "Gleitende Durchschnitte SMA $($cfg.SmaFastPeriod)/$($cfg.SmaSlowPeriod) (Taste M)" "SMA"
    Apply-TooltipMode
    Update-ChartControlsLayout
    Save-JsonState -Path $script:ConfigPath -Data $cfg
    Apply-ThemeToAllControls
    Apply-Layout $newLayout
    if ($needRefresh) { Refresh-AllMarketData -Force }
    Set-TransientStatus "Einstellungen gespeichert" 3
}

function Show-GlossaryDialog {
    # v4.0: searchable list of every explained term
    $dlg = New-DialogForm -Title "Glossar - $($script:AppTitle)" -W (S 640) -H (S 430)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 500), (S 300))
    $p = $script:Pal
    $aTL = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

    $lblF = New-Object System.Windows.Forms.Label
    $lblF.SetBounds((S 12), (S 15), (S 50), (S 18))
    $lblF.Text = "Suchen:"
    $dlg.Controls.Add($lblF)
    $tbF = New-Object System.Windows.Forms.TextBox
    $tbF.SetBounds((S 64), (S 12), (S 160), (S 24))
    $tbF.BackColor = $p.Input; $tbF.ForeColor = $p.Text; $tbF.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tbF.Anchor = $aTL
    $dlg.Controls.Add($tbF)

    $lb = New-Object System.Windows.Forms.ListBox
    $lb.SetBounds((S 12), (S 44), (S 212), (S 374))
    $lb.Anchor = $aTL -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $lb.BackColor = $p.Input; $lb.ForeColor = $p.Text; $lb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $lb.IntegralHeight = $false
    $lb.DisplayMember = "Term"
    $dlg.Controls.Add($lb)

    $tx = New-Object System.Windows.Forms.TextBox
    $tx.SetBounds((S 234), (S 12), (S 394), (S 406))
    $tx.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $tx.Multiline = $true
    $tx.ReadOnly = $true
    $tx.WordWrap = $true
    $tx.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $tx.BackColor = $p.Card; $tx.ForeColor = $p.Text; $tx.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tx.Font = New-Object System.Drawing.Font("Segoe UI", 10.0)
    $dlg.Controls.Add($tx)

    $script:GlossCtl = @{ Filter = $tbF; List = $lb; Text = $tx; All = @(Get-GlossaryEntries | Sort-Object Term) }
    $fill = {
        $gc = $script:GlossCtl
        $f = $gc.Filter.Text.Trim()
        $gc.List.BeginUpdate()
        $gc.List.Items.Clear()
        foreach ($en in $gc.All) {
            if (-not $f -or $en.Term -like "*$f*" -or $en.Short -like "*$f*" -or $en.Long -like "*$f*") { [void]$gc.List.Items.Add($en) }
        }
        $gc.List.EndUpdate()
        if ($gc.List.Items.Count -gt 0) { $gc.List.SelectedIndex = 0 } else { $gc.Text.Text = "Kein Begriff gefunden." }
    }
    $script:GlossCtl.Fill = $fill
    $tbF.Add_TextChanged({ & $script:GlossCtl.Fill })
    $lb.Add_SelectedIndexChanged({
        $gc = $script:GlossCtl
        $en = $gc.List.SelectedItem
        if ($null -ne $en) { $gc.Text.Text = ($en.Term + "`r`n`r`n" + $en.Short + "`r`n`r`n" + $en.Long) }
    })
    & $fill
    $owner = if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed) { $script:FsForm } else { $form }
    [void]$dlg.ShowDialog($owner)
    $script:GlossCtl = $null
    $tx.Font.Dispose()
    $dlg.Dispose()
}

function Show-ShortcutHelp {
    $txt = @"
Tastenkürzel

F1 / F2 / F3    Chart / Portfolio / Watch & Alarm
F5              Jetzt aktualisieren
Ctrl+F          Ticker suchen
Links / Rechts  Vorheriger / nächster Watchlist-Ticker
Mausrad (Chart) Zeitraum wechseln
1 - 6           Zeitraum 1D / 5D / 1M / 3M / 6M / 1Y
F11             Chart im Vollbild (auch Doppelklick auf Chart)

K  Linie / Kerzen       V  Volumen
M  SMA                  A  VWAP
B  Bollinger            R  RSI
E  Vor-/Nachbörse      W  Währung (EUR/USD/CHF/GBP)
T  Theme                C  Compact an/aus
L  Nächstes Layout     G  Glossar (Begriffe)
S  Einstellungen        H  Diese Hilfe
Z  Zoom zurücksetzen   X  Vergleich an/aus
Esc  Messung / Popups / Vollbild schließen

Layouts (Button rechts oben oder L):
Ticker    nur Kurs + Mini-Chart, rahmenlos
Compact   Leiste mit Marktstatus und Laufband
Standard  Fenster mit Tabs
Terminal  Chart oben, Watchlist + Portfolio darunter

Erklärungen: Maus auf Bedienelemente, Spaltenköpfe oder
die Legende im Chart (SMA, VWAP, RSI ...) halten.
Ausführlichkeit und Verzögerung in den Einstellungen.

Chart:
Strg + Mausrad    Zoomen (um die Mausposition)
Umschalt + Mausrad  Ausschnitt verschieben
Linke Maus ziehen   Messen (Differenz, %, Bars, Dauer)
Rechtsklick         Alarm auf diesem Kurs setzen

Doppelklick auf Kurs = Kurs kopieren
Header ziehen = Fenster verschieben
Marktstatus: Maus über die Statuszeile = Handelszeiten
Chart: Fadenkreuz zeigt Kurs (rechts) und Zeit (unten) an der Maus
Compact-Laufleiste: Klick = Ticker öffnen, Maus darüber = Pause
"@
    [System.Windows.Forms.MessageBox]::Show($form, $txt, "Hilfe - $($script:AppTitle)",
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

$btnToggleExt.Add_Click({ Toggle-ExtendedHours })
$btnSettings.Add_Click({ Show-SettingsDialog })

$lblLivePrice.Add_DoubleClick({
    $cmiCopyPrice.PerformClick()
    Set-TransientStatus "Kurs in Zwischenablage kopiert" 3
})

# Remember the window position right after it was moved (not only on close)
$form.Add_ResizeEnd({
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) {
        $script:Config.WindowX = $form.Location.X
        $script:Config.WindowY = $form.Location.Y
        Save-WindowSize
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
    }
})
# Live re-layout while dragging the border and on maximize / restore
$script:StartupDone = $false
$form.Add_Resize({
    Update-MainLayout
    # Remember "maximized" (restored on the next start)
    if ($script:StartupDone -and -not [bool]$script:Config.CompactMode -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
        $isMax = ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized)
        if ($isMax -ne [bool]$script:Config.WindowMaximized) {
            $script:Config.WindowMaximized = $isMax
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
        }
    }
})

$btnRefreshNow.Add_Click({
    Refresh-AllMarketData -Force
    Evaluate-GlobalAlerts
    Update-AllUiViews
})

$btnThemeCycle.Add_Click({
    $script:Config.Theme = Get-NextTheme $script:Config.Theme
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Apply-ThemeToAllControls
})

$cmbRefresh.Add_SelectedIndexChanged({
    if ($null -ne $cmbRefresh.SelectedItem) {
        $sec = [int](([string]$cmbRefresh.SelectedItem).Replace("s", ""))
        if ($sec -ge 5) {
            $script:Config.RefreshSeconds = $sec
            $pollTimer.Interval = $sec * 1000
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
        }
    }
})

$btnCurrency.Add_Click({
    $lstTickerDropdown.Visible = $false
    $lstCurrencyDropdown.Visible = -not $lstCurrencyDropdown.Visible
    if ($lstCurrencyDropdown.Visible) {
        $idx = $lstCurrencyDropdown.Items.IndexOf($script:Config.Currency)
        if ($idx -ge 0) { $lstCurrencyDropdown.SelectedIndex = $idx }
        $lstCurrencyDropdown.BringToFront()
        $lstCurrencyDropdown.Focus()
    }
})

$lstCurrencyDropdown.Add_Click({
    if ($null -ne $lstCurrencyDropdown.SelectedItem) {
        Set-ActiveCurrency -NewCurrency ([string]$lstCurrencyDropdown.SelectedItem)
    }
})

$lstCurrencyDropdown.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $null -ne $lstCurrencyDropdown.SelectedItem) {
        $e.SuppressKeyPress = $true
        Set-ActiveCurrency -NewCurrency ([string]$lstCurrencyDropdown.SelectedItem)
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $lstCurrencyDropdown.Visible = $false
    }
})

$btnPin.Add_Click({
    $script:Config.TopMost = -not $script:Config.TopMost
    $form.TopMost = $script:Config.TopMost
    $p = $script:Pal
    Style-FlatButton -Btn $btnPin `
        -BgColor $(if ($script:Config.TopMost) { $p.Accent } else { $p.Input }) `
        -FgColor $(if ($script:Config.TopMost) { $p.HeaderBg } else { $p.Text }) `
        -BorderColor $(if ($script:Config.TopMost) { $p.Accent } else { $p.Border })
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
})

$btnCompact.Add_Click({
    Update-LayoutButton
    $layoutMenu.Show($btnCompact, (New-Object System.Drawing.Point(0, $btnCompact.Height)))
})
$layoutMenu.Add_ItemClicked({
    param($sender, $e)
    $tag = [string]$e.ClickedItem.Tag
    if ($tag -like "Layout:*") {
        $sender.Close()
        Apply-Layout ($tag.Substring(7))
    } elseif ($tag -eq "Opt:Watch" -or $tag -eq "Opt:Portfolio") {
        if ($tag -eq "Opt:Watch") { $script:Config.TerminalShowWatch = -not [bool]$script:Config.TerminalShowWatch }
        else { $script:Config.TerminalShowPortfolio = -not [bool]$script:Config.TerminalShowPortfolio }
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        Update-LayoutButton
        if ([string]$script:Config.Layout -eq "Terminal") { Update-MainLayout }
    }
})

$btnTray.Add_Click({ $form.Hide() })
function Show-MainWindow {
    $form.Show()
    # back to maximized if it was maximized (was: always "Normal")
    $form.WindowState = if ([bool]$script:Config.WindowMaximized -and -not [bool]$script:Config.CompactMode) { [System.Windows.Forms.FormWindowState]::Maximized } else { [System.Windows.Forms.FormWindowState]::Normal }
    $form.Activate()
    Update-AllUiViews
}
$miShow.Add_Click({ Show-MainWindow })
$trayMenu.Add_Opening({
    foreach ($it in $miLayout.DropDownItems) { $it.Checked = ([string]$it.Tag -eq [string]$script:Config.Layout) }
})
$miRefresh.Add_Click({ Refresh-AllMarketData -Force; Evaluate-GlobalAlerts; Update-AllUiViews })
$miExit.Add_Click({ $trayIcon.Visible = $false; $form.Close() })
$trayIcon.Add_DoubleClick({ Show-MainWindow })

# Chart Context Menu Actions
$cmiCopyPrice.Add_Click({
    $sym = $script:Config.ActiveTicker.ToUpper()
    if ($script:QuoteStore.ContainsKey($sym)) {
        $q = $script:QuoteStore[$sym]
        $p = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $script:Config.Currency
        [System.Windows.Forms.Clipboard]::SetText(("{0}: {1:N2} {2}" -f $sym, $p, $script:Config.Currency))
    }
})
$cmiAddWatch.Add_Click({
    [void](Add-SymbolToWatchlist -RawSymbol $script:Config.ActiveTicker)
})
$cmiExportCsv.Add_Click({ $btnExportCsv.PerformClick() })
$cmiFullscreen.Add_Click({ Toggle-ChartFullscreen })

$chartContextMenu.Add_Opening({
    $px = $script:CtxPrice
    $sym = $script:Config.ActiveTicker.ToUpper()
    $cmiAlertHere.Enabled = -not [double]::IsNaN($px) -and $script:QuoteStore.ContainsKey($sym)
    if ($cmiAlertHere.Enabled) {
        $q = $script:QuoteStore[$sym]
        $cur = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $script:Config.Currency
        $op = if ($px -ge $cur) { ">=" } else { "<=" }
        $cmiAlertHere.Text = "Alarm: {0} {1} {2} {3}" -f $sym, $op, (Format-LevelPrice $px), $script:Config.Currency
        $cmiAlertHere.Tag = @{ Op = $op; Price = [double](Format-LevelPrice $px -Raw) }
    } else {
        $cmiAlertHere.Text = "Alarm hier setzen (Rechtsklick im Kursbereich)"
    }
    $cmp = [string]$script:Config.CompareTicker
    $cmiCompareOff.Enabled = -not [string]::IsNullOrWhiteSpace($cmp)
    $cmiCompareOff.Text = if ($cmp) { "Vergleich mit $cmp entfernen" } else { "Vergleich entfernen" }
    $cmiZoomReset.Enabled = ([int]$script:ViewCount -gt 0)
})
$cmiAlertHere.Add_Click({
    $t = $cmiAlertHere.Tag
    if ($null -eq $t) { return }
    $sym = $script:Config.ActiveTicker.ToUpper()
    if (Add-WidgetAlert -Ticker $sym -Condition $t.Op -Target $t.Price -Currency $script:Config.Currency -NoConfirm) {
        Set-TransientStatus ("Alarm angelegt: {0} {1} {2:N2} {3}" -f $sym, $t.Op, $t.Price, $script:Config.Currency) 4
        Update-AllUiViews
    }
})
$cmiLevels.Add_Click({
    $script:Config.ShowLevels = $cmiLevels.Checked
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})
$cmiCompare.Add_Click({ Show-CompareDialog })
$cmiCompareOff.Add_Click({ Set-CompareTicker -Symbol "" })
$cmiZoomReset.Add_Click({ Reset-ChartZoom })

# Portfolio Grid & Editor Events
$cmbPortSort.Add_SelectedIndexChanged({
    # choosing a preset ends a header-click sort
    $script:PfSort.Col = ""; $script:PfSort.Step = 0
    Set-GridSortGlyph -Grid $dgvPortfolio -Sort $script:PfSort
    Refresh-PortfolioGrid
})
$dgvPortfolio.Add_ColumnHeaderMouseClick({
    param($sender, $e)
    $name = $sender.Columns[$e.ColumnIndex].Name
    if ($name -eq "Spark") { return }
    Step-GridSort -Sort $script:PfSort -Col $name -TextCols @("Ticker")
    Set-GridSortGlyph -Grid $dgvPortfolio -Sort $script:PfSort
    Refresh-PortfolioGrid
})
$dgvWatchlist.Add_ColumnHeaderMouseClick({
    param($sender, $e)
    Step-GridSort -Sort $script:WlSort -Col ($sender.Columns[$e.ColumnIndex].Name) -TextCols @("Sym")
    Set-GridSortGlyph -Grid $dgvWatchlist -Sort $script:WlSort
    $lblWlTitle.Text = if ($script:WlSort.Col) { "Watchlist (sortiert - 3. Klick = eigene Reihenfolge)" } else { "Watchlist (Ziehen = Reihenfolge | Entf = Löschen)" }
    Refresh-WatchlistAndAlerts
})

# Drag & drop reordering (only in the manual order)
$script:WlDrag = @{ Sym = ""; Pt = [System.Drawing.Point]::Empty }
$dgvWatchlist.Add_MouseDown({
    param($sender, $e)
    $script:WlDrag.Sym = ""
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left -or $script:WlSort.Col) { return }
    $hit = $sender.HitTest($e.X, $e.Y)
    if ($hit.RowIndex -ge 0) {
        $script:WlDrag.Sym = [string]$sender.Rows[$hit.RowIndex].Cells[0].Value
        $script:WlDrag.Pt = $e.Location
    }
})
$dgvWatchlist.Add_MouseMove({
    param($sender, $e)
    if (-not $script:WlDrag.Sym -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $ds = [System.Windows.Forms.SystemInformation]::DragSize
    if ([math]::Abs($e.X - $script:WlDrag.Pt.X) -lt $ds.Width -and [math]::Abs($e.Y - $script:WlDrag.Pt.Y) -lt $ds.Height) { return }
    $sym = $script:WlDrag.Sym
    $script:WlDrag.Sym = ""
    [void]$sender.DoDragDrop($sym, [System.Windows.Forms.DragDropEffects]::Move)
})
$dgvWatchlist.Add_DragOver({
    param($sender, $e)
    $e.Effect = if ($e.Data.GetDataPresent([string]) -and -not $script:WlSort.Col) { [System.Windows.Forms.DragDropEffects]::Move } else { [System.Windows.Forms.DragDropEffects]::None }
})
$dgvWatchlist.Add_DragDrop({
    param($sender, $e)
    $sym = [string]$e.Data.GetData([string])
    if (-not $sym) { return }
    $pt = $sender.PointToClient((New-Object System.Drawing.Point($e.X, $e.Y)))
    $hit = $sender.HitTest($pt.X, $pt.Y)
    $target = if ($hit.RowIndex -ge 0) { $hit.RowIndex } else { $sender.Rows.Count - 1 }
    Move-WatchlistSymbol -Symbol $sym -NewIndex $target
})

$dgvPortfolio.Add_SelectionChanged({
    if ($script:SuppressGridSelection) { return }
    if ($dgvPortfolio.SelectedRows.Count -gt 0) {
        $sym = [string]$dgvPortfolio.SelectedRows[0].Cells[0].Value
        if ($sym -and $script:Portfolio.ContainsKey($sym)) {
            $p = $script:Portfolio[$sym]
            $txtPortTicker.Text = $sym
            $txtPortShares.Text = $p.Shares.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $txtPortAvg.Text    = $p.AvgPrice.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            Select-CurrencyInCombo -Combo $cmbPortCurr -Code $p.Currency
            $txtPortBuyAmt.Text = if ($p.BuyAmount -gt 0) { $p.BuyAmount.ToString([System.Globalization.CultureInfo]::InvariantCulture) } else { "" }
            $txtPortTarget.Text = if ($p.TargetAvg -gt 0) { $p.TargetAvg.ToString([System.Globalization.CultureInfo]::InvariantCulture) } else { "" }
            Update-NachkaufSimulation
        }
    }
})

$dgvPortfolio.Add_CellDoubleClick({
    param($sender, $e)
    if ($e.RowIndex -ge 0) {
        $sym = [string]$sender.Rows[$e.RowIndex].Cells[0].Value
        if ($sym) {
            Set-ActiveTab -TabName "Chart"
            Switch-ActiveTicker -NewTicker $sym -SkipResolve $true
        }
    }
})

$txtPortTicker.Add_TextChanged({ Update-NachkaufSimulation })
$txtPortShares.Add_TextChanged({ Update-NachkaufSimulation })
$txtPortAvg.Add_TextChanged({ Update-NachkaufSimulation })
$cmbPortCurr.Add_SelectedIndexChanged({ Update-NachkaufSimulation })
$txtPortBuyAmt.Add_TextChanged({ Update-NachkaufSimulation })
$txtPortTarget.Add_TextChanged({ Update-NachkaufSimulation })

$btnPortSave.Add_Click({
    foreach ($pair in @(@($txtPortShares, "Stück"), @($txtPortAvg, "EK-Kurs"), @($txtPortBuyAmt, "Nachkauf"), @($txtPortTarget, "Ziel-EK"))) {
        if (-not (Test-DecimalInput $pair[0].Text)) {
            $lblNachkaufOut.Text = "Ungültige Zahl im Feld '$($pair[1])': '$($pair[0].Text)'"
            $pair[0].Focus()
            return
        }
    }
    if ([string]::IsNullOrWhiteSpace($txtPortTicker.Text)) {
        $lblNachkaufOut.Text = "Bitte einen Ticker eingeben."
        return
    }
    $sym = Resolve-BestSymbol -RawInput $txtPortTicker.Text
    $sh  = Parse-DecimalInput $txtPortShares.Text
    $avg = Parse-DecimalInput $txtPortAvg.Text
    if ([string]::IsNullOrWhiteSpace($sym) -or $sh -le 0 -or $avg -le 0) {
        $lblNachkaufOut.Text = "Stück und EK-Kurs müssen größer als 0 sein."
        return
    }

    $posCurr = if ($cmbPortCurr.SelectedItem) { [string]$cmbPortCurr.SelectedItem } else { $script:Config.Currency }
    $txtPortTicker.Text = $sym

    $finalShares = $sh
    $finalAvg    = $avg
    $logBuy      = -not $script:Portfolio.ContainsKey($sym)   # new position = first buy
    if ($script:Portfolio.ContainsKey($sym)) {
        $existing = $script:Portfolio[$sym]
        if ([math]::Abs($existing.Shares - $sh) -gt 0.0001 -or [math]::Abs($existing.AvgPrice - $avg) -gt 0.0001) {
            $ans = [System.Windows.Forms.MessageBox]::Show(
                $form,
                "Position '$sym' existiert bereits ($([math]::Round($existing.Shares, 3)) Stk @ $([math]::Round($existing.AvgPrice, 2)) $($existing.Currency)).`r`n`r`n[Ja] = Zukauf hinzufügen & Durchschnitts-EK berechnen`r`n[Nein] = Bestehende Werte überschreiben",
                "Position zusammenführen?",
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($ans -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
            if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
                $oldAvgInPosCurr = Convert-CurrencyValue -Amount $existing.AvgPrice -FromCurrency $existing.Currency -ToCurrency $posCurr
                $finalShares = $existing.Shares + $sh
                $finalAvg    = (($existing.Shares * $oldAvgInPosCurr) + ($sh * $avg)) / $finalShares
                $logBuy      = $true
            }
        }
    }

    $script:Portfolio[$sym] = [PSCustomObject]@{
        Ticker    = $sym
        Shares    = $finalShares
        AvgPrice  = $finalAvg
        Currency  = $posCurr
        BuyAmount = Parse-DecimalInput $txtPortBuyAmt.Text
        TargetAvg = Parse-DecimalInput $txtPortTarget.Text
    }
    Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
    if ($logBuy) { Add-TransactionRecord -Type "Kauf" -Ticker $sym -Shares $sh -Price $avg -Fee 0 -Currency $posCurr -Date "" -Note "Portfolio-Editor" }
    Refresh-AllMarketData
    Update-AllUiViews
})

$btnPortTx.Add_Click({
    $t = $txtPortTicker.Text.Trim()
    if (-not $t) { $t = $script:Config.ActiveTicker }
    Show-TransactionDialog -Ticker $t
})
$btnPortHist.Add_Click({ Show-TransactionHistory })

$btnPortDel.Add_Click({
    $sym = $txtPortTicker.Text.Trim().ToUpper()
    if ($sym -and $script:Portfolio.ContainsKey($sym)) {
        if (-not (Confirm-Action -Text "Position '$sym' wirklich löschen?" -Title "Portfolio")) { return }
        $script:Portfolio.Remove($sym)
        Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
        Update-AllUiViews
    }
})

# Direct CSV Export from Chart Bar
$btnExportCsv.Add_Click({
    if (-not $script:ActiveSeries -or $script:ActiveSeries.Count -eq 0) { return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "CSV Datei (*.csv)|*.csv"
    $sfd.FileName = "{0}_{1}_{2}.csv" -f $script:Config.ActiveTicker, $script:Config.Timeframe, (Get-Date -Format "yyyyMMdd")
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $csvLines = New-Object System.Collections.Generic.List[string]
        $csvLines.Add("Datum;Open;High;Low;Close;Währung;Volumen")
        foreach ($pt in $script:ActiveSeries) {
            $dtStr = [DateTimeOffset]::FromUnixTimeMilliseconds($pt.Ts).ToLocalTime().ToString("yyyy-MM-dd HH:mm")
            $csvLines.Add(("{0};{1:F4};{2:F4};{3:F4};{4:F4};{5};{6}" -f $dtStr, $pt.Open, $pt.High, $pt.Low, $pt.Close, $script:Config.Currency, $pt.Volume))
        }
        [System.IO.File]::WriteAllLines($sfd.FileName, $csvLines, [System.Text.Encoding]::UTF8)
    }
})

# Watchlist Search, Add, Remove & Alerts Events
$wlSearchTimer = New-Object System.Windows.Forms.Timer
$wlSearchTimer.Interval = 320
$wlSearchTimer.Add_Tick({
    $wlSearchTimer.Stop()
    $q = $txtWlSearch.Text.Trim()
    if ($q.Length -lt 1) {
        $lstWlSearchDropdown.Visible = $false
        return
    }
    $url = Get-SearchUrl -Query $q
    Start-FetchJob -Urls @($url) -MaxConcurrency 1 -Context @{ Query = $q; Url = $url } -OnComplete {
        param($Box, $Ctx)
        if ($txtWlSearch.Text.Trim() -ne $Ctx.Query) { return }   # user typed on
        Show-WlSearchHits -Hits @(ConvertFrom-YahooSearch -Json $Box.Results[$Ctx.Url])
    }
})

function Show-WlSearchHits {
    param([array]$Hits)
    $lstWlSearchDropdown.BeginUpdate()
    $lstWlSearchDropdown.Items.Clear()
    foreach ($h in $Hits) {
        if ($null -ne $h) { [void]$lstWlSearchDropdown.Items.Add($h) }
    }
    $lstWlSearchDropdown.DisplayMember = "Display"
    $lstWlSearchDropdown.EndUpdate()
    if ($lstWlSearchDropdown.Items.Count -gt 0) {
        $lstWlSearchDropdown.SelectedIndex = 0
        $rowsVis = [math]::Min(8, [math]::Max(2, $lstWlSearchDropdown.Items.Count))
        $lstWlSearchDropdown.Height = ($rowsVis * (S 20)) + (S 6)
        $lstWlSearchDropdown.Visible = $true
        $lstWlSearchDropdown.BringToFront()
    } else {
        $lstWlSearchDropdown.Visible = $false
    }
}

$txtWlSearch.Add_TextChanged({
    if ($script:SuppressWlSearchEvent) { return }
    $wlSearchTimer.Stop()
    $wlSearchTimer.Start()
})

$txtWlSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Down -and $lstWlSearchDropdown.Visible -and $lstWlSearchDropdown.Items.Count -gt 0) {
        $e.SuppressKeyPress = $true
        $lstWlSearchDropdown.Focus()
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        $wlSearchTimer.Stop()
        $symToAdd = if ($lstWlSearchDropdown.Visible -and $null -ne $lstWlSearchDropdown.SelectedItem) {
            $lstWlSearchDropdown.SelectedItem.Symbol
        } else {
            $txtWlSearch.Text.Trim()
        }
        $lstWlSearchDropdown.Visible = $false
        if (-not [string]::IsNullOrWhiteSpace($symToAdd)) {
            $script:SuppressWlSearchEvent = $true
            $txtWlSearch.Text = ""
            $script:SuppressWlSearchEvent = $false
            [void](Add-SymbolToWatchlist -RawSymbol $symToAdd)
        }
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $lstWlSearchDropdown.Visible = $false
    }
})

$lstWlSearchDropdown.Add_Click({
    if ($null -ne $lstWlSearchDropdown.SelectedItem) {
        $symToAdd = $lstWlSearchDropdown.SelectedItem.Symbol
        $lstWlSearchDropdown.Visible = $false
        $script:SuppressWlSearchEvent = $true
        $txtWlSearch.Text = ""
        $script:SuppressWlSearchEvent = $false
        [void](Add-SymbolToWatchlist -RawSymbol $symToAdd)
    }
})

$lstWlSearchDropdown.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $null -ne $lstWlSearchDropdown.SelectedItem) {
        $e.SuppressKeyPress = $true
        $symToAdd = $lstWlSearchDropdown.SelectedItem.Symbol
        $lstWlSearchDropdown.Visible = $false
        $script:SuppressWlSearchEvent = $true
        $txtWlSearch.Text = ""
        $script:SuppressWlSearchEvent = $false
        [void](Add-SymbolToWatchlist -RawSymbol $symToAdd)
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $lstWlSearchDropdown.Visible = $false
    }
})

$btnWlAddSearch.Add_Click({
    $wlSearchTimer.Stop()
    $symToAdd = if ($lstWlSearchDropdown.Visible -and $null -ne $lstWlSearchDropdown.SelectedItem) {
        $lstWlSearchDropdown.SelectedItem.Symbol
    } else {
        $txtWlSearch.Text.Trim()
    }
    $lstWlSearchDropdown.Visible = $false
    if (-not [string]::IsNullOrWhiteSpace($symToAdd)) {
        $script:SuppressWlSearchEvent = $true
        $txtWlSearch.Text = ""
        $script:SuppressWlSearchEvent = $false
        [void](Add-SymbolToWatchlist -RawSymbol $symToAdd)
    }
})

$dgvWatchlist.Add_CellDoubleClick({
    param($sender, $e)
    if ($e.RowIndex -ge 0) {
        $sym = [string]$sender.Rows[$e.RowIndex].Cells[0].Value
        if ($sym) {
            Set-ActiveTab -TabName "Chart"
            Switch-ActiveTicker -NewTicker $sym -SkipResolve $true
        }
    }
})

$dgvWatchlist.Add_KeyDown({
    param($sender, $e)
    if ($e.Alt -and ($e.KeyCode -eq [System.Windows.Forms.Keys]::Up -or $e.KeyCode -eq [System.Windows.Forms.Keys]::Down) -and $dgvWatchlist.SelectedRows.Count -gt 0) {
        $e.Handled = $true
        if ($script:WlSort.Col) { Set-TransientStatus "Reihenfolge ändern: erst Sortierung aufheben (Spaltenkopf 3x klicken)" 4; return }
        $sym = [string]$dgvWatchlist.SelectedRows[0].Cells[0].Value
        $idx = @($script:Config.Watchlist).IndexOf($sym)
        Move-WatchlistSymbol -Symbol $sym -NewIndex ($idx + $(if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Up) { -1 } else { 1 }))
        return
    }
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete -and $dgvWatchlist.SelectedRows.Count -gt 0) {
        $e.Handled = $true
        $sym = [string]$dgvWatchlist.SelectedRows[0].Cells[0].Value
        [void](Remove-SymbolFromWatchlist -Symbol $sym)
    }
})

$btnWlAddActive.Add_Click({
    [void](Add-SymbolToWatchlist -RawSymbol $script:Config.ActiveTicker)
})

$btnWlRemove.Add_Click({
    if ($dgvWatchlist.SelectedRows.Count -gt 0) {
        $sym = [string]$dgvWatchlist.SelectedRows[0].Cells[0].Value
        [void](Remove-SymbolFromWatchlist -Symbol $sym)
    }
})

$btnAddAlert.Add_Click({
    $aCond = [string]$cmbAlertCond.SelectedItem
    $kind  = Get-AlertKind $aCond
    $raw   = $txtAlertPrice.Text
    $aPrice = 0.0
    if ($kind -ne "SMA") {
        # Tag% may be negative, RSI 0..100, price > 0. SMA alerts need no value.
        $aPrice = Parse-DecimalInput $raw
        $bad = [string]::IsNullOrWhiteSpace($raw) -or -not (Test-DecimalInput $raw) -or
               ($kind -eq "PRICE" -and $aPrice -le 0) -or ($kind -eq "RSI" -and ($aPrice -le 0 -or $aPrice -ge 100))
        if ($bad) {
            Set-TransientStatus "Ungültiger Alarm-Wert: '$raw'"
            return
        }
    }
    $aSym = Resolve-BestSymbol -RawInput $txtAlertTicker.Text
    if ([string]::IsNullOrWhiteSpace($aSym)) { return }
    $txtAlertTicker.Text = $aSym
    $curr = switch ($kind) { "PCT" { "%" } "RSI" { "RSI" } "SMA" { "SMA" } default { $script:Config.Currency } }
    $rearm = 0
    if ($null -ne $cmbAlertRearm.SelectedItem) { $rearm = [int]$script:RearmChoices[[string]$cmbAlertRearm.SelectedItem] }
    $ok = Add-WidgetAlert -Ticker $aSym -Condition $aCond -Target $aPrice -Currency $curr -Note $txtAlertNote.Text.Trim() -RearmMin $rearm
    if (-not $ok) { return }
    $txtAlertPrice.Text = ""
    $txtAlertNote.Text = ""
    Refresh-AllMarketData
    Evaluate-GlobalAlerts
    Update-AllUiViews
})

$btnDelAlert.Add_Click({
    $idx = $lstAlerts.SelectedIndex
    if ($idx -ge 0 -and $idx -lt $script:Alerts.Count) {
        if (-not (Confirm-Action -Text "Alarm '$($lstAlerts.Items[$idx])' löschen?" -Title "Preis-Alarm")) { return }
        $script:Alerts.RemoveAt($idx)
        Save-JsonState -Path $script:AlertsPath -Data $script:Alerts.ToArray()
        Update-AllUiViews
    }
})

$cmbAlertCond.Add_SelectedIndexChanged({
    $kind = Get-AlertKind ([string]$cmbAlertCond.SelectedItem)
    $isSma = ($kind -eq "SMA")
    $txtAlertPrice.Enabled = -not $isSma
    if ($isSma) { $txtAlertPrice.Text = "" }
    # v3.0: say what the value means for the chosen condition
    $hint = switch ($kind) {
        "PCT"   { "Tagesänderung in %, z.B. -3 oder 2,5" }
        "RSI"   { "RSI-Wert 1..99 (Stundenbasis), z.B. 70" }
        "SMA"   { "Kein Wert nötig: Kurs kreuzt SMA$($script:Config.SmaFastPeriod) (1h)" }
        default { "Kurs in $($script:Config.Currency) (Anzeigewährung)" }
    }
    Set-Tip $txtAlertPrice $hint "ALERTCOND"
})
$cmbAlertCond.SelectedIndex = 1; $cmbAlertCond.SelectedIndex = 0   # fire once for the hint

$txtAlertPrice.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        $btnAddAlert.PerformClick()
    }
})

$lstAlerts.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete) {
        $e.SuppressKeyPress = $true
        $btnDelAlert.PerformClick()
    }
})

$lstAlerts.Add_DoubleClick({
    $idx = $lstAlerts.SelectedIndex
    if ($idx -ge 0 -and $idx -lt $script:Alerts.Count) {
        $script:Alerts[$idx].Triggered = -not $script:Alerts[$idx].Triggered
        $script:Alerts[$idx].TriggeredAt = if ($script:Alerts[$idx].Triggered) { (Get-Date).ToString("o") } else { "" }
        Save-JsonState -Path $script:AlertsPath -Data $script:Alerts.ToArray()
        Refresh-WatchlistAndAlerts
    }
})

# Header Ticker Dropdown & Live Search Events
$btnTickerDrop.Add_Click({
    $lstCurrencyDropdown.Visible = $false
    if ($lstTickerDropdown.Visible) {
        $lstTickerDropdown.Visible = $false
    } else {
        Populate-TickerDropdown -FilterText ""
    }
})

# Focus alone no longer opens the dropdown (it popped open on startup and on
# every window activation). It opens on click, typing, Down arrow or the arrow button.
$txtSearch.Add_GotFocus({
    [void]$txtSearch.BeginInvoke([Action]{ $txtSearch.SelectAll() })
})
$txtSearch.Add_MouseClick({
    if (-not $lstTickerDropdown.Visible) { Populate-TickerDropdown -FilterText "" }
})

$searchTimer = New-Object System.Windows.Forms.Timer
$searchTimer.Interval = 300
$searchTimer.Add_Tick({
    $searchTimer.Stop()
    $q = $txtSearch.Text.Trim()
    if ($q.Length -eq 0) {
        Populate-TickerDropdown -FilterText ""
    } elseif ($q -ne $script:Config.ActiveTicker) {
        # Local matches right away, Yahoo hits are appended when they arrive
        Populate-TickerDropdown -FilterText $q
        $url = Get-SearchUrl -Query $q
        Start-FetchJob -Urls @($url) -MaxConcurrency 1 -Context @{ Query = $q; Url = $url } -OnComplete {
            param($Box, $Ctx)
            # user kept typing or already picked something: drop the stale result
            if ($txtSearch.Text.Trim() -ne $Ctx.Query -or ((-not $txtSearch.Focused) -and (-not $lstTickerDropdown.Focused))) { return }
            $hits = @(ConvertFrom-YahooSearch -Json $Box.Results[$Ctx.Url])
            if ($hits.Count -gt 0) { Populate-TickerDropdown -FilterText $Ctx.Query -SearchHits $hits }
        }
    }
})

$txtSearch.Add_TextChanged({
    if ($script:SuppressSearchEvent) { return }
    $searchTimer.Stop()
    $searchTimer.Start()
})

$txtSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Down) {
        $e.SuppressKeyPress = $true
        if (-not $lstTickerDropdown.Visible) {
            Populate-TickerDropdown -FilterText ""
        }
        if ($lstTickerDropdown.Visible -and $lstTickerDropdown.Items.Count -gt 0) {
            $lstTickerDropdown.Focus()
        }
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        $searchTimer.Stop()
        $typed = $txtSearch.Text.Trim().ToUpper()
        if ($lstTickerDropdown.Visible -and $null -ne $lstTickerDropdown.SelectedItem -and $typed -ne $lstTickerDropdown.SelectedItem.Symbol -and $typed.Length -gt 0) {
            $selSym = $lstTickerDropdown.SelectedItem.Symbol
            $lstTickerDropdown.Visible = $false
            Switch-ActiveTicker -NewTicker $selSym -SkipResolve $true
        } elseif ($typed.Length -gt 0) {
            $lstTickerDropdown.Visible = $false
            Switch-ActiveTicker -NewTicker $typed -SkipResolve $false
        }
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $lstTickerDropdown.Visible = $false
        $script:SuppressSearchEvent = $true
        $txtSearch.Text = $script:Config.ActiveTicker
        $script:SuppressSearchEvent = $false
    }
})

$lstTickerDropdown.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $null -ne $lstTickerDropdown.SelectedItem) {
        $e.SuppressKeyPress = $true
        $selSym = $lstTickerDropdown.SelectedItem.Symbol
        $lstTickerDropdown.Visible = $false
        Switch-ActiveTicker -NewTicker $selSym -SkipResolve $true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete -and $null -ne $lstTickerDropdown.SelectedItem) {
        $e.SuppressKeyPress = $true
        $delSym = $lstTickerDropdown.SelectedItem.Symbol
        if (Remove-SymbolFromWatchlist -Symbol $delSym) {
            Populate-TickerDropdown -FilterText ""
        }
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $lstTickerDropdown.Visible = $false
    }
})

$lstTickerDropdown.Add_MouseUp({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $idx = $lstTickerDropdown.IndexFromPoint($e.Location)
        if ($idx -ge 0) {
            $lstTickerDropdown.SelectedIndex = $idx
            $delSym = $lstTickerDropdown.Items[$idx].Symbol
            if (Remove-SymbolFromWatchlist -Symbol $delSym) {
                Populate-TickerDropdown -FilterText ""
            }
        }
    }
})

$lstTickerDropdown.Add_Click({
    if ($null -ne $lstTickerDropdown.SelectedItem) {
        $selSym = $lstTickerDropdown.SelectedItem.Symbol
        $lstTickerDropdown.Visible = $false
        Switch-ActiveTicker -NewTicker $selSym -SkipResolve $true
    }
})

# Close open dropdown popups when clicking anywhere else
$pnlChartCanvas.Add_MouseDown({ $lstTickerDropdown.Visible = $false; $lstCurrencyDropdown.Visible = $false })
$pnlChartControls.Add_MouseDown({ $lstTickerDropdown.Visible = $false; $lstCurrencyDropdown.Visible = $false })
$pnlNav.Add_MouseDown({ $lstTickerDropdown.Visible = $false; $lstCurrencyDropdown.Visible = $false })
$dgvPortfolio.Add_MouseDown({ $lstTickerDropdown.Visible = $false; $lstCurrencyDropdown.Visible = $false })
$dgvWatchlist.Add_MouseDown({ $lstTickerDropdown.Visible = $false; $lstCurrencyDropdown.Visible = $false; $lstWlSearchDropdown.Visible = $false })

# Global Keyboard Shortcuts (used by the main window AND the fullscreen chart)
$script:GlobalKeyHandler = {
    param($sender, $e)
    $isFs = ($null -ne $script:FsForm -and [object]::ReferenceEquals($sender, $script:FsForm))
    # F11: fullscreen chart on/off; Esc closes the fullscreen chart
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F11 -and -not $e.Control -and -not $e.Alt) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        Toggle-ChartFullscreen
        return
    }
    # Esc: first clears a measurement, then closes the fullscreen chart
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape -and $script:Measure.Active) {
        $e.Handled = $true
        Clear-ChartMeasure
        return
    }
    if ($isFs -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $e.Handled = $true
        Close-ChartFullscreen
        return
    }
    # Ctrl+F: jump to the ticker search (main window only)
    if (-not $isFs -and $e.Control -and -not $e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        $txtSearch.Focus()
        $txtSearch.SelectAll()
        if (-not $script:Config.CompactMode) { Populate-TickerDropdown -FilterText "" }
        return
    }
    # Other Ctrl/Alt combos (Ctrl+C, Alt+F4, ...) are never widget shortcuts
    if ($e.Control -or $e.Alt) { return }
    $ac = $sender.ActiveControl
    $isFKey = $e.KeyCode -in @([System.Windows.Forms.Keys]::F1, [System.Windows.Forms.Keys]::F2, [System.Windows.Forms.Keys]::F3, [System.Windows.Forms.Keys]::F5)
    # Typing into inputs/lists must not trigger letter shortcuts (F-keys still work)
    if (($ac -is [System.Windows.Forms.TextBox] -or $ac -is [System.Windows.Forms.ComboBox] -or $ac -is [System.Windows.Forms.ListBox]) -and -not $isFKey) { return }
    # Arrow keys belong to the grid when a grid has focus
    if ($ac -is [System.Windows.Forms.DataGridView] -and $e.KeyCode -in @([System.Windows.Forms.Keys]::Left, [System.Windows.Forms.Keys]::Right)) { return }

    # 1-6 (top row or numpad): timeframe 1D / 5D / 1M / 3M / 6M / 1Y
    $kc = [int]$e.KeyCode
    $tfIdx = -1
    if ($kc -ge [int][System.Windows.Forms.Keys]::D1 -and $kc -le [int][System.Windows.Forms.Keys]::D6) { $tfIdx = $kc - [int][System.Windows.Forms.Keys]::D1 }
    elseif ($kc -ge [int][System.Windows.Forms.Keys]::NumPad1 -and $kc -le [int][System.Windows.Forms.Keys]::NumPad6) { $tfIdx = $kc - [int][System.Windows.Forms.Keys]::NumPad1 }
    if ($tfIdx -ge 0) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        Set-Timeframe -Tf $tfList[$tfIdx]
        return
    }

    switch ($e.KeyCode) {
        ([System.Windows.Forms.Keys]::F1) { Set-ActiveTab -TabName "Chart"; $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F2) { Set-ActiveTab -TabName "Portfolio"; $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F3) { Set-ActiveTab -TabName "Watchlist"; $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F5) {
            Refresh-AllMarketData -Force; Evaluate-GlobalAlerts; Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::Left) {
            $wl = @($script:Config.Watchlist)
            if ($wl.Count -gt 1) {
                $idx = $wl.IndexOf($script:Config.ActiveTicker.ToUpper())
                $prevIdx = if ($idx -le 0) { $wl.Count - 1 } else { $idx - 1 }
                Switch-ActiveTicker -NewTicker $wl[$prevIdx] -SkipResolve $true
                $e.Handled = $true
            }
        }
        ([System.Windows.Forms.Keys]::Right) {
            $wl = @($script:Config.Watchlist)
            if ($wl.Count -gt 1) {
                $idx = $wl.IndexOf($script:Config.ActiveTicker.ToUpper())
                $nextIdx = if ($idx -lt 0 -or $idx -ge ($wl.Count - 1)) { 0 } else { $idx + 1 }
                Switch-ActiveTicker -NewTicker $wl[$nextIdx] -SkipResolve $true
                $e.Handled = $true
            }
        }
        ([System.Windows.Forms.Keys]::W) {
            Set-ActiveCurrency -NewCurrency (Get-NextDisplayCurrency $script:Config.Currency); $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::C) {
            Toggle-CompactLayout; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::L) {
            if (-not $isFs) { Apply-Layout (Get-NextLayout ([string]$script:Config.Layout)) }
            $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::G) {
            Show-GlossaryDialog; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::T) {
            $btnThemeCycle.PerformClick(); $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::K) {
            $script:Config.ChartType = if ($script:Config.ChartType -eq "Candle") { "Line" } else { "Candle" }
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::V) {
            $script:Config.ShowVolume = -not $script:Config.ShowVolume
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::A) {
            $script:Config.ShowVwap = -not $script:Config.ShowVwap
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::B) {
            $script:Config.ShowBollinger = -not $script:Config.ShowBollinger
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::R) {
            $script:Config.ShowRsi = -not $script:Config.ShowRsi
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::E) {
            Toggle-ExtendedHours; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::H) {
            Show-ShortcutHelp; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::Z) {
            Reset-ChartZoom; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::X) {
            if ($script:Config.CompareTicker) { Set-CompareTicker -Symbol "" } else { Show-CompareDialog }
            $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::S) {
            if (-not $isFs) { Show-SettingsDialog }
            $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::M) {
            $script:Config.ShowSma = -not $script:Config.ShowSma
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::Escape) {
            if ($lstTickerDropdown.Visible -or $lstCurrencyDropdown.Visible -or $lstWlSearchDropdown.Visible) {
                $lstTickerDropdown.Visible = $false
                $lstCurrencyDropdown.Visible = $false
                $lstWlSearchDropdown.Visible = $false
                $e.Handled = $true
            } elseif ($script:Config.CompactMode) {
                Apply-Layout ([string]$script:Config.LastFullLayout); $e.Handled = $true
            }
        }
    }
}
$form.Add_KeyDown($script:GlobalKeyHandler)

# Background Poll Timer
$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = ([int]$script:Config.RefreshSeconds * 1000)
function Flush-ErrorsToLog {
    # Event-handler errors only go to the (hidden) console; copy them to the log
    if ($global:Error.Count -gt 0) {
        $errs = @($global:Error)
        $global:Error.Clear()
        [array]::Reverse($errs)
        foreach ($er in $errs) {
            $line = if ($er.InvocationInfo) { $er.InvocationInfo.ScriptLineNumber } else { "?" }
            Write-WidgetLog ("PS error @ line {0}: {1}" -f $line, $er.ToString()) "ERROR"
        }
    }
}

$pollTimer.Add_Tick({
    if ($script:IsClosing) { return }
    Flush-ErrorsToLog
    try {
        if ($script:IsRefreshing) {
            # Watchdog: HttpClient times out long before this, but never hang forever
            if (((Get-Date) - $script:RefreshStarted).TotalSeconds -lt 90) { return }
            Write-WidgetLog "Refresh did not finish within 90 s, starting a new one" "WARN"
            $script:IsRefreshing = $false
        }
        # HTTP 429 backoff: skip automatic polls until the pause is over
        if ((Get-Date) -lt $script:BackoffUntil) {
            Update-StatusLine
            return
        }
        # Asynchronous: alerts + UI update run when the data has arrived
        Refresh-AllMarketData
    } catch {
        Write-WidgetLog "Poll tick failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
    }
})

# 1-second UI timer: market status countdown & "market open" notifications
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 1000
$script:LastUiTick = [DateTime]::MinValue
$uiTimer.Add_Tick({
    if ($script:IsClosing) { return }
    # v4.0: the 1-second timer did not run for a while -> the PC slept. The
    # data is old and a rate-limit pause from before the sleep is over.
    $nowTick = Get-Date
    $gapFrom = $script:LastUiTick
    $script:LastUiTick = $nowTick
    if (Test-ResumeGap -Last $gapFrom -Now $nowTick -ThresholdSec 90) {
        Write-WidgetLog ("Resume detected (no timer tick for {0:N0} s), refreshing" -f ($nowTick - $gapFrom).TotalSeconds)
        $script:BackoffUntil = [DateTime]::MinValue
        $script:BackoffLevel = 0
        if ($script:IsRefreshing -and (($nowTick - $script:RefreshStarted).TotalSeconds -gt 30)) { $script:IsRefreshing = $false }
        Set-TransientStatus "Aufgewacht - Kurse werden aktualisiert..." 4
        try { Refresh-AllMarketData -Force } catch { Write-WidgetLog "Resume refresh failed: $($_.Exception.Message)" "WARN" }
    }
    try {
        if ($form.Visible) { Update-MarketStatusUi; Update-StatusLine }
        Check-MarketOpenNotifications
    } catch {
        Write-WidgetLog "UI tick failed: $($_.Exception.Message)" "WARN"
    }
})

# Buttons normally swallow Left/Right as focus navigation, so the global
# "previous/next ticker" shortcut never fired. Mark them as input keys.
function Register-ArrowKeysAsInput {
    param([System.Windows.Forms.Control]$Root)
    foreach ($ctl in $Root.Controls) {
        if ($ctl -is [System.Windows.Forms.Button]) {
            $ctl.Add_PreviewKeyDown({
                param($sender, $e)
                if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Left -or $e.KeyCode -eq [System.Windows.Forms.Keys]::Right) {
                    $e.IsInputKey = $true
                }
            })
        }
        if ($ctl.HasChildren) { Register-ArrowKeysAsInput -Root $ctl }
    }
}
Register-ArrowKeysAsInput -Root $form

$form.Add_Shown({
    Flush-ErrorsToLog
    Write-WidgetLog "Widget v$($script:AppVersion) window shown"
    $txtPortTicker.Text = $script:Config.ActiveTicker
    Apply-ThemeToAllControls
    $wasMax = [bool]$script:Config.WindowMaximized
    Apply-Layout ([string]$script:Config.Layout)
    Apply-TooltipMode
    if ($wasMax -and -not [bool]$script:Config.CompactMode) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
    }
    $script:StartupDone = $true
    # Start with focus on a button, not the search box (which used to pop the dropdown open)
    if (-not $script:Config.CompactMode) { $tabButtons[$script:Config.ActiveTab].Select() } else { $btnCompact.Select() }
    Refresh-AllMarketData -Force
    Evaluate-GlobalAlerts
    Update-AllUiViews
    $pollTimer.Start()
    $uiTimer.Start()
    try { Update-OldAutostart } catch { }
    if ($script:MigratedFromOld) {
        Set-TransientStatus "Daten aus v3 übernommen (alter Ordner unverändert)" 8
    }
    try { Show-CurrencyMismatchNotice } catch { Write-WidgetLog "Currency check failed: $($_.Exception.Message)" "WARN" }
})

$form.Add_FormClosing({
    $script:IsClosing = $true
    if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed) { try { $script:FsForm.Close() } catch { } }
    $pollTimer.Stop()
    $uiTimer.Stop()
    $tapeTimer.Stop()
    $searchTimer.Stop()
    $wlSearchTimer.Stop()
    # Let running background fetches bail out (their callbacks are skipped)
    Stop-FetchWorker
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) {
        $script:Config.WindowX = $form.Location.X
        $script:Config.WindowY = $form.Location.Y
        Save-WindowSize
    }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Prune-IntradayCache
    Save-JsonState -Path $script:CachePath  -Data $script:IntradayCache
    Save-QuoteCache
    $trayIcon.Visible = $false
    Write-WidgetLog "Widget closing"
    # Resources are disposed after Application.Run returns: a refresh may still
    # be on the call stack (inside DoEvents) and must not hit disposed objects.
})

Write-WidgetLog "Starting message loop"
try {
    [void][System.Windows.Forms.Application]::Run($form)
} catch {
    Write-WidgetLog "Fatal: $($_.Exception.Message)" "ERROR"
} finally {
    Flush-ErrorsToLog
    try { $trayIcon.Dispose() } catch { }
    try { $trayMenu.Dispose() } catch { }
    try { $chartContextMenu.Dispose() } catch { }
    try { $toolTip.Dispose() } catch { }
    if ($script:TrayIconHandle -ne [IntPtr]::Zero) { try { [void][Win32WidgetHelperV26]::DestroyIcon($script:TrayIconHandle) } catch { } }
    foreach ($val in $script:GdiCache.Values) {
        if ($null -ne $val -and $val -is [System.IDisposable]) { try { $val.Dispose() } catch { } }
    }
    foreach ($k in @($script:ChartBmpCache.Keys)) { Remove-ChartBitmap -Key $k }
    if ($null -ne $script:TapeBitmap) { try { $script:TapeBitmap.Dispose() } catch { } }
    foreach ($f in @($fontTicker, $fontPrice, $fontUi, $fontUiBold, $fontMono, $fontAxis, $fontBadge)) {
        try { $f.Dispose() } catch { }
    }
    if ($null -ne $script:HttpClient) { try { $script:HttpClient.Dispose() } catch { } }
    if ($null -ne $script:AppMutex) {
        try { $script:AppMutex.ReleaseMutex() } catch { }
        $script:AppMutex.Dispose()
    }
}