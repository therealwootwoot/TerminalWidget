# TerminalWidget UI part 11 (System) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

function Get-AutostartPath {
    $dir = Get-AutostartDir
    if (-not $dir) { return "" }
    return (Join-Path $dir "Terminal Widget.lnk")
}

function Update-OldAutostart {
    # v4.0: the v3 shortcut ("Financial Widget.lnk") starts nvidia_widget.ps1.
    # Replace it with a shortcut to this script (only when this runs from a file).
    $dir = Get-AutostartDir
    if (-not $dir) { return }
    $old = Join-Path $dir "Financial Widget.lnk"
    if (-not (Test-Path -LiteralPath $old) -or [string]::IsNullOrEmpty($script:MainScriptPath)) { return }
    try {
        $sh = New-Object -ComObject WScript.Shell
        try { $args0 = [string]$sh.CreateShortcut($old).Arguments } finally { [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) }
        if ($args0 -notlike "*nvidia_widget*") { return }
        $err = Set-Autostart -Enable $true
        if ($err) { Write-WidgetLog "Autostart migration failed: $err" "WARN"; return }
        Remove-Item -LiteralPath $old -Force
        $script:Config.Autostart = $true
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        Write-WidgetLog "Autostart shortcut of v3 replaced by '$(Get-AutostartPath)'"
    } catch {
        Write-WidgetLog "Autostart migration failed: $($_.Exception.Message)" "WARN"
    }
}

function Test-Autostart {
    $lnk = Get-AutostartPath
    if (-not $lnk) { return $false }
    return (Test-Path -LiteralPath $lnk)
}

function Set-Autostart {
    # Returns "" on success, otherwise an error text
    param([bool]$Enable)
    $lnk = Get-AutostartPath
    if (-not $lnk) { return "Autostart-Ordner ist auf diesem System nicht verfügbar." }
    try {
        # the fallback folder may not exist yet on a fresh server profile
        $lnkDir = Split-Path -Parent $lnk
        if ($Enable -and -not (Test-Path -LiteralPath $lnkDir)) { New-Item -ItemType Directory -Path $lnkDir -Force | Out-Null }
        if (-not $Enable) {
            if (Test-Path $lnk) { Remove-Item -Path $lnk -Force }
            return ""
        }
        $scriptPath = $script:MainScriptPath
        if ([string]::IsNullOrEmpty($scriptPath)) { return "Skriptpfad unbekannt (aus einer Datei starten, nicht aus dem Editor)." }
        # same host as now (powershell.exe / pwsh.exe); from the ISE: powershell.exe
        $exe = (Get-Process -Id $PID).Path
        if ([string]::IsNullOrEmpty($exe) -or $exe -like "*powershell_ise*") { $exe = Join-Path $PSHOME "powershell.exe" }
        $sh = New-Object -ComObject WScript.Shell
        try {
            $sc = $sh.CreateShortcut($lnk)
            $sc.TargetPath = $exe
            $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
            $sc.WorkingDirectory = Split-Path -Parent $scriptPath
            $sc.WindowStyle = 7
            $sc.Description = "Terminal Widget"
            $sc.Save()
        } finally {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh)
        }
        Write-WidgetLog "Autostart shortcut created: $lnk"
        return ""
    } catch {
        Write-WidgetLog "Autostart change failed: $($_.Exception.Message)" "ERROR"
        return $_.Exception.Message
    }
}

# ------------------------------------------------------------------------------
# Settings dialog (v2.8): everything that used to be config.json-only
# ------------------------------------------------------------------------------
# ---- v5.3: settings window with pages ----
function Get-SettingCtlValue {
    param($Ctl)
    if ($Ctl -is [System.Windows.Forms.NumericUpDown]) { return [double]$Ctl.Value }
    if ($Ctl -is [System.Windows.Forms.CheckBox]) { return [bool]$Ctl.Checked }
    if ($Ctl -is [System.Windows.Forms.ComboBox]) { return [string]$Ctl.SelectedItem }
    return ([string]$Ctl.Text).Trim()
}

function Set-SettingCtlValue {
    param($Ctl, $Value)
    if ($null -eq $Ctl -or $null -eq $Value) { return }
    if ($Ctl -is [System.Windows.Forms.NumericUpDown]) {
        $v = [decimal][double]$Value
        $Ctl.Value = [math]::Max($Ctl.Minimum, [math]::Min($Ctl.Maximum, $v))
    } elseif ($Ctl -is [System.Windows.Forms.CheckBox]) {
        $Ctl.Checked = [bool]$Value
    } elseif ($Ctl -is [System.Windows.Forms.ComboBox]) {
        $ix = $Ctl.Items.IndexOf([string]$Value)
        if ($ix -ge 0) { $Ctl.SelectedIndex = $ix }
    } else {
        $Ctl.Text = [string]$Value
    }
}

function Update-SettingsMarkers {
    # dot in front of every setting that differs from the default
    $sc = $script:SettingsCtl
    if ($null -eq $sc) { return }
    foreach ($e in $sc.Reg) {
        if ($null -eq $e.Marker -or $e.Ctl.IsDisposed) { continue }
        $chg = Test-SettingChanged -Value (Get-SettingCtlValue $e.Ctl) -Default $e.Default
        # (Visible reads false on hidden pages, so the state is kept separately)
        $e.Changed = $chg
        $e.Marker.Visible = $chg
    }
    $sc.Nav.Invalidate()
}

function Show-SettingsPage {
    param([string]$Id)
    $sc = $script:SettingsCtl
    if ($null -eq $sc -or -not $sc.Pages.ContainsKey($Id)) { return }
    $sc.Cur = $Id
    foreach ($k in @($sc.Pages.Keys)) { $sc.Pages[$k].Visible = ($k -eq $Id) }
    $ix = [array]::IndexOf([string[]]$sc.PageIds, $Id)
    if ($ix -ge 0 -and $sc.Nav.SelectedIndex -ne $ix) { $sc.Nav.SelectedIndex = $ix }
    $sc.Nav.Invalidate()
}

function Update-SettingsSearch {
    # hits light up, the rest fades; the list on the left counts hits per page
    $sc = $script:SettingsCtl
    if ($null -eq $sc) { return }
    $q = [string]$sc.Search.Text
    $hits = Find-SettingsHits -Entries $sc.Reg -Query $q
    $sc.Hits = $hits
    $set = New-Object System.Collections.Generic.HashSet[int]
    foreach ($i in @($hits.Entries)) { [void]$set.Add([int]$i) }
    $first = @{}
    for ($i = 0; $i -lt $sc.Reg.Count; $i++) {
        $e = $sc.Reg[$i]
        $tgt = if ($null -ne $e.Lbl) { $e.Lbl } else { $e.Ctl }
        if ($null -eq $tgt -or $tgt.IsDisposed) { continue }
        if (-not $q.Trim()) { $tgt.ForeColor = $e.Orig; continue }
        if ($set.Contains($i)) {
            $tgt.ForeColor = $script:Pal.Accent
            if (-not $first.ContainsKey($e.Page)) { $first[$e.Page] = $tgt }
        } else { $tgt.ForeColor = $script:Pal.Border }
    }
    $script:SettingsSearchHits = @($hits.Entries).Count
    if ($q.Trim()) {
        $pg = Select-SettingsPage -Current $sc.Cur -Hits $hits
        Show-SettingsPage $pg
        if ($first.ContainsKey($pg) -and $first[$pg].Visible) { try { $sc.Pages[$pg].ScrollControlIntoView($first[$pg]) } catch { } }
    }
    $sc.Nav.Invalidate()
}

function Invoke-SettingsPreview {
    # live preview of style / theme / accent / rows in the main window;
    # Cancel puts the saved values back
    $sc = $script:SettingsCtl
    if ($null -eq $sc -or $sc.Building) { return }
    $cfg = $script:Config
    $cfg.UiStyle    = if ([string]$sc.Style.SelectedItem -like "Fresh*") { "Fresh" } else { "Refined" }
    $cfg.Theme      = [string]$sc.Theme.SelectedItem
    $acc = [string]$sc.Accent.SelectedItem
    if ($acc -ne "Eigene" -or $script:NewColors.Accent) { $cfg.AccentColor = $acc; $cfg.AccentHex = [string]$script:NewColors.Accent }
    $cfg.RowDensity = switch ([string]$sc.Rows.SelectedItem) { "Kompakt" { "Compact" } "Bequem" { "Comfortable" } default { "Normal" } }
    $cfg.ZebraRows  = [bool]$sc.Zebra.Checked
    try { Apply-ThemeToAllControls } catch { Write-WidgetLog "Settings preview: $($_.Exception.Message)" "WARN" }
    $pvp = $script:SettingsPreviewPanel
    if ($null -ne $pvp -and -not $pvp.IsDisposed) { $pvp.Invalidate() }
}

function Draw-SettingsPreview {
    # V7.1: a small sample (card, price, pill, button, toggle) in the current style / theme / accent
    param([System.Drawing.Graphics]$g, [int]$W, [int]$H)
    $p = $script:Pal; $sp = $script:UiSpec
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear($p.BodyBg)
    $rr = [float][math]::Max(2, [int]$sp.BtnRadius)
    $bp = New-Object System.Drawing.Pen($p.Border, [float]1)
    $outline = New-RoundedPath (New-Object System.Drawing.RectangleF(0.5, 0.5, [float]($W - 1), [float]($H - 1))) ([float](S 8))
    $g.DrawPath($bp, $outline); $outline.Dispose()
    # card
    $card = New-Object System.Drawing.RectangleF([float](S 10), [float](S 10), [float](S 200), [float]($H - (S 20)))
    $cp = New-RoundedPath $card $rr
    $cb = New-Object System.Drawing.SolidBrush($p.Card); $g.FillPath($cb, $cp); $g.DrawPath($bp, $cp); $cb.Dispose(); $cp.Dispose()
    $ba = New-Object System.Drawing.SolidBrush($p.Accent); $bt = New-Object System.Drawing.SolidBrush($p.Text); $bm = New-Object System.Drawing.SolidBrush($p.Muted)
    $g.DrawString("NVDA", $fontTicker, $ba, [float]($card.X + (S 10)), [float]($card.Y + (S 6)))
    $g.DrawString("123,45 EUR", $fontUiBold, $bt, [float]($card.X + (S 10)), [float]($card.Y + (S 26)))
    $upC = $colGreen
    if ([bool]$sp.Fresh) {
        $pill = New-Object System.Drawing.RectangleF([float]($card.X + (S 110)), [float]($card.Y + (S 26)), [float](S 74), [float](S 18))
        $pp = New-RoundedPath $pill ([float](S 9))
        $pb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(48, $upC.R, $upC.G, $upC.B)); $g.FillPath($pb, $pp); $pb.Dispose(); $pp.Dispose()
    }
    $ub = New-Object System.Drawing.SolidBrush($upC)
    $g.DrawString("+1,2 %", $fontUi, $ub, [float]($card.X + (S 120)), [float]($card.Y + (S 27)))
    $g.DrawString("Beispiel", $fontUi, $bm, [float]($card.X + (S 10)), [float]($card.Y + (S 46)))
    $ub.Dispose()
    # button
    $btn = New-Object System.Drawing.RectangleF([float](S 230), [float](S 14), [float](S 96), [float](S 28))
    $bpth = New-RoundedPath $btn $rr
    $g.FillPath($ba, $bpth); $bpth.Dispose()
    $ob = New-Object System.Drawing.SolidBrush($p.OnAccent)
    $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = [System.Drawing.StringAlignment]::Center; $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString("Aktion", $fontUi, $ob, $btn, $sf); $ob.Dispose()
    # secondary button
    $btn2 = New-Object System.Drawing.RectangleF([float](S 230), [float](S 48), [float](S 96), [float](S 28))
    $b2 = New-RoundedPath $btn2 $rr
    $ib = New-Object System.Drawing.SolidBrush($p.Input); $g.FillPath($ib, $b2); $g.DrawPath($bp, $b2); $ib.Dispose(); $b2.Dispose()
    $g.DrawString("Zweitaktion", $fontUi, $bt, $btn2, $sf); $sf.Dispose()
    # toggle (on)
    $tr = New-Object System.Drawing.RectangleF([float](S 344), [float](S 16), [float](S 36), [float](S 20))
    $tp = New-RoundedPath $tr ([float](S 10)); $g.FillPath($ba, $tp); $tp.Dispose()
    $kb = New-Object System.Drawing.SolidBrush($p.Text); $g.FillEllipse($kb, [float]($tr.Right - (S 17)), [float]($tr.Y + (S 3)), [float](S 14), [float](S 14)); $kb.Dispose()
    $g.DrawString("An", $fontUi, $bt, [float](S 386), [float]($tr.Y + (S 1)))
    # toggle (off)
    $tr2 = New-Object System.Drawing.RectangleF([float](S 344), [float](S 46), [float](S 36), [float](S 20))
    $tp2 = New-RoundedPath $tr2 ([float](S 10)); $ob2 = New-Object System.Drawing.SolidBrush($p.Border); $g.FillPath($ob2, $tp2); $ob2.Dispose(); $tp2.Dispose()
    $kb2 = New-Object System.Drawing.SolidBrush($p.Text); $g.FillEllipse($kb2, [float]($tr2.X + (S 3)), [float]($tr2.Y + (S 3)), [float](S 14), [float](S 14)); $kb2.Dispose()
    $g.DrawString("Aus", $fontUi, $bm, [float](S 386), [float]($tr2.Y + (S 1)))
    $ba.Dispose(); $bt.Dispose(); $bm.Dispose(); $bp.Dispose()
}

function Get-SettingsPaletteEntries {
    # Ctrl+K: every setting as "SET <label>" (built once from the real window)
    if ($null -ne $script:SettingsIndexCache) { return $script:SettingsIndexCache }
    if ($null -ne $script:SettingsCtl) { return @() }
    $list = @()
    try { $list = @(Show-SettingsDialog -IndexOnly) } catch { Write-WidgetLog "Settings index: $($_.Exception.Message)" "WARN" }
    $script:SettingsIndexCache = $list
    return $list
}

