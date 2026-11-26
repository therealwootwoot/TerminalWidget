# ==============================================================================
# v7.7: news - selectable sources, feed loading, reading, feed manager
# Loaded right after 05-ChartViews (which creates the news tab). Logic in Core.
# ==============================================================================
$script:NewsPath        = Join-Path $script:DataDir "news.json"
$script:NewsHistory     = @()
$script:NewsSaved       = @()
$script:NewsRead        = New-Object System.Collections.Generic.HashSet[string]
$script:NewsUnread      = New-Object System.Collections.Generic.HashSet[string]
$script:NewsNotified    = New-Object System.Collections.Generic.HashSet[string]
$script:NewsVersion     = 0          # counts changes of the list (grid + chart signature)
$script:NewsUnreadSig   = ""
$script:NewsUnreadCached = 0
$script:NewsPoolSig     = ""
$script:NewsPoolCache   = @()
$script:NewsShownSig    = ""
$script:NewsShownCache  = @()
$script:NewsPending     = 0          # fetch jobs still running
$script:NewsAllClosed   = $false
$script:NewsSavedMode   = $false     # list shows the saved items
$script:NewsQuery       = ""
$script:NewsLastRun     = @{}        # source id -> time of the last request
$script:FeedStatus      = @{}        # source id -> @{ LastOk; Error; Count }
$script:FeedPause       = @{}        # host -> @{ Level; Until } after HTTP 429
$script:NewsPreviewKey  = ""

function Import-NewsState {
    $d = Load-JsonState -Path $script:NewsPath -DefaultValue $null
    if ($null -eq $d) { return }
    $script:NewsHistory = @(@($d.History) | ForEach-Object { ConvertFrom-NewsRecord $_ } | Where-Object { $null -ne $_ })
    $script:NewsSaved = @(@($d.Saved) | ForEach-Object { ConvertFrom-NewsRecord $_ } | Where-Object { $null -ne $_ })
    foreach ($k in @($d.Read)) { if ($k) { [void]$script:NewsRead.Add([string]$k) } }
    foreach ($k in @($d.Unread)) { if ($k) { [void]$script:NewsUnread.Add([string]$k) } }
    foreach ($k in @($d.Notified)) { if ($k) { [void]$script:NewsNotified.Add([string]$k) } }
    $script:NewsItems = @($script:NewsHistory)
}

function Save-NewsState {
    if ($script:SmokeMode) { return }
    # marks of items that are gone are dropped
    $known = New-Object System.Collections.Generic.HashSet[string]
    foreach ($n in (@($script:NewsHistory) + @($script:NewsSaved))) { if ($null -ne $n) { [void]$known.Add([string]$n.Key) } }
    foreach ($set in @($script:NewsRead, $script:NewsUnread, $script:NewsNotified)) {
        foreach ($k in @($set)) { if ($known.Count -gt 0 -and -not $known.Contains($k)) { [void]$set.Remove($k) } }
    }
    Save-JsonState -Path $script:NewsPath -Data ([PSCustomObject]@{
        Version  = 1
        History  = @($script:NewsHistory | ForEach-Object { ConvertTo-NewsRecord $_ })
        Saved    = @($script:NewsSaved | ForEach-Object { ConvertTo-NewsRecord $_ })
        Read     = @($script:NewsRead)
        Unread   = @($script:NewsUnread)
        Notified = @($script:NewsNotified)
    })
}

# ---- which sources ----
function Get-EnabledNewsIds {
    $ids = @(@($script:Config.NewsSources) | Where-Object { $null -ne $_ -and $_.On } | ForEach-Object { [string]$_.Id })
    if ([bool]$script:Config.NewsYahoo) { $ids = @("yahoo") + $ids }
    return @($ids)
}

function Get-NotifyNewsIds {
    $ids = @(@($script:Config.NewsSources) | Where-Object { $null -ne $_ -and $_.On -and $_.Notify } | ForEach-Object { [string]$_.Id })
    if ([bool]$script:Config.NewsYahoo -and [bool]$script:Config.NewsYahooNotify) { $ids = @("yahoo") + $ids }
    return @($ids)
}

function Get-NewsStateSig {
    # changes whenever the content or a filter of the list changes
    return "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}" -f $script:NewsVersion, @($script:NewsItems).Count, [string](@($script:NewsItems)[0].Key), (@($script:Config.NewsViewHidden) -join ","),
        (@($script:Config.NewsMuted) -join ","), [string]$script:Config.NewsInclude, [string]$script:Config.NewsExclude, [bool]$script:Config.NewsMergeSimilar, (@(Get-EnabledNewsIds) -join ",")
}

function Get-NewsPool {
    # everything that counts: switched-on and visible sources, without muted publishers and rule matches
    $sig = Get-NewsStateSig
    if ($sig -eq $script:NewsPoolSig) { return @($script:NewsPoolCache) }
    $items = @(Select-NewsBySource -Items $script:NewsItems -Enabled @(Get-EnabledNewsIds) -Hidden @($script:Config.NewsViewHidden))
    $items = @(Remove-MutedNews -Items $items -Muted @($script:Config.NewsMuted))
    $script:NewsPoolCache = @(Select-NewsByRules -Items $items -Include @(ConvertTo-KeywordList ([string]$script:Config.NewsInclude)) -Exclude @(ConvertTo-KeywordList ([string]$script:Config.NewsExclude)))
    $script:NewsPoolSig = $sig
    return @($script:NewsPoolCache)
}

function Get-NewsShown {
    # the rows of the list: pool or saved items, then ticker filter, search, merging.
    # Kept until something changes: the list is redrawn every minute for the ages.
    $sig = "{0}|{1}|{2}|{3}|{4}|{5}" -f (Get-NewsStateSig), [string]$script:Config.NewsFilter, $script:NewsQuery, $script:NewsSavedMode, (@($script:Portfolio.Keys) -join ","), (@($script:Config.Watchlist) -join ",")
    if ($sig -eq $script:NewsShownSig) { return @($script:NewsShownCache) }
    $items = if ($script:NewsSavedMode) { @($script:NewsSaved) } else { @(Get-NewsPool) }
    $items = @(Select-NewsItems -Items $items -Filter ([string]$script:Config.NewsFilter) -Holdings @($script:Portfolio.Keys) -Watchlist @($script:Config.Watchlist))
    if ($script:NewsQuery) { $items = @(Search-NewsItems -Items $items -Query $script:NewsQuery) }
    # at most 250 rows: merging and filling the list stay quick with a long history
    $items = @($items | Select-Object -First 250)
    if ([bool]$script:Config.NewsMergeSimilar -and -not $script:NewsSavedMode) { $items = @(Merge-SimilarNews -Items $items) }
    $script:NewsShownCache = @($items)
    $script:NewsShownSig = $sig
    return @($items)
}

