# TerminalWidget UI part 08 (Analysis) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

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
                $lbl = if ([bool]$script:Config.PrivacyMode) { [string][char]0x2022 * 3 } else { "{0:N0}" -f $v }
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
            $pv = [bool]$script:Config.PrivacyMode
            foreach ($ln in $lines) { $txt += $(if ($pv) { "{0}: {1}" -f $ln.N, ([string][char]0x2022 * 3) } else { "{0}: {1:N2}" -f $ln.N, $ln.V[$hi] }) }
            $txt += ("Ergebnis: {0}" -f $(if ($pv) { [string][char]0x2022 * 3 } else { Format-Signed ($sr.Value[$hi] + $sr.Dividends[$hi] - $sr.Invested[$hi]) }))
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
            $g.DrawString($(if ([bool]$script:Config.PrivacyMode) { "{0,5:N1} %" -f $gr.Pct } else { "{0,5:N1} %  {1:N0}" -f $gr.Pct, $gr.Value }), $fontAxis, $brM, [float]($x1 + (S 6)), [float]($y + (S 5)))
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
    # v5.5: market (beta) or one sector / one currency
    $kind = [string]$ac.SKind.SelectedItem
    $grpKind = if ($kind -like "Sektor:*" -or $kind -like "Sector:*") { "Sector" } elseif ($kind -like "Währung:*" -or $kind -like "Currency:*") { "Currency" } else { "" }
    $grpName = if ($grpKind) { $kind.Substring($kind.IndexOf(":") + 1).Trim() } else { "" }
    foreach ($r in @($ac.Model.Rows | Where-Object { $_.Shares -gt 0 -and $_.Value -gt 0 })) {
        if ($grpKind) {
            $prof = Get-EffectiveProfile $script:Profiles[$r.Ticker]
            $grp = if ($grpKind -eq "Sector") { [string]$prof.Sector } else { [string](Get-InstrumentCurrency $r.Ticker) }
            $pos += [PSCustomObject]@{ Sym = $r.Ticker; Value = [double]$r.Value; Group = $grp }
            $src[$r.Ticker] = $grp
        } else {
            $b = Get-PositionBeta -Sym $r.Ticker
            $pos += [PSCustomObject]@{ Sym = $r.Ticker; Value = [double]$r.Value; Beta = [double]$b.Beta }
            $src[$r.Ticker] = $b.Source
        }
    }
    $g.Columns["Beta"].HeaderText = if ($grpKind) { Tr "Betroffen" } else { "Beta" }
    $g.Columns["Src"].HeaderText = if ($grpKind -eq "Sector") { Tr "Sektor" } elseif ($grpKind) { Tr "Währung" } else { Tr "Beta aus" }
    $sc = if ($grpKind) { Get-GroupScenarioImpact -Positions $pos -Group $grpName -Pct $mkt } else { Get-ScenarioImpact -Positions $pos -MarketPct $mkt }
    foreach ($r in $sc.Rows) {
        $i = $g.Rows.Add($r.Sym, $(if ($priv) { (Protect-Amount "0" $true) } else { "{0:N2}" -f $r.Value }), ("{0:N2}" -f $r.Beta), $(if ($r.BetaAssumed) { Tr "angenommen 1,0" } else { $src[$r.Sym] }), $(if ($priv) { (Protect-Amount "0" $true) } else { Format-Signed $r.Change }), ("{0:+0.0;-0.0}%" -f ($r.Beta * $mkt)))
        $g.Rows[$i].Cells["Chg"].Style.ForeColor = Get-SignColor ([double]$r.Change)
        if ($r.BetaAssumed -or ($grpKind -and [double]$r.Beta -eq 0)) { $g.Rows[$i].Cells["Src"].Style.ForeColor = $script:Pal.Muted }
    }
    $ac.SRes.ForeColor = Get-SignColor ([double]$sc.Change)
    $why = if ($grpKind -eq "Sector") { Tr "nur Positionen dieses Sektors, ohne Cash" } elseif ($grpKind) { Tr "nur Positionen in dieser Währung (Kursänderung in der Basiswährung), ohne Cash" } else { Tr "grobe Schätzung über das Beta, ohne Cash" }
    $ac.SRes.Text = "{0} {1} {2} ({3:+0.0;-0.0}%)  -  {4}" -f (Tr "Depot ca."), $(if ($priv) { (Protect-Amount "0" $true) } else { Format-Signed $sc.Change }), [string]$ac.Model.Base, $sc.Pct, $why
}