function Show-SettingsDialog {
    # v5.3: one page per topic (list on the left), the style at the top of the
    # Design page, search across all pages, "changed" markers, reset per page,
    # live preview of the look, size and last page remembered
    param([string]$Search = "", [string]$Page = "", [switch]$IndexOnly)
    if ($null -ne $script:SettingsCtl) { return }
    $p   = $script:Pal
    $cfg = $script:Config
    $dc  = $script:ConfigDefaults
    $lang = if ([string]$cfg.Language -eq "EN") { "EN" } else { "DE" }
    $pages = @(Get-SettingsPages)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Einstellungen - $($script:AppTitle)"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowIcon = $false
    $dlg.ShowInTaskbar = $false
    $dlg.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $dlg.BackColor = $p.BodyBg
    $dlg.ForeColor = $p.Text
    $dlg.Font = $fontUi
    $dlg.TopMost = $form.TopMost
    $dlg.KeyPreview = $true
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 640), (S 400))
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $cw = if ([int]$cfg.SettingsW -gt 0) { [int]$cfg.SettingsW } else { S 780 }
    $ch = if ([int]$cfg.SettingsH -gt 0) { [int]$cfg.SettingsH } else { S 560 }
    $dlg.ClientSize = New-Object System.Drawing.Size([math]::Min($cw, $wa.Width - (S 24)), [math]::Min($ch, $wa.Height - (S 48)))
    $dlg.Add_HandleCreated($script:DialogChromeHandler)

    # ---- frame: content (fill), page list (left), button bar (bottom) ----
    $host0 = New-Object System.Windows.Forms.Panel
    $host0.Dock = [System.Windows.Forms.DockStyle]::Fill
    $host0.BackColor = $p.BodyBg
    $dlg.Controls.Add($host0)
    $nav = New-Object System.Windows.Forms.ListBox
    $nav.Dock = [System.Windows.Forms.DockStyle]::Left
    $nav.Width = S 244
    $nav.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $nav.BackColor = $p.Card
    $nav.ForeColor = $p.Text
    $nav.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
    $nav.ItemHeight = S 32
    $nav.IntegralHeight = $false
    $nav.Font = $fontUi
    $dlg.Controls.Add($nav)
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $bar.Height = S 50
    $bar.BackColor = $p.Card
    $dlg.Controls.Add($bar)
    $barLine = New-Object System.Windows.Forms.Label
    $barLine.Dock = [System.Windows.Forms.DockStyle]::Top
    $barLine.Height = 1
    $barLine.BackColor = $p.Border
    $bar.Controls.Add($barLine)

    $reg = New-Object System.Collections.Generic.List[object]
    $pagePanels = @{}
    $lay = @{ Y = 0; Host = $null; Page = "" }
    $X0 = S 24; $LW = S 266; $IX = S 300; $IW = S 196

    $beginPage = {
        param([string]$Id)
        $pp = New-Object System.Windows.Forms.Panel
        $pp.Dock = [System.Windows.Forms.DockStyle]::Fill
        $pp.AutoScroll = $true
        $pp.Visible = $false
        $pp.BackColor = $p.BodyBg
        $host0.Controls.Add($pp)
        $pagePanels[$Id] = $pp
        $t = New-Object System.Windows.Forms.Label
        $t.Location = New-Object System.Drawing.Point($X0, (S 14))
        $t.AutoSize = $true
        $t.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
        $t.ForeColor = $p.Text
        $t.Text = Get-SettingsPageTitle -Id $Id -Language $lang
        $pp.Controls.Add($t)
        $lay.Host = $pp; $lay.Page = $Id; $lay.Y = S 52
    }
    $register = {
        # Search: label (German + English), tooltip, items, extra words
        param($Ctl, $Lbl, [string]$Key = "", $Default = $null, [string]$Words = "")
        $txt = if ($null -ne $Lbl) { [string]$Lbl.Text } else { [string]$Ctl.Text }
        $items = if ($Ctl -is [System.Windows.Forms.ComboBox]) { (@($Ctl.Items) -join " ") } else { "" }
        $tgt = if ($null -ne $Lbl) { $Lbl } else { $Ctl }
        $mk = $null
        if ($null -ne $Default) {
            $mk = New-Object System.Windows.Forms.Label
            $mk.SetBounds((S 8), ($tgt.Top + (S 2)), (S 14), (S 18))
            $mk.Text = [string][char]0x25CF
            $mk.ForeColor = $p.Accent
            $mk.Visible = $false
            $lay.Host.Controls.Add($mk)
            $dShow = $Default
            if ($Default -is [bool]) { $dShow = if ($Default) { "an" } else { "aus" } }
            Set-DynTip $mk ("Geändert - Standard: {0}" -f $dShow)
            if ($Ctl -is [System.Windows.Forms.NumericUpDown]) { $Ctl.Add_ValueChanged({ Update-SettingsMarkers }) }
            elseif ($Ctl -is [System.Windows.Forms.CheckBox]) { $Ctl.Add_CheckedChanged({ Update-SettingsMarkers }) }
            elseif ($Ctl -is [System.Windows.Forms.ComboBox]) { $Ctl.Add_SelectedIndexChanged({ Update-SettingsMarkers }) }
            else { $Ctl.Add_TextChanged({ Update-SettingsMarkers }) }
        }
        $reg.Add([PSCustomObject]@{
            Ctl = $Ctl; Lbl = $Lbl; Page = $lay.Page; Key = $Key; Default = $Default; Marker = $mk; Changed = $false; Orig = $tgt.ForeColor
            Label = $txt; Search = ("{0} {1} {2} {3} {4}" -f $txt, (Tr $txt), $script:SetTipText, $items, $Words)
            Strong = ("{0} {1} {2} {3}" -f $txt, (Tr $txt), $items, $Words)
        })
        $script:SetTipText = ""
    }
    $addSection = {
        param([string]$Text)
        $l = New-Object System.Windows.Forms.Label
        $l.Location = New-Object System.Drawing.Point($X0, ($lay.Y + (S 8)))
        $l.Size = New-Object System.Drawing.Size((S 460), (S 18))
        $l.Font = $fontUiBold
        $l.ForeColor = $p.Accent
        $l.Text = $Text
        $lay.Host.Controls.Add($l)
        $lay.Y += S 32
    }
    $mkLabel = {
        param([string]$Text, [string]$Tip, [string]$TipKey)
        $l = New-Object System.Windows.Forms.Label
        $l.Location = New-Object System.Drawing.Point($X0, ($lay.Y + (S 3)))
        $l.Size = New-Object System.Drawing.Size($LW, (S 18))
        $l.Text = $Text
        $lay.Host.Controls.Add($l)
        if ($Tip -or $TipKey) { Set-DynTip $l $Tip $TipKey }
        $script:SetTipText = $Tip
        return $l
    }
    $addNum = {
        param([string]$Label, [double]$Min, [double]$Max, [double]$Value, [string]$Tip = "", [string]$TipKey = "", [double]$Step = 1, [string]$Key = "", $Default = $null, [int]$Decimals = 0, [string]$Words = "", [switch]$Slider)
        $l = & $mkLabel $Label $Tip $TipKey
        $n = New-Object System.Windows.Forms.NumericUpDown
        $n.Location = New-Object System.Drawing.Point($IX, $lay.Y)
        $n.Size = New-Object System.Drawing.Size((S 112), (S 22))
        $n.DecimalPlaces = $Decimals
        $n.Minimum = [decimal]$Min
        $n.Maximum = [decimal]$Max
        $n.Increment = [decimal]([math]::Max([math]::Pow(10, -$Decimals), $Step))
        $n.Value = [decimal]([math]::Max($Min, [math]::Min($Max, $Value)))
        $n.BackColor = $p.Input
        $n.ForeColor = $p.Text
        $n.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $n.Font = $fontMono
        $n.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Right
        $lay.Host.Controls.Add($n)
        if ($Tip -or $TipKey) { Set-DynTip $n $Tip $TipKey }
        # V7.1: slider next to the number field (both stay in sync)
        if ($Slider -and $Decimals -eq 0 -and ('TwSliderV7' -as [type])) {
            $sl = New-Object TwSliderV7
            $sl.Minimum = [int]$Min; $sl.Maximum = [int]$Max; $sl.Step = [int][math]::Max(1, $Step)
            $sl.Value = [int]$n.Value
            $sl.Location = New-Object System.Drawing.Point($IX, ($lay.Y - 1))
            $sl.Size = New-Object System.Drawing.Size((S 150), (S 24))
            $n.Location = New-Object System.Drawing.Point(($IX + (S 160)), $lay.Y)
            $n.Size = New-Object System.Drawing.Size((S 76), (S 22))
            $sl.Tag = $n; $n.Tag = $sl
            $sl.Add_ValueChanged({ param($s, $e) if ([int]$s.Tag.Value -ne $s.Value) { $s.Tag.Value = [decimal]$s.Value } })
            $n.Add_ValueChanged({ param($s, $e) if ($null -ne $s.Tag -and [int]$s.Value -ne $s.Tag.Value) { $s.Tag.Value = [int]$s.Value } })
            $lay.Host.Controls.Add($sl)
            if ($Tip -or $TipKey) { Set-DynTip $sl $Tip $TipKey }
        }
        & $register $n $l $Key $Default $Words
        $lay.Y += S 30
        return $n
    }
    $addCombo = {
        param([string]$Label, [string[]]$Items, [string]$Value, [string]$Tip = "", [string]$TipKey = "", [string]$Key = "", $Default = $null, [string]$Words = "", [int]$Width = 0, [switch]$Segmented)
        $l = & $mkLabel $Label $Tip $TipKey
        # V7.0: styled items (rounded hover, check mark)
        if ('TwComboV7' -as [type]) { $cb = New-Object TwComboV7; $cb.ItemHeight = S 20 } else { $cb = New-Object System.Windows.Forms.ComboBox }
        $cb.Location = New-Object System.Drawing.Point($IX, $lay.Y)
        $cb.Size = New-Object System.Drawing.Size($(if ($Width -gt 0) { $Width } else { $IW }), (S 22))
        $cb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        $cb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $cb.BackColor = $p.Input
        $cb.ForeColor = $p.Text
        foreach ($it in $Items) { [void]$cb.Items.Add($it) }
        $cb.SelectedIndex = [math]::Max(0, $cb.Items.IndexOf($Value))
        $lay.Host.Controls.Add($cb)
        # V7.1: a few short choices as a segmented control; the combo box stays (hidden) as the value holder
        if ($Segmented -and ('TwSegmentV7' -as [type])) {
            $sg = New-Object TwSegmentV7
            $sg.Font = $fontUi
            $sg.Location = New-Object System.Drawing.Point($IX, ($lay.Y - 1))
            $sg.Size = New-Object System.Drawing.Size($(if ($Width -gt 0) { $Width } else { [math]::Min($IW, (S 230)) }), (S 26))
            $sg.Items = [string[]]@($Items)
            $sg.SelectedIndex = $cb.SelectedIndex
            $sg.Tag = $cb; $cb.Tag = $sg
            $sg.Add_SelectedIndexChanged({ param($s, $e) if ($s.Tag.SelectedIndex -ne $s.SelectedIndex) { $s.Tag.SelectedIndex = $s.SelectedIndex } })
            $cb.Add_SelectedIndexChanged({ param($s, $e) if ($null -ne $s.Tag -and $s.Tag.SelectedIndex -ne $s.SelectedIndex) { $s.Tag.SelectedIndex = $s.SelectedIndex } })
            $cb.Visible = $false
            $lay.Host.Controls.Add($sg)
            if ($Tip -or $TipKey) { Set-DynTip $sg $Tip $TipKey }
        } elseif ($Tip -or $TipKey) { Set-DynTip $cb $Tip $TipKey }
        & $register $cb $l $Key $Default $Words
        $lay.Y += S 30
        return $cb
    }
    $addCheck = {
        param([string]$Label, [bool]$Value, [string]$Tip = "", [string]$TipKey = "", [string]$Key = "", $Default = $null, [string]$Words = "")
        # V7.0: toggle switch instead of a plain check box
        if ('TwToggleV7' -as [type]) { $c = New-Object TwToggleV7 } else { $c = New-Object System.Windows.Forms.CheckBox }
        $c.Location = New-Object System.Drawing.Point($X0, $lay.Y)
        $c.Size = New-Object System.Drawing.Size((S 470), (S 24))
        $c.Text = $Label
        $c.Checked = $Value
        $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
        $c.ForeColor = $p.Text
        $lay.Host.Controls.Add($c)
        if ($Tip -or $TipKey) { Set-DynTip $c $Tip $TipKey }
        $script:SetTipText = $Tip
        & $register $c $null $Key $Default $Words
        $lay.Y += S 28
        return $c
    }
    $addText = {
        param([string]$Label, [string]$Value, [string]$Tip = "", [string]$TipKey = "", [string]$Key = "", $Default = $null, [int]$Width = 0, [string]$Words = "", [int]$X = 0)
        $l = & $mkLabel $Label $Tip $TipKey
        $t = New-Object System.Windows.Forms.TextBox
        $t.SetBounds($(if ($X -gt 0) { $X } else { $IX }), $lay.Y, $(if ($Width -gt 0) { $Width } else { S 112 }), (S 22))
        $t.BackColor = $p.Input; $t.ForeColor = $p.Text; $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $t.Font = $fontMono; $t.Text = $Value
        $lay.Host.Controls.Add($t)
        if ($Tip -or $TipKey) { Set-DynTip $t $Tip $TipKey }
        & $register $t $l $Key $Default $Words
        $lay.Y += S 30
        return $t
    }
    $addButton = {
        param([string]$Text, [string]$Tip = "", [scriptblock]$Act, [int]$Width = 0, [string]$Words = "", [switch]$SameRow)
        $b = New-Object System.Windows.Forms.Button
        $x = if ($SameRow -and $null -ne $lay.LastBtn) { $lay.LastBtn.Right + (S 8) } else { $X0 }
        $y = if ($SameRow -and $null -ne $lay.LastBtn) { $lay.LastBtn.Top } else { $lay.Y }
        $b.SetBounds($x, $y, $(if ($Width -gt 0) { $Width } else { S 230 }), (S 28))
        Style-FlatButton -Btn $b -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
        $b.Text = $Text
        if ($null -ne $Act) { $b.Add_Click($Act) }
        $lay.Host.Controls.Add($b)
        if ($Tip) { Set-DynTip $b $Tip }
        $script:SetTipText = $Tip
        & $register $b $null "" $null $Words
        if (-not $SameRow -or $null -eq $lay.LastBtn) { $lay.Y += S 36 }
        $lay.LastBtn = $b
        return $b
    }
    $addNote = {
        param([string]$Text, [int]$Lines = 1)
        $l = New-Object System.Windows.Forms.Label
        $l.SetBounds($X0, $lay.Y, (S 470), (S (18 * $Lines)))
        $l.ForeColor = $p.Muted
        $l.Text = $Text
        $lay.Host.Controls.Add($l)
        $lay.Y += S (18 * $Lines + 8)
        return $l
    }
    $script:NewColors = @{ Up = [string]$cfg.UpColor; Down = [string]$cfg.DownColor; Accent = [string]$cfg.AccentHex }
    $script:SetTipText = ""

    # ================= Darstellung =================
    & $beginPage "Display"
    & $addSection "Sprache"
    $cbLang = & $addCombo -Label "Sprache" -Items @("Deutsch", "English") -Segmented -Value $(if ([string]$cfg.Language -eq "EN") { "English" } else { "Deutsch" }) -Tip "English: Fenster, Knöpfe, Spalten und Befehle auf Englisch (Meldungen und Glossar bleiben Deutsch). Wirkt nach einem Neustart." -Key "Language" -Default "Deutsch" -Words "Language Englisch"
    & $addSection "Farben für Plus / Minus"
    $cbUd = & $addCombo -Label "Farben für Plus / Minus" -Items (@(@((Get-UpDownSchemes).Keys) + @("Eigene"))) -Value ([string]$cfg.UpDownScheme) -Tip "Farbenblind = Blau / Orange. Eigene = frei wählen." -TipKey "COLORS" -Key "UpDownScheme" -Default ([string]$dc.UpDownScheme) -Words "grün rot farbenblind"
    $chkArrow = & $addCheck -Label "Pfeile vor Veränderungen anzeigen" -Value ([bool]$cfg.ShowArrows) -Tip "Zusätzlich zur Farbe, z. B. für Farbsehschwäche" -TipKey "COLORS" -Key "ShowArrows" -Default ([bool]$dc.ShowArrows)
    $chkFlash = & $addCheck -Label "Kurs kurz einfärben, wenn er sich ändert" -Value ([bool]$cfg.PriceFlash) -Key "PriceFlash" -Default ([bool]$dc.PriceFlash) -Words "blinken flash"
    $chkStatusBar = & $addCheck -Label "Statusleiste unten anzeigen" -Value ([bool]$cfg.ShowStatusBar) -Tip "Alter der Daten, Börsenstatus und Privat-Modus in einer Zeile am unteren Fensterrand" -Key "ShowStatusBar" -Default ([bool]$dc.ShowStatusBar) -Words "Status Leiste Statusbar Stand"
    $chkPerMon = & $addCheck -Label "Neu starten, wenn das Fenster auf einen Bildschirm mit anderer Skalierung wechselt" -Value ([bool]$cfg.PerMonitorDpi) -Tip "Das Widget rechnet alle Größen beim Start aus der Skalierung des Bildschirms. Beim Wechsel auf einen anderen Bildschirm startet es kurz neu, damit alles scharf und richtig groß ist." -Key "PerMonitorDpi" -Default ([bool]$dc.PerMonitorDpi) -Words "DPI Skalierung Monitor Bildschirm Multi-Monitor"
    $chkPill = & $addCheck -Label "Tagesveränderung als farbige Pille" -Value ([bool]$cfg.DayChangePill) -Tip "In Watchlist und Portfolio steht die Tagesveränderung in einer Pille mit getöntem Hintergrund, nicht nur in farbiger Schrift." -Key "DayChangePill" -Default ([bool]$dc.DayChangePill) -Words "Pille Tag Veränderung Prozent Pill"
    $chkAnim = & $addCheck -Label "Kurze Übergänge (Hover-Effekte)" -Value ([bool]$cfg.Animations) -Tip "Knöpfe blenden beim Darüberfahren weich über. Aus, wenn Windows die Animationen abgeschaltet hat." -Key "Animations" -Default ([bool]$dc.Animations) -Words "Animation Motion Übergang Bewegung Reduce"
    $chkHc = & $addCheck -Label "Windows-Kontrastmodus übernehmen" -Value ([bool]$cfg.FollowHighContrast) -Tip "Ist in Windows ein Kontrastdesign aktiv, startet das Widget im Theme 'Contrast'." -Key "FollowHighContrast" -Default ([bool]$dc.FollowHighContrast) -Words "Kontrast Hochkontrast Barrierefreiheit High Contrast"
    $chkToasts = & $addCheck -Label "Kurze Meldungen im Fenster (Toasts)" -Value ([bool]$cfg.ShowToasts) -Tip "Meldungen wie 'gespeichert' erscheinen unten rechts im Fenster. Alarme kommen weiter über das Tray-Symbol." -Key "ShowToasts" -Default ([bool]$dc.ShowToasts) -Words "Toast Meldung Hinweis"
    & $addSection "Schrift"
    $monoOffered = @(Get-MonoFontNames | Where-Object { $_ -eq "Consolas" -or $script:InstalledFonts -contains $_ })
    $cbMono  = & $addCombo -Label "Schrift für Zahlen (ab Neustart)" -Items $monoOffered -Value ([string]$cfg.MonoFont) -Tip "Feste Zeichenbreite: Ziffern stehen untereinander. Cascadia Mono kommt mit Windows 11 / Windows Terminal." -Key "MonoFont" -Default ([string]$dc.MonoFont) -Words "Font"
    $scaleItems = @(Get-FontScaleSteps | ForEach-Object { "$_ %" })
    $cbScale = & $addCombo -Label "Schriftgröße Listen + Chart (ab Neustart)" -Items $scaleItems -Value ("{0} %" -f [int]$cfg.FontScale) -Tip "Vergrößert Tabellen (Zeilenhöhe wächst mit) und Chart-Beschriftung. Knöpfe und Eingabefelder bleiben gleich groß, damit nichts abgeschnitten wird." -Key "FontScale" -Default ("{0} %" -f [int]$dc.FontScale) -Words "Font size größer kleiner"
    $chkAlignR = & $addCheck -Label "Zahlen rechtsbündig (Watchlist, Portfolio)" -Value ([bool]$cfg.AlignNumbersRight) -Tip "Ziffern bleiben beim Aktualisieren an ihrem Platz" -Key "AlignNumbersRight" -Default ([bool]$dc.AlignNumbersRight)
    & $addSection "Chart-Indikatoren"
    $nSmaF  = & $addNum -Label "SMA schnell (auch Bollinger-Periode)" -Min 2 -Max 200 -Value ([int]$cfg.SmaFastPeriod) -TipKey "SMA" -Key "SmaFastPeriod" -Default ([int]$dc.SmaFastPeriod) -Words "Indikatoren gleitender Durchschnitt"
    $nSmaS  = & $addNum -Label "SMA langsam" -Min 3 -Max 400 -Value ([int]$cfg.SmaSlowPeriod) -TipKey "SMA" -Key "SmaSlowPeriod" -Default ([int]$dc.SmaSlowPeriod) -Words "Indikatoren gleitender Durchschnitt"
    $nRsi   = & $addNum -Label "RSI-Periode" -Min 2 -Max 100 -Value ([int]$cfg.RsiPeriod) -TipKey "RSI" -Key "RsiPeriod" -Default ([int]$dc.RsiPeriod) -Words "Indikatoren"
    $nRsiOb = & $addNum -Label "RSI überkauft ab" -Min 51 -Max 99 -Value ([int]$cfg.RsiOverbought) -TipKey "RSI" -Key "RsiOverbought" -Default ([int]$dc.RsiOverbought) -Words "Indikatoren"
    $nRsiOs = & $addNum -Label "RSI überverkauft bis" -Min 1 -Max 49 -Value ([int]$cfg.RsiOversold) -TipKey "RSI" -Key "RsiOversold" -Default ([int]$dc.RsiOversold) -Words "Indikatoren"
    $cbMa   = & $addCombo -Label "Gleitender Durchschnitt" -Items @("SMA", "EMA") -Segmented -Value ([string]$cfg.MaType) -Tip "SMA = einfacher Durchschnitt, EMA = gewichtet die letzten Kurse stärker" -TipKey "EMA" -Key "MaType" -Default ([string]$dc.MaType) -Words "Indikatoren"
    $cbLow  = & $addCombo -Label "Unteres Feld im Chart" -Items @("RSI", "MACD") -Segmented -Value ([string]$cfg.LowerPanel) -TipKey "MACD" -Key "LowerPanel" -Default ([string]$dc.LowerPanel) -Words "Indikatoren"

    # ================= Design (style first: it has to be findable) =================
    & $beginPage "Design"
    $dsMap = @{ "Refined" = "Refined - wie gewohnt, feiner"; "Fresh" = "Fresh - Karten, mehr Luft" }
    $lStyle = & $mkLabel "Stil" "Refined: gleiche Anordnung, feinere Linien und runde Knöpfe. Fresh: abgerundete Karten, mehr Abstand, Akzentlinie unter dem Kopf. Befehl STYLE schaltet um, auch im Layout-Menü und im Tray-Menü." ""
    $lStyle.Font = $fontUiBold
    $cbStyle = New-Object System.Windows.Forms.ComboBox
    $cbStyle.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $cbStyle.Visible = $false
    [void]$cbStyle.Items.Add($dsMap["Refined"]); [void]$cbStyle.Items.Add($dsMap["Fresh"])
    $cbStyle.SelectedIndex = $(if ([string]$cfg.UiStyle -eq "Fresh") { 1 } else { 0 })
    $lay.Host.Controls.Add($cbStyle)
    & $register $cbStyle $lStyle "UiStyle" $dsMap["Refined"] "Style Design Aussehen Look Refined Fresh Karten feiner"
    $lay.Y += S 26
    $styleCards = @()
    foreach ($si in @(@{ Ix = 0; T = "Refined"; D = "wie gewohnt, feiner" }, @{ Ix = 1; T = "Fresh"; D = "Karten, mehr Luft" })) {
        $b = New-Object System.Windows.Forms.Button
        $b.SetBounds(($X0 + $si.Ix * (S 236)), $lay.Y, (S 226), (S 58))
        Style-FlatButton -Btn $b -BgColor $p.Card -FgColor $p.Text -BorderColor $p.Border
        $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $b.Padding = New-Object System.Windows.Forms.Padding((S 10), 0, 0, 0)
        $b.Text = "{0}`r`n{1}" -f $si.T, (Tr $si.D)
        $b.Tag = $si.Ix
        $b.Name = "StyleCard" + $si.T
        $b.Add_Click({ param($sender, $e) $script:SettingsCtl.Style.SelectedIndex = [int]$sender.Tag })
        $lay.Host.Controls.Add($b)
        $styleCards += $b
    }
    $lay.Y += S 66
    & $addNote "Auch ohne dieses Fenster: Befehl STYLE, Layout-Menü (oben rechts) und Tray-Menü." 1 | Out-Null
    & $addSection "Vorschau"
    $pvPanel = New-Object System.Windows.Forms.Panel
    $pvPanel.SetBounds($X0, $lay.Y, (S 456), (S 84))
    $pvPanel.BackColor = $p.BodyBg
    Enable-DoubleBuffering -Control $pvPanel
    $pvPanel.Add_Paint({ param($s, $e) try { Draw-SettingsPreview -g $e.Graphics -W $s.Width -H $s.Height } catch { } })
    $lay.Host.Controls.Add($pvPanel)
    $script:SettingsPreviewPanel = $pvPanel
    $lay.Y += S 96
    & $addSection "Farben"
    $cbTheme  = & $addCombo -Label "Theme" -Items @(Get-ThemeNames) -Value ([string]$cfg.Theme) -TipKey "THEME" -Key "Theme" -Default ([string]$dc.Theme) -Words "dunkel hell dark light graphite Farbschema"
    $cbAccent = & $addCombo -Label "Akzentfarbe" -Items @("Sky", "Amber", "Violet", "Windows", "Eigene") -Value ([string]$cfg.AccentColor) -Tip "Eigene = Farbe frei wählen, Windows = Akzentfarbe aus den Windows-Einstellungen" -Key "AccentColor" -Default ([string]$dc.AccentColor) -Words "Accent"
    & $addSection "Listen und Fenster"
    $rdMap = @{ "Compact" = "Kompakt"; "Normal" = "Normal"; "Comfortable" = "Bequem" }
    $cbRows = & $addCombo -Label "Zeilenhöhe der Listen" -Items @("Kompakt", "Normal", "Bequem") -Segmented -Value $rdMap[[string]$cfg.RowDensity] -Tip "Höhe der Zeilen in Watchlist, Portfolio, News und Analyse" -Key "RowDensity" -Default $rdMap[[string]$dc.RowDensity] -Words "Zeilen Dichte"
    $chkZebra = & $addCheck -Label "Zebra-Zeilen (jede zweite Zeile heller)" -Value ([bool]$cfg.ZebraRows) -Key "ZebraRows" -Default ([bool]$dc.ZebraRows)
    $chkIcons = & $addCheck -Label "Symbole auf Knöpfen und in Menüs" -Value ([bool]$cfg.UseIcons) -Tip $(if ($script:IconFont) { "Schrift: $($script:IconFont)" } else { "Segoe Fluent Icons / MDL2 Assets nicht gefunden - es bleibt beim Text" }) -Key "UseIcons" -Default ([bool]$dc.UseIcons) -Words "Icons"
    $chkRound = & $addCheck -Label "Abgerundete Fensterecken (Windows 11)" -Value ([bool]$cfg.RoundCorners) -Key "RoundCorners" -Default ([bool]$dc.RoundCorners)

    # ================= Layout =================
    & $beginPage "Layout"
    & $addSection "Layout"
    $cbLayout = & $addCombo -Label "Layout" -Items @(Get-LayoutNames) -Value ([string]$cfg.Layout) -Tip "Auch über den Layout-Button rechts oben oder Taste L" -TipKey "LAYOUT" -Key "Layout" -Default ([string]$dc.Layout)
    $nOpacity = & $addNum -Label "Deckkraft (%)" -Slider -Min 30 -Max 100 -Value ([int]$cfg.Opacity) -TipKey "OPACITY" -Step 5 -Key "Opacity" -Default ([int]$dc.Opacity) -Words "transparent durchsichtig"
    & $addSection "Terminal-Layout"
    $chkTWatch = & $addCheck -Label "Terminal: Watchlist und Alarme anzeigen" -Value ([bool]$cfg.TerminalShowWatch) -TipKey "LAYOUT" -Key "TerminalShowWatch" -Default ([bool]$dc.TerminalShowWatch)
    $chkTPort  = & $addCheck -Label "Terminal: Portfolio anzeigen" -Value ([bool]$cfg.TerminalShowPortfolio) -TipKey "LAYOUT" -Key "TerminalShowPortfolio" -Default ([bool]$dc.TerminalShowPortfolio)
    $nTChart   = & $addNum -Label "Terminal: Chart-Höhe (%)" -Min 25 -Max 80 -Value ([int]$cfg.TerminalChartPct) -Tip "Anteil des Charts an der Fensterhöhe; der Rest gehört den Listen" -TipKey "LAYOUT" -Step 5 -Key "TerminalChartPct" -Default ([int]$dc.TerminalChartPct)
    & $addSection "Compact- und Ticker-Leiste"
    $chkTape  = & $addCheck -Label "Laufleiste (Watchlist) im Compact-Layout" -Value ([bool]$cfg.CompactTape) -Key "CompactTape" -Default ([bool]$dc.CompactTape)
    $tsMap = @{ "Slow" = "Langsam"; "Normal" = "Normal"; "Fast" = "Schnell" }
    $cbTapeSp = & $addCombo -Label "Laufleiste Tempo" -Items @("Langsam", "Normal", "Schnell") -Segmented -Value $tsMap[[string]$cfg.TapeSpeed] -Tip "Geschwindigkeit der Laufleiste im Compact-Layout (Maus darüber = Pause)" -Key "TapeSpeed" -Default $tsMap[[string]$dc.TapeSpeed]
    [void](& $addButton -Text "Compact / Ticker zeigt ..." -Tip "Was die schmale Leiste anzeigt: Tagesänderung absolut, Vor-/Nachbörse, Mini-Chart, Marktstatus oder das Depot-Ergebnis von heute" -Act { Show-CompactOptions -Owner $script:SettingsCtl.Dlg })
    & $addSection "Fenster"
    $chkTop  = & $addCheck -Label "Immer im Vordergrund" -Value ([bool]$cfg.TopMost) -TipKey "PIN" -Key "TopMost" -Default ([bool]$dc.TopMost)
    $chkSnap = & $addCheck -Label "Fenster am Bildschirmrand einrasten" -Value ([bool]$cfg.SnapToEdges) -Key "SnapToEdges" -Default ([bool]$dc.SnapToEdges)

    # ================= Daten & Aktualisierung =================
    & $beginPage "Data"
    & $addSection "Aktualisierung"
    $nRefresh = & $addNum -Label "Intervall (Sekunden)" -Min 5 -Max 600 -Value ([int]$cfg.RefreshSeconds) -Tip "Aktiver Ticker, Portfolio und aktive Alarme" -TipKey "REFRESH" -Key "RefreshSeconds" -Default ([int]$dc.RefreshSeconds) -Words "Kurse abfragen"
    $nSlow    = & $addNum -Label "Nur-Watchlist-Ticker (Sekunden)" -Min 15 -Max 1800 -Value ([int]$cfg.SlowRefreshSeconds) -Tip "Ticker, die nur in der Watchlist stehen, und Wechselkurse" -TipKey "REFRESH" -Key "SlowRefreshSeconds" -Default ([int]$dc.SlowRefreshSeconds)
    $nHttp    = & $addNum -Label "HTTP-Timeout (Sekunden, ab Neustart)" -Min 3 -Max 60 -Value ([int]$cfg.HttpTimeoutSeconds) -Key "HttpTimeoutSeconds" -Default ([int]$dc.HttpTimeoutSeconds) -Words "Verbindung"
    $nClosed  = & $addNum -Label "Alle Börsen zu: nur alle X Minuten (0 = aus)" -Min 0 -Max 120 -Value ([int]$cfg.ClosedPollMinutes) -Tip "Spart Abfragen nachts und am Wochenende. F5 aktualisiert jederzeit." -TipKey "REFRESH" -Key "ClosedPollMinutes" -Default ([int]$dc.ClosedPollMinutes) -Words "nachts Wochenende"
    & $addNote "Datenquelle: Yahoo Finance. Twelve Data und Finnhub springen ein bzw. ergänzen die Ticker-Analyse (kostenlose Schlüssel)." 1 | Out-Null
    & $addSection "Weitere Datenquellen (eigene API-Schlüssel)"
    $keyTip = "Wird verschlüsselt gespeichert (nur dein Windows-Konto). Leer = aus. Kostenlos: twelvedata.com / finnhub.io registrieren."
    $tTdKey = & $addText -Label "Twelve Data API-Schlüssel" -Value $(if ([string]$cfg.TwelveDataKeyEnc) { "********" } else { "" }) -Tip ("Twelve Data (kostenlos): nur US-Börsen, 8 Anfragen pro Minute, 800 pro Tag - springt bei Tageskursen ein, wenn Yahoo nichts liefert. " + $keyTip) -Width (S 196) -Words "API Key Twelve Data Datenquelle Provider"
    $tFhKey = & $addText -Label "Finnhub API-Schlüssel" -Value $(if ([string]$cfg.FinnhubKeyEnc) { "********" } else { "" }) -Tip ("Finnhub (kostenlos): 60 Anfragen pro Minute; Kennzahlen über Jahre, Quartalszahlen, Analysten-Trend in der Ticker-Analyse (US-Aktien). " + $keyTip) -Width (S 196) -Words "API Key Finnhub Datenquelle Provider"
    foreach ($tk in @($tTdKey, $tFhKey)) { $tk.UseSystemPasswordChar = $true }
    [void](& $addButton -Text "Datenquellen testen (PROV)" -Width (S 220) -Tip "Speichert die Einstellungen und prüft mit deinen Schlüsseln, welche Daten der kostenlose Zugang liefert" -Words "Test Provider Schlüssel prüfen" -Act { & $script:SettingsOpenAfter { Test-Providers } })
    & $addSection "Nachrichten (F4)"
    $nNewsMin  = & $addNum -Label "Neu laden alle (Minuten)" -Min 5 -Max 240 -Value ([int]$cfg.NewsRefreshMinutes) -Tip "Eine Abfrage je Ticker in Depot und Watchlist (max. 40). Sind alle Börsen zu, halb so oft." -Step 5 -Key "NewsRefreshMinutes" -Default ([int]$dc.NewsRefreshMinutes) -Words "News"
    $nNewsMove = & $addNum -Label "Ticker markieren ab Tagesbewegung (%)" -Min 0 -Max 50 -Value ([int]$cfg.NewsMoveThreshold) -Tip "Zeigt bei der neuesten Meldung, dass sich der Ticker heute stark bewegt (0 = aus)" -Key "NewsMoveThreshold" -Default ([int]$dc.NewsMoveThreshold) -Words "News"
    $script:NewMuted = @($cfg.NewsMuted | Where-Object { $_ })
    $btnMuted = & $addButton -Text ("{0} ({1})" -f "Ausgeblendete Quellen zeigen", @($script:NewMuted).Count) -Tip ("Ausgeblendet: " + $(if (@($script:NewMuted).Count -gt 0) { @($script:NewMuted) -join ", " } else { "keine" }) + ". Klick = alle wieder zeigen. Einzelne Quellen: Rechtsklick in der News-Liste.") -Words "News Quellen stumm" -Act {
        param($sender, $e)
        $script:NewMuted = @()
        $sender.Text = "{0} (0)" -f (Tr "Ausgeblendete Quellen zeigen")
        $sender.Enabled = $false
    }
    $btnMuted.Enabled = (@($script:NewMuted).Count -gt 0)
    # v5.7: own feeds
    $tFeeds = & $addText -Label "Eigene RSS-Feeds (eine Adresse je Zeile)" -Value ([string]$cfg.NewsFeeds) -Tip "RSS- oder Atom-Adressen, z. B. die Wirtschafts-Feeds deiner Zeitung. Meldungen mit dem Namen eines deiner Ticker im Titel werden dem Ticker zugeordnet." -Key "NewsFeeds" -Default ([string]$dc.NewsFeeds) -Width (S 196) -Words "RSS Atom Feed Nachrichten Quelle finanzen derstandard"
    $tFeeds.Multiline = $true; $tFeeds.Height = S 64; $tFeeds.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical; $tFeeds.Font = $fontUi
    $lay.Y += S 44

    # ================= Alarme & Benachrichtigungen =================
    & $beginPage "Alerts"
    & $addSection "Hinweise"
    $chkTray  = & $addCheck -Label "Tray-Hinweis + Ton bei Alarmen" -Value ([bool]$cfg.ShowTrayNotifications) -Key "ShowTrayNotifications" -Default ([bool]$dc.ShowTrayNotifications) -Words "Benachrichtigung Sound"
    $chkOpen  = & $addCheck -Label "Hinweis bei Handelsstart (Börsen im Portfolio / aktiver Ticker)" -Value ([bool]$cfg.NotifyMarketOpen) -Key "NotifyMarketOpen" -Default ([bool]$dc.NotifyMarketOpen)
    $chkEarn  = & $addCheck -Label "Hinweis am Vortag von Quartalszahlen (Portfolio)" -Value ([bool]$cfg.NotifyEarnings) -TipKey "EARNINGS" -Key "NotifyEarnings" -Default ([bool]$dc.NotifyEarnings) -Words "Earnings"
    $quietTip = "HH:MM, z. B. 22:00 bis 07:00. Beide leer = keine Ruhezeit."
    $tQFrom = & $addText -Label "Ruhezeit (kein Ton / Push) von - bis" -Value ([string]$cfg.QuietFrom) -Tip $quietTip -TipKey "QUIET" -Key "QuietFrom" -Default ([string]$dc.QuietFrom) -Width (S 54) -Words "Nacht still"
    $lay.Y -= S 30
    $tQTo = New-Object System.Windows.Forms.TextBox
    $tQTo.SetBounds(($IX + (S 62)), $lay.Y, (S 54), (S 22))
    $tQTo.BackColor = $p.Input; $tQTo.ForeColor = $p.Text; $tQTo.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tQTo.Font = $fontMono; $tQTo.Text = [string]$cfg.QuietTo
    $lay.Host.Controls.Add($tQTo)
    Set-DynTip $tQTo $quietTip "QUIET"
    foreach ($tq in @($tQFrom, $tQTo)) { $tq.MaxLength = 5 }
    $tQTo.Add_TextChanged({ Update-SettingsMarkers })
    $lay.Y += S 30
    & $addSection "Handy-Push"
    $btnPush = & $addButton -Text "Handy-Push einrichten ..." -Width (S 200) -Words "Push ntfy Telegram Handy" -Act {
        $sc = $script:SettingsCtl
        if (Show-PushDialog -Owner $sc.Dlg) {
            $sc.PushState.Text = if ([string]$script:Config.PushService -eq "Aus") { "aus" } else { "aktiv: " + [string]$script:Config.PushService }
        }
    }
    Set-DynTip $btnPush "" "PUSH"
    $lPushState = New-Object System.Windows.Forms.Label
    $lPushState.SetBounds(($btnPush.Right + (S 10)), ($btnPush.Top + (S 6)), (S 220), (S 18))
    $lPushState.ForeColor = $p.Muted
    $lPushState.Text = if ([string]$cfg.PushService -eq "Aus") { "aus" } else { "aktiv: " + [string]$cfg.PushService }
    $lay.Host.Controls.Add($lPushState)
    & $addSection "Nachrichten mit Alarm-Wörtern"
    $kwTip = "Kommagetrennt, z. B.: downgrade, gewinnwarnung, übernahme, profit warning. Kommt eine Schlagzeile mit so einem Wort zu einem Ticker im Depot, gibt es einen Hinweis (und Handy-Push, falls eingerichtet). Leer = aus."
    $tKw = & $addText -Label "Alarm-Wörter" -Value ([string]$cfg.NewsKeywords) -Tip $kwTip -Key "NewsKeywords" -Default ([string]$dc.NewsKeywords) -Width (S 196) -Words "News Schlagzeilen"
    $chkKwWatch = & $addCheck -Label "Alarm-Wörter auch für Watchlist-Ticker" -Value ([bool]$cfg.NewsKeywordWatch) -Key "NewsKeywordWatch" -Default ([bool]$dc.NewsKeywordWatch)
    & $addSection "Signal-Wechsel (Ticker-Analyse)"
    $saMap = @{ "Depot" = "Depot"; "Alle" = "Depot + Watchlist"; "Aus" = "Aus" }
    $cbSigAl = & $addCombo -Label "Hinweis bei Signal-Wechsel" -Items @("Depot", "Depot + Watchlist", "Aus") -Segmented -Width (S 300) -Value $saMap[[string]$cfg.SignalAlerts] -Tip "Einmal am Tag: Signal wird überwiegend positiv / negativ, Kurs fällt unter die Unterstützung oder steigt über den Widerstand" -Key "SignalAlerts" -Default "Depot" -Words "Signal Alarm Unterstützung Widerstand"

    # ================= Depot =================
    & $beginPage "Depot"
    & $addSection "Währung und Kennzahlen"
    $curItems = @("Auto") + @(Get-DisplayCurrencies)
    $cbCur = & $addCombo -Label "Währung (Auto = Währung des Tickers)" -Items $curItems -Value $(if ([bool]$cfg.AutoCurrency) { "Auto" } else { [string]$cfg.Currency }) -Tip "Auto: jeder Kurs und Chart in der Währung des Tickers, das Depot bleibt in der Basiswährung. Sonst alles in der gewählten Währung (auch Taste W)." -Key "Currency" -Default "Auto" -Words "Basiswährung EUR USD CHF GBP Currency"
    $nRf = & $addNum -Label "Risikofreier Zins für die Sharpe Ratio (%)" -Min 0 -Max 10 -Value ([double]$cfg.RiskFreePct) -Tip "Wird in der Analyse (Risiko) von der Rendite abgezogen" -Step 0.1 -Decimals 1 -Key "RiskFreePct" -Default ([double]$dc.RiskFreePct) -Words "Sharpe Risiko Zins"
    $chkTrayDepot = & $addCheck -Label "Tray-Symbol in der Farbe des Depot-Tages (statt Ticker)" -Value ([bool]$cfg.TrayFollowsDepot) -Tip "Grün / Rot / Grau nach dem heutigen Ergebnis des Depots. Ohne Positionen: aktiver Ticker." -Key "TrayFollowsDepot" -Default ([bool]$dc.TrayFollowsDepot)
    & $addSection "Werkzeuge (speichert und öffnet)"
    $openAfter = { param([scriptblock]$Then) $script:SettingsThen = $Then; $script:SettingsCtl.Ok.PerformClick() }
    $script:SettingsOpenAfter = $openAfter
    [void](& $addButton -Text "Cash-Konto ..." -Width (S 170) -Tip "Speichert die Einstellungen und öffnet das Cash-Konto (Befehl CASH)" -Words "CASH Einzahlung" -Act { & $script:SettingsOpenAfter { Show-CashDialog } })
    [void](& $addButton -Text "Sparpläne ..." -Width (S 170) -SameRow -Tip "Speichert die Einstellungen und öffnet die Sparpläne (Befehl SPAR)" -Words "SPAR Sparplan" -Act { & $script:SettingsOpenAfter { Show-SavingsPlansDialog } })
    $lay.LastBtn = $null
    [void](& $addButton -Text "Broker-CSV importieren ..." -Width (S 170) -Tip "Speichert die Einstellungen und öffnet den CSV-Import (Befehl IMP)" -Words "IMP Trading212 Import" -Act { & $script:SettingsOpenAfter { Show-CsvImportDialog } })
    [void](& $addButton -Text "Zielgewichte ..." -Width (S 170) -SameRow -Tip "Speichert die Einstellungen und öffnet Zielgewichte / Rebalancing (Befehl REBAL)" -Words "REBAL Rebalancing" -Act { & $script:SettingsOpenAfter { Show-AnalysisDialog -Page "Target" } })
    $lay.LastBtn = $null

    # ================= Tastatur & Befehle =================
    & $beginPage "Keyboard"
    & $addSection "Globales Tastenkürzel"
    $tHk = & $addText -Label "Globales Tastenkürzel (zeigen / verstecken)" -Value ([string]$cfg.GlobalHotkey) -Tip "Funktioniert auch, wenn ein anderes Programm vorne ist. Z. B. Ctrl+Alt+W, Win+F9. Leer = aus." -TipKey "HOTKEY" -Key "GlobalHotkey" -Default ([string]$dc.GlobalHotkey) -Width (S 140) -Words "Hotkey"
    & $addSection "Befehlszeile"
    & $addNote "Strg+K öffnet die Befehlszeile. Sie findet Befehle, Ticker, Menüeinträge und jede Einstellung - z. B. 'zebra', 'push' oder 'SET STIL'." 2 | Out-Null
    [void](& $addButton -Text "Alle Tastenkürzel und Befehle (HELP)" -Width (S 260) -Words "Hilfe F1 Kürzel" -Act { Show-ShortcutHelp })
    [void](& $addButton -Text "Glossar öffnen (G)" -Width (S 260) -Words "Begriffe Erklärungen" -Act { Show-GlossaryDialog })

    # ================= Sonstiges =================
    & $beginPage "Misc"
    & $addSection "Erklärungen (Maus darüber)"
    $modes = Get-TooltipModes
    $cbTip = & $addCombo -Label "Ausführlichkeit" -Items @($modes.Values) -Value ([string]$modes[[string]$cfg.TooltipMode]) -TipKey "TOOLTIPS" -Key "TooltipMode" -Default ([string]$modes[[string]$dc.TooltipMode]) -Words "Tooltips Hinweise"
    $nTipDelay = & $addNum -Label "Verzögerung (Millisekunden)" -Min 0 -Max 3000 -Value ([int]$cfg.TooltipDelayMs) -Tip "Wie lange die Maus stillstehen muss, bis der Hinweis erscheint" -TipKey "TOOLTIPS" -Step 100 -Key "TooltipDelayMs" -Default ([int]$dc.TooltipDelayMs) -Words "Tooltips"
    $chkHover  = & $addCheck -Label "Infokarte, wenn die Maus auf einem Ticker ruht" -Value ([bool]$cfg.HoverCards) -Tip "Watchlist und Portfolio: Kurs, Tagesspanne, 52-Wochen-Balken, 5-Tage-Verlauf, Position, nächste Termine" -Key "HoverCards" -Default ([bool]$dc.HoverCards) -Words "Hover"
    & $addSection "System"
    $autoNow = Test-Autostart
    $chkAuto = & $addCheck -Label "Mit Windows starten (Verknüpfung im Autostart-Ordner)" -Value $autoNow -Words "Autostart"
    & $addSection "Einstellungen übertragen"
    [void](& $addButton -Text "Einstellungen exportieren ..." -Width (S 200) -Tip "Speichert die Einstellungen (gespeicherter Stand, ohne Depots und ohne Push-Zugang) als Datei, z. B. für einen neuen PC" -Words "Export Datei neuer PC sichern" -Act { [void](Export-SettingsFile) })
    [void](& $addButton -Text "Einstellungen importieren ..." -Width (S 200) -SameRow -Tip "Liest eine exportierte Einstellungs-Datei ein (vorher automatisches Backup). Depot-Daten bleiben unberührt." -Words "Import Datei neuer PC" -Act { $script:SettingsAfter = { Import-SettingsFile }; $script:SettingsCtl.Dlg.Close() })
    $lay.LastBtn = $null
    & $addSection "Daten und Sicherung"
    [void](& $addButton -Text "Datenordner öffnen" -Width (S 170) -Tip $script:DataDir -Act { try { Start-Process -FilePath "explorer.exe" -ArgumentList "`"$($script:DataDir)`"" } catch { } })
    [void](& $addButton -Text "Log öffnen" -Width (S 170) -SameRow -Tip $script:LogPath -Act { if (Test-Path $script:LogPath) { try { Start-Process -FilePath "notepad.exe" -ArgumentList "`"$($script:LogPath)`"" } catch { } } })
    $lay.LastBtn = $null
    $btnBackup = & $addButton -Text "Backup jetzt" -Width (S 170) -Tip "Kopie von Einstellungen, Portfolio, Alarmen und Transaktionen in $($script:BackupDir)" -Act {
        $dest = Backup-DataFiles -Reason "manuell"
        $owner = if ($null -ne $script:SettingsCtl) { $script:SettingsCtl.Dlg } else { $form }
        $txt = if ($dest) { "Backup erstellt:`r`n$dest`r`n`r`n(Es werden die letzten 10 Backups behalten.)" } else { "Backup fehlgeschlagen oder keine Daten vorhanden - siehe Log." }
        [System.Windows.Forms.MessageBox]::Show($owner, $txt, "Backup", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    Set-DynTip $btnBackup "Kopie von Einstellungen, Portfolio, Alarmen und Transaktionen in $($script:BackupDir)" "BACKUP"
    [void](& $addButton -Text "Wiederherstellen ..." -Width (S 170) -SameRow -Tip "Ein Backup zurückspielen (täglich wird automatisch gesichert)" -Act { $script:SettingsAfter = { Show-RestoreDialog }; $script:SettingsCtl.Dlg.Close() })
    $lay.LastBtn = $null
    [void](& $addButton -Text "Daten exportieren ..." -Width (S 170) -Tip "Alle Daten als ZIP sichern (z. B. für einen anderen PC)" -Act { Export-DataZip })
    [void](& $addButton -Text "Daten importieren ..." -Width (S 170) -SameRow -Tip "Einen ZIP-Export einlesen (ersetzt alle Daten, vorher Backup)" -Act { $script:SettingsAfter = { Import-DataZip }; $script:SettingsCtl.Dlg.Close() })
    $lay.LastBtn = $null
    [void](& $addButton -Text $(if ($script:IsPortable) { "Portabel beenden ..." } else { "Portabel machen ..." }) -Width (S 170) -Tip $(if ($script:IsPortable) { "Daten liegen im Programmordner (data). Zurück nach %LOCALAPPDATA%." } else { "Daten in den Programmordner (data) verschieben, z. B. für einen USB-Stick" }) -Words "USB Stick" -Act { $script:SettingsAfter = { Switch-PortableMode }; $script:SettingsCtl.Dlg.Close() })
    & $addSection "Fehlersuche"
    [void](& $addButton -Text "Zustand prüfen (HEALTH)" -Width (S 200) -Tip "Prüft Datendateien, Backups, Datenquelle, Schriften und das Log" -Words "Health Diagnose Fehler" -Act { Show-HealthReport })
    [void](& $addButton -Text "Diagnose exportieren ..." -Width (S 200) -SameRow -Tip "ZIP mit Log, Einstellungen ohne Zugangsdaten und dem Zustand - für Fehlerberichte. Keine Depot-Daten." -Words "DIAG Fehlerbericht Log" -Act { [void](Export-Diagnostics) })
    $lay.LastBtn = $null
    & $addNote ("Version {0} - Daten: {1}" -f $script:AppVersion, $script:DataDir) 1 | Out-Null

    # ---- index for Ctrl+K: built from the real window, then thrown away ----
    if ($IndexOnly) {
        $out = New-Object System.Collections.Generic.List[object]
        $seen = New-Object System.Collections.Generic.HashSet[string]
        foreach ($pg in $pages) {
            $tt = Get-SettingsPageTitle -Id $pg.Id -Language $lang
            $t = "SET " + $tt.ToUpperInvariant()
            if ($seen.Add($t)) { $out.Add([PSCustomObject]@{ Text = $t; Desc = (Tr "Einstellungen - Seite"); Search = ("{0} {1}" -f $pg.De, $pg.En) }) }
        }
        foreach ($e in $reg) {
            $lbl = (Tr ([string]$e.Label)) -replace '\s*\.\.\.$', '' -replace '\s+\(\d+\)$', ''
            if (-not $lbl.Trim()) { continue }
            $t = "SET " + $lbl.ToUpperInvariant()
            if ($seen.Add($t)) { $out.Add([PSCustomObject]@{ Text = $t; Desc = ("{0} - {1}" -f (Tr "Einstellung"), (Get-SettingsPageTitle -Id $e.Page -Language $lang)); Search = [string]$e.Search }) }
        }
        $dlg.Dispose()
        return $out.ToArray()
    }

    # ---- page list ----
    foreach ($pg in $pages) { [void]$nav.Items.Add((Get-SettingsPageTitle -Id $pg.Id -Language $lang)) }
    $nav.Add_DrawItem({
        param($sender, $e)
        if ($e.Index -lt 0) { return }
        $sc = $script:SettingsCtl
        if ($null -eq $sc) { return }
        $id = [string]$sc.PageIds[$e.Index]
        $sel = ($id -eq $sc.Cur)
        $pl = $script:Pal
        $bgB = New-Object System.Drawing.SolidBrush($(if ($sel) { $pl.BodyBg } else { $pl.Card }))
        $e.Graphics.FillRectangle($bgB, $e.Bounds)
        $bgB.Dispose()
        if ($sel) {
            $ab = New-Object System.Drawing.SolidBrush($pl.Accent)
            $e.Graphics.FillRectangle($ab, $e.Bounds.X, ($e.Bounds.Y + (S 6)), (S 3), ($e.Bounds.Height - (S 12)))
            $ab.Dispose()
        }
        $q = [string]$sc.Search.Text
        $n = 0; $titleHit = $false
        if ($q.Trim() -and $null -ne $sc.Hits) { $n = [int]$sc.Hits.Counts[$id]; $titleHit = (@($sc.Hits.TitlePages) -contains $id) }
        $fg = if ($q.Trim() -and $n -eq 0 -and -not $titleHit) { $pl.Border } elseif ($sel) { $pl.Text } else { $pl.Muted }
        $chg = @($sc.Reg | Where-Object { $_.Page -eq $id -and $_.Changed }).Count
        $fl = [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
        $rT = New-Object System.Drawing.Rectangle(($e.Bounds.X + (S 14)), $e.Bounds.Y, ($e.Bounds.Width - (S 40)), $e.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$sender.Items[$e.Index], $(if ($sel) { $fontUiBold } else { $fontUi }), $rT, $fg, $fl)
        $rN = New-Object System.Drawing.Rectangle(($e.Bounds.Right - (S 26)), $e.Bounds.Y, (S 20), $e.Bounds.Height)
        $flR = $fl -bor [System.Windows.Forms.TextFormatFlags]::Right
        if ($q.Trim() -and $n -gt 0) { [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$n, $fontUiBold, $rN, $pl.Accent, $flR) }
        elseif (-not $q.Trim() -and $chg -gt 0) { [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string][char]0x25CF, $fontUi, $rN, $pl.Accent, $flR) }
    })
    $nav.Add_SelectedIndexChanged({
        param($sender, $e)
        $sc = $script:SettingsCtl
        if ($null -eq $sc -or $sender.SelectedIndex -lt 0) { return }
        $id = [string]$sc.PageIds[$sender.SelectedIndex]
        if ($id -ne $sc.Cur) { Show-SettingsPage $id }
    })

    # ---- button bar ----
    $lSearch = New-Object System.Windows.Forms.Label
    $lSearch.SetBounds((S 14), (S 17), (S 54), (S 18)); $lSearch.Text = "Suchen:"
    $lSearch.ForeColor = $p.Muted
    $bar.Controls.Add($lSearch)
    $tSearch = New-Object System.Windows.Forms.TextBox
    $tSearch.SetBounds((S 70), (S 13), (S 200), (S 24))
    $tSearch.Name = "tSettingsSearch"
    $tSearch.BackColor = $p.Input; $tSearch.ForeColor = $p.Text; $tSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $bar.Controls.Add($tSearch)
    Set-DynTip $tSearch "Einstellung auf allen Seiten suchen, z. B. 'stil', 'schrift', 'push' - die Seite mit Treffern öffnet sich, die Liste links zählt die Treffer"
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Size = New-Object System.Drawing.Size((S 94), (S 28))
    Style-FlatButton -Btn $btnCancel -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $btnCancel.Text = "Abbrechen"
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $bar.Controls.Add($btnCancel)
    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Size = New-Object System.Drawing.Size((S 94), (S 28))
    Style-FlatButton -Btn $btnOk -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $btnOk.Font = $fontUiBold
    $btnOk.Text = "OK"
    $bar.Controls.Add($btnOk)
    $btnReset = New-Object System.Windows.Forms.Button
    $btnReset.Size = New-Object System.Drawing.Size((S 154), (S 28))
    Style-FlatButton -Btn $btnReset -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $btnReset.Text = "Seite zurücksetzen"
    $bar.Controls.Add($btnReset)
    $btnCancel.Name = "btnSetCancel"; $btnOk.Name = "btnSetOk"; $btnReset.Name = "btnSetReset"
    $bar.Add_Layout({
        param($sender, $e)
        $w = $sender.ClientSize.Width
        $c = $sender.Controls
        $c["btnSetCancel"].Location = New-Object System.Drawing.Point(($w - (S 108)), (S 11))
        $c["btnSetOk"].Location = New-Object System.Drawing.Point(($w - (S 208)), (S 11))
        $c["btnSetReset"].Location = New-Object System.Drawing.Point(($w - (S 370)), (S 11))
    })
    Set-DynTip $btnReset "Setzt alle Einstellungen dieser Seite auf den Standard zurück (gespeichert erst mit OK). Punkt vor einer Einstellung = vom Standard geändert."
    $btnReset.Add_Click({
        $sc = $script:SettingsCtl
        foreach ($e in @($sc.Reg | Where-Object { $_.Page -eq $sc.Cur -and $null -ne $_.Default })) { Set-SettingCtlValue $e.Ctl $e.Default }
        if ($sc.Cur -eq "Alerts") { $sc.QTo.Text = [string]$script:ConfigDefaults.QuietTo }
        if ($sc.Cur -eq "Display") { $script:NewColors.Up = ""; $script:NewColors.Down = "" }
        if ($sc.Cur -eq "Design") { $script:NewColors.Accent = ""; Invoke-SettingsPreview }
        Update-SettingsMarkers
        Set-TransientStatus ("Seite '{0}' auf Standard gesetzt - OK speichert" -f (Get-SettingsPageTitle -Id $sc.Cur -Language $(if ([string]$script:Config.Language -eq "EN") { "EN" } else { "DE" }))) 4
    })

    # ---- colour pickers ----
    $script:PickColor = {
        param([string]$Start)
        $cd = New-Object System.Windows.Forms.ColorDialog
        $cd.FullOpen = $true
        $rgb = ConvertFrom-HexColor $Start
        if ($null -ne $rgb) { $cd.Color = [System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]) }
        $hex = ""
        if ($cd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $hex = ConvertTo-HexColor $cd.Color.R $cd.Color.G $cd.Color.B }
        $cd.Dispose()
        return $hex
    }
    $cbUd.Add_SelectionChangeCommitted({
        param($sender, $e)
        if ([string]$sender.SelectedItem -ne "Eigene") { return }
        $u = & $script:PickColor $script:NewColors.Up
        if (-not $u) { return }
        $d = & $script:PickColor $script:NewColors.Down
        if (-not $d) { return }
        $script:NewColors.Up = $u; $script:NewColors.Down = $d
    })
    $cbAccent.Add_SelectionChangeCommitted({
        param($sender, $e)
        if ([string]$sender.SelectedItem -eq "Eigene") {
            $a = & $script:PickColor $script:NewColors.Accent
            if ($a) { $script:NewColors.Accent = $a }
        }
        Invoke-SettingsPreview
    })

    # ---- style cards + live preview ----
    $cbStyle.Add_SelectedIndexChanged({
        $sc = $script:SettingsCtl
        if ($null -eq $sc) { return }
        $pl = $script:Pal
        foreach ($b in $sc.Cards) {
            $on = ([int]$b.Tag -eq $sc.Style.SelectedIndex)
            $b.FlatAppearance.BorderSize = if ($on) { 2 } else { 1 }
            $b.FlatAppearance.BorderColor = if ($on) { $pl.Accent } else { $pl.Border }
            $b.ForeColor = if ($on) { $pl.Accent } else { $pl.Text }
            $b.Font = if ($on) { $fontUiBold } else { $fontUi }
        }
        Invoke-SettingsPreview
    })
    $cbTheme.Add_SelectionChangeCommitted({ Invoke-SettingsPreview })
    $cbRows.Add_SelectionChangeCommitted({ Invoke-SettingsPreview })
    $chkZebra.Add_CheckedChanged({ Invoke-SettingsPreview })

    $btnOk.Add_Click({
        $sc = $script:SettingsCtl
        if ($sc.SmaF.Value -ge $sc.SmaS.Value) {
            Show-SettingsPage "Display"
            [System.Windows.Forms.MessageBox]::Show($sc.Dlg, "SMA schnell muss kleiner als SMA langsam sein.", "Einstellungen",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            $script:SettingsThen = $null
            return
        }
        if ($sc.Slow.Value -lt $sc.Refresh.Value) { $sc.Slow.Value = $sc.Refresh.Value }
        foreach ($tq in @($sc.QFrom, $sc.QTo)) {
            $tv = $tq.Text.Trim()
            if ($tv -and $tv -notmatch '^([01]?\d|2[0-3]):[0-5]\d$') {
                Show-SettingsPage "Alerts"
                [System.Windows.Forms.MessageBox]::Show($sc.Dlg, "Ruhezeit bitte als HH:MM eingeben (z. B. 22:00), oder leer lassen.", "Einstellungen",
                    [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                $tq.Focus() | Out-Null
                $script:SettingsThen = $null
                return
            }
        }
        $sc.Dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $sc.Dlg.Close()
    })
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel
    $tSearch.Add_TextChanged({ Update-SettingsSearch })
    # Enter in the search box must not press OK (the dialog key would come first)
    $tSearch.Add_PreviewKeyDown({ param($sender, $e) if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $e.IsInputKey = $true } })
    $tSearch.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $e.SuppressKeyPress = $true; Update-SettingsSearch }
    })
    $dlg.Add_KeyDown({
        param($sender, $e)
        if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::F) { $e.SuppressKeyPress = $true; $script:SettingsCtl.Search.Focus() | Out-Null }
    })
    $dlg.Add_FormClosing({
        param($sender, $e)
        $sc = $script:SettingsCtl
        if ($null -eq $sc) { return }
        if ($sender.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) {
            $script:Config.SettingsW = $sender.ClientSize.Width
            $script:Config.SettingsH = $sender.ClientSize.Height
        }
        $script:Config.SettingsPage = [string]$sc.Cur
    })

    $orig = @{ UiStyle = [string]$cfg.UiStyle; Theme = [string]$cfg.Theme; AccentColor = [string]$cfg.AccentColor; AccentHex = [string]$cfg.AccentHex; RowDensity = [string]$cfg.RowDensity; ZebraRows = [bool]$cfg.ZebraRows }
    $pageIds = @($pages | ForEach-Object { $_.Id })
    # (handlers reach the controls through script scope, not via the caller's locals)
    $script:SettingsCtl = @{
        Dlg = $dlg; Nav = $nav; Pages = $pagePanels; PageIds = $pageIds; Cur = ""; Reg = $reg; Search = $tSearch; Hits = $null; Building = $true
        SmaF = $nSmaF; SmaS = $nSmaS; Slow = $nSlow; Refresh = $nRefresh; PushState = $lPushState; QFrom = $tQFrom; QTo = $tQTo; Ok = $btnOk; Reset = $btnReset
        Style = $cbStyle; Cards = $styleCards; Theme = $cbTheme; Accent = $cbAccent; Rows = $cbRows; Zebra = $chkZebra
    }
    # style cards show the current choice (the preview is still off while building)
    $cbStyle.SelectedIndex = -1
    $cbStyle.SelectedIndex = $(if ([string]$cfg.UiStyle -eq "Fresh") { 1 } else { 0 })
    $start = if ($Page -and $pageIds -contains $Page) { $Page } elseif ($pageIds -contains [string]$cfg.SettingsPage) { [string]$cfg.SettingsPage } else { "Design" }
    Show-SettingsPage $start
    Update-SettingsMarkers
    $script:SettingsCtl.Building = $false
    if ($Search) {
        $script:SettingsInitialSearch = $Search
        $dlg.Add_Shown({
            $sc = $script:SettingsCtl
            if ($null -eq $sc) { return }
            $sc.Search.Text = [string]$script:SettingsInitialSearch
            $sc.Search.SelectionStart = $sc.Search.Text.Length
        })
    }
    $dlg.Add_Shown({ param($sender, $e) $sender.Activate() })

    $script:SettingsAfter = $null
    $script:SettingsThen = $null
    Apply-Language $dlg
    try { $res = $dlg.ShowDialog($form) } finally { $script:SettingsCtl = $null }
    # v4.5: data actions run after the settings window is gone (changes there are discarded)
    $after = $script:SettingsAfter
    $script:SettingsAfter = $null
    $then = $script:SettingsThen
    $script:SettingsThen = $null
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) {
        # undo the live preview
        foreach ($k in @($orig.Keys)) { $cfg.$k = $orig[$k] }
        $dlg.Dispose()
        Save-JsonState -Path $script:ConfigPath -Data $cfg
        try { Apply-ThemeToAllControls } catch { }
        if ($null -ne $after) { & $after }
        return
    }

    $needRefresh = ([int]$nSmaF.Value -ne [int]$cfg.SmaFastPeriod) -or ([int]$nSmaS.Value -ne [int]$cfg.SmaSlowPeriod) -or ([int]$nRsi.Value -ne [int]$cfg.RsiPeriod)
    $cfg.RefreshSeconds        = [int]$nRefresh.Value
    $cfg.SlowRefreshSeconds    = [int]$nSlow.Value
    $cfg.HttpTimeoutSeconds    = [int]$nHttp.Value
    $cfg.ClosedPollMinutes     = [int]$nClosed.Value
    $cfg.SmaFastPeriod         = [int]$nSmaF.Value
    $cfg.SmaSlowPeriod         = [int]$nSmaS.Value
    $cfg.RsiPeriod             = [int]$nRsi.Value
    $cfg.RsiOverbought         = [int]$nRsiOb.Value
    $cfg.RsiOversold           = [int]$nRsiOs.Value
    $cfg.Theme                 = [string]$cbTheme.SelectedItem
    $cfg.AccentColor           = [string]$cbAccent.SelectedItem
    $cfg.TopMost               = [bool]$chkTop.Checked
    $cfg.CompactTape           = [bool]$chkTape.Checked
    $cfg.UiStyle               = if ([string]$cbStyle.SelectedItem -like "Fresh*") { "Fresh" } else { "Refined" }
    $cfg.RowDensity            = switch ([string]$cbRows.SelectedItem) { "Kompakt" { "Compact" } "Bequem" { "Comfortable" } default { "Normal" } }
    $cfg.TapeSpeed             = switch ([string]$cbTapeSp.SelectedItem) { "Langsam" { "Slow" } "Schnell" { "Fast" } default { "Normal" } }
    $cfg.ZebraRows             = [bool]$chkZebra.Checked
    $cfg.UseIcons              = [bool]$chkIcons.Checked
    $cfg.ShowTrayNotifications = [bool]$chkTray.Checked
    $cfg.NotifyMarketOpen      = [bool]$chkOpen.Checked
    $cfg.NotifyEarnings        = [bool]$chkEarn.Checked
    $cfg.QuietFrom             = $tQFrom.Text.Trim()
    $cfg.QuietTo               = $tQTo.Text.Trim()
    $newLayout                 = [string]$cbLayout.SelectedItem
    $cfg.Opacity               = [int]$nOpacity.Value
    $cfg.TerminalShowWatch     = [bool]$chkTWatch.Checked
    $cfg.TerminalShowPortfolio = [bool]$chkTPort.Checked
    $cfg.TerminalChartPct      = [int]$nTChart.Value
    foreach ($mk in $modes.Keys) { if ($modes[$mk] -eq [string]$cbTip.SelectedItem) { $cfg.TooltipMode = $mk } }
    $cfg.TooltipDelayMs        = [int]$nTipDelay.Value
    $cfg.HoverCards            = [bool]$chkHover.Checked
    $newLang = if ([string]$cbLang.SelectedItem -eq "English") { "EN" } else { "DE" }
    $langChanged = ($newLang -ne [string]$cfg.Language)
    $cfg.Language              = $newLang
    if ([string]$cbMa.SelectedItem -ne [string]$cfg.MaType -or [string]$cbLow.SelectedItem -ne [string]$cfg.LowerPanel) { $needRefresh = $true }
    $cfg.MaType                = [string]$cbMa.SelectedItem
    $cfg.LowerPanel            = [string]$cbLow.SelectedItem
    $cfg.UpDownScheme          = [string]$cbUd.SelectedItem
    if ($cfg.UpDownScheme -eq "Eigene" -and -not ($script:NewColors.Up -and $script:NewColors.Down)) { $cfg.UpDownScheme = "Standard" }
    $cfg.UpColor               = [string]$script:NewColors.Up
    $cfg.DownColor             = [string]$script:NewColors.Down
    $cfg.AccentHex             = [string]$script:NewColors.Accent
    if ($cfg.AccentColor -eq "Eigene" -and -not $cfg.AccentHex) { $cfg.AccentColor = "Sky" }
    $cfg.ShowArrows            = [bool]$chkArrow.Checked
    $cfg.PriceFlash            = [bool]$chkFlash.Checked
    $cfg.ShowStatusBar         = [bool]$chkStatusBar.Checked
    $cfg.ShowToasts            = [bool]$chkToasts.Checked
    $cfg.Animations            = [bool]$chkAnim.Checked
    $cfg.FollowHighContrast    = [bool]$chkHc.Checked
    $cfg.DayChangePill         = [bool]$chkPill.Checked
    $cfg.PerMonitorDpi         = [bool]$chkPerMon.Checked
    $cfg.TrayFollowsDepot      = [bool]$chkTrayDepot.Checked
    $cfg.SnapToEdges           = [bool]$chkSnap.Checked
    $cfg.RiskFreePct           = [double]$nRf.Value
    $newCur = [string]$cbCur.SelectedItem
    $curChanged = if ($newCur -eq "Auto") { -not [bool]$cfg.AutoCurrency } else { [bool]$cfg.AutoCurrency -or $newCur -ne [string]$cfg.Currency }
    $newMono  = [string]$cbMono.SelectedItem
    $newScale = [int](([string]$cbScale.SelectedItem) -replace '[^0-9]', '')
    $fontChanged = ($newMono -ne [string]$cfg.MonoFont) -or ($newScale -ne [int]$cfg.FontScale)
    $cfg.MonoFont              = $newMono
    $cfg.FontScale             = $newScale
    $cfg.AlignNumbersRight     = [bool]$chkAlignR.Checked
    $cfg.RoundCorners          = [bool]$chkRound.Checked
    $newsMinChanged = ([int]$nNewsMin.Value -ne [int]$cfg.NewsRefreshMinutes)
    $cfg.NewsRefreshMinutes    = [int]$nNewsMin.Value
    $cfg.NewsMoveThreshold     = [int]$nNewsMove.Value
    $cfg.NewsKeywords          = (@(ConvertTo-KeywordList $tKw.Text) -join ", ")
    $cfg.NewsKeywordWatch      = [bool]$chkKwWatch.Checked
    $cfg.SignalAlerts          = switch ([string]$cbSigAl.SelectedItem) { "Depot + Watchlist" { "Alle" } "Aus" { "Aus" } default { "Depot" } }
    $feedsNew = (@(ConvertTo-FeedList $tFeeds.Text) -join "`r`n")
    if ($feedsNew -ne [string]$cfg.NewsFeeds) { $script:NextNewsLoad = Get-Date }
    $cfg.NewsFeeds             = $feedsNew
    # V6: keys - "********" = unchanged, empty = remove
    foreach ($kp in @(@($tTdKey, "TwelveDataKeyEnc"), @($tFhKey, "FinnhubKeyEnc"))) {
        $kt = ([string]$kp[0].Text).Trim()
        if ($kt -eq "********") { continue }
        if ($kt -ne [string](Unprotect-Secret ([string]$cfg.($kp[1])))) {
            $cfg.($kp[1]) = if ($kt) { Protect-Secret $kt } else { "" }
            # a new key: forget what the old one could do
            if ($null -ne $cfg.ProviderCaps -and $cfg.ProviderCaps -isnot [string]) { $pfx = if ($kp[1] -like "Twelve*") { "TwelveData|" } else { "Finnhub|" }; foreach ($pp in @($cfg.ProviderCaps.PSObject.Properties | Where-Object { $_.Name -like "$pfx*" })) { $cfg.ProviderCaps.PSObject.Properties.Remove($pp.Name) } }
        }
    }
    $cfg.NewsMuted             = @($script:NewMuted)
    $hkNew = $tHk.Text.Trim()
    $hkChanged = ($hkNew -ne [string]$cfg.GlobalHotkey)
    if (-not $hkNew -or $null -ne (ConvertFrom-HotkeyText $hkNew)) { $cfg.GlobalHotkey = $hkNew }
    else { Set-TransientStatus "Tastenkürzel '$hkNew' nicht erkannt - z. B. Ctrl+Alt+W" 6; $hkChanged = $false }
    $autoWanted = [bool]$chkAuto.Checked
    $dlg.Dispose()
    $script:SettingsIndexCache = $null
    if ($autoWanted -ne $autoNow) {
        $aErr = Set-Autostart -Enable $autoWanted
        if ($aErr) {
            [System.Windows.Forms.MessageBox]::Show($form, "Autostart konnte nicht geändert werden:`r`n$aErr", "Einstellungen",
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    }
    $cfg.Autostart = Test-Autostart

    # Apply
    $pollTimer.Interval = [int]$cfg.RefreshSeconds * 1000
    $refStr = "$($cfg.RefreshSeconds)s"
    if ($cmbRefresh.Items.IndexOf($refStr) -lt 0) { [void]$cmbRefresh.Items.Add($refStr) }
    $cmbRefresh.SelectedIndex = $cmbRefresh.Items.IndexOf($refStr)
    $form.TopMost = [bool]$cfg.TopMost
    $btnToggleRsi.Text = if ([string]$cfg.LowerPanel -eq "MACD") { "MACD" } else { "RSI-$($cfg.RsiPeriod)" }
    $btnToggleSma.Text = [string]$cfg.MaType
    Set-Tip $btnToggleSma "Gleitende Durchschnitte SMA $($cfg.SmaFastPeriod)/$($cfg.SmaSlowPeriod) (Taste M)" "SMA"
    Apply-TooltipMode
    Update-ChartControlsLayout
    Apply-NumberAlignment
    if ($newsMinChanged) { $script:NextNewsLoad = (Get-Date).AddMinutes([int]$cfg.NewsRefreshMinutes) }
    Save-JsonState -Path $script:ConfigPath -Data $cfg
    Apply-ThemeToAllControls
    Apply-Layout $newLayout
    if ($curChanged) { Set-ActiveCurrency -NewCurrency $newCur }
    elseif ($needRefresh) { Refresh-AllMarketData -Force }
    Set-TransientStatus "Einstellungen gespeichert" 3
    if ($langChanged -and (Confirm-Action -Text "Die Sprache wirkt nach einem Neustart. Jetzt neu starten? / Restart now to switch the language?" -Title "Sprache / Language")) {
        Restart-Widget
        return
    }
    if (-not $langChanged -and $fontChanged -and -not $script:SmokeMode -and (Confirm-Action -Text (Tr "Schrift und Schriftgröße wirken nach einem Neustart. Jetzt neu starten?") -Title (Tr "Schrift"))) {
        Restart-Widget
        return
    }
    if ($hkChanged) {
        $hm = Register-GlobalHotkey
        if ($hm -and $hm -ne "aus") { Set-TransientStatus "Tastenkürzel: $hm" 6 }
    }
    if ($null -ne $then) { & $then }
}

# ---- v5.3: settings as a file (e.g. to move to a new PC) ----
function Export-SettingsFile {
    param([string]$Path = "")
    if (-not $Path) {
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "Einstellungen (*.json)|*.json"
        $sfd.FileName = "TerminalWidget-Einstellungen-{0}.json" -f (Get-Date -Format "yyyyMMdd")
        $sfd.Title = Tr "Einstellungen exportieren"
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { $sfd.Dispose(); return "" }
        $Path = $sfd.FileName
        $sfd.Dispose()
    }
    try {
        $x = ConvertTo-SettingsExport -Config $script:Config -Version $script:AppVersion
        [System.IO.File]::WriteAllText($Path, ($x | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
        Write-WidgetLog "Settings exported: $Path"
        Set-TransientStatus ("Einstellungen exportiert: {0}" -f [System.IO.Path]::GetFileName($Path)) 4
        return $Path
    } catch {
        Write-WidgetLog "Settings export failed: $($_.Exception.Message)" "ERROR"
        Show-InfoBox ("Export fehlgeschlagen: {0}" -f $_.Exception.Message) "Einstellungen"
        return ""
    }
}

function Import-SettingsFile {
    param([string]$Path = "", [switch]$NoRestart)
    if (-not $Path) {
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "Einstellungen (*.json)|*.json|Alle Dateien (*.*)|*.*"
        $ofd.Title = Tr "Einstellungen importieren"
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { $ofd.Dispose(); return $false }
        $Path = $ofd.FileName
        $ofd.Dispose()
    }
    $data = $null
    try { $data = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json } catch { $data = $null }
    $r = ConvertFrom-SettingsExport -Data $data -Defaults $script:ConfigDefaults
    if (-not $r.Ok) { Show-InfoBox ($(if ($r.Error) { $r.Error } else { "Die Datei konnte nicht gelesen werden." })) "Einstellungen importieren"; return $false }
    $txt = "{0} Einstellungen aus '{1}' übernehmen?`r`n`r`nDepots, Alarme und Transaktionen bleiben unverändert. Vorher wird ein Backup angelegt." -f $r.Settings.Count, [System.IO.Path]::GetFileName($Path)
    if (-not (Confirm-Action -Text $txt -Title "Einstellungen importieren")) { return $false }
    [void](Backup-DataFiles -Reason "vor_einstellungen_import")
    foreach ($k in @($r.Settings.Keys)) { $script:Config.$k = $r.Settings[$k] }
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    $script:SettingsIndexCache = $null
    Write-WidgetLog ("Settings imported from {0}: {1} keys, skipped {2}" -f $Path, $r.Settings.Count, (@($r.Skipped) -join ","))
    if ($NoRestart -or $script:SmokeMode) { try { Apply-ThemeToAllControls } catch { }; return $true }
    if (Confirm-Action -Text "Einstellungen übernommen. Das Widget startet jetzt neu, damit alles wirkt." -Title "Einstellungen importieren") { Restart-Widget }
    else { Apply-ThemeToAllControls }
    return $true
}

# ---- v5.5: one-line text input ----
function Read-TextPrompt {
    param([string]$Title, [string]$Prompt, [string]$Value = "")
    if ($script:SmokeMode) { return "Smoke" }
    $p = $script:Pal
    $dlg = New-DialogForm -Title $Title -W (S 400) -H (S 112)
    $l = New-Object System.Windows.Forms.Label
    $l.SetBounds((S 12), (S 10), (S 376), (S 18)); $l.Text = $Prompt; $l.ForeColor = $p.Muted
    $dlg.Controls.Add($l)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.SetBounds((S 12), (S 32), (S 376), (S 24)); $tb.MaxLength = 80; $tb.Text = $Value
    $tb.BackColor = $p.Input; $tb.ForeColor = $p.Text; $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $dlg.Controls.Add($tb)
    $bOk = New-Object System.Windows.Forms.Button
    $bOk.SetBounds((S 182), (S 72), (S 100), (S 28)); $bOk.Text = "OK"; $bOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Style-FlatButton -Btn $bOk -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $dlg.Controls.Add($bOk)
    $bCa = New-Object System.Windows.Forms.Button
    $bCa.SetBounds((S 288), (S 72), (S 100), (S 28)); $bCa.Text = "Abbrechen"; $bCa.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    Style-FlatButton -Btn $bCa -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $dlg.Controls.Add($bCa)
    $dlg.AcceptButton = $bOk; $dlg.CancelButton = $bCa
    $owner = if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed) { $script:FsForm } else { $form }
    $res = $dlg.ShowDialog($owner)
    $out = $tb.Text.Trim()
    $dlg.Dispose()
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) { return "" }
    return $out
}

# ---- v5.5: note per ticker ----
function Show-NoteDialog {
    param([string]$Ticker)
    $sym = ([string]$Ticker).Trim().ToUpper()
    if (-not $sym) { return }
    $p = $script:Pal
    $dlg = New-DialogForm -Title ("Notiz - {0}" -f $sym) -W (S 520) -H (S 330) -Key "Note"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 380), (S 240))
    $aAll = [System.Windows.Forms.AnchorStyles]"Top,Bottom,Left,Right"
    $aBR = [System.Windows.Forms.AnchorStyles]"Bottom,Right"
    $l = New-Object System.Windows.Forms.Label
    $l.SetBounds((S 12), (S 10), (S 490), (S 18)); $l.ForeColor = $p.Muted
    $n0 = $script:Notes[$sym]
    $l.Text = if ($null -ne $n0 -and $n0.Updated) { "{0} ({1} {2})" -f (Tr "These, Kaufgrund, Ziele - nur für dich"), (Tr "zuletzt"), $n0.Updated } else { Tr "These, Kaufgrund, Ziele - nur für dich" }
    $dlg.Controls.Add($l)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.SetBounds((S 12), (S 32), (S 494), (S 220)); $tb.Anchor = $aAll
    $tb.Multiline = $true; $tb.AcceptsReturn = $true; $tb.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $tb.BackColor = $p.Input; $tb.ForeColor = $p.Text; $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tb.MaxLength = 4000
    $tb.Text = Get-TickerNote $sym
    $dlg.Controls.Add($tb)
    $bDel = New-Object System.Windows.Forms.Button
    $bDel.SetBounds((S 12), (S 262), (S 100), (S 28)); $bDel.Anchor = [System.Windows.Forms.AnchorStyles]"Bottom,Left"
    Style-FlatButton -Btn $bDel -BgColor $p.Input -FgColor $p.Muted -BorderColor $p.Border
    $bDel.Text = "Löschen"
    $bDel.Add_Click({ $script:NoteTb.Text = "" })
    $dlg.Controls.Add($bDel)
    $bOk = New-Object System.Windows.Forms.Button
    $bOk.SetBounds((S 300), (S 262), (S 100), (S 28)); $bOk.Anchor = $aBR
    Style-FlatButton -Btn $bOk -BgColor $p.Accent -FgColor $p.HeaderBg -BorderColor $p.Accent
    $bOk.Text = "Speichern"; $bOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($bOk)
    $bCa = New-Object System.Windows.Forms.Button
    $bCa.SetBounds((S 406), (S 262), (S 100), (S 28)); $bCa.Anchor = $aBR
    Style-FlatButton -Btn $bCa -BgColor $p.Input -FgColor $p.Text -BorderColor $p.Border
    $bCa.Text = "Abbrechen"; $bCa.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($bCa)
    $dlg.CancelButton = $bCa
    $script:NoteTb = $tb
    $dlg.Add_Shown({ $script:NoteTb.Focus() | Out-Null; $script:NoteTb.SelectionStart = $script:NoteTb.Text.Length })
    Apply-Language $dlg
    $res = $dlg.ShowDialog($form)
    $txt = $tb.Text
    $script:NoteTb = $null
    $dlg.Dispose()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-TickerNote -Ticker $sym -Text $txt
        Set-TransientStatus $(if ($txt.Trim()) { "Notiz zu $sym gespeichert" } else { "Notiz zu $sym gelöscht" }) 3
    }
}

