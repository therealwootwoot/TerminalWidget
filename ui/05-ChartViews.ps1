# TerminalWidget UI part 05 (ChartViews) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

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
    $cv.Add_DoubleClick({ if ($script:OnPriceAxis) { Reset-PriceScale } else { Close-ChartFullscreen } })
    $fs.Controls.Add($cv)
    # v5.5: small toolbar top right: drawing tools, zoom reset, close
    $tb0 = New-Object System.Windows.Forms.Panel
    $tbItems = @(@("H", [string][char]0x2014, "Horizontale Linie"), @("T", "/", "Trendlinie (D)"), @("F", "Fib", "Fibonacci"), @("R", [string][char]0x25AD, "Zone (Rechteck)"), @("N", "Aa", "Textnotiz"), @("Z", "1:1", "Zoom zurücksetzen (Z)"), @("X", [string][char]0x2715, "Vollbild schließen (Esc)"))
    $tb0.Size = New-Object System.Drawing.Size(((S 34) * $tbItems.Count + (S 4)), (S 30))
    $tb0.Location = New-Object System.Drawing.Point(($scr.Bounds.Width - $tb0.Width - (S 70)), (S 6))
    $tb0.BackColor = $script:Pal.HeaderBg
    $tb0.Name = "fsToolbar"
    $bx = S 2
    foreach ($ti in $tbItems) {
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds($bx, (S 3), (S 32), (S 24))
        Style-FlatButton -Btn $b -BgColor $script:Pal.Input -FgColor $script:Pal.Text -BorderColor $script:Pal.Border
        $b.Text = $ti[1]; $b.Tag = $ti[0]; $b.TabStop = $false
        Set-DynTip $b $ti[2]
        $b.Add_Click({
            param($sender, $e)
            switch ([string]$sender.Tag) { "Z" { Reset-ChartZoom } "X" { Close-ChartFullscreen } default { Set-DrawMode ([string]$sender.Tag) } }
            if ($null -ne $script:FsCanvas -and -not $script:FsCanvas.IsDisposed) { $script:FsCanvas.Focus() | Out-Null }
        })
        $tb0.Controls.Add($b)
        $bx += S 34
    }
    $fs.Controls.Add($tb0)
    $tb0.BringToFront()

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
$viewPortfolio.Location = New-Object System.Drawing.Point((S 12), ((S 92) + $script:MenuH))
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
$cmbDepot = New-ThemedCombo
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

$cmbPortSort = New-ThemedCombo
$cmbPortSort.Location = New-Object System.Drawing.Point((S 612), (S 6))
$cmbPortSort.Size = New-Object System.Drawing.Size((S 136), (S 24))
$cmbPortSort.DropDownWidth = S 200
$cmbPortSort.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$cmbPortSort.BackColor = $script:Pal.Input
$cmbPortSort.ForeColor = $script:Pal.Text
$cmbPortSort.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbPortSort.Font = $fontUi
[void]$cmbPortSort.Items.Add("Sort: Wert (ab)")
[void]$cmbPortSort.Items.Add("Sort: G/V % (ab)")
[void]$cmbPortSort.Items.Add("Sort: Tag %")
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

