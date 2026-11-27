# TerminalWidget UI part 13 (Startup) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

function Get-AlertCurrency {
    # what the number of an alert is measured in
    param([string]$Kind, [string]$Symbol)
    $qc = if ($script:QuoteStore.ContainsKey($Symbol)) { [string]$script:QuoteStore[$Symbol].Currency } else { "" }
    $c = switch ($Kind) {
        "PCT"    { "%" }
        "RSI"    { "RSI" }
        "SMA"    { "SMA" }
        "HIGH52" { "52W" }
        "LOW52"  { "52W" }
        "VOL"    { "VOL" }
        "PFPCT"  { "%" }
        # percent to the average cost in the position's currency (no FX effect)
        "EKPCT"  { if ($script:Portfolio.ContainsKey($Symbol)) { [string]$script:Portfolio[$Symbol].Currency } else { [string]$script:Config.Currency } }
        # trailing high in the instrument's own currency
        "TRAIL"  { if ($qc) { $qc } else { $script:Config.Currency } }
        # v5.1: a price alert is entered in the currency the price is shown in
        "PRICE"  { Get-PriceCurrency $Symbol }
        default  { $script:Config.Currency }
    }
    return [string]$c
}

function New-AlertChecked {
    # Validates and creates an alert (alert panel + command line).
    # Returns "" when created, "CANCEL" when the user declined, else an error text.
    param([string]$RawTicker, [string]$Cond, [double]$Value, [string]$Note = "", [int]$Rearm = 0, [int]$ExpDays = 0, [string]$Cond2 = "", [double]$Value2 = 0)
    $kind = Get-AlertKind $Cond
    if ($kind -ne "SMA") {
        # value ranges per kind (Tag% / EK% / Depot Tag% may be negative)
        $bad = ($kind -in @("PRICE", "PFVAL", "VOL") -and $Value -le 0) -or
               ($kind -in @("RSI", "TRAIL") -and ($Value -le 0 -or $Value -ge 100)) -or
               ($kind -in @("HIGH52", "LOW52") -and ($Value -lt 0 -or $Value -gt 50))
        if ($bad) { return ("Ungültiger Alarm-Wert {0} ({1})" -f $Value, (Get-AlertTargetHint $Cond)) }
    } else { $Value = 0.0 }
    if (Test-PortfolioAlertKind $kind) {
        if ($script:Portfolio.Count -eq 0) { return "Depot-Alarme brauchen Positionen im Portfolio." }
        $aSym = "DEPOT"
    } else {
        $aSym = Resolve-BestSymbol -RawInput $RawTicker
        if ([string]::IsNullOrWhiteSpace($aSym)) { return "Ticker '$RawTicker' nicht gefunden." }
    }
    if ($kind -eq "EKPCT" -and -not $script:Portfolio.ContainsKey($aSym)) { return "EK%-Alarme gehen nur für Positionen im Portfolio ($aSym fehlt)." }
    $curr = Get-AlertCurrency -Kind $kind -Symbol $aSym
    $curr2 = ""
    if ($Cond2) {
        $why = Test-AlertCombination -First $Cond -Second $Cond2
        if ($why) { return $why }
        $kind2 = Get-AlertKind $Cond2
        if ($kind2 -eq "SMA") { $Value2 = 0.0 } else { $bad2 = Test-AlertValue -Condition $Cond2 -Value $Value2; if ($bad2) { return ("Ungültiger Alarm-Wert {0} ({1})" -f $Value2, $bad2) } }
        if ($kind2 -eq "EKPCT" -and -not $script:Portfolio.ContainsKey($aSym)) { return "EK%-Alarme gehen nur für Positionen im Portfolio ($aSym fehlt)." }
        $curr2 = Get-AlertCurrency -Kind $kind2 -Symbol $aSym
    }
    $ok = Add-WidgetAlert -Ticker $aSym -Condition $Cond -Target $Value -Currency $curr -Note $Note -RearmMin $Rearm -ExpiresAt (Get-AlertExpiryDate -Days $ExpDays) -Condition2 $Cond2 -Target2 $Value2 -Currency2 $curr2
    if (-not $ok) { return "CANCEL" }
    Refresh-AllMarketData
    Evaluate-GlobalAlerts
    Update-AllUiViews
    return ""
}

$btnAddAlert.Add_Click({
    $aCond = [string]$cmbAlertCond.SelectedItem
    $kind  = Get-AlertKind $aCond
    $raw   = $txtAlertPrice.Text
    $aPrice = 0.0
    if ($kind -ne "SMA") {
        if ([string]::IsNullOrWhiteSpace($raw) -or -not (Test-DecimalInput $raw)) {
            Set-TransientStatus ("Ungültiger Alarm-Wert: '{0}' ({1})" -f $raw, (Get-AlertTargetHint $aCond)) 6
            return
        }
        $aPrice = Parse-DecimalInput $raw
    }
    $rearm = 0
    if ($null -ne $cmbAlertRearm.SelectedItem) { $rearm = [int]$script:RearmChoices[[string]$cmbAlertRearm.SelectedItem] }
    $expDays = 0
    if ($null -ne $cmbAlertExp.SelectedItem) { $expDays = [int]$script:AlertExpiryChoices[[string]$cmbAlertExp.SelectedItem] }
    $err = New-AlertChecked -RawTicker $txtAlertTicker.Text -Cond $aCond -Value $aPrice -Note $txtAlertNote.Text.Trim() -Rearm $rearm -ExpDays $expDays
    if ($err -eq "CANCEL") { return }
    if ($err) { Set-TransientStatus $err 6; return }
    if (-not (Test-PortfolioAlertKind $kind)) { $txtAlertTicker.Text = ([string]$script:Alerts[$script:Alerts.Count - 1].Ticker) }
    $txtAlertPrice.Text = ""
    $txtAlertNote.Text = ""
    $script:AlertAutoValue = ""
})

$btnDelAlert.Add_Click({
    $idx = $lstAlerts.SelectedIndex
    if ($idx -ge 0 -and $idx -lt $script:Alerts.Count) {
        # v4.6: no question any more - Ctrl+Z brings it back
        $al = $script:Alerts[$idx]
        $script:Alerts.RemoveAt($idx)
        Save-Alerts
        Update-AllUiViews
        Set-Undo -Kind "Alert" -Data @{ Item = $al; Index = $idx } -Text ("Alarm {0} {1} gelöscht" -f $al.Ticker, $al.Condition)
    }
})

$script:AlertAutoValue = ""
$cmbAlertCond.Add_SelectedIndexChanged({
    $cond = [string]$cmbAlertCond.SelectedItem
    $kind = Get-AlertKind $cond
    $isSma = ($kind -eq "SMA")
    $txtAlertPrice.Enabled = -not $isSma
    if ($isSma) { $txtAlertPrice.Text = "" }
    # v4.3: portfolio alerts watch the whole depot, not a ticker
    if (Test-PortfolioAlertKind $kind) {
        $txtAlertTicker.Text = "DEPOT"
        $txtAlertTicker.Enabled = $false
    } elseif (-not $txtAlertTicker.Enabled) {
        $txtAlertTicker.Enabled = $true
        $txtAlertTicker.Text = $script:Config.ActiveTicker
    }
    # suggested value; replaced again as long as the user did not type one
    $def = switch ($kind) { "TRAIL" { "8" } "VOL" { "2" } "HIGH52" { "0" } "LOW52" { "0" } "RSI" { "70" } default { "" } }
    if (-not $isSma -and ([string]::IsNullOrWhiteSpace($txtAlertPrice.Text) -or $txtAlertPrice.Text -eq $script:AlertAutoValue)) {
        $txtAlertPrice.Text = $def
        $script:AlertAutoValue = $def
    }
    $hint = Get-AlertTargetHint $cond
    if ($kind -eq "PFVAL") { $hint += " ($($script:Config.Currency))" }
    if ($kind -eq "PRICE") { $hint += " ($(Get-PriceCurrency ([string]$txtAlertTicker.Text)))" }
    if ($kind -eq "SMA") { $hint = "Kein Wert nötig: Kurs kreuzt SMA$($script:Config.SmaFastPeriod) (1h)" }
    Set-Tip $txtAlertPrice $hint $(if ($kind -eq "TRAIL") { "TRAIL" } elseif ($kind -eq "VOL") { "RELVOL" } else { "ALERTCOND" })
})
$cmbAlertCond.SelectedIndex = 1; $cmbAlertCond.SelectedIndex = 0   # fire once for the hint

$txtAlertPrice.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        $btnAddAlert.PerformClick()
    }
})

$lstAlerts.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete) {
        $e.SuppressKeyPress = $true
        $btnDelAlert.PerformClick()
    }
})

$lstAlerts.Add_DoubleClick({
    $idx = $lstAlerts.SelectedIndex
    if ($idx -ge 0 -and $idx -lt $script:Alerts.Count) {
        $al = $script:Alerts[$idx]
        if (Test-AlertExpired -Alert $al) {
            # v4.3: an expired alert comes back without an end date
            $al.ExpiresAt = ""
            $al.Triggered = $false
        } else {
            $al.Triggered = -not $al.Triggered
        }
        $al.TriggeredAt = if ($al.Triggered) { (Get-Date).ToString("o") } else { "" }
        if (-not $al.Triggered -and (Get-AlertKind $al.Condition) -eq "TRAIL") { $al.Peak = 0.0 }
        Save-Alerts
        Refresh-WatchlistAndAlerts
    }
})

$btnAlertLog.Add_Click({ Show-AlertLogDialog })

# v4.9.5: snooze an alert (right-click in the alert list)
function Set-AlertSnooze {
    param([int]$Index, [string]$Kind)
    if ($Index -lt 0 -or $Index -ge $script:Alerts.Count) { return }
    $al = $script:Alerts[$Index]
    $until = Get-SnoozeUntil -Kind $Kind
    $v = if ($until -gt [DateTime]::MinValue) { $until.ToString("o") } else { "" }
    $al | Add-Member -NotePropertyName SnoozeUntil -NotePropertyValue $v -Force
    Save-Alerts
    Refresh-WatchlistAndAlerts
    if ($v) { Set-TransientStatus ("Alarm {0} pausiert bis {1:dd.MM. HH:mm}" -f $al.Ticker, $until) 4 } else { Set-TransientStatus ("Alarm {0} wieder aktiv" -f $al.Ticker) 3 }
}
$alertMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miSnz1 = $alertMenu.Items.Add("1 Stunde pausieren")
$miSnz4 = $alertMenu.Items.Add("4 Stunden pausieren")
$miSnzT = $alertMenu.Items.Add("Bis morgen 08:00 pausieren")
$miSnzW = $alertMenu.Items.Add("1 Woche pausieren")
$miSnzOff = $alertMenu.Items.Add("Pause beenden")
[void]$alertMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
$miAlDel = $alertMenu.Items.Add("Löschen (Entf)")
$miSnz1.Add_Click({ Set-AlertSnooze -Index $lstAlerts.SelectedIndex -Kind "1h" })
$miSnz4.Add_Click({ Set-AlertSnooze -Index $lstAlerts.SelectedIndex -Kind "4h" })
$miSnzT.Add_Click({ Set-AlertSnooze -Index $lstAlerts.SelectedIndex -Kind "Tomorrow" })
$miSnzW.Add_Click({ Set-AlertSnooze -Index $lstAlerts.SelectedIndex -Kind "Week" })
$miSnzOff.Add_Click({ Set-AlertSnooze -Index $lstAlerts.SelectedIndex -Kind "" })
$miAlDel.Add_Click({ $btnDelAlert.PerformClick() })
$lstAlerts.Add_MouseUp({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
    $i = $sender.IndexFromPoint($e.Location)
    if ($i -lt 0 -or $i -ge $script:Alerts.Count) { return }
    $sender.SelectedIndex = $i
    $snz = Test-AlertSnoozed -Alert $script:Alerts[$i]
    $miSnzOff.Enabled = $snz
    $alertMenu.Show($sender, $e.Location)
})

# Header Ticker Dropdown & Live Search Events
$btnTickerDrop.Add_Click({
    $lstCurrencyDropdown.Visible = $false
    if ($lstTickerDropdown.Visible) {
        $lstTickerDropdown.Visible = $false
    } else {
        Populate-TickerDropdown -FilterText ""
    }
})

# Focus alone no longer opens the dropdown (it popped open on startup and on
# every window activation). It opens on click, typing, Down arrow or the arrow button.
$txtSearch.Add_GotFocus({
    [void]$txtSearch.BeginInvoke([Action]{ $txtSearch.SelectAll() })
})
$txtSearch.Add_MouseClick({
    if (-not $lstTickerDropdown.Visible) { Populate-TickerDropdown -FilterText "" }
})

$searchTimer = New-Object System.Windows.Forms.Timer
$searchTimer.Interval = 300
$searchTimer.Add_Tick({
    $searchTimer.Stop()
    $q = $txtSearch.Text.Trim()
    if ($q.Length -eq 0) {
        Populate-TickerDropdown -FilterText ""
    } elseif ($q -ne $script:Config.ActiveTicker) {
        # Local matches right away, Yahoo hits are appended when they arrive
        Populate-TickerDropdown -FilterText $q
        $url = Get-SearchUrl -Query $q
        Start-FetchJob -Urls @($url) -MaxConcurrency 1 -Context @{ Query = $q; Url = $url } -OnComplete {
            param($Box, $Ctx)
            # user kept typing or already picked something: drop the stale result
            if ($txtSearch.Text.Trim() -ne $Ctx.Query -or ((-not $txtSearch.Focused) -and (-not $lstTickerDropdown.Focused))) { return }
            $hits = @(ConvertFrom-YahooSearch -Json $Box.Results[$Ctx.Url])
            if ($hits.Count -gt 0) { Populate-TickerDropdown -FilterText $Ctx.Query -SearchHits $hits }
        }
    }
})

$txtSearch.Add_TextChanged({
    if ($script:SuppressSearchEvent) { return }
    $searchTimer.Stop()
    $searchTimer.Start()
})

$txtSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Down) {
        $e.SuppressKeyPress = $true
        if (-not $lstTickerDropdown.Visible) {
            Populate-TickerDropdown -FilterText ""
        }
        if ($lstTickerDropdown.Visible -and $lstTickerDropdown.Items.Count -gt 0) {
            $lstTickerDropdown.Focus()
        }
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        $searchTimer.Stop()
        $typed = $txtSearch.Text.Trim().ToUpper()
        if ($lstTickerDropdown.Visible -and $null -ne $lstTickerDropdown.SelectedItem -and $typed -ne $lstTickerDropdown.SelectedItem.Symbol -and $typed.Length -gt 0) {
            $selSym = $lstTickerDropdown.SelectedItem.Symbol
            $lstTickerDropdown.Visible = $false
            Switch-ActiveTicker -NewTicker $selSym -SkipResolve $true
        } elseif ($typed.Length -gt 0) {
            $lstTickerDropdown.Visible = $false
            Switch-ActiveTicker -NewTicker $typed -SkipResolve $false
        }
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $lstTickerDropdown.Visible = $false
        $script:SuppressSearchEvent = $true
        $txtSearch.Text = $script:Config.ActiveTicker
        $script:SuppressSearchEvent = $false
    }
})

$lstTickerDropdown.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $null -ne $lstTickerDropdown.SelectedItem) {
        $e.SuppressKeyPress = $true
        $selSym = $lstTickerDropdown.SelectedItem.Symbol
        $lstTickerDropdown.Visible = $false
        Switch-ActiveTicker -NewTicker $selSym -SkipResolve $true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete -and $null -ne $lstTickerDropdown.SelectedItem) {
        $e.SuppressKeyPress = $true
        $delSym = $lstTickerDropdown.SelectedItem.Symbol
        if (Remove-SymbolFromWatchlist -Symbol $delSym) {
            Populate-TickerDropdown -FilterText ""
        }
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $lstTickerDropdown.Visible = $false
    }
})

$lstTickerDropdown.Add_MouseUp({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $idx = $lstTickerDropdown.IndexFromPoint($e.Location)
        if ($idx -ge 0) {
            $lstTickerDropdown.SelectedIndex = $idx
            $delSym = $lstTickerDropdown.Items[$idx].Symbol
            if (Remove-SymbolFromWatchlist -Symbol $delSym) {
                Populate-TickerDropdown -FilterText ""
            }
        }
    }
})

$lstTickerDropdown.Add_Click({
    if ($null -ne $lstTickerDropdown.SelectedItem) {
        $selSym = $lstTickerDropdown.SelectedItem.Symbol
        $lstTickerDropdown.Visible = $false
        Switch-ActiveTicker -NewTicker $selSym -SkipResolve $true
    }
})

# Close open dropdown popups when clicking anywhere else
$pnlChartCanvas.Add_MouseDown({ $lstTickerDropdown.Visible = $false; $lstCurrencyDropdown.Visible = $false })
$pnlChartControls.Add_MouseDown({ $lstTickerDropdown.Visible = $false; $lstCurrencyDropdown.Visible = $false })
$pnlNav.Add_MouseDown({ $lstTickerDropdown.Visible = $false; $lstCurrencyDropdown.Visible = $false })
$dgvPortfolio.Add_MouseDown({ $lstTickerDropdown.Visible = $false; $lstCurrencyDropdown.Visible = $false })
$dgvWatchlist.Add_MouseDown({ $lstTickerDropdown.Visible = $false; $lstCurrencyDropdown.Visible = $false; $lstWlSearchDropdown.Visible = $false })

