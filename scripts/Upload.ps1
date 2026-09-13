[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Program,
    [Parameter(Mandatory)][string]$Port,
    [switch]$ConfirmHardwareReady
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$item = Get-Program -Name $Program
if (-not $ConfirmHardwareReady) {
    throw 'Upload requires -ConfirmHardwareReady after checking board identity, power, wiring and Bluetooth removal. See docs/bring-up.md.'
}
if ([string]::IsNullOrWhiteSpace($Port)) { throw 'An explicit serial port is required.' }
Assert-Toolchain
Write-Warning "This overwrites the firmware on $Port. Program: $Program. Required power state: $($item.power)."
& (Join-Path $PSScriptRoot 'Build.ps1') -Program $Program
Invoke-Arduino -Arguments @('compile', '--fqbn', $Toolchain.board, '--libraries', $LibraryDirectory, '--upload', '--port', $Port, (Join-Path $ProjectRoot $item.path))
Write-Host 'Upload completed. This is NOT evidence of hardware functional success.'
