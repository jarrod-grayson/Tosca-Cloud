<# 
.SYNOPSIS
  Triggers a Tosca Cloud Playlist from PowerShell or Azure DevOps,
  polls its execution status, and saves JUnit results.

.EXAMPLE
  pwsh ./Invoke-ToscaCloudPlaylist.ps1 `
    -TokenUrl "https://amspresales.okta.com/oauth2/default/v1/token" `
    -ClientId "Tricentis_Cloud_API" `
    -ClientSecret $env:TOSCA_CLIENT_SECRET `
    -Scope "tta" `
    -TenantBaseUrl "https://amspresales.my.tricentis.com/72548120-3e17-4758-8c12-b75bb448d443" `
    -PlaylistId "7d423f50-73d0-42bf-947d-5b5c3c51e2b4" `
    -ParameterOverridesJson '[{"name":"Browser","value":"Chrome"}]'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$TokenUrl,
    [Parameter(Mandatory=$true)] [string]$ClientId,
    [Parameter(Mandatory=$true)] [string]$ClientSecret,
    [Parameter(Mandatory=$true)] [string]$Scope,
    [Parameter(Mandatory=$true)] [string]$TenantBaseUrl,
    
    [Parameter(Mandatory=$false)] [string]$PlaylistId,
    [Parameter(Mandatory=$false)] [string]$PlaylistConfigFilePath,
    
    [Parameter(Mandatory=$false)] [int]$PollSeconds = 10,
    [Parameter(Mandatory=$false)] [int]$TimeoutMinutes = 60,
	[Parameter(Mandatory=$false)] [string]$ResultsFileName,
	[Parameter(Mandatory=$false)] [string]$ResultsFolderPath

)

# ---------- Utility Functions ----------
function Write-Info  { param([string]$m) Write-Host "[$(Get-Date -Format o)] $m" }
function Write-ErrorLine { param([string]$m) Write-Host "[$(Get-Date -Format o)] ERROR: $m" -ForegroundColor Red }

function Invoke-WithRetry {
  param(
    [Parameter(Mandatory=$true)][scriptblock]$Script,
    [int]$MaxRetries = 3,
    [int]$DelaySeconds = 5
  )
  $attempt = 0
  while ($true) {
    try { return & $Script }
    catch {
      $attempt++
      if ($attempt -ge $MaxRetries) { throw }
      Write-Info "Transient error: $($_.Exception.Message). Retry $attempt/$MaxRetries in $DelaySeconds sec..."
      Start-Sleep -Seconds $DelaySeconds
    }
  }
}

# ---------- 1) Get OAuth token ----------
Write-Info "Requesting OAuth token..."
$tokenBody = "grant_type=client_credentials&client_id=$([uri]::EscapeDataString($ClientId))&client_secret=$([uri]::EscapeDataString($ClientSecret))&scope=$([uri]::EscapeDataString($Scope))"

$tokenResponse = Invoke-WithRetry {
  Invoke-RestMethod -Method POST -Uri $TokenUrl `
    -Headers @{ "Accept"="application/json"; "Content-Type"="application/x-www-form-urlencoded" } `
    -Body $tokenBody
}
$accessToken = $tokenResponse.access_token
if (-not $accessToken) { throw "No access_token returned from token endpoint." }
Write-Info "✅ Token acquired."

# Common headers for Playlist API
$apiHeaders = @{
  "Authorization" = "Bearer $accessToken"
  "Accept"        = "application/json"
  "Content-Type"  = "application/json"
}

# ---------- 2) Trigger playlist run ----------
Write-Info "Triggering playlist run..."

try {
    # If PlaylistConfigFilePath provided, use that JSON
    if ($PlaylistConfigFilePath -and (Test-Path $PlaylistConfigFilePath)) {
        Write-Info "Using JSON payload from file: $PlaylistConfigFilePath"

        try {
            $triggerBody = Get-Content -Path $PlaylistConfigFilePath -Raw
            $null = $triggerBody | ConvertFrom-Json  # validate JSON
            Write-Info "✅ Playlist JSON payload validated successfully."
        }
        catch {
            throw "❌ Invalid JSON in PlaylistConfigFilePath '$PlaylistConfigFilePath': $($_.Exception.Message)"
        }
    }
    else {
        # Otherwise, build a default body from PlaylistId only
        if (-not $PlaylistId) {
            throw "PlaylistId is required if PlaylistConfigFilePath is not provided."
        }

        Write-Info "No config file provided — building default JSON payload from PlaylistId only."
        $triggerBodyObj = [ordered]@{
            playlistId         = $PlaylistId
            private            = $false
            parameterOverrides = @()
        }
        $triggerBody = $triggerBodyObj | ConvertTo-Json -Depth 5
    }

    Write-Info "Trigger request body:`n$triggerBody"

    # Trigger the playlist
    $triggerUrl = "$TenantBaseUrl/_playlists/api/v2/playlistRuns"
    Write-Info "Calling: $triggerUrl"

    $triggerResp = Invoke-WithRetry {
        Invoke-RestMethod -Method POST -Uri $triggerUrl -Headers $apiHeaders -Body $triggerBody
    }

    $runId = if ($triggerResp.id) { 
        $triggerResp.id 
    } elseif ($triggerResp.executionId) { 
        $triggerResp.executionId 
    } else { 
        $null 
    }

    if (-not $runId) { 
        throw "No run ID returned. Raw response: $($triggerResp | ConvertTo-Json -Depth 6)" 
    }

    Write-Info "✅ Playlist run started successfully. Run ID: $runId"
}
catch {
    Write-ErrorLine "❌ Failed to trigger playlist: $($_.Exception.Message)"
    exit 1
}

