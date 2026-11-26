# TerminalWidget UI part 07 (Events) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

function Show-PushDialog {
    # Phone push setup; changes go straight into $script:Config (saved by the caller)
    param($Owner)
    $p = $script:Pal
    $cfg = $script:Config
    $dlg = New-DialogForm -Title "Handy-Push - $($script:AppTitle)" -W (S 520) -H (S 410)
    $y = S 12
    $mkLbl = {
        param([string]$T, [int]$Y)
        $l = New-Object System.Windows.Forms.Label
        $l.SetBounds((S 14), ($Y + (S 3)), (S 130), (S 18)); $l.Text = $T
        $dlg.Controls.Add($l)
        return $l
    }
    $mkTxt = {
        param([string]$V, [int]$Y, [int]$Wd)
        $t = New-Object System.Windows.Forms.TextBox
        $t.SetBounds((S 150), $Y, $Wd, (S 24))
        $t.BackColor = $p.Input; $t.ForeColor = $p.Text; $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $t.Font = $fontMono; $t.Text = $V
        $dlg.Controls.Add($t)
        return $t
    }
    $mkBtn = {
        param([string]$T, [int]$X, [int]$Y, [int]$Wd)
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds($X, $Y, $Wd, (S 25))
        Style-FlatButton -Btn $b -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
        $b.Text = $T
        $dlg.Controls.Add($b)
        return $b
    }
    $info = New-Object System.Windows.Forms.Label
    $info.SetBounds((S 14), $y, (S 492), (S 34)); $info.ForeColor = $p.Muted
    $info.Text = "Alarme (und auf Wunsch Quartalszahlen) zusätzlich aufs Handy. ntfy: App installieren und das Thema abonnieren. Telegram: Bot bei @BotFather anlegen."
    $dlg.Controls.Add($info)
    $y += S 40
    [void](& $mkLbl "Dienst" $y)
    $cbSvc = New-Object System.Windows.Forms.ComboBox
    $cbSvc.SetBounds((S 150), $y, (S 120), (S 24))
    $cbSvc.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbSvc.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cbSvc.BackColor = $p.Input; $cbSvc.ForeColor = $p.Text
    foreach ($s in @("Aus", "ntfy", "Telegram")) { [void]$cbSvc.Items.Add($s) }
    $cbSvc.SelectedIndex = [math]::Max(0, $cbSvc.Items.IndexOf([string]$cfg.PushService))
    $dlg.Controls.Add($cbSvc)
    Set-DynTip $cbSvc "" "PUSH"
    $y += S 34
    $lSrv = & $mkLbl "ntfy-Server" $y
    $tSrv = & $mkTxt ([string]$cfg.PushServer) $y (S 250)
    Set-DynTip $tSrv "Standard: https://ntfy.sh - oder ein eigener ntfy-Server"
    $y += S 30
    $lTop = & $mkLbl "ntfy-Thema" $y
    $tTop = & $mkTxt ([string]$cfg.PushTopic) $y (S 250)
    $bRnd = & $mkBtn "Zufällig" (S 406) $y (S 100)
    Set-DynTip $tTop "Wie ein Passwort: wer das Thema kennt, liest mit. Erlaubt: Buchstaben, Ziffern, - und _" "PUSH"
    $y += S 34
    $lTok = & $mkLbl "Telegram-Token" $y
    $tTok = & $mkTxt "" $y (S 250)
    $tTok.UseSystemPasswordChar = $true
    $hasTok = [bool]([string]$cfg.PushTokenEnc)
    if ($hasTok) { $tTok.Text = "********" }
    Set-DynTip $tTok "Token von @BotFather (123456:ABC...). Wird verschlüsselt gespeichert (nur dein Windows-Konto kann ihn lesen)." "PUSH"
    $y += S 30
    $lChat = & $mkLbl "Telegram-Chat-ID" $y
    $tChat = & $mkTxt ([string]$cfg.PushChatId) $y (S 140)
    $bChat = & $mkBtn "Chat-ID holen" (S 296) $y (S 120)
    Set-DynTip $bChat "Erst dem Bot in Telegram eine Nachricht schreiben (z. B. /start), dann hier klicken"
    $y += S 36
    $chkA = New-Object System.Windows.Forms.CheckBox
    $chkA.SetBounds((S 14), $y, (S 240), (S 22)); $chkA.Text = "Bei Alarmen"; $chkA.Checked = [bool]$cfg.PushAlerts
    $chkA.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dlg.Controls.Add($chkA)
    $chkE = New-Object System.Windows.Forms.CheckBox
    $chkE.SetBounds((S 260), $y, (S 246), (S 22)); $chkE.Text = "Quartalszahlen (Vortag)"; $chkE.Checked = [bool]$cfg.PushEarnings
    $chkE.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dlg.Controls.Add($chkE)
    Set-DynTip $chkE "" "EARNINGS"
    $y += S 34
    $bTest = & $mkBtn "Test senden" (S 14) $y (S 120)
    $lRes = New-Object System.Windows.Forms.Label
    $lRes.SetBounds((S 142), ($y + (S 4)), (S 364), (S 40)); $lRes.ForeColor = $p.Muted
    $dlg.Controls.Add($lRes)
    $y += S 52
    $ok = & $mkBtn "OK" (S 312) $y (S 94)
    Style-FlatButton -Btn $ok -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $cancel = & $mkBtn "Abbrechen" (S 412) $y (S 94)
    Style-FlatButton -Btn $cancel -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.CancelButton = $cancel
    $dlg.ClientSize = New-Object System.Drawing.Size((S 520), ($y + (S 40)))

    $script:PushCtl = @{
        Dlg = $dlg; Svc = $cbSvc; Srv = $tSrv; Top = $tTop; Tok = $tTok; Chat = $tChat; Res = $lRes; A = $chkA; E = $chkE
        HasTok = $hasTok; Rows = @(@($lSrv, $tSrv), @($lTop, $tTop, $bRnd), @($lTok, $tTok), @($lChat, $tChat, $bChat))
    }
    $getToken = {
        $pc = $script:PushCtl
        $t = ([string]$pc.Tok.Text).Trim()
        if ($pc.HasTok -and $t -eq "********") { return (Unprotect-Secret ([string]$script:Config.PushTokenEnc)) }
        return $t
    }
    $script:PushCtl.GetToken = $getToken
    $script:PushCtl.Show = {
        $pc = $script:PushCtl
        $svc = [string]$pc.Svc.SelectedItem
        for ($i = 0; $i -lt $pc.Rows.Count; $i++) {
            $on = if ($i -lt 2) { $svc -eq "ntfy" } else { $svc -eq "Telegram" }
            foreach ($c in $pc.Rows[$i]) { $c.Enabled = $on }
        }
    }
    & $script:PushCtl.Show
    $cbSvc.Add_SelectedIndexChanged({ & $script:PushCtl.Show })
    $bRnd.Add_Click({ $script:PushCtl.Top.Text = New-RandomTopic })
    $tTok.Add_Enter({ param($sender, $e) if ($script:PushCtl.HasTok -and $sender.Text -eq "********") { $sender.SelectAll() } })
    $bChat.Add_Click({
        $pc = $script:PushCtl
        $tok = & $pc.GetToken
        if ($tok -notmatch '^\d+:[A-Za-z0-9_-]+$') { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Bitte zuerst einen gültigen Bot-Token eintragen."; return }
        $u = "https://api.telegram.org/bot{0}/getUpdates" -f $tok
        $r = Invoke-ParallelFetch -Urls @($u) -TimeoutSec 8
        $id = Get-TelegramChatId $r[$u]
        if ($id) { $pc.Chat.Text = $id; $pc.Res.ForeColor = $colGreen; $pc.Res.Text = "Chat-ID gefunden: $id" }
        else { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Keine Nachricht gefunden. Schreib dem Bot in Telegram etwas (z. B. /start) und versuch es nochmal." }
    })
    $bTest.Add_Click({
        $pc = $script:PushCtl
        $tmp = [PSCustomObject]@{
            PushService = [string]$pc.Svc.SelectedItem; PushServer = $pc.Srv.Text.Trim(); PushTopic = $pc.Top.Text.Trim()
            PushTokenEnc = ""; PushTokenPlain = (& $pc.GetToken); PushChatId = $pc.Chat.Text.Trim()
        }
        $req = Get-PushRequest -Title "TerminalWidget" -Message ("Test vom PC ({0}) - Push funktioniert." -f (Get-Date).ToString("HH:mm")) -Cfg $tmp
        if ($null -eq $req) { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Einstellungen unvollständig (Dienst, Thema bzw. Token und Chat-ID)."; return }
        $pc.Res.ForeColor = $script:Pal.Muted; $pc.Res.Text = "Sende ..."
        $started = Send-PushRequest -Req $req -Desc "Test" -OnDone {
            param($Ok, $Info)
            if ($null -eq $script:PushCtl) { return }
            $script:PushCtl.Res.ForeColor = if ($Ok) { $colGreen } else { $colRed }
            $script:PushCtl.Res.Text = if ($Ok) { "Gesendet - kommt die Nachricht am Handy an?" } else { "Fehler: $Info" }
        }
        if (-not $started) { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Konnte nicht senden (Limit 10 pro Minute oder Fehler, siehe Log)." }
    })
    $ok.Add_Click({
        $pc = $script:PushCtl
        $svc = [string]$pc.Svc.SelectedItem
        $tok = & $pc.GetToken
        if ($svc -eq "ntfy" -and $pc.Top.Text.Trim() -notmatch '^[A-Za-z0-9_-]{1,64}$') { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Bitte ein Thema eintragen (Buchstaben, Ziffern, - und _), z. B. über 'Zufällig'."; return }
        if ($svc -eq "Telegram" -and ($tok -notmatch '^\d+:[A-Za-z0-9_-]+$' -or $pc.Chat.Text.Trim() -notmatch '^-?\d+$')) { $pc.Res.ForeColor = $colRed; $pc.Res.Text = "Bitte Bot-Token und Chat-ID eintragen."; return }
        $c = $script:Config
        $c.PushService = $svc
        $c.PushServer = if ($pc.Srv.Text.Trim()) { $pc.Srv.Text.Trim() } else { "https://ntfy.sh" }
        $c.PushTopic = $pc.Top.Text.Trim()
        $c.PushTokenEnc = if ($tok) { Protect-Secret $tok } else { "" }
        $c.PushChatId = $pc.Chat.Text.Trim()
        $c.PushAlerts = [bool]$pc.A.Checked
        $c.PushEarnings = [bool]$pc.E.Checked
        Save-JsonState -Path $script:ConfigPath -Data $c
        Write-WidgetLog "Push settings saved: $svc"
        $pc.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $pc.Dlg.Close()
    })
    $res = $dlg.ShowDialog($(if ($null -ne $Owner) { $Owner } else { $form }))
    $script:PushCtl = $null
    $dlg.Dispose()
    return ($res -eq [System.Windows.Forms.DialogResult]::OK)
}

# ------------------------------------------------------------------------------
# Earnings / dividend dates (v4.2): refreshed in the background for portfolio,
# watchlist and the active ticker; tray hint the day before quarterly figures
# ------------------------------------------------------------------------------
$script:NextEventsCheck = (Get-Date).AddSeconds(30)

function Get-EventSymbols {
    $set = New-Object System.Collections.Generic.HashSet[string]
    if ($script:Config.ActiveTicker) { [void]$set.Add(([string]$script:Config.ActiveTicker).ToUpper()) }
    foreach ($k in $script:Portfolio.Keys) { [void]$set.Add(([string]$k).ToUpper()) }
    foreach ($w in @($script:Config.Watchlist)) { if ($w) { [void]$set.Add(([string]$w).ToUpper()) } }
    return @($set | Where-Object { $_ -notmatch '^\^|=X$|-USD$|-EUR$' })
}

function Update-EventsIfStale {
    if ($script:IsClosing -or $script:ProfileJobRunning -or $script:WorkerShared.CrumbFailed) { return }
    $stale = @(Get-EventSymbols | Where-Object { Test-EventsStale -Entry $script:Events[$_] } | Select-Object -First 15)
    if ($stale.Count -eq 0) { return }
    Start-ProfileJob -Symbols $stale -EventsOnly $true -OnComplete {
        try { Update-AllUiViews } catch { }
        if ($null -ne $script:AnaCtl) { Update-AnalysisDividends }
        Check-EarningsNotifications
    }
}

function Check-EarningsNotifications {
    # v8.0: one balloon per company and date, with an adjustable lead time
    # (earnings and, if switched on, ex-dividend day)
    $eLead = if ([bool]$script:Config.NotifyEarnings) { [int]$script:Config.EarningsLeadDays } else { -1 }
    $xLead = [int]$script:Config.ExDivLeadDays
    if ($eLead -lt 0 -and $xLead -lt 0) { return }
    $changed = $false
    foreach ($d in @(Get-DueDateNotices -Events $script:Events -Symbols @($script:Portfolio.Keys) -EarningsLead $eLead -ExDivLead $xLead)) {
        $when = if ($d.Days -eq 0) { "Heute" } elseif ($d.Days -eq 1) { "Morgen" } else { "In {0} Tagen" -f $d.Days }
        $title = if ($d.Kind -eq "Earnings") { "Quartalszahlen: $($d.Ticker)" } else { "Ex-Dividende: $($d.Ticker)" }
        $msg = if ($d.Kind -eq "Earnings") { "{0} ({1}) - Kurs kann stark schwanken" -f $when, (Format-IsoDateDe $d.Date) } else { "{0} ({1}) - ab diesem Tag ohne Dividende gehandelt" -f $when, (Format-IsoDateDe $d.Date) }
        [void](Send-WidgetNotification -Title $title -Message $msg -Kind "Earnings")
        $script:Events[$d.Ticker].($d.Flag) = [string]$d.Date
        $changed = $true
        Write-WidgetLog "$($d.Kind) notice: $($d.Ticker) $($d.Date)"
    }
    if ($changed) { Save-Events }
}

function Check-MarketOpenNotifications {
    # Balloon once per exchange when its regular session starts
    if (-not $script:Config.ShowTrayNotifications -or -not $script:Config.NotifyMarketOpen) { return }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $syms = New-Object System.Collections.Generic.List[string]
    $syms.Add($script:Config.ActiveTicker.ToUpper())
    foreach ($k in $script:Portfolio.Keys) { if (-not $syms.Contains($k)) { $syms.Add($k) } }
    $opened = @{}
    foreach ($sym in $syms) {
        if (-not $script:QuoteStore.ContainsKey($sym)) { continue }
        $q = $script:QuoteStore[$sym]
        if ($null -eq $q.Tp -or $q.Tp.Is247) { continue }
        $key = if ($q.Tp.Exchange) { $q.Tp.Exchange } else { "{0}|{1}" -f $q.Tp.TzName, $q.Tp.RegStartTod }
        $st = (Get-MarketState -Tp $q.Tp -NowSec $now).State
        if ($opened.ContainsKey($key)) { $opened[$key] += ", $sym"; continue }
        if ($script:LastMarketState.ContainsKey($key) -and $script:LastMarketState[$key] -ne "REGULAR" -and $st -eq "REGULAR") {
            $opened[$key] = $sym
        }
        $script:LastMarketState[$key] = $st
    }
    foreach ($k in $opened.Keys) {
        $trayIcon.ShowBalloonTip(5000, "Handelsstart: $k", "Regulärer Handel hat begonnen ($($opened[$k]))", [System.Windows.Forms.ToolTipIcon]::Info)
    }
}

function Update-TrayIcon {
    # Small up/down triangle in the tray & title bar instead of the generic app icon
    param([string]$Key)
    if ($Key -eq $script:LastTrayIconKey) { return }
    $script:LastTrayIconKey = $Key
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear([System.Drawing.Color]::Transparent)
        $colr = switch ($Key) { "up" { $colGreen } "down" { $colRed } default { $script:Pal.Neutral } }
        $br = New-Object System.Drawing.SolidBrush($colr)
        if ($Key -eq "up") {
            $g.FillPolygon($br, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF(8, 1)), (New-Object System.Drawing.PointF(15, 14)), (New-Object System.Drawing.PointF(1, 14))))
        } elseif ($Key -eq "down") {
            $g.FillPolygon($br, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF(1, 2)), (New-Object System.Drawing.PointF(15, 2)), (New-Object System.Drawing.PointF(8, 15))))
        } else {
            $g.FillEllipse($br, 2, 2, 12, 12)
        }
        $br.Dispose()
    } finally { $g.Dispose() }
    $hIcon = $bmp.GetHicon()
    $bmp.Dispose()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $oldHandle = $script:TrayIconHandle
    $trayIcon.Icon = $icon
    $form.Icon = $icon
    $script:TrayIconHandle = $hIcon
    if ($oldHandle -ne [IntPtr]::Zero) { [void][Win32WidgetHelperV26]::DestroyIcon($oldHandle) }
}

