[CmdletBinding()]
param([switch]$SkipTests)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Lock = Get-Content -LiteralPath (Join-Path $ProjectRoot 'android-toolchain.lock.json') -Raw | ConvertFrom-Json
$AndroidRoot = if ($env:SEP780_ANDROID_TOOL_ROOT) {
    [IO.Path]::GetFullPath($env:SEP780_ANDROID_TOOL_ROOT)
} else {
    Join-Path $env:LOCALAPPDATA 'SEP780RobotCar\android'
}
$env:ANDROID_HOME = Join-Path $AndroidRoot 'sdk'
$env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
$Gradle = Join-Path $AndroidRoot ("gradle-$($Lock.gradle.version)\bin\gradle.bat")
if (-not (Test-Path -LiteralPath $Gradle)) {
    throw 'Android toolchain missing. Run scripts/Setup-Android.ps1 first.'
}

# Gradle's Windows test worker cannot reliably load classes from this course archive's
# non-ASCII path. Build an exact disposable source copy under the pinned ASCII tool root.
$SourceProject = Join-Path $ProjectRoot 'mobile/android'
$AndroidProject = Join-Path $AndroidRoot 'project-work'
$rootPrefix = [IO.Path]::GetFullPath($AndroidRoot).TrimEnd('\') + '\'
$projectFull = [IO.Path]::GetFullPath($AndroidProject)
if (-not $projectFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Unsafe Android staging path.'
}
if (Test-Path -LiteralPath $AndroidProject) {
    Remove-Item -LiteralPath $AndroidProject -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $AndroidProject | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $SourceProject -Recurse -File) {
    if ($file.FullName -match '[\\/](build|\.gradle)[\\/]' -or $file.Name -eq 'local.properties') { continue }
    $relative = [IO.Path]::GetRelativePath($SourceProject, $file.FullName)
    $target = Join-Path $AndroidProject $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
}

$tasks = @(':app:clean')
if (-not $SkipTests) { $tasks += ':app:testDebugUnitTest' }
$tasks += ':app:lintDebug'
$tasks += ':app:assembleDebug'
& $Gradle @tasks --project-dir $AndroidProject --no-daemon --console=plain
if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }

$source = Join-Path $AndroidProject 'app/build/outputs/apk/debug/app-debug.apk'
$Aapt = Join-Path $env:ANDROID_HOME 'build-tools/35.0.0/aapt.exe'
if (-not (Test-Path -LiteralPath $Aapt)) { throw 'Pinned Android Asset Packaging Tool is missing.' }
$badging = (& $Aapt dump badging $source 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $badging -notmatch "package: name='io\.github\.shengqinchu\.sep780'" -or
        $badging -notmatch "sdkVersion:'26'" -or $badging -notmatch "targetSdkVersion:'35'") {
    throw 'Built APK identity or SDK bounds failed verification.'
}
$permissions = (& $Aapt dump permissions $source 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'Built APK permissions could not be inspected.' }
foreach ($permission in @('BLUETOOTH_SCAN', 'BLUETOOTH_CONNECT', 'RECORD_AUDIO')) {
    if ($permissions -notmatch [regex]::Escape("android.permission.$permission")) {
        throw "Built APK is missing $permission."
    }
}
$artifactRoot = Join-Path $ProjectRoot 'artifacts/local'
$target = Join-Path $artifactRoot 'SEP780-Robot-Car-debug.apk'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
Copy-Item -LiteralPath $source -Destination $target -Force
$hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "APK: $target"
Write-Host "SHA-256: $hash"
Write-Host 'The APK was compiled and tested locally; this command does not install or Bluetooth-test it.'
