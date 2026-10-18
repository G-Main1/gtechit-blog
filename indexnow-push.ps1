<#
.SYNOPSIS
    Submits URLs to the IndexNow API so participating search engines (Bing,
    Microsoft Edge, Yandex, Seznam and other IndexNow partners) crawl the site
    immediately instead of waiting for the next crawl cycle.

.DESCRIPTION
    Reads the public key from the key file in the site root, derives the URL list
    from sitemap.xml, and POSTs a single batch request. No account or API token
    is required. The only credential is the key file, which is already published
    at the site root.

    Google does not currently participate in IndexNow. For Google, submit the
    sitemap in Google Search Console instead.

.PARAMETER Full
    Submit every URL in sitemap.xml. Without this switch, only the core URLs are
    submitted.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\indexnow-push.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\indexnow-push.ps1 -Full
#>

[CmdletBinding()]
param(
    [switch]$Full
)

$ErrorActionPreference = 'Stop'

$siteRoot    = 'https://g-main1.github.io/gtechit-blog'
$apiEndpoint = 'https://api.indexnow.org/indexnow'
$hostName    = 'g-main1.github.io'

$keyFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.txt' -File |
    Where-Object { $_.BaseName -match '^[0-9a-f]{32}$' }

if (-not $keyFiles) {
    throw 'No IndexNow key file found. Expected a 32-character hex .txt file in the site root.'
}

$key = $keyFiles[0].BaseName

$urls = @(
    "$siteRoot/",
    "$siteRoot/llms.txt",
    "$siteRoot/llms-full.txt",
    "$siteRoot/feed.xml",
    "$siteRoot/robots.txt"
)

if ($Full) {
    $mapPath = Join-Path $PSScriptRoot 'sitemap.xml'
    if (Test-Path $mapPath) {
        [xml]$map = Get-Content -Raw -Encoding UTF8 $mapPath
        $all = @($map.urlset.url | ForEach-Object { $_.loc })
        if ($all.Count -gt 0) { $urls = $all }
    }
}

Write-Host 'IndexNow submission'
Write-Host ("  site : {0}" -f $siteRoot)
Write-Host ("  key  : {0}" -f $key)
Write-Host ("  urls : {0}" -f $urls.Count)
Write-Host ''

$keyUrl = "$siteRoot/$key.txt"
try {
    $probe = Invoke-WebRequest -Uri $keyUrl -UseBasicParsing -TimeoutSec 20
    if ($probe.Content.Trim() -ne $key) {
        throw ("Key file at {0} does not match the local key." -f $keyUrl)
    }
    Write-Host '  key file reachable : OK'
} catch {
    throw ("Key file not reachable at {0}. Publish it before submitting. {1}" -f $keyUrl, $_.Exception.Message)
}

$payload = @{
    host        = $hostName
    key         = $key
    keyLocation = $keyUrl
    urlList     = $urls
} | ConvertTo-Json -Depth 4

try {
    $response = Invoke-WebRequest -Uri $apiEndpoint -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $payload `
        -UseBasicParsing -TimeoutSec 40

    Write-Host ("  submission        : HTTP {0}" -f $response.StatusCode)
    switch ($response.StatusCode) {
        200 { Write-Host '  result            : OK, URLs already submitted and queued' }
        202 { Write-Host '  result            : accepted, URLs queued for crawling' }
        400 { Write-Host '  result            : bad request, check urlList matches the host' }
        403 { Write-Host '  result            : forbidden, key file not found or key mismatch' }
        422 { Write-Host '  result            : unprocessable, URLs do not belong to this host or key invalid' }
        429 { Write-Host '  result            : rate limited, wait before retrying' }
        default { Write-Host '  result            : see IndexNow documentation' }
    }
} catch {
    $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'n/a' }
    Write-Host ("  submission failed : HTTP {0}" -f $code)
    throw
}