# V7.0: day change as a pill (coloured background, not only coloured text); optional
$script:DayPillPainter = {
    param($sender, $e)
    if (-not [bool]$script:Config.DayChangePill -or $e.RowIndex -lt 0 -or $e.ColumnIndex -lt 0 -or $sender.Columns[$e.ColumnIndex].Name -ne "Day") { return }
    $txt = [string]$e.FormattedValue
    if ([string]::IsNullOrWhiteSpace($txt)) { return }
    try {
        $sel = (($e.State -band [System.Windows.Forms.DataGridViewElementStates]::Selected) -ne 0)
        $e.PaintBackground($e.ClipBounds, $sel)
        $fg = $e.CellStyle.ForeColor
        if ($sel) { $fg = $e.CellStyle.SelectionForeColor }
        $bgc = if ($sel) { $e.CellStyle.SelectionBackColor } else { $e.CellStyle.BackColor }
        if ($bgc.A -lt 255) { $bgc = $script:Pal.Card }
        $flags = [System.Windows.Forms.TextFormatFlags]::NoPadding
        $tw = [System.Windows.Forms.TextRenderer]::MeasureText($txt, $e.CellStyle.Font, [System.Drawing.Size]::Empty, $flags).Width
        $b = $e.CellBounds
        $w = [math]::Min($b.Width - (S 6), $tw + (S 12))
        $h = [math]::Min($b.Height - (S 4), (S 18))
        $r = New-Object System.Drawing.RectangleF(([float]($b.Right - $w - (S 3))), ([float]($b.Y + ($b.Height - $h) / 2)), [float]$w, [float]$h)
        $g = $e.Graphics
        $br = New-Object System.Drawing.SolidBrush((Get-MixColor -A $fg -B $bgc -T 0.22))
        Fill-RoundedRect -g $g -Brush $br -Rect $r -Radius ([float]($h / 2))
        $br.Dispose()
        $tf = [System.Windows.Forms.TextFormatFlags]
        [System.Windows.Forms.TextRenderer]::DrawText($g, $txt, $e.CellStyle.Font, (New-Object System.Drawing.Rectangle([int]$r.X, [int]$r.Y, [int]$r.Width, [int]$r.Height)), $fg, ($tf::HorizontalCenter -bor $tf::VerticalCenter -bor $tf::NoPadding -bor $tf::SingleLine))
        $e.Handled = $true
    } catch { }
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

$cmbPortCurr = New-ThemedCombo
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

# v7.5: the top-up calculator has its own row that opens on demand
$txtPortBuyAmt = New-PortInput -LabelText "Nachkauf:"     -X 8   -Y 88 -W 96
$lblPortBuyAmt = $script:PortInputLabels[$script:PortInputLabels.Count - 1]
$txtPortTarget = New-PortInput -LabelText "Oder Ziel-EK:" -X 110 -Y 88 -W 98
$lblPortTarget = $script:PortInputLabels[$script:PortInputLabels.Count - 1]
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
$btnPortTx.Location = New-Object System.Drawing.Point((S 476), (S 56))
$btnPortTx.Size = New-Object System.Drawing.Size((S 90), (S 26))
Style-FlatButton -Btn $btnPortTx -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnPortTx.Font = $fontUiBold
$btnPortTx.Text = "Transaktion"
$pnlPortBottom.Controls.Add($btnPortTx)
Set-Tip $btnPortTx "Kauf / Verkauf / Dividende buchen (realisierter G/V wird gespeichert)" "TX"

# v5.0: more depot tools behind a small menu button
$btnPortMore = New-Object System.Windows.Forms.Button
$btnPortMore.Location = New-Object System.Drawing.Point((S 568), (S 56))
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
$btnPortHist.Location = New-Object System.Drawing.Point((S 600), (S 56))
$btnPortHist.Size = New-Object System.Drawing.Size((S 62), (S 26))
Style-FlatButton -Btn $btnPortHist -BgColor $script:Pal.Input -FgColor $script:Pal.Muted -BorderColor $script:Pal.Border
$btnPortHist.Font = $fontUi
$btnPortHist.Text = "Historie"
$pnlPortBottom.Controls.Add($btnPortHist)
Set-Tip $btnPortHist "Alle Transaktionen, realisierter G/V, CSV-Export, Jahresreport" "REALIZED"

# v4.1: portfolio analysis (value history, returns, allocation)
$btnPortAna = New-Object System.Windows.Forms.Button
$btnPortAna.Location = New-Object System.Drawing.Point((S 666), (S 56))
$btnPortAna.Size = New-Object System.Drawing.Size((S 64), (S 26))
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

$btnPortSim = New-Object System.Windows.Forms.Button
$btnPortSim.Location = New-Object System.Drawing.Point((S 8), (S 56))
$btnPortSim.Size = New-Object System.Drawing.Size((S 150), (S 26))
Style-FlatButton -Btn $btnPortSim -BgColor $script:Pal.Input -FgColor $script:Pal.Text -BorderColor $script:Pal.Border
$btnPortSim.Font = $fontUi
$pnlPortBottom.Controls.Add($btnPortSim)
Set-Tip $btnPortSim "Nachkauf- und Ziel-EK-Rechner ein- oder ausklappen" "NACHKAUF"
$btnPortSim.Add_Click({
    $script:Config.PortSimOpen = -not [bool]$script:Config.PortSimOpen
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-PortSimLayout
    Update-NachkaufSimulation
})

function Update-PortSimLayout {
    # v7.5: closed = one message line next to the button; open = inputs + result below
    $open = [bool]$script:Config.PortSimOpen
    $arrow = if ($open) { [string][char]0x25BE } else { [string][char]0x25B8 }
    $btnPortSim.Text = "{0} {1}" -f $arrow, (Tr "Nachkauf-Rechner")
    foreach ($c in @($lblPortBuyAmt, $txtPortBuyAmt, $lblPortTarget, $txtPortTarget)) { $c.Visible = $open }
    $h = if ($open) { S 172 } else { S 90 }
    $pnlPortBottom.SetBounds($pnlPortBottom.Left, ($viewPortfolio.ClientSize.Height - $h - (S 8)), $pnlPortBottom.Width, $h)
    $dgvPortfolio.Height = [math]::Max((S 40), ($pnlPortBottom.Top - $dgvPortfolio.Top - (S 6)))
    $right = $pnlPortBottom.Width - (S 8)
    if ($open) { $lblNachkaufOut.SetBounds((S 218), (S 90), [math]::Max((S 100), ($right - (S 218))), (S 78)) }
    else { $lblNachkaufOut.SetBounds((S 166), (S 55), [math]::Max((S 100), ($btnPortTx.Left - (S 174))), (S 30)) }
}

# ==============================================================================
# VIEW 3: WATCHLIST & ALARME VIEW
# ==============================================================================
$viewWatch = New-Object System.Windows.Forms.Panel
$viewWatch.Location = New-Object System.Drawing.Point((S 12), ((S 92) + $script:MenuH))
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
$lblWlTitle.Text = "Watchlist"
$viewWatch.Controls.Add($lblWlTitle)
Set-Tip $lblWlTitle "Ziehen = Reihenfolge, Entf = Löschen, Rechtsklick auf einen Ticker = Aktionen und Gruppen"

# v5.0: watchlist groups (e.g. Tech, ETFs) - a filter over the one watchlist
$cmbWlGroup = New-ThemedCombo
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
    if ($null -ne $script:PnlWlChips) { $script:PnlWlChips.Invalidate() }
}
function Set-WatchGroup {
    param([string]$Name)
    $script:Config.WatchGroup = $Name
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-WatchGroupCombo
    Refresh-WatchlistAndAlerts
    Update-LinkedColumnSet
}
function New-WatchGroup {
    param([string]$Symbol = "")
    $nm = Read-TextInput -Title "Neue Gruppe" -Prompt "Name der Gruppe (z. B. Tech, ETFs, Dividenden):"
    if (-not $nm) { return "" }
    $nm = $nm.Trim()
    if (@($script:Config.WatchGroups | Where-Object { $null -ne $_ -and [string]$_.Name -eq $nm }).Count -eq 0) {
        $script:Config.WatchGroups = Set-WatchGroupMember -Groups @($script:Config.WatchGroups) -Group $nm -Symbol $Symbol -In $true
    } elseif ($Symbol) {
        $script:Config.WatchGroups = Set-WatchGroupMember -Groups @($script:Config.WatchGroups) -Group $nm -Symbol $Symbol -In $true
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

# V7.0: group chips above the list instead of the drop-down (the hidden drop-down still holds the state).
# Click = show group, "+" = new group, right click = delete, drop a ticker on a chip = add it to the group.
$cmbWlGroup.Visible = $false
$script:PnlWlChips = New-Object System.Windows.Forms.Panel
$script:PnlWlChips.Location = New-Object System.Drawing.Point((S 8), (S 64))
$script:PnlWlChips.Size = New-Object System.Drawing.Size((S 480), (S 28))
$script:PnlWlChips.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$script:PnlWlChips.AllowDrop = $true
$script:PnlWlChips.TabStop = $false
Enable-DoubleBuffering -Control $script:PnlWlChips
$viewWatch.Controls.Add($script:PnlWlChips)
Set-Tip $script:PnlWlChips "Gruppen: Klick zeigt die Gruppe, + legt eine neue an, Rechtsklick löscht. Einen Ticker aus der Liste auf eine Gruppe ziehen, um ihn einzusortieren."
$script:WlChips = @()
$script:WlChipHot = -1

function Get-WlChipModel {
    # chips in order: Alle, every group, then (if too narrow) a "more" chip and the "+" chip
    $items = @()
    $items += [PSCustomObject]@{ Key = ""; Text = ("{0} {1}" -f (Tr "Alle"), @($script:Config.Watchlist).Count); Kind = "group" }
    foreach ($gr in @($script:Config.WatchGroups)) {
        if ($null -eq $gr -or -not $gr.Name) { continue }
        $cnt = @(Get-WatchGroupSymbols -Watchlist @($script:Config.Watchlist) -Groups @($script:Config.WatchGroups) -Group ([string]$gr.Name)).Count
        $items += [PSCustomObject]@{ Key = [string]$gr.Name; Text = ("{0} {1}" -f $gr.Name, $cnt); Kind = "group" }
    }
    $flags = [System.Windows.Forms.TextFormatFlags]::NoPadding
    $widths = @($items | ForEach-Object { [int]([System.Windows.Forms.TextRenderer]::MeasureText($_.Text, $fontUi, [System.Drawing.Size]::Empty, $flags).Width + (S 20)) })
    $lay = Get-ChipLayout -Widths $widths -Available ([int]$script:PnlWlChips.Width) -Gap (S 6) -AddWidth (S 26) -MoreWidth (S 34)
    $out = @()
    for ($i = 0; $i -lt [int]$lay.Shown; $i++) {
        $items[$i] | Add-Member -NotePropertyName X -NotePropertyValue ([int]$lay.X[$i]) -Force
        $items[$i] | Add-Member -NotePropertyName W -NotePropertyValue ([int]$widths[$i]) -Force
        $out += $items[$i]
    }
    $nx = 0
    if ($out.Count -gt 0) { $nx = [int]$out[-1].X + [int]$out[-1].W + (S 6) }
    if ([bool]$lay.Overflow) {
        $hidden = @($items | Select-Object -Skip ([int]$lay.Shown))
        $out += [PSCustomObject]@{ Key = "|more"; Text = ([string][char]0x2026); Kind = "more"; X = $nx; W = (S 34); Hidden = $hidden }
        $nx += (S 34) + (S 6)
    }
    $out += [PSCustomObject]@{ Key = "|new"; Text = "+"; Kind = "add"; X = $nx; W = (S 26) }
    return $out
}

function Get-WlChipAt {
    param([int]$X, [int]$Y)
    if ($Y -lt (S 2) -or $Y -gt (S 26)) { return $null }
    foreach ($ch in @($script:WlChips)) { if ($X -ge [int]$ch.X -and $X -le ([int]$ch.X + [int]$ch.W)) { return $ch } }
    return $null
}

$script:PnlWlChips.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $p = $script:Pal
    $g.Clear($sender.Parent.BackColor)
    $script:WlChips = @(Get-WlChipModel)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $cur = [string]$script:Config.WatchGroup
    $hh = S 22
    $rad = if ($script:UiSpec.Fresh) { [float]($hh / 2) } else { [float](S $script:UiSpec.BtnRadius) }
    for ($i = 0; $i -lt $script:WlChips.Count; $i++) {
        $ch = $script:WlChips[$i]
        $sel = ($ch.Kind -eq "group" -and [string]$ch.Key -eq $cur)
        $hot = ($i -eq $script:WlChipHot)
        $fill = if ($sel) { $p.AccentSubtle } elseif ($hot) { $p.Hover } else { $p.Card }
        $line = if ($sel) { $p.Accent } else { $p.Border }
        $fg = if ($sel) { $p.Accent } elseif ($ch.Kind -eq "group") { $p.Text } else { $p.Muted }
        $br = New-Object System.Drawing.SolidBrush($fill)
        $pn = New-Object System.Drawing.Pen($line, 1)
        Fill-RoundedRect -g $g -Brush $br -Rect (New-Object System.Drawing.RectangleF([float]$ch.X, [float](S 3), [float]($ch.W - 1), [float]$hh)) -Radius $rad -Pen $pn
        $br.Dispose(); $pn.Dispose()
        $tf = [System.Windows.Forms.TextFormatFlags]
        $tr = New-Object System.Drawing.Rectangle([int]$ch.X, (S 3), [int]$ch.W, $hh)
        [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$ch.Text, $(if ($sel) { $fontUiBold } else { $fontUi }), $tr, $fg, ($tf::HorizontalCenter -bor $tf::VerticalCenter -bor $tf::SingleLine -bor $tf::NoPadding))
    }
})
$script:PnlWlChips.Add_Resize({ $script:PnlWlChips.Invalidate() })
$script:PnlWlChips.Add_MouseMove({
    param($sender, $e)
    $ch = Get-WlChipAt -X $e.X -Y $e.Y
    $ix = if ($null -eq $ch) { -1 } else { [array]::IndexOf(@($script:WlChips), $ch) }
    if ($ix -ne $script:WlChipHot) { $script:WlChipHot = $ix; $sender.Cursor = $(if ($ix -ge 0) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default }); $sender.Invalidate() }
})
$script:PnlWlChips.Add_MouseLeave({ $script:WlChipHot = -1; $script:PnlWlChips.Invalidate() })
$script:PnlWlChips.Add_MouseUp({
    param($sender, $e)
    $ch = Get-WlChipAt -X $e.X -Y $e.Y
    if ($null -eq $ch) { return }
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        if ($ch.Kind -eq "group") { Set-WatchGroup ([string]$ch.Key); if ($dgvWatchlist.CanFocus) { [void]$dgvWatchlist.Focus() } }
        elseif ($ch.Kind -eq "add") { $nm = New-WatchGroup; if ($nm) { Set-WatchGroup $nm } }
        elseif ($ch.Kind -eq "more") {
            $mm = New-Object System.Windows.Forms.ContextMenuStrip
            foreach ($hd in @($ch.Hidden)) {
                $mi = New-Object System.Windows.Forms.ToolStripMenuItem([string]$hd.Text)
                $mi.Tag = [string]$hd.Key
                $mi.Checked = ([string]$hd.Key -eq [string]$script:Config.WatchGroup)
                $mi.Add_Click({ param($s2, $e2) Set-WatchGroup ([string]$s2.Tag) })
                [void]$mm.Items.Add($mi)
            }
            $mm.Show($sender, (New-Object System.Drawing.Point([int]$ch.X, (S 28))))
        }
    }
    elseif ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right -and $ch.Kind -eq "group" -and [string]$ch.Key) {
        $gn = [string]$ch.Key
        if (Confirm-Action -Text ("Gruppe '{0}' löschen? (Die Ticker bleiben in der Watchlist.)" -f $gn) -Title "Gruppe") {
            $script:Config.WatchGroups = @(@($script:Config.WatchGroups) | Where-Object { $null -ne $_ -and [string]$_.Name -ne $gn })
            Set-WatchGroup $(if ([string]$script:Config.WatchGroup -eq $gn) { "" } else { [string]$script:Config.WatchGroup })
        }
    }
})
$script:PnlWlChips.Add_DragOver({
    param($sender, $e)
    $pt = $sender.PointToClient((New-Object System.Drawing.Point($e.X, $e.Y)))
    $ch = Get-WlChipAt -X $pt.X -Y $pt.Y
    $ok = ($null -ne $ch -and ($ch.Kind -eq "add" -or ($ch.Kind -eq "group" -and [string]$ch.Key)) -and $e.Data.GetDataPresent([string]))
    $e.Effect = if ($ok) { [System.Windows.Forms.DragDropEffects]::Move } else { [System.Windows.Forms.DragDropEffects]::None }
    $ix = if ($null -eq $ch -or -not $ok) { -1 } else { [array]::IndexOf(@($script:WlChips), $ch) }
    if ($ix -ne $script:WlChipHot) { $script:WlChipHot = $ix; $sender.Invalidate() }
})
$script:PnlWlChips.Add_DragLeave({ $script:WlChipHot = -1; $script:PnlWlChips.Invalidate() })
$script:PnlWlChips.Add_DragDrop({
    param($sender, $e)
    $script:WlChipHot = -1
    try {
        $pt = $sender.PointToClient((New-Object System.Drawing.Point($e.X, $e.Y)))
        $ch = Get-WlChipAt -X $pt.X -Y $pt.Y
        $sym = [string]$e.Data.GetData([string])
        if ($null -eq $ch -or [string]::IsNullOrWhiteSpace($sym)) { return }
        if ($ch.Kind -eq "add") {
            $nm = New-WatchGroup -Symbol $sym
            if ($nm) { Set-WatchGroup $nm }
        } elseif ($ch.Kind -eq "group" -and [string]$ch.Key) {
            $script:Config.WatchGroups = Set-WatchGroupMember -Groups @($script:Config.WatchGroups) -Group ([string]$ch.Key) -Symbol $sym -In $true
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Set-TransientStatus ("{0} -> {1}" -f $sym, [string]$ch.Key) 3
            Update-WatchGroupCombo
            Refresh-WatchlistAndAlerts
        }
    } catch { }
    $sender.Invalidate()
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
$dgvWatchlist.Location = New-Object System.Drawing.Point((S 8), (S 96))   # V7.0: group chips sit between the search row and the list
$dgvWatchlist.Size = New-Object System.Drawing.Size((S 480), (S 352))
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
[void]$dgvWatchlist.Columns.Add("Signal", "Signal")   # v5.5: score from the ticker analysis, hidden by default
$dgvWatchlist.Columns["Signal"].Visible = $false
# v8.0: more columns, hidden by default
foreach ($c8 in @(@("OwnTgt", "Zielkurs"), @("AlertDist", "Alarm-Abstand"), @("Note", "Notiz"), @("DayBase", "Heute (Währung)"))) {
    [void]$dgvWatchlist.Columns.Add($c8[0], $c8[1])
    $dgvWatchlist.Columns[$c8[0]].Visible = $false
}

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
$dgvWatchlist.Columns["Signal"].Width = S 52
$dgvWatchlist.Columns["OwnTgt"].Width = S 120
$dgvWatchlist.Columns["AlertDist"].Width = S 64
$dgvWatchlist.Columns["Note"].Width = S 110
$dgvWatchlist.Columns["DayBase"].Width = S 96
$dgvWatchlist.Columns["Signal"].ToolTipText = "Signal-Score der Ticker-Analyse (Tageskurse, einmal am Tag): Summe der positiven und negativen Signale. Keine Anlageberatung."

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
$dgvPortfolio.Add_CellPainting($script:DayPillPainter)
$dgvWatchlist.Add_CellPainting($script:SparkCellPainter)
$dgvWatchlist.Add_CellPainting($script:DayPillPainter)
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
        @($dgvWatchlist, @("Price", "Day", "Ext", "Rsi", "Dist", "Target", "Signal", "OwnTgt", "AlertDist", "DayBase")),
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
$viewNews.Location = New-Object System.Drawing.Point((S 12), ((S 92) + $script:MenuH))
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

$cmbNewsFilter = New-ThemedCombo
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
        $cnt = Get-NewsUnreadTotal
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
    if (@($Item.Also | Where-Object { $_ }).Count -gt 0) { $lines.Add((Tr "Auch bei:") + " " + (@($Item.Also) -join ", ")) }
    if ($Item.Summary) {
        $sm = [string]$Item.Summary
        if ($sm.Length -gt 240) { $sm = $sm.Substring(0, 239).TrimEnd() + [string][char]0x2026 }
        $lines.Add($sm)
    }
    if ($Item.Link) { $lines.Add((Tr "Doppelklick öffnet den Artikel im Browser")) }
    return ($lines -join "`r`n")
}

function Refresh-NewsGrid {
    # -IfChanged: skip when nothing changed (called on every price refresh;
    # the ages "vor 5 min" need at most one rebuild per minute)
    param([switch]$IfChanged)
    if ($null -eq $dgvNews -or $dgvNews.IsDisposed) { return }
    $sig = "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}" -f $script:NewsLoadedAt.Ticks, [string]$script:Config.NewsFilter, $script:NewsBoldSince.Ticks, (Get-Date).ToString("yyyyMMddHHmm"), $script:NewsLoading, @($script:NewsItems).Count, (@($script:Config.NewsMuted) -join ","), [bool]$script:Config.PrivacyMode, $script:NewsVersion, $script:NewsQuery, $script:NewsSavedMode
    if ($IfChanged -and $sig -eq $script:NewsGridSig) { return }
    $script:NewsGridSig = $sig
    $p = $script:Pal
    $items = @(Get-NewsShown)
    $highlight = @(ConvertTo-KeywordList ([string]$script:Config.NewsHighlight))
    $savedKeys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($sv in @($script:NewsSaved)) { if ($null -ne $sv) { [void]$savedKeys.Add([string]$sv.Key) } }
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
        $srcTxt = [string]$n.Publisher
        $alsoN = @($n.Also | Where-Object { $_ }).Count
        if ($alsoN -gt 0) { $srcTxt += " +" + $alsoN }
        $isSaved = $false
        foreach ($k in @(Get-NewsItemKeys $n)) { if ($savedKeys.Contains($k)) { $isSaved = $true; break } }
        $titleTxt = if ($isSaved) { [string][char]0x2605 + " " + [string]$n.Title } else { [string]$n.Title }
        $idx = $dgvNews.Rows.Add((Format-NewsAge -Time ([DateTime]$n.Time) -Now $now -Lang $lang), $symTxt, $srcTxt, $titleTxt)
        $row = $dgvNews.Rows[$idx]
        $row.Tag = $n
        $row.Cells["Age"].Style.ForeColor = $p.Muted
        $row.Cells["Src"].Style.ForeColor = $p.Muted
        $row.Cells["Syms"].Style.ForeColor = if ($null -eq $mv) { $p.Accent } elseif ($mv.Pct -ge 0) { $colGreen } else { $colRed }
        if ($highlight.Count -gt 0 -and (Test-NewsWords $n $highlight)) { $row.Cells["Title"].Style.ForeColor = $p.Warn }
        if (Test-NewsUnread -Item $n -Since $script:NewsBoldSince -ReadKeys $script:NewsRead -UnreadKeys $script:NewsUnread) {
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
        $msg = if ($script:NewsSavedMode) { "Keine gemerkten Meldungen (S merkt die markierte Meldung)." }
               elseif (@(Get-EnabledNewsIds).Count -eq 0) { "Keine Quelle eingeschaltet - Quellen > Feeds verwalten." }
               elseif (@($script:NewsItems).Count -eq 0 -and ($script:NewsLoading -or $script:NewsLoadedAt -eq [DateTime]::MinValue)) { "Nachrichten werden geladen ..." }
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
    Update-NewsPreview
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
    $choices = @(Get-NewsSourceChoices)
    $hidden = @($choices | Where-Object { @($script:Config.NewsViewHidden) -contains $_.Id }).Count
    $feeds = @($choices | Where-Object { $_.Id -ne "yahoo" }).Count
    $src = @()
    if ([bool]$script:Config.NewsYahoo) { $src += "Yahoo Finance" }
    if ($feeds -gt 0) { $src += "{0} {1}" -f $feeds, $(if ($feeds -eq 1) { "Feed" } else { "Feeds" }) }
    $parts += ((Tr "Quellen:") + " " + $(if ($src.Count -gt 0) { $src -join " + " } else { Tr "keine" }) + $(if ($hidden -gt 0) { " ({0} {1})" -f $hidden, (Tr "ausgeblendet") } else { "" }))
    $failed = @($choices | Where-Object { $null -ne $script:FeedStatus[$_.Id] -and $script:FeedStatus[$_.Id].Error })
    if ($failed.Count -gt 0) {
        # failures first, so that the narrow label does not cut them off
        $names = @($failed | Select-Object -First 3 | ForEach-Object { $_.Label }) -join ", "
        $parts = @((Tr "Fehler:") + " " + $names + $(if ($failed.Count -gt 3) { " +" + ($failed.Count - 3) } else { "" })) + $parts
    }
    $lblNewsInfo.ForeColor = if ($failed.Count -gt 0) { $script:Pal.Warn } else { $script:Pal.Muted }
    Set-DynTip $lblNewsInfo (($choices | ForEach-Object { "{0}: {1}" -f $_.Label, (Get-FeedStatusText $_.Id) }) -join "`r`n")
    $lblNewsInfo.Text = $parts -join "  |  "
}

$cmbNewsFilter.Add_SelectionChangeCommitted({
    if ($script:NewsFilterUpdating) { return }
    $i = $cmbNewsFilter.SelectedIndex
    if ($i -lt 0 -or $i -ge $script:NewsFilterKeys.Count) { return }
    Set-NewsFilter $script:NewsFilterKeys[$i]
})
$btnNewsRead.Add_Click({
    $script:NewsUnread.Clear()
    $script:NewsRead.Clear()
    Set-NewsSeen (Get-NewsNewest)
    $script:NewsBoldSince = $script:NewsSeenAt
    Save-NewsState
    Update-NewsViews
})
$btnNewsRefresh.Add_Click({
    # asks every source now, also feeds that would answer "not modified"
    $script:WorkerShared.Cond.Clear()
    Start-NewsLoad -Force
})
$dgvNews.Add_CellDoubleClick({
    param($sender, $e)
    if ($e.RowIndex -lt 0) { return }
    $n = $sender.Rows[$e.RowIndex].Tag
    Open-NewsItem $n
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
[void]$newsMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miNewsSave = $newsMenu.Items.Add("Merken (S)")
$miNewsRead = $newsMenu.Items.Add("Als gelesen markieren (M)")
$miNewsPrev = $newsMenu.Items.Add("Vorschau anzeigen (V)")
$miNewsCsv = $newsMenu.Items.Add("Gemerkte als CSV speichern ...")
$miNewsSave.Add_Click({ Switch-NewsSaved $script:NewsMenuItem })
$miNewsRead.Add_Click({ $n = $script:NewsMenuItem; if ($null -ne $n) { Set-NewsReadMark -Item $n -Read ([bool](Test-NewsUnread -Item $n -Since $script:NewsBoldSince -ReadKeys $script:NewsRead -UnreadKeys $script:NewsUnread)) } })
$miNewsPrev.Add_Click({ Set-NewsPreview (-not [bool]$script:Config.NewsPreview) })
$miNewsCsv.Add_Click({ Export-SavedNews })
$miNewsOpen.Add_Click({ Open-NewsItem $script:NewsMenuItem })
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
    $miNewsSave.Text = if (Test-NewsSaved $n) { Tr "Nicht mehr merken (S)" } else { Tr "Merken (S)" }
    $miNewsRead.Text = if (Test-NewsUnread -Item $n -Since $script:NewsBoldSince -ReadKeys $script:NewsRead -UnreadKeys $script:NewsUnread) { Tr "Als gelesen markieren (M)" } else { Tr "Als ungelesen markieren (M)" }
    $miNewsPrev.Text = if ([bool]$script:Config.NewsPreview) { Tr "Vorschau ausblenden (V)" } else { Tr "Vorschau anzeigen (V)" }
    $miNewsCsv.Enabled = (@($script:NewsSaved).Count -gt 0)
    $miNewsMute.Enabled = [bool]$n.Publisher
    $miNewsMute.Text = if ($n.Publisher) { "{0}: {1}" -f (Tr "Quelle ausblenden"), [string]$n.Publisher } else { Tr "Quelle ausblenden" }
    $newsMenu.Show($sender, $sender.PointToClient([System.Windows.Forms.Cursor]::Position))
})

$dgvNews.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $sender.SelectedRows.Count -gt 0) {
        $n = $sender.SelectedRows[0].Tag
        Open-NewsItem $n
        $e.Handled = $true
    }
})
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

