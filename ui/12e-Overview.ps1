# TerminalWidget UI part 12e (Overview screen, V10.0) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM.
# One painted canvas: everything is drawn from the data that is already loaded
# (quotes, 5-day sparklines, news). Opening it sends no extra requests.

$script:Ov = $null

function Get-OverviewData {
    $base = [string]$script:Config.Currency
    $pos = @()
    foreach ($k in @($script:Portfolio.Keys)) {
        $sym = ([string]$k).ToUpper()
        $pf = $script:Portfolio[$k]
        $sh = [double]$pf.Shares
        if ($sh -le 0) { continue }
        $cost = $sh * (Convert-CurrencyValue -Amount ([double]$pf.AvgPrice) -FromCurrency ([string]$pf.Currency) -ToCurrency $base)
        $q = $script:QuoteStore[$sym]
        $live = ($null -ne $q -and [double]$q.Price -gt 0)
        $price = 0.0; $val = $cost; $day = [double]::NaN; $dayPct = [double]::NaN
        if ($live) {
            $price = Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $base
            $val = $sh * $price
            if ([double]$q.PrevClose -gt 0) {
                $day = $val - $sh * (Convert-CurrencyValue -Amount ([double]$q.PrevClose) -FromCurrency ([string]$q.Currency) -ToCurrency $base)
                $dayPct = [double]$q.ChangePct
            }
        }
        $pos += [PSCustomObject]@{ Sym = $sym; Shares = $sh; Price = $price; Value = $val; Cost = $cost; Day = $day; DayPct = $dayPct; Live = $live; Cached = ($live -and [bool]$q.FromCache); Spark = $script:SparklineStore[$sym] }
    }
    $total = 0.0; $cost = 0.0; $day = 0.0; $prev = 0.0; $missing = 0; $cached = 0
    foreach ($p0 in $pos) {
        $total += $p0.Value; $cost += $p0.Cost
        if (-not $p0.Live) { $missing++ }
        if ($p0.Cached) { $cached++ }
        if (-not [double]::IsNaN($p0.Day)) { $day += $p0.Day; $prev += $p0.Value - $p0.Day }
    }
    $trendIn = @($pos | Where-Object { $_.Live -and $null -ne $_.Spark -and @($_.Spark).Count -ge 2 })
    $trend = @()
    # only with every position: a partial sum would look like a loss or gain
    if ($pos.Count -gt 0 -and $trendIn.Count -eq $pos.Count) {
        $trend = @(Get-CombinedTrend -Series @($trendIn | ForEach-Object { @{ EndValue = $_.Value; Values = [double[]]$_.Spark } }) -Points 60)
    }
    $held = @{}; foreach ($p0 in $pos) { $held[$p0.Sym] = $true }
    $watch = @()
    foreach ($w in @($script:Config.Watchlist)) {
        $u = ([string]$w).ToUpper()
        if (-not $u -or $held.ContainsKey($u)) { continue }
        $q = $script:QuoteStore[$u]
        if ($null -eq $q -or [double]$q.Price -le 0) { continue }
        $watch += [PSCustomObject]@{ Sym = $u; Price = [double]$q.Price; Currency = [string]$q.Currency; DayPct = [double]$q.ChangePct; Spark = $script:SparklineStore[$u] }
    }
    return [PSCustomObject]@{
        Base = $base; Positions = @($pos | Sort-Object Value -Descending); Total = $total; Cost = $cost
        Day = $day; DayPct = $(if ($prev -gt 0) { $day / $prev * 100.0 } else { [double]::NaN })
        Missing = $missing; Cached = $cached; Trend = $trend
        Watch = @($watch | Sort-Object @{ Expression = { [math]::Abs($_.DayPct) }; Descending = $true })
        News = @($script:NewsItems | Where-Object { $null -ne $_ -and $_.Title } | Sort-Object Time -Descending | Select-Object -First 12)
    }
}