function Get-NewsUnreadTotal {
    # asked on every screen update: recounted only when something changed
    $sig = "{0}|{1}" -f (Get-NewsStateSig), $script:NewsSeenAt.Ticks
    if ($sig -eq $script:NewsUnreadSig) { return $script:NewsUnreadCached }
    # the badge shows at most 99, so the newest 120 unread items are enough
    $items = @(Get-NewsPool | Where-Object { Test-NewsUnread -Item $_ -Since $script:NewsSeenAt -ReadKeys $script:NewsRead -UnreadKeys $script:NewsUnread } | Select-Object -First 120)
    if ([bool]$script:Config.NewsMergeSimilar) { $items = @(Merge-SimilarNews -Items $items) }
    $script:NewsUnreadSig = $sig
    $script:NewsUnreadCached = @($items).Count
    return $script:NewsUnreadCached
}

function Update-NewsViews {
    $script:NewsVersion++
    if ($viewNews.Visible) { Refresh-NewsGrid }
    Update-NewsBadge
}

# ---- loading ----
function Get-NewsNames {
    param([string[]]$Symbols)
    $names = @{}
    foreach ($s in @($Symbols)) {
        $q0 = $script:QuoteStore[$s]
        $nm = if ($null -ne $q0 -and $q0.LongName) { [string]$q0.LongName } elseif ($null -ne $script:Profiles[$s]) { [string]$script:Profiles[$s].Name } else { "" }
        if ($nm) { $names[([string]$s).ToUpperInvariant()] = $nm }
    }
    return $names
}

function Add-NewsFresh {
    param($Fresh)
    $days = [int]$script:Config.NewsHistoryDays
    foreach ($s in @($script:Config.NewsSources)) { if ($s.On -and [int]$s.MaxAgeDays -gt $days) { $days = [int]$s.MaxAgeDays } }
    $script:NewsHistory = @(Update-NewsHistory -History $script:NewsHistory -Fresh $Fresh -MaxDays $days -Max 600)
    $script:NewsItems = @($script:NewsHistory)
}

function Complete-NewsJob {
    $script:NewsPending = [math]::Max(0, $script:NewsPending - 1)
    if ($script:NewsPending -gt 0) { Update-NewsViews; return }
    $script:NewsLoading = $false
    if (-not $script:NewsError) {
        $script:NewsLoadedAt = Get-Date
        # first start: nothing counts as unread
        if ($script:NewsSeenAt -eq [DateTime]::MinValue) {
            Set-NewsSeen (Get-NewsNewest)
            $script:NewsBoldSince = $script:NewsSeenAt
        }
        Invoke-NewsKeywordCheck
        Save-NewsState
    }
    Update-NewsViews
}

function Start-YahooNewsJob {
    param([string[]]$Symbols)
    $urls = @{}
    foreach ($s in $Symbols) { $urls[$s] = Get-ProviderUrl -Kind "Search" -Symbol $s -NewsCount 10 }
    $script:NewsPending++
    Start-FetchJob -Urls @($urls.Values) -MaxConcurrency 4 -Context @{ Urls = $urls } -OnComplete {
        param($Box, $Ctx)
        try {
            if ([bool]$Box.RateLimited) {
                # Yahoo asked to slow down: same back-off as the price refresh (30 s doubling, max 5 min)
                $script:BackoffLevel = [math]::Min(5, $script:BackoffLevel + 1)
                $script:BackoffUntil = (Get-Date).AddSeconds([math]::Min(300, 30 * [math]::Pow(2, $script:BackoffLevel - 1)))
                $script:NewsLastRun.Remove("yahoo")
                Write-WidgetLog ("News (Yahoo): rate limit, pause until {0:HH:mm:ss}" -f $script:BackoffUntil) "WARN"
            }
            $by = @{}
            $ok = 0
            foreach ($s in $Ctx.Urls.Keys) {
                $j = $Box.Results[$Ctx.Urls[$s]]
                if ($null -ne $j) { $ok++ }
                $by[$s] = @(ConvertFrom-YahooNews $j)
            }
            if ($ok -eq 0) {
                $script:NewsError = "offline"
                $script:FeedStatus["yahoo"] = @{ LastOk = $script:FeedStatus["yahoo"].LastOk; Error = "keine Antwort"; Count = 0 }
                Write-WidgetLog "News: no answer for $($Ctx.Urls.Count) tickers" "WARN"
            } else {
                $items = @(Merge-NewsFeed -BySymbol $by -Max 200)
                $script:FeedStatus["yahoo"] = @{ LastOk = (Get-Date); Error = ""; Count = $items.Count }
                Add-NewsFresh $items
            }
        } finally { Complete-NewsJob }
    }
}

function Start-FeedJob {
    # own feeds in their own job: a rate limit or error here never touches the price refresh
    param($Requests)
    $script:NewsPending++
    $urls = @($Requests | ForEach-Object { [string]$_.Url } | Select-Object -Unique)
    Start-FetchJob -Urls $urls -MaxConcurrency 2 -Context @{ Requests = @($Requests) } -OnComplete {
        param($Box, $Ctx)
        try { Receive-FeedResults -Box $Box -Requests $Ctx.Requests }
        finally { Complete-NewsJob }
    }
}

function Receive-FeedResults {
    param($Box, $Requests)
    $symbols = @(Get-NewsSymbols -Holdings @($script:Portfolio.Keys | Sort-Object) -Watchlist @($script:Config.Watchlist) -Max 60)
    $terms = Get-NewsMatchTerms -Symbols $symbols -Names (Get-NewsNames $symbols) -Aliases (ConvertTo-NewsAliases ([string]$script:Config.NewsAliases))
    $fresh = @()
    $sum = @{}
    foreach ($r in @($Requests)) {
        $src = @($script:Config.NewsSources | Where-Object { $_.Id -eq $r.Id })[0]
        if ($null -eq $src) { continue }
        if (-not $sum.ContainsKey($r.Id)) { $sum[$r.Id] = @{ Ok = 0; Count = 0; Error = "" } }
        $url = [string]$r.Url
        $m = $null
        if ($null -ne $Box.Meta) { $m = $Box.Meta[$url] }
        $body = $Box.Results[$url]
        $hostName = Get-ProviderOfUrl $url
        $code = if ($null -ne $m) { [int]$m.Code } else { 0 }
        if ($code -eq 429) {
            $level = 1
            if ($script:FeedPause.ContainsKey($hostName)) { $level = [int]$script:FeedPause[$hostName].Level + 1 }
            $script:FeedPause[$hostName] = @{ Level = $level; Until = (Get-Date).AddSeconds((Get-FeedPauseSeconds $level)) }
            $sum[$r.Id].Error = "zu viele Abfragen (429), Pause bis {0:HH:mm}" -f $script:FeedPause[$hostName].Until
        } elseif ($code -eq 304) {
            $sum[$r.Id].Ok++
            $script:FeedPause.Remove($hostName)
        } elseif ($body -is [string] -and $body -match '(?i)<(rss|feed|rdf:RDF)\b') {
            $entries = @(ConvertFrom-RssFeed -Text $body -Fallback (Get-NewsSourceLabel $src))
            $items = @(ConvertTo-FeedItems -Entries $entries -Source $src -Ticker ([string]$r.Ticker) -Terms $terms)
            $fresh += $items
            $sum[$r.Id].Ok++
            $sum[$r.Id].Count += $items.Count
            $script:FeedPause.Remove($hostName)
            if ($m.ETag -or $m.Modified) { $script:WorkerShared.Cond[$url] = @{ ETag = [string]$m.ETag; Modified = [string]$m.Modified } }
        } else {
            $sum[$r.Id].Error = if ($code -ge 400) { "HTTP $code" } elseif ($code -eq 0) { if ($m.Error) { [string]$m.Error } else { "keine Antwort" } } else { "kein RSS- oder Atom-Feed" }
        }
    }
    foreach ($id in $sum.Keys) {
        $s = $sum[$id]
        $old = $script:FeedStatus[$id]
        $lastOk = if ($s.Ok -gt 0) { Get-Date } elseif ($null -ne $old) { $old.LastOk } else { $null }
        # nothing new (304) keeps the last count
        $count = if ($s.Count -eq 0 -and $s.Ok -gt 0 -and $null -ne $old) { $old.Count } else { $s.Count }
        $script:FeedStatus[$id] = @{ LastOk = $lastOk; Error = [string]$s.Error; Count = $count }
        if ($s.Error) { Write-WidgetLog ("News feed {0}: {1}" -f $id, $s.Error) "WARN" }
    }
    if ($fresh.Count -gt 0) { Add-NewsFresh $fresh }
    if (@($sum.Values | Where-Object { $_.Ok -gt 0 }).Count -gt 0) { $script:NewsError = "" }
}

