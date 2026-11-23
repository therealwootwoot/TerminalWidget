# ==============================================================================
# TerminalWidget.Core.ps1 - pure logic of the Terminal Widget (v4.0)
# ------------------------------------------------------------------------------
# No UI, no network, no config access: indicators, number parsing, currency
# units, market hours / sessions (DST-aware), exchange holiday calendars,
# (v3.0) symbol resolution, Yahoo search parsing, transaction math, CSV
# escaping and data-integrity checks; (v4.0) layouts, glossary, quote cache,
# freshness and the yearly report with historical FX rates.
# Dot-sourced by TerminalWidget.ps1 and by TerminalWidget.Core.Tests.ps1 (Pester):
#     Invoke-Pester .\TerminalWidget.Core.Tests.ps1
# Keep this file next to TerminalWidget.ps1. Encoding: UTF-8 with BOM.
# Must stay Windows PowerShell 5.1 compatible (no ??, ?., &&, ternary).
# ==============================================================================

# ------------------------------------------------------------------------------
# Market hours (from meta.currentTradingPeriod, all timestamps in unix seconds)
# ------------------------------------------------------------------------------
function Get-TodSec {
    # Seconds since exchange-local midnight
    param([long]$TsSec, [int]$Off)
    $x = ($TsSec + $Off) % 86400
    if ($x -lt 0) { $x += 86400 }
    return [int]$x
}

# Exchange time zones: DST-aware session math (v2.8). Yahoo only reports the
# CURRENT gmtoffset; cached bars from before a DST switch (US and EU switch on
# different dates!) were classified one hour off.
$script:TzCache = @{}
$script:IanaToWindowsTz = @{
    "America/New_York"    = "Eastern Standard Time"
    "America/Toronto"     = "Eastern Standard Time"
    "America/Chicago"     = "Central Standard Time"
    "America/Los_Angeles" = "Pacific Standard Time"
    "America/Sao_Paulo"   = "E. South America Standard Time"
    "Europe/London"       = "GMT Standard Time"
    "Europe/Dublin"       = "GMT Standard Time"
    "Europe/Lisbon"       = "GMT Standard Time"
    "Europe/Zurich"       = "W. Europe Standard Time"
    "Europe/Berlin"       = "W. Europe Standard Time"
    "Europe/Amsterdam"    = "W. Europe Standard Time"
    "Europe/Rome"         = "W. Europe Standard Time"
    "Europe/Milan"        = "W. Europe Standard Time"
    "Europe/Stockholm"    = "W. Europe Standard Time"
    "Europe/Oslo"         = "W. Europe Standard Time"
    "Europe/Vienna"       = "W. Europe Standard Time"
    "Europe/Paris"        = "Romance Standard Time"
    "Europe/Brussels"     = "Romance Standard Time"
    "Europe/Madrid"       = "Romance Standard Time"
    "Europe/Copenhagen"   = "Romance Standard Time"
    "Europe/Helsinki"     = "FLE Standard Time"
    "Europe/Warsaw"       = "Central European Standard Time"
    "Asia/Tokyo"          = "Tokyo Standard Time"
    "Asia/Hong_Kong"      = "China Standard Time"
    "Asia/Shanghai"       = "China Standard Time"
    "Asia/Singapore"      = "Singapore Standard Time"
    "Asia/Kolkata"        = "India Standard Time"
    "Asia/Seoul"          = "Korea Standard Time"
    "Australia/Sydney"    = "AUS Eastern Standard Time"
}

function Get-ExchangeTimeZone {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    if ($script:TzCache.ContainsKey($Name)) { return $script:TzCache[$Name] }
    $tz = $null
    # Windows id from the map first (works in 5.1 and 7 on Windows); the IANA id
    # directly only for zones not in the map (.NET 6+ knows them). v4.0.1: the
    # other order made 5.1 throw - caught, but logged as an error at every start.
    $ids = @()
    if ($script:IanaToWindowsTz.ContainsKey($Name)) { $ids += $script:IanaToWindowsTz[$Name] }
    $ids += $Name
    foreach ($id in $ids) {
        try { $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($id) }
        catch {
            # an unknown id is expected here: keep it out of $Error / widget.log
            $tz = $null
            if ($Error.Count -gt 0) { $Error.RemoveAt(0) }
        }
        if ($null -ne $tz) { break }
    }
    $script:TzCache[$Name] = $tz
    return $tz
}

function Get-TpOffsetAt {
    # UTC offset (seconds) of the exchange at a given moment
    param($Tp, [long]$TsSec)
    if ($null -ne $Tp.Tz) {
        try { return [int]$Tp.Tz.GetUtcOffset([DateTimeOffset]::FromUnixTimeSeconds($TsSec)).TotalSeconds } catch { }
    }
    return [int]$Tp.GmtOffset
}

function Get-TradingPeriodInfo {
    param($Meta)
    if ($null -eq $Meta) { return $null }
    $ctp = $Meta.currentTradingPeriod
    if ($null -eq $ctp -or $null -eq $ctp.regular -or $null -eq $ctp.regular.start -or $null -eq $ctp.regular.end) { return $null }
    $off = if ($null -ne $Meta.gmtoffset) { [int]$Meta.gmtoffset } elseif ($null -ne $ctp.regular.gmtoffset) { [int]$ctp.regular.gmtoffset } else { 0 }
    $regS  = [long]$ctp.regular.start
    $regE  = [long]$ctp.regular.end
    $preS  = if ($null -ne $ctp.pre -and $null -ne $ctp.pre.start -and [long]$ctp.pre.start -gt 0) { [long]$ctp.pre.start } else { $regS }
    $postE = if ($null -ne $ctp.post -and $null -ne $ctp.post.end -and [long]$ctp.post.end -gt 0) { [long]$ctp.post.end } else { $regE }
    $exch  = if ($Meta.fullExchangeName) { [string]$Meta.fullExchangeName } elseif ($Meta.exchangeName) { [string]$Meta.exchangeName } else { "" }
    $is247 = (($regE - $regS) -ge 86000) -or ([string]$Meta.instrumentType -eq "CRYPTOCURRENCY")
    $tzName = [string]$Meta.exchangeTimezoneName
    $tp = @{
        RegStart    = $regS
        RegEnd      = $regE
        PreStart    = $preS
        PostEnd     = $postE
        HasPre      = ($preS -lt $regS)
        HasPost     = ($postE -gt $regE)
        GmtOffset   = $off
        Is247       = $is247
        Exchange    = $exch
        TzName      = $tzName
        Tz          = (Get-ExchangeTimeZone -Name $tzName)
        HolidayCal  = (Get-HolidayCalendarKey -ExchangeCode ([string]$Meta.exchangeName) -TzName $tzName)
    }
    # Local opening/closing time, using the offset valid AT that moment
    $tp.RegStartTod = Get-TodSec -TsSec $regS -Off (Get-TpOffsetAt -Tp $tp -TsSec $regS)
    $tp.RegEndTod   = Get-TodSec -TsSec $regE -Off (Get-TpOffsetAt -Tp $tp -TsSec $regE)
    return $tp
}

function Get-BarSession {
    # "R" = regular session, "PRE" / "POST" = extended hours
    param([long]$TsSec, $Tp)
    if ($null -eq $Tp -or $Tp.Is247 -or -not ($Tp.HasPre -or $Tp.HasPost) -or $Tp.RegStartTod -ge $Tp.RegEndTod) { return "R" }
    $off = if ($null -ne $Tp.Tz) { Get-TpOffsetAt -Tp $Tp -TsSec $TsSec } else { $Tp.GmtOffset }
    $tod = ($TsSec + $off) % 86400
    if ($tod -lt 0) { $tod += 86400 }
    if ($tod -lt $Tp.RegStartTod) { return "PRE" }
    if ($tod -ge $Tp.RegEndTod) { return "POST" }
    return "R"
}

function Test-ExchangeWeekend {
    param([long]$TsSec, [int]$Off)
    $dow = [DateTimeOffset]::FromUnixTimeSeconds($TsSec + $Off).DayOfWeek
    return ($dow -eq [DayOfWeek]::Saturday -or $dow -eq [DayOfWeek]::Sunday)
}

function Get-NextRegularOpen {
    # Same LOCAL opening time on the next trading day (weekends and the known
    # exchange holidays skipped). Stepping by 86400 s alone drifted by an hour
    # across DST switches.
    param($Tp, [long]$NowSec)
    $t = [long]$Tp.RegStart
    $guard = 0
    while (($t -le $NowSec -or (Test-ExchangeWeekend -TsSec $t -Off (Get-TpOffsetAt -Tp $Tp -TsSec $t)) -or (Get-ExchangeHoliday -Tp $Tp -TsSec $t)) -and $guard -lt 21) {
        $offBefore = Get-TpOffsetAt -Tp $Tp -TsSec $t
        $t += 86400
        $t += $offBefore - (Get-TpOffsetAt -Tp $Tp -TsSec $t)
        $guard++
    }
    return $t
}

# ------------------------------------------------------------------------------
# Exchange holiday calendars (v2.9). Rule based (incl. Easter), so they work for
# every year: NYSE/Nasdaq (US), Xetra/Frankfurt (DE), SIX (CH), LSE (UK) and
# Wiener Boerse (AT). Only full closures; early closes come from Yahoo's
# trading period of the day. Weekend dates are irrelevant and not listed.
# ------------------------------------------------------------------------------
$script:HolidayCache = @{}

function Get-EasterSunday {
    # Anonymous Gregorian algorithm (Meeus/Jones/Butcher)
    param([int]$Year)
    $a = $Year % 19
    $b = [math]::Floor($Year / 100)
    $c = $Year % 100
    $d = [math]::Floor($b / 4)
    $e = $b % 4
    $f = [math]::Floor(($b + 8) / 25)
    $g = [math]::Floor(($b - $f + 1) / 3)
    $h = (19 * $a + $b - $d - $g + 15) % 30
    $i = [math]::Floor($c / 4)
    $k = $c % 4
    $l = (32 + 2 * $e + 2 * $i - $h - $k) % 7
    $m = [math]::Floor(($a + 11 * $h + 22 * $l) / 451)
    $month = [math]::Floor(($h + $l - 7 * $m + 114) / 31)
    $day = (($h + $l - 7 * $m + 114) % 31) + 1
    return (New-Object DateTime($Year, [int]$month, [int]$day))
}

function Get-NthWeekday {
    # N-th weekday of a month (N = -1: last one)
    param([int]$Year, [int]$Month, [DayOfWeek]$Day, [int]$N)
    if ($N -gt 0) {
        $d = New-Object DateTime($Year, $Month, 1)
        while ($d.DayOfWeek -ne $Day) { $d = $d.AddDays(1) }
        return $d.AddDays(7 * ($N - 1))
    }
    $d = (New-Object DateTime($Year, $Month, 1)).AddMonths(1).AddDays(-1)
    while ($d.DayOfWeek -ne $Day) { $d = $d.AddDays(-1) }
    return $d
}

function Get-UsObserved {
    # NYSE rule: Saturday -> Friday before, Sunday -> Monday after
    param([DateTime]$D)
    if ($D.DayOfWeek -eq [DayOfWeek]::Saturday) { return $D.AddDays(-1) }
    if ($D.DayOfWeek -eq [DayOfWeek]::Sunday) { return $D.AddDays(1) }
    return $D
}

function Get-HolidayCalendarKey {
    param([string]$ExchangeCode, [string]$TzName)
    $code = ([string]$ExchangeCode).ToUpper()
    if ($code -in @("NMS", "NYQ", "NGM", "NCM", "ASE", "PCX", "BTS", "NAS", "NYS", "PNK", "OQX", "OQB", "CBO")) { return "US" }
    if ($code -in @("GER", "FRA", "STU", "DUS", "MUN", "HAM", "BER", "HAN", "ETR")) { return "DE" }
    if ($code -in @("EBS", "VTX", "SWX")) { return "CH" }
    if ($code -in @("LSE", "IOB")) { return "UK" }
    if ($code -in @("VIE")) { return "AT" }
    switch ([string]$TzName) {
        "America/New_York" { return "US" }
        "Europe/Berlin"    { return "DE" }
        "Europe/Zurich"    { return "CH" }
        "Europe/London"    { return "UK" }
        "Europe/Vienna"    { return "AT" }
    }
    return ""
}

function Get-HolidayMap {
    # yyyy-MM-dd -> name, for one calendar and year (cached)
    param([string]$Cal, [int]$Year)
    $ck = "$Cal|$Year"
    if ($script:HolidayCache.ContainsKey($ck)) { return $script:HolidayCache[$ck] }
    $h = @{}
    $add = { param([DateTime]$D, [string]$Name) if ($D.DayOfWeek -ne [DayOfWeek]::Saturday -and $D.DayOfWeek -ne [DayOfWeek]::Sunday) { $h[$D.ToString("yyyy-MM-dd")] = $Name } }
    $easter = Get-EasterSunday -Year $Year
    $mk = { param([int]$M, [int]$D) New-Object DateTime($Year, $M, $D) }
    switch ($Cal) {
        "US" {
            # New Year on a Saturday is NOT moved to the Friday before (NYSE rule)
            $ny = & $mk 1 1
            if ($ny.DayOfWeek -eq [DayOfWeek]::Sunday) { $ny = $ny.AddDays(1) }
            & $add $ny "Neujahr"
            & $add (Get-NthWeekday $Year 1 ([DayOfWeek]::Monday) 3) "Martin Luther King Day"
            & $add (Get-NthWeekday $Year 2 ([DayOfWeek]::Monday) 3) "Presidents Day"
            & $add $easter.AddDays(-2) "Karfreitag"
            & $add (Get-NthWeekday $Year 5 ([DayOfWeek]::Monday) -1) "Memorial Day"
            if ($Year -ge 2022) { & $add (Get-UsObserved (& $mk 6 19)) "Juneteenth" }
            & $add (Get-UsObserved (& $mk 7 4)) "Independence Day"
            & $add (Get-NthWeekday $Year 9 ([DayOfWeek]::Monday) 1) "Labor Day"
            & $add (Get-NthWeekday $Year 11 ([DayOfWeek]::Thursday) 4) "Thanksgiving"
            & $add (Get-UsObserved (& $mk 12 25)) "Weihnachten"
        }
        "DE" {
            & $add (& $mk 1 1) "Neujahr"
            & $add $easter.AddDays(-2) "Karfreitag"
            & $add $easter.AddDays(1) "Ostermontag"
            & $add (& $mk 5 1) "Tag der Arbeit"
            & $add (& $mk 12 24) "Heiligabend"
            & $add (& $mk 12 25) "1. Weihnachtstag"
            & $add (& $mk 12 26) "2. Weihnachtstag"
            & $add (& $mk 12 31) "Silvester"
        }
        "CH" {
            & $add (& $mk 1 1) "Neujahr"
            & $add (& $mk 1 2) "Berchtoldstag"
            & $add $easter.AddDays(-2) "Karfreitag"
            & $add $easter.AddDays(1) "Ostermontag"
            & $add (& $mk 5 1) "Tag der Arbeit"
            & $add $easter.AddDays(39) "Auffahrt"
            & $add $easter.AddDays(50) "Pfingstmontag"
            & $add (& $mk 8 1) "Bundesfeier"
            & $add (& $mk 12 24) "Heiligabend"
            & $add (& $mk 12 25) "Weihnachten"
            & $add (& $mk 12 26) "Stephanstag"
            & $add (& $mk 12 31) "Silvester"
        }
        "UK" {
            $ny = & $mk 1 1
            if ($ny.DayOfWeek -eq [DayOfWeek]::Saturday) { $ny = $ny.AddDays(2) } elseif ($ny.DayOfWeek -eq [DayOfWeek]::Sunday) { $ny = $ny.AddDays(1) }
            & $add $ny "New Year's Day"
            & $add $easter.AddDays(-2) "Good Friday"
            & $add $easter.AddDays(1) "Easter Monday"
            & $add (Get-NthWeekday $Year 5 ([DayOfWeek]::Monday) 1) "Early May Bank Holiday"
            & $add (Get-NthWeekday $Year 5 ([DayOfWeek]::Monday) -1) "Spring Bank Holiday"
            & $add (Get-NthWeekday $Year 8 ([DayOfWeek]::Monday) -1) "Summer Bank Holiday"
            # Christmas / Boxing Day with substitute days
            $x = & $mk 12 25
            switch ($x.DayOfWeek) {
                ([DayOfWeek]::Friday)   { & $add $x "Christmas Day"; & $add (& $mk 12 28) "Boxing Day (Ersatz)" }
                ([DayOfWeek]::Saturday) { & $add (& $mk 12 27) "Christmas Day (Ersatz)"; & $add (& $mk 12 28) "Boxing Day (Ersatz)" }
                ([DayOfWeek]::Sunday)   { & $add (& $mk 12 26) "Boxing Day"; & $add (& $mk 12 27) "Christmas Day (Ersatz)" }
                default                 { & $add $x "Christmas Day"; & $add (& $mk 12 26) "Boxing Day" }
            }
        }
        "AT" {
            & $add (& $mk 1 1) "Neujahr"
            & $add $easter.AddDays(-2) "Karfreitag"
            & $add $easter.AddDays(1) "Ostermontag"
            & $add (& $mk 5 1) "Staatsfeiertag"
            & $add $easter.AddDays(50) "Pfingstmontag"
            & $add (& $mk 12 24) "Heiligabend"
            & $add (& $mk 12 25) "Christtag"
            & $add (& $mk 12 26) "Stefanitag"
            & $add (& $mk 12 31) "Silvester"
        }
    }
    $script:HolidayCache[$ck] = $h
    return $h
}