function Write-OvText {
    param($G, [string]$Text, $Font, $Color, [int]$X, [int]$Y, [int]$W, [int]$H, [string]$Align = "Left")
    if ($W -le 0 -or $H -le 0) { return }
    $tf = [System.Windows.Forms.TextFormatFlags]
    $fl = $tf::VerticalCenter -bor $tf::SingleLine -bor $tf::EndEllipsis -bor $tf::NoPrefix -bor $tf::NoPadding
    if ($Align -eq "Right") { $fl = $fl -bor $tf::Right } elseif ($Align -eq "Center") { $fl = $fl -bor $tf::HorizontalCenter }
    [System.Windows.Forms.TextRenderer]::DrawText($G, $Text, $Font, (New-Object System.Drawing.Rectangle($X, $Y, $W, $H)), $Color, $fl)
}

function Write-OvCard {
    param($G, [System.Drawing.Rectangle]$R, [string]$Title = "", [string]$Note = "")
    $p = $script:Pal
    $br = New-Object System.Drawing.SolidBrush($p.Card)
    $pen = New-Object System.Drawing.Pen((Get-MixColor -A $p.Border -B $p.Card -T 0.7), 1)
    Fill-RoundedRect $G $br (New-Object System.Drawing.RectangleF([float]$R.X, [float]$R.Y, [float]($R.Width - 1), [float]($R.Height - 1))) ([float](S 12)) $pen 0
    $br.Dispose(); $pen.Dispose()
    if ($Title) { Write-OvText $G $Title $fontUiBold $p.Text ($R.X + (S 16)) ($R.Y + (S 10)) ($R.Width - (S 32)) (S 20) }
    if ($Note) { Write-OvText $G $Note $fontUi $p.Muted ($R.X + [int]($R.Width / 3)) ($R.Y + (S 10)) ($R.Width - [int]($R.Width / 3) - (S 16)) (S 20) "Right" }
}

function Write-OvPill {
    # coloured percentage on a soft background of the same colour
    param($G, [double]$Pct, [int]$X, [int]$Y, [int]$W, [int]$H)
    $p = $script:Pal
    $nan = [double]::IsNaN($Pct)
    $col = if ($nan) { $p.Muted } elseif ($Pct -ge 0) { $colGreen } else { $colRed }
    $br = New-Object System.Drawing.SolidBrush((Get-MixColor -A $col -B $p.Card -T 0.16))
    Fill-RoundedRect $G $br (New-Object System.Drawing.RectangleF([float]$X, [float]$Y, [float]$W, [float]$H)) ([float]($H / 2)) $null 0
    $br.Dispose()
    $txt = if ($nan) { "-" } else { "{0:+0.00;-0.00;0.00}%" -f $Pct }
    Write-OvText $G $txt $fontUiBold $col $X $Y $W $H "Center"
}

function Add-OvHit {
    param([int]$X, [int]$Y, [int]$W, [int]$H, [string]$Kind, $Arg = $null)
    $script:Ov.Hits.Add([PSCustomObject]@{ R = (New-Object System.Drawing.Rectangle($X, $Y, $W, $H)); Kind = $Kind; Arg = $Arg })
}

function Write-OvHover {
    param($G, [int]$X, [int]$Y, [int]$W, [int]$H)
    $m = $script:Ov.Mouse
    if ($m.X -ge $X -and $m.X -lt ($X + $W) -and $m.Y -ge $Y -and $m.Y -lt ($Y + $H)) {
        $br = New-Object System.Drawing.SolidBrush((Get-MixColor -A $script:Pal.Hover -B $script:Pal.Card -T 0.6))
        Fill-RoundedRect $G $br (New-Object System.Drawing.RectangleF([float]$X, [float]$Y, [float]$W, [float]$H)) ([float](S 6)) $null 0
        $br.Dispose()
    }
}

