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
    [void](New-V8Label $dlg ((Tr "Ziele je Depot in {0} - in die Ziel-Spalten tippen (leer = kein Ziel)") -f $base) (S 12) (S 14) (S 342))
    $bSave = New-V8Button $dlg (Tr "Ziele speichern") (S 490) (S 8) (S 130)
    $bCalc = New-V8Button $dlg (Tr "Neu berechnen") (S 628) (S 8) (S 120)
    $bPlan = New-V8Button $dlg (Tr "Sparrechner ...") (S 360) (S 8) (S 122)
    $bPlan.Tag = $dlg
    $bPlan.Add_Click({ param($sender, $e) Show-SavingsCalcDialog -Owner $sender.Tag })
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

# ==============================================================================
# v11.4: one position in detail
# ==============================================================================
function Test-HasPosition {
    param([string]$Ticker)
    $sym = ([string]$Ticker).ToUpper()
    if (-not $sym) { return $false }
    if ($script:Portfolio.ContainsKey($sym)) { return $true }
    foreach ($t in $script:Transactions) { if (([string]$t.Ticker).ToUpper() -eq $sym) { return $true } }
    return $false
}

function Get-DepotShareOf {
    # share of one position in the depot value in percent (NaN without prices)
    param([string]$Ticker, [string]$Base)
    $sum = 0.0; $own = [double]::NaN
    foreach ($k in @($script:Portfolio.Keys)) {
        $px = Get-AnalysisPriceNow -Sym ([string]$k) -Base $Base
        if ([double]::IsNaN($px)) { continue }
        $v = [double]$script:Portfolio[$k].Shares * $px
        $sum += $v
        if (([string]$k).ToUpper() -eq $Ticker) { $own = $v }
    }
    if ($sum -le 0 -or [double]::IsNaN($own)) { return [double]::NaN }
    return $own / $sum * 100.0
}

