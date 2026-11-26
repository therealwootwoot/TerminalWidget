# TerminalWidget UI part 02 (Data) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

function Get-TickerEarningsBadge {
    param([string]$Sym, [int]$WindowDays = 7)
    $ev = $script:Events[([string]$Sym).ToUpper()]
    if ($null -eq $ev) { return $null }
    return (Get-EarningsBadge -EarningsDate ([string]$ev.EarningsDate) -WindowDays $WindowDays)
}

function Format-IsoDateDe {
    param([string]$Iso)
    if (-not $Iso -or $Iso.Length -lt 10) { return "" }
    $d = [DateTime]::MinValue
    if ([DateTime]::TryParseExact($Iso.Substring(0, 10), "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { return $d.ToString("dd.MM.yyyy") }
    return $Iso
}

# Persistent Intraday Cache
$script:IntradayCache = @{}
$rawCache = Load-JsonState -Path $script:CachePath -DefaultValue $null
if ($null -ne $rawCache) {
    foreach ($prop in $rawCache.PSObject.Properties) {
        $pts = New-Object System.Collections.Generic.List[PSObject]
        foreach ($pt in $prop.Value) {
            if ($null -ne $pt -and $pt.Close -gt 0) {
                $pts.Add([PSCustomObject]@{
                    Ts     = [long]$pt.Ts
                    Open   = if ($pt.Open) { [double]$pt.Open } else { [double]$pt.Close }
                    High   = [double]$pt.High
                    Low    = [double]$pt.Low
                    Close  = [double]$pt.Close
                    Volume = if ($pt.Volume) { [long]$pt.Volume } else { 0 }
                    Sess   = if ($pt.Sess) { [string]$pt.Sess } else { "R" }
                    Ext    = [bool]$pt.Ext
                })
            }
        }
        $script:IntradayCache[$prop.Name.ToUpper()] = $pts
    }
}

function Prune-IntradayCache {
    # Drop bars older than 5 days for EVERY ticker (Merge only prunes the active one)
    $cutoffMs = [DateTimeOffset]::UtcNow.AddDays(-5).ToUnixTimeMilliseconds()
    foreach ($key in @($script:IntradayCache.Keys)) {
        $kept = New-Object System.Collections.Generic.List[PSObject]
        foreach ($pt in $script:IntradayCache[$key]) {
            if ($null -ne $pt -and [long]$pt.Ts -ge $cutoffMs) { $kept.Add($pt) }
        }
        if ($kept.Count -eq 0) { $script:IntradayCache.Remove($key) } else { $script:IntradayCache[$key] = $kept }
    }
}
Prune-IntradayCache

function Merge-IntradayPoints {
    param([string]$Ticker, [array]$NewPoints)
    # SortedDictionary keeps the minute buckets ordered: no Sort-Object over
    # thousands of PSObjects on every poll any more
    $bucketMap = New-Object 'System.Collections.Generic.SortedDictionary[long,object]'
    $cutoffMs = [DateTimeOffset]::UtcNow.AddDays(-5).ToUnixTimeMilliseconds()

    if ($script:IntradayCache.ContainsKey($Ticker)) {
        foreach ($old in $script:IntradayCache[$Ticker]) {
            if ($null -ne $old -and [long]$old.Ts -ge $cutoffMs -and $old.Close -gt 0) {
                $bucketMap[[long][math]::Floor([long]$old.Ts / 60000.0)] = $old
            }
        }
    }
    foreach ($np in $NewPoints) {
        if ($null -ne $np -and [long]$np.Ts -ge $cutoffMs -and $np.Close -gt 0) {
            $bucketMap[[long][math]::Floor([long]$np.Ts / 60000.0)] = $np
        }
    }

    $list = New-Object System.Collections.Generic.List[PSObject]
    foreach ($item in $bucketMap.Values) { $list.Add($item) }
    $script:IntradayCache[$Ticker] = $list
    return $list
}

# ==============================================================================
# Part 2: Parallel HttpClient, Multi-FX & Technical Indicators
# ==============================================================================
$script:HttpHandler = New-Object System.Net.Http.HttpClientHandler
$script:HttpHandler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
$script:HttpClient = New-Object System.Net.Http.HttpClient($script:HttpHandler)
$script:HttpClient.Timeout = [TimeSpan]::FromSeconds([math]::Max(3, [int]$script:Config.HttpTimeoutSeconds))
$script:HttpClient.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

# Fallback rates (EUR -> X). Every currency actually in use is refreshed live;
# currencies listed in FxLive have a confirmed live rate.
$script:FxFromEur = @{
    "EUR" = 1.0000
    "USD" = 1.0950
    "CHF" = 0.9400
    "GBP" = 0.8350
    "CAD" = 1.5200
    "JPY" = 165.00
}
$script:FxLive    = New-Object System.Collections.Generic.HashSet[string]
[void]$script:FxLive.Add("EUR")
$script:FxMissing = New-Object System.Collections.Generic.HashSet[string]

# Rate limiting / slow refresh bookkeeping
$script:BackoffUntil      = [DateTime]::MinValue
$script:BackoffLevel      = 0
$script:LastRateLimited   = $false
$script:LastSlowRefresh   = [DateTime]::MinValue
$script:RefreshPending    = $false
$script:RefreshPendingForce = $false
$script:RefreshStarted    = [DateTime]::MinValue
$script:TransientStatus   = ""
$script:TransientUntil    = [DateTime]::MinValue
$script:ActiveGmtOffset   = 0
$script:LastCacheSave     = [DateTime]::MinValue
$script:ActiveSeriesKey   = ""
$script:LastDataTime      = $null
$script:FsForm            = $null
$script:FsCanvas          = $null

function Get-ChartUrl {
    param([string]$Symbol, [string]$Interval, [string]$Range, [switch]$PrePost)
    # Encode ^ & / etc. but keep "=" (legal in a path, used by FX symbols like EURUSD=X)
    $enc = [Uri]::EscapeDataString($Symbol).Replace("%3D", "=")
    $url = "https://query1.finance.yahoo.com/v8/finance/chart/${enc}?interval=$Interval&range=$Range"
    if ($PrePost) { $url += "&includePrePost=true" }
    return $url
}

# (market hours, time zones and holiday calendars: see NvidiaWidget.Core.ps1)

$script:IsRefreshing      = $false
$script:IsClosing         = $false
$script:LastFetchWarning  = ""
$script:LastFetchOffline  = $false
$script:QuoteStore        = @{}
$script:SparklineStore    = @{}
$script:ActiveSeries      = @()
$script:ActiveRsiSeries   = @()
$script:ActiveSma20       = @()
$script:ActiveSma50       = @()
$script:ActiveVwap        = @()
$script:ActiveBbUpper     = @()
$script:ActiveBbLower     = @()
$script:ActivePrevClose   = 0.0
$script:ActiveNativeCurr  = "USD"
$script:ChartCur          = "EUR"   # v5.1: currency the active chart series is in
$script:ActiveLongName    = ""
$script:ActiveLoadError   = ""

# ------------------------------------------------------------------------------
# Quote cache (v4.0): the last known quotes, sparklines and FX rates, so the
# window does not start empty. Cached quotes carry FromCache = $true (shown
# grey) until the first refresh replaces them. Cached FX rates are NOT marked
# live, so the status line still says when a rate is only a fallback.
# ------------------------------------------------------------------------------
$script:LastQuoteCacheSave = [DateTime]::MinValue

function Save-QuoteCache {
    try {
        $entries = New-Object System.Collections.Generic.List[PSObject]
        foreach ($k in @($script:QuoteStore.Keys)) {
            $q = $script:QuoteStore[$k]
            if ($null -eq $q -or [bool]$q.FromCache) { continue }
            $e = ConvertTo-QuoteCacheEntry -Quote $q -Spark $script:SparklineStore[$k]
            if ($null -ne $e) { $entries.Add($e) }
        }
        if ($entries.Count -eq 0) { return }
        $fx = [ordered]@{}
        foreach ($c in @($script:FxLive)) { if ($script:FxFromEur.ContainsKey($c)) { $fx[$c] = [double]$script:FxFromEur[$c] } }
        Save-JsonState -Path $script:QuoteCachePath -Data ([PSCustomObject]@{ SavedAt = (Get-Date).ToString("o"); Fx = $fx; Quotes = $entries.ToArray() })
        $script:LastQuoteCacheSave = Get-Date
    } catch {
        Write-WidgetLog "Saving the quote cache failed: $($_.Exception.Message)" "WARN"
    }
}

function Load-QuoteCache {
    $raw = Load-JsonState -Path $script:QuoteCachePath -DefaultValue $null
    if ($null -eq $raw) { return }
    $n = 0
    try {
        if ($null -ne $raw.Fx) {
            foreach ($prop in $raw.Fx.PSObject.Properties) {
                $c = Get-NormalizedCurrencyCode $prop.Name
                $r = ConvertFrom-JsonNumber $prop.Value 0.0
                if ($c -and $c -ne "EUR" -and $r -gt 0) { $script:FxFromEur[$c] = $r }
            }
        }
        foreach ($e in @($raw.Quotes)) {
            $q = ConvertFrom-QuoteCacheEntry -Entry $e
            if ($null -eq $q) { continue }
            $script:QuoteStore[$q.Ticker] = $q
            $sp = @(@($e.Spark) | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
            if ($sp.Count -ge 2) { $script:SparklineStore[$q.Ticker] = [double[]]$sp }
            $n++
        }
        Write-WidgetLog "Quote cache loaded: $n quotes (from $($raw.SavedAt))"
    } catch {
        Write-WidgetLog "Loading the quote cache failed: $($_.Exception.Message)" "WARN"
    }
}
Load-QuoteCache

function Invoke-ParallelFetch {
    # Synchronous fetch, only for the few interactive lookups that need an
    # answer right away (symbol resolve in dialogs / on Save). v3.0: no more
    # DoEvents while waiting - it let the user click into half-finished
    # handlers (re-entrancy). The wait is bounded by a cancellation timeout.
    param([string[]]$Urls, [int]$TimeoutSec = 6)
    $results = @{}
    if ($script:IsClosing -or -not $Urls -or $Urls.Count -eq 0) { return $results }

    $batch = @($Urls | Where-Object { $_ } | Select-Object -Unique)
    $cts = New-Object System.Threading.CancellationTokenSource
    $cts.CancelAfter([TimeSpan]::FromSeconds([math]::Max(2, $TimeoutSec)))
    $oldCursor = [System.Windows.Forms.Cursor]::Current
    [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $tasks = @{}
        foreach ($u in $batch) {
            try { $tasks[$u] = $script:HttpClient.GetAsync($u, $cts.Token) }
            catch { $results[$u] = $null }
        }

        $allTasks = [System.Threading.Tasks.Task[]]@($tasks.Values)
        if ($allTasks.Count -gt 0) {
            try { [void][System.Threading.Tasks.Task]::WaitAll($allTasks) }
            catch {
                # Individual HTTP task failures / cancellations handled below
            }
        }

        foreach ($u in $batch) {
            $t = $tasks[$u]
            $results[$u] = $null
            if ($null -ne $t -and $t.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $resp = $t.Result
                try {
                    $code = [int]$resp.StatusCode
                    if ($resp.IsSuccessStatusCode) {
                        # Content is already buffered (ResponseContentRead), so .Result does not block
                        $body = $resp.Content.ReadAsStringAsync().Result
                        # v5.7: RSS / XML stays text, everything else is JSON
                        $results[$u] = if ($body.TrimStart().StartsWith("<")) { $body } else { ($body | ConvertFrom-Json) }
                    } elseif ($code -eq 429) {
                        $script:LastRateLimited = $true
                        Write-WidgetLog "HTTP 429 (rate limited): $u" "WARN"
                    } elseif ($code -ne 404) {
                        Write-WidgetLog "HTTP ${code}: $u" "WARN"
                    }
                } catch {
                    Write-WidgetLog "Parse error for ${u}: $($_.Exception.Message)" "WARN"
                } finally {
                    $resp.Dispose()
                }
            } elseif ($null -ne $t -and $t.IsFaulted) {
                $inner = if ($t.Exception -and $t.Exception.InnerException) { $t.Exception.InnerException.Message } else { "unknown" }
                Write-WidgetLog "Request failed: $u ($inner)" "WARN"
            } elseif ($null -ne $t -and $t.IsCanceled) {
                Write-WidgetLog "Request timed out: $u" "WARN"
            }
        }
    } finally {
        [System.Windows.Forms.Cursor]::Current = $oldCursor
        $cts.Dispose()
    }
    return $results
}

# ------------------------------------------------------------------------------
# Background fetch worker (v2.8)
# HTTP requests AND JSON parsing run in a RunspacePool; the UI thread only gets
# the parsed objects via a completion callback. No DoEvents, no re-entrancy and
# no frozen window while Yahoo is slow. Invoke-ParallelFetch above is still used
# for the few synchronous lookups (symbol resolve on Enter / Save).
# ------------------------------------------------------------------------------
$script:FetchWorkerScript = {
    param($Client, [string[]]$Urls, [int]$MaxConc, [hashtable]$Fallbacks, [string[]]$KnownFx, [bool]$AutoFx, $Box, $Shared)

    $results = @{}
    $logs    = New-Object System.Collections.Generic.List[string]
    # Retry = URLs that failed in a way another Yahoo host might not (timeout,
    # connection error, 5xx, 401/403). 404 / 429 are not retried.
    $state   = @{ RateLimited = $false; Retry = (New-Object System.Collections.Generic.HashSet[string]) }
    # v7.7: per address @{ Code; Error; ETag; Modified } (used by the news feeds)
    $meta    = @{}
    if ($MaxConc -lt 1) { $MaxConc = 4 }

    function Fetch-UrlBatch {
        param([string[]]$List)
        $uniq = @($List | Where-Object { $_ -and -not $results.ContainsKey($_) } | Select-Object -Unique)
        for ($i = 0; $i -lt $uniq.Count; $i += $MaxConc) {
            if ($Shared.Cancel) { return }
            $end = [math]::Min($i + $MaxConc - 1, $uniq.Count - 1)
            $batch = @($uniq[$i..$end])
            $tasks = @{}
            foreach ($u in $batch) {
                try {
                    $cond = $null
                    if ($null -ne $Shared.Cond) { $cond = $Shared.Cond[$u] }
                    if ($null -eq $cond) { $tasks[$u] = $Client.GetAsync($u) }
                    else {
                        # v7.7: only send the feed again when it changed
                        $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, [string]$u)
                        if ($cond.ETag) { [void]$req.Headers.TryAddWithoutValidation("If-None-Match", [string]$cond.ETag) }
                        if ($cond.Modified) { [void]$req.Headers.TryAddWithoutValidation("If-Modified-Since", [string]$cond.Modified) }
                        $tasks[$u] = $Client.SendAsync($req)
                    }
                }
                catch { $meta[$u] = @{ Code = 0; Error = $_.Exception.Message }; $logs.Add("WARN|Request start failed: $u ($($_.Exception.Message))") }
            }
            $arr = [System.Threading.Tasks.Task[]]@($tasks.Values)
            if ($arr.Count -gt 0) {
                try {
                    while (-not [System.Threading.Tasks.Task]::WaitAll($arr, 100)) {
                        if ($Shared.Cancel) { return }
                    }
                } catch {
                    # individual failures are handled per task below
                }
            }
            foreach ($u in $batch) {
                $results[$u] = $null
                $t = $tasks[$u]
                if ($null -eq $t) { continue }
                if ($t.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                    $resp = $t.Result
                    try {
                        $code = [int]$resp.StatusCode
                        $m = @{ Code = $code; Error = ""; ETag = ""; Modified = "" }
                        try {
                            if ($null -ne $resp.Headers.ETag) { $m.ETag = $resp.Headers.ETag.ToString() }
                            if ($null -ne $resp.Content -and $null -ne $resp.Content.Headers.LastModified) { $m.Modified = $resp.Content.Headers.LastModified.ToString("r") }
                        } catch { }
                        $meta[$u] = $m
                        if ($code -eq 304) {
                            # not modified: nothing new
                        } elseif ($resp.IsSuccessStatusCode) {
                            $body = $resp.Content.ReadAsStringAsync().Result
                            $results[$u] = if ($body.TrimStart().StartsWith("<")) { $body } else { ($body | ConvertFrom-Json) }
                        } elseif ($code -eq 429) {
                            $state.RateLimited = $true
                            $logs.Add("WARN|HTTP 429 (rate limited): $u")
                        } elseif ($code -ne 404) {
                            $logs.Add("WARN|HTTP ${code}: $u")
                            [void]$state.Retry.Add($u)
                        }
                    } catch {
                        $logs.Add("WARN|Parse error for ${u}: $($_.Exception.Message)")
                    } finally {
                        $resp.Dispose()
                    }
                } elseif ($t.IsFaulted) {
                    $inner = if ($t.Exception -and $t.Exception.InnerException) { $t.Exception.InnerException.Message } else { "unknown" }
                    $meta[$u] = @{ Code = 0; Error = $inner }
                    $logs.Add("WARN|Request failed: $u ($inner)")
                    [void]$state.Retry.Add($u)
                } elseif ($t.IsCanceled) {
                    $meta[$u] = @{ Code = 0; Error = "Zeitüberschreitung" }
                    $logs.Add("WARN|Request timed out / cancelled: $u")
                    [void]$state.Retry.Add($u)
                }
            }
        }
    }

    # Yahoo host fallback (v2.9): query1 <-> query2. Results are always stored
    # under the ORIGINAL url; the host that worked last time is tried first.
    function Fetch-Mapped {
        param([string[]]$Orig, [string]$HostName)
        $map = @{}
        foreach ($o in $Orig) { if ($o) { $map[($o -replace '://query[12]\.', "://$HostName.")] = $o } }
        Fetch-UrlBatch -List @($map.Keys)
        foreach ($k in @($map.Keys)) {
            $o = $map[$k]
            if ($k -eq $o) { continue }
            if ($null -ne $results[$k] -or -not $results.ContainsKey($o)) { $results[$o] = $results[$k] }
            if ($state.Retry.Contains($k)) { [void]$state.Retry.Add($o) }
            [void]$results.Remove($k)
        }
    }
    $primaryHost = if ($Shared.PreferQ2) { "query2" } else { "query1" }
    $altHost     = if ($Shared.PreferQ2) { "query1" } else { "query2" }

    Fetch-Mapped -Orig $Urls -HostName $primaryHost
    $retry = @($Urls | Where-Object { $_ -and $null -eq $results[$_] -and $state.Retry.Contains($_) } | Select-Object -Unique)
    if ($retry.Count -gt 0 -and -not $Shared.Cancel) {
        foreach ($u in $retry) { [void]$state.Retry.Remove($u) }
        Fetch-Mapped -Orig $retry -HostName $altHost
        $recovered = @($retry | Where-Object { $null -ne $results[$_] }).Count
        if ($recovered -gt 0) {
            $Shared.PreferQ2 = ($altHost -eq "query2")
            $logs.Add("INFO|Yahoo host fallback: $recovered/$($retry.Count) via $altHost, next requests start with $altHost")
        }
    }

    # Fallback URLs (e.g. 1D chart of an EU stock before the open: <2 bars -> 5m/5d)
    if ($null -ne $Fallbacks -and $Fallbacks.Count -gt 0 -and -not $Shared.Cancel) {
        $fb = New-Object System.Collections.Generic.List[string]
        foreach ($prim in @($Fallbacks.Keys)) {
            $valid = 0
            try {
                foreach ($v in $results[$prim].chart.result[0].indicators.quote[0].close) {
                    if ($null -ne $v -and [double]$v -gt 0) { $valid++ }
                }
            } catch { }
            if ($valid -lt 2) { $fb.Add([string]$Fallbacks[$prim]) }
        }
        if ($fb.Count -gt 0) { Fetch-Mapped -Orig $fb.ToArray() -HostName $primaryHost }
    }

    # Currencies seen for the first time: fetch their EUR rate in the same job
    $extraFx = @{}
    if ($AutoFx -and -not $Shared.Cancel) {
        $known = New-Object System.Collections.Generic.HashSet[string]
        [void]$known.Add("EUR")
        foreach ($k in $KnownFx) { if ($k) { [void]$known.Add([string]$k) } }
        foreach ($u in @($results.Keys)) {
            $raw = $null
            try { $raw = [string]$results[$u].chart.result[0].meta.currency } catch { }
            if ([string]::IsNullOrEmpty($raw)) { continue }
            $c = if ($raw -ceq "GBp" -or $raw -ceq "GBX") { "GBP" } elseif ($raw -ceq "ZAc") { "ZAR" } elseif ($raw -ceq "ILA") { "ILS" } else { $raw.ToUpper() }
            if ($c -notmatch '^[A-Z]{3}$' -or $known.Contains($c)) { continue }
            [void]$known.Add($c)
            # identical to Get-ChartUrl -Symbol "EUR$c=X" -Interval 1d -Range 1d
            $extraFx[$c] = "https://query1.finance.yahoo.com/v8/finance/chart/EUR${c}=X?interval=1d&range=1d"
        }
        if ($extraFx.Count -gt 0) { Fetch-Mapped -Orig @($extraFx.Values) -HostName $primaryHost }
    }

    $Box.Results     = $results
    $Box.Logs        = $logs.ToArray()
    $Box.RateLimited = [bool]$state.RateLimited
    $Box.ExtraFx     = $extraFx
    $Box.Meta        = $meta
}

$script:WorkerShared = [hashtable]::Synchronized(@{ Cancel = $false; PreferQ2 = $false; Cond = [hashtable]::Synchronized(@{}) })
$script:FetchJobs    = New-Object System.Collections.Generic.List[PSObject]
$script:FetchLog     = New-Object System.Collections.Generic.Queue[object]   # v5.7: @{ T; P } per request
$script:WorkerPool   = $null
try {
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $script:WorkerPool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 3, $iss, $Host)
    $script:WorkerPool.Open()
    Write-WidgetLog "Background fetch worker ready"
} catch {
    Write-WidgetLog "RunspacePool unavailable, using synchronous fetch: $($_.Exception.Message)" "WARN"
    $script:WorkerPool = $null
}

$script:JobTimer = New-Object System.Windows.Forms.Timer
$script:JobTimer.Interval = 40

function Complete-FetchJob {
    param($Job)
    $box = $Job.Box
    if ($null -ne $box.Logs) {
        foreach ($l in $box.Logs) {
            $parts = [string]$l -split '\|', 2
            if ($parts.Count -eq 2) { Write-WidgetLog $parts[1] $parts[0] } else { Write-WidgetLog ([string]$l) "WARN" }
        }
    }
    if ($null -eq $box.Results) { $box.Results = @{} }
    if ($null -eq $box.ExtraFx) { $box.ExtraFx = @{} }
    if ($script:IsClosing -or $null -eq $Job.OnComplete) { return }
    try {
        & $Job.OnComplete $box $Job.Context
    } catch {
        Write-WidgetLog "Fetch callback failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
    }
}

function Pump-FetchJobs {
    if ($script:FetchJobs.Count -eq 0) { $script:JobTimer.Stop(); return }
    $done = @($script:FetchJobs | Where-Object { $_.Async.IsCompleted })
    foreach ($job in $done) {
        [void]$script:FetchJobs.Remove($job)
        try { [void]$job.PS.EndInvoke($job.Async) }
        catch { Write-WidgetLog "Fetch worker failed: $($_.Exception.Message)" "ERROR" }
        try { $job.PS.Dispose() } catch { }
        Complete-FetchJob -Job $job
    }
    if ($script:FetchJobs.Count -eq 0) { $script:JobTimer.Stop() }
}
$script:JobTimer.Add_Tick({ Pump-FetchJobs })

$script:ReqLog = New-Object System.Collections.ArrayList
function Get-RequestsPerMinute {
    # V7.1: how many requests went out in the last minute (for the status bar)
    $cut = (Get-Date).AddMinutes(-1)
    while ($script:ReqLog.Count -gt 0 -and [datetime]$script:ReqLog[0] -lt $cut) { $script:ReqLog.RemoveAt(0) }
    return [int]$script:ReqLog.Count
}

function Start-FetchJob {
    # Fire-and-forget fetch; $OnComplete runs later ON THE UI THREAD with
    # ($Box, $Context). $Box.Results maps url -> parsed JSON (or $null).
    param(
        [string[]]$Urls,
        [scriptblock]$OnComplete,
        $Context = $null,
        [hashtable]$Fallbacks = @{},
        [string[]]$KnownFx = @(),
        [switch]$AutoFx,
        [int]$MaxConcurrency = 4
    )
    if ($script:IsClosing) { return }
    try { $nowT = Get-Date; foreach ($u0 in @($Urls)) { [void]$script:ReqLog.Add($nowT) } } catch { }
    # v5.5: polling load for HEALTH (requests in the last hour)
    $nowR = Get-Date
    foreach ($u0 in @($Urls)) {
        $pv0 = Get-ProviderOfUrl $u0
        $script:FetchLog.Enqueue([PSCustomObject]@{ T = $nowR; P = $pv0 })
        if ($pv0 -in @("TwelveData", "Finnhub")) { Add-ProviderUsage $pv0 }
    }
    while ($script:FetchLog.Count -gt 0 -and ($nowR - $script:FetchLog.Peek().T).TotalMinutes -gt 60) { [void]$script:FetchLog.Dequeue() }
    $box = [hashtable]::Synchronized(@{ Results = $null; Logs = $null; RateLimited = $false; ExtraFx = $null; Meta = $null })
    $job = [PSCustomObject]@{ PS = $null; Async = $null; Box = $box; Context = $Context; OnComplete = $OnComplete }

    if ($null -eq $script:WorkerPool) {
        # Fallback: same worker code, synchronously on the UI thread
        try { & $script:FetchWorkerScript $script:HttpClient $Urls $MaxConcurrency $Fallbacks $KnownFx ([bool]$AutoFx) $box $script:WorkerShared }
        catch { Write-WidgetLog "Synchronous fetch failed: $($_.Exception.Message)" "ERROR" }
        Complete-FetchJob -Job $job
        return
    }

    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $script:WorkerPool
    [void]$ps.AddScript($script:FetchWorkerScript.ToString())
    [void]$ps.AddArgument($script:HttpClient)
    [void]$ps.AddArgument([string[]]$Urls)
    [void]$ps.AddArgument($MaxConcurrency)
    [void]$ps.AddArgument($Fallbacks)
    [void]$ps.AddArgument([string[]]$KnownFx)
    [void]$ps.AddArgument([bool]$AutoFx)
    [void]$ps.AddArgument($box)
    [void]$ps.AddArgument($script:WorkerShared)
    $job.PS = $ps
    $job.Async = $ps.BeginInvoke()
    $script:FetchJobs.Add($job)
    if (-not $script:JobTimer.Enabled) { $script:JobTimer.Start() }
}

# ------------------------------------------------------------------------------
# Company profiles (v4.1). quoteSummary (sector, industry, country) needs a
# Yahoo cookie (fc.yahoo.com) + crumb; the shared HttpClientHandler keeps the
# cookie. Without a crumb only the search API is used (sector, no country).
# ------------------------------------------------------------------------------
$script:ProfileWorkerScript = {
    param($Client, [string[]]$Symbols, $Box, $Shared)
    $logs = New-Object System.Collections.Generic.List[string]
    $res = @{}
    # v4.2: calendarEvents / summaryDetail = earnings and dividend dates
    $evOnly = [bool]$Box.EventsOnly
    # v4.9.5: financialData = analyst targets + consensus
    # v5.1: defaultKeyStatistics = fundamentals (P/B, PEG, EV/EBITDA)
    $mods = if ($Box.Modules) { [string]$Box.Modules } elseif ($evOnly) { "calendarEvents%2CsummaryDetail%2CfinancialData%2CdefaultKeyStatistics" } else { "assetProfile%2CquoteType%2CcalendarEvents%2CsummaryDetail%2CfinancialData%2CdefaultKeyStatistics" }
    $get = {
        param([string]$U)
        try {
            $t = $Client.GetAsync($U)
            while (-not $t.Wait(100)) { if ($Shared.Cancel) { return $null } }
            $r = $t.Result
            try { return @{ Code = [int]$r.StatusCode; Body = $r.Content.ReadAsStringAsync().Result } } finally { $r.Dispose() }
        } catch { return $null }
    }
    $crumb = [string]$Shared.Crumb
    if (-not $crumb -and -not $Shared.CrumbFailed) {
        [void](& $get "https://fc.yahoo.com")
        $c = & $get "https://query1.finance.yahoo.com/v1/test/getcrumb"
        $body = if ($null -ne $c) { ([string]$c.Body).Trim() } else { "" }
        if ($null -ne $c -and $c.Code -eq 200 -and $body.Length -gt 0 -and $body.Length -lt 40 -and $body -notmatch '[<{\s]') {
            $crumb = $body
            $Shared.Crumb = $crumb
            $logs.Add("INFO|Yahoo crumb obtained")
        } else {
            $Shared.CrumbFailed = $true
            $code = if ($null -ne $c) { $c.Code } else { "n/a" }
            $logs.Add("WARN|Yahoo crumb not available (HTTP $code): sector from the search only, country must be set by hand")
        }
    }
    foreach ($sym in $Symbols) {
        if ($Shared.Cancel) { break }
        $e = [Uri]::EscapeDataString($sym)
        $sum = $null; $srch = $null
        if ($crumb) {
            $r = & $get ("https://query2.finance.yahoo.com/v10/finance/quoteSummary/{0}?modules={1}&crumb={2}" -f $e, $mods, [Uri]::EscapeDataString($crumb))
            if ($null -ne $r -and $r.Code -eq 200) { try { $sum = $r.Body | ConvertFrom-Json } catch { } }
            elseif ($null -ne $r -and $r.Code -eq 401) { $Shared.Crumb = ""; $crumb = ""; $logs.Add("WARN|Yahoo crumb rejected (401), continuing with the search") }
        }
        if (-not $evOnly -and -not $Box.Modules) {
            $r2 = & $get ("https://query1.finance.yahoo.com/v1/finance/search?q={0}&quotesCount=5&newsCount=0" -f $e)
            if ($null -ne $r2 -and $r2.Code -eq 200) { try { $srch = $r2.Body | ConvertFrom-Json } catch { } }
        }
        $res[$sym] = @{ Summary = $sum; Search = $srch }
    }
    $Box.Results = $res
    $Box.Logs = $logs.ToArray()
    $Box.RateLimited = $false
    $Box.ExtraFx = @{}
}
$script:WorkerShared.Crumb = ""
$script:WorkerShared.CrumbFailed = $false
$script:ProfileJobRunning = $false

function Start-ProfileJob {
    # Fetches the profiles of $Symbols in the background; $OnComplete runs on
    # the UI thread after the store was updated and saved
    # v5.1: -Modules = other quoteSummary modules; the raw results go to $OnRaw
    param([string[]]$Symbols, [scriptblock]$OnComplete = $null, [bool]$EventsOnly = $false, [string]$Modules = "", [scriptblock]$OnRaw = $null)
    $syms = @($Symbols | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpper() } | Sort-Object -Unique)
    if ($syms.Count -eq 0 -or $script:IsClosing -or $script:ProfileJobRunning) { return }
    $script:ProfileJobRunning = $true
    $box = [hashtable]::Synchronized(@{ Results = $null; Logs = $null; RateLimited = $false; ExtraFx = $null; EventsOnly = ($EventsOnly -or [bool]$Modules); Modules = $Modules })
    $done = {
        param($Box, $Ctx)
        $script:ProfileJobRunning = $false
        if ($Box.Modules) { if ($null -ne $Ctx.Raw) { & $Ctx.Raw $Box.Results }; return }
        $n = 0; $ne = 0
        foreach ($sym in @($Box.Results.Keys)) {
            $rr = $Box.Results[$sym]
            if (-not $Box.EventsOnly) {
                $pr = ConvertFrom-YahooProfile -Summary $rr.Summary -Search $rr.Search -Symbol $sym
                $en = Get-ProfileEntry $sym
                foreach ($f in @("Sector", "Industry", "Country", "QuoteType", "Name")) { if ($pr.$f) { $en.$f = [string]$pr.$f } }
                $en.FetchedAt = (Get-Date).ToString("o")
                $n++
            }
            # v4.2: earnings / dividend dates (kept when Yahoo had nothing this time)
            $cal = if ($null -ne $rr.Summary) { ConvertFrom-YahooCalendar -Summary $rr.Summary } else { $null }
            Set-EventEntry -Ticker $sym -Cal $cal
            # v5.1: fundamentals for the ticker analysis
            $fund = if ($null -ne $rr.Summary) { ConvertFrom-YahooFundamentals -Summary $rr.Summary } else { $null }
            if ($null -ne $fund) {
                $script:Events[$sym].Fund = ConvertTo-StoredFund $fund
                # v5.7: one valuation snapshot per day for "vs. own history"
                $script:FundHist[$sym] = @(Add-FundSnapshot -History $script:FundHist[$sym] -Fund $script:Events[$sym].Fund -Day ((Get-Date).ToString("yyyy-MM-dd")))
                $script:FundHistDirty = $true
            }
            $ne++
        }
        if ($n -gt 0) { Save-Profiles; Write-WidgetLog "Profiles updated: $n" }
        if ($ne -gt 0) { Save-Events; Write-WidgetLog "Event dates updated: $ne" }
        if ($script:FundHistDirty) { $script:FundHistDirty = $false; try { Save-JsonState -Path $script:FundHistPath -Data $script:FundHist } catch { Write-WidgetLog "Fund history: $($_.Exception.Message)" "WARN" } }
        if ($null -ne $Ctx.Then) { & $Ctx.Then }
    }
    $job = [PSCustomObject]@{ PS = $null; Async = $null; Box = $box; Context = @{ Then = $OnComplete; Raw = $OnRaw }; OnComplete = $done }
    if ($null -eq $script:WorkerPool) {
        try { & $script:ProfileWorkerScript $script:HttpClient $syms $box $script:WorkerShared } catch { Write-WidgetLog "Profile fetch failed: $($_.Exception.Message)" "WARN" }
        Complete-FetchJob -Job $job
        return
    }
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $script:WorkerPool
    [void]$ps.AddScript($script:ProfileWorkerScript.ToString())
    [void]$ps.AddArgument($script:HttpClient)
    [void]$ps.AddArgument([string[]]$syms)
    [void]$ps.AddArgument($box)
    [void]$ps.AddArgument($script:WorkerShared)
    $job.PS = $ps
    $job.Async = $ps.BeginInvoke()
    $script:FetchJobs.Add($job)
    if (-not $script:JobTimer.Enabled) { $script:JobTimer.Start() }
}

