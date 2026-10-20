using System.Drawing.Drawing2D;

namespace Klack;

/// <summary>Tray icon, context menu, and the glue between hook and engine.</summary>
public sealed class TrayApp : ApplicationContext
{
    private static readonly (string Label, float Value)[] VolumePresets =
    {
        ("Quiet (25%)", 0.25f), ("Medium (50%)", 0.5f), ("Loud (75%)", 0.75f), ("Max (100%)", 1.0f),
    };

    private readonly Settings _settings;
    private readonly ClickEngine _engine;
    private readonly KeyboardHook _hook;
    private readonly NotifyIcon _tray;
    private readonly ContextMenuStrip _menu = new();
    private readonly ToolStripMenuItem _enabledItem;
    private readonly ToolStripMenuItem _packMenu;
    private readonly ToolStripMenuItem _volumeMenu;
    private readonly ToolStripMenuItem _startupItem;
    private readonly Icon _iconOn;
    private readonly Icon _iconOff;
    private VolumeForm? _volumeForm;

    public TrayApp()
    {
        _settings = Settings.Load();
        _engine = new ClickEngine(_settings.Volume);

        // Pick a pack that actually exists; fall back to the first available.
        var packs = ClickEngine.AvailablePacks();
        if (packs.Count > 0 && !packs.Contains(_settings.Pack, StringComparer.OrdinalIgnoreCase))
            _settings.Pack = packs[0];
        bool packOk = packs.Count > 0 && _engine.LoadPack(_settings.Pack);

        _iconOn = MakeIcon(enabled: true);
        _iconOff = MakeIcon(enabled: false);

        _enabledItem = new ToolStripMenuItem("Enabled") { Checked = _settings.Enabled, CheckOnClick = true };
        _enabledItem.CheckedChanged += (_, _) => SetEnabled(_enabledItem.Checked);

        _packMenu = new ToolStripMenuItem("Sound Pack");
        _volumeMenu = new ToolStripMenuItem("Volume");
        _startupItem = new ToolStripMenuItem("Launch at startup") { CheckOnClick = true };
        _startupItem.CheckedChanged += (_, _) => StartupRegistry.SetEnabled(_startupItem.Checked);

        var quit = new ToolStripMenuItem("Quit Klack");
        quit.Click += (_, _) => ExitThread();

        _menu.Items.Add(_enabledItem);
        _menu.Items.Add(_packMenu);
        _menu.Items.Add(_volumeMenu);
        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(_startupItem);
        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add(quit);
        _menu.Opening += (_, _) => RefreshMenu();

        _tray = new NotifyIcon
        {
            Text = "Klack",
            Icon = _settings.Enabled ? _iconOn : _iconOff,
            ContextMenuStrip = _menu,
            Visible = true,
        };
        _tray.DoubleClick += (_, _) => _enabledItem.Checked = !_enabledItem.Checked;

        _hook = new KeyboardHook();
        _hook.KeyDown += isSpace => { if (_settings.Enabled) _engine.KeyDown(isSpace); };
        _hook.KeyUp += isSpace => { if (_settings.Enabled) _engine.KeyUp(isSpace); };
        try
        {
            _hook.Install();
        }
        catch (Exception ex)
        {
            _tray.ShowBalloonTip(5000, "Klack", "Could not install keyboard hook: " + ex.Message, ToolTipIcon.Error);
        }

        if (!packOk)
            _tray.ShowBalloonTip(6000, "Klack",
                "No sound packs found. Expected folders in:\n" + ClickEngine.ProfilesRoot, ToolTipIcon.Warning);
        else if (_engine.LastError != null)
            _tray.ShowBalloonTip(6000, "Klack", "Audio output failed: " + _engine.LastError, ToolTipIcon.Error);

        RefreshMenu();
    }

    private void SetEnabled(bool enabled)
    {
        _settings.Enabled = enabled;
        _settings.Save();
        _tray.Icon = enabled ? _iconOn : _iconOff;
        _tray.Text = enabled ? "Klack" : "Klack (muted)";
    }

    private void SetPack(string name)
    {
        if (_engine.LoadPack(name))
        {
            _settings.Pack = name;
            _settings.Save();
        }
        else
        {
            _tray.ShowBalloonTip(4000, "Klack", $"Pack '{name}' has no usable samples.", ToolTipIcon.Warning);
        }
    }