# Global Keyboard Shortcuts (used by the main window AND the fullscreen chart)
$script:GlobalKeyHandler = {
    param($sender, $e)
    $isFs = ($null -ne $script:FsForm -and [object]::ReferenceEquals($sender, $script:FsForm))
    # F11: fullscreen chart on/off; Esc closes the fullscreen chart
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F11 -and -not $e.Control -and -not $e.Alt) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        Toggle-ChartFullscreen
        return
    }
    # v5.0: Esc first leaves the drawing mode
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape -and $script:DrawMode) {
        $e.Handled = $true
        Set-DrawMode ""
        Set-TransientStatus "Zeichnen abgebrochen" 2
        return
    }
    # Esc: first clears a measurement, then closes the fullscreen chart
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape -and $script:Measure.Active) {
        $e.Handled = $true
        Clear-ChartMeasure
        return
    }
    if ($isFs -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $e.Handled = $true
        Close-ChartFullscreen
        return
    }
    # v4.9.5: Esc leaves the full-page list (not while a drop-down is open)
    if (-not $isFs -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Escape -and $script:TerminalFull -and -not $lstTickerDropdown.Visible -and -not $lstWlSearchDropdown.Visible) {
        $e.Handled = $true
        Set-TerminalFull ""
        return
    }
    # v8.0: own shortcuts win over the built-in ones
    if (Invoke-UserShortcut -Sender $sender -E $e) { return }
    # Ctrl+F: jump to the ticker search (main window only)
    if (-not $isFs -and $e.Control -and -not $e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        $txtSearch.Focus()
        $txtSearch.SelectAll()
        if (-not $script:Config.CompactMode) { Populate-TickerDropdown -FilterText "" }
        return
    }
    # v4.6: Ctrl+Z = undo the last deletion (not inside text boxes)
    if ($e.Control -and -not $e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Z -and -not ($sender.ActiveControl -is [System.Windows.Forms.TextBox])) {
        if (Invoke-Undo) { $e.Handled = $true; $e.SuppressKeyPress = $true; return }
    }
    if ($e.Control -and -not $e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::Y -and -not ($sender.ActiveControl -is [System.Windows.Forms.TextBox])) {
        if (Invoke-Redo) { $e.Handled = $true; $e.SuppressKeyPress = $true; return }
    }
    # v4.4: Ctrl+K = command line (works in the fullscreen chart too)
    if ($e.Control -and -not $e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::K) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        Show-CommandPalette
        return
    }
    # v4.9.5: Ctrl+C in a list copies the whole table (visible columns, display order)
    if ($e.Control -and -not $e.Alt -and -not $e.Shift -and $e.KeyCode -eq [System.Windows.Forms.Keys]::C) {
        $gc = $sender.ActiveControl
        if ($gc -is [System.Windows.Forms.DataGridView] -and -not $gc.IsCurrentCellInEditMode -and $gc.Rows.Count -gt 0) {
            if (Copy-GridAsTable -Grid $gc) { $e.Handled = $true; $e.SuppressKeyPress = $true; return }
        }
    }
    # v7.7: Ctrl+F = search in the news list
    if ($e.Control -and -not $e.Alt -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F -and $viewNews.Visible) {
        [void]$txtNewsSearch.Focus(); $txtNewsSearch.SelectAll()
        $e.Handled = $true; $e.SuppressKeyPress = $true; return
    }
    # Other Ctrl/Alt combos (Ctrl+C, Alt+F4, ...) are never widget shortcuts
    if ($e.Control -or $e.Alt) { return }
    $ac = $sender.ActiveControl
    $isFKey = $e.KeyCode -in @([System.Windows.Forms.Keys]::F1, [System.Windows.Forms.Keys]::F2, [System.Windows.Forms.Keys]::F3, [System.Windows.Forms.Keys]::F5, [System.Windows.Forms.Keys]::F6)
    # v4.9: F4 = News, except in a drop-down (F4 opens it there, as in every Windows list)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F4 -and -not ($ac -is [System.Windows.Forms.ComboBox])) { $isFKey = $true }
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F9) { $isFKey = $true }
    # Typing into inputs/lists must not trigger letter shortcuts (F-keys still work)
    if (($ac -is [System.Windows.Forms.TextBox] -or $ac -is [System.Windows.Forms.ComboBox] -or $ac -is [System.Windows.Forms.ListBox]) -and -not $isFKey) { return }
    # Arrow keys belong to the grid when a grid has focus
    if ($ac -is [System.Windows.Forms.DataGridView] -and $e.KeyCode -in @([System.Windows.Forms.Keys]::Left, [System.Windows.Forms.Keys]::Right)) { return }

    # v7.7: J / K / O / S / M / V belong to the news list while it has the focus
    if ([object]::ReferenceEquals($ac, $dgvNews) -and -not $e.Shift -and (Invoke-NewsKey $e)) { $e.Handled = $true; $e.SuppressKeyPress = $true; return }

    # 1-6 (top row or numpad): timeframe 1D / 5D / 1M / 3M / 6M / 1Y
    $kc = [int]$e.KeyCode
    $tfIdx = -1
    if ($kc -ge [int][System.Windows.Forms.Keys]::D1 -and $kc -le [int][System.Windows.Forms.Keys]::D6) { $tfIdx = $kc - [int][System.Windows.Forms.Keys]::D1 }
    elseif ($kc -ge [int][System.Windows.Forms.Keys]::NumPad1 -and $kc -le [int][System.Windows.Forms.Keys]::NumPad6) { $tfIdx = $kc - [int][System.Windows.Forms.Keys]::NumPad1 }
    if ($tfIdx -ge 0) {
        $e.Handled = $true
        $e.SuppressKeyPress = $true
        Set-Timeframe -Tf $tfList[$tfIdx]
        return
    }

    switch ($e.KeyCode) {
        ([System.Windows.Forms.Keys]::F1) { Invoke-TabClick -TabName "Chart"; $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F2) { Invoke-TabClick -TabName "Portfolio" -ForceFull ([bool]$e.Shift); $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F3) { Invoke-TabClick -TabName "Watchlist" -ForceFull ([bool]$e.Shift); $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F4) { Invoke-TabClick -TabName "News" -ForceFull ([bool]$e.Shift); $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F6) { Show-OverviewDialog; $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F9) { Set-PrivacyMode (-not [bool]$script:Config.PrivacyMode); $e.Handled = $true }
        ([System.Windows.Forms.Keys]::F5) {
            Refresh-AllMarketData -Force; Evaluate-GlobalAlerts; Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::Left) {
            $wl = @($script:Config.Watchlist)
            if ($wl.Count -gt 1) {
                $idx = $wl.IndexOf($script:Config.ActiveTicker.ToUpper())
                $prevIdx = if ($idx -le 0) { $wl.Count - 1 } else { $idx - 1 }
                Switch-ActiveTicker -NewTicker $wl[$prevIdx] -SkipResolve $true
                $e.Handled = $true
            }
        }
        ([System.Windows.Forms.Keys]::Right) {
            $wl = @($script:Config.Watchlist)
            if ($wl.Count -gt 1) {
                $idx = $wl.IndexOf($script:Config.ActiveTicker.ToUpper())
                $nextIdx = if ($idx -lt 0 -or $idx -ge ($wl.Count - 1)) { 0 } else { $idx + 1 }
                Switch-ActiveTicker -NewTicker $wl[$nextIdx] -SkipResolve $true
                $e.Handled = $true
            }
        }
        ([System.Windows.Forms.Keys]::W) {
            Set-ActiveCurrency -NewCurrency (Get-NextCurrencyMode -Current $script:Config.Currency -Auto ([bool]$script:Config.AutoCurrency)); $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::C) {
            Toggle-CompactLayout; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::L) {
            if (-not $isFs) { Apply-Layout (Get-NextLayout ([string]$script:Config.Layout)) }
            $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::G) {
            Show-GlossaryDialog; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::P) {
            Show-AnalysisDialog; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::T) {
            $btnThemeCycle.PerformClick(); $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::D) { if ($script:DrawMode) { Set-DrawMode "" } else { Set-DrawMode "T" }; $e.Handled = $true }
        ([System.Windows.Forms.Keys]::K) {
            $script:Config.ChartType = Get-NextChartType ([string]$script:Config.ChartType)
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::V) {
            $script:Config.ShowVolume = -not $script:Config.ShowVolume
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::A) {
            $script:Config.ShowVwap = -not $script:Config.ShowVwap
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::B) {
            $script:Config.ShowBollinger = -not $script:Config.ShowBollinger
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::R) {
            $script:Config.ShowRsi = -not $script:Config.ShowRsi
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::E) {
            Toggle-ExtendedHours; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::H) {
            Show-ShortcutHelp; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::Y) {
            Set-LogScale (-not [bool]$script:Config.LogScale); $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::Divide) {
            $e.SuppressKeyPress = $true; Show-CommandPalette; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::Z) {
            Reset-ChartZoom; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::X) {
            if ($script:Config.CompareTicker) { Set-CompareTicker -Symbol "" } else { Show-CompareDialog }
            $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::S) {
            if (-not $isFs) { Show-SettingsDialog }
            $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::M) {
            $script:Config.ShowSma = -not $script:Config.ShowSma
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-AllUiViews; $e.Handled = $true
        }
        ([System.Windows.Forms.Keys]::Escape) {
            if ($lstTickerDropdown.Visible -or $lstCurrencyDropdown.Visible -or $lstWlSearchDropdown.Visible) {
                $lstTickerDropdown.Visible = $false
                $lstCurrencyDropdown.Visible = $false
                $lstWlSearchDropdown.Visible = $false
                $e.Handled = $true
            } elseif ($script:Config.CompactMode) {
                Apply-Layout ([string]$script:Config.LastFullLayout); $e.Handled = $true
            }
        }
    }
}
$form.Add_KeyDown($script:GlobalKeyHandler)

# Background Poll Timer
$pollTimer = New-Object System.Windows.Forms.Timer
$pollTimer.Interval = ([int]$script:Config.RefreshSeconds * 1000)
function Flush-ErrorsToLog {
    # Event-handler errors only go to the (hidden) console; copy them to the log
    if ($global:Error.Count -gt 0) {
        $errs = @($global:Error)
        $global:Error.Clear()
        [array]::Reverse($errs)
        foreach ($er in $errs) {
            $line = if ($er.InvocationInfo) { $er.InvocationInfo.ScriptLineNumber } else { "?" }
            Write-WidgetLog ("PS error @ line {0}: {1}" -f $line, $er.ToString()) "ERROR"
        }
    }
}

$pollTimer.Add_Tick({
    if ($script:IsClosing) { return }
    Flush-ErrorsToLog
    try {
        if ($script:IsRefreshing) {
            # Watchdog: HttpClient times out long before this, but never hang forever
            if (((Get-Date) - $script:RefreshStarted).TotalSeconds -lt 90) { return }
            Write-WidgetLog "Refresh did not finish within 90 s, starting a new one" "WARN"
            $script:IsRefreshing = $false
        }
        # HTTP 429 backoff: skip automatic polls until the pause is over
        if ((Get-Date) -lt $script:BackoffUntil) {
            Update-StatusLine
            return
        }
        # v4.4: every market of interest closed -> poll only every N minutes
        $lastData = if ($null -ne $script:LastDataTime) { [DateTime]$script:LastDataTime } else { [DateTime]::MinValue }
        if (Test-ClosedPollSkip -States @(Get-PrioMarketStates) -LastData $lastData -ClosedMinutes ([int]$script:Config.ClosedPollMinutes)) {
            Update-StatusLine
            return
        }
        # Asynchronous: alerts + UI update run when the data has arrived
        Refresh-AllMarketData
    } catch {
        Write-WidgetLog "Poll tick failed: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" "ERROR"
    }
})

# 1-second UI timer: market status countdown & "market open" notifications
$uiTimer = New-Object System.Windows.Forms.Timer
$uiTimer.Interval = 1000
$script:LastUiTick = [DateTime]::MinValue
$uiTimer.Add_Tick({
    if ($script:IsClosing) { return }
    # v4.0: the 1-second timer did not run for a while -> the PC slept. The
    # data is old and a rate-limit pause from before the sleep is over.
    $nowTick = Get-Date
    $gapFrom = $script:LastUiTick
    $script:LastUiTick = $nowTick
    if (Test-ResumeGap -Last $gapFrom -Now $nowTick -ThresholdSec 90) {
        Write-WidgetLog ("Resume detected (no timer tick for {0:N0} s), refreshing" -f ($nowTick - $gapFrom).TotalSeconds)
        $script:BackoffUntil = [DateTime]::MinValue
        $script:BackoffLevel = 0
        if ($script:IsRefreshing -and (($nowTick - $script:RefreshStarted).TotalSeconds -gt 30)) { $script:IsRefreshing = $false }
        Set-TransientStatus "Aufgewacht - Kurse werden aktualisiert..." 4
        try { Refresh-AllMarketData -Force } catch { Write-WidgetLog "Resume refresh failed: $($_.Exception.Message)" "WARN" }
    }
    try {
        if ($form.Visible) { Update-MarketStatusUi; Update-StatusLine }
        Check-MarketOpenNotifications
        if ($script:PushPending.Count -gt 0) { Pump-PushTasks }
        if ($script:StartupDone -and -not [bool]$script:Config.FirstRunDone -and $form.Visible -and -not $script:TourShown -and -not $script:SmokeMode) {
            $script:TourShown = $true
            Show-WelcomeTour
        }
        if ($nowTick -ge $script:NextEventsCheck) {
            $script:NextEventsCheck = $nowTick.AddMinutes(10)
            Update-EventsIfStale
            Check-EarningsNotifications
            Invoke-DailyBackup
            Invoke-SavingsPlans   # v5.0
            Request-DailySignals  # v5.7
        }
        # v4.9: news feed (also in the background, for the unread count)
        if ($script:StartupDone -and $nowTick -ge $script:NextNewsLoad) {
            $allClosed = Test-AllPrioClosed
            $script:NextNewsLoad = $nowTick.AddMinutes(1)
            $script:NewsAllClosed = $allClosed
            Start-NewsLoad
        }
    } catch {
        Write-WidgetLog "UI tick failed: $($_.Exception.Message)" "WARN"
    }
})

# Buttons normally swallow Left/Right as focus navigation, so the global
# "previous/next ticker" shortcut never fired. Mark them as input keys.
function Register-ArrowKeysAsInput {
    param([System.Windows.Forms.Control]$Root)
    foreach ($ctl in $Root.Controls) {
        if ($ctl -is [System.Windows.Forms.Button]) {
            $ctl.Add_PreviewKeyDown({
                param($sender, $e)
                if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Left -or $e.KeyCode -eq [System.Windows.Forms.Keys]::Right) {
                    $e.IsInputKey = $true
                }
            })
        }
        if ($ctl.HasChildren) { Register-ArrowKeysAsInput -Root $ctl }
    }
}
Register-ArrowKeysAsInput -Root $form

$form.Add_Shown({
    Flush-ErrorsToLog
    $script:StartupMs = [int]$script:StartWatch.ElapsedMilliseconds
    Write-WidgetLog ("Widget v{0} window shown after {1} ms" -f $script:AppVersion, $script:StartupMs)
    $txtPortTicker.Text = $script:Config.ActiveTicker
    Apply-ThemeToAllControls
    $wasMax = [bool]$script:Config.WindowMaximized
    Apply-Layout ([string]$script:Config.Layout)
    Apply-TooltipMode
    if ($wasMax -and -not [bool]$script:Config.CompactMode) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
    }
    $script:StartupDone = $true
    Add-FocusRings $form
    Update-PrivacyIndicator
    if ([bool]$script:Config.OverviewOnStart -and -not $script:SmokeMode -and -not [string]$script:Config.ReopenAnalysis) {
        # a moment later, so the first quotes are there
        $script:OverviewTimer = New-Object System.Windows.Forms.Timer
        $script:OverviewTimer.Interval = 1500
        $script:OverviewTimer.Add_Tick({ $script:OverviewTimer.Stop(); Show-OverviewDialog })
        $script:OverviewTimer.Start()
    }
    # v5.0: back to where you were: full-page list, open Analyse window
    if ([string]$script:Config.Layout -eq "Terminal" -and [string]$script:Config.TerminalFull -in @("Portfolio", "Watchlist", "News")) { Set-TerminalFull ([string]$script:Config.TerminalFull) }
    if ([string]$script:Config.ReopenAnalysis -and -not $script:SmokeMode) {
        $script:ReopenTimer = New-Object System.Windows.Forms.Timer
        $script:ReopenTimer.Interval = 1500
        $script:ReopenTimer.Add_Tick({ $script:ReopenTimer.Stop(); $pg0 = [string]$script:Config.ReopenAnalysis; $script:Config.ReopenAnalysis = ""; Show-AnalysisDialog -Page $pg0 })
        $script:ReopenTimer.Start()
    }
    # Start with focus on a button, not the search box (which used to pop the dropdown open)
    if (-not $script:Config.CompactMode) { $tabButtons[$script:Config.ActiveTab].Select() } else { $btnCompact.Select() }
    Refresh-AllMarketData -Force
    Evaluate-GlobalAlerts
    Update-AllUiViews
    $pollTimer.Start()
    $uiTimer.Start()
    try { Update-OldAutostart } catch { }
    if ($script:MigratedFromOld) {
        Set-TransientStatus "Daten aus v3 übernommen (alter Ordner unverändert)" 8
    }
    try { Show-CurrencyMismatchNotice } catch { Write-WidgetLog "Currency check failed: $($_.Exception.Message)" "WARN" }
})