function Get-ExchangeLocalDate {
    param($Tp, [long]$TsSec)
    $off = Get-TpOffsetAt -Tp $Tp -TsSec $TsSec
    return [DateTimeOffset]::FromUnixTimeSeconds($TsSec + $off).UtcDateTime.Date
}

function Get-ExchangeHoliday {
    # Name of the holiday at that moment (exchange-local date) or ""
    param($Tp, [long]$TsSec)
    if ($null -eq $Tp -or [string]::IsNullOrEmpty([string]$Tp.HolidayCal)) { return "" }
    $d = Get-ExchangeLocalDate -Tp $Tp -TsSec $TsSec
    $map = Get-HolidayMap -Cal ([string]$Tp.HolidayCal) -Year $d.Year
    $k = $d.ToString("yyyy-MM-dd")
    if ($map.ContainsKey($k)) { return [string]$map[$k] }
    return ""
}

function Get-UpcomingHolidays {
    param($Tp, [long]$NowSec, [int]$Count = 3)
    $out = @()
    if ($null -eq $Tp -or [string]::IsNullOrEmpty([string]$Tp.HolidayCal)) { return $out }
    $today = Get-ExchangeLocalDate -Tp $Tp -TsSec $NowSec
    foreach ($y in @($today.Year, ($today.Year + 1))) {
        $map = Get-HolidayMap -Cal ([string]$Tp.HolidayCal) -Year $y
        foreach ($k in ($map.Keys | Sort-Object)) {
            $d = [DateTime]::ParseExact($k, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
            if ($d -ge $today) { $out += [PSCustomObject]@{ Date = $d; Name = [string]$map[$k] } }
            if ($out.Count -ge $Count) { return $out }
        }
    }
    return $out
}

function Get-MarketState {
    param($Tp, [long]$NowSec)
    if ($null -eq $Tp) { return $null }
    if ($Tp.Is247) { return @{ State = "OPEN24"; Short = "24/7"; NextSec = 0L; Holiday = "" } }
    # Exchange holiday today: closed all day, whatever the trading period says
    $hol = Get-ExchangeHoliday -Tp $Tp -TsSec $NowSec
    if ($hol) {
        return @{ State = "CLOSED"; Short = "Feiertag"; NextSec = (Get-NextRegularOpen -Tp $Tp -NowSec $NowSec); Holiday = $hol }
    }
    if ($NowSec -ge $Tp.RegStart -and $NowSec -lt $Tp.RegEnd) {
        return @{ State = "REGULAR"; Short = "Offen"; NextSec = [long]$Tp.RegEnd; Holiday = "" }
    }
    if ($Tp.HasPre -and $NowSec -ge $Tp.PreStart -and $NowSec -lt $Tp.RegStart) {
        return @{ State = "PRE"; Short = "Pre"; NextSec = [long]$Tp.RegStart; Holiday = "" }
    }
    if ($Tp.HasPost -and $NowSec -ge $Tp.RegEnd -and $NowSec -lt $Tp.PostEnd) {
        return @{ State = "POST"; Short = "Post"; NextSec = [long]$Tp.PostEnd; Holiday = "" }
    }
    $open = if ($NowSec -lt $Tp.RegStart -and -not (Get-ExchangeHoliday -Tp $Tp -TsSec $Tp.RegStart)) { [long]$Tp.RegStart } else { Get-NextRegularOpen -Tp $Tp -NowSec $NowSec }
    return @{ State = "CLOSED"; Short = "Zu"; NextSec = $open; Holiday = "" }
}

function Format-Duration {
    param([long]$Sec)
    if ($Sec -lt 0) { $Sec = 0 }
    $d = [math]::Floor($Sec / 86400)
    $h = [math]::Floor(($Sec % 86400) / 3600)
    $m = [math]::Floor(($Sec % 3600) / 60)
    if ($d -gt 0) { return ("{0}d {1}h" -f $d, $h) }
    if ($h -gt 0) { return ("{0}h {1:00}m" -f $h, $m) }
    if ($m -gt 0) { return ("{0}m {1:00}s" -f $m, ($Sec % 60)) }
    return ("{0}s" -f $Sec)
}

function Format-LocalTime {
    param([long]$TsSec)
    $dt = [DateTimeOffset]::FromUnixTimeSeconds($TsSec).ToLocalTime()
    if ($dt.Date -ne (Get-Date).Date) { return $dt.ToString("ddd HH:mm") }
    return $dt.ToString("HH:mm")
}

function Get-MarketHoursTooltip {
    param($Tp)
    if ($null -eq $Tp) { return "" }
    $hm = { param($s) [DateTimeOffset]::FromUnixTimeSeconds([long]$s).ToLocalTime().ToString("HH:mm") }
    $lines = New-Object System.Collections.Generic.List[string]
    $title = if ($Tp.Exchange) { $Tp.Exchange } else { "Börse" }
    if ($Tp.TzName) { $title += " ($($Tp.TzName))" }
    $lines.Add($title)
    if ($Tp.Is247) {
        $lines.Add("Handel rund um die Uhr")
    } else {
        if ($Tp.HasPre)  { $lines.Add(("Vorbörse:   {0} - {1}" -f (& $hm $Tp.PreStart), (& $hm $Tp.RegStart))) }
        $lines.Add(("Handel:      {0} - {1}" -f (& $hm $Tp.RegStart), (& $hm $Tp.RegEnd)))
        if ($Tp.HasPost) { $lines.Add(("Nachbörse:  {0} - {1}" -f (& $hm $Tp.RegEnd), (& $hm $Tp.PostEnd))) }
        $nowS = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $up = @(Get-UpcomingHolidays -Tp $Tp -NowSec $nowS -Count 3)
        if ($up.Count -gt 0) {
            $lines.Add("Nächste Feiertage ($($Tp.HolidayCal)):")
            foreach ($u in $up) { $lines.Add(("  {0}  {1}" -f $u.Date.ToString("ddd dd.MM.yyyy"), $u.Name)) }
            $lines.Add("(Ortszeit; verkürzte Handelstage nur, wenn Yahoo sie meldet)")
        } else {
            $lines.Add("(Ortszeit; kein Feiertagskalender für diese Börse)")
        }
    }
    return ($lines -join "`r`n")
}

# ------------------------------------------------------------------------------
# Prices, indicators, parsing, formatting
# ------------------------------------------------------------------------------
function Normalize-CurrencyAndPrice {
    param([double]$Price, [string]$RawCurrency)
    # NOTE: case-sensitive compares! PowerShell's -eq ignores case, so
    # "GBP" -eq "GBp" is TRUE and would divide already-normalized prices again.
    if ($RawCurrency -ceq "GBp" -or $RawCurrency -ceq "GBX") {
        return @{ Price = ($Price / 100.0); Currency = "GBP" }
    }
    if ($RawCurrency -ceq "ZAc") {
        return @{ Price = ($Price / 100.0); Currency = "ZAR" }
    }
    if ($RawCurrency -ceq "ILA") {
        return @{ Price = ($Price / 100.0); Currency = "ILS" }
    }
    $c = if ($RawCurrency) { $RawCurrency.ToUpper() } else { "USD" }
    return @{ Price = $Price; Currency = $c }
}

function Get-TimeframeParams {
    param([string]$Tf)
    switch ($Tf) {
        "1d"  { return @{ Interval = "2m";  Range = "1d"  } }
        "5d"  { return @{ Interval = "15m"; Range = "5d"  } }
        "1mo" { return @{ Interval = "1h";  Range = "1mo" } }
        "3mo" { return @{ Interval = "1d";  Range = "3mo" } }
        "6mo" { return @{ Interval = "1d";  Range = "6mo" } }
        "1y"  { return @{ Interval = "1d";  Range = "1y"  } }
        default { return @{ Interval = "2m"; Range = "1d" } }
    }
}

function Compute-Sma {
    param([double[]]$Prices, [int]$Period)
    $n = $Prices.Count
    $sma = New-Object double[] $n
    for ($i = 0; $i -lt $n; $i++) { $sma[$i] = [double]::NaN }
    if ($n -lt $Period -or $Period -lt 1) { return $sma }

    $sum = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $sum += $Prices[$i]
        if ($i -ge $Period) { $sum -= $Prices[$i - $Period] }
        if ($i -ge ($Period - 1)) { $sma[$i] = $sum / [double]$Period }
    }
    return $sma
}

function Compute-BollingerBands {
    param([double[]]$Prices, [int]$Period = 20, [double]$Multiplier = 2.0)
    $n = $Prices.Count
    $upper = New-Object double[] $n
    $lower = New-Object double[] $n
    for ($i = 0; $i -lt $n; $i++) {
        $upper[$i] = [double]::NaN
        $lower[$i] = [double]::NaN
    }
    if ($n -lt $Period -or $Period -lt 2) { return @{ Upper = $upper; Lower = $lower } }

    $sma = Compute-Sma -Prices $Prices -Period $Period
    for ($i = ($Period - 1); $i -lt $n; $i++) {
        $mean = $sma[$i]
        $sqSum = 0.0
        for ($j = ($i - $Period + 1); $j -le $i; $j++) {
            $d = $Prices[$j] - $mean
            $sqSum += ($d * $d)
        }
        $stdDev = [math]::Sqrt($sqSum / [double]$Period)
        $upper[$i] = $mean + ($Multiplier * $stdDev)
        $lower[$i] = $mean - ($Multiplier * $stdDev)
    }
    return @{ Upper = $upper; Lower = $lower }
}

function Get-ExchangeDay {
    # Day number in the exchange's local time (gmtoffset in seconds)
    param([long]$TsMs, [int]$GmtOffsetSec)
    return [long][math]::Floor((($TsMs / 1000.0) + $GmtOffsetSec) / 86400.0)
}

function Compute-Vwap {
    # VWAP is a per-session measure: it restarts at every new trading day
    param([array]$Series, [int]$GmtOffsetSec = 0)
    $n = $Series.Count
    $vwap = New-Object double[] $n
    for ($i = 0; $i -lt $n; $i++) { $vwap[$i] = [double]::NaN }
    if ($n -eq 0) { return $vwap }

    $cumPv = 0.0
    $cumVol = 0.0
    $curDay = [long]::MinValue
    for ($i = 0; $i -lt $n; $i++) {
        $pt = $Series[$i]
        $day = Get-ExchangeDay -TsMs ([long]$pt.Ts) -GmtOffsetSec $GmtOffsetSec
        if ($day -ne $curDay) {
            $curDay = $day
            $cumPv = 0.0
            $cumVol = 0.0
        }
        $vol = [double]$pt.Volume
        # Extended-hours bars don't count (VWAP is a regular-session benchmark)
        if ($vol -gt 0 -and -not $pt.Ext) {
            $typical = ($pt.High + $pt.Low + $pt.Close) / 3.0
            $cumPv += ($typical * $vol)
            $cumVol += $vol
        }
        if ($cumVol -gt 0) {
            $vwap[$i] = $cumPv / $cumVol
        }
    }
    return $vwap
}

function Compute-Rsi {
    param([double[]]$Prices, [int]$Period = 14)
    $count = $Prices.Count
    $rsi = New-Object double[] $count
    for ($i = 0; $i -lt $count; $i++) { $rsi[$i] = [double]::NaN }
    if ($count -lt ($Period + 1) -or $Period -lt 2) { return $rsi }

    $gainSum = 0.0
    $lossSum = 0.0
    for ($i = 1; $i -le $Period; $i++) {
        $diff = $Prices[$i] - $Prices[$i - 1]
        if ($diff -ge 0) { $gainSum += $diff } else { $lossSum += [math]::Abs($diff) }
    }

    $avgGain = $gainSum / [double]$Period
    $avgLoss = $lossSum / [double]$Period
    $rsi[$Period] = if ($avgLoss -eq 0) { 100.0 } else { 100.0 - (100.0 / (1.0 + ($avgGain / $avgLoss))) }

    $smooth = [double]($Period - 1)
    for ($i = ($Period + 1); $i -lt $count; $i++) {
        $diff = $Prices[$i] - $Prices[$i - 1]
        $gain = if ($diff -gt 0) { $diff } else { 0.0 }
        $loss = if ($diff -lt 0) { [math]::Abs($diff) } else { 0.0 }
        $avgGain = (($avgGain * $smooth) + $gain) / [double]$Period
        $avgLoss = (($avgLoss * $smooth) + $loss) / [double]$Period
        $rsi[$i] = if ($avgLoss -eq 0) { 100.0 } else { 100.0 - (100.0 / (1.0 + ($avgGain / $avgLoss))) }
    }
    return $rsi
}

