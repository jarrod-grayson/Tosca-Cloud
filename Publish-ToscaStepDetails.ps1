#Requires -Version 3.0
<#
    Publish-ToscaStepDetails.ps1  (v2 - schema-aware renderer)
    ----------------------------------------------------------------------------
    Runs AFTER your existing execution-client + PublishTestResults@2 steps.
    Does NOT depend on internals of tosca_cloud_execution_client.ps1.

    v2 changes vs v1:
      * New-StepHtml now renders the real TestSteps.json schema as a collapsible
        step tree (state pills, action-mode tags, durations).
      * verify steps show Expected vs Actual side-by-side and highlight mismatches.
      * The failing path auto-expands; passing branches start collapsed.
      * Secret-looking values (password/token/secret/apikey) are masked.
      * Markdown summary now has status emoji + a failed-count header.
      * Pipe characters in the Markdown table are escaped (Escape-Md).

    Best-effort: always exits 0 so it can never flip your job's pass/fail.
#>

param(
    [string]   $BaseUrl,
    [string]   $SpaceId,
    [string]   $PortalBaseUrl = "",
    [string]   $SpaceName     = "",
    [string]   $ClientId,
    [string]   $ClientSecret,
    [string]   $TokenUrl,
    [string]   $BearerToken     = "",
    [string]   $PlaylistName,
    [string]   $PlaylistRunId   = "",
    [string]   $OutputDir       = "$env:BUILD_ARTIFACTSTAGINGDIRECTORY\ToscaStepReports",
    [int]      $ItemsPerPage    = 200,
    [int]      $RequestTimeout  = 60,
    [string[]] $FailedStates    = @('failed'),
    [bool]     $AttachToTestResults = $true
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Info  { param([string]$m) Write-Host "[$(Get-Date -f 'HH:mm:ss')] [INFO]  $m" -ForegroundColor Cyan }
function Write-Warn2 { param([string]$m) Write-Host "[$(Get-Date -f 'HH:mm:ss')] [WARN]  $m" -ForegroundColor Yellow }
function Write-Err2  { param([string]$m) Write-Host "[$(Get-Date -f 'HH:mm:ss')] [ERROR] $m" -ForegroundColor Red }

# --------------------------------------------------------------------------
# Auth / API
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
    param([string]$Uri,[hashtable]$Headers,[int]$Timeout)
    for ($try = 1; $try -le 3; $try++) {
        try { return Invoke-RestMethod -Uri $Uri -Method Get -Headers $Headers -TimeoutSec $Timeout }
        catch {
            $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
            if (($code -eq 429 -or $code -ge 500) -and $try -lt 3) {
                Write-Warn2 "GET $Uri returned $code; retry $try after backoff..."; Start-Sleep -Seconds (5 * $try); continue
            }
            throw
        }
    }
}

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

function Get-TestStepsJson {
    param([string]$BaseUrl,[string]$SpaceId,[string]$Token,[string]$TcrId,[int]$Timeout)
    $metaUrl = "$BaseUrl/$SpaceId/_playlists/api/v2/testCaseRuns/$TcrId/testSteps"
    $headers = @{ 'Accept'='application/json'; 'Authorization'="Bearer $Token" }
    try { $meta = Invoke-RestMethod -Uri $metaUrl -Method Get -Headers $headers -TimeoutSec $Timeout }
    catch {
        $code = try { [int]$_.Exception.Response.StatusCode } catch { 0 }
        if ($code -eq 404) { Write-Warn2 "No testSteps attachment for $TcrId (404)."; return $null }
        throw
    }
    if (-not $meta.contentDownloadUri) { Write-Warn2 "testSteps for $TcrId had no contentDownloadUri."; return $null }
    try {
        $raw = Invoke-WebRequest -Uri $meta.contentDownloadUri -Method Get -TimeoutSec $Timeout -UseBasicParsing
        return ($raw.Content | ConvertFrom-Json)
    } catch {
        Write-Warn2 "Anonymous download failed for $TcrId; retrying with bearer token."
        try {
            $raw = Invoke-WebRequest -Uri $meta.contentDownloadUri -Method Get -Headers $headers -TimeoutSec $Timeout -UseBasicParsing
            return ($raw.Content | ConvertFrom-Json)
        } catch { Write-Warn2 "Could not download step JSON for $TcrId : $($_.Exception.Message)"; return $null }
    }
}

