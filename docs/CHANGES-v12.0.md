# TerminalWidget 12.0

## Neu: Gesamtbericht
In der Portfolio-Analyse unter **Export → Gesamtbericht aller Seiten (HTML) ...**: eine einzelne Datei, die in jedem Browser aufgeht und sich drucken oder als PDF speichern lässt.

Enthalten:
- Alle Kennzahlen
- Diagramm mit Depotwert, netto investiertem Geld und Benchmark
- Rendite je Position
- Aufteilung nach Position, Währung, Sektor und Land
- Monatsrenditen, Risiko, Beitrag je Position
- Erhaltene und erwartete Dividenden (soweit vorhanden)
- Hinweis, falls Positionen oder Kursverläufe fehlen

Im Privat-Modus (F9) sind Beträge und die Achsenbeschriftung im Diagramm ausgeblendet. Prozente und der Verlauf der Linien bleiben sichtbar. Prüfe den Bericht, bevor du ihn weitergibst.

## Behoben: Privat-Modus
Diese Beträge blieben bisher sichtbar und werden jetzt ausgeblendet:
- Analyse, Seite „Beitrag“: Anfang, Käufe, Verkäufe, Ende und die Veränderung im Szenario
- Analyse, Seite „Dividenden“: Spalte „Erwartet 12M“ und die Beträge über den Balken

Dividenden **je Aktie** bleiben sichtbar, weil sie öffentliche Kursdaten sind.

## Seit Version 11
- 11.0 mehr Kennzahlen in der Analyse, 11.2 Fenster-Layout und Englisch
- 11.4 Detailfenster je Position (`NVDA POS`)
- 11.6 Sparrechner
- 11.8 Monatsrenditen, dunkle Bildlaufleisten
