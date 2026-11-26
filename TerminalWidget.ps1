# ==============================================================================
# TerminalWidget.ps1 - Terminal Widget v4.0 (formerly "Financial Terminal Widget")
# ------------------------------------------------------------------------------
# Files (keep together in one folder):
#   TerminalWidget.ps1             this script (UI, data, events)
#   TerminalWidget.Core.ps1        pure logic, dot-sourced at start
#   TerminalWidget.Core.Tests.ps1  Pester 5 tests:  Invoke-Pester .\TerminalWidget.Core.Tests.ps1
#   TerminalWidget_Start.bat       launcher (hidden window)
# Platform: Windows, Windows PowerShell 5.1 or PowerShell 7 (WinForms).
# Encoding: UTF-8 WITH BOM (Windows PowerShell 5.1 reads BOM-less files as ANSI
# and would garble the umlauts). Keep the BOM when editing.
# ------------------------------------------------------------------------------
# v4.0.1 fix:
#  - Windows PowerShell 5.1: no more "FindSystemTimeZoneById ... America/New_York
#    nicht gefunden" errors in widget.log at every start (the Windows time zone
#    id is tried first; expected lookup failures are not logged)
#
# v4.0 changes:
#  Rename
#  - Files, window title, data folder (%LOCALAPPDATA%\TerminalWidget), mutex
#    and autostart shortcut renamed. On the first start the data is COPIED
#    from NvidiaWidgetV2 (the old folder is left untouched for a rollback),
#    then backed up before the schema-4 migration. A running v3.x instance is
#    detected and can be stopped; an old autostart shortcut is replaced.
#  Layouts
#  - Four presets, layout button in the header / tray menu / L key:
#    Ticker (borderless strip: price + mini chart), Compact (bar + tape),
#    Standard (tabs), Terminal (chart on top, watchlist and portfolio at the
#    same time below; side by side when wide enough)
#  - Terminal theme (amber on black), window opacity, Terminal panel options
#  Hover explanations
#  - Glossary of ~40 terms; tooltips in three levels (off / short / detailed)
#    with adjustable delay; explanations on grid column headers and on the
#    chart legend (SMA, VWAP, BB, RSI, range badge, levels); glossary window (G)
#  Quick wins
#  - Starts with the last known quotes (quote_cache.json, shown grey until
#    the first refresh) instead of an empty window
#  - Refresh right after the PC wakes up (timer gap detection)
#  - Status: amber when older than 2 intervals, red when offline / very old
#  - Real umlauts in the UI
#  - Yearly report: realized gains/losses and dividends in a base currency,
#    converted at the FX rate of each booking date (history dialog)
#  - Fix: the v3.0.1 Core file contained PowerShell-7-only code (??) and did
#    not load in Windows PowerShell 5.1 (the launcher's host); removed
#
# v3.0.1 fixes:
#  - Settings (gear button) crashed with "Das Argument kann nicht an den
#    Parameter Path gebunden werden ..." where Windows reports no Startup
#    folder (seen on Windows Server 2022): autostart path now has a fallback
#  - Errors in any button/event handler are logged + shown in the status line
#    instead of the WinForms "Unbehandelte Ausnahme" dialog
#
# v3.0 changes (major version: reliability + data integrity):
#  Fixes
#  - Alarm panel: the "Bedingung" dropdown was empty on every fresh start
#    (list was defined after the combo box was filled) -> alerts could only
#    be created via the chart context menu. Lists now come from Core functions.
#  - Positions in currencies other than EUR/USD/CHF (e.g. GBP booked via the
#    transaction dialog) were silently turned into EUR on load. Any ISO code
#    is kept now; a one-time check reports positions already affected.
#  - Portfolio editor no longer overwrites a GBP/other position currency with
#    whatever the currency box happened to show.
#  - Symbol lookups no longer pump DoEvents (re-entrant clicks while waiting);
#    typed tickers are resolved in the background, known ones instantly.
#  - Alarm sound no longer blocks the UI (system sound instead of Console.Beep)
#  New
#  - GBP as display currency (header, W key, settings)
#  - Transaction history: "Position neu berechnen" (replay of all buys/sells,
#    average cost, preview before applying); offered after deleting a booking
#  - Settings: "Backup jetzt" (copy of all data files) and "Log oeffnen"
#  - Automatic backup of the data files before the v3 schema migration
#  - Empty states: hints in the alarm list and the empty portfolio
#  - Alarm value field explains its unit per condition (tooltip)
#  Maintenance
#  - Version in one place ($script:AppVersion); config carries SchemaVersion
#  - CSV exports escape text fields (separator, quotes, formula injection)
#  - Grids of hidden tabs are no longer rebuilt on every refresh
#  - More pure logic + Pester tests in NvidiaWidget.Core.ps1
#
# v2.9 changes:
#  Chart
#  - Cost basis (EK) of the position and price alerts drawn as levels; levels
#    outside the visible range get an edge marker with an arrow
#  - Right-click in the price area: "Alarm: >= / <= <price under the mouse>"
#  - Ctrl + wheel zooms around the mouse, Shift + wheel pans, Z resets
#  - Drag with the left mouse button measures change, %, bars and duration
#  - Comparison ticker (X / context menu) as a %-performance line, HUD shows it
#  Alerts
#  - New conditions: RSI >= / <= (1h), > SMA / < SMA (price vs. fast SMA, 1h)
#  - Optional re-arm (15m / 1h / 4h / 1 day) once the condition is false again
#  - Note per alert (shown in list + notification)
#  Market hours
#  - Rule-based holiday calendars (incl. Easter) for NYSE/Nasdaq, Xetra, SIX,
#    LSE and Wiener Boerse: status "Feiertag (...)", correct next open,
#    upcoming holidays in the tooltip
#  Watchlist / portfolio
#  - Header click sorts (3rd click = own order), sort glyphs
#  - Watchlist order by drag & drop or Alt+Up/Down
#  - Transactions: buy / sell / dividend incl. fees, realized P/L, history
#    window with filter, delete and CSV export; realized P/L in the summary
#  Robustness / maintenance
#  - Automatic fallback query1 <-> query2.finance.yahoo.com (sticky)
#  - Pure logic moved to NvidiaWidget.Core.ps1 + Pester tests
#  - Settings: "Mit Windows starten" (shortcut in the Startup folder)
#
# v2.8 changes:
#  Performance
#  - Data refresh runs in a background RunspacePool (HTTP + JSON parsing off
#    the UI thread): no more DoEvents re-entrancy, window stays responsive
#  - Live ticker/watchlist search is asynchronous as well
#  - Chart is rendered once into a cached bitmap; crosshair/HUD are drawn as a
#    light overlay -> smooth mouse tracking, no full re-render per mouse move
#  - Chart re-render only when its content changed (signature check)
#  - Intraday merge via SortedDictionary (no Sort-Object), session repair and
#    currency conversion in ONE pass over the last 2 days only, FX factor
#    computed once per series instead of 4 calls per bar
#  Fixes
#  - Status bar shows the FX pairs relevant for the display currency
#    (EUR/USD, USD/CHF, GBP/... incl. portfolio currencies), all in tooltip
#  - Maximized state is remembered (start + restore from tray)
#  - Window is pulled back on screen after size restore / monitor change
#  - HUD width measured from its text (was fixed, long values were cut off)
#  - DST-aware session math via exchange time zone (pre/post classification
#    of cached bars and "opens at" countdown were 1 h off around DST switches)
#  - Daily bars no longer classified as pre-market (whole chart was shaded
#    for exchanges that stamp daily bars at midnight)
#  New
#  - Crosshair with price tag (right axis), time tag (bottom axis), RSI value
#    in the RSI pane, close marker; HUD shows bar change % and volume
#  - Settings dialog (gear button / key S): intervals, indicator periods,
#    RSI levels, theme/accent, notifications, compact tape, data folder
#  - Watchlist: 5D sparkline column
#  - Compact mode: scrolling ticker tape (click = open, hover = pause)
#
# v2.7 changes:
#  - Window is resizable / maximizable (size is remembered), layout follows
#  - Chart fullscreen window: F11, double-click on chart, "Vollbild" button
#    or context menu. Esc / F11 / double-click closes. Keys 1-6 = timeframe
#  - Fix: File.Replace got "" instead of null as backup path (PowerShell turns
#    $null into "" for string args) -> "Der Pfad hat ein ungueltiges Format"
#  - Status bar shows "Stand" (time of last successful data refresh) and
#    turns amber when data is stale; refreshed every second
#  - Chart toggle buttons sized to their text (labels were cut off)
#  - Bar sessions are re-classified after merging with the cache (fixes
#    double "PRE" labels / dark stripes), implausible ext-hours wicks clipped
#  - Range badge says what the % refers to (vs. previous close / period)
#  - Watchlist & portfolio columns fill the grid width (BTC price was cut off)
#
# v2.6 changes:
#  - Market hours: live status (Offen / Pre / Post / Zu / 24/7) with countdown,
#    trading hours in local time as tooltip, optional "market open" balloon
#  - Pre-market & after-hours quotes (header + "Ext %" watchlist column)
#  - 1D chart can include extended hours (shaded), toggle "Ext (E)"
#  - VWAP / day change / RSI only use regular-session bars
#  - Header: absolute day change, ext quote line, draggable labels,
#    double-click price = copy; tray icon shows up/down colour
#  - Portfolio: day P/L in summary; alerts on day change % (Tag% >= / <=)
#  - Ctrl+F = ticker search, H = shortcut help, window position saved on move
#  - Fixes: ISE no longer killed by the single-instance guard, cached bars no
#    longer modified by live ticks, theme switch in compact mode, cache pruning
#
# v2.5 changes:
#  - Day change now uses the real previous session close (was 5-day change)
#  - Refresh requests during a running refresh are queued instead of dropped
#  - Grids keep selection/scroll on refresh; portfolio editor no longer reset
#  - Live FX for every currency in use (not just USD/CHF/GBP), warns if missing
#  - VWAP resets per trading session (5D)
#  - Ticker dropdown no longer pops open on startup / window activation
#  - Atomic JSON saves, URL-encoded symbols, locale-tolerant number input
#  - Confirmations before deleting, rate-limit (HTTP 429) backoff, log file
#  - Watchlist-only tickers refreshed less often to reduce API load
# ==============================================================================
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# v5.5: start time is measured from here (HEALTH, log)
$script:StartWatch = [System.Diagnostics.Stopwatch]::StartNew()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Web

try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32WidgetHelperV26 {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);

    [DllImport("user32.dll")]
    public static extern bool ReleaseCapture();

    [DllImport("user32.dll", EntryPoint = "SendMessageW", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendCue(IntPtr hWnd, int msg, IntPtr wParam, string lParam);

    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
"@ -ErrorAction Stop
    # V7.0: per-monitor DPI awareness (v2, Windows 10 1703+); older systems keep the system-wide awareness
    $pmOk = $false
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class TwDpiV7 {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
}
"@ -ErrorAction Stop
        $pmOk = [bool][TwDpiV7]::SetProcessDpiAwarenessContext([System.IntPtr]([int]-4))
    } catch { $pmOk = $false }
    if (-not $pmOk) { [void][Win32WidgetHelperV26]::SetProcessDPIAware() }
} catch {
    # Already loaded in current PowerShell session
}

