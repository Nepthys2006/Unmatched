# Copies the finished builds into "Unmatched Fan Made" and the Netlify site folder.
# Run rebuild_and_release_all.ps1 first; this script builds nothing.
#
# Close the game before running: the Windows folder is cleared and refilled.
$ErrorActionPreference = 'Stop'
$ProjectDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched\unmatched_game'
$FanMadeDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched Fan Made'
$LandingPlayDir = 'c:\Users\daryl\OneDrive\Desktop\Exploits\Unmatched\landing\play'
$WindowsBuild = "$ProjectDir\build\windows\x64\runner\Release"

# A running game holds its files open: clearing the folder would then half-delete it and leave
# the running game without its images. Stop here instead.
$running = Get-Process -Name Unmatched -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and $_.Path.StartsWith($FanMadeDir, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
}
if ($running) { throw "Close the game first: Unmatched.exe is running from $($running[0].Path)." }

foreach ($need in @("$ProjectDir\build\web\index.html", "$WindowsBuild\Unmatched.exe")) {
    if (-not (Test-Path $need)) { throw "Missing $need - run rebuild_and_release_all.ps1 first." }
}

Write-Host "1. Syncing the /play/ web build to landing/play..."
# The website needs the build made with --base-href /play/ (build\web_play). The plain web build
# (build\web, base href /) would break the site's /play/ page.
if (Test-Path $LandingPlayDir) {
    if (Test-Path "$ProjectDir\build\web_play\index.html") {
        Copy-Item -Path "$ProjectDir\build\web_play\*" -Destination $LandingPlayDir -Recurse -Force
    } else {
        Write-Warning "build\web_play not found: landing/play left unchanged (run rebuild_and_release_all.ps1)."
    }
}

Write-Host "2. Copying Android APK to Unmatched Fan Made..."
$apk = "$ProjectDir\build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apk) {
    Copy-Item -Path $apk -Destination "$FanMadeDir\Unmatched-Android.apk" -Force
} else {
    Write-Warning "No APK build found: the existing Unmatched-Android.apk was left as it is."
}

# A zip is built under a temporary name and swapped in only once it is complete.
function New-ReleaseZip($folder, $zipPath) {
    # Compress-Archive only accepts a destination that ends in .zip.
    $tmp = Join-Path (Split-Path $zipPath) ('new_' + (Split-Path $zipPath -Leaf))
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    Compress-Archive -Path "$folder\*" -DestinationPath $tmp -Force
    Move-Item $tmp $zipPath -Force
}

Write-Host "3. Syncing Web release to Unmatched Fan Made..."
if (Test-Path "$FanMadeDir\Web") {
    Remove-Item -Path "$FanMadeDir\Web\*" -Recurse -Force
} else {
    New-Item -ItemType Directory -Path "$FanMadeDir\Web" -Force | Out-Null
}
Copy-Item -Path "$ProjectDir\build\web\*" -Destination "$FanMadeDir\Web" -Recurse -Force
New-ReleaseZip "$FanMadeDir\Web" "$FanMadeDir\Unmatched-Web.zip"

Write-Host "4. Syncing Windows release to Unmatched Fan Made..."
if (Test-Path "$FanMadeDir\Windows") {
    Remove-Item -Path "$FanMadeDir\Windows\*" -Recurse -Force
} else {
    New-Item -ItemType Directory -Path "$FanMadeDir\Windows" -Force | Out-Null
}
Copy-Item -Path "$WindowsBuild\*" -Destination "$FanMadeDir\Windows" -Recurse -Force
New-ReleaseZip "$FanMadeDir\Windows" "$FanMadeDir\Unmatched-Windows.zip"

Write-Host "5. Checking the copies are complete..."
foreach ($pair in @(@($WindowsBuild, "$FanMadeDir\Windows"), @("$ProjectDir\build\web", "$FanMadeDir\Web"))) {
    $want = (Get-ChildItem $pair[0] -Recurse -File | Measure-Object).Count
    $have = (Get-ChildItem $pair[1] -Recurse -File | Measure-Object).Count
    if ($want -ne $have) { throw "$($pair[1]) has $have files but the build has $want." }
}

Write-Host "Packaging complete!"