function Get-SessionPrevClose {
    # Previous session close derived from intraday bars: the last valid close
    # whose exchange-local date is before the date of the most recent bar.
    # (meta.chartPreviousClose is the close BEFORE THE REQUESTED RANGE, so for
    #  range=5d it would yield a 5-day change instead of a day change.)
    # Only regular-session bars count (pre/post bars are skipped when $Tp is given).
    param($Result, $Tp = $null)
    if ($null -eq $Result -or $null -eq $Result.timestamp) { return $null }
    if ($null -eq $Result.indicators -or $null -eq $Result.indicators.quote -or @($Result.indicators.quote).Count -eq 0) { return $null }
    $ts  = @($Result.timestamp)
    $cls = @($Result.indicators.quote[0].close)
    if ($ts.Count -lt 2) { return $null }
    $off = if ($null -ne $Result.meta.gmtoffset) { [int]$Result.meta.gmtoffset } else { 0 }

    $lastIdx = -1
    for ($k = $ts.Count - 1; $k -ge 0; $k--) {
        if ($k -lt $cls.Count -and $null -ne $cls[$k] -and (Get-BarSession -TsSec ([long]$ts[$k]) -Tp $Tp) -eq "R") { $lastIdx = $k; break }
    }
    if ($lastIdx -lt 1) { return $null }
    $lastDay = Get-ExchangeDay -TsMs (([long]$ts[$lastIdx]) * 1000) -GmtOffsetSec $off
    for ($k = $lastIdx - 1; $k -ge 0; $k--) {
        if ($null -ne $cls[$k] -and [double]$cls[$k] -gt 0 -and (Get-BarSession -TsSec ([long]$ts[$k]) -Tp $Tp) -eq "R") {
            $d = Get-ExchangeDay -TsMs (([long]$ts[$k]) * 1000) -GmtOffsetSec $off
            if ($d -lt $lastDay) { return [double]$cls[$k] }
        }
    }
    return $null
}

function Get-ArraySlice {
    # Slice that survives PowerShell's array unrolling (also for 0/1 items)
    param($Arr, [int]$A, [int]$B)
    if ($null -eq $Arr) { return ,@() }
    $cnt = @($Arr).Count
    if ($cnt -le $B -or $A -lt 0 -or $B -lt $A) { return ,@() }
    if ($A -eq 0 -and $B -eq ($cnt - 1)) { return ,$Arr }
    return ,@($Arr[$A..$B])
}

function Format-CompactNumber {
    param([double]$V)
    $a = [math]::Abs($V)
    if ($a -ge 1e9) { return ("{0:N2}B" -f ($V / 1e9)) }
    if ($a -ge 1e6) { return ("{0:N2}M" -f ($V / 1e6)) }
    if ($a -ge 1e4) { return ("{0:N1}K" -f ($V / 1e3)) }
    return ("{0:N0}" -f $V)
}

function ConvertTo-InvariantNumberString {
    # Accepts 1234.56 | 1234,56 | 1.234,56 | 1,234.56 | 1'234.56 | 1 234,56 | 1.234.567
    param([string]$Raw)
    $t = $Raw.Trim() -replace "[\s']", ""   # \s also covers non-breaking spaces
    # Currency code / symbol before or after the number (v3.0: also prefixes,
    # Euro and Pound signs; built from char codes so the file stays ASCII)
    $sym = 'EUR|USD|CHF|GBP|\$|' + [char]0x20AC + '|' + [char]0x00A3
    $t = $t -replace "^($sym)", ""
    $t = $t -replace "($sym|%)$", ""
    $lastDot   = $t.LastIndexOf(".")
    $lastComma = $t.LastIndexOf(",")
    if ($lastDot -ge 0 -and $lastComma -ge 0) {
        # Both present: whichever comes last is the decimal separator
        if ($lastComma -gt $lastDot) { $t = $t.Replace(".", "").Replace(",", ".") }
        else { $t = $t.Replace(",", "") }
    } elseif ($lastComma -ge 0) {
        if (($t.Split(",").Count - 1) -gt 1) { $t = $t.Replace(",", "") }   # 1,234,567
        else { $t = $t.Replace(",", ".") }                                   # 1234,56
    } elseif (($t.Split(".").Count - 1) -gt 1) {
        $t = $t.Replace(".", "")                                             # 1.234.567
    }
    return $t
}

function Test-DecimalInput {
    # $true if empty or a valid number; used to give feedback instead of silently using 0
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $true }
    $val = 0.0
    return [double]::TryParse((ConvertTo-InvariantNumberString $Raw), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)
}

function Parse-DecimalInput {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return 0.0 }
    $val = 0.0
    if ([double]::TryParse((ConvertTo-InvariantNumberString $Raw), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
        if ([double]::IsNaN($val) -or [double]::IsInfinity($val)) { return 0.0 }
        return $val
    }
    return 0.0
}

function Get-AlertKind {
    param([string]$Condition)
    if ($Condition -like "Tag%*") { return "PCT" }
    if ($Condition -like "RSI*")  { return "RSI" }
    if ($Condition -like "*SMA") { return "SMA" }
    return "PRICE"
}

function Format-RearmLabel {
    param([int]$Min)
    if ($Min -ge 1440) { return ("{0}T" -f [int]($Min / 1440)) }
    if ($Min -ge 60) { return ("{0}h" -f [int]($Min / 60)) }
    return ("{0}m" -f $Min)
}

# ==============================================================================
# v3.0 additions
# ==============================================================================

# ------------------------------------------------------------------------------
# Lists shared by UI and logic. Functions (not $script: variables) so they are
# available no matter in which order the UI script builds its controls - in
# v2.9 the alert-condition list was defined AFTER the combo box was filled,
# which left the "Bedingung" dropdown empty on every fresh start.
# ------------------------------------------------------------------------------
function Get-DisplayCurrencies {
    return @("EUR", "USD", "CHF", "GBP")
}

function Get-AlertConditions {
    return @(">=", "<=", "Tag% >=", "Tag% <=", "RSI >=", "RSI <=", "> SMA", "< SMA")
}

function Get-NextDisplayCurrency {
    # W key: EUR -> USD -> CHF -> GBP -> EUR (unknown -> first entry)
    param([string]$Current)
    $list = @(Get-DisplayCurrencies)
    $i = [array]::IndexOf($list, ([string]$Current).Trim().ToUpper())
    return $list[($i + 1) % $list.Count]
}

function Get-NormalizedCurrencyCode {
    # ISO code for a stored or Yahoo currency: GBp/GBX -> GBP, ZAc -> ZAR,
    # ILA -> ILS, otherwise upper case. "" if it is not a 3-letter code.
    # (v2.9 silently turned every position currency other than EUR/USD/CHF
    #  into EUR when loading portfolio.json - e.g. GBP positions booked via
    #  the transaction dialog.)
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return "" }
    $t = $Raw.Trim()
    if ($t -ceq "GBp" -or $t -ceq "GBX") { return "GBP" }
    if ($t -ceq "ZAc") { return "ZAR" }
    if ($t -ceq "ILA") { return "ILS" }
    $u = $t.ToUpperInvariant()
    if ($u -cmatch '^[A-Z]{3}$') { return $u }
    return ""
}

# ------------------------------------------------------------------------------
# Yahoo responses (moved here from the UI script so they can be unit-tested)
# ------------------------------------------------------------------------------
function Get-ChartResult {
    param($Json)
    if ($null -ne $Json -and $null -ne $Json.chart -and $null -ne $Json.chart.result -and @($Json.chart.result).Count -gt 0) {
        return $Json.chart.result[0]
    }
    return $null
}

function ConvertFrom-YahooSearch {
    param($Json)
    $items = @()
    if ($null -ne $Json -and $null -ne $Json.quotes) {
        foreach ($q in $Json.quotes) {
            if ($q.symbol -and ($q.quoteType -in @("EQUITY", "ETF", "INDEX", "CRYPTOCURRENCY", "CURRENCY", "MUTUALFUND", "FUTURE"))) {
                $name = if ($q.shortname) { $q.shortname } elseif ($q.longname) { $q.longname } else { $q.symbol }
                $exch = if ($q.exchDisp) { $q.exchDisp } else { $q.exchange }
                $items += [PSCustomObject]@{
                    Symbol    = [string]$q.symbol.ToUpper()
                    Name      = [string]$name
                    Exch      = [string]$exch
                    Display   = ("{0,-10} | {1} ({2})" -f $q.symbol.ToUpper(), $name, $exch)
                    # v4.1: profile data the search delivers without a crumb
                    QuoteType = [string]$q.quoteType
                    Sector    = $(if ($q.sectorDisp) { [string]$q.sectorDisp } else { [string]$q.sector })
                    Industry  = $(if ($q.industryDisp) { [string]$q.industryDisp } else { [string]$q.industry })
                }
            }
        }
    }
    return $items
}

function Select-ResolvedSymbol {
    # What a typed symbol resolves to: the input itself when Yahoo has a price
    # for it, otherwise the first search hit, otherwise the (cleaned) input.
    param([string]$Raw, $ProbeJson, [array]$SearchItems = @())
    $clean = ([string]$Raw).Trim().ToUpper()
    if (-not $clean) { return "" }
    $r = Get-ChartResult $ProbeJson
    if ($null -ne $r -and $null -ne $r.meta -and $null -ne $r.meta.regularMarketPrice -and [double]$r.meta.regularMarketPrice -gt 0) {
        return $clean
    }
    foreach ($h in @($SearchItems)) {
        if ($null -ne $h -and $h.Symbol) { return ([string]$h.Symbol).ToUpper() }
    }
    return $clean
}

# ------------------------------------------------------------------------------
# Transactions: average-cost method. All amounts in the POSITION currency,
# buy fees are capitalised into the cost basis, sell fees reduce the result.
# ------------------------------------------------------------------------------
function Get-BuyResult {
    param([double]$OldShares, [double]$OldAvg, [double]$Shares, [double]$Price, [double]$Fee)
    $newSh = $OldShares + $Shares
    if ($newSh -le 0) { return @{ Shares = 0.0; AvgPrice = 0.0 } }
    $avg = (($OldShares * $OldAvg) + ($Shares * $Price) + $Fee) / $newSh
    return @{ Shares = $newSh; AvgPrice = $avg }
}

function Get-SellResult {
    param([double]$OldShares, [double]$OldAvg, [double]$Shares, [double]$Price, [double]$Fee)
    $realized = (($Price - $OldAvg) * $Shares) - $Fee
    $left = $OldShares - $Shares
    if ($left -le 0.000001) { $left = 0.0 }
    $avg = if ($left -gt 0) { $OldAvg } else { 0.0 }
    return @{ Shares = $left; AvgPrice = $avg; Realized = $realized }
}

function Get-PositionFromTransactions {
    # Replays the buys/sells of one ticker in date order (same date: booking
    # order). Bookings in a different currency than the first one, or with
    # non-positive shares/price, are skipped and counted; a sell larger than
    # the holding is clamped. $null when there is nothing to replay.
    # v4.1: stock splits (Splits: ticker -> @(@{ Date; Ratio })) multiply the
    # holding and divide the average from their ex-date on.
    param([array]$Transactions, [string]$Ticker, [hashtable]$Splits = @{})
    $sym = ([string]$Ticker).Trim().ToUpper()
    $rows = New-Object System.Collections.Generic.List[PSObject]
    $i = 0
    foreach ($tx in @($Transactions)) {
        $i++
        if ($null -eq $tx) { continue }
        if (([string]$tx.Ticker).ToUpper() -ne $sym) { continue }
        if ([string]$tx.Type -notin @("Kauf", "Verkauf")) { continue }
        $rows.Add([PSCustomObject]@{ Date = [string]$tx.Date; Idx = $i; Tx = $tx })
    }
    if ($rows.Count -eq 0) { return $null }
    $ordered = @($rows | Sort-Object -Property @{ Expression = { $_.Date } }, @{ Expression = { $_.Idx } })

    $cur = ""
    $sh = 0.0; $avg = 0.0; $real = 0.0
    $used = 0; $skipped = 0; $clamped = $false
    $spl = @(Get-SplitEvents -Splits $Splits -Ticker $sym)
    $k = 0; $splitN = 0
    foreach ($r in $ordered) {
        $tx = $r.Tx
        while ($k -lt $spl.Count -and [string]::CompareOrdinal([string]$spl[$k].Date, [string]$tx.Date) -le 0) {
            if ($sh -gt 0) { $sh *= [double]$spl[$k].Ratio; $avg /= [double]$spl[$k].Ratio; $splitN++ }
            $k++
        }
        $c = Get-NormalizedCurrencyCode ([string]$tx.Currency)
        if (-not $c) { $c = "EUR" }
        if (-not $cur) { $cur = $c }
        if ($c -ne $cur) { $skipped++; continue }
        $q   = [double]$tx.Shares
        $px  = [double]$tx.Price
        $fee = [double]$tx.Fee
        if ($q -le 0 -or $px -le 0) { $skipped++; continue }
        if ([string]$tx.Type -eq "Kauf") {
            $b = Get-BuyResult -OldShares $sh -OldAvg $avg -Shares $q -Price $px -Fee $fee
            $sh = $b.Shares; $avg = $b.AvgPrice
        } else {
            if ($q -gt ($sh + 0.000001)) { $q = $sh; $clamped = $true }
            if ($q -le 0) { $skipped++; continue }
            $s = Get-SellResult -OldShares $sh -OldAvg $avg -Shares $q -Price $px -Fee $fee
            $sh = $s.Shares; $avg = $s.AvgPrice; $real += $s.Realized
        }
        $used++
    }
    # splits after the last booking change today's holding too
    while ($k -lt $spl.Count) {
        if ($sh -gt 0) { $sh *= [double]$spl[$k].Ratio; $avg /= [double]$spl[$k].Ratio; $splitN++ }
        $k++
    }
    return [PSCustomObject]@{
        Splits   = $splitN
        Ticker   = $sym
        Shares   = $sh
        AvgPrice = $avg
        Currency = $cur
        Realized = $real
        Used     = $used
        Skipped  = $skipped
        Clamped  = $clamped
    }
}

function Find-PositionCurrencyMismatch {
    # Positions whose currency matches NONE of the currencies of their own
    # buys/sells - the trace left by the v2.9 load bug (GBP position -> EUR).
    param([hashtable]$Portfolio, [array]$Transactions)
    $out = @()
    if ($null -eq $Portfolio) { return $out }
    foreach ($sym in @($Portfolio.Keys | Sort-Object)) {
        $u = ([string]$sym).ToUpper()
        $pc = Get-NormalizedCurrencyCode ([string]$Portfolio[$sym].Currency)
        $txc = @(@($Transactions) | Where-Object { $null -ne $_ -and ([string]$_.Ticker).ToUpper() -eq $u -and [string]$_.Type -in @("Kauf", "Verkauf") } |
            ForEach-Object { Get-NormalizedCurrencyCode ([string]$_.Currency) } | Where-Object { $_ } | Sort-Object -Unique)
        if ($txc.Count -gt 0 -and $txc -notcontains $pc) {
            $out += [PSCustomObject]@{ Ticker = $u; PositionCurrency = $pc; TransactionCurrencies = ($txc -join ",") }
        }
    }
    return $out
}

