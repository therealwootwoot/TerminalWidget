# TerminalWidget UI part 04 (ChartRender) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

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
        $rb = New-Object System.Drawing.Pen($script:Pal.Mark, [float]1.5)
        $rb.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        $oy = [int]$L.OffsetY
        if ($script:DrawMode -eq "R") {
            # v5.5: zone
            $g.DrawRectangle($rb, [float][math]::Min($pxT.X1, $pxT.X2), [float]([math]::Min($pxT.Y1, $pxT.Y2) + $oy), [float][math]::Abs($pxT.X2 - $pxT.X1), [float][math]::Abs($pxT.Y2 - $pxT.Y1))
        } else {
            $g.DrawLine($rb, [float]$pxT.X1, [float]($pxT.Y1 + $oy), [float]$pxT.X2, [float]($pxT.Y2 + $oy))
        }
        $rb.Dispose()
    }
    # v5.5: Ctrl + drag = zoom into the marked range
    $zd = $script:ZoomDrag
    if ($null -ne $zd -and $zd.Key -eq $script:ActiveSeriesKey -and $n -ge 2) {
        $za = [math]::Max(0, [math]::Min($n - 1, [int]$zd.A - [int]$L.ViewStart))
        $zb = [math]::Max(0, [math]::Min($n - 1, [int]$zd.B - [int]$L.ViewStart))
        $zx1 = [math]::Min([double]$L.Pts[$za].X, [double]$L.Pts[$zb].X); $zx2 = [math]::Max([double]$L.Pts[$za].X, [double]$L.Pts[$zb].X)
        $ac0 = $script:Pal.Accent
        $zbr = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(40, $ac0.R, $ac0.G, $ac0.B))
        $g.FillRectangle($zbr, [float]$zx1, [float]($pr.Top + [int]$L.OffsetY), [float][math]::Max(1, $zx2 - $zx1), [float]$pr.Height)
        $zbr.Dispose()
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
        $rp = if ($null -ne $L.RsiPlot) { $L.RsiPlot } else { $rr }
        $rVal = [math]::Max(0.0, [math]::Min(100.0, (($rp.Bottom - $my) / [double]$rp.Height) * 100.0))
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
        [bool]$cfg.ShowNewsMarkers, $(if ([bool]$cfg.ShowNewsMarkers) { [string]$script:NewsVersion } else { "" }),
        [bool]$cfg.ShowTrades, $script:Transactions.Count, [string]$cfg.ChartType, $script:DrawingsSig,
        [bool]$cfg.PctAxis, [bool]$cfg.ShowSR, $(if ([bool]$cfg.ShowSR -and $null -ne $script:DailyCache[([string]$cfg.ActiveTicker).ToUpper()]) { [string]$script:DailyCache[([string]$cfg.ActiveTicker).ToUpper()].Day } else { "" })
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
    "Nachkauf-Rechner" = "Top-up calculator"
    "Datei" = "File"; "Ansicht" = "View"; "Hilfe" = "Help"; "Jetzt aktualisieren" = "Refresh now"
    "Daten exportieren (Zip) ..." = "Export data (zip) ..."; "Backup wiederherstellen ..." = "Restore backup ..."; "Einstellungen exportieren ..." = "Export settings ..."; "Einstellungen importieren ..." = "Import settings ..."
    "In den Infobereich ausblenden" = "Hide to tray"; "Watchlist && Alarme" = "Watchlist && alerts"; "Nächstes Theme" = "Next theme"
    "Privat-Modus (Beträge ausblenden)" = "Privacy mode (hide amounts)"; "Transaktion buchen ..." = "Book transaction ..."; "Transaktionshistorie ..." = "Transaction history ..."
    "Bargeld ..." = "Cash ..."; "Sparpläne ..." = "Savings plans ..."; "Analyse ..." = "Analysis ..."; "Jahresreport ..." = "Annual report ..."; "Befehlszeile ..." = "Command line ..."; "Kalender ..." = "Calendar ..."
    "Gewinner / Verlierer ..." = "Gainers / losers ..."; "Ticker vergleichen ..." = "Compare ticker ..."; "Alarm-Verlauf ..." = "Alert history ..."
    "Tastenkürzel ..." = "Keyboard shortcuts ..."; "Glossar ..." = "Glossary ..."; "Einführung ..." = "Welcome tour ..."; "Systemzustand (HEALTH) ..." = "Health report ..."; "Diagnose exportieren ..." = "Export diagnostics ..."; "Über ..." = "About ..."
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
    "Nachrichten - Depot und Watchlist" = "News - depot and watchlist"; "Alle gelesen" = "Mark all read"; "Ticker" = "Ticker"; "Alle" = "All"; "Nachrichten werden geladen ..." = "Loading news ..."; "Keine Nachrichten für diesen Filter." = "No news for this filter."; "Keine Verbindung - Nachrichten kommen beim nächsten Versuch." = "No connection - news follow on the next try."; "Keine Nachrichten der letzten 14 Tage." = "No news in the last 14 days."; "lädt ..." = "loading ..."; "Meldungen" = "items"; "Stand" = "as of"; "letzter Versuch ohne Verbindung" = "last try had no connection"; "Quelle: Yahoo Finance, Doppelklick öffnet den Artikel" = "Source: Yahoo Finance, double-click opens the article"; "Doppelklick öffnet den Artikel im Browser" = "Double-click opens the article in the browser"; "Aktiver Ticker:" = "Active ticker:"; "Schrift und Rahmen" = "Font and frame"; "Schrift für Zahlen (ab Neustart)" = "Font for numbers (after restart)"; "Schriftgröße Listen + Chart (ab Neustart)" = "List + chart font size (after restart)"; "Zahlen rechtsbündig (Watchlist, Portfolio)" = "Numbers right-aligned (watchlist, portfolio)"; "Abgerundete Fensterecken (Windows 11)" = "Rounded window corners (Windows 11)"; "Nachrichten (F4)" = "News (F4)"; "Neu laden alle (Minuten)" = "Reload every (minutes)"; "Ticker markieren ab Tagesbewegung (%)" = "Mark tickers moving today from (%)"; "Schrift und Schriftgröße wirken nach einem Neustart. Jetzt neu starten?" = "Font and font size apply after a restart. Restart now?"; "Schrift" = "Font"
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

