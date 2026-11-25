# TerminalWidget UI part 12 (Shell) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM. Part of the former single-file script (split in V7.0).

function Show-ShortcutHelp {
    if ([string]$script:Config.Language -eq "EN") {
        $txtEn = @"
Keyboard shortcuts

F1 - F4         Chart / Portfolio / Watch & alerts / News
F5              Refresh now
Ctrl+F          Search ticker
Ctrl+K          Command line (also numpad /)
Ctrl+Z          Undo the last deletion (10 seconds)
Ctrl+Y          Redo (30 seconds)
Ctrl+C          Copy the whole list as a table
F9              Privacy mode (hide amounts; Fn+F9 on many laptops)
Shift+F2/F3/F4  Terminal layout: list as a full page (Esc = back)
Ctrl+Alt+W      Show / hide the widget from anywhere
Left / Right    Previous / next watchlist ticker
1 - 6           Range 1D / 5D / 1M / 3M / 6M / 1Y
F11             Fullscreen chart

K  line / candles      V  volume
M  SMA/EMA             A  VWAP
B  Bollinger           R  RSI / MACD
E  pre/post market     W  currency
T  theme               C  compact on/off
L  next layout         G  glossary
P  portfolio analysis  S  settings
H  this help           Z  reset zoom   X  compare
Y  log scale           (diamond in the chart = ex-dividend)

Command line: NVDA, NVDA GP 1Y, NVDA DES, NVDA N, NVDA DVD,
NVDA EE, NVDA ALRT TRAIL 8, NVDA WL, PORT, ANA, DVD, CAL, TOP,
NEWS, NEWS DEPOT, NEWS WATCH, NEWS NVDA,
FX, LOG, REP, TF 3M, LAYOUT TERMINAL, LAYOUT SAVE <name>,
IND MACD, PF <depot>, IMP, BAK, SET, PUSH, ABOUT, TOUR

Right-click a column header = choose columns, drag = reorder.
Hover over controls for explanations (glossary is German).

New in 5.0
K               Line / candles / Heikin-Ashi
D               Draw a trend line (right-click chart > Draw:
                horizontal line, Fibonacci, alert on a line)
X               Compare - up to 3 tickers (right-click a ticker)
Terminal        Drag the dividers between chart and lists,
                double-click = default sizes
Watchlist       Group drop-down next to the title,
                right-click a ticker > To group
Hover card      Rest the mouse on a ticker
Settings        "Search:" at the bottom lights up matches
Portfolio (v)   Cash account, savings plans
P               Risk, target weights (rebalancing), heatmap
Commands        CASH SPAR REBAL RISK HEAT DRAW H/T/F FULL PRIV

New in 5.1
W               Auto (each price + chart in the ticker's currency,
                depot stays in the base currency) / EUR / USD / CHF / GBP
NVDA TA         Ticker analysis: signals, support / resistance,
                fundamentals vs. your tickers of the same sector
                (also right-click a ticker or the chart)
P               Beitrag (contribution, dividends, scenario),
                Vergleich (indices, rolling 12M, sectors vs. MSCI World)

New in 5.2
STYLE           Refined / Fresh design (also Settings > Design:
                row height, zebra rows, icons, ticker bar speed)
THEME GRAPHITE  neutral grey theme; accent colour "Windows"

New in 5.3
Settings        eight pages: Display, Design, Layout, Data & refresh,
                Alerts & notifications, Depot, Keyboard & commands, Other
Style           at the top of Settings > Design; also in the layout
                menu (top right), the tray menu and the STYLE command
Search          finds settings on every page ("style", "push", ...);
                a dot = changed from default, "Reset page" button
Ctrl+K          also finds every setting (SET ...) and menu entry (MENU ...)
Other           export / import the settings as a file (new PC)

New in 5.5
NVDA NOTE       note per ticker (also right-click, hover card, TA window)
HEALTH / DIAG   health check / diagnostics ZIP for bug reports
IMG             chart as image (IMG SAVE, IMG WIN = whole window)
SCALE PCT       percent axis from the first visible bar
Ctrl+drag       zoom into the marked range (Z = reset)
DRAW R / N      zone (rectangle) / text note; fullscreen chart toolbar
P > Einkommen   received dividends as a month calendar; Export button
Scenario        per sector or currency (Beitrag page)
Savings plans   yearly increase (%) and pause months
Watchlist       column "Signal" (header right-click), clock = stale price

New in 5.7
NVDA TA         daily and weekly signals side by side, one sentence for both;
                valuation vs. the ticker's own history (grows from now on)
NVDA PEER AMD   own peer group for the comparison column (PEER - = sector)
Signals         once a day: note when a depot ticker's signal turns, or the
                price crosses support / resistance (Settings > Alerts)
Chart           with support / resistance on: 50/200-day crossings (triangles)
News            own RSS / Atom feeds (Settings > Data & refresh)
THEME CONTRAST  high contrast; HEALTH shows requests per data source

New in 6.0
Settings        Data & refresh: own Twelve Data / Finnhub API keys (free)
PROV            test which data your keys deliver (only that is used)
Fallback        no Yahoo history -> Twelve Data -> Finnhub (US, free tiers)
NVDA TA         with Finnhub: figures over the years, valuation vs. quarterly
                history, earnings surprise + price reaction, analyst trend
Limits          per-minute / per-day budgets kept, message when reached
"@
        Show-HelpTextDialog -Title "Help - $($script:AppTitle)" -Text $txtEn
        return
    }
    $txt = @"
Tastenkürzel

F1 - F4         Chart / Portfolio / Watch & Alarm / News
F5              Jetzt aktualisieren
Ctrl+F          Ticker suchen
Links / Rechts  Vorheriger / nächster Watchlist-Ticker
Mausrad (Chart) Zeitraum wechseln
1 - 6           Zeitraum 1D / 5D / 1M / 3M / 6M / 1Y
F11             Chart im Vollbild (auch Doppelklick auf Chart)

Y  Log-Skala an/aus     (Raute im Chart = Ex-Dividende)
K  Linie / Kerzen       V  Volumen
M  SMA                  A  VWAP
B  Bollinger            R  RSI
E  Vor-/Nachbörse      W  Währung (EUR/USD/CHF/GBP)
T  Theme                C  Compact an/aus
L  Nächstes Layout     G  Glossar (Begriffe)
P  Portfolio-Analyse (Wertentwicklung, Rendite,
   Aufteilung, Dividenden, Kaufdaten nachtragen)
S  Einstellungen        H  Diese Hilfe
Z  Zoom zurücksetzen   X  Vergleich an/aus
Esc  Messung / Popups / Vollbild schließen

Layouts (Button rechts oben oder L):
Ticker    nur Kurs + Mini-Chart, rahmenlos
Compact   Leiste mit Marktstatus und Laufband
Standard  Fenster mit Tabs
Terminal  Chart oben, Watchlist + Portfolio darunter
          (oder die News: F4 / NEWS)
          Tab einer sichtbaren Liste nochmal klicken
          (oder Shift+F2/F3/F4) = Liste als ganze Seite,
          F1 / Esc = zurück

F9 (am Laptop oft Fn+F9) oder Augen-Knopf im Portfolio:
Privat-Modus (Beträge aus), Ctrl+Y: wiederholen,
Ctrl+C in einer Liste: ganze Tabelle kopieren.
Rechtsklick auf einen Ticker (Watchlist / Portfolio):
Chart, Alarm, Kauf buchen, News, Vergleich, DES.
Rechtsklick auf einen Alarm: pausieren (1 h / 4 h / morgen).
Punkt links von der Statuszeile: grün = Daten ok,
gelb = Pause / veraltet, rot = keine Verbindung.

News (F4): Meldungen zu Depot und Watchlist, neue fett,
die Zahl am Tab = ungelesen. Doppelklick = Artikel,
Klick auf den Ticker = Ticker öffnen. NEWS DEPOT /
NEWS WATCH / NEWS NVDA filtern, NVDA N = Einzelfenster.

Erklärungen: Maus auf Bedienelemente, Spaltenköpfe oder
die Legende im Chart (SMA, VWAP, RSI ...) halten.
Ausführlichkeit und Verzögerung in den Einstellungen.

Chart:
Strg + Mausrad    Zoomen (um die Mausposition)
Umschalt + Mausrad  Ausschnitt verschieben
Linke Maus ziehen   Messen (Differenz, %, Bars, Dauer)
Rechtsklick         Alarm auf diesem Kurs setzen

Doppelklick auf Kurs = Kurs kopieren
Header ziehen = Fenster verschieben
Marktstatus: Maus über die Statuszeile = Handelszeiten
Chart: Fadenkreuz zeigt Kurs (rechts) und Zeit (unten) an der Maus
Compact-Laufleiste: Klick = Ticker öffnen, Maus darüber = Pause
Ticker in Orange = Quartalszahlen in den nächsten 7 Tagen

Befehlszeile (Strg+K oder Num-/):
NVDA          Ticker öffnen      NVDA GP 1Y  Chart + Zeitraum
NVDA DES      Beschreibung       NVDA N      Nachrichten
NVDA DVD      Dividenden         NVDA EE     Termine
NVDA ALRT TRAIL 8 / >= 150 / TAG- 3 / 52H / VOL 2
NVDA WL / CMP / TX   Watchlist / Vergleich / Transaktion
PORT  ANA  DVD  CAL  TOP  FX  LOG  REP  TF 3M  LAYOUT TERMINAL
THEME OLED  SET  PUSH  GLOS  ABOUT  PF <Depot>  IMP  BAK  SCALE LOG
IND MACD/EMA  LAYOUT SAVE <Name>  CT (Durchklicken)  TOUR

Strg+Z         Löschen rückgängig (10 Sekunden)
Strg+Alt+W     Widget von überall zeigen / verstecken
Rechtsklick auf Spaltenkopf = Spalten wählen, Kopf ziehen = Reihenfolge

Alarme: Kurs, Tag%, RSI, SMA, Trailing-Stopp, EK%, 52W-Hoch/-Tief,
Volumen-Spitze, Depotwert und Depot-Tag%. "Verlauf" zeigt alle
Treffer. Handy-Push (ntfy/Telegram) und Ruhezeit: Einstellungen.

Neu in 5.0
K               Linie / Kerzen / Heikin-Ashi
D               Trendlinie zeichnen (Rechtsklick Chart > Zeichnen:
                Horizontale, Fibonacci, Alarm auf eine Linie)
X               Vergleich - bis zu 3 Ticker (Rechtsklick auf Ticker)
Terminal        Trennlinien zwischen Chart und Listen ziehen,
                Doppelklick = Standardgrößen
Watchlist       Gruppen-Auswahl neben dem Titel,
                Rechtsklick auf Ticker > Zu Gruppe
Infokarte       Maus auf einem Ticker ruhen lassen
Einstellungen   "Suchen:" unten hebt passende Optionen hervor
Portfolio (v)   Cash-Konto, Sparpläne
P               Risiko, Ziel-Gewichte (Rebalancing), Heatmap
Befehle         CASH SPAR REBAL RISK HEAT DRAW H/T/F FULL PRIV

Neu in 5.1
W               Auto (jeder Kurs + Chart in der Währung des Tickers,
                Depot bleibt in der Basiswährung) / EUR / USD / CHF / GBP
NVDA TA         Ticker-Analyse: Signale, Unterstützung / Widerstand,
                Kennzahlen gegen deine Ticker aus derselben Branche
                (auch Rechtsklick auf Ticker oder Chart)
P               Beitrag (je Position, Dividenden, Szenario),
                Vergleich (Indizes, rollierend 12 M, Sektoren vs. MSCI World)

Neu in 5.2
STYLE           Design Refined / Fresh (auch Einstellungen > Design:
                Zeilenhöhe, Zebra-Zeilen, Symbole, Tempo der Laufleiste)
THEME GRAPHITE  neutrales Grau; Akzentfarbe "Windows"

Neu in 5.3
Einstellungen   acht Seiten: Darstellung, Design, Layout, Daten &
                Aktualisierung, Alarme & Benachrichtigungen, Depot,
                Tastatur & Befehle, Sonstiges
Stil            ganz oben in Einstellungen > Design; auch im Layout-Menü
                (rechts oben), im Tray-Menü und mit dem Befehl STYLE
Suchen          findet Einstellungen auf allen Seiten ("stil", "push" ...);
                Punkt = vom Standard geändert, Knopf "Seite zurücksetzen"
Strg+K          findet auch jede Einstellung (SET ...) und jeden
                Menüeintrag (MENU ...)
Sonstiges       Einstellungen als Datei exportieren / importieren (neuer PC)

Neu in 5.5
NVDA NOTE       Notiz zum Ticker (auch Rechtsklick, Infokarte, TA-Fenster)
HEALTH / DIAG   Zustand prüfen / Diagnose als ZIP für Fehlerberichte
IMG             Chart als Bild (IMG SAVE, IMG WIN = ganzes Fenster)
SCALE PCT       Prozent-Achse ab dem ersten sichtbaren Balken
Strg+Ziehen     in den markierten Bereich zoomen (Z = zurück)
DRAW R / N      Zone (Rechteck) / Textnotiz; Werkzeugleiste im Vollbild
P > Einkommen   erhaltene Dividenden als Monatskalender; Knopf Export
Szenario        je Sektor oder Währung (Seite Beitrag)
Sparpläne       Dynamik (% pro Jahr) und Pausenmonate
Watchlist       Spalte "Signal" (Rechtsklick auf Kopf), Uhr = alter Kurs

Neu in 5.7
NVDA TA         Tages- und Wochensignale nebeneinander, ein Satz für beide;
                Bewertung vs. eigene Historie des Tickers (wächst ab jetzt)
NVDA PEER AMD   eigene Vergleichsgruppe für die Spalte Vergleich (PEER - = Sektor)
Signale         einmal am Tag: Hinweis, wenn das Signal eines Depot-Tickers
                kippt oder der Kurs Unterstützung / Widerstand kreuzt
Chart           mit Unterstützung / Widerstand: 50/200-Tage-Kreuzungen (Dreiecke)
Nachrichten     eigene RSS- / Atom-Feeds (Einstellungen > Daten)
THEME CONTRAST  hoher Kontrast; HEALTH zeigt Anfragen je Datenquelle

Neu in 6.0
Einstellungen   Daten & Aktualisierung: eigene Twelve-Data- / Finnhub-Schlüssel
PROV            prüft, was deine Schlüssel liefern (nur das wird genutzt)
Ausweichen      kein Yahoo-Verlauf -> Twelve Data -> Finnhub (US, kostenlos)
NVDA TA         mit Finnhub: Kennzahlen über Jahre, Bewertung vs. Quartals-
                Historie, Quartalszahlen mit Kursreaktion, Analysten-Trend
Limits          Minuten- / Tagesbudget wird eingehalten, Hinweis wenn erreicht
"@
    Show-HelpTextDialog -Title "Hilfe - $($script:AppTitle)" -Text $txt
}

