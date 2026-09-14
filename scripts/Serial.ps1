[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('list', 'self-test', 'capture', 'usb-check')][string]$Action,
    [string]$Port,
    [ValidateRange(1, 60)][double]$Seconds = 8,
    [ValidateRange(128, 65536)][int]$MaxBytes = 8192,
    [Alias('ConfirmUsbIsolated')][switch]$ConfirmUsbSetup
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$hostPython = Get-HostPython
$arguments = @('-X', 'utf8', (Join-Path $ProjectRoot 'host/serial_tool.py'), $Action)
if ($Action -in @('capture', 'usb-check')) {
    if (-not $ConfirmUsbSetup) { throw 'Confirm USB-only power, no batteries/external supply, car POWER off and Bluetooth removed before serial open.' }
    if ([string]::IsNullOrWhiteSpace($Port)) { throw 'An explicit port is required.' }
    $arguments += @('--port', $Port, '--seconds', $Seconds.ToString([Globalization.CultureInfo]::InvariantCulture), '--max-bytes', "$MaxBytes", '--confirm-usb-setup')
} elseif ($Port -or $ConfirmUsbSetup) {
    throw 'list/self-test do not accept a physical port or hardware confirmation.'
}
& $hostPython @arguments
if ($LASTEXITCODE -ne 0) { throw 'Serial operation did not pass. Inspect the JSON result; no automatic retry was attempted.' }