$form.Add_FormClosing({
    $script:IsClosing = $true
    # v5.0: an open Analyse window opens again at the next start
    $script:Config.ReopenAnalysis = if ($null -ne $script:AnaCtl -and -not $script:SmokeMode) { [string]$script:AnaCtl.Page } else { "" }
    if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed) { try { $script:FsForm.Close() } catch { } }
    $pollTimer.Stop()
    $uiTimer.Stop()
    $tapeTimer.Stop()
    $searchTimer.Stop()
    $wlSearchTimer.Stop()
    # Let running background fetches bail out (their callbacks are skipped)
    Stop-FetchWorker
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) {
        $script:Config.WindowX = $form.Location.X
        $script:Config.WindowY = $form.Location.Y
        Save-WindowSize
    }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Prune-IntradayCache
    Save-JsonState -Path $script:CachePath  -Data $script:IntradayCache
    Save-QuoteCache
    $trayIcon.Visible = $false
    Write-WidgetLog "Widget closing"
    # Resources are disposed after Application.Run returns: a refresh may still
    # be on the call stack (inside DoEvents) and must not hit disposed objects.
})

# ==============================================================================
# v4.7: UI smoke test (CI). TW_SMOKE_TEST = report path. Starts the real
# window, opens every dialog (closed again by a timer), runs commands and
# layout switches, then writes a JSON report and exits with the error count.
# ==============================================================================
$script:SmokeMode = [bool]$env:TW_SMOKE_TEST
$script:SmokeSteps = New-Object System.Collections.Generic.List[PSObject]
$script:SmokeFailures = New-Object System.Collections.Generic.List[string]
$script:SmokeNotes = New-Object System.Collections.Generic.List[string]
$script:SmokeProgErrors = @("CommandNotFoundException", "ParameterBindingFailed", "ParameterArgumentTransformationError", "NamedParameterNotFound",
    "PositionalParameterNotFound", "MethodNotFound", "MethodCountCouldNotFindBest", "InvokeMethodOnNull", "NullArray", "PropertyAssignmentException",
    "PropertyNotFound", "InvalidCastFromStringToInteger", "ArgumentTransformationError", "RuntimeException", "IndexOutOfRangeException", "NullReferenceException", "VariableIsUndefined")

function Get-SmokeErrors {
    # Errors since the last call: programming errors fail the step, the rest are notes
    param([string]$Step)
    $fails = @()
    if ($global:Error.Count -gt 0) {
        $errs = @($global:Error)
        $global:Error.Clear()
        [array]::Reverse($errs)
        foreach ($er in $errs) {
            $id = [string]$er.FullyQualifiedErrorId
            $ln = if ($er.InvocationInfo) { $er.InvocationInfo.ScriptLineNumber } else { 0 }
            $msg = "{0} @ line {1}: {2} [{3}]" -f $Step, $ln, $er.ToString(), $id
            $isProg = $false
            foreach ($p in $script:SmokeProgErrors) { if ($id -like "$p*") { $isProg = $true; break } }
            if ($isProg) { $fails += $msg } else { $script:SmokeNotes.Add($msg) }
        }
    }
    return $fails
}

function Invoke-SmokeStep {
    param([string]$Name, [scriptblock]$Action, [int]$CloseAfterMs = 1200)
    [void](Get-SmokeErrors -Step "before $Name")
    $script:SmokeCloser.Interval = $CloseAfterMs
    $script:SmokeCloser.Start()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $true; $err = ""
    $rendErr0 = [int]$script:ChartRenderErrors
    try { & $Action } catch { $ok = $false; $err = "{0} @ line {1}" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber }
    if ([int]$script:ChartRenderErrors -gt $rendErr0 -and -not $err) { $ok = $false; $err = "chart render failed: " + [string]$script:LastRenderError }
    $script:SmokeCloser.Stop()
    foreach ($f in @(Get-SmokeErrors -Step $Name)) { $ok = $false; $script:SmokeFailures.Add($f) }
    if ($err) { $script:SmokeFailures.Add("$Name : $err") }
    $script:SmokeSteps.Add([PSCustomObject]@{ Name = $Name; Ok = $ok; Ms = $sw.ElapsedMilliseconds; Error = $err })
}

$script:SmokeCloser = New-Object System.Windows.Forms.Timer
$script:SmokeCloser.Add_Tick({
    # a check that is still waiting goes first: after a stall both timers are due and
    # closing first would end the step with "probe did not run" (next tick closes)
    if ($null -ne $script:SmokeProbeTimer -and $script:SmokeProbeTimer.Enabled) { return }
    # closes every window except the main window (and the fullscreen chart)
    foreach ($f in @([System.Windows.Forms.Application]::OpenForms)) {
        if ([object]::ReferenceEquals($f, $form) -or ($null -ne $script:FsForm -and [object]::ReferenceEquals($f, $script:FsForm))) { continue }
        try { $f.Close() } catch { }
    }
})

