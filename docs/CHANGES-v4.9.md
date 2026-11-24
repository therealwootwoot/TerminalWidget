# TerminalWidget v4.9 – News tab and look and feel

## News tab (F4)
- **One feed for the depot and the watchlist**: a new tab next to Watch & Alarm (F4, `N` without a ticker, or `NEWS`). Up to 40 tickers are asked; the same article found for several tickers shows once, newest first. Index, FX and futures tickers are left out.
- **Filters**: All / Depot / Watchlist / one ticker in the drop-down, or `NEWS DEPOT`, `NEWS WATCH`, `NEWS NVDA`, `NEWS ALL`. `NVDA N` still opens the single-ticker news window.
- **Unread**: new items are bold. The tab shows the number of items that came in since you last looked (e.g. "News ● 5"). "Alle gelesen" clears the bold.
- **Why is it moving?** When a ticker of an item moves at least 3 % today, the ticker cell shows the change in the up/down colour (Settings → Nachrichten, 0 = off).
- Double-click or Enter opens the article. Click the ticker cell to make it the active ticker. Hover shows the full headline, source, time and tickers.
- **Terminal layout**: the News tab replaces the lists below the chart while it is selected.
- Refreshes every 15 minutes in the background (setting 5–240), half as often while every market is closed. ↻ reloads now.

## Look and feel
- **Same window frame everywhere**: every dialog now gets the dark title bar plus the theme's caption and border colour (before, only the main window did).
- **Rounded corners** on Windows 11, also on the borderless Ticker strip and the command palette (Settings → Schrift und Rahmen; the fullscreen chart stays square).
- **Font for numbers**: Consolas, Cascadia Mono, Cascadia Code or Lucida Console (only installed fonts are offered). **Font size** 90 / 100 / 110 / 120 %. Both apply after a restart; the widget offers to restart.
- **Numbers right-aligned** in the watchlist and portfolio (headers too), so digits stay in place when prices change. Can be switched off.

## Other
- The nav bar's command button gets narrower in small windows before the status text disappears.
- Tests: 12 new Pester tests (feed merging, filters, ages, unread count, movers, Terminal geometry, fonts, corners); the UI smoke test also covers the News tab, its filters, the unread count and the Terminal layout with News.
