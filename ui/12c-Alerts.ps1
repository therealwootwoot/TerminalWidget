# TerminalWidget UI part 12c (Alerts, notices, summary, V7.9) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM.

# ==============================================================================
# combined alert: two conditions, both must be true
# ==============================================================================
function Show-ComboAlertDialog {
    $dlg = New-DialogForm -Title "Kombinierter Alarm" -W (S 460) -H (S 250) -Key "ComboAlert"
    [void](New-V8Label $dlg (Tr "Der Alarm löst erst aus, wenn beide Bedingungen gleichzeitig erfüllt sind.") (S 12) (S 10) (S 436) -Muted)
    [void](New-V8Label $dlg (Tr "Ticker") (S 12) (S 42) (S 110))
    $tSym = New-V8Text $dlg ([string]$script:Config.ActiveTicker).ToUpper() (S 130) (S 38) (S 150)
    [void](New-V8Label $dlg (Tr "Bedingung 1") (S 12) (S 74) (S 110))
    $c1 = New-V8Combo $dlg @(Get-AlertConditions) ">=" (S 130) (S 70) (S 150)
    $v1 = New-V8Text $dlg "" (S 290) (S 70) (S 158)
    [void](New-V8Label $dlg (Tr "UND Bedingung 2") (S 12) (S 106) (S 110))
    $c2 = New-V8Combo $dlg @(Get-AlertConditions) "Volumen x" (S 130) (S 102) (S 150)
    $v2 = New-V8Text $dlg "" (S 290) (S 102) (S 158)
    [void](New-V8Label $dlg (Tr "Notiz") (S 12) (S 138) (S 110))
    $tNote = New-V8Text $dlg "" (S 130) (S 134) (S 318)
    $err = New-V8Label $dlg "" (S 12) (S 166) (S 436) (S 36)
    $err.ForeColor = $script:Pal.Warn
    $ok = New-V8Button $dlg (Tr "Anlegen") (S 248) (S 210) (S 96)
    $no = New-V8Button $dlg (Tr "Abbrechen") (S 352) (S 210) (S 96)
    $no.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.CancelButton = $no
    $script:ComboCtl = @{ Dlg = $dlg; Sym = $tSym; C1 = $c1; V1 = $v1; C2 = $c2; V2 = $v2; Note = $tNote; Err = $err }
    $ok.Add_Click({
        $cc = $script:ComboCtl
        $a = [string]$cc.C1.SelectedItem; $b = [string]$cc.C2.SelectedItem
        $why = Test-AlertCombination -First $a -Second $b
        if ($why) { $cc.Err.Text = Tr $why; return }
        $vals = @()
        foreach ($p in @(@($a, $cc.V1.Text), @($b, $cc.V2.Text))) {
            if ((Get-AlertKind $p[0]) -eq "SMA") { $vals += 0.0; continue }
            if (-not $p[1].Trim() -or -not (Test-DecimalInput $p[1])) { $cc.Err.Text = "{0}: {1}" -f $p[0], (Get-AlertTargetHint $p[0]); return }
            $vals += (Parse-DecimalInput $p[1])
        }
        $res = New-AlertChecked -RawTicker $cc.Sym.Text -Cond $a -Value $vals[0] -Note $cc.Note.Text.Trim() -Cond2 $b -Value2 $vals[1]
        if ($res -eq "") { $cc.Dlg.Close() } elseif ($res -ne "CANCEL") { $cc.Err.Text = $res }
    })
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
    $script:ComboCtl = $null
}

# ==============================================================================
# alert templates for a watchlist group or the depot
# ==============================================================================
function Get-AlertTemplates { return @(@($script:Config.AlertTemplates) | Where-Object { $null -ne $_ -and $_.Name }) }

function Get-TemplateScopes {
    # display name -> tickers
    $out = [ordered]@{}
    $out[(Tr "Depot-Positionen")] = @($script:Portfolio.Keys | ForEach-Object { ([string]$_).ToUpper() } | Sort-Object)
    $out[(Tr "Ganze Watchlist")] = @($script:Config.Watchlist | ForEach-Object { ([string]$_).ToUpper() })
    foreach ($g in @($script:Config.WatchGroups)) {
        if ($null -ne $g -and $g.Name) { $out[((Tr "Gruppe") + ": " + [string]$g.Name)] = @($g.Symbols | ForEach-Object { ([string]$_).ToUpper() }) }
    }
    return $out
}

function Format-TemplateText {
    param($T)
    $s = if ((Get-AlertKind ([string]$T.Condition)) -eq "SMA") { [string]$T.Condition } else { "{0} {1:0.##}" -f $T.Condition, [double]$T.Value }
    if ([string]$T.Condition2) {
        $s += "  " + (Tr "UND") + "  " + $(if ((Get-AlertKind ([string]$T.Condition2)) -eq "SMA") { [string]$T.Condition2 } else { "{0} {1:0.##}" -f $T.Condition2, [double]$T.Value2 })
    }
    return $s
}