function Start-NewsLoad {
    # asks every switched-on source that is due (-Force: all of them)
    param([switch]$Force)
    if ($script:IsClosing -or $script:NewsLoading) { return }
    $now = Get-Date
    $global = [int]$script:Config.NewsRefreshMinutes
    $symbols = @(Get-NewsSymbols -Holdings @($script:Portfolio.Keys | Sort-Object) -Watchlist @($script:Config.Watchlist) -Max 40)

    # Yahoo waits for the same pause as the prices
    $yahooDue = $false
    if ([bool]$script:Config.NewsYahoo -and $symbols.Count -gt 0 -and $now -ge $script:BackoffUntil) {
        $pseudo = [PSCustomObject]@{ Id = "yahoo"; On = $true; Minutes = 0 }
        $yahooDue = (@(Get-DueNewsSources -Sources @($pseudo) -LastRun $script:NewsLastRun -GlobalMinutes $global -Now $now -AllClosed $script:NewsAllClosed -Force:$Force).Count -gt 0)
    }
    $due = @(Get-DueNewsSources -Sources @($script:Config.NewsSources) -LastRun $script:NewsLastRun -GlobalMinutes $global -Now $now -AllClosed $script:NewsAllClosed -Force:$Force)
    $requests = @()
    if ($due.Count -gt 0) {
        $all = @(Get-NewsFeedRequests -Sources $due -Symbols $symbols -Names (Get-NewsNames $symbols))
        $requests = @($all | Where-Object { $p = $script:FeedPause[(Get-ProviderOfUrl ([string]$_.Url))]; $null -eq $p -or $now -ge $p.Until })
    }
    if (-not $yahooDue -and $requests.Count -eq 0) {
        if ($script:NewsLoadedAt -eq [DateTime]::MinValue -and @(Get-EnabledNewsIds).Count -eq 0) { $script:NewsLoadedAt = $now; Update-NewsViews }
        return
    }
    $script:NewsLoading = $true
    $script:NewsError = ""
    foreach ($s in $due) { $script:NewsLastRun[[string]$s.Id] = $now }
    # hold one extra count so that a synchronous first job cannot finish the round early
    $script:NewsPending++
    if ($yahooDue) { $script:NewsLastRun["yahoo"] = $now; Start-YahooNewsJob -Symbols $symbols }
    if ($requests.Count -gt 0) { Start-FeedJob -Requests $requests }
    if ($viewNews.Visible) { Update-NewsInfo }
    Complete-NewsJob
}

function Invoke-NewsKeywordCheck {
    # tray + phone push for new headlines with a chosen word about a held ticker (optionally
    # the watchlist), only from sources that may notify. Each item once: notified keys are
    # kept; the first run only notes what is there. Feeds with long intervals can deliver
    # items that are a little older than the newest one, so the check looks 6 hours back.
    $kw = @(ConvertTo-KeywordList ([string]$script:Config.NewsKeywords))
    $newest = Get-NewsNewest
    $last = [DateTime]::MinValue
    if ([string]$script:Config.NewsKeywordLastAt) {
        [void][DateTime]::TryParse([string]$script:Config.NewsKeywordLastAt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$last)
    }
    if ($kw.Count -gt 0) {
        $syms = @($script:Portfolio.Keys)
        if ([bool]$script:Config.NewsKeywordWatch) { $syms += @($script:Config.Watchlist) }
        $pool = @(Select-NewsBySource -Items $script:NewsItems -Enabled @(Get-NotifyNewsIds))
        $pool = @(Remove-MutedNews -Items $pool -Muted @($script:Config.NewsMuted))
        $pool = @(Select-NewsByRules -Items $pool -Exclude @(ConvertTo-KeywordList ([string]$script:Config.NewsExclude)))
        $first = ($last -eq [DateTime]::MinValue)
        $since = if ($first) { [DateTime]::MinValue } elseif ($script:NewsNotified.Count -eq 0) { $last } else { $last.AddHours(-6) }
        $hits = @(Find-NewsKeywordHits -Items $pool -Keywords $kw -Symbols $syms -Since $since | Where-Object { -not $script:NewsNotified.Contains([string]$_.Item.Key) })
        # the same story from several sources is one notice
        if ($hits.Count -gt 1) {
            $keep = @(Merge-SimilarNews -Items @($hits | ForEach-Object { $_.Item }) | ForEach-Object { [string]$_.Key })
            foreach ($h in @($hits | Where-Object { $keep -notcontains [string]$_.Item.Key })) { [void]$script:NewsNotified.Add([string]$h.Item.Key) }
            $hits = @($hits | Where-Object { $keep -contains [string]$_.Item.Key })
        }
        foreach ($h in $hits) { [void]$script:NewsNotified.Add([string]$h.Item.Key) }
        if (-not $first) {
            foreach ($h in ($hits | Select-Object -Last 3)) {
                $title = "News {0}: {1}" -f $h.Sym, $h.Keyword
                $msg = "{0} ({1})" -f [string]$h.Item.Title, [string]$h.Item.Publisher
                $push = Send-WidgetNotification -Title $title -Message $msg -Kind "News"
                Add-AlertLogEntry -Alert ([PSCustomObject]@{ Ticker = $h.Sym; Condition = "NEWS"; Note = $h.Keyword }) -Text ([string]$h.Item.Title) -Push $push
            }
            if ($hits.Count -gt 3) { Write-WidgetLog ("News keywords: {0} hits, notified the newest 3" -f $hits.Count) }
        }
    }
    if ($newest -gt $last) {
        $script:Config.NewsKeywordLastAt = $newest.ToString("o", [System.Globalization.CultureInfo]::InvariantCulture)
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
    }
}

# ---- reading ----
function Get-SelectedNews {
    if ($dgvNews.SelectedRows.Count -gt 0) { return $dgvNews.SelectedRows[0].Tag }
    return $null
}

