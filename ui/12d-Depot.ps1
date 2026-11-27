# TerminalWidget UI part 12d (Goals, costs, watchlist CSV, V8.0) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM.

# ==============================================================================
# fees and interest per year and depot
# ==============================================================================
function Get-DepotBookings {
    # bookings and cash entries of one depot, read from its files (read only)
    param([string]$Id)
    if ($Id -eq [string]$script:Config.ActiveDepot) {
        return @{ Transactions = @($script:Transactions.ToArray()); Cash = @($script:Cash.Entries.ToArray()) }
    }
    $dir = if ($Id) { Join-Path $script:DepotDir $Id } else { $script:DataDir }
    $tx = @(Load-JsonState -Path (Join-Path $dir "transactions.json") -DefaultValue @() | Where-Object { $null -ne $_ -and $_.Type })
    $cash = Load-JsonState -Path (Join-Path $dir "cash.json") -DefaultValue $null
    return @{ Transactions = $tx; Cash = @($(if ($null -ne $cash) { @($cash.Entries) | Where-Object { $null -ne $_ } })) }
}

function Get-FeeRows {
    $base = [string]$script:Config.Currency
    $fb = @{}
    foreach ($k in $script:FxFromEur.Keys) { $fb[$k] = [double]$script:FxFromEur[$k] }
    $hist = Get-FxHistoryMap
    $priv = [bool]$script:Config.PrivacyMode
    $money = { param([double]$v) Protect-Amount -Text ("{0:N2}" -f $v) -On $priv }
    $rows = @(); $approx = $false
    $totals = @{}
    foreach ($d in @(Get-DepotList)) {
        $b = Get-DepotBookings -Id ([string]$d.Id)
        foreach ($y in @(Get-FeeOverview -Transactions $b.Transactions -CashEntries $b.Cash -Base $base -History $hist -FallbackFromEur $fb)) {
            if ($y.Approx) { $approx = $true }
            $rows += [PSCustomObject]@{ Year = $y.Year; Depot = [string]$d.Name; Data = $y }
            if (-not $totals.ContainsKey($y.Year)) { $totals[$y.Year] = @{ O = 0.0; A = 0.0; I = 0.0; N = 0; Depots = 0 } }
            $t = $totals[$y.Year]; $t.O += $y.OrderFees; $t.A += $y.AccountFees; $t.I += $y.Interest; $t.N += $y.Orders; $t.Depots++
        }
    }
    $out = @()
    foreach ($yr in @($totals.Keys | Sort-Object -Descending)) {
        foreach ($r in @($rows | Where-Object { $_.Year -eq $yr })) {
            $x = $r.Data
            $out += ,@([string]$yr, $r.Depot, [string]$x.Orders, (& $money $x.OrderFees), (& $money $x.AccountFees), (& $money ($x.OrderFees + $x.AccountFees)), (& $money $x.Interest))
        }
        $t = $totals[$yr]
        if ($t.Depots -gt 1) { $out += ,@([string]$yr, (Tr "Alle Depots"), [string]$t.N, (& $money $t.O), (& $money $t.A), (& $money ($t.O + $t.A)), (& $money $t.I)) }
    }
    return @{ Rows = $out; Approx = $approx; Base = $base }
}

function Get-BrokerFeeRows {
    # all depots together, per year and broker (10.4)
    $base = [string]$script:Config.Currency
    $fb = @{}
    foreach ($k in $script:FxFromEur.Keys) { $fb[$k] = [double]$script:FxFromEur[$k] }
    $priv = [bool]$script:Config.PrivacyMode
    $money = { param([double]$v) Protect-Amount -Text ("{0:N2}" -f $v) -On $priv }
    $all = @(foreach ($d in @(Get-DepotList)) { (Get-DepotBookings -Id ([string]$d.Id)).Transactions })
    $rows = @(); $approx = $false
    foreach ($r in @(Get-BrokerFeeOverview -Transactions $all -Base $base -History (Get-FxHistoryMap) -FallbackFromEur $fb)) {
        if ($r.Approx) { $approx = $true }
        $name = if ($r.Broker) { $r.Broker } else { Tr "(ohne Broker)" }
        $rows += ,@([string]$r.Year, $name, [string]$r.Orders, (& $money $r.Volume), (& $money $r.Fees), (& $money $r.PerOrder), ("{0:N2} %" -f $r.Pct))
    }
    return @{ Rows = $rows; Approx = $approx; Base = $base }
}