function Stop-FetchWorker {
    # Called on shutdown: make running jobs bail out fast, then release the pool
    $script:WorkerShared.Cancel = $true
    try { $script:JobTimer.Stop() } catch { }
    try { $script:HttpClient.CancelPendingRequests() } catch { }
    foreach ($job in @($script:FetchJobs)) {
        try { [void]$job.Async.AsyncWaitHandle.WaitOne(1500) } catch { }
        try { $job.PS.Dispose() } catch { }
    }
    $script:FetchJobs.Clear()
    if ($null -ne $script:WorkerPool) { try { $script:WorkerPool.Dispose() } catch { } }
}


function Convert-CurrencyValue {
    param([double]$Amount, [string]$FromCurrency, [string]$ToCurrency)
    if ($Amount -eq 0) { return 0.0 }
    $norm = Normalize-CurrencyAndPrice -Price $Amount -RawCurrency $FromCurrency
    $val  = $norm.Price
    $from = $norm.Currency
    $to   = if ($ToCurrency) { $ToCurrency.ToUpper() } else { "EUR" }

    if ($from -eq $to) { return $val }

    foreach ($cc in @($from, $to)) {
        if (-not $script:FxLive.Contains($cc)) { [void]$script:FxMissing.Add($cc) }
    }
    $fromRate = if ($script:FxFromEur.ContainsKey($from) -and $script:FxFromEur[$from] -gt 0) { $script:FxFromEur[$from] } else { 1.0 }
    $toRate   = if ($script:FxFromEur.ContainsKey($to)   -and $script:FxFromEur[$to]   -gt 0) { $script:FxFromEur[$to] }   else { 1.0 }

    return (($val / $fromRate) * $toRate)
}

