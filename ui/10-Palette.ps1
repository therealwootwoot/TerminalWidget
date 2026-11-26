# TerminalWidget UI part 10 (Palette) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

function Get-PaletteExtras {
    return @(@(Get-SettingsPaletteEntries) + @(Get-MenuPaletteEntries))
}

function Invoke-MenuEntry {
    param([string]$Name)
    $q = ([string]$Name).Trim()
    if (-not $q) { return "MENU <Name> - z. B. MENU DURCHKLICKEN" }
    $all = @(Get-MenuPaletteEntries)
    $hit = @($all | Where-Object { (ConvertTo-SearchKey ([string]$_.Text).Substring(5)) -eq (ConvertTo-SearchKey $q) })
    if ($hit.Count -eq 0) { $hit = @($all | Where-Object { Test-SettingMatch -Text ([string]$_.Search) -Query $q }) }
    if ($hit.Count -eq 0) { return "Kein Menüeintrag gefunden: $q" }
    $it = $hit[0].Item
    if (-not $it.Enabled) { return "Menüeintrag gerade nicht verfügbar: $q" }
    if ($hit[0].Where -eq "Layout") { Invoke-LayoutMenuTag ([string]$it.Tag) }
    else { $it.PerformClick() }
    return ""
}

function Show-CommandPalette {
    param([string]$Initial = "")
    if ($null -ne $script:PalCtl) { return }
    $p = $script:Pal
    $W = S 640
    $f = New-Object System.Windows.Forms.Form
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $f.ShowInTaskbar = $false
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $f.TopMost = $true
    $f.KeyPreview = $true
    $f.BackColor = $p.Accent
    $f.Padding = New-Object System.Windows.Forms.Padding(1)
    $f.Add_HandleCreated({ param($sender, $e) Set-WindowChrome -Win $sender -Kind "Strip" })
    $f.ClientSize = New-Object System.Drawing.Size($W, (S 352))
    $inner = New-Object System.Windows.Forms.Panel
    $inner.Dock = [System.Windows.Forms.DockStyle]::Fill
    $inner.BackColor = $p.Card
    $f.Controls.Add($inner)
    $lp = New-Object System.Windows.Forms.Label
    $lp.SetBounds((S 10), (S 10), (S 22), (S 28)); $lp.Text = ">"; $lp.ForeColor = $p.Accent
    $lp.Font = New-Object System.Drawing.Font($script:MonoFamily, 14, [System.Drawing.FontStyle]::Bold)
    $inner.Controls.Add($lp)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.SetBounds((S 34), (S 10), ($W - (S 46)), (S 28))
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $tb.BackColor = $p.Card; $tb.ForeColor = $p.Text
    $tb.Font = New-Object System.Drawing.Font($script:MonoFamily, 14)
    $tb.CharacterCasing = [System.Windows.Forms.CharacterCasing]::Upper
    $inner.Controls.Add($tb)
    $sep = New-Object System.Windows.Forms.Label
    $sep.SetBounds((S 10), (S 42), ($W - (S 22)), 1); $sep.BackColor = $p.Border
    $inner.Controls.Add($sep)
    $lb = New-Object System.Windows.Forms.ListBox
    $lb.SetBounds((S 6), (S 48), ($W - (S 14)), (S 268))
    $lb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $lb.BackColor = $p.Card; $lb.ForeColor = $p.Text
    $lb.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $lb.ItemHeight = S 22
    $lb.Font = $fontMono
    $lb.IntegralHeight = $false
    $inner.Controls.Add($lb)
    $err = New-Object System.Windows.Forms.Label
    $err.SetBounds((S 10), (S 322), ($W - (S 22)), (S 22))
    $err.ForeColor = $colRed
    $err.AutoEllipsis = $true
    $inner.Controls.Add($err)
    $hint = "Enter = ausführen  Tab = übernehmen  Pfeile = Auswahl  Esc = schließen"
    $script:PalCtl = @{ Form = $f; Text = $tb; List = $lb; Err = $err; Items = @(); Run = ""; Hint = $hint }
    $lb.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0) { return }
        $pc = $script:PalCtl
        $it = $pc.Items[$e.Index]
        $sel = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
        $bg = if ($sel) { $script:Pal.Accent } else { $script:Pal.Card }
        $fg = if ($sel) { $script:Pal.HeaderBg } else { $script:Pal.Text }
        $mu = if ($sel) { $script:Pal.HeaderBg } else { $script:Pal.Muted }
        $b = New-Object System.Drawing.SolidBrush($bg)
        $e.Graphics.FillRectangle($b, $e.Bounds)
        $b.Dispose()
        $half = [int]($e.Bounds.Width * 0.36)
        $r1 = New-Object System.Drawing.Rectangle(($e.Bounds.X + (S 6)), $e.Bounds.Y, $half, $e.Bounds.Height)
        $r2 = New-Object System.Drawing.Rectangle(($e.Bounds.X + $half + (S 10)), $e.Bounds.Y, ($e.Bounds.Width - $half - (S 16)), $e.Bounds.Height)
        $fl = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$it.Text, $fontMono, $r1, $fg, $fl)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$it.Desc, $fontUi, $r2, $mu, $fl)
    })
    $tb.Add_TextChanged({ Update-PaletteSuggestions })
    $runSel = {
        $pc = $script:PalCtl
        $cmd = if ($pc.List.SelectedIndex -ge 0) { [string]$pc.Items[$pc.List.SelectedIndex].Text } else { $pc.Text.Text }
        $cmd = $cmd.Trim()
        if (-not $cmd) { return }
        $chk = ConvertFrom-TerminalCommand $cmd
        if ($chk.Kind -eq "Error") { $pc.Err.Text = $chk.Error; return }
        $pc.Run = $cmd
        $pc.Form.Close()
    }
    $script:PalCtl.RunSel = $runSel
    $f.Add_KeyDown({
        param($sender, $e)
        $pc = $script:PalCtl
        $n = $pc.List.Items.Count
        switch ($e.KeyCode) {
            ([System.Windows.Forms.Keys]::Escape) { $e.SuppressKeyPress = $true; $sender.Close() }
            ([System.Windows.Forms.Keys]::Down) { $e.SuppressKeyPress = $true; if ($n -gt 0) { $pc.List.SelectedIndex = [math]::Min($n - 1, $pc.List.SelectedIndex + 1) } }
            ([System.Windows.Forms.Keys]::Up) { $e.SuppressKeyPress = $true; if ($n -gt 0) { $pc.List.SelectedIndex = [math]::Max(-1, $pc.List.SelectedIndex - 1) } }
            ([System.Windows.Forms.Keys]::Tab) {
                $e.SuppressKeyPress = $true
                if ($n -gt 0) {
                    $ix = [math]::Max(0, $pc.List.SelectedIndex)
                    $pc.Text.Text = [string]$pc.Items[$ix].Text + " "
                    $pc.Text.SelectionStart = $pc.Text.Text.Length
                }
            }
            ([System.Windows.Forms.Keys]::Enter) { $e.SuppressKeyPress = $true; & $script:PalCtl.RunSel }
        }
    })
    # Tab must reach KeyDown instead of moving the focus
    $tb.Add_PreviewKeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Tab) { $e.IsInputKey = $true } })
    $lb.Add_DoubleClick({ & $script:PalCtl.RunSel })
    $lb.Add_Click({ $script:PalCtl.Text.Focus() | Out-Null })
    $f.Add_Deactivate({ param($sender, $e) if ($null -ne $script:PalCtl -and -not $script:PalCtl.Run) { $sender.Close() } })
    $f.Add_Shown({
        $pc = $script:PalCtl
        $pc.Text.Focus() | Out-Null
        $pc.Text.SelectionStart = $pc.Text.Text.Length
        $pc.Err.ForeColor = $script:Pal.Muted
        Update-PaletteSuggestions
        $pc.Err.Text = $pc.Hint
    })
    $tb.Text = $Initial
    # position: top centre of the visible main window, else of the screen
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    if ($form.Visible -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
        $x = $form.Left + [int](($form.Width - $f.Width) / 2)
        $y = $form.Top + (S 70)
    } else {
        $x = $wa.Left + [int](($wa.Width - $f.Width) / 2)
        $y = $wa.Top + [int]($wa.Height * 0.2)
    }
    $x = [math]::Max($wa.Left, [math]::Min($x, $wa.Right - $f.Width))
    $y = [math]::Max($wa.Top, [math]::Min($y, $wa.Bottom - $f.Height))
    $f.Location = New-Object System.Drawing.Point($x, $y)
    $tb.Add_TextChanged({ $script:PalCtl.Err.ForeColor = $colRed })
    [void]$f.ShowDialog()
    $run = [string]$script:PalCtl.Run
    $script:PalCtl = $null
    $f.Dispose()
    if ($run) {
        Write-WidgetLog "Command: $run"
        $script:Config.CommandHistory = @(Add-RecentCommand -Recent @($script:Config.CommandHistory) -Command $run)
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        $msg = ""
        try { $msg = Invoke-TerminalCommand $run } catch { $msg = "Fehler: $($_.Exception.Message)"; Write-WidgetLog "Command '$run' failed: $($_.Exception.Message)" "ERROR" }
        if ($msg) {
            # show the problem and let the user fix the line
            Set-TransientStatus $msg 6
            Show-CommandPalette -Initial $run
        }
    }
}

# ---- tray tooltip with today's portfolio result, polling while markets are closed ----
function Get-TrayDepotLine {
    param([string]$Currency)
    if ($script:Portfolio.Count -eq 0) { return "" }
    $pt = Get-PortfolioDayTotals -Currency $Currency
    if (-not $pt.Ok) { return "" }
    $d = $pt.Value - $pt.Prev
    if ([bool]$script:Config.PrivacyMode) { return ("Depot {0:+0.00;-0.00}%" -f $pt.DayPct) }
    return ("Depot {0:+#,##0;-#,##0} {1} ({2:+0.00;-0.00}%)" -f $d, $Currency, $pt.DayPct)
}

function Get-PrioMarketStates {
    # Market states of everything polled every time; empty = unknown (do not skip)
    $tiers = Get-QuoteTiers
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $out = @()
    foreach ($s in @($tiers.Prio)) {
        $q = $script:QuoteStore[$s]
        if ($null -eq $q -or $null -eq $q.Tp -or [bool]$q.FromCache) { return @() }
        $ms = Get-MarketState -Tp $q.Tp -NowSec $now
        if ($null -eq $ms) { return @() }
        $out += [string]$ms.State
    }
    return $out
}