function Write-OvHero {
    param($G, [System.Drawing.Rectangle]$R, $D)
    $p = $script:Pal
    $priv = [bool]$script:Config.PrivacyMode
    Write-OvCard $G $R
    $x = $R.X + (S 20)
    Write-OvText $G ("{0}  ·  {1}" -f (Tr "Depotwert"), (Get-DepotName ([string]$script:Config.ActiveDepot))) $fontUi $p.Muted $x ($R.Y + (S 14)) (S 300) (S 18)
    if ($D.Positions.Count -eq 0) {
        Write-OvText $G (Tr "Noch keine Positionen") $script:Ov.FontBig $p.Text $x ($R.Y + (S 40)) ($R.Width - (S 40)) (S 46)
        Write-OvText $G (Tr "Im Tab Portfolio eine Position anlegen oder eine CSV-Datei importieren.") $fontUi $p.Muted $x ($R.Y + (S 92)) ($R.Width - (S 40)) (S 18)
        return
    }
    $left = [math]::Min((S 380), [int]($R.Width * 0.46))
    Write-OvText $G (Protect-Amount -Text ("{0:N2} {1}" -f $D.Total, $D.Base) -On $priv) $script:Ov.FontBig $p.Text $x ($R.Y + (S 34)) $left (S 48)
    Write-OvPill $G $D.DayPct $x ($R.Y + (S 90)) (S 82) (S 24)
    $dayCol = if ($D.Day -ge 0) { $colGreen } else { $colRed }
    Write-OvText $G ((Protect-Amount -Text ("{0:+#,##0.00;-#,##0.00;0.00} {1}" -f $D.Day, $D.Base) -On $priv) + "  " + (Tr "heute")) $fontUi $dayCol ($x + (S 92)) ($R.Y + (S 90)) ($left - (S 92)) (S 24)
    $pl = $D.Total - $D.Cost
    $plPct = if ($D.Cost -gt 0) { $pl / $D.Cost * 100.0 } else { 0.0 }
    $plTxt = "{0}: {1}  ({2:+0.0;-0.0;0.0}%)" -f (Tr "Gesamt"), (Protect-Amount -Text ("{0:+#,##0.00;-#,##0.00;0.00} {1}" -f $pl, $D.Base) -On $priv), $plPct
    Write-OvText $G $plTxt $fontUi $(if ($pl -ge 0) { $colGreen } else { $colRed }) $x ($R.Y + (S 120)) $left (S 18)
    if ($D.Missing -gt 0) { Write-OvText $G ((Tr "{0} ohne Kurs: zum Einstand gerechnet") -f $D.Missing) $fontUi $p.Warn $x ($R.Y + (S 138)) $left (S 16) }
    elseif ($D.Cached -gt 0) { Write-OvText $G (Tr "Gespeicherte Kurse, Aktualisierung läuft") $fontUi $p.Warn $x ($R.Y + (S 138)) $left (S 16) }

    # 5-day trend with a soft area below the line
    $cx = $x + $left + (S 16); $cw = $R.Right - $cx - (S 16)
    if ($cw -lt (S 160)) { return }
    $cy = $R.Y + (S 36); $ch = $R.Height - (S 50)
    Write-OvText $G (Tr "5 Tage (heutige Stückzahlen)") $fontUi $p.Muted $cx ($R.Y + (S 14)) $cw (S 18) "Right"
    $v = @($D.Trend)
    if ($v.Count -lt 2) { Write-OvText $G (Tr "Verlauf erscheint, sobald alle Kurse geladen sind") $fontUi $p.Muted $cx $cy $cw $ch "Center"; return }
    $min = ($v | Measure-Object -Minimum).Minimum; $max = ($v | Measure-Object -Maximum).Maximum
    $span = if (($max - $min) -gt 0) { $max - $min } else { 1.0 }
    $pts = New-Object System.Drawing.PointF[] $v.Count
    for ($i = 0; $i -lt $v.Count; $i++) {
        $pts[$i] = New-Object System.Drawing.PointF([float]($cx + $cw * $i / ($v.Count - 1)), [float]($cy + $ch - (S 4) - ($v[$i] - $min) / $span * ($ch - (S 10))))
    }
    $col = if ($v[$v.Count - 1] -ge $v[0]) { $colGreen } else { $colRed }
    $area = New-Object System.Drawing.PointF[] ($v.Count + 2)
    [Array]::Copy($pts, $area, $v.Count)
    $area[$v.Count] = New-Object System.Drawing.PointF([float]($cx + $cw), [float]($cy + $ch))
    $area[$v.Count + 1] = New-Object System.Drawing.PointF([float]$cx, [float]($cy + $ch))
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle($cx, ($cy - 1), $cw, ($ch + 2))), [System.Drawing.Color]::FromArgb(70, $col), [System.Drawing.Color]::FromArgb(0, $col), [single]90)
    $G.FillPolygon($grad, $area); $grad.Dispose()
    $pen = New-Object System.Drawing.Pen($col, [single](S 2)); $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $G.DrawLines($pen, $pts); $pen.Dispose()
}