function Get-NewsItemKeys {
    param($Item)
    $k = @(@($Item.Keys) | Where-Object { $_ })
    if ($k.Count -eq 0) { $k = @([string]$Item.Key) }
    return @($k)
}

function Set-NewsReadMark {
    param($Item, [bool]$Read)
    if ($null -eq $Item) { return }
    foreach ($k in @(Get-NewsItemKeys $Item)) {
        if ($Read) { [void]$script:NewsRead.Add($k); [void]$script:NewsUnread.Remove($k) }
        else { [void]$script:NewsUnread.Add($k); [void]$script:NewsRead.Remove($k) }
    }
    Save-NewsState
    Update-NewsViews
}

function Test-NewsSaved {
    param($Item)
    $keys = @(Get-NewsItemKeys $Item)
    return (@($script:NewsSaved | Where-Object { $keys -contains [string]$_.Key }).Count -gt 0)
}

function Switch-NewsSaved {
    param($Item)
    if ($null -eq $Item) { return }
    if (Test-NewsSaved $Item) {
        $keys = @(Get-NewsItemKeys $Item)
        $script:NewsSaved = @($script:NewsSaved | Where-Object { $keys -notcontains [string]$_.Key })
        Set-TransientStatus (Tr "Nicht mehr gemerkt") 2
    } else {
        $copy = ConvertFrom-NewsRecord (ConvertTo-NewsRecord $Item)
        $script:NewsSaved = @(@($copy) + @($script:NewsSaved) | Select-Object -First 500)
        Set-TransientStatus (Tr "Gemerkt") 2
    }
    Save-NewsState
    Update-NewsViews
}

function Open-NewsItem {
    param($Item)
    if ($null -eq $Item -or -not $Item.Link) { return }
    Open-Link ([string]$Item.Link)
    Set-NewsReadMark -Item $Item -Read $true
}

function Move-NewsSelection {
    param([int]$Step)
    $n = $dgvNews.Rows.Count
    if ($n -eq 0) { return }
    $i = if ($dgvNews.SelectedRows.Count -gt 0) { $dgvNews.SelectedRows[0].Index + $Step } else { 0 }
    $i = [math]::Max(0, [math]::Min($n - 1, $i))
    $dgvNews.ClearSelection()
    $dgvNews.Rows[$i].Selected = $true
    $dgvNews.CurrentCell = $dgvNews.Rows[$i].Cells["Title"]
}

function Export-SavedNews {
    if (@($script:NewsSaved).Count -eq 0) { Set-TransientStatus (Tr "Noch nichts gemerkt") 3; return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "CSV (*.csv)|*.csv"
    $sfd.FileName = "TerminalWidget_News_{0}.csv" -f (Get-Date -Format "yyyyMMdd")
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    try {
        [System.IO.File]::WriteAllText($sfd.FileName, (ConvertTo-NewsCsv $script:NewsSaved), (New-Object System.Text.UTF8Encoding($true)))
        Set-TransientStatus ("{0}: {1}" -f (Tr "Exportiert"), $sfd.FileName) 5
    } catch {
        Write-WidgetLog "News export failed: $($_.Exception.Message)" "ERROR"
        Show-InfoBox -Text "Export fehlgeschlagen: $($_.Exception.Message)" -Title "News"
    }
}

# ---- news tab controls: Quellen, Gemerkt, search ----
$lblNewsTitle.Width = S 154
$lblNewsTitle.Text = "Nachrichten"

$btnNewsSources = New-Object System.Windows.Forms.Button
$btnNewsSources.SetBounds((S 168), (S 6), (S 84), (S 24))
Style-FlatButton -Btn $btnNewsSources -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnNewsSources.Text = "Quellen " + [string][char]0x25BE
$btnNewsSources.Anchor = $aNT -bor $aNL
$viewNews.Controls.Add($btnNewsSources)
Set-Tip $btnNewsSources "Quellen ein- und ausblenden, nur eine Quelle oder Gruppe zeigen, Feeds verwalten"

$btnNewsSaved = New-Object System.Windows.Forms.Button
$btnNewsSaved.SetBounds((S 258), (S 6), (S 76), (S 24))
Style-FlatButton -Btn $btnNewsSaved -BgColor $script:Pal.Input -FgColor $script:Pal.Accent -BorderColor $script:Pal.Border
$btnNewsSaved.Text = "Gemerkt"
$btnNewsSaved.Anchor = $aNT -bor $aNL
$viewNews.Controls.Add($btnNewsSaved)
Set-Tip $btnNewsSaved "Nur gemerkte Meldungen zeigen (S merkt die markierte Meldung)"

$txtNewsSearch = New-Object System.Windows.Forms.TextBox
$txtNewsSearch.SetBounds((S 342), (S 7), (S 120), (S 23))
$txtNewsSearch.BackColor = $script:Pal.Input; $txtNewsSearch.ForeColor = $script:Pal.Text
$txtNewsSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtNewsSearch.Font = $fontUi
$txtNewsSearch.Anchor = $aNT -bor $aNL -bor $aNR
$viewNews.Controls.Add($txtNewsSearch)
Set-Tip $txtNewsSearch "Suche in Titel, Kurztext, Quelle und Ticker (Strg+F, Esc leert)"

$txtNewsSearch.Add_TextChanged({ $script:NewsQuery = $txtNewsSearch.Text.Trim(); Refresh-NewsGrid })
$txtNewsSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Text = ""; [void]$dgvNews.Focus(); $e.Handled = $true; $e.SuppressKeyPress = $true }
    elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { [void]$dgvNews.Focus(); $e.Handled = $true; $e.SuppressKeyPress = $true }
})
$btnNewsSaved.Add_Click({
    $script:NewsSavedMode = -not $script:NewsSavedMode
    $btnNewsSaved.Text = if ($script:NewsSavedMode) { [string][char]0x2605 + " Gemerkt" } else { "Gemerkt" }
    Refresh-NewsGrid
})

function Set-NewsViewHidden {
    param([string[]]$Ids)
    $script:Config.NewsViewHidden = @(@($Ids) | Where-Object { $_ } | Sort-Object -Unique)
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-NewsViews
}

function Get-NewsSourceChoices {
    # switched-on sources for the menu: @(@{ Id; Label; Group })
    $out = @()
    if ([bool]$script:Config.NewsYahoo) { $out += [PSCustomObject]@{ Id = "yahoo"; Label = "Yahoo Finance"; Group = "" } }
    foreach ($s in @($script:Config.NewsSources)) { if ($null -ne $s -and $s.On) { $out += [PSCustomObject]@{ Id = [string]$s.Id; Label = (Get-NewsSourceLabel $s); Group = [string]$s.Group } } }
    return @($out)
}

$script:NewsSourceMenu = New-Object System.Windows.Forms.ContextMenuStrip
$script:NewsMenuStay = $false
$script:NewsSourceMenu.Add_Closing({
    param($sender, $e)
    # ticking sources keeps the menu open
    if ($script:NewsMenuStay -and $e.CloseReason -eq [System.Windows.Forms.ToolStripDropDownCloseReason]::ItemClicked) { $e.Cancel = $true }
    $script:NewsMenuStay = $false
})

