#!/usr/bin/env bash
# Generates the sound packs and publishes a self-contained win-x64 single-file
# build to windows/publish/. Works from macOS/Linux (cross-compile) or Windows
# (Git Bash / WSL). Requires the .NET 8 SDK and Python 3.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Generating sound packs (../Resources/profiles)"
python3 ../Resources/generate_sounds.py

echo "==> Publishing win-x64 self-contained single file"
dotnet publish Klack.Windows.csproj -c Release -r win-x64 -o publish

echo "==> Output:"
ls -1 publish
echo
echo "Done. Copy the whole publish/ folder (Klack.exe + profiles/) to a Windows machine."
