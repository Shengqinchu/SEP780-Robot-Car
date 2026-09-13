[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')

if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64') {
    throw 'This setup script currently supports x64 Windows and x64 Linux only.'
}
if (-not $OnWindows -and -not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Linux)) {
    throw 'This setup script currently supports x64 Windows and x64 Linux only.'
}
New-Item -ItemType Directory -Force -Path $ToolRoot, $CliDirectory, $LibraryDirectory | Out-Null
$download = if ($OnWindows) { $Toolchain.cli.windows_x64 } else { $Toolchain.cli.linux_x64 }
$archiveName = ([uri]$download.url).Segments[-1]
$archive = Join-Path $ToolRoot $archiveName

if (-not (Test-Path -LiteralPath $ArduinoCli)) {
    if (-not (Test-Path -LiteralPath $archive)) {
        Write-Host "Downloading Arduino CLI $($Toolchain.cli.version)..."
        Invoke-WebRequest -Uri $download.url -OutFile $archive -TimeoutSec 180
    }
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $download.sha256) {
        throw "CLI archive checksum mismatch. Do not execute: $archive"
    }
    if ($OnWindows) {
        Expand-Archive -LiteralPath $archive -DestinationPath $CliDirectory -Force
    } else {
        & tar -xzf $archive -C $CliDirectory
        if ($LASTEXITCODE -ne 0) { throw 'CLI archive extraction failed.' }
    }
}
Assert-Toolchain

# Use the original bundled library versions, not incompatible latest replacements.
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($zip in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'vendor/freenove/Libraries') -Filter '*.zip') {
    $reader = [IO.Compression.ZipFile]::OpenRead($zip.FullName)
    try {
        foreach ($entry in $reader.Entries) {
            if ($entry.FullName -match '(^[/\\])|(^|[/\\])\.\.([/\\]|$)|:') {
                throw "Unsafe archive entry: $($entry.FullName)"
            }
        }
    } finally {
        $reader.Dispose()
    }
    Expand-Archive -LiteralPath $zip.FullName -DestinationPath $LibraryDirectory -Force
}

Invoke-Arduino -Arguments @('core', 'update-index')
Invoke-Arduino -Arguments @('core', 'install', $Toolchain.core)
Invoke-Arduino -Arguments @('lib', 'install', $Toolchain.servo_library)
Invoke-Arduino -Arguments @('core', 'list')
Invoke-Arduino -Arguments @('lib', 'list')
Write-Host "Toolchain ready: $ArduinoCli"
Write-Host 'No board was flashed. No global Arduino configuration was changed.'
