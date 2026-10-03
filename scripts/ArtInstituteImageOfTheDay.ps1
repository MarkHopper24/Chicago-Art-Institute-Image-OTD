<#
.SYNOPSIS
    Fetches the Art Institute of Chicago "Image of the Day" and saves it for the TRMNL plugin.

.DESCRIPTION
    This script queries the Art Institute of Chicago public API (https://api.artic.edu/docs/)
    for public-domain artworks that have an image, deterministically selects one artwork for the
    current day, downloads its IIIF image in two sizes (one tuned for TRMNL OG, one for TRMNL X),
    and writes an ArtInstituteImageOfTheDay.json file that the TRMNL polling plugin consumes.

    The daily selection is deterministic: every device that renders on the same UTC day gets the
    same artwork, and the artwork changes automatically each day.

.PARAMETER UserAgentContact
    Value sent in the AIC-User-Agent header. The Art Institute asks API consumers to identify
    themselves. Defaults to this project's name and repository.

.EXAMPLE
    .\ArtInstituteImageOfTheDay.ps1

.NOTES
    File Name      : ArtInstituteImageOfTheDay.ps1
    Author         : Mark Hopper
    Prerequisite   : Run from the repository so the JSON and images land in the repo root.
    Data/Images    : Provided by the Art Institute of Chicago. Selected works are public domain (CC0).
#>

param(
    [string]$UserAgentContact = "ArtInstituteImageOfTheDay (github.com/MarkHopper24/Art-Institute-Image-of-the-Day)"
)

$ErrorActionPreference = 'Stop'

# --- Configuration -----------------------------------------------------------
$ApiBase = "https://api.artic.edu/api/v1"

# The API only allows paging into the first 1000 results (offset + limit must be <= 1000).
# These are ranked by relevance/popularity, so this is a curated pool of recognizable
# masterpieces, which is exactly what we want for an "image of the day".
$MaxPool = 1000

# IIIF image widths. OG (800x480, 1-bit) does not need much; X (1040x780, 4-bit) benefits from more.
$OgImageWidth = 843
$XImageWidth = 1200

$Headers = @{ 'AIC-User-Agent' = $UserAgentContact }

# Fields we ask the API to return (keeps the payload small and fast).
$Fields = @(
    'id', 'title', 'artist_display', 'date_display', 'medium_display',
    'dimensions', 'department_title', 'credit_line', 'image_id', 'is_public_domain'
) -join ','

# The repository root is the parent of the /scripts folder this file lives in.
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }

# Elasticsearch query: public domain AND has an image.
# The `params` API argument expects the full request body, so the bool clause
# must be wrapped in a top-level `query` key.
$SearchParams = @{
    query = @{
        bool = @{
            must = @(
                @{ term = @{ is_public_domain = $true } },
                @{ exists = @{ field = 'image_id' } }
            )
        }
    }
}

# --- Helpers -----------------------------------------------------------------
function Invoke-ArticApi {
    param(
        [Parameter(Mandatory = $true)][string]$Url
    )

    $maxRetries = 5
    $retryDelay = 5

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $Url -Method Get -Headers $Headers
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($attempt -lt $maxRetries -and ($null -eq $statusCode -or $statusCode -eq 429 -or $statusCode -ge 500)) {
                Write-Warning "API call failed (status $statusCode). Retry $attempt of $($maxRetries - 1) in $retryDelay s..."
                Start-Sleep -Seconds $retryDelay
                $retryDelay = $retryDelay * 2
            }
            else {
                throw
            }
        }
    }
}

function Get-DailyOffset {
    param([int]$PoolSize)

    # Whole days since the Unix epoch (UTC): stable within a day, advances daily.
    $epoch = [datetime]::SpecifyKind([datetime]'1970-01-01', [System.DateTimeKind]::Utc)
    $daysSinceEpoch = [int][math]::Floor(((Get-Date).ToUniversalTime() - $epoch).TotalDays)
    return $daysSinceEpoch % $PoolSize
}

function ConvertTo-CleanText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $Text = [System.Net.WebUtility]::HtmlDecode($Text)
    # artist_display and similar fields can contain newlines; flatten to a single readable line.
    $Text = $Text -replace '\r?\n', ', '
    $Text = $Text -replace '\s+', ' '
    return $Text.Trim()
}

function Save-Image {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$NativeUrl
    )
    Write-Host "Downloading image: $Url"
    try {
        Invoke-WebRequest -Uri $Url -Method Get -Headers $Headers -OutFile $Path
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode
        $errorText = "$($_.ErrorDetails.Message) $($_.Exception.Message)"
        # Only retry a scale restriction. Other HTTP/download errors must still fail the run.
        if ($statusCode -ne 403 -or $errorText -notmatch 'ScaleRestrictedException|Requests for scales in excess of 100%' -or $Url -eq $NativeUrl) {
            throw
        }
        Write-Warning "Requested image size exceeds the source. Retrying at native size: $NativeUrl"
        $Url = $NativeUrl
        Invoke-WebRequest -Uri $Url -Method Get -Headers $Headers -OutFile $Path
    }
    if (-not (Test-Path $Path) -or (Get-Item $Path).Length -eq 0) {
        throw "Downloaded image is missing or empty: $Path"
    }
    Write-Host ("Saved {0} ({1:N0} bytes)" -f $Path, (Get-Item $Path).Length)
    return $Url
}