$script:LastFxTip = ""
function Get-RelevantFxPairs {
    # Every currency in use (display, portfolio, quotes) against the display
    # currency, in market convention (EUR/USD, EUR/CHF, USD/CHF, ...)
    $disp = [string]$script:Config.Currency
    $used = New-Object System.Collections.Generic.HashSet[string]
    foreach ($c in @("USD", "CHF", "EUR")) { [void]$used.Add($c) }
    foreach ($p in $script:Portfolio.Values) { if ($p.Currency) { [void]$used.Add([string]$p.Currency) } }
    foreach ($q in $script:QuoteStore.Values) { if ($q.Currency) { [void]$used.Add([string]$q.Currency) } }
    [void]$used.Remove($disp)
    $prio = @{ "USD" = 0; "EUR" = 1; "CHF" = 2; "GBP" = 3 }
    $ordered = @($used | Sort-Object @{ Expression = { if ($prio.ContainsKey($_)) { $prio[$_] } else { 9 } } }, @{ Expression = { $_ } })
    $rDisp = if ($script:FxFromEur.ContainsKey($disp)) { [double]$script:FxFromEur[$disp] } else { 0.0 }
    $out = @()
    foreach ($c in $ordered) {
        if (-not $script:FxFromEur.ContainsKey($c) -or $rDisp -le 0) { continue }
        $rC = [double]$script:FxFromEur[$c]
        if ($rC -le 0) { continue }
        if ($disp -eq "EUR")   { $pair = "EUR/$c";    $rate = $rC }
        elseif ($c -eq "EUR")  { $pair = "EUR/$disp"; $rate = $rDisp }
        else                   { $pair = "$c/$disp";  $rate = $rDisp / $rC }
        $out += [PSCustomObject]@{ Pair = $pair; Rate = $rate; Live = ($script:FxLive.Contains($c) -and $script:FxLive.Contains($disp)) }
    }
    return $out
}

function Update-StatusLine {
    # Called by every UI update AND by the 1-second timer, so transient messages
    # expire on time and the "Stand" age colour stays current.
    if ($script:IsClosing -or $form.IsDisposed) { return }
    $p = $script:Pal
    $amber = $script:Pal.Warn
    $fxMissingList = @($script:FxMissing | Where-Object { $_ -and $_ -ne "EUR" -and -not $script:FxLive.Contains($_) } | Sort-Object)
    if ($script:TransientStatus -and (Get-Date) -lt $script:TransientUntil) {
        $txt = $script:TransientStatus; $colr = $amber
    } elseif (-not [string]::IsNullOrWhiteSpace($script:LastFetchWarning)) {
        # v4.0: offline = red, partial errors / rate limit = amber
        $txt = $script:LastFetchWarning
        $colr = if ($script:LastFetchOffline) { $colRed } else { $amber }
    } elseif ($fxMissingList.Count -gt 0) {
        $txt = "Kein Live-FX: " + ($fxMissingList -join ", ") + " (Werte ungenau)"; $colr = $amber
    } else {
        # Rates that matter for the display currency (was: always USD + CHF)
        $pairs = @(Get-RelevantFxPairs)
        $shown = @($pairs | Select-Object -First 3 | ForEach-Object { "{0} {1:N4}" -f $_.Pair, $_.Rate })
        # Time of the last successful refresh, NOT a clock
        $stand = if ($null -ne $script:LastDataTime) { $script:LastDataTime.ToString("HH:mm:ss") } else { "--:--:--" }
        # v7.1.1: show only as many pairs as fit (all rates stay in the tooltip)
        # With the status bar on, the time is already shown there, so the rates get the room.
        $tail = if ([bool]$script:Config.ShowStatusBar -and $shown.Count -gt 0) { @() } else { @("Stand $stand") }
        $minShow = if ($tail.Count -gt 0) { 0 } else { 1 }
        $nShow = $shown.Count
        do {
            $txt = (@($shown | Select-Object -First $nShow) + $tail) -join " | "
            $tooWide = $lblStatus.Width -gt 0 -and [System.Windows.Forms.TextRenderer]::MeasureText($txt, $lblStatus.Font).Width -gt $lblStatus.Width
            $nShow--
        } while ($tooWide -and $nShow -ge $minShow)
        $tip = "Wechselkurse (Anzeige in $($script:Config.Currency)):"
        foreach ($fp in $pairs) { $tip += "`r`n  {0,-8} {1:N4}{2}" -f $fp.Pair, $fp.Rate, $(if ($fp.Live) { "" } else { "  (Fallback)" }) }
        $tip += "`r`nStand = Uhrzeit der letzten erfolgreichen Datenaktualisierung (gelb = veraltet)"
        if ($tip -ne $script:LastFxTip) { Set-DynTip $lblStatus $tip "FX"; $script:LastFxTip = $tip }
        # v4.0: amber after 2 intervals, red when very old (see Get-StalenessLevel)
        $age = if ($null -eq $script:LastDataTime) { [double]::NaN } else { ((Get-Date) - $script:LastDataTime).TotalSeconds }
        $lvl = Get-StalenessLevel -AgeSec $age -RefreshSec ([int]$script:Config.RefreshSeconds)
        $colr = switch ($lvl) { "ERR" { $colRed } "WARN" { $amber } default { $p.Muted } }
    }
    # v4.0: explain a rate-limit pause / offline state when hovering the status
    $warnKey = if ($script:LastRateLimited -and $txt -eq $script:LastFetchWarning) { "RATELIMIT" } elseif ($txt -eq $script:LastFetchWarning -and $txt) { "STAND" } else { "" }
    if ($warnKey -and $script:LastFxTip -ne "warn:$warnKey") { Set-DynTip $lblStatus $txt $warnKey; $script:LastFxTip = "warn:$warnKey" }
    if ($lblStatus.Text -ne $txt) { $lblStatus.Text = $txt }
    if ($lblStatus.ForeColor -ne $colr) { $lblStatus.ForeColor = $colr }
    # v4.9.5: health dot
    $hAge = if ($null -eq $script:LastDataTime) { [double]::NaN } else { ((Get-Date) - $script:LastDataTime).TotalSeconds }
    $hClosed = $false
    if (-not [double]::IsNaN($hAge) -and $hAge -gt 2 * [int]$script:Config.RefreshSeconds) { $hClosed = Test-AllPrioClosed }
    $hl = Get-DataHealth -AgeSec $hAge -RefreshSec ([int]$script:Config.RefreshSeconds) -Offline ([bool]$script:LastFetchOffline) -RateLimited ([bool]$script:LastRateLimited) -ClosedMinutes ([int]$script:Config.ClosedPollMinutes) -AllClosed $hClosed
    if ($hl -ne $script:HealthLevel) {
        $script:HealthLevel = $hl
        $pnlHealth.Invalidate()
        $stTxt = if ($null -ne $script:LastDataTime) { $script:LastDataTime.ToString("HH:mm:ss") } else { "--:--:--" }
        $hTip = switch ($hl) {
            "OK"   { "Datenquelle Yahoo Finance: OK (letzte Aktualisierung $stTxt)" }
            "WARN" { if ($script:LastRateLimited) { "Yahoo bremst gerade (Rate-Limit) - es geht nach einer Pause automatisch weiter. Letzte Daten: $stTxt" } else { "Daten etwas veraltet oder unvollständig. Letzte Aktualisierung: $stTxt" } }
            "ERR"  { "Keine Verbindung zu Yahoo Finance oder Daten sehr alt. Letzte Aktualisierung: $stTxt. F5 versucht es sofort." }
            default { "Noch keine Daten" }
        }
        Set-DynTip $pnlHealth $hTip
    }
}

function Test-AllPrioClosed {
    $mst = @(Get-PrioMarketStates)
    return ($mst.Count -gt 0 -and @($mst | Where-Object { $_ -ne "CLOSED" }).Count -eq 0)
}

