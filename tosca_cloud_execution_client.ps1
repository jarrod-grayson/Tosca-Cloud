#Requires -Version 3.0

#####################################################################################
# Tosca Cloud Execution Client
# Simplified version to avoid param block parsing issues
#####################################################################################

# Load required assemblies (if needed for future functionality)

# Initialize variables with defaults
$BaseUrl = "https://presales.my.tricentis.com"
$SpaceId = "ca41f063-fc34-41ab-aba0-6c1bb8c9ac8e"
$BearerToken = ""
$TokenUrl = "https://presales.okta.com/oauth2/default/v1/token"
$ClientId = "Tricentis_Cloud_API"
$ClientSecret = ""
$PlaylistName = ""
$StartNewRun = $false
$RunPrivate = $false
$MonitorRun = $false
$PollingInterval = 5
$MaxPollingTimeout = 3600
$RetrieveResults = $false
$JUnitResultsFile = "junit_results.xml"
$RequestTimeout = 30
$OutputFormat = "json"
$OutputFile = ""
$Debug = $false
$Help = $false

# Parse command line arguments
for ($i = 0; $i -lt $args.Count; $i++) {
Â  Â  switch ($args[$i]) {
Â  Â  Â  Â  "-BaseUrl" { $BaseUrl = $args[++$i] }
Â  Â  Â  Â  "-SpaceId" { $SpaceId = $args[++$i] }
Â  Â  Â  Â  "-BearerToken" { $BearerToken = $args[++$i] }
Â  Â  Â  Â  "-PlaylistName" { $PlaylistName = $args[++$i] }
Â  Â  Â  Â  "-StartNewRun" { $StartNewRun = $true }
Â  Â  Â  Â  "-RunPrivate" { $RunPrivate = [System.Convert]::ToBoolean($args[++$i]) }
Â  Â  Â  Â  "-MonitorRun" { $MonitorRun = $true }
Â  Â  Â  Â  "-PollingInterval" { $PollingInterval = [int]$args[++$i] }
Â  Â  Â  Â  "-MaxPollingTimeout" { $MaxPollingTimeout = [int]$args[++$i] }
Â  Â  Â  Â  "-RetrieveResults" { $RetrieveResults = $true }
Â  Â  Â  Â  Â  Â  Â  Â  Â "-JUnitResultsFile" { $JUnitResultsFile = $args[++$i] }
Â  Â  Â  Â  Â "-RequestTimeout" { $RequestTimeout = [int]$args[++$i] }
Â  Â  Â  Â  Â "-OutputFormat" { $OutputFormat = $args[++$i] }
Â  Â  Â  Â  Â "-OutputFile" { $OutputFile = $args[++$i] }
Â  Â  Â  Â  Â "-TokenUrl" { $TokenUrl = $args[++$i] }
Â  Â  Â  Â  Â "-ClientId" { $ClientId = $args[++$i] }
Â  Â  Â  Â  Â "-ClientSecret" { $ClientSecret = $args[++$i] }
Â  Â  Â  Â  Â "-Debug" { $Debug = $true }
Â  Â  Â  Â  Â "-Help" { $Help = $true }
Â  Â  }
}

######################################################################
# Functions
######################################################################