# v5.3: settings pages, quick access, settings file
foreach ($kv in @{
    "Schrift" = "Font"; "Chart-Indikatoren" = "Chart indicators"; "Farben" = "Colours"; "Listen und Fenster" = "Lists and window"
    "Terminal-Layout" = "Terminal layout"; "Compact- und Ticker-Leiste" = "Compact and ticker bar"; "Fenster" = "Window"; "System" = "System"
    "Auch ohne dieses Fenster: Befehl STYLE, Layout-Menü (oben rechts) und Tray-Menü." = "Also without this window: STYLE command, layout menu (top right) and tray menu."
    "Datenquelle: Yahoo Finance. Weitere Quellen (Twelve Data, Finnhub) folgen mit V6." = "Data source: Yahoo Finance. More sources (Twelve Data, Finnhub) follow with V6."
    "Hinweise" = "Notifications"; "Handy-Push" = "Phone push"; "Nachrichten mit Alarm-Wörtern" = "News with alert words"
    "Währung und Kennzahlen" = "Currency and figures"; "Währung (Auto = Währung des Tickers)" = "Currency (Auto = the ticker's currency)"
    "Risikofreier Zins für die Sharpe Ratio (%)" = "Risk-free rate for the Sharpe ratio (%)"; "Werkzeuge (speichert und öffnet)" = "Tools (saves and opens)"
    "Cash-Konto ..." = "Cash account ..."; "Sparpläne ..." = "Savings plans ..."; "Broker-CSV importieren ..." = "Import broker CSV ..."; "Zielgewichte ..." = "Target weights ..."
    "Globales Tastenkürzel" = "Global hotkey"; "Befehlszeile" = "Command line"
    "Strg+K öffnet die Befehlszeile. Sie findet Befehle, Ticker, Menüeinträge und jede Einstellung - z. B. 'zebra', 'push' oder 'SET STIL'." = "Ctrl+K opens the command line. It finds commands, tickers, menu entries and every setting - e.g. 'zebra', 'push' or 'SET STYLE'."
    "Alle Tastenkürzel und Befehle (HELP)" = "All shortcuts and commands (HELP)"; "Einstellungen übertragen" = "Move settings"
    "Einstellungen exportieren ..." = "Export settings ..."; "Einstellungen importieren ..." = "Import settings ..."; "Einstellungen exportieren" = "Export settings"; "Einstellungen importieren" = "Import settings"
    "Daten und Sicherung" = "Data and backup"; "Seite zurücksetzen" = "Reset page"; "wie gewohnt, feiner" = "familiar, cleaner"; "Karten, mehr Luft" = "cards, more space"
    "Einstellung" = "Setting"; "Einstellungen - Seite" = "Settings - page"; "Menü" = "Menu"; "Einstellungen ..." = "Settings ..."
    "Stil: Refined" = "Style: Refined"; "Stil: Fresh" = "Style: Fresh"; "Compact / Ticker zeigt ..." = "Compact / ticker shows ..."; "Theme" = "Theme"
    "Menüeintrag ausführen (MENU <Name>)" = "Run a menu entry (MENU <name>)"; "Einstellungen (SET <Suchwort> springt zur Einstellung)" = "Settings (SET <word> jumps to the setting)"
}.GetEnumerator()) { $script:EnText[$kv.Key] = $kv.Value }
# v5.5
foreach ($kv in @{
    "Fehlersuche" = "Troubleshooting"; "Zustand prüfen (HEALTH)" = "Check health (HEALTH)"; "Diagnose exportieren ..." = "Export diagnostics ..."; "Zustand" = "Health"
    "OK = in Ordnung, !! = Warnung, XX = Fehler. DIAG exportiert eine Diagnose für Fehlerberichte." = "OK = fine, !! = warning, XX = error. DIAG exports diagnostics for bug reports."
    "Notiz ..." = "Note ..."; "Löschen" = "Delete"; "These, Kaufgrund, Ziele - nur für dich" = "Thesis, reason for buying, goals - just for you"
    "HTML-Bericht speichern ..." = "Save HTML report ..."; "CSV für Excel speichern ..." = "Save CSV for Excel ..."; "Als Bild kopieren" = "Copy as image"; "Als Bild speichern ..." = "Save as image ..."
    "Portfolio-Analyse" = "Portfolio analysis"; "keine Anlageberatung" = "not investment advice"; "Privat-Modus: Beträge ausgeblendet" = "Privacy mode: amounts hidden"
    "Chart als Bild kopieren" = "Copy chart as image"; "Chart als Bild speichern ..." = "Save chart as image ..."; "Ganzes Fenster als Bild kopieren" = "Copy whole window as image"
    "Prozent-Achse (ab Beginn des Ausschnitts)" = "Percent axis (from the start of the view)"; "Unterstützung / Widerstand (Tageskurse)" = "Support / resistance (daily)"
    "Zone (Rechteck)" = "Zone (rectangle)"; "Textnotiz" = "Text note"; "Textnotiz im Chart" = "Text note in the chart"; "Unterstützung" = "Support"; "Widerstand" = "Resistance"
    "Einkommen" = "Income"; "Jahr" = "Year"; "Summe Dividende" = "Dividend total"; "zum Vorjahr" = "vs. prior year"; "Szenario:" = "Scenario:"; "Markt (Beta)" = "Market (beta)"
    "Betroffen" = "Affected"; "Beta aus" = "Beta from"; "seit Beginn" = "since start"; "pro Monat" = "per month"; "Dividenden" = "Dividends"
    "Noch keine Dividenden gebucht (Transaktion 'Dividende' oder Broker-CSV-Import)." = "No dividends booked yet (transaction 'Dividend' or broker CSV import)."
    "nur Positionen dieses Sektors, ohne Cash" = "only positions of this sector, without cash"; "nur Positionen in dieser Währung (Kursänderung in der Basiswährung), ohne Cash" = "only positions in this currency (change in the base currency), without cash"
    "Dynamik %" = "Increase %"; "Pause" = "Pause"; "Jetzt" = "Now"; "Signal" = "Signal"
}.GetEnumerator()) { $script:EnText[$kv.Key] = $kv.Value }
# v5.7
foreach ($kv in @{
    "Wert (Tag)" = "Value (day)"; "Woche" = "Week"; "Tag" = "Day"; "Tageskurse" = "Daily prices"; "Wochenkurse" = "Weekly prices"
    "Vergleichsgruppe ..." = "Peer group ..."; "eigene Gruppe" = "own group"; "Vergleich = Median deiner Vergleichsgruppe (PEER)" = "Comparison = median of your peer group (PEER)"; "lädt noch" = "still loading"
    "Bewertung vs. eigene Historie" = "Valuation vs. own history"; "Median" = "Median"; "seit" = "since"; "Tage" = "days"; "ab 20 Tagen Daten" = "from 20 days of data"; "bisher" = "so far"; "Rang" = "rank"
    "teuer gegenüber der eigenen Historie" = "expensive vs. own history"; "günstig gegenüber der eigenen Historie" = "cheap vs. own history"; "im üblichen Bereich" = "in the usual range"
    "Rendite hoch gegenüber der eigenen Historie (eher günstig)" = "yield high vs. own history (rather cheap)"; "Rendite niedrig gegenüber der eigenen Historie (eher teuer)" = "yield low vs. own history (rather expensive)"
    "Tages- und Wochensignale sind positiv: Aufwärtstrend auf beiden Zeitebenen." = "Daily and weekly signals are positive: uptrend on both time frames."
    "Tages- und Wochensignale sind negativ: Abwärtstrend auf beiden Zeitebenen." = "Daily and weekly signals are negative: downtrend on both time frames."
    "Kurzfristig positiv, mittelfristig negativ: eher eine Erholung im längeren Abwärtstrend." = "Positive short term, negative medium term: more likely a bounce in a longer downtrend."
    "Kurzfristig negativ, mittelfristig positiv: eher ein Rücksetzer im längeren Aufwärtstrend." = "Negative short term, positive medium term: more likely a pullback in a longer uptrend."
    "Kurzfristig positiv, mittelfristig gemischt: der Aufwärtsimpuls ist auf Wochensicht noch nicht bestätigt." = "Positive short term, mixed medium term: the upswing is not confirmed on the weekly chart yet."
    "Kurzfristig negativ, mittelfristig gemischt: Schwäche, aber auf Wochensicht noch kein klarer Abwärtstrend." = "Negative short term, mixed medium term: weakness, but no clear weekly downtrend yet."
    "Kurzfristig gemischt, mittelfristig positiv: der längere Aufwärtstrend ist intakt, kurzfristig ohne Richtung." = "Mixed short term, positive medium term: the longer uptrend is intact, no short-term direction."
    "Kurzfristig gemischt, mittelfristig negativ: der längere Abwärtstrend ist nicht gebrochen." = "Mixed short term, negative medium term: the longer downtrend is not broken."
    "Kein klares Bild auf beiden Zeitebenen." = "No clear picture on either time frame."; "Zu wenig Wochendaten für die mittelfristige Sicht." = "Not enough weekly data for the medium-term view."
    "Signal-Wechsel (Ticker-Analyse)" = "Signal changes (ticker analysis)"; "Hinweis bei Signal-Wechsel" = "Notify on signal change"; "Depot + Watchlist" = "Depot + watchlist"; "Aus" = "Off"
    "Eigene RSS-Feeds (eine Adresse je Zeile)" = "Own RSS feeds (one address per line)"; "Ticker-Analyse: Rechtsklick > TA" = "Ticker analysis: right-click > TA"
}.GetEnumerator()) { $script:EnText[$kv.Key] = $kv.Value }
# V6
foreach ($kv in @{
    "Weitere Datenquellen (eigene API-Schlüssel)" = "More data sources (own API keys)"; "Twelve Data API-Schlüssel" = "Twelve Data API key"; "Finnhub API-Schlüssel" = "Finnhub API key"
    "Datenquellen testen (PROV)" = "Test data sources (PROV)"; "Datenquellen" = "Data sources"; "kein Schlüssel" = "no key"; "nutzbar" = "usable"; "nicht" = "not"; "Anfragen heute" = "requests today"
    "noch nicht getestet (PROV)" = "not tested yet (PROV)"; "kein Zugriff (kostenpflichtig oder Schlüssel falsch)" = "no access (paid plan or wrong key)"; "leer" = "empty"
    "Noch kein API-Schlüssel eingetragen (Einstellungen > Daten & Aktualisierung)." = "No API key yet (Settings > Data & refresh)."
    "Kennzahlen über die Jahre" = "Figures over the years"; "Bewertung vs. Historie (Quartale)" = "Valuation vs. history (quarters)"; "Quartale" = "quarters"
    "Quartalszahlen: Gewinn je Aktie" = "Earnings: EPS"; "Ist vs. Erwartung, Kursreaktion" = "actual vs. estimate, price reaction"; "Überraschung" = "Surprise"; "Kurs" = "Price"
    "Analysten (Trend)" = "Analysts (trend)"; "Empfehlungen jetzt" = "Recommendations now"; "vor 3 Monaten" = "3 months ago"; "positiver" = "more positive"; "negativer" = "more negative"; "unverändert" = "unchanged"
    "Kursziel (Mittel)" = "Price target (mean)"; "Mehr mit Finnhub" = "More with Finnhub"
    "Kostenloser Schlüssel in Einstellungen > Daten: Kennzahlen über Jahre, Quartalszahlen, Analysten-Trend" = "Free key in Settings > Data: figures over the years, earnings, analyst trend"
    "Gewinn je Aktie" = "EPS"; "Kauf" = "Buy"; "Halten" = "Hold"; "Verkauf" = "Sell"
}.GetEnumerator()) { $script:EnText[$kv.Key] = $kv.Value }

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
    # v5.7: screen readers - icon buttons get the first part of their tooltip as name
    if ($Ctl -is [System.Windows.Forms.ButtonBase] -and -not $Ctl.AccessibleName -and $Text) { $Ctl.AccessibleName = (($Text -split '[\.\(\r\n]')[0]).Trim() }
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

