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
        $conds.Count | Should -Be 8
        @($conds | ForEach-Object { Get-AlertKind $_ } | Sort-Object -Unique) -join "," | Should -Be "PCT,PRICE,RSI,SMA"
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
        Get-NextTheme "Terminal" | Should -Be "Dark"
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
        $labels = @("BB20", "PRE", "POST", "EUR", "USD", "CHF", "GBP", "OK")
        $used = New-Object System.Collections.Generic.HashSet[string]
        foreach ($line in (Get-Content -Path $ui -Encoding UTF8)) {
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
