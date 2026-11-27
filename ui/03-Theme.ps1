# TerminalWidget UI part 03 (Theme) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

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

function Get-CustomTheme {
    # a theme of the user by name, cleaned; $null for built-in or unknown names
    param([string]$Name)
    foreach ($t in @($script:Config.CustomThemes)) {
        if ($null -ne $t -and [string]$t.Name -eq $Name) { return (ConvertFrom-ThemeData $t) }
    }
    return $null
}

function Get-AllThemeNames {
    return @(Get-ThemeNames) + @(@($script:Config.CustomThemes) | Where-Object { $null -ne $_ -and $null -ne (ConvertFrom-ThemeData $_) } | ForEach-Object { [string]$_.Name })
}

function Get-ThemeBaseColors {
    # v8.0: an own theme is a built-in one with some colours replaced
    $ct = Get-CustomTheme ([string]$script:Config.Theme)
    if ($null -eq $ct) { return (Get-BuiltinThemeColors -ThemeName ([string]$script:Config.Theme)) }
    $t = Get-BuiltinThemeColors -ThemeName ([string]$ct.Base)
    foreach ($pp in $ct.Colors.PSObject.Properties) {
        $rgb = ConvertFrom-HexColor ([string]$pp.Value)
        if ($null -ne $rgb) { $t[$pp.Name] = [System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]) }
    }
    # title bar colours are Windows COLORREF numbers (0x00BBGGRR), not Color objects
    $ref = { param($c) [int](([int]$c.B * 65536) + ([int]$c.G * 256) + [int]$c.R) }
    $t["DwmCap"] = (& $ref $t["HeaderBg"]); $t["DwmBdr"] = (& $ref $t["Border"]); $t["DwmDark"] = [int]($t["BodyBg"].GetBrightness() -lt 0.5)
    return $t
}