# ---------- 3) Poll Status (end) ----------
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$activeStates = @("pending","running","starting")

$finalState = $null

while ((Get-Date) -lt $deadline) {
    try {
        Start-Sleep -Seconds $PollSeconds
        $statusUrl = "$TenantBaseUrl/_playlists/api/v2/playlistRuns/$runId"
        $statusResp = Invoke-RestMethod -Method GET -Uri $statusUrl -Headers $apiHeaders
        $state = $statusResp.state
        if (-not $state) {
            Write-Info "Warning: no state in response; will retry."
            continue
        }
        Write-Info "Current playlist state: $state"
        $normalized = $state.ToLower()

        if ($activeStates -contains $normalized) {
            continue
        }

        # At this point, state is final (not pending/running)
        $finalState = $normalized
        break
    }
    catch {
        Write-ErrorLine "Status check error: $($_.Exception.Message); retrying..."
        continue
    }
}

if (-not $finalState) {
    Write-ErrorLine "⏱ Timeout reached without final state"
    $finalState = "timeout"
}

Write-Info "Final state: $finalState"

# ---------- 4) Always attempt to fetch JUnit results ----------
try {
    $resultsUrl = "$TenantBaseUrl/_playlists/api/v2/playlistRuns/$runId/junit"
    Write-Info "Attempting to download JUnit results from: $resultsUrl"

    if (-not (Test-Path $ResultsFolderPath)) {
        Write-Info "Creating results folder: $ResultsFolderPath"
        New-Item -ItemType Directory -Force -Path $ResultsFolderPath | Out-Null
    }

    $resultsFilePath = Join-Path -Path $ResultsFolderPath -ChildPath $ResultsFileName

    # Extended retry logic (wait up to ~2 minutes)
    $maxRetries = 12        # 12 × 10s = 120s total
    $retryDelay = 10
    $attempt = 0
    $junitXml = $null

    do {
        try {
            $attempt++
            Write-Info "[$attempt/$maxRetries] Fetching JUnit results..."
            $response = Invoke-RestMethod -Method GET -Uri $resultsUrl -Headers @{
                "Accept"        = "application/xml"
                "Authorization" = "Bearer $accessToken"
            } -TimeoutSec 60

            # Convert the XML object back to text
            $junitXml = $response.OuterXml

            if ($junitXml -match "<testcase") {
                Write-Info "✅ Valid JUnit results detected on attempt $attempt."
                break
            }
            else {
                Write-Info "⚠️ Results not ready yet (no <testcase> found). Waiting $retryDelay seconds..."
                Start-Sleep -Seconds $retryDelay
            }
        }
        catch {
            Write-ErrorLine "⚠️ Error fetching JUnit (attempt $attempt): $($_.Exception.Message)"
            Start-Sleep -Seconds $retryDelay
        }
    } while ($attempt -lt $maxRetries)

    if (-not [string]::IsNullOrWhiteSpace($junitXml)) {
        # Pretty-print XML for readability and ADO compatibility
		if ($response -is [xml]) {
			$stringWriter = New-Object System.IO.StringWriter
			$xmlWriter = New-Object System.Xml.XmlTextWriter($stringWriter)
			$xmlWriter.Formatting = "Indented"
			$response.Save($xmlWriter)
			$formattedXml = $stringWriter.ToString()
			$formattedXml | Out-File -FilePath $resultsFilePath -Encoding UTF8
		}
		else {
			$junitXml | Out-File -FilePath $resultsFilePath -Encoding UTF8
		}

        Write-Info "📄 JUnit results saved to: $resultsFilePath"
    }
    else {
        Write-ErrorLine "❌ No JUnit content returned after waiting $($maxRetries * $retryDelay) seconds."
    }
}
catch {
    Write-ErrorLine "⚠️ Could not download JUnit results: $($_.Exception.Message)"
}

# ---------- 5) Exit code based on final state ----------
if ($finalState -in @("succeeded","passed","completed")) {
    Write-Info "🎉 Playlist [$PlaylistId] completed successfully."
    exit 0
}
elseif ($finalState -eq "failed") {
    Write-ErrorLine "❌ Playlist [$PlaylistId] failed."
    exit 1
}
elseif ($finalState -eq "canceled") {
    Write-ErrorLine "🚫 Playlist [$PlaylistId] was cancelled."
    exit 1
}
else {
    Write-ErrorLine "⚠️ Execution ended with state '$finalState'"
    exit 1
}
