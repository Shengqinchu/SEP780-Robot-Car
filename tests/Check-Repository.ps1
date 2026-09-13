[CmdletBinding()]
param()
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Common.ps1')

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$manifest = Get-Content -LiteralPath (Join-Path $ProjectRoot 'vendor/freenove-manifest.json') -Raw | ConvertFrom-Json
Assert-Condition ($manifest.commit -eq $Toolchain.upstream.commit) 'Upstream commit mismatch.'
$vendor = Join-Path $ProjectRoot 'vendor/freenove'
$actualFiles = @(Get-ChildItem -LiteralPath $vendor -File -Recurse)
Assert-Condition ($actualFiles.Count -eq $manifest.files.Count) 'Unexpected vendor file count.'
foreach ($file in $manifest.files) {
    Assert-Condition (-not ($file.path -match '(^/)|(^|/)\.\.(/|$)|:')) "Invalid manifest path: $($file.path)"
    $path = Join-Path $vendor $file.path
    Assert-Condition (Test-Path -LiteralPath $path -PathType Leaf) "Missing vendor file: $($file.path)"
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert-Condition ($hash -eq $file.sha256) "Modified vendor file: $($file.path)"
}
Write-Host "PASS: $($manifest.files.Count) original vendor files match SHA-256."

$programs = @(Get-Content -LiteralPath (Join-Path $ProjectRoot 'programs.json') -Raw | ConvertFrom-Json)
Assert-Condition (@($programs.name | Select-Object -Unique).Count -eq $programs.Count) 'Duplicate program name.'
foreach ($program in $programs) {
    Assert-Condition (-not ($program.path -match '(^/)|(^|/)\.\.(/|$)|:')) 'Program paths must be repository-relative.'
    $folder = Join-Path $ProjectRoot $program.path
    $sketchName = Split-Path $folder -Leaf
    Assert-Condition (Test-Path -LiteralPath (Join-Path $folder ($sketchName + '.ino'))) "Missing sketch: $($program.name)"
    Assert-Condition ($program.actuators -is [bool]) 'Actuator flags must be booleans.'
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($program.power)) 'Missing power-state requirement.'
}
Assert-Condition ((Get-Program 'servo_center').actuators -eq $true) 'Servo program must be marked as actuating.'
Assert-Condition ((Get-Program 'ultrasonic_test').actuators -eq $true) 'Ultrasonic example sweeps the servo.'
Assert-Condition ((Get-Program 'motor_test').actuators -eq $true) 'Motor program must be marked as actuating.'
Write-Host "PASS: $($programs.Count) named programs and actuator warnings."

foreach ($script in Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'scripts'), $PSScriptRoot -Filter '*.ps1' -File) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
    Assert-Condition ($parseErrors.Count -eq 0) "PowerShell syntax errors: $($script.Name)"
}
Write-Host 'PASS: PowerShell script syntax.'

$usb = Get-Content -LiteralPath (Join-Path $ProjectRoot 'firmware/usb_check/usb_check.ino') -Raw
Assert-Condition (-not ($usb -match 'analogWrite|Servo\.h|motorRun|servo\.attach')) 'USB-only check must not control actuators.'
Assert-Condition ($usb.Contains('Serial.begin(115200)')) 'USB check baud rate changed; update the bring-up contract.'
Write-Host 'PASS: USB-only source guard (static check, not a hardware test).'

$rejected = $false
try {
    & (Join-Path $ProjectRoot 'scripts/Upload.ps1') -Program usb_check -Port 'NOT-A-REAL-PORT'
} catch {
    $rejected = $_.Exception.Message -like 'Upload requires -ConfirmHardwareReady*'
}
Assert-Condition $rejected 'Upload must reject missing physical confirmation before accessing hardware.'
Write-Host 'PASS: Upload refused without hardware confirmation; no port accessed.'
Write-Host 'All repository checks passed. No hardware was tested.'
