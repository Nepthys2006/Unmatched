@echo off
setlocal
cd /d "%~dp0\.."

if not exist ".env" (
    echo Error: .env file not found.
    pause
    exit /b 1
)

echo ===================================================
echo   Unmatched Build Tool (Supabase Auto-Injected)
echo ===================================================
echo 1. Build Windows Desktop (Release)
echo 2. Build Android APK (Release)
echo 3. Build Web (Release)
echo 4. Build ALL (Windows + APK + Web)
echo ===================================================
set /p choice="Select an option (1-4): "

if "%choice%"=="1" goto build_windows
if "%choice%"=="2" goto build_apk
if "%choice%"=="3" goto build_web
if "%choice%"=="4" goto build_all

echo Invalid option. Exiting.
exit /b 1

:build_windows
echo Building Windows Release...
flutter build windows --release --dart-define-from-file=.env
goto finish

:build_apk
echo Building Android APK Release...
flutter build apk --release --dart-define-from-file=.env
goto finish

:build_web
echo Building Web Release...
flutter build web --release --no-web-resources-cdn --dart-define-from-file=.env
python tool/bundle_webapp.py
goto finish

:build_all
echo Building ALL targets...
flutter build windows --release --dart-define-from-file=.env
flutter build apk --release --dart-define-from-file=.env
flutter build web --release --no-web-resources-cdn --dart-define-from-file=.env
python tool/bundle_webapp.py
goto finish

:finish
echo.
echo ===================================================
echo   Build finished!
echo ===================================================
pause
