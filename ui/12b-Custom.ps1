# TerminalWidget UI part 12b (Customization, V7.8) - dot-sourced by TerminalWidget.ps1 in order, same scope as the main script.
# Keep UTF-8 with BOM.

# English texts of the v7.8 - 8.0 additions (existing entries of the main table win)
foreach ($pair in @(
    @('Farbregel:', 'Colour rule:'),
    @('Zielkurs', 'Target price'),
    @('Eigener Zielkurs in', 'Your target price in'),
    @('(leer = entfernen)', '(empty = remove)'),
    @('Abstand vom aktuellen Kurs bis zum eigenen Zielkurs', 'Distance from the current price to your target'),
    @('Abstand zum nächsten aktiven Kurs-Alarm', 'Distance to the nearest active price alert'),
    @('Heutige Änderung deiner Position (heutiger Wechselkurs)', 'Today''s change of your position (today''s exchange rate)'),
    @('Heutige Änderung je Stück (keine Position)', 'Today''s change per share (no position)'),
    @('Alarm-Abstand', 'To alert'),
    @('Heute (Währung)', 'Today (currency)'),
    @('Farbregeln', 'Colour rules'),
    @('Die erste passende, eingeschaltete Regel färbt die Zeile (Watchlist und Portfolio). Farbe als #RRGGBB, Doppelklick öffnet die Farbwahl.', 'The first matching rule that is on colours the row (watchlist and portfolio). Colour as #RRGGBB, double-click opens the picker.'),
    @('An', 'On'),
    @('Zahl', 'Number'),
    @('Farbe', 'Colour'),
    @('Vergleich', 'Compare'),
    @('Neue Regel', 'New rule'),
    @('Vorlagen wiederherstellen', 'Restore ready-made'),
    @('Eigene Regel', 'My rule'),
    @('Zahl oder Farbe ungültig in Regel:', 'Invalid number or colour in rule:'),
    @('Tagesänderung %', 'Day change %'),
    @('Tagesänderung % (egal welche Richtung)', 'Day change % (either direction)'),
    @('Abstand zu Alarm / Zielkurs %', 'Distance to alert / target %'),
    @('RSI (1h)', 'RSI (1h)'),
    @('Gewinn / Verlust zum Einstand %', 'Gain / loss on cost %'),
    @('Abstand zum 52W-Hoch %', 'Distance to 52W high %'),
    @('Große Tagesbewegung', 'Big day move'),
    @('Nahe Alarm oder Zielkurs', 'Near alert or target'),
    @('RSI überkauft', 'RSI overbought'),
    @('RSI überverkauft', 'RSI oversold'),
    @('Position im Gewinn', 'Position in profit'),
    @('Position im Verlust', 'Position at a loss'),
    @('Eigenes Theme', 'Own theme'),
    @('Mein Theme', 'My theme'),
    @('Basis', 'Based on'),
    @('Bereich', 'Area'),
    @('Farbe (Klick = wählen)', 'Colour (click to pick)'),
    @('Kopfzeile', 'Header'),
    @('Hintergrund', 'Background'),
    @('Flächen', 'Panels'),
    @('Karten und Listen', 'Cards and lists'),
    @('Eingabefelder', 'Input fields'),
    @('Maus darüber', 'Hover'),
    @('Gitterlinien', 'Grid lines'),
    @('Rahmen', 'Borders'),
    @('Schrift', 'Text'),
    @('Schrift gedämpft', 'Muted text'),
    @('Akzent', 'Accent'),
    @('Hinweis', 'Note'),
    @('Gewinn- und Verlustfarben stellst du in den Einstellungen ein.', 'Gain and loss colours are set in the settings.'),
    @('Speichern und anwenden', 'Save and apply'),
    @('Exportieren ...', 'Export ...'),
    @('Position im Detail (POS)', 'Position details (POS)'),
    @('Je Jahr', 'Per year'),
    @('Je Broker', 'Per broker'),
    @('Buchungen', 'Bookings'),
    @('Gekauft', 'Bought'),
    @('Verkauft', 'Sold'),
    @('Orders', 'Orders'),
    @('Buchung erfassen ...', 'Add booking ...'),
    @('erster Kauf', 'first buy'),
    @('Beträge in', 'amounts in'),
    @('ohne Angabe', 'not given'),
    @('Gesamtergebnis', 'Total result'),
    @('Dividende auf Einstand', 'Dividend on cost'),
    @('Anteil im Depot', 'Share of portfolio'),
    @('Keine Buchungen: Werte aus dem Portfolio-Editor, Einstand zum heutigen Wechselkurs.', 'No bookings: figures from the portfolio editor, cost at todays exchange rate.'),
    @('Das Portfolio zeigt eine andere Stückzahl als die Buchungen. Ergebnis und Einstand beruhen auf den Buchungen.', 'The portfolio shows a different share count than the bookings. Result and cost are based on the bookings.'),
    @('Quellen:', 'Sources:'),
    @('Quellen', 'Sources'),
    @('Gemerkt', 'Saved'),
    @('Positionen', 'Positions'),
    @('1J', '1Y'),
    @('3J', '3Y'),
    @('Dividenden im Jahr', 'Dividends this year'),
    @('Buchgewinn', 'Unrealised gain'),
    @('Größter Rückgang', 'Max drawdown'),
    @('Schwankung p.a.', 'Volatility p.a.'),
    @('Beste Position', 'Best position'),
    @('Schwächste Position', 'Weakest position'),
    @('Gegen Benchmark', 'Versus benchmark'),
    @('Gebühren', 'Fees'),
    @('Alarm-Übersicht ...', 'Alert overview ...'),
    @('Alarm-Übersicht', 'Alert overview'),
    @('erfüllt', 'met'),
    @('Punkte', 'points'),
    @('Alarm bearbeiten', 'Edit alert'),
    @('Wiederholen', 'Repeat'),
    @('Unverändert (bis {0})', 'Unchanged (until {0})'),
    @('Unverändert (ohne Ende)', 'Unchanged (no end)'),
    @('Gültig', 'Valid'),
    @('Auch aufs Handy schicken', 'Also send to the phone'),
    @('Aktiv', 'Active'),
    @('Ausgelöst', 'Triggered'),
    @('Pausiert', 'Paused'),
    @('Abgelaufen', 'Expired'),
    @('einmalig', 'once'),
    @('{0} von {1} Alarmen. Aktive nach Abstand sortiert, der nächste oben.', '{0} of {1} alerts. Active ones sorted by distance, closest first.'),
    @('Filter', 'Filter'),
    @('Abstand', 'To go'),
    @('So weit muss sich der Wert noch bewegen, bis der Alarm auslöst', 'How far the value still has to move before the alert fires'),
    @('Gültig bis', 'Valid until'),
    @('Bearbeiten ...', 'Edit ...'),
    @('Wieder scharf', 'Arm again'),
    @('Bis morgen pausieren', 'Pause until tomorrow'),
    @('Rückgängig', 'Undo'),
    @('Verlauf ...', 'History ...'),
    @('Alarm {0} {1} gelöscht', 'Alert {0} {1} deleted'),
    @('CSV export ...', 'CSV export ...'),
    @('{0} Einträge (höchstens 500)', '{0} entries (500 at most)'),
    @('Ziele je Depot in {0} - in die Ziel-Spalten tippen (leer = kein Ziel)', 'Goals per portfolio in {0} - type into the goal columns (empty = no goal)'),
    @('Ziel Wert', 'Value goal'),
    @('Stand', 'Progress'),
    @('Div. 12 Monate', 'Div. 12 months'),
    @('Ziel Dividenden', 'Dividend goal'),
    @('Stand ', 'Progress '),
    @('In diesem Depot dieses Jahr gebucht: {0}', 'Booked in this portfolio this year: {0}'),
    @('{0} Position(en) ohne Kurs', '{0} position(s) without a quote'),
    @('* mit zwischengespeicherten Kursen', '* with cached quotes'),
    @('+ Dividendendaten fehlen noch für {0} Position(en)', '+ dividend data still missing for {0} position(s)'),
    @('Ziele gespeichert', 'Goals saved'),
    @('Suche', 'Search'),
    @('Broker zuweisen ...', 'Assign broker ...'),
    @('Broker zuweisen', 'Assign broker'),
    @('Broker für {0} markierte Buchung(en), leer = entfernen', 'Broker for {0} selected booking(s), empty = remove'),
    @('Alle Broker', 'All brokers'),
    @('(ohne Broker)', '(no broker)'),
    @('{4} Buchungen  |  realisiert {0}: {1:+0.00;-0.00} {2}  |  gesamt: {3:+0.00;-0.00} {2}  (aktueller Kurs)', '{4} bookings  |  realised {0}: {1:+0.00;-0.00} {2}  |  total: {3:+0.00;-0.00} {2}  (current rate)'),
    @('Zum Löschen bitte genau eine Buchung markieren.', 'To delete, select exactly one booking.'),
    @('Volumen', 'Volume'),
    @('je Order', 'per order'),
    @('vom Volumen', 'of volume'),
    @('Kosten und Zinsen je Jahr', 'Costs and interest per year'),
    @('je Depot', 'by portfolio'),
    @('je Broker', 'by broker'),
    @('Gruppierung', 'Grouping'),
    @('Beträge in {0}. Nur Käufe und Verkäufe, alle Depots. Broker vergibst du in der Transaktionshistorie.', 'Amounts in {0}. Buys and sells only, all portfolios. Assign brokers in the transaction history.'),
    @('Nächste Termine', 'Upcoming dates'),
    @('Keine Termine in 45 Tagen bekannt', 'No dates known for the next 45 days'),
    @('Ziel {0:N0}%', 'Goal {0:N0}%'),
    @('morgen', 'tomorrow'),
    @('in {0} T', 'in {0} d'),
    @('Übersicht beim Start öffnen', 'Open overview at start'),
    @('Übersicht (F6)', 'Overview (F6)'),
    @('Übersicht', 'Overview'),
    @('Noch keine Positionen', 'No positions yet'),
    @('Im Tab Portfolio eine Position anlegen oder eine CSV-Datei importieren.', 'Add a position in the Portfolio tab or import a CSV file.'),
    @('heute', 'today'),
    @('Gesamt', 'Total'),
    @('{0} ohne Kurs: zum Einstand gerechnet', '{0} without a price: counted at cost'),
    @('Gespeicherte Kurse, Aktualisierung läuft', 'Saved prices, refreshing'),
    @('5 Tage (heutige Stückzahlen)', '5 days (current share counts)'),
    @('Verlauf erscheint, sobald alle Kurse geladen sind', 'The trend appears once all prices are loaded'),
    @('Depot heute', 'Portfolio today'),
    @('nach Wert', 'by value'),
    @('+ {0} weitere im Portfolio-Tab', '+ {0} more in the Portfolio tab'),
    @('Keine Positionen', 'No positions'),
    @('Übrige', 'Other'),
    @('Watchlist in Bewegung', 'Watchlist movers'),
    @('ohne Depotwerte', 'excluding holdings'),
    @('Noch keine Kurse', 'No prices yet'),
    @('Neueste Meldungen', 'Latest news'),
    @('Noch keine Meldungen geladen (Tab News)', 'No news loaded yet (News tab)'),
    @('Importieren ...', 'Import ...'),
    @('Dieses Theme löschen', 'Delete this theme'),
    @('Bitte einen eigenen Namen eingeben (höchstens 30 Zeichen, nicht der Name eines eingebauten Themes).', 'Please enter your own name (30 characters at most, not the name of a built-in theme).'),
    @('Bitte erst einen eigenen Namen eingeben.', 'Please enter your own name first.'),
    @('Theme exportiert', 'Theme exported'),
    @('Die Datei ist kein gültiges Theme.', 'The file is not a valid theme.'),
    @('Theme löschen:', 'Delete theme:'),
    @('Tastenkürzel und Favoriten', 'Shortcuts and favourites'),
    @('Taste z. B. ''Strg+Shift+S'' oder ''J''. Eigene Kürzel haben Vorrang vor den eingebauten. Favoriten stehen im Menü ''Favoriten'' und im Rechtsklick auf einen Ticker.', 'Key e.g. ''Strg+Shift+S'' (Strg = Ctrl) or ''J''. Your shortcuts win over built-in ones. Favourites appear in the ''Favourites'' menu and on right-clicking a ticker.'),
    @('Aktion', 'Action'),
    @('Eigene Taste', 'Your key'),
    @('Favorit', 'Favourite'),
    @('Favoriten', 'Favourites'),
    @('Nach oben', 'Move up'),
    @('Nach unten', 'Move down'),
    @('Diese Taste geht nicht:', 'This key cannot be used:'),
    @('Tastenkürzel', 'Shortcuts'),
    @('Doppelt vergeben:', 'Used twice:'),
    @('Jetzt aktualisieren', 'Refresh now'),
    @('Zusammenfassung', 'Summary'),
    @('Gewinner / Verlierer', 'Movers'),
    @('Ziele und Kosten', 'Goals and costs'),
    @('Nachkauf-Rechner', 'Add-on buy calculator'),
    @('Transaktion buchen', 'Book a transaction'),
    @('Transaktionshistorie', 'Transaction history'),
    @('Kombinierter Alarm', 'Combined alert'),
    @('Alarm-Vorlagen', 'Alert templates'),
    @('Alarm-Verlauf', 'Alert history'),
    @('Privat-Modus', 'Privacy mode'),
    @('Nächstes Theme', 'Next theme'),
    @('Zielkurs für den aktiven Ticker', 'Target price for the active ticker'),
    @('Preisachse automatisch', 'Price axis automatic'),
    @('Broker-CSV importieren', 'Import broker CSV'),
    @('Kennzahlen-Kacheln', 'Key figure tiles'),
    @('Haken = anzeigen. Reihenfolge mit den Pfeilen.', 'Tick = show. Order with the arrows.'),
    @('Ergebnis', 'Result'),
    @('Rendite p.a.', 'Return p.a.'),
    @('Dividenden', 'Dividends'),
    @('Im Zeitraum', 'In period'),
    @('Profil:', 'Profile:'),
    @('Aktuelle Spalten speichern ...', 'Save current columns ...'),
    @('Spaltenset speichern', 'Save column set'),
    @('Name (vorhandener Name wird ersetzt):', 'Name (an existing name is replaced):'),
    @('Für dieses Layout merken', 'Use for this layout'),
    @('Spaltenset mit dem Layout verknüpft', 'Column set linked to the layout'),
    @('Für diese Watchlist-Gruppe merken', 'Use for this watchlist group'),
    @('Spaltenset mit der Gruppe verknüpft', 'Column set linked to the group'),
    @('Dieses Spaltenset löschen', 'Delete this column set'),
    @('Spaltenset löschen:', 'Delete column set:'),
    @('Alle Verknüpfungen entfernen', 'Remove all links'),
    @('Eigenes Theme ...', 'Own theme ...'),
    @('Aktuelle Ansicht als Profil speichern ...', 'Save current view as profile ...'),
    @('Profil speichern', 'Save profile'),
    @('Name, z. B. Arbeit oder Privat:', 'Name, e.g. Work or Home:'),
    @('Aktives Profil löschen', 'Delete active profile'),
    @('Profil löschen:', 'Delete profile:'),
    @('Spaltensets', 'Column sets'),
    @('Profile', 'Profiles'),
    @('Farbregeln ...', 'Colour rules ...'),
    @('Kennzahlen-Kacheln ...', 'Key figure tiles ...'),
    @('Tastenkürzel und Favoriten ...', 'Shortcuts and favourites ...'),
    @('Zielkurs ...', 'Target price ...'),
    @('Der Alarm löst erst aus, wenn beide Bedingungen gleichzeitig erfüllt sind.', 'The alert fires only when both conditions are true at the same time.'),
    @('Bedingung 1', 'Condition 1'),
    @('UND Bedingung 2', 'AND condition 2'),
    @('Anlegen', 'Create'),
    @('Trendlinien-Alarme lassen sich nicht kombinieren.', 'Trend line alerts cannot be combined.'),
    @('Trailing % geht nur als erste Bedingung.', 'Trailing % only works as the first condition.'),
    @('Depot-Bedingungen lassen sich nur mit Depot-Bedingungen kombinieren.', 'Portfolio conditions can only be combined with portfolio conditions.'),
    @('Zwei gleiche Bedingungen ergeben keinen Sinn.', 'Two identical conditions make no sense.'),
    @('Depot-Positionen', 'Portfolio positions'),
    @('Ganze Watchlist', 'Whole watchlist'),
    @('Gruppe', 'Group'),
    @('UND', 'AND'),
    @('Eine Vorlage legt denselben Alarm für viele Ticker an. Nur Bedingungen ohne festen Kurs.', 'A template creates the same alert for many tickers. Only conditions without a fixed price.'),
    @('Anwenden auf', 'Apply to'),
    @('Anwenden ...', 'Apply ...'),
    @('Neue Vorlage', 'New template'),
    @('UND (optional)', 'AND (optional)'),
    @('Vorlage speichern', 'Save template'),
    @('Bitte einen Namen eingeben (höchstens 40 Zeichen).', 'Please enter a name (40 characters at most).'),
    @('Erst eine Vorlage wählen oder speichern.', 'Choose or save a template first.'),
    @('Nichts anzulegen: Die Alarme gibt es schon, oder es fehlen Positionen.', 'Nothing to create: the alerts exist already, or positions are missing.'),
    @('{0} Alarme anlegen? Bereits erfüllte lösen sofort aus.', 'Create {0} alerts? Those already met fire immediately.'),
    @('{0} Alarme angelegt.', '{0} alerts created.'),
    @('Vorwarnzeit für Termine', 'Notice lead time'),
    @('Hinweise für Positionen im Depot.', 'Notices for positions in your portfolio.'),
    @('Aus', 'Off'),
    @('Am selben Tag', 'Same day'),
    @('1 Tag vorher', '1 day before'),
    @('2 Tage vorher', '2 days before'),
    @('3 Tage vorher', '3 days before'),
    @('7 Tage vorher', '7 days before'),
    @('14 Tage vorher', '14 days before'),
    @('Ex-Dividende', 'Ex-dividend'),
    @('Quartalszahlen', 'Earnings'),
    @('Ex-Tag', 'Ex-date'),
    @('Zahltag', 'Pay date'),
    @('Keine Termine zum Exportieren', 'No dates to export'),
    @('{0} Termine exportiert', '{0} dates exported'),
    @('Export fehlgeschlagen:', 'Export failed:'),
    @('Kalender', 'Calendar'),
    @('Als .ics speichern ...', 'Save as .ics ...'),
    @('7 Tage', '7 days'),
    @('Heute', 'Today'),
    @('keine Positionen', 'no positions'),
    @('Wert jetzt', 'Value now'),
    @('{0} von {1} Positionen fehlen (keine Kurse für den Zeitraum)', '{0} of {1} positions missing (no prices for the period)'),
    @('noch keine Kurse für den Zeitraum', 'no prices for the period yet'),
    @('Stärkste', 'Strongest'),
    @('Schwächste', 'Weakest'),
    @('Bewegungen', 'Moves'),
    @('für {0} Ticker fehlen Kurse', 'prices missing for {0} tickers'),
    @('Termine', 'Dates'),
    @('nächste 7 Tage', 'next 7 days'),
    @('keine bekannt', 'none known'),
    @('Alarme', 'Alerts'),
    @('Schlagzeilen', 'Headlines'),
    @('keine geladen', 'none loaded'),
    @('Von selbst zeigen:', 'Show by itself:'),
    @('nie', 'never'),
    @('täglich', 'daily'),
    @('wöchentlich', 'weekly'),
    @('Was', 'What'),
    @('Wert', 'Value'),
    @('Zusammenfassung ...', 'Summary ...'),
    @('Kombinierter Alarm ...', 'Combined alert ...'),
    @('Alarm-Vorlagen ...', 'Alert templates ...'),
    @('Vorwarnzeit für Termine ...', 'Notice lead time ...'),
    @('Termine als .ics speichern ...', 'Save dates as .ics ...'),
    @('1 Woche pausieren', 'Pause for 1 week'),
    @('Alle Depots', 'All depots'),
    @('kein Ziel gesetzt', 'no goal set'),
    @('Ziel erreicht', 'goal reached'),
    @('es fehlen', 'missing'),
    @('Depotwert', 'Portfolio value'),
    @('noch keine Kurse für alle Positionen', 'no prices for all positions yet'),
    @('Dividenden, Prognose 12 Monate', 'Dividends, 12-month forecast'),
    @('Dieses Jahr gebucht: {0}', 'Booked this year: {0}'),
    @('Prognose unvollständig: {0} von {1} Positionen ohne Dividendendaten', 'Forecast incomplete: {0} of {1} positions without dividend data'),
    @('Beträge in {0}. Gebühren aus Buchungen und Cash-Konto, Zinsen aus dem Cash-Konto.', 'Amounts in {0}. Fees from bookings and cash account, interest from the cash account.'),
    @('Teilweise mit heutigem Wechselkurs gerechnet (Tageskurse lädt die Analyse).', 'Partly converted at today''s rate (the analysis loads daily rates).'),
    @('Ziele für das Depot ''{0}'', in {1} (leer = kein Ziel)', 'Goals for portfolio ''{0}'', in {1} (empty = no goal)'),
    @('Dividenden pro Jahr', 'Dividends per year'),
    @('Ziele speichern', 'Save goals'),
    @('Neu berechnen', 'Recalculate'),
    @('Kosten und Zinsen je Jahr und Depot', 'Costs and interest by year and portfolio'),
    @('Jahr', 'Year'),
    @('Ordergebühren', 'Order fees'),
    @('Kontogebühren', 'Account fees'),
    @('Kosten gesamt', 'Total costs'),
    @('Zinsen', 'Interest'),
    @('Bitte eine Zahl eingeben.', 'Please enter a number.'),
    @('{0} Ticker exportiert', '{0} tickers exported'),
    @('Die Datei ist zu groß.', 'The file is too large.'),
    @('Datei nicht lesbar:', 'File cannot be read:'),
    @('Keine Ticker gefunden. Erwartet wird eine Kopfzeile mit der Spalte ''Ticker''.', 'No tickers found. A header line with a ''Ticker'' column is expected.'),
    @('{0} Zeilen: {1} neue Ticker, {2} übersprungen.', '{0} rows: {1} new tickers, {2} skipped.'),
    @('Zielkurse und Notizen aus der Datei ersetzen vorhandene. Es wird nichts gelöscht. Importieren?', 'Targets and notes in the file replace existing ones. Nothing is deleted. Import?'),
    @('{0} neue Ticker importiert', '{0} new tickers imported'),
    @('Ziele und Kosten ...', 'Goals and costs ...'),
    @('Watchlist exportieren (CSV) ...', 'Export watchlist (CSV) ...'),
    @('Watchlist importieren (CSV) ...', 'Import watchlist (CSV) ...'),
    @('Value-at-Risk 95% (1 Tag, historisch)', 'Value-at-Risk 95% (1 day, historical)'),
    @('Value-at-Risk 95% (1 Zeitschritt, historisch)', 'Value-at-Risk 95% (1 step, historical)'),
    @('In 95 von 100 Zeitschritten war der Verlust kleiner als dieser Wert (aus dem gewählten Zeitraum, keine Garantie).', 'In 95 of 100 steps the loss was smaller than this (from the selected period, no guarantee).')
)) { if (-not $script:EnText.ContainsKey($pair[0])) { $script:EnText[$pair[0]] = $pair[1] } }

