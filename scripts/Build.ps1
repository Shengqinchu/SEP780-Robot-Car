[CmdletBinding()]
param(
    [string]$Program,
    [switch]$All
)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Toolchain
if ($Program -and $All) { throw 'Choose -Program or -All, not both.' }

if ($Program) {
    $selected = @(Get-Program -Name $Program)
} elseif ($All) {
    $selected = @(Get-Content -LiteralPath (Join-Path $ProjectRoot 'programs.json') -Raw | ConvertFrom-Json | Where-Object { $_.path.StartsWith('firmware/') })
    $vendorRoot = Join-Path $ProjectRoot 'vendor/freenove/Sketches'
    $selected += @(Get-ChildItem -LiteralPath $vendorRoot -Directory | Sort-Object Name | ForEach-Object {
        $ino = Join-Path $_.FullName ($_.Name + '.ino')
        if (Test-Path -LiteralPath $ino) {
            [pscustomobject]@{ name = $_.Name; path = 'vendor/freenove/Sketches/' + $_.Name }
        }
    })
} else {
    $selected = @(Get-Content -LiteralPath (Join-Path $ProjectRoot 'programs.json') -Raw | ConvertFrom-Json)
}

$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$buildRoot = Join-Path $ToolRoot ("build/" + $runId)
$reportRoot = Join-Path $ProjectRoot 'artifacts/local'
New-Item -ItemType Directory -Force -Path $buildRoot, $reportRoot | Out-Null
$results = @()
foreach ($item in $selected) {
    Write-Host "Compiling $($item.name)..."
    $source = Join-Path $ProjectRoot $item.path
    $build = Join-Path $buildRoot $item.name
    New-Item -ItemType Directory -Force -Path $build | Out-Null
    $stderr = Join-Path $build 'stderr.txt'
    $output = & $ArduinoCli compile --fqbn $Toolchain.board --libraries $LibraryDirectory --build-path $build --warnings all --json $source 2> $stderr
    $code = $LASTEXITCODE
    ($output -join "`n") | Set-Content -LiteralPath (Join-Path $build 'compile.json') -Encoding utf8
    $sizes = @()
    $libraries = @()
    $warningCount = 0
    if ($code -eq 0) {
        $parsed = ($output -join "`n") | ConvertFrom-Json
        $actualCore = $parsed.builder_result.board_platform.id + '@' + $parsed.builder_result.board_platform.version
        if (-not $parsed.success -or $actualCore -ne $Toolchain.core) {
            throw "Unexpected compiler result or core version: $actualCore"
        }
        $sizes = @($parsed.builder_result.executable_sections_size | Select-Object name, size, max_size)
        if ($parsed.builder_result.PSObject.Properties['used_libraries']) {
            $libraries = @($parsed.builder_result.used_libraries | ForEach-Object {
                $version = if ($_.PSObject.Properties['version']) { $_.version } else { '' }
                $pin = $Toolchain.library_versions.PSObject.Properties[$_.name]
                if ($pin -and $pin.Value -ne $version) {
                    throw "Library version mismatch: $($_.name) $version. Run Setup-Toolchain.ps1."
                }
                [pscustomobject]@{name = $_.name; version = $version}
            })
        }
        if ($parsed.builder_result.PSObject.Properties['diagnostics']) {
            $warningCount = @($parsed.builder_result.diagnostics | Where-Object severity -EQ 'WARNING').Count
        }
        Write-Host $parsed.compiler_out
    }
    $results += [pscustomobject]@{
        program = $item.name
        source = $item.path
        success = $code -eq 0
        exit_code = $code
        sizes = $sizes
        used_libraries = $libraries
        warning_count = $warningCount
    }
    if ($code -ne 0) {
        Write-Warning "Compilation failed: $($item.name)"
        Write-Host ($output -join "`n")
        Get-Content -LiteralPath $stderr | Write-Host
    }
}
$summary = [ordered]@{
    recorded_at_utc = [DateTime]::UtcNow.ToString('o')
    scope = 'Compilation only; not flashed or hardware-tested'
    cli_version = $Toolchain.cli.version
    core = $Toolchain.core
    fqbn = $Toolchain.board
    upstream_commit = $Toolchain.upstream.commit
    passed = @($results | Where-Object success -EQ $true).Count
    total = $results.Count
    programs = $results
}
$report = Join-Path $reportRoot ('compile-' + $runId + '.json')
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $report -Encoding utf8
Write-Host "Compilation: $($summary.passed)/$($summary.total) passed."
Write-Host "Summary: $report"
Write-Host "Raw compiler output: $buildRoot"
if ($summary.passed -ne $summary.total) { throw 'One or more sketches failed compilation.' }