# --------------------------------------------------------------------------
# Rendering helpers
# --------------------------------------------------------------------------
function ConvertTo-SafeHtml { param($v)
    if ($null -eq $v) { return "" }
    return ([string]$v).Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('"','&quot;')
}

function Format-Duration { param([string]$d)
    if ([string]::IsNullOrEmpty($d)) { return "" }
    try { $ts = [TimeSpan]::Parse($d) } catch { return $d }
    if     ($ts.TotalSeconds -ge 60) { return ("{0}m {1:0}s" -f [int][math]::Floor($ts.TotalMinutes), $ts.Seconds) }
    elseif ($ts.TotalSeconds -ge 1)  { return ("{0:0.0}s"    -f $ts.TotalSeconds) }
    else                             { return ("{0:0}ms"     -f $ts.TotalMilliseconds) }
}

function Test-ContainsFailure { param($step)
    if ("$($step.state)".ToLower() -eq 'failed') { return $true }
    foreach ($c in @($step.innerSteps)) { if ($c -and (Test-ContainsFailure $c)) { return $true } }
    return $false
}

function Add-LeafCount { param($step,$acc)
    $kids = @($step.innerSteps)
    if ($kids.Count -eq 0) {
        switch ("$($step.state)".ToLower()) { 'ok' { $acc.ok++ } 'failed' { $acc.fail++ } default { $acc.other++ } }
    } else { foreach ($c in $kids) { Add-LeafCount $c $acc } }
}

function Get-VerifyParts { param([string]$msg)
    $expected = $null; $actual = $null; $headline = $null
    if ($msg) {
        $lines = $msg -split "`r?`n"
        $headline = $lines[0].Trim()
        foreach ($l in $lines) {
            if     ($l -match 'Expected value\s*==\s*(.*)$') { $expected = $Matches[1].Trim().Trim('"') }
            elseif ($l -match 'Actual value:\s*(.*)$')       { $actual   = $Matches[1].Trim().Trim('"') }
        }
    }
    return [pscustomobject]@{ Headline=$headline; Expected=$expected; Actual=$actual }
}

function Test-IsSecret { param($step)
    $probe = "$($step.name) $($step.value)"
    return ($probe -match '(?i)pass(word|wd)?|secret|token|api[-_ ]?key|credential')
}

function Get-StepBody { param($step)
    $sb = New-Object System.Text.StringBuilder
    $mode = "$($step.actionMode)".ToLower()
    if ($mode -eq 'verify' -and $step.message -match 'Expected value') {
        $v = Get-VerifyParts $step.message
        $vcls = if ("$($step.state)".ToLower() -eq 'failed') { 'fail' } else { 'ok' }
        $exp = if ([string]::IsNullOrEmpty($v.Expected)) { "<em>(empty)</em>" } else { ConvertTo-SafeHtml $v.Expected }
        $act = if ([string]::IsNullOrEmpty($v.Actual))   { "<em>(empty)</em>" } else { ConvertTo-SafeHtml $v.Actual }
        [void]$sb.Append("<div class='verify $vcls'><div class='cmp'><span class='lbl'>Expected</span><code>$exp</code></div><div class='cmp'><span class='lbl'>Actual</span><code>$act</code></div></div>")
    } else {
        $secret = Test-IsSecret $step
        $parts = @()
        if ($step.value) {
            $vv = if ($secret) { '&bull;&bull;&bull;&bull;&bull;' } else { ConvertTo-SafeHtml $step.value }
            $parts += "<span class='kv'><span class='lbl'>Value</span><code>$vv</code></span>"
        }
        if ($step.usedValue) {
            $uv = if ($secret) { '&bull;&bull;&bull;&bull;&bull; <span class="masked">(masked)</span>' } else { ConvertTo-SafeHtml $step.usedValue }
            $parts += "<span class='kv'><span class='lbl'>Used</span><code>$uv</code></span>"
        }
        if ($parts.Count) { [void]$sb.Append("<div class='vals'>" + ($parts -join "") + "</div>") }
        if ($step.message) { [void]$sb.Append("<div class='msg'>$(ConvertTo-SafeHtml $step.message)</div>") }
    }
    if ($step.details) { [void]$sb.Append("<div class='det'>$(ConvertTo-SafeHtml $step.details)</div>") }
    return $sb.ToString()
}

