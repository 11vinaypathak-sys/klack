# Windows equivalent of build.sh. Run from PowerShell in the windows\ folder.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "==> Generating sound packs (..\Resources\profiles)"
python ..\Resources\generate_sounds.py

Write-Host "==> Publishing win-x64 self-contained single file"
dotnet publish Klack.Windows.csproj -c Release -r win-x64 -o publish

Write-Host "==> Output:"
Get-ChildItem publish
Write-Host "`nDone. Run publish\Klack.exe."