function Build-NewsSourceMenu {
    $menu = $script:NewsSourceMenu
    $menu.Items.Clear()
    $choices = @(Get-NewsSourceChoices)
    $hidden = @($script:Config.NewsViewHidden)
    foreach ($c in $choices) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($c.Label.Replace("&", "&&"))
        $mi.Checked = ($hidden -notcontains $c.Id)
        $mi.Tag = $c.Id
        $mi.Add_MouseDown({ $script:NewsMenuStay = $true })
        $mi.Add_Click({
            param($sender, $e)
            $id = [string]$sender.Tag
            $h = @($script:Config.NewsViewHidden)
            if ($sender.Checked) { $sender.Checked = $false; Set-NewsViewHidden (@($h) + $id) }
            else { $sender.Checked = $true; Set-NewsViewHidden @($h | Where-Object { $_ -ne $id }) }
        })
        [void]$menu.Items.Add($mi)
    }
    if ($choices.Count -eq 0) { $none = $menu.Items.Add((Tr "Keine Quelle eingeschaltet")); $none.Enabled = $false }
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $all = $menu.Items.Add((Tr "Alle zeigen")); $all.Add_Click({ Set-NewsViewHidden @() })
    $no = $menu.Items.Add((Tr "Keine zeigen")); $no.Add_Click({ Set-NewsViewHidden @(Get-NewsSourceChoices | ForEach-Object { $_.Id }) })
    if ($choices.Count -gt 1) {
        $only = New-Object System.Windows.Forms.ToolStripMenuItem((Tr "Nur diese"))
        foreach ($c in $choices) {
            $mi = New-Object System.Windows.Forms.ToolStripMenuItem($c.Label.Replace("&", "&&"))
            $mi.Tag = $c.Id
            $mi.Add_Click({ param($sender, $e) $id = [string]$sender.Tag; Set-NewsViewHidden @(Get-NewsSourceChoices | ForEach-Object { $_.Id } | Where-Object { $_ -ne $id }) })
            [void]$only.DropDownItems.Add($mi)
        }
        [void]$menu.Items.Add($only)
    }
    $groups = @($choices | ForEach-Object { $_.Group } | Where-Object { $_ } | Sort-Object -Unique)
    if ($groups.Count -gt 0) {
        $gm = New-Object System.Windows.Forms.ToolStripMenuItem((Tr "Nur Gruppe"))
        foreach ($g in $groups) {
            $mi = New-Object System.Windows.Forms.ToolStripMenuItem($g.Replace("&", "&&"))
            $mi.Tag = $g
            $mi.Add_Click({ param($sender, $e) $gn = [string]$sender.Tag; Set-NewsViewHidden @(Get-NewsSourceChoices | Where-Object { $_.Group -ne $gn } | ForEach-Object { $_.Id }) })
            [void]$gm.DropDownItems.Add($mi)
        }
        [void]$menu.Items.Add($gm)
    }
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $mg = $menu.Items.Add((Tr "Feeds verwalten ...")); $mg.Add_Click({ Show-FeedManager })
}
$btnNewsSources.Add_Click({
    Build-NewsSourceMenu
    $script:NewsSourceMenu.Show($btnNewsSources, 0, $btnNewsSources.Height)
})

# ---- preview pane ----
$pnlNewsPreview = New-Object System.Windows.Forms.Panel
$pnlNewsPreview.BackColor = $script:Pal.Card
$pnlNewsPreview.Visible = $false
$viewNews.Controls.Add($pnlNewsPreview)
$lblNpTitle = New-Object System.Windows.Forms.Label
$lblNpTitle.Font = $fontUiBold; $lblNpTitle.AutoEllipsis = $true; $lblNpTitle.UseMnemonic = $false
$lblNpMeta = New-Object System.Windows.Forms.Label
$lblNpMeta.Font = $fontUi; $lblNpMeta.AutoEllipsis = $true; $lblNpMeta.UseMnemonic = $false
$lblNpText = New-Object System.Windows.Forms.Label
$lblNpText.Font = $fontUi; $lblNpText.AutoEllipsis = $true; $lblNpText.UseMnemonic = $false
$picNews = New-Object System.Windows.Forms.PictureBox
$picNews.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picNews.Add_LoadCompleted({ param($sender, $e) if ($null -ne $e.Error) { $sender.Visible = $false; Set-NewsPreviewBounds } })
foreach ($c in @($lblNpTitle, $lblNpMeta, $lblNpText, $picNews)) { $pnlNewsPreview.Controls.Add($c) }

function Set-NewsPreviewBounds {
    $w = $pnlNewsPreview.Width; $h = $pnlNewsPreview.Height
    $pw = if ($picNews.Visible) { [math]::Min((S 150), [int]($w / 3)) } else { 0 }
    $tw = [math]::Max(10, $w - $pw - (S 12))
    $lblNpTitle.SetBounds((S 4), (S 4), $tw, (S 20))
    $lblNpMeta.SetBounds((S 4), (S 24), $tw, (S 18))
    $lblNpText.SetBounds((S 4), (S 44), $tw, [math]::Max(0, $h - (S 48)))
    if ($pw -gt 0) { $picNews.SetBounds(($w - $pw - (S 4)), (S 4), $pw, [math]::Max(10, $h - (S 8))) }
}

function Set-NewsLayout {
    # the preview takes the lower part of the list when it is switched on and there is room
    $ph = if ([bool]$script:Config.NewsPreview -and $viewNews.Height -ge (S 230)) { S 108 } else { 0 }
    $gridH = [math]::Max((S 40), $viewNews.ClientSize.Height - (S 54) - (S 8) - $ph)
    if ($dgvNews.Height -ne $gridH) { $dgvNews.Height = $gridH }
    $pnlNewsPreview.Visible = ($ph -gt 0)
    if ($ph -gt 0) {
        $pnlNewsPreview.SetBounds($dgvNews.Left, ($dgvNews.Top + $gridH + (S 4)), $dgvNews.Width, ($ph - (S 4)))
        Set-NewsPreviewBounds
    }
}
$viewNews.Add_SizeChanged({ Set-NewsLayout })

function Update-NewsPreview {
    if (-not $pnlNewsPreview.Visible) { return }
    $n = Get-SelectedNews
    $lblNpTitle.ForeColor = $script:Pal.Text; $lblNpMeta.ForeColor = $script:Pal.Muted; $lblNpText.ForeColor = $script:Pal.Text
    $pnlNewsPreview.BackColor = $script:Pal.Card
    if ($null -eq $n) {
        $lblNpTitle.Text = ""; $lblNpMeta.Text = ""; $lblNpText.Text = Tr "Eine Meldung wählen, um die Vorschau zu sehen."
        $picNews.Visible = $false; $script:NewsPreviewKey = ""
        Set-NewsPreviewBounds
        return
    }
    $lblNpTitle.Text = [string]$n.Title
    $meta = @()
    if ([DateTime]$n.Time -gt [DateTime]::MinValue) { $meta += ([DateTime]$n.Time).ToString("dd.MM.yyyy HH:mm") }
    if ($n.Publisher) { $meta += [string]$n.Publisher }
    if (@($n.Syms).Count -gt 0) { $meta += (@($n.Syms) -join " ") }
    $lblNpMeta.Text = $meta -join "  |  "
    $lblNpText.Text = if ($n.Summary) { [string]$n.Summary } else { Tr "Die Quelle schickt keinen Kurztext." }
    if ($script:NewsPreviewKey -ne [string]$n.Key) {
        $script:NewsPreviewKey = [string]$n.Key
        $picNews.Visible = $false
        try { $picNews.CancelAsync(); $picNews.Image = $null } catch { }
        # pictures are only requested while the preview is open (and can be switched off)
        if ([bool]$script:Config.NewsImages -and [string]$n.Image -match '^https://' -and -not $script:SmokeMode) {
            $picNews.Visible = $true
            try { $picNews.LoadAsync([string]$n.Image) } catch { $picNews.Visible = $false }
        }
    }
    Set-NewsPreviewBounds
}
$dgvNews.Add_SelectionChanged({ Update-NewsPreview })