# v5.1: currency a ticker's price is shown in. With "Auto" it is the ticker's
# own trading currency (ABBN.SW in CHF, SAP.DE in EUR); depot values, sums and
# the portfolio always stay in the base currency $script:Config.Currency.
function Get-PriceCurrency {
    param([string]$Symbol)
    if (-not [bool]$script:Config.AutoCurrency) { return [string]$script:Config.Currency }
    $u = ([string]$Symbol).ToUpper()
    $raw = ""
    if ($script:QuoteStore.ContainsKey($u) -and $script:QuoteStore[$u].Currency) { $raw = [string]$script:QuoteStore[$u].Currency }
    elseif ($script:Portfolio.ContainsKey($u) -and $script:Portfolio[$u].Currency) { $raw = [string]$script:Portfolio[$u].Currency }
    if ($raw) {
        $n = (Normalize-CurrencyAndPrice -Price 1.0 -RawCurrency $raw).Currency
        if ($n -match '^[A-Z]{3}$') { return $n }
    }
    $g = Get-TickerCurrencyGuess $u
    if ($g) { return $g }
    return [string]$script:Config.Currency
}







function Get-SearchUrl {
    param([string]$Query)
    $encoded = [System.Web.HttpUtility]::UrlEncode($Query.Trim())
    return "https://query1.finance.yahoo.com/v1/finance/search?q=$encoded&quotesCount=12&newsCount=0"
}