function Save-Config { Save-JsonState -Path $script:ConfigPath -Data $script:Config }
function Copy-ConfigValue { param($V) if ($null -eq $V) { return $null } return (ConvertTo-Json -InputObject $V -Depth 8 | ConvertFrom-Json) }

# ==============================================================================
# price axis: wheel = stretch / squeeze, drag = move, double click = automatic
# ==============================================================================
function Test-PriceAxisHit {
    param($L, [int]$X, [int]$Y)
    if ($null -eq $L -or $null -eq $L.PriceRect) { return $false }
    $my = $Y - [int]$L.OffsetY
    return ($X -gt ([int]$L.PriceRect.Right + 2) -and $my -ge [int]$L.PriceRect.Top -and $my -le [int]$L.PriceRect.Bottom)
}

function Reset-PriceScale {
    $script:PriceScale = 1.0
    $script:PriceShift = 0.0
    $script:PriceDrag = $null
    Refresh-ChartView
}

function Set-PriceScale {
    param([double]$Scale = $script:PriceScale, [double]$Shift = $script:PriceShift)
    $script:PriceScale = [math]::Min(8.0, [math]::Max(0.1, $Scale))
    $script:PriceShift = [math]::Min(4.0, [math]::Max(-4.0, $Shift))
    $script:PriceScaleKey = [string]$script:ActiveSeriesKey
    Refresh-ChartView
}

