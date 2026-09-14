[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Research([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$allNames = @()
$queryCount = 0
foreach ($file in @('github-inventory-2026-09-13.json', 'github-refinement-2026-09-13.json')) {
    $data = Get-Content -LiteralPath (Join-Path $PSScriptRoot $file) -Raw | ConvertFrom-Json
    Assert-Research ($data.query_count -eq $data.queries.Count) "Query count mismatch: $file"
    Assert-Research ($data.unique_repositories -eq $data.repositories.Count) "Repository count mismatch: $file"
    Assert-Research (@($data.repositories.name | Sort-Object -Unique).Count -eq $data.repositories.Count) "Duplicate records: $file"
    foreach ($repo in $data.repositories) {
        Assert-Research (([string]$repo.description).Length -le 240) 'Descriptions must be bounded.'
        Assert-Research ($repo.url -eq "https://github.com/$($repo.name)") 'Invalid repository URL.'
    }
    $queryCount += $data.query_count
    $allNames += $data.repositories.name
}
Write-Host "PASS: $queryCount queries; $(@($allNames | Sort-Object -Unique).Count) unique initial repositories."

$plan = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'shortlist.json') -Raw | ConvertFrom-Json)
$meta = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'review-metadata-2026-09-13.json') -Raw | ConvertFrom-Json
Assert-Research ($plan.Count -eq $meta.repositories.Count) 'Review metadata count mismatch.'
Assert-Research (@($meta.repositories.name | Sort-Object -Unique).Count -eq $plan.Count) 'Duplicate review metadata.'
foreach ($item in $plan) {
    $record = @($meta.repositories | Where-Object name -eq $item.name)
    Assert-Research ($record.Count -eq 1) "Missing metadata: $($item.name)"
    Assert-Research ($record[0].category -eq $item.category) 'Category mismatch.'
    Assert-Research ($record[0].commit -match '^[a-f0-9]{40}$') 'Invalid commit SHA.'
    foreach ($doc in $record[0].documents) {
        Assert-Research ($doc.blob_sha -match '^[a-f0-9]{40}$') 'Invalid document blob SHA.'
        Assert-Research ($doc.sha256 -match '^[a-f0-9]{64}$') 'Invalid document SHA-256.'
        Assert-Research ($doc.url.Contains("/blob/$($record[0].commit)/")) 'Document is not commit-pinned.'
    }
}
Write-Host "PASS: $($plan.Count) shortlisted repositories have unique pinned metadata."

$pins = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'source-pins-2026-09-13.json') -Raw | ConvertFrom-Json)
foreach ($pin in $pins) {
    $record = $meta.repositories | Where-Object name -eq $pin.name
    Assert-Research ($null -ne $record -and $pin.commit -eq $record.commit) 'Cloned source and metadata pins differ.'
}
Write-Host "PASS: $($pins.Count) cloned source pins agree with the review snapshot."

foreach ($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File) {
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors)
    Assert-Research ($parseErrors.Count -eq 0) "PowerShell syntax error: $($script.Name)"
}
Write-Host 'PASS: Research script syntax. No network request or serial operation performed.'
