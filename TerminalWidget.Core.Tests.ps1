# ==============================================================================
# TerminalWidget.Core.Tests.ps1 - Pester 5 tests for TerminalWidget.Core.ps1
# ------------------------------------------------------------------------------
# Run (PowerShell 5.1 or 7, in the folder of the scripts):
#     Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
#     Invoke-Pester .\TerminalWidget.Core.Tests.ps1 -Output Detailed
# No network, no UI: only the pure logic is tested (plus one text check that
# every glossary key used by TerminalWidget.ps1 exists).
# File encoding: UTF-8 with BOM (umlauts in the expected texts).
# ==============================================================================

BeforeAll {
    . (Join-Path $PSScriptRoot "TerminalWidget.Core.ps1")

    # Fake Yahoo "meta" for a US stock (regular 9:30-16:00 ET, pre 4:00, post 20:00)
    function New-TestMeta {
        param([long]$RegStart, [long]$RegEnd, [long]$PreStart, [long]$PostEnd, [int]$GmtOffset = -18000)
        return [PSCustomObject]@{
            gmtoffset            = $GmtOffset
            exchangeName         = "NMS"
            fullExchangeName     = "NasdaqGS"
            exchangeTimezoneName = "America/New_York"
            instrumentType       = "EQUITY"
            currentTradingPeriod = [PSCustomObject]@{
                pre     = [PSCustomObject]@{ start = $PreStart; end = $RegStart; gmtoffset = $GmtOffset }
                regular = [PSCustomObject]@{ start = $RegStart; end = $RegEnd; gmtoffset = $GmtOffset }
                post    = [PSCustomObject]@{ start = $RegEnd; end = $PostEnd; gmtoffset = $GmtOffset }
            }
        }
    }
    function Get-Defined { param($Arr) return @($Arr | Where-Object { -not [double]::IsNaN($_) }) }
}

Describe "Indicators" {
    It "SMA over a sliding window" {
        $r = Compute-Sma -Prices @(1, 2, 3, 4, 5) -Period 3
        [double]::IsNaN($r[0]) | Should -BeTrue
        [double]::IsNaN($r[1]) | Should -BeTrue
        $r[2] | Should -Be 2
        $r[3] | Should -Be 3
        $r[4] | Should -Be 4
    }
    It "SMA with too few values is all NaN" {
        (Get-Defined (Compute-Sma -Prices @(1, 2) -Period 5)).Count | Should -Be 0
    }
    It "RSI of a steadily rising series is 100" {
        $r = Compute-Rsi -Prices (1..20 | ForEach-Object { [double]$_ }) -Period 14
        [double]::IsNaN($r[13]) | Should -BeTrue
        $r[14] | Should -Be 100
        $r[19] | Should -Be 100
    }
    It "RSI of an alternating series is 50" {
        $prices = 0..20 | ForEach-Object { if ($_ % 2 -eq 0) { 1.0 } else { 2.0 } }
        $r = Compute-Rsi -Prices $prices -Period 14
        $r[14] | Should -Be 50
    }
    It "Bollinger bands of a flat series collapse onto the mean" {
        $bb = Compute-BollingerBands -Prices @(5, 5, 5, 5) -Period 3 -Multiplier 2
        $bb.Upper[2] | Should -Be 5
        $bb.Lower[3] | Should -Be 5
        [double]::IsNaN($bb.Upper[1]) | Should -BeTrue
    }
    It "VWAP ignores extended hours and restarts every day" {
        $d1 = 1767279600000L   # 2026-01-01 15:00 UTC
        $series = @(
            [PSCustomObject]@{ Ts = $d1;            High = 10; Low = 10; Close = 10; Volume = 100;  Ext = $false },
            [PSCustomObject]@{ Ts = $d1 + 3600000;  High = 20; Low = 20; Close = 20; Volume = 100;  Ext = $false },
            [PSCustomObject]@{ Ts = $d1 + 7200000;  High = 99; Low = 99; Close = 99; Volume = 1000; Ext = $true },
            [PSCustomObject]@{ Ts = $d1 + 86400000; High = 30; Low = 30; Close = 30; Volume = 50;   Ext = $false }
        )
        $v = Compute-Vwap -Series $series -GmtOffsetSec 0
        $v[0] | Should -Be 10
        $v[1] | Should -Be 15
        $v[2] | Should -Be 15
        $v[3] | Should -Be 30
    }
}

Describe "Number input (locale tolerant)" {
    It "parses <Raw> as <Expected>" -TestCases @(
        @{ Raw = "1234,56";     Expected = 1234.56 }
        @{ Raw = "1.234,56";    Expected = 1234.56 }
        @{ Raw = "1,234.56";    Expected = 1234.56 }
        @{ Raw = "1'234.50";    Expected = 1234.5 }
        @{ Raw = "1.234.567";   Expected = 1234567 }
        @{ Raw = "1,234,567";   Expected = 1234567 }
        @{ Raw = " 12 EUR ";    Expected = 12 }
        @{ Raw = "-3,5%";       Expected = -3.5 }
        @{ Raw = "EUR 12,50";   Expected = 12.5 }                                   # v3.0: prefix
        @{ Raw = "`$1,234.56";  Expected = 1234.56 }
        @{ Raw = ([string][char]0x20AC + "1.234,56"); Expected = 1234.56 }         # Euro sign
        @{ Raw = ("12 " + [string][char]0x20AC);      Expected = 12 }
        @{ Raw = ([string][char]0x00A3 + "7.5");      Expected = 7.5 }             # Pound sign
    ) {
        Parse-DecimalInput $Raw | Should -Be $Expected
    }
    It "rejects garbage but accepts empty input" {
        Test-DecimalInput "abc" | Should -BeFalse
        Test-DecimalInput "" | Should -BeTrue
        Parse-DecimalInput "" | Should -Be 0
    }
}

Describe "Currency units" {
    It "converts pence to pounds (case-sensitive GBp)" {
        $r = Normalize-CurrencyAndPrice -Price 1234 -RawCurrency "GBp"
        $r.Price | Should -Be 12.34
        $r.Currency | Should -Be "GBP"
    }
    It "leaves GBP untouched" {
        (Normalize-CurrencyAndPrice -Price 1234 -RawCurrency "GBP").Price | Should -Be 1234
    }
    It "converts ZAc to ZAR" {
        (Normalize-CurrencyAndPrice -Price 500 -RawCurrency "ZAc").Currency | Should -Be "ZAR"
    }
}

Describe "Holiday calendars" {
    It "Easter Sunday <Year> is <Date>" -TestCases @(
        @{ Year = 2024; Date = "2024-03-31" }
        @{ Year = 2025; Date = "2025-04-20" }
        @{ Year = 2026; Date = "2026-04-05" }
        @{ Year = 2027; Date = "2027-03-28" }
    ) {
        (Get-EasterSunday -Year $Year).ToString("yyyy-MM-dd") | Should -Be $Date
    }
    It "<Cal> <Date> is a holiday: <IsHoliday>" -TestCases @(
        @{ Cal = "US"; Date = "2026-11-26"; IsHoliday = $true }    # Thanksgiving
        @{ Cal = "US"; Date = "2026-07-03"; IsHoliday = $true }    # July 4th (Sat) observed Fri
        @{ Cal = "US"; Date = "2026-06-19"; IsHoliday = $true }    # Juneteenth
        @{ Cal = "US"; Date = "2026-04-03"; IsHoliday = $true }    # Good Friday
        @{ Cal = "US"; Date = "2027-06-18"; IsHoliday = $true }    # Juneteenth (Sat) observed Fri
        @{ Cal = "US"; Date = "2027-07-05"; IsHoliday = $true }    # July 4th (Sun) observed Mon
        @{ Cal = "US"; Date = "2027-12-24"; IsHoliday = $true }    # Christmas (Sat) observed Fri
        @{ Cal = "US"; Date = "2026-11-27"; IsHoliday = $false }   # day after Thanksgiving: early close only
        @{ Cal = "DE"; Date = "2026-12-24"; IsHoliday = $true }
        @{ Cal = "DE"; Date = "2026-12-31"; IsHoliday = $true }
        @{ Cal = "DE"; Date = "2026-05-25"; IsHoliday = $false }   # Xetra trades on Whit Monday
        @{ Cal = "CH"; Date = "2026-05-14"; IsHoliday = $true }    # Auffahrt
        @{ Cal = "CH"; Date = "2026-05-25"; IsHoliday = $true }    # Pfingstmontag
        @{ Cal = "CH"; Date = "2026-01-02"; IsHoliday = $true }    # Berchtoldstag
        @{ Cal = "UK"; Date = "2026-12-28"; IsHoliday = $true }    # Boxing Day (Sat) substitute
        @{ Cal = "UK"; Date = "2027-12-27"; IsHoliday = $true }    # Christmas (Sat) substitute
        @{ Cal = "UK"; Date = "2027-12-28"; IsHoliday = $true }    # Boxing Day (Sun) substitute
        @{ Cal = "AT"; Date = "2026-05-25"; IsHoliday = $true }    # Pfingstmontag
    ) {
        $y = [int]$Date.Substring(0, 4)
        (Get-HolidayMap -Cal $Cal -Year $y).ContainsKey($Date) | Should -Be $IsHoliday
    }
    It "finds exchange time zones without adding errors (v4.0.1)" {
        $script:TzCache.Remove("Europe/Zurich")
        $script:TzCache.Remove("Mars/Olympus_Mons")
        $before = $Error.Count
        Get-ExchangeTimeZone -Name "Europe/Zurich" | Should -Not -BeNullOrEmpty
        Get-ExchangeTimeZone -Name "Mars/Olympus_Mons" | Should -BeNullOrEmpty
        $Error.Count | Should -Be $before
    }
    It "maps exchange codes and time zones to calendars" {
        Get-HolidayCalendarKey -ExchangeCode "NMS" -TzName "" | Should -Be "US"
        Get-HolidayCalendarKey -ExchangeCode "EBS" -TzName "" | Should -Be "CH"
        Get-HolidayCalendarKey -ExchangeCode "XYZ" -TzName "Europe/Berlin" | Should -Be "DE"
        Get-HolidayCalendarKey -ExchangeCode "XYZ" -TzName "Asia/Tokyo" | Should -Be ""
    }
}

Describe "Sessions and market hours" {
    BeforeAll {
        # Mon 2026-01-05: regular 14:30-21:00 UTC (EST), pre from 09:00, post until 01:00
        $script:TpJan = Get-TradingPeriodInfo -Meta (New-TestMeta -RegStart 1767623400 -RegEnd 1767646800 -PreStart 1767603600 -PostEnd 1767661200)
        # Wed 2026-11-25 (day before Thanksgiving)
        $script:TpNov = Get-TradingPeriodInfo -Meta (New-TestMeta -RegStart 1795617000 -RegEnd 1795640400 -PreStart 1795597200 -PostEnd 1795658400)
        # Fri 2026-03-06 (US DST starts Sun 2026-03-08)
        $script:TpMar = Get-TradingPeriodInfo -Meta (New-TestMeta -RegStart 1772807400 -RegEnd 1772830800 -PreStart 1772787600 -PostEnd 1772848800)
    }
    It "builds the trading period with local opening time 9:30" {
        $script:TpJan.RegStartTod | Should -Be (9 * 3600 + 30 * 60)
        $script:TpJan.HolidayCal | Should -Be "US"
        $script:TpJan.HasPre | Should -BeTrue
    }
    It "classifies bars around the open (EST)" {
        Get-BarSession -TsSec 1772807340 -Tp $script:TpJan | Should -Be "PRE"   # Fri 06.03. 9:29 EST
        Get-BarSession -TsSec 1772807400 -Tp $script:TpJan | Should -Be "R"     # Fri 06.03. 9:30 EST
    }
    It "classifies bars correctly after the DST switch (EDT)" {
        if ($null -eq $script:TpJan.Tz) { Set-ItResult -Skipped -Because "time zone America/New_York not available"; return }
        Get-BarSession -TsSec 1773063000 -Tp $script:TpJan | Should -Be "R"     # Mon 09.03. 13:30 UTC = 9:30 EDT
        Get-BarSession -TsSec 1773061200 -Tp $script:TpJan | Should -Be "PRE"   # Mon 09.03. 13:00 UTC = 9:00 EDT
    }
    It "skips Thanksgiving for the next open" {
        Get-NextRegularOpen -Tp $script:TpNov -NowSec 1795644000 | Should -Be 1795789800   # -> Fri 27.11. 14:30 UTC
    }
    It "skips the weekend for the next open" {
        Get-NextRegularOpen -Tp $script:TpNov -NowSec 1795816800 | Should -Be 1796049000   # Fri evening -> Mon 30.11.
    }
    It "keeps the local opening time across the DST switch" {
        if ($null -eq $script:TpMar.Tz) { Set-ItResult -Skipped -Because "time zone America/New_York not available"; return }
        Get-NextRegularOpen -Tp $script:TpMar -NowSec 1772834400 | Should -Be 1773063000   # -> Mon 09.03. 9:30 EDT = 13:30 UTC
    }
    It "reports a holiday as closed with its name" {
        $ms = Get-MarketState -Tp $script:TpNov -NowSec 1795705200   # Thu 26.11. 15:00 UTC
        $ms.State | Should -Be "CLOSED"
        $ms.Holiday | Should -Be "Thanksgiving"
        $ms.NextSec | Should -Be 1795789800
    }
    It "reports the regular session as open" {
        (Get-MarketState -Tp $script:TpNov -NowSec (1795617000 + 600)).State | Should -Be "REGULAR"
    }
    It "takes the previous session close from intraday bars" {
        $res = [PSCustomObject]@{
            meta       = [PSCustomObject]@{ gmtoffset = 0 }
            timestamp  = @(1767279600, 1767283200, 1767366000)
            indicators = [PSCustomObject]@{ quote = @([PSCustomObject]@{ close = @(10.0, 11.0, 12.0) }) }
        }
        Get-SessionPrevClose -Result $res -Tp $null | Should -Be 11
    }
}

Describe "Helpers" {
    It "formats durations" {
        Format-Duration 59 | Should -Be "59s"
        Format-Duration 3725 | Should -Be "1h 02m"
        Format-Duration 90061 | Should -Be "1d 1h"
    }
    It "slices arrays without unrolling" {
        $r = Get-ArraySlice @(1, 2, 3, 4) 1 2
        $r.Count | Should -Be 2
        $r[0] | Should -Be 2
        (Get-ArraySlice @(5) 0 0).Count | Should -Be 1
        (Get-ArraySlice @(1, 2) 0 5).Count | Should -Be 0
    }
    It "recognises alert kinds" {
        Get-AlertKind ">=" | Should -Be "PRICE"
        Get-AlertKind "Tag% <=" | Should -Be "PCT"
        Get-AlertKind "RSI >=" | Should -Be "RSI"
        Get-AlertKind "> SMA" | Should -Be "SMA"
    }
    It "formats compact numbers" {
        Format-CompactNumber 1500000 | Should -Match "^1[.,]50M$"
        Format-CompactNumber 999 | Should -Be "999"
    }
}

# ==============================================================================
# v3.0
# ==============================================================================
Describe "Shared lists (v3.0)" {
    It "offers all alert conditions, each with a known kind" {
        $conds = @(Get-AlertConditions)
        $conds.Count | Should -Be 18
        @($conds | ForEach-Object { Get-AlertKind $_ } | Sort-Object -Unique) -join "," | Should -Be "EKPCT,HIGH52,LOW52,PCT,PFPCT,PFVAL,PRICE,RSI,SMA,TRAIL,VOL"
    }
    It "cycles the display currency <From> -> <To>" -TestCases @(
        @{ From = "EUR"; To = "USD" }
        @{ From = "USD"; To = "CHF" }
        @{ From = "chf"; To = "GBP" }
        @{ From = "GBP"; To = "EUR" }
        @{ From = "XYZ"; To = "EUR" }
    ) {
        Get-NextDisplayCurrency $From | Should -Be $To
    }
}

Describe "Currency codes (v3.0)" {
    It "normalizes '<Raw>' to '<Expected>'" -TestCases @(
        @{ Raw = "GBp";   Expected = "GBP" }
        @{ Raw = "GBX";   Expected = "GBP" }
        @{ Raw = "gbp";   Expected = "GBP" }
        @{ Raw = "ZAc";   Expected = "ZAR" }
        @{ Raw = "ILA";   Expected = "ILS" }
        @{ Raw = " chf "; Expected = "CHF" }
        @{ Raw = "SEK";   Expected = "SEK" }
        @{ Raw = "EURO";  Expected = "" }
        @{ Raw = "%";     Expected = "" }
        @{ Raw = "";      Expected = "" }
    ) {
        Get-NormalizedCurrencyCode $Raw | Should -Be $Expected
    }
    It "finds positions whose currency contradicts their own bookings" {
        $pf = @{
            "BARC.L" = [PSCustomObject]@{ Currency = "EUR" }
            "NVDA"   = [PSCustomObject]@{ Currency = "USD" }
            "ABBN.SW" = [PSCustomObject]@{ Currency = "CHF" }
        }
        $tx = @(
            [PSCustomObject]@{ Ticker = "BARC.L"; Type = "Kauf"; Currency = "GBP" }
            [PSCustomObject]@{ Ticker = "NVDA";   Type = "Kauf"; Currency = "USD" }
            [PSCustomObject]@{ Ticker = "NVDA";   Type = "Dividende"; Currency = "EUR" }
        )
        $m = @(Find-PositionCurrencyMismatch -Portfolio $pf -Transactions $tx)
        $m.Count | Should -Be 1
        $m[0].Ticker | Should -Be "BARC.L"
        $m[0].PositionCurrency | Should -Be "EUR"
        $m[0].TransactionCurrencies | Should -Be "GBP"
    }
    It "reports nothing without transactions" {
        @(Find-PositionCurrencyMismatch -Portfolio @{ "X" = [PSCustomObject]@{ Currency = "USD" } } -Transactions @()).Count | Should -Be 0
    }
}

Describe "Symbol resolution (v3.0)" {
    BeforeAll {
        $script:ProbeOk = [PSCustomObject]@{ chart = [PSCustomObject]@{ result = @([PSCustomObject]@{ meta = [PSCustomObject]@{ regularMarketPrice = 123.4 } }) } }
        $script:ProbeNoPrice = [PSCustomObject]@{ chart = [PSCustomObject]@{ result = @([PSCustomObject]@{ meta = [PSCustomObject]@{ regularMarketPrice = $null } }) } }
        $script:Hits = @([PSCustomObject]@{ Symbol = "nvda" }, [PSCustomObject]@{ Symbol = "NVD.DE" })
    }
    It "keeps a symbol Yahoo has a price for" {
        Select-ResolvedSymbol -Raw " abbn.sw " -ProbeJson $script:ProbeOk -SearchItems $script:Hits | Should -Be "ABBN.SW"
    }
    It "falls back to the first search hit" {
        Select-ResolvedSymbol -Raw "nvidia" -ProbeJson $script:ProbeNoPrice -SearchItems $script:Hits | Should -Be "NVDA"
        Select-ResolvedSymbol -Raw "nvidia" -ProbeJson $null -SearchItems $script:Hits | Should -Be "NVDA"
    }
    It "returns the cleaned input when nothing is known (offline)" {
        Select-ResolvedSymbol -Raw "msft" -ProbeJson $null -SearchItems @() | Should -Be "MSFT"
        Select-ResolvedSymbol -Raw "   " -ProbeJson $null | Should -Be ""
    }
    It "parses Yahoo search results and drops unsupported types" {
        $json = [PSCustomObject]@{ quotes = @(
            [PSCustomObject]@{ symbol = "nvda"; quoteType = "EQUITY"; shortname = "NVIDIA Corp"; exchDisp = "NASDAQ" }
            [PSCustomObject]@{ symbol = "NVDA250117C00100000"; quoteType = "OPTION"; shortname = "Option" }
            [PSCustomObject]@{ symbol = "GC=F"; quoteType = "FUTURE"; longname = "Gold"; exchange = "CMX" }
        ) }
        $r = @(ConvertFrom-YahooSearch -Json $json)
        $r.Count | Should -Be 2
        $r[0].Symbol | Should -Be "NVDA"
        $r[0].Name | Should -Be "NVIDIA Corp"
        $r[1].Exch | Should -Be "CMX"
        @(ConvertFrom-YahooSearch -Json $null).Count | Should -Be 0
    }
}

Describe "Transactions (v3.0)" {
    It "capitalises buy fees into the average cost" {
        $r = Get-BuyResult -OldShares 10 -OldAvg 100 -Shares 10 -Price 120 -Fee 2
        $r.Shares | Should -Be 20
        [math]::Round($r.AvgPrice, 6) | Should -Be 110.1
    }
    It "computes realized P/L on a sell and keeps the average" {
        $r = Get-SellResult -OldShares 20 -OldAvg 110.1 -Shares 5 -Price 130 -Fee 1
        [math]::Round($r.Realized, 6) | Should -Be 98.5
        $r.Shares | Should -Be 15
        $r.AvgPrice | Should -Be 110.1
    }
    It "resets the average when the position is closed" {
        $r = Get-SellResult -OldShares 5 -OldAvg 10 -Shares 5 -Price 12 -Fee 0
        $r.Shares | Should -Be 0
        $r.AvgPrice | Should -Be 0
    }
    It "replays bookings in date order and skips foreign-currency ones" {
        $tx = @(
            [PSCustomObject]@{ Date = "2026-01-10"; Ticker = "NVDA"; Type = "Kauf";      Shares = 10; Price = 100; Fee = 0; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-01-05"; Ticker = "nvda"; Type = "Kauf";      Shares = 10; Price = 80;  Fee = 0; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-02-01"; Ticker = "NVDA"; Type = "Verkauf";   Shares = 5;  Price = 120; Fee = 2; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-02-01"; Ticker = "NVDA"; Type = "Dividende"; Shares = 0;  Price = 9;   Fee = 0; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-03-01"; Ticker = "NVDA"; Type = "Kauf";      Shares = 1;  Price = 50;  Fee = 0; Currency = "GBP" }
            [PSCustomObject]@{ Date = "2026-01-01"; Ticker = "MSFT"; Type = "Kauf";      Shares = 3;  Price = 400; Fee = 0; Currency = "USD" }
        )
        $p = Get-PositionFromTransactions -Transactions $tx -Ticker "NVDA"
        $p.Shares | Should -Be 15
        $p.AvgPrice | Should -Be 90
        $p.Currency | Should -Be "EUR"
        $p.Realized | Should -Be 148
        $p.Used | Should -Be 3
        $p.Skipped | Should -Be 1
        $p.Clamped | Should -BeFalse
    }
    It "clamps a sell that is larger than the holding" {
        $tx = @(
            [PSCustomObject]@{ Date = "2026-01-01"; Ticker = "X"; Type = "Kauf";    Shares = 5; Price = 10; Fee = 0; Currency = "USD" }
            [PSCustomObject]@{ Date = "2026-01-02"; Ticker = "X"; Type = "Verkauf"; Shares = 7; Price = 12; Fee = 0; Currency = "USD" }
        )
        $p = Get-PositionFromTransactions -Transactions $tx -Ticker "X"
        $p.Shares | Should -Be 0
        $p.Realized | Should -Be 10
        $p.Clamped | Should -BeTrue
    }
    It "returns null when a ticker has no buys/sells" {
        Get-PositionFromTransactions -Transactions @() -Ticker "X" | Should -BeNullOrEmpty
    }
}

Describe "CSV fields (v3.0)" {
    It "escapes '<Raw>'" -TestCases @(
        @{ Raw = "plain";      Expected = "plain" }
        @{ Raw = "=SUM(A1)";   Expected = "'=SUM(A1)" }
        @{ Raw = "@cmd";       Expected = "'@cmd" }
        @{ Raw = "a;b";        Expected = '"a;b"' }
        @{ Raw = 'say "hi"';   Expected = '"say ""hi"""' }
        @{ Raw = "";           Expected = "" }
    ) {
        ConvertTo-CsvField $Raw | Should -Be $Expected
    }
}

# ==============================================================================
# v4.0
# ==============================================================================
Describe "Layouts and themes (v4.0)" {
    It "cycles the layout <From> -> <To>" -TestCases @(
        @{ From = "Ticker";   To = "Compact" }
        @{ From = "Compact";  To = "Standard" }
        @{ From = "Standard"; To = "Terminal" }
        @{ From = "Terminal"; To = "Ticker" }
        @{ From = "Quatsch";  To = "Standard" }
    ) {
        Get-NextLayout $From | Should -Be $To
    }
    It "treats Ticker and Compact as small bars" {
        Test-CompactLayout "Ticker" | Should -BeTrue
        Test-CompactLayout "Compact" | Should -BeTrue
        Test-CompactLayout "Standard" | Should -BeFalse
        Test-CompactLayout "Terminal" | Should -BeFalse
    }
    It "cycles the theme through Terminal and back to Dark" {
        Get-NextTheme "Light" | Should -Be "Terminal"
        Get-NextTheme "Terminal" | Should -Be "Graphite"
        Get-NextTheme "Graphite" | Should -Be "Contrast"
        Get-NextTheme "Contrast" | Should -Be "Dark"
        Get-NextTheme "unknown" | Should -Be "Dark"
    }
}

Describe "Terminal layout geometry (v4.0)" {
    It "puts both lists side by side when they fit" {
        $r = Get-TerminalLayoutRects -X 10 -Y 90 -W 1600 -H 900 -ChartPct 50 -PanelMinW 756 -Gap 8 -MinBottomH 300
        $r.SideBySide | Should -BeTrue
        $r.Chart | Should -Be @(10, 90, 1600, 450)
        $r.Watchlist[1] | Should -Be 548
        $r.Watchlist[3] | Should -Be 442
        ($r.Watchlist[2] + 8 + $r.Portfolio[2]) | Should -Be 1600
        $r.Portfolio[0] | Should -Be ($r.Watchlist[0] + $r.Watchlist[2] + 8)
    }
    It "shows only the active lower panel when the window is narrow" {
        $r = Get-TerminalLayoutRects -X 0 -Y 0 -W 1000 -H 900 -ActiveBottom "Portfolio" -PanelMinW 756
        $r.SideBySide | Should -BeFalse
        $r.Watchlist | Should -BeNullOrEmpty
        $r.Portfolio[2] | Should -Be 1000
    }
    It "falls back to the first enabled panel" {
        $r = Get-TerminalLayoutRects -X 0 -Y 0 -W 1000 -H 900 -ShowWatch $false -ActiveBottom "Watchlist"
        $r.Watchlist | Should -BeNullOrEmpty
        $r.Portfolio | Should -Not -BeNullOrEmpty
    }
    It "gives the chart everything when no list is enabled" {
        $r = Get-TerminalLayoutRects -X 5 -Y 6 -W 700 -H 500 -ShowWatch $false -ShowPortfolio $false
        $r.Chart | Should -Be @(5, 6, 700, 500)
    }
    It "keeps the minimum height of the lower panel" {
        $r = Get-TerminalLayoutRects -X 0 -Y 0 -W 1000 -H 700 -ChartPct 80 -MinBottomH 300 -Gap 8
        $r.Watchlist[3] | Should -Be 300
        $r.Chart[3] | Should -Be 392
    }
}

Describe "Freshness (v4.0)" {
    It "rates <Age> s at refresh <Ref> s as <Level>" -TestCases @(
        @{ Age = 10;   Ref = 15; Off = $false; Level = "OK" }
        @{ Age = 44;   Ref = 15; Off = $false; Level = "OK" }
        @{ Age = 46;   Ref = 15; Off = $false; Level = "WARN" }
        @{ Age = 301;  Ref = 15; Off = $false; Level = "ERR" }
        @{ Age = 130;  Ref = 60; Off = $false; Level = "WARN" }
        @{ Age = 5;    Ref = 15; Off = $true;  Level = "ERR" }
    ) {
        Get-StalenessLevel -AgeSec $Age -RefreshSec $Ref -Offline $Off | Should -Be $Level
    }
    It "treats 'never loaded' as an error" {
        Get-StalenessLevel -AgeSec ([double]::NaN) -RefreshSec 15 | Should -Be "ERR"
    }
    It "detects a sleep gap of the 1-second timer" {
        $t0 = Get-Date "2026-11-23 08:00:00"
        Test-ResumeGap -Last $t0 -Now $t0.AddSeconds(2) | Should -BeFalse
        Test-ResumeGap -Last $t0 -Now $t0.AddMinutes(30) | Should -BeTrue
        Test-ResumeGap -Last ([DateTime]::MinValue) -Now $t0 | Should -BeFalse
    }
}

Describe "Quote cache (v4.0)" {
    It "writes NaN / Infinity as null and reads null back as NaN" {
        ConvertTo-JsonSafeNumber ([double]::NaN) | Should -BeNullOrEmpty
        ConvertTo-JsonSafeNumber ([double]::PositiveInfinity) | Should -BeNullOrEmpty
        ConvertTo-JsonSafeNumber 1.5 | Should -Be 1.5
        [double]::IsNaN((ConvertFrom-JsonNumber $null)) | Should -BeTrue
        ConvertFrom-JsonNumber $null 0.0 | Should -Be 0
    }
    It "survives a JSON round trip and rebuilds the trading period" {
        $meta = New-TestMeta -RegStart 1767623400 -RegEnd 1767646800 -PreStart 1767603600 -PostEnd 1767661200
        $q = [PSCustomObject]@{
            Ticker = "NVDA"; LongName = "NVIDIA"; Price = 181.5; PrevClose = 180.0; ChangePct = 0.8333; Currency = "USD"
            High52 = 212.0; Low52 = 86.6; Rsi14 = [double]::NaN; SmaFastH = 179.9; Meta = (New-MetaLite $meta)
            UpdatedAt = (Get-Date "2026-11-23T15:30:00")
        }
        $entry = ConvertTo-QuoteCacheEntry -Quote $q -Spark @(1.0, [double]::NaN, 2.0)
        $json = ConvertTo-Json -InputObject $entry -Depth 8
        $json | Should -Not -MatchExactly '\bNaN\b'
        $back = ConvertFrom-QuoteCacheEntry -Entry ($json | ConvertFrom-Json)
        $back.Ticker | Should -Be "NVDA"
        $back.Price | Should -Be 181.5
        $back.FromCache | Should -BeTrue
        [double]::IsNaN($back.Rsi14) | Should -BeTrue
        $back.ExtPrice | Should -Be 0
        $back.Tp | Should -Not -BeNullOrEmpty
        $back.Tp.RegStartTod | Should -Be (9 * 3600 + 30 * 60)
        @($entry.Spark).Count | Should -Be 2
    }
    It "ignores entries without a price" {
        ConvertFrom-QuoteCacheEntry -Entry ([PSCustomObject]@{ Ticker = "X"; Price = $null }) | Should -BeNullOrEmpty
    }
}

Describe "Data folder migration (v4.0)" {
    It "copies the v3 data only when the new folder has none" {
        Get-DataMigrationAction -NewHasConfig $false -OldHasConfig $true | Should -Be "CopyFromOld"
        Get-DataMigrationAction -NewHasConfig $true -OldHasConfig $true | Should -Be "None"
        Get-DataMigrationAction -NewHasConfig $false -OldHasConfig $false | Should -Be "Fresh"
    }
    It "copies all data files including the caches" {
        $f = @(Get-DataFileNames)
        $f | Should -Contain "transactions.json"
        $f | Should -Contain "intraday_cache.json"
    }
}

Describe "Glossary and tooltips (v4.0)" {
    It "has unique keys and texts for every entry" {
        $all = @(Get-GlossaryEntries)
        $all.Count | Should -BeGreaterThan 30
        @($all | ForEach-Object { $_.Key } | Sort-Object -Unique).Count | Should -Be $all.Count
        foreach ($g in $all) {
            $g.Term | Should -Not -BeNullOrEmpty
            $g.Short | Should -Not -BeNullOrEmpty
            $g.Long.Length | Should -BeGreaterThan $g.Short.Length
        }
    }
    It "builds tooltip texts per mode" {
        Get-TooltipText -Text "Taste R" -Key "RSI" -Mode "Off" | Should -Be ""
        Get-TooltipText -Text "Taste R" -Key "RSI" -Mode "Short" | Should -Be "Taste R"
        Get-TooltipText -Text "" -Key "RSI" -Mode "Short" | Should -Match "^RSI .*: "
        $long = Get-TooltipText -Text "Taste R" -Key "RSI" -Mode "Long"
        $long | Should -Match "^Taste R"
        $long | Should -Match "überkauft"
        Get-TooltipText -Text "nur Text" -Key "GIBTSNICHT" -Mode "Long" | Should -Be "nur Text"
    }
    It "knows every glossary key that TerminalWidget.ps1 uses" {
        $ui = Join-Path $PSScriptRoot "TerminalWidget.ps1"
        if (-not (Test-Path $ui)) { Set-ItResult -Skipped -Because "TerminalWidget.ps1 not next to the tests"; return }
        $keys = @(Get-GlossaryEntries | ForEach-Object { $_.Key })
        # quoted UPPERCASE tokens on tooltip / legend lines; label texts excluded
        $labels = @("BB20", "PRE", "POST", "EUR", "USD", "CHF", "GBP", "OK", "EN", "DE")
        $used = New-Object System.Collections.Generic.HashSet[string]
        # V7.0: the UI script is split into the main file + ui\*.ps1 parts
        $uiFiles = @($ui) + @(Get-ChildItem -Path (Join-Path $PSScriptRoot "ui") -Filter *.ps1 -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.FullName })
        foreach ($line in ($uiFiles | ForEach-Object { Get-Content -Path $_ -Encoding UTF8 })) {
            if ($line -notmatch 'Set-Tip|Set-DynTip|addLeg|Legends\.Add|GlossaryShort|Spark = "SPARK"|addNum|addCombo|addCheck') { continue }
            foreach ($m in [regex]::Matches($line, '"([A-Z][A-Z0-9]{1,11})"')) {
                $k = $m.Groups[1].Value
                if ($labels -notcontains $k) { [void]$used.Add($k) }
            }
        }
        $used.Count | Should -BeGreaterThan 20
        @($used | Where-Object { $keys -notcontains $_ }) | Should -BeNullOrEmpty
    }
}