# V7.0: the window moved to a monitor with another scaling -> rebuild by restarting
# (all sizes are computed once at start from the monitor's DPI)
try {
    $form.Add_DpiChanged({
        param($sender, $e)
        try {
            if (-not [bool]$script:Config.PerMonitorDpi -or $script:DpiRestartPending) { return }
            $newScale = [math]::Max(1.0, ([double]$e.DeviceDpiNew / 96.0))
            if ([math]::Abs($newScale - [double]$script:DpiScale) -lt 0.01) { return }
            $script:DpiRestartPending = $true
            Write-WidgetLog ("DPI changed ({0} -> {1}): restarting" -f $script:DpiScale, $newScale)
            Show-Toast -Text "Bildschirm-Skalierung geändert - Widget startet neu" -Seconds 3
            $t = New-Object System.Windows.Forms.Timer
            $t.Interval = 1200
            $t.Add_Tick({ $this.Stop(); Restart-Widget -KeepData })
            $t.Start()
        } catch { }
    })
} catch { }

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
# V7.0: hover fade (colour mix over ~120 ms); off with "Animationen" or when Windows animations are off
$script:BtnFade = @{}
$script:BtnFadeTarget = @{}
function Test-MotionOn {
    try { return ([bool]$script:Config.Animations -and [System.Windows.Forms.SystemInformation]::UIEffectsEnabled) } catch { return $false }
}
# V7.1: the big header price rolls from the old to the new value (150 ms, only when motion is on and the move is small)
$script:PriceRoll = $null
$script:PriceRollLast = @{ Key = ""; Value = [double]::NaN }
$script:PriceRollTimer = New-Object System.Windows.Forms.Timer
$script:PriceRollTimer.Interval = 25
$script:PriceRollTimer.Add_Tick({
    $r = $script:PriceRoll
    if ($null -eq $r) { $script:PriceRollTimer.Stop(); return }
    if ($r.Step -ge @($r.Values).Count) { $script:PriceRollTimer.Stop(); $script:PriceRoll = $null; return }
    $lblLivePrice.Text = "{0:N2} {1}" -f [double]$r.Values[$r.Step], $r.Curr
    $r.Step++
    if ($r.Step -ge @($r.Values).Count) { $script:PriceRollTimer.Stop(); $script:PriceRoll = $null }
})
function Set-LivePriceText {
    param([string]$Key, [double]$Price, [string]$Curr)
    $from = [double]$script:PriceRollLast.Value
    $same = ([string]$script:PriceRollLast.Key -eq $Key)
    $script:PriceRollLast = @{ Key = $Key; Value = $Price }
    $script:PriceRollTimer.Stop(); $script:PriceRoll = $null
    $final = "{0:N2} {1}" -f $Price, $Curr
    if (-not $same -or [double]::IsNaN($from) -or $from -eq $Price -or [math]::Abs($Price - $from) -gt ([math]::Abs($from) * 0.2) -or -not (Test-MotionOn)) { $lblLivePrice.Text = $final; return }
    $script:PriceRoll = @{ Values = @(Get-RollValues -From $from -To $Price -Steps 5); Step = 0; Curr = $Curr }
    $script:PriceRollTimer.Start()
}
$script:BtnFadeTimer = New-Object System.Windows.Forms.Timer
$script:BtnFadeTimer.Interval = 20
$script:BtnFadeTimer.Add_Tick({
    $done = $true
    foreach ($b in @($script:BtnFadeTarget.Keys)) {
        $cur = [double]$script:BtnFade[$b]
        $tg = [double]$script:BtnFadeTarget[$b]
        if ($cur -lt $tg) { $cur = [math]::Min($tg, $cur + 0.2) } elseif ($cur -gt $tg) { $cur = [math]::Max($tg, $cur - 0.2) }
        $script:BtnFade[$b] = $cur
        try { $b.Invalidate() } catch { }
        if ($cur -eq $tg -and $tg -eq 0.0) { $script:BtnFade.Remove($b); $script:BtnFadeTarget.Remove($b) }
        elseif ($cur -ne $tg) { $done = $false }
    }
    if ($done) { $script:BtnFadeTimer.Stop() }
})
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
                elseif ([object]::ReferenceEquals($script:PressBtn, $sender)) { $script:Pal.AccentSubtle }
                elseif ($script:BtnFade.ContainsKey($sender) -and [double]$script:BtnFade[$sender] -gt 0) { Get-MixColor -A $sender.FlatAppearance.MouseOverBackColor -B $sender.BackColor -T ([double]$script:BtnFade[$sender]) }
                else { $sender.BackColor }
        $br = New-Object System.Drawing.SolidBrush($fill)
        $pn = $null
        if ($sender.FlatAppearance.BorderSize -gt 0) { $pn = New-Object System.Drawing.Pen($sender.FlatAppearance.BorderColor, 1) }
        Fill-RoundedRect -g $g -Brush $br -Rect (New-Object System.Drawing.RectangleF(0.5, 0.5, ($w - 1.5), ($h - 1.5))) -Radius ([float](S $spec.BtnRadius)) -Pen $pn
        $br.Dispose(); if ($null -ne $pn) { $pn.Dispose() }
        # V7.0: focus ring (keyboard focus only): 2 px accent line, one style in every theme
        # v7.5: ShowFocusCues is protected (always empty in PowerShell): skip the ring for mouse clicks instead
        if ($sender.Focused -and -not [object]::ReferenceEquals($script:MouseBtn, $sender)) {
            $fpen = New-Object System.Drawing.Pen($script:Pal.Accent, 2)
            Fill-RoundedRect -g $g -Brush ([System.Drawing.Brushes]::Transparent) -Rect (New-Object System.Drawing.RectangleF(1, 1, ($w - 3), ($h - 3))) -Radius ([float](S $spec.BtnRadius)) -Pen $fpen
            $fpen.Dispose()
        }
        $fg = if ($sender.Enabled) { $sender.ForeColor } else { $script:Pal.Disabled }
        $tf = [System.Windows.Forms.TextFormatFlags]
        # icon buttons (one glyph) get no padding and no ellipsis
        $short = ([string]$sender.Text).Length -le 2
        $flags = $tf::VerticalCenter -bor $tf::SingleLine -bor $tf::NoPrefix
        if (-not $short) { $flags = $flags -bor $tf::EndEllipsis }
        $ta = [string]$sender.TextAlign
        $flags = $flags -bor $(if ($ta -like "*Left") { $tf::Left } elseif ($ta -like "*Right") { $tf::Right } else { $tf::HorizontalCenter })
        $pad = if ($short) { 0 } else { S 4 }
        $tr = New-Object System.Drawing.Rectangle($pad, 0, [math]::Max(1, $w - 2 * $pad), $h)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $sender.Text, $sender.Font, $tr, $fg, $flags)
    } catch { }
}
$script:RoundBtnEnter = {
    param($sender, $e)
    $script:HotBtn = $sender
    $script:BtnFadeTarget[$sender] = 1.0
    if (Test-MotionOn) { if (-not $script:BtnFade.ContainsKey($sender)) { $script:BtnFade[$sender] = 0.0 }; $script:BtnFadeTimer.Start() } else { $script:BtnFade[$sender] = 1.0 }
    $sender.Invalidate()
}
$script:RoundBtnLeave = { param($sender, $e) if ([object]::ReferenceEquals($script:HotBtn, $sender)) { $script:HotBtn = $null }; if ([object]::ReferenceEquals($script:PressBtn, $sender)) { $script:PressBtn = $null }; if ($script:BtnFade.ContainsKey($sender)) { $script:BtnFadeTarget[$sender] = 0.0; if (Test-MotionOn) { $script:BtnFadeTimer.Start() } else { $script:BtnFade.Remove($sender); $script:BtnFadeTarget.Remove($sender) } }; $sender.Invalidate() }
# V7.0: pressed state and focus ring need a repaint
$script:MouseBtn = $null
$script:RoundBtnDown  = { param($sender, $e) $script:PressBtn = $sender; $script:MouseBtn = $sender; $sender.Invalidate() }
$script:RoundBtnUp    = { param($sender, $e) if ([object]::ReferenceEquals($script:PressBtn, $sender)) { $script:PressBtn = $null }; $sender.Invalidate() }
$script:RoundBtnFocus = { param($sender, $e) if (-not $sender.Focused -and [object]::ReferenceEquals($script:MouseBtn, $sender)) { $script:MouseBtn = $null }; $sender.Invalidate() }

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
        $Btn.Add_MouseDown($script:RoundBtnDown)
        $Btn.Add_MouseUp($script:RoundBtnUp)
        $Btn.Add_GotFocus($script:RoundBtnFocus)
        $Btn.Add_LostFocus($script:RoundBtnFocus)
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

