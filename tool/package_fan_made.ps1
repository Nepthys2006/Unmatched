$ProjectDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched\unmatched_game'
$FanMadeDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched Fan Made'
$LandingPlayDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched\landing\play'

Write-Host "1. Syncing Web to landing/play..."
if (Test-Path $LandingPlayDir) {
    Copy-Item -Path "$ProjectDir\build\web\*" -Destination $LandingPlayDir -Recurse -Force
}

Write-Host "2. Copying Android APK to Unmatched Fan Made..."
Copy-Item -Path "$ProjectDir\build\app\outputs\flutter-apk\app-release.apk" -Destination "$FanMadeDir\Unmatched-Android.apk" -Force

Write-Host "3. Syncing Web release to Unmatched Fan Made..."
if (Test-Path "$FanMadeDir\Web") {
    Remove-Item -Path "$FanMadeDir\Web\*" -Recurse -Force
} else {
    New-Item -ItemType Directory -Path "$FanMadeDir\Web" -Force | Out-Null
}
Copy-Item -Path "$ProjectDir\build\web\*" -Destination "$FanMadeDir\Web" -Recurse -Force
if (Test-Path "$FanMadeDir\Unmatched-Web.zip") { Remove-Item "$FanMadeDir\Unmatched-Web.zip" -Force }
Compress-Archive -Path "$FanMadeDir\Web\*" -DestinationPath "$FanMadeDir\Unmatched-Web.zip" -Force

Write-Host "4. Syncing Windows release to Unmatched Fan Made..."
if (Test-Path "$FanMadeDir\Windows") {
    Remove-Item -Path "$FanMadeDir\Windows\*" -Recurse -Force
} else {
    New-Item -ItemType Directory -Path "$FanMadeDir\Windows" -Force | Out-Null
}
Copy-Item -Path "$ProjectDir\build\windows\x64\runner\Release\*" -Destination "$FanMadeDir\Windows" -Recurse -Force
if (Test-Path "$FanMadeDir\Unmatched-Windows.zip") { Remove-Item "$FanMadeDir\Unmatched-Windows.zip" -Force }
Compress-Archive -Path "$FanMadeDir\Windows\*" -DestinationPath "$FanMadeDir\Unmatched-Windows.zip" -Force

Write-Host "Packaging complete!"

