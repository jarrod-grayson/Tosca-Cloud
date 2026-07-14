#Requires -Version 3.0
<#
    Publish-ToscaStepDetails.ps1
    ----------------------------------------------------------------------------
    Runs AFTER your existing execution-client + PublishTestResults@2 steps.
    It does NOT touch or depend on internals of tosca_cloud_execution_client.ps1.

    What it does:
      1. Authenticates (client credentials) - same pattern as your client script.
      2. Re-derives the playlist RUN id (latest run for the given playlist name),
         unless you pass -PlaylistRunId explicitly.
      3. Lists test case runs for that run (paginated) and keeps the FAILED ones.
      4. For each failed test case run: GET .../testSteps -> contentDownloadUri
         -> downloads the TestSteps.json (tries anonymous first, then bearer).
      5. Renders one self-contained HTML report per failed test case.
      6. Publishes a folder of reports + a Markdown summary tab, and (optionally)
         attaches each HTML to the matching FAILED test result in the Tests tab.

    Design notes:
      * Best-effort: this script never flips your pass/fail. It always exits 0
        and only writes warnings on problems, so it can't turn a red run green.
      * The TestSteps.json schema is not published, so the HTML renderer is
        schema-agnostic (recursively renders whatever JSON comes back and
        colour-codes anything that looks like a status/result field). Refine
        New-StepHtml once you've seen a real payload.
#>