# (ConvertFrom-YahooSearch, Get-ChartResult and Select-ResolvedSymbol live in
#  NvidiaWidget.Core.ps1 since v3.0)

# Raw input -> resolved symbol, for this session (v3.0). "NVIDIA" is looked up
# once; known symbols (quotes, watchlist, portfolio) need no network at all.
$script:ResolveCache = @{}
$script:ResolveSeq   = 0

function Get-KnownSymbol {
    param([string]$Raw)
    $u = ([string]$Raw).Trim().ToUpper()
    if (-not $u) { return "" }
    if ($script:ResolveCache.ContainsKey($u)) { return [string]$script:ResolveCache[$u] }
    if ($script:QuoteStore.ContainsKey($u) -or $script:Portfolio.ContainsKey($u) -or (@($script:Config.Watchlist) -contains $u)) { return $u }
    return ""
}

function Get-ResolveUrls {
    param([string]$Clean)
    return @{ Probe = (Get-ChartUrl -Symbol $Clean -Interval "1d" -Range "1d"); Search = (Get-SearchUrl -Query $Clean) }
}

function Complete-SymbolResolve {
    # Shared by the synchronous and the background path; caches only answers
    # that came from Yahoo (offline the raw input is used but not remembered)
    param([string]$Clean, $ProbeJson, $SearchJson)
    $hits = @(ConvertFrom-YahooSearch -Json $SearchJson)
    $sym = Select-ResolvedSymbol -Raw $Clean -ProbeJson $ProbeJson -SearchItems $hits
    if ($sym -and ($null -ne $ProbeJson -or $null -ne $SearchJson)) { $script:ResolveCache[$Clean] = $sym }
    return $sym
}

