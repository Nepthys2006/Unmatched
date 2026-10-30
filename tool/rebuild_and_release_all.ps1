# Rebuilds the Windows app, the Android APK and the web builds, then packages them into
# "Unmatched Fan Made" and the Netlify site folder.
#
#   .\rebuild_and_release_all.ps1                 everything
#   .\rebuild_and_release_all.ps1 -SkipAndroid    Windows + web only (the existing APK is kept)
#   .\rebuild_and_release_all.ps1 -SkipBackup     do not copy the previous release to
#                                                 %USERPROFILE%\release_backup_latest first
#
# Close the game before running: the release folder is cleared and refilled.
param(
    [switch]$SkipAndroid,
    [switch]$SkipBackup
)
$ErrorActionPreference = 'Stop'
$ProjectDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched\unmatched_game'
$FanMadeDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched Fan Made'
$LandingPlayDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched\landing\play'

Set-Location $ProjectDir

# A native command that fails does not stop a PowerShell script by itself; without this check a
# failed build would carry on and package the previous build's files as if they were new.
function Assert-Ok($what) {
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit code $LASTEXITCODE). Nothing from it was packaged." }
}

if (-not (Test-Path "$ProjectDir\.env")) { throw ".env is missing in $ProjectDir (the builds read the Supabase keys from it)." }

# The packaging step deletes the release folder's files. A running game holds them open, which
# leaves the folder half-deleted and the running game without its images.
$running = Get-Process -Name Unmatched -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and $_.Path.StartsWith($FanMadeDir, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
}
if ($running) { throw "Close the game first: Unmatched.exe is running from $($running[0].Path)." }

if (-not $SkipBackup) {
    $backup = Join-Path $env:USERPROFILE 'release_backup_latest'
    Write-Host "=== 0. Backing up the current release to $backup ===" -ForegroundColor Yellow
    robocopy $FanMadeDir $backup /MIR /XD 'How to Download' /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Backup failed (robocopy exit code $LASTEXITCODE)." }
    $global:LASTEXITCODE = 0
}

Write-Host "`n=== 1. Cleaning older versions from Unmatched Fan Made ===" -ForegroundColor Yellow
if (-not $SkipAndroid -and (Test-Path "$FanMadeDir\Unmatched-Android.apk")) { Remove-Item "$FanMadeDir\Unmatched-Android.apk" -Force }
if (Test-Path "$FanMadeDir\Unmatched-Windows.zip") { Remove-Item "$FanMadeDir\Unmatched-Windows.zip" -Force }
if (Test-Path "$FanMadeDir\Unmatched-Web.zip") { Remove-Item "$FanMadeDir\Unmatched-Web.zip" -Force }
if (Test-Path "$FanMadeDir\Web") { Remove-Item -Path "$FanMadeDir\Web\*" -Recurse -Force }
if (Test-Path "$FanMadeDir\Windows") { Remove-Item -Path "$FanMadeDir\Windows\*" -Recurse -Force }

Write-Host "`n=== 2. Building Windows Desktop (Release) ===" -ForegroundColor Green
flutter build windows --release --dart-define-from-file=.env
Assert-Ok 'Windows build'

if ($SkipAndroid) {
    Write-Host "`n=== 3. Android APK skipped (-SkipAndroid); the existing APK is kept ===" -ForegroundColor DarkYellow
} else {
    Write-Host "`n=== 3. Building Android APK (Release with full icons) ===" -ForegroundColor Green
    flutter build apk --release --no-tree-shake-icons --dart-define-from-file=.env
    Assert-Ok 'Android build'
}

Write-Host "`n=== 4. Building Web (Release with full icons) ===" -ForegroundColor Green
flutter build web --release --no-web-resources-cdn --no-tree-shake-icons --dart-define-from-file=.env
Assert-Ok 'Web build'
python tool/bundle_webapp.py
Assert-Ok 'bundle_webapp.py'

Write-Host "`n=== 5. Packaging fresh releases to Unmatched Fan Made ===" -ForegroundColor Cyan
# APK
if (-not $SkipAndroid) {
    Copy-Item -Path "$ProjectDir\build\app\outputs\flutter-apk\app-release.apk" -Destination "$FanMadeDir\Unmatched-Android.apk" -Force
}

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
Assert-Ok 'Netlify web build'
# build_site.py DELETES build\site and rebuilds it from ..\landing plus build\web_play.
# Edit the website in the landing folder, never in build\site.
python tool/build_site.py
Assert-Ok 'build_site.py'
if (Test-Path $LandingPlayDir) {
    Copy-Item -Path "$ProjectDir\build\web_play\*" -Destination $LandingPlayDir -Recurse -Force
}

Write-Host "`nSizes:" -ForegroundColor Cyan
Get-ChildItem $FanMadeDir -File | ForEach-Object { '  {0,-26} {1,7:N1} MB' -f $_.Name, ($_.Length / 1MB) }

Write-Host "`nAll release builds completed and packaged cleanly!" -ForegroundColor Cyan