    private void SetVolume(float v)
    {
        _settings.Volume = Math.Clamp(v, 0f, 1f);
        _engine.Volume = _settings.Volume;
        _settings.Save();
    }

    private void RefreshMenu()
    {
        _enabledItem.Checked = _settings.Enabled;
        _startupItem.Checked = StartupRegistry.IsEnabled();

        _packMenu.DropDownItems.Clear();
        var packs = ClickEngine.AvailablePacks();
        if (packs.Count == 0)
        {
            _packMenu.DropDownItems.Add(new ToolStripMenuItem("(no packs in profiles\\)") { Enabled = false });
        }
        foreach (var pack in packs)
        {
            var item = new ToolStripMenuItem(PrettyName(pack))
            {
                Checked = string.Equals(pack, _settings.Pack, StringComparison.OrdinalIgnoreCase),
                Tag = pack,
            };
            item.Click += (s, _) => SetPack((string)((ToolStripMenuItem)s!).Tag!);
            _packMenu.DropDownItems.Add(item);
        }

        _volumeMenu.DropDownItems.Clear();
        foreach (var (label, value) in VolumePresets)
        {
            var item = new ToolStripMenuItem(label)
            {
                Checked = Math.Abs(_settings.Volume - value) < 0.01f,
                Tag = value,
            };
            item.Click += (s, _) => SetVolume((float)((ToolStripMenuItem)s!).Tag!);
            _volumeMenu.DropDownItems.Add(item);
        }
        _volumeMenu.DropDownItems.Add(new ToolStripSeparator());
        var custom = new ToolStripMenuItem($"Custom…  ({(int)Math.Round(_settings.Volume * 100)}%)");
        custom.Click += (_, _) => ShowVolumeForm();
        _volumeMenu.DropDownItems.Add(custom);
    }

    private void ShowVolumeForm()
    {
        if (_volumeForm == null || _volumeForm.IsDisposed)
        {
            _volumeForm = new VolumeForm(_settings.Volume, SetVolume);
        }
        _volumeForm.Show();
        _volumeForm.Activate();
    }

    private static string PrettyName(string folder)
    {
        var words = folder.Split('_', StringSplitOptions.RemoveEmptyEntries)
            .Select(w => char.ToUpperInvariant(w[0]) + w[1..]);
        return string.Join(' ', words);
    }

    /// <summary>A simple drawn keycap so no binary icon asset is needed.</summary>
    private static Icon MakeIcon(bool enabled)
    {
        using var bmp = new Bitmap(32, 32);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.Transparent);
            var body = enabled ? Color.FromArgb(240, 240, 240) : Color.FromArgb(120, 120, 120);
            var edge = enabled ? Color.FromArgb(40, 40, 40) : Color.FromArgb(80, 80, 80);
            using var path = RoundedRect(new Rectangle(3, 3, 26, 26), 6);
            using var fill = new SolidBrush(body);
            using var pen = new Pen(edge, 2f);
            g.FillPath(fill, path);
            g.DrawPath(pen, path);
            using var inner = RoundedRect(new Rectangle(8, 7, 16, 14), 3);
            using var innerPen = new Pen(edge, 1.5f);
            g.DrawPath(innerPen, inner);
            if (!enabled)
            {
                using var slash = new Pen(Color.FromArgb(200, 60, 60), 3f);
                g.DrawLine(slash, 6, 26, 26, 6);
            }
        }
        IntPtr h = bmp.GetHicon();
        // Clone so the icon owns its handle and we can release the GDI one.
        using var tmp = Icon.FromHandle(h);
        var icon = (Icon)tmp.Clone();
        DestroyIcon(h);
        return icon;
    }

    private static GraphicsPath RoundedRect(Rectangle r, int radius)
    {
        var p = new GraphicsPath();
        int d = radius * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    protected override void ExitThreadCore()
    {
        _hook.Dispose();
        _tray.Visible = false;
        _tray.Dispose();
        _engine.Dispose();
        _volumeForm?.Dispose();
        _iconOn.Dispose();
        _iconOff.Dispose();
        base.ExitThreadCore();
    }
}
