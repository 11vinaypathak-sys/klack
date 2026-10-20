using System.Text.Json;
using System.Text.Json.Serialization;

namespace Klack;

/// <summary>Persisted in %APPDATA%\Klack\settings.json.</summary>
public sealed class Settings
{
    public bool Enabled { get; set; } = true;
    public string Pack { get; set; } = "clicky";
    /// <summary>0.0 .. 1.0</summary>
    public float Volume { get; set; } = 0.7f;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
    };

    public static string Directory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Klack");

    public static string FilePath => Path.Combine(Directory, "settings.json");

    public static Settings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var loaded = JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath), JsonOptions);
                if (loaded != null)
                {
                    loaded.Volume = Math.Clamp(loaded.Volume, 0f, 1f);
                    return loaded;
                }
            }
        }
        catch
        {
            // A corrupt file just means defaults; it is rewritten on the next change.
        }
        return new Settings();
    }

    public void Save()
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, JsonOptions));
        }
        catch
        {
            // Settings are a convenience; never crash the app over them.
        }
    }
}