function Update-AnalysisIncome {
    # v5.5: received dividends per month and year (calendar)
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.IGrid) { return }
    $base = Get-AnalysisBase
    $priv = [bool]$script:Config.PrivacyMode
    $items = @(foreach ($t in $script:Transactions) {
        if ([string]$t.Type -ne "Dividende") { continue }
        [PSCustomObject]@{ Date = [string]$t.Date; Amount = (Convert-CurrencyValue -Amount ([double]$t.Realized) -FromCurrency ([string]$t.Currency) -ToCurrency $base) }
    })
    $tab = Get-DividendIncomeTable -Items $items
    $g = $ac.IGrid
    $g.Rows.Clear()
    $acc = $script:Pal.Accent; $card = $script:Pal.Card
    foreach ($r in $tab.Rows) {
        $vals = @([string]$r.Year)
        foreach ($v in $r.Months) { $vals += $(if ($v -eq 0) { "" } elseif ($priv) { [string][char]0x2022 * 3 } else { "{0:N0}" -f $v }) }
        $vals += $(if ($priv) { [string][char]0x2022 * 3 } else { "{0:N2}" -f $r.Total })
        $vals += $(if ([double]::IsNaN($r.ChangePct)) { "" } else { "{0:+0;-0}%" -f $r.ChangePct })
        $i = $g.Rows.Add($vals)
        for ($mi = 0; $mi -lt 12; $mi++) {
            $v = [double]$r.Months[$mi]
            if ($v -le 0 -or $tab.Max -le 0) { continue }
            # colour scale: stronger accent = more income in that month
            $a = [math]::Min(1.0, [math]::Sqrt($v / $tab.Max))
            $mix = { param($x, $y) [int]($x + ($y - $x) * (0.15 + 0.6 * $a)) }
            $g.Rows[$i].Cells[$mi + 1].Style.BackColor = [System.Drawing.Color]::FromArgb((& $mix $card.R $acc.R), (& $mix $card.G $acc.G), (& $mix $card.B $acc.B))
            $g.Rows[$i].Cells[$mi + 1].ToolTipText = "{0:N2} {1}" -f $v, $base
        }
        if (-not [double]::IsNaN($r.ChangePct)) { $g.Rows[$i].Cells["Chg"].Style.ForeColor = Get-SignColor ([double]$r.ChangePct) }
    }
    if ($tab.Rows.Count -eq 0) { $ac.ISum.Text = Tr "Noch keine Dividenden gebucht (Transaktion 'Dividende' oder Broker-CSV-Import)."; return }
    $y0 = $tab.Rows[0]
    $ac.ISum.Text = $(if ($priv) { "{0} {1}: {2}   {3}: {4}" -f (Tr "Dividenden"), $y0.Year, ([string][char]0x2022 * 3), (Tr "seit Beginn"), ([string][char]0x2022 * 3) } else {
        "{0} {1}: {2:N2} {3} ({4:N2} {3} {5})   {6}: {7:N2} {3}" -f (Tr "Dividenden"), $y0.Year, $y0.Total, $base, $y0.MonthlyAvg, (Tr "pro Monat"), (Tr "seit Beginn"), $tab.Total })
}

function Update-ScenarioChoices {
    # sectors and currencies of the current positions
    $ac = $script:AnaCtl
    if ($null -eq $ac -or $null -eq $ac.SKind -or $null -eq $ac.Model) { return }
    $cur = [string]$ac.SKind.SelectedItem
    $sec = New-Object System.Collections.Generic.SortedSet[string]
    $ccy = New-Object System.Collections.Generic.SortedSet[string]
    foreach ($r in @($ac.Model.Rows | Where-Object { $_.Shares -gt 0 -and $_.Value -gt 0 })) {
        $prof = Get-EffectiveProfile $script:Profiles[$r.Ticker]
        if ([string]$prof.Sector) { [void]$sec.Add([string]$prof.Sector) }
        $c0 = [string](Get-InstrumentCurrency $r.Ticker); if ($c0) { [void]$ccy.Add($c0) }
    }
    $ac.SKind.BeginUpdate()
    $ac.SKind.Items.Clear()
    [void]$ac.SKind.Items.Add((Tr "Markt (Beta)"))
    foreach ($x in $sec) { [void]$ac.SKind.Items.Add(("{0}: {1}" -f (Tr "Sektor"), $x)) }
    foreach ($x in $ccy) { if ($x -ne [string]$ac.Model.Base) { [void]$ac.SKind.Items.Add(("{0}: {1}" -f (Tr "Währung"), $x)) } }
    $ac.SKind.EndUpdate()
    $ix = $ac.SKind.Items.IndexOf($cur)
    $ac.SKind.SelectedIndex = [math]::Max(0, $ix)
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
    if ($Page -eq "Income") { Update-AnalysisIncome }
    foreach ($k in $ac.PageButtons.Keys) {
        $bt = $ac.PageButtons[$k]
        if ($k -eq $Page) { Style-FlatButton -Btn $bt -BgColor $script:Pal.Accent -FgColor $script:Pal.HeaderBg -BorderColor $script:Pal.Accent }
        else { Style-FlatButton -Btn $bt -BgColor $script:Pal.Card -FgColor $script:Pal.Text -BorderColor $script:Pal.Border }
    }
}