function Set-GoalsGridMode {
    # same seven columns, other headings
    param([bool]$ByBroker)
    $g = $script:GoalCtl.Grid
    $heads = if ($ByBroker) { @("Jahr", "Broker", "Orders", "Volumen", "Ordergebühren", "je Order", "vom Volumen") }
             else { @("Jahr", "Depot", "Orders", "Ordergebühren", "Kontogebühren", "Kosten gesamt", "Zinsen") }
    for ($i = 0; $i -lt $heads.Count; $i++) { $g.Columns[$i].HeaderText = Tr $heads[$i] }
}

# ==============================================================================
# goals
# ==============================================================================
function Get-DividendForecast {
    # expected dividends of the next 12 months for one depot (default: the open one), from the
    # same data as the analysis page. Loading = positions without data yet.
    param([string]$Base, $Holdings = $null)
    if ($null -eq $Holdings) { $Holdings = $script:Portfolio }
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $res = @{ Income = 0.0; Loading = 0; Positions = 0 }
    foreach ($k in @($Holdings.Keys)) {
        $sym = ([string]$k).ToUpper()
        $sh = [double]$Holdings[$k].Shares
        if ($sh -le 0) { continue }
        $res.Positions++
        $dh = $script:DivHist[$sym]
        if ($null -eq $dh -or $dh.Failed) { $res.Loading++; continue }
        $st = Get-DividendStats -Dividends $dh.Divs -AsOf $today
        if ($null -eq $st) { continue }
        $cur = if ($dh.Currency) { [string]$dh.Currency } else { Get-InstrumentCurrency $sym }
        if (-not $cur) { $cur = [string]$Holdings[$k].Currency }
        foreach ($pj in @(Get-DividendProjection -Dividends $dh.Divs -AsOf $today -Stats $st)) {
            $res.Income += [double](Convert-CurrencyValue -Amount ([double]$pj.Amount * $sh) -FromCurrency $cur -ToCurrency $Base)
        }
    }
    return $res
}

function Get-DepotHoldings {
    # symbol -> position of one depot; the open one from memory, others from their file (read only)
    param([string]$Id)
    if ($Id -eq [string]$script:Config.ActiveDepot) { return $script:Portfolio }
    $dir = if ($Id) { Join-Path $script:DepotDir $Id } else { $script:DataDir }
    $res = @{}
    $raw = Load-JsonState -Path (Join-Path $dir "portfolio.json") -DefaultValue $null
    if ($null -ne $raw) {
        foreach ($prop in $raw.PSObject.Properties) {
            if ($null -eq $prop.Value) { continue }
            $cur = Get-NormalizedCurrencyCode ([string]$prop.Value.Currency)
            if (-not $cur) { $cur = "EUR" }
            $res[$prop.Name.ToUpper()] = [PSCustomObject]@{ Ticker = $prop.Name.ToUpper(); Shares = [double]$prop.Value.Shares; AvgPrice = [double]$prop.Value.AvgPrice; Currency = $cur }
        }
    }
    return $res
}

function Get-HoldingsValue {
    # market value in Base. Missing = positions without a quote or exchange rate (then Value is only a part)
    param($Holdings, [string]$Base)
    $res = @{ Value = 0.0; Missing = 0; Cached = 0; Count = 0 }
    foreach ($k in @($Holdings.Keys)) {
        $sym = ([string]$k).ToUpper()
        $sh = [double]$Holdings[$k].Shares
        if ($sh -le 0) { continue }
        $res.Count++
        $q = $script:QuoteStore[$sym]
        if ($null -eq $q -or [double]$q.Price -le 0) { $res.Missing++; continue }
        $cur = [string]$q.Currency
        if ($cur -ne "EUR" -and $cur -ne $Base -and -not $script:FxFromEur.ContainsKey($cur)) { $res.Missing++; continue }
        if ([bool]$q.FromCache) { $res.Cached++ }
        $res.Value += $sh * (Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency $cur -ToCurrency $Base)
    }
    return $res
}

