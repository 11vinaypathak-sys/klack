using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace Klack;

/// <summary>
/// Low-latency click playback. Mirrors the macOS ClickAudioEngine behaviour:
///  - all WAVs of a pack are preloaded into memory,
///  - a small voice pool lets clicks overlap instead of cutting each other off,
///  - down variants are walked up-and-down (not random) once typing becomes a
///    run, so a burst has a contour instead of sounding like gravel,
///  - per-hit gain drops slightly as typing speed rises (up to -28%),
///  - a darker copy of the down samples takes over in a fast burst,
///  - each new keydown fades ("ducks") the tails still ringing, with a release
///    that shortens as typing speeds up.
/// </summary>
public sealed class ClickEngine : IDisposable
{
    public const int SampleRate = 44100;
    private const int Channels = 2;
    private const int PoolSize = 24;

    // Flow (typing speed) shaping -- same constants as the Mac app.
    private const int SpeedWindowSize = 6;
    private const double FastTypingIntervalThreshold = 0.18; // seconds between keys
    private const double VeryFastIntervalFloor = 0.08;
    private const double DuckReleaseSlow = 0.13;
    private const double DuckReleaseFast = 0.045;
    private const float BurstExtraSoftness = 0.35f;

    private readonly object _lock = new();
    private readonly WaveFormat _format = WaveFormat.CreateIeeeFloatWaveFormat(SampleRate, Channels);
    private readonly MixingSampleProvider _mixer;
    private readonly VolumeSampleProvider _master;
    private IWavePlayer? _output;

    private readonly List<Voice> _active = new();
    private readonly List<double> _recentKeyDownTimes = new();
    private readonly Random _random = new();

    private float[][] _down = Array.Empty<float[]>();
    private float[][] _softDown = Array.Empty<float[]>();
    private float[][] _up = Array.Empty<float[]>();
    private float[]? _spaceDown;
    private float[]? _softSpaceDown;
    private float[]? _spaceUp;

    private int _melodyIndex;
    private int _melodyStep = 1;

    public string? LastError { get; private set; }

    public float Volume
    {
        get => _master.Volume;
        set => _master.Volume = Math.Clamp(value, 0f, 1f);
    }

    public ClickEngine(float volume)
    {
        _mixer = new MixingSampleProvider(_format) { ReadFully = true };
        _master = new VolumeSampleProvider(_mixer) { Volume = Math.Clamp(volume, 0f, 1f) };
        Start();
    }

    private void Start()
    {
        try
        {
            // WASAPI shared mode, short buffer. Shared mode resamples to the
            // device mix format for us if it is not 44.1k.
            var wasapi = new WasapiOut(AudioClientShareMode.Shared, useEventSync: true, latency: 20);
            wasapi.Init(_master);
            wasapi.Play();
            _output = wasapi;
            LastError = null;
        }
        catch (Exception ex)
        {
            LastError = "WASAPI: " + ex.Message;
            try
            {
                var fallback = new WaveOutEvent { DesiredLatency = 60, NumberOfBuffers = 3 };
                fallback.Init(_master);
                fallback.Play();
                _output = fallback;
                LastError = null;
            }
            catch (Exception ex2)
            {
                LastError += " | WaveOut: " + ex2.Message;
                _output = null;
            }
        }
    }

    // ---- Pack loading -------------------------------------------------------

    public static string ProfilesRoot =>
        Path.Combine(AppContext.BaseDirectory, "profiles");

    public static IReadOnlyList<string> AvailablePacks()
    {
        try
        {
            if (!Directory.Exists(ProfilesRoot)) return Array.Empty<string>();
            return Directory.GetDirectories(ProfilesRoot)
                .Where(d => File.Exists(Path.Combine(d, "click_down_1.wav")))
                .Select(Path.GetFileName)
                .Where(n => n != null)
                .Select(n => n!)
                .OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }
        catch { return Array.Empty<string>(); }
    }