function Set-CueText {
    # v7.3: Windows placeholder text (EM_SETCUEBANNER); without it the box just stays empty
    param([System.Windows.Forms.TextBox]$Box, [string]$Text)
    try {
        $Box.Tag = Tr $Text
        $apply = { param($sender, $e) [void][Win32WidgetHelperV26]::SendCue($sender.Handle, 0x1501, [IntPtr]1, [string]$sender.Tag) }
        $Box.Add_HandleCreated($apply)
        if ($Box.IsHandleCreated) { & $apply $Box $null }
    } catch { Write-WidgetLog "Placeholder text not available: $($_.Exception.Message)" "WARN" }
}

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
$txtAlertNote.Size = New-Object System.Drawing.Size((S 66), (S 24))
$txtAlertNote.BackColor = $script:Pal.Input
$txtAlertNote.ForeColor = $script:Pal.Text
$txtAlertNote.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtAlertNote.Font = $fontMono
$txtAlertNote.MaxLength = 60
$viewWatch.Controls.Add($txtAlertNote)
Set-Tip $txtAlertNote "Notiz zum Alarm (optional, erscheint im Hinweis)"

# v7.3: grey hint text inside the empty alarm inputs
Set-CueText $txtAlertTicker "Ticker"
Set-CueText $txtAlertPrice "Wert"
Set-CueText $txtAlertNote "Notiz"