function Invoke-SmokeTest {
    $pump = { [System.Windows.Forms.Application]::DoEvents() }
    Invoke-SmokeStep "Refresh" { Refresh-AllMarketData -Force; for ($i = 0; $i -lt 60 -and $script:IsRefreshing; $i++) { Start-Sleep -Milliseconds 250; & $pump }; Evaluate-GlobalAlerts; Update-AllUiViews }
    foreach ($lay in @("Terminal", "Standard", "Compact", "Ticker", "Standard")) { Invoke-SmokeStep "Layout $lay" { Apply-Layout $lay; & $pump } }
    foreach ($tab in @("Chart", "Portfolio", "Watchlist", "News", "Chart")) { Invoke-SmokeStep "Tab $tab" { Set-ActiveTab -TabName $tab; & $pump } }
    # v4.9: the news tab with a real load (or the offline message), then fake items
    Invoke-SmokeStep "News load" {
        Set-ActiveTab -TabName "News"
        Start-NewsLoad
        for ($i = 0; $i -lt 80 -and $script:NewsLoading; $i++) { Start-Sleep -Milliseconds 250; & $pump }
        $fake = @{
            "NVDA" = @([PSCustomObject]@{ Title = "Smoke: NVDA item"; Publisher = "Test"; Link = ""; Time = (Get-Date).AddMinutes(-5); Tickers = @("MSFT") })
            "MSFT" = @([PSCustomObject]@{ Title = "Smoke: MSFT item"; Publisher = "Test"; Link = ""; Time = (Get-Date).AddHours(-30); Tickers = @() })
        }
        $script:NewsItems = @(Merge-NewsFeed -BySymbol $fake) + @($script:NewsItems)
        $script:NewsBoldSince = (Get-Date).AddHours(-1)
        Refresh-NewsGrid; & $pump
        if ($dgvNews.Rows.Count -lt 2) { throw "news grid has $($dgvNews.Rows.Count) rows" }
    }
    Invoke-SmokeStep "News filter + read" {
        foreach ($nf in @("Holdings", "Watchlist", "MSFT", "All")) { Set-NewsFilter $nf; & $pump }
        $btnNewsRead.PerformClick(); & $pump
        Set-ActiveTab -TabName "Chart"; & $pump
        $script:NewsSeenAt = (Get-Date).AddDays(-3)
        Update-NewsBadge
        if ($tabButtons["News"].Text -notlike ("*" + [char]0x25CF + "*")) { throw "no unread count on the tab: $($tabButtons['News'].Text)" }
        Set-ActiveTab -TabName "News"; & $pump
        Set-ActiveTab -TabName "Chart"; & $pump
    }
    Invoke-SmokeStep "News in Terminal" { Apply-Layout "Terminal"; Set-ActiveTab -TabName "News"; & $pump; Set-ActiveTab -TabName "Watchlist"; Apply-Layout "Standard"; & $pump }
    # v4.9.5
    Invoke-SmokeStep "News mute + menu" {
        Set-ActiveTab -TabName "News"; & $pump
        $first = @($script:NewsItems | Where-Object { $_.Publisher })[0]
        if ($null -ne $first) {
            $script:NewsMenuItem = $first
            $miNewsMute.PerformClick(); & $pump
            if (@($script:Config.NewsMuted).Count -lt 1) { throw "source not muted" }
            $script:Config.NewsMuted = @()
            Refresh-NewsGrid
        }
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "News keywords" {
        $before = $script:AlertLog.Count
        $script:Config.NewsKeywords = "smoke"
        $script:Config.NewsKeywordLastAt = (Get-Date).AddDays(-1).ToString("o")
        $script:NewsItems = @([PSCustomObject]@{ Key = "smoke-kw"; Title = "Smoke test headline"; Publisher = "Test"; Link = ""; Time = (Get-Date).AddMinutes(-1); Syms = @("NVDA") }) + @($script:NewsItems)
        Invoke-NewsKeywordCheck
        if ($script:AlertLog.Count -le $before) { throw "no keyword notice logged" }
        $script:Config.NewsKeywords = ""
    }
    Invoke-SmokeStep "Privacy mode" {
        Set-ActiveTab -TabName "Portfolio"
        Set-PrivacyMode $true; & $pump
        if ($lblPortSummary.Text -notmatch [string][char]0x2022) { throw "summary not masked: $($lblPortSummary.Text)" }
        Set-PrivacyMode $false; & $pump
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Undo + redo" {
        Set-ActiveTab -TabName "Watchlist"; & $pump   # PerformClick needs a visible button
        $script:Alerts.Add([PSCustomObject]@{ Id = "r"; Ticker = "MSFT"; Condition = ">="; TargetPrice = 99999.0; Currency = "EUR"; Triggered = $false; Note = ""; RearmMin = 0; TriggeredAt = ""; ExpiresAt = ""; Peak = 0.0; Push = $true })
        Refresh-WatchlistAndAlerts
        $n0 = $script:Alerts.Count
        $lstAlerts.SelectedIndex = $n0 - 1
        $btnDelAlert.PerformClick()
        if (-not (Invoke-Undo)) { throw "undo failed" }
        if (-not (Invoke-Redo)) { throw "redo failed" }
        if ($script:Alerts.Count -ne ($n0 - 1)) { throw "redo did not delete again ($($script:Alerts.Count))" }
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Alert snooze" {
        Set-ActiveTab -TabName "Watchlist"; & $pump
        if ($script:Alerts.Count -gt 0) {
            Set-AlertSnooze -Index 0 -Kind "1h"
            if (-not (Test-AlertSnoozed -Alert $script:Alerts[0])) { throw "not snoozed" }
            if ([string]$lstAlerts.Items[0] -notlike "*ZZZ*") { throw "list does not show the pause" }
            Set-AlertSnooze -Index 0 -Kind ""
        }
    }
    Invoke-SmokeStep "Watchlist extras" {
        $dgvWatchlist.Columns["Target"].Visible = $true
        Refresh-WatchlistAndAlerts; & $pump
        $dgvWatchlist.Columns["Target"].Visible = $false
        Refresh-WatchlistAndAlerts
        foreach ($mi in @($miRowNews, $miRowCmp, $miRowAlert)) { $script:RowMenuSym = "MSFT"; $mi.PerformClick(); & $pump }
        Set-CompareTicker -Symbol ""
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Copy table" {
        Set-ActiveTab -TabName "Watchlist"; & $pump
        [void](Copy-GridAsTable -Grid $dgvWatchlist)
        Set-ActiveTab -TabName "Portfolio"; & $pump
        [void](Copy-GridAsTable -Grid $dgvPortfolio)
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Keys F9 + full page" {
        $key = { param([System.Windows.Forms.Keys]$K) & $script:GlobalKeyHandler $form (New-Object System.Windows.Forms.KeyEventArgs($K)); & $pump }
        $was = [bool]$script:Config.PrivacyMode
        & $key ([System.Windows.Forms.Keys]::F9)
        if ([bool]$script:Config.PrivacyMode -eq $was) { throw "F9 did not toggle the privacy mode" }
        & $key ([System.Windows.Forms.Keys]::F9)
        Set-ActiveTab -TabName "Portfolio"; & $pump   # PerformClick needs a visible button
        $btnPrivacy.PerformClick(); & $pump
        if (-not [bool]$script:Config.PrivacyMode) { throw "privacy button did not switch it on" }
        Set-PrivacyMode $false
        Apply-Layout "Terminal"; & $pump
        & $key ([System.Windows.Forms.Keys]::F2 -bor [System.Windows.Forms.Keys]::Shift)
        if ($script:TerminalFull -ne "Portfolio" -or [bool]$script:ViewOn["Chart"]) { throw "Shift+F2 did not show the portfolio as a full page" }
        & $key ([System.Windows.Forms.Keys]::Escape)
        if ($script:TerminalFull -or -not [bool]$script:ViewOn["Chart"]) { throw "Esc did not return to the split view" }
        Set-ActiveTab -TabName "Watchlist"; & $pump
        $tabButtons["Watchlist"].PerformClick(); & $pump
        if ($script:TerminalFull -ne "Watchlist") { throw "second click on a shown tab did not open the full page" }
        $tabButtons["News"].PerformClick(); & $pump
        if ($script:TerminalFull -ne "News") { throw "full page did not follow the tab" }
        $tabButtons["Chart"].PerformClick(); & $pump
        if ($script:TerminalFull) { throw "Chart did not leave the full page" }
        [void](Invoke-TerminalCommand "FULL PORT"); & $pump
        [void](Invoke-TerminalCommand "FULL"); & $pump
        Apply-Layout "Standard"; & $pump
    }
    # v5.0 Stage A
    Invoke-SmokeStep "Cash account" {
        $script:Cash.Enabled = $true
        $script:Cash.Currency = "EUR"
        $script:Cash.BaselineIds = @($script:Transactions | ForEach-Object { [string]$_.Id })
        Add-CashEntry -Kind "Start" -Amount 1000
        Add-CashEntry -Kind "Einzahlung" -Amount 500
        $ci = Get-CashInfo -Currency "EUR"
        if ($null -eq $ci -or [math]::Abs($ci.Balance - 1500) -gt 0.01) { throw "cash balance wrong: $($ci.Balance)" }
        Set-ActiveTab -TabName "Portfolio"; & $pump
        Refresh-PortfolioGrid
        if ($lblPortSummary.Text -notlike "*Cash*") { throw "summary without cash: $($lblPortSummary.Text)" }
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Savings plan booking" {
        $n0 = $script:Transactions.Count
        $st = (Get-Date).AddMonths(-2)
        $script:SavingsPlans.Add([PSCustomObject]@{ Id = "smoke-plan"; Ticker = "MSFT"; Amount = 100.0; Fee = 1.0; Currency = "EUR"; Day = 3; Start = (New-Object DateTime($st.Year, $st.Month, 1)).ToString("yyyy-MM-dd"); LastBooked = ""; Active = $true })
        Save-SavingsPlans
        Invoke-SavingsPlans
        for ($i = 0; $i -lt 120 -and $script:PlansRunning; $i++) { Start-Sleep -Milliseconds 250; & $pump }
        $pl = @($script:SavingsPlans | Where-Object { $_.Id -eq "smoke-plan" })[0]
        if (-not $pl.LastBooked) { $script:SmokeNotes.Add("savings plan: nothing booked (offline?)") }
        elseif ($script:Transactions.Count -le $n0) { throw "plan marked as booked but no transaction" }
        $ci = Get-CashInfo -Currency "EUR"
        if ($pl.LastBooked -and $ci.Balance -ge 1500) { throw "the plan's buys did not reduce the cash ($($ci.Balance))" }
        [void]$script:SavingsPlans.Remove($pl)
        Save-SavingsPlans
    }
    # v5.0 Stage B
    Invoke-SmokeStep "Chart types + trades" {
        Set-ActiveTab -TabName "Chart"; Set-Timeframe -Tf "1d"; & $pump
        # date of the newest price bar: "today" has no bar on weekends, holidays or before the market opens
        $buyDay = (Get-Date).ToString("yyyy-MM-dd")
        if (@($script:ActiveSeries).Count -gt 0) { $buyDay = [DateTimeOffset]::FromUnixTimeMilliseconds([long]@($script:ActiveSeries)[-1].Ts).LocalDateTime.ToString("yyyy-MM-dd") }
        [void](Invoke-Transaction -Type "Kauf" -Ticker "NVDA" -Shares 1 -Price 100 -Fee 0 -Currency "USD" -Date $buyDay -Note "smoke")
        foreach ($ct in @("HA", "Candle", "Line")) {
            $script:Config.ChartType = $ct; $script:LastChartLayout = $null
            Update-AllUiViews; $script:ChartSignature = ""; Update-ChartCacheSignature; $pnlChartCanvas.Refresh(); & $pump
            if ($null -eq $script:LastChartLayout -and @($script:ActiveSeries).Count -ge 2) { throw "chart did not render as $ct (see widget.log)" }
        }
        $tradeTips = @($script:LastChartLayout.Legends | Where-Object { [string]$_.Tip -like "Kauf*" })
        if (@($script:ActiveSeries).Count -ge 2 -and $tradeTips.Count -eq 0) { throw "today's buy is not drawn as a marker" }
        & $script:GlobalKeyHandler $form (New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::K)); & $pump
        if ([string]$script:Config.ChartType -ne "Candle") { $acN = if ($form.ActiveControl) { $form.ActiveControl.GetType().Name + "/" + $form.ActiveControl.Name } else { "none" }; throw "K did not cycle the chart type ($($script:Config.ChartType), focus $acN)" }
        $script:Config.ChartType = "Line"; Update-AllUiViews
    }
    Invoke-SmokeStep "Compare three" {
        Switch-CompareTicker -Symbol "MSFT"; Switch-CompareTicker -Symbol "SAP.DE"; Switch-CompareTicker -Symbol "AAPL"
        if (@($script:Config.CompareMore).Count -ne 2) { throw "expected 2 extra comparisons, got $(@($script:Config.CompareMore).Count)" }
        Switch-CompareTicker -Symbol "AMD"
        if (@($script:Config.CompareMore).Count -ne 2) { throw "a fourth comparison was accepted" }
        Refresh-AllMarketData -Force
        for ($i = 0; $i -lt 60 -and $script:IsRefreshing; $i++) { Start-Sleep -Milliseconds 250; & $pump }
        Update-AllUiViews; $pnlChartCanvas.Refresh(); & $pump
        if ($script:ActiveCompareMore.Count -lt 1) { $script:SmokeNotes.Add("compare: extra lines not loaded (offline?)") }
        Set-CompareTicker -Symbol ""
        if (@($script:Config.CompareMore).Count -ne 0) { throw "clearing did not remove the extra comparisons" }
    }
    Invoke-SmokeStep "Drawings" {
        Set-ActiveTab -TabName "Chart"; Update-AllUiViews; $pnlChartCanvas.Refresh(); & $pump
        $L = Get-CanvasLayout -Canvas $pnlChartCanvas
        if ($null -eq $L) { $script:SmokeNotes.Add("drawings: no chart layout (no data?)"); return }
        $pr = $L.PriceRect
        $click = { param([int]$X, [int]$Y, $Btn = [System.Windows.Forms.MouseButtons]::Left) & $script:ChartMouseDownHandler $pnlChartCanvas (New-Object System.Windows.Forms.MouseEventArgs($Btn, 1, $X, ($Y + [int]$L.OffsetY), 0)); & $pump }
        $u = ([string]$script:Config.ActiveTicker).ToUpper()
        $n0 = if ($script:Drawings.ContainsKey($u)) { $script:Drawings[$u].Count } else { 0 }
        Set-DrawMode "H"; & $click ($pr.Left + [int]($pr.Width / 2)) ($pr.Top + [int]($pr.Height / 3))
        Set-DrawMode "T"; & $click ($pr.Left + 20) ($pr.Bottom - 30); & $click ($pr.Right - 40) ($pr.Top + 40)
        & $script:GlobalKeyHandler $form (New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::D)); & $pump
        if ($script:DrawMode -ne "T") { throw "D did not start the trend line mode" }
        Set-DrawMode "F"; & $click ($pr.Left + 60) ($pr.Bottom - 20); & $click ($pr.Left + 200) ($pr.Top + 20)
        if ($script:Drawings[$u].Count -ne ($n0 + 3)) { throw "expected 3 new drawings, got $($script:Drawings[$u].Count - $n0)" }
        $pnlChartCanvas.Refresh(); & $pump
        $L = Get-CanvasLayout -Canvas $pnlChartCanvas
        $hit = Find-DrawingAt -L $L -X ($pr.Left + 10) -Y ($pr.Top + [int]($pr.Height / 3) + [int]$L.OffsetY)
        if ($null -eq $hit -or $hit.Kind -ne "H") { throw "right-click hit test did not find the horizontal line" }
        $na = $script:Alerts.Count
        New-DrawingAlert $hit
        New-DrawingAlert (@($script:Drawings[$u] | Where-Object { $_.Kind -eq "T" })[0])
        if ($script:Alerts.Count -lt $na + 1) { $script:SmokeNotes.Add("drawing alerts: no quote yet") }
        Evaluate-GlobalAlerts
        Read-Drawings
        if ($script:Drawings[$u].Count -ne ($n0 + 3)) { throw "drawings were not saved" }
        Remove-Drawing -All
        Set-DrawMode ""
    }
    # v5.0 Stage C
    Invoke-SmokeStep "Terminal dividers" {
        Apply-Layout "Terminal"; Set-ActiveTab -TabName "Watchlist"; & $pump
        if (-not $splitChart.Visible) { throw "no divider between chart and lists" }
        $h0 = $viewChart.Height
        $script:Config.TerminalChartPct = 35; Update-MainLayout; & $pump
        if ($viewChart.Height -ge $h0) { throw "chart did not get smaller ($h0 -> $($viewChart.Height))" }
        $script:Config.TerminalChartPct = 55; Update-MainLayout
        Set-TerminalFull "Portfolio"
        if ([string]$script:Config.TerminalFull -ne "Portfolio" -or $splitChart.Visible) { throw "full page not remembered or divider still shown" }
        Set-TerminalFull ""
        Apply-Layout "Standard"; & $pump
        if ($splitChart.Visible) { throw "divider visible in Standard" }
    }
    Invoke-SmokeStep "V7.5 layouts" {
        Apply-Layout "Standard"; Set-ActiveTab -TabName "Portfolio"; & $pump
        $script:Config.PortSimOpen = $false; Update-PortSimLayout; & $pump
        $g0 = $dgvPortfolio.Height
        if ($txtPortBuyAmt.Visible) { throw "calculator inputs visible while closed" }
        if ($dgvPortfolio.Bottom -gt $pnlPortBottom.Top) { throw "portfolio list overlaps the editor (closed)" }
        $btnPortSim.PerformClick(); & $pump
        if (-not $txtPortBuyAmt.Visible) { throw "calculator did not open" }
        if ($dgvPortfolio.Height -ge $g0 -or $dgvPortfolio.Bottom -gt $pnlPortBottom.Top) { throw "portfolio list did not make room: $g0 -> $($dgvPortfolio.Height)" }
        $btnPortSim.PerformClick(); & $pump
        if ($dgvPortfolio.Height -ne $g0) { throw "closing did not restore the list height" }
        Set-ActiveTab -TabName "Watchlist"; & $pump
        $old = $viewWatch.Size
        $viewWatch.Size = New-Object System.Drawing.Size((S 1600), $old.Height); $script:Config.WatchDetail = $true; Update-WatchLayout; & $pump
        if (-not $lblWlDetail.Visible) { throw "no detail panel in a wide watchlist" }
        if ($dgvWatchlist.Right -gt $lblWlDetail.Left -or $lblWlDetail.Right -gt $lstAlerts.Left) { throw "wide watchlist panels overlap" }
        if ($lstAlerts.Width -le (S 252) -or $cmbAlertRearm.Right -gt $viewWatch.ClientSize.Width) { throw "alarm column did not widen correctly: $($lstAlerts.Width)" }
        if ($lblWlDetail.Text.Length -eq 0) { throw "detail panel is empty" }
        $viewWatch.Size = $old; Update-WatchLayout; & $pump
        if ($lblWlDetail.Visible) { throw "detail panel visible in a narrow watchlist" }
        if ($dgvWatchlist.Right -gt $lstAlerts.Left) { throw "list overlaps the alarm column" }
        Add-FocusRings $form
        if ($script:RingDone.Count -eq 0) { throw "no focus rings registered" }
        Set-ActiveTab -TabName "Portfolio"
    }
    Invoke-SmokeStep "V7.5.1 menu bar" {
        Apply-Layout "Standard"; Set-ActiveTab -TabName "Chart"; & $pump
        if (-not $script:MenuBar.Visible) { throw "menu bar hidden in Standard" }
        if ($pnlHeader.Top -lt $script:MenuBar.Bottom) { throw "header under the menu bar: $($pnlHeader.Top) < $($script:MenuBar.Bottom)" }
        if ($pnlNav.Top -lt $pnlHeader.Bottom) { throw "navigation overlaps the header" }
        if ($viewChart.Top -lt $pnlNav.Bottom) { throw "view overlaps the navigation" }
        if ($viewChart.Bottom -gt $form.ClientSize.Height) { throw "view below the window edge" }
        $names = @($script:MenuBar.Items | ForEach-Object { $_.Text }) -join ","
        if ($script:MenuBar.Items.Count -ne 6) { throw "menus: $names" }
        foreach ($m in $script:MenuBar.Items) { $m.ShowDropDown(); & $pump; $m.HideDropDown(); & $pump }
        $script:Config.PortSimOpen = $false; Update-PortSimLayout
        $script:MbCalc.PerformClick(); & $pump
        if (-not ($viewPortfolio.Visible -and $txtPortBuyAmt.Visible)) { throw "menu did not show the calculator" }
        $script:MbCalc.PerformClick(); & $pump
        if ($txtPortBuyAmt.Visible) { throw "menu did not close the calculator" }
        Apply-Layout "Compact"; & $pump
        if ($script:MenuBar.Visible -or $pnlHeader.Top -ne 0) { throw "menu bar / header wrong in Compact" }
        Apply-Layout "Standard"; & $pump
        if (-not $script:MenuBar.Visible -or $pnlHeader.Top -ne $script:MenuH) { throw "menu bar not restored" }
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Watchlist groups" {
        Set-ActiveTab -TabName "Watchlist"; & $pump
        $script:Config.WatchGroups = Set-WatchGroupMember -Groups @() -Group "Tech" -Symbol "NVDA"
        Set-WatchGroup "Tech"; & $pump
        if ($dgvWatchlist.Rows.Count -ne 1) { throw "group view shows $($dgvWatchlist.Rows.Count) rows" }
        $me = New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Right, 1, 10, 10, 0)
        & $script:RowMenuHandler $dgvWatchlist (New-Object System.Windows.Forms.DataGridViewCellMouseEventArgs(0, 0, 10, 10, $me)); & $pump
        $tg = @($miRowGroup.DropDownItems | Where-Object { [string]$_.Tag -eq "Tech" })[0]
        if ($null -eq $tg -or -not $tg.Checked) { throw "group menu does not tick the member" }
        $rowMenu.Close()
        Set-WatchGroup ""; & $pump
        if ($dgvWatchlist.Rows.Count -lt 3) { throw "'Alle' does not show the whole watchlist" }
        $script:Config.WatchGroups = @(); Update-WatchGroupCombo
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Hover card" {
        Set-ActiveTab -TabName "Watchlist"; & $pump
        & $script:HoverEnter $dgvWatchlist (New-Object System.Windows.Forms.DataGridViewCellEventArgs(0, 0))
        for ($i = 0; $i -lt 20 -and -not $pnlHover.Visible; $i++) { Start-Sleep -Milliseconds 100; & $pump }
        if (-not $pnlHover.Visible -and $script:QuoteStore.ContainsKey(([string]$dgvWatchlist.Rows[0].Cells[0].Value).ToUpper())) { throw "hover card did not appear" }
        $pnlHover.Refresh(); & $pump
        Hide-HoverCard
        if ($pnlHover.Visible) { throw "hover card did not hide" }
        Set-ActiveTab -TabName "Chart"
    }
    # v5.1
    Invoke-SmokeStep "Auto currency" {
        Set-ActiveCurrency "EUR"
        if ((Get-PriceCurrency "NVDA") -ne "EUR") { throw "fixed EUR does not show NVDA in EUR" }
        Set-ActiveCurrency "AUTO"
        if ((Get-PriceCurrency "NVDA") -ne "USD" -or (Get-PriceCurrency "SAP.DE") -ne "EUR") { throw "Auto: NVDA $(Get-PriceCurrency 'NVDA'), SAP.DE $(Get-PriceCurrency 'SAP.DE')" }
        foreach ($pair in @(@("SAP.DE", "EUR"), @("NVDA", "USD"))) {
            Switch-ActiveTicker -NewTicker $pair[0] -SkipResolve $true
            for ($i = 0; $i -lt 60 -and ($script:IsRefreshing -or @($script:ActiveSeries).Count -lt 2); $i++) { Start-Sleep -Milliseconds 250; & $pump }
            Update-AllUiViews; & $pump
            if (@($script:ActiveSeries).Count -ge 2 -and $script:ChartCur -ne $pair[1]) { throw "$($pair[0]) chart in $($script:ChartCur)" }
            if ($script:QuoteStore.ContainsKey($pair[0]) -and $lblLivePrice.Text -notlike "* $($pair[1])") { throw "$($pair[0]) header shows '$($lblLivePrice.Text)'" }
        }
        if ($btnCurrency.Text -notlike "Auto*") { throw "currency button shows '$($btnCurrency.Text)'" }
        & $script:GlobalKeyHandler $form (New-Object System.Windows.Forms.KeyEventArgs([System.Windows.Forms.Keys]::W)); & $pump
        if ([bool]$script:Config.AutoCurrency -or [string]$script:Config.Currency -ne "EUR") { throw "W after Auto should give EUR" }
        Set-ActiveCurrency "AUTO"
    } 20000
    Invoke-SmokeStep "Prev close + health" {
        Set-Timeframe -Tf "1d"; & $pump
        $cmiPrevClose.PerformClick(); & $pump
        $cmiPrevClose.PerformClick(); & $pump
        Update-StatusLine
        if (-not $script:HealthLevel) { throw "no health level after refresh" }
    }
    foreach ($th in @("OLED", "Light", "Terminal", "Dark")) { Invoke-SmokeStep "Theme $th" { $script:Config.Theme = $th; Apply-ThemeToAllControls; & $pump } }
    foreach ($cmd in @("SCALE LOG", "TF 1Y", "SCALE LIN", "IND MACD", "IND EMA", "TF 5D", "IND RSI", "IND SMA", "NVDA GP 3M", "NVDA CMP", "CMP", "PORT", "ALRT", "LAYOUT SAVE SMOKE", "LAYOUT SMOKE", "LAYOUT DEL SMOKE", "NVDA ALRT TRAIL 8", "NVDA ALRT >= 99999", "ALRT DTAG- 50", "NVDA WL", "NEWS DEPOT", "NEWS MSFT", "NEWS", "N", "PRIV ON", "PRIV OFF", "DRAW H", "DRAW CLEAR", "NVDA CMP", "CMP")) {
        Invoke-SmokeStep "Command $cmd" { $m = Invoke-TerminalCommand $cmd; if ($m) { $script:SmokeNotes.Add("Command '$cmd': $m") }; & $pump }
    }
    Invoke-SmokeStep "Fullscreen chart" { Toggle-ChartFullscreen; & $pump; Close-ChartFullscreen; & $pump }
    $dialogs = [ordered]@{
        "Settings" = { Show-SettingsDialog }
        "Glossary" = { Show-GlossaryDialog }
        "Analysis Perf" = { Show-AnalysisDialog -Page "Perf" }
        "Analysis Ret" = { Show-AnalysisDialog -Page "Ret" }
        "Analysis Alloc" = { Show-AnalysisDialog -Page "Alloc" }
        "Analysis Div" = { Show-AnalysisDialog -Page "Div" }
        "Analysis Risk" = { Show-AnalysisDialog -Page "Risk" }
        "Analysis Target" = { Show-AnalysisDialog -Page "Target" }
        "Analysis Heat" = { Show-AnalysisDialog -Page "Heat" }
        "Cash" = { Show-CashDialog }
        "Savings plans" = { Show-SavingsPlansDialog }
        "Transaction history" = { Show-TransactionHistory }
        "Transaction dialog" = { Show-TransactionDialog -Ticker "NVDA" }
        "Year report" = { Show-YearReport }
        "Buy dates" = { [void](Show-BuyDatesDialog) }
        "Alert log" = { Show-AlertLogDialog }
        "Push" = { [void](Show-PushDialog) }
        "News" = { Show-NewsDialog "NVDA" }
        "Description" = { Show-DescriptionDialog "NVDA" }
        "Ticker analysis quick" = { Show-TickerAnalysis "NVDA" }
        "Ticker dividends" = { Show-TickerDividendsDialog "MSFT" }
        "Calendar" = { Show-CalendarDialog }
        "Movers" = { Show-MoversDialog }
        "FX" = { Show-FxDialog }
        "About" = { Show-AboutDialog }
        "Help" = { Show-ShortcutHelp }
        "Restore" = { Show-RestoreDialog }
        "Compare" = { Show-CompareDialog }
        "Command palette" = { Show-CommandPalette -Initial "NV" }
        "Welcome tour" = { Show-WelcomeTour }
        "Compact options" = { Show-CompactOptions }
    }
    foreach ($k in $dialogs.Keys) { Invoke-SmokeStep "Dialog $k" $dialogs[$k] 2500 }
    Invoke-SmokeStep "Settings search" {
        $script:SettingsSearchHits = -1
        $script:SmokeTyper = New-Object System.Windows.Forms.Timer
        $script:SmokeTyper.Interval = 700
        $script:SmokeTyper.Add_Tick({
            $script:SmokeTyper.Stop()
            foreach ($f in @([System.Windows.Forms.Application]::OpenForms)) {
                $hit = $f.Controls.Find("tSettingsSearch", $true)
                if ($hit.Count -gt 0) { $hit[0].Text = "push"; $script:SmokeSearchPush = $script:SettingsSearchHits; $hit[0].Text = "xyzxyz"; $script:SmokeSearchNone = $script:SettingsSearchHits; $hit[0].Text = "" }
            }
        })
        $script:SmokeSearchPush = -1; $script:SmokeSearchNone = -1
        $script:SmokeTyper.Start()
        Show-SettingsDialog
        $script:SmokeTyper.Stop()
        if ($script:SmokeSearchPush -lt 1) { throw "search 'push' found $($script:SmokeSearchPush) settings" }
        if ($script:SmokeSearchNone -ne 0) { throw "nonsense search found $($script:SmokeSearchNone) settings" }
    } 2500
    # v5.0: the Analyse pages again with time to load the price history
    foreach ($pg in @("Risk", "Target", "Heat")) { Invoke-SmokeStep "Analysis $pg loaded" { Show-AnalysisDialog -Page $pg } 12000 }
    # v5.1: look inside the open window shortly before it is closed
    $script:SmokeProbeTimer = New-Object System.Windows.Forms.Timer
    $script:SmokeProbeTimer.Add_Tick({ $script:SmokeProbeTimer.Stop(); try { $script:SmokeProbeResult = & $script:SmokeProbe } catch { $script:SmokeProbeResult = "probe failed: " + $_.Exception.Message } })
    $probeRun = {
        param([scriptblock]$Open, [scriptblock]$Probe, [int]$At)
        $script:SmokeProbe = $Probe; $script:SmokeProbeResult = "probe did not run"
        $script:SmokeProbeTimer.Interval = $At; $script:SmokeProbeTimer.Start()
        & $Open
        $script:SmokeProbeTimer.Stop()
        if ($script:SmokeProbeResult) { throw [string]$script:SmokeProbeResult }
    }
    Invoke-SmokeStep "Analysis Contrib + scenario" {
        & $probeRun { Show-AnalysisDialog -Page "Contrib" } {
            $ac = $script:AnaCtl
            if ($null -eq $ac) { return "window not open" }
            if ($ac.CGrid.Rows.Count -lt 2) { return "contribution grid has $($ac.CGrid.Rows.Count) rows" }
            $ac.SNum.Value = -30; [System.Windows.Forms.Application]::DoEvents()
            if ($ac.SGrid.Rows.Count -lt 1 -or -not $ac.SRes.Text) { return "scenario empty" }
            Set-AnalysisRange "1Y"; Set-AnalysisRange "Max"
            return ""
        } 11000
    } 13000
    Invoke-SmokeStep "Analysis Bench" {
        & $probeRun { Show-AnalysisDialog -Page "Bench" } {
            $ac = $script:AnaCtl
            if ($null -eq $ac) { return "window not open" }
            Update-AnalysisBench
            if ($ac.BGrid.Rows.Count -lt 2) { return "comparison grid has $($ac.BGrid.Rows.Count) rows" }
            if (@($ac.BLines | Where-Object { $null -ne $_.Win }).Count -lt 2) { return "fewer than 2 lines (indices not loaded)" }
            $ac.BChart.Refresh()
            if ($ac.SecGrid.Rows.Count -lt 1) { return "no sector rows" }
            return ""
        } 11000
    } 13000
    Invoke-SmokeStep "Ticker analysis" {
        & $probeRun { Show-TickerAnalysis "MSFT" } {
            $c = $script:TaCtl
            if ($null -eq $c) { return "window not open" }
            if ($null -eq $c.Bars) { return "no daily bars loaded" }
            if ($c.TGrid.Rows.Count -lt 8) { return "only $($c.TGrid.Rows.Count) signal rows" }
            $c.Chart.Refresh()
            $c.Dlg.Width = $c.Dlg.Width + 40
            if ($c.FGrid.Rows.Count -lt 1) { return "no fundamentals rows" }
            return ""
        } 9000
    } 11000
    Invoke-SmokeStep "Compact with depot line" {
        $script:Config.CompactShow = "Depot,Spark,DayAbs"
        Apply-Layout "Compact"; & $pump; Update-MarketStatusUi
        Apply-Layout "Ticker"; & $pump
        $script:Config.CompactShow = "DayAbs,Ext,Spark,Market"
        Apply-Layout "Standard"; & $pump
    }
    Invoke-SmokeStep "Grid edit" {
        Set-ActiveTab -TabName "Portfolio"; & $pump
        if ($dgvPortfolio.Rows.Count -gt 0) {
            $dgvPortfolio.CurrentCell = $dgvPortfolio.Rows[0].Cells["Shares"]
            [void]$dgvPortfolio.BeginEdit($true)
            $dgvPortfolio.CurrentCell.Value = "12"
            [void]$dgvPortfolio.EndEdit()
            & $pump
            [void](Invoke-Undo)
        }
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "Depot switch" {
        $script:Config.Depots = @([PSCustomObject]@{ Id = "smoke"; Name = "Smoke" })
        Switch-Depot "smoke"; & $pump
        Switch-Depot ""; & $pump
    }
    Invoke-SmokeStep "Undo" {
        $script:Alerts.Add([PSCustomObject]@{ Id = "x"; Ticker = "AAPL"; Condition = ">="; TargetPrice = 1.0; Currency = "EUR"; Triggered = $false; Note = ""; RearmMin = 0; TriggeredAt = ""; ExpiresAt = ""; Peak = 0.0; Push = $true })
        Refresh-WatchlistAndAlerts
        $lstAlerts.SelectedIndex = $script:Alerts.Count - 1
        $btnDelAlert.PerformClick()
        [void](Invoke-Undo)
    }
    Invoke-SmokeStep "Click-through" { Set-ClickThrough $true; Set-ClickThrough $false }
    Invoke-SmokeStep "Backup" { [void](Backup-DataFiles -Reason "smoke"); Invoke-DailyBackup }
    Invoke-SmokeStep "English main window" { $script:Config.Language = "EN"; Apply-Language $form; Apply-Language $trayMenu; Apply-Language $chartContextMenu; Update-AllUiViews; & $pump }
    Invoke-SmokeStep "English settings" { Show-SettingsDialog } 2500
    Invoke-SmokeStep "English analysis" { Show-AnalysisDialog -Page "Div" } 2500
    Invoke-SmokeStep "English palette" { Show-CommandPalette -Initial "NVDA " } 2000
    Invoke-SmokeStep "English help text" { Show-ShortcutHelp } 2000
    $script:Config.Language = "DE"
    # v5.2: design styles, with screenshots for the review (TW_SMOKE_SHOTS = folder)
    $shot = {
        param([string]$Name, $Win = $null)
        $dirS = [string]$env:TW_SMOKE_SHOTS
        if (-not $dirS) { return }
        if (-not (Test-Path $dirS)) { New-Item -ItemType Directory -Path $dirS -Force | Out-Null }
        $wf = if ($null -ne $Win) { $Win } else { $form }
        try { $wf.Activate() } catch { }
        for ($k = 0; $k -lt 6; $k++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 60 }
        $b = $wf.Bounds
        $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
        $gS = [System.Drawing.Graphics]::FromImage($bmp)
        try { $gS.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size) } catch { $gS.Dispose(); $gS = $null; $wf.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $b.Width, $b.Height))) }
        if ($null -ne $gS) { $gS.Dispose() }
        $bmp.Save((Join-Path $dirS ($Name + ".png")), [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
    Invoke-SmokeStep "Design styles" {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.SetBounds($wa.X, $wa.Y, [math]::Min($wa.Width, 1600), [math]::Min($wa.Height, 1000))
        Apply-Layout "Terminal"; Set-ActiveTab -TabName "Watchlist"; & $pump
        $script:Config.Theme = "Dark"; [void](Invoke-TerminalCommand "STYLE REFINED"); & $pump
        if ($script:UiSpec.Fresh) { throw "STYLE REFINED did not switch" }
        & $shot "01-refined-dark-terminal"
        [void](Invoke-TerminalCommand "STYLE FRESH"); & $pump
        if (-not $script:UiSpec.Fresh) { throw "STYLE FRESH did not switch" }
        if ($script:IconFont -and $btnSettings.Text -ne [string][char]0xE713) { throw "settings button has no icon ('$($btnSettings.Text)')" }
        $want = S ([math]::Round([int]$script:UiSpec.RowH * $script:GridRowScale))
        if ($dgvWatchlist.RowTemplate.Height -ne $want) { throw "row height $($dgvWatchlist.RowTemplate.Height), expected $want" }
        $pnlChartCanvas.Refresh(); $viewWatch.Refresh(); $btnRefreshNow.Refresh()
        & $shot "02-fresh-dark-terminal"
        $script:Config.Theme = "Light"; Apply-ThemeToAllControls; & $pump
        & $shot "03-fresh-light-terminal"
        $script:Config.Theme = "Graphite"; $script:Config.ZebraRows = $true; $script:Config.RowDensity = "Comfortable"; $script:Config.AccentColor = "Windows"; Apply-ThemeToAllControls; & $pump
        if ($null -eq $script:Pal.Warn) { throw "palette has no Warn colour" }
        & $shot "04-fresh-graphite-zebra-windows-accent"
        Apply-Layout "Standard"; Set-ActiveTab -TabName "Portfolio"; & $pump
        & $shot "05-fresh-graphite-portfolio"
        $script:Config.UseIcons = $false; Apply-Icons
        if ($btnSettings.Text -ne [string][char]0x2699) { throw "icons off did not restore the text" }
        $script:Config.UseIcons = $true
        $script:Config.Theme = "Dark"; $script:Config.ZebraRows = $false; $script:Config.RowDensity = "Normal"; $script:Config.AccentColor = "Sky"
        [void](Invoke-TerminalCommand "STYLE REFINED")
        Apply-Layout "Compact"; & $pump
        $script:Config.TapeSpeed = "Fast"; for ($k = 0; $k -lt 10; $k++) { Start-Sleep -Milliseconds 20; & $pump }
        & $shot "06-refined-compact-tape"
        $script:Config.TapeSpeed = "Normal"
        Apply-Layout "Terminal"; Set-ActiveTab -TabName "Watchlist"; & $pump
    } 20000
    $script:SmokeShot = $shot
    [void](Invoke-TerminalCommand "STYLE FRESH")
    Invoke-SmokeStep "Design ticker analysis" { & $probeRun { Show-TickerAnalysis "NVDA" } { & $script:SmokeShot "07-fresh-ticker-analysis" ([System.Windows.Forms.Form]::ActiveForm); "" } 8000 } 10000
    Invoke-SmokeStep "V10 overview" { & $probeRun { Show-OverviewDialog } {
        if ($null -eq $script:Ov) { return "window not open" }
        $script:Ov.Canvas.Refresh()
        if ($script:Ov.Hits.Count -lt 3) { return "overview rows: $($script:Ov.Hits.Count)" }
        & $script:SmokeShot "22-overview" $script:Ov.Dlg
        $keepT = $script:Config.Theme; $script:Config.Theme = "Light"; $script:Pal = Get-ThemeColors; $script:Ov.Canvas.BackColor = $script:Pal.BodyBg; $script:Ov.Canvas.Refresh()
        & $script:SmokeShot "23-overview-light" $script:Ov.Dlg
        $script:Config.Theme = $keepT; $script:Pal = Get-ThemeColors
        return ""
    } 2500 } 4000
    Invoke-SmokeStep "V10.2 overview clicks + privacy" {
        $keepTicker = [string]$script:Config.ActiveTicker
        $keepGoal = $script:Config.DepotGoals
        $script:Config.DepotGoals = Set-DepotGoal -Goals @() -Id ([string]$script:Config.ActiveDepot) -Value 10000.0
        $script:SmokePicked = ""
        & $probeRun { Show-OverviewDialog } {
            if ($null -eq $script:Ov) { return "window not open" }
            Set-PrivacyMode $true; $script:Ov.Canvas.Refresh(); & $script:SmokeShot "24-overview-privacy" $script:Ov.Dlg; Set-PrivacyMode $false
            $script:Ov.Canvas.Refresh()
            $hit = @($script:Ov.Hits.ToArray() | Where-Object { $_.Kind -eq "Ticker" -and $_.Arg -ne [string]$script:Config.ActiveTicker })[0]
            if ($null -eq $hit) { return "no other ticker row" }
            $script:SmokePicked = [string]$hit.Arg
            $kind = Invoke-OverviewClick -At (New-Object System.Drawing.Point(($hit.R.X + 5), ($hit.R.Y + 5)))
            if ($kind -ne "Ticker") { return "click hit '$kind'" }
            return ""
        } 2500
        $script:Config.DepotGoals = $keepGoal
        & $pump
        if ([string]$script:Config.ActiveTicker -ne $script:SmokePicked) { throw "click did not switch to $($script:SmokePicked): $($script:Config.ActiveTicker)" }
        if ([string]$script:Config.ActiveTab -ne "Chart") { throw "chart tab not shown" }
        Switch-ActiveTicker -NewTicker $keepTicker -SkipResolve $true; & $pump
    } 6000
    Invoke-SmokeStep "V10.4 broker" {
        $saved = @($script:Transactions.ToArray())
        try {
            $script:Transactions.Clear()
            $year = (Get-Date).Year
            Add-TransactionRecord -Type "Kauf" -Ticker "NVDA" -Shares 10 -Price 100 -Fee 1 -Currency "EUR" -Date "$year-01-10" -Broker "Flatex"
            Add-TransactionRecord -Type "Kauf" -Ticker "MSFT" -Shares 5 -Price 300 -Fee 7.5 -Currency "EUR" -Date "$year-02-11" -Broker "Hausbank" -Note "Smoke Sparplan"
            Add-TransactionRecord -Type "Verkauf" -Ticker "NVDA" -Shares 2 -Price 140 -Fee 1 -Currency "EUR" -Date "$year-03-12" -Realized 79
            & $probeRun { Show-TransactionHistory } {
                $h = $script:TxHist
                if ($null -eq $h) { return "window not open" }
                if ($h.Grid.Rows.Count -ne 3) { return "rows $($h.Grid.Rows.Count)" }
                $h.BrokerF.SelectedIndex = 1
                if ($h.Grid.Rows.Count -ne 1) { return "no-broker filter: $($h.Grid.Rows.Count)" }
                $h.BrokerF.SelectedIndex = 0; $h.Find.Text = "sparplan"
                if ($h.Grid.Rows.Count -ne 1) { return "search: $($h.Grid.Rows.Count)" }
                $h.Find.Text = ""
                & $script:SmokeShot "25-history-broker" $h.Dlg
                return ""
            } 2500
            & $probeRun { Show-TransactionDialog -Ticker "NVDA" } {
                if ($null -eq $script:TxDlg) { return "window not open" }
                if ($script:TxDlg.Broker.Text -ne "Flatex") { return "broker not preset: '$($script:TxDlg.Broker.Text)'" }
                & $script:SmokeShot "26-booking-broker" $script:TxDlg.Dlg
                return ""
            } 2000
            & $probeRun { Show-GoalsCostsDialog } {
                $gc = $script:GoalCtl
                if ($null -eq $gc) { return "window not open" }
                $gc.Group.SelectedIndex = 1
                if ($gc.Grid.Rows.Count -lt 3) { return "broker rows $($gc.Grid.Rows.Count)" }
                & $script:SmokeShot "27-costs-per-broker" $gc.Dlg
                return ""
            } 2500
        } finally {
            $script:Transactions.Clear()
            foreach ($t in $saved) { $script:Transactions.Add($t) }
            Save-Transactions
        }
    } 14000
    Invoke-SmokeStep "V10.6 goals for all depots" {
        $keepDepots = $script:Config.Depots; $keepGoals = $script:Config.DepotGoals
        $keepAll = @($script:Config.GoalAllValue, $script:Config.GoalAllDividend)
        $dir = Join-Path $script:DepotDir "smoke-zweit"
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $dir "portfolio.json"), '{"NVDA":{"Shares":4,"AvgPrice":90,"Currency":"USD"}}')
            $script:Config.Depots = @([PSCustomObject]@{ Id = "smoke-zweit"; Name = "Zweitdepot" })
            $script:Config.DepotGoals = @()
            & $probeRun { Show-GoalsCostsDialog } {
                $gc = $script:GoalCtl
                if ($null -eq $gc) { return "window not open" }
                if ($gc.Goals.Rows.Count -ne 3) { return "goal rows $($gc.Goals.Rows.Count)" }
                $gc.Goals.Rows[0].Cells["ValueGoal"].Value = "8000"
                $gc.Goals.Rows[1].Cells["ValueGoal"].Value = "500"
                $gc.Goals.Rows[2].Cells["ValueGoal"].Value = "20000"
                $gc.Goals.Rows[2].Cells["DivGoal"].Value = "100"
                $gc.Goals.Rows[1].Cells["DivGoal"].Value = "abc"
                if (-not (Save-GoalsFromGrid)) { return "bad number accepted" }
                if ((Get-DepotGoal -Goals $script:Config.DepotGoals -Id "").Value -ne 0) { return "saved despite the error" }
                $gc.Goals.Rows[1].Cells["DivGoal"].Value = ""
                $err = Save-GoalsFromGrid
                if ($err) { return $err }
                Update-GoalsView; $gc.Goals.Refresh()
                if ((Get-DepotGoal -Goals $script:Config.DepotGoals -Id "smoke-zweit").Value -ne 500) { return "second depot goal not saved" }
                if ([double]$script:Config.GoalAllValue -ne 20000) { return "total goal not saved" }
                if ([string]$gc.Goals.Rows[1].Cells["ValuePct"].Value -notmatch '%') { return "no progress for the second depot: '$($gc.Goals.Rows[1].Cells["Value"].Value)'" }
                & $script:SmokeShot "28-goals-all-depots" $gc.Dlg
                # background load of a symbol that only the second depot holds
                [System.IO.File]::WriteAllText((Join-Path $script:DepotDir "smoke-zweit\portfolio.json"), '{"IBM":{"Shares":1,"AvgPrice":100,"Currency":"USD"}}')
                $script:QuoteStore.Remove("IBM")
                Start-GoalDataLoad
                for ($i = 0; $i -lt 40 -and -not $script:QuoteStore.ContainsKey("IBM"); $i++) { Start-Sleep -Milliseconds 250; [System.Windows.Forms.Application]::DoEvents() }
                if (-not $script:QuoteStore.ContainsKey("IBM")) { $script:SmokeNotes.Add("goals: quote of the second depot not loaded (offline?)") }
                else {
                    Update-GoalsView
                    if ([string]$gc.Goals.Rows[1].Cells["Value"].Value -notmatch '\d') { return "loaded quote not shown" }
                    $script:SmokeNotes.Add("goals: background quote of the second depot loaded")
                }
                return ""
            } 3000
        } finally {
            $script:QuoteStore.Remove("IBM")
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
            $script:Config.Depots = $keepDepots; $script:Config.DepotGoals = $keepGoals
            $script:Config.GoalAllValue = $keepAll[0]; $script:Config.GoalAllDividend = $keepAll[1]
            Save-Config
        }
    } 20000
    Invoke-SmokeStep "Design settings" { & $probeRun { Show-SettingsDialog } { & $script:SmokeShot "08-fresh-settings" ([System.Windows.Forms.Form]::ActiveForm); "" } 1200 } 2500
    Invoke-SmokeStep "V7.7 news sources + reading" -CloseAfterMs 2500 -Action {
        Apply-Layout "Standard"; Set-ActiveTab -TabName "News"; & $pump
        for ($i = 0; $i -lt 80 -and $script:NewsLoading; $i++) { Start-Sleep -Milliseconds 250; & $pump }
        $keepItems = @($script:NewsItems)
        $src = @(ConvertTo-NewsSourceList @([PSCustomObject]@{ Url = "https://example.invalid/rss"; Name = "SmokeFeed"; Group = "Test" }))
        $script:Config.NewsSources = $src
        $fid = [string]$src[0].Id
        $mk = { param($k, $title, $sid) [PSCustomObject]@{ Key = $k; Title = $title; Publisher = $sid; Link = ""; Time = (Get-Date).AddMinutes(-3); Syms = @("NVDA"); Summary = "Kurztext zum Test"; Image = ""; Sources = @($sid); Also = @() } }
        $script:NewsItems = @((& $mk "s-y" "Smoke yahoo headline about chips today" "yahoo"), (& $mk "s-f" "Completely different feed story regarding energy" $fid))
        Set-NewsFilter "All"; Update-NewsViews; & $pump
        if ($dgvNews.Rows.Count -ne 2) { throw "two sources, rows: $($dgvNews.Rows.Count)" }
        Set-NewsViewHidden @($fid); & $pump
        if ($dgvNews.Rows.Count -ne 1) { throw "hidden source still shown: $($dgvNews.Rows.Count)" }
        Set-NewsViewHidden @(); $script:Config.NewsSources[0].On = $false; Update-NewsViews; & $pump
        if ($dgvNews.Rows.Count -ne 1) { throw "switched-off source still shown: $($dgvNews.Rows.Count)" }
        $script:Config.NewsSources[0].On = $true; Update-NewsViews; & $pump
        Build-NewsSourceMenu
        if ($script:NewsSourceMenu.Items.Count -lt 6) { throw "source menu items: $($script:NewsSourceMenu.Items.Count)" }
        $script:NewsSourceMenu.Show($btnNewsSources, 0, $btnNewsSources.Height); & $pump
        $script:NewsSourceMenu.Items[0].PerformClick(); & $pump
        if (@($script:Config.NewsViewHidden).Count -ne 1) { throw "menu tick did not hide a source" }
        $script:NewsSourceMenu.Close(); Set-NewsViewHidden @()
        $txtNewsSearch.Text = "energy"; & $pump
        if ($dgvNews.Rows.Count -ne 1) { throw "search rows: $($dgvNews.Rows.Count)" }
        $txtNewsSearch.Text = ""; & $pump
        $dgvNews.ClearSelection(); $dgvNews.Rows[0].Selected = $true; & $pump
        $one = Get-SelectedNews
        Switch-NewsSaved $one; & $pump
        $btnNewsSaved.PerformClick(); & $pump
        if ($dgvNews.Rows.Count -ne 1 -or $null -eq $dgvNews.Rows[0].Tag) { throw "saved view rows: $($dgvNews.Rows.Count)" }
        $btnNewsSaved.PerformClick(); & $pump
        Switch-NewsSaved $one
        Set-NewsReadMark -Item $one -Read $false
        if (-not (Test-NewsUnread -Item $one -Since ([DateTime]::MaxValue) -ReadKeys $script:NewsRead -UnreadKeys $script:NewsUnread)) { throw "unread mark lost" }
        Set-NewsReadMark -Item $one -Read $true
        Set-NewsPreview $true; & $pump
        $dgvNews.ClearSelection(); $dgvNews.Rows[0].Selected = $true; & $pump
        if (-not $pnlNewsPreview.Visible -or $lblNpText.Text -ne "Kurztext zum Test") { throw "preview: visible=$($pnlNewsPreview.Visible) text=$($lblNpText.Text)" }
        if ($pnlNewsPreview.Top -lt $dgvNews.Bottom -or $pnlNewsPreview.Bottom -gt $viewNews.Height) { throw "preview overlaps the list or leaves the tab" }
        Set-NewsPreview $false; & $pump
        # a feed answer goes through parsing, matching and status; 429 pauses only that host
        $u = "https://example.invalid/rss"
        $box = @{ Results = @{ $u = '<rss><channel><title>S</title><item><title>NVIDIA smoke feed item</title><link>https://example.invalid/a?id=1</link></item></channel></rss>' }; Meta = @{ $u = @{ Code = 200; Error = ""; ETag = ""; Modified = "" } } }
        $before = $script:BackoffUntil
        Receive-FeedResults -Box $box -Requests @([PSCustomObject]@{ Url = $u; Id = $fid; Ticker = "NVDA" })
        if ($script:FeedStatus[$fid].Error -or $script:FeedStatus[$fid].Count -ne 1) { throw "feed status: $($script:FeedStatus[$fid].Error) / $($script:FeedStatus[$fid].Count)" }
        $box = @{ Results = @{ $u = $null }; Meta = @{ $u = @{ Code = 429; Error = "" } } }
        Receive-FeedResults -Box $box -Requests @([PSCustomObject]@{ Url = $u; Id = $fid; Ticker = "" })
        if ($script:BackoffUntil -ne $before) { throw "a feed rate limit changed the price back-off" }
        if (-not $script:FeedPause.ContainsKey((Get-ProviderOfUrl $u))) { throw "feed host not paused" }
        Update-NewsViews; & $pump
        if ($lblNewsInfo.Text -notmatch "SmokeFeed") { throw "failed feed not named: $($lblNewsInfo.Text)" }
        $script:Config.ShowNewsMarkers = $true; Set-ActiveTab -TabName "Chart"; $script:ChartSignature = ""; Update-AllUiViews; & $pump; if ($script:SmokeShot) { & $script:SmokeShot "12-news-markers" }
        $script:Config.ShowNewsMarkers = $false
        Set-ActiveTab -TabName "News"; Set-NewsPreview $true; & $pump; if ($script:SmokeShot) { & $script:SmokeShot "13-news-preview" }; Set-NewsPreview $false
        $script:FeedPause.Clear(); $script:FeedStatus.Remove($fid)
        $script:NewsHistory = @(); $script:NewsSaved = @()
        $script:Config.NewsSources = @(); $script:NewsItems = $keepItems; Update-NewsViews
        Set-ActiveTab -TabName "Chart"
    }
    Invoke-SmokeStep "V7.7 feed manager" -CloseAfterMs 5000 -Action {
        $script:Config.NewsSources = @(ConvertTo-NewsSourceList @([PSCustomObject]@{ Url = "https://example.invalid/rss?q={name}"; Name = "Vorlage" }))
        & $probeRun { Show-FeedManager } {
            if ($null -eq $script:FeedDlg -or $script:FeedDlg.Dlg.IsDisposed) { return "window not open" }
            if ($script:FeedDlg.Grid.Rows.Count -ne 2) { return "rows: $($script:FeedDlg.Grid.Rows.Count)" }
            if ($script:SmokeShot) { & $script:SmokeShot "14-feed-manager" $script:FeedDlg.Dlg }
            return ""
        } 1500
        & $pump
        if (@($script:Config.NewsSources).Count -ne 1) { throw "cancelling the manager changed the feeds" }
        $script:Config.NewsSources = @()
    }
    # V7.0: contrast of every theme (text 4.5:1, muted text and accent 3:1) against card and background
    Invoke-SmokeStep "Theme contrast" {
        $saved = [string]$script:Config.Theme
        $bad = @()
        $rgb = { param($c) return @([int]$c.R, [int]$c.G, [int]$c.B) }
        foreach ($tn in (Get-ThemeNames)) {
            $script:Config.Theme = $tn
            $pp = Get-ThemeColors
            foreach ($surf in @("Card", "BodyBg", "PanelBg")) {
                $r1 = Get-ContrastRatio -A (& $rgb $pp.Text) -B (& $rgb $pp[$surf])
                if ($r1 -lt 4.5) { $bad += ("{0}: text on {1} = {2:N1}" -f $tn, $surf, $r1) }
                $r2 = Get-ContrastRatio -A (& $rgb $pp.Muted) -B (& $rgb $pp[$surf])
                if ($r2 -lt 3.0) { $bad += ("{0}: muted on {1} = {2:N1}" -f $tn, $surf, $r2) }
                $r3 = Get-ContrastRatio -A (& $rgb $pp.Accent) -B (& $rgb $pp[$surf])
                if ($r3 -lt 3.0) { $bad += ("{0}: accent on {1} = {2:N1}" -f $tn, $surf, $r3) }
            }
        }
        $script:Config.Theme = $saved
        if ($bad.Count -gt 0) { throw ($bad -join "; ") }
    } 5000
    # V7.1: new controls, dialog template, pane divider hit test, GDI objects after repeated dialogs
    Invoke-SmokeStep "V7.1 controls + template" {
        if ('TwSegmentV7' -as [type]) {
            $sg = New-Object TwSegmentV7; $sg.Size = New-Object System.Drawing.Size(200, 26); $sg.Items = [string[]]@("A", "B", "C")
            $script:SmokeSegHit = 0
            $sg.Add_SelectedIndexChanged({ $script:SmokeSegHit++ })
            $sg.SelectedIndex = 2
            if ($sg.SelectedIndex -ne 2 -or $script:SmokeSegHit -ne 1) { throw "segmented control: index $($sg.SelectedIndex), events $($script:SmokeSegHit)" }
            $bm = New-Object System.Drawing.Bitmap 200, 26
            $sg.DrawToBitmap($bm, (New-Object System.Drawing.Rectangle(0, 0, 200, 26))); $bm.Dispose(); $sg.Dispose()
        } else { $script:SmokeNotes.Add("TwSegmentV7 not available (no compiler?)") }
        if ('TwSliderV7' -as [type]) {
            $sl = New-Object TwSliderV7; $sl.Minimum = 30; $sl.Maximum = 100; $sl.Step = 5; $sl.Size = New-Object System.Drawing.Size(150, 24)
            $sl.Value = 500
            if ($sl.Value -ne 100) { throw "slider did not clamp: $($sl.Value)" }
            $bm = New-Object System.Drawing.Bitmap 150, 24
            $sl.DrawToBitmap($bm, (New-Object System.Drawing.Rectangle(0, 0, 150, 24))); $bm.Dispose(); $sl.Dispose()
        }
        $sd = New-StandardDialog -Title "Test" -Subtitle "Untertitel" -W 400 -BodyH 32
        if ($null -eq $sd.Ok -or $null -eq $sd.Err -or $sd.Dlg.AcceptButton -ne $sd.Ok) { throw "dialog template incomplete" }
        $sd.Dlg.Tag.Validate = { param($t) if (-not $t) { "leer" } else { "" } }
        if ((& $sd.Dlg.Tag.Validate "") -ne "leer") { throw "validation hook" }
        $sd.Dlg.Dispose()
        $fakeL = @{ PriceRect = (New-Object System.Drawing.Rectangle(10, 6, 300, 200)); RsiRect = (New-Object System.Drawing.Rectangle(10, 214, 300, 80)); PaneTotal = 288; PaneTop = 6; GapY = 8; OffsetY = 0 }
        if (-not (Test-PaneDividerHit -L $fakeL -Y 209)) { throw "divider hit test (inside the gap)" }
        if (Test-PaneDividerHit -L $fakeL -Y 100) { throw "divider hit test (inside the chart)" }
    } 3000
    Invoke-SmokeStep "Accessibility" {
        Set-AccessibilityDefaults $form -NoTabOrder
        $miss = @(); $small = @()
        $scan = $null
        $scan = {
            param($c)
            foreach ($k in @($c.Controls)) {
                $isInput = ($k -is [System.Windows.Forms.Button] -or $k -is [System.Windows.Forms.TextBox] -or $k -is [System.Windows.Forms.ComboBox] -or $k -is [System.Windows.Forms.NumericUpDown])
                if ($isInput -and $k.Visible -and [string]::IsNullOrEmpty($k.AccessibleName)) { $miss += ("{0}:{1}" -f $k.GetType().Name, $k.Name) }
                if ($k -is [System.Windows.Forms.Button] -and $k.Visible -and ($k.Height -lt (S 20) -or $k.Width -lt (S 20))) { $small += ("{0} {1}x{2}" -f $k.Text, $k.Width, $k.Height) }
                if ($k.Controls.Count -gt 0) { & $scan $k }
            }
        }
        & $scan $form
        $script:SmokeNotes.Add(("Accessibility: {0} inputs without a name, {1} buttons under 20 px" -f $miss.Count, $small.Count))
        if ($small.Count -gt 0) { $script:SmokeNotes.Add("Small buttons: " + (($small | Select-Object -First 8) -join "; ")) }
        if ($miss.Count -gt 0) { $script:SmokeNotes.Add("Unnamed: " + (($miss | Select-Object -First 8) -join "; ")) }
    } 1000
    Invoke-SmokeStep "GDI handles" {
        if (-not ('TwSmokeGdi' -as [type])) { Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class TwSmokeGdi { [DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr h, uint f); }' }
        $hp = [System.Diagnostics.Process]::GetCurrentProcess().Handle
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        $g0 = [TwSmokeGdi]::GetGuiResources($hp, 0)
        for ($i = 0; $i -lt 4; $i++) { Show-SettingsDialog; & $pump }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers(); & $pump
        $g1 = [TwSmokeGdi]::GetGuiResources($hp, 0)
        $script:SmokeNotes.Add("GDI objects: $g0 -> $g1 after 4 settings windows")
        if (($g1 - $g0) -gt 2500) { throw "GDI objects grew from $g0 to $g1" }
    } 900
    # v5.3: settings pages, style findable, search, markers, reset, preview, Ctrl+K, settings file
    Invoke-SmokeStep "Settings pages" {
        $styleBefore = [string]$script:Config.UiStyle
        & $probeRun { Show-SettingsDialog -Page "Display" } {
            $sc = $script:SettingsCtl
            if ($null -eq $sc) { return "window not open" }
            if ($sc.Pages.Count -ne 8) { return "pages: $($sc.Pages.Count)" }
            $wa = [System.Windows.Forms.Screen]::FromControl($sc.Dlg).WorkingArea
            if ($sc.Dlg.Height -gt $wa.Height) { return "window $($sc.Dlg.Height) px is taller than the screen ($($wa.Height) px)" }
            foreach ($q in @("stil", "Style", "Fresh", "Refined")) {
                Show-SettingsPage "Display"
                $sc.Search.Text = $q; [System.Windows.Forms.Application]::DoEvents()
                if ($sc.Cur -ne "Design") { return "search '$q' opened page '$($sc.Cur)'" }
                }
            $sc.Search.Text = ""
            $eS = @($sc.Reg | Where-Object { $_.Key -eq "UiStyle" })[0]
            $sc.Style.SelectedIndex = 0; [System.Windows.Forms.Application]::DoEvents()
            if ($script:UiSpec.Fresh -or $eS.Changed) { return "live preview did not switch to Refined" }
            $sc.Style.SelectedIndex = 1; [System.Windows.Forms.Application]::DoEvents()
            if (-not $script:UiSpec.Fresh) { return "live preview did not switch to Fresh" }
            if (-not $eS.Changed -or -not $eS.Marker.Visible) { return "no 'changed' marker for Fresh" }
            & $script:SmokeShot "10-settings-design-page" $sc.Dlg
            Show-SettingsPage "Design"
            $sc.Reset.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
            if ($sc.Style.SelectedIndex -ne 0 -or $eS.Changed -or $script:UiSpec.Fresh) { return "reset page did not restore the style" }
            foreach ($id in @($sc.PageIds)) { Show-SettingsPage $id; [System.Windows.Forms.Application]::DoEvents() }
            $sc.Search.Text = "push"; [System.Windows.Forms.Application]::DoEvents()
            if ($sc.Cur -ne "Alerts") { return "search 'push' opened page '$($sc.Cur)'" }
            & $script:SmokeShot "11-settings-search" $sc.Dlg
            return ""
        } 2500
        if ([string]$script:Config.UiStyle -ne $styleBefore) { throw "Cancel did not undo the preview ($($script:Config.UiStyle))" }
    } 6000
    Invoke-SmokeStep "SET opens the right page" {
        & $probeRun { [void](Invoke-TerminalCommand "SET ZEBRA") } {
            $sc = $script:SettingsCtl
            if ($null -eq $sc) { return "window not open" }
            if ($sc.Cur -ne "Design") { return "SET ZEBRA opened '$($sc.Cur)'" }
            return ""
        } 1500
    } 3500
    Invoke-SmokeStep "Settings in Ctrl+K" {
        $script:SettingsIndexCache = $null
        $ix = @(Get-SettingsPaletteEntries)
        if ($ix.Count -lt 40) { throw "only $($ix.Count) settings in the index" }
        if (@($ix | Where-Object { $_.Text -eq "SET STIL" }).Count -eq 0) { throw "SET STIL missing" }
        if (@(Get-MenuPaletteEntries).Count -lt 8) { throw "menu entries missing" }
        $sug = @(Get-CommandSuggestions -Text "zebra" -Extra (Get-PaletteExtras) | ForEach-Object { $_.Text })
        if (@($sug | Where-Object { $_ -like "SET ZEBRA*" }).Count -eq 0) { throw "'zebra' finds no setting: $($sug -join ', ')" }
        $m = Invoke-MenuEntry "Stil: Fresh"; & $pump
        if ($m -or -not $script:UiSpec.Fresh) { throw "MENU Stil: Fresh failed ($m)" }
        # (the English step before has translated the tray menu: "Stil" may read "Style")
        $trayRef = @(Get-MenuPaletteEntries | Where-Object { $_.Where -eq "Tray" -and [string]$_.Search -like "* > Refined" })
        if ($trayRef.Count -eq 0) { throw "tray menu has no style entry" }
        $m = Invoke-MenuEntry ([string]$trayRef[0].Search); & $pump
        if ($m -or $script:UiSpec.Fresh) { throw "MENU $($trayRef[0].Search) (tray) failed ($m)" }
    }
    Invoke-SmokeStep "Settings file" {
        $tmp = Join-Path $env:TEMP ("tw-settings-{0}.json" -f $PID)
        $themeBefore = [string]$script:Config.Theme
        if (-not (Export-SettingsFile -Path $tmp)) { throw "export failed" }
        $script:Config.Theme = "Light"
        if (-not (Import-SettingsFile -Path $tmp -NoRestart)) { throw "import failed" }
        if ([string]$script:Config.Theme -ne $themeBefore) { throw "import did not restore the theme ($($script:Config.Theme))" }
        Remove-Item $tmp -ErrorAction SilentlyContinue
        & $pump
    }
    # v5.5 A: notes, HEALTH, diagnostics
    Invoke-SmokeStep "Ticker note" {
        Set-TickerNote -Ticker "NVDA" -Text "  Smoke: KI-These`nzweite Zeile  "
        if ((Get-TickerNote "nvda") -ne "Smoke: KI-These`r`nzweite Zeile") { throw "note not stored: '$(Get-TickerNote NVDA)'" }
        [void](Invoke-TerminalCommand "MSFT NOTE Cloud-Wachstum"); if ((Get-TickerNote "MSFT") -ne "Cloud-Wachstum") { throw "NOTE command did not store" }
        & $probeRun { Show-NoteDialog -Ticker "NVDA" } { if ($null -eq $script:NoteTb -or $script:NoteTb.Text -notlike "Smoke*") { return "note dialog empty" }; "" } 800
        # hover card with the note (painted, then hidden again)
        $script:HoverPending = @{ Sym = "NVDA" }; $script:HoverTimer.Stop(); $script:HoverTimer.Start()
        for ($k = 0; $k -lt 12; $k++) { Start-Sleep -Milliseconds 80; & $pump }
        if ($pnlHover.Visible) { $pnlHover.Refresh(); if ($pnlHover.Height -le (S 172)) { throw "hover card has no room for the note" } }
        Hide-HoverCard
        Set-TickerNote -Ticker "MSFT" -Text ""
        if (Get-TickerNote "MSFT") { throw "empty note not removed" }
    } 2500
    Invoke-SmokeStep "HEALTH and DIAG" {
        [void](Invoke-TerminalCommand "HEALTH")
        if (-not $script:LastHealthText -or $script:LastHealthText -notmatch "Datendateien") { throw "health report empty" }
        $zp = Join-Path $env:TEMP ("tw-diag-{0}.zip" -f $PID)
        if (-not (Export-Diagnostics -Path $zp) -or -not (Test-Path $zp)) { throw "diagnostics ZIP missing" }
        Remove-Item $zp -ErrorAction SilentlyContinue
    }
    # v5.5 B: privacy in the Analyse window, export, image, dialog places
    Invoke-SmokeStep "Analyse privacy + export" {
        Set-PrivacyMode $true
        $script:SmokeExpDir = Join-Path $env:TEMP ("tw-exp-{0}" -f $PID)
        New-Item -ItemType Directory -Path $script:SmokeExpDir -Force | Out-Null
        & $probeRun { Show-AnalysisDialog -Page "Ret" } {
            $ac = $script:AnaCtl
            if ($null -eq $ac) { return "window not open" }
            foreach ($gr in @(Get-ChildGrids $ac.Dlg)) {
                foreach ($col in $gr.Columns) {
                    if (-not (Test-AmountColumn ([string]$col.HeaderText))) { continue }
                    foreach ($row in $gr.Rows) {
                        $fv = [string]$row.Cells[$col.Index].FormattedValue
                        if ($fv -match '\d' -and -not $fv.Contains("%")) { return "privacy: '$($col.HeaderText)' shows '$fv'" }
                    }
                }
            }
            $pg = $ac.Pages[[string]$ac.Page]
            $h = Export-GridsReport -Grids (Get-ChildGrids $pg) -Title "Smoke" -Format "Html" -Path (Join-Path $script:SmokeExpDir "a.html")
            $c = Export-GridsReport -Grids (Get-ChildGrids $pg) -Title "Smoke" -Format "Csv" -Path (Join-Path $script:SmokeExpDir "a.csv")
            if (@(Get-ChildGrids $pg | Where-Object { $_.Rows.Count -gt 0 }).Count -gt 0 -and (-not $h -or -not $c)) { return "page export failed" }
            & $script:SmokeShot "12-analyse-privacy" $ac.Dlg
            return ""
        } 9000
        Set-PrivacyMode $false
    } 11000
    Invoke-SmokeStep "Chart image" {
        $ip = Join-Path $script:SmokeExpDir "chart.png"
        if (-not (Export-ChartImage -Mode "Save" -Path $ip) -or (Get-Item $ip).Length -lt 1000) { throw "chart image missing or empty" }
        $wp = Join-Path $script:SmokeExpDir "win.png"
        if (-not (Export-ControlImage -Ctl $form -Mode "Save" -Path $wp)) { throw "window image missing" }
        Remove-Item $script:SmokeExpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    # v5.5 C: chart - percent axis, daily cache + S/R + signal column, Ctrl-drag zoom, zone / text, fullscreen toolbar
    Invoke-SmokeStep "Chart percent axis" {
        Set-ActiveTab -TabName "Chart"; Set-ChartOption -Key "PctAxis" -On $true; & $pump; $pnlChartCanvas.Refresh()
        & $script:SmokeShot "13-chart-percent-axis"
        Set-ChartOption -Key "PctAxis" -On $false; & $pump
    }
    Invoke-SmokeStep "Daily cache, S/R, signal column" {
        $sy0 = ([string]$script:Config.ActiveTicker).ToUpper()
        Request-DailyBars -Symbols @($sy0, "MSFT")
        for ($k = 0; $k -lt 80 -and $script:DailyPending.Count -gt 0; $k++) { Start-Sleep -Milliseconds 200; & $pump }
        if ($null -eq $script:DailyCache[$sy0]) { $script:SmokeNotes.Add("daily cache: no bars for $sy0 (offline?)") }
        else {
            if (-not (Test-Path $script:DailyCachePath)) { throw "daily_cache.json not written" }
            Set-ChartOption -Key "ShowSR" -On $true; & $pump; $pnlChartCanvas.Refresh()
            & $script:SmokeShot "14-chart-support-resistance"
            Set-ChartOption -Key "ShowSR" -On $false
            $dgvWatchlist.Columns["Signal"].Visible = $true
            Set-ActiveTab -TabName "Watchlist"; Refresh-WatchlistAndAlerts; & $pump
            $rw = @($dgvWatchlist.Rows | Where-Object { ([string]$_.Cells[0].Value).Trim().ToUpper() -eq $sy0 })
            if ($rw.Count -gt 0 -and [string]$rw[0].Cells["Signal"].Value -eq "-") { throw "signal column empty for $sy0" }
            $dgvWatchlist.Columns["Signal"].Visible = $false
            Set-ActiveTab -TabName "Chart"
        }
    } 20000
    Invoke-SmokeStep "Ctrl-drag zoom" {
        Set-ActiveTab -TabName "Chart"; Reset-ChartZoom; $pnlChartCanvas.Refresh(); & $pump
        $nAll = @($script:ActiveSeries).Count
        if ($nAll -ge 40) {
            $script:ZoomDrag = @{ A = 5; B = 30; Key = $script:ActiveSeriesKey }
            & $script:ChartMouseUpHandler $pnlChartCanvas (New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Left, 1, 10, 10, 0))
            if ([int]$script:ViewCount -ne 26 -or [int]$script:ViewOffset -ne ($nAll - 31)) { throw "zoom window $($script:ViewCount)/$($script:ViewOffset)" }
            $pnlChartCanvas.Refresh()
            Reset-ChartZoom
        }
    }
    Invoke-SmokeStep "Zone and text drawings" {
        $ser = @($script:ActiveSeries)
        if ($ser.Count -ge 20) {
            $a = [PSCustomObject]@{ T = [long]$ser[3].Ts; P = [double]$ser[3].Close }
            $b = [PSCustomObject]@{ T = [long]$ser[15].Ts; P = [double]$ser[15].Close * 1.02 }
            Add-Drawing -Kind "R" -A $a -B $b
            Add-Drawing -Kind "N" -A $b -Text "Smoke-Notiz"
            Set-DrawMode "R"; Set-DrawMode "N"; Set-DrawMode ""
            $pnlChartCanvas.Refresh(); & $pump
            & $script:SmokeShot "15-chart-zone-text"
            $dl = $script:Drawings[([string]$script:Config.ActiveTicker).ToUpper()]
            if (@($dl | Where-Object { $_.Kind -eq "N" -and $_.Text -eq "Smoke-Notiz" }).Count -ne 1) { throw "text note not stored" }
            Read-Drawings
            if (@($script:Drawings[([string]$script:Config.ActiveTicker).ToUpper()] | Where-Object { $_.Kind -eq "R" }).Count -lt 1) { throw "zone not saved" }
            Remove-Drawing -All
        }
    }
    Invoke-SmokeStep "Fullscreen toolbar" {
        Toggle-ChartFullscreen; & $pump
        if ($null -eq $script:FsForm -or $script:FsForm.Controls.Find("fsToolbar", $false).Count -ne 1) { throw "no toolbar in fullscreen" }
        & $script:SmokeShot "16-fullscreen-toolbar" $script:FsForm
        Close-ChartFullscreen; & $pump
    }
    # v5.5 D: sector / currency scenario, dividend calendar, savings plan dynamics
    Invoke-SmokeStep "Scenario by sector / currency" {
        & $probeRun { Show-AnalysisDialog -Page "Contrib" } {
            $ac = $script:AnaCtl
            if ($null -eq $ac -or $null -eq $ac.Model) { return "model not loaded" }
            Update-ScenarioChoices
            if ($ac.SKind.Items.Count -lt 2) { return "no sector / currency to choose ($($ac.SKind.Items.Count))" }
            $ac.SKind.SelectedIndex = $ac.SKind.Items.Count - 1
            Update-AnalysisScenario
            if ([string]$ac.SGrid.Columns["Beta"].HeaderText -eq "Beta") { return "group scenario not applied" }
            if (-not $ac.SRes.Text) { return "no scenario result" }
            return ""
        } 9000
    } 11000
    Invoke-SmokeStep "Dividend calendar" {
        & $probeRun { Show-AnalysisDialog -Page "Income" } {
            $ac = $script:AnaCtl
            if ($null -eq $ac) { return "window not open" }
            if ($ac.IGrid.Rows.Count -lt 1) { return "no year in the dividend calendar" }
            & $script:SmokeShot "17-analyse-income" $ac.Dlg
            return ""
        } 3000
    } 5000
    Invoke-SmokeStep "Savings plan dynamics" {
        $script:SavingsPlans.Add([PSCustomObject]@{ Id = "smk"; Ticker = "MSFT"; Amount = 100.0; Fee = 0.0; Currency = "USD"; Day = 1; Start = "2099-01-01"; LastBooked = ""; Active = $true; Increase = 5.0; Pause = "Jul, Aug" })
        & $probeRun { Show-SavingsPlansDialog } {
            $g = $script:PlanCtl.Grid
            $r = @($g.Rows | Where-Object { [string]$_.Tag -eq "smk" })[0]
            if ($null -eq $r -or [string]$r.Cells["Pause"].Value -ne "Jul, Aug") { return "pause months not shown" }
            & $script:PlanCtl.Save
            return ""
        } 800
        Read-SavingsPlans
        $pl = @($script:SavingsPlans | Where-Object { $_.Id -eq "smk" })[0]
        if ($null -eq $pl -or [double]$pl.Increase -ne 5 -or [string]$pl.Pause -ne "Jul, Aug") { throw "dynamics / pause not saved" }
        $script:SavingsPlans.Remove($pl) | Out-Null; Save-SavingsPlans
    } 2500

    # v5.5 E: Fresh tabs, loading skeleton, health numbers
    Invoke-SmokeStep "Fresh tabs + skeleton" {
        [void](Invoke-TerminalCommand "STYLE FRESH"); & $pump
        $script:Config.Watchlist = @($script:Config.Watchlist) + @("SMOKEX.XX")
        Set-ActiveTab -TabName "Watchlist"; Refresh-WatchlistAndAlerts; & $pump; $dgvWatchlist.Refresh()
        $sk = @($dgvWatchlist.Rows | Where-Object { [string]$_.Tag -eq "skel" })
        if ($sk.Count -lt 1) { throw "no skeleton row for a ticker without a quote" }
        & $script:SmokeShot "18-fresh-tabs-skeleton"
        $script:Config.Watchlist = @($script:Config.Watchlist | Where-Object { $_ -ne "SMOKEX.XX" })
        Refresh-WatchlistAndAlerts
        [void](Invoke-TerminalCommand "STYLE REFINED"); Set-ActiveTab -TabName "Chart"; & $pump
        if (@(Get-HealthChecks | Where-Object { $_.Name -in @("Startzeit", "Speicher", "Abfragen") }).Count -lt 2) { throw "health has no start / memory / load lines" }
    }
    # v5.7: weekly signals, peer group, valuation history, signal alerts, contrast theme
    Invoke-SmokeStep "TA weekly + peers + history" {
        [void](Invoke-TerminalCommand "NVDA PEER MSFT AAPL")
        if ((Get-PeerGroup "NVDA") -join "," -ne "MSFT,AAPL") { throw "peer group not saved: $((Get-PeerGroup NVDA) -join ',')" }
        if (-not [bool](Get-FundPeers -Sym "NVDA").Own) { throw "own peer group not used" }
        $h = @(); foreach ($i in 1..25) { $h = Add-FundSnapshot -History $h -Fund ([PSCustomObject]@{ TrailingPE = 30.0 + $i }) -Day ((Get-Date).AddDays(-30 + $i).ToString("yyyy-MM-dd")) }
        $script:FundHist["NVDA"] = $h
        & $probeRun { Show-TickerAnalysis "NVDA" } {
            $c = $script:TaCtl
            if ($null -eq $c) { return "window not open" }
            if ($c.TGrid.Columns.Count -ne 4) { return "TA grid has $($c.TGrid.Columns.Count) columns" }
            if ($null -ne $c.Bars -and ($null -eq $c.WSig -or $c.TSum.Text -notmatch "/")) { return "no weekly signals: '$($c.TSum.Text)'" }
            if ($null -ne $script:Events["NVDA"] -and $null -ne $script:Events["NVDA"].Fund -and @($c.FGrid.Rows | Where-Object { [string]$_.Cells[0].Value -like "*eigene Historie*" }).Count -ne 1) { return "valuation history rows missing" }
            & $script:SmokeShot "19-ta-weekly-history" $c.Dlg
            return ""
        } 8000
        [void](Invoke-TerminalCommand "NVDA PEER -")
        if (@(Get-PeerGroup "NVDA").Count -ne 0) { throw "PEER - did not clear" }
    } 10000
    Invoke-SmokeStep "Signal change alert" {
        $o = [PSCustomObject]@{ Day = "2026-01-01"; Score = 0; Close = @(1..30 | ForEach-Object { 100.0 }); Support = 95.0; Resistance = 105.0 }
        $n0 = [PSCustomObject]@{ Day = "2026-01-02"; Score = 5; Close = @(1..30 | ForEach-Object { 106.0 }) }
        $script:LastSignalAlert = ""
        $psym = @($script:Portfolio.Keys)[0]
        Send-SignalChangeAlerts -Sym ([string]$psym).ToUpper() -Old $o -New $n0
        if ($script:LastSignalAlert -notmatch "Widerstand") { throw "no signal alert for a depot ticker ('$($script:LastSignalAlert)')" }
        $script:Config.SignalAlerts = "Aus"; $script:LastSignalAlert = ""
        Send-SignalChangeAlerts -Sym ([string]$psym).ToUpper() -Old $o -New $n0
        if ($script:LastSignalAlert) { throw "alert although switched off" }
        $script:Config.SignalAlerts = "Depot"
    }
    Invoke-SmokeStep "Contrast theme + 50/200 markers" {
        [void](Invoke-TerminalCommand "THEME CONTRAST"); Set-ActiveTab -TabName "Chart"; [void](Invoke-TerminalCommand "TF 1Y")
        Set-ChartOption -Key "ShowSR" -On $true; & $pump; $pnlChartCanvas.Refresh()
        & $script:SmokeShot "20-contrast-theme-markers"
        Set-ChartOption -Key "ShowSR" -On $false
        $script:Config.Theme = "Dark"; Apply-ThemeToAllControls; & $pump
        if (@(Get-HealthChecks | Where-Object { $_.Name -eq "Abfragen" -and $_.Detail -match "Yahoo" }).Count -lt 1) { throw "health shows no requests per provider" }
    }
    # V6: providers without keys, sample answers in the ticker analysis, budget, log redaction
    Invoke-SmokeStep "V6 providers" {
        Write-WidgetLog "smoke https://finnhub.io/api/v1/quote?symbol=AAPL&token=SECRET123"
        if ((Get-Content -Path $script:LogPath -Tail 5) -join " " -match "SECRET123") { throw "API key written to the log" }
        Test-Providers -Quiet
        $script:Config.FinnhubKeyEnc = Protect-Secret "smoke-key"
        if ((Get-ProviderKey "Finnhub") -ne "smoke-key") { throw "key round trip failed" }
        $day = (Get-Date).ToString("yyyy-MM-dd")
        $script:ProvCache["NVDA|Metric"] = [PSCustomObject]@{ Day = $day; Data = ('{"series":{"annual":{"pe":[{"period":"2024-12-31","v":50.1},{"period":"2025-12-31","v":45.2}],"netMargin":[{"period":"2025-12-31","v":48.8}]},"quarterly":{"pe":[' + ((1..10 | ForEach-Object { '{"period":"' + (Get-Date).AddMonths(-3 * $_).ToString("yyyy-MM-dd") + '","v":' + (30 + $_) + '}' }) -join ",") + ']}}}' | ConvertFrom-Json) }
        $script:ProvCache["NVDA|Earnings"] = [PSCustomObject]@{ Day = $day; Data = ('[{"actual":0.89,"estimate":0.85,"period":"2026-07-31","surprisePercent":4.7}]' | ConvertFrom-Json) }
        $script:ProvCache["NVDA|Recommendation"] = [PSCustomObject]@{ Day = $day; Data = ('[{"buy":40,"hold":5,"period":"2026-11-01","sell":1,"strongBuy":20,"strongSell":0},{"buy":38,"hold":6,"period":"2026-08-01","sell":1,"strongBuy":18,"strongSell":0}]' | ConvertFrom-Json) }
        $script:Config.ProviderCaps = [PSCustomObject]@{ "Finnhub|Metric" = $false; "Finnhub|Earnings" = $false; "Finnhub|Calendar" = $false; "Finnhub|Recommendation" = $false; "Finnhub|PriceTarget" = $false; "Finnhub|Daily" = $false }
        & $probeRun { Show-TickerAnalysis "NVDA" } {
            $c = $script:TaCtl
            if ($null -eq $c) { return "window not open" }
            if ($null -ne $script:Events["NVDA"] -and $null -ne $script:Events["NVDA"].Fund) {
                foreach ($h in @("Kennzahlen über die Jahre", "Quartalszahlen: Gewinn je Aktie", "Analysten (Trend)")) {
                    if (@($c.FGrid.Rows | Where-Object { [string]$_.Cells[0].Value -eq $h }).Count -ne 1) { return "section '$h' missing" }
                }
                & $script:SmokeShot "21-ta-finnhub" $c.Dlg
            }
            return ""
        } 8000
        $script:Config.FinnhubKeyEnc = ""; $script:Config.ProviderCaps = [PSCustomObject]@{}
        foreach ($k in @("Metric", "Earnings", "Recommendation")) { [void]$script:ProvCache.Remove("NVDA|$k") }
        if (-not (Test-ProviderCap "Finnhub" "Metric")) { throw "untested capability should count as usable" }
        [void](Select-ProviderUrls @(1..10 | ForEach-Object { [PSCustomObject]@{ Provider = "TwelveData"; Url = "https://api.twelvedata.com/x" } }))
        if (@(Get-HealthChecks | Where-Object { $_.Name -eq "Finnhub" }).Count -ne 1) { throw "health has no provider line" }
    } 10000
    Invoke-SmokeStep "Dialog places" {
        Show-CashDialog
        if ($null -eq $script:Config.DialogPlacement.PSObject.Properties["Cash"]) { throw "cash window place not saved" }
    } 1500

    Invoke-SmokeStep "Design analysis" { & $probeRun { Show-AnalysisDialog -Page "Bench" } { & $script:SmokeShot "09-fresh-analysis-bench" ([System.Windows.Forms.Form]::ActiveForm); "" } 9000 } 11000
    [void](Invoke-TerminalCommand "STYLE REFINED")
    Invoke-SmokeStep "V8.0 price axis" {
        Apply-Layout "Standard"; Set-ActiveTab -TabName "Chart"; & $pump
        for ($i = 0; $i -lt 40 -and $null -eq (Get-CanvasLayout -Canvas $pnlChartCanvas); $i++) { Start-Sleep -Milliseconds 100; & $pump }
        Reset-ChartZoom; $pnlChartCanvas.Refresh(); & $pump
        $L = Get-CanvasLayout -Canvas $pnlChartCanvas
        if ($null -eq $L) { $script:SmokeNotes.Add("price axis: no chart data, skipped"); return }
        $span0 = [double]$L.SpanP
        $x = [int]$L.PriceRect.Right + 12; $y = [int]$L.PriceRect.Top + [int]$L.OffsetY + 40
        if (-not (Test-PriceAxisHit -L $L -X $x -Y $y)) { throw "axis not recognised" }
        $mk = { param($X, $Y, $D) New-Object System.Windows.Forms.MouseEventArgs([System.Windows.Forms.MouseButtons]::Left, 1, $X, $Y, $D) }
        & $script:ChartWheelHandler $pnlChartCanvas (& $mk $x $y -120); $pnlChartCanvas.Refresh(); & $pump
        $span1 = [double](Get-CanvasLayout -Canvas $pnlChartCanvas).SpanP
        if ($span1 -le $span0) { throw "wheel did not widen the range: $span0 -> $span1" }
        & $script:ChartMouseDownHandler $pnlChartCanvas (& $mk $x $y 0)
        Start-Sleep -Milliseconds 60
        & $script:ChartMouseMoveHandler $pnlChartCanvas (& $mk $x ($y + 60) 0)
        & $script:ChartMouseUpHandler $pnlChartCanvas (& $mk $x ($y + 60) 0)
        $pnlChartCanvas.Refresh(); & $pump
        if ($script:PriceShift -le 0) { throw "dragging down did not move the range up: $($script:PriceShift)" }
        if ($null -ne $script:PriceDrag) { throw "drag still active" }
        # far out of view: the chart must still draw
        Set-PriceScale -Scale 0.1 -Shift 4; $pnlChartCanvas.Refresh(); & $pump
        Reset-ChartZoom; $pnlChartCanvas.Refresh(); & $pump
        if (Test-PriceScaled) { throw "reset left the axis scaled" }
    }
    Invoke-SmokeStep "V8.0 colour rules, columns, theme" {
        $old = @{ Rules = $script:Config.ColorRules; Themes = $script:Config.CustomThemes; Theme = [string]$script:Config.Theme }
        try {
            $rules = @(Get-DefaultColorRules); $rules[0].Value = 0; $rules[0].On = $true
            $script:Config.ColorRules = $rules
            foreach ($c in @("OwnTgt", "AlertDist", "Note", "DayBase")) { $dgvWatchlist.Columns[$c].Visible = $true }
            $s0 = ([string]$script:Config.Watchlist[0]).ToUpper()
            Set-OwnTarget -Sym $s0 -Price 123.45 -Currency "USD"
            Set-ActiveTab -TabName "Watchlist"; Refresh-WatchlistAndAlerts; & $pump
            if ($null -ne $script:QuoteStore[$s0]) {
                $row = @($dgvWatchlist.Rows | Where-Object { [string]$_.Cells[0].Value -eq $s0 })[0]
                if ([string]$row.Cells["OwnTgt"].Value -notlike "*123*") { throw "own target missing: $($row.Cells['OwnTgt'].Value)" }
                if ($row.DefaultCellStyle.BackColor.IsEmpty) { throw "colour rule not applied" }
            }
            Save-ColumnSet "Smoke"
            foreach ($c in @("OwnTgt", "AlertDist", "Note", "DayBase")) { $dgvWatchlist.Columns[$c].Visible = $false }
            if (-not (Use-ColumnSet "Smoke")) { throw "column set not found" }
            if (-not $dgvWatchlist.Columns["OwnTgt"].Visible) { throw "column set did not show the column" }
            foreach ($c in @("OwnTgt", "AlertDist", "Note", "DayBase")) { $dgvWatchlist.Columns[$c].Visible = $false }
            $script:Config.ColumnSets = @(); $script:ActiveColumnSet = ""
            Set-OwnTarget -Sym $s0 -Price 0 -Currency ""
            Save-CustomTheme (ConvertFrom-ThemeData ([PSCustomObject]@{ Name = "Smoke Theme"; Base = "Light"; Colors = [PSCustomObject]@{ Card = "#123456" } }))
            Set-ThemeByName "Smoke Theme"; & $pump
            if ($script:Pal.Card.R -ne 0x12 -or $script:Pal.Card.B -ne 0x56) { throw "own theme colour not used: $($script:Pal.Card)" }
            foreach ($dk in @("DwmCap", "DwmBdr", "DwmDark")) { if ($script:Pal[$dk] -isnot [int]) { throw "title bar value $dk is not a number: $($script:Pal[$dk])" } }
        } finally {
            $script:Config.ColorRules = $old.Rules; $script:Config.CustomThemes = $old.Themes
            Set-ThemeByName $old.Theme; Set-ActiveTab -TabName "Chart"
        }
    }
    Invoke-SmokeStep "V8.0 shortcuts, favourites, profiles" {
        $script:Config.KeyMap = [PSCustomObject]@{ privacy = "Strg+Shift+P" }
        $script:Config.Favorites = @("calendar", "privacy")
        Update-FavoritesMenu
        if ($script:MbFavorites.DropDownItems.Count -ne 2) { throw "favourites: $($script:MbFavorites.DropDownItems.Count)" }
        $p0 = [bool]$script:Config.PrivacyMode
        $ke = New-Object System.Windows.Forms.KeyEventArgs(([System.Windows.Forms.Keys]::P -bor [System.Windows.Forms.Keys]::Control -bor [System.Windows.Forms.Keys]::Shift))
        if (-not (Invoke-UserShortcut -Sender $form -E $ke)) { throw "shortcut not recognised" }
        if ([bool]$script:Config.PrivacyMode -eq $p0) { throw "shortcut did nothing" }
        Set-PrivacyMode $p0
        $script:Config.KeyMap = $null; $script:Config.Favorites = @(); Update-FavoritesMenu
        $th = [string]$script:Config.Theme
        Save-WidgetProfile "Smoke A"
        $script:Config.Theme = "OLED"; Apply-ThemeToAllControls
        if (-not (Use-WidgetProfile "Smoke A")) { throw "profile not found" }
        & $pump
        if ([string]$script:Config.Theme -ne $th) { throw "profile did not restore the theme: $($script:Config.Theme)" }
        Update-ProfileMenu; Update-ThemeMenu; Update-ColumnSetMenu
        $script:Config.UserProfiles = @(); $script:Config.ActiveProfile = ""
    }
    foreach ($v8 in @(@("colour rules", { Show-ColorRulesDialog }), @("theme editor", { Show-ThemeEditor }), @("keys", { Show-KeysFavoritesDialog }), @("tiles", { Show-KpiTilesDialog }),
                      @("combined alert", { Show-ComboAlertDialog }), @("templates", { Show-AlertTemplatesDialog }), @("notices", { Show-NoticeSettingsDialog }),
                      @("summary", { Show-SummaryDialog }), @("summary week", { Show-SummaryDialog -Period "Week" }), @("goals", { Show-GoalsCostsDialog }), @("own target", { Show-OwnTargetDialog "NVDA" }), @("calendar export button", { Show-CalendarDialog }))) {
        Invoke-SmokeStep ("V8.0 window: " + $v8[0]) $v8[1]
    }
    Invoke-SmokeStep "V8.0 combined alert + template" {
        $n0 = $script:Alerts.Count
        [void](Add-WidgetAlert -Ticker "AAPL" -Condition ">=" -Target 999999 -Currency "USD" -Condition2 "Volumen x" -Target2 2 -Currency2 "VOL" -NoConfirm)
        $a = $script:Alerts[$script:Alerts.Count - 1]
        if ((Format-AlertLine -Alert $a) -notlike "* & *") { throw "second condition not shown: $(Format-AlertLine -Alert $a)" }
        if ((Get-AlertState -Alert $a).Met) { throw "combined alert met although the price condition is not" }
        $added = Add-TemplateAlerts -Template ([PSCustomObject]@{ Name = "Smoke"; Condition = "RSI >="; Value = 99.0; Condition2 = ""; Value2 = 0.0 }) -Symbols @("AAPL", "MSFT")
        if ($added -ne 2) { throw "template added $added alerts" }
        Refresh-WatchlistAndAlerts; & $pump
        while ($script:Alerts.Count -gt $n0) { $script:Alerts.RemoveAt($script:Alerts.Count - 1) }
        Save-Alerts; Refresh-WatchlistAndAlerts
    }
    Invoke-SmokeStep "V8.0 summary rows, CSV, calendar file, goals" {
        foreach ($per in @("Day", "Week")) { if (@(Get-SummaryRows -Period $per).Count -lt 3) { throw "summary $per too short" } }
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("tw-v8-{0}.csv" -f [Guid]::NewGuid().ToString("N"))
        try {
            Export-WatchlistCsv -Path $tmp
            $r = ConvertFrom-WatchlistCsv ([System.IO.File]::ReadAllText($tmp))
            if (@($r.Rows).Count -ne @($script:Config.Watchlist).Count) { throw "CSV rows $(@($r.Rows).Count) / watchlist $(@($script:Config.Watchlist).Count)" }
            $wl = @($script:Config.Watchlist); $wg = $script:Config.WatchGroups
            $n = Import-WatchlistRows -Rows @([PSCustomObject]@{ Ticker = "SMOKE.XX"; Groups = @("G1", "G2", "G3"); Target = 0; Currency = ""; Note = "" })
            if ($n -ne 1) { throw "import added $n" }
            if (@($script:Config.WatchGroups | Where-Object { [string]$_.Name -in @("G1", "G2", "G3") }).Count -ne 3) { throw "groups merged: $(@($script:Config.WatchGroups | ForEach-Object { $_.Name }) -join ',')" }
            $script:Config.Watchlist = $wl; $script:Config.WatchGroups = $wg; Save-Config
        } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
        $ev = $script:Events["NVDA"]
        $script:Events["NVDA"] = New-EventEntry; $script:Events["NVDA"].EarningsDate = (Get-Date).AddDays(5).ToString("yyyy-MM-dd")
        $ics = Join-Path ([System.IO.Path]::GetTempPath()) "tw-v8.ics"
        try { if ((Export-CalendarIcs -Symbols @("NVDA") -Path $ics) -ne 1) { throw "calendar export wrote nothing" } }
        finally { Remove-Item $ics -ErrorAction SilentlyContinue; if ($null -ne $ev) { $script:Events["NVDA"] = $ev } else { $script:Events.Remove("NVDA") } }
        [void](Get-FeeRows)
        [void](Get-DividendForecast -Base ([string]$script:Config.Currency))
    }
    Invoke-SmokeStep "V8.0 English" {
        $lg = [string]$script:Config.Language
        $script:Config.Language = "EN"
        try { Show-GoalsCostsDialog } finally { $script:Config.Language = $lg }
    }
    Invoke-SmokeStep "Final refresh" { Update-AllUiViews; & $pump }

    $rep = [PSCustomObject]@{
        PowerShell = $PSVersionTable.PSVersion.ToString(); Version = $script:AppVersion
        Steps = $script:SmokeSteps.ToArray(); Failures = $script:SmokeFailures.ToArray(); Notes = $script:SmokeNotes.ToArray()
    }
    try { [IO.File]::WriteAllText([string]$env:TW_SMOKE_TEST, ($rep | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8) } catch { }
    $script:SmokeExit = $script:SmokeFailures.Count
    $trayIcon.Visible = $false
    $form.Close()
}

$script:SmokeExit = 99
if ($script:SmokeMode) {
    $script:SmokeStarter = New-Object System.Windows.Forms.Timer
    $script:SmokeStarter.Interval = 3000
    $script:SmokeStarter.Add_Tick({
        $script:SmokeStarter.Stop()
        try { Invoke-SmokeTest } catch {
            $script:SmokeFailures.Add("Smoke runner: $($_.Exception.Message) @ line $($_.InvocationInfo.ScriptLineNumber)")
            try { [IO.File]::WriteAllText([string]$env:TW_SMOKE_TEST, (@{ Failures = $script:SmokeFailures.ToArray(); Steps = $script:SmokeSteps.ToArray() } | ConvertTo-Json -Depth 5)) } catch { }
            $script:SmokeExit = 98
            $form.Close()
        }
    })
    $form.Add_Shown({ $script:SmokeStarter.Start() })
}

# v4.7: English mode for the main window and its menus
try { Apply-Language $form; Apply-Language $trayMenu; Apply-Language $chartContextMenu } catch { Write-WidgetLog "Language: $($_.Exception.Message)" "WARN" }

Write-WidgetLog "Starting message loop"
try {
    [void][System.Windows.Forms.Application]::Run($form)
} catch {
    Write-WidgetLog "Fatal: $($_.Exception.Message)" "ERROR"
} finally {
    Flush-ErrorsToLog
    try { $trayIcon.Dispose() } catch { }
    try { $trayMenu.Dispose() } catch { }
    try { $chartContextMenu.Dispose() } catch { }
    try { $toolTip.Dispose() } catch { }
    if ($script:TrayIconHandle -ne [IntPtr]::Zero) { try { [void][Win32WidgetHelperV26]::DestroyIcon($script:TrayIconHandle) } catch { } }
    foreach ($val in $script:GdiCache.Values) {
        if ($null -ne $val -and $val -is [System.IDisposable]) { try { $val.Dispose() } catch { } }
    }
    foreach ($k in @($script:ChartBmpCache.Keys)) { Remove-ChartBitmap -Key $k }
    if ($null -ne $script:TapeBitmap) { try { $script:TapeBitmap.Dispose() } catch { } }
    foreach ($f in @($fontTicker, $fontPrice, $fontUi, $fontUiBold, $fontMono, $fontAxis, $fontBadge)) {
        try { $f.Dispose() } catch { }
    }
    if ($null -ne $script:HttpClient) { try { $script:HttpClient.Dispose() } catch { } }
    if ($null -ne $script:AppMutex) {
        try { $script:AppMutex.ReleaseMutex() } catch { }
        $script:AppMutex.Dispose()
    }
}