# V7.0: one renderer for all context / tray menus (rounded hover, token colours,
# right-aligned shortcuts, separators from the border colour). If this fails to
# compile, the menus keep the system look.
try {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class TwMenuRendererV7 : ToolStripProfessionalRenderer {
    public static Color BackC = Color.FromArgb(32, 32, 36);
    public static Color HoverC = Color.FromArgb(54, 54, 61);
    public static Color TextC = Color.FromArgb(244, 244, 245);
    public static Color MutedC = Color.FromArgb(161, 161, 170);
    public static Color BorderC = Color.FromArgb(60, 60, 68);
    public static Color AccentC = Color.FromArgb(56, 189, 248);
    public static int Radius = 4;

    public TwMenuRendererV7() : base() { this.RoundedEdges = false; }

    static GraphicsPath RoundRect(Rectangle r, int radius) {
        GraphicsPath p = new GraphicsPath();
        int d = Math.Max(1, Math.Min(radius * 2, Math.Min(r.Width, r.Height)));
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
        using (SolidBrush b = new SolidBrush(BackC)) { e.Graphics.FillRectangle(b, e.AffectedBounds); }
    }
    protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) {
        using (Pen p = new Pen(BorderC)) { e.Graphics.DrawRectangle(p, 0, 0, e.ToolStrip.Width - 1, e.ToolStrip.Height - 1); }
    }
    protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) { }
    protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
        ToolStripItem item = e.Item;
        if (!item.Enabled || !(item.Selected || item.Pressed)) { return; }
        Rectangle r = new Rectangle(4, 1, item.Width - 8, item.Height - 2);
        SmoothingMode old = e.Graphics.SmoothingMode;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (GraphicsPath gp = RoundRect(r, Radius)) using (SolidBrush b = new SolidBrush(HoverC)) { e.Graphics.FillPath(b, gp); }
        e.Graphics.SmoothingMode = old;
    }
    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
        e.TextColor = e.Item.Enabled ? TextC : MutedC;
        base.OnRenderItemText(e);
    }
    protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
        int y = e.Item.Height / 2;
        using (Pen p = new Pen(BorderC)) { e.Graphics.DrawLine(p, 8, y, e.Item.Width - 8, y); }
    }
    protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) {
        e.ArrowColor = MutedC;
        base.OnRenderArrow(e);
    }
    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e) {
        Rectangle r = e.ImageRectangle;
        SmoothingMode old = e.Graphics.SmoothingMode;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        int cx = r.X + r.Width / 2;
        int cy = r.Y + r.Height / 2;
        using (Pen p = new Pen(AccentC, 2f)) {
            e.Graphics.DrawLines(p, new Point[] { new Point(cx - 4, cy), new Point(cx - 1, cy + 3), new Point(cx + 4, cy - 3) });
        }
        e.Graphics.SmoothingMode = old;
    }
}
"@ -ErrorAction Stop
} catch {
    # already loaded in this PowerShell session, or no compiler: system look stays
}

# V7.0: toggle switch (a real CheckBox, so .Checked / CheckedChanged keep working)
try {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class TwToggleV7 : CheckBox {
    public static Color OnC = Color.FromArgb(56, 189, 248);
    public static Color OffC = Color.FromArgb(60, 60, 68);
    public static Color KnobC = Color.FromArgb(244, 244, 245);
    public static Color TextC = Color.FromArgb(244, 244, 245);
    public static Color DisabledC = Color.FromArgb(120, 120, 128);

    public TwToggleV7() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Cursor = Cursors.Hand;
    }
    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }

    static GraphicsPath Pill(Rectangle r) {
        GraphicsPath p = new GraphicsPath();
        int d = r.Height;
        p.AddArc(r.X, r.Y, d, d, 90, 180);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 180);
        p.CloseFigure();
        return p;
    }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        Color back = (Parent != null) ? Parent.BackColor : BackColor;
        g.Clear(back);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int h = Math.Max(14, Math.Min(Height - 4, 20));
        int w = (int)(h * 1.8);
        Rectangle track = new Rectangle(2, (Height - h) / 2, w, h);
        Color c = Checked ? OnC : OffC;
        if (!Enabled) { c = Color.FromArgb(90, c); }
        using (GraphicsPath gp = Pill(track)) using (SolidBrush b = new SolidBrush(c)) { g.FillPath(b, gp); }
        int kd = h - 6;
        int kx = Checked ? (track.Right - kd - 3) : (track.X + 3);
        using (SolidBrush kb = new SolidBrush(KnobC)) { g.FillEllipse(kb, kx, track.Y + 3, kd, kd); }
        if (Focused && ShowFocusCues) {
            Rectangle fr = new Rectangle(track.X - 2, track.Y - 2, track.Width + 4, track.Height + 4);
            using (GraphicsPath fp = Pill(fr)) using (Pen pen = new Pen(OnC, 2f)) { g.DrawPath(pen, fp); }
        }
        Rectangle tr = new Rectangle(w + 12, 0, Math.Max(1, Width - w - 14), Height);
        TextRenderer.DrawText(g, Text, Font, tr, Enabled ? TextC : DisabledC, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }
}
"@ -ErrorAction Stop
} catch {
    # already loaded, or no compiler: normal check boxes stay
}

# V7.0: drop-down with styled items (rounded hover, check mark on the selected item); the combo box API stays the same
try {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class TwComboV7 : ComboBox {
    public static Color ListC = Color.FromArgb(32, 32, 36);
    public static Color HoverC = Color.FromArgb(54, 54, 61);
    public static Color TextC = Color.FromArgb(244, 244, 245);
    public static Color AccentC = Color.FromArgb(56, 189, 248);

    public static Color BorderC = Color.FromArgb(70, 70, 80);
    public static bool RoundedClosed = true;
    bool hotC = false;

    public TwComboV7() {
        DrawMode = DrawMode.OwnerDrawFixed;
    }
    protected override void OnMouseEnter(EventArgs e) { hotC = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hotC = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void WndProc(ref Message m) {
        base.WndProc(ref m);
        if (m.Msg == 0xF && RoundedClosed && DropDownStyle == ComboBoxStyle.DropDownList && Width > 20 && Height > 12) {
            try { PaintClosed(); } catch (Exception) { }
        }
    }
    void PaintClosed() {
        using (Graphics g = Graphics.FromHwnd(Handle)) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Color pb = (Parent != null) ? Parent.BackColor : BackColor;
            using (SolidBrush pbr = new SolidBrush(pb)) { g.FillRectangle(pbr, 0, 0, Width, Height); }
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            int d = 8;
            using (GraphicsPath gp = new GraphicsPath()) {
                gp.AddArc(r.X, r.Y, d, d, 180, 90);
                gp.AddArc(r.Right - d, r.Y, d, d, 270, 90);
                gp.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
                gp.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
                gp.CloseFigure();
                using (SolidBrush bb = new SolidBrush(BackColor)) { g.FillPath(bb, gp); }
                using (Pen bp = new Pen((Focused || hotC || DroppedDown) ? AccentC : BorderC, 1f)) { g.DrawPath(bp, gp); }
            }
            Color fore = Enabled ? ForeColor : Color.FromArgb(120, ForeColor);
            string text = (SelectedItem != null) ? GetItemText(SelectedItem) : "";
            Rectangle tr = new Rectangle(8, 0, Math.Max(1, Width - 30), Height);
            TextRenderer.DrawText(g, text, Font, tr, fore, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            int cx = Width - 14; int cy = Height / 2;
            using (Pen cp = new Pen(fore, 1.6f)) { g.DrawLines(cp, new Point[] { new Point(cx - 3, cy - 1), new Point(cx, cy + 2), new Point(cx + 3, cy - 1) }); }
        }
    }
    protected override void OnDrawItem(DrawItemEventArgs e) {
        Graphics g = e.Graphics;
        bool edit = (e.State & DrawItemState.ComboBoxEdit) != 0;
        bool sel = !edit && (e.State & DrawItemState.Selected) != 0;
        Color back = edit ? BackColor : ListC;
        using (SolidBrush bb = new SolidBrush(back)) { g.FillRectangle(bb, e.Bounds); }
        if (e.Index < 0) { return; }
        if (sel) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(e.Bounds.X + 3, e.Bounds.Y + 1, e.Bounds.Width - 6, e.Bounds.Height - 2);
            int d = 8;
            using (GraphicsPath gp = new GraphicsPath()) {
                gp.AddArc(r.X, r.Y, d, d, 180, 90);
                gp.AddArc(r.Right - d, r.Y, d, d, 270, 90);
                gp.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
                gp.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
                gp.CloseFigure();
                using (SolidBrush hb = new SolidBrush(HoverC)) { g.FillPath(hb, gp); }
            }
        }
        string text = GetItemText(Items[e.Index]);
        Color fore = edit ? ForeColor : TextC;
        Rectangle tr = new Rectangle(e.Bounds.X + 6, e.Bounds.Y, e.Bounds.Width - (edit ? 8 : 26), e.Bounds.Height);
        TextRenderer.DrawText(g, text, Font, tr, fore, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        if (!edit && e.Index == SelectedIndex) {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int cx = e.Bounds.Right - 14;
            int cy = e.Bounds.Y + e.Bounds.Height / 2;
            using (Pen p = new Pen(AccentC, 2f)) {
                g.DrawLines(p, new Point[] { new Point(cx - 4, cy), new Point(cx - 1, cy + 3), new Point(cx + 4, cy - 3) });
            }
        }
    }
}
"@ -ErrorAction Stop
} catch {
    # already loaded, or no compiler: normal combo boxes stay
}

# V7.1: segmented control (a few short choices side by side) and slider
try {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public class TwSegmentV7 : Control {
    public static Color AccentC = Color.FromArgb(56, 189, 248);
    public static Color TrackC = Color.FromArgb(40, 40, 46);
    public static Color TextC = Color.FromArgb(244, 244, 245);
    public static Color MutedC = Color.FromArgb(160, 160, 170);
    public static Color OnTextC = Color.FromArgb(10, 10, 12);
    string[] items = new string[0];
    int sel = 0;
    int hot = -1;
    public event EventHandler SelectedIndexChanged;

    public TwSegmentV7() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        TabStop = true;
        Cursor = Cursors.Hand;
    }
    public string[] Items { get { return items; } set { items = value ?? new string[0]; if (sel >= items.Length) { sel = 0; } Invalidate(); } }
    public int SelectedIndex {
        get { return sel; }
        set {
            if (value < 0 || value >= items.Length || value == sel) { return; }
            sel = value; Invalidate();
            if (SelectedIndexChanged != null) { SelectedIndexChanged(this, EventArgs.Empty); }
        }
    }
    int[] Edges() {
        int n = items.Length;
        int[] e = new int[n + 1];
        if (n == 0) { return e; }
        int[] w = new int[n];
        int sum = 0;
        for (int i = 0; i < n; i++) { w[i] = TextRenderer.MeasureText(items[i], Font).Width + 24; sum += w[i]; }
        int avail = Math.Max(1, Width - 4);
        int x = 2;
        e[0] = x;
        for (int i = 0; i < n; i++) {
            x += (i == n - 1) ? (avail - (x - 2)) : (int)((long)w[i] * avail / sum);
            e[i + 1] = x;
        }
        e[n] = 2 + avail;
        return e;
    }
    int HitTest(int px) {
        int[] e = Edges();
        for (int i = 0; i < items.Length; i++) { if (px >= e[i] && px < e[i + 1]) { return i; } }
        return -1;
    }
    static GraphicsPath Round(Rectangle r, int d) {
        GraphicsPath p = new GraphicsPath();
        if (d < 2) { p.AddRectangle(r); return p; }
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
    protected override bool IsInputKey(Keys k) { return k == Keys.Left || k == Keys.Right || base.IsInputKey(k); }
    protected override void OnKeyDown(KeyEventArgs e) {
        if (e.KeyCode == Keys.Left) { SelectedIndex = Math.Max(0, sel - 1); e.Handled = true; }
        else if (e.KeyCode == Keys.Right) { SelectedIndex = Math.Min(items.Length - 1, sel + 1); e.Handled = true; }
        base.OnKeyDown(e);
    }
    protected override void OnMouseDown(MouseEventArgs e) { Focus(); int i = HitTest(e.X); if (i >= 0) { SelectedIndex = i; } base.OnMouseDown(e); }
    protected override void OnMouseMove(MouseEventArgs e) { int i = HitTest(e.X); if (i != hot) { hot = i; Invalidate(); } base.OnMouseMove(e); }
    protected override void OnMouseLeave(EventArgs e) { hot = -1; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.Clear((Parent != null) ? Parent.BackColor : BackColor);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle track = new Rectangle(0, 0, Width - 1, Height - 1);
        int rad = Math.Min(Height - 1, 12);
        using (GraphicsPath gp = Round(track, rad)) using (SolidBrush b = new SolidBrush(TrackC)) { g.FillPath(b, gp); }
        int[] ed = Edges();
        for (int i = 0; i < items.Length; i++) {
            Rectangle r = new Rectangle(ed[i] + 1, 3, Math.Max(1, ed[i + 1] - ed[i] - 2), Height - 7);
            bool on = (i == sel);
            if (on) {
                using (GraphicsPath sp = Round(r, Math.Max(2, rad - 4))) using (SolidBrush ab = new SolidBrush(Enabled ? AccentC : Color.FromArgb(90, AccentC))) { g.FillPath(ab, sp); }
            }
            Color fc = on ? OnTextC : ((i == hot) ? TextC : MutedC);
            TextRenderer.DrawText(g, items[i], Font, r, fc, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);
        }
        if (Focused && ShowFocusCues) {
            using (GraphicsPath fp = Round(track, rad)) using (Pen pen = new Pen(AccentC, 2f)) { g.DrawPath(pen, fp); }
        }
    }
}

public class TwSliderV7 : Control {
    public static Color AccentC = Color.FromArgb(56, 189, 248);
    public static Color TrackC = Color.FromArgb(60, 60, 68);
    public static Color KnobC = Color.FromArgb(244, 244, 245);
    int min = 0, max = 100, val = 0, step = 1;
    bool drag = false;
    public event EventHandler ValueChanged;

    public TwSliderV7() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        TabStop = true;
        Cursor = Cursors.Hand;
    }
    public int Minimum { get { return min; } set { min = value; if (val < min) { val = min; } Invalidate(); } }
    public int Maximum { get { return max; } set { max = Math.Max(value, min + 1); if (val > max) { val = max; } Invalidate(); } }
    public int Step { get { return step; } set { step = Math.Max(1, value); } }
    public int Value {
        get { return val; }
        set {
            int v = Math.Max(min, Math.Min(max, value));
            if (v == val) { return; }
            val = v; Invalidate();
            if (ValueChanged != null) { ValueChanged(this, EventArgs.Empty); }
        }
    }
    int Snap(int v) { int s = step; return min + (int)Math.Round((double)(v - min) / s) * s; }
    int FromX(int x) {
        int pad = 9;
        double f = (double)(x - pad) / Math.Max(1, Width - 2 * pad);
        f = Math.Max(0.0, Math.Min(1.0, f));
        return Snap((int)Math.Round(min + f * (max - min)));
    }
    protected override bool IsInputKey(Keys k) { return k == Keys.Left || k == Keys.Right || k == Keys.Up || k == Keys.Down || base.IsInputKey(k); }
    protected override void OnKeyDown(KeyEventArgs e) {
        if (e.KeyCode == Keys.Left || e.KeyCode == Keys.Down) { Value = val - step; e.Handled = true; }
        else if (e.KeyCode == Keys.Right || e.KeyCode == Keys.Up) { Value = val + step; e.Handled = true; }
        else if (e.KeyCode == Keys.Home) { Value = min; e.Handled = true; }
        else if (e.KeyCode == Keys.End) { Value = max; e.Handled = true; }
        else if (e.KeyCode == Keys.PageUp) { Value = val + step * 5; e.Handled = true; }
        else if (e.KeyCode == Keys.PageDown) { Value = val - step * 5; e.Handled = true; }
        base.OnKeyDown(e);
    }
    protected override void OnMouseDown(MouseEventArgs e) { Focus(); drag = true; Capture = true; Value = FromX(e.X); base.OnMouseDown(e); }
    protected override void OnMouseMove(MouseEventArgs e) { if (drag) { Value = FromX(e.X); } base.OnMouseMove(e); }
    protected override void OnMouseUp(MouseEventArgs e) { drag = false; Capture = false; base.OnMouseUp(e); }
    protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
    protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.Clear((Parent != null) ? Parent.BackColor : BackColor);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int pad = 9;
        int cy = Height / 2;
        double f = (double)(val - min) / Math.Max(1, max - min);
        int kx = pad + (int)Math.Round(f * (Width - 2 * pad));
        Color ac = Enabled ? AccentC : Color.FromArgb(90, AccentC);
        using (Pen tp = new Pen(TrackC, 4f)) { tp.StartCap = LineCap.Round; tp.EndCap = LineCap.Round; g.DrawLine(tp, pad, cy, Width - pad, cy); }
        using (Pen ap = new Pen(ac, 4f)) { ap.StartCap = LineCap.Round; ap.EndCap = LineCap.Round; g.DrawLine(ap, pad, cy, kx, cy); }
        using (SolidBrush kb = new SolidBrush(KnobC)) { g.FillEllipse(kb, kx - 7, cy - 7, 14, 14); }
        if (Focused && ShowFocusCues) { using (Pen fp = new Pen(AccentC, 2f)) { g.DrawEllipse(fp, kx - 9, cy - 9, 18, 18); } }
    }
}
"@ -ErrorAction Stop
} catch {
    # already loaded, or no compiler: combo boxes and number fields stay
}