function Get-GoalRows {
    # one row per depot and, with several depots, one for all together (Id "*")
    param([string]$Base)
    $rows = @()
    $sum = @{ Value = 0.0; Missing = 0; Cached = 0; Income = 0.0; Loading = 0 }
    foreach ($d in @(Get-DepotList)) {
        $h = Get-DepotHoldings -Id ([string]$d.Id)
        $v = Get-HoldingsValue -Holdings $h -Base $Base
        $f = Get-DividendForecast -Base $Base -Holdings $h
        $goal = Get-DepotGoal -Goals $script:Config.DepotGoals -Id ([string]$d.Id)
        $rows += [PSCustomObject]@{ Id = [string]$d.Id; Name = [string]$d.Name; Value = $v.Value; Missing = $v.Missing; Cached = $v.Cached; ValueGoal = $goal.Value; Income = $f.Income; Loading = $f.Loading; DividendGoal = $goal.Dividend }
        $sum.Value += $v.Value; $sum.Missing += $v.Missing; $sum.Cached += $v.Cached; $sum.Income += $f.Income; $sum.Loading += $f.Loading
    }
    if ($rows.Count -gt 1) {
        $rows += [PSCustomObject]@{ Id = "*"; Name = (Tr "Alle Depots"); Value = $sum.Value; Missing = $sum.Missing; Cached = $sum.Cached; ValueGoal = [double]$script:Config.GoalAllValue; Income = $sum.Income; Loading = $sum.Loading; DividendGoal = [double]$script:Config.GoalAllDividend }
    }
    return $rows
}

function Start-GoalDataLoad {
    # quotes for symbols that only other depots hold (the regular refresh does not
    # ask for them) and dividend histories for all depots, both in the background
    $all = @{}
    foreach ($d in @(Get-DepotList)) {
        $h = Get-DepotHoldings -Id ([string]$d.Id)
        foreach ($k in @($h.Keys)) { if ([double]$h[$k].Shares -gt 0) { $all[([string]$k).ToUpper()] = $h[$k] } }
    }
    $live = @{}
    foreach ($s in @(@($script:Portfolio.Keys) + @($script:Config.Watchlist))) { if ($s) { $live[([string]$s).ToUpper()] = $true } }
    $urls = @{}
    foreach ($s in @($all.Keys)) { if (-not $live.ContainsKey($s)) { $urls[$s] = Get-ChartUrl -Symbol $s -Interval "1h" -Range "5d" -PrePost } }
    if ($urls.Count -gt 0) {
        Start-FetchJob -Urls @($urls.Values) -MaxConcurrency 4 -Context @{ Urls = $urls } -OnComplete {
            param($Box, $Ctx)
            foreach ($s in @($Ctx.Urls.Keys)) {
                $r = Get-ChartResult $Box.Results[$Ctx.Urls[$s]]
                if ($null -eq $r) { continue }
                try { Update-QuoteFromResult -Sym $s -R $r -RsiPeriod ([int]$script:Config.RsiPeriod) }
                catch { Write-WidgetLog "Goal quote ${s}: $($_.Exception.Message)" "WARN" }
            }
            if ($null -ne $script:GoalCtl) { Update-GoalsView }
        }
    }
    Start-DividendLoad -Positions $all
}