function Test-PriceScaled { return ([math]::Abs($script:PriceScale - 1.0) -gt 1e-6 -or [math]::Abs($script:PriceShift) -gt 1e-6) }

# ==============================================================================
# colour rules
# ==============================================================================
function Get-ColorRules {
    $r = @(@($script:Config.ColorRules) | Where-Object { $null -ne $_ })
    if ($r.Count -eq 0) { return @(Get-DefaultColorRules) }
    return $r
}

function Get-RuleFacts {
    # the numbers one list row is judged by (prices in the quote's currency)
    param([string]$Sym)
    $f = @{}
    $q = $script:QuoteStore[$Sym]
    if ($null -eq $q -or [double]$q.Price -le 0) { return $f }
    $px = [double]$q.Price
    $f.DayPct = [double]$q.ChangePct
    $f.DayAbsPct = [math]::Abs([double]$q.ChangePct)
    $f.Rsi = [double]$q.Rsi14
    if ([double]$q.High52 -gt 0) { $f.High52Pct = [math]::Abs($px / [double]$q.High52 - 1.0) * 100.0 }
    $levels = @()
    foreach ($a in $script:Alerts) {
        if ([string]$a.Ticker -ne $Sym -or [bool]$a.Triggered -or (Get-AlertKind ([string]$a.Condition)) -ne "PRICE") { continue }
        if ([string]$a.Currency -notmatch '^[A-Z]{3}$') { continue }
        $levels += [double](Convert-CurrencyValue -Amount ([double]$a.TargetPrice) -FromCurrency ([string]$a.Currency) -ToCurrency ([string]$q.Currency))
    }
    $ot = Get-OwnTarget $Sym
    if ($null -ne $ot) { $levels += [double](Convert-CurrencyValue -Amount ([double]$ot.Price) -FromCurrency ([string]$ot.Currency) -ToCurrency ([string]$q.Currency)) }
    $f.Near = Get-NearestDistancePct -Price $px -Levels ([double[]]$levels)
    $pf = $script:Portfolio[$Sym]
    if ($null -ne $pf -and [double]$pf.Shares -gt 0 -and [double]$pf.AvgPrice -gt 0) {
        $avg = [double](Convert-CurrencyValue -Amount ([double]$pf.AvgPrice) -FromCurrency ([string]$pf.Currency) -ToCurrency ([string]$q.Currency))
        if ($avg -gt 0) { $f.TotalPct = ($px / $avg - 1.0) * 100.0 }
    }
    return $f
}

function Set-RowRuleColor {
    param($Row, [string]$Sym, $Rules)
    $hit = Get-MatchingColorRule -Rules $Rules -Facts (Get-RuleFacts $Sym)
    if ($null -eq $hit) { return }
    $rgb = ConvertFrom-HexColor ([string]$hit.Color)
    if ($null -eq $rgb) { return }
    $Row.DefaultCellStyle.BackColor = Get-BlendColor -A ([System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2])) -B $script:Pal.Card -T 0.24
    $first = $Row.Cells[0]
    if (-not $first.ToolTipText) { $first.ToolTipText = (Tr "Farbregel:") + " " + [string]$hit.Name }
}

# ==============================================================================
# own columns of the watchlist
# ==============================================================================
function Get-OwnTarget {
    param([string]$Sym)
    $all = $script:Config.OwnTargets
    if ($null -eq $all) { return $null }
    $p = $all.PSObject.Properties[$Sym]
    if ($null -eq $p -or $null -eq $p.Value -or [double]$p.Value.Price -le 0) { return $null }
    return $p.Value
}

function Set-OwnTarget {
    # Price 0 removes the target
    param([string]$Sym, [double]$Price, [string]$Currency)
    $all = $script:Config.OwnTargets
    if ($null -eq $all) { $all = [PSCustomObject]@{}; $script:Config.OwnTargets = $all }
    if ($Price -le 0) { $all.PSObject.Properties.Remove($Sym) }
    else { $all | Add-Member -NotePropertyName $Sym -NotePropertyValue ([PSCustomObject]@{ Price = $Price; Currency = $Currency }) -Force }
    Save-Config
}