# ------------------------------------------------------------------------------
# CSV
# ------------------------------------------------------------------------------
function ConvertTo-CsvField {
    # One text field for a ';'-separated CSV: quoted when needed, and text that
    # Excel would run as a formula (=, +, -, @ at the start) is neutralised.
    # Use for free text only (notes, names) - not for numbers.
    param([string]$Value, [string]$Delimiter = ";")
    $v = [string]$Value
    if ($v -match '^[=+\-@\t\r]') { $v = "'" + $v }
    if ($v.Contains($Delimiter) -or $v.Contains('"') -or $v.Contains("`n") -or $v.Contains("`r")) {
        $v = '"' + $v.Replace('"', '""') + '"'
    }
    return $v
}

# ==============================================================================
# v4.0 additions
# ==============================================================================

# ------------------------------------------------------------------------------
# Layouts and themes. "Ticker" and "Compact" are the small bars; "Standard" is
# the tabbed window; "Terminal" shows the chart and the lists at the same time.
# ------------------------------------------------------------------------------
function Get-LayoutNames {
    return @("Ticker", "Compact", "Standard", "Terminal")
}

function Get-NextLayout {
    # L key: Ticker -> Compact -> Standard -> Terminal -> Ticker (unknown -> Standard)
    param([string]$Current)
    $list = @(Get-LayoutNames)
    $i = [array]::IndexOf($list, [string]$Current)
    if ($i -lt 0) { return "Standard" }
    return $list[($i + 1) % $list.Count]
}

function Test-CompactLayout {
    # Small bars: no tabs, no views, fixed window size
    param([string]$Layout)
    return ([string]$Layout -in @("Ticker", "Compact"))
}

function Get-ThemeNames {
    return @("Dark", "OLED", "Light", "Terminal")
}

function Get-NextTheme {
    param([string]$Current)
    $list = @(Get-ThemeNames)
    $i = [array]::IndexOf($list, [string]$Current)
    return $list[($i + 1) % $list.Count]
}

function Get-TerminalLayoutRects {
    # Geometry of the Terminal layout: chart on top, the list panels below.
    # Both lists side by side when they fit (PanelMinW each), otherwise only
    # the one picked by ActiveBottom. Rects are @(x, y, w, h); $null = hidden.
    param(
        [int]$X, [int]$Y, [int]$W, [int]$H,
        [double]$ChartPct = 55,
        [bool]$ShowWatch = $true,
        [bool]$ShowPortfolio = $true,
        [string]$ActiveBottom = "Watchlist",
        [int]$PanelMinW = 756,
        [int]$Gap = 8,
        [int]$MinBottomH = 300,
        [int]$MinChartH = 160
    )
    $out = [PSCustomObject]@{ Chart = $null; Watchlist = $null; Portfolio = $null; SideBySide = $false }
    $bottom = New-Object System.Collections.Generic.List[string]
    if ($ShowWatch) { $bottom.Add("Watchlist") }
    if ($ShowPortfolio) { $bottom.Add("Portfolio") }
    if ($bottom.Count -eq 0 -or $H -lt ($MinChartH + $Gap + 40)) {
        $out.Chart = @($X, $Y, $W, $H)
        return $out
    }
    $pct = [math]::Max(20.0, [math]::Min(85.0, $ChartPct))
    $chartH = [int][math]::Round($H * $pct / 100.0)
    $bottomH = $H - $chartH - $Gap
    if ($bottomH -lt $MinBottomH) {
        $bottomH = [math]::Min($MinBottomH, $H - $MinChartH - $Gap)
        $chartH = $H - $bottomH - $Gap
    }
    $out.Chart = @($X, $Y, $W, $chartH)
    $by = $Y + $chartH + $Gap
    if ($bottom.Count -eq 2 -and $W -ge (2 * $PanelMinW + $Gap)) {
        $half = [int][math]::Floor(($W - $Gap) / 2)
        $out.Watchlist = @($X, $by, $half, $bottomH)
        $out.Portfolio = @(($X + $half + $Gap), $by, ($W - $half - $Gap), $bottomH)
        $out.SideBySide = $true
        return $out
    }
    $pick = if ($bottom.Contains([string]$ActiveBottom)) { [string]$ActiveBottom } else { $bottom[0] }
    if ($pick -eq "Watchlist") { $out.Watchlist = @($X, $by, $W, $bottomH) } else { $out.Portfolio = @($X, $by, $W, $bottomH) }
    return $out
}

# ------------------------------------------------------------------------------
# Data freshness
# ------------------------------------------------------------------------------
function Get-StalenessLevel {
    # "OK" / "WARN" (older than 2 refresh intervals, at least 45 s) /
    # "ERR" (offline, or older than 10 intervals, at least 5 min)
    param([double]$AgeSec, [int]$RefreshSec, [bool]$Offline = $false)
    if ($Offline -or [double]::IsNaN($AgeSec) -or $AgeSec -lt 0) { return "ERR" }
    $warn = [math]::Max(45, 2 * $RefreshSec)
    $err  = [math]::Max(300, 10 * $RefreshSec)
    if ($AgeSec -gt $err) { return "ERR" }
    if ($AgeSec -gt $warn) { return "WARN" }
    return "OK"
}

function Test-ResumeGap {
    # A 1-second timer that did not tick for ThresholdSec means the PC slept
    # (or the process was frozen): the data is old, refresh right away.
    param([DateTime]$Last, [DateTime]$Now, [int]$ThresholdSec = 90)
    if ($Last -eq [DateTime]::MinValue) { return $false }
    return (($Now - $Last).TotalSeconds -ge $ThresholdSec)
}

# ------------------------------------------------------------------------------
# Quote cache (start with the last known quotes instead of an empty window).
# ConvertTo-Json writes NaN as a bare token that ConvertFrom-Json rejects, so
# numbers go through these helpers.
# ------------------------------------------------------------------------------
function ConvertTo-JsonSafeNumber {
    param($Value)
    if ($null -eq $Value) { return $null }
    $d = [double]$Value
    if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) { return $null }
    return $d
}

function ConvertFrom-JsonNumber {
    param($Value, [double]$Default = [double]::NaN)
    if ($null -eq $Value) { return $Default }
    try { return [double]$Value } catch { return $Default }
}

function New-MetaLite {
    # The parts of Yahoo's chart meta that Get-TradingPeriodInfo needs
    param($Meta)
    if ($null -eq $Meta) { return $null }
    $seg = {
        param($S)
        if ($null -eq $S) { return $null }
        return [PSCustomObject]@{ start = $S.start; end = $S.end; gmtoffset = $S.gmtoffset }
    }
    $ctp = $Meta.currentTradingPeriod
    $ctpLite = $null
    if ($null -ne $ctp) {
        $ctpLite = [PSCustomObject]@{ pre = (& $seg $ctp.pre); regular = (& $seg $ctp.regular); post = (& $seg $ctp.post) }
    }
    return [PSCustomObject]@{
        gmtoffset            = $Meta.gmtoffset
        exchangeName         = [string]$Meta.exchangeName
        fullExchangeName     = [string]$Meta.fullExchangeName
        exchangeTimezoneName = [string]$Meta.exchangeTimezoneName
        instrumentType       = [string]$Meta.instrumentType
        currentTradingPeriod = $ctpLite
    }
}

function ConvertTo-QuoteCacheEntry {
    param($Quote, $Spark = $null)
    if ($null -eq $Quote) { return $null }
    $sp = @()
    foreach ($v in @($Spark)) { $n = ConvertTo-JsonSafeNumber $v; if ($null -ne $n) { $sp += $n } }
    $upd = if ($Quote.UpdatedAt -is [DateTime]) { $Quote.UpdatedAt.ToString("o") } else { [string]$Quote.UpdatedAt }
    return [PSCustomObject]@{
        Ticker    = [string]$Quote.Ticker
        LongName  = [string]$Quote.LongName
        Price     = (ConvertTo-JsonSafeNumber $Quote.Price)
        PrevClose = (ConvertTo-JsonSafeNumber $Quote.PrevClose)
        ChangePct = (ConvertTo-JsonSafeNumber $Quote.ChangePct)
        Currency  = [string]$Quote.Currency
        High52    = (ConvertTo-JsonSafeNumber $Quote.High52)
        Low52     = (ConvertTo-JsonSafeNumber $Quote.Low52)
        Rsi14     = (ConvertTo-JsonSafeNumber $Quote.Rsi14)
        SmaFastH  = (ConvertTo-JsonSafeNumber $Quote.SmaFastH)
        Meta      = $Quote.Meta
        UpdatedAt = $upd
        Spark     = $sp
    }
}

function ConvertFrom-QuoteCacheEntry {
    # Cache entry -> QuoteStore object (FromCache = $true, no ext-hours quote)
    param($Entry)
    if ($null -eq $Entry -or -not $Entry.Ticker) { return $null }
    $price = ConvertFrom-JsonNumber $Entry.Price 0.0
    if ($price -le 0) { return $null }
    $upd = [DateTime]::MinValue
    [void][DateTime]::TryParse([string]$Entry.UpdatedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$upd)
    $tp = $null
    try { $tp = Get-TradingPeriodInfo -Meta $Entry.Meta } catch { $tp = $null }
    return [PSCustomObject]@{
        Ticker     = ([string]$Entry.Ticker).ToUpper()
        LongName   = if ($Entry.LongName) { [string]$Entry.LongName } else { ([string]$Entry.Ticker).ToUpper() }
        Price      = $price
        PrevClose  = (ConvertFrom-JsonNumber $Entry.PrevClose 0.0)
        ChangePct  = (ConvertFrom-JsonNumber $Entry.ChangePct 0.0)
        Currency   = if ($Entry.Currency) { [string]$Entry.Currency } else { "USD" }
        High52     = (ConvertFrom-JsonNumber $Entry.High52 0.0)
        Low52      = (ConvertFrom-JsonNumber $Entry.Low52 0.0)
        Rsi14      = (ConvertFrom-JsonNumber $Entry.Rsi14)
        SmaFastH   = (ConvertFrom-JsonNumber $Entry.SmaFastH)
        ExtPrice   = 0.0
        ExtPct     = 0.0
        ExtSession = ""
        ExtTs      = 0L
        Tp         = $tp
        Meta       = $Entry.Meta
        UpdatedAt  = $upd
        FromCache  = $true
    }
}

function Get-DataMigrationAction {
    # v4.0 moved the data folder (NvidiaWidgetV2 -> TerminalWidget). The old
    # folder is only copied, never changed, so v3.0 keeps working on it.
    param([bool]$NewHasConfig, [bool]$OldHasConfig)
    if ($NewHasConfig) { return "None" }
    if ($OldHasConfig) { return "CopyFromOld" }
    return "Fresh"
}

function Get-DataFileNames {
    return @("config.json", "portfolio.json", "alerts.json", "transactions.json", "intraday_cache.json", "quote_cache.json", "profiles.json")
}

# ------------------------------------------------------------------------------
# Hover explanations (glossary). Keys are referenced by the UI (Set-Tip -Key)
# and by the chart legend; the test file checks that every key used exists.
# ------------------------------------------------------------------------------
function Get-TooltipModes {
    # Stored value -> label
    return [ordered]@{ "Off" = "Aus"; "Short" = "Kurz"; "Long" = "Ausführlich" }
}

$script:GlossaryCache = $null

