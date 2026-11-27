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

function Format-EditNumber {
    # v7.1.1: number for an input field - decimal separator of the system, no
    # grouping, so Parse-DecimalInput reads it back unchanged
    param([double]$Value, [System.Globalization.CultureInfo]$Culture = [System.Globalization.CultureInfo]::CurrentCulture)
    $t = $Value.ToString("0.##########", [System.Globalization.CultureInfo]::InvariantCulture)
    if ($Culture.NumberFormat.NumberDecimalSeparator -eq ",") { return $t.Replace(".", ",") }
    return $t
}

function Get-LogErrorCount {
    # v7.1.1: errors since the start of this process. Without its start line in
    # the given lines (long session), all of them belong to this session.
    param($Lines, [int]$ProcessId)
    $all = @($Lines)
    $from = 0
    $marker = "Script start (PID {0}," -f $ProcessId
    for ($i = $all.Count - 1; $i -ge 0; $i--) {
        if (([string]$all[$i]).Contains($marker)) { $from = $i; break }
    }
    $n = 0
    for ($i = $from; $i -lt $all.Count; $i++) { if (([string]$all[$i]) -match '\[ERROR\]') { $n++ } }
    return $n
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

function Get-NextDisplayCurrency {
    # W key: EUR -> USD -> CHF -> GBP -> EUR (unknown -> first entry)
    param([string]$Current)
    $list = @(Get-DisplayCurrencies)
    $i = [array]::IndexOf($list, ([string]$Current).Trim().ToUpper())
    return $list[($i + 1) % $list.Count]
}

function Get-NextCurrencyMode {
    # v5.1: W key with automatic currency: AUTO -> EUR -> USD -> CHF -> GBP -> AUTO
    param([string]$Current, [bool]$Auto)
    $list = @("AUTO") + @(Get-DisplayCurrencies)
    $cur = if ($Auto) { "AUTO" } else { ([string]$Current).Trim().ToUpper() }
    $i = [array]::IndexOf($list, $cur)
    return $list[($i + 1) % $list.Count]
}

function Get-TickerCurrencyGuess {
    # v5.1: trading currency from the exchange suffix, until Yahoo has answered
    param([string]$Symbol)
    $u = ([string]$Symbol).Trim().ToUpper()
    if ($u -match '=X$') {
        $pair = $u -replace '=X$', ''
        if ($pair.Length -ge 6) { return $pair.Substring(3, 3) } else { return $pair }
    }
    if ($u.StartsWith("^")) { return "" }
    if ($u -notmatch '\.([A-Z]+)$') { return "USD" }
    switch ($Matches[1]) {
        { $_ -in @("DE", "F", "BE", "DU", "HM", "HA", "MU", "SG", "PA", "AS", "BR", "MI", "MC", "VI", "HE", "LS", "IR", "AT") } { return "EUR" }
        "SW" { return "CHF" }
        "L"  { return "GBP" }
        "TO" { return "CAD" }
        "V"  { return "CAD" }
        "T"  { return "JPY" }
        "HK" { return "HKD" }
        "ST" { return "SEK" }
        "CO" { return "DKK" }
        "OL" { return "NOK" }
        "AX" { return "AUD" }
        "WA" { return "PLN" }
        default { return "" }
    }
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
    return @("Dark", "OLED", "Light", "Terminal", "Graphite", "Contrast")   # v5.7: Contrast = high contrast
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
        [int]$MinChartH = 160,
        [string]$Full = "",
        [double]$SplitPct = 50
    )
    # v4.9: ActiveBottom "News" puts the news tab below the chart, full width
    $out = [PSCustomObject]@{ Chart = $null; Watchlist = $null; Portfolio = $null; News = $null; SideBySide = $false }
    # v4.9.5: one list as a full page (the chart and the other lists hidden)
    if ($Full -in @("Watchlist", "Portfolio", "News")) {
        $out.$Full = @($X, $Y, $W, $H)
        return $out
    }
    $bottom = New-Object System.Collections.Generic.List[string]
    if ($ShowWatch) { $bottom.Add("Watchlist") }
    if ($ShowPortfolio) { $bottom.Add("Portfolio") }
    $newsOn = ([string]$ActiveBottom -eq "News")
    if (($bottom.Count -eq 0 -and -not $newsOn) -or $H -lt ($MinChartH + $Gap + 40)) {
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
    if ($newsOn) {
        $out.News = @($X, $by, $W, $bottomH)
        return $out
    }
    if ($bottom.Count -eq 2 -and $W -ge (2 * $PanelMinW + $Gap)) {
        # v5.0: the divider between the two lists can be dragged (SplitPct = watchlist share)
        $sp = [math]::Max(25.0, [math]::Min(75.0, $SplitPct))
        $half = [int][math]::Floor(($W - $Gap) * $sp / 100.0)
        $half = [math]::Max($PanelMinW, [math]::Min($W - $Gap - $PanelMinW, $half))
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

function Get-FlashAlpha {
    # v4.9.5: price flash strength: Max while holding, then linear to 0
    param([double]$ElapsedMs, [int]$HoldMs = 300, [int]$FadeMs = 600, [double]$Max = 0.35)
    if ($ElapsedMs -lt 0) { return $Max }
    if ($ElapsedMs -le $HoldMs) { return $Max }
    if ($FadeMs -le 0) { return 0.0 }
    $t = ($ElapsedMs - $HoldMs) / $FadeMs
    if ($t -ge 1) { return 0.0 }
    return [math]::Round($Max * (1 - $t), 4)
}

function Get-DirectionKey {
    # v4.9.5: "up" / "down" / "none" (flat within +-Flat %, or no value)
    param([double]$Pct, [double]$Flat = 0.005)
    if ([double]::IsNaN($Pct)) { return "none" }
    if ($Pct -gt $Flat) { return "up" }
    if ($Pct -lt -$Flat) { return "down" }
    return "none"
}

function Protect-Amount {
    # v4.9.5: privacy mode (F9): amounts become dots, percentages stay
    param([string]$Text, [bool]$On = $false)
    if (-not $On) { return $Text }
    return [string]([char]0x2022) * 4
}

function Get-SnoozeUntil {
    # v4.9.5: "1h" / "4h" / "Tomorrow" (next day 08:00) -> DateTime; MinValue = no pause
    param([string]$Kind, [DateTime]$Now = (Get-Date))
    switch ($Kind) {
        "1h"       { return $Now.AddHours(1) }
        "4h"       { return $Now.AddHours(4) }
        "Tomorrow" { return $Now.Date.AddDays(1).AddHours(8) }
        "Week"     { return $Now.Date.AddDays(7).AddHours(8) }
        default    { return [DateTime]::MinValue }
    }
}

function Test-AlertSnoozed {
    # v4.9.5: an alert with SnoozeUntil in the future stays quiet
    param($Alert, [DateTime]$Now = (Get-Date))
    if ($null -eq $Alert -or $null -eq $Alert.PSObject.Properties["SnoozeUntil"]) { return $false }
    $v = [string]$Alert.SnoozeUntil
    if (-not $v) { return $false }
    $t = [DateTime]::MinValue
    if (-not [DateTime]::TryParse($v, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$t)) { return $false }
    return ($Now -lt $t)
}

function ConvertTo-TsvTable {
    # v4.9.5: header + rows -> tab-separated text (pastes into Excel / mail);
    # tabs and line breaks inside a cell become spaces
    param([string[]]$Headers, $Rows)
    $clean = { param($v) (([string]$v) -replace '[\t\r\n]+', ' ').Trim() }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((@($Headers | ForEach-Object { & $clean $_ }) -join "`t"))
    foreach ($r in @($Rows)) {
        if ($null -eq $r) { continue }
        $lines.Add((@(@($r) | ForEach-Object { & $clean $_ }) -join "`t"))
    }
    return ($lines -join "`r`n")
}

function Get-DataHealth {
    # v4.9.5: colour of the status dot: "OK" / "WARN" / "ERR" ("" = no data yet).
    # While every market is closed the widget polls only every ClosedMinutes,
    # so older data is still fine then.
    param([double]$AgeSec, [int]$RefreshSec, [bool]$Offline = $false, [bool]$RateLimited = $false, [int]$ClosedMinutes = 0, [bool]$AllClosed = $false)
    if ($Offline) { return "ERR" }
    if ([double]::IsNaN($AgeSec)) { return "" }
    if ($RateLimited) { return "WARN" }
    $every = $RefreshSec
    if ($AllClosed -and $ClosedMinutes -gt 0) { $every = [math]::Max($RefreshSec, $ClosedMinutes * 60) }
    return (Get-StalenessLevel -AgeSec $AgeSec -RefreshSec $every)
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
    # v5.5: cash, savings plans, drawings and notes travel with export / import too
    return @("config.json", "portfolio.json", "alerts.json", "transactions.json", "intraday_cache.json", "quote_cache.json", "profiles.json", "events.json", "alert-log.json",
        "cash.json", "savingsplans.json", "drawings.json", "notes.json", "news.json")
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
    & $add "ALERTCOND" "Alarm-Bedingung" "Wann der Alarm auslöst." "Kurs >= / <=: Kurs in Anzeigewährung. Tag% >= / <=: Tagesänderung in %. RSI >= / <=: RSI auf Stundenbasis. > SMA / < SMA: Kurs kreuzt den schnellen SMA (Stundenbasis), kein Wert nötig. Trailing %: Rückgang vom höchsten Kurs seit dem Anlegen. EK% >= / <=: Gewinn/Verlust zum Einstand der Position. 52W Hoch / Tief: Kurs erreicht das 52-Wochen-Hoch/-Tief (Zahl = erlaubter Abstand in %). Volumen x: Volumen ist ein Vielfaches des Üblichen zur gleichen Uhrzeit. Depot >= / <= und Depot Tag%: ganzes Portfolio (Ticker egal)."
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
    & $add "SHARPE" "Sharpe-Quote" "Rendite über dem risikolosen Zins je Einheit Schwankung." "(Rendite p.a. - risikoloser Zins) / Volatilität p.a. Über 1 gilt als gut, unter 0 heißt: weniger als der sichere Zins. Hängt stark vom gewählten Zeitraum ab."
    & $add "DRAWDOWN" "Max. Drawdown" "Größter Rückgang vom bisherigen Hoch bis zum folgenden Tief." "Zeigt, wie viel ein Depot zwischenzeitlich verloren hat, bevor es sich erholt hat - aus der zeitgewichteten Wertentwicklung (Einzahlungen herausgerechnet)."
    & $add "VOLA" "Volatilität" "Schwankung der Tagesrenditen, aufs Jahr hochgerechnet." "Standardabweichung der Tagesrenditen mal Wurzel der Handelstage pro Jahr. 15 % heißt grob: in zwei von drei Jahren liegt das Ergebnis innerhalb von ±15 % um den Durchschnitt."
    & $add "BETA" "Beta" "Wie stark das Depot mit der Benchmark mitgeht." "1 = bewegt sich im Schnitt wie die Benchmark, 1,5 = um 50 % stärker, 0,5 = halb so stark. Aus den Tagesrenditen im gewählten Zeitraum."
    & $add "REBAL" "Rebalancing" "Zurück zu den gewünschten Anteilen kaufen / verkaufen." "Für Positionen mit Ziel-Anteil rechnet das Widget aus, wie viel zu kaufen oder zu verkaufen wäre. 'Nur kaufen' verteilt neues Geld (und Cash) auf die untergewichteten Positionen, ohne zu verkaufen."
    & $add "CASH" "Cash-Konto" "Kontostand des Depots, bewegt durch Käufe, Verkäufe, Dividenden und Einzahlungen." "Beim Einschalten trägst du den heutigen Kontostand ein. Danach ziehen neue Käufe Kurs x Stück + Gebühr ab, Verkäufe bringen den Erlös, Dividenden den Nettobetrag. Ein- und Auszahlungen, Zinsen und Gebühren bucht man im Cash-Fenster."
    & $add "XIRR" "Rendite p.a. (XIRR)" "Geldgewichtete Jahresrendite deiner Ein- und Auszahlungen." "Interner Zinsfuß: die Jahresrendite, die alle Käufe (Auszahlungen), Verkäufe und Dividenden (Einzahlungen) plus den heutigen Wert genau ausgleicht. Berücksichtigt, wann wie viel Geld investiert war. Bei weniger als 30 Tagen Haltedauer nicht aussagekräftig und daher ausgeblendet."
    & $add "NETINVEST" "Netto investiert" "Käufe minus Verkaufserlöse, zum Kurs am Buchungstag." "Summe aller Käufe inklusive Gebühren minus aller Verkaufserlöse, jeweils mit dem Wechselkurs am Buchungstag in die Basiswährung umgerechnet. Liegt die Wertkurve darüber, bist du insgesamt im Plus."
    & $add "BENCHMARK" "Benchmark (Schattendepot)" "Was dein Geld im Vergleichsindex gemacht hätte." "Jeder Kauf und Verkauf deines Depots wird zum selben Tag mit demselben Betrag im Vergleichs-ETF (Standard: iShares Core MSCI World, EUNL.DE) nachgespielt. So vergleichst du fair: gleiche Beträge, gleiche Zeitpunkte. Thesaurierende ETFs enthalten ihre Ausschüttungen im Kurs."
    & $add "UNREALIZED" "Unrealisiert" "Buchgewinn/-verlust der offenen Stücke." "Heutiger Wert minus Einstand der noch gehaltenen Stücke, beides in der Basiswährung. Der Einstand ist der gleitende Durchschnitt zum Wechselkurs am Kauftag, Währungsgewinne sind also enthalten."
    & $add "TOTALRET" "Gesamtergebnis" "Unrealisiert + realisiert + Dividenden." "Alles, was die Position bisher gebracht hat: Buchgewinn der offenen Stücke, realisierte Gewinne/Verluste aus Verkäufen und Dividenden nach Abzügen. Die Prozentzahl bezieht sich auf alle Käufe (inkl. Gebühren)."
    & $add "ALLOCATION" "Aufteilung" "Wie sich dein Depotwert verteilt." "Depotwert nach Position, Währung, Sektor oder Land. Sektor und Land kommen von Yahoo und lassen sich je Position überschreiben (Spalten rechts). ETFs und Fonds werden als eigene Gruppe gezählt, weil sie selbst gestreut sind."
    & $add "CONCENTRATION" "Klumpenrisiko" "Zu großer Anteil in einer Gruppe." "Eine Gruppe (eine Aktie, eine Währung, ein Sektor, ein Land) hat mehr Anteil am Depot als die eingestellte Schwelle (Standard 20 %). Kein Fehler, aber ein Hinweis: ein Rückschlag dort trifft das ganze Depot stark."
    & $add "SPLIT" "Aktiensplit" "Mehr Stück zum geringeren Kurs, Wert unverändert." "Bei einem Split (z. B. NVIDIA 10:1 im Juni 2024) wird jede Aktie in mehrere geteilt. Historische Kurse von Yahoo sind bereits angepasst; Buchungen vor dem Split rechnet das Widget automatisch mit dem Split-Verhältnis um."
    # v4.2: dividends, events, buy dates
    & $add "DIVYIELD" "Dividendenrendite" "Erwartete Jahresdividende / aktueller Kurs." "Erwartete Dividende der nächsten 12 Monate je Aktie geteilt durch den aktuellen Kurs. Brutto, also vor Quellensteuer und KESt. Eine hohe Rendite kann auch heißen, dass der Kurs stark gefallen ist oder eine Kürzung droht."
    & $add "YOC" "Rendite auf Einstand" "Erwartete Jahresdividende / dein Kaufkurs." "Yield on Cost: erwartete Jahresdividende je Aktie geteilt durch deinen durchschnittlichen Einstandskurs. Steigt mit jeder Dividendenerhöhung, auch wenn der Kurs mitsteigt."
    & $add "EXDATE" "Ex-Tag" "Ab diesem Tag ohne Dividende gehandelt." "Wer die Aktie am Tag vor dem Ex-Tag (Schluss) hält, bekommt die Dividende. Am Ex-Tag fällt der Kurs ungefähr um die Dividende. Die Auszahlung (Zahltag) folgt meist einige Tage bis Wochen später. Mit ~ markierte Tage sind aus dem Rhythmus der letzten Zahlungen geschätzt."
    & $add "DIVFORECAST" "Dividendenprognose" "Erwartete Zahlungen der nächsten 12 Monate." "Die Zahlungen des letzten Jahres, um ein Jahr verschoben, mal deine Stückzahl, in der Basiswährung zum heutigen Wechselkurs. Nach Ex-Tag in Monate einsortiert. Eine Schätzung: Kürzungen, Erhöhungen und Sonderdividenden sind nicht enthalten, Steuern nicht abgezogen."
    & $add "EARNINGS" "Quartalszahlen" "Termin der nächsten Geschäftszahlen." "An diesem Tag veröffentlicht das Unternehmen seine Quartals- oder Jahreszahlen, oft vor Börsenbeginn oder nach Börsenschluss. Der Kurs schwankt dann meist stärker als sonst. Termin von Yahoo, manchmal noch vorläufig (Zeitraum)."
    & $add "TRAIL" "Trailing Stop" "Alarm, wenn der Kurs um X % vom Höchststand fällt." "Der Alarm merkt sich den höchsten Kurs seit dem Anlegen (bzw. seit dem letzten Wieder-scharf-Schalten). Fällt der Kurs um die eingestellten Prozent unter dieses Hoch, löst er aus. Steigt der Kurs, wandert die Stopp-Marke mit nach oben - Gewinne laufen lassen, Verluste begrenzen. Es wird nichts verkauft, nur gemeldet."
    & $add "RELVOL" "Relatives Volumen" "Heutiges Volumen im Vergleich zum Üblichen." "Umsatz heute bis jetzt geteilt durch den durchschnittlichen Umsatz der letzten Tage bis zur gleichen Uhrzeit (Stundenkerzen, nur reguläre Sitzung). 2x = doppelt so viel gehandelt wie sonst - oft ein Zeichen für Nachrichten."
    & $add "EXPIRY" "Gültig bis" "Alarm läuft automatisch ab." "Nach diesem Tag wird der Alarm nicht mehr geprüft und in der Liste als abgelaufen (EXP) angezeigt. Doppelklick schaltet ihn wieder scharf, Entf löscht ihn."
    & $add "QUIET" "Ruhezeit" "In dieser Zeit kein Ton und kein Handy-Push." "Alarme werden weiter geprüft und im Verlauf protokolliert, aber zwischen Beginn und Ende gibt es keinen Ton und keine Push-Nachricht (die Sprechblase am PC erscheint still). Über Mitternacht möglich, z. B. 22:00 bis 07:00. Gleiche Zeiten = keine Ruhezeit."
    & $add "PUSH" "Handy-Push" "Alarme aufs Handy schicken (ntfy oder Telegram)." "ntfy: kostenlose App ntfy installieren, dasselbe Thema (Topic) abonnieren wie hier eingetragen - fertig, kein Konto nötig. Das Thema ist wie ein Passwort: wer es kennt, liest mit, darum ein zufälliges nehmen. Telegram: bei @BotFather einen Bot anlegen, den Token hier eintragen, dem Bot eine Nachricht schreiben und 'Chat-ID holen' klicken. Der Token wird mit Windows (DPAPI) verschlüsselt gespeichert."
    & $add "ALERTLOG" "Alarm-Verlauf" "Liste aller ausgelösten Alarme." "Jeder Treffer wird mit Zeit, Ticker, Wert und Notiz gespeichert (die letzten 500), auch während der Ruhezeit. Ob ein Push verschickt wurde, steht in der letzten Spalte."
    & $add "EMA" "EMA" "Exponentieller gleitender Durchschnitt." "Wie der SMA ein Durchschnitt der letzten Kurse, aber neuere Kurse zählen stärker. Reagiert dadurch schneller auf Trendwechsel, schwankt aber auch mehr. Umschalten SMA/EMA in den Einstellungen (Indikatoren)."
    & $add "MACD" "MACD" "Trendfolge-Indikator aus zwei EMAs (12 / 26) und Signallinie (9)." "MACD-Linie = EMA12 minus EMA26 (blau), Signallinie = EMA9 der MACD-Linie (orange), Balken = Abstand beider. Kreuzt die MACD-Linie die Signallinie von unten, gilt das als Kaufsignal, von oben als Verkaufssignal. Über null = Aufwärtstrend. Statt RSI im unteren Feld: Einstellungen oder Befehl IND MACD."
    & $add "COLORS" "Farben Plus / Minus" "Farben für steigende und fallende Werte." "Standard: Grün / Rot. Farbenblind: Blau / Orange - gut unterscheidbar bei Rot-Grün-Schwäche. Pfeile ▲▼ zeigen die Richtung zusätzlich ohne Farbe."
    & $add "HOTKEY" "Globales Tastenkürzel" "Holt das Widget aus jedem Programm nach vorne." "Funktioniert systemweit, auch wenn ein anderes Fenster aktiv ist: einmal drücken = Widget zeigen, nochmal = verstecken. Schaltet auch 'Durchklicken' wieder aus. Format: Ctrl+Alt+W, Strg+Umschalt+F9, Win+Space."
    & $add "OPENING" "Anfangsbestand" "Nachgetragener Kauf für Stück ohne Buchung." "Für Stück, die im Portfolio-Editor eingetragen, aber nie als Kauf gebucht wurden, wird mit deinem Kaufdatum ein Kauf nachgebucht. Der Kurs wird so gewählt, dass dein EK gleich bleibt. Die Position selbst ändert sich nicht; Wertentwicklung, XIRR und Jahresreport können sie dann mitrechnen."
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

    # v5.1: per ticker value + cumulated buys / sales / dividends (attribution)
    $bySym = @{}
    $accB = @{}; $accS = @{}; $accD = @{}
    foreach ($o in $books) {
        if ($bySym.ContainsKey($o.Sym)) { continue }
        $bySym[$o.Sym] = [PSCustomObject]@{ Value = (New-Object double[] $n); Buys = (New-Object double[] $n); Sells = (New-Object double[] $n); Divs = (New-Object double[] $n) }
        $accB[$o.Sym] = 0.0; $accS[$o.Sym] = 0.0; $accD[$o.Sym] = 0.0
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
                        $accB[$s] += $cv.Value
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
                        $accS[$s] += $pr.Value
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
                        $accD[$s] += $gr.Value
                    }
                }
            }
            $b++
        }
        $tot = 0.0
        foreach ($s in $syms) {
            if ($shares[$s] -gt 0 -and $valBase.ContainsKey($s)) {
                $px = $valBase[$s][$j]
                if (-not [double]::IsNaN($px)) { $tot += $shares[$s] * $px; $bySym[$s].Value[$j] = $shares[$s] * $px }
            }
        }
        foreach ($s in $bySym.Keys) { $bySym[$s].Buys[$j] = $accB[$s]; $bySym[$s].Sells[$j] = $accS[$s]; $bySym[$s].Divs[$j] = $accD[$s] }
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
        BySym        = $bySym
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

function Get-Contributions {
    # v5.1: what each position added to the depot result between two points of
    # the value series: end value + sales + dividends - start value - buys.
    # Pct = modified Dietz return of the position (half the net flow counts).
    param($BySym, [int]$Start, [int]$End)
    $rows = New-Object System.Collections.Generic.List[PSObject]
    $total = 0.0
    foreach ($s in @($BySym.Keys | Sort-Object)) {
        $x = $BySym[$s]
        $n = @($x.Value).Count
        if ($n -eq 0) { continue }
        $a = [math]::Max(0, [math]::Min($Start, $n - 1)); $b = [math]::Max($a, [math]::Min($End, $n - 1))
        $v0 = [double]$x.Value[$a]; $v1 = [double]$x.Value[$b]
        $buy = [double]$x.Buys[$b] - [double]$x.Buys[$a]
        $sell = [double]$x.Sells[$b] - [double]$x.Sells[$a]
        $div = [double]$x.Divs[$b] - [double]$x.Divs[$a]
        if ($v0 -eq 0 -and $v1 -eq 0 -and $buy -eq 0 -and $sell -eq 0 -and $div -eq 0) { continue }
        $c = $v1 + $sell + $div - $v0 - $buy
        $den = $v0 + 0.5 * ($buy - $sell)
        $pct = if ($den -gt 0) { $c / $den * 100.0 } else { [double]::NaN }
        $rows.Add([PSCustomObject]@{ Sym = $s; Start = $v0; End = $v1; Buys = $buy; Sells = $sell; Divs = $div; Contribution = $c; Pct = $pct; Share = [double]::NaN })
        $total += $c
    }
    foreach ($r in $rows) { if ([math]::Abs($total) -gt 1e-9) { $r.Share = $r.Contribution / [math]::Abs($total) * 100.0 } }
    $sorted = @($rows | Sort-Object -Property @{ Expression = { [double]$_.Contribution }; Descending = $true }, @{ Expression = { [string]$_.Sym }; Descending = $false })
    return [PSCustomObject]@{ Rows = $sorted; Total = $total }
}

function Get-ScenarioImpact {
    # v5.1: rough what-if: market moves MarketPct, each position by beta x that.
    # Positions without a beta count with 1.0 (flagged).
    param([array]$Positions, [double]$MarketPct)
    $rows = @()
    $tot = 0.0; $val = 0.0
    foreach ($p in @($Positions)) {
        if ($null -eq $p) { continue }
        $b = [double]$p.Beta
        $est = [double]::IsNaN($b)
        if ($est) { $b = 1.0 }
        $chg = [double]$p.Value * $b * $MarketPct / 100.0
        $rows += [PSCustomObject]@{ Sym = [string]$p.Sym; Value = [double]$p.Value; Beta = $b; BetaAssumed = $est; Change = $chg }
        $tot += $chg; $val += [double]$p.Value
    }
    return [PSCustomObject]@{ Rows = @($rows | Sort-Object -Property @{ Expression = { [double]$_.Change }; Descending = $false }); Change = $tot; Value = $val; Pct = $(if ($val -gt 0) { $tot / $val * 100.0 } else { 0.0 }) }
}

function Get-RollingReturns {
    # v5.1: return over a window of Days calendar days, for every point that
    # has such a window behind it. Values = index series (e.g. TWR growth).
    param([string[]]$Dates, [double[]]$Values, [int]$Days = 365)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $outD = New-Object System.Collections.Generic.List[string]
    $outV = New-Object System.Collections.Generic.List[double]
    $n = @($Dates).Count
    if ($n -lt 2) { return [PSCustomObject]@{ Dates = @(); Values = @() } }
    $j = 0
    for ($i = 0; $i -lt $n; $i++) {
        $from = [DateTime]::ParseExact($Dates[$i], "yyyy-MM-dd", $inv).AddDays(-$Days).ToString("yyyy-MM-dd")
        if ([string]::CompareOrdinal($Dates[0], $from) -gt 0) { continue }
        while (($j + 1) -lt $n -and [string]::CompareOrdinal($Dates[$j + 1], $from) -le 0) { $j++ }
        if ($Values[$j] -gt 0) { $outD.Add($Dates[$i]); $outV.Add(($Values[$i] / $Values[$j] - 1.0) * 100.0) }
    }
    return [PSCustomObject]@{ Dates = $outD.ToArray(); Values = $outV.ToArray() }
}

function Get-TwrIndex {
    # v5.1: time-weighted growth index (start 100) aligned with the value
    # series; buys / sales are taken out like in Get-FlowAdjustedReturns.
    # Without Invested it is simply Value rebased to 100 (benchmarks).
    param([double[]]$Value, [double[]]$Invested = $null, [double[]]$Dividends = $null, [int]$Start = 0)
    $n = @($Value).Count
    $out = New-Object double[] $n
    for ($i = 0; $i -lt $n; $i++) { $out[$i] = [double]::NaN }
    if ($n -eq 0 -or $Start -ge $n) { return ,$out }
    $out[$Start] = 100.0
    for ($i = $Start + 1; $i -lt $n; $i++) {
        $v0 = [double]$Value[$i - 1]; $v1 = [double]$Value[$i]
        if ($v0 -le 0 -or [double]::IsNaN($v0) -or [double]::IsNaN($v1)) { $out[$i] = $out[$i - 1]; continue }
        $dI = if ($null -ne $Invested -and $Invested.Count -gt $i) { [double]$Invested[$i] - [double]$Invested[$i - 1] } else { 0.0 }
        $dD = if ($null -ne $Dividends -and $Dividends.Count -gt $i) { [double]$Dividends[$i] - [double]$Dividends[$i - 1] } else { 0.0 }
        $out[$i] = $out[$i - 1] * (($v1 + $dD - $dI) / $v0)
    }
    return ,$out
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

# ==============================================================================
# v4.2 additions: buy dates, dividends, earnings
# ==============================================================================

# ------------------------------------------------------------------------------
# Buy date of positions without bookings -> opening booking
# ------------------------------------------------------------------------------
function ConvertTo-IsoDate {
    # "24.11.2025", "24.11.25", "2025-11-24", "24/11/2025" -> "2025-11-24"; "" if invalid
    param([string]$Text)
    $t = ([string]$Text).Trim()
    if (-not $t) { return "" }
    $formats = [string[]]@("dd.MM.yyyy", "d.M.yyyy", "dd.MM.yy", "d.M.yy", "yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy", "yyyyMMdd", "yyyy/MM/dd", "dd-MM-yyyy")
    $d = [DateTime]::MinValue
    if ([DateTime]::TryParseExact($t, $formats, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) {
        return $d.ToString("yyyy-MM-dd")
    }
    return ""
}

function Get-OpeningBooking {
    # Buy that explains the shares a position has beyond its bookings. The
    # price keeps the position's average as the editor shows it:
    # (all shares x EK - booked shares x booked average) / missing shares.
    # $null when nothing is missing.
    param([double]$Shares, [double]$AvgPrice, [double]$BookedShares = 0, [double]$BookedAvg = 0)
    $miss = $Shares - $BookedShares
    if ($miss -le 0.000001) { return $null }
    $px = (($Shares * $AvgPrice) - ($BookedShares * $BookedAvg)) / $miss
    if ([double]::IsNaN($px) -or [double]::IsInfinity($px) -or $px -le 0) { $px = $AvgPrice }
    return [PSCustomObject]@{ Shares = $miss; Price = $px }
}

# ------------------------------------------------------------------------------
# Dividends: frequency, trailing 12 months, projection for the next 12 months
# Dividends = @(@{ Date = "yyyy-MM-dd"; Amount = per share }) (from the chart events)
# ------------------------------------------------------------------------------
function Get-DividendStats {
    param([array]$Dividends, [string]$AsOf = "")
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $now = if ($AsOf) { [DateTime]::ParseExact($AsOf, "yyyy-MM-dd", $inv) } else { (Get-Date).Date }
    $ev = @(@($Dividends) | Where-Object { $null -ne $_ -and [double]$_.Amount -gt 0 -and [string]::CompareOrdinal([string]$_.Date, $now.ToString("yyyy-MM-dd")) -le 0 } |
        Sort-Object -Property @{ Expression = { [string]$_.Date } })
    if ($ev.Count -eq 0) { return $null }
    $dates = @($ev | ForEach-Object { [DateTime]::ParseExact([string]$_.Date, "yyyy-MM-dd", $inv) })
    $last = $ev[$ev.Count - 1]
    $lastD = $dates[$dates.Count - 1]

    # frequency from the median gap of the last (up to) 8 payments
    $freq = 1
    $gaps = @()
    $from = [math]::Max(1, $dates.Count - 8)
    for ($i = $from; $i -lt $dates.Count; $i++) { $gaps += ($dates[$i] - $dates[$i - 1]).TotalDays }
    if ($gaps.Count -gt 0) {
        $sg = @($gaps | Sort-Object)
        $med = $sg[[int][math]::Floor(($sg.Count - 1) / 2)]
        $freq = if ($med -lt 45) { 12 } elseif ($med -lt 135) { 4 } elseif ($med -lt 250) { 2 } else { 1 }
    }
    $label = switch ($freq) { 12 { "monatlich" } 4 { "quartalsweise" } 2 { "halbjährlich" } default { "jährlich" } }

    $yearAgo = $now.AddDays(-365)
    $t12 = 0.0; $n12 = 0
    for ($i = 0; $i -lt $ev.Count; $i++) { if ($dates[$i] -gt $yearAgo) { $t12 += [double]$ev[$i].Amount; $n12++ } }
    # no payment for 1.5 cycles + a month: probably cut or suspended
    $stopped = (($now - $lastD).TotalDays -gt ((365.0 / $freq) * 1.5 + 30))
    $annual = if ($stopped) { 0.0 } elseif ($n12 -ge $freq) { $t12 } else { [double]$last.Amount * $freq }
    $next = $lastD.AddMonths([int](12 / $freq))
    $guard = 0
    while ($next -le $now -and $guard -lt 48) { $next = $next.AddMonths([int](12 / $freq)); $guard++ }
    return [PSCustomObject]@{
        Frequency = $freq; FrequencyLabel = $label
        Last = [double]$last.Amount; LastDate = [string]$last.Date
        Trailing12 = $t12; Count12 = $n12; Annual = $annual
        NextEx = $(if ($stopped) { "" } else { $next.ToString("yyyy-MM-dd") })
        Stopped = $stopped
    }
}

function Get-DividendProjection {
    # Expected payments per share in the next 12 months (by ex-date): last
    # year's payments moved forward by one year; when there were fewer than
    # the usual number, the latest amount is continued at its frequency.
    param([array]$Dividends, [string]$AsOf = "", $Stats = $null)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $now = if ($AsOf) { [DateTime]::ParseExact($AsOf, "yyyy-MM-dd", $inv) } else { (Get-Date).Date }
    $st = if ($null -ne $Stats) { $Stats } else { Get-DividendStats -Dividends $Dividends -AsOf $now.ToString("yyyy-MM-dd") }
    if ($null -eq $st -or $st.Stopped) { return @() }
    $end = $now.AddDays(365)
    $out = New-Object System.Collections.Generic.List[PSObject]
    foreach ($e in @($Dividends)) {
        if ($null -eq $e -or [double]$e.Amount -le 0) { continue }
        $d = [DateTime]::ParseExact([string]$e.Date, "yyyy-MM-dd", $inv)
        if ($d -le $now -and $d -gt $now.AddDays(-365)) {
            $pd = $d.AddYears(1)
            if ($pd -gt $now -and $pd -le $end) { $out.Add([PSCustomObject]@{ Date = $pd.ToString("yyyy-MM-dd"); Amount = [double]$e.Amount }) }
        }
    }
    if ($out.Count -lt $st.Frequency) {
        $step = [int](12 / $st.Frequency)
        $d = [DateTime]::ParseExact($st.LastDate, "yyyy-MM-dd", $inv).AddMonths($step)
        $guard = 0
        while ($d -le $end -and $guard -lt 60) {
            if ($d -gt $now) {
                $dup = $false
                foreach ($o in $out) { if ([math]::Abs(([DateTime]::ParseExact($o.Date, "yyyy-MM-dd", $inv) - $d).TotalDays) -lt 20) { $dup = $true; break } }
                if (-not $dup) { $out.Add([PSCustomObject]@{ Date = $d.ToString("yyyy-MM-dd"); Amount = $st.Last }) }
            }
            $d = $d.AddMonths($step)
            $guard++
        }
    }
    return @($out | Sort-Object -Property @{ Expression = { [string]$_.Date } })
}

function Get-MonthlyBuckets {
    # Items with Date and Value -> 12 calendar months from the month of AsOf
    param([array]$Items, [string]$AsOf = "", [int]$Months = 12)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $now = if ($AsOf) { [DateTime]::ParseExact($AsOf, "yyyy-MM-dd", $inv) } else { (Get-Date).Date }
    $names = @("Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez")
    $first = New-Object DateTime($now.Year, $now.Month, 1)
    $out = @()
    $idx = @{}
    for ($i = 0; $i -lt $Months; $i++) {
        $m = $first.AddMonths($i)
        $key = $m.ToString("yyyy-MM")
        $idx[$key] = $i
        $out += [PSCustomObject]@{ Month = $key; Label = ("{0} {1}" -f $names[$m.Month - 1], $m.ToString("yy")); Value = 0.0 }
    }
    foreach ($it in @($Items)) {
        if ($null -eq $it -or -not $it.Date) { continue }
        $k = ([string]$it.Date).Substring(0, 7)
        if ($idx.ContainsKey($k)) { $out[$idx[$k]].Value += [double]$it.Value }
    }
    return $out
}

# ------------------------------------------------------------------------------
# Earnings / dividend dates from Yahoo quoteSummary (calendarEvents,
# summaryDetail) - needs the crumb; without it the dividend dates are estimated
# ------------------------------------------------------------------------------
function ConvertFrom-YahooCalendar {
    param($Summary, [string]$AsOf = "")
    $o = [PSCustomObject]@{
        EarningsDate = ""; EarningsEnd = ""; ExDividendDate = ""; DividendDate = ""
        DividendRate = [double]::NaN; DividendYield = [double]::NaN; TrailingRate = [double]::NaN
        # v4.9.5: analysts (module financialData)
        TargetMean = [double]::NaN; TargetHigh = [double]::NaN; TargetLow = [double]::NaN
        RecMean = [double]::NaN; RecKey = ""; Analysts = [double]::NaN
    }
    $r = $null
    try { $r = $Summary.quoteSummary.result[0] } catch { $r = $null }
    if ($null -eq $r) { return $o }
    $today = if ($AsOf) { $AsOf } else { (Get-Date).ToString("yyyy-MM-dd") }
    $num = {
        param($V)
        if ($null -eq $V) { return [double]::NaN }
        if ($V -is [ValueType]) { return [double]$V }
        if ($null -ne $V.raw) { return [double]$V.raw }
        return [double]::NaN
    }
    $date = {
        param($V)
        $n = & $num $V
        if ([double]::IsNaN($n) -or $n -le 0) { return "" }
        return [DateTimeOffset]::FromUnixTimeSeconds([long]$n).UtcDateTime.ToString("yyyy-MM-dd")
    }
    $ce = $r.calendarEvents
    if ($null -ne $ce) {
        if ($null -ne $ce.earnings -and $null -ne $ce.earnings.earningsDate) {
            $ed = @(@($ce.earnings.earningsDate) | ForEach-Object { & $date $_ } | Where-Object { $_ } | Sort-Object)
            $fut = @($ed | Where-Object { [string]::CompareOrdinal($_, $today) -ge 0 })
            if ($fut.Count -gt 0) { $o.EarningsDate = $fut[0]; if ($fut.Count -gt 1) { $o.EarningsEnd = $fut[$fut.Count - 1] } }
            elseif ($ed.Count -gt 0) { $o.EarningsDate = $ed[$ed.Count - 1] }
        }
        $o.ExDividendDate = & $date $ce.exDividendDate
        $o.DividendDate = & $date $ce.dividendDate
    }
    $sd = $r.summaryDetail
    if ($null -ne $sd) {
        $o.DividendRate = & $num $sd.dividendRate
        $o.DividendYield = & $num $sd.dividendYield
        $o.TrailingRate = & $num $sd.trailingAnnualDividendRate
        if (-not $o.ExDividendDate) { $o.ExDividendDate = & $date $sd.exDividendDate }
    }
    $fd = $r.financialData
    if ($null -ne $fd) {
        $o.TargetMean = & $num $fd.targetMeanPrice
        $o.TargetHigh = & $num $fd.targetHighPrice
        $o.TargetLow  = & $num $fd.targetLowPrice
        $o.RecMean    = & $num $fd.recommendationMean
        $o.Analysts   = & $num $fd.numberOfAnalystOpinions
        $rk = ([string]$fd.recommendationKey).Trim().ToLowerInvariant()
        if ($rk -and $rk -ne "none") { $o.RecKey = $rk }
    }
    return $o
}

function Get-ConsensusLabel {
    # v4.9.5: Yahoo recommendationKey -> short German label
    param([string]$Key, [switch]$Long)
    $map = @{
        "strong_buy"   = @("Kauf+", "Starker Kauf")
        "buy"          = @("Kauf", "Kaufen")
        "hold"         = @("Halten", "Halten")
        "underperform" = @("Schwach", "Untergewichten")
        "sell"         = @("Verkauf", "Verkaufen")
        "strong_sell"  = @("Verkauf+", "Starker Verkauf")
    }
    $k = ([string]$Key).Trim().ToLowerInvariant()
    if (-not $map.ContainsKey($k)) { return "" }
    if ($Long) { return $map[$k][1] }
    return $map[$k][0]
}

function Get-TargetUpside {
    # Analyst mean target vs. price in % (NaN when one is missing)
    param([double]$Target, [double]$Price)
    if ([double]::IsNaN($Target) -or [double]::IsNaN($Price) -or $Target -le 0 -or $Price -le 0) { return [double]::NaN }
    return ($Target / $Price - 1.0) * 100.0
}

function Get-RangePosition {
    # v4.9.5: where the price sits in the 52-week range: 0 = low, 1 = high
    # (clamped); NaN without a valid range
    param([double]$Price, [double]$Low, [double]$High)
    if ([double]::IsNaN($Price) -or $Low -le 0 -or $High -le 0 -or $High -le $Low -or $Price -le 0) { return [double]::NaN }
    $f = ($Price - $Low) / ($High - $Low)
    return [math]::Max(0.0, [math]::Min(1.0, $f))
}

function Get-EarningsBadge {
    # Quarterly figures within WindowDays: @{ Days; Text; Date }, else $null
    param([string]$EarningsDate, [string]$AsOf = "", [int]$WindowDays = 7)
    if (-not $EarningsDate) { return $null }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $now = if ($AsOf) { [DateTime]::ParseExact($AsOf, "yyyy-MM-dd", $inv) } else { (Get-Date).Date }
    $d = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact($EarningsDate, "yyyy-MM-dd", $inv, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $null }
    $days = [int]($d - $now).TotalDays
    if ($days -lt 0 -or $days -gt $WindowDays) { return $null }
    $txt = if ($days -eq 0) { "heute" } elseif ($days -eq 1) { "morgen" } else { "in $days T" }
    return [PSCustomObject]@{ Days = $days; Text = $txt; Date = $EarningsDate }
}

function Test-EventsStale {
    # Earnings / dividend dates are refreshed about once a day
    param($Entry, [int]$MaxHours = 20, [DateTime]$Now = (Get-Date))
    if ($null -eq $Entry -or -not $Entry.FetchedAt) { return $true }
    $t = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$Entry.FetchedAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$t)) { return $true }
    return (($Now - $t).TotalHours -gt $MaxHours)
}

function Get-SplitFactorAfter {
    # Product of all split ratios AFTER Date: a booking on Date for N of
    # today's shares is N / factor shares at price x factor in its own time
    param([hashtable]$Splits, [string]$Ticker, [string]$Date)
    $f = 1.0
    foreach ($sp in @(Get-SplitEvents -Splits $Splits -Ticker $Ticker)) {
        if ([string]::CompareOrdinal([string]$sp.Date, $Date) -gt 0) { $f *= [double]$sp.Ratio }
    }
    return $f
}

# ==============================================================================
# v4.3: more alert types, quiet hours, expiry, phone push
# ==============================================================================

# Alert kinds by condition text (the order matters: "Depot Tag% >=" is a
# portfolio alert, "Tag% >=" a ticker alert)
function Get-AlertKind {
    param([string]$Condition)
    if ($Condition -like "Depot Tag%*") { return "PFPCT" }
    if ($Condition -like "Depot*")      { return "PFVAL" }
    if ($Condition -like "Tag%*")       { return "PCT" }
    if ($Condition -like "RSI*")        { return "RSI" }
    if ($Condition -like "*SMA")        { return "SMA" }
    if ($Condition -like "Trailing*")   { return "TRAIL" }
    if ($Condition -like "EK%*")        { return "EKPCT" }
    if ($Condition -eq "52W Hoch")      { return "HIGH52" }
    if ($Condition -eq "52W Tief")      { return "LOW52" }
    if ($Condition -like "Volumen*")    { return "VOL" }
    if ($Condition -like "Trend*")      { return "TREND" }   # v5.0: trend line from the chart
    return "PRICE"
}

function Get-AlertConditions {
    return @(">=", "<=", "Tag% >=", "Tag% <=", "RSI >=", "RSI <=", "> SMA", "< SMA",
             "Trailing %", "EK% >=", "EK% <=", "52W Hoch", "52W Tief", "Volumen x",
             "Depot >=", "Depot <=", "Depot Tag% >=", "Depot Tag% <=")
}

function Test-PortfolioAlertKind {
    param([string]$Kind)
    return ($Kind -eq "PFVAL" -or $Kind -eq "PFPCT")
}

function Get-AlertTargetHint {
    # What the number field means for a condition (placeholder / tooltip)
    param([string]$Condition)
    switch (Get-AlertKind $Condition) {
        "PCT"    { return "Tagesänderung in %, z. B. 5 oder -3" }
        "RSI"    { return "RSI-Wert 0-100, z. B. 70" }
        "SMA"    { return "keine Zahl nötig" }
        "TRAIL"  { return "Rückgang vom Höchstkurs in %, z. B. 8" }
        "EKPCT"  { return "Gewinn/Verlust zum Einstand in %, z. B. 20 oder -10" }
        "HIGH52" { return "Abstand zum 52W-Hoch in %, 0 = neues Hoch" }
        "LOW52"  { return "Abstand zum 52W-Tief in %, 0 = neues Tief" }
        "VOL"    { return "Vielfaches des normalen Volumens, z. B. 2" }
        "PFVAL"  { return "Depotwert in der Anzeigewährung" }
        "PFPCT"  { return "Tagesänderung des Depots in %" }
        default  { return "Kurs in der gewählten Währung" }
    }
}

function Get-AlertEvaluation {
    # Pure alert check. $Ctx (all optional, NaN = unknown):
    #   Price (in the alert currency), QuotePrice, High52, Low52 (quote currency),
    #   ChangePct, Rsi, Sma, AvgCost (alert currency), RelVol,
    #   PfValue (alert currency), PfDayPct, RsiPeriod, SmaPeriod
    # Returns @{ Ok; Value; Met; Text; Peak } - Peak = new trailing high
    param($Alert, [hashtable]$Ctx)
    $res = @{ Ok = $false; Value = [double]::NaN; Met = $false; Text = ""; Peak = [double]::NaN }
    $cond = [string]$Alert.Condition
    $t = [double]$Alert.TargetPrice
    $get = { param([string]$K) if ($Ctx.ContainsKey($K) -and $null -ne $Ctx[$K]) { return [double]$Ctx[$K] } return [double]::NaN }
    $cmp = {
        param([double]$V, [string]$Op)
        return (($Op -like "*>=*" -and $V -ge $t) -or ($Op -like "*<=*" -and $V -le $t))
    }
    $cur = [string]$Alert.Currency
    switch (Get-AlertKind $cond) {
        "TREND" {
            # v5.0: the target moves along a trend line (T1/P1, T2/P2 in ms / alert currency)
            $v = & $get "Price"; if ([double]::IsNaN($v)) { return $res }
            $nowMs = & $get "NowMs"
            if ([double]::IsNaN($nowMs)) { $nowMs = [double][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
            $line = Get-TrendPriceAt -T1 ([long]$Alert.T1) -P1 ([double]$Alert.P1) -T2 ([long]$Alert.T2) -P2 ([double]$Alert.P2) -T ([long]$nowMs)
            if ([double]::IsNaN($line)) { return $res }
            $t = $line
            $res.Ok = $true; $res.Value = $v; $res.Met = & $cmp $v $cond
            $res.Text = "Kurs {0:N2} {1} vs. Trendlinie {2:N2} ({3})" -f $v, $cur, $line, $cond
        }
        "PCT" {
            $v = & $get "ChangePct"; if ([double]::IsNaN($v)) { return $res }
            $res.Ok = $true; $res.Value = $v; $res.Met = & $cmp $v $cond
            $res.Text = "Tagesänderung {0:+0.00;-0.00}% (Ziel {1} {2:N2}%)" -f $v, $cond.Substring(4).Trim(), $t
        }
        "RSI" {
            $v = & $get "Rsi"; if ([double]::IsNaN($v)) { return $res }
            $res.Ok = $true; $res.Value = $v; $res.Met = & $cmp $v $cond
            $res.Text = "RSI-{0} (1h) {1:N1} (Ziel {2} {3:N1})" -f [int](& $get "RsiPeriod"), $v, $cond.Substring(3).Trim(), $t
        }
        "SMA" {
            $sma = & $get "Sma"; $qp = & $get "QuotePrice"
            if ([double]::IsNaN($sma) -or $sma -le 0 -or [double]::IsNaN($qp)) { return $res }
            $dist = (($qp / $sma) - 1.0) * 100.0
            $res.Ok = $true; $res.Value = $dist
            $res.Met = if ($cond -like ">*") { $qp -gt $sma } else { $qp -lt $sma }
            $res.Text = "Kurs {0:N2} vs. SMA{1} (1h) {2:N2} ({3:+0.00;-0.00}%)" -f $qp, [int](& $get "SmaPeriod"), $sma, $dist
        }
        "TRAIL" {
            $px = & $get "Price"; if ([double]::IsNaN($px) -or $px -le 0 -or $t -le 0) { return $res }
            $peak = [double]$Alert.Peak
            if ([double]::IsNaN($peak) -or $peak -le 0 -or $px -gt $peak) { $peak = $px }
            $drop = (($px / $peak) - 1.0) * 100.0
            $stop = $peak * (1.0 - $t / 100.0)
            $res.Ok = $true; $res.Value = $drop; $res.Peak = $peak
            $res.Met = ($px -le $stop)
            $res.Text = "Kurs {0:N2} {1}, Hoch seit Start {2:N2} ({3:+0.00;-0.00}%), Stopp bei {4:N2}" -f $px, $cur, $peak, $drop, $stop
        }
        "EKPCT" {
            $px = & $get "Price"; $avg = & $get "AvgCost"
            if ([double]::IsNaN($px) -or [double]::IsNaN($avg) -or $avg -le 0) { return $res }
            $v = (($px / $avg) - 1.0) * 100.0
            $res.Ok = $true; $res.Value = $v; $res.Met = & $cmp $v $cond
            $res.Text = "Kurs {0:N2} {1} = {2:+0.00;-0.00}% zum EK {3:N2} (Ziel {4} {5:N1}%)" -f $px, $cur, $v, $avg, $cond.Substring(3).Trim(), $t
        }
        "HIGH52" {
            $qp = & $get "QuotePrice"; $h = & $get "High52"
            if ([double]::IsNaN($qp) -or [double]::IsNaN($h) -or $h -le 0) { return $res }
            $v = (($qp / $h) - 1.0) * 100.0
            $res.Ok = $true; $res.Value = $v
            $res.Met = ($qp -ge $h * (1.0 - [math]::Abs($t) / 100.0) - 1e-9)
            $res.Text = "Kurs {0:N2}, 52W-Hoch {1:N2} ({2:+0.00;-0.00}%)" -f $qp, $h, $v
        }
        "LOW52" {
            $qp = & $get "QuotePrice"; $l = & $get "Low52"
            if ([double]::IsNaN($qp) -or [double]::IsNaN($l) -or $l -le 0) { return $res }
            $v = (($qp / $l) - 1.0) * 100.0
            $res.Ok = $true; $res.Value = $v
            $res.Met = ($qp -le $l * (1.0 + [math]::Abs($t) / 100.0) + 1e-9)
            $res.Text = "Kurs {0:N2}, 52W-Tief {1:N2} ({2:+0.00;-0.00}%)" -f $qp, $l, $v
        }
        "VOL" {
            $rv = & $get "RelVol"; if ([double]::IsNaN($rv) -or $t -le 0) { return $res }
            $res.Ok = $true; $res.Value = $rv; $res.Met = ($rv -ge $t)
            $res.Text = "Volumen {0:N1}x so hoch wie üblich um diese Zeit (Ziel {1:N1}x)" -f $rv, $t
        }
        "PFVAL" {
            $v = & $get "PfValue"; if ([double]::IsNaN($v)) { return $res }
            $res.Ok = $true; $res.Value = $v; $res.Met = & $cmp $v $cond
            $res.Text = "Depotwert {0:N2} {1} (Ziel {2} {3:N2})" -f $v, $cur, $cond.Substring(5).Trim(), $t
        }
        "PFPCT" {
            $v = & $get "PfDayPct"; if ([double]::IsNaN($v)) { return $res }
            $res.Ok = $true; $res.Value = $v; $res.Met = & $cmp $v $cond
            $res.Text = "Depot heute {0:+0.00;-0.00}% (Ziel {1} {2:N2}%)" -f $v, $cond.Substring(10).Trim(), $t
        }
        default {
            $v = & $get "Price"; if ([double]::IsNaN($v)) { return $res }
            $res.Ok = $true; $res.Value = $v; $res.Met = & $cmp $v $cond
            $res.Text = "Kurs {0:N2} {1} (Ziel {2} {3:N2})" -f $v, $cur, $cond, $t
        }
    }
    return $res
}

# ---- alert overview and editing (v10.8) --------------------------------------
function Get-AlertDistance {
    # How far an alert is from firing, from the current value of its evaluation.
    # Gap is signed (the direction the value still has to move). Score is only
    # for sorting: roughly "percent to go". Unit: "%" price move, "P" points, "x".
    param([string]$Condition, [double]$Target, [double]$Value, [bool]$Met = $false)
    $res = [PSCustomObject]@{ Ok = $false; Gap = 0.0; Unit = "%"; Score = [double]::MaxValue }
    if ($Met) { $res.Ok = $true; $res.Score = 0.0; return $res }
    if ([double]::IsNaN($Value)) { return $res }
    switch (Get-AlertKind $Condition) {
        "TREND"  { return $res }   # the target moves with the line
        "SMA"    { $res.Gap = -$Value }
        "TRAIL"  { $res.Gap = -[math]::Abs($Target) - $Value }
        "HIGH52" { $res.Gap = -[math]::Abs($Target) - $Value }
        "LOW52"  { $res.Gap = [math]::Abs($Target) - $Value }
        "PCT"    { $res.Gap = $Target - $Value }
        "PFPCT"  { $res.Gap = $Target - $Value }
        "EKPCT"  {
            if ($Value -le -100) { return $res }
            $res.Gap = ((1.0 + $Target / 100.0) / (1.0 + $Value / 100.0) - 1.0) * 100.0
        }
        "RSI"    { $res.Gap = $Target - $Value; $res.Unit = "P" }
        "VOL"    { $res.Gap = $Target - $Value; $res.Unit = "x" }
        default  {
            if ($Value -le 0) { return $res }
            $res.Gap = ($Target - $Value) / $Value * 100.0
        }
    }
    $res.Ok = $true
    $res.Score = switch ($res.Unit) {
        "P" { [math]::Abs($res.Gap) / 2.0 }
        "x" { if ($Target -gt 0) { [math]::Abs($res.Gap) / $Target * 100.0 } else { [math]::Abs($res.Gap) } }
        default { [math]::Abs($res.Gap) }
    }
    return $res
}

function Get-AlertStatusName {
    # Expired / Paused / Hit / Active
    param($Alert, [DateTime]$Now = (Get-Date))
    if (Test-AlertExpired -Alert $Alert -Now $Now) { return "Expired" }
    if (Test-AlertSnoozed -Alert $Alert -Now $Now) { return "Paused" }
    if ([bool]$Alert.Triggered) { return "Hit" }
    return "Active"
}

function Update-AlertSettings {
    # changes an existing alert -> "" or an error text (then nothing changes).
    # A new target arms the alert again; a new note or repeat time does not.
    param($Alert, [double]$Value, [double]$Value2 = 0, [string]$Note = "", [int]$RearmMin = 0, [string]$ExpiresAt = "", [bool]$Push = $true)
    $kind = Get-AlertKind ([string]$Alert.Condition)
    $fixed = @("SMA", "TREND")
    if ($kind -notin $fixed) {
        $bad = Test-AlertValue -Condition ([string]$Alert.Condition) -Value $Value
        if ($bad) { return $bad }
    }
    $cond2 = [string]$Alert.Condition2
    if ($cond2 -and (Get-AlertKind $cond2) -notin $fixed) {
        $bad = Test-AlertValue -Condition $cond2 -Value $Value2
        if ($bad) { return $bad }
    }
    $changed = $false
    if ($kind -notin $fixed -and [double]$Alert.TargetPrice -ne $Value) { $Alert.TargetPrice = $Value; $changed = $true }
    if ($cond2 -and (Get-AlertKind $cond2) -notin $fixed -and [double]$Alert.Target2 -ne $Value2) { $Alert.Target2 = $Value2; $changed = $true }
    $oldEnd = [string]$Alert.ExpiresAt
    foreach ($pair in @(@("Note", $Note.Trim()), @("RearmMin", $RearmMin), @("ExpiresAt", $ExpiresAt), @("Push", $Push))) {
        $Alert | Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1] -Force
    }
    # an alert that had run out and gets a new end starts fresh
    if ($changed -or ($oldEnd -ne $ExpiresAt -and $oldEnd -and [string]::CompareOrdinal((Get-Date).ToString("yyyy-MM-dd"), $oldEnd) -gt 0)) {
        $Alert.Triggered = $false; $Alert.TriggeredAt = ""
    }
    return ""
}

function Get-RelativeVolume {
    # Today's volume so far / average volume of the previous days up to the
    # same time of day (regular-session bars only). NaN when not computable.
    param([long[]]$Ts, [double[]]$Vol, [int]$GmtOffset = 0)
    $n = [math]::Min(@($Ts).Count, @($Vol).Count)
    if ($n -lt 2) { return [double]::NaN }
    $days = [ordered]@{}
    for ($i = 0; $i -lt $n; $i++) {
        $loc = [long]$Ts[$i] + $GmtOffset
        $day = [long][math]::Floor($loc / 86400.0)
        $tod = $loc - $day * 86400
        # string keys: an integer key would hit the "by position" indexer
        $dk = "d" + $day
        if (-not $days.Contains($dk)) { $days[$dk] = New-Object System.Collections.Generic.List[double[]] }
        $days[$dk].Add([double[]]@($tod, [double]$Vol[$i]))
    }
    $keys = @($days.Keys)
    if ($keys.Count -lt 2) { return [double]::NaN }
    $today = $days[$keys[$keys.Count - 1]]
    $lastTod = $today[$today.Count - 1][0]
    $todayVol = 0.0
    foreach ($b in $today) { $todayVol += $b[1] }
    $sum = 0.0; $cnt = 0
    for ($k = 0; $k -lt $keys.Count - 1; $k++) {
        $s = 0.0
        foreach ($b in $days[$keys[$k]]) { if ($b[0] -le $lastTod) { $s += $b[1] } }
        if ($s -gt 0) { $sum += $s; $cnt++ }
    }
    if ($cnt -eq 0 -or $sum -le 0) { return [double]::NaN }
    return ($todayVol / ($sum / $cnt))
}

function Test-QuietHours {
    # "22:00" - "07:00" (over midnight allowed); empty or equal = never quiet
    param([string]$From, [string]$To, [DateTime]$Now = (Get-Date))
    $f = [TimeSpan]::Zero; $t = [TimeSpan]::Zero
    if (-not [TimeSpan]::TryParse([string]$From, [ref]$f) -or -not [TimeSpan]::TryParse([string]$To, [ref]$t)) { return $false }
    if ($f -eq $t) { return $false }
    $n = $Now.TimeOfDay
    if ($f -lt $t) { return ($n -ge $f -and $n -lt $t) }
    return ($n -ge $f -or $n -lt $t)
}

function Get-AlertExpiryChoices {
    return [ordered]@{ "unbegrenzt" = 0; "heute" = 1; "1 Woche" = 7; "1 Monat" = 31; "3 Monate" = 92 }
}

function Get-AlertExpiryDate {
    # Days from Get-AlertExpiryChoices -> last valid day (yyyy-MM-dd), "" = no end
    param([int]$Days, [DateTime]$Now = (Get-Date))
    if ($Days -le 0) { return "" }
    if ($Days -eq 1) { return $Now.ToString("yyyy-MM-dd") }
    if ($Days -eq 31) { return $Now.AddMonths(1).ToString("yyyy-MM-dd") }
    if ($Days -eq 92) { return $Now.AddMonths(3).ToString("yyyy-MM-dd") }
    return $Now.AddDays($Days).ToString("yyyy-MM-dd")
}

function Test-AlertExpired {
    param($Alert, [DateTime]$Now = (Get-Date))
    $e = [string]$Alert.ExpiresAt
    if (-not $e) { return $false }
    return ([string]::CompareOrdinal($Now.ToString("yyyy-MM-dd"), $e) -gt 0)
}

# ------------------------------------------------------------------------------
# Phone push (ntfy or Telegram): request building is pure, sending is in the UI
# ------------------------------------------------------------------------------
function New-PushRequest {
    # Returns @{ Url; Json } or $null when the service is not configured
    param([string]$Service, [string]$Title, [string]$Message, [string]$Server = "https://ntfy.sh",
          [string]$Topic = "", [string]$Token = "", [string]$ChatId = "", [int]$Priority = 3, [string[]]$Tags = @())
    switch ($Service) {
        "ntfy" {
            if (-not $Topic -or $Topic -notmatch '^[A-Za-z0-9_-]{1,64}$') { return $null }
            $srv = ([string]$Server).Trim().TrimEnd('/')
            if (-not $srv) { $srv = "https://ntfy.sh" }
            if ($srv -notmatch '^https?://') { return $null }
            $body = [ordered]@{ topic = $Topic; title = $Title; message = $Message; priority = [math]::Max(1, [math]::Min(5, $Priority)) }
            if (@($Tags).Count -gt 0) { $body.tags = @($Tags) }
            return @{ Url = $srv; Json = ($body | ConvertTo-Json -Compress) }
        }
        "Telegram" {
            if (-not $Token -or $Token -notmatch '^\d+:[A-Za-z0-9_-]+$' -or -not $ChatId -or $ChatId -notmatch '^-?\d+$') { return $null }
            $txt = if ($Title) { "{0}`n{1}" -f $Title, $Message } else { $Message }
            $body = [ordered]@{ chat_id = $ChatId; text = $txt; disable_web_page_preview = $true }
            return @{ Url = ("https://api.telegram.org/bot{0}/sendMessage" -f $Token); Json = ($body | ConvertTo-Json -Compress) }
        }
    }
    return $null
}

function Get-TelegramChatId {
    # Chat of the newest message the bot received (getUpdates); "" if none
    param($Json)
    $id = ""
    try {
        foreach ($u in @($Json.result)) {
            $m = if ($null -ne $u.message) { $u.message } elseif ($null -ne $u.channel_post) { $u.channel_post } else { $null }
            if ($null -ne $m -and $null -ne $m.chat -and $null -ne $m.chat.id) { $id = [string]$m.chat.id }
        }
    } catch { $id = "" }
    return $id
}

function Test-PushAllowed {
    # Simple rate limit: at most $Max pushes in the last 60 seconds
    param([DateTime[]]$Sent, [DateTime]$Now = (Get-Date), [int]$Max = 10)
    $recent = @(@($Sent) | Where-Object { ($Now - $_).TotalSeconds -lt 60 })
    return ($recent.Count -lt $Max)
}

function New-RandomTopic {
    $chars = "abcdefghijkmnpqrstuvwxyz23456789".ToCharArray()
    $rng = New-Object System.Random
    return ("tw-" + (-join (1..12 | ForEach-Object { $chars[$rng.Next($chars.Length)] })))
}

# ==============================================================================
# v4.4: terminal command line, news, event calendar, update check
# ==============================================================================
function Get-TerminalFunctions {
    # Function words: Scope "G" = without ticker, "T" = after a ticker, "GT" = both
    return [ordered]@{
        "GP"     = @{ Scope = "T";  Desc = "Chart (optional Zeitraum: GP 1Y)" }
        "DES"    = @{ Scope = "T";  Desc = "Beschreibung: Profil, Kennzahlen, Termine, Position" }
        "TA"     = @{ Scope = "T";  Desc = "Ticker-Analyse: technische Signale, Unterstützung / Widerstand, Kennzahlen" }
        "FA"     = @{ Scope = "T";  Desc = "Ticker-Analyse: Kennzahlen (KGV, Margen, Wachstum ...) im Vergleich" }
        "N"      = @{ Scope = "GT"; Desc = "Nachrichten (ohne Ticker: News-Tab)" }
        "NEWS"   = @{ Scope = "G";  Desc = "News-Tab: NEWS / NEWS DEPOT / NEWS WATCH / NEWS <Ticker>" }
        "DVD"    = @{ Scope = "GT"; Desc = "Dividenden (ohne Ticker: Depot-Dividenden)" }
        "EE"     = @{ Scope = "GT"; Desc = "Termine: Quartalszahlen, Ex-Tag, Zahltag" }
        "ALRT"   = @{ Scope = "GT"; Desc = "Alarm anlegen: NVDA ALRT >= 150 / TRAIL 8 / 52H / VOL 2 (ohne Ticker: Alarmliste)" }
        "WL"     = @{ Scope = "T";  Desc = "Zur Watchlist hinzufügen" }
        "NOTE"   = @{ Scope = "T";  Desc = "Notiz zum Ticker (Kaufgrund, These)" }
        "PEER"   = @{ Scope = "T";  Desc = "Eigene Vergleichsgruppe: NVDA PEER AMD INTC (PEER - = wieder Sektor)" }
        "CMP"    = @{ Scope = "GT"; Desc = "Vergleich im Chart (CMP ohne Ticker = aus)" }
        "TX"     = @{ Scope = "GT"; Desc = "Transaktion erfassen / Historie" }
        "PORT"   = @{ Scope = "G";  Desc = "Portfolio" }
        "ANA"    = @{ Scope = "G";  Desc = "Portfolio-Analyse" }
        "CAL"    = @{ Scope = "G";  Desc = "Terminkalender (Portfolio + Watchlist)" }
        "TOP"    = @{ Scope = "G";  Desc = "Gewinner / Verlierer heute" }
        "FX"     = @{ Scope = "G";  Desc = "Wechselkurse" }
        "LOG"    = @{ Scope = "G";  Desc = "Alarm-Verlauf" }
        "REP"    = @{ Scope = "G";  Desc = "Jahresreport" }
        "TF"     = @{ Scope = "G";  Desc = "Zeitraum: TF 1D / 5D / 1M / 3M / 6M / 1Y" }
        "LAYOUT" = @{ Scope = "G";  Desc = "Layout: LAYOUT TERMINAL / STANDARD / COMPACT / TICKER, LAYOUT SAVE <Name>, LAYOUT DEL <Name>" }
        "THEME"  = @{ Scope = "G";  Desc = "Theme wechseln (THEME <Name>)" }
        "STYLE"  = @{ Scope = "G";  Desc = "Design umschalten: STYLE / STYLE FRESH / STYLE REFINED" }
        "SET"    = @{ Scope = "G";  Desc = "Einstellungen (SET <Suchwort> springt zur Einstellung)" }
        "MENU"   = @{ Scope = "G";  Desc = "Menüeintrag ausführen (MENU <Name>)" }
        "HEALTH" = @{ Scope = "G";  Desc = "Zustand prüfen: Datendateien, Backups, Datenquelle, Schriften" }
        "IMG"    = @{ Scope = "G";  Desc = "Bild: IMG = Chart in die Zwischenablage, IMG SAVE, IMG WIN (ganzes Fenster)" }
        "PROV"   = @{ Scope = "G";  Desc = "Datenquellen testen: was liefern deine Twelve-Data- / Finnhub-Schlüssel?" }
        "DIAG"   = @{ Scope = "G";  Desc = "Diagnose als ZIP exportieren (Log, Einstellungen ohne Zugangsdaten, Zustand)" }
        "PUSH"   = @{ Scope = "G";  Desc = "Handy-Push einrichten" }
        "GLOS"   = @{ Scope = "G";  Desc = "Glossar" }
        "HELP"   = @{ Scope = "G";  Desc = "Tastenkürzel und Befehle" }
        "ABOUT"  = @{ Scope = "G";  Desc = "Version, Pfade, Update-Prüfung" }
        "PF"     = @{ Scope = "G";  Desc = "Depot wechseln: PF <Name> (ohne Name: neues Depot)" }
        "IMP"    = @{ Scope = "G";  Desc = "Broker-CSV importieren" }
        "BAK"    = @{ Scope = "G";  Desc = "Backup wiederherstellen" }
        "IND"    = @{ Scope = "G";  Desc = "Indikatoren: IND MACD / RSI / EMA / SMA" }
        "CT"     = @{ Scope = "G";  Desc = "Durchklicken an/aus (Maus geht durchs Fenster)" }
        "PRIV"   = @{ Scope = "G";  Desc = "Privat-Modus: Beträge ausblenden (PRIV ON / OFF, Taste F9)" }
        "DRAW"   = @{ Scope = "G";  Desc = "Im Chart zeichnen: DRAW H (Linie) / T (Trendlinie) / F (Fibonacci) / CLEAR" }
        "CASH"   = @{ Scope = "G";  Desc = "Cash-Konto des Depots (Einzahlung, Auszahlung, Kontostand)" }
        "SPAR"   = @{ Scope = "G";  Desc = "Sparpläne (monatliche Käufe automatisch buchen)" }
        "REBAL"  = @{ Scope = "G";  Desc = "Zielgewichte und Rebalancing-Vorschlag" }
        "RISK"   = @{ Scope = "G";  Desc = "Risiko: Drawdown, Volatilität, Sharpe, Beta, Korrelation" }
        "HEAT"   = @{ Scope = "G";  Desc = "Heatmap des Depots (Größe = Anteil, Farbe = Tag %)" }
        "FULL"   = @{ Scope = "G";  Desc = "Liste als ganze Seite (Terminal): FULL PORT / FULL WATCH / FULL NEWS, FULL = zurück" }
        "TOUR"   = @{ Scope = "G";  Desc = "Kurze Einführung" }
        "SCALE"  = @{ Scope = "G";  Desc = "Preisachse: SCALE LOG / SCALE LIN" }
        "BAR"    = @{ Scope = "G";  Desc = "Was die Compact-/Ticker-Leiste zeigt" }
    }
}

function ConvertFrom-TerminalCommand {
    # "NVDA GP 1Y" -> @{ Kind = "Ticker"; Ticker = "NVDA"; Func = "GP"; Args = @("1Y") }
    # "CAL"        -> @{ Kind = "Global"; Func = "CAL" }
    # "NVDA"       -> @{ Kind = "Ticker"; Ticker = "NVDA"; Func = "" }
    param([string]$Text)
    $r = @{ Kind = "Empty"; Ticker = ""; Func = ""; Args = @(); Error = "" }
    $tok = @(([string]$Text).Trim() -split '\s+' | Where-Object { $_ })
    if ($tok.Count -eq 0) { return $r }
    $fn = Get-TerminalFunctions
    $t0 = $tok[0].ToUpperInvariant()
    if ($fn.Contains($t0) -and $fn[$t0].Scope -like "*G*") {
        $r.Kind = "Global"; $r.Func = $t0
        $r.Args = @($tok | Select-Object -Skip 1)
        return $r
    }
    if ($fn.Contains($t0)) { $r.Kind = "Error"; $r.Error = "$t0 braucht einen Ticker davor, z. B. NVDA $t0"; return $r }
    if ($t0 -notmatch '^[A-Z0-9\^][A-Z0-9\.\-=\^]{0,19}$') { $r.Kind = "Error"; $r.Error = "Unbekannter Befehl oder Ticker: $($tok[0])"; return $r }
    $r.Kind = "Ticker"; $r.Ticker = $t0
    if ($tok.Count -ge 2) {
        $t1 = $tok[1].ToUpperInvariant()
        if (-not $fn.Contains($t1) -or $fn[$t1].Scope -notlike "*T*") { $r.Kind = "Error"; $r.Error = "Unbekannte Funktion '$($tok[1])' - nach dem Ticker z. B. GP, DES, N, DVD, EE, ALRT, WL"; return $r }
        $r.Func = $t1
        $r.Args = @($tok | Select-Object -Skip 2)
    }
    return $r
}

function ConvertFrom-AlertShorthand {
    # "ALRT" arguments -> @{ Condition; Value } or $null
    #   >= 150 | <= 150 | TAG+ 3 | TAG- 3 | RSI+ 70 | RSI- 30 | SMA+ | SMA- | TRAIL 8
    #   EK+ 20 | EK- 10 | 52H [1] | 52L [1] | VOL 2 | DEPOT>= 50000 | DEPOT<= | DTAG+ 2 | DTAG- 2
    param([string[]]$ArgList)
    $a = @($ArgList | Where-Object { $_ })
    if ($a.Count -eq 0) { return $null }
    $k = $a[0].ToUpperInvariant()
    $vRaw = if ($a.Count -ge 2) { $a[1] } else { "" }
    if ($k -match '^(>=|<=)(.+)$') { $k = $Matches[1]; $vRaw = $Matches[2] }
    $map = @{
        ">=" = ">="; "<=" = "<="; "TAG+" = "Tag% >="; "TAG-" = "Tag% <="; "RSI+" = "RSI >="; "RSI-" = "RSI <="
        "SMA+" = "> SMA"; "SMA-" = "< SMA"; "TRAIL" = "Trailing %"; "EK+" = "EK% >="; "EK-" = "EK% <="
        "52H" = "52W Hoch"; "52L" = "52W Tief"; "VOL" = "Volumen x"
        "DEPOT>=" = "Depot >="; "DEPOT<=" = "Depot <="; "DTAG+" = "Depot Tag% >="; "DTAG-" = "Depot Tag% <="
    }
    if (-not $map.ContainsKey($k)) { return $null }
    $cond = $map[$k]
    $kind = Get-AlertKind $cond
    $v = 0.0
    if ($kind -eq "SMA") { return @{ Condition = $cond; Value = 0.0 } }
    if (-not $vRaw) {
        if ($kind -in @("HIGH52", "LOW52")) { return @{ Condition = $cond; Value = 0.0 } }
        return $null
    }
    $norm = ([string]$vRaw).Trim().Replace(",", ".").TrimEnd('%', 'x', 'X')
    if (-not [double]::TryParse($norm, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $null }
    if ($kind -in @("PCT", "PFPCT", "EKPCT") -and $k -match '-$') { $v = -[math]::Abs($v) }
    return @{ Condition = $cond; Value = $v }
}

function Get-CommandSuggestions {
    # Autocomplete: @(@{ Text; Desc }) for what has been typed so far
    # v5.3: Extra = settings and menu entries @(@{ Text; Desc; Search }); they
    # are offered when the typed words appear in Search ("SET <words>" = settings only)
    param([string]$Text, [string[]]$Tickers = @(), [string[]]$Recent = @(), [int]$Max = 12, [string[]]$Depots = @(), [string[]]$Layouts = @(), $Extra = @())
    $out = New-Object System.Collections.Generic.List[PSObject]
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $add = {
        param([string]$T, [string]$D)
        if ($out.Count -lt $Max -and $seen.Add($T)) { $out.Add([PSCustomObject]@{ Text = $T; Desc = $D }) }
    }
    $fn = Get-TerminalFunctions
    $raw = [string]$Text
    $tx = $raw.TrimStart().ToUpperInvariant()
    $tok = @($tx -split '\s+' | Where-Object { $_ })
    $endsSpace = $raw.EndsWith(" ")
    if ($tok.Count -eq 0) {
        foreach ($r in @($Recent)) { & $add ([string]$r) "zuletzt" }
        foreach ($k in $fn.Keys) { if ($fn[$k].Scope -like "*G*") { & $add $k $fn[$k].Desc } }
        return $out.ToArray()
    }
    $addExtra = {
        param([string]$Q, [string]$Prefix = "")
        if (-not $Q.Trim()) { return }
        foreach ($x in @($Extra)) {
            if ($null -eq $x) { continue }
            if ($Prefix -and -not ([string]$x.Text).ToUpperInvariant().StartsWith($Prefix)) { continue }
            if (Test-SettingMatch -Text ([string]$x.Text + " " + [string]$x.Search) -Query $Q) { & $add ([string]$x.Text) ([string]$x.Desc) }
        }
    }
    if ($tok.Count -eq 1 -and -not $endsSpace) {
        foreach ($r in @($Recent)) { if (([string]$r).ToUpperInvariant().StartsWith($tx)) { & $add ([string]$r) "zuletzt" } }
        foreach ($k in $fn.Keys) { if ($k.StartsWith($tx) -and $fn[$k].Scope -like "*G*") { & $add $k $fn[$k].Desc } }
        foreach ($t in @($Tickers)) { if (([string]$t).ToUpperInvariant().StartsWith($tx)) { & $add ([string]$t).ToUpperInvariant() "Ticker öffnen" } }
        if ($tx.Length -ge 3) { & $addExtra $tx }
        return $out.ToArray()
    }
    $first = $tok[0]
    if ($first -in @("SET", "MENU")) {
        $rest = (@($tok | Select-Object -Skip 1) -join " ")
        & $addExtra $rest ($first + " ")
        if ($out.Count -eq 0 -and -not $rest) { & $add $first $fn[$first].Desc }
        return $out.ToArray()
    }
    if ($fn.Contains($first) -and $fn[$first].Scope -like "*G*") {
        $opts = switch ($first) {
            "TF"     { @("1D", "5D", "1M", "3M", "6M", "1Y") }
            "LAYOUT" { @("TERMINAL", "STANDARD", "COMPACT", "TICKER") + @($Layouts | ForEach-Object { ([string]$_).ToUpperInvariant() }) + @("SAVE") }
            "IND"    { @("MACD", "RSI", "EMA", "SMA") }
            "SCALE"  { @("LOG", "LIN") }
            "PF"     { @($Depots | ForEach-Object { ([string]$_).ToUpperInvariant() }) }
            default  { @() }
        }
        $part = if ($tok.Count -ge 2 -and -not $endsSpace) { $tok[1] } else { "" }
        foreach ($o in $opts) { if ($o.StartsWith($part)) { & $add ("{0} {1}" -f $first, $o) $fn[$first].Desc } }
        return $out.ToArray()
    }
    # ticker + function
    $part = if ($tok.Count -ge 2 -and -not $endsSpace) { $tok[1] } else { "" }
    if ($tok.Count -eq 1 -or ($tok.Count -eq 2 -and -not $endsSpace)) {
        foreach ($k in $fn.Keys) { if ($fn[$k].Scope -like "*T*" -and $k.StartsWith($part)) { & $add ("{0} {1}" -f $first, $k) $fn[$k].Desc } }
    }
    if ($tok.Count -ge 2 -and $tok[1] -eq "ALRT") {
        foreach ($ex in @(">= ", "<= ", "TRAIL 8", "TAG- 3", "TAG+ 3", "EK+ 20", "EK- 10", "52H", "52L", "VOL 2", "RSI+ 70", "RSI- 30", "SMA+", "SMA-")) {
            & $add ("{0} ALRT {1}" -f $first, $ex).TrimEnd() "Alarm"
        }
    }
    if ($tok.Count -ge 2 -and $tok[1] -eq "GP") {
        foreach ($o in @("1D", "5D", "1M", "3M", "6M", "1Y")) { & $add ("{0} GP {1}" -f $first, $o) "Chart" }
    }
    # free words that are no ticker command ("zebra zeilen") -> settings / menus
    if (-not $fn.Contains($first) -and ($tok.Count -lt 2 -or -not $fn.Contains($tok[1]))) { & $addExtra $tx }
    return $out.ToArray()
}

function Add-RecentCommand {
    param([string[]]$Recent, [string]$Command, [int]$Max = 20)
    $c = ([string]$Command).Trim().ToUpperInvariant()
    if (-not $c) { return @($Recent) }
    $list = @($c) + @(@($Recent) | Where-Object { $_ -and ([string]$_).ToUpperInvariant() -ne $c })
    return @($list | Select-Object -First $Max)
}

function ConvertFrom-YahooNews {
    # v1/finance/search news -> @(@{ Title; Publisher; Link; Time (DateTime local); Tickers })
    param($Json)
    $out = @()
    if ($null -eq $Json -or $null -eq $Json.news) { return $out }
    foreach ($n in @($Json.news)) {
        if ($null -eq $n -or -not $n.title) { continue }
        $link = [string]$n.link
        if ($link -notmatch '^https?://') { $link = "" }
        $t = [DateTime]::MinValue
        if ($null -ne $n.providerPublishTime) { try { $t = [DateTimeOffset]::FromUnixTimeSeconds([long]$n.providerPublishTime).LocalDateTime } catch { } }
        $img = ""
        try {
            $res = @($n.thumbnail.resolutions | Where-Object { $null -ne $_ -and [string]$_.url -match '^https://' } | Sort-Object { [int]$_.width })
            if ($res.Count -gt 0) { $img = [string]$res[$res.Count - 1].url }
        } catch { }
        $out += [PSCustomObject]@{
            Title = [string]$n.title; Publisher = [string]$n.publisher; Link = $link; Time = $t
            Tickers = @(@($n.relatedTickers) | Where-Object { $_ } | ForEach-Object { [string]$_ })
            Summary = ""; Image = $img
        }
    }
    return @($out | Sort-Object -Property Time -Descending)
}

# ------------------------------------------------------------------------------
# News tab (v4.9): one feed for holdings + watchlist
# ------------------------------------------------------------------------------
function Get-NewsSymbols {
    # Tickers to ask for news: holdings first, then the watchlist, each once.
    # Indices (^GSPC), FX (EURUSD=X) and futures (GC=F) have no useful news.
    param([string[]]$Holdings = @(), [string[]]$Watchlist = @(), [int]$Max = 40)
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($s in (@($Holdings) + @($Watchlist))) {
        if ($null -eq $s) { continue }
        $u = ([string]$s).Trim().ToUpperInvariant()
        if (-not $u -or $u -match '^\^|=X$|=F$') { continue }
        if ($seen.Add($u)) {
            $out.Add($u)
            if ($out.Count -ge $Max) { break }
        }
    }
    return @($out)
}

function Get-NewsKey {
    # De-duplication key: the link without anchor and tracking parameters, else the
    # title. v7.7: other query parameters stay (article.php?id=1 is not ?id=2).
    param($Item)
    $link = [string]$Item.Link
    if ($link) {
        $link = $link -replace '#.*$', ''
        $base = $link; $query = ""
        $q = $link.IndexOf('?')
        if ($q -ge 0) { $base = $link.Substring(0, $q); $query = $link.Substring($q + 1) }
        $keep = @($query -split '&' | Where-Object { $_ -and $_ -notmatch '^(utm_[^=]*|utm|fbclid|gclid|mc_cid|mc_eid|cmpid|ncid|ocid|src|\.tsrc|guccounter|guce_[^=]*)(=|$)' } | Sort-Object)
        $key = $base.TrimEnd('/')
        if ($keep.Count -gt 0) { $key += "?" + ($keep -join "&") }
        return $key.ToLowerInvariant()
    }
    return "t:" + (([string]$Item.Title).Trim() -replace '\s+', ' ').ToLowerInvariant()
}

function Merge-NewsFeed {
    # Per-ticker lists (ticker -> ConvertFrom-YahooNews items) -> one feed,
    # newest first. The same article found for several tickers appears once;
    # Syms lists every ticker of ours it belongs to (queried or related).
    param([hashtable]$BySymbol, [int]$Max = 150, [int]$MaxAgeDays = 14, [DateTime]$Now = [DateTime]::MinValue)
    if ($Now -eq [DateTime]::MinValue) { $Now = Get-Date }
    $out = @()
    if ($null -eq $BySymbol -or $BySymbol.Count -eq 0) { return $out }
    $ours = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $BySymbol.Keys) { [void]$ours.Add(([string]$k).ToUpperInvariant()) }
    $map = @{}
    $order = New-Object System.Collections.Generic.List[string]
    foreach ($sym in @($BySymbol.Keys | Sort-Object)) {
        $su = ([string]$sym).ToUpperInvariant()
        foreach ($n in @($BySymbol[$sym])) {
            if ($null -eq $n -or -not $n.Title) { continue }
            $t = [DateTime]::MinValue
            if ($null -ne $n.Time) { $t = [DateTime]$n.Time }
            if ($t -gt [DateTime]::MinValue -and ($Now - $t).TotalDays -gt $MaxAgeDays) { continue }
            $key = Get-NewsKey $n
            $e = $map[$key]
            if ($null -eq $e) {
                $e = [PSCustomObject]@{
                    Key = $key; Title = ([string]$n.Title).Trim(); Publisher = [string]$n.Publisher
                    Link = [string]$n.Link; Time = $t; Syms = New-Object System.Collections.Generic.List[string]
                    Summary = [string]$n.Summary; Image = [string]$n.Image
                }
                $map[$key] = $e
                $order.Add($key)
            }
            if (-not $e.Syms.Contains($su)) { $e.Syms.Add($su) }
            foreach ($rt in @($n.Tickers)) {
                $ru = ([string]$rt).ToUpperInvariant()
                if ($ru -and $ours.Contains($ru) -and -not $e.Syms.Contains($ru)) { $e.Syms.Add($ru) }
            }
        }
    }
    foreach ($key in $order) {
        $e = $map[$key]
        $out += [PSCustomObject]@{
            Key = $e.Key; Title = $e.Title; Publisher = $e.Publisher; Link = $e.Link; Time = $e.Time
            Syms = @($e.Syms | Sort-Object)
            Summary = $e.Summary; Image = $e.Image; Sources = @("yahoo"); Also = @()
        }
    }
    $sorted = @($out | Sort-Object -Property @{ Expression = { $_.Time }; Descending = $true }, @{ Expression = { $_.Title }; Descending = $false })
    if ($sorted.Count -gt $Max) { $sorted = @($sorted[0..($Max - 1)]) }
    return $sorted
}

function Select-NewsItems {
    # Filter: "All", "Holdings", "Watchlist" or one ticker
    param($Items, [string]$Filter = "All", [string[]]$Holdings = @(), [string[]]$Watchlist = @())
    $f = ([string]$Filter).Trim()
    # an empty list coming out of another function arrives as $null: no $null items
    if (-not $f -or $f -eq "All") { return @(@($Items) | Where-Object { $null -ne $_ }) }
    $set = New-Object System.Collections.Generic.HashSet[string]
    $src = switch ($f) {
        "Holdings"  { @($Holdings) }
        "Watchlist" { @($Watchlist) }
        default     { @($f) }
    }
    foreach ($s in $src) { if ($s) { [void]$set.Add(([string]$s).ToUpperInvariant()) } }
    return @(@($Items) | Where-Object { $null -ne $_ -and @($_.Syms | Where-Object { $set.Contains(([string]$_).ToUpperInvariant()) }).Count -gt 0 })
}

function Format-NewsAge {
    # "vor 12 min", "vor 3 h", "gestern 14:30", "21.11. 09:15" (EN: "12 min ago" ...)
    param([DateTime]$Time, [DateTime]$Now = [DateTime]::MinValue, [string]$Lang = "DE")
    if ($Time -eq [DateTime]::MinValue) { return "" }
    if ($Now -eq [DateTime]::MinValue) { $Now = Get-Date }
    $en = ($Lang -eq "EN")
    $age = $Now - $Time
    if ($age.TotalMinutes -lt 1) { if ($en) { return "now" } else { return "jetzt" } }
    if ($age.TotalMinutes -lt 60) {
        $m = [int][math]::Floor($age.TotalMinutes)
        if ($en) { return "$m min ago" } else { return "vor $m min" }
    }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Time.Date -eq $Now.Date) {
        $h = [int][math]::Floor($age.TotalHours)
        if ($en) { return "$h h ago" } else { return "vor $h h" }
    }
    if ($Time.Date -eq $Now.Date.AddDays(-1)) {
        if ($en) { return "yesterday " + $Time.ToString("HH:mm", $inv) } else { return "gestern " + $Time.ToString("HH:mm", $inv) }
    }
    return $Time.ToString("dd.MM. HH:mm", $inv)
}

function Get-NewsUnreadCount {
    # Items newer than the last time the news tab was looked at
    param($Items, [DateTime]$Since)
    return @(@($Items) | Where-Object { $null -ne $_ -and [DateTime]$_.Time -gt $Since }).Count
}

function Get-NewsMover {
    # The ticker of an item that moves most today, if it moves at least
    # Threshold % (to see why a position jumps). $null otherwise.
    param([string[]]$Syms, [hashtable]$DayPct, [double]$Threshold = 3)
    if ($null -eq $DayPct -or $Threshold -le 0) { return $null }
    $best = $null
    foreach ($s in @($Syms)) {
        if (-not $s) { continue }
        $v = $DayPct[([string]$s).ToUpperInvariant()]
        if ($null -eq $v) { continue }
        $d = [double]$v
        if ([double]::IsNaN($d) -or [math]::Abs($d) -lt $Threshold) { continue }
        if ($null -eq $best -or [math]::Abs($d) -gt [math]::Abs($best.Pct)) { $best = [PSCustomObject]@{ Sym = ([string]$s).ToUpperInvariant(); Pct = $d } }
    }
    return $best
}

function Get-NewsMoverRows {
    # v4.9.5: item key -> mover, only for the NEWEST item of each moving
    # ticker (Items newest first), so "+31 %" is not repeated on every row
    param($Items, [hashtable]$DayPct, [double]$Threshold = 3)
    $out = @{}
    $done = New-Object System.Collections.Generic.HashSet[string]
    foreach ($n in @($Items)) {
        if ($null -eq $n) { continue }
        # only tickers that were not marked on a newer item yet
        $open = @(@($n.Syms) | Where-Object { $_ -and -not $done.Contains(([string]$_).ToUpperInvariant()) })
        if ($open.Count -eq 0) { continue }
        $mv = Get-NewsMover -Syms $open -DayPct $DayPct -Threshold $Threshold
        if ($null -eq $mv) { continue }
        [void]$done.Add([string]$mv.Sym)
        $out[[string]$n.Key] = $mv
    }
    return $out
}

function Remove-MutedNews {
    # v4.9.5: drop items of muted sources (publisher names, any case)
    param($Items, [string[]]$Muted = @())
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($m in @($Muted)) { if ($m) { [void]$set.Add(([string]$m).Trim().ToLowerInvariant()) } }
    if ($set.Count -eq 0) { return @(@($Items) | Where-Object { $null -ne $_ }) }
    return @(@($Items) | Where-Object { $null -ne $_ -and -not $set.Contains(([string]$_.Publisher).Trim().ToLowerInvariant()) })
}

function ConvertTo-KeywordList {
    # "Downgrade, Übernahme; gewinnwarnung" -> lower-case words, each once
    param([string]$Text)
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($w in (([string]$Text) -split '[,;\r\n]+')) {
        $t = $w.Trim().ToLowerInvariant()
        if ($t -and -not $out.Contains($t)) { $out.Add($t) }
    }
    return @($out)
}

function Find-NewsKeywordHits {
    # v4.9.5: items newer than Since, about one of Symbols, whose headline
    # contains a keyword -> @(@{ Item; Keyword; Sym }), oldest first
    param($Items, [string[]]$Keywords = @(), [string[]]$Symbols = @(), [DateTime]$Since = [DateTime]::MinValue)
    $kw = @(@($Keywords) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $out = @()
    if ($kw.Count -eq 0) { return $out }
    $syms = New-Object System.Collections.Generic.HashSet[string]
    foreach ($s in @($Symbols)) { if ($s) { [void]$syms.Add(([string]$s).ToUpperInvariant()) } }
    foreach ($n in @($Items)) {
        if ($null -eq $n -or [DateTime]$n.Time -le $Since) { continue }
        $hit = @(@($n.Syms) | Where-Object { $syms.Contains(([string]$_).ToUpperInvariant()) })
        if ($hit.Count -eq 0) { continue }
        $title = ([string]$n.Title).ToLowerInvariant()
        foreach ($k in $kw) {
            if ($title.Contains($k)) {
                $out += [PSCustomObject]@{ Item = $n; Keyword = $k; Sym = ([string]$hit[0]).ToUpperInvariant() }
                break
            }
        }
    }
    return @($out | Sort-Object -Property @{ Expression = { [DateTime]$_.Item.Time } })
}

function Get-NewsPollMinutes {
    # Refresh interval of the news feed: the setting, doubled while every
    # market is closed (news still comes, but nothing trades on it)
    param([int]$Minutes = 15, [bool]$AllClosed = $false)
    $m = [math]::Max(5, [math]::Min(240, $Minutes))
    if ($AllClosed) { $m = [math]::Min(240, 2 * $m) }
    return [int]$m
}

function Get-EventCalendar {
    # Upcoming dates from the event store: @(@{ Date; Ticker; Kind; Days })
    param([hashtable]$Events, [string[]]$Symbols, [string]$AsOf = "", [int]$Days = 60)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $now = if ($AsOf) { [DateTime]::ParseExact($AsOf, "yyyy-MM-dd", $inv) } else { (Get-Date).Date }
    $end = $now.AddDays($Days)
    $out = @()
    foreach ($s in @($Symbols | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpperInvariant() } | Sort-Object -Unique)) {
        $e = $Events[$s]
        if ($null -eq $e) { continue }
        foreach ($pair in @(@("EarningsDate", "Quartalszahlen"), @("ExDividendDate", "Ex-Tag"), @("DividendDate", "Zahltag"))) {
            $v = [string]$e.($pair[0])
            if (-not $v) { continue }
            $d = [DateTime]::MinValue
            if (-not [DateTime]::TryParseExact($v, "yyyy-MM-dd", $inv, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { continue }
            if ($d -lt $now -or $d -gt $end) { continue }
            $out += [PSCustomObject]@{ Date = $v; Ticker = $s; Kind = $pair[1]; Days = [int]($d - $now).TotalDays }
        }
    }
    return @($out | Sort-Object -Property @{ Expression = { $_.Date } }, @{ Expression = { $_.Ticker } })
}

function Test-ClosedPollSkip {
    # Poll less while every market of interest is closed: $true = skip this poll
    param([string[]]$States, [DateTime]$LastData, [int]$ClosedMinutes, [DateTime]$Now = (Get-Date))
    if ($ClosedMinutes -le 0 -or @($States).Count -eq 0) { return $false }
    foreach ($s in @($States)) { if ($s -ne "CLOSED") { return $false } }
    return (($Now - $LastData).TotalMinutes -lt $ClosedMinutes)
}

function Compare-AppVersion {
    # -1 / 0 / 1 for "4.3" vs "4.10", "v4.4.1" ...
    param([string]$A, [string]$B)
    $pa = @(([string]$A).TrimStart('v', 'V') -split '\.' | ForEach-Object { $n = 0; [void][int]::TryParse($_, [ref]$n); $n })
    $pb = @(([string]$B).TrimStart('v', 'V') -split '\.' | ForEach-Object { $n = 0; [void][int]::TryParse($_, [ref]$n); $n })
    for ($i = 0; $i -lt [math]::Max($pa.Count, $pb.Count); $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    return 0
}

function Get-LatestTagVersion {
    # GitHub /tags response -> highest "vX.Y[.Z]" (without the v), "" if none
    param($Json)
    $best = ""
    foreach ($t in @($Json)) {
        $n = [string]$t.name
        if ($n -notmatch '^v?\d+(\.\d+){1,2}$') { continue }
        $v = $n.TrimStart('v', 'V')
        if (-not $best -or (Compare-AppVersion $v $best) -gt 0) { $best = $v }
    }
    return $best
}

# ==============================================================================
# v4.5: broker CSV import, depots
# ==============================================================================
function Get-CsvDelimiter {
    # ; , or TAB - whichever splits the first lines most consistently
    param([string[]]$Lines)
    $sample = @($Lines | Where-Object { $_ -and $_.Trim() } | Select-Object -First 10)
    $best = ";"; $bestScore = -1
    foreach ($d in @(";", ",", "`t", "|")) {
        $counts = @($sample | ForEach-Object { @(Split-CsvLine -Line $_ -Delimiter $d).Count })
        if ($counts.Count -eq 0) { continue }
        $max = ($counts | Measure-Object -Maximum).Maximum
        if ($max -lt 2) { continue }
        $same = @($counts | Where-Object { $_ -eq $max }).Count
        $score = $same * 100 + $max
        if ($score -gt $bestScore) { $bestScore = $score; $best = $d }
    }
    return $best
}

function Split-CsvLine {
    # One CSV line -> fields (quotes, doubled quotes inside quotes)
    param([string]$Line, [string]$Delimiter = ";")
    $out = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inQ = $false
    $d = [char]$Delimiter
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $ch = $Line[$i]
        if ($inQ) {
            if ($ch -eq '"') {
                if ($i + 1 -lt $Line.Length -and $Line[$i + 1] -eq '"') { [void]$sb.Append('"'); $i++ }
                else { $inQ = $false }
            } else { [void]$sb.Append($ch) }
        } elseif ($ch -eq '"') { $inQ = $true }
        elseif ($ch -eq $d) { $out.Add($sb.ToString().Trim()); [void]$sb.Clear() }
        else { [void]$sb.Append($ch) }
    }
    $out.Add($sb.ToString().Trim())
    return $out.ToArray()
}

function ConvertFrom-CsvText {
    # -> @{ Delimiter; Headers = string[]; Rows = @(string[]) }; the header is the
    # first line with as many fields as the widest line (skips broker preambles)
    param([string]$Text)
    $lines = @(([string]$Text) -split "`r?`n" | Where-Object { $_.Trim() })
    $res = @{ Delimiter = ";"; Headers = @(); Rows = @() }
    if ($lines.Count -eq 0) { return $res }
    $d = Get-CsvDelimiter -Lines $lines
    $split = @($lines | ForEach-Object { ,(Split-CsvLine -Line $_ -Delimiter $d) })
    $max = (@($split | ForEach-Object { $_.Count }) | Measure-Object -Maximum).Maximum
    $h = 0
    while ($h -lt $split.Count -and $split[$h].Count -lt [math]::Max(2, $max - 1)) { $h++ }
    if ($h -ge $split.Count) { return $res }
    $res.Delimiter = $d
    $res.Headers = @($split[$h] | ForEach-Object { ([string]$_).Trim().Trim([char]0xFEFF) })
    $rows = @()
    for ($i = $h + 1; $i -lt $split.Count; $i++) { if (@($split[$i] | Where-Object { $_ }).Count -gt 0) { $rows += ,$split[$i] } }
    $res.Rows = $rows
    return $res
}

function Get-CsvFieldNames {
    return [ordered]@{
        Date = "Datum"; Type = "Art"; Ident = "Ticker / ISIN"; Shares = "Stück"; Price = "Kurs"
        Amount = "Betrag"; Fee = "Gebühr"; Tax = "Steuer"; Currency = "Währung"; Name = "Name"
    }
}

function Get-CsvColumnGuess {
    # Header names -> @{ Field = column index or -1 }
    param([string[]]$Headers)
    $pat = [ordered]@{
        Date     = '^(datum|date|buchungstag|buchungsdatum|handelstag|ausführungsdatum|ausfuehrungsdatum|valuta|trade ?date|transaction ?date|zeit|time)'
        Type     = '^(typ|type|art|transaktion|transaktionsart|geschäftsart|geschaeftsart|buchungsart|transaction ?type|action|vorgang|aktion)'
        Ident    = '^(isin|symbol|ticker|wertpapier ?kennnummer|wkn|instrument)'
        Shares   = '^(stück|stueck|stk|anzahl|menge|quantity|shares|nominale|units|anteile|no\.? ?of ?shares)'
        Price    = '^(kurs($|[\s\(/])|preis|price|ausführungskurs|ausfuehrungskurs|execution ?price|t\. ?price|price ?per ?share)'
        Amount   = '^(betrag|amount|gesamt|total|kurswert|wert$|value|net ?amount|proceeds|summe)'
        Fee      = '^(gebühr|gebuehr|gebühren|gebuehren|provision|fee|fees|commission|comm|kosten|spesen)'
        Tax      = '^(steuer|steuern|tax|taxes|quellensteuer|kapitalertragsteuer|withholding ?tax)'
        Currency = '^(währung|waehrung|currency|whg|ccy)'
        Name     = '^(name|bezeichnung|wertpapier|titel|description|beschreibung)'
    }
    $map = @{}
    foreach ($f in $pat.Keys) { $map[$f] = -1 }
    $used = @{}
    # ISIN columns win over name columns for the identifier
    foreach ($f in $pat.Keys) {
        for ($i = 0; $i -lt @($Headers).Count; $i++) {
            if ($used.ContainsKey($i)) { continue }
            $h = ([string]$Headers[$i]).Trim().ToLowerInvariant()
            if ($h -match $pat[$f]) { $map[$f] = $i; $used[$i] = $true; break }
        }
    }
    # v5.5: extra columns (e.g. Trading212): currency of the total / of the
    # withholding tax, exchange rate, further fees in the account currency
    $extra = [ordered]@{
        AmountCurrency = '^(currency|währung|waehrung) ?\((total|gesamt|betrag)'
        TaxCurrency    = '^(currency|währung|waehrung) ?\((withholding|quellensteuer)'
        Rate           = '^(exchange ?rate|wechselkurs|devisenkurs|fx ?rate)'
        Broker         = '^(broker|depotbank)$'
    }
    foreach ($f in $extra.Keys) {
        $map[$f] = -1
        for ($i = 0; $i -lt @($Headers).Count; $i++) {
            if (([string]$Headers[$i]).Trim().ToLowerInvariant() -match $extra[$f]) { $map[$f] = $i; break }
        }
    }
    $fx = @()
    for ($i = 0; $i -lt @($Headers).Count; $i++) {
        if ($used.ContainsKey($i)) { continue }
        $h = ([string]$Headers[$i]).Trim().ToLowerInvariant()
        if ($h -match '^(currency conversion fee|stamp duty|french transaction tax|transaction fee|finra fee|charge amount|ptm levy)') { $fx += $i }
    }
    $map["FeeExtra"] = $fx
    return $map
}

function ConvertFrom-CsvNumber {
    # "1.234,56" / "1,234.56" / "-12,5" / "12 EUR" -> double; NaN if not a number
    param([string]$Raw)
    $t = ([string]$Raw).Trim() -replace '[^\d,\.\-+]', ''
    if (-not $t -or $t -eq '-' -or $t -eq '+') { return [double]::NaN }
    $lc = $t.LastIndexOf(','); $ld = $t.LastIndexOf('.')
    if ($lc -ge 0 -and $ld -ge 0) {
        if ($lc -gt $ld) { $t = $t.Replace('.', '').Replace(',', '.') } else { $t = $t.Replace(',', '') }
    } elseif ($lc -ge 0) {
        # "1,234" with exactly 3 digits after a single comma and more before: thousands
        $parts = $t.Split(',')
        if ($parts.Count -gt 2) { $t = $t.Replace(',', '') } else { $t = $t.Replace(',', '.') }
    } elseif ($ld -ge 0) {
        $parts = $t.Split('.')
        if ($parts.Count -gt 2) { $t = $t.Replace('.', '') }
    }
    $v = 0.0
    if ([double]::TryParse($t, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $v }
    return [double]::NaN
}

function ConvertFrom-CsvType {
    # Broker wording -> Kauf / Verkauf / Dividende / "" (skip)
    param([string]$Raw)
    $t = ([string]$Raw).Trim().ToLowerInvariant()
    if (-not $t) { return "" }
    # v5.5: cash movements (go to the cash account, not to the bookings)
    if ($t -match '^(deposit|einzahlung|einlage)') { return "Einzahlung" }
    if ($t -match '^(withdrawal|auszahlung|entnahme)') { return "Auszahlung" }
    if ($t -match 'interest on cash|lending interest|cash interest|zinsgutschrift|habenzins') { return "Zinsen" }
    if ($t -match 'dividend|ausschüttung|ausschuettung|ertrag|distribution|coupon|zins') { return "Dividende" }
    if ($t -match 'verkauf|sell|^s$|^sld$|^sale') { return "Verkauf" }
    if ($t -match 'kauf|buy|^b$|^bot$|sparplan|savings ?plan|purchase|einbuchung') { return "Kauf" }
    return ""
}

function Test-Isin {
    param([string]$Text)
    return ([string]$Text).Trim().ToUpperInvariant() -match '^[A-Z]{2}[A-Z0-9]{9}\d$'
}

function ConvertFrom-BrokerRows {
    # Rows + column map -> @(@{ Date; Type; Ident; Name; Shares; Price; Fee; Currency; Ok; Note })
    # Price = per share for buys/sells, total gross amount for dividends (like the widget's own bookings)
    # v5.5: cash rows (Einzahlung / Auszahlung / Zinsen) come back with Cash = $true
    # and Amount (signed, in AmountCurrency); Trading212: fees in the account
    # currency are converted with the row's exchange rate when it checks out
    param([array]$Rows, [hashtable]$Map, [string]$DefaultCurrency = "EUR")
    $get = { param($R, [string]$F) $i = if ($Map.ContainsKey($F) -and $null -ne $Map[$F] -and $Map[$F] -isnot [array]) { [int]$Map[$F] } else { -1 }; if ($i -ge 0 -and $i -lt @($R).Count) { return [string]$R[$i] } return "" }
    $feeCols = if ($Map.ContainsKey("FeeExtra")) { @($Map["FeeExtra"]) } else { @() }
    $out = @()
    foreach ($r in @($Rows)) {
        $o = [ordered]@{ Date = ""; Type = ""; Ident = ""; Name = ""; Shares = 0.0; Price = 0.0; Fee = 0.0; Currency = $DefaultCurrency; Ok = $false; Note = ""; Cash = $false; Amount = 0.0; Broker = "" }
        $o.Broker = (& $get $r "Broker").Trim()
        $dRaw = ((& $get $r "Date").Trim()) -replace '[T ,;].*$', ''
        $o.Date = ConvertTo-IsoDate $dRaw
        $o.Ident = (& $get $r "Ident").Trim().ToUpperInvariant()
        $o.Name = (& $get $r "Name").Trim()
        $cur = Get-NormalizedCurrencyCode (& $get $r "Currency")
        if ($cur) { $o.Currency = $cur }
        $sh = ConvertFrom-CsvNumber (& $get $r "Shares")
        $px = ConvertFrom-CsvNumber (& $get $r "Price")
        $am = ConvertFrom-CsvNumber (& $get $r "Amount")
        $fe = ConvertFrom-CsvNumber (& $get $r "Fee")
        $tx = ConvertFrom-CsvNumber (& $get $r "Tax")
        $typ = if ([int]$Map["Type"] -ge 0) { ConvertFrom-CsvType (& $get $r "Type") } else { "" }
        if (-not $typ -and [int]$Map["Type"] -lt 0 -and -not [double]::IsNaN($sh) -and $sh -ne 0) { $typ = if ($sh -lt 0) { "Verkauf" } else { "Kauf" } }
        $o.Type = $typ
        $amCur = Get-NormalizedCurrencyCode (& $get $r "AmountCurrency")
        if ($typ -in @("Einzahlung", "Auszahlung", "Zinsen")) {
            $o.Cash = $true
            $o.Currency = if ($amCur) { $amCur } else { $o.Currency }
            $v = if (-not [double]::IsNaN($am)) { [math]::Abs($am) } elseif (-not [double]::IsNaN($px)) { [math]::Abs($px) } else { 0.0 }
            $o.Amount = if ($typ -eq "Auszahlung") { -$v } else { $v }
            $why = @()
            if (-not $o.Date) { $why += "Datum fehlt" }
            if ($v -le 0) { $why += "Betrag fehlt" }
            $o.Ok = ($why.Count -eq 0); $o.Note = $why -join ", "
            $out += [PSCustomObject]$o
            continue
        }
        # factor: account currency -> price currency (only if the row's numbers agree)
        $rate = ConvertFrom-CsvNumber (& $get $r "Rate")
        $acc2px = $(if (-not $amCur -or $amCur -eq $o.Currency) { 1.0 } else { [double]::NaN })
        if ([double]::IsNaN($acc2px) -and $rate -gt 0 -and $sh -ne 0 -and $px -gt 0 -and -not [double]::IsNaN($am) -and $am -ne 0) {
            $gross = [math]::Abs($sh) * $px
            if ([math]::Abs($gross / $rate / [math]::Abs($am) - 1) -lt 0.03) { $acc2px = $rate }
            elseif ([math]::Abs($gross * $rate / [math]::Abs($am) - 1) -lt 0.03) { $acc2px = 1 / $rate }
        }
        $feeAcc = 0.0
        foreach ($fc in $feeCols) { if ([int]$fc -ge 0 -and [int]$fc -lt @($r).Count) { $fv = ConvertFrom-CsvNumber ([string]$r[[int]$fc]); if (-not [double]::IsNaN($fv)) { $feeAcc += [math]::Abs($fv) } } }
        $o.Fee = if ([double]::IsNaN($fe)) { 0.0 } else { [math]::Abs($fe) }
        if ($feeAcc -gt 0) {
            if (-not [double]::IsNaN($acc2px)) { $o.Fee += $feeAcc * $acc2px }
            else { $o.Note = "Gebühr ({0:N2} {1}) nicht umgerechnet" -f $feeAcc, $amCur }
        }
        $taxCur = Get-NormalizedCurrencyCode (& $get $r "TaxCurrency")
        if (-not [double]::IsNaN($tx) -and $taxCur -and $taxCur -ne $o.Currency) {
            $tx = if ($taxCur -eq $amCur -and -not [double]::IsNaN($acc2px)) { $tx * $acc2px } else { [double]::NaN }
        }
        if (-not [double]::IsNaN($tx) -and $o.Type -ne "Dividende") { $o.Fee += [math]::Abs($tx) }
        $o.Shares = if ([double]::IsNaN($sh)) { 0.0 } else { [math]::Abs($sh) }
        if ($o.Type -eq "Dividende") {
            # v5.5: the total is in another currency (Trading212: account currency) -> gross from shares x per share
            $useGross = ($amCur -and $amCur -ne $o.Currency -and $o.Shares -gt 0 -and -not [double]::IsNaN($px) -and $px -gt 0)
            $o.Price = if ($useGross) { [math]::Abs($px) * $o.Shares } elseif (-not [double]::IsNaN($am) -and $am -ne 0) { [math]::Abs($am) } elseif (-not [double]::IsNaN($px) -and $o.Shares -gt 0) { [math]::Abs($px) * $o.Shares } else { 0.0 }
            if (-not [double]::IsNaN($tx)) { $o.Fee += [math]::Abs($tx) }
        } else {
            if (-not [double]::IsNaN($px) -and $px -ne 0) { $o.Price = [math]::Abs($px) }
            elseif (-not [double]::IsNaN($am) -and $o.Shares -gt 0) {
                # amount usually includes the fee: buys paid amount + fee, sells receive amount - fee
                $net = [math]::Abs($am)
                $gross = if ($o.Type -eq "Kauf") { $net - $o.Fee } else { $net + $o.Fee }
                if ($gross -le 0) { $gross = $net }
                $o.Price = $gross / $o.Shares
            }
        }
        $why = @()
        if (-not $o.Type) { $why += "Art unbekannt" }
        if (-not $o.Date) { $why += "Datum fehlt" }
        if (-not $o.Ident) { $why += "Ticker/ISIN fehlt" }
        if ($o.Type -ne "Dividende" -and $o.Shares -le 0) { $why += "Stück fehlen" }
        if ($o.Price -le 0) { $why += "Kurs/Betrag fehlt" }
        $o.Ok = ($why.Count -eq 0)
        $o.Note = (@(@($why) + @($(if ($o.Note) { $o.Note }))) | Where-Object { $_ }) -join ", "
        $out += [PSCustomObject]$o
    }
    return $out
}

function Test-DuplicateTransaction {
    # Same date, ticker, type, shares and price (0.5 % tolerance) as an existing booking
    param([array]$Existing, $New)
    foreach ($t in @($Existing)) {
        if ([string]$t.Date -ne [string]$New.Date -or ([string]$t.Ticker).ToUpper() -ne ([string]$New.Ticker).ToUpper() -or [string]$t.Type -ne [string]$New.Type) { continue }
        if ([math]::Abs([double]$t.Shares - [double]$New.Shares) -gt 1e-6 * [math]::Max(1, [double]$New.Shares)) { continue }
        $p = [math]::Max(1e-9, [math]::Abs([double]$New.Price))
        if ([math]::Abs([double]$t.Price - [double]$New.Price) / $p -le 0.005) { return $true }
    }
    return $false
}

function Get-YahooSymbolFromSearch {
    # First equity / ETF / fund symbol of a search response; prefers $PreferSuffix (e.g. ".DE")
    param($Json, [string]$PreferSuffix = "")
    $items = @(ConvertFrom-YahooSearch $Json | Where-Object { $_.QuoteType -in @("EQUITY", "ETF", "MUTUALFUND") })
    if ($items.Count -eq 0) { return "" }
    if ($PreferSuffix) { foreach ($i in $items) { if ($i.Symbol.EndsWith($PreferSuffix.ToUpperInvariant())) { return $i.Symbol } } }
    return $items[0].Symbol
}

function ConvertTo-DepotId {
    # Display name -> folder-safe id
    param([string]$Name)
    $s = ([string]$Name).Trim().ToLowerInvariant()
    $s = $s.Replace('ä', 'ae').Replace('ö', 'oe').Replace('ü', 'ue').Replace('ß', 'ss')
    $s = ($s -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $s) { $s = "depot" }
    if ($s.Length -gt 40) { $s = $s.Substring(0, 40).Trim('-') }
    return $s
}

function Get-BackupInfo {
    # backups\yyyyMMdd_HHmmss_reason -> @{ When (DateTime); Reason }
    param([string]$FolderName)
    $o = @{ When = [DateTime]::MinValue; Reason = "" }
    if ($FolderName -match '^(\d{8}_\d{6})_?(.*)$') {
        $d = [DateTime]::MinValue
        if ([DateTime]::TryParseExact($Matches[1], "yyyyMMdd_HHmmss", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { $o.When = $d }
        $o.Reason = ([string]$Matches[2]).Replace('_', ' ')
    }
    return $o
}

# ==============================================================================
# v4.6: EMA / MACD, colour schemes, hotkeys, grid layouts, window snapping
# ==============================================================================
function Compute-Ema {
    # Exponential moving average; starts with the SMA of the first Period values (NaN before)
    param([double[]]$Prices, [int]$Period)
    $n = @($Prices).Count
    $out = New-Object double[] $n
    for ($i = 0; $i -lt $n; $i++) { $out[$i] = [double]::NaN }
    if ($Period -lt 1 -or $n -lt $Period) { return ,$out }
    $sum = 0.0
    for ($i = 0; $i -lt $Period; $i++) { $sum += $Prices[$i] }
    $out[$Period - 1] = $sum / $Period
    $k = 2.0 / ($Period + 1)
    for ($i = $Period; $i -lt $n; $i++) { $out[$i] = $Prices[$i] * $k + $out[$i - 1] * (1 - $k) }
    return ,$out
}

function Compute-Macd {
    # MACD line (EMA fast - EMA slow), signal (EMA of MACD), histogram
    param([double[]]$Prices, [int]$Fast = 12, [int]$Slow = 26, [int]$Signal = 9)
    $n = @($Prices).Count
    $ef = Compute-Ema -Prices $Prices -Period $Fast
    $es = Compute-Ema -Prices $Prices -Period $Slow
    $macd = New-Object double[] $n
    $sig = New-Object double[] $n
    $hist = New-Object double[] $n
    for ($i = 0; $i -lt $n; $i++) { $macd[$i] = $ef[$i] - $es[$i]; $sig[$i] = [double]::NaN; $hist[$i] = [double]::NaN }
    $first = -1
    for ($i = 0; $i -lt $n; $i++) { if (-not [double]::IsNaN($macd[$i])) { $first = $i; break } }
    if ($first -ge 0 -and ($n - $first) -ge $Signal) {
        $tail = New-Object double[] ($n - $first)
        [Array]::Copy($macd, $first, $tail, 0, $n - $first)
        $se = Compute-Ema -Prices $tail -Period $Signal
        for ($i = 0; $i -lt $se.Count; $i++) {
            $sig[$first + $i] = $se[$i]
            if (-not [double]::IsNaN($se[$i])) { $hist[$first + $i] = $macd[$first + $i] - $se[$i] }
        }
    }
    return @{ Macd = $macd; Signal = $sig; Hist = $hist }
}

function ConvertFrom-HexColor {
    # "#3B82F6" / "3b82f6" -> @(r, g, b), $null if invalid
    param([string]$Hex)
    $h = ([string]$Hex).Trim().TrimStart('#')
    if ($h -notmatch '^[0-9A-Fa-f]{6}$') { return $null }
    return @([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16))
}

function ConvertTo-HexColor {
    param([int]$R, [int]$G, [int]$B)
    return ("#{0:X2}{1:X2}{2:X2}" -f $R, $G, $B)
}

function Get-UpDownSchemes {
    # Up / down colours; "Farbenblind" = blue / orange (deuteranopia-safe)
    return [ordered]@{
        "Standard"    = @{ Up = "#10B981"; Down = "#F43F5E" }
        "Farbenblind" = @{ Up = "#3B82F6"; Down = "#F97316" }
        "Klassisch"   = @{ Up = "#22C55E"; Down = "#EF4444" }
        "Terminal"    = @{ Up = "#00E676"; Down = "#FF5252" }
    }
}

function Get-UpDownColors {
    # Scheme name (or "Eigene" with hex values) -> @{ Up = @(r,g,b); Down = @(r,g,b) }
    param([string]$Scheme, [string]$UpHex = "", [string]$DownHex = "")
    $all = Get-UpDownSchemes
    $u = $null; $d = $null
    if ($Scheme -eq "Eigene") { $u = ConvertFrom-HexColor $UpHex; $d = ConvertFrom-HexColor $DownHex }
    if ($null -eq $u -or $null -eq $d) {
        $sc = if ($all.Contains($Scheme)) { $all[$Scheme] } else { $all["Standard"] }
        $u = ConvertFrom-HexColor $sc.Up; $d = ConvertFrom-HexColor $sc.Down
    }
    return @{ Up = $u; Down = $d }
}

# ------------------------------------------------------------------------------
# Look and feel (v4.9)
# ------------------------------------------------------------------------------
function Get-MonoFontNames {
    # Fonts offered for numbers and tickers (all fixed-width)
    return @("Consolas", "Cascadia Mono", "Cascadia Code", "Lucida Console")
}

function Resolve-MonoFont {
    # The wanted font if it is offered and installed, else Consolas
    param([string]$Wanted, [string[]]$Installed = @())
    if ($Wanted -and (Get-MonoFontNames) -contains $Wanted -and @($Installed) -contains $Wanted) { return $Wanted }
    return "Consolas"
}

function Get-FontScaleSteps { return @(90, 100, 110, 120) }

function Get-ScaledFontSize {
    # Base size in pt * scale %, rounded to 0.5 pt; unknown scales count as 100
    param([double]$Base, [int]$ScalePct = 100)
    if ((Get-FontScaleSteps) -notcontains $ScalePct) { $ScalePct = 100 }
    return [math]::Round($Base * $ScalePct / 100.0 * 2, [System.MidpointRounding]::AwayFromZero) / 2.0
}

function Get-WindowCornerPref {
    # DWMWA_WINDOW_CORNER_PREFERENCE (33): 1 = square, 2 = round, 3 = small round.
    # Windows 11 rounds normal windows itself; borderless strips need asking.
    # The fullscreen chart stays square.
    param([string]$Kind = "Window", [bool]$Round = $true)
    if (-not $Round -or $Kind -eq "Fullscreen") { return 1 }
    if ($Kind -eq "Strip") { return 3 }
    return 2
}

function ConvertFrom-HotkeyText {
    # "Ctrl+Alt+W" -> @{ Mods = MOD_* bits; Key = virtual key code; Text } or $null
    # MOD_ALT 1, MOD_CONTROL 2, MOD_SHIFT 4, MOD_WIN 8
    param([string]$Text)
    $parts = @(([string]$Text) -split '\+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts.Count -lt 2) { return $null }
    $mods = 0
    $names = @()
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        switch ($parts[$i].ToUpperInvariant()) {
            { $_ -in @("CTRL", "STRG", "CONTROL") } { $mods = $mods -bor 2; $names += "Strg" }
            "ALT" { $mods = $mods -bor 1; $names += "Alt" }
            { $_ -in @("SHIFT", "UMSCHALT") } { $mods = $mods -bor 4; $names += "Umschalt" }
            { $_ -in @("WIN", "WINDOWS") } { $mods = $mods -bor 8; $names += "Win" }
            default { return $null }
        }
    }
    if ($mods -eq 0) { return $null }
    $k = $parts[$parts.Count - 1].ToUpperInvariant()
    $vk = 0
    if ($k -match '^[A-Z0-9]$') { $vk = [int][char]$k }
    elseif ($k -match '^F([1-9]|1[0-2])$') { $vk = 0x6F + [int]$Matches[1] }
    elseif ($k -eq "SPACE" -or $k -eq "LEERTASTE") { $vk = 0x20 }
    else { return $null }
    return @{ Mods = $mods; Key = $vk; Text = (($names + $k) -join "+") }
}

function ConvertTo-GridLayout {
    # Columns (Name, DisplayIndex, FillWeight, Visible) -> storable list
    param([array]$Columns)
    return @($Columns | ForEach-Object { [PSCustomObject]@{ Name = [string]$_.Name; Index = [int]$_.DisplayIndex; Weight = [double]$_.FillWeight; Visible = [bool]$_.Visible } })
}

function Get-SnappedPosition {
    # Snaps a window rectangle to the edges of the working area within $Dist pixels
    param([int]$X, [int]$Y, [int]$W, [int]$H, [int]$AreaLeft, [int]$AreaTop, [int]$AreaRight, [int]$AreaBottom, [int]$Dist = 16)
    $nx = $X; $ny = $Y
    if ([math]::Abs($X - $AreaLeft) -le $Dist) { $nx = $AreaLeft }
    elseif ([math]::Abs(($X + $W) - $AreaRight) -le $Dist) { $nx = $AreaRight - $W }
    if ([math]::Abs($Y - $AreaTop) -le $Dist) { $ny = $AreaTop }
    elseif ([math]::Abs(($Y + $H) - $AreaBottom) -le $Dist) { $ny = $AreaBottom - $H }
    return @{ X = $nx; Y = $ny; Moved = ($nx -ne $X -or $ny -ne $Y) }
}

function Test-UndoValid {
    param($Undo, [DateTime]$Now = (Get-Date))
    return ($null -ne $Undo -and $null -ne $Undo.Until -and $Now -le [DateTime]$Undo.Until)
}

# ==============================================================================
# v4.8: log scale, chart event markers, version file
# ==============================================================================
function Get-PriceFrac {
    # Price -> 0..1 position between MinP and MinP+SpanP (linear or logarithmic)
    param([double]$V, [double]$MinP, [double]$SpanP, [bool]$Log = $false)
    if ($SpanP -eq 0) { return 0.5 }
    if (-not $Log) { return (($V - $MinP) / $SpanP) }
    $top = $MinP + $SpanP
    if ($MinP -le 0 -or $top -le 0) { return (($V - $MinP) / $SpanP) }
    if ($V -le 0) { return -0.05 }
    $l0 = [math]::Log($MinP)
    return (([math]::Log($V) - $l0) / ([math]::Log($top) - $l0))
}

function Get-PriceFromFrac {
    # Inverse of Get-PriceFrac
    param([double]$F, [double]$MinP, [double]$SpanP, [bool]$Log = $false)
    if (-not $Log -or $MinP -le 0 -or ($MinP + $SpanP) -le 0) { return ($MinP + $F * $SpanP) }
    $l0 = [math]::Log($MinP)
    $l1 = [math]::Log($MinP + $SpanP)
    return [math]::Exp($l0 + $F * ($l1 - $l0))
}

function Get-LogPaddedRange {
    # Min/max with 8 % padding in log space; $null when log is impossible (<= 0)
    param([double]$Min, [double]$Max, [double]$Pad = 0.08)
    if ($Min -le 0 -or $Max -le 0) { return $null }
    $a = [math]::Log($Min); $b = [math]::Log($Max)
    if ($b -le $a) { $b = $a + 0.01 }
    $p = ($b - $a) * $Pad
    return @{ Min = [math]::Exp($a - $p); Max = [math]::Exp($b + $p) }
}

function ConvertFrom-ChartDividendEvents {
    # chart result (events=div) -> @(@{ Ts = unix seconds; Amount })
    param($Result)
    $out = @()
    try {
        $d = $Result.events.dividends
        if ($null -ne $d) {
            foreach ($p in $d.PSObject.Properties) {
                $e = $p.Value
                if ($null -ne $e -and $null -ne $e.date -and [double]$e.amount -gt 0) { $out += @{ Ts = [long]$e.date; Amount = [double]$e.amount } }
            }
        }
    } catch { }
    return @($out | Sort-Object -Property @{ Expression = { $_.Ts } })
}

function Get-NearestBarIndex {
    # Index of the bar whose time (ms) is closest to $TsMs, -1 when farther than $MaxGapMs
    param([long[]]$BarTsMs, [long]$TsMs, [long]$MaxGapMs)
    $best = -1; $bd = [long]::MaxValue
    for ($i = 0; $i -lt @($BarTsMs).Count; $i++) {
        $d = [math]::Abs([long]$BarTsMs[$i] - $TsMs)
        if ($d -lt $bd) { $bd = $d; $best = $i }
    }
    if ($best -lt 0 -or $bd -gt $MaxGapMs) { return -1 }
    return $best
}

function Get-LatestVersionFromJson {
    # version.json in the repository: { "version": "4.8" }
    param($Json)
    try { $v = [string]$Json.version } catch { $v = "" }
    if ($v -match '^\d+(\.\d+){1,2}$') { return $v }
    return ""
}

# ==============================================================================
# v5.0 Stage A: cash, risk, rebalancing, savings plans, heatmap
# ==============================================================================
function Get-CashMovements {
    # Trades booked after cash tracking started (Id not in ExcludeIds) plus the
    # cash ledger -> @(@{ Date; Kind; Ticker; Amount (signed); Currency; Source; Id }) oldest first.
    # Buy = -(shares x price + fee), sell = +(shares x price - fee), dividend = +(amount - fee).
    param($Transactions, $Entries, [string[]]$ExcludeIds = @())
    $skip = New-Object System.Collections.Generic.HashSet[string]
    foreach ($i in @($ExcludeIds)) { if ($i) { [void]$skip.Add([string]$i) } }
    $out = @()
    foreach ($t in @($Transactions)) {
        if ($null -eq $t -or $skip.Contains([string]$t.Id)) { continue }
        $sh = [double]$t.Shares; $px = [double]$t.Price; $fee = [double]$t.Fee
        $amt = switch ([string]$t.Type) {
            "Kauf"      { -($sh * $px + $fee) }
            "Verkauf"   { $sh * $px - $fee }
            "Dividende" { $px - $fee }
            default     { $null }
        }
        if ($null -eq $amt) { continue }
        $out += [PSCustomObject]@{ Date = [string]$t.Date; Kind = [string]$t.Type; Ticker = ([string]$t.Ticker).ToUpper(); Amount = [double]$amt; Currency = ([string]$t.Currency).ToUpper(); Source = "Trade"; Id = [string]$t.Id }
    }
    foreach ($e in @($Entries)) {
        if ($null -eq $e) { continue }
        $out += [PSCustomObject]@{ Date = [string]$e.Date; Kind = [string]$e.Kind; Ticker = ""; Amount = [double]$e.Amount; Currency = ([string]$e.Currency).ToUpper(); Source = "Cash"; Id = [string]$e.Id }
    }
    return @($out | Sort-Object -Property @{ Expression = { $_.Date } }, @{ Expression = { $_.Source -eq "Trade" } })
}

function Get-CashBalance {
    # Sum of movements in Currency; Rates: other currency -> factor into Currency.
    # Currencies without a rate are left out and listed in Missing.
    param($Movements, [string]$Currency, [hashtable]$Rates = @{})
    $cc = ([string]$Currency).ToUpper()
    $sum = 0.0
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($m in @($Movements)) {
        if ($null -eq $m) { continue }
        $mc = ([string]$m.Currency).ToUpper()
        if (-not $mc -or $mc -eq $cc) { $sum += [double]$m.Amount; continue }
        $f = $Rates[$mc]
        if ($null -eq $f -or [double]::IsNaN([double]$f) -or [double]$f -le 0) { if (-not $missing.Contains($mc)) { $missing.Add($mc) }; continue }
        $sum += [double]$m.Amount * [double]$f
    }
    return [PSCustomObject]@{ Balance = $sum; Missing = @($missing) }
}

function Get-FlowAdjustedReturns {
    # Value history with deposits / withdrawals -> period returns that ignore
    # the flows: (V_t + dDividends - dInvested) / V_(t-1) - 1
    param([double[]]$Value, [double[]]$Invested, [double[]]$Dividends = $null)
    $out = New-Object System.Collections.Generic.List[double]
    if ($null -eq $Value -or $Value.Count -lt 2) { return }
    for ($i = 1; $i -lt $Value.Count; $i++) {
        $v0 = [double]$Value[$i - 1]
        if ($v0 -le 0 -or [double]::IsNaN($v0) -or [double]::IsNaN([double]$Value[$i])) { continue }
        $dI = if ($null -ne $Invested -and $Invested.Count -gt $i) { [double]$Invested[$i] - [double]$Invested[$i - 1] } else { 0.0 }
        $dD = if ($null -ne $Dividends -and $Dividends.Count -gt $i) { [double]$Dividends[$i] - [double]$Dividends[$i - 1] } else { 0.0 }
        $out.Add((([double]$Value[$i] + $dD - $dI) / $v0) - 1.0)
    }
    return $out.ToArray()
}

function Get-PeriodsPerYear {
    # Data points per year from the date axis (daily trading data ~252)
    param([string[]]$Dates)
    if ($null -eq $Dates -or $Dates.Count -lt 2) { return 252.0 }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $a = [DateTime]::ParseExact([string]$Dates[0], "yyyy-MM-dd", $inv)
    $b = [DateTime]::ParseExact([string]$Dates[$Dates.Count - 1], "yyyy-MM-dd", $inv)
    $years = ($b - $a).TotalDays / 365.25
    if ($years -le 0.02) { return 252.0 }
    return [math]::Max(1.0, ($Dates.Count - 1) / $years)
}

function Get-ReturnStats {
    # Returns (fractions per period) -> annualized return / volatility in %,
    # Sharpe (risk-free in % p.a.), max drawdown in % with its peak/trough
    # period, best/worst period
    param([double[]]$Returns, [double]$PeriodsPerYear = 252, [double]$RiskFreePct = 0.0)
    $o = [PSCustomObject]@{ N = 0; AnnReturn = [double]::NaN; Vol = [double]::NaN; Sharpe = [double]::NaN; MaxDd = [double]::NaN
        DdPeak = -1; DdTrough = -1; Best = [double]::NaN; BestIdx = -1; Worst = [double]::NaN; WorstIdx = -1; Total = [double]::NaN }
    if ($null -eq $Returns -or $Returns.Count -lt 2) { return $o }
    $n = $Returns.Count
    $o.N = $n
    $mean = 0.0; foreach ($r in $Returns) { $mean += $r }; $mean /= $n
    $ss = 0.0; foreach ($r in $Returns) { $ss += ($r - $mean) * ($r - $mean) }
    $sd = [math]::Sqrt($ss / ($n - 1))
    $o.Vol = $sd * [math]::Sqrt($PeriodsPerYear) * 100.0
    $idx = 1.0; $peak = 1.0; $peakI = -1; $maxDd = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $r = $Returns[$i]
        $idx *= (1.0 + $r)
        if ($idx -gt $peak) { $peak = $idx; $peakI = $i }
        $dd = $idx / $peak - 1.0
        if ($dd -lt $maxDd) { $maxDd = $dd; $o.DdPeak = $peakI; $o.DdTrough = $i }
        if ($o.BestIdx -lt 0 -or $r -gt $o.Best) { $o.Best = $r; $o.BestIdx = $i }
        if ($o.WorstIdx -lt 0 -or $r -lt $o.Worst) { $o.Worst = $r; $o.WorstIdx = $i }
    }
    $o.Total = ($idx - 1.0) * 100.0
    $o.MaxDd = $maxDd * 100.0
    $o.Best *= 100.0; $o.Worst *= 100.0
    $years = $n / $PeriodsPerYear
    if ($idx -gt 0 -and $years -gt 0) { $o.AnnReturn = ([math]::Pow($idx, 1.0 / $years) - 1.0) * 100.0 }
    if ($o.Vol -gt 0) { $o.Sharpe = ($o.AnnReturn - $RiskFreePct) / $o.Vol }
    return $o
}

function Get-Correlation {
    # Pearson correlation of two equally long series (NaN below 3 points)
    param([double[]]$A, [double[]]$B)
    $n = [math]::Min(@($A).Count, @($B).Count)
    if ($n -lt 3) { return [double]::NaN }
    $ma = 0.0; $mb = 0.0
    for ($i = 0; $i -lt $n; $i++) { $ma += $A[$i]; $mb += $B[$i] }
    $ma /= $n; $mb /= $n
    $c = 0.0; $va = 0.0; $vb = 0.0
    for ($i = 0; $i -lt $n; $i++) { $da = $A[$i] - $ma; $db = $B[$i] - $mb; $c += $da * $db; $va += $da * $da; $vb += $db * $db }
    if ($va -le 0 -or $vb -le 0) { return [double]::NaN }
    return $c / [math]::Sqrt($va * $vb)
}

function Get-Beta {
    # Sensitivity of R to the benchmark B: cov(R, B) / var(B)
    param([double[]]$R, [double[]]$B)
    $n = [math]::Min(@($R).Count, @($B).Count)
    if ($n -lt 3) { return [double]::NaN }
    $mr = 0.0; $mb = 0.0
    for ($i = 0; $i -lt $n; $i++) { $mr += $R[$i]; $mb += $B[$i] }
    $mr /= $n; $mb /= $n
    $c = 0.0; $vb = 0.0
    for ($i = 0; $i -lt $n; $i++) { $c += ($R[$i] - $mr) * ($B[$i] - $mb); $vb += ($B[$i] - $mb) * ($B[$i] - $mb) }
    if ($vb -le 0) { return [double]::NaN }
    return $c / $vb
}

function Get-DailyReturnsByDate {
    # Closes on dates -> hashtable date -> return vs. the previous close
    param([string[]]$Dates, [double[]]$Closes, [string]$FromDate = "")
    $h = @{}
    if ($null -eq $Dates -or $null -eq $Closes) { return $h }
    $n = [math]::Min($Dates.Count, $Closes.Count)
    for ($i = 1; $i -lt $n; $i++) {
        $p0 = [double]$Closes[$i - 1]; $p1 = [double]$Closes[$i]
        if ($p0 -le 0 -or $p1 -le 0 -or [double]::IsNaN($p0) -or [double]::IsNaN($p1)) { continue }
        if ($FromDate -and [string]::CompareOrdinal([string]$Dates[$i], $FromDate) -lt 0) { continue }
        $h[[string]$Dates[$i]] = $p1 / $p0 - 1.0
    }
    return $h
}

function Get-CorrelationMatrix {
    # sym -> (date -> return) => @{ Syms; M = double[,]; Counts = int[,] } on common dates
    param([hashtable]$BySym, [int]$MinCommon = 20)
    $syms = @($BySym.Keys | Sort-Object)
    $n = $syms.Count
    $m = New-Object 'double[,]' $n, $n
    $cnt = New-Object 'int[,]' $n, $n
    for ($i = 0; $i -lt $n; $i++) {
        $m[$i, $i] = 1.0
        for ($j = $i + 1; $j -lt $n; $j++) {
            $a = $BySym[$syms[$i]]; $b = $BySym[$syms[$j]]
            $xa = New-Object System.Collections.Generic.List[double]; $xb = New-Object System.Collections.Generic.List[double]
            foreach ($d in $a.Keys) { if ($b.ContainsKey($d)) { $xa.Add([double]$a[$d]); $xb.Add([double]$b[$d]) } }
            $c = if ($xa.Count -ge $MinCommon) { Get-Correlation -A $xa.ToArray() -B $xb.ToArray() } else { [double]::NaN }
            $m[$i, $j] = $c; $m[$j, $i] = $c
            $cnt[$i, $j] = $xa.Count; $cnt[$j, $i] = $xa.Count
        }
    }
    return [PSCustomObject]@{ Syms = $syms; M = $m; Counts = $cnt }
}

function Get-RebalancePlan {
    # Positions: @(@{ Sym; Value; Price }) in one currency; Targets: sym -> % .
    # Only positions with a target take part; Money (cash + new money) can be
    # invested. BuyOnly: no sales, the money goes to the most underweight
    # positions. -> @{ Rows; Base; Invest; Left; TargetSum }
    param($Positions, [hashtable]$Targets, [double]$Money = 0.0, [bool]$BuyOnly = $false)
    $rows = @()
    $sumV = 0.0; $tSum = 0.0
    foreach ($p in @($Positions)) {
        if ($null -eq $p) { continue }
        $s = ([string]$p.Sym).ToUpper()
        if (-not $Targets.ContainsKey($s)) { continue }
        $t = [math]::Max(0.0, [double]$Targets[$s])
        $sumV += [double]$p.Value; $tSum += $t
        $rows += [PSCustomObject]@{ Sym = $s; Value = [double]$p.Value; Price = [double]$p.Price; Target = $t; Pct = 0.0; TargetValue = 0.0; Drift = 0.0; Trade = 0.0; Shares = 0.0; After = 0.0 }
    }
    $money = [math]::Max(0.0, $Money)
    $base = $sumV + $money
    $res = [PSCustomObject]@{ Rows = $rows; Base = $base; Invest = 0.0; Left = $money; TargetSum = $tSum }
    if ($rows.Count -eq 0 -or $base -le 0) { return $res }
    foreach ($r in $rows) {
        $r.Pct = if ($sumV -gt 0) { $r.Value / $sumV * 100.0 } else { 0.0 }
        $r.TargetValue = $base * $r.Target / 100.0
        $r.Drift = $r.Pct - $r.Target
        $r.Trade = $r.TargetValue - $r.Value
    }
    if ($BuyOnly) {
        $short = 0.0
        foreach ($r in $rows) { if ($r.Trade -gt 0) { $short += $r.Trade } else { $r.Trade = 0.0 } }
        $f = if ($short -gt $money -and $short -gt 0) { $money / $short } else { 1.0 }
        foreach ($r in $rows) { $r.Trade = $r.Trade * $f }
    }
    $net = 0.0
    foreach ($r in $rows) {
        if ([math]::Abs($r.Trade) -lt 0.005) { $r.Trade = 0.0 }
        $r.Shares = if ($r.Price -gt 0) { $r.Trade / $r.Price } else { 0.0 }
        $r.After = $r.Value + $r.Trade
        $net += $r.Trade
    }
    $res.Invest = $net
    $res.Left = $money - $net
    return $res
}

function Get-DueSavingsDates {
    # Savings plan (Day 1-28, Start, LastBooked as yyyy-MM-dd) -> booking
    # dates after LastBooked (or from Start) up to Today, at most 24
    param($Plan, [string]$Today)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $out = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Plan -or -not $Plan.Start) { return @($out) }
    $day = [math]::Max(1, [math]::Min(28, [int]$Plan.Day))
    $start = [DateTime]::ParseExact([string]$Plan.Start, "yyyy-MM-dd", $inv)
    $after = if ($Plan.LastBooked) { [DateTime]::ParseExact([string]$Plan.LastBooked, "yyyy-MM-dd", $inv) } else { $start.AddDays(-1) }
    $today = [DateTime]::ParseExact($Today, "yyyy-MM-dd", $inv)
    $m = New-Object DateTime($start.Year, $start.Month, 1)
    # v5.5: pause months (e.g. "7,8" or "Jul, Aug") are skipped, not caught up later
    $pause = @()
    if ($null -ne $Plan.PSObject.Properties["Pause"]) { $pause = @(ConvertTo-PauseMonths ([string]$Plan.Pause)) }
    while ($m -le $today -and $out.Count -lt 24) {
        $d = New-Object DateTime($m.Year, $m.Month, $day)
        if ($d -ge $start -and $d -gt $after -and $d -le $today -and $pause -notcontains $d.Month) { $out.Add($d.ToString("yyyy-MM-dd", $inv)) }
        $m = $m.AddMonths(1)
    }
    return @($out)
}

function Get-CloseOnOrBefore {
    # Last close on or before Date (weekend / holiday -> the trading day before)
    param([string[]]$Dates, [double[]]$Closes, [string]$Date)
    if ($null -eq $Dates -or $null -eq $Closes) { return $null }
    $best = -1
    for ($i = 0; $i -lt [math]::Min($Dates.Count, $Closes.Count); $i++) {
        if ([string]::CompareOrdinal([string]$Dates[$i], $Date) -le 0 -and [double]$Closes[$i] -gt 0) { $best = $i }
    }
    if ($best -lt 0) { return $null }
    return [PSCustomObject]@{ Date = [string]$Dates[$best]; Close = [double]$Closes[$best] }
}

function Get-TreemapRects {
    # Squarified treemap: values -> @(x, y, w, h) per value (input order).
    # Zero / negative values get an empty rect.
    param([double[]]$Values, [double]$X, [double]$Y, [double]$W, [double]$H)
    $n = @($Values).Count
    $rects = New-Object 'object[]' $n
    for ($i = 0; $i -lt $n; $i++) { $rects[$i] = @(0.0, 0.0, 0.0, 0.0) }
    $idx = @(0..($n - 1) | Where-Object { $n -gt 0 -and [double]$Values[$_] -gt 0 } | Sort-Object -Property @{ Expression = { [double]$Values[$_] }; Descending = $true }, @{ Expression = { [int]$_ }; Descending = $false })   # stable on 5.1 too
    $total = 0.0; foreach ($i in $idx) { $total += [double]$Values[$i] }
    if ($idx.Count -eq 0 -or $total -le 0 -or $W -le 0 -or $H -le 0) { return ,$rects }
    $scale = ($W * $H) / $total
    $rx = $X; $ry = $Y; $rw = $W; $rh = $H
    $worst = {
        param($Areas, [double]$Side)
        $s = 0.0; $mx = 0.0; $mn = [double]::MaxValue
        foreach ($a in $Areas) { $s += $a; if ($a -gt $mx) { $mx = $a }; if ($a -lt $mn) { $mn = $a } }
        if ($s -le 0 -or $Side -le 0) { return [double]::MaxValue }
        return [math]::Max(($Side * $Side * $mx) / ($s * $s), ($s * $s) / ($Side * $Side * $mn))
    }
    $pos = 0
    while ($pos -lt $idx.Count) {
        $side = [math]::Min($rw, $rh)
        $row = New-Object System.Collections.Generic.List[int]
        $areas = New-Object System.Collections.Generic.List[double]
        $row.Add($idx[$pos]); $areas.Add([double]$Values[$idx[$pos]] * $scale); $pos++
        while ($pos -lt $idx.Count) {
            $cand = New-Object System.Collections.Generic.List[double]
            $cand.AddRange($areas)
            $cand.Add([double]$Values[$idx[$pos]] * $scale)
            if ((& $worst $cand $side) -le (& $worst $areas $side)) { $row.Add($idx[$pos]); $areas.Add([double]$Values[$idx[$pos]] * $scale); $pos++ } else { break }
        }
        $sumA = 0.0; foreach ($a in $areas) { $sumA += $a }
        if ($rw -ge $rh) {
            # column on the left
            $cw = if ($rh -gt 0) { $sumA / $rh } else { 0.0 }
            $yy = $ry
            for ($k = 0; $k -lt $row.Count; $k++) { $hh = if ($cw -gt 0) { $areas[$k] / $cw } else { 0.0 }; $rects[$row[$k]] = @($rx, $yy, $cw, $hh); $yy += $hh }
            $rx += $cw; $rw -= $cw
        } else {
            # row on top
            $chh = if ($rw -gt 0) { $sumA / $rw } else { 0.0 }
            $xx = $rx
            for ($k = 0; $k -lt $row.Count; $k++) { $ww = if ($chh -gt 0) { $areas[$k] / $chh } else { 0.0 }; $rects[$row[$k]] = @($xx, $ry, $ww, $chh); $xx += $ww }
            $ry += $chh; $rh -= $chh
        }
    }
    return ,$rects
}

# ==============================================================================
# v5.0 Stage B: chart drawings, Heikin-Ashi, trend line alerts
# ==============================================================================
function Get-FracIndexAtTs {
    # Bars are drawn evenly spaced: a time -> fractional bar index (linear
    # between two bars, extrapolated with the average spacing beyond the ends)
    param([long[]]$BarTs, [long]$Ts)
    $n = @($BarTs).Count
    if ($n -eq 0) { return [double]::NaN }
    if ($n -eq 1) { return 0.0 }
    $avg = [double]($BarTs[$n - 1] - $BarTs[0]) / ($n - 1)
    if ($avg -le 0) { return 0.0 }
    if ($Ts -le $BarTs[0]) { return [double]($Ts - $BarTs[0]) / $avg }
    if ($Ts -ge $BarTs[$n - 1]) { return ($n - 1) + [double]($Ts - $BarTs[$n - 1]) / $avg }
    $lo = 0; $hi = $n - 1
    while ($hi - $lo -gt 1) { $mid = [int](($lo + $hi) / 2); if ($BarTs[$mid] -le $Ts) { $lo = $mid } else { $hi = $mid } }
    $span = [double]($BarTs[$hi] - $BarTs[$lo])
    if ($span -le 0) { return [double]$lo }
    return $lo + [double]($Ts - $BarTs[$lo]) / $span
}

function Get-TsAtFracIndex {
    # Inverse of Get-FracIndexAtTs
    param([long[]]$BarTs, [double]$Idx)
    $n = @($BarTs).Count
    if ($n -eq 0) { return 0L }
    if ($n -eq 1) { return [long]$BarTs[0] }
    $avg = [double]($BarTs[$n - 1] - $BarTs[0]) / ($n - 1)
    if ($Idx -le 0) { return [long]([double]$BarTs[0] + $Idx * $avg) }
    if ($Idx -ge ($n - 1)) { return [long]([double]$BarTs[$n - 1] + ($Idx - ($n - 1)) * $avg) }
    $i = [int][math]::Floor($Idx)
    $f = $Idx - $i
    return [long]([double]$BarTs[$i] + $f * [double]($BarTs[$i + 1] - $BarTs[$i]))
}

function Get-FibLevels {
    # Retracement from P1 (start of the move) to P2 (end): 0 % = P2, 100 % = P1
    param([double]$P1, [double]$P2)
    $out = @()
    foreach ($pc in @(0.0, 23.6, 38.2, 50.0, 61.8, 78.6, 100.0)) { $out += [PSCustomObject]@{ Pct = $pc; Price = $P2 - ($P2 - $P1) * $pc / 100.0 } }
    return $out
}

function Get-PointLineDistance {
    # Pixel distance of (X, Y) to the segment (X1,Y1)-(X2,Y2); Ray = extends past (X2,Y2)
    param([double]$X, [double]$Y, [double]$X1, [double]$Y1, [double]$X2, [double]$Y2, [bool]$Ray = $false)
    $dx = $X2 - $X1; $dy = $Y2 - $Y1
    $len2 = $dx * $dx + $dy * $dy
    if ($len2 -le 0) { return [math]::Sqrt(($X - $X1) * ($X - $X1) + ($Y - $Y1) * ($Y - $Y1)) }
    $t = (($X - $X1) * $dx + ($Y - $Y1) * $dy) / $len2
    if ($t -lt 0) { $t = 0.0 }
    if (-not $Ray -and $t -gt 1) { $t = 1.0 }
    $px = $X1 + $t * $dx; $py = $Y1 + $t * $dy
    return [math]::Sqrt(($X - $px) * ($X - $px) + ($Y - $py) * ($Y - $py))
}

function Get-TrendPriceAt {
    # Price of a trend line (two points in time) at time T, linear in time
    param([long]$T1, [double]$P1, [long]$T2, [double]$P2, [long]$T)
    if ($T2 -eq $T1) { return [double]::NaN }
    return $P1 + ($P2 - $P1) * ([double]($T - $T1) / [double]($T2 - $T1))
}

function ConvertTo-HeikinAshi {
    # Bars (Ts, Open, High, Low, Close, Volume) -> Heikin-Ashi bars:
    # close = (O+H+L+C)/4, open = (previous HA open + previous HA close)/2
    param($Bars)
    $out = New-Object System.Collections.Generic.List[object]
    $po = [double]::NaN; $pc = [double]::NaN
    foreach ($b in @($Bars)) {
        if ($null -eq $b) { continue }
        $o = [double]$b.Open; $h = [double]$b.High; $l = [double]$b.Low; $c = [double]$b.Close
        if ($o -le 0) { $o = $c }
        $hc = ($o + $h + $l + $c) / 4.0
        $ho = if ([double]::IsNaN($po)) { ($o + $c) / 2.0 } else { ($po + $pc) / 2.0 }
        $out.Add([PSCustomObject]@{ Ts = $b.Ts; Open = $ho; High = [math]::Max($h, [math]::Max($ho, $hc)); Low = [math]::Min($l, [math]::Min($ho, $hc)); Close = $hc; Volume = $b.Volume })
        $po = $ho; $pc = $hc
    }
    return $out.ToArray()
}

function Get-NextChartType {
    # K key / button: Linie -> Kerzen -> Heikin-Ashi -> Linie
    param([string]$Current)
    switch ($Current) { "Line" { return "Candle" } "Candle" { return "HA" } default { return "Line" } }
}

function Set-CompareList {
    # v5.0: up to 3 comparison tickers. Adding a ticker that is already in
    # the list removes it. -> @{ List; Msg }
    param([string[]]$Current, [string]$Symbol, [int]$Max = 3)
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($c in @($Current)) { if ($c) { $u = ([string]$c).ToUpperInvariant(); if (-not $list.Contains($u)) { $list.Add($u) } } }
    $s = ([string]$Symbol).Trim().ToUpperInvariant()
    if (-not $s) { return [PSCustomObject]@{ List = @(); Msg = "removed all" } }
    if ($list.Contains($s)) { [void]$list.Remove($s); return [PSCustomObject]@{ List = @($list); Msg = "removed" } }
    if ($list.Count -ge $Max) { return [PSCustomObject]@{ List = @($list); Msg = "full" } }
    $list.Add($s)
    return [PSCustomObject]@{ List = @($list); Msg = "added" }
}

# ==============================================================================
# v5.0 Stage C: workspace (dividers, watchlist groups, settings search)
# ==============================================================================
function Get-DragPct {
    # Divider dragged to Pos inside a span starting at Start with Length -> % (clamped)
    param([double]$Pos, [double]$Start, [double]$Length, [double]$Min = 20, [double]$Max = 80)
    if ($Length -le 0) { return [math]::Round(($Min + $Max) / 2) }
    $p = ($Pos - $Start) / $Length * 100.0
    return [math]::Round([math]::Max($Min, [math]::Min($Max, $p)))
}

function Get-WatchGroupSymbols {
    # Watchlist (in its order) limited to a group; "" = all
    param([string[]]$Watchlist, $Groups, [string]$Group = "")
    $wl = @(@($Watchlist) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpperInvariant() })
    if (-not $Group) { return $wl }
    $g = @(@($Groups) | Where-Object { $null -ne $_ -and [string]$_.Name -eq $Group })
    if ($g.Count -eq 0) { return $wl }
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($s in @($g[0].Symbols)) { if ($s) { [void]$set.Add(([string]$s).ToUpperInvariant()) } }
    return @($wl | Where-Object { $set.Contains($_) })
}

function ConvertTo-FlatWatchGroups {
    # v8.0: before 8.0 the group list could be saved as a list inside a list
    # (and the next change then merged the groups). Returns a flat, clean list.
    param($Groups)
    $out = @()
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($Groups)
    while ($stack.Count -gt 0) {
        $g = $stack.Pop()
        if ($null -eq $g) { continue }
        if ($g -is [System.Array]) { for ($i = $g.Count - 1; $i -ge 0; $i--) { $stack.Push($g[$i]) }; continue }
        if ($g.Name) { $out += [PSCustomObject]@{ Name = [string]$g.Name; Symbols = @(@($g.Symbols) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpperInvariant() }) } }
    }
    return ,$out
}

function Set-WatchGroupMember {
    # Adds (In = $true) or removes a ticker in a group; a new name creates the
    # group. Returns the new group list (name order kept, empty groups stay).
    param($Groups, [string]$Group, [string]$Symbol, [bool]$In = $true)
    $out = @()
    $found = $false
    $s = ([string]$Symbol).Trim().ToUpperInvariant()
    foreach ($g in @($Groups)) {
        if ($null -eq $g -or -not $g.Name) { continue }
        $syms = @(@($g.Symbols) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpperInvariant() })
        if ([string]$g.Name -eq $Group) {
            $found = $true
            $syms = @($syms | Where-Object { $_ -ne $s })
            if ($In -and $s) { $syms += $s }
        }
        $out += [PSCustomObject]@{ Name = [string]$g.Name; Symbols = @($syms) }
    }
    if (-not $found -and $Group -and $In) { $out += [PSCustomObject]@{ Name = $Group; Symbols = @($(if ($s) { $s })) } }
    return ,$out
}

function ConvertTo-SearchKey {
    # lower case, umlauts and ß folded, so "uber" finds "Über"
    param([string]$Text)
    $t = ([string]$Text).ToLowerInvariant()
    return ($t -replace 'ä', 'a' -replace 'ö', 'o' -replace 'ü', 'u' -replace 'ß', 'ss')
}

function Test-SettingMatch {
    # Settings search: every word of the query must appear in the text
    param([string]$Text, [string]$Query)
    $q = (ConvertTo-SearchKey $Query).Trim()
    if (-not $q) { return $false }
    $t = ConvertTo-SearchKey $Text
    foreach ($w in ($q -split '\s+')) { if ($w -and -not $t.Contains($w)) { return $false } }
    return $true
}

# ------------------------------------------------------------------------------
# v5.1: ticker analysis - technical signals, support / resistance, fundamentals
# ------------------------------------------------------------------------------
function ConvertFrom-YahooOhlc {
    # Yahoo chart JSON (interval 1d) -> daily bars without gaps
    param($Json)
    $o = [PSCustomObject]@{ Dates = @(); Open = @(); High = @(); Low = @(); Close = @(); Volume = @(); Currency = ""; Name = "" }
    $r = Get-ChartResult $Json
    if ($null -eq $r -or $null -eq $r.timestamp -or $null -eq $r.indicators) { return $null }
    $raw = [string]$r.meta.currency
    $unit = Normalize-CurrencyAndPrice -Price 1.0 -RawCurrency $raw
    $o.Currency = [string]$unit.Currency
    $o.Name = if ($r.meta.shortName) { [string]$r.meta.shortName } else { [string]$r.meta.symbol }
    $q = $r.indicators.quote[0]
    $ts = @($r.timestamp); $c = @($q.close); $op = @($q.open); $hi = @($q.high); $lo = @($q.low); $vo = @($q.volume)
    $d = New-Object System.Collections.Generic.List[string]
    $lO = New-Object System.Collections.Generic.List[double]; $lH = New-Object System.Collections.Generic.List[double]
    $lL = New-Object System.Collections.Generic.List[double]; $lC = New-Object System.Collections.Generic.List[double]
    $lV = New-Object System.Collections.Generic.List[double]
    $gmt = if ($null -ne $r.meta.gmtoffset) { [int]$r.meta.gmtoffset } else { 0 }
    for ($i = 0; $i -lt [math]::Min($ts.Count, $c.Count); $i++) {
        if ($null -eq $c[$i] -or [double]$c[$i] -le 0) { continue }
        $cc = [double]$c[$i] * $unit.Price
        $d.Add([DateTimeOffset]::FromUnixTimeSeconds([long]$ts[$i] + $gmt).UtcDateTime.ToString("yyyy-MM-dd"))
        $lC.Add($cc)
        $lO.Add($(if ($i -lt $op.Count -and $null -ne $op[$i]) { [double]$op[$i] * $unit.Price } else { $cc }))
        $lH.Add($(if ($i -lt $hi.Count -and $null -ne $hi[$i]) { [double]$hi[$i] * $unit.Price } else { $cc }))
        $lL.Add($(if ($i -lt $lo.Count -and $null -ne $lo[$i]) { [double]$lo[$i] * $unit.Price } else { $cc }))
        $lV.Add($(if ($i -lt $vo.Count -and $null -ne $vo[$i]) { [double]$vo[$i] } else { 0.0 }))
    }
    if ($lC.Count -eq 0) { return $null }
    $o.Dates = $d.ToArray(); $o.Open = $lO.ToArray(); $o.High = $lH.ToArray(); $o.Low = $lL.ToArray(); $o.Close = $lC.ToArray(); $o.Volume = $lV.ToArray()
    return $o
}

function Get-SupportResistance {
    # Swing highs / lows (Wing bars lower / higher on each side) of the last
    # Lookback bars, grouped when within TolPct of each other. Returns the
    # nearest group below the last close (support) and above (resistance).
    param([double[]]$Highs, [double[]]$Lows, [double[]]$Closes, [int]$Lookback = 250, [int]$Wing = 5, [double]$TolPct = 1.5)
    $n = @($Closes).Count
    $res = [PSCustomObject]@{ Support = [double]::NaN; SupportTouches = 0; Resistance = [double]::NaN; ResistanceTouches = 0; Levels = @() }
    if ($n -lt (2 * $Wing + 3)) { return $res }
    $from = [math]::Max($Wing, $n - $Lookback)
    $pts = New-Object System.Collections.Generic.List[double]
    for ($i = $from; $i -lt ($n - $Wing); $i++) {
        $isH = $true; $isL = $true
        for ($k = 1; $k -le $Wing; $k++) {
            if ($Highs[$i - $k] -gt $Highs[$i] -or $Highs[$i + $k] -gt $Highs[$i]) { $isH = $false }
            if ($Lows[$i - $k] -lt $Lows[$i] -or $Lows[$i + $k] -lt $Lows[$i]) { $isL = $false }
        }
        if ($isH) { $pts.Add([double]$Highs[$i]) }
        if ($isL) { $pts.Add([double]$Lows[$i]) }
    }
    if ($pts.Count -eq 0) { return $res }
    $sorted = @($pts.ToArray() | Sort-Object)
    $groups = New-Object System.Collections.Generic.List[PSObject]
    $cur = New-Object System.Collections.Generic.List[double]
    foreach ($p in $sorted) {
        if ($cur.Count -gt 0) {
            $avg = ($cur | Measure-Object -Average).Average
            if ([math]::Abs($p - $avg) / $avg * 100.0 -gt $TolPct) { $groups.Add([PSCustomObject]@{ Level = $avg; Touches = $cur.Count }); $cur = New-Object System.Collections.Generic.List[double] }
        }
        $cur.Add($p)
    }
    if ($cur.Count -gt 0) { $groups.Add([PSCustomObject]@{ Level = ($cur | Measure-Object -Average).Average; Touches = $cur.Count }) }
    $last = [double]$Closes[$n - 1]
    foreach ($g in $groups) {
        if ($g.Level -lt $last * 0.995) { if ([double]::IsNaN($res.Support) -or $g.Level -gt $res.Support) { $res.Support = [double]$g.Level; $res.SupportTouches = [int]$g.Touches } }
        elseif ($g.Level -gt $last * 1.005) { if ([double]::IsNaN($res.Resistance) -or $g.Level -lt $res.Resistance) { $res.Resistance = [double]$g.Level; $res.ResistanceTouches = [int]$g.Touches } }
    }
    $res.Levels = $groups.ToArray()
    return $res
}

function Get-TechnicalSignals {
    # Signal table for one ticker from daily bars. Score per row: +1 positive,
    # -1 negative, 0 neutral / information. Not advice - a summary of the
    # classic indicators.
    param([double[]]$Closes, [double[]]$Highs = $null, [double[]]$Lows = $null, [double[]]$Volumes = $null)
    $n = @($Closes).Count
    $rows = New-Object System.Collections.Generic.List[PSObject]
    $out = [PSCustomObject]@{ Rows = @(); Score = 0; Positive = 0; Negative = 0; Summary = ""; Support = $null }
    if ($n -lt 30) { $out.Summary = "Zu wenig Kursdaten"; return $out }
    if ($null -eq $Highs -or $Highs.Count -ne $n) { $Highs = $Closes }
    if ($null -eq $Lows -or $Lows.Count -ne $n) { $Lows = $Closes }
    $last = [double]$Closes[$n - 1]
    $add = { param([string]$K, [string]$Name, [string]$Val, [int]$Sc, [string]$Txt) $rows.Add([PSCustomObject]@{ Key = $K; Name = $Name; Value = $Val; Score = $Sc; Text = $Txt }) }
    $pctTo = { param([double]$x) if ($x -gt 0) { ($last / $x - 1.0) * 100.0 } else { [double]::NaN } }
    $s20 = Compute-Sma -Prices $Closes -Period 20
    $s50 = Compute-Sma -Prices $Closes -Period 50
    $s200 = Compute-Sma -Prices $Closes -Period 200
    foreach ($t in @(@(200, $s200, "Trend lang (SMA 200)"), @(50, $s50, "Trend mittel (SMA 50)"), @(20, $s20, "Trend kurz (SMA 20)"))) {
        $sv = [double]$t[1][$n - 1]
        if ([double]::IsNaN($sv)) { & $add ("SMA" + $t[0]) $t[2] "-" 0 "zu wenig Daten"; continue }
        $d = & $pctTo $sv
        & $add ("SMA" + $t[0]) $t[2] ("{0:N2} ({1:+0.0;-0.0}%)" -f $sv, $d) $(if ($d -ge 0) { 1 } else { -1 }) $(if ($d -ge 0) { "Kurs darüber" } else { "Kurs darunter" })
    }
    if (-not [double]::IsNaN([double]$s200[$n - 1])) {
        $gold = ([double]$s50[$n - 1] -gt [double]$s200[$n - 1])
        $since = 0
        for ($i = $n - 1; $i -ge 1; $i--) {
            if ([double]::IsNaN([double]$s200[$i - 1])) { break }
            if ((([double]$s50[$i - 1] -gt [double]$s200[$i - 1])) -ne $gold) { break }
            $since++
        }
        $txt = if ($gold) { "Golden Cross" } else { "Death Cross" }
        & $add "CROSS" "SMA 50 / SMA 200" ("{0} {1}" -f $since, "Tage") $(if ($gold) { 1 } else { -1 }) ("{0} seit {1} Handelstagen" -f $txt, $since)
    }
    $rsi = Compute-Rsi -Prices $Closes -Period 14
    $rv = [double]$rsi[$n - 1]
    if (-not [double]::IsNaN($rv)) {
        $rs = 0; $rt = "neutral"
        if ($rv -ge 70) { $rs = -1; $rt = "überkauft" } elseif ($rv -le 30) { $rs = 1; $rt = "überverkauft" } elseif ($rv -ge 50) { $rt = "neutral, eher stark" } else { $rt = "neutral, eher schwach" }
        & $add "RSI" "RSI 14" ("{0:N1}" -f $rv) $rs $rt
    }
    $m = Compute-Macd -Prices $Closes
    $mh = [double]$m.Hist[$n - 1]
    if (-not [double]::IsNaN($mh)) {
        $mh1 = [double]$m.Hist[$n - 2]
        $rising = (-not [double]::IsNaN($mh1)) -and $mh -gt $mh1
        & $add "MACD" "MACD (12/26/9)" ("{0:+0.000;-0.000}" -f $mh) $(if ($mh -ge 0) { 1 } else { -1 }) ("{0}, Histogramm {1}" -f $(if ($mh -ge 0) { "über der Signallinie" } else { "unter der Signallinie" }), $(if ($rising) { "steigt" } else { "fällt" }))
    }
    $bb = Compute-BollingerBands -Prices $Closes -Period 20 -Multiplier 2.0
    $bu = [double]$bb.Upper[$n - 1]; $bl = [double]$bb.Lower[$n - 1]
    if (-not [double]::IsNaN($bu) -and $bu -gt $bl) {
        $pb = ($last - $bl) / ($bu - $bl)
        $bs = 0; $bt = "innerhalb der Bänder"
        if ($pb -gt 1) { $bs = -1; $bt = "über dem oberen Band" } elseif ($pb -lt 0) { $bs = 1; $bt = "unter dem unteren Band" }
        & $add "BOLL" "Bollinger %B" ("{0:N2}" -f $pb) $bs $bt
    }
    foreach ($mm in @(@(63, "Momentum 3 Monate"), @(126, "Momentum 6 Monate"), @(252, "Momentum 12 Monate"))) {
        if ($n -gt $mm[0]) {
            $r = ($last / [double]$Closes[$n - 1 - $mm[0]] - 1.0) * 100.0
            & $add ("MOM" + $mm[0]) $mm[1] ("{0:+0.0;-0.0}%" -f $r) $(if ($r -ge 0) { 1 } else { -1 }) $(if ($r -ge 0) { "gestiegen" } else { "gefallen" })
        }
    }
    $w = [math]::Min(252, $n)
    $hi = ($Highs[($n - $w)..($n - 1)] | Measure-Object -Maximum).Maximum
    $lo = ($Lows[($n - $w)..($n - 1)] | Measure-Object -Minimum).Minimum
    if ($hi -gt $lo) {
        $pos = ($last - $lo) / ($hi - $lo) * 100.0
        & $add "RANGE" "52-Wochen-Spanne" ("{0:N0}%" -f $pos) 0 ("{0:+0.0;-0.0}% zum Hoch, {1:+0.0;-0.0}% zum Tief" -f (($last / $hi - 1) * 100.0), (($last / $lo - 1) * 100.0))
    }
    if ($n -ge 15) {
        $trs = New-Object double[] $n
        for ($i = 1; $i -lt $n; $i++) { $trs[$i] = [math]::Max([double]$Highs[$i] - [double]$Lows[$i], [math]::Max([math]::Abs([double]$Highs[$i] - [double]$Closes[$i - 1]), [math]::Abs([double]$Lows[$i] - [double]$Closes[$i - 1]))) }
        $atr = ($trs[($n - 14)..($n - 1)] | Measure-Object -Average).Average
        & $add "ATR" "Schwankung (ATR 14)" ("{0:N2} ({1:N1}%)" -f $atr, ($atr / $last * 100.0)) 0 "durchschnittliche Tagesspanne"
    }
    if ($null -ne $Volumes -and $Volumes.Count -eq $n -and $n -ge 60) {
        $v20 = ($Volumes[($n - 20)..($n - 1)] | Measure-Object -Average).Average
        $v60 = ($Volumes[($n - 60)..($n - 1)] | Measure-Object -Average).Average
        if ($v60 -gt 0) {
            $vr = $v20 / $v60
            & $add "VOL" "Volumen (20 zu 60 Tage)" ("{0:N2}x" -f $vr) 0 $(if ($vr -ge 1.2) { "mehr Umsatz als üblich" } elseif ($vr -le 0.8) { "weniger Umsatz als üblich" } else { "üblich" })
        }
    }
    $sr = Get-SupportResistance -Highs $Highs -Lows $Lows -Closes $Closes
    if (-not [double]::IsNaN($sr.Support)) { & $add "SUP" "Unterstützung" ("{0:N2} ({1:+0.0;-0.0}%)" -f $sr.Support, (($sr.Support / $last - 1) * 100.0)) 0 ("{0}x getestet" -f $sr.SupportTouches) }
    if (-not [double]::IsNaN($sr.Resistance)) { & $add "RES" "Widerstand" ("{0:N2} ({1:+0.0;-0.0}%)" -f $sr.Resistance, (($sr.Resistance / $last - 1) * 100.0)) 0 ("{0}x getestet" -f $sr.ResistanceTouches) }
    $out.Rows = $rows.ToArray()
    $out.Support = $sr
    foreach ($r in $rows) { $out.Score += $r.Score; if ($r.Score -gt 0) { $out.Positive++ } elseif ($r.Score -lt 0) { $out.Negative++ } }
    $out.Summary = if ($out.Score -ge 3) { "überwiegend positiv" } elseif ($out.Score -le -3) { "überwiegend negativ" } else { "gemischt" }
    return $out
}

function Get-FundamentalFields {
    # Key, label, kind (Ratio / Pct / Money / Plain), better (Low / High / ""), Yahoo module.field
    return @(
        @("MarketCap", "Börsenwert", "Money", "", "summaryDetail.marketCap"),
        @("TrailingPE", "KGV (12 Monate)", "Ratio", "Low", "summaryDetail.trailingPE"),
        @("ForwardPE", "KGV erwartet", "Ratio", "Low", "summaryDetail.forwardPE"),
        @("PEG", "PEG", "Ratio", "Low", "defaultKeyStatistics.pegRatio"),
        @("PriceToSales", "KUV", "Ratio", "Low", "summaryDetail.priceToSalesTrailing12Months"),
        @("PriceToBook", "KBV", "Ratio", "Low", "defaultKeyStatistics.priceToBook"),
        @("EvEbitda", "EV / EBITDA", "Ratio", "Low", "defaultKeyStatistics.enterpriseToEbitda"),
        @("DivYield", "Dividendenrendite", "Pct", "High", "summaryDetail.dividendYield"),
        @("Payout", "Ausschüttungsquote", "Pct", "", "summaryDetail.payoutRatio"),
        @("GrossMargin", "Bruttomarge", "Pct", "High", "financialData.grossMargins"),
        @("OpMargin", "Operative Marge", "Pct", "High", "financialData.operatingMargins"),
        @("ProfitMargin", "Nettomarge", "Pct", "High", "financialData.profitMargins"),
        @("ROE", "Eigenkapitalrendite", "Pct", "High", "financialData.returnOnEquity"),
        @("RevenueGrowth", "Umsatzwachstum", "Pct", "High", "financialData.revenueGrowth"),
        @("EarningsGrowth", "Gewinnwachstum", "Pct", "High", "financialData.earningsGrowth"),
        @("DebtToEquity", "Verschuldung (FK/EK)", "Plain", "Low", "financialData.debtToEquity"),
        @("CurrentRatio", "Liquidität (Current Ratio)", "Ratio", "High", "financialData.currentRatio"),
        @("FreeCashflow", "Free Cashflow", "Money", "", "financialData.freeCashflow"),
        @("Beta", "Beta", "Ratio", "", "summaryDetail.beta")
    )
}

function ConvertFrom-YahooFundamentals {
    param($Summary)
    $r = $null
    try { $r = $Summary.quoteSummary.result[0] } catch { $r = $null }
    if ($null -eq $r) { return $null }
    $o = [ordered]@{}
    $any = $false
    foreach ($f in (Get-FundamentalFields)) {
        $parts = $f[4].Split('.')
        $v = $r.($parts[0])
        if ($null -ne $v) { $v = $v.($parts[1]) }
        $x = [double]::NaN
        if ($null -ne $v) {
            if ($v -is [ValueType]) { $x = [double]$v } elseif ($null -ne $v.raw) { $x = [double]$v.raw }
        }
        if (-not [double]::IsNaN($x)) { $any = $true }
        $o[$f[0]] = $x
    }
    if ([double]::IsNaN([double]$o["ForwardPE"]) -and $null -ne $r.defaultKeyStatistics -and $null -ne $r.defaultKeyStatistics.forwardPE) {
        $fp = $r.defaultKeyStatistics.forwardPE
        if ($null -ne $fp.raw) { $o["ForwardPE"] = [double]$fp.raw; $any = $true }
    }
    $o["Currency"] = if ($null -ne $r.financialData -and $r.financialData.financialCurrency) { [string]$r.financialData.financialCurrency } elseif ($null -ne $r.summaryDetail -and $r.summaryDetail.currency) { [string]$r.summaryDetail.currency } else { "" }
    if (-not $any) { return $null }
    return [PSCustomObject]$o
}

function Get-Median {
    param([double[]]$Values)
    $v = @($Values | Where-Object { -not [double]::IsNaN([double]$_) } | Sort-Object)
    if ($v.Count -eq 0) { return [double]::NaN }
    if ($v.Count % 2 -eq 1) { return [double]$v[[int][math]::Floor($v.Count / 2)] }
    return ([double]$v[$v.Count / 2 - 1] + [double]$v[$v.Count / 2]) / 2.0
}

function Format-FundamentalValue {
    param([double]$X, [string]$Kind, [string]$Currency = "")
    if ([double]::IsNaN($X)) { return "-" }
    switch ($Kind) {
        "Pct"   { return ("{0:N1}%" -f ($X * 100.0)) }
        "Money" {
            $a = [math]::Abs($X)
            $t = if ($a -ge 1e12) { "{0:N2} Bio." -f ($X / 1e12) } elseif ($a -ge 1e9) { "{0:N1} Mrd." -f ($X / 1e9) } elseif ($a -ge 1e6) { "{0:N1} Mio." -f ($X / 1e6) } else { "{0:N0}" -f $X }
            return ("{0} {1}" -f $t, $Currency).Trim()
        }
        "Plain" { return ("{0:N0}%" -f $X) }
        default { return ("{0:N2}" -f $X) }
    }
}

function Get-FundamentalRows {
    # Rows for the ticker analysis: own value, median of the peers (your other
    # tickers in the same sector) and a rough classification (+1 / 0 / -1)
    param($Fund, [array]$Peers = @())
    $rows = @()
    if ($null -eq $Fund) { return $rows }
    $cur = [string]$Fund.Currency
    $num = {
        param($O, [string]$K)
        $pp = $O.PSObject.Properties[$K]
        if ($null -eq $pp -or $null -eq $pp.Value -or [string]$pp.Value -eq "") { return [double]::NaN }
        $d = 0.0
        if ([double]::TryParse([string]$pp.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
        try { return [double]$pp.Value } catch { return [double]::NaN }
    }
    foreach ($f in (Get-FundamentalFields)) {
        $k = $f[0]; $kind = $f[2]; $better = $f[3]
        $x = & $num $Fund $k
        $pv = @(@($Peers) | Where-Object { $null -ne $_ } | ForEach-Object { & $num $_ $k } | Where-Object { -not [double]::IsNaN($_) })
        $med = if ($pv.Count -ge 2) { Get-Median -Values ([double[]]$pv) } else { [double]::NaN }
        $sc = 0; $note = ""
        if (-not [double]::IsNaN($x)) {
            if (-not [double]::IsNaN($med) -and $better -and [math]::Abs($med) -gt 1e-12) {
                $rel = $x / $med
                $neg = ($k -in @("TrailingPE", "ForwardPE", "PEG", "EvEbitda") -and $x -le 0)
                if ($neg) { $sc = -1; $note = "negativ (Verlust)" }
                elseif ($better -eq "Low") { if ($rel -le 0.85) { $sc = 1; $note = "niedriger als Vergleich" } elseif ($rel -ge 1.15) { $sc = -1; $note = "höher als Vergleich" } else { $note = "ähnlich" } }
                else { if ($x -ge $med * 1.15 -or ($med -lt 0 -and $x -gt $med)) { $sc = 1; $note = "besser als Vergleich" } elseif ($x -le $med * 0.85) { $sc = -1; $note = "schwächer als Vergleich" } else { $note = "ähnlich" } }
            } else {
                switch ($k) {
                    "PEG"           { if ($x -gt 0 -and $x -lt 1) { $sc = 1; $note = "unter 1" } elseif ($x -gt 2) { $sc = -1; $note = "über 2" } }
                    "TrailingPE"    { if ($x -le 0) { $sc = -1; $note = "Verlust" } }
                    "DebtToEquity"  { if ($x -gt 200) { $sc = -1; $note = "hoch verschuldet" } elseif ($x -lt 50) { $sc = 1; $note = "wenig Schulden" } }
                    "CurrentRatio"  { if ($x -lt 1) { $sc = -1; $note = "unter 1" } elseif ($x -ge 1.5) { $sc = 1; $note = "solide" } }
                    "RevenueGrowth" { if ($x -gt 0.05) { $sc = 1; $note = "wächst" } elseif ($x -lt 0) { $sc = -1; $note = "schrumpft" } }
                    "EarningsGrowth" { if ($x -gt 0.05) { $sc = 1; $note = "wächst" } elseif ($x -lt 0) { $sc = -1; $note = "schrumpft" } }
                    "ProfitMargin"  { if ($x -lt 0) { $sc = -1; $note = "Verlust" } }
                    "Payout"        { if ($x -gt 1) { $sc = -1; $note = "mehr als der Gewinn" } }
                }
            }
        }
        $rows += [PSCustomObject]@{ Key = $k; Name = $f[1]; Value = (Format-FundamentalValue -X $x -Kind $kind -Currency $cur); Peer = (Format-FundamentalValue -X $med -Kind $kind -Currency $cur); PeerCount = $pv.Count; Score = $sc; Note = $note; X = $x; PeerValues = @($pv) }
    }
    return $rows
}

function ConvertTo-SectorKey {
    # "Financial Services" / "financial_services" -> "financialservices"
    param([string]$Name)
    return ((([string]$Name).ToLowerInvariant()) -replace '[^a-z]', '')
}

function ConvertFrom-YahooSectorWeights {
    # v5.1: quoteSummary topHoldings.sectorWeightings of an ETF -> sector key -> percent
    param($Summary)
    $out = @{}
    $r = $null
    try { $r = $Summary.quoteSummary.result[0] } catch { $r = $null }
    if ($null -eq $r -or $null -eq $r.topHoldings -or $null -eq $r.topHoldings.sectorWeightings) { return $out }
    foreach ($item in @($r.topHoldings.sectorWeightings)) {
        if ($null -eq $item) { continue }
        foreach ($pp in $item.PSObject.Properties) {
            $v = $pp.Value
            $x = [double]::NaN
            if ($v -is [ValueType]) { $x = [double]$v } elseif ($null -ne $v -and $null -ne $v.raw) { $x = [double]$v.raw }
            if (-not [double]::IsNaN($x)) { $out[(ConvertTo-SectorKey $pp.Name)] = $x * 100.0 }
        }
    }
    return $out
}

function Get-SectorComparison {
    # Depot groups (Key = sector name, Pct) against reference weights (key -> %)
    param([array]$Groups, [hashtable]$Reference)
    $names = @{
        "technology" = "Technology"; "financialservices" = "Financial Services"; "healthcare" = "Healthcare"
        "consumercyclical" = "Consumer Cyclical"; "industrials" = "Industrials"; "communicationservices" = "Communication Services"
        "consumerdefensive" = "Consumer Defensive"; "energy" = "Energy"; "basicmaterials" = "Basic Materials"
        "realestate" = "Real Estate"; "utilities" = "Utilities"
    }
    $dep = @{}
    $other = 0.0
    foreach ($g in @($Groups)) {
        if ($null -eq $g) { continue }
        $k = ConvertTo-SectorKey ([string]$g.Key)
        if ($names.ContainsKey($k)) { $dep[$k] = [double]$dep[$k] + [double]$g.Pct } else { $other += [double]$g.Pct }
    }
    $rows = @()
    foreach ($k in $names.Keys) {
        $d = if ($dep.ContainsKey($k)) { [double]$dep[$k] } else { 0.0 }
        $rf = if ($null -ne $Reference -and $Reference.ContainsKey($k)) { [double]$Reference[$k] } else { [double]::NaN }
        if ($d -eq 0 -and ([double]::IsNaN($rf) -or $rf -eq 0)) { continue }
        $rows += [PSCustomObject]@{ Sector = $names[$k]; Depot = $d; Ref = $rf; Diff = $(if ([double]::IsNaN($rf)) { [double]::NaN } else { $d - $rf }) }
    }
    $rows = @($rows | Sort-Object -Property @{ Expression = { [double]$_.Depot }; Descending = $true }, @{ Expression = { $(if ([double]::IsNaN([double]$_.Ref)) { 0.0 } else { [double]$_.Ref }) }; Descending = $true }, @{ Expression = { [string]$_.Sector }; Descending = $false })
    if ($other -gt 0) { $rows += [PSCustomObject]@{ Sector = "Andere / ETF / unbekannt"; Depot = $other; Ref = [double]::NaN; Diff = [double]::NaN } }
    return $rows
}

function Get-AlignedIndex {
    # v5.1: close series rebased to 100 on the target dates (last close on or
    # before each date); NaN before the first close
    param([string[]]$Target, [string[]]$Dates, [double[]]$Closes)
    $n = @($Target).Count
    $out = New-Object double[] $n
    $j = -1; $base = [double]::NaN
    for ($i = 0; $i -lt $n; $i++) {
        while (($j + 1) -lt @($Dates).Count -and [string]::CompareOrdinal([string]$Dates[$j + 1], [string]$Target[$i]) -le 0) { $j++ }
        if ($j -lt 0 -or [double]$Closes[$j] -le 0) { $out[$i] = [double]::NaN; continue }
        if ([double]::IsNaN($base)) { $base = [double]$Closes[$j] }
        $out[$i] = [double]$Closes[$j] / $base * 100.0
    }
    return ,$out
}

# ------------------------------------------------------------------------------
# v5.2: design - style (Refined / Fresh), row density, ticker bar speed,
# Windows accent colour
# ------------------------------------------------------------------------------
function Get-UiSpec {
    param([string]$Style = "Refined", [string]$Density = "Normal")
    $fresh = ($Style -eq "Fresh")
    $row = switch ($Density) { "Compact" { 21 } "Comfortable" { 30 } default { 25 } }
    if ($fresh) { $row += 2 }
    return [PSCustomObject]@{
        Style      = $(if ($fresh) { "Fresh" } else { "Refined" })
        Fresh      = $fresh
        BtnRadius  = $(if ($fresh) { 8 } else { 4 })
        CardRadius = $(if ($fresh) { 10 } else { 0 })
        Gap        = $(if ($fresh) { 12 } else { 8 })
        RowH       = $row
        HeaderH    = $(if ($fresh) { 30 } else { 26 })
        FillAlpha  = $(if ($fresh) { 95 } else { 64 })
        LineWidth  = $(if ($fresh) { 2.2 } else { 1.9 })
        CellPad    = $(if ($fresh) { 4 } else { 2 })
    }
}

function Get-UiStyles { return @("Refined", "Fresh") }

# ------------------------------------------------------------------------------
# V7.0: design tokens - scales, accent states, contrast
# ------------------------------------------------------------------------------
function Get-DesignScale {
    # One scale for the whole widget (before DPI scaling). Everything is a multiple of 4.
    return [PSCustomObject]@{
        Space  = [PSCustomObject]@{ XS = 4; S = 8; M = 12; L = 16; XL = 24 }
        Radius = [PSCustomObject]@{ S = 4; M = 8; L = 12 }
        Font   = [PSCustomObject]@{ Caption = 7.5; Body = 8.5; BodyStrong = 8.5; Title = 11.0; Display = 16.0 }
        Motion = [PSCustomObject]@{ Fast = 80; Normal = 120; Slow = 150 }   # milliseconds, at most 150
    }
}

function ConvertTo-GridPx {
    # Rounds a size to the 4 px grid; after DPI scaling the grid step is 4 * Scale
    param([double]$Value, [double]$Scale = 1.0)
    $step = 4.0 * $Scale
    if ($step -le 0) { return [int][math]::Round($Value) }
    $n = [math]::Round($Value / $step, [System.MidpointRounding]::AwayFromZero)
    return [int][math]::Round($n * $step)
}

function Get-RelativeLuminance {
    # WCAG relative luminance of an sRGB colour (R, G, B = 0..255)
    param([int[]]$Rgb)
    $lin = @()
    foreach ($v in @($Rgb[0], $Rgb[1], $Rgb[2])) {
        $s = $v / 255.0
        if ($s -le 0.03928) { $lin += ($s / 12.92) } else { $lin += [math]::Pow((($s + 0.055) / 1.055), 2.4) }
    }
    return (0.2126 * $lin[0] + 0.7152 * $lin[1] + 0.0722 * $lin[2])
}

function Get-ContrastRatio {
    # WCAG contrast ratio, 1 .. 21
    param([int[]]$A, [int[]]$B)
    $la = Get-RelativeLuminance -Rgb $A
    $lb = Get-RelativeLuminance -Rgb $B
    $hi = [math]::Max($la, $lb)
    $lo = [math]::Min($la, $lb)
    return (($hi + 0.05) / ($lo + 0.05))
}

function Get-MixRgb {
    # T = share of A (0..1)
    param([int[]]$A, [int[]]$B, [double]$T)
    return @(
        [int]($B[0] + ($A[0] - $B[0]) * $T),
        [int]($B[1] + ($A[1] - $B[1]) * $T),
        [int]($B[2] + ($A[2] - $B[2]) * $T)
    )
}

function Get-AccentStates {
    # Hover / pressed / subtle-background colours and the text colour on top of
    # the accent, all derived from the base accent, so any Windows accent works.
    param([int[]]$Rgb, [int[]]$Surface = @(24, 24, 27), [bool]$DarkSurface = $true)
    $white = @(255, 255, 255)
    $black = @(0, 0, 0)
    if ($DarkSurface) {
        $hover   = Get-MixRgb -A $white -B $Rgb -T 0.15
        $pressed = Get-MixRgb -A $black -B $Rgb -T 0.20
    }
    else {
        $hover   = Get-MixRgb -A $black -B $Rgb -T 0.12
        $pressed = Get-MixRgb -A $black -B $Rgb -T 0.25
    }
    $subtle = Get-MixRgb -A $Rgb -B $Surface -T 0.18
    $onAccent = $black
    if ((Get-ContrastRatio -A $Rgb -B $white) -ge (Get-ContrastRatio -A $Rgb -B $black)) { $onAccent = $white }
    return [PSCustomObject]@{ Hover = $hover; Pressed = $pressed; Subtle = $subtle; OnAccent = $onAccent }
}

function Get-PollNote {
    # v7.3: why data is refreshed less often than selected ("" = normal polling)
    param([bool]$AllClosed, [int]$ClosedMinutes, [int]$RefreshSec, $BackoffUntil = $null, [DateTime]$Now = (Get-Date))
    if ($null -ne $BackoffUntil -and [DateTime]$BackoffUntil -gt $Now) { return ("Yahoo-Pause bis {0:HH:mm}" -f [DateTime]$BackoffUntil) }
    if ($AllClosed -and $ClosedMinutes -gt 0 -and ($ClosedMinutes * 60) -gt $RefreshSec) { return "Märkte zu - Abfrage alle $ClosedMinutes min" }
    return ""
}

function Get-ShortMarketText {
    # v7.3: shorter market status for narrow windows
    param([string]$Text)
    return (([string]$Text) -replace ' - (öffnet in|zu in|Handel in|Ende in) ', ' · ' -replace ' - öffnet ', ' · ')
}

function Get-WatchPanelWidths {
    # v7.5: watchlist view widths in design pixels. Alarm column 252..420; a 260 px detail
    # panel only when the list keeps at least 560 px next to it.
    param([int]$ViewW, [bool]$WantDetail = $true)
    $alarm = [int][math]::Floor($ViewW * 0.28)
    $alarm = [math]::Max(252, [math]::Min(420, $alarm))
    $alarm = [math]::Max(252, [math]::Min($alarm, $ViewW - 504))   # list: at least 480
    $can = (($ViewW - $alarm - 260 - 32) -ge 640)
    $detail = if ($can -and $WantDetail) { 260 } else { 0 }
    $grid = $ViewW - $alarm - 24 - $(if ($detail -gt 0) { $detail + 8 } else { 0 })
    return [PSCustomObject]@{ Grid = [int]$grid; Detail = [int]$detail; Alarm = [int]$alarm; CanDetail = [bool]$can }
}

function Get-TickerDetailLines {
    # v7.5: text lines for the watchlist detail panel (prices in the quote currency)
    param([string]$Symbol, $Quote = $null, $Position = $null, [string]$Note = "", [bool]$Privacy = $false)
    $dots = [string][char]0x2022 * 3
    $out = @($Symbol)
    if ($null -eq $Quote) { $out += "Noch keine Kursdaten." }
    else {
        $cur = [string]$Quote.Currency
        if ($Quote.LongName -and [string]$Quote.LongName -ne $Symbol) { $out += [string]$Quote.LongName }
        $out += ""
        $out += ("Kurs      {0:N2} {1}" -f [double]$Quote.Price, $cur)
        $out += ("Tag       {0:+0.00;-0.00;0.00} %" -f [double]$Quote.ChangePct)
        if ([double]$Quote.PrevClose -gt 0) { $out += ("Vortag    {0:N2}" -f [double]$Quote.PrevClose) }
        if ([double]$Quote.ExtPrice -gt 0) { $out += ("Ext       {0:N2} ({1:+0.00;-0.00;0.00} %)" -f [double]$Quote.ExtPrice, [double]$Quote.ExtPct) }
        if ([double]$Quote.High52 -gt 0 -and [double]$Quote.Low52 -gt 0) {
            $out += ("52W Hoch  {0:N2} ({1:+0.0;-0.0;0.0} %)" -f [double]$Quote.High52, (([double]$Quote.Price - [double]$Quote.High52) / [double]$Quote.High52 * 100.0))
            $out += ("52W Tief  {0:N2}" -f [double]$Quote.Low52)
        }
        if ($null -ne $Quote.Rsi14 -and -not [double]::IsNaN([double]$Quote.Rsi14)) { $out += ("RSI 1h    {0:N1}" -f [double]$Quote.Rsi14) }
    }
    if ($null -ne $Position -and [double]$Position.Shares -gt 0) {
        $out += ""
        $out += "Position"
        $out += ("Stück     {0}" -f $(if ($Privacy) { $dots } else { "{0:N2}" -f [double]$Position.Shares }))
        $out += ("EK        {0:N2} {1}" -f [double]$Position.AvgPrice, [string]$Position.Currency)
    }
    if ($Note.Trim()) { $out += ""; $out += "Notiz"; $out += $Note.Trim() }
    return $out
}

function Get-StatusBarParts {
    # V7.0: the pieces of the status bar at the bottom of the window
    param([double]$AgeSec = [double]::NaN, [string]$Stand = "", [string]$Market = "", [bool]$Privacy = $false, [int]$ReqPerMin = -1, [string]$PollNote = "")
    $parts = @()
    if ($Stand) {
        $a = ""
        if (-not [double]::IsNaN($AgeSec)) {
            if ($AgeSec -lt 90) { $a = " (vor {0:N0} s)" -f $AgeSec } else { $a = " (vor {0:N0} min)" -f [math]::Floor($AgeSec / 60) }
        }
        $parts += ("Stand " + $Stand + $a)
    }
    else { $parts += "Noch keine Daten" }
    if ($Market) { $parts += $Market }
    if ($PollNote) { $parts += $PollNote }
    if ($ReqPerMin -ge 0) { $parts += ("{0} Abfragen/min" -f $ReqPerMin) }
    if ($Privacy) { $parts += "Privat-Modus" }
    return $parts
}

function Get-ChipLayout {
    # V7.0: how many chips fit into one row; the rest goes behind a "more" chip.
    # Returns Shown (number of chips), Overflow ($true = a "more" chip is needed) and X (left edge of each shown chip).
    param([int[]]$Widths, [int]$Available, [int]$Gap = 6, [int]$AddWidth = 26, [int]$MoreWidth = 34)
    $n = @($Widths).Count
    $total = 0
    foreach ($w in @($Widths)) { $total += ([int]$w + $Gap) }
    $x = @()
    if ($n -eq 0) { return [PSCustomObject]@{ Shown = 0; Overflow = $false; X = @() } }
    if (($total + $AddWidth) -le $Available) {
        $pos = 0
        foreach ($w in @($Widths)) { $x += $pos; $pos += ([int]$w + $Gap) }
        return [PSCustomObject]@{ Shown = $n; Overflow = $false; X = $x }
    }
    $cap = $Available - ($MoreWidth + $Gap + $AddWidth + $Gap)
    $pos = 0
    $shown = 0
    foreach ($w in @($Widths)) {
        if ($shown -gt 0 -and ($pos + [int]$w) -gt $cap) { break }
        $x += $pos
        $pos += ([int]$w + $Gap)
        $shown++
    }
    return [PSCustomObject]@{ Shown = $shown; Overflow = ($shown -lt $n); X = $x }
}

function Get-EarliestDate {
    # v7.7: the earliest "yyyy-MM-dd" of a list, "" for an empty one. The @() matters:
    # with exactly one entry, ($list | Sort-Object)[0] is the first CHARACTER.
    param([string[]]$Dates = @())
    $s = @(@($Dates) | Where-Object { $_ } | Sort-Object)
    if ($s.Count -eq 0) { return "" }
    return [string]$s[0]
}

function Get-XirrNote {
    # v7.3: why the return p.a. shows "-" ("" when there is a value). Needs 30 days since the first booking.
    param([double]$Xirr, [string]$FirstDate = "", [string]$Today = "", [int]$MinDays = 30)
    if (-not [double]::IsNaN($Xirr)) { return "" }
    if (-not $FirstDate) { return "keine gebuchte Position" }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $end = if ($Today) { [DateTime]::ParseExact($Today, "yyyy-MM-dd", $inv) } else { (Get-Date).Date }
    $left = $MinDays - [int]($end - [DateTime]::ParseExact($FirstDate.Substring(0, 10), "yyyy-MM-dd", $inv)).TotalDays
    if ($left -eq 1) { return "ab $MinDays Tagen (noch 1 Tag)" }
    if ($left -gt 1) { return "ab $MinDays Tagen (noch $left Tage)" }
    return "nicht berechenbar"
}

function Get-AnalysisKpiTiles {
    # V7.0: the key figures at the top of the Analyse "Wertentwicklung" page.
    # Kind = up / down / flat decides the colour (green / red only for gains / losses).
    param([double]$Value, [double]$Invested, [double]$Dividends, [double]$Xirr, [string]$Base = "EUR", [double]$WindowResult = [double]::NaN, [string]$RangeLabel = "", [string]$XirrNote = "")
    $res = $Value + $Dividends - $Invested
    $kindOf = { param([double]$x) if ([double]::IsNaN($x) -or [math]::Abs($x) -lt 0.005) { return "flat" } elseif ($x -gt 0) { return "up" } else { return "down" } }
    $pct = [double]::NaN
    if ($Invested -gt 0) { $pct = $res / $Invested * 100.0 }
    $tiles = @()
    $tiles += [PSCustomObject]@{ Id = "Value"; Label = "Depotwert"; Text = ("{0:N0} {1}" -f $Value, $Base); Sub = ("Investiert {0:N0}" -f $Invested); Kind = "flat" }
    $tiles += [PSCustomObject]@{ Id = "Result"; Label = "Ergebnis"; Text = ("{0:+#,##0;-#,##0;0} {1}" -f $res, $Base); Sub = $(if ([double]::IsNaN($pct)) { "" } else { "{0:+0.0;-0.0;0.0} % auf Einsatz" -f $pct }); Kind = (& $kindOf $res) }
    $tiles += [PSCustomObject]@{ Id = "Xirr"; Label = "Rendite p.a."; Text = $(if ([double]::IsNaN($Xirr)) { "-" } else { "{0:+0.0;-0.0;0.0} %" -f ($Xirr * 100.0) }); Sub = $(if ($XirrNote) { $XirrNote } else { "XIRR" }); Kind = (& $kindOf $Xirr) }
    $tiles += [PSCustomObject]@{ Id = "Div"; Label = "Dividenden"; Text = ("{0:N0} {1}" -f $Dividends, $Base); Sub = "bisher erhalten"; Kind = "flat" }
    if (-not [double]::IsNaN($WindowResult)) {
        $tiles += [PSCustomObject]@{ Id = "Window"; Label = $(if ($RangeLabel) { "Im Zeitraum ($RangeLabel)" } else { "Im Zeitraum" }); Text = ("{0:+#,##0;-#,##0;0} {1}" -f $WindowResult, $Base); Sub = ""; Kind = (& $kindOf $WindowResult) }
    }
    return $tiles
}

function Get-DonutSlices {
    # V7.1: slices of the allocation donut. Small shares are merged into "Rest".
    # Start / Sweep in degrees, clockwise from 12 o'clock (GDI+ angle = Start - 90).
    param($Items, [double]$MinPct = 3.0, [int]$MaxSlices = 8)
    $list = @($Items | Where-Object { $null -ne $_ -and [double]$_.Value -gt 0 } | Sort-Object { [double]$_.Value } -Descending)
    $total = 0.0
    foreach ($i in $list) { $total += [double]$i.Value }
    if ($list.Count -eq 0 -or $total -le 0) { return @() }
    $keep = @(); $rest = 0.0
    foreach ($i in $list) {
        $pct = [double]$i.Value / $total * 100.0
        $full = ($list.Count -gt $MaxSlices -and $keep.Count -ge ($MaxSlices - 1))
        if ($pct -lt $MinPct -or $full) { $rest += [double]$i.Value } else { $keep += [PSCustomObject]@{ Name = [string]$i.Name; Value = [double]$i.Value } }
    }
    if ($rest -gt 0) { $keep += [PSCustomObject]@{ Name = "Rest"; Value = $rest } }
    $out = @(); $angle = 0.0
    foreach ($k in $keep) {
        $sw = $k.Value / $total * 360.0
        $out += [PSCustomObject]@{ Name = $k.Name; Value = $k.Value; Pct = ($k.Value / $total * 100.0); Start = $angle; Sweep = $sw }
        $angle += $sw
    }
    return $out
}

function Get-DotPlotLayout {
    # V7.1: position of one value among peer values on a 0..1 axis (dot plot). Rank 1 = lowest.
    param([double]$Value, [double[]]$Peers)
    $ps = @($Peers | Where-Object { -not [double]::IsNaN($_) })
    $all = $ps + @($Value)
    $min = ($all | Measure-Object -Minimum).Minimum
    $max = ($all | Measure-Object -Maximum).Maximum
    $span = $max - $min
    $pos = { param([double]$x) if ($span -le 0) { return 0.5 } else { return ($x - $min) / $span } }
    $sorted = @($all | Sort-Object)
    $n = $sorted.Count
    if ($n % 2 -eq 1) { $median = $sorted[[int](($n - 1) / 2)] } else { $median = ($sorted[$n / 2 - 1] + $sorted[$n / 2]) / 2.0 }
    $rank = 1
    foreach ($p in $ps) { if ($p -lt $Value) { $rank++ } }
    return [PSCustomObject]@{ Min = $min; Max = $max; Pos = (& $pos $Value); PeerPos = @($ps | ForEach-Object { & $pos $_ }); Median = $median; MedianPos = (& $pos $median); Rank = $rank; Count = $n }
}

function Get-ValuationBand {
    # V7.1: fair-value band from the history of one multiple (e.g. P/E) and the current earnings per share.
    # Low / Mid / High = 20th / 50th / 80th percentile of the multiple * EPS. State compares the price with the band.
    param([double[]]$Multiples, [double]$Eps, [double]$Price)
    $m = @($Multiples | Where-Object { -not [double]::IsNaN($_) -and $_ -gt 0 } | Sort-Object)
    if ($m.Count -lt 5 -or $Eps -le 0) { return $null }
    $pct = { param([double]$q) $idx = ($m.Count - 1) * $q; $lo = [math]::Floor($idx); $hi = [math]::Ceiling($idx); return $m[[int]$lo] + ($m[[int]$hi] - $m[[int]$lo]) * ($idx - $lo) }
    $low = (& $pct 0.2) * $Eps; $mid = (& $pct 0.5) * $Eps; $high = (& $pct 0.8) * $Eps
    $state = "fair"
    if ($Price -lt $low) { $state = "cheap" } elseif ($Price -gt $high) { $state = "expensive" }
    return [PSCustomObject]@{ Low = $low; Mid = $mid; High = $high; State = $state }
}

function Get-PaneLayout {
    # V7.1: heights of the chart (main) and the indicator panes below it. Divider = share of the main chart
    # (clamped); the panes share the rest equally, each at least MinPane px.
    param([int]$Total, [int]$PaneCount, [double]$Divider = 0.7, [int]$MinPane = 48)
    if ($PaneCount -le 0) { return [PSCustomObject]@{ Main = $Total; Pane = 0; Count = 0; DividerY = $Total } }
    $d = [math]::Min(0.85, [math]::Max(0.35, $Divider))
    $main = [int][math]::Round($Total * $d)
    $pane = [int][math]::Floor(($Total - $main) / $PaneCount)
    if ($pane -lt $MinPane) { $pane = $MinPane; $main = [math]::Max(0, $Total - $pane * $PaneCount) }
    return [PSCustomObject]@{ Main = $main; Pane = $pane; Count = $PaneCount; DividerY = $main }
}

function Get-SegmentLayout {
    # V7.1: widths of the segments of a segmented control, proportional to the text, summing to Width.
    param([string[]]$Labels, [int]$Width, [int]$Pad = 16, [int]$CharPx = 7)
    $n = @($Labels).Count
    if ($n -eq 0) { return @() }
    $raw = @($Labels | ForEach-Object { $_.Length * $CharPx + 2 * $Pad })
    $sum = ($raw | Measure-Object -Sum).Sum
    $out = @(); $used = 0
    for ($i = 0; $i -lt $n; $i++) {
        if ($i -eq $n - 1) { $w = $Width - $used } else { $w = [int][math]::Floor($raw[$i] / $sum * $Width) }
        $out += [PSCustomObject]@{ X = $used; W = $w }
        $used += $w
    }
    return $out
}

function Get-RollValues {
    # V7.1: intermediate values of a number roll-over (ease-out); the last value is exactly To
    param([double]$From, [double]$To, [int]$Steps = 6)
    if ($Steps -lt 1) { return @($To) }
    $out = @()
    for ($i = 1; $i -le $Steps; $i++) {
        $t = $i / [double]$Steps
        $e = 1.0 - [math]::Pow(1.0 - $t, 3)
        $out += ($From + ($To - $From) * $e)
    }
    $out[$out.Count - 1] = $To
    return $out
}

function Get-TokenMap {
    # Token name -> key of the palette ($script:Pal). Drawing code asks for tokens only.
    return [ordered]@{
        "surface.window"  = "BodyBg"
        "surface.header"  = "HeaderBg"
        "surface.panel"   = "PanelBg"
        "surface.card"    = "Card"
        "surface.raised"  = "Input"
        "surface.hover"   = "Hover"
        "border.subtle"   = "Grid"
        "border.strong"   = "Border"
        "text.primary"    = "Text"
        "text.muted"      = "Muted"
        "text.disabled"   = "Disabled"
        "accent"          = "Accent"
        "accent.hover"    = "AccentHover"
        "accent.pressed"  = "AccentPressed"
        "accent.subtle"   = "AccentSubtle"
        "accent.text"     = "OnAccent"
        "warning"         = "Warn"
        "busy"            = "Busy"
        "mark"            = "Mark"
        "series.violet"   = "Violet"
        "series.pink"     = "Pink"
        "series.cyan"     = "Cyan"
        "series.lime"     = "Lime"
        "series.blue"     = "Blue"
        "series.neutral"  = "Neutral"
    }
}

function Get-RowDensities { return @("Compact", "Normal", "Comfortable") }
function Get-TapeSpeeds { return @("Slow", "Normal", "Fast") }

function Get-TapeStep {
    # pixels per 30 ms tick (before DPI scaling)
    param([string]$Speed)
    switch ($Speed) { "Slow" { return 0.5 } "Fast" { return 2.0 } default { return 1.0 } }
}

function ConvertFrom-AbgrDword {
    # HKCU\Software\Microsoft\Windows\DWM\AccentColor is 0xAABBGGRR; the
    # registry hands it to PowerShell as a (possibly negative) Int32
    param([long]$Value)
    $v = $Value -band 0xFFFFFFFFL
    return @([int]($v -band 0xFF), [int](($v -shr 8) -band 0xFF), [int](($v -shr 16) -band 0xFF))
}

function ConvertTo-StoredFund {
    # v5.1: fundamentals as plain numbers (NaN -> null, so the JSON stays valid)
    param($F)
    if ($null -eq $F) { return $null }
    $o = [ordered]@{}
    # (loop variable must not be $f: PowerShell names are case-insensitive)
    foreach ($fd in (Get-FundamentalFields)) {
        $pp = $F.PSObject.Properties[$fd[0]]
        $x = [double]::NaN
        if ($null -ne $pp -and $null -ne $pp.Value -and [string]$pp.Value -ne "") { try { $x = [double]$pp.Value } catch { } }
        $o[$fd[0]] = if ([double]::IsNaN($x) -or [double]::IsInfinity($x)) { $null } else { $x }
    }
    $o["Currency"] = [string]$F.Currency
    return [PSCustomObject]$o
}

# ------------------------------------------------------------------------------
# v5.3: settings window with pages, settings search, export / import
# ------------------------------------------------------------------------------
function Get-SettingsPages {
    # The eight pages of the settings window, in display order
    return @(
        [PSCustomObject]@{ Id = "Display"; De = "Darstellung";                 En = "Display" }
        [PSCustomObject]@{ Id = "Design";  De = "Design";                      En = "Design" }
        [PSCustomObject]@{ Id = "Layout";  De = "Layout";                      En = "Layout" }
        [PSCustomObject]@{ Id = "Data";    De = "Daten & Aktualisierung";      En = "Data & refresh" }
        [PSCustomObject]@{ Id = "Alerts";  De = "Alarme & Benachrichtigungen"; En = "Alerts & notifications" }
        [PSCustomObject]@{ Id = "Depot";   De = "Depot";                       En = "Depot" }
        [PSCustomObject]@{ Id = "Keyboard"; De = "Tastatur & Befehle";          En = "Keyboard & commands" }
        [PSCustomObject]@{ Id = "Misc";    De = "Sonstiges";                   En = "Other" }
    )
}

function Get-SettingsPageTitle {
    param([string]$Id, [string]$Language = "DE")
    foreach ($pg in (Get-SettingsPages)) {
        if ($pg.Id -eq $Id) { if ($Language -eq "EN") { return $pg.En } else { return $pg.De } }
    }
    return $Id
}

function Find-SettingsHits {
    # Entries: @(@{ Page; Search; Strong }) - Search = label, tooltip, items,
    # extra words; Strong (optional) = the same without the tooltip.
    # Returns @{ Entries = indices of matching entries; Counts = page -> hits;
    # StrongCounts = page -> hits in label / keywords; TitlePages = pages whose
    # title matches (German or English) }
    param($Entries, [string]$Query)
    $res = [PSCustomObject]@{ Entries = @(); Counts = [ordered]@{}; StrongCounts = [ordered]@{}; TitlePages = @() }
    foreach ($pg in (Get-SettingsPages)) { $res.Counts[$pg.Id] = 0; $res.StrongCounts[$pg.Id] = 0 }
    if (-not ([string]$Query).Trim()) { return $res }
    $idx = New-Object System.Collections.Generic.List[int]
    # (foreach, not @(): @() on a List[object] throws "Argument types do not match")
    $all = @(foreach ($x in $Entries) { $x })
    for ($i = 0; $i -lt $all.Count; $i++) {
        $e = $all[$i]
        if ($null -eq $e) { continue }
        if (Test-SettingMatch -Text ([string]$e.Search) -Query $Query) {
            $idx.Add($i)
            if ($res.Counts.Contains([string]$e.Page)) {
                $res.Counts[[string]$e.Page]++
                $st = if ($null -ne $e.PSObject.Properties["Strong"] -and $null -ne $e.Strong) { [string]$e.Strong } else { [string]$e.Search }
                if (Test-SettingMatch -Text $st -Query $Query) { $res.StrongCounts[[string]$e.Page]++ }
            }
        }
    }
    $res.Entries = $idx.ToArray()
    # page titles by word start, so "fresh" does not land on "Data & refresh"
    $qw = @((ConvertTo-SearchKey $Query).Trim() -split '\s+' | Where-Object { $_ })
    $titleHit = {
        param([string]$T)
        $tw = @((ConvertTo-SearchKey $T) -split '[^a-z0-9]+' | Where-Object { $_ })
        foreach ($w in $qw) { if (-not @($tw | Where-Object { $_.StartsWith($w) }).Count) { return $false } }
        return $true
    }
    $res.TitlePages = @(Get-SettingsPages | Where-Object { (& $titleHit $_.De) -or (& $titleHit $_.En) } | ForEach-Object { $_.Id })
    return $res
}

function Select-SettingsPage {
    # Which page to show for a search: a matching page title wins; then hits in
    # a label or keyword (current page first), then hits only in a tooltip
    param([string]$Current, $Hits)
    if ($null -eq $Hits) { return $Current }
    if (@($Hits.TitlePages).Count -gt 0) { return [string]@($Hits.TitlePages)[0] }
    $tables = @()
    if ($null -ne $Hits.PSObject.Properties["StrongCounts"] -and $null -ne $Hits.StrongCounts) { $tables += , $Hits.StrongCounts }
    $tables += , $Hits.Counts
    foreach ($t in $tables) {
        if ($t.Contains($Current) -and [int]$t[$Current] -gt 0) { return $Current }
        foreach ($k in @($t.get_Keys())) { if ([int]$t[$k] -gt 0) { return [string]$k } }
    }
    return $Current
}

function Test-SettingChanged {
    # "changed from default" marker: compares what a control shows with its
    # default (numbers by value, text case-sensitive, $null = no default)
    param($Value, $Default)
    if ($null -eq $Default) { return $false }
    if ($Value -is [bool] -or $Default -is [bool]) { return ([bool]$Value -ne [bool]$Default) }
    $dv = 0.0; $vv = 0.0
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $sty = [System.Globalization.NumberStyles]::Float
    if (($Default -is [int] -or $Default -is [long] -or $Default -is [double] -or $Default -is [decimal]) -and
        [double]::TryParse([string]::Format($inv, "{0}", $Value), $sty, $inv, [ref]$vv)) {
        $dv = [double]$Default
        return ([math]::Abs($vv - $dv) -gt 1e-9)
    }
    return (([string]$Value).Trim() -cne ([string]$Default).Trim())
}

function Get-PortableSettingKeys {
    # Settings that make sense on another PC. Not included: window positions,
    # histories, depots, the encrypted push token (bound to this Windows user)
    return @(
        "RefreshSeconds", "SlowRefreshSeconds", "HttpTimeoutSeconds", "ClosedPollMinutes",
        "SmaFastPeriod", "SmaSlowPeriod", "RsiPeriod", "RsiOverbought", "RsiOversold", "MaType", "LowerPanel",
        "Theme", "AccentColor", "AccentHex", "Language", "TopMost", "CompactTape",
        "UiStyle", "RowDensity", "TapeSpeed", "ZebraRows", "UseIcons", "ShowStatusBar", "PortSimOpen", "WatchDetail", "ShowToasts", "PerMonitorDpi", "DayChangePill", "Animations", "FollowHighContrast",
        "ShowTrayNotifications", "NotifyMarketOpen", "NotifyEarnings", "QuietFrom", "QuietTo",
        "Layout", "Opacity", "TerminalShowWatch", "TerminalShowPortfolio", "TerminalChartPct", "CompactShow",
        "UpDownScheme", "UpColor", "DownColor", "ShowArrows", "PriceFlash", "TrayFollowsDepot", "SnapToEdges",
        "GlobalHotkey", "MonoFont", "FontScale", "AlignNumbersRight", "RoundCorners",
        "NewsRefreshMinutes", "NewsMoveThreshold", "NewsKeywords", "NewsKeywordWatch", "NewsMuted",
        "TooltipMode", "TooltipDelayMs", "HoverCards",
        "Currency", "AutoCurrency", "RiskFreePct",
        "ChartType", "ShowVolume", "ShowRsi", "PaneDivider", "ShowSma", "ShowVwap", "ShowBollinger", "ShowExtended", "ShowPrevClose", "LogScale",
        "UserLayouts", "GridLayouts",
        "PctAxis", "ShowSR", "SignalAlerts", "PeerGroups", "NewsFeeds",
        "NewsSources", "NewsSourcesMigrated", "NewsYahoo", "NewsYahooNotify", "NewsViewHidden", "NewsAliases",
        "NewsInclude", "NewsExclude", "NewsHighlight", "NewsMergeSimilar", "NewsPreview", "NewsImages", "NewsHistoryDays", "ShowNewsMarkers",
        "ColorRules", "CustomThemes", "OwnTargets", "ColumnSets", "ColumnSetMap", "KeyMap", "Favorites", "KpiTiles", "UserProfiles",
        "AlertTemplates", "EarningsLeadDays", "ExDivLeadDays", "SummaryAuto", "GoalDepotValue", "GoalDividendYear", "DepotGoals", "GoalAllValue", "GoalAllDividend"
    )
}

function ConvertTo-SettingsExport {
    # Config -> export object (only the portable keys that exist)
    param($Config, [string]$Version, [DateTime]$Now = (Get-Date))
    $s = [ordered]@{}
    foreach ($k in (Get-PortableSettingKeys)) {
        $pp = $Config.PSObject.Properties[$k]
        if ($null -ne $pp) { $s[$k] = $pp.Value }
    }
    return [PSCustomObject]@{
        Format   = "TerminalWidget.Settings"
        Version  = [string]$Version
        Exported = $Now.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
        Settings = [PSCustomObject]$s
    }
}

function ConvertFrom-SettingsExport {
    # Export object (from JSON) -> @{ Ok; Error; Settings (hashtable); Skipped }
    # Only portable keys the defaults know are taken; each value is converted to
    # the type of its default. Unknown or broken values are skipped, not guessed.
    param($Data, $Defaults)
    $r = [PSCustomObject]@{ Ok = $false; Error = ""; Settings = @{}; Skipped = @() }
    if ($null -eq $Data -or [string]$Data.Format -ne "TerminalWidget.Settings" -or $null -eq $Data.Settings) {
        $r.Error = "Keine Einstellungs-Datei des Terminal Widgets."
        return $r
    }
    $skipped = New-Object System.Collections.Generic.List[string]
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $portable = @(Get-PortableSettingKeys)
    foreach ($pp in $Data.Settings.PSObject.Properties) {
        $k = $pp.Name
        $dp = if ($null -ne $Defaults) { $Defaults.PSObject.Properties[$k] } else { $null }
        if ($k -notin $portable -or $null -eq $dp) { $skipped.Add($k); continue }
        $d = $dp.Value; $v = $pp.Value
        try {
            if ($d -is [bool]) {
                if ($v -is [bool]) { $r.Settings[$k] = $v }
                elseif ([string]$v -in @("true", "false", "True", "False")) { $r.Settings[$k] = ([string]$v -eq "true" -or [string]$v -eq "True") }
                else { $skipped.Add($k) }
            } elseif ($d -is [int] -or $d -is [long]) {
                $x = 0.0
                if ($null -ne $v -and $v -isnot [bool] -and [double]::TryParse([string]::Format($inv, "{0}", $v), [System.Globalization.NumberStyles]::Float, $inv, [ref]$x)) { $r.Settings[$k] = [int][math]::Round($x) } else { $skipped.Add($k) }
            } elseif ($d -is [double] -or $d -is [decimal]) {
                $x = 0.0
                if ($null -ne $v -and $v -isnot [bool] -and [double]::TryParse([string]::Format($inv, "{0}", $v), [System.Globalization.NumberStyles]::Float, $inv, [ref]$x)) { $r.Settings[$k] = [double]$x } else { $skipped.Add($k) }
            } elseif ($d -is [string]) {
                if ($null -eq $v -or $v -is [string] -or $v -is [ValueType]) { $r.Settings[$k] = [string]$v } else { $skipped.Add($k) }
            } elseif ($d -is [array]) {
                if ($null -eq $v) { $r.Settings[$k] = @() }
                elseif ($v -is [array]) { $r.Settings[$k] = @($v) }
                else { $skipped.Add($k) }
            } else {
                # objects (saved layouts, column widths): taken as they are
                if ($null -ne $v -and $v -isnot [string] -and $v -isnot [ValueType]) { $r.Settings[$k] = $v } else { $skipped.Add($k) }
            }
        } catch { $skipped.Add($k) }
    }
    $r.Skipped = $skipped.ToArray()
    $r.Ok = ($r.Settings.Count -gt 0)
    if (-not $r.Ok) { $r.Error = "Die Datei enthält keine bekannten Einstellungen." }
    return $r
}

# ------------------------------------------------------------------------------
# v5.5: per-ticker notes, health check, diagnostics
# ------------------------------------------------------------------------------
function ConvertTo-NoteText {
    # what is stored: trimmed, Windows line breaks, at most 4000 characters
    param([string]$Text)
    $t = ([string]$Text) -replace "`r`n", "`n" -replace "`r", "`n"
    $t = $t.Trim()
    if ($t.Length -gt 4000) { $t = $t.Substring(0, 4000) }
    return ($t -replace "`n", "`r`n")
}

function Get-NoteSnippet {
    # one line for the hover card / tooltips
    param([string]$Text, [int]$Max = 120)
    $t = (([string]$Text) -replace '\s+', ' ').Trim()
    if ($t.Length -le $Max) { return $t }
    return ($t.Substring(0, [math]::Max(1, $Max - 1)).TrimEnd() + [string][char]0x2026)
}

function Get-BackupHealth {
    # newest backup age -> OK (< 2 days) / WARN (< 8 days) / ERR
    param($Newest, [DateTime]$Now = (Get-Date))
    if ($null -eq $Newest) { return [PSCustomObject]@{ State = "ERR"; Days = [double]::NaN } }
    $d = ($Now - [DateTime]$Newest).TotalDays
    $st = if ($d -lt 2) { "OK" } elseif ($d -lt 8) { "WARN" } else { "ERR" }
    return [PSCustomObject]@{ State = $st; Days = $d }
}

function Format-HealthReport {
    # Checks: @(@{ Name; State = OK / WARN / ERR / INFO; Detail })
    param($Checks, [string]$Title = "Zustand")
    $sym = @{ "OK" = "OK  "; "WARN" = "!!  "; "ERR" = "XX  "; "INFO" = "    " }
    $lines = New-Object System.Collections.Generic.List[string]
    $nW = 0; $nE = 0
    foreach ($c in @($Checks)) {
        if ($null -eq $c) { continue }
        $st = [string]$c.State
        if ($st -eq "WARN") { $nW++ } elseif ($st -eq "ERR") { $nE++ }
        $pre = if ($sym.ContainsKey($st)) { $sym[$st] } else { "    " }
        $lines.Add(("{0}{1,-24} {2}" -f $pre, [string]$c.Name, [string]$c.Detail).TrimEnd())
    }
    $head = if ($nE -gt 0) { "{0}: {1} Fehler, {2} Warnung(en)" -f $Title, $nE, $nW } elseif ($nW -gt 0) { "{0}: {1} Warnung(en)" -f $Title, $nW } else { "{0}: alles in Ordnung" -f $Title }
    return (@($head, "") + $lines.ToArray()) -join "`r`n"
}

function Get-DiagnosticConfig {
    # config for a bug report: secrets and personal lists removed
    param($Config)
    $c = $Config | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    foreach ($k in @("PushTokenEnc", "PushTopic", "PushChatId", "PushServer", "TwelveDataKeyEnc", "FinnhubKeyEnc")) {
        if ($null -ne $c.PSObject.Properties[$k]) { $c.$k = $(if ([string]$c.$k) { "(entfernt)" } else { "" }) }
    }
    foreach ($k in @("Watchlist", "RecentTickers", "CommandHistory", "Depots", "TargetWeights", "WatchGroups", "OwnTargets", "UserProfiles", "GoalDepotValue", "GoalDividendYear", "DepotGoals", "GoalAllValue", "GoalAllDividend", "AlertTemplates")) {
        if ($null -ne $c.PSObject.Properties[$k]) { $c.$k = "(entfernt)" }
    }
    # v7.7: feed addresses may carry personal tokens or tickers
    if ($null -ne $c.PSObject.Properties["NewsSources"]) {
        $c.NewsSources = @(@($c.NewsSources) | Where-Object { $null -ne $_ } | ForEach-Object { [PSCustomObject]@{ Host = (Get-ProviderOfUrl ([string]$_.Url -replace '\{[a-z]+\}', 'x')); On = $_.On } })
    }
    foreach ($k in @("NewsFeeds", "NewsAliases")) {
        if ($null -ne $c.PSObject.Properties[$k] -and [string]$c.$k) { $c.$k = "(entfernt)" }
    }
    return $c
}

# ---- v5.5: privacy mask, CSV / HTML export, dialog placement ----
function Test-AmountColumn {
    # Columns whose values reveal money or position size (masked in privacy mode)
    param([string]$Header)
    $h = ConvertTo-SearchKey $Header
    if (-not $h -or $h.Contains("%") -or $h -match 'anteil|weight|rendite|return|kgv|ratio|kurs$|price') { return $false }
    foreach ($w in @("betrag", "wert", "gewinn", "verlust", "dividende", "einstand", "kosten", "summe", "saldo", "g/v", "brutto", "netto", "ertrag", "stuck", "beitrag", "kauf / verkauf", "einzahlung", "auszahlung",
                     "amount", "value", "profit", "loss", "dividend", "cost", "total", "gross", "net", "income", "shares", "contribution", "balance", "deposit", "withdrawal")) {
        if ($h.Contains($w)) { return $true }
    }
    return $false
}

function Hide-AmountsInText {
    # "Summe: 1.234,56 EUR (+3,2 %)" -> "Summe: ••• EUR (+3,2 %)"; percentages stay
    param([string]$Text)
    if (-not $Text) { return $Text }
    $dots = [string][char]0x2022 * 3
    $cur = '(EUR|USD|CHF|GBP|JPY|CAD|AUD|SEK|NOK|DKK|PLN|HKD|€|\$|£)'
    $num = '[-+−]?\d[\d.,'' ]*\d|[-+−]?\d'
    $t = [regex]::Replace($Text, "(?<![\w.,])($num)(\s?)$cur(?!\w)", { param($m) $dots + $m.Groups[2].Value + $m.Groups[3].Value })
    $t = [regex]::Replace($t, "$cur(\s?)($num)(?![\d%])", { param($m) $m.Groups[1].Value + $m.Groups[2].Value + $dots })
    return $t
}

function ConvertTo-CsvText {
    # Excel-friendly CSV (semicolon for German Excel); quotes where needed
    param([string[]]$Headers, $Rows, [string]$Separator = ";")
    $q = {
        param($v)
        $s = [string]$v
        if ($s.Contains($Separator) -or $s.Contains('"') -or $s.Contains("`n") -or $s.Contains("`r")) { return '"' + $s.Replace('"', '""') + '"' }
        return $s
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add((@($Headers | ForEach-Object { & $q $_ }) -join $Separator))
    foreach ($r in @($Rows)) { if ($null -ne $r) { $lines.Add((@(@($r) | ForEach-Object { & $q $_ }) -join $Separator)) } }
    return ($lines.ToArray() -join "`r`n")
}

function ConvertTo-HtmlReport {
    # Sections: @(@{ Title; Headers; Rows; Note }) -> one self-contained HTML page
    param([string]$Title, $Sections, [string]$Footer = "")
    $enc = { param($v) [System.Net.WebUtility]::HtmlEncode([string]$v) }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("<!DOCTYPE html>`r`n<html lang=`"de`"><head><meta charset=`"utf-8`"><title>" + (& $enc $Title) + "</title>`r`n<style>")
    [void]$sb.Append("body{font-family:'Segoe UI',sans-serif;margin:24px;color:#1f2328}h1{font-size:20px}h2{font-size:15px;margin-top:24px}")
    [void]$sb.Append("table{border-collapse:collapse;font-size:13px}th,td{padding:4px 10px;border-bottom:1px solid #d0d7de;text-align:left}")
    [void]$sb.Append("td.n{text-align:right;font-family:Consolas,monospace}th{background:#f6f8fa}p.note,footer{color:#656d76;font-size:12px}</style></head><body>`r`n")
    [void]$sb.Append("<h1>" + (& $enc $Title) + "</h1>`r`n")
    foreach ($sec in @($Sections)) {
        if ($null -eq $sec) { continue }
        if ($sec.Title) { [void]$sb.Append("<h2>" + (& $enc $sec.Title) + "</h2>`r`n") }
        if ($sec.Note) { [void]$sb.Append("<p class=`"note`">" + (& $enc $sec.Note) + "</p>`r`n") }
        if (@($sec.Headers).Count -eq 0) { continue }
        [void]$sb.Append("<table><tr>")
        foreach ($h in @($sec.Headers)) { [void]$sb.Append("<th>" + (& $enc $h) + "</th>") }
        [void]$sb.Append("</tr>`r`n")
        foreach ($r in @($sec.Rows)) {
            if ($null -eq $r) { continue }
            [void]$sb.Append("<tr>")
            foreach ($v in @($r)) {
                $sv = [string]$v
                $cls = if ($sv -match '^[-+−]?[\d.,'' ]+\s?(%|[A-Z]{3})?$' -and $sv -match '\d') { " class=`"n`"" } else { "" }
                [void]$sb.Append("<td$cls>" + (& $enc $sv) + "</td>")
            }
            [void]$sb.Append("</tr>`r`n")
        }
        [void]$sb.Append("</table>`r`n")
    }
    if ($Footer) { [void]$sb.Append("<footer><p>" + (& $enc $Footer) + "</p></footer>`r`n") }
    [void]$sb.Append("</body></html>`r`n")
    return $sb.ToString()
}

function Get-DialogPlacement {
    # Saved bounds of a dialog, only if at least 120 x 60 px of its top part
    # lie on one of the screens (monitor unplugged -> default position)
    # Saved: @{ X; Y; W; H }; Screens: @(@{ X; Y; W; H }) working areas
    param($Saved, $Screens, [int]$MinW = 200, [int]$MinH = 120)
    if ($null -eq $Saved) { return $null }
    $x = [int]$Saved.X; $y = [int]$Saved.Y; $w = [int]$Saved.W; $h = [int]$Saved.H
    if ($w -lt $MinW -or $h -lt $MinH) { return $null }
    foreach ($sc in @($Screens)) {
        if ($null -eq $sc) { continue }
        $ix = [math]::Min($x + $w, [int]$sc.X + [int]$sc.W) - [math]::Max($x, [int]$sc.X)
        $topIn = ($y -ge [int]$sc.Y - 4) -and ($y -le [int]$sc.Y + [int]$sc.H - 60)
        if ($ix -ge 120 -and $topIn) {
            # not larger than that screen
            $w2 = [math]::Min($w, [int]$sc.W); $h2 = [math]::Min($h, [int]$sc.H)
            return [PSCustomObject]@{ X = $x; Y = $y; W = $w2; H = $h2 }
        }
    }
    return $null
}

# ---- v5.5: chart - percent axis, drag zoom, zones; daily history cache ----
function Format-PctAxisLabel {
    # price -> change since the first visible bar ("+3.2%")
    param([double]$Value, [double]$Base)
    if ($Base -le 0 -or [double]::IsNaN($Value)) { return "" }
    $pc = ($Value / $Base - 1) * 100
    if ([math]::Abs($pc) -lt 0.05) { return "0%" }
    $fmt = if ([math]::Abs($pc) -ge 100) { "{0:+0;-0}%" } else { "{0:+0.0;-0.0}%" }
    return ($fmt -f $pc)
}

function Get-ZoomWindow {
    # Ctrl + drag from bar A to bar B (absolute indices) -> @{ Count; Offset }
    # for the chart view (Offset = bars hidden on the right); $null if too small
    param([int]$A, [int]$B, [int]$Total, [int]$MinBars = 10)
    if ($Total -lt 2) { return $null }
    $lo = [math]::Max(0, [math]::Min($A, $B)); $hi = [math]::Min($Total - 1, [math]::Max($A, $B))
    if ($hi - $lo + 1 -lt 3) { return $null }
    $cnt = $hi - $lo + 1
    if ($cnt -lt $MinBars) {
        $mid = ($lo + $hi) / 2.0
        $cnt = [math]::Min($Total, $MinBars)
        $lo = [int][math]::Round($mid - ($cnt - 1) / 2.0)
        $lo = [math]::Max(0, [math]::Min($Total - $cnt, $lo))
        $hi = $lo + $cnt - 1
    }
    if ($cnt -ge $Total) { return [PSCustomObject]@{ Count = 0; Offset = 0 } }
    return [PSCustomObject]@{ Count = $cnt; Offset = ($Total - 1 - $hi) }
}

function Test-PointInZone {
    # zone drawing: inside the rectangle, or within Tol of its border
    param([double]$X, [double]$Y, [double]$X1, [double]$Y1, [double]$X2, [double]$Y2, [double]$Tol = 4)
    $l = [math]::Min($X1, $X2) - $Tol; $r = [math]::Max($X1, $X2) + $Tol
    $t = [math]::Min($Y1, $Y2) - $Tol; $b = [math]::Max($Y1, $Y2) + $Tol
    return ($X -ge $l -and $X -le $r -and $Y -ge $t -and $Y -le $b)
}

function ConvertTo-DailyCacheEntry {
    # daily bars + signals of one ticker, as stored in daily_cache.json
    param($Bars, $Sig, [string]$Day)
    if ($null -eq $Bars) { return $null }
    $r2 = { param($a) @(@($a) | ForEach-Object { [math]::Round([double]$_, 4) }) }
    $sup = [double]::NaN; $res = [double]::NaN
    if ($null -ne $Sig -and $null -ne $Sig.Support) { $sup = [double]$Sig.Support.Support; $res = [double]$Sig.Support.Resistance }
    return [PSCustomObject]@{
        Day = $Day; Currency = [string]$Bars.Currency
        Dates = @($Bars.Dates); Close = (& $r2 $Bars.Close); High = (& $r2 $Bars.High); Low = (& $r2 $Bars.Low); Volume = @(@($Bars.Volume) | ForEach-Object { [math]::Round([double]$_) })
        Score = $(if ($null -ne $Sig) { [int]$Sig.Score } else { 0 }); Summary = $(if ($null -ne $Sig) { [string]$Sig.Summary } else { "" })
        Positive = $(if ($null -ne $Sig) { [int]$Sig.Positive } else { 0 }); Negative = $(if ($null -ne $Sig) { [int]$Sig.Negative } else { 0 })
        Support = $(if ([double]::IsNaN($sup)) { $null } else { [math]::Round($sup, 4) }); Resistance = $(if ([double]::IsNaN($res)) { $null } else { [math]::Round($res, 4) })
    }
}

function Test-DailyCacheFresh {
    param($Entry, [string]$Day)
    return ($null -ne $Entry -and [string]$Entry.Day -eq $Day -and @($Entry.Close).Count -ge 30)
}

function Format-SignalCell {
    # watchlist column: "+4" / "-2" / "0" with a sign for the colour
    param($Entry)
    if ($null -eq $Entry -or @($Entry.Close).Count -lt 30) { return [PSCustomObject]@{ Text = "-"; Sign = 0; Tip = "" } }
    $s = [int]$Entry.Score
    $t = if ($s -gt 0) { "+$s" } else { "$s" }
    $tip = "{0} ({1} positiv, {2} negativ) - Stand {3}" -f [string]$Entry.Summary, [int]$Entry.Positive, [int]$Entry.Negative, [string]$Entry.Day
    return [PSCustomObject]@{ Text = $t; Sign = [math]::Sign($s); Tip = $tip }
}


# ---- v5.5: savings plans - yearly increase, pause months ----
function ConvertTo-PauseMonths {
    # "7, 8" / "Jul Aug" / "juli,dez" -> @(7, 8) / @(7, 12); unknown parts are ignored
    param([string]$Text)
    $names = @{ "jan" = 1; "feb" = 2; "mar" = 3; "mrz" = 3; "apr" = 4; "mai" = 5; "may" = 5; "jun" = 6; "jul" = 7; "aug" = 8; "sep" = 9; "okt" = 10; "oct" = 10; "nov" = 11; "dez" = 12; "dec" = 12 }
    $out = New-Object System.Collections.Generic.List[int]
    foreach ($part in (([string]$Text) -split '[\s,;/]+')) {
        $t = (ConvertTo-SearchKey $part).Trim('.')
        if (-not $t) { continue }
        $n = 0
        if ([int]::TryParse($t, [ref]$n)) { if ($n -ge 1 -and $n -le 12 -and -not $out.Contains($n)) { $out.Add($n) }; continue }
        if ($t.Length -ge 3 -and $names.ContainsKey($t.Substring(0, 3)) -and -not $out.Contains($names[$t.Substring(0, 3)])) { $out.Add($names[$t.Substring(0, 3)]) }
    }
    return @($out | Sort-Object)
}

function Format-PauseMonths {
    param([int[]]$Months)
    $n = @("", "Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez")
    return (@(@($Months) | Where-Object { $_ -ge 1 -and $_ -le 12 } | Sort-Object -Unique | ForEach-Object { $n[$_] }) -join ", ")
}

function Get-SavingsPlanAmount {
    # amount for one booking date: + Increase % for every full year since Start
    param($Plan, [string]$Date)
    $amt = [double]$Plan.Amount
    $inc = if ($null -ne $Plan.PSObject.Properties["Increase"]) { [double]$Plan.Increase } else { 0.0 }
    if ($inc -eq 0 -or -not $Plan.Start -or -not $Date) { return $amt }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $st = [DateTime]::ParseExact([string]$Plan.Start, "yyyy-MM-dd", $inv)
    $d = [DateTime]::ParseExact($Date, "yyyy-MM-dd", $inv)
    $years = $d.Year - $st.Year
    if ($d.Month -lt $st.Month -or ($d.Month -eq $st.Month -and $d.Day -lt $st.Day)) { $years-- }
    if ($years -le 0) { return $amt }
    return [math]::Round($amt * [math]::Pow(1 + $inc / 100.0, $years), 2)
}

function Get-GroupScenarioImpact {
    # v5.5: what-if for one sector or one currency: positions of that group
    # move by Pct, the rest stays. Same shape as Get-ScenarioImpact
    # (Beta = 1 for the group, 0 otherwise).
    param([array]$Positions, [string]$Group, [double]$Pct)
    $rows = @()
    $tot = 0.0; $val = 0.0
    foreach ($p in @($Positions)) {
        if ($null -eq $p) { continue }
        $hit = ([string]$p.Group -eq $Group)
        $chg = if ($hit) { [double]$p.Value * $Pct / 100.0 } else { 0.0 }
        $rows += [PSCustomObject]@{ Sym = [string]$p.Sym; Value = [double]$p.Value; Beta = $(if ($hit) { 1.0 } else { 0.0 }); BetaAssumed = $false; Change = $chg; Group = [string]$p.Group }
        $tot += $chg; $val += [double]$p.Value
    }
    return [PSCustomObject]@{ Rows = @($rows | Sort-Object -Property @{ Expression = { [double]$_.Change }; Descending = $false }, @{ Expression = { [double]$_.Value }; Descending = $true }); Change = $tot; Value = $val; Pct = $(if ($val -gt 0) { $tot / $val * 100.0 } else { 0.0 }) }
}

function Get-DividendIncomeTable {
    # v5.5: received dividends (Items: @{ Date yyyy-MM-dd; Amount } in the base
    # currency) -> one row per year (newest first) with 12 months, total and
    # change to the year before; Max = largest month (for the colour scale)
    param($Items)
    $years = @{}
    foreach ($it in @($Items)) {
        if ($null -eq $it -or -not $it.Date -or [string]$it.Date -notmatch '^(\d{4})-(\d{2})') { continue }
        $y = [int]$Matches[1]; $m = [int]$Matches[2]
        if ($m -lt 1 -or $m -gt 12) { continue }
        if (-not $years.ContainsKey($y)) { $years[$y] = New-Object double[] 12 }
        $years[$y][$m - 1] += [double]$it.Amount
    }
    $rows = @(); $max = 0.0
    foreach ($y in @($years.Keys | Sort-Object -Descending)) {
        $ms = $years[$y]
        $tot = ($ms | Measure-Object -Sum).Sum
        foreach ($v in $ms) { if ($v -gt $max) { $max = $v } }
        $prev = if ($years.ContainsKey($y - 1)) { ($years[$y - 1] | Measure-Object -Sum).Sum } else { [double]::NaN }
        $chg = if (-not [double]::IsNaN($prev) -and $prev -gt 0) { ($tot / $prev - 1) * 100 } else { [double]::NaN }
        $rows += [PSCustomObject]@{ Year = $y; Months = [double[]]$ms; Total = [double]$tot; ChangePct = $chg; MonthlyAvg = [double]$tot / 12.0 }
    }
    return [PSCustomObject]@{ Rows = $rows; Max = $max; Total = [double](@($rows | ForEach-Object { $_.Total }) | Measure-Object -Sum).Sum }
}

# ==============================================================================
# v5.7: analysis without new providers - weekly signals, signal changes, peer
# groups, valuation vs. own history, RSS news, provider layer
# ==============================================================================
function ConvertTo-WeeklyBars {
    # daily bars -> weekly (week = Monday..Sunday): last close, highest high,
    # lowest low, summed volume; Dates = the last trading day of each week
    param([string[]]$Dates, [double[]]$Close, [double[]]$High = $null, [double[]]$Low = $null, [double[]]$Volume = $null)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $o = [PSCustomObject]@{ Dates = @(); Close = @(); High = @(); Low = @(); Volume = @() }
    $n = [math]::Min(@($Dates).Count, @($Close).Count)
    if ($n -eq 0) { return $o }
    $d = New-Object System.Collections.Generic.List[string]; $c = New-Object System.Collections.Generic.List[double]
    $h = New-Object System.Collections.Generic.List[double]; $l = New-Object System.Collections.Generic.List[double]; $v = New-Object System.Collections.Generic.List[double]
    $curKey = ""
    for ($i = 0; $i -lt $n; $i++) {
        $dt = [DateTime]::ParseExact([string]$Dates[$i], "yyyy-MM-dd", $inv)
        $dow = ([int]$dt.DayOfWeek + 6) % 7
        $key = $dt.AddDays(-$dow).ToString("yyyy-MM-dd", $inv)
        $hi = if ($null -ne $High -and $i -lt $High.Count) { [double]$High[$i] } else { [double]$Close[$i] }
        $lo = if ($null -ne $Low -and $i -lt $Low.Count) { [double]$Low[$i] } else { [double]$Close[$i] }
        $vo = if ($null -ne $Volume -and $i -lt $Volume.Count) { [double]$Volume[$i] } else { 0.0 }
        if ($key -ne $curKey) {
            $curKey = $key
            $d.Add([string]$Dates[$i]); $c.Add([double]$Close[$i]); $h.Add($hi); $l.Add($lo); $v.Add($vo)
        } else {
            $k = $d.Count - 1
            $d[$k] = [string]$Dates[$i]; $c[$k] = [double]$Close[$i]
            if ($hi -gt $h[$k]) { $h[$k] = $hi }
            if ($lo -lt $l[$k]) { $l[$k] = $lo }
            $v[$k] += $vo
        }
    }
    $o.Dates = $d.ToArray(); $o.Close = $c.ToArray(); $o.High = $h.ToArray(); $o.Low = $l.ToArray(); $o.Volume = $v.ToArray()
    return $o
}

function Get-SignalTone {
    # score -> +1 (überwiegend positiv) / -1 (überwiegend negativ) / 0
    param([int]$Score)
    if ($Score -ge 3) { return 1 }
    if ($Score -le -3) { return -1 }
    return 0
}

function Get-TimeframeVerdict {
    # daily and weekly signal score -> one plain-language sentence
    param([int]$Daily, [int]$Weekly, [bool]$HasWeekly = $true)
    $d = Get-SignalTone $Daily; $w = Get-SignalTone $Weekly
    if (-not $HasWeekly) { return [PSCustomObject]@{ Tone = $d; Text = "Zu wenig Wochendaten für die mittelfristige Sicht." } }
    $t = switch ("$d|$w") {
        "1|1"   { "Tages- und Wochensignale sind positiv: Aufwärtstrend auf beiden Zeitebenen." }
        "-1|-1" { "Tages- und Wochensignale sind negativ: Abwärtstrend auf beiden Zeitebenen." }
        "1|-1"  { "Kurzfristig positiv, mittelfristig negativ: eher eine Erholung im längeren Abwärtstrend." }
        "-1|1"  { "Kurzfristig negativ, mittelfristig positiv: eher ein Rücksetzer im längeren Aufwärtstrend." }
        "1|0"   { "Kurzfristig positiv, mittelfristig gemischt: der Aufwärtsimpuls ist auf Wochensicht noch nicht bestätigt." }
        "-1|0"  { "Kurzfristig negativ, mittelfristig gemischt: Schwäche, aber auf Wochensicht noch kein klarer Abwärtstrend." }
        "0|1"   { "Kurzfristig gemischt, mittelfristig positiv: der längere Aufwärtstrend ist intakt, kurzfristig ohne Richtung." }
        "0|-1"  { "Kurzfristig gemischt, mittelfristig negativ: der längere Abwärtstrend ist nicht gebrochen." }
        default { "Kein klares Bild auf beiden Zeitebenen." }
    }
    $tone = if ($d -eq $w) { $d } else { 0 }
    return [PSCustomObject]@{ Tone = $tone; Text = $t }
}

function Get-SignalChanges {
    # yesterday's vs. today's cache entry -> what changed (for alerts):
    # signal tone up / down, price crossing yesterday's support / resistance
    param($Old, $New)
    $out = @()
    if ($null -eq $Old -or $null -eq $New -or @($New.Close).Count -lt 2 -or [string]$Old.Day -eq [string]$New.Day) { return $out }
    $t0 = Get-SignalTone ([int]$Old.Score); $t1 = Get-SignalTone ([int]$New.Score)
    if ($t1 -ne $t0) {
        $lab = @{ "1" = "überwiegend positiv"; "-1" = "überwiegend negativ"; "0" = "gemischt" }
        $out += [PSCustomObject]@{ Kind = $(if ($t1 -gt $t0) { "Up" } else { "Down" }); Text = ("Signal jetzt {0} (vorher {1}, Score {2:+0;-0;0})" -f $lab["$t1"], $lab["$t0"], [int]$New.Score) }
    }
    $last = [double]@($New.Close)[-1]
    $prevClose = [double]@($Old.Close)[-1]
    if ($null -ne $Old.Support -and [double]$Old.Support -gt 0 -and $prevClose -ge [double]$Old.Support -and $last -lt [double]$Old.Support) {
        $out += [PSCustomObject]@{ Kind = "BelowSupport"; Text = ("Kurs unter die Unterstützung {0:N2} gefallen" -f [double]$Old.Support) }
    }
    if ($null -ne $Old.Resistance -and [double]$Old.Resistance -gt 0 -and $prevClose -le [double]$Old.Resistance -and $last -gt [double]$Old.Resistance) {
        $out += [PSCustomObject]@{ Kind = "AboveResistance"; Text = ("Kurs über den Widerstand {0:N2} gestiegen" -f [double]$Old.Resistance) }
    }
    return $out
}

function Get-MaCrossMarkers {
    # days where the fast average crosses the slow one (Golden / Death cross)
    param([double[]]$Closes, [string[]]$Dates, [int]$Fast = 50, [int]$Slow = 200)
    $out = @()
    $n = [math]::Min(@($Closes).Count, @($Dates).Count)
    if ($n -le $Slow) { return $out }
    $f = Compute-Sma -Prices $Closes -Period $Fast
    $s = Compute-Sma -Prices $Closes -Period $Slow
    for ($i = $Slow; $i -lt $n; $i++) {
        if ([double]::IsNaN($f[$i - 1]) -or [double]::IsNaN($s[$i - 1])) { continue }
        $a = $f[$i - 1] - $s[$i - 1]; $b = $f[$i] - $s[$i]
        if ($a -le 0 -and $b -gt 0) { $out += [PSCustomObject]@{ Date = [string]$Dates[$i]; Kind = "Golden" } }
        elseif ($a -ge 0 -and $b -lt 0) { $out += [PSCustomObject]@{ Date = [string]$Dates[$i]; Kind = "Death" } }
    }
    return $out
}

function ConvertTo-PeerList {
    # "AMD, intc  TSM;AMD" -> @("AMD", "INTC", "TSM") without the ticker itself, max 15
    param([string]$Text, [string]$Self = "")
    $me = ([string]$Self).Trim().ToUpperInvariant()
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($p in (([string]$Text) -split '[\s,;]+')) {
        $u = $p.Trim().ToUpperInvariant()
        if (-not $u -or $u -eq $me -or $out.Contains($u) -or $u -notmatch '^[A-Z0-9\^][A-Z0-9\.\-=\^]{0,19}$') { continue }
        $out.Add($u)
        if ($out.Count -ge 15) { break }
    }
    return @($out)
}

function Get-ValuationKeys {
    return @(@("TrailingPE", "KGV (12 Monate)"), @("ForwardPE", "KGV erwartet"), @("PriceToSales", "KUV"), @("PriceToBook", "KBV"), @("EvEbitda", "EV / EBITDA"), @("DivYield", "Dividendenrendite"))
}

function Add-FundSnapshot {
    # one valuation snapshot per day (newest last, at most Max days)
    param($History, $Fund, [string]$Day, [int]$Max = 500)
    $list = @(@($History) | Where-Object { $null -ne $_ -and [string]$_.D -ne $Day })
    if ($null -eq $Fund) { return $list }
    $snap = [ordered]@{ D = $Day }
    $any = $false
    foreach ($k in (Get-ValuationKeys)) {
        $pp = $Fund.PSObject.Properties[$k[0]]
        $v = $null
        if ($null -ne $pp -and $null -ne $pp.Value -and [string]$pp.Value -ne "") { try { $x = [double]$pp.Value; if (-not [double]::IsNaN($x) -and -not [double]::IsInfinity($x)) { $v = [math]::Round($x, 4); $any = $true } } catch { } }
        $snap[$k[0]] = $v
    }
    if ($any) { $list += [PSCustomObject]$snap }
    $list = @($list | Sort-Object -Property { [string]$_.D })
    if ($list.Count -gt $Max) { $list = @($list | Select-Object -Last $Max) }
    return $list
}

function Get-ValuationVsHistory {
    # today's ratio vs. the snapshots collected so far: median, range, rank
    # Rows only for keys with at least MinDays values
    param($History, $Fund, [int]$MinDays = 20)
    $rows = @()
    $hist = @(@($History) | Where-Object { $null -ne $_ })
    foreach ($k in (Get-ValuationKeys)) {
        $vals = @($hist | ForEach-Object { $_.PSObject.Properties[$k[0]] } | Where-Object { $null -ne $_ -and $null -ne $_.Value } | ForEach-Object { [double]$_.Value })
        if ($vals.Count -lt $MinDays) { continue }
        $now = [double]::NaN
        if ($null -ne $Fund -and $null -ne $Fund.PSObject.Properties[$k[0]] -and $null -ne $Fund.($k[0])) { try { $now = [double]$Fund.($k[0]) } catch { } }
        if ([double]::IsNaN($now)) { $now = $vals[-1] }
        $sorted = @($vals | Sort-Object)
        $med = Get-Median $sorted
        # mid-rank: equal values count half (flat history -> 50)
        $below = @($sorted | Where-Object { $_ -lt $now }).Count
        $equal = @($sorted | Where-Object { $_ -eq $now }).Count
        $rank = [math]::Round(100.0 * ($below + 0.5 * $equal) / $sorted.Count)
        $note = if ($k[0] -eq "DivYield") {
            if ($rank -ge 80) { "Rendite hoch gegenüber der eigenen Historie (eher günstig)" } elseif ($rank -le 20) { "Rendite niedrig gegenüber der eigenen Historie (eher teuer)" } else { "im üblichen Bereich" }
        } else {
            if ($rank -ge 80) { "teuer gegenüber der eigenen Historie" } elseif ($rank -le 20) { "günstig gegenüber der eigenen Historie" } else { "im üblichen Bereich" }
        }
        $rows += [PSCustomObject]@{ Key = $k[0]; Label = $k[1]; Now = $now; Median = $med; Min = $sorted[0]; Max = $sorted[-1]; Count = $sorted.Count; Rank = $rank; Note = $note; Since = [string]$hist[0].D }
    }
    return $rows
}

function ConvertFrom-RssFeed {
    # RSS 2.0 or Atom text -> @(@{ Title; Publisher; Link; Time; Tickers = @() })
    # DTDs and external entities are not processed (safe for any feed)
    param([string]$Text, [string]$Fallback = "")
    $out = @()
    if (-not ([string]$Text).Trim().StartsWith("<")) { return $out }
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    $set = New-Object System.Xml.XmlReaderSettings
    $set.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $set.XmlResolver = $null
    try {
        $rd = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader($Text)), $set)
        $doc.Load($rd); $rd.Close()
    } catch { return $out }
    $parseT = {
        param([string]$s)
        $dto = [DateTimeOffset]::MinValue
        $s2 = ([string]$s).Trim() -replace '\s(GMT|UT|UTC)$', ' +0000' -replace '\sCET$', ' +0100' -replace '\sCEST$', ' +0200'
        if ([DateTimeOffset]::TryParse($s2, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$dto)) { return $dto.LocalDateTime }
        return [DateTime]::MinValue
    }
    $root = $doc.DocumentElement
    if ($null -eq $root) { return $out }
    if ($root.LocalName -eq "feed") {
        $pub = ([string]($root.SelectSingleNode("*[local-name()='title']").InnerText)).Trim()
        foreach ($e in @($root.SelectNodes("*[local-name()='entry']"))) {
            $ln = $e.SelectSingleNode("*[local-name()='link'][@rel='alternate' or not(@rel)]")
            $link = if ($null -ne $ln) { [string]$ln.GetAttribute("href") } else { "" }
            $tn = $e.SelectSingleNode("*[local-name()='updated' or local-name()='published']")
            $sn = $e.SelectSingleNode("*[local-name()='summary']")
            if ($null -eq $sn) { $sn = $e.SelectSingleNode("*[local-name()='content' and namespace-uri()=namespace-uri(..)]") }
            $body = if ($null -ne $sn) { [string]$sn.InnerText } else { "" }
            $out += [PSCustomObject]@{ Title = ([string]$e.SelectSingleNode("*[local-name()='title']").InnerText).Trim(); Publisher = $(if ($pub) { $pub } else { $Fallback }); Link = $(if ($link -match '^https?://') { $link } else { "" }); Time = $(if ($null -ne $tn) { & $parseT $tn.InnerText } else { [DateTime]::MinValue }); Tickers = @(); Summary = (ConvertTo-PlainSummary $body); Image = (Get-FeedItemImage -Node $e -Html $body) }
        }
        return @($out | Where-Object { $_.Title })
    }
    $ch = $root.SelectSingleNode("*[local-name()='channel']")
    if ($null -eq $ch) { $ch = $root }
    $tt = $ch.SelectSingleNode("*[local-name()='title']")
    $pub = if ($null -ne $tt) { ([string]$tt.InnerText).Trim() } else { "" }
    foreach ($it in @($root.SelectNodes("//*[local-name()='item']"))) {
        $tn = $it.SelectSingleNode("*[local-name()='title']"); $lk = $it.SelectSingleNode("*[local-name()='link']")
        $dn = $it.SelectSingleNode("*[local-name()='pubDate' or local-name()='date']")
        $link = if ($null -ne $lk) { ([string]$lk.InnerText).Trim() } else { "" }
        $sn = $it.SelectSingleNode("*[local-name()='description']")
        if ($null -eq $sn) { $sn = $it.SelectSingleNode("*[local-name()='encoded']") }
        $body = if ($null -ne $sn) { [string]$sn.InnerText } else { "" }
        $out += [PSCustomObject]@{ Title = $(if ($null -ne $tn) { ([string]$tn.InnerText).Trim() } else { "" }); Publisher = $(if ($pub) { $pub } else { $Fallback }); Link = $(if ($link -match '^https?://') { $link } else { "" }); Time = $(if ($null -ne $dn) { & $parseT $dn.InnerText } else { [DateTime]::MinValue }); Tickers = @(); Summary = (ConvertTo-PlainSummary $body); Image = (Get-FeedItemImage -Node $it -Html $body) }
    }
    return @($out | Where-Object { $_.Title })
}

function Get-NewsNameKey {
    # company name -> the word to look for in headlines ("NVIDIA Corporation" -> "nvidia")
    param([string]$Name)
    $stop = @("the", "inc", "corp", "corporation", "ag", "se", "plc", "nv", "sa", "co", "ltd", "group", "holding", "holdings", "company", "class", "ishares", "vanguard", "xtrackers", "core", "msci", "etf", "ucits")
    foreach ($w in ((ConvertTo-SearchKey $Name) -split '[^a-z0-9]+')) { if ($w.Length -ge 4 -and $stop -notcontains $w) { return $w } }
    return ""
}

function Add-RssToFeed {
    # merged Yahoo feed + RSS items -> one feed (newest first, no duplicates);
    # RSS items get the tickers whose name key (NameMap: sym -> word) is in the title
    param($Feed, $RssItems, [hashtable]$NameMap = @{}, [int]$Max = 150, [int]$MaxAgeDays = 14, [DateTime]$Now = [DateTime]::MinValue)
    if ($Now -eq [DateTime]::MinValue) { $Now = Get-Date }
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($f in @($Feed)) { if ($null -ne $f) { [void]$seen.Add([string]$f.Key); $out.Add($f) } }
    foreach ($n in @($RssItems)) {
        if ($null -eq $n -or -not $n.Title) { continue }
        $t = if ($null -ne $n.Time) { [DateTime]$n.Time } else { [DateTime]::MinValue }
        if ($t -gt [DateTime]::MinValue -and ($Now - $t).TotalDays -gt $MaxAgeDays) { continue }
        $key = Get-NewsKey $n
        if (-not $seen.Add($key)) { continue }
        $tk = ConvertTo-SearchKey ([string]$n.Title)
        $syms = @(foreach ($s in $NameMap.Keys) { $w = [string]$NameMap[$s]; if ($w -and $tk -match ('\b' + [regex]::Escape($w) + '\b')) { ([string]$s).ToUpperInvariant() } })
        $out.Add([PSCustomObject]@{ Key = $key; Title = ([string]$n.Title).Trim(); Publisher = [string]$n.Publisher; Link = [string]$n.Link; Time = $t; Syms = @($syms | Sort-Object -Unique) })
    }
    $sorted = @($out | Sort-Object -Property @{ Expression = { $_.Time }; Descending = $true }, @{ Expression = { $_.Title }; Descending = $false })
    if ($sorted.Count -gt $Max) { $sorted = @($sorted[0..($Max - 1)]) }
    return $sorted
}

function ConvertTo-FeedList {
    # settings text -> http(s) URLs (comma, semicolon, space or line break separated), max 10
    param([string]$Text)
    return @(@(([string]$Text) -split '[\s,;]+') | Where-Object { $_ -match '^https?://[^\s]+$' } | Select-Object -Unique -First 10)
}

# ---- provider layer (groundwork): every data request is built here ----
function Get-DataProviders { return @("Yahoo", "TwelveData", "Finnhub") }

function Get-ProviderUrl {
    # Kind: Chart (Range, Interval), Daily (1y daily bars), Search (news), Quote
    # Provider: Yahoo for now; V6 adds Twelve Data / Finnhub behind the same call
    param([string]$Kind, [string]$Symbol, [string]$Range = "1y", [string]$Interval = "1d", [int]$NewsCount = 10, [string]$Provider = "Yahoo")
    $s = [Uri]::EscapeDataString(([string]$Symbol).Trim())
    switch ($Kind) {
        "Daily"  { return "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval=1d&range={1}" -f $s, $Range }
        "Chart"  { return "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval={1}&range={2}" -f $s, $Interval, $Range }
        "Search" { return "https://query1.finance.yahoo.com/v1/finance/search?q={0}&quotesCount=0&newsCount={1}" -f $s, $NewsCount }
        default  { return "" }
    }
}

function Get-ProviderOfUrl {
    # host -> provider name for the request budget ("Yahoo", "RSS: derstandard.at", ...)
    param([string]$Url)
    $u = $null
    if (-not [Uri]::TryCreate([string]$Url, [UriKind]::Absolute, [ref]$u)) { return "?" }
    $h = $u.Host.ToLowerInvariant()
    if ($h -like "*finance.yahoo.com" -or $h -like "*yahoo.com") { return "Yahoo" }
    if ($h -like "*twelvedata.com") { return "TwelveData" }
    if ($h -like "*finnhub.io") { return "Finnhub" }
    return "RSS: " + ($h -replace '^www\.', '')
}

# ==============================================================================
# V6.0: data providers (Twelve Data, Finnhub) and deeper ticker analysis
# Free tiers (checked 2026-11): Twelve Data Basic = 8 credits / min, 800 / day,
# US markets only, no earnings; Finnhub free = 60 calls / min, basic financials,
# earnings surprises (last 4 quarters), recommendation trends. Everything else
# is probed with the user's key (Test-Providers) and only used when it works.
# ==============================================================================
function Get-ProviderLimits {
    # requests per minute / per day we allow ourselves (a little below the plan)
    return @{
        "TwelveData" = [PSCustomObject]@{ PerMin = 7; PerDay = 780 }
        "Finnhub"    = [PSCustomObject]@{ PerMin = 55; PerDay = 0 }
    }
}

function Test-UsSymbol {
    # Yahoo symbol without exchange suffix and not an index / FX pair -> US listing
    param([string]$Symbol)
    $s = ([string]$Symbol).Trim().ToUpperInvariant()
    return ($s -match '^[A-Z][A-Z0-9\-]{0,9}$')
}

function ConvertTo-ProviderSymbol {
    # Yahoo symbol -> provider symbol; "" when the free tier does not cover it
    param([string]$Symbol, [string]$Provider)
    $s = ([string]$Symbol).Trim().ToUpperInvariant()
    if (-not (Test-UsSymbol $s)) { return "" }
    if ($Provider -eq "TwelveData") { return ($s -replace '-', '.') }   # BRK-B -> BRK.B
    return ($s -replace '-', '.')
}

function Get-ProviderRequestUrl {
    # Twelve Data / Finnhub URLs (the key is a query parameter; log lines are redacted)
    param([string]$Provider, [string]$Kind, [string]$Symbol, [string]$Key, [string]$From = "", [string]$To = "")
    $k = [Uri]::EscapeDataString([string]$Key)
    $s = [Uri]::EscapeDataString([string]$Symbol)
    if ($Provider -eq "TwelveData") {
        switch ($Kind) {
            "Daily" { return "https://api.twelvedata.com/time_series?symbol={0}&interval=1day&outputsize=260&apikey={1}" -f $s, $k }
            "Quote" { return "https://api.twelvedata.com/quote?symbol={0}&apikey={1}" -f $s, $k }
        }
        return ""
    }
    switch ($Kind) {
        "Daily"    { return "https://finnhub.io/api/v1/stock/candle?symbol={0}&resolution=D&from={1}&to={2}&token={3}" -f $s, $From, $To, $k }
        "Quote"    { return "https://finnhub.io/api/v1/quote?symbol={0}&token={1}" -f $s, $k }
        "Metric"   { return "https://finnhub.io/api/v1/stock/metric?symbol={0}&metric=all&token={1}" -f $s, $k }
        "Earnings" { return "https://finnhub.io/api/v1/stock/earnings?symbol={0}&token={1}" -f $s, $k }
        "Calendar" { return "https://finnhub.io/api/v1/calendar/earnings?symbol={0}&from={1}&to={2}&token={3}" -f $s, $From, $To, $k }
        "Recommendation" { return "https://finnhub.io/api/v1/stock/recommendation?symbol={0}&token={1}" -f $s, $k }
        "PriceTarget"    { return "https://finnhub.io/api/v1/stock/price-target?symbol={0}&token={1}" -f $s, $k }
    }
    return ""
}

function Hide-ApiKeys {
    # log lines never contain keys: apikey=..., token=...
    param([string]$Text)
    return ([string]$Text -replace '(?i)\b(apikey|token|api_key)=[^&\s"'']+', '$1=***')
}

function Get-ProviderError {
    # provider answer -> "" (fine) or an error text (Twelve Data sends errors with HTTP 200)
    param($Json)
    if ($null -eq $Json) { return "keine Antwort" }
    if ($Json -is [string]) { return "unerwartete Antwort" }
    if ($null -ne $Json.PSObject.Properties["status"] -and [string]$Json.status -eq "error") { return ("{0} {1}" -f [string]$Json.code, [string]$Json.message).Trim() }
    if ($null -ne $Json.PSObject.Properties["error"] -and [string]$Json.error) { return [string]$Json.error }
    if ($null -ne $Json.PSObject.Properties["s"] -and [string]$Json.s -eq "no_data") { return "keine Daten" }
    return ""
}

function ConvertFrom-TwelveDataSeries {
    # /time_series (1day) -> bars like ConvertFrom-YahooOhlc (oldest first)
    param($Json)
    if ((Get-ProviderError $Json) -or $null -eq $Json.values) { return $null }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $vals = @($Json.values)
    [array]::Reverse($vals)
    $o = [PSCustomObject]@{ Dates = @(); Open = @(); High = @(); Low = @(); Close = @(); Volume = @(); Currency = ""; Name = ""; Source = "TwelveData" }
    $num = { param($x) $d = 0.0; if ([double]::TryParse([string]$x, [System.Globalization.NumberStyles]::Float, $inv, [ref]$d)) { $d } else { [double]::NaN } }
    $aD = @(); $aO = @(); $aH = @(); $aL = @(); $aC = @(); $aV = @()
    foreach ($v in $vals) {
        $c0 = & $num $v.close
        if ([double]::IsNaN($c0) -or $c0 -le 0) { continue }
        $aD += ([string]$v.datetime).Substring(0, 10); $aC += $c0
        $o0 = & $num $v.open; $h0 = & $num $v.high; $l0 = & $num $v.low; $v0 = & $num $v.volume
        $aO += $(if ([double]::IsNaN($o0)) { $c0 } else { $o0 }); $aH += $(if ([double]::IsNaN($h0)) { $c0 } else { $h0 }); $aL += $(if ([double]::IsNaN($l0)) { $c0 } else { $l0 }); $aV += $(if ([double]::IsNaN($v0)) { 0.0 } else { $v0 })
    }
    if ($aC.Count -eq 0) { return $null }
    $o.Dates = $aD; $o.Open = [double[]]$aO; $o.High = [double[]]$aH; $o.Low = [double[]]$aL; $o.Close = [double[]]$aC; $o.Volume = [double[]]$aV
    if ($null -ne $Json.meta) { $o.Currency = [string]$Json.meta.currency; $o.Name = [string]$Json.meta.symbol }
    return $o
}

function ConvertFrom-FinnhubCandles {
    # /stock/candle -> bars (dates in UTC; daily bars have no time of day)
    param($Json, [string]$Currency = "USD")
    if ((Get-ProviderError $Json) -or $null -eq $Json.c -or $null -eq $Json.t) { return $null }
    $n = [math]::Min(@($Json.c).Count, @($Json.t).Count)
    if ($n -eq 0) { return $null }
    $o = [PSCustomObject]@{ Dates = @(); Open = @(); High = @(); Low = @(); Close = @(); Volume = @(); Currency = $Currency; Name = ""; Source = "Finnhub" }
    $aD = @(); $aC = @(); $aO = @(); $aH = @(); $aL = @(); $aV = @()
    for ($i = 0; $i -lt $n; $i++) {
        $c0 = [double]$Json.c[$i]
        if ($c0 -le 0) { continue }
        $aD += [DateTimeOffset]::FromUnixTimeSeconds([long]$Json.t[$i]).UtcDateTime.ToString("yyyy-MM-dd"); $aC += $c0
        $aO += $(if ($null -ne $Json.o) { [double]$Json.o[$i] } else { $c0 }); $aH += $(if ($null -ne $Json.h) { [double]$Json.h[$i] } else { $c0 })
        $aL += $(if ($null -ne $Json.l) { [double]$Json.l[$i] } else { $c0 }); $aV += $(if ($null -ne $Json.v) { [double]$Json.v[$i] } else { 0.0 })
    }
    $o.Dates = $aD; $o.Open = [double[]]$aO; $o.High = [double[]]$aH; $o.Low = [double[]]$aL; $o.Close = [double[]]$aC; $o.Volume = [double[]]$aV
    return $o
}

function Test-ProviderBudget {
    # may one more request go to this provider? Log = @(@{ T; P }), DayCount =
    # requests already sent today (kept across restarts)
    param($Log, [string]$Provider, [DateTime]$Now = (Get-Date), [int]$DayCount = 0)
    $lim = (Get-ProviderLimits)[$Provider]
    if ($null -eq $lim) { return [PSCustomObject]@{ Ok = $true; Reason = "" } }
    $lastMin = @(@($Log) | Where-Object { $null -ne $_ -and [string]$_.P -eq $Provider -and ($Now - [DateTime]$_.T).TotalSeconds -lt 60 }).Count
    if ($lim.PerDay -gt 0 -and $DayCount -ge $lim.PerDay) { return [PSCustomObject]@{ Ok = $false; Reason = ("{0}: Tageslimit erreicht ({1}) - wieder ab morgen" -f $Provider, $lim.PerDay) } }
    if ($lastMin -ge $lim.PerMin) { return [PSCustomObject]@{ Ok = $false; Reason = ("{0}: Minutenlimit erreicht ({1}) - kurz warten" -f $Provider, $lim.PerMin) } }
    return [PSCustomObject]@{ Ok = $true; Reason = "" }
}

function Format-ProviderReport {
    # probe results @(@{ Provider; Kind; Ok; Detail }) -> text for the user
    param($Results)
    $lab = @{ Daily = "Tageskurse (Verlauf)"; Quote = "Kurs"; Metric = "Kennzahlen + Verlauf"; Earnings = "Quartalszahlen (Überraschung)"; Calendar = "Termine der Quartalszahlen"; Recommendation = "Analysten-Empfehlungen"; PriceTarget = "Kursziele" }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($grp in @(@($Results) | Group-Object -Property Provider)) {
        $lines.Add([string]$grp.Name)
        foreach ($r in $grp.Group) { $lines.Add(("  {0} {1,-32} {2}" -f $(if ($r.Ok) { "OK" } else { "--" }), $lab[[string]$r.Kind], [string]$r.Detail).TrimEnd()) }
        $lines.Add("")
    }
    return ($lines.ToArray() -join "`r`n").TrimEnd()
}

function ConvertFrom-FinnhubMetricSeries {
    # /stock/metric?metric=all -> @{ Annual = rows; Quarterly = valuation history }
    # Annual rows: @{ Key; Label; Points = @(@{ Year; Value }) } newest year last
    param($Json, [int]$Years = 5)
    $res = [PSCustomObject]@{ Annual = @(); Quarterly = @() }
    if ((Get-ProviderError $Json) -or $null -eq $Json.series) { return $res }
    $keys = @(@("pe", "KGV", "Ratio"), @("ps", "KUV", "Ratio"), @("pb", "KBV", "Ratio"), @("grossMargin", "Bruttomarge", "Pct"), @("operatingMargin", "Operative Marge", "Pct"),
              @("netMargin", "Nettomarge", "Pct"), @("roe", "Eigenkapitalrendite", "Pct"), @("eps", "Gewinn je Aktie", "Plain"), @("currentRatio", "Liquidität (Current Ratio)", "Ratio"), @("totalDebtToEquity", "Verschuldung (FK/EK)", "Ratio"))
    $an = $Json.series.annual
    if ($null -ne $an) {
        foreach ($k in $keys) {
            $pp = $an.PSObject.Properties[$k[0]]
            if ($null -eq $pp -or $null -eq $pp.Value) { continue }
            $pts = @(@($pp.Value) | Where-Object { $null -ne $_ -and $null -ne $_.v -and $_.period } | ForEach-Object { [PSCustomObject]@{ Year = ([string]$_.period).Substring(0, 4); Value = [double]$_.v } } | Sort-Object Year)
            if ($pts.Count -eq 0) { continue }
            # margins may come as fractions (0.25) or percent (25) - show percent
            if ($k[2] -eq "Pct" -and @($pts | Where-Object { [math]::Abs($_.Value) -gt 1.5 }).Count -eq 0) { foreach ($pt in $pts) { $pt.Value = $pt.Value * 100 } }
            $res.Annual += [PSCustomObject]@{ Key = $k[0]; Label = $k[1]; Kind = $k[2]; Points = @($pts | Select-Object -Last $Years) }
        }
    }
    # quarterly P/E, P/S, P/B as valuation history (same shape as fund_history)
    $q = $Json.series.quarterly
    if ($null -ne $q) {
        $byDate = @{}
        foreach ($m in @(@("pe", "TrailingPE"), @("ps", "PriceToSales"), @("pb", "PriceToBook"))) {
            $pp = $q.PSObject.Properties[$m[0]]
            if ($null -eq $pp) { continue }
            foreach ($x in @($pp.Value)) {
                if ($null -eq $x -or $null -eq $x.v -or -not $x.period) { continue }
                $d = [string]$x.period
                if (-not $byDate.ContainsKey($d)) { $byDate[$d] = [ordered]@{ D = $d } }
                $byDate[$d][$m[1]] = [double]$x.v
            }
        }
        $res.Quarterly = @($byDate.Keys | Sort-Object | ForEach-Object { [PSCustomObject]$byDate[$_] })
    }
    return $res
}

function Format-SeriesTrend {
    # "25,1 → 28,4 → 31,0 (2022–2024)"; Pct values are fractions? Finnhub sends margins in %
    param($Points, [string]$Kind = "Ratio")
    $p = @($Points)
    if ($p.Count -eq 0) { return "" }
    $fmt = if ($Kind -eq "Pct") { "{0:N1}%" } else { "{0:N1}" }
    $vals = @($p | ForEach-Object { $fmt -f [double]$_.Value }) -join (" " + [string][char]0x2192 + " ")
    return "{0} ({1}{2}{3})" -f $vals, $p[0].Year, [string][char]0x2013, $p[-1].Year
}

function Get-EarningsReaction {
    # price move around a report: last close before the report day ("amc" =
    # after the close: the report day itself counts as before) to the first
    # close after it. NaN when the prices do not cover the date.
    param([string[]]$Dates, [double[]]$Closes, [string]$ReportDate, [string]$Hour = "")
    $n = [math]::Min(@($Dates).Count, @($Closes).Count)
    if ($n -lt 2 -or -not $ReportDate) { return [double]::NaN }
    $amc = ([string]$Hour -eq "amc")
    $bi = -1; $ai = -1
    for ($i = 0; $i -lt $n; $i++) {
        $c = [string]::CompareOrdinal([string]$Dates[$i], $ReportDate)
        if ($c -lt 0 -or ($amc -and $c -eq 0)) { $bi = $i }
        elseif ($ai -lt 0 -and $bi -ge 0 -and ($c -gt 0 -or (-not $amc -and $c -eq 0))) { $ai = $i }
    }
    if ($bi -lt 0 -or $ai -lt 0 -or [double]$Closes[$bi] -le 0) { return [double]::NaN }
    return ([double]$Closes[$ai] / [double]$Closes[$bi] - 1) * 100
}

function ConvertFrom-FinnhubEarnings {
    # /stock/earnings + optional /calendar/earnings (report dates) + daily
    # prices -> @(@{ Period; Actual; Estimate; SurprisePct; Date; ReactionPct }) newest first
    param($Earnings, $Calendar = $null, [string[]]$Dates = @(), [double[]]$Closes = @())
    $out = @()
    if ($null -eq $Earnings -or (Get-ProviderError $Earnings)) { return $out }
    $cal = @()
    if ($null -ne $Calendar -and $null -ne $Calendar.earningsCalendar) { $cal = @($Calendar.earningsCalendar | Where-Object { $_.date } | Sort-Object { [string]$_.date }) }
    foreach ($e in @($Earnings | Sort-Object { [string]$_.period } -Descending)) {
        if ($null -eq $e -or -not $e.period) { continue }
        $act = if ($null -ne $e.actual) { [double]$e.actual } else { [double]::NaN }
        $est = if ($null -ne $e.estimate) { [double]$e.estimate } else { [double]::NaN }
        $sp = if ($null -ne $e.surprisePercent) { [double]$e.surprisePercent } elseif (-not [double]::IsNaN($est) -and $est -ne 0 -and -not [double]::IsNaN($act)) { ($act / $est - 1) * 100 } else { [double]::NaN }
        # report = first calendar date after the quarter end (within 100 days)
        $rep = @($cal | Where-Object { [string]::CompareOrdinal([string]$_.date, [string]$e.period) -gt 0 -and ([DateTime]$_.date - [DateTime]$e.period).TotalDays -le 100 })
        $rd = if ($rep.Count -gt 0) { [string]$rep[0].date } else { "" }
        $hr = if ($rep.Count -gt 0) { [string]$rep[0].hour } else { "" }
        $rx = if ($rd) { Get-EarningsReaction -Dates $Dates -Closes $Closes -ReportDate $rd -Hour $hr } else { [double]::NaN }
        $out += [PSCustomObject]@{ Period = [string]$e.period; Actual = $act; Estimate = $est; SurprisePct = $sp; Date = $rd; ReactionPct = $rx }
    }
    return $out
}

function Get-RecommendationTrend {
    # /stock/recommendation (monthly, newest first) -> counts now, 3 months ago,
    # mean score (1 = strong buy ... 5 = strong sell) and a short trend text
    param($Json)
    $rows = @(@($Json) | Where-Object { $null -ne $_ -and $_.period } | Sort-Object { [string]$_.period } -Descending)
    if ($rows.Count -eq 0 -or (Get-ProviderError $Json)) { return $null }
    $score = {
        param($r)
        $sb = [double]$r.strongBuy; $b = [double]$r.buy; $h = [double]$r.hold; $s = [double]$r.sell; $ss = [double]$r.strongSell
        $tot = $sb + $b + $h + $s + $ss
        if ($tot -le 0) { return [double]::NaN }
        return ($sb * 1 + $b * 2 + $h * 3 + $s * 4 + $ss * 5) / $tot
    }
    $now = $rows[0]
    $old = if ($rows.Count -ge 4) { $rows[3] } else { $rows[-1] }
    $s0 = & $score $now; $s1 = & $score $old
    $trend = if ([double]::IsNaN($s0) -or [double]::IsNaN($s1) -or $rows.Count -lt 2) { "" } elseif ($s0 -lt $s1 - 0.1) { "positiver" } elseif ($s0 -gt $s1 + 0.1) { "negativer" } else { "unverändert" }
    $cnt = { param($r) "{0} {1} / {2} {3} / {4} {5}" -f ([int]$r.strongBuy + [int]$r.buy), "Kauf", [int]$r.hold, "Halten", ([int]$r.sell + [int]$r.strongSell), "Verkauf" }
    return [PSCustomObject]@{ Now = (& $cnt $now); Before = (& $cnt $old); Score = $s0; ScoreBefore = $s1; Trend = $trend; Period = [string]$now.period; PeriodBefore = [string]$old.period }
}

function Test-ProviderCacheFresh {
    # provider_cache.json entries: @{ Day; Data } - refreshed once a day
    param($Entry, [string]$Day)
    return ($null -ne $Entry -and [string]$Entry.Day -eq $Day)
}

# ==============================================================================
# v7.7: selectable news sources, matching, reading (pure logic)
# A source: Id, Url, Name, On, Notify, Group, Ticker, Minutes (0 = global),
# MaxAgeDays (0 = 14). "yahoo" is the built-in source id.
# ==============================================================================
function ConvertTo-NewsSource {
    # any object (config JSON, OPML row, dialog row) -> a clean source, $null without a web address
    param($In)
    if ($null -eq $In) { return $null }
    $url = ([string]$In.Url).Trim()
    if ($url -notmatch '^https?://[^\s]+$') { return $null }
    $int = { param($v, [int]$min, [int]$max) $x = 0; if (-not [int]::TryParse(([string]$v).Trim(), [ref]$x) -or $x -le 0) { return 0 }; return [math]::Max($min, [math]::Min($max, $x)) }
    $bool = { param($v, [bool]$def) if ($null -eq $v -or [string]$v -eq "") { return $def }; if ($v -is [bool]) { return $v }; return ([string]$v -eq "True") }
    $id = ([string]$In.Id).Trim()
    if (-not $id -or $id -eq "yahoo") { $id = "f" + [Guid]::NewGuid().ToString("N").Substring(0, 10) }
    return [PSCustomObject]@{
        Id = $id; Url = $url; Name = ([string]$In.Name).Trim()
        On = (& $bool $In.On $true); Notify = (& $bool $In.Notify $true)
        Group = ([string]$In.Group).Trim(); Ticker = ([string]$In.Ticker).Trim().ToUpperInvariant()
        Minutes = (& $int $In.Minutes 5 1440); MaxAgeDays = (& $int $In.MaxAgeDays 1 90)
    }
}

function ConvertTo-NewsSourceList {
    # clean list: invalid rows dropped, each address once, unique ids, at most Max
    param($List, [int]$Max = 30)
    $out = @()
    $urls = New-Object System.Collections.Generic.HashSet[string]
    $ids = New-Object System.Collections.Generic.HashSet[string]
    foreach ($e in @($List)) {
        $s = ConvertTo-NewsSource $e
        if ($null -eq $s -or -not $urls.Add($s.Url)) { continue }
        if (-not $ids.Add($s.Id)) { $s.Id = "f" + [Guid]::NewGuid().ToString("N").Substring(0, 10); [void]$ids.Add($s.Id) }
        $out += $s
        if ($out.Count -ge $Max) { break }
    }
    return @($out)
}

function Add-LegacyNewsFeeds {
    # the v5.7 text setting -> sources, added behind the existing ones (all switched on)
    param($Sources, [string]$Text)
    $new = @(@(ConvertTo-FeedList $Text) | ForEach-Object { [PSCustomObject]@{ Url = $_ } })
    return @(ConvertTo-NewsSourceList (@($Sources) + $new))
}

function Get-NewsSourceLabel {
    param($Source)
    if ($Source.Name) { return [string]$Source.Name }
    $h = (Get-ProviderOfUrl ([string]$Source.Url -replace '\{[a-z]+\}', 'x')) -replace '^RSS: ', ''
    return $h
}

function Get-CompanyShortName {
    # "ABB Ltd" -> "ABB", "NVIDIA Corporation" -> "NVIDIA" (for {name} in feed templates)
    param([string]$Name)
    $n = ([string]$Name).Trim()
    $n = $n -replace '(?i)[\s,]+(inc|corp|corporation|incorporated|ag|se|plc|nv|n\.v|sa|s\.a|co|ltd|limited|group|holding|holdings|company|class [abc])\.?(?=\s|,|$)', ''
    return $n.Trim(" ,.".ToCharArray())
}

function Get-NewsFeedRequests {
    # sources -> requests @(@{ Url; Id; Ticker }). {ticker} / {name} make one request per
    # ticker; the Ticker field then limits the list (comma separated), else it is a fixed ticker.
    param($Sources, [string[]]$Symbols = @(), [hashtable]$Names = @{}, [int]$MaxPerTemplate = 15, [int]$Max = 60)
    $out = @()
    foreach ($s in @($Sources)) {
        if ($null -eq $s -or -not $s.On) { continue }
        if ([string]$s.Url -notmatch '\{(ticker|name)\}') {
            $out += [PSCustomObject]@{ Url = [string]$s.Url; Id = [string]$s.Id; Ticker = [string]$s.Ticker }
        } else {
            $list = @(([string]$s.Ticker) -split '[,; ]+' | Where-Object { $_ })
            if ($list.Count -eq 0) { $list = @($Symbols) }
            foreach ($sym in @($list | Select-Object -First $MaxPerTemplate)) {
                $su = ([string]$sym).ToUpperInvariant()
                $nm = Get-CompanyShortName ([string]$Names[$su])
                if (-not $nm) { $nm = $su -replace '\..*$', '' }
                $u = ([string]$s.Url).Replace("{ticker}", [Uri]::EscapeDataString($su)).Replace("{name}", [Uri]::EscapeDataString($nm))
                $out += [PSCustomObject]@{ Url = $u; Id = [string]$s.Id; Ticker = $su }
            }
        }
    }
    return @($out | Select-Object -First $Max)
}

function Get-DueNewsSources {
    # sources whose own interval (or the global one, doubled while all markets are closed) is over
    param($Sources, [hashtable]$LastRun = @{}, [int]$GlobalMinutes = 15, [DateTime]$Now = (Get-Date), [bool]$AllClosed = $false, [switch]$Force)
    return @(@($Sources) | Where-Object {
        if ($null -eq $_ -or -not $_.On) { $false }
        elseif ($Force -or -not $LastRun.ContainsKey([string]$_.Id)) { $true }
        else {
            $m = if ([int]$_.Minutes -gt 0) { [int]$_.Minutes } else { Get-NewsPollMinutes -Minutes $GlobalMinutes -AllClosed $AllClosed }
            ($Now - [DateTime]$LastRun[[string]$_.Id]).TotalSeconds -ge ($m * 60 - 20)
        }
    })
}

function Get-FeedPauseSeconds {
    # per host after HTTP 429: 2, 4, 8 ... minutes, at most one hour
    param([int]$Level = 1)
    return [int][math]::Min(3600, 120 * [math]::Pow(2, [math]::Max(0, $Level - 1)))
}

# ---- matching headlines to tickers ----
function Get-NewsNameTerm {
    # company name -> @{ Word; Exact }: a long word matches in any case; a short
    # all-capitals name (ABB, SAP, OMV) only as written. $null = nothing usable.
    param([string]$Name)
    $long = Get-NewsNameKey $Name
    $first = @(([string]$Name) -split '[^\p{L}\p{Nd}]+' | Where-Object { $_ -and $_ -ne "The" })
    if ($first.Count -gt 0 -and $first[0] -cmatch '^[A-Z]{2,3}$' -and @("AG", "SA", "SE", "NV", "CO", "ETF", "US", "UK", "EU", "AI") -cnotcontains $first[0]) {
        return [PSCustomObject]@{ Word = [string]$first[0]; Exact = $true }
    }
    if ($long) { return [PSCustomObject]@{ Word = $long; Exact = $false } }
    return $null
}

function ConvertTo-NewsAliases {
    # lines "ABBN.SW = ABB, Asea Brown Boveri" -> @{ "ABBN.SW" = @("ABB", "Asea Brown Boveri") }
    param([string]$Text)
    $out = @{}
    foreach ($line in (([string]$Text) -split '[\r\n]+')) {
        $p = $line -split '=', 2
        if ($p.Count -ne 2) { continue }
        $sym = $p[0].Trim().ToUpperInvariant()
        $words = @($p[1] -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -ge 2 })
        if ($sym -and $words.Count -gt 0) { $out[$sym] = @(@($out[$sym]) + $words | Where-Object { $_ }) }
    }
    return $out
}

function Get-NewsMatchTerms {
    # symbols + company names + aliases -> @{ sym = @(@{ Word; Exact }) }
    param([string[]]$Symbols = @(), [hashtable]$Names = @{}, [hashtable]$Aliases = @{})
    $out = @{}
    foreach ($s in @(@($Symbols) + @($Aliases.Keys))) {
        if (-not $s) { continue }
        $u = ([string]$s).ToUpperInvariant()
        if ($out.ContainsKey($u)) { continue }
        $terms = @()
        $t = Get-NewsNameTerm ([string]$Names[$u])
        if ($null -ne $t) { $terms += $t }
        foreach ($a in @($Aliases[$u])) {
            if (-not $a) { continue }
            $exact = ([string]$a -cmatch '^[A-Z0-9.&]{2,4}$')
            $terms += [PSCustomObject]@{ Word = $(if ($exact) { [string]$a } else { ConvertTo-SearchKey $a }); Exact = $exact }
        }
        if ($terms.Count -gt 0) { $out[$u] = @($terms) }
    }
    return $out
}

function Find-NewsSymbols {
    # headline -> our tickers whose term appears as a whole word
    param([string]$Title, [hashtable]$Terms = @{})
    $folded = ConvertTo-SearchKey $Title
    return @(@(foreach ($s in $Terms.Keys) {
        foreach ($t in @($Terms[$s])) {
            $rx = '(?<![\p{L}\p{Nd}])' + [regex]::Escape([string]$t.Word) + '(?![\p{L}\p{Nd}])'
            $hit = if ($t.Exact) { [string]$Title -cmatch $rx } else { $folded -match $rx }
            if ($hit) { [string]$s; break }
        }
    }) | Sort-Object -Unique)
}

function ConvertTo-FeedItems {
    # parsed feed entries of one request -> feed items (source name, fixed ticker, matched tickers, max. age)
    param($Entries, $Source, [string]$Ticker = "", [hashtable]$Terms = @{}, [DateTime]$Now = (Get-Date))
    $age = if ([int]$Source.MaxAgeDays -gt 0) { [int]$Source.MaxAgeDays } else { 14 }
    $out = @()
    foreach ($n in @($Entries)) {
        if ($null -eq $n -or -not $n.Title) { continue }
        $t = if ($null -ne $n.Time) { [DateTime]$n.Time } else { [DateTime]::MinValue }
        if ($t -gt [DateTime]::MinValue -and ($Now - $t).TotalDays -gt $age) { continue }
        $syms = @(Find-NewsSymbols -Title ([string]$n.Title) -Terms $Terms)
        if ($Ticker) { $syms = @(@($syms) + $Ticker.ToUpperInvariant() | Sort-Object -Unique) }
        $out += [PSCustomObject]@{
            Key = (Get-NewsKey $n); Title = ([string]$n.Title).Trim()
            Publisher = $(if ($Source.Name) { [string]$Source.Name } else { [string]$n.Publisher })
            Link = [string]$n.Link; Time = $t; Syms = @($syms)
            Summary = [string]$n.Summary; Image = [string]$n.Image; Sources = @([string]$Source.Id); Also = @()
        }
    }
    return @($out)
}

function ConvertTo-PlainSummary {
    # description HTML -> one line of plain text
    param([string]$Html, [int]$Max = 500)
    if (-not $Html) { return "" }
    $t = $Html -replace '(?is)<(script|style)\b.*?</\1>', ' ' -replace '(?s)<[^>]*>', ' '
    $t = [System.Net.WebUtility]::HtmlDecode($t) -replace '\s+', ' '
    $t = $t.Trim()
    if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max - 1).TrimEnd() + [string][char]0x2026 }
    return $t
}

function Get-FeedItemImage {
    # media:thumbnail / media:content / image enclosure / first <img> of the text; https only
    param($Node, [string]$Html = "")
    if ($null -ne $Node) {
        foreach ($xp in @(".//*[local-name()='thumbnail']", ".//*[local-name()='content' and @url]", "*[local-name()='enclosure']", "*[local-name()='link' and @rel='enclosure']")) {
            foreach ($m in @($Node.SelectNodes($xp))) {
                $u = [string]$m.GetAttribute("url")
                if (-not $u) { $u = [string]$m.GetAttribute("href") }
                $type = [string]$m.GetAttribute("type") + " " + [string]$m.GetAttribute("medium")
                if ($u -match '^https://' -and ($m.LocalName -eq "thumbnail" -or $type -match 'image' -or $u -match '(?i)\.(jpe?g|png|gif)(\?|$)')) { return $u }
            }
        }
    }
    $mm = [regex]::Match([string]$Html, '(?is)<img\b[^>]*?\bsrc\s*=\s*["''](https://[^"'']+)["'']')
    if ($mm.Success) {
        $tag = $mm.Value
        if ($tag -notmatch '(?i)(width|height)\s*=\s*["'']?1(px)?["''\s>]') { return [System.Net.WebUtility]::HtmlDecode($mm.Groups[1].Value) }
    }
    return ""
}

# ---- what is shown ----
function Get-ItemSources {
    param($Item)
    return @(@($Item.Sources) | Where-Object { $_ })
}

function Select-NewsBySource {
    # an item shows when one of its sources is switched on and not hidden in the "Quellen" menu
    param($Items, [string[]]$Enabled = @(), [string[]]$Hidden = @())
    return @(@($Items) | Where-Object {
        if ($null -eq $_) { $false } else {
            $src = @(Get-ItemSources $_)
            if ($src.Count -eq 0) { $true } else { @($src | Where-Object { $Enabled -contains $_ -and $Hidden -notcontains $_ }).Count -gt 0 }
        }
    })
}

function Test-NewsWords {
    # the first of Words that headline or summary contains ("" = none)
    param($Item, [string[]]$Words = @())
    $text = ConvertTo-SearchKey (([string]$Item.Title) + " " + ([string]$Item.Summary))
    foreach ($w in @($Words)) { if ($w -and $text.Contains((ConvertTo-SearchKey $w))) { return [string]$w } }
    return ""
}

function Select-NewsByRules {
    # Include: only items with one of these words (empty = all). Exclude: hide items with one of these.
    param($Items, [string[]]$Include = @(), [string[]]$Exclude = @())
    $inc = @(@($Include) | Where-Object { $_ })
    $exc = @(@($Exclude) | Where-Object { $_ })
    return @(@($Items) | Where-Object { $null -ne $_ -and ($inc.Count -eq 0 -or (Test-NewsWords $_ $inc)) -and ($exc.Count -eq 0 -or -not (Test-NewsWords $_ $exc)) })
}

function Search-NewsItems {
    # every word of the query must appear in headline, summary, source or tickers
    param($Items, [string]$Query = "")
    $words = @((ConvertTo-SearchKey $Query) -split '\s+' | Where-Object { $_ })
    return @(@($Items) | Where-Object {
        if ($null -eq $_) { $false } else {
            $text = ConvertTo-SearchKey (([string]$_.Title) + " " + ([string]$_.Summary) + " " + ([string]$_.Publisher) + " " + (@($_.Syms) -join " "))
            $all = $true
            foreach ($w in $words) { if (-not $text.Contains($w)) { $all = $false; break } }
            $all
        }
    })
}

function Merge-SimilarNews {
    # near-identical headlines within Hours become one entry (the newest). Needs 4+ words,
    # a word overlap of at least Threshold and the same numbers (Q2 is not Q3).
    # The result are copies; Keys lists every merged item, Also the other sources.
    param($Items, [double]$Threshold = 0.65, [int]$Hours = 48)
    $groups = New-Object System.Collections.Generic.List[object]
    $index = @{}     # word -> numbers of the groups that contain it
    foreach ($n in @($Items)) {
        if ($null -eq $n) { continue }
        # plain loops: this runs for every row of the list
        $set = New-Object System.Collections.Generic.SortedSet[string]([StringComparer]::Ordinal)
        $numSet = New-Object System.Collections.Generic.SortedSet[string]([StringComparer]::Ordinal)
        foreach ($w in [regex]::Split((ConvertTo-SearchKey ([string]$n.Title)), '[^\p{L}\p{Nd}]+')) {
            if (-not $w) { continue }
            if ($w -match '\d') { [void]$set.Add($w); [void]$numSet.Add($w) } elseif ($w.Length -ge 3) { [void]$set.Add($w) }
        }
        $words = @($set)
        $nums = @($numSet) -join ","
        $target = $null
        if ($words.Count -ge 4) {
            $shared = @{}
            foreach ($w in $words) { foreach ($gi in $index[$w]) { $shared[$gi] = 1 + [int]$shared[$gi] } }
            # enough common words at all? (overlap >= Threshold needs at least this many)
            $need = [math]::Ceiling($Threshold * $words.Count)
            $candidates = New-Object System.Collections.Generic.List[int]
            foreach ($key in $shared.Keys) { if ($shared[$key] -ge $need) { $candidates.Add($key) } }
            $candidates.Sort()
            foreach ($gi in $candidates) {
                $g = $groups[$gi]
                if ($g.Nums -ne $nums) { continue }
                if ([math]::Abs(([DateTime]$g.Item.Time - [DateTime]$n.Time).TotalHours) -gt $Hours) { continue }
                $union = $g.Words.Count + $words.Count - $shared[$gi]
                if ($union -gt 0 -and ($shared[$gi] / [double]$union) -ge $Threshold) { $target = $g; break }
            }
        }
        if ($null -eq $target) {
            $copy = [PSCustomObject]@{ Key = [string]$n.Key; Title = [string]$n.Title; Publisher = [string]$n.Publisher; Link = [string]$n.Link; Time = [DateTime]$n.Time
                Syms = @($n.Syms); Summary = [string]$n.Summary; Image = [string]$n.Image; Sources = @(Get-ItemSources $n); Also = @(); Keys = @([string]$n.Key) }
            if ($words.Count -ge 4) {
                foreach ($w in $words) { if (-not $index.ContainsKey($w)) { $index[$w] = New-Object System.Collections.Generic.List[int] }; $index[$w].Add($groups.Count) }
            }
            $groups.Add([PSCustomObject]@{ Item = $copy; Words = $words; Nums = $nums })
        } else {
            $m = $target.Item
            $m.Keys = @($m.Keys) + [string]$n.Key
            $m.Syms = @(@($m.Syms) + @($n.Syms) | Where-Object { $_ } | Sort-Object -Unique)
            $m.Sources = @(@($m.Sources) + @(Get-ItemSources $n) | Where-Object { $_ } | Sort-Object -Unique)
            if ([string]$n.Publisher -and [string]$n.Publisher -ne $m.Publisher -and @($m.Also) -notcontains [string]$n.Publisher) { $m.Also = @($m.Also) + [string]$n.Publisher }
            if (-not $m.Summary) { $m.Summary = [string]$n.Summary }
            if (-not $m.Image) { $m.Image = [string]$n.Image }
        }
    }
    return @($groups | ForEach-Object { $_.Item })
}

# ---- history and saved items (news.json) ----
function ConvertTo-NewsRecord {
    param($Item)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    return [PSCustomObject]@{ Key = [string]$Item.Key; Title = [string]$Item.Title; Publisher = [string]$Item.Publisher; Link = [string]$Item.Link
        Time = ([DateTime]$Item.Time).ToString("yyyy-MM-ddTHH:mm:ss", $inv); Syms = @(@($Item.Syms) | Where-Object { $_ })
        Summary = [string]$Item.Summary; Image = [string]$Item.Image; Sources = @(Get-ItemSources $Item) }
}

function ConvertFrom-NewsRecord {
    param($Record)
    if ($null -eq $Record -or -not $Record.Title) { return $null }
    $t = [DateTime]::MinValue
    if ($Record.Time -is [DateTime]) { $t = [DateTime]$Record.Time }
    elseif ($Record.Time) { [void][DateTime]::TryParse([string]$Record.Time, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$t) }
    return [PSCustomObject]@{ Key = [string]$Record.Key; Title = [string]$Record.Title; Publisher = [string]$Record.Publisher
        Link = $(if ([string]$Record.Link -match '^https?://') { [string]$Record.Link } else { "" }); Time = $t
        Syms = @(@($Record.Syms) | Where-Object { $_ }); Summary = [string]$Record.Summary; Image = [string]$Record.Image
        Sources = @(@($Record.Sources) | Where-Object { $_ }); Also = @() }
}

function Update-NewsHistory {
    # history + fresh items -> one list by key (fresh wins; tickers and sources are joined), newest first
    param($History, $Fresh, [int]$MaxDays = 14, [int]$Max = 500, [DateTime]$Now = (Get-Date))
    $map = @{}
    foreach ($n in @($History)) { if ($null -ne $n) { $map[[string]$n.Key] = $n } }
    $done = New-Object System.Collections.Generic.HashSet[string]
    foreach ($n in @($Fresh)) {
        if ($null -eq $n) { continue }
        $k = [string]$n.Key
        $old = $map[$k]
        if ($null -ne $old) {
            $n.Syms = @(@($n.Syms) + @($old.Syms) | Where-Object { $_ } | Sort-Object -Unique)
            $n.Sources = @(@(Get-ItemSources $n) + @(Get-ItemSources $old) | Sort-Object -Unique)
            # an item without a date keeps the time it was first seen with
            if ([DateTime]$n.Time -eq [DateTime]::MinValue) { $n.Time = $old.Time }
        }
        # never seen and no date: it counts from now (and expires like the others)
        if ([DateTime]$n.Time -eq [DateTime]::MinValue) { $n.Time = $Now }
        $map[$k] = $n
    }
    $list = @($map.Values | Where-Object { [DateTime]$_.Time -eq [DateTime]::MinValue -or ($Now - [DateTime]$_.Time).TotalDays -le $MaxDays })
    return @($list | Sort-Object -Property @{ Expression = { [DateTime]$_.Time }; Descending = $true }, @{ Expression = { [string]$_.Title }; Descending = $false } | Select-Object -First $Max)
}

function Test-NewsUnread {
    # read / unread marks win over the "seen since" time
    param($Item, [DateTime]$Since, $ReadKeys = $null, $UnreadKeys = $null)
    $keys = @(@($Item.Keys) | Where-Object { $_ })
    if ($keys.Count -eq 0) { $keys = @([string]$Item.Key) }
    if ($null -ne $UnreadKeys) { foreach ($k in $keys) { if ($UnreadKeys.Contains([string]$k)) { return $true } } }
    if ($null -ne $ReadKeys -and $ReadKeys.Contains([string]$keys[0])) { return $false }
    return ([DateTime]$Item.Time -gt $Since)
}

function ConvertTo-NewsCsv {
    # saved items -> CSV (semicolon); cells that a spreadsheet would run as a formula are prefixed
    param($Items)
    $cell = { param([string]$v) if ($v -match '^[=+\-@\t\r]') { $v = "'" + $v }; '"' + $v.Replace('"', '""') + '"' }
    $lines = @('"Zeit";"Quelle";"Ticker";"Titel";"Link"')
    foreach ($n in @($Items)) {
        if ($null -eq $n) { continue }
        $time = if ([DateTime]$n.Time -gt [DateTime]::MinValue) { ([DateTime]$n.Time).ToString("yyyy-MM-dd HH:mm") } else { "" }
        $lines += @((& $cell $time), (& $cell ([string]$n.Publisher)), (& $cell (@($n.Syms) -join " ")), (& $cell ([string]$n.Title)), (& $cell ([string]$n.Link))) -join ";"
    }
    return ($lines -join "`r`n") + "`r`n"
}

function Get-NewsChartMarks {
    # news of one ticker -> @(@{ Index; Count; Text }) on the bars of a chart series
    param($Items, [string]$Symbol, [long[]]$BarTsMs, [long]$MaxGapMs)
    $su = ([string]$Symbol).ToUpperInvariant()
    $by = @{}
    if ($null -eq $BarTsMs -or $BarTsMs.Count -lt 2) { return @() }
    foreach ($n in @($Items)) {
        if ($null -eq $n -or [DateTime]$n.Time -eq [DateTime]::MinValue -or @($n.Syms) -notcontains $su) { continue }
        $ms = ([DateTimeOffset]([DateTime]$n.Time)).ToUnixTimeMilliseconds()
        if ($ms -lt $BarTsMs[0] -or $ms -gt ($BarTsMs[$BarTsMs.Count - 1] + $MaxGapMs)) { continue }
        $i = [Array]::BinarySearch($BarTsMs, [long]$ms)
        if ($i -lt 0) { $i = (-bnot $i) - 1 }
        if ($i -lt 0 -or ($ms - $BarTsMs[$i]) -gt $MaxGapMs) { continue }
        if (-not $by.ContainsKey($i)) { $by[$i] = @() }
        $by[$i] += $n
    }
    return @($by.Keys | Sort-Object | ForEach-Object {
        $list = @($by[$_])
        $text = @($list | Select-Object -First 3 | ForEach-Object { "{0} ({1})" -f $_.Title, $_.Publisher }) -join "`r`n"
        if ($list.Count -gt 3) { $text += "`r`n+" + ($list.Count - 3) }
        [PSCustomObject]@{ Index = [int]$_; Count = $list.Count; Text = $text }
    })
}

# ---- feed discovery and OPML ----
function Find-FeedLinks {
    # web page -> RSS / Atom addresses from its <link rel="alternate"> tags
    param([string]$Html, [string]$BaseUrl)
    $base = $null
    if (-not [Uri]::TryCreate([string]$BaseUrl, [UriKind]::Absolute, [ref]$base)) { return @() }
    $out = @()
    foreach ($m in [regex]::Matches([string]$Html, '(?is)<link\b[^>]*>')) {
        $tag = $m.Value
        if ($tag -notmatch '(?i)type\s*=\s*["'']application/(rss|atom)\+xml["'']') { continue }
        $h = [regex]::Match($tag, '(?is)\bhref\s*=\s*["'']([^"'']+)["'']')
        if (-not $h.Success) { continue }
        $abs = $null
        if ([Uri]::TryCreate($base, [System.Net.WebUtility]::HtmlDecode($h.Groups[1].Value), [ref]$abs) -and $abs.Scheme -match '^https?$') { $out += $abs.AbsoluteUri }
    }
    return @($out | Select-Object -Unique)
}

function ConvertTo-Opml {
    param($Sources)
    $esc = { param($v) [System.Security.SecurityElement]::Escape([string]$v) }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
    [void]$sb.AppendLine('<opml version="2.0"><head><title>TerminalWidget Feeds</title></head><body>')
    foreach ($s in @($Sources)) {
        if ($null -eq $s) { continue }
        [void]$sb.AppendLine(('  <outline type="rss" text="{0}" xmlUrl="{1}" category="{2}"/>' -f (& $esc (Get-NewsSourceLabel $s)), (& $esc $s.Url), (& $esc $s.Group)))
    }
    [void]$sb.AppendLine('</body></opml>')
    return $sb.ToString()
}

function ConvertFrom-Opml {
    # OPML -> sources (folder name or category = group); DTDs are not processed
    param([string]$Text)
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    $set = New-Object System.Xml.XmlReaderSettings
    $set.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $set.XmlResolver = $null
    try {
        $rd = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader(([string]$Text).TrimStart([char]0xFEFF).Trim())), $set)
        $doc.Load($rd); $rd.Close()
    } catch { return @() }
    $rows = @()
    foreach ($o in @($doc.SelectNodes("//*[local-name()='outline'][@xmlUrl]"))) {
        $group = [string]$o.GetAttribute("category")
        if (-not $group -and $o.ParentNode.LocalName -eq "outline") { $group = [string]$o.ParentNode.GetAttribute("text") }
        $name = [string]$o.GetAttribute("text")
        if (-not $name) { $name = [string]$o.GetAttribute("title") }
        $rows += [PSCustomObject]@{ Url = [string]$o.GetAttribute("xmlUrl"); Name = $name; Group = $group }
    }
    return @(ConvertTo-NewsSourceList $rows)
}

# ==============================================================================
# v8.0: price axis, colour rules, own themes, shortcuts, ordering, alerts,
#       notices, calendar export, summary, goals, risk figures, watchlist CSV
# ==============================================================================
function Get-ScaledPriceRange {
    # Visible price range after the user scrolled the price axis.
    # Scale 1 / Shift 0 = automatic; Scale > 1 shows a wider range; Shift is a
    # share of the automatic range (positive = higher prices).
    param([double]$MinP, [double]$SpanP, [bool]$Log = $false, [double]$Scale = 1.0, [double]$Shift = 0.0)
    $sc = [math]::Min(8.0, [math]::Max(0.1, $Scale))
    $sh = [math]::Min(4.0, [math]::Max(-4.0, $Shift))
    $lo = Get-PriceFromFrac (0.5 + $sh - $sc / 2.0) $MinP $SpanP $Log
    $hi = Get-PriceFromFrac (0.5 + $sh + $sc / 2.0) $MinP $SpanP $Log
    return @{ Min = $lo; Span = ($hi - $lo) }
}

# ---- colour rules ------------------------------------------------------------
function Get-ColorRuleFields {
    return [ordered]@{
        "DayPct"    = "Tagesänderung %"
        "DayAbsPct" = "Tagesänderung % (egal welche Richtung)"
        "Near"      = "Abstand zu Alarm / Zielkurs %"
        "Rsi"       = "RSI (1h)"
        "TotalPct"  = "Gewinn / Verlust zum Einstand %"
        "High52Pct" = "Abstand zum 52W-Hoch %"
    }
}

function New-ColorRule {
    param([string]$Id, [string]$Name, [string]$Field, [string]$Op, [double]$Value, [string]$Color, [bool]$On = $false)
    return [PSCustomObject]@{ Id = $Id; Name = $Name; On = $On; Field = $Field; Op = $Op; Value = $Value; Color = $Color }
}

function Get-DefaultColorRules {
    # ready-made rules, all off until the user switches them on
    return @(
        (New-ColorRule "bigmove" "Große Tagesbewegung" "DayAbsPct" ">=" 3 "#F59E0B")
        (New-ColorRule "near" "Nahe Alarm oder Zielkurs" "Near" "<=" 2 "#A855F7")
        (New-ColorRule "rsihigh" "RSI überkauft" "Rsi" ">=" 70 "#F43F5E")
        (New-ColorRule "rsilow" "RSI überverkauft" "Rsi" "<=" 30 "#10B981")
        (New-ColorRule "gain" "Position im Gewinn" "TotalPct" ">=" 10 "#10B981")
        (New-ColorRule "loss" "Position im Verlust" "TotalPct" "<=" -10 "#F43F5E")
    )
}

function Get-MatchingColorRule {
    # First switched-on rule that matches the facts of one row, else $null.
    # Facts: hashtable field -> number; missing / NaN values never match.
    param($Rules, [hashtable]$Facts)
    foreach ($r in @($Rules)) {
        if ($null -eq $r -or -not [bool]$r.On) { continue }
        $f = [string]$r.Field
        if (-not $Facts.ContainsKey($f) -or $null -eq $Facts[$f]) { continue }
        $v = [double]$Facts[$f]
        if ([double]::IsNaN($v)) { continue }
        $t = [double]$r.Value
        if (([string]$r.Op -eq ">=" -and $v -ge $t) -or ([string]$r.Op -eq "<=" -and $v -le $t)) { return $r }
    }
    return $null
}

function Get-NearestDistancePct {
    # smallest distance in % between the price and any of the levels (> 0); NaN if none
    param([double]$Price, [double[]]$Levels)
    $best = [double]::NaN
    if ($Price -le 0) { return $best }
    foreach ($l in @($Levels)) {
        if ($null -eq $l -or $l -le 0) { continue }
        $d = [math]::Abs($l / $Price - 1.0) * 100.0
        if ([double]::IsNaN($best) -or $d -lt $best) { $best = $d }
    }
    return $best
}

# ---- own themes --------------------------------------------------------------
function Get-ThemeColorKeys {
    return [ordered]@{
        HeaderBg = "Kopfzeile"; BodyBg = "Hintergrund"; PanelBg = "Flächen"; Card = "Karten und Listen"; Input = "Eingabefelder"
        Hover = "Maus darüber"; Grid = "Gitterlinien"; Border = "Rahmen"; Text = "Schrift"; Muted = "Schrift gedämpft"; Accent = "Akzent"; Warn = "Hinweis"
    }
}

function ConvertFrom-ThemeData {
    # Theme object (own config or imported file) -> clean @{ Name; Base; Colors }
    # or $null. Unknown keys and broken colours are dropped, not guessed.
    param($Data)
    if ($null -eq $Data) { return $null }
    $name = ([string]$Data.Name).Trim()
    if (-not $name -or $name.Length -gt 30 -or @(Get-ThemeNames) -contains $name) { return $null }
    $base = [string]$Data.Base
    if (@(Get-ThemeNames) -notcontains $base) { $base = "Dark" }
    $colors = [ordered]@{}
    if ($null -ne $Data.Colors) {
        foreach ($k in (Get-ThemeColorKeys).Keys) {
            $p = $Data.Colors.PSObject.Properties[$k]
            $v = if ($null -ne $p) { [string]$p.Value } elseif ($Data.Colors -is [System.Collections.IDictionary]) { [string]$Data.Colors[$k] } else { "" }
            $rgb = ConvertFrom-HexColor $v
            if ($null -ne $rgb) { $colors[$k] = ConvertTo-HexColor $rgb[0] $rgb[1] $rgb[2] }
        }
    }
    return [PSCustomObject]@{ Name = $name; Base = $base; Colors = [PSCustomObject]$colors }
}

# ---- own shortcuts -----------------------------------------------------------
function ConvertTo-ShortcutText {
    # "ctrl + shift+a" -> "Strg+Shift+A"; "" when not allowed.
    # Allowed: optional Strg / Alt / Shift plus A-Z, 0-9 or F1-F12.
    param([string]$Text)
    $parts = @(([string]$Text) -split '\+' | ForEach-Object { $_.Trim().ToUpperInvariant() } | Where-Object { $_ })
    if ($parts.Count -eq 0) { return "" }
    $key = $parts[$parts.Count - 1]
    if ($key -notmatch '^([A-Z]|[0-9]|F([1-9]|1[0-2]))$') { return "" }
    $c = $false; $a = $false; $s = $false
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        switch -regex ($parts[$i]) {
            '^(CTRL|STRG|CONTROL)$' { $c = $true }
            '^ALT$'                 { $a = $true }
            '^(SHIFT|UMSCHALT)$'    { $s = $true }
            default                 { return "" }
        }
    }
    $out = @()
    if ($c) { $out += "Strg" }
    if ($a) { $out += "Alt" }
    if ($s) { $out += "Shift" }
    $out += $key
    $t = $out -join "+"
    # keys the widget or Windows need
    if ($t -in @("Strg+C", "Strg+V", "Strg+X", "Strg+Z", "Strg+Y", "Strg+A", "Strg+K", "Alt+F4", "F10")) { return "" }
    # plain digits switch the time range
    if ($t -match '^[0-9]$') { return "" }
    return $t
}

function Get-KeyShortcutText {
    # the same text form for a pressed key
    param([string]$KeyName, [bool]$Ctrl, [bool]$Alt, [bool]$Shift)
    $k = [string]$KeyName
    if ($k -match '^D([0-9])$') { $k = $Matches[1] }
    if ($k -notmatch '^([A-Z]|[0-9]|F([1-9]|1[0-2]))$') { return "" }
    $p = @()
    if ($Ctrl) { $p += "Strg" }
    if ($Alt) { $p += "Alt" }
    if ($Shift) { $p += "Shift" }
    $p += $k.ToUpperInvariant()
    return ($p -join "+")
}

function Select-OrderedIds {
    # Chosen ids in the chosen order (unknown ones dropped, no doubles);
    # an empty choice means all available in their normal order
    param([string[]]$Available, [string[]]$Chosen, [switch]$EmptyIsNone)
    $out = @()
    foreach ($c in @($Chosen)) { if ($c -and @($Available) -contains $c -and $out -notcontains $c) { $out += $c } }
    if ($out.Count -eq 0 -and -not $EmptyIsNone) { return @($Available) }
    return $out
}

# ---- alerts: two conditions, templates ---------------------------------------
function Test-AlertCombination {
    # "" when the two conditions can be combined, else the reason
    param([string]$First, [string]$Second)
    $a = Get-AlertKind $First; $b = Get-AlertKind $Second
    if ($a -eq "TREND" -or $b -eq "TREND") { return "Trendlinien-Alarme lassen sich nicht kombinieren." }
    if ($b -eq "TRAIL") { return "Trailing % geht nur als erste Bedingung." }
    if ((Test-PortfolioAlertKind $a) -ne (Test-PortfolioAlertKind $b)) { return "Depot-Bedingungen lassen sich nur mit Depot-Bedingungen kombinieren." }
    if ($First -eq $Second) { return "Zwei gleiche Bedingungen ergeben keinen Sinn." }
    return ""
}

function Join-AlertEvaluations {
    # both conditions must be true; no data for one = no data at all
    param($First, $Second)
    $res = @{ Ok = ($First.Ok -and $Second.Ok); Value = $First.Value; Met = $false; Text = ""; Peak = $First.Peak }
    if ($res.Ok) {
        $res.Met = ($First.Met -and $Second.Met)
        $res.Text = "{0}  UND  {1}" -f $First.Text, $Second.Text
    }
    return $res
}

function Get-TemplateConditions {
    # conditions that mean the same thing for every ticker (no absolute prices)
    return @("Tag% >=", "Tag% <=", "RSI >=", "RSI <=", "> SMA", "< SMA", "Trailing %", "EK% >=", "EK% <=", "52W Hoch", "52W Tief", "Volumen x")
}

function Test-AlertValue {
    # "" when the number fits the condition, else the hint text
    param([string]$Condition, [double]$Value)
    $kind = Get-AlertKind $Condition
    $bad = ($kind -in @("PRICE", "PFVAL", "VOL") -and $Value -le 0) -or
           ($kind -in @("RSI", "TRAIL") -and ($Value -le 0 -or $Value -ge 100)) -or
           ($kind -in @("HIGH52", "LOW52") -and ($Value -lt 0 -or $Value -gt 50))
    if ($bad) { return (Get-AlertTargetHint $Condition) }
    return ""
}

function Get-TemplateTargets {
    # Tickers a template gets an alert for: without an equal alert already;
    # EK% conditions only for tickers with a position
    param([string[]]$Symbols, $Alerts, [string]$Condition, [double]$Value, [string]$Condition2 = "", [double]$Value2 = 0, [string[]]$Held = @())
    $out = @()
    $needsPos = ((Get-AlertKind $Condition) -eq "EKPCT" -or ($Condition2 -and (Get-AlertKind $Condition2) -eq "EKPCT"))
    foreach ($s0 in @($Symbols)) {
        $s = ([string]$s0).ToUpperInvariant()
        if (-not $s -or $out -contains $s) { continue }
        if ($needsPos -and @($Held) -notcontains $s) { continue }
        $dup = @($Alerts | Where-Object { $null -ne $_ -and ([string]$_.Ticker).ToUpperInvariant() -eq $s -and [string]$_.Condition -eq $Condition -and
            [math]::Abs([double]$_.TargetPrice - $Value) -lt 1e-9 -and [string]$_.Condition2 -eq $Condition2 -and
            (-not $Condition2 -or [math]::Abs([double]$_.Target2 - $Value2) -lt 1e-9) })
        if ($dup.Count -eq 0) { $out += $s }
    }
    return $out
}

# ---- notices ahead of dates --------------------------------------------------
function Get-DueDateNotices {
    # Earnings / ex-dividend notices that are due now: 0..lead days ahead and
    # not sent yet for that date. A lead of -1 switches a kind off.
    param([hashtable]$Events, [string[]]$Symbols, [int]$EarningsLead = 1, [int]$ExDivLead = -1, [string]$AsOf = "")
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $now = if ($AsOf) { [DateTime]::ParseExact($AsOf, "yyyy-MM-dd", $inv) } else { (Get-Date).Date }
    $out = @()
    foreach ($s0 in @($Symbols)) {
        $s = ([string]$s0).ToUpperInvariant()
        $e = $Events[$s]
        if ($null -eq $e) { continue }
        foreach ($k in @(@("Earnings", "EarningsDate", "NotifiedEarnings", $EarningsLead), @("ExDiv", "ExDividendDate", "NotifiedExDiv", $ExDivLead))) {
            $lead = [int]$k[3]
            if ($lead -lt 0) { continue }
            $v = [string]$e.($k[1])
            if (-not $v -or [string]$e.($k[2]) -eq $v) { continue }
            $d = [DateTime]::MinValue
            if (-not [DateTime]::TryParseExact($v, "yyyy-MM-dd", $inv, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { continue }
            $days = [int]($d - $now).TotalDays
            if ($days -lt 0 -or $days -gt $lead) { continue }
            $out += [PSCustomObject]@{ Ticker = $s; Kind = $k[0]; Date = $v; Days = $days; Flag = $k[2] }
        }
    }
    return $out
}

# ---- calendar export (.ics) --------------------------------------------------
function ConvertTo-IcsText {
    # Events @(@{ Date; Ticker; Kind }) -> iCalendar text with all-day entries
    param($Events, [DateTime]$Now = (Get-Date))
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $esc = { param([string]$t) $t.Replace('\', '\\').Replace(';', '\;').Replace(',', '\,').Replace("`r", "").Replace("`n", '\n') }
    $fold = {
        # lines are limited to 75 bytes; continuation lines start with a space
        param([string]$line)
        $parts = New-Object System.Collections.Generic.List[string]
        $cur = ""; $bytes = 0
        foreach ($ch in $line.ToCharArray()) {
            $b = [System.Text.Encoding]::UTF8.GetByteCount([string]$ch)
            if ($bytes + $b -gt 73) { $parts.Add($cur); $cur = " "; $bytes = 1 }
            $cur += $ch; $bytes += $b
        }
        $parts.Add($cur)
        return ($parts.ToArray() -join "`r`n")
    }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($h in @("BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//TerminalWidget//Termine//DE", "CALSCALE:GREGORIAN")) { $lines.Add($h) }
    $stamp = $Now.ToUniversalTime().ToString("yyyyMMdd'T'HHmmss'Z'", $inv)
    foreach ($e in @($Events)) {
        if ($null -eq $e) { continue }
        $d = [DateTime]::MinValue
        if (-not [DateTime]::TryParseExact([string]$e.Date, "yyyy-MM-dd", $inv, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { continue }
        $uid = (("{0}-{1}-{2}" -f $e.Date, $e.Ticker, $e.Kind) -replace '[^A-Za-z0-9\-]', '') + "@terminalwidget"
        $lines.Add("BEGIN:VEVENT")
        $lines.Add("UID:$uid")
        $lines.Add("DTSTAMP:$stamp")
        $lines.Add("DTSTART;VALUE=DATE:" + $d.ToString("yyyyMMdd", $inv))
        $lines.Add("DTEND;VALUE=DATE:" + $d.AddDays(1).ToString("yyyyMMdd", $inv))
        $lines.Add((& $fold ("SUMMARY:" + (& $esc ("{0}: {1}" -f $e.Ticker, $e.Kind)))))
        $lines.Add("TRANSP:TRANSPARENT")
        $lines.Add("END:VEVENT")
    }
    $lines.Add("END:VCALENDAR")
    return (($lines.ToArray() -join "`r`n") + "`r`n")
}

# ---- summary -----------------------------------------------------------------
function Get-ReferenceClose {
    # last daily close on or before (AsOf - DaysBack); NaN when the history does
    # not reach back that far or the match is more than 10 days older
    param([string[]]$Dates, [double[]]$Closes, [int]$DaysBack = 7, [string]$AsOf = "")
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $now = if ($AsOf) { [DateTime]::ParseExact($AsOf, "yyyy-MM-dd", $inv) } else { (Get-Date).Date }
    $limit = $now.AddDays(-$DaysBack).ToString("yyyy-MM-dd")
    $oldest = $now.AddDays(-$DaysBack - 10).ToString("yyyy-MM-dd")
    $n = [math]::Min(@($Dates).Count, @($Closes).Count)
    for ($i = $n - 1; $i -ge 0; $i--) {
        if ([string]::CompareOrdinal([string]$Dates[$i], $limit) -gt 0) { continue }
        if ([string]::CompareOrdinal([string]$Dates[$i], $oldest) -lt 0) { break }
        if ($Closes[$i] -gt 0) { return [double]$Closes[$i] }
    }
    return [double]::NaN
}

function Select-SummaryMovers {
    # items @{ Ticker; Pct } -> the Top rising and the Top falling ones
    param($Items, [int]$Top = 3)
    $list = @($Items | Where-Object { $null -ne $_ -and -not [double]::IsNaN([double]$_.Pct) })
    return [PSCustomObject]@{
        Up   = @($list | Where-Object { [double]$_.Pct -gt 0 } | Sort-Object -Property @{ Expression = { [double]$_.Pct }; Descending = $true } | Select-Object -First $Top)
        Down = @($list | Where-Object { [double]$_.Pct -lt 0 } | Sort-Object -Property @{ Expression = { [double]$_.Pct } } | Select-Object -First $Top)
    }
}

function Test-SummaryDue {
    # show the summary window by itself? Daily = once per day, Weekly = once per
    # calendar week (Monday-based)
    param([string]$Mode, [string]$LastShown, [DateTime]$Now = (Get-Date))
    if ($Mode -notin @("Daily", "Weekly")) { return $false }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $last = [DateTime]::MinValue
    if (-not [DateTime]::TryParseExact([string]$LastShown, "yyyy-MM-dd", $inv, [System.Globalization.DateTimeStyles]::None, [ref]$last)) { return $true }
    if ($Mode -eq "Daily") { return ($last.Date -lt $Now.Date) }
    $monday = $Now.Date.AddDays(-(([int]$Now.DayOfWeek + 6) % 7))
    return ($last.Date -lt $monday)
}

# ---- fees and interest, goals ------------------------------------------------
function Get-FeeOverview {
    # One depot -> per year: order fees (bookings), account fees and interest
    # (cash account), converted to Base with the rate of the booking day.
    # Approx = some rate had to be taken from today.
    param($Transactions, $CashEntries, [string]$Base = "EUR", [hashtable]$History = @{}, [hashtable]$FallbackFromEur = @{})
    $years = @{}
    $row = {
        param([string]$y)
        if (-not $years.ContainsKey($y)) { $years[$y] = [PSCustomObject]@{ Year = $y; OrderFees = 0.0; AccountFees = 0.0; Interest = 0.0; Orders = 0; Approx = $false } }
        return $years[$y]
    }
    $add = {
        param($r, [string]$field, [double]$amount, [string]$cur, [string]$date)
        $c = Get-NormalizedCurrencyCode $cur
        if (-not $c) { $c = $Base }
        $cv = Convert-AmountOnDate -Amount $amount -From $c -To $Base -Date $date -History $History -FallbackFromEur $FallbackFromEur
        if ([bool]$cv.Approx -and $c -ne $Base) { $r.Approx = $true }
        $r.$field += [double]$cv.Value
    }
    foreach ($t in @($Transactions)) {
        if ($null -eq $t -or ([string]$t.Date).Length -lt 4) { continue }
        $fee = [double]$t.Fee
        $r = & $row ([string]$t.Date).Substring(0, 4)
        if ([string]$t.Type -in @("Kauf", "Verkauf")) { $r.Orders++ }
        if ($fee -ne 0) { & $add $r "OrderFees" $fee ([string]$t.Currency) ([string]$t.Date) }
    }
    foreach ($e in @($CashEntries)) {
        if ($null -eq $e -or ([string]$e.Date).Length -lt 4) { continue }
        $kind = [string]$e.Kind
        if ($kind -ne "Gebühr" -and $kind -ne "Zinsen") { continue }
        $r = & $row ([string]$e.Date).Substring(0, 4)
        # account fees are stored negative: shown as a positive cost
        if ($kind -eq "Gebühr") { & $add $r "AccountFees" (-[double]$e.Amount) ([string]$e.Currency) ([string]$e.Date) }
        else { & $add $r "Interest" ([double]$e.Amount) ([string]$e.Currency) ([string]$e.Date) }
    }
    return @($years.Values | Sort-Object -Property @{ Expression = { $_.Year }; Descending = $true })
}

# ---- broker per booking (v10.4) ----------------------------------------------
function Get-BrokerNames {
    # all brokers used in the bookings, once each (case does not matter), sorted
    param($Transactions)
    $seen = @{}
    foreach ($t in @($Transactions)) {
        if ($null -eq $t) { continue }
        $b = ([string]$t.Broker).Trim()
        if ($b -and -not $seen.ContainsKey($b)) { $seen[$b] = $b }
    }
    return @($seen.Values | Sort-Object)
}

function Get-LastBroker {
    # broker of the newest booking of this ticker; without one, of the newest booking at all
    param($Transactions, [string]$Ticker = "")
    $with = @(@($Transactions) | Where-Object { $null -ne $_ -and ([string]$_.Broker).Trim() })
    if ($with.Count -eq 0) { return "" }
    $own = @($with | Where-Object { [string]$_.Ticker -eq $Ticker })
    $pool = if ($own.Count -gt 0) { $own } else { $with }
    $best = $pool[0]
    foreach ($t in $pool) { if ([string]::CompareOrdinal([string]$t.Date, [string]$best.Date) -ge 0) { $best = $t } }
    return ([string]$best.Broker).Trim()
}

function Test-BookingMatch {
    # every word must occur in ticker, note, broker, type or date (ISO or German)
    param($Booking, [string]$Search = "")
    if (-not ([string]$Search).Trim()) { return $true }
    $d = [string]$Booking.Date
    $de = if ($d -match '^(\d{4})-(\d{2})-(\d{2})') { "{0}.{1}.{2}" -f $Matches[3], $Matches[2], $Matches[1] } else { "" }
    $hay = (@([string]$Booking.Ticker, [string]$Booking.Note, [string]$Booking.Broker, [string]$Booking.Type, $d, $de) -join " ").ToLowerInvariant()
    foreach ($w in @($Search.Trim().ToLowerInvariant() -split '\s+')) { if (-not $hay.Contains($w)) { return $false } }
    return $true
}

function Set-BookingBroker {
    # sets the broker of the bookings with these ids -> number of changed bookings
    param($Transactions, [string[]]$Ids, [string]$Broker = "")
    $want = @{}
    foreach ($i in @($Ids)) { if ($i) { $want[$i] = $true } }
    $name = ([string]$Broker).Trim()
    $n = 0
    foreach ($t in @($Transactions)) {
        if ($null -eq $t -or -not $want.ContainsKey([string]$t.Id)) { continue }
        if ([string]$t.Broker -cne $name) { $t.Broker = $name; $n++ }
    }
    return $n
}

function Get-BrokerFeeOverview {
    # buys and sells per year and broker: orders, volume, order fees, fee in
    # percent of the volume. Dividends are left out (their "fee" holds taxes).
    param($Transactions, [string]$Base = "EUR", [hashtable]$History = @{}, [hashtable]$FallbackFromEur = @{})
    $rows = @{}
    foreach ($t in @($Transactions)) {
        if ($null -eq $t -or ([string]$t.Date).Length -lt 4) { continue }
        if ([string]$t.Type -notin @("Kauf", "Verkauf")) { continue }
        $year = ([string]$t.Date).Substring(0, 4)
        $name = ([string]$t.Broker).Trim()
        $key = $year + "|" + $name.ToLowerInvariant()
        if (-not $rows.ContainsKey($key)) { $rows[$key] = [PSCustomObject]@{ Year = $year; Broker = $name; Orders = 0; Volume = 0.0; Fees = 0.0; PerOrder = 0.0; Pct = 0.0; Approx = $false } }
        $r = $rows[$key]
        $cur = Get-NormalizedCurrencyCode ([string]$t.Currency)
        if (-not $cur) { $cur = $Base }
        foreach ($part in @(@("Volume", [math]::Abs([double]$t.Shares * [double]$t.Price)), @("Fees", [double]$t.Fee))) {
            if ([double]$part[1] -eq 0) { continue }
            $cv = Convert-AmountOnDate -Amount ([double]$part[1]) -From $cur -To $Base -Date ([string]$t.Date) -History $History -FallbackFromEur $FallbackFromEur
            if ([bool]$cv.Approx -and $cur -ne $Base) { $r.Approx = $true }
            $r.($part[0]) += [double]$cv.Value
        }
        $r.Orders++
    }
    foreach ($r in $rows.Values) {
        $r.PerOrder = $r.Fees / $r.Orders
        if ($r.Volume -gt 0) { $r.Pct = $r.Fees / $r.Volume * 100.0 }
    }
    return @($rows.Values | Sort-Object -Property @{ Expression = { $_.Year }; Descending = $true }, @{ Expression = { $_.Broker }; Descending = $false })
}

# ---- goals per depot (v10.6) -------------------------------------------------
function Get-DepotGoal {
    # -> @{ Value; Dividend } of one depot ("" = main depot); 0 = no goal
    param($Goals, [string]$Id = "")
    foreach ($g in @($Goals)) {
        if ($null -ne $g -and [string]$g.Id -eq $Id) { return [PSCustomObject]@{ Value = [double]$g.Value; Dividend = [double]$g.Dividend } }
    }
    return [PSCustomObject]@{ Value = 0.0; Dividend = 0.0 }
}

function Set-DepotGoal {
    # new goal list with this depot set; without any goal the entry is dropped
    param($Goals, [string]$Id = "", [double]$Value = 0.0, [double]$Dividend = 0.0)
    $out = @(@($Goals) | Where-Object { $null -ne $_ -and [string]$_.Id -ne $Id })
    if ($Value -gt 0 -or $Dividend -gt 0) {
        $out += [PSCustomObject]@{ Id = $Id; Value = [math]::Max(0.0, $Value); Dividend = [math]::Max(0.0, $Dividend) }
    }
    return ,$out
}

function Get-GoalProgress {
    param([double]$Current, [double]$Target)
    if ($Target -le 0 -or [double]::IsNaN($Current)) { return $null }
    $pct = [math]::Max(0.0, $Current / $Target * 100.0)
    return [PSCustomObject]@{ Pct = $pct; BarPct = [math]::Min(100.0, $pct); Remaining = [math]::Max(0.0, $Target - $Current); Reached = ($Current -ge $Target) }
}

# ---- risk figures ------------------------------------------------------------
function Get-SortinoRatio {
    # (return p.a. - risk-free) / downside deviation p.a. Only periods below
    # the risk-free rate count as risk. Returns: fractions, AnnReturn: %.
    param([double[]]$Returns, [double]$AnnReturn, [double]$PeriodsPerYear = 252, [double]$RiskFreePct = 0.0)
    if ($null -eq $Returns -or $Returns.Count -lt 2 -or [double]::IsNaN($AnnReturn)) { return [double]::NaN }
    $mar = $RiskFreePct / 100.0 / $PeriodsPerYear
    $ss = 0.0
    foreach ($r in $Returns) { $d = [math]::Min(0.0, $r - $mar); $ss += $d * $d }
    $dd = [math]::Sqrt($ss / $Returns.Count) * [math]::Sqrt($PeriodsPerYear) * 100.0
    if ($dd -le 0) { return [double]::NaN }
    return (($AnnReturn - $RiskFreePct) / $dd)
}

function Get-HistoricVaR {
    # historic Value-at-Risk for one period: the loss (in %, positive number)
    # that was exceeded in only (100 - Level) % of the periods. 0 = even that
    # quantile was no loss. NaN with fewer than 20 returns.
    param([double[]]$Returns, [double]$Level = 95)
    if ($null -eq $Returns -or $Returns.Count -lt 20) { return [double]::NaN }
    $s = [double[]]@($Returns | Sort-Object)
    $pos = (1.0 - $Level / 100.0) * ($s.Count - 1)
    $lo = [int][math]::Floor($pos); $hi = [int][math]::Ceiling($pos)
    $q = $s[$lo] + ($s[$hi] - $s[$lo]) * ($pos - $lo)
    return [math]::Max(0.0, -$q * 100.0)
}

# ---- watchlist CSV -----------------------------------------------------------
function ConvertTo-WatchlistCsv {
    # Rows @{ Ticker; Groups (string[]); Target; Currency; Note }
    param($Rows)
    $inv = [System.Globalization.CultureInfo]::GetCultureInfo("de-DE")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Ticker;Gruppen;Zielkurs;Währung;Notiz")
    foreach ($r in @($Rows)) {
        if ($null -eq $r) { continue }
        $tg = if ([double]$r.Target -gt 0) { ([double]$r.Target).ToString("0.########", $inv) } else { "" }
        $note = (([string]$r.Note) -replace '[\r\n]+', ' ').Trim()
        $lines.Add((@((ConvertTo-CsvField ([string]$r.Ticker)), (ConvertTo-CsvField (@($r.Groups) -join "|")), $tg, $(if ($tg) { [string]$r.Currency } else { "" }), (ConvertTo-CsvField $note)) -join ";"))
    }
    return (($lines.ToArray() -join "`r`n") + "`r`n")
}

function ConvertFrom-WatchlistCsv {
    # -> @{ Rows; Skipped }. A header line with "Ticker" is expected; other
    # columns are optional. ^GSPC style symbols are allowed.
    param([string]$Text)
    $res = [PSCustomObject]@{ Rows = @(); Skipped = 0 }
    $csv = ConvertFrom-CsvText $Text
    $h = @($csv.Headers | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() })
    $col = { param([string[]]$names) foreach ($n in $names) { $i = [array]::IndexOf([string[]]$h, $n); if ($i -ge 0) { return $i } } return -1 }
    $iT = & $col @("ticker", "symbol")
    if ($iT -lt 0) {
        # a single column without header options still needs the header word
        $lines = @(([string]$Text) -split "`r?`n" | ForEach-Object { $_.Trim().Trim([char]0xFEFF) } | Where-Object { $_ })
        if ($lines.Count -eq 0 -or $lines[0].ToLowerInvariant() -notin @("ticker", "symbol")) { return $res }
        $csv = @{ Rows = @($lines | Select-Object -Skip 1 | ForEach-Object { ,[string[]]@($_) }) }
        $h = @("ticker"); $iT = 0
    }
    $iG = & $col @("gruppen", "gruppe", "groups"); $iP = & $col @("zielkurs", "target"); $iC = & $col @("währung", "currency"); $iN = & $col @("notiz", "note")
    $get = { param($row, [int]$i) if ($i -ge 0 -and $i -lt @($row).Count) { return ([string]$row[$i]).Trim() } return "" }
    $seen = @{}
    $rows = @()
    foreach ($row in @($csv.Rows)) {
        $sym = (& $get $row $iT).TrimStart("'").ToUpperInvariant()
        if ($sym -notmatch '^[A-Z0-9\^][A-Z0-9\.\-=\^]{0,19}$' -or $seen.ContainsKey($sym)) { $res.Skipped++; continue }
        $seen[$sym] = $true
        $tg = 0.0
        $raw = & $get $row $iP
        if ($raw) { $x = ConvertFrom-CsvNumber $raw; if (-not [double]::IsNaN($x) -and $x -gt 0) { $tg = $x } }
        $cur = (& $get $row $iC).ToUpperInvariant()
        if ($cur -notmatch '^[A-Z]{3}$') { $cur = "" }
        $note = & $get $row $iN
        if ($note -match "^'[=+\-@]") { $note = $note.Substring(1) }
        $grp = @((& $get $row $iG).TrimStart("'") -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_.Length -le 40 })
        $rows += [PSCustomObject]@{ Ticker = $sym; Groups = $grp; Target = $tg; Currency = $cur; Note = $note }
    }
    $res.Rows = $rows
    return $res
}

# ---- 9.0: chart tags ---------------------------------------------------------
function Get-FreeTagX {
    # Left edge for a tag so that it does not cover the tags in $Used
    # (@{X;Y;W;H}). Moves left only; never past $MinX.
    param([double]$X, [double]$Y, [double]$Width, [double]$Height, $Used = @(), [double]$MinX = 0, [double]$Gap = 4)
    $x0 = $X
    for ($guard = 0; $guard -lt 50; $guard++) {
        $hit = $null
        foreach ($u in @($Used)) {
            if ($null -eq $u) { continue }
            if ($x0 -lt ($u.X + $u.W) -and ($x0 + $Width) -gt $u.X -and $Y -lt ($u.Y + $u.H) -and ($Y + $Height) -gt $u.Y) { $hit = $u; break }
        }
        if ($null -eq $hit) { return $x0 }
        $next = $hit.X - $Width - $Gap
        if ($next -lt $MinX) { return [math]::Max($MinX, $x0) }
        $x0 = $next
    }
    return $x0
}

function Get-FittedWidths {
    # Widths for a row of buttons: text width + padding when there is room
    # (never stretched further), otherwise all shrink by the same factor.
    param([double[]]$Natural, [double]$Available, [double]$Gap = 4, [double]$Pad = 16)
    if ($null -eq $Natural -or $Natural.Count -eq 0) { return @() }
    $want = @($Natural | ForEach-Object { $_ + $Pad })
    $sum = 0.0; foreach ($w in $want) { $sum += $w }
    $room = $Available - $Gap * ($Natural.Count - 1)
    $f = if ($sum -gt $room -and $sum -gt 0) { [math]::Max(0.0, $room / $sum) } else { 1.0 }
    return @($want | ForEach-Object { [int][math]::Floor($_ * $f) })
}

# ---- 10.0: overview ----------------------------------------------------------
function Get-AllocationSlices {
    # Items @{Name;Value} -> largest first with Pct; everything after
    # MaxSlices-1 is one "other" slice. Values <= 0 are left out.
    param($Items, [int]$MaxSlices = 6, [string]$OtherName = "Übrige")
    $list = @(@($Items) | Where-Object { $null -ne $_ -and [double]$_.Value -gt 0 } | ForEach-Object { [PSCustomObject]@{ Name = [string]$_.Name; Value = [double]$_.Value } } | Sort-Object Value -Descending)
    if ($list.Count -eq 0) { return @() }
    $sum = 0.0; foreach ($i in $list) { $sum += $i.Value }
    if ($list.Count -gt $MaxSlices) {
        $rest = 0.0; foreach ($i in @($list | Select-Object -Skip ($MaxSlices - 1))) { $rest += $i.Value }
        $list = @($list | Select-Object -First ($MaxSlices - 1)) + @([PSCustomObject]@{ Name = $OtherName; Value = $rest })
    }
    return @($list | ForEach-Object { [PSCustomObject]@{ Name = $_.Name; Value = $_.Value; Pct = $_.Value / $sum * 100.0 } })
}

function Get-CombinedTrend {
    # Portfolio value over a short period. Series @{EndValue; Values}: each
    # price line is scaled so its last point equals today's position value
    # (independent of price units), stretched to $Points and added up.
    param($Series, [int]$Points = 60)
    $sum = New-Object double[] $Points
    $used = 0
    foreach ($s in @($Series)) {
        $v = [double[]]@($s.Values)
        if ($v.Count -lt 2 -or $v[$v.Count - 1] -le 0) { continue }
        $f = [double]$s.EndValue / $v[$v.Count - 1]
        for ($i = 0; $i -lt $Points; $i++) {
            $pos = $i * ($v.Count - 1) / [double]($Points - 1)
            $lo = [int][math]::Floor($pos); $hi = [math]::Min($v.Count - 1, $lo + 1)
            $sum[$i] += ($v[$lo] + ($v[$hi] - $v[$lo]) * ($pos - $lo)) * $f
        }
        $used++
    }
    if ($used -eq 0) { return @() }
    return $sum
}