function Write-OvPositions {
    param($G, [System.Drawing.Rectangle]$R, $D)
    $p = $script:Pal
    $priv = [bool]$script:Config.PrivacyMode
    Write-OvCard $G $R (Tr "Depot heute") (Tr "nach Wert")
    $rowH = S 34
    $y = $R.Y + (S 38)
    $fit = [math]::Max(0, [int][math]::Floor(($R.Bottom - (S 8) - $y) / $rowH))
    $list = @($D.Positions)
    if ($list.Count -gt $fit) { $fit = [math]::Max(0, $fit - 1) }
    $wide = ($R.Width -ge (S 470))
    foreach ($it in @($list | Select-Object -First $fit)) {
        $x = $R.X + (S 8); $w = $R.Width - (S 16)
        Write-OvHover $G $x $y $w $rowH
        Add-OvHit $x $y $w $rowH "Ticker" $it.Sym
        Write-OvText $G $it.Sym $fontUiBold $p.Text ($x + (S 8)) $y (S 84) $rowH
        $cx = $x + (S 96)
        if ($wide -and $null -ne $it.Spark) { Draw-MiniSparkline -g $G -Rect (New-Object System.Drawing.Rectangle($cx, ($y + (S 4)), (S 90), ($rowH - (S 8)))) -Values $it.Spark; $cx += S 100 }
        $pillW = S 80
        $valW = $x + $w - $pillW - (S 20) - $cx
        Write-OvText $G (Protect-Amount -Text ("{0:N2} {1}" -f $it.Value, $D.Base) -On $priv) $fontUi $p.Text $cx ($y + (S 2)) $valW (S 18) "Right"
        $wt = if ($D.Total -gt 0) { $it.Value / $D.Total } else { 0.0 }
        $bw = [math]::Max(0, [math]::Min((S 130), $valW - (S 8)))
        if ($bw -gt 0) {
            $bx = $cx + $valW - $bw
            $tr = New-Object System.Drawing.SolidBrush($p.Input); $G.FillRectangle($tr, $bx, ($y + (S 24)), $bw, (S 3)); $tr.Dispose()
            $fb = New-Object System.Drawing.SolidBrush($p.Accent); $G.FillRectangle($fb, $bx, ($y + (S 24)), [int]($bw * $wt), (S 3)); $fb.Dispose()
        }
        Write-OvPill $G $it.DayPct ($x + $w - $pillW - (S 6)) ($y + (S 6)) $pillW (S 22)
        $y += $rowH
    }
    if ($list.Count -gt $fit) { Write-OvText $G ((Tr "+ {0} weitere im Portfolio-Tab") -f ($list.Count - $fit)) $fontUi $p.Muted ($R.X + (S 16)) $y ($R.Width - (S 32)) (S 24) }
    if ($list.Count -eq 0) { Write-OvText $G (Tr "Keine Positionen") $fontUi $p.Muted $R.X $R.Y $R.Width $R.Height "Center" }
}

