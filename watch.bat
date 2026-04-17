@echo off
REM Re-run build_hot_reload.bat whenever any source\**\*.odin file changes.
REM Uses PowerShell's built-in FileSystemWatcher - no install needed.
REM
REM Workflow:
REM   1. Terminal A: build_hot_reload.bat run   (launches game)
REM   2. Terminal B: watch.bat                  (auto-rebuilds on save)

cd /d "%~dp0"

call build_hot_reload.bat
echo [watch] ready - waiting for changes in source\

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$w = New-Object System.IO.FileSystemWatcher '%cd%\source','*.odin';" ^
  "$w.IncludeSubdirectories = $true;" ^
  "$w.EnableRaisingEvents = $true;" ^
  "while ($true) {" ^
  "  $r = $w.WaitForChanged('Changed,Created,Renamed', 1000);" ^
  "  if (-not $r.TimedOut) {" ^
  "    Write-Host '[watch] change detected, rebuilding...';" ^
  "    & cmd /c '%~dp0build_hot_reload.bat';" ^
  "    Start-Sleep -Milliseconds 300;" ^
  "  }" ^
  "}"