function Resolve-BestSymbol {
    # Synchronous (bounded wait, no DoEvents). Used by dialogs and Save
    # buttons; the ticker search box resolves in the background instead.
    param([string]$RawInput)
    $clean = ([string]$RawInput).Trim().ToUpper()
    if ([string]::IsNullOrWhiteSpace($clean)) { return "" }
    $known = Get-KnownSymbol -Raw $clean
    if ($known) { return $known }

    $u = Get-ResolveUrls -Clean $clean
    $res = Invoke-ParallelFetch -Urls @($u.Probe, $u.Search)
    return (Complete-SymbolResolve -Clean $clean -ProbeJson $res[$u.Probe] -SearchJson $res[$u.Search])
}

function Confirm-Action {
    param([string]$Text, [string]$Title = "Bestätigen")
    if ($env:TW_SMOKE_TEST) { return $true }
    # Pass the form as owner so the box never hides behind the TopMost widget
    $owner = if ($null -ne $form -and -not $form.IsDisposed) { $form } else { $null }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        $owner, $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    return ($ans -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Show-Toast {
    # V7.0: short message at the bottom right of the window; click to close
    param([string]$Text, [int]$Seconds = 4)
    try {
        if (-not [bool]$script:Config.ShowToasts -or [string]::IsNullOrWhiteSpace($Text)) { return }
        if ($null -eq $form -or $form.IsDisposed -or -not $form.Visible) { return }
        if ($null -eq $script:ToastPanel) {
            $pn = New-Object System.Windows.Forms.Panel
            $pn.Visible = $false
            $pn.Cursor = [System.Windows.Forms.Cursors]::Hand
            Enable-DoubleBuffering -Control $pn
            $pn.Add_Paint({
                param($sender, $e)
                $g = $e.Graphics
                $p = $script:Pal
                $g.Clear($p.BodyBg)
                $r = New-Object System.Drawing.RectangleF(1, 1, ($sender.Width - 3), ($sender.Height - 3))
                $br = New-Object System.Drawing.SolidBrush($p.Card)
                $pen = New-Object System.Drawing.Pen($p.Border, 1)
                Fill-RoundedRect $g $br $r ([float]$script:UiSpec.BtnRadius) $pen 0
                $br.Dispose(); $pen.Dispose()
                $bar = New-Object System.Drawing.SolidBrush($p.Accent)
                $g.FillRectangle($bar, (S 8), (S 8), (S 3), ($sender.Height - (S 16)))
                $bar.Dispose()
                $tr = New-Object System.Drawing.Rectangle((S 18), 0, ($sender.Width - (S 26)), $sender.Height)
                [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$script:ToastText, $fontUi, $tr, $p.Text, ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis))
            })
            $pn.Add_Click({ $script:ToastTimer.Stop(); $script:ToastPanel.Visible = $false })
            $form.Controls.Add($pn)
            $script:ToastPanel = $pn
            $script:ToastTimer = New-Object System.Windows.Forms.Timer
            $script:ToastTimer.Add_Tick({ $script:ToastTimer.Stop(); $script:ToastPanel.Visible = $false })
        }
        $script:ToastText = $Text
        $flags = [System.Windows.Forms.TextFormatFlags]::NoPadding
        $tw = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $fontUi, [System.Drawing.Size]::Empty, $flags).Width
        $w = [math]::Min([int]($form.ClientSize.Width - (S 24)), [math]::Max((S 160), $tw + (S 36)))
        $h = S 32
        $sb = 0
        if ($null -ne $script:PnlStatusBar -and $script:PnlStatusBar.Visible) { $sb = $script:PnlStatusBar.Height }
        $script:ToastPanel.SetBounds([int]($form.ClientSize.Width - $w - (S 12)), [int]($form.ClientSize.Height - $h - $sb - (S 12)), [int]$w, [int]$h)
        $script:ToastPanel.Visible = $true
        $script:ToastPanel.BringToFront()
        $script:ToastPanel.Invalidate()
        $script:ToastTimer.Stop()
        $script:ToastTimer.Interval = [int]([math]::Max(1, $Seconds) * 1000)
        $script:ToastTimer.Start()
    } catch { }
}

function Set-TransientStatus {
    param([string]$Text, [int]$Seconds = 5)
    Show-Toast -Text $Text -Seconds $Seconds
    $script:TransientStatus = $Text
    $script:TransientUntil  = (Get-Date).AddSeconds($Seconds)
    if ($null -ne $lblStatus) {
        $lblStatus.ForeColor = $script:Pal.Busy
        $lblStatus.Text = $Text
    }
}

function Add-SymbolToWatchlist {
    param([string]$RawSymbol, [switch]$SwitchToChart)
    $resolved = Resolve-BestSymbol -RawInput $RawSymbol
    if ([string]::IsNullOrWhiteSpace($resolved)) { return $false }

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($w in $script:Config.Watchlist) {
        if (-not [string]::IsNullOrWhiteSpace($w)) {
            $u = $w.Trim().ToUpper()
            if (-not $list.Contains($u)) { [void]$list.Add($u) }
        }
    }
    if (-not $list.Contains($resolved)) {
        [void]$list.Add($resolved)
        $script:Config.Watchlist = $list.ToArray()
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
    }
    if ($SwitchToChart) {
        Set-ActiveTab -TabName "Chart"
        Switch-ActiveTicker -NewTicker $resolved -SkipResolve $true
    } else {
        Refresh-AllMarketData
        Update-AllUiViews
    }
    return $true
}