function Show-InfoBox {
    param([string]$Text, [string]$Title = "Hinweis")
    if ($env:TW_SMOKE_TEST) { Write-WidgetLog "InfoBox: $Text"; return }
    $owner = if ($null -ne $form -and -not $form.IsDisposed) { $form } else { $null }
    [void][System.Windows.Forms.MessageBox]::Show($owner, $Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# ==============================================================================
# v4.5: depots, CSV import, backups / restore, export / import, portable mode
# ==============================================================================
function Switch-Depot {
    param([string]$Id)
    if ($Id -eq [string]$script:Config.ActiveDepot) { return }
    Set-DepotPaths $Id
    Read-PortfolioData
    Read-TransactionsData
    Read-CashData
    Read-SavingsPlans
    $script:Config.ActiveDepot = $Id
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Write-WidgetLog ("Depot switched to '{0}'" -f (Get-DepotName $Id))
    Update-DepotCombo
    Set-TransientStatus ("Depot: {0}" -f (Get-DepotName $Id)) 3
    Refresh-AllMarketData
    Update-AllUiViews
}

function Read-TextInput {
    # Small input box; returns the text or $null when cancelled
    param([string]$Title, [string]$Prompt, [string]$Value = "", [scriptblock]$Validate = $null)
    $p = $script:Pal
    # V7.1: standard dialog template (title, subtitle, inline error, primary button right)
    $sd = New-StandardDialog -Title $Title -Subtitle $Prompt -W 400 -BodyH 32
    $dlg = $sd.Dlg
    $t = New-Object System.Windows.Forms.TextBox
    $t.SetBounds(0, (S 4), $sd.Body.Width, (S 24)); $t.Text = $Value
    $t.BackColor = $p.Input; $t.ForeColor = $p.Text; $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $sd.Body.Controls.Add($t)
    $dlg.Tag.Input = $t; $dlg.Tag.Validate = $Validate
    $t.Add_TextChanged({ param($s, $e) $f = $s.FindForm(); if ($null -ne $f -and $null -ne $f.Tag) { $f.Tag.Err.Text = "" } })
    $dlg.Add_Shown({ param($s, $e) try { $s.Tag.Input.Focus(); $s.Tag.Input.SelectAll() } catch { } })
    $res = $dlg.ShowDialog($form)
    $v = $t.Text.Trim()
    $dlg.Dispose()
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $v
}

function New-Depot {
    $name = Read-TextInput -Title "Neues Depot" -Prompt "Name des Depots (z. B. Zweitbroker, Übungsdepot)" -Validate { param($t) $v = $t.Trim(); if (-not $v) { "Bitte einen Namen eingeben." } elseif ($v.Length -gt 40) { "Höchstens 40 Zeichen." } else { "" } }
    if (-not $name) { return }
    $base = ConvertTo-DepotId $name
    $id = $base; $n = 2
    while (@(Get-DepotList | Where-Object { $_.Id -eq $id }).Count -gt 0) { $id = "{0}-{1}" -f $base, $n; $n++ }
    $script:Config.Depots = @(@($script:Config.Depots) | Where-Object { $null -ne $_ }) + @([PSCustomObject]@{ Id = $id; Name = $name })
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Write-WidgetLog "Depot created: $name ($id)"
    Switch-Depot $id
}

function Rename-ActiveDepot {
    $id = [string]$script:Config.ActiveDepot
    $name = Read-TextInput -Title "Depot umbenennen" -Prompt "Neuer Name:" -Value (Get-DepotName $id)
    if (-not $name) { return }
    if (-not $id) { $script:Config.MainDepotName = $name }
    else { foreach ($d in @($script:Config.Depots)) { if ([string]$d.Id -eq $id) { $d.Name = $name } } }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-DepotCombo
}

function Remove-ActiveDepot {
    $id = [string]$script:Config.ActiveDepot
    if (-not $id) { Show-InfoBox -Text "Das Hauptdepot kann nicht gelöscht werden." -Title "Depot"; return }
    $name = Get-DepotName $id
    if (-not (Confirm-Action -Text ("Depot '{0}' mit allen Positionen und Buchungen löschen?`r`n`r`nDie Dateien werden vorher ins Backup kopiert." -f $name) -Title "Depot löschen")) { return }
    [void](Backup-DataFiles -Reason ("vor_loeschen_" + $id))
    Switch-Depot ""
    try { Remove-Item -Path (Join-Path $script:DepotDir $id) -Recurse -Force -ErrorAction Stop } catch { Write-WidgetLog "Depot folder not removed: $($_.Exception.Message)" "WARN" }
    $script:Config.Depots = @(@($script:Config.Depots) | Where-Object { $null -ne $_ -and [string]$_.Id -ne $id })
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-DepotCombo
    Set-TransientStatus "Depot '$name' gelöscht" 4
}

$script:DepotComboBusy = $false
function Update-DepotCombo {
    $script:DepotComboBusy = $true
    try {
        $cmbDepot.Items.Clear()
        $sel = 0; $i = 0
        foreach ($d in Get-DepotList) {
            [void]$cmbDepot.Items.Add($d.Name)
            if ($d.Id -eq [string]$script:Config.ActiveDepot) { $sel = $i }
            $i++
        }
        foreach ($x in @("+ Neues Depot ...", "  Umbenennen ...", "  Löschen ...")) { [void]$cmbDepot.Items.Add($x) }
        $cmbDepot.SelectedIndex = $sel
    } finally { $script:DepotComboBusy = $false }
}

# ---- backups ----
function Invoke-DailyBackup {
    $today = (Get-Date).ToString("yyyy-MM-dd")
    if ([string]$script:Config.LastAutoBackup -eq $today) { return }
    if (Backup-DataFiles -Reason "taeglich") {
        $script:Config.LastAutoBackup = $today
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
    }
}

function Restart-Widget {
    # Restored / imported data must not be overwritten by this instance on exit
    # (V7.0: -KeepData for a plain restart, e.g. after a DPI change: state is saved normally)
    param([switch]$KeepData)
    $script:FreezeData = (-not $KeepData)
    $bat = Join-Path $script:ScriptDir "TerminalWidget_Start.bat"
    try {
        if (Test-Path $bat) {
            Start-Process -FilePath "cmd.exe" -ArgumentList ('/c timeout /t 3 /nobreak >nul & start "" "{0}"' -f $bat) -WindowStyle Hidden
        } else {
            $exe = (Get-Process -Id $PID).Path
            $self = Join-Path $script:ScriptDir "TerminalWidget.ps1"
            Start-Process -FilePath "cmd.exe" -ArgumentList ('/c timeout /t 3 /nobreak >nul & start "" "{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $exe, $self) -WindowStyle Hidden
        }
    } catch { Write-WidgetLog "Restart failed: $($_.Exception.Message)" "ERROR" }
    Write-WidgetLog "Restarting the widget"
    $trayIcon.Visible = $false
    $form.Close()
}

function Copy-DataSet {
    # Copies the data files (+ depots folder) from $From to $To
    param([string]$From, [string]$To)
    foreach ($f in @(Get-DataFileNames)) {
        $src = Join-Path $From $f
        if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $To $f) -Force }
    }
    $dSrc = Join-Path $From "depots"
    if (Test-Path $dSrc) {
        $dDst = Join-Path $To "depots"
        if (Test-Path $dDst) { Remove-Item -Path $dDst -Recurse -Force }
        Copy-Item -Path $dSrc -Destination $dDst -Recurse -Force
    }
}

function Show-RestoreDialog {
    $rows = @()
    if (Test-Path $script:BackupDir) {
        foreach ($d in @(Get-ChildItem -Path $script:BackupDir -Directory | Sort-Object Name -Descending)) {
            $bi = Get-BackupInfo $d.Name
            $n = @(Get-ChildItem -Path $d.FullName -File).Count
            $dep = if (Test-Path (Join-Path $d.FullName "depots")) { "+ Depots" } else { "" }
            $rows += @{ Cells = @($(if ($bi.When -gt [DateTime]::MinValue) { $bi.When.ToString("dd.MM.yyyy HH:mm") } else { $d.Name }), $bi.Reason, ("{0} Dateien {1}" -f $n, $dep).Trim()); Tag = $d.FullName }
        }
    }
    Show-InfoGrid -Title "Backup wiederherstellen (BAK)" -Columns @("Zeitpunkt", "Anlass", "Inhalt") -Weights @(140, 200, 140) -W 560 -H 460 -Footer "Doppelklick = dieses Backup wiederherstellen (der aktuelle Stand wird vorher gesichert, danach startet das Widget neu). Täglich wird automatisch gesichert, die letzten 20 bleiben." -Extra @{ Rows = $rows } -OnShown { Set-InfoRows -Rows $script:InfoCtl.Rows } -OnDouble {
        param($Tag)
        $src = [string]$Tag
        $bi = Get-BackupInfo (Split-Path -Leaf $src)
        if (-not (Confirm-Action -Text ("Stand vom {0} wiederherstellen?`r`n`r`nEinstellungen, Portfolio, Depots, Alarme und Buchungen werden ersetzt. Der aktuelle Stand wird vorher gesichert. Danach startet das Widget neu." -f $bi.When.ToString("dd.MM.yyyy HH:mm")) -Title "Wiederherstellen")) { return }
        [void](Backup-DataFiles -Reason "vor_wiederherstellung")
        try {
            Copy-DataSet -From $src -To $script:DataDir
            Write-WidgetLog "Backup restored: $src"
        } catch {
            Write-WidgetLog "Restore failed: $($_.Exception.Message)" "ERROR"
            Show-InfoBox -Text "Wiederherstellen fehlgeschlagen: $($_.Exception.Message)" -Title "Wiederherstellen"
            return
        }
        $script:InfoCtl.Dlg.Close()
        Restart-Widget
    }
}

function Export-DataZip {
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "ZIP-Archiv (*.zip)|*.zip"
    $sfd.FileName = "TerminalWidget_Daten_{0}.zip" -f (Get-Date -Format "yyyyMMdd")
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("tw_export_" + [Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        Copy-DataSet -From $script:DataDir -To $tmp
        Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $sfd.FileName -Force
        Write-WidgetLog "Data exported: $($sfd.FileName)"
        Show-InfoBox -Text ("Exportiert nach:`r`n{0}`r`n`r`nHinweis: ein Telegram-Token ist an dein Windows-Konto gebunden und muss auf einem anderen PC neu eingetragen werden." -f $sfd.FileName) -Title "Export"
    } catch {
        Write-WidgetLog "Export failed: $($_.Exception.Message)" "ERROR"
        Show-InfoBox -Text "Export fehlgeschlagen: $($_.Exception.Message)" -Title "Export"
    } finally { Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Import-DataZip {
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "ZIP-Archiv (*.zip)|*.zip"
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("tw_import_" + [Guid]::NewGuid().ToString("N"))
    try {
        Expand-Archive -Path $ofd.FileName -DestinationPath $tmp -Force
        if (-not (Test-Path (Join-Path $tmp "config.json"))) { Show-InfoBox -Text "Das Archiv enthält keine config.json - kein TerminalWidget-Export." -Title "Import"; return }
        if (-not (Confirm-Action -Text "Alle Daten durch den Inhalt des Archivs ersetzen?`r`nDer aktuelle Stand wird vorher gesichert. Danach startet das Widget neu." -Title "Import")) { return }
        [void](Backup-DataFiles -Reason "vor_import")
        Copy-DataSet -From $tmp -To $script:DataDir
        Write-WidgetLog "Data imported: $($ofd.FileName)"
        Restart-Widget
    } catch {
        Write-WidgetLog "Import failed: $($_.Exception.Message)" "ERROR"
        Show-InfoBox -Text "Import fehlgeschlagen: $($_.Exception.Message)" -Title "Import"
    } finally { Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Switch-PortableMode {
    # portable.txt next to the script = data in <program folder>\data
    $flag = Join-Path $script:ScriptDir "portable.txt"
    $portDir = Join-Path $script:ScriptDir "data"
    $localDir = Join-Path $env:LOCALAPPDATA "TerminalWidget"
    if ($script:IsPortable) {
        if (-not (Confirm-Action -Text ("Portabel-Modus beenden?`r`nDie Daten werden nach {0} kopiert, danach startet das Widget neu." -f $localDir) -Title "Portabel")) { return }
        try {
            if (-not (Test-Path $localDir)) { New-Item -ItemType Directory -Path $localDir -Force | Out-Null }
            [void](Backup-DataFiles -Reason "vor_portabel_aus")
            Copy-DataSet -From $script:DataDir -To $localDir
            Remove-Item -Path $flag -Force
        } catch { Show-InfoBox -Text "Fehlgeschlagen: $($_.Exception.Message)" -Title "Portabel"; return }
    } else {
        if (-not (Confirm-Action -Text ("Portabel-Modus einschalten?`r`nDie Daten werden nach {0} kopiert (z. B. für einen USB-Stick), danach startet das Widget neu. Autostart zeigt weiter auf diesen Ordner." -f $portDir) -Title "Portabel")) { return }
        try {
            if (-not (Test-Path $portDir)) { New-Item -ItemType Directory -Path $portDir -Force | Out-Null }
            Copy-DataSet -From $script:DataDir -To $portDir
            Set-Content -Path $flag -Value "Daten liegen im Unterordner data (TerminalWidget portabel). Datei löschen = wieder %LOCALAPPDATA%." -Encoding UTF8
        } catch { Show-InfoBox -Text "Fehlgeschlagen (Ordner schreibgeschützt?): $($_.Exception.Message)" -Title "Portabel"; return }
    }
    Restart-Widget
}

# ---- CSV import ----
function Read-TextFileGuess {
    # UTF-8 (with or without BOM), else Windows-1252 (German broker exports)
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { return $utf8.GetString($bytes).TrimStart([char]0xFEFF) } catch { return [System.Text.Encoding]::GetEncoding(1252).GetString($bytes) }
}

function Show-CsvImportDialog {
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "CSV / Text (*.csv;*.txt)|*.csv;*.txt|Alle Dateien (*.*)|*.*"
    $ofd.Title = "Broker-Export (CSV) wählen"
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $csv = $null
    try { $csv = ConvertFrom-CsvText (Read-TextFileGuess $ofd.FileName) } catch { Write-WidgetLog "CSV read failed: $($_.Exception.Message)" "ERROR" }
    if ($null -eq $csv -or @($csv.Headers).Count -lt 2 -or @($csv.Rows).Count -eq 0) {
        Show-InfoBox -Text "In der Datei wurde keine Tabelle gefunden (Kopfzeile + Zeilen, getrennt mit ; , oder Tab)." -Title "CSV-Import"
        return
    }
    $p = $script:Pal
    $dlg = New-DialogForm -Title ("CSV-Import - {0} -> Depot '{1}'" -f (Split-Path -Leaf $ofd.FileName), (Get-DepotName ([string]$script:Config.ActiveDepot))) -W (S 1000) -H (S 640)
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 860), (S 480))
    $aTLR = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $aAll = $aTLR -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $aBL = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $aBR = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
    $info = New-Object System.Windows.Forms.Label
    $info.SetBounds((S 12), (S 8), (S 560), (S 20)); $info.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left; $info.ForeColor = $p.Muted
    $info.Text = "Spalten prüfen, Häkchen setzen, Symbole anpassen. Doppelte Buchungen werden übersprungen."
    $dlg.Controls.Add($info)
    # step indicator: Datei > Spalten > Prüfen > Import (step 2 until a column is changed, then 3)
    $steps = New-Object System.Windows.Forms.Panel
    $steps.SetBounds((S 580), (S 6), (S 408), (S 24)); $steps.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
    $steps.BackColor = $dlg.BackColor; $steps.Tag = 2
    $steps.Add_Paint({
        param($s, $e)
        $pp = $script:Pal; $g2 = $e.Graphics
        $g2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $names = @("Datei", "Spalten", "Prüfen", "Import"); $cur = [int]$s.Tag
        $w = [int]($s.Width / 4); $f = $s.Font
        for ($k = 0; $k -lt 4; $k++) {
            $x0 = $k * $w; $d = [int](S 14); $cy = [int](($s.Height - $d) / 2)
            $done = (($k + 1) -lt $cur); $act = (($k + 1) -eq $cur)
            $fill = if ($done -or $act) { $pp.Accent } else { $pp.Border }
            $bF = New-Object System.Drawing.SolidBrush($fill)
            $g2.FillEllipse($bF, $x0 + 2, $cy, $d, $d); $bF.Dispose()
            $col = if ($act) { $pp.Text } elseif ($done) { $pp.Muted } else { $pp.Muted }
            $txt = if ($done) { [string][char]0x2713 + " " + $names[$k] } else { ([string]($k + 1)) + " " + $names[$k] }
            $br = New-Object System.Drawing.SolidBrush($col)
            $g2.DrawString($txt, $f, $br, [single]($x0 + $d + 6), [single]($cy - 1)); $br.Dispose()
        }
    })
    $dlg.Controls.Add($steps)
    $guess = Get-CsvColumnGuess -Headers $csv.Headers
    $fields = Get-CsvFieldNames
    $combos = @{}
    $i = 0
    foreach ($f in $fields.Keys) {
        $x = (S 12) + ($i % 5) * (S 196)
        $y = (S 34) + [math]::Floor($i / 5) * (S 30)
        $l = New-Object System.Windows.Forms.Label
        $l.SetBounds($x, ($y + (S 3)), (S 74), (S 18)); $l.Text = $fields[$f]
        $dlg.Controls.Add($l)
        $cb = New-Object System.Windows.Forms.ComboBox
        $cb.SetBounds(($x + (S 76)), $y, (S 112), (S 24))
        $cb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cb.BackColor = $p.Input; $cb.ForeColor = $p.Text
        [void]$cb.Items.Add("(keine)")
        foreach ($h in $csv.Headers) { [void]$cb.Items.Add($(if ($h) { $h } else { "(leer)" })) }
        $cb.SelectedIndex = [int]$guess[$f] + 1
        $cb.DropDownWidth = S 200
        $dlg.Controls.Add($cb)
        $combos[$f] = $cb
        $i++
    }
    $y2 = S 98
    $lCur = New-Object System.Windows.Forms.Label
    $lCur.SetBounds((S 12), ($y2 + (S 3)), (S 150), (S 18)); $lCur.Text = "Währung, wenn leer:"
    $dlg.Controls.Add($lCur)
    $cbCur = New-Object System.Windows.Forms.ComboBox
    $cbCur.SetBounds((S 164), $y2, (S 70), (S 24))
    $cbCur.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbCur.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cbCur.BackColor = $p.Input; $cbCur.ForeColor = $p.Text
    foreach ($c in @("EUR", "USD", "CHF", "GBP")) { [void]$cbCur.Items.Add($c) }
    $cbCur.SelectedIndex = 0
    $dlg.Controls.Add($cbCur)
    $lSuf = New-Object System.Windows.Forms.Label
    $lSuf.SetBounds((S 250), ($y2 + (S 3)), (S 150), (S 18)); $lSuf.Text = "ISIN bevorzugt an Börse:"
    $dlg.Controls.Add($lSuf)
    $cbSuf = New-Object System.Windows.Forms.ComboBox
    $cbSuf.SetBounds((S 402), $y2, (S 120), (S 24))
    $cbSuf.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbSuf.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cbSuf.BackColor = $p.Input; $cbSuf.ForeColor = $p.Text
    foreach ($c in @("Heimatbörse", ".DE Xetra", ".F Frankfurt", ".VI Wien", ".SW Zürich", ".L London", ".AS Amsterdam", ".PA Paris")) { [void]$cbSuf.Items.Add($c) }
    $cbSuf.SelectedIndex = 0
    $dlg.Controls.Add($cbSuf)
    Set-DynTip $cbSuf "Bei ISINs: welches Yahoo-Symbol genommen wird. Heimatbörse = erster Treffer (meist US/Heimatmarkt); .DE = Xetra-Kurse in EUR."
    $btnRes = New-Object System.Windows.Forms.Button
    $btnRes.SetBounds((S 534), ($y2 - (S 1)), (S 150), (S 26))
    Style-FlatButton -Btn $btnRes -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $btnRes.Text = "ISINs auflösen"
    $dlg.Controls.Add($btnRes)
    $chkReb = New-Object System.Windows.Forms.CheckBox
    $chkReb.SetBounds((S 700), $y2, (S 290), (S 24)); $chkReb.Anchor = $aTLR
    $chkReb.Text = "Positionen danach aus Buchungen berechnen"; $chkReb.Checked = $true
    $chkReb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $dlg.Controls.Add($chkReb)
    Set-DynTip $chkReb "Stück und EK der betroffenen Positionen werden aus allen Buchungen neu berechnet (Durchschnittskosten, Splits berücksichtigt)" "REBUILD"
    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds((S 12), (S 132), (S 976), (S 450)); $g.Anchor = $aAll
    Style-DataGrid -Grid $g
    $g.ReadOnly = $false
    $g.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::CellSelect
    $chkCol = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $chkCol.Name = "Use"; $chkCol.HeaderText = ""; $chkCol.FillWeight = [float](S 30)
    [void]$g.Columns.Add($chkCol)
    foreach ($cd in @(@("Date", "Datum", 90), @("Type", "Art", 80), @("Ident", "Ticker / ISIN", 130), @("Sym", "Symbol", 90), @("Shares", "Stück", 80), @("Price", "Kurs / Betrag", 100), @("Fee", "Gebühr", 70), @("Cur", "Whg", 50), @("Note", "Hinweis", 220))) {
        $ci = $g.Columns.Add($cd[0], $cd[1])
        $g.Columns[$ci].FillWeight = [float](S $cd[2])
        $g.Columns[$ci].ReadOnly = ($cd[0] -ne "Sym")
    }
    $g.Columns["Sym"].DefaultCellStyle.ForeColor = $p.Accent
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $dlg.Controls.Add($g)
    $lSum = New-Object System.Windows.Forms.Label
    $lSum.SetBounds((S 12), (S 594), (S 700), (S 34)); $lSum.Anchor = $aBL -bor [System.Windows.Forms.AnchorStyles]::Right; $lSum.ForeColor = $p.Muted
    $dlg.Controls.Add($lSum)
    $btnImp = New-Object System.Windows.Forms.Button
    $btnImp.SetBounds((S 794), (S 598), (S 94), (S 28)); $btnImp.Anchor = $aBR
    Style-FlatButton -Btn $btnImp -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnImp.Text = "Importieren"
    $dlg.Controls.Add($btnImp)
    $btnCa = New-Object System.Windows.Forms.Button
    $btnCa.SetBounds((S 894), (S 598), (S 94), (S 28)); $btnCa.Anchor = $aBR
    Style-FlatButton -Btn $btnCa -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $btnCa.Text = "Abbrechen"
    $btnCa.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCa)
    $dlg.CancelButton = $btnCa

    $script:CsvCtl = @{ Dlg = $dlg; Grid = $g; Csv = $csv; Combos = $combos; Cur = $cbCur; Suf = $cbSuf; Sum = $lSum; Reb = $chkReb; Rows = @(); IsinMap = @{}; File = (Split-Path -Leaf $ofd.FileName); Imported = 0; Guess = $guess; CashN = 0 }
    $script:CsvCtl.Fill = {
        $cc = $script:CsvCtl
        $map = @{}
        foreach ($f in $cc.Combos.Keys) { $map[$f] = $cc.Combos[$f].SelectedIndex - 1 }
        # v5.5: automatic extras (currency of the total, exchange rate, more fee columns)
        foreach ($f in @("AmountCurrency", "TaxCurrency", "Rate", "FeeExtra")) { if ($cc.Guess.ContainsKey($f)) { $map[$f] = $cc.Guess[$f] } }
        $cc.Rows = @(ConvertFrom-BrokerRows -Rows $cc.Csv.Rows -Map $map -DefaultCurrency ([string]$cc.Cur.SelectedItem))
        $existing = $script:Transactions.ToArray()
        $cc.Grid.Rows.Clear()
        $nOk = 0; $nDup = 0; $nIsin = 0
        $nCash = 0
        foreach ($b in $cc.Rows) {
            if ([bool]$b.Cash) {
                # v5.5: deposits / withdrawals / interest -> cash account
                $note = $b.Note; $use = $b.Ok
                if ($use -and -not [bool]$script:Cash.Enabled) { $note = "Cash-Konto ist aus (CASH)"; $use = $false }
                elseif ($use -and @($script:Cash.Entries | Where-Object { [string]$_.Date -eq $b.Date -and [string]$_.Kind -eq $b.Type -and [math]::Abs([double]$_.Amount - [double]$b.Amount) -lt 0.005 }).Count -gt 0) { $note = "schon vorhanden"; $use = $false; $nDup++ }
                elseif ($use) { $note = "Cash-Konto"; $nCash++ }
                $ri = $cc.Grid.Rows.Add($use, (Format-IsoDateDe $b.Date), $b.Type, "", "", "", ("{0:N2}" -f $b.Amount), "", $b.Currency, $note)
                if (-not $use) { $cc.Grid.Rows[$ri].DefaultCellStyle.ForeColor = $script:Pal.Muted }
                continue
            }
            $sym = if (Test-Isin $b.Ident) { [string]$cc.IsinMap[$b.Ident] } else { $b.Ident }
            $note = $b.Note
            $use = $b.Ok
            if ($b.Ok -and -not $sym) { $note = "ISIN noch nicht aufgelöst"; $use = $false; $nIsin++ }
            elseif ($b.Ok -and (Test-DuplicateTransaction -Existing $existing -New ([PSCustomObject]@{ Date = $b.Date; Ticker = $sym; Type = $b.Type; Shares = $b.Shares; Price = $b.Price }))) { $note = "schon vorhanden"; $use = $false; $nDup++ }
            if ($use) { $nOk++ }
            $ri = $cc.Grid.Rows.Add($use, (Format-IsoDateDe $b.Date), $b.Type, $b.Ident, $sym, ("{0:N4}" -f $b.Shares), ("{0:N4}" -f $b.Price), ("{0:N2}" -f $b.Fee), $b.Currency, $note)
            if (-not $b.Ok) { $cc.Grid.Rows[$ri].DefaultCellStyle.ForeColor = $script:Pal.Muted }
        }
        $cc.Sum.Text = "{0} Zeilen: {1} zum Import, {2} Cash-Bewegungen, {3} schon vorhanden, {4} ISIN offen, {5} übersprungen (Art/Datum/Stück fehlen)." -f $cc.Rows.Count, $nOk, $nCash, $nDup, $nIsin, @($cc.Rows | Where-Object { -not $_.Ok }).Count
    }
    $script:CsvCtl.Steps = $steps
    foreach ($cb in @($combos.Values) + @($cbCur)) { $cb.Add_SelectionChangeCommitted({ & $script:CsvCtl.Fill; $script:CsvCtl.Steps.Tag = 3; $script:CsvCtl.Steps.Invalidate() }) }
    $btnRes.Add_Click({
        $cc = $script:CsvCtl
        $isins = @($cc.Rows | Where-Object { Test-Isin $_.Ident } | ForEach-Object { $_.Ident } | Sort-Object -Unique | Where-Object { -not $cc.IsinMap.ContainsKey($_) })
        if ($isins.Count -eq 0) { & $cc.Fill; return }
        $suf = ([string]$cc.Suf.SelectedItem).Split(' ')[0]
        if (-not $suf.StartsWith(".")) { $suf = "" }
        $cc.Sum.Text = "Suche {0} ISIN(s) bei Yahoo ..." -f $isins.Count
        $cc.Dlg.Refresh()
        $urls = @{}
        foreach ($is in $isins) { $urls[$is] = "https://query1.finance.yahoo.com/v1/finance/search?q={0}&quotesCount=10&newsCount=0" -f $is }
        $res = Invoke-ParallelFetch -Urls @($urls.Values) -TimeoutSec 12
        foreach ($is in $isins) {
            $s = Get-YahooSymbolFromSearch -Json $res[$urls[$is]] -PreferSuffix $suf
            if ($s) { $cc.IsinMap[$is] = $s }
        }
        & $cc.Fill
    })
    $g.Add_CellEndEdit({
        param($sender, $e)
        if ($sender.Columns[$e.ColumnIndex].Name -ne "Sym") { return }
        $cc = $script:CsvCtl
        $b = $cc.Rows[$e.RowIndex]
        $v = ([string]$sender.Rows[$e.RowIndex].Cells["Sym"].Value).Trim().ToUpper()
        $sender.Rows[$e.RowIndex].Cells["Sym"].Value = $v
        if ((Test-Isin $b.Ident) -and $v) { $cc.IsinMap[$b.Ident] = $v }
        if ($v -and $b.Ok) { $sender.Rows[$e.RowIndex].Cells["Use"].Value = $true }
    })
    $btnImp.Add_Click({
        $cc = $script:CsvCtl
        $cc.Grid.EndEdit() | Out-Null
        $n = 0
        # v5.5: backup first - cash rows are written right away
        if (@(for ($k = 0; $k -lt $cc.Rows.Count; $k++) { if ([bool]$cc.Grid.Rows[$k].Cells["Use"].Value) { 1 } }).Count -gt 0) { [void](Backup-DataFiles -Reason "vor_csv_import") }
        $syms = New-Object System.Collections.Generic.HashSet[string]
        for ($k = 0; $k -lt $cc.Rows.Count; $k++) {
            $row = $cc.Grid.Rows[$k]
            if (-not [bool]$row.Cells["Use"].Value) { continue }
            $b = $cc.Rows[$k]
            if ([bool]$b.Cash) {
                if ($b.Ok -and [bool]$script:Cash.Enabled) {
                    # amount in the cash currency (today's rate if the broker used another one)
                    $amt = Convert-CurrencyValue -Amount ([double]$b.Amount) -FromCurrency ([string]$b.Currency) -ToCurrency ([string]$script:Cash.Currency)
                    Add-CashEntry -Kind $b.Type -Amount $amt -Date $b.Date -Note ("CSV-Import " + $cc.File)
                    $cc.CashN++
                }
                continue
            }
            $sym = ([string]$row.Cells["Sym"].Value).Trim().ToUpper()
            if (-not $b.Ok -or -not $sym) { continue }
            $script:Transactions.Add([PSCustomObject]@{
                Id = [Guid]::NewGuid().ToString("N"); Date = $b.Date; Ticker = $sym; Type = $b.Type
                Shares = [double]$b.Shares; Price = [double]$b.Price; Fee = [double]$b.Fee; Currency = $b.Currency
                Realized = 0.0; Note = "CSV-Import " + $cc.File
            })
            [void]$syms.Add($sym)
            $n++
        }
        if ($n -eq 0 -and $cc.CashN -gt 0) { $cc.Imported = $cc.CashN; $cc.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK; $cc.Dlg.Close(); return }
        if ($n -eq 0) { $cc.Sum.Text = "Nichts ausgewählt."; return }
        Save-Transactions
        Write-WidgetLog ("CSV import: {0} bookings from {1}" -f $n, $cc.File)
        if ($cc.Reb.Checked) {
            foreach ($s in $syms) { [void](Invoke-PositionRebuild -Ticker $s -Owner $cc.Dlg -Silent) }
        }
        $cc.Imported = $n
        $cc.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $cc.Dlg.Close()
    })
    $dlg.Add_Shown({ & $script:CsvCtl.Fill })
    [void]$dlg.ShowDialog($form)
    $n = [int]$script:CsvCtl.Imported
    $script:CsvCtl = $null
    $dlg.Dispose()
    if ($n -gt 0) {
        Set-TransientStatus ("{0} Buchungen importiert" -f $n) 5
        Refresh-AllMarketData
        Update-AllUiViews
    }
}

# ==============================================================================
# v4.6: grid columns, global hotkey, click-through, snapping, undo, price
# flash, colours, own layouts, welcome tour
# ==============================================================================

# ---- colours ----
function Get-BlendColor {
    param([System.Drawing.Color]$A, [System.Drawing.Color]$B, [double]$T)
    return [System.Drawing.Color]::FromArgb([int]($B.R + ($A.R - $B.R) * $T), [int]($B.G + ($A.G - $B.G) * $T), [int]($B.B + ($A.B - $B.B) * $T))
}

function Update-UpDownColors {
    $ud = Get-UpDownColors -Scheme ([string]$script:Config.UpDownScheme) -UpHex ([string]$script:Config.UpColor) -DownHex ([string]$script:Config.DownColor)
    $script:colGreen = [System.Drawing.Color]::FromArgb($ud.Up[0], $ud.Up[1], $ud.Up[2])
    $script:colRed = [System.Drawing.Color]::FromArgb($ud.Down[0], $ud.Down[1], $ud.Down[2])
}

function Get-ArrowPrefix {
    param([double]$V)
    if (-not [bool]$script:Config.ShowArrows) { return "" }
    if ($V -gt 0) { return [string][char]0x25B2 + " " }
    if ($V -lt 0) { return [string][char]0x25BC + " " }
    return ""
}

# ---- grid columns: right-click on a header, drag headers to reorder ----
$script:GridDefaults = @{}
$script:GridLayoutSig = @{}
$script:GridLayoutBusy = $false

function Save-GridLayout {
    param([System.Windows.Forms.DataGridView]$Grid, [string]$Key)
    if ($script:GridLayoutBusy) { return }
    $gl = $script:Config.GridLayouts
    if ($null -eq $gl) { $gl = [PSCustomObject]@{}; $script:Config.GridLayouts = $gl }
    $val = @(ConvertTo-GridLayout @($Grid.Columns))
    # resizing the window changes widths but not the weights: only save real changes
    $sig = ($val | ForEach-Object { "{0}:{1}:{2:F1}:{3}" -f $_.Name, $_.Index, $_.Weight, $_.Visible }) -join "|"
    if ($script:GridLayoutSig[$Key] -eq $sig) { return }
    $script:GridLayoutSig[$Key] = $sig
    if ($null -eq $gl.PSObject.Properties[$Key]) { $gl | Add-Member -NotePropertyName $Key -NotePropertyValue $val -Force } else { $gl.$Key = $val }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
}

function Restore-GridLayout {
    param([System.Windows.Forms.DataGridView]$Grid, [string]$Key, [switch]$Defaults)
    $items = $null
    if ($Defaults) { $items = $script:GridDefaults[$Key] }
    elseif ($null -ne $script:Config.GridLayouts -and $null -ne $script:Config.GridLayouts.PSObject.Properties[$Key]) { $items = @($script:Config.GridLayouts.$Key) }
    if ($null -eq $items) { return }
    $script:GridLayoutBusy = $true
    try {
        foreach ($it in @($items | Sort-Object -Property @{ Expression = { [int]$_.Index } })) {
            $col = $Grid.Columns[[string]$it.Name]
            if ($null -eq $col) { continue }
            if ($col.Index -ne 0) { $col.Visible = [bool]$it.Visible }
            if ([double]$it.Weight -gt 0) { $col.FillWeight = [float][double]$it.Weight }
            $col.DisplayIndex = [math]::Min([int]$it.Index, $Grid.Columns.Count - 1)
        }
    } catch { Write-WidgetLog "Grid layout $Key not restored: $($_.Exception.Message)" "WARN" }
    finally { $script:GridLayoutBusy = $false }
}

function Enable-GridCustomization {
    param([System.Windows.Forms.DataGridView]$Grid, [string]$Key)
    $script:GridDefaults[$Key] = @(ConvertTo-GridLayout @($Grid.Columns))
    $Grid.AllowUserToOrderColumns = $true
    $Grid.Tag = $Key
    Restore-GridLayout -Grid $Grid -Key $Key
    $script:GridLayoutSig[$Key] = (@(ConvertTo-GridLayout @($Grid.Columns)) | ForEach-Object { "{0}:{1}:{2:F1}:{3}" -f $_.Name, $_.Index, $_.Weight, $_.Visible }) -join "|"
    $Grid.Add_ColumnDisplayIndexChanged({ param($sender, $e) Save-GridLayout -Grid $sender -Key ([string]$sender.Tag) })
    $Grid.Add_ColumnWidthChanged({ param($sender, $e) Save-GridLayout -Grid $sender -Key ([string]$sender.Tag) })
    $Grid.Add_ColumnHeaderMouseClick({
        param($sender, $e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $menu.ShowCheckMargin = $true
        foreach ($col in @($sender.Columns | Sort-Object DisplayIndex)) {
            $mi = New-Object System.Windows.Forms.ToolStripMenuItem($(if ($col.HeaderText) { $col.HeaderText } else { $col.Name }))
            $mi.Checked = $col.Visible
            $mi.Enabled = ($col.Index -ne 0)
            $mi.Tag = @($sender, $col.Name)
            $mi.Add_Click({
                param($s2, $e2)
                $gr = $s2.Tag[0]; $cn = [string]$s2.Tag[1]
                $gr.Columns[$cn].Visible = -not $gr.Columns[$cn].Visible
                Save-GridLayout -Grid $gr -Key ([string]$gr.Tag)
            })
            [void]$menu.Items.Add($mi)
        }
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        $rs = New-Object System.Windows.Forms.ToolStripMenuItem("Standard wiederherstellen")
        $rs.Tag = $sender
        $rs.Add_Click({
            param($s2, $e2)
            Restore-GridLayout -Grid $s2.Tag -Key ([string]$s2.Tag.Tag) -Defaults
            Save-GridLayout -Grid $s2.Tag -Key ([string]$s2.Tag.Tag)
        })
        [void]$menu.Items.Add($rs)
        $menu.Show($sender, $sender.PointToClient([System.Windows.Forms.Cursor]::Position))
    })
}

# ---- global hotkey + click-through (Win32 via a small helper class) ----
$script:Hotkey = $null
$script:HotkeyTypeOk = $false
try {
    if (-not ("TwHotkeyWindow" -as [type])) {
        $refs = New-Object System.Collections.Generic.List[string]
        foreach ($t in @([System.Windows.Forms.NativeWindow], [System.Windows.Forms.Message], [System.Windows.Forms.CreateParams])) {
            $loc = $t.Assembly.Location
            if ($loc -and -not $refs.Contains($loc)) { $refs.Add($loc) }
        }
        Add-Type -ReferencedAssemblies $refs.ToArray() -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TwHotkeyWindow : System.Windows.Forms.NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int index, int value);
    public Action OnHotkey;
    bool registered;
    public TwHotkeyWindow() { CreateHandle(new System.Windows.Forms.CreateParams()); }
    public bool Register(uint mods, uint vk) { Unregister(); registered = RegisterHotKey(Handle, 0x7A11, mods | 0x4000, vk); return registered; }
    public void Unregister() { if (registered) { UnregisterHotKey(Handle, 0x7A11); registered = false; } }
    protected override void WndProc(ref System.Windows.Forms.Message m) {
        if (m.Msg == 0x0312 && OnHotkey != null) { try { OnHotkey(); } catch { } }
        base.WndProc(ref m);
    }
    public void Dispose() { Unregister(); DestroyHandle(); }
    public static void SetClickThrough(IntPtr hWnd, bool on) {
        int ex = GetWindowLong(hWnd, -20);
        if (on) { ex = ex | 0x80000 | 0x20; } else { ex = ex & ~0x20; }
        SetWindowLong(hWnd, -20, ex);
    }
}
"@
    }
    $script:HotkeyTypeOk = $true
} catch {
    Write-WidgetLog "Hotkey helper not available: $($_.Exception.Message)" "WARN"
}

function Invoke-HotkeyToggle {
    if ($script:IsClosing) { return }
    if ($script:ClickThrough) { Set-ClickThrough $false }
    if ($form.Visible -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized -and [System.Windows.Forms.Form]::ActiveForm -eq $form) {
        $form.Hide()
    } else {
        Show-MainWindow
        $form.Activate()
    }
}

function Register-GlobalHotkey {
    if (-not $script:HotkeyTypeOk) { return "nicht verfügbar" }
    try {
        if ($null -eq $script:Hotkey) {
            $script:Hotkey = New-Object TwHotkeyWindow
            $script:Hotkey.OnHotkey = [Action]{ Invoke-HotkeyToggle }
        }
        $script:Hotkey.Unregister()
        $hk = ConvertFrom-HotkeyText ([string]$script:Config.GlobalHotkey)
        if ($null -eq $hk) { return "aus" }
        if ($script:Hotkey.Register([uint32]$hk.Mods, [uint32]$hk.Key)) { Write-WidgetLog "Global hotkey: $($hk.Text)"; return "" }
        Write-WidgetLog "Global hotkey $($hk.Text) is used by another program" "WARN"
        return "$($hk.Text) ist schon von einem anderen Programm belegt"
    } catch {
        Write-WidgetLog "Global hotkey failed: $($_.Exception.Message)" "WARN"
        return "Fehler: $($_.Exception.Message)"
    }
}

$script:ClickThrough = $false
function Set-ClickThrough {
    param([bool]$On)
    if (-not $script:HotkeyTypeOk) { Set-TransientStatus "Durchklicken ist auf diesem System nicht verfügbar" 4; return }
    if ($On -and -not (ConvertFrom-HotkeyText ([string]$script:Config.GlobalHotkey))) {
        Show-InfoBox -Text "Zum Zurückholen wird das globale Tastenkürzel gebraucht (Einstellungen). Ohne Kürzel bleibt nur das Tray-Menü." -Title "Durchklicken"
    }
    $script:ClickThrough = $On
    try { [TwHotkeyWindow]::SetClickThrough($form.Handle, $On) } catch { Write-WidgetLog "Click-through failed: $($_.Exception.Message)" "WARN" }
    if ($On) {
        if (-not $form.TopMost) { $form.TopMost = $true }
        if ($form.Opacity -gt 0.85) { $form.Opacity = 0.85 }
    } else {
        $form.Opacity = [double]$script:Config.Opacity / 100.0
        $form.TopMost = [bool]$script:Config.TopMost
    }
    $miClickThrough.Checked = $On
    Write-WidgetLog "Click-through: $On"
}

# ---- undo for deletions (Ctrl+Z within 10 seconds) ----
$script:Undo = $null
function Set-Undo {
    param([string]$Kind, $Data, [string]$Text)
    $script:Undo = @{ Kind = $Kind; Data = $Data; Until = (Get-Date).AddSeconds(10) }
    $script:Redo = $null
    Set-TransientStatus ("{0} - Strg+Z = rückgängig" -f $Text) 10
}

$script:Redo = $null
function Invoke-Undo {
    $u = $script:Undo
    if (-not (Test-UndoValid -Undo $u)) { return $false }
    $script:Undo = $null
    # v4.9.5: remember the state before undoing, so Ctrl+Y can redo it
    $redoData = $null
    switch ($u.Kind) {
        "Alert" {
            $ix = [math]::Min([int]$u.Data.Index, $script:Alerts.Count)
            $script:Alerts.Insert($ix, $u.Data.Item)
            Save-Alerts
            $redoData = @{ Item = $u.Data.Item }
        }
        "Position" {
            $k = [string]$u.Data.Key
            $redoData = @{ Key = $k; Item = $(if ($script:Portfolio.ContainsKey($k)) { $script:Portfolio[$k] } else { $null }) }
            $script:Portfolio[$k] = $u.Data.Item
            Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
        }
        "Watchlist" {
            $redoData = @($script:Config.Watchlist)
            $script:Config.Watchlist = @($u.Data)
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
        }
    }
    $script:Redo = @{ Kind = $u.Kind; Data = $redoData; Undo = $u; Until = (Get-Date).AddSeconds(30) }
    Set-TransientStatus "Wiederhergestellt - Strg+Y = wiederholen" 4
    Refresh-AllMarketData
    Update-AllUiViews
    return $true
}

function Invoke-Redo {
    # v4.9.5: Ctrl+Y redoes the last undo (within 30 seconds); Ctrl+Z works again after it
    $r = $script:Redo
    if (-not (Test-UndoValid -Undo $r)) { return $false }
    $script:Redo = $null
    switch ($r.Kind) {
        "Alert" {
            # by reference: PSCustomObjects all compare equal in List.Remove
            for ($i = 0; $i -lt $script:Alerts.Count; $i++) {
                if ([object]::ReferenceEquals($script:Alerts[$i], $r.Data.Item)) { $script:Alerts.RemoveAt($i); break }
            }
            Save-Alerts
        }
        "Position" {
            $k = [string]$r.Data.Key
            if ($null -eq $r.Data.Item) { [void]$script:Portfolio.Remove($k) } else { $script:Portfolio[$k] = $r.Data.Item }
            Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
        }
        "Watchlist" {
            $script:Config.Watchlist = @($r.Data)
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
        }
    }
    $u = $r.Undo
    $u.Until = (Get-Date).AddSeconds(10)
    $script:Undo = $u
    Set-TransientStatus "Wiederholt - Strg+Z = rückgängig" 4
    Refresh-AllMarketData
    Update-AllUiViews
    return $true
}

# ---- v4.9.5: copy a list as a table (Ctrl+C) ----
function Copy-GridAsTable {
    param([System.Windows.Forms.DataGridView]$Grid)
    $cols = @($Grid.Columns | Where-Object { $_.Visible -and $_.Name -ne "Spark" } | Sort-Object DisplayIndex)
    if ($cols.Count -eq 0) { return $false }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Grid.Rows) {
        if ($Grid -eq $dgvNews -and $null -eq $r.Tag) { continue }   # the "loading" line
        $vals = @($cols | ForEach-Object { [string]$r.Cells[$_.Index].FormattedValue })
        $rows.Add($vals)
    }
    if ($rows.Count -eq 0) { return $false }
    $txt = ConvertTo-TsvTable -Headers @($cols | ForEach-Object { $_.HeaderText }) -Rows $rows.ToArray()
    try { [System.Windows.Forms.Clipboard]::SetText($txt) } catch { Set-TransientStatus "Zwischenablage nicht verfügbar" 3; return $true }
    Set-TransientStatus ("{0} Zeilen kopiert - in Excel oder eine Mail einfügen" -f $rows.Count) 4
    return $true
}

# ==============================================================================
# v5.0 Stage A: cash account + savings plans (dialogs and booking)
# ==============================================================================
function Show-CashDialog {
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Cash-Konto - $(Get-DepotName ([string]$script:Config.ActiveDepot))" -W (S 720) -H (S 470) -Key "Cash"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 600), (S 360))
    $dlg.KeyPreview = $true
    $dlg.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() } })
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.SetBounds((S 14), (S 12), (S 330), (S 22)); $chk.Text = "Cash-Konto für dieses Depot führen"
    $chk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $chk.ForeColor = $p.Text
    $chk.Checked = [bool]$script:Cash.Enabled
    $dlg.Controls.Add($chk)
    Set-DynTip $chk "Ab dem Einschalten verändern neue Käufe, Verkäufe und Dividenden den Kontostand. Ältere Buchungen zählen nicht - dafür fragt das Widget nach dem heutigen Kontostand."
    $lblCur = New-Object System.Windows.Forms.Label
    $lblCur.SetBounds((S 360), (S 15), (S 70), (S 18)); $lblCur.Text = "Währung:"
    $dlg.Controls.Add($lblCur)
    $cbCur = New-Object System.Windows.Forms.ComboBox
    $cbCur.SetBounds((S 432), (S 11), (S 70), (S 24))
    $cbCur.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbCur.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cbCur.BackColor = $p.Input; $cbCur.ForeColor = $p.Accent
    foreach ($c in (Get-DisplayCurrencies)) { [void]$cbCur.Items.Add($c) }
    Select-CurrencyInCombo -Combo $cbCur -Code ([string]$script:Cash.Currency)
    $dlg.Controls.Add($cbCur)

    $lblBal = New-Object System.Windows.Forms.Label
    $lblBal.SetBounds((S 14), (S 44), (S 690), (S 30)); $lblBal.Anchor = $aT -bor $aL -bor $aR
    $lblBal.Font = $fontPrice; $lblBal.ForeColor = $p.Text
    $dlg.Controls.Add($lblBal)

    $mk = {
        param([string]$T, [int]$X, [string]$Tip)
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds($X, (S 82), (S 104), (S 26))
        Style-FlatButton -Btn $b -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
        $b.Text = $T
        $dlg.Controls.Add($b)
        Set-DynTip $b $Tip
        return $b
    }
    $bIn  = & $mk "Einzahlung" (S 14) "Geld auf das Depotkonto einzahlen"
    $bOut = & $mk "Auszahlung" (S 122) "Geld vom Depotkonto abheben"
    $bInt = & $mk "Zinsen" (S 230) "Zinsen gutschreiben (netto)"
    $bFee = & $mk "Gebühr" (S 338) "Kontoführung, Depotgebühr ... abziehen"
    $bSet = & $mk "Stand setzen" (S 446) "Kontostand laut Bank eintragen - die Differenz wird als Korrektur gebucht"
    $bDel = & $mk "Eintrag löschen" (S 554) "Markierten Kassen-Eintrag löschen (Käufe / Verkäufe hier nicht - die in der Historie)"
    $bDel.Width = S 150

    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds((S 14), (S 118), (S 690), (S 300)); $g.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Style-DataGrid -Grid $g
    foreach ($cn in @("Datum", "Art", "Ticker", "Betrag", "Währung", "Notiz")) { [void]$g.Columns.Add($cn, $cn) }
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $g.Columns["Betrag"].DefaultCellStyle.Alignment = [System.Windows.Forms.DataGridViewContentAlignment]::MiddleRight
    $g.Columns["Notiz"].FillWeight = 160
    $dlg.Controls.Add($g)
    $lblInfo = New-Object System.Windows.Forms.Label
    $lblInfo.SetBounds((S 14), (S 424), (S 690), (S 36)); $lblInfo.Anchor = $aB -bor $aL -bor $aR
    $lblInfo.ForeColor = $p.Muted
    $lblInfo.Text = "Käufe ziehen Kurs x Stück + Gebühr ab, Verkäufe bringen Erlös - Gebühr, Dividenden Betrag - Steuer. Fremdwährungen zum aktuellen Kurs umgerechnet."
    $dlg.Controls.Add($lblInfo)

    $script:CashCtl = @{ Dlg = $dlg; Chk = $chk; Cur = $cbCur; Bal = $lblBal; Grid = $g; Buttons = @($bIn, $bOut, $bInt, $bFee, $bSet, $bDel) }
    $fill = {
        $cc = $script:CashCtl
        $on = [bool]$script:Cash.Enabled
        foreach ($b in $cc.Buttons) { $b.Enabled = $on }
        $cc.Cur.Enabled = $on
        $cc.Grid.Rows.Clear()
        $ci = Get-CashInfo
        if ($null -eq $ci) { $cc.Bal.Text = Tr "Aus - Haken setzen, um den Kontostand mitzuführen"; $cc.Bal.ForeColor = $script:Pal.Muted; return }
        $cc.Bal.Text = "{0}: {1:N2} {2}" -f (Tr "Kontostand"), $ci.Balance, $ci.Currency
        if (@($ci.Missing).Count -gt 0) { $cc.Bal.Text += "  (ohne " + (@($ci.Missing) -join ", ") + ")" }
        $cc.Bal.ForeColor = if ($ci.Balance -lt 0) { $colRed } else { $script:Pal.Text }
        foreach ($m in @($ci.Movements | Sort-Object -Property Date -Descending)) {
            $note = ""
            if ($m.Source -eq "Cash") { $en = @($script:Cash.Entries | Where-Object { $_.Id -eq $m.Id })[0]; if ($null -ne $en) { $note = [string]$en.Note } }
            $i = $cc.Grid.Rows.Add($m.Date, $m.Kind, $m.Ticker, ("{0:+#,##0.00;-#,##0.00;0.00}" -f $m.Amount), $m.Currency, $note)
            $cc.Grid.Rows[$i].Tag = $m
            $cc.Grid.Rows[$i].Cells["Betrag"].Style.ForeColor = if ($m.Amount -ge 0) { $colGreen } else { $colRed }
            if ($m.Source -eq "Trade") { $cc.Grid.Rows[$i].Cells["Art"].Style.ForeColor = $script:Pal.Muted }
        }
    }
    $script:CashCtl.Fill = $fill
    $askAmount = {
        param([string]$Title, [string]$Prompt)
        $t = Read-TextInput -Title $Title -Prompt $Prompt
        if ($null -eq $t) { return $null }
        $v = Parse-DecimalInput $t
        if ($v -le 0) { [System.Windows.Forms.MessageBox]::Show($script:CashCtl.Dlg, "Bitte einen Betrag größer 0 eingeben.", "Cash", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null; return $null }
        return $v
    }
    $script:CashCtl.Ask = $askAmount
    $chk.Add_Click({
        $cc = $script:CashCtl
        if ($cc.Chk.Checked -and -not [bool]$script:Cash.Enabled) {
            $cur = [string]$cc.Cur.SelectedItem
            $t = Read-TextInput -Title "Cash-Konto" -Prompt ("Aktueller Kontostand in {0} (vor neuen Buchungen):" -f $cur) -Value "0"
            if ($null -eq $t) { $cc.Chk.Checked = $false; return }
            $script:Cash.Enabled = $true
            $script:Cash.Currency = $cur
            # bookings that exist now are already in this balance
            $script:Cash.BaselineIds = @($script:Transactions | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
            $v = if ($script:SmokeMode) { 1000.0 } else { Parse-DecimalInput $t }
            if ($v -ne 0) { Add-CashEntry -Kind "Start" -Amount $v -Note (Tr "Kontostand beim Einschalten") } else { Save-CashData }
        } elseif (-not $cc.Chk.Checked -and [bool]$script:Cash.Enabled) {
            $script:Cash.Enabled = $false
            Save-CashData
        }
        & $cc.Fill
        Update-AllUiViews
    })
    $cbCur.Add_SelectionChangeCommitted({
        $cc = $script:CashCtl
        $script:Cash.Currency = [string]$cc.Cur.SelectedItem
        Save-CashData
        & $cc.Fill
    })
    $bIn.Add_Click({ $v = & $script:CashCtl.Ask "Einzahlung" ("Betrag in {0}:" -f $script:Cash.Currency); if ($null -ne $v) { Add-CashEntry -Kind "Einzahlung" -Amount $v; & $script:CashCtl.Fill; Update-AllUiViews } })
    $bOut.Add_Click({ $v = & $script:CashCtl.Ask "Auszahlung" ("Betrag in {0}:" -f $script:Cash.Currency); if ($null -ne $v) { Add-CashEntry -Kind "Auszahlung" -Amount (-$v); & $script:CashCtl.Fill; Update-AllUiViews } })
    $bInt.Add_Click({ $v = & $script:CashCtl.Ask "Zinsen" ("Zinsen (netto) in {0}:" -f $script:Cash.Currency); if ($null -ne $v) { Add-CashEntry -Kind "Zinsen" -Amount $v; & $script:CashCtl.Fill; Update-AllUiViews } })
    $bFee.Add_Click({ $v = & $script:CashCtl.Ask "Gebühr" ("Gebühr in {0}:" -f $script:Cash.Currency); if ($null -ne $v) { Add-CashEntry -Kind "Gebühr" -Amount (-$v); & $script:CashCtl.Fill; Update-AllUiViews } })
    $bSet.Add_Click({
        $ci = Get-CashInfo
        if ($null -eq $ci) { return }
        $t = Read-TextInput -Title "Kontostand setzen" -Prompt ("Kontostand laut Bank in {0}:" -f $ci.Currency) -Value ("{0:0.00}" -f $ci.Balance)
        if ($null -eq $t) { return }
        $diff = (Parse-DecimalInput $t) - $ci.Balance
        if ([math]::Abs($diff) -ge 0.005) { Add-CashEntry -Kind "Korrektur" -Amount $diff -Note ("{0} {1:N2}" -f (Tr "gesetzt auf"), (Parse-DecimalInput $t)) }
        & $script:CashCtl.Fill; Update-AllUiViews
    })
    $bDel.Add_Click({
        $cc = $script:CashCtl
        if ($cc.Grid.SelectedRows.Count -eq 0) { return }
        $m = $cc.Grid.SelectedRows[0].Tag
        if ($null -eq $m -or $m.Source -ne "Cash") { Set-TransientStatus "Käufe / Verkäufe / Dividenden bitte in der Transaktions-Historie löschen" 5; return }
        for ($i = 0; $i -lt $script:Cash.Entries.Count; $i++) { if ($script:Cash.Entries[$i].Id -eq $m.Id) { $script:Cash.Entries.RemoveAt($i); break } }
        Save-CashData
        & $cc.Fill; Update-AllUiViews
    })
    & $fill
    Apply-Language $dlg
    [void]$dlg.ShowDialog($form)
    $script:CashCtl = $null
    $dlg.Dispose()
}

function Show-SavingsPlansDialog {
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Sparpläne - $(Get-DepotName ([string]$script:Config.ActiveDepot))" -W (S 760) -H (S 420) -Key "Plans"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 640), (S 320))
    $dlg.KeyPreview = $true
    $dlg.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $sender.Close() } })
    $aT = [System.Windows.Forms.AnchorStyles]::Top; $aB = [System.Windows.Forms.AnchorStyles]::Bottom
    $aL = [System.Windows.Forms.AnchorStyles]::Left; $aR = [System.Windows.Forms.AnchorStyles]::Right
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.SetBounds((S 14), (S 10), (S 730), (S 36)); $lbl.Anchor = $aT -bor $aL -bor $aR; $lbl.ForeColor = $p.Muted
    $lbl.Text = "Jeden Monat am Stichtag wird ein Kauf zum Schlusskurs dieses Tages gebucht (am Wochenende: letzter Handelstag davor). Verpasste Monate werden beim nächsten Start nachgebucht. Dynamik = Betrag steigt jedes volle Jahr um x %, Pause = diese Monate auslassen (z. B. 7, 8)."
    $dlg.Controls.Add($lbl)
    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds((S 14), (S 50), (S 730), (S 280)); $g.Anchor = $aT -bor $aB -bor $aL -bor $aR
    Style-DataGrid -Grid $g
    $g.ReadOnly = $false
    foreach ($cn in @("Ticker", "Betrag", "Währung", "Gebühr", "Tag", "Start", "Dynamik %", "Pause", "Jetzt", "Zuletzt", "Aktiv")) {
        if ($cn -eq "Aktiv") { $col = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn; $col.Name = $cn; $col.HeaderText = $cn; [void]$g.Columns.Add($col) }
        else { [void]$g.Columns.Add($cn, $cn) }
    }
    $g.Columns["Zuletzt"].ReadOnly = $true
    $g.Columns["Jetzt"].ReadOnly = $true
    $g.Columns["Dynamik %"].ToolTipText = "Betrag steigt jedes volle Jahr ab Start um diesen Prozentsatz (0 = gleich bleibend)"
    $g.Columns["Pause"].ToolTipText = "Monate ohne Kauf, z. B. 7, 8 oder Jul, Aug (werden nicht nachgebucht)"
    $g.Columns["Jetzt"].ToolTipText = "Betrag des nächsten Kaufs mit Dynamik"
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $g.Columns["Ticker"].ToolTipText = "Yahoo-Symbol, z. B. EUNL.DE"
    $g.Columns["Tag"].ToolTipText = "Tag im Monat (1-28)"
    $g.Columns["Start"].ToolTipText = "Erster Monat, JJJJ-MM-TT"
    $dlg.Controls.Add($g)
    foreach ($pl in $script:SavingsPlans) {
        $nowAmt = Get-SavingsPlanAmount -Plan $pl -Date ((Get-Date).ToString("yyyy-MM-dd"))
        $i = $g.Rows.Add($pl.Ticker, ("{0:0.00}" -f $pl.Amount), $pl.Currency, ("{0:0.00}" -f $pl.Fee), $pl.Day, $pl.Start, ("{0:0.##}" -f [double]$pl.Increase), (Format-PauseMonths (ConvertTo-PauseMonths ([string]$pl.Pause))), ("{0:N2}" -f $nowAmt), $pl.LastBooked, [bool]$pl.Active)
        $g.Rows[$i].Tag = $pl.Id
    }
    $mk = {
        param([string]$T, [int]$X, $Anchor)
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds($X, (S 340), (S 130), (S 28)); $b.Anchor = $Anchor
        Style-FlatButton -Btn $b -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
        $b.Text = $T
        $dlg.Controls.Add($b)
        return $b
    }
    $bAdd = & $mk "+ Sparplan" (S 14) ($aB -bor $aL)
    $bDel = & $mk "Entfernen" (S 150) ($aB -bor $aL)
    $bRun = & $mk "Jetzt prüfen" (S 286) ($aB -bor $aL)
    $bOk  = & $mk "Speichern" (S 614) ($aB -bor $aR)
    Style-FlatButton -Btn $bOk -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $script:PlanCtl = @{ Dlg = $dlg; Grid = $g }
    $bAdd.Add_Click({
        $g = $script:PlanCtl.Grid
        $sym = ([string]$script:Config.ActiveTicker).ToUpper()
        $cur = if ($script:QuoteStore.ContainsKey($sym)) { [string]$script:QuoteStore[$sym].Currency } else { "EUR" }
        $nextM = (Get-Date).AddMonths(1)
        $i = $g.Rows.Add($sym, "100.00", $cur, "0.00", 1, (New-Object DateTime($nextM.Year, $nextM.Month, 1)).ToString("yyyy-MM-dd"), "0", "", "", "", $true)
        $g.Rows[$i].Tag = [Guid]::NewGuid().ToString("N")
        $g.CurrentCell = $g.Rows[$i].Cells["Ticker"]
    })
    $bDel.Add_Click({ $g = $script:PlanCtl.Grid; if ($g.SelectedRows.Count -gt 0) { $g.Rows.Remove($g.SelectedRows[0]) } elseif ($null -ne $g.CurrentRow) { $g.Rows.Remove($g.CurrentRow) } })
    $save = {
        $g = $script:PlanCtl.Grid
        [void]$g.EndEdit()
        $list = New-Object System.Collections.Generic.List[object]
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        foreach ($r in $g.Rows) {
            $sym = ([string]$r.Cells["Ticker"].Value).Trim().ToUpper()
            if (-not $sym) { continue }
            $st = ([string]$r.Cells["Start"].Value).Trim()
            $d = [DateTime]::MinValue
            if (-not [DateTime]::TryParseExact($st, "yyyy-MM-dd", $inv, [System.Globalization.DateTimeStyles]::None, [ref]$d)) { $st = (Get-Date).ToString("yyyy-MM-dd") }
            $cur = Get-NormalizedCurrencyCode ([string]$r.Cells["Währung"].Value)
            if (-not $cur) { $cur = "EUR" }
            $list.Add([PSCustomObject]@{
                Id = [string]$r.Tag; Ticker = $sym; Amount = (Parse-DecimalInput ([string]$r.Cells["Betrag"].Value)); Fee = (Parse-DecimalInput ([string]$r.Cells["Gebühr"].Value))
                Currency = $cur; Day = [math]::Max(1, [math]::Min(28, [int](Parse-DecimalInput ([string]$r.Cells["Tag"].Value)))); Start = $st
                LastBooked = [string]$r.Cells["Zuletzt"].Value; Active = [bool]$r.Cells["Aktiv"].Value
                Increase = [math]::Max(-50, [math]::Min(100, (Parse-DecimalInput ([string]$r.Cells["Dynamik %"].Value))))
                Pause = (Format-PauseMonths (ConvertTo-PauseMonths ([string]$r.Cells["Pause"].Value)))
            })
        }
        $script:SavingsPlans = $list
        Save-SavingsPlans
    }
    $script:PlanCtl.Save = $save
    $bOk.Add_Click({ & $script:PlanCtl.Save; $script:PlanCtl.Dlg.Close(); Invoke-SavingsPlans })
    $bRun.Add_Click({ & $script:PlanCtl.Save; Invoke-SavingsPlans; Set-TransientStatus "Sparpläne werden geprüft ..." 3 })
    Apply-Language $dlg
    [void]$dlg.ShowDialog($form)
    $script:PlanCtl = $null
    $dlg.Dispose()
}