function Set-NewsPreview {
    param([bool]$On)
    $script:Config.NewsPreview = $On
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    $script:NewsPreviewKey = ""
    Set-NewsLayout
    Update-NewsPreview
}

function Invoke-NewsKey {
    # keys while the news list has the focus; $true = handled
    param([System.Windows.Forms.KeyEventArgs]$E)
    switch ($E.KeyCode) {
        ([System.Windows.Forms.Keys]::J) { Move-NewsSelection 1; return $true }
        ([System.Windows.Forms.Keys]::K) { Move-NewsSelection -1; return $true }
        ([System.Windows.Forms.Keys]::O) { Open-NewsItem (Get-SelectedNews); return $true }
        ([System.Windows.Forms.Keys]::S) { Switch-NewsSaved (Get-SelectedNews); return $true }
        ([System.Windows.Forms.Keys]::M) {
            $n = Get-SelectedNews
            if ($null -ne $n) { Set-NewsReadMark -Item $n -Read ([bool](Test-NewsUnread -Item $n -Since $script:NewsBoldSince -ReadKeys $script:NewsRead -UnreadKeys $script:NewsUnread)) }
            return $true
        }
        ([System.Windows.Forms.Keys]::V) { Set-NewsPreview (-not [bool]$script:Config.NewsPreview); return $true }
    }
    return $false
}

function Apply-NewsTheme {
    $p = $script:Pal
    foreach ($b in @($btnNewsSources, $btnNewsSaved)) { Style-FlatButton -Btn $b -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border }
    $txtNewsSearch.BackColor = $p.Input; $txtNewsSearch.ForeColor = $p.Text
    $pnlNewsPreview.BackColor = $p.Card
    $script:NewsPreviewKey = ""
    Update-NewsPreview
}

# ---- feed manager ----
function Get-FeedStatusText {
    param([string]$Id)
    $s = $script:FeedStatus[$Id]
    if ($null -eq $s) { return "noch nicht geladen" }
    if ($s.Error) {
        $t = [string]$s.Error
        if ($null -ne $s.LastOk) { $t += " (zuletzt ok {0:HH:mm})" -f $s.LastOk }
        return $t
    }
    if ($null -eq $s.LastOk) { return "-" }
    return "ok {0:HH:mm}, {1} Meldungen" -f $s.LastOk, $s.Count
}

function Add-FeedManagerRow {
    param($Grid, $Source)
    $i = $Grid.Rows.Add([bool]$Source.On, [string]$Source.Name, [string]$Source.Url, [string]$Source.Group, [string]$Source.Ticker,
        $(if ([int]$Source.Minutes -gt 0) { [string]$Source.Minutes } else { "" }), $(if ([int]$Source.MaxAgeDays -gt 0) { [string]$Source.MaxAgeDays } else { "" }),
        [bool]$Source.Notify, $(if ($Source.Id) { Get-FeedStatusText ([string]$Source.Id) } else { "neu" }))
    $Grid.Rows[$i].Tag = [string]$Source.Id
    return $i
}

function Get-FeedManagerRows {
    # grid -> raw source objects (without the fixed Yahoo row)
    param($Grid)
    $out = @()
    foreach ($r in $Grid.Rows) {
        if ([string]$r.Tag -eq "yahoo") { continue }
        $out += [PSCustomObject]@{
            Id = [string]$r.Tag; On = [bool]$r.Cells["On"].Value; Name = [string]$r.Cells["Name"].Value; Url = [string]$r.Cells["Url"].Value
            Group = [string]$r.Cells["Group"].Value; Ticker = [string]$r.Cells["Ticker"].Value; Minutes = [string]$r.Cells["Minutes"].Value
            MaxAgeDays = [string]$r.Cells["Age"].Value; Notify = [bool]$r.Cells["Notify"].Value
        }
    }
    return @($out)
}

function Start-FeedTest {
    # loads one feed once and writes the result into its status cell
    param($Grid, $Row)
    if ($null -eq $Row -or [string]$Row.Tag -eq "yahoo") { return }
    $src = ConvertTo-NewsSource ([PSCustomObject]@{ Url = [string]$Row.Cells["Url"].Value; Ticker = [string]$Row.Cells["Ticker"].Value })
    if ($null -eq $src) { $Row.Cells["Status"].Value = Tr "Adresse muss mit http:// oder https:// beginnen"; return }
    $act = ([string]$script:Config.ActiveTicker).ToUpperInvariant()
    $req = @(Get-NewsFeedRequests -Sources @($src) -Symbols @($act) -Names (Get-NewsNames @($act)))[0]
    $url = [string]$req.Url
    $script:WorkerShared.Cond.Remove($url)
    $Row.Cells["Status"].Value = Tr "teste ..."
    Start-FetchJob -Urls @($url) -Context @{ Grid = $Grid; Row = $Row; Url = $url } -OnComplete {
        param($Box, $Ctx)
        if ($Ctx.Grid.IsDisposed -or $Ctx.Row.Index -lt 0) { return }
        $m = $null
        if ($null -ne $Box.Meta) { $m = $Box.Meta[$Ctx.Url] }
        $body = $Box.Results[$Ctx.Url]
        $entries = @()
        if ($body -is [string]) { $entries = @(ConvertFrom-RssFeed -Text $body) }
        $text = if ($entries.Count -gt 0) {
            if (-not [string]$Ctx.Row.Cells["Name"].Value -and $entries[0].Publisher) { $Ctx.Row.Cells["Name"].Value = [string]$entries[0].Publisher }
            "Test ok: {0} Meldungen, z. B. {1}" -f $entries.Count, $entries[0].Title
        } elseif ($null -ne $m -and [int]$m.Code -ge 400) { "Test: HTTP $($m.Code)" }
        elseif ($null -eq $m -or [int]$m.Code -eq 0) { "Test: keine Antwort" }
        else { "Test: kein RSS- oder Atom-Feed (oder leer) - 'Adresse finden' versuchen" }
        $Ctx.Row.Cells["Status"].Value = $text
        $Ctx.Row.Cells["Status"].ToolTipText = $text
    }
}