function Update-GoalsView {
    $gc = $script:GoalCtl
    if ($null -eq $gc) { return }
    $base = [string]$script:Config.Currency
    $priv = [bool]$script:Config.PrivacyMode
    $money = { param([double]$v) Protect-Amount -Text ("{0:N0}" -f $v) -On $priv }
    $dash = [string][char]0x2013
    $rows = @(Get-GoalRows -Base $base)
    $gg = $gc.Goals
    # goal cells are only filled when the rows are new: a later refresh must not overwrite typing
    $fresh = ($gg.Rows.Count -ne $rows.Count)
    if ($fresh) {
        $gg.Rows.Clear()
        foreach ($r in $rows) {
            $i = $gg.Rows.Add()
            $gg.Rows[$i].Tag = $r.Id
            $gg.Rows[$i].Cells["Depot"].Value = $r.Name
            foreach ($pair in @(@("ValueGoal", $r.ValueGoal), @("DivGoal", $r.DividendGoal))) {
                $gg.Rows[$i].Cells[$pair[0]].Value = if ($priv) { Protect-Amount -Text "0" -On $true } elseif ([double]$pair[1] -gt 0) { ([double]$pair[1]).ToString("0.##") } else { "" }
            }
            if ($r.Id -eq "*") { $gg.Rows[$i].DefaultCellStyle.Font = $fontUiBold }
        }
    }
    $missing = 0; $cached = 0; $loading = 0
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]; $row = $gg.Rows[$i]
        if ($r.Id -ne "*") { $missing += $r.Missing; $cached += $r.Cached; $loading += $r.Loading }
        # incomplete sums are not shown as a number: they would look like a loss
        $row.Cells["Value"].Value = if ($r.Missing -gt 0) { $dash } else { (& $money $r.Value) + $(if ($r.Cached -gt 0) { " *" } else { "" }) }
        $row.Cells["Income"].Value = (& $money $r.Income) + $(if ($r.Loading -gt 0) { " +" } else { "" })
        $saved = if ($r.Id -eq "*") { @([double]$script:Config.GoalAllValue, [double]$script:Config.GoalAllDividend) } else { $g0 = Get-DepotGoal -Goals $script:Config.DepotGoals -Id $r.Id; @($g0.Value, $g0.Dividend) }
        $pv = if ($r.Missing -gt 0) { $null } else { Get-GoalProgress -Current $r.Value -Target $saved[0] }
        $pd = Get-GoalProgress -Current $r.Income -Target $saved[1]
        foreach ($pair in @(@("ValuePct", $pv), @("DivPct", $pd))) {
            $cell = $row.Cells[$pair[0]]
            $cell.Tag = $pair[1]
            $cell.Value = if ($null -eq $pair[1]) { "" } else { "{0:N0} %" -f $pair[1].Pct }
            $cell.ToolTipText = if ($null -eq $pair[1]) { "" } elseif ($pair[1].Reached) { Tr "Ziel erreicht" } else { (Tr "es fehlen") + " " + (& $money $pair[1].Remaining) + " " + $base }
        }
    }
    $got = [double](Get-RealizedTotal -Year (Get-Date).Year -Type "Dividende")
    $info = @((Tr "In diesem Depot dieses Jahr gebucht: {0}") -f (Protect-Amount -Text ("{0:N2} {1}" -f $got, $base) -On $priv))
    if ($missing -gt 0) { $info += (Tr "{0} Position(en) ohne Kurs") -f $missing }
    if ($cached -gt 0) { $info += Tr "* mit zwischengespeicherten Kursen" }
    if ($loading -gt 0) { $info += (Tr "+ Dividendendaten fehlen noch für {0} Position(en)") -f $loading }
    $gc.Lbl3.Text = $info -join "   |   "
    $gg.ClearSelection()
    $gg.Invalidate()

    $byBroker = ($gc.Group.SelectedIndex -eq 1)
    Set-GoalsGridMode $byBroker
    $fr = if ($byBroker) { Get-BrokerFeeRows } else { Get-FeeRows }
    $gc.Grid.Rows.Clear()
    foreach ($r in @($fr.Rows)) { [void]$gc.Grid.Rows.Add([object[]]$r) }
    $gc.Note.Text = if ($byBroker) { (Tr "Beträge in {0}. Nur Käufe und Verkäufe, alle Depots. Broker vergibst du in der Transaktionshistorie.") -f $fr.Base }
                    else { (Tr "Beträge in {0}. Gebühren aus Buchungen und Cash-Konto, Zinsen aus dem Cash-Konto.") -f $fr.Base }
    if ($fr.Approx) { $gc.Note.Text += " " + (Tr "Teilweise mit heutigem Wechselkurs gerechnet (Tageskurse lädt die Analyse).") }
}