$script:PlansRunning = $false
function Invoke-SavingsPlans {
    # Books the due months of every active plan at the close of the due day
    if ($script:IsClosing -or $script:PlansRunning -or $null -eq $script:SavingsPlans -or $script:SavingsPlans.Count -eq 0) { return }
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $due = @{}
    foreach ($pl in $script:SavingsPlans) {
        if (-not [bool]$pl.Active -or [double]$pl.Amount -le 0) { continue }
        $ds = @(Get-DueSavingsDates -Plan $pl -Today $today)
        if ($ds.Count -gt 0) { $due[$pl.Id] = $ds }
    }
    if ($due.Count -eq 0) { return }
    $urls = @{}
    foreach ($pl in @($script:SavingsPlans | Where-Object { $due.ContainsKey($_.Id) })) {
        $first = [DateTime]::ParseExact([string]$due[$pl.Id][0], "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
        $p1 = [DateTimeOffset]::new($first.AddDays(-10)).ToUnixTimeSeconds()
        $p2 = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $urls[$pl.Id] = "https://query1.finance.yahoo.com/v8/finance/chart/{0}?interval=1d&period1={1}&period2={2}" -f [Uri]::EscapeDataString($pl.Ticker), $p1, $p2
    }
    $script:PlansRunning = $true
    Start-FetchJob -Urls @($urls.Values) -MaxConcurrency 2 -Context @{ Urls = $urls; Due = $due } -OnComplete {
        param($Box, $Ctx)
        $script:PlansRunning = $false
        $booked = 0
        foreach ($id in @($Ctx.Urls.Keys)) {
            $pl = @($script:SavingsPlans | Where-Object { $_.Id -eq $id })[0]
            if ($null -eq $pl) { continue }
            $h = ConvertFrom-YahooDailyHistory -Json $Box.Results[$Ctx.Urls[$id]]
            if ($null -eq $h) { Write-WidgetLog "Savings plan $($pl.Ticker): no price history" "WARN"; continue }
            foreach ($d in @($Ctx.Due[$id])) {
                $c = Get-CloseOnOrBefore -Dates $h.Dates -Closes $h.Closes -Date $d
                if ($null -eq $c) { continue }
                # amount and fee in the plan currency, price in the instrument currency
                $px = Convert-CurrencyValue -Amount $c.Close -FromCurrency ([string]$h.Currency) -ToCurrency ([string]$pl.Currency)
                if ($px -le 0) { continue }
                $amt = Get-SavingsPlanAmount -Plan $pl -Date $d   # v5.5: yearly increase
                $sh = ($amt - [double]$pl.Fee) / $px
                if ($sh -le 0) { continue }
                $err = Invoke-Transaction -Type "Kauf" -Ticker $pl.Ticker -Shares $sh -Price $px -Fee ([double]$pl.Fee) -Currency ([string]$pl.Currency) -Date $d -Note ("Sparplan {0:N2} {1}" -f $amt, $pl.Currency)
                if ($err) { Write-WidgetLog "Savings plan $($pl.Ticker) $d : $err" "WARN"; break }
                $pl.LastBooked = $d
                $booked++
            }
        }
        if ($booked -gt 0) {
            Save-SavingsPlans
            Write-WidgetLog "Savings plans: $booked booking(s)"
            [void](Send-WidgetNotification -Title "Sparplan" -Message ("{0} Kauf/Käufe gebucht - siehe Transaktions-Historie" -f $booked) -Kind "Info" -AllowPush $false)
            Refresh-AllMarketData
            Update-AllUiViews
        }
    }
}

# ---- v4.9.5: privacy mode (F9) ----
function Set-PrivacyMode {
    param([bool]$On)
    $script:Config.PrivacyMode = $On
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    $script:LastTrayIconKey = ""
    Set-TransientStatus $(if ($On) { "Privat-Modus an: Beträge ausgeblendet (F9 = aus)" } else { "Privat-Modus aus" }) 4
    Update-PrivacyIndicator
    Update-AllUiViews
    if ($viewPortfolio.Visible) { Refresh-PortfolioGrid }
}

function Update-PrivacyIndicator {
    # eye = amounts shown (click hides), crossed eye = hidden; tray menu tick
    $on = [bool]$script:Config.PrivacyMode
    if ($script:IconFont) {
        $btnPrivacy.Text = if ($on) { [string][char]0xED1A } else { [string][char]0xE7B3 }
    } else {
        $btnPrivacy.Text = if ($on) { [string][char]0x2022 } else { "P" }
    }
    $btnPrivacy.ForeColor = if ($on) { $script:Pal.Accent } else { $script:Pal.Muted }
    Set-DynTip $btnPrivacy $(if ($on) { "Privat-Modus an: Beträge ausgeblendet. Klick oder F9 = wieder zeigen." } else { "Beträge ausblenden (Privat-Modus, F9 / Fn+F9), z. B. beim Bildschirm teilen" })
    $miPrivacy.Checked = $on
    $b = $tabButtons["Portfolio"]
    if ($null -eq $b) { return }
    $want = if ([bool]$script:Config.PrivacyMode) { "Portfolio " + [string][char]0x2022 + [string][char]0x2022 } else { "Portfolio (F2)" }
    if ($b.Text -ne (Tr $want)) { $b.Text = Tr $want }
}

# ---- price flash ----
$script:LastFlashPrice = @{}
# v4.9.5: the tint holds briefly, then fades back over ~0.6 s
$script:FlashCells = New-Object System.Collections.Generic.List[object]
$script:FlashTimer = New-Object System.Windows.Forms.Timer
$script:FlashTimer.Interval = 50
$script:FlashTimer.Add_Tick({
    $now = Get-Date
    for ($i = $script:FlashCells.Count - 1; $i -ge 0; $i--) {
        $f = $script:FlashCells[$i]
        $a = Get-FlashAlpha -ElapsedMs (($now - $f.Start).TotalMilliseconds) -HoldMs 300 -FadeMs 600 -Max 0.35
        try {
            if ($a -le 0) {
                $f.Cell.Style.BackColor = [System.Drawing.Color]::Empty
                $script:FlashCells.RemoveAt($i)
            } else {
                $f.Cell.Style.BackColor = Get-BlendColor -A $f.Color -B $script:Pal.Card -T $a
            }
        } catch { $script:FlashCells.RemoveAt($i) }
    }
    if ($script:FlashCells.Count -eq 0) { $script:FlashTimer.Stop() }
})

function Set-PriceFlash {
    # Tints the price cell when the price changed since the last refresh
    param($Cell, [string]$Key, [double]$Price)
    if (-not [bool]$script:Config.PriceFlash -or $Price -le 0) { return }
    $old = $script:LastFlashPrice[$Key]
    $script:LastFlashPrice[$Key] = $Price
    if ($null -eq $old -or [math]::Abs([double]$old - $Price) -lt 1e-9) { return }
    $c = if ($Price -gt [double]$old) { $script:colGreen } else { $script:colRed }
    $Cell.Style.BackColor = Get-BlendColor -A $c -B $script:Pal.Card -T 0.35
    $script:FlashCells.Add([PSCustomObject]@{ Cell = $Cell; Color = $c; Start = (Get-Date) })
    if (-not $script:FlashTimer.Enabled) { $script:FlashTimer.Start() }
}

# ---- own layouts ----
$script:LayoutKeys = @("Layout", "TerminalChartPct", "TerminalShowWatch", "TerminalShowPortfolio", "TerminalBottom", "Theme", "AccentColor", "AccentHex",
                       "UpDownScheme", "ChartType", "ShowVolume", "ShowSma", "ShowRsi", "ShowVwap", "ShowBollinger", "ShowExtended", "Timeframe", "LowerPanel", "MaType", "Opacity", "TopMost")

function Save-UserLayout {
    param([string]$Name)
    $snap = [ordered]@{ Name = $Name }
    foreach ($k in $script:LayoutKeys) { $snap[$k] = $script:Config.$k }
    $list = @(@($script:Config.UserLayouts) | Where-Object { $null -ne $_ -and ([string]$_.Name).ToUpper() -ne $Name.ToUpper() })
    $script:Config.UserLayouts = @($list) + @([PSCustomObject]$snap)
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Set-TransientStatus "Layout '$Name' gespeichert (LAYOUT $($Name.ToUpper()))" 4
}

function Use-UserLayout {
    param([string]$Name)
    $hit = @(@($script:Config.UserLayouts) | Where-Object { $null -ne $_ -and ([string]$_.Name).ToUpper() -eq $Name.ToUpper() })
    if ($hit.Count -eq 0) { return $false }
    $l = $hit[0]
    foreach ($k in $script:LayoutKeys) { if ($null -ne $l.PSObject.Properties[$k] -and $k -ne "Layout") { $script:Config.$k = $l.$k } }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-UpDownColors
    Apply-ThemeToAllControls
    $form.Opacity = [double]$script:Config.Opacity / 100.0
    $form.TopMost = [bool]$script:Config.TopMost
    Apply-Layout ([string]$l.Layout)
    Refresh-AllMarketData -Force
    Update-AllUiViews
    return $true
}

# ---- welcome tour ----
function Show-CompactOptions {
    # v4.8: which parts the Compact / Ticker bar shows (saved immediately)
    param($Owner = $null)
    $p = $script:Pal
    $opts = [ordered]@{ "DayAbs" = "Tagesänderung absolut"; "Ext" = "Vor- / Nachbörse"; "Spark" = "Mini-Chart"; "Market" = "Marktstatus (nur Compact)"; "Depot" = "Depot heute statt Marktstatus (nur Compact)" }
    $cur = @(([string]$script:Config.CompactShow) -split ',' | ForEach-Object { $_.Trim() })
    $dlg = New-DialogForm -Title "Compact / Ticker zeigt" -W (S 360) -H (S 240)
    $y = S 14
    $boxes = @{}
    foreach ($k in $opts.Keys) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.SetBounds((S 16), $y, (S 330), (S 24)); $c.Text = $opts[$k]; $c.Checked = ($cur -contains $k)
        $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $dlg.Controls.Add($c)
        $boxes[$k] = $c
        $y += S 28
    }
    $ok = New-Object System.Windows.Forms.Button
    $ok.SetBounds((S 252), ($y + (S 8)), (S 94), (S 28)); $ok.Text = "OK"
    Style-FlatButton -Btn $ok -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($ok)
    $dlg.AcceptButton = $ok
    $dlg.ClientSize = New-Object System.Drawing.Size((S 360), ($y + (S 50)))
    $res = $dlg.ShowDialog($(if ($null -ne $Owner) { $Owner } else { $form }))
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:Config.CompactShow = (@($opts.Keys | Where-Object { $boxes[$_].Checked }) -join ",")
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        if ([bool]$script:Config.CompactMode) { Apply-Layout ([string]$script:Config.Layout) }
    }
    $dlg.Dispose()
}