function Update-PositionView {
    $c = $script:PosCtl
    if ($null -eq $c -or $c.Dlg.IsDisposed) { return }
    $sym = $c.Ticker
    $base = Get-AnalysisBase
    $fb = @{}
    foreach ($k in $script:FxFromEur.Keys) { $fb[$k] = [double]$script:FxFromEur[$k] }
    $pf = $script:Portfolio[$sym]
    $px = Get-AnalysisPriceNow -Sym $sym -Base $base
    $det = Get-PositionDetail -Transactions $script:Transactions.ToArray() -Ticker $sym -Base $base -History (Get-FxHistoryMap) -FallbackFromEur $fb `
        -Splits (Get-SplitMap) -PriceNow $px -PortfolioShares $(if ($null -ne $pf) { [double]$pf.Shares } else { -1.0 })
    $note = ""
    if (-not $det.HasBookings -and $null -ne $pf) {
        # no bookings: the figures of the portfolio editor (cost at today's rate)
        $det.Cost = Convert-CurrencyValue -Amount ([double]$pf.Shares * [double]$pf.AvgPrice) -FromCurrency ([string]$pf.Currency) -ToCurrency $base
        if ($det.Shares -gt 0) { $det.AvgCost = $det.Cost / $det.Shares }
        if (-not [double]::IsNaN($det.Value) -and $det.Cost -gt 0) { $det.Unreal = $det.Value - $det.Cost; $det.UnrealPct = $det.Unreal / $det.Cost * 100.0; $det.Total = $det.Unreal; $det.Pct = $det.UnrealPct }
        $note = "Keine Buchungen: Werte aus dem Portfolio-Editor, Einstand zum heutigen Wechselkurs."
    } elseif ($det.HasBookings -and $null -ne $pf -and [math]::Abs($det.BookedShares - [double]$pf.Shares) -gt 0.0001) {
        $note = "Das Portfolio zeigt eine andere Stückzahl als die Buchungen. Ergebnis und Einstand beruhen auf den Buchungen."
    }
    if ($det.Approx) { $note = ($note + " Teilweise mit heutigem statt historischem Wechselkurs gerechnet.").Trim() }
    $c.Detail = $det
    $priv = [bool]$script:Config.PrivacyMode
    $tiles = @(Get-PositionTiles -Detail $det -Base $base -Share (Get-DepotShareOf -Ticker $sym -Base $base) -Privacy $priv)
    foreach ($tl in $tiles) { $tl.Label = Tr-Status (Tr ([string]$tl.Label)); $tl.Sub = Tr-Status ([string]$tl.Sub) }
    $c.Tiles = $tiles
    $c.TilePanel.Invalidate()

    $q = $script:QuoteStore[$sym]
    $parts = @()
    if ($null -ne $q -and [double]$q.Price -gt 0) { $parts += ("{0} {1:N2} {2}  {3:+0.00;-0.00;0.00} %" -f (Tr "Kurs"), [double]$q.Price, [string]$q.Currency, [double]$q.ChangePct) }
    if ($det.FirstDate) { $parts += ("{0} {1} ({2} {3})" -f (Tr "erster Kauf"), (Format-IsoDateDe $det.FirstDate), $det.HoldDays, (Tr "Tage")) }
    $parts += ("{0} {1}" -f (Tr "Beträge in"), $base)
    $c.Head.Text = $parts -join "   ·   "
    $c.Note.Text = Tr $note

    $money = { param([double]$v) if ($priv) { Protect-Amount "0" $true } elseif ([math]::Abs($v) -lt 0.005) { "-" } else { "{0:N2}" -f $v } }
    $c.Years.Rows.Clear()
    foreach ($y in @($det.Years)) { [void]$c.Years.Rows.Add($y.Year, (& $money $y.Bought), (& $money $y.Sold), (& $money $y.Dividends), (& $money $y.Fees)) }
    $c.Brokers.Rows.Clear()
    foreach ($b in @($det.Brokers)) {
        $name = if ($b.Broker) { $b.Broker } else { Tr "ohne Angabe" }
        [void]$c.Brokers.Rows.Add($name, $(if ($priv) { Protect-Amount "0" $true } else { "{0:0.####}" -f $b.Shares }), $b.Orders, (& $money $b.Volume), (& $money $b.Fees))
    }
    $c.Bookings.Rows.Clear()
    foreach ($t in @($det.Bookings)) {
        [void]$c.Bookings.Rows.Add((Format-IsoDateDe ([string]$t.Date)), (Tr ([string]$t.Type)),
            $(if ($priv) { Protect-Amount "0" $true } elseif ([double]$t.Shares -gt 0) { "{0:0.####}" -f [double]$t.Shares } else { "-" }),
            $(if ($priv -and [string]$t.Type -eq "Dividende") { Protect-Amount "0" $true } else { "{0:N2}" -f [double]$t.Price }),
            $(if ($priv) { Protect-Amount "0" $true } else { "{0:N2}" -f [double]$t.Fee }), [string]$t.Currency, [string]$t.Broker, [string]$t.Note)
    }
    foreach ($g in @($c.Years, $c.Brokers, $c.Bookings)) { $g.ClearSelection() }
}

function Start-PositionRates {
    # historic exchange rates for the booking days (same numbers as the analysis)
    $c = $script:PosCtl
    if ($null -eq $c) { return }
    $own = @($script:Transactions | Where-Object { ([string]$_.Ticker).ToUpper() -eq $c.Ticker })
    if ($own.Count -eq 0) { return }
    $first = Get-EarliestBookingDate -Transactions $own
    if (-not $first) { return }
    $fromD = [DateTime]::ParseExact($first, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture).AddDays(-10)
    $curs = @(@($own | ForEach-Object { [string]$_.Currency }) + (Get-AnalysisBase))
    $urls = Get-AnalysisFxUrls -Currencies $curs -From $fromD.ToString("yyyy-MM-dd") -P1 ([DateTimeOffset]$fromD).ToUnixTimeSeconds() -P2 ([DateTimeOffset]((Get-Date).AddDays(1))).ToUnixTimeSeconds()
    if ($urls.Count -eq 0) { return }
    Start-FetchJob -Urls @($urls.Values) -MaxConcurrency 3 -Context @{ Fx = $urls; From = $fromD.ToString("yyyy-MM-dd") } -OnComplete {
        param($Box, $Ctx)
        Save-FxHistResults -Box $Box -FxUrls $Ctx.Fx -From $Ctx.From
        Update-PositionView
    }
}

function Show-PositionDialog {
    param([string]$Ticker, $Owner = $null)
    $sym = ([string]$Ticker).Trim().ToUpper()
    if (-not $sym -or $null -ne $script:PosCtl) { return }
    if (-not (Test-HasPosition $sym)) { Set-TransientStatus "$sym hat weder Position noch Buchungen" 4; return }
    $p = $script:Pal
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right
    try { Ensure-SplitsLoaded -Tickers @($sym) } catch { Write-WidgetLog "Position splits: $($_.Exception.Message)" "WARN" }
    $dlg = New-DialogForm -Title "Position - $sym" -W (S 940) -H (S 600) -Key "Position"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MaximizeBox = $true
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 820), (S 520))
    $dlg.KeyPreview = $true
    $dlg.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() } })

    $q = $script:QuoteStore[$sym]
    $name = if ($null -ne $q -and $q.LongName -and [string]$q.LongName -ne $sym) { "$sym  ·  $($q.LongName)" } else { $sym }
    $title = New-V8Label $dlg $name (S 12) (S 10) (S 916) (S 20)
    $title.Font = $fontUiBold; $title.AutoEllipsis = $true; $title.Anchor = $aT -bor $aL -bor $aR
    $head = New-V8Label $dlg "" (S 12) (S 31) (S 916) (S 18) -Muted
    $head.AutoEllipsis = $true; $head.Anchor = $aT -bor $aL -bor $aR
    $tp = New-Object System.Windows.Forms.Panel
    $tp.SetBounds((S 12), (S 56), (S 916), (S 120)); $tp.Anchor = $aT -bor $aL -bor $aR
    Enable-DoubleBuffering -Control $tp
    $tp.Add_Paint({ param($sender, $e) Write-KpiTiles -G $e.Graphics -Panel $sender -Tiles $(if ($null -eq $script:PosCtl) { @() } else { @($script:PosCtl.Tiles | Where-Object { $null -ne $_ }) }) })
    $tp.Add_Resize({ param($sender, $e) $sender.Invalidate() })
    $dlg.Controls.Add($tp)

    $mkGrid = {
        param($Cols, [int]$X, [int]$Y, [int]$W, [int]$H, $Anchor)
        $g = New-Object System.Windows.Forms.DataGridView
        $g.SetBounds($X, $Y, $W, $H); $g.Anchor = $Anchor
        Style-DataGrid -Grid $g
        foreach ($cd in $Cols) {
            $ci = $g.Columns.Add($cd[0], (Tr $cd[1]))
            $g.Columns[$ci].FillWeight = [float](S $cd[2])
            if ($cd[3]) { $g.Columns[$ci].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
        }
        $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
        $dlg.Controls.Add($g)
        return $g
    }
    [void](New-V8Label $dlg (Tr "Je Jahr") (S 12) (S 186) (S 200))
    [void](New-V8Label $dlg (Tr "Je Broker") (S 482) (S 186) (S 200))
    $years = & $mkGrid @(@("Year", "Jahr", 56, $false), @("Bought", "Gekauft", 90, $true), @("Sold", "Verkauft", 90, $true), @("Divs", "Dividenden", 90, $true), @("Fees", "Gebühren", 76, $true)) (S 12) (S 206) (S 458) (S 126) ($aT -bor $aL)
    $brokers = & $mkGrid @(@("Broker", "Broker", 110, $false), @("Shares", "Stück", 70, $true), @("Orders", "Orders", 58, $true), @("Volume", "Volumen", 90, $true), @("Fees", "Gebühren", 76, $true)) (S 482) (S 206) (S 446) (S 126) ($aT -bor $aL -bor $aR)
    [void](New-V8Label $dlg (Tr "Buchungen") (S 12) (S 342) (S 200))
    $book = & $mkGrid @(@("Date", "Datum", 80, $false), @("Type", "Typ", 70, $false), @("Shares", "Stück", 72, $true), @("Price", "Kurs/Betrag", 90, $true), @("Fee", "Gebühr", 70, $true), @("Cur", "Whg", 46, $false), @("Broker", "Broker", 90, $false), @("Note", "Notiz", 180, $false)) (S 12) (S 362) (S 916) (S 166) ($aT -bor $aB -bor $aL -bor $aR)

    $note = New-V8Label $dlg "" (S 12) (S 534) (S 916) (S 18) -Muted
    $note.AutoEllipsis = $true; $note.Anchor = $aB -bor $aL -bor $aR
    $bChart = New-V8Button $dlg (Tr "Chart öffnen") (S 12) (S 560) (S 130)
    $bBook = New-V8Button $dlg (Tr "Buchung erfassen ...") (S 150) (S 560) (S 160)
    $bClose = New-V8Button $dlg (Tr "Schließen") (S 828) (S 560) (S 100)
    $bChart.Anchor = $aB -bor $aL; $bBook.Anchor = $aB -bor $aL; $bClose.Anchor = $aB -bor $aR
    $bClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.CancelButton = $bClose
    $bChart.Add_Click({
        $s0 = $script:PosCtl.Ticker
        $script:PosCtl.OpenChart = $s0
        $script:PosCtl.Dlg.Close()
    })
    $bBook.Add_Click({ Show-TransactionDialog -Ticker $script:PosCtl.Ticker; Update-PositionView })

    $script:PosCtl = @{ Dlg = $dlg; Ticker = $sym; TilePanel = $tp; Tiles = @(); Head = $head; Note = $note; Years = $years; Brokers = $brokers; Bookings = $book; Detail = $null; OpenChart = "" }
    $dlg.Tag = $bClose
    $dlg.Add_Shown({ param($sender, $e) $sender.ActiveControl = $sender.Tag; Update-PositionView; Start-PositionRates })   # no focus frame around a table
    try {
        [void]$dlg.ShowDialog($(if ($null -ne $Owner) { $Owner } else { $form }))
    } finally {
        $open = [string]$script:PosCtl.OpenChart
        $script:PosCtl = $null
        $dlg.Dispose()
    }
    if ($open) {
        if ($null -ne $script:AnaCtl -and -not $script:AnaCtl.Dlg.IsDisposed) { $script:AnaCtl.Dlg.Close() }
        Switch-ActiveTicker -NewTicker $open -SkipResolve $true
        if ([string]$script:Config.Layout -ne "Terminal") { Set-ActiveTab -TabName "Chart" }
    }
}
$script:PosCtl = $null

# ==============================================================================
# v11.6: savings calculator (own assumptions -> how the depot could grow)
# ==============================================================================
function Get-CalcAssumptions {
    $d = [ordered]@{ Return = 5.0; Spread = 2.0; Years = 15.0; Increase = 0.0; Inflation = 2.0 }
    $have = $script:Config.SavingsCalc
    if ($null -ne $have) {
        foreach ($k in @($d.Keys)) { if ($null -ne $have.PSObject.Properties[$k]) { $d[$k] = [double]$have.$k } }
    }
    return $d
}

function Get-CalcInput {
    param([string]$Key, [double]$Min, [double]$Max)
    $t = [string]$script:CalcCtl.Inputs[$Key].Text
    if (-not $t.Trim()) { return 0.0 }
    if (-not (Test-DecimalInput $t)) { return [double]::NaN }
    return [math]::Max($Min, [math]::Min($Max, (Parse-DecimalInput $t)))
}

function Get-CalcDateText {
    param([int]$Months)
    return (Get-Date).AddMonths($Months).ToString("MM.yyyy")
}

function Update-SavingsCalc {
    $c = $script:CalcCtl
    if ($null -eq $c -or -not $c.Ready) { return }
    $v = @{
        Start = Get-CalcInput "Start" 0 1000000000; Monthly = Get-CalcInput "Monthly" 0 10000000; Return = Get-CalcInput "Return" -50 50
        Spread = Get-CalcInput "Spread" 0 30; Years = Get-CalcInput "Years" 1 60; Increase = Get-CalcInput "Increase" -20 50
        Inflation = Get-CalcInput "Inflation" -10 50; Goal = Get-CalcInput "Goal" 0 10000000000
    }
    $bad = @($v.Keys | Where-Object { [double]::IsNaN($v[$_]) })
    if ($bad.Count -gt 0) {
        $c.Result.Text = Tr "Bitte nur Zahlen eingeben."
        $c.Series = $null; $c.Chart.Invalidate(); $c.Grid.Rows.Clear()
        return
    }
    $months = [int][math]::Max(1, [math]::Round($v.Years)) * 12
    $run = { param([double]$r) @(Get-Projection -Start $v.Start -Monthly $v.Monthly -ReturnPct $r -Months $months -IncreasePct $v.Increase -InflationPct $v.Inflation) }
    $low = & $run ($v.Return - $v.Spread); $mid = & $run $v.Return; $high = & $run ($v.Return + $v.Spread)
    $c.Series = @{ Low = $low; Mid = $mid; High = $high; Goal = $v.Goal; Months = $months; Values = $v }
    $priv = [bool]$script:Config.PrivacyMode
    $base = $c.Base
    $money = { param([double]$x) if ($priv) { Protect-Amount "0" $true } else { "{0:N0} {1}" -f $x, $base } }

    $lines = @()
    $lines += (Tr "Nach {0} Jahren bei {1:0.##} % p.a.: {2}, davon eingezahlt {3}.") -f ($months / 12), $v.Return, (& $money $mid[-1].Value), (& $money $mid[-1].PaidIn)
    if ($v.Spread -gt 0) { $lines += (Tr "Spanne von {0:0.##} % bis {1:0.##} %: {2} bis {3}. In heutiger Kaufkraft (Mitte): {4}.") -f ($v.Return - $v.Spread), ($v.Return + $v.Spread), (& $money $low[-1].Value), (& $money $high[-1].Value), (& $money $mid[-1].Real) }
    else { $lines += (Tr "In heutiger Kaufkraft: {0}.") -f (& $money $mid[-1].Real) }
    if ($v.Goal -gt 0) {
        $long = @(Get-Projection -Start $v.Start -Monthly $v.Monthly -ReturnPct $v.Return -Months 720 -IncreasePct $v.Increase)
        $hit = Get-MonthsToGoal -Series $long -Goal $v.Goal
        $need = Get-RequiredMonthly -Start $v.Start -Goal $v.Goal -ReturnPct $v.Return -Months $months -IncreasePct $v.Increase
        $when = if ($hit -eq 0) { Tr "ist schon erreicht." } elseif ($hit -lt 0) { Tr "wird so innerhalb von 60 Jahren nicht erreicht." } else { (Tr "wäre etwa {0} erreicht (in {1:0.#} Jahren).") -f (Get-CalcDateText $hit), ($hit / 12.0) }
        $lines += (Tr "Ziel {0}") -f (& $money $v.Goal) + " " + $when
        if ($need -le 0) { $lines += Tr "Für das Ziel am Ende der Laufzeit ist keine Sparrate nötig." }
        else { $lines += (Tr "Für das Ziel nach {0} Jahren wäre eine Sparrate von {1} je Monat nötig.") -f ($months / 12), (& $money $need) }
    }
    $c.Result.Text = $lines -join "`r`n"

    $c.Grid.Rows.Clear()
    foreach ($r in @(Get-ProjectionRows -Low $low -Mid $mid -High $high -StartYear (Get-Date).Year)) {
        [void]$c.Grid.Rows.Add($r.Years, $r.Year, (& $money $r.PaidIn), (& $money $r.Low), (& $money $r.Mid), (& $money $r.High), (& $money $r.Real))
    }
    $c.Grid.ClearSelection()
    $c.Chart.Invalidate()
}

function Write-SavingsCalcChart {
    param($G, [int]$W, [int]$H)
    $p = $script:Pal
    $G.Clear($p.Card)
    $c = $script:CalcCtl
    if ($null -eq $c -or $null -eq $c.Series) { return }
    $s = $c.Series
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $n = $s.Mid.Count
    if ($n -lt 2) { return }
    $top = [math]::Max([double]$s.High[-1].Value, [double]$s.Mid[-1].PaidIn)
    foreach ($pt in $s.High) { if ($pt.Value -gt $top) { $top = $pt.Value } }
    if ($s.Goal -gt 0 -and $s.Goal -le $top * 2.0) { $top = [math]::Max($top, $s.Goal) }
    if ($top -le 0) { return }
    $top *= 1.08
    $L = S 70; $R = $W - (S 14); $T = S 26; $B = $H - (S 22)
    $toX = { param([int]$i) [float]($L + ($R - $L) * ($i / [double]($n - 1))) }
    $toY = { param([double]$val) [float]($B - ($B - $T) * ([math]::Max(0.0, $val) / $top)) }
    $priv = [bool]$script:Config.PrivacyMode
    $gridPen = New-Object System.Drawing.Pen($p.Grid, [float]1)
    $muted = New-Object System.Drawing.SolidBrush($p.Muted)
    try {
        for ($k = 0; $k -le 4; $k++) {
            $val = $top * $k / 4.0
            $y = & $toY $val
            $G.DrawLine($gridPen, [float]$L, $y, [float]$R, $y)
            $lbl = if ($priv) { [string]([char]0x2022) * 3 } else { "{0:N0}" -f $val }
            $sz = $G.MeasureString($lbl, $fontAxis)
            $G.DrawString($lbl, $fontAxis, $muted, [float]($L - $sz.Width - (S 4)), [float]($y - $sz.Height / 2))
        }
        $years = ($n - 1) / 12
        $step = [int][math]::Max(1, [math]::Ceiling($years / 8.0))
        for ($yr = 0; $yr -le $years; $yr += $step) {
            $lbl = [string]((Get-Date).Year + $yr)
            $sz = $G.MeasureString($lbl, $fontAxis)
            $x = [math]::Min([float]($R - $sz.Width), [math]::Max([float]$L, [float]((& $toX ($yr * 12)) - $sz.Width / 2)))
            $G.DrawString($lbl, $fontAxis, $muted, [float]$x, [float]($B + (S 4)))
        }
        $lines = @(
            @{ S = $s.High; F = "Value"; C = $colGreen; W = 1.4; Dash = $false; N = (Tr "oben") }
            @{ S = $s.Mid; F = "Value"; C = $p.Accent; W = 2.2; Dash = $false; N = (Tr "Mitte") }
            @{ S = $s.Low; F = "Value"; C = $p.Warn; W = 1.4; Dash = $false; N = (Tr "unten") }
            @{ S = $s.Mid; F = "PaidIn"; C = $p.Muted; W = 1.3; Dash = $true; N = (Tr "Eingezahlt") }
        )
        $lx = $L
        foreach ($ln in $lines) {
            $pen = New-Object System.Drawing.Pen($ln.C, [float]$ln.W)
            if ($ln.Dash) { $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash }
            $pts = New-Object System.Drawing.PointF[] $n
            for ($i = 0; $i -lt $n; $i++) { $pts[$i] = New-Object System.Drawing.PointF((& $toX $i), (& $toY ([double]$ln.S[$i].($ln.F)))) }
            $G.DrawLines($pen, $pts)
            $G.DrawLine($pen, [float]$lx, [float](S 12), [float]($lx + (S 16)), [float](S 12))
            $G.DrawString($ln.N, $fontAxis, $muted, [float]($lx + (S 20)), [float](S 5))
            $lx += (S 34) + [int]$G.MeasureString($ln.N, $fontAxis).Width
            $pen.Dispose()
        }
        if ($s.Goal -gt 0 -and $s.Goal -le $top) {
            $gp = New-Object System.Drawing.Pen($p.Text, [float]1)
            $gp.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
            $y = & $toY $s.Goal
            $G.DrawLine($gp, [float]$L, $y, [float]$R, $y)
            $G.DrawString((Tr "Ziel"), $fontAxis, $muted, [float]($L + (S 4)), [float]($y - (S 15)))
            $gp.Dispose()
        }
    } finally { $gridPen.Dispose(); $muted.Dispose() }
}

function Export-SavingsCalcCsv {
    param([string]$Path = "")
    $c = $script:CalcCtl
    if ($null -eq $c -or $null -eq $c.Series) { return }
    if (-not $Path) {
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "CSV (*.csv)|*.csv"; $sfd.FileName = "TerminalWidget-Sparrechner.csv"
        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $Path = $sfd.FileName }
        $sfd.Dispose()
        if (-not $Path) { return }
    }
    try {
        $heads = @($c.Grid.Columns | ForEach-Object { [string]$_.HeaderText })
        $rows = foreach ($r in $c.Grid.Rows) { ,@($r.Cells | ForEach-Object { [string]$_.Value }) }
        [System.IO.File]::WriteAllText($Path, (ConvertTo-CsvText -Headers $heads -Rows @($rows)), (New-Object System.Text.UTF8Encoding($true)))
        Set-TransientStatus ((Tr "Exportiert:") + " " + [System.IO.Path]::GetFileName($Path)) 4
    } catch { Show-InfoBox ((Tr "Export fehlgeschlagen:") + " " + $_.Exception.Message) (Tr "Sparrechner") }
}

function Show-SavingsCalcDialog {
    param($Owner = $null)
    if ($null -ne $script:CalcCtl) { return }
    $p = $script:Pal
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right
    $dlg = New-DialogForm -Title "Sparrechner" -W (S 960) -H (S 600) -Key "SavingsCalc"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MaximizeBox = $true
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 860), (S 540))
    $dlg.KeyPreview = $true
    $dlg.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() } })

    # prefill: depot value, active savings plans, goal of this depot
    $base = Get-AnalysisBase
    $holdings = Get-HoldingsValue -Holdings $script:Portfolio -Base $base
    $monthly = 0.0
    $amounts = Get-ActivePlanAmounts -Plans $script:SavingsPlans.ToArray()
    foreach ($cur in @($amounts.Keys)) { $monthly += Convert-CurrencyValue -Amount ([double]$amounts[$cur]) -FromCurrency ([string]$cur) -ToCurrency $base }
    $goal = [double](Get-DepotGoal -Goals $script:Config.DepotGoals -Id ([string]$script:Config.ActiveDepot)).Value
    if ($goal -gt 0 -and [string]$script:Config.Currency -ne $base) { $goal = Convert-CurrencyValue -Amount $goal -FromCurrency ([string]$script:Config.Currency) -ToCurrency $base }
    $a = Get-CalcAssumptions
    $values = [ordered]@{
        Start = "{0:0}" -f [double]$holdings.Value; Monthly = "{0:0}" -f $monthly; Goal = $(if ($goal -gt 0) { "{0:0}" -f $goal } else { "" })
        Return = "{0:0.##}" -f $a.Return; Spread = "{0:0.##}" -f $a.Spread; Years = "{0:0}" -f $a.Years; Increase = "{0:0.##}" -f $a.Increase; Inflation = "{0:0.##}" -f $a.Inflation
    }
    $inputs = @{}
    $labels = @{ Start = ((Tr "Startwert ({0})") -f $base); Monthly = ((Tr "Sparrate je Monat ({0})") -f $base); Goal = ((Tr "Ziel ({0}, optional)") -f $base)
        Return = (Tr "Rendite p.a. %"); Spread = (Tr "Spanne +/- %"); Years = (Tr "Laufzeit (Jahre)"); Increase = (Tr "Sparrate steigt p.a. %"); Inflation = (Tr "Inflation p.a. %") }
    $y = S 36
    [void](New-V8Label $dlg (Tr "Deine Annahmen") (S 12) (S 12) (S 190))
    foreach ($k in $values.Keys) {
        [void](New-V8Label $dlg $labels[$k] (S 12) $y (S 190) -Muted)
        $tb = New-Object System.Windows.Forms.TextBox
        $tb.SetBounds((S 12), ($y + (S 19)), (S 180), (S 24)); $tb.BackColor = $p.Input; $tb.ForeColor = $p.Text
        $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle; $tb.Text = $values[$k]; $tb.AccessibleName = $labels[$k]
        if ([bool]$script:Config.PrivacyMode -and $k -in @("Start", "Monthly", "Goal")) { $tb.UseSystemPasswordChar = $true }
        $dlg.Controls.Add($tb)
        $inputs[$k] = $tb
        $y += S 52
    }
    $chart = New-Object System.Windows.Forms.Panel
    $chart.SetBounds((S 208), (S 12), (S 740), (S 232)); $chart.Anchor = $aT -bor $aL -bor $aR
    Enable-DoubleBuffering -Control $chart
    $chart.Add_Paint({ param($sender, $e) try { Write-SavingsCalcChart -G $e.Graphics -W $sender.ClientSize.Width -H $sender.ClientSize.Height } catch { Write-WidgetLog "Savings chart: $($_.Exception.Message)" "WARN" } })
    $chart.Add_Resize({ param($sender, $e) $sender.Invalidate() })
    $dlg.Controls.Add($chart)
    $result = New-V8Label $dlg "" (S 208) (S 252) (S 740) (S 70)
    $result.Anchor = $aT -bor $aL -bor $aR
    $grid = New-V8Grid $dlg (S 208) (S 326) (S 740) (S 196)
    $grid.Anchor = $aT -bor $aB -bor $aL -bor $aR
    foreach ($cd in @(@("Years", "Jahre", 40), @("Year", "Jahr", 46), @("Paid", "Eingezahlt", 90), @("Low", "unten", 90), @("Mid", "Mitte", 90), @("High", "oben", 90), @("Real", "Kaufkraft (Mitte)", 110))) {
        Add-V8Column $grid $cd[0] $cd[1] $cd[2] -ReadOnly
        $grid.Columns[$cd[0]].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight
    }
    $note = New-V8Label $dlg (Tr "Rechenbeispiel mit deinen Annahmen und gleichbleibender Rendite. Keine Vorhersage und keine Anlageberatung. Ohne Steuern und Gebühren; echte Kurse schwanken.") (S 208) (S 528) (S 740) (S 32) -Muted
    $note.Anchor = $aB -bor $aL -bor $aR
    $bCsv = New-V8Button $dlg (Tr "Als CSV speichern ...") (S 208) (S 564) (S 180)
    $bClose = New-V8Button $dlg (Tr "Schließen") (S 848) (S 564) (S 100)
    $bCsv.Anchor = $aB -bor $aL; $bClose.Anchor = $aB -bor $aR
    $bClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.CancelButton = $bClose
    $bCsv.Add_Click({ Export-SavingsCalcCsv })

    $hint = ""
    if ($holdings.Missing -gt 0) { $hint = (Tr "Startwert unvollständig: für {0} Positionen fehlt noch ein Kurs.") -f $holdings.Missing }
    $script:CalcCtl = @{ Dlg = $dlg; Inputs = $inputs; Chart = $chart; Result = $result; Grid = $grid; Series = $null; Base = $base; Ready = $true }
    if ($hint) { $note.Text = $hint + " " + $note.Text }
    foreach ($tb in $inputs.Values) { $tb.Add_TextChanged({ Update-SavingsCalc }) }
    $dlg.Add_Shown({ Update-SavingsCalc })
    try {
        [void]$dlg.ShowDialog($(if ($null -ne $Owner) { $Owner } else { $form }))
    } finally {
        # remember the assumptions (not the amounts)
        $keep = [ordered]@{}
        foreach ($k in @("Return", "Spread", "Years", "Increase", "Inflation")) {
            $t = [string]$inputs[$k].Text
            $keep[$k] = if ((Test-DecimalInput $t) -and $t.Trim()) { Parse-DecimalInput $t } else { (Get-CalcAssumptions)[$k] }
        }
        $script:Config.SavingsCalc = [PSCustomObject]$keep
        Save-Config
        $script:CalcCtl = $null
        $dlg.Dispose()
    }
}
$script:CalcCtl = $null
[void](Add-BarItem $mbPort "Sparrechner ..." { Show-SavingsCalcDialog })
