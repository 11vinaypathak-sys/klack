# Klack for Windows (MVP)

A minimal Windows system-tray port of [Klack](../README.md): mechanical-keyboard
click sounds on every keystroke, using the same sound packs as the macOS app.

> ## ⚠️ UNTESTED ON WINDOWS
> This project was written and cross-compiled on **macOS** (`dotnet publish -r win-x64`).
> The resulting `Klack.exe` has **never been executed on a Windows machine**.
> It builds and publishes cleanly, and the code follows documented Win32 / NAudio
> behaviour, but no runtime behaviour (hook, audio, tray menu) has been observed.
> Treat it as a first build for a tester, not a release. See
> [What a tester should check first](#what-a-tester-should-check-first).

## What it does

- Lives in the system tray (no window). Right-click the icon for the menu.
- **Enabled** toggle (double-clicking the icon toggles it too).
- **Sound Pack** submenu listing every folder found in `profiles\` next to the exe.
- **Volume**: four presets plus a `Custom…` slider window.
- **Launch at startup**: writes/removes an `HKCU\...\CurrentVersion\Run` entry.
- **Quit**.
- Settings (pack, volume, enabled) persist in `%APPDATA%\Klack\settings.json`.

### Behaviour mirrored from the Mac app

- Global low-level keyboard hook (`WH_KEYBOARD_LL`). **Listen-only**: every event
  is passed on unchanged, nothing is blocked, nothing is logged or stored. The
  hook only reports "down/up" and "was it the space bar".
- Space uses the `click_space_down/up` pair; every other key uses the down/up variants.
- Auto-repeat is ignored: a held key plays once, not machine-gun style.
- All WAVs are preloaded; up to 24 overlapping voices.
- Down variants are **walked up and down** (not random) once typing becomes a
  run, so bursts have a contour instead of sounding like gravel.
- Per-hit gain **drops up to 28 %** as typing speed rises; a darker (high-shelf
  cut) copy of the down samples takes over in a fast burst; each new keydown
  fades the still-ringing tails with a release that shortens as you speed up.
- Output: WASAPI shared mode, 20 ms buffer, with a WaveOut fallback.

One deliberate difference: the Mac build treats the first two keystrokes after
launch as "fast" (flow = 1). This port treats them as isolated (flow = 0).

## Sound packs

Only the generated / project-owned packs are used. No audio is downloaded or
sampled from the internet. Packs are plain folders of 44.1 kHz mono 16-bit WAVs:

```
profiles/<name>/click_down_1..6.wav  click_up_1..3.wav
                click_space_down.wav click_space_up.wav
```

They are produced by `../Resources/generate_sounds.py` (pure-stdlib Python) and
copied into the publish output by an MSBuild target in the `.csproj`. The exe
looks for `profiles\` **next to itself**, so always ship the two together.

## Build

Requirements: **.NET SDK 8.0** (tested with 8.0.426), **Python 3**.
Building the `net8.0-windows` target from macOS/Linux works because the project
sets `EnableWindowsTargeting`.

One-shot (generates packs, then publishes to `windows/publish/`):

```bash
./build.sh          # macOS / Linux / Git Bash
.\build.ps1         # Windows PowerShell
```

Manual:

```bash
python3 ../Resources/generate_sounds.py
dotnet build  Klack.Windows.csproj -c Release
dotnet publish Klack.Windows.csproj -c Release -r win-x64 -o publish
```

Output: `publish/Klack.exe` (self-contained single file, ~66 MB compressed, no
.NET runtime install needed) and `publish/profiles/`.

## Run

Copy the whole `publish\` folder to a Windows 10/11 PC and double-click
`Klack.exe`. A keycap icon appears in the tray (it may be hidden under the `^`
overflow arrow). Start typing.

### SmartScreen warning

The exe is **not code-signed**, so Windows SmartScreen will show
"Windows protected your PC". Click **More info → Run anyway**. This is expected
for any unsigned open-source build; signing requires a paid certificate.

Some antivirus products flag *any* program that installs a global keyboard hook.
The hook here is listen-only (see `KeyboardHook.cs`, ~100 lines), but expect
the question.

## What a tester should check first

1. **It starts**: icon appears in the tray; no crash dialog; `%APPDATA%\Klack\settings.json` is created after changing anything.
2. **Sound plays** on keydown and keyup in any app (Notepad, browser, terminal). If silent, check the tray balloon for an audio or "no packs" error and confirm `profiles\` sits beside the exe.
3. **Keys are not swallowed or delayed**: typing in Notepad is unaffected with Klack running; latency between press and click feels immediate (<30 ms).
4. **Holding a key** plays once (no repeat machine-gun); **space** sounds different from letters.
5. **Fast typing** gets slightly quieter and tighter rather than louder/mushier.
6. **Sound Pack** submenu lists all folders and switching is instant; **Volume** presets and slider work; **Enabled** off mutes without quitting.
7. **Launch at startup** adds/removes `Klack` under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (check with `regedit` or `reg query`).
8. **Second launch** shows "already running" instead of a second icon.
9. **Quit** removes the icon and the process exits (`Task Manager`).
10. Output-device change (plug in headphones) — the WASAPI stream may need a restart; note what happens.

## Files

| File | Purpose |
|---|---|
| `Klack.Windows.csproj` | Project; publish settings; copies `profiles/` on publish |
| `Program.cs` | Entry point, single-instance mutex |
| `TrayApp.cs` | Tray icon, context menu, drawn icon, wiring |
| `KeyboardHook.cs` | `WH_KEYBOARD_LL` listen-only hook with repeat filter |
| `ClickEngine.cs` | NAudio WASAPI playback, voice pool, variant walk, burst shaping |
| `Settings.cs` | JSON settings in `%APPDATA%\Klack\` |
| `StartupRegistry.cs` | HKCU Run key |
| `VolumeForm.cs` | Small slider window |
| `build.sh` / `build.ps1` | Generate packs + publish |

License: MIT, same as the main project.