function Show-Help {
Â  Â  Write-Host "`nTosca Cloud Execution Client" -ForegroundColor Green
Â  Â  Write-Host "===========================`n"
Â  Â  Write-Host "USAGE:"
Â  Â  Write-Host " Â .\tosca_cloud_execution_client.ps1 [Options]`n"
Â  Â  Write-Host "PARAMETERS:"
Â  Â  Write-Host " Â -BaseUrl <url> Â  Â  Â  Â  Â  Â  Â Base URL for Tosca Cloud API (default: https://presales.my.tricentis.com)"
Â  Â  Write-Host " Â -SpaceId <id> Â  Â  Â  Â  Â  Â  Â  Space ID for Tosca Cloud (default: ca41f063-fc34-41ab-aba0-6c1bb8c9ac8e)"
Â  Â  Write-Host " Â -BearerToken <token> Â  Â  Â  Â Bearer token for authentication (optional - will be obtained automatically)"
Â  Â  Write-Host " Â -TokenUrl <url> Â  Â  Â  Â  Â  Â  Token URL for OAuth2 client credentials (default: https://tricentis-internal.oktapreview.com/oauth2/default/v1/token)"
Â  Â  Write-Host " Â -ClientId <id> Â  Â  Â  Â  Â  Â  Â Client ID for OAuth2 (default: Tricentis_Cloud_API)"
Â  Â  Write-Host " Â -ClientSecret <secret> Â  Â  Â Client secret for OAuth2 (MANDATORY)"
Â  Â  Write-Host " Â -PlaylistName <name> Â  Â  Â  Â Name of playlist to find and use"
Â  Â  Write-Host " Â -StartNewRun Â  Â  Â  Â  Â  Â  Â  Â Start a new playlist run"
Â  Â  Write-Host " Â -RunPrivate <bool> Â  Â  Â  Â  Â Set run as private (default: false)"
Â  Â  Write-Host " Â -MonitorRun Â  Â  Â  Â  Â  Â  Â  Â  Monitor the run until completion"
Â  Â  Write-Host " Â -PollingInterval <seconds> Â Polling interval for monitoring (default: 5)"
Â  Â  Write-Host " Â -MaxPollingTimeout <seconds> Maximum timeout for monitoring (default: 3600)"
Â  Â  Write-Host " Â -RetrieveResults Â  Â  Â  Â  Â  Â Retrieve JUnit test results"
Â  Â  Write-Host " Â -JUnitResultsFile <file> Â  Â Output file for JUnit results (default: junit_results.xml)"
Â  Â  Write-Host " Â -RequestTimeout <seconds> Â  Request timeout (default: 30)"
Â  Â  Write-Host " Â -Debug Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Enable debug output"
Â  Â  Write-Host " Â -Help Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Show this help message`n"
Â  Â  Write-Host "EXAMPLES:"
Â  Â  Write-Host " Â # Get all playlist runs (with automatic token)"
Â  Â  Write-Host " Â .\tosca_cloud_execution_client.ps1 -ClientSecret 'your-client-secret'"
Â  Â  Write-Host ""
Â  Â  Write-Host " Â # Extract playlist ID by name"
Â  Â  Write-Host " Â .\tosca_cloud_execution_client.ps1 -ClientSecret 'your-client-secret' -PlaylistName 'D365|Create Journal'"
Â  Â  Write-Host ""
Â  Â  Write-Host " Â # Start a new playlist run"
Â  Â  Write-Host " Â .\tosca_cloud_execution_client.ps1 -ClientSecret 'your-client-secret' -PlaylistName 'Test Playlist' -StartNewRun"
Â  Â  Write-Host ""
Â  Â  Write-Host " Â # Complete workflow: start, monitor, and get results"
Â  Â  Write-Host " Â .\tosca_cloud_execution_client.ps1 -ClientSecret 'your-client-secret' -PlaylistName 'Test Playlist' -StartNewRun -MonitorRun -RetrieveResults"
Â  Â  Write-Host ""
Â  Â  Write-Host " Â # Use custom token instead of client credentials"
Â  Â  Write-Host " Â .\tosca_cloud_execution_client.ps1 -BearerToken 'your-bearer-token' -PlaylistName 'Test Playlist' -StartNewRun -MonitorRun -RetrieveResults`n"
}

function Write-DebugMessage {
Â  Â  param([string]$Message)
Â  Â  if ($Debug) {
Â  Â  Â  Â  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Â  Â  Â  Â  Write-Host "[$timestamp] [DEBUG] $Message" -ForegroundColor Yellow
Â  Â  }
}

function Write-ErrorMessage {
Â  Â  param([string]$Message)
Â  Â  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Â  Â  Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red
}

function Write-InfoMessage {
Â  Â  param([string]$Message)
Â  Â  $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Â  Â  Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan
}