function Remove-SymbolFromWatchlist {
    param([string]$Symbol, [bool]$AskConfirm = $true)
    $u = $Symbol.Trim().ToUpper()
    if ([string]::IsNullOrWhiteSpace($u)) { return $false }
    if (@($script:Config.Watchlist) -notcontains $u) { return $false }
    # v4.6: no question - Ctrl+Z restores the list ($AskConfirm kept for callers)
    $undoList = @($script:Config.Watchlist)

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($w in $script:Config.Watchlist) {
        if (-not [string]::IsNullOrWhiteSpace($w) -and $w.Trim().ToUpper() -ne $u) {
            [void]$list.Add($w.Trim().ToUpper())
        }
    }
    if ($list.Count -lt 1) {
        [System.Windows.Forms.MessageBox]::Show(
            $form,
            "Mindestens ein Ticker muss in der Watchlist verbleiben.",
            "Hinweis",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return $false
    }

    $script:Config.Watchlist = $list.ToArray()
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Set-Undo -Kind "Watchlist" -Data $undoList -Text "$u aus der Watchlist entfernt"
    if ($script:Config.ActiveTicker.ToUpper() -eq $u) {
        Switch-ActiveTicker -NewTicker $list[0] -SkipResolve $true
    } else {
        Update-AllUiViews
    }
    return $true
}


function Get-MetaPrevCloseFallback {
    param($Meta, [double]$RawMarket)
    if ($null -ne $Meta.previousClose -and [double]$Meta.previousClose -gt 0) { return [double]$Meta.previousClose }
    if ($null -ne $Meta.chartPreviousClose -and [double]$Meta.chartPreviousClose -gt 0) { return [double]$Meta.chartPreviousClose }
    return $RawMarket
}

function Update-FxFromResults {
    param([hashtable]$FxUrlMap, [hashtable]$Fetched)
    foreach ($cCode in @($FxUrlMap.Keys)) {
        $fxRes = Get-ChartResult $Fetched[$FxUrlMap[$cCode]]
        if ($null -ne $fxRes -and $null -ne $fxRes.meta.regularMarketPrice -and [double]$fxRes.meta.regularMarketPrice -gt 0) {
            $script:FxFromEur[$cCode] = [double]$fxRes.meta.regularMarketPrice
            [void]$script:FxLive.Add($cCode)
            [void]$script:FxMissing.Remove($cCode)
        }
    }
}

function Get-QuoteTiers {
    # Priority tier: refreshed every poll. Slow tier: watchlist-only tickers.
    $active = $script:Config.ActiveTicker.ToUpper()
    $prio = New-Object System.Collections.Generic.HashSet[string]
    [void]$prio.Add($active)
    foreach ($p in $script:Portfolio.Keys) { [void]$prio.Add($p.ToUpper()) }
    # (re-arming alerts need fresh data too, even while triggered)
    foreach ($a in $script:Alerts) {
        # v4.3: portfolio alerts ("DEPOT") have no symbol of their own; expired ones rest
        if ((Test-PortfolioAlertKind (Get-AlertKind $a.Condition)) -or (Test-AlertExpired -Alert $a)) { continue }
        if (-not $a.Triggered -or [int]$a.RearmMin -gt 0) { [void]$prio.Add($a.Ticker.ToUpper()) }
    }
    $slow = New-Object System.Collections.Generic.HashSet[string]
    foreach ($w in $script:Config.Watchlist) {
        $u = $w.ToUpper()
        if (-not $prio.Contains($u)) { [void]$slow.Add($u) }
    }
    foreach ($a in $script:Alerts) {
        if (Test-PortfolioAlertKind (Get-AlertKind $a.Condition)) { continue }
        $u = $a.Ticker.ToUpper(); if (-not $prio.Contains($u)) { [void]$slow.Add($u) }
    }
    return @{ Prio = $prio; Slow = $slow }
}

function Refresh-AllMarketData {
    # v2.8: asynchronous. Builds the request plan, hands it to the background
    # worker and returns immediately; Complete-MarketRefresh applies the result
    # on the UI thread (and runs alerts + UI update) when the data is in.
    param([switch]$Force)
    if ($script:IsClosing) { return }
    if ($script:IsRefreshing) {
        # A refresh is in flight: remember the request, it runs right after
        $script:RefreshPending = $true
        if ($Force) { $script:RefreshPendingForce = $true }
        return
    }
    # (rate-limit backoff is applied by the poll timer only, so user actions
    #  like switching ticker still load immediately)
    $plan = $null
    try {
        $plan = New-RefreshPlan -Force:$Force
    } catch {
        Write-WidgetLog "Refresh plan failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
        return
    }
    $script:IsRefreshing   = $true
    $script:RefreshStarted = Get-Date
    Update-RefreshIndicator
    Start-FetchJob -Urls $plan.Urls -Fallbacks $plan.Fallbacks -KnownFx $plan.KnownFx -AutoFx -Context $plan -OnComplete {
        param($Box, $Plan)
        Complete-MarketRefresh -Box $Box -Plan $Plan
    }
}

function Update-RefreshIndicator {
    if ($null -eq $btnRefreshNow -or $btnRefreshNow.IsDisposed) { return }
    $btnRefreshNow.ForeColor = if ($script:IsRefreshing) { $script:Pal.Busy } else { $script:Pal.Accent }
}

function Complete-MarketRefresh {
    param($Box, $Plan)
    try {
        Apply-RefreshResults -Box $Box -Plan $Plan
    } catch {
        Write-WidgetLog "Refresh failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
    } finally {
        $script:IsRefreshing = $false
    }
    if ($script:IsClosing) { return }
    # v4.0: keep the quote cache fresh (every 2 minutes)
    if (((Get-Date) - $script:LastQuoteCacheSave).TotalSeconds -ge 120 -and $null -ne $script:LastDataTime) { Save-QuoteCache }
    try {
        Evaluate-GlobalAlerts
        Update-AllUiViews
    } catch {
        Write-WidgetLog "UI update after refresh failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
    }
    Update-RefreshIndicator
    if ($script:RefreshPending) {
        $f = [bool]$script:RefreshPendingForce
        $script:RefreshPending = $false
        $script:RefreshPendingForce = $false
        Refresh-AllMarketData -Force:$f
    }
}

function New-RefreshPlan {
    param([switch]$Force)
    # Snapshot of what this refresh is for (user may change it mid-flight)
    $active   = $script:Config.ActiveTicker.ToUpper()
    $tf       = [string]$script:Config.Timeframe
    $dispCurr = Get-PriceCurrency $active
    $cfgCur   = [string]$script:Config.Currency
    $autoCur  = [bool]$script:Config.AutoCurrency
    $extCfg   = [bool]$script:Config.ShowExtended
    $useExt   = $extCfg -and $tf -eq "1d"
    $tfParams = Get-TimeframeParams -Tf $tf
    $now      = Get-Date

    $slowDue = $Force -or $script:Config.ActiveTab -eq "Watchlist" -or
               (($now - $script:LastSlowRefresh).TotalSeconds -ge [int]$script:Config.SlowRefreshSeconds)

    $tiers = Get-QuoteTiers
    $allTickers = New-Object System.Collections.Generic.HashSet[string]
    foreach ($s in $tiers.Prio) { [void]$allTickers.Add($s) }
    foreach ($s in $tiers.Slow) {
        # Slow tier only when due, but always fetch symbols we have no quote for yet
        if ($slowDue -or -not $script:QuoteStore.ContainsKey($s)) { [void]$allTickers.Add($s) }
    }

    # FX: every currency in use (quotes, portfolio, alerts, display)
    $fxNeeded = New-Object System.Collections.Generic.HashSet[string]
    foreach ($c in @("USD", "CHF", "GBP", $dispCurr)) { [void]$fxNeeded.Add($c) }
    foreach ($q in $script:QuoteStore.Values) { [void]$fxNeeded.Add([string]$q.Currency) }
    foreach ($p in $script:Portfolio.Values) { [void]$fxNeeded.Add([string]$p.Currency) }
    # (percent alerts store "%" as currency - not an FX symbol)
    # (only price alerts carry a real currency; "%", "RSI", "SMA" are markers)
    foreach ($a in $script:Alerts) { if ((Get-AlertKind $a.Condition) -in @("PRICE", "TRAIL", "EKPCT", "PFVAL") -and [string]$a.Currency -match '^[A-Z]{3}$') { [void]$fxNeeded.Add([string]$a.Currency) } }
    foreach ($c in $script:FxMissing) { [void]$fxNeeded.Add($c) }
    [void]$fxNeeded.Remove("EUR")

    $fxUrlMap = @{}
    foreach ($c in $fxNeeded) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        # FX moves slowly: only on slow ticks, or when we have no live rate yet
        if ($slowDue -or -not $script:FxLive.Contains($c)) {
            $fxUrlMap[$c] = Get-ChartUrl -Symbol "EUR$c=X" -Interval "1d" -Range "1d"
        }
    }

    $activeChartUrl = (Get-ChartUrl -Symbol $active -Interval $tfParams.Interval -Range $tfParams.Range -PrePost:$useExt) + "&events=div"
    $fallbackUrl = ""
    $fallbacks = @{}
    if ($tf -eq "1d") {
        # EU/CH exchanges before the open have no 2m bars for "today" yet
        $fallbackUrl = Get-ChartUrl -Symbol $active -Interval "5m" -Range "5d" -PrePost:$useExt
        $fallbacks[$activeChartUrl] = $fallbackUrl
    }

    $urlList = New-Object System.Collections.Generic.List[string]
    foreach ($u in $fxUrlMap.Values) { $urlList.Add($u) }
    $urlList.Add($activeChartUrl)

    # Comparison ticker: same interval/range as the active chart
    $compare = ([string]$script:Config.CompareTicker).ToUpper()
    $compareUrl = ""
    if ($compare -and $compare -ne $active) {
        $compareUrl = Get-ChartUrl -Symbol $compare -Interval $tfParams.Interval -Range $tfParams.Range -PrePost:$useExt
        $urlList.Add($compareUrl)
    } else {
        $compare = ""
    }
    # v5.0: further comparison tickers (up to 2)
    $moreUrls = [ordered]@{}
    if ($compare) {
        foreach ($cm in @($script:Config.CompareMore)) {
            $cu = ([string]$cm).ToUpper()
            if (-not $cu -or $cu -eq $active -or $cu -eq $compare -or $moreUrls.Contains($cu) -or $moreUrls.Count -ge 2) { continue }
            $mu = Get-ChartUrl -Symbol $cu -Interval $tfParams.Interval -Range $tfParams.Range -PrePost:$useExt
            $moreUrls[$cu] = $mu
            $urlList.Add($mu)
        }
    }

    $quoteUrlMap = @{}
    foreach ($sym in $allTickers) {
        # includePrePost: extended-hours bars give the pre-/after-market quote;
        # they are filtered out again for day change, sparkline and RSI
        $qUrl = Get-ChartUrl -Symbol $sym -Interval "1h" -Range "5d" -PrePost
        $quoteUrlMap[$sym] = $qUrl
        if (-not $urlList.Contains($qUrl)) { $urlList.Add($qUrl) }
    }

    $knownFx = New-Object System.Collections.Generic.List[string]
    foreach ($c in $script:FxLive) { $knownFx.Add($c) }
    foreach ($c in $fxUrlMap.Keys) { if (-not $knownFx.Contains($c)) { $knownFx.Add($c) } }

    return @{
        Active         = $active
        Tf             = $tf
        DispCurr       = $dispCurr
        CfgCur         = $cfgCur
        AutoCur        = $autoCur
        ExtCfg         = $extCfg
        UseExt         = $useExt
        SeriesKey      = "$active|$tf|$(if ($autoCur) { 'AUTO' } else { $dispCurr })|$useExt"
        Now            = $now
        SlowDue        = [bool]$slowDue
        AllTickers     = @($allTickers)
        FxUrlMap       = $fxUrlMap
        QuoteUrlMap    = $quoteUrlMap
        ActiveChartUrl = $activeChartUrl
        FallbackUrl    = $fallbackUrl
        Fallbacks      = $fallbacks
        Compare        = $compare
        CompareUrl     = $compareUrl
        CompareMore    = $moreUrls
        Urls           = $urlList.ToArray()
        KnownFx        = $knownFx.ToArray()
    }
}