[System.Windows.Forms.Application]::EnableVisualStyles()

# v3.0.1: an exception in any event handler (button click etc.) used to pop up
# the WinForms "Unbehandelte Ausnahme" dialog. Now it is logged and shown in
# the status line; the widget keeps running. Must be set before the first window.
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        try {
            $ex = $e.Exception
            $where = if ($ex -is [System.Management.Automation.IContainsErrorRecord] -and $ex.ErrorRecord.InvocationInfo) { " @ line $($ex.ErrorRecord.InvocationInfo.ScriptLineNumber)" } else { "" }
            Write-WidgetLog ("UI handler error{0}: {1}" -f $where, $ex.Message) "ERROR"
            Set-TransientStatus ("Fehler: {0} (Details im Log)" -f $ex.Message) 8
        } catch { }
    })
} catch { }

# Pure logic (indicators, parsing, market hours, holidays) lives in a separate
# file so it can be unit-tested with Pester without starting the UI (v2.9)
$script:ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
$script:MainScriptPath = $PSCommandPath   # V7.0: parts in ui\ must not use $PSCommandPath (it would name the part)
$script:CorePath = Join-Path $script:ScriptDir "TerminalWidget.Core.ps1"
if (-not (Test-Path $script:CorePath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "TerminalWidget.Core.ps1 fehlt.`r`n`r`nDie Datei muss im selben Ordner liegen wie das Widget-Skript:`r`n$($script:ScriptDir)",
        "Terminal Widget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
try {
    . $script:CorePath
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "TerminalWidget.Core.ps1 konnte nicht geladen werden:`r`n$($_.Exception.Message)`r`n`r`nBitte die Dateien des Widgets erneut kopieren (Core und Widget müssen dieselbe Version haben).",
        "Terminal Widget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
if (-not (Get-Command Get-LayoutNames -ErrorAction SilentlyContinue)) {
    [System.Windows.Forms.MessageBox]::Show(
        "TerminalWidget.Core.ps1 ist veraltet (v4.0 erwartet).`r`n`r`nBitte Core- und Widget-Datei aus derselben Version verwenden.",
        "Terminal Widget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}

$script:AppVersion    = "10.0"
$script:SchemaVersion = 5
$script:AppTitle      = "Terminal Widget v$($script:AppVersion)"

# ==============================================================================
# Part 1: Storage Paths, Atomic Persistence & Config Migration
# ==============================================================================
# v4.5: portable.txt next to the script = data in <program folder>\data
$script:IsPortable    = Test-Path (Join-Path $script:ScriptDir "portable.txt")
$script:DataDir       = if ($script:IsPortable) { Join-Path $script:ScriptDir "data" } else { Join-Path $env:LOCALAPPDATA "TerminalWidget" }
# v4.7: the CI smoke test runs on its own data folder
if ($env:TW_SMOKE_TEST -and $env:TW_SMOKE_DIR) { $script:DataDir = $env:TW_SMOKE_DIR }
$script:OldDataDir    = Join-Path $env:LOCALAPPDATA "NvidiaWidgetV2"   # v2.x / v3.x
$script:ConfigPath    = Join-Path $script:DataDir "config.json"
$script:PortfolioPath = Join-Path $script:DataDir "portfolio.json"
$script:AlertsPath    = Join-Path $script:DataDir "alerts.json"
$script:CachePath     = Join-Path $script:DataDir "intraday_cache.json"
$script:QuoteCachePath = Join-Path $script:DataDir "quote_cache.json"

$script:LogPath       = Join-Path $script:DataDir "widget.log"

if (-not (Test-Path $script:DataDir)) {
    New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
}

# Lightweight rolling log (window runs hidden, so errors would otherwise be invisible)
function Write-WidgetLog {
    param([string]$Message, [string]$Level = "INFO")
    try {
        if ((Test-Path $script:LogPath) -and ((Get-Item $script:LogPath).Length -gt 1MB)) {
            Move-Item -Path $script:LogPath -Destination "$($script:LogPath).old" -Force
        }
        # V6: API keys in URLs never reach the log (or a diagnostics ZIP)
        $Message = [string]$Message -replace '(?i)\b(apikey|token|api_key)=[^&\s"'']+', '$1=***'
        $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
        [System.IO.File]::AppendAllText($script:LogPath, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch { }
}

# v4.0: data folder moved. Copy (never move) the v3 data on the first start, so
# the old version keeps working on its own folder.
$script:MigratedFromOld = $false
try {
    $migAction = Get-DataMigrationAction -NewHasConfig (Test-Path $script:ConfigPath) -OldHasConfig (Test-Path (Join-Path $script:OldDataDir "config.json"))
    if ($migAction -eq "CopyFromOld") {
        foreach ($fn in (Get-DataFileNames)) {
            $src = Join-Path $script:OldDataDir $fn
            if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $script:DataDir $fn) -Force }
        }
        $script:MigratedFromOld = $true
        Write-WidgetLog "Data copied from $($script:OldDataDir) (old folder left unchanged)"
    }
} catch {
    Write-WidgetLog "Copying the v3 data failed: $($_.Exception.Message)" "ERROR"
}

# Single-Instance Mutex Guard. v4.0 has its own mutex; a running v2.x/v3.x
# (old mutex name) is detected as well, it works on the old data folder.
Write-WidgetLog ("Script start (PID {0}, PowerShell {1}, {2})" -f $PID, $PSVersionTable.PSVersion, $PSCommandPath)
$script:MutexCreated = $false
$script:AppMutex = New-Object System.Threading.Mutex($true, "Local\TerminalWidget_v4_Mutex", [ref]$script:MutexCreated)
$script:OldInstanceRunning = $false
try {
    $oldMx = $null
    if ([System.Threading.Mutex]::TryOpenExisting("Local\NvidiaFinancialWidgetV2_Mutex", [ref]$oldMx)) {
        $script:OldInstanceRunning = $true
        $oldMx.Dispose()
    }
} catch { }
if (-not $script:MutexCreated -or $script:OldInstanceRunning) {
    Write-WidgetLog ("Another instance is running (v4: {0}, old version: {1})" -f (-not $script:MutexCreated), $script:OldInstanceRunning) "WARN"
    # The window runs hidden, so show boxes on top of everything
    $mbTop = [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly
    $others = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe' OR Name='powershell_ise.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $PID -and ($_.CommandLine -like '*TerminalWidget.ps1*' -or $_.CommandLine -like '*nvidia_widget*') })
    # (powershell_ise.exe is NOT matched blindly any more: killing an unrelated
    #  ISE window would lose unsaved scripts)
    Write-WidgetLog ("Candidate instances: " + (($others | ForEach-Object { "$($_.Name)#$($_.ProcessId)" }) -join ", "))

    if ($others.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Das Widget ist noch aktiv, aber kein Widget-Prozess wurde gefunden.`r`n`r`nLäuft es evtl. in VS Code, der PowerShell ISE oder einem offenen PowerShell-Fenster? Dieses Fenster schließen - oder Windows ab- und wieder anmelden.",
            "Widget aktiv",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1, $mbTop
        ) | Out-Null
        exit
    }

    $who = if ($script:OldInstanceRunning) { "Die alte Version (Financial Widget v3) läuft noch." } else { "Das Terminal Widget läuft bereits (evtl. versteckt im System Tray)." }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "$who`r`n`r`n[Ja] = Laufende Instanz beenden und diese starten`r`n[Nein] = Abbrechen",
        "Widget aktiv",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button1, $mbTop
    )
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { exit }

    foreach ($o in $others) {
        try { Stop-Process -Id $o.ProcessId -Force -ErrorAction Stop; Write-WidgetLog "Stopped $($o.Name)#$($o.ProcessId)" }
        catch { Write-WidgetLog "Could not stop $($o.ProcessId): $($_.Exception.Message)" "WARN" }
    }

    # Take over the mutex once the old process is gone. A killed owner leaves
    # it "abandoned": WaitOne then throws, but we still own it.
    $acquired = [bool]$script:MutexCreated
    if (-not $acquired) {
        try { $acquired = $script:AppMutex.WaitOne(5000) }
        catch [System.Threading.AbandonedMutexException] { $acquired = $true }
    }

    if (-not $acquired) {
        Write-WidgetLog "Could not acquire mutex after stopping old instance" "ERROR"
        [System.Windows.Forms.MessageBox]::Show(
            "Die laufende Instanz konnte nicht beendet werden.`r`nBitte Windows ab- und wieder anmelden und erneut starten.",
            "Widget aktiv",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button1, $mbTop
        ) | Out-Null
        exit
    }
    # A v3 instance that was just stopped may have written its data after
    # our copy: copy again (only if this start did the migration)
    if ($script:MigratedFromOld -and $script:OldInstanceRunning) {
        Start-Sleep -Milliseconds 500
        foreach ($fn in (Get-DataFileNames)) {
            $src = Join-Path $script:OldDataDir $fn
            if (Test-Path $src) { try { Copy-Item -Path $src -Destination (Join-Path $script:DataDir $fn) -Force } catch { } }
        }
        Write-WidgetLog "Data copied again after stopping the old version"
    }
}
Write-WidgetLog "Mutex acquired, building UI"

function Save-JsonState {
    param([string]$Path, $Data)
    # v4.5: after a restore / import the files on disk must stay as they are
    if ($script:FreezeData) { return }
    $tmpPath = "$Path.tmp"
    try {
        # -InputObject (not the pipeline) so arrays with 0/1 items stay JSON arrays
        $json = ConvertTo-Json -InputObject $Data -Depth 8
        if ($null -eq $json) { $json = "" }
        [System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.Encoding]::UTF8)
        if ([System.IO.File]::Exists($Path)) {
            try {
                # Atomic swap on NTFS. [NullString]::Value, NOT $null: PowerShell
                # passes $null as "" to string parameters, and an empty backup
                # path throws "Der Pfad hat ein ungueltiges Format".
                [System.IO.File]::Replace($tmpPath, $Path, [NullString]::Value)
            } catch {
                # Fallback (e.g. file briefly locked by AV / indexer)
                [System.IO.File]::Copy($tmpPath, $Path, $true)
                Remove-Item -Path $tmpPath -Force -ErrorAction SilentlyContinue
            }
        } else {
            [System.IO.File]::Move($tmpPath, $Path)
        }
    } catch {
        Write-WidgetLog "Failed to save state to ${Path}: $($_.Exception.Message)" "ERROR"
    }
}

function Load-JsonState {
    param([string]$Path, $DefaultValue)
    if (Test-Path $Path) {
        try {
            $raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                return ($raw | ConvertFrom-Json)
            }
        } catch {
            # Backup corrupt JSON once instead of silently losing it
            $bak = "$Path.corrupt_$(Get-Date -Format 'yyyyMMddHHmmss')"
            try { Copy-Item -Path $Path -Destination $bak -Force } catch { }
            Write-WidgetLog "Corrupt JSON in ${Path}, backed up to $bak" "WARN"
        }
    }
    return $DefaultValue
}