# v7.5.1: menu bar at the top of the full layouts; everything below starts this much lower
$script:MenuH = S 24
$form.ClientSize = New-Object System.Drawing.Size((S 780), ((S 560) + $script:MenuH))
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
# v5.3: the style is reachable without the settings window
$miStyle = New-Object System.Windows.Forms.ToolStripMenuItem("Stil")
foreach ($sn in @("Refined", "Fresh")) {
    $smi = New-Object System.Windows.Forms.ToolStripMenuItem($sn)
    $smi.Tag = $sn
    $smi.Add_Click({ param($sender, $e) [void](Invoke-TerminalCommand ("STYLE " + ([string]$sender.Tag).ToUpper())) })
    [void]$miStyle.DropDownItems.Add($smi)
}
[void]$trayMenu.Items.Add($miStyle)
$miSettings = New-Object System.Windows.Forms.ToolStripMenuItem("Einstellungen ...")
$miSettings.Add_Click({ Show-MainWindow; Show-SettingsDialog })
[void]$trayMenu.Items.Add($miSettings)
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
$pnlHeader.Location = New-Object System.Drawing.Point(0, $script:MenuH)
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
$pnlTape.Size = New-Object System.Drawing.Size((S 760), (S 22))
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
$btnCurrency.Location = New-Object System.Drawing.Point((S 536), (S 11))
$btnCurrency.Size = New-Object System.Drawing.Size((S 62), (S 26))
Style-FlatButton -Btn $btnCurrency -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Accent
$btnCurrency.Font = $fontUiBold
$btnCurrency.Text = $(if ([bool]$script:Config.AutoCurrency) { "Auto $script:DropArrow" } else { "$($script:Config.Currency) $script:DropArrow" })
$pnlHeader.Controls.Add($btnCurrency)
Set-Tip $btnCurrency "Währung (Taste W). Auto = jeder Kurs und der Chart in der Währung des Tickers (ABBN.SW in CHF, SAP.DE in EUR); Depotwerte bleiben in der Basiswährung. EUR/USD/CHF/GBP = alles in dieser Währung (wird auch Basiswährung)." "FX"

