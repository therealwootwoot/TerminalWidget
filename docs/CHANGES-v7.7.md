# TerminalWidget 7.7

Enthält die geplanten Schritte 7.5.2 (Fehler), 7.6 (Feeds auswählen) und 7.7 (News lesen).

## Fehler behoben
- Depot-Analyse: Absturz (`Substring`), wenn es nur **eine** Buchung gab.
- Ein Rate-Limit (HTTP 429) eines eigenen Feeds bremst die Kurse nicht mehr; pausiert wird nur dieser Anbieter.
- Kurze Firmennamen (ABB, SAP) werden Meldungen zugeordnet.
- Links, die sich nur im Query unterscheiden, gelten nicht mehr als dieselbe Meldung.
- Fehler je Feed sind sichtbar (Fußzeile, Tooltip, Feed-Verwaltung, HEALTH).

## Quellen
- Feed-Verwaltung: an/aus, Name, Gruppe, Ticker, Intervall, Höchstalter, Hinweise, Test, Adresse finden, OPML.
- Menü "Quellen": ein- und ausblenden, nur eine Quelle, nur eine Gruppe.
- Vorlagen mit `{ticker}` oder `{name}`; eigene Namen je Ticker.
- Alte Feed-Adressen werden einmal übernommen.

## Lesen
- Suche (Strg+F), Merken (S), gelesen/ungelesen (M), Vorschau (V), J/K, O.
- Gemerkte als CSV.
- Ähnliche Schlagzeilen zusammengefasst, Verlauf (Standard 14 Tage, höchstens 600).
- Regeln: nur/ausblenden/hervorheben.
- News-Markierungen im Chart (Rechtsklick, Standard aus).

## Hinweise
- Die Verlauf- und Merkliste liegt in `news.json` (im Backup enthalten).
- Feed-Adressen stehen in Einstellungs-Export und OPML-Datei, nicht in DIAG.