$btnToggleExt.Add_Click({ Toggle-ExtendedHours })
$btnSettings.Add_Click({ Show-SettingsDialog })

$lblLivePrice.Add_DoubleClick({
    $cmiCopyPrice.PerformClick()
    Set-TransientStatus "Kurs in Zwischenablage kopiert" 3
})

# Remember the window position right after it was moved (not only on close)
$form.Add_ResizeEnd({
    if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) {
        $script:Config.WindowX = $form.Location.X
        $script:Config.WindowY = $form.Location.Y
        Save-WindowSize
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
    }
})
# Live re-layout while dragging the border and on maximize / restore
$script:StartupDone = $false
$form.Add_Resize({
    Update-MainLayout
    # Remember "maximized" (restored on the next start)
    if ($script:StartupDone -and -not [bool]$script:Config.CompactMode -and $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
        $isMax = ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized)
        if ($isMax -ne [bool]$script:Config.WindowMaximized) {
            $script:Config.WindowMaximized = $isMax
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
        }
    }
})

$btnRefreshNow.Add_Click({
    Refresh-AllMarketData -Force
    Evaluate-GlobalAlerts
    Update-AllUiViews
})

$btnThemeCycle.Add_Click({
    $script:Config.Theme = Get-NextTheme $script:Config.Theme
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Apply-ThemeToAllControls
})

$cmbRefresh.Add_SelectedIndexChanged({
    if ($null -ne $cmbRefresh.SelectedItem) {
        $sec = [int](([string]$cmbRefresh.SelectedItem).Replace("s", ""))
        if ($sec -ge 5) {
            $script:Config.RefreshSeconds = $sec
            $pollTimer.Interval = $sec * 1000
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
        }
    }
})

$btnCurrency.Add_Click({
    $lstTickerDropdown.Visible = $false
    $lstCurrencyDropdown.Visible = -not $lstCurrencyDropdown.Visible
    if ($lstCurrencyDropdown.Visible) {
        $idx = if ([bool]$script:Config.AutoCurrency) { 0 } else { $lstCurrencyDropdown.Items.IndexOf($script:Config.Currency) }
        if ($idx -ge 0) { $lstCurrencyDropdown.SelectedIndex = $idx }
        $lstCurrencyDropdown.BringToFront()
        $lstCurrencyDropdown.Focus()
    }
})

$lstCurrencyDropdown.Add_Click({
    if ($null -ne $lstCurrencyDropdown.SelectedItem) {
        Set-ActiveCurrency -NewCurrency ([string]$lstCurrencyDropdown.SelectedItem)
    }
})

$lstCurrencyDropdown.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $null -ne $lstCurrencyDropdown.SelectedItem) {
        $e.SuppressKeyPress = $true
        Set-ActiveCurrency -NewCurrency ([string]$lstCurrencyDropdown.SelectedItem)
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $lstCurrencyDropdown.Visible = $false
    }
})