$btnPin = New-Object System.Windows.Forms.Button
$btnPin.Location = New-Object System.Drawing.Point((S 604), (S 11))
$btnPin.Size = New-Object System.Drawing.Size((S 36), (S 26))
$btnPin.Font = $fontUiBold
$btnPin.Text = "Pin"
$pnlHeader.Controls.Add($btnPin)
Set-Tip $btnPin "Immer im Vordergrund (Always on Top)" "PIN"

$btnCompact = New-Object System.Windows.Forms.Button
$btnCompact.Location = New-Object System.Drawing.Point((S 646), (S 11))
$btnCompact.Size = New-Object System.Drawing.Size((S 90), (S 26))
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
# v5.3: style right here (it used to hide deep in the settings)
[void]$layoutMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
foreach ($sn in @("Refined", "Fresh")) {
    $lmiS = New-Object System.Windows.Forms.ToolStripMenuItem(("Stil: {0}" -f $sn))
    $lmiS.Tag = "Style:$sn"
    [void]$layoutMenu.Items.Add($lmiS)
}
$lmiSet = New-Object System.Windows.Forms.ToolStripMenuItem("Einstellungen ...")
$lmiSet.Tag = "Settings"
[void]$layoutMenu.Items.Add($lmiSet)
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
$lstCurrencyDropdown.Location = New-Object System.Drawing.Point((S 544), ((S 40) + $script:MenuH))
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
$lstTickerDropdown.Location = New-Object System.Drawing.Point((S 12), ((S 40) + $script:MenuH))
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
$pnlNav.Location = New-Object System.Drawing.Point((S 12), ((S 56) + $script:MenuH))
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
    # v5.5 Fresh: accent underline under the active tab
    $b.Add_Paint({
        param($sender, $e)
        if ($null -eq $script:UiSpec -or -not [bool]$script:UiSpec.Fresh -or -not [bool]$script:ViewOn[[string]$sender.Tag]) { return }
        $ub = New-Object System.Drawing.SolidBrush($script:Pal.Accent)
        $e.Graphics.FillRectangle($ub, (S 12), ($sender.Height - (S 3)), ($sender.Width - (S 24)), (S 2))
        $ub.Dispose()
    })
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