function Get-GlossaryEntries {
    # built once (tooltips and the chart legend look terms up all the time)
    if ($null -ne $script:GlossaryCache) { return $script:GlossaryCache }
    $e = New-Object System.Collections.Generic.List[PSObject]
    $add = { param($K, $T, $S, $L) $e.Add([PSCustomObject]@{ Key = $K; Term = $T; Short = $S; Long = $L }) }
    & $add "PRICE" "Kurs" "Letzter Kurs in der Anzeigewährung." "Letzter gehandelter Kurs der regulären Börsensitzung, umgerechnet in die Anzeigewährung (Taste W). Ein Kurs aus Vor- oder Nachbörse steht darunter separat. Doppelklick kopiert den Kurs."
    & $add "DAYCHG" "Tagesänderung" "Veränderung seit dem letzten Schlusskurs." "Veränderung gegenüber dem Schlusskurs des letzten Handelstags, in Prozent und darunter absolut in der Anzeigewährung. Grün = gestiegen, rot = gefallen."
    & $add "EXT" "Vor-/Nachbörse (Pre/Post)" "Handel außerhalb der regulären Börsenzeiten." "Handel vor der Eröffnung (Pre) und nach dem Schluss (Post), bei US-Aktien 4:00-9:30 und 16:00-20:00 New Yorker Zeit. Wenig Umsatz, daher größere Sprünge. Im 1D-Chart grau hinterlegt (Taste E)."
    & $add "MARKET" "Marktstatus" "Offen / Pre / Post / Zu / 24/7 mit Countdown." "Zeigt, ob die Börse des Tickers gerade handelt, und wie lange noch bzw. bis zur nächsten Eröffnung. Feiertage von NYSE/Nasdaq, Xetra, SIX, LSE und Wiener Börse werden berücksichtigt. Maus darüber zeigt die Handelszeiten in deiner Ortszeit."
    & $add "RSI" "RSI (Relative Strength Index)" "Stärke der Anstiege vs. Rückgänge, Skala 0-100." "Vergleicht über N Perioden (Standard 14) die durchschnittlichen Anstiege mit den durchschnittlichen Rückgängen. Über 70 gilt als überkauft, unter 30 als überverkauft. Das sind Hinweise auf eine starke Bewegung, keine Kauf- oder Verkaufssignale. In Watchlist und Alarmen auf Stundenbasis."
    & $add "SMA" "SMA (gleitender Durchschnitt)" "Durchschnitt der letzten N Schlusskurse." "Simple Moving Average: Mittelwert der letzten N Schlusskurse. Die schnelle Linie (z. B. 20) reagiert früher, die langsame (z. B. 50) zeigt den übergeordneten Trend. Kreuzt der Kurs die Linie, dreht oft das kurzfristige Bild. Perioden in den Einstellungen (Taste M)."
    & $add "VWAP" "VWAP" "Volumengewichteter Durchschnittskurs des Tages." "Volume Weighted Average Price: Durchschnittskurs aller Umsätze des Tages, gewichtet mit dem Volumen. Startet jeden Handelstag neu und zählt nur die reguläre Sitzung. Liegt der Kurs darüber, liegen die meisten heutigen Käufer im Plus. Nur in 1D und 5D (Taste A)."
    & $add "BB" "Bollinger-Bänder" "SMA plus/minus 2 Standardabweichungen." "Ein Band um den schnellen SMA im Abstand von zwei Standardabweichungen. Breite Bänder = hohe Schwankung, enge Bänder = ruhiger Markt, oft vor einer größeren Bewegung. Ein Kurs am Band ist extrem im Verhältnis zur jüngsten Schwankung (Taste B)."
    & $add "VOL" "Volumen" "Gehandelte Stück je Kerze." "Anzahl gehandelter Stück pro Kerze, unten im Chart. Grün = die Kerze schloss höher als sie eröffnete, rot = tiefer. Hohes Volumen bestätigt eine Bewegung, niedriges macht sie weniger aussagekräftig (Taste V)."
    & $add "CANDLE" "Kerzenchart" "Eröffnung, Hoch, Tief und Schluss je Periode." "Jede Kerze zeigt Eröffnung, Hoch, Tief und Schluss (OHLC) einer Periode. Grüner Körper = Schluss über Eröffnung, roter = darunter. Die dünnen Dochte reichen bis zum Hoch und Tief (Taste K)."
    & $add "TF" "Zeitraum" "1D bis 1Y; bestimmt die Kerzengröße." "1D: 2-Minuten-Kerzen, 5D: 15 Minuten, 1M: Stunden, 3M bis 1Y: Tage. Tasten 1-6 oder Mausrad über dem Chart wechseln den Zeitraum."
    & $add "PREVCLOSE" "Vortagesschluss" "Gestrichelte Linie im 1D-Chart." "Schlusskurs des letzten Handelstags. Die Tagesänderung bezieht sich auf diese Linie."
    & $add "RANGE" "Zeitraum-Badge" "Tief/Hoch und Veränderung im sichtbaren Bereich." "L = tiefster, H = höchster Kurs im sichtbaren Bereich. Dahinter die Veränderung seit dessen Beginn, im 1D-Chart seit dem Vortagesschluss."
    & $add "COMPARE" "Vergleich" "Zweiter Ticker als %-Linie." "Ein zweiter Ticker (z. B. ein Index) als Prozentlinie, auf den ersten sichtbaren Kurs normiert. So siehst du, ob sich dein Wert besser oder schlechter entwickelt hat (Taste X)."
    & $add "LEVELS" "EK- und Alarmlinien" "Dein Einstandskurs und Preisalarme im Chart." "Einstandskurs (EK) der Position und Preisalarme als waagrechte Linien. Liegen sie außerhalb des sichtbaren Bereichs, zeigt ein Pfeil am Rand die Richtung. Rechtsklick in den Chart legt einen Alarm auf diesem Kurs an."
    & $add "ZOOM" "Zoom" "Strg+Rad zoomt, Umschalt+Rad verschiebt, Z = alles." "Strg + Mausrad zoomt um die Mausposition, Umschalt + Mausrad verschiebt den Ausschnitt, Z setzt zurück. Indikatoren werden auf der ganzen Reihe gerechnet und bleiben korrekt."
    & $add "MEASURE" "Messen" "Linke Maustaste ziehen misst eine Strecke." "Mit gedrückter linker Maustaste von einem Punkt zum anderen ziehen: zeigt Differenz, Prozent, Anzahl Kerzen und Dauer. Esc löscht die Messung."
    & $add "EK" "Einstandskurs (EK)" "Durchschnittlicher Kaufpreis je Stück." "Durchschnittlicher Kaufpreis je Stück inklusive Kaufgebühren (Durchschnittskostenmethode). Ein Nachkauf verschiebt den EK, ein Verkauf ändert ihn nicht."
    & $add "PNL" "G/V gesamt" "Gewinn/Verlust der offenen Position." "(Kurs - EK) x Stück, in der Anzeigewährung. Das ist ein Buchgewinn bzw. -verlust: erst ein Verkauf macht ihn real."
    & $add "WEIGHT" "Anteil" "Gewicht der Position am Depotwert." "Wert der Position geteilt durch den Depotwert. Hohe Anteile einzelner Werte bedeuten ein Klumpenrisiko."
    & $add "DAYPCT" "Tag %" "Tagesänderung des Kurses." "Kursänderung seit dem letzten Schlusskurs in Prozent."
    & $add "REALIZED" "Realisiert" "Gewinn/Verlust aus Verkäufen und Dividenden." "Verkäufe: (Verkaufskurs - EK) x Stück - Gebühren. Dividenden: Betrag nach Gebühren/Quellensteuer. Die Summe im Depot ist zum aktuellen Wechselkurs umgerechnet; der Jahresreport rechnet mit dem Kurs am Buchungstag."
    & $add "NACHKAUF" "Nachkauf-Simulation" "Was ein Nachkauf mit deinem EK macht." "Gib einen Betrag ein: du siehst, wie viele Stück du zum aktuellen Kurs bekommst und wie sich dein durchschnittlicher Einstandskurs ändert."
    & $add "TARGETEK" "Ziel-EK" "Kapital, das für einen gewünschten EK nötig wäre." "Gib einen gewünschten neuen Einstandskurs ein: du siehst, wie viel Kapital du zum aktuellen Kurs nachkaufen müsstest. Geht nur, wenn der Ziel-EK zwischen aktuellem EK und Kurs liegt."
    & $add "SPARK" "5-Tage-Trend" "Verlauf der letzten 5 Tage." "Mini-Chart aus Stundenkursen der letzten 5 Handelstage, nur reguläre Sitzung. Grün = höher als vor 5 Tagen."
    & $add "HIGH52" "52W-H" "Abstand zum 52-Wochen-Hoch." "Wie weit der Kurs unter dem höchsten Kurs der letzten 52 Wochen liegt. -20 % heißt: 20 % unter dem Jahreshoch."
    & $add "ALERTCOND" "Alarm-Bedingung" "Wann der Alarm auslöst." "Kurs >= / <=: Kurs in Anzeigewährung. Tag% >= / <=: Tagesänderung in %. RSI >= / <=: RSI auf Stundenbasis. > SMA / < SMA: Kurs kreuzt den schnellen SMA (Stundenbasis), kein Wert nötig."
    & $add "REARM" "Wieder scharf (Re-Arm)" "Alarm nach einer Wartezeit erneut aktivieren." "Einmalig: der Alarm bleibt nach dem Auslösen aus. R 15m bis R 1T: der Alarm wird wieder scharf, sobald die Wartezeit um ist UND die Bedingung nicht mehr erfüllt ist, damit er nicht bei jeder Aktualisierung erneut auslöst."
    & $add "FX" "Wechselkurse" "Umrechnung über die EUR-Kurse von Yahoo." "Alle Beträge werden über EUR-Kurse von Yahoo (z. B. EURUSD=X) umgerechnet. 'Fallback' bedeutet: es gibt noch keinen Live-Kurs, ein fester Ersatzkurs wird verwendet und die Werte sind ungenau."
    & $add "STAND" "Stand" "Zeit der letzten erfolgreichen Aktualisierung." "Uhrzeit der letzten erfolgreichen Datenabfrage. Gelb = älter als zwei Intervalle, rot = offline oder sehr alt."
    & $add "CACHE" "Kurs aus dem Cache" "Beim Start gespeicherter Kurs, noch nicht aktuell." "Damit das Fenster nicht leer startet, werden die zuletzt bekannten Kurse angezeigt (grau). Sie werden beim ersten erfolgreichen Abruf ersetzt."
    & $add "REFRESH" "Aktualisierung" "Wie oft Kurse geladen werden." "Intervall für den aktiven Ticker, Portfolio und aktive Alarme. Ticker, die nur in der Watchlist stehen, und Wechselkurse werden seltener geladen (Einstellungen)."
    & $add "LAYOUT" "Layout" "Ticker, Compact, Standard oder Terminal." "Ticker: nur Kurs und Mini-Chart, rahmenlos. Compact: Leiste mit Marktstatus und Laufband. Standard: Fenster mit Tabs Chart / Portfolio / Watch & Alarm. Terminal: Chart oben, Watchlist und Portfolio gleichzeitig darunter. Taste L wechselt, C springt zwischen Compact und dem großen Layout."
    & $add "THEME" "Theme" "Farbschema: Dark, OLED, Light, Terminal." "Dark, OLED (schwarz für OLED-Bildschirme), Light und Terminal (Bernstein auf Schwarz). Taste T wechselt."
    & $add "PIN" "Immer im Vordergrund" "Fenster bleibt über anderen Fenstern." "Das Widget bleibt über allen anderen Fenstern sichtbar."
    & $add "TX" "Transaktion" "Kauf, Verkauf oder Dividende buchen." "Kauf erhöht den Bestand und verschiebt den EK (inkl. Gebühren). Verkauf verringert ihn und speichert den realisierten G/V. Dividende speichert den Betrag nach Abzügen."
    & $add "REPORT" "Jahresreport" "Realisierte G/V und Dividenden eines Jahres." "Realisierte Gewinne, Verluste und Dividenden eines Jahres in einer Basiswährung, jeweils mit dem Wechselkurs am Buchungstag. Der EK wird in der Basiswährung als gleitender Durchschnitt geführt. Hilfsrechnung für die Steuererklärung, keine Steuerberatung."
    & $add "REBUILD" "Position neu berechnen" "Bestand und EK aus den Buchungen neu rechnen." "Spielt alle Käufe und Verkäufe eines Tickers in Datumsreihenfolge nach (Durchschnittskosten) und ersetzt danach Bestand und EK, mit Vorschau."
    & $add "RATELIMIT" "Rate-Limit" "Yahoo bremst bei zu vielen Abfragen." "Bei zu vielen Anfragen antwortet Yahoo mit HTTP 429. Das Widget pausiert dann automatisch und versucht es später wieder."
    & $add "OPACITY" "Deckkraft" "Durchsichtigkeit des Fensters." "100 % = undurchsichtig. Niedrigere Werte lassen das Widget über anderen Fenstern durchscheinen."
    & $add "TOOLTIPS" "Erklärungen" "Wie ausführlich die Hinweise beim Darüberfahren sind." "Aus: keine Hinweise. Kurz: eine Zeile. Ausführlich: mit Erklärung des Begriffs. Die Verzögerung bestimmt, wie lange die Maus stillstehen muss. Taste G öffnet das Glossar."
    & $add "HOLIDAY" "Börsenfeiertag" "An diesem Tag wird nicht gehandelt." "Regelbasierte Feiertagskalender (inkl. Ostern) für NYSE/Nasdaq, Xetra, SIX, LSE und Wiener Börse. Verkürzte Handelstage kommen von Yahoo."
    & $add "BACKUP" "Backup" "Kopie deiner Daten." "Kopie von Einstellungen, Portfolio, Alarmen und Transaktionen im Datenordner unter backups. Die letzten 10 werden behalten."
    # v4.1: portfolio analytics
    & $add "XIRR" "Rendite p.a. (XIRR)" "Geldgewichtete Jahresrendite deiner Ein- und Auszahlungen." "Interner Zinsfuß: die Jahresrendite, die alle Käufe (Auszahlungen), Verkäufe und Dividenden (Einzahlungen) plus den heutigen Wert genau ausgleicht. Berücksichtigt, wann wie viel Geld investiert war. Bei weniger als 30 Tagen Haltedauer nicht aussagekräftig und daher ausgeblendet."
    & $add "NETINVEST" "Netto investiert" "Käufe minus Verkaufserlöse, zum Kurs am Buchungstag." "Summe aller Käufe inklusive Gebühren minus aller Verkaufserlöse, jeweils mit dem Wechselkurs am Buchungstag in die Basiswährung umgerechnet. Liegt die Wertkurve darüber, bist du insgesamt im Plus."
    & $add "BENCHMARK" "Benchmark (Schattendepot)" "Was dein Geld im Vergleichsindex gemacht hätte." "Jeder Kauf und Verkauf deines Depots wird zum selben Tag mit demselben Betrag im Vergleichs-ETF (Standard: iShares Core MSCI World, EUNL.DE) nachgespielt. So vergleichst du fair: gleiche Beträge, gleiche Zeitpunkte. Thesaurierende ETFs enthalten ihre Ausschüttungen im Kurs."
    & $add "UNREALIZED" "Unrealisiert" "Buchgewinn/-verlust der offenen Stücke." "Heutiger Wert minus Einstand der noch gehaltenen Stücke, beides in der Basiswährung. Der Einstand ist der gleitende Durchschnitt zum Wechselkurs am Kauftag, Währungsgewinne sind also enthalten."
    & $add "TOTALRET" "Gesamtergebnis" "Unrealisiert + realisiert + Dividenden." "Alles, was die Position bisher gebracht hat: Buchgewinn der offenen Stücke, realisierte Gewinne/Verluste aus Verkäufen und Dividenden nach Abzügen. Die Prozentzahl bezieht sich auf alle Käufe (inkl. Gebühren)."
    & $add "ALLOCATION" "Aufteilung" "Wie sich dein Depotwert verteilt." "Depotwert nach Position, Währung, Sektor oder Land. Sektor und Land kommen von Yahoo und lassen sich je Position überschreiben (Spalten rechts). ETFs und Fonds werden als eigene Gruppe gezählt, weil sie selbst gestreut sind."
    & $add "CONCENTRATION" "Klumpenrisiko" "Zu großer Anteil in einer Gruppe." "Eine Gruppe (eine Aktie, eine Währung, ein Sektor, ein Land) hat mehr Anteil am Depot als die eingestellte Schwelle (Standard 20 %). Kein Fehler, aber ein Hinweis: ein Rückschlag dort trifft das ganze Depot stark."
    & $add "SPLIT" "Aktiensplit" "Mehr Stück zum geringeren Kurs, Wert unverändert." "Bei einem Split (z. B. NVIDIA 10:1 im Juni 2024) wird jede Aktie in mehrere geteilt. Historische Kurse von Yahoo sind bereits angepasst; Buchungen vor dem Split rechnet das Widget automatisch mit dem Split-Verhältnis um."
    $script:GlossaryCache = $e.ToArray()
    return $script:GlossaryCache
}

function Get-GlossaryEntry {
    param([string]$Key)
    foreach ($g in (Get-GlossaryEntries)) { if ($g.Key -eq $Key) { return $g } }
    return $null
}

function Get-TooltipText {
    # Text for a control tooltip. Off: "". Short: the control's own text (or
    # the term's short explanation). Long: plus the full explanation.
    param([string]$Text, [string]$Key, [string]$Mode = "Short")
    if ($Mode -eq "Off") { return "" }
    $g = if ($Key) { Get-GlossaryEntry $Key } else { $null }
    if ($Mode -eq "Long" -and $null -ne $g) {
        $head = if ($Text) { $Text + "`r`n`r`n" } else { "" }
        return ($head + $g.Term + ": " + $g.Long)
    }
    if ($Text) { return $Text }
    if ($null -ne $g) { return ($g.Term + ": " + $g.Short) }
    return ""
}