Describe "FX history and yearly report (v4.0)" {
    BeforeAll {
        $script:Hist = @{
            "USD" = @{ Dates = @("2025-03-03", "2025-06-02", "2026-02-02"); Rates = @(1.25, 1.10, 1.20) }
            "CHF" = @{ Dates = @("2025-01-02"); Rates = @(0.94) }
        }
    }
    It "takes the rate of the last trading day on or before the date" {
        Get-FxRateOnDate -History $script:Hist -Currency "USD" -Date "2025-03-03" | Should -Be 1.25
        Get-FxRateOnDate -History $script:Hist -Currency "USD" -Date "2025-05-31" | Should -Be 1.25
        Get-FxRateOnDate -History $script:Hist -Currency "USD" -Date "2026-12-31" | Should -Be 1.20
        Get-FxRateOnDate -History $script:Hist -Currency "USD" -Date "2024-01-01" | Should -Be 1.25   # before the history: first rate
        Get-FxRateOnDate -History $script:Hist -Currency "eur" -Date "2026-01-01" | Should -Be 1.0
        [double]::IsNaN((Get-FxRateOnDate -History $script:Hist -Currency "JPY" -Date "2026-01-01")) | Should -BeTrue
    }
    It "converts between two foreign currencies via EUR" {
        $r = Convert-AmountOnDate -Amount 120 -From "USD" -To "CHF" -Date "2026-02-02" -History $script:Hist
        [math]::Round($r.Value, 6) | Should -Be 94
        $r.Approx | Should -BeFalse
    }
    It "uses today's rate and flags it when the history is missing" {
        $r = Convert-AmountOnDate -Amount 1000 -From "JPY" -To "EUR" -Date "2026-01-01" -History $script:Hist -FallbackFromEur @{ JPY = 160.0 }
        $r.Value | Should -Be 6.25
        $r.Approx | Should -BeTrue
    }
    It "parses Yahoo FX history (exchange-local dates, gaps skipped)" {
        $json = [PSCustomObject]@{ chart = [PSCustomObject]@{ result = @([PSCustomObject]@{
            meta = [PSCustomObject]@{ gmtoffset = 0 }
            timestamp = @(1767225600, 1767312000, 1767398400)
            indicators = [PSCustomObject]@{ quote = @([PSCustomObject]@{ close = @(1.17, $null, 1.18) }) }
        }) } }
        $h = ConvertFrom-YahooFxHistory -Json $json
        $h.Dates | Should -Be @("2026-01-01", "2026-01-03")
        $h.Rates | Should -Be @(1.17, 1.18)
        ConvertFrom-YahooFxHistory -Json $null | Should -BeNullOrEmpty
    }
    It "computes the result in EUR with the FX rate of each booking date" {
        $tx = @(
            [PSCustomObject]@{ Date = "2025-03-03"; Ticker = "NVDA"; Type = "Kauf";    Shares = 10; Price = 100; Fee = 0; Currency = "USD" }
            [PSCustomObject]@{ Date = "2026-02-02"; Ticker = "NVDA"; Type = "Verkauf"; Shares = 10; Price = 120; Fee = 0; Currency = "USD" }
        )
        $rep = Get-RealizedReport -Transactions $tx -Year 2026 -Base "EUR" -History $script:Hist
        @($rep.Rows).Count | Should -Be 1
        [math]::Round($rep.Rows[0].Proceeds, 6) | Should -Be 1000    # 1200 USD / 1.20
        [math]::Round($rep.Rows[0].Cost, 6) | Should -Be 800         # 1000 USD / 1.25
        [math]::Round($rep.Totals.Gains, 6) | Should -Be 200
        $rep.Totals.Losses | Should -Be 0
        @((Get-RealizedReport -Transactions $tx -Year 2025 -Base "EUR" -History $script:Hist).Rows).Count | Should -Be 0
    }
    It "keeps a moving average in the base currency (fees capitalised) across partial sells" {
        $tx = @(
            [PSCustomObject]@{ Date = "2025-03-03"; Ticker = "X"; Type = "Kauf";    Shares = 10; Price = 100; Fee = 5;  Currency = "USD" }   # 1005 / 1.25 = 804
            [PSCustomObject]@{ Date = "2025-06-02"; Ticker = "X"; Type = "Kauf";    Shares = 10; Price = 110; Fee = 0;  Currency = "USD" }   # 1100 / 1.10 = 1000
            [PSCustomObject]@{ Date = "2026-02-02"; Ticker = "X"; Type = "Verkauf"; Shares = 5;  Price = 120; Fee = 12; Currency = "USD" }
        )
        $rep = Get-RealizedReport -Transactions $tx -Year 2026 -Base "EUR" -History $script:Hist
        $r = $rep.Rows[0]
        [math]::Round($r.Cost, 6) | Should -Be 451        # (804 + 1000) / 20 * 5
        [math]::Round($r.Proceeds, 6) | Should -Be 500    # 600 / 1.20
        [math]::Round($r.Fee, 6) | Should -Be 10          # 12 / 1.20
        [math]::Round($r.Result, 6) | Should -Be 39
        [math]::Round($rep.Totals.SellFees, 6) | Should -Be 10
    }
    It "reports losses, dividends and EUR positions" {
        $tx = @(
            [PSCustomObject]@{ Date = "2026-01-10"; Ticker = "SAP.DE"; Type = "Kauf";      Shares = 2; Price = 200; Fee = 0; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-03-10"; Ticker = "SAP.DE"; Type = "Verkauf";   Shares = 2; Price = 150; Fee = 1; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-05-10"; Ticker = "SAP.DE"; Type = "Dividende"; Shares = 0; Price = 10;  Fee = 2.75; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-06-01"; Ticker = "MSFT";   Type = "Dividende"; Shares = 0; Price = 12;  Fee = 1.8; Currency = "USD" }
        )
        $rep = Get-RealizedReport -Transactions $tx -Year 2026 -Base "EUR" -History $script:Hist
        @($rep.Rows).Count | Should -Be 3
        $rep.Totals.Losses | Should -Be -101
        [math]::Round($rep.Totals.DividendsGross, 6) | Should -Be 20        # 10 + 12 / 1.20
        [math]::Round($rep.Totals.DividendFees, 6) | Should -Be 4.25       # 2.75 + 1.8 / 1.20
        [math]::Round($rep.Totals.Net, 6) | Should -Be -85.25
        $rep.Rows[0].Date | Should -Be "2026-03-10"
    }
    It "clamps a sale larger than the booked holding and warns" {
        $tx = @(
            [PSCustomObject]@{ Date = "2026-01-02"; Ticker = "X"; Type = "Kauf";    Shares = 1; Price = 10; Fee = 0; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-01-03"; Ticker = "X"; Type = "Verkauf"; Shares = 3; Price = 12; Fee = 0; Currency = "EUR" }
        )
        $rep = Get-RealizedReport -Transactions $tx -Year 2026
        $rep.Rows[0].Shares | Should -Be 1
        $rep.Totals.Gains | Should -Be 2
        @($rep.Warnings).Count | Should -Be 1
    }
    It "flags rows converted with today's rate" {
        $tx = @(
            [PSCustomObject]@{ Date = "2026-01-02"; Ticker = "Y"; Type = "Kauf";    Shares = 1; Price = 1000; Fee = 0; Currency = "JPY" }
            [PSCustomObject]@{ Date = "2026-02-02"; Ticker = "Y"; Type = "Verkauf"; Shares = 1; Price = 1600; Fee = 0; Currency = "JPY" }
        )
        $rep = Get-RealizedReport -Transactions $tx -Year 2026 -History $script:Hist -FallbackFromEur @{ JPY = 160.0 }
        $rep.Rows[0].Approx | Should -BeTrue
        [math]::Round($rep.Totals.Gains, 6) | Should -Be 3.75
        @($rep.Warnings).Count | Should -Be 1
    }
    It "lists the currencies whose history is needed" {
        $tx = @(
            [PSCustomObject]@{ Date = "2025-01-02"; Ticker = "A"; Type = "Kauf"; Currency = "USD" }
            [PSCustomObject]@{ Date = "2027-01-02"; Ticker = "B"; Type = "Kauf"; Currency = "JPY" }
            [PSCustomObject]@{ Date = "2026-01-02"; Ticker = "C"; Type = "Kauf"; Currency = "EUR" }
        )
        @(Get-ReportCurrencies -Transactions $tx -Year 2026 -Base "CHF") | Should -Be @("CHF", "USD")
        Get-EarliestBookingDate -Transactions $tx | Should -Be "2025-01-02"
    }
}

# ==============================================================================
# v4.1: portfolio analytics
# ==============================================================================
Describe "Stock splits (v4.1)" {
    BeforeAll {
        $script:Spl = @{ "NVDA" = @([PSCustomObject]@{ Date = "2024-06-10"; Ratio = 10.0 }) }
        $script:SplTx = @(
            [PSCustomObject]@{ Date = "2024-01-02"; Ticker = "NVDA"; Type = "Kauf";    Shares = 10; Price = 1000; Fee = 0; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-02-02"; Ticker = "NVDA"; Type = "Verkauf"; Shares = 50; Price = 130;  Fee = 0; Currency = "EUR" }
        )
    }
    It "rebuilds a position across a split" {
        $p = Get-PositionFromTransactions -Transactions $script:SplTx -Ticker "NVDA" -Splits $script:Spl
        $p.Shares | Should -Be 50
        $p.AvgPrice | Should -Be 100
        $p.Realized | Should -Be 1500
        $p.Clamped | Should -BeFalse
        $p.Splits | Should -Be 1
    }
    It "applies a split after the last booking to today's holding" {
        $tx = @([PSCustomObject]@{ Date = "2024-01-02"; Ticker = "NVDA"; Type = "Kauf"; Shares = 3; Price = 500; Fee = 0; Currency = "EUR" })
        $p = Get-PositionFromTransactions -Transactions $tx -Ticker "NVDA" -Splits $script:Spl
        $p.Shares | Should -Be 30
        $p.AvgPrice | Should -Be 50
    }
    It "does not clamp a post-split sale in the yearly report" {
        $rep = Get-RealizedReport -Transactions $script:SplTx -Year 2026 -Splits $script:Spl
        @($rep.Warnings).Count | Should -Be 0
        $rep.Rows[0].Shares | Should -Be 50
        $rep.Totals.Gains | Should -Be 1500    # 50 x 130 - 50 x (10000 / 100)
    }
    It "sorts split events and ignores invalid ones" {
        $s = @{ "X" = @(@{ Date = "2025-01-01"; Ratio = 2.0 }, @{ Date = "2020-01-01"; Ratio = 4.0 }, @{ Date = "2021-01-01"; Ratio = 0 }) }
        $ev = @(Get-SplitEvents -Splits $s -Ticker "x")
        $ev.Count | Should -Be 2
        $ev[0].Date | Should -Be "2020-01-01"
        @(Get-SplitEvents -Splits $s -Ticker "Y").Count | Should -Be 0
    }
}

Describe "Daily history and alignment (v4.1)" {
    It "parses closes, pence, splits and dividends" {
        $json = [PSCustomObject]@{ chart = [PSCustomObject]@{ result = @([PSCustomObject]@{
            meta = [PSCustomObject]@{ gmtoffset = 0; currency = "GBp" }
            timestamp = @(1767225600, 1767312000, 1767398400)
            indicators = [PSCustomObject]@{ quote = @([PSCustomObject]@{ close = @(1000.0, $null, 1010.0) }) }
            events = [PSCustomObject]@{
                splits = [PSCustomObject]@{ "1767312000" = [PSCustomObject]@{ date = 1767312000; numerator = 4; denominator = 1 } }
                dividends = [PSCustomObject]@{ "1767225600" = [PSCustomObject]@{ date = 1767225600; amount = 25.0 } }
            }
        }) } }
        $h = ConvertFrom-YahooDailyHistory -Json $json
        $h.Currency | Should -Be "GBP"
        $h.Dates | Should -Be @("2026-01-01", "2026-01-03")
        $h.Closes | Should -Be @(10.0, 10.1)
        $h.Splits[0].Date | Should -Be "2026-01-02"
        $h.Splits[0].Ratio | Should -Be 4
        $h.Dividends[0].Amount | Should -Be 0.25
        ConvertFrom-YahooDailyHistory -Json $null | Should -BeNullOrEmpty
    }
    It "aligns a history to a date axis (last value on or before)" {
        $a = Get-AlignedSeries -Target @("2026-01-01", "2026-01-03", "2026-01-04", "2026-01-09") -Dates @("2026-01-02", "2026-01-04", "2026-01-08") -Values @(1.0, 2.0, 3.0)
        $a | Should -Be @(1.0, 1.0, 2.0, 3.0)
        [double]::IsNaN((Get-AlignedSeries -Target @("2026-01-01") -Dates @() -Values @())[0]) | Should -BeTrue
    }
    It "looks up a single date" {
        Get-HistoryValueOnDate -Dates @("2026-01-02", "2026-01-05") -Values @(5.0, 6.0) -Date "2026-01-04" | Should -Be 5
        Get-HistoryValueOnDate -Dates @("2026-01-02", "2026-01-05") -Values @(5.0, 6.0) -Date "2026-01-01" | Should -Be 5
    }
    It "builds FX factors to the base currency, with fallback" {
        $hist = @{ "USD" = @{ Dates = @("2026-01-01", "2026-01-02"); Rates = @(1.25, 1.20) } }
        $f = Get-AlignedFxToBase -Target @("2026-01-01", "2026-01-02") -Currency "USD" -Base "EUR" -History $hist
        $f.Factor | Should -Be @(0.8, (1 / 1.2))
        $f.Approx | Should -BeFalse
        $g = Get-AlignedFxToBase -Target @("2026-01-01") -Currency "JPY" -Base "EUR" -History $hist -FallbackFromEur @{ JPY = 160.0 }
        $g.Factor[0] | Should -Be 0.00625
        $g.Approx | Should -BeTrue
    }
}

Describe "Ledger and XIRR (v4.1)" {
    BeforeAll {
        $script:H41 = @{ "USD" = @{ Dates = @("2025-03-03", "2025-06-02", "2026-02-02"); Rates = @(1.25, 1.10, 1.20) } }
    }
    It "replays all bookings in the base currency with cash flows" {
        $tx = @(
            [PSCustomObject]@{ Date = "2025-03-03"; Ticker = "X"; Type = "Kauf";      Shares = 10; Price = 100; Fee = 5;  Currency = "USD" }
            [PSCustomObject]@{ Date = "2025-06-02"; Ticker = "X"; Type = "Kauf";      Shares = 10; Price = 110; Fee = 0;  Currency = "USD" }
            [PSCustomObject]@{ Date = "2026-02-02"; Ticker = "X"; Type = "Verkauf";   Shares = 5;  Price = 120; Fee = 12; Currency = "USD" }
            [PSCustomObject]@{ Date = "2026-02-02"; Ticker = "X"; Type = "Dividende"; Shares = 0;  Price = 24;  Fee = 6;  Currency = "USD" }
        )
        $l = (Get-PortfolioLedger -Transactions $tx -Base "EUR" -History $script:H41 -AsOf "2026-03-01")["X"]
        $l.Shares | Should -Be 15
        [math]::Round($l.Cost, 6) | Should -Be 1353         # 1804 - 451
        [math]::Round($l.Realized, 6) | Should -Be 39
        [math]::Round($l.Dividends, 6) | Should -Be 15      # 18 / 1.20
        [math]::Round($l.Bought, 6) | Should -Be 1804
        $l.FirstDate | Should -Be "2025-03-03"
        $l.CfAmounts.Count | Should -Be 4
        ($l.CfKinds -join "") | Should -Be "BBSD"
        [math]::Round(($l.CfAmounts | Measure-Object -Sum).Sum, 6) | Should -Be (-1804 + 490 + 15)
    }
    It "scales today's shares by splits after the last booking" {
        $tx = @([PSCustomObject]@{ Date = "2024-01-02"; Ticker = "NVDA"; Type = "Kauf"; Shares = 3; Price = 500; Fee = 0; Currency = "EUR" })
        $l = (Get-PortfolioLedger -Transactions $tx -Splits @{ "NVDA" = @([PSCustomObject]@{ Date = "2024-06-10"; Ratio = 10.0 }) } -AsOf "2026-01-01")["NVDA"]
        $l.Shares | Should -Be 30
        $l.Cost | Should -Be 1500
    }
    It "lists positions not covered by bookings" {
        $pf = @{ "A" = [PSCustomObject]@{ Shares = 10 }; "B" = [PSCustomObject]@{ Shares = 5 } }
        $lg = @{ "A" = [PSCustomObject]@{ Shares = 10.0 } }
        $u = @(Get-UncoveredPositions -Portfolio $pf -Ledger $lg)
        $u.Count | Should -Be 1
        $u[0].Ticker | Should -Be "B"
        $u[0].Missing | Should -Be 5
    }
    It "computes XIRR <Expected>" -TestCases @(
        @{ D = @("2025-01-01", "2026-01-01"); A = @(-1000.0, 1100.0); Expected = 0.1 }
        @{ D = @("2025-01-01", "2025-07-02", "2026-01-01"); A = @(-1000.0, -1000.0, 2200.0); Expected = 0.134627 }
        @{ D = @("2024-01-01", "2024-06-01", "2026-01-01"); A = @(-1000.0, 50.0, 800.0); Expected = -0.08136 }
    ) {
        [math]::Round((Get-Xirr -Dates $D -Amounts $A), 5) | Should -Be ([math]::Round($Expected, 5))
    }
    It "returns NaN without money in and out" {
        [double]::IsNaN((Get-Xirr -Dates @("2025-01-01", "2026-01-01") -Amounts @(-1.0, -2.0))) | Should -BeTrue
        [double]::IsNaN((Get-Xirr -Dates @("2025-01-01") -Amounts @(-1.0))) | Should -BeTrue
    }
}

Describe "Value history and benchmark (v4.1)" {
    It "rebuilds the value curve and the benchmark shadow portfolio" {
        $d = @("2026-01-02", "2026-01-05", "2026-01-06", "2026-01-07")
        $prices = @{ "X" = @{ Dates = $d; Closes = @(10.0, 11.0, 12.0, 13.0); Currency = "EUR"; Splits = @() } }
        $bench = @{ Dates = $d; Closes = @(100.0, 100.0, 110.0, 120.0); Currency = "EUR" }
        $tx = @(
            [PSCustomObject]@{ Date = "2026-01-02"; Ticker = "X"; Type = "Kauf";      Shares = 10; Price = 10; Fee = 0; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-01-06"; Ticker = "X"; Type = "Verkauf";   Shares = 5;  Price = 12; Fee = 0; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2026-01-07"; Ticker = "X"; Type = "Dividende"; Shares = 0;  Price = 3;  Fee = 1; Currency = "EUR" }
        )
        $v = Get-PortfolioValueSeries -Transactions $tx -Prices $prices -Benchmark $bench -EndDate "2026-01-07"
        $v.Dates | Should -Be $d
        $v.Value | Should -Be @(100.0, 110.0, 60.0, 65.0)
        $v.Invested | Should -Be @(100.0, 100.0, 40.0, 40.0)
        $v.Dividends | Should -Be @(0.0, 0.0, 0.0, 2.0)
        [math]::Round($v.Bench[2], 6) | Should -Be 50
        [math]::Round($v.Bench[3], 6) | Should -Be ([math]::Round(120 * (1 - 60 / 110), 6))
        @($v.Missing).Count | Should -Be 0
    }
    It "values pre-split bookings with split-adjusted closes" {
        $prices = @{ "S" = @{ Dates = @("2024-06-03", "2024-06-10", "2024-06-11"); Closes = @(10.0, 11.0, 12.0); Currency = "EUR"; Splits = @([PSCustomObject]@{ Date = "2024-06-10"; Ratio = 10.0 }) } }
        $tx = @(
            [PSCustomObject]@{ Date = "2024-06-03"; Ticker = "S"; Type = "Kauf";    Shares = 10; Price = 100; Fee = 0; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2024-06-11"; Ticker = "S"; Type = "Verkauf"; Shares = 50; Price = 12;  Fee = 0; Currency = "EUR" }
        )
        $v = Get-PortfolioValueSeries -Transactions $tx -Prices $prices -EndDate "2024-06-11"
        $v.Value | Should -Be @(1000.0, 1100.0, 600.0)
        $v.Bench | Should -BeNullOrEmpty
    }
    It "reports tickers without price history" {
        $tx = @([PSCustomObject]@{ Date = "2026-01-02"; Ticker = "Y"; Type = "Kauf"; Shares = 1; Price = 1; Fee = 0; Currency = "EUR" })
        Get-PortfolioValueSeries -Transactions $tx -Prices @{} -EndDate "2026-01-07" | Should -BeNullOrEmpty
        Get-PortfolioValueSeries -Transactions @() -Prices @{} | Should -BeNullOrEmpty
    }
    It "finds the start of a time window" {
        $d = @("2023-01-02", "2025-06-30", "2025-07-05", "2026-01-02")
        Get-SeriesWindowStart -Dates $d -Range "6M" | Should -Be 2
        Get-SeriesWindowStart -Dates $d -Range "1Y" | Should -Be 1
        Get-SeriesWindowStart -Dates $d -Range "Max" | Should -Be 0
    }
}

Describe "Allocation and profiles (v4.1)" {
    It "groups values and computes shares" {
        $g = @(Get-AllocationBreakdown -Items @(
            [PSCustomObject]@{ Key = "USD"; Value = 600 }, [PSCustomObject]@{ Key = "EUR"; Value = 300 },
            [PSCustomObject]@{ Key = "USD"; Value = 100 }, [PSCustomObject]@{ Key = ""; Value = 0 }, [PSCustomObject]@{ Key = ""; Value = 0.0001 }))
        $g[0].Key | Should -Be "USD"
        [math]::Round($g[0].Pct, 4) | Should -Be ([math]::Round(700 / 1000.0001 * 100, 4))
        $g.Count | Should -Be 3
        $g[2].Key | Should -Be "Unbekannt"
        @(Get-ConcentrationWarnings -Groups $g -ThresholdPct 20).Count | Should -Be 2
    }
    It "reads sector and country from quoteSummary and falls back to the search" {
        $sum = [PSCustomObject]@{ quoteSummary = [PSCustomObject]@{ result = @([PSCustomObject]@{
            assetProfile = [PSCustomObject]@{ sector = "Technology"; industry = "Semiconductors"; country = "United States" }
            quoteType = [PSCustomObject]@{ quoteType = "EQUITY"; longName = "NVIDIA Corporation" } }) } }
        $p = ConvertFrom-YahooProfile -Summary $sum -Search $null -Symbol "NVDA"
        $p.Sector | Should -Be "Technology"
        $p.Country | Should -Be "United States"
        $srch = [PSCustomObject]@{ quotes = @([PSCustomObject]@{ symbol = "abbn.sw"; quoteType = "EQUITY"; sectorDisp = "Industrials"; industryDisp = "Electrical Equipment"; longname = "ABB Ltd" }) }
        $q = ConvertFrom-YahooProfile -Summary $null -Search $srch -Symbol "ABBN.SW"
        $q.Sector | Should -Be "Industrials"
        $q.Country | Should -Be ""
        $q.Name | Should -Be "ABB Ltd"
    }
    It "prefers manual values, then Yahoo, then the instrument type" {
        $e = Get-EffectiveProfile ([PSCustomObject]@{ Sector = "Technology"; Country = "United States"; ManualCountry = "Taiwan"; QuoteType = "EQUITY" })
        $e.Sector | Should -Be "Technologie"
        $e.SectorSource | Should -Be "Yahoo"
        $e.Country | Should -Be "Taiwan"
        $e.CountrySource | Should -Be "manuell"
        $f = Get-EffectiveProfile ([PSCustomObject]@{ QuoteType = "ETF" })
        $f.Sector | Should -Be "ETF / Fonds"
        (Get-EffectiveProfile $null).Country | Should -Be "Unbekannt"
        Get-CountryLabel "Austria" | Should -Be "Österreich"
    }
    It "refreshes profiles older than 30 days" {
        $now = Get-Date "2026-11-23T12:00:00"
        Test-ProfileStale -Entry $null -Now $now | Should -BeTrue
        Test-ProfileStale -Entry ([PSCustomObject]@{ FetchedAt = "2026-11-01T12:00:00" }) -Now $now | Should -BeFalse
        Test-ProfileStale -Entry ([PSCustomObject]@{ FetchedAt = "2026-10-01T12:00:00" }) -Now $now | Should -BeTrue
    }
}

# ==============================================================================
# v4.2: buy dates, dividends, earnings
# ==============================================================================
Describe "Buy dates and opening bookings (v4.2)" {
    It "parses '<Text>' as '<Iso>'" -TestCases @(
        @{ Text = "24.11.2025"; Iso = "2025-11-24" }
        @{ Text = " 1.2.25 ";   Iso = "2025-02-01" }
        @{ Text = "2025-11-24"; Iso = "2025-11-24" }
        @{ Text = "24/11/2025"; Iso = "2025-11-24" }
        @{ Text = "31.02.2025"; Iso = "" }
        @{ Text = "gestern";    Iso = "" }
        @{ Text = "";           Iso = "" }
    ) {
        ConvertTo-IsoDate $Text | Should -Be $Iso
    }
    It "books the missing shares so that the average stays the same" {
        $o = Get-OpeningBooking -Shares 10 -AvgPrice 100 -BookedShares 4 -BookedAvg 90
        $o.Shares | Should -Be 6
        [math]::Round($o.Price, 6) | Should -Be ([math]::Round(640 / 6, 6))
        # replaying both buys gives the editor's average again
        $b = Get-BuyResult -OldShares 4 -OldAvg 90 -Shares $o.Shares -Price $o.Price -Fee 0
        [math]::Round($b.AvgPrice, 9) | Should -Be 100
    }
    It "uses the EK for a position without bookings and when the formula fails" {
        $o = Get-OpeningBooking -Shares 5 -AvgPrice 50
        $o.Shares | Should -Be 5
        $o.Price | Should -Be 50
        (Get-OpeningBooking -Shares 10 -AvgPrice 10 -BookedShares 5 -BookedAvg 30).Price | Should -Be 10
        Get-OpeningBooking -Shares 5 -AvgPrice 50 -BookedShares 5 -BookedAvg 50 | Should -BeNullOrEmpty
    }
}

Describe "Dividends (v4.2)" {
    BeforeAll {
        $script:Quarterly = @(
            [PSCustomObject]@{ Date = "2025-02-10"; Amount = 0.24 }
            [PSCustomObject]@{ Date = "2025-05-12"; Amount = 0.24 }
            [PSCustomObject]@{ Date = "2025-08-11"; Amount = 0.25 }
            [PSCustomObject]@{ Date = "2025-11-10"; Amount = 0.25 }
        )
    }
    It "detects a quarterly payer" {
        $s = Get-DividendStats -Dividends $script:Quarterly -AsOf "2025-11-23"
        $s.Frequency | Should -Be 4
        $s.FrequencyLabel | Should -Be "quartalsweise"
        [math]::Round($s.Trailing12, 6) | Should -Be 0.98
        [math]::Round($s.Annual, 6) | Should -Be 0.98
        $s.Last | Should -Be 0.25
        $s.NextEx | Should -Be "2026-02-10"
        $s.Stopped | Should -BeFalse
    }
    It "detects annual and monthly payers" {
        $a = Get-DividendStats -Dividends @(@{ Date = "2024-05-02"; Amount = 2.0 }, @{ Date = "2025-05-05"; Amount = 2.2 }) -AsOf "2025-11-23"
        $a.Frequency | Should -Be 1
        $a.Annual | Should -Be 2.2
        $a.NextEx | Should -Be "2026-05-05"
        $m = Get-DividendStats -Dividends @(@{ Date = "2025-09-01"; Amount = 0.1 }, @{ Date = "2025-10-01"; Amount = 0.1 }, @{ Date = "2025-11-03"; Amount = 0.1 }) -AsOf "2025-11-23"
        $m.Frequency | Should -Be 12
        [math]::Round($m.Annual, 6) | Should -Be 1.2     # fewer than 12 payments seen: latest x 12
    }
    It "treats a long pause as stopped" {
        $s = Get-DividendStats -Dividends @(@{ Date = "2022-05-02"; Amount = 1.0 }, @{ Date = "2023-05-02"; Amount = 1.0 }) -AsOf "2025-11-23"
        $s.Stopped | Should -BeTrue
        $s.Annual | Should -Be 0
        $s.NextEx | Should -Be ""
        @(Get-DividendProjection -Dividends @(@{ Date = "2023-05-02"; Amount = 1.0 }) -AsOf "2025-11-23").Count | Should -Be 0
        Get-DividendStats -Dividends @() | Should -BeNullOrEmpty
    }
    It "moves last year's payments forward by one year" {
        $p = @(Get-DividendProjection -Dividends $script:Quarterly -AsOf "2025-11-23")
        $p.Count | Should -Be 4
        ($p | ForEach-Object { $_.Date }) -join "," | Should -Be "2026-02-10,2026-05-12,2026-08-11,2026-11-10"
        $p[0].Amount | Should -Be 0.24
    }
    It "fills gaps in the history at the usual frequency" {
        $ev = @(
            @{ Date = "2024-08-01"; Amount = 0.2 }, @{ Date = "2024-11-01"; Amount = 0.2 },
            @{ Date = "2025-08-01"; Amount = 0.3 }, @{ Date = "2025-11-03"; Amount = 0.3 }
        )
        $p = @(Get-DividendProjection -Dividends $ev -AsOf "2025-11-23")
        ($p | ForEach-Object { $_.Date }) -join "," | Should -Be "2026-02-03,2026-05-03,2026-08-01,2026-11-03"
        $p[0].Amount | Should -Be 0.3
    }
    It "sorts amounts into 12 calendar months" {
        $b = @(Get-MonthlyBuckets -AsOf "2025-11-23" -Items @(
            @{ Date = "2025-11-30"; Value = 1 }, @{ Date = "2026-02-10"; Value = 2 }, @{ Date = "2026-02-20"; Value = 3 }, @{ Date = "2026-11-10"; Value = 9 }))
        $b.Count | Should -Be 12
        $b[0].Label | Should -Be "Nov 25"
        $b[0].Value | Should -Be 1
        $b[3].Month | Should -Be "2026-02"
        $b[3].Value | Should -Be 5
        $b[11].Label | Should -Be "Okt 26"
        (($b | ForEach-Object { $_.Value }) | Measure-Object -Sum).Sum | Should -Be 6
    }
}

Describe "Earnings and dividend dates (v4.2)" {
    It "reads quoteSummary calendarEvents and summaryDetail" {
        $sum = [PSCustomObject]@{ quoteSummary = [PSCustomObject]@{ result = @([PSCustomObject]@{
            calendarEvents = [PSCustomObject]@{
                earnings = [PSCustomObject]@{ earningsDate = @([PSCustomObject]@{ raw = 1764190800 }, [PSCustomObject]@{ raw = 1764622800 }) }
                exDividendDate = [PSCustomObject]@{ raw = 1765497600 }
                dividendDate = [PSCustomObject]@{ raw = 1765573200 }
            }
            summaryDetail = [PSCustomObject]@{ dividendRate = [PSCustomObject]@{ raw = 0.04 }; dividendYield = [PSCustomObject]@{ raw = 0.0002 }; trailingAnnualDividendRate = 0.04 }
        }) } }
        $c = ConvertFrom-YahooCalendar -Summary $sum -AsOf "2025-11-23"
        $c.EarningsDate | Should -Be "2025-11-26"
        $c.EarningsEnd | Should -Be "2025-12-01"
        $c.ExDividendDate | Should -Be "2025-12-12"
        $c.DividendDate | Should -Be "2025-12-12"
        $c.DividendRate | Should -Be 0.04
        $c.TrailingRate | Should -Be 0.04
        (ConvertFrom-YahooCalendar -Summary $null).EarningsDate | Should -Be ""
    }
    It "keeps only future earnings dates when there are any" {
        $sum = [PSCustomObject]@{ quoteSummary = [PSCustomObject]@{ result = @([PSCustomObject]@{
            calendarEvents = [PSCustomObject]@{ earnings = [PSCustomObject]@{ earningsDate = @([PSCustomObject]@{ raw = 1755648000 }) } } }) } }
        (ConvertFrom-YahooCalendar -Summary $sum -AsOf "2025-11-23").EarningsDate | Should -Be "2025-08-20"
    }
    It "shows a badge for <Date>: '<Text>'" -TestCases @(
        @{ Date = "2025-11-23"; Text = "heute" }
        @{ Date = "2025-11-24"; Text = "morgen" }
        @{ Date = "2025-11-26"; Text = "in 3 T" }
        @{ Date = "2025-12-10"; Text = "" }
        @{ Date = "2025-11-20"; Text = "" }
        @{ Date = "";           Text = "" }
    ) {
        $b = Get-EarningsBadge -EarningsDate $Date -AsOf "2025-11-23"
        if ($Text) { $b.Text | Should -Be $Text } else { $b | Should -BeNullOrEmpty }
    }
    It "refreshes events after 20 hours" {
        $now = Get-Date "2026-11-23T12:00:00"
        Test-EventsStale -Entry ([PSCustomObject]@{ FetchedAt = "2026-11-23T08:00:00" }) -Now $now | Should -BeFalse
        Test-EventsStale -Entry ([PSCustomObject]@{ FetchedAt = "2026-11-22T08:00:00" }) -Now $now | Should -BeTrue
        Test-EventsStale -Entry $null -Now $now | Should -BeTrue
    }
}

Describe "Opening bookings across splits (v4.2)" {
    It "converts today's shares to the units of the booking date" {
        $s = @{ "NVDA" = @([PSCustomObject]@{ Date = "2024-06-10"; Ratio = 10.0 }, [PSCustomObject]@{ Date = "2021-07-20"; Ratio = 4.0 }) }
        Get-SplitFactorAfter -Splits $s -Ticker "nvda" -Date "2023-01-02" | Should -Be 10
        Get-SplitFactorAfter -Splits $s -Ticker "NVDA" -Date "2020-01-02" | Should -Be 40
        Get-SplitFactorAfter -Splits $s -Ticker "NVDA" -Date "2024-06-10" | Should -Be 1
        # booked as 10 @ 150 in 2023 -> 100 @ 15 today
        $tx = @([PSCustomObject]@{ Date = "2023-01-02"; Ticker = "NVDA"; Type = "Kauf"; Shares = (100 / 10); Price = (15 * 10); Fee = 0; Currency = "USD" })
        $p = Get-PositionFromTransactions -Transactions $tx -Ticker "NVDA" -Splits $s
        $p.Shares | Should -Be 100
        $p.AvgPrice | Should -Be 15
    }
}

# ==============================================================================
# v4.3
# ==============================================================================
Describe "Alert kinds (v4.3)" {
    It "classifies <C> as <K>" -TestCases @(
        @{ C = "Depot Tag% <="; K = "PFPCT" }, @{ C = "Depot >="; K = "PFVAL" }, @{ C = "Tag% >="; K = "PCT" },
        @{ C = "Trailing %"; K = "TRAIL" }, @{ C = "EK% <="; K = "EKPCT" }, @{ C = "52W Hoch"; K = "HIGH52" },
        @{ C = "52W Tief"; K = "LOW52" }, @{ C = "Volumen x"; K = "VOL" }, @{ C = "<="; K = "PRICE" }
    ) {
        param($C, $K)
        Get-AlertKind $C | Should -Be $K
    }
    It "has a hint for every condition" {
        foreach ($c in Get-AlertConditions) { Get-AlertTargetHint $c | Should -Not -BeNullOrEmpty }
    }
}

Describe "Alert evaluation (v4.3)" {
    BeforeAll {
        function New-A { param([string]$C, [double]$T, [double]$Peak = [double]::NaN) [PSCustomObject]@{ Condition = $C; TargetPrice = $T; Currency = "EUR"; Peak = $Peak } }
    }
    It "price alert" {
        $r = Get-AlertEvaluation -Alert (New-A ">=" 100) -Ctx @{ Price = 101.0 }
        $r.Ok | Should -BeTrue; $r.Met | Should -BeTrue
        (Get-AlertEvaluation -Alert (New-A ">=" 100) -Ctx @{ Price = 99.0 }).Met | Should -BeFalse
    }
    It "is not ok without data" {
        (Get-AlertEvaluation -Alert (New-A ">=" 100) -Ctx @{}).Ok | Should -BeFalse
        (Get-AlertEvaluation -Alert (New-A "EK% >=" 10) -Ctx @{ Price = 100.0 }).Ok | Should -BeFalse
    }
    It "trailing stop follows the high and fires on the drop" {
        $a = New-A "Trailing %" 10
        $r1 = Get-AlertEvaluation -Alert $a -Ctx @{ Price = 100.0 }
        $r1.Peak | Should -Be 100; $r1.Met | Should -BeFalse
        $a.Peak = $r1.Peak
        $r2 = Get-AlertEvaluation -Alert $a -Ctx @{ Price = 120.0 }
        $r2.Peak | Should -Be 120; $r2.Met | Should -BeFalse
        $a.Peak = $r2.Peak
        (Get-AlertEvaluation -Alert $a -Ctx @{ Price = 109.0 }).Met | Should -BeFalse
        $r4 = Get-AlertEvaluation -Alert $a -Ctx @{ Price = 108.0 }
        $r4.Met | Should -BeTrue
        $r4.Peak | Should -Be 120
        [math]::Round($r4.Value, 2) | Should -Be -10
    }
    It "percent from average cost" {
        $r = Get-AlertEvaluation -Alert (New-A "EK% >=" 20) -Ctx @{ Price = 121.0; AvgCost = 100.0 }
        $r.Met | Should -BeTrue
        [math]::Round($r.Value, 1) | Should -Be 21
        (Get-AlertEvaluation -Alert (New-A "EK% <=" -10) -Ctx @{ Price = 95.0; AvgCost = 100.0 }).Met | Should -BeFalse
        (Get-AlertEvaluation -Alert (New-A "EK% <=" -10) -Ctx @{ Price = 89.0; AvgCost = 100.0 }).Met | Should -BeTrue
    }
    It "52-week high with tolerance" {
        (Get-AlertEvaluation -Alert (New-A "52W Hoch" 0) -Ctx @{ QuotePrice = 199.0; High52 = 200.0 }).Met | Should -BeFalse
        (Get-AlertEvaluation -Alert (New-A "52W Hoch" 0) -Ctx @{ QuotePrice = 200.0; High52 = 200.0 }).Met | Should -BeTrue
        (Get-AlertEvaluation -Alert (New-A "52W Hoch" 1) -Ctx @{ QuotePrice = 198.5; High52 = 200.0 }).Met | Should -BeTrue
        (Get-AlertEvaluation -Alert (New-A "52W Tief" 2) -Ctx @{ QuotePrice = 51.0; Low52 = 50.0 }).Met | Should -BeTrue
        (Get-AlertEvaluation -Alert (New-A "52W Tief" 2) -Ctx @{ QuotePrice = 52.0; Low52 = 50.0 }).Met | Should -BeFalse
    }
    It "volume spike and portfolio alerts" {
        (Get-AlertEvaluation -Alert (New-A "Volumen x" 2) -Ctx @{ RelVol = 2.4 }).Met | Should -BeTrue
        (Get-AlertEvaluation -Alert (New-A "Volumen x" 2) -Ctx @{ RelVol = [double]::NaN }).Ok | Should -BeFalse
        (Get-AlertEvaluation -Alert (New-A "Depot >=" 50000) -Ctx @{ PfValue = 50100.0 }).Met | Should -BeTrue
        (Get-AlertEvaluation -Alert (New-A "Depot Tag% <=" -2) -Ctx @{ PfDayPct = -2.5 }).Met | Should -BeTrue
        (Get-AlertEvaluation -Alert (New-A "Depot Tag% <=" -2) -Ctx @{ PfDayPct = -1.5 }).Met | Should -BeFalse
        Test-PortfolioAlertKind "PFVAL" | Should -BeTrue
        Test-PortfolioAlertKind "PRICE" | Should -BeFalse
    }
    It "keeps the v3 behaviour for day%, RSI and SMA" {
        (Get-AlertEvaluation -Alert (New-A "Tag% <=" -3) -Ctx @{ ChangePct = -3.2 }).Met | Should -BeTrue
        (Get-AlertEvaluation -Alert (New-A "RSI >=" 70) -Ctx @{ Rsi = 71.0; RsiPeriod = 14 }).Met | Should -BeTrue
        (Get-AlertEvaluation -Alert (New-A "> SMA" 0) -Ctx @{ QuotePrice = 10.0; Sma = 9.0; SmaPeriod = 20 }).Met | Should -BeTrue
        (Get-AlertEvaluation -Alert (New-A "< SMA" 0) -Ctx @{ QuotePrice = 10.0; Sma = 9.0; SmaPeriod = 20 }).Met | Should -BeFalse
    }
}

Describe "Relative volume (v4.3)" {
    It "compares today with the same time of the previous days" {
        $d0 = 1700000000 - (1700000000 % 86400)
        $ts = @(); $vol = @()
        foreach ($day in 0..2) {
            foreach ($h in 0..5) { $ts += [long]($d0 + $day * 86400 + 50400 + $h * 3600); $vol += 100.0 }
        }
        # today: two hours so far with 300 each -> 600 vs 200 usual
        $ts += [long]($d0 + 3 * 86400 + 50400); $vol += 300.0
        $ts += [long]($d0 + 3 * 86400 + 54000); $vol += 300.0
        [math]::Round((Get-RelativeVolume -Ts $ts -Vol $vol -GmtOffset 0), 2) | Should -Be 3
    }
    It "is NaN with only one day" {
        [double]::IsNaN((Get-RelativeVolume -Ts @(1000L, 4600L) -Vol @(1.0, 2.0))) | Should -BeTrue
    }
}

Describe "Quiet hours and expiry (v4.3)" {
    It "quiet <From>-<To> at <At> = <Exp>" -TestCases @(
        @{ From = "22:00"; To = "07:00"; At = "23:30"; Exp = $true }, @{ From = "22:00"; To = "07:00"; At = "06:59"; Exp = $true },
        @{ From = "22:00"; To = "07:00"; At = "07:00"; Exp = $false }, @{ From = "12:00"; To = "13:00"; At = "12:30"; Exp = $true },
        @{ From = "12:00"; To = "13:00"; At = "13:30"; Exp = $false }, @{ From = ""; To = ""; At = "03:00"; Exp = $false },
        @{ From = "08:00"; To = "08:00"; At = "08:00"; Exp = $false }
    ) {
        param($From, $To, $At, $Exp)
        Test-QuietHours -From $From -To $To -Now ([DateTime]::Parse("2026-11-23 $At", [System.Globalization.CultureInfo]::InvariantCulture)) | Should -Be $Exp
    }
    It "computes expiry dates and checks them" {
        $now = [DateTime]::new(2026, 1, 31, 10, 0, 0)
        Get-AlertExpiryDate -Days 0 -Now $now | Should -Be ""
        Get-AlertExpiryDate -Days 1 -Now $now | Should -Be "2026-01-31"
        Get-AlertExpiryDate -Days 7 -Now $now | Should -Be "2026-02-07"
        Get-AlertExpiryDate -Days 31 -Now $now | Should -Be "2026-02-28"
        $a = [PSCustomObject]@{ ExpiresAt = "2026-01-31" }
        Test-AlertExpired -Alert $a -Now $now | Should -BeFalse
        Test-AlertExpired -Alert $a -Now $now.AddDays(1) | Should -BeTrue
        Test-AlertExpired -Alert ([PSCustomObject]@{ ExpiresAt = "" }) -Now $now | Should -BeFalse
        @((Get-AlertExpiryChoices).Keys).Count | Should -Be 5
    }
}

Describe "Phone push (v4.3)" {
    It "builds an ntfy request" {
        $r = New-PushRequest -Service "ntfy" -Title "Alarm: NVDA" -Message "Kurs 120 über 118" -Server "https://ntfy.sh/" -Topic "tw-abc123" -Priority 4 -Tags @("bell")
        $r.Url | Should -Be "https://ntfy.sh"
        $j = $r.Json | ConvertFrom-Json
        $j.topic | Should -Be "tw-abc123"
        $j.title | Should -Be "Alarm: NVDA"
        $j.priority | Should -Be 4
        @($j.tags)[0] | Should -Be "bell"
    }
    It "keeps umlauts in the JSON" {
        $r = New-PushRequest -Service "ntfy" -Title "Ä" -Message "Größer" -Topic "t1"
        ($r.Json | ConvertFrom-Json).message | Should -Be "Größer"
    }
    It "refuses bad ntfy topics and servers" {
        New-PushRequest -Service "ntfy" -Title "x" -Message "y" -Topic "" | Should -BeNullOrEmpty
        New-PushRequest -Service "ntfy" -Title "x" -Message "y" -Topic "a/b" | Should -BeNullOrEmpty
        New-PushRequest -Service "ntfy" -Title "x" -Message "y" -Topic "ok" -Server "ftp://x" | Should -BeNullOrEmpty
    }
    It "builds a Telegram request" {
        $r = New-PushRequest -Service "Telegram" -Title "T" -Message "M" -Token "123456:AAbb-cc_DD" -ChatId "-100987"
        $r.Url | Should -Be "https://api.telegram.org/bot123456:AAbb-cc_DD/sendMessage"
        $j = $r.Json | ConvertFrom-Json
        $j.chat_id | Should -Be "-100987"
        $j.text | Should -Be "T`nM"
    }
    It "refuses incomplete Telegram settings and unknown services" {
        New-PushRequest -Service "Telegram" -Title "T" -Message "M" -Token "bad" -ChatId "1" | Should -BeNullOrEmpty
        New-PushRequest -Service "Telegram" -Title "T" -Message "M" -Token "1:a" -ChatId "abc" | Should -BeNullOrEmpty
        New-PushRequest -Service "Aus" -Title "T" -Message "M" | Should -BeNullOrEmpty
    }
    It "finds the chat id in getUpdates" {
        $j = '{"ok":true,"result":[{"update_id":1,"message":{"chat":{"id":111}}},{"update_id":2,"message":{"chat":{"id":222}}}]}' | ConvertFrom-Json
        Get-TelegramChatId $j | Should -Be "222"
        Get-TelegramChatId ('{"ok":true,"result":[]}' | ConvertFrom-Json) | Should -Be ""
    }
    It "limits pushes per minute" {
        $now = Get-Date
        $sent = @(1..10 | ForEach-Object { $now.AddSeconds(-$_) })
        Test-PushAllowed -Sent $sent -Now $now -Max 10 | Should -BeFalse
        Test-PushAllowed -Sent @($now.AddMinutes(-5)) -Now $now -Max 10 | Should -BeTrue
        Test-PushAllowed -Sent @() -Now $now | Should -BeTrue
    }
    It "makes random topics" {
        $t = New-RandomTopic
        $t | Should -Match '^tw-[a-z0-9]{12}$'
        (New-PushRequest -Service "ntfy" -Title "x" -Message "y" -Topic $t) | Should -Not -BeNullOrEmpty
    }
}

# ==============================================================================
# v4.4
# ==============================================================================
Describe "Terminal commands (v4.4)" {
    It "parses <Text>" -TestCases @(
        @{ Text = "nvda gp 1y"; Kind = "Ticker"; Ticker = "NVDA"; Func = "GP"; Rest = "1Y" },
        @{ Text = "CAL"; Kind = "Global"; Ticker = ""; Func = "CAL"; Rest = "" },
        @{ Text = "  SAP.DE  "; Kind = "Ticker"; Ticker = "SAP.DE"; Func = ""; Rest = "" },
        @{ Text = "N"; Kind = "Global"; Ticker = ""; Func = "N"; Rest = "" },
        @{ Text = "AAPL N"; Kind = "Ticker"; Ticker = "AAPL"; Func = "N"; Rest = "" },
        @{ Text = "tf 3m"; Kind = "Global"; Ticker = ""; Func = "TF"; Rest = "3m" },
        @{ Text = "^GSPC GP"; Kind = "Ticker"; Ticker = "^GSPC"; Func = "GP"; Rest = "" },
        @{ Text = "NVDA ALRT >= 150"; Kind = "Ticker"; Ticker = "NVDA"; Func = "ALRT"; Rest = ">=,150" }
    ) {
        param($Text, $Kind, $Ticker, $Func, $Rest)
        $r = ConvertFrom-TerminalCommand $Text
        $r.Kind | Should -Be $Kind
        $r.Ticker | Should -Be $Ticker
        $r.Func | Should -Be $Func
        (@($r.Args) -join ",") | Should -Be $Rest
    }
    It "reports errors" {
        (ConvertFrom-TerminalCommand "GP").Kind | Should -Be "Error"
        (ConvertFrom-TerminalCommand "NVDA XYZ").Kind | Should -Be "Error"
        (ConvertFrom-TerminalCommand "NVDA PORT").Kind | Should -Be "Error"
        (ConvertFrom-TerminalCommand "hallo welt!").Kind | Should -Be "Error"
        (ConvertFrom-TerminalCommand "").Kind | Should -Be "Empty"
    }
    It "reads alert shorthand <A>" -TestCases @(
        @{ A = ">=,150"; C = ">="; V = 150 }, @{ A = ">=150,5"; C = ">="; V = 150.5 }, @{ A = "TRAIL,8%"; C = "Trailing %"; V = 8 },
        @{ A = "TAG-,3"; C = "Tag% <="; V = -3 }, @{ A = "EK+,20"; C = "EK% >="; V = 20 }, @{ A = "52H"; C = "52W Hoch"; V = 0 },
        @{ A = "VOL,2x"; C = "Volumen x"; V = 2 }, @{ A = "SMA+"; C = "> SMA"; V = 0 }, @{ A = "DTAG-,2"; C = "Depot Tag% <="; V = -2 }
    ) {
        param($A, $C, $V)
        $r = ConvertFrom-AlertShorthand -ArgList ($A -split ',', 2 | ForEach-Object { $_ } | Where-Object { $_ })
        if ($A -eq ">=150,5") { $r = ConvertFrom-AlertShorthand -ArgList @(">=150,5") }
        $r.Condition | Should -Be $C
        [double]$r.Value | Should -Be $V
    }
    It "refuses unknown or incomplete alerts" {
        ConvertFrom-AlertShorthand -ArgList @("FOO", "1") | Should -BeNullOrEmpty
        ConvertFrom-AlertShorthand -ArgList @(">=") | Should -BeNullOrEmpty
        ConvertFrom-AlertShorthand -ArgList @(">=", "abc") | Should -BeNullOrEmpty
        ConvertFrom-AlertShorthand -ArgList @() | Should -BeNullOrEmpty
    }
    It "suggests globals, tickers and functions" {
        $s = @(Get-CommandSuggestions -Text "" -Recent @("NVDA GP"))
        $s[0].Text | Should -Be "NVDA GP"
        @($s.Text) | Should -Contain "PORT"
        @(Get-CommandSuggestions -Text "NV" -Tickers @("NVDA", "MSFT")).Text | Should -Contain "NVDA"
        @(Get-CommandSuggestions -Text "NV" -Tickers @("NVDA", "MSFT")).Text | Should -Not -Contain "MSFT"
        $f = @(Get-CommandSuggestions -Text "NVDA " -Max 30).Text
        $f | Should -Contain "NVDA GP"
        $f | Should -Contain "NVDA DES"
        $f | Should -Not -Contain "NVDA PORT"
        @(Get-CommandSuggestions -Text "NVDA D").Text -join "," | Should -Be "NVDA DES,NVDA DVD"
        @(Get-CommandSuggestions -Text "TF 1").Text -join "," | Should -Be "TF 1D,TF 1M,TF 1Y"
        @(Get-CommandSuggestions -Text "NVDA ALRT ").Text | Should -Contain "NVDA ALRT TRAIL 8"
    }
    It "keeps a recent list without duplicates" {
        $r = Add-RecentCommand -Recent @("A GP", "CAL") -Command "cal"
        ($r -join ",") | Should -Be "CAL,A GP"
        @(Add-RecentCommand -Recent @(1..30 | ForEach-Object { "X$_" }) -Command "NEW").Count | Should -Be 20
    }
}

Describe "News, calendar, polling, versions (v4.4)" {
    It "reads Yahoo news, newest first" {
        $j = '{"news":[{"title":"Alt","publisher":"P1","link":"https://a.example/1","providerPublishTime":1700000000,"relatedTickers":["NVDA"]},{"title":"Neu","publisher":"P2","link":"javascript:x","providerPublishTime":1700003600},{"publisher":"no title"}]}' | ConvertFrom-Json
        $n = @(ConvertFrom-YahooNews $j)
        $n.Count | Should -Be 2
        $n[0].Title | Should -Be "Neu"
        $n[0].Link | Should -Be ""
        $n[1].Tickers[0] | Should -Be "NVDA"
        @(ConvertFrom-YahooNews $null).Count | Should -Be 0
    }
    It "lists upcoming events in order" {
        $ev = @{
            "NVDA" = [PSCustomObject]@{ EarningsDate = "2026-12-01"; ExDividendDate = "2026-11-20"; DividendDate = "2026-12-05" }
            "MSFT" = [PSCustomObject]@{ EarningsDate = "2026-11-25"; ExDividendDate = ""; DividendDate = "" }
            "FAR"  = [PSCustomObject]@{ EarningsDate = "2027-06-01"; ExDividendDate = ""; DividendDate = "" }
        }
        $c = @(Get-EventCalendar -Events $ev -Symbols @("nvda", "MSFT", "FAR", "NONE") -AsOf "2026-11-23" -Days 60)
        ($c | ForEach-Object { "{0} {1} {2}" -f $_.Date, $_.Ticker, $_.Kind }) -join "|" | Should -Be "2026-11-25 MSFT Quartalszahlen|2026-12-01 NVDA Quartalszahlen|2026-12-05 NVDA Zahltag"
        $c[0].Days | Should -Be 2
    }
    It "skips polls only while every market is closed" {
        $now = Get-Date
        Test-ClosedPollSkip -States @("CLOSED", "CLOSED") -LastData $now.AddMinutes(-3) -ClosedMinutes 10 -Now $now | Should -BeTrue
        Test-ClosedPollSkip -States @("CLOSED", "CLOSED") -LastData $now.AddMinutes(-11) -ClosedMinutes 10 -Now $now | Should -BeFalse
        Test-ClosedPollSkip -States @("CLOSED", "OPEN24") -LastData $now -ClosedMinutes 10 -Now $now | Should -BeFalse
        Test-ClosedPollSkip -States @("CLOSED") -LastData $now -ClosedMinutes 0 -Now $now | Should -BeFalse
        Test-ClosedPollSkip -States @() -LastData $now -ClosedMinutes 10 -Now $now | Should -BeFalse
    }
    It "compares versions" {
        Compare-AppVersion "4.3" "4.10" | Should -Be -1
        Compare-AppVersion "v4.4" "4.4.0" | Should -Be 0
        Compare-AppVersion "5.0" "4.9.9" | Should -Be 1
        Get-LatestTagVersion ('[{"name":"v4.3"},{"name":"v4.10"},{"name":"test"},{"name":"v4.4.1"}]' | ConvertFrom-Json) | Should -Be "4.10"
        Get-LatestTagVersion @() | Should -Be ""
    }
}

# ==============================================================================
# v4.5
# ==============================================================================
Describe "CSV import (v4.5)" {
    It "splits quoted fields" {
        (Split-CsvLine -Line 'a;"b;c";"say ""hi""";' -Delimiter ";") -join "|" | Should -Be 'a|b;c|say "hi"|'
    }
    It "detects the delimiter" {
        Get-CsvDelimiter -Lines @("a;b;c", "1;2,5;3") | Should -Be ";"
        Get-CsvDelimiter -Lines @("a,b,c", "1,2.5,3") | Should -Be ","
        Get-CsvDelimiter -Lines @("a`tb`tc", "1`t2`t3") | Should -Be "`t"
    }
    It "skips a preamble and finds the header" {
        $txt = "Depotumsätze`r`nZeitraum: 2025`r`nDatum;Typ;ISIN;Stück;Kurs;Gebühr`r`n15.01.2025;Kauf;US67066G1040;10;120,50;1,00`r`n`r`n"
        $c = ConvertFrom-CsvText $txt
        $c.Headers -join "|" | Should -Be "Datum|Typ|ISIN|Stück|Kurs|Gebühr"
        @($c.Rows).Count | Should -Be 1
        $c.Rows[0][4] | Should -Be "120,50"
    }
    It "guesses columns" {
        $m = Get-CsvColumnGuess @("Buchungstag", "Transaktionsart", "Name", "ISIN", "Anzahl", "Ausführungskurs", "Betrag", "Provision", "Währung")
        $m.Date | Should -Be 0; $m.Type | Should -Be 1; $m.Name | Should -Be 2; $m.Ident | Should -Be 3
        $m.Shares | Should -Be 4; $m.Price | Should -Be 5; $m.Amount | Should -Be 6; $m.Fee | Should -Be 7; $m.Currency | Should -Be 8
        (Get-CsvColumnGuess @("foo", "bar")).Date | Should -Be -1
    }
    It "reads numbers <Raw>" -TestCases @(
        @{ Raw = "1.234,56"; V = 1234.56 }, @{ Raw = "1,234.56"; V = 1234.56 }, @{ Raw = "-12,5"; V = -12.5 },
        @{ Raw = "12 EUR"; V = 12 }, @{ Raw = "1.234.567"; V = 1234567 }, @{ Raw = "0.5"; V = 0.5 }
    ) {
        param($Raw, $V)
        ConvertFrom-CsvNumber $Raw | Should -Be $V
    }
    It "treats empty text as NaN" { [double]::IsNaN((ConvertFrom-CsvNumber "")) | Should -BeTrue; [double]::IsNaN((ConvertFrom-CsvNumber "abc")) | Should -BeTrue }
    It "maps broker wording <Raw> -> <T>" -TestCases @(
        @{ Raw = "Kauf"; T = "Kauf" }, @{ Raw = "BUY"; T = "Kauf" }, @{ Raw = "Sparplanausführung"; T = "Kauf" }, @{ Raw = "Verkauf"; T = "Verkauf" },
        @{ Raw = "SELL"; T = "Verkauf" }, @{ Raw = "Dividende"; T = "Dividende" }, @{ Raw = "Ausschüttung"; T = "Dividende" }, @{ Raw = "Einzahlung"; T = "Einzahlung" },
        @{ Raw = "Market buy"; T = "Kauf" }, @{ Raw = "Limit sell"; T = "Verkauf" }, @{ Raw = "Dividend (Ordinary)"; T = "Dividende" }, @{ Raw = "Interest on cash"; T = "Zinsen" },
        @{ Raw = "Withdrawal"; T = "Auszahlung" }, @{ Raw = "Currency conversion"; T = "" }
    ) {
        param($Raw, $T)
        ConvertFrom-CsvType $Raw | Should -Be $T
    }
    It "recognises ISINs" { Test-Isin "US67066G1040" | Should -BeTrue; Test-Isin "NVDA" | Should -BeFalse }
    It "converts rows to bookings" {
        $map = @{ Date = 0; Type = 1; Ident = 2; Shares = 3; Price = 4; Amount = 5; Fee = 6; Tax = -1; Currency = 7; Name = -1 }
        $rows = @(
            ,@("15.01.2025", "Kauf", "US67066G1040", "10", "120,50", "", "1,00", "USD")
            ,@("2025-02-03T10:00:00", "Verkauf", "NVDA", "-4", "", "596,00", "4,00", "")
            ,@("20.03.2025", "Dividende", "US67066G1040", "10", "", "0,40", "", "USD")
            ,@("01.04.2025", "Einzahlung", "", "", "", "1000", "", "")
        )
        $b = @(ConvertFrom-BrokerRows -Rows $rows -Map $map -DefaultCurrency "EUR")
        $b[0].Date | Should -Be "2025-01-15"; $b[0].Type | Should -Be "Kauf"; $b[0].Shares | Should -Be 10; $b[0].Price | Should -Be 120.5; $b[0].Fee | Should -Be 1; $b[0].Currency | Should -Be "USD"; $b[0].Ok | Should -BeTrue
        $b[1].Date | Should -Be "2025-02-03"; $b[1].Shares | Should -Be 4; $b[1].Price | Should -Be 150; $b[1].Currency | Should -Be "EUR"
        $b[2].Type | Should -Be "Dividende"; $b[2].Price | Should -Be 0.4
        # v5.5: deposits are cash rows now (for the cash account)
        $b[3].Type | Should -Be "Einzahlung"; $b[3].Cash | Should -BeTrue; $b[3].Amount | Should -Be 1000; $b[3].Ok | Should -BeTrue
    }
    It "infers buy/sell from the sign without a type column" {
        $map = @{ Date = 0; Type = -1; Ident = 1; Shares = 2; Price = 3; Amount = -1; Fee = -1; Tax = -1; Currency = -1; Name = -1 }
        $b = @(ConvertFrom-BrokerRows -Rows @(,@("20240115", "AAPL", "-3", "180.5")) -Map $map)
        $b[0].Type | Should -Be "Verkauf"; $b[0].Date | Should -Be "2024-01-15"; $b[0].Shares | Should -Be 3
    }
    It "finds duplicates" {
        $ex = @([PSCustomObject]@{ Date = "2025-01-15"; Ticker = "NVDA"; Type = "Kauf"; Shares = 10.0; Price = 120.5 })
        Test-DuplicateTransaction -Existing $ex -New ([PSCustomObject]@{ Date = "2025-01-15"; Ticker = "nvda"; Type = "Kauf"; Shares = 10.0; Price = 120.9 }) | Should -BeTrue
        Test-DuplicateTransaction -Existing $ex -New ([PSCustomObject]@{ Date = "2025-01-15"; Ticker = "NVDA"; Type = "Kauf"; Shares = 11.0; Price = 120.5 }) | Should -BeFalse
        Test-DuplicateTransaction -Existing @() -New $ex[0] | Should -BeFalse
    }
    It "picks a symbol from the search" {
        $j = '{"quotes":[{"symbol":"NVD.DE","quoteType":"EQUITY","shortname":"NVIDIA"},{"symbol":"NVDA","quoteType":"EQUITY","shortname":"NVIDIA"},{"symbol":"X","quoteType":"OPTION"}]}' | ConvertFrom-Json
        Get-YahooSymbolFromSearch $j | Should -Be "NVD.DE"
        Get-YahooSymbolFromSearch $j -PreferSuffix "NVDA" | Should -Be "NVDA"
        Get-YahooSymbolFromSearch $null | Should -Be ""
    }
}

Describe "Depots and backups (v4.5)" {
    It "makes folder-safe ids" {
        ConvertTo-DepotId "Zweites Depot (Flatex)" | Should -Be "zweites-depot-flatex"
        ConvertTo-DepotId "Übungsdepot" | Should -Be "uebungsdepot"
        ConvertTo-DepotId "   " | Should -Be "depot"
    }
    It "reads backup folder names" {
        $i = Get-BackupInfo "20251124_093000_taeglich"
        $i.When | Should -Be ([DateTime]::new(2025, 11, 24, 9, 30, 0))
        $i.Reason | Should -Be "taeglich"
        (Get-BackupInfo "foo").When | Should -Be ([DateTime]::MinValue)
    }
}

# ==============================================================================
# v4.6
# ==============================================================================
Describe "EMA and MACD (v4.6)" {
    It "computes the EMA" {
        $e = Compute-Ema -Prices @(1.0, 2.0, 3.0, 4.0, 5.0) -Period 3
        [double]::IsNaN($e[1]) | Should -BeTrue
        $e[2] | Should -Be 2
        $e[3] | Should -Be 3
        $e[4] | Should -Be 4
        @(Compute-Ema -Prices @(1.0) -Period 3).Count | Should -Be 1
    }
    It "computes MACD, signal and histogram" {
        $p = [double[]]@(1..60 | ForEach-Object { 100 + [math]::Sin($_ / 3.0) * 5 + $_ * 0.2 })
        $m = Compute-Macd -Prices $p
        [double]::IsNaN($m.Macd[24]) | Should -BeTrue
        [double]::IsNaN($m.Macd[25]) | Should -BeFalse
        [double]::IsNaN($m.Signal[32]) | Should -BeTrue
        [double]::IsNaN($m.Signal[33]) | Should -BeFalse
        [math]::Round($m.Hist[50], 10) | Should -Be ([math]::Round($m.Macd[50] - $m.Signal[50], 10))
    }
    It "is flat for a constant series" {
        $m = Compute-Macd -Prices ([double[]]@(1..40 | ForEach-Object { 50.0 }))
        $m.Macd[39] | Should -Be 0
        $m.Hist[39] | Should -Be 0
    }
}

Describe "Colours, hotkeys, layout helpers (v4.6)" {
    It "converts hex colours" {
        (ConvertFrom-HexColor "#3B82F6") -join "," | Should -Be "59,130,246"
        (ConvertFrom-HexColor "ffffff") -join "," | Should -Be "255,255,255"
        ConvertFrom-HexColor "#12" | Should -BeNullOrEmpty
        ConvertTo-HexColor 59 130 246 | Should -Be "#3B82F6"
    }
    It "picks up/down colours" {
        (Get-UpDownColors "Farbenblind").Up -join "," | Should -Be "59,130,246"
        (Get-UpDownColors "Eigene" "#010203" "#040506").Down -join "," | Should -Be "4,5,6"
        (Get-UpDownColors "Eigene" "kaputt" "").Up -join "," | Should -Be "16,185,129"
        (Get-UpDownColors "Unbekannt").Down -join "," | Should -Be "244,63,94"
    }
    It "parses hotkey <T>" -TestCases @(
        @{ T = "Ctrl+Alt+W"; M = 3; K = 87 }, @{ T = "Strg+Umschalt+F9"; M = 6; K = 0x78 }, @{ T = "Win+Space"; M = 8; K = 0x20 }, @{ T = "alt+1"; M = 1; K = 49 }
    ) {
        param($T, $M, $K)
        $h = ConvertFrom-HotkeyText $T
        $h.Mods | Should -Be $M
        $h.Key | Should -Be $K
    }
    It "refuses hotkeys without modifier or with unknown parts" {
        ConvertFrom-HotkeyText "W" | Should -BeNullOrEmpty
        ConvertFrom-HotkeyText "Ctrl+Pfeil" | Should -BeNullOrEmpty
        ConvertFrom-HotkeyText "Hyper+W" | Should -BeNullOrEmpty
        ConvertFrom-HotkeyText "" | Should -BeNullOrEmpty
    }
    It "stores grid layouts" {
        $cols = @([PSCustomObject]@{ Name = "Ticker"; DisplayIndex = 1; FillWeight = 80.0; Visible = $true }, [PSCustomObject]@{ Name = "Spark"; DisplayIndex = 0; FillWeight = 60.0; Visible = $false })
        $l = @(ConvertTo-GridLayout $cols)
        $l[1].Name | Should -Be "Spark"; $l[1].Visible | Should -BeFalse; $l[0].Index | Should -Be 1
    }
    It "snaps to screen edges" {
        $r = Get-SnappedPosition -X 10 -Y 300 -W 400 -H 300 -AreaLeft 0 -AreaTop 0 -AreaRight 1920 -AreaBottom 1040
        $r.X | Should -Be 0; $r.Y | Should -Be 300; $r.Moved | Should -BeTrue
        $r2 = Get-SnappedPosition -X 1510 -Y 735 -W 400 -H 300 -AreaLeft 0 -AreaTop 0 -AreaRight 1920 -AreaBottom 1040
        $r2.X | Should -Be 1520; $r2.Y | Should -Be 740
        (Get-SnappedPosition -X 500 -Y 500 -W 400 -H 300 -AreaLeft 0 -AreaTop 0 -AreaRight 1920 -AreaBottom 1040).Moved | Should -BeFalse
    }
    It "knows when an undo has expired" {
        $now = Get-Date
        Test-UndoValid -Undo @{ Until = $now.AddSeconds(5) } -Now $now | Should -BeTrue
        Test-UndoValid -Undo @{ Until = $now.AddSeconds(-1) } -Now $now | Should -BeFalse
        Test-UndoValid -Undo $null | Should -BeFalse
    }
}

# ==============================================================================
# v4.7: UI smoke test - starts the real widget (only when TW_RUN_UI_SMOKE=1, as in CI)
# ==============================================================================
Describe "UI smoke test (v4.7)" -Tag "UI" {
    BeforeAll {
        $script:SmokeOn = ($env:TW_RUN_UI_SMOKE -eq "1")
    }
    It "starts the widget, opens every dialog and closes again without programming errors" {
        if (-not $script:SmokeOn) { Set-ItResult -Skipped -Because "set TW_RUN_UI_SMOKE=1 to run (opens windows)"; return }
        $ui = Join-Path $PSScriptRoot "TerminalWidget.ps1"
        $dir = Join-Path ([IO.Path]::GetTempPath()) ("tw_smoke_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [IO.File]::WriteAllText((Join-Path $dir "config.json"), '{"FirstRunDone": true, "Layout": "Standard", "Watchlist": ["NVDA", "MSFT", "SAP.DE"], "ActiveTicker": "NVDA"}', $utf8)
        [IO.File]::WriteAllText((Join-Path $dir "portfolio.json"), '{"NVDA": {"Ticker": "NVDA", "Shares": 10, "AvgPrice": 100, "Currency": "USD", "BuyAmount": 0, "TargetAvg": 0}, "MSFT": {"Ticker": "MSFT", "Shares": 5, "AvgPrice": 300, "Currency": "USD", "BuyAmount": 0, "TargetAvg": 0}}', $utf8)
        [IO.File]::WriteAllText((Join-Path $dir "transactions.json"), '[{"Id": "a", "Date": "2024-03-01", "Ticker": "NVDA", "Type": "Kauf", "Shares": 1, "Price": 800, "Fee": 1, "Currency": "USD", "Realized": 0, "Note": ""}, {"Id": "b", "Date": "2025-01-10", "Ticker": "MSFT", "Type": "Kauf", "Shares": 5, "Price": 300, "Fee": 1, "Currency": "USD", "Realized": 0, "Note": ""}, {"Id": "c", "Date": "2025-06-12", "Ticker": "MSFT", "Type": "Dividende", "Shares": 5, "Price": 4.15, "Fee": 0, "Currency": "USD", "Realized": 0, "Note": ""}]', $utf8)
        [IO.File]::WriteAllText((Join-Path $dir "alerts.json"), '[{"Id": "1", "Ticker": "NVDA", "Condition": ">=", "TargetPrice": 99999, "Currency": "EUR", "Triggered": false, "Note": "", "RearmMin": 0, "TriggeredAt": ""}]', $utf8)
        $report = Join-Path $dir "smoke-report.json"
        $env:TW_SMOKE_TEST = $report
        $env:TW_SMOKE_DIR = $dir
        try {
            $exe = (Get-Process -Id $PID).Path
            $p = Start-Process -FilePath $exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$ui`"") -PassThru
            $done = $p.WaitForExit(900000)
            if (-not $done) { try { $p.Kill() } catch { } }
        } finally {
            Remove-Item Env:\TW_SMOKE_TEST -ErrorAction SilentlyContinue
            Remove-Item Env:\TW_SMOKE_DIR -ErrorAction SilentlyContinue
        }
        $log = Join-Path $dir "widget.log"
        if (Test-Path $log) { Write-Host "---- widget.log (last 60 lines) ----"; Get-Content $log -Tail 60 | ForEach-Object { Write-Host $_ } }
        # v5.2: screenshots also into the log (base64), for reviews without artifact access
        if ($env:TW_SMOKE_SHOTS -and (Test-Path $env:TW_SMOKE_SHOTS)) {
            foreach ($png in Get-ChildItem -Path $env:TW_SMOKE_SHOTS -File | Where-Object { $_.Extension -in @(".png", ".html") }) {
                $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($png.FullName))
                Write-Host ("SHOT-BEGIN " + $png.Name)
                for ($i = 0; $i -lt $b64.Length; $i += 3000) { Write-Host ("SHOT|" + $b64.Substring($i, [math]::Min(3000, $b64.Length - $i))) }
                Write-Host ("SHOT-END " + $png.Name)
            }
        }
        $done | Should -BeTrue -Because "the widget must finish the smoke run within 15 minutes"
        Test-Path $report | Should -BeTrue -Because "the smoke run writes a report"
        $rep = Get-Content $report -Raw | ConvertFrom-Json
        foreach ($st in @($rep.Steps)) { Write-Host ("{0,-28} {1,-5} {2,6} ms {3}" -f $st.Name, $(if ($st.Ok) { "ok" } else { "FAIL" }), $st.Ms, $st.Error) }
        foreach ($n in @($rep.Notes)) { Write-Host "note: $n" }
        (@($rep.Failures) -join "`n") | Should -BeNullOrEmpty
        @($rep.Steps).Count | Should -BeGreaterThan 40
        $p.ExitCode | Should -Be 0
    }
}

# ==============================================================================
# v4.8
# ==============================================================================
Describe "Log scale and chart markers (v4.8)" {
    It "maps prices linearly" {
        Get-PriceFrac 150 100 100 | Should -Be 0.5
        Get-PriceFromFrac 0.5 100 100 | Should -Be 150
    }
    It "maps prices logarithmically" {
        # 10 .. 1000: 100 sits in the middle
        [math]::Round((Get-PriceFrac 100 10 990 $true), 6) | Should -Be 0.5
        [math]::Round((Get-PriceFromFrac 0.5 10 990 $true), 6) | Should -Be 100
        Get-PriceFrac 0 10 990 $true | Should -BeLessThan 0
        Get-PriceFrac 50 -10 100 $true | Should -Be 0.6
    }
    It "round-trips" {
        foreach ($v in @(12.5, 77.0, 640.0)) {
            [math]::Round((Get-PriceFromFrac (Get-PriceFrac $v 10 990 $true) 10 990 $true), 6) | Should -Be $v
        }
    }
    It "pads in log space" {
        $r = Get-LogPaddedRange 100 400
        $r.Min | Should -BeLessThan 100
        $r.Max | Should -BeGreaterThan 400
        [math]::Round([math]::Log(100 / $r.Min), 6) | Should -Be ([math]::Round([math]::Log($r.Max / 400), 6))
        Get-LogPaddedRange 0 10 | Should -BeNullOrEmpty
    }
    It "reads dividend events of a chart result" {
        $r = '{"events":{"dividends":{"1700000000":{"amount":0.04,"date":1700000000},"1690000000":{"amount":0.04,"date":1690000000}}}}' | ConvertFrom-Json
        $d = @(ConvertFrom-ChartDividendEvents $r)
        $d.Count | Should -Be 2
        $d[0].Ts | Should -Be 1690000000
        @(ConvertFrom-ChartDividendEvents ('{"meta":{}}' | ConvertFrom-Json)).Count | Should -Be 0
    }
    It "finds the nearest bar" {
        $bars = [long[]]@(1000, 2000, 3000)
        Get-NearestBarIndex -BarTsMs $bars -TsMs 2400 -MaxGapMs 600 | Should -Be 1
        Get-NearestBarIndex -BarTsMs $bars -TsMs 9000 -MaxGapMs 600 | Should -Be -1
    }
    It "reads the version file" {
        Get-LatestVersionFromJson ('{"version":"4.10"}' | ConvertFrom-Json) | Should -Be "4.10"
        Get-LatestVersionFromJson ('{"v":1}' | ConvertFrom-Json) | Should -Be ""
        Get-LatestVersionFromJson $null | Should -Be ""
    }
}

Describe "News tab (v4.9)" {
    BeforeAll {
        $now = Get-Date -Year 2026 -Month 11 -Day 24 -Hour 12 -Minute 0 -Second 0
        function New-TestNews {
            param([string]$Title, [string]$Link, [double]$HoursAgo, [string[]]$Tickers = @(), [string]$Pub = "P")
            [PSCustomObject]@{ Title = $Title; Publisher = $Pub; Link = $Link; Time = $now.AddHours(-$HoursAgo); Tickers = $Tickers }
        }
    }
    It "asks for holdings first, each ticker once, without FX / indices / futures" {
        $s = @(Get-NewsSymbols -Holdings @("nvda", "EUNL.DE") -Watchlist @("NVDA", "^GSPC", "EURUSD=X", "GC=F", "BTC-USD", " ", $null, "msft"))
        ($s -join ",") | Should -Be "NVDA,EUNL.DE,BTC-USD,MSFT"
        @(Get-NewsSymbols -Watchlist @("A", "B", "C") -Max 2).Count | Should -Be 2
        @(Get-NewsSymbols).Count | Should -Be 0
    }
    It "merges per-ticker lists into one feed, newest first, without duplicates" {
        $by = @{
            "NVDA" = @((New-TestNews "Chips up" "https://x.example/a?src=yahoo" 1 @("NVDA", "AMD")), (New-TestNews "Old one" "https://x.example/old" 30))
            "AMD"  = @((New-TestNews "Chips up" "https://x.example/a" 1), (New-TestNews "AMD news" "" 0.5))
            "MSFT" = @((New-TestNews "Ancient" "https://x.example/z" (24 * 20)))
        }
        $f = @(Merge-NewsFeed -BySymbol $by -Now $now)
        ($f | ForEach-Object { $_.Title }) -join "|" | Should -Be "AMD news|Chips up|Old one"
        ($f[1].Syms -join ",") | Should -Be "AMD,NVDA"
        $f[0].Key | Should -Be "t:amd news"
        @(Merge-NewsFeed -BySymbol $by -Now $now -Max 1).Count | Should -Be 1
        @(Merge-NewsFeed -BySymbol @{} -Now $now).Count | Should -Be 0
        @(Merge-NewsFeed -BySymbol $null -Now $now).Count | Should -Be 0
    }
    It "adds related tickers only when they are ours" {
        $by = @{ "NVDA" = @((New-TestNews "T" "https://x.example/t" 1 @("TSM", "nvda", "MSFT"))); "MSFT" = @() }
        $f = @(Merge-NewsFeed -BySymbol $by -Now $now)
        ($f[0].Syms -join ",") | Should -Be "MSFT,NVDA"
    }
    It "filters by holdings, watchlist or one ticker" {
        $items = @(
            [PSCustomObject]@{ Title = "a"; Syms = @("NVDA") },
            [PSCustomObject]@{ Title = "b"; Syms = @("MSFT", "AMD") },
            [PSCustomObject]@{ Title = "c"; Syms = @("TSLA") }
        )
        @(Select-NewsItems -Items $items -Filter "All").Count | Should -Be 3
        @(Select-NewsItems -Items $items -Filter "").Count | Should -Be 3
        (@(Select-NewsItems -Items $items -Filter "Holdings" -Holdings @("nvda", "AMD")) | ForEach-Object { $_.Title }) -join "" | Should -Be "ab"
        (@(Select-NewsItems -Items $items -Filter "Watchlist" -Watchlist @("TSLA")) | ForEach-Object { $_.Title }) -join "" | Should -Be "c"
        (@(Select-NewsItems -Items $items -Filter "msft") | ForEach-Object { $_.Title }) -join "" | Should -Be "b"
        @(Select-NewsItems -Items $items -Filter "Holdings" -Holdings @()).Count | Should -Be 0
    }
    It "formats the age of an item" {
        Format-NewsAge -Time $now.AddSeconds(-20) -Now $now | Should -Be "jetzt"
        Format-NewsAge -Time $now.AddSeconds(30) -Now $now | Should -Be "jetzt"
        Format-NewsAge -Time $now.AddMinutes(-12) -Now $now | Should -Be "vor 12 min"
        Format-NewsAge -Time $now.AddMinutes(-12) -Now $now -Lang "EN" | Should -Be "12 min ago"
        Format-NewsAge -Time $now.AddHours(-3.5) -Now $now | Should -Be "vor 3 h"
        Format-NewsAge -Time $now.Date.AddDays(-1).AddHours(14.5) -Now $now | Should -Be "gestern 14:30"
        Format-NewsAge -Time $now.Date.AddDays(-1).AddHours(14.5) -Now $now -Lang "EN" | Should -Be "yesterday 14:30"
        Format-NewsAge -Time $now.Date.AddDays(-3).AddHours(9.25) -Now $now | Should -Be "21.11. 09:15"
        Format-NewsAge -Time ([DateTime]::MinValue) -Now $now | Should -Be ""
    }
    It "counts unread items" {
        $items = @([PSCustomObject]@{ Time = $now }, [PSCustomObject]@{ Time = $now.AddHours(-2) }, [PSCustomObject]@{ Time = [DateTime]::MinValue })
        Get-NewsUnreadCount -Items $items -Since $now.AddHours(-1) | Should -Be 1
        Get-NewsUnreadCount -Items $items -Since ([DateTime]::MinValue) | Should -Be 2
        Get-NewsUnreadCount -Items @() -Since $now | Should -Be 0
    }
    It "marks the ticker that moves most today" {
        $pct = @{ "NVDA" = 4.2; "AMD" = -6.1; "MSFT" = 0.4; "X" = [double]::NaN }
        $m = Get-NewsMover -Syms @("nvda", "AMD") -DayPct $pct -Threshold 3
        $m.Sym | Should -Be "AMD"
        $m.Pct | Should -Be -6.1
        Get-NewsMover -Syms @("MSFT", "X", "NONE") -DayPct $pct -Threshold 3 | Should -BeNullOrEmpty
        Get-NewsMover -Syms @("NVDA") -DayPct $pct -Threshold 0 | Should -BeNullOrEmpty
        Get-NewsMover -Syms @("NVDA") -DayPct $null | Should -BeNullOrEmpty
    }
    It "polls less often while markets are closed" {
        Get-NewsPollMinutes -Minutes 15 | Should -Be 15
        Get-NewsPollMinutes -Minutes 15 -AllClosed $true | Should -Be 30
        Get-NewsPollMinutes -Minutes 1 | Should -Be 5
        Get-NewsPollMinutes -Minutes 200 -AllClosed $true | Should -Be 240
    }
    It "puts the news tab below the chart in the Terminal layout" {
        $r = Get-TerminalLayoutRects -X 10 -Y 90 -W 1600 -H 900 -ChartPct 50 -ActiveBottom "News" -PanelMinW 756 -Gap 8 -MinBottomH 300
        $r.News | Should -Be @(10, 548, 1600, 442)
        $r.Watchlist | Should -BeNullOrEmpty
        $r.Portfolio | Should -BeNullOrEmpty
        $r2 = Get-TerminalLayoutRects -X 0 -Y 0 -W 900 -H 800 -ShowWatch $false -ShowPortfolio $false -ActiveBottom "News"
        $r2.News | Should -Not -BeNullOrEmpty
        (Get-TerminalLayoutRects -X 0 -Y 0 -W 900 -H 800 -ActiveBottom "Watchlist").News | Should -BeNullOrEmpty
    }
}

Describe "Look and feel (v4.9)" {
    It "uses the wanted number font only when it is installed" {
        Resolve-MonoFont -Wanted "Cascadia Mono" -Installed @("Arial", "Cascadia Mono") | Should -Be "Cascadia Mono"
        Resolve-MonoFont -Wanted "Cascadia Mono" -Installed @("Arial") | Should -Be "Consolas"
        Resolve-MonoFont -Wanted "Comic Sans MS" -Installed @("Comic Sans MS") | Should -Be "Consolas"
        Resolve-MonoFont -Wanted "" -Installed @() | Should -Be "Consolas"
    }
    It "scales font sizes in half points" {
        Get-ScaledFontSize -Base 8.5 -ScalePct 100 | Should -Be 8.5
        Get-ScaledFontSize -Base 8.5 -ScalePct 110 | Should -Be 9.5
        Get-ScaledFontSize -Base 8.5 -ScalePct 90 | Should -Be 7.5
        Get-ScaledFontSize -Base 13 -ScalePct 120 | Should -Be 15.5
        Get-ScaledFontSize -Base 8.5 -ScalePct 77 | Should -Be 8.5
    }
    It "picks the window corner style" {
        Get-WindowCornerPref -Kind "Window" | Should -Be 2
        Get-WindowCornerPref -Kind "Strip" | Should -Be 3
        Get-WindowCornerPref -Kind "Fullscreen" | Should -Be 1
        Get-WindowCornerPref -Kind "Window" -Round $false | Should -Be 1
    }
}

Describe "Polish (v4.9.5)" {
    BeforeAll {
        $now = Get-Date -Year 2026 -Month 11 -Day 24 -Hour 12 -Minute 0 -Second 0
    }
    It "marks the day move only on the newest item of each ticker" {
        $items = @(
            [PSCustomObject]@{ Key = "a"; Syms = @("NVDA") },
            [PSCustomObject]@{ Key = "b"; Syms = @("NVDA") },
            [PSCustomObject]@{ Key = "c"; Syms = @("AMD", "NVDA") },
            [PSCustomObject]@{ Key = "d"; Syms = @("MSFT") }
        )
        $m = Get-NewsMoverRows -Items $items -DayPct @{ "NVDA" = 31.2; "AMD" = -5; "MSFT" = 0.2 } -Threshold 3
        @($m.Keys | Sort-Object) -join "," | Should -Be "a,c"
        $m["a"].Sym | Should -Be "NVDA"
        $m["c"].Sym | Should -Be "AMD"
        (Get-NewsMoverRows -Items $items -DayPct @{} -Threshold 3).Count | Should -Be 0
    }
    It "drops muted sources" {
        $items = @([PSCustomObject]@{ Publisher = "Motley Fool" }, [PSCustomObject]@{ Publisher = "Reuters" }, [PSCustomObject]@{ Publisher = "" })
        @(Remove-MutedNews -Items $items -Muted @(" motley fool ")).Count | Should -Be 2
        @(Remove-MutedNews -Items $items -Muted @()).Count | Should -Be 3
        @(Remove-MutedNews -Items $items -Muted $null).Count | Should -Be 3
        # an empty feed must not turn into one $null item (broke the News tab on 5.1)
        @(Select-NewsItems -Items (Remove-MutedNews -Items @() -Muted @()) -Filter "All").Count | Should -Be 0
        @(Select-NewsItems -Items $null -Filter "All").Count | Should -Be 0
    }
    It "reads keyword lists" {
        (ConvertTo-KeywordList "Downgrade, Übernahme;gewinnwarnung`n downgrade ,,") -join "|" | Should -Be "downgrade|übernahme|gewinnwarnung"
        @(ConvertTo-KeywordList "").Count | Should -Be 0
    }
    It "finds keyword headlines of the chosen tickers, newer than the last check" {
        $items = @(
            [PSCustomObject]@{ Title = "Analyst issues DOWNGRADE on Nvidia"; Syms = @("NVDA"); Time = $now.AddMinutes(-5) },
            [PSCustomObject]@{ Title = "Downgrade for Microsoft"; Syms = @("MSFT"); Time = $now.AddMinutes(-4) },
            [PSCustomObject]@{ Title = "Old downgrade"; Syms = @("NVDA"); Time = $now.AddDays(-2) },
            [PSCustomObject]@{ Title = "ABB: Übernahme geplant"; Syms = @("ABBN.SW"); Time = $now.AddMinutes(-30) }
        )
        $h = @(Find-NewsKeywordHits -Items $items -Keywords @("downgrade", "übernahme") -Symbols @("nvda", "ABBN.SW") -Since $now.AddDays(-1))
        $h.Count | Should -Be 2
        $h[0].Sym | Should -Be "ABBN.SW"
        $h[0].Keyword | Should -Be "übernahme"
        $h[1].Sym | Should -Be "NVDA"
        @(Find-NewsKeywordHits -Items $items -Keywords @() -Symbols @("NVDA")).Count | Should -Be 0
    }
    It "rates the data health" {
        Get-DataHealth -AgeSec 10 -RefreshSec 15 | Should -Be "OK"
        Get-DataHealth -AgeSec 100 -RefreshSec 15 | Should -Be "WARN"
        Get-DataHealth -AgeSec 1000 -RefreshSec 15 | Should -Be "ERR"
        Get-DataHealth -AgeSec 1000 -RefreshSec 15 -AllClosed $true -ClosedMinutes 10 | Should -Be "OK"
        Get-DataHealth -AgeSec 1500 -RefreshSec 15 -AllClosed $true -ClosedMinutes 10 | Should -Be "WARN"
        Get-DataHealth -AgeSec 300 -RefreshSec 15 -AllClosed $true -ClosedMinutes 10 | Should -Be "OK"
        Get-DataHealth -AgeSec 10 -RefreshSec 15 -RateLimited $true | Should -Be "WARN"
        Get-DataHealth -AgeSec 10 -RefreshSec 15 -Offline $true | Should -Be "ERR"
        Get-DataHealth -AgeSec ([double]::NaN) -RefreshSec 15 | Should -Be ""
    }
    It "fades the price flash" {
        Get-FlashAlpha -ElapsedMs 100 | Should -Be 0.35
        Get-FlashAlpha -ElapsedMs 600 | Should -Be 0.175
        Get-FlashAlpha -ElapsedMs 950 | Should -Be 0
        Get-FlashAlpha -ElapsedMs 400 -HoldMs 300 -FadeMs 0 | Should -Be 0
    }
    It "gives a direction for the tray icon" {
        Get-DirectionKey 1.2 | Should -Be "up"
        Get-DirectionKey -0.4 | Should -Be "down"
        Get-DirectionKey 0.001 | Should -Be "none"
        Get-DirectionKey ([double]::NaN) | Should -Be "none"
    }
    It "hides amounts in privacy mode" {
        Protect-Amount "1.234,00 CHF" $false | Should -Be "1.234,00 CHF"
        Protect-Amount "1.234,00 CHF" $true | Should -Be ([string]([char]0x2022) * 4)
    }
    It "reads analyst targets and consensus" {
        $j = '{"quoteSummary":{"result":[{"financialData":{"targetMeanPrice":{"raw":200.5},"targetHighPrice":{"raw":250},"targetLowPrice":{"raw":140},"recommendationMean":{"raw":1.8},"recommendationKey":"buy","numberOfAnalystOpinions":{"raw":42}}}]}}' | ConvertFrom-Json
        $c = ConvertFrom-YahooCalendar -Summary $j
        $c.TargetMean | Should -Be 200.5
        $c.TargetLow | Should -Be 140
        $c.RecKey | Should -Be "buy"
        $c.Analysts | Should -Be 42
        $n = ConvertFrom-YahooCalendar -Summary ('{"quoteSummary":{"result":[{"financialData":{"recommendationKey":"none"}}]}}' | ConvertFrom-Json)
        $n.RecKey | Should -Be ""
        [double]::IsNaN($n.TargetMean) | Should -BeTrue
        Get-ConsensusLabel "buy" | Should -Be "Kauf"
        Get-ConsensusLabel "STRONG_BUY" -Long | Should -Be "Starker Kauf"
        Get-ConsensusLabel "x" | Should -Be ""
        [math]::Round((Get-TargetUpside -Target 110 -Price 100), 6) | Should -Be 10
        [double]::IsNaN((Get-TargetUpside -Target ([double]::NaN) -Price 100)) | Should -BeTrue
    }
    It "places the price in the 52-week range" {
        Get-RangePosition -Price 75 -Low 50 -High 100 | Should -Be 0.5
        Get-RangePosition -Price 120 -Low 50 -High 100 | Should -Be 1
        Get-RangePosition -Price 10 -Low 50 -High 100 | Should -Be 0
        [double]::IsNaN((Get-RangePosition -Price 75 -Low 100 -High 50)) | Should -BeTrue
    }
    It "snoozes alerts" {
        (Get-SnoozeUntil -Kind "1h" -Now $now) | Should -Be $now.AddHours(1)
        (Get-SnoozeUntil -Kind "Tomorrow" -Now $now) | Should -Be $now.Date.AddDays(1).AddHours(8)
        (Get-SnoozeUntil -Kind "" -Now $now) | Should -Be ([DateTime]::MinValue)
        $a = [PSCustomObject]@{ Ticker = "X"; SnoozeUntil = $now.AddHours(1).ToString("o") }
        Test-AlertSnoozed -Alert $a -Now $now | Should -BeTrue
        Test-AlertSnoozed -Alert $a -Now $now.AddHours(2) | Should -BeFalse
        Test-AlertSnoozed -Alert ([PSCustomObject]@{ Ticker = "X" }) -Now $now | Should -BeFalse
        Test-AlertSnoozed -Alert ([PSCustomObject]@{ Ticker = "X"; SnoozeUntil = "" }) -Now $now | Should -BeFalse
    }
    It "builds a tab-separated table" {
        $t = ConvertTo-TsvTable -Headers @("Ticker", "Kurs") -Rows @(, @("NVDA", "138,87 CHF"))
        $t | Should -Be ("Ticker`tKurs`r`nNVDA`t138,87 CHF")
        $t2 = ConvertTo-TsvTable -Headers @("A", "B") -Rows @(@("x`ty", "1"), @("z", "2`r`n3"))
        ($t2 -split "`r`n")[1] | Should -Be "x y`t1"
        ($t2 -split "`r`n")[2] | Should -Be "z`t2 3"
    }
    It "shows one list as a full page in the Terminal layout" {
        $r = Get-TerminalLayoutRects -X 10 -Y 90 -W 1600 -H 900 -Full "Portfolio"
        $r.Portfolio | Should -Be @(10, 90, 1600, 900)
        $r.Chart | Should -BeNullOrEmpty
        $r.Watchlist | Should -BeNullOrEmpty
        (Get-TerminalLayoutRects -X 0 -Y 0 -W 900 -H 800 -Full "Watchlist" -ShowWatch $false).Watchlist | Should -Be @(0, 0, 900, 800)
        (Get-TerminalLayoutRects -X 0 -Y 0 -W 900 -H 800 -Full "Chart").Chart | Should -Not -BeNullOrEmpty
    }
    It "knows the privacy and full-page commands" {
        (ConvertFrom-TerminalCommand "FULL").Kind | Should -Be "Global"
        (ConvertFrom-TerminalCommand "PRIV").Kind | Should -Be "Global"
    }
}

Describe "Depot tools (v5.0)" {
    It "derives cash movements from new trades and the ledger" {
        $tx = @(
            [PSCustomObject]@{ Id = "old"; Date = "2026-01-02"; Ticker = "nvda"; Type = "Kauf"; Shares = 10; Price = 100; Fee = 5; Currency = "USD" },
            [PSCustomObject]@{ Id = "b"; Date = "2026-03-01"; Ticker = "SAP.DE"; Type = "Kauf"; Shares = 2; Price = 200; Fee = 1; Currency = "EUR" },
            [PSCustomObject]@{ Id = "s"; Date = "2026-04-01"; Ticker = "SAP.DE"; Type = "Verkauf"; Shares = 1; Price = 250; Fee = 1; Currency = "EUR" },
            [PSCustomObject]@{ Id = "d"; Date = "2026-05-01"; Ticker = "MSFT"; Type = "Dividende"; Shares = 5; Price = 4; Fee = 0.6; Currency = "USD" }
        )
        $led = @([PSCustomObject]@{ Id = "c1"; Date = "2026-02-01"; Kind = "Start"; Amount = 1000; Currency = "EUR" })
        $mv = @(Get-CashMovements -Transactions $tx -Entries $led -ExcludeIds @("old"))
        $mv.Count | Should -Be 4
        ($mv | ForEach-Object { $_.Kind }) -join "," | Should -Be "Start,Kauf,Verkauf,Dividende"
        $mv[1].Amount | Should -Be -401
        $mv[2].Amount | Should -Be 249
        [math]::Round($mv[3].Amount, 2) | Should -Be 3.4
        $b = Get-CashBalance -Movements $mv -Currency "EUR" -Rates @{ USD = 0.9 }
        [math]::Round($b.Balance, 2) | Should -Be ([math]::Round(1000 - 401 + 249 + 3.4 * 0.9, 2))
        (Get-CashBalance -Movements $mv -Currency "EUR" -Rates @{}).Missing | Should -Be @("USD")
    }
    It "computes returns without the deposits" {
        # 100 -> 110 (+10 %), then +100 deposit -> 210, then 231 (+10 %)
        $r = Get-FlowAdjustedReturns -Value @(100, 110, 210, 231) -Invested @(100, 100, 200, 200)
        (@($r) | ForEach-Object { [math]::Round($_, 4) }) -join "," | Should -Be "0.1,0,0.1"
        @(Get-FlowAdjustedReturns -Value @(100) -Invested @(100)).Count | Should -Be 0
    }
    It "rates risk: volatility, drawdown, best and worst" {
        $s = Get-ReturnStats -Returns @(0.1, -0.2, 0.05, 0.1) -PeriodsPerYear 4 -RiskFreePct 0
        [math]::Round($s.MaxDd, 2) | Should -Be -20
        $s.DdPeak | Should -Be 0
        $s.DdTrough | Should -Be 1
        [math]::Round($s.Best, 2) | Should -Be 10
        $s.WorstIdx | Should -Be 1
        [math]::Round($s.Total, 2) | Should -Be ([math]::Round((1.1 * 0.8 * 1.05 * 1.1 - 1) * 100, 2))
        $s.Vol | Should -BeGreaterThan 0
        [double]::IsNaN((Get-ReturnStats -Returns @(0.1)).Vol) | Should -BeTrue
        [math]::Round((Get-PeriodsPerYear -Dates @("2025-01-01", "2025-07-02", "2026-01-01")), 1) | Should -Be 2
    }
    It "measures beta and correlation" {
        $b = @(0.01, -0.02, 0.03, 0.0, -0.01)
        $r = @($b | ForEach-Object { 2 * $_ })
        [math]::Round((Get-Beta -R $r -B $b), 6) | Should -Be 2
        [math]::Round((Get-Correlation -A $r -B $b), 6) | Should -Be 1
        [math]::Round((Get-Correlation -A $b -B @($b | ForEach-Object { -$_ })), 6) | Should -Be -1
        [double]::IsNaN((Get-Correlation -A @(1, 2) -B @(1, 2))) | Should -BeTrue
        $h = Get-DailyReturnsByDate -Dates @("a", "b", "c") -Closes @(100, 110, 99)
        [math]::Round($h["c"], 4) | Should -Be -0.1
        $m = Get-CorrelationMatrix -BySym @{ A = @{ d1 = 0.1; d2 = -0.1; d3 = 0.2 }; B = @{ d1 = 0.2; d2 = -0.2; d3 = 0.4 } } -MinCommon 3
        ($m.Syms -join ",") | Should -Be "A,B"
        $mm = $m.M
        $c01 = $mm[0, 1]
        [math]::Round($c01, 6) | Should -Be 1
    }
    It "plans a rebalancing with and without sales" {
        $pos = @(@{ Sym = "A"; Value = 600; Price = 10 }, @{ Sym = "B"; Value = 400; Price = 20 }, @{ Sym = "C"; Value = 50; Price = 5 })
        $p = Get-RebalancePlan -Positions $pos -Targets @{ A = 50; B = 50 } -Money 0
        @($p.Rows).Count | Should -Be 2
        ($p.Rows | Where-Object Sym -eq "A").Trade | Should -Be -100
        ($p.Rows | Where-Object Sym -eq "B").Shares | Should -Be 5
        [math]::Round($p.Left, 2) | Should -Be 0
        $q = Get-RebalancePlan -Positions $pos -Targets @{ A = 50; B = 50 } -Money 100 -BuyOnly $true
        ($q.Rows | Where-Object Sym -eq "A").Trade | Should -Be 0
        ($q.Rows | Where-Object Sym -eq "B").Trade | Should -Be 100
        $q.Left | Should -Be 0
        $r = Get-RebalancePlan -Positions $pos -Targets @{ A = 40; B = 40 } -Money 0
        $r.TargetSum | Should -Be 80
        [math]::Round($r.Left, 2) | Should -Be 200
    }
    It "finds due savings plan dates and the close of that day" {
        (Get-DueSavingsDates -Plan @{ Day = 5; Start = "2026-09-01"; LastBooked = "" } -Today "2026-11-24") -join "," | Should -Be "2026-09-05,2026-10-05,2026-11-05"
        (Get-DueSavingsDates -Plan @{ Day = 5; Start = "2026-09-01"; LastBooked = "2026-10-05" } -Today "2026-11-24") -join "," | Should -Be "2026-11-05"
        @(Get-DueSavingsDates -Plan @{ Day = 31; Start = "2026-11-01"; LastBooked = "" } -Today "2026-11-24").Count | Should -Be 0
        (Get-DueSavingsDates -Plan @{ Day = 31; Start = "2026-10-01"; LastBooked = "" } -Today "2026-11-24") -join "," | Should -Be "2026-10-28"
        $c = Get-CloseOnOrBefore -Dates @("2026-11-05", "2026-11-06", "2026-11-09") -Closes @(10, 11, 12) -Date "2026-11-08"
        $c.Date | Should -Be "2026-11-06"
        $c.Close | Should -Be 11
        Get-CloseOnOrBefore -Dates @("2026-11-05") -Closes @(10) -Date "2026-11-01" | Should -BeNullOrEmpty
    }
    It "lays out a squarified treemap that fills the area" {
        $r = Get-TreemapRects -Values @(6, 6, 4, 3, 2, 2, 1) -X 0 -Y 0 -W 6 -H 4
        $r[0] | Should -Be @(0, 0, 3, 2)
        $r[1] | Should -Be @(0, 2, 3, 2)
        $area = 0.0; foreach ($x in $r) { $area += $x[2] * $x[3] }
        [math]::Round($area, 6) | Should -Be 24
        $z = Get-TreemapRects -Values @(5, 0) -X 0 -Y 0 -W 10 -H 10
        $z[1] | Should -Be @(0, 0, 0, 0)
        $z[0] | Should -Be @(0, 0, 10, 10)
    }
    It "knows the depot commands" {
        foreach ($c in @("CASH", "SPAR", "REBAL", "RISK", "HEAT")) { (ConvertFrom-TerminalCommand $c).Kind | Should -Be "Global" }
    }
}

Describe "Chart tools (v5.0)" {
    It "maps time to the evenly spaced bars and back" {
        $ts = [long[]]@(0, 10, 20, 40)
        Get-FracIndexAtTs -BarTs $ts -Ts 30 | Should -Be 2.5
        Get-FracIndexAtTs -BarTs $ts -Ts 60 | Should -Be 4.5
        Get-FracIndexAtTs -BarTs $ts -Ts -20 | Should -Be ([double](-20) / (40 / 3))
        Get-TsAtFracIndex -BarTs $ts -Idx 2.5 | Should -Be 30
        Get-TsAtFracIndex -BarTs $ts -Idx (Get-FracIndexAtTs -BarTs $ts -Ts 55) | Should -Be 55
        [double]::IsNaN((Get-FracIndexAtTs -BarTs ([long[]]@()) -Ts 5)) | Should -BeTrue
    }
    It "computes Fibonacci levels from the start to the end of a move" {
        $f = @(Get-FibLevels -P1 100 -P2 200)
        $f.Count | Should -Be 7
        ($f | Where-Object Pct -eq 0).Price | Should -Be 200
        ($f | Where-Object Pct -eq 100).Price | Should -Be 100
        [math]::Round(($f | Where-Object Pct -eq 61.8).Price, 2) | Should -Be 138.2
    }
    It "measures the distance of the mouse to a line" {
        Get-PointLineDistance -X 5 -Y 3 -X1 0 -Y1 0 -X2 10 -Y2 0 | Should -Be 3
        Get-PointLineDistance -X 20 -Y 0 -X1 0 -Y1 0 -X2 10 -Y2 0 | Should -Be 10
        Get-PointLineDistance -X 20 -Y 0 -X1 0 -Y1 0 -X2 10 -Y2 0 -Ray $true | Should -Be 0
    }
    It "follows a trend line in time and alerts when the price crosses it" {
        Get-TrendPriceAt -T1 0 -P1 100 -T2 1000 -P2 110 -T 1500 | Should -Be 115
        [double]::IsNaN((Get-TrendPriceAt -T1 5 -P1 1 -T2 5 -P2 2 -T 9)) | Should -BeTrue
        Get-AlertKind "Trend >=" | Should -Be "TREND"
        $a = [PSCustomObject]@{ Condition = "Trend <="; TargetPrice = 0; Currency = "EUR"; T1 = 0; P1 = 100; T2 = 1000; P2 = 110 }
        (Get-AlertEvaluation -Alert $a -Ctx @{ Price = 104; NowMs = 500 }).Met | Should -BeTrue
        (Get-AlertEvaluation -Alert $a -Ctx @{ Price = 106; NowMs = 500 }).Met | Should -BeFalse
        (Get-AlertEvaluation -Alert $a -Ctx @{ NowMs = 500 }).Ok | Should -BeFalse
    }
    It "builds Heikin-Ashi bars" {
        $bars = @(
            [PSCustomObject]@{ Ts = 1; Open = 10; High = 12; Low = 9; Close = 11; Volume = 5 },
            [PSCustomObject]@{ Ts = 2; Open = 11; High = 13; Low = 10; Close = 12; Volume = 6 }
        )
        $h = @(ConvertTo-HeikinAshi $bars)
        $h.Count | Should -Be 2
        $h[0].Close | Should -Be 10.5
        $h[0].Open | Should -Be 10.5
        $h[1].Open | Should -Be 10.5
        $h[1].Close | Should -Be 11.5
        $h[1].High | Should -Be 13
        $h[1].Low | Should -Be 10
        $h[1].Volume | Should -Be 6
    }
    It "cycles the chart type" {
        Get-NextChartType "Line" | Should -Be "Candle"
        Get-NextChartType "Candle" | Should -Be "HA"
        Get-NextChartType "HA" | Should -Be "Line"
        Get-NextChartType "x" | Should -Be "Line"
    }
    It "keeps up to three comparisons" {
        $r = Set-CompareList -Current @("QQQ") -Symbol "spy"
        ($r.List -join ",") | Should -Be "QQQ,SPY"
        $r.Msg | Should -Be "added"
        (Set-CompareList -Current @("QQQ", "SPY") -Symbol "QQQ").List -join "," | Should -Be "SPY"
        (Set-CompareList -Current @("A", "B", "C") -Symbol "D").Msg | Should -Be "full"
        @((Set-CompareList -Current @("A") -Symbol "").List).Count | Should -Be 0
    }
    It "knows the drawing command" {
        (ConvertFrom-TerminalCommand "DRAW T").Kind | Should -Be "Global"
    }
}

Describe "Workspace (v5.0)" {
    It "turns a divider position into a clamped percentage" {
        Get-DragPct -Pos 550 -Start 100 -Length 900 | Should -Be 50
        Get-DragPct -Pos 0 -Start 100 -Length 900 -Min 25 -Max 80 | Should -Be 25
        Get-DragPct -Pos 5000 -Start 100 -Length 900 -Min 25 -Max 80 | Should -Be 80
        Get-DragPct -Pos 5 -Start 0 -Length 0 -Min 20 -Max 80 | Should -Be 50
    }
    It "splits the two lists by the dragged share" {
        $r = Get-TerminalLayoutRects -X 0 -Y 0 -W 2000 -H 900 -SplitPct 60 -PanelMinW 756 -Gap 8
        $r.Watchlist[2] | Should -Be 1195
        ($r.Watchlist[2] + 8 + $r.Portfolio[2]) | Should -Be 2000
        # never narrower than PanelMinW
        (Get-TerminalLayoutRects -X 0 -Y 0 -W 2000 -H 900 -SplitPct 75 -PanelMinW 756 -Gap 8).Portfolio[2] | Should -Be 756
    }
    It "keeps watchlist groups" {
        $g = Set-WatchGroupMember -Groups @() -Group "Tech" -Symbol "nvda"
        $g = Set-WatchGroupMember -Groups $g -Group "Tech" -Symbol "MSFT"
        $g = Set-WatchGroupMember -Groups $g -Group "ETF" -Symbol "EUNL.DE"
        @($g).Count | Should -Be 2
        ($g[0].Symbols -join ",") | Should -Be "NVDA,MSFT"
        (Get-WatchGroupSymbols -Watchlist @("msft", "ABBN.SW", "NVDA") -Groups $g -Group "Tech") -join "," | Should -Be "MSFT,NVDA"
        @(Get-WatchGroupSymbols -Watchlist @("A", "B") -Groups $g -Group "").Count | Should -Be 2
        @(Get-WatchGroupSymbols -Watchlist @("A", "B") -Groups $g -Group "Gone").Count | Should -Be 2
        $g = Set-WatchGroupMember -Groups $g -Group "Tech" -Symbol "NVDA" -In $false
        ($g[0].Symbols -join ",") | Should -Be "MSFT"
        $e = Set-WatchGroupMember -Groups @() -Group "Leer" -Symbol ""
        @($e[0].Symbols).Count | Should -Be 0
    }
    It "finds settings by words, umlauts folded" {
        Test-SettingMatch -Text "Schriftgröße Listen + Chart (ab Neustart)" -Query "schrift grosse" | Should -BeTrue
        Test-SettingMatch -Text "Handy-Push einrichten ..." -Query "push" | Should -BeTrue
        Test-SettingMatch -Text "Theme" -Query "push" | Should -BeFalse
        Test-SettingMatch -Text "Theme" -Query "  " | Should -BeFalse
    }
}

Describe "Currency (v5.1)" {
    It "guesses the trading currency from the exchange suffix" {
        Get-TickerCurrencyGuess "ABBN.SW" | Should -Be "CHF"
        Get-TickerCurrencyGuess "sap.de" | Should -Be "EUR"
        Get-TickerCurrencyGuess "NVDA" | Should -Be "USD"
        Get-TickerCurrencyGuess "VOD.L" | Should -Be "GBP"
        Get-TickerCurrencyGuess "EURUSD=X" | Should -Be "USD"
        Get-TickerCurrencyGuess "^GDAXI" | Should -Be ""
        Get-TickerCurrencyGuess "XYZ.QQ" | Should -Be ""
    }
    It "cycles Auto and the fixed currencies with W" {
        Get-NextCurrencyMode -Current "CHF" -Auto $true | Should -Be "EUR"
        Get-NextCurrencyMode -Current "EUR" -Auto $false | Should -Be "USD"
        Get-NextCurrencyMode -Current "GBP" -Auto $false | Should -Be "AUTO"
    }
}

Describe "Analysis (v5.1)" {
    It "splits the depot result by position" {
        $by = @{
            "A" = [PSCustomObject]@{ Value = [double[]]@(100, 120, 150); Buys = [double[]]@(100, 100, 100); Sells = [double[]]@(0, 0, 0); Divs = [double[]]@(0, 0, 2) }
            "B" = [PSCustomObject]@{ Value = [double[]]@(0, 50, 40); Buys = [double[]]@(0, 50, 50); Sells = [double[]]@(0, 0, 0); Divs = [double[]]@(0, 0, 0) }
        }
        $c = Get-Contributions -BySym $by -Start 0 -End 2
        $c.Rows[0].Sym | Should -Be "A"
        $c.Rows[0].Contribution | Should -Be 52
        $c.Rows[1].Contribution | Should -Be -10
        $c.Total | Should -Be 42
        [math]::Round($c.Rows[1].Pct, 2) | Should -Be -40
    }
    It "tracks per-ticker values in the value series" {
        $tx = @(
            [PSCustomObject]@{ Date = "2024-01-02"; Type = "Kauf"; Ticker = "AAA"; Shares = 10; Price = 10; Fee = 0; Currency = "EUR" }
            [PSCustomObject]@{ Date = "2024-01-04"; Type = "Verkauf"; Ticker = "AAA"; Shares = 5; Price = 12; Fee = 0; Currency = "EUR" }
        )
        $prices = @{ "AAA" = [PSCustomObject]@{ Dates = @("2024-01-02", "2024-01-03", "2024-01-04"); Closes = @(10.0, 11.0, 12.0); Currency = "EUR"; Splits = @() } }
        $s = Get-PortfolioValueSeries -Transactions $tx -Prices $prices -Base "EUR" -EndDate "2024-01-04"
        $s.BySym["AAA"].Value[1] | Should -Be 110
        $s.BySym["AAA"].Sells[2] | Should -Be 60
        (Get-Contributions -BySym $s.BySym -Start 0 -End 2).Total | Should -Be 20
    }
    It "builds a time-weighted index and rolling returns" {
        $x = Get-TwrIndex -Value @(100, 110, 220, 200) -Invested @(100, 100, 200, 200)
        [math]::Round($x[2], 6) | Should -Be 120
        (Get-TwrIndex -Value @(50, 60) -Start 1)[1] | Should -Be 100
        $r = Get-RollingReturns -Dates @("2024-01-01", "2024-06-01", "2025-01-02") -Values @(100, 110, 120) -Days 365
        @($r.Values).Count | Should -Be 1
        [math]::Round($r.Values[0], 9) | Should -Be 20
    }
    It "estimates a market scenario with beta" {
        $s = Get-ScenarioImpact -Positions @([PSCustomObject]@{ Sym = "A"; Value = 1000; Beta = 1.5 }, [PSCustomObject]@{ Sym = "B"; Value = 1000; Beta = [double]::NaN }) -MarketPct -20
        $s.Change | Should -Be -500
        ($s.Rows | Where-Object { $_.Sym -eq "B" }).BetaAssumed | Should -BeTrue
        $s.Pct | Should -Be -25
    }
    It "finds support and resistance and rates the signals" {
        $c = New-Object double[] 260
        for ($i = 0; $i -lt 260; $i++) { $c[$i] = 100 + 10 * [math]::Sin($i / 8.0) + $i * 0.05 }
        $sr = Get-SupportResistance -Highs $c -Lows $c -Closes $c
        $sr.Support | Should -BeLessThan $c[259]
        $sr.Resistance | Should -BeGreaterThan $c[259]
        $t = Get-TechnicalSignals -Closes $c
        @($t.Rows | Where-Object { $_.Key -eq "SMA200" }).Count | Should -Be 1
        @($t.Rows | Where-Object { $_.Key -eq "RSI" }).Count | Should -Be 1
        $t.Summary | Should -BeIn @("überwiegend positiv", "überwiegend negativ", "gemischt")
        (Get-TechnicalSignals -Closes @(1.0, 2.0)).Summary | Should -Be "Zu wenig Kursdaten"
    }
    It "reads fundamentals and compares them with peers" {
        $sum = [PSCustomObject]@{ quoteSummary = [PSCustomObject]@{ result = @([PSCustomObject]@{
            summaryDetail = [PSCustomObject]@{ trailingPE = [PSCustomObject]@{ raw = 30.0 }; marketCap = [PSCustomObject]@{ raw = 2.5e9 } }
            financialData = [PSCustomObject]@{ profitMargins = [PSCustomObject]@{ raw = 0.25 }; financialCurrency = "EUR" }
            defaultKeyStatistics = [PSCustomObject]@{ forwardPE = [PSCustomObject]@{ raw = 20.0 } } }) } }
        $f = ConvertFrom-YahooFundamentals -Summary $sum
        $f.TrailingPE | Should -Be 30
        $f.ForwardPE | Should -Be 20
        $f.Currency | Should -Be "EUR"
        ConvertFrom-YahooFundamentals -Summary $null | Should -BeNullOrEmpty
        $rows = Get-FundamentalRows -Fund $f -Peers @([PSCustomObject]@{ TrailingPE = 20; ProfitMargin = 0.1 }, [PSCustomObject]@{ TrailingPE = 24; ProfitMargin = $null })
        ($rows | Where-Object { $_.Key -eq "TrailingPE" }).Score | Should -Be -1
        ($rows | Where-Object { $_.Key -eq "TrailingPE" }).Peer | Should -Be "22.00"
        ($rows | Where-Object { $_.Key -eq "ProfitMargin" }).Peer | Should -Be "-"
        ($rows | Where-Object { $_.Key -eq "MarketCap" }).Value | Should -Be "2.5 Mrd. EUR"
    }
    It "keeps fundamentals when they are stored (v5.2 fix)" {
        $st = ConvertTo-StoredFund ([PSCustomObject]@{ TrailingPE = 30.5; MarketCap = 2.5e9; ForwardPE = [double]::NaN; Currency = "EUR" })
        $st.TrailingPE | Should -Be 30.5
        $st.ForwardPE | Should -BeNullOrEmpty
        $st.Currency | Should -Be "EUR"
        ((Get-FundamentalRows -Fund $st) | Where-Object { $_.Key -eq "TrailingPE" }).Value | Should -Be "30.50"
    }
    It "compares sectors with the MSCI World" {
        $sum = [PSCustomObject]@{ quoteSummary = [PSCustomObject]@{ result = @([PSCustomObject]@{ topHoldings = [PSCustomObject]@{ sectorWeightings = @([PSCustomObject]@{ technology = [PSCustomObject]@{ raw = 0.25 } }, [PSCustomObject]@{ realestate = [PSCustomObject]@{ raw = 0.02 } }) } }) } }
        $ref = ConvertFrom-YahooSectorWeights -Summary $sum
        $ref["technology"] | Should -Be 25
        $rows = Get-SectorComparison -Groups @([PSCustomObject]@{ Key = "Technology"; Pct = 60.0 }, [PSCustomObject]@{ Key = "Unbekannt"; Pct = 40.0 }) -Reference $ref
        $rows[0].Diff | Should -Be 35
        $rows[$rows.Count - 1].Sector | Should -Be "Andere / ETF / unbekannt"
    }
}

Describe "Design (v5.2)" {
    It "describes the two styles and the row densities" {
        $r = Get-UiSpec -Style "Refined" -Density "Normal"
        $f = Get-UiSpec -Style "Fresh" -Density "Comfortable"
        $r.Fresh | Should -BeFalse
        $r.CardRadius | Should -Be 0
        $f.CardRadius | Should -BeGreaterThan 0
        $f.Gap | Should -BeGreaterThan $r.Gap
        $f.RowH | Should -Be 32
        (Get-UiSpec -Style "nonsense" -Density "Compact").Style | Should -Be "Refined"
        (Get-UiSpec -Density "Compact").RowH | Should -Be 21
    }
    It "reads the Windows accent colour" {
        (ConvertFrom-AbgrDword -Value 0xFFD77800) -join "," | Should -Be "0,120,215"
        (ConvertFrom-AbgrDword -Value -2656256) -join "," | Should -Be "0,120,215"
    }
    It "steps the ticker bar" {
        Get-TapeStep "Slow" | Should -Be 0.5
        Get-TapeStep "Fast" | Should -Be 2
        Get-TapeStep "" | Should -Be 1
    }
}

Describe "Settings pages (v5.3)" {
    BeforeAll {
        $script:SetEntries = @(
            [PSCustomObject]@{ Page = "Design";  Search = "Stil Refined - wie gewohnt, feiner Fresh - Karten, mehr Luft Design Style" }
            [PSCustomObject]@{ Page = "Design";  Search = "Zebra-Zeilen (jede zweite Zeile heller)" }
            [PSCustomObject]@{ Page = "Display"; Search = "Schrift für Zahlen (ab Neustart)" }
            [PSCustomObject]@{ Page = "Alerts";  Search = "Handy-Push einrichten ..." }
            [PSCustomObject]@{ Page = "Display"; Search = "Schriftgröße Listen + Chart (ab Neustart)" }
        )
    }
    It "has the eight agreed pages in order" {
        $pg = @(Get-SettingsPages)
        $pg.Count | Should -Be 8
        ($pg | ForEach-Object { $_.De }) -join "|" | Should -Be "Darstellung|Design|Layout|Daten & Aktualisierung|Alarme & Benachrichtigungen|Depot|Tastatur & Befehle|Sonstiges"
        Get-SettingsPageTitle -Id "Keyboard" -Language "EN" | Should -Be "Keyboard & commands"
        Get-SettingsPageTitle -Id "nope" | Should -Be "nope"
    }
    It "finds the style by every name it goes by" {
        foreach ($q in @("stil", "Style", "FRESH", "refined")) {
            $h = Find-SettingsHits -Entries $script:SetEntries -Query $q
            @($h.Entries) | Should -Contain 0
            Select-SettingsPage -Current "Display" -Hits $h | Should -Be "Design"
        }
    }
    It "counts hits per page and keeps the current page when it has hits" {
        $h = Find-SettingsHits -Entries $script:SetEntries -Query "schrift"
        $h.Counts["Display"] | Should -Be 2
        $h.Counts["Design"] | Should -Be 0
        Select-SettingsPage -Current "Display" -Hits $h | Should -Be "Display"
        Select-SettingsPage -Current "Design" -Hits $h | Should -Be "Display"
        $none = Find-SettingsHits -Entries $script:SetEntries -Query "gibtsnicht"
        @($none.Entries).Count | Should -Be 0
        Select-SettingsPage -Current "Layout" -Hits $none | Should -Be "Layout"
    }
    It "prefers a label hit to a tooltip hit" {
        $e = @(
            [PSCustomObject]@{ Page = "Misc";   Search = "Einstellungen exportieren ... ohne Push-Zugang"; Strong = "Einstellungen exportieren ..." }
            [PSCustomObject]@{ Page = "Alerts"; Search = "Handy-Push einrichten ... Push ntfy"; Strong = "Handy-Push einrichten ... Push ntfy" }
        )
        $h = Find-SettingsHits -Entries $e -Query "push"
        $h.Counts["Misc"] | Should -Be 1
        $h.StrongCounts["Misc"] | Should -Be 0
        Select-SettingsPage -Current "Misc" -Hits $h | Should -Be "Alerts"
        # only a tooltip hit anywhere: still found
        $h2 = Find-SettingsHits -Entries $e -Query "zugang"
        Select-SettingsPage -Current "Design" -Hits $h2 | Should -Be "Misc"
    }
    It "takes the entries as a generic list, too (the settings window keeps them in one)" {
        $list = New-Object System.Collections.Generic.List[object]
        foreach ($x in $script:SetEntries) { $list.Add($x) }
        $h = Find-SettingsHits -Entries $list -Query "fresh"
        @($h.Entries) | Should -Contain 0
        $h.Counts["Design"] | Should -Be 1
    }
    It "jumps to a page whose title matches" {
        $h = Find-SettingsHits -Entries $script:SetEntries -Query "tastatur"
        Select-SettingsPage -Current "Display" -Hits $h | Should -Be "Keyboard"
        $h2 = Find-SettingsHits -Entries $script:SetEntries -Query "notifications"
        Select-SettingsPage -Current "Display" -Hits $h2 | Should -Be "Alerts"
        (Find-SettingsHits -Entries $script:SetEntries -Query "  ").Counts["Design"] | Should -Be 0
        # "fresh" is inside "Data & refresh" - titles match by word start only
        @((Find-SettingsHits -Entries $script:SetEntries -Query "fresh").TitlePages).Count | Should -Be 0
        @((Find-SettingsHits -Entries $script:SetEntries -Query "daten").TitlePages) | Should -Contain "Data"
    }
    It "marks settings that differ from the default" {
        Test-SettingChanged -Value 15 -Default 15 | Should -BeFalse
        Test-SettingChanged -Value ([decimal]15) -Default 15 | Should -BeFalse
        Test-SettingChanged -Value 20 -Default 15 | Should -BeTrue
        Test-SettingChanged -Value $true -Default $true | Should -BeFalse
        Test-SettingChanged -Value $false -Default $true | Should -BeTrue
        Test-SettingChanged -Value "Fresh - Karten, mehr Luft" -Default "Refined - wie gewohnt, feiner" | Should -BeTrue
        Test-SettingChanged -Value "Ctrl+Alt+W " -Default "Ctrl+Alt+W" | Should -BeFalse
        Test-SettingChanged -Value "x" -Default $null | Should -BeFalse
        Test-SettingChanged -Value ([decimal]2.5) -Default 2.0 | Should -BeTrue
    }
    It "exports only portable settings" {
        $cfg = [PSCustomObject]@{ Theme = "Light"; UiStyle = "Fresh"; WindowX = 500; PushTokenEnc = "secret"; CommandHistory = @("NVDA") }
        $x = ConvertTo-SettingsExport -Config $cfg -Version "5.3" -Now ([DateTime]"2026-11-24 10:00")
        $x.Format | Should -Be "TerminalWidget.Settings"
        $x.Exported | Should -Be "2026-11-24T10:00:00"
        @($x.Settings.PSObject.Properties.Name) -join "," | Should -Be "Theme,UiStyle"
        Get-PortableSettingKeys | Should -Not -Contain "PushTokenEnc"
        Get-PortableSettingKeys | Should -Not -Contain "WindowX"
    }
    It "imports with type checks and skips what it does not know" {
        $def = [PSCustomObject]@{ Theme = "Dark"; RefreshSeconds = 15; RiskFreePct = 2.0; ZebraRows = $false; NewsMuted = @(); UserLayouts = @(); WindowX = 100; GridLayouts = [PSCustomObject]@{} }
        $json = @"
{ "Format": "TerminalWidget.Settings", "Version": "5.3", "Settings": {
  "Theme": "Light", "RefreshSeconds": "30", "RiskFreePct": 2.5, "ZebraRows": true,
  "NewsMuted": ["Motley Fool"], "WindowX": 900, "Unknown": 1, "GridLayouts": { "Watch": "a" } } }
"@
        $r = ConvertFrom-SettingsExport -Data ($json | ConvertFrom-Json) -Defaults $def
        $r.Ok | Should -BeTrue
        $r.Settings["Theme"] | Should -Be "Light"
        $r.Settings["RefreshSeconds"] | Should -Be 30
        $r.Settings["RefreshSeconds"] | Should -BeOfType [int]
        $r.Settings["RiskFreePct"] | Should -Be 2.5
        $r.Settings["ZebraRows"] | Should -BeTrue
        @($r.Settings["NewsMuted"]) -join "," | Should -Be "Motley Fool"
        $r.Settings["GridLayouts"].Watch | Should -Be "a"
        $r.Settings.ContainsKey("WindowX") | Should -BeFalse
        $r.Skipped | Should -Contain "WindowX"
        $r.Skipped | Should -Contain "Unknown"
    }
    It "rejects broken values and foreign files" {
        $def = [PSCustomObject]@{ RefreshSeconds = 15; ZebraRows = $false }
        $bad = '{ "Format": "TerminalWidget.Settings", "Settings": { "RefreshSeconds": "viel", "ZebraRows": "ja" } }' | ConvertFrom-Json
        $r = ConvertFrom-SettingsExport -Data $bad -Defaults $def
        $r.Ok | Should -BeFalse
        @($r.Skipped).Count | Should -Be 2
        (ConvertFrom-SettingsExport -Data ('{ "Theme": "Dark" }' | ConvertFrom-Json) -Defaults $def).Error | Should -Not -BeNullOrEmpty
        (ConvertFrom-SettingsExport -Data $null -Defaults $def).Ok | Should -BeFalse
    }
    It "offers settings and menu entries in Ctrl+K" {
        $extra = @(
            [PSCustomObject]@{ Text = "SET STIL"; Desc = "Einstellung - Design"; Search = "Refined Fresh Style Design" }
            [PSCustomObject]@{ Text = "SET ZEBRA-ZEILEN (JEDE ZWEITE ZEILE HELLER)"; Desc = "Einstellung - Design"; Search = "" }
            [PSCustomObject]@{ Text = "MENU DURCHKLICKEN (MAUS GEHT DURCH)"; Desc = "Menü - Tray"; Search = "" }
        )
        $t = @(Get-CommandSuggestions -Text "fresh" -Extra $extra | ForEach-Object { $_.Text })
        $t | Should -Contain "SET STIL"
        $t = @(Get-CommandSuggestions -Text "SET zebra" -Extra $extra | ForEach-Object { $_.Text })
        $t | Should -Contain "SET ZEBRA-ZEILEN (JEDE ZWEITE ZEILE HELLER)"
        $t | Should -Not -Contain "MENU DURCHKLICKEN (MAUS GEHT DURCH)"
        $t = @(Get-CommandSuggestions -Text "MENU durch" -Extra $extra | ForEach-Object { $_.Text })
        $t | Should -Contain "MENU DURCHKLICKEN (MAUS GEHT DURCH)"
        $t = @(Get-CommandSuggestions -Text "zebra zeile" -Extra $extra | ForEach-Object { $_.Text })
        $t | Should -Contain "SET ZEBRA-ZEILEN (JEDE ZWEITE ZEILE HELLER)"
        # two letters: tickers only, no settings noise
        @(Get-CommandSuggestions -Text "st" -Extra $extra -Tickers @("STM") | ForEach-Object { $_.Text }) | Should -Not -Contain "SET STIL"
        # ticker commands stay as they were
        @(Get-CommandSuggestions -Text "NVDA G" -Extra $extra | ForEach-Object { $_.Text }) | Should -Contain "NVDA GP"
        (ConvertFrom-TerminalCommand "SET STIL").Func | Should -Be "SET"
        (ConvertFrom-TerminalCommand "MENU BEENDEN").Kind | Should -Be "Global"
    }
}

Describe "Notes, health, diagnostics (v5.5)" {
    It "stores notes trimmed with Windows line breaks and a length limit" {
        ConvertTo-NoteText "  Kaufgrund`nKI-Rechenzentren  " | Should -Be "Kaufgrund`r`nKI-Rechenzentren"
        (ConvertTo-NoteText ("x" * 5000)).Length | Should -Be 4000
        ConvertTo-NoteText "   " | Should -Be ""
    }
    It "shortens a note to one line" {
        Get-NoteSnippet "a`r`n  b" | Should -Be "a b"
        $s = Get-NoteSnippet ("wort " * 50) -Max 20
        $s.Length | Should -BeLessOrEqual 20
        $s | Should -Match ([string][char]0x2026 + '$')
    }
    It "rates the newest backup by age" {
        $now = [DateTime]"2026-11-24 12:00"
        (Get-BackupHealth -Newest $now.AddHours(-30) -Now $now).State | Should -Be "OK"
        (Get-BackupHealth -Newest $now.AddDays(-5) -Now $now).State | Should -Be "WARN"
        (Get-BackupHealth -Newest $now.AddDays(-20) -Now $now).State | Should -Be "ERR"
        (Get-BackupHealth -Newest $null -Now $now).State | Should -Be "ERR"
    }
    It "summarises the health checks" {
        $ok = Format-HealthReport -Checks @([PSCustomObject]@{ Name = "Daten"; State = "OK"; Detail = "7" })
        $ok | Should -Match "alles in Ordnung"
        $bad = Format-HealthReport -Checks @([PSCustomObject]@{ Name = "A"; State = "ERR"; Detail = "x" }, [PSCustomObject]@{ Name = "B"; State = "WARN"; Detail = "y" })
        $bad | Should -Match "1 Fehler, 1 Warnung"
        $bad | Should -Match "XX  A"
    }
    It "removes secrets and personal lists from the diagnostic config" {
        $c = [PSCustomObject]@{ Theme = "Dark"; PushTokenEnc = "geheim"; PushTopic = ""; Watchlist = @("NVDA"); Depots = @() }
        $d = Get-DiagnosticConfig $c
        $d.Theme | Should -Be "Dark"
        $d.PushTokenEnc | Should -Be "(entfernt)"
        $d.PushTopic | Should -Be ""
        $d.Watchlist | Should -Be "(entfernt)"
        $c.PushTokenEnc | Should -Be "geheim"
    }
    It "exports notes, cash, savings plans and drawings with the data" {
        foreach ($f in @("notes.json", "cash.json", "savingsplans.json", "drawings.json")) { @(Get-DataFileNames) | Should -Contain $f }
    }
    It "knows NOTE, HEALTH and DIAG" {
        (ConvertFrom-TerminalCommand "NVDA NOTE").Func | Should -Be "NOTE"
        (ConvertFrom-TerminalCommand "HEALTH").Kind | Should -Be "Global"
        (ConvertFrom-TerminalCommand "DIAG").Kind | Should -Be "Global"
    }
}

Describe "Privacy, export, dialog places (v5.5)" {
    It "knows which columns show amounts" {
        foreach ($h in @("Wert", "Betrag", "Stück", "Dividende", "Summe Jahr", "Beitrag heute", "Value", "Shares", "Kauf / Verkauf")) { Test-AmountColumn $h | Should -BeTrue }
        foreach ($h in @("Ticker", "Anteil", "Ist %", "Rendite", "Datum", "Kennzahl", "Signal", "")) { Test-AmountColumn $h | Should -BeFalse }
    }
    It "hides amounts with a currency but keeps percentages" {
        Hide-AmountsInText "Summe: 1.234,56 EUR (+3,2 %)" | Should -Be ("Summe: " + ([string][char]0x2022 * 3) + " EUR (+3,2 %)")
        Hide-AmountsInText "Dividende USD 120" | Should -Be ("Dividende USD " + ([string][char]0x2022 * 3))
        Hide-AmountsInText "Rendite 12,5 % p.a., Beta 1,2" | Should -Be "Rendite 12,5 % p.a., Beta 1,2"
        Hide-AmountsInText "" | Should -Be ""
    }
    It "writes CSV with quotes only where needed" {
        $csv = ConvertTo-CsvText -Headers @("Ticker", "Notiz") -Rows @(, @("NVDA", 'sagt "ja"; gut'))
        $csv | Should -Be ("Ticker;Notiz`r`nNVDA;" + '"sagt ""ja""; gut"')
    }
    It "builds an escaped HTML report" {
        $h = ConvertTo-HtmlReport -Title "A & B" -Sections @([PSCustomObject]@{ Title = "Seite"; Headers = @("x", "y"); Rows = @(, @("<b>", "1.234,50 EUR")); Note = "" }) -Footer "f"
        $h | Should -Match "<title>A &amp; B</title>"
        $h | Should -Match "&lt;b&gt;"
        $h | Should -Match '<td class="n">1.234,50 EUR</td>'
        $h | Should -Match "<footer>"
    }
    It "puts a dialog back only where a screen still is" {
        $scr = @([PSCustomObject]@{ X = 0; Y = 0; W = 1920; H = 1040 })
        (Get-DialogPlacement -Saved ([PSCustomObject]@{ X = 100; Y = 50; W = 700; H = 500 }) -Screens $scr).X | Should -Be 100
        Get-DialogPlacement -Saved ([PSCustomObject]@{ X = 2500; Y = 50; W = 700; H = 500 }) -Screens $scr | Should -BeNullOrEmpty
        Get-DialogPlacement -Saved ([PSCustomObject]@{ X = 100; Y = 1020; W = 700; H = 500 }) -Screens $scr | Should -BeNullOrEmpty
        (Get-DialogPlacement -Saved ([PSCustomObject]@{ X = 0; Y = 0; W = 3000; H = 2000 }) -Screens $scr).W | Should -Be 1920
        $two = $scr + @([PSCustomObject]@{ X = 1920; Y = 0; W = 1280; H = 1000 })
        (Get-DialogPlacement -Saved ([PSCustomObject]@{ X = 2500; Y = 50; W = 700; H = 500 }) -Screens $two).X | Should -Be 2500
        Get-DialogPlacement -Saved $null -Screens $scr | Should -BeNullOrEmpty
    }
}

Describe "Chart and signal cache (v5.5)" {
    It "labels the percent axis from the first visible bar" {
        Format-PctAxisLabel -Value 110 -Base 100 | Should -Be ("{0:+0.0;-0.0}%" -f 10.0)
        Format-PctAxisLabel -Value 100.01 -Base 100 | Should -Be "0%"
        Format-PctAxisLabel -Value 350 -Base 100 | Should -Be "+250%"
        Format-PctAxisLabel -Value 10 -Base 0 | Should -Be ""
    }
    It "turns a Ctrl-drag into a zoom window" {
        $z = Get-ZoomWindow -A 40 -B 80 -Total 100
        $z.Count | Should -Be 41
        $z.Offset | Should -Be 19
        (Get-ZoomWindow -A 80 -B 40 -Total 100).Offset | Should -Be 19
        (Get-ZoomWindow -A 95 -B 99 -Total 100 -MinBars 10).Count | Should -Be 10
        (Get-ZoomWindow -A 95 -B 99 -Total 100 -MinBars 10).Offset | Should -Be 0
        Get-ZoomWindow -A 5 -B 6 -Total 100 | Should -BeNullOrEmpty
        (Get-ZoomWindow -A 0 -B 99 -Total 100).Count | Should -Be 0
    }
    It "hits a zone inside and on its border" {
        Test-PointInZone -X 50 -Y 50 -X1 10 -Y1 10 -X2 100 -Y2 80 | Should -BeTrue
        Test-PointInZone -X 103 -Y 50 -X1 10 -Y1 10 -X2 100 -Y2 80 | Should -BeTrue
        Test-PointInZone -X 120 -Y 50 -X1 10 -Y1 10 -X2 100 -Y2 80 | Should -BeFalse
    }
    It "stores daily bars and signals and knows when they are stale" {
        $bars = [PSCustomObject]@{ Currency = "USD"; Dates = @(1..40 | ForEach-Object { "2026-01-{0:00}" -f ($_ % 28 + 1) }); Close = @(1..40 | ForEach-Object { 100.123456 + $_ }); High = @(1..40 | ForEach-Object { 102 + $_ }); Low = @(1..40 | ForEach-Object { 99 + $_ }); Volume = @(1..40 | ForEach-Object { 1000.4 }) }
        $sig = Get-TechnicalSignals -Closes ([double[]]$bars.Close) -Highs ([double[]]$bars.High) -Lows ([double[]]$bars.Low)
        $e = ConvertTo-DailyCacheEntry -Bars $bars -Sig $sig -Day "2026-11-24"
        $e.Close[0] | Should -Be 101.1235
        $e.Volume[0] | Should -Be 1000
        $e.Score | Should -Be $sig.Score
        Test-DailyCacheFresh -Entry $e -Day "2026-11-24" | Should -BeTrue
        Test-DailyCacheFresh -Entry $e -Day "2026-11-25" | Should -BeFalse
        Test-DailyCacheFresh -Entry $null -Day "2026-11-24" | Should -BeFalse
        ($e | ConvertTo-Json -Depth 4 | ConvertFrom-Json).Day | Should -Be "2026-11-24"
    }
    It "formats the signal column" {
        (Format-SignalCell ([PSCustomObject]@{ Close = @(1..30); Score = 3; Summary = "überwiegend positiv"; Positive = 4; Negative = 1; Day = "2026-11-24" })).Text | Should -Be "+3"
        (Format-SignalCell ([PSCustomObject]@{ Close = @(1..30); Score = -2; Summary = "gemischt"; Positive = 1; Negative = 3; Day = "x" })).Sign | Should -Be -1
        (Format-SignalCell $null).Text | Should -Be "-"
    }
}

Describe "Depot extras (v5.5)" {
    It "reads pause months in numbers and names" {
        (ConvertTo-PauseMonths "7, 8") -join "," | Should -Be "7,8"
        (ConvertTo-PauseMonths "Jul; Aug / dez 13 x") -join "," | Should -Be "7,8,12"
        (ConvertTo-PauseMonths "März") -join "," | Should -Be "3"
        @(ConvertTo-PauseMonths "").Count | Should -Be 0
        Format-PauseMonths @(12, 7, 7) | Should -Be "Jul, Dez"
    }
    It "skips pause months when booking a savings plan" {
        $pl = [PSCustomObject]@{ Day = 1; Start = "2026-05-01"; LastBooked = ""; Pause = "Jul, Aug" }
        (Get-DueSavingsDates -Plan $pl -Today "2026-10-15") -join "," | Should -Be "2026-05-01,2026-06-01,2026-09-01,2026-10-01"
        $old = [PSCustomObject]@{ Day = 1; Start = "2026-05-01"; LastBooked = "" }
        @(Get-DueSavingsDates -Plan $old -Today "2026-10-15").Count | Should -Be 6
    }
    It "raises the savings plan amount every full year" {
        $pl = [PSCustomObject]@{ Amount = 100; Increase = 5; Start = "2024-03-01" }
        Get-SavingsPlanAmount -Plan $pl -Date "2025-02-28" | Should -Be 100
        Get-SavingsPlanAmount -Plan $pl -Date "2025-03-01" | Should -Be 105
        Get-SavingsPlanAmount -Plan $pl -Date "2026-03-01" | Should -Be 110.25
        Get-SavingsPlanAmount -Plan ([PSCustomObject]@{ Amount = 50; Start = "2020-01-01" }) -Date "2026-01-01" | Should -Be 50
    }
    It "moves only the chosen sector or currency in a scenario" {
        $pos = @([PSCustomObject]@{ Sym = "NVDA"; Value = 1000; Group = "USD" }, [PSCustomObject]@{ Sym = "SAP.DE"; Value = 1000; Group = "EUR" })
        $sc = Get-GroupScenarioImpact -Positions $pos -Group "USD" -Pct -10
        $sc.Change | Should -Be -100
        $sc.Pct | Should -Be -5
        @($sc.Rows | Where-Object { $_.Sym -eq "SAP.DE" })[0].Change | Should -Be 0
        @($sc.Rows | Where-Object { $_.Sym -eq "NVDA" })[0].Beta | Should -Be 1
    }
    It "builds the dividend calendar per year and month" {
        $t = Get-DividendIncomeTable -Items @(@{ Date = "2025-03-10"; Amount = 10 }, @{ Date = "2026-03-02"; Amount = 12 }, @{ Date = "2026-03-20"; Amount = 3 }, @{ Date = "2026-11-01"; Amount = 5 }, @{ Date = "kaputt"; Amount = 99 })
        @($t.Rows).Count | Should -Be 2
        $t.Rows[0].Year | Should -Be 2026
        $t.Rows[0].Months[2] | Should -Be 15
        $t.Rows[0].Total | Should -Be 20
        $t.Rows[0].ChangePct | Should -Be 100
        [double]::IsNaN($t.Rows[1].ChangePct) | Should -BeTrue
        $t.Max | Should -Be 15
        $t.Total | Should -Be 30
        @((Get-DividendIncomeTable -Items @()).Rows).Count | Should -Be 0
    }
}

Describe "Trading212 import (v5.5)" {
    BeforeAll {
        $f = Join-Path $PSScriptRoot "testdata/trading212-history-sample.csv"
        $script:T212 = if (Test-Path $f) { ConvertFrom-CsvText ([IO.File]::ReadAllText($f)) } else { $null }
    }
    It "detects every Trading212 column" {
        if ($null -eq $script:T212) { Set-ItResult -Skipped -Because "testdata not next to the tests"; return }
        $m = Get-CsvColumnGuess -Headers $script:T212.Headers
        $m.Type | Should -Be 0; $m.Date | Should -Be 1; $m.Ident | Should -Be 2; $m.Name | Should -Be 4
        $m.Shares | Should -Be 7; $m.Price | Should -Be 8; $m.Currency | Should -Be 9; $m.Rate | Should -Be 10
        $m.Amount | Should -Be 13; $m.AmountCurrency | Should -Be 14; $m.Tax | Should -Be 15; $m.TaxCurrency | Should -Be 16
        @($m.FeeExtra) -join "," | Should -Be "17"
    }
    It "reads buys, sells, dividends and cash rows" {
        if ($null -eq $script:T212) { Set-ItResult -Skipped -Because "testdata not next to the tests"; return }
        $b = @(ConvertFrom-BrokerRows -Rows $script:T212.Rows -Map (Get-CsvColumnGuess -Headers $script:T212.Headers) -DefaultCurrency "EUR")
        $b.Count | Should -Be 8
        # deposit -> cash account
        $b[0].Cash | Should -BeTrue; $b[0].Type | Should -Be "Einzahlung"; $b[0].Amount | Should -Be 1000; $b[0].Currency | Should -Be "EUR"
        # fractional buy in USD, conversion fee from EUR into USD with the row's rate
        $b[1].Type | Should -Be "Kauf"; $b[1].Shares | Should -Be 0.5123456; $b[1].Price | Should -Be 180.2; $b[1].Currency | Should -Be "USD"
        [math]::Round($b[1].Fee, 4) | Should -Be ([math]::Round(0.13 * 1.0835, 4))
        $b[1].Ok | Should -BeTrue
        # EUR buy without fee
        $b[2].Currency | Should -Be "EUR"; $b[2].Fee | Should -Be 0
        # dividend: gross in USD from shares x per share, withholding tax as fee
        $b[3].Type | Should -Be "Dividende"; $b[3].Currency | Should -Be "USD"
        [math]::Round($b[3].Price, 5) | Should -Be ([math]::Round(0.5123456 * 0.24, 5)); $b[3].Fee | Should -Be 0.02
        # interest -> cash, currency conversion skipped, sell, withdrawal negative
        $b[4].Type | Should -Be "Zinsen"; $b[4].Amount | Should -Be 0.45
        $b[5].Ok | Should -BeFalse
        $b[6].Type | Should -Be "Verkauf"; $b[6].Shares | Should -Be 0.2; [math]::Round($b[6].Fee, 3) | Should -Be 0.054
        $b[7].Type | Should -Be "Auszahlung"; $b[7].Amount | Should -Be -200
    }
    It "does not guess a fee currency when the numbers do not agree" {
        $map = @{ Date = 0; Type = 1; Ident = 2; Shares = 3; Price = 4; Amount = 5; Fee = -1; Tax = -1; Currency = 6; Name = -1; AmountCurrency = 7; TaxCurrency = -1; Rate = 8; FeeExtra = @(9) }
        $b = @(ConvertFrom-BrokerRows -Rows @(, @("2024-01-02", "Market buy", "TSTA", "1", "100", "50", "USD", "EUR", "1.1", "0.5")) -Map $map)
        $b[0].Fee | Should -Be 0
        $b[0].Note | Should -Match "nicht umgerechnet"
        $b[0].Ok | Should -BeTrue
    }
}

Describe "Analysis without new providers (v5.7)" {
    It "builds weekly bars from daily bars" {
        $d = @("2026-01-05", "2026-01-06", "2026-01-09", "2026-01-12", "2026-01-16")
        $w = ConvertTo-WeeklyBars -Dates $d -Close @(10, 11, 12, 13, 9) -High @(10, 15, 12, 13, 14) -Low @(9, 10, 8, 12, 9) -Volume @(1, 1, 1, 2, 2)
        @($w.Dates) -join "," | Should -Be "2026-01-09,2026-01-16"
        @($w.Close) -join "," | Should -Be "12,9"
        $w.High[0] | Should -Be 15; $w.Low[0] | Should -Be 8; $w.Volume[1] | Should -Be 4
    }
    It "explains daily vs. weekly signals in one sentence" {
        (Get-TimeframeVerdict -Daily 4 -Weekly 3).Tone | Should -Be 1
        (Get-TimeframeVerdict -Daily 4 -Weekly -3).Text | Should -Match "Erholung"
        (Get-TimeframeVerdict -Daily -4 -Weekly 5).Text | Should -Match "Rücksetzer"
        (Get-TimeframeVerdict -Daily 0 -Weekly 0).Text | Should -Match "Kein klares Bild"
        (Get-TimeframeVerdict -Daily 4 -Weekly 0 -HasWeekly $false).Text | Should -Match "Wochendaten"
    }
    It "finds signal changes between two days" {
        $old = [PSCustomObject]@{ Day = "2026-11-23"; Score = 0; Close = @(100, 101); Support = 95.0; Resistance = 105.0 }
        $up = @(Get-SignalChanges -Old $old -New ([PSCustomObject]@{ Day = "2026-11-24"; Score = 4; Close = @(101, 106) }))
        @($up | ForEach-Object { $_.Kind }) -join "," | Should -Be "Up,AboveResistance"
        $down = @(Get-SignalChanges -Old $old -New ([PSCustomObject]@{ Day = "2026-11-24"; Score = -3; Close = @(101, 94) }))
        @($down | ForEach-Object { $_.Kind }) -join "," | Should -Be "Down,BelowSupport"
        @(Get-SignalChanges -Old $old -New ([PSCustomObject]@{ Day = "2026-11-23"; Score = 4; Close = @(1, 2) })).Count | Should -Be 0
        @(Get-SignalChanges -Old $null -New $old).Count | Should -Be 0
    }
    It "marks 50/200 crossings" {
        $cl = @(1..400 | ForEach-Object { if ($_ -lt 220) { 300.0 - $_ } else { 80.0 + ($_ - 220) * 2 } })
        $m = @(Get-MaCrossMarkers -Closes $cl -Dates @(1..400 | ForEach-Object { "d$_" }))
        $m.Count | Should -Be 1
        $m[0].Kind | Should -Be "Golden"
        @(Get-MaCrossMarkers -Closes @(1.0, 2.0) -Dates @("a", "b")).Count | Should -Be 0
    }
    It "reads a peer list" {
        (ConvertTo-PeerList "amd, INTC nvda;amd x!" -Self "NVDA") -join "," | Should -Be "AMD,INTC"
        @(ConvertTo-PeerList "").Count | Should -Be 0
        @(ConvertTo-PeerList ((1..20 | ForEach-Object { "T$_" }) -join " ")).Count | Should -Be 15
    }
    It "keeps one valuation snapshot per day and compares with it" {
        $h = @()
        foreach ($i in 1..25) { $h = Add-FundSnapshot -History $h -Fund ([PSCustomObject]@{ TrailingPE = 20.0 + $i; DivYield = 0.01 }) -Day ("2026-01-{0:00}" -f $i) }
        $h = Add-FundSnapshot -History $h -Fund ([PSCustomObject]@{ TrailingPE = 50.0 }) -Day "2026-01-25"
        $h.Count | Should -Be 25
        $h[-1].TrailingPE | Should -Be 50
        $r = @(Get-ValuationVsHistory -History $h -Fund ([PSCustomObject]@{ TrailingPE = 50.0 }))
        $pe = @($r | Where-Object { $_.Key -eq "TrailingPE" })[0]
        $pe.Rank | Should -BeGreaterThan 90
        $pe.Note | Should -Match "teuer"
        $pe.Since | Should -Be "2026-01-01"
        @($r | Where-Object { $_.Key -eq "DivYield" })[0].Rank | Should -Be 50
        @(Get-ValuationVsHistory -History @($h | Select-Object -First 5) -Fund $null).Count | Should -Be 0
        (Add-FundSnapshot -History @() -Fund ([PSCustomObject]@{ MarketCap = 1 }) -Day "2026-01-01").Count | Should -Be 0
    }
    It "reads RSS and Atom feeds and ignores DTD tricks" {
        $rss = '<?xml version="1.0"?><rss version="2.0"><channel><title>Wirtschaft</title><item><title>NVIDIA &amp; Co legen zu</title><link>https://example.at/a?x=1</link><pubDate>Tue, 24 Nov 2026 10:00:00 +0100</pubDate></item><item><title>Ohne Link</title><link>javascript:alert(1)</link></item></channel></rss>'
        $it = @(ConvertFrom-RssFeed -Text $rss)
        $it.Count | Should -Be 2
        $it[0].Title | Should -Be "NVIDIA & Co legen zu"
        $it[0].Publisher | Should -Be "Wirtschaft"
        $it[0].Time.Year | Should -Be 2026
        $it[1].Link | Should -Be ""
        $atom = '<feed xmlns="http://www.w3.org/2005/Atom"><title>A</title><entry><title>Hallo</title><link href="https://x.y/1"/><updated>2026-11-24T09:00:00Z</updated></entry></feed>'
        @(ConvertFrom-RssFeed -Text $atom)[0].Link | Should -Be "https://x.y/1"
        @(ConvertFrom-RssFeed -Text '<!DOCTYPE r [<!ENTITY e SYSTEM "file:///c:/windows/win.ini">]><rss><channel><item><title>&e;</title></item></channel></rss>').Count | Should -Be 0
        @(ConvertFrom-RssFeed -Text '{"json": 1}').Count | Should -Be 0
    }
    It "merges RSS into the news feed and finds our tickers by name" {
        Get-NewsNameKey "NVIDIA Corporation" | Should -Be "nvidia"
        Get-NewsNameKey "Apple Inc." | Should -Be "apple"
        $feed = @([PSCustomObject]@{ Key = "https://y.com/1"; Title = "Alt"; Publisher = "Yahoo"; Link = "https://y.com/1"; Time = [DateTime]"2026-11-23 08:00"; Syms = @("NVDA") })
        $rss = @([PSCustomObject]@{ Title = "Nvidia mit Rekord"; Publisher = "Standard"; Link = "https://s.at/2"; Time = [DateTime]"2026-11-24 09:00"; Tickers = @() },
                 [PSCustomObject]@{ Title = "Doppelt"; Publisher = "Standard"; Link = "https://y.com/1?utm=x"; Time = [DateTime]"2026-11-24 09:00"; Tickers = @() })
        $m = @(Add-RssToFeed -Feed $feed -RssItems $rss -NameMap @{ NVDA = "nvidia" } -Now ([DateTime]"2026-11-24 12:00"))
        $m.Count | Should -Be 2
        $m[0].Title | Should -Be "Nvidia mit Rekord"
        @($m[0].Syms) -join "," | Should -Be "NVDA"
        (ConvertTo-FeedList "https://a.b/rss, ftp://x  https://c.d/feed;https://a.b/rss") -join " " | Should -Be "https://a.b/rss https://c.d/feed"
    }
    It "builds data URLs in one place and names the provider" {
        Get-ProviderUrl -Kind "Daily" -Symbol "SAP.DE" | Should -Be "https://query1.finance.yahoo.com/v8/finance/chart/SAP.DE?interval=1d&range=1y"
        Get-ProviderUrl -Kind "Search" -Symbol "NVDA" -NewsCount 5 | Should -Match "newsCount=5"
        Get-ProviderOfUrl "https://query1.finance.yahoo.com/v8/x" | Should -Be "Yahoo"
        Get-ProviderOfUrl "https://www.derstandard.at/rss/wirtschaft" | Should -Be "RSS: derstandard.at"
        (ConvertFrom-TerminalCommand "NVDA PEER AMD").Func | Should -Be "PEER"
        Get-ThemeNames | Should -Contain "Contrast"
    }
}

Describe "Data providers (V6)" {
    It "maps symbols the free tiers cover" {
        ConvertTo-ProviderSymbol "AAPL" "TwelveData" | Should -Be "AAPL"
        ConvertTo-ProviderSymbol "BRK-B" "TwelveData" | Should -Be "BRK.B"
        ConvertTo-ProviderSymbol "SAP.DE" "Finnhub" | Should -Be ""
        ConvertTo-ProviderSymbol "^GSPC" "Finnhub" | Should -Be ""
        Get-ProviderOfUrl "https://api.twelvedata.com/time_series?symbol=X" | Should -Be "TwelveData"
        Get-ProviderOfUrl "https://finnhub.io/api/v1/quote" | Should -Be "Finnhub"
    }
    It "never logs API keys" {
        $t = Hide-ApiKeys "HTTP 403: https://finnhub.io/api/v1/quote?symbol=AAPL&token=abc123 / https://api.twelvedata.com/q?apikey=zz&y=1"
        $t | Should -Not -Match "abc123"
        $t | Should -Not -Match "zz&"
        $t | Should -Match "token=\*\*\*"
    }
    It "reads errors, also the HTTP-200 errors of Twelve Data" {
        Get-ProviderError ('{"code":401,"message":"apikey is incorrect","status":"error"}' | ConvertFrom-Json) | Should -Match "401"
        Get-ProviderError ('{"error":"You don''t have access to this resource."}' | ConvertFrom-Json) | Should -Match "access"
        Get-ProviderError ('{"s":"no_data"}' | ConvertFrom-Json) | Should -Be "keine Daten"
        Get-ProviderError $null | Should -Be "keine Antwort"
        Get-ProviderError ('{"c":[1]}' | ConvertFrom-Json) | Should -Be ""
    }
    It "converts Twelve Data and Finnhub daily bars" {
        $td = '{"meta":{"symbol":"AAPL","currency":"USD"},"values":[{"datetime":"2026-11-24","open":"230","high":"233","low":"229","close":"232.5","volume":"1000"},{"datetime":"2026-11-21","open":"228","high":"231","low":"227","close":"230.1","volume":"900"}],"status":"ok"}' | ConvertFrom-Json
        $b = ConvertFrom-TwelveDataSeries $td
        @($b.Dates) -join "," | Should -Be "2026-11-21,2026-11-24"
        $b.Close[1] | Should -Be 232.5
        $b.Currency | Should -Be "USD"
        $b.Source | Should -Be "TwelveData"
        ConvertFrom-TwelveDataSeries ('{"status":"error","code":429,"message":"limit"}' | ConvertFrom-Json) | Should -BeNullOrEmpty
        $fc = ConvertFrom-FinnhubCandles ('{"c":[100,101.5],"h":[101,102],"l":[99,100],"o":[100,101],"s":"ok","t":[1763942400,1764028800],"v":[5,6]}' | ConvertFrom-Json)
        @($fc.Dates) -join "," | Should -Be "2025-11-24,2025-11-25"
        $fc.Volume[1] | Should -Be 6
    }
    It "keeps the per-minute and per-day budget" {
        $now = [DateTime]"2026-11-24 12:00:00"
        $log = @(1..7 | ForEach-Object { [PSCustomObject]@{ T = $now.AddSeconds(-10); P = "TwelveData" } })
        (Test-ProviderBudget -Log $log -Provider "TwelveData" -Now $now).Ok | Should -BeFalse
        (Test-ProviderBudget -Log $log -Provider "TwelveData" -Now $now.AddSeconds(61)).Ok | Should -BeTrue
        (Test-ProviderBudget -Log @() -Provider "TwelveData" -Now $now -DayCount 780).Reason | Should -Match "Tageslimit"
        (Test-ProviderBudget -Log $log -Provider "Finnhub" -Now $now).Ok | Should -BeTrue
        (Test-ProviderBudget -Log @() -Provider "Yahoo" -Now $now).Ok | Should -BeTrue
    }
    It "reads figures over the years and the quarterly valuation history" {
        $m = '{"series":{"annual":{"pe":[{"period":"2025-09-30","v":30.1},{"period":"2024-09-30","v":28.2}],"netMargin":[{"period":"2025-09-30","v":0.243}]},"quarterly":{"pe":[{"period":"2026-06-30","v":33},{"period":"2026-03-31","v":31}],"ps":[{"period":"2026-06-30","v":8}]}}}' | ConvertFrom-Json
        $ms = ConvertFrom-FinnhubMetricSeries $m
        $pe = @($ms.Annual | Where-Object { $_.Key -eq "pe" })[0]
        @($pe.Points | ForEach-Object { $_.Year }) -join "," | Should -Be "2024,2025"
        [math]::Round(@($ms.Annual | Where-Object { $_.Key -eq "netMargin" })[0].Points[0].Value, 1) | Should -Be 24.3
        Format-SeriesTrend -Points $pe.Points | Should -Match "2024"
        @($ms.Quarterly).Count | Should -Be 2
        $ms.Quarterly[1].PriceToSales | Should -Be 8
        @((ConvertFrom-FinnhubMetricSeries ('{"error":"x"}' | ConvertFrom-Json)).Annual).Count | Should -Be 0
    }
    It "puts earnings surprise and price reaction together" {
        Get-EarningsReaction -Dates @("2026-07-29", "2026-07-30", "2026-07-31") -Closes @(200, 202, 210) -ReportDate "2026-07-30" -Hour "amc" | Should -BeGreaterThan 3.9
        [math]::Round((Get-EarningsReaction -Dates @("2026-07-29", "2026-07-30", "2026-07-31") -Closes @(200, 202, 210) -ReportDate "2026-07-30" -Hour "bmo"), 2) | Should -Be 1
        [double]::IsNaN((Get-EarningsReaction -Dates @("2026-01-01") -Closes @(1) -ReportDate "2026-07-30")) | Should -BeTrue
        $e = '[{"actual":1.6,"estimate":1.5,"period":"2026-06-30","surprisePercent":6.67},{"actual":1.4,"estimate":1.45,"period":"2026-03-31"}]' | ConvertFrom-Json
        $cal = '{"earningsCalendar":[{"date":"2026-07-30","hour":"amc"},{"date":"2026-05-01","hour":"amc"}]}' | ConvertFrom-Json
        $r = @(ConvertFrom-FinnhubEarnings -Earnings $e -Calendar $cal -Dates @("2026-07-29", "2026-07-30", "2026-07-31") -Closes @(200, 202, 210))
        $r[0].Period | Should -Be "2026-06-30"; $r[0].Date | Should -Be "2026-07-30"
        [math]::Round($r[0].ReactionPct, 2) | Should -Be 3.96
        [math]::Round($r[1].SurprisePct, 2) | Should -Be -3.45
        [double]::IsNaN($r[1].ReactionPct) | Should -BeTrue
    }
    It "describes the analyst trend" {
        $rec = '[{"buy":20,"hold":8,"period":"2026-11-01","sell":1,"strongBuy":12,"strongSell":0},{"buy":19,"hold":9,"period":"2026-10-01","sell":1,"strongBuy":10,"strongSell":0},{"buy":18,"hold":10,"period":"2026-09-01","sell":2,"strongBuy":9,"strongSell":0},{"buy":15,"hold":12,"period":"2026-08-01","sell":3,"strongBuy":8,"strongSell":1}]' | ConvertFrom-Json
        $t = Get-RecommendationTrend $rec
        $t.Now | Should -Be "32 Kauf / 8 Halten / 1 Verkauf"
        $t.PeriodBefore | Should -Be "2026-08-01"
        $t.Trend | Should -Be "positiver"
        Get-RecommendationTrend @() | Should -BeNullOrEmpty
    }
    It "reports what the keys deliver" {
        $txt = Format-ProviderReport @([PSCustomObject]@{ Provider = "Finnhub"; Kind = "Metric"; Ok = $true; Detail = "" }, [PSCustomObject]@{ Provider = "Finnhub"; Kind = "PriceTarget"; Ok = $false; Detail = "Premium" })
        $txt | Should -Match "OK Kennzahlen"
        $txt | Should -Match "-- Kursziele"
        Test-ProviderCacheFresh -Entry ([PSCustomObject]@{ Day = "2026-11-24" }) -Day "2026-11-24" | Should -BeTrue
        Test-ProviderCacheFresh -Entry $null -Day "2026-11-24" | Should -BeFalse
        (ConvertFrom-TerminalCommand "PROV").Kind | Should -Be "Global"
    }
}

Describe "Release files (v4.8)" {
    It "has version.json matching the widget version" {
        $ui = Join-Path $PSScriptRoot "TerminalWidget.ps1"
        $vf = Join-Path $PSScriptRoot "version.json"
        if (-not (Test-Path $ui) -or -not (Test-Path $vf)) { Set-ItResult -Skipped -Because "repository files not next to the tests"; return }
        $line = @(Get-Content -Path $ui -Encoding UTF8 | Where-Object { $_ -match '^\$script:AppVersion\s*=' })[0]
        $app = [regex]::Match($line, '"([^"]+)"').Groups[1].Value
        Get-LatestVersionFromJson (Get-Content $vf -Raw | ConvertFrom-Json) | Should -Be $app
    }
}


Describe "Design tokens (V7.0)" {
    It "keeps every spacing and radius value on the 4 px grid" {
        $s = Get-DesignScale
        foreach ($v in $s.Space.PSObject.Properties.Value) { ($v % 4) | Should -Be 0 }
        foreach ($v in $s.Radius.PSObject.Properties.Value) { ($v % 4) | Should -Be 0 }
    }
    It "keeps motion durations at 150 ms or less" {
        foreach ($v in (Get-DesignScale).Motion.PSObject.Properties.Value) { $v | Should -BeLessOrEqual 150 }
    }
    It "rounds <Value> px at scale <Scale> to <Expected>" -TestCases @(
        @{ Value = 10; Scale = 1.0; Expected = 12 }
        @{ Value = 9;  Scale = 1.0; Expected = 8 }
        @{ Value = 13; Scale = 1.5; Expected = 12 }
        @{ Value = 0;  Scale = 2.0; Expected = 0 }
    ) {
        ConvertTo-GridPx -Value $Value -Scale $Scale | Should -Be $Expected
    }
    It "computes WCAG contrast: black on white is 21, equal colours are 1" {
        [math]::Round((Get-ContrastRatio -A @(0, 0, 0) -B @(255, 255, 255)), 2) | Should -Be 21
        [math]::Round((Get-ContrastRatio -A @(40, 50, 60) -B @(40, 50, 60)), 2) | Should -Be 1
    }
    It "derives a lighter hover and a darker pressed accent on dark surfaces" {
        $a = @(56, 189, 248)
        $st = Get-AccentStates -Rgb $a -DarkSurface $true
        (Get-RelativeLuminance -Rgb $st.Hover) | Should -BeGreaterThan (Get-RelativeLuminance -Rgb $a)
        (Get-RelativeLuminance -Rgb $st.Pressed) | Should -BeLessThan (Get-RelativeLuminance -Rgb $a)
    }
    It "derives darker hover and pressed accents on light surfaces" {
        $a = @(2, 132, 199)
        $st = Get-AccentStates -Rgb $a -Surface @(255, 255, 255) -DarkSurface $false
        (Get-RelativeLuminance -Rgb $st.Hover) | Should -BeLessThan (Get-RelativeLuminance -Rgb $a)
        (Get-RelativeLuminance -Rgb $st.Pressed) | Should -BeLessThan (Get-RelativeLuminance -Rgb $st.Hover)
    }
    It "picks readable text on the accent" {
        ((Get-AccentStates -Rgb @(255, 221, 0)).OnAccent -join ",") | Should -Be "0,0,0"
        ((Get-AccentStates -Rgb @(0, 0, 128)).OnAccent -join ",") | Should -Be "255,255,255"
    }
    It "has a token map without duplicates and with the core roles" {
        $m = Get-TokenMap
        @($m.Values | Select-Object -Unique).Count | Should -Be $m.Count
        foreach ($k in @("surface.card", "text.primary", "text.muted", "text.disabled", "accent", "accent.hover", "accent.pressed", "accent.subtle", "accent.text")) {
            $m.Contains($k) | Should -BeTrue
        }
    }
}

Describe "Status bar and toasts (V7.0)" {
    It "shows the request rate when it is known (V7.1)" {
        $p = @(Get-StatusBarParts -Stand "10:00:00" -AgeSec 5 -Market "Börse offen" -ReqPerMin 12)
        $p[2] | Should -Be "12 Abfragen/min"
        @(Get-StatusBarParts -Stand "10:00:00" -AgeSec 5).Count | Should -Be 1
    }
    It "lists data age, market and privacy mode" {
        $p = @(Get-StatusBarParts -Stand "10:00:00" -AgeSec 30 -Market "Börse offen" -Privacy $true)
        $p.Count | Should -Be 3
        $p[0] | Should -Be "Stand 10:00:00 (vor 30 s)"
        $p[2] | Should -Be "Privat-Modus"
    }
    It "switches to minutes when the data is older than 90 seconds" {
        @(Get-StatusBarParts -Stand "10:00:00" -AgeSec 300)[0] | Should -Be "Stand 10:00:00 (vor 5 min)"
    }
    It "says so when there is no data yet" {
        @(Get-StatusBarParts)[0] | Should -Be "Noch keine Daten"
    }
}

Describe "Chip row layout (V7.0)" {
    It "shows every chip when they fit" {
        $l = Get-ChipLayout -Widths @(50, 60, 70) -Available 400
        $l.Shown | Should -Be 3
        $l.Overflow | Should -BeFalse
        ($l.X -join ",") | Should -Be "0,56,122"
    }
    It "moves the rest behind a more chip when the row is too narrow" {
        $l = Get-ChipLayout -Widths @(50, 60, 70) -Available 150
        $l.Shown | Should -Be 1
        $l.Overflow | Should -BeTrue
    }
    It "always keeps the first chip" {
        (Get-ChipLayout -Widths @(200, 60) -Available 100).Shown | Should -Be 1
    }
    It "handles an empty list" {
        (Get-ChipLayout -Widths @() -Available 300).Shown | Should -Be 0
    }
}

Describe "Analyse key figure tiles (V7.0)" {
    It "builds the tiles and colours gains and losses" {
        $k = @(Get-AnalysisKpiTiles -Value 10000 -Invested 8000 -Dividends 200 -Xirr 0.123 -WindowResult 150 -RangeLabel "1J")
        ($k | ForEach-Object { $_.Id }) -join "," | Should -Be "Value,Result,Xirr,Div,Window"
        ($k | Where-Object { $_.Id -eq "Result" }).Kind | Should -Be "up"
        ($k | Where-Object { $_.Id -eq "Value" }).Kind | Should -Be "flat"
    }
    It "marks a loss as down and leaves out the period tile without a window" {
        $k = @(Get-AnalysisKpiTiles -Value 7000 -Invested 8000 -Dividends 0 -Xirr -0.05)
        ($k | Where-Object { $_.Id -eq "Result" }).Kind | Should -Be "down"
        ($k | Where-Object { $_.Id -eq "Xirr" }).Kind | Should -Be "down"
        @($k).Count | Should -Be 4
    }
    It "shows a dash when the XIRR is unknown" {
        (@(Get-AnalysisKpiTiles -Value 100 -Invested 100 -Dividends 0 -Xirr ([double]::NaN)) | Where-Object { $_.Id -eq "Xirr" }).Text | Should -Be "-"
    }
}

Describe "V7.1 helpers" {
    It "rolls a number towards the target and ends exactly there" {
        $r = @(Get-RollValues -From 100 -To 110 -Steps 5)
        $r.Count | Should -Be 5
        $r[0] | Should -BeGreaterThan 100
        $r[0] | Should -BeLessThan 110
        $r[4] | Should -Be 110
        ($r[1] - $r[0]) | Should -BeLessThan ($r[0] - 100)
    }
    It "builds donut slices that add up to 360 degrees and merges small shares" {
        $s = @(Get-DonutSlices -Items @(@{Name="A";Value=50},@{Name="B";Value=45},@{Name="C";Value=2},@{Name="D";Value=3}) -MinPct 4)
        ($s | ForEach-Object { $_.Name }) -join "," | Should -Be "A,B,Rest"
        (($s | Measure-Object -Property Sweep -Sum).Sum) | Should -BeGreaterThan 359.99
        $s[0].Start | Should -Be 0
        @(Get-DonutSlices -Items @()).Count | Should -Be 0
    }
    It "caps the number of donut slices" {
        $items = 1..12 | ForEach-Object { [PSCustomObject]@{ Name = "T$_"; Value = 10 } }
        @(Get-DonutSlices -Items $items -MinPct 0 -MaxSlices 6).Count | Should -Be 6
    }
    It "places a value among peers" {
        $d = Get-DotPlotLayout -Value 20 -Peers @(10, 30, 40)
        $d.Rank | Should -Be 2
        $d.Pos | Should -BeGreaterThan 0.3
        $d.Pos | Should -BeLessThan 0.4
        $d.Median | Should -Be 25
        (Get-DotPlotLayout -Value 5 -Peers @(5, 5)).Pos | Should -Be 0.5
    }
    It "computes the valuation band and its state" {
        $b = Get-ValuationBand -Multiples @(10, 12, 14, 16, 18, 20, 22) -Eps 5 -Price 40
        $b.Mid | Should -Be 80
        $b.State | Should -Be "cheap"
        (Get-ValuationBand -Multiples @(10, 12, 14, 16, 18, 20, 22) -Eps 5 -Price 200).State | Should -Be "expensive"
        Get-ValuationBand -Multiples @(10, 12) -Eps 5 -Price 40 | Should -BeNullOrEmpty
    }
    It "lays out the chart panes" {
        $l = Get-PaneLayout -Total 400 -PaneCount 2 -Divider 0.7
        $l.Main | Should -Be 280
        $l.Pane | Should -Be 60
        (Get-PaneLayout -Total 400 -PaneCount 2 -Divider 0.99).Main | Should -Be 304
        (Get-PaneLayout -Total 150 -PaneCount 3 -Divider 0.7).Pane | Should -Be 48
        (Get-PaneLayout -Total 400 -PaneCount 0).Main | Should -Be 400
    }
    It "lays out segments so that they fill the width" {
        $s = @(Get-SegmentLayout -Labels @("1T", "1W", "1M", "Alles") -Width 300)
        $s.Count | Should -Be 4
        ($s[3].X + $s[3].W) | Should -Be 300
        $s[3].W | Should -BeGreaterThan $s[0].W
    }
}

Describe "V7.1.1 fixes" {
    It "formats numbers for input fields with the system decimal separator" {
        $de = [System.Globalization.CultureInfo]::GetCultureInfo("de-AT")
        $us = [System.Globalization.CultureInfo]::GetCultureInfo("en-US")
        Format-EditNumber -Value 59.4 -Culture $de | Should -Be "59,4"
        Format-EditNumber -Value 59.4 -Culture $us | Should -Be "59.4"
        Format-EditNumber -Value 40 -Culture $de | Should -Be "40"
        Format-EditNumber -Value 1234.567 -Culture $de | Should -Be "1234,567"
    }
    It "reads a formatted input number back unchanged" {
        $de = [System.Globalization.CultureInfo]::GetCultureInfo("de-AT")
        foreach ($v in @(59.4, 0.12345678, 1234.567, 1000000, 40)) {
            Parse-DecimalInput (Format-EditNumber -Value $v -Culture $de) | Should -Be $v
        }
    }
    It "counts only log errors of the running process" {
        $lines = @(
            "2026-11-24 13:00:00 [INFO] Script start (PID 11, PowerShell 5.1)",
            "2026-11-24 13:00:01 [ERROR] old",
            "2026-11-26 05:52:25 [INFO] Script start (PID 22, PowerShell 5.1)",
            "2026-11-26 05:52:26 [INFO] fine")
        Get-LogErrorCount -Lines $lines -ProcessId 22 | Should -Be 0
        Get-LogErrorCount -Lines ($lines + "2026-11-26 06:00:00 [ERROR] new") -ProcessId 22 | Should -Be 1
    }
    It "counts all errors when the start line is no longer in the tail" {
        Get-LogErrorCount -Lines @("x [ERROR] a", "x [INFO] b", "x [ERROR] c") -ProcessId 22 | Should -Be 2
        Get-LogErrorCount -Lines @() -ProcessId 22 | Should -Be 0
    }
}

Describe "V7.3 helpers" {
    It "explains a missing XIRR" {
        Get-XirrNote -Xirr 0.1 -FirstDate "2026-11-02" -Today "2026-11-26" | Should -Be ""
        Get-XirrNote -Xirr ([double]::NaN) -FirstDate "2026-11-02" -Today "2026-11-26" | Should -Be "ab 30 Tagen (noch 6 Tage)"
        Get-XirrNote -Xirr ([double]::NaN) -FirstDate "2026-10-28" -Today "2026-11-26" | Should -Be "ab 30 Tagen (noch 1 Tag)"
        Get-XirrNote -Xirr ([double]::NaN) -FirstDate "2026-10-27" -Today "2026-11-26" | Should -Be "nicht berechenbar"
        Get-XirrNote -Xirr ([double]::NaN) | Should -Be "keine gebuchte Position"
    }
    It "shows the XIRR note in the tile" {
        $k = @(Get-AnalysisKpiTiles -Value 100 -Invested 100 -Dividends 0 -Xirr ([double]::NaN) -XirrNote "ab 30 Tagen (noch 6 Tage)")
        ($k | Where-Object { $_.Id -eq "Xirr" }).Sub | Should -Be "ab 30 Tagen (noch 6 Tage)"
    }
    It "says why polling is slower" {
        $now = [DateTime]"2026-11-26T06:00:00"
        Get-PollNote -AllClosed $true -ClosedMinutes 10 -RefreshSec 60 -Now $now | Should -Be "Märkte zu - Abfrage alle 10 min"
        Get-PollNote -AllClosed $false -ClosedMinutes 10 -RefreshSec 60 -Now $now | Should -Be ""
        Get-PollNote -AllClosed $true -ClosedMinutes 0 -RefreshSec 60 -Now $now | Should -Be ""
        Get-PollNote -AllClosed $true -ClosedMinutes 1 -RefreshSec 60 -Now $now | Should -Be ""
        Get-PollNote -AllClosed $false -ClosedMinutes 10 -RefreshSec 60 -BackoffUntil $now.AddMinutes(5) -Now $now | Should -Be "Yahoo-Pause bis 06:05"
        Get-PollNote -AllClosed $false -ClosedMinutes 10 -RefreshSec 60 -BackoffUntil ([DateTime]::MinValue) -Now $now | Should -Be ""
    }
    It "shortens the market status" {
        Get-ShortMarketText "Zu - öffnet in 2h 49m" | Should -Be "Zu · 2h 49m"
        Get-ShortMarketText "Offen - zu in 3h" | Should -Be "Offen · 3h"
        Get-ShortMarketText "Handel 24/7" | Should -Be "Handel 24/7"
        Get-ShortMarketText "Closed - opens in 2h 49m" | Should -Be "Closed · 2h 49m"
    }
    It "keeps price columns unmasked when the header names the currency" {
        Test-AmountColumn "EK (USD)" | Should -BeFalse
        Test-AmountColumn "Kurs (USD)" | Should -BeFalse
    }
}

Describe "V7.5 helpers" {
    It "keeps the design widths at the minimum size" {
        $w = Get-WatchPanelWidths -ViewW 756
        $w.Grid | Should -Be 480
        $w.Alarm | Should -Be 252
        $w.Detail | Should -Be 0
        $w.CanDetail | Should -BeFalse
    }
    It "widens the alarm column and adds details in a very wide view" {
        $w = Get-WatchPanelWidths -ViewW 1900
        $w.Alarm | Should -Be 420
        $w.Detail | Should -Be 260
        ($w.Grid + $w.Detail + $w.Alarm + 32) | Should -Be 1900
        $off = Get-WatchPanelWidths -ViewW 1900 -WantDetail $false
        $off.Detail | Should -Be 0
        $off.CanDetail | Should -BeTrue
        ($off.Grid + $off.Alarm + 24) | Should -Be 1900
    }
    It "never lets the list get smaller than 480" {
        foreach ($vw in 756, 800, 900, 1000, 1200, 1600) { (Get-WatchPanelWidths -ViewW $vw).Grid | Should -BeGreaterOrEqual 480 }
    }
    It "builds detail lines and hides the share count in privacy mode" {
        $q = [PSCustomObject]@{ Currency = "USD"; LongName = "Nvidia"; Price = 100.0; ChangePct = 1.5; PrevClose = 98.5; ExtPrice = 0.0; ExtPct = 0.0; High52 = 125.0; Low52 = 50.0; Rsi14 = [double]::NaN }
        $pos = [PSCustomObject]@{ Shares = 7.0; AvgPrice = 80.0; Currency = "USD" }
        $a = (@(Get-TickerDetailLines -Symbol "NVDA" -Quote $q -Position $pos -Note "Test") -join "`n")
        $a | Should -Match "Nvidia"
        $a | Should -Match "52W Hoch"
        $a | Should -Match "Notiz"
        $a | Should -Not -Match "RSI"
        $a | Should -Match "Stück     7"
        $b = (@(Get-TickerDetailLines -Symbol "NVDA" -Quote $q -Position $pos -Privacy $true) -join "`n")
        $b | Should -Not -Match "Stück     7"
        (@(Get-TickerDetailLines -Symbol "X") -join "|") | Should -Be "X|Noch keine Kursdaten."
    }
}

Describe "News sources and reading (v7.7)" {
    It "passes the logic cases" {
        $script:fail = New-Object System.Collections.Generic.List[string]
        function T($name, $got, $want) { if ([string]$got -cne [string]$want) { $script:fail.Add("$name : got '$got' want '$want'") } }
        T "one date" (Get-EarliestDate -Dates @("2026-11-02")) "2026-11-02"
        T "two dates" (Get-EarliestDate -Dates @("2026-11-02", "2025-01-03")) "2025-01-03"
        T "no date" (Get-EarliestDate -Dates @()) ""
        T "xirr note one" (Get-XirrNote -Xirr ([double]::NaN) -FirstDate (Get-EarliestDate @("2026-11-02")) -Today "2026-11-26") "ab 30 Tagen (noch 6 Tage)"
        T "key id" ((Get-NewsKey @{Link="https://a.at/x.php?id=1"}) -eq (Get-NewsKey @{Link="https://a.at/x.php?id=2"})) "False"
        T "key utm" (Get-NewsKey @{Link="https://Y.com/1?utm_source=a#x"}) "https://y.com/1"
        T "key utm old" (Get-NewsKey @{Link="https://y.com/1?utm=x"}) "https://y.com/1"
        $terms = Get-NewsMatchTerms -Symbols @("ABBN.SW","SAP.DE","NVDA") -Names @{"ABBN.SW"="ABB Ltd";"SAP.DE"="SAP SE";"NVDA"="NVIDIA Corporation"}
        T "abb" (@(Find-NewsSymbols "ABB wins order" $terms) -join ",") "ABBN.SW"
        T "abbey" (@(Find-NewsSymbols "Abbey road and sapphire" $terms) -join ",") ""
        T "sap+nv" (@(Find-NewsSymbols "SAP and Nvidia team up" $terms) -join ",") "NVDA,SAP.DE"
        $al = Get-NewsMatchTerms -Symbols @() -Aliases (ConvertTo-NewsAliases "RHM.DE = Rheinmetall, RHM`nbad line")
        T "alias" (@(Find-NewsSymbols "Rheinmetall liefert" $al) -join ",") "RHM.DE"
        T "short name" (Get-CompanyShortName "ABB Ltd") "ABB"
        $src = ConvertTo-NewsSourceList @([pscustomobject]@{Url="https://a.b/rss?q={name}";Ticker=""}, [pscustomobject]@{Url="ftp://x"}, [pscustomobject]@{Url="https://c.d/feed";On=$false;Minutes="2";Ticker="abbn.sw"})
        T "sources" @($src).Count 2
        T "minutes clamp" $src[1].Minutes 5
        $rq = @(Get-NewsFeedRequests -Sources $src -Symbols @("ABBN.SW","NVDA") -Names @{"ABBN.SW"="ABB Ltd"})
        T "template" (@($rq | % Url) -join " ") "https://a.b/rss?q=ABB https://a.b/rss?q=NVDA"
        T "legacy" @(Add-LegacyNewsFeeds -Sources @() -Text "https://a.b/1`r`nhttps://a.b/2").Count 2
        T "legacy one" @(Add-LegacyNewsFeeds -Sources @() -Text "https://a.b/1").Count 1
        T "due" @(Get-DueNewsSources -Sources $src -LastRun @{ $src[0].Id = (Get-Date) }).Count 0
        T "force" @(Get-DueNewsSources -Sources $src -LastRun @{ $src[0].Id = (Get-Date) } -Force).Count 1
        $rss = '<rss xmlns:media="http://search.yahoo.com/mrss/"><channel><title>W</title><item><title>A &amp; B</title><link>https://x.at/1</link><pubDate>Thu, 26 Nov 2026 09:00:00 GMT</pubDate><description>&lt;p&gt;Hallo &lt;b&gt;Welt&lt;/b&gt; &amp;amp; mehr&lt;/p&gt;</description><media:thumbnail url="https://x.at/a.jpg"/></item></channel></rss>'
        $e = @(ConvertFrom-RssFeed -Text $rss)
        T "summary" $e[0].Summary "Hallo Welt & mehr"
        T "image" $e[0].Image "https://x.at/a.jpg"
        $atom = '<feed xmlns="http://www.w3.org/2005/Atom"><title>F</title><entry><title>T</title><link href="https://x.y/1"/><updated>2026-11-26T10:00:00Z</updated><summary type="html">&lt;img src="https://x.y/p.png"&gt;Text</summary></entry></feed>'
        $a = @(ConvertFrom-RssFeed -Text $atom); T "atom sum" $a[0].Summary "Text"; T "atom img" $a[0].Image "https://x.y/p.png"
        $now = [DateTime]"2026-11-26 12:00"
        $items = @(ConvertTo-FeedItems -Entries $e -Source $src[0] -Ticker "ABBN.SW" -Now $now)
        T "fixed ticker" (@($items[0].Syms) -join ",") "ABBN.SW"
        T "src filter on" @(Select-NewsBySource -Items $items -Enabled @($src[0].Id)).Count 1
        T "src filter off" @(Select-NewsBySource -Items $items -Enabled @("yahoo")).Count 0
        T "src hidden" @(Select-NewsBySource -Items $items -Enabled @($src[0].Id) -Hidden @($src[0].Id)).Count 0
        T "include" @(Select-NewsByRules -Items $items -Include @("welt")).Count 1
        T "exclude" @(Select-NewsByRules -Items $items -Exclude @("welt")).Count 0
        T "search" @(Search-NewsItems -Items $items -Query "hallo abbn").Count 1
        T "search no" @(Search-NewsItems -Items $items -Query "hallo xyz").Count 0
        function N($k,$t,$p,$h) { [pscustomobject]@{Key=$k;Title=$t;Publisher=$p;Link="";Time=$now.AddHours(-$h);Syms=@("NVDA");Summary="";Image="";Sources=@($p);Also=@()} }
        $m = @(Merge-SimilarNews @((N 1 "Nvidia shares jump after record quarterly results" "A" 1), (N 2 "Nvidia shares jump after record quarterly results today" "B" 2), (N 3 "Apple unveils new phone in autumn event" "C" 3)))
        T "merge" $m.Count 2; T "also" (@($m[0].Also) -join ",") "B"; T "keys" @($m[0].Keys).Count 2
        $q = @(Merge-SimilarNews @((N 1 "Nvidia reports Q2 results above expectations" "A" 1), (N 2 "Nvidia reports Q3 results above expectations" "B" 2)))
        T "numbers differ" $q.Count 2
        $h = @(Update-NewsHistory -History @((N 1 "old" "A" 1), (N 9 "ancient" "A" 900)) -Fresh @((N 1 "new" "B" 1)) -Now $now)
        T "history" $h.Count 1; T "history src" (@($h[0].Sources) -join ",") "A,B"
        $rt = ConvertFrom-NewsRecord ((ConvertTo-Json -InputObject (ConvertTo-NewsRecord $h[0]) -Depth 5) | ConvertFrom-Json)
        T "roundtrip time" $rt.Time.ToString("s") $h[0].Time.ToString("s"); T "roundtrip src" @($rt.Sources).Count 2
        $read = New-Object System.Collections.Generic.HashSet[string]; [void]$read.Add("1")
        T "read mark" (Test-NewsUnread -Item $h[0] -Since $now.AddDays(-5) -ReadKeys $read) "False"
        T "unread mark" (Test-NewsUnread -Item $h[0] -Since $now -UnreadKeys $read) "True"
        T "csv formula" ((ConvertTo-NewsCsv @((N 1 "=cmd" "A" 1))) -match '"''=cmd"') "True"
        $bars = [long[]]@(0..3 | % { ([DateTimeOffset]$now.AddHours(-4 + $_)).ToUnixTimeMilliseconds() })
        $mk = @(Get-NewsChartMarks -Items @((N 1 "x" "A" 1.5), (N 2 "y" "A" 1.2), (N 3 "z" "A" 100)) -Symbol "nvda" -BarTsMs $bars -MaxGapMs 3600000)
        T "marks" ("{0}:{1}:{2}" -f $mk.Count, $mk[0].Index, $mk[0].Count) "1:2:2"
        T "discover" (@(Find-FeedLinks '<link rel="alternate" type="application/rss+xml" href="/feed.xml">' "https://s.at/news") -join "") "https://s.at/feed.xml"
        $o = ConvertFrom-Opml (ConvertTo-Opml $src)
        T "opml" @($o).Count 2
        T "opml dtd" @(ConvertFrom-Opml '<!DOCTYPE r [<!ENTITY e SYSTEM "file:///etc/passwd">]><opml><body><outline text="&e;" xmlUrl="https://a.b"/></body></opml>').Count 0
        $cfg = [pscustomobject]@{ NewsSources = $src; NewsFeeds = "https://a.b/?token=SECRET"; NewsAliases = "A=B" }
        T "diag no token" ((ConvertTo-Json (Get-DiagnosticConfig $cfg) -Depth 6) -match 'SECRET|a\.b/rss') "False"
        T "name key kept" (Get-NewsNameKey "NVIDIA Corporation") "nvidia"
        ($script:fail -join "`n") | Should -BeNullOrEmpty
    }
}

Describe "V8.0 logic" {
    It "keeps three watchlist groups apart and repairs nested lists" {
        $cfg = [PSCustomObject]@{ WatchGroups = @() }
        foreach ($p in @(@("Tech", "AAA"), @("ETF", "BBB"), @("Div", "CCC"))) {
            # the form the app uses: no @() around the call
            $cfg.WatchGroups = Set-WatchGroupMember -Groups @($cfg.WatchGroups) -Group $p[0] -Symbol $p[1] -In $true
        }
        @($cfg.WatchGroups | ForEach-Object { $_.Name }) -join "," | Should -Be "Tech,ETF,Div"
        $old = '{"WatchGroups":[[{"Name":"Tech","Symbols":["aaa"]},{"Name":"ETF","Symbols":["BBB"]}]]}' | ConvertFrom-Json
        $flat = ConvertTo-FlatWatchGroups $old.WatchGroups
        @($flat | ForEach-Object { $_.Name }) -join "," | Should -Be "Tech,ETF"
        $flat[0].Symbols -join "," | Should -Be "AAA"
        (ConvertTo-FlatWatchGroups @()).Count | Should -Be 0
    }
    It "scales and moves the price axis" {
        $r = Get-ScaledPriceRange -MinP 100 -SpanP 100
        $r.Min | Should -Be 100; $r.Span | Should -Be 100
        $r = Get-ScaledPriceRange -MinP 100 -SpanP 100 -Scale 2
        $r.Min | Should -Be 50; $r.Span | Should -Be 200
        $r = Get-ScaledPriceRange -MinP 100 -SpanP 100 -Shift 0.5
        $r.Min | Should -Be 150
        $l = Get-ScaledPriceRange -MinP 100 -SpanP 300 -Log $true -Scale 2
        $l.Min | Should -BeGreaterThan 0
        (Get-ScaledPriceRange -MinP 100 -SpanP 100 -Scale 99).Span | Should -Be 800
    }
    It "picks the first matching colour rule that is on" {
        $rules = @(Get-DefaultColorRules)
        Get-MatchingColorRule -Rules $rules -Facts @{ DayAbsPct = 9 } | Should -BeNullOrEmpty
        foreach ($r in $rules) { $r.On = $true }
        (Get-MatchingColorRule -Rules $rules -Facts @{ DayAbsPct = 3; Rsi = 80 }).Id | Should -Be "bigmove"
        (Get-MatchingColorRule -Rules $rules -Facts @{ DayAbsPct = 1; Rsi = 25 }).Id | Should -Be "rsilow"
        (Get-MatchingColorRule -Rules $rules -Facts @{ TotalPct = -12 }).Id | Should -Be "loss"
        Get-MatchingColorRule -Rules $rules -Facts @{ Rsi = [double]::NaN } | Should -BeNullOrEmpty
        [math]::Round((Get-NearestDistancePct -Price 100 -Levels @(0, 90, 103)), 4) | Should -Be 3
        [double]::IsNaN((Get-NearestDistancePct -Price 100 -Levels @())) | Should -BeTrue
    }
    It "reads own themes and drops broken parts" {
        $t = ConvertFrom-ThemeData ('{"Name":"Mein","Base":"Nope","Colors":{"Card":"#112233","Text":"rot","Other":"#000000"}}' | ConvertFrom-Json)
        $t.Base | Should -Be "Dark"
        $t.Colors.Card | Should -Be "#112233"
        @($t.Colors.PSObject.Properties).Count | Should -Be 1
        ConvertFrom-ThemeData ('{"Name":"Dark"}' | ConvertFrom-Json) | Should -BeNullOrEmpty
        ConvertFrom-ThemeData ('{"Name":""}' | ConvertFrom-Json) | Should -BeNullOrEmpty
    }
    It "normalises shortcuts and refuses reserved ones" {
        ConvertTo-ShortcutText "ctrl + shift+p" | Should -Be "Strg+Shift+P"
        ConvertTo-ShortcutText "j" | Should -Be "J"
        foreach ($bad in @("Strg+C", "Strg+K", "Alt+F4", "3", "Strg+", "Win+X", "Enter", "")) { ConvertTo-ShortcutText $bad | Should -Be "" }
        Get-KeyShortcutText -KeyName "D7" -Ctrl $true -Alt $false -Shift $false | Should -Be "Strg+7"
        Get-KeyShortcutText -KeyName "Left" -Ctrl $false -Alt $false -Shift $false | Should -Be ""
    }
    It "orders chosen ids" {
        @(Select-OrderedIds -Available @("a", "b", "c") -Chosen @("c", "x", "a", "c")) -join "," | Should -Be "c,a"
        @(Select-OrderedIds -Available @("a", "b") -Chosen @()) -join "," | Should -Be "a,b"
        @(Select-OrderedIds -Available @("a", "b") -Chosen @() -EmptyIsNone).Count | Should -Be 0
    }
    It "combines two alert conditions" {
        Test-AlertCombination ">=" "Volumen x" | Should -Be ""
        Test-AlertCombination "Depot >=" "Depot Tag% >=" | Should -Be ""
        Test-AlertCombination ">=" "Depot >=" | Should -Not -Be ""
        Test-AlertCombination ">=" "Trailing %" | Should -Not -Be ""
        Test-AlertCombination "RSI >=" "RSI >=" | Should -Not -Be ""
        $a = @{ Ok = $true; Value = 1.0; Met = $true; Text = "A"; Peak = 5.0 }
        $b = @{ Ok = $true; Value = 2.0; Met = $false; Text = "B"; Peak = [double]::NaN }
        (Join-AlertEvaluations $a $b).Met | Should -BeFalse
        $b.Met = $true
        $j = Join-AlertEvaluations $a $b
        $j.Met | Should -BeTrue; $j.Peak | Should -Be 5; $j.Text | Should -Be "A  UND  B"
        (Join-AlertEvaluations $a @{ Ok = $false; Value = 0; Met = $true; Text = ""; Peak = 0 }).Met | Should -BeFalse
    }
    It "applies templates without doubles" {
        $al = @([PSCustomObject]@{ Ticker = "AAA"; Condition = "RSI >="; TargetPrice = 70.0 })
        @(Get-TemplateTargets -Symbols @("aaa", "bbb", "BBB") -Alerts $al -Condition "RSI >=" -Value 70) -join "," | Should -Be "BBB"
        @(Get-TemplateTargets -Symbols @("AAA", "BBB") -Alerts $al -Condition "EK% <=" -Value -10 -Held @("BBB")) -join "," | Should -Be "BBB"
        @(Get-TemplateTargets -Symbols @("AAA") -Alerts $al -Condition "RSI >=" -Value 70 -Condition2 "Volumen x" -Value2 2).Count | Should -Be 1
        Test-AlertValue "RSI >=" 120 | Should -Not -Be ""
        Test-AlertValue "RSI >=" 70 | Should -Be ""
    }
    It "finds due notices with lead times" {
        $ev = @{ AAA = [PSCustomObject]@{ EarningsDate = "2026-03-10"; ExDividendDate = "2026-03-12"; NotifiedEarnings = "" } }
        @(Get-DueDateNotices -Events $ev -Symbols @("AAA") -AsOf "2026-03-08").Count | Should -Be 0
        @(Get-DueDateNotices -Events $ev -Symbols @("AAA") -AsOf "2026-03-09").Count | Should -Be 1
        @(Get-DueDateNotices -Events $ev -Symbols @("AAA") -AsOf "2026-03-07" -EarningsLead 3 -ExDivLead 5).Count | Should -Be 2
        @(Get-DueDateNotices -Events $ev -Symbols @("AAA") -AsOf "2026-03-11" -EarningsLead 3).Count | Should -Be 0
        $ev.AAA.NotifiedEarnings = "2026-03-10"
        @(Get-DueDateNotices -Events $ev -Symbols @("AAA") -AsOf "2026-03-10").Count | Should -Be 0
    }
    It "writes a calendar file" {
        $t = ConvertTo-IcsText -Events @([PSCustomObject]@{ Date = "2026-12-31"; Ticker = "AAA"; Kind = "Quartalszahlen, Q4; neu" }) -Now ([DateTime]::new(2026, 1, 2, 3, 4, 5, [DateTimeKind]::Utc))
        $t | Should -Match "DTSTART;VALUE=DATE:20261231"
        $t | Should -Match "DTEND;VALUE=DATE:20270101"
        $t | Should -Match "SUMMARY:AAA: Quartalszahlen\\, Q4\\; neu"
        $long = ConvertTo-IcsText -Events @([PSCustomObject]@{ Date = "2026-01-01"; Ticker = "AAA"; Kind = ("ü" * 90) })
        foreach ($l in ($long -split "`r`n")) { [System.Text.Encoding]::UTF8.GetByteCount($l) | Should -BeLessOrEqual 75 }
    }
    It "finds the reference close, movers and the summary day" {
        $d = @("2026-03-01", "2026-03-02", "2026-03-06", "2026-03-09"); $c = [double[]]@(10, 11, 12, 13)
        Get-ReferenceClose -Dates $d -Closes $c -DaysBack 7 -AsOf "2026-03-09" | Should -Be 11
        [double]::IsNaN((Get-ReferenceClose -Dates $d -Closes $c -DaysBack 30 -AsOf "2026-03-09")) | Should -BeTrue
        $m = Select-SummaryMovers -Items @(@{ Ticker = "A"; Pct = 1 }, @{ Ticker = "B"; Pct = -5 }, @{ Ticker = "C"; Pct = 4 }) -Top 1
        $m.Up[0].Ticker | Should -Be "C"; $m.Down[0].Ticker | Should -Be "B"
        $now = [DateTime]::new(2026, 3, 11, 9, 0, 0)   # Wednesday
        Test-SummaryDue -Mode "Daily" -LastShown "2026-03-11" -Now $now | Should -BeFalse
        Test-SummaryDue -Mode "Daily" -LastShown "2026-03-10" -Now $now | Should -BeTrue
        Test-SummaryDue -Mode "Weekly" -LastShown "2026-03-09" -Now $now | Should -BeFalse
        Test-SummaryDue -Mode "Weekly" -LastShown "2026-03-08" -Now $now | Should -BeTrue
        Test-SummaryDue -Mode "Off" -LastShown "" -Now $now | Should -BeFalse
    }
    It "sums fees and interest per year" {
        $tx = @([PSCustomObject]@{ Date = "2025-05-01"; Type = "Kauf"; Fee = 2.0; Currency = "EUR" }, [PSCustomObject]@{ Date = "2026-01-05"; Type = "Verkauf"; Fee = 3.0; Currency = "USD" })
        $cash = @([PSCustomObject]@{ Date = "2026-02-01"; Kind = "Gebühr"; Amount = -5.0; Currency = "EUR" }, [PSCustomObject]@{ Date = "2026-02-02"; Kind = "Zinsen"; Amount = 7.5; Currency = "EUR" }, [PSCustomObject]@{ Date = "2026-02-03"; Kind = "Einzahlung"; Amount = 100; Currency = "EUR" })
        $r = @(Get-FeeOverview -Transactions $tx -CashEntries $cash -Base "EUR" -FallbackFromEur @{ EUR = 1.0; USD = 1.5 })
        $r[0].Year | Should -Be "2026"; $r[0].OrderFees | Should -Be 2; $r[0].Approx | Should -BeTrue
        $r[0].AccountFees | Should -Be 5; $r[0].Interest | Should -Be 7.5
        $r[1].OrderFees | Should -Be 2; $r[1].Approx | Should -BeFalse; $r[1].Orders | Should -Be 1
    }
    It "measures goal progress" {
        (Get-GoalProgress -Current 50 -Target 200).Pct | Should -Be 25
        $g = Get-GoalProgress -Current 300 -Target 200
        $g.BarPct | Should -Be 100; $g.Reached | Should -BeTrue; $g.Remaining | Should -Be 0
        Get-GoalProgress -Current 1 -Target 0 | Should -BeNullOrEmpty
    }
    It "computes Sortino and historic VaR" {
        # downside: one period of -2 % out of 4 -> sqrt(0.0004 / 4) = 0.01 -> 1 % per period
        [math]::Round((Get-SortinoRatio -Returns ([double[]]@(0.01, -0.02, 0.03, 0.0)) -AnnReturn 10 -PeriodsPerYear 4), 6) | Should -Be 5
        [double]::IsNaN((Get-SortinoRatio -Returns ([double[]]@(0.01, 0.02)) -AnnReturn 10)) | Should -BeTrue
        # -10 % ... +10 % in 21 steps: the 5 % quantile is the second value (-9 %)
        $r = [double[]]@(-10..10 | ForEach-Object { $_ / 100.0 })
        [math]::Round((Get-HistoricVaR -Returns $r -Level 95), 6) | Should -Be 9
        Get-HistoricVaR -Returns ([double[]]@(1..25 | ForEach-Object { 0.01 })) | Should -Be 0
        [double]::IsNaN((Get-HistoricVaR -Returns ([double[]]@(0.1, 0.2)))) | Should -BeTrue
    }
    It "writes and reads the watchlist CSV" {
        $rows = @([PSCustomObject]@{ Ticker = "^GSPC"; Groups = @("Index", "US"); Target = 1234.5; Currency = "USD"; Note = "=cmd; `"x`"`r`nzwei" },
                  [PSCustomObject]@{ Ticker = "ABBN.SW"; Groups = @(); Target = 0; Currency = ""; Note = "" })
        $csv = ConvertTo-WatchlistCsv $rows
        $csv | Should -Match "'=cmd"
        $r = ConvertFrom-WatchlistCsv $csv
        $r.Skipped | Should -Be 0
        @($r.Rows).Count | Should -Be 2
        $r.Rows[0].Ticker | Should -Be "^GSPC"; $r.Rows[0].Target | Should -Be 1234.5
        $r.Rows[0].Groups -join "," | Should -Be "Index,US"
        $r.Rows[0].Note | Should -Be "=cmd; `"x`" zwei"
        $one = ConvertFrom-WatchlistCsv "Ticker`r`nnvda`r`nbad symbol`r`nNVDA"
        @($one.Rows).Count | Should -Be 1; $one.Skipped | Should -Be 2
        @((ConvertFrom-WatchlistCsv "a;b`r`n1;2").Rows).Count | Should -Be 0
    }
}

# ==============================================================================
# v9.0
# ==============================================================================
Describe "Layout helpers (v9.0)" {
    It "keeps a tag in place when nothing is in the way" {
        Get-FreeTagX -X 500 -Y 10 -Width 80 -Height 15 -Used @() | Should -Be 500
    }
    It "moves a tag left of the one it would cover" {
        Get-FreeTagX -X 500 -Y 12 -Width 80 -Height 15 -Used @(@{ X = 490; Y = 10; W = 90; H = 15 }) -Gap 4 | Should -Be 406
    }
    It "never moves a tag past the left limit" {
        Get-FreeTagX -X 50 -Y 10 -Width 80 -Height 15 -Used @(@{ X = 40; Y = 10; W = 100; H = 15 }) -MinX 4 | Should -Be 50
    }
    It "does not stretch buttons when there is room" {
        (Get-FittedWidths -Natural @(40, 60) -Available 500) -join "," | Should -Be "56,76"
    }
    It "shrinks buttons so the row fits" {
        $w = @(Get-FittedWidths -Natural @(100, 100, 100) -Available 200 -Gap 4)
        (($w | Measure-Object -Sum).Sum + 8) | Should -BeLessOrEqual 200
    }
}

Describe "Overview logic (v10.0)" {
    It "sorts slices and sums to 100 percent" {
        $r = @(Get-AllocationSlices -Items @(@{ Name = "A"; Value = 25 }, @{ Name = "B"; Value = 75 }, @{ Name = "C"; Value = 0 }))
        $r.Count | Should -Be 2
        $r[0].Name | Should -Be "B"
        $r[0].Pct | Should -Be 75
    }
    It "collects small positions in one slice" {
        $items = 1..9 | ForEach-Object { @{ Name = "T$_"; Value = $_ } }
        $r = @(Get-AllocationSlices -Items $items -MaxSlices 4 -OtherName "Rest")
        $r.Count | Should -Be 4
        $r[3].Name | Should -Be "Rest"
        $r[3].Value | Should -Be 21
    }
    It "returns nothing without positions" {
        @(Get-AllocationSlices -Items @()).Count | Should -Be 0
        @(Get-CombinedTrend -Series @()).Count | Should -Be 0
    }
    It "ends at today's total, whatever the price unit is" {
        $r = @(Get-CombinedTrend -Series @(@{ EndValue = 100.0; Values = @(500.0, 1000.0) }, @{ EndValue = 50.0; Values = @(5.0, 5.0, 5.0) }) -Points 3)
        $r[0] | Should -Be 100
        $r[1] | Should -Be 125
        $r[2] | Should -Be 150
    }
}

Describe "Broker per booking (v10.4)" {
    BeforeAll {
        function New-TestBooking($id, $date, $ticker, $type, $shares, $price, $fee, $broker, $note = "") {
            [PSCustomObject]@{ Id = $id; Date = $date; Ticker = $ticker; Type = $type; Shares = $shares; Price = $price; Fee = $fee; Currency = "EUR"; Broker = $broker; Note = $note }
        }
    }
    BeforeEach {
        $script:b = @(
            (New-TestBooking "1" "2026-01-10" "NVDA" "Kauf" 10 100 1 "Flatex"),
            (New-TestBooking "2" "2026-03-05" "MSFT" "Kauf" 2 300 6 "Hausbank" "Sparplan"),
            (New-TestBooking "3" "2026-02-01" "NVDA" "Verkauf" 5 120 1 "flatex"),
            (New-TestBooking "4" "2025-07-01" "SAP.DE" "Kauf" 1 200 2 ""),
            (New-TestBooking "5" "2026-04-01" "NVDA" "Dividende" 0 50 13 "Flatex"))
    }
    It "lists every broker once" {
        @(Get-BrokerNames $b).Count | Should -Be 2
    }
    It "takes the broker of the newest booking of the ticker" {
        Get-LastBroker -Transactions $b -Ticker "MSFT" | Should -Be "Hausbank"
        Get-LastBroker -Transactions $b -Ticker "SAP.DE" | Should -Be "Flatex"
        Get-LastBroker -Transactions @() -Ticker "SAP.DE" | Should -Be ""
    }
    It "searches all words in ticker, note, broker and German date" {
        Test-BookingMatch -Booking $b[1] -Search "msft sparplan" | Should -BeTrue
        Test-BookingMatch -Booking $b[1] -Search "05.03.2026" | Should -BeTrue
        Test-BookingMatch -Booking $b[1] -Search "msft flatex" | Should -BeFalse
        Test-BookingMatch -Booking $b[1] -Search "  " | Should -BeTrue
    }
    It "assigns a broker only to the chosen bookings" {
        Set-BookingBroker -Transactions $b -Ids @("4", "2") -Broker " Hausbank " | Should -Be 1
        $b[3].Broker | Should -Be "Hausbank"
        $b[0].Broker | Should -Be "Flatex"
    }
    It "adds up orders, volume and fees per year and broker without dividends" {
        $r = @(Get-BrokerFeeOverview -Transactions $b -Base "EUR")
        $r.Count | Should -Be 3
        $f = @($r | Where-Object { $_.Year -eq "2026" -and $_.Broker -eq "Flatex" })[0]
        $f.Orders | Should -Be 2
        $f.Volume | Should -Be 1600
        $f.Fees | Should -Be 2
        $f.PerOrder | Should -Be 1
        $f.Pct | Should -Be 0.125
        $r[2].Year | Should -Be "2025"
    }
    It "reads a broker column from a CSV file" {
        $csv = ConvertFrom-CsvText "Datum;Typ;Ticker;Stück;Kurs;Broker`n01.02.2026;Kauf;SAP.DE;2;100;Flatex"
        $map = Get-CsvColumnGuess -Headers $csv.Headers
        @(ConvertFrom-BrokerRows -Rows $csv.Rows -Map $map)[0].Broker | Should -Be "Flatex"
    }
}

Describe "Goals per depot (v10.6)" {
    It "keeps one goal per depot and leaves the others alone" {
        $g = Set-DepotGoal -Goals @() -Id "" -Value 1000 -Dividend 50
        $g = Set-DepotGoal -Goals $g -Id "zweit" -Value 200
        $g = Set-DepotGoal -Goals $g -Id "" -Value 3000
        @($g).Count | Should -Be 2
        (Get-DepotGoal -Goals $g -Id "").Value | Should -Be 3000
        (Get-DepotGoal -Goals $g -Id "").Dividend | Should -Be 0
        (Get-DepotGoal -Goals $g -Id "zweit").Value | Should -Be 200
        (Get-DepotGoal -Goals $g -Id "fehlt").Value | Should -Be 0
    }
    It "drops the entry when both goals are empty" {
        $g = Set-DepotGoal -Goals (Set-DepotGoal -Goals @() -Id "a" -Value 5) -Id "a"
        @($g).Count | Should -Be 0
    }
    It "survives a round trip through JSON with a single entry" {
        $json = ConvertTo-Json -InputObject @{ DepotGoals = (Set-DepotGoal -Goals @() -Id "a" -Dividend 7) } -Depth 5
        $back = $json | ConvertFrom-Json
        (Get-DepotGoal -Goals $back.DepotGoals -Id "a").Dividend | Should -Be 7
    }
    It "exports the new goal settings" {
        $keys = Get-PortableSettingKeys
        foreach ($k in @("DepotGoals", "GoalAllValue", "GoalAllDividend")) { $keys | Should -Contain $k }
    }
}

Describe "Alert overview and editing (v10.8)" {
    BeforeAll {
        function New-TestAlert($cond, $target) {
            [PSCustomObject]@{ Id = "x"; Ticker = "NVDA"; Condition = $cond; TargetPrice = [double]$target; Currency = "USD"; Triggered = $true; TriggeredAt = "2026-01-01T10:00:00"; Note = ""; RearmMin = 0; ExpiresAt = ""; Peak = 0.0; Push = $true }
        }
    }
    It "gives the price move that is still needed" {
        $d = Get-AlertDistance -Condition ">=" -Target 110 -Value 100
        $d.Ok | Should -BeTrue
        [math]::Round($d.Gap, 4) | Should -Be 10
        (Get-AlertDistance -Condition "<=" -Target 90 -Value 100).Gap | Should -Be -10
    }
    It "turns gain on cost into a price move" {
        [math]::Round((Get-AlertDistance -Condition "EK% >=" -Target 20 -Value 0).Gap, 4) | Should -Be 20
        [math]::Round((Get-AlertDistance -Condition "EK% >=" -Target 20 -Value 10).Gap, 4) | Should -Be 9.0909
    }
    It "handles trailing stop and the 52 week levels" {
        (Get-AlertDistance -Condition "Trailing %" -Target 8 -Value -3).Gap | Should -Be -5
        (Get-AlertDistance -Condition "52W Hoch" -Target 0 -Value -4).Gap | Should -Be 4
        (Get-AlertDistance -Condition "52W Tief" -Target 2 -Value 12).Gap | Should -Be -10
    }
    It "scores a met alert as zero and unknown values as furthest" {
        (Get-AlertDistance -Condition ">=" -Target 1 -Value 2 -Met $true).Score | Should -Be 0
        (Get-AlertDistance -Condition ">=" -Target 1 -Value ([double]::NaN)).Ok | Should -BeFalse
    }
    It "arms the alert again only when the target changes" {
        $a = New-TestAlert ">=" 100
        Update-AlertSettings -Alert $a -Value 100 -Note "n" -RearmMin 60 | Should -Be ""
        $a.Triggered | Should -BeTrue
        $a.RearmMin | Should -Be 60
        Update-AlertSettings -Alert $a -Value 120 | Should -Be ""
        $a.Triggered | Should -BeFalse
        $a.TargetPrice | Should -Be 120
    }
    It "changes nothing when a value does not fit" {
        $a = New-TestAlert "RSI >=" 70
        Update-AlertSettings -Alert $a -Value 150 -Note "neu" | Should -Not -Be ""
        $a.TargetPrice | Should -Be 70
        $a.Note | Should -Be ""
    }
    It "names the state of an alert" {
        $a = New-TestAlert ">=" 1
        Get-AlertStatusName -Alert $a | Should -Be "Hit"
        $a.Triggered = $false
        Get-AlertStatusName -Alert $a | Should -Be "Active"
        $a.ExpiresAt = "2020-01-01"
        Get-AlertStatusName -Alert $a | Should -Be "Expired"
    }
}

Describe "Analysis tiles (v11.0)" {
    It "delivers every extra tile, with a dash where a figure is missing" {
        $t = @(Get-AnalysisExtraTiles -Base "EUR")
        $t.Count | Should -Be 10
        @($t | Where-Object { $_.Text -eq "-" }).Count | Should -Be 10
    }
    It "picks the best and the weakest position" {
        $pos = @([PSCustomObject]@{ Ticker = "A"; Pct = 5.0 }, [PSCustomObject]@{ Ticker = "B"; Pct = -12.5 }, [PSCustomObject]@{ Ticker = "C"; Pct = [double]::NaN }, [PSCustomObject]@{ Ticker = "D"; Pct = 40.0 })
        $t = @(Get-AnalysisExtraTiles -Positions $pos)
        $best = @($t | Where-Object { $_.Id -eq "Best" })[0]
        $worst = @($t | Where-Object { $_.Id -eq "Worst" })[0]
        $best.Text | Should -BeLike "D*"
        $best.Kind | Should -Be "up"
        $worst.Text | Should -BeLike "B*"
        $worst.Kind | Should -Be "down"
    }
    It "marks a drawdown red and leaves volatility neutral" {
        $t = @(Get-AnalysisExtraTiles -MaxDrawdown -18 -Vol 22)
        @($t | Where-Object { $_.Id -eq "Drawdown" })[0].Kind | Should -Be "down"
        @($t | Where-Object { $_.Id -eq "Vola" })[0].Kind | Should -Be "flat"
    }
    It "counts the dividends of this year only" {
        Get-DividendsSince -Dates @("2025-06-01", "2025-12-31", "2026-03-01", "2026-09-01") -Cumulative @(10, 25, 40, 70) -From "2026-01-01" | Should -Be 45
        Get-DividendsSince -Dates @("2026-03-01") -Cumulative @(7) -From "2026-01-01" | Should -Be 7
    }
    It "uses one row up to six tiles and then more rows" {
        (Get-TileGrid -Count 6 -Width 976 -RowHeight 56 -Gap 8).Rows | Should -Be 1
        $g = Get-TileGrid -Count 10 -Width 976 -RowHeight 56 -Gap 8
        $g.Rows | Should -Be 2
        $g.Height | Should -Be 120
        @($g.Rects)[5].Y | Should -Be 64
        @($g.Rects)[5].X | Should -Be 0
        (@($g.Rects)[4].X + @($g.Rects)[4].W) | Should -BeLessOrEqual 976
        (Get-TileGrid -Count 15 -Width 976 -RowHeight 56 -Gap 8).Rows | Should -Be 3
    }
}

Describe "Privacy in the analysis (v11.0)" {
    It "hides money tiles and keeps percentages" {
        $dots = [string]([char]0x2022) * 4
        $t = @(Get-AnalysisKpiTiles -Value 10000 -Invested 8000 -Dividends 200 -Xirr 0.1) + @(Get-AnalysisExtraTiles -Unreal 500 -Fees 12 -Vol 20)
        $p = @(Protect-KpiTiles $t $true)
        $p.Count | Should -Be $t.Count
        foreach ($id in @("Value", "Result", "Div", "Unreal", "Fees")) { @($p | Where-Object { $_.Id -eq $id })[0].Text | Should -Be $dots }
        @($p | Where-Object { $_.Id -eq "Value" })[0].Sub | Should -Not -Match "\d"
        @($p | Where-Object { $_.Id -eq "Result" })[0].Sub | Should -Match "%"
        @($p | Where-Object { $_.Id -eq "Vola" })[0].Text | Should -Match "20"
        @(Protect-KpiTiles $t $false)[0].Text | Should -Match "EUR"
    }
    It "masks the result columns of the return table" {
        foreach ($h in @("Unrealisiert", "Realisiert", "Gesamt", "Unrealized")) { Test-AmountColumn $h | Should -BeTrue }
        foreach ($h in @("Gesamt %", "XIRR p.a.", "Seit")) { Test-AmountColumn $h | Should -BeFalse }
    }
}

Describe "Chart bar of a booking (v11.2)" {
    BeforeAll { $script:days = @("2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-09", "2026-11-10") }
    It "uses the same day, or the next trading day after a weekend" {
        Get-TradeBarIndex -BarDates $days -Date "2026-11-03" | Should -Be 1
        Get-TradeBarIndex -BarDates $days -Date "2026-11-07" | Should -Be 5
    }
    It "keeps a booking just after the last bar and drops ones outside the range" {
        Get-TradeBarIndex -BarDates $days -Date "2026-11-11" | Should -Be 6
        Get-TradeBarIndex -BarDates $days -Date "2026-11-20" | Should -Be -1
        Get-TradeBarIndex -BarDates $days -Date "2026-11-01" | Should -Be -1
        Get-TradeBarIndex -BarDates $days -Date "kein Datum" | Should -Be -1
    }
    It "takes the containing week on weekly bars" {
        $w = @("2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26")
        Get-TradeBarIndex -BarDates $w -Date "2026-10-15" | Should -Be 1
        Get-TradeBarIndex -BarDates $w -Date "2026-10-28" | Should -Be 3
        Get-TradeBarIndex -BarDates $w -Date "2026-11-30" | Should -Be -1
    }
}

Describe "English run-time texts (v11.2)" {
    It "translates <de>" -ForEach @(
        @{ de = "Stand 03:12:05 (vor 44 s)"; en = "As of 03:12:05 (44 s ago)" }
        @{ de = "Märkte zu - Abfrage alle 10 min"; en = "Markets closed - polling every 10 min" }
        @{ de = "12 Abfragen/min"; en = "12 requests/min" }
        @{ de = "Teilweise veraltete Daten (2 Fehler)"; en = "Some data is out of date (2 errors)" }
        @{ de = "Feiertag"; en = "Holiday" }
        @{ de = "Zu"; en = "Closed" }
        @{ de = "Zeitraum: gesamt"; en = "Period: all" }
        @{ de = "Im Zeitraum (6 Monate)"; en = "In period (6 months)" }
        @{ de = "Dividenden 2026"; en = "Dividends 2026" }
        @{ de = "+56.0 % auf Einsatz"; en = "+56.0 % on invested" }
        @{ de = "+17.2 Pkt."; en = "+17.2 pts" }
    ) { ConvertTo-EnglishStatus $de | Should -BeExactly $en }
    It "leaves other text alone" {
        ConvertTo-EnglishStatus "NVDA 149.30 USD" | Should -BeExactly "NVDA 149.30 USD"
        ConvertTo-EnglishStatus "" | Should -BeExactly ""
    }
}

Describe "One position in detail (v11.4)" {
    BeforeAll {
        $mk = { param($tk, $type, $date, $sh, $px, $fee, $br) [PSCustomObject]@{ Ticker = $tk; Type = $type; Date = $date; Shares = $sh; Price = $px; Fee = $fee; Currency = "EUR"; Broker = $br } }
        $script:ptx = @(
            (& $mk "ABC" "Kauf" "2025-01-10" 10 100 5 "Flatex"), (& $mk "ABC" "Kauf" "2025-06-10" 10 120 5 "Scalable"),
            (& $mk "ABC" "Verkauf" "2026-02-10" 5 150 5 "Flatex"), (& $mk "ABC" "Dividende" "2026-03-10" 0 30 8 "Flatex"),
            (& $mk "XYZ" "Kauf" "2025-01-10" 1 1 0 ""))
        $script:det = Get-PositionDetail -Transactions $ptx -Ticker "abc" -PriceNow 130 -Today "2026-11-27"
    }
    It "adds up cost, result and income of this ticker only" {
        $det.Shares | Should -Be 15
        $det.Cost | Should -Be 1657.5
        $det.AvgCost | Should -Be 110.5
        $det.Value | Should -Be 1950
        $det.Unreal | Should -Be 292.5
        $det.Real | Should -Be 192.5
        $det.Div | Should -Be 22
        $det.Div12 | Should -Be 22
        $det.Total | Should -Be 507
        $det.Fees | Should -Be 15
        $det.Orders | Should -Be 3
        $det.HoldDays | Should -Be 686
        $det.Xirr | Should -BeGreaterThan 0.1
    }
    It "splits the figures per year and per broker" {
        @($det.Years).Count | Should -Be 2
        @($det.Years)[0].Year | Should -Be "2026"
        @($det.Years)[0].Sold | Should -Be 745
        @($det.Years)[1].Bought | Should -Be 2210
        @($det.Years)[1].Fees | Should -Be 10
        $f = @($det.Brokers | Where-Object { $_.Broker -eq "Flatex" })[0]
        $f.Shares | Should -Be 5
        $f.Orders | Should -Be 2
        $f.Fees | Should -Be 10
    }
    It "lists the newest booking first" { @($det.Bookings)[0].Date | Should -Be "2026-03-10" }
    It "copes with a position without bookings" {
        $e = Get-PositionDetail -Transactions $ptx -Ticker "NONE" -PriceNow 10 -PortfolioShares 3
        $e.HasBookings | Should -BeFalse
        $e.Value | Should -Be 30
        [double]::IsNaN($e.Total) | Should -BeTrue
    }
    It "builds ten tiles and hides amounts in privacy mode" {
        @(Get-PositionTiles -Detail $det -Share 40).Count | Should -Be 10
        $p = @(Get-PositionTiles -Detail $det -Share 40 -Privacy $true)
        foreach ($id in @("Value", "Cost", "Unreal", "Total", "Real", "Div", "Fees")) {
            $t = @($p | Where-Object { $_.Id -eq $id })[0]
            $t.Text | Should -Not -Match "\d"
        }
        @($p | Where-Object { $_.Id -eq "Value" })[0].Sub | Should -Not -Match "\d"
        @($p | Where-Object { $_.Id -eq "Share" })[0].Text | Should -Be "40.0 %"
    }
}

Describe "Savings calculator (v11.6)" {
    It "adds the monthly amount without any return" {
        $s = @(Get-Projection -Start 1000 -Monthly 100 -ReturnPct 0 -Months 24)
        $s.Count | Should -Be 25
        $s[-1].Value | Should -Be 3400
        $s[-1].PaidIn | Should -Be 3400
    }
    It "compounds the yearly return over twelve months" {
        $s = @(Get-Projection -Start 1000 -Monthly 0 -ReturnPct 10 -Months 12)
        [math]::Round($s[-1].Value, 6) | Should -Be 1100
        $s[-1].PaidIn | Should -Be 1000
    }
    It "raises the monthly amount after each full year" {
        $s = @(Get-Projection -Start 0 -Monthly 100 -ReturnPct 0 -Months 25 -IncreasePct 10)
        [math]::Round($s[12].Value, 2) | Should -Be 1200
        [math]::Round($s[13].Value - $s[12].Value, 2) | Should -Be 110
        [math]::Round($s[25].Value - $s[24].Value, 2) | Should -Be 121
    }
    It "shows purchasing power with inflation" {
        $s = @(Get-Projection -Start 1000 -Monthly 0 -ReturnPct 2 -Months 12 -InflationPct 2)
        [math]::Round($s[-1].Real, 6) | Should -Be 1000
    }
    It "finds when a goal is reached" {
        $s = @(Get-Projection -Start 0 -Monthly 100 -ReturnPct 0 -Months 120)
        Get-MonthsToGoal -Series $s -Goal 1200 | Should -Be 12
        Get-MonthsToGoal -Series $s -Goal 999999 | Should -Be -1
        Get-MonthsToGoal -Series $s -Goal 0 | Should -Be -1
    }
    It "works out the monthly amount needed for a goal" {
        Get-RequiredMonthly -Start 0 -Goal 12000 -ReturnPct 0 -Months 120 | Should -Be 100
        Get-RequiredMonthly -Start 5000 -Goal 4000 -ReturnPct 0 -Months 12 | Should -Be 0
        $m = Get-RequiredMonthly -Start 10000 -Goal 100000 -ReturnPct 6 -Months 180 -IncreasePct 2
        [math]::Round(@(Get-Projection -Start 10000 -Monthly $m -ReturnPct 6 -Months 180 -IncreasePct 2)[-1].Value, 2) | Should -Be 100000
    }
    It "gives one row per year" {
        $s = @(Get-Projection -Start 100 -Monthly 10 -ReturnPct 3 -Months 36)
        $r = @(Get-ProjectionRows -Low $s -Mid $s -High $s -StartYear 2026)
        $r.Count | Should -Be 3
        $r[2].Year | Should -Be 2029
    }
    It "sums only active savings plans per currency" {
        $plans = @(
            [PSCustomObject]@{ Amount = 100; Currency = "EUR"; Active = $true; Start = "2026-01-01"; Increase = 0 },
            [PSCustomObject]@{ Amount = 50; Currency = "EUR"; Active = $true; Start = "2026-01-01"; Increase = 0 },
            [PSCustomObject]@{ Amount = 70; Currency = "USD"; Active = $false; Start = "2026-01-01"; Increase = 0 })
        $a = Get-ActivePlanAmounts -Plans $plans -Today "2026-11-27"
        $a["EUR"] | Should -Be 150
        $a.ContainsKey("USD") | Should -BeFalse
    }
}

Describe "Monthly returns (v11.8)" {
    BeforeAll {
        $script:d = [string[]]@("2025-12-30", "2025-12-31", "2026-01-02", "2026-01-30", "2026-02-02")
        $script:v = [double[]]@(100, 110, 121, 221, 198.9)
        $script:i = [double[]]@(100, 100, 100, 200, 200)
        $script:m = @(Get-MonthlyReturns -Dates $script:d -Value $script:v -Invested $script:i)
    }
    It "chains the days of a month and takes deposits out" {
        $script:m.Count | Should -Be 3
        $script:m[0].Key | Should -Be "2025-12"
        [math]::Round($script:m[0].Pct, 6) | Should -Be 10
        [math]::Round($script:m[1].Pct, 6) | Should -Be 10
        [math]::Round($script:m[2].Pct, 6) | Should -Be -10
        $script:m[1].Days | Should -Be 2
    }
    It "counts dividends as return" {
        $r = @(Get-MonthlyReturns -Dates @("2026-01-01", "2026-01-02") -Value @(100, 100) -Invested @(100, 100) -Dividends @(0, 3))
        [math]::Round($r[0].Pct, 6) | Should -Be 3
    }
    It "skips days without a value before them" {
        $r = @(Get-MonthlyReturns -Dates @("2026-01-01", "2026-02-02", "2026-02-03") -Value @(0, 100, 105) -Invested @(0, 100, 100))
        $r.Count | Should -Be 1
        $r[0].Key | Should -Be "2026-02"
        [math]::Round($r[0].Pct, 6) | Should -Be 5
    }
    It "builds one row per year with a chained total, newest first" {
        $t = @(Get-MonthTable -Returns $script:m)
        $t.Count | Should -Be 2
        $t[0].Year | Should -Be 2026
        [math]::Round($t[0].Total, 6) | Should -Be -1
        [double]::IsNaN($t[0].Months[2]) | Should -BeTrue
        [math]::Round($t[1].Months[11], 6) | Should -Be 10
    }
    It "summarises the months" {
        $s = Get-MonthStats -Returns $script:m
        $s.Count | Should -Be 3
        $s.Positive | Should -Be 2
        $s.Worst.Key | Should -Be "2026-02"
        Get-MonthStats -Returns @() | Should -BeNullOrEmpty
    }
}

Describe "Privacy columns (v12.0)" {
    It "masks the money columns of the contribution, scenario and dividend tables" {
        foreach ($h in @("Anfang", "Käufe", "Verkäufe", "Ende", "Veränderung", "Erwartet 12M", "Start", "Buys", "Sales", "End", "Change", "Expected 12M")) { Test-AmountColumn $h | Should -BeTrue -Because $h }
    }
    It "keeps public market data and dates visible" {
        foreach ($h in @("Letzte", "Pro Jahr", "Nächster Ex-Tag", "Quartalszahlen", "Zahltag", "Seit")) { Test-AmountColumn $h | Should -BeFalse -Because $h }
    }
}
Describe "Full report (v12.0)" {
    BeforeAll {
        $script:lines = @(@{ Name = "Value <a>"; Values = @(100, 150.5, 200); Color = "#000000"; Dashed = $false })
        $script:dates = [string[]]@("2026-01-01", "2026-01-02", "2026-01-03")
    }
    It "draws one line per series with decimal points in any culture" {
        $old = [System.Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("de-AT")
            $svg = ConvertTo-SvgLineChart -Dates $script:dates -Lines $script:lines
        } finally { [System.Threading.Thread]::CurrentThread.CurrentCulture = $old }
        $svg | Should -Match '<polyline'
        $svg | Should -Match 'points="70,276 480,149\.8 890,26"'
        $svg | Should -Match 'Value &lt;a&gt;'
    }
    It "leaves out the axis amounts on request" {
        ConvertTo-SvgLineChart -Dates $script:dates -Lines $script:lines | Should -Match 'text-anchor="end" dominant-baseline'
        ConvertTo-SvgLineChart -Dates $script:dates -Lines $script:lines -HideValues | Should -Not -Match 'text-anchor="end" dominant-baseline'
    }
    It "gives nothing without enough data" {
        ConvertTo-SvgLineChart -Dates @("2026-01-01") -Lines $script:lines | Should -Be ""
        ConvertTo-SvgLineChart -Dates $script:dates -Lines @() | Should -Be ""
    }
    It "puts the chart into the report and colours signed percentages" {
        $html = ConvertTo-HtmlReport -Title "T" -Sections @(
            [PSCustomObject]@{ Title = "Chart"; Headers = @(); Rows = @(); Note = ""; Html = "<svg></svg>" },
            [PSCustomObject]@{ Title = "Table"; Headers = @("A", "B", "C"); Rows = @(, @("+1.5%", "-2.0%", "-3.00 EUR")); Note = ""; Html = "" })
        $html | Should -Match '<svg></svg>'
        $html | Should -Match 'class="n pos">\+1\.5%'
        $html | Should -Match 'class="n neg">-2\.0%'
        $html | Should -Match 'class="n">-3\.00 EUR'
    }
}