function Write-OvAllocation {
    param($G, [System.Drawing.Rectangle]$R, $D)
    $p = $script:Pal
    Write-OvCard $G $R (Tr "Aufteilung")
    $slices = @(Get-AllocationSlices -Items @($D.Positions | ForEach-Object { @{ Name = $_.Sym; Value = $_.Value } }) -MaxSlices 6 -OtherName (Tr "Übrige"))
    if ($slices.Count -eq 0) { Write-OvText $G (Tr "Keine Positionen") $fontUi $p.Muted $R.X $R.Y $R.Width $R.Height "Center"; return }
    $size = [math]::Max((S 60), [math]::Min([int]($R.Width * 0.46), $R.Height - (S 58)))
    $dx = $R.X + (S 18); $dy = $R.Y + (S 40) + [int](($R.Height - (S 52) - $size) / 2)
    $pal = @(Get-SeriesPalette -Count 7)
    $ring = [math]::Max((S 10), [int]($size * 0.16))
    $arc = New-Object System.Drawing.Rectangle(($dx + [int]($ring / 2)), ($dy + [int]($ring / 2)), ($size - $ring), ($size - $ring))
    $a = -90.0
    for ($i = 0; $i -lt $slices.Count; $i++) {
        $sw = 360.0 * $slices[$i].Pct / 100.0
        $gapA = if ($slices.Count -gt 1 -and $sw -gt 4) { 1.6 } else { 0.0 }
        $pen = New-Object System.Drawing.Pen($pal[$i % $pal.Count], [single]$ring)
        $G.DrawArc($pen, $arc, [single]$a, [single][math]::Max(0.4, $sw - $gapA)); $pen.Dispose()
        $a += $sw
    }
    Write-OvText $G ([string]$D.Positions.Count) $script:Ov.FontMid $p.Text $dx ($dy + [int]($size / 2) - (S 20)) $size (S 24) "Center"
    Write-OvText $G (Tr "Positionen") $fontUi $p.Muted $dx ($dy + [int]($size / 2) + (S 4)) $size (S 16) "Center"
    $lx = $dx + $size + (S 18); $lw = $R.Right - $lx - (S 14)
    $ly = $R.Y + (S 40) + [int](($R.Height - (S 52) - $slices.Count * (S 22)) / 2)
    for ($i = 0; $i -lt $slices.Count; $i++) {
        $b = New-Object System.Drawing.SolidBrush($pal[$i % $pal.Count]); $G.FillEllipse($b, $lx, ($ly + (S 6)), (S 9), (S 9)); $b.Dispose()
        Write-OvText $G $slices[$i].Name $fontUi $p.Text ($lx + (S 16)) $ly ($lw - (S 66)) (S 22)
        Write-OvText $G ("{0:N1}%" -f $slices[$i].Pct) $fontUi $p.Muted ($lx + $lw - (S 52)) $ly (S 52) (S 22) "Right"
        $ly += S 22
    }
}