# ------------------------------------------------------------------------------
# Yearly report (v4.0): realized gains/losses and dividends of one year in a
# base currency, each booking converted at the FX rate of its own date. The
# cost basis is kept in the base currency as a moving average, so currency
# gains on the position are part of the result.
# History: currency -> @{ Dates = string[] (yyyy-MM-dd, ascending); Rates = double[] }
# with Rates = units of that currency per 1 EUR (Yahoo EURxxx=X).
# ------------------------------------------------------------------------------
function ConvertFrom-YahooFxHistory {
    param($Json)
    $r = Get-ChartResult $Json
    if ($null -eq $r -or $null -eq $r.timestamp -or $null -eq $r.indicators) { return $null }
    $off = if ($null -ne $r.meta -and $null -ne $r.meta.gmtoffset) { [int]$r.meta.gmtoffset } else { 0 }
    $ts = @($r.timestamp)
    $cl = @($r.indicators.quote[0].close)
    $map = New-Object 'System.Collections.Generic.SortedDictionary[string,double]' ([System.StringComparer]::Ordinal)
    $n = [math]::Min($ts.Count, $cl.Count)
    for ($i = 0; $i -lt $n; $i++) {
        if ($null -eq $cl[$i] -or [double]$cl[$i] -le 0) { continue }
        $d = [DateTimeOffset]::FromUnixTimeSeconds([long]$ts[$i] + $off).UtcDateTime.ToString("yyyy-MM-dd")
        $map[$d] = [double]$cl[$i]
    }
    if ($map.Count -eq 0) { return $null }
    $dates = New-Object string[] $map.Count
    $rates = New-Object double[] $map.Count
    $k = 0
    foreach ($kv in $map.GetEnumerator()) { $dates[$k] = $kv.Key; $rates[$k] = $kv.Value; $k++ }
    return @{ Dates = $dates; Rates = $rates }
}

function Get-FxRateOnDate {
    # EUR -> Currency rate valid on Date: the last rate on or before it
    # (weekends/holidays use the previous trading day), else the first one
    # after it. NaN when there is no history for the currency.
    param([hashtable]$History, [string]$Currency, [string]$Date)
    $c = Get-NormalizedCurrencyCode $Currency
    if ($c -eq "EUR") { return 1.0 }
    if ($null -eq $History -or -not $History.ContainsKey($c)) { return [double]::NaN }
    $h = $History[$c]
    # (no @() copy: this runs for every booking and every chart point)
    $dates = $h.Dates
    $rates = $h.Rates
    if ($null -eq $dates -or $dates.Count -eq 0) { return [double]::NaN }
    $lo = 0; $hi = $dates.Count - 1; $found = -1
    while ($lo -le $hi) {
        $mid = [int][math]::Floor(($lo + $hi) / 2)
        if ([string]::CompareOrdinal([string]$dates[$mid], $Date) -le 0) { $found = $mid; $lo = $mid + 1 } else { $hi = $mid - 1 }
    }
    if ($found -lt 0) { $found = 0 }
    return [double]$rates[$found]
}

function Convert-AmountOnDate {
    # Amount in From -> To at the rates of Date. Missing history: the
    # fallback rate (today's) is used and Approx is set.
    param([double]$Amount, [string]$From, [string]$To, [string]$Date, [hashtable]$History, [hashtable]$FallbackFromEur = @{})
    $approx = $false
    $rates = @()
    foreach ($c in @($From, $To)) {
        $r = Get-FxRateOnDate -History $History -Currency $c -Date $Date
        if ([double]::IsNaN($r)) {
            $approx = $true
            $nc = Get-NormalizedCurrencyCode $c
            $r = if ($null -ne $FallbackFromEur -and $FallbackFromEur.ContainsKey($nc) -and [double]$FallbackFromEur[$nc] -gt 0) { [double]$FallbackFromEur[$nc] } else { 1.0 }
        }
        $rates += $r
    }
    return @{ Value = (($Amount / $rates[0]) * $rates[1]); Approx = $approx }
}

function Get-RealizedReport {
    param(
        [array]$Transactions,
        [int]$Year,
        [string]$Base = "EUR",
        [hashtable]$History = @{},
        [hashtable]$FallbackFromEur = @{},
        [hashtable]$Splits = @{}
    )
    $base = Get-NormalizedCurrencyCode $Base
    if (-not $base) { $base = "EUR" }
    $yearEnd = "{0}-12-31" -f $Year
    $yearKey = [string]$Year
    $rows = New-Object System.Collections.Generic.List[PSObject]
    $warn = New-Object System.Collections.Generic.List[string]

    # Group by ticker, keep booking order for the same date
    $groups = @{}
    $i = 0
    foreach ($tx in @($Transactions)) {
        $i++
        if ($null -eq $tx -or -not $tx.Ticker) { continue }
        if ([string]$tx.Type -notin @("Kauf", "Verkauf", "Dividende")) { continue }
        $sym = ([string]$tx.Ticker).ToUpper()
        if (-not $groups.ContainsKey($sym)) { $groups[$sym] = New-Object System.Collections.Generic.List[PSObject] }
        $groups[$sym].Add([PSCustomObject]@{ Date = [string]$tx.Date; Idx = $i; Tx = $tx })
    }

    foreach ($sym in @($groups.Keys | Sort-Object)) {
        $ordered = @($groups[$sym] | Sort-Object -Property @{ Expression = { $_.Date } }, @{ Expression = { $_.Idx } })
        $sh = 0.0
        $cost = 0.0
        $posApprox = $false
        # v4.1: stock splits multiply the holding (the cost stays the same)
        $spl = @(Get-SplitEvents -Splits $Splits -Ticker $sym)
        $k = 0
        foreach ($o in $ordered) {
            $tx = $o.Tx
            $date = [string]$tx.Date
            if ([string]::CompareOrdinal($date, $yearEnd) -gt 0) { break }
            while ($k -lt $spl.Count -and [string]::CompareOrdinal([string]$spl[$k].Date, $date) -le 0) {
                if ($sh -gt 0) { $sh *= [double]$spl[$k].Ratio }
                $k++
            }
            $inYear = $date.StartsWith($yearKey)
            $cur = Get-NormalizedCurrencyCode ([string]$tx.Currency)
            if (-not $cur) { $cur = "EUR" }
            $q = [double]$tx.Shares
            $px = [double]$tx.Price
            $fee = [double]$tx.Fee
            switch ([string]$tx.Type) {
                "Kauf" {
                    if ($q -le 0 -or $px -le 0) { continue }
                    $cv = Convert-AmountOnDate -Amount (($q * $px) + $fee) -From $cur -To $base -Date $date -History $History -FallbackFromEur $FallbackFromEur
                    $cost += $cv.Value
                    $sh += $q
                    if ($cv.Approx) { $posApprox = $true }
                }
                "Verkauf" {
                    if ($q -le 0 -or $px -le 0) { continue }
                    if ($q -gt ($sh + 0.000001)) {
                        if ($inYear) { $warn.Add(("{0} {1}: Verkauf von {2:N4} Stück, Bestand laut Buchungen nur {3:N4} - begrenzt" -f $date, $sym, $q, $sh)) }
                        $q = $sh
                    }
                    if ($q -le 0) { continue }
                    $avg = $cost / $sh
                    $costPart = $avg * $q
                    $pr = Convert-AmountOnDate -Amount ($q * $px) -From $cur -To $base -Date $date -History $History -FallbackFromEur $FallbackFromEur
                    $fe = Convert-AmountOnDate -Amount $fee -From $cur -To $base -Date $date -History $History -FallbackFromEur $FallbackFromEur
                    $res = $pr.Value - $costPart - $fe.Value
                    $cost -= $costPart
                    $sh -= $q
                    if ($sh -le 0.000001) { $sh = 0.0; $cost = 0.0 }
                    if ($inYear) {
                        $rows.Add([PSCustomObject]@{
                            Date = $date; Ticker = $sym; Type = "Verkauf"; Shares = $q; Currency = $cur
                            Amount = ($q * $px); Proceeds = $pr.Value; Cost = $costPart; Fee = $fe.Value; Result = $res
                            Approx = ($pr.Approx -or $fe.Approx -or $posApprox)
                        })
                    }
                    if ($sh -eq 0.0) { $posApprox = $false }
                }
                "Dividende" {
                    if (-not $inYear -or $px -le 0) { continue }
                    $gr = Convert-AmountOnDate -Amount $px -From $cur -To $base -Date $date -History $History -FallbackFromEur $FallbackFromEur
                    $fe = Convert-AmountOnDate -Amount $fee -From $cur -To $base -Date $date -History $History -FallbackFromEur $FallbackFromEur
                    $rows.Add([PSCustomObject]@{
                        Date = $date; Ticker = $sym; Type = "Dividende"; Shares = $q; Currency = $cur
                        Amount = $px; Proceeds = $gr.Value; Cost = 0.0; Fee = $fe.Value; Result = ($gr.Value - $fe.Value)
                        Approx = ($gr.Approx -or $fe.Approx)
                    })
                }
            }
        }
    }

    $sorted = @($rows | Sort-Object -Property Date, Ticker)
    $gains = 0.0; $losses = 0.0; $divG = 0.0; $divF = 0.0; $sellF = 0.0; $approxN = 0
    foreach ($r in $sorted) {
        if ($r.Approx) { $approxN++ }
        if ($r.Type -eq "Verkauf") {
            if ($r.Result -ge 0) { $gains += $r.Result } else { $losses += $r.Result }
            $sellF += $r.Fee
        } else {
            $divG += $r.Proceeds
            $divF += $r.Fee
        }
    }
    if ($approxN -gt 0) { $warn.Add(("{0} Zeile(n) mit aktuellem statt historischem Wechselkurs (Kursverlauf fehlte) - mit ~ markiert" -f $approxN)) }
    return [PSCustomObject]@{
        Year     = $Year
        Base     = $base
        Rows     = $sorted
        Totals   = [PSCustomObject]@{
            Gains          = $gains
            Losses         = $losses
            SellNet        = ($gains + $losses)
            SellFees       = $sellF
            DividendsGross = $divG
            DividendFees   = $divF
            DividendsNet   = ($divG - $divF)
            Net            = ($gains + $losses + $divG - $divF)
        }
        Warnings = $warn.ToArray()
    }
}

function Get-ReportCurrencies {
    # Currencies (other than EUR) whose FX history the report needs
    param([array]$Transactions, [int]$Year, [string]$Base = "EUR")
    $set = New-Object System.Collections.Generic.HashSet[string]
    $yearEnd = "{0}-12-31" -f $Year
    foreach ($tx in @($Transactions)) {
        if ($null -eq $tx -or [string]$tx.Type -notin @("Kauf", "Verkauf", "Dividende")) { continue }
        if ([string]::CompareOrdinal([string]$tx.Date, $yearEnd) -gt 0) { continue }
        $c = Get-NormalizedCurrencyCode ([string]$tx.Currency)
        if ($c -and $c -ne "EUR") { [void]$set.Add($c) }
    }
    $b = Get-NormalizedCurrencyCode $Base
    if ($b -and $b -ne "EUR") { [void]$set.Add($b) }
    return @($set | Sort-Object)
}

function Get-EarliestBookingDate {
    param([array]$Transactions)
    $min = ""
    foreach ($tx in @($Transactions)) {
        $d = [string]$tx.Date
        if ($d -match '^\d{4}-\d{2}-\d{2}' -and (-not $min -or [string]::CompareOrdinal($d, $min) -lt 0)) { $min = $d.Substring(0, 10) }
    }
    return $min
}
# ==============================================================================
# v4.1 additions: portfolio analytics
# ==============================================================================

# ------------------------------------------------------------------------------
# Daily history, splits, aligned series
# ------------------------------------------------------------------------------
function Get-SplitEvents {
    # Splits of one ticker, sorted by date: @(@{ Date = "yyyy-MM-dd"; Ratio = 10.0 })
    param([hashtable]$Splits, [string]$Ticker)
    if ($null -eq $Splits) { return @() }
    $u = ([string]$Ticker).ToUpper()
    if (-not $Splits.ContainsKey($u)) { return @() }
    return @(@($Splits[$u]) | Where-Object { $null -ne $_ -and [double]$_.Ratio -gt 0 } | Sort-Object -Property @{ Expression = { [string]$_.Date } })
}

function ConvertFrom-YahooDailyHistory {
    # Yahoo chart JSON (interval=1d, events=div|split) ->
    #   @{ Dates; Closes; Currency; Splits = @(@{Date;Ratio}); Dividends = @(@{Date;Amount}) }
    # Pence quotes (GBp/GBX, ZAc, ILA) are converted to the main unit. Closes
    # are split-adjusted by Yahoo; booked share counts are adjusted with Splits.
    param($Json)
    $r = Get-ChartResult $Json
    if ($null -eq $r -or $null -eq $r.timestamp -or $null -eq $r.indicators) { return $null }
    $off = if ($null -ne $r.meta -and $null -ne $r.meta.gmtoffset) { [int]$r.meta.gmtoffset } else { 0 }
    $raw = if ($null -ne $r.meta) { [string]$r.meta.currency } else { "" }
    $unit = Normalize-CurrencyAndPrice -Price 1.0 -RawCurrency $raw
    $factor = [double]$unit.Price
    $cur = Get-NormalizedCurrencyCode ([string]$unit.Currency)
    if (-not $cur) { $cur = "USD" }
    $toDate = { param($T) [DateTimeOffset]::FromUnixTimeSeconds([long]$T + $off).UtcDateTime.ToString("yyyy-MM-dd") }

    $ts = @($r.timestamp)
    $cl = @($r.indicators.quote[0].close)
    $map = New-Object 'System.Collections.Generic.SortedDictionary[string,double]' ([System.StringComparer]::Ordinal)
    $n = [math]::Min($ts.Count, $cl.Count)
    for ($i = 0; $i -lt $n; $i++) {
        if ($null -eq $cl[$i] -or [double]$cl[$i] -le 0) { continue }
        $map[(& $toDate $ts[$i])] = [double]$cl[$i] * $factor
    }
    if ($map.Count -eq 0) { return $null }
    $dates = New-Object string[] $map.Count
    $closes = New-Object double[] $map.Count
    $k = 0
    foreach ($kv in $map.GetEnumerator()) { $dates[$k] = $kv.Key; $closes[$k] = $kv.Value; $k++ }

    $splits = @()
    $divs = @()
    if ($null -ne $r.events) {
        if ($null -ne $r.events.splits) {
            foreach ($prop in $r.events.splits.PSObject.Properties) {
                $e = $prop.Value
                $num = [double]$e.numerator; $den = [double]$e.denominator
                if ($num -gt 0 -and $den -gt 0 -and $num -ne $den) {
                    $splits += [PSCustomObject]@{ Date = (& $toDate $e.date); Ratio = ($num / $den) }
                }
            }
        }
        if ($null -ne $r.events.dividends) {
            foreach ($prop in $r.events.dividends.PSObject.Properties) {
                $e = $prop.Value
                if ([double]$e.amount -gt 0) { $divs += [PSCustomObject]@{ Date = (& $toDate $e.date); Amount = ([double]$e.amount * $factor) } }
            }
        }
    }
    return @{
        Dates     = $dates
        Closes    = $closes
        Currency  = $cur
        Splits    = @($splits | Sort-Object -Property @{ Expression = { [string]$_.Date } })
        Dividends = @($divs | Sort-Object -Property @{ Expression = { [string]$_.Date } })
    }
}

