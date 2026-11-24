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

$script:AppVersion    = "5.2"
$script:SchemaVersion = 5
$script:AppTitle      = "Terminal Widget v$($script:AppVersion)"

# ==============================================================================
# Part 1: Storage Paths, Atomic Persistence & Config Migration
# ==============================================================================
# v4.5: portable.txt next to the script = data in <program folder>\data
$script:IsPortable    = Test-Path (Join-Path $script:ScriptDir "portable.txt")
$script:DataDir       = if ($script:IsPortable) { Join-Path $script:ScriptDir "data" } else { Join-Path $env:LOCALAPPDATA "TerminalWidget" }
# v4.7: the CI smoke test runs on its own data folder
if ($env:TW_SMOKE_TEST -and $env:TW_SMOKE_DIR) { $script:DataDir = $env:TW_SMOKE_DIR }
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
    # v4.5: after a restore / import the files on disk must stay as they are
    if ($script:FreezeData) { return }
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
        $files = @(@("config.json", "portfolio.json", "alerts.json", "transactions.json", "profiles.json", "events.json", "alert-log.json", "cash.json", "savingsplans.json", "drawings.json") |
            ForEach-Object { Join-Path $script:DataDir $_ } | Where-Object { Test-Path $_ })
        if ($files.Count -eq 0) { return "" }
        $safe = ($Reason -replace '[^A-Za-z0-9_.-]', '_')
        $dest = Join-Path $script:BackupDir ("{0}_{1}" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $safe)
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        foreach ($f in $files) { Copy-Item -Path $f -Destination $dest -Force }
        # v4.5: further depots
        $dd = Join-Path $script:DataDir "depots"
        if (Test-Path $dd) { Copy-Item -Path $dd -Destination (Join-Path $dest "depots") -Recurse -Force }
        $all = @(Get-ChildItem -Path $script:BackupDir -Directory | Sort-Object Name -Descending)
        if ($all.Count -gt 20) {
            $all | Select-Object -Skip 20 | ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
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
    AutoCurrency          = $true             # v5.1: price + chart in the ticker's own currency (depot stays in Currency)
    UiStyle               = "Refined"         # v5.2: Refined (same layout, cleaner) / Fresh (rounded cards, more space)
    RowDensity            = "Normal"          # v5.2: Compact / Normal / Comfortable list rows
    ZebraRows             = $false            # v5.2: every second list row slightly lighter
    UseIcons              = $true             # v5.2: Segoe Fluent / MDL2 icons on buttons and menus
    TapeSpeed             = "Normal"          # v5.2: ticker bar Slow / Normal / Fast
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
    NotifyEarnings        = $true
    # v4.3: phone push + quiet hours
    PushService           = "Aus"
    PushServer            = "https://ntfy.sh"
    PushTopic             = ""
    PushTokenEnc          = ""
    PushChatId            = ""
    PushAlerts            = $true
    PushEarnings          = $false
    QuietFrom             = ""
    QuietTo               = ""
    # v4.4
    CommandHistory        = @()
    ClosedPollMinutes     = 10
    # v4.5
    Depots                = @()
    ActiveDepot           = ""
    MainDepotName         = "Hauptdepot"
    LastAutoBackup        = ""
    # v4.6
    MaType                = "SMA"
    LowerPanel            = "RSI"
    UpDownScheme          = "Standard"
    UpColor               = ""
    DownColor             = ""
    AccentHex             = ""
    ShowArrows            = $false
    PriceFlash            = $true
    GlobalHotkey          = "Ctrl+Alt+W"
    SnapToEdges           = $true
    GridLayouts           = [PSCustomObject]@{}
    UserLayouts           = @()
    FirstRunDone          = $false
    # v4.7
    Language              = "DE"
    # v4.8
    LogScale              = $false
    CompactShow           = "DayAbs,Ext,Spark,Market"
    # v4.9: news tab + look and feel
    NewsFilter            = "All"             # All / Holdings / Watchlist / <ticker>
    NewsSeenAt            = ""                # newest item seen in the news tab (ISO, local)
    NewsRefreshMinutes    = 15
    NewsMoveThreshold     = 3                 # mark items of tickers moving >= x % today (0 = off)
    MonoFont              = "Consolas"        # numbers and tickers (from the next start)
    FontScale             = 100               # 90 / 100 / 110 / 120 % (from the next start)
    AlignNumbersRight     = $true             # numbers right-aligned in the lists
    RoundCorners          = $true             # Windows 11 rounded window corners
    # v5.0
    RiskFreePct           = 2.0               # risk-free rate for the Sharpe ratio
    TargetWeights         = [PSCustomObject]@{} # depot id ("main") -> ticker -> target %
    # v4.9.5
    NewsMuted             = @()               # muted news sources (publisher names)
    NewsKeywords          = ""                # "downgrade, übernahme" -> push for held tickers
    NewsKeywordWatch      = $false            # keywords also for watchlist tickers
    NewsKeywordLastAt     = ""                # newest item already checked for keywords (ISO)
    TrayFollowsDepot      = $true             # tray icon colour = depot day result
    PrivacyMode           = $false            # F9: hide amounts, keep percentages
    RecentTickers         = @()               # last opened tickers (search list)
    ShowPrevClose         = $true             # dotted previous-close line in the chart
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
    CompareMore           = @()               # v5.0: up to 2 more comparison tickers
    ShowTrades            = $true             # v5.0: own buys / sells in the chart
    Autostart             = $false
    # v4.0
    Layout                = "Standard"        # Ticker / Compact / Standard / Terminal
    LastFullLayout        = "Standard"        # where C / Expand returns to
    TerminalShowWatch     = $true
    TerminalShowPortfolio = $true
    TerminalChartPct      = 55
    TerminalSplitPct      = 50                # v5.0: watchlist share when side by side
    TerminalFull          = ""                # v5.0: list shown as a full page (restored at start)
    ReopenAnalysis        = ""                # v5.0: Analyse page that was open when the widget closed
    AnalysisLastPage      = "Perf"
    WatchGroups           = @()               # v5.0: @{ Name; Symbols }
    WatchGroup            = ""                # shown group, "" = all
    HoverCards            = $true             # v5.0: info card when the mouse rests on a ticker
    TerminalBottom        = "Watchlist"       # bottom panel when only one fits
    TerminalW             = 0                 # remembered client size of the Terminal layout
    TerminalH             = 0
    Opacity               = 100
    TooltipMode           = "Short"           # Off / Short / Long
    TooltipDelayMs        = 400
    ReportBase            = "EUR"
    # v4.1: portfolio analytics
    AnalysisCompare       = "EUNL.DE, ^GSPC, ^GDAXI, ^ATX"   # v5.1: indices on the Vergleich page
    ScenarioPct           = -20               # v5.1: market move for the scenario
    AnalysisBenchmark     = "EUNL.DE"         # iShares Core MSCI World (Xetra, EUR); "" = none
    AnalysisBase          = ""                # "" = display currency
    AnalysisRange         = "Max"             # 6M / 1Y / 3Y / Max
    AnalysisShowBench     = $true
    AnalysisShowInvested  = $true
    ConcentrationWarnPct  = 20
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
if ($script:Config.ChartType -notin @("Line", "Candle", "HA")) { $script:Config.ChartType = "Line" }
if ($script:Config.ActiveTab -notin @("Chart", "Portfolio", "Watchlist", "News")) { $script:Config.ActiveTab = "Chart" }
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
$script:Config.AnalysisBenchmark = ([string]$script:Config.AnalysisBenchmark).Trim().ToUpper()
if ([string]$script:Config.AnalysisRange -notin @("6M", "1Y", "3Y", "Max")) { $script:Config.AnalysisRange = "Max" }
$script:Config.ConcentrationWarnPct = [math]::Max(5, [math]::Min(90, [int]$script:Config.ConcentrationWarnPct))
if ([string]$script:Config.TerminalBottom -notin @("Watchlist", "Portfolio", "News")) { $script:Config.TerminalBottom = "Watchlist" }
$script:Config.NewsRefreshMinutes = [math]::Max(5, [math]::Min(240, [int]$script:Config.NewsRefreshMinutes))
$script:Config.NewsMoveThreshold  = [math]::Max(0, [math]::Min(50, [int]$script:Config.NewsMoveThreshold))
if ([int]$script:Config.FontScale -notin @(Get-FontScaleSteps)) { $script:Config.FontScale = 100 }
if ([string]$script:Config.MonoFont -notin @(Get-MonoFontNames)) { $script:Config.MonoFont = "Consolas" }
if (-not (Get-NormalizedCurrencyCode ([string]$script:Config.ReportBase))) { $script:Config.ReportBase = "EUR" }
if ($script:Config.AccentColor -notin @("Sky", "Amber", "Violet", "Eigene", "Windows")) { $script:Config.AccentColor = "Sky" }
if ([string]$script:Config.UiStyle -notin @(Get-UiStyles)) { $script:Config.UiStyle = "Refined" }
if ([string]$script:Config.RowDensity -notin @(Get-RowDensities)) { $script:Config.RowDensity = "Normal" }
if ([string]$script:Config.TapeSpeed -notin @(Get-TapeSpeeds)) { $script:Config.TapeSpeed = "Normal" }
if ([string]$script:Config.MaType -notin @("SMA", "EMA")) { $script:Config.MaType = "SMA" }
if ([string]$script:Config.LowerPanel -notin @("RSI", "MACD")) { $script:Config.LowerPanel = "RSI" }
if ([int]$script:Config.RefreshSeconds -lt 5) { $script:Config.RefreshSeconds = 15 }
if ([int]$script:Config.SlowRefreshSeconds -lt [int]$script:Config.RefreshSeconds) { $script:Config.SlowRefreshSeconds = [math]::Max(60, [int]$script:Config.RefreshSeconds) }
if ([int]$script:Config.SmaFastPeriod -lt 2) { $script:Config.SmaFastPeriod = 20 }
if ([int]$script:Config.SmaSlowPeriod -lt 5) { $script:Config.SmaSlowPeriod = 50 }
if ([int]$script:Config.RsiPeriod -lt 2) { $script:Config.RsiPeriod = 14 }

# ------------------------------------------------------------------------------
# Depots (v4.5): several portfolios. The main depot uses portfolio.json /
# transactions.json in the data folder (as before), others live in
# depots\<id>\. Alerts, profiles and event dates are shared.
# ------------------------------------------------------------------------------
$script:DepotDir = Join-Path $script:DataDir "depots"

function Get-DepotList {
    $list = @([PSCustomObject]@{ Id = ""; Name = $(if ($script:Config.MainDepotName) { [string]$script:Config.MainDepotName } else { "Hauptdepot" }) })
    foreach ($d in @($script:Config.Depots)) { if ($null -ne $d -and $d.Id) { $list += [PSCustomObject]@{ Id = [string]$d.Id; Name = [string]$d.Name } } }
    return $list
}

function Get-DepotName {
    param([string]$Id)
    foreach ($d in Get-DepotList) { if ($d.Id -eq $Id) { return $d.Name } }
    return ""
}

function Set-DepotPaths {
    param([string]$Id)
    if (-not $Id) {
        $script:PortfolioPath = Join-Path $script:DataDir "portfolio.json"
        $script:TransactionsPath = Join-Path $script:DataDir "transactions.json"
        $script:CashPath = Join-Path $script:DataDir "cash.json"
        $script:PlansPath = Join-Path $script:DataDir "savingsplans.json"
        return
    }
    $dir = Join-Path $script:DepotDir $Id
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script:PortfolioPath = Join-Path $dir "portfolio.json"
    $script:TransactionsPath = Join-Path $dir "transactions.json"
    $script:CashPath = Join-Path $dir "cash.json"
    $script:PlansPath = Join-Path $dir "savingsplans.json"
}

if ([string]$script:Config.ActiveDepot -and -not (@(Get-DepotList | Where-Object { $_.Id -eq [string]$script:Config.ActiveDepot }).Count)) { $script:Config.ActiveDepot = "" }
Set-DepotPaths ([string]$script:Config.ActiveDepot)

# Portfolio Holdings
function Read-PortfolioData {
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
}
Read-PortfolioData

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
            # v4.3: expiry date, trailing high (0 = not yet known), push per alert
            ExpiresAt   = if ($a.ExpiresAt) { [string]$a.ExpiresAt } else { "" }
            Peak        = $(if ($null -ne $a.Peak) { [double]$a.Peak } else { 0.0 })
            Push        = if ($null -ne $a.Push) { [bool]$a.Push } else { $true }
        })
        # v4.9.5 pause and v5.0 trend line points survive a restart
        $na = $script:Alerts[$script:Alerts.Count - 1]
        if ($a.SnoozeUntil) { $na | Add-Member -NotePropertyName SnoozeUntil -NotePropertyValue ([string]$a.SnoozeUntil) -Force }
        if ([string]$a.Condition -like "Trend*") {
            foreach ($f in @("T1", "T2")) { $na | Add-Member -NotePropertyName $f -NotePropertyValue ([long]$a.$f) -Force }
            foreach ($f in @("P1", "P2")) { $na | Add-Member -NotePropertyName $f -NotePropertyValue ([double]$a.$f) -Force }
        }
    }
}

# Alert history (v4.3): every hit with value and push status, last 500
$script:AlertLogPath = Join-Path $script:DataDir "alert-log.json"
$script:AlertLog = New-Object System.Collections.Generic.List[PSObject]
foreach ($e in @(Load-JsonState -Path $script:AlertLogPath -DefaultValue @())) {
    if ($null -ne $e -and $e.At) {
        $script:AlertLog.Add([PSCustomObject]@{
            At = [string]$e.At; Ticker = [string]$e.Ticker; Condition = [string]$e.Condition
            Text = [string]$e.Text; Note = [string]$e.Note; Push = [string]$e.Push
        })
    }
}

# Transaction history (v2.9): buys / sells / dividends with realized P/L
# (path set by Set-DepotPaths)
function Read-TransactionsData {
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
}
Read-TransactionsData

# ------------------------------------------------------------------------------
# v5.0: cash account per depot (cash.json next to the transactions). Trades
# booked after cash tracking was switched on move the cash; the ledger holds
# deposits, withdrawals, interest, fees and the opening balance.
# ------------------------------------------------------------------------------
function Read-CashData {
    $raw = Load-JsonState -Path $script:CashPath -DefaultValue $null
    $c = [PSCustomObject]@{ Enabled = $false; Currency = [string]$script:Config.Currency; BaselineIds = @(); Entries = (New-Object System.Collections.Generic.List[object]) }
    if ($null -ne $raw) {
        if ($null -ne $raw.Enabled) { $c.Enabled = [bool]$raw.Enabled }
        if ($raw.Currency) { $c.Currency = ([string]$raw.Currency).ToUpper() }
        $c.BaselineIds = @(@($raw.BaselineIds) | Where-Object { $_ } | ForEach-Object { [string]$_ })
        foreach ($e in @($raw.Entries)) {
            if ($null -eq $e -or $null -eq $e.Amount) { continue }
            $c.Entries.Add([PSCustomObject]@{ Id = [string]$e.Id; Date = [string]$e.Date; Kind = [string]$e.Kind; Amount = [double]$e.Amount; Currency = ([string]$e.Currency).ToUpper(); Note = [string]$e.Note })
        }
    }
    $script:Cash = $c
}

function Save-CashData {
    $c = $script:Cash
    Save-JsonState -Path $script:CashPath -Data ([PSCustomObject]@{ Enabled = [bool]$c.Enabled; Currency = [string]$c.Currency; BaselineIds = @($c.BaselineIds); Entries = $c.Entries.ToArray() })
}

function Add-CashEntry {
    param([string]$Kind, [double]$Amount, [string]$Note = "", [string]$Date = "")
    $d = if ($Date) { $Date } else { (Get-Date).ToString("yyyy-MM-dd") }
    $script:Cash.Entries.Add([PSCustomObject]@{ Id = [Guid]::NewGuid().ToString("N"); Date = $d; Kind = $Kind; Amount = $Amount; Currency = [string]$script:Cash.Currency; Note = $Note })
    Save-CashData
}

function Get-CashInfo {
    # $null while cash tracking is off; else balance in the cash and the display currency
    param([string]$Currency = "")
    $c = $script:Cash
    if ($null -eq $c -or -not [bool]$c.Enabled) { return $null }
    $cur = if ($Currency) { $Currency } else { [string]$script:Config.Currency }
    $mv = @(Get-CashMovements -Transactions $script:Transactions.ToArray() -Entries $c.Entries.ToArray() -ExcludeIds @($c.BaselineIds))
    $rates = @{}
    foreach ($m in $mv) {
        $mc = [string]$m.Currency
        if ($mc -and $mc -ne [string]$c.Currency -and -not $rates.ContainsKey($mc)) { $rates[$mc] = Convert-CurrencyValue -Amount 1.0 -FromCurrency $mc -ToCurrency ([string]$c.Currency) }
    }
    $b = Get-CashBalance -Movements $mv -Currency ([string]$c.Currency) -Rates $rates
    return [PSCustomObject]@{
        Balance = $b.Balance; Currency = [string]$c.Currency; Missing = $b.Missing; Movements = $mv
        Display = (Convert-CurrencyValue -Amount $b.Balance -FromCurrency ([string]$c.Currency) -ToCurrency $cur); DisplayCurrency = $cur
    }
}

# v5.0: savings plans (savingsplans.json per depot), booked automatically
function Read-SavingsPlans {
    $raw = Load-JsonState -Path $script:PlansPath -DefaultValue $null
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($raw)) {
        if ($null -eq $p -or -not $p.Ticker) { continue }
        $list.Add([PSCustomObject]@{
            Id = [string]$p.Id; Ticker = ([string]$p.Ticker).ToUpper(); Amount = [double]$p.Amount; Fee = [double]$p.Fee
            Currency = ([string]$p.Currency).ToUpper(); Day = [int]$p.Day; Start = [string]$p.Start; LastBooked = [string]$p.LastBooked
            Active = $(if ($null -eq $p.Active) { $true } else { [bool]$p.Active })
        })
    }
    $script:SavingsPlans = $list
}
function Save-SavingsPlans { Save-JsonState -Path $script:PlansPath -Data $script:SavingsPlans.ToArray() }

Read-CashData
Read-SavingsPlans

# Company profiles (v4.1): sector / country from Yahoo plus manual overrides,
# kept apart from portfolio.json so editing a position never loses them
$script:ProfilesPath = Join-Path $script:DataDir "profiles.json"
$script:Profiles = @{}
$rawProfiles = Load-JsonState -Path $script:ProfilesPath -DefaultValue $null
if ($null -ne $rawProfiles) {
    foreach ($prop in $rawProfiles.PSObject.Properties) {
        if ($null -eq $prop.Value) { continue }
        $v = $prop.Value
        $script:Profiles[$prop.Name.ToUpper()] = [PSCustomObject]@{
            Sector = [string]$v.Sector; Industry = [string]$v.Industry; Country = [string]$v.Country
            QuoteType = [string]$v.QuoteType; Name = [string]$v.Name; FetchedAt = [string]$v.FetchedAt
            ManualSector = [string]$v.ManualSector; ManualCountry = [string]$v.ManualCountry
        }
    }
}

function Save-Profiles {
    Save-JsonState -Path $script:ProfilesPath -Data $script:Profiles
}

function Get-ProfileEntry {
    # Entry of a ticker; created (empty) when missing
    param([string]$Ticker)
    $u = ([string]$Ticker).ToUpper()
    if (-not $script:Profiles.ContainsKey($u)) {
        $script:Profiles[$u] = [PSCustomObject]@{ Sector = ""; Industry = ""; Country = ""; QuoteType = ""; Name = ""; FetchedAt = ""; ManualSector = ""; ManualCountry = "" }
    }
    return $script:Profiles[$u]
}

# Earnings / dividend dates (v4.2) from Yahoo quoteSummary, refreshed about
# once a day. Unknown numbers are stored as null (NaN is not valid JSON).
$script:EventsPath = Join-Path $script:DataDir "events.json"
$script:Events = @{}

function ConvertTo-EventNumber {
    param($V)
    if ($null -eq $V) { return [double]::NaN }
    try { return [double]$V } catch { return [double]::NaN }
}

$script:EventNumberFields = @("DividendRate", "DividendYield", "TrailingRate", "TargetMean", "TargetHigh", "TargetLow", "RecMean", "Analysts")
function New-EventEntry {
    param($V = $null)
    $e = [PSCustomObject]@{
        EarningsDate = ""; EarningsEnd = ""; ExDividendDate = ""; DividendDate = ""
        DividendRate = [double]::NaN; DividendYield = [double]::NaN; TrailingRate = [double]::NaN
        FetchedAt = ""; NotifiedEarnings = ""
        TargetMean = [double]::NaN; TargetHigh = [double]::NaN; TargetLow = [double]::NaN; RecMean = [double]::NaN; Analysts = [double]::NaN; RecKey = ""
        Fund = $null
    }
    if ($null -ne $V) {
        # v5.1: fundamentals; entries from before are fetched again once
        if ($null -ne $V.PSObject.Properties["Fund"]) { $e.Fund = ConvertTo-StoredFund $V.Fund }
        foreach ($f in @("EarningsDate", "EarningsEnd", "ExDividendDate", "DividendDate", "FetchedAt", "NotifiedEarnings", "RecKey")) { if ($null -ne $V.$f) { $e.$f = [string]$V.$f } }
        foreach ($f in $script:EventNumberFields) { $e.$f = ConvertTo-EventNumber $V.$f }
        # v4.9.5: entries from before the analyst data are fetched again once
        if ($null -eq $V.PSObject.Properties["RecKey"]) { $e.FetchedAt = "" }
        if ($null -eq $V.PSObject.Properties["Fund"]) { $e.FetchedAt = "" }
    }
    return $e
}

$rawEvents = Load-JsonState -Path $script:EventsPath -DefaultValue $null
if ($null -ne $rawEvents) {
    foreach ($prop in $rawEvents.PSObject.Properties) {
        if ($null -ne $prop.Value) { $script:Events[$prop.Name.ToUpper()] = New-EventEntry $prop.Value }
    }
}

function ConvertTo-StoredFund {
    # v5.1: fundamentals as plain numbers (NaN -> null, so the JSON stays valid)
    param($F)
    if ($null -eq $F) { return $null }
    $o = [ordered]@{}
    foreach ($f in (Get-FundamentalFields)) {
        $pp = $F.PSObject.Properties[$f[0]]
        $x = [double]::NaN
        if ($null -ne $pp -and $null -ne $pp.Value -and [string]$pp.Value -ne "") { try { $x = [double]$pp.Value } catch { } }
        $o[$f[0]] = if ([double]::IsNaN($x) -or [double]::IsInfinity($x)) { $null } else { $x }
    }
    $o["Currency"] = [string]$F.Currency
    return [PSCustomObject]$o
}

function Save-Events {
    $out = @{}
    foreach ($k in @($script:Events.Keys)) {
        $e = $script:Events[$k]
        $o = [ordered]@{}
        foreach ($f in @("EarningsDate", "EarningsEnd", "ExDividendDate", "DividendDate", "FetchedAt", "NotifiedEarnings", "RecKey")) { $o[$f] = [string]$e.$f }
        foreach ($f in $script:EventNumberFields) {
            $n = [double]$e.$f
            $o[$f] = if ([double]::IsNaN($n) -or [double]::IsInfinity($n)) { $null } else { $n }
        }
        $o["Fund"] = $e.Fund
        $out[$k] = [PSCustomObject]$o
    }
    Save-JsonState -Path $script:EventsPath -Data $out
}

function Set-EventEntry {
    # Stores parsed calendar data; the "notified" mark survives while the
    # earnings date stays the same
    param([string]$Ticker, $Cal)
    $u = ([string]$Ticker).ToUpper()
    $old = $script:Events[$u]
    $e = New-EventEntry
    if ($null -ne $Cal) {
        foreach ($f in @("EarningsDate", "EarningsEnd", "ExDividendDate", "DividendDate", "RecKey")) { $e.$f = [string]$Cal.$f }
        foreach ($f in $script:EventNumberFields) { $e.$f = ConvertTo-EventNumber $Cal.$f }
    } elseif ($null -ne $old) {
        $e = New-EventEntry $old
    }
    if ($null -ne $old -and [string]$old.NotifiedEarnings -and [string]$old.NotifiedEarnings -eq $e.EarningsDate) { $e.NotifiedEarnings = [string]$old.NotifiedEarnings }
    if ($null -ne $old -and $null -ne $old.Fund) { $e.Fund = $old.Fund }
    $e.FetchedAt = (Get-Date).ToString("o")
    $script:Events[$u] = $e
}

function Get-TickerEarningsBadge {
    param([string]$Sym, [int]$WindowDays = 7)
    $ev = $script:Events[([string]$Sym).ToUpper()]
    if ($null -eq $ev) { return $null }
    return (Get-EarningsBadge -EarningsDate ([string]$ev.EarningsDate) -WindowDays $WindowDays)
}

function Format-IsoDateDe {
    param([string]$Iso)
    if (-not $Iso -or $Iso.Length -lt 10) { return "" }
    $d = [DateTime]::MinValue
    if ([DateTime]::TryParseExact($Iso.Substring(0, 10), "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $d.ToString("dd.MM.yyyy") }
    return $Iso
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
$script:ChartCur          = "EUR"   # v5.1: currency the active chart series is in
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

# ------------------------------------------------------------------------------
# Company profiles (v4.1). quoteSummary (sector, industry, country) needs a
# Yahoo cookie (fc.yahoo.com) + crumb; the shared HttpClientHandler keeps the
# cookie. Without a crumb only the search API is used (sector, no country).
# ------------------------------------------------------------------------------
$script:ProfileWorkerScript = {
    param($Client, [string[]]$Symbols, $Box, $Shared)
    $logs = New-Object System.Collections.Generic.List[string]
    $res = @{}
    # v4.2: calendarEvents / summaryDetail = earnings and dividend dates
    $evOnly = [bool]$Box.EventsOnly
    # v4.9.5: financialData = analyst targets + consensus
    # v5.1: defaultKeyStatistics = fundamentals (P/B, PEG, EV/EBITDA)
    $mods = if ($Box.Modules) { [string]$Box.Modules } elseif ($evOnly) { "calendarEvents%2CsummaryDetail%2CfinancialData%2CdefaultKeyStatistics" } else { "assetProfile%2CquoteType%2CcalendarEvents%2CsummaryDetail%2CfinancialData%2CdefaultKeyStatistics" }
    $get = {
        param([string]$U)
        try {
            $t = $Client.GetAsync($U)
            while (-not $t.Wait(100)) { if ($Shared.Cancel) { return $null } }
            $r = $t.Result
            try { return @{ Code = [int]$r.StatusCode; Body = $r.Content.ReadAsStringAsync().Result } } finally { $r.Dispose() }
        } catch { return $null }
    }
    $crumb = [string]$Shared.Crumb
    if (-not $crumb -and -not $Shared.CrumbFailed) {
        [void](& $get "https://fc.yahoo.com")
        $c = & $get "https://query1.finance.yahoo.com/v1/test/getcrumb"
        $body = if ($null -ne $c) { ([string]$c.Body).Trim() } else { "" }
        if ($null -ne $c -and $c.Code -eq 200 -and $body.Length -gt 0 -and $body.Length -lt 40 -and $body -notmatch '[<{\s]') {
            $crumb = $body
            $Shared.Crumb = $crumb
            $logs.Add("INFO|Yahoo crumb obtained")
        } else {
            $Shared.CrumbFailed = $true
            $code = if ($null -ne $c) { $c.Code } else { "n/a" }
            $logs.Add("WARN|Yahoo crumb not available (HTTP $code): sector from the search only, country must be set by hand")
        }
    }
    foreach ($sym in $Symbols) {
        if ($Shared.Cancel) { break }
        $e = [Uri]::EscapeDataString($sym)
        $sum = $null; $srch = $null
        if ($crumb) {
            $r = & $get ("https://query2.finance.yahoo.com/v10/finance/quoteSummary/{0}?modules={1}&crumb={2}" -f $e, $mods, [Uri]::EscapeDataString($crumb))
            if ($null -ne $r -and $r.Code -eq 200) { try { $sum = $r.Body | ConvertFrom-Json } catch { } }
            elseif ($null -ne $r -and $r.Code -eq 401) { $Shared.Crumb = ""; $crumb = ""; $logs.Add("WARN|Yahoo crumb rejected (401), continuing with the search") }
        }
        if (-not $evOnly -and -not $Box.Modules) {
            $r2 = & $get ("https://query1.finance.yahoo.com/v1/finance/search?q={0}&quotesCount=5&newsCount=0" -f $e)
            if ($null -ne $r2 -and $r2.Code -eq 200) { try { $srch = $r2.Body | ConvertFrom-Json } catch { } }
        }
        $res[$sym] = @{ Summary = $sum; Search = $srch }
    }
    $Box.Results = $res
    $Box.Logs = $logs.ToArray()
    $Box.RateLimited = $false
    $Box.ExtraFx = @{}
}
$script:WorkerShared.Crumb = ""
$script:WorkerShared.CrumbFailed = $false
$script:ProfileJobRunning = $false

function Start-ProfileJob {
    # Fetches the profiles of $Symbols in the background; $OnComplete runs on
    # the UI thread after the store was updated and saved
    # v5.1: -Modules = other quoteSummary modules; the raw results go to $OnRaw
    param([string[]]$Symbols, [scriptblock]$OnComplete = $null, [bool]$EventsOnly = $false, [string]$Modules = "", [scriptblock]$OnRaw = $null)
    $syms = @($Symbols | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpper() } | Sort-Object -Unique)
    if ($syms.Count -eq 0 -or $script:IsClosing -or $script:ProfileJobRunning) { return }
    $script:ProfileJobRunning = $true
    $box = [hashtable]::Synchronized(@{ Results = $null; Logs = $null; RateLimited = $false; ExtraFx = $null; EventsOnly = ($EventsOnly -or [bool]$Modules); Modules = $Modules })
    $done = {
        param($Box, $Ctx)
        $script:ProfileJobRunning = $false
        if ($Box.Modules) { if ($null -ne $Ctx.Raw) { & $Ctx.Raw $Box.Results }; return }
        $n = 0; $ne = 0
        foreach ($sym in @($Box.Results.Keys)) {
            $rr = $Box.Results[$sym]
            if (-not $Box.EventsOnly) {
                $pr = ConvertFrom-YahooProfile -Summary $rr.Summary -Search $rr.Search -Symbol $sym
                $en = Get-ProfileEntry $sym
                foreach ($f in @("Sector", "Industry", "Country", "QuoteType", "Name")) { if ($pr.$f) { $en.$f = [string]$pr.$f } }
                $en.FetchedAt = (Get-Date).ToString("o")
                $n++
            }
            # v4.2: earnings / dividend dates (kept when Yahoo had nothing this time)
            $cal = if ($null -ne $rr.Summary) { ConvertFrom-YahooCalendar -Summary $rr.Summary } else { $null }
            Set-EventEntry -Ticker $sym -Cal $cal
            # v5.1: fundamentals for the ticker analysis
            $fund = if ($null -ne $rr.Summary) { ConvertFrom-YahooFundamentals -Summary $rr.Summary } else { $null }
            if ($null -ne $fund) { $script:Events[$sym].Fund = ConvertTo-StoredFund $fund }
            $ne++
        }
        if ($n -gt 0) { Save-Profiles; Write-WidgetLog "Profiles updated: $n" }
        if ($ne -gt 0) { Save-Events; Write-WidgetLog "Event dates updated: $ne" }
        if ($null -ne $Ctx.Then) { & $Ctx.Then }
    }
    $job = [PSCustomObject]@{ PS = $null; Async = $null; Box = $box; Context = @{ Then = $OnComplete; Raw = $OnRaw }; OnComplete = $done }
    if ($null -eq $script:WorkerPool) {
        try { & $script:ProfileWorkerScript $script:HttpClient $syms $box $script:WorkerShared } catch { Write-WidgetLog "Profile fetch failed: $($_.Exception.Message)" "WARN" }
        Complete-FetchJob -Job $job
        return
    }
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $script:WorkerPool
    [void]$ps.AddScript($script:ProfileWorkerScript.ToString())
    [void]$ps.AddArgument($script:HttpClient)
    [void]$ps.AddArgument([string[]]$syms)
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

# v5.1: currency a ticker's price is shown in. With "Auto" it is the ticker's
# own trading currency (ABBN.SW in CHF, SAP.DE in EUR); depot values, sums and
# the portfolio always stay in the base currency $script:Config.Currency.
function Get-PriceCurrency {
    param([string]$Symbol)
    if (-not [bool]$script:Config.AutoCurrency) { return [string]$script:Config.Currency }
    $u = ([string]$Symbol).ToUpper()
    $raw = ""
    if ($script:QuoteStore.ContainsKey($u) -and $script:QuoteStore[$u].Currency) { $raw = [string]$script:QuoteStore[$u].Currency }
    elseif ($script:Portfolio.ContainsKey($u) -and $script:Portfolio[$u].Currency) { $raw = [string]$script:Portfolio[$u].Currency }
    if ($raw) {
        $n = (Normalize-CurrencyAndPrice -Price 1.0 -RawCurrency $raw).Currency
        if ($n -match '^[A-Z]{3}$') { return $n }
    }
    $g = Get-TickerCurrencyGuess $u
    if ($g) { return $g }
    return [string]$script:Config.Currency
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
    if ($env:TW_SMOKE_TEST) { return $true }
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
    # v4.6: no question - Ctrl+Z restores the list ($AskConfirm kept for callers)
    $undoList = @($script:Config.Watchlist)

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
    Set-Undo -Kind "Watchlist" -Data $undoList -Text "$u aus der Watchlist entfernt"
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
    foreach ($a in $script:Alerts) {
        # v4.3: portfolio alerts ("DEPOT") have no symbol of their own; expired ones rest
        if ((Test-PortfolioAlertKind (Get-AlertKind $a.Condition)) -or (Test-AlertExpired -Alert $a)) { continue }
        if (-not $a.Triggered -or [int]$a.RearmMin -gt 0) { [void]$prio.Add($a.Ticker.ToUpper()) }
    }
    $slow = New-Object System.Collections.Generic.HashSet[string]
    foreach ($w in $script:Config.Watchlist) {
        $u = $w.ToUpper()
        if (-not $prio.Contains($u)) { [void]$slow.Add($u) }
    }
    foreach ($a in $script:Alerts) {
        if (Test-PortfolioAlertKind (Get-AlertKind $a.Condition)) { continue }
        $u = $a.Ticker.ToUpper(); if (-not $prio.Contains($u)) { [void]$slow.Add($u) }
    }
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
    $dispCurr = Get-PriceCurrency $active
    $cfgCur   = [string]$script:Config.Currency
    $autoCur  = [bool]$script:Config.AutoCurrency
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
    foreach ($a in $script:Alerts) { if ((Get-AlertKind $a.Condition) -in @("PRICE", "TRAIL", "EKPCT", "PFVAL") -and [string]$a.Currency -match '^[A-Z]{3}$') { [void]$fxNeeded.Add([string]$a.Currency) } }
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

    $activeChartUrl = (Get-ChartUrl -Symbol $active -Interval $tfParams.Interval -Range $tfParams.Range -PrePost:$useExt) + "&events=div"
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
    # v5.0: further comparison tickers (up to 2)
    $moreUrls = [ordered]@{}
    if ($compare) {
        foreach ($cm in @($script:Config.CompareMore)) {
            $cu = ([string]$cm).ToUpper()
            if (-not $cu -or $cu -eq $active -or $cu -eq $compare -or $moreUrls.Contains($cu) -or $moreUrls.Count -ge 2) { continue }
            $mu = Get-ChartUrl -Symbol $cu -Interval $tfParams.Interval -Range $tfParams.Range -PrePost:$useExt
            $moreUrls[$cu] = $mu
            $urlList.Add($mu)
        }
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
        CfgCur         = $cfgCur
        AutoCur        = $autoCur
        ExtCfg         = $extCfg
        UseExt         = $useExt
        SeriesKey      = "$active|$tf|$(if ($autoCur) { 'AUTO' } else { $dispCurr })|$useExt"
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
        CompareMore    = $moreUrls
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

    # v4.3: relative volume (today vs. previous days at the same time, regular session)
    $relVol = [double]::NaN
    try {
        $q0 = if ($null -ne $R.indicators -and $null -ne $R.indicators.quote -and @($R.indicators.quote).Count -gt 0) { $R.indicators.quote[0] } else { $null }
        if ($null -ne $q0 -and $null -ne $q0.volume -and $null -ne $R.timestamp) {
            $vTs = New-Object System.Collections.Generic.List[long]
            $vVo = New-Object System.Collections.Generic.List[double]
            $tsA = @($R.timestamp); $voA = @($q0.volume)
            for ($k = 0; $k -lt [math]::Min($tsA.Count, $voA.Count); $k++) {
                if ($null -ne $voA[$k] -and [double]$voA[$k] -gt 0 -and (Get-BarSession -TsSec ([long]$tsA[$k]) -Tp $tp) -eq "R") {
                    $vTs.Add([long]$tsA[$k]); $vVo.Add([double]$voA[$k])
                }
            }
            $off = if ($null -ne $tp) { [int]$tp.GmtOffset } else { 0 }
            if ($vTs.Count -gt 1) { $relVol = Get-RelativeVolume -Ts $vTs.ToArray() -Vol $vVo.ToArray() -GmtOffset $off }
        }
    } catch { $relVol = [double]::NaN }
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
        RelVol     = $relVol
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
    if ($active -ne $script:Config.ActiveTicker.ToUpper() -or $tf -ne $script:Config.Timeframe -or $Plan.CfgCur -ne [string]$script:Config.Currency -or $Plan.AutoCur -ne [bool]$script:Config.AutoCurrency -or $Plan.ExtCfg -ne [bool]$script:Config.ShowExtended) {
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
        # v5.0: the further comparison tickers
        $keepMore = @{}
        if ($null -ne $Plan.CompareMore) {
            foreach ($cm in @($Plan.CompareMore.Keys)) {
                $al = Get-CompareAligned -R (Get-ChartResult $fetched[$Plan.CompareMore[$cm]]) -Plan $Plan
                if ($null -ne $al) { $keepMore[$cm] = $al } elseif ($script:ActiveCompareMore.ContainsKey($cm)) { $keepMore[$cm] = $script:ActiveCompareMore[$cm] }
            }
        }
        $script:ActiveCompareMore = $keepMore
        $script:CompareMoreSig = (@($keepMore.Keys | Sort-Object | ForEach-Object { "{0}:{1}" -f $_, @($keepMore[$_]).Count }) -join ",")
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
$script:ActiveCompareMore = @{}
$script:CompareMoreSig = ""
$script:ChartRenderErrors = 0
$script:LastRenderError = ""

function Get-CompareAligned {
    # v5.0: closes of a comparison chart aligned to the active bars, or $null
    param($R, $Plan)
    if ($null -eq $R -or $null -eq $R.timestamp -or $null -eq $R.indicators) { return $null }
    $saveC = $script:ActiveCompare; $saveS = $script:CompareSig
    Build-CompareSeries -R $R -Plan ([PSCustomObject]@{ Compare = "x"; Tf = $Plan.Tf })
    $out = $script:ActiveCompare
    $script:ActiveCompare = $saveC; $script:CompareSig = $saveS
    return ,$out
}

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
    if (-not $sym) { $script:Config.CompareMore = @(); $script:ActiveCompareMore = @{} }
    $script:ActiveCompare = @()
    $script:CompareSig = ""
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    if ($sym) { Set-TransientStatus "Vergleich mit $sym wird geladen..." 3 } else { Set-TransientStatus "Vergleich entfernt" 2 }
    Refresh-AllMarketData
    Update-AllUiViews
}

function Switch-CompareTicker {
    # v5.0: "NVDA CMP" / row menu: add a comparison (up to 3) or remove it again
    param([string]$Symbol)
    $sym = ([string]$Symbol).Trim().ToUpper()
    if ($sym) { $sym = Resolve-BestSymbol -RawInput $sym }
    if (-not $sym) { return }
    $cur = @(@([string]$script:Config.CompareTicker) + @($script:Config.CompareMore) | Where-Object { $_ })
    $r = Set-CompareList -Current $cur -Symbol $sym -Max 3
    if ($r.Msg -eq "full") { Set-TransientStatus ("Höchstens 3 Vergleiche - erst einen entfernen ({0} CMP)" -f $cur[0]) 5; return }
    $lst = @($r.List)
    $script:Config.CompareTicker = if ($lst.Count -gt 0) { [string]$lst[0] } else { "" }
    $script:Config.CompareMore = if ($lst.Count -gt 1) { @($lst[1..($lst.Count - 1)]) } else { @() }
    $script:ActiveCompare = @(); $script:CompareSig = ""; $script:ActiveCompareMore = @{}
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Set-TransientStatus $(if ($r.Msg -eq "added") { "Vergleich: " + ($lst -join ", ") } elseif ($lst.Count -gt 0) { "$sym entfernt - Vergleich: " + ($lst -join ", ") } else { "Vergleich entfernt" }) 4
    Refresh-AllMarketData
    Update-AllUiViews
}

function Show-CompareDialog {
    $p = $script:Pal
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Add_HandleCreated($script:DialogChromeHandler)
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
    # v4.8: ex-dividend dates for the markers in the chart
    $script:ActiveDividends = @(ConvertFrom-ChartDividendEvents $Res0)
    $meta0 = $Res0.meta
    $rawCurr0 = if ($meta0.currency) { [string]$meta0.currency } else { "USD" }
    $rawMkt0  = if ($null -ne $meta0.regularMarketPrice) { [double]$meta0.regularMarketPrice } else { 0.0 }
    $normMeta = Normalize-CurrencyAndPrice -Price $rawMkt0 -RawCurrency $rawCurr0
    $unit     = (Normalize-CurrencyAndPrice -Price 1.0 -RawCurrency $rawCurr0).Price

    $script:ActiveNativeCurr = $normMeta.Currency
    # v5.1: auto currency follows what Yahoo says the ticker trades in
    if ($Plan.AutoCur) { $dispCurr = $normMeta.Currency }
    $script:ChartCur = $dispCurr
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
    if ([string]$script:Config.MaType -eq "EMA") {
        $script:ActiveSma20 = Compute-Ema -Prices $closeArr -Period ([int]$script:Config.SmaFastPeriod)
        $script:ActiveSma50 = Compute-Ema -Prices $closeArr -Period ([int]$script:Config.SmaSlowPeriod)
    } else {
        $script:ActiveSma20 = Compute-Sma -Prices $closeArr -Period ([int]$script:Config.SmaFastPeriod)
        $script:ActiveSma50 = Compute-Sma -Prices $closeArr -Period ([int]$script:Config.SmaSlowPeriod)
    }
    $script:ActiveMacd      = Compute-Macd -Prices $closeArr
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
# v4.6: up/down colours from the chosen scheme (colour-blind safe option)
$udInit   = Get-UpDownColors -Scheme ([string]$script:Config.UpDownScheme) -UpHex ([string]$script:Config.UpColor) -DownHex ([string]$script:Config.DownColor)
$colGreen = [System.Drawing.Color]::FromArgb($udInit.Up[0], $udInit.Up[1], $udInit.Up[2])
$colRed   = [System.Drawing.Color]::FromArgb($udInit.Down[0], $udInit.Down[1], $udInit.Down[2])

# v4.9: number font (Consolas / Cascadia Mono / ...) and font size, read at start
$script:InstalledFonts = @()
try {
    $ifc = New-Object System.Drawing.Text.InstalledFontCollection
    $script:InstalledFonts = @($ifc.Families | ForEach-Object { $_.Name })
    $ifc.Dispose()
} catch { }
$script:MonoFamily = Resolve-MonoFont -Wanted ([string]$script:Config.MonoFont) -Installed $script:InstalledFonts
# The size setting only scales the lists (grid cells + row height) and the
# chart labels: buttons, labels and input boxes have fixed pixel sizes and
# would clip larger text.
$fsc = [int]$script:Config.FontScale
$script:GridRowScale = $fsc / 100.0
$fontTicker = New-Object System.Drawing.Font($script:MonoFamily, 10.5, [System.Drawing.FontStyle]::Bold)
$fontPrice  = New-Object System.Drawing.Font($script:MonoFamily, 13.0, [System.Drawing.FontStyle]::Bold)
$fontUi     = New-Object System.Drawing.Font("Segoe UI", 8.5)
$fontUiBold = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$fontMono   = New-Object System.Drawing.Font($script:MonoFamily, 8.5)
$fontAxis   = New-Object System.Drawing.Font($script:MonoFamily, (Get-ScaledFontSize 8.0 $fsc))
$fontBadge  = New-Object System.Drawing.Font($script:MonoFamily, (Get-ScaledFontSize 8.0 $fsc), [System.Drawing.FontStyle]::Bold)
$fontGrid       = New-Object System.Drawing.Font($script:MonoFamily, (Get-ScaledFontSize 8.5 $fsc))
$fontGridBold   = New-Object System.Drawing.Font($script:MonoFamily, (Get-ScaledFontSize 8.5 $fsc), [System.Drawing.FontStyle]::Bold)
$fontGridUi     = New-Object System.Drawing.Font("Segoe UI", (Get-ScaledFontSize 8.5 $fsc))
$fontGridUiBold = New-Object System.Drawing.Font("Segoe UI", (Get-ScaledFontSize 8.5 $fsc), [System.Drawing.FontStyle]::Bold)

$script:GdiCache = @{}

function Get-ThemeColors {
    $accent = switch ($script:Config.AccentColor) {
        "Eigene" {
            $rgb = ConvertFrom-HexColor ([string]$script:Config.AccentHex)
            if ($null -ne $rgb) { [System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]) } else { [System.Drawing.Color]::FromArgb(56, 189, 248) }
        }
        "Amber"  { [System.Drawing.Color]::FromArgb(245, 158, 11) }
        "Violet" { [System.Drawing.Color]::FromArgb(168, 85, 247) }
        # v5.2: the accent colour chosen in Windows (Settings > Personalisation > Colours)
        "Windows" {
            $wc = $null
            try { $wv = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name AccentColor -ErrorAction Stop).AccentColor; $wc = ConvertFrom-AbgrDword -Value ([long]$wv) } catch { }
            if ($null -ne $wc) { [System.Drawing.Color]::FromArgb($wc[0], $wc[1], $wc[2]) } else { [System.Drawing.Color]::FromArgb(0, 120, 215) }
        }
        default  { [System.Drawing.Color]::FromArgb(56, 189, 248) }
    }
    # v5.2: warning colour per theme (amber, darker on light backgrounds)
    $warn = [System.Drawing.Color]::FromArgb(245, 158, 11)

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
                Warn     = [System.Drawing.Color]::FromArgb(250, 204, 21)
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
                Warn     = $warn
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
                Warn     = [System.Drawing.Color]::FromArgb(217, 119, 6)
                DwmCap   = 0x00F9F5F1
                DwmBdr   = 0x00E1D5CB
                DwmDark  = 0
            }
        }
        "Graphite" {
            # v5.2: neutral grey (no blue tint), close to the Windows 11 dark look
            return @{
                HeaderBg = [System.Drawing.Color]::FromArgb(18, 18, 20)
                BodyBg   = [System.Drawing.Color]::FromArgb(24, 24, 27)
                PanelBg  = [System.Drawing.Color]::FromArgb(20, 20, 23)
                Card     = [System.Drawing.Color]::FromArgb(32, 32, 36)
                Input    = [System.Drawing.Color]::FromArgb(40, 40, 45)
                Hover    = [System.Drawing.Color]::FromArgb(54, 54, 61)
                Grid     = [System.Drawing.Color]::FromArgb(42, 42, 48)
                Border   = [System.Drawing.Color]::FromArgb(60, 60, 68)
                Text     = [System.Drawing.Color]::FromArgb(244, 244, 245)
                Muted    = [System.Drawing.Color]::FromArgb(161, 161, 170)
                Accent   = $accent
                Warn     = $warn
                DwmCap   = 0x00141212
                DwmBdr   = 0x00443C3C
                DwmDark  = 1
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
                Warn     = $warn
                DwmCap   = 0x00160F0B
                DwmBdr   = 0x004E3B2E
                DwmDark  = 1
            }
        }
    }
}

$script:Pal = Get-ThemeColors
# v5.2: design numbers of the chosen style (radii, gaps, row height ...)
$script:UiSpec = Get-UiSpec -Style ([string]$script:Config.UiStyle) -Density ([string]$script:Config.RowDensity)
$script:IconFont = if ($script:InstalledFonts -contains "Segoe Fluent Icons") { "Segoe Fluent Icons" } elseif ($script:InstalledFonts -contains "Segoe MDL2 Assets") { "Segoe MDL2 Assets" } else { "" }

function Get-MixColor {
    # v5.2: T = share of A (0..1), alpha kept opaque
    param([System.Drawing.Color]$A, [System.Drawing.Color]$B, [double]$T)
    return [System.Drawing.Color]::FromArgb([int]($B.R + ($A.R - $B.R) * $T), [int]($B.G + ($A.G - $B.G) * $T), [int]($B.B + ($A.B - $B.B) * $T))
}

function New-RoundedPath {
    param([System.Drawing.RectangleF]$R, [float]$Radius)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [float][math]::Min(2.0 * $Radius, [math]::Min($R.Width, $R.Height))
    if ($d -le 1) { $path.AddRectangle($R); return $path }
    $path.AddArc($R.X, $R.Y, $d, $d, 180, 90)
    $path.AddArc(($R.Right - $d), $R.Y, $d, $d, 270, 90)
    $path.AddArc(($R.Right - $d), ($R.Bottom - $d), $d, $d, 0, 90)
    $path.AddArc($R.X, ($R.Bottom - $d), $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function Fill-RoundedRect {
    # Rectangle or RectangleF, anti-aliased, optional border pen and drop shadow
    param($g, $Brush, $Rect, [float]$Radius, $Pen = $null, [int]$Shadow = 0)
    $rf = New-Object System.Drawing.RectangleF([float]$Rect.X, [float]$Rect.Y, [float]$Rect.Width, [float]$Rect.Height)
    $old = $g.SmoothingMode
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    if ($Shadow -gt 0) {
        for ($k = $Shadow; $k -ge 1; $k--) {
            $sr = New-Object System.Drawing.RectangleF(($rf.X + $k * 0.6), ($rf.Y + $k), $rf.Width, $rf.Height)
            $sp = New-RoundedPath $sr ($Radius + $k * 0.5)
            $sb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb([int](70 / $Shadow), 0, 0, 0))
            $g.FillPath($sb, $sp); $sb.Dispose(); $sp.Dispose()
        }
    }
    $path = New-RoundedPath $rf $Radius
    $g.FillPath($Brush, $path)
    if ($null -ne $Pen) { $g.DrawPath($Pen, $path) }
    $path.Dispose()
    $g.SmoothingMode = $old
}

function Rebuild-GdiCache {
    foreach ($val in $script:GdiCache.Values) {
        if ($null -ne $val -and $val -is [System.IDisposable]) { $val.Dispose() }
    }
    $script:GdiCache.Clear()
    $p = $script:Pal

    $script:GdiCache["bgBrush"]       = New-Object System.Drawing.SolidBrush($p.BodyBg)
    $script:GdiCache["panelBrush"]    = New-Object System.Drawing.SolidBrush($p.PanelBg)
    # v5.2: softer grid (dotted in the Fresh style), frame and card colours
    $gp0 = New-Object System.Drawing.Pen((Get-MixColor -A $p.Grid -B $p.PanelBg -T 0.75), 1)
    if ($script:UiSpec.Fresh) { $gp0.DashPattern = [float[]]@(1, 3) }
    $script:GdiCache["gridPen"]       = $gp0
    $script:GdiCache["framePen"]      = New-Object System.Drawing.Pen((Get-MixColor -A $p.Border -B $p.PanelBg -T 0.6), 1)
    $script:GdiCache["cardBrush"]     = New-Object System.Drawing.SolidBrush($p.Card)
    $script:GdiCache["cardPen"]       = New-Object System.Drawing.Pen((Get-MixColor -A $p.Border -B $p.Card -T 0.55), 1)
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
    $script:GdiCache["lineUp"]     = New-Object System.Drawing.Pen($colGreen, [float]$script:UiSpec.LineWidth)
    $script:GdiCache["lineDown"]   = New-Object System.Drawing.Pen($colRed, [float]$script:UiSpec.LineWidth)
    foreach ($lk in @("lineUp", "lineDown")) {
        $script:GdiCache[$lk].LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $script:GdiCache[$lk].StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $script:GdiCache[$lk].EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    }
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
    return ("{0}|{1}|{2}|{3}" -f $script:Config.ActiveTicker.ToUpper(), $script:Config.Timeframe, $(if ([bool]$script:Config.AutoCurrency) { "AUTO" } else { $script:Config.Currency }), $useExt)
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
    # v5.2 Fresh: the whole chart sits on a rounded card
    $fresh = [bool]$script:UiSpec.Fresh
    if ($fresh -and $Bounds.Width -gt 20 -and $Bounds.Height -gt 20) {
        Fill-RoundedRect -g $g -Brush $c["cardBrush"] -Rect (New-Object System.Drawing.RectangleF(([float]$Bounds.X + 1), ([float]$Bounds.Y + 1), ([float]$Bounds.Width - 2), ([float]$Bounds.Height - 2))) -Radius ([float](S $script:UiSpec.CardRadius)) -Pen $c["cardPen"]
    }

    # v4.0: hit areas of legend texts for the hover explanations
    $legends = New-Object System.Collections.Generic.List[PSObject]
    $addLeg = {
        param([string]$Txt, [double]$Lx, [double]$Ly, [string]$Key, $Font = $fontAxis, [string]$Tip = "")
        $lsz = $g.MeasureString($Txt, $Font)
        # v5.0: Tip = own hover text (markers), else the glossary term of Key
        $legends.Add([PSCustomObject]@{ R = (New-Object System.Drawing.RectangleF([float]$Lx, [float]$Ly, [float]$lsz.Width, [float]$lsz.Height)); Key = $Key; Tip = $Tip })
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
    if (-not $fresh) {
        $g.FillRectangle($c["panelBrush"], $priceRect)
        $g.DrawRectangle($c["framePen"], $priceRect)
    }

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
    # v5.0: further comparison lines, rebased like the first one
    $moreLines = @()
    if ($cmpSym -and $null -ne $script:ActiveCompareMore -and $script:ActiveCompareMore.Count -gt 0) {
        $mColors = @([System.Drawing.Color]::FromArgb(6, 182, 212), [System.Drawing.Color]::FromArgb(168, 85, 247))
        $mi = 0
        foreach ($ms in @($script:Config.CompareMore)) {
            $msu = ([string]$ms).ToUpper()
            $raw = $script:ActiveCompareMore[$msu]
            if ($null -eq $raw) { continue }
            $vr = Get-ArraySlice $raw $s0 $s1
            if (@($vr).Count -ne $n) { continue }
            $bI = -1
            for ($i = 0; $i -lt $n; $i++) { if (-not [double]::IsNaN([double]$vr[$i]) -and [double]$vr[$i] -gt 0 -and [double]$series[$i].Close -gt 0) { $bI = $i; break } }
            if ($bI -lt 0) { continue }
            $vals = New-Object double[] $n
            $pcts = New-Object double[] $n
            $bc = [double]$vr[$bI]; $bp = [double]$series[$bI].Close
            for ($i = 0; $i -lt $n; $i++) {
                $cv = [double]$vr[$i]
                if ($i -lt $bI -or [double]::IsNaN($cv) -or $cv -le 0) { $vals[$i] = [double]::NaN; $pcts[$i] = [double]::NaN; continue }
                $vals[$i] = $bp * ($cv / $bc)
                $pcts[$i] = (($cv / $bc) - 1.0) * 100.0
            }
            $moreLines += [PSCustomObject]@{ Sym = $msu; Vals = $vals; Pct = $pcts; Color = $mColors[$mi % 2] }
            $mi++
        }
    }
    $isCandle = ($script:Config.ChartType -in @("Candle", "HA"))
    # v5.0: Heikin-Ashi candles (from the full series, then the visible window); lines,
    # HUD and price tags keep using the real prices
    $cBars = $series
    if ($script:Config.ChartType -eq "HA") {
        $haAll = ConvertTo-HeikinAshi @($script:ActiveSeries)
        $cBars = if ($s0 -gt 0 -or $s1 -lt ($totalN - 1)) { @($haAll[$s0..$s1]) } else { $haAll }
        if (@($cBars).Count -ne $n) { $cBars = $series }
    }
    $minP = [double]::MaxValue
    $maxP = [double]::MinValue
    $rawLow = [double]::MaxValue
    $rawHigh = [double]::MinValue
    $maxVol = 0L

    for ($i = 0; $i -lt $n; $i++) {
        $lo = if ($isCandle) { [math]::Min($series[$i].Low, $cBars[$i].Low) } else { $series[$i].Close }
        $hi = if ($isCandle) { [math]::Max($series[$i].High, $cBars[$i].High) } else { $series[$i].Close }
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
    foreach ($ml in $moreLines) { foreach ($mv in $ml.Vals) { if (-not [double]::IsNaN($mv)) { if ($mv -lt $minP) { $minP = $mv }; if ($mv -gt $maxP) { $maxP = $mv } } } }
    if ($script:ActivePrevClose -gt 0 -and $script:Config.Timeframe -eq "1d") {
        if ($script:ActivePrevClose -lt $minP) { $minP = $script:ActivePrevClose }
        if ($script:ActivePrevClose -gt $maxP) { $maxP = $script:ActivePrevClose }
    }
    if ($maxP -eq $minP) { $maxP += 1.0; $minP -= 1.0 }
    # v4.8: logarithmic price axis (only possible with positive prices)
    $isLog = [bool]$script:Config.LogScale
    $lr = if ($isLog) { Get-LogPaddedRange -Min $minP -Max $maxP } else { $null }
    if ($null -ne $lr) {
        $minP = $lr.Min; $maxP = $lr.Max
    } else {
        $isLog = $false
        $padRange = ($maxP - $minP) * 0.08
        $minP -= $padRange
        $maxP += $padRange
    }
    $spanP = $maxP - $minP

    # Horizontal Grid & Right Y-Axis
    $gridSteps = 5
    for ($s = 0; $s -le $gridSteps; $s++) {
        $frac = $s / [double]$gridSteps
        $y = [int]($priceRect.Bottom - ($frac * $priceRect.Height))
        $val = Get-PriceFromFrac $frac $minP $spanP $isLog
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

    # Previous Close Dashed Line (1D; v4.9.5: also 5D, with a "Vortag" label, switchable)
    if ($script:ActivePrevClose -gt 0 -and $script:Config.Timeframe -in @("1d", "5d") -and [bool]$script:Config.ShowPrevClose) {
        $prevY = [int]($priceRect.Bottom - ((Get-PriceFrac ($script:ActivePrevClose) $minP $spanP $isLog) * $priceRect.Height))
        if ($prevY -ge $priceRect.Top -and $prevY -le $priceRect.Bottom) {
            $g.DrawLine($c["dashPen"], $priceRect.Left, $prevY, $priceRect.Right, $prevY)
            $pcTxt = "{0} {1:N2}" -f (Tr "Vortag"), $script:ActivePrevClose
            $pcSz = $g.MeasureString($pcTxt, $fontAxis)
            $pcY = $prevY - [int][math]::Ceiling($pcSz.Height) - 1
            if ($pcY -lt $priceRect.Top) { $pcY = $prevY + 2 }
            $pcBr = New-Object System.Drawing.SolidBrush($script:Pal.Muted)
            $g.DrawString($pcTxt, $fontAxis, $pcBr, ($priceRect.Left + (S 4)), $pcY)
            $pcBr.Dispose()
        }
    }

    # Price Coordinates
    $pts = New-Object System.Drawing.PointF[] $n
    for ($i = 0; $i -lt $n; $i++) {
        $x = $priceRect.Left + (($i / [double]($n - 1)) * $priceRect.Width)
        $y = $priceRect.Bottom - ((Get-PriceFrac ($series[$i].Close) $minP $spanP $isLog) * $priceRect.Height)
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
            $cb = $cBars[$i]
            $yOpen  = [int]($priceRect.Bottom - ((Get-PriceFrac ($cb.Open) $minP $spanP $isLog) * $priceRect.Height))
            $yClose = if ([object]::ReferenceEquals($cBars, $series)) { [int]$pts[$i].Y } else { [int]($priceRect.Bottom - ((Get-PriceFrac ($cb.Close) $minP $spanP $isLog) * $priceRect.Height)) }
            $yHigh  = [int]($priceRect.Bottom - ((Get-PriceFrac ($cb.High) $minP $spanP $isLog) * $priceRect.Height))
            $yLow   = [int]($priceRect.Bottom - ((Get-PriceFrac ($cb.Low) $minP $spanP $isLog) * $priceRect.Height))

            $bull = ($cb.Close -ge $cb.Open)
            $wPen = if ($bull) { $c["penUp"] } else { $c["penDown"] }
            $bBr  = if ($bull) { $c["brUp"] }  else { $c["brDown"] }

            $g.DrawLine($wPen, $cx, $yHigh, $cx, $yLow)
            $topY  = [math]::Min($yOpen, $yClose)
            $rectH = [math]::Max(1, [math]::Abs($yClose - $yOpen))
            $g.FillRectangle($bBr, ($cx - [int]($bodyW / 2)), $topY, $bodyW, $rectH)
        }
    } else {
        # v5.2: three-stop fade in the line colour (stronger in the Fresh style)
        $fa = [int]$script:UiSpec.FillAlpha
        $fillTop = [System.Drawing.Color]::FromArgb($fa, $lineColor.R, $lineColor.G, $lineColor.B)
        $fillBot = [System.Drawing.Color]::FromArgb(0, $lineColor.R, $lineColor.G, $lineColor.B)

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
        $cbl = New-Object System.Drawing.Drawing2D.ColorBlend(3)
        $cbl.Colors = [System.Drawing.Color[]]@($fillTop, [System.Drawing.Color]::FromArgb([int]($fa * 0.3), $lineColor.R, $lineColor.G, $lineColor.B), $fillBot)
        $cbl.Positions = [float[]]@(0.0, 0.55, 1.0)
        $gradBrush.InterpolationColors = $cbl
        $minY = $priceRect.Bottom
        foreach ($pp0 in $pts) { if ($pp0.Y -lt $minY) { $minY = $pp0.Y } }
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
                $yu = $priceRect.Bottom - ((Get-PriceFrac ($vBbU[$i]) $minP $spanP $isLog) * $priceRect.Height)
                $yl = $priceRect.Bottom - ((Get-PriceFrac ($vBbL[$i]) $minP $spanP $isLog) * $priceRect.Height)
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
                $y20 = $priceRect.Bottom - ((Get-PriceFrac ($vSma20[$i]) $minP $spanP $isLog) * $priceRect.Height)
                $sma20Pts.Add((New-Object System.Drawing.PointF([float]$x, [float]$y20)))
            }
            if ($i -lt $vSma50.Count -and -not [double]::IsNaN($vSma50[$i])) {
                $y50 = $priceRect.Bottom - ((Get-PriceFrac ($vSma50[$i]) $minP $spanP $isLog) * $priceRect.Height)
                $sma50Pts.Add((New-Object System.Drawing.PointF([float]$x, [float]$y50)))
            }
        }
        if ($sma20Pts.Count -ge 2) { $g.DrawLines($c["sma20Pen"], $sma20Pts.ToArray()) }
        if ($sma50Pts.Count -ge 2) { $g.DrawLines($c["sma50Pen"], $sma50Pts.ToArray()) }

        $s1Lbl = "$($script:Config.MaType)$($script:Config.SmaFastPeriod)"
        $s2Lbl = "$($script:Config.MaType)$($script:Config.SmaSlowPeriod)"
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
                $yv = $priceRect.Bottom - ((Get-PriceFrac ($vVwap[$i]) $minP $spanP $isLog) * $priceRect.Height)
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
            $yc = $priceRect.Bottom - ((Get-PriceFrac ($cmpVals[$i]) $minP $spanP $isLog) * $priceRect.Height)
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

    # v5.0: further comparison lines
    foreach ($ml in $moreLines) {
        $mPts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $lp = [double]::NaN
        for ($i = 0; $i -lt $n; $i++) {
            if ([double]::IsNaN($ml.Vals[$i])) { continue }
            $ym = $priceRect.Bottom - ((Get-PriceFrac ($ml.Vals[$i]) $minP $spanP $isLog) * $priceRect.Height)
            $mPts.Add((New-Object System.Drawing.PointF([float]$pts[$i].X, [float]$ym)))
            $lp = $ml.Pct[$i]
        }
        $mPen = New-Object System.Drawing.Pen($ml.Color, [float]1.5)
        $mBr = New-Object System.Drawing.SolidBrush($ml.Color)
        try {
            if ($mPts.Count -ge 2) { $g.DrawLines($mPen, $mPts.ToArray()) }
            if (-not [double]::IsNaN($lp)) {
                $mLbl = "vs {0} {1:+0.00;-0.00}%" -f $ml.Sym, $lp
                $g.DrawString($mLbl, $fontAxis, $mBr, ($priceRect.Left + $leftLegendOffset), ($priceRect.Top + (S 4)))
                & $addLeg $mLbl ($priceRect.Left + $leftLegendOffset) ($priceRect.Top + (S 4)) "COMPARE"
                $leftLegendOffset += [int][math]::Ceiling($g.MeasureString($mLbl, $fontAxis).Width) + (S 8)
            }
        } finally { $mPen.Dispose(); $mBr.Dispose() }
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
    # v5.0: own drawings (geometry like the overlay layout)
    if ($script:DrawingsReady) { Draw-ChartDrawings -g $g -L @{ PriceRect = $priceRect; MinP = $minP; SpanP = $spanP; LogScale = $isLog; Series = $series; N = $n; OffsetY = 0 } }
    if ([bool]$script:Config.ShowLevels) {
        Draw-ChartLevels -g $g -PriceRect $priceRect -MinP $minP -SpanP $spanP -Legends $legends -IsLog $isLog
    }

    # Right Y-Axis Current Price Pill Tag
    $lastY = [int]$pts[$n - 1].Y
    $tagH  = S 18
    $tagRect = New-Object System.Drawing.Rectangle(($priceRect.Right + 2), ($lastY - [int]($tagH / 2)), ($rightAxisWidth - 4), $tagH)
    $tagBrush = New-Object System.Drawing.SolidBrush($lineColor)
    # v5.2: dotted guide from the last point to the axis, a dot with a halo, rounded tag
    $guide = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(140, $lineColor.R, $lineColor.G, $lineColor.B), 1)
    $guide.DashPattern = [float[]]@(2, 3)
    $g.DrawLine($guide, [float]$pts[$n - 1].X, [float]$lastY, [float]$priceRect.Right, [float]$lastY)
    $guide.Dispose()
    if (-not $isCandle) {
        $halo = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(60, $lineColor.R, $lineColor.G, $lineColor.B))
        $hr = [float](S 6); $dr = [float](S 3)
        $g.FillEllipse($halo, ([float]$pts[$n - 1].X - $hr), ([float]$pts[$n - 1].Y - $hr), (2 * $hr), (2 * $hr))
        $g.FillEllipse($tagBrush, ([float]$pts[$n - 1].X - $dr), ([float]$pts[$n - 1].Y - $dr), (2 * $dr), (2 * $dr))
        $halo.Dispose()
    }
    Fill-RoundedRect -g $g -Brush $tagBrush -Rect $tagRect -Radius ([float](S 5))
    $g.DrawString(("{0:N2}" -f $series[$n - 1].Close), $fontBadge, $c["tagTextBr"], ($tagRect.Left + (S 4)), ($tagRect.Top + 2))
    $tagBrush.Dispose()

    # v4.8: ex-dividend markers (D) at the bottom of the price panel, next earnings date top right
    if (@($script:ActiveDividends).Count -gt 0 -and $n -ge 2) {
        $barTs = [long[]]@($series | ForEach-Object { [long]$_.Ts })
        $gapMs = [long][math]::Max(3600000, ([double]($barTs[$n - 1] - $barTs[0]) / [math]::Max(1, $n - 1)) * 1.5)
        $mBr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(56, 189, 248))
        try {
            foreach ($dv in @($script:ActiveDividends)) {
                $bi = Get-NearestBarIndex -BarTsMs $barTs -TsMs ([long]$dv.Ts * 1000) -MaxGapMs $gapMs
                if ($bi -lt 0) { continue }
                $mx = $priceRect.Left + (($bi / [double]($n - 1)) * $priceRect.Width)
                $my = $priceRect.Bottom - (S 14)
                $pts = [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF([float]$mx, [float]($my - (S 5)))), (New-Object System.Drawing.PointF([float]($mx + (S 5)), [float]$my)),
                    (New-Object System.Drawing.PointF([float]$mx, [float]($my + (S 5)))), (New-Object System.Drawing.PointF([float]($mx - (S 5)), [float]$my)))
                $g.FillPolygon($mBr, $pts)
                $dTxt = "Ex-Dividende {0:N2} {1}" -f ([double]$dv.Amount), $script:ActiveNativeCurr
                & $addLeg "xx" ($mx - (S 6)) ($my - (S 6)) "EXDATE" $fontAxis $dTxt
            }
        } finally { $mBr.Dispose() }
    }
    # v5.0: own buys / sells of this ticker as triangles at the booked price
    $actU = ([string]$script:Config.ActiveTicker).ToUpper()
    if ([bool]$script:Config.ShowTrades -and $n -ge 2) {
        $txA = @($script:Transactions | Where-Object { ([string]$_.Ticker).ToUpper() -eq $actU -and [string]$_.Type -in @("Kauf", "Verkauf") })
        if ($txA.Count -gt 0) {
            $dayIdx = @{}
            for ($i = 0; $i -lt $n; $i++) {
                $dk = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$series[$i].Ts).LocalDateTime.ToString("yyyy-MM-dd")
                if (-not $dayIdx.ContainsKey($dk)) { $dayIdx[$dk] = $i }
            }
            $buyBr = New-Object System.Drawing.SolidBrush($colGreen)
            $sellBr = New-Object System.Drawing.SolidBrush($colRed)
            $outPen = New-Object System.Drawing.Pen($script:Pal.PanelBg, [float]1)
            try {
                foreach ($tx in $txA) {
                    $ti = $dayIdx[[string]$tx.Date]
                    if ($null -eq $ti) { continue }
                    $tpx = Convert-CurrencyValue -Amount ([double]$tx.Price) -FromCurrency ([string]$tx.Currency) -ToCurrency ([string]$script:ChartCur)
                    if ($tpx -le 0) { continue }
                    $tx0 = $priceRect.Left + (([int]$ti / [double]($n - 1)) * $priceRect.Width)
                    $ty0 = $priceRect.Bottom - ((Get-PriceFrac $tpx $minP $spanP $isLog) * $priceRect.Height)
                    $ty0 = [math]::Max($priceRect.Top + (S 8), [math]::Min($priceRect.Bottom - (S 8), $ty0))
                    $isBuy = ([string]$tx.Type -eq "Kauf")
                    $sz = S 6
                    # (assigned inside the branches: an if-expression would unroll the PointF[] into object[])
                    $dir = if ($isBuy) { 1.0 } else { -1.0 }
                    $tri = New-Object System.Drawing.PointF[] 3
                    $tri[0] = New-Object System.Drawing.PointF([float]$tx0, [float]($ty0 + 2 * $dir))
                    $tri[1] = New-Object System.Drawing.PointF([float]($tx0 + $sz), [float]($ty0 + (2 + $sz * 1.4) * $dir))
                    $tri[2] = New-Object System.Drawing.PointF([float]($tx0 - $sz), [float]($ty0 + (2 + $sz * 1.4) * $dir))
                    $g.FillPolygon($(if ($isBuy) { $buyBr } else { $sellBr }), $tri)
                    $g.DrawPolygon($outPen, $tri)
                    $tTip = "{0} {1}: {2:N4} Stk @ {3:N2} {4}{5}" -f $(if ($isBuy) { "Kauf" } else { "Verkauf" }), (Format-IsoDateDe ([string]$tx.Date)), [double]$tx.Shares, [double]$tx.Price, [string]$tx.Currency, $(if ($tx.Note) { " - " + [string]$tx.Note } else { "" })
                    $ly = if ($isBuy) { $ty0 + 2 } else { $ty0 - 2 - $sz * 1.4 }
                    & $addLeg "xx" ($tx0 - $sz) $ly "" $fontAxis $tTip
                }
            } finally { $buyBr.Dispose(); $sellBr.Dispose(); $outPen.Dispose() }
        }
    }
    $evA = $script:Events[([string]$script:Config.ActiveTicker).ToUpper()]
    if ($null -ne $evA -and $evA.EarningsDate) {
        $ebA = Get-EarningsBadge -EarningsDate ([string]$evA.EarningsDate) -WindowDays 30
        if ($null -ne $ebA) {
            $eTxt = "Zahlen {0} ({1})" -f (Format-IsoDateDe $ebA.Date).Substring(0, 6), $ebA.Text
            $eSz = $g.MeasureString($eTxt, $fontAxis)
            $eBr = New-Object System.Drawing.SolidBrush($script:Pal.Warn)
            $ex = $priceRect.Right - $eSz.Width - (S 6)
            $g.DrawString($eTxt, $fontAxis, $eBr, [float]$ex, [float]($priceRect.Top + (S 4)))
            & $addLeg $eTxt $ex ($priceRect.Top + (S 4)) "EARNINGS"
            $eBr.Dispose()
        }
    }
    if ($isLog) { $g.DrawString("log", $fontAxis, $c["axisTextBrush"], ($priceRect.Right + (S 6)), ($priceRect.Top - (S 2))) }

    $bottomAxisAnchor = $priceRect.Bottom
    $rsiRectL = $null

    # Optional RSI Sub-Panel (v4.6: or MACD)
    if ($showRsi -and $rsiH -ge (S 42) -and [string]$script:Config.LowerPanel -eq "MACD") {
        $rsiRect = New-Object System.Drawing.Rectangle($padLeft, ($padTop + $priceH + $gapY), $plotWidth, $rsiH)
        if (-not $fresh) { $g.FillRectangle($c["panelBrush"], $rsiRect); $g.DrawRectangle($c["framePen"], $rsiRect) }
        $mAll = $script:ActiveMacd
        if ($null -ne $mAll -and @($mAll.Macd).Count -eq $totalN) {
            $vM = Get-ArraySlice $mAll.Macd $s0 $s1
            $vS = Get-ArraySlice $mAll.Signal $s0 $s1
            $vH = Get-ArraySlice $mAll.Hist $s0 $s1
            $mx = 0.0
            for ($i = 0; $i -lt $n; $i++) {
                foreach ($v in @($vM[$i], $vS[$i], $vH[$i])) { if (-not [double]::IsNaN([double]$v) -and [math]::Abs([double]$v) -gt $mx) { $mx = [math]::Abs([double]$v) } }
            }
            if ($mx -gt 0) {
                $mx *= 1.1
                $y0 = $rsiRect.Top + $rsiRect.Height / 2.0
                $sc = ($rsiRect.Height / 2.0) / $mx
                $g.DrawLine($c["gridPen"], $rsiRect.Left, [int]$y0, $rsiRect.Right, [int]$y0)
                $bw = [math]::Max(1.0, ($rsiRect.Width / [double][math]::Max(1, $n)) * 0.6)
                $mPts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
                $sPts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
                for ($i = 0; $i -lt $n; $i++) {
                    $x = $rsiRect.Left + (($i / [double][math]::Max(1, $n - 1)) * $rsiRect.Width)
                    $hv = [double]$vH[$i]
                    if (-not [double]::IsNaN($hv) -and $hv -ne 0) {
                        $hy = $hv * $sc
                        $br = if ($hv -ge 0) { $c["brUp"] } else { $c["brDown"] }
                        $top = if ($hv -ge 0) { $y0 - $hy } else { $y0 }
                        $g.FillRectangle($br, [float]($x - $bw / 2), [float]$top, [float]$bw, [float][math]::Max(1.0, [math]::Abs($hy)))
                    }
                    if (-not [double]::IsNaN([double]$vM[$i])) { $mPts.Add((New-Object System.Drawing.PointF([float]$x, [float]($y0 - [double]$vM[$i] * $sc)))) }
                    if (-not [double]::IsNaN([double]$vS[$i])) { $sPts.Add((New-Object System.Drawing.PointF([float]$x, [float]($y0 - [double]$vS[$i] * $sc)))) }
                }
                if ($mPts.Count -ge 2) { $g.DrawLines($c["rsiPenAcc"], $mPts.ToArray()) }
                if ($sPts.Count -ge 2) {
                    $sigPen = New-Object System.Drawing.Pen($script:Pal.Warn, [float](1.1 * $script:DpiScale))
                    $g.DrawLines($sigPen, $sPts.ToArray())
                    $sigPen.Dispose()
                }
                $lastM = [double]$vM[$n - 1]; $lastS = [double]$vS[$n - 1]
                $mTxt = if ([double]::IsNaN($lastM)) { "MACD(12,26,9)" } else { "MACD(12,26,9): {0:N2}  Signal {1:N2}" -f $lastM, $lastS }
                $g.DrawString($mTxt, $fontBadge, $c["rsiBrAcc"], ($rsiRect.Left + (S 6)), ($rsiRect.Top + 3))
                & $addLeg $mTxt ($rsiRect.Left + (S 6)) ($rsiRect.Top + 3) "MACD" $fontBadge
            } else {
                $g.DrawString("MACD: zu wenig Daten", $fontAxis, $c["axisTextBrush"], ($rsiRect.Left + (S 6)), ($rsiRect.Top + 3))
            }
        } else {
            $g.DrawString("MACD: zu wenig Daten", $fontAxis, $c["axisTextBrush"], ($rsiRect.Left + (S 6)), ($rsiRect.Top + 3))
        }
        $bottomAxisAnchor = $rsiRect.Bottom
        $rsiRectL = $rsiRect
    } elseif ($showRsi -and $rsiH -ge (S 42)) {
        $rsiRect = New-Object System.Drawing.Rectangle($padLeft, ($padTop + $priceH + $gapY), $plotWidth, $rsiH)
        if (-not $fresh) { $g.FillRectangle($c["panelBrush"], $rsiRect); $g.DrawRectangle($c["framePen"], $rsiRect) }

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
        LogScale       = $isLog
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
    $curr = [string]$script:ChartCur
    $out = @()
    if ($script:Portfolio.ContainsKey($sym)) {
        $pp = $script:Portfolio[$sym]
        if ($pp.AvgPrice -gt 0) {
            $ek = Convert-CurrencyValue -Amount $pp.AvgPrice -FromCurrency $pp.Currency -ToCurrency $curr
            $out += [PSCustomObject]@{ Price = $ek; Label = ("EK {0:N2}" -f $ek); Kind = "EK"; Hit = $false }
        }
    }
    foreach ($a in $script:Alerts) {
        # v4.3: trailing stop = current stop price as a line
        if ($a.Ticker -eq $sym -and (Get-AlertKind $a.Condition) -eq "TRAIL" -and [double]$a.Peak -gt 0 -and [string]$a.Currency -match '^[A-Z]{3}$') {
            $lv = Convert-CurrencyValue -Amount ([double]$a.Peak * (1.0 - [double]$a.TargetPrice / 100.0)) -FromCurrency $a.Currency -ToCurrency $curr
            $out += [PSCustomObject]@{ Price = $lv; Label = ("Trailing-Stopp {0:N2}" -f $lv); Kind = "AL"; Hit = [bool]$a.Triggered }
            continue
        }
        if ($a.Ticker -ne $sym -or (Get-AlertKind $a.Condition) -ne "PRICE") { continue }
        $lv = Convert-CurrencyValue -Amount $a.TargetPrice -FromCurrency $a.Currency -ToCurrency $curr
        $out += [PSCustomObject]@{ Price = $lv; Label = ("Alarm {0} {1:N2}" -f $a.Condition, $lv); Kind = "AL"; Hit = [bool]$a.Triggered }
    }
    return $out
}

function Draw-ChartLevels {
    param([System.Drawing.Graphics]$g, [System.Drawing.Rectangle]$PriceRect, [double]$MinP, [double]$SpanP, $Legends = $null, [bool]$IsLog = $false)
    $levels = @(Get-ChartLevels)
    if ($levels.Count -eq 0) { return }
    $amber = $script:Pal.Warn
    $topY = $PriceRect.Top + (S 4)
    $botY = $PriceRect.Bottom - (S 18)
    foreach ($lv in $levels) {
        $colr = if ($lv.Kind -eq "EK") { $script:Pal.Accent } elseif ($lv.Hit) { $script:Pal.Muted } else { $amber }
        $txt = $lv.Label
        $ly = $PriceRect.Bottom - ((Get-PriceFrac ([double]$lv.Price) $MinP $SpanP $IsLog) * $PriceRect.Height)
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

    # v5.0: line being drawn (first point fixed, second at the mouse)
    if ($null -ne $script:DrawPending -and $null -ne $script:DrawMouse -and $n -ge 2) {
        $tmp = [PSCustomObject]@{ Kind = "T"; T1 = [long]$script:DrawPending.T; P1 = [double]$script:DrawPending.P; T2 = [long]$script:DrawMouse.T; P2 = [double]$script:DrawMouse.P; Cur = [string]$script:ChartCur }
        $pxT = Get-DrawingPixels -L $L -D $tmp
        $rb = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(250, 204, 21), [float]1.5)
        $rb.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        $g.DrawLine($rb, [float]$pxT.X1, [float]($pxT.Y1 + [int]$L.OffsetY), [float]$pxT.X2, [float]($pxT.Y2 + [int]$L.OffsetY))
        $rb.Dispose()
    }

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
    $yVal = Get-PriceFromFrac (($pr.Bottom - $hy) / [double]$pr.Height) ([double]$L.MinP) ([double]$L.SpanP) ([bool]$L.LogScale)
    $tagRect = New-Object System.Drawing.Rectangle(($pr.Right + 2), ($hy - [int]($tagH / 2)), $tagW, $tagH)
    Fill-RoundedRect -g $g -Brush $c["crossTagBg"] -Rect $tagRect -Radius ([float](S 4))
    $g.DrawString(("{0:N2}" -f $yVal), $fontBadge, $c["crossTagFg"], ($tagRect.Left + 3), ($tagRect.Top + 2))

    # RSI pane: horizontal line + value tag at the mouse
    if ($inRsi -and $rr.Height -gt 0 -and [string]$script:Config.LowerPanel -ne "MACD") {
        $g.DrawLine($c["crossPen"], $rr.Left, $my, $rr.Right, $my)
        $rVal = (($rr.Bottom - $my) / [double]$rr.Height) * 100.0
        $rTag = New-Object System.Drawing.Rectangle(($rr.Right + 2), ($my - [int]($tagH / 2)), $tagW, $tagH)
        Fill-RoundedRect -g $g -Brush $c["crossTagBg"] -Rect $rTag -Radius ([float](S 4))
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
    Fill-RoundedRect -g $g -Brush $c["crossTagBg"] -Rect $tRect -Radius ([float](S 4))
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
        "{0} | C: {1:N2} {2}{3}{4}{5}" -f $hDt, $hPt.Close, $script:ChartCur, $hChg, $hVol, $hRsi
    }
    $hudSz = $g.MeasureString($hudTxt, $fontAxis)
    $hudW = [int][math]::Ceiling($hudSz.Width) + (S 10)
    $hudH = S 22
    $hudX = $pr.Right - $hudW - (S 8)
    if ($hudX -lt ($pr.Left + 6)) { $hudX = $pr.Left + 6 }
    $hudRect = New-Object System.Drawing.Rectangle($hudX, ($pr.Top + (S 22)), $hudW, $hudH)
    # v5.2: rounded HUD with a soft shadow
    Fill-RoundedRect -g $g -Brush $c["hudBg"] -Rect $hudRect -Radius ([float](S 6)) -Pen $c["framePen"] -Shadow 3
    $g.DrawString($hudTxt, $fontAxis, $c["hudFg"], ($hudRect.Left + 5), ($hudRect.Top + 4))
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
        Fill-RoundedRect -g $g -Brush $lblBr -Rect (New-Object System.Drawing.Rectangle($x, $y, $w, $h)) -Radius ([float](S 5)) -Shadow 2
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
    if ($script:DrawingsReady) { Update-DrawingsSig }
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
        $cfg.CompareTicker, $script:CompareSig, $script:CompareMoreSig, $script:ViewCount, $script:ViewOffset,
        $cfg.LogScale, @($script:ActiveDividends).Count, [string]$cfg.LowerPanel, [string]$cfg.MaType, [bool]$cfg.ShowPrevClose,
        [bool]$cfg.ShowTrades, $script:Transactions.Count, [string]$cfg.ChartType, $script:DrawingsSig
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
            $script:ChartRenderErrors++   # v5.0: the smoke test fails on these
            $script:LastRenderError = "$($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"
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

# ==============================================================================
# v4.7: English user interface (Settings > Sprache). Static texts of windows,
# buttons, column headers, menus and the command list are translated when a
# window is built; messages, explanations and the glossary stay German.
# ==============================================================================
$script:EnText = @{
    "Vergleichen mit" = "Compare with"; "Ticker (Kursentwicklung in % ab Chartbeginn):" = "Ticker (performance in % from chart start):"; "Vergleichen" = "Compare"
    "Abbrechen" = "Cancel"; "Kerzen" = "Candles"; "Volumen" = "Volume"; "Vollbild" = "Fullscreen"; "EK-Währ.:" = "Cost ccy:"
    "Position speichern" = "Save position"; "Löschen" = "Delete"; "Transaktion..." = "Transaction..."; "Historie" = "History"; "Analyse" = "Analysis"
    "Position wählen oder Ticker, Stück & EK eintragen für Live-Nachkauf-Simulation." = "Pick a position or enter ticker, shares & cost for a live top-up simulation."
    "Watchlist (Ziehen = Reihenfolge | Entf = Löschen)" = "Watchlist (drag = order | Del = remove)"; "+ Aktiven Ticker" = "+ Active ticker"; "+ Suchen / Add" = "+ Search / add"
    "Entfernen" = "Remove"; "Alarme (Doppelklick = Reset)" = "Alerts (double-click = reset)"; "Verlauf" = "History"; "Leeren" = "Clear"; "Schließen" = "Close"
    "Bei Alarmen" = "On alerts"; "Quartalszahlen (Vortag)" = "Earnings (day before)"; "Buchen" = "Book"; "Eintrag löschen" = "Delete entry"; "CSV export" = "CSV export"
    "Position neu berechnen" = "Recalculate position"; "Jahresreport..." = "Yearly report..."; "Berechnen" = "Calculate"; "Basis:" = "Base:"; "Netto investiert" = "Net invested"
    "Hinweis ab (%):" = "Warn from (%):"; "Sektor/Land per Klick überschreiben (blau = manuell). Leer = wieder automatisch." = "Click to override sector/country (blue = manual). Empty = automatic again."
    "Übernehmen" = "Apply"; "Währung, wenn leer:" = "Currency if empty:"; "ISIN bevorzugt an Börse:" = "Preferred exchange for ISINs:"; "ISINs auflösen" = "Resolve ISINs"
    "Positionen danach aus Buchungen berechnen" = "Recalculate positions from bookings"; "Importieren" = "Import"; "Überspringen" = "Skip"
    "Ruhezeit (kein Ton / Push) von - bis" = "Quiet hours (no sound / push) from - to"; "Handy-Push einrichten ..." = "Phone push setup ..."
    "Globales Tastenkürzel (zeigen / verstecken)" = "Global hotkey (show / hide)"; "Glossar öffnen (G)" = "Open glossary (G)"; "Datenordner öffnen" = "Open data folder"
    "Backup jetzt" = "Backup now"; "Log öffnen" = "Open log"; "Suchen:" = "Search:"; "Kein Begriff gefunden." = "No term found."
    "Alarm hier setzen (Rechtsklick im Kursbereich)" = "Set alert here (right-click in the price area)"; "Stück" = "Shares"; "Kurs" = "Price"; "Wert" = "Value"; "Anteil" = "Weight"
    "G/V Gesamt" = "Total P/L"; "Tag %" = "Day %"; "Markt" = "Market"; "Anzeigen / Wiederherstellen" = "Show / restore"; "Jetzt aktualisieren (F5)" = "Refresh now (F5)"; "Beenden" = "Exit"
    "Aktuellen Kurs kopieren" = "Copy current price"; "Aktiven Ticker zur Watchlist hinzufügen" = "Add active ticker to watchlist"; "Chartdaten als CSV exportieren" = "Export chart data as CSV"
    "Chart im Vollbild (F11)" = "Fullscreen chart (F11)"; "Vergleichen mit ... (X)" = "Compare with ... (X)"; "Vergleich entfernen" = "Remove comparison"; "Zoom zurücksetzen (Z)" = "Reset zoom (Z)"
    "Durchklicken (Maus geht durch)" = "Click-through (mouse passes through)"
    "Noch keine Alarme." = "No alerts yet."; "Ticker, Bedingung, Wert -> '+'" = "Ticker, condition, value -> '+'"; "oder Rechtsklick in den Chart." = "or right-click into the chart."
    "Alle Ticker" = "All tickers"; "(keine)" = "(none)"; "Aktualisierung" = "Refresh"; "Intervall (Sekunden)" = "Interval (seconds)"; "Nur-Watchlist-Ticker (Sekunden)" = "Watchlist-only tickers (seconds)"
    "HTTP-Timeout (Sekunden, ab Neustart)" = "HTTP timeout (seconds, after restart)"; "Alle Börsen zu: nur alle X Minuten (0 = aus)" = "All markets closed: every X minutes (0 = off)"
    "Indikatoren" = "Indicators"; "SMA schnell (auch Bollinger-Periode)" = "Fast SMA (also Bollinger period)"; "SMA langsam" = "Slow SMA"; "RSI-Periode" = "RSI period"
    "RSI überkauft ab" = "RSI overbought from"; "RSI überverkauft bis" = "RSI oversold up to"; "Gleitender Durchschnitt" = "Moving average"; "Unteres Feld im Chart" = "Lower chart panel"
    "Darstellung" = "Appearance"; "Akzentfarbe" = "Accent colour"; "Immer im Vordergrund" = "Always on top"; "Laufleiste (Watchlist) im Compact-Layout" = "Ticker tape (watchlist) in Compact layout"
    "Benachrichtigungen" = "Notifications"; "Tray-Hinweis + Ton bei Alarmen" = "Tray notice + sound on alerts"; "Hinweis bei Handelsstart (Börsen im Portfolio / aktiver Ticker)" = "Notice when trading starts (portfolio exchanges / active ticker)"
    "Hinweis am Vortag von Quartalszahlen (Portfolio)" = "Notice the day before earnings (portfolio)"; "Mit Windows starten (Verknüpfung im Autostart-Ordner)" = "Start with Windows (shortcut in the startup folder)"
    "Layout und Fenster" = "Layout and window"; "Deckkraft (%)" = "Opacity (%)"; "Terminal: Watchlist und Alarme anzeigen" = "Terminal: show watchlist and alerts"; "Terminal: Portfolio anzeigen" = "Terminal: show portfolio"
    "Terminal: Chart-Höhe (%)" = "Terminal: chart height (%)"; "Farben und Fenster" = "Colours and window"; "Farben für Plus / Minus" = "Colours for up / down"
    "Pfeile vor Veränderungen anzeigen" = "Show arrows before changes"; "Kurs kurz einfärben, wenn er sich ändert" = "Flash the price when it changes"; "Fenster am Bildschirmrand einrasten" = "Snap the window to screen edges"
    "Erklärungen (Maus darüber)" = "Explanations (hover)"; "Ausführlichkeit" = "Detail"; "Verzögerung (Millisekunden)" = "Delay (milliseconds)"; "Zufällig" = "Random"; "Chat-ID holen" = "Get chat ID"
    "Test senden" = "Send test"; "Wertentwicklung" = "Performance"; "Rendite" = "Returns"; "Aufteilung" = "Allocation"; "Dividenden" = "Dividends"; "Neu laden" = "Reload"; "Kaufdaten ..." = "Buy dates ..."
    "Zeit" = "Time"; "Bedingung" = "Condition"; "Notiz" = "Note"; "Verkauf" = "Sell"; "Kauf" = "Buy"; "Datum" = "Date"; "Typ" = "Type"; "Kurs/Betrag" = "Price/amount"; "Gebühr" = "Fee"; "Whg" = "Ccy"
    "Realisiert" = "Realized"; "Dividende" = "Dividend"; "Betrag (Whg)" = "Amount (ccy)"; "Erlös" = "Proceeds"; "Einstand" = "Cost"; "Gebühr/Steuer" = "Fee/tax"; "Ergebnis" = "Result"
    "Seit" = "Since"; "Unrealisiert" = "Unrealized"; "Gesamt" = "Total"; "Gesamt %" = "Total %"; "Währung" = "Currency"; "Sektor" = "Sector"; "Land" = "Country"; "Quelle" = "Source"
    "Rhythmus" = "Frequency"; "Letzte" = "Last"; "Pro Jahr" = "Per year"; "auf EK" = "on cost"; "Erwartet 12M" = "Expected 12M"; "Nächster Ex-Tag" = "Next ex-date"; "Zahltag" = "Pay date"
    "Quartalszahlen" = "Earnings"; "Art" = "Kind"; "Kaufdatum" = "Buy date"; "Wann" = "When"; "Anlass" = "Reason"; "Hinweis" = "Note"; "Kurs / Betrag" = "Price / amount"
    "Einstellungen" = "Settings"; "Sprache" = "Language"; "Wiederherstellen ..." = "Restore ..."; "Daten exportieren ..." = "Export data ..."; "Daten importieren ..." = "Import data ..."
    "Portabel machen ..." = "Make portable ..."; "Portabel beenden ..." = "End portable mode ..."; "Weiter" = "Next"; "Los geht's" = "Let's go"; "Feld" = "Field"; "Titel" = "Title"
    "Ereignis" = "Event"; "Inhalt" = "Content"; "Zeitpunkt" = "Time"; "Betrag je Aktie" = "Amount per share"; "Summe Jahr" = "Year total"; "Ex-Tag" = "Ex-date"
    "1 EUR =" = "1 EUR ="; "1 Einheit = EUR" = "1 unit = EUR"; "zum 52W-Hoch" = "to 52W high"; "Dienst" = "Service"; "ntfy-Server" = "ntfy server"; "ntfy-Thema" = "ntfy topic"
    "Telegram-Token" = "Telegram token"; "Telegram-Chat-ID" = "Telegram chat ID"; "Stück:" = "Shares:"; "Kurs:" = "Price:"; "Gebühr:" = "Fee:"; "Datum:" = "Date:"; "Ticker:" = "Ticker:"
    # command list
    "Chart (optional Zeitraum: GP 1Y)" = "Chart (optional range: GP 1Y)"; "Beschreibung: Profil, Kennzahlen, Termine, Position" = "Description: profile, figures, dates, position"; "Nachrichten" = "News"
    "Dividenden (ohne Ticker: Depot-Dividenden)" = "Dividends (without ticker: portfolio dividends)"; "Termine: Quartalszahlen, Ex-Tag, Zahltag" = "Dates: earnings, ex-date, pay date"
    "Alarm anlegen: NVDA ALRT >= 150 / TRAIL 8 / 52H / VOL 2 (ohne Ticker: Alarmliste)" = "Create alert: NVDA ALRT >= 150 / TRAIL 8 / 52H / VOL 2 (without ticker: alert list)"
    "Zur Watchlist hinzufügen" = "Add to watchlist"; "Vergleich im Chart (CMP ohne Ticker = aus)" = "Compare in chart (CMP without ticker = off)"; "Transaktion erfassen / Historie" = "Book transaction / history"
    "Portfolio-Analyse" = "Portfolio analysis"; "Terminkalender (Portfolio + Watchlist)" = "Event calendar (portfolio + watchlist)"; "Gewinner / Verlierer heute" = "Today's winners / losers"
    "Wechselkurse" = "Exchange rates"; "Alarm-Verlauf" = "Alert history"; "Jahresreport" = "Yearly report"; "Zeitraum: TF 1D / 5D / 1M / 3M / 6M / 1Y" = "Range: TF 1D / 5D / 1M / 3M / 6M / 1Y"
    "Layout: LAYOUT TERMINAL / STANDARD / COMPACT / TICKER, LAYOUT SAVE <Name>, LAYOUT DEL <Name>" = "Layout: LAYOUT TERMINAL / STANDARD / COMPACT / TICKER, LAYOUT SAVE <name>, LAYOUT DEL <name>"
    "Theme wechseln (THEME <Name>)" = "Change theme (THEME <name>)"; "Handy-Push einrichten" = "Phone push setup"; "Glossar" = "Glossary"; "Tastenkürzel und Befehle" = "Shortcuts and commands"
    "Version, Pfade, Update-Prüfung" = "Version, paths, update check"; "Depot wechseln: PF <Name> (ohne Name: neues Depot)" = "Switch depot: PF <name> (without name: new depot)"
    "Broker-CSV importieren" = "Import broker CSV"; "Backup wiederherstellen" = "Restore backup"; "Indikatoren: IND MACD / RSI / EMA / SMA" = "Indicators: IND MACD / RSI / EMA / SMA"
    "Durchklicken an/aus (Maus geht durchs Fenster)" = "Click-through on/off (mouse passes through)"; "Kurze Einführung" = "Short tour"; "zuletzt" = "recent"; "Ticker öffnen" = "Open ticker"; "Alarm" = "Alert"
    # v4.9: news tab, fonts, frame
    "> Befehl" = "> Command"; "> Befehl     Strg+K" = "> Command    Ctrl+K"; "Nachrichten - Depot und Watchlist" = "News - depot and watchlist"; "Alle gelesen" = "Mark all read"; "Ticker" = "Ticker"; "Alle" = "All"; "Nachrichten werden geladen ..." = "Loading news ..."; "Keine Nachrichten für diesen Filter." = "No news for this filter."; "Keine Verbindung - Nachrichten kommen beim nächsten Versuch." = "No connection - news follow on the next try."; "Keine Nachrichten der letzten 14 Tage." = "No news in the last 14 days."; "lädt ..." = "loading ..."; "Meldungen" = "items"; "Stand" = "as of"; "letzter Versuch ohne Verbindung" = "last try had no connection"; "Quelle: Yahoo Finance, Doppelklick öffnet den Artikel" = "Source: Yahoo Finance, double-click opens the article"; "Doppelklick öffnet den Artikel im Browser" = "Double-click opens the article in the browser"; "Aktiver Ticker:" = "Active ticker:"; "Schrift und Rahmen" = "Font and frame"; "Schrift für Zahlen (ab Neustart)" = "Font for numbers (after restart)"; "Schriftgröße Listen + Chart (ab Neustart)" = "List + chart font size (after restart)"; "Zahlen rechtsbündig (Watchlist, Portfolio)" = "Numbers right-aligned (watchlist, portfolio)"; "Abgerundete Fensterecken (Windows 11)" = "Rounded window corners (Windows 11)"; "Nachrichten (F4)" = "News (F4)"; "Neu laden alle (Minuten)" = "Reload every (minutes)"; "Ticker markieren ab Tagesbewegung (%)" = "Mark tickers moving today from (%)"; "Schrift und Schriftgröße wirken nach einem Neustart. Jetzt neu starten?" = "Font and font size apply after a restart. Restart now?"; "Schrift" = "Font"
    # v4.9.5
    "Rechtsklick: Quelle ausblenden" = "Right-click: mute source"; "Artikel öffnen" = "Open article"; "Link kopieren" = "Copy link"; "Quelle ausblenden" = "Mute source"; "Link kopiert" = "Link copied"; "Quelle ausgeblendet:" = "Source muted:"; "zurück in den Einstellungen" = "undo in Settings"; "Alarm-Wörter" = "Alert words"; "Alarm-Wörter auch für Watchlist-Ticker" = "Alert words for watchlist tickers too"; "Ausgeblendete Quellen zeigen" = "Show muted sources"; "Tray-Symbol in der Farbe des Depot-Tages (statt Ticker)" = "Tray icon in the colour of the depot's day (not the ticker)"; "Beitrag heute" = "Today's contribution"; "Privat (F9)" = "Private (F9)"; "Privat-Modus: Beträge und Stückzahlen ausgeblendet. F9 = wieder zeigen." = "Privacy mode: amounts and shares hidden. F9 = show again."; "Privat-Modus: erst F9 drücken, dann bearbeiten" = "Privacy mode: press F9 first, then edit"; "Weitere Positionen: unten Ticker, Stück und EK eintragen - oder:" = "More positions: enter ticker, shares and cost below - or:"; "+ Kauf buchen ..." = "+ Book a buy ..."; "Broker-CSV importieren ..." = "Import broker CSV ..."; "Analysten" = "Analysts"; "1 Stunde pausieren" = "Pause for 1 hour"; "4 Stunden pausieren" = "Pause for 4 hours"; "Bis morgen 08:00 pausieren" = "Pause until tomorrow 08:00"; "Pause beenden" = "End pause"; "Löschen (Entf)" = "Delete (Del)"; "Chart öffnen" = "Open chart"; "Alarm anlegen ..." = "Create alert ..."; "Kauf / Verkauf buchen ..." = "Book buy / sell ..."; "Nachrichten (News-Tab)" = "News (news tab)"; "Im Chart vergleichen" = "Compare in chart"; "Beschreibung (DES)" = "Description (DES)"; "Aus der Watchlist entfernen" = "Remove from watchlist"; "Vortag" = "Prev. close"; "Vortages-Schluss als Linie (1D / 5D)" = "Previous close as a line (1D / 5D)"
    "Ganze Seite" = "Full page"; "Tab nochmal klicken, F1 oder Esc = zurück" = "click the tab again, F1 or Esc = back"; "Privat-Modus: Beträge ausblenden (F9)" = "Privacy mode: hide amounts (F9)"
    # v5.0
    "Cash-Konto für dieses Depot führen" = "Keep a cash account for this depot"; "Währung:" = "Currency:"; "Einzahlung" = "Deposit"; "Auszahlung" = "Withdrawal"; "Zinsen" = "Interest"; "Stand setzen" = "Set balance"; "Kontostand" = "Balance"; "Aus - Haken setzen, um den Kontostand mitzuführen" = "Off - tick the box to track the balance"; "Kontostand beim Einschalten" = "Balance when switched on"; "gesetzt auf" = "set to"; "+ Sparplan" = "+ Savings plan"; "Jetzt prüfen" = "Check now"; "Speichern" = "Save"; "Transaktion" = "Transaction"; "Cash-Konto ... (CASH)" = "Cash account ... (CASH)"; "Sparpläne ... (SPAR)" = "Savings plans ... (SPAR)"; "Zielgewichte / Rebalancing (REBAL)" = "Target weights / rebalancing (REBAL)"; "Risiko (RISK)" = "Risk (RISK)"; "Heatmap (HEAT)" = "Heatmap (HEAT)"; "Risiko" = "Risk"; "Zielgewichte" = "Targets"; "Risikoloser Zins für Sharpe (% p.a.):" = "Risk-free rate for Sharpe (% p.a.):"; "Kennzahl" = "Measure"; "Depot" = "Depot"; "Zu wenig Verlauf - erst ein paar Wochen Buchungen / Kurse" = "Not enough history yet - a few weeks of bookings / prices needed"; "Zeitraum" = "Period"; "Werte" = "values"; "Rendite p.a. (zeitgewichtet)" = "Return p.a. (time-weighted)"; "Rendite im Zeitraum" = "Return in period"; "Volatilität p.a." = "Volatility p.a."; "Max. Drawdown" = "Max. drawdown"; "Beta zur Benchmark" = "Beta vs. benchmark"; "Korrelation zur Benchmark" = "Correlation with benchmark"; "Bester Tag" = "Best day"; "Schlechtester Tag" = "Worst day"; "gemeinsame Tage" = "common days"; "Neues Geld:" = "New money:"; "Cash-Konto einbeziehen" = "Include cash account"; "Nur kaufen (nichts verkaufen)" = "Buy only (no sales)"; "Gleich verteilen" = "Equal weights"; "Ziele löschen" = "Clear targets"; "Noch keine Ziele: in der Spalte 'Ziel %' Anteile eintragen (Enter) oder 'Gleich verteilen'. Positionen ohne Ziel bleiben unverändert." = "No targets yet: enter shares in the 'Ziel %' column (Enter) or use 'Equal weights'. Positions without a target stay as they are."; "Basis (Positionen mit Ziel + Geld)" = "Base (positions with target + money)"; "übrig" = "left"; "Vorschlag ohne Gebühren und Steuern, Stückzahlen gerundet auf 2 Stellen. Keine Anlageberatung." = "Suggestion without fees and taxes, shares rounded to 2 decimals. Not investment advice."; "Privat-Modus: Beträge ausgeblendet (F9)." = "Privacy mode: amounts hidden (F9)."; "Depot (Größe = Anteil)" = "Depot (size = weight)"; "Watchlist (gleich groß)" = "Watchlist (equal size)"; "Keine Positionen mit aktuellem Kurs." = "No positions with a current price."
    "Zeichnen" = "Draw"; "Horizontale Linie" = "Horizontal line"; "Trendlinie (D)" = "Trend line (D)"; "Fibonacci" = "Fibonacci"; "Alle Zeichnungen dieses Tickers löschen" = "Delete all drawings of this ticker"; "Alarm auf diese Linie" = "Alert on this line"; "Zeichnung löschen" = "Delete drawing"; "Eigene Käufe / Verkäufe anzeigen" = "Show own buys / sells"
    "+ Neue Gruppe ..." = "+ New group ..."; "Gruppe löschen:" = "Delete group:"; "Zu Gruppe" = "To group"; "Neue Gruppe ..." = "New group ..."; "Tag:" = "Day:"; "Im Depot" = "In depot"; "Zahlen:" = "Earnings:"; "Analysten:" = "Analysts:"; "Infokarte, wenn die Maus auf einem Ticker ruht" = "Info card when the mouse rests on a ticker"
    "Beitrag" = "Contribution"; "Vergleich" = "Compare"; "Ticker-Analyse: Signale + Kennzahlen (TA)" = "Ticker analysis: signals + fundamentals (TA)"; "Technische Signale (Tageskurse)" = "Technical signals (daily)"; "Kennzahlen" = "Fundamentals"; "Signal" = "Signal"; "Einordnung" = "Assessment"; "Szenario: Markt" = "Scenario: market"; "Indizes:" = "Indices:"; "Laden" = "Load"; "Anfang" = "Start"; "Käufe" = "Buys"; "Verkäufe" = "Sales"; "Ende" = "End"; "Beta aus" = "Beta from"; "Veränderung" = "Change"; "Position %" = "Position %"; "Diff." = "Diff."; "12M jetzt" = "12M now"; "12M min" = "12M min"; "12M max" = "12M max"; "Volatilität" = "Volatility"; "Max. DD" = "Max. DD"; "Summe" = "Total"; "Kurs 12 Monate" = "Price 12 months"; "positiv" = "positive"; "negativ" = "negative"; "überwiegend positiv" = "mostly positive"; "überwiegend negativ" = "mostly negative"; "gemischt" = "mixed"; "Signale" = "Signals"; "Zusammenfassung klassischer Indikatoren und Kennzahlen - keine Anlageberatung." = "Summary of classic indicators and ratios - not investment advice."; "Kurse in der Währung des Tickers, Depot in {0}" = "Prices in the ticker's currency, depot in {0}"
    "Design" = "Design"; "Stil" = "Style"; "Zeilenhöhe der Listen" = "List row height"; "Kompakt" = "Compact"; "Bequem" = "Comfortable"; "Laufleiste Tempo" = "Ticker bar speed"; "Langsam" = "Slow"; "Schnell" = "Fast"; "Zebra-Zeilen (jede zweite Zeile heller)" = "Zebra rows (every second row lighter)"; "Symbole auf Knöpfen und in Menüs" = "Icons on buttons and menus"; "Refined - wie gewohnt, feiner" = "Refined - familiar, cleaner"; "Fresh - Karten, mehr Luft" = "Fresh - cards, more space"
}

function Tr {
    param([string]$Text)
    if ([string]$script:Config.Language -ne "EN" -or -not $Text) { return $Text }
    $t = $script:EnText[$Text]
    if ($null -ne $t) { return $t }
    return $Text
}

function Apply-Language {
    # Translates the static texts of a window and its menus (English mode only)
    param($Root)
    if ([string]$script:Config.Language -ne "EN" -or $null -eq $Root) { return }
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $c = $stack.Pop()
        if ($c -is [System.Windows.Forms.DataGridView]) {
            foreach ($col in $c.Columns) { $col.HeaderText = Tr $col.HeaderText }
        } elseif ($c -is [System.Windows.Forms.Control] -and -not ($c -is [System.Windows.Forms.TextBox]) -and -not ($c -is [System.Windows.Forms.ComboBox])) {
            if ($c.Text) { $c.Text = Tr $c.Text }
        }
        if ($c -is [System.Windows.Forms.Control]) {
            if ($null -ne $c.ContextMenuStrip) { $stack.Push($c.ContextMenuStrip) }
            foreach ($ch in $c.Controls) { $stack.Push($ch) }
        }
        if ($c -is [System.Windows.Forms.ToolStrip]) { foreach ($it in $c.Items) { $stack.Push($it) } }
        if ($c -is [System.Windows.Forms.ToolStripItem]) {
            if ($c.Text) { $c.Text = Tr $c.Text }
            if ($c -is [System.Windows.Forms.ToolStripDropDownItem]) { foreach ($it in $c.DropDownItems) { $stack.Push($it) } }
        }
    }
}

function Set-Tip {
    param([System.Windows.Forms.Control]$Ctl, [string]$Text, [string]$Key = "")
    if ($null -eq $Ctl) { return }
    $Text = Tr $Text
    $script:TipReg[$Ctl] = @{ Text = $Text; Key = $Key }
    $toolTip.SetToolTip($Ctl, (Get-TooltipText -Text $Text -Key $Key -Mode (Get-TipModeNow)))
}

function Set-DynTip {
    param([System.Windows.Forms.Control]$Ctl, [string]$Text, [string]$Key = "")
    if ($null -eq $Ctl -or $Ctl.IsDisposed) { return }
    $Text = Tr $Text
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

function Set-WindowChrome {
    # v4.9: the same window frame for the main window and every dialog: dark
    # title bar, caption + border colour of the theme, rounded corners
    # (Windows 11; older Windows ignores the unknown attributes).
    param([System.Windows.Forms.Form]$Win, [string]$Kind = "Window")
    if ($null -eq $Win -or $Win.IsDisposed -or -not $Win.IsHandleCreated) { return }
    try {
        $darkMode = [int]$script:Pal.DwmDark
        [void][Win32WidgetHelperV26]::DwmSetWindowAttribute($Win.Handle, 20, [ref]$darkMode, 4)
        $captionColor = [int]$script:Pal.DwmCap
        [void][Win32WidgetHelperV26]::DwmSetWindowAttribute($Win.Handle, 35, [ref]$captionColor, 4)
        $borderColor = [int]$script:Pal.DwmBdr
        [void][Win32WidgetHelperV26]::DwmSetWindowAttribute($Win.Handle, 34, [ref]$borderColor, 4)
        $corner = [int](Get-WindowCornerPref -Kind $Kind -Round ([bool]$script:Config.RoundCorners))
        [void][Win32WidgetHelperV26]::DwmSetWindowAttribute($Win.Handle, 33, [ref]$corner, 4)
    } catch { }
}

function Apply-DwmTitlebarTheme {
    # the main window; the borderless ticker strip gets small round corners
    $kind = if ([string]$script:Config.Layout -eq "Ticker") { "Strip" } else { "Window" }
    Set-WindowChrome -Win $form -Kind $kind
    foreach ($ow in @($form.OwnedForms)) { Set-WindowChrome -Win $ow }
}

# every dialog gets the frame when its window handle exists
$script:DialogChromeHandler = { param($sender, $e) Set-WindowChrome -Win $sender }

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

# v5.2: rounded buttons, painted over the flat button (radius from the style)
$script:RoundBtns = New-Object System.Collections.Generic.HashSet[object]
$script:HotBtn = $null
$script:RoundBtnPaint = {
    param($sender, $e)
    $spec = $script:UiSpec
    if ($null -eq $spec -or [int]$spec.BtnRadius -le 0) { return }
    try {
        $g = $e.Graphics
        $par = $sender.Parent
        $bg = if ($null -ne $par) { $par.BackColor } else { $script:Pal.BodyBg }
        if ($bg.A -lt 255) { $bg = $script:Pal.BodyBg }
        $g.Clear($bg)
        $w = $sender.ClientSize.Width; $h = $sender.ClientSize.Height
        $fill = if (-not $sender.Enabled) { Get-MixColor -A $sender.BackColor -B $bg -T 0.5 }
                elseif ([object]::ReferenceEquals($script:HotBtn, $sender)) { $sender.FlatAppearance.MouseOverBackColor }
                else { $sender.BackColor }
        $br = New-Object System.Drawing.SolidBrush($fill)
        $pn = $null
        if ($sender.FlatAppearance.BorderSize -gt 0) { $pn = New-Object System.Drawing.Pen($sender.FlatAppearance.BorderColor, 1) }
        Fill-RoundedRect -g $g -Brush $br -Rect (New-Object System.Drawing.RectangleF(0.5, 0.5, ($w - 1.5), ($h - 1.5))) -Radius ([float](S $spec.BtnRadius)) -Pen $pn
        $br.Dispose(); if ($null -ne $pn) { $pn.Dispose() }
        $fg = if ($sender.Enabled) { $sender.ForeColor } else { $script:Pal.Muted }
        $tf = [System.Windows.Forms.TextFormatFlags]
        $flags = $tf::VerticalCenter -bor $tf::SingleLine -bor $tf::EndEllipsis -bor $tf::NoPrefix
        $ta = [string]$sender.TextAlign
        $flags = $flags -bor $(if ($ta -like "*Left") { $tf::Left } elseif ($ta -like "*Right") { $tf::Right } else { $tf::HorizontalCenter })
        $pad = S 4
        $tr = New-Object System.Drawing.Rectangle($pad, 0, [math]::Max(1, $w - 2 * $pad), $h)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $sender.Text, $sender.Font, $tr, $fg, $flags)
    } catch { }
}
$script:RoundBtnEnter = { param($sender, $e) $script:HotBtn = $sender; $sender.Invalidate() }
$script:RoundBtnLeave = { param($sender, $e) if ([object]::ReferenceEquals($script:HotBtn, $sender)) { $script:HotBtn = $null }; $sender.Invalidate() }

function Style-FlatButton {
    param(
        [System.Windows.Forms.Button]$Btn,
        [System.Drawing.Color]$BgColor,
        [System.Drawing.Color]$FgColor,
        [System.Drawing.Color]$BorderColor
    )
    $Btn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    if (-not $script:RoundBtns.Contains($Btn)) {
        [void]$script:RoundBtns.Add($Btn)
        $Btn.Add_Paint($script:RoundBtnPaint)
        $Btn.Add_MouseEnter($script:RoundBtnEnter)
        $Btn.Add_MouseLeave($script:RoundBtnLeave)
    }
    # v5.2: the Fresh style drops plain borders (accent borders stay: they mean something)
    $Btn.FlatAppearance.BorderSize = if ($script:UiSpec.Fresh -and $BorderColor.ToArgb() -eq $script:Pal.Border.ToArgb()) { 0 } else { 1 }
    $Btn.Invalidate()
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
# v4.6: click-through (mouse goes to the window below; hotkey brings it back)
$miClickThrough = New-Object System.Windows.Forms.ToolStripMenuItem("Durchklicken (Maus geht durch)")
[void]$trayMenu.Items.Add($miClickThrough)
$miClickThrough.Add_Click({ Set-ClickThrough (-not $script:ClickThrough) })
# v4.9.5: privacy mode also from the tray (F9 needs Fn on many laptops)
$miPrivacy = New-Object System.Windows.Forms.ToolStripMenuItem("Privat-Modus: Beträge ausblenden (F9)")
[void]$trayMenu.Items.Add($miPrivacy)
$miPrivacy.Add_Click({ Set-PrivacyMode (-not [bool]$script:Config.PrivacyMode) })
[void]$trayMenu.Items.Add("-")
$miExit    = $trayMenu.Items.Add("Beenden")
$trayIcon.ContextMenuStrip = $trayMenu

function Style-DataGrid {
    param([System.Windows.Forms.DataGridView]$Grid)
    $spec = $script:UiSpec
    $Grid.BackgroundColor = $script:Pal.Card
    $Grid.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    # v5.2: only horizontal row lines, softer
    $Grid.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
    $Grid.GridColor = Get-MixColor -A $script:Pal.Border -B $script:Pal.Card -T 0.55
    $Grid.RowHeadersVisible = $false
    $Grid.AllowUserToAddRows = $false
    $Grid.AllowUserToDeleteRows = $false
    $Grid.AllowUserToResizeRows = $false
    $Grid.ReadOnly = $true
    $Grid.MultiSelect = $false
    $Grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $Grid.EnableHeadersVisualStyles = $false
    $Grid.ColumnHeadersBorderStyle = if ($spec.Fresh) { [System.Windows.Forms.DataGridViewHeaderBorderStyle]::None } else { [System.Windows.Forms.DataGridViewHeaderBorderStyle]::Single }
    $Grid.ColumnHeadersHeight = S $spec.HeaderH
    $rowH = S ([math]::Round([int]$spec.RowH * $script:GridRowScale))
    $Grid.RowTemplate.Height = $rowH
    if ($Grid.Rows.Count -le 400) { foreach ($rw in $Grid.Rows) { if ($rw.Height -ne $rowH) { $rw.Height = $rowH } } }

    $hdrStyle = New-Object System.Windows.Forms.DataGridViewCellStyle
    $hdrStyle.BackColor = if ($spec.Fresh) { $script:Pal.Card } else { $script:Pal.Input }
    $hdrStyle.ForeColor = if ($spec.Fresh) { $script:Pal.Muted } else { $script:Pal.Accent }
    $hdrStyle.SelectionBackColor = $hdrStyle.BackColor
    $hdrStyle.Font = $fontUiBold
    $hdrStyle.Padding = New-Object System.Windows.Forms.Padding((S $spec.CellPad), 0, (S $spec.CellPad), 0)
    $Grid.ColumnHeadersDefaultCellStyle = $hdrStyle

    $cellStyle = New-Object System.Windows.Forms.DataGridViewCellStyle
    $cellStyle.BackColor = $script:Pal.Card
    $cellStyle.ForeColor = $script:Pal.Text
    $cellStyle.SelectionBackColor = $script:Pal.Hover
    $cellStyle.SelectionForeColor = $script:Pal.Text
    $cellStyle.Font = $fontGrid
    $cellStyle.Padding = New-Object System.Windows.Forms.Padding((S $spec.CellPad), 0, (S $spec.CellPad), 0)
    $Grid.DefaultCellStyle = $cellStyle
    # v5.2: zebra rows (optional)
    $alt = New-Object System.Windows.Forms.DataGridViewCellStyle
    $alt.BackColor = if ([bool]$script:Config.ZebraRows) { Get-MixColor -A $script:Pal.Text -B $script:Pal.Card -T 0.035 } else { $script:Pal.Card }
    $Grid.AlternatingRowsDefaultCellStyle = $alt
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
    } elseif ($script:UiSpec.Fresh) {
        # v5.2 Fresh: accent line under the header that fades out to the right
        $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0, 0)), (New-Object System.Drawing.Point([math]::Max(2, $sender.Width), 0)), $script:Pal.Accent, $script:Pal.HeaderBg)
        $e.Graphics.FillRectangle($gb, 0, ($sender.Height - 2), $sender.Width, 2)
        $gb.Dispose()
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
    $sig = "{0}|{1}|{2}|{3}" -f $script:Config.Theme, $script:Config.AccentColor, $curr, [bool]$script:Config.AutoCurrency
    foreach ($sym in $syms) {
        if (-not $script:QuoteStore.ContainsKey($sym)) { continue }
        $q = $script:QuoteStore[$sym]
        $px = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency (Get-PriceCurrency $sym)
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
        # v5.2: soft fade at both ends while it scrolls
        $fw = S 28
        $ph = [math]::Max(1, $sender.ClientSize.Height)
        $hb = $script:Pal.HeaderBg
        $clear = [System.Drawing.Color]::FromArgb(0, $hb.R, $hb.G, $hb.B)
        $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, 0, $fw, $ph)), $hb, $clear, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        $g.FillRectangle($lg, 0, 0, $fw, $ph); $lg.Dispose()
        $rg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(($pw - $fw), 0, $fw, $ph)), $clear, $hb, [System.Drawing.Drawing2D.LinearGradientMode]::Horizontal)
        $g.FillRectangle($rg, ($pw - $fw), 0, $fw, $ph); $rg.Dispose()
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
$tapeTimer.Interval = 16   # v5.2: ~60 steps a second, speed from TapeSpeed
$tapeTimer.Add_Tick({
    $bmp = $script:TapeBitmap
    if ($script:TapeHover -or $null -eq $bmp -or -not $pnlTape.Visible -or -not $form.Visible) { return }
    if ($bmp.Width -le $pnlTape.ClientSize.Width) { return }
    $script:TapeOffset = ($script:TapeOffset + $script:DpiScale * 0.55 * (Get-TapeStep ([string]$script:Config.TapeSpeed))) % $bmp.Width
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
$btnCurrency.Text = $(if ([bool]$script:Config.AutoCurrency) { "Auto $script:DropArrow" } else { "$($script:Config.Currency) $script:DropArrow" })
$pnlHeader.Controls.Add($btnCurrency)
Set-Tip $btnCurrency "Währung (Taste W). Auto = jeder Kurs und der Chart in der Währung des Tickers (ABBN.SW in CHF, SAP.DE in EUR); Depotwerte bleiben in der Basiswährung. EUR/USD/CHF/GBP = alles in dieser Währung (wird auch Basiswährung)." "FX"

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
[void]$lstCurrencyDropdown.Items.Add("Auto")
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
    @{ Key = "Watchlist"; Label = "Watch & Alarm (F3)"; W = 138 },
    @{ Key = "News";      Label = "News (F4)";          W = 80  }
)
# v4.9: the nav bar controls right of the tabs start here (was 346)
$script:NavX = 431
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
    if ($td.Key -ne "Chart") { Set-Tip $b ("{0} - {1}" -f $td.Label, "Terminal-Layout: nochmal klicken = als ganze Seite (Shift+F-Taste), Esc = zurück") }
    $tabX += (S ($td.W + 5))
}

$btnRefreshNow = New-Object System.Windows.Forms.Button
$btnRefreshNow.Location = New-Object System.Drawing.Point((S ($script:NavX)), (S 2))
$btnRefreshNow.Size = New-Object System.Drawing.Size((S 30), (S 27))
Style-FlatButton -Btn $btnRefreshNow -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnRefreshNow.Font = $fontUiBold
$btnRefreshNow.Text = [string][char]0x21BB
$pnlNav.Controls.Add($btnRefreshNow)
Set-Tip $btnRefreshNow "Marktdaten jetzt aktualisieren (F5)" "REFRESH"

$cmbRefresh = New-Object System.Windows.Forms.ComboBox
$cmbRefresh.Location = New-Object System.Drawing.Point((S ($script:NavX + 34)), (S 4))
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
$btnThemeCycle.Location = New-Object System.Drawing.Point((S ($script:NavX + 96)), (S 2))
$btnThemeCycle.Size = New-Object System.Drawing.Size((S 66), (S 27))
Style-FlatButton -Btn $btnThemeCycle -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnThemeCycle.Font = $fontUi
$btnThemeCycle.Text = $script:Config.Theme
$pnlNav.Controls.Add($btnThemeCycle)
Set-Tip $btnThemeCycle "Theme wechseln: Dark / OLED / Light / Terminal (Taste T)" "THEME"

$btnSettings = New-Object System.Windows.Forms.Button
$btnSettings.Location = New-Object System.Drawing.Point((S ($script:NavX + 166)), (S 2))
$btnSettings.Size = New-Object System.Drawing.Size((S 30), (S 27))
Style-FlatButton -Btn $btnSettings -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnSettings.Font = $fontUiBold
$btnSettings.Text = [string][char]0x2699
$pnlNav.Controls.Add($btnSettings)
Set-Tip $btnSettings "Einstellungen (Taste S)"

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point((S ($script:NavX + 200)), (S 6))
$lblStatus.Size = New-Object System.Drawing.Size((S 222), (S 20))
$lblStatus.Font = $fontMono
$lblStatus.ForeColor = $script:Pal.Muted
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblStatus.AutoEllipsis = $true
$lblStatus.Text = "USD 1.0950 | CHF 0.9400"
$pnlNav.Controls.Add($lblStatus)

# v4.4: command line button (Ctrl+K)
$btnCmd = New-Object System.Windows.Forms.Button
$btnCmd.SetBounds((S ($script:NavX + 200)), (S 3), (S 170), (S 24))
Style-FlatButton -Btn $btnCmd -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnCmd.Font = $fontMono
$btnCmd.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$btnCmd.Text = "> Befehl     Strg+K"
$pnlNav.Controls.Add($btnCmd)
Set-Tip $btnCmd "Befehlszeile wie im Terminal: NVDA GP, NVDA DES, NVDA N, CAL, TOP, PORT, NVDA ALRT TRAIL 8 ... (Strg+K)"
$btnCmd.Add_Click({ Show-CommandPalette })

# v4.9.5: data source health dot (green / amber / red) left of the status text
$script:HealthLevel = ""
$pnlHealth = New-Object System.Windows.Forms.Panel
$pnlHealth.SetBounds((S ($script:NavX + 380)), (S 10), (S 12), (S 12))
$pnlHealth.BackColor = $script:Pal.BodyBg
Enable-DoubleBuffering -Control $pnlHealth
$pnlHealth.Add_Paint({
    param($sender, $e)
    $amber = $script:Pal.Warn
    $c = switch ($script:HealthLevel) { "ERR" { $colRed } "WARN" { $amber } "OK" { $colGreen } default { $script:Pal.Muted } }
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $br = New-Object System.Drawing.SolidBrush($c)
    $d = [math]::Min($sender.Width, $sender.Height) - 2
    $e.Graphics.FillEllipse($br, 1, 1, $d, $d)
    $br.Dispose()
})
$pnlNav.Controls.Add($pnlHealth)
Set-Tip $lblStatus "Wechselkurse und Stand der letzten Aktualisierung" "STAND"

# ==============================================================================
# VIEW 1: CHART VIEW
# ==============================================================================
# v5.2 Fresh: list panels as rounded cards (corners painted in the window colour)
$script:CardPaint = {
    param($sender, $e)
    if ($null -eq $script:UiSpec -or -not $script:UiSpec.Fresh) { return }
    try {
        $g = $e.Graphics
        $w = $sender.ClientSize.Width; $h = $sender.ClientSize.Height
        $rad = [float](S $script:UiSpec.CardRadius)
        $outer = New-Object System.Drawing.Drawing2D.GraphicsPath
        $outer.AddRectangle((New-Object System.Drawing.Rectangle(-1, -1, ($w + 2), ($h + 2))))
        $inner = New-RoundedPath (New-Object System.Drawing.RectangleF(0, 0, [float]$w, [float]$h)) $rad
        $outer.AddPath($inner, $false)
        $outer.FillMode = [System.Drawing.Drawing2D.FillMode]::Alternate
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $bb = New-Object System.Drawing.SolidBrush($form.BackColor)
        $g.FillPath($bb, $outer); $bb.Dispose()
        $edge = New-RoundedPath (New-Object System.Drawing.RectangleF(0.5, 0.5, [float]($w - 1), [float]($h - 1))) $rad
        $g.DrawPath($script:GdiCache["cardPen"], $edge)
        $edge.Dispose(); $inner.Dispose(); $outer.Dispose()
    } catch { }
}
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
$cmiTa = $chartContextMenu.Items.Add("Ticker-Analyse: Signale + Kennzahlen (TA)")
[void]$chartContextMenu.Items.Add("-")
$cmiCompare    = $chartContextMenu.Items.Add("Vergleichen mit ... (X)")
$cmiCompareOff = $chartContextMenu.Items.Add("Vergleich entfernen")
$cmiZoomReset  = $chartContextMenu.Items.Add("Zoom zurücksetzen (Z)")
$cmiLevels     = New-Object System.Windows.Forms.ToolStripMenuItem("EK- und Alarmlinien anzeigen")
$cmiLevels.CheckOnClick = $true
$cmiLevels.Checked = [bool]$script:Config.ShowLevels
[void]$chartContextMenu.Items.Add($cmiLevels)
# v4.8: logarithmic price axis
$cmiLog = New-Object System.Windows.Forms.ToolStripMenuItem("Logarithmische Skala (Y)")
$cmiLog.CheckOnClick = $true
$cmiLog.Checked = [bool]$script:Config.LogScale
[void]$chartContextMenu.Items.Add($cmiLog)
# v4.9.5: previous close line (1D / 5D)
$cmiPrevClose = New-Object System.Windows.Forms.ToolStripMenuItem("Vortages-Schluss als Linie (1D / 5D)")
$cmiPrevClose.CheckOnClick = $true
$cmiPrevClose.Checked = [bool]$script:Config.ShowPrevClose
$cmiPrevClose.Add_Click({
    $script:Config.ShowPrevClose = $cmiPrevClose.Checked
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-ChartCacheSignature
    $script:ChartSignature = ""
    Update-AllUiViews
})
[void]$chartContextMenu.Items.Add($cmiPrevClose)
# v5.0: own trades as markers
$cmiTrades = New-Object System.Windows.Forms.ToolStripMenuItem("Eigene Käufe / Verkäufe anzeigen")
$cmiTrades.CheckOnClick = $true
$cmiTrades.Checked = [bool]$script:Config.ShowTrades
$cmiTrades.Add_Click({
    $script:Config.ShowTrades = $cmiTrades.Checked
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    $script:ChartSignature = ""
    Update-AllUiViews
})
[void]$chartContextMenu.Items.Add($cmiTrades)
# v5.0: drawing tools
$cmiDraw = New-Object System.Windows.Forms.ToolStripMenuItem("Zeichnen")
foreach ($dk in @(@("H", "Horizontale Linie"), @("T", "Trendlinie (D)"), @("F", "Fibonacci"))) {
    $dmi = New-Object System.Windows.Forms.ToolStripMenuItem($dk[1])
    $dmi.Tag = $dk[0]
    $dmi.Add_Click({ param($sender, $e) Set-DrawMode ([string]$sender.Tag) })
    [void]$cmiDraw.DropDownItems.Add($dmi)
}
[void]$cmiDraw.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$cmiDrawClear = New-Object System.Windows.Forms.ToolStripMenuItem("Alle Zeichnungen dieses Tickers löschen")
$cmiDrawClear.Add_Click({ Remove-Drawing -All })
[void]$cmiDraw.DropDownItems.Add($cmiDrawClear)
[void]$chartContextMenu.Items.Add($cmiDraw)
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
$btnToggleSma.Text = [string]$script:Config.MaType
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
$btnToggleRsi.Text = if ([string]$script:Config.LowerPanel -eq "MACD") { "MACD" } else { "RSI-$($script:Config.RsiPeriod)" }
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
    $txt = Get-TooltipText -Text ([string]$hit.Tip) -Key $hit.Key -Mode $mode
    if (-not $txt) { return }
    $dur = if ($mode -eq "Long") { 30000 } else { 10000 }
    $toolTip.Show($txt, $Canvas, [int]($X + (S 14)), [int]($Y + (S 18)), [int]$dur)
}

$script:ChartMouseMoveHandler = {
    param($sender, $e)
    # Hit-testing uses the geometry of the bitmap that is actually on screen
    $L = Get-CanvasLayout -Canvas $sender
    if ($null -eq $L) { return }
    if ($null -ne $script:DrawPending) { $script:DrawMouse = Get-ChartPointAt -L $L -X $e.X -Y $e.Y; $sender.Invalidate() }
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
        if ($script:DrawMode) { Set-DrawMode ""; $script:CtxDrawing = $null; return }
        $script:CtxDrawing = Find-DrawingAt -L $L -X $e.X -Y $e.Y
        # price under the mouse for "Alarm hier setzen"
        $my = $e.Y - [int]$L.OffsetY
        $pr = $L.PriceRect
        $script:CtxPrice = if ($my -ge $pr.Top -and $my -le $pr.Bottom -and $pr.Height -gt 0) {
            Get-PriceFromFrac (($pr.Bottom - $my) / [double]$pr.Height) ([double]$L.MinP) ([double]$L.SpanP) ([bool]$L.LogScale)
        } else { [double]::NaN }
        return
    }
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and $script:DrawMode) {
        # v5.0: drawing tools
        $pt = Get-ChartPointAt -L $L -X $e.X -Y $e.Y
        if ($null -eq $pt) { return }
        if ($script:DrawMode -eq "H") { Add-Drawing -Kind "H" -A $pt; Set-DrawMode ""; return }
        if ($null -eq $script:DrawPending) { $script:DrawPending = $pt; Set-TransientStatus "Jetzt den zweiten Punkt klicken (Esc = abbrechen)" 8; return }
        Add-Drawing -Kind $script:DrawMode -A $script:DrawPending -B $pt
        Set-DrawMode ""
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
$viewPortfolio.Add_Paint($script:CardPaint)

$lblPortSummary = New-Object System.Windows.Forms.Label
$lblPortSummary.Location = New-Object System.Drawing.Point((S 10), (S 8))
$lblPortSummary.Size = New-Object System.Drawing.Size((S 424), (S 22))
$lblPortSummary.AutoEllipsis = $true
$lblPortSummary.Font = $fontMono
$lblPortSummary.ForeColor = $script:Pal.Text
$lblPortSummary.Text = "Depotwert: 0.00 $($script:Config.Currency) | Gesamt G/V: +0.00 $($script:Config.Currency) (+0.00%)"
$viewPortfolio.Controls.Add($lblPortSummary)

# v4.9.5: privacy toggle next to the summary (same as F9)
$script:IconFont = if ($script:InstalledFonts -contains "Segoe Fluent Icons") { "Segoe Fluent Icons" } elseif ($script:InstalledFonts -contains "Segoe MDL2 Assets") { "Segoe MDL2 Assets" } else { "" }
$btnPrivacy = New-Object System.Windows.Forms.Button
$btnPrivacy.SetBounds((S 438), (S 6), (S 28), (S 24))
Style-FlatButton -Btn $btnPrivacy -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
if ($script:IconFont) { $btnPrivacy.Font = New-Object System.Drawing.Font($script:IconFont, 9) } else { $btnPrivacy.Font = $fontUiBold }
$btnPrivacy.Add_Click({ Set-PrivacyMode (-not [bool]$script:Config.PrivacyMode) })
$viewPortfolio.Controls.Add($btnPrivacy)

# v4.5: depot selector
$cmbDepot = New-Object System.Windows.Forms.ComboBox
$cmbDepot.Location = New-Object System.Drawing.Point((S 470), (S 6))
$cmbDepot.Size = New-Object System.Drawing.Size((S 136), (S 24))
$cmbDepot.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbDepot.BackColor = $script:Pal.Input
$cmbDepot.ForeColor = $script:Pal.Accent
$cmbDepot.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbDepot.Font = $fontUi
$cmbDepot.DropDownWidth = S 200
$viewPortfolio.Controls.Add($cmbDepot)
Set-Tip $cmbDepot "Depot wählen: mehrere Portfolios (z. B. zweiter Broker, Übungsdepot). Befehl: PF <Name>"

$cmbPortSort = New-Object System.Windows.Forms.ComboBox
$cmbPortSort.Location = New-Object System.Drawing.Point((S 612), (S 6))
$cmbPortSort.Size = New-Object System.Drawing.Size((S 136), (S 24))
$cmbPortSort.DropDownWidth = S 200
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
[void]$dgvPortfolio.Columns.Add("Contrib", "Beitrag heute")   # v4.9.5

$dgvPortfolio.Columns[0].Width = S 68
$dgvPortfolio.Columns[1].Width = S 70
$dgvPortfolio.Columns[2].Width = S 66
$dgvPortfolio.Columns[3].Width = S 74
$dgvPortfolio.Columns[4].Width = S 74
$dgvPortfolio.Columns[5].Width = S 92
$dgvPortfolio.Columns[6].Width = S 56
$dgvPortfolio.Columns[7].Width = S 132
$dgvPortfolio.Columns[8].Width = S 68
$dgvPortfolio.Columns[9].Width = S 84
$viewPortfolio.Controls.Add($dgvPortfolio)

# v4.9.5: hint with buttons in the empty part of a short portfolio list
$pnlPortHint = New-Object System.Windows.Forms.Panel
$pnlPortHint.Size = New-Object System.Drawing.Size((S 520), (S 64))
$pnlPortHint.BackColor = $script:Pal.Card
$pnlPortHint.Visible = $false
$lblPortHint = New-Object System.Windows.Forms.Label
$lblPortHint.SetBounds(0, 0, (S 520), (S 20))
$lblPortHint.Font = $fontUi
$lblPortHint.ForeColor = $script:Pal.Muted
$lblPortHint.Text = "Weitere Positionen: unten Ticker, Stück und EK eintragen - oder:"
$pnlPortHint.Controls.Add($lblPortHint)
$btnHintTx = New-Object System.Windows.Forms.Button
$btnHintTx.SetBounds(0, (S 26), (S 160), (S 26))
Style-FlatButton -Btn $btnHintTx -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnHintTx.Font = $fontUiBold
$btnHintTx.Text = "+ Kauf buchen ..."
$btnHintTx.Add_Click({ Show-TransactionDialog -Ticker ([string]$script:Config.ActiveTicker) })
$pnlPortHint.Controls.Add($btnHintTx)
$btnHintImp = New-Object System.Windows.Forms.Button
$btnHintImp.SetBounds((S 168), (S 26), (S 170), (S 26))
Style-FlatButton -Btn $btnHintImp -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnHintImp.Font = $fontUiBold
$btnHintImp.Text = "Broker-CSV importieren ..."
$btnHintImp.Add_Click({ Show-CsvImportDialog })
$pnlPortHint.Controls.Add($btnHintImp)
$viewPortfolio.Controls.Add($pnlPortHint)
$pnlPortHint.BringToFront()

function Update-PortfolioHint {
    # shown below the rows while there are at most 3 positions and room for it
    $n = $dgvPortfolio.Rows.Count
    $top = $dgvPortfolio.Top + $dgvPortfolio.ColumnHeadersHeight + $n * $dgvPortfolio.RowTemplate.Height + (S 24)
    $show = ($n -le 3) -and (($top + $pnlPortHint.Height) -lt ($dgvPortfolio.Bottom - (S 8)))
    if ($show) { $pnlPortHint.Location = New-Object System.Drawing.Point(($dgvPortfolio.Left + (S 12)), $top) }
    if ($pnlPortHint.Visible -ne $show) { $pnlPortHint.Visible = $show }
}
$dgvPortfolio.Add_Resize({ Update-PortfolioHint })


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
$btnPortTx.Size = New-Object System.Drawing.Size((S 90), (S 26))
Style-FlatButton -Btn $btnPortTx -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnPortTx.Font = $fontUiBold
$btnPortTx.Text = "Transaktion"
$pnlPortBottom.Controls.Add($btnPortTx)
Set-Tip $btnPortTx "Kauf / Verkauf / Dividende buchen (realisierter G/V wird gespeichert)" "TX"

# v5.0: more depot tools behind a small menu button
$btnPortMore = New-Object System.Windows.Forms.Button
$btnPortMore.Location = New-Object System.Drawing.Point((S 702), (S 56))
$btnPortMore.Size = New-Object System.Drawing.Size((S 28), (S 26))
Style-FlatButton -Btn $btnPortMore -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnPortMore.Font = $fontUiBold
$btnPortMore.Text = [string][char]0x25BE
$pnlPortBottom.Controls.Add($btnPortMore)
Set-Tip $btnPortMore "Cash-Konto, Sparpläne, Rebalancing, Risiko, Heatmap"
$portMoreMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miPmCash  = $portMoreMenu.Items.Add("Cash-Konto ... (CASH)")
$miPmPlans = $portMoreMenu.Items.Add("Sparpläne ... (SPAR)")
[void]$portMoreMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miPmRebal = $portMoreMenu.Items.Add("Zielgewichte / Rebalancing (REBAL)")
$miPmRisk  = $portMoreMenu.Items.Add("Risiko (RISK)")
$miPmHeat  = $portMoreMenu.Items.Add("Heatmap (HEAT)")
$miPmCash.Add_Click({ Show-CashDialog })
$miPmPlans.Add_Click({ Show-SavingsPlansDialog })
$miPmRebal.Add_Click({ Show-AnalysisDialog -Page "Target" })
$miPmRisk.Add_Click({ Show-AnalysisDialog -Page "Risk" })
$miPmHeat.Add_Click({ Show-AnalysisDialog -Page "Heat" })
$btnPortMore.Add_Click({ param($sender, $e) $portMoreMenu.Show($sender, 0, $sender.Height) })

$btnPortHist = New-Object System.Windows.Forms.Button
$btnPortHist.Location = New-Object System.Drawing.Point((S 610), (S 88))
$btnPortHist.Size = New-Object System.Drawing.Size((S 58), (S 26))
Style-FlatButton -Btn $btnPortHist -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnPortHist.Font = $fontUi
$btnPortHist.Text = "Historie"
$pnlPortBottom.Controls.Add($btnPortHist)
Set-Tip $btnPortHist "Alle Transaktionen, realisierter G/V, CSV-Export, Jahresreport" "REALIZED"

# v4.1: portfolio analysis (value history, returns, allocation)
$btnPortAna = New-Object System.Windows.Forms.Button
$btnPortAna.Location = New-Object System.Drawing.Point((S 672), (S 88))
$btnPortAna.Size = New-Object System.Drawing.Size((S 58), (S 26))
Style-FlatButton -Btn $btnPortAna -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnPortAna.Font = $fontUi
$btnPortAna.Text = "Analyse"
$pnlPortBottom.Controls.Add($btnPortAna)
Set-Tip $btnPortAna "Wertentwicklung mit Benchmark, Rendite je Position, Aufteilung nach Sektor/Land/Währung (Taste P)" "XIRR"
$btnPortAna.Add_Click({ Show-AnalysisDialog })

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
$viewWatch.Add_Paint($script:CardPaint)

$lblWlTitle = New-Object System.Windows.Forms.Label
$lblWlTitle.Location = New-Object System.Drawing.Point((S 10), (S 8))
$lblWlTitle.Size = New-Object System.Drawing.Size((S 228), (S 20))
$lblWlTitle.AutoEllipsis = $true
$lblWlTitle.Font = $fontUiBold
$lblWlTitle.ForeColor = $script:Pal.Accent
$lblWlTitle.Text = "Watchlist (Ziehen = Reihenfolge | Entf = Löschen)"
$viewWatch.Controls.Add($lblWlTitle)
Set-Tip $lblWlTitle "Ziehen = Reihenfolge, Entf = Löschen, Rechtsklick auf einen Ticker = Aktionen und Gruppen"

# v5.0: watchlist groups (e.g. Tech, ETFs) - a filter over the one watchlist
$cmbWlGroup = New-Object System.Windows.Forms.ComboBox
$cmbWlGroup.Location = New-Object System.Drawing.Point((S 242), (S 6))
$cmbWlGroup.Size = New-Object System.Drawing.Size((S 118), (S 24))
$cmbWlGroup.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbWlGroup.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbWlGroup.BackColor = $script:Pal.Input
$cmbWlGroup.ForeColor = $script:Pal.Accent
$cmbWlGroup.Font = $fontUi
$cmbWlGroup.DropDownWidth = S 200
# not a tab stop and focus goes back to the list after a choice - otherwise
# single-key shortcuts (K, D, 1-6, ...) would type into the drop-down
$cmbWlGroup.TabStop = $false
$viewWatch.Controls.Add($cmbWlGroup)
Set-Tip $cmbWlGroup "Gruppe anzeigen: Alle oder eine eigene Gruppe. Ticker per Rechtsklick > 'Zu Gruppe' einsortieren."
$script:WlGroupKeys = New-Object System.Collections.Generic.List[string]
$script:WlGroupUpdating = $false
$script:WlGroupSig = ""
function Update-WatchGroupCombo {
    $sig = "{0}|{1}|{2}|{3}" -f (@($script:Config.Watchlist) -join ","), [string]$script:Config.WatchGroup, (@($script:Config.WatchGroups | ForEach-Object { "{0}:{1}" -f $_.Name, (@($_.Symbols) -join " ") }) -join ";"), [string]$script:Config.Language
    if ($sig -eq $script:WlGroupSig -and $cmbWlGroup.Items.Count -gt 0) { return }
    $script:WlGroupSig = $sig
    $script:WlGroupUpdating = $true
    $cmbWlGroup.BeginUpdate()
    $cmbWlGroup.Items.Clear(); $script:WlGroupKeys.Clear()
    $all = @($script:Config.Watchlist).Count
    [void]$cmbWlGroup.Items.Add(("{0} ({1})" -f (Tr "Alle"), $all)); $script:WlGroupKeys.Add("")
    foreach ($gr in @($script:Config.WatchGroups)) {
        if ($null -eq $gr -or -not $gr.Name) { continue }
        $cnt = @(Get-WatchGroupSymbols -Watchlist @($script:Config.Watchlist) -Groups @($script:Config.WatchGroups) -Group ([string]$gr.Name)).Count
        [void]$cmbWlGroup.Items.Add(("{0} ({1})" -f $gr.Name, $cnt)); $script:WlGroupKeys.Add([string]$gr.Name)
    }
    [void]$cmbWlGroup.Items.Add((Tr "+ Neue Gruppe ...")); $script:WlGroupKeys.Add("|new")
    if ([string]$script:Config.WatchGroup) { [void]$cmbWlGroup.Items.Add(("{0} '{1}'" -f (Tr "Gruppe löschen:"), $script:Config.WatchGroup)); $script:WlGroupKeys.Add("|del") }
    $ix = $script:WlGroupKeys.IndexOf([string]$script:Config.WatchGroup)
    $cmbWlGroup.SelectedIndex = [math]::Max(0, $ix)
    $cmbWlGroup.EndUpdate()
    $script:WlGroupUpdating = $false
}
function Set-WatchGroup {
    param([string]$Name)
    $script:Config.WatchGroup = $Name
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-WatchGroupCombo
    Refresh-WatchlistAndAlerts
}
function New-WatchGroup {
    param([string]$Symbol = "")
    $nm = Read-TextInput -Title "Neue Gruppe" -Prompt "Name der Gruppe (z. B. Tech, ETFs, Dividenden):"
    if (-not $nm) { return "" }
    $nm = $nm.Trim()
    if (@($script:Config.WatchGroups | Where-Object { $null -ne $_ -and [string]$_.Name -eq $nm }).Count -eq 0) {
        $script:Config.WatchGroups = @(Set-WatchGroupMember -Groups @($script:Config.WatchGroups) -Group $nm -Symbol $Symbol -In $true)
    } elseif ($Symbol) {
        $script:Config.WatchGroups = @(Set-WatchGroupMember -Groups @($script:Config.WatchGroups) -Group $nm -Symbol $Symbol -In $true)
    }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    return $nm
}
$cmbWlGroup.Add_SelectionChangeCommitted({
    if ($script:WlGroupUpdating) { return }
    $k = $script:WlGroupKeys[$cmbWlGroup.SelectedIndex]
    if ($k -eq "|new") {
        $nm = New-WatchGroup
        if ($nm) { Set-WatchGroup $nm } else { Update-WatchGroupCombo }
        return
    }
    if ($k -eq "|del") {
        $gn = [string]$script:Config.WatchGroup
        if (Confirm-Action -Text ("Gruppe '{0}' löschen? (Die Ticker bleiben in der Watchlist.)" -f $gn) -Title "Gruppe") {
            $script:Config.WatchGroups = @(@($script:Config.WatchGroups) | Where-Object { $null -ne $_ -and [string]$_.Name -ne $gn })
            Set-WatchGroup ""
        } else { Update-WatchGroupCombo }
        return
    }
    Set-WatchGroup $k
    if ($dgvWatchlist.CanFocus) { [void]$dgvWatchlist.Focus() }
})

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
[void]$dgvWatchlist.Columns.Add("Target", "Analysten")   # v4.9.5, hidden by default (header right-click)
$dgvWatchlist.Columns["Target"].Visible = $false

# Design widths = minimum widths (sum fits the 480 px grid incl. scrollbar)
$dgvWatchlist.Columns["Sym"].Width    = S 64
$dgvWatchlist.Columns["Spark"].Width  = S 44
$dgvWatchlist.Columns["Price"].Width  = S 92
$dgvWatchlist.Columns["Day"].Width    = S 58
$dgvWatchlist.Columns["Ext"].Width    = S 54
$dgvWatchlist.Columns["Rsi"].Width    = S 44
$dgvWatchlist.Columns["Dist"].Width   = S 54
$dgvWatchlist.Columns["Market"].Width = S 56
$dgvWatchlist.Columns["Target"].Width = S 84

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
# v4.9.5: 52-week range bar under the "52W-H" value (marker = price between low and high)
$dgvWatchlist.Add_CellPainting({
    param($sender, $e)
    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0 -or $sender.Columns[$e.ColumnIndex].Name -ne "Dist") { return }
    $sym = [string]$sender.Rows[$e.RowIndex].Cells[0].Value
    $q = $script:QuoteStore[$sym]
    if ($null -eq $q) { return }
    $f = Get-RangePosition -Price ([double]$q.Price) -Low ([double]$q.Low52) -High ([double]$q.High52)
    if ([double]::IsNaN($f)) { return }
    $e.Paint($e.ClipBounds, [System.Windows.Forms.DataGridViewPaintParts]::All)
    $b = $e.CellBounds
    $x0 = $b.Left + (S 4); $x1 = $b.Right - (S 5)
    $y = $b.Bottom - (S 5)
    if ($x1 -le $x0) { $e.Handled = $true; return }
    $pen = New-Object System.Drawing.Pen($script:Pal.Border, [float](S 2))
    $e.Graphics.DrawLine($pen, $x0, $y, $x1, $y)
    $pen.Dispose()
    $mx = $x0 + [int][math]::Round(($x1 - $x0) * $f)
    $mc = if ($f -ge 0.85) { $colGreen } elseif ($f -le 0.15) { $colRed } else { $script:Pal.Accent }
    $br = New-Object System.Drawing.SolidBrush($mc)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $r = S 3
    $e.Graphics.FillEllipse($br, ($mx - $r), ($y - $r), (2 * $r), (2 * $r))
    $br.Dispose()
    $e.Handled = $true
})

function Apply-NumberAlignment {
    # v4.9: numbers right-aligned (header too), so digits stay in their
    # columns when prices change; off = left as before
    $right = [bool]$script:Config.AlignNumbersRight
    $cell = if ($right) { [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight } else { [System.Windows.Forms.DataGridViewContentAlignment]::MiddleLeft }
    $sets = @(
        @($dgvWatchlist, @("Price", "Day", "Ext", "Rsi", "Dist", "Target")),
        @($dgvPortfolio, @("Shares", "Avg", "Price", "Val", "Weight", "Pnl", "Day", "Contrib"))
    )
    foreach ($set in $sets) {
        foreach ($cn in $set[1]) {
            $col = $set[0].Columns[$cn]
            if ($null -eq $col) { continue }
            $col.DefaultCellStyle.Alignment = $cell
            $col.HeaderCell.Style.Alignment = $cell
        }
    }
}
Apply-NumberAlignment

# ==============================================================================
# v4.9: NEWS TAB - one feed for the depot + watchlist
# ==============================================================================
$script:NewsItems     = @()
$script:NewsLoading   = $false
$script:NewsLoadedAt  = [DateTime]::MinValue
$script:NewsError     = ""
$script:NextNewsLoad  = (Get-Date).AddSeconds(25)
$script:NewsWasVisible = $false
$script:NewsSeenAt    = [DateTime]::MinValue
if ([string]$script:Config.NewsSeenAt) {
    $nsa = [DateTime]::MinValue
    if ([DateTime]::TryParse([string]$script:Config.NewsSeenAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$nsa)) { $script:NewsSeenAt = $nsa }
}
$script:NewsBoldSince = $script:NewsSeenAt
$script:NewsGridSig = ""
$script:NewsComboSig = ""
$script:LastNewsTip = ""
$script:NewsFilterUpdating = $false
$script:NewsFilterKeys = New-Object System.Collections.Generic.List[string]

$aNT = [System.Windows.Forms.AnchorStyles]::Top
$aNB = [System.Windows.Forms.AnchorStyles]::Bottom
$aNL = [System.Windows.Forms.AnchorStyles]::Left
$aNR = [System.Windows.Forms.AnchorStyles]::Right

$viewNews = New-Object System.Windows.Forms.Panel
$viewNews.Location = New-Object System.Drawing.Point((S 12), (S 92))
$viewNews.Size = New-Object System.Drawing.Size((S 756), (S 456))
$viewNews.BackColor = $script:Pal.Card
$viewNews.Visible = $false
$form.Controls.Add($viewNews)
$viewNews.Add_Paint($script:CardPaint)

$lblNewsTitle = New-Object System.Windows.Forms.Label
$lblNewsTitle.SetBounds((S 10), (S 8), (S 330), (S 20))
$lblNewsTitle.Font = $fontUiBold
$lblNewsTitle.ForeColor = $script:Pal.Accent
$lblNewsTitle.Text = "Nachrichten - Depot und Watchlist"
$lblNewsTitle.Anchor = $aNT -bor $aNL
$viewNews.Controls.Add($lblNewsTitle)

$cmbNewsFilter = New-Object System.Windows.Forms.ComboBox
$cmbNewsFilter.SetBounds((S 470), (S 6), (S 128), (S 24))
$cmbNewsFilter.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbNewsFilter.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbNewsFilter.BackColor = $script:Pal.Input
$cmbNewsFilter.ForeColor = $script:Pal.Text
$cmbNewsFilter.Font = $fontMono
$cmbNewsFilter.MaxDropDownItems = 20
$cmbNewsFilter.Anchor = $aNT -bor $aNR
$viewNews.Controls.Add($cmbNewsFilter)
Set-Tip $cmbNewsFilter "Welche Nachrichten: alle, nur Depot, nur Watchlist oder ein Ticker (auch: NEWS DEPOT / NEWS WATCH / NEWS NVDA)"

$btnNewsRead = New-Object System.Windows.Forms.Button
$btnNewsRead.SetBounds((S 604), (S 6), (S 112), (S 24))
Style-FlatButton -Btn $btnNewsRead -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnNewsRead.Font = $fontUiBold
$btnNewsRead.Text = "Alle gelesen"
$btnNewsRead.Anchor = $aNT -bor $aNR
$viewNews.Controls.Add($btnNewsRead)
Set-Tip $btnNewsRead "Neue Meldungen sind fett, bis du sie als gelesen markierst"

$btnNewsRefresh = New-Object System.Windows.Forms.Button
$btnNewsRefresh.SetBounds((S 722), (S 6), (S 26), (S 24))
Style-FlatButton -Btn $btnNewsRefresh -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnNewsRefresh.Font = $fontUiBold
$btnNewsRefresh.Text = [string][char]0x21BB
$btnNewsRefresh.Anchor = $aNT -bor $aNR
$viewNews.Controls.Add($btnNewsRefresh)
Set-Tip $btnNewsRefresh "Nachrichten jetzt neu laden"

$lblNewsInfo = New-Object System.Windows.Forms.Label
$lblNewsInfo.SetBounds((S 10), (S 32), (S 738), (S 18))
$lblNewsInfo.Font = $fontUi
$lblNewsInfo.ForeColor = $script:Pal.Muted
$lblNewsInfo.Text = "Nachrichten werden geladen ..."
$lblNewsInfo.Anchor = $aNT -bor $aNL -bor $aNR
$viewNews.Controls.Add($lblNewsInfo)

$dgvNews = New-Object System.Windows.Forms.DataGridView
$dgvNews.SetBounds((S 8), (S 54), (S 740), (S 394))
Style-DataGrid -Grid $dgvNews
Enable-DoubleBuffering -Control $dgvNews
$dgvNews.Anchor = $aNT -bor $aNB -bor $aNL -bor $aNR
$dgvNews.ShowCellToolTips = $true
[void]$dgvNews.Columns.Add("Age",   "Zeit")
[void]$dgvNews.Columns.Add("Syms",  "Ticker")
[void]$dgvNews.Columns.Add("Src",   "Quelle")
[void]$dgvNews.Columns.Add("Title", "Titel")
$dgvNews.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
$dgvNews.Columns["Age"].Width  = S 104
$dgvNews.Columns["Syms"].Width = S 150
$dgvNews.Columns["Src"].Width  = S 120
$dgvNews.Columns["Title"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
$dgvNews.Columns["Title"].DefaultCellStyle.Font = $fontGridUi
foreach ($nc in $dgvNews.Columns) { $nc.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable }
$viewNews.Controls.Add($dgvNews)
$dgvNews.Columns["Age"].ToolTipText  = "Wann die Meldung erschienen ist"
$dgvNews.Columns["Syms"].ToolTipText = "Zu welchen deiner Ticker sie gehört. Mit Prozentzahl: der Ticker bewegt sich heute stark. Klick = Ticker öffnen"
$dgvNews.Columns["Title"].ToolTipText = "Doppelklick öffnet den Artikel im Browser"

function Get-NewsFilterLabel {
    param([string]$Filter)
    switch ([string]$Filter) {
        "All"       { return (Tr "Alle") }
        "Holdings"  { return "Depot" }
        "Watchlist" { return "Watchlist" }
        default     { return [string]$Filter }
    }
}

function Update-NewsFilterCombo {
    # Alle / Depot / Watchlist, then every ticker of depot + watchlist
    $script:NewsFilterKeys = New-Object System.Collections.Generic.List[string]
    foreach ($k in @("All", "Holdings", "Watchlist")) { $script:NewsFilterKeys.Add($k) }
    foreach ($s in @(Get-NewsSymbols -Holdings @($script:Portfolio.Keys | Sort-Object) -Watchlist @($script:Config.Watchlist) -Max 60)) { $script:NewsFilterKeys.Add($s) }
    $cur = [string]$script:Config.NewsFilter
    if (-not $script:NewsFilterKeys.Contains($cur)) { $script:NewsFilterKeys.Add($cur) }
    $sig = ($script:NewsFilterKeys -join ",") + "|" + $cur + "|" + [string]$script:Config.Language
    if ($sig -eq $script:NewsComboSig -and $cmbNewsFilter.Items.Count -gt 0) { return }
    $script:NewsComboSig = $sig
    $script:NewsFilterUpdating = $true
    $cmbNewsFilter.BeginUpdate()
    $cmbNewsFilter.Items.Clear()
    foreach ($k in $script:NewsFilterKeys) { [void]$cmbNewsFilter.Items.Add((Get-NewsFilterLabel $k)) }
    $cmbNewsFilter.SelectedIndex = [math]::Max(0, $script:NewsFilterKeys.IndexOf($cur))
    $cmbNewsFilter.EndUpdate()
    $script:NewsFilterUpdating = $false
}

function Set-NewsFilter {
    param([string]$Filter)
    $f = ([string]$Filter).Trim()
    if (-not $f) { $f = "All" }
    $script:Config.NewsFilter = $f
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-NewsFilterCombo
    Refresh-NewsGrid
}

function Get-NewsNewest {
    $newest = [DateTime]::MinValue
    foreach ($n in @($script:NewsItems)) { if ($null -ne $n -and [DateTime]$n.Time -gt $newest) { $newest = [DateTime]$n.Time } }
    return $newest
}

function Set-NewsSeen {
    param([DateTime]$At)
    if ($At -le $script:NewsSeenAt) { return }
    $script:NewsSeenAt = $At
    $script:Config.NewsSeenAt = $At.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
}

function Update-NewsBadge {
    # Tab text "News (F4)" or "News ● 5" (unread since the tab was last seen).
    # While the tab is shown everything in it counts as seen; what was new
    # when it opened stays bold until "Alle gelesen".
    $vis = [bool]$script:ViewOn["News"] -and $form.Visible -and -not [bool]$script:Config.CompactMode
    $cnt = 0
    if ($vis) {
        if (-not $script:NewsWasVisible) { $script:NewsBoldSince = $script:NewsSeenAt }
        Set-NewsSeen (Get-NewsNewest)
    } else {
        $cnt = Get-NewsUnreadCount -Items (Remove-MutedNews -Items $script:NewsItems -Muted @($script:Config.NewsMuted)) -Since $script:NewsSeenAt
    }
    $script:NewsWasVisible = $vis
    $b = $tabButtons["News"]
    if ($null -eq $b) { return }
    $txt = if ($cnt -gt 0) { "News {0} {1}" -f [char]0x25CF, [math]::Min(99, $cnt) } else { "News (F4)" }
    if ($b.Text -ne $txt) { $b.Text = $txt }
    if (-not [bool]$script:ViewOn["News"]) { $b.ForeColor = if ($cnt -gt 0) { $script:Pal.Accent } else { $script:Pal.Text } }
    $tipTxt = if ($cnt -gt 0) { "{0} neue Nachrichten zu Depot und Watchlist (F4)" -f $cnt } else { "Nachrichten zu Depot und Watchlist (F4)" }
    if ($script:LastNewsTip -ne $tipTxt) { $script:LastNewsTip = $tipTxt; Set-DynTip $b $tipTxt }
}

function Get-NewsTooltip {
    param($Item)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add([string]$Item.Title)
    $meta = @()
    if ([DateTime]$Item.Time -gt [DateTime]::MinValue) { $meta += ([DateTime]$Item.Time).ToString("dd.MM.yyyy HH:mm", $inv) }
    if ($Item.Publisher) { $meta += [string]$Item.Publisher }
    if ($meta.Count -gt 0) { $lines.Add($meta -join "  |  ") }
    if (@($Item.Syms).Count -gt 0) { $lines.Add("Ticker: " + (@($Item.Syms) -join ", ")) }
    if ($Item.Link) { $lines.Add((Tr "Doppelklick öffnet den Artikel im Browser")) }
    return ($lines -join "`r`n")
}

function Refresh-NewsGrid {
    # -IfChanged: skip when nothing changed (called on every price refresh;
    # the ages "vor 5 min" need at most one rebuild per minute)
    param([switch]$IfChanged)
    if ($null -eq $dgvNews -or $dgvNews.IsDisposed) { return }
    $sig = "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}" -f $script:NewsLoadedAt.Ticks, [string]$script:Config.NewsFilter, $script:NewsBoldSince.Ticks, (Get-Date).ToString("yyyyMMddHHmm"), $script:NewsLoading, @($script:NewsItems).Count, (@($script:Config.NewsMuted) -join ","), [bool]$script:Config.PrivacyMode
    if ($IfChanged -and $sig -eq $script:NewsGridSig) { return }
    $script:NewsGridSig = $sig
    $p = $script:Pal
    $hold = @($script:Portfolio.Keys)
    $items = @(Select-NewsItems -Items (Remove-MutedNews -Items $script:NewsItems -Muted @($script:Config.NewsMuted)) -Filter ([string]$script:Config.NewsFilter) -Holdings $hold -Watchlist @($script:Config.Watchlist))
    $dayPct = @{}
    foreach ($k in @($script:QuoteStore.Keys)) {
        $q = $script:QuoteStore[$k]
        if ($null -ne $q -and $null -ne $q.ChangePct -and -not [bool]$q.FromCache) { $dayPct[([string]$k).ToUpperInvariant()] = [double]$q.ChangePct }
    }
    $lang = [string]$script:Config.Language
    $now = Get-Date
    $first = -1
    try { $first = $dgvNews.FirstDisplayedScrollingRowIndex } catch { }
    $selKey = ""
    if ($dgvNews.SelectedRows.Count -gt 0 -and $null -ne $dgvNews.SelectedRows[0].Tag) { $selKey = [string]$dgvNews.SelectedRows[0].Tag.Key }
    # v4.9.5: the day move only on the newest item of each ticker
    $movers = Get-NewsMoverRows -Items $items -DayPct $dayPct -Threshold ([double]$script:Config.NewsMoveThreshold)
    $dgvNews.SuspendLayout()
    $dgvNews.Rows.Clear()
    foreach ($n in $items) {
        $mv = $movers[[string]$n.Key]
        $symTxt = @($n.Syms | Select-Object -First 4) -join " "
        if (@($n.Syms).Count -gt 4) { $symTxt += " +" + (@($n.Syms).Count - 4) }
        if ($null -ne $mv) { $symTxt = "{0}  {1}{2:+0.0;-0.0}%" -f $symTxt, (Get-ArrowPrefix $mv.Pct), $mv.Pct }
        $idx = $dgvNews.Rows.Add((Format-NewsAge -Time ([DateTime]$n.Time) -Now $now -Lang $lang), $symTxt, [string]$n.Publisher, [string]$n.Title)
        $row = $dgvNews.Rows[$idx]
        $row.Tag = $n
        $row.Cells["Age"].Style.ForeColor = $p.Muted
        $row.Cells["Src"].Style.ForeColor = $p.Muted
        $row.Cells["Syms"].Style.ForeColor = if ($null -eq $mv) { $p.Accent } elseif ($mv.Pct -ge 0) { $colGreen } else { $colRed }
        if ([DateTime]$n.Time -gt $script:NewsBoldSince) {
            foreach ($cn in @("Age", "Syms", "Src")) { $row.Cells[$cn].Style.Font = $fontGridBold }
            $row.Cells["Title"].Style.Font = $fontGridUiBold
        }
        $tip = Get-NewsTooltip $n
        foreach ($cn in @("Age", "Title")) { $row.Cells[$cn].ToolTipText = $tip }
        $row.Cells["Src"].ToolTipText = ([string]$n.Publisher) + "`r`n" + (Tr "Rechtsklick: Quelle ausblenden")
        $row.Cells["Syms"].ToolTipText = if ($null -ne $mv) { "{0} heute {1:+0.0;-0.0}% - Klick öffnet den Ticker" -f $mv.Sym, $mv.Pct } else { "Klick öffnet den Ticker" }
        if ($selKey -and [string]$n.Key -eq $selKey) { $row.Selected = $true }
    }
    if ($items.Count -eq 0) {
        $msg = if ($script:NewsLoading -or $script:NewsLoadedAt -eq [DateTime]::MinValue) { "Nachrichten werden geladen ..." }
               elseif (@($script:NewsItems).Count -gt 0) { "Keine Nachrichten für diesen Filter." }
               elseif ($script:NewsError) { "Keine Verbindung - Nachrichten kommen beim nächsten Versuch." }
               else { "Keine Nachrichten der letzten 14 Tage." }
        $idx = $dgvNews.Rows.Add("", "", "", (Tr $msg))
        $dgvNews.Rows[$idx].DefaultCellStyle.ForeColor = $p.Muted
    }
    if (-not $selKey) { $dgvNews.ClearSelection() }
    if ($first -ge 0 -and $first -lt $dgvNews.Rows.Count) { try { $dgvNews.FirstDisplayedScrollingRowIndex = $first } catch { } }
    $dgvNews.ResumeLayout()
    Update-NewsInfo -Shown $items.Count
}

function Update-NewsInfo {
    param([int]$Shown = -1)
    if ($Shown -lt 0) { $Shown = @($dgvNews.Rows | Where-Object { $null -ne $_.Tag }).Count }
    $parts = @()
    if ($script:NewsLoading) { $parts += (Tr "lädt ...") }
    if ($script:NewsLoadedAt -gt [DateTime]::MinValue) {
        $parts += ("{0} {1}" -f $Shown, (Tr "Meldungen"))
        $parts += ("{0} {1}" -f (Tr "Stand"), $script:NewsLoadedAt.ToString("HH:mm"))
    }
    if ($script:NewsError) { $parts += (Tr "letzter Versuch ohne Verbindung") }
    $parts += (Tr "Quelle: Yahoo Finance, Doppelklick öffnet den Artikel")
    $lblNewsInfo.Text = $parts -join "  |  "
}

function Invoke-NewsKeywordCheck {
    # v4.9.5: tray + phone push for new headlines with a chosen word about a
    # held ticker (optionally the watchlist). Each item once: the newest
    # checked time is kept in the config, the first run only sets it.
    $kw = @(ConvertTo-KeywordList ([string]$script:Config.NewsKeywords))
    $newest = Get-NewsNewest
    $last = [DateTime]::MinValue
    if ([string]$script:Config.NewsKeywordLastAt) {
        [void][DateTime]::TryParse([string]$script:Config.NewsKeywordLastAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$last)
    }
    if ($kw.Count -gt 0 -and $last -gt [DateTime]::MinValue) {
        $syms = @($script:Portfolio.Keys)
        if ([bool]$script:Config.NewsKeywordWatch) { $syms += @($script:Config.Watchlist) }
        $hits = @(Find-NewsKeywordHits -Items (Remove-MutedNews -Items $script:NewsItems -Muted @($script:Config.NewsMuted)) -Keywords $kw -Symbols $syms -Since $last)
        foreach ($h in ($hits | Select-Object -Last 3)) {
            $title = "News {0}: {1}" -f $h.Sym, $h.Keyword
            $msg = "{0} ({1})" -f [string]$h.Item.Title, [string]$h.Item.Publisher
            $push = Send-WidgetNotification -Title $title -Message $msg -Kind "News"
            Add-AlertLogEntry -Alert ([PSCustomObject]@{ Ticker = $h.Sym; Condition = "NEWS"; Note = $h.Keyword }) -Text ([string]$h.Item.Title) -Push $push
        }
        if ($hits.Count -gt 3) { Write-WidgetLog ("News keywords: {0} hits, notified the newest 3" -f $hits.Count) }
    }
    if ($newest -gt $last) {
        $script:Config.NewsKeywordLastAt = $newest.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
    }
}

function Start-NewsLoad {
    # One Yahoo search request per ticker (holdings + watchlist, max 40),
    # merged into one feed in the background
    if ($script:IsClosing -or $script:NewsLoading) { return }
    # v4.9.5: Yahoo asked us to slow down -> the news wait for the same pause
    if ((Get-Date) -lt $script:BackoffUntil) {
        $script:NextNewsLoad = $script:BackoffUntil.AddMinutes(1)
        return
    }
    $syms = @(Get-NewsSymbols -Holdings @($script:Portfolio.Keys | Sort-Object) -Watchlist @($script:Config.Watchlist) -Max 40)
    if ($syms.Count -eq 0) {
        $script:NewsItems = @()
        $script:NewsLoadedAt = Get-Date
        Update-NewsBadge
        if ($viewNews.Visible) { Refresh-NewsGrid }
        return
    }
    $urls = @{}
    foreach ($s in $syms) { $urls[$s] = "https://query1.finance.yahoo.com/v1/finance/search?q={0}&quotesCount=0&newsCount=10" -f [Uri]::EscapeDataString($s) }
    $script:NewsLoading = $true
    if ($viewNews.Visible) { Update-NewsInfo }
    Start-FetchJob -Urls @($urls.Values) -MaxConcurrency 4 -Context @{ Urls = $urls } -OnComplete {
        param($Box, $Ctx)
        $script:NewsLoading = $false
        if ([bool]$Box.RateLimited) {
            # same back-off as the price refresh (30 s doubling, max 5 min)
            $script:BackoffLevel = [math]::Min(5, $script:BackoffLevel + 1)
            $script:BackoffUntil = (Get-Date).AddSeconds([math]::Min(300, 30 * [math]::Pow(2, $script:BackoffLevel - 1)))
            $script:NextNewsLoad = $script:BackoffUntil.AddMinutes(1)
            Write-WidgetLog ("News: rate limit, pause until {0:HH:mm:ss}" -f $script:BackoffUntil) "WARN"
        }
        $by = @{}
        $ok = 0
        foreach ($s in $Ctx.Urls.Keys) {
            $j = $Box.Results[$Ctx.Urls[$s]]
            if ($null -ne $j) { $ok++ }
            $by[$s] = @(ConvertFrom-YahooNews $j)
        }
        if ($ok -eq 0) {
            $script:NewsError = "offline"
            Write-WidgetLog "News: no answer for $($Ctx.Urls.Count) tickers" "WARN"
        } else {
            $script:NewsError = ""
            $script:NewsItems = @(Merge-NewsFeed -BySymbol $by -Max 150)
            $script:NewsLoadedAt = Get-Date
            # first start: nothing counts as unread
            if ($script:NewsSeenAt -eq [DateTime]::MinValue) {
                Set-NewsSeen (Get-NewsNewest)
                $script:NewsBoldSince = $script:NewsSeenAt
            }
            Invoke-NewsKeywordCheck
        }
        Update-NewsBadge
        if ($viewNews.Visible) { Refresh-NewsGrid }
    }
}

$cmbNewsFilter.Add_SelectionChangeCommitted({
    if ($script:NewsFilterUpdating) { return }
    $i = $cmbNewsFilter.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:NewsFilterKeys.Count) { return }
    Set-NewsFilter $script:NewsFilterKeys[$i]
})
$btnNewsRead.Add_Click({
    $script:NewsBoldSince = [DateTime]::MaxValue
    Set-NewsSeen (Get-NewsNewest)
    $script:NewsBoldSince = $script:NewsSeenAt
    Refresh-NewsGrid
    Update-NewsBadge
})
$btnNewsRefresh.Add_Click({
    $script:NextNewsLoad = (Get-Date).AddMinutes((Get-NewsPollMinutes -Minutes ([int]$script:Config.NewsRefreshMinutes)))
    Start-NewsLoad
})
$dgvNews.Add_CellDoubleClick({
    param($sender, $e)
    if ($e.RowIndex -lt 0) { return }
    $n = $sender.Rows[$e.RowIndex].Tag
    if ($null -ne $n -and $n.Link) { Open-Link ([string]$n.Link) }
})
$dgvNews.Add_CellClick({
    param($sender, $e)
    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -ne $sender.Columns["Syms"].Index) { return }
    $n = $sender.Rows[$e.RowIndex].Tag
    if ($null -eq $n -or @($n.Syms).Count -eq 0) { return }
    # the ticker that moves (if any), else the first
    $pick = [string]@($n.Syms)[0]
    $cellTxt = [string]$sender.Rows[$e.RowIndex].Cells[$e.ColumnIndex].Value
    foreach ($s in @($n.Syms)) { if ($cellTxt -match ('(^|\s)' + [regex]::Escape([string]$s) + '\s\s')) { $pick = [string]$s } }
    Switch-ActiveTicker -NewTicker $pick -SkipResolve $true
    Set-TransientStatus ("{0} {1}" -f (Tr "Aktiver Ticker:"), $pick) 3
})
# v4.9.5: right-click menu (open, copy link, open ticker, mute source)
$script:NewsMenuItem = $null
$newsMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miNewsOpen = $newsMenu.Items.Add("Artikel öffnen")
$miNewsCopy = $newsMenu.Items.Add("Link kopieren")
$miNewsTicker = $newsMenu.Items.Add("Ticker öffnen")
[void]$newsMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miNewsMute = $newsMenu.Items.Add("Quelle ausblenden")
$miNewsOpen.Add_Click({ $n = $script:NewsMenuItem; if ($null -ne $n -and $n.Link) { Open-Link ([string]$n.Link) } })
$miNewsCopy.Add_Click({ $n = $script:NewsMenuItem; if ($null -ne $n -and $n.Link) { try { [System.Windows.Forms.Clipboard]::SetText([string]$n.Link); Set-TransientStatus (Tr "Link kopiert") 2 } catch { } } })
$miNewsTicker.Add_Click({ $n = $script:NewsMenuItem; if ($null -ne $n -and @($n.Syms).Count -gt 0) { Switch-ActiveTicker -NewTicker ([string]@($n.Syms)[0]) -SkipResolve $true } })
$miNewsMute.Add_Click({
    $n = $script:NewsMenuItem
    if ($null -eq $n -or -not $n.Publisher) { return }
    $pub = ([string]$n.Publisher).Trim()
    $script:Config.NewsMuted = @(@($script:Config.NewsMuted) + @($pub) | Where-Object { $_ } | Sort-Object -Unique)
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Set-TransientStatus ("{0} '{1}' - {2}" -f (Tr "Quelle ausgeblendet:"), $pub, (Tr "zurück in den Einstellungen")) 5
    Refresh-NewsGrid
    Update-NewsBadge
})
$dgvNews.Add_CellMouseDown({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right -or $e.RowIndex -lt 0) { return }
    $n = $sender.Rows[$e.RowIndex].Tag
    if ($null -eq $n) { return }
    $sender.ClearSelection()
    $sender.Rows[$e.RowIndex].Selected = $true
    $script:NewsMenuItem = $n
    $miNewsOpen.Enabled = [bool]$n.Link
    $miNewsCopy.Enabled = [bool]$n.Link
    $miNewsTicker.Enabled = (@($n.Syms).Count -gt 0)
    $miNewsTicker.Text = if (@($n.Syms).Count -gt 0) { "{0}: {1}" -f (Tr "Ticker öffnen"), @($n.Syms)[0] } else { Tr "Ticker öffnen" }
    $miNewsMute.Enabled = [bool]$n.Publisher
    $miNewsMute.Text = if ($n.Publisher) { "{0}: {1}" -f (Tr "Quelle ausblenden"), [string]$n.Publisher } else { Tr "Quelle ausblenden" }
    $newsMenu.Show($sender, $sender.PointToClient([System.Windows.Forms.Cursor]::Position))
})

$dgvNews.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $sender.SelectedRows.Count -gt 0) {
        $n = $sender.SelectedRows[0].Tag
        if ($null -ne $n -and $n.Link) { Open-Link ([string]$n.Link) }
        $e.Handled = $true
    }
})
Update-NewsFilterCombo
Refresh-NewsGrid

$lblAlTitle = New-Object System.Windows.Forms.Label
$lblAlTitle.Location = New-Object System.Drawing.Point((S 496), (S 8))
$lblAlTitle.Size = New-Object System.Drawing.Size((S 168), (S 20))
$lblAlTitle.Font = $fontUiBold
$lblAlTitle.ForeColor = $script:Pal.Accent
$lblAlTitle.Text = "Alarme (Doppelklick = Reset)"
$viewWatch.Controls.Add($lblAlTitle)

# v4.3: history of fired alerts
$btnAlertLog = New-Object System.Windows.Forms.Button
$btnAlertLog.Location = New-Object System.Drawing.Point((S 668), (S 5))
$btnAlertLog.Size = New-Object System.Drawing.Size((S 80), (S 24))
Style-FlatButton -Btn $btnAlertLog -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnAlertLog.Text = "Verlauf"
$viewWatch.Controls.Add($btnAlertLog)
Set-Tip $btnAlertLog "Ausgelöste Alarme mit Zeit, Wert und Push-Status" "ALERTLOG"

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
$cmbAlertCond.DropDownWidth = S 130
$cmbAlertCond.MaxDropDownItems = 18
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
$txtAlertNote.Size = New-Object System.Drawing.Size((S 96), (S 24))
$txtAlertNote.BackColor = $script:Pal.Input
$txtAlertNote.ForeColor = $script:Pal.Text
$txtAlertNote.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtAlertNote.Font = $fontMono
$txtAlertNote.MaxLength = 60
$viewWatch.Controls.Add($txtAlertNote)
Set-Tip $txtAlertNote "Notiz zum Alarm (optional, erscheint im Hinweis)"

# v4.3: expiry
$cmbAlertExp = New-Object System.Windows.Forms.ComboBox
$cmbAlertExp.Location = New-Object System.Drawing.Point((S 596), (S 66))
$cmbAlertExp.Size = New-Object System.Drawing.Size((S 68), (S 24))
$cmbAlertExp.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbAlertExp.BackColor = $script:Pal.Input
$cmbAlertExp.ForeColor = $script:Pal.Text
$cmbAlertExp.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbAlertExp.Font = $fontMono
$cmbAlertExp.DropDownWidth = S 100
$script:AlertExpiryChoices = Get-AlertExpiryChoices
foreach ($ek in $script:AlertExpiryChoices.Keys) { [void]$cmbAlertExp.Items.Add($ek) }
$cmbAlertExp.SelectedIndex = 0
$viewWatch.Controls.Add($cmbAlertExp)
Set-Tip $cmbAlertExp "Gültig bis: danach wird der Alarm nicht mehr geprüft" "EXPIRY"

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
$cmbDepot.Anchor       = $aT -bor $aR
$cmbWlGroup.Anchor     = $aT -bor $aL
$btnPrivacy.Anchor     = $aT -bor $aR
$dgvPortfolio.Anchor   = $anchorAll
$pnlPortBottom.Anchor  = $aB -bor $aL -bor $aR
$lblNachkaufOut.Anchor = $aT -bor $aL -bor $aR
$btnPortTx.Anchor   = $aT -bor $aR
$btnPortMore.Anchor = $aT -bor $aR
$btnPortHist.Anchor = $aT -bor $aR
$btnPortAna.Anchor  = $aT -bor $aR

# Watchlist view: list grows, alarm column keeps its width on the right
$dgvWatchlist.Anchor = $anchorAll
foreach ($ctl in @($lblAlTitle, $btnAlertLog, $txtAlertTicker, $cmbAlertCond, $txtAlertPrice, $btnAddAlert, $btnDelAlert, $txtAlertNote, $cmbAlertExp, $cmbAlertRearm)) { $ctl.Anchor = $aT -bor $aR }
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
    $old = (@("Chart", "Portfolio", "Watchlist", "News") | ForEach-Object { [bool]$script:ViewOn[$_] }) -join ","
    $script:ViewOn = $On
    $viewChart.Visible     = [bool]$On["Chart"]
    $viewPortfolio.Visible = [bool]$On["Portfolio"]
    $viewWatch.Visible     = [bool]$On["Watchlist"]
    $viewNews.Visible      = [bool]$On["News"]
    Update-TabHighlight
    Update-NewsBadge
    $new = (@("Chart", "Portfolio", "Watchlist", "News") | ForEach-Object { [bool]$script:ViewOn[$_] }) -join ","
    # a view that just appeared may have missed refreshes while hidden
    if ($new -ne $old -and $script:StartupDone -and $form.Visible) { Update-VisibleTabContent }
}

# v5.0: dividers of the Terminal layout (drag = chart height / list widths)
$script:SplitDrag = ""
$script:SplitArea = @{ X = 0; Y = 0; W = 1; H = 1 }
$splitChart = New-Object System.Windows.Forms.Panel
$splitChart.Cursor = [System.Windows.Forms.Cursors]::HSplit
$splitChart.Visible = $false
$splitChart.Tag = "Chart"
$splitLists = New-Object System.Windows.Forms.Panel
$splitLists.Cursor = [System.Windows.Forms.Cursors]::VSplit
$splitLists.Visible = $false
$splitLists.Tag = "Lists"
foreach ($sp in @($splitChart, $splitLists)) {
    $sp.BackColor = $script:Pal.BodyBg
    $form.Controls.Add($sp)
    $sp.Add_MouseEnter({ param($sender, $e) $sender.BackColor = $script:Pal.Border })
    $sp.Add_MouseLeave({ param($sender, $e) if (-not $script:SplitDrag) { $sender.BackColor = $script:Pal.BodyBg } })
    $sp.Add_MouseDown({ param($sender, $e) if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:SplitDrag = [string]$sender.Tag; $sender.Capture = $true } })
    $sp.Add_MouseMove({
        param($sender, $e)
        if (-not $script:SplitDrag) { return }
        $pt = $form.PointToClient([System.Windows.Forms.Cursor]::Position)
        $a = $script:SplitArea
        if ($script:SplitDrag -eq "Chart") {
            $pct = Get-DragPct -Pos $pt.Y -Start $a.Y -Length $a.H -Min 25 -Max 80
            if ($pct -ne [int]$script:Config.TerminalChartPct) { $script:Config.TerminalChartPct = $pct; Update-MainLayout }
        } else {
            $pct = Get-DragPct -Pos $pt.X -Start $a.X -Length $a.W -Min 25 -Max 75
            if ($pct -ne [int]$script:Config.TerminalSplitPct) { $script:Config.TerminalSplitPct = $pct; Update-MainLayout }
        }
    })
    $sp.Add_MouseUp({
        param($sender, $e)
        if (-not $script:SplitDrag) { return }
        $script:SplitDrag = ""
        $sender.Capture = $false
        $sender.BackColor = $script:Pal.BodyBg
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
    })
    $sp.Add_DoubleClick({
        # double-click = back to the default sizes
        param($sender, $e)
        if ([string]$sender.Tag -eq "Chart") { $script:Config.TerminalChartPct = 55 } else { $script:Config.TerminalSplitPct = 50 }
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        Update-MainLayout
    })
}
Set-Tip $splitChart "Ziehen = Chart-Höhe ändern, Doppelklick = Standard"
Set-Tip $splitLists "Ziehen = Breite von Watchlist und Portfolio ändern, Doppelklick = Standard"

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
    # v4.9: the command button gets narrower before the status text vanishes
    $cmdX = S ($script:NavX + 200)
    $cmdW = [math]::Max((S 110), [math]::Min((S 170), $pnlNav.Width - $cmdX - (S 220)))
    $btnCmd.SetBounds($cmdX, (S 3), $cmdW, (S 24))
    # v4.9: short label when the button is narrow (the tooltip names Ctrl+K)
    $cmdTxt = if ($cmdW -lt (S 150)) { "> Befehl" } else { "> Befehl     Strg+K" }
    $cmdTxt = Tr $cmdTxt
    if ($btnCmd.Text -ne $cmdTxt) { $btnCmd.Text = $cmdTxt }
    $stX = $cmdX + $cmdW + (S 8)
    $pnlHealth.SetBounds($stX, (S 10), (S 12), (S 12))
    $stX += S 16
    $lblStatus.SetBounds($stX, (S 6), [math]::Max(0, $pnlNav.Width - $stX), (S 20))

    $vx = S 12
    $vy = S 92
    $vw = $W - (S 24)
    $vh = $H - (S 92) - (S 12)
    if ([string]$script:Config.Layout -eq "Terminal") {
        # v4.0: chart on top, watchlist / portfolio below (side by side when wide enough)
        $r = Get-TerminalLayoutRects -X $vx -Y $vy -W $vw -H $vh -ChartPct ([double]$script:Config.TerminalChartPct) `
            -ShowWatch ([bool]$script:Config.TerminalShowWatch) -ShowPortfolio ([bool]$script:Config.TerminalShowPortfolio) `
            -ActiveBottom ([string]$script:Config.TerminalBottom) -PanelMinW (S 756) -Gap (S $script:UiSpec.Gap) -MinBottomH (S 300) -MinChartH (S 160) -Full ([string]$script:TerminalFull) `
            -SplitPct ([double]$script:Config.TerminalSplitPct)
        $on = @{}
        foreach ($pair in @(@("Chart", $viewChart), @("Watchlist", $viewWatch), @("Portfolio", $viewPortfolio), @("News", $viewNews))) {
            $rect = $r.($pair[0])
            if ($null -ne $rect) {
                $pair[1].SetBounds([int]$rect[0], [int]$rect[1], [int]$rect[2], [int]$rect[3])
                $on[$pair[0]] = $true
            }
        }
        Set-ViewVisibility $on
        # v5.0: draggable dividers in the gaps (chart / lists, watchlist / portfolio)
        $bottomR = @($r.Watchlist, $r.Portfolio, $r.News) | Where-Object { $null -ne $_ } | Select-Object -First 1
        if ($null -ne $r.Chart -and $null -ne $bottomR) {
            $splitChart.SetBounds($vx, ([int]$r.Chart[1] + [int]$r.Chart[3]), $vw, ([int]$bottomR[1] - [int]$r.Chart[1] - [int]$r.Chart[3]))
            $splitChart.Visible = $true; $splitChart.BringToFront()
        } else { $splitChart.Visible = $false }
        if ([bool]$r.SideBySide) {
            $splitLists.SetBounds(([int]$r.Watchlist[0] + [int]$r.Watchlist[2]), [int]$r.Watchlist[1], ([int]$r.Portfolio[0] - [int]$r.Watchlist[0] - [int]$r.Watchlist[2]), [int]$r.Watchlist[3])
            $splitLists.Visible = $true; $splitLists.BringToFront()
        } else { $splitLists.Visible = $false }
        $script:SplitArea = @{ X = $vx; Y = $vy; W = $vw; H = $vh }
    } else {
        foreach ($v in @($viewChart, $viewPortfolio, $viewWatch, $viewNews)) { $v.SetBounds($vx, $vy, $vw, $vh) }
        Set-ViewVisibility @{ ([string]$script:Config.ActiveTab) = $true }
        $splitChart.Visible = $false; $splitLists.Visible = $false
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
    Update-UpDownColors
    $script:Pal = Get-ThemeColors
    $script:UiSpec = Get-UiSpec -Style ([string]$script:Config.UiStyle) -Density ([string]$script:Config.RowDensity)
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
    $splitChart.BackColor = $p.BodyBg; $splitLists.BackColor = $p.BodyBg
    $pnlHover.BackColor = $p.HeaderBg
    $pnlHealth.BackColor = $p.BodyBg
    $pnlHealth.Invalidate()
    Style-FlatButton -Btn $btnRefreshNow -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $cmbRefresh.BackColor = $p.Input
    $cmbRefresh.ForeColor = $p.Muted
    Style-FlatButton -Btn $btnThemeCycle -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $btnThemeCycle.Text = $script:Config.Theme
    Style-FlatButton -Btn $btnSettings -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    Style-FlatButton -Btn $btnCmd -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
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
    $cmbDepot.BackColor = $p.Input; $cmbDepot.ForeColor = $p.Accent
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
    Style-FlatButton -Btn $btnPortMore -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    Style-FlatButton -Btn $btnPortHist -BgColor $p.Input -FgColor $p.Muted  -BorderColor $p.Border
    Style-FlatButton -Btn $btnPortAna  -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $lblNachkaufOut.ForeColor = $p.Text
    $btnPrivacy.BackColor = $p.Input
    $btnPrivacy.FlatAppearance.BorderColor = $p.Border
    if ($script:StartupDone) { Update-PrivacyIndicator }
    $pnlPortHint.BackColor = $p.Card
    $lblPortHint.ForeColor = $p.Muted
    Style-FlatButton -Btn $btnHintTx  -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    Style-FlatButton -Btn $btnHintImp -BgColor $p.Input -FgColor $p.Muted  -BorderColor $p.Border

    $viewWatch.BackColor = $p.Card
    $lblWlTitle.ForeColor = $p.Accent
    $lblAlTitle.ForeColor = $p.Accent
    Style-FlatButton -Btn $btnWlAddActive -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $txtWlSearch.BackColor = $p.Input; $txtWlSearch.ForeColor = $p.Text
    Style-FlatButton -Btn $btnWlAddSearch -BgColor $p.Input -FgColor $colGreen -BorderColor $p.Border
    Style-FlatButton -Btn $btnWlRemove    -BgColor $p.Input -FgColor $colRed   -BorderColor $p.Border
    $lstWlSearchDropdown.BackColor = $p.HeaderBg; $lstWlSearchDropdown.ForeColor = $p.Text
    $cmbWlGroup.BackColor = $p.Input; $cmbWlGroup.ForeColor = $p.Accent
    Style-DataGrid -Grid $dgvWatchlist

    $txtAlertTicker.BackColor = $p.Input; $txtAlertTicker.ForeColor = $p.Text
    $cmbAlertCond.BackColor   = $p.Input; $cmbAlertCond.ForeColor   = $p.Text
    $txtAlertPrice.BackColor  = $p.Input; $txtAlertPrice.ForeColor  = $p.Text
    $txtAlertNote.BackColor   = $p.Input; $txtAlertNote.ForeColor   = $p.Text
    $cmbAlertRearm.BackColor  = $p.Input; $cmbAlertRearm.ForeColor  = $p.Text
    $cmbAlertExp.BackColor    = $p.Input; $cmbAlertExp.ForeColor    = $p.Text
    Style-FlatButton -Btn $btnAddAlert -BgColor $p.Input -FgColor $colGreen -BorderColor $p.Border
    Style-FlatButton -Btn $btnAlertLog -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    Style-FlatButton -Btn $btnDelAlert -BgColor $p.Input -FgColor $colRed   -BorderColor $p.Border
    $lstAlerts.BackColor = $p.Input; $lstAlerts.ForeColor = $p.Text

    # v4.9: news tab
    $viewNews.BackColor = $p.Card
    $lblNewsTitle.ForeColor = $p.Accent
    $lblNewsInfo.ForeColor = $p.Muted
    $cmbNewsFilter.BackColor = $p.Input; $cmbNewsFilter.ForeColor = $p.Text
    Style-FlatButton -Btn $btnNewsRead    -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    Style-FlatButton -Btn $btnNewsRefresh -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    Style-DataGrid -Grid $dgvNews
    $dgvNews.ShowCellToolTips = $true
    if ($viewNews.Visible) { Refresh-NewsGrid }

    Set-ActiveTab -TabName $script:Config.ActiveTab
    Update-AllUiViews
    $pnlHeader.Invalidate()
    $pnlTickerBox.Invalidate()
    # v5.2: icons, gaps and card corners follow the style
    Apply-Icons
    Update-MainLayout
    foreach ($v in @($viewWatch, $viewPortfolio, $viewNews, $viewChart)) { $v.Invalidate() }
    foreach ($b in @($script:RoundBtns)) { if ($null -ne $b -and -not $b.IsDisposed) { $b.Invalidate() } }
    $script:ChartSignature = ""
    $pnlChartCanvas.Invalidate()
}

# v5.2: icon font glyphs on buttons and menus (text fallback without the font)
$script:GlyphCache = @{}
function Get-GlyphImage {
    param([int]$Code, [System.Drawing.Color]$Color)
    if (-not $script:IconFont) { return $null }
    $key = "{0:X}|{1}" -f $Code, $Color.ToArgb()
    if ($script:GlyphCache.ContainsKey($key)) { return $script:GlyphCache[$key] }
    $sz = S 16
    $bmp = New-Object System.Drawing.Bitmap($sz, $sz, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([System.Drawing.Color]::Transparent)
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $f = New-Object System.Drawing.Font($script:IconFont, [float]($sz * 0.8), [System.Drawing.GraphicsUnit]::Pixel)
        $br = New-Object System.Drawing.SolidBrush($Color)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center; $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $g.DrawString([string][char]$Code, $f, $br, (New-Object System.Drawing.RectangleF(0, 0, [float]$sz, [float]$sz)), $sf)
        $br.Dispose(); $f.Dispose(); $sf.Dispose()
    } finally { $g.Dispose() }
    $script:GlyphCache[$key] = $bmp
    return $bmp
}

function Apply-Icons {
    $on = [bool]$script:Config.UseIcons -and [bool]$script:IconFont
    if ($null -eq $script:IconBtnFont -and $script:IconFont) { $script:IconBtnFont = New-Object System.Drawing.Font($script:IconFont, 10) }
    $btns = @(
        @($btnSettings, 0xE713, ([string][char]0x2699)),
        @($btnRefreshNow, 0xE72C, ([string][char]0x21BB)),
        @($btnNewsRefresh, 0xE72C, ([string][char]0x21BB)),
        @($btnTray, 0xE921, "_"),
        @($btnPortMore, 0xE70D, ([string][char]0x25BE)),
        @($btnAddAlert, 0xE710, "+"),
        @($btnPin, 0xE718, "Pin"),
        @($btnFullscreen, 0xE740, (Tr "Vollbild"))
    )
    foreach ($bd in $btns) {
        $b = $bd[0]
        if ($null -eq $b) { continue }
        if ($on) { $b.Font = $script:IconBtnFont; $b.Text = [string][char][int]$bd[1] }
        else { $b.Font = $fontUiBold; $b.Text = [string]$bd[2] }
    }
    Update-ChartControlsLayout
    $col = $script:Pal.Accent
    $menuIcons = @(
        @($miShow, 0xE8A7), @($miLayout, 0xE8A9), @($miRefresh, 0xE72C), @($miPrivacy, 0xE890), @($miExit, 0xE7E8),
        @($cmiCopyPrice, 0xE8C8), @($cmiAddWatch, 0xE710), @($cmiExportCsv, 0xE78C), @($cmiFullscreen, 0xE740), @($cmiTa, 0xE9D9),
        @($cmiCompare, 0xEB11), @($cmiAlertHere, 0xEA8F), @($cmiZoomReset, 0xE72C),
        @($miRowChart, 0xE9D2), @($miRowAlert, 0xEA8F), @($miRowBuy, 0xE719), @($miRowNews, 0xE8A5), @($miRowCmp, 0xEB11),
        @($miRowDes, 0xE946), @($miRowTa, 0xE9D9), @($miRowRemove, 0xE74D), @($miRowGroup, 0xE8EC)
    )
    foreach ($mi in $menuIcons) {
        if ($null -eq $mi[0]) { continue }
        $mi[0].Image = if ($on) { Get-GlyphImage -Code ([int]$mi[1]) -Color $col } else { $null }
    }
    foreach ($m in @($trayMenu, $chartContextMenu, $rowMenu)) { if ($null -ne $m) { $m.ImageScalingSize = New-Object System.Drawing.Size((S 16), (S 16)) } }
}




function Set-ActiveCurrency {
    # v5.1: "AUTO" = prices in the ticker's own currency, depot stays in the
    # base currency; a fixed currency switches Auto off and becomes the base
    param([string]$NewCurrency)
    $c = $NewCurrency.Trim().ToUpper()
    if ($c -like "AUTO*") {
        $script:Config.AutoCurrency = $true
        $btnCurrency.Text = "Auto $script:DropArrow"
        Set-TransientStatus ("Kurse in der Währung des Tickers, Depot in {0}" -f $script:Config.Currency) 4
    } else {
        if ($c -notin @(Get-DisplayCurrencies)) { return }
        $script:Config.AutoCurrency = $false
        $script:Config.Currency = $c
        $btnCurrency.Text = "$c $script:DropArrow"
    }
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

    # v4.9.5: recently opened tickers first (marked), then watchlist + depot
    $recentSet = New-Object System.Collections.Generic.HashSet[string]
    $localSymbols = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($script:Config.RecentTickers)) {
        if (-not $r) { continue }
        $ru = ([string]$r).ToUpper()
        [void]$recentSet.Add($ru)
        if (-not $localSymbols.Contains($ru)) { [void]$localSymbols.Add($ru) }
    }
    foreach ($w in $script:Config.Watchlist) { if (-not $localSymbols.Contains($w.ToUpper())) { [void]$localSymbols.Add($w.ToUpper()) } }
    foreach ($p in $script:Portfolio.Keys) {
        if (-not $localSymbols.Contains($p.ToUpper())) { [void]$localSymbols.Add($p.ToUpper()) }
    }

    foreach ($sym in $localSymbols) {
        $q = if ($script:QuoteStore.ContainsKey($sym)) { $script:QuoteStore[$sym] } else { $null }
        $prN = $script:Profiles[$sym]
        $nameStr = if ($q -and $q.LongName) { $q.LongName } elseif ($null -ne $prN -and $prN.Name) { [string]$prN.Name } else { $sym }
        if ($fUpper.Length -gt 0 -and $sym -notlike "*$fUpper*" -and $nameStr.ToUpper() -notlike "*$fUpper*") {
            continue
        }
        [void]$seen.Add($sym)
        if ($q) {
            $pcSym = Get-PriceCurrency $sym
            $pConv = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $pcSym
            $sign  = if ($q.ChangePct -ge 0) { "+" } else { "" }
            $disp  = "{0,-9} | {1,8:N2} {2} ({3}{4:N1}%) | {5}" -f $sym, $pConv, $pcSym, $sign, $q.ChangePct, $nameStr
        } else {
            $disp  = "{0,-9} | {1}" -f $sym, $nameStr
        }
        if ($recentSet.Contains($sym) -and $fUpper.Length -eq 0) { $disp = [string][char]0x21BA + " " + $disp } else { $disp = "  " + $disp }
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
    if ($TabName -notin @("Chart", "Portfolio", "Watchlist", "News")) { $TabName = "Chart" }
    # v4.9.5: another tab while a list is shown as a full page: that one full page, Chart = split view
    if ($script:TerminalFull -and $TabName -ne $script:TerminalFull) { $script:TerminalFull = if ($TabName -eq "Chart") { "" } else { $TabName } }
    $script:Config.ActiveTab = $TabName
    if ($script:HoverReady) { Hide-HoverCard }
    # Terminal: the Portfolio / Watch / News tabs pick the lower panel
    if ($TabName -in @("Portfolio", "Watchlist", "News")) { $script:Config.TerminalBottom = $TabName }
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

# v4.9.5: Terminal layout - a list as a full page. Clicking the tab of a list
# that is already shown (or Shift+F2/F3/F4, FULL) fills the window with it;
# Chart, the same tab again or Esc bring the split view back.
$script:TerminalFull = ""
function Set-TerminalFull {
    param([string]$Panel)
    if ($Panel -and $Panel -notin @("Portfolio", "Watchlist", "News")) { $Panel = "" }
    if ([string]$script:Config.Layout -ne "Terminal") {
        # Standard already shows one tab per page
        $script:TerminalFull = ""
        if ($Panel) { Set-ActiveTab -TabName $Panel }
        return
    }
    $script:TerminalFull = $Panel
    $script:Config.TerminalFull = $Panel
    if ($Panel) {
        $script:Config.TerminalBottom = $Panel
        $script:Config.ActiveTab = $Panel
        Set-TransientStatus ("{0}: {1} - {2}" -f (Tr "Ganze Seite"), (Tr ([string]$tabButtons[$Panel].Text)), (Tr "Tab nochmal klicken, F1 oder Esc = zurück")) 5
    }
    Update-MainLayout
    if ($form.Visible -and $script:StartupDone) { Update-VisibleTabContent }
}

function Invoke-TabClick {
    # tab button / F1-F4: in the Terminal layout a second click on a shown list = full page
    param([string]$TabName, [bool]$ForceFull = $false)
    if ([string]$script:Config.Layout -eq "Terminal" -and -not [bool]$script:Config.CompactMode) {
        if ($TabName -eq "Chart") {
            if ($script:TerminalFull) { Set-TerminalFull "" ; return }
        } elseif ($script:TerminalFull -eq $TabName) {
            Set-TerminalFull ""; return
        } elseif ($script:TerminalFull -or $ForceFull -or [bool]$script:ViewOn[$TabName]) {
            Set-TerminalFull $TabName; return
        }
    } elseif ($ForceFull -and $TabName -ne "Chart") {
        Set-ActiveTab -TabName $TabName; return
    }
    Set-ActiveTab -TabName $TabName
}

function Update-VisibleTabContent {
    if ($viewPortfolio.Visible) {
        Refresh-PortfolioGrid
        Update-NachkaufSimulation
    }
    if ($viewWatch.Visible) { Refresh-WatchlistAndAlerts }
    if ($viewNews.Visible) {
        Update-NewsFilterCombo
        Refresh-NewsGrid -IfChanged
        # the first look at the tab loads the feed if it is old
        if (-not $script:NewsLoading -and ((Get-Date) - $script:NewsLoadedAt).TotalMinutes -gt [int]$script:Config.NewsRefreshMinutes) {
            $script:NextNewsLoad = Get-Date
        }
    }
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
    $script:TerminalFull = ""
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
        # v4.8: what the Compact / Ticker bar shows
        $cs = @(([string]$script:Config.CompactShow) -split ',' | ForEach-Object { $_.Trim() })
        $picCompactSpark.Visible = ($cs -contains "Spark")
        $lblDayAbs.Visible = ($cs -contains "DayAbs")
        $lblExtQuote.Visible = ($cs -contains "Ext")
        $csM = @(([string]$script:Config.CompactShow) -split ',' | ForEach-Object { $_.Trim() })
        $lblMarketStatus.Visible = (-not $isTicker) -and (($csM -contains "Market") -or ($csM -contains "Depot"))
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
        $lblDayAbs.Visible = $true
        $lblExtQuote.Visible = $true
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
    # v4.8: never rebuild the rows while a cell is being edited
    if ($dgvPortfolio.IsCurrentCellInEditMode) { return }
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
        $contrib = [double]::NaN
        if ($script:QuoteStore.ContainsKey($sym)) {
            $q = $script:QuoteStore[$sym]
            $mktConv = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $curr
            $dayPct  = $q.ChangePct
            if ($q.PrevClose -gt 0) {
                $prevConv = Convert-CurrencyValue -Amount $q.PrevClose -FromCurrency $q.Currency -ToCurrency $curr
                $contrib  = $p.Shares * ($mktConv - $prevConv)
                $totDay  += $contrib
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
            Contrib = $contrib
        })
    }

    $pfMap = @{ "Ticker" = "Ticker"; "Shares" = "Shares"; "Avg" = "Avg"; "Price" = "Price"; "Val" = "Value"; "Weight" = "Value"; "Pnl" = "PnlPct"; "Day" = "DayPct"; "Contrib" = "ContribSort" }
    # v4.9.5: missing contributions sort last
    foreach ($r in $rows) { $r | Add-Member -NotePropertyName ContribSort -NotePropertyValue $(if ([double]::IsNaN([double]$r.Contrib)) { [double]::MinValue } else { [double]$r.Contrib }) -Force }
    $priv = [bool]$script:Config.PrivacyMode
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
        # v4.9.5: privacy mode hides amounts and shares, keeps percentages
        $contribTxt = if ([double]::IsNaN([double]$r.Contrib)) { "-" } else { "{0:+#,##0.00;-#,##0.00;0.00}" -f $r.Contrib }
        $idx = $dgvPortfolio.Rows.Add(
            $r.Ticker,
            "",
            (Protect-Amount ("{0:N2}" -f $r.Shares) $priv),
            ("{0:N2}" -f $r.Avg),
            ("{0:N2}" -f $r.Price),
            (Protect-Amount ("{0:N2} {1}" -f $r.Value, $curr) $priv),
            ("{0:N1}%" -f $weight),
            $(if ($priv) { "{0}{1:N1}%" -f $sign, $r.PnlPct } else { "{0}{1:N2} ({0}{2:N1}%)" -f $sign, $r.PnlAbs, $r.PnlPct }),
            ("{0}{1:N2}%" -f $dSign, $r.DayPct),
            (Protect-Amount $contribTxt $priv)
        )
        if (-not [double]::IsNaN([double]$r.Contrib)) { $dgvPortfolio.Rows[$idx].Cells[9].Style.ForeColor = if ($r.Contrib -ge 0) { $colGreen } else { $colRed } }
        $dgvPortfolio.Rows[$idx].Cells[7].Style.ForeColor = if ($r.PnlAbs -ge 0) { $colGreen } else { $colRed }
        $dgvPortfolio.Rows[$idx].Cells[8].Style.ForeColor = if ($r.DayPct -ge 0) { $colGreen } else { $colRed }
        if ([bool]$script:Config.ShowArrows) { $dgvPortfolio.Rows[$idx].Cells[8].Value = (Get-ArrowPrefix ([double]$r.DayPct)) + [string]$dgvPortfolio.Rows[$idx].Cells[8].Value }
        Set-PriceFlash -Cell $dgvPortfolio.Rows[$idx].Cells["Price"] -Key ("P|" + $r.Ticker) -Price ([double]$r.Price)
        $eb = Get-TickerEarningsBadge $r.Ticker
        if ($null -ne $eb) {
            $dgvPortfolio.Rows[$idx].Cells[0].Style.ForeColor = $script:Pal.Warn
            $dgvPortfolio.Rows[$idx].Cells[0].ToolTipText = "Quartalszahlen {0} ({1})" -f $eb.Text, (Format-IsoDateDe $eb.Date)
        }
    }
    Restore-GridState -Grid $dgvPortfolio -State $gridState
    } finally {
        $script:SuppressGridSelection = $false
    }
    Update-PortfolioHint

    $totPnl = $totVal - $totCost
    $totPct = if ($totCost -gt 0) { ($totPnl / $totCost) * 100.0 } else { 0.0 }
    $tSign  = if ($totPnl -ge 0) { "+" } else { "" }
    $lblPortSummary.ForeColor = if ($totPnl -ge 0) { $colGreen } else { $colRed }
    $dPct  = if ($totPrev -gt 0) { ($totDay / $totPrev) * 100.0 } else { 0.0 }
    $dSign = if ($totDay -ge 0) { "+" } else { "" }
    $realYear = Get-RealizedTotal -Year (Get-Date).Year
    $realAll  = Get-RealizedTotal
    # v4.9.5: realized this year incl. dividends, with the dividend part
    $divYear  = Get-RealizedTotal -Year (Get-Date).Year -Type "Dividende"
    $hasYear  = @($script:Transactions | Where-Object { ([string]$_.Date).StartsWith([string](Get-Date).Year) -and [double]$_.Realized -ne 0 }).Count -gt 0
    $realTxt  = ""
    if ($hasYear -and -not $priv) {
        $realTxt = " | {0}: {1:+0.00;-0.00} real." -f (Get-Date).Year, $realYear
        if ([math]::Abs($divYear) -gt 0.004) { $realTxt += " (Div. {0:+0.00;-0.00})" -f $divYear }
    }
    if ($priv) {
        $lblPortSummary.Text = ("Depot: {0} | G/V: {1}{2:N2}% | Heute: {3}{4:N2}%  | {5}" -f (Protect-Amount "" $true), $tSign, $totPct, $dSign, $dPct, (Tr "Privat (F9)"))
    } else {
        # v5.0: cash account
        $ciP = Get-CashInfo -Currency $curr
        $cashTxt = if ($null -ne $ciP) { " | Cash: {0:N2} (Gesamt {1:N2})" -f $ciP.Display, ($totVal + $ciP.Display) } else { "" }
        $lblPortSummary.Text = ("Depot: {0:N2} {1}{9} | G/V: {2}{3:N2} ({2}{4:N2}%) | Heute: {5}{6:N2} ({5}{7:N2}%){8}" -f $totVal, $curr, $tSign, $totPnl, $totPct, $dSign, $totDay, $dPct, $realTxt, $cashTxt)
    }
    if ($script:Portfolio.Count -eq 0) {
        # Empty state (v3.0)
        $lblPortSummary.ForeColor = $script:Pal.Muted
        $lblPortSummary.Text = "Noch keine Positionen - unten Ticker, Stück und EK eintragen oder 'Transaktion...' buchen."
    }
    if ($priv) { Set-DynTip $lblPortSummary (Tr "Privat-Modus: Beträge und Stückzahlen ausgeblendet. F9 = wieder zeigen."); return }
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
    # v5.0: only the chosen group ("" = all)
    $syms = @(Get-WatchGroupSymbols -Watchlist @($script:Config.Watchlist) -Groups @($script:Config.WatchGroups) -Group ([string]$script:Config.WatchGroup))
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
    # v5.0: inside a group the row number is a position in the group - use the
    # position of the ticker shown there in the full watchlist
    if ([string]$script:Config.WatchGroup) {
        $vis = @(Get-WatchlistOrder)
        if ($vis.Count -gt 0) { $NewIndex = $list.IndexOf([string]$vis[[math]::Max(0, [math]::Min($vis.Count - 1, $NewIndex))]) }
    }
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
    Update-WatchGroupCombo
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
            $curr = Get-PriceCurrency $uSym   # v5.1: own currency per row with Auto
            $pConv = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $curr
            $sign  = if ($q.ChangePct -ge 0) { "+" } else { "" }
            $rsiStr = if (-not [double]::IsNaN($q.Rsi14)) { "{0:N1}" -f $q.Rsi14 } else { "-" }
            $distStr = if ($q.High52 -gt 0) { "{0:N1}%" -f ((($q.Price - $q.High52) / $q.High52) * 100.0) } else { "-" }
            $extStr = if ($q.ExtPrice -gt 0) { "{0}{1:N2}%" -f $(if ($q.ExtPct -ge 0) { "+" } else { "" }), $q.ExtPct } else { "-" }
            $ms = Get-MarketState -Tp $q.Tp -NowSec $nowSec
            $mStr = if ($null -ne $ms) { $ms.Short } else { "-" }
            # v4.9.5: analyst mean target vs. price + consensus
            $ev = $script:Events[$uSym]
            $tgtStr = "-"; $tgtTip = ""; $up = [double]::NaN
            if ($null -ne $ev) {
                $up = Get-TargetUpside -Target ([double]$ev.TargetMean) -Price ([double]$q.Price)
                $lab = Get-ConsensusLabel ([string]$ev.RecKey)
                if (-not [double]::IsNaN($up)) { $tgtStr = ("{0:+0;-0}% {1}" -f $up, $lab).Trim() } elseif ($lab) { $tgtStr = $lab }
                if ($tgtStr -ne "-") { $tgtTip = Get-AnalystText -Ev $ev -Price ([double]$q.Price) -Currency ([string]$q.Currency) }
            }
            $idx = $dgvWatchlist.Rows.Add(
                $uSym,
                "",
                ("{0:N2} {1}" -f $pConv, $curr),
                ("{0}{1:N2}%" -f $sign, $q.ChangePct),
                $extStr,
                $rsiStr,
                $distStr,
                $mStr,
                $tgtStr
            )
            $row = $dgvWatchlist.Rows[$idx]
            if (-not [double]::IsNaN($up)) { $row.Cells["Target"].Style.ForeColor = if ($up -ge 0) { $colGreen } else { $colRed } }
            if ($tgtTip) { $row.Cells["Target"].ToolTipText = $tgtTip }
            if ($q.High52 -gt 0 -and $q.Low52 -gt 0) { $row.Cells["Dist"].ToolTipText = "52 Wochen: {0:N2} - {1:N2} {2}`r`nAbstand zum Hoch: {3}" -f $q.Low52, $q.High52, $q.Currency, $distStr }
            $eb = Get-TickerEarningsBadge $uSym
            if ($null -ne $eb) {
                $row.Cells[0].Style.ForeColor = $script:Pal.Warn
                $row.Cells[0].ToolTipText = "Quartalszahlen {0} ({1})" -f $eb.Text, (Format-IsoDateDe $eb.Date)
            }
            $row.Cells["Day"].Style.ForeColor = if ($q.ChangePct -ge 0) { $colGreen } else { $colRed }
            if ([bool]$script:Config.ShowArrows) { $row.Cells["Day"].Value = (Get-ArrowPrefix ([double]$q.ChangePct)) + [string]$row.Cells["Day"].Value }
            if (-not [bool]$q.FromCache) { Set-PriceFlash -Cell $row.Cells["Price"] -Key ("W|" + $uSym) -Price ([double]$q.Price) }
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
            [void]$dgvWatchlist.Rows.Add($uSym, "", "...", "-", "-", "-", "-", "-", "-")
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



function Get-PortfolioDayTotals {
    # Value and day change of the whole portfolio in $Currency from live
    # quotes; Ok = $false while a position has no live quote yet
    param([string]$Currency)
    $res = @{ Ok = $false; Value = 0.0; Prev = 0.0; DayPct = [double]::NaN }
    foreach ($k in @($script:Portfolio.Keys)) {
        $pf = $script:Portfolio[$k]
        $sh = [double]$pf.Shares
        if ($sh -le 0) { continue }
        $q = $script:QuoteStore[([string]$k).ToUpper()]
        if ($null -eq $q -or [bool]$q.FromCache -or [double]$q.Price -le 0) { return $res }
        $res.Value += $sh * (Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $Currency)
        $pc = if ([double]$q.PrevClose -gt 0) { [double]$q.PrevClose } else { [double]$q.Price }
        $res.Prev += $sh * (Convert-CurrencyValue -Amount $pc -FromCurrency ([string]$q.Currency) -ToCurrency $Currency)
    }
    if ($res.Prev -gt 0) { $res.DayPct = ($res.Value / $res.Prev - 1.0) * 100.0 }
    $res.Ok = ($res.Value -gt 0)
    return $res
}

function Get-AlertState {
    # Current value of what an alert watches + whether its condition is met
    # (v4.3: the check itself is Get-AlertEvaluation in Core). Ok = $false
    # when there is no live data (yet).
    param($Alert)
    $none = @{ Ok = $false; Value = [double]::NaN; Met = $false; Text = ""; Peak = [double]::NaN }
    $kind = Get-AlertKind ([string]$Alert.Condition)
    $ctx = @{ RsiPeriod = [double]$script:Config.RsiPeriod; SmaPeriod = [double]$script:Config.SmaFastPeriod }
    if (Test-PortfolioAlertKind $kind) {
        $pt = Get-PortfolioDayTotals -Currency ([string]$Alert.Currency)
        if (-not $pt.Ok) { return $none }
        $ctx.PfValue = $pt.Value
        $ctx.PfDayPct = $pt.DayPct
        return (Get-AlertEvaluation -Alert $Alert -Ctx $ctx)
    }
    if (-not $script:QuoteStore.ContainsKey($Alert.Ticker)) { return $none }
    $q = $script:QuoteStore[$Alert.Ticker]
    # v4.0: never fire on a cached quote from the last session
    if ([bool]$q.FromCache) { return $none }
    $ctx.QuotePrice = [double]$q.Price
    $ctx.ChangePct = [double]$q.ChangePct
    $ctx.Rsi = [double]$q.Rsi14
    $ctx.Sma = [double]$q.SmaFastH
    $ctx.High52 = [double]$q.High52
    $ctx.Low52 = [double]$q.Low52
    $ctx.RelVol = if ($null -ne $q.RelVol) { [double]$q.RelVol } else { [double]::NaN }
    $cur = [string]$Alert.Currency
    $ctx.Price = if ($cur -match '^[A-Z]{3}$') { Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $cur } else { [double]$q.Price }
    if ($kind -eq "EKPCT" -and $script:Portfolio.ContainsKey($Alert.Ticker)) {
        $pf = $script:Portfolio[$Alert.Ticker]
        $ctx.AvgCost = Convert-CurrencyValue -Amount ([double]$pf.AvgPrice) -FromCurrency ([string]$pf.Currency) -ToCurrency $cur
    }
    return (Get-AlertEvaluation -Alert $Alert -Ctx $ctx)
}


function Format-AlertLine {
    param($Alert)
    $kind = Get-AlertKind $Alert.Condition
    $snz = Test-AlertSnoozed -Alert $Alert
    $flag = if (Test-AlertExpired -Alert $Alert) { "[EXP]" } elseif ($snz) { "[ZZZ]" } elseif ($Alert.Triggered) { "[HIT]" } else { "[ACT]" }
    $t = [double]$Alert.TargetPrice
    $body = switch ($kind) {
        "PCT"    { "{0} {1:N2}%" -f $Alert.Condition, $t }
        "RSI"    { "{0} {1:N0}" -f $Alert.Condition, $t }
        "SMA"    { "{0}{1}" -f $Alert.Condition, $script:Config.SmaFastPeriod }
        "TRAIL"  { $pk = [double]$Alert.Peak; if ($pk -gt 0) { "Trail {0:N1}% (Stopp {1:N2})" -f $t, ($pk * (1.0 - $t / 100.0)) } else { "Trail {0:N1}%" -f $t } }
        "EKPCT"  { "{0} {1:N1}%" -f $Alert.Condition, $t }
        "HIGH52" { if ($t -gt 0) { "52W-Hoch -{0:N1}%" -f $t } else { "52W-Hoch" } }
        "LOW52"  { if ($t -gt 0) { "52W-Tief +{0:N1}%" -f $t } else { "52W-Tief" } }
        "VOL"    { "Vol >= {0:N1}x" -f $t }
        "PFVAL"  { "{0} {1:N0} {2}" -f $Alert.Condition, $t, $Alert.Currency }
        "PFPCT"  { "{0} {1:N2}%" -f $Alert.Condition, $t }
        default  { "{0} {1:N2} {2}" -f $Alert.Condition, $t, $Alert.Currency }
    }
    $re = if ([int]$Alert.RearmMin -gt 0) { " (R{0})" -f (Format-RearmLabel ([int]$Alert.RearmMin)) } else { "" }
    $ex = [string]$Alert.ExpiresAt
    $exp = if ($ex.Length -ge 10) { " bis {0}.{1}." -f $ex.Substring(8, 2), $ex.Substring(5, 2) } else { "" }
    $np = if (-not [bool]$Alert.Push -and [string]$script:Config.PushService -ne "Aus") { " (ohne Push)" } else { "" }
    $note = if ($Alert.Note) { " - " + $Alert.Note } else { "" }
    if ($snz) {
        $su = [DateTime]::Parse([string]$Alert.SnoozeUntil, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        $np += if ($su.Date -eq (Get-Date).Date) { " (Pause bis {0:HH:mm})" -f $su } else { " (Pause bis {0:dd.MM. HH:mm})" -f $su }
    }
    return ("{0} {1,-8} {2}{3}{4}{5}{6}" -f $flag, $Alert.Ticker, $body, $re, $exp, $np, $note)
}

function Add-WidgetAlert {
    # Central place to create an alert (alert panel + chart context menu)
    param([string]$Ticker, [string]$Condition, [double]$Target, [string]$Currency, [string]$Note = "", [int]$RearmMin = 0,
          [string]$ExpiresAt = "", [bool]$Push = $true, [switch]$NoConfirm)
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
        ExpiresAt   = $ExpiresAt
        Peak        = 0.0
        Push        = $Push
    }
    $st = Get-AlertState -Alert $a
    # trailing stop: the high starts at today's price
    if (-not [double]::IsNaN([double]$st.Peak)) { $a.Peak = [double]$st.Peak }
    if (-not $NoConfirm) {
        if ($st.Ok -and $st.Met -and -not (Confirm-Action -Text ("Bedingung ist bereits erfüllt:`r`n{0}`r`nAlarm würde sofort auslösen. Trotzdem anlegen?" -f $st.Text) -Title "Alarm")) {
            return $false
        }
    }
    $script:Alerts.Add($a)
    Save-Alerts
    return $true
}

function Save-Alerts {
    Save-JsonState -Path $script:AlertsPath -Data $script:Alerts.ToArray()
}

function Add-AlertLogEntry {
    param($Alert, [string]$Text, [string]$Push)
    $script:AlertLog.Add([PSCustomObject]@{
        At = (Get-Date).ToString("o"); Ticker = [string]$Alert.Ticker; Condition = [string]$Alert.Condition
        Text = $Text; Note = [string]$Alert.Note; Push = $Push
    })
    while ($script:AlertLog.Count -gt 500) { $script:AlertLog.RemoveAt(0) }
    Save-JsonState -Path $script:AlertLogPath -Data $script:AlertLog.ToArray()
}

function Evaluate-GlobalAlerts {
    $changed = $false
    $now = Get-Date
    foreach ($a in $script:Alerts) {
        if (Test-AlertExpired -Alert $a -Now $now) { continue }
        if (Test-AlertSnoozed -Alert $a -Now $now) { continue }   # v4.9.5
        $st = Get-AlertState -Alert $a
        if (-not $st.Ok) { continue }
        $isTrail = ((Get-AlertKind $a.Condition) -eq "TRAIL")
        if ($a.Triggered) {
            # Re-arm: after the wait time AND once the condition is no longer met
            # (hysteresis - otherwise it would fire again on every poll). A
            # trailing stop starts over from today's price instead.
            if ([int]$a.RearmMin -gt 0 -and ($isTrail -or -not $st.Met)) {
                $at = [DateTime]::MinValue
                $okAt = [DateTime]::TryParse([string]$a.TriggeredAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$at)
                if (-not $okAt -or ($now - $at).TotalMinutes -ge [int]$a.RearmMin) {
                    $a.Triggered = $false
                    if ($isTrail) { $a.Peak = 0.0 }
                    $changed = $true
                    Write-WidgetLog "Alert re-armed: $($a.Ticker) $($a.Condition)"
                }
            }
            continue
        }
        if ($isTrail -and -not [double]::IsNaN([double]$st.Peak) -and [math]::Abs([double]$st.Peak - [double]$a.Peak) -gt 1e-9) {
            $a.Peak = [double]$st.Peak
            $changed = $true
        }
        if ($st.Met) {
            $a.Triggered = $true
            $a.TriggeredAt = $now.ToString("o")
            $changed = $true
            Write-WidgetLog "Alert hit: $($a.Ticker) $($st.Text)"
            $isPf = Test-PortfolioAlertKind (Get-AlertKind $a.Condition)
            $title = if ($isPf) { "Alarm: Depot" } else { "Alarm: $($a.Ticker)" }
            $msg = if ($isPf) { $st.Text } else { "{0}: {1}" -f $a.Ticker, $st.Text }
            if ($a.Note) { $msg += "`r`n" + $a.Note }
            $pushed = Send-WidgetNotification -Title $title -Message $msg -Kind "Alert" -AllowPush ([bool]$a.Push)
            Add-AlertLogEntry -Alert $a -Text $st.Text -Push $pushed
        }
    }
    if ($changed) { Save-Alerts }
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
        "PRE"     { return $script:Pal.Warn }
        "POST"    { return [System.Drawing.Color]::FromArgb(168, 85, 247) }
        default   { return $script:Pal.Muted }
    }
}

function Update-MarketStatusUi {
    if ($script:IsClosing -or $form.IsDisposed) { return }
    # v4.8: the Compact bar can show today's portfolio result instead
    if ([bool]$script:Config.CompactMode -and (([string]$script:Config.CompactShow) -split ',') -contains "Depot") {
        $dl = Get-TrayDepotLine -Currency ([string]$script:Config.Currency)
        $lblMarketStatus.Text = if ($dl) { $dl } else { "Depot: warte auf Kurse" }
        return
    }
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

# ------------------------------------------------------------------------------
# Notifications (v4.3): tray balloon + sound, phone push (ntfy / Telegram),
# quiet hours. Push requests run asynchronously on their own HttpClient (no
# Yahoo cookies); $uiTimer collects the results via Pump-PushTasks.
# ------------------------------------------------------------------------------
$script:PushClient  = $null
$script:PushPending = New-Object System.Collections.Generic.List[PSObject]
$script:PushSent    = New-Object System.Collections.Generic.List[DateTime]

function Protect-Secret {
    # Windows DPAPI (current user) via SecureString, works in 5.1 and 7. The
    # plain text is the token the user just typed; only the encrypted form is stored.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
    param([string]$Plain)
    if (-not $Plain) { return "" }
    try { return (ConvertFrom-SecureString -SecureString (ConvertTo-SecureString -String $Plain -AsPlainText -Force)) }
    catch { Write-WidgetLog "Protect-Secret failed: $($_.Exception.Message)" "WARN"; return "" }
}

function Unprotect-Secret {
    param([string]$Enc)
    if (-not $Enc) { return "" }
    try { return (New-Object System.Net.NetworkCredential("", (ConvertTo-SecureString -String $Enc))).Password }
    catch { Write-WidgetLog "Stored push token cannot be decrypted (other Windows user or PC?)" "WARN"; return "" }
}

function Get-PushRequest {
    param([string]$Title, [string]$Message, [int]$Priority = 3, [string[]]$Tags = @(), $Cfg = $null)
    if ($null -eq $Cfg) { $Cfg = $script:Config }
    $tok = if ($Cfg.PushTokenPlain) { [string]$Cfg.PushTokenPlain } else { Unprotect-Secret ([string]$Cfg.PushTokenEnc) }
    return (New-PushRequest -Service ([string]$Cfg.PushService) -Title $Title -Message $Message -Server ([string]$Cfg.PushServer) `
        -Topic ([string]$Cfg.PushTopic) -Token $tok -ChatId ([string]$Cfg.PushChatId) -Priority $Priority -Tags $Tags)
}

function Send-PushRequest {
    # Starts the POST and returns $true; $OnDone runs later on the UI thread
    # with ($Ok, $Info)
    param($Req, [string]$Desc, [scriptblock]$OnDone = $null)
    if ($null -eq $Req) { return $false }
    if (-not (Test-PushAllowed -Sent $script:PushSent.ToArray() -Max 10)) {
        Write-WidgetLog "Push skipped (more than 10 per minute): $Desc" "WARN"
        return $false
    }
    try {
        if ($null -eq $script:PushClient) {
            $script:PushClient = New-Object System.Net.Http.HttpClient
            $script:PushClient.Timeout = [TimeSpan]::FromSeconds(15)
        }
        $content = New-Object System.Net.Http.StringContent([string]$Req.Json, [System.Text.Encoding]::UTF8, "application/json")
        $task = $script:PushClient.PostAsync([string]$Req.Url, $content)
        $script:PushPending.Add([PSCustomObject]@{ Task = $task; Content = $content; Desc = $Desc; OnDone = $OnDone })
        $script:PushSent.Add((Get-Date))
        while ($script:PushSent.Count -gt 20) { $script:PushSent.RemoveAt(0) }
        return $true
    } catch {
        Write-WidgetLog "Push could not be started: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Pump-PushTasks {
    for ($i = $script:PushPending.Count - 1; $i -ge 0; $i--) {
        $pp = $script:PushPending[$i]
        if (-not $pp.Task.IsCompleted) { continue }
        $script:PushPending.RemoveAt($i)
        $ok = $false; $info = ""
        if ($pp.Task.IsFaulted -or $pp.Task.IsCanceled) {
            $info = if ($null -ne $pp.Task.Exception) { "keine Verbindung: " + $pp.Task.Exception.GetBaseException().Message } else { "Zeitüberschreitung" }
        } else {
            $resp = $pp.Task.Result
            try {
                $ok = [bool]$resp.IsSuccessStatusCode
                $info = if ($ok) { "gesendet" } else { "abgelehnt (HTTP {0}): {1}" -f [int]$resp.StatusCode, [string]$resp.Content.ReadAsStringAsync().Result }
            } catch { $info = $_.Exception.Message } finally { $resp.Dispose() }
        }
        try { $pp.Content.Dispose() } catch { }
        if ($info.Length -gt 300) { $info = $info.Substring(0, 300) }
        Write-WidgetLog ("Push '{0}': {1}" -f $pp.Desc, $info) $(if ($ok) { "INFO" } else { "WARN" })
        if ($null -ne $pp.OnDone) { try { & $pp.OnDone $ok $info } catch { } }
    }
}

function Send-WidgetNotification {
    # Balloon (+ sound for alerts) and phone push, respecting quiet hours.
    # Returns the push status for the alert log: ja / aus / Ruhezeit / Fehler
    param([string]$Title, [string]$Message, [string]$Kind = "Alert", [bool]$AllowPush = $true)
    $quiet = Test-QuietHours -From ([string]$script:Config.QuietFrom) -To ([string]$script:Config.QuietTo)
    if ($script:Config.ShowTrayNotifications) {
        if (-not $quiet -and $Kind -eq "Alert") { try { [System.Media.SystemSounds]::Exclamation.Play() } catch { } }
        try { $trayIcon.ShowBalloonTip(6000, $Title, $Message, [System.Windows.Forms.ToolTipIcon]::Info) } catch { }
    }
    $want = if ($Kind -eq "Earnings") { [bool]$script:Config.PushEarnings } else { [bool]$script:Config.PushAlerts }
    if ([string]$script:Config.PushService -eq "Aus" -or -not $want -or -not $AllowPush) { return "aus" }
    if ($quiet) { return "Ruhezeit" }
    $prio = if ($Kind -eq "Alert") { 4 } else { 3 }
    $tags = if ($Kind -eq "Alert") { @("bell") } elseif ($Kind -eq "News") { @("newspaper") } else { @("date") }
    if (Send-PushRequest -Req (Get-PushRequest -Title $Title -Message $Message -Priority $prio -Tags $tags) -Desc $Title) { return "ja" }
    return "Fehler"
}

function Show-AlertLogDialog {
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Alarm-Verlauf - $($script:AppTitle)" -W (S 760) -H (S 440)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 560), (S 280))
    $aBR = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds((S 12), (S 12), (S 736), (S 372))
    $g.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    Style-DataGrid -Grid $g
    foreach ($cd in @(@("At", "Zeit", 100), @("Ticker", "Ticker", 70), @("Cond", "Bedingung", 90), @("Text", "Wert", 280), @("Note", "Notiz", 110), @("Push", "Push", 60))) {
        $ci = $g.Columns.Add($cd[0], $cd[1])
        $g.Columns[$ci].FillWeight = [float](S $cd[2])
    }
    $g.Columns["Push"].ToolTipText = "ja = aufs Handy geschickt, Ruhezeit / aus = nicht geschickt, Fehler = siehe Log"
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    for ($i = $script:AlertLog.Count - 1; $i -ge 0; $i--) {
        $e = $script:AlertLog[$i]
        $at = [DateTime]::MinValue
        $atTxt = if ([DateTime]::TryParse([string]$e.At, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$at)) { $at.ToString("dd.MM.yy HH:mm") } else { [string]$e.At }
        [void]$g.Rows.Add($atTxt, $e.Ticker, $e.Condition, $e.Text, $e.Note, $e.Push)
    }
    $dlg.Controls.Add($g)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.SetBounds((S 12), (S 398), (S 400), (S 20))
    $lbl.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $lbl.ForeColor = $p.Muted
    $lbl.Text = "{0} Einträge (die letzten 500 werden behalten)" -f $script:AlertLog.Count
    $dlg.Controls.Add($lbl)
    Set-DynTip $lbl "" "ALERTLOG"
    $btnClr = New-Object System.Windows.Forms.Button
    $btnClr.SetBounds((S 554), (S 394), (S 94), (S 28)); $btnClr.Anchor = $aBR
    Style-FlatButton -Btn $btnClr -BgColor $p.Input -FgColor $colRed -BorderColor $p.Border
    $btnClr.Text = "Leeren"
    $btnClr.Add_Click({
        param($sender, $e)
        if (-not (Confirm-Action -Text "Alarm-Verlauf wirklich leeren?" -Title "Alarm-Verlauf")) { return }
        $script:AlertLog.Clear()
        Save-JsonState -Path $script:AlertLogPath -Data @()
        $sender.FindForm().Close()
    })
    $dlg.Controls.Add($btnClr)
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.SetBounds((S 654), (S 394), (S 94), (S 28)); $btnClose.Anchor = $aBR
    Style-FlatButton -Btn $btnClose -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnClose.Text = "Schließen"
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnClose)
    $dlg.CancelButton = $btnClose
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
}

function Show-PushDialog {
    # Phone push setup; changes go straight into $script:Config (saved by the caller)
    param($Owner)
    $p = $script:Pal
    $cfg = $script:Config
    $dlg = New-DialogForm -Title "Handy-Push - $($script:AppTitle)" -W (S 520) -H (S 410)
    $y = S 12
    $mkLbl = {
        param([string]$T, [int]$Y)
        $l = New-Object System.Windows.Forms.Label
        $l.SetBounds((S 14), ($Y + (S 3)), (S 130), (S 18)); $l.Text = $T
        $dlg.Controls.Add($l)
        return $l
    }
    $mkTxt = {
        param([string]$V, [int]$Y, [int]$Wd)
        $t = New-Object System.Windows.Forms.TextBox
        $t.SetBounds((S 150), $Y, $Wd, (S 24))
        $t.BackColor = $p.Input; $t.ForeColor = $p.Text; $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $t.Font = $fontMono; $t.Text = $V
        $dlg.Controls.Add($t)
        return $t
    }
    $mkBtn = {
        param([string]$T, [int]$X, [int]$Y, [int]$Wd)
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds($X, $Y, $Wd, (S 25))
        Style-FlatButton -Btn $b -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
        $b.Text = $T
        $dlg.Controls.Add($b)
        return $b
    }
    $info = New-Object System.Windows.Forms.Label
    $info.SetBounds((S 14), $y, (S 492), (S 34)); $info.ForeColor = $p.Muted
    $info.Text = "Alarme (und auf Wunsch Quartalszahlen) zusätzlich aufs Handy. ntfy: App installieren und das Thema abonnieren. Telegram: Bot bei @BotFather anlegen."
    $dlg.Controls.Add($info)
    $y += S 40
    [void](& $mkLbl "Dienst" $y)
    $cbSvc = New-Object System.Windows.Forms.ComboBox
    $cbSvc.SetBounds((S 150), $y, (S 120), (S 24))
    $cbSvc.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbSvc.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cbSvc.BackColor = $p.Input; $cbSvc.ForeColor = $p.Text
    foreach ($s in @("Aus", "ntfy", "Telegram")) { [void]$cbSvc.Items.Add($s) }
    $cbSvc.SelectedIndex = [math]::Max(0, $cbSvc.Items.IndexOf([string]$cfg.PushService))
    $dlg.Controls.Add($cbSvc)
    Set-DynTip $cbSvc "" "PUSH"
    $y += S 34
    $lSrv = & $mkLbl "ntfy-Server" $y
    $tSrv = & $mkTxt ([string]$cfg.PushServer) $y (S 250)
    Set-DynTip $tSrv "Standard: https://ntfy.sh - oder ein eigener ntfy-Server"
    $y += S 30
    $lTop = & $mkLbl "ntfy-Thema" $y
    $tTop = & $mkTxt ([string]$cfg.PushTopic) $y (S 250)
    $bRnd = & $mkBtn "Zufällig" (S 406) $y (S 100)
    Set-DynTip $tTop "Wie ein Passwort: wer das Thema kennt, liest mit. Erlaubt: Buchstaben, Ziffern, - und _" "PUSH"
    $y += S 34
    $lTok = & $mkLbl "Telegram-Token" $y
    $tTok = & $mkTxt "" $y (S 250)
    $tTok.UseSystemPasswordChar = $true
    $hasTok = [bool]([string]$cfg.PushTokenEnc)
    if ($hasTok) { $tTok.Text = "********" }
    Set-DynTip $tTok "Token von @BotFather (123456:ABC...). Wird verschlüsselt gespeichert (nur dein Windows-Konto kann ihn lesen)." "PUSH"
    $y += S 30
    $lChat = & $mkLbl "Telegram-Chat-ID" $y
    $tChat = & $mkTxt ([string]$cfg.PushChatId) $y (S 140)
    $bChat = & $mkBtn "Chat-ID holen" (S 296) $y (S 120)
    Set-DynTip $bChat "Erst dem Bot in Telegram eine Nachricht schreiben (z. B. /start), dann hier klicken"
    $y += S 36
    $chkA = New-Object System.Windows.Forms.CheckBox
    $chkA.SetBounds((S 14), $y, (S 240), (S 22)); $chkA.Text = "Bei Alarmen"; $chkA.Checked = [bool]$cfg.PushAlerts
    $chkA.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dlg.Controls.Add($chkA)
    $chkE = New-Object System.Windows.Forms.CheckBox
    $chkE.SetBounds((S 260), $y, (S 246), (S 22)); $chkE.Text = "Quartalszahlen (Vortag)"; $chkE.Checked = [bool]$cfg.PushEarnings
    $chkE.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dlg.Controls.Add($chkE)
    Set-DynTip $chkE "" "EARNINGS"
    $y += S 34
    $bTest = & $mkBtn "Test senden" (S 14) $y (S 120)
    $lRes = New-Object System.Windows.Forms.Label
    $lRes.SetBounds((S 142), ($y + (S 4)), (S 364), (S 40)); $lRes.ForeColor = $p.Muted
    $dlg.Controls.Add($lRes)
    $y += S 52
    $ok = & $mkBtn "OK" (S 312) $y (S 94)
    Style-FlatButton -Btn $ok -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $cancel = & $mkBtn "Abbrechen" (S 412) $y (S 94)
    Style-FlatButton -Btn $cancel -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.CancelButton = $cancel
    $dlg.ClientSize = New-Object System.Drawing.Size((S 520), ($y + (S 40)))

    $script:PushCtl = @{
        Dlg = $dlg; Svc = $cbSvc; Srv = $tSrv; Top = $tTop; Tok = $tTok; Chat = $tChat; Res = $lRes; A = $chkA; E = $chkE
        HasTok = $hasTok; Rows = @(@($lSrv, $tSrv), @($lTop, $tTop, $bRnd), @($lTok, $tTok), @($lChat, $tChat, $bChat))
    }
    $getToken = {
        $pc = $script:PushCtl
        $t = ([string]$pc.Tok.Text).Trim()
        if ($pc.HasTok -and $t -eq "********") { return (Unprotect-Secret ([string]$script:Config.PushTokenEnc)) }
        return $t
    }
    $script:PushCtl.GetToken = $getToken
    $script:PushCtl.Show = {
        $pc = $script:PushCtl
        $svc = [string]$pc.Svc.SelectedItem
        for ($i = 0; $i -lt $pc.Rows.Count; $i++) {
            $on = if ($i -lt 2) { $svc -eq "ntfy" } else { $svc -eq "Telegram" }
            foreach ($c in $pc.Rows[$i]) { $c.Enabled = $on }
        }
    }
    & $script:PushCtl.Show
    $cbSvc.Add_SelectedIndexChanged({ & $script:PushCtl.Show })
    $bRnd.Add_Click({ $script:PushCtl.Top.Text = New-RandomTopic })
    $tTok.Add_Enter({ param($sender, $e) if ($script:PushCtl.HasTok -and $sender.Text -eq "********") { $sender.SelectAll() } })
    $bChat.Add_Click({
        $pc = $script:PushCtl
        $tok = & $pc.GetToken
        if ($tok -notmatch '^\d+:[A-Za-z0-9_-]+$') { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Bitte zuerst einen gültigen Bot-Token eintragen."; return }
        $u = "https://api.telegram.org/bot{0}/getUpdates" -f $tok
        $r = Invoke-ParallelFetch -Urls @($u) -TimeoutSec 8
        $id = Get-TelegramChatId $r[$u]
        if ($id) { $pc.Chat.Text = $id; $pc.Res.ForeColor = $colGreen; $pc.Res.Text = "Chat-ID gefunden: $id" }
        else { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Keine Nachricht gefunden. Schreib dem Bot in Telegram etwas (z. B. /start) und versuch es nochmal." }
    })
    $bTest.Add_Click({
        $pc = $script:PushCtl
        $tmp = [PSCustomObject]@{
            PushService = [string]$pc.Svc.SelectedItem; PushServer = $pc.Srv.Text.Trim(); PushTopic = $pc.Top.Text.Trim()
            PushTokenEnc = ""; PushTokenPlain = (& $pc.GetToken); PushChatId = $pc.Chat.Text.Trim()
        }
        $req = Get-PushRequest -Title "TerminalWidget" -Message ("Test vom PC ({0}) - Push funktioniert." -f (Get-Date).ToString("HH:mm")) -Cfg $tmp
        if ($null -eq $req) { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Einstellungen unvollständig (Dienst, Thema bzw. Token und Chat-ID)."; return }
        $pc.Res.ForeColor = $script:Pal.Muted; $pc.Res.Text = "Sende ..."
        $started = Send-PushRequest -Req $req -Desc "Test" -OnDone {
            param($Ok, $Info)
            if ($null -eq $script:PushCtl) { return }
            $script:PushCtl.Res.ForeColor = if ($Ok) { $colGreen } else { $colRed }
            $script:PushCtl.Res.Text = if ($Ok) { "Gesendet - kommt die Nachricht am Handy an?" } else { "Fehler: $Info" }
        }
        if (-not $started) { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Konnte nicht senden (Limit 10 pro Minute oder Fehler, siehe Log)." }
    })
    $ok.Add_Click({
        $pc = $script:PushCtl
        $svc = [string]$pc.Svc.SelectedItem
        $tok = & $pc.GetToken
        if ($svc -eq "ntfy" -and $pc.Top.Text.Trim() -notmatch '^[A-Za-z0-9_-]{1,64}$') { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Bitte ein Thema eintragen (Buchstaben, Ziffern, - und _), z. B. über 'Zufällig'."; return }
        if ($svc -eq "Telegram" -and ($tok -notmatch '^\d+:[A-Za-z0-9_-]+$' -or $pc.Chat.Text.Trim() -notmatch '^-?\d+$')) { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Bitte Bot-Token und Chat-ID eintragen."; return }
        $c = $script:Config
        $c.PushService = $svc
        $c.PushServer = if ($pc.Srv.Text.Trim()) { $pc.Srv.Text.Trim() } else { "https://ntfy.sh" }
        $c.PushTopic = $pc.Top.Text.Trim()
        $c.PushTokenEnc = if ($tok) { Protect-Secret $tok } else { "" }
        $c.PushChatId = $pc.Chat.Text.Trim()
        $c.PushAlerts = [bool]$pc.A.Checked
        $c.PushEarnings = [bool]$pc.E.Checked
        Save-JsonState -Path $script:ConfigPath -Data $c
        Write-WidgetLog "Push settings saved: $svc"
        $pc.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $pc.Dlg.Close()
    })
    $res = $dlg.ShowDialog($(if ($null -ne $Owner) { $Owner } else { $form }))
    $script:PushCtl = $null
    $dlg.Dispose()
    return ($res -eq [System.Windows.Forms.DialogResult]::OK)
}

# ------------------------------------------------------------------------------
# Earnings / dividend dates (v4.2): refreshed in the background for portfolio,
# watchlist and the active ticker; tray hint the day before quarterly figures
# ------------------------------------------------------------------------------
$script:NextEventsCheck = (Get-Date).AddSeconds(30)

function Get-EventSymbols {
    $set = New-Object System.Collections.Generic.HashSet[string]
    if ($script:Config.ActiveTicker) { [void]$set.Add(([string]$script:Config.ActiveTicker).ToUpper()) }
    foreach ($k in $script:Portfolio.Keys) { [void]$set.Add(([string]$k).ToUpper()) }
    foreach ($w in @($script:Config.Watchlist)) { if ($w) { [void]$set.Add(([string]$w).ToUpper()) } }
    return @($set | Where-Object { $_ -notmatch '^\^|=X$|-USD$|-EUR$' })
}

function Update-EventsIfStale {
    if ($script:IsClosing -or $script:ProfileJobRunning -or $script:WorkerShared.CrumbFailed) { return }
    $stale = @(Get-EventSymbols | Where-Object { Test-EventsStale -Entry $script:Events[$_] } | Select-Object -First 15)
    if ($stale.Count -eq 0) { return }
    Start-ProfileJob -Symbols $stale -EventsOnly $true -OnComplete {
        try { Update-AllUiViews } catch { }
        if ($null -ne $script:AnaCtl) { Update-AnalysisDividends }
        Check-EarningsNotifications
    }
}

function Check-EarningsNotifications {
    # One balloon per company and earnings date, the day before (or on the day)
    if (-not $script:Config.NotifyEarnings) { return }
    $changed = $false
    foreach ($k in @($script:Portfolio.Keys)) {
        $u = ([string]$k).ToUpper()
        $ev = $script:Events[$u]
        if ($null -eq $ev -or -not $ev.EarningsDate -or [string]$ev.NotifiedEarnings -eq [string]$ev.EarningsDate) { continue }
        $b = Get-EarningsBadge -EarningsDate ([string]$ev.EarningsDate) -WindowDays 1
        if ($null -eq $b) { continue }
        [void](Send-WidgetNotification -Title "Quartalszahlen: $u" -Message ("{0} ({1}) - Kurs kann stark schwanken" -f $(if ($b.Days -eq 0) { "Heute" } else { "Morgen" }), (Format-IsoDateDe $b.Date)) -Kind "Earnings")
        $ev.NotifiedEarnings = [string]$ev.EarningsDate
        $changed = $true
        Write-WidgetLog "Earnings notice: $u $($ev.EarningsDate)"
    }
    if ($changed) { Save-Events }
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
    $amber = $script:Pal.Warn
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
    # v4.9.5: health dot
    $hAge = if ($null -eq $script:LastDataTime) { [double]::NaN } else { ((Get-Date) - $script:LastDataTime).TotalSeconds }
    $hClosed = $false
    if (-not [double]::IsNaN($hAge) -and $hAge -gt 2 * [int]$script:Config.RefreshSeconds) { $hClosed = Test-AllPrioClosed }
    $hl = Get-DataHealth -AgeSec $hAge -RefreshSec ([int]$script:Config.RefreshSeconds) -Offline ([bool]$script:LastFetchOffline) -RateLimited ([bool]$script:LastRateLimited) -ClosedMinutes ([int]$script:Config.ClosedPollMinutes) -AllClosed $hClosed
    if ($hl -ne $script:HealthLevel) {
        $script:HealthLevel = $hl
        $pnlHealth.Invalidate()
        $stTxt = if ($null -ne $script:LastDataTime) { $script:LastDataTime.ToString("HH:mm:ss") } else { "--:--:--" }
        $hTip = switch ($hl) {
            "OK"   { "Datenquelle Yahoo Finance: OK (letzte Aktualisierung $stTxt)" }
            "WARN" { if ($script:LastRateLimited) { "Yahoo bremst gerade (Rate-Limit) - es geht nach einer Pause automatisch weiter. Letzte Daten: $stTxt" } else { "Daten etwas veraltet oder unvollständig. Letzte Aktualisierung: $stTxt" } }
            "ERR"  { "Keine Verbindung zu Yahoo Finance oder Daten sehr alt. Letzte Aktualisierung: $stTxt. F5 versucht es sofort." }
            default { "Noch keine Daten" }
        }
        Set-DynTip $pnlHealth $hTip
    }
}

function Test-AllPrioClosed {
    $mst = @(Get-PrioMarketStates)
    return ($mst.Count -gt 0 -and @($mst | Where-Object { $_ -ne "CLOSED" }).Count -eq 0)
}

function Update-AllUiViews {
    if ($script:IsClosing -or $form.IsDisposed) { return }
    $sym  = $script:Config.ActiveTicker.ToUpper()
    $curr = Get-PriceCurrency $sym   # v5.1: price in the ticker currency (Auto); depot lines below use $baseCur
    $baseCur = [string]$script:Config.Currency
    $p    = $script:Pal
    $btnCurrency.Text = $(if ([bool]$script:Config.AutoCurrency) { "Auto $script:DropArrow" } else { "$baseCur $script:DropArrow" })

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
        @{ Btn = $btnChartType;  Active = ($script:Config.ChartType -in @("Candle", "HA")) },
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
    # v5.0: Linie / Kerzen / Heikin-Ashi (K cycles)
    $ctTxt = if ([string]$script:Config.ChartType -eq "HA") { "Heikin-A." } else { Tr "Kerzen" }
    if ($btnChartType.Text -ne $ctTxt) { $btnChartType.Text = $ctTxt }

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
        $lblDayChange.Text = "{0}{1}{2:N2}%" -f (Get-ArrowPrefix ([double]$q.ChangePct)), $sign, $q.ChangePct
        # v4.6: coloured "pill" behind the day change
        $lblDayChange.BackColor = Get-BlendColor -A $col -B $p.HeaderBg -T 0.18
        $dispPrev = Convert-CurrencyValue -Amount $q.PrevClose -FromCurrency $q.Currency -ToCurrency $curr
        $lblDayAbs.Text = if ($q.PrevClose -gt 0) { "{0}{1:N2} {2}" -f $sign, ($dispPrice - $dispPrev), $curr } else { "" }
        # v4.2: quarterly figures within a week -> amber note in front of the name
        $eb = Get-TickerEarningsBadge ([string]$script:Config.ActiveTicker)
        if ($null -ne $eb) {
            $lblHeaderName.Text = "Zahlen {0} · {1} ({2})" -f $eb.Text, $q.LongName, $q.Currency
            $lblHeaderName.ForeColor = $script:Pal.Warn
        } else {
            $lblHeaderName.Text = "{0} ({1})" -f $q.LongName, $q.Currency
            $lblHeaderName.ForeColor = $p.Muted
        }

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
        # v4.4: second line with today's portfolio result
        $dl = Get-TrayDepotLine -Currency $baseCur
        if ($dl -and ($tt.Length + $dl.Length + 1) -le 63) { $tt = $tt + "`n" + $dl }
        $trayIcon.Text = if ($tt.Length -gt 63) { $tt.Substring(0, 63) } else { $tt }
        # v4.9.5: the tray icon follows the depot's day result (setting), else the ticker
        $trayKey = if ($q.ChangePct -ge 0) { "up" } else { "down" }
        if ([bool]$script:Config.TrayFollowsDepot -and $script:Portfolio.Count -gt 0) {
            $ptT = Get-PortfolioDayTotals -Currency $baseCur
            if ($ptT.Ok) { $trayKey = Get-DirectionKey -Pct ([double]$ptT.DayPct) }
        }
        Update-TrayIcon -Key $trayKey
    } else {
        $lblLivePrice.Text = "--.-- $curr"
        $lblDayChange.ForeColor = $p.Muted
        $lblDayChange.BackColor = $p.HeaderBg
        $lblDayChange.Text = "0.00%"
        $lblDayAbs.Text = ""
        $lblExtQuote.Text = ""
        $lblHeaderName.Text = $sym
        $lblHeaderName.ForeColor = $script:Pal.Muted
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
    # v4.9.5: recent tickers for the search list (saved with the next config write)
    $script:Config.RecentTickers = @(Add-RecentCommand -Recent @($script:Config.RecentTickers) -Command $clean -Max 10)
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
        Invoke-TabClick -TabName ([string]$sender.Tag)
    })
}

foreach ($k in $tfButtons.Keys) {
    $tfButtons[$k].Add_Click({
        param($sender, $e)
        Set-Timeframe -Tf ([string]$sender.Tag)
    })
}

$btnChartType.Add_Click({
    $script:Config.ChartType = Get-NextChartType ([string]$script:Config.ChartType)
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
    param([int]$Year = 0, [string]$Type = "")
    $curr = $script:Config.Currency
    $sum = 0.0
    foreach ($t in $script:Transactions) {
        if ($Year -gt 0 -and -not ([string]$t.Date).StartsWith([string]$Year)) { continue }
        if ($Type -and [string]$t.Type -ne $Type) { continue }
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
    $d.Add_HandleCreated($script:DialogChromeHandler)
    # v4.7: English mode translates the static texts once the dialog is built
    $d.Add_Shown({ param($sender, $e) Apply-Language $sender })
    $d.Text = Tr $Title
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
    # v4.5: CSV import from the history window
    $btnImp = New-Object System.Windows.Forms.Button
    $btnImp.SetBounds((S 572), (S 398), (S 60), (S 28))
    $btnImp.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    Style-FlatButton -Btn $btnImp -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnImp.Text = "Import"
    $btnImp.Add_Click({ $script:TxHist.Import = $true; $script:TxHist.Dlg.Close() })
    $dlg.Controls.Add($btnImp)
    Set-DynTip $btnImp "Buchungen aus einer Broker-CSV importieren (Trade Republic, Scalable, Flatex, comdirect, IBKR ... - Spalten werden erkannt). Befehl: IMP"
    $script:TxHist.Import = $false
    [void]$dlg.ShowDialog($form)
    $doImport = [bool]$script:TxHist.Import
    $script:TxHist = $null
    $dlg.Dispose()
    if ($doImport) { Show-CsvImportDialog }
}

function Invoke-PositionRebuild {
    # v3.0: replays all buys/sells of one ticker (average cost, see Core) and -
    # after a preview - replaces the position. Returns $true when it changed.
    # v4.5: -Silent = no dialogs (CSV import)
    param([string]$Ticker, $Owner = $null, [switch]$Silent)
    $sym = ([string]$Ticker).Trim().ToUpper()
    if (-not $sym) { return $false }
    $own = if ($null -ne $Owner) { $Owner } else { $form }
    $title = "Position neu berechnen"
    # v4.1: split events (bounded synchronous lookup, once per session)
    Ensure-SplitsLoaded -Tickers @($sym)
    $r = Get-PositionFromTransactions -Transactions $script:Transactions.ToArray() -Ticker $sym -Splits (Get-SplitMap)
    if ($null -eq $r) {
        if ($Silent) { return $false }
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
    if ($r.Splits -gt 0) { $notes += "`r`n- {0} Aktiensplit(s) berücksichtigt (Stück und EK umgerechnet)" -f $r.Splits }
    $msg = ("{0}: aus {1} Buchung(en) neu berechnen (Durchschnittskosten)?`r`n`r`nAktuell:  {2}`r`nNeu:      {3}{4}`r`n`r`nHinweis: Werte, die im Portfolio-Editor direkt überschrieben wurden, sind nicht als Buchung erfasst und gehen dabei verloren." -f $sym, $r.Used, $oldTxt, $newTxt, $notes)
    if (-not $Silent) {
        $ans = [System.Windows.Forms.MessageBox]::Show($own, $msg, $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
    }

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
# v4.1: split events per ticker (from the report's monthly or the analysis'
# daily history), shared by the yearly report, the rebuild and the analysis
$script:SplitCache = @{}

function Get-FxHistoryMap {
    $hist = @{}
    foreach ($k in $script:FxHistCache.Keys) { if ($null -ne $script:FxHistCache[$k].Hist) { $hist[$k] = $script:FxHistCache[$k].Hist } }
    return $hist
}

function Get-SplitMap {
    $m = @{}
    foreach ($k in $script:SplitCache.Keys) { $m[$k] = @($script:SplitCache[$k].Splits) }
    return $m
}

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
        $rc.Info.ForeColor = if (@($Rep.Warnings).Count -gt 0) { $script:Pal.Warn } else { $script:Pal.Muted }
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
        # v4.1: split events of every ticker with buys/sells (NVDA 10:1 etc.)
        $needSplit = @($txs | Where-Object { [string]$_.Type -in @("Kauf", "Verkauf") } | ForEach-Object { ([string]$_.Ticker).ToUpper() } | Sort-Object -Unique |
            Where-Object { -not $script:SplitCache.ContainsKey($_) -or [int]$script:SplitCache[$_].ToYear -lt $year })
        $fallback = @{}
        foreach ($k in $script:FxFromEur.Keys) { $fallback[$k] = [double]$script:FxFromEur[$k] }
        $compute = {
            param([int]$Y, [string]$B, $Txs, $Fb)
            $rep = Get-RealizedReport -Transactions $Txs -Year $Y -Base $B -History (Get-FxHistoryMap) -FallbackFromEur $Fb -Splits (Get-SplitMap)
            & $script:RepCtl.Render $rep
        }
        $script:RepCtl.Compute = $compute
        if ($need.Count -eq 0 -and $needSplit.Count -eq 0) { & $compute $year $base $txs $fallback; return }

        # Daily FX history from the earliest booking up to the end of the year
        $first = Get-EarliestBookingDate -Transactions $txs
        $from = if ($first) { [DateTime]::ParseExact($first, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture).AddDays(-10) } else { New-Object DateTime($year, 1, 1) }
        $to = (New-Object DateTime($year, 12, 31)).AddDays(2)
        if ($to -gt (Get-Date)) { $to = Get-Date }
        $p1 = ([DateTimeOffset]$from).ToUnixTimeSeconds()
        $p2 = ([DateTimeOffset]$to).ToUnixTimeSeconds()
        $urls = @{}
        foreach ($c in $need) { $urls[$c] = "https://query1.finance.yahoo.com/v8/finance/chart/EUR${c}=X?interval=1d&period1=$p1&period2=$p2" }
        $splitUrls = @{}
        foreach ($t in $needSplit) { $splitUrls[$t] = "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval=1mo&period1={1}&period2={2}&events=split" -f [Uri]::EscapeDataString($t), $p1, ([DateTimeOffset](Get-Date)).ToUnixTimeSeconds() }
        $rc.Calc.Enabled = $false
        $rc.Info.ForeColor = $script:Pal.Muted
        $rc.Info.Text = "Lade Wechselkurse und Splits: " + (@($need) + @($needSplit) -join ", ") + " ..."
        Start-FetchJob -Urls (@($urls.Values) + @($splitUrls.Values)) -MaxConcurrency 3 -Context @{ Urls = $urls; SplitUrls = $splitUrls; Year = $year; Base = $base; Txs = $txs; Fb = $fallback; From = $from.ToString("yyyy-MM-dd") } -OnComplete {
            param($Box, $Ctx)
            foreach ($c in @($Ctx.Urls.Keys)) {
                $h = ConvertFrom-YahooFxHistory -Json $Box.Results[$Ctx.Urls[$c]]
                if ($null -ne $h) { $script:FxHistCache[$c] = @{ Hist = $h; ToYear = $Ctx.Year; FromDate = $Ctx.From } }
                else { Write-WidgetLog "FX history for $c not available" "WARN" }
            }
            foreach ($t in @($Ctx.SplitUrls.Keys)) {
                $h = ConvertFrom-YahooDailyHistory -Json $Box.Results[$Ctx.SplitUrls[$t]]
                $old = $script:SplitCache[$t]
                if ($null -ne $h -and ($null -eq $old -or -not [bool]$old.Full)) { $script:SplitCache[$t] = @{ Splits = @($h.Splits); ToYear = (Get-Date).Year } }
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

# ==============================================================================
# Portfolio analysis (v4.1): value history rebuilt from the bookings with a
# benchmark shadow portfolio, returns per position (XIRR), and the breakdown
# by position / currency / sector / country. Window: P key or Portfolio >
# "Analyse". Data: daily closes since the first booking, daily FX, profiles.
# ==============================================================================
$script:AnaHist = @{}     # symbol -> @{ Hist; At; From }
$script:AnaCtl  = $null   # controls + model while the window is open

function Get-AnalysisBase {
    $b = Get-NormalizedCurrencyCode ([string]$script:Config.AnalysisBase)
    if (-not $b) { $b = [string]$script:Config.Currency }
    return $b
}

function Get-AnalysisSymbols {
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $script:Portfolio.Keys) { [void]$set.Add(([string]$k).ToUpper()) }
    foreach ($t in $script:Transactions) { if ([string]$t.Type -in @("Kauf", "Verkauf")) { [void]$set.Add(([string]$t.Ticker).ToUpper()) } }
    return @($set | Sort-Object)
}

function Get-AnalysisPriceNow {
    # Current price in Base: live quote, else the last daily close; NaN if unknown
    param([string]$Sym, [string]$Base)
    $q = $script:QuoteStore[$Sym]
    if ($null -ne $q -and [double]$q.Price -gt 0) { return (Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $Base) }
    $h = $script:AnaHist[$Sym]
    if ($null -ne $h -and $null -ne $h.Hist -and $h.Hist.Closes.Count -gt 0) {
        return (Convert-CurrencyValue -Amount ([double]$h.Hist.Closes[$h.Hist.Closes.Count - 1]) -FromCurrency ([string]$h.Hist.Currency) -ToCurrency $Base)
    }
    return [double]::NaN
}

function Get-InstrumentCurrency {
    param([string]$Sym)
    $q = $script:QuoteStore[$Sym]
    if ($null -ne $q -and $q.Currency) { return (Get-NormalizedCurrencyCode ([string]$q.Currency)) }
    $h = $script:AnaHist[$Sym]
    if ($null -ne $h -and $null -ne $h.Hist) { return [string]$h.Hist.Currency }
    if ($script:Portfolio.ContainsKey($Sym)) { return [string]$script:Portfolio[$Sym].Currency }
    return ""
}

function Test-FxHistFresh {
    param([string]$Cur, [string]$From)
    if (-not $script:FxHistCache.ContainsKey($Cur)) { return $false }
    $e = $script:FxHistCache[$Cur]
    if ($null -eq $e.Hist -or [int]$e.ToYear -lt (Get-Date).Year -or -not $e.FromDate) { return $false }
    return ([string]::CompareOrdinal([string]$e.FromDate, $From) -le 0)
}

function Get-AnalysisFxUrls {
    param([string[]]$Currencies, [string]$From, [long]$P1, [long]$P2, [bool]$Force = $false)
    $u = @{}
    foreach ($c0 in @($Currencies)) {
        $c = Get-NormalizedCurrencyCode ([string]$c0)
        if (-not $c -or $c -eq "EUR" -or $u.ContainsKey($c)) { continue }
        if ($Force -or -not (Test-FxHistFresh -Cur $c -From $From)) {
            $u[$c] = "https://query1.finance.yahoo.com/v8/finance/chart/EUR${c}=X?interval=1d&period1=$P1&period2=$P2"
        }
    }
    return $u
}

function Save-FxHistResults {
    param($Box, [hashtable]$FxUrls, [string]$From)
    foreach ($c in @($FxUrls.Keys)) {
        $h = ConvertFrom-YahooFxHistory -Json $Box.Results[$FxUrls[$c]]
        if ($null -ne $h) { $script:FxHistCache[$c] = @{ Hist = $h; ToYear = (Get-Date).Year; FromDate = $From } }
        else { Write-WidgetLog "FX history for $c not available" "WARN" }
    }
}

function Start-AnalysisLoad {
    param([bool]$Force = $false)
    $ac = $script:AnaCtl
    if ($null -eq $ac) { return }
    $txs = $script:Transactions.ToArray()
    $first = Get-EarliestBookingDate -Transactions @($txs | Where-Object { [string]$_.Type -in @("Kauf", "Verkauf", "Dividende") })
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $fromD = if ($first) { [DateTime]::ParseExact($first, "yyyy-MM-dd", $inv).AddDays(-10) } else { (Get-Date).Date.AddYears(-1) }
    $from = $fromD.ToString("yyyy-MM-dd")
    $p1 = ([DateTimeOffset]$fromD).ToUnixTimeSeconds()
    $p2 = ([DateTimeOffset]((Get-Date).AddDays(1))).ToUnixTimeSeconds()
    $base = Get-AnalysisBase
    $bench = [string]$script:Config.AnalysisBenchmark
    $syms = @(Get-AnalysisSymbols)
    if ($bench -and $syms -notcontains $bench) { $syms += $bench }
    foreach ($cs in (Get-CompareSymbols)) { if ($syms -notcontains $cs) { $syms += $cs } }

    $urls = @{}
    foreach ($s in $syms) {
        $h = $script:AnaHist[$s]
        $fresh = ($null -ne $h -and ((Get-Date) - $h.At).TotalMinutes -lt 30 -and [string]::CompareOrdinal([string]$h.From, $from) -le 0)
        if ($Force -or -not $fresh) {
            $urls[$s] = "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval=1d&period1={1}&period2={2}&events=div%7Csplit" -f [Uri]::EscapeDataString($s), $p1, $p2
        }
    }
    # currencies known now; price currencies seen for the first time follow in step 2
    $curs = New-Object System.Collections.Generic.HashSet[string]
    foreach ($t in $txs) { $c = Get-NormalizedCurrencyCode ([string]$t.Currency); if ($c) { [void]$curs.Add($c) } }
    [void]$curs.Add($base)
    foreach ($k in $script:Portfolio.Keys) { $c = Get-InstrumentCurrency ([string]$k); if ($c) { [void]$curs.Add($c) } }
    $fxUrls = Get-AnalysisFxUrls -Currencies @($curs) -From $from -P1 $p1 -P2 $p2 -Force $Force

    if (($urls.Count + $fxUrls.Count) -eq 0) {
        Update-AnalysisModel
    } else {
        $ac.Status.ForeColor = $script:Pal.Muted
        $ac.Status.Text = "Lade Kursverläufe ({0}) und Wechselkurse ({1}) seit {2} ..." -f $urls.Count, $fxUrls.Count, $fromD.ToString("dd.MM.yyyy")
        $ac.Reload.Enabled = $false
        Start-FetchJob -Urls (@($urls.Values) + @($fxUrls.Values)) -MaxConcurrency 4 -Context @{ Urls = $urls; Fx = $fxUrls; From = $from; P1 = $p1; P2 = $p2 } -OnComplete {
            param($Box, $Ctx)
            $failed = @()
            foreach ($s in @($Ctx.Urls.Keys)) {
                $h = ConvertFrom-YahooDailyHistory -Json $Box.Results[$Ctx.Urls[$s]]
                if ($null -ne $h) {
                    $script:AnaHist[$s] = @{ Hist = $h; At = (Get-Date); From = $Ctx.From }
                    $old = $script:SplitCache[$s]
                    if ($null -eq $old -or -not [bool]$old.Full) { $script:SplitCache[$s] = @{ Splits = @($h.Splits); ToYear = (Get-Date).Year } }
                } else {
                    $failed += $s
                }
            }
            Save-FxHistResults -Box $Box -FxUrls $Ctx.Fx -From $Ctx.From
            if ($null -eq $script:AnaCtl) { return }
            $script:AnaCtl.Failed = $failed
            $curs2 = @()
            foreach ($s in @($script:AnaHist.Keys)) { $curs2 += [string]$script:AnaHist[$s].Hist.Currency }
            $more = Get-AnalysisFxUrls -Currencies $curs2 -From $Ctx.From -P1 $Ctx.P1 -P2 $Ctx.P2
            if ($more.Count -eq 0) { Update-AnalysisModel; return }
            Start-FetchJob -Urls @($more.Values) -MaxConcurrency 3 -Context @{ Fx = $more; From = $Ctx.From } -OnComplete {
                param($Box2, $Ctx2)
                Save-FxHistResults -Box $Box2 -FxUrls $Ctx2.Fx -From $Ctx2.From
                if ($null -ne $script:AnaCtl) { Update-AnalysisModel }
            }
        }
    }

    # Profiles (sector / country) at most every 30 days; the same request also
    # brings the earnings / dividend dates (v4.2), those are kept for a day
    $pSyms = @($script:Portfolio.Keys | ForEach-Object { ([string]$_).ToUpper() })
    $stale = @($pSyms | Where-Object { $Force -or (Test-ProfileStale -Entry $script:Profiles[$_]) })
    $evStale = @($pSyms | Where-Object { $Force -or (Test-EventsStale -Entry $script:Events[$_]) })
    $after = { if ($null -ne $script:AnaCtl) { Update-AnalysisAllocation; Update-AnalysisDividends } }
    if ($stale.Count -gt 0) {
        Start-ProfileJob -Symbols (@($stale) + @($evStale)) -OnComplete $after
    } elseif ($evStale.Count -gt 0 -and -not $script:WorkerShared.CrumbFailed) {
        Start-ProfileJob -Symbols $evStale -EventsOnly $true -OnComplete $after
    }
    Start-DividendLoad -Force $Force
}

function Update-AnalysisModel {
    $ac = $script:AnaCtl
    if ($null -eq $ac) { return }
    $ac.Reload.Enabled = $true
    $base = Get-AnalysisBase
    $txs = $script:Transactions.ToArray()
    $hist = Get-FxHistoryMap
    $fb = @{}
    foreach ($k in $script:FxFromEur.Keys) { $fb[$k] = [double]$script:FxFromEur[$k] }
    $splits = Get-SplitMap
    $bsym = [string]$script:Config.AnalysisBenchmark
    $prices = @{}
    foreach ($s in @($script:AnaHist.Keys)) { if ($s -ne $bsym -or $script:Portfolio.ContainsKey($s)) { $prices[$s] = $script:AnaHist[$s].Hist } }
    $bench = if ($bsym -and $null -ne $script:AnaHist[$bsym]) { $script:AnaHist[$bsym].Hist } else { $null }

    $ledger = Get-PortfolioLedger -Transactions $txs -Base $base -History $hist -FallbackFromEur $fb -Splits $splits
    $series = $null
    try { $series = Get-PortfolioValueSeries -Transactions $txs -Prices $prices -Base $base -History $hist -FallbackFromEur $fb -Benchmark $bench }
    catch { Write-WidgetLog "Value history failed: $($_.Exception.Message)" "ERROR" }
    $uncovered = @(Get-UncoveredPositions -Portfolio $script:Portfolio -Ledger $ledger)
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    $rows = New-Object System.Collections.Generic.List[PSObject]
    $allD = New-Object System.Collections.Generic.List[string]
    $allA = New-Object System.Collections.Generic.List[double]
    $benchD = New-Object System.Collections.Generic.List[string]
    $benchA = New-Object System.Collections.Generic.List[double]
    $tot = @{ Value = 0.0; Cost = 0.0; Unreal = 0.0; Real = 0.0; Div = 0.0; Bought = 0.0; Booked = 0.0 }
    $symSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $ledger.Keys) { [void]$symSet.Add($k) }
    foreach ($k in $script:Portfolio.Keys) { [void]$symSet.Add(([string]$k).ToUpper()) }
    foreach ($sym in @($symSet | Sort-Object)) {
        $L = $ledger[$sym]
        $pf = $script:Portfolio[$sym]
        $pfSh = if ($null -ne $pf) { [double]$pf.Shares } else { 0.0 }
        $px = Get-AnalysisPriceNow -Sym $sym -Base $base
        $hasPx = -not [double]::IsNaN($px)
        $value = if ($hasPx) { $pfSh * $px } else { 0.0 }
        $r = [PSCustomObject]@{ Ticker = $sym; Since = ""; Shares = $pfSh; Value = $value; Cost = 0.0; Unreal = 0.0; Real = 0.0; Div = 0.0; Total = 0.0; Pct = [double]::NaN; Xirr = [double]::NaN; NoPrice = (-not $hasPx); NoBookings = ($null -eq $L) }
        if ($null -ne $L) {
            $bookedVal = if ($hasPx) { $L.Shares * $px } else { 0.0 }
            $r.Since = $L.FirstDate
            $r.Cost = $L.Cost
            $r.Unreal = if ($L.Shares -gt 0 -and $hasPx) { $bookedVal - $L.Cost } else { 0.0 }
            $r.Real = $L.Realized
            $r.Div = $L.Dividends
            $r.Total = $r.Unreal + $r.Real + $r.Div
            if ($L.Bought -gt 0) { $r.Pct = $r.Total / $L.Bought * 100.0 }
            $cd = @($L.CfDates); $ca = @($L.CfAmounts); $ck = @($L.CfKinds)
            for ($i = 0; $i -lt $cd.Count; $i++) {
                $allD.Add($cd[$i]); $allA.Add($ca[$i])
                if ($ck[$i] -ne "D") { $benchD.Add($cd[$i]); $benchA.Add($ca[$i]) }
            }
            if ($bookedVal -gt 0) { $cd += $today; $ca += $bookedVal }
            $span = ([DateTime]::ParseExact($today, "yyyy-MM-dd", $inv) - [DateTime]::ParseExact($L.FirstDate, "yyyy-MM-dd", $inv)).TotalDays
            if ($span -ge 30) { $r.Xirr = Get-Xirr -Dates ([string[]]$cd) -Amounts ([double[]]$ca) }
            $tot.Bought += $L.Bought
            $tot.Booked += $bookedVal
        } elseif ($null -ne $pf) {
            # no bookings: cost from the portfolio editor at today's FX
            $r.Cost = Convert-CurrencyValue -Amount ($pfSh * [double]$pf.AvgPrice) -FromCurrency ([string]$pf.Currency) -ToCurrency $base
            $r.Unreal = if ($hasPx) { $value - $r.Cost } else { 0.0 }
            $r.Total = $r.Unreal
            if ($r.Cost -gt 0) { $r.Pct = $r.Total / $r.Cost * 100.0 }
        }
        $tot.Value += $r.Value; $tot.Cost += $r.Cost; $tot.Unreal += $r.Unreal; $tot.Real += $r.Real; $tot.Div += $r.Div
        $rows.Add($r)
    }
    $totXirr = [double]::NaN
    if ($allD.Count -gt 0 -and $tot.Booked -gt 0) {
        $d = @($allD.ToArray()) + $today
        $a = @($allA.ToArray()) + $tot.Booked
        $minD = ($d | Sort-Object)[0]
        if (([DateTime]::ParseExact($today, "yyyy-MM-dd", $inv) - [DateTime]::ParseExact($minD, "yyyy-MM-dd", $inv)).TotalDays -ge 30) {
            $totXirr = Get-Xirr -Dates ([string[]]$d) -Amounts ([double[]]$a)
        }
    }
    $benchXirr = [double]::NaN
    $benchVal = [double]::NaN
    if ($null -ne $series -and $null -ne $series.Bench -and $benchD.Count -gt 0) {
        $last = $series.Dates.Count - 1
        $benchVal = $series.Bench[$last]
        $d = @($benchD.ToArray()) + $series.Dates[$last]
        $a = @($benchA.ToArray()) + $benchVal
        $minD = ($d | Sort-Object)[0]
        if ($benchVal -gt 0 -and ([DateTime]::ParseExact($series.Dates[$last], "yyyy-MM-dd", $inv) - [DateTime]::ParseExact($minD, "yyyy-MM-dd", $inv)).TotalDays -ge 30) {
            $benchXirr = Get-Xirr -Dates ([string[]]$d) -Amounts ([double[]]$a)
        }
    }
    $tot.Total = $tot.Unreal + $tot.Real + $tot.Div
    $tot.Pct = if ($tot.Bought -gt 0) { $tot.Total / $tot.Bought * 100.0 } else { [double]::NaN }
    $ac.Model = [PSCustomObject]@{
        Base = $base; Series = $series; Rows = $rows.ToArray(); Total = $tot; TotalXirr = $totXirr
        BenchXirr = $benchXirr; BenchValue = $benchVal; Uncovered = $uncovered
    }
    Update-AnalysisPerf
    Update-AnalysisReturns
    Update-AnalysisAllocation
    Update-AnalysisDividends
    Update-AnalysisRisk
    Update-AnalysisTarget
    Update-AnalysisHeat
    Update-AnalysisContrib
    if ([string]$ac.Page -eq "Bench") { Update-AnalysisBench }
}

function Format-Signed {
    param([double]$V, [string]$Fmt = "N2")
    if ([double]::IsNaN($V)) { return "-" }
    $s = $V.ToString($Fmt)
    if ($V -gt 0) { return "+" + $s }
    return $s
}

function Update-AnalysisPerf {
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.Model) { return }
    $m = $ac.Model
    $b = $m.Base
    $notes = New-Object System.Collections.Generic.List[string]
    if (@($m.Uncovered).Count -gt 0) {
        $notes.Add("Ohne (vollständige) Buchungen, nicht in der Kurve: " + ((@($m.Uncovered) | ForEach-Object { "{0} ({1:N4} von {2:N4} Stk)" -f $_.Ticker, $_.Missing, $_.Shares }) -join ", ") + " - Käufe über 'Transaktion...' buchen.")
    }
    if (@($ac.Failed).Count -gt 0) { $notes.Add("Kein Kursverlauf von Yahoo: " + (@($ac.Failed) -join ", ")) }
    $sr = $m.Series
    if ($null -eq $sr) {
        $ac.Sum.Text = if ($script:Transactions.Count -eq 0) { "Noch keine Buchungen. Die Wertentwicklung wird aus deinen Käufen und Verkäufen berechnet: Portfolio > 'Transaktion...'." } else { "Keine Kursverläufe für die gebuchten Ticker verfügbar." }
        $ac.Sum.ForeColor = $script:Pal.Muted
    } else {
        $last = $sr.Dates.Count - 1
        $v = $sr.Value[$last]; $i = $sr.Invested[$last]; $d = $sr.Dividends[$last]
        $res = $v + $d - $i
        $i0 = Get-SeriesWindowStart -Dates $sr.Dates -Range ([string]$script:Config.AnalysisRange)
        $win = ($sr.Value[$last] - $sr.Value[$i0]) - ($sr.Invested[$last] - $sr.Invested[$i0]) + ($sr.Dividends[$last] - $sr.Dividends[$i0])
        $ld = [DateTime]::ParseExact($sr.Dates[$last], "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture).ToString("dd.MM.yyyy")
        $lines = @(
            ("Depotwert {0:N2} {1}   Netto investiert {2:N2}   Dividenden {3:N2}   (Schlusskurse vom {4})" -f $v, $b, $i, $d, $ld)
            ("Ergebnis {0} {1}   Rendite p.a. (XIRR) {2} %   Im Zeitraum {3}: {4} {1}" -f (Format-Signed $res), $b, (Format-Signed ($m.TotalXirr * 100) "N1"), (Get-RangeLabel ([string]$script:Config.AnalysisRange)), (Format-Signed $win))
        )
        if (-not [double]::IsNaN($m.BenchValue)) {
            $diff = ($m.TotalXirr - $m.BenchXirr) * 100
            $verdict = if ([double]::IsNaN($diff)) { "" } elseif ($diff -ge 0) { "   -> Depot {0:N1} Prozentpunkte p.a. besser" -f $diff } else { "   -> Depot {0:N1} Prozentpunkte p.a. schlechter" -f (-$diff) }
            $lines += ("Benchmark {0}: gleiche Käufe/Verkäufe wären heute {1:N2} {2} wert, XIRR {3} %{4}" -f $script:Config.AnalysisBenchmark, $m.BenchValue, $b, (Format-Signed ($m.BenchXirr * 100) "N1"), $verdict)
        }
        if ($sr.Approx) { $notes.Add("Teilweise mit aktuellem statt historischem Wechselkurs gerechnet (Verlauf fehlte).") }
        $ac.Sum.Text = ($lines -join "`r`n")
        $ac.Sum.ForeColor = if ($res -ge 0) { $colGreen } else { $colRed }
    }
    $ac.Status.Text = if ($notes.Count -gt 0) { $notes -join "  |  " } else { "Stand {0}. Gebuchte Positionen, Basiswährung {1}." -f (Get-Date).ToString("HH:mm"), $b }
    $ac.Status.ForeColor = if ($notes.Count -gt 0) { $script:Pal.Warn } else { $script:Pal.Muted }
    Set-DynTip $ac.Status ($ac.Status.Text)
    $ac.Chart.Invalidate()
}

function Get-RangeLabel {
    param([string]$R)
    switch ($R) { "6M" { "6 Monate" } "1Y" { "1 Jahr" } "3Y" { "3 Jahre" } default { "gesamt" } }
}

function Update-AnalysisReturns {
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.Model) { return }
    $m = $ac.Model
    $g = $ac.RetGrid
    $g.SuspendLayout()
    $g.Rows.Clear()
    $sign = { param($Cell, [double]$V) if (-not [double]::IsNaN($V) -and [math]::Abs($V) -gt 0.004) { $Cell.Style.ForeColor = $(if ($V -ge 0) { $colGreen } else { $colRed }) } }
    foreach ($r in @($m.Rows | Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, Ticker)) {
        $since = if ($r.Since) { [DateTime]::ParseExact($r.Since, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture).ToString("dd.MM.yy") } elseif ($r.NoBookings) { "ohne Buch." } else { "" }
        $ri = $g.Rows.Add($r.Ticker, $since, $(if ($r.Shares -gt 0) { "{0:N4}" -f $r.Shares } else { "-" }), $(if ($r.NoPrice) { "kein Kurs" } else { "{0:N2}" -f $r.Value }),
            ("{0:N2}" -f $r.Cost), (Format-Signed $r.Unreal), (Format-Signed $r.Real), (Format-Signed $r.Div), (Format-Signed $r.Total),
            $(if ([double]::IsNaN($r.Pct)) { "-" } else { (Format-Signed $r.Pct "N1") + " %" }), $(if ([double]::IsNaN($r.Xirr)) { "-" } else { (Format-Signed ($r.Xirr * 100) "N1") + " %" }))
        $row = $g.Rows[$ri]
        foreach ($cn in @("Unreal", "Real", "Div", "Total")) { & $sign $row.Cells[$cn] ([double]$r.$cn) }
        & $sign $row.Cells["Pct"] ([double]$r.Pct)
        & $sign $row.Cells["Xirr"] ([double]$r.Xirr)
        if ($r.NoBookings) { $row.Cells["Since"].ToolTipText = "Keine Kauf-Buchungen: Einstand aus dem Portfolio-Editor (EK x Stück, heutiger Wechselkurs), kein XIRR" }
        if ($r.Shares -le 0) { $row.DefaultCellStyle.ForeColor = $script:Pal.Muted }
    }
    $t = $m.Total
    $ri = $g.Rows.Add("Summe", "", "", ("{0:N2}" -f $t.Value), ("{0:N2}" -f $t.Cost), (Format-Signed $t.Unreal), (Format-Signed $t.Real), (Format-Signed $t.Div), (Format-Signed $t.Total),
        $(if ([double]::IsNaN($t.Pct)) { "-" } else { (Format-Signed $t.Pct "N1") + " %" }), $(if ([double]::IsNaN($m.TotalXirr)) { "-" } else { (Format-Signed ($m.TotalXirr * 100) "N1") + " %" }))
    $row = $g.Rows[$ri]
    $row.DefaultCellStyle.Font = $fontBadge
    $row.DefaultCellStyle.BackColor = $script:Pal.Input
    foreach ($cn in @("Unreal", "Real", "Div", "Total")) { & $sign $row.Cells[$cn] ([double]$t.$cn) }
    & $sign $row.Cells["Xirr"] ([double]$m.TotalXirr)
    $g.ResumeLayout()
    $g.ClearSelection()
    $ac.RetNote.Text = "Beträge in {0}. Einstand = gleitender Durchschnitt zum Wechselkurs am Kauftag (inkl. Kaufgebühren), Splits berücksichtigt. Gesamt % bezieht sich auf alle Käufe. XIRR ab 30 Tagen Haltedauer." -f $m.Base
}

function Get-AllocationItems {
    # Current positions (value > 0) keyed by the chosen dimension
    $ac = $script:AnaCtl
    $out = @()
    if ($null -eq $ac -or $null -eq $ac.Model) { return $out }
    foreach ($r in @($ac.Model.Rows)) {
        if ($r.Shares -le 0 -or $r.Value -le 0) { continue }
        $prof = Get-EffectiveProfile $script:Profiles[$r.Ticker]
        $key = switch ([string]$ac.Dim) {
            "Currency" { Get-InstrumentCurrency $r.Ticker }
            "Sector"   { $prof.Sector }
            "Country"  { $prof.Country }
            default    { $r.Ticker }
        }
        $out += [PSCustomObject]@{ Key = $key; Value = $r.Value }
    }
    # v5.0: cash account as its own slice (position / currency view)
    if ([string]$ac.Dim -in @("", "Position", "Currency")) {
        $ci = Get-CashInfo -Currency ([string]$ac.Model.Base)
        if ($null -ne $ci -and $ci.Display -gt 0) { $out += [PSCustomObject]@{ Key = $(if ([string]$ac.Dim -eq "Currency") { $ci.Currency } else { "Cash" }); Value = $ci.Display } }
    }
    return $out
}

function Update-AnalysisAllocation {
    $ac = $script:AnaCtl
    if ($null -eq $ac) { return }
    $ac.Groups = @(Get-AllocationBreakdown -Items @(Get-AllocationItems))
    $thr = [double]$script:Config.ConcentrationWarnPct
    $warn = @(Get-ConcentrationWarnings -Groups $ac.Groups -ThresholdPct $thr)
    $dimName = switch ([string]$ac.Dim) { "Currency" { "Währung" } "Sector" { "Sektor" } "Country" { "Land" } default { "Position" } }
    if ($warn.Count -gt 0) {
        $ac.AllocWarn.ForeColor = $script:Pal.Warn
        $ac.AllocWarn.Text = "Klumpenrisiko ({0} über {1:N0} %): {2}" -f $dimName, $thr, ((@($warn) | ForEach-Object { "{0} {1:N1} %" -f $_.Key, $_.Pct }) -join ", ")
    } else {
        $ac.AllocWarn.ForeColor = $script:Pal.Muted
        $ac.AllocWarn.Text = if (@($ac.Groups).Count -gt 0) { "Keine {0} über {1:N0} % des Depots." -f $dimName, $thr } else { "Keine Positionen mit Kurs." }
    }
    foreach ($k in $ac.DimButtons.Keys) {
        $bt = $ac.DimButtons[$k]
        if ($k -eq $ac.Dim) { Style-FlatButton -Btn $bt -BgColor $script:Pal.Accent -FgColor $script:Pal.HeaderBg -BorderColor $script:Pal.Accent }
        else { Style-FlatButton -Btn $bt -BgColor $script:Pal.Card -FgColor $script:Pal.Text -BorderColor $script:Pal.Border }
    }
    $ac.Bars.Invalidate()

    # profile grid (skipped while a cell is being edited)
    $pg = $ac.ProfGrid
    if ($pg.IsCurrentCellInEditMode) { return }
    $pg.Rows.Clear()
    foreach ($r in @($ac.Model.Rows | Where-Object { $_.Shares -gt 0 } | Sort-Object -Property Ticker)) {
        $en = $script:Profiles[$r.Ticker]
        $ef = Get-EffectiveProfile $en
        $name = if ($null -ne $en -and $en.Name) { [string]$en.Name } else { "" }
        $src = "{0} / {1}" -f $(if ($ef.SectorSource) { $ef.SectorSource } else { "-" }), $(if ($ef.CountrySource) { $ef.CountrySource } else { "-" })
        $ri = $pg.Rows.Add($r.Ticker, $name, $ef.Sector, $ef.Country, $src)
        if ($ef.SectorSource -eq "manuell") { $pg.Rows[$ri].Cells["Sector"].Style.ForeColor = $script:Pal.Accent }
        if ($ef.CountrySource -eq "manuell") { $pg.Rows[$ri].Cells["Country"].Style.ForeColor = $script:Pal.Accent }
    }
    $pg.ClearSelection()
}

function Draw-AnalysisChart {
    param([System.Drawing.Graphics]$g, [int]$W, [int]$H)
    $ac = $script:AnaCtl
    $p = $script:Pal
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear($p.Card)
    $brMuted = New-Object System.Drawing.SolidBrush($p.Muted)
    $brText = New-Object System.Drawing.SolidBrush($p.Text)
    $amber = $script:Pal.Warn
    try {
        $m = if ($null -ne $ac) { $ac.Model } else { $null }
        if ($null -eq $m -or $null -eq $m.Series) {
            $msg = if ($null -eq $m) { "Lade Daten ..." } else { "Keine Wertentwicklung verfügbar (siehe unten)." }
            $sz = $g.MeasureString($msg, $fontUi)
            $g.DrawString($msg, $fontUi, $brMuted, [float](($W - $sz.Width) / 2), [float](($H - $sz.Height) / 2))
            if ($null -ne $ac) { $ac.Geom = $null }
            return
        }
        $sr = $m.Series
        $i1 = $sr.Dates.Count - 1
        $i0 = Get-SeriesWindowStart -Dates $sr.Dates -Range ([string]$script:Config.AnalysisRange)
        if (($i1 - $i0) -lt 1) { $i0 = [math]::Max(0, $i1 - 1) }
        $lines = @(@{ V = $sr.Value; C = $p.Accent; W = 2.0; Dash = $false; N = "Depotwert" })
        if ([bool]$script:Config.AnalysisShowInvested) { $lines += @{ V = $sr.Invested; C = $p.Muted; W = 1.3; Dash = $true; N = "Netto investiert" } }
        if ([bool]$script:Config.AnalysisShowBench -and $null -ne $sr.Bench) { $lines += @{ V = $sr.Bench; C = $amber; W = 1.4; Dash = $false; N = ("Benchmark " + $script:Config.AnalysisBenchmark) } }
        $min = [double]::MaxValue; $max = [double]::MinValue
        foreach ($ln in $lines) { for ($i = $i0; $i -le $i1; $i++) { $v = $ln.V[$i]; if ($v -lt $min) { $min = $v }; if ($v -gt $max) { $max = $v } } }
        if (($max - $min) -lt 1e-6) { $max += 1; $min -= 1 }
        $pad = ($max - $min) * 0.06
        $min = [math]::Max(0, $min - $pad); $max += $pad
        $L = S 74; $R = $W - (S 12); $T = S 24; $B = $H - (S 24)
        if (($R - $L) -lt 50 -or ($B - $T) -lt 40) { return }
        $toX = { param([int]$I) $L + ($R - $L) * (($I - $i0) / [double]($i1 - $i0)) }
        $toY = { param([double]$V) $B - ($B - $T) * (($V - $min) / ($max - $min)) }
        $gridPen = New-Object System.Drawing.Pen($p.Grid, 1)
        try {
            for ($k = 0; $k -le 4; $k++) {
                $v = $min + ($max - $min) * $k / 4.0
                $y = [float](& $toY $v)
                $g.DrawLine($gridPen, [float]$L, $y, [float]$R, $y)
                $lbl = "{0:N0}" -f $v
                $sz = $g.MeasureString($lbl, $fontAxis)
                $g.DrawString($lbl, $fontAxis, $brMuted, [float]($L - $sz.Width - (S 4)), [float]($y - $sz.Height / 2))
            }
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            $nx = [math]::Min(6, $i1 - $i0 + 1)
            for ($k = 0; $k -lt $nx; $k++) {
                $ix = [int][math]::Round($i0 + ($i1 - $i0) * $k / [math]::Max(1, $nx - 1))
                $x = [float](& $toX $ix)
                $lbl = [DateTime]::ParseExact($sr.Dates[$ix], "yyyy-MM-dd", $inv).ToString("dd.MM.yy")
                $sz = $g.MeasureString($lbl, $fontAxis)
                $lx = [math]::Max([float]$L, [math]::Min([float]($R - $sz.Width), [float]($x - $sz.Width / 2)))
                $g.DrawString($lbl, $fontAxis, $brMuted, [float]$lx, [float]($B + (S 5)))
            }
        } finally { $gridPen.Dispose() }

        $lx = [float]$L
        foreach ($ln in $lines) {
            $pen = New-Object System.Drawing.Pen($ln.C, [float]($ln.W * $script:DpiScale))
            try {
                if ($ln.Dash) { $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash }
                $pts = New-Object System.Drawing.PointF[] ($i1 - $i0 + 1)
                for ($i = $i0; $i -le $i1; $i++) { $pts[$i - $i0] = New-Object System.Drawing.PointF([float](& $toX $i), [float](& $toY $ln.V[$i])) }
                if ($pts.Count -ge 2) { $g.DrawLines($pen, $pts) }
                $g.DrawLine($pen, $lx, [float](S 11), [float]($lx + (S 16)), [float](S 11))
                $g.DrawString($ln.N, $fontAxis, $brText, [float]($lx + (S 20)), [float](S 4))
                $lx += (S 28) + $g.MeasureString($ln.N, $fontAxis).Width
            } finally { $pen.Dispose() }
        }
        $ac.Geom = @{ L = $L; R = $R; T = $T; B = $B; I0 = $i0; I1 = $i1 }

        # hover: vertical line + values box
        $hi = [int]$ac.HoverIdx
        if ($hi -ge $i0 -and $hi -le $i1) {
            $x = [float](& $toX $hi)
            $hp = New-Object System.Drawing.Pen($p.Muted, 1)
            $hp.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
            $g.DrawLine($hp, $x, [float]$T, $x, [float]$B)
            $hp.Dispose()
            $txt = @([DateTime]::ParseExact($sr.Dates[$hi], "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture).ToString("ddd dd.MM.yyyy"))
            foreach ($ln in $lines) { $txt += ("{0}: {1:N2}" -f $ln.N, $ln.V[$hi]) }
            $txt += ("Ergebnis: {0}" -f (Format-Signed ($sr.Value[$hi] + $sr.Dividends[$hi] - $sr.Invested[$hi])))
            $body = $txt -join "`n"
            $sz = $g.MeasureString($body, $fontAxis)
            $bx = if (($x + (S 10) + $sz.Width) -lt $R) { $x + (S 10) } else { $x - (S 10) - $sz.Width }
            $by = [float]($T + (S 4))
            $bg = New-Object System.Drawing.SolidBrush($p.Input)
            $g.FillRectangle($bg, [float]($bx - 4), [float]($by - 3), [float]($sz.Width + 8), [float]($sz.Height + 6))
            $bg.Dispose()
            $g.DrawString($body, $fontAxis, $brText, [float]$bx, $by)
        }
    } finally {
        $brMuted.Dispose(); $brText.Dispose()
    }
}

function Draw-AllocationBars {
    param([System.Drawing.Graphics]$g, [int]$W, [int]$H)
    $ac = $script:AnaCtl
    $p = $script:Pal
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear($p.Card)
    $brT = New-Object System.Drawing.SolidBrush($p.Text)
    $brM = New-Object System.Drawing.SolidBrush($p.Muted)
    $brA = New-Object System.Drawing.SolidBrush($p.Accent)
    $brW = New-Object System.Drawing.SolidBrush($script:Pal.Warn)
    try {
        $groups = if ($null -ne $ac) { @($ac.Groups) } else { @() }
        if ($groups.Count -eq 0) {
            $g.DrawString("Keine Daten.", $fontUi, $brM, [float](S 10), [float](S 10))
            return
        }
        $thr = [double]$script:Config.ConcentrationWarnPct
        $rowH = S 24
        $labW = S 150
        $pctW = S 120
        $x0 = $labW + (S 8)
        $x1 = $W - $pctW
        $maxPct = [math]::Max(1.0, (@($groups | ForEach-Object { [double]$_.Pct }) | Sort-Object -Descending)[0])
        $y = S 8
        foreach ($gr in $groups) {
            if (($y + $rowH) -gt $H) {
                $g.DrawString(("... und {0} weitere" -f ($groups.Count - [array]::IndexOf($groups, $gr))), $fontUi, $brM, [float](S 8), [float]$y)
                break
            }
            $lbl = [string]$gr.Key
            if ($lbl.Length -gt 22) { $lbl = $lbl.Substring(0, 21) + "…" }
            $g.DrawString($lbl, $fontUi, $brT, [float](S 8), [float]($y + (S 4)))
            $bw = [math]::Max(2.0, ($x1 - $x0) * ([double]$gr.Pct / $maxPct))
            $br = if ([double]$gr.Pct -gt $thr) { $brW } else { $brA }
            $g.FillRectangle($br, [float]$x0, [float]($y + (S 4)), [float]$bw, [float]($rowH - (S 9)))
            $g.DrawString(("{0,5:N1} %  {1:N0}" -f $gr.Pct, $gr.Value), $fontAxis, $brM, [float]($x1 + (S 6)), [float]($y + (S 5)))
            $y += $rowH
        }
        # threshold marker
        if ($thr -le $maxPct) {
            $tx = [float]($x0 + ($x1 - $x0) * ($thr / $maxPct))
            $pen = New-Object System.Drawing.Pen($script:Pal.Warn, 1)
            $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
            $g.DrawLine($pen, $tx, [float](S 4), $tx, [float]([math]::Min($H - 2, $y)))
            $pen.Dispose()
        }
    } finally {
        $brT.Dispose(); $brM.Dispose(); $brA.Dispose(); $brW.Dispose()
    }
}

# ------------------------------------------------------------------------------
# Dividends page (v4.2): history per share from the chart events (5 years,
# monthly bars), dates from quoteSummary where available, otherwise estimated
# ------------------------------------------------------------------------------
$script:DivHist = @{}     # symbol -> @{ Divs; Currency; At; Failed }

function Start-DividendLoad {
    param([bool]$Force = $false)
    $urls = @{}
    foreach ($k in @($script:Portfolio.Keys)) {
        $u = ([string]$k).ToUpper()
        if ([double]$script:Portfolio[$k].Shares -le 0) { continue }
        $h = $script:DivHist[$u]
        $fresh = ($null -ne $h -and ((Get-Date) - $h.At).TotalHours -lt $(if ($h.Failed) { 0.5 } else { 6 }))
        if ($Force -or -not $fresh) {
            $urls[$u] = "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval=1mo&range=5y&events=div" -f [Uri]::EscapeDataString($u)
        }
    }
    if ($urls.Count -eq 0) { Update-AnalysisDividends; return }
    Start-FetchJob -Urls @($urls.Values) -MaxConcurrency 4 -Context @{ Urls = $urls } -OnComplete {
        param($Box, $Ctx)
        foreach ($s in @($Ctx.Urls.Keys)) {
            $h = ConvertFrom-YahooDailyHistory -Json $Box.Results[$Ctx.Urls[$s]]
            if ($null -ne $h) { $script:DivHist[$s] = @{ Divs = @($h.Dividends); Currency = [string]$h.Currency; At = (Get-Date); Failed = $false } }
            else { $script:DivHist[$s] = @{ Divs = @(); Currency = ""; At = (Get-Date); Failed = $true } }
        }
        if ($null -ne $script:AnaCtl) { Update-AnalysisDividends }
    }
}

function Update-AnalysisDividends {
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.DivGrid) { return }
    $base = Get-AnalysisBase
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $amber = $script:Pal.Warn
    $g = $ac.DivGrid
    $g.Rows.Clear()
    $items = New-Object System.Collections.Generic.List[PSObject]
    $tot = @{ Income = 0.0; Value = 0.0; Cost = 0.0; Loading = 0; Payers = 0 }
    foreach ($sym in @($script:Portfolio.Keys | ForEach-Object { ([string]$_).ToUpper() } | Sort-Object)) {
        $pf = $script:Portfolio[$sym]
        $sh = [double]$pf.Shares
        if ($sh -le 0) { continue }
        $dh = $script:DivHist[$sym]
        $ev = $script:Events[$sym]
        $cur = if ($null -ne $dh -and $dh.Currency) { [string]$dh.Currency } else { Get-InstrumentCurrency $sym }
        if (-not $cur) { $cur = [string]$pf.Currency }
        $pxB = Get-AnalysisPriceNow -Sym $sym -Base $base
        if (-not [double]::IsNaN($pxB)) { $tot.Value += $sh * $pxB }
        $tot.Cost += Convert-CurrencyValue -Amount ($sh * [double]$pf.AvgPrice) -FromCurrency ([string]$pf.Currency) -ToCurrency $base

        $st = $null; $proj = @()
        if ($null -ne $dh -and -not $dh.Failed) {
            $st = Get-DividendStats -Dividends $dh.Divs -AsOf $today
            if ($null -ne $st) { $proj = @(Get-DividendProjection -Dividends $dh.Divs -AsOf $today -Stats $st) }
        }
        if ($null -eq $dh) { $tot.Loading++ }
        $incB = 0.0
        foreach ($pj in $proj) {
            $v = Convert-CurrencyValue -Amount ([double]$pj.Amount * $sh) -FromCurrency $cur -ToCurrency $base
            $incB += $v
            $items.Add([PSCustomObject]@{ Date = $pj.Date; Value = $v })
        }
        $tot.Income += $incB
        if ($incB -gt 0) { $tot.Payers++ }

        $annual = if ($null -ne $st) { [double]$st.Annual } else { 0.0 }
        $pxI = Get-AnalysisPriceNow -Sym $sym -Base $cur
        $avgI = Convert-CurrencyValue -Amount ([double]$pf.AvgPrice) -FromCurrency ([string]$pf.Currency) -ToCurrency $cur
        $yld = if ($annual -gt 0 -and -not [double]::IsNaN($pxI) -and $pxI -gt 0) { "{0:N2}%" -f ($annual / $pxI * 100.0) } else { "-" }
        $yoc = if ($annual -gt 0 -and $avgI -gt 0) { "{0:N2}%" -f ($annual / $avgI * 100.0) } else { "-" }
        $rhythm = if ($null -eq $dh) { "lädt ..." } elseif ($dh.Failed) { "n/v" } elseif ($null -eq $st) { "keine" } elseif ($st.Stopped) { "ausgesetzt?" } else { [string]$st.FrequencyLabel }
        $lastTxt = if ($null -ne $st) { "{0:N4} {1}" -f $st.Last, $cur } else { "-" }
        $annTxt = if ($annual -gt 0) { "{0:N4} {1}" -f $annual, $cur } else { "-" }
        $incTxt = if ($incB -gt 0) { "{0:N2} {1}" -f $incB, $base } else { "-" }
        $exTxt = "-"; $exExact = $false
        if ($null -ne $ev -and $ev.ExDividendDate -and [string]::CompareOrdinal([string]$ev.ExDividendDate, $today) -ge 0) { $exTxt = Format-IsoDateDe $ev.ExDividendDate; $exExact = $true }
        elseif ($null -ne $st -and $st.NextEx) { $exTxt = "~" + (Format-IsoDateDe $st.NextEx) }
        $payTxt = if ($null -ne $ev -and $ev.DividendDate -and [string]::CompareOrdinal([string]$ev.DividendDate, $today) -ge 0) { Format-IsoDateDe $ev.DividendDate } else { "-" }
        $earnTxt = "-"
        if ($null -ne $ev -and $ev.EarningsDate -and [string]::CompareOrdinal([string]$ev.EarningsDate, $today) -ge 0) {
            $earnTxt = Format-IsoDateDe $ev.EarningsDate
            if ($ev.EarningsEnd -and $ev.EarningsEnd -ne $ev.EarningsDate) { $earnTxt += " - " + (Format-IsoDateDe $ev.EarningsEnd) }
        }
        $ri = $g.Rows.Add($sym, $rhythm, $lastTxt, $annTxt, $yld, $yoc, $incTxt, $exTxt, $payTxt, $earnTxt)
        $row = $g.Rows[$ri]
        if (-not $exExact -and $exTxt -ne "-") { $row.Cells["Ex"].Style.ForeColor = $script:Pal.Muted; $row.Cells["Ex"].ToolTipText = "Geschätzt aus dem bisherigen Rhythmus (~). Genaues Datum kommt von Yahoo, sobald angekündigt." }
        if ($null -ne $st -and $st.Stopped) { $row.Cells["Freq"].Style.ForeColor = $amber; $row.Cells["Freq"].ToolTipText = "Seit {0} keine Zahlung mehr - gekürzt oder ausgesetzt? Nicht in der Prognose." -f (Format-IsoDateDe $st.LastDate) }
        if ($null -ne $st) { $row.Cells["Last"].ToolTipText = "Letzte Dividende am {0} (Ex-Tag), {1} Zahlungen in 12 Monaten" -f (Format-IsoDateDe $st.LastDate), $st.Count12 }
        $eb = Get-TickerEarningsBadge $sym
        if ($null -ne $eb) { $row.Cells["Earn"].Style.ForeColor = $amber; $row.Cells["Earn"].ToolTipText = "Quartalszahlen {0}" -f $eb.Text }
    }
    $ac.DivBuckets = @(Get-MonthlyBuckets -Items $items.ToArray() -AsOf $today)
    $ac.DivBase = $base

    # received this year (bookings, gross, in base)
    $recv = [double]::NaN
    try {
        $fb = @{}
        foreach ($k in $script:FxFromEur.Keys) { $fb[$k] = [double]$script:FxFromEur[$k] }
        $rep = Get-RealizedReport -Transactions $script:Transactions.ToArray() -Year (Get-Date).Year -Base $base -History (Get-FxHistoryMap) -FallbackFromEur $fb -Splits (Get-SplitMap)
        $recv = [double]$rep.DividendsGross
    } catch { Write-WidgetLog "Dividends received: $($_.Exception.Message)" "WARN" }

    $ac.DivForecast = [double]$tot.Income
    $yP = if ($tot.Value -gt 0) { "{0:N2} %" -f ($tot.Income / $tot.Value * 100.0) } else { "-" }
    $yC = if ($tot.Cost -gt 0) { "{0:N2} %" -f ($tot.Income / $tot.Cost * 100.0) } else { "-" }
    $rTxt = if ([double]::IsNaN($recv)) { "-" } else { "{0:N2} {1}" -f $recv, $base }
    $ac.DivSum.Text = ("Erwartet nächste 12 Monate: {0:N2} {1}  (≈ {2:N2} {1} / Monat)   Rendite: {3}   auf Einstand: {4}`r`nErhalten {5} (gebucht): {6}   Zahler: {7} von {8} Positionen{9}" -f
        $tot.Income, $base, ($tot.Income / 12.0), $yP, $yC, (Get-Date).Year, $rTxt, $tot.Payers, $g.Rows.Count, $(if ($tot.Loading -gt 0) { "   (lade Dividenden ...)" } else { "" }))
    $ac.DivBars.Invalidate()
}

function Draw-DividendBars {
    param([System.Drawing.Graphics]$g, [int]$W, [int]$H)
    $ac = $script:AnaCtl
    $p = $script:Pal
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear($p.Card)
    $brT = New-Object System.Drawing.SolidBrush($p.Text)
    $brM = New-Object System.Drawing.SolidBrush($p.Muted)
    $brA = New-Object System.Drawing.SolidBrush($p.Accent)
    $sfC = New-Object System.Drawing.StringFormat
    $sfC.Alignment = [System.Drawing.StringAlignment]::Center
    try {
        $bk = if ($null -ne $ac) { @($ac.DivBuckets) } else { @() }
        $g.DrawString(("Erwartete Dividenden je Monat (nach Ex-Tag, brutto, {0})" -f $ac.DivBase), $fontUi, $brM, [float](S 8), [float](S 6))
        if ($bk.Count -eq 0) { return }
        $max = 0.0
        foreach ($b in $bk) { if ([double]$b.Value -gt $max) { $max = [double]$b.Value } }
        if ($max -le 0) { $g.DrawString("Keine Dividenden erwartet.", $fontUi, $brM, [float](S 8), [float](S 30)); return }
        $top = S 44; $bot = $H - (S 24)
        $slot = ($W - (S 16)) / [double]$bk.Count
        for ($i = 0; $i -lt $bk.Count; $i++) {
            $v = [double]$bk[$i].Value
            $x = (S 8) + $i * $slot
            $bh = if ($max -gt 0) { ($bot - $top) * $v / $max } else { 0 }
            if ($v -gt 0) {
                $g.FillRectangle($brA, [float]($x + $slot * 0.18), [float]($bot - $bh), [float]($slot * 0.64), [float][math]::Max(1, $bh))
                $g.DrawString(("{0:N0}" -f $v), $fontUi, $brT, (New-Object System.Drawing.RectangleF([float]$x, [float]($bot - $bh - (S 18)), [float]$slot, [float](S 18))), $sfC)
            }
            $g.DrawString([string]$bk[$i].Label, $fontUi, $brM, (New-Object System.Drawing.RectangleF([float]$x, [float]($bot + (S 4)), [float]$slot, [float](S 18))), $sfC)
        }
    } finally {
        $brT.Dispose(); $brM.Dispose(); $brA.Dispose(); $sfC.Dispose()
    }
}

# ==============================================================================
# v5.0: Analyse pages Risiko / Zielgewichte / Heatmap
# ==============================================================================
function Get-DepotKey { if ([string]$script:Config.ActiveDepot) { return [string]$script:Config.ActiveDepot } return "main" }

function Get-TargetWeights {
    $h = @{}
    $all = $script:Config.TargetWeights
    if ($null -eq $all) { return $h }
    $k = Get-DepotKey
    $mine = $all.PSObject.Properties[$k]
    if ($null -eq $mine -or $null -eq $mine.Value) { return $h }
    foreach ($pp in $mine.Value.PSObject.Properties) { $h[([string]$pp.Name).ToUpper()] = [double]$pp.Value }
    return $h
}

function Set-TargetWeights {
    param([hashtable]$Weights)
    if ($null -eq $script:Config.TargetWeights) { $script:Config.TargetWeights = [PSCustomObject]@{} }
    $o = [ordered]@{}
    foreach ($k in @($Weights.Keys | Sort-Object)) { $o[$k] = [double]$Weights[$k] }
    $script:Config.TargetWeights | Add-Member -NotePropertyName (Get-DepotKey) -NotePropertyValue ([PSCustomObject]$o) -Force
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
}

function Update-AnalysisRisk {
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.RiskGrid) { return }
    $g = $ac.RiskGrid
    $g.Rows.Clear()
    $sr = if ($null -ne $ac.Model) { $ac.Model.Series } else { $null }
    if ($null -eq $sr -or @($sr.Dates).Count -lt 10) {
        [void]$g.Rows.Add((Tr "Zu wenig Verlauf - erst ein paar Wochen Buchungen / Kurse"), "", "")
        $ac.CorrGrid.Columns.Clear()
        return
    }
    $dates = [string[]]$sr.Dates
    $st = Get-SeriesWindowStart -Dates $dates -Range ([string]$script:Config.AnalysisRange)
    $sub = { param($a) if ($null -eq $a) { return $null }; $arr = @($a); return [double[]]@($arr[$st..($arr.Count - 1)]) }
    $v = & $sub $sr.Value; $inv = & $sub $sr.Invested; $dv = & $sub $sr.Dividends; $bn = & $sub $sr.Bench
    $dd = [string[]]@($dates[$st..($dates.Count - 1)])
    $ppy = Get-PeriodsPerYear -Dates $dd
    $rf = [double]$script:Config.RiskFreePct
    $rP = [double[]]@(Get-FlowAdjustedReturns -Value $v -Invested $inv -Dividends $dv)
    $sP = Get-ReturnStats -Returns $rP -PeriodsPerYear $ppy -RiskFreePct $rf
    $hasB = ($null -ne $bn -and @($bn | Where-Object { $_ -gt 0 }).Count -gt 10)
    $rB = if ($hasB) { [double[]]@(Get-FlowAdjustedReturns -Value $bn -Invested $inv) } else { [double[]]@() }
    $sB = if ($hasB) { Get-ReturnStats -Returns $rB -PeriodsPerYear $ppy -RiskFreePct $rf } else { $null }
    $ac.RiskRange.Text = "{0} {1} - {2} ({3} {4}), Benchmark {5}" -f (Tr "Zeitraum"), $dd[0], $dd[$dd.Count - 1], $rP.Count, (Tr "Werte"), $(if ($hasB) { [string]$script:Config.AnalysisBenchmark } else { "-" })
    $fmtP = { param($x, [string]$f = "{0:+0.00;-0.00}%") if ($null -eq $x -or [double]::IsNaN([double]$x)) { "-" } else { $f -f [double]$x } }
    $dateAt = { param([int]$i) if ($i -ge 0 -and ($i + 1) -lt $dd.Count) { $dd[$i + 1] } else { "" } }
    $add = {
        param([string]$K, [string]$A, [string]$B, $ColorA = $null)
        $i = $g.Rows.Add((Tr $K), $A, $B)
        if ($null -ne $ColorA) { $g.Rows[$i].Cells["Depot"].Style.ForeColor = $ColorA }
    }
    & $add "Rendite p.a. (zeitgewichtet)" (& $fmtP $sP.AnnReturn) $(if ($hasB) { & $fmtP $sB.AnnReturn } else { "-" }) (Get-SignColor ([double]$sP.AnnReturn))
    & $add "Rendite im Zeitraum" (& $fmtP $sP.Total) $(if ($hasB) { & $fmtP $sB.Total } else { "-" })
    & $add "Volatilität p.a." (& $fmtP $sP.Vol "{0:0.00}%") $(if ($hasB) { & $fmtP $sB.Vol "{0:0.00}%" } else { "-" })
    & $add "Sharpe" (& $fmtP $sP.Sharpe "{0:0.00}") $(if ($hasB) { & $fmtP $sB.Sharpe "{0:0.00}" } else { "-" })
    $ddTxt = & $fmtP $sP.MaxDd "{0:0.00}%"
    if ($sP.DdTrough -ge 0) { $ddTxt += "  ({0} > {1})" -f $(if ($sP.DdPeak -ge 0) { & $dateAt $sP.DdPeak } else { $dd[0] }), (& $dateAt $sP.DdTrough) }
    & $add "Max. Drawdown" $ddTxt $(if ($hasB) { & $fmtP $sB.MaxDd "{0:0.00}%" } else { "-" }) $colRed
    if ($hasB -and [math]::Min($rP.Count, $rB.Count) -ge 3) {
        $n = [math]::Min($rP.Count, $rB.Count)
        $beta = Get-Beta -R ([double[]]@($rP[0..($n - 1)])) -B ([double[]]@($rB[0..($n - 1)]))
        $corr = Get-Correlation -A ([double[]]@($rP[0..($n - 1)])) -B ([double[]]@($rB[0..($n - 1)]))
        & $add "Beta zur Benchmark" (& $fmtP $beta "{0:0.00}") "1.00"
        & $add "Korrelation zur Benchmark" (& $fmtP $corr "{0:0.00}") "1.00"
    }
    & $add "Bester Tag" ("{0}  {1}" -f (& $fmtP $sP.Best), (& $dateAt $sP.BestIdx)) $(if ($hasB) { & $fmtP $sB.Best } else { "-" }) $colGreen
    & $add "Schlechtester Tag" ("{0}  {1}" -f (& $fmtP $sP.Worst), (& $dateAt $sP.WorstIdx)) $(if ($hasB) { & $fmtP $sB.Worst } else { "-" }) $colRed

    # correlation of the held positions, last 12 months
    $from = (Get-Date).AddYears(-1).ToString("yyyy-MM-dd")
    $by = @{}
    foreach ($r in @($ac.Model.Rows | Where-Object { $_.Shares -gt 0 } | Sort-Object Value -Descending | Select-Object -First 12)) {
        $hh = $script:AnaHist[$r.Ticker]
        if ($null -eq $hh -or $null -eq $hh.Hist) { continue }
        $by[$r.Ticker] = Get-DailyReturnsByDate -Dates ([string[]]$hh.Hist.Dates) -Closes ([double[]]$hh.Hist.Closes) -FromDate $from
    }
    $cg = $ac.CorrGrid
    $cg.Rows.Clear(); $cg.Columns.Clear()
    if ($by.Count -lt 2) { return }
    $cm = Get-CorrelationMatrix -BySym $by -MinCommon 20
    foreach ($sy in $cm.Syms) { $ci = $cg.Columns.Add($sy, $sy); $cg.Columns[$ci].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleCenter; $cg.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable }
    for ($i = 0; $i -lt $cm.Syms.Count; $i++) {
        $vals = @(for ($j = 0; $j -lt $cm.Syms.Count; $j++) { $x = $cm.M[$i, $j]; if ([double]::IsNaN($x)) { "-" } else { "{0:0.00}" -f $x } })
        $ri = $cg.Rows.Add([object[]]$vals)
        $cg.Rows[$ri].HeaderCell.Value = $cm.Syms[$i]
        for ($j = 0; $j -lt $cm.Syms.Count; $j++) {
            $x = $cm.M[$i, $j]
            if ($i -eq $j -or [double]::IsNaN($x)) { $cg.Rows[$ri].Cells[$j].Style.ForeColor = $script:Pal.Muted; continue }
            $tint = if ($x -ge 0) { $colRed } else { [System.Drawing.Color]::FromArgb(59, 130, 246) }
            $cg.Rows[$ri].Cells[$j].Style.BackColor = Get-BlendColor -A $tint -B $script:Pal.Card -T ([math]::Min(0.6, [math]::Abs($x) * 0.6))
            $cnts = $cm.Counts
            $nCommon = $cnts[$i, $j]
            $cg.Rows[$ri].Cells[$j].ToolTipText = "{0} / {1}: {2:0.00} ({3} {4})" -f $cm.Syms[$i], $cm.Syms[$j], $x, $nCommon, (Tr "gemeinsame Tage")
        }
    }
    $cg.RowHeadersDefaultCellStyle.BackColor = $script:Pal.Input
    $cg.RowHeadersDefaultCellStyle.ForeColor = $script:Pal.Accent
}

function Update-AnalysisTarget {
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.TGrid) { return }
    $g = $ac.TGrid
    if ($g.IsCurrentCellInEditMode) { return }
    $g.Rows.Clear()
    if ($null -eq $ac.Model) { return }
    $base = [string]$ac.Model.Base
    $tw = Get-TargetWeights
    $pos = @()
    foreach ($r in @($ac.Model.Rows | Where-Object { $_.Shares -gt 0 -and $_.Value -gt 0 } | Sort-Object Value -Descending)) {
        $pos += [PSCustomObject]@{ Sym = $r.Ticker; Value = [double]$r.Value; Price = [double]$r.Value / [double]$r.Shares }
    }
    $money = [math]::Max(0.0, (Parse-DecimalInput ([string]$ac.TMoney.Text)))
    $ci = Get-CashInfo -Currency $base
    $ac.TCash.Enabled = ($null -ne $ci)
    if ($null -ne $ci -and $ac.TCash.Checked -and $ci.Display -gt 0) { $money += $ci.Display }
    $plan = Get-RebalancePlan -Positions $pos -Targets $tw -Money $money -BuyOnly ([bool]$ac.TBuyOnly.Checked)
    $sumAll = 0.0; foreach ($x in $pos) { $sumAll += $x.Value }
    $priv = [bool]$script:Config.PrivacyMode
    foreach ($x in $pos) {
        $pr = @($plan.Rows | Where-Object { $_.Sym -eq $x.Sym })[0]
        $ist = if ($sumAll -gt 0) { $x.Value / $sumAll * 100.0 } else { 0.0 }
        if ($null -eq $pr) {
            $i = $g.Rows.Add($x.Sym, (Protect-Amount ("{0:N2}" -f $x.Value) $priv), ("{0:N1}%" -f $ist), "", "", "", "", "")
            $g.Rows[$i].DefaultCellStyle.ForeColor = $script:Pal.Muted
            $g.Rows[$i].Cells["Ziel"].Style.ForeColor = $script:Pal.Accent
            continue
        }
        # share of all positions after the trades
        $totAfter = $sumAll + $plan.Invest
        $after = if ($totAfter -gt 0) { $pr.After / $totAfter * 100.0 } else { 0.0 }
        $tradeTxt = if ([math]::Abs($pr.Trade) -lt 0.005) { "-" } else { "{0}{1:N2} {2}" -f $(if ($pr.Trade -gt 0) { (Tr "Kauf") + " " } else { (Tr "Verkauf") + " " }), [math]::Abs($pr.Trade), $base }
        $shTxt = if ([math]::Abs($pr.Shares) -lt 0.0001) { "-" } else { "{0:N2}" -f [math]::Abs($pr.Shares) }
        $i = $g.Rows.Add($x.Sym, (Protect-Amount ("{0:N2}" -f $x.Value) $priv), ("{0:N1}%" -f $ist), ("{0:0.##}" -f $pr.Target), ("{0:+0.0;-0.0;0.0} %-Pkt." -f $pr.Drift), $tradeTxt, $shTxt, ("{0:N1}%" -f $after))
        $g.Rows[$i].Cells["Abweichung"].Style.ForeColor = if ([math]::Abs($pr.Drift) -ge 5) { $script:Pal.Warn } else { $script:Pal.Muted }
        if ($pr.Trade -gt 0.005) { $g.Rows[$i].Cells["KaufVerkauf"].Style.ForeColor = $colGreen } elseif ($pr.Trade -lt -0.005) { $g.Rows[$i].Cells["KaufVerkauf"].Style.ForeColor = $colRed }
    }
    $p = $script:Pal
    if (@($plan.Rows).Count -eq 0) {
        $ac.TSum.Text = Tr "Noch keine Ziele: in der Spalte 'Ziel %' Anteile eintragen (Enter) oder 'Gleich verteilen'. Positionen ohne Ziel bleiben unverändert."
        $ac.TSum.ForeColor = $p.Muted
        return
    }
    $warn = if ([math]::Abs($plan.TargetSum - 100) -gt 0.05) { "  " + ("Achtung: Ziele ergeben {0:0.#} % - der Rest bleibt Geld." -f $plan.TargetSum) } else { "" }
    $ac.TSum.Text = "{0}: {1:N2} {2} | {3}: {4:N2} {2} | {5}: {6:N2} {2}{7}`r`n{8}" -f (Tr "Basis (Positionen mit Ziel + Geld)"), $plan.Base, $base, (Tr "netto investiert"), $plan.Invest, (Tr "übrig"), $plan.Left, $warn, (Tr "Vorschlag ohne Gebühren und Steuern, Stückzahlen gerundet auf 2 Stellen. Keine Anlageberatung.")
    if ($priv) { $ac.TSum.Text = Tr "Privat-Modus: Beträge ausgeblendet (F9)." }
    $ac.TSum.ForeColor = if ($warn) { $script:Pal.Warn } else { $p.Text }
}

function Update-AnalysisHeat {
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.Heat) { return }
    foreach ($k in $ac.HeatBtns.Keys) {
        $bt = $ac.HeatBtns[$k]
        if ($k -eq $ac.HeatMode) { Style-FlatButton -Btn $bt -BgColor $script:Pal.Accent -FgColor $script:Pal.HeaderBg -BorderColor $script:Pal.Accent }
        else { Style-FlatButton -Btn $bt -BgColor $script:Pal.Card -FgColor $script:Pal.Text -BorderColor $script:Pal.Border }
    }
    $ac.Heat.Invalidate()
}

function Draw-Heatmap {
    param([System.Drawing.Graphics]$g, [int]$W, [int]$H)
    $ac = $script:AnaCtl
    if ($null -eq $ac) { return }
    $items = @()
    if ($ac.HeatMode -eq "Watch") {
        foreach ($s in @($script:Config.Watchlist)) { $items += [PSCustomObject]@{ Sym = ([string]$s).ToUpper(); Value = 1.0 } }
    } else {
        foreach ($k in @($script:Portfolio.Keys)) {
            $pf = $script:Portfolio[$k]; $q = $script:QuoteStore[([string]$k).ToUpper()]
            if ($null -eq $q -or [double]$pf.Shares -le 0) { continue }
            $items += [PSCustomObject]@{ Sym = ([string]$k).ToUpper(); Value = [double]$pf.Shares * (Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency ([string]$script:Config.Currency)) }
        }
    }
    $g.Clear($script:Pal.BodyBg)
    $ac.HeatRects = @()
    if ($items.Count -eq 0) {
        $br0 = New-Object System.Drawing.SolidBrush($script:Pal.Muted)
        $g.DrawString((Tr "Keine Positionen mit aktuellem Kurs."), $fontUi, $br0, 10, 10); $br0.Dispose()
        return
    }
    $tot = 0.0; foreach ($it in $items) { $tot += $it.Value }
    $rects = Get-TreemapRects -Values ([double[]]@($items | ForEach-Object { $_.Value })) -X 0 -Y 0 -W $W -H $H
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center; $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $txtBr = New-Object System.Drawing.SolidBrush($script:Pal.Text)
    $pen = New-Object System.Drawing.Pen($script:Pal.BodyBg, [float](S 2))
    $list = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $items.Count; $i++) {
        $r = $rects[$i]
        if ($r[2] -lt 1 -or $r[3] -lt 1) { continue }
        $sym = $items[$i].Sym
        $q = $script:QuoteStore[$sym]
        $pct = if ($null -ne $q -and -not [bool]$q.FromCache) { [double]$q.ChangePct } else { [double]::NaN }
        $base = if ([double]::IsNaN($pct)) { $script:Pal.Card } elseif ($pct -ge 0) { $colGreen } else { $colRed }
        $t = if ([double]::IsNaN($pct)) { 0.0 } else { 0.25 + [math]::Min(0.65, [math]::Abs($pct) / 3.0 * 0.65) }
        $col = Get-BlendColor -A $base -B $script:Pal.Card -T $t
        $br = New-Object System.Drawing.SolidBrush($col)
        $rf = New-Object System.Drawing.RectangleF([float]$r[0], [float]$r[1], [float]$r[2], [float]$r[3])
        $g.FillRectangle($br, $rf); $br.Dispose()
        $g.DrawRectangle($pen, [float]$r[0], [float]$r[1], [float]$r[2], [float]$r[3])
        $lines = @($sym)
        if (-not [double]::IsNaN($pct)) { $lines += ("{0:+0.00;-0.00}%" -f $pct) }
        if ($ac.HeatMode -ne "Watch" -and $tot -gt 0) { $lines += ("{0:N1}% {1}" -f ($items[$i].Value / $tot * 100.0), (Tr "Anteil")) }
        $txt = ($lines -join "`n")
        $sz = $g.MeasureString($txt, $fontUiBold)
        if ($sz.Width -le $r[2] - 4 -and $sz.Height -le $r[3] - 4) { $g.DrawString($txt, $fontUiBold, $txtBr, $rf, $fmt) }
        elseif ($g.MeasureString($sym, $fontUi).Width -le $r[2] - 2 -and $r[3] -ge 14) { $g.DrawString($sym, $fontUi, $txtBr, $rf, $fmt) }
        $list.Add([PSCustomObject]@{ Sym = $sym; R = $r })
    }
    $ac.HeatRects = $list.ToArray()
    $txtBr.Dispose(); $pen.Dispose(); $fmt.Dispose()
}

# ---- v5.1: Analyse pages "Beitrag" (attribution, dividends, scenario) and "Vergleich" (indices, rolling, sectors) ----
function Get-CompareSymbols {
    $raw = [string]$script:Config.AnalysisCompare
    return @($raw -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { $_.Trim().ToUpper() } | Select-Object -Unique -First 6)
}

function Set-AnalysisRange {
    param([string]$Range)
    $ac = $script:AnaCtl
    if ($null -eq $ac) { return }
    $script:Config.AnalysisRange = $Range
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    & $ac.StyleRange
    Update-AnalysisPerf
    Update-AnalysisRisk
    Update-AnalysisContrib
    Update-AnalysisBench
}

function Get-PositionBeta {
    # beta of a ticker vs. the benchmark (daily returns, last 12 months);
    # falls back to Yahoo's beta. Returns @{ Beta; Source }
    param([string]$Sym)
    $bs = [string]$script:Config.AnalysisBenchmark
    $h = $script:AnaHist[$Sym]; $hb = $script:AnaHist[$bs]
    if ($bs -and $null -ne $h -and $null -ne $hb) {
        $from = (Get-Date).AddYears(-1).ToString("yyyy-MM-dd")
        $ra = Get-DailyReturnsByDate -Dates ([string[]]$h.Hist.Dates) -Closes ([double[]]$h.Hist.Closes) -FromDate $from
        $rb = Get-DailyReturnsByDate -Dates ([string[]]$hb.Hist.Dates) -Closes ([double[]]$hb.Hist.Closes) -FromDate $from
        $a = New-Object System.Collections.Generic.List[double]; $b = New-Object System.Collections.Generic.List[double]
        foreach ($d in $ra.Keys) { if ($rb.ContainsKey($d)) { $a.Add([double]$ra[$d]); $b.Add([double]$rb[$d]) } }
        if ($a.Count -ge 60) { return [PSCustomObject]@{ Beta = (Get-Beta -R $a.ToArray() -B $b.ToArray()); Source = $bs } }
    }
    $ev = $script:Events[$Sym]
    if ($null -ne $ev -and $null -ne $ev.Fund -and $null -ne $ev.Fund.Beta) { return [PSCustomObject]@{ Beta = [double]$ev.Fund.Beta; Source = "Yahoo" } }
    return [PSCustomObject]@{ Beta = [double]::NaN; Source = "" }
}

function Update-AnalysisContrib {
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.CGrid) { return }
    $g = $ac.CGrid
    $g.Rows.Clear()
    $priv = [bool]$script:Config.PrivacyMode
    $m = $ac.Model
    $sr = if ($null -ne $m) { $m.Series } else { $null }
    $base = if ($null -ne $m) { [string]$m.Base } else { Get-AnalysisBase }
    $money = { param([double]$v) if ($priv) { (Protect-Amount "0" $true) } else { "{0:N2}" -f $v } }
    if ($null -eq $sr -or $null -eq $sr.BySym -or @($sr.Dates).Count -lt 2) {
        [void]$g.Rows.Add((Tr "Noch kein Verlauf - Kurse werden geladen oder es fehlen Buchungen"), "", "", "", "", "", "", "", "")
    } else {
        $dates = [string[]]$sr.Dates
        $st = Get-SeriesWindowStart -Dates $dates -Range ([string]$script:Config.AnalysisRange)
        $cb = Get-Contributions -BySym $sr.BySym -Start $st -End ($dates.Count - 1)
        $maxAbs = 0.0; foreach ($r in $cb.Rows) { $maxAbs = [math]::Max($maxAbs, [math]::Abs([double]$r.Contribution)) }
        foreach ($r in $cb.Rows) {
            $i = $g.Rows.Add($r.Sym, (& $money $r.Start), (& $money $r.Buys), (& $money $r.Sells), (& $money $r.Divs), (& $money $r.End), $(if ($priv) { (Protect-Amount "0" $true) } else { Format-Signed $r.Contribution }), $(if ([double]::IsNaN([double]$r.Pct)) { "-" } else { "{0:+0.0;-0.0}%" -f $r.Pct }), $(if ([double]::IsNaN([double]$r.Share)) { "-" } else { "{0:+0;-0}%" -f $r.Share }))
            $col = Get-SignColor ([double]$r.Contribution)
            $g.Rows[$i].Cells["Contrib"].Style.ForeColor = $col
            $g.Rows[$i].Cells["Pct"].Style.ForeColor = $col
            if ($maxAbs -gt 0) { $g.Rows[$i].Cells["Contrib"].Style.BackColor = Get-BlendColor -A $col -B $script:Pal.Card -T ([math]::Min(0.45, [math]::Abs([double]$r.Contribution) / $maxAbs * 0.45)) }
        }
        $i = $g.Rows.Add((Tr "Summe"), "", "", "", "", "", $(if ($priv) { (Protect-Amount "0" $true) } else { Format-Signed $cb.Total }), "", "")
        $g.Rows[$i].DefaultCellStyle.Font = $fontUiBold
        $g.Rows[$i].Cells["Contrib"].Style.ForeColor = Get-SignColor ([double]$cb.Total)
        $ac.CInfo.Text = "{0} {1} - {2} ({3}), {4} {5}. {6}" -f (Tr "Zeitraum"), $dates[$st], $dates[$dates.Count - 1], (Get-RangeLabel ([string]$script:Config.AnalysisRange)), (Tr "Beträge in"), $base, (Tr "Beitrag = Endwert + Verkäufe + Dividenden - Anfangswert - Käufe")
    }
    # dividends of the next 12 months (projection from the Dividenden page)
    if ($null -ne $ac.DivForecast) {
        $ac.CDiv.Text = "{0}: {1} {2} ({3} {4} / {5})  -  {6}" -f (Tr "Dividenden nächste 12 Monate (Prognose)"), (& $money ([double]$ac.DivForecast)), $base, (Tr "ca."), (& $money ([double]$ac.DivForecast / 12.0)), (Tr "Monat"), (Tr "Monate und Ex-Tage: Seite Dividenden")
    } else { $ac.CDiv.Text = Tr "Dividenden-Prognose wird geladen ..." }
    Update-AnalysisScenario
}

function Update-AnalysisScenario {
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.SGrid) { return }
    $g = $ac.SGrid
    $g.Rows.Clear()
    $priv = [bool]$script:Config.PrivacyMode
    if ($null -eq $ac.Model) { return }
    $mkt = [double]$ac.SNum.Value
    $pos = @()
    $src = @{}
    foreach ($r in @($ac.Model.Rows | Where-Object { $_.Shares -gt 0 -and $_.Value -gt 0 })) {
        $b = Get-PositionBeta -Sym $r.Ticker
        $pos += [PSCustomObject]@{ Sym = $r.Ticker; Value = [double]$r.Value; Beta = [double]$b.Beta }
        $src[$r.Ticker] = $b.Source
    }
    $sc = Get-ScenarioImpact -Positions $pos -MarketPct $mkt
    foreach ($r in $sc.Rows) {
        $i = $g.Rows.Add($r.Sym, $(if ($priv) { (Protect-Amount "0" $true) } else { "{0:N2}" -f $r.Value }), ("{0:N2}" -f $r.Beta), $(if ($r.BetaAssumed) { Tr "angenommen 1,0" } else { $src[$r.Sym] }), $(if ($priv) { (Protect-Amount "0" $true) } else { Format-Signed $r.Change }), ("{0:+0.0;-0.0}%" -f ($r.Beta * $mkt)))
        $g.Rows[$i].Cells["Chg"].Style.ForeColor = Get-SignColor ([double]$r.Change)
        if ($r.BetaAssumed) { $g.Rows[$i].Cells["Src"].Style.ForeColor = $script:Pal.Muted }
    }
    $ac.SRes.ForeColor = Get-SignColor ([double]$sc.Change)
    $ac.SRes.Text = "{0} {1} {2} ({3:+0.0;-0.0}%)  -  {4}" -f (Tr "Depot ca."), $(if ($priv) { (Protect-Amount "0" $true) } else { Format-Signed $sc.Change }), [string]$ac.Model.Base, $sc.Pct, (Tr "grobe Schätzung über das Beta, ohne Cash")
}

function Update-AnalysisBench {
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.BGrid) { return }
    $g = $ac.BGrid
    $g.Rows.Clear()
    $ac.BLines = @()
    $m = $ac.Model
    $sr = if ($null -ne $m) { $m.Series } else { $null }
    if ($null -eq $sr -or @($sr.Dates).Count -lt 10) {
        [void]$g.Rows.Add((Tr "Zu wenig Verlauf"), "", "", "", "", "", "", "")
        $ac.BChart.Invalidate()
    } else {
        $base = [string]$m.Base
        $dates = [string[]]$sr.Dates
        $st = Get-SeriesWindowStart -Dates $dates -Range ([string]$script:Config.AnalysisRange)
        $dd = [string[]]@($dates[$st..($dates.Count - 1)])
        $ppy = Get-PeriodsPerYear -Dates $dd
        $hist = Get-FxHistoryMap
        $fb = @{}; foreach ($k in $script:FxFromEur.Keys) { $fb[$k] = [double]$script:FxFromEur[$k] }
        $colors = @($script:Pal.Accent, $script:Pal.Warn, [System.Drawing.Color]::FromArgb(168, 85, 247), [System.Drawing.Color]::FromArgb(236, 72, 153), [System.Drawing.Color]::FromArgb(34, 211, 238), [System.Drawing.Color]::FromArgb(132, 204, 22), [System.Drawing.Color]::FromArgb(148, 163, 184))
        $lines = @()
        $full = Get-TwrIndex -Value ([double[]]$sr.Value) -Invested ([double[]]$sr.Invested) -Dividends ([double[]]$sr.Dividends)
        $win = Get-TwrIndex -Value ([double[]]$sr.Value) -Invested ([double[]]$sr.Invested) -Dividends ([double[]]$sr.Dividends) -Start $st
        $lines += [PSCustomObject]@{ Name = (Tr "Depot"); Full = $full; Win = [double[]]@($win[$st..($win.Count - 1)]); Color = $colors[0] }
        $ci = 1
        foreach ($cs in (Get-CompareSymbols)) {
            $h = $script:AnaHist[$cs]
            if ($null -eq $h -or $null -eq $h.Hist -or @($h.Hist.Dates).Count -lt 2) { $lines += [PSCustomObject]@{ Name = $cs; Full = $null; Win = $null; Color = $colors[$ci % $colors.Count] }; $ci++; continue }
            $cl = Get-AlignedSeries -Target $dates -Dates $h.Hist.Dates -Values $h.Hist.Closes
            $fx = Get-AlignedFxToBase -Target $dates -Currency ([string]$h.Hist.Currency) -Base $base -History $hist -FallbackFromEur $fb
            $v = New-Object double[] $dates.Count
            for ($j = 0; $j -lt $dates.Count; $j++) { $v[$j] = $cl[$j] * $fx.Factor[$j] }
            $fi = Get-TwrIndex -Value $v
            $wi = Get-TwrIndex -Value $v -Start $st
            $lines += [PSCustomObject]@{ Name = $cs; Full = $fi; Win = [double[]]@($wi[$st..($wi.Count - 1)]); Color = $colors[$ci % $colors.Count] }
            $ci++
        }
        foreach ($ln in $lines) {
            if ($null -eq $ln.Win) { [void]$g.Rows.Add($ln.Name, (Tr "keine Kurse"), "", "", "", "", "", ""); continue }
            $rets = New-Object System.Collections.Generic.List[double]
            for ($j = 1; $j -lt $ln.Win.Count; $j++) { if ($ln.Win[$j - 1] -gt 0) { $rets.Add($ln.Win[$j] / $ln.Win[$j - 1] - 1.0) } }
            $stt = Get-ReturnStats -Returns $rets.ToArray() -PeriodsPerYear $ppy -RiskFreePct ([double]$script:Config.RiskFreePct)
            $roll = Get-RollingReturns -Dates $dates -Values $ln.Full -Days 365
            $rv = @($roll.Values)
            $fmt = { param($x, [string]$f = "{0:+0.0;-0.0}%") if ($null -eq $x -or [double]::IsNaN([double]$x)) { "-" } else { $f -f [double]$x } }
            $i = $g.Rows.Add($ln.Name, (& $fmt ($ln.Win[$ln.Win.Count - 1] - 100.0)), (& $fmt $stt.AnnReturn), (& $fmt $stt.Vol "{0:0.0}%"), (& $fmt $stt.MaxDd "{0:0.0}%"),
                $(if ($rv.Count -gt 0) { & $fmt $rv[$rv.Count - 1] } else { "-" }), $(if ($rv.Count -gt 0) { & $fmt (($rv | Measure-Object -Minimum).Minimum) } else { "-" }), $(if ($rv.Count -gt 0) { & $fmt (($rv | Measure-Object -Maximum).Maximum) } else { "-" }))
            $g.Rows[$i].Cells[0].Style.ForeColor = $ln.Color
            $g.Rows[$i].Cells[1].Style.ForeColor = Get-SignColor ([double]($ln.Win[$ln.Win.Count - 1] - 100.0))
        }
        $ac.BLines = $lines
        $ac.BDates = $dd
        $ac.BInfo.Text = "{0} {1} - {2}, {3} {4} {5}" -f (Tr "Zeitraum"), $dd[0], $dd[$dd.Count - 1], (Tr "alles in"), $base, (Tr "(Indizes umgerechnet, Depot zeitgewichtet ohne Ein- / Auszahlungen)")
        $ac.BChart.Invalidate()
    }
    # sectors vs. MSCI World (iShares URTH holdings, fetched once per session)
    $sg = $ac.SecGrid
    $sg.Rows.Clear()
    if ($null -eq $script:SectorRef -and -not $script:SectorRefLoading -and -not $script:WorkerShared.CrumbFailed -and -not $script:ProfileJobRunning) {
        $script:SectorRefLoading = $true
        Start-ProfileJob -Symbols @("URTH") -Modules "topHoldings" -OnRaw {
            param($Res)
            $script:SectorRefLoading = $false
            $rr = $Res["URTH"]
            if ($null -ne $rr -and $null -ne $rr.Summary) { $sw = ConvertFrom-YahooSectorWeights -Summary $rr.Summary; if ($sw.Count -gt 0) { $script:SectorRef = $sw } }
            if ($null -ne $script:AnaCtl) { Update-AnalysisBench }
        }
    }
    $savedDim = $ac.Dim
    $ac.Dim = "Sector"
    $groups = @(Get-AllocationBreakdown -Items @(Get-AllocationItems))
    $ac.Dim = $savedDim
    foreach ($r in @(Get-SectorComparison -Groups $groups -Reference $script:SectorRef)) {
        $i = $sg.Rows.Add((Tr $r.Sector), ("{0:N1}%" -f $r.Depot), $(if ([double]::IsNaN([double]$r.Ref)) { "-" } else { "{0:N1}%" -f $r.Ref }), $(if ([double]::IsNaN([double]$r.Diff)) { "-" } else { "{0:+0.0;-0.0}" -f $r.Diff }))
        if (-not [double]::IsNaN([double]$r.Diff) -and [math]::Abs([double]$r.Diff) -ge 5) { $sg.Rows[$i].Cells[3].Style.ForeColor = $(if ($r.Diff -gt 0) { $script:Pal.Warn } else { [System.Drawing.Color]::FromArgb(59, 130, 246) }) }
    }
    if ($null -eq $script:SectorRef) { $sg.Columns[2].HeaderText = $(if ($script:SectorRefLoading) { Tr "MSCI World (lädt)" } else { Tr "MSCI World (n/v)" }) } else { $sg.Columns[2].HeaderText = "MSCI World" }
}

function Draw-BenchChart {
    param($g, [int]$W, [int]$H)
    $ac = $script:AnaCtl
    $p = $script:Pal
    $g.Clear($p.Card)
    if ($null -eq $ac -or @($ac.BLines).Count -eq 0) { return }
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $mn = [double]::MaxValue; $mx = [double]::MinValue; $n = 0
    foreach ($ln in $ac.BLines) { if ($null -eq $ln.Win) { continue }; $n = [math]::Max($n, $ln.Win.Count); foreach ($v in $ln.Win) { if (-not [double]::IsNaN($v)) { if ($v -lt $mn) { $mn = $v }; if ($v -gt $mx) { $mx = $v } } } }
    if ($n -lt 2 -or $mx -le $mn) { return }
    $pad = ($mx - $mn) * 0.06; $mn -= $pad; $mx += $pad
    $l = S 8; $t = S 26; $r = $W - (S 56); $b = $H - (S 22)
    $toX = { param([int]$i) $l + $i / [double]($n - 1) * ($r - $l) }
    $toY = { param([double]$v) $b - ($v - $mn) / ($mx - $mn) * ($b - $t) }
    $gp = New-Object System.Drawing.Pen($p.Grid, [float]1)
    $tb = New-Object System.Drawing.SolidBrush($p.Muted)
    try {
        for ($k = 0; $k -le 4; $k++) {
            $v = $mn + ($mx - $mn) * $k / 4.0
            $y = & $toY $v
            $g.DrawLine($gp, [float]$l, [float]$y, [float]$r, [float]$y)
            $g.DrawString(("{0:+0;-0}%" -f ($v - 100.0)), $fontAxis, $tb, [float]($r + (S 4)), [float]($y - (S 7)))
        }
        $y100 = & $toY 100.0
        $zp = New-Object System.Drawing.Pen($p.Border, [float]1); $zp.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
        $g.DrawLine($zp, [float]$l, [float]$y100, [float]$r, [float]$y100); $zp.Dispose()
        $lx = $l
        $lines = @($ac.BLines)
        for ($li = $lines.Count - 1; $li -ge 0; $li--) {
            $ln = $lines[$li]
            if ($null -eq $ln.Win) { continue }
            $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
            for ($i = 0; $i -lt $ln.Win.Count; $i++) { if (-not [double]::IsNaN($ln.Win[$i])) { $pts.Add((New-Object System.Drawing.PointF([float](& $toX $i), [float](& $toY $ln.Win[$i])))) } }
            if ($pts.Count -ge 2) { $pn = New-Object System.Drawing.Pen($ln.Color, $(if ($li -eq 0) { [float]2.2 } else { [float]1.4 })); $g.DrawLines($pn, $pts.ToArray()); $pn.Dispose() }
        }
        foreach ($ln in $lines) {
            $txt = if ($null -eq $ln.Win) { "{0} -" -f $ln.Name } else { "{0} {1:+0.0;-0.0}%" -f $ln.Name, ($ln.Win[$ln.Win.Count - 1] - 100.0) }
            $br = New-Object System.Drawing.SolidBrush($ln.Color)
            $g.FillRectangle($br, [float]$lx, [float](S 8), [float](S 10), [float](S 10))
            $g.DrawString($txt, $fontAxis, $tb, [float]($lx + (S 14)), [float](S 5))
            $lx += [int]$g.MeasureString($txt, $fontAxis).Width + (S 26)
            $br.Dispose()
        }
        if ($null -ne $ac.BDates -and @($ac.BDates).Count -gt 1) {
            $g.DrawString([string]$ac.BDates[0], $fontAxis, $tb, [float]$l, [float]($b + (S 4)))
            $ls = [string]$ac.BDates[@($ac.BDates).Count - 1]
            $g.DrawString($ls, $fontAxis, $tb, [float]($r - $g.MeasureString($ls, $fontAxis).Width), [float]($b + (S 4)))
        }
    } finally { $gp.Dispose(); $tb.Dispose() }
}

function Show-AnalysisPage {
    param([string]$Page)
    $ac = $script:AnaCtl
    if ($null -eq $ac) { return }
    $ac.Page = $Page
    $script:Config.AnalysisLastPage = $Page
    foreach ($k in $ac.Pages.Keys) { $ac.Pages[$k].Visible = ($k -eq $Page) }
    if ($Page -eq "Heat") { Update-AnalysisHeat }
    if ($Page -eq "Bench") { Update-AnalysisBench }
    foreach ($k in $ac.PageButtons.Keys) {
        $bt = $ac.PageButtons[$k]
        if ($k -eq $Page) { Style-FlatButton -Btn $bt -BgColor $script:Pal.Accent -FgColor $script:Pal.HeaderBg -BorderColor $script:Pal.Accent }
        else { Style-FlatButton -Btn $bt -BgColor $script:Pal.Card -FgColor $script:Pal.Text -BorderColor $script:Pal.Border }
    }
}

function Show-AnalysisDialog {
    param([string]$Page = "")
    if ($null -ne $script:AnaCtl) { return }
    # v5.0: P opens the page used last time
    if (-not $Page) { $Page = if ([string]$script:Config.AnalysisLastPage) { [string]$script:Config.AnalysisLastPage } else { "Perf" } }
    $p = $script:Pal
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right
    $aAll = $aT -bor $aB -bor $aL -bor $aR

    $dlg = New-DialogForm -Title "Portfolio-Analyse - $($script:AppTitle)" -W (S 1000) -H (S 640)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MaximizeBox = $true
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 860), (S 520))
    $dlg.KeyPreview = $true

    $mkBtn = {
        param([string]$T, [int]$X, [int]$Y, [int]$Wd, $Parent, $Anchor = $null)
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds($X, $Y, $Wd, (S 26))
        Style-FlatButton -Btn $b -BgColor $p.Card -FgColor $p.Text -BorderColor $p.Border
        $b.Text = $T
        if ($null -ne $Anchor) { $b.Anchor = $Anchor }
        $Parent.Controls.Add($b)
        return $b
    }

    $pageBtns = [ordered]@{}
    $pageBtns["Perf"]  = & $mkBtn "Wertentwicklung" (S 12) (S 10) (S 130) $dlg
    $pageBtns["Ret"]   = & $mkBtn "Rendite" (S 146) (S 10) (S 80) $dlg
    $pageBtns["Alloc"] = & $mkBtn "Aufteilung" (S 230) (S 10) (S 92) $dlg
    $pageBtns["Div"]   = & $mkBtn "Dividenden" (S 326) (S 10) (S 94) $dlg
    # v5.0
    $pageBtns["Risk"]   = & $mkBtn "Risiko" (S 424) (S 10) (S 70) $dlg
    $pageBtns["Target"] = & $mkBtn "Zielgewichte" (S 498) (S 10) (S 100) $dlg
    $pageBtns["Heat"]   = & $mkBtn "Heatmap" (S 602) (S 10) (S 80) $dlg
    # v5.1
    $pageBtns["Contrib"] = & $mkBtn "Beitrag" (S 686) (S 10) (S 76) $dlg
    $pageBtns["Bench"]   = & $mkBtn "Vergleich" (S 766) (S 10) (S 86) $dlg
    Set-DynTip $pageBtns["Contrib"] "Was jede Position zum Ergebnis beigetragen hat, Dividenden-Prognose und Szenario 'Markt -20 %'"
    Set-DynTip $pageBtns["Bench"] "Depot gegen mehrere Indizes, rollierende 12-Monats-Rendite und Sektoren gegen den MSCI World"
    Set-DynTip $pageBtns["Risk"] "Volatilität, maximaler Rückgang, Sharpe, Beta und Korrelation der Positionen"
    Set-DynTip $pageBtns["Target"] "Ziel-Anteile je Position und was zu kaufen / verkaufen wäre (Rebalancing)"
    Set-DynTip $pageBtns["Heat"] "Depot als Kacheln: Größe = Anteil, Farbe = Tagesänderung"
    Set-DynTip $pageBtns["Div"] "Erwartete Dividenden, Rendite, Ex-Tage und Quartalszahlen je Position" "DIVFORECAST"
    Set-DynTip $pageBtns["Perf"] "Depotwert über die Zeit, aus deinen Buchungen nachgerechnet, mit Benchmark" "BENCHMARK"
    Set-DynTip $pageBtns["Ret"] "Ergebnis und Jahresrendite je Position" "XIRR"
    Set-DynTip $pageBtns["Alloc"] "Aufteilung nach Position, Währung, Sektor und Land" "ALLOCATION"

    $lblBase = New-Object System.Windows.Forms.Label
    $lblBase.SetBounds((S 560), (S 41), (S 44), (S 18)); $lblBase.Anchor = $aT -bor $aR; $lblBase.Text = "Basis:"
    $dlg.Controls.Add($lblBase)
    $cbBase = New-Object System.Windows.Forms.ComboBox
    $cbBase.SetBounds((S 604), (S 38), (S 62), (S 24)); $cbBase.Anchor = $aT -bor $aR
    $cbBase.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbBase.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cbBase.BackColor = $p.Input; $cbBase.ForeColor = $p.Accent
    foreach ($c in (Get-DisplayCurrencies)) { [void]$cbBase.Items.Add($c) }
    Select-CurrencyInCombo -Combo $cbBase -Code (Get-AnalysisBase)
    $dlg.Controls.Add($cbBase)
    $lblBench = New-Object System.Windows.Forms.Label
    $lblBench.SetBounds((S 676), (S 41), (S 72), (S 18)); $lblBench.Anchor = $aT -bor $aR; $lblBench.Text = "Benchmark:"
    $dlg.Controls.Add($lblBench)
    $tbBench = New-Object System.Windows.Forms.TextBox
    $tbBench.SetBounds((S 748), (S 38), (S 90), (S 24)); $tbBench.Anchor = $aT -bor $aR
    $tbBench.BackColor = $p.Input; $tbBench.ForeColor = $p.Text; $tbBench.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tbBench.Font = $fontMono; $tbBench.Text = [string]$script:Config.AnalysisBenchmark
    $dlg.Controls.Add($tbBench)
    Set-DynTip $tbBench "Yahoo-Symbol, z. B. EUNL.DE (MSCI World, EUR), ^GSPC (S&P 500), ^ATX. Leer = kein Vergleich." "BENCHMARK"
    $btnReload = & $mkBtn "Neu laden" (S 846) (S 37) (S 140) $dlg ($aT -bor $aR)
    Set-DynTip $btnReload "Kursverläufe, Wechselkurse und Profile neu von Yahoo laden"

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.SetBounds((S 12), (S 42), (S 536), (S 18)); $lblStatus.Anchor = $aT -bor $aL -bor $aR
    $lblStatus.AutoEllipsis = $true; $lblStatus.ForeColor = $p.Muted
    $dlg.Controls.Add($lblStatus)

    $pages = [ordered]@{}
    foreach ($k in @("Perf", "Ret", "Alloc", "Div", "Risk", "Target", "Heat", "Contrib", "Bench")) {
        $pn = New-Object System.Windows.Forms.Panel
        $pn.SetBounds((S 12), (S 64), (S 976), (S 564))
        $pn.Anchor = $aAll
        $pn.BackColor = $p.BodyBg
        $dlg.Controls.Add($pn)
        $pages[$k] = $pn
    }

    # --- Wertentwicklung ---
    $pp = $pages["Perf"]
    $rangeBtns = @{}
    $rx = 0
    foreach ($rg in @(@("6M", "6M"), @("1Y", "1J"), @("3Y", "3J"), @("Max", "Max"))) {
        $rangeBtns[$rg[0]] = & $mkBtn $rg[1] $rx 0 (S 46) $pp
        $rangeBtns[$rg[0]].Tag = $rg[0]
        $rx += S 50
    }
    $chkInv = New-Object System.Windows.Forms.CheckBox
    $chkInv.SetBounds(($rx + (S 16)), (S 3), (S 140), (S 22)); $chkInv.Text = "Netto investiert"
    $chkInv.Checked = [bool]$script:Config.AnalysisShowInvested; $chkInv.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $pp.Controls.Add($chkInv)
    Set-DynTip $chkInv "" "NETINVEST"
    $chkBench = New-Object System.Windows.Forms.CheckBox
    $chkBench.SetBounds(($rx + (S 160)), (S 3), (S 120), (S 22)); $chkBench.Text = "Benchmark"
    $chkBench.Checked = [bool]$script:Config.AnalysisShowBench; $chkBench.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $pp.Controls.Add($chkBench)
    Set-DynTip $chkBench "" "BENCHMARK"
    $chart = New-Object System.Windows.Forms.Panel
    $chart.SetBounds(0, (S 32), (S 976), (S 456))
    $chart.Anchor = $aAll
    Enable-DoubleBuffering -Control $chart
    $pp.Controls.Add($chart)
    $btnBuyDates = & $mkBtn "Kaufdaten ..." (S 846) 0 (S 130) $pp ($aT -bor $aR)
    Set-DynTip $btnBuyDates "Kaufdatum für Positionen ohne Buchung nachtragen (Anfangsbestand) oder Datum von Editor-Buchungen korrigieren" "OPENING"
    $lblSum = New-Object System.Windows.Forms.Label
    $lblSum.SetBounds(0, (S 494), (S 976), (S 68))
    $lblSum.Anchor = $aB -bor $aL -bor $aR
    $lblSum.Font = $fontMono
    $pp.Controls.Add($lblSum)

    # --- Rendite ---
    $pr = $pages["Ret"]
    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.SetBounds(0, 0, (S 976), (S 520))
    $grid.Anchor = $aAll
    Style-DataGrid -Grid $grid
    foreach ($cd in @(@("Ticker", "Ticker", 80, ""), @("Since", "Seit", 70, ""), @("Shares", "Stück", 84, ""), @("Value", "Wert", 96, "PRICE"), @("Cost", "Einstand", 96, "EK"),
                      @("Unreal", "Unrealisiert", 96, "UNREALIZED"), @("Real", "Realisiert", 90, "REALIZED"), @("Div", "Dividenden", 86, ""),
                      @("Total", "Gesamt", 96, "TOTALRET"), @("Pct", "Gesamt %", 74, "TOTALRET"), @("Xirr", "XIRR p.a.", 74, "XIRR"))) {
        $ci = $grid.Columns.Add($cd[0], $cd[1])
        $col = $grid.Columns[$ci]
        $col.FillWeight = [float](S $cd[2])
        $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
        if ($ci -ge 2) { $col.DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
        if ($cd[3]) { $col.ToolTipText = Get-GlossaryShort -Key $cd[3] }
    }
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $pr.Controls.Add($grid)
    $lblRetNote = New-Object System.Windows.Forms.Label
    $lblRetNote.SetBounds(0, (S 526), (S 976), (S 36)); $lblRetNote.Anchor = $aB -bor $aL -bor $aR
    $lblRetNote.ForeColor = $p.Muted
    $pr.Controls.Add($lblRetNote)

    # --- Aufteilung ---
    $pa = $pages["Alloc"]
    $dimBtns = [ordered]@{}
    $dx = 0
    foreach ($dm in @(@("Position", "Position"), @("Currency", "Währung"), @("Sector", "Sektor"), @("Country", "Land"))) {
        $dimBtns[$dm[0]] = & $mkBtn $dm[1] $dx 0 (S 84) $pa
        $dimBtns[$dm[0]].Tag = $dm[0]
        $dx += S 88
    }
    $lblThr = New-Object System.Windows.Forms.Label
    $lblThr.SetBounds(($dx + (S 12)), (S 5), (S 96), (S 18)); $lblThr.Text = "Hinweis ab (%):"
    $pa.Controls.Add($lblThr)
    $nThr = New-Object System.Windows.Forms.NumericUpDown
    $nThr.SetBounds(($dx + (S 108)), (S 2), (S 56), (S 22)); $nThr.Minimum = 5; $nThr.Maximum = 90; $nThr.Increment = 5
    $nThr.Value = [int]$script:Config.ConcentrationWarnPct
    $nThr.BackColor = $p.Input; $nThr.ForeColor = $p.Text; $nThr.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $pa.Controls.Add($nThr)
    Set-DynTip $lblThr "" "CONCENTRATION"; Set-DynTip $nThr "" "CONCENTRATION"
    $bars = New-Object System.Windows.Forms.Panel
    $bars.SetBounds(0, (S 32), (S 540), (S 492))
    $bars.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Enable-DoubleBuffering -Control $bars
    $pa.Controls.Add($bars)
    $lblWarn = New-Object System.Windows.Forms.Label
    $lblWarn.SetBounds(0, (S 530), (S 540), (S 32)); $lblWarn.Anchor = $aB -bor $aL -bor $aR
    $pa.Controls.Add($lblWarn)
    $pg = New-Object System.Windows.Forms.DataGridView
    $pg.SetBounds((S 552), (S 32), (S 424), (S 492))
    $pg.Anchor = $aT -bor $aB -bor $aR
    Style-DataGrid -Grid $pg
    $pg.ReadOnly = $false
    $pg.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::CellSelect
    foreach ($cd in @(@("Ticker", "Ticker", 70, $true), @("Name", "Name", 110, $true), @("Sector", "Sektor", 100, $false), @("Country", "Land", 90, $false), @("Source", "Quelle", 70, $true))) {
        $ci = $pg.Columns.Add($cd[0], $cd[1])
        $pg.Columns[$ci].FillWeight = [float](S $cd[2])
        $pg.Columns[$ci].ReadOnly = [bool]$cd[3]
        $pg.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    }
    $pg.Columns["Sector"].ToolTipText = "Sektor überschreiben: Zelle anklicken und tippen. Leer lassen = automatisch (Yahoo)."
    $pg.Columns["Country"].ToolTipText = "Land überschreiben: Zelle anklicken und tippen. Leer lassen = automatisch (Yahoo)."
    $pg.Columns["Source"].ToolTipText = "Herkunft Sektor / Land: Yahoo, manuell oder nach Typ (ETF, Krypto ...)"
    $pg.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $pa.Controls.Add($pg)
    $lblPg = New-Object System.Windows.Forms.Label
    $lblPg.SetBounds((S 552), (S 530), (S 424), (S 32)); $lblPg.Anchor = $aB -bor $aR
    $lblPg.ForeColor = $p.Muted
    $lblPg.Text = "Sektor/Land per Klick überschreiben (blau = manuell). Leer = wieder automatisch."
    $pa.Controls.Add($lblPg)

    # --- Dividenden ---
    $pd = $pages["Div"]
    $lblDivSum = New-Object System.Windows.Forms.Label
    $lblDivSum.SetBounds(0, 0, (S 976), (S 40)); $lblDivSum.Anchor = $aT -bor $aL -bor $aR
    $lblDivSum.Font = $fontMono
    $pd.Controls.Add($lblDivSum)
    $dg = New-Object System.Windows.Forms.DataGridView
    $dg.SetBounds(0, (S 44), (S 976), (S 290)); $dg.Anchor = $aT -bor $aL -bor $aR
    Style-DataGrid -Grid $dg
    foreach ($cd in @(@("Ticker", "Ticker", 80, ""), @("Freq", "Rhythmus", 96, ""), @("Last", "Letzte", 96, ""), @("Annual", "Pro Jahr", 96, ""), @("Yield", "Rendite", 70, "DIVYIELD"),
                      @("Yoc", "auf EK", 70, "YOC"), @("Income", "Erwartet 12M", 104, "DIVFORECAST"), @("Ex", "Nächster Ex-Tag", 104, "EXDATE"), @("Pay", "Zahltag", 84, ""), @("Earn", "Quartalszahlen", 130, "EARNINGS"))) {
        $ci = $dg.Columns.Add($cd[0], $cd[1])
        $col = $dg.Columns[$ci]
        $col.FillWeight = [float](S $cd[2])
        $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
        if ($ci -ge 2 -and $ci -le 6) { $col.DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
        if ($cd[3]) { $col.ToolTipText = Get-GlossaryShort -Key $cd[3] }
    }
    $dg.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $pd.Controls.Add($dg)
    $divBars = New-Object System.Windows.Forms.Panel
    $divBars.SetBounds(0, (S 342), (S 976), (S 186)); $divBars.Anchor = $aAll
    Enable-DoubleBuffering -Control $divBars
    $pd.Controls.Add($divBars)
    $lblDivNote = New-Object System.Windows.Forms.Label
    $lblDivNote.SetBounds(0, (S 532), (S 976), (S 30)); $lblDivNote.Anchor = $aB -bor $aL -bor $aR
    $lblDivNote.ForeColor = $p.Muted
    $lblDivNote.Text = "Prognose: Zahlungen der letzten 12 Monate je Aktie × heutige Stückzahl, brutto (vor Steuern). ~ = geschätzter Termin. Wechselkurse von heute."
    $pd.Controls.Add($lblDivNote)

    $script:AnaCtl = @{
        DivGrid = $dg; DivSum = $lblDivSum; DivBars = $divBars; DivBuckets = @(); DivBase = ""
        Dlg = $dlg; Status = $lblStatus; Reload = $btnReload; Base = $cbBase; Bench = $tbBench
        Pages = $pages; PageButtons = $pageBtns; Page = "Perf"
        Chart = $chart; Sum = $lblSum; RangeButtons = $rangeBtns; HoverIdx = -1; Geom = $null
        RetGrid = $grid; RetNote = $lblRetNote
        Bars = $bars; AllocWarn = $lblWarn; ProfGrid = $pg; DimButtons = $dimBtns; Dim = "Position"; Groups = @()
        Model = $null; Failed = @()
    }

    # --- events ---
    foreach ($k in $pageBtns.Keys) { $pageBtns[$k].Tag = $k; $pageBtns[$k].Add_Click({ param($sender, $e) Show-AnalysisPage ([string]$sender.Tag) }) }
    $styleRange = {
        foreach ($set in @(@($script:AnaCtl.RangeButtons) + @($script:AnaCtl.RangeSets))) {
            if ($null -eq $set) { continue }
            foreach ($k in $set.Keys) {
                $bt = $set[$k]
                if ($k -eq [string]$script:Config.AnalysisRange) { Style-FlatButton -Btn $bt -BgColor $script:Pal.Accent -FgColor $script:Pal.HeaderBg -BorderColor $script:Pal.Accent }
                else { Style-FlatButton -Btn $bt -BgColor $script:Pal.Card -FgColor $script:Pal.Text -BorderColor $script:Pal.Border }
            }
        }
    }
    $script:AnaCtl.StyleRange = $styleRange
    foreach ($k in $rangeBtns.Keys) {
        $rangeBtns[$k].Add_Click({
            param($sender, $e)
            Set-AnalysisRange ([string]$sender.Tag)
        })
    }
    & $styleRange
    $chkInv.Add_CheckedChanged({ param($sender, $e) $script:Config.AnalysisShowInvested = [bool]$sender.Checked; Save-JsonState -Path $script:ConfigPath -Data $script:Config; $script:AnaCtl.Chart.Invalidate() })
    $chkBench.Add_CheckedChanged({ param($sender, $e) $script:Config.AnalysisShowBench = [bool]$sender.Checked; Save-JsonState -Path $script:ConfigPath -Data $script:Config; $script:AnaCtl.Chart.Invalidate() })
    $chart.Add_Paint({ param($sender, $e) try { Draw-AnalysisChart -g $e.Graphics -W $sender.ClientSize.Width -H $sender.ClientSize.Height } catch { Write-WidgetLog "Analysis chart: $($_.Exception.Message)" "WARN" } })
    $chart.Add_Resize({ param($sender, $e) $sender.Invalidate() })
    $chart.Add_MouseMove({
        param($sender, $e)
        $ac = $script:AnaCtl
        $gm = $ac.Geom
        if ($null -eq $gm -or $e.X -lt $gm.L -or $e.X -gt $gm.R) { if ($ac.HoverIdx -ne -1) { $ac.HoverIdx = -1; $sender.Invalidate() }; return }
        $idx = [int][math]::Round($gm.I0 + ($gm.I1 - $gm.I0) * (($e.X - $gm.L) / [double]($gm.R - $gm.L)))
        if ($idx -ne $ac.HoverIdx) { $ac.HoverIdx = $idx; $sender.Invalidate() }
    })
    $chart.Add_MouseLeave({ param($sender, $e) $script:AnaCtl.HoverIdx = -1; $sender.Invalidate() })
    $bars.Add_Paint({ param($sender, $e) try { Draw-AllocationBars -g $e.Graphics -W $sender.ClientSize.Width -H $sender.ClientSize.Height } catch { Write-WidgetLog "Allocation bars: $($_.Exception.Message)" "WARN" } })
    $bars.Add_Resize({ param($sender, $e) $sender.Invalidate() })
    $divBars.Add_Paint({ param($sender, $e) try { Draw-DividendBars -g $e.Graphics -W $sender.ClientSize.Width -H $sender.ClientSize.Height } catch { Write-WidgetLog "Dividend bars: $($_.Exception.Message)" "WARN" } })
    $divBars.Add_Resize({ param($sender, $e) $sender.Invalidate() })
    $btnBuyDates.Add_Click({ if ([int](@(Show-BuyDatesDialog) | Select-Object -Last 1) -gt 0) { Start-AnalysisLoad } })
    foreach ($k in $dimBtns.Keys) {
        $dimBtns[$k].Add_Click({ param($sender, $e) $script:AnaCtl.Dim = [string]$sender.Tag; Update-AnalysisAllocation })
    }
    $nThr.Add_ValueChanged({
        param($sender, $e)
        $script:Config.ConcentrationWarnPct = [int]$sender.Value
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        Update-AnalysisAllocation
    })
    $pg.Add_CellEndEdit({
        param($sender, $e)
        $col = $sender.Columns[$e.ColumnIndex].Name
        if ($col -notin @("Sector", "Country")) { return }
        $row = $sender.Rows[$e.RowIndex]
        $sym = [string]$row.Cells["Ticker"].Value
        $txt = ([string]$row.Cells[$col].Value).Trim()
        $en = Get-ProfileEntry $sym
        $before = Get-EffectiveProfile $en
        $auto = if ($col -eq "Sector") { $before.Sector } else { $before.Country }
        $field = if ($col -eq "Sector") { "ManualSector" } else { "ManualCountry" }
        # unchanged text = no override; empty = back to automatic
        if ($txt -ne $auto -or -not $txt) { $en.$field = $txt }
        Save-Profiles
        $ef = Get-EffectiveProfile $en
        $row.Cells[$col].Value = if ($col -eq "Sector") { $ef.Sector } else { $ef.Country }
        $srcNow = if ($col -eq "Sector") { $ef.SectorSource } else { $ef.CountrySource }
        $row.Cells[$col].Style.ForeColor = if ($srcNow -eq "manuell") { $script:Pal.Accent } else { $script:Pal.Text }
        $row.Cells["Source"].Value = "{0} / {1}" -f $(if ($ef.SectorSource) { $ef.SectorSource } else { "-" }), $(if ($ef.CountrySource) { $ef.CountrySource } else { "-" })
        $ac = $script:AnaCtl
        $ac.Groups = @(Get-AllocationBreakdown -Items @(Get-AllocationItems))
        $ac.Bars.Invalidate()
    })
    # ---- v5.0: Risiko ----
    $pk = $pages["Risk"]
    $lblRf = New-Object System.Windows.Forms.Label
    $lblRf.SetBounds(0, (S 4), (S 220), (S 18)); $lblRf.Text = "Risikoloser Zins für Sharpe (% p.a.):"
    $pk.Controls.Add($lblRf)
    $nRf = New-Object System.Windows.Forms.NumericUpDown
    $nRf.SetBounds((S 224), (S 1), (S 64), (S 22)); $nRf.DecimalPlaces = 1; $nRf.Increment = 0.5; $nRf.Minimum = 0; $nRf.Maximum = 10
    $nRf.Value = [decimal][math]::Max(0, [math]::Min(10, [double]$script:Config.RiskFreePct))
    $nRf.BackColor = $p.Input; $nRf.ForeColor = $p.Text
    $pk.Controls.Add($nRf)
    Set-DynTip $nRf "Sharpe = (Rendite p.a. - risikoloser Zins) / Volatilität. Höher = mehr Rendite je Schwankung." "SHARPE"
    Set-DynTip $pageBtns["Risk"] "Volatilität, maximaler Rückgang, Sharpe, Beta und Korrelation der Positionen" "DRAWDOWN"
    $lblRiskRange = New-Object System.Windows.Forms.Label
    $lblRiskRange.SetBounds((S 300), (S 4), (S 660), (S 18)); $lblRiskRange.ForeColor = $p.Muted; $lblRiskRange.Anchor = $aT -bor $aL -bor $aR
    $pk.Controls.Add($lblRiskRange)
    $gRisk = New-Object System.Windows.Forms.DataGridView
    $gRisk.SetBounds(0, (S 28), (S 476), (S 300)); $gRisk.Anchor = $aT -bor $aL
    Style-DataGrid -Grid $gRisk
    foreach ($cn in @("Kennzahl", "Depot", "Benchmark")) { [void]$gRisk.Columns.Add($cn, $cn) }
    $gRisk.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $gRisk.Columns["Kennzahl"].FillWeight = 150
    foreach ($cn in @("Depot", "Benchmark")) { $gRisk.Columns[$cn].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    $pk.Controls.Add($gRisk)
    $lblRiskNote = New-Object System.Windows.Forms.Label
    $lblRiskNote.SetBounds((S 490), (S 28), (S 486), (S 300)); $lblRiskNote.Anchor = $aT -bor $aL -bor $aR; $lblRiskNote.ForeColor = $p.Muted
    $lblRiskNote.Text = "Berechnet aus der Wertentwicklung (Seite 1) mit herausgerechneten Ein- und Auszahlungen (zeitgewichtet). Volatilität = Schwankung der Tagesrenditen aufs Jahr hochgerechnet. Max. Drawdown = größter Verlust vom Hoch bis zum Tief. Beta = wie stark das Depot mit der Benchmark mitgeht (1 = gleich stark). Zeitraum wie auf Seite 1 gewählt (6M / 1J / 3J / Max)."
    $pk.Controls.Add($lblRiskNote)
    $lblCorr = New-Object System.Windows.Forms.Label
    $lblCorr.SetBounds(0, (S 336), (S 976), (S 18)); $lblCorr.Font = $fontUiBold; $lblCorr.ForeColor = $p.Accent
    $lblCorr.Text = "Korrelation der Positionen (Tagesrenditen, letzte 12 Monate): 1 = laufen gleich, 0 = unabhängig, -1 = gegenläufig"
    $pk.Controls.Add($lblCorr)
    $gCorr = New-Object System.Windows.Forms.DataGridView
    $gCorr.SetBounds(0, (S 358), (S 976), (S 206)); $gCorr.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Style-DataGrid -Grid $gCorr
    $gCorr.RowHeadersVisible = $true
    $gCorr.RowHeadersWidth = S 90
    $gCorr.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $pk.Controls.Add($gCorr)
    $nRf.Add_ValueChanged({ param($sender, $e) $script:Config.RiskFreePct = [double]$sender.Value; Save-JsonState -Path $script:ConfigPath -Data $script:Config; Update-AnalysisRisk })
    $script:AnaCtl.RiskGrid = $gRisk; $script:AnaCtl.CorrGrid = $gCorr; $script:AnaCtl.RiskRange = $lblRiskRange

    # ---- v5.0: Zielgewichte / Rebalancing ----
    $pt = $pages["Target"]
    $lblMoney = New-Object System.Windows.Forms.Label
    $lblMoney.SetBounds(0, (S 5), (S 92), (S 18)); $lblMoney.Text = "Neues Geld:"
    $pt.Controls.Add($lblMoney)
    $tbMoney = New-Object System.Windows.Forms.TextBox
    $tbMoney.SetBounds((S 94), (S 2), (S 90), (S 22)); $tbMoney.Text = "0"
    $tbMoney.BackColor = $p.Input; $tbMoney.ForeColor = $p.Text; $tbMoney.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle; $tbMoney.Font = $fontMono
    $pt.Controls.Add($tbMoney)
    Set-DynTip $tbMoney "Betrag, der zusätzlich investiert werden soll (in der Basiswährung oben rechts)"
    $chkCashIn = New-Object System.Windows.Forms.CheckBox
    $chkCashIn.SetBounds((S 196), (S 2), (S 170), (S 22)); $chkCashIn.Text = "Cash-Konto einbeziehen"
    $chkCashIn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $chkCashIn.ForeColor = $p.Text
    $chkCashIn.Checked = $true
    $pt.Controls.Add($chkCashIn)
    $chkBuyOnly = New-Object System.Windows.Forms.CheckBox
    $chkBuyOnly.SetBounds((S 372), (S 2), (S 170), (S 22)); $chkBuyOnly.Text = "Nur kaufen (nichts verkaufen)"
    $chkBuyOnly.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $chkBuyOnly.ForeColor = $p.Text
    $pt.Controls.Add($chkBuyOnly)
    $btnEqual = & $mkBtn "Gleich verteilen" (S 556) 0 (S 120) $pt
    $btnClearT = & $mkBtn "Ziele löschen" (S 682) 0 (S 110) $pt
    $gT = New-Object System.Windows.Forms.DataGridView
    $gT.SetBounds(0, (S 32), (S 976), (S 470)); $gT.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Style-DataGrid -Grid $gT
    $gT.ReadOnly = $false
    foreach ($cn in @("Ticker", "Wert", "Ist %", "Ziel %", "Abweichung", "Kauf / Verkauf", "Stück", "Danach %")) { [void]$gT.Columns.Add(($cn -replace '[^A-Za-z]', ''), $cn) }
    $gT.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    foreach ($c in $gT.Columns) {
        $c.ReadOnly = ($c.Name -ne "Ziel")
        $c.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
        if ($c.Index -gt 0) { $c.DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    }
    $gT.Columns["Ziel"].DefaultCellStyle.BackColor = $p.Input
    $gT.Columns["Ziel"].DefaultCellStyle.ForeColor = $p.Accent
    $gT.Columns["Ziel"].ToolTipText = "Ziel-Anteil in % eintragen (Enter). Positionen ohne Ziel bleiben außen vor."
    $pt.Controls.Add($gT)
    $lblTSum = New-Object System.Windows.Forms.Label
    $lblTSum.SetBounds(0, (S 508), (S 976), (S 54)); $lblTSum.Anchor = $aB -bor $aL -bor $aR
    $pt.Controls.Add($lblTSum)
    $script:AnaCtl.TGrid = $gT; $script:AnaCtl.TMoney = $tbMoney; $script:AnaCtl.TCash = $chkCashIn; $script:AnaCtl.TBuyOnly = $chkBuyOnly; $script:AnaCtl.TSum = $lblTSum
    $gT.Add_CellEndEdit({
        param($sender, $e)
        if ($sender.Columns[$e.ColumnIndex].Name -ne "Ziel") { return }
        $sym = [string]$sender.Rows[$e.RowIndex].Cells["Ticker"].Value
        $raw = ([string]$sender.Rows[$e.RowIndex].Cells["Ziel"].Value).Trim() -replace '%', ''
        $tw = Get-TargetWeights
        if (-not $raw) { $tw.Remove($sym) } else { $tw[$sym] = [math]::Max(0.0, [math]::Min(100.0, (Parse-DecimalInput $raw))) }
        Set-TargetWeights $tw
        $sender.BeginInvoke([Action]{ Update-AnalysisTarget }) | Out-Null
    })
    foreach ($ctl in @($chkCashIn, $chkBuyOnly)) { $ctl.Add_CheckedChanged({ Update-AnalysisTarget }) }
    $tbMoney.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $e.SuppressKeyPress = $true; Update-AnalysisTarget } })
    $tbMoney.Add_Leave({ Update-AnalysisTarget })
    $btnEqual.Add_Click({
        $ac = $script:AnaCtl
        if ($null -eq $ac.Model) { return }
        $held = @($ac.Model.Rows | Where-Object { $_.Shares -gt 0 -and $_.Value -gt 0 } | ForEach-Object { $_.Ticker })
        if ($held.Count -eq 0) { return }
        $tw = @{}
        foreach ($h in $held) { $tw[$h] = [math]::Round(100.0 / $held.Count, 2) }
        Set-TargetWeights $tw
        Update-AnalysisTarget
    })
    $btnClearT.Add_Click({ Set-TargetWeights @{}; Update-AnalysisTarget })

    # ---- v5.0: Heatmap ----
    $ph = $pages["Heat"]
    $hmBtns = @{}
    $hx = 0
    foreach ($hk in @(@("Depot", "Depot (Größe = Anteil)"), @("Watch", "Watchlist (gleich groß)"))) {
        $hb = & $mkBtn $hk[1] $hx 0 (S 170) $ph
        $hb.Tag = $hk[0]
        $hmBtns[$hk[0]] = $hb
        $hx += S 176
    }
    $lblHm = New-Object System.Windows.Forms.Label
    $lblHm.SetBounds(($hx + (S 8)), (S 5), (S 600), (S 18)); $lblHm.ForeColor = $p.Muted; $lblHm.Anchor = $aT -bor $aL -bor $aR
    $lblHm.Text = "Farbe = Tagesänderung (grün / rot, kräftiger ab ±3 %). Klick = Ticker öffnen."
    $ph.Controls.Add($lblHm)
    $hm = New-Object System.Windows.Forms.Panel
    $hm.SetBounds(0, (S 32), (S 976), (S 530)); $hm.Anchor = $aT -bor $aB -bor $aL -bor $aR
    $hm.BackColor = $p.BodyBg
    Enable-DoubleBuffering -Control $hm
    $ph.Controls.Add($hm)
    $script:AnaCtl.Heat = $hm; $script:AnaCtl.HeatMode = "Depot"; $script:AnaCtl.HeatBtns = $hmBtns; $script:AnaCtl.HeatRects = @()
    foreach ($hk in $hmBtns.Keys) { $hmBtns[$hk].Add_Click({ param($sender, $e) $script:AnaCtl.HeatMode = [string]$sender.Tag; Update-AnalysisHeat }) }
    $hm.Add_Paint({ param($sender, $e) Draw-Heatmap -g $e.Graphics -W $sender.ClientSize.Width -H $sender.ClientSize.Height })
    $hm.Add_Resize({ param($sender, $e) $sender.Invalidate() })
    $hm.Add_MouseClick({
        param($sender, $e)
        foreach ($t in @($script:AnaCtl.HeatRects)) {
            if ($e.X -ge $t.R[0] -and $e.X -le ($t.R[0] + $t.R[2]) -and $e.Y -ge $t.R[1] -and $e.Y -le ($t.R[1] + $t.R[3])) {
                Switch-ActiveTicker -NewTicker ([string]$t.Sym) -SkipResolve $true
                Set-TransientStatus ("{0} {1}" -f (Tr "Aktiver Ticker:"), $t.Sym) 3
                break
            }
        }
    })

    $applyInputs = {
        $ac = $script:AnaCtl
        $script:Config.AnalysisBase = [string]$ac.Base.SelectedItem
        $script:Config.AnalysisBenchmark = ([string]$ac.Bench.Text).Trim().ToUpper()
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
    }
    # --- v5.1: Beitrag ---
    $pcn = $pages["Contrib"]
    $mkRange = {
        param($Parent)
        $set = @{}
        $x0 = 0
        foreach ($rg in @(@("6M", "6M"), @("1Y", "1J"), @("3Y", "3J"), @("Max", "Max"))) {
            $bt = & $mkBtn $rg[1] $x0 0 (S 46) $Parent
            $bt.Tag = $rg[0]
            $bt.Add_Click({ param($sender, $e) Set-AnalysisRange ([string]$sender.Tag) })
            $set[$rg[0]] = $bt
            $x0 += S 50
        }
        return $set
    }
    $rsC = & $mkRange $pcn
    $lblCInfo = New-Object System.Windows.Forms.Label
    $lblCInfo.SetBounds((S 214), (S 5), (S 760), (S 18)); $lblCInfo.Anchor = $aT -bor $aL -bor $aR; $lblCInfo.ForeColor = $p.Muted; $lblCInfo.AutoEllipsis = $true
    $pcn.Controls.Add($lblCInfo)
    $gC = New-Object System.Windows.Forms.DataGridView
    $gC.SetBounds(0, (S 32), (S 976), (S 290)); $gC.Anchor = $aT -bor $aL -bor $aR
    Style-DataGrid -Grid $gC
    foreach ($cd in @(@("Sym", "Ticker", 80), @("Start", "Anfang", 96), @("Buys", "Käufe", 90), @("Sells", "Verkäufe", 90), @("Divs", "Dividenden", 86), @("End", "Ende", 96), @("Contrib", "Beitrag", 100), @("Pct", "Rendite", 74), @("Share", "Anteil", 70))) {
        $ci = $gC.Columns.Add($cd[0], $cd[1]); $gC.Columns[$ci].FillWeight = [float](S $cd[2]); $gC.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
        if ($ci -ge 1) { $gC.Columns[$ci].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    }
    $gC.Columns["Contrib"].ToolTipText = Tr "Endwert + Verkäufe + Dividenden - Anfangswert - Käufe im Zeitraum"
    $gC.Columns["Pct"].ToolTipText = Tr "Rendite der Position im Zeitraum (Modified Dietz: Käufe / Verkäufe zählen zur Hälfte)"
    $gC.Columns["Share"].ToolTipText = Tr "Anteil am Gesamtergebnis des Depots"
    $gC.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $pcn.Controls.Add($gC)
    $lblCDiv = New-Object System.Windows.Forms.Label
    $lblCDiv.SetBounds(0, (S 328), (S 976), (S 20)); $lblCDiv.Anchor = $aT -bor $aL -bor $aR; $lblCDiv.Font = $fontUiBold; $lblCDiv.AutoEllipsis = $true
    $pcn.Controls.Add($lblCDiv)
    $lblScn = New-Object System.Windows.Forms.Label
    $lblScn.SetBounds(0, (S 358), (S 116), (S 20)); $lblScn.Text = "Szenario: Markt"
    $pcn.Controls.Add($lblScn)
    $nScn = New-Object System.Windows.Forms.NumericUpDown
    $nScn.SetBounds((S 118), (S 355), (S 64), (S 24)); $nScn.Minimum = -60; $nScn.Maximum = 60; $nScn.Increment = 5
    $nScn.Value = [decimal][math]::Max(-60, [math]::Min(60, [int]$script:Config.ScenarioPct))
    $nScn.BackColor = $p.Input; $nScn.ForeColor = $p.Text; $nScn.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $pcn.Controls.Add($nScn)
    Set-DynTip $nScn "Wie stark sich der Markt (die Benchmark) bewegt. Jede Position bewegt sich um Beta x diesen Wert." "BETA"
    $lblScnPct = New-Object System.Windows.Forms.Label
    $lblScnPct.SetBounds((S 186), (S 358), (S 24), (S 20)); $lblScnPct.Text = "%"
    $pcn.Controls.Add($lblScnPct)
    $lblSRes = New-Object System.Windows.Forms.Label
    $lblSRes.SetBounds((S 214), (S 358), (S 760), (S 20)); $lblSRes.Anchor = $aT -bor $aL -bor $aR; $lblSRes.Font = $fontUiBold; $lblSRes.AutoEllipsis = $true
    $pcn.Controls.Add($lblSRes)
    $gS = New-Object System.Windows.Forms.DataGridView
    $gS.SetBounds(0, (S 384), (S 976), (S 178)); $gS.Anchor = $aAll
    Style-DataGrid -Grid $gS
    foreach ($cd in @(@("Sym", "Ticker", 80), @("Val", "Wert", 100), @("Beta", "Beta", 70), @("Src", "Beta aus", 110), @("Chg", "Veränderung", 110), @("ChgPct", "Position %", 80))) {
        $ci = $gS.Columns.Add($cd[0], $cd[1]); $gS.Columns[$ci].FillWeight = [float](S $cd[2]); $gS.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
        if ($ci -ge 1 -and $cd[0] -ne "Src") { $gS.Columns[$ci].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    }
    $gS.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $pcn.Controls.Add($gS)
    $nScn.Add_ValueChanged({ param($sender, $e) $script:Config.ScenarioPct = [int]$sender.Value; Update-AnalysisScenario })
    $script:AnaCtl.CGrid = $gC; $script:AnaCtl.CInfo = $lblCInfo; $script:AnaCtl.CDiv = $lblCDiv; $script:AnaCtl.SGrid = $gS; $script:AnaCtl.SNum = $nScn; $script:AnaCtl.SRes = $lblSRes

    # --- v5.1: Vergleich ---
    $pbn = $pages["Bench"]
    $rsB = & $mkRange $pbn
    $lblIdx = New-Object System.Windows.Forms.Label
    $lblIdx.SetBounds((S 214), (S 5), (S 52), (S 18)); $lblIdx.Text = "Indizes:"
    $pbn.Controls.Add($lblIdx)
    $tbIdx = New-Object System.Windows.Forms.TextBox
    $tbIdx.SetBounds((S 268), (S 2), (S 300), (S 24))
    $tbIdx.BackColor = $p.Input; $tbIdx.ForeColor = $p.Text; $tbIdx.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle; $tbIdx.Font = $fontMono
    $tbIdx.Text = [string]$script:Config.AnalysisCompare
    $pbn.Controls.Add($tbIdx)
    Set-DynTip $tbIdx "Bis zu 6 Yahoo-Symbole mit Komma, z. B. EUNL.DE (MSCI World), ^GSPC (S&P 500), ^GDAXI (DAX), ^ATX, ^NDX, IWDA.AS"
    $btnIdx = & $mkBtn "Laden" (S 574) 0 (S 70) $pbn
    $lblBInfo = New-Object System.Windows.Forms.Label
    $lblBInfo.SetBounds((S 652), (S 5), (S 324), (S 18)); $lblBInfo.Anchor = $aT -bor $aL -bor $aR; $lblBInfo.ForeColor = $p.Muted; $lblBInfo.AutoEllipsis = $true
    $pbn.Controls.Add($lblBInfo)
    $bChart = New-Object System.Windows.Forms.Panel
    $bChart.SetBounds(0, (S 32), (S 976), (S 290)); $bChart.Anchor = $aT -bor $aL -bor $aR
    Enable-DoubleBuffering -Control $bChart
    $pbn.Controls.Add($bChart)
    $gB = New-Object System.Windows.Forms.DataGridView
    $gB.SetBounds(0, (S 330), (S 640), (S 232)); $gB.Anchor = $aAll
    Style-DataGrid -Grid $gB
    foreach ($cd in @(@("N", "Name", 90), @("T", "Zeitraum", 70), @("A", "p.a.", 64), @("V", "Volatilität", 70), @("D", "Max. DD", 66), @("R", "12M jetzt", 70), @("Rmin", "12M min", 64), @("Rmax", "12M max", 64))) {
        $ci = $gB.Columns.Add($cd[0], $cd[1]); $gB.Columns[$ci].FillWeight = [float](S $cd[2]); $gB.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
        if ($ci -ge 1) { $gB.Columns[$ci].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    }
    $gB.Columns["R"].ToolTipText = Tr "Rollierende 12-Monats-Rendite: heute, und die schlechteste / beste aller 12-Monats-Spannen im ganzen Verlauf"
    $gB.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $pbn.Controls.Add($gB)
    $gSec = New-Object System.Windows.Forms.DataGridView
    $gSec.SetBounds((S 648), (S 330), (S 328), (S 232)); $gSec.Anchor = $aT -bor $aB -bor $aR
    Style-DataGrid -Grid $gSec
    foreach ($cd in @(@("S", "Sektor", 140), @("D", "Depot", 60), @("M", "MSCI World", 76), @("X", "Diff.", 52))) {
        $ci = $gSec.Columns.Add($cd[0], $cd[1]); $gSec.Columns[$ci].FillWeight = [float](S $cd[2]); $gSec.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
        if ($ci -ge 1) { $gSec.Columns[$ci].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    }
    $gSec.Columns["X"].ToolTipText = Tr "Prozentpunkte über (+) oder unter (-) dem MSCI World; ETFs und Positionen ohne Sektor stehen unter 'Andere'"
    $gSec.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $pbn.Controls.Add($gSec)
    $bChart.Add_Paint({ param($sender, $e) try { Draw-BenchChart -g $e.Graphics -W $sender.ClientSize.Width -H $sender.ClientSize.Height } catch { Write-WidgetLog "Bench chart: $($_.Exception.Message)" "WARN" } })
    $bChart.Add_Resize({ param($sender, $e) $sender.Invalidate() })
    $applyIdx = {
        $script:Config.AnalysisCompare = (@(($script:AnaCtl.BText.Text) -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { $_.Trim().ToUpper() } | Select-Object -Unique -First 6) -join ", ")
        $script:AnaCtl.BText.Text = [string]$script:Config.AnalysisCompare
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        Start-AnalysisLoad
    }
    $script:AnaCtl.ApplyIdx = $applyIdx
    $btnIdx.Add_Click({ & $script:AnaCtl.ApplyIdx })
    $tbIdx.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $e.SuppressKeyPress = $true; & $script:AnaCtl.ApplyIdx } })
    $script:AnaCtl.BGrid = $gB; $script:AnaCtl.SecGrid = $gSec; $script:AnaCtl.BChart = $bChart; $script:AnaCtl.BInfo = $lblBInfo; $script:AnaCtl.BText = $tbIdx; $script:AnaCtl.BLines = @(); $script:AnaCtl.BDates = @()
    $script:AnaCtl.RangeSets = @($rsC, $rsB)
    & $script:AnaCtl.StyleRange
    $script:AnaCtl.ApplyInputs = $applyInputs
    $btnReload.Add_Click({ & $script:AnaCtl.ApplyInputs; Start-AnalysisLoad -Force $true })
    $cbBase.Add_SelectionChangeCommitted({ & $script:AnaCtl.ApplyInputs; Start-AnalysisLoad })
    $tbBench.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $e.SuppressKeyPress = $true; & $script:AnaCtl.ApplyInputs; Start-AnalysisLoad }
    })
    $dlg.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() }
    })
    $script:AnaCtl.StartPage = $Page
    # v5.0: wider for the seven page buttons (the controls follow their anchors)
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 1000), (S 520))
    $dlg.ClientSize = New-Object System.Drawing.Size((S 1130), $dlg.ClientSize.Height)
    $dlg.Add_Shown({ Show-AnalysisPage ([string]$script:AnaCtl.StartPage); Update-AnalysisAllocation; Start-AnalysisLoad })

    try {
        $owner = if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed) { $script:FsForm } else { $form }
        [void]$dlg.ShowDialog($owner)
    } finally {
        $script:AnaCtl = $null
        $dlg.Dispose()
    }
}

# ------------------------------------------------------------------------------
# Buy dates (v4.2): the date of a buy matters for the value history, XIRR and
# the yearly report. Saving a position asks for it; "Kaufdaten" adds opening
# bookings for unbooked shares and corrects editor bookings dated "today".
# Bookings dated before a split are stored in the units of their own date.
# ------------------------------------------------------------------------------
function Ensure-SplitsLoaded {
    # Split events of these tickers (bounded synchronous lookup, once per session)
    param([string[]]$Tickers)
    $need = @(@($Tickers) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpper() } | Sort-Object -Unique | Where-Object { -not $script:SplitCache.ContainsKey($_) -or -not [bool]$script:SplitCache[$_].Full })
    if ($need.Count -eq 0) { return }
    $urls = @{}
    foreach ($t in $need) { $urls[$t] = "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval=1mo&range=max&events=split" -f [Uri]::EscapeDataString($t) }
    $res = Invoke-ParallelFetch -Urls @($urls.Values)
    foreach ($t in $need) {
        $h = ConvertFrom-YahooDailyHistory -Json $res[$urls[$t]]
        # Full = complete history (range=max); the analysis cache only covers its own window
        if ($null -ne $h) { $script:SplitCache[$t] = @{ Splits = @($h.Splits); ToYear = (Get-Date).Year; Full = $true } }
        else { Write-WidgetLog "Split events for $t not available (offline?)" "WARN" }
    }
}

function Get-BookingUnitsFactor {
    # today's units -> units on Date (1.0 for recent dates, no lookup needed)
    param([string]$Ticker, [string]$Date)
    if (-not $Date) { return 1.0 }
    $d = [DateTime]::ParseExact($Date, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    if (((Get-Date).Date - $d).TotalDays -lt 7) { return 1.0 }
    Ensure-SplitsLoaded -Tickers @($Ticker)
    return (Get-SplitFactorAfter -Splits (Get-SplitMap) -Ticker $Ticker -Date $Date)
}

function Show-BuyDatePrompt {
    # Returns yyyy-MM-dd, or "" when cancelled
    param([string]$Ticker, [double]$Shares)
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Kaufdatum - $Ticker" -W (S 360) -H (S 150)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.SetBounds((S 14), (S 12), (S 332), (S 40))
    $lbl.Text = ("Wann wurden die {0:N4} Stück {1} gekauft?`r`nFür Wertentwicklung, Rendite (XIRR) und Jahresreport." -f $Shares, $Ticker)
    $dlg.Controls.Add($lbl)
    $dp = New-Object System.Windows.Forms.DateTimePicker
    $dp.SetBounds((S 14), (S 60), (S 140), (S 24))
    $dp.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
    $dp.CustomFormat = "dd.MM.yyyy"
    $dp.MaxDate = (Get-Date).Date
    $dp.Value = (Get-Date).Date
    $dlg.Controls.Add($dp)
    Set-DynTip $dp "Tippen oder aus dem Kalender wählen. Enter = übernehmen." "OPENING"
    $ok = New-Object System.Windows.Forms.Button
    $ok.SetBounds((S 156), (S 106), (S 90), (S 28))
    Style-FlatButton -Btn $ok -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $ok.Text = "OK"
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($ok)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.SetBounds((S 252), (S 106), (S 94), (S 28))
    Style-FlatButton -Btn $cancel -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $cancel.Text = "Abbrechen"
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($cancel)
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel
    $dlg.Add_Shown({ param($sender, $e) $sender.ActiveControl = $sender.AcceptButton })
    $res = $dlg.ShowDialog($form)
    $iso = $dp.Value.ToString("yyyy-MM-dd")
    $dlg.Dispose()
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return "" }
    return $iso
}

function Get-BuyDateRows {
    # Opening bookings still missing + editor bookings whose date can be corrected
    $rows = New-Object System.Collections.Generic.List[PSObject]
    $syms = @($script:Portfolio.Keys | ForEach-Object { ([string]$_).ToUpper() } | Sort-Object)
    Ensure-SplitsLoaded -Tickers $syms
    $splits = Get-SplitMap
    $txs = $script:Transactions.ToArray()
    foreach ($sym in $syms) {
        $pf = $script:Portfolio[$sym]
        $r = Get-PositionFromTransactions -Transactions $txs -Ticker $sym -Splits $splits
        $bkSh = 0.0; $bkAvg = [double]$pf.AvgPrice
        if ($null -ne $r) {
            $bkSh = [double]$r.Shares
            if ((Get-NormalizedCurrencyCode ([string]$r.Currency)) -eq (Get-NormalizedCurrencyCode ([string]$pf.Currency))) { $bkAvg = [double]$r.AvgPrice }
        }
        $ob = Get-OpeningBooking -Shares ([double]$pf.Shares) -AvgPrice ([double]$pf.AvgPrice) -BookedShares $bkSh -BookedAvg $bkAvg
        if ($null -ne $ob) {
            $rows.Add([PSCustomObject]@{ Kind = "Open"; Ticker = $sym; What = $(if ($bkSh -gt 0) { "fehlt (Teil)" } else { "ohne Buchung" }); Shares = $ob.Shares; Price = $ob.Price; Currency = [string]$pf.Currency; Date = ""; Tx = $null })
        }
    }
    foreach ($tx in $script:Transactions) {
        if ([string]$tx.Type -eq "Kauf" -and ([string]$tx.Note) -like "Portfolio-Editor*") {
            $rows.Add([PSCustomObject]@{ Kind = "Edit"; Ticker = [string]$tx.Ticker; What = "Editor-Buchung"; Shares = [double]$tx.Shares; Price = [double]$tx.Price; Currency = [string]$tx.Currency; Date = [string]$tx.Date; Tx = $tx })
        }
    }
    return $rows.ToArray()
}

function Show-BuyDatesDialog {
    # Returns the number of changed / added bookings
    $p = $script:Pal
    $rows = @(Get-BuyDateRows)
    $dlg = New-DialogForm -Title "Kaufdaten - $($script:AppTitle)" -W (S 720) -H (S 420)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 600), (S 300))
    $aAll = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $aBR = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $info = New-Object System.Windows.Forms.Label
    $info.SetBounds((S 12), (S 10), (S 696), (S 46))
    $info.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $info.Text = if ($rows.Count -eq 0) { "Alle Positionen sind vollständig gebucht, und es gibt keine Editor-Buchungen zu korrigieren." } else { "Kaufdatum in der letzten Spalte eintragen (TT.MM.JJJJ). 'ohne Buchung' / 'fehlt': es wird ein Kauf nachgebucht (Anfangsbestand), die Position bleibt unverändert. 'Editor-Buchung': das Datum wird korrigiert. Leer lassen = nichts ändern." }
    $dlg.Controls.Add($info)
    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds((S 12), (S 60), (S 696), (S 306))
    $g.Anchor = $aAll
    Style-DataGrid -Grid $g
    $g.ReadOnly = $false
    $g.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::CellSelect
    foreach ($cd in @(@("Ticker", "Ticker", 80, $true), @("What", "Art", 110, $true), @("Shares", "Stück", 90, $true), @("Price", "Kurs", 90, $true), @("Cur", "Whg", 50, $true), @("Date", "Kaufdatum", 100, $false))) {
        $ci = $g.Columns.Add($cd[0], $cd[1])
        $g.Columns[$ci].FillWeight = [float](S $cd[2])
        $g.Columns[$ci].ReadOnly = [bool]$cd[3]
        $g.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    }
    $g.Columns["Date"].DefaultCellStyle.ForeColor = $p.Accent
    $g.Columns["What"].ToolTipText = Get-GlossaryShort -Key "OPENING"
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    foreach ($r in $rows) {
        $dTxt = if ($r.Date) { [DateTime]::ParseExact($r.Date.Substring(0, 10), "yyyy-MM-dd", $inv).ToString("dd.MM.yyyy") } else { "" }
        [void]$g.Rows.Add($r.Ticker, $r.What, ("{0:N4}" -f $r.Shares), ("{0:N4}" -f $r.Price), $r.Currency, $dTxt)
    }
    $dlg.Controls.Add($g)
    $ok = New-Object System.Windows.Forms.Button
    $ok.SetBounds((S 518), (S 378), (S 90), (S 28)); $ok.Anchor = $aBR
    Style-FlatButton -Btn $ok -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $ok.Text = "Übernehmen"
    $dlg.Controls.Add($ok)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.SetBounds((S 614), (S 378), (S 94), (S 28)); $cancel.Anchor = $aBR
    Style-FlatButton -Btn $cancel -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $cancel.Text = "Abbrechen"
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($cancel)
    $dlg.CancelButton = $cancel
    $script:BuyDateCtl = @{ Dlg = $dlg; Grid = $g; Rows = $rows; Changed = 0 }
    $ok.Add_Click({
        $bc = $script:BuyDateCtl
        $bc.Grid.EndEdit() | Out-Null
        $today = (Get-Date).ToString("yyyy-MM-dd")
        $plan = @()
        for ($i = 0; $i -lt $bc.Rows.Count; $i++) {
            $txt = ([string]$bc.Grid.Rows[$i].Cells["Date"].Value).Trim()
            $r = $bc.Rows[$i]
            if (-not $txt) { continue }
            $iso = ConvertTo-IsoDate $txt
            if (-not $iso -or [string]::CompareOrdinal($iso, $today) -gt 0) {
                [System.Windows.Forms.MessageBox]::Show($bc.Dlg, ("{0}: '{1}' ist kein gültiges Datum (TT.MM.JJJJ, nicht in der Zukunft)." -f $r.Ticker, $txt), "Kaufdaten",
                    [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                $bc.Grid.CurrentCell = $bc.Grid.Rows[$i].Cells["Date"]
                return
            }
            if ($r.Kind -eq "Edit" -and $iso -eq ([string]$r.Date).Substring(0, 10)) { continue }
            $plan += ,@($r, $iso)
        }
        foreach ($pl in $plan) {
            $r = $pl[0]; $iso = $pl[1]
            $fD = Get-BookingUnitsFactor -Ticker $r.Ticker -Date $iso
            if ($r.Kind -eq "Open") {
                Add-TransactionRecord -Type "Kauf" -Ticker $r.Ticker -Shares ($r.Shares / $fD) -Price ($r.Price * $fD) -Fee 0 -Currency $r.Currency -Date $iso -Note "Anfangsbestand (nachgetragen)"
                Write-WidgetLog ("Opening booking: {0} {1:N4} @ {2:N4} {3} on {4} (split factor {5})" -f $r.Ticker, $r.Shares, $r.Price, $r.Currency, $iso, $fD)
            } else {
                $fR = Get-BookingUnitsFactor -Ticker $r.Ticker -Date ([string]$r.Date).Substring(0, 10)
                $r.Tx.Shares = [double]$r.Tx.Shares * $fR / $fD
                $r.Tx.Price = [double]$r.Tx.Price * $fD / $fR
                $r.Tx.Date = $iso
                Write-WidgetLog ("Editor booking of {0} moved from {1} to {2}" -f $r.Ticker, $r.Date, $iso)
            }
            $bc.Changed++
        }
        if ($bc.Changed -gt 0) { Save-Transactions }
        $bc.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $bc.Dlg.Close()
    })
    $owner = if ($null -ne $script:AnaCtl) { $script:AnaCtl.Dlg } else { $form }
    [void]$dlg.ShowDialog($owner)
    $n = [int]$script:BuyDateCtl.Changed
    $script:BuyDateCtl = $null
    $dlg.Dispose()
    if ($n -gt 0) { Set-TransientStatus ("{0} Kaufdatum/-daten übernommen" -f $n) 4 }
    return $n
}

# ==============================================================================
# v4.4: terminal command line (Ctrl+K), news, description, dividends per
# ticker, event calendar, movers, FX, about / update check
# ==============================================================================
$script:InfoCtl = $null
$script:PalCtl  = $null
$script:RepoUrl = "https://github.com/therealwootwoot/TerminalWidget"

function Get-KnownTickers {
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($t in (@($script:Config.Watchlist) + @($script:Portfolio.Keys) + @($script:QuoteStore.Keys))) {
        $u = ([string]$t).ToUpper()
        if ($u -and -not $list.Contains($u)) { $list.Add($u) }
    }
    return $list.ToArray()
}

function Open-Link {
    param([string]$Url)
    if ($Url -match '^https?://') { try { Start-Process -FilePath $Url } catch { Write-WidgetLog "Link could not be opened: $Url" "WARN" } }
}

function Show-InfoGrid {
    # Read-only list dialog used by the terminal functions. Rows are filled
    # with Set-InfoRows (also later, from a background fetch). $OnDouble gets
    # the Tag of the double-clicked row.
    param([string]$Title, [string[]]$Columns, [int[]]$Weights, [int]$W = 780, [int]$H = 480,
          [string]$Footer = "", [scriptblock]$OnShown = $null, [scriptblock]$OnDouble = $null, [hashtable]$Extra = @{}, [int[]]$RightAlign = @())
    $p = $script:Pal
    $dlg = New-DialogForm -Title $Title -W (S $W) -H (S $H)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 420), (S 260))
    $dlg.KeyPreview = $true
    $dlg.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() } })
    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds((S 12), (S 12), (S ($W - 24)), (S ($H - 64)))
    $g.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    Style-DataGrid -Grid $g
    for ($i = 0; $i -lt $Columns.Count; $i++) {
        $ci = $g.Columns.Add(("c{0}" -f $i), $Columns[$i])
        $g.Columns[$ci].FillWeight = [float](S $(if ($i -lt $Weights.Count) { $Weights[$i] } else { 100 }))
        if ($RightAlign -contains $i) { $g.Columns[$ci].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    }
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dlg.Controls.Add($g)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.SetBounds((S 12), (S ($H - 44)), (S ($W - 130)), (S 36))
    $lbl.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $lbl.ForeColor = $p.Muted
    $lbl.Text = $Footer
    $dlg.Controls.Add($lbl)
    $btn = New-Object System.Windows.Forms.Button
    $btn.SetBounds((S ($W - 106)), (S ($H - 42)), (S 94), (S 28))
    $btn.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    Style-FlatButton -Btn $btn -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btn.Text = "Schließen"
    $btn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btn)
    $dlg.CancelButton = $btn
    $prev = $script:InfoCtl
    $script:InfoCtl = @{ Dlg = $dlg; Grid = $g; Footer = $lbl; OnShown = $OnShown; OnDouble = $OnDouble }
    foreach ($k in $Extra.Keys) { $script:InfoCtl[$k] = $Extra[$k] }
    if ($null -ne $OnDouble) {
        $g.Add_CellDoubleClick({
            param($sender, $e)
            if ($e.RowIndex -lt 0 -or $null -eq $script:InfoCtl) { return }
            $tag = $sender.Rows[$e.RowIndex].Tag
            if ($null -ne $tag) { & $script:InfoCtl.OnDouble $tag }
        })
    }
    if ($null -ne $OnShown) { $dlg.Add_Shown({ if ($null -ne $script:InfoCtl) { & $script:InfoCtl.OnShown } }) }
    [void]$dlg.ShowDialog($form)
    $script:InfoCtl = $prev
    $dlg.Dispose()
}

function Set-InfoRows {
    # Rows: @(@{ Cells = @(...); Tag = ...; Color = ...; CellColors = @{ idx = color } })
    param($Rows, $Footer = $null)
    $ic = $script:InfoCtl
    if ($null -eq $ic -or $ic.Dlg.IsDisposed) { return }
    $g = $ic.Grid
    $g.Rows.Clear()
    foreach ($r in @($Rows)) {
        if ($null -eq $r) { continue }
        $i = $g.Rows.Add([object[]]@($r.Cells))
        $row = $g.Rows[$i]
        $row.Tag = $r.Tag
        if ($null -ne $r.Color) { $row.DefaultCellStyle.ForeColor = $r.Color }
        if ($null -ne $r.CellColors) { foreach ($k in $r.CellColors.Keys) { $row.Cells[[int]$k].Style.ForeColor = $r.CellColors[$k] } }
    }
    if ($null -ne $Footer) { $ic.Footer.Text = [string]$Footer }
}

function Get-SignColor {
    param([double]$V)
    if ([double]::IsNaN($V) -or $V -eq 0) { return $script:Pal.Text }
    if ($V -gt 0) { return $colGreen }
    return $colRed
}

# ---- N: news ----
function Show-NewsDialog {
    param([string]$Ticker)
    $sym = ([string]$Ticker).Trim().ToUpper()
    if (-not $sym) { return }
    $url = "https://query1.finance.yahoo.com/v1/finance/search?q={0}&quotesCount=0&newsCount=25" -f [Uri]::EscapeDataString($sym)
    Show-InfoGrid -Title "Nachrichten - $sym (N)" -Columns @("Zeit", "Quelle", "Titel") -Weights @(90, 120, 560) -W 900 -H 520 -Footer "Lade Nachrichten ..." -Extra @{ Url = $url; Sym = $sym } -OnDouble { param($Tag) Open-Link ([string]$Tag) } -OnShown {
        Start-FetchJob -Urls @($script:InfoCtl.Url) -MaxConcurrency 1 -Context @{ Url = $script:InfoCtl.Url } -OnComplete {
            param($Box, $Ctx)
            $items = @(ConvertFrom-YahooNews $Box.Results[$Ctx.Url])
            $rows = foreach ($n in $items) {
                $tTxt = if ($n.Time -gt [DateTime]::MinValue) { $n.Time.ToString("dd.MM. HH:mm") } else { "" }
                @{ Cells = @($tTxt, $n.Publisher, $n.Title); Tag = $n.Link }
            }
            $foot = if ($items.Count -gt 0) { "{0} Meldungen (Yahoo Finance). Doppelklick öffnet den Artikel im Browser." -f $items.Count } else { "Keine Nachrichten gefunden (offline oder unbekannter Ticker)." }
            Set-InfoRows -Rows $rows -Footer $foot
        }
    }
}

# v4.9.5: analyst target text (tooltip and DES)
function Get-AnalystText {
    param($Ev, [double]$Price, [string]$Currency)
    if ($null -eq $Ev) { return "" }
    $lines = @()
    $tm = [double]$Ev.TargetMean
    if (-not [double]::IsNaN($tm) -and $tm -gt 0) {
        $up = Get-TargetUpside -Target $tm -Price $Price
        $line = "Kursziel (Mittel): {0:N2} {1}" -f $tm, $Currency
        if (-not [double]::IsNaN($up)) { $line += " ({0:+0.0;-0.0}%)" -f $up }
        $lines += $line
        if (-not [double]::IsNaN([double]$Ev.TargetLow) -and -not [double]::IsNaN([double]$Ev.TargetHigh)) { $lines += ("Spanne: {0:N2} - {1:N2}" -f [double]$Ev.TargetLow, [double]$Ev.TargetHigh) }
    }
    $lab = Get-ConsensusLabel ([string]$Ev.RecKey) -Long
    if ($lab) {
        $l2 = "Empfehlung: $lab"
        if (-not [double]::IsNaN([double]$Ev.RecMean)) { $l2 += " ({0:N1} auf 1 = Kauf ... 5 = Verkauf)" -f [double]$Ev.RecMean }
        $lines += $l2
    }
    if (-not [double]::IsNaN([double]$Ev.Analysts) -and [double]$Ev.Analysts -gt 0) { $lines += ("{0:N0} Analysten (Yahoo Finance)" -f [double]$Ev.Analysts) }
    return ($lines -join "`r`n")
}

# ---- DES: description ----
function Get-DescriptionRows {
    param([string]$Sym)
    $rows = New-Object System.Collections.Generic.List[object]
    $add = { param([string]$K, [string]$V, $C = $null) if ($V) { $rows.Add(@{ Cells = @($K, $V); Color = $null; CellColors = $(if ($null -ne $C) { @{ 1 = $C } } else { $null }) }) } }
    $q = $script:QuoteStore[$Sym]
    $pr = $script:Profiles[$Sym]
    $ev = $script:Events[$Sym]
    $curr = Get-PriceCurrency $Sym
    $name = if ($null -ne $pr -and $pr.Name) { [string]$pr.Name } elseif ($null -ne $q) { [string]$q.LongName } else { "" }
    & $add "Name" $name
    if ($null -ne $pr) {
        $ef = Get-EffectiveProfile $pr
        & $add "Typ" ([string]$pr.QuoteType)
        & $add "Sektor" ([string]$ef.Sector)
        & $add "Branche" ([string]$pr.Industry)
        & $add "Land" ([string]$ef.Country)
    }
    if ($null -ne $q) {
        if ($null -ne $q.Tp -and $q.Tp.Exchange) { & $add "Börse" ([string]$q.Tp.Exchange) }
        & $add "Währung" ([string]$q.Currency)
        $stand = if ([bool]$q.FromCache) { " (Cache)" } else { "" }
        & $add "Kurs" ("{0:N2} {1}{2}" -f $q.Price, $q.Currency, $stand)
        & $add "Tagesänderung" ("{0:+0.00;-0.00}%" -f $q.ChangePct) (Get-SignColor ([double]$q.ChangePct))
        if ([double]$q.High52 -gt 0) { & $add "52W Hoch" ("{0:N2} ({1:+0.0;-0.0}%)" -f $q.High52, (([double]$q.Price / [double]$q.High52 - 1) * 100)) }
        if ([double]$q.Low52 -gt 0) { & $add "52W Tief" ("{0:N2} ({1:+0.0;-0.0}%)" -f $q.Low52, (([double]$q.Price / [double]$q.Low52 - 1) * 100)) }
        if (-not [double]::IsNaN([double]$q.Rsi14)) { & $add "RSI (1h)" ("{0:N1}" -f $q.Rsi14) }
        if ($null -ne $q.RelVol -and -not [double]::IsNaN([double]$q.RelVol)) { & $add "Volumen vs. üblich" ("{0:N1}x" -f $q.RelVol) }
        $ms = Get-MarketState -Tp $q.Tp -NowSec ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        if ($null -ne $ms) { & $add "Markt" ([string]$ms.Short) }
    }
    if ($null -ne $ev) {
        & $add "Quartalszahlen" (Format-IsoDateDe $ev.EarningsDate)
        & $add "Ex-Tag" (Format-IsoDateDe $ev.ExDividendDate)
        & $add "Zahltag" (Format-IsoDateDe $ev.DividendDate)
        if (-not [double]::IsNaN([double]$ev.DividendRate) -and [double]$ev.DividendRate -gt 0) { & $add "Dividende p.a." ("{0:N2}" -f $ev.DividendRate) }
        if (-not [double]::IsNaN([double]$ev.DividendYield) -and [double]$ev.DividendYield -gt 0) { & $add "Dividendenrendite" ("{0:N2}%" -f ([double]$ev.DividendYield * 100)) }
        # v4.9.5: analysts
        $tm = [double]$ev.TargetMean
        if (-not [double]::IsNaN($tm) -and $tm -gt 0) {
            $pNow = if ($null -ne $q) { [double]$q.Price } else { [double]::NaN }
            $upD = Get-TargetUpside -Target $tm -Price $pNow
            $cc = if ($null -ne $q) { [string]$q.Currency } else { "" }
            $tTxt = "{0:N2} {1}" -f $tm, $cc
            if (-not [double]::IsNaN($upD)) { $tTxt += " ({0:+0.0;-0.0}%)" -f $upD }
            & $add "Kursziel Analysten" $tTxt $(if ([double]::IsNaN($upD)) { $null } else { Get-SignColor $upD })
            if (-not [double]::IsNaN([double]$ev.TargetLow) -and -not [double]::IsNaN([double]$ev.TargetHigh)) { & $add "Kursziel-Spanne" ("{0:N2} - {1:N2}" -f [double]$ev.TargetLow, [double]$ev.TargetHigh) }
        }
        $cl = Get-ConsensusLabel ([string]$ev.RecKey) -Long
        if ($cl) {
            $nA = if (-not [double]::IsNaN([double]$ev.Analysts)) { " ({0:N0} Analysten)" -f [double]$ev.Analysts } else { "" }
            & $add "Empfehlung" ($cl + $nA)
        }
    }
    if ($script:Portfolio.ContainsKey($Sym)) {
        $pf = $script:Portfolio[$Sym]
        & $add "Position" ("{0:N4} Stk @ {1:N2} {2}" -f $pf.Shares, $pf.AvgPrice, $pf.Currency)
        if ($null -ne $q -and [double]$q.Price -gt 0) {
            $val = [double]$pf.Shares * (Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $curr)
            $cost = [double]$pf.Shares * (Convert-CurrencyValue -Amount ([double]$pf.AvgPrice) -FromCurrency ([string]$pf.Currency) -ToCurrency $curr)
            & $add "Wert" ("{0:N2} {1}" -f $val, $curr)
            if ($cost -gt 0) { & $add "G/V" ("{0:+#,##0.00;-#,##0.00} {1} ({2:+0.0;-0.0}%)" -f ($val - $cost), $curr, (($val / $cost - 1) * 100)) (Get-SignColor ($val - $cost)) }
        }
    }
    $nA = @($script:Alerts | Where-Object { $_.Ticker -eq $Sym }).Count
    if ($nA -gt 0) { & $add "Alarme" ("{0}" -f $nA) }
    if ($rows.Count -eq 0) { $rows.Add(@{ Cells = @("", "Noch keine Daten - werden geladen ..."); Color = $script:Pal.Muted }) }
    return $rows.ToArray()
}

function Show-DescriptionDialog {
    param([string]$Ticker)
    $sym = ([string]$Ticker).Trim().ToUpper()
    if (-not $sym) { return }
    Show-InfoGrid -Title "Beschreibung - $sym (DES)" -Columns @("Feld", "Wert") -Weights @(160, 420) -W 560 -H 560 -Footer "N = Nachrichten, DVD = Dividenden, EE = Termine (Strg+K)" -Extra @{ Sym = $sym } -OnShown {
        $s = [string]$script:InfoCtl.Sym
        Set-InfoRows -Rows (Get-DescriptionRows $s)
        $q = $script:QuoteStore[$s]
        if ($null -eq $q -or [bool]$q.FromCache) {
            $u = Get-ChartUrl -Symbol $s -Interval "1h" -Range "5d" -PrePost
            Start-FetchJob -Urls @($u) -MaxConcurrency 1 -Context @{ Url = $u; Sym = $s } -OnComplete {
                param($Box, $Ctx)
                $r = Get-ChartResult $Box.Results[$Ctx.Url]
                if ($null -ne $r) { Update-QuoteFromResult -Sym $Ctx.Sym -R $r -RsiPeriod ([int]$script:Config.RsiPeriod) }
                if ($null -ne $script:InfoCtl -and $script:InfoCtl.Sym -eq $Ctx.Sym) { Set-InfoRows -Rows (Get-DescriptionRows $Ctx.Sym) }
            }
        }
        if ((Test-ProfileStale -Entry $script:Profiles[$s]) -or (Test-EventsStale -Entry $script:Events[$s])) {
            Start-ProfileJob -Symbols @($s) -OnComplete { if ($null -ne $script:InfoCtl -and $script:InfoCtl.Sym) { Set-InfoRows -Rows (Get-DescriptionRows ([string]$script:InfoCtl.Sym)) } }
        }
    }
}

# ---- v5.1: TA / FA <ticker>: technical signals + fundamentals in one window ----
$script:TaCtl = $null

function Get-FundPeers {
    # other tickers of your depot + watchlist in the same sector with fundamentals
    param([string]$Sym)
    $sec = ""
    $pr = $script:Profiles[$Sym]
    if ($null -ne $pr) { $sec = [string]$pr.Sector }
    if (-not $sec) { return [PSCustomObject]@{ Sector = ""; Peers = @(); Syms = @() } }
    $peers = @(); $names = @()
    foreach ($k in @($script:Events.Keys)) {
        $u = ([string]$k).ToUpper()
        if ($u -eq $Sym) { continue }
        $e = $script:Events[$u]
        $p2 = $script:Profiles[$u]
        if ($null -eq $e -or $null -eq $e.Fund -or $null -eq $p2 -or [string]$p2.Sector -ne $sec) { continue }
        $peers += $e.Fund; $names += $u
    }
    return [PSCustomObject]@{ Sector = $sec; Peers = $peers; Syms = $names }
}

function Update-TickerAnalysis {
    $c = $script:TaCtl
    if ($null -eq $c -or $c.Dlg.IsDisposed) { return }
    $sym = [string]$c.Sym
    $p = $script:Pal
    $q = $script:QuoteStore[$sym]
    $pr = $script:Profiles[$sym]
    $name = if ($null -ne $q -and $q.LongName) { [string]$q.LongName } elseif ($null -ne $c.Bars) { [string]$c.Bars.Name } else { $sym }
    $secTxt = if ($null -ne $pr -and $pr.Sector) { " · {0}{1}" -f $pr.Sector, $(if ($pr.Industry) { " / " + $pr.Industry } else { "" }) } else { "" }
    $pxTxt = ""
    if ($null -ne $q) { $pc = Get-PriceCurrency $sym; $pxTxt = "  ·  {0:N2} {1} ({2:+0.00;-0.00}%)" -f (Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $pc), $pc, [double]$q.ChangePct }
    $c.Title.Text = "{0}  {1}{2}{3}" -f $sym, $name, $secTxt, $pxTxt

    # technical
    $g = $c.TGrid
    $g.Rows.Clear()
    if ($null -ne $c.Bars) {
        $sig = Get-TechnicalSignals -Closes ([double[]]$c.Bars.Close) -Highs ([double[]]$c.Bars.High) -Lows ([double[]]$c.Bars.Low) -Volumes ([double[]]$c.Bars.Volume)
        $c.Sig = $sig
        foreach ($r in $sig.Rows) {
            $i = $g.Rows.Add((Tr $r.Name), $r.Value, (Tr $r.Text))
            $col = if ($r.Score -gt 0) { $colGreen } elseif ($r.Score -lt 0) { $colRed } else { $p.Muted }
            $g.Rows[$i].Cells[2].Style.ForeColor = $col
        }
        $sc = [int]$sig.Score
        $c.TSum.ForeColor = if ($sc -ge 3) { $colGreen } elseif ($sc -le -3) { $colRed } else { $script:Pal.Warn }
        $c.TSum.Text = "{0}: {1}  ({2} {3}, {4} {5}; {6} {7})" -f (Tr "Signale"), (Tr $sig.Summary), $sig.Positive, (Tr "positiv"), $sig.Negative, (Tr "negativ"), (Tr "Kurse in"), $c.Bars.Currency
    } elseif ($c.Failed) {
        [void]$g.Rows.Add((Tr "Kursverlauf nicht verfügbar"), "", "")
        $c.TSum.Text = ""
    } else {
        [void]$g.Rows.Add((Tr "Lade Kursverlauf (2 Jahre) ..."), "", "")
        $c.TSum.Text = ""
    }
    $c.Chart.Invalidate()

    # fundamentals
    $f = $c.FGrid
    $f.Rows.Clear()
    $ev = $script:Events[$sym]
    $fund = if ($null -ne $ev) { $ev.Fund } else { $null }
    if ($null -eq $fund) {
        $msg = if ($script:WorkerShared.CrumbFailed) { "Kennzahlen brauchen den Yahoo-Zugang (Crumb) - gerade nicht verfügbar" } elseif ($c.FundTried -and -not $script:ProfileJobRunning) { "Yahoo hat für diesen Ticker keine Kennzahlen (ETF / Index?)" } else { "Lade Kennzahlen ..." }
        [void]$f.Rows.Add((Tr $msg), "", "", "")
        $c.FNote.Text = ""
        return
    }
    $pe = Get-FundPeers -Sym $sym
    foreach ($r in @(Get-FundamentalRows -Fund $fund -Peers $pe.Peers)) {
        $i = $f.Rows.Add((Tr $r.Name), $r.Value, $(if ($r.PeerCount -ge 2) { $r.Peer } else { "-" }), (Tr $r.Note))
        $col = if ($r.Score -gt 0) { $colGreen } elseif ($r.Score -lt 0) { $colRed } else { $p.Muted }
        $f.Rows[$i].Cells[3].Style.ForeColor = $col
        if ($r.Value -eq "-") { $f.Rows[$i].Cells[1].Style.ForeColor = $p.Muted }
    }
    $c.FNote.Text = if (@($pe.Syms).Count -ge 2) {
        "{0} {1} ({2}): {3}" -f (Tr "Vergleich = Median deiner Ticker aus"), $pe.Sector, @($pe.Syms).Count, ((@($pe.Syms) | Select-Object -First 8) -join ", ")
    } elseif ($pe.Sector) {
        "{0} '{1}' {2}" -f (Tr "Für einen Vergleich fehlen weitere Ticker aus"), $pe.Sector, (Tr "in Depot / Watchlist (mind. 2)")
    } else { Tr "Sektor unbekannt - kein Vergleich" }
}

function Draw-TickerAnalysisChart {
    param($g, [int]$W, [int]$H)
    $c = $script:TaCtl
    $p = $script:Pal
    $g.Clear($p.Card)
    if ($null -eq $c -or $null -eq $c.Bars -or @($c.Bars.Close).Count -lt 2) { return }
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $cl = [double[]]$c.Bars.Close
    $n0 = $cl.Count
    $show = [math]::Min(252, $n0)
    $st = $n0 - $show
    $s50 = Compute-Sma -Prices $cl -Period 50
    $s200 = Compute-Sma -Prices $cl -Period 200
    $lv = New-Object System.Collections.Generic.List[double]
    for ($i = $st; $i -lt $n0; $i++) { $lv.Add($cl[$i]); foreach ($a in @($s50[$i], $s200[$i])) { if (-not [double]::IsNaN([double]$a)) { $lv.Add([double]$a) } } }
    $sr = if ($null -ne $c.Sig) { $c.Sig.Support } else { $null }
    $mn = ($lv | Measure-Object -Minimum).Minimum; $mx = ($lv | Measure-Object -Maximum).Maximum
    if ($mx -le $mn) { $mx = $mn + 1 }
    $pad = ($mx - $mn) * 0.06; $mn -= $pad; $mx += $pad
    $l = S 8; $t = S 8; $r = $W - (S 62); $b = $H - (S 20)
    $toX = { param([int]$i) $l + ($i - $st) / [double]([math]::Max(1, $show - 1)) * ($r - $l) }
    $toY = { param([double]$v) $b - ($v - $mn) / ($mx - $mn) * ($b - $t) }
    $gp = New-Object System.Drawing.Pen($p.Grid, [float]1)
    $tb = New-Object System.Drawing.SolidBrush($p.Muted)
    try {
        for ($k = 0; $k -le 4; $k++) {
            $v = $mn + ($mx - $mn) * $k / 4.0
            $y = & $toY $v
            $g.DrawLine($gp, [float]$l, [float]$y, [float]$r, [float]$y)
            $g.DrawString(("{0:N2}" -f $v), $fontAxis, $tb, [float]($r + (S 4)), [float]($y - (S 7)))
        }
        # support / resistance (dashed)
        if ($null -ne $sr) {
            foreach ($lvl in @(@($sr.Support, $colGreen, "S"), @($sr.Resistance, $colRed, "W"))) {
                $x = [double]$lvl[0]
                if ([double]::IsNaN($x) -or $x -lt $mn -or $x -gt $mx) { continue }
                $dp = New-Object System.Drawing.Pen($lvl[1], [float]1)
                $dp.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
                $y = & $toY $x
                $g.DrawLine($dp, [float]$l, [float]$y, [float]$r, [float]$y)
                $dp.Dispose()
            }
        }
        foreach ($ser in @(@($s200, [System.Drawing.Color]::FromArgb(168, 85, 247), [float]1.2), @($s50, $script:Pal.Warn, [float]1.2), @($cl, $p.Accent, [float]1.8))) {
            $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
            for ($i = $st; $i -lt $n0; $i++) {
                $v = [double]$ser[0][$i]
                if ([double]::IsNaN($v)) { continue }
                $pts.Add((New-Object System.Drawing.PointF([float](& $toX $i), [float](& $toY $v))))
            }
            if ($pts.Count -ge 2) { $pn = New-Object System.Drawing.Pen($ser[1], $ser[2]); $g.DrawLines($pn, $pts.ToArray()); $pn.Dispose() }
        }
        $leg = "{0}   SMA 50   SMA 200   {1}" -f (Tr "Kurs 12 Monate"), (Tr "- - Unterstützung / Widerstand")
        $g.DrawString($leg, $fontAxis, $tb, [float]$l, [float]($b + (S 3)))
    } finally { $gp.Dispose(); $tb.Dispose() }
}

function Show-TickerAnalysis {
    param([string]$Ticker)
    $sym = ([string]$Ticker).Trim().ToUpper()
    if (-not $sym) { return }
    if ($null -ne $script:TaCtl -and -not $script:TaCtl.Dlg.IsDisposed) { $script:TaCtl.Dlg.Close() }
    $p = $script:Pal
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right
    $dlg = New-DialogForm -Title "Ticker-Analyse - $sym (TA)" -W (S 1080) -H (S 660)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MaximizeBox = $true
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 900), (S 520))
    $title = New-Object System.Windows.Forms.Label
    $title.SetBounds((S 12), (S 10), (S 1056), (S 24)); $title.Anchor = $aT -bor $aL -bor $aR
    $title.Font = $fontUiBold; $title.ForeColor = $p.Accent; $title.AutoEllipsis = $true
    $dlg.Controls.Add($title)
    $half = S 528
    $lt = New-Object System.Windows.Forms.Label
    $lt.SetBounds((S 12), (S 40), $half, (S 18)); $lt.Text = "Technische Signale (Tageskurse)"; $lt.Font = $fontUiBold
    $dlg.Controls.Add($lt)
    $chart = New-Object System.Windows.Forms.Panel
    $chart.SetBounds((S 12), (S 60), $half, (S 200)); $chart.Anchor = $aT -bor $aL
    Enable-DoubleBuffering -Control $chart
    $dlg.Controls.Add($chart)
    $tg = New-Object System.Windows.Forms.DataGridView
    $tg.SetBounds((S 12), (S 266), $half, (S 326)); $tg.Anchor = $aT -bor $aB -bor $aL
    Style-DataGrid -Grid $tg
    foreach ($cd in @(@("Sig", "Signal", 150), @("Val", "Wert", 130), @("Txt", "Einordnung", 210))) { $ci = $tg.Columns.Add($cd[0], $cd[1]); $tg.Columns[$ci].FillWeight = [float](S $cd[2]); $tg.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable }
    $tg.Columns[1].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight
    $tg.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dlg.Controls.Add($tg)
    $tsum = New-Object System.Windows.Forms.Label
    $tsum.SetBounds((S 12), (S 596), $half, (S 20)); $tsum.Anchor = $aB -bor $aL; $tsum.Font = $fontUiBold; $tsum.AutoEllipsis = $true
    $dlg.Controls.Add($tsum)
    $rx = S 552
    $lf = New-Object System.Windows.Forms.Label
    $lf.SetBounds($rx, (S 40), (S 516), (S 18)); $lf.Text = "Kennzahlen"; $lf.Font = $fontUiBold; $lf.Anchor = $aT -bor $aL -bor $aR
    $dlg.Controls.Add($lf)
    $fg = New-Object System.Windows.Forms.DataGridView
    $fg.SetBounds($rx, (S 60), (S 516), (S 532)); $fg.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Style-DataGrid -Grid $fg
    foreach ($cd in @(@("K", "Kennzahl", 170), @("V", "Wert", 110), @("P", "Vergleich", 100), @("E", "Einordnung", 150))) { $ci = $fg.Columns.Add($cd[0], $cd[1]); $fg.Columns[$ci].FillWeight = [float](S $cd[2]); $fg.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable }
    $fg.Columns[1].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight
    $fg.Columns[2].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight
    $fg.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dlg.Controls.Add($fg)
    $fnote = New-Object System.Windows.Forms.Label
    $fnote.SetBounds($rx, (S 596), (S 516), (S 20)); $fnote.Anchor = $aB -bor $aL -bor $aR; $fnote.ForeColor = $p.Muted; $fnote.AutoEllipsis = $true
    $dlg.Controls.Add($fnote)
    $disc = New-Object System.Windows.Forms.Label
    $disc.SetBounds((S 12), (S 626), (S 900), (S 20)); $disc.Anchor = $aB -bor $aL -bor $aR; $disc.ForeColor = $p.Muted
    $disc.Text = "Zusammenfassung klassischer Indikatoren und Kennzahlen - keine Anlageberatung."
    $dlg.Controls.Add($disc)
    $ok = New-Object System.Windows.Forms.Button
    $ok.SetBounds((S 968), (S 622), (S 100), (S 28)); $ok.Anchor = $aB -bor $aR; $ok.Text = "Schließen"
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Style-FlatButton -Btn $ok -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $dlg.Controls.Add($ok); $dlg.CancelButton = $ok
    # the chart grows with the window width (left half)
    $dlg.Add_Resize({
        param($sender, $e)
        $c0 = $script:TaCtl
        if ($null -eq $c0) { return }
        $w2 = [int](($sender.ClientSize.Width - (S 36)) / 2)
        foreach ($ctl in @($c0.Chart, $c0.TGrid, $c0.TSum)) { $ctl.Width = $w2 }
        foreach ($ctl in @($c0.FGrid, $c0.FNote, $c0.FLabel)) { $ctl.Left = $w2 + (S 24); $ctl.Width = $sender.ClientSize.Width - $w2 - (S 36) }
    })
    $chart.Add_Paint({ param($sender, $e) try { Draw-TickerAnalysisChart -g $e.Graphics -W $sender.ClientSize.Width -H $sender.ClientSize.Height } catch { Write-WidgetLog "TA chart: $($_.Exception.Message)" "WARN" } })
    $script:TaCtl = @{ Sym = $sym; Dlg = $dlg; Title = $title; Chart = $chart; TGrid = $tg; TSum = $tsum; FGrid = $fg; FNote = $fnote; FLabel = $lf; Bars = $null; Sig = $null; Failed = $false; FundTried = $false }
    $dlg.Add_Shown({
        Update-TickerAnalysis
        $c0 = $script:TaCtl
        $u = "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval=1d&range=2y" -f [Uri]::EscapeDataString($c0.Sym)
        Start-FetchJob -Urls @($u) -MaxConcurrency 1 -Context @{ Url = $u; Sym = $c0.Sym } -OnComplete {
            param($Box, $Ctx)
            $c1 = $script:TaCtl
            if ($null -eq $c1 -or $c1.Sym -ne $Ctx.Sym) { return }
            $c1.Bars = ConvertFrom-YahooOhlc -Json $Box.Results[$Ctx.Url]
            $c1.Failed = ($null -eq $c1.Bars)
            Update-TickerAnalysis
        }
        $ev0 = $script:Events[$c0.Sym]
        if ($null -eq $ev0 -or $null -eq $ev0.Fund -or (Test-EventsStale -Entry $ev0)) {
            $c0.FundTried = $true
            $full = Test-ProfileStale -Entry $script:Profiles[$c0.Sym]
            Start-ProfileJob -Symbols @($c0.Sym) -EventsOnly (-not $full) -OnComplete { if ($null -ne $script:TaCtl) { Update-TickerAnalysis } }
        }
    })
    [void]$dlg.ShowDialog($form)
    $script:TaCtl = $null
    $dlg.Dispose()
}

# ---- DVD <ticker>: dividend history ----
function Show-TickerDividendsDialog {
    param([string]$Ticker)
    $sym = ([string]$Ticker).Trim().ToUpper()
    if (-not $sym) { return }
    $url = "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval=1mo&range=10y&events=div" -f [Uri]::EscapeDataString($sym)
    Show-InfoGrid -Title "Dividenden - $sym (DVD)" -Columns @("Ex-Tag", "Betrag je Aktie", "Summe Jahr") -Weights @(120, 160, 160) -W 560 -H 520 -RightAlign @(1, 2) -Footer "Lade Dividenden ..." -Extra @{ Url = $url; Sym = $sym } -OnShown {
        Start-FetchJob -Urls @($script:InfoCtl.Url) -MaxConcurrency 1 -Context @{ Url = $script:InfoCtl.Url; Sym = $script:InfoCtl.Sym } -OnComplete {
            param($Box, $Ctx)
            $h = ConvertFrom-YahooDailyHistory -Json $Box.Results[$Ctx.Url]
            if ($null -eq $h) { Set-InfoRows -Rows @() -Footer "Keine Daten (offline oder unbekannter Ticker)."; return }
            $divs = @($h.Dividends)
            if ($divs.Count -eq 0) { Set-InfoRows -Rows @() -Footer "$($Ctx.Sym) hat in den letzten 10 Jahren keine Dividende gezahlt."; return }
            $cur = [string]$h.Currency
            $years = @{}
            foreach ($d in $divs) { $y = ([string]$d.Date).Substring(0, 4); $years[$y] = [double]$years[$y] + [double]$d.Amount }
            $rows = @()
            $lastYear = ""
            for ($i = $divs.Count - 1; $i -ge 0; $i--) {
                $d = $divs[$i]
                $y = ([string]$d.Date).Substring(0, 4)
                $ys = if ($y -ne $lastYear) { "{0}: {1:N4} {2}" -f $y, $years[$y], $cur } else { "" }
                $lastYear = $y
                $rows += @{ Cells = @((Format-IsoDateDe $d.Date), ("{0:N4} {1}" -f $d.Amount, $cur), $ys) }
            }
            $st = Get-DividendStats -Dividends $divs
            $foot = ""
            if ($null -ne $st) {
                $foot = "{0}, zuletzt {1:N4} {2}, pro Jahr ~{3:N4} {2}" -f $st.FrequencyLabel, $st.Last, $cur, $st.Annual
                $q = $script:QuoteStore[$Ctx.Sym]
                if ($null -ne $q -and [double]$q.Price -gt 0 -and $st.Annual -gt 0) {
                    $px = Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $cur
                    if ($px -gt 0) { $foot += " = {0:N2}% Rendite" -f ($st.Annual / $px * 100) }
                }
                if ($st.Stopped) { $foot += " - seit {0} keine Zahlung (ausgesetzt?)" -f (Format-IsoDateDe $st.LastDate) }
                elseif ($st.NextEx) { $foot += ", nächster Ex-Tag ~{0}" -f (Format-IsoDateDe $st.NextEx) }
                if ($script:Portfolio.ContainsKey($Ctx.Sym) -and $st.Annual -gt 0) {
                    $foot += "`r`nFür deine {0:N2} Stück: ~{1:N2} {2} im Jahr (brutto)" -f $script:Portfolio[$Ctx.Sym].Shares, ([double]$script:Portfolio[$Ctx.Sym].Shares * $st.Annual), $cur
                }
            }
            Set-InfoRows -Rows $rows -Footer $foot
        }
    }
}

# ---- CAL / EE: event calendar ----
function Get-CalendarRows {
    param([string[]]$Symbols, [int]$Days)
    $amber = $script:Pal.Warn
    $rows = foreach ($c in @(Get-EventCalendar -Events $script:Events -Symbols $Symbols -Days $Days)) {
        $when = if ($c.Days -eq 0) { "heute" } elseif ($c.Days -eq 1) { "morgen" } else { "in {0} T" -f $c.Days }
        $own = if ($script:Portfolio.ContainsKey($c.Ticker)) { "Portfolio" } else { "" }
        @{ Cells = @((Format-IsoDateDe $c.Date), $when, $c.Ticker, $c.Kind, $own); Tag = $c.Ticker; Color = $(if ($c.Days -le 7 -and $c.Kind -eq "Quartalszahlen") { $amber } else { $null }) }
    }
    return @($rows)
}

function Show-CalendarDialog {
    param([string[]]$Symbols = @(), [int]$Days = 60)
    $syms = if (@($Symbols).Count -gt 0) { @($Symbols | ForEach-Object { ([string]$_).ToUpper() }) } else { @(Get-EventSymbols) }
    $title = if (@($Symbols).Count -eq 1) { "Termine - $($syms[0]) (EE)" } else { "Terminkalender - nächste $Days Tage (CAL)" }
    Show-InfoGrid -Title $title -Columns @("Datum", "Wann", "Ticker", "Ereignis", "") -Weights @(100, 80, 90, 130, 80) -W 600 -H 520 -Extra @{ Syms = $syms; Days = $Days } -OnDouble {
        param($Tag)
        $script:InfoCtl.Dlg.Close()
        Switch-ActiveTicker -NewTicker ([string]$Tag) -SkipResolve $true
    } -OnShown {
        $ic = $script:InfoCtl
        $miss = @($ic.Syms | Where-Object { Test-EventsStale -Entry $script:Events[$_] })
        $foot = "Termine von Yahoo Finance, täglich aktualisiert. Doppelklick = Ticker öffnen."
        Set-InfoRows -Rows (Get-CalendarRows -Symbols $ic.Syms -Days $ic.Days) -Footer $(if ($miss.Count -gt 0 -and -not $script:WorkerShared.CrumbFailed) { "Aktualisiere Termine für {0} Ticker ..." -f $miss.Count } else { $foot })
        if ($miss.Count -gt 0 -and -not $script:WorkerShared.CrumbFailed -and -not $script:ProfileJobRunning) {
            Start-ProfileJob -Symbols @($miss | Select-Object -First 25) -EventsOnly $true -OnComplete {
                $ic2 = $script:InfoCtl
                if ($null -ne $ic2 -and $null -ne $ic2.Syms) { Set-InfoRows -Rows (Get-CalendarRows -Symbols $ic2.Syms -Days $ic2.Days) -Footer "Termine von Yahoo Finance, täglich aktualisiert. Doppelklick = Ticker öffnen." }
            }
        } elseif ($script:WorkerShared.CrumbFailed) {
            $ic.Footer.Text = "Yahoo-Anmeldung (Crumb) nicht verfügbar - nur gespeicherte Termine."
        }
        if ($ic.Grid.Rows.Count -eq 0 -and $miss.Count -eq 0) { $ic.Footer.Text = "Keine Termine in den nächsten $($ic.Days) Tagen." }
    }
}

# ---- TOP: movers ----
function Show-MoversDialog {
    $curr = $script:Config.Currency
    $syms = @(Get-KnownTickers | Where-Object { $null -ne $script:QuoteStore[$_] -and [double]$script:QuoteStore[$_].Price -gt 0 })
    $list = @($syms | Sort-Object -Property @{ Expression = { [double]$script:QuoteStore[$_].ChangePct } } -Descending)
    $rows = foreach ($s in $list) {
        $q = $script:QuoteStore[$s]
        $pcS = Get-PriceCurrency $s; $px = Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency (Get-PriceCurrency $s)
        $rv = if ($null -ne $q.RelVol -and -not [double]::IsNaN([double]$q.RelVol)) { "{0:N1}x" -f $q.RelVol } else { "-" }
        $dh = if ([double]$q.High52 -gt 0) { "{0:+0.0;-0.0}%" -f (([double]$q.Price / [double]$q.High52 - 1) * 100) } else { "-" }
        $ms = Get-MarketState -Tp $q.Tp -NowSec ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        $own = if ($script:Portfolio.ContainsKey($s)) { "P" } else { "" }
        @{ Cells = @($s, $own, ("{0:N2} {1}" -f $px, $pcS), ("{0:+0.00;-0.00}%" -f $q.ChangePct), $rv, $dh, $(if ($null -ne $ms) { $ms.Short } else { "" })); Tag = $s; CellColors = @{ 3 = (Get-SignColor ([double]$q.ChangePct)) } }
    }
    Show-InfoGrid -Title "Gewinner / Verlierer heute (TOP)" -Columns @("Ticker", "", "Kurs", "Tag", "Volumen", "zum 52W-Hoch", "Markt") -Weights @(90, 30, 120, 80, 80, 100, 70) -RightAlign @(2, 3, 4, 5) -W 680 -H 520 -Footer "Watchlist + Portfolio, sortiert nach Tagesänderung. P = im Portfolio. Doppelklick = Ticker öffnen." -Extra @{ Rows = @($rows) } -OnShown { Set-InfoRows -Rows $script:InfoCtl.Rows } -OnDouble {
        param($Tag)
        $script:InfoCtl.Dlg.Close()
        Switch-ActiveTicker -NewTicker ([string]$Tag) -SkipResolve $true
    }
}

# ---- FX ----
function Show-FxDialog {
    $rows = foreach ($c in @($script:FxFromEur.Keys | Sort-Object)) {
        $r = [double]$script:FxFromEur[$c]
        if ($c -eq "EUR" -or $r -le 0) { continue }
        $live = if ($script:FxLive.Contains($c)) { "live" } else { "Ersatzwert" }
        @{ Cells = @($c, ("{0:N4}" -f $r), ("{0:N4}" -f (1.0 / $r)), $live); Color = $(if ($live -eq "live") { $null } else { $script:Pal.Muted }) }
    }
    Show-InfoGrid -Title "Wechselkurse (FX)" -Columns @("Währung", "1 EUR =", "1 Einheit = EUR", "Quelle") -Weights @(80, 120, 140, 90) -RightAlign @(1, 2) -W 520 -H 380 -Footer "Kurse von Yahoo Finance (EURxxx=X). Ersatzwert = noch nicht geladen, fester Näherungswert." -Extra @{ Rows = @($rows) } -OnShown { Set-InfoRows -Rows $script:InfoCtl.Rows }
}

# ---- ABOUT ----
function Show-AboutDialog {
    $rows = @(
        @{ Cells = @("Version", $script:AppVersion) }
        @{ Cells = @("PowerShell", $PSVersionTable.PSVersion.ToString()) }
        @{ Cells = @("Datenordner", $script:DataDir); Tag = "dir:" + $script:DataDir }
        @{ Cells = @("Log", $script:LogPath); Tag = "file:" + $script:LogPath }
        @{ Cells = @("Programmordner", $script:ScriptDir); Tag = "dir:" + $script:ScriptDir }
        @{ Cells = @("Projekt", $script:RepoUrl); Tag = "url:" + $script:RepoUrl }
    )
    Show-InfoGrid -Title "Über $($script:AppTitle)" -Columns @("", "") -Weights @(110, 440) -W 620 -H 330 -Footer "Prüfe auf Updates ..." -Extra @{ Rows = $rows } -OnDouble {
        param($Tag)
        $t = [string]$Tag
        if ($t.StartsWith("url:")) { Open-Link $t.Substring(4) }
        elseif ($t.StartsWith("dir:")) { try { Start-Process -FilePath "explorer.exe" -ArgumentList ('"{0}"' -f $t.Substring(4)) } catch { } }
        elseif ($t.StartsWith("file:") -and (Test-Path $t.Substring(5))) { try { Start-Process -FilePath "notepad.exe" -ArgumentList ('"{0}"' -f $t.Substring(5)) } catch { } }
    } -OnShown {
        Set-InfoRows -Rows $script:InfoCtl.Rows
        $u = "https://raw.githubusercontent.com/therealwootwoot/TerminalWidget/main/version.json"
        Start-FetchJob -Urls @($u) -MaxConcurrency 1 -Context @{ Url = $u } -OnComplete {
            param($Box, $Ctx)
            if ($null -eq $script:InfoCtl) { return }
            $latest = Get-LatestVersionFromJson $Box.Results[$Ctx.Url]
            $script:InfoCtl.Footer.Text = if (-not $latest) { "Update-Prüfung nicht möglich (offline oder keine Versionen veröffentlicht). Doppelklick auf eine Zeile öffnet Ordner / Seite." }
                elseif ((Compare-AppVersion $latest $script:AppVersion) -gt 0) { "Neue Version $latest verfügbar - Doppelklick auf 'Projekt' öffnet die Seite." }
                else { "Aktuell (neueste Version: $latest). Doppelklick auf eine Zeile öffnet Ordner / Seite." }
        }
    }
}

# ---- dispatcher ----
function Invoke-TerminalCommand {
    # Runs a command line; returns "" or an error text for the palette
    param([string]$Text)
    $c = ConvertFrom-TerminalCommand $Text
    if ($c.Kind -eq "Empty") { return "" }
    if ($c.Kind -eq "Error") { return $c.Error }
    $tfMap = @{ "1D" = "1d"; "5D" = "5d"; "1M" = "1mo"; "3M" = "3mo"; "6M" = "6mo"; "1Y" = "1y"; "1J" = "1y" }
    $arg0 = if (@($c.Args).Count -gt 0) { ([string]$c.Args[0]).ToUpper() } else { "" }
    if ($c.Kind -eq "Global") {
        switch ($c.Func) {
            "PORT"   { Set-ActiveTab -TabName "Portfolio" }
            "ANA"    { Show-AnalysisDialog }
            "DVD"    { Show-AnalysisDialog -Page "Div" }
            "CAL"    { Show-CalendarDialog }
            "EE"     { Show-CalendarDialog }
            "N"      { Set-ActiveTab -TabName "News" }
            "NEWS"   {
                # NEWS / NEWS DEPOT / NEWS WATCH / NEWS ALL / NEWS <ticker>
                switch ($arg0) {
                    ""      { }
                    "ALL"   { Set-NewsFilter "All" }
                    "ALLE"  { Set-NewsFilter "All" }
                    "DEPOT" { Set-NewsFilter "Holdings" }
                    "PF"    { Set-NewsFilter "Holdings" }
                    "WATCH" { Set-NewsFilter "Watchlist" }
                    "WL"    { Set-NewsFilter "Watchlist" }
                    default {
                        $ns = Resolve-BestSymbol -RawInput $arg0
                        if ([string]::IsNullOrWhiteSpace($ns)) { return "Ticker '$arg0' nicht gefunden." }
                        Set-NewsFilter $ns
                        if (@(Get-NewsSymbols -Holdings @($script:Portfolio.Keys) -Watchlist @($script:Config.Watchlist) -Max 200) -notcontains $ns) {
                            Set-TransientStatus "$ns ist nicht in Depot oder Watchlist - Einzelansicht: $ns N" 6
                        }
                    }
                }
                Set-ActiveTab -TabName "News"
            }
            "ALRT"   {
                if ($arg0) { return (Invoke-TerminalCommand ("{0} ALRT {1}" -f $script:Config.ActiveTicker, (@($c.Args) -join " "))) }
                Set-ActiveTab -TabName "Watchlist"
            }
            "LOG"    { Show-AlertLogDialog }
            "TOP"    { Show-MoversDialog }
            "FX"     { Show-FxDialog }
            "REP"    { Show-YearReport }
            "TX"     { Show-TransactionHistory }
            "CMP"    { Set-CompareTicker -Symbol "" }
            "TF"     {
                if (-not $tfMap.ContainsKey($arg0)) { return "Zeitraum: TF 1D / 5D / 1M / 3M / 6M / 1Y" }
                Set-Timeframe -Tf $tfMap[$arg0]
            }
            "LAYOUT" {
                $rest = (@($c.Args | Select-Object -Skip 1) -join " ").Trim()
                if ($arg0 -eq "SAVE") {
                    if (-not $rest) { return "Name fehlt: LAYOUT SAVE <Name>" }
                    if (@(Get-LayoutNames | Where-Object { $_.ToUpper() -eq $rest.ToUpper() }).Count -gt 0) { return "'$rest' ist ein eingebautes Layout - bitte anderen Namen wählen" }
                    Save-UserLayout -Name $rest
                    return ""
                }
                if ($arg0 -eq "DEL") {
                    $script:Config.UserLayouts = @(@($script:Config.UserLayouts) | Where-Object { $null -ne $_ -and ([string]$_.Name).ToUpper() -ne $rest.ToUpper() })
                    Save-JsonState -Path $script:ConfigPath -Data $script:Config
                    Set-TransientStatus "Layout '$rest' gelöscht" 3
                    return ""
                }
                $full = (@($c.Args) -join " ").Trim()
                $ln = @(Get-LayoutNames | Where-Object { $_.ToUpper() -eq $arg0 })
                if ($ln.Count -gt 0) { Apply-Layout $ln[0]; return "" }
                if (Use-UserLayout -Name $full) { return "" }
                $own = @(@($script:Config.UserLayouts) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.Name })
                return "Layout: " + ((@(Get-LayoutNames) + $own) -join " / ") + " - eigenes speichern: LAYOUT SAVE <Name>"
            }
            "IND"    {
                switch ($arg0) {
                    "MACD" { $script:Config.LowerPanel = "MACD"; $script:Config.ShowRsi = $true }
                    "RSI"  { $script:Config.LowerPanel = "RSI"; $script:Config.ShowRsi = $true }
                    "EMA"  { $script:Config.MaType = "EMA"; $script:Config.ShowSma = $true }
                    "SMA"  { $script:Config.MaType = "SMA"; $script:Config.ShowSma = $true }
                    default { return "IND MACD / RSI / EMA / SMA" }
                }
                Save-JsonState -Path $script:ConfigPath -Data $script:Config
                $btnToggleRsi.Text = if ([string]$script:Config.LowerPanel -eq "MACD") { "MACD" } else { "RSI-$($script:Config.RsiPeriod)" }
                $btnToggleSma.Text = [string]$script:Config.MaType
                Refresh-AllMarketData -Force
                Update-AllUiViews
            }
            "CT"     { Set-ClickThrough (-not $script:ClickThrough) }
            "DRAW"   {
                switch ($arg0) {
                    "H" { Set-DrawMode "H" } "T" { Set-DrawMode "T" } "F" { Set-DrawMode "F" } "FIB" { Set-DrawMode "F" }
                    "CLEAR" { Remove-Drawing -All }
                    default { return "DRAW H (Linie) / T (Trendlinie) / F (Fibonacci) / CLEAR" }
                }
                if ([string]$script:Config.Layout -ne "Terminal") { Set-ActiveTab -TabName "Chart" }
            }
            "CASH"   { Show-CashDialog }
            "SPAR"   { Show-SavingsPlansDialog }
            "REBAL"  { Show-AnalysisDialog -Page "Target" }
            "RISK"   { Show-AnalysisDialog -Page "Risk" }
            "HEAT"   { Show-AnalysisDialog -Page "Heat" }
            "FULL"   {
                $fp = switch ($arg0) { "PORT" { "Portfolio" } "PORTFOLIO" { "Portfolio" } "WATCH" { "Watchlist" } "WL" { "Watchlist" } "NEWS" { "News" } default { "" } }
                if ($arg0 -and -not $fp) { return "FULL PORT / FULL WATCH / FULL NEWS, FULL = zurück" }
                if ([string]$script:Config.Layout -ne "Terminal" -and $fp) { Set-ActiveTab -TabName $fp; return "" }
                Set-TerminalFull $fp
            }
            "PRIV"   { if ($arg0 -eq "ON") { Set-PrivacyMode $true } elseif ($arg0 -eq "OFF") { Set-PrivacyMode $false } else { Set-PrivacyMode (-not [bool]$script:Config.PrivacyMode) } }
            "SCALE"  {
                if ($arg0 -eq "LOG") { Set-LogScale $true } elseif ($arg0 -eq "LIN") { Set-LogScale $false } else { Set-LogScale (-not [bool]$script:Config.LogScale) }
            }
            "BAR"    { Show-CompactOptions }
            "TOUR"   { Show-WelcomeTour }
            "THEME"  {
                if (-not $arg0) { $btnThemeCycle.PerformClick(); return "" }
                $tn = @(Get-ThemeNames | Where-Object { $_.ToUpper() -eq $arg0 })
                if ($tn.Count -eq 0) { return "Theme: " + ((Get-ThemeNames) -join " / ") }
                $script:Config.Theme = $tn[0]
                Save-JsonState -Path $script:ConfigPath -Data $script:Config
                Apply-ThemeToAllControls
            }
            "STYLE"  {
                # v5.2: STYLE / STYLE FRESH / STYLE REFINED (+ ROWS COMPACT|NORMAL|COMFORTABLE)
                if ($arg0 -in @("FRESH", "REFINED")) { $script:Config.UiStyle = $(if ($arg0 -eq "FRESH") { "Fresh" } else { "Refined" }) }
                elseif (-not $arg0) { $script:Config.UiStyle = $(if ([string]$script:Config.UiStyle -eq "Fresh") { "Refined" } else { "Fresh" }) }
                else { return "STYLE / STYLE FRESH / STYLE REFINED" }
                Save-JsonState -Path $script:ConfigPath -Data $script:Config
                Apply-ThemeToAllControls
                Set-TransientStatus ("Design: {0}" -f $script:Config.UiStyle) 3
            }
            "SET"    { Show-SettingsDialog }
            "PUSH"   { [void](Show-PushDialog) }
            "GLOS"   { Show-GlossaryDialog }
            "HELP"   { Show-ShortcutHelp }
            "ABOUT"  { Show-AboutDialog }
            "IMP"    { Show-CsvImportDialog }
            "BAK"    { Show-RestoreDialog }
            "PF"     {
                $want = (@($c.Args) -join " ").Trim()
                if (-not $want) { New-Depot; return "" }
                $hit = @(Get-DepotList | Where-Object { $_.Name.ToUpper() -eq $want.ToUpper() -or $_.Id.ToUpper() -eq $want.ToUpper() })
                if ($hit.Count -eq 0) { return "Depot '$want' gibt es nicht. Vorhanden: " + ((Get-DepotList | ForEach-Object { $_.Name }) -join ", ") }
                Switch-Depot $hit[0].Id
                Set-ActiveTab -TabName "Portfolio"
            }
        }
        return ""
    }
    $sym = $c.Ticker
    if ($c.Func -in @("", "GP", "DES", "N", "DVD", "EE", "TX", "TA", "FA")) {
        $res = Resolve-BestSymbol -RawInput $sym
        if ([string]::IsNullOrWhiteSpace($res)) { return "Ticker '$sym' nicht gefunden." }
        $sym = $res
    }
    switch ($c.Func) {
        ""     { Switch-ActiveTicker -NewTicker $sym -SkipResolve $true }
        "GP"   {
            Switch-ActiveTicker -NewTicker $sym -SkipResolve $true
            if ([string]$script:Config.Layout -ne "Terminal") { Set-ActiveTab -TabName "Chart" }
            if ($arg0) {
                if (-not $tfMap.ContainsKey($arg0)) { return "Zeitraum nach GP: 1D / 5D / 1M / 3M / 6M / 1Y" }
                Set-Timeframe -Tf $tfMap[$arg0]
            }
        }
        "DES"  { Show-DescriptionDialog $sym }
        "TA"   { Show-TickerAnalysis $sym }
        "FA"   { Show-TickerAnalysis $sym }
        "N"    { Show-NewsDialog $sym }
        "DVD"  { Show-TickerDividendsDialog $sym }
        "EE"   {
            if (Test-EventsStale -Entry $script:Events[$sym]) {
                if (-not $script:ProfileJobRunning) { Start-ProfileJob -Symbols @($sym) -EventsOnly $true -OnComplete { if ($null -ne $script:InfoCtl -and $null -ne $script:InfoCtl.Syms) { Set-InfoRows -Rows (Get-CalendarRows -Symbols $script:InfoCtl.Syms -Days $script:InfoCtl.Days) } } }
            }
            Show-CalendarDialog -Symbols @($sym) -Days 400
        }
        "ALRT" {
            if (@($c.Args).Count -eq 0) {
                $txtAlertTicker.Text = $sym
                Set-ActiveTab -TabName "Watchlist"
                return ""
            }
            $al = ConvertFrom-AlertShorthand -ArgList @($c.Args)
            if ($null -eq $al) { return "Alarm z. B.: $sym ALRT >= 150 | TRAIL 8 | TAG- 3 | EK+ 20 | 52H | VOL 2 | RSI+ 70 | SMA+" }
            $err = New-AlertChecked -RawTicker $sym -Cond $al.Condition -Value ([double]$al.Value)
            if ($err -eq "CANCEL") { return "" }
            if ($err) { return $err }
            Set-TransientStatus ("Alarm angelegt: {0}" -f (Format-AlertLine -Alert $script:Alerts[$script:Alerts.Count - 1])) 5
        }
        "WL"   { [void](Add-SymbolToWatchlist -RawSymbol $sym) }
        "CMP"  { Switch-CompareTicker -Symbol $sym; if ([string]$script:Config.Layout -ne "Terminal") { Set-ActiveTab -TabName "Chart" } }
        "TX"   { Show-TransactionDialog -Ticker $sym }
    }
    return ""
}

# ---- Ctrl+K: command palette ----
function Update-PaletteSuggestions {
    $pc = $script:PalCtl
    if ($null -eq $pc) { return }
    $pc.Items = @(Get-CommandSuggestions -Text $pc.Text.Text -Tickers (Get-KnownTickers) -Recent @($script:Config.CommandHistory) -Max 12 -Depots @(Get-DepotList | ForEach-Object { $_.Name }) -Layouts @(@($script:Config.UserLayouts) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.Name }))
    $pc.List.BeginUpdate()
    $pc.List.Items.Clear()
    foreach ($it in $pc.Items) { $it.Desc = Tr ([string]$it.Desc); [void]$pc.List.Items.Add($it.Text) }
    $pc.List.EndUpdate()
    $pc.List.SelectedIndex = -1
    $pc.Err.Text = ""
}

function Show-CommandPalette {
    param([string]$Initial = "")
    if ($null -ne $script:PalCtl) { return }
    $p = $script:Pal
    $W = S 640
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $f.ShowInTaskbar = $false
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $f.TopMost = $true
    $f.KeyPreview = $true
    $f.BackColor = $p.Accent
    $f.Padding = New-Object System.Windows.Forms.Padding(1)
    $f.Add_HandleCreated({ param($sender, $e) Set-WindowChrome -Win $sender -Kind "Strip" })
    $f.ClientSize = New-Object System.Drawing.Size($W, (S 352))
    $inner = New-Object System.Windows.Forms.Panel
    $inner.Dock = [System.Windows.Forms.DockStyle]::Fill
    $inner.BackColor = $p.Card
    $f.Controls.Add($inner)
    $lp = New-Object System.Windows.Forms.Label
    $lp.SetBounds((S 10), (S 10), (S 22), (S 28)); $lp.Text = ">"; $lp.ForeColor = $p.Accent
    $lp.Font = New-Object System.Drawing.Font($script:MonoFamily, 14, [System.Drawing.FontStyle]::Bold)
    $inner.Controls.Add($lp)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.SetBounds((S 34), (S 10), ($W - (S 46)), (S 28))
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $tb.BackColor = $p.Card; $tb.ForeColor = $p.Text
    $tb.Font = New-Object System.Drawing.Font($script:MonoFamily, 14)
    $tb.CharacterCasing = [System.Windows.Forms.CharacterCasing]::Upper
    $inner.Controls.Add($tb)
    $sep = New-Object System.Windows.Forms.Label
    $sep.SetBounds((S 10), (S 42), ($W - (S 22)), 1); $sep.BackColor = $p.Border
    $inner.Controls.Add($sep)
    $lb = New-Object System.Windows.Forms.ListBox
    $lb.SetBounds((S 6), (S 48), ($W - (S 14)), (S 268))
    $lb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $lb.BackColor = $p.Card; $lb.ForeColor = $p.Text
    $lb.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $lb.ItemHeight = S 22
    $lb.Font = $fontMono
    $lb.IntegralHeight = $false
    $inner.Controls.Add($lb)
    $err = New-Object System.Windows.Forms.Label
    $err.SetBounds((S 10), (S 322), ($W - (S 22)), (S 22))
    $err.ForeColor = $colRed
    $err.AutoEllipsis = $true
    $inner.Controls.Add($err)
    $hint = "Enter = ausführen  Tab = übernehmen  Pfeile = Auswahl  Esc = schließen"
    $script:PalCtl = @{ Form = $f; Text = $tb; List = $lb; Err = $err; Items = @(); Run = ""; Hint = $hint }
    $lb.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0) { return }
        $pc = $script:PalCtl
        $it = $pc.Items[$e.Index]
        $sel = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
        $bg = if ($sel) { $script:Pal.Accent } else { $script:Pal.Card }
        $fg = if ($sel) { $script:Pal.HeaderBg } else { $script:Pal.Text }
        $mu = if ($sel) { $script:Pal.HeaderBg } else { $script:Pal.Muted }
        $b = New-Object System.Drawing.SolidBrush($bg)
        $e.Graphics.FillRectangle($b, $e.Bounds)
        $b.Dispose()
        $half = [int]($e.Bounds.Width * 0.36)
        $r1 = New-Object System.Drawing.Rectangle(($e.Bounds.X + (S 6)), $e.Bounds.Y, $half, $e.Bounds.Height)
        $r2 = New-Object System.Drawing.Rectangle(($e.Bounds.X + $half + (S 10)), $e.Bounds.Y, ($e.Bounds.Width - $half - (S 16)), $e.Bounds.Height)
        $fl = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$it.Text, $fontMono, $r1, $fg, $fl)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$it.Desc, $fontUi, $r2, $mu, $fl)
    })
    $tb.Add_TextChanged({ Update-PaletteSuggestions })
    $runSel = {
        $pc = $script:PalCtl
        $cmd = if ($pc.List.SelectedIndex -ge 0) { [string]$pc.Items[$pc.List.SelectedIndex].Text } else { $pc.Text.Text }
        $cmd = $cmd.Trim()
        if (-not $cmd) { return }
        $chk = ConvertFrom-TerminalCommand $cmd
        if ($chk.Kind -eq "Error") { $pc.Err.Text = $chk.Error; return }
        $pc.Run = $cmd
        $pc.Form.Close()
    }
    $script:PalCtl.RunSel = $runSel
    $f.Add_KeyDown({
        param($sender, $e)
        $pc = $script:PalCtl
        $n = $pc.List.Items.Count
        switch ($e.KeyCode) {
            ([System.Windows.Forms.Keys]::Escape) { $e.SuppressKeyPress = $true; $sender.Close() }
            ([System.Windows.Forms.Keys]::Down) { $e.SuppressKeyPress = $true; if ($n -gt 0) { $pc.List.SelectedIndex = [math]::Min($n - 1, $pc.List.SelectedIndex + 1) } }
            ([System.Windows.Forms.Keys]::Up) { $e.SuppressKeyPress = $true; if ($n -gt 0) { $pc.List.SelectedIndex = [math]::Max(-1, $pc.List.SelectedIndex - 1) } }
            ([System.Windows.Forms.Keys]::Tab) {
                $e.SuppressKeyPress = $true
                if ($n -gt 0) {
                    $ix = [math]::Max(0, $pc.List.SelectedIndex)
                    $pc.Text.Text = [string]$pc.Items[$ix].Text + " "
                    $pc.Text.SelectionStart = $pc.Text.Text.Length
                }
            }
            ([System.Windows.Forms.Keys]::Enter) { $e.SuppressKeyPress = $true; & $script:PalCtl.RunSel }
        }
    })
    # Tab must reach KeyDown instead of moving the focus
    $tb.Add_PreviewKeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Tab) { $e.IsInputKey = $true } })
    $lb.Add_DoubleClick({ & $script:PalCtl.RunSel })
    $lb.Add_Click({ $script:PalCtl.Text.Focus() | Out-Null })
    $f.Add_Deactivate({ param($sender, $e) if ($null -ne $script:PalCtl -and -not $script:PalCtl.Run) { $sender.Close() } })
    $f.Add_Shown({
        $pc = $script:PalCtl
        $pc.Text.Focus() | Out-Null
        $pc.Text.SelectionStart = $pc.Text.Text.Length
        $pc.Err.ForeColor = $script:Pal.Muted
        Update-PaletteSuggestions
        $pc.Err.Text = $pc.Hint
    })
    $tb.Text = $Initial
    # position: top centre of the visible main window, else of the screen
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    if ($form.Visible -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
        $x = $form.Left + [int](($form.Width - $f.Width) / 2)
        $y = $form.Top + (S 70)
    } else {
        $x = $wa.Left + [int](($wa.Width - $f.Width) / 2)
        $y = $wa.Top + [int]($wa.Height * 0.2)
    }
    $x = [math]::Max($wa.Left, [math]::Min($x, $wa.Right - $f.Width))
    $y = [math]::Max($wa.Top, [math]::Min($y, $wa.Bottom - $f.Height))
    $f.Location = New-Object System.Drawing.Point($x, $y)
    $tb.Add_TextChanged({ $script:PalCtl.Err.ForeColor = $colRed })
    [void]$f.ShowDialog()
    $run = [string]$script:PalCtl.Run
    $script:PalCtl = $null
    $f.Dispose()
    if ($run) {
        Write-WidgetLog "Command: $run"
        $script:Config.CommandHistory = @(Add-RecentCommand -Recent @($script:Config.CommandHistory) -Command $run)
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        $msg = ""
        try { $msg = Invoke-TerminalCommand $run } catch { $msg = "Fehler: $($_.Exception.Message)"; Write-WidgetLog "Command '$run' failed: $($_.Exception.Message)" "ERROR" }
        if ($msg) {
            # show the problem and let the user fix the line
            Set-TransientStatus $msg 6
            Show-CommandPalette -Initial $run
        }
    }
}

# ---- tray tooltip with today's portfolio result, polling while markets are closed ----
function Get-TrayDepotLine {
    param([string]$Currency)
    if ($script:Portfolio.Count -eq 0) { return "" }
    $pt = Get-PortfolioDayTotals -Currency $Currency
    if (-not $pt.Ok) { return "" }
    $d = $pt.Value - $pt.Prev
    if ([bool]$script:Config.PrivacyMode) { return ("Depot {0:+0.00;-0.00}%" -f $pt.DayPct) }
    return ("Depot {0:+#,##0;-#,##0} {1} ({2:+0.00;-0.00}%)" -f $d, $Currency, $pt.DayPct)
}

function Get-PrioMarketStates {
    # Market states of everything polled every time; empty = unknown (do not skip)
    $tiers = Get-QuoteTiers
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $out = @()
    foreach ($s in @($tiers.Prio)) {
        $q = $script:QuoteStore[$s]
        if ($null -eq $q -or $null -eq $q.Tp -or [bool]$q.FromCache) { return @() }
        $ms = Get-MarketState -Tp $q.Tp -NowSec $now
        if ($null -eq $ms) { return @() }
        $out += [string]$ms.State
    }
    return $out
}

function Show-InfoBox {
    param([string]$Text, [string]$Title = "Hinweis")
    if ($env:TW_SMOKE_TEST) { Write-WidgetLog "InfoBox: $Text"; return }
    $owner = if ($null -ne $form -and -not $form.IsDisposed) { $form } else { $null }
    [void][System.Windows.Forms.MessageBox]::Show($owner, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# ==============================================================================
# v4.5: depots, CSV import, backups / restore, export / import, portable mode
# ==============================================================================
function Switch-Depot {
    param([string]$Id)
    if ($Id -eq [string]$script:Config.ActiveDepot) { return }
    Set-DepotPaths $Id
    Read-PortfolioData
    Read-TransactionsData
    Read-CashData
    Read-SavingsPlans
    $script:Config.ActiveDepot = $Id
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Write-WidgetLog ("Depot switched to '{0}'" -f (Get-DepotName $Id))
    Update-DepotCombo
    Set-TransientStatus ("Depot: {0}" -f (Get-DepotName $Id)) 3
    Refresh-AllMarketData
    Update-AllUiViews
}

function Read-TextInput {
    # Small input box; returns the text or $null when cancelled
    param([string]$Title, [string]$Prompt, [string]$Value = "")
    $p = $script:Pal
    $dlg = New-DialogForm -Title $Title -W (S 380) -H (S 130)
    $l = New-Object System.Windows.Forms.Label
    $l.SetBounds((S 14), (S 12), (S 352), (S 20)); $l.Text = $Prompt
    $dlg.Controls.Add($l)
    $t = New-Object System.Windows.Forms.TextBox
    $t.SetBounds((S 14), (S 38), (S 352), (S 24)); $t.Text = $Value
    $t.BackColor = $p.Input; $t.ForeColor = $p.Text; $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($t)
    $ok = New-Object System.Windows.Forms.Button
    $ok.SetBounds((S 172), (S 86), (S 94), (S 28)); $ok.Text = "OK"
    Style-FlatButton -Btn $ok -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($ok)
    $ca = New-Object System.Windows.Forms.Button
    $ca.SetBounds((S 272), (S 86), (S 94), (S 28)); $ca.Text = "Abbrechen"
    Style-FlatButton -Btn $ca -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $ca.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($ca)
    $dlg.AcceptButton = $ok; $dlg.CancelButton = $ca
    $res = $dlg.ShowDialog($form)
    $v = $t.Text.Trim()
    $dlg.Dispose()
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $v
}

function New-Depot {
    $name = Read-TextInput -Title "Neues Depot" -Prompt "Name des Depots (z. B. Zweitbroker, Übungsdepot):"
    if (-not $name) { return }
    $base = ConvertTo-DepotId $name
    $id = $base; $n = 2
    while (@(Get-DepotList | Where-Object { $_.Id -eq $id }).Count -gt 0) { $id = "{0}-{1}" -f $base, $n; $n++ }
    $script:Config.Depots = @(@($script:Config.Depots) | Where-Object { $null -ne $_ }) + @([PSCustomObject]@{ Id = $id; Name = $name })
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Write-WidgetLog "Depot created: $name ($id)"
    Switch-Depot $id
}

function Rename-ActiveDepot {
    $id = [string]$script:Config.ActiveDepot
    $name = Read-TextInput -Title "Depot umbenennen" -Prompt "Neuer Name:" -Value (Get-DepotName $id)
    if (-not $name) { return }
    if (-not $id) { $script:Config.MainDepotName = $name }
    else { foreach ($d in @($script:Config.Depots)) { if ([string]$d.Id -eq $id) { $d.Name = $name } } }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-DepotCombo
}

function Remove-ActiveDepot {
    $id = [string]$script:Config.ActiveDepot
    if (-not $id) { Show-InfoBox -Text "Das Hauptdepot kann nicht gelöscht werden." -Title "Depot"; return }
    $name = Get-DepotName $id
    if (-not (Confirm-Action -Text ("Depot '{0}' mit allen Positionen und Buchungen löschen?`r`n`r`nDie Dateien werden vorher ins Backup kopiert." -f $name) -Title "Depot löschen")) { return }
    [void](Backup-DataFiles -Reason ("vor_loeschen_" + $id))
    Switch-Depot ""
    try { Remove-Item -Path (Join-Path $script:DepotDir $id) -Recurse -Force -ErrorAction Stop } catch { Write-WidgetLog "Depot folder not removed: $($_.Exception.Message)" "WARN" }
    $script:Config.Depots = @(@($script:Config.Depots) | Where-Object { $null -ne $_ -and [string]$_.Id -ne $id })
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-DepotCombo
    Set-TransientStatus "Depot '$name' gelöscht" 4
}

$script:DepotComboBusy = $false
function Update-DepotCombo {
    $script:DepotComboBusy = $true
    try {
        $cmbDepot.Items.Clear()
        $sel = 0; $i = 0
        foreach ($d in Get-DepotList) {
            [void]$cmbDepot.Items.Add($d.Name)
            if ($d.Id -eq [string]$script:Config.ActiveDepot) { $sel = $i }
            $i++
        }
        foreach ($x in @("+ Neues Depot ...", "  Umbenennen ...", "  Löschen ...")) { [void]$cmbDepot.Items.Add($x) }
        $cmbDepot.SelectedIndex = $sel
    } finally { $script:DepotComboBusy = $false }
}

# ---- backups ----
function Invoke-DailyBackup {
    $today = (Get-Date).ToString("yyyy-MM-dd")
    if ([string]$script:Config.LastAutoBackup -eq $today) { return }
    if (Backup-DataFiles -Reason "taeglich") {
        $script:Config.LastAutoBackup = $today
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
    }
}

function Restart-Widget {
    # Restored / imported data must not be overwritten by this instance on exit
    $script:FreezeData = $true
    $bat = Join-Path $script:ScriptDir "TerminalWidget_Start.bat"
    try {
        if (Test-Path $bat) {
            Start-Process -FilePath "cmd.exe" -ArgumentList ('/c timeout /t 3 /nobreak >nul & start "" "{0}"' -f $bat) -WindowStyle Hidden
        } else {
            $exe = (Get-Process -Id $PID).Path
            $self = Join-Path $script:ScriptDir "TerminalWidget.ps1"
            Start-Process -FilePath "cmd.exe" -ArgumentList ('/c timeout /t 3 /nobreak >nul & start "" "{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $exe, $self) -WindowStyle Hidden
        }
    } catch { Write-WidgetLog "Restart failed: $($_.Exception.Message)" "ERROR" }
    Write-WidgetLog "Restarting the widget"
    $trayIcon.Visible = $false
    $form.Close()
}

function Copy-DataSet {
    # Copies the data files (+ depots folder) from $From to $To
    param([string]$From, [string]$To)
    foreach ($f in @(Get-DataFileNames)) {
        $src = Join-Path $From $f
        if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $To $f) -Force }
    }
    $dSrc = Join-Path $From "depots"
    if (Test-Path $dSrc) {
        $dDst = Join-Path $To "depots"
        if (Test-Path $dDst) { Remove-Item -Path $dDst -Recurse -Force }
        Copy-Item -Path $dSrc -Destination $dDst -Recurse -Force
    }
}

function Show-RestoreDialog {
    $rows = @()
    if (Test-Path $script:BackupDir) {
        foreach ($d in @(Get-ChildItem -Path $script:BackupDir -Directory | Sort-Object Name -Descending)) {
            $bi = Get-BackupInfo $d.Name
            $n = @(Get-ChildItem -Path $d.FullName -File).Count
            $dep = if (Test-Path (Join-Path $d.FullName "depots")) { "+ Depots" } else { "" }
            $rows += @{ Cells = @($(if ($bi.When -gt [DateTime]::MinValue) { $bi.When.ToString("dd.MM.yyyy HH:mm") } else { $d.Name }), $bi.Reason, ("{0} Dateien {1}" -f $n, $dep).Trim()); Tag = $d.FullName }
        }
    }
    Show-InfoGrid -Title "Backup wiederherstellen (BAK)" -Columns @("Zeitpunkt", "Anlass", "Inhalt") -Weights @(140, 200, 140) -W 560 -H 460 -Footer "Doppelklick = dieses Backup wiederherstellen (der aktuelle Stand wird vorher gesichert, danach startet das Widget neu). Täglich wird automatisch gesichert, die letzten 20 bleiben." -Extra @{ Rows = $rows } -OnShown { Set-InfoRows -Rows $script:InfoCtl.Rows } -OnDouble {
        param($Tag)
        $src = [string]$Tag
        $bi = Get-BackupInfo (Split-Path -Leaf $src)
        if (-not (Confirm-Action -Text ("Stand vom {0} wiederherstellen?`r`n`r`nEinstellungen, Portfolio, Depots, Alarme und Buchungen werden ersetzt. Der aktuelle Stand wird vorher gesichert. Danach startet das Widget neu." -f $bi.When.ToString("dd.MM.yyyy HH:mm")) -Title "Wiederherstellen")) { return }
        [void](Backup-DataFiles -Reason "vor_wiederherstellung")
        try {
            Copy-DataSet -From $src -To $script:DataDir
            Write-WidgetLog "Backup restored: $src"
        } catch {
            Write-WidgetLog "Restore failed: $($_.Exception.Message)" "ERROR"
            Show-InfoBox -Text "Wiederherstellen fehlgeschlagen: $($_.Exception.Message)" -Title "Wiederherstellen"
            return
        }
        $script:InfoCtl.Dlg.Close()
        Restart-Widget
    }
}

function Export-DataZip {
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "ZIP-Archiv (*.zip)|*.zip"
    $sfd.FileName = "TerminalWidget_Daten_{0}.zip" -f (Get-Date -Format "yyyyMMdd")
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("tw_export_" + [Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        Copy-DataSet -From $script:DataDir -To $tmp
        Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $sfd.FileName -Force
        Write-WidgetLog "Data exported: $($sfd.FileName)"
        Show-InfoBox -Text ("Exportiert nach:`r`n{0}`r`n`r`nHinweis: ein Telegram-Token ist an dein Windows-Konto gebunden und muss auf einem anderen PC neu eingetragen werden." -f $sfd.FileName) -Title "Export"
    } catch {
        Write-WidgetLog "Export failed: $($_.Exception.Message)" "ERROR"
        Show-InfoBox -Text "Export fehlgeschlagen: $($_.Exception.Message)" -Title "Export"
    } finally { Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Import-DataZip {
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "ZIP-Archiv (*.zip)|*.zip"
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("tw_import_" + [Guid]::NewGuid().ToString("N"))
    try {
        Expand-Archive -Path $ofd.FileName -DestinationPath $tmp -Force
        if (-not (Test-Path (Join-Path $tmp "config.json"))) { Show-InfoBox -Text "Das Archiv enthält keine config.json - kein TerminalWidget-Export." -Title "Import"; return }
        if (-not (Confirm-Action -Text "Alle Daten durch den Inhalt des Archivs ersetzen?`r`nDer aktuelle Stand wird vorher gesichert. Danach startet das Widget neu." -Title "Import")) { return }
        [void](Backup-DataFiles -Reason "vor_import")
        Copy-DataSet -From $tmp -To $script:DataDir
        Write-WidgetLog "Data imported: $($ofd.FileName)"
        Restart-Widget
    } catch {
        Write-WidgetLog "Import failed: $($_.Exception.Message)" "ERROR"
        Show-InfoBox -Text "Import fehlgeschlagen: $($_.Exception.Message)" -Title "Import"
    } finally { Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Switch-PortableMode {
    # portable.txt next to the script = data in <program folder>\data
    $flag = Join-Path $script:ScriptDir "portable.txt"
    $portDir = Join-Path $script:ScriptDir "data"
    $localDir = Join-Path $env:LOCALAPPDATA "TerminalWidget"
    if ($script:IsPortable) {
        if (-not (Confirm-Action -Text ("Portabel-Modus beenden?`r`nDie Daten werden nach {0} kopiert, danach startet das Widget neu." -f $localDir) -Title "Portabel")) { return }
        try {
            if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Path $localDir -Force | Out-Null }
            [void](Backup-DataFiles -Reason "vor_portabel_aus")
            Copy-DataSet -From $script:DataDir -To $localDir
            Remove-Item -Path $flag -Force
        } catch { Show-InfoBox -Text "Fehlgeschlagen: $($_.Exception.Message)" -Title "Portabel"; return }
    } else {
        if (-not (Confirm-Action -Text ("Portabel-Modus einschalten?`r`nDie Daten werden nach {0} kopiert (z. B. für einen USB-Stick), danach startet das Widget neu. Autostart zeigt weiter auf diesen Ordner." -f $portDir) -Title "Portabel")) { return }
        try {
            if (-not (Test-Path $portDir)) { New-Item -ItemType Directory -Path $portDir -Force | Out-Null }
            Copy-DataSet -From $script:DataDir -To $portDir
            Set-Content -Path $flag -Value "Daten liegen im Unterordner data (TerminalWidget portabel). Datei löschen = wieder %LOCALAPPDATA%." -Encoding UTF8
        } catch { Show-InfoBox -Text "Fehlgeschlagen (Ordner schreibgeschützt?): $($_.Exception.Message)" -Title "Portabel"; return }
    }
    Restart-Widget
}

# ---- CSV import ----
function Read-TextFileGuess {
    # UTF-8 (with or without BOM), else Windows-1252 (German broker exports)
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { return $utf8.GetString($bytes).TrimStart([char]0xFEFF) } catch { return [System.Text.Encoding]::GetEncoding(1252).GetString($bytes) }
}

function Show-CsvImportDialog {
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "CSV / Text (*.csv;*.txt)|*.csv;*.txt|Alle Dateien (*.*)|*.*"
    $ofd.Title = "Broker-Export (CSV) wählen"
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $csv = $null
    try { $csv = ConvertFrom-CsvText (Read-TextFileGuess $ofd.FileName) } catch { Write-WidgetLog "CSV read failed: $($_.Exception.Message)" "ERROR" }
    if ($null -eq $csv -or @($csv.Headers).Count -lt 2 -or @($csv.Rows).Count -eq 0) {
        Show-InfoBox -Text "In der Datei wurde keine Tabelle gefunden (Kopfzeile + Zeilen, getrennt mit ; , oder Tab)." -Title "CSV-Import"
        return
    }
    $p = $script:Pal
    $dlg = New-DialogForm -Title ("CSV-Import - {0} -> Depot '{1}'" -f (Split-Path -Leaf $ofd.FileName), (Get-DepotName ([string]$script:Config.ActiveDepot))) -W (S 1000) -H (S 640)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 860), (S 480))
    $aTLR = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $aAll = $aTLR -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $aBL = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $aBR = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $info = New-Object System.Windows.Forms.Label
    $info.SetBounds((S 12), (S 8), (S 976), (S 20)); $info.Anchor = $aTLR; $info.ForeColor = $p.Muted
    $info.Text = "Spalten zuordnen (automatisch erkannt). Häkchen = wird importiert. Symbol-Spalte ist änderbar. Schon vorhandene Buchungen werden nicht doppelt importiert."
    $dlg.Controls.Add($info)
    $guess = Get-CsvColumnGuess -Headers $csv.Headers
    $fields = Get-CsvFieldNames
    $combos = @{}
    $i = 0
    foreach ($f in $fields.Keys) {
        $x = (S 12) + ($i % 5) * (S 196)
        $y = (S 34) + [math]::Floor($i / 5) * (S 30)
        $l = New-Object System.Windows.Forms.Label
        $l.SetBounds($x, ($y + (S 3)), (S 74), (S 18)); $l.Text = $fields[$f]
        $dlg.Controls.Add($l)
        $cb = New-Object System.Windows.Forms.ComboBox
        $cb.SetBounds(($x + (S 76)), $y, (S 112), (S 24))
        $cb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cb.BackColor = $p.Input; $cb.ForeColor = $p.Text
        [void]$cb.Items.Add("(keine)")
        foreach ($h in $csv.Headers) { [void]$cb.Items.Add($(if ($h) { $h } else { "(leer)" })) }
        $cb.SelectedIndex = [int]$guess[$f] + 1
        $cb.DropDownWidth = S 200
        $dlg.Controls.Add($cb)
        $combos[$f] = $cb
        $i++
    }
    $y2 = S 98
    $lCur = New-Object System.Windows.Forms.Label
    $lCur.SetBounds((S 12), ($y2 + (S 3)), (S 150), (S 18)); $lCur.Text = "Währung, wenn leer:"
    $dlg.Controls.Add($lCur)
    $cbCur = New-Object System.Windows.Forms.ComboBox
    $cbCur.SetBounds((S 164), $y2, (S 70), (S 24))
    $cbCur.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbCur.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cbCur.BackColor = $p.Input; $cbCur.ForeColor = $p.Text
    foreach ($c in @("EUR", "USD", "CHF", "GBP")) { [void]$cbCur.Items.Add($c) }
    $cbCur.SelectedIndex = 0
    $dlg.Controls.Add($cbCur)
    $lSuf = New-Object System.Windows.Forms.Label
    $lSuf.SetBounds((S 250), ($y2 + (S 3)), (S 150), (S 18)); $lSuf.Text = "ISIN bevorzugt an Börse:"
    $dlg.Controls.Add($lSuf)
    $cbSuf = New-Object System.Windows.Forms.ComboBox
    $cbSuf.SetBounds((S 402), $y2, (S 120), (S 24))
    $cbSuf.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbSuf.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cbSuf.BackColor = $p.Input; $cbSuf.ForeColor = $p.Text
    foreach ($c in @("Heimatbörse", ".DE Xetra", ".F Frankfurt", ".VI Wien", ".SW Zürich", ".L London", ".AS Amsterdam", ".PA Paris")) { [void]$cbSuf.Items.Add($c) }
    $cbSuf.SelectedIndex = 0
    $dlg.Controls.Add($cbSuf)
    Set-DynTip $cbSuf "Bei ISINs: welches Yahoo-Symbol genommen wird. Heimatbörse = erster Treffer (meist US/Heimatmarkt); .DE = Xetra-Kurse in EUR."
    $btnRes = New-Object System.Windows.Forms.Button
    $btnRes.SetBounds((S 534), ($y2 - (S 1)), (S 150), (S 26))
    Style-FlatButton -Btn $btnRes -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnRes.Text = "ISINs auflösen"
    $dlg.Controls.Add($btnRes)
    $chkReb = New-Object System.Windows.Forms.CheckBox
    $chkReb.SetBounds((S 700), $y2, (S 290), (S 24)); $chkReb.Anchor = $aTLR
    $chkReb.Text = "Positionen danach aus Buchungen berechnen"; $chkReb.Checked = $true
    $chkReb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dlg.Controls.Add($chkReb)
    Set-DynTip $chkReb "Stück und EK der betroffenen Positionen werden aus allen Buchungen neu berechnet (Durchschnittskosten, Splits berücksichtigt)" "REBUILD"
    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds((S 12), (S 132), (S 976), (S 450)); $g.Anchor = $aAll
    Style-DataGrid -Grid $g
    $g.ReadOnly = $false
    $g.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::CellSelect
    $chkCol = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $chkCol.Name = "Use"; $chkCol.HeaderText = ""; $chkCol.FillWeight = [float](S 30)
    [void]$g.Columns.Add($chkCol)
    foreach ($cd in @(@("Date", "Datum", 90), @("Type", "Art", 80), @("Ident", "Ticker / ISIN", 130), @("Sym", "Symbol", 90), @("Shares", "Stück", 80), @("Price", "Kurs / Betrag", 100), @("Fee", "Gebühr", 70), @("Cur", "Whg", 50), @("Note", "Hinweis", 220))) {
        $ci = $g.Columns.Add($cd[0], $cd[1])
        $g.Columns[$ci].FillWeight = [float](S $cd[2])
        $g.Columns[$ci].ReadOnly = ($cd[0] -ne "Sym")
    }
    $g.Columns["Sym"].DefaultCellStyle.ForeColor = $p.Accent
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dlg.Controls.Add($g)
    $lSum = New-Object System.Windows.Forms.Label
    $lSum.SetBounds((S 12), (S 594), (S 700), (S 34)); $lSum.Anchor = $aBL -bor [System.Windows.Forms.AnchorStyles]::Right; $lSum.ForeColor = $p.Muted
    $dlg.Controls.Add($lSum)
    $btnImp = New-Object System.Windows.Forms.Button
    $btnImp.SetBounds((S 794), (S 598), (S 94), (S 28)); $btnImp.Anchor = $aBR
    Style-FlatButton -Btn $btnImp -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnImp.Text = "Importieren"
    $dlg.Controls.Add($btnImp)
    $btnCa = New-Object System.Windows.Forms.Button
    $btnCa.SetBounds((S 894), (S 598), (S 94), (S 28)); $btnCa.Anchor = $aBR
    Style-FlatButton -Btn $btnCa -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $btnCa.Text = "Abbrechen"
    $btnCa.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCa)
    $dlg.CancelButton = $btnCa

    $script:CsvCtl = @{ Dlg = $dlg; Grid = $g; Csv = $csv; Combos = $combos; Cur = $cbCur; Suf = $cbSuf; Sum = $lSum; Reb = $chkReb; Rows = @(); IsinMap = @{}; File = (Split-Path -Leaf $ofd.FileName); Imported = 0 }
    $script:CsvCtl.Fill = {
        $cc = $script:CsvCtl
        $map = @{}
        foreach ($f in $cc.Combos.Keys) { $map[$f] = $cc.Combos[$f].SelectedIndex - 1 }
        $cc.Rows = @(ConvertFrom-BrokerRows -Rows $cc.Csv.Rows -Map $map -DefaultCurrency ([string]$cc.Cur.SelectedItem))
        $existing = $script:Transactions.ToArray()
        $cc.Grid.Rows.Clear()
        $nOk = 0; $nDup = 0; $nIsin = 0
        foreach ($b in $cc.Rows) {
            $sym = if (Test-Isin $b.Ident) { [string]$cc.IsinMap[$b.Ident] } else { $b.Ident }
            $note = $b.Note
            $use = $b.Ok
            if ($b.Ok -and -not $sym) { $note = "ISIN noch nicht aufgelöst"; $use = $false; $nIsin++ }
            elseif ($b.Ok -and (Test-DuplicateTransaction -Existing $existing -New ([PSCustomObject]@{ Date = $b.Date; Ticker = $sym; Type = $b.Type; Shares = $b.Shares; Price = $b.Price }))) { $note = "schon vorhanden"; $use = $false; $nDup++ }
            if ($use) { $nOk++ }
            $ri = $cc.Grid.Rows.Add($use, (Format-IsoDateDe $b.Date), $b.Type, $b.Ident, $sym, ("{0:N4}" -f $b.Shares), ("{0:N4}" -f $b.Price), ("{0:N2}" -f $b.Fee), $b.Currency, $note)
            if (-not $b.Ok) { $cc.Grid.Rows[$ri].DefaultCellStyle.ForeColor = $script:Pal.Muted }
        }
        $cc.Sum.Text = "{0} Zeilen: {1} zum Import, {2} schon vorhanden, {3} ISIN offen, {4} übersprungen (Art/Datum/Stück fehlen, z. B. Ein-/Auszahlungen)." -f $cc.Rows.Count, $nOk, $nDup, $nIsin, @($cc.Rows | Where-Object { -not $_.Ok }).Count
    }
    foreach ($cb in @($combos.Values) + @($cbCur)) { $cb.Add_SelectionChangeCommitted({ & $script:CsvCtl.Fill }) }
    $btnRes.Add_Click({
        $cc = $script:CsvCtl
        $isins = @($cc.Rows | Where-Object { Test-Isin $_.Ident } | ForEach-Object { $_.Ident } | Sort-Object -Unique | Where-Object { -not $cc.IsinMap.ContainsKey($_) })
        if ($isins.Count -eq 0) { & $cc.Fill; return }
        $suf = ([string]$cc.Suf.SelectedItem).Split(' ')[0]
        if (-not $suf.StartsWith(".")) { $suf = "" }
        $cc.Sum.Text = "Suche {0} ISIN(s) bei Yahoo ..." -f $isins.Count
        $cc.Dlg.Refresh()
        $urls = @{}
        foreach ($is in $isins) { $urls[$is] = "https://query1.finance.yahoo.com/v1/finance/search?q={0}&quotesCount=10&newsCount=0" -f $is }
        $res = Invoke-ParallelFetch -Urls @($urls.Values) -TimeoutSec 12
        foreach ($is in $isins) {
            $s = Get-YahooSymbolFromSearch -Json $res[$urls[$is]] -PreferSuffix $suf
            if ($s) { $cc.IsinMap[$is] = $s }
        }
        & $cc.Fill
    })
    $g.Add_CellEndEdit({
        param($sender, $e)
        if ($sender.Columns[$e.ColumnIndex].Name -ne "Sym") { return }
        $cc = $script:CsvCtl
        $b = $cc.Rows[$e.RowIndex]
        $v = ([string]$sender.Rows[$e.RowIndex].Cells["Sym"].Value).Trim().ToUpper()
        $sender.Rows[$e.RowIndex].Cells["Sym"].Value = $v
        if ((Test-Isin $b.Ident) -and $v) { $cc.IsinMap[$b.Ident] = $v }
        if ($v -and $b.Ok) { $sender.Rows[$e.RowIndex].Cells["Use"].Value = $true }
    })
    $btnImp.Add_Click({
        $cc = $script:CsvCtl
        $cc.Grid.EndEdit() | Out-Null
        $n = 0
        $syms = New-Object System.Collections.Generic.HashSet[string]
        for ($k = 0; $k -lt $cc.Rows.Count; $k++) {
            $row = $cc.Grid.Rows[$k]
            if (-not [bool]$row.Cells["Use"].Value) { continue }
            $b = $cc.Rows[$k]
            $sym = ([string]$row.Cells["Sym"].Value).Trim().ToUpper()
            if (-not $b.Ok -or -not $sym) { continue }
            $script:Transactions.Add([PSCustomObject]@{
                Id = [Guid]::NewGuid().ToString("N"); Date = $b.Date; Ticker = $sym; Type = $b.Type
                Shares = [double]$b.Shares; Price = [double]$b.Price; Fee = [double]$b.Fee; Currency = $b.Currency
                Realized = 0.0; Note = "CSV-Import " + $cc.File
            })
            [void]$syms.Add($sym)
            $n++
        }
        if ($n -eq 0) { $cc.Sum.Text = "Nichts ausgewählt."; return }
        [void](Backup-DataFiles -Reason "vor_csv_import")
        Save-Transactions
        Write-WidgetLog ("CSV import: {0} bookings from {1}" -f $n, $cc.File)
        if ($cc.Reb.Checked) {
            foreach ($s in $syms) { [void](Invoke-PositionRebuild -Ticker $s -Owner $cc.Dlg -Silent) }
        }
        $cc.Imported = $n
        $cc.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cc.Dlg.Close()
    })
    $dlg.Add_Shown({ & $script:CsvCtl.Fill })
    [void]$dlg.ShowDialog($form)
    $n = [int]$script:CsvCtl.Imported
    $script:CsvCtl = $null
    $dlg.Dispose()
    if ($n -gt 0) {
        Set-TransientStatus ("{0} Buchungen importiert" -f $n) 5
        Refresh-AllMarketData
        Update-AllUiViews
    }
}

# ==============================================================================
# v4.6: grid columns, global hotkey, click-through, snapping, undo, price
# flash, colours, own layouts, welcome tour
# ==============================================================================

# ---- colours ----
function Get-BlendColor {
    param([System.Drawing.Color]$A, [System.Drawing.Color]$B, [double]$T)
    return [System.Drawing.Color]::FromArgb([int]($B.R + ($A.R - $B.R) * $T), [int]($B.G + ($A.G - $B.G) * $T), [int]($B.B + ($A.B - $B.B) * $T))
}

function Update-UpDownColors {
    $ud = Get-UpDownColors -Scheme ([string]$script:Config.UpDownScheme) -UpHex ([string]$script:Config.UpColor) -DownHex ([string]$script:Config.DownColor)
    $script:colGreen = [System.Drawing.Color]::FromArgb($ud.Up[0], $ud.Up[1], $ud.Up[2])
    $script:colRed = [System.Drawing.Color]::FromArgb($ud.Down[0], $ud.Down[1], $ud.Down[2])
}

function Get-ArrowPrefix {
    param([double]$V)
    if (-not [bool]$script:Config.ShowArrows) { return "" }
    if ($V -gt 0) { return [string][char]0x25B2 + " " }
    if ($V -lt 0) { return [string][char]0x25BC + " " }
    return ""
}

# ---- grid columns: right-click on a header, drag headers to reorder ----
$script:GridDefaults = @{}
$script:GridLayoutSig = @{}
$script:GridLayoutBusy = $false

function Save-GridLayout {
    param([System.Windows.Forms.DataGridView]$Grid, [string]$Key)
    if ($script:GridLayoutBusy) { return }
    $gl = $script:Config.GridLayouts
    if ($null -eq $gl) { $gl = [PSCustomObject]@{}; $script:Config.GridLayouts = $gl }
    $val = @(ConvertTo-GridLayout @($Grid.Columns))
    # resizing the window changes widths but not the weights: only save real changes
    $sig = ($val | ForEach-Object { "{0}:{1}:{2:F1}:{3}" -f $_.Name, $_.Index, $_.Weight, $_.Visible }) -join "|"
    if ($script:GridLayoutSig[$Key] -eq $sig) { return }
    $script:GridLayoutSig[$Key] = $sig
    if ($null -eq $gl.PSObject.Properties[$Key]) { $gl | Add-Member -NotePropertyName $Key -NotePropertyValue $val -Force } else { $gl.$Key = $val }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
}

function Restore-GridLayout {
    param([System.Windows.Forms.DataGridView]$Grid, [string]$Key, [switch]$Defaults)
    $items = $null
    if ($Defaults) { $items = $script:GridDefaults[$Key] }
    elseif ($null -ne $script:Config.GridLayouts -and $null -ne $script:Config.GridLayouts.PSObject.Properties[$Key]) { $items = @($script:Config.GridLayouts.$Key) }
    if ($null -eq $items) { return }
    $script:GridLayoutBusy = $true
    try {
        foreach ($it in @($items | Sort-Object -Property @{ Expression = { [int]$_.Index } })) {
            $col = $Grid.Columns[[string]$it.Name]
            if ($null -eq $col) { continue }
            if ($col.Index -ne 0) { $col.Visible = [bool]$it.Visible }
            if ([double]$it.Weight -gt 0) { $col.FillWeight = [float][double]$it.Weight }
            $col.DisplayIndex = [math]::Min([int]$it.Index, $Grid.Columns.Count - 1)
        }
    } catch { Write-WidgetLog "Grid layout $Key not restored: $($_.Exception.Message)" "WARN" }
    finally { $script:GridLayoutBusy = $false }
}

function Enable-GridCustomization {
    param([System.Windows.Forms.DataGridView]$Grid, [string]$Key)
    $script:GridDefaults[$Key] = @(ConvertTo-GridLayout @($Grid.Columns))
    $Grid.AllowUserToOrderColumns = $true
    $Grid.Tag = $Key
    Restore-GridLayout -Grid $Grid -Key $Key
    $script:GridLayoutSig[$Key] = (@(ConvertTo-GridLayout @($Grid.Columns)) | ForEach-Object { "{0}:{1}:{2:F1}:{3}" -f $_.Name, $_.Index, $_.Weight, $_.Visible }) -join "|"
    $Grid.Add_ColumnDisplayIndexChanged({ param($sender, $e) Save-GridLayout -Grid $sender -Key ([string]$sender.Tag) })
    $Grid.Add_ColumnWidthChanged({ param($sender, $e) Save-GridLayout -Grid $sender -Key ([string]$sender.Tag) })
    $Grid.Add_ColumnHeaderMouseClick({
        param($sender, $e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $menu.ShowCheckMargin = $true
        foreach ($col in @($sender.Columns | Sort-Object DisplayIndex)) {
            $mi = New-Object System.Windows.Forms.ToolStripMenuItem($(if ($col.HeaderText) { $col.HeaderText } else { $col.Name }))
            $mi.Checked = $col.Visible
            $mi.Enabled = ($col.Index -ne 0)
            $mi.Tag = @($sender, $col.Name)
            $mi.Add_Click({
                param($s2, $e2)
                $gr = $s2.Tag[0]; $cn = [string]$s2.Tag[1]
                $gr.Columns[$cn].Visible = -not $gr.Columns[$cn].Visible
                Save-GridLayout -Grid $gr -Key ([string]$gr.Tag)
            })
            [void]$menu.Items.Add($mi)
        }
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $rs = New-Object System.Windows.Forms.ToolStripMenuItem("Standard wiederherstellen")
        $rs.Tag = $sender
        $rs.Add_Click({
            param($s2, $e2)
            Restore-GridLayout -Grid $s2.Tag -Key ([string]$s2.Tag.Tag) -Defaults
            Save-GridLayout -Grid $s2.Tag -Key ([string]$s2.Tag.Tag)
        })
        [void]$menu.Items.Add($rs)
        $menu.Show($sender, $sender.PointToClient([System.Windows.Forms.Cursor]::Position))
    })
}

# ---- global hotkey + click-through (Win32 via a small helper class) ----
$script:Hotkey = $null
$script:HotkeyTypeOk = $false
try {
    if (-not ("TwHotkeyWindow" -as [type])) {
        $refs = New-Object System.Collections.Generic.List[string]
        foreach ($t in @([System.Windows.Forms.NativeWindow], [System.Windows.Forms.Message], [System.Windows.Forms.CreateParams])) {
            $loc = $t.Assembly.Location
            if ($loc -and -not $refs.Contains($loc)) { $refs.Add($loc) }
        }
        Add-Type -ReferencedAssemblies $refs.ToArray() -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TwHotkeyWindow : System.Windows.Forms.NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int index, int value);
    public Action OnHotkey;
    bool registered;
    public TwHotkeyWindow() { CreateHandle(new System.Windows.Forms.CreateParams()); }
    public bool Register(uint mods, uint vk) { Unregister(); registered = RegisterHotKey(Handle, 0x7A11, mods | 0x4000, vk); return registered; }
    public void Unregister() { if (registered) { UnregisterHotKey(Handle, 0x7A11); registered = false; } }
    protected override void WndProc(ref System.Windows.Forms.Message m) {
        if (m.Msg == 0x0312 && OnHotkey != null) { try { OnHotkey(); } catch { } }
        base.WndProc(ref m);
    }
    public void Dispose() { Unregister(); DestroyHandle(); }
    public static void SetClickThrough(IntPtr hWnd, bool on) {
        int ex = GetWindowLong(hWnd, -20);
        if (on) { ex = ex | 0x80000 | 0x20; } else { ex = ex & ~0x20; }
        SetWindowLong(hWnd, -20, ex);
    }
}
"@
    }
    $script:HotkeyTypeOk = $true
} catch {
    Write-WidgetLog "Hotkey helper not available: $($_.Exception.Message)" "WARN"
}

function Invoke-HotkeyToggle {
    if ($script:IsClosing) { return }
    if ($script:ClickThrough) { Set-ClickThrough $false }
    if ($form.Visible -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and [System.Windows.Forms.Form]::ActiveForm -eq $form) {
        $form.Hide()
    } else {
        Show-MainWindow
        $form.Activate()
    }
}

function Register-GlobalHotkey {
    if (-not $script:HotkeyTypeOk) { return "nicht verfügbar" }
    try {
        if ($null -eq $script:Hotkey) {
            $script:Hotkey = New-Object TwHotkeyWindow
            $script:Hotkey.OnHotkey = [Action]{ Invoke-HotkeyToggle }
        }
        $script:Hotkey.Unregister()
        $hk = ConvertFrom-HotkeyText ([string]$script:Config.GlobalHotkey)
        if ($null -eq $hk) { return "aus" }
        if ($script:Hotkey.Register([uint32]$hk.Mods, [uint32]$hk.Key)) { Write-WidgetLog "Global hotkey: $($hk.Text)"; return "" }
        Write-WidgetLog "Global hotkey $($hk.Text) is used by another program" "WARN"
        return "$($hk.Text) ist schon von einem anderen Programm belegt"
    } catch {
        Write-WidgetLog "Global hotkey failed: $($_.Exception.Message)" "WARN"
        return "Fehler: $($_.Exception.Message)"
    }
}

$script:ClickThrough = $false
function Set-ClickThrough {
    param([bool]$On)
    if (-not $script:HotkeyTypeOk) { Set-TransientStatus "Durchklicken ist auf diesem System nicht verfügbar" 4; return }
    if ($On -and -not (ConvertFrom-HotkeyText ([string]$script:Config.GlobalHotkey))) {
        Show-InfoBox -Text "Zum Zurückholen wird das globale Tastenkürzel gebraucht (Einstellungen). Ohne Kürzel bleibt nur das Tray-Menü." -Title "Durchklicken"
    }
    $script:ClickThrough = $On
    try { [TwHotkeyWindow]::SetClickThrough($form.Handle, $On) } catch { Write-WidgetLog "Click-through failed: $($_.Exception.Message)" "WARN" }
    if ($On) {
        if (-not $form.TopMost) { $form.TopMost = $true }
        if ($form.Opacity -gt 0.85) { $form.Opacity = 0.85 }
    } else {
        $form.Opacity = [double]$script:Config.Opacity / 100.0
        $form.TopMost = [bool]$script:Config.TopMost
    }
    $miClickThrough.Checked = $On
    Write-WidgetLog "Click-through: $On"
}

# ---- undo for deletions (Ctrl+Z within 10 seconds) ----
$script:Undo = $null
function Set-Undo {
    param([string]$Kind, $Data, [string]$Text)
    $script:Undo = @{ Kind = $Kind; Data = $Data; Until = (Get-Date).AddSeconds(10) }
    $script:Redo = $null
    Set-TransientStatus ("{0} - Strg+Z = rückgängig" -f $Text) 10
}

$script:Redo = $null
function Invoke-Undo {
    $u = $script:Undo
    if (-not (Test-UndoValid -Undo $u)) { return $false }
    $script:Undo = $null
    # v4.9.5: remember the state before undoing, so Ctrl+Y can redo it
    $redoData = $null
    switch ($u.Kind) {
        "Alert" {
            $ix = [math]::Min([int]$u.Data.Index, $script:Alerts.Count)
            $script:Alerts.Insert($ix, $u.Data.Item)
            Save-Alerts
            $redoData = @{ Item = $u.Data.Item }
        }
        "Position" {
            $k = [string]$u.Data.Key
            $redoData = @{ Key = $k; Item = $(if ($script:Portfolio.ContainsKey($k)) { $script:Portfolio[$k] } else { $null }) }
            $script:Portfolio[$k] = $u.Data.Item
            Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
        }
        "Watchlist" {
            $redoData = @($script:Config.Watchlist)
            $script:Config.Watchlist = @($u.Data)
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
        }
    }
    $script:Redo = @{ Kind = $u.Kind; Data = $redoData; Undo = $u; Until = (Get-Date).AddSeconds(30) }
    Set-TransientStatus "Wiederhergestellt - Strg+Y = wiederholen" 4
    Refresh-AllMarketData
    Update-AllUiViews
    return $true
}

function Invoke-Redo {
    # v4.9.5: Ctrl+Y redoes the last undo (within 30 seconds); Ctrl+Z works again after it
    $r = $script:Redo
    if (-not (Test-UndoValid -Undo $r)) { return $false }
    $script:Redo = $null
    switch ($r.Kind) {
        "Alert" {
            # by reference: PSCustomObjects all compare equal in List.Remove
            for ($i = 0; $i -lt $script:Alerts.Count; $i++) {
                if ([object]::ReferenceEquals($script:Alerts[$i], $r.Data.Item)) { $script:Alerts.RemoveAt($i); break }
            }
            Save-Alerts
        }
        "Position" {
            $k = [string]$r.Data.Key
            if ($null -eq $r.Data.Item) { [void]$script:Portfolio.Remove($k) } else { $script:Portfolio[$k] = $r.Data.Item }
            Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
        }
        "Watchlist" {
            $script:Config.Watchlist = @($r.Data)
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
        }
    }
    $u = $r.Undo
    $u.Until = (Get-Date).AddSeconds(10)
    $script:Undo = $u
    Set-TransientStatus "Wiederholt - Strg+Z = rückgängig" 4
    Refresh-AllMarketData
    Update-AllUiViews
    return $true
}

# ---- v4.9.5: copy a list as a table (Ctrl+C) ----
function Copy-GridAsTable {
    param([System.Windows.Forms.DataGridView]$Grid)
    $cols = @($Grid.Columns | Where-Object { $_.Visible -and $_.Name -ne "Spark" } | Sort-Object DisplayIndex)
    if ($cols.Count -eq 0) { return $false }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Grid.Rows) {
        if ($Grid -eq $dgvNews -and $null -eq $r.Tag) { continue }   # the "loading" line
        $vals = @($cols | ForEach-Object { [string]$r.Cells[$_.Index].FormattedValue })
        $rows.Add($vals)
    }
    if ($rows.Count -eq 0) { return $false }
    $txt = ConvertTo-TsvTable -Headers @($cols | ForEach-Object { $_.HeaderText }) -Rows $rows.ToArray()
    try { [System.Windows.Forms.Clipboard]::SetText($txt) } catch { Set-TransientStatus "Zwischenablage nicht verfügbar" 3; return $true }
    Set-TransientStatus ("{0} Zeilen kopiert - in Excel oder eine Mail einfügen" -f $rows.Count) 4
    return $true
}

# ==============================================================================
# v5.0 Stage A: cash account + savings plans (dialogs and booking)
# ==============================================================================
function Show-CashDialog {
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Cash-Konto - $(Get-DepotName ([string]$script:Config.ActiveDepot))" -W (S 720) -H (S 470)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 600), (S 360))
    $dlg.KeyPreview = $true
    $dlg.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() } })
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.SetBounds((S 14), (S 12), (S 330), (S 22)); $chk.Text = "Cash-Konto für dieses Depot führen"
    $chk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $chk.ForeColor = $p.Text
    $chk.Checked = [bool]$script:Cash.Enabled
    $dlg.Controls.Add($chk)
    Set-DynTip $chk "Ab dem Einschalten verändern neue Käufe, Verkäufe und Dividenden den Kontostand. Ältere Buchungen zählen nicht - dafür fragt das Widget nach dem heutigen Kontostand."
    $lblCur = New-Object System.Windows.Forms.Label
    $lblCur.SetBounds((S 360), (S 15), (S 70), (S 18)); $lblCur.Text = "Währung:"
    $dlg.Controls.Add($lblCur)
    $cbCur = New-Object System.Windows.Forms.ComboBox
    $cbCur.SetBounds((S 432), (S 11), (S 70), (S 24))
    $cbCur.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbCur.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cbCur.BackColor = $p.Input; $cbCur.ForeColor = $p.Accent
    foreach ($c in (Get-DisplayCurrencies)) { [void]$cbCur.Items.Add($c) }
    Select-CurrencyInCombo -Combo $cbCur -Code ([string]$script:Cash.Currency)
    $dlg.Controls.Add($cbCur)

    $lblBal = New-Object System.Windows.Forms.Label
    $lblBal.SetBounds((S 14), (S 44), (S 690), (S 30)); $lblBal.Anchor = $aT -bor $aL -bor $aR
    $lblBal.Font = $fontPrice; $lblBal.ForeColor = $p.Text
    $dlg.Controls.Add($lblBal)

    $mk = {
        param([string]$T, [int]$X, [string]$Tip)
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds($X, (S 82), (S 104), (S 26))
        Style-FlatButton -Btn $b -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
        $b.Text = $T
        $dlg.Controls.Add($b)
        Set-DynTip $b $Tip
        return $b
    }
    $bIn  = & $mk "Einzahlung" (S 14) "Geld auf das Depotkonto einzahlen"
    $bOut = & $mk "Auszahlung" (S 122) "Geld vom Depotkonto abheben"
    $bInt = & $mk "Zinsen" (S 230) "Zinsen gutschreiben (netto)"
    $bFee = & $mk "Gebühr" (S 338) "Kontoführung, Depotgebühr ... abziehen"
    $bSet = & $mk "Stand setzen" (S 446) "Kontostand laut Bank eintragen - die Differenz wird als Korrektur gebucht"
    $bDel = & $mk "Eintrag löschen" (S 554) "Markierten Kassen-Eintrag löschen (Käufe / Verkäufe hier nicht - die in der Historie)"
    $bDel.Width = S 150

    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds((S 14), (S 118), (S 690), (S 300)); $g.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Style-DataGrid -Grid $g
    foreach ($cn in @("Datum", "Art", "Ticker", "Betrag", "Währung", "Notiz")) { [void]$g.Columns.Add($cn, $cn) }
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $g.Columns["Betrag"].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight
    $g.Columns["Notiz"].FillWeight = 160
    $dlg.Controls.Add($g)
    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.SetBounds((S 14), (S 424), (S 690), (S 36)); $lblInfo.Anchor = $aB -bor $aL -bor $aR
    $lblInfo.ForeColor = $p.Muted
    $lblInfo.Text = "Käufe ziehen Kurs x Stück + Gebühr ab, Verkäufe bringen Erlös - Gebühr, Dividenden Betrag - Steuer. Fremdwährungen zum aktuellen Kurs umgerechnet."
    $dlg.Controls.Add($lblInfo)

    $script:CashCtl = @{ Dlg = $dlg; Chk = $chk; Cur = $cbCur; Bal = $lblBal; Grid = $g; Buttons = @($bIn, $bOut, $bInt, $bFee, $bSet, $bDel) }
    $fill = {
        $cc = $script:CashCtl
        $on = [bool]$script:Cash.Enabled
        foreach ($b in $cc.Buttons) { $b.Enabled = $on }
        $cc.Cur.Enabled = $on
        $cc.Grid.Rows.Clear()
        $ci = Get-CashInfo
        if ($null -eq $ci) { $cc.Bal.Text = Tr "Aus - Haken setzen, um den Kontostand mitzuführen"; $cc.Bal.ForeColor = $script:Pal.Muted; return }
        $cc.Bal.Text = "{0}: {1:N2} {2}" -f (Tr "Kontostand"), $ci.Balance, $ci.Currency
        if (@($ci.Missing).Count -gt 0) { $cc.Bal.Text += "  (ohne " + (@($ci.Missing) -join ", ") + ")" }
        $cc.Bal.ForeColor = if ($ci.Balance -lt 0) { $colRed } else { $script:Pal.Text }
        foreach ($m in @($ci.Movements | Sort-Object -Property Date -Descending)) {
            $note = ""
            if ($m.Source -eq "Cash") { $en = @($script:Cash.Entries | Where-Object { $_.Id -eq $m.Id })[0]; if ($null -ne $en) { $note = [string]$en.Note } }
            $i = $cc.Grid.Rows.Add($m.Date, $m.Kind, $m.Ticker, ("{0:+#,##0.00;-#,##0.00;0.00}" -f $m.Amount), $m.Currency, $note)
            $cc.Grid.Rows[$i].Tag = $m
            $cc.Grid.Rows[$i].Cells["Betrag"].Style.ForeColor = if ($m.Amount -ge 0) { $colGreen } else { $colRed }
            if ($m.Source -eq "Trade") { $cc.Grid.Rows[$i].Cells["Art"].Style.ForeColor = $script:Pal.Muted }
        }
    }
    $script:CashCtl.Fill = $fill
    $askAmount = {
        param([string]$Title, [string]$Prompt)
        $t = Read-TextInput -Title $Title -Prompt $Prompt
        if ($null -eq $t) { return $null }
        $v = Parse-DecimalInput $t
        if ($v -le 0) { [System.Windows.Forms.MessageBox]::Show($script:CashCtl.Dlg, "Bitte einen Betrag größer 0 eingeben.", "Cash", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return $null }
        return $v
    }
    $script:CashCtl.Ask = $askAmount
    $chk.Add_Click({
        $cc = $script:CashCtl
        if ($cc.Chk.Checked -and -not [bool]$script:Cash.Enabled) {
            $cur = [string]$cc.Cur.SelectedItem
            $t = Read-TextInput -Title "Cash-Konto" -Prompt ("Aktueller Kontostand in {0} (vor neuen Buchungen):" -f $cur) -Value "0"
            if ($null -eq $t) { $cc.Chk.Checked = $false; return }
            $script:Cash.Enabled = $true
            $script:Cash.Currency = $cur
            # bookings that exist now are already in this balance
            $script:Cash.BaselineIds = @($script:Transactions | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
            $v = if ($script:SmokeMode) { 1000.0 } else { Parse-DecimalInput $t }
            if ($v -ne 0) { Add-CashEntry -Kind "Start" -Amount $v -Note (Tr "Kontostand beim Einschalten") } else { Save-CashData }
        } elseif (-not $cc.Chk.Checked -and [bool]$script:Cash.Enabled) {
            $script:Cash.Enabled = $false
            Save-CashData
        }
        & $cc.Fill
        Update-AllUiViews
    })
    $cbCur.Add_SelectionChangeCommitted({
        $cc = $script:CashCtl
        $script:Cash.Currency = [string]$cc.Cur.SelectedItem
        Save-CashData
        & $cc.Fill
    })
    $bIn.Add_Click({ $v = & $script:CashCtl.Ask "Einzahlung" ("Betrag in {0}:" -f $script:Cash.Currency); if ($null -ne $v) { Add-CashEntry -Kind "Einzahlung" -Amount $v; & $script:CashCtl.Fill; Update-AllUiViews } })
    $bOut.Add_Click({ $v = & $script:CashCtl.Ask "Auszahlung" ("Betrag in {0}:" -f $script:Cash.Currency); if ($null -ne $v) { Add-CashEntry -Kind "Auszahlung" -Amount (-$v); & $script:CashCtl.Fill; Update-AllUiViews } })
    $bInt.Add_Click({ $v = & $script:CashCtl.Ask "Zinsen" ("Zinsen (netto) in {0}:" -f $script:Cash.Currency); if ($null -ne $v) { Add-CashEntry -Kind "Zinsen" -Amount $v; & $script:CashCtl.Fill; Update-AllUiViews } })
    $bFee.Add_Click({ $v = & $script:CashCtl.Ask "Gebühr" ("Gebühr in {0}:" -f $script:Cash.Currency); if ($null -ne $v) { Add-CashEntry -Kind "Gebühr" -Amount (-$v); & $script:CashCtl.Fill; Update-AllUiViews } })
    $bSet.Add_Click({
        $ci = Get-CashInfo
        if ($null -eq $ci) { return }
        $t = Read-TextInput -Title "Kontostand setzen" -Prompt ("Kontostand laut Bank in {0}:" -f $ci.Currency) -Value ("{0:0.00}" -f $ci.Balance)
        if ($null -eq $t) { return }
        $diff = (Parse-DecimalInput $t) - $ci.Balance
        if ([math]::Abs($diff) -ge 0.005) { Add-CashEntry -Kind "Korrektur" -Amount $diff -Note ("{0} {1:N2}" -f (Tr "gesetzt auf"), (Parse-DecimalInput $t)) }
        & $script:CashCtl.Fill; Update-AllUiViews
    })
    $bDel.Add_Click({
        $cc = $script:CashCtl
        if ($cc.Grid.SelectedRows.Count -eq 0) { return }
        $m = $cc.Grid.SelectedRows[0].Tag
        if ($null -eq $m -or $m.Source -ne "Cash") { Set-TransientStatus "Käufe / Verkäufe / Dividenden bitte in der Transaktions-Historie löschen" 5; return }
        for ($i = 0; $i -lt $script:Cash.Entries.Count; $i++) { if ($script:Cash.Entries[$i].Id -eq $m.Id) { $script:Cash.Entries.RemoveAt($i); break } }
        Save-CashData
        & $cc.Fill; Update-AllUiViews
    })
    & $fill
    Apply-Language $dlg
    [void]$dlg.ShowDialog($form)
    $script:CashCtl = $null
    $dlg.Dispose()
}

function Show-SavingsPlansDialog {
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Sparpläne - $(Get-DepotName ([string]$script:Config.ActiveDepot))" -W (S 760) -H (S 420)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 640), (S 320))
    $dlg.KeyPreview = $true
    $dlg.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() } })
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.SetBounds((S 14), (S 10), (S 730), (S 36)); $lbl.Anchor = $aT -bor $aL -bor $aR; $lbl.ForeColor = $p.Muted
    $lbl.Text = "Jeden Monat am Stichtag wird ein Kauf zum Schlusskurs dieses Tages gebucht (am Wochenende: letzter Handelstag davor). Verpasste Monate werden beim nächsten Start nachgebucht."
    $dlg.Controls.Add($lbl)
    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds((S 14), (S 50), (S 730), (S 280)); $g.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Style-DataGrid -Grid $g
    $g.ReadOnly = $false
    foreach ($cn in @("Ticker", "Betrag", "Währung", "Gebühr", "Tag", "Start", "Zuletzt", "Aktiv")) {
        if ($cn -eq "Aktiv") { $col = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn; $col.Name = $cn; $col.HeaderText = $cn; [void]$g.Columns.Add($col) }
        else { [void]$g.Columns.Add($cn, $cn) }
    }
    $g.Columns["Zuletzt"].ReadOnly = $true
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $g.Columns["Ticker"].ToolTipText = "Yahoo-Symbol, z. B. EUNL.DE"
    $g.Columns["Tag"].ToolTipText = "Tag im Monat (1-28)"
    $g.Columns["Start"].ToolTipText = "Erster Monat, JJJJ-MM-TT"
    $dlg.Controls.Add($g)
    foreach ($pl in $script:SavingsPlans) {
        $i = $g.Rows.Add($pl.Ticker, ("{0:0.00}" -f $pl.Amount), $pl.Currency, ("{0:0.00}" -f $pl.Fee), $pl.Day, $pl.Start, $pl.LastBooked, [bool]$pl.Active)
        $g.Rows[$i].Tag = $pl.Id
    }
    $mk = {
        param([string]$T, [int]$X, $Anchor)
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds($X, (S 340), (S 130), (S 28)); $b.Anchor = $Anchor
        Style-FlatButton -Btn $b -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
        $b.Text = $T
        $dlg.Controls.Add($b)
        return $b
    }
    $bAdd = & $mk "+ Sparplan" (S 14) ($aB -bor $aL)
    $bDel = & $mk "Entfernen" (S 150) ($aB -bor $aL)
    $bRun = & $mk "Jetzt prüfen" (S 286) ($aB -bor $aL)
    $bOk  = & $mk "Speichern" (S 614) ($aB -bor $aR)
    Style-FlatButton -Btn $bOk -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $script:PlanCtl = @{ Dlg = $dlg; Grid = $g }
    $bAdd.Add_Click({
        $g = $script:PlanCtl.Grid
        $sym = ([string]$script:Config.ActiveTicker).ToUpper()
        $cur = if ($script:QuoteStore.ContainsKey($sym)) { [string]$script:QuoteStore[$sym].Currency } else { "EUR" }
        $nextM = (Get-Date).AddMonths(1)
        $i = $g.Rows.Add($sym, "100.00", $cur, "0.00", 1, (New-Object DateTime($nextM.Year, $nextM.Month, 1)).ToString("yyyy-MM-dd"), "", $true)
        $g.Rows[$i].Tag = [Guid]::NewGuid().ToString("N")
        $g.CurrentCell = $g.Rows[$i].Cells["Ticker"]
    })
    $bDel.Add_Click({ $g = $script:PlanCtl.Grid; if ($g.SelectedRows.Count -gt 0) { $g.Rows.Remove($g.SelectedRows[0]) } elseif ($null -ne $g.CurrentRow) { $g.Rows.Remove($g.CurrentRow) } })
    $save = {
        $g = $script:PlanCtl.Grid
        [void]$g.EndEdit()
        $list = New-Object System.Collections.Generic.List[object]
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        foreach ($r in $g.Rows) {
            $sym = ([string]$r.Cells["Ticker"].Value).Trim().ToUpper()
            if (-not $sym) { continue }
            $st = ([string]$r.Cells["Start"].Value).Trim()
            $d = [DateTime]::MinValue
            if (-not [DateTime]::TryParseExact($st, "yyyy-MM-dd", $inv, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { $st = (Get-Date).ToString("yyyy-MM-dd") }
            $cur = Get-NormalizedCurrencyCode ([string]$r.Cells["Währung"].Value)
            if (-not $cur) { $cur = "EUR" }
            $list.Add([PSCustomObject]@{
                Id = [string]$r.Tag; Ticker = $sym; Amount = (Parse-DecimalInput ([string]$r.Cells["Betrag"].Value)); Fee = (Parse-DecimalInput ([string]$r.Cells["Gebühr"].Value))
                Currency = $cur; Day = [math]::Max(1, [math]::Min(28, [int](Parse-DecimalInput ([string]$r.Cells["Tag"].Value)))); Start = $st
                LastBooked = [string]$r.Cells["Zuletzt"].Value; Active = [bool]$r.Cells["Aktiv"].Value
            })
        }
        $script:SavingsPlans = $list
        Save-SavingsPlans
    }
    $script:PlanCtl.Save = $save
    $bOk.Add_Click({ & $script:PlanCtl.Save; $script:PlanCtl.Dlg.Close(); Invoke-SavingsPlans })
    $bRun.Add_Click({ & $script:PlanCtl.Save; Invoke-SavingsPlans; Set-TransientStatus "Sparpläne werden geprüft ..." 3 })
    Apply-Language $dlg
    [void]$dlg.ShowDialog($form)
    $script:PlanCtl = $null
    $dlg.Dispose()
}

$script:PlansRunning = $false
function Invoke-SavingsPlans {
    # Books the due months of every active plan at the close of the due day
    if ($script:IsClosing -or $script:PlansRunning -or $null -eq $script:SavingsPlans -or $script:SavingsPlans.Count -eq 0) { return }
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $due = @{}
    foreach ($pl in $script:SavingsPlans) {
        if (-not [bool]$pl.Active -or [double]$pl.Amount -le 0) { continue }
        $ds = @(Get-DueSavingsDates -Plan $pl -Today $today)
        if ($ds.Count -gt 0) { $due[$pl.Id] = $ds }
    }
    if ($due.Count -eq 0) { return }
    $urls = @{}
    foreach ($pl in @($script:SavingsPlans | Where-Object { $due.ContainsKey($_.Id) })) {
        $first = [DateTime]::ParseExact([string]$due[$pl.Id][0], "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
        $p1 = [DateTimeOffset]::new($first.AddDays(-10)).ToUnixTimeSeconds()
        $p2 = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $urls[$pl.Id] = "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval=1d&period1={1}&period2={2}" -f [Uri]::EscapeDataString($pl.Ticker), $p1, $p2
    }
    $script:PlansRunning = $true
    Start-FetchJob -Urls @($urls.Values) -MaxConcurrency 2 -Context @{ Urls = $urls; Due = $due } -OnComplete {
        param($Box, $Ctx)
        $script:PlansRunning = $false
        $booked = 0
        foreach ($id in @($Ctx.Urls.Keys)) {
            $pl = @($script:SavingsPlans | Where-Object { $_.Id -eq $id })[0]
            if ($null -eq $pl) { continue }
            $h = ConvertFrom-YahooDailyHistory -Json $Box.Results[$Ctx.Urls[$id]]
            if ($null -eq $h) { Write-WidgetLog "Savings plan $($pl.Ticker): no price history" "WARN"; continue }
            foreach ($d in @($Ctx.Due[$id])) {
                $c = Get-CloseOnOrBefore -Dates $h.Dates -Closes $h.Closes -Date $d
                if ($null -eq $c) { continue }
                # amount and fee in the plan currency, price in the instrument currency
                $px = Convert-CurrencyValue -Amount $c.Close -FromCurrency ([string]$h.Currency) -ToCurrency ([string]$pl.Currency)
                if ($px -le 0) { continue }
                $sh = ([double]$pl.Amount - [double]$pl.Fee) / $px
                if ($sh -le 0) { continue }
                $err = Invoke-Transaction -Type "Kauf" -Ticker $pl.Ticker -Shares $sh -Price $px -Fee ([double]$pl.Fee) -Currency ([string]$pl.Currency) -Date $d -Note ("Sparplan {0:N2} {1}" -f [double]$pl.Amount, $pl.Currency)
                if ($err) { Write-WidgetLog "Savings plan $($pl.Ticker) $d : $err" "WARN"; break }
                $pl.LastBooked = $d
                $booked++
            }
        }
        if ($booked -gt 0) {
            Save-SavingsPlans
            Write-WidgetLog "Savings plans: $booked booking(s)"
            [void](Send-WidgetNotification -Title "Sparplan" -Message ("{0} Kauf/Käufe gebucht - siehe Transaktions-Historie" -f $booked) -Kind "Info" -AllowPush $false)
            Refresh-AllMarketData
            Update-AllUiViews
        }
    }
}

# ---- v4.9.5: privacy mode (F9) ----
function Set-PrivacyMode {
    param([bool]$On)
    $script:Config.PrivacyMode = $On
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    $script:LastTrayIconKey = ""
    Set-TransientStatus $(if ($On) { "Privat-Modus an: Beträge ausgeblendet (F9 = aus)" } else { "Privat-Modus aus" }) 4
    Update-PrivacyIndicator
    Update-AllUiViews
    if ($viewPortfolio.Visible) { Refresh-PortfolioGrid }
}

function Update-PrivacyIndicator {
    # eye = amounts shown (click hides), crossed eye = hidden; tray menu tick
    $on = [bool]$script:Config.PrivacyMode
    if ($script:IconFont) {
        $btnPrivacy.Text = if ($on) { [string][char]0xED1A } else { [string][char]0xE7B3 }
    } else {
        $btnPrivacy.Text = if ($on) { [string][char]0x2022 } else { "P" }
    }
    $btnPrivacy.ForeColor = if ($on) { $script:Pal.Accent } else { $script:Pal.Muted }
    Set-DynTip $btnPrivacy $(if ($on) { "Privat-Modus an: Beträge ausgeblendet. Klick oder F9 = wieder zeigen." } else { "Beträge ausblenden (Privat-Modus, F9 / Fn+F9), z. B. beim Bildschirm teilen" })
    $miPrivacy.Checked = $on
    $b = $tabButtons["Portfolio"]
    if ($null -eq $b) { return }
    $want = if ([bool]$script:Config.PrivacyMode) { "Portfolio " + [string][char]0x2022 + [string][char]0x2022 } else { "Portfolio (F2)" }
    if ($b.Text -ne (Tr $want)) { $b.Text = Tr $want }
}

# ---- price flash ----
$script:LastFlashPrice = @{}
# v4.9.5: the tint holds briefly, then fades back over ~0.6 s
$script:FlashCells = New-Object System.Collections.Generic.List[object]
$script:FlashTimer = New-Object System.Windows.Forms.Timer
$script:FlashTimer.Interval = 50
$script:FlashTimer.Add_Tick({
    $now = Get-Date
    for ($i = $script:FlashCells.Count - 1; $i -ge 0; $i--) {
        $f = $script:FlashCells[$i]
        $a = Get-FlashAlpha -ElapsedMs (($now - $f.Start).TotalMilliseconds) -HoldMs 300 -FadeMs 600 -Max 0.35
        try {
            if ($a -le 0) {
                $f.Cell.Style.BackColor = [System.Drawing.Color]::Empty
                $script:FlashCells.RemoveAt($i)
            } else {
                $f.Cell.Style.BackColor = Get-BlendColor -A $f.Color -B $script:Pal.Card -T $a
            }
        } catch { $script:FlashCells.RemoveAt($i) }
    }
    if ($script:FlashCells.Count -eq 0) { $script:FlashTimer.Stop() }
})

function Set-PriceFlash {
    # Tints the price cell when the price changed since the last refresh
    param($Cell, [string]$Key, [double]$Price)
    if (-not [bool]$script:Config.PriceFlash -or $Price -le 0) { return }
    $old = $script:LastFlashPrice[$Key]
    $script:LastFlashPrice[$Key] = $Price
    if ($null -eq $old -or [math]::Abs([double]$old - $Price) -lt 1e-9) { return }
    $c = if ($Price -gt [double]$old) { $script:colGreen } else { $script:colRed }
    $Cell.Style.BackColor = Get-BlendColor -A $c -B $script:Pal.Card -T 0.35
    $script:FlashCells.Add([PSCustomObject]@{ Cell = $Cell; Color = $c; Start = (Get-Date) })
    if (-not $script:FlashTimer.Enabled) { $script:FlashTimer.Start() }
}

# ---- own layouts ----
$script:LayoutKeys = @("Layout", "TerminalChartPct", "TerminalShowWatch", "TerminalShowPortfolio", "TerminalBottom", "Theme", "AccentColor", "AccentHex",
                       "UpDownScheme", "ChartType", "ShowVolume", "ShowSma", "ShowRsi", "ShowVwap", "ShowBollinger", "ShowExtended", "Timeframe", "LowerPanel", "MaType", "Opacity", "TopMost")

function Save-UserLayout {
    param([string]$Name)
    $snap = [ordered]@{ Name = $Name }
    foreach ($k in $script:LayoutKeys) { $snap[$k] = $script:Config.$k }
    $list = @(@($script:Config.UserLayouts) | Where-Object { $null -ne $_ -and ([string]$_.Name).ToUpper() -ne $Name.ToUpper() })
    $script:Config.UserLayouts = @($list) + @([PSCustomObject]$snap)
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Set-TransientStatus "Layout '$Name' gespeichert (LAYOUT $($Name.ToUpper()))" 4
}

function Use-UserLayout {
    param([string]$Name)
    $hit = @(@($script:Config.UserLayouts) | Where-Object { $null -ne $_ -and ([string]$_.Name).ToUpper() -eq $Name.ToUpper() })
    if ($hit.Count -eq 0) { return $false }
    $l = $hit[0]
    foreach ($k in $script:LayoutKeys) { if ($null -ne $l.PSObject.Properties[$k] -and $k -ne "Layout") { $script:Config.$k = $l.$k } }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-UpDownColors
    Apply-ThemeToAllControls
    $form.Opacity = [double]$script:Config.Opacity / 100.0
    $form.TopMost = [bool]$script:Config.TopMost
    Apply-Layout ([string]$l.Layout)
    Refresh-AllMarketData -Force
    Update-AllUiViews
    return $true
}

# ---- welcome tour ----
function Show-CompactOptions {
    # v4.8: which parts the Compact / Ticker bar shows (saved immediately)
    param($Owner = $null)
    $p = $script:Pal
    $opts = [ordered]@{ "DayAbs" = "Tagesänderung absolut"; "Ext" = "Vor- / Nachbörse"; "Spark" = "Mini-Chart"; "Market" = "Marktstatus (nur Compact)"; "Depot" = "Depot heute statt Marktstatus (nur Compact)" }
    $cur = @(([string]$script:Config.CompactShow) -split ',' | ForEach-Object { $_.Trim() })
    $dlg = New-DialogForm -Title "Compact / Ticker zeigt" -W (S 360) -H (S 240)
    $y = S 14
    $boxes = @{}
    foreach ($k in $opts.Keys) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.SetBounds((S 16), $y, (S 330), (S 24)); $c.Text = $opts[$k]; $c.Checked = ($cur -contains $k)
        $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $dlg.Controls.Add($c)
        $boxes[$k] = $c
        $y += S 28
    }
    $ok = New-Object System.Windows.Forms.Button
    $ok.SetBounds((S 252), ($y + (S 8)), (S 94), (S 28)); $ok.Text = "OK"
    Style-FlatButton -Btn $ok -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($ok)
    $dlg.AcceptButton = $ok
    $dlg.ClientSize = New-Object System.Drawing.Size((S 360), ($y + (S 50)))
    $res = $dlg.ShowDialog($(if ($null -ne $Owner) { $Owner } else { $form }))
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:Config.CompactShow = (@($opts.Keys | Where-Object { $boxes[$_].Checked }) -join ",")
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        if ([bool]$script:Config.CompactMode) { Apply-Layout ([string]$script:Config.Layout) }
    }
    $dlg.Dispose()
}

function Show-WelcomeTour {
    $pages = @(
        @("Willkommen beim TerminalWidget", "Vom kleinen Ticker bis zum Terminal: mit L (oder dem Layout-Button oben rechts) wechselst du zwischen Ticker, Compact, Standard und Terminal.`r`n`r`nMaus über ein Element halten zeigt eine Erklärung. G öffnet das Glossar, H alle Tastenkürzel."),
        @("Ticker und Watchlist", "Strg+F sucht einen Ticker (Name, Symbol oder ISIN). In der Watchlist: ziehen = Reihenfolge, Entf = löschen (Strg+Z holt ihn zurück), Rechtsklick auf eine Spaltenüberschrift = Spalten ein-/ausblenden, Überschriften ziehen = umsortieren."),
        @("Portfolio", "Positionen im Portfolio-Tab anlegen - beim Speichern wird nach dem Kaufdatum gefragt. Buchungen vom Broker: Historie > Import (CSV). Mehrere Depots: Auswahl oben im Portfolio-Tab. P öffnet die Analyse mit Wertentwicklung, Rendite, Aufteilung und Dividenden."),
        @("Alarme und Handy", "Alarme im Watch-Tab oder per Rechtsklick in den Chart: Kurs, Tag%, Trailing-Stopp, 52W-Hoch, Volumen, Depotwert ... Einstellungen > Handy-Push schickt sie per ntfy oder Telegram aufs Handy, mit Ruhezeit für die Nacht."),
        @("Befehlszeile", "Strg+K öffnet die Befehlszeile wie im Terminal:`r`n  NVDA GP 1Y   Chart     NVDA DES   Beschreibung`r`n  NVDA N   Nachrichten   CAL   Termine   TOP   Gewinner/Verlierer`r`n  NVDA ALRT TRAIL 8   Alarm`r`n`r`nStrg+Alt+W holt das Widget von überall nach vorne (einstellbar).")
    )
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Kurze Tour" -W (S 520) -H (S 300)
    $t = New-Object System.Windows.Forms.Label
    $t.SetBounds((S 20), (S 16), (S 480), (S 28)); $t.Font = $fontUiBold; $t.ForeColor = $p.Accent
    $dlg.Controls.Add($t)
    $b = New-Object System.Windows.Forms.Label
    $b.SetBounds((S 20), (S 52), (S 480), (S 180)); $b.Font = $fontUi
    $dlg.Controls.Add($b)
    $n = New-Object System.Windows.Forms.Label
    $n.SetBounds((S 20), (S 254), (S 120), (S 20)); $n.ForeColor = $p.Muted
    $dlg.Controls.Add($n)
    $next = New-Object System.Windows.Forms.Button
    $next.SetBounds((S 406), (S 248), (S 96), (S 30))
    Style-FlatButton -Btn $next -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $dlg.Controls.Add($next)
    $skip = New-Object System.Windows.Forms.Button
    $skip.SetBounds((S 302), (S 248), (S 96), (S 30)); $skip.Text = "Überspringen"
    Style-FlatButton -Btn $skip -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $skip.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($skip)
    $dlg.CancelButton = $skip
    $script:TourCtl = @{ Dlg = $dlg; T = $t; B = $b; N = $n; Next = $next; Pages = $pages; I = 0 }
    $script:TourCtl.Show = {
        $tc = $script:TourCtl
        $pg = $tc.Pages[$tc.I]
        $tc.T.Text = $pg[0]; $tc.B.Text = $pg[1]
        $tc.N.Text = "{0} / {1}" -f ($tc.I + 1), $tc.Pages.Count
        $tc.Next.Text = if ($tc.I -ge $tc.Pages.Count - 1) { "Los geht's" } else { "Weiter" }
    }
    $next.Add_Click({
        $tc = $script:TourCtl
        if ($tc.I -ge $tc.Pages.Count - 1) { $tc.Dlg.Close(); return }
        $tc.I++
        & $tc.Show
    })
    & $script:TourCtl.Show
    [void]$dlg.ShowDialog($form)
    $script:TourCtl = $null
    $dlg.Dispose()
    $script:Config.FirstRunDone = $true
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
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
    $dlg.Add_HandleCreated($script:DialogChromeHandler)

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
    $nClosed  = & $addNum "Alle Börsen zu: nur alle X Minuten (0 = aus)" 0 120 ([int]$cfg.ClosedPollMinutes) "Spart Abfragen nachts und am Wochenende. F5 aktualisiert jederzeit." "REFRESH"

    & $addSection "Indikatoren"
    $nSmaF  = & $addNum "SMA schnell (auch Bollinger-Periode)" 2 200 ([int]$cfg.SmaFastPeriod) "" "SMA"
    $nSmaS  = & $addNum "SMA langsam" 3 400 ([int]$cfg.SmaSlowPeriod) "" "SMA"
    $nRsi   = & $addNum "RSI-Periode" 2 100 ([int]$cfg.RsiPeriod) "" "RSI"
    $nRsiOb = & $addNum "RSI überkauft ab" 51 99 ([int]$cfg.RsiOverbought) "" "RSI"
    $nRsiOs = & $addNum "RSI überverkauft bis" 1 49 ([int]$cfg.RsiOversold) "" "RSI"
    $cbMa   = & $addCombo "Gleitender Durchschnitt" @("SMA", "EMA") ([string]$cfg.MaType) "SMA = einfacher Durchschnitt, EMA = gewichtet die letzten Kurse stärker" "EMA"
    $cbLow  = & $addCombo "Unteres Feld im Chart" @("RSI", "MACD") ([string]$cfg.LowerPanel) "" "MACD"

    & $addSection "Darstellung"
    $cbTheme  = & $addCombo "Theme" @(Get-ThemeNames) ([string]$cfg.Theme) "" "THEME"
    $cbAccent = & $addCombo "Akzentfarbe" @("Sky", "Amber", "Violet", "Windows", "Eigene") ([string]$cfg.AccentColor) "Eigene = Farbe frei wählen, Windows = Akzentfarbe aus den Windows-Einstellungen"
    $cbLang   = & $addCombo "Sprache" @("Deutsch", "English") $(if ([string]$cfg.Language -eq "EN") { "English" } else { "Deutsch" }) "English: Fenster, Knöpfe, Spalten und Befehle auf Englisch (Meldungen und Glossar bleiben Deutsch). Wirkt nach einem Neustart."
    $chkTop   = & $addCheck "Immer im Vordergrund" ([bool]$cfg.TopMost) "" "PIN"
    $chkTape  = & $addCheck "Laufleiste (Watchlist) im Compact-Layout" ([bool]$cfg.CompactTape)

    # v5.2
    & $addSection "Design"
    $dsMap = @{ "Refined" = "Refined - wie gewohnt, feiner"; "Fresh" = "Fresh - Karten, mehr Luft" }
    $cbStyle = & $addCombo "Stil" @($dsMap["Refined"], $dsMap["Fresh"]) $dsMap[[string]$cfg.UiStyle] "Refined: gleiche Anordnung, feinere Linien und runde Knöpfe. Fresh: abgerundete Karten, mehr Abstand, Akzentlinie unter dem Kopf. Befehl STYLE schaltet um."
    $rdMap = @{ "Compact" = "Kompakt"; "Normal" = "Normal"; "Comfortable" = "Bequem" }
    $cbRows = & $addCombo "Zeilenhöhe der Listen" @("Kompakt", "Normal", "Bequem") $rdMap[[string]$cfg.RowDensity] "Höhe der Zeilen in Watchlist, Portfolio, News und Analyse"
    $tsMap = @{ "Slow" = "Langsam"; "Normal" = "Normal"; "Fast" = "Schnell" }
    $cbTapeSp = & $addCombo "Laufleiste Tempo" @("Langsam", "Normal", "Schnell") $tsMap[[string]$cfg.TapeSpeed] "Geschwindigkeit der Laufleiste im Compact-Layout (Maus darüber = Pause)"
    $chkZebra = & $addCheck "Zebra-Zeilen (jede zweite Zeile heller)" ([bool]$cfg.ZebraRows)
    $chkIcons = & $addCheck "Symbole auf Knöpfen und in Menüs" ([bool]$cfg.UseIcons) $(if ($script:IconFont) { "Schrift: $($script:IconFont)" } else { "Segoe Fluent Icons / MDL2 Assets nicht gefunden - es bleibt beim Text" })

    & $addSection "Benachrichtigungen"
    $chkTray  = & $addCheck "Tray-Hinweis + Ton bei Alarmen" ([bool]$cfg.ShowTrayNotifications)
    $chkOpen  = & $addCheck "Hinweis bei Handelsstart (Börsen im Portfolio / aktiver Ticker)" ([bool]$cfg.NotifyMarketOpen)
    $chkEarn  = & $addCheck "Hinweis am Vortag von Quartalszahlen (Portfolio)" ([bool]$cfg.NotifyEarnings) "" "EARNINGS"
    # v4.3: quiet hours + phone push
    $lQuiet = New-Object System.Windows.Forms.Label
    $lQuiet.Location = New-Object System.Drawing.Point(($lay.X + (S 26)), ($lay.Y + (S 3)))
    $lQuiet.Size = New-Object System.Drawing.Size((S 200), (S 18))
    $lQuiet.Text = "Ruhezeit (kein Ton / Push) von - bis"
    $dlg.Controls.Add($lQuiet)
    $tQFrom = New-Object System.Windows.Forms.TextBox
    $tQFrom.SetBounds(($lay.X + (S 292)), $lay.Y, (S 50), (S 22))
    $tQTo = New-Object System.Windows.Forms.TextBox
    $tQTo.SetBounds(($lay.X + (S 354)), $lay.Y, (S 50), (S 22))
    foreach ($tq in @($tQFrom, $tQTo)) {
        $tq.BackColor = $p.Input; $tq.ForeColor = $p.Text; $tq.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $tq.Font = $fontMono; $tq.MaxLength = 5
        $dlg.Controls.Add($tq)
        Set-DynTip $tq "HH:MM, z. B. 22:00 bis 07:00. Beide leer = keine Ruhezeit." "QUIET"
    }
    Set-DynTip $lQuiet "" "QUIET"
    $tQFrom.Text = [string]$cfg.QuietFrom
    $tQTo.Text = [string]$cfg.QuietTo
    $lay.Y += S 29
    $btnPush = New-Object System.Windows.Forms.Button
    $btnPush.SetBounds(($lay.X + (S 26)), $lay.Y, (S 190), (S 26))
    Style-FlatButton -Btn $btnPush -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnPush.Text = "Handy-Push einrichten ..."
    $dlg.Controls.Add($btnPush)
    $lPushState = New-Object System.Windows.Forms.Label
    $lPushState.SetBounds(($lay.X + (S 224)), ($lay.Y + (S 5)), (S 180), (S 18))
    $lPushState.ForeColor = $p.Muted
    $lPushState.Text = if ([string]$cfg.PushService -eq "Aus") { "aus" } else { "aktiv: " + [string]$cfg.PushService }
    $dlg.Controls.Add($lPushState)
    Set-DynTip $btnPush "" "PUSH"
    $btnPush.Add_Click({
        $sc = $script:SettingsCtl
        if (Show-PushDialog -Owner $sc.Dlg) {
            $sc.PushState.Text = if ([string]$script:Config.PushService -eq "Aus") { "aus" } else { "aktiv: " + [string]$script:Config.PushService }
        }
    })
    $lay.Y += S 32

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
    $btnBar = New-Object System.Windows.Forms.Button
    $btnBar.SetBounds(($lay.X + (S 26)), $lay.Y, (S 230), (S 26))
    Style-FlatButton -Btn $btnBar -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnBar.Text = "Compact / Ticker zeigt ..."
    $btnBar.Add_Click({ Show-CompactOptions -Owner $script:SettingsCtl.Dlg })
    $dlg.Controls.Add($btnBar)
    Set-DynTip $btnBar "Was die schmale Leiste anzeigt: Tagesänderung absolut, Vor-/Nachbörse, Mini-Chart, Marktstatus oder das Depot-Ergebnis von heute" "LAYOUT"
    $lay.Y += S 32

    # v4.6: colours and window
    & $addSection "Farben und Fenster"
    $cbUd     = & $addCombo "Farben für Plus / Minus" @(@((Get-UpDownSchemes).Keys) + @("Eigene")) ([string]$cfg.UpDownScheme) "Farbenblind = Blau / Orange. Eigene = frei wählen." "COLORS"
    $chkArrow = & $addCheck "Pfeile vor Veränderungen anzeigen" ([bool]$cfg.ShowArrows) "Zusätzlich zur Farbe, z. B. für Farbsehschwäche" "COLORS"
    $chkFlash = & $addCheck "Kurs kurz einfärben, wenn er sich ändert" ([bool]$cfg.PriceFlash)
    $chkTrayDepot = & $addCheck "Tray-Symbol in der Farbe des Depot-Tages (statt Ticker)" ([bool]$cfg.TrayFollowsDepot) "Grün / Rot / Grau nach dem heutigen Ergebnis des Depots. Ohne Positionen: aktiver Ticker."
    $chkSnap  = & $addCheck "Fenster am Bildschirmrand einrasten" ([bool]$cfg.SnapToEdges)
    $lHk = New-Object System.Windows.Forms.Label
    $lHk.Location = New-Object System.Drawing.Point(($lay.X + (S 26)), ($lay.Y + (S 3)))
    $lHk.Size = New-Object System.Drawing.Size((S 258), (S 18))
    $lHk.Text = "Globales Tastenkürzel (zeigen / verstecken)"
    $dlg.Controls.Add($lHk)
    $tHk = New-Object System.Windows.Forms.TextBox
    $tHk.SetBounds(($lay.X + (S 292)), $lay.Y, (S 112), (S 22))
    $tHk.BackColor = $p.Input; $tHk.ForeColor = $p.Text; $tHk.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tHk.Font = $fontMono; $tHk.Text = [string]$cfg.GlobalHotkey
    $dlg.Controls.Add($tHk)
    Set-DynTip $tHk "Funktioniert auch, wenn ein anderes Programm vorne ist. Z. B. Ctrl+Alt+W, Win+F9. Leer = aus." "HOTKEY"
    Set-DynTip $lHk "" "HOTKEY"
    $lay.Y += S 29
    $script:NewColors = @{ Up = [string]$cfg.UpColor; Down = [string]$cfg.DownColor; Accent = [string]$cfg.AccentHex }
    $pickColor = {
        param([string]$Start)
        $cd = New-Object System.Windows.Forms.ColorDialog
        $cd.FullOpen = $true
        $rgb = ConvertFrom-HexColor $Start
        if ($null -ne $rgb) { $cd.Color = [System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]) }
        $hex = ""
        if ($cd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $hex = ConvertTo-HexColor $cd.Color.R $cd.Color.G $cd.Color.B }
        $cd.Dispose()
        return $hex
    }
    $script:PickColor = $pickColor
    $cbUd.Add_SelectionChangeCommitted({
        param($sender, $e)
        if ([string]$sender.SelectedItem -ne "Eigene") { return }
        $u = & $script:PickColor $script:NewColors.Up
        if (-not $u) { return }
        $d = & $script:PickColor $script:NewColors.Down
        if (-not $d) { return }
        $script:NewColors.Up = $u; $script:NewColors.Down = $d
    })
    $cbAccent.Add_SelectionChangeCommitted({
        param($sender, $e)
        if ([string]$sender.SelectedItem -ne "Eigene") { return }
        $a = & $script:PickColor $script:NewColors.Accent
        if ($a) { $script:NewColors.Accent = $a }
    })

    # v4.9: fonts, window frame, news
    & $addSection "Schrift und Rahmen"
    $monoOffered = @(Get-MonoFontNames | Where-Object { $_ -eq "Consolas" -or $script:InstalledFonts -contains $_ })
    $cbMono  = & $addCombo "Schrift für Zahlen (ab Neustart)" $monoOffered ([string]$cfg.MonoFont) "Feste Zeichenbreite: Ziffern stehen untereinander. Cascadia Mono kommt mit Windows 11 / Windows Terminal."
    $scaleItems = @(Get-FontScaleSteps | ForEach-Object { "$_ %" })
    $cbScale = & $addCombo "Schriftgröße Listen + Chart (ab Neustart)" $scaleItems ("{0} %" -f [int]$cfg.FontScale) "Vergrößert Tabellen (Zeilenhöhe wächst mit) und Chart-Beschriftung. Knöpfe und Eingabefelder bleiben gleich groß, damit nichts abgeschnitten wird."
    $chkAlignR = & $addCheck "Zahlen rechtsbündig (Watchlist, Portfolio)" ([bool]$cfg.AlignNumbersRight) "Ziffern bleiben beim Aktualisieren an ihrem Platz"
    $chkRound  = & $addCheck "Abgerundete Fensterecken (Windows 11)" ([bool]$cfg.RoundCorners)

    & $addSection "Nachrichten (F4)"
    $nNewsMin  = & $addNum "Neu laden alle (Minuten)" 5 240 ([int]$cfg.NewsRefreshMinutes) "Eine Abfrage je Ticker in Depot und Watchlist (max. 40). Sind alle Börsen zu, halb so oft." "" 5
    $nNewsMove = & $addNum "Ticker markieren ab Tagesbewegung (%)" 0 50 ([int]$cfg.NewsMoveThreshold) "Zeigt bei der neuesten Meldung, dass sich der Ticker heute stark bewegt (0 = aus)"
    # v4.9.5: keyword alerts + muted sources
    $lKw = New-Object System.Windows.Forms.Label
    $lKw.Location = New-Object System.Drawing.Point(($lay.X + (S 26)), ($lay.Y + (S 3)))
    $lKw.Size = New-Object System.Drawing.Size((S 140), (S 18))
    $lKw.Text = "Alarm-Wörter"
    $dlg.Controls.Add($lKw)
    $tKw = New-Object System.Windows.Forms.TextBox
    $tKw.SetBounds(($lay.X + (S 170)), $lay.Y, (S 234), (S 22))
    $tKw.BackColor = $p.Input; $tKw.ForeColor = $p.Text; $tKw.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tKw.Font = $fontMono; $tKw.Text = [string]$cfg.NewsKeywords
    $dlg.Controls.Add($tKw)
    $kwTip = "Kommagetrennt, z. B.: downgrade, gewinnwarnung, übernahme, profit warning. Kommt eine Schlagzeile mit so einem Wort zu einem Ticker im Depot, gibt es einen Hinweis (und Handy-Push, falls eingerichtet). Leer = aus."
    Set-DynTip $tKw $kwTip; Set-DynTip $lKw $kwTip
    $lay.Y += S 29
    $chkKwWatch = & $addCheck "Alarm-Wörter auch für Watchlist-Ticker" ([bool]$cfg.NewsKeywordWatch)
    $script:NewMuted = @($cfg.NewsMuted | Where-Object { $_ })
    $btnMuted = New-Object System.Windows.Forms.Button
    $btnMuted.SetBounds(($lay.X + (S 26)), $lay.Y, (S 230), (S 26))
    Style-FlatButton -Btn $btnMuted -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnMuted.Text = "{0} ({1})" -f "Ausgeblendete Quellen zeigen", @($script:NewMuted).Count
    $btnMuted.Enabled = (@($script:NewMuted).Count -gt 0)
    Set-DynTip $btnMuted ("Ausgeblendet: " + $(if (@($script:NewMuted).Count -gt 0) { @($script:NewMuted) -join ", " } else { "keine" }) + ". Klick = alle wieder zeigen. Einzelne Quellen: Rechtsklick in der News-Liste.")
    $btnMuted.Add_Click({
        param($sender, $e)
        $script:NewMuted = @()
        $sender.Text = "{0} (0)" -f (Tr "Ausgeblendete Quellen zeigen")
        $sender.Enabled = $false
    })
    $dlg.Controls.Add($btnMuted)
    $lay.Y += S 32

    & $addSection "Erklärungen (Maus darüber)"
    $modes = Get-TooltipModes
    $cbTip = & $addCombo "Ausführlichkeit" @($modes.Values) ([string]$modes[[string]$cfg.TooltipMode]) "" "TOOLTIPS"
    $nTipDelay = & $addNum "Verzögerung (Millisekunden)" 0 3000 ([int]$cfg.TooltipDelayMs) "Wie lange die Maus stillstehen muss, bis der Hinweis erscheint" "TOOLTIPS" 100
    $chkHover  = & $addCheck "Infokarte, wenn die Maus auf einem Ticker ruht" ([bool]$cfg.HoverCards) "Watchlist und Portfolio: Kurs, Tagesspanne, 52-Wochen-Balken, 5-Tage-Verlauf, Position, nächste Termine"
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
    # v5.0: search - matching settings light up, the rest fades
    $lSearch = New-Object System.Windows.Forms.Label
    $lSearch.SetBounds((S 384), ($by + (S 6)), (S 52), (S 18)); $lSearch.Text = "Suchen:"
    $dlg.Controls.Add($lSearch)
    $tSearch = New-Object System.Windows.Forms.TextBox
    $tSearch.SetBounds((S 438), ($by + (S 2)), (S 200), (S 24))
    $tSearch.Name = "tSettingsSearch"
    $tSearch.BackColor = $p.Input; $tSearch.ForeColor = $p.Text; $tSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($tSearch)
    Set-DynTip $tSearch "Einstellung suchen, z. B. 'schrift', 'push', 'news' - Treffer werden hervorgehoben"
    $script:SetSearchColors = @{}
    foreach ($sc0 in $dlg.Controls) {
        if (($sc0 -is [System.Windows.Forms.Label] -or $sc0 -is [System.Windows.Forms.CheckBox] -or $sc0 -is [System.Windows.Forms.Button]) -and $sc0.Text) { $script:SetSearchColors[$sc0] = $sc0.ForeColor }
    }
    $script:SetSearchColors.Remove($lSearch)
    $tSearch.Add_TextChanged({
        param($sender, $e)
        $qq = $sender.Text
        $hits = 0
        foreach ($c0 in @($script:SetSearchColors.Keys)) {
            if ($c0.IsDisposed) { continue }
            if (-not $qq.Trim()) { $c0.ForeColor = $script:SetSearchColors[$c0]; continue }
            $tipT = ""
            try { $tipT = [string]$toolTip.GetToolTip($c0) } catch { }
            if (Test-SettingMatch -Text ($c0.Text + " " + $tipT) -Query $qq) { $c0.ForeColor = $script:Pal.Accent; $hits++ } else { $c0.ForeColor = $script:Pal.Border }
        }
        $script:SettingsSearchHits = $hits
    })
    # v4.5: restore / export / import / portable
    $mkDataBtn = {
        param([string]$T, [int]$X, [string]$Tip, [scriptblock]$Act)
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds($X, ($by + (S 36)), (S 130), (S 28))
        Style-FlatButton -Btn $b -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
        $b.Text = $T
        $b.Add_Click($Act)
        $dlg.Controls.Add($b)
        Set-DynTip $b $Tip
    }
    & $mkDataBtn "Wiederherstellen ..." (S 14) "Ein Backup zurückspielen (täglich wird automatisch gesichert)" { $script:SettingsAfter = { Show-RestoreDialog }; $script:SettingsCtl.Dlg.Close() }
    & $mkDataBtn "Daten exportieren ..." (S 150) "Alle Daten als ZIP sichern (z. B. für einen anderen PC)" { Export-DataZip }
    & $mkDataBtn "Daten importieren ..." (S 286) "Einen ZIP-Export einlesen (ersetzt alle Daten, vorher Backup)" { $script:SettingsAfter = { Import-DataZip }; $script:SettingsCtl.Dlg.Close() }
    & $mkDataBtn $(if ($script:IsPortable) { "Portabel beenden ..." } else { "Portabel machen ..." }) (S 422) $(if ($script:IsPortable) { "Daten liegen im Programmordner (data). Zurück nach %LOCALAPPDATA%." } else { "Daten in den Programmordner (data) verschieben, z. B. für einen USB-Stick" }) { $script:SettingsAfter = { Switch-PortableMode }; $script:SettingsCtl.Dlg.Close() }
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
    $script:SettingsCtl = @{ Dlg = $dlg; SmaF = $nSmaF; SmaS = $nSmaS; Slow = $nSlow; Refresh = $nRefresh; PushState = $lPushState; QFrom = $tQFrom; QTo = $tQTo }
    $btnOk.Add_Click({
        $sc = $script:SettingsCtl
        if ($sc.SmaF.Value -ge $sc.SmaS.Value) {
            [System.Windows.Forms.MessageBox]::Show($sc.Dlg, "SMA schnell muss kleiner als SMA langsam sein.", "Einstellungen",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        if ($sc.Slow.Value -lt $sc.Refresh.Value) { $sc.Slow.Value = $sc.Refresh.Value }
        foreach ($tq in @($sc.QFrom, $sc.QTo)) {
            $tv = $tq.Text.Trim()
            if ($tv -and $tv -notmatch '^([01]?\d|2[0-3]):[0-5]\d$') {
                [System.Windows.Forms.MessageBox]::Show($sc.Dlg, "Ruhezeit bitte als HH:MM eingeben (z. B. 22:00), oder leer lassen.", "Einstellungen",
                    [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                $tq.Focus() | Out-Null
                return
            }
        }
        $sc.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $sc.Dlg.Close()
    })
    $dlg.Controls.Add($btnOk)
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel
    $dlg.ClientSize = New-Object System.Drawing.Size((S 860), ($by + (S 78)))

    $script:SettingsAfter = $null
    Apply-Language $dlg
    $res = $dlg.ShowDialog($form)
    $script:SettingsCtl = $null
    # v4.5: data actions run after the settings window is gone (changes there are discarded)
    $after = $script:SettingsAfter
    $script:SettingsAfter = $null
    if ($null -ne $after) { $dlg.Dispose(); & $after; return }
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) { $dlg.Dispose(); return }

    $needRefresh = ([int]$nSmaF.Value -ne [int]$cfg.SmaFastPeriod) -or ([int]$nSmaS.Value -ne [int]$cfg.SmaSlowPeriod) -or ([int]$nRsi.Value -ne [int]$cfg.RsiPeriod)
    $cfg.RefreshSeconds        = [int]$nRefresh.Value
    $cfg.SlowRefreshSeconds    = [int]$nSlow.Value
    $cfg.HttpTimeoutSeconds    = [int]$nHttp.Value
    $cfg.ClosedPollMinutes     = [int]$nClosed.Value
    $cfg.SmaFastPeriod         = [int]$nSmaF.Value
    $cfg.SmaSlowPeriod         = [int]$nSmaS.Value
    $cfg.RsiPeriod             = [int]$nRsi.Value
    $cfg.RsiOverbought         = [int]$nRsiOb.Value
    $cfg.RsiOversold           = [int]$nRsiOs.Value
    $cfg.Theme                 = [string]$cbTheme.SelectedItem
    $cfg.AccentColor           = [string]$cbAccent.SelectedItem
    $cfg.TopMost               = [bool]$chkTop.Checked
    $cfg.CompactTape           = [bool]$chkTape.Checked
    $cfg.UiStyle               = if ([string]$cbStyle.SelectedItem -like "Fresh*") { "Fresh" } else { "Refined" }
    $cfg.RowDensity            = switch ([string]$cbRows.SelectedItem) { "Kompakt" { "Compact" } "Bequem" { "Comfortable" } default { "Normal" } }
    $cfg.TapeSpeed             = switch ([string]$cbTapeSp.SelectedItem) { "Langsam" { "Slow" } "Schnell" { "Fast" } default { "Normal" } }
    $cfg.ZebraRows             = [bool]$chkZebra.Checked
    $cfg.UseIcons              = [bool]$chkIcons.Checked
    $cfg.ShowTrayNotifications = [bool]$chkTray.Checked
    $cfg.NotifyMarketOpen      = [bool]$chkOpen.Checked
    $cfg.NotifyEarnings        = [bool]$chkEarn.Checked
    $cfg.QuietFrom             = $tQFrom.Text.Trim()
    $cfg.QuietTo               = $tQTo.Text.Trim()
    # v4.0
    $newLayout                 = [string]$cbLayout.SelectedItem
    $cfg.Opacity               = [int]$nOpacity.Value
    $cfg.TerminalShowWatch     = [bool]$chkTWatch.Checked
    $cfg.TerminalShowPortfolio = [bool]$chkTPort.Checked
    $cfg.TerminalChartPct      = [int]$nTChart.Value
    foreach ($mk in $modes.Keys) { if ($modes[$mk] -eq [string]$cbTip.SelectedItem) { $cfg.TooltipMode = $mk } }
    $cfg.TooltipDelayMs        = [int]$nTipDelay.Value
    $cfg.HoverCards            = [bool]$chkHover.Checked
    $newLang = if ([string]$cbLang.SelectedItem -eq "English") { "EN" } else { "DE" }
    $langChanged = ($newLang -ne [string]$cfg.Language)
    $cfg.Language              = $newLang
    # v4.6
    if ([string]$cbMa.SelectedItem -ne [string]$cfg.MaType -or [string]$cbLow.SelectedItem -ne [string]$cfg.LowerPanel) { $needRefresh = $true }
    $cfg.MaType                = [string]$cbMa.SelectedItem
    $cfg.LowerPanel            = [string]$cbLow.SelectedItem
    $cfg.UpDownScheme          = [string]$cbUd.SelectedItem
    if ($cfg.UpDownScheme -eq "Eigene" -and -not ($script:NewColors.Up -and $script:NewColors.Down)) { $cfg.UpDownScheme = "Standard" }
    $cfg.UpColor               = [string]$script:NewColors.Up
    $cfg.DownColor             = [string]$script:NewColors.Down
    $cfg.AccentHex             = [string]$script:NewColors.Accent
    if ($cfg.AccentColor -eq "Eigene" -and -not $cfg.AccentHex) { $cfg.AccentColor = "Sky" }
    $cfg.ShowArrows            = [bool]$chkArrow.Checked
    $cfg.PriceFlash            = [bool]$chkFlash.Checked
    $cfg.TrayFollowsDepot      = [bool]$chkTrayDepot.Checked
    $cfg.SnapToEdges           = [bool]$chkSnap.Checked
    # v4.9
    $newMono  = [string]$cbMono.SelectedItem
    $newScale = [int](([string]$cbScale.SelectedItem) -replace '[^0-9]', '')
    $fontChanged = ($newMono -ne [string]$cfg.MonoFont) -or ($newScale -ne [int]$cfg.FontScale)
    $cfg.MonoFont              = $newMono
    $cfg.FontScale             = $newScale
    $cfg.AlignNumbersRight     = [bool]$chkAlignR.Checked
    $cfg.RoundCorners          = [bool]$chkRound.Checked
    $newsMinChanged = ([int]$nNewsMin.Value -ne [int]$cfg.NewsRefreshMinutes)
    $cfg.NewsRefreshMinutes    = [int]$nNewsMin.Value
    $cfg.NewsMoveThreshold     = [int]$nNewsMove.Value
    $cfg.NewsKeywords          = (@(ConvertTo-KeywordList $tKw.Text) -join ", ")
    $cfg.NewsKeywordWatch      = [bool]$chkKwWatch.Checked
    $cfg.NewsMuted             = @($script:NewMuted)
    $hkNew = $tHk.Text.Trim()
    $hkChanged = ($hkNew -ne [string]$cfg.GlobalHotkey)
    if (-not $hkNew -or $null -ne (ConvertFrom-HotkeyText $hkNew)) { $cfg.GlobalHotkey = $hkNew }
    else { Set-TransientStatus "Tastenkürzel '$hkNew' nicht erkannt - z. B. Ctrl+Alt+W" 6; $hkChanged = $false }
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
    $btnToggleRsi.Text = if ([string]$cfg.LowerPanel -eq "MACD") { "MACD" } else { "RSI-$($cfg.RsiPeriod)" }
    $btnToggleSma.Text = [string]$cfg.MaType
    Set-Tip $btnToggleSma "Gleitende Durchschnitte SMA $($cfg.SmaFastPeriod)/$($cfg.SmaSlowPeriod) (Taste M)" "SMA"
    Apply-TooltipMode
    Update-ChartControlsLayout
    Apply-NumberAlignment
    if ($newsMinChanged) { $script:NextNewsLoad = (Get-Date).AddMinutes([int]$cfg.NewsRefreshMinutes) }
    Save-JsonState -Path $script:ConfigPath -Data $cfg
    Apply-ThemeToAllControls
    Apply-Layout $newLayout
    if ($needRefresh) { Refresh-AllMarketData -Force }
    Set-TransientStatus "Einstellungen gespeichert" 3
    if ($langChanged -and (Confirm-Action -Text "Die Sprache wirkt nach einem Neustart. Jetzt neu starten? / Restart now to switch the language?" -Title "Sprache / Language")) {
        Restart-Widget
        return
    }
    if (-not $langChanged -and $fontChanged -and -not $script:SmokeMode -and (Confirm-Action -Text (Tr "Schrift und Schriftgröße wirken nach einem Neustart. Jetzt neu starten?") -Title (Tr "Schrift"))) {
        Restart-Widget
        return
    }
    if ($hkChanged) {
        $hm = Register-GlobalHotkey
        if ($hm -and $hm -ne "aus") { Set-TransientStatus "Tastenkürzel: $hm" 6 }
    }
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

# v5.0: the help outgrew a message box - scrollable, resizable window
function Show-HelpTextDialog {
    param([string]$Title, [string]$Text)
    $p = $script:Pal
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dlg = New-DialogForm -Title $Title -W ([math]::Min((S 640), $wa.Width - 40)) -H ([math]::Min((S 640), $wa.Height - 60))
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 420), (S 300))
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.WordWrap = $false
    $tb.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $tb.BackColor = $p.BodyBg; $tb.ForeColor = $p.Text; $tb.Font = $fontMono
    $tb.Text = ($Text -replace "`r?`n", "`r`n")
    $tb.SetBounds((S 12), (S 10), ($dlg.ClientSize.Width - (S 24)), ($dlg.ClientSize.Height - (S 56)))
    $tb.Anchor = [System.Windows.Forms.AnchorStyles]"Top, Bottom, Left, Right"
    $dlg.Controls.Add($tb)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Schließen"
    $ok.SetBounds(($dlg.ClientSize.Width - (S 112)), ($dlg.ClientSize.Height - (S 38)), (S 100), (S 28))
    $ok.Anchor = [System.Windows.Forms.AnchorStyles]"Bottom, Right"
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Style-FlatButton -Btn $ok -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $dlg.Controls.Add($ok)
    $dlg.AcceptButton = $ok; $dlg.CancelButton = $ok
    $dlg.Add_Shown({ param($sender, $e) $sender.ActiveControl = $sender.AcceptButton })
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
}

function Show-ShortcutHelp {
    if ([string]$script:Config.Language -eq "EN") {
        $txtEn = @"
Keyboard shortcuts

F1 - F4         Chart / Portfolio / Watch & alerts / News
F5              Refresh now
Ctrl+F          Search ticker
Ctrl+K          Command line (also numpad /)
Ctrl+Z          Undo the last deletion (10 seconds)
Ctrl+Y          Redo (30 seconds)
Ctrl+C          Copy the whole list as a table
F9              Privacy mode (hide amounts; Fn+F9 on many laptops)
Shift+F2/F3/F4  Terminal layout: list as a full page (Esc = back)
Ctrl+Alt+W      Show / hide the widget from anywhere
Left / Right    Previous / next watchlist ticker
1 - 6           Range 1D / 5D / 1M / 3M / 6M / 1Y
F11             Fullscreen chart

K  line / candles      V  volume
M  SMA/EMA             A  VWAP
B  Bollinger           R  RSI / MACD
E  pre/post market     W  currency
T  theme               C  compact on/off
L  next layout         G  glossary
P  portfolio analysis  S  settings
H  this help           Z  reset zoom   X  compare
Y  log scale           (diamond in the chart = ex-dividend)

Command line: NVDA, NVDA GP 1Y, NVDA DES, NVDA N, NVDA DVD,
NVDA EE, NVDA ALRT TRAIL 8, NVDA WL, PORT, ANA, DVD, CAL, TOP,
NEWS, NEWS DEPOT, NEWS WATCH, NEWS NVDA,
FX, LOG, REP, TF 3M, LAYOUT TERMINAL, LAYOUT SAVE <name>,
IND MACD, PF <depot>, IMP, BAK, SET, PUSH, ABOUT, TOUR

Right-click a column header = choose columns, drag = reorder.
Hover over controls for explanations (glossary is German).

New in 5.0
K               Line / candles / Heikin-Ashi
D               Draw a trend line (right-click chart > Draw:
                horizontal line, Fibonacci, alert on a line)
X               Compare - up to 3 tickers (right-click a ticker)
Terminal        Drag the dividers between chart and lists,
                double-click = default sizes
Watchlist       Group drop-down next to the title,
                right-click a ticker > To group
Hover card      Rest the mouse on a ticker
Settings        "Search:" at the bottom lights up matches
Portfolio (v)   Cash account, savings plans
P               Risk, target weights (rebalancing), heatmap
Commands        CASH SPAR REBAL RISK HEAT DRAW H/T/F FULL PRIV

New in 5.1
W               Auto (each price + chart in the ticker's currency,
                depot stays in the base currency) / EUR / USD / CHF / GBP
NVDA TA         Ticker analysis: signals, support / resistance,
                fundamentals vs. your tickers of the same sector
                (also right-click a ticker or the chart)
P               Beitrag (contribution, dividends, scenario),
                Vergleich (indices, rolling 12M, sectors vs. MSCI World)
"@
        Show-HelpTextDialog -Title "Help - $($script:AppTitle)" -Text $txtEn
        return
    }
    $txt = @"
Tastenkürzel

F1 - F4         Chart / Portfolio / Watch & Alarm / News
F5              Jetzt aktualisieren
Ctrl+F          Ticker suchen
Links / Rechts  Vorheriger / nächster Watchlist-Ticker
Mausrad (Chart) Zeitraum wechseln
1 - 6           Zeitraum 1D / 5D / 1M / 3M / 6M / 1Y
F11             Chart im Vollbild (auch Doppelklick auf Chart)

Y  Log-Skala an/aus     (Raute im Chart = Ex-Dividende)
K  Linie / Kerzen       V  Volumen
M  SMA                  A  VWAP
B  Bollinger            R  RSI
E  Vor-/Nachbörse      W  Währung (EUR/USD/CHF/GBP)
T  Theme                C  Compact an/aus
L  Nächstes Layout     G  Glossar (Begriffe)
P  Portfolio-Analyse (Wertentwicklung, Rendite,
   Aufteilung, Dividenden, Kaufdaten nachtragen)
S  Einstellungen        H  Diese Hilfe
Z  Zoom zurücksetzen   X  Vergleich an/aus
Esc  Messung / Popups / Vollbild schließen

Layouts (Button rechts oben oder L):
Ticker    nur Kurs + Mini-Chart, rahmenlos
Compact   Leiste mit Marktstatus und Laufband
Standard  Fenster mit Tabs
Terminal  Chart oben, Watchlist + Portfolio darunter
          (oder die News: F4 / NEWS)
          Tab einer sichtbaren Liste nochmal klicken
          (oder Shift+F2/F3/F4) = Liste als ganze Seite,
          F1 / Esc = zurück

F9 (am Laptop oft Fn+F9) oder Augen-Knopf im Portfolio:
Privat-Modus (Beträge aus), Ctrl+Y: wiederholen,
Ctrl+C in einer Liste: ganze Tabelle kopieren.
Rechtsklick auf einen Ticker (Watchlist / Portfolio):
Chart, Alarm, Kauf buchen, News, Vergleich, DES.
Rechtsklick auf einen Alarm: pausieren (1 h / 4 h / morgen).
Punkt links von der Statuszeile: grün = Daten ok,
gelb = Pause / veraltet, rot = keine Verbindung.

News (F4): Meldungen zu Depot und Watchlist, neue fett,
die Zahl am Tab = ungelesen. Doppelklick = Artikel,
Klick auf den Ticker = Ticker öffnen. NEWS DEPOT /
NEWS WATCH / NEWS NVDA filtern, NVDA N = Einzelfenster.

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
Ticker in Orange = Quartalszahlen in den nächsten 7 Tagen

Befehlszeile (Strg+K oder Num-/):
NVDA          Ticker öffnen      NVDA GP 1Y  Chart + Zeitraum
NVDA DES      Beschreibung       NVDA N      Nachrichten
NVDA DVD      Dividenden         NVDA EE     Termine
NVDA ALRT TRAIL 8 / >= 150 / TAG- 3 / 52H / VOL 2
NVDA WL / CMP / TX   Watchlist / Vergleich / Transaktion
PORT  ANA  DVD  CAL  TOP  FX  LOG  REP  TF 3M  LAYOUT TERMINAL
THEME OLED  SET  PUSH  GLOS  ABOUT  PF <Depot>  IMP  BAK  SCALE LOG
IND MACD/EMA  LAYOUT SAVE <Name>  CT (Durchklicken)  TOUR

Strg+Z         Löschen rückgängig (10 Sekunden)
Strg+Alt+W     Widget von überall zeigen / verstecken
Rechtsklick auf Spaltenkopf = Spalten wählen, Kopf ziehen = Reihenfolge

Alarme: Kurs, Tag%, RSI, SMA, Trailing-Stopp, EK%, 52W-Hoch/-Tief,
Volumen-Spitze, Depotwert und Depot-Tag%. "Verlauf" zeigt alle
Treffer. Handy-Push (ntfy/Telegram) und Ruhezeit: Einstellungen.

Neu in 5.0
K               Linie / Kerzen / Heikin-Ashi
D               Trendlinie zeichnen (Rechtsklick Chart > Zeichnen:
                Horizontale, Fibonacci, Alarm auf eine Linie)
X               Vergleich - bis zu 3 Ticker (Rechtsklick auf Ticker)
Terminal        Trennlinien zwischen Chart und Listen ziehen,
                Doppelklick = Standardgrößen
Watchlist       Gruppen-Auswahl neben dem Titel,
                Rechtsklick auf Ticker > Zu Gruppe
Infokarte       Maus auf einem Ticker ruhen lassen
Einstellungen   "Suchen:" unten hebt passende Optionen hervor
Portfolio (v)   Cash-Konto, Sparpläne
P               Risiko, Ziel-Gewichte (Rebalancing), Heatmap
Befehle         CASH SPAR REBAL RISK HEAT DRAW H/T/F FULL PRIV

Neu in 5.1
W               Auto (jeder Kurs + Chart in der Währung des Tickers,
                Depot bleibt in der Basiswährung) / EUR / USD / CHF / GBP
NVDA TA         Ticker-Analyse: Signale, Unterstützung / Widerstand,
                Kennzahlen gegen deine Ticker aus derselben Branche
                (auch Rechtsklick auf Ticker oder Chart)
P               Beitrag (je Position, Dividenden, Szenario),
                Vergleich (Indizes, rollierend 12 M, Sektoren vs. MSCI World)
"@
    Show-HelpTextDialog -Title "Hilfe - $($script:AppTitle)" -Text $txt
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
        $idx = if ([bool]$script:Config.AutoCurrency) { 0 } else { $lstCurrencyDropdown.Items.IndexOf($script:Config.Currency) }
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
        $pcc = Get-PriceCurrency $sym
        $p = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $pcc
        [System.Windows.Forms.Clipboard]::SetText(("{0}: {1:N2} {2}" -f $sym, $p, $pcc))
    }
})
$cmiTa.Add_Click({ Show-TickerAnalysis ([string]$script:Config.ActiveTicker) })
$cmiAddWatch.Add_Click({
    [void](Add-SymbolToWatchlist -RawSymbol $script:Config.ActiveTicker)
})
$cmiExportCsv.Add_Click({ $btnExportCsv.PerformClick() })
$cmiFullscreen.Add_Click({ Toggle-ChartFullscreen })

# ==============================================================================
# v5.0 Stage B: drawings in the chart (horizontal line, trend line, Fibonacci)
# saved per ticker in drawings.json as (time, price in the ticker's currency),
# so they survive zoom, timeframe and display currency changes.
# ==============================================================================
$script:DrawingsPath = Join-Path $script:DataDir "drawings.json"
$script:Drawings = @{}
$script:DrawMode = ""
$script:DrawPending = $null
$script:DrawMouse = $null
$script:CtxDrawing = $null
$script:DrawingsSig = ""
function Read-Drawings {
    $script:Drawings = @{}
    $raw = Load-JsonState -Path $script:DrawingsPath -DefaultValue $null
    if ($null -eq $raw) { return }
    foreach ($pp in $raw.PSObject.Properties) {
        $l = New-Object System.Collections.Generic.List[object]
        foreach ($d in @($pp.Value)) {
            if ($null -eq $d -or -not $d.Kind) { continue }
            $l.Add([PSCustomObject]@{ Id = [string]$d.Id; Kind = [string]$d.Kind; T1 = [long]$d.T1; P1 = [double]$d.P1; T2 = [long]$d.T2; P2 = [double]$d.P2; Cur = [string]$d.Cur })
        }
        if ($l.Count -gt 0) { $script:Drawings[([string]$pp.Name).ToUpper()] = $l }
    }
    Update-DrawingsSig
}
function Save-Drawings {
    $o = [ordered]@{}
    foreach ($k in @($script:Drawings.Keys | Sort-Object)) { if ($script:Drawings[$k].Count -gt 0) { $o[$k] = $script:Drawings[$k].ToArray() } }
    Save-JsonState -Path $script:DrawingsPath -Data ([PSCustomObject]$o)
    Update-DrawingsSig
}
function Update-DrawingsSig {
    $dl = $script:Drawings[([string]$script:Config.ActiveTicker).ToUpper()]
    $script:DrawingsSig = if ($null -eq $dl) { "0" } else { "{0}|{1}" -f $dl.Count, (@($dl | ForEach-Object { $_.Id }) -join ",") }
}

function Set-DrawMode {
    param([string]$Mode)
    $script:DrawMode = $Mode
    $script:DrawPending = $null
    $script:DrawMouse = $null
    $cur = if ($Mode) { [System.Windows.Forms.Cursors]::Cross } else { [System.Windows.Forms.Cursors]::Default }
    $pnlChartCanvas.Cursor = $cur
    if ($null -ne $script:FsCanvas -and -not $script:FsCanvas.IsDisposed) { $script:FsCanvas.Cursor = $cur }
    switch ($Mode) {
        "H" { Set-TransientStatus "Horizontale Linie: in den Chart klicken (Esc = abbrechen)" 8 }
        "T" { Set-TransientStatus "Trendlinie: Startpunkt klicken, dann Endpunkt (Esc = abbrechen)" 8 }
        "F" { Set-TransientStatus "Fibonacci: Anfang der Bewegung klicken, dann das Ende (Esc = abbrechen)" 8 }
    }
    $pnlChartCanvas.Invalidate()
}

function Get-ChartPointAt {
    # Mouse position -> @{ T (ms); P (display currency) } on the visible chart, or $null
    param($L, [int]$X, [int]$Y)
    $pr = $L.PriceRect
    $my = $Y - [int]$L.OffsetY
    if ($L.N -lt 2 -or $X -lt $pr.Left -or $X -gt $pr.Right -or $my -lt $pr.Top -or $my -gt $pr.Bottom) { return $null }
    $ts = [long[]]@($L.Series | ForEach-Object { [long]$_.Ts })
    $fi = ($X - $pr.Left) / [double]$pr.Width * ($L.N - 1)
    $p = Get-PriceFromFrac (($pr.Bottom - $my) / [double]$pr.Height) ([double]$L.MinP) ([double]$L.SpanP) ([bool]$L.LogScale)
    return [PSCustomObject]@{ T = (Get-TsAtFracIndex -BarTs $ts -Idx $fi); P = $p }
}

function Get-DrawingPixels {
    # Drawing -> pixel coordinates on a chart layout (display currency)
    param($L, $D)
    $pr = $L.PriceRect
    $ts = [long[]]@($L.Series | ForEach-Object { [long]$_.Ts })
    $fx = Convert-CurrencyValue -Amount 1.0 -FromCurrency ([string]$D.Cur) -ToCurrency ([string]$script:ChartCur)
    $toY = { param([double]$P) $pr.Bottom - ((Get-PriceFrac ($P * $fx) ([double]$L.MinP) ([double]$L.SpanP) ([bool]$L.LogScale)) * $pr.Height) }
    $toX = { param([long]$T) $pr.Left + ((Get-FracIndexAtTs -BarTs $ts -Ts $T) / [double]([math]::Max(1, $L.N - 1))) * $pr.Width }
    return [PSCustomObject]@{ X1 = (& $toX $D.T1); Y1 = (& $toY $D.P1); X2 = $(if ($D.Kind -eq "H") { $pr.Right } else { & $toX $D.T2 }); Y2 = $(if ($D.Kind -eq "H") { & $toY $D.P1 } else { & $toY $D.P2 }); Fx = $fx }
}

function Find-DrawingAt {
    param($L, [int]$X, [int]$Y, [int]$Tol = 6)
    $dl = $script:Drawings[([string]$script:Config.ActiveTicker).ToUpper()]
    if ($null -eq $dl -or $L.N -lt 2) { return $null }
    $my = $Y - [int]$L.OffsetY
    $best = $null; $bd = [double](S $Tol)
    foreach ($d in $dl) {
        $px = Get-DrawingPixels -L $L -D $d
        $dist = switch ($d.Kind) {
            "H" { [math]::Abs($my - $px.Y1) }
            "T" { Get-PointLineDistance -X $X -Y $my -X1 $px.X1 -Y1 $px.Y1 -X2 $px.X2 -Y2 $px.Y2 -Ray $true }
            default {
                $m = [double]::MaxValue
                foreach ($lv in (Get-FibLevels -P1 $d.P1 -P2 $d.P2)) {
                    $yy = $L.PriceRect.Bottom - ((Get-PriceFrac ($lv.Price * $px.Fx) ([double]$L.MinP) ([double]$L.SpanP) ([bool]$L.LogScale)) * $L.PriceRect.Height)
                    if ($X -ge [math]::Min($px.X1, $px.X2) - 4) { $m = [math]::Min($m, [math]::Abs($my - $yy)) }
                }
                $m
            }
        }
        if ($dist -le $bd) { $bd = $dist; $best = $d }
    }
    return $best
}

function Add-Drawing {
    param([string]$Kind, $A, $B = $null)
    $u = ([string]$script:Config.ActiveTicker).ToUpper()
    $nat = if ($script:ActiveNativeCurr) { [string]$script:ActiveNativeCurr } else { [string]$script:ChartCur }
    $back = Convert-CurrencyValue -Amount 1.0 -FromCurrency ([string]$script:ChartCur) -ToCurrency $nat
    $d = [PSCustomObject]@{ Id = [Guid]::NewGuid().ToString("N").Substring(0, 12); Kind = $Kind; T1 = [long]$A.T; P1 = [double]$A.P * $back; T2 = 0L; P2 = 0.0; Cur = $nat }
    if ($null -ne $B) { $d.T2 = [long]$B.T; $d.P2 = [double]$B.P * $back }
    if (-not $script:Drawings.ContainsKey($u)) { $script:Drawings[$u] = New-Object System.Collections.Generic.List[object] }
    $script:Drawings[$u].Add($d)
    Save-Drawings
    $script:ChartSignature = ""
    Update-ChartCacheSignature
    $pnlChartCanvas.Invalidate()
    if ($null -ne $script:FsCanvas -and -not $script:FsCanvas.IsDisposed) { $script:FsCanvas.Invalidate() }
}

function Remove-Drawing {
    param($D, [switch]$All)
    $u = ([string]$script:Config.ActiveTicker).ToUpper()
    if ($All) { [void]$script:Drawings.Remove($u) }
    elseif ($null -ne $D -and $script:Drawings.ContainsKey($u)) {
        for ($i = 0; $i -lt $script:Drawings[$u].Count; $i++) { if ($script:Drawings[$u][$i].Id -eq $D.Id) { $script:Drawings[$u].RemoveAt($i); break } }
    }
    Save-Drawings
    $script:ChartSignature = ""
    Update-ChartCacheSignature
    $pnlChartCanvas.Invalidate()
}

function Draw-ChartDrawings {
    # Static layer: all drawings of the active ticker
    param([System.Drawing.Graphics]$g, $L)
    $dl = $script:Drawings[([string]$script:Config.ActiveTicker).ToUpper()]
    if ($null -eq $dl -or $dl.Count -eq 0 -or $L.N -lt 2) { return }
    $pr = $L.PriceRect
    $col = [System.Drawing.Color]::FromArgb(250, 204, 21)
    $pen = New-Object System.Drawing.Pen($col, [float]1.5)
    $fibPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(160, $col.R, $col.G, $col.B), [float]1)
    $fibPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $br = New-Object System.Drawing.SolidBrush($col)
    $oldClip = $g.Clip
    $g.SetClip($pr)
    try {
        foreach ($d in $dl) {
            $px = Get-DrawingPixels -L $L -D $d
            switch ($d.Kind) {
                "H" {
                    $g.DrawLine($pen, [float]$pr.Left, [float]$px.Y1, [float]$pr.Right, [float]$px.Y1)
                    $g.DrawString(("{0:N2}" -f ($d.P1 * $px.Fx)), $fontAxis, $br, [float]($pr.Left + (S 4)), [float]($px.Y1 - (S 14)))
                }
                "T" {
                    # ray: from point 1 through point 2 to the right edge
                    $x2 = $px.X2; $y2 = $px.Y2
                    if ([math]::Abs($px.X2 - $px.X1) -gt 0.5) {
                        $slope = ($px.Y2 - $px.Y1) / ($px.X2 - $px.X1)
                        $xe = if ($px.X2 -ge $px.X1) { $pr.Right } else { $pr.Left }
                        $x2 = $xe; $y2 = $px.Y1 + $slope * ($xe - $px.X1)
                    }
                    $g.DrawLine($pen, [float]$px.X1, [float]$px.Y1, [float]$x2, [float]$y2)
                    $g.FillEllipse($br, [float]($px.X1 - 3), [float]($px.Y1 - 3), [float]6, [float]6)
                    $g.FillEllipse($br, [float]($px.X2 - 3), [float]($px.Y2 - 3), [float]6, [float]6)
                }
                "F" {
                    $xs = [math]::Max([double]$pr.Left, [math]::Min($px.X1, $px.X2))
                    foreach ($lv in (Get-FibLevels -P1 $d.P1 -P2 $d.P2)) {
                        $yy = $pr.Bottom - ((Get-PriceFrac ($lv.Price * $px.Fx) ([double]$L.MinP) ([double]$L.SpanP) ([bool]$L.LogScale)) * $pr.Height)
                        $g.DrawLine($(if ($lv.Pct -in @(0.0, 100.0)) { $pen } else { $fibPen }), [float]$xs, [float]$yy, [float]$pr.Right, [float]$yy)
                        $g.DrawString(("{0:0.#}%  {1:N2}" -f $lv.Pct, ($lv.Price * $px.Fx)), $fontAxis, $br, [float]($xs + (S 4)), [float]($yy - (S 13)))
                    }
                }
            }
        }
    } finally {
        $g.Clip = $oldClip
        $pen.Dispose(); $fibPen.Dispose(); $br.Dispose()
    }
}

function New-DrawingAlert {
    # horizontal line -> price alert, trend line -> alert that follows the line
    param($D)
    if ($null -eq $D) { return }
    $sym = ([string]$script:Config.ActiveTicker).ToUpper()
    $q = $script:QuoteStore[$sym]
    if ($null -eq $q -or [double]$q.Price -le 0) { Set-TransientStatus "Noch kein Kurs - später nochmal versuchen" 4; return }
    $cur = [string]$D.Cur
    $now = Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $cur
    if ($D.Kind -eq "H") {
        $op = if ($D.P1 -ge $now) { ">=" } else { "<=" }
        if (Add-WidgetAlert -Ticker $sym -Condition $op -Target ([math]::Round($D.P1, 4)) -Currency $cur -Note "Linie im Chart" -NoConfirm) {
            Set-TransientStatus ("Alarm: {0} {1} {2:N2} {3}" -f $sym, $op, $D.P1, $cur) 5
        }
        return
    }
    if ($D.Kind -eq "T") {
        $lineNow = Get-TrendPriceAt -T1 $D.T1 -P1 $D.P1 -T2 $D.T2 -P2 $D.P2 -T ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
        $op = if ($lineNow -ge $now) { "Trend >=" } else { "Trend <=" }
        $a = [PSCustomObject]@{
            Id = [Guid]::NewGuid().ToString("N"); Ticker = $sym; Condition = $op; TargetPrice = [math]::Round($lineNow, 4); Currency = $cur
            Triggered = $false; Note = "Trendlinie im Chart"; RearmMin = 0; TriggeredAt = ""; ExpiresAt = ""; Peak = 0.0; Push = $true
            T1 = $D.T1; P1 = $D.P1; T2 = $D.T2; P2 = $D.P2
        }
        $script:Alerts.Add($a)
        Save-Alerts
        Refresh-WatchlistAndAlerts
        Set-TransientStatus ("Alarm: {0} kreuzt die Trendlinie (jetzt {1:N2} {2})" -f $sym, $lineNow, $cur) 6
    }
}

# right-click menu on a drawing
$drawMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miDrAlert = $drawMenu.Items.Add("Alarm auf diese Linie")
$miDrDel = $drawMenu.Items.Add("Zeichnung löschen")
$miDrDelAll = $drawMenu.Items.Add("Alle Zeichnungen dieses Tickers löschen")
$script:MenuDrawing = $null
$miDrAlert.Add_Click({ New-DrawingAlert $script:MenuDrawing })
$miDrDel.Add_Click({ Remove-Drawing $script:MenuDrawing })
$miDrDelAll.Add_Click({ Remove-Drawing -All })

Read-Drawings
$script:DrawingsReady = $true

$chartContextMenu.Add_Opening({
    param($sender, $e)
    # v5.0: right-click on a drawing opens its own menu
    if ($null -ne $script:CtxDrawing) {
        $e.Cancel = $true
        $script:MenuDrawing = $script:CtxDrawing
        $script:CtxDrawing = $null
        $miDrAlert.Enabled = ($script:MenuDrawing.Kind -in @("H", "T"))
        $drawMenu.Show([System.Windows.Forms.Cursor]::Position)
        return
    }
    $px = $script:CtxPrice
    $sym = $script:Config.ActiveTicker.ToUpper()
    $cmiAlertHere.Enabled = -not [double]::IsNaN($px) -and $script:QuoteStore.ContainsKey($sym)
    if ($cmiAlertHere.Enabled) {
        $q = $script:QuoteStore[$sym]
        $cur = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $script:ChartCur
        $op = if ($px -ge $cur) { ">=" } else { "<=" }
        $cmiAlertHere.Text = "Alarm: {0} {1} {2} {3}" -f $sym, $op, (Format-LevelPrice $px), $script:ChartCur
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
    if (Add-WidgetAlert -Ticker $sym -Condition $t.Op -Target $t.Price -Currency $script:ChartCur -NoConfirm) {
        Set-TransientStatus ("Alarm angelegt: {0} {1} {2:N2} {3}" -f $sym, $t.Op, $t.Price, $script:ChartCur) 4
        Update-AllUiViews
    }
})
function Set-LogScale {
    param([bool]$On)
    $script:Config.LogScale = $On
    $cmiLog.Checked = $On
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Set-TransientStatus $(if ($On) { "Logarithmische Preisachse" } else { "Lineare Preisachse" }) 2
    Update-AllUiViews
}
$cmiLog.Add_Click({ Set-LogScale ([bool]$cmiLog.Checked) })
$cmiLevels.Add_Click({
    $script:Config.ShowLevels = $cmiLevels.Checked
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})
$cmiCompare.Add_Click({ Show-CompareDialog })
$cmiCompareOff.Add_Click({ Set-CompareTicker -Symbol "" })
$cmiZoomReset.Add_Click({ Reset-ChartZoom })

# Portfolio Grid & Editor Events
Update-DepotCombo
# v4.8: shares and cost can be typed directly into the portfolio table
$dgvPortfolio.ReadOnly = $false
foreach ($col in $dgvPortfolio.Columns) { $col.ReadOnly = ($col.Name -notin @("Shares", "Avg")) }
$dgvPortfolio.Columns["Shares"].ToolTipText = "Stück - Zelle markieren und tippen (oder F2) zum Ändern"
$dgvPortfolio.Columns["Avg"].ToolTipText = "EK in Anzeigewährung - Zelle markieren und tippen (oder F2) zum Ändern"
$dgvPortfolio.Add_CellEndEdit({
    param($sender, $e)
    $col = $sender.Columns[$e.ColumnIndex].Name
    if ($col -notin @("Shares", "Avg")) { return }
    $row = $sender.Rows[$e.RowIndex]
    $sym = ([string]$row.Cells["Ticker"].Value).ToUpper()
    $raw = [string]$row.Cells[$col].Value
    if (-not $script:Portfolio.ContainsKey($sym)) { return }
    $pf = $script:Portfolio[$sym]
    $v = Parse-DecimalInput $raw
    if (-not (Test-DecimalInput $raw) -or $v -le 0) {
        Set-TransientStatus "Ungültige Zahl: '$raw'" 4
        Refresh-PortfolioGrid
        return
    }
    $before = "{0:N4} Stk @ {1:N4} {2}" -f $pf.Shares, $pf.AvgPrice, $pf.Currency
    if ($col -eq "Shares") { $pf.Shares = $v }
    else { $pf.AvgPrice = Convert-CurrencyValue -Amount $v -FromCurrency ([string]$script:Config.Currency) -ToCurrency ([string]$pf.Currency) }
    Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
    Write-WidgetLog ("Position edited in the grid: {0} {1} -> {2:N4} Stk @ {3:N4} {4}" -f $sym, $before, $pf.Shares, $pf.AvgPrice, $pf.Currency)
    Set-TransientStatus ("{0} geändert (ohne Buchung) - Strg+Z = rückgängig" -f $sym) 6
    Update-AllUiViews
})
$dgvPortfolio.Add_CellBeginEdit({
    param($sender, $e)
    # v4.9.5: no editing of hidden values
    if ([bool]$script:Config.PrivacyMode) { $e.Cancel = $true; Set-TransientStatus (Tr "Privat-Modus: erst F9 drücken, dann bearbeiten") 4; return }
    # remember the position for Ctrl+Z
    $sym = ([string]$sender.Rows[$e.RowIndex].Cells["Ticker"].Value).ToUpper()
    if ($script:Portfolio.ContainsKey($sym)) {
        $pf = $script:Portfolio[$sym]
        $script:Undo = @{ Kind = "Position"; Data = @{ Key = $sym; Item = [PSCustomObject]@{ Ticker = $sym; Shares = [double]$pf.Shares; AvgPrice = [double]$pf.AvgPrice; Currency = [string]$pf.Currency; BuyAmount = [double]$pf.BuyAmount; TargetAvg = [double]$pf.TargetAvg } }; Until = (Get-Date).AddSeconds(30) }
    }
})
# v4.6: columns (right-click a header), global hotkey, snapping to screen edges
Enable-GridCustomization -Grid $dgvWatchlist -Key "Watchlist"
Enable-GridCustomization -Grid $dgvPortfolio -Key "Portfolio"
$hkMsg = Register-GlobalHotkey
if ($hkMsg -and $hkMsg -ne "aus") { Write-WidgetLog "Global hotkey: $hkMsg" "WARN" }
$form.Add_ResizeEnd({
    if (-not [bool]$script:Config.SnapToEdges -or $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) { return }
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $sn = Get-SnappedPosition -X $form.Left -Y $form.Top -W $form.Width -H $form.Height -AreaLeft $wa.Left -AreaTop $wa.Top -AreaRight $wa.Right -AreaBottom $wa.Bottom -Dist (S 16)
    if ($sn.Moved) { $form.Location = New-Object System.Drawing.Point([int]$sn.X, [int]$sn.Y) }
})
$cmbDepot.Add_SelectionChangeCommitted({
    if ($script:DepotComboBusy) { return }
    $ix = $cmbDepot.SelectedIndex
    $list = @(Get-DepotList)
    if ($ix -lt $list.Count) { Switch-Depot $list[$ix].Id; return }
    $act = $ix - $list.Count
    Update-DepotCombo
    switch ($act) { 0 { New-Depot } 1 { Rename-ActiveDepot } 2 { Remove-ActiveDepot } }
})

$cmbPortSort.Add_SelectedIndexChanged({
    # choosing a preset ends a header-click sort
    $script:PfSort.Col = ""; $script:PfSort.Step = 0
    Set-GridSortGlyph -Grid $dgvPortfolio -Sort $script:PfSort
    Refresh-PortfolioGrid
})
$dgvPortfolio.Add_ColumnHeaderMouseClick({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $name = $sender.Columns[$e.ColumnIndex].Name
    if ($name -eq "Spark") { return }
    Step-GridSort -Sort $script:PfSort -Col $name -TextCols @("Ticker")
    Set-GridSortGlyph -Grid $dgvPortfolio -Sort $script:PfSort
    Refresh-PortfolioGrid
})
$dgvWatchlist.Add_ColumnHeaderMouseClick({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
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

    # v4.2: the buy gets its real date (value history, XIRR, yearly report)
    $buyDate = ""
    if ($logBuy) {
        $buyDate = Show-BuyDatePrompt -Ticker $sym -Shares $sh
        if (-not $buyDate) { $lblNachkaufOut.Text = "Speichern abgebrochen."; return }
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
    if ($logBuy) {
        # a buy dated before a split is stored in the units of its own date
        $bf = Get-BookingUnitsFactor -Ticker $sym -Date $buyDate
        Add-TransactionRecord -Type "Kauf" -Ticker $sym -Shares ($sh / $bf) -Price ($avg * $bf) -Fee 0 -Currency $posCurr -Date $buyDate -Note "Portfolio-Editor"
    }
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
        $old = $script:Portfolio[$sym]
        $script:Portfolio.Remove($sym)
        Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
        Update-AllUiViews
        Set-Undo -Kind "Position" -Data @{ Key = $sym; Item = $old } -Text "Position $sym gelöscht (Buchungen bleiben)"
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
            $csvLines.Add(("{0};{1:F4};{2:F4};{3:F4};{4:F4};{5};{6}" -f $dtStr, $pt.Open, $pt.High, $pt.Low, $pt.Close, $script:ChartCur, $pt.Volume))
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

# ---- v5.0: hover card (mouse rests on a ticker in the watchlist / portfolio) ----
$script:HoverSym = ""
$script:HoverPending = $null
$pnlHover = New-Object System.Windows.Forms.Panel
$pnlHover.Size = New-Object System.Drawing.Size((S 300), (S 172))
$pnlHover.Visible = $false
$pnlHover.BackColor = $script:Pal.HeaderBg
Enable-DoubleBuffering -Control $pnlHover
$form.Controls.Add($pnlHover)
$script:HoverTimer = New-Object System.Windows.Forms.Timer
$script:HoverTimer.Interval = 650
$script:HoverTimer.Add_Tick({
    $script:HoverTimer.Stop()
    $hp = $script:HoverPending
    if ($null -eq $hp -or -not [bool]$script:Config.HoverCards) { return }
    $script:HoverSym = [string]$hp.Sym
    $pt = $form.PointToClient([System.Windows.Forms.Cursor]::Position)
    $x = $pt.X + (S 18); $y = $pt.Y + (S 14)
    if ($x + $pnlHover.Width -gt $form.ClientSize.Width - (S 4)) { $x = $pt.X - $pnlHover.Width - (S 12) }
    if ($y + $pnlHover.Height -gt $form.ClientSize.Height - (S 4)) { $y = $pt.Y - $pnlHover.Height - (S 8) }
    $pnlHover.Location = New-Object System.Drawing.Point([math]::Max(0, $x), [math]::Max(0, $y))
    $pnlHover.Visible = $true
    $pnlHover.BringToFront()
    $pnlHover.Invalidate()
})
function Hide-HoverCard {
    $script:HoverTimer.Stop()
    $script:HoverPending = $null
    if ($pnlHover.Visible) { $pnlHover.Visible = $false }
}
$script:HoverEnter = {
    param($sender, $e)
    if ($e.RowIndex -lt 0 -or -not [bool]$script:Config.HoverCards) { return }
    $sym = ([string]$sender.Rows[$e.RowIndex].Cells[0].Value).Trim().ToUpper()
    if (-not $sym -or -not $script:QuoteStore.ContainsKey($sym)) { Hide-HoverCard; return }
    if ($pnlHover.Visible -and $script:HoverSym -eq $sym) { return }
    if ($pnlHover.Visible) { $pnlHover.Visible = $false }
    $script:HoverPending = @{ Sym = $sym }
    $script:HoverTimer.Stop(); $script:HoverTimer.Start()
}
foreach ($hg in @($dgvWatchlist, $dgvPortfolio)) {
    $hg.Add_CellMouseEnter($script:HoverEnter)
    $hg.Add_MouseLeave({ Hide-HoverCard })
    $hg.Add_Scroll({ Hide-HoverCard })
    $hg.Add_MouseDown({ Hide-HoverCard })
}
$pnlHover.Add_MouseEnter({ Hide-HoverCard })
$script:HoverReady = $true
$pnlHover.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $p = $script:Pal
    $sym = $script:HoverSym
    $q = $script:QuoteStore[$sym]
    $w = $sender.Width; $h = $sender.Height
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear($p.HeaderBg)
    $bp = New-Object System.Drawing.Pen($p.Accent, [float]1)
    $g.DrawRectangle($bp, 0, 0, $w - 1, $h - 1); $bp.Dispose()
    if ($null -eq $q) { return }
    $txt = New-Object System.Drawing.SolidBrush($p.Text)
    $mut = New-Object System.Drawing.SolidBrush($p.Muted)
    $acc = New-Object System.Drawing.SolidBrush($p.Accent)
    $upB = New-Object System.Drawing.SolidBrush($(if ([double]$q.ChangePct -ge 0) { $colGreen } else { $colRed }))
    try {
        $x0 = S 10; $y = S 8
        $g.DrawString($sym, $fontTicker, $acc, $x0, $y)
        $nm = if ($q.LongName) { [string]$q.LongName } else { "" }
        $g.DrawString($nm, $fontUi, $mut, (New-Object System.Drawing.RectangleF([float]($x0 + (S 90)), [float]($y + 2), [float]($w - (S 104)), [float](S 18))))
        $y += S 22
        $curr = [string]$script:Config.Currency
        $pcur = Get-PriceCurrency $sym
        $pc = Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $pcur
        $g.DrawString(("{0:N2} {1}" -f $pc, $pcur), $fontPrice, $txt, $x0, $y)
        $g.DrawString(("{0:+0.00;-0.00}%" -f [double]$q.ChangePct), $fontTicker, $upB, ($x0 + (S 150)), ($y + (S 3)))
        $y += S 26
        # day range (from the quote meta) and 52-week bar
        $dLo = [double]::NaN; $dHi = [double]::NaN
        if ($null -ne $q.Meta) { try { $dLo = [double]$q.Meta.regularMarketDayLow; $dHi = [double]$q.Meta.regularMarketDayHigh } catch { } }
        if ($dLo -gt 0 -and $dHi -gt 0) { $g.DrawString(("{0} {1:N2} - {2:N2} {3}" -f (Tr "Tag:"), $dLo, $dHi, $q.Currency), $fontUi, $mut, $x0, $y); $y += S 17 }
        $f52 = Get-RangePosition -Price ([double]$q.Price) -Low ([double]$q.Low52) -High ([double]$q.High52)
        if (-not [double]::IsNaN($f52)) {
            $g.DrawString(("52W {0:N2}" -f [double]$q.Low52), $fontAxis, $mut, $x0, $y)
            $hiTxt = "{0:N2}" -f [double]$q.High52
            $hiW = $g.MeasureString($hiTxt, $fontAxis).Width
            $g.DrawString($hiTxt, $fontAxis, $mut, [float]($w - (S 10) - $hiW), $y)
            $bx0 = $x0 + (S 78); $bx1 = $w - (S 18) - $hiW; $by = $y + (S 7)
            $tp = New-Object System.Drawing.Pen($p.Border, [float](S 3)); $g.DrawLine($tp, [float]$bx0, [float]$by, [float]$bx1, [float]$by); $tp.Dispose()
            $mx = $bx0 + ($bx1 - $bx0) * $f52
            $g.FillEllipse($acc, [float]($mx - (S 4)), [float]($by - (S 4)), [float](S 8), [float](S 8))
            $y += S 18
        }
        # 5-day sparkline
        if ($script:SparklineStore.ContainsKey($sym)) {
            Draw-MiniSparkline -g $g -Rect (New-Object System.Drawing.Rectangle($x0, $y, ($w - 2 * $x0), (S 26))) -Values $script:SparklineStore[$sym]
            $y += S 30
        }
        # position, next event, analysts
        $lines = @()
        if ($script:Portfolio.ContainsKey($sym)) {
            $pf = $script:Portfolio[$sym]
            $val = [double]$pf.Shares * $pc
            $cost = [double]$pf.Shares * (Convert-CurrencyValue -Amount ([double]$pf.AvgPrice) -FromCurrency ([string]$pf.Currency) -ToCurrency $curr)
            $pl = if ($cost -gt 0) { ($val / $cost - 1) * 100 } else { [double]::NaN }
            $lines += $(if ([bool]$script:Config.PrivacyMode) { "{0}: {1:+0.0;-0.0}%" -f (Tr "Im Depot"), $pl } else { "{0}: {1:N2} Stk, {2:N2} {3} ({4:+0.0;-0.0}%)" -f (Tr "Im Depot"), [double]$pf.Shares, $val, $curr, $pl })
        }
        $ev = $script:Events[$sym]
        if ($null -ne $ev) {
            if ($ev.EarningsDate) { $lines += ("{0} {1}" -f (Tr "Zahlen:"), (Format-IsoDateDe ([string]$ev.EarningsDate))) }
            $lab = Get-ConsensusLabel ([string]$ev.RecKey) -Long
            $up = Get-TargetUpside -Target ([double]$ev.TargetMean) -Price ([double]$q.Price)
            if ($lab -or -not [double]::IsNaN($up)) { $lines += ("{0} {1}{2}" -f (Tr "Analysten:"), $lab, $(if (-not [double]::IsNaN($up)) { " (Ziel {0:+0;-0}%)" -f $up } else { "" })) }
        }
        foreach ($ln in $lines) { if ($y -lt $h - (S 16)) { $g.DrawString($ln, $fontUi, $txt, $x0, $y); $y += S 17 } }
    } finally { $txt.Dispose(); $mut.Dispose(); $acc.Dispose(); $upB.Dispose() }
})

# v4.9.5: right-click actions on a ticker (watchlist and portfolio)
$script:RowMenuSym = ""
$rowMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miRowChart = $rowMenu.Items.Add("Chart öffnen")
$miRowAlert = $rowMenu.Items.Add("Alarm anlegen ...")
$miRowBuy   = $rowMenu.Items.Add("Kauf / Verkauf buchen ...")
$miRowNews  = $rowMenu.Items.Add("Nachrichten (News-Tab)")
$miRowCmp   = $rowMenu.Items.Add("Im Chart vergleichen")
$miRowDes   = $rowMenu.Items.Add("Beschreibung (DES)")
$miRowTa    = $rowMenu.Items.Add("Ticker-Analyse: Signale + Kennzahlen (TA)")
$miRowSep   = New-Object System.Windows.Forms.ToolStripSeparator
[void]$rowMenu.Items.Add($miRowSep)
$miRowRemove = $rowMenu.Items.Add("Aus der Watchlist entfernen")
# v5.0: groups
$miRowGroup = New-Object System.Windows.Forms.ToolStripMenuItem("Zu Gruppe")
$rowMenu.Items.Insert($rowMenu.Items.IndexOf($miRowSep), $miRowGroup)
$miRowChart.Add_Click({ $s0 = $script:RowMenuSym; if ([string]$script:Config.Layout -ne "Terminal") { Set-ActiveTab -TabName "Chart" }; Switch-ActiveTicker -NewTicker $s0 -SkipResolve $true })
$miRowAlert.Add_Click({
    $s0 = $script:RowMenuSym
    Set-ActiveTab -TabName "Watchlist"
    $txtAlertTicker.Text = $s0
    [void]$txtAlertPrice.Focus()
    Set-TransientStatus ("Alarm für {0}: Bedingung und Wert eintragen, dann '+'" -f $s0) 5
})
$miRowBuy.Add_Click({ Show-TransactionDialog -Ticker $script:RowMenuSym })
$miRowNews.Add_Click({ Set-NewsFilter $script:RowMenuSym; Set-ActiveTab -TabName "News" })
$miRowCmp.Add_Click({
    $s0 = $script:RowMenuSym
    if ($s0 -eq ([string]$script:Config.ActiveTicker).ToUpper()) { Set-TransientStatus "Das ist der aktive Ticker - erst einen anderen öffnen" 4; return }
    Switch-CompareTicker -Symbol $s0
    if ([string]$script:Config.Layout -ne "Terminal") { Set-ActiveTab -TabName "Chart" }
})
$miRowDes.Add_Click({ Show-DescriptionDialog $script:RowMenuSym })
$miRowTa.Add_Click({ Show-TickerAnalysis $script:RowMenuSym })
$miRowRemove.Add_Click({ Remove-SymbolFromWatchlist -Symbol $script:RowMenuSym })
$script:RowMenuHandler = {
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right -or $e.RowIndex -lt 0) { return }
    $sym = ([string]$sender.Rows[$e.RowIndex].Cells[0].Value).Trim().ToUpper()
    if (-not $sym) { return }
    $script:RowMenuSym = $sym
    $sender.ClearSelection()
    $sender.Rows[$e.RowIndex].Selected = $true
    $inWl = (@($script:Config.Watchlist | ForEach-Object { ([string]$_).ToUpper() }) -contains $sym)
    $miRowRemove.Visible = $inWl -and ($sender -eq $dgvWatchlist)
    $miRowSep.Visible = $miRowRemove.Visible
    $miRowChart.Text = "{0}: {1}" -f (Tr "Chart öffnen"), $sym
    # groups: tick = member; click toggles; last entry creates a new group
    $miRowGroup.DropDownItems.Clear()
    $miRowGroup.Visible = $inWl
    foreach ($gr in @($script:Config.WatchGroups)) {
        if ($null -eq $gr -or -not $gr.Name) { continue }
        $gi = New-Object System.Windows.Forms.ToolStripMenuItem([string]$gr.Name)
        $gi.Checked = (@($gr.Symbols | ForEach-Object { ([string]$_).ToUpper() }) -contains $sym)
        $gi.Tag = [string]$gr.Name
        $gi.Add_Click({
            param($s2, $e2)
            $script:Config.WatchGroups = @(Set-WatchGroupMember -Groups @($script:Config.WatchGroups) -Group ([string]$s2.Tag) -Symbol $script:RowMenuSym -In (-not $s2.Checked))
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-WatchGroupCombo
            Refresh-WatchlistAndAlerts
        })
        [void]$miRowGroup.DropDownItems.Add($gi)
    }
    $gn = New-Object System.Windows.Forms.ToolStripMenuItem((Tr "Neue Gruppe ..."))
    $gn.Add_Click({ $nm = New-WatchGroup -Symbol $script:RowMenuSym; if ($nm) { Update-WatchGroupCombo; Refresh-WatchlistAndAlerts } })
    [void]$miRowGroup.DropDownItems.Add($gn)
    $rowMenu.Show($sender, $sender.PointToClient([System.Windows.Forms.Cursor]::Position))
}
$dgvWatchlist.Add_CellMouseDown($script:RowMenuHandler)
$dgvPortfolio.Add_CellMouseDown($script:RowMenuHandler)

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

function New-AlertChecked {
    # Validates and creates an alert (alert panel + command line).
    # Returns "" when created, "CANCEL" when the user declined, else an error text.
    param([string]$RawTicker, [string]$Cond, [double]$Value, [string]$Note = "", [int]$Rearm = 0, [int]$ExpDays = 0)
    $kind = Get-AlertKind $Cond
    if ($kind -ne "SMA") {
        # value ranges per kind (Tag% / EK% / Depot Tag% may be negative)
        $bad = ($kind -in @("PRICE", "PFVAL", "VOL") -and $Value -le 0) -or
               ($kind -in @("RSI", "TRAIL") -and ($Value -le 0 -or $Value -ge 100)) -or
               ($kind -in @("HIGH52", "LOW52") -and ($Value -lt 0 -or $Value -gt 50))
        if ($bad) { return ("Ungültiger Alarm-Wert {0} ({1})" -f $Value, (Get-AlertTargetHint $Cond)) }
    } else { $Value = 0.0 }
    if (Test-PortfolioAlertKind $kind) {
        if ($script:Portfolio.Count -eq 0) { return "Depot-Alarme brauchen Positionen im Portfolio." }
        $aSym = "DEPOT"
    } else {
        $aSym = Resolve-BestSymbol -RawInput $RawTicker
        if ([string]::IsNullOrWhiteSpace($aSym)) { return "Ticker '$RawTicker' nicht gefunden." }
    }
    if ($kind -eq "EKPCT" -and -not $script:Portfolio.ContainsKey($aSym)) { return "EK%-Alarme gehen nur für Positionen im Portfolio ($aSym fehlt)." }
    $qc = if ($script:QuoteStore.ContainsKey($aSym)) { [string]$script:QuoteStore[$aSym].Currency } else { "" }
    $curr = switch ($kind) {
        "PCT"    { "%" }
        "RSI"    { "RSI" }
        "SMA"    { "SMA" }
        "HIGH52" { "52W" }
        "LOW52"  { "52W" }
        "VOL"    { "VOL" }
        "PFPCT"  { "%" }
        # percent to the average cost in the position's currency (no FX effect)
        "EKPCT"  { [string]$script:Portfolio[$aSym].Currency }
        # trailing high in the instrument's own currency
        "TRAIL"  { if ($qc) { $qc } else { $script:Config.Currency } }
        # v5.1: a price alert is entered in the currency the price is shown in
        "PRICE"  { Get-PriceCurrency $aSym }
        default  { $script:Config.Currency }
    }
    $ok = Add-WidgetAlert -Ticker $aSym -Condition $Cond -Target $Value -Currency $curr -Note $Note -RearmMin $Rearm -ExpiresAt (Get-AlertExpiryDate -Days $ExpDays)
    if (-not $ok) { return "CANCEL" }
    Refresh-AllMarketData
    Evaluate-GlobalAlerts
    Update-AllUiViews
    return ""
}

$btnAddAlert.Add_Click({
    $aCond = [string]$cmbAlertCond.SelectedItem
    $kind  = Get-AlertKind $aCond
    $raw   = $txtAlertPrice.Text
    $aPrice = 0.0
    if ($kind -ne "SMA") {
        if ([string]::IsNullOrWhiteSpace($raw) -or -not (Test-DecimalInput $raw)) {
            Set-TransientStatus ("Ungültiger Alarm-Wert: '{0}' ({1})" -f $raw, (Get-AlertTargetHint $aCond)) 6
            return
        }
        $aPrice = Parse-DecimalInput $raw
    }
    $rearm = 0
    if ($null -ne $cmbAlertRearm.SelectedItem) { $rearm = [int]$script:RearmChoices[[string]$cmbAlertRearm.SelectedItem] }
    $expDays = 0
    if ($null -ne $cmbAlertExp.SelectedItem) { $expDays = [int]$script:AlertExpiryChoices[[string]$cmbAlertExp.SelectedItem] }
    $err = New-AlertChecked -RawTicker $txtAlertTicker.Text -Cond $aCond -Value $aPrice -Note $txtAlertNote.Text.Trim() -Rearm $rearm -ExpDays $expDays
    if ($err -eq "CANCEL") { return }
    if ($err) { Set-TransientStatus $err 6; return }
    if (-not (Test-PortfolioAlertKind $kind)) { $txtAlertTicker.Text = ([string]$script:Alerts[$script:Alerts.Count - 1].Ticker) }
    $txtAlertPrice.Text = ""
    $txtAlertNote.Text = ""
    $script:AlertAutoValue = ""
})

$btnDelAlert.Add_Click({
    $idx = $lstAlerts.SelectedIndex
    if ($idx -ge 0 -and $idx -lt $script:Alerts.Count) {
        # v4.6: no question any more - Ctrl+Z brings it back
        $al = $script:Alerts[$idx]
        $script:Alerts.RemoveAt($idx)
        Save-Alerts
        Update-AllUiViews
        Set-Undo -Kind "Alert" -Data @{ Item = $al; Index = $idx } -Text ("Alarm {0} {1} gelöscht" -f $al.Ticker, $al.Condition)
    }
})

$script:AlertAutoValue = ""
$cmbAlertCond.Add_SelectedIndexChanged({
    $cond = [string]$cmbAlertCond.SelectedItem
    $kind = Get-AlertKind $cond
    $isSma = ($kind -eq "SMA")
    $txtAlertPrice.Enabled = -not $isSma
    if ($isSma) { $txtAlertPrice.Text = "" }
    # v4.3: portfolio alerts watch the whole depot, not a ticker
    if (Test-PortfolioAlertKind $kind) {
        $txtAlertTicker.Text = "DEPOT"
        $txtAlertTicker.Enabled = $false
    } elseif (-not $txtAlertTicker.Enabled) {
        $txtAlertTicker.Enabled = $true
        $txtAlertTicker.Text = $script:Config.ActiveTicker
    }
    # suggested value; replaced again as long as the user did not type one
    $def = switch ($kind) { "TRAIL" { "8" } "VOL" { "2" } "HIGH52" { "0" } "LOW52" { "0" } "RSI" { "70" } default { "" } }
    if (-not $isSma -and ([string]::IsNullOrWhiteSpace($txtAlertPrice.Text) -or $txtAlertPrice.Text -eq $script:AlertAutoValue)) {
        $txtAlertPrice.Text = $def
        $script:AlertAutoValue = $def
    }
    $hint = Get-AlertTargetHint $cond
    if ($kind -eq "PFVAL") { $hint += " ($($script:Config.Currency))" }
    if ($kind -eq "PRICE") { $hint += " ($(Get-PriceCurrency ([string]$txtAlertTicker.Text)))" }
    if ($kind -eq "SMA") { $hint = "Kein Wert nötig: Kurs kreuzt SMA$($script:Config.SmaFastPeriod) (1h)" }
    Set-Tip $txtAlertPrice $hint $(if ($kind -eq "TRAIL") { "TRAIL" } elseif ($kind -eq "VOL") { "RELVOL" } else { "ALERTCOND" })
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
        $al = $script:Alerts[$idx]
        if (Test-AlertExpired -Alert $al) {
            # v4.3: an expired alert comes back without an end date
            $al.ExpiresAt = ""
            $al.Triggered = $false
        } else {
            $al.Triggered = -not $al.Triggered
        }
        $al.TriggeredAt = if ($al.Triggered) { (Get-Date).ToString("o") } else { "" }
        if (-not $al.Triggered -and (Get-AlertKind $al.Condition) -eq "TRAIL") { $al.Peak = 0.0 }
        Save-Alerts
        Refresh-WatchlistAndAlerts
    }
})

$btnAlertLog.Add_Click({ Show-AlertLogDialog })

# v4.9.5: snooze an alert (right-click in the alert list)
function Set-AlertSnooze {
    param([int]$Index, [string]$Kind)
    if ($Index -lt 0 -or $Index -ge $script:Alerts.Count) { return }
    $al = $script:Alerts[$Index]
    $until = Get-SnoozeUntil -Kind $Kind
    $v = if ($until -gt [DateTime]::MinValue) { $until.ToString("o") } else { "" }
    $al | Add-Member -NotePropertyName SnoozeUntil -NotePropertyValue $v -Force
    Save-Alerts
    Refresh-WatchlistAndAlerts
    if ($v) { Set-TransientStatus ("Alarm {0} pausiert bis {1:dd.MM. HH:mm}" -f $al.Ticker, $until) 4 } else { Set-TransientStatus ("Alarm {0} wieder aktiv" -f $al.Ticker) 3 }
}
$alertMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miSnz1 = $alertMenu.Items.Add("1 Stunde pausieren")
$miSnz4 = $alertMenu.Items.Add("4 Stunden pausieren")
$miSnzT = $alertMenu.Items.Add("Bis morgen 08:00 pausieren")
$miSnzOff = $alertMenu.Items.Add("Pause beenden")
[void]$alertMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miAlDel = $alertMenu.Items.Add("Löschen (Entf)")
$miSnz1.Add_Click({ Set-AlertSnooze -Index $lstAlerts.SelectedIndex -Kind "1h" })
$miSnz4.Add_Click({ Set-AlertSnooze -Index $lstAlerts.SelectedIndex -Kind "4h" })
$miSnzT.Add_Click({ Set-AlertSnooze -Index $lstAlerts.SelectedIndex -Kind "Tomorrow" })
$miSnzOff.Add_Click({ Set-AlertSnooze -Index $lstAlerts.SelectedIndex -Kind "" })
$miAlDel.Add_Click({ $btnDelAlert.PerformClick() })
$lstAlerts.Add_MouseUp({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
    $i = $sender.IndexFromPoint($e.Location)
    if ($i -lt 0 -or $i -ge $script:Alerts.Count) { return }
    $sender.SelectedIndex = $i
    $snz = Test-AlertSnoozed -Alert $script:Alerts[$i]
    $miSnzOff.Enabled = $snz
    $alertMenu.Show($sender, $e.Location)
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
    # v5.0: Esc first leaves the drawing mode
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape -and $script:DrawMode) {
        $e.Handled = $true
        Set-DrawMode ""
        Set-TransientStatus "Zeichnen abgebrochen" 2
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
    # v4.9.5: Esc leaves the full-page list (not while a drop-down is open)
    if (-not $isFs -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Escape -and $script:TerminalFull -and -not $lstTickerDropdown.Visible -and -not $lstWlSearchDropdown.Visible) {
        $e.Handled = $true
        Set-TerminalFull ""
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
    # v4.6: Ctrl+Z = undo the last deletion (not inside text boxes)
    if ($e.Control -and -not $e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Z -and -not ($sender.ActiveControl -is [System.Windows.Forms.TextBox])) {
        if (Invoke-Undo) { $e.Handled = $true; $e.SuppressKeyPress = $true; return }
    }
    if ($e.Control -and -not $e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Y -and -not ($sender.ActiveControl -is [System.Windows.Forms.TextBox])) {
        if (Invoke-Redo) { $e.Handled = $true; $e.SuppressKeyPress = $true; return }
    }
    # v4.4: Ctrl+K = command line (works in the fullscreen chart too)
    if ($e.Control -and -not $e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::K) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        Show-CommandPalette
        return
    }
    # v4.9.5: Ctrl+C in a list copies the whole table (visible columns, display order)
    if ($e.Control -and -not $e.Alt -and -not $e.Shift -and $e.KeyCode -eq [System.Windows.Forms.Keys]::C) {
        $gc = $sender.ActiveControl
        if ($gc -is [System.Windows.Forms.DataGridView] -and -not $gc.IsCurrentCellInEditMode -and $gc.Rows.Count -gt 0) {
            if (Copy-GridAsTable -Grid $gc) { $e.Handled = $true; $e.SuppressKeyPress = $true; return }
        }
    }
    # Other Ctrl/Alt combos (Ctrl+C, Alt+F4, ...) are never widget shortcuts
    if ($e.Control -or $e.Alt) { return }
    $ac = $sender.ActiveControl
    $isFKey = $e.KeyCode -in @([System.Windows.Forms.Keys]::F1, [System.Windows.Forms.Keys]::F2, [System.Windows.Forms.Keys]::F3, [System.Windows.Forms.Keys]::F5)
    # v4.9: F4 = News, except in a drop-down (F4 opens it there, as in every Windows list)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F4 -and -not ($ac -is [System.Windows.Forms.ComboBox])) { $isFKey = $true }
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F9) { $isFKey = $true }
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
        ([System.Windows.Forms.Keys]::F1) { Invoke-TabClick -TabName "Chart"; $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F2) { Invoke-TabClick -TabName "Portfolio" -ForceFull ([bool]$e.Shift); $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F3) { Invoke-TabClick -TabName "Watchlist" -ForceFull ([bool]$e.Shift); $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F4) { Invoke-TabClick -TabName "News" -ForceFull ([bool]$e.Shift); $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F9) { Set-PrivacyMode (-not [bool]$script:Config.PrivacyMode); $e.Handled = $true }
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
            Set-ActiveCurrency -NewCurrency (Get-NextCurrencyMode -Current $script:Config.Currency -Auto ([bool]$script:Config.AutoCurrency)); $e.Handled = $true
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
        ([System.Windows.Forms.Keys]::P) {
            Show-AnalysisDialog; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::T) {
            $btnThemeCycle.PerformClick(); $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::D) { if ($script:DrawMode) { Set-DrawMode "" } else { Set-DrawMode "T" }; $e.Handled = $true }
        ([System.Windows.Forms.Keys]::K) {
            $script:Config.ChartType = Get-NextChartType ([string]$script:Config.ChartType)
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
        ([System.Windows.Forms.Keys]::Y) {
            Set-LogScale (-not [bool]$script:Config.LogScale); $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::Divide) {
            $e.SuppressKeyPress = $true; Show-CommandPalette; $e.Handled = $true
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
        # v4.4: every market of interest closed -> poll only every N minutes
        $lastData = if ($null -ne $script:LastDataTime) { [DateTime]$script:LastDataTime } else { [DateTime]::MinValue }
        if (Test-ClosedPollSkip -States @(Get-PrioMarketStates) -LastData $lastData -ClosedMinutes ([int]$script:Config.ClosedPollMinutes)) {
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
        if ($script:PushPending.Count -gt 0) { Pump-PushTasks }
        if ($script:StartupDone -and -not [bool]$script:Config.FirstRunDone -and $form.Visible -and -not $script:TourShown -and -not $script:SmokeMode) {
            $script:TourShown = $true
            Show-WelcomeTour
        }
        if ($nowTick -ge $script:NextEventsCheck) {
            $script:NextEventsCheck = $nowTick.AddMinutes(10)
            Update-EventsIfStale
            Check-EarningsNotifications
            Invoke-DailyBackup
            Invoke-SavingsPlans   # v5.0
        }
        # v4.9: news feed (also in the background, for the unread count)
        if ($script:StartupDone -and $nowTick -ge $script:NextNewsLoad) {
            $allClosed = Test-AllPrioClosed
            $script:NextNewsLoad = $nowTick.AddMinutes((Get-NewsPollMinutes -Minutes ([int]$script:Config.NewsRefreshMinutes) -AllClosed $allClosed))
            Start-NewsLoad
        }
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
    Update-PrivacyIndicator
    # v5.0: back to where you were: full-page list, open Analyse window
    if ([string]$script:Config.Layout -eq "Terminal" -and [string]$script:Config.TerminalFull -in @("Portfolio", "Watchlist", "News")) { Set-TerminalFull ([string]$script:Config.TerminalFull) }
    if ([string]$script:Config.ReopenAnalysis -and -not $script:SmokeMode) {
        $script:ReopenTimer = New-Object System.Windows.Forms.Timer
        $script:ReopenTimer.Interval = 1500
        $script:ReopenTimer.Add_Tick({ $script:ReopenTimer.Stop(); $pg0 = [string]$script:Config.ReopenAnalysis; $script:Config.ReopenAnalysis = ""; Show-AnalysisDialog -Page $pg0 })
        $script:ReopenTimer.Start()
    }
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
    # v5.0: an open Analyse window opens again at the next start
    $script:Config.ReopenAnalysis = if ($null -ne $script:AnaCtl -and -not $script:SmokeMode) { [string]$script:AnaCtl.Page } else { "" }
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

# ==============================================================================
# v4.7: UI smoke test (CI). TW_SMOKE_TEST = report path. Starts the real
# window, opens every dialog (closed again by a timer), runs commands and
# layout switches, then writes a JSON report and exits with the error count.
# ==============================================================================
$script:SmokeMode = [bool]$env:TW_SMOKE_TEST
$script:SmokeSteps = New-Object System.Collections.Generic.List[PSObject]
$script:SmokeFailures = New-Object System.Collections.Generic.List[string]
$script:SmokeNotes = New-Object System.Collections.Generic.List[string]
$script:SmokeProgErrors = @("CommandNotFoundException", "ParameterBindingFailed", "ParameterArgumentTransformationError", "NamedParameterNotFound",
    "PositionalParameterNotFound", "MethodNotFound", "MethodCountCouldNotFindBest", "InvokeMethodOnNull", "NullArray", "PropertyAssignmentException",
    "PropertyNotFound", "InvalidCastFromStringToInteger", "ArgumentTransformationError", "RuntimeException", "IndexOutOfRangeException", "NullReferenceException", "VariableIsUndefined")

function Get-SmokeErrors {
    # Errors since the last call: programming errors fail the step, the rest are notes
    param([string]$Step)
    $fails = @()
    if ($global:Error.Count -gt 0) {
        $errs = @($global:Error)
        $global:Error.Clear()
        [array]::Reverse($errs)
        foreach ($er in $errs) {
            $id = [string]$er.FullyQualifiedErrorId
            $ln = if ($er.InvocationInfo) { $er.InvocationInfo.ScriptLineNumber } else { 0 }
            $msg = "{0} @ line {1}: {2} [{3}]" -f $Step, $ln, $er.ToString(), $id
            $isProg = $false
            foreach ($p in $script:SmokeProgErrors) { if ($id -like "$p*") { $isProg = $true; break } }
            if ($isProg) { $fails += $msg } else { $script:SmokeNotes.Add($msg) }
        }
    }
    return $fails
}

function Invoke-SmokeStep {
    param([string]$Name, [scriptblock]$Action, [int]$CloseAfterMs = 1200)
    [void](Get-SmokeErrors -Step "before $Name")
    $script:SmokeCloser.Interval = $CloseAfterMs
    $script:SmokeCloser.Start()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $true; $err = ""
    $rendErr0 = [int]$script:ChartRenderErrors
    try { & $Action } catch { $ok = $false; $err = "{0} @ line {1}" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber }
    if ([int]$script:ChartRenderErrors -gt $rendErr0 -and -not $err) { $ok = $false; $err = "chart render failed: " + [string]$script:LastRenderError }
    $script:SmokeCloser.Stop()
    foreach ($f in @(Get-SmokeErrors -Step $Name)) { $ok = $false; $script:SmokeFailures.Add($f) }
    if ($err) { $script:SmokeFailures.Add("$Name : $err") }
    $script:SmokeSteps.Add([PSCustomObject]@{ Name = $Name; Ok = $ok; Ms = $sw.ElapsedMilliseconds; Error = $err })
}

$script:SmokeCloser = New-Object System.Windows.Forms.Timer
$script:SmokeCloser.Add_Tick({
    # closes every window except the main window (and the fullscreen chart)
    foreach ($f in @([System.Windows.Forms.Application]::OpenForms)) {
        if ([object]::ReferenceEquals($f, $form) -or ($null -ne $script:FsForm -and [object]::ReferenceEquals($f, $script:FsForm))) { continue }
        try { $f.Close() } catch { }
    }
})

function Invoke-SmokeTest {
    $pump = { [System.Windows.Forms.Application]::DoEvents() }
    Invoke-SmokeStep "Refresh" { Refresh-AllMarketData -Force; for ($i = 0; $i -lt 60 -and $script:IsRefreshing; $i++) { Start-Sleep -Milliseconds 250; & $pump }; Evaluate-GlobalAlerts; Update-AllUiViews }
    foreach ($lay in @("Terminal", "Standard", "Compact", "Ticker", "Standard")) { Invoke-SmokeStep "Layout $lay" { Apply-Layout $lay; & $pump } }
    foreach ($tab in @("Chart", "Portfolio", "Watchlist", "News", "Chart")) { Invoke-SmokeStep "Tab $tab" { Set-ActiveTab -TabName $tab; & $pump } }
    # v4.9: the news tab with a real load (or the offline message), then fake items
    Invoke-SmokeStep "News load" {
        Set-ActiveTab -TabName "News"
        Start-NewsLoad
        for ($i = 0; $i -lt 80 -and $script:NewsLoading; $i++) { Start-Sleep -Milliseconds 250; & $pump }
        $fake = @{
            "NVDA" = @([PSCustomObject]@{ Title = "Smoke: NVDA item"; Publisher = "Test"; Link = ""; Time = (Get-Date).AddMinutes(-5); Tickers = @("MSFT") })
            "MSFT" = @([PSCustomObject]@{ Title = "Smoke: MSFT item"; Publisher = "Test"; Link = ""; Time = (Get-Date).AddHours(-30); Tickers = @() })
        }
        $script:NewsItems = @(Merge-NewsFeed -BySymbol $fake) + @($script:NewsItems)
        $script:NewsBoldSince = (Get-Date).AddHours(-1)
        Refresh-NewsGrid; & $pump
        if ($dgvNews.Rows.Count -lt 2) { throw "news grid has $($dgvNews.Rows.Count) rows" }
    }
    Invoke-SmokeStep "News filter + read" {
        foreach ($nf in @("Holdings", "Watchlist", "MSFT", "All")) { Set-NewsFilter $nf; & $pump }
        $btnNewsRead.PerformClick(); & $pump
        Set-ActiveTab -TabName "Chart"; & $pump
        $script:NewsSeenAt = (Get-Date).AddDays(-3)
        Update-NewsBadge
        if ($tabButtons["News"].Text -notlike ("*" + [char]0x25CF + "*")) { throw "no unread count on the tab: $($tabButtons['News'].Text)" }
        Set-ActiveTab -TabName "News"; & $pump
        Set-ActiveTab -TabName "Chart"; & $pump
    }
    Invoke-SmokeStep "News in Terminal" { Apply-Layout "Terminal"; Set-ActiveTab -TabName "News"; & $pump; Set-ActiveTab -TabName "Watchlist"; Apply-Layout "Standard"; & $pump }
    # v4.9.5
    Invoke-SmokeStep "News mute + menu" {
        Set-ActiveTab -TabName "News"; & $pump
        $first = @($script:NewsItems | Where-Object { $_.Publisher })[0]
        if ($null -ne $first) {
            $script:NewsMenuItem = $first
            $miNewsMute.PerformClick(); & $pump
            if (@($script:Config.NewsMuted).Count -lt 1) { throw "source not muted" }
            $script:Config.NewsMuted = @()
            Refresh-NewsGrid
        }
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "News keywords" {
        $before = $script:AlertLog.Count
        $script:Config.NewsKeywords = "smoke"
        $script:Config.NewsKeywordLastAt = (Get-Date).AddDays(-1).ToString("o")
        $script:NewsItems = @([PSCustomObject]@{ Key = "smoke-kw"; Title = "Smoke test headline"; Publisher = "Test"; Link = ""; Time = (Get-Date).AddMinutes(-1); Syms = @("NVDA") }) + @($script:NewsItems)
        Invoke-NewsKeywordCheck
        if ($script:AlertLog.Count -le $before) { throw "no keyword notice logged" }
        $script:Config.NewsKeywords = ""
    }
    Invoke-SmokeStep "Privacy mode" {
        Set-ActiveTab -TabName "Portfolio"
        Set-PrivacyMode $true; & $pump
        if ($lblPortSummary.Text -notmatch [string][char]0x2022) { throw "summary not masked: $($lblPortSummary.Text)" }
        Set-PrivacyMode $false; & $pump
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Undo + redo" {
        Set-ActiveTab -TabName "Watchlist"; & $pump   # PerformClick needs a visible button
        $script:Alerts.Add([PSCustomObject]@{ Id = "r"; Ticker = "MSFT"; Condition = ">="; TargetPrice = 99999.0; Currency = "EUR"; Triggered = $false; Note = ""; RearmMin = 0; TriggeredAt = ""; ExpiresAt = ""; Peak = 0.0; Push = $true })
        Refresh-WatchlistAndAlerts
        $n0 = $script:Alerts.Count
        $lstAlerts.SelectedIndex = $n0 - 1
        $btnDelAlert.PerformClick()
        if (-not (Invoke-Undo)) { throw "undo failed" }
        if (-not (Invoke-Redo)) { throw "redo failed" }
        if ($script:Alerts.Count -ne ($n0 - 1)) { throw "redo did not delete again ($($script:Alerts.Count))" }
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Alert snooze" {
        Set-ActiveTab -TabName "Watchlist"; & $pump
        if ($script:Alerts.Count -gt 0) {
            Set-AlertSnooze -Index 0 -Kind "1h"
            if (-not (Test-AlertSnoozed -Alert $script:Alerts[0])) { throw "not snoozed" }
            if ([string]$lstAlerts.Items[0] -notlike "*ZZZ*") { throw "list does not show the pause" }
            Set-AlertSnooze -Index 0 -Kind ""
        }
    }
    Invoke-SmokeStep "Watchlist extras" {
        $dgvWatchlist.Columns["Target"].Visible = $true
        Refresh-WatchlistAndAlerts; & $pump
        $dgvWatchlist.Columns["Target"].Visible = $false
        Refresh-WatchlistAndAlerts
        foreach ($mi in @($miRowNews, $miRowCmp, $miRowAlert)) { $script:RowMenuSym = "MSFT"; $mi.PerformClick(); & $pump }
        Set-CompareTicker -Symbol ""
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Copy table" {
        Set-ActiveTab -TabName "Watchlist"; & $pump
        [void](Copy-GridAsTable -Grid $dgvWatchlist)
        Set-ActiveTab -TabName "Portfolio"; & $pump
        [void](Copy-GridAsTable -Grid $dgvPortfolio)
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Keys F9 + full page" {
        $key = { param([System.Windows.Forms.Keys]$K) & $script:GlobalKeyHandler $form (New-Object System.Windows.Forms.KeyEventArgs($K)); & $pump }
        $was = [bool]$script:Config.PrivacyMode
        & $key ([System.Windows.Forms.Keys]::F9)
        if ([bool]$script:Config.PrivacyMode -eq $was) { throw "F9 did not toggle the privacy mode" }
        & $key ([System.Windows.Forms.Keys]::F9)
        Set-ActiveTab -TabName "Portfolio"; & $pump   # PerformClick needs a visible button
        $btnPrivacy.PerformClick(); & $pump
        if (-not [bool]$script:Config.PrivacyMode) { throw "privacy button did not switch it on" }
        Set-PrivacyMode $false
        Apply-Layout "Terminal"; & $pump
        & $key ([System.Windows.Forms.Keys]::F2 -bor [System.Windows.Forms.Keys]::Shift)
        if ($script:TerminalFull -ne "Portfolio" -or [bool]$script:ViewOn["Chart"]) { throw "Shift+F2 did not show the portfolio as a full page" }
        & $key ([System.Windows.Forms.Keys]::Escape)
        if ($script:TerminalFull -or -not [bool]$script:ViewOn["Chart"]) { throw "Esc did not return to the split view" }
        Set-ActiveTab -TabName "Watchlist"; & $pump
        $tabButtons["Watchlist"].PerformClick(); & $pump
        if ($script:TerminalFull -ne "Watchlist") { throw "second click on a shown tab did not open the full page" }
        $tabButtons["News"].PerformClick(); & $pump
        if ($script:TerminalFull -ne "News") { throw "full page did not follow the tab" }
        $tabButtons["Chart"].PerformClick(); & $pump
        if ($script:TerminalFull) { throw "Chart did not leave the full page" }
        [void](Invoke-TerminalCommand "FULL PORT"); & $pump
        [void](Invoke-TerminalCommand "FULL"); & $pump
        Apply-Layout "Standard"; & $pump
    }
    # v5.0 Stage A
    Invoke-SmokeStep "Cash account" {
        $script:Cash.Enabled = $true
        $script:Cash.Currency = "EUR"
        $script:Cash.BaselineIds = @($script:Transactions | ForEach-Object { [string]$_.Id })
        Add-CashEntry -Kind "Start" -Amount 1000
        Add-CashEntry -Kind "Einzahlung" -Amount 500
        $ci = Get-CashInfo -Currency "EUR"
        if ($null -eq $ci -or [math]::Abs($ci.Balance - 1500) -gt 0.01) { throw "cash balance wrong: $($ci.Balance)" }
        Set-ActiveTab -TabName "Portfolio"; & $pump
        Refresh-PortfolioGrid
        if ($lblPortSummary.Text -notlike "*Cash*") { throw "summary without cash: $($lblPortSummary.Text)" }
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Savings plan booking" {
        $n0 = $script:Transactions.Count
        $st = (Get-Date).AddMonths(-2)
        $script:SavingsPlans.Add([PSCustomObject]@{ Id = "smoke-plan"; Ticker = "MSFT"; Amount = 100.0; Fee = 1.0; Currency = "EUR"; Day = 3; Start = (New-Object DateTime($st.Year, $st.Month, 1)).ToString("yyyy-MM-dd"); LastBooked = ""; Active = $true })
        Save-SavingsPlans
        Invoke-SavingsPlans
        for ($i = 0; $i -lt 120 -and $script:PlansRunning; $i++) { Start-Sleep -Milliseconds 250; & $pump }
        $pl = @($script:SavingsPlans | Where-Object { $_.Id -eq "smoke-plan" })[0]
        if (-not $pl.LastBooked) { $script:SmokeNotes.Add("savings plan: nothing booked (offline?)") }
        elseif ($script:Transactions.Count -le $n0) { throw "plan marked as booked but no transaction" }
        $ci = Get-CashInfo -Currency "EUR"
        if ($pl.LastBooked -and $ci.Balance -ge 1500) { throw "the plan's buys did not reduce the cash ($($ci.Balance))" }
        [void]$script:SavingsPlans.Remove($pl)
        Save-SavingsPlans
    }
    # v5.0 Stage B
    Invoke-SmokeStep "Chart types + trades" {
        Set-ActiveTab -TabName "Chart"; Set-Timeframe -Tf "1d"; & $pump
        [void](Invoke-Transaction -Type "Kauf" -Ticker "NVDA" -Shares 1 -Price 100 -Fee 0 -Currency "USD" -Date (Get-Date).ToString("yyyy-MM-dd") -Note "smoke")
        foreach ($ct in @("HA", "Candle", "Line")) {
            $script:Config.ChartType = $ct; $script:LastChartLayout = $null
            Update-AllUiViews; $script:ChartSignature = ""; Update-ChartCacheSignature; $pnlChartCanvas.Refresh(); & $pump
            if ($null -eq $script:LastChartLayout -and @($script:ActiveSeries).Count -ge 2) { throw "chart did not render as $ct (see widget.log)" }
        }
        $tradeTips = @($script:LastChartLayout.Legends | Where-Object { [string]$_.Tip -like "Kauf*" })
        if (@($script:ActiveSeries).Count -ge 2 -and $tradeTips.Count -eq 0) { throw "today's buy is not drawn as a marker" }
        & $script:GlobalKeyHandler $form (New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::K)); & $pump
        if ([string]$script:Config.ChartType -ne "Candle") { $acN = if ($form.ActiveControl) { $form.ActiveControl.GetType().Name + "/" + $form.ActiveControl.Name } else { "none" }; throw "K did not cycle the chart type ($($script:Config.ChartType), focus $acN)" }
        $script:Config.ChartType = "Line"; Update-AllUiViews
    }
    Invoke-SmokeStep "Compare three" {
        Switch-CompareTicker -Symbol "MSFT"; Switch-CompareTicker -Symbol "SAP.DE"; Switch-CompareTicker -Symbol "AAPL"
        if (@($script:Config.CompareMore).Count -ne 2) { throw "expected 2 extra comparisons, got $(@($script:Config.CompareMore).Count)" }
        Switch-CompareTicker -Symbol "AMD"
        if (@($script:Config.CompareMore).Count -ne 2) { throw "a fourth comparison was accepted" }
        Refresh-AllMarketData -Force
        for ($i = 0; $i -lt 60 -and $script:IsRefreshing; $i++) { Start-Sleep -Milliseconds 250; & $pump }
        Update-AllUiViews; $pnlChartCanvas.Refresh(); & $pump
        if ($script:ActiveCompareMore.Count -lt 1) { $script:SmokeNotes.Add("compare: extra lines not loaded (offline?)") }
        Set-CompareTicker -Symbol ""
        if (@($script:Config.CompareMore).Count -ne 0) { throw "clearing did not remove the extra comparisons" }
    }
    Invoke-SmokeStep "Drawings" {
        Set-ActiveTab -TabName "Chart"; Update-AllUiViews; $pnlChartCanvas.Refresh(); & $pump
        $L = Get-CanvasLayout -Canvas $pnlChartCanvas
        if ($null -eq $L) { $script:SmokeNotes.Add("drawings: no chart layout (no data?)"); return }
        $pr = $L.PriceRect
        $click = { param([int]$X, [int]$Y, $Btn = [System.Windows.Forms.MouseButtons]::Left) & $script:ChartMouseDownHandler $pnlChartCanvas (New-Object System.Windows.Forms.MouseEventArgs($Btn, 1, $X, ($Y + [int]$L.OffsetY), 0)); & $pump }
        $u = ([string]$script:Config.ActiveTicker).ToUpper()
        $n0 = if ($script:Drawings.ContainsKey($u)) { $script:Drawings[$u].Count } else { 0 }
        Set-DrawMode "H"; & $click ($pr.Left + [int]($pr.Width / 2)) ($pr.Top + [int]($pr.Height / 3))
        Set-DrawMode "T"; & $click ($pr.Left + 20) ($pr.Bottom - 30); & $click ($pr.Right - 40) ($pr.Top + 40)
        & $script:GlobalKeyHandler $form (New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::D)); & $pump
        if ($script:DrawMode -ne "T") { throw "D did not start the trend line mode" }
        Set-DrawMode "F"; & $click ($pr.Left + 60) ($pr.Bottom - 20); & $click ($pr.Left + 200) ($pr.Top + 20)
        if ($script:Drawings[$u].Count -ne ($n0 + 3)) { throw "expected 3 new drawings, got $($script:Drawings[$u].Count - $n0)" }
        $pnlChartCanvas.Refresh(); & $pump
        $L = Get-CanvasLayout -Canvas $pnlChartCanvas
        $hit = Find-DrawingAt -L $L -X ($pr.Left + 10) -Y ($pr.Top + [int]($pr.Height / 3) + [int]$L.OffsetY)
        if ($null -eq $hit -or $hit.Kind -ne "H") { throw "right-click hit test did not find the horizontal line" }
        $na = $script:Alerts.Count
        New-DrawingAlert $hit
        New-DrawingAlert (@($script:Drawings[$u] | Where-Object { $_.Kind -eq "T" })[0])
        if ($script:Alerts.Count -lt $na + 1) { $script:SmokeNotes.Add("drawing alerts: no quote yet") }
        Evaluate-GlobalAlerts
        Read-Drawings
        if ($script:Drawings[$u].Count -ne ($n0 + 3)) { throw "drawings were not saved" }
        Remove-Drawing -All
        Set-DrawMode ""
    }
    # v5.0 Stage C
    Invoke-SmokeStep "Terminal dividers" {
        Apply-Layout "Terminal"; Set-ActiveTab -TabName "Watchlist"; & $pump
        if (-not $splitChart.Visible) { throw "no divider between chart and lists" }
        $h0 = $viewChart.Height
        $script:Config.TerminalChartPct = 35; Update-MainLayout; & $pump
        if ($viewChart.Height -ge $h0) { throw "chart did not get smaller ($h0 -> $($viewChart.Height))" }
        $script:Config.TerminalChartPct = 55; Update-MainLayout
        Set-TerminalFull "Portfolio"
        if ([string]$script:Config.TerminalFull -ne "Portfolio" -or $splitChart.Visible) { throw "full page not remembered or divider still shown" }
        Set-TerminalFull ""
        Apply-Layout "Standard"; & $pump
        if ($splitChart.Visible) { throw "divider visible in Standard" }
    }
    Invoke-SmokeStep "Watchlist groups" {
        Set-ActiveTab -TabName "Watchlist"; & $pump
        $script:Config.WatchGroups = @(Set-WatchGroupMember -Groups @() -Group "Tech" -Symbol "NVDA")
        Set-WatchGroup "Tech"; & $pump
        if ($dgvWatchlist.Rows.Count -ne 1) { throw "group view shows $($dgvWatchlist.Rows.Count) rows" }
        $me = New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Right, 1, 10, 10, 0)
        & $script:RowMenuHandler $dgvWatchlist (New-Object System.Windows.Forms.DataGridViewCellMouseEventArgs(0, 0, 10, 10, $me)); & $pump
        $tg = @($miRowGroup.DropDownItems | Where-Object { [string]$_.Tag -eq "Tech" })[0]
        if ($null -eq $tg -or -not $tg.Checked) { throw "group menu does not tick the member" }
        $rowMenu.Close()
        Set-WatchGroup ""; & $pump
        if ($dgvWatchlist.Rows.Count -lt 3) { throw "'Alle' does not show the whole watchlist" }
        $script:Config.WatchGroups = @(); Update-WatchGroupCombo
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Hover card" {
        Set-ActiveTab -TabName "Watchlist"; & $pump
        & $script:HoverEnter $dgvWatchlist (New-Object System.Windows.Forms.DataGridViewCellEventArgs(0, 0))
        for ($i = 0; $i -lt 20 -and -not $pnlHover.Visible; $i++) { Start-Sleep -Milliseconds 100; & $pump }
        if (-not $pnlHover.Visible -and $script:QuoteStore.ContainsKey(([string]$dgvWatchlist.Rows[0].Cells[0].Value).ToUpper())) { throw "hover card did not appear" }
        $pnlHover.Refresh(); & $pump
        Hide-HoverCard
        if ($pnlHover.Visible) { throw "hover card did not hide" }
        Set-ActiveTab -TabName "Chart"
    }
    # v5.1
    Invoke-SmokeStep "Auto currency" {
        Set-ActiveCurrency "EUR"
        if ((Get-PriceCurrency "NVDA") -ne "EUR") { throw "fixed EUR does not show NVDA in EUR" }
        Set-ActiveCurrency "AUTO"
        if ((Get-PriceCurrency "NVDA") -ne "USD" -or (Get-PriceCurrency "SAP.DE") -ne "EUR") { throw "Auto: NVDA $(Get-PriceCurrency 'NVDA'), SAP.DE $(Get-PriceCurrency 'SAP.DE')" }
        foreach ($pair in @(@("SAP.DE", "EUR"), @("NVDA", "USD"))) {
            Switch-ActiveTicker -NewTicker $pair[0] -SkipResolve $true
            for ($i = 0; $i -lt 60 -and ($script:IsRefreshing -or @($script:ActiveSeries).Count -lt 2); $i++) { Start-Sleep -Milliseconds 250; & $pump }
            Update-AllUiViews; & $pump
            if (@($script:ActiveSeries).Count -ge 2 -and $script:ChartCur -ne $pair[1]) { throw "$($pair[0]) chart in $($script:ChartCur)" }
            if ($script:QuoteStore.ContainsKey($pair[0]) -and $lblLivePrice.Text -notlike "* $($pair[1])") { throw "$($pair[0]) header shows '$($lblLivePrice.Text)'" }
        }
        if ($btnCurrency.Text -notlike "Auto*") { throw "currency button shows '$($btnCurrency.Text)'" }
        & $script:GlobalKeyHandler $form (New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::W)); & $pump
        if ([bool]$script:Config.AutoCurrency -or [string]$script:Config.Currency -ne "EUR") { throw "W after Auto should give EUR" }
        Set-ActiveCurrency "AUTO"
    } 20000
    Invoke-SmokeStep "Prev close + health" {
        Set-Timeframe -Tf "1d"; & $pump
        $cmiPrevClose.PerformClick(); & $pump
        $cmiPrevClose.PerformClick(); & $pump
        Update-StatusLine
        if (-not $script:HealthLevel) { throw "no health level after refresh" }
    }
    foreach ($th in @("OLED", "Light", "Terminal", "Dark")) { Invoke-SmokeStep "Theme $th" { $script:Config.Theme = $th; Apply-ThemeToAllControls; & $pump } }
    foreach ($cmd in @("SCALE LOG", "TF 1Y", "SCALE LIN", "IND MACD", "IND EMA", "TF 5D", "IND RSI", "IND SMA", "NVDA GP 3M", "NVDA CMP", "CMP", "PORT", "ALRT", "LAYOUT SAVE SMOKE", "LAYOUT SMOKE", "LAYOUT DEL SMOKE", "NVDA ALRT TRAIL 8", "NVDA ALRT >= 99999", "ALRT DTAG- 50", "NVDA WL", "NEWS DEPOT", "NEWS MSFT", "NEWS", "N", "PRIV ON", "PRIV OFF", "DRAW H", "DRAW CLEAR", "NVDA CMP", "CMP")) {
        Invoke-SmokeStep "Command $cmd" { $m = Invoke-TerminalCommand $cmd; if ($m) { $script:SmokeNotes.Add("Command '$cmd': $m") }; & $pump }
    }
    Invoke-SmokeStep "Fullscreen chart" { Toggle-ChartFullscreen; & $pump; Close-ChartFullscreen; & $pump }
    $dialogs = [ordered]@{
        "Settings" = { Show-SettingsDialog }
        "Glossary" = { Show-GlossaryDialog }
        "Analysis Perf" = { Show-AnalysisDialog -Page "Perf" }
        "Analysis Ret" = { Show-AnalysisDialog -Page "Ret" }
        "Analysis Alloc" = { Show-AnalysisDialog -Page "Alloc" }
        "Analysis Div" = { Show-AnalysisDialog -Page "Div" }
        "Analysis Risk" = { Show-AnalysisDialog -Page "Risk" }
        "Analysis Target" = { Show-AnalysisDialog -Page "Target" }
        "Analysis Heat" = { Show-AnalysisDialog -Page "Heat" }
        "Cash" = { Show-CashDialog }
        "Savings plans" = { Show-SavingsPlansDialog }
        "Transaction history" = { Show-TransactionHistory }
        "Transaction dialog" = { Show-TransactionDialog -Ticker "NVDA" }
        "Year report" = { Show-YearReport }
        "Buy dates" = { [void](Show-BuyDatesDialog) }
        "Alert log" = { Show-AlertLogDialog }
        "Push" = { [void](Show-PushDialog) }
        "News" = { Show-NewsDialog "NVDA" }
        "Description" = { Show-DescriptionDialog "NVDA" }
        "Ticker analysis quick" = { Show-TickerAnalysis "NVDA" }
        "Ticker dividends" = { Show-TickerDividendsDialog "MSFT" }
        "Calendar" = { Show-CalendarDialog }
        "Movers" = { Show-MoversDialog }
        "FX" = { Show-FxDialog }
        "About" = { Show-AboutDialog }
        "Help" = { Show-ShortcutHelp }
        "Restore" = { Show-RestoreDialog }
        "Compare" = { Show-CompareDialog }
        "Command palette" = { Show-CommandPalette -Initial "NV" }
        "Welcome tour" = { Show-WelcomeTour }
        "Compact options" = { Show-CompactOptions }
    }
    foreach ($k in $dialogs.Keys) { Invoke-SmokeStep "Dialog $k" $dialogs[$k] 2500 }
    Invoke-SmokeStep "Settings search" {
        $script:SettingsSearchHits = -1
        $script:SmokeTyper = New-Object System.Windows.Forms.Timer
        $script:SmokeTyper.Interval = 700
        $script:SmokeTyper.Add_Tick({
            $script:SmokeTyper.Stop()
            foreach ($f in @([System.Windows.Forms.Application]::OpenForms)) {
                $hit = $f.Controls.Find("tSettingsSearch", $true)
                if ($hit.Count -gt 0) { $hit[0].Text = "push"; $script:SmokeSearchPush = $script:SettingsSearchHits; $hit[0].Text = "xyzxyz"; $script:SmokeSearchNone = $script:SettingsSearchHits; $hit[0].Text = "" }
            }
        })
        $script:SmokeSearchPush = -1; $script:SmokeSearchNone = -1
        $script:SmokeTyper.Start()
        Show-SettingsDialog
        $script:SmokeTyper.Stop()
        if ($script:SmokeSearchPush -lt 1) { throw "search 'push' found $($script:SmokeSearchPush) settings" }
        if ($script:SmokeSearchNone -ne 0) { throw "nonsense search found $($script:SmokeSearchNone) settings" }
    } 2500
    # v5.0: the Analyse pages again with time to load the price history
    foreach ($pg in @("Risk", "Target", "Heat")) { Invoke-SmokeStep "Analysis $pg loaded" { Show-AnalysisDialog -Page $pg } 12000 }
    # v5.1: look inside the open window shortly before it is closed
    $script:SmokeProbeTimer = New-Object System.Windows.Forms.Timer
    $script:SmokeProbeTimer.Add_Tick({ $script:SmokeProbeTimer.Stop(); try { $script:SmokeProbeResult = & $script:SmokeProbe } catch { $script:SmokeProbeResult = "probe failed: " + $_.Exception.Message } })
    $probeRun = {
        param([scriptblock]$Open, [scriptblock]$Probe, [int]$At)
        $script:SmokeProbe = $Probe; $script:SmokeProbeResult = "probe did not run"
        $script:SmokeProbeTimer.Interval = $At; $script:SmokeProbeTimer.Start()
        & $Open
        $script:SmokeProbeTimer.Stop()
        if ($script:SmokeProbeResult) { throw [string]$script:SmokeProbeResult }
    }
    Invoke-SmokeStep "Analysis Contrib + scenario" {
        & $probeRun { Show-AnalysisDialog -Page "Contrib" } {
            $ac = $script:AnaCtl
            if ($null -eq $ac) { return "window not open" }
            if ($ac.CGrid.Rows.Count -lt 2) { return "contribution grid has $($ac.CGrid.Rows.Count) rows" }
            $ac.SNum.Value = -30; [System.Windows.Forms.Application]::DoEvents()
            if ($ac.SGrid.Rows.Count -lt 1 -or -not $ac.SRes.Text) { return "scenario empty" }
            Set-AnalysisRange "1Y"; Set-AnalysisRange "Max"
            return ""
        } 11000
    } 13000
    Invoke-SmokeStep "Analysis Bench" {
        & $probeRun { Show-AnalysisDialog -Page "Bench" } {
            $ac = $script:AnaCtl
            if ($null -eq $ac) { return "window not open" }
            Update-AnalysisBench
            if ($ac.BGrid.Rows.Count -lt 2) { return "comparison grid has $($ac.BGrid.Rows.Count) rows" }
            if (@($ac.BLines | Where-Object { $null -ne $_.Win }).Count -lt 2) { return "fewer than 2 lines (indices not loaded)" }
            $ac.BChart.Refresh()
            if ($ac.SecGrid.Rows.Count -lt 1) { return "no sector rows" }
            return ""
        } 11000
    } 13000
    Invoke-SmokeStep "Ticker analysis" {
        & $probeRun { Show-TickerAnalysis "MSFT" } {
            $c = $script:TaCtl
            if ($null -eq $c) { return "window not open" }
            if ($null -eq $c.Bars) { return "no daily bars loaded" }
            if ($c.TGrid.Rows.Count -lt 8) { return "only $($c.TGrid.Rows.Count) signal rows" }
            $c.Chart.Refresh()
            $c.Dlg.Width = $c.Dlg.Width + 40
            if ($c.FGrid.Rows.Count -lt 1) { return "no fundamentals rows" }
            return ""
        } 9000
    } 11000
    Invoke-SmokeStep "Compact with depot line" {
        $script:Config.CompactShow = "Depot,Spark,DayAbs"
        Apply-Layout "Compact"; & $pump; Update-MarketStatusUi
        Apply-Layout "Ticker"; & $pump
        $script:Config.CompactShow = "DayAbs,Ext,Spark,Market"
        Apply-Layout "Standard"; & $pump
    }
    Invoke-SmokeStep "Grid edit" {
        Set-ActiveTab -TabName "Portfolio"; & $pump
        if ($dgvPortfolio.Rows.Count -gt 0) {
            $dgvPortfolio.CurrentCell = $dgvPortfolio.Rows[0].Cells["Shares"]
            [void]$dgvPortfolio.BeginEdit($true)
            $dgvPortfolio.CurrentCell.Value = "12"
            [void]$dgvPortfolio.EndEdit()
            & $pump
            [void](Invoke-Undo)
        }
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Depot switch" {
        $script:Config.Depots = @([PSCustomObject]@{ Id = "smoke"; Name = "Smoke" })
        Switch-Depot "smoke"; & $pump
        Switch-Depot ""; & $pump
    }
    Invoke-SmokeStep "Undo" {
        $script:Alerts.Add([PSCustomObject]@{ Id = "x"; Ticker = "AAPL"; Condition = ">="; TargetPrice = 1.0; Currency = "EUR"; Triggered = $false; Note = ""; RearmMin = 0; TriggeredAt = ""; ExpiresAt = ""; Peak = 0.0; Push = $true })
        Refresh-WatchlistAndAlerts
        $lstAlerts.SelectedIndex = $script:Alerts.Count - 1
        $btnDelAlert.PerformClick()
        [void](Invoke-Undo)
    }
    Invoke-SmokeStep "Click-through" { Set-ClickThrough $true; Set-ClickThrough $false }
    Invoke-SmokeStep "Backup" { [void](Backup-DataFiles -Reason "smoke"); Invoke-DailyBackup }
    Invoke-SmokeStep "English main window" { $script:Config.Language = "EN"; Apply-Language $form; Apply-Language $trayMenu; Apply-Language $chartContextMenu; Update-AllUiViews; & $pump }
    Invoke-SmokeStep "English settings" { Show-SettingsDialog } 2500
    Invoke-SmokeStep "English analysis" { Show-AnalysisDialog -Page "Div" } 2500
    Invoke-SmokeStep "English palette" { Show-CommandPalette -Initial "NVDA " } 2000
    Invoke-SmokeStep "English help text" { Show-ShortcutHelp } 2000
    $script:Config.Language = "DE"
    # v5.2: design styles, with screenshots for the review (TW_SMOKE_SHOTS = folder)
    $shot = {
        param([string]$Name, $Win = $null)
        $dirS = [string]$env:TW_SMOKE_SHOTS
        if (-not $dirS) { return }
        if (-not (Test-Path $dirS)) { New-Item -ItemType Directory -Path $dirS -Force | Out-Null }
        $wf = if ($null -ne $Win) { $Win } else { $form }
        try { $wf.Activate() } catch { }
        for ($k = 0; $k -lt 6; $k++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 60 }
        $b = $wf.Bounds
        $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
        $gS = [System.Drawing.Graphics]::FromImage($bmp)
        try { $gS.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size) } catch { $gS.Dispose(); $gS = $null; $wf.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height))) }
        if ($null -ne $gS) { $gS.Dispose() }
        $bmp.Save((Join-Path $dirS ($Name + ".png")), [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
    Invoke-SmokeStep "Design styles" {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.SetBounds($wa.X, $wa.Y, [math]::Min($wa.Width, 1600), [math]::Min($wa.Height, 1000))
        Apply-Layout "Terminal"; Set-ActiveTab -TabName "Watchlist"; & $pump
        $script:Config.Theme = "Dark"; [void](Invoke-TerminalCommand "STYLE REFINED"); & $pump
        if ($script:UiSpec.Fresh) { throw "STYLE REFINED did not switch" }
        & $shot "01-refined-dark-terminal"
        [void](Invoke-TerminalCommand "STYLE FRESH"); & $pump
        if (-not $script:UiSpec.Fresh) { throw "STYLE FRESH did not switch" }
        if ($script:IconFont -and $btnSettings.Text -ne [string][char]0xE713) { throw "settings button has no icon ('$($btnSettings.Text)')" }
        $want = S ([math]::Round([int]$script:UiSpec.RowH * $script:GridRowScale))
        if ($dgvWatchlist.RowTemplate.Height -ne $want) { throw "row height $($dgvWatchlist.RowTemplate.Height), expected $want" }
        $pnlChartCanvas.Refresh(); $viewWatch.Refresh(); $btnRefreshNow.Refresh()
        & $shot "02-fresh-dark-terminal"
        $script:Config.Theme = "Light"; Apply-ThemeToAllControls; & $pump
        & $shot "03-fresh-light-terminal"
        $script:Config.Theme = "Graphite"; $script:Config.ZebraRows = $true; $script:Config.RowDensity = "Comfortable"; $script:Config.AccentColor = "Windows"; Apply-ThemeToAllControls; & $pump
        if ($null -eq $script:Pal.Warn) { throw "palette has no Warn colour" }
        & $shot "04-fresh-graphite-zebra-windows-accent"
        Apply-Layout "Standard"; Set-ActiveTab -TabName "Portfolio"; & $pump
        & $shot "05-fresh-graphite-portfolio"
        $script:Config.UseIcons = $false; Apply-Icons
        if ($btnSettings.Text -ne [string][char]0x2699) { throw "icons off did not restore the text" }
        $script:Config.UseIcons = $true
        $script:Config.Theme = "Dark"; $script:Config.ZebraRows = $false; $script:Config.RowDensity = "Normal"; $script:Config.AccentColor = "Sky"
        [void](Invoke-TerminalCommand "STYLE REFINED")
        Apply-Layout "Compact"; & $pump
        $script:Config.TapeSpeed = "Fast"; for ($k = 0; $k -lt 10; $k++) { Start-Sleep -Milliseconds 20; & $pump }
        & $shot "06-refined-compact-tape"
        $script:Config.TapeSpeed = "Normal"
        Apply-Layout "Terminal"; Set-ActiveTab -TabName "Watchlist"; & $pump
    } 20000
    $script:SmokeShot = $shot
    [void](Invoke-TerminalCommand "STYLE FRESH")
    Invoke-SmokeStep "Design ticker analysis" { & $probeRun { Show-TickerAnalysis "NVDA" } { & $script:SmokeShot "07-fresh-ticker-analysis" ([System.Windows.Forms.Form]::ActiveForm); "" } 8000 } 10000
    Invoke-SmokeStep "Design settings" { & $probeRun { Show-SettingsDialog } { & $script:SmokeShot "08-fresh-settings" ([System.Windows.Forms.Form]::ActiveForm); "" } 1200 } 2500
    Invoke-SmokeStep "Design analysis" { & $probeRun { Show-AnalysisDialog -Page "Bench" } { & $script:SmokeShot "09-fresh-analysis-bench" ([System.Windows.Forms.Form]::ActiveForm); "" } 9000 } 11000
    [void](Invoke-TerminalCommand "STYLE REFINED")
    Invoke-SmokeStep "Final refresh" { Update-AllUiViews; & $pump }

    $rep = [PSCustomObject]@{
        PowerShell = $PSVersionTable.PSVersion.ToString(); Version = $script:AppVersion
        Steps = $script:SmokeSteps.ToArray(); Failures = $script:SmokeFailures.ToArray(); Notes = $script:SmokeNotes.ToArray()
    }
    try { [IO.File]::WriteAllText([string]$env:TW_SMOKE_TEST, ($rep | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8) } catch { }
    $script:SmokeExit = $script:SmokeFailures.Count
    $trayIcon.Visible = $false
    $form.Close()
}

$script:SmokeExit = 99
if ($script:SmokeMode) {
    $script:SmokeStarter = New-Object System.Windows.Forms.Timer
    $script:SmokeStarter.Interval = 3000
    $script:SmokeStarter.Add_Tick({
        $script:SmokeStarter.Stop()
        try { Invoke-SmokeTest } catch {
            $script:SmokeFailures.Add("Smoke runner: $($_.Exception.Message) @ line $($_.InvocationInfo.ScriptLineNumber)")
            try { [IO.File]::WriteAllText([string]$env:TW_SMOKE_TEST, (@{ Failures = $script:SmokeFailures.ToArray(); Steps = $script:SmokeSteps.ToArray() } | ConvertTo-Json -Depth 5)) } catch { }
            $script:SmokeExit = 98
            $form.Close()
        }
    })
    $form.Add_Shown({ $script:SmokeStarter.Start() })
}

# v4.7: English mode for the main window and its menus
try { Apply-Language $form; Apply-Language $trayMenu; Apply-Language $chartContextMenu } catch { Write-WidgetLog "Language: $($_.Exception.Message)" "WARN" }

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
if ($script:SmokeMode) { exit ([int]$script:SmokeExit) }
