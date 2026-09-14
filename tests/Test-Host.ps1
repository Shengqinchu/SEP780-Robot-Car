[CmdletBinding()]
param()
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Common.ps1')
$hostPython = Get-HostPython
& $hostPython -X utf8 -m unittest discover -s (Join-Path $PSScriptRoot 'host') -v
if ($LASTEXITCODE -ne 0) { throw 'Offline host tests failed.' }
Push-Location (Join-Path $ProjectRoot 'host')
try { $expected = & $hostPython -X utf8 -c 'import serial_tool; print(serial_tool.port_lock_name("COM5"))' }
finally { Pop-Location }
if ($LASTEXITCODE -ne 0 -or $expected -ne (Split-Path (Get-PortLockPath 'COM5') -Leaf)) {
    throw 'PowerShell and Python port-lock names differ.'
}
Invoke-WithPortLock -Port 'COM9999' -Operation {
    $rejected = $false
    try { Invoke-WithPortLock -Port 'COM9999' -Operation { throw 'Nested lock unexpectedly acquired.' } }
    catch { $rejected = $_.Exception.Message -like 'Project port lock exists*' }
    if (-not $rejected) { throw 'Port lock did not reject a concurrent owner.' }
}
foreach ($port in @("COM5`n", 'COM0', 'loop://')) {
    $rejected = $false
    try { [void](Get-PortLockPath -Port $port) }
    catch { $rejected = $_.Exception.Message -like 'Expected a local*' }
    if (-not $rejected) { throw 'An invalid port was accepted by PowerShell.' }
}
Write-Host 'PASS: Shared lock naming and PowerShell lock exclusion. No physical port opened.'
