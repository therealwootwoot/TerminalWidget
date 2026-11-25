# TerminalWidget UI part 09 (Dialogs) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

function Show-AnalysisDialog {
    param([string]$Page = "")
    if ($null -ne $script:AnaCtl) { return }
    # v5.0: P opens the page used last time
    if (-not $Page) { $Page = if ([string]$script:Config.AnalysisLastPage) { [string]$script:Config.AnalysisLastPage } else { "Perf" } }
    $p = $script:Pal
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right
    $aAll = $aT -bor $aB -bor $aL -bor $aR

    $dlg = New-DialogForm -Title "Portfolio-Analyse - $($script:AppTitle)" -W (S 1000) -H (S 640) -Key "Analyse"
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
    # v5.5
    $pageBtns["Income"]  = & $mkBtn "Einkommen" (S 856) (S 10) (S 92) $dlg
    Set-DynTip $pageBtns["Income"] "Erhaltene Dividenden je Monat und Jahr (aus den Buchungen), als Kalender"
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
    foreach ($k in @("Perf", "Ret", "Alloc", "Div", "Risk", "Target", "Heat", "Contrib", "Bench", "Income")) {
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
    $chart.SetBounds(0, (S 32), (S 976), (S 396))   # V7.0: 60 px shorter, the key figure tiles sit below
    $chart.Anchor = $aAll
    Enable-DoubleBuffering -Control $chart
    $pp.Controls.Add($chart)
    $btnBuyDates = & $mkBtn "Kaufdaten ..." (S 846) 0 (S 130) $pp ($aT -bor $aR)
    Set-DynTip $btnBuyDates "Kaufdatum für Positionen ohne Buchung nachtragen (Anfangsbestand) oder Datum von Editor-Buchungen korrigieren" "OPENING"
    # V7.0: key figure tiles (value, result, return p.a., dividends, period)
    $kpiPanel = New-Object System.Windows.Forms.Panel
    $kpiPanel.SetBounds(0, (S 432), (S 976), (S 56))
    $kpiPanel.Anchor = $aB -bor $aL -bor $aR
    Enable-DoubleBuffering -Control $kpiPanel
    $kpiPanel.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $p = $script:Pal
        $g.Clear($sender.Parent.BackColor)
        $ac = $script:AnaCtl
        if ($null -eq $ac -or $null -eq $ac.Kpi -or @($ac.Kpi).Count -eq 0) { return }
        $tiles = @($ac.Kpi)
        $gap = S 8
        $w = [int](($sender.Width - ($tiles.Count - 1) * $gap) / $tiles.Count)
        $rad = if ($script:UiSpec.Fresh) { [float](S 10) } else { [float](S 3) }
        $tf = [System.Windows.Forms.TextFormatFlags]
        $fl = $tf::Left -bor $tf::Top -bor $tf::NoPadding -bor $tf::SingleLine -bor $tf::EndEllipsis
        for ($i = 0; $i -lt $tiles.Count; $i++) {
            $t = $tiles[$i]
            $x = $i * ($w + $gap)
            $br = New-Object System.Drawing.SolidBrush($p.Card)
            $pn = New-Object System.Drawing.Pen($p.Border, 1)
            Fill-RoundedRect -g $g -Brush $br -Rect (New-Object System.Drawing.RectangleF([float]$x, 0.5, [float]($w - 1), [float]($sender.Height - 1.5))) -Radius $rad -Pen $pn
            $br.Dispose(); $pn.Dispose()
            $vc = switch ([string]$t.Kind) { "up" { $script:colGreen } "down" { $script:colRed } default { $p.Text } }
            [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$t.Label, $fontUi, (New-Object System.Drawing.Rectangle(($x + (S 10)), (S 6), ($w - (S 20)), (S 14))), $p.Muted, $fl)
            [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$t.Text, $fontUiBold, (New-Object System.Drawing.Rectangle(($x + (S 10)), (S 21), ($w - (S 20)), (S 16))), $vc, $fl)
            if ($t.Sub) { [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$t.Sub, $fontUi, (New-Object System.Drawing.Rectangle(($x + (S 10)), (S 38), ($w - (S 20)), (S 14))), $p.Muted, $fl) }
        }
    })
    $pp.Controls.Add($kpiPanel)
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
        Chart = $chart; Sum = $lblSum; KpiPanel = $kpiPanel; Kpi = @(); RangeButtons = $rangeBtns; HoverIdx = -1; Geom = $null
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
    $lblScn.SetBounds(0, (S 358), (S 62), (S 20)); $lblScn.Text = "Szenario:"
    $pcn.Controls.Add($lblScn)
    # v5.5: market, one sector or one currency
    $cbScn = New-Object System.Windows.Forms.ComboBox
    $cbScn.SetBounds((S 64), (S 355), (S 180), (S 24)); $cbScn.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbScn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cbScn.BackColor = $p.Input; $cbScn.ForeColor = $p.Text
    [void]$cbScn.Items.Add((Tr "Markt (Beta)")); $cbScn.SelectedIndex = 0
    $pcn.Controls.Add($cbScn)
    Set-DynTip $cbScn "Markt: jede Position bewegt sich um Beta x Wert. Sektor / Währung: nur diese Positionen bewegen sich um den Wert (z. B. 'USD -10 %' = Dollar verliert 10 % zur Basiswährung)."
    $cbScn.Add_DropDown({ Update-ScenarioChoices })
    $cbScn.Add_SelectionChangeCommitted({ Update-AnalysisScenario })
    $nScn = New-Object System.Windows.Forms.NumericUpDown
    $nScn.SetBounds((S 250), (S 355), (S 64), (S 24)); $nScn.Minimum = -60; $nScn.Maximum = 60; $nScn.Increment = 5
    $nScn.Value = [decimal][math]::Max(-60, [math]::Min(60, [int]$script:Config.ScenarioPct))
    $nScn.BackColor = $p.Input; $nScn.ForeColor = $p.Text; $nScn.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $pcn.Controls.Add($nScn)
    Set-DynTip $nScn "Wie stark sich der Markt (die Benchmark) bewegt. Jede Position bewegt sich um Beta x diesen Wert." "BETA"
    $lblScnPct = New-Object System.Windows.Forms.Label
    $lblScnPct.SetBounds((S 318), (S 358), (S 24), (S 20)); $lblScnPct.Text = "%"
    $pcn.Controls.Add($lblScnPct)
    $lblSRes = New-Object System.Windows.Forms.Label
    $lblSRes.SetBounds((S 346), (S 358), (S 628), (S 20)); $lblSRes.Anchor = $aT -bor $aL -bor $aR; $lblSRes.Font = $fontUiBold; $lblSRes.AutoEllipsis = $true
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
    # --- v5.5: Einkommen (received dividends as a calendar) ---
    $pin = $pages["Income"]
    $lblInc = New-Object System.Windows.Forms.Label
    $lblInc.SetBounds(0, 0, (S 976), (S 40)); $lblInc.Anchor = $aT -bor $aL -bor $aR; $lblInc.Font = $fontMono
    $pin.Controls.Add($lblInc)
    $gI = New-Object System.Windows.Forms.DataGridView
    $gI.SetBounds(0, (S 44), (S 976), (S 470)); $gI.Anchor = $aAll
    Style-DataGrid -Grid $gI
    $mn = @("Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez")
    $ci = $gI.Columns.Add("Year", "Jahr"); $gI.Columns[$ci].FillWeight = [float](S 56)
    for ($mi = 0; $mi -lt 12; $mi++) { $ci = $gI.Columns.Add(("M{0}" -f ($mi + 1)), $mn[$mi]); $gI.Columns[$ci].FillWeight = [float](S 60); $gI.Columns[$ci].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    $ci = $gI.Columns.Add("Sum", "Summe Dividende"); $gI.Columns[$ci].FillWeight = [float](S 92); $gI.Columns[$ci].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight
    $ci = $gI.Columns.Add("Chg", "zum Vorjahr"); $gI.Columns[$ci].FillWeight = [float](S 70); $gI.Columns[$ci].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight
    foreach ($col in $gI.Columns) { $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable }
    $gI.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $pin.Controls.Add($gI)
    $lblIncNote = New-Object System.Windows.Forms.Label
    $lblIncNote.SetBounds(0, (S 520), (S 976), (S 36)); $lblIncNote.Anchor = $aB -bor $aL -bor $aR; $lblIncNote.ForeColor = $p.Muted
    $lblIncNote.Text = "Aus den Dividenden-Buchungen dieses Depots (netto nach Gebühr / Quellensteuer, wie gebucht), umgerechnet mit heutigen Wechselkursen. Je kräftiger die Farbe, desto mehr kam in dem Monat."
    $pin.Controls.Add($lblIncNote)
    $script:AnaCtl.IGrid = $gI; $script:AnaCtl.ISum = $lblInc
    $script:AnaCtl.CGrid = $gC; $script:AnaCtl.CInfo = $lblCInfo; $script:AnaCtl.CDiv = $lblCDiv; $script:AnaCtl.SGrid = $gS; $script:AnaCtl.SNum = $nScn; $script:AnaCtl.SRes = $lblSRes; $script:AnaCtl.SKind = $cbScn

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
    # v5.5: export of the current page + privacy mode for every grid and label
    $btnExp = New-Object System.Windows.Forms.Button
    $btnExp.SetBounds(($dlg.ClientSize.Width - (S 112)), (S 10), (S 100), (S 26)); $btnExp.Anchor = $aT -bor $aR
    Style-FlatButton -Btn $btnExp -BgColor $p.Card -FgColor $p.Accent -BorderColor $p.Border
    $btnExp.Text = "Export " + $script:DropArrow
    Set-DynTip $btnExp "Aktuelle Seite als HTML-Bericht oder CSV (Excel) speichern, oder als Bild"
    $dlg.Controls.Add($btnExp)
    $expMenu = New-Object System.Windows.Forms.ContextMenuStrip
    foreach ($ei in @(@("Html", "HTML-Bericht speichern ..."), @("Csv", "CSV für Excel speichern ..."), @("ImgCopy", "Als Bild kopieren"), @("ImgSave", "Als Bild speichern ..."))) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($ei[1]); $mi.Tag = $ei[0]; [void]$expMenu.Items.Add($mi)
    }
    Apply-Language $expMenu
    $expMenu.Add_ItemClicked({
        param($sender, $e)
        $sender.Close()
        $ac = $script:AnaCtl
        if ($null -eq $ac) { return }
        $pg = $ac.Pages[[string]$ac.Page]
        $title = "{0} - {1}" -f (Tr "Portfolio-Analyse"), (Tr ([string]$ac.PageButtons[[string]$ac.Page].Text))
        switch ([string]$e.ClickedItem.Tag) {
            "Html"    { [void](Export-GridsReport -Grids (Get-ChildGrids $pg) -Title $title -Format "Html" -Note (Get-ChildLabelText $pg)) }
            "Csv"     { [void](Export-GridsReport -Grids (Get-ChildGrids $pg) -Title $title -Format "Csv") }
            "ImgCopy" { [void](Export-ControlImage -Ctl $ac.Dlg -Mode "Copy") }
            "ImgSave" { [void](Export-ControlImage -Ctl $ac.Dlg -Mode "Save" -Name "Analyse") }
        }
    })
    $btnExp.Tag = $expMenu
    $btnExp.Add_Click({ param($sender, $e) $sender.Tag.Show($sender, (New-Object System.Drawing.Point(0, $sender.Height))) })
    Enable-PrivacyMask $dlg

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
    # v5.5: every info window remembers its place (key = first word of the title)
    $dlg = New-DialogForm -Title $Title -W (S $W) -H (S $H) -Key ("Info_" + (([string]$Title -split '[\s-]+')[0] -replace '[^\w]', ''))
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

