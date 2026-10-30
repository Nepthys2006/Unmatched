$ErrorActionPreference = 'Stop'
$ProjectDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched\unmatched_game'
$FanMadeDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched Fan Made'
$LandingPlayDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched\landing\play'

Set-Location $ProjectDir

Write-Host "=== 1. Cleaning older versions from Unmatched Fan Made ===" -ForegroundColor Yellow
if (Test-Path "$FanMadeDir\Unmatched-Android.apk") { Remove-Item "$FanMadeDir\Unmatched-Android.apk" -Force }
if (Test-Path "$FanMadeDir\Unmatched-Windows.zip") { Remove-Item "$FanMadeDir\Unmatched-Windows.zip" -Force }
if (Test-Path "$FanMadeDir\Unmatched-Web.zip") { Remove-Item "$FanMadeDir\Unmatched-Web.zip" -Force }
if (Test-Path "$FanMadeDir\Web") { Remove-Item -Path "$FanMadeDir\Web\*" -Recurse -Force }
if (Test-Path "$FanMadeDir\Windows") { Remove-Item -Path "$FanMadeDir\Windows\*" -Recurse -Force }

Write-Host "`n=== 2. Building Windows Desktop (Release) ===" -ForegroundColor Green
flutter build windows --release --dart-define-from-file=.env

Write-Host "`n=== 3. Building Android APK (Release with full icons) ===" -ForegroundColor Green
flutter build apk --release --no-tree-shake-icons --dart-define-from-file=.env

Write-Host "`n=== 4. Building Web (Release with full icons) ===" -ForegroundColor Green
flutter build web --release --no-web-resources-cdn --no-tree-shake-icons --dart-define-from-file=.env
python tool/bundle_webapp.py

Write-Host "`n=== 5. Packaging fresh releases to Unmatched Fan Made ===" -ForegroundColor Cyan
# APK
Copy-Item -Path "$ProjectDir\build\app\outputs\flutter-apk\app-release.apk" -Destination "$FanMadeDir\Unmatched-Android.apk" -Force

# Web
if (-not (Test-Path "$FanMadeDir\Web")) { New-Item -ItemType Directory -Path "$FanMadeDir\Web" -Force | Out-Null }
Copy-Item -Path "$ProjectDir\build\web\*" -Destination "$FanMadeDir\Web" -Recurse -Force
Compress-Archive -Path "$FanMadeDir\Web\*" -DestinationPath "$FanMadeDir\Unmatched-Web.zip" -Force

# Windows
if (-not (Test-Path "$FanMadeDir\Windows")) { New-Item -ItemType Directory -Path "$FanMadeDir\Windows" -Force | Out-Null }
Copy-Item -Path "$ProjectDir\build\windows\x64\runner\Release\*" -Destination "$FanMadeDir\Windows" -Recurse -Force
Compress-Archive -Path "$FanMadeDir\Windows\*" -DestinationPath "$FanMadeDir\Unmatched-Windows.zip" -Force

Write-Host "`n=== 6. Building Netlify Web Site (/play/ with full icons) ===" -ForegroundColor Green
flutter build web --release --no-tree-shake-icons --base-href /play/ --dart-define-from-file=.env --output build/web_play
python tool/build_site.py
if (Test-Path $LandingPlayDir) {
    Copy-Item -Path "$ProjectDir\build\web_play\*" -Destination $LandingPlayDir -Recurse -Force
}

Write-Host "`nAll release builds completed and packaged cleanly!" -ForegroundColor Cyan