function Start-FeedDiscovery {
    param($Grid, $Info, [string]$PageUrl)
    $u = ([string]$PageUrl).Trim()
    if ($u -and $u -notmatch '^[a-z]+://') { $u = "https://" + $u }
    if ($u -notmatch '^https?://[^\s]+$') { $Info.Text = Tr "Keine gültige Adresse."; return }
    $Info.Text = Tr "suche Feeds ..."
    Start-FetchJob -Urls @($u) -Context @{ Grid = $Grid; Info = $Info; Url = $u } -OnComplete {
        param($Box, $Ctx)
        if ($Ctx.Grid.IsDisposed) { return }
        $body = $Box.Results[$Ctx.Url]
        $found = @()
        if ($body -is [string]) {
            if (@(ConvertFrom-RssFeed -Text $body).Count -gt 0) { $found = @($Ctx.Url) }
            else { $found = @(Find-FeedLinks -Html $body -BaseUrl $Ctx.Url) }
        }
        $have = @(Get-FeedManagerRows $Ctx.Grid | ForEach-Object { $_.Url })
        $added = 0
        foreach ($f in @($found | Where-Object { $have -notcontains $_ } | Select-Object -First 10)) {
            # found feeds start switched off: the user ticks the ones wanted
            [void](Add-FeedManagerRow -Grid $Ctx.Grid -Source ([PSCustomObject]@{ Id = ""; On = $false; Name = ""; Url = $f; Group = ""; Ticker = ""; Minutes = 0; MaxAgeDays = 0; Notify = $true }))
            $added++
        }
        $Ctx.Info.Text = if ($added -gt 0) { "{0} Feed(s) gefunden - zum Einschalten anhaken." -f $added }
                         elseif ($found.Count -gt 0) { "Die gefundenen Feeds stehen schon in der Liste." }
                         else { "Auf dieser Seite ist kein Feed angegeben (oder sie ist nicht erreichbar)." }
    }
}

function Set-NewsSources {
    # saves the list from the manager and loads what changed
    param($Sources, [bool]$Yahoo, [bool]$YahooNotify, [string]$Aliases)
    $script:Config.NewsSources = @(ConvertTo-NewsSourceList $Sources)
    $script:Config.NewsYahoo = $Yahoo
    $script:Config.NewsYahooNotify = $YahooNotify
    $script:Config.NewsAliases = $Aliases.Trim()
    $ids = @(@($script:Config.NewsSources) | ForEach-Object { $_.Id }) + "yahoo"
    $script:Config.NewsViewHidden = @(@($script:Config.NewsViewHidden) | Where-Object { $ids -contains $_ })
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    # everything is read again with the new options (also feeds that answered "not modified")
    $script:WorkerShared.Cond.Clear()
    $script:NewsLastRun = @{}
    $script:NextNewsLoad = Get-Date
    Update-NewsViews
}