param(
    [string]   $BaseUrl,
    [string]   $SpaceId,
    [string]   $ClientId,
    [string]   $ClientSecret,
    [string]   $TokenUrl,
    [string]   $BearerToken     = "",
    [string]   $PlaylistName,
    [string]   $PlaylistRunId   = "",                    # optional explicit override
    [string]   $OutputDir       = "$env:BUILD_ARTIFACTSTAGINGDIRECTORY\ToscaStepReports",
    [int]      $ItemsPerPage    = 200,
    [int]      $RequestTimeout  = 60,
    [string[]] $FailedStates    = @('failed'),           # add 'unknown','canceled' if you want them treated as failures
    [bool]     $AttachToTestResults = $true
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Info  { param([string]$m) Write-Host "[$(Get-Date -f 'HH:mm:ss')] [INFO]  $m" -ForegroundColor Cyan }
function Write-Warn2 { param([string]$m) Write-Host "[$(Get-Date -f 'HH:mm:ss')] [WARN]  $m" -ForegroundColor Yellow }
function Write-Err2  { param([string]$m) Write-Host "[$(Get-Date -f 'HH:mm:ss')] [ERROR] $m" -ForegroundColor Red }

# --------------------------------------------------------------------------
# Auth
# --------------------------------------------------------------------------
function Get-Token {
    param([string]$TokenUrl,[string]$ClientId,[string]$ClientSecret,[int]$Timeout)
    $headers = @{ 'Accept'='application/json'; 'Content-Type'='application/x-www-form-urlencoded' }
    $body = "client_id=$ClientId&client_secret=$([uri]::EscapeDataString($ClientSecret))&grant_type=client_credentials"
    $resp = Invoke-RestMethod -Uri $TokenUrl -Method Post -Headers $headers -Body $body -TimeoutSec $Timeout
    if (-not $resp.access_token) { throw "No access_token returned from $TokenUrl" }
    return $resp.access_token
}

function Invoke-Api {
    # small wrapper with one retry on 429/5xx
    param([string]$Uri,[hashtable]$Headers,[int]$Timeout)
    for ($try = 1; $try -le 3; $try++) {
        try {
            return Invoke-RestMethod -Uri $Uri -Method Get -Headers $Headers -TimeoutSec $Timeout
        } catch {
            $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
            if (($code -eq 429 -or $code -ge 500) -and $try -lt 3) {
                Write-Warn2 "GET $Uri returned $code; retry $try after backoff..."
                Start-Sleep -Seconds (5 * $try); continue
            }
            throw
        }
    }
}

# --------------------------------------------------------------------------
# Resolve the playlist RUN id (latest run for the playlist name)
# --------------------------------------------------------------------------
function Resolve-PlaylistRunId {
    param([string]$BaseUrl,[string]$SpaceId,[string]$Token,[string]$PlaylistName,[int]$Timeout)
    $url = "$BaseUrl/$SpaceId/_playlists/api/v2/playlistRuns?sort=desc(createdAt)&itemsPerPage=2000"
    $headers = @{ 'Accept'='application/json'; 'Authorization'="Bearer $Token" }
    $resp = Invoke-Api -Uri $url -Headers $headers -Timeout $Timeout
    $items = if ($resp.items) { $resp.items } else { @($resp) }
    $match = $items | Where-Object { $_.playlistName -and ($_.playlistName -ieq $PlaylistName) } |
                      Sort-Object { [datetime]$_.createdAt } -Descending | Select-Object -First 1
    if (-not $match) { throw "No playlist run found for playlist name '$PlaylistName'." }
    Write-Info "Resolved run id $($match.id) (state=$($match.state), createdAt=$($match.createdAt))"
    return $match.id
}

# --------------------------------------------------------------------------
# List FAILED test case runs for a run (paginated)
# --------------------------------------------------------------------------
function Get-FailedTestCaseRuns {
    param([string]$BaseUrl,[string]$SpaceId,[string]$Token,[string]$RunId,[int]$PerPage,[string[]]$States,[int]$Timeout)
    $headers = @{ 'Accept'='application/json'; 'Authorization'="Bearer $Token" }
    $all = @(); $pageToken = $null
    do {
        $url = "$BaseUrl/$SpaceId/_playlists/api/v2/testCaseRuns?playlistRunId=$RunId&itemsPerPage=$PerPage"
        if ($pageToken) { $url += "&pageToken=$([uri]::EscapeDataString($pageToken))" }
        $resp = Invoke-Api -Uri $url -Headers $headers -Timeout $Timeout
        if ($resp.items) { $all += $resp.items }
        $pageToken = $resp.nextPageToken
    } while ($pageToken)
    Write-Info "Found $($all.Count) test case run(s) in total."
    $failed = $all | Where-Object { $_.state -and ($States -contains $_.state.ToString().ToLower()) }
    Write-Info "$($failed.Count) failed (states: $($States -join ', '))."
    return ,$failed
}

# --------------------------------------------------------------------------
# testSteps metadata -> download the TestSteps.json (anon first, then bearer)
# --------------------------------------------------------------------------
function Get-TestStepsJson {
    param([string]$BaseUrl,[string]$SpaceId,[string]$Token,[string]$TcrId,[int]$Timeout)
    $metaUrl = "$BaseUrl/$SpaceId/_playlists/api/v2/testCaseRuns/$TcrId/testSteps"
    $headers = @{ 'Accept'='application/json'; 'Authorization'="Bearer $Token" }
    try {
        $meta = Invoke-RestMethod -Uri $metaUrl -Method Get -Headers $headers -TimeoutSec $Timeout
    } catch {
        $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        if ($code -eq 404) { Write-Warn2 "No testSteps attachment for $TcrId (404)."; return $null }
        throw
    }
    if (-not $meta.contentDownloadUri) { Write-Warn2 "testSteps for $TcrId had no contentDownloadUri."; return $null }

    # Pre-signed URL: try WITHOUT the bearer header first.
    try {
        $raw = Invoke-WebRequest -Uri $meta.contentDownloadUri -Method Get -TimeoutSec $Timeout -UseBasicParsing
        return ($raw.Content | ConvertFrom-Json)
    } catch {
        Write-Warn2 "Anonymous download failed for $TcrId; retrying with bearer token."
        try {
            $raw = Invoke-WebRequest -Uri $meta.contentDownloadUri -Method Get -Headers $headers -TimeoutSec $Timeout -UseBasicParsing
            return ($raw.Content | ConvertFrom-Json)
        } catch {
            Write-Warn2 "Could not download step JSON for $TcrId : $($_.Exception.Message)"
            return $null
        }
    }
}

# --------------------------------------------------------------------------
# HTML rendering (schema-agnostic recursive renderer)
# --------------------------------------------------------------------------
function ConvertTo-SafeHtml { param($v)
    if ($null -eq $v) { return "" }
    return ([string]$v).Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}

function Get-StatusClass { param([string]$key,[string]$val)
    $k = "$key".ToLower(); $t = "$val".ToLower()
    if ($k -match 'status|result|state|outcome|passed') {
        if ($t -match 'fail|error|abort|not.?ok|false') { return 'bad' }
        if ($t -match 'pass|ok|success|true|done')       { return 'good' }
    }
    return ''
}

function Render-JsonNode { param($node,[string]$keyName = "")
    $sb = New-Object System.Text.StringBuilder
    if ($node -is [System.Collections.IEnumerable] -and -not ($node -is [string])) {
        [void]$sb.Append('<ul>')
        $i = 0
        foreach ($item in $node) {
            [void]$sb.Append("<li><span class='idx'>[$i]</span> " + (Render-JsonNode -node $item) + "</li>")
            $i++
        }
        [void]$sb.Append('</ul>')
    }
    elseif ($node -is [psobject] -and $node.PSObject.Properties.Name.Count -gt 0) {
        [void]$sb.Append('<ul>')
        foreach ($p in $node.PSObject.Properties) {
            $cls = Get-StatusClass -key $p.Name -val $p.Value
            $badge = if ($cls) { " <span class='badge $cls'>$(ConvertTo-SafeHtml $p.Value)</span>" } else { "" }
            $isLeaf = -not ($p.Value -is [psobject]) -and -not ($p.Value -is [System.Collections.IEnumerable] -and -not ($p.Value -is [string]))
            if ($isLeaf) {
                if ($cls) {
                    [void]$sb.Append("<li><span class='key'>$(ConvertTo-SafeHtml $p.Name)</span>:$badge</li>")
                } else {
                    [void]$sb.Append("<li><span class='key'>$(ConvertTo-SafeHtml $p.Name)</span>: <span class='val'>$(ConvertTo-SafeHtml $p.Value)</span></li>")
                }
            } else {
                [void]$sb.Append("<li><details open><summary><span class='key'>$(ConvertTo-SafeHtml $p.Name)</span></summary>" + (Render-JsonNode -node $p.Value -keyName $p.Name) + "</details></li>")
            }
        }
        [void]$sb.Append('</ul>')
    }
    else {
        [void]$sb.Append("<span class='val'>$(ConvertTo-SafeHtml $node)</span>")
    }
    return $sb.ToString()
}

function New-StepHtml { param($TestCaseRun,$StepJson)
    $title = if ($TestCaseRun.displayName) { $TestCaseRun.displayName } else { $TestCaseRun.testCaseId }
    $bodyInner = if ($StepJson) { Render-JsonNode -node $StepJson } else { "<p class='note'>No step-level attachment was available for this test case run.</p>" }
    $css = @"
<style>
 body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:0;padding:24px;color:#1b1f24;background:#fff;font-size:14px;line-height:1.5}
 h1{font-size:18px;margin:0 0 4px} .sub{color:#5b6570;margin:0 0 16px;font-size:12px}
 .hdr{border-left:4px solid #d1242f;background:#fff5f5;padding:12px 16px;border-radius:6px;margin-bottom:20px}
 ul{list-style:none;margin:4px 0;padding-left:18px;border-left:1px solid #e6e8eb}
 li{margin:2px 0} .key{color:#0550ae;font-weight:600} .val{color:#24292f;font-family:ui-monospace,Consolas,monospace}
 .idx{color:#8b949e;font-family:ui-monospace,Consolas,monospace}
 summary{cursor:pointer} details{margin:2px 0}
 .badge{display:inline-block;padding:1px 8px;border-radius:10px;font-size:12px;font-weight:600}
 .badge.bad{background:#ffebe9;color:#d1242f} .badge.good{background:#dafbe1;color:#1a7f37}
 .note{color:#5b6570;font-style:italic}
</style>
"@
    return @"
<!doctype html><html><head><meta charset="utf-8"><title>$([System.Web.HttpUtility]::HtmlEncode($title)) - Step detail</title>$css</head>
<body>
 <div class="hdr">
   <h1>$([System.Web.HttpUtility]::HtmlEncode($title))</h1>
   <p class="sub">State: <b>$($TestCaseRun.state)</b> &nbsp;|&nbsp; Test case run: $($TestCaseRun.id) &nbsp;|&nbsp; Test case: $($TestCaseRun.testCaseId)</p>
 </div>
 $bodyInner
</body></html>
"@
}

# --------------------------------------------------------------------------
# Azure DevOps Test REST helpers (attach HTML to failed results)
# --------------------------------------------------------------------------
function Get-AdoFailedResults {
    param([string]$Collection,[string]$Project,[string]$BuildId,[string]$AdoToken)
    $h = @{ 'Authorization'="Bearer $AdoToken"; 'Accept'='application/json' }
    $buildUri = [uri]::EscapeDataString("vstfs:///Build/Build/$BuildId")
    $runsUrl  = "$Collection$Project/_apis/test/runs?buildUri=$buildUri&api-version=7.1"
    $runs = Invoke-RestMethod -Uri $runsUrl -Method Get -Headers $h
    if (-not $runs.value -or $runs.value.Count -eq 0) { Write-Warn2 "No ADO test runs found for build $BuildId."; return @() }
    $results = @()
    foreach ($r in $runs.value) {
        $resUrl = "$Collection$Project/_apis/test/Runs/$($r.id)/results?outcomes=Failed&`$top=1000&api-version=7.1"
        $res = Invoke-RestMethod -Uri $resUrl -Method Get -Headers $h
        foreach ($item in $res.value) {
            $results += [pscustomobject]@{ RunId=$r.id; ResultId=$item.id; Title=$item.testCaseTitle; AutoName=$item.automatedTestName }
        }
    }
    Write-Info "ADO reports $($results.Count) failed result(s) for this build."
    return $results
}

function Add-AdoAttachment {
    param([string]$Collection,[string]$Project,[string]$AdoToken,[string]$RunId,[string]$ResultId,[string]$FilePath,[string]$FileName)
    $h = @{ 'Authorization'="Bearer $AdoToken"; 'Content-Type'='application/json' }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($FilePath))
    $body = @{ attachmentType='GeneralAttachment'; fileName=$FileName; comment='Tosca step-level detail'; stream=$b64 } | ConvertTo-Json
    $url  = "$Collection$Project/_apis/test/Runs/$RunId/Results/$ResultId/attachments?api-version=7.1"
    Invoke-RestMethod -Uri $url -Method Post -Headers $h -Body $body | Out-Null
}

# ==========================================================================
# MAIN  (best-effort: always exits 0)
# ==========================================================================
try {
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

    if ([string]::IsNullOrEmpty($BearerToken)) {
        $BearerToken = Get-Token -TokenUrl $TokenUrl -ClientId $ClientId -ClientSecret $ClientSecret -Timeout $RequestTimeout
    }

    if ([string]::IsNullOrEmpty($PlaylistRunId)) {
        $PlaylistRunId = Resolve-PlaylistRunId -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -PlaylistName $PlaylistName -Timeout $RequestTimeout
    }

    $failedRuns = Get-FailedTestCaseRuns -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -RunId $PlaylistRunId -PerPage $ItemsPerPage -States $FailedStates -Timeout $RequestTimeout

    if (-not $failedRuns -or $failedRuns.Count -eq 0) {
        Write-Info "No failed test case runs - nothing to enrich."
        exit 0
    }

    # displayName (lower) -> html path, for later matching to ADO results
    $nameToHtml = @{}
    $reportIndex = @()
    foreach ($tcr in $failedRuns) {
        $safe   = ($tcr.displayName, $tcr.testCaseId -ne $null)[0]
        $safe   = ($safe -replace '[^\w\-]+','_').Trim('_'); if (-not $safe) { $safe = $tcr.id }
        $file   = Join-Path $OutputDir ("FAILED_{0}_{1}.html" -f $safe, $tcr.id)
        $json   = Get-TestStepsJson -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -TcrId $tcr.id -Timeout $RequestTimeout
        (New-StepHtml -TestCaseRun $tcr -StepJson $json) | Out-File -FilePath $file -Encoding UTF8
        Write-Info "Rendered $file"
        if ($tcr.displayName) { $nameToHtml[$tcr.displayName.ToLower()] = $file }
        $reportIndex += [pscustomobject]@{ Name=$tcr.displayName; State=$tcr.state; File=(Split-Path $file -Leaf) }
    }

    # Markdown summary tab
    $md = "# Tosca failed tests - step detail`n`nPlaylist run: ``$PlaylistRunId```n`n| Test case | State | Report |`n|---|---|---|`n"
    foreach ($r in $reportIndex) { $md += "| $($r.Name) | $($r.State) | $($r.File) |`n" }
    $mdPath = Join-Path $OutputDir "_summary.md"
    $md | Out-File -FilePath $mdPath -Encoding UTF8
    Write-Host "##vso[task.uploadsummary]$mdPath"

    # Attach to failed ADO results
    if ($AttachToTestResults) {
        $collection = $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
        $project    = $env:SYSTEM_TEAMPROJECT
        $buildId    = $env:BUILD_BUILDID
        $adoToken   = $env:SYSTEM_ACCESSTOKEN
        if ([string]::IsNullOrEmpty($adoToken)) {
            Write-Warn2 "SYSTEM_ACCESSTOKEN not available - skipping per-result attachments. (Set env SYSTEM_ACCESSTOKEN: `$(System.AccessToken) and grant the build service Test-Manage permission.) Reports are still published as an artifact."
        } else {
            $adoFailed = Get-AdoFailedResults -Collection $collection -Project $project -BuildId $buildId -AdoToken $adoToken
            $attached = 0
            foreach ($res in $adoFailed) {
                $key = "$($res.Title)".ToLower()
                if ($nameToHtml.ContainsKey($key)) {
                    try {
                        Add-AdoAttachment -Collection $collection -Project $project -AdoToken $adoToken -RunId $res.RunId -ResultId $res.ResultId -FilePath $nameToHtml[$key] -FileName "ToscaStepDetail.html"
                        $attached++
                    } catch { Write-Warn2 "Attach failed for '$($res.Title)': $($_.Exception.Message)" }
                } else {
                    Write-Warn2 "No rendered report matched ADO result title '$($res.Title)' (name-matching mismatch)."
                }
            }
            Write-Info "Attached $attached report(s) to failed test results."
        }
    }

    exit 0
}
catch {
    Write-Err2 "Enrichment step failed (non-fatal): $($_.Exception.Message)"
    exit 0   # never change the job's pass/fail outcome
}
