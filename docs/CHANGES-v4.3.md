# TerminalWidget v4.3 – Alerts and phone push

## New alert types
Pick them in the condition list of the alert panel (Watchlist tab). The number field shows what the value means for each type, and some types fill in a suggested value.

| Condition | Value | Fires when |
|---|---|---|
| `Trailing %` | drop in % (suggested: 8) | the price falls that far below its highest point since the alert was created. The stop moves up with the price and is drawn on the chart. |
| `EK% >=` / `EK% <=` | % vs. average cost | the position is up / down that much (portfolio positions only, in the position currency, so exchange-rate moves don't count) |
| `52W Hoch` / `52W Tief` | allowed distance in % (0 = new high / low) | the price reaches the 52-week high / low |
| `Volumen x` | multiple (suggested: 2) | today's volume so far is that many times the usual volume at the same time of day (hourly bars, regular session) |
| `Depot >=` / `Depot <=` | amount in the display currency | the whole portfolio is worth more / less than that |
| `Depot Tag% >=` / `Depot Tag% <=` | % | the whole portfolio is up / down that much today |

Portfolio alerts show `DEPOT` as their ticker. They only fire once every position has a live quote.

## Alert options
- **Valid until** (new box in the second row): unlimited, today, 1 week, 1 month, 3 months. Expired alerts show as `[EXP]` and are no longer checked. Double-click one to bring it back with no end date.
- **Re-arm** works as before. A trailing stop that re-arms starts again from the current price.
- **History** (the "Verlauf" button above the list): every alert that fired, with the time, value, note and push status. The last 500 are kept in `alert-log.json`, which is included in backups.

## Quiet hours
Settings → Benachrichtigungen → "Ruhezeit von – bis" (e.g. 22:00 – 07:00, can span midnight). During quiet hours alerts are still checked and logged, and the tray bubble still appears, but there is **no sound and no phone push**.

## Phone push
Settings → Benachrichtigungen → **"Handy-Push einrichten ..."**

- **ntfy** (no account needed): install the ntfy app, click "Zufällig" to get a random topic, and subscribe to that topic in the app. The topic works like a password.
- **Telegram:** create a bot with @BotFather and paste its token. Send the bot a message (e.g. `/start`), then click "Chat-ID holen".
- **"Test senden"** shows right away whether the message went through.
- Choose what gets pushed: alerts (on by default) and/or earnings the day before.
- The Telegram token is stored encrypted with Windows (DPAPI), so only your Windows account can read it.
- Limit: at most 10 pushes per minute. Results and errors go to `widget.log`.

## Other
- Version 4.3, help text (H) updated, new glossary entries: Trailing Stop, Relatives Volumen, Gültig bis, Ruhezeit, Handy-Push, Alarm-Verlauf.
- Native Windows toasts were not added: on Windows 10/11 the tray bubble already appears as a regular notification, and WinRT toasts don't work in PowerShell 7.
