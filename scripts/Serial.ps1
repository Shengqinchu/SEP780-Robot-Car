[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('list', 'self-test', 'capture', 'usb-check')][string]$Action,
    [string]$Port,
    [ValidateRange(1, 60)][double]$Seconds = 8,
    [ValidateRange(128, 65536)][int]$MaxBytes = 8192,
    [switch]$ConfirmUsbIsolated
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$hostPython = Get-HostPython
$arguments = @('-X', 'utf8', (Join-Path $ProjectRoot 'host/serial_tool.py'), $Action)
if ($Action -in @('capture', 'usb-check')) {
    if (-not $ConfirmUsbIsolated) { throw 'Confirm bare USB board and isolated actuators before serial open; it may reset the MCU.' }
    if ([string]::IsNullOrWhiteSpace($Port)) { throw 'An explicit port is required.' }
    $arguments += @('--port', $Port, '--seconds', $Seconds.ToString([Globalization.CultureInfo]::InvariantCulture), '--max-bytes', "$MaxBytes", '--confirm-usb-isolated')
} elseif ($Port -or $ConfirmUsbIsolated) {
    throw 'list/self-test do not accept a physical port or hardware confirmation.'
}
& $hostPython @arguments
if ($LASTEXITCODE -ne 0) { throw 'Serial operation did not pass. Inspect the JSON result; no automatic retry was attempted.' }