function Update-AllUiViews {
    if ($script:IsClosing -or $form.IsDisposed) { return }
    $sym  = $script:Config.ActiveTicker.ToUpper()
    $curr = Get-PriceCurrency $sym   # v5.1: price in the ticker currency (Auto); depot lines below use $baseCur
    $baseCur = [string]$script:Config.Currency
    $p    = $script:Pal
    $btnCurrency.Text = $(if ([bool]$script:Config.AutoCurrency) { "Auto $script:DropArrow" } else { "$baseCur $script:DropArrow" })

    if (-not $txtSearch.Focused) {
        $script:SuppressSearchEvent = $true
        $txtSearch.Text = $sym
        $script:SuppressSearchEvent = $false
    }

    foreach ($k in $tfButtons.Keys) {
        $btn = $tfButtons[$k]
        if ($k -eq $script:Config.Timeframe) {
            Style-FlatButton -Btn $btn -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
        } else {
            Style-FlatButton -Btn $btn -BgColor $p.Card -FgColor $p.Text -BorderColor $p.Border
        }
    }

    $togglePairs = @(
        @{ Btn = $btnChartType;  Active = ($script:Config.ChartType -in @("Candle", "HA")) },
        @{ Btn = $btnToggleVol;  Active = [bool]$script:Config.ShowVolume },
        @{ Btn = $btnToggleSma;  Active = [bool]$script:Config.ShowSma },
        @{ Btn = $btnToggleVwap; Active = [bool]$script:Config.ShowVwap },
        @{ Btn = $btnToggleBb;   Active = [bool]$script:Config.ShowBollinger },
        @{ Btn = $btnToggleRsi;  Active = [bool]$script:Config.ShowRsi },
        @{ Btn = $btnToggleExt;  Active = [bool]$script:Config.ShowExtended }
    )
    foreach ($tp in $togglePairs) {
        if ($tp.Active) {
            Style-FlatButton -Btn $tp.Btn -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
        } else {
            Style-FlatButton -Btn $tp.Btn -BgColor $p.Card -FgColor $p.Text -BorderColor $p.Border
        }
    }
    # v5.0: Linie / Kerzen / Heikin-Ashi (K cycles)
    $ctTxt = if ([string]$script:Config.ChartType -eq "HA") { "Heikin-A." } else { Tr "Kerzen" }
    if ($btnChartType.Text -ne $ctTxt) { $btnChartType.Text = $ctTxt }

    if ($script:QuoteStore.ContainsKey($sym)) {
        $q = $script:QuoteStore[$sym]
        $dispPrice = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $curr
        $sign = if ($q.ChangePct -ge 0) { "+" } else { "" }
        $col  = if ($q.ChangePct -ge 0) { $colGreen } else { $colRed }

        Set-LivePriceText -Key $sym -Price ([double]$dispPrice) -Curr $curr
        # v4.0: a quote from the cache of the last session is shown grey
        $fromCache = [bool]$q.FromCache
        $lblLivePrice.ForeColor = if ($fromCache) { $p.Muted } else { $p.Text }
        $priceTip = if ($fromCache) { "Kurs aus dem Cache (Stand {0}) - wird gerade aktualisiert" -f $q.UpdatedAt.ToString("dd.MM. HH:mm") } else { "Doppelklick = Kurs kopieren" }
        if ($priceTip -ne $script:LastPriceTip) { Set-Tip $lblLivePrice $priceTip $(if ($fromCache) { "CACHE" } else { "PRICE" }); $script:LastPriceTip = $priceTip }
        $lblDayChange.ForeColor = $col
        $lblDayChange.Text = "{0}{1}{2:N2}%" -f (Get-ArrowPrefix ([double]$q.ChangePct)), $sign, $q.ChangePct
        # v4.6: coloured "pill" behind the day change
        $lblDayChange.BackColor = Get-BlendColor -A $col -B $p.HeaderBg -T 0.18
        $dispPrev = Convert-CurrencyValue -Amount $q.PrevClose -FromCurrency $q.Currency -ToCurrency $curr
        $lblDayAbs.Text = if ($q.PrevClose -gt 0) { "{0}{1:N2} {2}" -f $sign, ($dispPrice - $dispPrev), $curr } else { "" }
        # v4.2: quarterly figures within a week -> amber note in front of the name
        $eb = Get-TickerEarningsBadge ([string]$script:Config.ActiveTicker)
        if ($null -ne $eb) {
            $lblHeaderName.Text = "Zahlen {0} · {1} ({2})" -f $eb.Text, $q.LongName, $q.Currency
            $lblHeaderName.ForeColor = $script:Pal.Warn
        } else {
            $lblHeaderName.Text = "{0} ({1})" -f $q.LongName, $q.Currency
            $lblHeaderName.ForeColor = $p.Muted
        }

        # Pre-/after-market quote below the price
        if ($q.ExtPrice -gt 0) {
            $extDisp = Convert-CurrencyValue -Amount $q.ExtPrice -FromCurrency $q.Currency -ToCurrency $curr
            $eSign = if ($q.ExtPct -ge 0) { "+" } else { "" }
            $eLbl  = if ($q.ExtSession -eq "PRE") { "Pre" } else { "Post" }
            $lblExtQuote.Text = "{0} {1:N2} {2}{3:N2}%" -f $eLbl, $extDisp, $eSign, $q.ExtPct
            $lblExtQuote.ForeColor = if ($q.ExtPct -ge 0) { $colGreen } else { $colRed }
            $eWhen = [DateTimeOffset]::FromUnixTimeSeconds([long]$q.ExtTs).ToLocalTime().ToString("ddd HH:mm")
            Set-DynTip $lblExtQuote ("{0} {1:N2} {2} ({3}{4:N2}% vs. Schluss) - Stand {5}" -f $(if ($q.ExtSession -eq "PRE") { "Vorbörse" } else { "Nachbörse" }), $extDisp, $curr, $eSign, $q.ExtPct, $eWhen) "EXT"
        } else {
            $lblExtQuote.Text = ""
        }

        $ms = Get-MarketState -Tp $q.Tp -NowSec ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        $stateTxt = if ($null -ne $ms) { " " + $ms.Short } else { "" }
        $tt = "{0}: {1:N2} {2} ({3}{4:N2}%){5}" -f $sym, $dispPrice, $curr, $sign, $q.ChangePct, $stateTxt
        # v4.4: second line with today's portfolio result
        $dl = Get-TrayDepotLine -Currency $baseCur
        if ($dl -and ($tt.Length + $dl.Length + 1) -le 63) { $tt = $tt + "`n" + $dl }
        $trayIcon.Text = if ($tt.Length -gt 63) { $tt.Substring(0, 63) } else { $tt }
        # v4.9.5: the tray icon follows the depot's day result (setting), else the ticker
        $trayKey = if ($q.ChangePct -ge 0) { "up" } else { "down" }
        if ([bool]$script:Config.TrayFollowsDepot -and $script:Portfolio.Count -gt 0) {
            $ptT = Get-PortfolioDayTotals -Currency $baseCur
            if ($ptT.Ok) { $trayKey = Get-DirectionKey -Pct ([double]$ptT.DayPct) }
        }
        Update-TrayIcon -Key $trayKey
    } else {
        $lblLivePrice.Text = "--.-- $curr"
        $lblDayChange.ForeColor = $p.Muted
        $lblDayChange.BackColor = $p.HeaderBg
        $lblDayChange.Text = "0.00%"
        $lblDayAbs.Text = ""
        $lblExtQuote.Text = ""
        $lblHeaderName.Text = $sym
        $lblHeaderName.ForeColor = $script:Pal.Muted
        Update-TrayIcon -Key "none"
    }
    Update-MarketStatusUi

    Update-StatusLine

    # Hidden in tray: only header/tray tooltip matter, skip the grid rebuilds.
    # v3.0: only the VISIBLE tab is rebuilt; Set-ActiveTab refreshes a tab
    # when it is shown.
    if ($form.Visible) { Update-VisibleTabContent }
    if ([bool]$script:Config.CompactMode) { Update-TickerTape }
    # Static chart bitmap is only re-rendered when its content really changed
    Update-ChartCacheSignature
    $pnlChartCanvas.Invalidate()
    $picCompactSpark.Invalidate()
    if ($null -ne $script:FsCanvas -and -not $script:FsCanvas.IsDisposed) { $script:FsCanvas.Invalidate() }
}

function Switch-ActiveTicker {
    param([string]$NewTicker, [bool]$SkipResolve = $false)
    $raw = $NewTicker.Trim().ToUpper()
    if ([string]::IsNullOrWhiteSpace($raw)) { return }

    $lstTickerDropdown.Visible   = $false
    $lstWlSearchDropdown.Visible = $false

    if (-not $SkipResolve) {
        $known = Get-KnownSymbol -Raw $raw
        if ($known) { $raw = $known; $SkipResolve = $true }
    }
    if (-not $SkipResolve) {
        # v3.0: unknown input is resolved in the background (was: synchronous
        # lookup + DoEvents). A newer switch supersedes this one via ResolveSeq.
        $script:ResolveSeq++
        $lblHeaderName.Text = "Suche $raw..."
        $u = Get-ResolveUrls -Clean $raw
        Start-FetchJob -Urls @($u.Probe, $u.Search) -MaxConcurrency 2 -Context @{ Raw = $raw; Seq = $script:ResolveSeq; Probe = $u.Probe; Search = $u.Search } -OnComplete {
            param($Box, $Ctx)
            if ($Ctx.Seq -ne $script:ResolveSeq) { return }
            $sym = Complete-SymbolResolve -Clean $Ctx.Raw -ProbeJson $Box.Results[$Ctx.Probe] -SearchJson $Box.Results[$Ctx.Search]
            if ($null -eq $Box.Results[$Ctx.Probe] -and $null -eq $Box.Results[$Ctx.Search]) {
                Set-TransientStatus "Symbolsuche nicht erreichbar - verwende '$($Ctx.Raw)'" 4
            }
            if ($sym) { Switch-ActiveTicker -NewTicker $sym -SkipResolve $true }
        }
        return
    }
    $script:ResolveSeq++   # a direct switch cancels a pending background lookup
    $clean = $raw

    $script:Config.ActiveTicker = $clean
    # v4.9.5: recent tickers for the search list (saved with the next config write)
    $script:Config.RecentTickers = @(Add-RecentCommand -Recent @($script:Config.RecentTickers) -Command $clean -Max 10)
    $script:ActiveSeries        = @()
    $script:ActiveLoadError     = ""
    $lblHeaderName.Text         = "Lade $clean..."
    $script:HoverIndex          = -1
    Update-ChartCacheSignature
    $pnlChartCanvas.Invalidate()

    $script:SuppressSearchEvent = $true
    $txtSearch.Text = $clean
    $script:SuppressSearchEvent = $false

    $txtAlertTicker.Text = $clean
    $txtPortTicker.Text  = $clean
    if ($script:Portfolio.ContainsKey($clean)) {
        $p = $script:Portfolio[$clean]
        $txtPortShares.Text = (Format-EditNumber $p.Shares)
        $txtPortAvg.Text    = (Format-EditNumber $p.AvgPrice)
        Select-CurrencyInCombo -Combo $cmbPortCurr -Code $p.Currency
        $txtPortBuyAmt.Text = if ($p.BuyAmount -gt 0) { (Format-EditNumber $p.BuyAmount) } else { "" }
        $txtPortTarget.Text = if ($p.TargetAvg -gt 0) { (Format-EditNumber $p.TargetAvg) } else { "" }
    } else {
        $txtPortShares.Text = ""; $txtPortAvg.Text = ""; $txtPortBuyAmt.Text = ""; $txtPortTarget.Text = ""
        $cIdx = $cmbPortCurr.Items.IndexOf($script:Config.Currency)
        if ($cIdx -ge 0) { $cmbPortCurr.SelectedIndex = $cIdx }
    }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Refresh-AllMarketData
    Update-AllUiViews
}

# ==============================================================================
# Events & Keyboard Shortcuts
# ==============================================================================
foreach ($k in $tabButtons.Keys) {
    $tabButtons[$k].Add_Click({
        param($sender, $e)
        Invoke-TabClick -TabName ([string]$sender.Tag)
    })
}

foreach ($k in $tfButtons.Keys) {
    $tfButtons[$k].Add_Click({
        param($sender, $e)
        Set-Timeframe -Tf ([string]$sender.Tag)
    })
}