    /// <summary>Returns false if the pack folder has no usable samples.</summary>
    public bool LoadPack(string name)
    {
        var dir = Path.Combine(ProfilesRoot, name);
        var down = new List<float[]>();
        var up = new List<float[]>();
        for (int i = 1; i <= 16; i++)
        {
            var b = LoadWav(Path.Combine(dir, $"click_down_{i}.wav"));
            if (b == null) break;
            down.Add(b);
        }
        for (int i = 1; i <= 16; i++)
        {
            var b = LoadWav(Path.Combine(dir, $"click_up_{i}.wav"));
            if (b == null) break;
            up.Add(b);
        }
        var spaceDown = LoadWav(Path.Combine(dir, "click_space_down.wav"));
        var spaceUp = LoadWav(Path.Combine(dir, "click_space_up.wav"));
        if (down.Count == 0) return false;

        var soft = down.Select(b => Soften(b, BurstExtraSoftness)).ToArray();

        lock (_lock)
        {
            _down = down.ToArray();
            _softDown = soft;
            _up = up.ToArray();
            _spaceDown = spaceDown;
            _softSpaceDown = spaceDown != null ? Soften(spaceDown, BurstExtraSoftness) : null;
            _spaceUp = spaceUp;
            _melodyIndex = 0;
            _melodyStep = 1;
        }
        return true;
    }

