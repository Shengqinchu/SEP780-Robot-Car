Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Toolchain = Get-Content -LiteralPath (Join-Path $ProjectRoot 'toolchain.lock.json') -Raw | ConvertFrom-Json
$OnWindows = $env:OS -eq 'Windows_NT'
if ($env:SEP780_TOOL_ROOT) {
    $ToolRoot = [IO.Path]::GetFullPath($env:SEP780_TOOL_ROOT)
} elseif ($OnWindows) {
    $ToolRoot = Join-Path $env:LOCALAPPDATA 'SEP780RobotCar'
} else {
    $ToolRoot = Join-Path $HOME '.cache/sep780-robot-car'
}
$CliDirectory = Join-Path $ToolRoot ("cli-" + $Toolchain.cli.version)
$CliName = if ($OnWindows) { 'arduino-cli.exe' } else { 'arduino-cli' }
$ArduinoCli = Join-Path $CliDirectory $CliName
$env:ARDUINO_DIRECTORIES_DATA = Join-Path $ToolRoot 'arduino-data'
$env:ARDUINO_DIRECTORIES_DOWNLOADS = Join-Path $ToolRoot 'arduino-downloads'
$env:ARDUINO_DIRECTORIES_USER = Join-Path $ToolRoot 'sketchbook'
$env:ARDUINO_UPDATER_ENABLE_NOTIFICATION = 'false'
$LibraryDirectory = Join-Path $env:ARDUINO_DIRECTORIES_USER 'libraries'

function Invoke-Arduino {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & $ArduinoCli @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Arduino CLI failed (exit $LASTEXITCODE): $($Arguments -join ' ')"
    }
}

function Assert-Toolchain {
    if (-not (Test-Path -LiteralPath $ArduinoCli)) {
        throw 'Toolchain missing. Run scripts/Setup-Toolchain.ps1 first.'
    }
    $version = & $ArduinoCli version --format json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $version.VersionString -ne $Toolchain.cli.version) {
        throw 'Arduino CLI version does not match toolchain.lock.json.'
    }
}

function Get-Program {
    param([Parameter(Mandatory)][string]$Name)
    $programs = @(Get-Content -LiteralPath (Join-Path $ProjectRoot 'programs.json') -Raw | ConvertFrom-Json)
    $matches = @($programs | Where-Object name -EQ $Name)
    if ($matches.Count -ne 1) {
        throw "Unknown program '$Name'. Choices: $(($programs.name) -join ', ')"
    }
    return $matches[0]
}

function Get-HostPython {
    $relative = if ($OnWindows) { 'Scripts/python.exe' } else { 'bin/python' }
    $python = Join-Path (Join-Path $ProjectRoot '.local/host-pyserial-3.5') $relative
    if (-not (Test-Path -LiteralPath $python)) { throw 'Host environment missing. Run scripts/Setup-Host.ps1 first.' }
    return $python
}

function Get-PortLockPath {
    param([Parameter(Mandatory)][string]$Port)
    if ($Port -match '\ACOM[1-9][0-9]{0,3}\z') { $Port = $Port.ToUpperInvariant() }
    elseif ($Port -cnotmatch '\A/dev/tty(ACM|USB)[0-9]+\z') { throw 'Expected a local COMn or /dev/ttyACMn/ttyUSBn port.' }
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Port))).ToLowerInvariant().Substring(0, 16)
    return Join-Path (Join-Path $ProjectRoot '.local/port-locks') "port-$hash.lock"
}

function Invoke-WithPortLock {
    param([Parameter(Mandatory)][string]$Port, [Parameter(Mandatory)][scriptblock]$Operation)
    $path = Get-PortLockPath -Port $Port
    New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
    try { $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None) }
    catch [IO.IOException] { throw 'Project port lock exists or cannot be created. Close the owner or inspect a stale lock; no port accessed.' }
    $token = [Guid]::NewGuid().ToString('N')
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes((@{token=$token; pid=$PID; port=$Port} | ConvertTo-Json -Compress))
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
    try { & $Operation }
    finally {
        if (Test-Path -LiteralPath $path) {
            $owner = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            if ($owner.token -eq $token) { Remove-Item -LiteralPath $path }
        }
    }
}
