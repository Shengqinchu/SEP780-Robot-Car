[CmdletBinding()]
param([string]$Scenario = 'scenarios/line_course.csv')
. (Join-Path $PSScriptRoot 'Common.ps1')
& (Join-Path $ProjectRoot 'tests/Test-Control.ps1') -BuildOnly
$exe = Join-Path $ProjectRoot $(if ($OnWindows) { '.local/control-tests/control-tests.exe' } else { '.local/control-tests/control-tests' })
$source = if ([IO.Path]::IsPathRooted($Scenario)) { $Scenario } else { Join-Path $ProjectRoot $Scenario }
$output = Join-Path $ProjectRoot 'artifacts/local/line-course-replay.csv'
& (Get-HostPython) -X utf8 (Join-Path $ProjectRoot 'host/simulate.py') --executable $exe --scenario $source --output $output
if ($LASTEXITCODE -ne 0) { throw 'Scenario replay failed.' }
Write-Host "Replay CSV: $output"
