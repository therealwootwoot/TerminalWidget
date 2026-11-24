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
        Get-NextTheme "Graphite" | Should -Be "Dark"
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
            $done = $p.WaitForExit(420000)
            if (-not $done) { try { $p.Kill() } catch { } }
        } finally {
            Remove-Item Env:\TW_SMOKE_TEST -ErrorAction SilentlyContinue
            Remove-Item Env:\TW_SMOKE_DIR -ErrorAction SilentlyContinue
        }
        $log = Join-Path $dir "widget.log"
        if (Test-Path $log) { Write-Host "---- widget.log (last 60 lines) ----"; Get-Content $log -Tail 60 | ForEach-Object { Write-Host $_ } }
        # v5.2: screenshots also into the log (base64), for reviews without artifact access
        if ($env:TW_SMOKE_SHOTS -and (Test-Path $env:TW_SMOKE_SHOTS)) {
            foreach ($png in Get-ChildItem -Path $env:TW_SMOKE_SHOTS -Filter *.png) {
                $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($png.FullName))
                Write-Host ("SHOT-BEGIN " + $png.Name)
                for ($i = 0; $i -lt $b64.Length; $i += 3000) { Write-Host ("SHOT|" + $b64.Substring($i, [math]::Min(3000, $b64.Length - $i))) }
                Write-Host ("SHOT-END " + $png.Name)
            }
        }
        $done | Should -BeTrue -Because "the widget must finish the smoke run within 7 minutes"
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