function Update-QuoteFromResult {
    # 2. Quote + 5D sparkline + quick RSI (hourly bars) for one symbol
    param([string]$Sym, $R, [int]$RsiPeriod)
    $meta = $R.meta
    $rawMarket = if ($null -ne $meta.regularMarketPrice) { [double]$meta.regularMarketPrice } else { 0.0 }
    if ($rawMarket -le 0) { return }

    $rawCurr = if ($meta.currency) { [string]$meta.currency } else { "USD" }
    $normP = Normalize-CurrencyAndPrice -Price $rawMarket -RawCurrency $rawCurr
    $price = $normP.Price
    $curr  = $normP.Currency
    $unit  = (Normalize-CurrencyAndPrice -Price 1.0 -RawCurrency $rawCurr).Price   # 1.0 or 0.01 (GBp, ZAc, ILA)

    $tp = Get-TradingPeriodInfo -Meta $meta
    $rawPrev = Get-SessionPrevClose -Result $R -Tp $tp
    if ($null -eq $rawPrev -or $rawPrev -le 0) { $rawPrev = Get-MetaPrevCloseFallback -Meta $meta -RawMarket $rawMarket }
    $prev   = [double]$rawPrev * $unit
    $pct    = if ($prev -gt 0) { (($price - $prev) / $prev) * 100.0 } else { 0.0 }
    $high52 = if ($null -ne $meta.fiftyTwoWeekHigh -and [double]$meta.fiftyTwoWeekHigh -gt 0) { [double]$meta.fiftyTwoWeekHigh * $unit } else { 0.0 }
    $low52  = if ($null -ne $meta.fiftyTwoWeekLow  -and [double]$meta.fiftyTwoWeekLow  -gt 0) { [double]$meta.fiftyTwoWeekLow  * $unit } else { 0.0 }

    $sparkList = New-Object System.Collections.Generic.List[double]
    $extPrice = 0.0
    $extSess  = ""
    $extTs    = 0L
    if ($null -ne $R.indicators -and $null -ne $R.indicators.quote -and @($R.indicators.quote).Count -gt 0 -and $null -ne $R.indicators.quote[0].close -and $null -ne $R.timestamp) {
        $tsArr = @($R.timestamp)
        $clArr = @($R.indicators.quote[0].close)
        $nBars = [math]::Min($tsArr.Count, $clArr.Count)
        for ($k = 0; $k -lt $nBars; $k++) {
            $v = $clArr[$k]
            if ($null -ne $v -and [double]$v -gt 0 -and (Get-BarSession -TsSec ([long]$tsArr[$k]) -Tp $tp) -eq "R") {
                $sparkList.Add([double]$v * $unit)
            }
        }
        # The newest valid bar decides whether there is a pre-/after-market quote
        if ($null -ne $tp -and ($tp.HasPre -or $tp.HasPost)) {
            for ($k = $nBars - 1; $k -ge 0; $k--) {
                $v = $clArr[$k]
                if ($null -ne $v -and [double]$v -gt 0) {
                    $sess = Get-BarSession -TsSec ([long]$tsArr[$k]) -Tp $tp
                    if ($sess -ne "R") {
                        $extPrice = [double]$v * $unit
                        $extSess  = $sess
                        $extTs    = [long]$tsArr[$k]
                    }
                    break
                }
            }
        }
    }
    $extPct = if ($extPrice -gt 0 -and $price -gt 0) { (($extPrice - $price) / $price) * 100.0 } else { 0.0 }

    # v4.3: relative volume (today vs. previous days at the same time, regular session)
    $relVol = [double]::NaN
    try {
        $q0 = if ($null -ne $R.indicators -and $null -ne $R.indicators.quote -and @($R.indicators.quote).Count -gt 0) { $R.indicators.quote[0] } else { $null }
        if ($null -ne $q0 -and $null -ne $q0.volume -and $null -ne $R.timestamp) {
            $vTs = New-Object System.Collections.Generic.List[long]
            $vVo = New-Object System.Collections.Generic.List[double]
            $tsA = @($R.timestamp); $voA = @($q0.volume)
            for ($k = 0; $k -lt [math]::Min($tsA.Count, $voA.Count); $k++) {
                if ($null -ne $voA[$k] -and [double]$voA[$k] -gt 0 -and (Get-BarSession -TsSec ([long]$tsA[$k]) -Tp $tp) -eq "R") {
                    $vTs.Add([long]$tsA[$k]); $vVo.Add([double]$voA[$k])
                }
            }
            $off = if ($null -ne $tp) { [int]$tp.GmtOffset } else { 0 }
            if ($vTs.Count -gt 1) { $relVol = Get-RelativeVolume -Ts $vTs.ToArray() -Vol $vVo.ToArray() -GmtOffset $off }
        }
    } catch { $relVol = [double]::NaN }
    if ($price -gt 0 -and ($sparkList.Count -eq 0 -or [math]::Abs($sparkList[$sparkList.Count - 1] - $price) -gt 0.00001)) {
        $sparkList.Add($price)
    }
    $sparkArr = $sparkList.ToArray()
    $script:SparklineStore[$Sym] = $sparkArr

    # Hourly SMA (fast period) for the "Kurs > / < SMA" alerts
    $smaArr = Compute-Sma -Prices $sparkArr -Period ([int]$script:Config.SmaFastPeriod)
    $smaH = [double]::NaN
    if ($smaArr.Count -gt 0) { $smaH = $smaArr[$smaArr.Count - 1] }

    $rsiArr = Compute-Rsi -Prices $sparkArr -Period $RsiPeriod
    $lastRsi = [double]::NaN
    for ($k = $rsiArr.Count - 1; $k -ge 0; $k--) {
        if (-not [double]::IsNaN($rsiArr[$k])) { $lastRsi = $rsiArr[$k]; break }
    }

    $script:QuoteStore[$Sym] = [PSCustomObject]@{
        Ticker     = $Sym
        LongName   = if ($meta.shortName) { [string]$meta.shortName } else { $Sym }
        Price      = $price
        PrevClose  = $prev
        ChangePct  = $pct
        Currency   = $curr
        High52     = $high52
        Low52      = $low52
        Rsi14      = $lastRsi
        SmaFastH   = $smaH
        ExtPrice   = $extPrice
        ExtPct     = $extPct
        ExtSession = $extSess
        ExtTs      = $extTs
        RelVol     = $relVol
        Tp         = $tp
        Meta       = (New-MetaLite $meta)
        UpdatedAt  = (Get-Date)
    }
}

function Apply-RefreshResults {
    param($Box, $Plan)
    $active   = $Plan.Active
    $tf       = $Plan.Tf
    $dispCurr = $Plan.DispCurr
    $useExt   = $Plan.UseExt
    $fetched  = $Box.Results
    $script:LastRateLimited = [bool]$Box.RateLimited

    $failedCount = 0
    foreach ($u in $Plan.Urls) {
        if ($null -eq $fetched[$u]) { $failedCount++ }
    }
    if ($failedCount -lt $Plan.Urls.Count) { $script:LastDataTime = Get-Date }

    # 1. FX rates (planned ones + currencies the worker discovered on the way)
    Update-FxFromResults -FxUrlMap $Plan.FxUrlMap -Fetched $fetched
    if ($Box.ExtraFx.Count -gt 0) { Update-FxFromResults -FxUrlMap $Box.ExtraFx -Fetched $fetched }

    # 2. Quotes
    $rsiPeriod = [int]$script:Config.RsiPeriod
    foreach ($sym in $Plan.AllTickers) {
        $r = Get-ChartResult $fetched[$Plan.QuoteUrlMap[$sym]]
        if ($null -ne $r) { Update-QuoteFromResult -Sym $sym -R $r -RsiPeriod $rsiPeriod }
    }
    if ($Plan.SlowDue) { $script:LastSlowRefresh = $Plan.Now }

    # Status / rate-limit backoff
    if ($script:LastRateLimited) {
        $script:BackoffLevel = [math]::Min(5, $script:BackoffLevel + 1)
        $waitSec = [math]::Min(300, 30 * [math]::Pow(2, $script:BackoffLevel - 1))
        $script:BackoffUntil = (Get-Date).AddSeconds($waitSec)
        Write-WidgetLog "Rate limited, pausing auto-refresh for $waitSec s" "WARN"
    } else {
        $script:BackoffLevel = 0
    }
    $script:LastFetchOffline = ($failedCount -eq $Plan.Urls.Count -and -not $script:LastRateLimited)
    $script:LastFetchWarning = if ($script:LastRateLimited) {
        "Rate-Limit: Pause bis {0:HH:mm:ss}" -f $script:BackoffUntil
    } elseif ($failedCount -eq $Plan.Urls.Count) {
        "Offline / API nicht erreichbar"
    } elseif ($failedCount -gt 0) {
        "Teilweise veraltete Daten ($failedCount Fehler)"
    } else {
        ""
    }

    # The user switched ticker/timeframe/currency while we were fetching:
    # don't paint stale chart data, refresh again for the new selection.
    if ($active -ne $script:Config.ActiveTicker.ToUpper() -or $tf -ne $script:Config.Timeframe -or $Plan.CfgCur -ne [string]$script:Config.Currency -or $Plan.AutoCur -ne [bool]$script:Config.AutoCurrency -or $Plan.ExtCfg -ne [bool]$script:Config.ShowExtended) {
        $script:RefreshPending = $true
        return
    }

    # 3. Active ticker chart series (with fallback for EU/CH exchanges)
    $res0 = Get-ChartResult $fetched[$Plan.ActiveChartUrl]
    $validCount = 0
    if ($null -ne $res0 -and $null -ne $res0.indicators -and $null -ne $res0.indicators.quote -and @($res0.indicators.quote).Count -gt 0 -and $null -ne $res0.indicators.quote[0].close) {
        foreach ($v in $res0.indicators.quote[0].close) {
            if ($null -ne $v -and [double]$v -gt 0) { $validCount++ }
        }
    }
    if ($tf -eq "1d" -and $validCount -lt 2 -and $Plan.FallbackUrl) {
        $fbR = Get-ChartResult $fetched[$Plan.FallbackUrl]
        if ($null -ne $fbR) { $res0 = $fbR }
    }

    if ($null -ne $res0 -and $null -ne $res0.indicators -and $null -ne $res0.indicators.quote -and @($res0.indicators.quote).Count -gt 0) {
        Build-ActiveChartSeries -Res0 $res0 -Plan $Plan
        $cmpRes = if ($Plan.CompareUrl) { Get-ChartResult $fetched[$Plan.CompareUrl] } else { $null }
        Build-CompareSeries -R $cmpRes -Plan $Plan
        # v5.0: the further comparison tickers
        $keepMore = @{}
        if ($null -ne $Plan.CompareMore) {
            foreach ($cm in @($Plan.CompareMore.Keys)) {
                $al = Get-CompareAligned -R (Get-ChartResult $fetched[$Plan.CompareMore[$cm]]) -Plan $Plan
                if ($null -ne $al) { $keepMore[$cm] = $al } elseif ($script:ActiveCompareMore.ContainsKey($cm)) { $keepMore[$cm] = $script:ActiveCompareMore[$cm] }
            }
        }
        $script:ActiveCompareMore = $keepMore
        $script:CompareMoreSig = (@($keepMore.Keys | Sort-Object | ForEach-Object { "{0}:{1}" -f $_, @($keepMore[$_]).Count }) -join ",")
    } elseif ($script:ActiveSeriesKey -eq $Plan.SeriesKey -and @($script:ActiveSeries).Count -ge 2) {
        # Transient fetch failure: keep showing the last good chart (status bar warns)
    } else {
        $script:ActiveSeries    = @()
        $script:ActiveRsiSeries = @()
        $script:ActiveSma20     = @()
        $script:ActiveSma50     = @()
        $script:ActiveVwap      = @()
        $script:ActiveBbUpper   = @()
        $script:ActiveBbLower   = @()
        $script:ActiveLongName  = $active
        $script:ActiveLoadError = "Keine Kursdaten für '$active' gefunden."
    }
}

