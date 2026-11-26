# TerminalWidget 8.0

Enthält die geplanten Schritte 7.8, 7.9 und 8.0 in einem Release.

## Fehler behoben
- Watchlist-Gruppen: Beim Anlegen oder Ändern einer **dritten** Gruppe wurden die ersten beiden zu einer verschmolzen (aus „Tech“ und „ETF“ wurde „Tech ETF“). Eine nur falsch verschachtelt gespeicherte Liste wird beim Start repariert. Bereits verschmolzene Gruppen lassen sich nicht automatisch trennen – bitte neu anlegen.

## Chart: Preisachse scrollen
- Mausrad über der Preisachse: Skala strecken / stauchen.
- Achse mit der Maus ziehen: sichtbaren Preisbereich verschieben.
- Doppelklick auf die Achse, Taste Z oder Ansicht → „Preisachse automatisch“: zurück.
- Ein anderer Ticker oder Zeitraum beginnt wieder automatisch. Gilt auch im Vollbild.

## Anpassen (7.8)
- **Spaltensets** (Watchlist + Portfolio) speichern, wechseln, mit Layout oder Watchlist-Gruppe verknüpfen (Ansicht → Spaltensets).
- Neue Watchlist-Spalten (Rechtsklick auf die Kopfzeile): Zielkurs mit Abstand, Alarm-Abstand, Notiz, Heute in Anzeigewährung. Zielkurs setzen: Rechtsklick auf den Ticker.
- **Farbregeln** für Zeilen: große Tagesbewegung, nahe Alarm/Zielkurs, RSI-Extreme, Gewinn/Verlust, plus eigene Regeln. Alle anfangs aus.
- **Eigene Themes** mit 12 Farben, Export und Import als Datei.
- **Eigene Tastenkürzel** und **Favoriten** (Menü „Favoriten“ und Rechtsklick auf einen Ticker).
- **Kennzahlen-Kacheln** der Analyse wählen und ordnen.
- **Profile** (z. B. Arbeit / Privat), Wechsel über Ansicht → Profile.

## Alarme und Hinweise (7.9)
- **Kombinierter Alarm**: zwei Bedingungen, beide gleichzeitig erfüllt.
- **Alarm-Vorlagen** für Depot, Watchlist oder eine Gruppe.
- **Vorwarnzeit** für Quartalszahlen (Standard 1 Tag) und neu Ex-Dividende (Standard aus).
- Alarm zusätzlich **1 Woche** pausieren.
- **Termine als .ics** (Werkzeuge-Menü und Kalenderfenster).
- **Zusammenfassung** (heute / 7 Tage) als Fenster, auf Wunsch täglich oder wöchentlich von selbst. Es wird nichts verschickt. Die 7-Tage-Werte nutzen heutige Stückzahlen und den heutigen Wechselkurs; fehlende Kurse werden angezeigt.

## Depot (8.0)
- **Ziele und Kosten** (Portfolio-Menü): Gebühren und Zinsen je Jahr und Depot; Ziele für Depotwert und Dividenden pro Jahr (Prognose 12 Monate) für das aktive Depot.
- Risiko-Seite: **Sortino** und **historisches Value-at-Risk 95 %**.
- **Watchlist als CSV** exportieren / importieren (Ticker; Gruppen; Zielkurs; Währung; Notiz). Der Import legt vorher ein Backup an und löscht nichts.

## War schon vorhanden
Notizen je Ticker, Pause je Alarm, Dividendenrendite auf den Einstand, erwartete Dividenden je Monat, Zinsen und Gebühren im Cash-Konto, gespeicherte Layouts.

## Hinweise
- Buchungen haben kein Broker-Feld: Gebühren „je Broker“ heißt je Depot.
- Fehlt der Tages-Wechselkurs, rechnet „Ziele und Kosten“ mit dem heutigen und sagt das.