function Get-HistoryValueOnDate {
    # Last value on or before Date (binary search), else the first one; NaN if empty
    param($Dates, $Values, [string]$Date)
    if ($null -eq $Dates -or $Dates.Count -eq 0) { return [double]::NaN }
    $lo = 0; $hi = $Dates.Count - 1; $found = -1
    while ($lo -le $hi) {
        $mid = [int][math]::Floor(($lo + $hi) / 2)
        if ([string]::CompareOrdinal([string]$Dates[$mid], $Date) -le 0) { $found = $mid; $lo = $mid + 1 } else { $hi = $mid - 1 }
    }
    if ($found -lt 0) { $found = 0 }
    return [double]$Values[$found]
}

function Get-AlignedSeries {
    # Values of a history aligned to the ascending date list Target: the last
    # value on or before each date (before the history starts: its first value).
    # One pass, no lookups. All NaN when there is no history.
    param([string[]]$Target, $Dates, $Values)
    $n = $Target.Count
    $out = New-Object double[] $n
    $cnt = if ($null -eq $Dates) { 0 } else { $Dates.Count }
    if ($cnt -eq 0) {
        for ($i = 0; $i -lt $n; $i++) { $out[$i] = [double]::NaN }
        return ,$out
    }
    $j = 0
    for ($i = 0; $i -lt $n; $i++) {
        while (($j + 1) -lt $cnt -and [string]::CompareOrdinal([string]$Dates[$j + 1], $Target[$i]) -le 0) { $j++ }
        $out[$i] = [double]$Values[$j]
    }
    return ,$out
}

function Get-AlignedFxToBase {
    # Factor that turns an amount in Currency into Base, per target date
    # (Rates are units per 1 EUR). Missing history: today's fallback rate.
    param([string[]]$Target, [string]$Currency, [string]$Base, [hashtable]$History, [hashtable]$FallbackFromEur = @{})
    $n = $Target.Count
    $out = New-Object double[] $n
    $approx = $false
    $legs = @()
    foreach ($c in @($Currency, $Base)) {
        $nc = Get-NormalizedCurrencyCode $c
        if ($nc -eq "EUR" -or -not $nc) {
            $a = New-Object double[] $n
            for ($i = 0; $i -lt $n; $i++) { $a[$i] = 1.0 }
        } elseif ($null -ne $History -and $History.ContainsKey($nc) -and $History[$nc].Dates.Count -gt 0) {
            $a = Get-AlignedSeries -Target $Target -Dates $History[$nc].Dates -Values $History[$nc].Rates
        } else {
            $approx = $true
            $fb = if ($null -ne $FallbackFromEur -and $FallbackFromEur.ContainsKey($nc) -and [double]$FallbackFromEur[$nc] -gt 0) { [double]$FallbackFromEur[$nc] } else { 1.0 }
            $a = New-Object double[] $n
            for ($i = 0; $i -lt $n; $i++) { $a[$i] = $fb }
        }
        $legs += ,$a
    }
    for ($i = 0; $i -lt $n; $i++) { $out[$i] = $legs[1][$i] / $legs[0][$i] }
    return @{ Factor = $out; Approx = $approx }
}

# ------------------------------------------------------------------------------
# Ledger: every ticker's bookings replayed in the base currency (moving
# average cost at the FX rate of each booking date, splits applied), plus the
# cash flows for the money-weighted return.
# ------------------------------------------------------------------------------
function Get-PortfolioLedger {
    param(
        [array]$Transactions,
        [string]$Base = "EUR",
        [hashtable]$History = @{},
        [hashtable]$FallbackFromEur = @{},
        [hashtable]$Splits = @{},
        [string]$AsOf = ""
    )
    $base = Get-NormalizedCurrencyCode $Base
    if (-not $base) { $base = "EUR" }
    $end = if ($AsOf) { $AsOf } else { (Get-Date).ToString("yyyy-MM-dd") }
    $groups = @{}
    $i = 0
    foreach ($tx in @($Transactions)) {
        $i++
        if ($null -eq $tx -or -not $tx.Ticker) { continue }
        if ([string]$tx.Type -notin @("Kauf", "Verkauf", "Dividende")) { continue }
        if ([string]::CompareOrdinal([string]$tx.Date, $end) -gt 0) { continue }
        $sym = ([string]$tx.Ticker).ToUpper()
        if (-not $groups.ContainsKey($sym)) { $groups[$sym] = New-Object System.Collections.Generic.List[PSObject] }
        $groups[$sym].Add([PSCustomObject]@{ Date = [string]$tx.Date; Idx = $i; Tx = $tx })
    }
    $out = @{}
    foreach ($sym in @($groups.Keys)) {
        $L = [PSCustomObject]@{
            Ticker = $sym; Currency = ""; Shares = 0.0; Cost = 0.0; Realized = 0.0; Dividends = 0.0; Fees = 0.0
            Bought = 0.0; FirstDate = ""; CfDates = (New-Object System.Collections.Generic.List[string])
            CfAmounts = (New-Object System.Collections.Generic.List[double])
            CfKinds = (New-Object System.Collections.Generic.List[string]); Approx = $false; Clamped = $false
        }
        $spl = @(Get-SplitEvents -Splits $Splits -Ticker $sym)
        $k = 0
        $ordered = @($groups[$sym] | Sort-Object -Property @{ Expression = { $_.Date } }, @{ Expression = { $_.Idx } })
        foreach ($o in $ordered) {
            $tx = $o.Tx
            $date = [string]$tx.Date
            while ($k -lt $spl.Count -and [string]::CompareOrdinal([string]$spl[$k].Date, $date) -le 0) {
                if ($L.Shares -gt 0) { $L.Shares *= [double]$spl[$k].Ratio }
                $k++
            }
            $cur = Get-NormalizedCurrencyCode ([string]$tx.Currency)
            if (-not $cur) { $cur = "EUR" }
            $q = [double]$tx.Shares; $px = [double]$tx.Price; $fee = [double]$tx.Fee
            switch ([string]$tx.Type) {
                "Kauf" {
                    if ($q -le 0 -or $px -le 0) { continue }
                    $cv = Convert-AmountOnDate -Amount (($q * $px) + $fee) -From $cur -To $base -Date $date -History $History -FallbackFromEur $FallbackFromEur
                    $fv = Convert-AmountOnDate -Amount $fee -From $cur -To $base -Date $date -History $History -FallbackFromEur $FallbackFromEur
                    $L.Cost += $cv.Value; $L.Bought += $cv.Value; $L.Shares += $q; $L.Fees += $fv.Value
                    if (-not $L.FirstDate) { $L.FirstDate = $date }
                    if (-not $L.Currency) { $L.Currency = $cur }
                    $L.CfDates.Add($date); $L.CfAmounts.Add(-$cv.Value); $L.CfKinds.Add("B")
                    if ($cv.Approx) { $L.Approx = $true }
                }
                "Verkauf" {
                    if ($q -le 0 -or $px -le 0) { continue }
                    if ($q -gt ($L.Shares + 0.000001)) { $q = $L.Shares; $L.Clamped = $true }
                    if ($q -le 0) { continue }
                    $costPart = ($L.Cost / $L.Shares) * $q
                    $pr = Convert-AmountOnDate -Amount ($q * $px) -From $cur -To $base -Date $date -History $History -FallbackFromEur $FallbackFromEur
                    $fe = Convert-AmountOnDate -Amount $fee -From $cur -To $base -Date $date -History $History -FallbackFromEur $FallbackFromEur
                    $L.Realized += ($pr.Value - $costPart - $fe.Value)
                    $L.Fees += $fe.Value
                    $L.Cost -= $costPart
                    $L.Shares -= $q
                    if ($L.Shares -le 0.000001) { $L.Shares = 0.0; $L.Cost = 0.0 }
                    $L.CfDates.Add($date); $L.CfAmounts.Add($pr.Value - $fe.Value); $L.CfKinds.Add("S")
                    if ($pr.Approx -or $fe.Approx) { $L.Approx = $true }
                }
                "Dividende" {
                    if ($px -le 0) { continue }
                    $gr = Convert-AmountOnDate -Amount ($px - $fee) -From $cur -To $base -Date $date -History $History -FallbackFromEur $FallbackFromEur
                    $L.Dividends += $gr.Value
                    $L.CfDates.Add($date); $L.CfAmounts.Add($gr.Value); $L.CfKinds.Add("D")
                    if ($gr.Approx) { $L.Approx = $true }
                }
            }
        }
        while ($k -lt $spl.Count -and [string]::CompareOrdinal([string]$spl[$k].Date, $end) -le 0) {
            if ($L.Shares -gt 0) { $L.Shares *= [double]$spl[$k].Ratio }
            $k++
        }
        $out[$sym] = $L
    }
    return $out
}

function Get-UncoveredPositions {
    # Positions whose share count is not (fully) explained by bookings: they
    # cannot be part of the rebuilt history
    param([hashtable]$Portfolio, [hashtable]$Ledger)
    $out = @()
    if ($null -eq $Portfolio) { return $out }
    foreach ($sym in @($Portfolio.Keys | Sort-Object)) {
        $pf = [double]$Portfolio[$sym].Shares
        $bk = if ($null -ne $Ledger -and $Ledger.ContainsKey(([string]$sym).ToUpper())) { [double]$Ledger[([string]$sym).ToUpper()].Shares } else { 0.0 }
        if ([math]::Abs($pf - $bk) -gt (0.0001 * [math]::Max(1.0, [math]::Abs($pf)))) {
            $out += [PSCustomObject]@{ Ticker = ([string]$sym).ToUpper(); Shares = $pf; Booked = $bk; Missing = ($pf - $bk) }
        }
    }
    return $out
}

# ------------------------------------------------------------------------------
# Money-weighted return (XIRR, annualized, days / 365)
# ------------------------------------------------------------------------------
function Get-XirrNpv {
    param([double[]]$T, [double[]]$A, [double]$Rate)
    $f = 0.0; $df = 0.0
    for ($i = 0; $i -lt $A.Count; $i++) {
        $v = [math]::Pow(1.0 + $Rate, $T[$i])
        $f += $A[$i] / $v
        $df += -$T[$i] * $A[$i] / ($v * (1.0 + $Rate))
    }
    return @($f, $df)
}

function Get-Xirr {
    # NaN when it cannot be computed (needs money in AND out, >= 2 dates)
    param([string[]]$Dates, [double[]]$Amounts)
    $n = [math]::Min(@($Dates).Count, @($Amounts).Count)
    if ($n -lt 2) { return [double]::NaN }
    $hasNeg = $false; $hasPos = $false
    $dt = New-Object DateTime[] $n
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    for ($i = 0; $i -lt $n; $i++) {
        if ($Amounts[$i] -lt 0) { $hasNeg = $true } elseif ($Amounts[$i] -gt 0) { $hasPos = $true }
        $dt[$i] = [DateTime]::ParseExact(([string]$Dates[$i]).Substring(0, 10), "yyyy-MM-dd", $inv)
    }
    if (-not ($hasNeg -and $hasPos)) { return [double]::NaN }
    # (no Measure-Object: Windows PowerShell 5.1 cannot take the minimum of dates)
    $d0 = $dt[0]
    for ($i = 1; $i -lt $n; $i++) { if ($dt[$i] -lt $d0) { $d0 = $dt[$i] } }
    $t = New-Object double[] $n
    $a = New-Object double[] $n
    $tMax = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $t[$i] = ($dt[$i] - $d0).TotalDays / 365.0
        $a[$i] = [double]$Amounts[$i]
        if ($t[$i] -gt $tMax) { $tMax = $t[$i] }
    }
    if ($tMax -le 0) { return [double]::NaN }

    # Newton from 10 %
    $r = 0.1
    for ($it = 0; $it -lt 60; $it++) {
        $fd = Get-XirrNpv -T $t -A $a -Rate $r
        if ([math]::Abs($fd[0]) -lt 1e-9) { return $r }
        if ($fd[1] -eq 0 -or [double]::IsNaN($fd[1])) { break }
        $next = $r - ($fd[0] / $fd[1])
        if ([double]::IsNaN($next) -or [double]::IsInfinity($next) -or $next -le -0.9999) { break }
        if ([math]::Abs($next - $r) -lt 1e-12) { return $next }
        $r = $next
    }
    # Bisection fallback
    $lo = -0.9999; $hi = 1.0
    $flo = (Get-XirrNpv -T $t -A $a -Rate $lo)[0]
    $fhi = (Get-XirrNpv -T $t -A $a -Rate $hi)[0]
    $g = 0
    while (($flo * $fhi) -gt 0 -and $g -lt 40) { $hi *= 2.0; $fhi = (Get-XirrNpv -T $t -A $a -Rate $hi)[0]; $g++ }
    if (($flo * $fhi) -gt 0) { return [double]::NaN }
    for ($it = 0; $it -lt 300; $it++) {
        $mid = ($lo + $hi) / 2.0
        $fm = (Get-XirrNpv -T $t -A $a -Rate $mid)[0]
        if ([math]::Abs($fm) -lt 1e-9 -or ($hi - $lo) -lt 1e-12) { return $mid }
        if (($flo * $fm) -lt 0) { $hi = $mid; $fhi = $fm } else { $lo = $mid; $flo = $fm }
    }
    return (($lo + $hi) / 2.0)
}

