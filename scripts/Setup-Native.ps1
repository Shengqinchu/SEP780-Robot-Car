[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')
$lock = Get-Content -LiteralPath (Join-Path $ProjectRoot 'native.lock.json') -Raw | ConvertFrom-Json
if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64' -or
    (-not $OnWindows -and -not $IsLinux)) { throw 'Native tests support x64 Windows and Linux.' }
$package = if ($OnWindows) { $lock.zig.windows_x64 } else { $lock.zig.linux_x64 }
# Keep compiler/cache on the project volume, including Windows redirected profiles.
$nativeRoot = Join-Path $ProjectRoot '.local/native'
$compiler = Join-Path (Join-Path $nativeRoot $package.folder) $(if ($OnWindows) { 'zig.exe' } else { 'zig' })
New-Item -ItemType Directory -Force -Path $nativeRoot | Out-Null
if (-not (Test-Path -LiteralPath $compiler)) {
    $archive = Join-Path $nativeRoot ([uri]$package.url).Segments[-1]
    if (-not (Test-Path -LiteralPath $archive)) {
        Write-Host "Downloading native test compiler Zig $($lock.zig.version)..."
        Invoke-WebRequest -Uri $package.url -OutFile $archive -TimeoutSec 300
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $package.sha256) {
        throw 'Native compiler archive checksum mismatch.'
    }
    if ($OnWindows) { Expand-Archive -LiteralPath $archive -DestinationPath $nativeRoot -Force }
    else {
        & tar -xJf $archive -C $nativeRoot
        if ($LASTEXITCODE -ne 0) { throw 'Native compiler extraction failed.' }
    }
}
if ((& $compiler version) -ne $lock.zig.version -or $LASTEXITCODE -ne 0) { throw 'Native compiler version mismatch.' }
foreach ($file in $lock.unity.files) {
    $path = Join-Path (Join-Path $ProjectRoot 'vendor/unity') $file.path
    if (-not (Test-Path -LiteralPath $path) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
        throw "Unity snapshot mismatch: $($file.path)"
    }
}
Write-Host "Native tests ready: Zig $($lock.zig.version), Unity $($lock.unity.version)."
