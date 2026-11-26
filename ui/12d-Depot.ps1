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
    # expected dividends of the next 12 months for the active depot, from the
    # same data as the analysis page. Loading = positions without data yet.
    param([string]$Base)
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $res = @{ Income = 0.0; Loading = 0; Positions = 0 }
    foreach ($k in @($script:Portfolio.Keys)) {
        $sym = ([string]$k).ToUpper()
        $sh = [double]$script:Portfolio[$k].Shares
        if ($sh -le 0) { continue }
        $res.Positions++
        $dh = $script:DivHist[$sym]
        if ($null -eq $dh -or $dh.Failed) { $res.Loading++; continue }
        $st = Get-DividendStats -Dividends $dh.Divs -AsOf $today
        if ($null -eq $st) { continue }
        $cur = if ($dh.Currency) { [string]$dh.Currency } else { Get-InstrumentCurrency $sym }
        if (-not $cur) { $cur = [string]$script:Portfolio[$k].Currency }
        foreach ($pj in @(Get-DividendProjection -Dividends $dh.Divs -AsOf $today -Stats $st)) {
            $res.Income += [double](Convert-CurrencyValue -Amount ([double]$pj.Amount * $sh) -FromCurrency $cur -ToCurrency $Base)
        }
    }
    return $res
}

function Update-GoalsView {
    $gc = $script:GoalCtl
    if ($null -eq $gc) { return }
    $base = [string]$script:Config.Currency
    $priv = [bool]$script:Config.PrivacyMode
    $money = { param([double]$v) Protect-Amount -Text ("{0:N0} {1}" -f $v, $base) -On $priv }
    $show = {
        param($Bar, $Label, [double]$Current, [double]$Target, [string]$What)
        $p = Get-GoalProgress -Current $Current -Target $Target
        if ($null -eq $p) { $Bar.Value = 0; $Label.Text = "{0}: {1}  -  {2}" -f $What, (& $money $Current), (Tr "kein Ziel gesetzt"); return }
        $Bar.Value = [int][math]::Round($p.BarPct)
        $tail = if ($p.Reached) { Tr "Ziel erreicht" } else { (Tr "es fehlen") + " " + (& $money $p.Remaining) }
        $Label.Text = "{0}: {1} / {2}  ({3:N0}%)  -  {4}" -f $What, (& $money $Current), (& $money $Target), $p.Pct, $tail
    }
    $pt = Get-PortfolioDayTotals -Currency $base
    if ($pt.Ok) { & $show $gc.Bar1 $gc.Lbl1 ([double]$pt.Value) ([double]$script:Config.GoalDepotValue) (Tr "Depotwert") }
    else { $gc.Bar1.Value = 0; $gc.Lbl1.Text = (Tr "Depotwert") + ": " + (Tr "noch keine Kurse für alle Positionen") }
    $fc = Get-DividendForecast -Base $base
    & $show $gc.Bar2 $gc.Lbl2 ([double]$fc.Income) ([double]$script:Config.GoalDividendYear) (Tr "Dividenden, Prognose 12 Monate")
    $got = [double](Get-RealizedTotal -Year (Get-Date).Year -Type "Dividende")
    $gc.Lbl3.Text = (Tr "Dieses Jahr gebucht: {0}") -f (Protect-Amount -Text ("{0:N2} {1}" -f $got, $base) -On $priv)
    if ($fc.Loading -gt 0) { $gc.Lbl3.Text += "   |   " + ((Tr "Prognose unvollständig: {0} von {1} Positionen ohne Dividendendaten") -f $fc.Loading, $fc.Positions) }

    $byBroker = ($gc.Group.SelectedIndex -eq 1)
    Set-GoalsGridMode $byBroker
    $fr = if ($byBroker) { Get-BrokerFeeRows } else { Get-FeeRows }
    $gc.Grid.Rows.Clear()
    foreach ($r in @($fr.Rows)) { [void]$gc.Grid.Rows.Add([object[]]$r) }
    $gc.Note.Text = if ($byBroker) { (Tr "Beträge in {0}. Nur Käufe und Verkäufe, alle Depots. Broker vergibst du in der Transaktionshistorie.") -f $fr.Base }
                    else { (Tr "Beträge in {0}. Gebühren aus Buchungen und Cash-Konto, Zinsen aus dem Cash-Konto.") -f $fr.Base }
    if ($fr.Approx) { $gc.Note.Text += " " + (Tr "Teilweise mit heutigem Wechselkurs gerechnet (Tageskurse lädt die Analyse).") }
}