function Write-OvWatch {
    param($G, [System.Drawing.Rectangle]$R, $D)
    $p = $script:Pal
    Write-OvCard $G $R (Tr "Watchlist in Bewegung") (Tr "ohne Depotwerte")
    $rowH = S 28; $y = $R.Y + (S 38)
    $fit = [math]::Max(0, [int][math]::Floor(($R.Bottom - (S 8) - $y) / $rowH))
    foreach ($it in @($D.Watch | Select-Object -First $fit)) {
        $x = $R.X + (S 8); $w = $R.Width - (S 16)
        Write-OvHover $G $x $y $w $rowH
        Add-OvHit $x $y $w $rowH "Ticker" $it.Sym
        Write-OvText $G $it.Sym $fontUiBold $p.Text ($x + (S 8)) $y (S 84) $rowH
        if ($w -ge (S 330) -and $null -ne $it.Spark) { Draw-MiniSparkline -g $G -Rect (New-Object System.Drawing.Rectangle(($x + (S 96)), ($y + (S 3)), (S 70), ($rowH - (S 6)))) -Values $it.Spark }
        Write-OvText $G ("{0:N2} {1}" -f $it.Price, $it.Currency) $fontUi $p.Muted ($x + $w - (S 210)) $y (S 114) $rowH "Right"
        Write-OvPill $G $it.DayPct ($x + $w - (S 86)) ($y + (S 4)) (S 80) (S 20)
        $y += $rowH
    }
    if ($D.Watch.Count -eq 0) { Write-OvText $G (Tr "Noch keine Kurse") $fontUi $p.Muted $R.X $R.Y $R.Width $R.Height "Center" }
}

function Write-OvNews {
    param($G, [System.Drawing.Rectangle]$R, $D)
    $p = $script:Pal
    Write-OvCard $G $R (Tr "Neueste Meldungen")
    $rowH = S 40; $y = $R.Y + (S 38)
    $fit = [math]::Max(0, [int][math]::Floor(($R.Bottom - (S 8) - $y) / $rowH))
    foreach ($it in @($D.News | Select-Object -First $fit)) {
        $x = $R.X + (S 8); $w = $R.Width - (S 16)
        Write-OvHover $G $x $y $w $rowH
        Add-OvHit $x $y $w $rowH "News" $it
        Write-OvText $G ([string]$it.Title) $fontUi $p.Text ($x + (S 8)) ($y + (S 2)) ($w - (S 16)) (S 20)
        $meta = "{0}  ·  {1}  ·  {2}" -f (@($it.Syms) -join " "), [string]$it.Publisher, ([DateTime]$it.Time).ToString("dd.MM. HH:mm")
        Write-OvText $G $meta $fontUi $p.Muted ($x + (S 8)) ($y + (S 20)) ($w - (S 16)) (S 18)
        $y += $rowH
    }
    if ($D.News.Count -eq 0) { Write-OvText $G (Tr "Noch keine Meldungen geladen (Tab News)") $fontUi $p.Muted $R.X $R.Y $R.Width $R.Height "Center" }
}

function Write-Overview {
    param($G, [int]$W, [int]$H)
    $ov = $script:Ov
    if ($null -eq $ov) { return }
    $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $G.Clear($script:Pal.BodyBg)
    $ov.Hits.Clear()
    $d = Get-OverviewData
    $m = S 14; $gap = S 12
    $inner = $W - 2 * $m
    $heroH = S 164
    Write-OvHero $G (New-Object System.Drawing.Rectangle($m, $m, $inner, $heroH)) $d
    $top = $m + $heroH + $gap
    $rest = $H - $top - $m
    $midH = [int](($rest - $gap) * 0.54); $lowH = $rest - $gap - $midH
    $leftW = [int](($inner - $gap) * 0.56); $rightW = $inner - $gap - $leftW
    $rx = $m + $leftW + $gap
    Write-OvPositions  $G (New-Object System.Drawing.Rectangle($m, $top, $leftW, $midH)) $d
    Write-OvAllocation $G (New-Object System.Drawing.Rectangle($rx, $top, $rightW, $midH)) $d
    Write-OvWatch      $G (New-Object System.Drawing.Rectangle($m, ($top + $midH + $gap), $leftW, $lowH)) $d
    Write-OvNews       $G (New-Object System.Drawing.Rectangle($rx, ($top + $midH + $gap), $rightW, $lowH)) $d
}