function Show-OwnTargetDialog {
    param([string]$Sym)
    if (-not $Sym) { return }
    $q = $script:QuoteStore[$Sym]
    $old = Get-OwnTarget $Sym
    $cur = if ($null -ne $old) { [string]$old.Currency } elseif ($null -ne $q) { [string]$q.Currency } else { Get-PriceCurrency $Sym }
    $val = if ($null -ne $old) { ([double]$old.Price).ToString("0.########") } else { "" }
    $txt = Read-TextInput -Title ((Tr "Zielkurs") + " " + $Sym) -Prompt ((Tr "Eigener Zielkurs in") + " $cur " + (Tr "(leer = entfernen)")) -Value $val -Validate {
        param($t) if ($t.Trim() -and -not (Test-DecimalInput $t)) { "Bitte eine Zahl eingeben." } else { "" }
    }
    if ($null -eq $txt) { return }
    $v = if ($txt) { Parse-DecimalInput $txt } else { 0.0 }
    Set-OwnTarget -Sym $Sym -Price $v -Currency $cur
    Refresh-WatchlistAndAlerts
}

function Add-WatchlistExtras {
    # fills the v7.8 columns and applies the colour rules (called after the rows are built)
    $cols = @("OwnTgt", "AlertDist", "Note", "DayBase") | Where-Object { $null -ne $dgvWatchlist.Columns[$_] -and $dgvWatchlist.Columns[$_].Visible }
    $rules = @(Get-ColorRules | Where-Object { [bool]$_.On })
    if (@($cols).Count -eq 0 -and $rules.Count -eq 0) { return }
    $base = [string]$script:Config.Currency
    foreach ($row in $dgvWatchlist.Rows) {
        $sym = ([string]$row.Cells[0].Value).Trim().ToUpper()
        if (-not $sym -or [string]$row.Tag -eq "skel") { continue }
        $q = $script:QuoteStore[$sym]
        if ($null -eq $q) { continue }
        if ($cols -contains "OwnTgt") {
            $row.Cells["OwnTgt"].Value = "-"
            $ot = Get-OwnTarget $sym
            if ($null -ne $ot) {
                $tq = [double](Convert-CurrencyValue -Amount ([double]$ot.Price) -FromCurrency ([string]$ot.Currency) -ToCurrency ([string]$q.Currency))
                $dist = if ([double]$q.Price -gt 0) { ($tq / [double]$q.Price - 1.0) * 100.0 } else { 0.0 }
                $row.Cells["OwnTgt"].Value = "{0:N2} {1} ({2:+0.0;-0.0;0.0}%)" -f [double]$ot.Price, $ot.Currency, $dist
                $row.Cells["OwnTgt"].ToolTipText = Tr "Abstand vom aktuellen Kurs bis zum eigenen Zielkurs"
            }
        }
        if ($cols -contains "AlertDist") {
            $best = [double]::NaN
            $lv = @()
            foreach ($a in $script:Alerts) {
                if ([string]$a.Ticker -ne $sym -or [bool]$a.Triggered -or (Get-AlertKind ([string]$a.Condition)) -ne "PRICE" -or [string]$a.Currency -notmatch '^[A-Z]{3}$') { continue }
                $lv += [double](Convert-CurrencyValue -Amount ([double]$a.TargetPrice) -FromCurrency ([string]$a.Currency) -ToCurrency ([string]$q.Currency))
            }
            $best = Get-NearestDistancePct -Price ([double]$q.Price) -Levels ([double[]]$lv)
            $row.Cells["AlertDist"].Value = if ([double]::IsNaN($best)) { "-" } else { "{0:N1}%" -f $best }
            $row.Cells["AlertDist"].ToolTipText = Tr "Abstand zum nächsten aktiven Kurs-Alarm"
        }
        if ($cols -contains "Note") {
            $nt = Get-TickerNote $sym
            $row.Cells["Note"].Value = if ($nt) { Get-NoteSnippet $nt -Max 60 } else { "" }
            if ($nt) { $row.Cells["Note"].ToolTipText = $nt }
        }
        if ($cols -contains "DayBase") {
            $pc = [double]$q.PrevClose
            if ($pc -gt 0) {
                $per = [double](Convert-CurrencyValue -Amount ([double]$q.Price - $pc) -FromCurrency ([string]$q.Currency) -ToCurrency $base)
                $pf = $script:Portfolio[$sym]
                if ($null -ne $pf -and [double]$pf.Shares -gt 0) {
                    $row.Cells["DayBase"].Value = Protect-Amount -Text ("{0:+#,##0.00;-#,##0.00;0.00} {1}" -f ($per * [double]$pf.Shares), $base) -On ([bool]$script:Config.PrivacyMode)
                    $row.Cells["DayBase"].ToolTipText = Tr "Heutige Änderung deiner Position (heutiger Wechselkurs)"
                } else {
                    $row.Cells["DayBase"].Value = "{0:+#,##0.00;-#,##0.00;0.00} {1}" -f $per, $base
                    $row.Cells["DayBase"].ToolTipText = Tr "Heutige Änderung je Stück (keine Position)"
                }
                $row.Cells["DayBase"].Style.ForeColor = if ($per -ge 0) { $colGreen } else { $colRed }
            } else { $row.Cells["DayBase"].Value = "-" }
        }
        if ($rules.Count -gt 0) { Set-RowRuleColor -Row $row -Sym $sym -Rules $rules }
    }
}

function Add-PortfolioRuleColors {
    $rules = @(Get-ColorRules | Where-Object { [bool]$_.On })
    if ($rules.Count -eq 0) { return }
    foreach ($row in $dgvPortfolio.Rows) {
        $sym = ([string]$row.Cells[0].Value).Trim().ToUpper()
        if ($sym -and $script:Portfolio.ContainsKey($sym)) { Set-RowRuleColor -Row $row -Sym $sym -Rules $rules }
    }
}

# ==============================================================================
# small helpers for the editor windows
# ==============================================================================
function New-V8Button {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$W)
    $b = New-Object System.Windows.Forms.Button
    $b.SetBounds($X, $Y, $W, (S 28)); $b.Text = $Text
    Style-FlatButton -Btn $b -BgColor $script:Pal.Input -FgColor $script:Pal.Text -BorderColor $script:Pal.Border
    $Parent.Controls.Add($b)
    return $b
}

function New-V8Label {
    param($Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 0, [switch]$Muted)
    $l = New-Object System.Windows.Forms.Label
    if ($H -le 0) { $H = S 18 }
    $l.SetBounds($X, $Y, $W, $H); $l.Text = $Text
    $l.ForeColor = if ($Muted) { $script:Pal.Muted } else { $script:Pal.Text }
    $Parent.Controls.Add($l)
    return $l
}

function New-V8Text {
    param($Parent, [string]$Value, [int]$X, [int]$Y, [int]$W)
    $t = New-Object System.Windows.Forms.TextBox
    $t.SetBounds($X, $Y, $W, (S 24)); $t.Text = $Value
    $t.BackColor = $script:Pal.Input; $t.ForeColor = $script:Pal.Text; $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $Parent.Controls.Add($t)
    return $t
}

function New-V8Combo {
    param($Parent, [string[]]$Items, [string]$Selected, [int]$X, [int]$Y, [int]$W)
    $c = New-Object System.Windows.Forms.ComboBox
    $c.SetBounds($X, $Y, $W, (S 24)); $c.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $c.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $c.BackColor = $script:Pal.Input; $c.ForeColor = $script:Pal.Text
    foreach ($i in @($Items)) { [void]$c.Items.Add($i) }
    $ix = $c.Items.IndexOf($Selected)
    if ($c.Items.Count -gt 0) { $c.SelectedIndex = [math]::Max(0, $ix) }
    $Parent.Controls.Add($c)
    return $c
}

function New-V8Grid {
    param($Parent, [int]$X, [int]$Y, [int]$W, [int]$H, [switch]$Editable)
    $g = New-Object System.Windows.Forms.DataGridView
    $g.SetBounds($X, $Y, $W, $H)
    Style-DataGrid -Grid $g
    $g.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    if ($Editable) {
        $g.ReadOnly = $false
        $g.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::CellSelect
        $g.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnEnter
    }
    $Parent.Controls.Add($g)
    return $g
}

function Add-V8Column {
    # Kind: text / check / combo
    param($Grid, [string]$Name, [string]$Header, [int]$Weight, [string]$Kind = "text", [string[]]$Items = @(), [switch]$ReadOnly)
    $col = switch ($Kind) {
        "check" { New-Object System.Windows.Forms.DataGridViewCheckBoxColumn }
        "combo" { $cc = New-Object System.Windows.Forms.DataGridViewComboBoxColumn; foreach ($i in $Items) { [void]$cc.Items.Add($i) }; $cc.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat; $cc }
        default { New-Object System.Windows.Forms.DataGridViewTextBoxColumn }
    }
    $col.Name = $Name; $col.HeaderText = Tr $Header; $col.FillWeight = [float]$Weight
    $col.SortMode = [System.Windows.Forms.DataGridViewColumnSortMode]::NotSortable
    [void]$Grid.Columns.Add($col)
    if ($ReadOnly) { $Grid.Columns[$Name].ReadOnly = $true }
}