function Get-BuiltinThemeColors {
    param([string]$ThemeName)
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

    switch ($ThemeName) {
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
        "Contrast" {
            # v5.7: high contrast - black, white text, yellow accent, clear borders
            return @{
                HeaderBg = [System.Drawing.Color]::FromArgb(0, 0, 0)
                BodyBg   = [System.Drawing.Color]::FromArgb(0, 0, 0)
                PanelBg  = [System.Drawing.Color]::FromArgb(0, 0, 0)
                Card     = [System.Drawing.Color]::FromArgb(10, 10, 10)
                Input    = [System.Drawing.Color]::FromArgb(0, 0, 0)
                Hover    = [System.Drawing.Color]::FromArgb(40, 40, 0)
                Grid     = [System.Drawing.Color]::FromArgb(90, 90, 90)
                Border   = [System.Drawing.Color]::FromArgb(210, 210, 210)
                Text     = [System.Drawing.Color]::FromArgb(255, 255, 255)
                Muted    = [System.Drawing.Color]::FromArgb(225, 225, 225)
                Accent   = [System.Drawing.Color]::FromArgb(255, 221, 0)
                Warn     = [System.Drawing.Color]::FromArgb(255, 170, 0)
                DwmCap   = 0x00000000
                DwmBdr   = 0x00FFFFFF
                DwmDark  = 1
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

function Get-ThemeColors {
    # V7.0: the base colours of the theme plus the derived tokens (disabled text,
    # accent hover / pressed / subtle, text on accent)
    $p = Get-ThemeBaseColors
    $toRgb = { param($c) return @([int]$c.R, [int]$c.G, [int]$c.B) }
    $acc = & $toRgb $p.Accent
    $light = ($p.BodyBg.GetBrightness() -gt 0.5)
    $st = Get-AccentStates -Rgb $acc -Surface (& $toRgb $p.Card) -DarkSurface (-not $light)
    $p["AccentHover"]   = [System.Drawing.Color]::FromArgb($st.Hover[0], $st.Hover[1], $st.Hover[2])
    $p["AccentPressed"] = [System.Drawing.Color]::FromArgb($st.Pressed[0], $st.Pressed[1], $st.Pressed[2])
    $p["AccentSubtle"]  = [System.Drawing.Color]::FromArgb($st.Subtle[0], $st.Subtle[1], $st.Subtle[2])
    $p["OnAccent"]      = [System.Drawing.Color]::FromArgb($st.OnAccent[0], $st.OnAccent[1], $st.OnAccent[2])
    $dis = Get-MixRgb -A (& $toRgb $p.Muted) -B (& $toRgb $p.Card) -T 0.55
    $p["Disabled"]      = [System.Drawing.Color]::FromArgb($dis[0], $dis[1], $dis[2])
    # V7.1: fixed data colours as tokens (busy = amber, mark = ruler / drawings, series colours for charts and legends)
    $p["Busy"]    = [System.Drawing.Color]::FromArgb(245, 158, 11)
    $p["Mark"]    = $(if ($light) { [System.Drawing.Color]::FromArgb(202, 138, 4) } else { [System.Drawing.Color]::FromArgb(250, 204, 21) })
    $p["Violet"]  = [System.Drawing.Color]::FromArgb(168, 85, 247)
    $p["Pink"]    = [System.Drawing.Color]::FromArgb(236, 72, 153)
    $p["Cyan"]    = [System.Drawing.Color]::FromArgb(34, 211, 238)
    $p["Lime"]    = [System.Drawing.Color]::FromArgb(132, 204, 22)
    $p["Blue"]    = [System.Drawing.Color]::FromArgb(59, 130, 246)
    $p["Neutral"] = [System.Drawing.Color]::FromArgb(148, 163, 184)
    return $p
}

function Get-Token {
    # V7.0: Get-Token 'surface.card' -> colour from the current palette
    param([string]$Name)
    $map = Get-TokenMap
    if (-not $map.Contains($Name)) { throw "Unknown design token: $Name" }
    return $script:Pal[$map[$Name]]
}

$script:Pal = Get-ThemeColors
# v5.2: design numbers of the chosen style (radii, gaps, row height ...)
$script:UiSpec = Get-UiSpec -Style ([string]$script:Config.UiStyle) -Density ([string]$script:Config.RowDensity)
$script:IconFont = if ($script:InstalledFonts -contains "Segoe Fluent Icons") { "Segoe Fluent Icons" } elseif ($script:InstalledFonts -contains "Segoe MDL2 Assets") { "Segoe MDL2 Assets" } else { "" }
function Get-SeriesPalette {
    # V7.1: categorical colours for donut / legend, derived from the accent (hue steps), so every theme stays consistent
    param([int]$Count = 8)
    $a = $script:Pal.Accent
    $h0 = [double]$a.GetHue()
    $dark = ($script:Pal.BodyBg.GetBrightness() -lt 0.5)
    $s = 0.55; $v = $(if ($dark) { 0.90 } else { 0.72 })
    $out = @()
    for ($i = 0; $i -lt $Count; $i++) {
        if ($i -eq 0) { $out += $a; continue }
        $h = (($h0 + 360.0 / $Count * $i) % 360.0)
        $c = $v * $s; $x = $c * (1 - [math]::Abs((($h / 60.0) % 2) - 1)); $m = $v - $c
        switch ([int][math]::Floor($h / 60.0)) {
            0 { $r = $c; $g = $x; $b = 0 } 1 { $r = $x; $g = $c; $b = 0 } 2 { $r = 0; $g = $c; $b = $x }
            3 { $r = 0; $g = $x; $b = $c } 4 { $r = $x; $g = 0; $b = $c } default { $r = $c; $g = 0; $b = $x }
        }
        $out += [System.Drawing.Color]::FromArgb([int](($r + $m) * 255), [int](($g + $m) * 255), [int](($b + $m) * 255))
    }
    return $out
}

function New-ThemedCombo {
    # V7.1: drop-down with rounded closed box and styled items (falls back to the plain combo box)
    if ('TwComboV7' -as [type]) { $c = New-Object TwComboV7; $c.ItemHeight = S 18; return $c }
    return (New-Object System.Windows.Forms.ComboBox)
}

function Update-MenuRenderer {
    # V7.0: colours of the shared menu renderer follow the theme
    try {
        $p = $script:Pal
        if (-not ('TwMenuRendererV7' -as [type])) { return }
        [TwMenuRendererV7]::BackC   = $p.Card
        [TwMenuRendererV7]::HoverC  = $p.Hover
        [TwMenuRendererV7]::TextC   = $p.Text
        [TwMenuRendererV7]::MutedC  = $p.Disabled
        [TwMenuRendererV7]::BorderC = $p.Border
        [TwMenuRendererV7]::AccentC = $p.Accent
        [TwMenuRendererV7]::Radius  = [int]$script:UiSpec.BtnRadius
        if ('TwComboV7' -as [type]) {
            [TwComboV7]::ListC = $p.Card
            [TwComboV7]::HoverC = $p.Hover
            [TwComboV7]::TextC = $p.Text
            [TwComboV7]::AccentC = $p.Accent
        }
        if ('TwSegmentV7' -as [type]) {
            [TwSegmentV7]::AccentC = $p.Accent
            [TwSegmentV7]::TrackC = $p.Input
            [TwSegmentV7]::TextC = $p.Text
            [TwSegmentV7]::MutedC = $p.Muted
            [TwSegmentV7]::OnTextC = $p.OnAccent
        }
        if ('TwSliderV7' -as [type]) {
            [TwSliderV7]::AccentC = $p.Accent
            [TwSliderV7]::TrackC = $p.Border
            [TwSliderV7]::KnobC = $p.Text
        }
        if ('TwComboV7' -as [type]) { [TwComboV7]::BorderC = $p.Border }
        if ('TwToggleV7' -as [type]) {
            [TwToggleV7]::OnC = $p.Accent
            [TwToggleV7]::OffC = $p.Border
            [TwToggleV7]::KnobC = $p.Text
            [TwToggleV7]::TextC = $p.Text
            [TwToggleV7]::DisabledC = $p.Disabled
        }
        if (-not ([System.Windows.Forms.ToolStripManager]::Renderer -is [TwMenuRendererV7])) {
            [System.Windows.Forms.ToolStripManager]::Renderer = New-Object TwMenuRendererV7
        }
    } catch { }
}

Update-MenuRenderer

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

    # V7.1: the divider between chart and indicator pane can be dragged (Config.PaneDivider = share of the main chart)
    $priceH = $totalH
    if ($showRsi) {
        $dv = 0.72
        try { $dv = [double]$script:Config.PaneDivider } catch { $dv = 0.72 }
        if ($dv -lt 0.35 -or $dv -gt 0.85) { $dv = 0.72 }
        $priceH = [int]([math]::Floor($totalH * $dv))
        if (($totalH - $priceH) -lt (S 42)) { $priceH = [math]::Max(1, $totalH - (S 42)) }
    }
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
    # v8.0: price axis scrolled by the user; another series starts automatic again
    if ($script:PriceScaleKey -ne [string]$script:ActiveSeriesKey) { $script:PriceScale = 1.0; $script:PriceShift = 0.0; $script:PriceScaleKey = [string]$script:ActiveSeriesKey }
    $priceScaled = Test-PriceScaled
    if ($priceScaled) {
        $sr0 = Get-ScaledPriceRange -MinP $minP -SpanP $spanP -Log $isLog -Scale $script:PriceScale -Shift $script:PriceShift
        $minP = $sr0.Min; $spanP = $sr0.Span; $maxP = $minP + $spanP
    }

    # Horizontal Grid & Right Y-Axis
    $gridSteps = 5
    for ($s = 0; $s -le $gridSteps; $s++) {
        $frac = $s / [double]$gridSteps
        $y = [int]($priceRect.Bottom - ($frac * $priceRect.Height))
        $val = Get-PriceFromFrac $frac $minP $spanP $isLog
        $g.DrawLine($c["gridPen"], $priceRect.Left, $y, $priceRect.Right, $y)
        # v5.5: percent from the first visible bar instead of prices (optional)
        $axTxt = if ([bool]$script:Config.PctAxis -and [double]$series[0].Close -gt 0) { Format-PctAxisLabel -Value $val -Base ([double]$series[0].Close) } else { "{0:N2}" -f $val }
        $g.DrawString($axTxt, $fontAxis, $c["axisTextBrush"], ($priceRect.Right + (S 6)), ($y - (S 6)))
    }

    # a scaled price range can push lines outside the panel: clip everything up to the axis tag
    if ($priceScaled) { $g.SetClip($priceRect) }

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

    # v5.5: support / resistance from the daily bars (same as the ticker analysis)
    if ([bool]$script:Config.ShowSR) {
        $srSym = ([string]$script:Config.ActiveTicker).ToUpper()
        $srE = $script:DailyCache[$srSym]
        if (-not (Test-DailyCacheFresh -Entry $srE -Day (Get-TodayKey))) { Request-DailyBars -Symbols @($srSym) }
        if ($null -ne $srE) {
            $srFx = Convert-CurrencyValue -Amount 1.0 -FromCurrency ([string]$srE.Currency) -ToCurrency ([string]$script:ChartCur)
            foreach ($lv in @(@("Unterstützung", $srE.Support, $colGreen), @("Widerstand", $srE.Resistance, $colRed))) {
                if ($null -eq $lv[1] -or [double]$lv[1] -le 0) { continue }
                $pv = [double]$lv[1] * $srFx
                $sy0 = [int]($priceRect.Bottom - ((Get-PriceFrac $pv $minP $spanP $isLog) * $priceRect.Height))
                if ($sy0 -lt $priceRect.Top -or $sy0 -gt $priceRect.Bottom) { continue }
                $srPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(170, $lv[2].R, $lv[2].G, $lv[2].B), [float](S 1))
                $srPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::DashDot
                $g.DrawLine($srPen, $priceRect.Left, $sy0, $priceRect.Right, $sy0)
                $srPen.Dispose()
                $srTxt = "{0} {1:N2}" -f (Tr $lv[0]), $pv
                $srSz = $g.MeasureString($srTxt, $fontAxis)
                $srBr = New-Object System.Drawing.SolidBrush($lv[2])
                $g.DrawString($srTxt, $fontAxis, $srBr, [float]($priceRect.Right - $srSz.Width - (S 4)), [float]($sy0 - $srSz.Height - 1))
                $srBr.Dispose()
            }
            # v5.7: 50/200-day crossings (daily data) as triangles at the bottom
            $mk = @(Get-MaCrossMarkers -Closes ([double[]]$srE.Close) -Dates ([string[]]$srE.Dates))
            if ($mk.Count -gt 0 -and $n -ge 2) {
                $md = @{}; foreach ($m0 in $mk) { $md[[string]$m0.Date] = [string]$m0.Kind }
                $prevD = ""
                for ($mi = 0; $mi -lt $n; $mi++) {
                    $dStr = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$series[$mi].Ts).LocalDateTime.ToString("yyyy-MM-dd")
                    if ($dStr -eq $prevD) { continue }
                    $prevD = $dStr
                    if (-not $md.ContainsKey($dStr)) { continue }
                    $mx = [float]($priceRect.Left + $priceRect.Width * $mi / [math]::Max(1, $n - 1))
                    $gold = ($md[$dStr] -eq "Golden")
                    $tc = if ($gold) { $colGreen } else { $colRed }
                    $tb = New-Object System.Drawing.SolidBrush($tc)
                    $yb = [float]($priceRect.Bottom - (S 2))
                    $tri = if ($gold) { [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF($mx, ($yb - (S 9)))), (New-Object System.Drawing.PointF(($mx - (S 5)), $yb)), (New-Object System.Drawing.PointF(($mx + (S 5)), $yb))) } else { [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF($mx, $yb)), (New-Object System.Drawing.PointF(($mx - (S 5)), ($yb - (S 9)))), (New-Object System.Drawing.PointF(($mx + (S 5)), ($yb - (S 9))))) }
                    $g.FillPolygon($tb, $tri)
                    $g.DrawString($(if ($gold) { "50/200 " + [string][char]0x2191 } else { "50/200 " + [string][char]0x2193 }), $fontAxis, $tb, [float]($mx + (S 6)), [float]($yb - (S 13)))
                    $tb.Dispose()
                }
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
        $refTxt = if ($script:Config.Timeframe -eq "1d" -and $script:ActivePrevClose -gt 0) { Tr "vs. Vortag" } elseif ($s0 -gt 0 -or $s1 -lt ($totalN - 1)) { Tr "Ausschnitt" } else { Tr "Zeitraum" }
        if ($series[$n - 1].Ext) { $refTxt += $(if ($series[$n - 1].Sess -eq "PRE") { Tr ", inkl. Pre" } else { Tr ", inkl. Post" }) }
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
    if ($priceScaled) { $g.ResetClip() }
    # the tag stays at the edge when the last price is scrolled out of view
    $lastInView = ($lastY -ge $priceRect.Top -and $lastY -le $priceRect.Bottom)
    $tagY = [math]::Max($priceRect.Top, [math]::Min($priceRect.Bottom, $lastY))
    $tagRect = New-Object System.Drawing.Rectangle(($priceRect.Right + 2), ($tagY - [int]($tagH / 2)), ($rightAxisWidth - 4), $tagH)
    $tagBrush = New-Object System.Drawing.SolidBrush($lineColor)
    # v5.2: dotted guide from the last point to the axis, a dot with a halo, rounded tag
    $guide = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(140, $lineColor.R, $lineColor.G, $lineColor.B), 1)
    $guide.DashPattern = [float[]]@(2, 3)
    if ($lastInView) { $g.DrawLine($guide, [float]$pts[$n - 1].X, [float]$lastY, [float]$priceRect.Right, [float]$lastY) }
    $guide.Dispose()
    if (-not $isCandle -and $lastInView) {
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
                $diaPts = [System.Drawing.PointF[]]@(   # 9.0: was $pts, which overwrote the price points (date axis, hit tests)
                    (New-Object System.Drawing.PointF([float]$mx, [float]($my - (S 5)))), (New-Object System.Drawing.PointF([float]($mx + (S 5)), [float]$my)),
                    (New-Object System.Drawing.PointF([float]$mx, [float]($my + (S 5)))), (New-Object System.Drawing.PointF([float]($mx - (S 5)), [float]$my)))
                $g.FillPolygon($mBr, $diaPts)
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
            $barDays = New-Object 'string[]' $n
            for ($i = 0; $i -lt $n; $i++) { $barDays[$i] = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$series[$i].Ts).LocalDateTime.ToString("yyyy-MM-dd") }
            $buyBr = New-Object System.Drawing.SolidBrush($colGreen)
            $sellBr = New-Object System.Drawing.SolidBrush($colRed)
            $outPen = New-Object System.Drawing.Pen($script:Pal.PanelBg, [float]1)
            try {
                foreach ($tx in $txA) {
                    $ti = Get-TradeBarIndex -BarDates $barDays -Date ([string]$tx.Date)   # 11.2: also weekends and holidays
                    if ($ti -lt 0) { continue }
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
    # v7.7: news of this ticker as small squares along the top, at the time of publication
    if ([bool]$script:Config.ShowNewsMarkers -and $n -ge 2) {
        $newsTs = New-Object 'long[]' $n
        for ($i = 0; $i -lt $n; $i++) { $newsTs[$i] = [long]$series[$i].Ts }
        # a headline belongs to a bar when it is at most one bar spacing (plus a weekend on daily bars) later
        $spacing = [long](($newsTs[$n - 1] - $newsTs[0]) / ($n - 1))
        $maxGap = if ($spacing -ge 72000000) { [long]345600000 } else { [long][math]::Max(3600000, 3 * ($newsTs[1] - $newsTs[0])) }
        $marks = @(Get-NewsChartMarks -Items @(Get-NewsPool) -Symbol $actU -BarTsMs $newsTs -MaxGapMs $maxGap)
        if ($marks.Count -gt 0) {
            $nwBr = New-Object System.Drawing.SolidBrush($script:Pal.Accent)
            try {
                foreach ($mk in $marks) {
                    $nx = $priceRect.Left + (($mk.Index / [double]($n - 1)) * $priceRect.Width)
                    $ny = $priceRect.Top + (S 20)
                    $side = if ($mk.Count -gt 1) { S 8 } else { S 6 }
                    $g.FillRectangle($nwBr, [float]($nx - $side / 2), [float]$ny, [float]$side, [float]$side)
                    & $addLeg "xx" ($nx - (S 6)) ($ny - (S 3)) "" $fontAxis ("News: " + $mk.Text)
                }
            } finally { $nwBr.Dispose() }
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
    $rsiPlotL = $null

    # Optional RSI Sub-Panel (v4.6: or MACD)
    if ($showRsi -and $rsiH -ge (S 42) -and [string]$script:Config.LowerPanel -eq "MACD") {
        $rsiRect = New-Object System.Drawing.Rectangle($padLeft, ($padTop + $priceH + $gapY), $plotWidth, $rsiH)
        if (-not $fresh) { $g.FillRectangle($c["panelBrush"], $rsiRect); $g.DrawRectangle($c["framePen"], $rsiRect) }
        if ($fresh) {
            # V7.1: indicator pane as a rounded card
            $cp = New-RoundedPath (New-Object System.Drawing.RectangleF([float]$rsiRect.X, [float]$rsiRect.Y, [float]$rsiRect.Width, [float]$rsiRect.Height)) ([float](S 6))
            $g.FillPath($c["panelBrush"], $cp); $cp.Dispose()
        }
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
        if ($fresh) {
            # V7.1: indicator pane as a rounded card
            $cp = New-RoundedPath (New-Object System.Drawing.RectangleF([float]$rsiRect.X, [float]$rsiRect.Y, [float]$rsiRect.Width, [float]$rsiRect.Height)) ([float](S 6))
            $g.FillPath($c["panelBrush"], $cp); $cp.Dispose()
        }

        $obVal = [double]$script:Config.RsiOverbought
        $osVal = [double]$script:Config.RsiOversold
        # v7.1.1: values are drawn below the label row, with room for the line at 0 and 100
        $rsiPlot = New-Object System.Drawing.Rectangle($rsiRect.X, ($rsiRect.Y + (S 17)), $rsiRect.Width, ($rsiRect.Height - (S 19)))
        $rsiPlotL = $rsiPlot
        $yOb = [int]($rsiPlot.Bottom - (($obVal / 100.0) * $rsiPlot.Height))
        $y50 = [int]($rsiPlot.Bottom - (0.50 * $rsiPlot.Height))
        $yOs = [int]($rsiPlot.Bottom - (($osVal / 100.0) * $rsiPlot.Height))

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
                    $ry = $rsiPlot.Bottom - (($clamped / 100.0) * $rsiPlot.Height)
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
        RsiPlot        = $rsiPlotL
        PaneTop        = $padTop
        PaneTotal      = $totalH
        GapY           = $gapY
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
    $script:PriceScale = 1.0
    $script:PriceShift = 0.0
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
            $out += [PSCustomObject]@{ Price = $ek; Label = ("{0} {1:N2}" -f (Tr "EK"), $ek); Kind = "EK"; Hit = $false }
        }
    }
    foreach ($a in $script:Alerts) {
        # v4.3: trailing stop = current stop price as a line
        if ($a.Ticker -eq $sym -and (Get-AlertKind $a.Condition) -eq "TRAIL" -and [double]$a.Peak -gt 0 -and [string]$a.Currency -match '^[A-Z]{3}$') {
            $lv = Convert-CurrencyValue -Amount ([double]$a.Peak * (1.0 - [double]$a.TargetPrice / 100.0)) -FromCurrency $a.Currency -ToCurrency $curr
            $out += [PSCustomObject]@{ Price = $lv; Label = ("{0} {1:N2}" -f (Tr "Trailing-Stopp"), $lv); Kind = "AL"; Hit = [bool]$a.Triggered }
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
    $used = New-Object System.Collections.Generic.List[object]
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
                # 9.0: a tag that would cover an earlier one moves to the left of it
                $tx = [int](Get-FreeTagX -X $tx -Y $ty -Width $tw -Height $th -Used $used.ToArray() -MinX ($PriceRect.Left + (S 4)) -Gap (S 4))
                $used.Add(@{ X = $tx; Y = $ty; W = $tw; H = $th })
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
                $tx = [int](Get-FreeTagX -X $tx -Y $ty -Width $tw2 -Height $th -Used $used.ToArray() -MinX ($PriceRect.Left + (S 4)) -Gap (S 4))
                $used.Add(@{ X = $tx; Y = $ty; W = $tw2; H = $th })
                $g.FillRectangle($br, $tx, $ty, $tw2, $th)
                $g.DrawString($txt2, $fontAxis, $fg, ($tx + (S 3)), ($ty + 1))
                if ($null -ne $Legends) { $Legends.Add([PSCustomObject]@{ R = (New-Object System.Drawing.RectangleF([float]$tx, [float]$ty, [float]$tw2, [float]$th)); Key = "LEVELS" }) }
            }
        } finally {
            $br.Dispose()
        }
    }
}