function Show-WelcomeTour {
    $pages = @(
        @("Willkommen beim TerminalWidget", "Vom kleinen Ticker bis zum Terminal: mit L (oder dem Layout-Button oben rechts) wechselst du zwischen Ticker, Compact, Standard und Terminal.`r`n`r`nMaus über ein Element halten zeigt eine Erklärung. G öffnet das Glossar, H alle Tastenkürzel."),
        @("Neu in V7: Aussehen und Bedienung", "Statusleiste unten (Stand der Daten, Börsenstatus), kurze Meldungen im Fenster und Schalter statt Häkchen in den Einstellungen. Watchlist-Gruppen sind Chips: Ticker darauf ziehen sortiert ein, Rechtsklick löscht. In der Analyse zeigen Kacheln die wichtigsten Zahlen; ein Klick auf eine Chart-Legende (BB20, SMA, VWAP) blendet den Indikator aus. Tagesveränderung als Pille und Animationen schaltest du unter Einstellungen > Design. LAYOUT FOCUS zeigt Chart und Watchlist ohne Portfolio.")
        @("Ticker und Watchlist", "Strg+F sucht einen Ticker (Name, Symbol oder ISIN). In der Watchlist: ziehen = Reihenfolge, Entf = löschen (Strg+Z holt ihn zurück), Rechtsklick auf eine Spaltenüberschrift = Spalten ein-/ausblenden, Überschriften ziehen = umsortieren."),
        @("Portfolio", "Positionen im Portfolio-Tab anlegen - beim Speichern wird nach dem Kaufdatum gefragt. Buchungen vom Broker: Historie > Import (CSV). Mehrere Depots: Auswahl oben im Portfolio-Tab. P öffnet die Analyse mit Wertentwicklung, Rendite, Aufteilung und Dividenden."),
        @("Alarme und Handy", "Alarme im Watch-Tab oder per Rechtsklick in den Chart: Kurs, Tag%, Trailing-Stopp, 52W-Hoch, Volumen, Depotwert ... Einstellungen > Handy-Push schickt sie per ntfy oder Telegram aufs Handy, mit Ruhezeit für die Nacht."),
        @("Befehlszeile", "Strg+K öffnet die Befehlszeile wie im Terminal:`r`n  NVDA GP 1Y   Chart     NVDA DES   Beschreibung`r`n  NVDA N   Nachrichten   CAL   Termine   TOP   Gewinner/Verlierer`r`n  NVDA ALRT TRAIL 8   Alarm`r`n`r`nStrg+Alt+W holt das Widget von überall nach vorne (einstellbar).")
    )
    $p = $script:Pal
    $dlg = New-DialogForm -Title "Kurze Tour" -W (S 520) -H (S 300)
    $t = New-Object System.Windows.Forms.Label
    $t.SetBounds((S 20), (S 16), (S 480), (S 28)); $t.Font = $fontUiBold; $t.ForeColor = $p.Accent
    $dlg.Controls.Add($t)
    $b = New-Object System.Windows.Forms.Label
    $b.SetBounds((S 20), (S 52), (S 480), (S 180)); $b.Font = $fontUi
    $dlg.Controls.Add($b)
    $n = New-Object System.Windows.Forms.Label
    $n.SetBounds((S 20), (S 254), (S 120), (S 20)); $n.ForeColor = $p.Muted
    $dlg.Controls.Add($n)
    $next = New-Object System.Windows.Forms.Button
    $next.SetBounds((S 406), (S 248), (S 96), (S 30))
    Style-FlatButton -Btn $next -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $dlg.Controls.Add($next)
    $skip = New-Object System.Windows.Forms.Button
    $skip.SetBounds((S 302), (S 248), (S 96), (S 30)); $skip.Text = "Überspringen"
    Style-FlatButton -Btn $skip -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $skip.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($skip)
    $dlg.CancelButton = $skip
    $script:TourCtl = @{ Dlg = $dlg; T = $t; B = $b; N = $n; Next = $next; Pages = $pages; I = 0 }
    $script:TourCtl.Show = {
        $tc = $script:TourCtl
        $pg = $tc.Pages[$tc.I]
        $tc.T.Text = $pg[0]; $tc.B.Text = $pg[1]
        $tc.N.Text = "{0} / {1}" -f ($tc.I + 1), $tc.Pages.Count
        $tc.Next.Text = if ($tc.I -ge $tc.Pages.Count - 1) { "Los geht's" } else { "Weiter" }
    }
    $next.Add_Click({
        $tc = $script:TourCtl
        if ($tc.I -ge $tc.Pages.Count - 1) { $tc.Dlg.Close(); return }
        $tc.I++
        & $tc.Show
    })
    & $script:TourCtl.Show
    [void]$dlg.ShowDialog($form)
    $script:TourCtl = $null
    $dlg.Dispose()
    $script:Config.FirstRunDone = $true
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
}

