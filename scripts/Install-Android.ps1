[CmdletBinding()]
param(
    [string]$Serial,
    [switch]$ConfirmDeviceReady
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $ConfirmDeviceReady) {
    throw 'Phone installation requires -ConfirmDeviceReady after USB debugging is enabled and the target phone is confirmed.'
}
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$AndroidRoot = if ($env:SEP780_ANDROID_TOOL_ROOT) {
    [IO.Path]::GetFullPath($env:SEP780_ANDROID_TOOL_ROOT)
} else {
    Join-Path $env:LOCALAPPDATA 'SEP780RobotCar\android'
}
$Adb = Join-Path $AndroidRoot 'sdk\platform-tools\adb.exe'
$Apk = Join-Path $ProjectRoot 'artifacts/local/SEP780-Robot-Car-debug.apk'
if (-not (Test-Path -LiteralPath $Adb)) { throw 'ADB missing. Run scripts/Setup-Android.ps1 first.' }
if (-not (Test-Path -LiteralPath $Apk)) { throw 'APK missing. Run scripts/Build-Android.ps1 first.' }
$selector = if ($Serial) { @('-s', $Serial) } else { @() }
& $Adb @selector install -r $Apk
if ($LASTEXITCODE -ne 0) { throw 'APK installation failed.' }
Write-Host 'APK installed. The app has not connected to or moved the robot.'
