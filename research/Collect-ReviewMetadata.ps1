[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$plan = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'shortlist.json') -Raw | ConvertFrom-Json
$cache = Join-Path (Split-Path $PSScriptRoot -Parent) '.cache/review-documents'
New-Item -ItemType Directory -Force -Path $cache | Out-Null
$records = @()

function Get-GitHubJson([string]$Endpoint, [switch]$AllowMissing) {
    $raw = & gh api $Endpoint 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($AllowMissing -and ($raw -join "`n") -match 'HTTP 404') { return $null }
        throw "GitHub request failed: $Endpoint : $($raw -join ' ')"
    }
    return ($raw -join "`n" | ConvertFrom-Json)
}

foreach ($item in $plan) {
    $meta = Get-GitHubJson "repos/$($item.name)"
    $commit = Get-GitHubJson "repos/$($item.name)/commits/$($meta.default_branch)"
    $record = [ordered]@{
        name = $meta.full_name
        category = $item.category
        url = $meta.html_url
        private = $meta.private
        stars = $meta.stargazers_count
        archived = $meta.archived
        pushed_at = $meta.pushed_at
        commit = $commit.sha
        commit_date = $commit.commit.committer.date
        license_spdx = $(if ($meta.license) { $meta.license.spdx_id } else { $null })
        documents = @()
    }
    foreach ($endpoint in @('readme', 'license')) {
        $doc = Get-GitHubJson "repos/$($item.name)/${endpoint}?ref=$($commit.sha)" -AllowMissing
        if (-not $doc) { continue }
        $bytes = [Convert]::FromBase64String($doc.content)
        $key = $item.name.Replace('/', '__')
        [IO.File]::WriteAllBytes((Join-Path $cache "$key--$endpoint.txt"), $bytes)
        $record.documents += [ordered]@{
            kind = $endpoint
            path = $doc.path
            blob_sha = $doc.sha
            sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            url = "https://github.com/$($item.name)/blob/$($commit.sha)/$($doc.path)"
        }
    }
    $records += $record
    Write-Host "$($record.name): $($record.stars) stars, $($record.license_spdx), $($record.documents.Count) documents"
}
$out = [ordered]@{retrieved_at_utc=[DateTime]::UtcNow.ToString('o'); repositories=$records}
$out | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'review-metadata-2026-09-13.json') -Encoding utf8
