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
    switch ($args[$i]) {
        "-BaseUrl" { $BaseUrl = $args[++$i] }
        "-SpaceId" { $SpaceId = $args[++$i] }
        "-BearerToken" { $BearerToken = $args[++$i] }
        "-PlaylistName" { $PlaylistName = $args[++$i] }
        "-StartNewRun" { $StartNewRun = $true }
        "-RunPrivate" { $RunPrivate = [System.Convert]::ToBoolean($args[++$i]) }
        "-MonitorRun" { $MonitorRun = $true }
        "-PollingInterval" { $PollingInterval = [int]$args[++$i] }
        "-MaxPollingTimeout" { $MaxPollingTimeout = [int]$args[++$i] }
        "-RetrieveResults" { $RetrieveResults = $true }
                 "-JUnitResultsFile" { $JUnitResultsFile = $args[++$i] }
         "-RequestTimeout" { $RequestTimeout = [int]$args[++$i] }
         "-OutputFormat" { $OutputFormat = $args[++$i] }
         "-OutputFile" { $OutputFile = $args[++$i] }
         "-TokenUrl" { $TokenUrl = $args[++$i] }
         "-ClientId" { $ClientId = $args[++$i] }
         "-ClientSecret" { $ClientSecret = $args[++$i] }
         "-Debug" { $Debug = $true }
         "-Help" { $Help = $true }
    }
}

######################################################################
# Functions
######################################################################

function Show-Help {
    Write-Host "`nTosca Cloud Execution Client" -ForegroundColor Green
    Write-Host "===========================`n"
    Write-Host "USAGE:"
    Write-Host "  .\tosca_cloud_execution_client.ps1 [Options]`n"
    Write-Host "PARAMETERS:"
    Write-Host "  -BaseUrl <url>              Base URL for Tosca Cloud API (default: https://presales.my.tricentis.com)"
    Write-Host "  -SpaceId <id>               Space ID for Tosca Cloud (default: ca41f063-fc34-41ab-aba0-6c1bb8c9ac8e)"
    Write-Host "  -BearerToken <token>        Bearer token for authentication (optional - will be obtained automatically)"
    Write-Host "  -TokenUrl <url>             Token URL for OAuth2 client credentials (default: https://tricentis-internal.oktapreview.com/oauth2/default/v1/token)"
    Write-Host "  -ClientId <id>              Client ID for OAuth2 (default: Tricentis_Cloud_API)"
    Write-Host "  -ClientSecret <secret>      Client secret for OAuth2 (MANDATORY)"
    Write-Host "  -PlaylistName <name>        Name of playlist to find and use"
    Write-Host "  -StartNewRun                Start a new playlist run"
    Write-Host "  -RunPrivate <bool>          Set run as private (default: false)"
    Write-Host "  -MonitorRun                 Monitor the run until completion"
    Write-Host "  -PollingInterval <seconds>  Polling interval for monitoring (default: 5)"
    Write-Host "  -MaxPollingTimeout <seconds> Maximum timeout for monitoring (default: 3600)"
    Write-Host "  -RetrieveResults            Retrieve JUnit test results"
    Write-Host "  -JUnitResultsFile <file>    Output file for JUnit results (default: junit_results.xml)"
    Write-Host "  -RequestTimeout <seconds>   Request timeout (default: 30)"
    Write-Host "  -Debug                      Enable debug output"
    Write-Host "  -Help                       Show this help message`n"
    Write-Host "EXAMPLES:"
    Write-Host "  # Get all playlist runs (with automatic token)"
    Write-Host "  .\tosca_cloud_execution_client.ps1 -ClientSecret 'your-client-secret'"
    Write-Host ""
    Write-Host "  # Extract playlist ID by name"
    Write-Host "  .\tosca_cloud_execution_client.ps1 -ClientSecret 'your-client-secret' -PlaylistName 'D365|Create Journal'"
    Write-Host ""
    Write-Host "  # Start a new playlist run"
    Write-Host "  .\tosca_cloud_execution_client.ps1 -ClientSecret 'your-client-secret' -PlaylistName 'Test Playlist' -StartNewRun"
    Write-Host ""
    Write-Host "  # Complete workflow: start, monitor, and get results"
    Write-Host "  .\tosca_cloud_execution_client.ps1 -ClientSecret 'your-client-secret' -PlaylistName 'Test Playlist' -StartNewRun -MonitorRun -RetrieveResults"
    Write-Host ""
    Write-Host "  # Use custom token instead of client credentials"
    Write-Host "  .\tosca_cloud_execution_client.ps1 -BearerToken 'your-bearer-token' -PlaylistName 'Test Playlist' -StartNewRun -MonitorRun -RetrieveResults`n"
}