$btnChartType.Add_Click({
    $script:Config.ChartType = Get-NextChartType ([string]$script:Config.ChartType)
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

$btnToggleVol.Add_Click({
    $script:Config.ShowVolume = -not $script:Config.ShowVolume
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

$btnToggleSma.Add_Click({
    $script:Config.ShowSma = -not $script:Config.ShowSma
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

$btnToggleVwap.Add_Click({
    $script:Config.ShowVwap = -not $script:Config.ShowVwap
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

$btnToggleBb.Add_Click({
    $script:Config.ShowBollinger = -not $script:Config.ShowBollinger
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

$btnToggleRsi.Add_Click({
    $script:Config.ShowRsi = -not $script:Config.ShowRsi
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})

function Toggle-ExtendedHours {
    $script:Config.ShowExtended = -not [bool]$script:Config.ShowExtended
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    if ($script:Config.Timeframe -ne "1d") {
        Set-TransientStatus ("Vor-/Nachbörse {0} (wirkt im 1D-Chart)" -f $(if ($script:Config.ShowExtended) { "an" } else { "aus" })) 4
        Update-AllUiViews
        return
    }
    $script:ActiveSeries = @()
    Update-AllUiViews
    Refresh-AllMarketData
    Update-AllUiViews
}

# ------------------------------------------------------------------------------
# Transactions (v2.9): buy / sell / dividend with realized P/L. Amounts are in
# the position currency; realized P/L is converted with the CURRENT FX rate.
# ------------------------------------------------------------------------------
function Save-Transactions {
    Save-JsonState -Path $script:TransactionsPath -Data $script:Transactions.ToArray()
}

function Add-TransactionRecord {
    param([string]$Type, [string]$Ticker, [double]$Shares, [double]$Price, [double]$Fee, [string]$Currency, [string]$Date, [double]$Realized = 0.0, [string]$Note = "")
    $script:Transactions.Add([PSCustomObject]@{
        Id       = [Guid]::NewGuid().ToString("N")
        Date     = if ($Date) { $Date } else { (Get-Date).ToString("yyyy-MM-dd") }
        Ticker   = $Ticker.ToUpper()
        Type     = $Type
        Shares   = $Shares
        Price    = $Price
        Fee      = $Fee
        Currency = $Currency
        Realized = $Realized
        Note     = $Note
    })
    Save-Transactions
}

function Get-RealizedTotal {
    # Sum of realized P/L in the display currency (optionally one year only)
    param([int]$Year = 0, [string]$Type = "")
    $curr = $script:Config.Currency
    $sum = 0.0
    foreach ($t in $script:Transactions) {
        if ($Year -gt 0 -and -not ([string]$t.Date).StartsWith([string]$Year)) { continue }
        if ($Type -and [string]$t.Type -ne $Type) { continue }
        if ([double]$t.Realized -ne 0) { $sum += Convert-CurrencyValue -Amount $t.Realized -FromCurrency $t.Currency -ToCurrency $curr }
    }
    return $sum
}

function Invoke-Transaction {
    # Applies a transaction to the position and logs it. Returns an error text or "".
    param([string]$Type, [string]$Ticker, [double]$Shares, [double]$Price, [double]$Fee, [string]$Currency, [string]$Date, [string]$Note)
    $sym = $Ticker.ToUpper()
    $pos = if ($script:Portfolio.ContainsKey($sym)) { $script:Portfolio[$sym] } else { $null }
    switch ($Type) {
        "Kauf" {
            if ($Shares -le 0 -or $Price -le 0) { return "Stück und Kurs müssen größer als 0 sein." }
            if ($null -eq $pos) {
                $avg = (($Shares * $Price) + $Fee) / $Shares
                $script:Portfolio[$sym] = [PSCustomObject]@{ Ticker = $sym; Shares = $Shares; AvgPrice = $avg; Currency = $Currency; BuyAmount = 0.0; TargetAvg = 0.0 }
            } else {
                # buy in the position currency (cost basis incl. fees)
                $px  = Convert-CurrencyValue -Amount $Price -FromCurrency $Currency -ToCurrency $pos.Currency
                $fee = Convert-CurrencyValue -Amount $Fee -FromCurrency $Currency -ToCurrency $pos.Currency
                $newSh = $pos.Shares + $Shares
                $pos.AvgPrice = (($pos.Shares * $pos.AvgPrice) + ($Shares * $px) + $fee) / $newSh
                $pos.Shares = $newSh
                $Currency = $pos.Currency; $Price = $px; $Fee = $fee
            }
            Add-TransactionRecord -Type "Kauf" -Ticker $sym -Shares $Shares -Price $Price -Fee $Fee -Currency $Currency -Date $Date -Note $Note
        }
        "Verkauf" {
            if ($null -eq $pos) { return "Keine Position '$sym' vorhanden." }
            if ($Shares -le 0 -or $Price -le 0) { return "Stück und Kurs müssen größer als 0 sein." }
            if ($Shares -gt ($pos.Shares + 0.000001)) { return ("Nur {0:N4} Stück im Bestand." -f $pos.Shares) }
            $px  = Convert-CurrencyValue -Amount $Price -FromCurrency $Currency -ToCurrency $pos.Currency
            $fee = Convert-CurrencyValue -Amount $Fee -FromCurrency $Currency -ToCurrency $pos.Currency
            $realized = (($px - $pos.AvgPrice) * $Shares) - $fee
            $pos.Shares = $pos.Shares - $Shares
            Add-TransactionRecord -Type "Verkauf" -Ticker $sym -Shares $Shares -Price $px -Fee $fee -Currency $pos.Currency -Date $Date -Realized $realized -Note $Note
            if ($pos.Shares -le 0.000001) { $script:Portfolio.Remove($sym) }
        }
        "Dividende" {
            if ($Price -le 0) { return "Bitte den Dividendenbetrag (gesamt, brutto) als 'Betrag' eingeben." }
            $tc = if ($null -ne $pos) { $pos.Currency } else { $Currency }
            $amt = Convert-CurrencyValue -Amount $Price -FromCurrency $Currency -ToCurrency $tc
            $fee = Convert-CurrencyValue -Amount $Fee -FromCurrency $Currency -ToCurrency $tc
            Add-TransactionRecord -Type "Dividende" -Ticker $sym -Shares $Shares -Price $amt -Fee $fee -Currency $tc -Date $Date -Realized ($amt - $fee) -Note $Note
        }
        default { return "Unbekannter Typ '$Type'." }
    }
    Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
    return ""
}

# v7.5: focus ring for text fields and tables. A text box cannot paint its own frame, so its
# parent draws it; a table draws it inside its own edge.
$script:RingDone = New-Object 'System.Collections.Generic.HashSet[object]'
$script:RingParentPaint = {
    param($sender, $e)
    try {
        foreach ($k in $sender.Controls) {
            if (($k -is [System.Windows.Forms.TextBox] -and $k.BorderStyle -ne [System.Windows.Forms.BorderStyle]::None -and $k.Focused -and $k.Visible) -or
                ($k -is [System.Windows.Forms.NumericUpDown] -and $k.ContainsFocus -and $k.Visible)) {
                $pen = New-Object System.Drawing.Pen($script:Pal.Accent, 2)
                $e.Graphics.DrawRectangle($pen, ($k.Left - 1), ($k.Top - 1), ($k.Width + 1), ($k.Height + 1))
                $pen.Dispose()
            }
        }
    } catch { }
}
$script:RingFieldChanged = { param($sender, $e) if ($null -ne $sender.Parent) { $sender.Parent.Invalidate() } }
$script:RingGridPaint = {
    param($sender, $e)
    if (-not $sender.Focused) { return }
    try {
        $pen = New-Object System.Drawing.Pen($script:Pal.Accent, 2)
        $e.Graphics.DrawRectangle($pen, 1, 1, ($sender.ClientSize.Width - 2), ($sender.ClientSize.Height - 2))
        $pen.Dispose()
    } catch { }
}
$script:RingGridChanged = { param($sender, $e) $sender.Invalidate() }
$script:RingForget = { param($sender, $e) [void]$script:RingDone.Remove($sender) }
function Add-FocusRings {
    param([System.Windows.Forms.Control]$Root)
    try {
        foreach ($k in @($Root.Controls)) {
            if ($k -is [System.Windows.Forms.DataGridView]) {
                if ($script:RingDone.Add($k)) {
                    $k.Add_Disposed($script:RingForget)
                    $k.Add_Paint($script:RingGridPaint)
                    $k.Add_GotFocus($script:RingGridChanged); $k.Add_LostFocus($script:RingGridChanged)
                    $k.Add_Scroll($script:RingGridChanged)
                }
            } elseif ($k -is [System.Windows.Forms.TextBox] -or $k -is [System.Windows.Forms.NumericUpDown]) {
                if ($script:RingDone.Add($k)) {
                    $k.Add_Disposed($script:RingForget)
                    if ($script:RingDone.Add($Root)) { $Root.Add_Paint($script:RingParentPaint); $Root.Add_Disposed($script:RingForget) }
                    $k.Add_Enter($script:RingFieldChanged); $k.Add_Leave($script:RingFieldChanged)
                }
            } elseif ($k.Controls.Count -gt 0) { Add-FocusRings $k }
        }
    } catch { Write-WidgetLog "Focus ring: $($_.Exception.Message)" "WARN" }
}

function Set-AccessibilityDefaults {
    # V7.1: accessible names for buttons / inputs without one (own text, else the label to the left or above)
    # and a tab order that follows the reading order (top to bottom, left to right) inside every container.
    param([System.Windows.Forms.Control]$Root, [switch]$NoTabOrder)
    try {
        $walk = {
            param($c)
            $kids = @($c.Controls)
            foreach ($k in $kids) {
                if ([string]::IsNullOrEmpty($k.AccessibleName)) {
                    $n = ""
                    if ($k -is [System.Windows.Forms.Button] -or $k -is [System.Windows.Forms.CheckBox]) { $n = [string]$k.Text }
                    elseif ($k -is [System.Windows.Forms.TextBox] -or $k -is [System.Windows.Forms.ComboBox] -or $k -is [System.Windows.Forms.NumericUpDown] -or $k -is [System.Windows.Forms.DataGridView]) {
                        $best = $null
                        foreach ($lb in $kids) {
                            if ($lb -isnot [System.Windows.Forms.Label] -or [string]::IsNullOrWhiteSpace($lb.Text)) { continue }
                            $sameRow = ([math]::Abs($lb.Top - $k.Top) -le (S 8) -and $lb.Left -lt $k.Left)
                            $above = ($lb.Bottom -le ($k.Top + (S 2)) -and ($k.Top - $lb.Bottom) -le (S 24) -and [math]::Abs($lb.Left - $k.Left) -le (S 40))
                            if ($sameRow -or $above) { if ($null -eq $best -or $lb.Left -gt $best.Left) { $best = $lb } }
                        }
                        if ($null -ne $best) { $n = [string]$best.Text }
                    }
                    $n = $n.Trim().TrimEnd(":").Trim()
                    if ($n) { $k.AccessibleName = $n }
                }
                if ($k.Controls.Count -gt 0) { & $walk $k }
            }
            if ($NoTabOrder) { return }
            $ord = @($kids | Where-Object { $_.TabStop } | Sort-Object @{ Expression = { [int][math]::Floor($_.Top / [double](S 8)) } }, @{ Expression = { $_.Left } })
            $ix = 0
            foreach ($k in $ord) { try { $k.TabIndex = $ix } catch { }; $ix++ }
        }
        & $walk $Root
    } catch { }
}

function New-DialogForm {
    # v5.5: Key = remember position (and size, if sizable) under this name
    param([string]$Title, [int]$W, [int]$H, [string]$Key = "")
    $p = $script:Pal
    $d = New-Object System.Windows.Forms.Form
    $d.Text = $Title
    $d.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.ShowInTaskbar = $false
    $d.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $d.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $d.BackColor = $p.BodyBg; $d.ForeColor = $p.Text; $d.Font = $fontUi
    $d.TopMost = $form.TopMost
    $d.ClientSize = New-Object System.Drawing.Size($W, $H)
    $d.Add_HandleCreated($script:DialogChromeHandler)
    # v4.7: English mode translates the static texts once the dialog is built
    $d.Add_Shown({ param($sender, $e) Apply-Language $sender; Set-AccessibilityDefaults $sender; Add-FocusRings $sender })
    $d.Text = Tr $Title
    if ($Key) { Register-DialogPlacement -Dlg $d -Key $Key }
    return $d
}

function New-StandardDialog {
    # V7.1: one dialog template - title + subtitle, 16 px margins (4 px grid), primary button bottom right,
    # Enter = OK, Esc = cancel, inline error line instead of pop-up messages.
    # Returns Dlg, Body (panel for the content, Body width = W - 32), Ok, Cancel, Err. Validation: set $r.Dlg.Tag.Validate = { param($text) "" or error text }.
    param([string]$Title, [string]$Subtitle = "", [int]$W = 400, [int]$BodyH = 60, [string]$OkText = "OK", [string]$CancelText = "Abbrechen", [string]$Key = "")
    $p = $script:Pal
    $headH = if ($Subtitle) { S 60 } else { S 40 }
    $bodyPx = S $BodyH
    $d = New-DialogForm -Title $Title -W (S $W) -H ($headH + $bodyPx + (S 76)) -Key $Key
    $lt = New-Object System.Windows.Forms.Label
    $lt.SetBounds((S 16), (S 14), ((S $W) - (S 32)), (S 22)); $lt.Font = $fontUiBold; $lt.Text = $Title; $lt.AutoEllipsis = $true
    $d.Controls.Add($lt)
    if ($Subtitle) {
        $ls = New-Object System.Windows.Forms.Label
        $ls.SetBounds((S 16), (S 36), ((S $W) - (S 32)), (S 18)); $ls.ForeColor = $p.Muted; $ls.Text = $Subtitle; $ls.AutoEllipsis = $true
        $d.Controls.Add($ls)
    }
    $body = New-Object System.Windows.Forms.Panel
    $body.SetBounds((S 16), $headH, ((S $W) - (S 32)), $bodyPx); $body.BackColor = $d.BackColor
    $d.Controls.Add($body)
    $err = New-Object System.Windows.Forms.Label
    $err.SetBounds((S 16), ($headH + $bodyPx + (S 4)), ((S $W) - (S 32)), (S 18)); $err.ForeColor = $colRed; $err.Text = ""; $err.AutoEllipsis = $true
    $d.Controls.Add($err)
    $y = $headH + $bodyPx + (S 28)
    $ok = New-Object System.Windows.Forms.Button
    $ok.SetBounds(((S $W) - (S 16) - (S 96)), $y, (S 96), (S 28)); $ok.Text = $OkText
    Style-FlatButton -Btn $ok -BgColor $p.Accent -FgColor $p.OnAccent -BorderColor $p.Accent
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $d.Controls.Add($ok)
    $ca = New-Object System.Windows.Forms.Button
    $ca.SetBounds(((S $W) - (S 16) - (S 96) - (S 8) - (S 96)), $y, (S 96), (S 28)); $ca.Text = $CancelText
    Style-FlatButton -Btn $ca -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $ca.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $d.Controls.Add($ca)
    $d.AcceptButton = $ok; $d.CancelButton = $ca
    $d.Tag = @{ Validate = $null; Err = $err; Input = $null }
    $d.Add_FormClosing({
        param($s, $e)
        if ($s.DialogResult -ne [System.Windows.Forms.DialogResult]::OK -or $null -eq $s.Tag -or $null -eq $s.Tag.Validate) { return }
        $txt = if ($null -ne $s.Tag.Input) { [string]$s.Tag.Input.Text } else { "" }
        $msg = [string](& $s.Tag.Validate $txt)
        if ($msg) { $e.Cancel = $true; $s.Tag.Err.Text = $msg; $s.DialogResult = [System.Windows.Forms.DialogResult]::None }
    })
    return [PSCustomObject]@{ Dlg = $d; Body = $body; Ok = $ok; Cancel = $ca; Err = $err }
}

# ---- v5.5: dialogs open where they were closed (if that screen still exists) ----
function Register-DialogPlacement {
    param([System.Windows.Forms.Form]$Dlg, [string]$Key)
    $Dlg.Name = "twdlg_" + $Key
    $Dlg.Add_Load({
        param($sender, $e)
        try {
            $k = ([string]$sender.Name).Substring(6)
            $all = $script:Config.DialogPlacement
            if ($null -eq $all -or $null -eq $all.PSObject.Properties[$k]) { return }
            $screens = @([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { $wa = $_.WorkingArea; [PSCustomObject]@{ X = $wa.X; Y = $wa.Y; W = $wa.Width; H = $wa.Height } })
            $pl = Get-DialogPlacement -Saved $all.$k -Screens $screens -MinW ([math]::Min($sender.Width, (S 200))) -MinH ([math]::Min($sender.Height, (S 120)))
            if ($null -eq $pl) { return }
            $sender.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
            if ($sender.FormBorderStyle -eq [System.Windows.Forms.FormBorderStyle]::Sizable) {
                $w = [math]::Max($sender.MinimumSize.Width, [int]$pl.W); $h = [math]::Max($sender.MinimumSize.Height, [int]$pl.H)
                $sender.Bounds = New-Object System.Drawing.Rectangle([int]$pl.X, [int]$pl.Y, $w, $h)
            } else {
                $sender.Location = New-Object System.Drawing.Point([int]$pl.X, [int]$pl.Y)
            }
        } catch { Write-WidgetLog "Dialog placement: $($_.Exception.Message)" "WARN" }
    })
    $Dlg.Add_FormClosing({
        param($sender, $e)
        try {
            if ($sender.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) { return }
            $k = ([string]$sender.Name).Substring(6)
            if ($null -eq $script:Config.DialogPlacement -or $script:Config.DialogPlacement -is [string]) { $script:Config.DialogPlacement = [PSCustomObject]@{} }
            $b = $sender.Bounds
            $v = [PSCustomObject]@{ X = $b.X; Y = $b.Y; W = $b.Width; H = $b.Height }
            $script:Config.DialogPlacement | Add-Member -NotePropertyName $k -NotePropertyValue $v -Force
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
        } catch { Write-WidgetLog "Dialog placement: $($_.Exception.Message)" "WARN" }
    })
}

# ---- v5.5: privacy mode in every window that shows amounts ----
$script:PrivacyCellFmt = {
    param($sender, $e)
    if (-not [bool]$script:Config.PrivacyMode -or $e.ColumnIndex -lt 0 -or $e.RowIndex -lt 0) { return }
    $col = $sender.Columns[$e.ColumnIndex]
    if (-not (Test-AmountColumn ([string]$col.HeaderText))) { return }
    $v = [string]$e.Value
    if (-not $v -or $v.Contains("%") -or $v -notmatch '\d') { return }
    $e.Value = [string][char]0x2022 * 3
    $e.FormattingApplied = $true
}
$script:PrivacyLabelFix = {
    param($sender, $e)
    if (-not [bool]$script:Config.PrivacyMode) { return }
    $t = Hide-AmountsInText ([string]$sender.Text)
    if ($t -ne [string]$sender.Text) { $sender.Text = $t }
}
function Enable-PrivacyMask {
    # grids: amount columns show dots; labels: amounts with a currency show dots
    param($Root)
    if ($null -eq $Root) { return }
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $c = $stack.Pop()
        if ($c -is [System.Windows.Forms.DataGridView]) { $c.Add_CellFormatting($script:PrivacyCellFmt) }
        elseif ($c -is [System.Windows.Forms.Label]) { $c.Add_TextChanged($script:PrivacyLabelFix); & $script:PrivacyLabelFix $c $null }
        foreach ($ch in $c.Controls) { $stack.Push($ch) }
    }
}

# ---- v5.5: export - pictures of windows / charts, grids as CSV or HTML ----
function Get-ControlBitmap {
    param([System.Windows.Forms.Control]$Ctl)
    $bmp = New-Object System.Drawing.Bitmap([math]::Max(1, $Ctl.Width), [math]::Max(1, $Ctl.Height))
    $Ctl.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $bmp.Width, $bmp.Height)))
    return $bmp
}

function Export-ControlImage {
    # Mode Copy = clipboard, Save = PNG file (Path empty = ask)
    param([System.Windows.Forms.Control]$Ctl, [string]$Mode = "Copy", [string]$Name = "TerminalWidget", [string]$Path = "")
    if ($null -eq $Ctl -or $Ctl.IsDisposed) { return "" }
    $bmp = $null
    try {
        $bmp = Get-ControlBitmap $Ctl
        if ($Mode -eq "Copy") {
            [System.Windows.Forms.Clipboard]::SetImage($bmp)
            Set-TransientStatus "Bild in der Zwischenablage" 3
            return "clipboard"
        }
        if (-not $Path) {
            $sfd = New-Object System.Windows.Forms.SaveFileDialog
            $sfd.Filter = "PNG-Bild (*.png)|*.png"
            $sfd.FileName = "{0}_{1}.png" -f $Name, (Get-Date -Format "yyyyMMdd_HHmm")
            if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { $sfd.Dispose(); return "" }
            $Path = $sfd.FileName; $sfd.Dispose()
        }
        $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        Set-TransientStatus ("Bild gespeichert: {0}" -f [IO.Path]::GetFileName($Path)) 4
        return $Path
    } catch {
        Write-WidgetLog "Image export: $($_.Exception.Message)" "WARN"
        Set-TransientStatus ("Bild fehlgeschlagen: {0}" -f $_.Exception.Message) 5
        return ""
    } finally { if ($null -ne $bmp) { $bmp.Dispose() } }
}

function Get-GridExportData {
    # visible columns, formatted values (privacy mask applies)
    param([System.Windows.Forms.DataGridView]$Grid)
    $cols = @($Grid.Columns | Where-Object { $_.Visible } | Sort-Object DisplayIndex)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Grid.Rows) {
        if ($r.IsNewRow -or -not $r.Visible) { continue }
        $vals = @(foreach ($c in $cols) { [string]$r.Cells[$c.Index].FormattedValue })
        $rows.Add([object[]]$vals)
    }
    return [PSCustomObject]@{ Headers = [string[]]@($cols | ForEach-Object { [string]$_.HeaderText }); Rows = $rows.ToArray() }
}

function Export-GridsReport {
    # Grids of a window / page as CSV (first grid) or HTML (all, with the labels as notes)
    param([object[]]$Grids, [string]$Title, [string]$Format = "Html", [string]$Path = "", [string]$Note = "")
    $grids = @($Grids | Where-Object { $null -ne $_ -and $_.Visible -and $_.Rows.Count -gt 0 })
    if ($grids.Count -eq 0) { Set-TransientStatus "Auf dieser Seite gibt es keine Tabelle zum Exportieren" 4; return "" }
    $ext = if ($Format -eq "Csv") { "csv" } else { "html" }
    if (-not $Path) {
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = if ($Format -eq "Csv") { "CSV für Excel (*.csv)|*.csv" } else { "HTML-Bericht (*.html)|*.html" }
        $safe = ($Title -replace '[^\w\-]+', '_').Trim('_')
        $sfd.FileName = "{0}_{1}.{2}" -f $safe, (Get-Date -Format "yyyyMMdd"), $ext
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { $sfd.Dispose(); return "" }
        $Path = $sfd.FileName; $sfd.Dispose()
    }
    try {
        if ($Format -eq "Csv") {
            $sections = @(foreach ($g in $grids) { Get-GridExportData $g })
            $parts = @(foreach ($sec in $sections) { ConvertTo-CsvText -Headers $sec.Headers -Rows $sec.Rows })
            # UTF-8 with BOM: Excel then shows the umlauts correctly
            [IO.File]::WriteAllText($Path, ($parts -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding($true)))
        } else {
            $sections = @(foreach ($g in $grids) { $d = Get-GridExportData $g; [PSCustomObject]@{ Title = ""; Headers = $d.Headers; Rows = $d.Rows; Note = "" } })
            if ($Note -and $sections.Count -gt 0) { $sections[0].Note = $Note }
            $foot = "{0} {1} - {2}{3}" -f $script:AppTitle, (Get-Date -Format "dd.MM.yyyy HH:mm"), (Tr "keine Anlageberatung"), $(if ([bool]$script:Config.PrivacyMode) { " - " + (Tr "Privat-Modus: Beträge ausgeblendet") } else { "" })
            [IO.File]::WriteAllText($Path, (ConvertTo-HtmlReport -Title $Title -Sections $sections -Footer $foot), (New-Object System.Text.UTF8Encoding($false)))
        }
        Write-WidgetLog "Report exported: $Path"
        Set-TransientStatus ("Gespeichert: {0}" -f [IO.Path]::GetFileName($Path)) 4
        return $Path
    } catch {
        Write-WidgetLog "Report export: $($_.Exception.Message)" "WARN"
        Show-InfoBox -Text ("Export fehlgeschlagen: {0}" -f $_.Exception.Message) -Title "Export"
        return ""
    }
}

function Get-ChildGrids {
    param($Root)
    $out = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $c = $stack.Pop()
        if ($c -is [System.Windows.Forms.DataGridView]) { $out.Add($c) }
        foreach ($ch in $c.Controls) { $stack.Push($ch) }
    }
    return $out.ToArray()
}

function Get-ChildLabelText {
    # longer labels of a page (sums, notes) for the HTML report
    param($Root)
    $t = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $c = $stack.Pop()
        if ($c -is [System.Windows.Forms.Label] -and $c.Visible -and ([string]$c.Text).Length -gt 25) { $t.Add([string]$c.Text) }
        foreach ($ch in $c.Controls) { $stack.Push($ch) }
    }
    return ($t.ToArray() -join " | ")
}

function Show-TransactionDialog {
    param([string]$Ticker = "")
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Transaktion erfassen" -W (S 360) -H (S 330)
    $rowY = @{ Y = (S 14) }
    $addRow = {
        param([string]$Label, [System.Windows.Forms.Control]$Ctl)
        $l = New-Object System.Windows.Forms.Label
        $l.SetBounds((S 14), ($rowY.Y + (S 3)), (S 120), (S 18))
        $l.Text = $Label
        $dlg.Controls.Add($l)
        $Ctl.SetBounds((S 140), $rowY.Y, (S 204), (S 24))
        $dlg.Controls.Add($Ctl)
        $rowY.Y += S 32
    }
    $newTb = {
        param([string]$Text)
        $t = New-Object System.Windows.Forms.TextBox
        $t.BackColor = $p.Input; $t.ForeColor = $p.Text; $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle; $t.Font = $fontMono
        $t.Text = $Text
        return $t
    }
    $cbType = New-Object System.Windows.Forms.ComboBox
    $cbType.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbType.BackColor = $p.Input; $cbType.ForeColor = $p.Text; $cbType.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    foreach ($tt in @("Kauf", "Verkauf", "Dividende")) { [void]$cbType.Items.Add($tt) }
    $cbType.SelectedIndex = 0
    & $addRow "Typ" $cbType

    $dtp = New-Object System.Windows.Forms.DateTimePicker
    $dtp.Format = [System.Windows.Forms.DateTimePickerFormat]::Short
    $dtp.Value = Get-Date
    & $addRow "Datum" $dtp

    $tbSym = & $newTb $Ticker.ToUpper()
    & $addRow "Ticker" $tbSym
    $tbSh  = & $newTb ""
    & $addRow "Stück" $tbSh
    $tbPx  = & $newTb ""
    & $addRow "Kurs je Stück" $tbPx
    $lblPx = $dlg.Controls[$dlg.Controls.Count - 2]
    $tbFee = & $newTb ""
    & $addRow "Gebühren" $tbFee

    $cbCur = New-Object System.Windows.Forms.ComboBox
    $cbCur.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbCur.BackColor = $p.Input; $cbCur.ForeColor = $p.Accent; $cbCur.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    foreach ($cc in (Get-DisplayCurrencies)) { [void]$cbCur.Items.Add($cc) }
    $preCur = if ($Ticker -and $script:Portfolio.ContainsKey($Ticker.ToUpper())) { $script:Portfolio[$Ticker.ToUpper()].Currency } else { $script:Config.Currency }
    $cbCur.SelectedIndex = 0
    Select-CurrencyInCombo -Combo $cbCur -Code $preCur
    & $addRow "Währung" $cbCur

    $tbNote = & $newTb ""
    & $addRow "Notiz" $tbNote

    $info = New-Object System.Windows.Forms.Label
    $info.SetBounds((S 14), $rowY.Y, (S 330), (S 32))
    $info.ForeColor = $p.Muted
    $dlg.Controls.Add($info)

    $script:TxDlg = @{ Dlg = $dlg; Type = $cbType; Sym = $tbSym; Sh = $tbSh; Px = $tbPx; Fee = $tbFee; Cur = $cbCur; Note = $tbNote; Date = $dtp; Info = $info; LblPx = $lblPx }
    $cbType.Add_SelectedIndexChanged({
        $t = $script:TxDlg
        $isDiv = ([string]$t.Type.SelectedItem -eq "Dividende")
        $t.LblPx.Text = if ($isDiv) { "Betrag gesamt" } else { "Kurs je Stück" }
        $t.Info.Text = switch ([string]$t.Type.SelectedItem) {
            "Kauf"      { "Kauf erhöht den Bestand; der EK wird inkl. Gebühren neu berechnet." }
            "Verkauf"   { "Realisierter G/V = (Kurs - EK) x Stück - Gebühren." }
            "Dividende" { "Stück optional. Betrag brutto; Gebühren/Steuern werden abgezogen." }
        }
    })
    $cbType.SelectedIndex = 1; $cbType.SelectedIndex = 0   # fire once for the info text

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.SetBounds((S 154), ($rowY.Y + (S 40)), (S 92), (S 28))
    Style-FlatButton -Btn $btnOk -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnOk.Text = "Buchen"
    $btnOk.Add_Click({
        $t = $script:TxDlg
        foreach ($tb in @($t.Sh, $t.Px, $t.Fee)) {
            if (-not (Test-DecimalInput $tb.Text)) { $t.Info.ForeColor = $colRed; $t.Info.Text = "Ungültige Zahl: '$($tb.Text)'"; return }
        }
        if ([string]::IsNullOrWhiteSpace($t.Sym.Text)) { $t.Info.ForeColor = $colRed; $t.Info.Text = "Bitte einen Ticker eingeben."; return }
        $sym = $t.Sym.Text.Trim().ToUpper()
        if (-not $script:Portfolio.ContainsKey($sym)) { $sym = Resolve-BestSymbol -RawInput $sym }
        $err = Invoke-Transaction -Type ([string]$t.Type.SelectedItem) -Ticker $sym -Shares (Parse-DecimalInput $t.Sh.Text) -Price (Parse-DecimalInput $t.Px.Text) `
            -Fee (Parse-DecimalInput $t.Fee.Text) -Currency ([string]$t.Cur.SelectedItem) -Date ($t.Date.Value.ToString("yyyy-MM-dd")) -Note $t.Note.Text.Trim()
        if ($err) { $t.Info.ForeColor = $colRed; $t.Info.Text = $err; return }
        $t.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $t.Dlg.Close()
    })
    $dlg.Controls.Add($btnOk)
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.SetBounds((S 252), ($rowY.Y + (S 40)), (S 92), (S 28))
    Style-FlatButton -Btn $btnCancel -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $btnCancel.Text = "Abbrechen"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCancel)
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel
    $dlg.ClientSize = New-Object System.Drawing.Size((S 360), ($rowY.Y + (S 82)))

    $res = $dlg.ShowDialog($form)
    $script:TxDlg = $null
    $dlg.Dispose()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-TransientStatus "Transaktion gebucht" 3
        Refresh-AllMarketData
        Update-AllUiViews
    }
}

function Show-TransactionHistory {
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Transaktionshistorie" -W (S 760) -H (S 440) -Key "TxHistory"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 600), (S 300))

    $cbFilter = New-Object System.Windows.Forms.ComboBox
    $cbFilter.SetBounds((S 12), (S 10), (S 140), (S 24))
    $cbFilter.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbFilter.BackColor = $p.Input; $cbFilter.ForeColor = $p.Text; $cbFilter.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    [void]$cbFilter.Items.Add("Alle Ticker")
    foreach ($tk in @($script:Transactions | ForEach-Object { $_.Ticker } | Sort-Object -Unique)) { [void]$cbFilter.Items.Add($tk) }
    $cbFilter.SelectedIndex = 0
    $dlg.Controls.Add($cbFilter)

    $lblSum = New-Object System.Windows.Forms.Label
    $lblSum.SetBounds((S 164), (S 13), (S 584), (S 20))
    $lblSum.Font = $fontMono
    $lblSum.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $dlg.Controls.Add($lblSum)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.SetBounds((S 12), (S 42), (S 736), (S 346))
    $grid.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    Style-DataGrid -Grid $grid
    foreach ($cd in @(@("Date", "Datum", 84), @("Type", "Typ", 72), @("Ticker", "Ticker", 72), @("Shares", "Stück", 70), @("Price", "Kurs/Betrag", 86),
                      @("Fee", "Gebühr", 64), @("Cur", "Whg", 44), @("Real", "Realisiert", 92), @("Note", "Notiz", 120), @("Id", "Id", 10))) {
        $ci = $grid.Columns.Add($cd[0], $cd[1])
        $grid.Columns[$ci].Width = S $cd[2]
        $grid.Columns[$ci].FillWeight = [float](S $cd[2])
    }
    $grid.Columns["Id"].Visible = $false
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dlg.Controls.Add($grid)

    $btnDel = New-Object System.Windows.Forms.Button
    $btnDel.SetBounds((S 12), (S 398), (S 120), (S 28))
    $btnDel.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    Style-FlatButton -Btn $btnDel -BgColor $p.Input -FgColor $colRed -BorderColor $p.Border
    $btnDel.Text = "Eintrag löschen"
    $dlg.Controls.Add($btnDel)
    $btnCsv = New-Object System.Windows.Forms.Button
    $btnCsv.SetBounds((S 140), (S 398), (S 110), (S 28))
    $btnCsv.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    Style-FlatButton -Btn $btnCsv -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $btnCsv.Text = "CSV export"
    $dlg.Controls.Add($btnCsv)
    # v3.0: rebuild the position of the selected / filtered ticker from its bookings
    $btnRebuild = New-Object System.Windows.Forms.Button
    $btnRebuild.SetBounds((S 258), (S 398), (S 170), (S 28))
    $btnRebuild.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    Style-FlatButton -Btn $btnRebuild -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnRebuild.Text = "Position neu berechnen"
    $dlg.Controls.Add($btnRebuild)
    # v4.0: yearly report (realized G/V + dividends at the FX rate of each booking date)
    $btnReport = New-Object System.Windows.Forms.Button
    $btnReport.SetBounds((S 436), (S 398), (S 130), (S 28))
    $btnReport.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    Style-FlatButton -Btn $btnReport -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnReport.Text = "Jahresreport..."
    $btnReport.Add_Click({ Show-YearReport -Owner $script:TxHist.Dlg })
    $dlg.Controls.Add($btnReport)
    Set-DynTip $btnReport "Realisierte G/V und Dividenden eines Jahres, mit dem Wechselkurs am Buchungstag" "REPORT"
    Set-DynTip $btnRebuild "Bestand und EK des markierten (oder gefilterten) Tickers aus allen Kauf-/Verkaufsbuchungen neu berechnen - mit Vorschau" "REBUILD"
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.SetBounds((S 638), (S 398), (S 110), (S 28))
    $btnClose.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    Style-FlatButton -Btn $btnClose -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnClose.Text = "Schließen"
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnClose)
    $dlg.CancelButton = $btnClose

    $script:TxHist = @{ Grid = $grid; Filter = $cbFilter; Sum = $lblSum; Dlg = $dlg }
    $fill = {
        $h = $script:TxHist
        $flt = [string]$h.Filter.SelectedItem
        $curr = $script:Config.Currency
        $h.Grid.Rows.Clear()
        $sumAll = 0.0; $sumYear = 0.0
        $yr = [string](Get-Date).Year
        foreach ($t in @($script:Transactions | Sort-Object Date -Descending)) {
            if ($flt -ne "Alle Ticker" -and $t.Ticker -ne $flt) { continue }
            $realDisp = if ([double]$t.Realized -ne 0) { Convert-CurrencyValue -Amount $t.Realized -FromCurrency $t.Currency -ToCurrency $curr } else { 0.0 }
            $sumAll += $realDisp
            if (([string]$t.Date).StartsWith($yr)) { $sumYear += $realDisp }
            $ri = $h.Grid.Rows.Add($t.Date, $t.Type, $t.Ticker, ("{0:N4}" -f $t.Shares), ("{0:N2}" -f $t.Price), ("{0:N2}" -f $t.Fee), $t.Currency,
                $(if ([double]$t.Realized -ne 0) { "{0:+0.00;-0.00}" -f $t.Realized } else { "" }), $t.Note, $t.Id)
            if ([double]$t.Realized -ne 0) { $h.Grid.Rows[$ri].Cells["Real"].Style.ForeColor = if ($t.Realized -ge 0) { $colGreen } else { $colRed } }
        }
        $h.Sum.Text = "Realisiert {0}: {1:+0.00;-0.00} {2}  |  gesamt: {3:+0.00;-0.00} {2}  (zum aktuellen Kurs umgerechnet)" -f $yr, $sumYear, $curr, $sumAll
        $h.Sum.ForeColor = if ($sumAll -ge 0) { $colGreen } else { $colRed }
    }
    $script:TxHist.Fill = $fill
    $cbFilter.Add_SelectedIndexChanged({ & $script:TxHist.Fill })
    $btnDel.Add_Click({
        $h = $script:TxHist
        if ($h.Grid.SelectedRows.Count -eq 0) { return }
        $id = [string]$h.Grid.SelectedRows[0].Cells["Id"].Value
        $delSym = [string]$h.Grid.SelectedRows[0].Cells["Ticker"].Value
        $delType = [string]$h.Grid.SelectedRows[0].Cells["Type"].Value
        if (-not (Confirm-Action -Text "Eintrag löschen?`r`n`r`nDer Bestand wird nicht automatisch geändert; im nächsten Schritt kannst du die Position aus den verbleibenden Buchungen neu berechnen lassen." -Title "Transaktion")) { return }
        for ($i = $script:Transactions.Count - 1; $i -ge 0; $i--) { if ($script:Transactions[$i].Id -eq $id) { $script:Transactions.RemoveAt($i) } }
        Save-Transactions
        & $h.Fill
        # v3.0: offer the recalculation right away (buys/sells only)
        if ($delType -in @("Kauf", "Verkauf") -and $delSym) {
            if (Invoke-PositionRebuild -Ticker $delSym -Owner $h.Dlg) { Update-AllUiViews }
        }
    })
    $btnRebuild.Add_Click({
        $h = $script:TxHist
        $sym = ""
        if ($h.Grid.SelectedRows.Count -gt 0) { $sym = [string]$h.Grid.SelectedRows[0].Cells["Ticker"].Value }
        if (-not $sym -and [string]$h.Filter.SelectedItem -ne "Alle Ticker") { $sym = [string]$h.Filter.SelectedItem }
        if (-not $sym) {
            [System.Windows.Forms.MessageBox]::Show($h.Dlg, "Bitte eine Buchung markieren oder oben einen Ticker wählen.", "Position neu berechnen",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            return
        }
        if (Invoke-PositionRebuild -Ticker $sym -Owner $h.Dlg) { Update-AllUiViews }
    })
    $btnCsv.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "CSV Datei (*.csv)|*.csv"
        $sfd.FileName = "transaktionen_{0}.csv" -f (Get-Date -Format "yyyyMMdd")
        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add("Datum;Typ;Ticker;Stück;Kurs/Betrag;Gebühr;Währung;Realisiert;Notiz")
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            foreach ($t in @($script:Transactions | Sort-Object Date)) {
                # v3.0: text fields escaped (quotes, line breaks, formula injection)
                $lines.Add(("{0};{1};{2};{3};{4};{5};{6};{7};{8}" -f $t.Date, $t.Type, (ConvertTo-CsvField $t.Ticker), ([double]$t.Shares).ToString($inv), ([double]$t.Price).ToString($inv), ([double]$t.Fee).ToString($inv), $t.Currency, ([double]$t.Realized).ToString($inv), (ConvertTo-CsvField ([string]$t.Note))))
            }
            [System.IO.File]::WriteAllLines($sfd.FileName, $lines, [System.Text.Encoding]::UTF8)
        }
        $sfd.Dispose()
    })
    & $fill
    # v4.5: CSV import from the history window
    $btnImp = New-Object System.Windows.Forms.Button
    $btnImp.SetBounds((S 572), (S 398), (S 60), (S 28))
    $btnImp.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    Style-FlatButton -Btn $btnImp -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnImp.Text = "Import"
    $btnImp.Add_Click({ $script:TxHist.Import = $true; $script:TxHist.Dlg.Close() })
    $dlg.Controls.Add($btnImp)
    Set-DynTip $btnImp "Buchungen aus einer Broker-CSV importieren (Trade Republic, Scalable, Flatex, comdirect, IBKR ... - Spalten werden erkannt). Befehl: IMP"
    $script:TxHist.Import = $false
    [void]$dlg.ShowDialog($form)
    $doImport = [bool]$script:TxHist.Import
    $script:TxHist = $null
    $dlg.Dispose()
    if ($doImport) { Show-CsvImportDialog }
}

function Invoke-PositionRebuild {
    # v3.0: replays all buys/sells of one ticker (average cost, see Core) and -
    # after a preview - replaces the position. Returns $true when it changed.
    # v4.5: -Silent = no dialogs (CSV import)
    param([string]$Ticker, $Owner = $null, [switch]$Silent)
    $sym = ([string]$Ticker).Trim().ToUpper()
    if (-not $sym) { return $false }
    $own = if ($null -ne $Owner) { $Owner } else { $form }
    $title = "Position neu berechnen"
    # v4.1: split events (bounded synchronous lookup, once per session)
    Ensure-SplitsLoaded -Tickers @($sym)
    $r = Get-PositionFromTransactions -Transactions $script:Transactions.ToArray() -Ticker $sym -Splits (Get-SplitMap)
    if ($null -eq $r) {
        if ($Silent) { return $false }
        [System.Windows.Forms.MessageBox]::Show($own, "Für $sym gibt es keine Kauf-/Verkaufsbuchungen.", $title,
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return $false
    }
    $old = if ($script:Portfolio.ContainsKey($sym)) { $script:Portfolio[$sym] } else { $null }
    $oldTxt = if ($null -ne $old) { "{0:N4} Stk @ {1:N4} {2}" -f $old.Shares, $old.AvgPrice, $old.Currency } else { "keine Position" }
    $newTxt = if ($r.Shares -gt 0) { "{0:N4} Stk @ {1:N4} {2}" -f $r.Shares, $r.AvgPrice, $r.Currency } else { "0 Stk - Position wird entfernt" }
    $notes = ""
    if ($r.Skipped -gt 0) { $notes += "`r`n- {0} Buchung(en) übersprungen (andere Währung als {1} oder Stück/Kurs = 0)" -f $r.Skipped, $r.Currency }
    if ($r.Clamped) { $notes += "`r`n- Ein Verkauf war größer als der Bestand und wurde begrenzt" }
    if ($r.Splits -gt 0) { $notes += "`r`n- {0} Aktiensplit(s) berücksichtigt (Stück und EK umgerechnet)" -f $r.Splits }
    $msg = ("{0}: aus {1} Buchung(en) neu berechnen (Durchschnittskosten)?`r`n`r`nAktuell:  {2}`r`nNeu:      {3}{4}`r`n`r`nHinweis: Werte, die im Portfolio-Editor direkt überschrieben wurden, sind nicht als Buchung erfasst und gehen dabei verloren." -f $sym, $r.Used, $oldTxt, $newTxt, $notes)
    if (-not $Silent) {
        $ans = [System.Windows.Forms.MessageBox]::Show($own, $msg, $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return $false }
    }

    if ($r.Shares -le 0) {
        [void]$script:Portfolio.Remove($sym)
    } else {
        $script:Portfolio[$sym] = [PSCustomObject]@{
            Ticker    = $sym
            Shares    = [double]$r.Shares
            AvgPrice  = [double]$r.AvgPrice
            Currency  = [string]$r.Currency
            BuyAmount = $(if ($null -ne $old) { [double]$old.BuyAmount } else { 0.0 })
            TargetAvg = $(if ($null -ne $old) { [double]$old.TargetAvg } else { 0.0 })
        }
    }
    Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
    Write-WidgetLog ("Position rebuilt from transactions: {0} {1} -> {2}" -f $sym, $oldTxt, $newTxt)
    Set-TransientStatus "Position $sym neu berechnet" 3
    return $true
}

# ------------------------------------------------------------------------------
# Yearly report (v4.0). FX histories (EURxxx=X, daily) are loaded once per
# session and currency; the calculation itself is Get-RealizedReport (Core).
# ------------------------------------------------------------------------------
$script:FxHistCache = @{}
# v4.1: split events per ticker (from the report's monthly or the analysis'
# daily history), shared by the yearly report, the rebuild and the analysis
$script:SplitCache = @{}

function Get-FxHistoryMap {
    $hist = @{}
    foreach ($k in $script:FxHistCache.Keys) { if ($null -ne $script:FxHistCache[$k].Hist) { $hist[$k] = $script:FxHistCache[$k].Hist } }
    return $hist
}

function Get-SplitMap {
    $m = @{}
    foreach ($k in $script:SplitCache.Keys) { $m[$k] = @($script:SplitCache[$k].Splits) }
    return $m
}

function Get-ReportYears {
    # Years with bookings (newest first) + the current year; default = newest
    # year with a sale or dividend
    $years = New-Object System.Collections.Generic.HashSet[int]
    [void]$years.Add((Get-Date).Year)
    $def = 0
    foreach ($t in $script:Transactions) {
        $d = [string]$t.Date
        if ($d -match '^(\d{4})-') {
            $y = [int]$Matches[1]
            [void]$years.Add($y)
            if ([string]$t.Type -in @("Verkauf", "Dividende") -and $y -gt $def) { $def = $y }
        }
    }
    if ($def -eq 0) { $def = (Get-Date).Year }
    return @{ Years = @($years | Sort-Object -Descending); Default = $def }
}

function Show-YearReport {
    param($Owner = $null)
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Jahresreport - realisierte Gewinne/Verluste und Dividenden" -W (S 940) -H (S 540) -Key "YearReport"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 760), (S 400))
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right

    $mkLbl = {
        param([string]$T, [int]$X, [int]$Y, [int]$W)
        $l = New-Object System.Windows.Forms.Label
        $l.SetBounds($X, $Y, $W, (S 18))
        $l.Text = $T
        $dlg.Controls.Add($l)
        return $l
    }
    [void](& $mkLbl "Jahr:" (S 12) (S 15) (S 36))
    $cbYear = New-Object System.Windows.Forms.ComboBox
    $cbYear.SetBounds((S 50), (S 12), (S 80), (S 24))
    $cbYear.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbYear.BackColor = $p.Input; $cbYear.ForeColor = $p.Text; $cbYear.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ry = Get-ReportYears
    foreach ($y in $ry.Years) { [void]$cbYear.Items.Add([string]$y) }
    $cbYear.SelectedIndex = [math]::Max(0, $cbYear.Items.IndexOf([string]$ry.Default))
    $dlg.Controls.Add($cbYear)

    [void](& $mkLbl "Basiswährung:" (S 144) (S 15) (S 92))
    $cbBase = New-Object System.Windows.Forms.ComboBox
    $cbBase.SetBounds((S 238), (S 12), (S 70), (S 24))
    $cbBase.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbBase.BackColor = $p.Input; $cbBase.ForeColor = $p.Accent; $cbBase.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    foreach ($c in (Get-DisplayCurrencies)) { [void]$cbBase.Items.Add($c) }
    Select-CurrencyInCombo -Combo $cbBase -Code ([string]$script:Config.ReportBase)
    if ($cbBase.SelectedIndex -lt 0) { $cbBase.SelectedIndex = 0 }
    $dlg.Controls.Add($cbBase)

    $btnCalc = New-Object System.Windows.Forms.Button
    $btnCalc.SetBounds((S 320), (S 10), (S 100), (S 27))
    Style-FlatButton -Btn $btnCalc -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnCalc.Text = "Berechnen"
    $dlg.Controls.Add($btnCalc)

    $lblInfo = & $mkLbl "" (S 430) (S 15) (S 498)
    $lblInfo.Anchor = $aT -bor $aL -bor $aR
    $lblInfo.AutoEllipsis = $true
    $lblInfo.ForeColor = $p.Muted

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.SetBounds((S 12), (S 44), (S 916), (S 340))
    $grid.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Style-DataGrid -Grid $grid
    foreach ($cd in @(@("Date", "Datum", 82), @("Ticker", "Ticker", 76), @("Type", "Typ", 72), @("Shares", "Stück", 70), @("Cur", "Whg", 44),
                      @("Amount", "Betrag (Whg)", 96), @("Proceeds", "Erlös", 92), @("Cost", "Einstand", 92), @("Fee", "Gebühr/Steuer", 96), @("Result", "Ergebnis", 96), @("Approx", "", 22))) {
        $ci = $grid.Columns.Add($cd[0], $cd[1])
        $grid.Columns[$ci].Width = S $cd[2]
        $grid.Columns[$ci].FillWeight = [float](S $cd[2])
        $grid.Columns[$ci].SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    }
    $grid.Columns["Proceeds"].ToolTipText = "Verkaufserlös bzw. Dividende brutto, in Basiswährung zum Kurs am Buchungstag"
    $grid.Columns["Cost"].ToolTipText = "Anteiliger Einstand (gleitender Durchschnitt in Basiswährung, Kaufgebühren enthalten)"
    $grid.Columns["Fee"].ToolTipText = "Verkaufsgebühr bzw. bei Dividenden einbehaltene Steuer/Gebühr"
    $grid.Columns["Approx"].ToolTipText = "~ = aktueller statt historischer Wechselkurs"
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dlg.Controls.Add($grid)

    $lblSum = New-Object System.Windows.Forms.Label
    $lblSum.SetBounds((S 12), (S 390), (S 700), (S 96))
    $lblSum.Anchor = $aB -bor $aL -bor $aR
    $lblSum.Font = $fontMono
    $dlg.Controls.Add($lblSum)

    $lblNote = New-Object System.Windows.Forms.Label
    $lblNote.SetBounds((S 12), (S 490), (S 700), (S 34))
    $lblNote.Anchor = $aB -bor $aL -bor $aR
    $lblNote.ForeColor = $p.Muted
    $lblNote.Text = "Hilfsrechnung aus deinen Buchungen, keine Steuerberatung. Maßgeblich sind die Abrechnungen bzw. Steuerreports deiner Bank/deines Brokers."
    $dlg.Controls.Add($lblNote)

    $btnCsv = New-Object System.Windows.Forms.Button
    $btnCsv.SetBounds((S 722), (S 496), (S 100), (S 28))
    $btnCsv.Anchor = $aB -bor $aR
    Style-FlatButton -Btn $btnCsv -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $btnCsv.Text = "CSV export"
    $btnCsv.Enabled = $false
    $dlg.Controls.Add($btnCsv)
    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.SetBounds((S 828), (S 496), (S 100), (S 28))
    $btnClose.Anchor = $aB -bor $aR
    Style-FlatButton -Btn $btnClose -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $btnClose.Text = "Schließen"
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnClose)
    $dlg.CancelButton = $btnClose

    $script:RepCtl = @{ Dlg = $dlg; Year = $cbYear; Base = $cbBase; Grid = $grid; Info = $lblInfo; Sum = $lblSum; Csv = $btnCsv; Calc = $btnCalc; Report = $null }

    $render = {
        param($Rep)
        $rc = $script:RepCtl
        if ($null -eq $rc -or $rc.Dlg.IsDisposed) { return }
        $rc.Report = $Rep
        $rc.Grid.Rows.Clear()
        foreach ($r in $Rep.Rows) {
            $ri = $rc.Grid.Rows.Add($r.Date, $r.Ticker, $r.Type, $(if ($r.Type -eq "Verkauf") { "{0:N4}" -f $r.Shares } else { "" }), $r.Currency,
                ("{0:N2}" -f $r.Amount), ("{0:N2}" -f $r.Proceeds), $(if ($r.Type -eq "Verkauf") { "{0:N2}" -f $r.Cost } else { "" }), ("{0:N2}" -f $r.Fee),
                ("{0:+0.00;-0.00;0.00}" -f $r.Result), $(if ($r.Approx) { "~" } else { "" }))
            $rc.Grid.Rows[$ri].Cells["Result"].Style.ForeColor = if ($r.Result -ge 0) { $colGreen } else { $colRed }
        }
        $t = $Rep.Totals
        $b = $Rep.Base
        $rc.Sum.Text = (("Verkäufe:  Gewinne {0,12:N2}   Verluste {1,12:N2}   Saldo {2,12:N2} {6}`r`n" +
                         "            (Verkaufsgebühren enthalten: {3:N2} {6})`r`n" +
                         "Dividenden: brutto  {4,12:N2}   Abzüge  {5,12:N2}   netto {7,12:N2} {6}`r`n" +
                         "Gesamt (Saldo Verkäufe + Dividenden netto): {8:+0.00;-0.00;0.00} {6}") -f
                         $t.Gains, $t.Losses, $t.SellNet, $t.SellFees, $t.DividendsGross, $t.DividendFees, $b, $t.DividendsNet, $t.Net)
        $rc.Sum.ForeColor = if ($t.Net -ge 0) { $colGreen } else { $colRed }
        $rows = @($Rep.Rows).Count
        $rc.Info.ForeColor = if (@($Rep.Warnings).Count -gt 0) { $script:Pal.Warn } else { $script:Pal.Muted }
        $rc.Info.Text = if (@($Rep.Warnings).Count -gt 0) { (@($Rep.Warnings) -join " | ") } else { "{0} Buchung(en) in {1}" -f $rows, $Rep.Year }
        Set-DynTip $rc.Info (@($Rep.Warnings) -join "`r`n")
        $rc.Csv.Enabled = ($rows -gt 0)
        $rc.Calc.Enabled = $true
    }
    $script:RepCtl.Render = $render

    $btnCalc.Add_Click({
        $rc = $script:RepCtl
        $year = [int][string]$rc.Year.SelectedItem
        $base = [string]$rc.Base.SelectedItem
        $script:Config.ReportBase = $base
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        $txs = $script:Transactions.ToArray()
        $need = @(Get-ReportCurrencies -Transactions $txs -Year $year -Base $base | Where-Object { -not $script:FxHistCache.ContainsKey($_) -or [int]$script:FxHistCache[$_].ToYear -lt $year })
        # v4.1: split events of every ticker with buys/sells (NVDA 10:1 etc.)
        $needSplit = @($txs | Where-Object { [string]$_.Type -in @("Kauf", "Verkauf") } | ForEach-Object { ([string]$_.Ticker).ToUpper() } | Sort-Object -Unique |
            Where-Object { -not $script:SplitCache.ContainsKey($_) -or [int]$script:SplitCache[$_].ToYear -lt $year })
        $fallback = @{}
        foreach ($k in $script:FxFromEur.Keys) { $fallback[$k] = [double]$script:FxFromEur[$k] }
        $compute = {
            param([int]$Y, [string]$B, $Txs, $Fb)
            $rep = Get-RealizedReport -Transactions $Txs -Year $Y -Base $B -History (Get-FxHistoryMap) -FallbackFromEur $Fb -Splits (Get-SplitMap)
            & $script:RepCtl.Render $rep
        }
        $script:RepCtl.Compute = $compute
        if ($need.Count -eq 0 -and $needSplit.Count -eq 0) { & $compute $year $base $txs $fallback; return }

        # Daily FX history from the earliest booking up to the end of the year
        $first = Get-EarliestBookingDate -Transactions $txs
        $from = if ($first) { [DateTime]::ParseExact($first, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture).AddDays(-10) } else { New-Object DateTime($year, 1, 1) }
        $to = (New-Object DateTime($year, 12, 31)).AddDays(2)
        if ($to -gt (Get-Date)) { $to = Get-Date }
        $p1 = ([DateTimeOffset]$from).ToUnixTimeSeconds()
        $p2 = ([DateTimeOffset]$to).ToUnixTimeSeconds()
        $urls = @{}
        foreach ($c in $need) { $urls[$c] = "https://query1.finance.yahoo.com/v8/finance/chart/EUR${c}=X?interval=1d&period1=$p1&period2=$p2" }
        $splitUrls = @{}
        foreach ($t in $needSplit) { $splitUrls[$t] = "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval=1mo&period1={1}&period2={2}&events=split" -f [Uri]::EscapeDataString($t), $p1, ([DateTimeOffset](Get-Date)).ToUnixTimeSeconds() }
        $rc.Calc.Enabled = $false
        $rc.Info.ForeColor = $script:Pal.Muted
        $rc.Info.Text = "Lade Wechselkurse und Splits: " + (@($need) + @($needSplit) -join ", ") + " ..."
        Start-FetchJob -Urls (@($urls.Values) + @($splitUrls.Values)) -MaxConcurrency 3 -Context @{ Urls = $urls; SplitUrls = $splitUrls; Year = $year; Base = $base; Txs = $txs; Fb = $fallback; From = $from.ToString("yyyy-MM-dd") } -OnComplete {
            param($Box, $Ctx)
            foreach ($c in @($Ctx.Urls.Keys)) {
                $h = ConvertFrom-YahooFxHistory -Json $Box.Results[$Ctx.Urls[$c]]
                if ($null -ne $h) { $script:FxHistCache[$c] = @{ Hist = $h; ToYear = $Ctx.Year; FromDate = $Ctx.From } }
                else { Write-WidgetLog "FX history for $c not available" "WARN" }
            }
            foreach ($t in @($Ctx.SplitUrls.Keys)) {
                $h = ConvertFrom-YahooDailyHistory -Json $Box.Results[$Ctx.SplitUrls[$t]]
                $old = $script:SplitCache[$t]
                if ($null -ne $h -and ($null -eq $old -or -not [bool]$old.Full)) { $script:SplitCache[$t] = @{ Splits = @($h.Splits); ToYear = (Get-Date).Year } }
            }
            if ($null -eq $script:RepCtl) { return }
            & $script:RepCtl.Compute $Ctx.Year $Ctx.Base $Ctx.Txs $Ctx.Fb
        }
    })

    $btnCsv.Add_Click({
        $rc = $script:RepCtl
        $rep = $rc.Report
        if ($null -eq $rep) { return }
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "CSV Datei (*.csv)|*.csv"
        $sfd.FileName = "jahresreport_{0}_{1}.csv" -f $rep.Year, $rep.Base
        if ($sfd.ShowDialog($rc.Dlg) -eq [System.Windows.Forms.DialogResult]::OK) {
            $inv = [System.Globalization.CultureInfo]::InvariantCulture
            $lines = New-Object System.Collections.Generic.List[string]
            $lines.Add(("Datum;Typ;Ticker;Stück;Währung;Betrag;Erlös {0};Einstand {0};Gebühr/Steuer {0};Ergebnis {0};Näherung" -f $rep.Base))
            foreach ($r in $rep.Rows) {
                $lines.Add(("{0};{1};{2};{3};{4};{5};{6};{7};{8};{9};{10}" -f $r.Date, $r.Type, (ConvertTo-CsvField $r.Ticker), ([double]$r.Shares).ToString($inv), $r.Currency,
                    ([math]::Round([double]$r.Amount, 4)).ToString($inv), ([math]::Round([double]$r.Proceeds, 2)).ToString($inv), ([math]::Round([double]$r.Cost, 2)).ToString($inv),
                    ([math]::Round([double]$r.Fee, 2)).ToString($inv), ([math]::Round([double]$r.Result, 2)).ToString($inv), $(if ($r.Approx) { "ja" } else { "" })))
            }
            $t = $rep.Totals
            $lines.Add("")
            foreach ($pair in @(@("Gewinne Verkäufe", $t.Gains), @("Verluste Verkäufe", $t.Losses), @("Saldo Verkäufe", $t.SellNet), @("Verkaufsgebühren (enthalten)", $t.SellFees),
                                @("Dividenden brutto", $t.DividendsGross), @("Dividenden Abzüge", $t.DividendFees), @("Dividenden netto", $t.DividendsNet), @("Gesamt", $t.Net))) {
                $lines.Add(("{0};{1}" -f $pair[0], ([math]::Round([double]$pair[1], 2)).ToString($inv)))
            }
            foreach ($w in @($rep.Warnings)) { $lines.Add(("Hinweis;{0}" -f (ConvertTo-CsvField $w))) }
            [System.IO.File]::WriteAllLines($sfd.FileName, $lines, [System.Text.Encoding]::UTF8)
            Set-TransientStatus "Jahresreport exportiert" 3
        }
        $sfd.Dispose()
    })

    $own = if ($null -ne $Owner) { $Owner } else { $form }
    $dlg.Add_Shown({ $script:RepCtl.Calc.PerformClick() })
    Enable-PrivacyMask $dlg
    [void]$dlg.ShowDialog($own)
    $script:RepCtl = $null
    $dlg.Dispose()
}

# ==============================================================================
# Portfolio analysis (v4.1): value history rebuilt from the bookings with a
# benchmark shadow portfolio, returns per position (XIRR), and the breakdown
# by position / currency / sector / country. Window: P key or Portfolio >
# "Analyse". Data: daily closes since the first booking, daily FX, profiles.
# ==============================================================================
$script:AnaHist = @{}     # symbol -> @{ Hist; At; From }
$script:AnaCtl  = $null   # controls + model while the window is open

function Get-AnalysisBase {
    $b = Get-NormalizedCurrencyCode ([string]$script:Config.AnalysisBase)
    if (-not $b) { $b = [string]$script:Config.Currency }
    return $b
}

function Get-AnalysisSymbols {
    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($k in $script:Portfolio.Keys) { [void]$set.Add(([string]$k).ToUpper()) }
    foreach ($t in $script:Transactions) { if ([string]$t.Type -in @("Kauf", "Verkauf")) { [void]$set.Add(([string]$t.Ticker).ToUpper()) } }
    return @($set | Sort-Object)
}

function Get-AnalysisPriceNow {
    # Current price in Base: live quote, else the last daily close; NaN if unknown
    param([string]$Sym, [string]$Base)
    $q = $script:QuoteStore[$Sym]
    if ($null -ne $q -and [double]$q.Price -gt 0) { return (Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $Base) }
    $h = $script:AnaHist[$Sym]
    if ($null -ne $h -and $null -ne $h.Hist -and $h.Hist.Closes.Count -gt 0) {
        return (Convert-CurrencyValue -Amount ([double]$h.Hist.Closes[$h.Hist.Closes.Count - 1]) -FromCurrency ([string]$h.Hist.Currency) -ToCurrency $Base)
    }
    return [double]::NaN
}

function Get-InstrumentCurrency {
    param([string]$Sym)
    $q = $script:QuoteStore[$Sym]
    if ($null -ne $q -and $q.Currency) { return (Get-NormalizedCurrencyCode ([string]$q.Currency)) }
    $h = $script:AnaHist[$Sym]
    if ($null -ne $h -and $null -ne $h.Hist) { return [string]$h.Hist.Currency }
    if ($script:Portfolio.ContainsKey($Sym)) { return [string]$script:Portfolio[$Sym].Currency }
    return ""
}

function Test-FxHistFresh {
    param([string]$Cur, [string]$From)
    if (-not $script:FxHistCache.ContainsKey($Cur)) { return $false }
    $e = $script:FxHistCache[$Cur]
    if ($null -eq $e.Hist -or [int]$e.ToYear -lt (Get-Date).Year -or -not $e.FromDate) { return $false }
    return ([string]::CompareOrdinal([string]$e.FromDate, $From) -le 0)
}

