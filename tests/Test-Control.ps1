[CmdletBinding()]
param([switch]$BuildOnly)
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Common.ps1')
$lock = Get-Content -LiteralPath (Join-Path $ProjectRoot 'native.lock.json') -Raw | ConvertFrom-Json
$package = if ($OnWindows) { $lock.zig.windows_x64 } else { $lock.zig.linux_x64 }
$compiler = Join-Path (Join-Path $ProjectRoot ('.local/native/' + $package.folder)) $(if ($OnWindows) { 'zig.exe' } else { 'zig' })
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Run scripts/Setup-Native.ps1 first.' }
if ((& $compiler version) -ne $lock.zig.version -or $LASTEXITCODE -ne 0) { throw 'Native compiler version mismatch.' }
$build = Join-Path $ProjectRoot '.local/control-tests'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$env:ZIG_GLOBAL_CACHE_DIR = Join-Path $build 'global-cache'
$env:ZIG_LOCAL_CACHE_DIR = Join-Path $build 'local-cache'
$object = Join-Path $build 'unity.o'
$exe = Join-Path $build $(if ($OnWindows) { 'control-tests.exe' } else { 'control-tests' })
Push-Location $ProjectRoot
try {
    & $compiler cc -std=c99 -O0 -g -DUNITY_EXCLUDE_FLOAT -DUNITY_EXCLUDE_DOUBLE -Ivendor/unity/src -c vendor/unity/src/unity.c -o $object
    if ($LASTEXITCODE -ne 0) { throw 'Unity compilation failed.' }
    & $compiler c++ -std=c++11 -O0 -g -fno-exceptions -fno-rtti -nostdlib++ -Wall -Wextra -Werror -DUNITY_EXCLUDE_FLOAT -DUNITY_EXCLUDE_DOUBLE `
        -Ifirmware/robot_car -Ivendor/unity/src -Itests/native/stubs `
        firmware/robot_car/controller.cpp firmware/robot_car/protocol.cpp firmware/robot_car/ir_input.cpp `
        firmware/robot_car/fnk0041_io.cpp tests/native/stubs/arduino.cpp tests/native/test_control.cpp $object -o $exe
    if ($LASTEXITCODE -ne 0) { throw 'Control test compilation failed.' }
    if (-not $BuildOnly) {
        & $exe
        if ($LASTEXITCODE -ne 0) { throw 'Control tests failed.' }
    }
} finally { Pop-Location }