function Show-GoalsCostsDialog {
    $dlg = New-DialogForm -Title "Ziele und Kosten" -W (S 760) -H (S 520) -Key "GoalsCosts"
    $base = [string]$script:Config.Currency
    [void](New-V8Label $dlg ((Tr "Ziele für das Depot '{0}', in {1} (leer = kein Ziel)") -f (Get-DepotName ([string]$script:Config.ActiveDepot)), $base) (S 12) (S 10) (S 736))
    [void](New-V8Label $dlg (Tr "Depotwert") (S 12) (S 40) (S 90))
    $fmt = { param([double]$v) if ($v -gt 0) { $v.ToString("0.##") } else { "" } }
    $t1 = New-V8Text $dlg (& $fmt ([double]$script:Config.GoalDepotValue)) (S 104) (S 36) (S 110)
    [void](New-V8Label $dlg (Tr "Dividenden pro Jahr") (S 232) (S 40) (S 130))
    $t2 = New-V8Text $dlg (& $fmt ([double]$script:Config.GoalDividendYear)) (S 366) (S 36) (S 110)
    $bSave = New-V8Button $dlg (Tr "Ziele speichern") (S 490) (S 34) (S 130)
    $bCalc = New-V8Button $dlg (Tr "Neu berechnen") (S 628) (S 34) (S 120)
    $mk = {
        param([int]$Y)
        $l = New-V8Label $dlg "" (S 12) (S $Y) (S 736)
        $b = New-Object System.Windows.Forms.ProgressBar
        $b.SetBounds((S 12), (S ($Y + 20)), (S 736), (S 12)); $b.Minimum = 0; $b.Maximum = 100
        $dlg.Controls.Add($b)
        return @($l, $b)
    }
    $g1 = & $mk 76
    $g2 = & $mk 118
    $l3 = New-V8Label $dlg "" (S 12) (S 158) (S 736) -Muted
    [void](New-V8Label $dlg (Tr "Kosten und Zinsen je Jahr") (S 12) (S 188) (S 400))
    $cbGroup = New-V8Combo $dlg @((Tr "je Depot"), (Tr "je Broker")) (Tr "je Depot") (S 598) (S 183) (S 150)
    $cbGroup.AccessibleName = Tr "Gruppierung"
    $g = New-V8Grid $dlg (S 12) (S 210) (S 736) (S 254)
    $cols = @(@("Year", "Jahr", 50), @("Depot", "Depot", 120), @("Orders", "Orders", 50), @("OrderFees", "Ordergebühren", 90), @("AccFees", "Kontogebühren", 90), @("Fees", "Kosten gesamt", 90), @("Interest", "Zinsen", 80))
    foreach ($c in $cols) { Add-V8Column $g $c[0] $c[1] $c[2] -ReadOnly }
    foreach ($n in @("Orders", "OrderFees", "AccFees", "Fees", "Interest")) { $g.Columns[$n].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    $note = New-V8Label $dlg "" (S 12) (S 472) (S 620) (S 40) -Muted
    $no = New-V8Button $dlg (Tr "Schließen") (S 652) (S 482) (S 96)
    $no.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.CancelButton = $no
    $script:GoalCtl = @{ Dlg = $dlg; T1 = $t1; T2 = $t2; Lbl1 = $g1[0]; Bar1 = $g1[1]; Lbl2 = $g2[0]; Bar2 = $g2[1]; Lbl3 = $l3; Grid = $g; Note = $note; Group = $cbGroup }
    $cbGroup.Add_SelectedIndexChanged({ Update-GoalsView })
    $bSave.Add_Click({
        $vals = @()
        foreach ($tb in @($script:GoalCtl.T1, $script:GoalCtl.T2)) {
            if ($tb.Text.Trim() -and -not (Test-DecimalInput $tb.Text)) { Show-InfoBox (Tr "Bitte eine Zahl eingeben.") (Tr "Ziele und Kosten"); return }
            $vals += [math]::Max(0.0, $(if ($tb.Text.Trim()) { Parse-DecimalInput $tb.Text } else { 0.0 }))
        }
        $script:Config.GoalDepotValue = [double]$vals[0]
        $script:Config.GoalDividendYear = [double]$vals[1]
        Save-Config
        Update-GoalsView
    })
    $bCalc.Add_Click({ Update-GoalsView })
    $dlg.Add_Shown({
        if (-not $script:SmokeMode) { Start-DividendLoad }
        Update-GoalsView
    })
    # dividend data arrives in the background: look again for a short while
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 4000
    $script:GoalTicks = 0
    $timer.Add_Tick({ param($sender, $e) $script:GoalTicks++; Update-GoalsView; if ($script:GoalTicks -ge 3) { $sender.Stop() } })
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
