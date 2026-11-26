# TerminalWidget 10.4

## Broker je Buchung
- Neues Feld **Broker** beim Erfassen einer Transaktion. Vorbelegt mit dem zuletzt für diesen Ticker verwendeten.
- **CSV-Import**: Broker-Auswahl für die ganze Datei; eine Spalte „Broker“ oder „Depotbank“ wird erkannt und hat Vorrang.
- Sparpläne übernehmen den letzten Broker des Tickers.
- Der CSV-Export der Historie enthält den Broker (neue letzte Spalte).

## Transaktionshistorie
- Filter nach Broker, auch „ohne Broker“.
- **Suche** über Ticker, Notiz, Broker, Art und Datum.
- **Broker zuweisen**: mehrere Zeilen mit Strg oder Umschalt markieren. So lassen sich alte Buchungen nachtragen. Gelöscht wird weiterhin nur einzeln.

## Ziele und Kosten
- Umschalter **je Depot / je Broker**. Je Broker: Orders, Volumen, Ordergebühren, Gebühr je Order und in Prozent des Volumens (nur Käufe und Verkäufe, alle Depots).
