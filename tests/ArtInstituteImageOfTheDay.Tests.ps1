<#
.SYNOPSIS
    Tests image sizing in temporary fixtures, without committing or publishing output.
.EXAMPLE
    pwsh -File .\tests\ArtInstituteImageOfTheDay.Tests.ps1
.EXAMPLE
    pwsh -File .\tests\ArtInstituteImageOfTheDay.Tests.ps1 -Live
    Also downloads artworks 170 and 81548 from the public API into temporary fixtures.
#>
param([switch]$Live)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AicImageSizeTests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
# Load the real web cmdlet assembly before constructing HTTP errors in the mocks.
$null = Get-Command Microsoft.PowerShell.Utility\Invoke-WebRequest
$results = [System.Collections.Generic.List[object]]::new()

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -cne $Expected) { throw "$Message (expected '$Expected', got '$Actual')" }
}

function Throw-HttpError {
    param([int]$Status, [string]$Message)
    $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
    $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new("HTTP $Status", $response)
    $record = [System.Management.Automation.ErrorRecord]::new($exception, 'FixtureHttpError', 'InvalidOperation', $null)
    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Message)
    throw $record
}

function Invoke-TestCase {
    param([hashtable]$Case)

    $fixture = Join-Path $testRoot $Case.Name
    $scripts = Join-Path $fixture 'scripts'
    New-Item -ItemType Directory -Path $scripts | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/ArtInstituteImageOfTheDay.ps1') -Destination $scripts
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/ReadMeUpdater.ps1') -Destination $scripts
    Set-Content -LiteralPath (Join-Path $fixture 'README.md') -Value "<!-- ARTWORK_START -->`nold artwork`n<!-- ARTWORK_END -->`n`nFixture documentation."
    $requests = [System.Collections.Generic.List[string]]::new()
    $infoCalls = [System.Collections.Generic.List[string]]::new()
    $headers = @{ 'AIC-User-Agent' = 'Chicago-Art-Institute-Image-OTD size-fix tests' }
    $response = [pscustomobject]@{
        pagination = [pscustomobject]@{ total = 1000 }
        config = [pscustomobject]@{ iiif_url = 'https://fixture.invalid/iiif/2' }
        data = @([pscustomobject]@{
            id = 170; title = 'Fixture Artwork'; image_id = 'fixture-image'
            artist_display = 'Fixture Artist'; date_display = '2026'; medium_display = 'Test'
            dimensions = ''; department_title = ''; credit_line = ''; is_public_domain = $true
        })
    }
    if ($Case.LiveArtwork) {
        $fields = 'id,title,artist_display,date_display,medium_display,dimensions,department_title,credit_line,image_id,is_public_domain'
        $response = Microsoft.PowerShell.Utility\Invoke-RestMethod -Uri "https://api.artic.edu/api/v1/artworks/$($Case.LiveArtwork)?fields=$fields" -Headers $headers -TimeoutSec 30
        $response | Add-Member -NotePropertyName pagination -NotePropertyValue ([pscustomobject]@{ total = 1000 })
    }
    $imageBase = "$($response.config.iiif_url)/$($response.data[0].image_id)"

    # Only the search selection is stubbed for live tests, pinning the chosen artwork.
    # Both production scripts run unchanged in the copied fixture directory.
    function Invoke-RestMethod {
        param($Uri, $Method, $Headers, $TimeoutSec)
        if ($Uri -like '*/info.json') {
            $infoCalls.Add([string]$Uri)
            if ($Case.LiveArtwork -and -not $Case.InfoUnavailable) {
                return Microsoft.PowerShell.Utility\Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -TimeoutSec $TimeoutSec
            }
            if ($Case.InfoUnavailable) { Throw-HttpError 404 'Image information unavailable' }
            return [pscustomobject]@{ width = $Case.SourceWidth }
        }
        if ($Uri -like 'https://api.artic.edu/api/v1/artworks/search?*') { return $response }
        throw "Unexpected API request: $Uri"
    }

    function Invoke-WebRequest {
        param($Uri, $Method, $Headers, $OutFile)
        $requests.Add([string]$Uri)
        if ($Case.LiveArtwork) {
            Microsoft.PowerShell.Utility\Invoke-WebRequest -Uri $Uri -Method $Method -Headers $Headers -OutFile $OutFile -TimeoutSec 30
            return
        }
        if ($Case.DownloadFailure -eq 'Timeout') { throw 'Fixture download timeout' }
        if ($Case.DownloadStatus) { Throw-HttpError $Case.DownloadStatus 'Access denied or server error' }
        if ($Uri -like '*/full/pct:100/*' -and $Case.NativeFailure) { Throw-HttpError 403 'ScaleRestrictedException: Requests for scales in excess of 100% are not allowed.' }
        if ($Uri -match '/full/(\d+),/' -and [int]$Matches[1] -gt $Case.ActualWidth) {
            Throw-HttpError 403 'ScaleRestrictedException: Requests for scales in excess of 100% are not allowed.'
        }
        if ($Case.EmptyDownload) { [System.IO.File]::WriteAllBytes($OutFile, [byte[]]@()) }
        else { [System.IO.File]::WriteAllBytes($OutFile, [byte[]]@(255, 216, 255, 217)) }
    }

    $failure = $null
    $dimensions = @()
    try { & (Join-Path $scripts 'ArtInstituteImageOfTheDay.ps1') }
    catch { $failure = $_ }
    Assert-Equal $infoCalls.Count 1 'Source metadata should be requested once'
    $jsonPath = Join-Path $fixture 'ArtInstituteImageOfTheDay.json'
    if ($Case.ExpectedFailure) {
        if (-not $failure) { throw 'Expected the download to fail' }
        if ($failure.ToString() -notmatch $Case.ExpectedFailure) { throw "Unexpected failure: $failure" }
        Assert-Equal (Test-Path -LiteralPath $jsonPath) $false 'Failed downloads must not produce new JSON'
    }
    else {
        if ($failure) { throw $failure }
        $data = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
        Assert-Equal $data.ImageURL "$imageBase/full/$($Case.ExpectedOg)/0/default.jpg" 'OG URL must reflect the successful download'
        Assert-Equal $data.ImageURLLarge "$imageBase/full/$($Case.ExpectedX)/0/default.jpg" 'X URL must reflect the successful download'
        Assert-Equal $data.ArtworkID $response.data[0].id 'Artwork selection must be preserved'
        Assert-Equal $data.LocalImage 'artwork.jpg' 'OG filename must be preserved'
        Assert-Equal $data.LocalImageX 'artwork_x.jpg' 'X filename must be preserved'
        foreach ($imageName in @('artwork.jpg', 'artwork_x.jpg')) {
            $imagePath = Join-Path $fixture $imageName
            if ((Get-Item -LiteralPath $imagePath).Length -le 0) { throw "Empty image: $imagePath" }
            if ($Case.LiveArtwork) {
                Add-Type -AssemblyName System.Drawing
                $image = [System.Drawing.Image]::FromFile($imagePath)
                try {
                    $dimensions += "$imageName=$($image.Width)x$($image.Height)"
                    $expectedWidth = if ($imageName -eq 'artwork.jpg') { $Case.OgPixels } else { $Case.XPixels }
                    Assert-Equal $image.Width $expectedWidth 'Live JPEG width must match the requested or native size'
                }
                finally { $image.Dispose() }
            }
        }
        & (Join-Path $scripts 'ReadMeUpdater.ps1')
        $readme = Get-Content -LiteralPath (Join-Path $fixture 'README.md') -Raw
        if (-not $readme.Contains('src="' + $data.ImageURLLarge + '"')) { throw 'README must use the successful X URL' }
        if (-not $readme.Contains('Fixture documentation.')) { throw 'README documentation was lost' }
    }
    Assert-Equal $requests.Count $Case.ExpectedRequests 'Unexpected number of image requests'
    $results.Add([pscustomobject]@{ Case = $Case.Name; Result = 'PASS'; Requests = $requests.ToArray(); Dimensions = $dimensions; Fixture = $fixture })
    Write-Host "PASS: $($Case.Name)"
}

