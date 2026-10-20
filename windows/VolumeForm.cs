namespace Klack;

/// <summary>Tiny always-on-top window with a single volume slider.</summary>
public sealed class VolumeForm : Form
{
    public VolumeForm(float initial, Action<float> onChange)
    {
        Text = "Klack Volume";
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        StartPosition = FormStartPosition.CenterScreen;
        TopMost = true;
        ShowInTaskbar = false;
        ClientSize = new Size(300, 70);
        MaximizeBox = false;
        MinimizeBox = false;

        var label = new Label { AutoSize = true, Location = new Point(12, 10) };
        var slider = new TrackBar
        {
            Minimum = 0, Maximum = 100, TickFrequency = 10,
            Value = (int)Math.Round(Math.Clamp(initial, 0f, 1f) * 100),
            Location = new Point(8, 28), Width = 284,
        };
        label.Text = $"Volume: {slider.Value}%";
        slider.ValueChanged += (_, _) =>
        {
            label.Text = $"Volume: {slider.Value}%";
            onChange(slider.Value / 100f);
        };
        Controls.Add(label);
        Controls.Add(slider);

        KeyPreview = true;
        KeyDown += (_, e) => { if (e.KeyCode == Keys.Escape) Close(); };
    }
}