# ---- v5.5: HEALTH and diagnostics ----
function Get-HealthChecks {
    $checks = New-Object System.Collections.Generic.List[object]
    $add = { param($N, $St, $D) $checks.Add([PSCustomObject]@{ Name = $N; State = $St; Detail = $D }) }
    & $add "Version" "INFO" ("{0}, PowerShell {1}" -f $script:AppVersion, $PSVersionTable.PSVersion)
    & $add "Datenordner" "INFO" $script:DataDir
    # data files: present ones must parse
    $bad = @(); $okN = 0
    foreach ($fn in @(Get-DataFileNames)) {
        $fp = Join-Path $script:DataDir $fn
        if (-not (Test-Path $fp)) { continue }
        try { [void]([IO.File]::ReadAllText($fp) | ConvertFrom-Json); $okN++ } catch { $bad += $fn }
    }
    if ($bad.Count -gt 0) { & $add "Datendateien" "ERR" ("nicht lesbar: {0}" -f ($bad -join ", ")) } else { & $add "Datendateien" "OK" ("{0} Dateien lesbar" -f $okN) }
    try {
        $probe = Join-Path $script:DataDir ("health_" + [Guid]::NewGuid().ToString("N") + ".tmp")
        [IO.File]::WriteAllText($probe, "x"); Remove-Item $probe -Force
        & $add "Schreibrechte" "OK" "Datenordner beschreibbar"
    } catch { & $add "Schreibrechte" "ERR" $_.Exception.Message }
    # backups
    $newest = $null; $nB = 0
    if (Test-Path $script:BackupDir) {
        $bd = @(Get-ChildItem -Path $script:BackupDir -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        $nB = $bd.Count
        if ($nB -gt 0) { $newest = $bd[0].LastWriteTime }
    }
    $bh = Get-BackupHealth -Newest $newest
    & $add "Backups" $bh.State $(if ($null -eq $newest) { "keine Backups" } else { "{0} vorhanden, neuestes vor {1:N1} Tagen" -f $nB, $bh.Days })
    # data source
    $nq = $script:QuoteStore.Count
    $fresh = @($script:QuoteStore.Values | Where-Object { $null -ne $_ -and -not [bool]$_.FromCache }).Count
    $st = if ($nq -eq 0) { "WARN" } elseif ($fresh -eq 0) { "WARN" } else { "OK" }
    & $add "Datenquelle (Yahoo)" $st ("{0} Kurse, davon {1} live, {2} aus dem Cache" -f $nq, $fresh, ($nq - $fresh))
    # fonts
    & $add "Symbol-Schrift" $(if ($script:IconFont) { "OK" } else { "WARN" }) $(if ($script:IconFont) { [string]$script:IconFont } else { "nicht gefunden - Knöpfe zeigen Text" })
    $monoOk = ([string]$script:Config.MonoFont -eq "Consolas" -or $script:InstalledFonts -contains [string]$script:Config.MonoFont)
    & $add "Zahlen-Schrift" $(if ($monoOk) { "OK" } else { "WARN" }) ([string]$script:Config.MonoFont)
    # V6: data providers
    foreach ($pv in @("TwelveData", "Finnhub")) {
        if (-not (Get-ProviderKey $pv)) { & $add $pv "INFO" (Tr "kein Schlüssel"); continue }
        $caps = @(); $no = @()
        $pc = $script:Config.ProviderCaps
        if ($null -ne $pc -and $pc -isnot [string]) { foreach ($pp in $pc.PSObject.Properties) { if ($pp.Name -like "$pv|*") { if ([bool]$pp.Value) { $caps += $pp.Name.Split("|")[1] } else { $no += $pp.Name.Split("|")[1] } } } }
        $lim = (Get-ProviderLimits)[$pv]
        & $add $pv $(if ($caps.Count -eq 0 -and $no.Count -gt 0) { "WARN" } else { "OK" }) ("{0}: {1}{2}; {3} {4}{5}" -f (Tr "nutzbar"), $(if ($caps.Count -gt 0) { $caps -join ", " } else { Tr "noch nicht getestet (PROV)" }), $(if ($no.Count -gt 0) { " (" + (Tr "nicht") + ": " + ($no -join ", ") + ")" } else { "" }), (Get-ProviderDayCount $pv), (Tr "Anfragen heute"), $(if ($lim.PerDay -gt 0) { " / " + $lim.PerDay } else { "" }))
    }
    # v5.5: start time, memory, polling load
    if ($null -ne $script:StartupMs) { & $add "Startzeit" $(if ([int]$script:StartupMs -gt 15000) { "WARN" } else { "INFO" }) ("{0:N1} s bis zum Fenster" -f ([int]$script:StartupMs / 1000.0)) }
    if ($script:StartupParts) { & $add "Startzeit je Teil" "INFO" ($script:StartupParts -join ", ") }
    try {
        $pr0 = [System.Diagnostics.Process]::GetCurrentProcess()
        $mb = $pr0.WorkingSet64 / 1MB
        & $add "Speicher" $(if ($mb -gt 900) { "WARN" } else { "INFO" }) ("{0:N0} MB (Arbeitsspeicher), {1:N0} MB privat" -f $mb, ($pr0.PrivateMemorySize64 / 1MB))
    } catch { }
    $nReq = $script:FetchLog.Count
    $byP = @($script:FetchLog.ToArray() | Group-Object -Property P | Sort-Object Count -Descending | ForEach-Object { "{0} {1}" -f $_.Name, $_.Count })
    & $add "Abfragen" $(if ($nReq -gt 2000) { "WARN" } else { "INFO" }) ("{0} Anfragen in der letzten Stunde ({3}), Intervall {1} s / {2} s" -f $nReq, [int]$script:Config.RefreshSeconds, [int]$script:Config.SlowRefreshSeconds, $(if ($byP.Count -gt 0) { $byP -join ", " } else { "-" }))
    # log
    if (Test-Path $script:LogPath) {
        $lf = Get-Item $script:LogPath
        $errN = Get-LogErrorCount -Lines @(Get-Content -Path $script:LogPath -Tail 400 -ErrorAction SilentlyContinue) -ProcessId $PID
        & $add "Log" $(if ($errN -gt 0) { "WARN" } else { "OK" }) ("{0:N0} KB, {1} Fehler seit diesem Start (max. 400 Zeilen)" -f ($lf.Length / 1KB), $errN)
    }
    return $checks.ToArray()
}

function Show-HealthReport {
    $txt = Format-HealthReport -Checks (Get-HealthChecks) -Title (Tr "Zustand")
    $script:LastHealthText = $txt
    if ($script:SmokeMode) { Write-WidgetLog ("HEALTH`r`n" + $txt); return }
    Show-HelpTextDialog -Title ("{0} - {1}" -f (Tr "Zustand"), $script:AppTitle) -Text ($txt + "`r`n`r`n" + (Tr "OK = in Ordnung, !! = Warnung, XX = Fehler. DIAG exportiert eine Diagnose für Fehlerberichte."))
}

function Export-Diagnostics {
    # ZIP: log, config without secrets, health report, version - for bug reports
    param([string]$Path = "")
    if (-not $Path) {
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "ZIP-Archiv (*.zip)|*.zip"
        $sfd.FileName = "TerminalWidget_Diagnose_{0}.zip" -f (Get-Date -Format "yyyyMMdd_HHmm")
        if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { $sfd.Dispose(); return "" }
        $Path = $sfd.FileName
        $sfd.Dispose()
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("tw_diag_" + [Guid]::NewGuid().ToString("N"))
    try {
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        if (Test-Path $script:LogPath) { Copy-Item -Path $script:LogPath -Destination (Join-Path $tmp "widget.log") -Force }
        [IO.File]::WriteAllText((Join-Path $tmp "config-ohne-zugangsdaten.json"), ((Get-DiagnosticConfig $script:Config) | ConvertTo-Json -Depth 8), $utf8)
        [IO.File]::WriteAllText((Join-Path $tmp "zustand.txt"), (Format-HealthReport -Checks (Get-HealthChecks)), $utf8)
        $info = "Version {0}`r`nPowerShell {1}`r`nWindows {2}`r`nDPI {3}`r`nBildschirme {4}`r`nErstellt {5}" -f $script:AppVersion, $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString, $script:DpiScale, [System.Windows.Forms.Screen]::AllScreens.Count, (Get-Date -Format "yyyy-MM-dd HH:mm")
        [IO.File]::WriteAllText((Join-Path $tmp "version.txt"), $info, $utf8)
        if (Test-Path $Path) { Remove-Item $Path -Force }
        Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $Path -Force
        Write-WidgetLog "Diagnostics exported: $Path"
        Set-TransientStatus ("Diagnose gespeichert: {0} (ohne Depot-Daten und Zugangsdaten)" -f [IO.Path]::GetFileName($Path)) 6
        return $Path
    } catch {
        Write-WidgetLog "Diagnostics export failed: $($_.Exception.Message)" "ERROR"
        Show-InfoBox -Text ("Diagnose fehlgeschlagen: {0}" -f $_.Exception.Message) -Title "Diagnose"
        return ""
    } finally { Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Show-GlossaryDialog {
    # v4.0: searchable list of every explained term
    $dlg = New-DialogForm -Title "Glossar - $($script:AppTitle)" -W (S 640) -H (S 430) -Key "Glossary"
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 500), (S 300))
    $p = $script:Pal
    $aTL = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

    $lblF = New-Object System.Windows.Forms.Label
    $lblF.SetBounds((S 12), (S 15), (S 50), (S 18))
    $lblF.Text = "Suchen:"
    $dlg.Controls.Add($lblF)
    $tbF = New-Object System.Windows.Forms.TextBox
    $tbF.SetBounds((S 64), (S 12), (S 160), (S 24))
    $tbF.BackColor = $p.Input; $tbF.ForeColor = $p.Text; $tbF.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tbF.Anchor = $aTL
    $dlg.Controls.Add($tbF)

    $lb = New-Object System.Windows.Forms.ListBox
    $lb.SetBounds((S 12), (S 44), (S 212), (S 374))
    $lb.Anchor = $aTL -bor [System.Windows.Forms.AnchorStyles]::Bottom
    $lb.BackColor = $p.Input; $lb.ForeColor = $p.Text; $lb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $lb.IntegralHeight = $false
    $lb.DisplayMember = "Term"
    $dlg.Controls.Add($lb)

    $tx = New-Object System.Windows.Forms.TextBox
    $tx.SetBounds((S 234), (S 12), (S 394), (S 406))
    $tx.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
    $tx.Multiline = $true
    $tx.ReadOnly = $true
    $tx.WordWrap = $true
    $tx.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
    $tx.BackColor = $p.Card; $tx.ForeColor = $p.Text; $tx.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tx.Font = New-Object System.Drawing.Font("Segoe UI", 10.0)
    $dlg.Controls.Add($tx)

    $script:GlossCtl = @{ Filter = $tbF; List = $lb; Text = $tx; All = @(Get-GlossaryEntries | Sort-Object Term) }
    $fill = {
        $gc = $script:GlossCtl
        $f = $gc.Filter.Text.Trim()
        $gc.List.BeginUpdate()
        $gc.List.Items.Clear()
        foreach ($en in $gc.All) {
            if (-not $f -or $en.Term -like "*$f*" -or $en.Short -like "*$f*" -or $en.Long -like "*$f*") { [void]$gc.List.Items.Add($en) }
        }
        $gc.List.EndUpdate()
        if ($gc.List.Items.Count -gt 0) { $gc.List.SelectedIndex = 0 } else { $gc.Text.Text = "Kein Begriff gefunden." }
    }
    $script:GlossCtl.Fill = $fill
    $tbF.Add_TextChanged({ & $script:GlossCtl.Fill })
    $lb.Add_SelectedIndexChanged({
        $gc = $script:GlossCtl
        $en = $gc.List.SelectedItem
        if ($null -ne $en) { $gc.Text.Text = ($en.Term + "`r`n`r`n" + $en.Short + "`r`n`r`n" + $en.Long) }
    })
    & $fill
    $owner = if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed) { $script:FsForm } else { $form }
    [void]$dlg.ShowDialog($owner)
    $script:GlossCtl = $null
    $tx.Font.Dispose()
    $dlg.Dispose()
}

function Set-DarkScrollBars {
    # v7.1.1: scrollbars follow dark themes (Windows 10 1809+; otherwise unchanged)
    param([System.Windows.Forms.Control]$Control)
    if (-not [int]$script:Pal.DwmDark) { return }
    try {
        if (-not ("TwUxThemeV71" -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TwUxThemeV71 {
    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    public static extern int SetWindowTheme(IntPtr hWnd, string subApp, string subId);
}
"@ -ErrorAction Stop
        }
        [void][TwUxThemeV71]::SetWindowTheme($Control.Handle, "DarkMode_Explorer", [NullString]::Value)
    } catch { Write-WidgetLog "Dark scrollbars not available: $($_.Exception.Message)" "WARN" }
}

# v5.0: the help outgrew a message box - scrollable, resizable window
function Show-HelpTextDialog {
    param([string]$Title, [string]$Text)
    $p = $script:Pal
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $dlg = New-DialogForm -Title $Title -W ([math]::Min((S 640), $wa.Width - 40)) -H ([math]::Min((S 640), $wa.Height - 60))
    $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
    $dlg.MinimumSize = New-Object System.Drawing.Size((S 420), (S 300))
    if ($null -ne $form.Icon) { $dlg.Icon = $form.Icon }   # v7.1.1: not the default Windows icon
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.WordWrap = $false
    $tb.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $tb.BackColor = $p.BodyBg; $tb.ForeColor = $p.Text; $tb.Font = $fontMono
    $tb.Text = ($Text -replace "`r?`n", "`r`n")
    $tb.SetBounds((S 12), (S 10), ($dlg.ClientSize.Width - (S 24)), ($dlg.ClientSize.Height - (S 56)))
    $tb.Anchor = [System.Windows.Forms.AnchorStyles]"Top, Bottom, Left, Right"
    $tb.Add_HandleCreated({ param($sender, $e) Set-DarkScrollBars $sender })
    $dlg.Controls.Add($tb)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "Schließen"
    $ok.SetBounds(($dlg.ClientSize.Width - (S 112)), ($dlg.ClientSize.Height - (S 38)), (S 100), (S 28))
    $ok.Anchor = [System.Windows.Forms.AnchorStyles]"Bottom, Right"
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    Style-FlatButton -Btn $ok -BgColor $p.Input -FgColor $p.Accent -BorderColor $p.Border
    $dlg.Controls.Add($ok)
    $dlg.AcceptButton = $ok; $dlg.CancelButton = $ok
    $dlg.Add_Shown({ param($sender, $e) $sender.ActiveControl = $sender.AcceptButton })
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
}