function Get-BearerToken {
Â  Â  param([string]$TokenUrl, [string]$ClientId, [string]$ClientSecret, [int]$Timeout)
Â  Â Â 
Â  Â  try {
Â  Â  Â  Â  Write-InfoMessage "Obtaining Bearer token using client credentials..."
Â  Â  Â  Â  Write-DebugMessage "Token URL: $TokenUrl"
Â  Â  Â  Â  Write-DebugMessage "Client ID: $ClientId"
Â  Â  Â  Â Â 
Â  Â  Â  Â  $headers = @{
Â  Â  Â  Â  Â  Â  "Accept" = "application/json"
Â  Â  Â  Â  Â  Â  "Content-Type" = "application/x-www-form-urlencoded"
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  $body = @{
Â  Â  Â  Â  Â  Â  "client_id" = $ClientId
Â  Â  Â  Â  Â  Â  "client_secret" = $ClientSecret
Â  Â  Â  Â  Â  Â  "grant_type" = "client_credentials"
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  # Convert body to form-urlencoded format
Â  Â  Â  Â  $formData = ($body.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
Â  Â  Â  Â Â 
Â  Â  Â  Â  Write-DebugMessage "Request body: $formData"
Â  Â  Â  Â Â 
Â  Â  Â  Â  $response = Invoke-RestMethod -Uri $TokenUrl -Method Post -Headers $headers -Body $formData -TimeoutSec $Timeout
Â  Â  Â  Â Â 
Â  Â  Â  Â  Write-InfoMessage "Successfully obtained Bearer token"
Â  Â  Â  Â  Write-DebugMessage "Token type: $($response.token_type)"
Â  Â  Â  Â  Write-DebugMessage "Expires in: $($response.expires_in) seconds"
Â  Â  Â  Â Â 
Â  Â  Â  Â  if ($response.access_token) {
Â  Â  Â  Â  Â  Â  return $response.access_token
Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Write-ErrorMessage "No access_token received in response"
Â  Â  Â  Â  Â  Â  throw "No access_token received in response"
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  } catch {
Â  Â  Â  Â  Write-ErrorMessage "Failed to obtain Bearer token: $($_.Exception.Message)"
Â  Â  Â  Â  throw $_
Â  Â  }
}

function Get-PlaylistRuns {
Â  Â  param([string]$Url, [string]$Token, [int]$Timeout)
Â  Â Â 
Â  Â  try {
Â  Â  Â  Â  Write-InfoMessage "Fetching playlist runs from Tosca Cloud API..."
Â  Â  Â  Â  Write-DebugMessage "URL: $Url"
Â  Â  Â  Â  $PagedUrl = $Url + "?itemsPerPage=2000"
Â  Â  Â  Â  $headers = @{
Â  Â  Â  Â  Â  Â  "Accept" Â  Â  Â  Â = "application/json"
Â  Â  Â  Â  Â  Â  "Authorization" = "Bearer $Token"
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  $response = Invoke-RestMethod -Uri $PagedUrl -Method Get -Headers $headers -TimeoutSec $Timeout
Â  Â  Â  Â Â 
Â  Â  Â  Â  Write-InfoMessage "Successfully retrieved playlist runs data"
Â  Â  Â  Â  return $response
Â  Â  Â  Â Â 
Â  Â  } catch {
Â  Â  Â  Â  Write-ErrorMessage "Failed to fetch playlist runs: $($_.Exception.Message)"
Â  Â  Â  Â  throw $_
Â  Â  }
}

function Get-PlaylistIdByName {
Â  Â  param([object]$PlaylistRunsResponse, [string]$TargetPlaylistName)
Â  Â Â 
Â  Â  try {
Â  Â  Â  Â  Write-InfoMessage "Searching for playlist with name: '$TargetPlaylistName'"
Â  Â  Â  Â Â 
Â  Â  Â  Â  $playlistItems = $null
Â  Â  Â  Â  if ($PlaylistRunsResponse.items) {
Â  Â  Â  Â  Â  Â  $playlistItems = $PlaylistRunsResponse.items
Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  $playlistItems = if ($PlaylistRunsResponse -is [Array]) { $PlaylistRunsResponse } else { @($PlaylistRunsResponse) }
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  if (-not $playlistItems -or $playlistItems.Count -eq 0) {
Â  Â  Â  Â  Â  Â  Write-ErrorMessage "No playlist runs found in the response"
Â  Â  Â  Â  Â  Â  return $null
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  $matchingPlaylists = @()
Â  Â  Â  Â  foreach ($item in $playlistItems) {
Â  Â  Â  Â  Â  Â  $currentPlaylistName = $item.playlistName
Â  Â  Â  Â  Â  Â  Write-DebugMessage "Checking playlist: '$currentPlaylistName' (ID: $($item.playlistId))"
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  if ($currentPlaylistName -and $currentPlaylistName -ieq $TargetPlaylistName) {
Â  Â  Â  Â  Â  Â  Â  Â  $matchingPlaylists += $item
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Found matching playlist! ID: $($item.playlistId)"
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  if ($matchingPlaylists.Count -eq 0) {
Â  Â  Â  Â  Â  Â  Write-ErrorMessage "No playlist found with name: '$TargetPlaylistName'"
Â  Â  Â  Â  Â  Â  return $null
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  if ($matchingPlaylists.Count -gt 1) {
Â  Â  Â  Â  Â  Â  Write-InfoMessage "Found $($matchingPlaylists.Count) playlist runs with name: '$TargetPlaylistName'"
Â  Â  Â  Â  Â  Â  Write-InfoMessage "Returning playlist ID from the most recent run"
Â  Â  Â  Â  Â  Â  $matchingPlaylists = $matchingPlaylists | Sort-Object createdAt -Descending
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  $selectedItem = $matchingPlaylists[0]
Â  Â  Â  Â  $playlistId = $selectedItem.playlistId
Â  Â  Â  Â Â 
Â  Â  Â  Â  if ($playlistId) {
Â  Â  Â  Â  Â  Â  Write-InfoMessage "Found playlist ID: $playlistId"
Â  Â  Â  Â  Â  Â  return $playlistId
Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Playlist run found but no playlistId property available"
Â  Â  Â  Â  Â  Â  return $null
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  } catch {
Â  Â  Â  Â  Write-ErrorMessage "Failed to extract playlist ID: $($_.Exception.Message)"
Â  Â  Â  Â  throw $_
Â  Â  }
}

function Start-NewPlaylistRun {
Â  Â  param([string]$BaseUrl, [string]$SpaceId, [string]$Token, [string]$PlaylistId, [bool]$IsPrivate, [int]$Timeout)
Â  Â Â 
Â  Â  try {
Â  Â  Â  Â  Write-InfoMessage "Starting new playlist run for playlist ID: $PlaylistId"
Â  Â  Â  Â Â 
Â  Â  Â  Â  $apiUrl = "$BaseUrl/$SpaceId/_playlists/api/v2/playlistRuns"
Â  Â  Â  Â  $headers = @{
Â  Â  Â  Â  Â  Â  'Accept' = 'application/json'
Â  Â  Â  Â  Â  Â  'Authorization' = "Bearer $Token"
Â  Â  Â  Â  Â  Â  'Content-Type' = 'application/json'
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  $requestBody = @{
Â  Â  Â  Â  Â  Â  playlistId = $PlaylistId
Â  Â  Â  Â  Â  Â  private = $IsPrivate
Â  Â  Â  Â  } | ConvertTo-Json
Â  Â  Â  Â Â 
Â  Â  Â  Â  $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $requestBody -TimeoutSec $Timeout
Â  Â  Â  Â Â 
Â  Â  Â  Â  Write-InfoMessage "Successfully started new playlist run"
Â  Â  Â  Â  if ($response.id) {
Â  Â  Â  Â  Â  Â  Write-InfoMessage "New run ID: $($response.id)"
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  return $response
Â  Â  Â  Â Â 
Â  Â  } catch {
Â  Â  Â  Â  Write-ErrorMessage "Failed to start new playlist run: $($_.Exception.Message)"
Â  Â  Â  Â  throw $_
Â  Â  }
}

function Watch-PlaylistRun {
Â  Â  param([string]$BaseUrl, [string]$SpaceId, [string]$Token, [string]$RunId, [int]$PollingIntervalSeconds, [int]$MaxTimeoutSeconds, [int]$RequestTimeout)
Â  Â Â 
Â  Â  try {
Â  Â  Â  Â  Write-InfoMessage "Starting to monitor playlist run: $RunId"
Â  Â  Â  Â Â 
Â  Â  Â  Â  $apiUrl = "$BaseUrl/$SpaceId/_playlists/api/v2/playlistRuns/$RunId"
Â  Â  Â  Â  $headers = @{
Â  Â  Â  Â  Â  Â  'Accept' = 'application/json'
Â  Â  Â  Â  Â  Â  'Authorization' = "Bearer $Token"
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  $startTime = Get-Date
Â  Â  Â  Â  $endTime = $startTime.AddSeconds($MaxTimeoutSeconds)
Â  Â  Â  Â  $pollCount = 0
Â  Â  Â  Â Â 
Â  Â  Â  Â  while ((Get-Date) -lt $endTime) {
Â  Â  Â  Â  Â  Â  $pollCount++
Â  Â  Â  Â  Â  Â  $currentTime = Get-Date
Â  Â  Â  Â  Â  Â  $elapsedSeconds = [math]::Round(($currentTime - $startTime).TotalSeconds, 1)
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Write-InfoMessage "Poll #$pollCount (elapsed: ${elapsedSeconds}s) - Checking run status..."
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec $RequestTimeout
Â  Â  Â  Â  Â  Â  Â  Â  $currentState = $response.state
Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Current state: $currentState"
Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  $completionStates = @("passed", "failed", "completed", "succeeded", "error", "cancelled")
Â  Â  Â  Â  Â  Â  Â  Â  $isCompleted = $completionStates -contains $currentState.ToLower()
Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  if ($isCompleted) {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Run completed with state: $currentState"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $successStates = @("passed", "completed", "succeeded")
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $isSuccess = $successStates -contains $currentState.ToLower()
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  if ($isSuccess) {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "âœ… Playlist run PASSED!"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "âŒ Playlist run FAILED!"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  return $response
Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Next poll in $PollingIntervalSeconds seconds..."
Â  Â  Â  Â  Â  Â  Â  Â  Start-Sleep -Seconds $PollingIntervalSeconds
Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Failed to check run status on poll #$pollCount : $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  Â  Â  Start-Sleep -Seconds $PollingIntervalSeconds
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  Write-ErrorMessage "Monitoring timeout reached after $MaxTimeoutSeconds seconds"
Â  Â  Â  Â  throw "Monitoring timeout reached after $MaxTimeoutSeconds seconds"
Â  Â  Â  Â Â 
Â  Â  } catch {
Â  Â  Â  Â  Write-ErrorMessage "Failed to monitor playlist run: $($_.Exception.Message)"
Â  Â  Â  Â  throw $_
Â  Â  }
}

function Get-JUnitResults {
Â  Â  param([string]$BaseUrl, [string]$SpaceId, [string]$Token, [string]$RunId, [string]$JUnitResultsFileName, [int]$RequestTimeout)
Â  Â Â 
Â  Â  try {
Â  Â  Â  Â  Write-InfoMessage "Retrieving JUnit test results for run: $RunId"
Â  Â  Â  Â  $apiUrl = "$BaseUrl/$SpaceId/_playlists/api/v2/playlistRuns/$RunId/junit"
Â  Â  Â  Â  $headers = @{
Â  Â  Â  Â  Â  Â  'Accept' = 'application/json'
Â  Â  Â  Â  Â  Â  'Authorization' = "Bearer $Token"
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  if ([String]::IsNullOrEmpty($JUnitResultsFileName)) {
Â  Â  Â  Â  Â  Â  #$JUnitResultsFileName = "${RunId}_junit_results.xml"
Â  Â  Â  Â  Â  Â  $JUnitResultsFileName = "junit_results.xml"
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  if (-not $JUnitResultsFileName.EndsWith('.xml', [StringComparison]::OrdinalIgnoreCase)) {
Â  Â  Â  Â  Â  Â  $JUnitResultsFileName += '.xml'
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  Write-InfoMessage "JUnit results will be saved to: $JUnitResultsFileName"
Â  Â  Â  Â Â 
Â  Â  Â  Â  $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec $RequestTimeout
Â  Â  Â  Â Â 
Â  Â  Â  Â  Write-InfoMessage "Successfully retrieved JUnit test results"
Â  Â  Â  Â Â 
Â  Â  Â  Â  # Safely handle the response to avoid XmlResolver issues
Â  Â  Â  Â  Write-DebugMessage "Response type: $($response.GetType().Name)"
Â  Â  Â  Â Â 
Â  Â  Â  Â  $junitXmlContent = $null
Â  Â  Â  Â Â 
Â  Â  Â  Â  # Safely extract content from response
Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  if ($response -is [String]) {
Â  Â  Â  Â  Â  Â  Â  Â  $junitXmlContent = $response
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Response is string type"
Â  Â  Â  Â  Â  Â  } elseif ($response.xmlContent) {
Â  Â  Â  Â  Â  Â  Â  Â  $junitXmlContent = $response.xmlContent
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Extracted from xmlContent property"
Â  Â  Â  Â  Â  Â  } elseif ($response.content) {
Â  Â  Â  Â  Â  Â  Â  Â  $junitXmlContent = $response.content
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Extracted from content property"
Â  Â  Â  Â  Â  Â  } elseif ($response -is [System.Xml.XmlDocument]) {
Â  Â  Â  Â  Â  Â  Â  Â  # Handle XML document directly
Â  Â  Â  Â  Â  Â  Â  Â  $junitXmlContent = $response.OuterXml
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Response is XML document"
Â  Â  Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Â  Â  # Handle complex objects safely
Â  Â  Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $junitXmlContent = $response | ConvertTo-Json -Depth 10
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Converted response to JSON"
Â  Â  Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  # Fallback to simple string conversion
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $junitXmlContent = $response.ToString()
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Used ToString() fallback"
Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Failed to extract content from response: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  # Last resort: try to get raw content
Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  $junitXmlContent = $response.ToString()
Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Cannot convert response to string"
Â  Â  Â  Â  Â  Â  Â  Â  return $null
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  if ([String]::IsNullOrEmpty($junitXmlContent)) {
Â  Â  Â  Â  Â  Â  Write-ErrorMessage "No JUnit content received from API"
Â  Â  Â  Â  Â  Â  return $null
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  Write-DebugMessage "JUnit content length: $($junitXmlContent.Length) characters"
Â  Â  Â  Â Â 
Â  Â  Â  Â  # Check if content is actually valid
Â  Â  Â  Â  if ($junitXmlContent.Length -eq 0) {
Â  Â  Â  Â  Â  Â  Write-ErrorMessage "JUnit content is empty (0 characters)"
Â  Â  Â  Â  Â  Â  return $null
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  Â  Â  # Show first 100 characters for debugging
Â  Â  Â  Â  $preview = $junitXmlContent.Substring(0, [Math]::Min(100, $junitXmlContent.Length))
Â  Â  Â  Â  Write-DebugMessage "Content preview: $preview"
Â  Â  Â  Â Â 
Â  Â  Â  Â  Write-InfoMessage "Saving JUnit results to file: $JUnitResultsFileName"
Â  Â  Â  Â Â 
Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  # Validate XML content before saving
Â  Â  Â  Â  Â  Â  if ([String]::IsNullOrWhiteSpace($junitXmlContent)) {
Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "JUnit content is empty or null"
Â  Â  Â  Â  Â  Â  Â  Â  return $null
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  # Try to parse as XML to validate structure
Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  [xml]$xmlDoc = $junitXmlContent
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "XML content validated successfully"
Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Invalid XML content received: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  Â  Â  # Still save the content as-is for debugging
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  # Ensure the directory exists
Â  Â  Â  Â  Â  Â  $directory = Split-Path $JUnitResultsFileName -Parent
Â  Â  Â  Â  Â  Â  if ($directory -and -not (Test-Path $directory)) {
Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Creating directory: $directory"
Â  Â  Â  Â  Â  Â  Â  Â  New-Item -ItemType Directory -Path $directory -Force | Out-Null
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  # Check if we can write to the target location
Â  Â  Â  Â  Â  Â  Write-DebugMessage "Checking write permissions for: $JUnitResultsFileName"
Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  $testFile = "$JUnitResultsFileName.test"
Â  Â  Â  Â  Â  Â  Â  Â  [System.IO.File]::WriteAllText($testFile, "test", $utf8Encoding)
Â  Â  Â  Â  Â  Â  Â  Â  if (Test-Path $testFile) {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Remove-Item $testFile -Force
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Write permissions OK"
Â  Â  Â  Â  Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Write permissions test failed"
Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Write permissions test failed: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  # Write the file with proper encoding
Â  Â  Â  Â  Â  Â  $utf8Encoding = New-Object System.Text.UTF8Encoding $false
Â  Â  Â  Â  Â  Â  Write-DebugMessage "About to write file: $JUnitResultsFileName"
Â  Â  Â  Â  Â  Â  Write-DebugMessage "Content length: $($junitXmlContent.Length) characters"
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  [System.IO.File]::WriteAllText($JUnitResultsFileName, $junitXmlContent, $utf8Encoding)
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "File.WriteAllText completed without exception"
Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "File.WriteAllText failed: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Exception type: $($_.Exception.GetType().Name)"
Â  Â  Â  Â  Â  Â  Â  Â  throw $_
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Write-DebugMessage "File write operation completed"
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  # Immediately check if file exists
Â  Â  Â  Â  Â  Â  if (Test-Path $JUnitResultsFileName) {
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "File exists immediately after write"
Â  Â  Â  Â  Â  Â  Â  Â  $immediateFileInfo = Get-Item $JUnitResultsFileName
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Immediate file size: $($immediateFileInfo.Length) bytes"
Â  Â  Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "File does NOT exist immediately after write"
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Write-InfoMessage "Successfully saved JUnit results to: $JUnitResultsFileName"
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  # Wait a moment for file system to sync
Â  Â  Â  Â  Â  Â  Start-Sleep -Milliseconds 100
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  # Check if file exists and get its information
Â  Â  Â  Â  Â  Â  Write-DebugMessage "Checking if file exists: $JUnitResultsFileName"
Â  Â  Â  Â  Â  Â  $fileExists = Test-Path $JUnitResultsFileName
Â  Â  Â  Â  Â  Â  Write-DebugMessage "File exists check result: $fileExists"
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  if ($fileExists) {
Â  Â  Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $fileInfo = Get-Item $JUnitResultsFileName
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $fileSizeKB = [math]::Round($fileInfo.Length / 1024, 2)
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "File size: $fileSizeKB KB"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $resolvedPath = (Resolve-Path $JUnitResultsFileName).Path
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  return @{
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  FileName = $JUnitResultsFileName
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  FilePath = $resolvedPath
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Content = $junitXmlContent
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  SizeBytes = $fileInfo.Length
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Failed to get file information: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  # Return basic info without file details
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  return @{
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  FileName = $JUnitResultsFileName
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  FilePath = $JUnitResultsFileName
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Content = $junitXmlContent
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  SizeBytes = $junitXmlContent.Length
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "File was not created: $JUnitResultsFileName"
Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  # Try to list files in the directory to see what's there
Â  Â  Â  Â  Â  Â  Â  Â  $directory = Split-Path $JUnitResultsFileName -Parent
Â  Â  Â  Â  Â  Â  Â  Â  if ($directory) {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Checking directory contents: $directory"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $files = Get-ChildItem -Path $directory -Name "*.xml" | Sort-Object
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "XML files in directory: $($files -join ', ')"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Could not list directory contents: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  # Try to create the file again with a different approach
Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Attempting to create file with Set-Content..."
Â  Â  Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Set-Content -Path $JUnitResultsFileName -Value $junitXmlContent -Encoding UTF8
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Start-Sleep -Milliseconds 200
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  if (Test-Path $JUnitResultsFileName) {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "File created successfully with Set-Content"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $fileInfo = Get-Item $JUnitResultsFileName
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $fileSizeKB = [math]::Round($fileInfo.Length / 1024, 2)
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "File size: $fileSizeKB KB"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  return @{
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  FileName = $JUnitResultsFileName
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  FilePath = (Resolve-Path $JUnitResultsFileName).Path
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Content = $junitXmlContent
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  SizeBytes = $fileInfo.Length
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Set-Content also failed to create file"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-DebugMessage "Set-Content failed: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  # Return basic info without file details
Â  Â  Â  Â  Â  Â  Â  Â  return @{
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  FileName = $JUnitResultsFileName
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  FilePath = $JUnitResultsFileName
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Content = $junitXmlContent
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  SizeBytes = $junitXmlContent.Length
Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Failed to save JUnit results to file: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  throw $_
Â  Â  Â  Â  }
Â  Â  Â  Â Â 
Â  Â  } catch {
Â  Â  Â  Â  Write-ErrorMessage "Failed to retrieve JUnit test results: $($_.Exception.Message)"
Â  Â  Â  Â  throw $_
Â  Â  }
}



######################################################################
# Main execution
######################################################################

# Show help if requested
if ($Help) {
Â  Â  Show-Help
Â  Â  exit 0
}

# Validate ClientSecret parameter
if ([String]::IsNullOrEmpty($ClientSecret)) {
Â  Â  Write-ErrorMessage "ClientSecret parameter is mandatory. Please provide it using -ClientSecret parameter."
Â  Â  Show-Help
Â  Â  exit 1
}

# Obtain Bearer token if not provided
if ([String]::IsNullOrEmpty($BearerToken)) {
Â  Â  Write-InfoMessage "No Bearer token provided, obtaining one using client credentials..."
Â  Â  try {
Â  Â  Â  Â  $BearerToken = Get-BearerToken -TokenUrl $TokenUrl -ClientId $ClientId -ClientSecret $ClientSecret -Timeout $RequestTimeout
Â  Â  Â  Â  Write-InfoMessage "Bearer token obtained successfully"
Â  Â  } catch {
Â  Â  Â  Â  Write-ErrorMessage "Failed to obtain Bearer token: $($_.Exception.Message)"
Â  Â  Â  Â  Write-ErrorMessage "Please provide a valid Bearer token using -BearerToken parameter or ensure client credentials are correct"
Â  Â  Â  Â  Show-Help
Â  Â  Â  Â  exit 1
Â  Â  }
}

# Validate StartNewRun parameter dependencies
if ($StartNewRun -and -not $PlaylistName) {
Â  Â  Write-ErrorMessage "PlaylistName parameter is required when StartNewRun is specified"
Â  Â  Show-Help
Â  Â  exit 1
}

# Validate MonitorRun parameter dependencies
if ($MonitorRun -and -not $StartNewRun) {
Â  Â  Write-ErrorMessage "StartNewRun parameter is required when MonitorRun is specified"
Â  Â  Show-Help
Â  Â  exit 1
}

# Validate RetrieveResults parameter dependencies
if ($RetrieveResults -and -not $MonitorRun) {
Â  Â  Write-ErrorMessage "MonitorRun parameter is required when RetrieveResults is specified"
Â  Â  Show-Help
Â  Â  exit 1
}

# Construct the API URL
$apiUrl = "$BaseUrl/$SpaceId/_playlists/api/v2/playlistRuns"

Write-InfoMessage "Starting Tosca Cloud Execution Client"
Write-DebugMessage "Base URL: $BaseUrl"
Write-DebugMessage "Space ID: $SpaceId"
Write-DebugMessage "API URL: $apiUrl"

try {
Â  Â  # Fetch the playlist runs
Â  Â  $playlistRuns = Get-PlaylistRuns -Url $apiUrl -Token $BearerToken -Timeout $RequestTimeout
Â  Â Â 
Â  Â  # If PlaylistName is provided, extract the playlist ID
Â  Â  if ($PlaylistName) {
Â  Â  Â  Â  Write-InfoMessage "=== STEP 1: Extracting Playlist ID ==="
Â  Â  Â  Â  $playlistId = Get-PlaylistIdByName -PlaylistRunsResponse $playlistRuns -TargetPlaylistName $PlaylistName
Â  Â  Â  Â Â 
Â  Â  Â  Â  if ($playlistId) {
Â  Â  Â  Â  Â  Â  Write-InfoMessage "Step 1 completed successfully - Playlist ID: $playlistId"
Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  # If StartNewRun is specified, proceed to Step 2
Â  Â  Â  Â  Â  Â  if ($StartNewRun) {
Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "`n=== STEP 2: Starting New Playlist Run ==="
Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $newRunResponse = Start-NewPlaylistRun -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -PlaylistId $playlistId -IsPrivate $RunPrivate -Timeout $RequestTimeout
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Step 2 completed successfully"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  # Extract new run ID for potential Step 3
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $newRunId = $newRunResponse.id
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  # If MonitorRun is specified, proceed to Step 3
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  if ($MonitorRun -and $newRunId) {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "`n=== STEP 3: Monitoring Playlist Run ==="
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $finalRunResponse = Watch-PlaylistRun -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -RunId $newRunId -PollingIntervalSeconds $PollingInterval -MaxTimeoutSeconds $MaxPollingTimeout -RequestTimeout $RequestTimeout
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Step 3 completed successfully"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  # If RetrieveResults is specified, proceed to Step 4
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  if ($RetrieveResults) {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "`n=== STEP 4: Retrieving JUnit Test Results ==="
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  try {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $junitResults = Get-JUnitResults -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -RunId $newRunId -JUnitResultsFileName $JUnitResultsFile -RequestTimeout $RequestTimeout
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Step 4 completed successfully"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "`n=== ALL FOUR STEPS COMPLETED SUCCESSFULLY ==="
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Original Playlist ID: $playlistId"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "New Run ID: $newRunId"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Final State: $($finalRunResponse.state)"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  if ($junitResults) {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "JUnit Results File: $($junitResults.FileName)"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "JUnit Results Size: $([math]::Round($junitResults.SizeBytes / 1024, 2)) KB"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  # Exit with appropriate code based on final state
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $successStates = @("passed", "completed", "succeeded")
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $isSuccess = $successStates -contains $finalRunResponse.state.ToLower()
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  exit $(if ($isSuccess) { 0 } else { 1 })
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Step 4 failed: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  exit 1
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  # Steps 1, 2, and 3 only
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "`n=== STEPS 1, 2, AND 3 COMPLETED SUCCESSFULLY ==="
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Original Playlist ID: $playlistId"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "New Run ID: $newRunId"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Final State: $($finalRunResponse.state)"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  # Exit with appropriate code based on final state
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $successStates = @("passed", "completed", "succeeded")
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  $isSuccess = $successStates -contains $finalRunResponse.state.ToLower()
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  exit $(if ($isSuccess) { 0 } else { 1 })
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Step 3 failed: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  exit 1
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  # Steps 1 + 2 only
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "`n=== STEPS 1 AND 2 COMPLETED SUCCESSFULLY ==="
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Original Playlist ID: $playlistId"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  if ($newRunResponse.id) {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "New Run ID: $($newRunResponse.id)"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  exit 0
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â Â 
Â  Â  Â  Â  Â  Â  Â  Â  } catch {
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Step 2 failed: $($_.Exception.Message)"
Â  Â  Â  Â  Â  Â  Â  Â  Â  Â  exit 1
Â  Â  Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Â  Â  # Step 1 only - just output the playlist ID
Â  Â  Â  Â  Â  Â  Â  Â  Write-Output $playlistId
Â  Â  Â  Â  Â  Â  Â  Â  Write-InfoMessage "Step 1 completed successfully - Playlist ID: $playlistId"
Â  Â  Â  Â  Â  Â  Â  Â  exit 0
Â  Â  Â  Â  Â  Â  }
Â  Â  Â  Â  } else {
Â  Â  Â  Â  Â  Â  Write-ErrorMessage "Step 1 failed - Could not find playlist ID for name: '$PlaylistName'"
Â  Â  Â  Â  Â  Â  exit 1
Â  Â  Â  Â  }
Â  Â  } else {
Â  Â  Â  Â  # No playlist name provided - just return all playlist runs
Â  Â  Â  Â  Write-Output ($playlistRuns | ConvertTo-Json -Depth 10)
Â  Â  Â  Â  Write-InfoMessage "Script completed successfully"
Â  Â  Â  Â  exit 0
Â  Â  }
Â  Â Â 
} catch {
Â  Â  Write-ErrorMessage "Script execution failed: $($_.Exception.Message)"
Â  Â  exit 1
}
