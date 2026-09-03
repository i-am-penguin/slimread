<#
    Tells Bing, DuckDuckGo and Yandex to re-crawl the site, now, instead of waiting
    for them to come round on their own schedule.

    Run this after publishing a change to anything under docs/. It is not needed for
    changes to tweaks/ or the app - those reach the phone directly and are not pages
    a search engine indexes.

        powershell -ExecutionPolicy Bypass -File .\Ping-IndexNow.ps1

    WHAT THIS DOES NOT COVER: Google. Google trialled IndexNow and does not use it,
    so Google discovery still depends on Search Console and on ordinary crawling.
    There is no equivalent no-account ping for Google.

    HOW IT WORKS: IndexNow proves you own the site by asking you to host a file whose
    name and contents are the same secret key. docs/<key>.txt is that file. Because
    the site lives on a subpath rather than the root of the host, the key file sits
    beside the pages and `keyLocation` points at it - IndexNow then accepts any URL at
    or below that file's directory, which is every page this site has.

    IF THE KEY IS EVER ROTATED: change $Key below, rename docs/<key>.txt to match on
    BOTH sides, and push before running this again. A key that does not match the
    hosted file is rejected.
#>

$ErrorActionPreference = 'Stop'

$Key      = 'c074d34cf0890a1e22bbd2db959f0fc5'
$Host_    = 'i-am-penguin.github.io'
$Base     = "https://$Host_/slimread"
$KeyUrl   = "$Base/$Key.txt"

# Every page worth indexing. Assets (CSS, images) are not submitted - search engines
# fetch those themselves when they crawl the page that references them.
$Urls = @(
    "$Base/"
    "$Base/faq.html"
)

Write-Host ''
Write-Host '  IndexNow - asking Bing / DuckDuckGo / Yandex to re-crawl' -ForegroundColor Cyan
Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray

# Check the key file is actually reachable first. If it is not, every submission
# below would be rejected and the endpoint gives no useful reason, so it is worth
# failing here with something readable instead.
try {
    $served = (Invoke-WebRequest -Uri $KeyUrl -UseBasicParsing -TimeoutSec 20).Content.Trim()
} catch {
    Write-Host ''
    Write-Host "  STOPPED: could not fetch $KeyUrl" -ForegroundColor Red
    Write-Host '  The key file is not published yet. Commit and push docs/, wait for' -ForegroundColor Yellow
    Write-Host '  GitHub Pages to rebuild, then run this again.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

if ($served -ne $Key) {
    Write-Host ''
    Write-Host '  STOPPED: the hosted key does not match $Key in this script.' -ForegroundColor Red
    Write-Host "    hosted:   $served" -ForegroundColor Yellow
    Write-Host "    expected: $Key" -ForegroundColor Yellow
    Write-Host '  Make the two agree, push, then run this again.' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}
Write-Host '    [ok] key file is published and matches' -ForegroundColor Green

foreach ($u in $Urls) {
    $endpoint = 'https://api.indexnow.org/indexnow' +
                "?url=$([uri]::EscapeDataString($u))" +
                "&key=$Key" +
                "&keyLocation=$([uri]::EscapeDataString($KeyUrl))"
    try {
        $r = Invoke-WebRequest -Uri $endpoint -UseBasicParsing -TimeoutSec 20
        # 200 accepted, 202 accepted but the key is still being verified. Both are fine.
        Write-Host "    [ok] $($r.StatusCode)  $u" -ForegroundColor Green
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        Write-Host "    [!] $code  $u" -ForegroundColor Yellow
        if ($code -eq 422) { Write-Host '         422 = URL does not match the key location.' -ForegroundColor DarkGray }
        if ($code -eq 403) { Write-Host '         403 = key rejected. Check the hosted file.' -ForegroundColor DarkGray }
        if ($code -eq 429) { Write-Host '         429 = too many requests. Try again later.' -ForegroundColor DarkGray }
    }
}

Write-Host ''
Write-Host '  Submitted. Crawling is still their decision and their timing -' -ForegroundColor Gray
Write-Host '  this removes the waiting, not the queue.' -ForegroundColor Gray
Write-Host ''