# ------------------------------------------------------------------------------
# Value history rebuilt from the bookings, and a benchmark "shadow" portfolio:
# every buy / sell of the real portfolio is done in the benchmark instead.
# Prices: ticker -> @{ Dates; Closes; Currency; Splits } (ConvertFrom-YahooDailyHistory)
# ------------------------------------------------------------------------------
function Get-PortfolioValueSeries {
    param(
        [array]$Transactions,
        [hashtable]$Prices,
        [string]$Base = "EUR",
        [hashtable]$History = @{},
        [hashtable]$FallbackFromEur = @{},
        $Benchmark = $null,
        [string]$EndDate = "",
        [int]$MaxPoints = 1500
    )
    $base = Get-NormalizedCurrencyCode $Base
    if (-not $base) { $base = "EUR" }
    $end = if ($EndDate) { $EndDate } else { (Get-Date).ToString("yyyy-MM-dd") }

    $bk = New-Object System.Collections.Generic.List[PSObject]
    $i = 0
    foreach ($tx in @($Transactions)) {
        $i++
        if ($null -eq $tx -or -not $tx.Ticker -or [string]$tx.Type -notin @("Kauf", "Verkauf", "Dividende")) { continue }
        if ([string]::CompareOrdinal([string]$tx.Date, $end) -gt 0) { continue }
        $bk.Add([PSCustomObject]@{ Date = [string]$tx.Date; Idx = $i; Tx = $tx; Sym = ([string]$tx.Ticker).ToUpper() })
    }
    if ($bk.Count -eq 0) { return $null }
    $books = @($bk | Sort-Object -Property @{ Expression = { $_.Date } }, @{ Expression = { $_.Idx } })
    $start = [string]$books[0].Date
    $syms = @($books | Where-Object { $_.Tx.Type -ne "Dividende" } | ForEach-Object { $_.Sym } | Sort-Object -Unique)

    # Date axis: every trading day of any held ticker between start and end
    $axisSet = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::Ordinal)
    $missing = @()
    foreach ($s in $syms) {
        if ($null -eq $Prices -or -not $Prices.ContainsKey($s) -or $null -eq $Prices[$s]) { $missing += $s; continue }
        foreach ($d in $Prices[$s].Dates) {
            if ([string]::CompareOrdinal($d, $start) -ge 0 -and [string]::CompareOrdinal($d, $end) -le 0) { [void]$axisSet.Add($d) }
        }
    }
    if ($axisSet.Count -eq 0) { return $null }
    $axisAll = New-Object string[] $axisSet.Count
    $axisSet.CopyTo($axisAll)
    if ($axisAll.Count -gt $MaxPoints) {
        $step = [math]::Ceiling($axisAll.Count / $MaxPoints)
        $keep = New-Object System.Collections.Generic.List[string]
        for ($j = 0; $j -lt $axisAll.Count; $j += $step) { $keep.Add($axisAll[$j]) }
        if ($keep[$keep.Count - 1] -ne $axisAll[$axisAll.Count - 1]) { $keep.Add($axisAll[$axisAll.Count - 1]) }
        $axis = $keep.ToArray()
    } else {
        $axis = $axisAll
    }
    $n = $axis.Count

    # Aligned price x FX per ticker
    $approx = $false
    $valBase = @{}
    $splitList = @{}
    $shares = @{}
    foreach ($s in $syms) {
        $shares[$s] = 0.0
        if ($missing -contains $s) { $splitList[$s] = @(); continue }
        $p = $Prices[$s]
        $cl = Get-AlignedSeries -Target $axis -Dates $p.Dates -Values $p.Closes
        $fx = Get-AlignedFxToBase -Target $axis -Currency ([string]$p.Currency) -Base $base -History $History -FallbackFromEur $FallbackFromEur
        if ($fx.Approx) { $approx = $true }
        $v = New-Object double[] $n
        for ($j = 0; $j -lt $n; $j++) { $v[$j] = $cl[$j] * $fx.Factor[$j] }
        $valBase[$s] = $v
        $splitList[$s] = @(@($p.Splits) | Where-Object { $null -ne $_ -and [double]$_.Ratio -gt 0 } | Sort-Object -Property @{ Expression = { [string]$_.Date } })
    }

    # Benchmark in the base currency (aligned) + lookups on booking dates
    $bench = $null
    $benchBase = $null
    if ($null -ne $Benchmark -and $null -ne $Benchmark.Dates -and $Benchmark.Dates.Count -gt 0) {
        $bcl = Get-AlignedSeries -Target $axis -Dates $Benchmark.Dates -Values $Benchmark.Closes
        $bfx = Get-AlignedFxToBase -Target $axis -Currency ([string]$Benchmark.Currency) -Base $base -History $History -FallbackFromEur $FallbackFromEur
        $benchBase = New-Object double[] $n
        for ($j = 0; $j -lt $n; $j++) { $benchBase[$j] = $bcl[$j] * $bfx.Factor[$j] }
        $bench = New-Object double[] $n
    }
    $benchOnDate = {
        param([string]$D)
        $px = Get-HistoryValueOnDate -Dates $Benchmark.Dates -Values $Benchmark.Closes -Date $D
        $cv = Convert-AmountOnDate -Amount $px -From ([string]$Benchmark.Currency) -To $base -Date $D -History $History -FallbackFromEur $FallbackFromEur
        return $cv.Value
    }

    # Yahoo's closes are adjusted for every split up to today, so booked shares
    # are converted to today's units: x every split AFTER the booking date
    # (a booking on the ex-date is already in post-split units)
    $laterSplitFactor = {
        param([string]$S, [string]$D)
        $f = 1.0
        foreach ($sp in @($splitList[$S])) { if ([string]::CompareOrdinal([string]$sp.Date, $D) -gt 0) { $f *= [double]$sp.Ratio } }
        return $f
    }

    $value = New-Object double[] $n
    $invested = New-Object double[] $n
    $divCum = New-Object double[] $n
    $net = 0.0; $dv = 0.0; $units = 0.0; $clampedBench = $false
    $b = 0
    for ($j = 0; $j -lt $n; $j++) {
        $d = $axis[$j]
        while ($b -lt $books.Count -and [string]::CompareOrdinal([string]$books[$b].Date, $d) -le 0) {
            $o = $books[$b]; $tx = $o.Tx; $s = $o.Sym; $bd = [string]$o.Date
            $cur = Get-NormalizedCurrencyCode ([string]$tx.Currency)
            if (-not $cur) { $cur = "EUR" }
            $q = [double]$tx.Shares; $px = [double]$tx.Price; $fee = [double]$tx.Fee
            $sf = if ($shares.ContainsKey($s)) { & $laterSplitFactor $s $bd } else { 1.0 }
            switch ([string]$tx.Type) {
                "Kauf" {
                    if ($q -gt 0 -and $px -gt 0) {
                        $cv = Convert-AmountOnDate -Amount (($q * $px) + $fee) -From $cur -To $base -Date $bd -History $History -FallbackFromEur $FallbackFromEur
                        $shares[$s] = $shares[$s] + ($q * $sf)
                        $net += $cv.Value
                        if ($null -ne $bench) { $bp = & $benchOnDate $bd; if ($bp -gt 0) { $units += $cv.Value / $bp } }
                    }
                }
                "Verkauf" {
                    if ($q -gt 0 -and $px -gt 0) {
                        # clamp in today's units, proceeds in the booked units
                        $qa = [math]::Min($q * $sf, $shares[$s])
                        $q = $qa / $sf
                        $pr = Convert-AmountOnDate -Amount (($q * $px) - $fee) -From $cur -To $base -Date $bd -History $History -FallbackFromEur $FallbackFromEur
                        $shares[$s] = $shares[$s] - $qa
                        $net -= $pr.Value
                        if ($null -ne $bench) {
                            $bp = & $benchOnDate $bd
                            if ($bp -gt 0) { $units -= $pr.Value / $bp }
                            if ($units -lt 0) { $units = 0.0; $clampedBench = $true }
                        }
                    }
                }
                "Dividende" {
                    if ($px -gt 0) {
                        $gr = Convert-AmountOnDate -Amount ($px - $fee) -From $cur -To $base -Date $bd -History $History -FallbackFromEur $FallbackFromEur
                        $dv += $gr.Value
                    }
                }
            }
            $b++
        }
        $tot = 0.0
        foreach ($s in $syms) {
            if ($shares[$s] -gt 0 -and $valBase.ContainsKey($s)) {
                $px = $valBase[$s][$j]
                if (-not [double]::IsNaN($px)) { $tot += $shares[$s] * $px }
            }
        }
        $value[$j] = $tot
        $invested[$j] = $net
        $divCum[$j] = $dv
        if ($null -ne $bench) { $bench[$j] = $units * $benchBase[$j] }
    }
    return [PSCustomObject]@{
        Dates        = $axis
        Value        = $value
        Invested     = $invested
        Dividends    = $divCum
        Bench        = $bench
        Missing      = $missing
        Approx       = $approx
        BenchClamped = $clampedBench
    }
}

function Get-SeriesWindowStart {
    # Index of the first point of a window (6M / 1Y / 3Y / Max) on a date axis
    param([string[]]$Dates, [string]$Range, [string]$EndDate = "")
    if ($null -eq $Dates -or $Dates.Count -eq 0) { return 0 }
    $last = if ($EndDate) { $EndDate } else { $Dates[$Dates.Count - 1] }
    $ld = [DateTime]::ParseExact($last, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
    $from = switch ($Range) {
        "6M" { $ld.AddMonths(-6) }
        "1Y" { $ld.AddYears(-1) }
        "3Y" { $ld.AddYears(-3) }
        default { $null }
    }
    if ($null -eq $from) { return 0 }
    $f = $from.ToString("yyyy-MM-dd")
    for ($i = 0; $i -lt $Dates.Count; $i++) { if ([string]::CompareOrdinal($Dates[$i], $f) -ge 0) { return $i } }
    return ($Dates.Count - 1)
}

# ------------------------------------------------------------------------------
# Breakdown (allocation) and concentration
# ------------------------------------------------------------------------------
function Get-AllocationBreakdown {
    # Items: objects with Key and Value -> groups sorted by value, with Pct
    param([array]$Items)
    $sum = @{}
    $total = 0.0
    foreach ($it in @($Items)) {
        if ($null -eq $it) { continue }
        $v = [double]$it.Value
        if ($v -le 0 -or [double]::IsNaN($v)) { continue }
        $k = if ([string]::IsNullOrWhiteSpace([string]$it.Key)) { "Unbekannt" } else { [string]$it.Key }
        if (-not $sum.ContainsKey($k)) { $sum[$k] = 0.0 }
        $sum[$k] += $v
        $total += $v
    }
    $out = @()
    foreach ($k in $sum.Keys) {
        $out += [PSCustomObject]@{ Key = $k; Value = $sum[$k]; Pct = $(if ($total -gt 0) { $sum[$k] / $total * 100.0 } else { 0.0 }) }
    }
    return @($out | Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key } })
}

function Get-ConcentrationWarnings {
    param([array]$Groups, [double]$ThresholdPct = 20)
    return @(@($Groups) | Where-Object { $null -ne $_ -and [double]$_.Pct -gt $ThresholdPct })
}

# ------------------------------------------------------------------------------
# Company profile (sector / country). Yahoo's quoteSummary needs a cookie +
# crumb; the search API delivers at least the sector without one.
# ------------------------------------------------------------------------------
function ConvertFrom-YahooProfile {
    param($Summary, $Search, [string]$Symbol)
    $o = [PSCustomObject]@{ Sector = ""; Industry = ""; Country = ""; QuoteType = ""; Name = "" }
    try {
        $r = $Summary.quoteSummary.result[0]
        if ($null -ne $r.assetProfile) {
            $o.Sector = [string]$r.assetProfile.sector
            $o.Industry = [string]$r.assetProfile.industry
            $o.Country = [string]$r.assetProfile.country
        }
        if ($null -ne $r.quoteType) {
            $o.QuoteType = [string]$r.quoteType.quoteType
            $o.Name = if ($r.quoteType.longName) { [string]$r.quoteType.longName } else { [string]$r.quoteType.shortName }
        }
    } catch { }
    if ($null -ne $Search -and $null -ne $Search.quotes) {
        $hit = $null
        foreach ($q in @($Search.quotes)) { if (([string]$q.symbol).ToUpper() -eq ([string]$Symbol).ToUpper()) { $hit = $q; break } }
        if ($null -ne $hit) {
            if (-not $o.Sector)    { $o.Sector = if ($hit.sectorDisp) { [string]$hit.sectorDisp } else { [string]$hit.sector } }
            if (-not $o.Industry)  { $o.Industry = if ($hit.industryDisp) { [string]$hit.industryDisp } else { [string]$hit.industry } }
            if (-not $o.QuoteType) { $o.QuoteType = [string]$hit.quoteType }
            if (-not $o.Name)      { $o.Name = if ($hit.longname) { [string]$hit.longname } else { [string]$hit.shortname } }
        }
    }
    return $o
}

function Get-SectorLabel {
    param([string]$Sector)
    $map = @{
        "Technology" = "Technologie"; "Financial Services" = "Finanzen"; "Healthcare" = "Gesundheit"
        "Consumer Cyclical" = "Zyklischer Konsum"; "Consumer Defensive" = "Basiskonsum"
        "Communication Services" = "Kommunikation"; "Industrials" = "Industrie"; "Energy" = "Energie"
        "Basic Materials" = "Grundstoffe"; "Real Estate" = "Immobilien"; "Utilities" = "Versorger"
    }
    if ($map.ContainsKey($Sector)) { return $map[$Sector] }
    return $Sector
}

function Get-CountryLabel {
    param([string]$Country)
    $map = @{
        "United States" = "USA"; "Germany" = "Deutschland"; "Switzerland" = "Schweiz"; "Austria" = "Österreich"
        "United Kingdom" = "Großbritannien"; "Netherlands" = "Niederlande"; "France" = "Frankreich"; "Ireland" = "Irland"
        "Italy" = "Italien"; "Spain" = "Spanien"; "Sweden" = "Schweden"; "Denmark" = "Dänemark"; "Norway" = "Norwegen"
        "Finland" = "Finnland"; "Belgium" = "Belgien"; "Canada" = "Kanada"; "Japan" = "Japan"; "China" = "China"
        "Taiwan" = "Taiwan"; "South Korea" = "Südkorea"; "Hong Kong" = "Hongkong"; "India" = "Indien"
        "Australia" = "Australien"; "Brazil" = "Brasilien"; "Luxembourg" = "Luxemburg"; "Israel" = "Israel"
    }
    if ($map.ContainsKey($Country)) { return $map[$Country] }
    return $Country
}

function Get-EffectiveProfile {
    # Manual value > Yahoo value > by instrument type > "Unbekannt"
    param($Entry)
    $qt = if ($null -ne $Entry) { ([string]$Entry.QuoteType).ToUpper() } else { "" }
    $byType = switch ($qt) {
        "ETF"            { @{ Sector = "ETF / Fonds"; Country = "Fonds (gemischt)" } }
        "MUTUALFUND"     { @{ Sector = "ETF / Fonds"; Country = "Fonds (gemischt)" } }
        "CRYPTOCURRENCY" { @{ Sector = "Krypto"; Country = "Ohne Land" } }
        "INDEX"          { @{ Sector = "Index"; Country = "Ohne Land" } }
        "CURRENCY"       { @{ Sector = "Devisen"; Country = "Ohne Land" } }
        "FUTURE"         { @{ Sector = "Rohstoffe / Futures"; Country = "Ohne Land" } }
        default          { @{ Sector = ""; Country = "" } }
    }
    $res = [PSCustomObject]@{ Sector = "Unbekannt"; Country = "Unbekannt"; SectorSource = ""; CountrySource = "" }
    if ($null -ne $Entry -and $Entry.ManualSector) { $res.Sector = [string]$Entry.ManualSector; $res.SectorSource = "manuell" }
    elseif ($null -ne $Entry -and $Entry.Sector) { $res.Sector = Get-SectorLabel ([string]$Entry.Sector); $res.SectorSource = "Yahoo" }
    elseif ($byType.Sector) { $res.Sector = $byType.Sector; $res.SectorSource = "Typ" }
    if ($null -ne $Entry -and $Entry.ManualCountry) { $res.Country = [string]$Entry.ManualCountry; $res.CountrySource = "manuell" }
    elseif ($null -ne $Entry -and $Entry.Country) { $res.Country = Get-CountryLabel ([string]$Entry.Country); $res.CountrySource = "Yahoo" }
    elseif ($byType.Country) { $res.Country = $byType.Country; $res.CountrySource = "Typ" }
    return $res
}

function Test-ProfileStale {
    # Fetched profile older than MaxDays (or never fetched)?
    param($Entry, [int]$MaxDays = 30, [DateTime]$Now = (Get-Date))
    if ($null -eq $Entry -or -not $Entry.FetchedAt) { return $true }
    $t = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$Entry.FetchedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$t)) { return $true }
    return (($Now - $t).TotalDays -gt $MaxDays)
}
