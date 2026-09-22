[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Lock = Get-Content -LiteralPath (Join-Path $ProjectRoot 'android-toolchain.lock.json') -Raw | ConvertFrom-Json

if ($env:OS -ne 'Windows_NT' -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64') {
    throw 'The pinned Android setup currently supports x64 Windows only.'
}

$javaVersion = (& java -version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $javaVersion -notmatch 'version "(1[7-9]|2[0-9])') {
    throw 'JDK 17 or newer is required. Install a JDK and put java on PATH.'
}

$AndroidRoot = if ($env:SEP780_ANDROID_TOOL_ROOT) {
    [IO.Path]::GetFullPath($env:SEP780_ANDROID_TOOL_ROOT)
} else {
    Join-Path $env:LOCALAPPDATA 'SEP780RobotCar\android'
}
$DownloadRoot = Join-Path (Split-Path $AndroidRoot -Parent) 'android-downloads'
$SdkRoot = Join-Path $AndroidRoot 'sdk'
$GradleHome = Join-Path $AndroidRoot ("gradle-" + $Lock.gradle.version)
$CommandLineHome = Join-Path $SdkRoot ("cmdline-tools\" + $Lock.command_line_tools.version)
$SdkManager = Join-Path $CommandLineHome 'bin\sdkmanager.bat'
New-Item -ItemType Directory -Force -Path $AndroidRoot, $DownloadRoot, $SdkRoot | Out-Null

function Get-VerifiedArchive {
    param([Parameter(Mandatory)]$Package)
    $name = ([uri]$Package.url).Segments[-1]
    $path = Join-Path $DownloadRoot $name
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "Downloading $name..."
        Invoke-WebRequest -Uri $Package.url -OutFile $path -TimeoutSec 600
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Package.sha256) {
        throw "Archive checksum mismatch. Do not execute: $path"
    }
    return $path
}

if (-not (Test-Path -LiteralPath (Join-Path $GradleHome 'bin\gradle.bat'))) {
    $archive = Get-VerifiedArchive -Package $Lock.gradle
    Expand-Archive -LiteralPath $archive -DestinationPath $AndroidRoot -Force
}

if (-not (Test-Path -LiteralPath $SdkManager)) {
    $archive = Get-VerifiedArchive -Package $Lock.command_line_tools.windows_x64
    $stage = Join-Path $AndroidRoot 'cmdline-tools-stage'
    $rootPrefix = [IO.Path]::GetFullPath($AndroidRoot).TrimEnd('\') + '\'
    $stageFull = [IO.Path]::GetFullPath($stage)
    if (-not $stageFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unsafe Android command-line tools staging path.'
    }
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage, $CommandLineHome | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $stage -Force
    Copy-Item -Path (Join-Path $stage 'cmdline-tools\*') -Destination $CommandLineHome -Recurse -Force
    Remove-Item -LiteralPath $stage -Recurse -Force
}

$env:ANDROID_HOME = $SdkRoot
$env:ANDROID_SDK_ROOT = $SdkRoot
$licenses = 1..20 | ForEach-Object { 'y' }
$licenses | & $SdkManager "--sdk_root=$SdkRoot" --licenses | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Android SDK license setup failed.' }

& $SdkManager "--sdk_root=$SdkRoot" @($Lock.sdk.packages) | Out-Host
if ($LASTEXITCODE -ne 0) { throw 'Android SDK package installation failed.' }

Write-Host "Android SDK ready: $SdkRoot"
Write-Host "Gradle ready: $GradleHome"
Write-Host 'No phone was accessed and no APK was installed.'