# --- Main --------------------------------------------------------------------
Write-Host "Querying the Art Institute of Chicago for the image of the day..."

$encodedQuery = [System.Uri]::EscapeDataString(($SearchParams | ConvertTo-Json -Depth 10 -Compress))

# 1. Find out how large the public-domain-with-image pool is.
$countUrl = "$ApiBase/artworks/search?params=$encodedQuery&fields=id&limit=1"
$countResponse = Invoke-ArticApi -Url $countUrl
$total = [int]$countResponse.pagination.total
if ($total -le 0) { throw "The search returned no artworks." }

$poolSize = [math]::Min($total, $MaxPool)
$offset = Get-DailyOffset -PoolSize $poolSize
$page = $offset + 1  # API pages are 1-based; limit=1 makes page == offset + 1.

Write-Host "Pool size: $poolSize (of $total total). Today's offset: $offset (page $page)."

# 2. Fetch the single artwork for today.
$iiifBase = $countResponse.config.iiif_url
$artUrl = "$ApiBase/artworks/search?params=$encodedQuery&fields=$Fields&limit=1&page=$page"
$artResponse = Invoke-ArticApi -Url $artUrl
$art = $artResponse.data | Select-Object -First 1
if (-not $art) { throw "No artwork was returned for page $page." }
if (-not $iiifBase) { $iiifBase = $artResponse.config.iiif_url }
if (-not $art.image_id) { throw "Selected artwork '$($art.title)' has no image_id." }

Write-Host "Selected: '$($art.title)' (id $($art.id))"

# 3. Clamp the requested widths to the IIIF source width; this server forbids upscaling.
$imageBase = "$iiifBase/$($art.image_id)"
$nativeImageUrl = "$imageBase/full/pct:100/0/default.jpg"  # IIIF native size, without upscaling.
$downloadWidthOg = $OgImageWidth
$downloadWidthX = $XImageWidth
try {
    $imageInfo = Invoke-RestMethod -Uri "$imageBase/info.json" -Method Get -Headers $Headers -TimeoutSec 30
    $sourceWidth = 0
    if (-not [int]::TryParse([string]$imageInfo.width, [ref]$sourceWidth) -or $sourceWidth -le 0) {
        throw 'IIIF metadata has no valid source width.'
    }
    $downloadWidthOg = [math]::Min($OgImageWidth, $sourceWidth)
    $downloadWidthX = [math]::Min($XImageWidth, $sourceWidth)
    Write-Host "Source width: $sourceWidth px. Download widths: OG $downloadWidthOg px, X $downloadWidthX px."
}
catch {
    # Metadata is advisory. Save-Image can recover from an explicit scale rejection below.
    Write-Warning "Could not determine the IIIF source width. Using requested widths with a native-size fallback. $($_.Exception.Message)"
}
$imageUrlOg = "$imageBase/full/$downloadWidthOg,/0/default.jpg"
$imageUrlX = "$imageBase/full/$downloadWidthX,/0/default.jpg"

$localImage = "artwork.jpg"
$localImageX = "artwork_x.jpg"
$imageUrlOg = Save-Image -Url $imageUrlOg -Path (Join-Path $RepoRoot $localImage) -NativeUrl $nativeImageUrl
$imageUrlX = Save-Image -Url $imageUrlX -Path (Join-Path $RepoRoot $localImageX) -NativeUrl $nativeImageUrl

# 4. Assemble the data object the TRMNL plugin polls.
$artworkPageUrl = "https://www.artic.edu/artworks/$($art.id)"

$data = [ordered]@{
    Title         = ConvertTo-CleanText $art.title
    Artist        = ConvertTo-CleanText $art.artist_display
    DateDisplay   = ConvertTo-CleanText $art.date_display
    Medium        = ConvertTo-CleanText $art.medium_display
    Dimensions    = ConvertTo-CleanText $art.dimensions
    Department    = ConvertTo-CleanText $art.department_title
    CreditLine    = ConvertTo-CleanText $art.credit_line
    ArtworkID     = $art.id
    ArtworkURL    = $artworkPageUrl
    ImageURL      = $imageUrlOg
    ImageURLLarge = $imageUrlX
    LocalImage    = $localImage
    LocalImageX   = $localImageX
    Date          = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    Attribution   = "Artwork image and metadata provided by the Art Institute of Chicago under CC0. This work is in the public domain."
}

$jsonPath = Join-Path $RepoRoot "ArtInstituteImageOfTheDay.json"
$data | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding UTF8
Write-Host "Wrote $jsonPath"
Write-Host "Done."