# ==============================================================================
# colour rule editor
# ==============================================================================
function Show-ColorRulesDialog {
    $dlg = New-DialogForm -Title "Farbregeln" -W (S 820) -H (S 420) -Key "ColorRules"
    [void](New-V8Label $dlg (Tr "Die erste passende, eingeschaltete Regel färbt die Zeile (Watchlist und Portfolio). Farbe als #RRGGBB, Doppelklick öffnet die Farbwahl.") (S 12) (S 10) (S 796) -Muted)
    $g = New-V8Grid $dlg (S 12) (S 34) (S 796) (S 324) -Editable
    $fields = Get-ColorRuleFields
    $names = @($fields.Values | ForEach-Object { Tr $_ })
    Add-V8Column $g "On" "An" 30 "check"
    Add-V8Column $g "Name" "Name" 150
    Add-V8Column $g "Field" "Wert" 200 "combo" $names
    Add-V8Column $g "Op" "Vergleich" 60 "combo" @(">=", "<=")
    Add-V8Column $g "Value" "Zahl" 60
    Add-V8Column $g "Color" "Farbe" 70
    $script:RuleCtl = @{ Dlg = $dlg; Grid = $g; Keys = @($fields.Keys); Names = $names }
    $script:RuleCtl.Add = {
        param($r)
        $ix = [array]::IndexOf([string[]]$script:RuleCtl.Keys, [string]$r.Field)
        $i = $script:RuleCtl.Grid.Rows.Add([bool]$r.On, [string]$r.Name, $script:RuleCtl.Names[[math]::Max(0, $ix)], [string]$r.Op, ([double]$r.Value).ToString("0.####"), [string]$r.Color)
        $script:RuleCtl.Grid.Rows[$i].Tag = [string]$r.Id
        Update-RuleSwatch $script:RuleCtl.Grid.Rows[$i]
    }
    foreach ($r in (Get-ColorRules)) { & $script:RuleCtl.Add $r }
    $g.Add_DataError({ param($sender, $e) $e.ThrowException = $false })
    $g.Add_CellEndEdit({ param($sender, $e) Update-RuleSwatch $sender.Rows[$e.RowIndex] })
    $g.Add_CellDoubleClick({
        param($sender, $e)
        if ($e.RowIndex -lt 0 -or $sender.Columns[$e.ColumnIndex].Name -ne "Color") { return }
        $sender.EndEdit() | Out-Null
        $hex = Select-HexColor -Current ([string]$sender.Rows[$e.RowIndex].Cells["Color"].Value)
        if ($hex) { $sender.Rows[$e.RowIndex].Cells["Color"].Value = $hex; Update-RuleSwatch $sender.Rows[$e.RowIndex] }
    })
    $bNew = New-V8Button $dlg (Tr "Neue Regel") (S 12) (S 378) (S 110)
    $bDel = New-V8Button $dlg (Tr "Löschen") (S 128) (S 378) (S 90)
    $bStd = New-V8Button $dlg (Tr "Vorlagen wiederherstellen") (S 224) (S 378) (S 190)
    $bOk  = New-V8Button $dlg (Tr "Speichern") (S 608) (S 378) (S 96)
    $bNo  = New-V8Button $dlg (Tr "Abbrechen") (S 712) (S 378) (S 96)
    $bNo.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.CancelButton = $bNo
    $bNew.Add_Click({ & $script:RuleCtl.Add (New-ColorRule ([Guid]::NewGuid().ToString("N")) (Tr "Eigene Regel") "DayPct" ">=" 5 "#38BDF8" $true) })
    $bDel.Add_Click({ $c = $script:RuleCtl.Grid.CurrentCell; if ($null -ne $c) { $script:RuleCtl.Grid.Rows.RemoveAt($c.RowIndex) } })
    $bStd.Add_Click({ $script:RuleCtl.Grid.Rows.Clear(); foreach ($r in (Get-DefaultColorRules)) { & $script:RuleCtl.Add $r } })
    $bOk.Add_Click({
        $gr = $script:RuleCtl.Grid
        [void]$gr.EndEdit()
        $out = @()
        foreach ($row in $gr.Rows) {
            $raw = [string]$row.Cells["Value"].Value
            if (-not (Test-DecimalInput $raw) -or $null -eq (ConvertFrom-HexColor ([string]$row.Cells["Color"].Value))) {
                Show-InfoBox ((Tr "Zahl oder Farbe ungültig in Regel:") + " " + [string]$row.Cells["Name"].Value) (Tr "Farbregeln")
                return
            }
            $ix = [array]::IndexOf([string[]]$script:RuleCtl.Names, [string]$row.Cells["Field"].Value)
            $out += New-ColorRule ([string]$row.Tag) ([string]$row.Cells["Name"].Value) $script:RuleCtl.Keys[[math]::Max(0, $ix)] ([string]$row.Cells["Op"].Value) (Parse-DecimalInput $raw) ([string]$row.Cells["Color"].Value).Trim() ([bool]$row.Cells["On"].Value)
        }
        $script:Config.ColorRules = @($out)
        Save-Config
        $script:RuleCtl.Dlg.Close()
        Refresh-WatchlistAndAlerts
        if ($viewPortfolio.Visible) { Refresh-PortfolioGrid }
    })
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
    $script:RuleCtl = $null
}

function Update-RuleSwatch {
    param($Row)
    $rgb = ConvertFrom-HexColor ([string]$Row.Cells["Color"].Value)
    if ($null -eq $rgb) { return }
    $c = [System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2])
    $st = $Row.Cells["Color"].Style
    $st.BackColor = $c; $st.SelectionBackColor = $c
    $fg = if ($c.GetBrightness() -gt 0.55) { [System.Drawing.Color]::Black } else { [System.Drawing.Color]::White }
    $st.ForeColor = $fg; $st.SelectionForeColor = $fg
}

function Select-HexColor {
    param([string]$Current)
    if ($script:SmokeMode) { return "" }
    $cd = New-Object System.Windows.Forms.ColorDialog
    $cd.FullOpen = $true
    $rgb = ConvertFrom-HexColor $Current
    if ($null -ne $rgb) { $cd.Color = [System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]) }
    $out = ""
    if ($cd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $out = ConvertTo-HexColor $cd.Color.R $cd.Color.G $cd.Color.B }
    $cd.Dispose()
    return $out
}

# ==============================================================================
# own themes
# ==============================================================================
function Set-ThemeByName {
    param([string]$Name)
    $script:Config.Theme = $Name
    Save-Config
    Apply-ThemeToAllControls
    Update-AllUiViews
}

function Save-CustomTheme {
    param($Theme)
    $list = @(@($script:Config.CustomThemes) | Where-Object { $null -ne $_ -and [string]$_.Name -ne [string]$Theme.Name })
    $script:Config.CustomThemes = @($list) + @($Theme)
    Save-Config
}

function Get-ThemeHexColors {
    # the colours of the current theme as hex values (starting point of the editor)
    $out = [ordered]@{}
    foreach ($k in (Get-ThemeColorKeys).Keys) { $c = $script:Pal[$k]; $out[$k] = ConvertTo-HexColor $c.R $c.G $c.B }
    return $out
}

function Show-ThemeEditor {
    $dlg = New-DialogForm -Title "Eigenes Theme" -W (S 520) -H (S 540) -Key "ThemeEditor"
    $cur = Get-CustomTheme ([string]$script:Config.Theme)
    $base = if ($null -ne $cur) { [string]$cur.Base } else { [string]$script:Config.Theme }
    $nm = if ($null -ne $cur) { [string]$cur.Name } else { Tr "Mein Theme" }
    [void](New-V8Label $dlg (Tr "Name") (S 12) (S 14) (S 60))
    $tName = New-V8Text $dlg $nm (S 80) (S 10) (S 190)
    [void](New-V8Label $dlg (Tr "Basis") (S 290) (S 14) (S 50))
    $cBase = New-V8Combo $dlg (Get-ThemeNames) $base (S 346) (S 10) (S 160)
    $g = New-V8Grid $dlg (S 12) (S 46) (S 496) (S 392)
    Add-V8Column $g "Part" "Bereich" 160
    Add-V8Column $g "Color" "Farbe (Klick = wählen)" 110
    $colors = Get-ThemeHexColors
    $labels = Get-ThemeColorKeys
    foreach ($k in $labels.Keys) {
        $i = $g.Rows.Add((Tr $labels[$k]), $colors[$k])
        $g.Rows[$i].Tag = $k
        Update-RuleSwatch $g.Rows[$i]
    }
    $g.Add_CellClick({
        param($sender, $e)
        if ($e.RowIndex -lt 0 -or $sender.Columns[$e.ColumnIndex].Name -ne "Color") { return }
        $hex = Select-HexColor -Current ([string]$sender.Rows[$e.RowIndex].Cells["Color"].Value)
        if ($hex) { $sender.Rows[$e.RowIndex].Cells["Color"].Value = $hex; Update-RuleSwatch $sender.Rows[$e.RowIndex] }
    })
    $script:ThemeCtl = @{ Dlg = $dlg; Grid = $g; Name = $tName; Base = $cBase }
    $script:ThemeCtl.Read = {
        $cols = [ordered]@{}
        foreach ($row in $script:ThemeCtl.Grid.Rows) { $cols[[string]$row.Tag] = [string]$row.Cells["Color"].Value }
        return (ConvertFrom-ThemeData ([PSCustomObject]@{ Name = $script:ThemeCtl.Name.Text; Base = [string]$script:ThemeCtl.Base.SelectedItem; Colors = $cols }))
    }
    [void](New-V8Label $dlg (Tr "Gewinn- und Verlustfarben stellst du in den Einstellungen ein.") (S 12) (S 444) (S 496) -Muted)
    $bSave = New-V8Button $dlg (Tr "Speichern und anwenden") (S 12) (S 468) (S 190)
    $bExp = New-V8Button $dlg (Tr "Exportieren ...") (S 208) (S 468) (S 140)
    $bImp = New-V8Button $dlg (Tr "Importieren ...") (S 354) (S 468) (S 154)
    $bDel = New-V8Button $dlg (Tr "Dieses Theme löschen") (S 12) (S 502) (S 190)
    $bNo = New-V8Button $dlg (Tr "Schließen") (S 412) (S 502) (S 96)
    $bNo.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.CancelButton = $bNo
    $bSave.Add_Click({
        $t = & $script:ThemeCtl.Read
        if ($null -eq $t) { Show-InfoBox (Tr "Bitte einen eigenen Namen eingeben (höchstens 30 Zeichen, nicht der Name eines eingebauten Themes).") (Tr "Eigenes Theme"); return }
        Save-CustomTheme $t
        Set-ThemeByName ([string]$t.Name)
        $script:ThemeCtl.Dlg.Close()
    })
    $bExp.Add_Click({
        $t = & $script:ThemeCtl.Read
        if ($null -eq $t) { Show-InfoBox (Tr "Bitte erst einen eigenen Namen eingeben.") (Tr "Eigenes Theme"); return }
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = "Theme (*.twtheme.json)|*.twtheme.json"
        $sfd.FileName = (($t.Name -replace '[^\w\-]+', '_') + ".twtheme.json")
        if ($sfd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Save-JsonState -Path $sfd.FileName -Data $t; Set-TransientStatus (Tr "Theme exportiert") 3 }
        $sfd.Dispose()
    })
    $bImp.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "Theme (*.json)|*.json"
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $t = $null
            try { if ((Get-Item $ofd.FileName).Length -lt 65536) { $t = ConvertFrom-ThemeData ([System.IO.File]::ReadAllText($ofd.FileName) | ConvertFrom-Json) } } catch { $t = $null }
            if ($null -eq $t) { Show-InfoBox (Tr "Die Datei ist kein gültiges Theme.") (Tr "Eigenes Theme") }
            else { Save-CustomTheme $t; Set-ThemeByName ([string]$t.Name); $script:ThemeCtl.Dlg.Close() }
        }
        $ofd.Dispose()
    })
    $bDel.Add_Click({
        $n = $script:ThemeCtl.Name.Text.Trim()
        $ct = Get-CustomTheme $n
        if ($null -eq $ct) { return }
        if (-not (Confirm-Action -Text ((Tr "Theme löschen:") + " " + $n + "?") -Title (Tr "Eigenes Theme"))) { return }
        $script:Config.CustomThemes = @(@($script:Config.CustomThemes) | Where-Object { $null -ne $_ -and [string]$_.Name -ne $n })
        if ([string]$script:Config.Theme -eq $n) { Set-ThemeByName ([string]$ct.Base) } else { Save-Config }
        $script:ThemeCtl.Dlg.Close()
    })
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
    $script:ThemeCtl = $null
}

