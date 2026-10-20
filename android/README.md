# Klack Keyboard (Android)

> ## ⚠️ BUILT, NOT RUN ON A DEVICE
> This project was written on a Mac and `./gradlew assembleDebug` produces an APK. **No
> emulator or phone has run it yet**: key commit, sound playback and the enable/select flow are
> all unverified. If you install it, please open an issue with what you saw — that is how it
> becomes tested.

A minimal Android keyboard that makes mechanical-keyboard click sounds on every key,
using the same generated sound packs as the macOS Klack app.

## Why it is a keyboard, not a background app

On macOS, Klack is a menu-bar app that listens to every keystroke system-wide and plays a
click. Android does not allow that. No app can observe what you type into another app's
keyboard: there is no global key hook, and input events are delivered only to the focused
app and the current Input Method Editor (IME). The accessibility API is the only thing that
comes close, and it is not allowed to be used for this (it does not expose keystrokes from
other keyboards, and using it for non-accessibility purposes gets apps removed from Play).
So the only honest way to ship "Klack on Android" is for Klack to **be** the keyboard you type
on. That is what this is: a plain QWERTY IME where each key press plays a Klack down click
and each release plays an up click. It is a different product from the Mac app, by
necessity, and it only sounds when you type with *this* keyboard.

## What is in the box

- `app/src/main/java/com/klack/keyboard/`
  - `KlackInputMethodService.kt`: the IME. Commits text, handles backspace (with
    key-repeat), enter (editor action or newline), auto-shift at sentence start.
  - `KeyboardView.kt`: the hand-drawn QWERTY layout (numbers row, letters, shift with
    double-tap caps lock, backspace, `?123` symbols page, space, enter). Multi-touch aware,
    with per-finger down/up so rollover typing sounds right.
  - `ClickSoundEngine.kt`: SoundPool player that mirrors `Sources/Klack/AudioEngine.swift`:
    random down/up variants, dedicated space pair, melodic walk through variants during a
    burst, per-hit gain that drops as typing speeds up, and raised-cosine ducking of
    still-ringing tails. Follows the device **media** volume times the in-app volume.
  - `SettingsActivity.kt`: sound pack picker, volume slider, preview, a test text field,
    and the two buttons that matter: *Enable* (system keyboard list) and *Select* (keyboard
    picker). Settings live in SharedPreferences and the IME picks changes up live.
- `app/src/main/assets/profiles/<pack>/*.wav`: the sound packs, copied in at build time
  (see below). Never sampled audio: every file is synthesised by
  `../Resources/generate_sounds.py`.

## Build

Requirements (what was installed on the dev Mac, all via Homebrew, no sudo):

- JDK 17: `brew install openjdk@17`
- Android command-line tools: `brew install --cask android-commandlinetools`
- Then one platform and build-tools:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0"
```

If your Mac's HTTPS goes through a TLS-intercepting proxy (for example Zscaler on a managed corporate laptop), Java will
refuse Gradle's downloads with `PKIX path building failed`. Fix once by adding the proxy's root
CA to a copy of the JDK truststore and pointing Gradle at it:

```bash
JH=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
security find-certificate -a -p -c "Zscaler Root CA" /Library/Keychains/System.keychain > ~/.gradle/zscaler-root.pem
cp $JH/lib/security/cacerts ~/.gradle/cacerts-with-zscaler.jks
$JH/bin/keytool -importcert -noprompt -alias zscaler-root -file ~/.gradle/zscaler-root.pem -keystore ~/.gradle/cacerts-with-zscaler.jks -storepass changeit
printf 'systemProp.javax.net.ssl.trustStore=%s/.gradle/cacerts-with-zscaler.jks\nsystemProp.javax.net.ssl.trustStorePassword=changeit\n' "$HOME" >> ~/.gradle/gradle.properties
export JAVA_OPTS="-Djavax.net.ssl.trustStore=$HOME/.gradle/cacerts-with-zscaler.jks -Djavax.net.ssl.trustStorePassword=changeit"  # for the wrapper's own download
```

`local.properties` points `sdk.dir` at Homebrew's default SDK root
(`/opt/homebrew/share/android-commandlinetools`). Edit it if your SDK lives elsewhere, or set
`ANDROID_HOME`.

Sound packs are not in git (same as the Mac app). Generate them once, then build:

```bash
cd android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
./gradlew generateSoundPacks   # runs ../Resources/generate_sounds.py (pure-stdlib python3)
./gradlew assembleDebug
```

`assembleDebug` runs `syncSoundPacks` automatically, which copies `../Resources/profiles/*/*.wav`
into `app/src/main/assets/profiles/`. The APK lands at
`app/build/outputs/apk/debug/app-debug.apk`. Gradle 8.9 downloads itself the first time via
the wrapper.

## Install the debug APK

With a phone in developer mode and USB debugging on:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Or sideload: copy `app-debug.apk` to the phone, open it from Files, allow "install unknown
apps" for that app when asked. It is a debug build, so Play Protect will warn; that is expected.

## Enable and select the keyboard (the part people get stuck on)

Android never activates a new keyboard on its own. Two steps, both reachable from the
Klack Keyboard app's screen:

1. **Enable**: tap *1. Enable Klack Keyboard*. The system "On-screen keyboard" / "Manage
   keyboards" list opens. Turn on *Klack Keyboard* and accept the standard warning
   (every third-party keyboard gets the "may collect what you type" dialog; Klack has no
   internet permission and sends nothing anywhere).
2. **Select**: tap *2. Select Klack Keyboard*. The keyboard picker appears; choose
   *Klack Keyboard*. On most phones you can also switch later via the small keyboard icon in
   the navigation bar while any text field is focused, or by long-pressing the space bar on
   Gboard.

The status line at the top of the app tells you which step you are on. Then tap the test
field at the bottom and type.

## Limitations

- Only sounds when typing on *this* keyboard. By design of the platform, not a bug.
- MVP layout: English QWERTY only, no suggestions, autocorrect, long-press accents, emoji,
  voice, clipboard or theming. Enough to type correctly into any field.
- Uses the **media** volume stream, so a phone on silent/vibrate still clicks if media volume
  is up. Gboard-style key sounds use the system stream instead; this was a deliberate choice so
  the volume users consciously control is the one that applies.
- Not tested on a device or emulator at the time of writing (no system image was downloaded).
  See the top-level handover notes for what was and was not verified.