function Save-GoalsFromGrid {
    # -> "" or an error text; nothing is saved when one cell is not a number
    $gg = $script:GoalCtl.Goals
    [void]$gg.EndEdit()
    $new = @()
    foreach ($row in @($gg.Rows)) {
        $vals = @()
        foreach ($col in @("ValueGoal", "DivGoal")) {
            $t = ([string]$row.Cells[$col].Value).Trim()
            if ($t -and -not (Test-DecimalInput $t)) { return ((Tr "Bitte eine Zahl eingeben.") + " (" + [string]$row.Cells["Depot"].Value + ": " + $t + ")") }
            $vals += [math]::Max(0.0, $(if ($t) { Parse-DecimalInput $t } else { 0.0 }))
        }
        $new += ,@([string]$row.Tag, $vals[0], $vals[1])
    }
    foreach ($n in $new) {
        if ($n[0] -eq "*") { $script:Config.GoalAllValue = [double]$n[1]; $script:Config.GoalAllDividend = [double]$n[2] }
        else { $script:Config.DepotGoals = Set-DepotGoal -Goals $script:Config.DepotGoals -Id $n[0] -Value $n[1] -Dividend $n[2] }
    }
    Save-Config
    return ""
}

function Write-GoalBarCell {
    # percent cells of the goal table: number with a bar underneath
    param($Grid, $E)
    if ($E.RowIndex -lt 0 -or $E.ColumnIndex -lt 0) { return }
    $name = $Grid.Columns[$E.ColumnIndex].Name
    if ($name -ne "ValuePct" -and $name -ne "DivPct") { return }
    $prog = $Grid.Rows[$E.RowIndex].Cells[$E.ColumnIndex].Tag
    if ($null -eq $prog) { return }
    $E.PaintBackground($E.CellBounds, $false)
    $b = $E.CellBounds
    $x = $b.X + (S 6); $w = [math]::Max((S 10), $b.Width - (S 12))
    $col = if ($prog.Reached) { $colGreen } else { $script:Pal.Accent }
    $track = New-Object System.Drawing.SolidBrush($script:Pal.Input); $fill = New-Object System.Drawing.SolidBrush($col)
    try {
        $E.Graphics.FillRectangle($track, $x, ($b.Bottom - (S 7)), $w, (S 4))
        $E.Graphics.FillRectangle($fill, $x, ($b.Bottom - (S 7)), [int]($w * $prog.BarPct / 100.0), (S 4))
        $r = New-Object System.Drawing.Rectangle($x, $b.Y, $w, ($b.Height - (S 7)))
        [System.Windows.Forms.TextRenderer]::DrawText($E.Graphics, [string]$E.FormattedValue, $fontUi, $r, $script:Pal.Text, [System.Windows.Forms.TextFormatFlags]"Right, VerticalCenter")
    } finally { $track.Dispose(); $fill.Dispose() }
    $E.Handled = $true
}