$btnPin.Add_Click({
    $script:Config.TopMost = -not $script:Config.TopMost
    $form.TopMost = $script:Config.TopMost
    $p = $script:Pal
    Style-FlatButton -Btn $btnPin `
        -BgColor $(if ($script:Config.TopMost) { $p.Accent } else { $p.Input }) `
        -FgColor $(if ($script:Config.TopMost) { $p.HeaderBg } else { $p.Text }) `
        -BorderColor $(if ($script:Config.TopMost) { $p.Accent } else { $p.Border })
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
})

$btnCompact.Add_Click({
    Update-LayoutButton
    $layoutMenu.Show($btnCompact, (New-Object System.Drawing.Point(0, $btnCompact.Height)))
})
$layoutMenu.Add_ItemClicked({
    param($sender, $e)
    $sender.Close()
    Invoke-LayoutMenuTag ([string]$e.ClickedItem.Tag)
})
function Invoke-LayoutMenuTag {
    # v5.3: shared by the menu and by MENU <name> in Ctrl+K
    param([string]$Tag)
    if ($tag -like "Layout:*") {
        Apply-Layout ($tag.Substring(7))
    } elseif ($tag -like "Style:*") {
        [void](Invoke-TerminalCommand ("STYLE " + $tag.Substring(6).ToUpper()))
        Update-LayoutButton
    } elseif ($tag -eq "Settings") {
        Show-SettingsDialog
    } elseif ($tag -eq "Opt:Watch" -or $tag -eq "Opt:Portfolio") {
        if ($tag -eq "Opt:Watch") { $script:Config.TerminalShowWatch = -not [bool]$script:Config.TerminalShowWatch }
        else { $script:Config.TerminalShowPortfolio = -not [bool]$script:Config.TerminalShowPortfolio }
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        Update-LayoutButton
        if ([string]$script:Config.Layout -eq "Terminal") { Update-MainLayout }
    }
}

$btnTray.Add_Click({ $form.Hide() })
function Show-MainWindow {
    $form.Show()
    if (-not $script:MainA11yDone) { $script:MainA11yDone = $true; Set-AccessibilityDefaults $form -NoTabOrder }
    # back to maximized if it was maximized (was: always "Normal")
    $form.WindowState = if ([bool]$script:Config.WindowMaximized -and -not [bool]$script:Config.CompactMode) { [System.Windows.Forms.FormWindowState]::Maximized } else { [System.Windows.Forms.FormWindowState]::Normal }
    $form.Activate()
    Update-AllUiViews
}
$miShow.Add_Click({ Show-MainWindow })
$trayMenu.Add_Opening({
    foreach ($it in $miLayout.DropDownItems) { $it.Checked = ([string]$it.Tag -eq [string]$script:Config.Layout) }
    foreach ($it in $miStyle.DropDownItems) { $it.Checked = ([string]$it.Tag -eq [string]$script:Config.UiStyle) }
})
$miRefresh.Add_Click({ Refresh-AllMarketData -Force; Evaluate-GlobalAlerts; Update-AllUiViews })
$miExit.Add_Click({ $trayIcon.Visible = $false; $form.Close() })
$trayIcon.Add_DoubleClick({ Show-MainWindow })

# Chart Context Menu Actions
$cmiCopyPrice.Add_Click({
    $sym = $script:Config.ActiveTicker.ToUpper()
    if ($script:QuoteStore.ContainsKey($sym)) {
        $q = $script:QuoteStore[$sym]
        $pcc = Get-PriceCurrency $sym
        $p = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $pcc
        [System.Windows.Forms.Clipboard]::SetText(("{0}: {1:N2} {2}" -f $sym, $p, $pcc))
    }
})
$cmiTa.Add_Click({ Show-TickerAnalysis ([string]$script:Config.ActiveTicker) })
$cmiAddWatch.Add_Click({
    [void](Add-SymbolToWatchlist -RawSymbol $script:Config.ActiveTicker)
})
$cmiExportCsv.Add_Click({ $btnExportCsv.PerformClick() })
$cmiFullscreen.Add_Click({ Toggle-ChartFullscreen })
$cmiImgCopy.Add_Click({ [void](Export-ChartImage -Mode "Copy") })
$cmiImgSave.Add_Click({ [void](Export-ChartImage -Mode "Save") })
$cmiWinCopy.Add_Click({ [void](Export-ControlImage -Ctl $form -Mode "Copy") })
function Export-ChartImage {
    param([string]$Mode = "Copy", [string]$Path = "")
    $c = if ($null -ne $script:FsForm -and -not $script:FsForm.IsDisposed -and $script:FsForm.Visible) { $script:FsForm } else { $pnlChartCanvas }
    return (Export-ControlImage -Ctl $c -Mode $Mode -Name ("Chart_" + ([string]$script:Config.ActiveTicker).ToUpper()) -Path $Path)
}

# ==============================================================================
# v5.0 Stage B: drawings in the chart (horizontal line, trend line, Fibonacci)
# saved per ticker in drawings.json as (time, price in the ticker's currency),
# so they survive zoom, timeframe and display currency changes.
# ==============================================================================
$script:DrawingsPath = Join-Path $script:DataDir "drawings.json"
$script:Drawings = @{}
$script:DrawMode = ""
$script:DrawPending = $null
$script:DrawMouse = $null
$script:CtxDrawing = $null
$script:DrawingsSig = ""
function Read-Drawings {
    $script:Drawings = @{}
    $raw = Load-JsonState -Path $script:DrawingsPath -DefaultValue $null
    if ($null -eq $raw) { return }
    foreach ($pp in $raw.PSObject.Properties) {
        $l = New-Object System.Collections.Generic.List[object]
        foreach ($d in @($pp.Value)) {
            if ($null -eq $d -or -not $d.Kind) { continue }
            $l.Add([PSCustomObject]@{ Id = [string]$d.Id; Kind = [string]$d.Kind; T1 = [long]$d.T1; P1 = [double]$d.P1; T2 = [long]$d.T2; P2 = [double]$d.P2; Cur = [string]$d.Cur; Text = [string]$d.Text })
        }
        if ($l.Count -gt 0) { $script:Drawings[([string]$pp.Name).ToUpper()] = $l }
    }
    Update-DrawingsSig
}
function Save-Drawings {
    $o = [ordered]@{}
    foreach ($k in @($script:Drawings.Keys | Sort-Object)) { if ($script:Drawings[$k].Count -gt 0) { $o[$k] = $script:Drawings[$k].ToArray() } }
    Save-JsonState -Path $script:DrawingsPath -Data ([PSCustomObject]$o)
    Update-DrawingsSig
}
function Update-DrawingsSig {
    $dl = $script:Drawings[([string]$script:Config.ActiveTicker).ToUpper()]
    $script:DrawingsSig = if ($null -eq $dl) { "0" } else { "{0}|{1}" -f $dl.Count, (@($dl | ForEach-Object { $_.Id }) -join ",") }
}

function Set-DrawMode {
    param([string]$Mode)
    $script:DrawMode = $Mode
    $script:DrawPending = $null
    $script:DrawMouse = $null
    $cur = if ($Mode) { [System.Windows.Forms.Cursors]::Cross } else { [System.Windows.Forms.Cursors]::Default }
    $pnlChartCanvas.Cursor = $cur
    if ($null -ne $script:FsCanvas -and -not $script:FsCanvas.IsDisposed) { $script:FsCanvas.Cursor = $cur }
    switch ($Mode) {
        "H" { Set-TransientStatus "Horizontale Linie: in den Chart klicken (Esc = abbrechen)" 8 }
        "T" { Set-TransientStatus "Trendlinie: Startpunkt klicken, dann Endpunkt (Esc = abbrechen)" 8 }
        "F" { Set-TransientStatus "Fibonacci: Anfang der Bewegung klicken, dann das Ende (Esc = abbrechen)" 8 }
        "R" { Set-TransientStatus "Zone: eine Ecke klicken, dann die gegenüberliegende (Esc = abbrechen)" 8 }
        "N" { Set-TransientStatus "Textnotiz: in den Chart klicken, dann Text eingeben (Esc = abbrechen)" 8 }
    }
    $pnlChartCanvas.Invalidate()
}

function Get-ChartPointAt {
    # Mouse position -> @{ T (ms); P (display currency) } on the visible chart, or $null
    param($L, [int]$X, [int]$Y)
    $pr = $L.PriceRect
    $my = $Y - [int]$L.OffsetY
    if ($L.N -lt 2 -or $X -lt $pr.Left -or $X -gt $pr.Right -or $my -lt $pr.Top -or $my -gt $pr.Bottom) { return $null }
    $ts = [long[]]@($L.Series | ForEach-Object { [long]$_.Ts })
    $fi = ($X - $pr.Left) / [double]$pr.Width * ($L.N - 1)
    $p = Get-PriceFromFrac (($pr.Bottom - $my) / [double]$pr.Height) ([double]$L.MinP) ([double]$L.SpanP) ([bool]$L.LogScale)
    return [PSCustomObject]@{ T = (Get-TsAtFracIndex -BarTs $ts -Idx $fi); P = $p }
}

function Get-DrawingPixels {
    # Drawing -> pixel coordinates on a chart layout (display currency)
    param($L, $D)
    $pr = $L.PriceRect
    $ts = [long[]]@($L.Series | ForEach-Object { [long]$_.Ts })
    $fx = Convert-CurrencyValue -Amount 1.0 -FromCurrency ([string]$D.Cur) -ToCurrency ([string]$script:ChartCur)
    $toY = { param([double]$P) $pr.Bottom - ((Get-PriceFrac ($P * $fx) ([double]$L.MinP) ([double]$L.SpanP) ([bool]$L.LogScale)) * $pr.Height) }
    $toX = { param([long]$T) $pr.Left + ((Get-FracIndexAtTs -BarTs $ts -Ts $T) / [double]([math]::Max(1, $L.N - 1))) * $pr.Width }
    $x1 = & $toX $D.T1; $y1 = & $toY $D.P1
    $x2 = if ($D.Kind -eq "H") { $pr.Right } elseif ($D.Kind -eq "N") { $x1 } else { & $toX $D.T2 }
    $y2 = if ($D.Kind -in @("H", "N")) { $y1 } else { & $toY $D.P2 }
    return [PSCustomObject]@{ X1 = $x1; Y1 = $y1; X2 = $x2; Y2 = $y2; Fx = $fx }
}

function Find-DrawingAt {
    param($L, [int]$X, [int]$Y, [int]$Tol = 6)
    $dl = $script:Drawings[([string]$script:Config.ActiveTicker).ToUpper()]
    if ($null -eq $dl -or $L.N -lt 2) { return $null }
    $my = $Y - [int]$L.OffsetY
    $best = $null; $bd = [double](S $Tol)
    foreach ($d in $dl) {
        $px = Get-DrawingPixels -L $L -D $d
        $dist = switch ($d.Kind) {
            "H" { [math]::Abs($my - $px.Y1) }
            "T" { Get-PointLineDistance -X $X -Y $my -X1 $px.X1 -Y1 $px.Y1 -X2 $px.X2 -Y2 $px.Y2 -Ray $true }
            "R" { if (Test-PointInZone -X $X -Y $my -X1 $px.X1 -Y1 $px.Y1 -X2 $px.X2 -Y2 $px.Y2 -Tol (S 3)) { 0 } else { [double]::MaxValue } }
            "N" { if (Test-PointInZone -X $X -Y $my -X1 ($px.X1 - (S 4)) -Y1 ($px.Y1 - (S 20)) -X2 ($px.X1 + (S 170)) -Y2 ($px.Y1 + (S 4))) { 0 } else { [double]::MaxValue } }
            default {
                $m = [double]::MaxValue
                foreach ($lv in (Get-FibLevels -P1 $d.P1 -P2 $d.P2)) {
                    $yy = $L.PriceRect.Bottom - ((Get-PriceFrac ($lv.Price * $px.Fx) ([double]$L.MinP) ([double]$L.SpanP) ([bool]$L.LogScale)) * $L.PriceRect.Height)
                    if ($X -ge [math]::Min($px.X1, $px.X2) - 4) { $m = [math]::Min($m, [math]::Abs($my - $yy)) }
                }
                $m
            }
        }
        if ($dist -le $bd) { $bd = $dist; $best = $d }
    }
    return $best
}

function Add-Drawing {
    param([string]$Kind, $A, $B = $null, [string]$Text = "")
    $u = ([string]$script:Config.ActiveTicker).ToUpper()
    $nat = if ($script:ActiveNativeCurr) { [string]$script:ActiveNativeCurr } else { [string]$script:ChartCur }
    $back = Convert-CurrencyValue -Amount 1.0 -FromCurrency ([string]$script:ChartCur) -ToCurrency $nat
    $d = [PSCustomObject]@{ Id = [Guid]::NewGuid().ToString("N").Substring(0, 12); Kind = $Kind; T1 = [long]$A.T; P1 = [double]$A.P * $back; T2 = 0L; P2 = 0.0; Cur = $nat; Text = $Text }
    if ($null -ne $B) { $d.T2 = [long]$B.T; $d.P2 = [double]$B.P * $back }
    if (-not $script:Drawings.ContainsKey($u)) { $script:Drawings[$u] = New-Object System.Collections.Generic.List[object] }
    $script:Drawings[$u].Add($d)
    Save-Drawings
    $script:ChartSignature = ""
    Update-ChartCacheSignature
    $pnlChartCanvas.Invalidate()
    if ($null -ne $script:FsCanvas -and -not $script:FsCanvas.IsDisposed) { $script:FsCanvas.Invalidate() }
}

function Remove-Drawing {
    param($D, [switch]$All)
    $u = ([string]$script:Config.ActiveTicker).ToUpper()
    if ($All) { [void]$script:Drawings.Remove($u) }
    elseif ($null -ne $D -and $script:Drawings.ContainsKey($u)) {
        for ($i = 0; $i -lt $script:Drawings[$u].Count; $i++) { if ($script:Drawings[$u][$i].Id -eq $D.Id) { $script:Drawings[$u].RemoveAt($i); break } }
    }
    Save-Drawings
    $script:ChartSignature = ""
    Update-ChartCacheSignature
    $pnlChartCanvas.Invalidate()
}

function Draw-ChartDrawings {
    # Static layer: all drawings of the active ticker
    param([System.Drawing.Graphics]$g, $L)
    $dl = $script:Drawings[([string]$script:Config.ActiveTicker).ToUpper()]
    if ($null -eq $dl -or $dl.Count -eq 0 -or $L.N -lt 2) { return }
    $pr = $L.PriceRect
    $col = $script:Pal.Mark
    $pen = New-Object System.Drawing.Pen($col, [float]1.5)
    $fibPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(160, $col.R, $col.G, $col.B), [float]1)
    $fibPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $br = New-Object System.Drawing.SolidBrush($col)
    $oldClip = $g.Clip
    $g.SetClip($pr)
    try {
        foreach ($d in $dl) {
            $px = Get-DrawingPixels -L $L -D $d
            switch ($d.Kind) {
                "H" {
                    $g.DrawLine($pen, [float]$pr.Left, [float]$px.Y1, [float]$pr.Right, [float]$px.Y1)
                    $g.DrawString(("{0:N2}" -f ($d.P1 * $px.Fx)), $fontAxis, $br, [float]($pr.Left + (S 4)), [float]($px.Y1 - (S 14)))
                }
                "T" {
                    # ray: from point 1 through point 2 to the right edge
                    $x2 = $px.X2; $y2 = $px.Y2
                    if ([math]::Abs($px.X2 - $px.X1) -gt 0.5) {
                        $slope = ($px.Y2 - $px.Y1) / ($px.X2 - $px.X1)
                        $xe = if ($px.X2 -ge $px.X1) { $pr.Right } else { $pr.Left }
                        $x2 = $xe; $y2 = $px.Y1 + $slope * ($xe - $px.X1)
                    }
                    $g.DrawLine($pen, [float]$px.X1, [float]$px.Y1, [float]$x2, [float]$y2)
                    $g.FillEllipse($br, [float]($px.X1 - 3), [float]($px.Y1 - 3), [float]6, [float]6)
                    $g.FillEllipse($br, [float]($px.X2 - 3), [float]($px.Y2 - 3), [float]6, [float]6)
                }
                "R" {
                    # v5.5: zone (e.g. buy zone) - translucent area with a dashed frame
                    $zx = [math]::Min($px.X1, $px.X2); $zy = [math]::Min($px.Y1, $px.Y2)
                    $zw = [math]::Max(1, [math]::Abs($px.X2 - $px.X1)); $zh = [math]::Max(1, [math]::Abs($px.Y2 - $px.Y1))
                    $zf = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(38, $col.R, $col.G, $col.B))
                    $g.FillRectangle($zf, [float]$zx, [float]$zy, [float]$zw, [float]$zh); $zf.Dispose()
                    $g.DrawRectangle($fibPen, [float]$zx, [float]$zy, [float]$zw, [float]$zh)
                    $g.DrawString(("{0:N2} - {1:N2}" -f ([math]::Min($d.P1, $d.P2) * $px.Fx), ([math]::Max($d.P1, $d.P2) * $px.Fx)), $fontAxis, $br, [float]($zx + (S 3)), [float]($zy + (S 2)))
                }
                "N" {
                    # v5.5: text note
                    $nt = [string]$d.Text
                    $ns = $g.MeasureString($nt, $fontAxis)
                    $nb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(225, $script:Pal.HeaderBg.R, $script:Pal.HeaderBg.G, $script:Pal.HeaderBg.B))
                    $nrX = [float]($px.X1 + (S 6)); $nrY = [float]($px.Y1 - $ns.Height - (S 4))
                    $g.FillRectangle($nb, $nrX, $nrY, [float]($ns.Width + (S 6)), [float]($ns.Height + (S 2))); $nb.Dispose()
                    $g.DrawRectangle($pen, $nrX, $nrY, [float]($ns.Width + (S 6)), [float]($ns.Height + (S 2)))
                    $g.DrawString($nt, $fontAxis, $br, [float]($nrX + (S 3)), [float]($nrY + 1))
                    $g.FillEllipse($br, [float]($px.X1 - 3), [float]($px.Y1 - 3), [float]6, [float]6)
                }
                "F" {
                    $xs = [math]::Max([double]$pr.Left, [math]::Min($px.X1, $px.X2))
                    foreach ($lv in (Get-FibLevels -P1 $d.P1 -P2 $d.P2)) {
                        $yy = $pr.Bottom - ((Get-PriceFrac ($lv.Price * $px.Fx) ([double]$L.MinP) ([double]$L.SpanP) ([bool]$L.LogScale)) * $pr.Height)
                        $g.DrawLine($(if ($lv.Pct -in @(0.0, 100.0)) { $pen } else { $fibPen }), [float]$xs, [float]$yy, [float]$pr.Right, [float]$yy)
                        $g.DrawString(("{0:0.#}%  {1:N2}" -f $lv.Pct, ($lv.Price * $px.Fx)), $fontAxis, $br, [float]($xs + (S 4)), [float]($yy - (S 13)))
                    }
                }
            }
        }
    } finally {
        $g.Clip = $oldClip
        $pen.Dispose(); $fibPen.Dispose(); $br.Dispose()
    }
}

function New-DrawingAlert {
    # horizontal line -> price alert, trend line -> alert that follows the line
    param($D)
    if ($null -eq $D) { return }
    $sym = ([string]$script:Config.ActiveTicker).ToUpper()
    $q = $script:QuoteStore[$sym]
    if ($null -eq $q -or [double]$q.Price -le 0) { Set-TransientStatus "Noch kein Kurs - später nochmal versuchen" 4; return }
    $cur = [string]$D.Cur
    $now = Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $cur
    if ($D.Kind -eq "H") {
        $op = if ($D.P1 -ge $now) { ">=" } else { "<=" }
        if (Add-WidgetAlert -Ticker $sym -Condition $op -Target ([math]::Round($D.P1, 4)) -Currency $cur -Note "Linie im Chart" -NoConfirm) {
            Set-TransientStatus ("Alarm: {0} {1} {2:N2} {3}" -f $sym, $op, $D.P1, $cur) 5
        }
        return
    }
    if ($D.Kind -eq "T") {
        $lineNow = Get-TrendPriceAt -T1 $D.T1 -P1 $D.P1 -T2 $D.T2 -P2 $D.P2 -T ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
        $op = if ($lineNow -ge $now) { "Trend >=" } else { "Trend <=" }
        $a = [PSCustomObject]@{
            Id = [Guid]::NewGuid().ToString("N"); Ticker = $sym; Condition = $op; TargetPrice = [math]::Round($lineNow, 4); Currency = $cur
            Triggered = $false; Note = "Trendlinie im Chart"; RearmMin = 0; TriggeredAt = ""; ExpiresAt = ""; Peak = 0.0; Push = $true
            T1 = $D.T1; P1 = $D.P1; T2 = $D.T2; P2 = $D.P2
        }
        $script:Alerts.Add($a)
        Save-Alerts
        Refresh-WatchlistAndAlerts
        Set-TransientStatus ("Alarm: {0} kreuzt die Trendlinie (jetzt {1:N2} {2})" -f $sym, $lineNow, $cur) 6
    }
}

# right-click menu on a drawing
$drawMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miDrAlert = $drawMenu.Items.Add("Alarm auf diese Linie")
$miDrDel = $drawMenu.Items.Add("Zeichnung löschen")
$miDrDelAll = $drawMenu.Items.Add("Alle Zeichnungen dieses Tickers löschen")
$script:MenuDrawing = $null
$miDrAlert.Add_Click({ New-DrawingAlert $script:MenuDrawing })
$miDrDel.Add_Click({ Remove-Drawing $script:MenuDrawing })
$miDrDelAll.Add_Click({ Remove-Drawing -All })

Read-Drawings
$script:DrawingsReady = $true

$chartContextMenu.Add_Opening({
    param($sender, $e)
    # v5.0: right-click on a drawing opens its own menu
    if ($null -ne $script:CtxDrawing) {
        $e.Cancel = $true
        $script:MenuDrawing = $script:CtxDrawing
        $script:CtxDrawing = $null
        $miDrAlert.Enabled = ($script:MenuDrawing.Kind -in @("H", "T"))
        $drawMenu.Show([System.Windows.Forms.Cursor]::Position)
        return
    }
    $cmiPctAxis.Checked = [bool]$script:Config.PctAxis
    $cmiSR.Checked = [bool]$script:Config.ShowSR
    $px = $script:CtxPrice
    $sym = $script:Config.ActiveTicker.ToUpper()
    $cmiAlertHere.Enabled = -not [double]::IsNaN($px) -and $script:QuoteStore.ContainsKey($sym)
    if ($cmiAlertHere.Enabled) {
        $q = $script:QuoteStore[$sym]
        $cur = Convert-CurrencyValue -Amount $q.Price -FromCurrency $q.Currency -ToCurrency $script:ChartCur
        $op = if ($px -ge $cur) { ">=" } else { "<=" }
        $cmiAlertHere.Text = "Alarm: {0} {1} {2} {3}" -f $sym, $op, (Format-LevelPrice $px), $script:ChartCur
        $cmiAlertHere.Tag = @{ Op = $op; Price = [double](Format-LevelPrice $px -Raw) }
    } else {
        $cmiAlertHere.Text = "Alarm hier setzen (Rechtsklick im Kursbereich)"
    }
    $cmp = [string]$script:Config.CompareTicker
    $cmiCompareOff.Enabled = -not [string]::IsNullOrWhiteSpace($cmp)
    $cmiCompareOff.Text = if ($cmp) { "Vergleich mit $cmp entfernen" } else { "Vergleich entfernen" }
    $cmiZoomReset.Enabled = ([int]$script:ViewCount -gt 0)
})
$cmiAlertHere.Add_Click({
    $t = $cmiAlertHere.Tag
    if ($null -eq $t) { return }
    $sym = $script:Config.ActiveTicker.ToUpper()
    if (Add-WidgetAlert -Ticker $sym -Condition $t.Op -Target $t.Price -Currency $script:ChartCur -NoConfirm) {
        Set-TransientStatus ("Alarm angelegt: {0} {1} {2:N2} {3}" -f $sym, $t.Op, $t.Price, $script:ChartCur) 4
        Update-AllUiViews
    }
})
function Set-LogScale {
    param([bool]$On)
    $script:Config.LogScale = $On
    $cmiLog.Checked = $On
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Set-TransientStatus $(if ($On) { "Logarithmische Preisachse" } else { "Lineare Preisachse" }) 2
    Update-AllUiViews
}
$cmiLog.Add_Click({ Set-LogScale ([bool]$cmiLog.Checked) })
$cmiLevels.Add_Click({
    $script:Config.ShowLevels = $cmiLevels.Checked
    Save-JsonState -Path $script:ConfigPath -Data $script:Config
    Update-AllUiViews
})
$cmiCompare.Add_Click({ Show-CompareDialog })
$cmiCompareOff.Add_Click({ Set-CompareTicker -Symbol "" })
$cmiZoomReset.Add_Click({ Reset-ChartZoom })

# Portfolio Grid & Editor Events
Update-DepotCombo
# v4.8: shares and cost can be typed directly into the portfolio table
$dgvPortfolio.ReadOnly = $false
foreach ($col in $dgvPortfolio.Columns) { $col.ReadOnly = ($col.Name -notin @("Shares", "Avg")) }
$dgvPortfolio.Columns["Shares"].ToolTipText = "Stück - Zelle markieren und tippen (oder F2) zum Ändern"
$dgvPortfolio.Columns["Avg"].ToolTipText = "EK in Anzeigewährung - Zelle markieren und tippen (oder F2) zum Ändern"
$dgvPortfolio.Add_CellEndEdit({
    param($sender, $e)
    $col = $sender.Columns[$e.ColumnIndex].Name
    if ($col -notin @("Shares", "Avg")) { return }
    $row = $sender.Rows[$e.RowIndex]
    $sym = ([string]$row.Cells["Ticker"].Value).ToUpper()
    $raw = [string]$row.Cells[$col].Value
    if (-not $script:Portfolio.ContainsKey($sym)) { return }
    $pf = $script:Portfolio[$sym]
    $v = Parse-DecimalInput $raw
    if (-not (Test-DecimalInput $raw) -or $v -le 0) {
        Set-TransientStatus "Ungültige Zahl: '$raw'" 4
        Refresh-PortfolioGrid
        return
    }
    $before = "{0:N4} Stk @ {1:N4} {2}" -f $pf.Shares, $pf.AvgPrice, $pf.Currency
    if ($col -eq "Shares") { $pf.Shares = $v }
    else { $pf.AvgPrice = Convert-CurrencyValue -Amount $v -FromCurrency ([string]$script:Config.Currency) -ToCurrency ([string]$pf.Currency) }
    Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
    Write-WidgetLog ("Position edited in the grid: {0} {1} -> {2:N4} Stk @ {3:N4} {4}" -f $sym, $before, $pf.Shares, $pf.AvgPrice, $pf.Currency)
    Set-TransientStatus ("{0} geändert (ohne Buchung) - Strg+Z = rückgängig" -f $sym) 6
    Update-AllUiViews
})
$dgvPortfolio.Add_CellBeginEdit({
    param($sender, $e)
    # v4.9.5: no editing of hidden values
    if ([bool]$script:Config.PrivacyMode) { $e.Cancel = $true; Set-TransientStatus (Tr "Privat-Modus: erst F9 drücken, dann bearbeiten") 4; return }
    # remember the position for Ctrl+Z
    $sym = ([string]$sender.Rows[$e.RowIndex].Cells["Ticker"].Value).ToUpper()
    if ($script:Portfolio.ContainsKey($sym)) {
        $pf = $script:Portfolio[$sym]
        $script:Undo = @{ Kind = "Position"; Data = @{ Key = $sym; Item = [PSCustomObject]@{ Ticker = $sym; Shares = [double]$pf.Shares; AvgPrice = [double]$pf.AvgPrice; Currency = [string]$pf.Currency; BuyAmount = [double]$pf.BuyAmount; TargetAvg = [double]$pf.TargetAvg } }; Until = (Get-Date).AddSeconds(30) }
    }
})
# v4.6: columns (right-click a header), global hotkey, snapping to screen edges
Enable-GridCustomization -Grid $dgvWatchlist -Key "Watchlist"
Enable-GridCustomization -Grid $dgvPortfolio -Key "Portfolio"
$hkMsg = Register-GlobalHotkey
if ($hkMsg -and $hkMsg -ne "aus") { Write-WidgetLog "Global hotkey: $hkMsg" "WARN" }
$form.Add_ResizeEnd({
    if (-not [bool]$script:Config.SnapToEdges -or $form.WindowState -ne [System.Windows.Forms.FormWindowState]::Normal) { return }
    $wa = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    $sn = Get-SnappedPosition -X $form.Left -Y $form.Top -W $form.Width -H $form.Height -AreaLeft $wa.Left -AreaTop $wa.Top -AreaRight $wa.Right -AreaBottom $wa.Bottom -Dist (S 16)
    if ($sn.Moved) { $form.Location = New-Object System.Drawing.Point([int]$sn.X, [int]$sn.Y) }
})
$cmbDepot.Add_SelectionChangeCommitted({
    if ($script:DepotComboBusy) { return }
    $ix = $cmbDepot.SelectedIndex
    $list = @(Get-DepotList)
    if ($ix -lt $list.Count) { Switch-Depot $list[$ix].Id; return }
    $act = $ix - $list.Count
    Update-DepotCombo
    switch ($act) { 0 { New-Depot } 1 { Rename-ActiveDepot } 2 { Remove-ActiveDepot } }
})

$cmbPortSort.Add_SelectedIndexChanged({
    # choosing a preset ends a header-click sort
    $script:PfSort.Col = ""; $script:PfSort.Step = 0
    Set-GridSortGlyph -Grid $dgvPortfolio -Sort $script:PfSort
    Refresh-PortfolioGrid
})
$dgvPortfolio.Add_ColumnHeaderMouseClick({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $name = $sender.Columns[$e.ColumnIndex].Name
    if ($name -eq "Spark") { return }
    Step-GridSort -Sort $script:PfSort -Col $name -TextCols @("Ticker")
    Set-GridSortGlyph -Grid $dgvPortfolio -Sort $script:PfSort
    Refresh-PortfolioGrid
})
$dgvWatchlist.Add_ColumnHeaderMouseClick({
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    Step-GridSort -Sort $script:WlSort -Col ($sender.Columns[$e.ColumnIndex].Name) -TextCols @("Sym")
    Set-GridSortGlyph -Grid $dgvWatchlist -Sort $script:WlSort
    $lblWlTitle.Text = if ($script:WlSort.Col) { "Watchlist (sortiert - 3. Klick = eigene Reihenfolge)" } else { "Watchlist (Ziehen = Reihenfolge | Entf = Löschen)" }
    Refresh-WatchlistAndAlerts
})

# Drag & drop reordering (only in the manual order)
$script:WlDrag = @{ Sym = ""; Pt = [System.Drawing.Point]::Empty }
$dgvWatchlist.Add_MouseDown({
    param($sender, $e)
    $script:WlDrag.Sym = ""
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left -or $script:WlSort.Col) { return }
    $hit = $sender.HitTest($e.X, $e.Y)
    if ($hit.RowIndex -ge 0) {
        $script:WlDrag.Sym = [string]$sender.Rows[$hit.RowIndex].Cells[0].Value
        $script:WlDrag.Pt = $e.Location
    }
})
$dgvWatchlist.Add_MouseMove({
    param($sender, $e)
    if (-not $script:WlDrag.Sym -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $ds = [System.Windows.Forms.SystemInformation]::DragSize
    if ([math]::Abs($e.X - $script:WlDrag.Pt.X) -lt $ds.Width -and [math]::Abs($e.Y - $script:WlDrag.Pt.Y) -lt $ds.Height) { return }
    $sym = $script:WlDrag.Sym
    $script:WlDrag.Sym = ""
    [void]$sender.DoDragDrop($sym, [System.Windows.Forms.DragDropEffects]::Move)
})
$dgvWatchlist.Add_DragOver({
    param($sender, $e)
    $e.Effect = if ($e.Data.GetDataPresent([string]) -and -not $script:WlSort.Col) { [System.Windows.Forms.DragDropEffects]::Move } else { [System.Windows.Forms.DragDropEffects]::None }
})
$dgvWatchlist.Add_DragDrop({
    param($sender, $e)
    $sym = [string]$e.Data.GetData([string])
    if (-not $sym) { return }
    $pt = $sender.PointToClient((New-Object System.Drawing.Point($e.X, $e.Y)))
    $hit = $sender.HitTest($pt.X, $pt.Y)
    $target = if ($hit.RowIndex -ge 0) { $hit.RowIndex } else { $sender.Rows.Count - 1 }
    Move-WatchlistSymbol -Symbol $sym -NewIndex $target
})

$dgvPortfolio.Add_SelectionChanged({
    if ($script:SuppressGridSelection) { return }
    if ($dgvPortfolio.SelectedRows.Count -gt 0) {
        $sym = [string]$dgvPortfolio.SelectedRows[0].Cells[0].Value
        if ($sym -and $script:Portfolio.ContainsKey($sym)) {
            $p = $script:Portfolio[$sym]
            $txtPortTicker.Text = $sym
            $txtPortShares.Text = $p.Shares.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $txtPortAvg.Text    = $p.AvgPrice.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            Select-CurrencyInCombo -Combo $cmbPortCurr -Code $p.Currency
            $txtPortBuyAmt.Text = if ($p.BuyAmount -gt 0) { $p.BuyAmount.ToString([System.Globalization.CultureInfo]::InvariantCulture) } else { "" }
            $txtPortTarget.Text = if ($p.TargetAvg -gt 0) { $p.TargetAvg.ToString([System.Globalization.CultureInfo]::InvariantCulture) } else { "" }
            Update-NachkaufSimulation
        }
    }
})

$dgvPortfolio.Add_CellDoubleClick({
    param($sender, $e)
    if ($e.RowIndex -ge 0) {
        $sym = [string]$sender.Rows[$e.RowIndex].Cells[0].Value
        if ($sym) {
            Set-ActiveTab -TabName "Chart"
            Switch-ActiveTicker -NewTicker $sym -SkipResolve $true
        }
    }
})

$txtPortTicker.Add_TextChanged({ Update-NachkaufSimulation })
$txtPortShares.Add_TextChanged({ Update-NachkaufSimulation })
$txtPortAvg.Add_TextChanged({ Update-NachkaufSimulation })
$cmbPortCurr.Add_SelectedIndexChanged({ Update-NachkaufSimulation })
$txtPortBuyAmt.Add_TextChanged({ Update-NachkaufSimulation })
$txtPortTarget.Add_TextChanged({ Update-NachkaufSimulation })

$btnPortSave.Add_Click({
    foreach ($pair in @(@($txtPortShares, "Stück"), @($txtPortAvg, "EK-Kurs"), @($txtPortBuyAmt, "Nachkauf"), @($txtPortTarget, "Ziel-EK"))) {
        if (-not (Test-DecimalInput $pair[0].Text)) {
            $lblNachkaufOut.Text = "Ungültige Zahl im Feld '$($pair[1])': '$($pair[0].Text)'"
            $pair[0].Focus()
            return
        }
    }
    if ([string]::IsNullOrWhiteSpace($txtPortTicker.Text)) {
        $lblNachkaufOut.Text = "Bitte einen Ticker eingeben."
        return
    }
    $sym = Resolve-BestSymbol -RawInput $txtPortTicker.Text
    $sh  = Parse-DecimalInput $txtPortShares.Text
    $avg = Parse-DecimalInput $txtPortAvg.Text
    if ([string]::IsNullOrWhiteSpace($sym) -or $sh -le 0 -or $avg -le 0) {
        $lblNachkaufOut.Text = "Stück und EK-Kurs müssen größer als 0 sein."
        return
    }

    $posCurr = if ($cmbPortCurr.SelectedItem) { [string]$cmbPortCurr.SelectedItem } else { $script:Config.Currency }
    $txtPortTicker.Text = $sym

    $finalShares = $sh
    $finalAvg    = $avg
    $logBuy      = -not $script:Portfolio.ContainsKey($sym)   # new position = first buy
    if ($script:Portfolio.ContainsKey($sym)) {
        $existing = $script:Portfolio[$sym]
        if ([math]::Abs($existing.Shares - $sh) -gt 0.0001 -or [math]::Abs($existing.AvgPrice - $avg) -gt 0.0001) {
            $ans = [System.Windows.Forms.MessageBox]::Show(
                $form,
                "Position '$sym' existiert bereits ($([math]::Round($existing.Shares, 3)) Stk @ $([math]::Round($existing.AvgPrice, 2)) $($existing.Currency)).`r`n`r`n[Ja] = Zukauf hinzufügen & Durchschnitts-EK berechnen`r`n[Nein] = Bestehende Werte überschreiben",
                "Position zusammenführen?",
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($ans -eq [System.Windows.Forms.DialogResult]::Cancel) { return }
            if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) {
                $oldAvgInPosCurr = Convert-CurrencyValue -Amount $existing.AvgPrice -FromCurrency $existing.Currency -ToCurrency $posCurr
                $finalShares = $existing.Shares + $sh
                $finalAvg    = (($existing.Shares * $oldAvgInPosCurr) + ($sh * $avg)) / $finalShares
                $logBuy      = $true
            }
        }
    }

    # v4.2: the buy gets its real date (value history, XIRR, yearly report)
    $buyDate = ""
    if ($logBuy) {
        $buyDate = Show-BuyDatePrompt -Ticker $sym -Shares $sh
        if (-not $buyDate) { $lblNachkaufOut.Text = "Speichern abgebrochen."; return }
    }

    $script:Portfolio[$sym] = [PSCustomObject]@{
        Ticker    = $sym
        Shares    = $finalShares
        AvgPrice  = $finalAvg
        Currency  = $posCurr
        BuyAmount = Parse-DecimalInput $txtPortBuyAmt.Text
        TargetAvg = Parse-DecimalInput $txtPortTarget.Text
    }
    Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
    if ($logBuy) {
        # a buy dated before a split is stored in the units of its own date
        $bf = Get-BookingUnitsFactor -Ticker $sym -Date $buyDate
        Add-TransactionRecord -Type "Kauf" -Ticker $sym -Shares ($sh / $bf) -Price ($avg * $bf) -Fee 0 -Currency $posCurr -Date $buyDate -Note "Portfolio-Editor"
    }
    Refresh-AllMarketData
    Update-AllUiViews
})

$btnPortTx.Add_Click({
    $t = $txtPortTicker.Text.Trim()
    if (-not $t) { $t = $script:Config.ActiveTicker }
    Show-TransactionDialog -Ticker $t
})
$btnPortHist.Add_Click({ Show-TransactionHistory })

$btnPortDel.Add_Click({
    $sym = $txtPortTicker.Text.Trim().ToUpper()
    if ($sym -and $script:Portfolio.ContainsKey($sym)) {
        $old = $script:Portfolio[$sym]
        $script:Portfolio.Remove($sym)
        Save-JsonState -Path $script:PortfolioPath -Data $script:Portfolio
        Update-AllUiViews
        Set-Undo -Kind "Position" -Data @{ Key = $sym; Item = $old } -Text "Position $sym gelöscht (Buchungen bleiben)"
    }
})

# Direct CSV Export from Chart Bar
$btnExportCsv.Add_Click({
    if (-not $script:ActiveSeries -or $script:ActiveSeries.Count -eq 0) { return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "CSV Datei (*.csv)|*.csv"
    $sfd.FileName = "{0}_{1}_{2}.csv" -f $script:Config.ActiveTicker, $script:Config.Timeframe, (Get-Date -Format "yyyyMMdd")
    if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $csvLines = New-Object System.Collections.Generic.List[string]
        $csvLines.Add("Datum;Open;High;Low;Close;Währung;Volumen")
        foreach ($pt in $script:ActiveSeries) {
            $dtStr = [DateTimeOffset]::FromUnixTimeMilliseconds($pt.Ts).ToLocalTime().ToString("yyyy-MM-dd HH:mm")
            $csvLines.Add(("{0};{1:F4};{2:F4};{3:F4};{4:F4};{5};{6}" -f $dtStr, $pt.Open, $pt.High, $pt.Low, $pt.Close, $script:ChartCur, $pt.Volume))
        }
        [System.IO.File]::WriteAllLines($sfd.FileName, $csvLines, [System.Text.Encoding]::UTF8)
    }
})

# Watchlist Search, Add, Remove & Alerts Events
$wlSearchTimer = New-Object System.Windows.Forms.Timer
$wlSearchTimer.Interval = 320
$wlSearchTimer.Add_Tick({
    $wlSearchTimer.Stop()
    $q = $txtWlSearch.Text.Trim()
    if ($q.Length -lt 1) {
        $lstWlSearchDropdown.Visible = $false
        return
    }
    $url = Get-SearchUrl -Query $q
    Start-FetchJob -Urls @($url) -MaxConcurrency 1 -Context @{ Query = $q; Url = $url } -OnComplete {
        param($Box, $Ctx)
        if ($txtWlSearch.Text.Trim() -ne $Ctx.Query) { return }   # user typed on
        Show-WlSearchHits -Hits @(ConvertFrom-YahooSearch -Json $Box.Results[$Ctx.Url])
    }
})

function Show-WlSearchHits {
    param([array]$Hits)
    $lstWlSearchDropdown.BeginUpdate()
    $lstWlSearchDropdown.Items.Clear()
    foreach ($h in $Hits) {
        if ($null -ne $h) { [void]$lstWlSearchDropdown.Items.Add($h) }
    }
    $lstWlSearchDropdown.DisplayMember = "Display"
    $lstWlSearchDropdown.EndUpdate()
    if ($lstWlSearchDropdown.Items.Count -gt 0) {
        $lstWlSearchDropdown.SelectedIndex = 0
        $rowsVis = [math]::Min(8, [math]::Max(2, $lstWlSearchDropdown.Items.Count))
        $lstWlSearchDropdown.Height = ($rowsVis * (S 20)) + (S 6)
        $lstWlSearchDropdown.Visible = $true
        $lstWlSearchDropdown.BringToFront()
    } else {
        $lstWlSearchDropdown.Visible = $false
    }
}

$txtWlSearch.Add_TextChanged({
    if ($script:SuppressWlSearchEvent) { return }
    $wlSearchTimer.Stop()
    $wlSearchTimer.Start()
})

$txtWlSearch.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Down -and $lstWlSearchDropdown.Visible -and $lstWlSearchDropdown.Items.Count -gt 0) {
        $e.SuppressKeyPress = $true
        $lstWlSearchDropdown.Focus()
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $e.SuppressKeyPress = $true
        $wlSearchTimer.Stop()
        $symToAdd = if ($lstWlSearchDropdown.Visible -and $null -ne $lstWlSearchDropdown.SelectedItem) {
            $lstWlSearchDropdown.SelectedItem.Symbol
        } else {
            $txtWlSearch.Text.Trim()
        }
        $lstWlSearchDropdown.Visible = $false
        if (-not [string]::IsNullOrWhiteSpace($symToAdd)) {
            $script:SuppressWlSearchEvent = $true
            $txtWlSearch.Text = ""
            $script:SuppressWlSearchEvent = $false
            [void](Add-SymbolToWatchlist -RawSymbol $symToAdd)
        }
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $lstWlSearchDropdown.Visible = $false
    }
})

$lstWlSearchDropdown.Add_Click({
    if ($null -ne $lstWlSearchDropdown.SelectedItem) {
        $symToAdd = $lstWlSearchDropdown.SelectedItem.Symbol
        $lstWlSearchDropdown.Visible = $false
        $script:SuppressWlSearchEvent = $true
        $txtWlSearch.Text = ""
        $script:SuppressWlSearchEvent = $false
        [void](Add-SymbolToWatchlist -RawSymbol $symToAdd)
    }
})

$lstWlSearchDropdown.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and $null -ne $lstWlSearchDropdown.SelectedItem) {
        $e.SuppressKeyPress = $true
        $symToAdd = $lstWlSearchDropdown.SelectedItem.Symbol
        $lstWlSearchDropdown.Visible = $false
        $script:SuppressWlSearchEvent = $true
        $txtWlSearch.Text = ""
        $script:SuppressWlSearchEvent = $false
        [void](Add-SymbolToWatchlist -RawSymbol $symToAdd)
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $lstWlSearchDropdown.Visible = $false
    }
})

$btnWlAddSearch.Add_Click({
    $wlSearchTimer.Stop()
    $symToAdd = if ($lstWlSearchDropdown.Visible -and $null -ne $lstWlSearchDropdown.SelectedItem) {
        $lstWlSearchDropdown.SelectedItem.Symbol
    } else {
        $txtWlSearch.Text.Trim()
    }
    $lstWlSearchDropdown.Visible = $false
    if (-not [string]::IsNullOrWhiteSpace($symToAdd)) {
        $script:SuppressWlSearchEvent = $true
        $txtWlSearch.Text = ""
        $script:SuppressWlSearchEvent = $false
        [void](Add-SymbolToWatchlist -RawSymbol $symToAdd)
    }
})

# ---- v5.5: loading skeleton: rows without data show soft grey bars ----
$dgvWatchlist.Add_CellPainting({
    param($sender, $e)
    if ($e.RowIndex -lt 0 -or $e.ColumnIndex -le 0) { return }
    $row = $sender.Rows[$e.RowIndex]
    if ([string]$row.Tag -ne "skel") { return }
    $e.PaintBackground($e.CellBounds, $false)
    $b = $e.CellBounds
    $w = [int]($b.Width * $(if ($e.ColumnIndex % 2 -eq 0) { 0.55 } else { 0.7 }))
    $h = [math]::Max(4, [int]($b.Height * 0.34))
    $x = if ([bool]$script:Config.AlignNumbersRight) { $b.Right - $w - (S 6) } else { $b.Left + (S 6) }
    $c0 = Get-BlendColor -A $script:Pal.Border -B $script:Pal.Card -T 0.55
    $br = New-Object System.Drawing.SolidBrush($c0)
    $e.Graphics.FillRectangle($br, $x, ($b.Top + [int](($b.Height - $h) / 2)), $w, $h)
    $br.Dispose()
    $e.Handled = $true
})

# ---- v5.0: hover card (mouse rests on a ticker in the watchlist / portfolio) ----
$script:HoverSym = ""
$script:HoverPending = $null
$pnlHover = New-Object System.Windows.Forms.Panel
$pnlHover.Size = New-Object System.Drawing.Size((S 300), (S 172))
$pnlHover.Visible = $false
$pnlHover.BackColor = $script:Pal.Card
Enable-DoubleBuffering -Control $pnlHover
$form.Controls.Add($pnlHover)
$script:HoverTimer = New-Object System.Windows.Forms.Timer
$script:HoverTimer.Interval = 650
$script:HoverTimer.Add_Tick({
    $script:HoverTimer.Stop()
    $hp = $script:HoverPending
    if ($null -eq $hp -or -not [bool]$script:Config.HoverCards) { return }
    $script:HoverSym = [string]$hp.Sym
    # v5.5: room for the note
    $pnlHover.Height = if (Get-TickerNote $script:HoverSym) { S 210 } else { S 172 }
    $pt = $form.PointToClient([System.Windows.Forms.Cursor]::Position)
    $x = $pt.X + (S 18); $y = $pt.Y + (S 14)
    if ($x + $pnlHover.Width -gt $form.ClientSize.Width - (S 4)) { $x = $pt.X - $pnlHover.Width - (S 12) }
    if ($y + $pnlHover.Height -gt $form.ClientSize.Height - (S 4)) { $y = $pt.Y - $pnlHover.Height - (S 8) }
    $pnlHover.Location = New-Object System.Drawing.Point([math]::Max(0, $x), [math]::Max(0, $y))
    try {
        $rp = New-RoundedPath (New-Object System.Drawing.RectangleF(0, 0, [float]$pnlHover.Width, [float]$pnlHover.Height)) ([float](S 8))
        $oldRg = $pnlHover.Region
        $pnlHover.Region = New-Object System.Drawing.Region($rp)
        $rp.Dispose(); if ($null -ne $oldRg) { $oldRg.Dispose() }
    } catch { }
    $pnlHover.Visible = $true
    $pnlHover.BringToFront()
    $pnlHover.Invalidate()
})
function Hide-HoverCard {
    $script:HoverTimer.Stop()
    $script:HoverPending = $null
    if ($pnlHover.Visible) { $pnlHover.Visible = $false }
}
$script:HoverEnter = {
    param($sender, $e)
    if ($e.RowIndex -lt 0 -or -not [bool]$script:Config.HoverCards) { return }
    $sym = ([string]$sender.Rows[$e.RowIndex].Cells[0].Value).Trim().ToUpper()
    if (-not $sym -or -not $script:QuoteStore.ContainsKey($sym)) { Hide-HoverCard; return }
    if ($pnlHover.Visible -and $script:HoverSym -eq $sym) { return }
    if ($pnlHover.Visible) { $pnlHover.Visible = $false }
    $script:HoverPending = @{ Sym = $sym }
    $script:HoverTimer.Stop(); $script:HoverTimer.Start()
}
foreach ($hg in @($dgvWatchlist, $dgvPortfolio)) {
    $hg.Add_CellMouseEnter($script:HoverEnter)
    $hg.Add_MouseLeave({ Hide-HoverCard })
    $hg.Add_Scroll({ Hide-HoverCard })
    $hg.Add_MouseDown({ Hide-HoverCard })
}
$pnlHover.Add_MouseEnter({ Hide-HoverCard })
$script:HoverReady = $true
$pnlHover.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $p = $script:Pal
    $sym = $script:HoverSym
    $q = $script:QuoteStore[$sym]
    $w = $sender.Width; $h = $sender.Height
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    # V7.1: info card = card surface, strong border, rounded corners (same look as the toasts and menus)
    $g.Clear($p.Card)
    $bpath = New-RoundedPath (New-Object System.Drawing.RectangleF(0.5, 0.5, [float]($w - 1), [float]($h - 1))) ([float](S 8))
    $bp = New-Object System.Drawing.Pen($p.Border, [float]1)
    $g.DrawPath($bp, $bpath); $bp.Dispose(); $bpath.Dispose()
    if ($null -eq $q) { return }
    $txt = New-Object System.Drawing.SolidBrush($p.Text)
    $mut = New-Object System.Drawing.SolidBrush($p.Muted)
    $acc = New-Object System.Drawing.SolidBrush($p.Accent)
    $upB = New-Object System.Drawing.SolidBrush($(if ([double]$q.ChangePct -ge 0) { $colGreen } else { $colRed }))
    try {
        $x0 = S 10; $y = S 8
        $g.DrawString($sym, $fontTicker, $acc, $x0, $y)
        $nm = if ($q.LongName) { [string]$q.LongName } else { "" }
        $g.DrawString($nm, $fontUi, $mut, (New-Object System.Drawing.RectangleF([float]($x0 + (S 90)), [float]($y + 2), [float]($w - (S 104)), [float](S 18))))
        $y += S 22
        $curr = [string]$script:Config.Currency
        $pcur = Get-PriceCurrency $sym
        $pc = Convert-CurrencyValue -Amount ([double]$q.Price) -FromCurrency ([string]$q.Currency) -ToCurrency $pcur
        $g.DrawString(("{0:N2} {1}" -f $pc, $pcur), $fontPrice, $txt, $x0, $y)
        $g.DrawString(("{0:+0.00;-0.00}%" -f [double]$q.ChangePct), $fontTicker, $upB, ($x0 + (S 150)), ($y + (S 3)))
        $y += S 26
        # day range (from the quote meta) and 52-week bar
        $dLo = [double]::NaN; $dHi = [double]::NaN
        if ($null -ne $q.Meta) { try { $dLo = [double]$q.Meta.regularMarketDayLow; $dHi = [double]$q.Meta.regularMarketDayHigh } catch { } }
        if ($dLo -gt 0 -and $dHi -gt 0) { $g.DrawString(("{0} {1:N2} - {2:N2} {3}" -f (Tr "Tag:"), $dLo, $dHi, $q.Currency), $fontUi, $mut, $x0, $y); $y += S 17 }
        $f52 = Get-RangePosition -Price ([double]$q.Price) -Low ([double]$q.Low52) -High ([double]$q.High52)
        if (-not [double]::IsNaN($f52)) {
            $g.DrawString(("52W {0:N2}" -f [double]$q.Low52), $fontAxis, $mut, $x0, $y)
            $hiTxt = "{0:N2}" -f [double]$q.High52
            $hiW = $g.MeasureString($hiTxt, $fontAxis).Width
            $g.DrawString($hiTxt, $fontAxis, $mut, [float]($w - (S 10) - $hiW), $y)
            $bx0 = $x0 + (S 78); $bx1 = $w - (S 18) - $hiW; $by = $y + (S 7)
            $tp = New-Object System.Drawing.Pen($p.Border, [float](S 3)); $g.DrawLine($tp, [float]$bx0, [float]$by, [float]$bx1, [float]$by); $tp.Dispose()
            $mx = $bx0 + ($bx1 - $bx0) * $f52
            $g.FillEllipse($acc, [float]($mx - (S 4)), [float]($by - (S 4)), [float](S 8), [float](S 8))
            $y += S 18
        }
        # 5-day sparkline
        if ($script:SparklineStore.ContainsKey($sym)) {
            Draw-MiniSparkline -g $g -Rect (New-Object System.Drawing.Rectangle($x0, $y, ($w - 2 * $x0), (S 26))) -Values $script:SparklineStore[$sym]
            $y += S 30
        }
        # position, next event, analysts
        $lines = @()
        if ($script:Portfolio.ContainsKey($sym)) {
            $pf = $script:Portfolio[$sym]
            $val = [double]$pf.Shares * $pc
            $cost = [double]$pf.Shares * (Convert-CurrencyValue -Amount ([double]$pf.AvgPrice) -FromCurrency ([string]$pf.Currency) -ToCurrency $curr)
            $pl = if ($cost -gt 0) { ($val / $cost - 1) * 100 } else { [double]::NaN }
            $lines += $(if ([bool]$script:Config.PrivacyMode) { "{0}: {1:+0.0;-0.0}%" -f (Tr "Im Depot"), $pl } else { "{0}: {1:N2} Stk, {2:N2} {3} ({4:+0.0;-0.0}%)" -f (Tr "Im Depot"), [double]$pf.Shares, $val, $curr, $pl })
        }
        $ev = $script:Events[$sym]
        if ($null -ne $ev) {
            if ($ev.EarningsDate) { $lines += ("{0} {1}" -f (Tr "Zahlen:"), (Format-IsoDateDe ([string]$ev.EarningsDate))) }
            $lab = Get-ConsensusLabel ([string]$ev.RecKey) -Long
            $up = Get-TargetUpside -Target ([double]$ev.TargetMean) -Price ([double]$q.Price)
            if ($lab -or -not [double]::IsNaN($up)) { $lines += ("{0} {1}{2}" -f (Tr "Analysten:"), $lab, $(if (-not [double]::IsNaN($up)) { " (Ziel {0:+0;-0}%)" -f $up } else { "" })) }
        }
        foreach ($ln in $lines) { if ($y -lt $h - (S 16)) { $g.DrawString($ln, $fontUi, $txt, $x0, $y); $y += S 17 } }
        # v5.5: the note (two lines at most)
        $nt = Get-TickerNote $sym
        if ($nt -and $y -lt $h - (S 20)) {
            $nr = New-Object System.Drawing.RectangleF([float]$x0, [float]($y + (S 2)), [float]($w - 2 * $x0), [float]([math]::Min((S 34), $h - $y - (S 4))))
            $sf = New-Object System.Drawing.StringFormat
            $sf.Trimming = [System.Drawing.StringTrimming]::EllipsisWord
            $g.DrawString(([string][char]0x270E + " " + (Get-NoteSnippet $nt -Max 160)), $fontUi, $mut, $nr, $sf)
            $sf.Dispose()
        }
    } finally { $txt.Dispose(); $mut.Dispose(); $acc.Dispose(); $upB.Dispose() }
})

# v4.9.5: right-click actions on a ticker (watchlist and portfolio)
$script:RowMenuSym = ""
$rowMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miRowChart = $rowMenu.Items.Add("Chart öffnen")
$miRowAlert = $rowMenu.Items.Add("Alarm anlegen ...")
$miRowBuy   = $rowMenu.Items.Add("Kauf / Verkauf buchen ...")
$miRowNews  = $rowMenu.Items.Add("Nachrichten (News-Tab)")
$miRowCmp   = $rowMenu.Items.Add("Im Chart vergleichen")
$miRowDes   = $rowMenu.Items.Add("Beschreibung (DES)")
$miRowTa    = $rowMenu.Items.Add("Ticker-Analyse: Signale + Kennzahlen (TA)")
$miRowNote  = $rowMenu.Items.Add("Notiz ...")
$miRowSep   = New-Object System.Windows.Forms.ToolStripSeparator
[void]$rowMenu.Items.Add($miRowSep)
$miRowRemove = $rowMenu.Items.Add("Aus der Watchlist entfernen")
# v5.0: groups
$miRowGroup = New-Object System.Windows.Forms.ToolStripMenuItem("Zu Gruppe")
$rowMenu.Items.Insert($rowMenu.Items.IndexOf($miRowSep), $miRowGroup)
$miRowChart.Add_Click({ $s0 = $script:RowMenuSym; if ([string]$script:Config.Layout -ne "Terminal") { Set-ActiveTab -TabName "Chart" }; Switch-ActiveTicker -NewTicker $s0 -SkipResolve $true })
$miRowAlert.Add_Click({
    $s0 = $script:RowMenuSym
    Set-ActiveTab -TabName "Watchlist"
    $txtAlertTicker.Text = $s0
    [void]$txtAlertPrice.Focus()
    Set-TransientStatus ("Alarm für {0}: Bedingung und Wert eintragen, dann '+'" -f $s0) 5
})
$miRowBuy.Add_Click({ Show-TransactionDialog -Ticker $script:RowMenuSym })
$miRowNews.Add_Click({ Set-NewsFilter $script:RowMenuSym; Set-ActiveTab -TabName "News" })
$miRowCmp.Add_Click({
    $s0 = $script:RowMenuSym
    if ($s0 -eq ([string]$script:Config.ActiveTicker).ToUpper()) { Set-TransientStatus "Das ist der aktive Ticker - erst einen anderen öffnen" 4; return }
    Switch-CompareTicker -Symbol $s0
    if ([string]$script:Config.Layout -ne "Terminal") { Set-ActiveTab -TabName "Chart" }
})
$miRowDes.Add_Click({ Show-DescriptionDialog $script:RowMenuSym })
$miRowTa.Add_Click({ Show-TickerAnalysis $script:RowMenuSym })
$miRowNote.Add_Click({ Show-NoteDialog -Ticker $script:RowMenuSym })
$miRowRemove.Add_Click({ Remove-SymbolFromWatchlist -Symbol $script:RowMenuSym })
$script:RowMenuHandler = {
    param($sender, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right -or $e.RowIndex -lt 0) { return }
    $sym = ([string]$sender.Rows[$e.RowIndex].Cells[0].Value).Trim().ToUpper()
    if (-not $sym) { return }
    $script:RowMenuSym = $sym
    $sender.ClearSelection()
    $sender.Rows[$e.RowIndex].Selected = $true
    $inWl = (@($script:Config.Watchlist | ForEach-Object { ([string]$_).ToUpper() }) -contains $sym)
    $miRowRemove.Visible = $inWl -and ($sender -eq $dgvWatchlist)
    $miRowSep.Visible = $miRowRemove.Visible
    $miRowChart.Text = "{0}: {1}" -f (Tr "Chart öffnen"), $sym
    # groups: tick = member; click toggles; last entry creates a new group
    $miRowGroup.DropDownItems.Clear()
    $miRowGroup.Visible = $inWl
    foreach ($gr in @($script:Config.WatchGroups)) {
        if ($null -eq $gr -or -not $gr.Name) { continue }
        $gi = New-Object System.Windows.Forms.ToolStripMenuItem([string]$gr.Name)
        $gi.Checked = (@($gr.Symbols | ForEach-Object { ([string]$_).ToUpper() }) -contains $sym)
        $gi.Tag = [string]$gr.Name
        $gi.Add_Click({
            param($s2, $e2)
            $script:Config.WatchGroups = @(Set-WatchGroupMember -Groups @($script:Config.WatchGroups) -Group ([string]$s2.Tag) -Symbol $script:RowMenuSym -In (-not $s2.Checked))
            Save-JsonState -Path $script:ConfigPath -Data $script:Config
            Update-WatchGroupCombo
            Refresh-WatchlistAndAlerts
        })
        [void]$miRowGroup.DropDownItems.Add($gi)
    }
    $gn = New-Object System.Windows.Forms.ToolStripMenuItem((Tr "Neue Gruppe ..."))
    $gn.Add_Click({ $nm = New-WatchGroup -Symbol $script:RowMenuSym; if ($nm) { Update-WatchGroupCombo; Refresh-WatchlistAndAlerts } })
    [void]$miRowGroup.DropDownItems.Add($gn)
    $rowMenu.Show($sender, $sender.PointToClient([System.Windows.Forms.Cursor]::Position))
}
$dgvWatchlist.Add_CellMouseDown($script:RowMenuHandler)
$dgvPortfolio.Add_CellMouseDown($script:RowMenuHandler)

$dgvWatchlist.Add_CellDoubleClick({
    param($sender, $e)
    if ($e.RowIndex -ge 0) {
        $sym = [string]$sender.Rows[$e.RowIndex].Cells[0].Value
        if ($sym) {
            Set-ActiveTab -TabName "Chart"
            Switch-ActiveTicker -NewTicker $sym -SkipResolve $true
        }
    }
})

$dgvWatchlist.Add_KeyDown({
    param($sender, $e)
    if ($e.Alt -and ($e.KeyCode -eq [System.Windows.Forms.Keys]::Up -or $e.KeyCode -eq [System.Windows.Forms.Keys]::Down) -and $dgvWatchlist.SelectedRows.Count -gt 0) {
        $e.Handled = $true
        if ($script:WlSort.Col) { Set-TransientStatus "Reihenfolge ändern: erst Sortierung aufheben (Spaltenkopf 3x klicken)" 4; return }
        $sym = [string]$dgvWatchlist.SelectedRows[0].Cells[0].Value
        $idx = @($script:Config.Watchlist).IndexOf($sym)
        Move-WatchlistSymbol -Symbol $sym -NewIndex ($idx + $(if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Up) { -1 } else { 1 }))
        return
    }
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Delete -and $dgvWatchlist.SelectedRows.Count -gt 0) {
        $e.Handled = $true
        $sym = [string]$dgvWatchlist.SelectedRows[0].Cells[0].Value
        [void](Remove-SymbolFromWatchlist -Symbol $sym)
    }
})

$btnWlAddActive.Add_Click({
    [void](Add-SymbolToWatchlist -RawSymbol $script:Config.ActiveTicker)
})

$btnWlRemove.Add_Click({
    if ($dgvWatchlist.SelectedRows.Count -gt 0) {
        $sym = [string]$dgvWatchlist.SelectedRows[0].Cells[0].Value
        [void](Remove-SymbolFromWatchlist -Symbol $sym)
    }
})

