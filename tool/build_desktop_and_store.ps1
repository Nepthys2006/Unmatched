$ErrorActionPreference = 'Stop'
$ProjectDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched\unmatched_game'
$FanMadeDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched Fan Made'

Set-Location $ProjectDir

Write-Host "=== Building Windows Desktop (Release) ===" -ForegroundColor Green
flutter build windows --release --dart-define-from-file=.env

Write-Host "`n=== Storing Windows Desktop to '$FanMadeDir\Windows' ===" -ForegroundColor Cyan
if (Test-Path "$FanMadeDir\Windows") {
    Remove-Item -Path "$FanMadeDir\Windows\*" -Recurse -Force
} else {
    New-Item -ItemType Directory -Path "$FanMadeDir\Windows" -Force | Out-Null
}

Copy-Item -Path "$ProjectDir\build\windows\x64\runner\Release\*" -Destination "$FanMadeDir\Windows" -Recurse -Force

Write-Host "`n=== Creating fresh Unmatched-Windows.zip ===" -ForegroundColor Cyan
if (Test-Path "$FanMadeDir\Unmatched-Windows.zip") {
    Remove-Item "$FanMadeDir\Unmatched-Windows.zip" -Force
}
Compress-Archive -Path "$FanMadeDir\Windows\*" -DestinationPath "$FanMadeDir\Unmatched-Windows.zip" -Force

# Also update the copy in How to Download if the folder exists
if (Test-Path "$FanMadeDir\How to Download") {
    Copy-Item -Path "$FanMadeDir\Unmatched-Windows.zip" -Destination "$FanMadeDir\How to Download\Unmatched-Windows.zip" -Force
}

Write-Host "`nDesktop build and packaging completed successfully!" -ForegroundColor Green
Get-ChildItem -Path "$FanMadeDir\Unmatched-Windows.zip" | Select-Object Name, Length, LastWriteTime
Get-ChildItem -Path "$FanMadeDir\Windows" | Select-Object Name, Length, LastWriteTime