function Get-StepHtmlNode { param($step)
    $state = "$($step.state)".ToLower()
    $cls   = switch ($state) { 'ok' { 'ok' } 'failed' { 'fail' } default { 'skip' } }
    $pill  = switch ($state) { 'ok' { 'OK' } 'failed' { 'FAIL' } default { $state.ToUpper() } }
    $dur   = Format-Duration $step.duration
    $name  = ConvertTo-SafeHtml $step.name
    $mode  = if ($step.actionMode) { "<span class='mode m-$([string]$step.actionMode)'>$(ConvertTo-SafeHtml $step.actionMode)</span>" } else { "" }
    $head  = "<span class='pill $cls'>$pill</span> <span class='nm'>$name</span> $mode <span class='dur'>$dur</span>"
    $body  = Get-StepBody $step
    $kids  = @($step.innerSteps)
    if ($kids.Count -gt 0) {
        $open  = if (Test-ContainsFailure $step) { ' open' } else { '' }
        $inner = ($kids | ForEach-Object { Get-StepHtmlNode $_ }) -join ""
        return "<details class='step $cls'$open><summary>$head</summary><div class='kids'>$body$inner</div></details>"
    } else {
        return "<div class='step leaf $cls'><div class='hd'>$head</div>$body</div>"
    }
}

