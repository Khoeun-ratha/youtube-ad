@echo off
echo ========================================================
echo    Launching Ad-Free YouTube app
echo    (no backend needed - the app talks to youtube.com)
echo ========================================================
cd /d "%~dp0mobile_app"
flutter run
pause
