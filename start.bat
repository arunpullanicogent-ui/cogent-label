@echo off
cd /d "%~dp0"
echo Starting Cogent Label Printer... keep this window open while you use the app.
start "" http://localhost:3000
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause
