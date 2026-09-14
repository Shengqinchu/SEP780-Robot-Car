[CmdletBinding()]
param([string]$PythonPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not $PythonPath) {
    $commandName = if ($OnWindows) { 'python' } else { 'python3' }
    $PythonPath = (Get-Command $commandName -ErrorAction Stop).Source
}
& $PythonPath -X utf8 -c 'import sys; assert sys.version_info >= (3, 10), "Python 3.10+ required"'
if ($LASTEXITCODE -ne 0) { throw 'A working Python 3.10+ executable is required. Pass -PythonPath explicitly.' }
$venv = Join-Path $ProjectRoot '.local/host-pyserial-3.5'
$hostPython = Join-Path $venv $(if ($OnWindows) { 'Scripts/python.exe' } else { 'bin/python' })
if (-not (Test-Path -LiteralPath $hostPython)) {
    & $PythonPath -X utf8 -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the isolated Python environment.' }
}
& $hostPython -X utf8 -m pip --isolated --disable-pip-version-check install --index-url https://pypi.org/simple --require-hashes --only-binary=:all: --no-deps -r (Join-Path $ProjectRoot 'host/requirements.lock')
if ($LASTEXITCODE -ne 0) { throw 'Pinned host dependency installation failed.' }
& $hostPython -X utf8 -c 'import serial; assert serial.VERSION == "3.5"; print("Host ready: pySerial " + serial.VERSION)'
if ($LASTEXITCODE -ne 0) { throw 'Host dependency verification failed.' }
Write-Host 'Isolated host environment ready. No serial port was opened.'
