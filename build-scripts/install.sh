#!/bin/bash
# Builds Klack and installs it into Klack.app, then relaunches it.
#
# This exists because the app bundle and the built binary are two separate
# things: `swift build` only ever writes to .build/release/Klack, so without
# this step you can fix a bug, build cleanly, and still be running a months-old
# binary out of Klack.app with no indication anything is stale.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/Klack.app"
BIN="$ROOT/.build/release/Klack"

echo "==> Building"
swift build -c release --product Klack

if [ ! -f "$BIN" ]; then
  echo "!! build produced no binary at $BIN" >&2
  exit 1
fi

echo "==> Quitting running instance"
# Must quit before overwriting: replacing the binary underneath a running
# process leaves the old code in memory, so the "new" build appears to change
# nothing until the next manual relaunch.
pkill -x Klack 2>/dev/null || true
sleep 1

echo "==> Installing into bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Klack"

# Sound packs and fonts live in the repo, not in the build output, so they're
# copied separately -- a binary-only install silently loses new sound packs.
# The synthesized packs are generated, not committed, so a fresh clone has
# none. Build them on first run -- generate_sounds.py is pure stdlib Python.
if [ ! -d "$ROOT/Resources/profiles" ]; then
  echo "==> Generating synthesized sound packs (first run)"
  python3 "$ROOT/Resources/generate_sounds.py"
fi
if [ -d "$ROOT/Resources/profiles" ]; then
  rsync -a --delete "$ROOT/Resources/profiles/" "$APP/Contents/Resources/profiles/"
fi
if [ -d "$ROOT/Resources/fonts" ]; then
  rsync -a --delete "$ROOT/Resources/fonts/" "$APP/Contents/Resources/fonts/"
fi

# Signing identity.
#
# Ad-hoc signing (`-`) derives the identity from a hash of the binary, so every
# rebuild mints a *new* identity and macOS drops the Input Monitoring grant --
# the app then sits in the menu bar looking healthy and hearing nothing.
# Signing with a real certificate keys the grant to the certificate instead,
# so it survives rebuilds. See build-scripts/signing-setup.md.
SIGN_IDENTITY="Klack Local Dev"
# By default an ad-hoc signature's designated requirement is the binary's own
# cdhash, so every rebuild produces a requirement nothing previously granted
# can satisfy -- which is why Input Monitoring kept evaporating and the app sat
# in the menu bar looking healthy while hearing nothing. Pinning the
# requirement to the bundle identifier instead keeps it stable across builds.
REQUIREMENT='designated => identifier "com.vinaypathak.klack"'

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "==> Signing with a certificate (stable identity)"
    codesign --force --deep --sign "$SIGN_IDENTITY" -r="$REQUIREMENT" "$APP"
else
    echo "==> Signing ad-hoc with a pinned identifier (stable identity)"
    codesign --force --deep --sign - -r="$REQUIREMENT" "$APP"
fi

# Assert it, rather than trusting that the flag did what we think. A signature
# that silently falls back to a cdhash requirement is the exact failure this
# is here to prevent, and it is invisible until the permission dies again.
ACTUAL_REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | grep '^designated' || true)"
if [[ "$ACTUAL_REQUIREMENT" == *"identifier \"com.vinaypathak.klack\""* ]]; then
    echo "    requirement: $ACTUAL_REQUIREMENT"
else
    echo "==> !! Requirement is NOT pinned -- Input Monitoring will break again."
    echo "==> !! Got: ${ACTUAL_REQUIREMENT:-<none>}"
    exit 1
fi

echo "==> Verifying"
# Runs the installed binary, not the build-output one, so a bad copy or a
# missing resource is caught here rather than after launch.
KLACK_SELFTEST=1 "$APP/Contents/MacOS/Klack" || {
  echo "!! self-test failed -- the installed app has broken audio" >&2
  exit 1
}
KLACK_DUCKTEST=1 "$APP/Contents/MacOS/Klack" || {
  echo "!! ducking test failed -- fast typing will stack into mush" >&2
  exit 1
}
KLACK_CRASHTEST=1 "$APP/Contents/MacOS/Klack" || {
  echo "!! crash-survival test failed -- an audio device change could kill the app" >&2
  exit 1
}

echo "==> Launching"
open "$APP"
echo "Done. Installed binary: $(date -r "$APP/Contents/MacOS/Klack" '+%Y-%m-%d %H:%M')"