function Get-PeerGroup {
    param([string]$Sym)
    $pg = $script:Config.PeerGroups
    if ($null -eq $pg -or $pg -is [string]) { return @() }
    $pp = $pg.PSObject.Properties[([string]$Sym).ToUpper()]
    if ($null -eq $pp) { return @() }
    return @(@($pp.Value) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpper() })
}

function Set-PeerGroup {
    param([string]$Sym, [string[]]$Peers)
    $u = ([string]$Sym).ToUpper()
    if ($null -eq $script:Config.PeerGroups -or $script:Config.PeerGroups -is [string]) { $script:Config.PeerGroups = [PSCustomObject]@{} }
    if (@($Peers).Count -gt 0) { $script:Config.PeerGroups | Add-Member -NotePropertyName $u -NotePropertyValue @($Peers) -Force }
    else { $script:Config.PeerGroups.PSObject.Properties.Remove($u) }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    # fundamentals of peers outside depot / watchlist
    $miss = @(@($Peers) | Where-Object { $null -eq $script:Events[$_] -or $null -eq $script:Events[$_].Fund })
    if ($miss.Count -gt 0) { Start-ProfileJob -Symbols $miss -EventsOnly $true -OnComplete { if ($null -ne $script:TaCtl) { Update-TickerAnalysis } } }
}