# V7.0: status bar at the bottom (data age, market state, privacy mode)
$script:PnlStatusBar = New-Object System.Windows.Forms.Panel
$script:PnlStatusBar.Height = S 22
$script:PnlStatusBar.BackColor = $script:Pal.HeaderBg
$script:PnlStatusBar.Visible = $false
Enable-DoubleBuffering -Control $script:PnlStatusBar
$script:PnlStatusBar.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $p = $script:Pal
    $g.Clear($p.HeaderBg)
    $g.DrawLine($script:GdiCache["sepPen"], 0, 0, $sender.Width, 0)
    $age = [double]::NaN
    $stand = ""
    if ($null -ne $script:LastDataTime) { $age = ((Get-Date) - $script:LastDataTime).TotalSeconds; $stand = $script:LastDataTime.ToString("HH:mm:ss") }
    # v7.3: the market status is in the header only; here: why polling is slower, if it is
    $note = ""
    try {
        $closedMin = [int]$script:Config.ClosedPollMinutes
        $allClosed = $closedMin -gt 0 -and (Test-AllPrioClosed)
        $note = Get-PollNote -AllClosed $allClosed -ClosedMinutes $closedMin -RefreshSec ([int]$script:Config.RefreshSeconds) -BackoffUntil $script:BackoffUntil
    } catch { }
    $parts = @(Get-StatusBarParts -AgeSec $age -Stand $stand -Privacy ([bool]$script:Config.PrivacyMode) -ReqPerMin (Get-RequestsPerMinute) -PollNote $note)
    $txt = $parts -join "   |   "
    $tr = New-Object System.Drawing.Rectangle((S 12), 0, ($sender.Width - (S 24)), $sender.Height)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $txt, $fontMono, $tr, $p.Muted, ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis))
})
$form.Controls.Add($script:PnlStatusBar)
$script:StatusBarTimer = New-Object System.Windows.Forms.Timer
$script:StatusBarTimer.Interval = 1000
$script:StatusBarTimer.Add_Tick({ if ($script:PnlStatusBar.Visible) { $script:PnlStatusBar.Invalidate() } })
$script:StatusBarTimer.Start()
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
$viewChart.Location = New-Object System.Drawing.Point((S 12), ((S 92) + $script:MenuH))
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
# v5.5: pictures of the chart / the window
$cmiImgCopy = $chartContextMenu.Items.Add("Chart als Bild kopieren")
$cmiImgSave = $chartContextMenu.Items.Add("Chart als Bild speichern ...")
$cmiWinCopy = $chartContextMenu.Items.Add("Ganzes Fenster als Bild kopieren")
# v5.5: percent axis, support / resistance
$cmiPctAxis = New-Object System.Windows.Forms.ToolStripMenuItem("Prozent-Achse (ab Beginn des Ausschnitts)")
$cmiPctAxis.Add_Click({ Set-ChartOption -Key "PctAxis" -On (-not [bool]$script:Config.PctAxis) })
[void]$chartContextMenu.Items.Add($cmiPctAxis)
$cmiSR = New-Object System.Windows.Forms.ToolStripMenuItem("Unterstützung / Widerstand (Tageskurse)")
$cmiSR.Add_Click({ Set-ChartOption -Key "ShowSR" -On (-not [bool]$script:Config.ShowSR) })
[void]$chartContextMenu.Items.Add($cmiSR)
function Set-ChartOption {
    param([string]$Key, [bool]$On)
    $script:Config.$Key = $On
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    if ($Key -eq "ShowSR" -and $On) { Request-DailyBars -Symbols @(([string]$script:Config.ActiveTicker).ToUpper()) }
    Refresh-ChartView
}
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
# v7.7: news marks
$cmiNewsMarks = New-Object System.Windows.Forms.ToolStripMenuItem("News im Chart anzeigen")
$cmiNewsMarks.CheckOnClick = $true
$cmiNewsMarks.Checked = [bool]$script:Config.ShowNewsMarkers
$cmiNewsMarks.Add_Click({
    $script:Config.ShowNewsMarkers = $cmiNewsMarks.Checked
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    $script:ChartSignature = ""
    Update-AllUiViews
})
[void]$chartContextMenu.Items.Add($cmiNewsMarks)
# v5.0: drawing tools
$cmiDraw = New-Object System.Windows.Forms.ToolStripMenuItem("Zeichnen")
foreach ($dk in @(@("H", "Horizontale Linie"), @("T", "Trendlinie (D)"), @("F", "Fibonacci"), @("R", "Zone (Rechteck)"), @("N", "Textnotiz"))) {
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

function Get-ChartLegendAt {
    param($L, [int]$X, [int]$Y)
    if ($null -eq $L -or $null -eq $L.Legends) { return $null }
    $py = [float]($Y - [int]$L.OffsetY)
    foreach ($lg in @($L.Legends)) { if ($lg.R.Contains([float]$X, $py)) { return $lg } }
    return $null
}

function Test-PaneDividerHit {
    # V7.1: the gap between chart and indicator pane is a drag handle
    param($L, [int]$Y)
    if ($null -eq $L -or $null -eq $L.RsiRect -or $null -eq $L.PaneTotal) { return $false }
    $my = $Y - [int]$L.OffsetY
    return ($my -ge ([int]$L.PriceRect.Bottom - (S 2)) -and $my -le ([int]$L.RsiRect.Top + (S 2)))
}

$script:PaneDrag = $null
$script:ChartMouseMoveHandler = {
    param($sender, $e)
    # Hit-testing uses the geometry of the bitmap that is actually on screen
    $L = Get-CanvasLayout -Canvas $sender
    if ($null -eq $L) { return }
    if ($null -ne $script:PaneDrag) {
        $frac = (($e.Y - [int]$L.OffsetY) - [double]$L.PaneTop - ([double]$L.GapY / 2.0)) / [double]$L.PaneTotal
        $frac = [math]::Max(0.35, [math]::Min(0.85, $frac))
        if ([math]::Abs($frac - [double]$script:Config.PaneDivider) -gt 0.004 -and $script:PaneDrag.Sw.ElapsedMilliseconds -gt 40) {
            $script:Config.PaneDivider = [math]::Round($frac, 3)
            $script:PaneDrag.Sw.Restart()
            Refresh-ChartView
        }
        return
    }
    if (Test-PaneDividerHit -L $L -Y $e.Y) { if ($sender.Cursor -ne [System.Windows.Forms.Cursors]::SizeNS) { $sender.Cursor = [System.Windows.Forms.Cursors]::SizeNS } }
    elseif ($sender.Cursor -eq [System.Windows.Forms.Cursors]::SizeNS) { $sender.Cursor = [System.Windows.Forms.Cursors]::Default }
    if ($null -ne $script:DrawPending) { $script:DrawMouse = Get-ChartPointAt -L $L -X $e.X -Y $e.Y; $sender.Invalidate() }
    Update-ChartLegendTip -Canvas $sender -L $L -X $e.X -Y $e.Y
    $lgh = Get-ChartLegendAt -L $L -X $e.X -Y $e.Y
    $wantHand = ($null -ne $lgh -and [string]$lgh.Key -in @("BB", "SMA", "VWAP"))
    if ($wantHand -and $sender.Cursor -ne [System.Windows.Forms.Cursors]::Hand) { $sender.Cursor = [System.Windows.Forms.Cursors]::Hand }
    elseif (-not $wantHand -and $sender.Cursor -eq [System.Windows.Forms.Cursors]::Hand) { $sender.Cursor = [System.Windows.Forms.Cursors]::Default }
    $idx = Get-HoverIndexAt -L $L -X $e.X
    if ($null -ne $script:ZoomDrag -and $idx -ge 0) { $script:ZoomDrag.B = [int]$L.ViewStart + $idx; $sender.Invalidate() }
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
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and (Test-PaneDividerHit -L $L -Y $e.Y)) {
        $script:PaneDrag = @{ Sw = [System.Diagnostics.Stopwatch]::StartNew() }
        return
    }
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
        if ($script:DrawMode -eq "N") {
            # v5.5: text note at the clicked point
            Set-DrawMode ""
            $tx = Read-TextPrompt -Title "Textnotiz im Chart" -Prompt "Text (z. B. 'Kaufzone', 'Zahlen 18.2.')"
            if ($tx) { Add-Drawing -Kind "N" -A $pt -Text $tx }
            return
        }
        if ($null -eq $script:DrawPending) { $script:DrawPending = $pt; Set-TransientStatus "Jetzt den zweiten Punkt klicken (Esc = abbrechen)" 8; return }
        Add-Drawing -Kind $script:DrawMode -A $script:DrawPending -B $pt
        Set-DrawMode ""
        return
    }
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left -and ([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Control) -eq [System.Windows.Forms.Keys]::Control) {
        # v5.5: Ctrl + drag = zoom
        $idx = Get-HoverIndexAt -L $L -X $e.X
        if ($idx -ge 0) { $script:ZoomDrag = @{ A = ([int]$L.ViewStart + $idx); B = ([int]$L.ViewStart + $idx); Key = $script:ActiveSeriesKey } }
        return
    }
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        # V7.0: a click on an indicator legend (BB20, SMA / EMA, VWAP) hides that indicator
        $lgHit = Get-ChartLegendAt -L $L -X $e.X -Y $e.Y
        if ($null -ne $lgHit -and [string]$lgHit.Key -in @("BB", "SMA", "VWAP")) {
            switch ([string]$lgHit.Key) {
                "BB"   { $script:Config.ShowBollinger = $false }
                "SMA"  { $script:Config.ShowSma = $false }
                "VWAP" { $script:Config.ShowVwap = $false }
            }
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Set-TransientStatus ("{0} ausgeblendet (Knopf unter dem Chart schaltet wieder ein)" -f [string]$lgHit.Key) 3
            Update-AllUiViews
            return
        }
        $idx = Get-HoverIndexAt -L $L -X $e.X
        $script:Measure = @{ Active = $false; Dragging = ($idx -ge 0); A = ([int]$L.ViewStart + $idx); B = ([int]$L.ViewStart + $idx); X0 = $e.X; Key = $script:ActiveSeriesKey }
        $sender.Invalidate()
    }
}
$script:ChartMouseUpHandler = {
    param($sender, $e)
    if ($null -ne $script:PaneDrag) {
        $script:PaneDrag = $null
        Refresh-ChartView
        try { Save-JsonState -Path $script:ConfigPath -Data $script:Config } catch { }
        return
    }
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $script:Measure.Dragging = $false
        $zd = $script:ZoomDrag
        $script:ZoomDrag = $null
        if ($null -ne $zd -and $zd.Key -eq $script:ActiveSeriesKey) {
            $zw = Get-ZoomWindow -A ([int]$zd.A) -B ([int]$zd.B) -Total @($script:ActiveSeries).Count
            if ($null -ne $zw) {
                $script:ViewCount = [int]$zw.Count; $script:ViewOffset = [int]$zw.Offset
                $script:HoverIndex = -1
                Refresh-ChartView
                Set-TransientStatus "Zoom: Z oder Rechtsklick > Zoom zurücksetzen" 4
            }
        }
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