$cases = @(
    @{ Name = 'artwork-170-width'; SourceWidth = 1097; ActualWidth = 1097; ExpectedOg = '843,'; ExpectedX = '1097,'; ExpectedRequests = 2 },
    @{ Name = 'below-both-targets'; SourceWidth = 500; ActualWidth = 500; ExpectedOg = '500,'; ExpectedX = '500,'; ExpectedRequests = 2 },
    @{ Name = 'at-og-target'; SourceWidth = 843; ActualWidth = 843; ExpectedOg = '843,'; ExpectedX = '843,'; ExpectedRequests = 2 },
    @{ Name = 'at-x-target'; SourceWidth = 1200; ActualWidth = 1200; ExpectedOg = '843,'; ExpectedX = '1200,'; ExpectedRequests = 2 },
    @{ Name = 'larger-source'; SourceWidth = 2400; ActualWidth = 2400; ExpectedOg = '843,'; ExpectedX = '1200,'; ExpectedRequests = 2 },
    @{ Name = 'info-unavailable'; InfoUnavailable = $true; ActualWidth = 1097; ExpectedOg = '843,'; ExpectedX = 'pct:100'; ExpectedRequests = 3 },
    @{ Name = 'info-unavailable-small-source'; InfoUnavailable = $true; ActualWidth = 500; ExpectedOg = 'pct:100'; ExpectedX = 'pct:100'; ExpectedRequests = 4 },
    @{ Name = 'info-unavailable-large-source'; InfoUnavailable = $true; ActualWidth = 2400; ExpectedOg = '843,'; ExpectedX = '1200,'; ExpectedRequests = 2 },
    @{ Name = 'stale-source-width'; SourceWidth = 2400; ActualWidth = 1097; ExpectedOg = '843,'; ExpectedX = 'pct:100'; ExpectedRequests = 3 },
    @{ Name = 'unrelated-403'; SourceWidth = 2400; DownloadStatus = 403; ExpectedFailure = 'Access denied'; ExpectedRequests = 1 },
    @{ Name = 'missing-image-404'; SourceWidth = 2400; DownloadStatus = 404; ExpectedFailure = 'Access denied'; ExpectedRequests = 1 },
    @{ Name = 'server-error-500'; SourceWidth = 2400; DownloadStatus = 500; ExpectedFailure = 'server error'; ExpectedRequests = 1 },
    @{ Name = 'download-timeout'; SourceWidth = 2400; DownloadFailure = 'Timeout'; ExpectedFailure = 'timeout'; ExpectedRequests = 1 },
    @{ Name = 'native-download-failure'; SourceWidth = 2400; ActualWidth = 500; NativeFailure = $true; ExpectedFailure = 'ScaleRestrictedException'; ExpectedRequests = 2 },
    @{ Name = 'empty-download'; SourceWidth = 2400; ActualWidth = 2400; EmptyDownload = $true; ExpectedFailure = 'missing or empty'; ExpectedRequests = 1 }
)
foreach ($width in @($null, 0, -1, 'invalid', '1097.5', '2147483648')) {
    $cases += @{ Name = "invalid-width-$($cases.Count)"; SourceWidth = $width; ActualWidth = 1097; ExpectedOg = '843,'; ExpectedX = 'pct:100'; ExpectedRequests = 3 }
}
foreach ($case in $cases) { Invoke-TestCase $case }
if ($Live) {
    Invoke-TestCase @{ Name = 'live-artwork-170'; LiveArtwork = 170; ExpectedOg = '843,'; ExpectedX = '1097,'; OgPixels = 843; XPixels = 1097; ExpectedRequests = 2 }
    Invoke-TestCase @{ Name = 'live-artwork-81548'; LiveArtwork = 81548; ExpectedOg = '843,'; ExpectedX = '1200,'; OgPixels = 843; XPixels = 1200; ExpectedRequests = 2 }
    Invoke-TestCase @{ Name = 'live-artwork-170-without-info'; LiveArtwork = 170; InfoUnavailable = $true; ExpectedOg = '843,'; ExpectedX = 'pct:100'; OgPixels = 843; XPixels = 1097; ExpectedRequests = 3 }
}
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $testRoot 'results.json') -Encoding UTF8
Write-Host "$($results.Count) tests passed. Evidence: $testRoot"