function Get-FundPeers {
    # other tickers of your depot + watchlist in the same sector with fundamentals
    # v5.7: an own comparison group (PEER) wins over the sector
    param([string]$Sym)
    $own = @(Get-PeerGroup $Sym)
    if ($own.Count -gt 0) {
        $pf = @(); $nm = @()
        foreach ($u in $own) { $e = $script:Events[$u]; if ($null -ne $e -and $null -ne $e.Fund) { $pf += $e.Fund; $nm += $u } }
        return [PSCustomObject]@{ Sector = (Tr "eigene Gruppe"); Peers = $pf; Syms = $nm; Own = $true; Wanted = $own }
    }
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
        # v5.7: the same signals on weekly bars + one sentence for both
        $wb = ConvertTo-WeeklyBars -Dates ([string[]]$c.Bars.Dates) -Close ([double[]]$c.Bars.Close) -High ([double[]]$c.Bars.High) -Low ([double[]]$c.Bars.Low) -Volume ([double[]]$c.Bars.Volume)
        $wsig = Get-TechnicalSignals -Closes ([double[]]$wb.Close) -Highs ([double[]]$wb.High) -Lows ([double[]]$wb.Low) -Volumes ([double[]]$wb.Volume)
        $wByKey = @{}
        foreach ($wr in @($wsig.Rows)) { $wByKey[[string]$wr.Key] = $wr }
        $c.WSig = $wsig
        foreach ($r in $sig.Rows) {
            $wr = $wByKey[[string]$r.Key]
            $wTxt = if ($null -eq $wr -or $r.Key -in @("SUP", "RES", "ATR", "VOL")) { "" } elseif ($wr.Score -gt 0) { "+" } elseif ($wr.Score -lt 0) { [string][char]0x2212 } else { [string][char]0x00B7 }
            $i = $g.Rows.Add((Tr $r.Name), $r.Value, $wTxt, (Tr $r.Text))
            $col = if ($r.Score -gt 0) { $colGreen } elseif ($r.Score -lt 0) { $colRed } else { $p.Muted }
            $g.Rows[$i].Cells[3].Style.ForeColor = $col
            if ($null -ne $wr -and $wTxt) {
                $g.Rows[$i].Cells[2].Style.ForeColor = if ($wr.Score -gt 0) { $colGreen } elseif ($wr.Score -lt 0) { $colRed } else { $p.Muted }
                $g.Rows[$i].Cells[2].ToolTipText = "{0}: {1} - {2}" -f (Tr "Wochenkurse"), $wr.Value, (Tr $wr.Text)
            }
        }
        $sc = [int]$sig.Score
        $vd = Get-TimeframeVerdict -Daily $sc -Weekly ([int]$wsig.Score) -HasWeekly (@($wb.Close).Count -ge 30)
        $c.Gauge = @{ Daily = $sc; Weekly = [int]$wsig.Score }
        if ($null -ne $c.GaugePanel) { $c.GaugePanel.Invalidate() }
        $c.TSum.ForeColor = if ($vd.Tone -gt 0) { $colGreen } elseif ($vd.Tone -lt 0) { $colRed } else { $script:Pal.Warn }
        $c.TSum.Text = "{0} {1:+0;-0;0} / {2} {3:+0;-0;0}: {4}" -f (Tr "Tag"), $sc, (Tr "Woche"), [int]$wsig.Score, (Tr $vd.Text)
        Set-DynTip $c.TSum ("{0}: {1} ({2} {3}, {4} {5})`r`n{6}: {7}`r`n{8} {9}" -f (Tr "Tageskurse"), (Tr $sig.Summary), $sig.Positive, (Tr "positiv"), $sig.Negative, (Tr "negativ"), (Tr "Wochenkurse"), (Tr $wsig.Summary), (Tr "Kurse in"), $c.Bars.Currency)
    } elseif ($c.Failed) {
        [void]$g.Rows.Add((Tr "Kursverlauf nicht verfügbar"), "", "", "")
        $c.TSum.Text = ""
    } else {
        [void]$g.Rows.Add((Tr "Lade Kursverlauf (2 Jahre) ..."), "", "", "")
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
    # v5.7: valuation vs. own history (snapshots collected since v5.7)
    $vh = @(Get-ValuationVsHistory -History $script:FundHist[$sym] -Fund $fund)
    $nSnap = @($script:FundHist[$sym]).Count
    $hi = $f.Rows.Add((Tr "Bewertung vs. eigene Historie"), "", (Tr "Median"), $(if ($vh.Count -gt 0) { "{0} {1} ({2} {3})" -f (Tr "seit"), (Format-IsoDateDe ([string]$vh[0].Since)), $vh[0].Count, (Tr "Tage") } else { "{0} ({1} {2})" -f (Tr "ab 20 Tagen Daten"), $nSnap, (Tr "bisher") }))
    $f.Rows[$hi].DefaultCellStyle.Font = $fontUiBold
    $f.Rows[$hi].DefaultCellStyle.ForeColor = $p.Accent
    foreach ($r in $vh) {
        $pct = ($r.Key -eq "DivYield")
        $fmt = { param($v) if ($pct) { "{0:N2}%" -f ($v * 100) } else { "{0:N1}" -f $v } }
        $i = $f.Rows.Add(("  " + (Tr $r.Label)), (& $fmt $r.Now), (& $fmt $r.Median), ("{0} ({1} {2}: {3} - {4})" -f (Tr $r.Note), (Tr "Rang"), $r.Rank, (& $fmt $r.Min), (& $fmt $r.Max)))
        $good = if ($pct) { $r.Rank -ge 80 } else { $r.Rank -le 20 }
        $bad = if ($pct) { $r.Rank -le 20 } else { $r.Rank -ge 80 }
        $f.Rows[$i].Cells[3].Style.ForeColor = if ($good) { $colGreen } elseif ($bad) { $colRed } else { $p.Muted }
    }
    # V6: Finnhub - figures over the years, valuation vs. quarterly history, earnings, analysts
    $addHead = { param([string]$T, [string]$Note) $hx = $f.Rows.Add((Tr $T), "", "", $Note); $f.Rows[$hx].DefaultCellStyle.Font = $fontUiBold; $f.Rows[$hx].DefaultCellStyle.ForeColor = $p.Accent }
    $mj = Get-ProviderData $sym "Metric"
    if ($null -ne $mj) {
        $ms = ConvertFrom-FinnhubMetricSeries $mj
        if (@($ms.Annual).Count -gt 0) {
            & $addHead "Kennzahlen über die Jahre" "Finnhub"
            foreach ($r in $ms.Annual) {
                $last = [double]$r.Points[-1].Value
                $i = $f.Rows.Add(("  " + (Tr $r.Label)), $(if ($r.Kind -eq "Pct") { "{0:N1}%" -f $last } else { "{0:N2}" -f $last }), "", (Format-SeriesTrend -Points $r.Points -Kind $r.Kind))
                $f.Rows[$i].Cells[3].Style.ForeColor = $p.Muted
            }
        }
        $vq = @(Get-ValuationVsHistory -History $ms.Quarterly -Fund $fund -MinDays 8)
        if ($vq.Count -gt 0) {
            & $addHead "Bewertung vs. Historie (Quartale)" ("{0} {1}, {2} {3}" -f (Tr "seit"), (Format-IsoDateDe ([string]$vq[0].Since)), $vq[0].Count, (Tr "Quartale"))
            foreach ($r in $vq) {
                $i = $f.Rows.Add(("  " + (Tr $r.Label)), ("{0:N1}" -f $r.Now), ("{0:N1}" -f $r.Median), ("{0} ({1} {2})" -f (Tr $r.Note), (Tr "Rang"), $r.Rank))
                $f.Rows[$i].Cells[3].Style.ForeColor = if ($r.Rank -le 20) { $colGreen } elseif ($r.Rank -ge 80) { $colRed } else { $p.Muted }
            }
        }
    }
    $ej = Get-ProviderData $sym "Earnings"
    if ($null -ne $ej) {
        $bd = if ($null -ne $c.Bars) { [string[]]$c.Bars.Dates } else { @() }
        $bc = if ($null -ne $c.Bars) { [double[]]$c.Bars.Close } else { @() }
        $ers = @(ConvertFrom-FinnhubEarnings -Earnings $ej -Calendar (Get-ProviderData $sym "Calendar") -Dates $bd -Closes $bc)
        if ($ers.Count -gt 0) {
            & $addHead "Quartalszahlen: Gewinn je Aktie" (Tr "Ist vs. Erwartung, Kursreaktion")
            foreach ($r in $ers) {
                $rxT = if ([double]::IsNaN($r.ReactionPct)) { "" } else { "{0} {1:+0.0;-0.0}%" -f (Tr "Kurs"), $r.ReactionPct }
                $i = $f.Rows.Add(("  " + (Format-IsoDateDe $r.Period)), $(if ([double]::IsNaN($r.Actual)) { "-" } else { "{0:N2}" -f $r.Actual }), $(if ([double]::IsNaN($r.Estimate)) { "-" } else { "{0:N2}" -f $r.Estimate }),
                    ("{0}{1}" -f $(if ([double]::IsNaN($r.SurprisePct)) { "" } else { "{0} {1:+0.0;-0.0}%" -f (Tr "Überraschung"), $r.SurprisePct }), $(if ($rxT) { ", " + $rxT } else { "" })))
                $f.Rows[$i].Cells[3].Style.ForeColor = if ($r.SurprisePct -gt 0) { $colGreen } elseif ($r.SurprisePct -lt 0) { $colRed } else { $p.Muted }
            }
        }
    }
    $rt = Get-RecommendationTrend (Get-ProviderData $sym "Recommendation")
    if ($null -ne $rt) {
        & $addHead "Analysten (Trend)" ("Finnhub, {0}" -f (Format-IsoDateDe $rt.Period))
        $i = $f.Rows.Add(("  " + (Tr "Empfehlungen jetzt")), ("{0:N2}" -f $rt.Score), ("{0:N2}" -f $rt.ScoreBefore), ("{0} ({1} {2}: {3}) - {4}" -f $rt.Now, (Tr "vor 3 Monaten"), (Format-IsoDateDe $rt.PeriodBefore), $rt.Before, (Tr $rt.Trend)))
        $f.Rows[$i].Cells[3].Style.ForeColor = if ($rt.Trend -eq "positiver") { $colGreen } elseif ($rt.Trend -eq "negativer") { $colRed } else { $p.Muted }
        $f.Rows[$i].Cells[1].ToolTipText = Tr "1 = starker Kauf ... 5 = starker Verkauf (Durchschnitt); Spalte Vergleich = vor 3 Monaten"
    }
    $pt = Get-ProviderData $sym "PriceTarget"
    if ($null -ne $pt -and $null -ne $pt.PSObject.Properties["targetMean"] -and [double]$pt.targetMean -gt 0) {
        $i = $f.Rows.Add(("  " + (Tr "Kursziel (Mittel)")), ("{0:N2}" -f [double]$pt.targetMean), ("{0:N2} - {1:N2}" -f [double]$pt.targetLow, [double]$pt.targetHigh), ("Finnhub, {0}" -f [string]$pt.lastUpdated))
    }
    if (-not (Get-ProviderKey "Finnhub") -and (Test-UsSymbol $sym)) {
        $i = $f.Rows.Add((Tr "Mehr mit Finnhub"), "", "", (Tr "Kostenloser Schlüssel in Einstellungen > Daten: Kennzahlen über Jahre, Quartalszahlen, Analysten-Trend"))
        $f.Rows[$i].DefaultCellStyle.ForeColor = $p.Muted
    }
    $c.FNote.Text = if ([bool]$pe.Own) {
        $miss = @(@($pe.Wanted) | Where-Object { @($pe.Syms) -notcontains $_ })
        "{0}: {1}{2}" -f (Tr "Vergleich = Median deiner Vergleichsgruppe (PEER)"), (@($pe.Syms) -join ", "), $(if ($miss.Count -gt 0) { " - " + (Tr "lädt noch") + ": " + ($miss -join ", ") } else { "" })
    } elseif (@($pe.Syms).Count -ge 2) {
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
    $dlg = New-DialogForm -Title "Ticker-Analyse - $sym (TA)" -W (S 1080) -H (S 660) -Key "TA"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MaximizeBox = $true
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 900), (S 520))
    $title = New-Object System.Windows.Forms.Label
    $title.SetBounds((S 12), (S 10), (S 846), (S 24)); $title.Anchor = $aT -bor $aL -bor $aR
    $title.Font = $fontUiBold; $title.ForeColor = $p.Accent; $title.AutoEllipsis = $true
    $dlg.Controls.Add($title)
    # V7.0: signal gauge (daily and weekly score on a red - grey - green scale)
    $gauge = New-Object System.Windows.Forms.Panel
    $gauge.SetBounds((S 868), (S 6), (S 200), (S 30)); $gauge.Anchor = $aT -bor $aR
    Enable-DoubleBuffering -Control $gauge
    $gauge.Add_Paint({
        param($sender, $e)
        $g = $e.Graphics
        $pp = $script:Pal
        $g.Clear($sender.Parent.BackColor)
        $tc = $script:TaCtl
        if ($null -eq $tc -or $null -eq $tc.Gauge) { return }
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rows = @(@("Tag", [int]$tc.Gauge.Daily), @("Woche", [int]$tc.Gauge.Weekly))
        $x0 = S 44; $tw = $sender.Width - $x0 - (S 4); $th = S 8
        for ($k = 0; $k -lt 2; $k++) {
            $y = (S 3) + $k * (S 13)
            [System.Windows.Forms.TextRenderer]::DrawText($g, (Tr $rows[$k][0]), $fontAxis, (New-Object System.Drawing.Rectangle(0, ($y - (S 2)), $x0, (S 13))), $pp.Muted, ([System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::NoPadding))
            $seg = [int]($tw / 3)
            $cols = @((Get-BlendColor -A $script:colRed -B $pp.Card -T 0.55), (Get-BlendColor -A $pp.Muted -B $pp.Card -T 0.35), (Get-BlendColor -A $script:colGreen -B $pp.Card -T 0.55))
            for ($s2 = 0; $s2 -lt 3; $s2++) {
                $sb = New-Object System.Drawing.SolidBrush($cols[$s2])
                $g.FillRectangle($sb, ($x0 + $s2 * $seg), $y, $seg, $th); $sb.Dispose()
            }
            $sc2 = [math]::Max(-6, [math]::Min(6, [int]$rows[$k][1]))
            $mx = $x0 + [int](($sc2 + 6) / 12.0 * $tw)
            $mb = New-Object System.Drawing.SolidBrush($pp.Text)
            $g.FillEllipse($mb, ($mx - (S 4)), ($y - 1), (S 8), ($th + 2)); $mb.Dispose()
        }
    })
    $dlg.Controls.Add($gauge)
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
    foreach ($cd in @(@("Sig", "Signal", 140), @("Val", "Wert (Tag)", 110), @("Wk", "Woche", 90), @("Txt", "Einordnung", 190))) { $ci = $tg.Columns.Add($cd[0], $cd[1]); $tg.Columns[$ci].FillWeight = [float](S $cd[2]); $tg.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable }
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
    # v5.5: note to the ticker
    $bNote = New-Object System.Windows.Forms.Button
    $bNote.SetBounds((S 858), (S 622), (S 100), (S 28)); $bNote.Anchor = $aB -bor $aR
    Style-FlatButton -Btn $bNote -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $bNote.Text = $(if (Get-TickerNote $sym) { "Notiz " + [string][char]0x270E } else { "Notiz ..." })
    $bNote.Tag = $sym
    Set-DynTip $bNote $(if (Get-TickerNote $sym) { Get-NoteSnippet (Get-TickerNote $sym) -Max 300 } else { "Eigene Notiz zum Ticker: These, Kaufgrund, Ziele" })
    $bNote.Add_Click({ param($sender, $e) Show-NoteDialog -Ticker ([string]$sender.Tag); $sender.Text = $(if (Get-TickerNote ([string]$sender.Tag)) { "Notiz " + [string][char]0x270E } else { "Notiz ..." }) })
    $dlg.Controls.Add($bNote)
    # v5.7: own comparison group
    $bPeer = New-Object System.Windows.Forms.Button
    $bPeer.SetBounds((S 718), (S 622), (S 130), (S 28)); $bPeer.Anchor = $aB -bor $aR
    Style-FlatButton -Btn $bPeer -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $bPeer.Text = "Vergleichsgruppe ..."; $bPeer.Tag = $sym
    Set-DynTip $bPeer "Eigene Ticker für die Spalte 'Vergleich' statt des Sektors (Befehl NVDA PEER AMD INTC)"
    $bPeer.Add_Click({ param($sender, $e) [void](Invoke-TerminalCommand (([string]$sender.Tag) + " PEER")) })
    $dlg.Controls.Add($bPeer)
    # the chart grows with the window width (left half)
    $dlg.Add_Resize({
        param($sender, $e)
        $c0 = $script:TaCtl
        if ($null -eq $c0) { return }
        $w2 = [int](($sender.ClientSize.Width - (S 36)) / 2)
        foreach ($ctl in @($c0.Chart, $c0.TGrid, $c0.TSum, $c0.TLabel)) { $ctl.Width = $w2 }
        foreach ($ctl in @($c0.FGrid, $c0.FNote, $c0.FLabel)) { $ctl.Left = $w2 + (S 24); $ctl.Width = $sender.ClientSize.Width - $w2 - (S 36) }
    })
    $chart.Add_Paint({ param($sender, $e) try { Draw-TickerAnalysisChart -g $e.Graphics -W $sender.ClientSize.Width -H $sender.ClientSize.Height } catch { Write-WidgetLog "TA chart: $($_.Exception.Message)" "WARN" } })
    $script:TaCtl = @{ Sym = $sym; Dlg = $dlg; Title = $title; GaugePanel = $gauge; Gauge = $null; Chart = $chart; TGrid = $tg; TSum = $tsum; FGrid = $fg; FNote = $fnote; FLabel = $lf; TLabel = $lt; Bars = $null; Sig = $null; Failed = $false; FundTried = $false }
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
            # V6: no Yahoo history -> Twelve Data / Finnhub (1 year)
            if ($c1.Failed -and (Request-ProviderBars -Sym $c1.Sym -OnBars { param($b) $c2 = $script:TaCtl; if ($null -ne $c2) { $c2.Bars = $b; $c2.Failed = $false; Update-TickerAnalysis } })) { $c1.Failed = $false }
            Update-TickerAnalysis
        }
        Request-ProviderAnalysis -Sym $c0.Sym
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
                if ($arg0 -eq "FOCUS") {
                    # V7.0: chart + watchlist, no portfolio
                    $script:Config.TerminalShowWatch = $true
                    $script:Config.TerminalShowPortfolio = $false
                    Save-JsonState -Path $script:ConfigPath -Data $script:Config
                    Apply-Layout "Terminal"
                    return ""
                }
                $full = (@($c.Args) -join " ").Trim()
                $ln = @(Get-LayoutNames | Where-Object { $_.ToUpper() -eq $arg0 })
                if ($ln.Count -gt 0) { Apply-Layout $ln[0]; return "" }
                if (Use-UserLayout -Name $full) { return "" }
                $own = @(@($script:Config.UserLayouts) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.Name })
                return "Layout: " + ((@(Get-LayoutNames) + @("Focus") + $own) -join " / ") + " - eigenes speichern: LAYOUT SAVE <Name>"
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
                    "R" { Set-DrawMode "R" } "ZONE" { Set-DrawMode "R" } "N" { Set-DrawMode "N" } "TEXT" { Set-DrawMode "N" }
                    "CLEAR" { Remove-Drawing -All }
                    default { return "DRAW H (Linie) / T (Trendlinie) / F (Fibonacci) / R (Zone) / N (Text) / CLEAR" }
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
                if ($arg0 -eq "PCT") { Set-ChartOption -Key "PctAxis" -On (-not [bool]$script:Config.PctAxis); return "" }
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
            "HEALTH" { Show-HealthReport }
            "PROV"   { Test-Providers }
            "IMG"    {
                # IMG = chart to the clipboard, IMG SAVE, IMG WIN (whole window), IMG WIN SAVE
                $aa = @($c.Args | ForEach-Object { ([string]$_).ToUpper() })
                $md = if ($aa -contains "SAVE") { "Save" } else { "Copy" }
                if ($aa -contains "WIN") { [void](Export-ControlImage -Ctl $form -Mode $md -Name "TerminalWidget") } else { [void](Export-ChartImage -Mode $md) }
            }
            "DIAG"   { [void](Export-Diagnostics) }
            "SET"    { $null = Show-SettingsDialog -Search ((@($c.Args) -join " ").Trim()) }
            "MENU"   { return (Invoke-MenuEntry ((@($c.Args) -join " ").Trim())) }
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
        "PEER" {
            # v5.7: NVDA PEER AMD INTC TSM / NVDA PEER - (delete) / NVDA PEER (edit)
            $rest = (@($c.Args) -join " ").Trim()
            if ($rest -eq "-") { Set-PeerGroup -Sym $sym -Peers @(); Set-TransientStatus ("Vergleichsgruppe von {0} gelöscht - wieder Sektor" -f $sym) 4; return "" }
            if (-not $rest) { $rest = Read-TextPrompt -Title ("Vergleichsgruppe - {0}" -f $sym) -Prompt "Ticker für den Vergleich, z. B. AMD INTC TSM (leer = Sektor)" -Value ((Get-PeerGroup $sym) -join " ") }
            $pl = @(ConvertTo-PeerList -Text $rest -Self $sym)
            Set-PeerGroup -Sym $sym -Peers $pl
            Set-TransientStatus $(if ($pl.Count -gt 0) { "Vergleichsgruppe {0}: {1}" -f $sym, ($pl -join ", ") } else { "Vergleichsgruppe von {0} gelöscht" -f $sym }) 5
            if ($null -ne $script:TaCtl -and $script:TaCtl.Sym -eq $sym) { Update-TickerAnalysis }
        }
        "NOTE" {
            $rest = (@($c.Args) -join " ").Trim()
            if ($rest) { Set-TickerNote -Ticker $sym -Text $rest; Set-TransientStatus ("Notiz zu {0} gespeichert" -f $sym) 3 }
            else { Show-NoteDialog -Ticker $sym }
        }
        "CMP"  { Switch-CompareTicker -Symbol $sym; if ([string]$script:Config.Layout -ne "Terminal") { Set-ActiveTab -TabName "Chart" } }
        "TX"   { Show-TransactionDialog -Ticker $sym }
    }
    return ""
}