function Write-DebugMessage {
    param([string]$Message)
    if ($Debug) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] [DEBUG] $Message" -ForegroundColor Yellow
    }
}

function Write-ErrorMessage {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red
}

function Write-InfoMessage {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan
}

function Get-BearerToken {
    param([string]$TokenUrl, [string]$ClientId, [string]$ClientSecret, [int]$Timeout)
    
    try {
        Write-InfoMessage "Obtaining Bearer token using client credentials..."
        Write-DebugMessage "Token URL: $TokenUrl"
        Write-DebugMessage "Client ID: $ClientId"
        
        $headers = @{
            "Accept" = "application/json"
            "Content-Type" = "application/x-www-form-urlencoded"
            
        }
        
        $body = @{
            "client_id" = $ClientId
            "client_secret" = $ClientSecret
            "grant_type" = "client_credentials"
        }
        
        # Convert body to form-urlencoded format
        $formData = ($body.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
        
        Write-DebugMessage "Request body: $formData"
        
        $response = Invoke-RestMethod -Uri $TokenUrl -Method Post -Headers $headers -Body $formData -TimeoutSec $Timeout
        
        Write-InfoMessage "Successfully obtained Bearer token"
        Write-DebugMessage "Token type: $($response.token_type)"
        Write-DebugMessage "Expires in: $($response.expires_in) seconds"
        
        if ($response.access_token) {
            return $response.access_token
        } else {
            Write-ErrorMessage "No access_token received in response"
            throw "No access_token received in response"
        }
        
    } catch {
        Write-ErrorMessage "Failed to obtain Bearer token: $($_.Exception.Message)"
        throw $_
    }
}

function Get-PlaylistRuns {
    param([string]$Url, [string]$Token, [int]$Timeout)
    
    try {
        Write-InfoMessage "Fetching playlist runs from Tosca Cloud API..."
        Write-DebugMessage "URL: $Url"
        $PagedUrl = $Url + "?itemsPerPage=2000"
        $headers = @{
            "Accept"        = "application/json"
            "Authorization" = "Bearer $Token"
        }
        
        $response = Invoke-RestMethod -Uri $PagedUrl -Method Get -Headers $headers -TimeoutSec $Timeout
        
        Write-InfoMessage "Successfully retrieved playlist runs data"
        return $response
        
    } catch {
        Write-ErrorMessage "Failed to fetch playlist runs: $($_.Exception.Message)"
        throw $_
    }
}

function Get-PlaylistIdByName {
    param([object]$PlaylistRunsResponse, [string]$TargetPlaylistName)
    
    try {
        Write-InfoMessage "Searching for playlist with name: '$TargetPlaylistName'"
        
        $playlistItems = $null
        if ($PlaylistRunsResponse.items) {
            $playlistItems = $PlaylistRunsResponse.items
        } else {
            $playlistItems = if ($PlaylistRunsResponse -is [Array]) { $PlaylistRunsResponse } else { @($PlaylistRunsResponse) }
        }
        
        if (-not $playlistItems -or $playlistItems.Count -eq 0) {
            Write-ErrorMessage "No playlist runs found in the response"
            return $null
        }
        
        $matchingPlaylists = @()
        foreach ($item in $playlistItems) {
            $currentPlaylistName = $item.playlistName
            Write-DebugMessage "Checking playlist: '$currentPlaylistName' (ID: $($item.playlistId))"
            
            if ($currentPlaylistName -and $currentPlaylistName -ieq $TargetPlaylistName) {
                $matchingPlaylists += $item
                Write-DebugMessage "Found matching playlist! ID: $($item.playlistId)"
            }
        }
        
        if ($matchingPlaylists.Count -eq 0) {
            Write-ErrorMessage "No playlist found with name: '$TargetPlaylistName'"
            return $null
        }
        
        if ($matchingPlaylists.Count -gt 1) {
            Write-InfoMessage "Found $($matchingPlaylists.Count) playlist runs with name: '$TargetPlaylistName'"
            Write-InfoMessage "Returning playlist ID from the most recent run"
            $matchingPlaylists = $matchingPlaylists | Sort-Object createdAt -Descending
        }
        
        $selectedItem = $matchingPlaylists[0]
        $playlistId = $selectedItem.playlistId
        
        if ($playlistId) {
            Write-InfoMessage "Found playlist ID: $playlistId"
            return $playlistId
        } else {
            Write-ErrorMessage "Playlist run found but no playlistId property available"
            return $null
        }
        
    } catch {
        Write-ErrorMessage "Failed to extract playlist ID: $($_.Exception.Message)"
        throw $_
    }
}

function Start-NewPlaylistRun {
    param([string]$BaseUrl, [string]$SpaceId, [string]$Token, [string]$PlaylistId, [bool]$IsPrivate, [int]$Timeout)
    
    try {
        Write-InfoMessage "Starting new playlist run for playlist ID: $PlaylistId"
        
        $apiUrl = "$BaseUrl/$SpaceId/_playlists/api/v2/playlistRuns"
        $headers = @{
            'Accept' = 'application/json'
            'Authorization' = "Bearer $Token"
            'Content-Type' = 'application/json'
        }
        
        $requestBody = @{
            playlistId = $PlaylistId
            private = $IsPrivate
        } | ConvertTo-Json
        
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers $headers -Body $requestBody -TimeoutSec $Timeout
        
        Write-InfoMessage "Successfully started new playlist run"
        if ($response.id) {
            Write-InfoMessage "New run ID: $($response.id)"
        }
        
        return $response
        
    } catch {
        Write-ErrorMessage "Failed to start new playlist run: $($_.Exception.Message)"
        throw $_
    }
}

function Watch-PlaylistRun {
    param([string]$BaseUrl, [string]$SpaceId, [string]$Token, [string]$RunId, [int]$PollingIntervalSeconds, [int]$MaxTimeoutSeconds, [int]$RequestTimeout)
    
    try {
        Write-InfoMessage "Starting to monitor playlist run: $RunId"
        
        $apiUrl = "$BaseUrl/$SpaceId/_playlists/api/v2/playlistRuns/$RunId"
        $headers = @{
            'Accept' = 'application/json'
            'Authorization' = "Bearer $Token"
        }
        
        $startTime = Get-Date
        $endTime = $startTime.AddSeconds($MaxTimeoutSeconds)
        $pollCount = 0
        
        while ((Get-Date) -lt $endTime) {
            $pollCount++
            $currentTime = Get-Date
            $elapsedSeconds = [math]::Round(($currentTime - $startTime).TotalSeconds, 1)
            
            Write-InfoMessage "Poll #$pollCount (elapsed: ${elapsedSeconds}s) - Checking run status..."
            
            try {
                $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec $RequestTimeout
                $currentState = $response.state
                Write-InfoMessage "Current state: $currentState"
                
                $completionStates = @("passed", "failed", "completed", "succeeded", "error", "cancelled")
                $isCompleted = $completionStates -contains $currentState.ToLower()
                
                if ($isCompleted) {
                    Write-InfoMessage "Run completed with state: $currentState"
                    $successStates = @("passed", "completed", "succeeded")
                    $isSuccess = $successStates -contains $currentState.ToLower()
                    
                    if ($isSuccess) {
                        Write-InfoMessage "✅ Playlist run PASSED!"
                    } else {
                        Write-InfoMessage "❌ Playlist run FAILED!"
                    }
                    
                    return $response
                }
                
                Write-InfoMessage "Next poll in $PollingIntervalSeconds seconds..."
                Start-Sleep -Seconds $PollingIntervalSeconds
                
            } catch {
                Write-ErrorMessage "Failed to check run status on poll #$pollCount : $($_.Exception.Message)"
                Start-Sleep -Seconds $PollingIntervalSeconds
            }
        }
        
        Write-ErrorMessage "Monitoring timeout reached after $MaxTimeoutSeconds seconds"
        throw "Monitoring timeout reached after $MaxTimeoutSeconds seconds"
        
    } catch {
        Write-ErrorMessage "Failed to monitor playlist run: $($_.Exception.Message)"
        throw $_
    }
}

function Get-JUnitResults {
    param([string]$BaseUrl, [string]$SpaceId, [string]$Token, [string]$RunId, [string]$JUnitResultsFileName, [int]$RequestTimeout)
    
    try {
        Write-InfoMessage "Retrieving JUnit test results for run: $RunId"
        $apiUrl = "$BaseUrl/$SpaceId/_playlists/api/v2/playlistRuns/$RunId/junit"
        $headers = @{
            'Accept' = 'application/json'
            'Authorization' = "Bearer $Token"
        }
        
        if ([String]::IsNullOrEmpty($JUnitResultsFileName)) {
            #$JUnitResultsFileName = "${RunId}_junit_results.xml"
            $JUnitResultsFileName = "junit_results.xml"
        }
        
        if (-not $JUnitResultsFileName.EndsWith('.xml', [StringComparison]::OrdinalIgnoreCase)) {
            $JUnitResultsFileName += '.xml'
        }
        
        Write-InfoMessage "JUnit results will be saved to: $JUnitResultsFileName"
        
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec $RequestTimeout
        
        Write-InfoMessage "Successfully retrieved JUnit test results"
        
        # Safely handle the response to avoid XmlResolver issues
        Write-DebugMessage "Response type: $($response.GetType().Name)"
        
        $junitXmlContent = $null
        
        # Safely extract content from response
        try {
            if ($response -is [String]) {
                $junitXmlContent = $response
                Write-DebugMessage "Response is string type"
            } elseif ($response.xmlContent) {
                $junitXmlContent = $response.xmlContent
                Write-DebugMessage "Extracted from xmlContent property"
            } elseif ($response.content) {
                $junitXmlContent = $response.content
                Write-DebugMessage "Extracted from content property"
            } elseif ($response -is [System.Xml.XmlDocument]) {
                # Handle XML document directly
                $junitXmlContent = $response.OuterXml
                Write-DebugMessage "Response is XML document"
            } else {
                # Handle complex objects safely
                try {
                    $junitXmlContent = $response | ConvertTo-Json -Depth 10
                    Write-DebugMessage "Converted response to JSON"
                } catch {
                    # Fallback to simple string conversion
                    $junitXmlContent = $response.ToString()
                    Write-DebugMessage "Used ToString() fallback"
                }
            }
        } catch {
            Write-ErrorMessage "Failed to extract content from response: $($_.Exception.Message)"
            # Last resort: try to get raw content
            try {
                $junitXmlContent = $response.ToString()
            } catch {
                Write-ErrorMessage "Cannot convert response to string"
                return $null
            }
        }
        
        if ([String]::IsNullOrEmpty($junitXmlContent)) {
            Write-ErrorMessage "No JUnit content received from API"
            return $null
        }
        
        Write-DebugMessage "JUnit content length: $($junitXmlContent.Length) characters"
        
        # Check if content is actually valid
        if ($junitXmlContent.Length -eq 0) {
            Write-ErrorMessage "JUnit content is empty (0 characters)"
            return $null
        }
        
        # Show first 100 characters for debugging
        $preview = $junitXmlContent.Substring(0, [Math]::Min(100, $junitXmlContent.Length))
        Write-DebugMessage "Content preview: $preview"
        
        Write-InfoMessage "Saving JUnit results to file: $JUnitResultsFileName"
        
        try {
            # Validate XML content before saving
            if ([String]::IsNullOrWhiteSpace($junitXmlContent)) {
                Write-ErrorMessage "JUnit content is empty or null"
                return $null
            }
            
            # Try to parse as XML to validate structure
            try {
                [xml]$xmlDoc = $junitXmlContent
                Write-DebugMessage "XML content validated successfully"
            } catch {
                Write-ErrorMessage "Invalid XML content received: $($_.Exception.Message)"
                # Still save the content as-is for debugging
            }
            
            # Ensure the directory exists
            $directory = Split-Path $JUnitResultsFileName -Parent
            if ($directory -and -not (Test-Path $directory)) {
                Write-InfoMessage "Creating directory: $directory"
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
            
            # Check if we can write to the target location
            Write-DebugMessage "Checking write permissions for: $JUnitResultsFileName"
            try {
                $testFile = "$JUnitResultsFileName.test"
                [System.IO.File]::WriteAllText($testFile, "test", $utf8Encoding)
                if (Test-Path $testFile) {
                    Remove-Item $testFile -Force
                    Write-DebugMessage "Write permissions OK"
                } else {
                    Write-DebugMessage "Write permissions test failed"
                }
            } catch {
                Write-DebugMessage "Write permissions test failed: $($_.Exception.Message)"
            }
            
            # Write the file with proper encoding
            $utf8Encoding = New-Object System.Text.UTF8Encoding $false
            Write-DebugMessage "About to write file: $JUnitResultsFileName"
            Write-DebugMessage "Content length: $($junitXmlContent.Length) characters"
            
            try {
                [System.IO.File]::WriteAllText($JUnitResultsFileName, $junitXmlContent, $utf8Encoding)
                Write-DebugMessage "File.WriteAllText completed without exception"
            } catch {
                Write-ErrorMessage "File.WriteAllText failed: $($_.Exception.Message)"
                Write-ErrorMessage "Exception type: $($_.Exception.GetType().Name)"
                throw $_
            }
            
            Write-DebugMessage "File write operation completed"
            
            # Immediately check if file exists
            if (Test-Path $JUnitResultsFileName) {
                Write-DebugMessage "File exists immediately after write"
                $immediateFileInfo = Get-Item $JUnitResultsFileName
                Write-DebugMessage "Immediate file size: $($immediateFileInfo.Length) bytes"
            } else {
                Write-DebugMessage "File does NOT exist immediately after write"
            }
            
            Write-InfoMessage "Successfully saved JUnit results to: $JUnitResultsFileName"
            
            # Wait a moment for file system to sync
            Start-Sleep -Milliseconds 100
            
            # Check if file exists and get its information
            Write-DebugMessage "Checking if file exists: $JUnitResultsFileName"
            $fileExists = Test-Path $JUnitResultsFileName
            Write-DebugMessage "File exists check result: $fileExists"
            
            if ($fileExists) {
                try {
                    $fileInfo = Get-Item $JUnitResultsFileName
                    $fileSizeKB = [math]::Round($fileInfo.Length / 1024, 2)
                    Write-InfoMessage "File size: $fileSizeKB KB"
                    
                    $resolvedPath = (Resolve-Path $JUnitResultsFileName).Path
                    
                    return @{
                        FileName = $JUnitResultsFileName
                        FilePath = $resolvedPath
                        Content = $junitXmlContent
                        SizeBytes = $fileInfo.Length
                    }
                } catch {
                    Write-ErrorMessage "Failed to get file information: $($_.Exception.Message)"
                    # Return basic info without file details
                    return @{
                        FileName = $JUnitResultsFileName
                        FilePath = $JUnitResultsFileName
                        Content = $junitXmlContent
                        SizeBytes = $junitXmlContent.Length
                    }
                }
            } else {
                Write-ErrorMessage "File was not created: $JUnitResultsFileName"
                
                # Try to list files in the directory to see what's there
                $directory = Split-Path $JUnitResultsFileName -Parent
                if ($directory) {
                    Write-DebugMessage "Checking directory contents: $directory"
                    try {
                        $files = Get-ChildItem -Path $directory -Name "*.xml" | Sort-Object
                        Write-DebugMessage "XML files in directory: $($files -join ', ')"
                    } catch {
                        Write-DebugMessage "Could not list directory contents: $($_.Exception.Message)"
                    }
                }
                
                # Try to create the file again with a different approach
                Write-DebugMessage "Attempting to create file with Set-Content..."
                try {
                    Set-Content -Path $JUnitResultsFileName -Value $junitXmlContent -Encoding UTF8
                    Start-Sleep -Milliseconds 200
                    if (Test-Path $JUnitResultsFileName) {
                        Write-DebugMessage "File created successfully with Set-Content"
                        $fileInfo = Get-Item $JUnitResultsFileName
                        $fileSizeKB = [math]::Round($fileInfo.Length / 1024, 2)
                        Write-InfoMessage "File size: $fileSizeKB KB"
                        
                        return @{
                            FileName = $JUnitResultsFileName
                            FilePath = (Resolve-Path $JUnitResultsFileName).Path
                            Content = $junitXmlContent
                            SizeBytes = $fileInfo.Length
                        }
                    } else {
                        Write-DebugMessage "Set-Content also failed to create file"
                    }
                } catch {
                    Write-DebugMessage "Set-Content failed: $($_.Exception.Message)"
                }
                
                # Return basic info without file details
                return @{
                    FileName = $JUnitResultsFileName
                    FilePath = $JUnitResultsFileName
                    Content = $junitXmlContent
                    SizeBytes = $junitXmlContent.Length
                }
            }
            
        } catch {
            Write-ErrorMessage "Failed to save JUnit results to file: $($_.Exception.Message)"
            throw $_
        }
        
    } catch {
        Write-ErrorMessage "Failed to retrieve JUnit test results: $($_.Exception.Message)"
        throw $_
    }
}



######################################################################
# Main execution
######################################################################

# Show help if requested
if ($Help) {
    Show-Help
    exit 0
}

# Validate ClientSecret parameter
if ([String]::IsNullOrEmpty($ClientSecret)) {
    Write-ErrorMessage "ClientSecret parameter is mandatory. Please provide it using -ClientSecret parameter."
    Show-Help
    exit 1
}

# Obtain Bearer token if not provided
if ([String]::IsNullOrEmpty($BearerToken)) {
    Write-InfoMessage "No Bearer token provided, obtaining one using client credentials..."
    try {
        $BearerToken = Get-BearerToken -TokenUrl $TokenUrl -ClientId $ClientId -ClientSecret $ClientSecret -Timeout $RequestTimeout
        Write-InfoMessage "Bearer token obtained successfully"
    } catch {
        Write-ErrorMessage "Failed to obtain Bearer token: $($_.Exception.Message)"
        Write-ErrorMessage "Please provide a valid Bearer token using -BearerToken parameter or ensure client credentials are correct"
        Show-Help
        exit 1
    }
}

# Validate StartNewRun parameter dependencies
if ($StartNewRun -and -not $PlaylistName) {
    Write-ErrorMessage "PlaylistName parameter is required when StartNewRun is specified"
    Show-Help
    exit 1
}

# Validate MonitorRun parameter dependencies
if ($MonitorRun -and -not $StartNewRun) {
    Write-ErrorMessage "StartNewRun parameter is required when MonitorRun is specified"
    Show-Help
    exit 1
}

# Validate RetrieveResults parameter dependencies
if ($RetrieveResults -and -not $MonitorRun) {
    Write-ErrorMessage "MonitorRun parameter is required when RetrieveResults is specified"
    Show-Help
    exit 1
}

# Construct the API URL
$apiUrl = "$BaseUrl/$SpaceId/_playlists/api/v2/playlistRuns"

Write-InfoMessage "Starting Tosca Cloud Execution Client"
Write-DebugMessage "Base URL: $BaseUrl"
Write-DebugMessage "Space ID: $SpaceId"
Write-DebugMessage "API URL: $apiUrl"

try {
    # Fetch the playlist runs
    $playlistRuns = Get-PlaylistRuns -Url $apiUrl -Token $BearerToken -Timeout $RequestTimeout
    
    # If PlaylistName is provided, extract the playlist ID
    if ($PlaylistName) {
        Write-InfoMessage "=== STEP 1: Extracting Playlist ID ==="
        $playlistId = Get-PlaylistIdByName -PlaylistRunsResponse $playlistRuns -TargetPlaylistName $PlaylistName
        
        if ($playlistId) {
            Write-InfoMessage "Step 1 completed successfully - Playlist ID: $playlistId"
            
            # If StartNewRun is specified, proceed to Step 2
            if ($StartNewRun) {
                Write-InfoMessage "`n=== STEP 2: Starting New Playlist Run ==="
                
                try {
                    $newRunResponse = Start-NewPlaylistRun -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -PlaylistId $playlistId -IsPrivate $RunPrivate -Timeout $RequestTimeout
                    
                    Write-InfoMessage "Step 2 completed successfully"
                    
                    # Extract new run ID for potential Step 3
                    $newRunId = $newRunResponse.id
                    
                    # If MonitorRun is specified, proceed to Step 3
                    if ($MonitorRun -and $newRunId) {
                        Write-InfoMessage "`n=== STEP 3: Monitoring Playlist Run ==="
                        
                        try {
                            $finalRunResponse = Watch-PlaylistRun -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -RunId $newRunId -PollingIntervalSeconds $PollingInterval -MaxTimeoutSeconds $MaxPollingTimeout -RequestTimeout $RequestTimeout
                            
                            Write-InfoMessage "Step 3 completed successfully"
                            
                            # If RetrieveResults is specified, proceed to Step 4
                            if ($RetrieveResults) {
                                Write-InfoMessage "`n=== STEP 4: Retrieving JUnit Test Results ==="
                                
                                try {
                                    $junitResults = Get-JUnitResults -BaseUrl $BaseUrl -SpaceId $SpaceId -Token $BearerToken -RunId $newRunId -JUnitResultsFileName $JUnitResultsFile -RequestTimeout $RequestTimeout
                                    
                                    Write-InfoMessage "Step 4 completed successfully"
                                    
                                    Write-InfoMessage "`n=== ALL FOUR STEPS COMPLETED SUCCESSFULLY ==="
                                    Write-InfoMessage "Original Playlist ID: $playlistId"
                                    Write-InfoMessage "New Run ID: $newRunId"
                                    Write-InfoMessage "Final State: $($finalRunResponse.state)"
                                    if ($junitResults) {
                                        Write-InfoMessage "JUnit Results File: $($junitResults.FileName)"
                                        Write-InfoMessage "JUnit Results Size: $([math]::Round($junitResults.SizeBytes / 1024, 2)) KB"
                                    }
                                    
                                    # Exit with appropriate code based on final state
                                    $successStates = @("passed", "completed", "succeeded")
                                    $isSuccess = $successStates -contains $finalRunResponse.state.ToLower()
                                    exit $(if ($isSuccess) { 0 } else { 1 })
                                    
                                } catch {
                                    Write-ErrorMessage "Step 4 failed: $($_.Exception.Message)"
                                    exit 1
                                }
                            } else {
                                # Steps 1, 2, and 3 only
                                Write-InfoMessage "`n=== STEPS 1, 2, AND 3 COMPLETED SUCCESSFULLY ==="
                                Write-InfoMessage "Original Playlist ID: $playlistId"
                                Write-InfoMessage "New Run ID: $newRunId"
                                Write-InfoMessage "Final State: $($finalRunResponse.state)"
                                
                                # Exit with appropriate code based on final state
                                $successStates = @("passed", "completed", "succeeded")
                                $isSuccess = $successStates -contains $finalRunResponse.state.ToLower()
                                exit $(if ($isSuccess) { 0 } else { 1 })
                            }
                            
                        } catch {
                            Write-ErrorMessage "Step 3 failed: $($_.Exception.Message)"
                            exit 1
                        }
                    } else {
                        # Steps 1 + 2 only
                        Write-InfoMessage "`n=== STEPS 1 AND 2 COMPLETED SUCCESSFULLY ==="
                        Write-InfoMessage "Original Playlist ID: $playlistId"
                        if ($newRunResponse.id) {
                            Write-InfoMessage "New Run ID: $($newRunResponse.id)"
                        }
                        
                        exit 0
                    }
                    
                } catch {
                    Write-ErrorMessage "Step 2 failed: $($_.Exception.Message)"
                    exit 1
                }
            } else {
                # Step 1 only - just output the playlist ID
                Write-Output $playlistId
                Write-InfoMessage "Step 1 completed successfully - Playlist ID: $playlistId"
                exit 0
            }
        } else {
            Write-ErrorMessage "Step 1 failed - Could not find playlist ID for name: '$PlaylistName'"
            exit 1
        }
    } else {
        # No playlist name provided - just return all playlist runs
        Write-Output ($playlistRuns | ConvertTo-Json -Depth 10)
        Write-InfoMessage "Script completed successfully"
        exit 0
    }
    
} catch {
    Write-ErrorMessage "Script execution failed: $($_.Exception.Message)"
    exit 1
}