$script:ActiveCompare = @()
$script:CompareSig    = ""
$script:ActiveCompareMore = @{}
$script:CompareMoreSig = ""
$script:ChartRenderErrors = 0
$script:LastRenderError = ""

function Get-CompareAligned {
    # v5.0: closes of a comparison chart aligned to the active bars, or $null
    param($R, $Plan)
    if ($null -eq $R -or $null -eq $R.timestamp -or $null -eq $R.indicators) { return $null }
    $saveC = $script:ActiveCompare; $saveS = $script:CompareSig
    Build-CompareSeries -R $R -Plan ([PSCustomObject]@{ Compare = "x"; Tf = $Plan.Tf })
    $out = $script:ActiveCompare
    $script:ActiveCompare = $saveC; $script:CompareSig = $saveS
    return ,$out
}

function Build-CompareSeries {
    # Aligns the comparison ticker's closes to the active series (last known
    # close at or before each bar; daily charts are matched by calendar day)
    param($R, $Plan)
    if (-not $Plan.Compare -or $null -eq $R -or $null -eq $R.timestamp -or $null -eq $R.indicators) {
        # keep the previous line on a transient failure of the same comparison
        if (-not $Plan.Compare) { $script:ActiveCompare = @(); $script:CompareSig = "" }
        return
    }
    $tsArr = @($R.timestamp)
    $clArr = @($R.indicators.quote[0].close)
    $m = [math]::Min($tsArr.Count, $clArr.Count)
    $cTs = New-Object System.Collections.Generic.List[long]
    $cCl = New-Object System.Collections.Generic.List[double]
    for ($k = 0; $k -lt $m; $k++) {
        if ($null -ne $clArr[$k] -and [double]$clArr[$k] -gt 0) { $cTs.Add([long]$tsArr[$k] * 1000); $cCl.Add([double]$clArr[$k]) }
    }
    $ser = @($script:ActiveSeries)
    $n = $ser.Count
    $out = New-Object double[] $n
    $daily = $Plan.Tf -in @("3mo", "6mo", "1y")
    if ($daily) {
        $byDay = @{}
        for ($k = 0; $k -lt $cTs.Count; $k++) { $byDay[[long][math]::Floor($cTs[$k] / 86400000.0)] = $cCl[$k] }
        $last = [double]::NaN
        for ($i = 0; $i -lt $n; $i++) {
            $dk = [long][math]::Floor([long]$ser[$i].Ts / 86400000.0)
            if ($byDay.ContainsKey($dk)) { $last = [double]$byDay[$dk] }
            $out[$i] = $last
        }
    } else {
        $j = 0
        $last = [double]::NaN
        for ($i = 0; $i -lt $n; $i++) {
            $t = [long]$ser[$i].Ts
            while ($j -lt $cTs.Count -and $cTs[$j] -le $t) { $last = $cCl[$j]; $j++ }
            $out[$i] = $last
        }
    }
    $script:ActiveCompare = $out
    $script:CompareSig = "{0}|{1}|{2}" -f $Plan.Compare, $n, $(if ($n -gt 0) { $out[$n - 1] } else { 0 })
}

function Set-CompareTicker {
    param([string]$Symbol)
    $sym = $Symbol.Trim().ToUpper()
    if ($sym) { $sym = Resolve-BestSymbol -RawInput $sym }
    $script:Config.CompareTicker = $sym
    if (-not $sym) { $script:Config.CompareMore = @(); $script:ActiveCompareMore = @{} }
    $script:ActiveCompare = @()
    $script:CompareSig = ""
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    if ($sym) { Set-TransientStatus "Vergleich mit $sym wird geladen..." 3 } else { Set-TransientStatus "Vergleich entfernt" 2 }
    Refresh-AllMarketData
    Update-AllUiViews
}

function Switch-CompareTicker {
    # v5.0: "NVDA CMP" / row menu: add a comparison (up to 3) or remove it again
    param([string]$Symbol)
    $sym = ([string]$Symbol).Trim().ToUpper()
    if ($sym) { $sym = Resolve-BestSymbol -RawInput $sym }
    if (-not $sym) { return }
    $cur = @(@([string]$script:Config.CompareTicker) + @($script:Config.CompareMore) | Where-Object { $_ })
    $r = Set-CompareList -Current $cur -Symbol $sym -Max 3
    if ($r.Msg -eq "full") { Set-TransientStatus ("Höchstens 3 Vergleiche - erst einen entfernen ({0} CMP)" -f $cur[0]) 5; return }
    $lst = @($r.List)
    $script:Config.CompareTicker = if ($lst.Count -gt 0) { [string]$lst[0] } else { "" }
    $script:Config.CompareMore = if ($lst.Count -gt 1) { @($lst[1..($lst.Count - 1)]) } else { @() }
    $script:ActiveCompare = @(); $script:CompareSig = ""; $script:ActiveCompareMore = @{}
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Set-TransientStatus $(if ($r.Msg -eq "added") { "Vergleich: " + ($lst -join ", ") } elseif ($lst.Count -gt 0) { "$sym entfernt - Vergleich: " + ($lst -join ", ") } else { "Vergleich entfernt" }) 4
    Refresh-AllMarketData
    Update-AllUiViews
}

function Show-CompareDialog {
    $p = $script:Pal
    # v7.5: standard dialog template
    $sd = New-StandardDialog -Title "Vergleichen mit" -Subtitle "Ticker (Kursentwicklung in % ab Chartbeginn):" -W 400 -BodyH 32 -OkText "Vergleichen"
    $dlg = $sd.Dlg
    $dlg.TopMost = $true

    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.SetBounds(0, (S 4), $sd.Body.Width, (S 24))
    $cb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    $cb.BackColor = $p.Input; $cb.ForeColor = $p.Text; $cb.Font = $fontMono
    foreach ($sug in @("QQQ", "SPY", "^GSPC", "^NDX", "SOXX", "^GDAXI", "^SSMI", "^ATX", "BTC-USD")) { [void]$cb.Items.Add($sug) }
    foreach ($w in $script:Config.Watchlist) { if (-not $cb.Items.Contains($w)) { [void]$cb.Items.Add($w) } }
    $cb.Text = if ($script:Config.CompareTicker) { [string]$script:Config.CompareTicker } else { "QQQ" }
    $sd.Body.Controls.Add($cb)

    $owner = if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed) { $script:FsForm } else { $form }
    $res = $dlg.ShowDialog($owner)
    $txt = $cb.Text
    $dlg.Dispose()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK -and -not [string]::IsNullOrWhiteSpace($txt)) {
        Set-CompareTicker -Symbol $txt
    }
}

function ConvertTo-DisplayBars {
    # One pass: optional session repair (1D) + currency conversion -> NEW objects
    # (the intraday cache is never modified).
    #  - Repair: session re-derived from the bar time with the current trading
    #    period (cached bars may have been classified without it), and
    #    extended-hours wicks clipped to the body when they stick out > 1 %
    #    (single off-exchange prints produced long spikes in the post-market)
    param([array]$Bars, $Tp, [double]$Factor, [bool]$Repair)
    $out = New-Object System.Collections.Generic.List[PSObject]
    foreach ($b in $Bars) {
        if ($null -eq $b) { continue }
        $sess = [string]$b.Sess
        if ($Repair -and $null -ne $Tp) { $sess = Get-BarSession -TsSec ([long][math]::Floor([double]$b.Ts / 1000.0)) -Tp $Tp }
        if ([string]::IsNullOrEmpty($sess)) { $sess = "R" }
        $isExt = ($sess -ne "R")
        $o  = [double]$b.Open
        $cl = [double]$b.Close
        $hi = [double]$b.High
        $lo = [double]$b.Low
        if ($Repair -and $isExt) {
            $bodyHi = [math]::Max($o, $cl)
            $bodyLo = [math]::Min($o, $cl)
            if ($hi -gt ($bodyHi * 1.01)) { $hi = $bodyHi }
            if ($lo -lt ($bodyLo * 0.99)) { $lo = $bodyLo }
        }
        $out.Add([PSCustomObject]@{
            Ts     = [long]$b.Ts
            Open   = $o * $Factor
            High   = $hi * $Factor
            Low    = $lo * $Factor
            Close  = $cl * $Factor
            Volume = [long]$b.Volume
            Sess   = $sess
            Ext    = $isExt
        })
    }
    return $out.ToArray()
}