# ==============================================================================
# column sets (watchlist + portfolio), switchable by name, per layout / group
# ==============================================================================
function Get-ColumnSets { return @(@($script:Config.ColumnSets) | Where-Object { $null -ne $_ -and $_.Name }) }

function Save-ColumnSet {
    param([string]$Name)
    $set = [PSCustomObject]@{ Name = $Name; Watch = @(ConvertTo-GridLayout @($dgvWatchlist.Columns)); Portfolio = @(ConvertTo-GridLayout @($dgvPortfolio.Columns)) }
    $script:Config.ColumnSets = @(@(Get-ColumnSets | Where-Object { [string]$_.Name -ne $Name })) + @($set)
    $script:ActiveColumnSet = $Name
    Save-Config
}

function Set-GridLayoutItems {
    param($Grid, [string]$Key, $Items)
    if (@($Items).Count -eq 0) { return }
    $gl = $script:Config.GridLayouts
    if ($null -eq $gl) { $gl = [PSCustomObject]@{}; $script:Config.GridLayouts = $gl }
    $gl | Add-Member -NotePropertyName $Key -NotePropertyValue @($Items) -Force
    $script:GridLayoutSig.Remove($Key)
    Restore-GridLayout -Grid $Grid -Key $Key
}

function Use-ColumnSet {
    param([string]$Name)
    $set = @(Get-ColumnSets | Where-Object { [string]$_.Name -eq $Name }) | Select-Object -First 1
    if ($null -eq $set) { return $false }
    Set-GridLayoutItems -Grid $dgvWatchlist -Key ([string]$dgvWatchlist.Tag) -Items $set.Watch
    Set-GridLayoutItems -Grid $dgvPortfolio -Key ([string]$dgvPortfolio.Tag) -Items $set.Portfolio
    $script:ActiveColumnSet = $Name
    Save-Config
    Refresh-WatchlistAndAlerts
    if ($viewPortfolio.Visible) { Refresh-PortfolioGrid }
    return $true
}

function Set-ColumnSetLink {
    # Key "Layout:Terminal" or "Group:Tech"; Name "" removes the link
    param([string]$Key, [string]$Name)
    $m = $script:Config.ColumnSetMap
    if ($null -eq $m) { $m = [PSCustomObject]@{}; $script:Config.ColumnSetMap = $m }
    if ($Name) { $m | Add-Member -NotePropertyName $Key -NotePropertyValue $Name -Force } else { $m.PSObject.Properties.Remove($Key) }
    Save-Config
}

function Update-LinkedColumnSet {
    # a linked watchlist group wins over a linked layout
    $m = $script:Config.ColumnSetMap
    if ($null -eq $m -or @($m.PSObject.Properties).Count -eq 0) { return }
    foreach ($k in @(("Group:" + [string]$script:Config.WatchGroup), ("Layout:" + [string]$script:Config.Layout))) {
        $p = $m.PSObject.Properties[$k]
        if ($null -eq $p -or -not [string]$p.Value) { continue }
        if ([string]$p.Value -ne $script:ActiveColumnSet) { [void](Use-ColumnSet ([string]$p.Value)) }
        return
    }
}

# ==============================================================================
# actions that can get an own shortcut or be a favourite
# ==============================================================================
$script:UserActions = [ordered]@{
    "refresh"     = @{ Title = "Jetzt aktualisieren"; Run = { $btnRefreshNow.PerformClick() } }
    "summary"     = @{ Title = "Zusammenfassung"; Run = { Show-SummaryDialog } }
    "calendar"    = @{ Title = "Kalender"; Run = { Show-CalendarDialog } }
    "movers"      = @{ Title = "Gewinner / Verlierer"; Run = { Show-MoversDialog } }
    "analysis"    = @{ Title = "Analyse"; Run = { Show-AnalysisDialog } }
    "goals"       = @{ Title = "Ziele und Kosten"; Run = { Show-GoalsCostsDialog } }
    "calculator"  = @{ Title = "Nachkauf-Rechner"; Run = { Show-PortfolioCalculator } }
    "transaction" = @{ Title = "Transaktion buchen"; Run = { Show-TransactionDialog -Ticker ([string]$script:Config.ActiveTicker) } }
    "history"     = @{ Title = "Transaktionshistorie"; Run = { Show-TransactionHistory } }
    "combo"       = @{ Title = "Kombinierter Alarm"; Run = { Show-ComboAlertDialog } }
    "templates"   = @{ Title = "Alarm-Vorlagen"; Run = { Show-AlertTemplatesDialog } }
    "alertlog"    = @{ Title = "Alarm-Verlauf"; Run = { Show-AlertLogDialog } }
    "privacy"     = @{ Title = "Privat-Modus"; Run = { Set-PrivacyMode (-not [bool]$script:Config.PrivacyMode) } }
    "topmost"     = @{ Title = "Immer im Vordergrund"; Run = { $btnPin.PerformClick() } }
    "theme"       = @{ Title = "Nächstes Theme"; Run = { $btnThemeCycle.PerformClick() } }
    "colorrules"  = @{ Title = "Farbregeln"; Run = { Show-ColorRulesDialog } }
    "target"      = @{ Title = "Zielkurs für den aktiven Ticker"; Run = { Show-OwnTargetDialog ([string]$script:Config.ActiveTicker).ToUpper() } }
    "pricereset"  = @{ Title = "Preisachse automatisch"; Run = { Reset-PriceScale } }
    "csvimport"   = @{ Title = "Broker-CSV importieren"; Run = { Show-CsvImportDialog } }
    "settings"    = @{ Title = "Einstellungen"; Run = { Show-SettingsDialog } }
}

function Invoke-UserAction {
    param([string]$Id)
    $a = $script:UserActions[$Id]
    if ($null -eq $a) { return }
    try { & $a.Run } catch { Write-WidgetLog "Action $Id failed: $($_.Exception.Message)" "WARN" }
}

function Get-ActionShortcut {
    param([string]$Id)
    $m = $script:Config.KeyMap
    if ($null -eq $m) { return "" }
    $p = $m.PSObject.Properties[$Id]
    if ($null -eq $p) { return "" }
    return [string]$p.Value
}

function Invoke-UserShortcut {
    # called first by the main key handler; own shortcuts win over built-in ones
    param($Sender, $E)
    $m = $script:Config.KeyMap
    if ($null -eq $m -or @($m.PSObject.Properties).Count -eq 0) { return $false }
    $text = Get-KeyShortcutText -KeyName ([string]$E.KeyCode) -Ctrl ([bool]$E.Control) -Alt ([bool]$E.Alt) -Shift ([bool]$E.Shift)
    if (-not $text) { return $false }
    # while typing, only combinations with Strg or Alt (and F-keys) count
    $ac = $Sender.ActiveControl
    $typing = ($ac -is [System.Windows.Forms.TextBox] -or $ac -is [System.Windows.Forms.ComboBox] -or $ac -is [System.Windows.Forms.ListBox])
    if ($typing -and -not ($E.Control -or $E.Alt) -and $text -notmatch '(^|\+)F\d+$') { return $false }
    foreach ($p in $m.PSObject.Properties) {
        if ([string]$p.Value -ne $text -or -not $script:UserActions.Contains($p.Name)) { continue }
        $E.Handled = $true
        $E.SuppressKeyPress = $true
        Invoke-UserAction $p.Name
        return $true
    }
    return $false
}

