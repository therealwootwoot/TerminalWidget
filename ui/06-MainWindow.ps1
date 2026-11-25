# TerminalWidget UI part 06 (MainWindow) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

function Update-MainLayout {
    if ([bool]$script:Config.CompactMode) { $script:PnlStatusBar.Visible = $false }
    if ([bool]$script:Config.CompactMode -or $form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { return }
    $W = $form.ClientSize.Width
    $H = $form.ClientSize.Height
    if ($W -lt (S 400) -or $H -lt (S 300)) { return }

    # V7.0: status bar at the bottom edge; the views end above it
    $sbH = 0
    if ([bool]$script:Config.ShowStatusBar) {
        $sbH = S 22
        $script:PnlStatusBar.SetBounds(0, ($H - $sbH), $W, $sbH)
        $script:PnlStatusBar.Visible = $true
        $script:PnlStatusBar.BringToFront()
    } else { $script:PnlStatusBar.Visible = $false }

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
    $vh = $H - (S 92) - (S 12) - $sbH
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
    Update-MenuRenderer
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
    Update-TabHighlight   # v5.5: Fresh pill tabs follow the style
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
            elseif ($tag -like "Style:*") { $it.Checked = ($tag -eq ("Style:" + $script:Config.UiStyle)) }
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
    # v5.5: signal column visible -> daily bars for the watchlist (once a day)
    if ($dgvWatchlist.Columns["Signal"].Visible -and -not $script:SmokeMode) { Request-DailyBars -Symbols @($script:Config.Watchlist) }
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
            $sigCell = Format-SignalCell $script:DailyCache[$uSym]
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
                $tgtStr,
                $sigCell.Text
            )
            $row = $dgvWatchlist.Rows[$idx]
            if ($sigCell.Sign -ne 0) { $row.Cells["Signal"].Style.ForeColor = if ($sigCell.Sign -gt 0) { $colGreen } else { $colRed } }
            if ($sigCell.Tip) { $row.Cells["Signal"].ToolTipText = $sigCell.Tip }
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
            } elseif ($null -ne $ms -and [string]$ms.State -eq "REGULAR" -and $null -ne $q.UpdatedAt) {
                # v5.5: stale while the market is open -> clock in front of the price
                $ageS = ((Get-Date) - [DateTime]$q.UpdatedAt).TotalSeconds
                if ((Get-StalenessLevel -AgeSec $ageS -RefreshSec ([int]$script:Config.SlowRefreshSeconds)) -ne "OK") {
                    $row.Cells["Price"].Value = [string][char]0x25F7 + " " + [string]$row.Cells["Price"].Value
                    $row.Cells["Price"].Style.ForeColor = $script:Pal.Warn
                    $row.Cells["Price"].ToolTipText = "Kurs seit {0:N0} Min. nicht aktualisiert (Stand {1}) - Börse ist offen" -f ($ageS / 60), ([DateTime]$q.UpdatedAt).ToString("HH:mm")
                }
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
            # v5.5: loading skeleton (grey bars) instead of "..." until the first quote
            $skI = $dgvWatchlist.Rows.Add($uSym, "", "", "", "", "", "", "", "", "")
            $dgvWatchlist.Rows[$skI].Tag = "skel"
            $dgvWatchlist.Rows[$skI].Cells[0].ToolTipText = "Kurs wird geladen ..."
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
    $dlg = New-DialogForm -Title "Alarm-Verlauf - $($script:AppTitle)" -W (S 760) -H (S 440) -Key "AlertLog"
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