# Backups (v3.0): before the schema migration and on demand from the settings
$script:BackupDir = Join-Path $script:DataDir "backups"

function Backup-DataFiles {
    # Copies config/portfolio/alerts/transactions (not the intraday cache) to
    # backups\<timestamp>_<reason>\ and keeps the newest 10 backups.
    # Returns the backup folder, or "" when there was nothing to copy / it failed.
    param([string]$Reason = "manuell")
    try {
        $files = @(@("config.json", "portfolio.json", "alerts.json", "transactions.json", "profiles.json", "events.json", "alert-log.json", "cash.json", "savingsplans.json", "drawings.json", "notes.json", "news.json") |
            ForEach-Object { Join-Path $script:DataDir $_ } | Where-Object { Test-Path $_ })
        if ($files.Count -eq 0) { return "" }
        $safe = ($Reason -replace '[^A-Za-z0-9_.-]', '_')
        $dest = Join-Path $script:BackupDir ("{0}_{1}" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $safe)
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        foreach ($f in $files) { Copy-Item -Path $f -Destination $dest -Force }
        # v4.5: further depots
        $dd = Join-Path $script:DataDir "depots"
        if (Test-Path $dd) { Copy-Item -Path $dd -Destination (Join-Path $dest "depots") -Recurse -Force }
        $all = @(Get-ChildItem -Path $script:BackupDir -Directory | Sort-Object Name -Descending)
        if ($all.Count -gt 20) {
            $all | Select-Object -Skip 20 | ForEach-Object { Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Write-WidgetLog "Backup created: $dest"
        return $dest
    } catch {
        Write-WidgetLog "Backup failed: $($_.Exception.Message)" "ERROR"
        return ""
    }
}

$defaultConfig = [PSCustomObject]@{
    SchemaVersion         = $script:SchemaVersion
    CurrencyNoticeKey     = ""
    ActiveTicker          = "NVDA"
    ActiveTab             = "Chart"
    Currency              = "EUR"
    AutoCurrency          = $true             # v5.1: price + chart in the ticker's own currency (depot stays in Currency)
    UiStyle               = "Fresh"           # V7.0: new installs start in Fresh (saved settings stay as they are); was Refined. v5.2: Refined (same layout, cleaner) / Fresh (rounded cards, more space)
    RowDensity            = "Normal"          # v5.2: Compact / Normal / Comfortable list rows
    ZebraRows             = $false            # v5.2: every second list row slightly lighter
    ShowStatusBar         = $true             # V7.0: status bar at the bottom (data age, market, privacy mode)
    PortSimOpen           = $false            # v7.5: top-up calculator opened
    WatchDetail           = $true             # v7.5: detail panel in a very wide watchlist
    PerMonitorDpi         = $true             # V7.0: restart the widget when the window moves to a monitor with another scaling
    DayChangePill         = $false            # V7.0: day change as a coloured pill in the lists
    Animations            = $true             # V7.0: short fades (hover); also off when Windows animations are off
    FollowHighContrast    = $true             # V7.0: Windows high-contrast mode switches to the Contrast theme
    ShowToasts            = $true             # V7.0: short messages inside the window (alerts still use the tray)
    UseIcons              = $true             # v5.2: Segoe Fluent / MDL2 icons on buttons and menus
    TapeSpeed             = "Normal"          # v5.2: ticker bar Slow / Normal / Fast
    SettingsPage          = "Design"          # v5.3: last page of the settings window
    SettingsW             = 0                 # v5.3: settings window size (0 = default)
    SettingsH             = 0
    DialogPlacement       = [PSCustomObject]@{} # v5.5: position / size per dialog
    PctAxis               = $false            # v5.5: price axis in % from the first visible bar
    ShowSR                = $false            # v5.5: support / resistance (daily, from TA) in the chart
    SignalAlerts          = "Depot"           # v5.7: signal-change alerts for Depot / Alle (+ watchlist) / Aus
    PeerGroups            = [PSCustomObject]@{} # v5.7: own comparison group per ticker
    NewsFeeds             = ""                # v5.7: extra RSS / Atom feeds (one URL per line); since v7.7 only read once
    NewsSources           = @()               # v7.7: own feeds @{ Id; Url; Name; On; Notify; Group; Ticker; Minutes; MaxAgeDays }
    NewsSourcesMigrated   = $false            # v7.7: the old NewsFeeds text was taken over
    NewsYahoo             = $true             # v7.7: Yahoo Finance as a news source
    NewsYahooNotify       = $true             # v7.7: Yahoo headlines may trigger keyword notices
    NewsViewHidden        = @()               # v7.7: source ids hidden with the "Quellen" menu (still loaded)
    NewsAliases           = ""                # v7.7: "ABBN.SW = ABB, Asea" per line
    NewsInclude           = ""                # v7.7: show only headlines with one of these words
    NewsExclude           = ""                # v7.7: hide headlines with one of these words
    NewsHighlight         = ""                # v7.7: highlight headlines with one of these words
    NewsMergeSimilar      = $true             # v7.7: near-identical headlines become one row
    NewsPreview           = $false            # v7.7: preview pane under the news list
    NewsImages            = $true             # v7.7: load the picture of an item in the preview pane
    NewsHistoryDays       = 14                # v7.7: how long news stay in the history
    ShowNewsMarkers       = $false            # v7.7: news of the ticker as marks in the chart
    TwelveDataKeyEnc      = ""                # V6: API keys (Windows DPAPI, this user only)
    FinnhubKeyEnc         = ""
    ProviderCaps          = [PSCustomObject]@{} # V6: "Provider|Kind" -> works with this key (from the test)
    ProviderUsage         = [PSCustomObject]@{ Day = ""; TwelveData = 0; Finnhub = 0 }
    ChartType             = "Line"
    ShowVolume            = $true
    CompactMode           = $false
    TopMost               = $true
    ShowRsi               = $true
    PaneDivider           = 0.72
    ShowSma               = $true
    ShowVwap              = $true
    ShowBollinger         = $false
    ShowExtended          = $true
    NotifyMarketOpen      = $true
    NotifyEarnings        = $true
    # v4.3: phone push + quiet hours
    PushService           = "Aus"
    PushServer            = "https://ntfy.sh"
    PushTopic             = ""
    PushTokenEnc          = ""
    PushChatId            = ""
    PushAlerts            = $true
    PushEarnings          = $false
    QuietFrom             = ""
    QuietTo               = ""
    # v4.4
    CommandHistory        = @()
    ClosedPollMinutes     = 10
    # v4.5
    Depots                = @()
    ActiveDepot           = ""
    MainDepotName         = "Hauptdepot"
    LastAutoBackup        = ""
    # v4.6
    MaType                = "SMA"
    LowerPanel            = "RSI"
    UpDownScheme          = "Standard"
    UpColor               = ""
    DownColor             = ""
    AccentHex             = ""
    ShowArrows            = $false
    PriceFlash            = $true
    GlobalHotkey          = "Ctrl+Alt+W"
    SnapToEdges           = $true
    GridLayouts           = [PSCustomObject]@{}
    UserLayouts           = @()
    FirstRunDone          = $false
    # v4.7
    Language              = "DE"
    # v4.8
    LogScale              = $false
    CompactShow           = "DayAbs,Ext,Spark,Market"
    # v4.9: news tab + look and feel
    NewsFilter            = "All"             # All / Holdings / Watchlist / <ticker>
    NewsSeenAt            = ""                # newest item seen in the news tab (ISO, local)
    NewsRefreshMinutes    = 15
    NewsMoveThreshold     = 3                 # mark items of tickers moving >= x % today (0 = off)
    MonoFont              = "Consolas"        # numbers and tickers (from the next start)
    FontScale             = 100               # 90 / 100 / 110 / 120 % (from the next start)
    AlignNumbersRight     = $true             # numbers right-aligned in the lists
    RoundCorners          = $true             # Windows 11 rounded window corners
    # v5.0
    RiskFreePct           = 2.0               # risk-free rate for the Sharpe ratio
    TargetWeights         = [PSCustomObject]@{} # depot id ("main") -> ticker -> target %
    # v4.9.5
    NewsMuted             = @()               # muted news sources (publisher names)
    NewsKeywords          = ""                # "downgrade, übernahme" -> push for held tickers
    NewsKeywordWatch      = $false            # keywords also for watchlist tickers
    NewsKeywordLastAt     = ""                # newest item already checked for keywords (ISO)
    TrayFollowsDepot      = $true             # tray icon colour = depot day result
    PrivacyMode           = $false            # F9: hide amounts, keep percentages
    RecentTickers         = @()               # last opened tickers (search list)
    ShowPrevClose         = $true             # dotted previous-close line in the chart
    SmaFastPeriod         = 20
    SmaSlowPeriod         = 50
    RsiPeriod             = 14
    RsiOverbought         = 70
    RsiOversold           = 30
    Theme                 = "Dark"
    AccentColor           = "Sky"
    ShowTrayNotifications = $true
    HttpTimeoutSeconds    = 8
    RefreshSeconds        = 15
    SlowRefreshSeconds    = 60
    Timeframe             = "1d"
    PortfolioSort         = "ValueDesc"
    WindowX               = 100
    WindowY               = 100
    WindowW               = 0
    WindowH               = 0
    WindowMaximized       = $false
    CompactTape           = $true
    ShowLevels            = $true
    CompareTicker         = ""
    CompareMore           = @()               # v5.0: up to 2 more comparison tickers
    ShowTrades            = $true             # v5.0: own buys / sells in the chart
    Autostart             = $false
    # v4.0
    Layout                = "Standard"        # Ticker / Compact / Standard / Terminal
    LastFullLayout        = "Standard"        # where C / Expand returns to
    TerminalShowWatch     = $true
    TerminalShowPortfolio = $true
    TerminalChartPct      = 55
    TerminalSplitPct      = 50                # v5.0: watchlist share when side by side
    TerminalFull          = ""                # v5.0: list shown as a full page (restored at start)
    ReopenAnalysis        = ""                # v5.0: Analyse page that was open when the widget closed
    AnalysisLastPage      = "Perf"
    WatchGroups           = @()               # v5.0: @{ Name; Symbols }
    WatchGroup            = ""                # shown group, "" = all
    HoverCards            = $true             # v5.0: info card when the mouse rests on a ticker
    TerminalBottom        = "Watchlist"       # bottom panel when only one fits
    TerminalW             = 0                 # remembered client size of the Terminal layout
    TerminalH             = 0
    Opacity               = 100
    TooltipMode           = "Short"           # Off / Short / Long
    TooltipDelayMs        = 400
    ReportBase            = "EUR"
    # v4.1: portfolio analytics
    AnalysisCompare       = "EUNL.DE, ^GSPC, ^GDAXI, ^ATX"   # v5.1: indices on the Vergleich page
    ScenarioPct           = -20               # v5.1: market move for the scenario
    AnalysisBenchmark     = "EUNL.DE"         # iShares Core MSCI World (Xetra, EUR); "" = none
    AnalysisBase          = ""                # "" = display currency
    AnalysisRange         = "Max"             # 6M / 1Y / 3Y / Max
    AnalysisShowBench     = $true
    AnalysisShowInvested  = $true
    ConcentrationWarnPct  = 20
    Watchlist            = @("NVDA", "ABBN.SW", "MSFT", "AAPL", "AMD", "AMZN", "AVGO")
    # v8.0: own looks and handling
    ColorRules            = @()                # empty = the ready-made rules (all off)
    CustomThemes          = @()
    OwnTargets            = $null              # ticker -> own target price
    ColumnSets            = @()
    ColumnSetMap          = $null              # "Layout:x" / "Group:y" -> column set name
    KeyMap                = $null              # action -> own shortcut
    Favorites             = @()
    KpiTiles              = @()                # empty = all, default order
    UserProfiles          = @()
    ActiveProfile         = ""
    # v8.0: alerts and notices
    AlertTemplates        = @()
    EarningsLeadDays      = 1                  # -1 = off
    ExDivLeadDays         = -1
    SummaryAuto           = "Off"              # Off / Daily / Weekly
    SummaryLastShown      = ""
    # v8.0: goals (display currency, 0 = no goal)
    GoalDepotValue        = 0.0
    GoalDividendYear      = 0.0
}

# v5.3: untouched copy of the defaults ("changed" markers, reset page, settings import)
$script:ConfigDefaults = $defaultConfig.PSObject.Copy()
$script:Config = Load-JsonState -Path $script:ConfigPath -DefaultValue $defaultConfig

# Schema migration (v3.0 / v4.0): back up the existing data files once, BEFORE
# anything is rewritten. v4 only adds config keys; the files stay readable by
# v3.0 (in v4.0 they live in the new data folder anyway).
$cfgSchema = 0
if ($null -ne $script:Config.PSObject.Properties["SchemaVersion"]) { $cfgSchema = [int]$script:Config.SchemaVersion }
if ((Test-Path $script:ConfigPath) -and $cfgSchema -lt $script:SchemaVersion) {
    $bk = Backup-DataFiles -Reason ("vor_v{0}_migration" -f $script:SchemaVersion)
    Write-WidgetLog ("Migrating data from schema {0} to {1} (backup: {2})" -f $cfgSchema, $script:SchemaVersion, $(if ($bk) { $bk } else { "none" }))
}

# Ensure all default properties exist on loaded config (schema migration)
foreach ($prop in $defaultConfig.PSObject.Properties) {
    if ($null -eq $script:Config.PSObject.Properties[$prop.Name]) {
        $script:Config | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    }
}
$script:Config.SchemaVersion = $script:SchemaVersion

# Sanitize Watchlist & Settings
if ($null -eq $script:Config.Watchlist -or @($script:Config.Watchlist).Count -eq 0) {
    $script:Config.Watchlist = @("NVDA", "ABBN.SW", "MSFT", "AAPL", "AMD", "AMZN")
} else {
    $cleanWl = New-Object System.Collections.Generic.List[string]
    foreach ($w in $script:Config.Watchlist) {
        if (-not [string]::IsNullOrWhiteSpace($w)) {
            $u = $w.Trim().ToUpper()
            if (-not $cleanWl.Contains($u)) { [void]$cleanWl.Add($u) }
        }
    }
    $script:Config.Watchlist = if ($cleanWl.Count -gt 0) { $cleanWl.ToArray() } else { @("NVDA") }
}

if ([string]::IsNullOrWhiteSpace($script:Config.ActiveTicker)) { $script:Config.ActiveTicker = $script:Config.Watchlist[0] }
if ([string]$script:Config.Currency -notin @(Get-DisplayCurrencies)) { $script:Config.Currency = "EUR" }
if ($script:Config.ChartType -notin @("Line", "Candle", "HA")) { $script:Config.ChartType = "Line" }
if ($script:Config.ActiveTab -notin @("Chart", "Portfolio", "Watchlist", "News")) { $script:Config.ActiveTab = "Chart" }
# v8.0: repair a group list saved as a list inside a list
$script:Config.WatchGroups = ConvertTo-FlatWatchGroups $script:Config.WatchGroups
if ($script:Config.Theme -notin @(Get-ThemeNames) -and @($script:Config.CustomThemes | Where-Object { $null -ne $_ -and [string]$_.Name -eq [string]$script:Config.Theme }).Count -eq 0) { $script:Config.Theme = "Dark" }
# v4.0 layouts: a v3 config only knows CompactMode
if ($script:Config.PSObject.Properties["Layout"] -and $cfgSchema -lt 4 -and [bool]$script:Config.CompactMode) { $script:Config.Layout = "Compact" }
if ([string]$script:Config.Layout -notin @(Get-LayoutNames)) { $script:Config.Layout = "Standard" }
if ([string]$script:Config.LastFullLayout -notin @("Standard", "Terminal")) { $script:Config.LastFullLayout = "Standard" }
$script:Config.CompactMode = Test-CompactLayout $script:Config.Layout
if ([string]$script:Config.TooltipMode -notin @((Get-TooltipModes).Keys)) { $script:Config.TooltipMode = "Short" }
$script:Config.TooltipDelayMs   = [math]::Max(0, [math]::Min(5000, [int]$script:Config.TooltipDelayMs))
$script:Config.Opacity          = [math]::Max(30, [math]::Min(100, [int]$script:Config.Opacity))
$script:Config.TerminalChartPct = [math]::Max(25, [math]::Min(80, [int]$script:Config.TerminalChartPct))
$script:Config.AnalysisBenchmark = ([string]$script:Config.AnalysisBenchmark).Trim().ToUpper()
if ([string]$script:Config.AnalysisRange -notin @("6M", "1Y", "3Y", "Max")) { $script:Config.AnalysisRange = "Max" }
$script:Config.ConcentrationWarnPct = [math]::Max(5, [math]::Min(90, [int]$script:Config.ConcentrationWarnPct))
if ([string]$script:Config.TerminalBottom -notin @("Watchlist", "Portfolio", "News")) { $script:Config.TerminalBottom = "Watchlist" }
$script:Config.NewsRefreshMinutes = [math]::Max(5, [math]::Min(240, [int]$script:Config.NewsRefreshMinutes))
$script:Config.NewsMoveThreshold  = [math]::Max(0, [math]::Min(50, [int]$script:Config.NewsMoveThreshold))
$script:Config.NewsHistoryDays    = [math]::Max(1, [math]::Min(90, [int]$script:Config.NewsHistoryDays))
# v7.7: the feeds of the old text setting become selectable sources, once. NewsFeeds
# stays untouched, so an older version still finds its feeds.
$script:Config.NewsSources = @(ConvertTo-NewsSourceList $script:Config.NewsSources)
if (-not [bool]$script:Config.NewsSourcesMigrated) {
    $script:Config.NewsSources = @(Add-LegacyNewsFeeds -Sources $script:Config.NewsSources -Text ([string]$script:Config.NewsFeeds))
    $script:Config.NewsSourcesMigrated = $true
}
if ([int]$script:Config.FontScale -notin @(Get-FontScaleSteps)) { $script:Config.FontScale = 100 }
if ([string]$script:Config.MonoFont -notin @(Get-MonoFontNames)) { $script:Config.MonoFont = "Consolas" }
if (-not (Get-NormalizedCurrencyCode ([string]$script:Config.ReportBase))) { $script:Config.ReportBase = "EUR" }
if ($script:Config.AccentColor -notin @("Sky", "Amber", "Violet", "Eigene", "Windows")) { $script:Config.AccentColor = "Sky" }
if ([string]$script:Config.UiStyle -notin @(Get-UiStyles)) { $script:Config.UiStyle = "Refined" }
# V7.0: Windows high-contrast mode -> Contrast theme
try {
    if ([bool]$script:Config.FollowHighContrast -and [System.Windows.Forms.SystemInformation]::HighContrast -and [string]$script:Config.Theme -ne "Contrast") {
        $script:Config.Theme = "Contrast"
        Write-WidgetLog "Windows high-contrast mode is on: Contrast theme"
    }
} catch { }
if ([string]$script:Config.RowDensity -notin @(Get-RowDensities)) { $script:Config.RowDensity = "Normal" }
if ([string]$script:Config.TapeSpeed -notin @(Get-TapeSpeeds)) { $script:Config.TapeSpeed = "Normal" }
if ([string]$script:Config.MaType -notin @("SMA", "EMA")) { $script:Config.MaType = "SMA" }
if ([string]$script:Config.LowerPanel -notin @("RSI", "MACD")) { $script:Config.LowerPanel = "RSI" }
if ([int]$script:Config.RefreshSeconds -lt 5) { $script:Config.RefreshSeconds = 15 }
if ([int]$script:Config.SlowRefreshSeconds -lt [int]$script:Config.RefreshSeconds) { $script:Config.SlowRefreshSeconds = [math]::Max(60, [int]$script:Config.RefreshSeconds) }
if ([int]$script:Config.SmaFastPeriod -lt 2) { $script:Config.SmaFastPeriod = 20 }
if ([int]$script:Config.SmaSlowPeriod -lt 5) { $script:Config.SmaSlowPeriod = 50 }
if ([int]$script:Config.RsiPeriod -lt 2) { $script:Config.RsiPeriod = 14 }

# ------------------------------------------------------------------------------
# Depots (v4.5): several portfolios. The main depot uses portfolio.json /
# transactions.json in the data folder (as before), others live in
# depots\<id>\. Alerts, profiles and event dates are shared.
# ------------------------------------------------------------------------------
$script:DepotDir = Join-Path $script:DataDir "depots"

function Get-DepotList {
    $list = @([PSCustomObject]@{ Id = ""; Name = $(if ($script:Config.MainDepotName) { [string]$script:Config.MainDepotName } else { "Hauptdepot" }) })
    foreach ($d in @($script:Config.Depots)) { if ($null -ne $d -and $d.Id) { $list += [PSCustomObject]@{ Id = [string]$d.Id; Name = [string]$d.Name } } }
    return $list
}

function Get-DepotName {
    param([string]$Id)
    foreach ($d in Get-DepotList) { if ($d.Id -eq $Id) { return $d.Name } }
    return ""
}

function Set-DepotPaths {
    param([string]$Id)
    if (-not $Id) {
        $script:PortfolioPath = Join-Path $script:DataDir "portfolio.json"
        $script:TransactionsPath = Join-Path $script:DataDir "transactions.json"
        $script:CashPath = Join-Path $script:DataDir "cash.json"
        $script:PlansPath = Join-Path $script:DataDir "savingsplans.json"
        return
    }
    $dir = Join-Path $script:DepotDir $Id
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script:PortfolioPath = Join-Path $dir "portfolio.json"
    $script:TransactionsPath = Join-Path $dir "transactions.json"
    $script:CashPath = Join-Path $dir "cash.json"
    $script:PlansPath = Join-Path $dir "savingsplans.json"
}

if ([string]$script:Config.ActiveDepot -and -not (@(Get-DepotList | Where-Object { $_.Id -eq [string]$script:Config.ActiveDepot }).Count)) { $script:Config.ActiveDepot = "" }
Set-DepotPaths ([string]$script:Config.ActiveDepot)

# Portfolio Holdings
function Read-PortfolioData {
$script:Portfolio = @{}
$rawPortfolio = Load-JsonState -Path $script:PortfolioPath -DefaultValue $null
if ($null -ne $rawPortfolio) {
    foreach ($prop in $rawPortfolio.PSObject.Properties) {
        if ($null -ne $prop.Value) {
            # v3.0: keep any ISO currency (v2.9 forced everything but EUR/USD/CHF to EUR)
            $pCurr = Get-NormalizedCurrencyCode ([string]$prop.Value.Currency)
            if (-not $pCurr) { $pCurr = "EUR" }
            $script:Portfolio[$prop.Name.ToUpper()] = [PSCustomObject]@{
                Ticker    = $prop.Name.ToUpper()
                Shares    = [double]$prop.Value.Shares
                AvgPrice  = [double]$prop.Value.AvgPrice
                Currency  = $pCurr
                BuyAmount = [double]$prop.Value.BuyAmount
                TargetAvg = [double]$prop.Value.TargetAvg
            }
        }
    }
}
}
Read-PortfolioData

# Global Alerts
$script:Alerts = New-Object System.Collections.Generic.List[PSObject]
$rawAlerts = Load-JsonState -Path $script:AlertsPath -DefaultValue @()
foreach ($a in $rawAlerts) {
    if ($null -ne $a -and $a.Ticker) {
        $script:Alerts.Add([PSCustomObject]@{
            Id          = [string]$a.Id
            Ticker      = [string]$a.Ticker.ToUpper()
            Condition   = [string]$a.Condition
            TargetPrice = [double]$a.TargetPrice
            Currency    = if ($a.Currency) { [string]$a.Currency } else { "EUR" }
            Triggered   = [bool]$a.Triggered
            # v2.9: note, automatic re-arm (minutes, 0 = off) and trigger time
            Note        = if ($a.Note) { [string]$a.Note } else { "" }
            RearmMin    = [int]$a.RearmMin
            TriggeredAt = if ($a.TriggeredAt) { [string]$a.TriggeredAt } else { "" }
            # v4.3: expiry date, trailing high (0 = not yet known), push per alert
            ExpiresAt   = if ($a.ExpiresAt) { [string]$a.ExpiresAt } else { "" }
            Peak        = $(if ($null -ne $a.Peak) { [double]$a.Peak } else { 0.0 })
            Push        = if ($null -ne $a.Push) { [bool]$a.Push } else { $true }
        })
        # v4.9.5 pause and v5.0 trend line points survive a restart
        $na = $script:Alerts[$script:Alerts.Count - 1]
        if ($a.SnoozeUntil) { $na | Add-Member -NotePropertyName SnoozeUntil -NotePropertyValue ([string]$a.SnoozeUntil) -Force }
        # v8.0: second condition of a combined alert
        if ($a.Condition2) {
            $na | Add-Member -NotePropertyName Condition2 -NotePropertyValue ([string]$a.Condition2) -Force
            $na | Add-Member -NotePropertyName Target2 -NotePropertyValue ([double]$a.Target2) -Force
            $na | Add-Member -NotePropertyName Currency2 -NotePropertyValue ([string]$a.Currency2) -Force
        }
        if ([string]$a.Condition -like "Trend*") {
            foreach ($f in @("T1", "T2")) { $na | Add-Member -NotePropertyName $f -NotePropertyValue ([long]$a.$f) -Force }
            foreach ($f in @("P1", "P2")) { $na | Add-Member -NotePropertyName $f -NotePropertyValue ([double]$a.$f) -Force }
        }
    }
}

# Alert history (v4.3): every hit with value and push status, last 500
$script:AlertLogPath = Join-Path $script:DataDir "alert-log.json"
$script:AlertLog = New-Object System.Collections.Generic.List[PSObject]
foreach ($e in @(Load-JsonState -Path $script:AlertLogPath -DefaultValue @())) {
    if ($null -ne $e -and $e.At) {
        $script:AlertLog.Add([PSCustomObject]@{
            At = [string]$e.At; Ticker = [string]$e.Ticker; Condition = [string]$e.Condition
            Text = [string]$e.Text; Note = [string]$e.Note; Push = [string]$e.Push
        })
    }
}

# Transaction history (v2.9): buys / sells / dividends with realized P/L
# (path set by Set-DepotPaths)
function Read-TransactionsData {
$script:Transactions = New-Object System.Collections.Generic.List[PSObject]
foreach ($t in @(Load-JsonState -Path $script:TransactionsPath -DefaultValue @())) {
    if ($null -ne $t -and $t.Ticker -and $t.Type) {
        $script:Transactions.Add([PSCustomObject]@{
            Id       = if ($t.Id) { [string]$t.Id } else { [Guid]::NewGuid().ToString("N") }
            Date     = [string]$t.Date
            Ticker   = ([string]$t.Ticker).ToUpper()
            Type     = [string]$t.Type
            Shares   = [double]$t.Shares
            Price    = [double]$t.Price
            Fee      = [double]$t.Fee
            Currency = if ($t.Currency) { [string]$t.Currency } else { "EUR" }
            Realized = [double]$t.Realized
            Note     = [string]$t.Note
        })
    }
}
}
Read-TransactionsData

# ------------------------------------------------------------------------------
# v5.0: cash account per depot (cash.json next to the transactions). Trades
# booked after cash tracking was switched on move the cash; the ledger holds
# deposits, withdrawals, interest, fees and the opening balance.
# ------------------------------------------------------------------------------
function Read-CashData {
    $raw = Load-JsonState -Path $script:CashPath -DefaultValue $null
    $c = [PSCustomObject]@{ Enabled = $false; Currency = [string]$script:Config.Currency; BaselineIds = @(); Entries = (New-Object System.Collections.Generic.List[object]) }
    if ($null -ne $raw) {
        if ($null -ne $raw.Enabled) { $c.Enabled = [bool]$raw.Enabled }
        if ($raw.Currency) { $c.Currency = ([string]$raw.Currency).ToUpper() }
        $c.BaselineIds = @(@($raw.BaselineIds) | Where-Object { $_ } | ForEach-Object { [string]$_ })
        foreach ($e in @($raw.Entries)) {
            if ($null -eq $e -or $null -eq $e.Amount) { continue }
            $c.Entries.Add([PSCustomObject]@{ Id = [string]$e.Id; Date = [string]$e.Date; Kind = [string]$e.Kind; Amount = [double]$e.Amount; Currency = ([string]$e.Currency).ToUpper(); Note = [string]$e.Note })
        }
    }
    $script:Cash = $c
}

function Save-CashData {
    $c = $script:Cash
    Save-JsonState -Path $script:CashPath -Data ([PSCustomObject]@{ Enabled = [bool]$c.Enabled; Currency = [string]$c.Currency; BaselineIds = @($c.BaselineIds); Entries = $c.Entries.ToArray() })
}

function Add-CashEntry {
    param([string]$Kind, [double]$Amount, [string]$Note = "", [string]$Date = "")
    $d = if ($Date) { $Date } else { (Get-Date).ToString("yyyy-MM-dd") }
    $script:Cash.Entries.Add([PSCustomObject]@{ Id = [Guid]::NewGuid().ToString("N"); Date = $d; Kind = $Kind; Amount = $Amount; Currency = [string]$script:Cash.Currency; Note = $Note })
    Save-CashData
}

function Get-CashInfo {
    # $null while cash tracking is off; else balance in the cash and the display currency
    param([string]$Currency = "")
    $c = $script:Cash
    if ($null -eq $c -or -not [bool]$c.Enabled) { return $null }
    $cur = if ($Currency) { $Currency } else { [string]$script:Config.Currency }
    $mv = @(Get-CashMovements -Transactions $script:Transactions.ToArray() -Entries $c.Entries.ToArray() -ExcludeIds @($c.BaselineIds))
    $rates = @{}
    foreach ($m in $mv) {
        $mc = [string]$m.Currency
        if ($mc -and $mc -ne [string]$c.Currency -and -not $rates.ContainsKey($mc)) { $rates[$mc] = Convert-CurrencyValue -Amount 1.0 -FromCurrency $mc -ToCurrency ([string]$c.Currency) }
    }
    $b = Get-CashBalance -Movements $mv -Currency ([string]$c.Currency) -Rates $rates
    return [PSCustomObject]@{
        Balance = $b.Balance; Currency = [string]$c.Currency; Missing = $b.Missing; Movements = $mv
        Display = (Convert-CurrencyValue -Amount $b.Balance -FromCurrency ([string]$c.Currency) -ToCurrency $cur); DisplayCurrency = $cur
    }
}

# v5.0: savings plans (savingsplans.json per depot), booked automatically
function Read-SavingsPlans {
    $raw = Load-JsonState -Path $script:PlansPath -DefaultValue $null
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($p in @($raw)) {
        if ($null -eq $p -or -not $p.Ticker) { continue }
        $list.Add([PSCustomObject]@{
            Id = [string]$p.Id; Ticker = ([string]$p.Ticker).ToUpper(); Amount = [double]$p.Amount; Fee = [double]$p.Fee
            Currency = ([string]$p.Currency).ToUpper(); Day = [int]$p.Day; Start = [string]$p.Start; LastBooked = [string]$p.LastBooked
            Active = $(if ($null -eq $p.Active) { $true } else { [bool]$p.Active })
            Increase = [double]$p.Increase; Pause = [string]$p.Pause   # v5.5
        })
    }
    $script:SavingsPlans = $list
}
function Save-SavingsPlans { Save-JsonState -Path $script:PlansPath -Data $script:SavingsPlans.ToArray() }

Read-CashData
Read-SavingsPlans

# Company profiles (v4.1): sector / country from Yahoo plus manual overrides,
# kept apart from portfolio.json so editing a position never loses them
$script:ProfilesPath = Join-Path $script:DataDir "profiles.json"
$script:Profiles = @{}
$rawProfiles = Load-JsonState -Path $script:ProfilesPath -DefaultValue $null
if ($null -ne $rawProfiles) {
    foreach ($prop in $rawProfiles.PSObject.Properties) {
        if ($null -eq $prop.Value) { continue }
        $v = $prop.Value
        $script:Profiles[$prop.Name.ToUpper()] = [PSCustomObject]@{
            Sector = [string]$v.Sector; Industry = [string]$v.Industry; Country = [string]$v.Country
            QuoteType = [string]$v.QuoteType; Name = [string]$v.Name; FetchedAt = [string]$v.FetchedAt
            ManualSector = [string]$v.ManualSector; ManualCountry = [string]$v.ManualCountry
        }
    }
}

# v5.7: valuation snapshots per ticker and day (fund_history.json)
$script:FundHistPath = Join-Path $script:DataDir "fund_history.json"
$script:FundHist = @{}
$rawFh = Load-JsonState -Path $script:FundHistPath -DefaultValue $null
if ($null -ne $rawFh) { foreach ($prop in $rawFh.PSObject.Properties) { $script:FundHist[$prop.Name.ToUpper()] = @($prop.Value) } }

# v5.5: free-text note per ticker (thesis / reason for buying) in notes.json
$script:NotesPath = Join-Path $script:DataDir "notes.json"
$script:Notes = @{}
$rawNotes = Load-JsonState -Path $script:NotesPath -DefaultValue $null
if ($null -ne $rawNotes) {
    foreach ($prop in $rawNotes.PSObject.Properties) {
        if ($null -ne $prop.Value -and [string]$prop.Value.Text) {
            $script:Notes[$prop.Name.ToUpper()] = [PSCustomObject]@{ Text = [string]$prop.Value.Text; Updated = [string]$prop.Value.Updated }
        }
    }
}

# v5.5: daily bars + signals per ticker, fetched once a day (daily_cache.json);
# feeds the signal column, the support / resistance lines and later analysis
$script:DailyCachePath = Join-Path $script:DataDir "daily_cache.json"
$script:DailyCache = @{}
$script:DailyPending = New-Object System.Collections.Generic.HashSet[string]
$script:DailyFailed = @{}   # sym -> day of a failed fetch (no retry loop on the same day)
$rawDaily = Load-JsonState -Path $script:DailyCachePath -DefaultValue $null
if ($null -ne $rawDaily) { foreach ($prop in $rawDaily.PSObject.Properties) { if ($null -ne $prop.Value) { $script:DailyCache[$prop.Name.ToUpper()] = $prop.Value } } }

function Get-TodayKey { return (Get-Date).ToString("yyyy-MM-dd") }

function Save-DailyCache {
    # only tickers still in use (watchlist, depots, active)
    $keep = New-Object System.Collections.Generic.HashSet[string]
    try { foreach ($t in @(Get-KnownTickers)) { [void]$keep.Add(([string]$t).ToUpper()) } } catch { }
    [void]$keep.Add(([string]$script:Config.ActiveTicker).ToUpper())
    foreach ($k in @($script:DailyCache.Keys)) { if (-not $keep.Contains($k)) { [void]$script:DailyCache.Remove($k) } }
    Save-JsonState -Path $script:DailyCachePath -Data $script:DailyCache
}

function Save-DailyFromBars {
    # bars from any provider -> daily cache entry (+ signal-change check)
    param([string]$Sym, $Bars)
    if ($null -eq $Bars -or @($Bars.Close).Count -lt 30) { return }
    $sig = Get-TechnicalSignals -Closes ([double[]]$Bars.Close) -Highs ([double[]]$Bars.High) -Lows ([double[]]$Bars.Low) -Volumes ([double[]]$Bars.Volume)
    $old = $script:DailyCache[$Sym]
    $script:DailyCache[$Sym] = ConvertTo-DailyCacheEntry -Bars $Bars -Sig $sig -Day (Get-TodayKey)
    $script:DailyCache[$Sym] | Add-Member -NotePropertyName Source -NotePropertyValue ([string]$Bars.Source) -Force
    [void]$script:DailyFailed.Remove($Sym)
    try { Send-SignalChangeAlerts -Sym $Sym -Old $old -New $script:DailyCache[$Sym] } catch { }
    try { Save-DailyCache } catch { }
    Update-ChartCacheSignature
    $pnlChartCanvas.Invalidate()
    if ($dgvWatchlist.Columns["Signal"].Visible) { Refresh-WatchlistAndAlerts }
}

function Request-DailyBars {
    # fetches what is not fresh today (in the background); OnDone runs on the UI thread
    param([string[]]$Symbols, [scriptblock]$OnDone = $null)
    $day = Get-TodayKey
    $need = @(@($Symbols) | Where-Object { $_ } | ForEach-Object { ([string]$_).ToUpper() } | Select-Object -Unique |
        Where-Object { -not (Test-DailyCacheFresh -Entry $script:DailyCache[$_] -Day $day) -and -not $script:DailyPending.Contains($_) -and [string]$script:DailyFailed[$_] -ne $day })
    if ($need.Count -eq 0) { if ($null -ne $OnDone) { & $OnDone }; return }
    $map = @{}
    foreach ($sy in $need) { $map[$sy] = Get-ProviderUrl -Kind "Daily" -Symbol $sy -Range "1y"; [void]$script:DailyPending.Add($sy) }
    Start-FetchJob -Urls @($map.Values) -MaxConcurrency 4 -Context @{ Map = $map; Day = $day; OnDone = $OnDone } -OnComplete {
        param($Box, $Ctx)
        foreach ($sy in @($Ctx.Map.Keys)) {
            [void]$script:DailyPending.Remove($sy)
            $bars = $null
            try { $bars = ConvertFrom-YahooOhlc -Json $Box.Results[$Ctx.Map[$sy]] } catch { $bars = $null }
            if ($null -eq $bars -or @($bars.Close).Count -lt 30) {
                $script:DailyFailed[$sy] = $Ctx.Day
                # V6: Twelve Data / Finnhub step in (US tickers on the free tiers)
                $script:FallbackDay = $Ctx.Day
                [void](Request-ProviderBars -Sym $sy -OnBars ([scriptblock]::Create(('param($b) Save-DailyFromBars -Sym "{0}" -Bars $b' -f $sy))))
                continue
            }
            $sig = Get-TechnicalSignals -Closes ([double[]]$bars.Close) -Highs ([double[]]$bars.High) -Lows ([double[]]$bars.Low) -Volumes ([double[]]$bars.Volume)
            $oldE = $script:DailyCache[$sy]
            $script:DailyCache[$sy] = ConvertTo-DailyCacheEntry -Bars $bars -Sig $sig -Day $Ctx.Day
            # v5.7: signal changed since the last day -> note (depot / all, see settings)
            try { Send-SignalChangeAlerts -Sym $sy -Old $oldE -New $script:DailyCache[$sy] } catch { Write-WidgetLog "Signal alert $sy : $($_.Exception.Message)" "WARN" }
        }
        try { Save-DailyCache } catch { Write-WidgetLog "Daily cache: $($_.Exception.Message)" "WARN" }
        Update-ChartCacheSignature
        $pnlChartCanvas.Invalidate()
        if ($dgvWatchlist.Columns["Signal"].Visible) { Refresh-WatchlistAndAlerts }
        if ($null -ne $Ctx.OnDone) { & $Ctx.OnDone }
    }
}

# ==============================================================================
# V6: Twelve Data / Finnhub - keys, budget, test, fallback, analysis data
# ==============================================================================
$script:ProvCachePath = Join-Path $script:DataDir "provider_cache.json"
$script:ProvCache = @{}
$rawPc = Load-JsonState -Path $script:ProvCachePath -DefaultValue $null
if ($null -ne $rawPc) { foreach ($prop in $rawPc.PSObject.Properties) { $script:ProvCache[$prop.Name] = $prop.Value } }

function Get-ProviderKey {
    param([string]$Provider)
    $enc = if ($Provider -eq "TwelveData") { [string]$script:Config.TwelveDataKeyEnc } else { [string]$script:Config.FinnhubKeyEnc }
    if (-not $enc) { return "" }
    return (Unprotect-Secret $enc)
}

function Test-ProviderCap {
    # unknown (not tested yet) counts as "try it"; a failed test as "no"
    param([string]$Provider, [string]$Kind)
    $c = $script:Config.ProviderCaps
    if ($null -eq $c -or $c -is [string]) { return $true }
    $pp = $c.PSObject.Properties["$Provider|$Kind"]
    if ($null -eq $pp) { return $true }
    return [bool]$pp.Value
}

function Add-ProviderUsage {
    param([string]$Provider)
    $u = $script:Config.ProviderUsage
    $day = (Get-Date).ToString("yyyy-MM-dd")
    if ($null -eq $u -or $u -is [string] -or [string]$u.Day -ne $day) { $u = [PSCustomObject]@{ Day = $day; TwelveData = 0; Finnhub = 0 }; $script:Config.ProviderUsage = $u }
    if ($null -eq $u.PSObject.Properties[$Provider]) { $u | Add-Member -NotePropertyName $Provider -NotePropertyValue 0 -Force }
    $u.$Provider = [int]$u.$Provider + 1
}

function Get-ProviderDayCount {
    param([string]$Provider)
    $u = $script:Config.ProviderUsage
    if ($null -eq $u -or $u -is [string] -or [string]$u.Day -ne (Get-Date).ToString("yyyy-MM-dd") -or $null -eq $u.PSObject.Properties[$Provider]) { return 0 }
    return [int]$u.$Provider
}

function Select-ProviderUrls {
    # keeps only the requests the per-minute / per-day budget allows; says why once
    param([array]$Requests)
    $ok = @()
    $count = @{}
    foreach ($r in @($Requests)) {
        $pv = [string]$r.Provider
        $log = @($script:FetchLog.ToArray())
        $extra = [int]$count[$pv]
        $fake = @(1..$extra | Where-Object { $extra -gt 0 } | ForEach-Object { [PSCustomObject]@{ T = (Get-Date); P = $pv } })
        $b = Test-ProviderBudget -Log ($log + $fake) -Provider $pv -DayCount ((Get-ProviderDayCount $pv) + $extra)
        if (-not $b.Ok) {
            if ($script:LastBudgetMsg -ne $b.Reason) { $script:LastBudgetMsg = $b.Reason; Set-TransientStatus $b.Reason 6; Write-WidgetLog $b.Reason "WARN" }
            continue
        }
        $count[$pv] = $extra + 1
        $ok += $r
    }
    return $ok
}

function Request-ProviderBars {
    # fallback for daily bars when Yahoo had nothing: Twelve Data, then Finnhub (US only on the free tiers)
    param([string]$Sym, [scriptblock]$OnBars)
    foreach ($pv in @("TwelveData", "Finnhub")) {
        $key = Get-ProviderKey $pv
        $ps = ConvertTo-ProviderSymbol -Symbol $Sym -Provider $pv
        if (-not $key -or -not $ps -or -not (Test-ProviderCap $pv "Daily")) { continue }
        $from = [DateTimeOffset]::UtcNow.AddDays(-380).ToUnixTimeSeconds(); $to = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $url = Get-ProviderRequestUrl -Provider $pv -Kind "Daily" -Symbol $ps -Key $key -From $from -To $to
        if (@(Select-ProviderUrls @([PSCustomObject]@{ Provider = $pv; Url = $url })).Count -eq 0) { continue }
        Write-WidgetLog ("Daily bars {0}: Yahoo empty, trying {1}" -f $Sym, $pv)
        Start-FetchJob -Urls @($url) -MaxConcurrency 1 -Context @{ Url = $url; Sym = $Sym; Pv = $pv; OnBars = $OnBars } -OnComplete {
            param($Box, $Ctx)
            $j = $Box.Results[$Ctx.Url]
            $bars = if ($Ctx.Pv -eq "TwelveData") { ConvertFrom-TwelveDataSeries $j } else { ConvertFrom-FinnhubCandles $j }
            if ($null -eq $bars) { Write-WidgetLog ("{0} {1}: {2}" -f $Ctx.Pv, $Ctx.Sym, (Get-ProviderError $j)) "WARN"; return }
            & $Ctx.OnBars $bars
        }
        return $true
    }
    return $false
}

function Test-Providers {
    # probes every endpoint with the user's keys (AAPL), stores what works
    param([switch]$Quiet)
    $reqs = @()
    $from = (Get-Date).AddDays(-400).ToString("yyyy-MM-dd"); $to = (Get-Date).ToString("yyyy-MM-dd")
    $fromU = [DateTimeOffset]::UtcNow.AddDays(-30).ToUnixTimeSeconds(); $toU = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $tdKey = Get-ProviderKey "TwelveData"; $fhKey = Get-ProviderKey "Finnhub"
    if ($tdKey) { foreach ($k in @("Daily", "Quote")) { $reqs += [PSCustomObject]@{ Provider = "TwelveData"; Kind = $k; Url = (Get-ProviderRequestUrl -Provider "TwelveData" -Kind $k -Symbol "AAPL" -Key $tdKey) } } }
    if ($fhKey) {
        foreach ($k in @("Quote", "Daily", "Metric", "Earnings", "Calendar", "Recommendation", "PriceTarget")) {
            $f = if ($k -eq "Daily") { $fromU } else { $from }; $t = if ($k -eq "Daily") { $toU } else { $to }
            $reqs += [PSCustomObject]@{ Provider = "Finnhub"; Kind = $k; Url = (Get-ProviderRequestUrl -Provider "Finnhub" -Kind $k -Symbol "AAPL" -Key $fhKey -From $f -To $t) }
        }
    }
    if ($reqs.Count -eq 0) { if (-not $Quiet) { Show-InfoBox -Text (Tr "Noch kein API-Schlüssel eingetragen (Einstellungen > Daten & Aktualisierung).") -Title "Datenquellen" }; return }
    $reqs = @(Select-ProviderUrls $reqs)
    Set-TransientStatus "Datenquellen werden getestet ..." 4
    Start-FetchJob -Urls @($reqs | ForEach-Object { $_.Url }) -MaxConcurrency 3 -Context @{ Reqs = $reqs; Quiet = [bool]$Quiet } -OnComplete {
        param($Box, $Ctx)
        $res = @()
        if ($null -eq $script:Config.ProviderCaps -or $script:Config.ProviderCaps -is [string]) { $script:Config.ProviderCaps = [PSCustomObject]@{} }
        foreach ($r in $Ctx.Reqs) {
            $j = $Box.Results[$r.Url]
            $err = Get-ProviderError $j
            $empty = (-not $err) -and ((@($j).Count -eq 0) -or ($r.Kind -eq "Calendar" -and @($j.earningsCalendar).Count -eq 0))
            $ok = (-not $err) -and -not $empty
            $det = if ($ok) { "" } elseif ($null -eq $j) { Tr "kein Zugriff (kostenpflichtig oder Schlüssel falsch)" } elseif ($empty) { Tr "leer" } else { $err }
            $res += [PSCustomObject]@{ Provider = $r.Provider; Kind = $r.Kind; Ok = $ok; Detail = $det }
            $script:Config.ProviderCaps | Add-Member -NotePropertyName ("{0}|{1}" -f $r.Provider, $r.Kind) -NotePropertyValue $ok -Force
        }
        Save-JsonState -Path $script:ConfigPath -Data $script:Config
        $script:LastProviderReport = Format-ProviderReport $res
        Write-WidgetLog ("Provider test:`r`n" + $script:LastProviderReport)
        if (-not $Ctx.Quiet -and -not $script:SmokeMode) {
            Show-HelpTextDialog -Title ("{0} - {1}" -f (Tr "Datenquellen"), $script:AppTitle) -Text ($script:LastProviderReport + "`r`n`r`n" + (Tr "Twelve Data (kostenlos): nur US-Börsen, 8 Anfragen pro Minute, 800 pro Tag. Finnhub (kostenlos): 60 pro Minute; Kennzahlen, Quartalszahlen und Analysten-Empfehlungen. Was hier '--' zeigt, nutzt das Widget nicht."))
        }
    }
}

function Request-ProviderAnalysis {
    # Finnhub data for the ticker analysis, cached per ticker and day
    param([string]$Sym)
    $key = Get-ProviderKey "Finnhub"
    $ps = ConvertTo-ProviderSymbol -Symbol $Sym -Provider "Finnhub"
    if (-not $key -or -not $ps) { return }
    $day = (Get-Date).ToString("yyyy-MM-dd")
    $from = (Get-Date).AddDays(-760).ToString("yyyy-MM-dd")
    $reqs = @()
    foreach ($k in @("Metric", "Earnings", "Calendar", "Recommendation", "PriceTarget")) {
        if (-not (Test-ProviderCap "Finnhub" $k)) { continue }
        if (Test-ProviderCacheFresh -Entry $script:ProvCache["$Sym|$k"] -Day $day) { continue }
        $reqs += [PSCustomObject]@{ Provider = "Finnhub"; Kind = $k; Url = (Get-ProviderRequestUrl -Provider "Finnhub" -Kind $k -Symbol $ps -Key $key -From $from -To $day) }
    }
    $reqs = @(Select-ProviderUrls $reqs)
    if ($reqs.Count -eq 0) { return }
    Start-FetchJob -Urls @($reqs | ForEach-Object { $_.Url }) -MaxConcurrency 3 -Context @{ Reqs = $reqs; Sym = $Sym; Day = $day } -OnComplete {
        param($Box, $Ctx)
        foreach ($r in $Ctx.Reqs) {
            $j = $Box.Results[$r.Url]
            if ($null -eq $j -or (Get-ProviderError $j)) { continue }
            $script:ProvCache[("{0}|{1}" -f $Ctx.Sym, $r.Kind)] = [PSCustomObject]@{ Day = $Ctx.Day; Data = $j }
        }
        # only tickers still in use stay in the cache
        $keep = New-Object System.Collections.Generic.HashSet[string]
        try { foreach ($t in @(Get-KnownTickers)) { [void]$keep.Add(([string]$t).ToUpper()) } } catch { }
        [void]$keep.Add([string]$Ctx.Sym)
        foreach ($k0 in @($script:ProvCache.Keys)) { if (-not $keep.Contains(([string]$k0 -split '\|')[0])) { [void]$script:ProvCache.Remove($k0) } }
        try { Save-JsonState -Path $script:ProvCachePath -Data $script:ProvCache } catch { }
        if ($null -ne $script:TaCtl -and $script:TaCtl.Sym -eq $Ctx.Sym) { Update-TickerAnalysis }
    }
}

function Get-ProviderData {
    param([string]$Sym, [string]$Kind)
    $e = $script:ProvCache["$Sym|$Kind"]
    if ($null -eq $e) { return $null }
    return $e.Data
}

function Test-SignalAlertTicker {
    param([string]$Sym)
    $mode = [string]$script:Config.SignalAlerts
    if ($mode -eq "Aus") { return $false }
    if ($script:Portfolio.ContainsKey($Sym)) { return $true }
    return ($mode -eq "Alle" -and @($script:Config.Watchlist | ForEach-Object { ([string]$_).ToUpper() }) -contains $Sym)
}

function Send-SignalChangeAlerts {
    param([string]$Sym, $Old, $New)
    if (-not (Test-SignalAlertTicker $Sym)) { return }
    $ch = @(Get-SignalChanges -Old $Old -New $New)
    if ($ch.Count -eq 0) { return }
    $msg = (@($ch | ForEach-Object { $_.Text }) -join "; ")
    Write-WidgetLog ("Signal change {0}: {1}" -f $Sym, $msg)
    if ($script:SmokeMode) { $script:LastSignalAlert = "$Sym|$msg"; return }
    [void](Send-WidgetNotification -Title ("Signal: {0}" -f $Sym) -Message ($msg + " - " + (Tr "Ticker-Analyse: Rechtsklick > TA")) -Kind "Info" -AllowPush $true)
}

function Request-DailySignals {
    # once a day in the background: daily bars of the depot (and the watchlist
    # with "Alle") so that signal changes are noticed without opening anything
    $mode = [string]$script:Config.SignalAlerts
    if ($mode -eq "Aus" -or $script:SmokeMode) { return }
    $syms = @($script:Portfolio.Keys | ForEach-Object { ([string]$_).ToUpper() })
    if ($mode -eq "Alle") { $syms += @($script:Config.Watchlist) }
    if ($syms.Count -gt 0) { Request-DailyBars -Symbols $syms }
}

function Get-TickerNote {
    param([string]$Ticker)
    $n = $script:Notes[([string]$Ticker).ToUpper()]
    if ($null -eq $n) { return "" }
    return [string]$n.Text
}

function Set-TickerNote {
    param([string]$Ticker, [string]$Text)
    $u = ([string]$Ticker).ToUpper()
    if (-not $u) { return }
    $t = ConvertTo-NoteText $Text
    if ($t) { $script:Notes[$u] = [PSCustomObject]@{ Text = $t; Updated = (Get-Date).ToString("yyyy-MM-dd HH:mm") } }
    else { [void]$script:Notes.Remove($u) }
    Save-JsonState -Path $script:NotesPath -Data $script:Notes
}

function Save-Profiles {
    Save-JsonState -Path $script:ProfilesPath -Data $script:Profiles
}

function Get-ProfileEntry {
    # Entry of a ticker; created (empty) when missing
    param([string]$Ticker)
    $u = ([string]$Ticker).ToUpper()
    if (-not $script:Profiles.ContainsKey($u)) {
        $script:Profiles[$u] = [PSCustomObject]@{ Sector = ""; Industry = ""; Country = ""; QuoteType = ""; Name = ""; FetchedAt = ""; ManualSector = ""; ManualCountry = "" }
    }
    return $script:Profiles[$u]
}

# Earnings / dividend dates (v4.2) from Yahoo quoteSummary, refreshed about
# once a day. Unknown numbers are stored as null (NaN is not valid JSON).
$script:EventsPath = Join-Path $script:DataDir "events.json"
$script:Events = @{}

function ConvertTo-EventNumber {
    param($V)
    if ($null -eq $V) { return [double]::NaN }
    try { return [double]$V } catch { return [double]::NaN }
}

$script:EventNumberFields = @("DividendRate", "DividendYield", "TrailingRate", "TargetMean", "TargetHigh", "TargetLow", "RecMean", "Analysts")
function New-EventEntry {
    param($V = $null)
    $e = [PSCustomObject]@{
        EarningsDate = ""; EarningsEnd = ""; ExDividendDate = ""; DividendDate = ""
        DividendRate = [double]::NaN; DividendYield = [double]::NaN; TrailingRate = [double]::NaN
        FetchedAt = ""; NotifiedEarnings = ""; NotifiedExDiv = ""
        TargetMean = [double]::NaN; TargetHigh = [double]::NaN; TargetLow = [double]::NaN; RecMean = [double]::NaN; Analysts = [double]::NaN; RecKey = ""
        Fund = $null
    }
    if ($null -ne $V) {
        # v5.1: fundamentals; entries from before are fetched again once
        if ($null -ne $V.PSObject.Properties["Fund"]) { $e.Fund = ConvertTo-StoredFund $V.Fund }
        foreach ($f in @("EarningsDate", "EarningsEnd", "ExDividendDate", "DividendDate", "FetchedAt", "NotifiedEarnings", "NotifiedExDiv", "RecKey")) { if ($null -ne $V.$f) { $e.$f = [string]$V.$f } }
        foreach ($f in $script:EventNumberFields) { $e.$f = ConvertTo-EventNumber $V.$f }
        # v4.9.5: entries from before the analyst data are fetched again once
        if ($null -eq $V.PSObject.Properties["RecKey"]) { $e.FetchedAt = "" }
        if ($null -eq $V.PSObject.Properties["Fund"]) { $e.FetchedAt = "" }
    }
    return $e
}

$rawEvents = Load-JsonState -Path $script:EventsPath -DefaultValue $null
if ($null -ne $rawEvents) {
    foreach ($prop in $rawEvents.PSObject.Properties) {
        if ($null -ne $prop.Value) { $script:Events[$prop.Name.ToUpper()] = New-EventEntry $prop.Value }
    }
}

function Save-Events {
    $out = @{}
    foreach ($k in @($script:Events.Keys)) {
        $e = $script:Events[$k]
        $o = [ordered]@{}
        foreach ($f in @("EarningsDate", "EarningsEnd", "ExDividendDate", "DividendDate", "FetchedAt", "NotifiedEarnings", "NotifiedExDiv", "RecKey")) { $o[$f] = [string]$e.$f }
        foreach ($f in $script:EventNumberFields) {
            $n = [double]$e.$f
            $o[$f] = if ([double]::IsNaN($n) -or [double]::IsInfinity($n)) { $null } else { $n }
        }
        $o["Fund"] = $e.Fund
        $out[$k] = [PSCustomObject]$o
    }
    Save-JsonState -Path $script:EventsPath -Data $out
}

function Set-EventEntry {
    # Stores parsed calendar data; the "notified" mark survives while the
    # earnings date stays the same
    param([string]$Ticker, $Cal)
    $u = ([string]$Ticker).ToUpper()
    $old = $script:Events[$u]
    $e = New-EventEntry
    if ($null -ne $Cal) {
        foreach ($f in @("EarningsDate", "EarningsEnd", "ExDividendDate", "DividendDate", "RecKey")) { $e.$f = [string]$Cal.$f }
        foreach ($f in $script:EventNumberFields) { $e.$f = ConvertTo-EventNumber $Cal.$f }
    } elseif ($null -ne $old) {
        $e = New-EventEntry $old
    }
    if ($null -ne $old -and [string]$old.NotifiedEarnings -and [string]$old.NotifiedEarnings -eq $e.EarningsDate) { $e.NotifiedEarnings = [string]$old.NotifiedEarnings }
    if ($null -ne $old -and [string]$old.NotifiedExDiv -and [string]$old.NotifiedExDiv -eq $e.ExDividendDate) { $e.NotifiedExDiv = [string]$old.NotifiedExDiv }
    if ($null -ne $old -and $null -ne $old.Fund) { $e.Fund = $old.Fund }
    $e.FetchedAt = (Get-Date).ToString("o")
    $script:Events[$u] = $e
}

# V7.0: the former single script is split into ui\*.ps1 parts. They are dot-sourced in order,
# so everything runs in this script's scope exactly as before.
# v7.1.1: load time per part goes to the log and to HEALTH. 13-Startup runs the
# message loop, so its load time is not measured; "window shown after" covers it.
$script:StartupParts = New-Object System.Collections.Generic.List[string]
Write-WidgetLog ("Startup: main script ready after {0} ms" -f $script:StartWatch.ElapsedMilliseconds)
foreach ($twPart in @("02-Data", "03-Theme", "04-ChartRender", "05-ChartViews", "05b-News", "06-MainWindow", "07-Events", "08-Analysis", "09-Dialogs", "10-Palette", "11-System", "12-Shell", "12b-Custom", "12c-Alerts", "12d-Depot", "12e-Overview", "13-Startup")) {
    $twPartStart = $script:StartWatch.ElapsedMilliseconds
    if ($twPart -eq "13-Startup") { Write-WidgetLog ("Startup: parts 02-12 loaded after {0} ms" -f $twPartStart) }
    . (Join-Path (Join-Path $script:ScriptDir "ui") "$twPart.ps1")
    if ($twPart -ne "13-Startup") {
        $twPartMs = $script:StartWatch.ElapsedMilliseconds - $twPartStart
        $script:StartupParts.Add(("{0} {1} ms" -f $twPart, $twPartMs))
        Write-WidgetLog ("Startup part {0}: {1} ms" -f $twPart, $twPartMs)
    }
}
if ($script:SmokeMode) { exit ([int]$script:SmokeExit) }