function Show-GoalsCostsDialog {
    $dlg = New-DialogForm -Title "Ziele und Kosten" -W (S 760) -H (S 540) -Key "GoalsCosts2"
    $base = [string]$script:Config.Currency
    $priv = [bool]$script:Config.PrivacyMode
    [void](New-V8Label $dlg ((Tr "Ziele je Depot in {0} - in die Ziel-Spalten tippen (leer = kein Ziel)") -f $base) (S 12) (S 14) (S 470))
    $bSave = New-V8Button $dlg (Tr "Ziele speichern") (S 490) (S 8) (S 130)
    $bCalc = New-V8Button $dlg (Tr "Neu berechnen") (S 628) (S 8) (S 120)
    $gg = New-V8Grid $dlg (S 12) (S 42) (S 736) (S 150) -Editable
    $gg.AllowUserToResizeRows = $false
    $gg.RowTemplate.Height = S 28
    foreach ($c in @(@("Depot", "Depot", 120), @("Value", "Depotwert", 90), @("ValueGoal", "Ziel Wert", 85), @("ValuePct", "Stand", 90), @("Income", "Div. 12 Monate", 100), @("DivGoal", "Ziel Dividenden", 95), @("DivPct", "Stand ", 90))) {
        if ($c[0] -in @("ValueGoal", "DivGoal")) { Add-V8Column $gg $c[0] $c[1] $c[2] } else { Add-V8Column $gg $c[0] $c[1] $c[2] -ReadOnly }
    }
    foreach ($n in @("Value", "ValueGoal", "Income", "DivGoal")) { $gg.Columns[$n].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    foreach ($n in @("ValueGoal", "DivGoal")) { $gg.Columns[$n].DefaultCellStyle.BackColor = $script:Pal.Input; $gg.Columns[$n].ReadOnly = $priv }
    $bSave.Enabled = (-not $priv)
    $gg.Add_CellPainting({ param($s, $e) Write-GoalBarCell -Grid $s -E $e })
    $l3 = New-V8Label $dlg "" (S 12) (S 198) (S 736) (S 32) -Muted
    [void](New-V8Label $dlg (Tr "Kosten und Zinsen je Jahr") (S 12) (S 238) (S 400))
    $cbGroup = New-V8Combo $dlg @((Tr "je Depot"), (Tr "je Broker")) (Tr "je Depot") (S 598) (S 233) (S 150)
    $cbGroup.AccessibleName = Tr "Gruppierung"
    $g = New-V8Grid $dlg (S 12) (S 262) (S 736) (S 222)
    $cols = @(@("Year", "Jahr", 50), @("Depot", "Depot", 120), @("Orders", "Orders", 50), @("OrderFees", "Ordergebühren", 90), @("AccFees", "Kontogebühren", 90), @("Fees", "Kosten gesamt", 90), @("Interest", "Zinsen", 80))
    foreach ($c in $cols) { Add-V8Column $g $c[0] $c[1] $c[2] -ReadOnly }
    foreach ($n in @("Orders", "OrderFees", "AccFees", "Fees", "Interest")) { $g.Columns[$n].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    $note = New-V8Label $dlg "" (S 12) (S 492) (S 620) (S 40) -Muted
    $no = New-V8Button $dlg (Tr "Schließen") (S 652) (S 502) (S 96)
    $no.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.CancelButton = $no
    $script:GoalCtl = @{ Dlg = $dlg; Goals = $gg; Lbl3 = $l3; Grid = $g; Note = $note; Group = $cbGroup }
    $cbGroup.Add_SelectedIndexChanged({ Update-GoalsView })
    $bSave.Add_Click({
        $err = Save-GoalsFromGrid
        if ($err) { Show-InfoBox $err (Tr "Ziele und Kosten"); return }
        Update-GoalsView
        Set-TransientStatus (Tr "Ziele gespeichert") 3
    })
    $bCalc.Add_Click({ if (-not $script:SmokeMode) { Start-GoalDataLoad }; Update-GoalsView })
    $dlg.Add_Shown({
        if (-not $script:SmokeMode) { Start-GoalDataLoad }
        Update-GoalsView
    })
    # dividend data arrives in the background: look again for a short while
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 4000
    $script:GoalTicks = 0
    $timer.Add_Tick({ param($sender, $e) $script:GoalTicks++; if ($null -ne $script:GoalCtl -and -not $script:GoalCtl.Goals.IsCurrentCellInEditMode) { Update-GoalsView }; if ($script:GoalTicks -ge 3) { $sender.Stop() } })
    $timer.Start()
    [void]$dlg.ShowDialog($form)
    $timer.Stop(); $timer.Dispose()
    $dlg.Dispose()
    $script:GoalCtl = $null
}

# ==============================================================================
# watchlist as CSV
# ==============================================================================
function Get-WatchlistCsvRows {
    foreach ($w in @($script:Config.Watchlist)) {
        $u = ([string]$w).ToUpper()
        if (-not $u) { continue }
        $groups = @($script:Config.WatchGroups | Where-Object { $null -ne $_ -and $_.Name -and @($_.Symbols | ForEach-Object { ([string]$_).ToUpper() }) -contains $u } | ForEach-Object { [string]$_.Name })
        $ot = Get-OwnTarget $u
        [PSCustomObject]@{ Ticker = $u; Groups = $groups; Target = $(if ($null -ne $ot) { [double]$ot.Price } else { 0.0 }); Currency = $(if ($null -ne $ot) { [string]$ot.Currency } else { "" }); Note = (Get-TickerNote $u) }
    }
}

function Export-WatchlistCsv {
    param([string]$Path = "")
    if (-not $Path) {
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "CSV (*.csv)|*.csv"; $sfd.FileName = "TerminalWidget-Watchlist.csv"
        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $Path = $sfd.FileName }
        $sfd.Dispose()
        if (-not $Path) { return }
    }
    try {
        $rows = @(Get-WatchlistCsvRows)
        [System.IO.File]::WriteAllText($Path, (ConvertTo-WatchlistCsv $rows), (New-Object System.Text.UTF8Encoding($true)))
        Set-TransientStatus ((Tr "{0} Ticker exportiert") -f $rows.Count) 4
    } catch { Show-InfoBox ((Tr "Export fehlgeschlagen:") + " " + $_.Exception.Message) "Watchlist" }
}

function Import-WatchlistRows {
    # only adds: nothing is removed from the watchlist or from groups; a target
    # price or note in the file replaces the one stored for that ticker
    param($Rows)
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($w in @($script:Config.Watchlist)) { if ($w) { $list.Add(([string]$w).ToUpper()) } }
    $added = 0
    foreach ($r in @($Rows)) {
        $u = [string]$r.Ticker
        if (-not $list.Contains($u)) { $list.Add($u); $added++ }
        foreach ($gr in @($r.Groups)) { $script:Config.WatchGroups = Set-WatchGroupMember -Groups @($script:Config.WatchGroups) -Group $gr -Symbol $u -In $true }
        if ([double]$r.Target -gt 0) {
            $cur = if ([string]$r.Currency) { [string]$r.Currency } else { Get-PriceCurrency $u }
            Set-OwnTarget -Sym $u -Price ([double]$r.Target) -Currency $cur
        }
        if ([string]$r.Note) { Set-TickerNote -Ticker $u -Text ([string]$r.Note) }
    }
    $script:Config.Watchlist = $list.ToArray()
    Save-Config
    return $added
}

function Import-WatchlistCsv {
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "CSV (*.csv;*.txt)|*.csv;*.txt"
    $path = ""
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $path = $ofd.FileName }
    $ofd.Dispose()
    if (-not $path) { return }
    try {
        if ((Get-Item $path).Length -gt 1MB) { throw (Tr "Die Datei ist zu groß.") }
        $res = ConvertFrom-WatchlistCsv ([System.IO.File]::ReadAllText($path))
    } catch { Show-InfoBox ((Tr "Datei nicht lesbar:") + " " + $_.Exception.Message) "Watchlist"; return }
    if (@($res.Rows).Count -eq 0) { Show-InfoBox (Tr "Keine Ticker gefunden. Erwartet wird eine Kopfzeile mit der Spalte 'Ticker'.") "Watchlist"; return }
    $have = @($script:Config.Watchlist | ForEach-Object { ([string]$_).ToUpper() })
    $new = @($res.Rows | Where-Object { $have -notcontains $_.Ticker }).Count
    $msg = (Tr "{0} Zeilen: {1} neue Ticker, {2} übersprungen.`r`nZielkurse und Notizen aus der Datei ersetzen vorhandene. Es wird nichts gelöscht. Importieren?") -f @($res.Rows).Count, $new, $res.Skipped
    if (-not (Confirm-Action -Text $msg -Title "Watchlist")) { return }
    [void](Backup-DataFiles -Reason "vor_watchlist_import")
    $n = Import-WatchlistRows -Rows $res.Rows
    Update-WatchGroupCombo
    Refresh-AllMarketData
    Update-AllUiViews
    Set-TransientStatus ((Tr "{0} neue Ticker importiert") -f $n) 5
}

# ---- menu ----
Add-BarLine $mbPort
[void](Add-BarItem $mbPort "Ziele und Kosten ..." { Show-GoalsCostsDialog })
[void](Add-BarItem $mbPort "Watchlist exportieren (CSV) ..." { Export-WatchlistCsv })
[void](Add-BarItem $mbPort "Watchlist importieren (CSV) ..." { Import-WatchlistCsv })
