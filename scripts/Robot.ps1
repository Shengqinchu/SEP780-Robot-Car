[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('observe','line','drive','stop')][string]$Action,
    [Parameter(Mandatory)][string]$Port,
    [ValidateRange(1,30)][double]$Seconds = 5,
    [ValidateRange(-150,150)][int]$Left = 0,
    [ValidateRange(-150,150)][int]$Right = 0,
    [switch]$ConfirmHardwareReady,
    [switch]$ConfirmMotionClear
)
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not $ConfirmHardwareReady) { throw 'Robot session requires -ConfirmHardwareReady before any port access.' }
if ($Action -in @('line','drive') -and -not $ConfirmMotionClear) { throw 'Motion requires -ConfirmMotionClear.' }
$arguments = @('-X','utf8',(Join-Path $ProjectRoot 'host/robot_tool.py'),$Action,'--port',$Port,
    '--seconds',$Seconds.ToString([Globalization.CultureInfo]::InvariantCulture),'--left',"$Left",'--right',"$Right",'--confirm-hardware-ready')
if ($ConfirmMotionClear) { $arguments += '--confirm-motion-clear' }
& (Get-HostPython) @arguments
if ($LASTEXITCODE -ne 0) { throw 'Robot session failed. Read the saved result; no automatic retry.' }