# v4.3: expiry
$cmbAlertExp = New-Object System.Windows.Forms.ComboBox
$cmbAlertExp.Location = New-Object System.Drawing.Point((S 566), (S 66))
$cmbAlertExp.Size = New-Object System.Drawing.Size((S 96), (S 24))
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
$btnPortSim.Anchor  = $aT -bor $aL
Update-PortSimLayout

# v7.5: details for the selected ticker, shown when the watchlist is very wide
$btnWlDetail = New-Object System.Windows.Forms.Button
$btnWlDetail.Location = New-Object System.Drawing.Point((S 496), (S 35))
$btnWlDetail.Size = New-Object System.Drawing.Size((S 90), (S 25))
Style-FlatButton -Btn $btnWlDetail -BgColor $script:Pal.Input -FgColor $script:Pal.Text -BorderColor $script:Pal.Border
$btnWlDetail.Font = $fontUi
$btnWlDetail.Text = "Details"
$btnWlDetail.Visible = $false
$viewWatch.Controls.Add($btnWlDetail)
Set-Tip $btnWlDetail "Details zum markierten Ticker ein- oder ausblenden (nur bei breiter Watchlist)"
$lblWlDetail = New-Object System.Windows.Forms.Label
$lblWlDetail.Font = $fontMono
$lblWlDetail.ForeColor = $script:Pal.Text
$lblWlDetail.BackColor = $script:Pal.Input
$lblWlDetail.Padding = New-Object System.Windows.Forms.Padding((S 6))
$lblWlDetail.UseMnemonic = $false
$lblWlDetail.Visible = $false
$viewWatch.Controls.Add($lblWlDetail)