    /// <summary>Decode a WAV to mono float at the engine sample rate.</summary>
    private static float[]? LoadWav(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            using var reader = new AudioFileReader(path); // float output
            ISampleProvider src = reader;
            if (src.WaveFormat.Channels > 1) src = new StereoToMonoSampleProvider(src) { LeftVolume = 0.5f, RightVolume = 0.5f };
            if (src.WaveFormat.SampleRate != SampleRate) src = new WdlResamplingSampleProvider(src, SampleRate);

            var list = new List<float>(4096);
            var buf = new float[4096];
            int n;
            while ((n = src.Read(buf, 0, buf.Length)) > 0)
                list.AddRange(buf.Take(n));
            return list.Count > 0 ? list.ToArray() : null;
        }
        catch { return null; }
    }

    /// <summary>
    /// High-shelf cut (2 kHz corner, two one-pole stages), same as the Mac
    /// app's soften(): the click keeps its body and loses some of its edge.
    /// No make-up gain, deliberately.
    /// </summary>
    private static float[] Soften(float[] input, float amount)
    {
        var output = new float[input.Length];
        float coeff = 1f - MathF.Exp(-2f * MathF.PI * 2000f / SampleRate);
        float keepHighs = 1f - amount;
        float low1 = 0, low2 = 0;
        for (int i = 0; i < input.Length; i++)
        {
            float x = input[i];
            low1 += coeff * (x - low1);
            low2 += coeff * (low1 - low2);
            output[i] = low2 + (x - low2) * keepHighs;
        }
        return output;
    }

    // ---- Triggering -----------------------------------------------------------

    /// <summary>0 = isolated keystroke, 1 = fast burst.</summary>
    private float RecordKeyDownAndComputeFlow()
    {
        double now = Environment.TickCount64 / 1000.0;
        _recentKeyDownTimes.Add(now);
        if (_recentKeyDownTimes.Count > SpeedWindowSize)
            _recentKeyDownTimes.RemoveRange(0, _recentKeyDownTimes.Count - SpeedWindowSize);
        if (_recentKeyDownTimes.Count < 3) return 0f;

        double sum = 0;
        for (int i = 1; i < _recentKeyDownTimes.Count; i++)
            sum += _recentKeyDownTimes[i] - _recentKeyDownTimes[i - 1];
        double avg = sum / (_recentKeyDownTimes.Count - 1);
        if (avg >= FastTypingIntervalThreshold) return 0f;

        double progress = (FastTypingIntervalThreshold - avg) / (FastTypingIntervalThreshold - VeryFastIntervalFloor);
        return (float)Math.Clamp(progress, 0.0, 1.0);
    }

    private static float BurstGain(float flow) => 1f - 0.28f * Math.Clamp(flow, 0f, 1f);

    private static double ReleaseFor(float flow) =>
        DuckReleaseSlow + (DuckReleaseFast - DuckReleaseSlow) * flow;

    public void KeyDown(bool isSpace)
    {
        lock (_lock)
        {
            float flow = RecordKeyDownAndComputeFlow();
            float gain = BurstGain(flow);
            double release = ReleaseFor(flow);
            bool inBurst = flow > 0.5f;

            float[]? sample;
            if (isSpace)
            {
                sample = (inBurst ? _softSpaceDown : _spaceDown) ?? _spaceDown;
                // No dedicated space sample in this pack: fall through to a normal click.
                sample ??= NextDownVariant(inBurst ? _softDown : _down, melodic: flow > 0.35f);
            }
            else
            {
                var source = (inBurst && _softDown.Length > 0) ? _softDown : _down;
                sample = NextDownVariant(source, melodic: flow > 0.35f);
            }
            if (sample == null) return;

            Play(sample, gain, ducksOthers: true, release);
        }
    }

    public void KeyUp(bool isSpace)
    {
        lock (_lock)
        {
            float[]? sample = isSpace && _spaceUp != null
                ? _spaceUp
                : (_up.Length > 0 ? _up[_random.Next(_up.Length)] : null);
            if (sample == null) return;
            Play(sample, 1f, ducksOthers: false, DuckReleaseSlow);
        }
    }

    /// <summary>Walks the variants up and down instead of picking at random.</summary>
    private float[]? NextDownVariant(float[][] buffers, bool melodic)
    {
        if (buffers.Length == 0) return null;
        if (!melodic || buffers.Length == 1) return buffers[_random.Next(buffers.Length)];
        _melodyIndex += _melodyStep;
        if (_melodyIndex >= buffers.Length - 1) { _melodyIndex = buffers.Length - 1; _melodyStep = -1; }
        else if (_melodyIndex <= 0) { _melodyIndex = 0; _melodyStep = 1; }
        return buffers[_melodyIndex];
    }

    private void Play(float[] sample, float gain, bool ducksOthers, double release)
    {
        if (_output == null) return;

        // Drop voices that have finished on their own.
        _active.RemoveAll(v => v.Finished);

        if (ducksOthers)
            foreach (var v in _active) v.BeginFade(release);

        // Hard cap on polyphony: recycle the oldest voice if the pool is full.
        while (_active.Count >= PoolSize)
        {
            _active[0].Kill();
            _active.RemoveAt(0);
        }

        var voice = new Voice(sample, Math.Clamp(gain, 0f, 2f), SampleRate, Channels);
        _active.Add(voice);
        _mixer.AddMixerInput(voice);
    }

    public void Dispose()
    {
        try { _output?.Stop(); } catch { }
        _output?.Dispose();
        _output = null;
    }

    // ---- Voice ------------------------------------------------------------------

    /// <summary>
    /// One playing sample: mono source rendered to stereo at a fixed gain, with
    /// an optional raised-cosine fade to silence (the "duck") triggered by a
    /// later keydown. The mixer drops it automatically once Read returns 0.
    /// </summary>
    private sealed class Voice : ISampleProvider
    {
        private readonly float[] _data;
        private readonly float _gain;
        private readonly int _channels;
        private int _pos;

        // Fade state (written from the key thread, read on the audio thread;
        // tearing here is harmless -- at worst one buffer of slightly wrong gain).
        private volatile bool _fading;
        private double _fadeSamples;
        private double _fadeElapsed;
        private volatile bool _killed;

        public WaveFormat WaveFormat { get; }
        public bool Finished => _killed || _pos >= _data.Length;

        public Voice(float[] data, float gain, int sampleRate, int channels)
        {
            _data = data;
            _gain = gain;
            _channels = channels;
            WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(sampleRate, channels);
        }

        public void BeginFade(double seconds)
        {
            if (_fading || Finished) return;
            _fadeSamples = Math.Max(1, seconds * WaveFormat.SampleRate);
            _fadeElapsed = 0;
            _fading = true;
        }

        public void Kill() => _killed = true;

        public int Read(float[] buffer, int offset, int count)
        {
            if (_killed) return 0;
            int frames = count / _channels;
            int written = 0;
            for (int f = 0; f < frames; f++)
            {
                if (_pos >= _data.Length) break;
                float g = _gain;
                if (_fading)
                {
                    double progress = Math.Min(1.0, _fadeElapsed / _fadeSamples);
                    g *= (float)(0.5 * (1 + Math.Cos(Math.PI * progress)));
                    _fadeElapsed++;
                    if (progress >= 1.0) { _killed = true; break; }
                }
                float s = _data[_pos++] * g;
                for (int c = 0; c < _channels; c++) buffer[offset + written++] = s;
            }
            return written;
        }
    }
}
