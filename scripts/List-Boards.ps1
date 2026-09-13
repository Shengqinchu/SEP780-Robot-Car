. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Toolchain
Invoke-Arduino -Arguments @('board', 'list')