function Show-KeysFavoritesDialog {
    $dlg = New-DialogForm -Title "Tastenkürzel und Favoriten" -W (S 640) -H (S 560) -Key "KeysFav"
    [void](New-V8Label $dlg (Tr "Taste z. B. 'Strg+Shift+S' oder 'J'. Eigene Kürzel haben Vorrang vor den eingebauten. Favoriten stehen im Menü 'Favoriten' und im Rechtsklick auf einen Ticker.") (S 12) (S 8) (S 616) (S 34) -Muted)
    $g = New-V8Grid $dlg (S 12) (S 46) (S 616) (S 466) -Editable
    Add-V8Column $g "Action" "Aktion" 210 -ReadOnly
    Add-V8Column $g "Key" "Eigene Taste" 110
    Add-V8Column $g "Fav" "Favorit" 60 "check"
    $favs = @($script:Config.Favorites | ForEach-Object { [string]$_ })
    # favourites first, in their order
    $order = @(Select-OrderedIds -Available @($script:UserActions.Keys) -Chosen $favs -EmptyIsNone)
    $order += @($script:UserActions.Keys | Where-Object { $order -notcontains $_ })
    foreach ($id in $order) {
        $i = $g.Rows.Add((Tr $script:UserActions[$id].Title), (Get-ActionShortcut $id), [bool]($favs -contains $id))
        $g.Rows[$i].Tag = $id
    }
    $script:KeyCtl = @{ Dlg = $dlg; Grid = $g }
    $bUp = New-V8Button $dlg (Tr "Nach oben") (S 12) (S 522) (S 100)
    $bDn = New-V8Button $dlg (Tr "Nach unten") (S 118) (S 522) (S 100)
    $bOk = New-V8Button $dlg (Tr "Speichern") (S 428) (S 522) (S 96)
    $bNo = New-V8Button $dlg (Tr "Abbrechen") (S 532) (S 522) (S 96)
    $bNo.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.CancelButton = $bNo
    $script:KeyCtl.Move = {
        param([int]$Dir)
        $gr = $script:KeyCtl.Grid
        [void]$gr.EndEdit()
        if ($null -eq $gr.CurrentCell) { return }
        $i = $gr.CurrentCell.RowIndex; $j = $i + $Dir
        if ($j -lt 0 -or $j -ge $gr.Rows.Count) { return }
        $row = $gr.Rows[$i]
        $gr.Rows.RemoveAt($i)
        $gr.Rows.Insert($j, $row)
        $gr.CurrentCell = $gr.Rows[$j].Cells["Key"]
    }
    $bUp.Add_Click({ & $script:KeyCtl.Move -1 })
    $bDn.Add_Click({ & $script:KeyCtl.Move 1 })
    $bOk.Add_Click({
        $gr = $script:KeyCtl.Grid
        [void]$gr.EndEdit()
        $map = [PSCustomObject]@{}
        $used = @{}
        $fav = @()
        foreach ($row in $gr.Rows) {
            $id = [string]$row.Tag
            if ([bool]$row.Cells["Fav"].Value) { $fav += $id }
            $raw = ([string]$row.Cells["Key"].Value).Trim()
            if (-not $raw) { continue }
            $k = ConvertTo-ShortcutText $raw
            if (-not $k) { Show-InfoBox ((Tr "Diese Taste geht nicht:") + " " + $raw) (Tr "Tastenkürzel"); return }
            if ($used.ContainsKey($k)) { Show-InfoBox ((Tr "Doppelt vergeben:") + " " + $k) (Tr "Tastenkürzel"); return }
            $used[$k] = $true
            $map | Add-Member -NotePropertyName $id -NotePropertyValue $k -Force
        }
        $script:Config.KeyMap = $map
        $script:Config.Favorites = @($fav)
        Save-Config
        Update-FavoritesMenu
        $script:KeyCtl.Dlg.Close()
    })
    [void]$dlg.ShowDialog($form)
    $dlg.Dispose()
    $script:KeyCtl = $null
}

# ==============================================================================
# analysis tiles: choose and order
# ==============================================================================
function Get-KpiTileChoices {
    return [ordered]@{ "Value" = "Depotwert"; "Result" = "Ergebnis"; "Xirr" = "Rendite p.a."; "Window" = "Im Zeitraum"; "Div" = "Dividenden"
        "DivYear" = "Dividenden im Jahr"; "Unreal" = "Buchgewinn"; "Drawdown" = "Größter Rückgang"; "Vola" = "Schwankung p.a."; "Best" = "Beste Position"
        "Worst" = "Schwächste Position"; "Real" = "Realisiert"; "Bench" = "Gegen Benchmark"; "Sharpe" = "Sharpe"; "Fees" = "Gebühren" }
}

function Get-KpiTileSelection {
    # the user's tiles in their order; without a choice the first ten (two rows)
    $all = @((Get-KpiTileChoices).Keys)
    $mine = @(Select-OrderedIds -Available $all -Chosen @($script:Config.KpiTiles | ForEach-Object { [string]$_ }) -EmptyIsNone)
    if ($mine.Count -eq 0) { return @($all | Select-Object -First 10) }
    return $mine
}

function Select-KpiTiles {
    param($Tiles)
    $byId = @{}
    foreach ($t in @($Tiles)) { $byId[[string]$t.Id] = $t }
    $ids = @(Get-KpiTileSelection)
    return @($ids | Where-Object { $byId.ContainsKey($_) } | ForEach-Object { $byId[$_] })
}

function Show-KpiTilesDialog {
    param($Owner = $null)
    $sd = New-StandardDialog -Title "Kennzahlen-Kacheln" -Subtitle "Haken = anzeigen. Reihenfolge mit den Pfeilen." -W 420 -BodyH 292 -OkText "Speichern"
    $dlg = $sd.Dlg
    $dlg.TopMost = $true
    $lb = New-Object System.Windows.Forms.CheckedListBox
    $lb.SetBounds(0, 0, ($sd.Body.Width - (S 80)), (S 288)); $lb.CheckOnClick = $true
    $lb.BackColor = $script:Pal.Input; $lb.ForeColor = $script:Pal.Text; $lb.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $sd.Body.Controls.Add($lb)
    $all = Get-KpiTileChoices
    $chosen = @(Get-KpiTileSelection)
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($id in (@($chosen) + @($all.Keys | Where-Object { $chosen -notcontains $_ }))) { $ids.Add($id); [void]$lb.Items.Add((Tr $all[$id]), [bool]($chosen -contains $id)) }
    $script:KpiCtl = @{ List = $lb; Ids = $ids }
    $script:KpiCtl.Move = {
        param([int]$Dir)
        $l = $script:KpiCtl.List; $i = $l.SelectedIndex; $j = $i + $Dir
        if ($i -lt 0 -or $j -lt 0 -or $j -ge $l.Items.Count) { return }
        $txt = $l.Items[$i]; $on = $l.GetItemChecked($i); $id = $script:KpiCtl.Ids[$i]
        $l.Items.RemoveAt($i); $l.Items.Insert($j, $txt); $l.SetItemChecked($j, $on)
        $script:KpiCtl.Ids.RemoveAt($i); $script:KpiCtl.Ids.Insert($j, $id)
        $l.SelectedIndex = $j
    }
    $up = New-V8Button $sd.Body ([string][char]0x25B2) ($sd.Body.Width - (S 70)) 0 (S 70)
    $dn = New-V8Button $sd.Body ([string][char]0x25BC) ($sd.Body.Width - (S 70)) (S 34) (S 70)
    $up.Add_Click({ & $script:KpiCtl.Move -1 })
    $dn.Add_Click({ & $script:KpiCtl.Move 1 })
    if ($dlg.ShowDialog($(if ($null -ne $Owner) { $Owner } else { $form })) -eq [System.Windows.Forms.DialogResult]::OK) {
        $sel = @(for ($i = 0; $i -lt $lb.Items.Count; $i++) { if ($lb.GetItemChecked($i)) { $ids[$i] } })
        if ($sel.Count -eq 0) { $sel = @() }   # nothing ticked = back to the standard tiles
        $script:Config.KpiTiles = @($sel)
        Save-Config
        if ($null -ne $script:AnaCtl -and $null -ne $script:AnaCtl.Model) { Update-AnalysisPerf }
    }
    $dlg.Dispose()
    $script:KpiCtl = $null
}

# ==============================================================================
# profiles (e.g. work / private), switched from the menu
# ==============================================================================
function Get-ProfileSettingKeys {
    return @("Layout", "Theme", "UiStyle", "RowDensity", "WatchGroup", "PrivacyMode", "GridLayouts", "ColumnSetMap", "ColorRules", "KpiTiles", "Favorites",
             "NewsViewHidden", "NewsFilter", "ShowTrayNotifications", "PushAlerts", "TopMost", "Opacity", "TerminalShowWatch", "TerminalShowPortfolio", "TerminalChartPct")
}

function Get-UserProfiles { return @(@($script:Config.UserProfiles) | Where-Object { $null -ne $_ -and $_.Name }) }

function Save-WidgetProfile {
    param([string]$Name)
    $snap = [ordered]@{}
    foreach ($k in (Get-ProfileSettingKeys)) {
        $v = $script:Config.$k
        $snap[$k] = if ($v -is [System.Array]) { @($v) } elseif ($v -is [pscustomobject]) { Copy-ConfigValue $v } else { $v }
    }
    $prof = [PSCustomObject]@{ Name = $Name; Settings = [PSCustomObject]$snap }
    $script:Config.UserProfiles = @(@(Get-UserProfiles | Where-Object { [string]$_.Name -ne $Name })) + @($prof)
    $script:Config.ActiveProfile = $Name
    Save-Config
}