function New-StepHtml { param($TestCaseRun,$StepJson,$PortalBaseUrl,$SpaceName,$PlaylistRunId)
    $title = if ($TestCaseRun.displayName) { $TestCaseRun.displayName } else { $TestCaseRun.testCaseId }
    $st    = "$($TestCaseRun.state)".ToLower()
    $hcls  = if ($st -eq 'failed') { 'fail' } elseif ($st -in @('succeeded','ok','passed')) { 'ok' } else { 'skip' }

    $chips = ""; $meta = ""; $tree = "<p class='note'>No step-level attachment was available for this test case run.</p>"
    if ($StepJson) {
        $roots = @($StepJson)
        $acc = [pscustomobject]@{ ok=0; fail=0; other=0 }
        foreach ($r in $roots) { Add-LeafCount $r $acc }
        $chips = "<span class='chip ok'>$($acc.ok) passed</span><span class='chip fail'>$($acc.fail) failed</span>"
        if ($acc.other) { $chips += "<span class='chip skip'>$($acc.other) other</span>" }
        if ($roots[0].startTime) { $meta += "Started " + (ConvertTo-SafeHtml $roots[0].startTime) }
        $rootDur = Format-Duration $roots[0].duration
        if ($rootDur) { $meta += " &nbsp;&middot;&nbsp; $rootDur" }
        $treeSteps = if ($roots.Count -eq 1 -and @($roots[0].innerSteps).Count -gt 0) { @($roots[0].innerSteps) } else { $roots }
        $tree = ($treeSteps | ForEach-Object { Get-StepHtmlNode $_ }) -join ""
    }

    $resultLink = ""
    if ($PortalBaseUrl -and $SpaceName -and $PlaylistRunId) {
        $resultUrl = "$PortalBaseUrl/_portal/space/$([uri]::EscapeDataString($SpaceName))/runs/$PlaylistRunId/results/$($TestCaseRun.id)"
        $resultLink = " &nbsp;&middot;&nbsp; <a href='$resultUrl'>Open in Tosca Cloud &rarr;</a>"
    }

    $css = @"
<style>
 :root{--red:#d1242f;--red-bg:#fff5f5;--green:#1a7f37;--green-bg:#eafbf0;--ink:#1b1f24;--mut:#5b6570;--line:#e6e8eb;--mono:ui-monospace,SFMono-Regular,Consolas,monospace}
 *{box-sizing:border-box} body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:0;padding:24px;color:var(--ink);background:#fafbfc;font-size:14px;line-height:1.5}
 .card{max-width:1000px;margin:0 auto}
 header{background:#fff;border:1px solid var(--line);border-left:5px solid var(--red);border-radius:8px;padding:16px 20px;margin-bottom:16px}
 header.ok{border-left-color:var(--green)}
 h1{font-size:20px;margin:0 0 8px;letter-spacing:-.2px}
 .meta{color:var(--mut);font-size:12px;margin-bottom:10px}
 .chip{display:inline-block;padding:2px 10px;border-radius:12px;font-size:12px;font-weight:600;margin-right:6px}
 .chip.ok{background:var(--green-bg);color:var(--green)} .chip.fail{background:var(--red-bg);color:var(--red)} .chip.skip{background:#eef1f4;color:var(--mut)}
 .step{background:#fff;border:1px solid var(--line);border-radius:6px;margin:6px 0}
 details.step>summary{list-style:none;cursor:pointer;padding:8px 12px;display:flex;align-items:center;gap:8px;border-radius:6px}
 details.step>summary::-webkit-details-marker{display:none}
 details.step>summary::before{content:'\25B8';color:var(--mut);font-size:11px;transition:transform .1s} details.step[open]>summary::before{transform:rotate(90deg)}
 .step.leaf .hd{padding:8px 12px;display:flex;align-items:center;gap:8px}
 .step.fail{border-color:#ffc9c9} details.step.fail>summary,.step.leaf.fail .hd{background:var(--red-bg)}
 .kids{padding:2px 10px 8px 24px;border-left:2px solid var(--line);margin-left:14px}
 .pill{font-size:10px;font-weight:700;letter-spacing:.4px;padding:2px 7px;border-radius:4px;color:#fff;flex:none}
 .pill.ok{background:var(--green)} .pill.fail{background:var(--red)} .pill.skip{background:#8b949e}
 .nm{font-weight:600;flex:1;min-width:0}
 .mode{font-size:10px;text-transform:uppercase;letter-spacing:.4px;color:var(--mut);border:1px solid var(--line);border-radius:4px;padding:1px 6px;flex:none}
 .m-verify{color:#0550ae;border-color:#b6d4fe} .m-input{color:#6f42c1;border-color:#e2d4fb} .m-select{color:#57606a}
 .dur{color:var(--mut);font-size:12px;font-family:var(--mono);flex:none}
 .verify{display:flex;gap:10px;margin:6px 0 2px;flex-wrap:wrap} .cmp{flex:1;min-width:220px;border:1px solid var(--line);border-radius:6px;padding:6px 10px;background:#fff}
 .verify.fail .cmp{border-color:#ffc9c9;background:var(--red-bg)} .verify.ok .cmp{background:#fff}
 .lbl{display:block;font-size:10px;text-transform:uppercase;letter-spacing:.5px;color:var(--mut);margin-bottom:2px}
 code{font-family:var(--mono);font-size:12.5px;word-break:break-word} .masked{color:var(--mut);font-style:italic;font-family:inherit}
 .vals{display:flex;gap:16px;flex-wrap:wrap;margin:4px 0} .kv .lbl{display:inline;margin-right:6px}
 .msg{color:var(--mut);font-family:var(--mono);font-size:12px;white-space:pre-wrap;margin:4px 0}
 .det{color:var(--mut);font-size:12px;margin:4px 0} .note{color:var(--mut);font-style:italic}
</style>
"@
    return @"
<!doctype html><html><head><meta charset="utf-8"><title>$(ConvertTo-SafeHtml $title) - Step detail</title>$css</head>
<body><div class="card">
 <header class="$hcls">
   <h1>$(ConvertTo-SafeHtml $title)</h1>
   <div class="meta">State <b>$($TestCaseRun.state)</b> &nbsp;&middot;&nbsp; $meta &nbsp;&middot;&nbsp; run $($TestCaseRun.id)$resultLink</div>
   <div>$chips</div>
 </header>
 $tree
</div></body></html>
"@
}

# --------------------------------------------------------------------------
# Azure DevOps Test REST helpers
# --------------------------------------------------------------------------
function Get-AdoFailedResults {
    param([string]$Collection,[string]$Project,[string]$BuildId,[string]$AdoToken)
    $h = @{ 'Authorization'="Bearer $AdoToken"; 'Accept'='application/json' }
    $buildUri = [uri]::EscapeDataString("vstfs:///Build/Build/$BuildId")
    $runs = Invoke-RestMethod -Uri "$Collection$Project/_apis/test/runs?buildUri=$buildUri&api-version=7.1" -Method Get -Headers $h
    if (-not $runs.value -or $runs.value.Count -eq 0) { Write-Warn2 "No ADO test runs found for build $BuildId."; return @() }
    $results = @()
    foreach ($r in $runs.value) {
        $res = Invoke-RestMethod -Uri "$Collection$Project/_apis/test/Runs/$($r.id)/results?outcomes=Failed&`$top=1000&api-version=7.1" -Method Get -Headers $h
        foreach ($item in $res.value) { $results += [pscustomobject]@{ RunId=$r.id; ResultId=$item.id; Title=$item.testCaseTitle } }
    }
    Write-Info "ADO reports $($results.Count) failed result(s) for this build."
    return $results
}

function Add-AdoAttachment {
    param([string]$Collection,[string]$Project,[string]$AdoToken,[string]$RunId,[string]$ResultId,[string]$FilePath,[string]$FileName)
    $h = @{ 'Authorization'="Bearer $AdoToken"; 'Content-Type'='application/json' }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($FilePath))
    $body = @{ attachmentType='GeneralAttachment'; fileName=$FileName; comment='Tosca step-level detail'; stream=$b64 } | ConvertTo-Json
    Invoke-RestMethod -Uri "$Collection$Project/_apis/test/Runs/$RunId/Results/$ResultId/attachments?api-version=7.1" -Method Post -Headers $h -Body $body | Out-Null
}

function Escape-Md { param($s)
    if ($null -eq $s) { return "" }
    return ([string]$s).Replace('|','\|').Replace("`r"," ").Replace("`n"," ")
}

# ==========================================================================
# MAIN  (best-effort: always exits 0)
# ==========================================================================
try {
    if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

    if ([string]::IsNullOrEmpty($BearerToken)) {
        $BearerToken = Get-Token -TokenUrl $TokenUrl -ClientId $ClientId -ClientSecret $ClientSecret -Timeout $RequestTimeout
    }
    if ([string]::IsNullOrEmpty($PlaylistRunId)) {
        $PlaylistRunId = Resolve-PlaylistRunId -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -PlaylistName $PlaylistName -Timeout $RequestTimeout
    }

    $failedRuns = Get-FailedTestCaseRuns -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -RunId $PlaylistRunId -PerPage $ItemsPerPage -States $FailedStates -Timeout $RequestTimeout
    if (-not $failedRuns -or $failedRuns.Count -eq 0) { Write-Info "No failed test case runs - nothing to enrich."; exit 0 }

    $portal = if ($PortalBaseUrl) { $PortalBaseUrl } else { $BaseUrl }

    $nameToHtml = @{}; $reportIndex = @()
    foreach ($tcr in $failedRuns) {
        $safe = if ($tcr.displayName) { $tcr.displayName } else { $tcr.testCaseId }
        $safe = ($safe -replace '[^\w\-]+','_').Trim('_'); if (-not $safe) { $safe = $tcr.id }
        $file = Join-Path $OutputDir ("FAILED_{0}_{1}.html" -f $safe, $tcr.id)
        $json = Get-TestStepsJson -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -TcrId $tcr.id -Timeout $RequestTimeout
        (New-StepHtml -TestCaseRun $tcr -StepJson $json -PortalBaseUrl $portal -SpaceName $SpaceName -PlaylistRunId $PlaylistRunId) | Out-File -FilePath $file -Encoding UTF8
        Write-Info "Rendered $file"
        if ($tcr.displayName) { $nameToHtml[$tcr.displayName.ToLower()] = $file }
        $resultUrl = if ($SpaceName) { "$portal/_portal/space/$([uri]::EscapeDataString($SpaceName))/runs/$PlaylistRunId/results/$($tcr.id)" } else { "" }
        $reportIndex += [pscustomobject]@{ Name=$tcr.displayName; State=$tcr.state; File=(Split-Path $file -Leaf); Url=$resultUrl }
    }

    # Markdown summary tab (emoji + counts, pipe-safe)
    $md  = "# Tosca failed tests - step detail`n`n"
    if ($SpaceName) {
        $runUrl = "$portal/_portal/space/$([uri]::EscapeDataString($SpaceName))/runs/$PlaylistRunId"
        $md += "**[Open run in Tosca Cloud]($runUrl)**`n`n"
    }
    $md += "**Playlist run:** ``$PlaylistRunId``  `n"
    $md += "**Failed test cases:** $($reportIndex.Count)`n`n"
    $md += "|  | Test case | State | Report |`n|---|---|---|---|`n"
    foreach ($r in $reportIndex) {
        $emoji = if ("$($r.State)".ToLower() -eq 'failed') { [char]0x274C } else { [char]0x26A0 }
        $nameCell = if ($r.Url) { "[$(Escape-Md $r.Name)]($($r.Url))" } else { Escape-Md $r.Name }
        $md += "| $emoji | $nameCell | $(Escape-Md $r.State) | $(Escape-Md $r.File) |`n"
    }
    $mdPath = Join-Path $OutputDir "_summary.md"
    $md | Out-File -FilePath $mdPath -Encoding UTF8
    Write-Host "##vso[task.uploadsummary]$mdPath"

    if ($AttachToTestResults) {
        $collection = $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
        $project    = $env:SYSTEM_TEAMPROJECT
        $buildId    = $env:BUILD_BUILDID
        $adoToken   = $env:SYSTEM_ACCESSTOKEN
        if ([string]::IsNullOrEmpty($adoToken)) {
            Write-Warn2 "SYSTEM_ACCESSTOKEN not available - skipping per-result attachments. Reports still published as an artifact."
        } else {
            $adoFailed = Get-AdoFailedResults -Collection $collection -Project $project -BuildId $buildId -AdoToken $adoToken
            $attached = 0
            foreach ($res in $adoFailed) {
                $key = "$($res.Title)".ToLower()
                if ($nameToHtml.ContainsKey($key)) {
                    try { Add-AdoAttachment -Collection $collection -Project $project -AdoToken $adoToken -RunId $res.RunId -ResultId $res.ResultId -FilePath $nameToHtml[$key] -FileName "ToscaStepDetail.html"; $attached++ }
                    catch { Write-Warn2 "Attach failed for '$($res.Title)': $($_.Exception.Message)" }
                } else { Write-Warn2 "No rendered report matched ADO result title '$($res.Title)'." }
            }
            Write-Info "Attached $attached report(s) to failed test results."
        }
    }
    exit 0
}
catch { Write-Err2 "Enrichment step failed (non-fatal): $($_.Exception.Message)"; exit 0 }