# v7.5: alarm column controls with their design position; per row one control stretches
$script:AlarmCol = @()
foreach ($def in @(
    @($lblAlTitle, "stretch"), @($btnAlertLog, "move"),
    @($txtAlertTicker, "keep"), @($cmbAlertCond, "stretch"), @($txtAlertPrice, "move"), @($btnAddAlert, "move"), @($btnDelAlert, "move"),
    @($txtAlertNote, "stretch"), @($cmbAlertExp, "move"), @($cmbAlertRearm, "move"), @($lstAlerts, "stretch"))) {
    $script:AlarmCol += [PSCustomObject]@{ C = $def[0]; Mode = $def[1]; Off = ($def[0].Left - (S 496)); W = $def[0].Width }
}

function Update-WatchLayout {
    # v7.5: the alarm column grows with the window (252 to 420 px); very wide views get a detail panel
    $vw = $viewWatch.ClientSize.Width
    if ($vw -lt (S 700)) { return }
    $w = Get-WatchPanelWidths -ViewW ([int][math]::Floor($vw / $script:DpiScale)) -WantDetail ([bool]$script:Config.WatchDetail)
    $alarmW = S $w.Alarm
    $detailW = if ($w.Detail -gt 0) { S $w.Detail } else { 0 }
    $colX = $vw - (S 8) - $alarmW
    $gridW = $colX - (S 16) - $(if ($detailW -gt 0) { $detailW + (S 8) } else { 0 })
    $extra = $alarmW - (S 252)
    foreach ($a in $script:AlarmCol) {
        $x = $colX + $a.Off + $(if ($a.Mode -eq "move") { $extra } else { 0 })
        $cw = $a.W + $(if ($a.Mode -eq "stretch") { $extra } else { 0 })
        $a.C.Left = $x
        $a.C.Width = $cw
    }
    $dgvWatchlist.Width = $gridW
    $script:PnlWlChips.Width = $gridW
    $btnWlDetail.Visible = [bool]$w.CanDetail
    if ($detailW -gt 0) { $lblWlDetail.SetBounds(($colX - (S 8) - $detailW), $dgvWatchlist.Top, $detailW, $dgvWatchlist.Height) }
    $lblWlDetail.Visible = ($detailW -gt 0)
    if ($detailW -gt 0) { Update-WatchDetail }
}
$btnWlDetail.Add_Click({
    $script:Config.WatchDetail = -not [bool]$script:Config.WatchDetail
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-WatchLayout
})
$viewWatch.Add_Resize({ Update-WatchLayout })
$dgvWatchlist.Add_SelectionChanged({ if (-not $script:SuppressGridSelection -and $lblWlDetail.Visible) { Update-WatchDetail } })

# Watchlist view: list grows, alarm column on the right (width: Update-WatchLayout)
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
    # v5.5 Fresh: tabs as soft pills, the active one with an accent underline
    if ($null -ne $script:UiSpec -and [bool]$script:UiSpec.Fresh) {
        foreach ($k in $tabButtons.Keys) {
            $b = $tabButtons[$k]
            if ([bool]$script:ViewOn[$k]) {
                $pill = Get-BlendColor -A $p.Accent -B $p.BodyBg -T 0.20
                Style-FlatButton -Btn $b -BgColor $pill -FgColor $p.Accent -BorderColor $pill
            } else {
                Style-FlatButton -Btn $b -BgColor $p.BodyBg -FgColor $p.Muted -BorderColor $p.BodyBg
            }
            $b.FlatAppearance.BorderSize = 0
            $b.FlatAppearance.MouseOverBackColor = Get-BlendColor -A $p.Accent -B $p.BodyBg -T 0.12
            $b.Invalidate()
        }
        return
    }
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

