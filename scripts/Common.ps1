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
