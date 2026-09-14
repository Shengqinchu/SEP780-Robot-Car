[CmdletBinding()]
param()
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Common.ps1')
$documents = @('README.md','README.en.md','docs/calibration.md','docs/calibration.en.md','docs/controller.md','docs/control-protocol.md','docs/project-plan.md','docs/test-plan.md')
$linkCount = 0
foreach ($file in $documents) {
    $path = Join-Path $ProjectRoot $file
    $content = Get-Content -LiteralPath $path -Raw
    # These guides use ordinary inline Markdown links, without reference-style definitions.
    foreach ($match in [regex]::Matches($content, '\[[^\]\r\n]+\]\(([^\s)]+)\)')) {
        $target = $match.Groups[1].Value
        if ($target -match '^https://|^#') { continue }
        $target = ($target -split '#',2)[0]
        if (-not (Test-Path -LiteralPath (Join-Path (Split-Path $path -Parent) $target))) {
            throw "Broken local link in ${file}: $target"
        }
        ++$linkCount
    }
    if ([regex]::Matches($content, '(?m)^```').Count % 2 -ne 0) { throw "Unbalanced code fences: $file" }
}
$commands = @()
foreach ($file in @('README.md','README.en.md')) {
    $content = Get-Content -LiteralPath (Join-Path $ProjectRoot $file) -Raw
    if (($content -split '\r?\n').Count -gt 140) { throw "README exceeds the project entry-page length budget: $file" }
    if ($content -match '\bTODO\b|\bFIXME\b|\bTBD\b') { throw "Unfinished README text: $file" }
    $commands += (([regex]::Matches($content, '(?s)```powershell\r?\n(.*?)```') | ForEach-Object {
        $_.Groups[1].Value.Replace("`r",'').Trim()
    }) -join "`n")
}
if ($commands[0] -ne $commands[1]) { throw 'Chinese and English README command examples differ.' }
Write-Host "PASS: $($documents.Count) guides, $linkCount local links, code fences, concise READMEs, matching bilingual commands."
