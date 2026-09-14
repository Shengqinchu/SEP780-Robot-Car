[CmdletBinding()]
param(
    [string]$OutputName = 'github-inventory-2026-09-13.json',
    [string]$PlanName = 'github-search-plan.json'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$plan = Get-Content -LiteralPath (Join-Path $PSScriptRoot $PlanName) -Raw | ConvertFrom-Json
$root = Split-Path $PSScriptRoot -Parent
$cache = Join-Path $root '.cache/github-research'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$repos = @{}
$queryResults = @()
$failures = @()

function Add-Repository {
    param($Repository, [string]$Origin)
    $key = $Repository.full_name.ToLowerInvariant()
    if (-not $repos.ContainsKey($key)) {
        $license = if ($Repository.license) { $Repository.license.spdx_id } else { $null }
        $description = [string]$Repository.description
        $repos[$key] = [ordered]@{
            name = $Repository.full_name
            url = $Repository.html_url
            description = $description.Substring(0, [Math]::Min(240, $description.Length))
            description_truncated = ($description.Length -gt 240)
            stars = $Repository.stargazers_count
            forks = $Repository.forks_count
            language = $Repository.language
            license_spdx = $license
            archived = $Repository.archived
            created_at = $Repository.created_at
            pushed_at = $Repository.pushed_at
            default_branch = $Repository.default_branch
            origins = @()
        }
    }
    if ($Origin -notin $repos[$key].origins) { $repos[$key].origins += $Origin }
}

foreach ($query in $plan.queries) {
    $retrieved = 0
    $total = 0
    $incomplete = $false
    $pages = 0
    for ($page=1; $page -le $plan.max_pages; $page++) {
        $raw = & gh api -X GET search/repositories -f "q=$($query.q)" -f 'sort=stars' -f 'order=desc' -f "per_page=$($plan.per_page)" -f "page=$page" 2>&1
        if ($LASTEXITCODE -ne 0) {
            $failures += [ordered]@{source=$query.id; message=($raw -join "`n")}
            break
        }
        $raw -join "`n" | Set-Content -LiteralPath (Join-Path $cache "$($query.id)-$page.json") -Encoding utf8
        $data = $raw -join "`n" | ConvertFrom-Json
        $total = $data.total_count
        $incomplete = $incomplete -or $data.incomplete_results
        $pages++
        foreach ($item in $data.items) { Add-Repository $item $query.id }
        $retrieved += @($data.items).Count
        if (@($data.items).Count -lt $plan.per_page -or $retrieved -ge $total) { break }
        Start-Sleep -Seconds 2
    }
    $queryResults += [ordered]@{id=$query.id; query=$query.q; total_matches=$total; retrieved=$retrieved; pages=$pages; truncated=($retrieved -lt $total); incomplete_results=$incomplete}
    Write-Host "$($query.id): retrieved $retrieved of $total"
    Start-Sleep -Seconds 2
}

foreach ($seed in $plan.seeds) {
    $raw = & gh api "repos/$seed" 2>&1
    if ($LASTEXITCODE -ne 0) {
        $failures += [ordered]@{source=$seed; message=($raw -join "`n")}
        continue
    }
    $data = $raw -join "`n" | ConvertFrom-Json
    Add-Repository $data 'curated_primary_seed'
    Write-Host "Seed: $($data.full_name) ($($data.stargazers_count) stars)"
}

$result = [ordered]@{
    retrieved_at_utc = [DateTime]::UtcNow.ToString('o')
    scope = 'Bounded multilingual repository search plus primary-project seeds; not exhaustive GitHub coverage'
    query_count = $queryResults.Count
    unique_repositories = $repos.Count
    queries = $queryResults
    repositories = @($repos.Values | Sort-Object { $_.stars } -Descending)
    errors = $failures
}
$output = Join-Path $PSScriptRoot $OutputName
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $output -Encoding utf8
Write-Host "Inventory: $($repos.Count) unique repositories, $($failures.Count) errors -> $output"