function Show-FeedManager {
    $p = $script:Pal
    $d = New-DialogForm -Title "News-Feeds verwalten" -W (S 980) -H (S 520) -Key "feeds"
    $d.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $d.MinimumSize = New-Object System.Drawing.Size((S 760), (S 420))
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right
    $W = $d.ClientSize.Width; $H = $d.ClientSize.Height

    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds((S 12), (S 12), ($W - (S 24)), ($H - (S 204)))
    $g.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Style-DataGrid -Grid $g
    $g.ReadOnly = $false
    $g.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
    $g.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
    $g.MultiSelect = $false
    $g.AllowUserToAddRows = $false
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::None
    $g.ShowCellToolTips = $true
    $addCol = {
        param([string]$Name, [string]$Head, [int]$Width, [bool]$Check, [string]$Tip)
        $col = if ($Check) { New-Object System.Windows.Forms.DataGridViewCheckBoxColumn } else { New-Object System.Windows.Forms.DataGridViewTextBoxColumn }
        $col.Name = $Name; $col.HeaderText = $Head; $col.Width = S $Width; $col.ToolTipText = $Tip
        $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
        [void]$g.Columns.Add($col)
    }
    & $addCol "On" "An" 34 $true "Nur eingeschaltete Quellen werden abgefragt und angezeigt"
    & $addCol "Name" "Name" 130 $false "Leer = Titel des Feeds"
    & $addCol "Url" "Adresse" 270 $false "RSS oder Atom. {ticker} oder {name} = eine Abfrage je Ticker (höchstens 15)"
    & $addCol "Group" "Gruppe" 80 $false "z. B. Österreich, Firma, Markt - im Menü Quellen: Nur Gruppe"
    & $addCol "Ticker" "Ticker" 70 $false "Feste Zuordnung. Bei {ticker}/{name}: für welche Ticker (mit Komma), leer = Depot + Watchlist"
    & $addCol "Minutes" "Min." 40 $false "Eigenes Abfrage-Intervall in Minuten (ab 5), leer = Einstellung"
    & $addCol "Age" "Tage" 40 $false "Älteste Meldung in Tagen, leer = 14"
    & $addCol "Notify" "Hinweis" 52 $true "Darf Stichwort-Hinweise auslösen"
    & $addCol "Status" "Status" 200 $false "Ergebnis der letzten Abfrage oder des Tests"
    $g.Columns["Status"].ReadOnly = $true
    $g.Columns["Status"].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::Fill
    $g.Columns["Status"].MinimumWidth = S 120
    $d.Controls.Add($g)
    $y0 = $g.Rows.Add([bool]$script:Config.NewsYahoo, "Yahoo Finance", "(eingebaut: Meldungen je Ticker)", "", "", "", "", [bool]$script:Config.NewsYahooNotify, (Get-FeedStatusText "yahoo"))
    $g.Rows[$y0].Tag = "yahoo"
    foreach ($c in @("Name", "Url", "Group", "Ticker", "Minutes", "Age")) { $g.Rows[$y0].Cells[$c].ReadOnly = $true; $g.Rows[$y0].Cells[$c].Style.ForeColor = $p.Muted }
    foreach ($s in @($script:Config.NewsSources)) { if ($null -ne $s) { [void](Add-FeedManagerRow -Grid $g -Source $s) } }

    $info = New-Object System.Windows.Forms.Label
    $info.SetBounds((S 12), ($H - (S 186)), ($W - (S 24)), (S 18)); $info.Anchor = $aB -bor $aL -bor $aR
    $info.ForeColor = $p.Muted; $info.AutoEllipsis = $true
    $info.Text = "Adresse mit {ticker} oder {name} = Vorlage, je Ticker eine Abfrage. Änderungen gelten nach Speichern."
    $d.Controls.Add($info)

    $btn = {
        param([string]$Text, [int]$X, [int]$Width, [int]$Y, [string]$Tip)
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds((S $X), $Y, (S $Width), (S 26)); $b.Text = $Text; $b.Anchor = $aB -bor $aL
        Style-FlatButton -Btn $b -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
        if ($Tip) { Set-Tip $b $Tip }
        $d.Controls.Add($b)
        return $b
    }
    $yb = $H - (S 162)
    $bNew = & $btn "Neu" 12 60 $yb "Leere Zeile für eine neue Adresse"
    $bDel = & $btn "Entfernen" 78 84 $yb "Markierten Feed aus der Liste nehmen"
    $bAll = & $btn "Alle an" 168 70 $yb "Alle Quellen einschalten"
    $bNone = & $btn "Alle aus" 244 70 $yb "Alle Quellen ausschalten (Adressen bleiben)"
    $bTest = & $btn "Testen" 320 70 $yb "Markierten Feed jetzt einmal abrufen"
    $bFind = & $btn "Adresse finden ..." 396 128 $yb "Feeds auf einer Internetseite suchen"
    $bImp = & $btn "OPML laden ..." 530 108 $yb "Feed-Liste aus einer OPML-Datei dazuladen"
    $bExp = & $btn "OPML speichern ..." 644 128 $yb "Feed-Liste als OPML-Datei sichern"

    $la = New-Object System.Windows.Forms.Label
    $la.SetBounds((S 12), ($H - (S 128)), ($W - (S 24)), (S 18)); $la.Anchor = $aB -bor $aL -bor $aR
    $la.Text = "Eigene Namen je Ticker (eine Zeile je Ticker, z. B.  ABBN.SW = ABB, Asea Brown Boveri)"
    $d.Controls.Add($la)
    $ta = New-Object System.Windows.Forms.TextBox
    $ta.Multiline = $true; $ta.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $ta.SetBounds((S 12), ($H - (S 108)), ($W - (S 24)), (S 62)); $ta.Anchor = $aB -bor $aL -bor $aR
    $ta.BackColor = $p.Input; $ta.ForeColor = $p.Text; $ta.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $ta.Text = (([string]$script:Config.NewsAliases) -replace "`r?`n", "`r`n")
    $d.Controls.Add($ta)

    $ok = New-Object System.Windows.Forms.Button
    $ok.SetBounds(($W - (S 212)), ($H - (S 36)), (S 96), (S 28)); $ok.Text = "Speichern"; $ok.Anchor = $aB -bor $aR
    Style-FlatButton -Btn $ok -BgColor $p.Accent -FgColor $p.OnAccent -BorderColor $p.Accent
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ca = New-Object System.Windows.Forms.Button
    $ca.SetBounds(($W - (S 108)), ($H - (S 36)), (S 96), (S 28)); $ca.Text = "Abbrechen"; $ca.Anchor = $aB -bor $aR
    Style-FlatButton -Btn $ca -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $ca.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $d.Controls.Add($ok); $d.Controls.Add($ca)
    $d.CancelButton = $ca

    # handlers read their controls from here (script blocks outlive local variables)
    $script:FeedDlg = @{ Dlg = $d; Grid = $g; Info = $info }
    $bNew.Add_Click({
        $gr = $script:FeedDlg.Grid
        $i = Add-FeedManagerRow -Grid $gr -Source ([PSCustomObject]@{ Id = ""; On = $true; Name = ""; Url = "https://"; Group = ""; Ticker = ""; Minutes = 0; MaxAgeDays = 0; Notify = $true })
        $gr.CurrentCell = $gr.Rows[$i].Cells["Url"]
        [void]$gr.Focus()
    })
    $bDel.Add_Click({
        $gr = $script:FeedDlg.Grid
        $r = $gr.CurrentRow
        if ($null -eq $r -or [string]$r.Tag -eq "yahoo") { $script:FeedDlg.Info.Text = Tr "Yahoo Finance lässt sich nur ausschalten, nicht entfernen."; return }
        [void]$gr.EndEdit()
        $gr.Rows.Remove($r)
    })
    $bAll.Add_Click({ $gr = $script:FeedDlg.Grid; [void]$gr.EndEdit(); $gr.CurrentCell = $null; foreach ($r in $gr.Rows) { $r.Cells["On"].Value = $true } })
    $bNone.Add_Click({ $gr = $script:FeedDlg.Grid; [void]$gr.EndEdit(); $gr.CurrentCell = $null; foreach ($r in $gr.Rows) { $r.Cells["On"].Value = $false } })
    $bTest.Add_Click({ $gr = $script:FeedDlg.Grid; [void]$gr.EndEdit(); Start-FeedTest -Grid $gr -Row $gr.CurrentRow })
    $bFind.Add_Click({
        $u = Read-TextInput -Title "Feed-Adresse finden" -Prompt "Adresse der Internetseite:" -Value ""
        if ($null -ne $u) { Start-FeedDiscovery -Grid $script:FeedDlg.Grid -Info $script:FeedDlg.Info -PageUrl $u }
    })
    $bImp.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "OPML (*.opml;*.xml)|*.opml;*.xml|Alle Dateien (*.*)|*.*"
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            $gr = $script:FeedDlg.Grid
            $have = @(Get-FeedManagerRows $gr | ForEach-Object { $_.Url })
            $new = @(ConvertFrom-Opml (Read-TextFileGuess -Path $ofd.FileName) | Where-Object { $have -notcontains $_.Url })
            foreach ($s in $new) { $s.Id = ""; [void](Add-FeedManagerRow -Grid $gr -Source $s) }
            $script:FeedDlg.Info.Text = "{0} Feed(s) dazugeladen." -f $new.Count
        } catch { $script:FeedDlg.Info.Text = "OPML konnte nicht gelesen werden: $($_.Exception.Message)" }
    })
    $bExp.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "OPML (*.opml)|*.opml"
        $sfd.FileName = "TerminalWidget_Feeds.opml"
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        try {
            $gr = $script:FeedDlg.Grid; [void]$gr.EndEdit()
            [System.IO.File]::WriteAllText($sfd.FileName, (ConvertTo-Opml (ConvertTo-NewsSourceList (Get-FeedManagerRows $gr))), (New-Object System.Text.UTF8Encoding($false)))
            $script:FeedDlg.Info.Text = "Gespeichert. Die Datei enthält alle Adressen, auch persönliche."
        } catch { $script:FeedDlg.Info.Text = "Speichern fehlgeschlagen: $($_.Exception.Message)" }
    })
    $d.Add_FormClosing({
        param($sender, $e)
        if ($sender.DialogResult -ne [System.Windows.Forms.DialogResult]::OK) { return }
        [void]$script:FeedDlg.Grid.EndEdit()
        # a half-typed address must not disappear silently
        $bad = @(Get-FeedManagerRows $script:FeedDlg.Grid | Where-Object { $null -eq (ConvertTo-NewsSource $_) -and $_.Url.Trim() -notin @("", "https://", "http://") })
        if ($bad.Count -gt 0) {
            $script:FeedDlg.Info.Text = "Ungültige Adresse: " + $bad[0].Url
            $e.Cancel = $true; $sender.DialogResult = [System.Windows.Forms.DialogResult]::None
        }
    })
    $res = $d.ShowDialog($form)
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        $yr = @($g.Rows | Where-Object { [string]$_.Tag -eq "yahoo" })[0]
        Set-NewsSources -Sources (Get-FeedManagerRows $g) -Yahoo ([bool]$yr.Cells["On"].Value) -YahooNotify ([bool]$yr.Cells["Notify"].Value) -Aliases $ta.Text
        Set-TransientStatus "Feeds gespeichert" 3
    }
    $d.Dispose()
}

Import-NewsState
Update-NewsFilterCombo
Set-NewsLayout
Refresh-NewsGrid