function Show-OverviewDialog {
    if ($null -ne $script:Ov) { return }
    $dlg = New-DialogForm -Title "Übersicht" -W (S 1000) -H (S 680) -Key "Overview"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MaximizeBox = $true
    $dlg.KeyPreview = $true
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dlg.MinimumSize = New-Object System.Drawing.Size([math]::Min((S 820), $wa.Width), [math]::Min((S 580), $wa.Height))
    $dlg.ClientSize = New-Object System.Drawing.Size([math]::Min((S 1000), ($wa.Width - (S 24))), [math]::Min((S 680), ($wa.Height - (S 48))))
    $cv = New-Object System.Windows.Forms.Panel
    $cv.Dock = [System.Windows.Forms.DockStyle]::Fill
    Enable-DoubleBuffering -Control $cv
    $dlg.Controls.Add($cv)
    $script:Ov = @{
        Dlg = $dlg; Canvas = $cv; Hits = (New-Object System.Collections.Generic.List[object]); Mouse = (New-Object System.Drawing.Point(-1, -1))
        FontBig = (New-Object System.Drawing.Font("Segoe UI Semibold", 24)); FontMid = (New-Object System.Drawing.Font("Segoe UI Semibold", 14)); Pick = ""; Over = -1
    }
    $cv.Add_Paint({ param($sender, $e) try { Write-Overview -G $e.Graphics -W $sender.ClientSize.Width -H $sender.ClientSize.Height } catch { Write-WidgetLog "Overview: $($_.Exception.Message)" "WARN" } })
    $cv.Add_Resize({ param($sender, $e) $sender.Invalidate() })
    $cv.Add_MouseMove({
        param($sender, $e)
        $ov = $script:Ov
        if ($null -eq $ov) { return }
        $ov.Mouse = $e.Location
        $over = -1
        for ($i = 0; $i -lt $ov.Hits.Count; $i++) { if ($ov.Hits[$i].R.Contains($e.Location)) { $over = $i; break } }
        # repaint only when the pointer reaches another row
        if ($over -ne $ov.Over) {
            $ov.Over = $over
            $sender.Cursor = if ($over -ge 0) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default }
            $sender.Invalidate()
        }
    })
    $cv.Add_MouseClick({
        param($sender, $e)
        $ov = $script:Ov
        if ($null -eq $ov -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        foreach ($h in $ov.Hits.ToArray()) {
            if (-not $h.R.Contains($e.Location)) { continue }
            if ($h.Kind -eq "Ticker") { $ov.Pick = [string]$h.Arg; $ov.Dlg.Close() }
            elseif ($h.Kind -eq "News") { Open-NewsItem $h.Arg }
            return
        }
    })
    $dlg.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -in @([System.Windows.Forms.Keys]::Escape, [System.Windows.Forms.Keys]::F6)) { $sender.Close() }
        elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::F9) { Set-PrivacyMode (-not [bool]$script:Config.PrivacyMode); $script:Ov.Canvas.Invalidate() }
    })
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 5000
    $timer.Add_Tick({ if ($null -ne $script:Ov) { $script:Ov.Canvas.Invalidate() } })
    $timer.Start()
    $pick = ""
    try {
        [void]$dlg.ShowDialog($form)
        $pick = [string]$script:Ov.Pick
    } finally {
        $timer.Stop(); $timer.Dispose()
        $script:Ov.FontBig.Dispose(); $script:Ov.FontMid.Dispose()
        $script:Ov = $null
        $dlg.Dispose()
    }
    if ($pick) { Switch-ActiveTicker -NewTicker $pick -SkipResolve $true; Set-ActiveTab -TabName "Chart" }
}

# ---- menu: first entry of "Ansicht" ----
$miOverview = New-Object System.Windows.Forms.ToolStripMenuItem((Tr "Übersicht"))
$miOverview.ShortcutKeyDisplayString = "F6"
$miOverview.Add_Click({ Show-OverviewDialog })
$mbView.DropDownItems.Insert(0, $miOverview)
$mbView.DropDownItems.Insert(1, (New-Object System.Windows.Forms.ToolStripSeparator))