# ---- Ctrl+K: command palette ----
function Update-PaletteSuggestions {
    $pc = $script:PalCtl
    if ($null -eq $pc) { return }
    $pc.Items = @(Get-CommandSuggestions -Text $pc.Text.Text -Tickers (Get-KnownTickers) -Recent @($script:Config.CommandHistory) -Max 12 -Depots @(Get-DepotList | ForEach-Object { $_.Name }) -Layouts @(@($script:Config.UserLayouts) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_.Name }) -Extra (Get-PaletteExtras))
    $pc.List.BeginUpdate()
    $pc.List.Items.Clear()
    foreach ($it in $pc.Items) { $it.Desc = Tr ([string]$it.Desc); [void]$pc.List.Items.Add($it.Text) }
    $pc.List.EndUpdate()
    $pc.List.SelectedIndex = -1
    $pc.Err.Text = ""
}

# v5.3: Ctrl+K also reaches every setting ("SET ...") and every menu entry ("MENU ...")
function Get-MenuPaletteEntries {
    $out = New-Object System.Collections.Generic.List[object]
    $walk = {
        param($Items, [string]$Where, [string]$Prefix)
        foreach ($it in @($Items)) {
            if ($it -isnot [System.Windows.Forms.ToolStripMenuItem]) { continue }
            $t = (([string]$it.Text) -replace '&', '').Trim()
            if (-not $t) { continue }
            $full = if ($Prefix) { "$Prefix > $t" } else { $t }
            if ($it.DropDownItems.Count -gt 0) { & $walk $it.DropDownItems $Where $full; continue }
            $out.Add([PSCustomObject]@{ Text = ("MENU " + $full.ToUpperInvariant()); Desc = ("{0} - {1}" -f (Tr "Menü"), $Where); Search = $full; Item = $it; Where = $Where })
        }
    }
    & $walk $trayMenu.Items "Tray" ""
    & $walk $layoutMenu.Items "Layout" ""
    if ($null -ne $chartContextMenu) { & $walk $chartContextMenu.Items "Chart" "" }
    return $out.ToArray()
}