function Show-CurrencyMismatchNotice {
    # v3.0: positions whose currency contradicts their own bookings were most
    # likely hit by the v2.9 load bug (non EUR/USD/CHF -> EUR, amount kept).
    # Nothing is changed automatically; the notice repeats only if the list changes.
    $mm = @(Find-PositionCurrencyMismatch -Portfolio $script:Portfolio -Transactions $script:Transactions.ToArray())
    if ($mm.Count -eq 0) { return }
    foreach ($m in $mm) { Write-WidgetLog ("Currency mismatch: {0} position in {1}, bookings in {2}" -f $m.Ticker, $m.PositionCurrency, $m.TransactionCurrencies) "WARN" }
    $key = (@($mm | ForEach-Object { "{0}:{1}>{2}" -f $_.Ticker, $_.TransactionCurrencies, $_.PositionCurrency }) -join "|")
    if ($key -eq [string]$script:Config.CurrencyNoticeKey) { return }
    $script:Config.CurrencyNoticeKey = $key
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    $lines = @($mm | ForEach-Object { "  {0}: Position in {1}, Buchungen in {2}" -f $_.Ticker, $_.PositionCurrency, $_.TransactionCurrencies }) -join "`r`n"
    $txt = "Bei diesen Positionen passt die Währung nicht zu den eigenen Buchungen:`r`n`r`n$lines`r`n`r`n" +
           "Wahrscheinliche Ursache: v2.9 hat beim Laden jede Währung außer EUR/USD/CHF auf EUR gesetzt (der EK-Betrag blieb gleich, nur die Währung wurde falsch).`r`n`r`n" +
           "Korrektur: Portfolio > 'Historie...' > Ticker markieren > 'Position neu berechnen' - oder im Portfolio-Editor die richtige Währung wählen und speichern.`r`n`r`n" +
           "Dieser Hinweis erscheint erst wieder, wenn sich die Liste ändert."
    [System.Windows.Forms.MessageBox]::Show($form, $txt, "Daten prüfen - $($script:AppTitle)",
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
}

# ------------------------------------------------------------------------------
# Autostart (v2.9): shortcut in the user's Startup folder
# ------------------------------------------------------------------------------
function Get-AutostartDir {
    # v3.0.1: GetFolderPath("Startup") returns "" on some Windows Server / RDS
    # profiles; Join-Path "" then threw and crashed the settings dialog.
    # Fallback: the standard per-user Startup folder; "" if even that is unknown.
    $dir = [Environment]::GetFolderPath("Startup")
    if ([string]::IsNullOrWhiteSpace($dir) -and $env:APPDATA) {
        $dir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
    }
    if ([string]::IsNullOrWhiteSpace($dir)) { return "" }
    return $dir
}