function Use-WidgetProfile {
    param([string]$Name)
    $prof = @(Get-UserProfiles | Where-Object { [string]$_.Name -eq $Name }) | Select-Object -First 1
    if ($null -eq $prof) { return $false }
    $layout = ""; $privacy = [bool]$script:Config.PrivacyMode
    foreach ($k in (Get-ProfileSettingKeys)) {
        $p = $prof.Settings.PSObject.Properties[$k]
        if ($null -eq $p) { continue }
        if ($k -eq "Layout") { $layout = [string]$p.Value; continue }
        if ($k -eq "PrivacyMode") { $privacy = [bool]$p.Value; continue }
        $v = $p.Value
        if ($k -in @("ColorRules", "KpiTiles", "Favorites", "NewsViewHidden")) { $v = @($v | Where-Object { $null -ne $_ } | ForEach-Object { Copy-ConfigValue $_ }) }
        elseif ($v -is [pscustomobject]) { $v = Copy-ConfigValue $v }
        $script:Config.$k = $v
    }
    if ([string]$script:Config.Theme -notin @(Get-AllThemeNames)) { $script:Config.Theme = "Dark" }
    $script:Config.ActiveProfile = $Name
    Save-Config
    $script:GridLayoutSig.Clear()
    $script:ActiveColumnSet = ""
    Restore-GridLayout -Grid $dgvWatchlist -Key ([string]$dgvWatchlist.Tag)
    Restore-GridLayout -Grid $dgvPortfolio -Key ([string]$dgvPortfolio.Tag)
    $form.TopMost = [bool]$script:Config.TopMost
    Apply-ThemeToAllControls
    if (-not $layout) { $layout = [string]$script:Config.Layout }
    Apply-Layout $layout
    if ($privacy -ne [bool]$script:Config.PrivacyMode) { Set-PrivacyMode $privacy }
    Update-FavoritesMenu
    Update-WatchGroupCombo
    Update-AllUiViews
    Set-TransientStatus ((Tr "Profil:") + " " + $Name) 4
    return $true
}

# ==============================================================================
# menu entries
# ==============================================================================
function Add-DynamicEntry {
    param($Parent, [string]$Text, [string]$Tag, [scriptblock]$Action, [bool]$Checked = $false)
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem($Text)
    $mi.Tag = $Tag; $mi.Checked = $Checked
    $mi.Add_Click($Action)
    [void]$Parent.DropDownItems.Add($mi)
}

function Update-ColumnSetMenu {
    $m = $script:MbColumns
    $m.DropDownItems.Clear()
    foreach ($s in (Get-ColumnSets)) { Add-DynamicEntry $m ([string]$s.Name) ([string]$s.Name) { param($sender, $e) [void](Use-ColumnSet ([string]$sender.Tag)) } ([string]$s.Name -eq $script:ActiveColumnSet) }
    if ((Get-ColumnSets).Count -gt 0) { Add-BarLine $m }
    [void](Add-BarItem $m "Aktuelle Spalten speichern ..." {
        $n = Read-TextInput -Title (Tr "Spaltenset speichern") -Prompt (Tr "Name (vorhandener Name wird ersetzt):") -Value $script:ActiveColumnSet -Validate { param($t) if (-not $t.Trim() -or $t.Trim().Length -gt 30) { "1 bis 30 Zeichen." } else { "" } }
        if ($n) { Save-ColumnSet $n }
    })
    if ($script:ActiveColumnSet) {
        [void](Add-BarItem $m "Für dieses Layout merken" { Set-ColumnSetLink -Key ("Layout:" + [string]$script:Config.Layout) -Name $script:ActiveColumnSet; Set-TransientStatus (Tr "Spaltenset mit dem Layout verknüpft") 3 })
        if ([string]$script:Config.WatchGroup) {
            [void](Add-BarItem $m "Für diese Watchlist-Gruppe merken" { Set-ColumnSetLink -Key ("Group:" + [string]$script:Config.WatchGroup) -Name $script:ActiveColumnSet; Set-TransientStatus (Tr "Spaltenset mit der Gruppe verknüpft") 3 })
        }
        [void](Add-BarItem $m "Dieses Spaltenset löschen" {
            $n = $script:ActiveColumnSet
            if (-not (Confirm-Action -Text ((Tr "Spaltenset löschen:") + " " + $n + "?"))) { return }
            $script:Config.ColumnSets = @(Get-ColumnSets | Where-Object { [string]$_.Name -ne $n })
            foreach ($p in @($script:Config.ColumnSetMap.PSObject.Properties)) { if ([string]$p.Value -eq $n) { $script:Config.ColumnSetMap.PSObject.Properties.Remove($p.Name) } }
            $script:ActiveColumnSet = ""
            Save-Config
        })
    }
    [void](Add-BarItem $m "Alle Verknüpfungen entfernen" { $script:Config.ColumnSetMap = [PSCustomObject]@{}; Save-Config })
}

function Update-ThemeMenu {
    $m = $script:MbThemes
    $m.DropDownItems.Clear()
    foreach ($n in (Get-AllThemeNames)) { Add-DynamicEntry $m $n $n { param($sender, $e) Set-ThemeByName ([string]$sender.Tag) } ($n -eq [string]$script:Config.Theme) }
    Add-BarLine $m
    [void](Add-BarItem $m "Eigenes Theme ..." { Show-ThemeEditor })
}

function Update-ProfileMenu {
    $m = $script:MbProfiles
    $m.DropDownItems.Clear()
    foreach ($p in (Get-UserProfiles)) { Add-DynamicEntry $m ([string]$p.Name) ([string]$p.Name) { param($sender, $e) [void](Use-WidgetProfile ([string]$sender.Tag)) } ([string]$p.Name -eq [string]$script:Config.ActiveProfile) }
    if ((Get-UserProfiles).Count -gt 0) { Add-BarLine $m }
    [void](Add-BarItem $m "Aktuelle Ansicht als Profil speichern ..." {
        $n = Read-TextInput -Title (Tr "Profil speichern") -Prompt (Tr "Name, z. B. Arbeit oder Privat:") -Value ([string]$script:Config.ActiveProfile) -Validate { param($t) if (-not $t.Trim() -or $t.Trim().Length -gt 30) { "1 bis 30 Zeichen." } else { "" } }
        if ($n) { Save-WidgetProfile $n }
    })
    if (@(Get-UserProfiles | Where-Object { [string]$_.Name -eq [string]$script:Config.ActiveProfile }).Count -gt 0) {
        [void](Add-BarItem $m "Aktives Profil löschen" {
            $n = [string]$script:Config.ActiveProfile
            if (-not (Confirm-Action -Text ((Tr "Profil löschen:") + " " + $n + "?"))) { return }
            $script:Config.UserProfiles = @(Get-UserProfiles | Where-Object { [string]$_.Name -ne $n })
            $script:Config.ActiveProfile = ""
            Save-Config
        })
    }
}

function Update-FavoritesMenu {
    $ids = @(Select-OrderedIds -Available @($script:UserActions.Keys) -Chosen @($script:Config.Favorites | ForEach-Object { [string]$_ }) -EmptyIsNone)
    foreach ($m in @($script:MbFavorites, $miRowFavorites)) {
        if ($null -eq $m) { continue }
        $m.DropDownItems.Clear()
        foreach ($id in $ids) {
            Add-DynamicEntry $m (Tr $script:UserActions[$id].Title) $id { param($sender, $e) Invoke-UserAction ([string]$sender.Tag) }
            $m.DropDownItems[$m.DropDownItems.Count - 1].ShortcutKeyDisplayString = Get-ActionShortcut $id
        }
    }
    # only shown once there is something in it
    if ($null -ne $script:MbFavorites) { $script:MbFavorites.Available = ($ids.Count -gt 0) }
    $script:FavoriteCount = $ids.Count
}

$script:ActiveColumnSet = ""

Add-BarLine $mbView
$script:MbColumns = Add-BarItem $mbView "Spaltensets"
$script:MbThemes = Add-BarItem $mbView "Themes"
$script:MbProfiles = Add-BarItem $mbView "Profile"
[void](Add-BarItem $mbView "Farbregeln ..." { Show-ColorRulesDialog })
[void](Add-BarItem $mbView "Kennzahlen-Kacheln ..." { Show-KpiTilesDialog })
[void](Add-BarItem $mbView "Tastenkürzel und Favoriten ..." { Show-KeysFavoritesDialog })
[void](Add-BarItem $mbView "Preisachse automatisch" { Reset-PriceScale })
# placeholders so the submenus can open; the real entries are built when the menu opens
foreach ($m0 in @($script:MbColumns, $script:MbThemes, $script:MbProfiles)) { [void](Add-BarItem $m0 "-") }
$mbView.Add_DropDownOpening({ Update-ColumnSetMenu; Update-ThemeMenu; Update-ProfileMenu })

$script:MbFavorites = New-Object System.Windows.Forms.ToolStripMenuItem((Tr "Favoriten"))
$script:MenuBar.Items.Insert($script:MenuBar.Items.IndexOf($mbHelp), $script:MbFavorites)

$miRowTarget = New-Object System.Windows.Forms.ToolStripMenuItem("Zielkurs ...")
$rowMenu.Items.Insert($rowMenu.Items.IndexOf($miRowNote) + 1, $miRowTarget)
$miRowTarget.Add_Click({ Show-OwnTargetDialog $script:RowMenuSym })
$miRowFavorites = New-Object System.Windows.Forms.ToolStripMenuItem("Favoriten")
[void]$rowMenu.Items.Add($miRowFavorites)
$rowMenu.Add_Opening({ $miRowFavorites.Visible = ($script:FavoriteCount -gt 0) })
Update-FavoritesMenu
$script:CustomReady = $true
