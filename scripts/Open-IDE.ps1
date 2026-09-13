[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not $OnWindows) { throw 'This launcher is for the prepared Windows IDE only.' }
$ide = Join-Path $ToolRoot 'arduino-ide-2.3.10/Arduino IDE.exe'
if (-not (Test-Path -LiteralPath $ide)) { throw 'The prepared Arduino IDE executable is not present on this machine.' }
# Run interactively only when the user explicitly invokes this launcher.
& $ide (Join-Path $ProjectRoot 'firmware/usb_check/usb_check.ino')
