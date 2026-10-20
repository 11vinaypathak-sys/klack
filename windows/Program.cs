using System.Threading;

namespace Klack;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        // One instance only: a second copy would double every click.
        using var mutex = new Mutex(initiallyOwned: true, "Local\\Klack.Windows.SingleInstance", out bool isFirst);
        if (!isFirst)
        {
            MessageBox.Show("Klack is already running. Look for it in the system tray.",
                "Klack", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        ApplicationConfiguration.Initialize();
        using var app = new TrayApp();
        Application.Run(app);
    }
}