function Add-TemplateAlerts {
    # creates the alerts of a template; returns how many
    param($Template, [string[]]$Symbols)
    $cond = [string]$Template.Condition; $cond2 = [string]$Template.Condition2
    $held = @($script:Portfolio.Keys | ForEach-Object { ([string]$_).ToUpper() })
    $todo = @(Get-TemplateTargets -Symbols $Symbols -Alerts $script:Alerts.ToArray() -Condition $cond -Value ([double]$Template.Value) -Condition2 $cond2 -Value2 ([double]$Template.Value2) -Held $held)
    foreach ($s in $todo) {
        [void](Add-WidgetAlert -Ticker $s -Condition $cond -Target ([double]$Template.Value) -Currency (Get-AlertCurrency -Kind (Get-AlertKind $cond) -Symbol $s) -Note ([string]$Template.Name) `
            -Condition2 $cond2 -Target2 ([double]$Template.Value2) -Currency2 $(if ($cond2) { Get-AlertCurrency -Kind (Get-AlertKind $cond2) -Symbol $s } else { "" }) -NoConfirm)
    }
    return $todo.Count
}

function Update-TemplateList {
    $tc = $script:TplCtl
    $tc.List.Items.Clear()
    foreach ($t in (Get-AlertTemplates)) { [void]$tc.List.Items.Add(("{0}:  {1}" -f $t.Name, (Format-TemplateText $t))) }
    if ($tc.List.Items.Count -gt 0) { $tc.List.SelectedIndex = 0 }
}

function Show-AlertTemplatesDialog {
    $dlg = New-DialogForm -Title "Alarm-Vorlagen" -W (S 560) -H (S 400) -Key "AlertTemplates"
    [void](New-V8Label $dlg (Tr "Eine Vorlage legt denselben Alarm für viele Ticker an. Nur Bedingungen ohne festen Kurs.") (S 12) (S 8) (S 536) -Muted)
    $lb = New-Object System.Windows.Forms.ListBox
    $lb.SetBounds((S 12), (S 32), (S 536), (S 130)); $lb.BackColor = $script:Pal.Input; $lb.ForeColor = $script:Pal.Text; $lb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($lb)
    $scopes = Get-TemplateScopes
    [void](New-V8Label $dlg (Tr "Anwenden auf") (S 12) (S 176) (S 100))
    $cScope = New-V8Combo $dlg @($scopes.Keys) "" (S 116) (S 172) (S 216)
    $bApply = New-V8Button $dlg (Tr "Anwenden ...") (S 340) (S 171) (S 110)
    $bDel = New-V8Button $dlg (Tr "Löschen") (S 458) (S 171) (S 90)
    [void](New-V8Label $dlg (Tr "Neue Vorlage") (S 12) (S 218) (S 200))
    [void](New-V8Label $dlg (Tr "Name") (S 12) (S 244) (S 100))
    $tName = New-V8Text $dlg "" (S 116) (S 240) (S 216)
    $conds = @(Get-TemplateConditions)
    [void](New-V8Label $dlg (Tr "Bedingung 1") (S 12) (S 276) (S 100))
    $c1 = New-V8Combo $dlg $conds "RSI >=" (S 116) (S 272) (S 140)
    $v1 = New-V8Text $dlg "70" (S 264) (S 272) (S 68)
    [void](New-V8Label $dlg (Tr "UND (optional)") (S 12) (S 308) (S 100))
    $c2 = New-V8Combo $dlg (@("-") + $conds) "-" (S 116) (S 304) (S 140)
    $v2 = New-V8Text $dlg "" (S 264) (S 304) (S 68)
    $bAdd = New-V8Button $dlg (Tr "Vorlage speichern") (S 340) (S 304) (S 150)
    $msg = New-V8Label $dlg "" (S 12) (S 338) (S 430) (S 50)
    $msg.ForeColor = $script:Pal.Warn
    $no = New-V8Button $dlg (Tr "Schließen") (S 452) (S 360) (S 96)
    $no.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.CancelButton = $no
    $script:TplCtl = @{ Dlg = $dlg; List = $lb; Scope = $cScope; Scopes = $scopes; Name = $tName; C1 = $c1; V1 = $v1; C2 = $c2; V2 = $v2; Msg = $msg }
    Update-TemplateList
    $bAdd.Add_Click({
        $tc = $script:TplCtl
        $name = $tc.Name.Text.Trim()
        if (-not $name -or $name.Length -gt 40) { $tc.Msg.Text = Tr "Bitte einen Namen eingeben (höchstens 40 Zeichen)."; return }
        $a = [string]$tc.C1.SelectedItem
        $b = [string]$tc.C2.SelectedItem; if ($b -eq "-") { $b = "" }
        if ($b) { $why = Test-AlertCombination -First $a -Second $b; if ($why) { $tc.Msg.Text = Tr $why; return } }
        $vals = @()
        foreach ($p in @(@($a, $tc.V1.Text), @($b, $tc.V2.Text))) {
            if (-not $p[0] -or (Get-AlertKind $p[0]) -eq "SMA") { $vals += 0.0; continue }
            if (-not $p[1].Trim() -or -not (Test-DecimalInput $p[1])) { $tc.Msg.Text = "{0}: {1}" -f $p[0], (Get-AlertTargetHint $p[0]); return }
            $x = Parse-DecimalInput $p[1]
            $bad = Test-AlertValue -Condition $p[0] -Value $x
            if ($bad) { $tc.Msg.Text = "{0}: {1}" -f $p[0], $bad; return }
            $vals += $x
        }
        $t = [PSCustomObject]@{ Name = $name; Condition = $a; Value = $vals[0]; Condition2 = $b; Value2 = $vals[1] }
        $script:Config.AlertTemplates = @(@(Get-AlertTemplates | Where-Object { [string]$_.Name -ne $name })) + @($t)
        Save-Config
        $tc.Msg.Text = ""
        Update-TemplateList
    })
    $bDel.Add_Click({
        $tc = $script:TplCtl; $i = $tc.List.SelectedIndex
        $all = @(Get-AlertTemplates)
        if ($i -lt 0 -or $i -ge $all.Count) { return }
        $name = [string]$all[$i].Name
        $script:Config.AlertTemplates = @($all | Where-Object { [string]$_.Name -ne $name })
        Save-Config
        Update-TemplateList
    })
    $bApply.Add_Click({
        $tc = $script:TplCtl; $i = $tc.List.SelectedIndex
        $all = @(Get-AlertTemplates)
        if ($i -lt 0 -or $i -ge $all.Count) { $tc.Msg.Text = Tr "Erst eine Vorlage wählen oder speichern."; return }
        $syms = @($tc.Scopes[[string]$tc.Scope.SelectedItem])
        $t = $all[$i]
        $held = @($script:Portfolio.Keys | ForEach-Object { ([string]$_).ToUpper() })
        $todo = @(Get-TemplateTargets -Symbols $syms -Alerts $script:Alerts.ToArray() -Condition ([string]$t.Condition) -Value ([double]$t.Value) -Condition2 ([string]$t.Condition2) -Value2 ([double]$t.Value2) -Held $held)
        if ($todo.Count -eq 0) { $tc.Msg.Text = Tr "Nichts anzulegen: Die Alarme gibt es schon, oder es fehlen Positionen."; return }
        if (-not (Confirm-Action -Text (("{0}: {1}`r`n`r`n" -f $t.Name, (Format-TemplateText $t)) + ((Tr "{0} Alarme anlegen? Bereits erfüllte lösen sofort aus.") -f $todo.Count)) -Title (Tr "Alarm-Vorlagen"))) { return }
        $n = Add-TemplateAlerts -Template $t -Symbols $syms
        $tc.Msg.Text = (Tr "{0} Alarme angelegt.") -f $n
        Refresh-AllMarketData
        Evaluate-GlobalAlerts
        Update-AllUiViews
    })
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
    $script:TplCtl = $null
}

# ==============================================================================
# lead time of the earnings / ex-dividend notices
# ==============================================================================
function Show-NoticeSettingsDialog {
    $sd = New-StandardDialog -Title "Vorwarnzeit für Termine" -Subtitle "Hinweise für Positionen im Depot." -W 420 -BodyH 80 -OkText "Speichern"
    $choices = [ordered]@{ (Tr "Aus") = -1; (Tr "Am selben Tag") = 0; (Tr "1 Tag vorher") = 1; (Tr "2 Tage vorher") = 2; (Tr "3 Tage vorher") = 3; (Tr "7 Tage vorher") = 7; (Tr "14 Tage vorher") = 14 }
    $find = { param([int]$v) foreach ($k in $choices.Keys) { if ($choices[$k] -eq $v) { return $k } } return (Tr "Aus") }
    $e0 = if ([bool]$script:Config.NotifyEarnings) { [int]$script:Config.EarningsLeadDays } else { -1 }
    [void](New-V8Label $sd.Body (Tr "Quartalszahlen") 0 (S 4) (S 130))
    $ce = New-V8Combo $sd.Body @($choices.Keys) (& $find $e0) (S 140) 0 (S 220)
    [void](New-V8Label $sd.Body (Tr "Ex-Dividende") 0 (S 40) (S 130))
    $cx = New-V8Combo $sd.Body @($choices.Keys) (& $find ([int]$script:Config.ExDivLeadDays)) (S 140) (S 36) (S 220)
    if ($sd.Dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $e = [int]$choices[[string]$ce.SelectedItem]
        $script:Config.NotifyEarnings = ($e -ge 0)
        if ($e -ge 0) { $script:Config.EarningsLeadDays = $e }
        $script:Config.ExDivLeadDays = [int]$choices[[string]$cx.SelectedItem]
        Save-Config
        Check-EarningsNotifications
    }
    $sd.Dlg.Dispose()
}

# ==============================================================================
# calendar export
# ==============================================================================
function Export-CalendarIcs {
    param([string[]]$Symbols, [int]$Days = 90, [string]$Path = "")
    $ev = @(Get-EventCalendar -Events $script:Events -Symbols $Symbols -Days $Days)
    if ($ev.Count -eq 0) { Set-TransientStatus (Tr "Keine Termine zum Exportieren") 4; return 0 }
    $items = @($ev | ForEach-Object { [PSCustomObject]@{ Date = $_.Date; Ticker = $_.Ticker; Kind = (Tr ([string]$_.Kind)) } })
    if (-not $Path) {
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "Kalender (*.ics)|*.ics"
        $sfd.FileName = "TerminalWidget-Termine.ics"
        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $Path = $sfd.FileName }
        $sfd.Dispose()
        if (-not $Path) { return 0 }
    }
    try {
        # without BOM: some calendar programs refuse it
        [System.IO.File]::WriteAllText($Path, (ConvertTo-IcsText -Events $items), (New-Object System.Text.UTF8Encoding($false)))
        Set-TransientStatus ((Tr "{0} Termine exportiert") -f $items.Count) 4
        return $items.Count
    } catch {
        Show-InfoBox ((Tr "Export fehlgeschlagen:") + " " + $_.Exception.Message) (Tr "Kalender")
        return 0
    }
}

function Add-CalendarExportButton {
    # extra button in the calendar window
    $ic = $script:InfoCtl
    if ($null -eq $ic -or $null -ne $ic.IcsButton) { return }
    $close = $ic.Dlg.CancelButton
    $b = New-V8Button $ic.Dlg (Tr "Als .ics speichern ...") ($close.Left - (S 160)) $close.Top (S 150)
    $b.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $ic.Footer.Width = [math]::Max((S 60), $b.Left - $ic.Footer.Left - (S 8))
    $b.Add_Click({ [void](Export-CalendarIcs -Symbols $script:InfoCtl.Syms -Days $script:InfoCtl.Days) })
    $ic.IcsButton = $b
}

# ==============================================================================
# daily / weekly summary (a window; nothing is sent)
# ==============================================================================
function Get-SummarySymbols {
    $set = New-Object System.Collections.Generic.List[string]
    foreach ($s in (@($script:Portfolio.Keys) + @($script:Config.Watchlist))) {
        $u = ([string]$s).ToUpper()
        if ($u -and -not $set.Contains($u)) { $set.Add($u) }
    }
    return $set.ToArray()
}

function Get-PeriodChange {
    # change in % of one ticker over the period; NaN when it cannot be said
    param([string]$Sym, [string]$Period)
    $q = $script:QuoteStore[$Sym]
    if ($null -eq $q -or [double]$q.Price -le 0) { return [double]::NaN }
    if ($Period -eq "Day") { return [double]$q.ChangePct }
    $e = $script:DailyCache[$Sym]
    if ($null -eq $e -or [string]$e.Currency -ne [string]$q.Currency) { return [double]::NaN }
    $ref = Get-ReferenceClose -Dates @($e.Dates) -Closes ([double[]]@($e.Close)) -DaysBack 7
    if ([double]::IsNaN($ref)) { return [double]::NaN }
    return (([double]$q.Price / $ref - 1.0) * 100.0)
}

function Get-SummaryRows {
    param([string]$Period = "Day")
    $rows = @()
    $base = [string]$script:Config.Currency
    $priv = [bool]$script:Config.PrivacyMode
    $since = if ($Period -eq "Week") { (Get-Date).AddDays(-7) } else { (Get-Date).Date }
    $syms = @(Get-SummarySymbols)
    $row = { param($a, $b, $c, $color = $null, $tag = $null) @{ Cells = @($a, $b, $c); Color = $color; Tag = $tag } }

    # depot: today's positions, valued at today's exchange rate
    $now = 0.0; $then = 0.0; $missing = 0; $count = 0
    foreach ($k in @($script:Portfolio.Keys)) {
        $u = ([string]$k).ToUpper()
        $sh = [double]$script:Portfolio[$k].Shares
        if ($sh -le 0) { continue }
        $count++
        $q = $script:QuoteStore[$u]
        $pct = Get-PeriodChange -Sym $u -Period $Period
        if ($null -eq $q -or [double]::IsNaN($pct) -or $pct -le -100) { $missing++; continue }
        $v = $sh * [double](Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $base)
        $now += $v
        $then += $v / (1.0 + $pct / 100.0)
    }
    $label = if ($Period -eq "Week") { Tr "7 Tage" } else { Tr "Heute" }
    if ($count -eq 0) { $rows += & $row (Tr "Depot") (Tr "keine Positionen") "" }
    elseif ($then -gt 0) {
        $diff = $now - $then
        $txt = Protect-Amount -Text ("{0:+#,##0.00;-#,##0.00;0.00} {1}" -f $diff, $base) -On $priv
        $col = if ($diff -ge 0) { $colGreen } else { $colRed }
        $rows += & $row (Tr "Depot") $label ("{0}  ({1:+0.00;-0.00;0.00}%)" -f $txt, ($diff / $then * 100.0)) $col
        $rows += & $row (Tr "Depot") (Tr "Wert jetzt") (Protect-Amount -Text ("{0:N2} {1}" -f $now, $base) -On $priv)
        if ($missing -gt 0) { $rows += & $row (Tr "Depot") (Tr "Hinweis") ((Tr "{0} von {1} Positionen fehlen (keine Kurse für den Zeitraum)") -f $missing, $count) $script:Pal.Warn }
    } else { $rows += & $row (Tr "Depot") $label (Tr "noch keine Kurse für den Zeitraum") $script:Pal.Warn }

    $items = @($syms | ForEach-Object { @{ Ticker = $_; Pct = (Get-PeriodChange -Sym $_ -Period $Period) } })
    $m = Select-SummaryMovers -Items $items -Top 3
    foreach ($x in @($m.Up)) { $rows += & $row (Tr "Stärkste") $x.Ticker ("{0:+0.00}%" -f [double]$x.Pct) $colGreen $x.Ticker }
    foreach ($x in @($m.Down)) { $rows += & $row (Tr "Schwächste") $x.Ticker ("{0:0.00}%" -f [double]$x.Pct) $colRed $x.Ticker }
    $unknown = @($items | Where-Object { [double]::IsNaN([double]$_.Pct) }).Count
    if ($unknown -gt 0) { $rows += & $row (Tr "Bewegungen") (Tr "Hinweis") ((Tr "für {0} Ticker fehlen Kurse") -f $unknown) $script:Pal.Warn }

    $ev = @(Get-EventCalendar -Events $script:Events -Symbols $syms -Days 7)
    foreach ($c in @($ev | Select-Object -First 12)) { $rows += & $row (Tr "Termine") $c.Ticker ("{0}  {1}" -f (Format-IsoDateDe $c.Date), (Tr ([string]$c.Kind))) $null $c.Ticker }
    if ($ev.Count -eq 0) { $rows += & $row (Tr "Termine") (Tr "nächste 7 Tage") (Tr "keine bekannt") }

    $hits = @($script:AlertLog | Where-Object {
        $t = [DateTime]::MinValue
        [DateTime]::TryParse([string]$_.At, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$t) -and $t -ge $since })
    foreach ($h in @($hits | Select-Object -Last 8)) { $rows += & $row (Tr "Alarme") ([string]$h.Ticker) ([string]$h.Text) $script:Pal.Warn }

    $news = @(Get-NewsPool | Where-Object { $null -ne $_.Time -and [DateTime]$_.Time -ge $since } | Sort-Object -Property @{ Expression = { [DateTime]$_.Time }; Descending = $true } | Select-Object -First 8)
    foreach ($n in $news) { $rows += & $row (Tr "Schlagzeilen") ((@($n.Syms) | Select-Object -First 2) -join ", ") ([string]$n.Title) }
    if ($news.Count -eq 0) { $rows += & $row (Tr "Schlagzeilen") "" (Tr "keine geladen") }
    return @($rows)
}

function Show-SummaryDialog {
    param([string]$Period = "Day")
    $title = "Zusammenfassung"
    Show-InfoGrid -Title $title -Columns @("Bereich", "Was", "Wert") -Weights @(90, 110, 360) -W 720 -H 560 -Extra @{ Period = $Period } -OnDouble {
        param($Tag)
        $script:InfoCtl.Dlg.Close()
        Switch-ActiveTicker -NewTicker ([string]$Tag) -SkipResolve $true
    } -OnShown {
        $ic = $script:InfoCtl
        $ic.Footer.Visible = $false
        $y = $ic.Dlg.CancelButton.Top
        $bottom = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
        $cp = New-V8Combo $ic.Dlg @((Tr "Heute"), (Tr "7 Tage")) $(if ($ic.Period -eq "Week") { Tr "7 Tage" } else { Tr "Heute" }) (S 12) ($y + (S 2)) (S 100)
        $lbl = New-V8Label $ic.Dlg (Tr "Von selbst zeigen:") (S 124) ($y + (S 6)) (S 118) -Muted
        $modes = @("Off", "Daily", "Weekly")
        $names = @((Tr "nie"), (Tr "täglich"), (Tr "wöchentlich"))
        $ca = New-V8Combo $ic.Dlg $names $names[[math]::Max(0, [array]::IndexOf([string[]]$modes, [string]$script:Config.SummaryAuto))] (S 246) ($y + (S 2)) (S 110)
        foreach ($c in @($cp, $lbl, $ca)) { $c.Anchor = $bottom }
        $cp.Add_SelectedIndexChanged({
            param($sender, $e)
            $script:InfoCtl.Period = if ($sender.SelectedIndex -eq 1) { "Week" } else { "Day" }
            Set-InfoRows -Rows (Get-SummaryRows -Period $script:InfoCtl.Period)
        })
        $ca.Add_SelectedIndexChanged({ param($sender, $e) $script:Config.SummaryAuto = @("Off", "Daily", "Weekly")[[math]::Max(0, $sender.SelectedIndex)]; Save-Config })
        if (-not $script:SmokeMode) { Request-DailyBars -Symbols @(Get-SummarySymbols) }
        Set-InfoRows -Rows (Get-SummaryRows -Period $ic.Period)
    }
}

# shows the summary by itself when switched on (once per day or week)
$script:SummaryTimer = New-Object System.Windows.Forms.Timer
$script:SummaryTimer.Interval = 60000
$script:SummaryTimer.Add_Tick({
    $mode = [string]$script:Config.SummaryAuto
    if ($script:SmokeMode -or $script:IsClosing -or -not $form.Visible -or -not (Test-SummaryDue -Mode $mode -LastShown ([string]$script:Config.SummaryLastShown))) { return }
    # not while another window of the widget is open
    if ([System.Windows.Forms.Application]::OpenForms.Count -gt 1 -or $script:QuoteStore.Count -eq 0) { return }
    $script:Config.SummaryLastShown = (Get-Date).ToString("yyyy-MM-dd")
    Save-Config
    Show-SummaryDialog -Period $(if ($mode -eq "Weekly") { "Week" } else { "Day" })
})
$script:SummaryTimer.Start()

# ---- menu ----
Add-BarLine $mbTools
[void](Add-BarItem $mbTools "Zusammenfassung ..." { Show-SummaryDialog })
[void](Add-BarItem $mbTools "Kombinierter Alarm ..." { Show-ComboAlertDialog })
[void](Add-BarItem $mbTools "Alarm-Vorlagen ..." { Show-AlertTemplatesDialog })
[void](Add-BarItem $mbTools "Vorwarnzeit für Termine ..." { Show-NoticeSettingsDialog })
[void](Add-BarItem $mbTools "Termine als .ics speichern ..." { [void](Export-CalendarIcs -Symbols @(Get-EventSymbols)) })

# ==============================================================================
# alert overview (v10.8): every alert with its distance to firing, edit in place
# ==============================================================================
function Format-AlertNow {
    # current value of an evaluation, in the unit of the condition
    param([string]$Condition, [double]$Value, [string]$Currency)
    if ([double]::IsNaN($Value)) { return [string][char]0x2013 }
    switch (Get-AlertKind $Condition) {
        "RSI"   { return ("{0:N1}" -f $Value) }
        "VOL"   { return ("{0:N1}x" -f $Value) }
        "PRICE" { return ("{0:N2} {1}" -f $Value, $Currency) }
        "TREND" { return ("{0:N2} {1}" -f $Value, $Currency) }
        "PFVAL" { return (Protect-Amount -Text ("{0:N0} {1}" -f $Value, $Currency) -On ([bool]$script:Config.PrivacyMode)) }
        default { return ("{0:+0.00;-0.00}%" -f $Value) }
    }
}

function Format-AlertGap {
    param($Distance)
    if ($null -eq $Distance -or -not $Distance.Ok) { return [string][char]0x2013 }
    if ($Distance.Score -eq 0) { return (Tr "erfüllt") }
    $u = switch ($Distance.Unit) { "P" { " " + (Tr "Punkte") } "x" { "x" } default { "%" } }
    return ("{0:+0.0;-0.0}{1}" -f $Distance.Gap, $u)
}

function Get-AlertOverviewRows {
    # Filter: All / Active / Hit / Paused / Expired. Active ones first, closest on top.
    param([string]$Filter = "All")
    $rank = @{ Active = 0; Hit = 1; Paused = 2; Expired = 3 }
    $rows = @()
    foreach ($a in @($script:Alerts.ToArray())) {
        $status = Get-AlertStatusName -Alert $a
        if ($Filter -ne "All" -and $status -ne $Filter) { continue }
        $st = Get-AlertSingleState -Alert $a
        $dist = $null; $now = [string][char]0x2013; $tip = ""
        if ($st.Ok) {
            $dist = Get-AlertDistance -Condition ([string]$a.Condition) -Target ([double]$a.TargetPrice) -Value ([double]$st.Value) -Met ([bool]$st.Met)
            $now = Format-AlertNow -Condition ([string]$a.Condition) -Value ([double]$st.Value) -Currency ([string]$a.Currency)
            $tip = [string]$st.Text
            if ([string]$a.Condition2) {
                # combined: the condition that is further away decides
                $s2 = Get-AlertSingleState -Alert ([PSCustomObject]@{ Ticker = [string]$a.Ticker; Condition = [string]$a.Condition2; TargetPrice = [double]$a.Target2; Currency = [string]$a.Currency2; Peak = 0.0 })
                if (-not $s2.Ok) { $dist = $null }
                else {
                    $d2 = Get-AlertDistance -Condition ([string]$a.Condition2) -Target ([double]$a.Target2) -Value ([double]$s2.Value) -Met ([bool]$s2.Met)
                    if (-not $d2.Ok -or $d2.Score -gt $dist.Score) { $dist = $d2 }
                    $now += " | " + (Format-AlertNow -Condition ([string]$a.Condition2) -Value ([double]$s2.Value) -Currency ([string]$a.Currency2))
                    $tip += "`r`n" + [string]$s2.Text
                }
            }
        }
        $what = Format-AlertBody -Alert $a
        if ([string]$a.Condition2) { $what += " & " + (Format-AlertBody -Alert ([PSCustomObject]@{ Condition = [string]$a.Condition2; TargetPrice = [double]$a.Target2; Currency = [string]$a.Currency2; Peak = 0.0 })) }
        if ([bool]$script:Config.PrivacyMode -and (Get-AlertKind ([string]$a.Condition)) -eq "PFVAL") { $what = Hide-AmountsInText $what; $tip = Hide-AmountsInText $tip }
        if ($status -in @("Hit", "Expired")) { $dist = $null }
        $score = if ($null -ne $dist -and $dist.Ok) { [double]$dist.Score } else { [double]::MaxValue }
        $rows += [PSCustomObject]@{ Alert = $a; Id = [string]$a.Id; Status = $status; Rank = $rank[$status]; Score = $score; What = $what; Now = $now; Gap = (Format-AlertGap $dist); Tip = $tip }
    }
    return @($rows | Sort-Object Rank, Score, @{ Expression = { [string]$_.Alert.Ticker } })
}

function Get-AlertIndex {
    param([string]$Id)
    for ($i = 0; $i -lt $script:Alerts.Count; $i++) { if ([string]$script:Alerts[$i].Id -eq $Id) { return $i } }
    return -1
}

function Show-AlertEditDialog {
    param($Alert, $Owner = $null)
    if ($null -eq $Alert) { return $false }
    $c2 = [string]$Alert.Condition2
    $h = if ($c2) { 298 } else { 266 }
    $dlg = New-DialogForm -Title (Tr "Alarm bearbeiten") -W (S 460) -H (S $h) -Key ""
    [void](New-V8Label $dlg ("{0}  -  {1}" -f $Alert.Ticker, (Format-AlertBody -Alert $Alert)) (S 12) (S 10) (S 436))
    $y = 40
    [void](New-V8Label $dlg ((Tr "Wert") + " (" + [string]$Alert.Condition + ")") (S 12) (S ($y + 4)) (S 160))
    $v1 = New-V8Text $dlg $(if ((Get-AlertKind ([string]$Alert.Condition)) -in @("SMA", "TREND")) { "" } else { ([double]$Alert.TargetPrice).ToString("0.####") }) (S 180) (S $y) (S 268)
    $v1.Enabled = ((Get-AlertKind ([string]$Alert.Condition)) -notin @("SMA", "TREND")); $v1.AccessibleName = Tr "Wert"
    $y += 32
    $v2 = $null
    if ($c2) {
        [void](New-V8Label $dlg ((Tr "Wert") + " (" + $c2 + ")") (S 12) (S ($y + 4)) (S 160))
        $v2 = New-V8Text $dlg $(if ((Get-AlertKind $c2) -in @("SMA", "TREND")) { "" } else { ([double]$Alert.Target2).ToString("0.####") }) (S 180) (S $y) (S 268)
        $v2.Enabled = ((Get-AlertKind $c2) -notin @("SMA", "TREND")); $v2.AccessibleName = (Tr "Wert") + " 2"
        $y += 32
    }
    [void](New-V8Label $dlg (Tr "Notiz") (S 12) (S ($y + 4)) (S 160))
    $tNote = New-V8Text $dlg ([string]$Alert.Note) (S 180) (S $y) (S 268); $tNote.AccessibleName = Tr "Notiz"
    $y += 32
    # repeat and end: the stored value stays selectable even if it is none of the standard choices
    $rearm = [ordered]@{}
    foreach ($k in $script:RearmChoices.Keys) { $rearm[[string]$k] = [int]$script:RearmChoices[$k] }
    $curRearm = @($rearm.Keys | Where-Object { $rearm[$_] -eq [int]$Alert.RearmMin })
    if ($curRearm.Count -eq 0) { $lab = "R " + (Format-RearmLabel ([int]$Alert.RearmMin)); $rearm[$lab] = [int]$Alert.RearmMin; $curRearm = @($lab) }
    [void](New-V8Label $dlg (Tr "Wiederholen") (S 12) (S ($y + 4)) (S 160))
    $cRe = New-V8Combo $dlg @($rearm.Keys) ([string]$curRearm[0]) (S 180) (S $y) (S 268); $cRe.AccessibleName = Tr "Wiederholen"
    $y += 32
    $endNow = [string]$Alert.ExpiresAt
    $keep = if ($endNow) { (Tr "Unverändert (bis {0})") -f (Format-IsoDateDe $endNow) } else { Tr "Unverändert (ohne Ende)" }
    $ends = [ordered]@{ $keep = -1 }
    foreach ($k in $script:AlertExpiryChoices.Keys) { $ends[[string]$k] = [int]$script:AlertExpiryChoices[$k] }
    [void](New-V8Label $dlg (Tr "Gültig") (S 12) (S ($y + 4)) (S 160))
    $cEnd = New-V8Combo $dlg @($ends.Keys) $keep (S 180) (S $y) (S 268); $cEnd.AccessibleName = Tr "Gültig"
    $y += 32
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.SetBounds((S 180), (S $y), (S 268), (S 24)); $chk.Text = Tr "Auch aufs Handy schicken"; $chk.Checked = [bool]$Alert.Push
    $chk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dlg.Controls.Add($chk)
    $err = New-V8Label $dlg "" (S 12) (S ($y + 28)) (S 436) (S 20); $err.ForeColor = $script:Pal.Warn
    $ok = New-V8Button $dlg (Tr "Speichern") (S 248) (S ($h - 38)) (S 96)
    $no = New-V8Button $dlg (Tr "Abbrechen") (S 352) (S ($h - 38)) (S 96)
    $no.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.CancelButton = $no; $dlg.AcceptButton = $ok
    $script:AlertEdit = @{ Dlg = $dlg; Alert = $Alert; V1 = $v1; V2 = $v2; Note = $tNote; Rearm = $cRe; RearmMap = $rearm; End = $cEnd; EndMap = $ends; Push = $chk; Err = $err; Ok = $ok; Saved = $false }
    $ok.Add_Click({ Save-AlertEdit })
    [void]$dlg.ShowDialog($(if ($null -ne $Owner) { $Owner } else { $form }))
    $saved = [bool]$script:AlertEdit.Saved
    $dlg.Dispose()
    $script:AlertEdit = $null
    return $saved
}

function Save-AlertEdit {
    $ed = $script:AlertEdit
    if ($null -eq $ed) { return }
    $vals = @(0.0, 0.0); $i = 0
    foreach ($tb in @($ed.V1, $ed.V2)) {
        if ($null -ne $tb -and $tb.Enabled) {
            if (-not $tb.Text.Trim() -or -not (Test-DecimalInput $tb.Text)) { $ed.Err.Text = Tr "Bitte eine Zahl eingeben."; return }
            $vals[$i] = Parse-DecimalInput $tb.Text
        }
        $i++
    }
    $days = [int]$ed.EndMap[[string]$ed.End.SelectedItem]
    $end = if ($days -lt 0) { [string]$ed.Alert.ExpiresAt } else { Get-AlertExpiryDate -Days $days }
    $why = Update-AlertSettings -Alert $ed.Alert -Value $vals[0] -Value2 $vals[1] -Note $ed.Note.Text -RearmMin ([int]$ed.RearmMap[[string]$ed.Rearm.SelectedItem]) -ExpiresAt $end -Push $ed.Push.Checked
    if ($why) { $ed.Err.Text = $why; return }
    Save-Alerts
    $ed.Saved = $true
    $ed.Dlg.Close()
}

function Update-AlertOverview {
    $ov = $script:AlertOv
    if ($null -eq $ov) { return }
    $keys = @("All", "Active", "Hit", "Paused", "Expired")
    $filter = $keys[[math]::Max(0, $ov.Filter.SelectedIndex)]
    $names = @{ Active = (Tr "Aktiv"); Hit = (Tr "Ausgelöst"); Paused = (Tr "Pausiert"); Expired = (Tr "Abgelaufen") }
    $sel = if ($ov.Grid.SelectedRows.Count -gt 0) { [string]$ov.Grid.SelectedRows[0].Tag } else { "" }
    $top = $ov.Grid.FirstDisplayedScrollingRowIndex
    $ov.Grid.Rows.Clear()
    $rows = @(Get-AlertOverviewRows -Filter $filter)
    foreach ($r in $rows) {
        $a = $r.Alert
        $re = if ([int]$a.RearmMin -gt 0) { Format-RearmLabel ([int]$a.RearmMin) } else { Tr "einmalig" }
        $end = if ([string]$a.ExpiresAt) { Format-IsoDateDe ([string]$a.ExpiresAt) } else { "" }
        $i = $ov.Grid.Rows.Add($names[$r.Status], [string]$a.Ticker, $r.What, $r.Now, $r.Gap, $re, $end, [string]$a.Note)
        $row = $ov.Grid.Rows[$i]
        $row.Tag = $r.Id
        $row.Cells["Now"].ToolTipText = $r.Tip
        $row.Cells["Status"].Style.ForeColor = switch ($r.Status) { "Active" { $colGreen } "Hit" { $script:Pal.Warn } default { $script:Pal.Muted } }
        # close to firing: within 2 percent
        if ($r.Status -eq "Active" -and $r.Score -le 2.0) { $row.Cells["Gap"].Style.ForeColor = $script:Pal.Warn }
    }
    $ov.Grid.ClearSelection()
    foreach ($row in @($ov.Grid.Rows)) { if ([string]$row.Tag -eq $sel) { $row.Selected = $true } }
    if ($ov.Grid.SelectedRows.Count -eq 0 -and $ov.Grid.Rows.Count -gt 0) { $ov.Grid.Rows[0].Selected = $true }
    if ($top -ge 0 -and $top -lt $ov.Grid.Rows.Count) { $ov.Grid.FirstDisplayedScrollingRowIndex = $top }
    $ov.Count.Text = (Tr "{0} von {1} Alarmen. Aktive nach Abstand sortiert, der nächste oben.") -f $rows.Count, $script:Alerts.Count
    foreach ($b in $ov.RowButtons) { $b.Enabled = ($ov.Grid.Rows.Count -gt 0) }
}

function Invoke-AlertOverviewAction {
    # Edit / Pause / Arm / Delete on the selected row
    param([string]$Action)
    $ov = $script:AlertOv
    if ($null -eq $ov -or $ov.Grid.SelectedRows.Count -eq 0) { return }
    $idx = Get-AlertIndex ([string]$ov.Grid.SelectedRows[0].Tag)
    if ($idx -lt 0) { Update-AlertOverview; return }
    $al = $script:Alerts[$idx]
    switch ($Action) {
        "Edit"   { if (Show-AlertEditDialog -Alert $al -Owner $ov.Dlg) { Evaluate-GlobalAlerts; Update-AllUiViews } }
        "Pause"  { Set-AlertSnooze -Index $idx -Kind "Tomorrow" }
        "Arm"    {
            if (Test-AlertExpired -Alert $al) { $al.ExpiresAt = "" }
            $al.Triggered = $false; $al.TriggeredAt = ""
            $al | Add-Member -NotePropertyName SnoozeUntil -NotePropertyValue "" -Force
            if ((Get-AlertKind ([string]$al.Condition)) -eq "TRAIL") { $al.Peak = 0.0 }
            Save-Alerts; Refresh-WatchlistAndAlerts
        }
        "Delete" {
            $script:Alerts.RemoveAt($idx); Save-Alerts; Update-AllUiViews
            Set-Undo -Kind "Alert" -Data @{ Item = $al; Index = $idx } -Text ((Tr "Alarm {0} {1} gelöscht") -f $al.Ticker, $al.Condition)
            $ov.Count.Tag = $al; $ov.Undo.Enabled = $true
        }
        default  { return }
    }
    Update-AlertOverview
}

function Show-AlertOverviewDialog {
    $dlg = New-DialogForm -Title "Alarm-Übersicht" -W (S 900) -H (S 440) -Key "AlertOverview"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 760), (S 300))
    $aTL = [System.Windows.Forms.AnchorStyles]"Top, Left"
    $aBL = [System.Windows.Forms.AnchorStyles]"Bottom, Left"
    $aBR = [System.Windows.Forms.AnchorStyles]"Bottom, Right"
    $cf = New-V8Combo $dlg @((Tr "Alle"), (Tr "Aktiv"), (Tr "Ausgelöst"), (Tr "Pausiert"), (Tr "Abgelaufen")) (Tr "Alle") (S 12) (S 10) (S 140)
    $cf.AccessibleName = Tr "Filter"
    $cnt = New-V8Label $dlg "" (S 164) (S 14) (S 724) -Muted
    $g = New-V8Grid $dlg (S 12) (S 42) (S 876) (S 350)
    $g.Anchor = [System.Windows.Forms.AnchorStyles]"Top, Bottom, Left, Right"
    $g.MultiSelect = $false
    foreach ($c in @(@("Status", "Status", 70), @("Ticker", "Ticker", 60), @("What", "Bedingung", 150), @("Now", "Jetzt", 100), @("Gap", "Abstand", 80), @("Rearm", "Wiederholen", 65), @("End", "Gültig bis", 70), @("Note", "Notiz", 120))) {
        Add-V8Column $g $c[0] $c[1] $c[2] -ReadOnly
    }
    foreach ($n in @("Status", "Ticker", "Gap", "Rearm", "End")) { $g.Columns[$n].AutoSizeMode = [System.Windows.Forms.DataGridViewAutoSizeColumnMode]::AllCells }
    $g.Columns["Gap"].ToolTipText = Tr "So weit muss sich der Wert noch bewegen, bis der Alarm auslöst"
    foreach ($n in @("Now", "Gap")) { $g.Columns[$n].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight }
    $buttons = @(); $x = 12
    foreach ($bd in @(@("Edit", "Bearbeiten ...", 116), @("Arm", "Wieder scharf", 116), @("Pause", "Bis morgen pausieren", 160), @("Delete", "Löschen", 90))) {
        $b = New-V8Button $dlg (Tr $bd[1]) (S $x) (S 402) (S $bd[2])
        $b.Anchor = $aBL; $b.Tag = $bd[0]
        $b.Add_Click({ param($s, $e) Invoke-AlertOverviewAction ([string]$s.Tag) })
        $buttons += $b
        $x += $bd[2] + 8
    }
    $undo = New-V8Button $dlg (Tr "Rückgängig") (S $x) (S 402) (S 106)
    $undo.Anchor = $aBL; $undo.Enabled = $false
    $undo.Add_Click({ param($s, $e) if (Invoke-Undo) { Update-AlertOverview }; $s.Enabled = $false })
    $bLog = New-V8Button $dlg (Tr "Verlauf ...") (S 690) (S 402) (S 96)
    $bLog.Anchor = $aBR; $bLog.Add_Click({ Show-AlertLogDialog })
    $no = New-V8Button $dlg (Tr "Schließen") (S 792) (S 402) (S 96)
    $no.Anchor = $aBR; $no.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.CancelButton = $no
    $script:AlertOv = @{ Dlg = $dlg; Grid = $g; Filter = $cf; Count = $cnt; RowButtons = $buttons; Undo = $undo }
    $cf.Add_SelectedIndexChanged({ Update-AlertOverview })
    $g.Add_CellDoubleClick({ param($s, $e) if ($e.RowIndex -ge 0) { Invoke-AlertOverviewAction "Edit" } })
    $dlg.Add_Shown({ Update-AlertOverview })
    # values move with the quotes
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 5000
    $timer.Add_Tick({ if ($null -ne $script:AlertOv -and $null -eq $script:AlertEdit) { Update-AlertOverview } })
    $timer.Start()
    [void]$dlg.ShowDialog($form)
    $timer.Stop(); $timer.Dispose()
    $dlg.Dispose()
    $script:AlertOv = $null
}

$script:AlertOv = $null
$script:AlertEdit = $null
[void](Add-BarItem $mbTools "Alarm-Übersicht ..." { Show-AlertOverviewDialog })
