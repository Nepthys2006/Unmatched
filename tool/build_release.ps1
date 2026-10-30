<#
.SYNOPSIS
  Builds Unmatched release targets with Supabase credentials baked in.

.PARAMETER Target
  The build target: 'windows', 'apk', 'web', or 'all' (default: 'windows').
#>
param(
  [ValidateSet('windows', 'apk', 'web', 'all')]
  [string]$Target = 'windows'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
Set-Location $ProjectDir

if (-not (Test-Path ".env")) {
  Write-Error "Missing .env file in $ProjectDir. Please create .env with SUPABASE_URL and SUPABASE_KEY."
  exit 1
}

Write-Host "Building target: $Target with Supabase credentials from .env..." -ForegroundColor Cyan

if ($Target -eq 'windows' -or $Target -eq 'all') {
  Write-Host "`n=== Building Windows Desktop (Release) ===" -ForegroundColor Green
  flutter build windows --release --dart-define-from-file=.env
  Write-Host "Windows build ready at: build\windows\x64\runner\Release\Unmatched.exe" -ForegroundColor Green
}

if ($Target -eq 'apk' -or $Target -eq 'all') {
  Write-Host "`n=== Building Android APK (Release) ===" -ForegroundColor Green
  flutter build apk --release --no-tree-shake-icons --dart-define-from-file=.env
  Write-Host "Android APK ready at: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
}

if ($Target -eq 'web' -or $Target -eq 'all') {
  Write-Host "`n=== Building Web (Release) ===" -ForegroundColor Green
  flutter build web --release --no-web-resources-cdn --no-tree-shake-icons --dart-define-from-file=.env
  python tool/bundle_webapp.py
  Write-Host "Web build ready at: build\web\" -ForegroundColor Green
}

Write-Host "`nBuild complete!" -ForegroundColor Cyan
