#Requires -Version 5.1
<#
.SYNOPSIS
    Triggers a Tosca Cloud playlist run, monitors it to completion, and retrieves JUnit results.

.DESCRIPTION
    A customer-agnostic, CI-friendly client for the Tosca Cloud Playlists API (v2).

    Flow:
        1. Acquire an OAuth2 access token (client credentials) or use a supplied bearer token.
        2. Resolve the target playlist by -PlaylistId (preferred) or -PlaylistName (catalog lookup).
        3. Optionally start a run (-StartNewRun; implied by -MonitorRun / -RetrieveResults).
        4. Optionally poll the run to a terminal state (-MonitorRun).
        5. Optionally download JUnit results as compatible UTF-8 XML (-RetrieveResults).

    All configuration is supplied via parameters, except the client secret:
    when -ClientSecret is omitted it is read from the TOSCA_CLIENT_SECRET
    environment variable, so the secret need not appear on the command line.

.NOTES
    Exit codes:
        0  Success (run succeeded, or requested action completed).
        1  Unexpected/generic error.
        2  Usage / missing-parameter error.
        3  Authentication failure.
        4  Playlist could not be resolved (not found or ambiguous).
        5  Failed to start the playlist run.
        6  Monitoring timed out.
        7  Run completed but did not succeed (failed/canceled).
        8  Failed to retrieve JUnit results.

    Known limitation: the Playlists API exposes no idempotency key on run creation,
    so a lost response after a successful POST cannot be safely auto-retried; run
    creation is therefore not retried on ambiguous network failures.

.EXAMPLE
    # Recommended CI usage: secret from environment, run + monitor + results
    $env:TOSCA_CLIENT_SECRET = '***'
    .\tosca_cloud_execution_client.ps1 `
        -BaseUrl 'https://acme.my.tricentis.com' -WorkspaceId '<workspace-guid>' `
        -TokenUrl 'https://acme.okta.com/oauth2/default/v1/token' `
        -ClientId 'Tricentis_Cloud_API' -Scope 'tta' `
        -PlaylistName 'Regression - Web To Lead - End to End' `
        -StartNewRun -MonitorRun -RetrieveResults `
        -JUnitResultsFile 'results.xml'
#>
[CmdletBinding()]
param(
    [string]$BaseUrl,
    [string]$WorkspaceId,
    [string]$TokenUrl,
    [string]$ClientId,
    # Sole env-var default: read from TOSCA_CLIENT_SECRET when -ClientSecret is
    # omitted, so the secret can be supplied via the pipeline's env: block rather
    # than on the command line. All other values are passed as explicit args.
    [string]$ClientSecret                   = $env:TOSCA_CLIENT_SECRET,
    [string]$BearerToken,
    [string]$Scope,

    [string]$PlaylistId,
    [string]$PlaylistName,
    [switch]$RunPrivate,
    [string[]]$ParameterOverride,

    [switch]$StartNewRun,
    [switch]$MonitorRun,
    [switch]$RetrieveResults,
    [switch]$CancelOnTimeout,

    [ValidateRange(1, 3600)]  [int]$PollingInterval          = 10,
    [ValidateRange(1, 86400)] [int]$MaxPollingTimeout        = 7200,
    [ValidateRange(5, 600)]   [int]$RequestTimeout           = 60,
    [ValidateRange(0, 10)]    [int]$MaxRetries               = 4,
    [ValidateRange(1, 50)]    [int]$MaxConsecutivePollErrors = 5,

    [string]$JUnitResultsFile = 'junit_results.xml',
    [ValidateSet('utf8bom', 'utf8')] [string]$JUnitEncoding = 'utf8bom',
    [string]$SummaryJsonFile,
    [ValidateSet('text', 'json')] [string]$LogFormat = 'text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

# Ensure TLS 1.2+ on Windows PowerShell 5.1 (default may negotiate TLS 1.0/1.1).
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# ----------------------------------------------------------------------------
# Exit codes
# ----------------------------------------------------------------------------
$EXIT_SUCCESS            = 0
$EXIT_GENERIC            = 1
$EXIT_USAGE             = 2
$EXIT_AUTH              = 3
$EXIT_PLAYLIST_NOT_FOUND = 4
$EXIT_RUN_START         = 5
$EXIT_TIMEOUT           = 6
$EXIT_TEST_FAILED       = 7
$EXIT_RESULTS           = 8

# Typed error that carries the intended process exit code.
class ToscaError : System.Exception {
    [int]$ExitCode
    ToscaError([string]$message, [int]$exitCode) : base($message) { $this.ExitCode = $exitCode }
}

# ----------------------------------------------------------------------------
# Script state
# ----------------------------------------------------------------------------
$script:CorrelationId = [guid]::NewGuid().ToString('n').Substring(0, 8)
$script:ExitCode      = $EXIT_SUCCESS
$script:Secrets       = New-Object System.Collections.Generic.List[string]
$script:Token         = @{ Value = $null; ExpiresAt = [datetime]::MinValue; Static = $false }

# ----------------------------------------------------------------------------
# Secret redaction + logging
# ----------------------------------------------------------------------------
function Add-Secret {
    param([string]$Value)
    if ($Value -and -not $script:Secrets.Contains($Value)) { $script:Secrets.Add($Value) | Out-Null }
}

function Protect-Text {
    param([string]$Text)
    if (-not $Text) { return $Text }
    foreach ($s in $script:Secrets) { if ($s) { $Text = $Text.Replace($s, '***REDACTED***') } }
    # Scrub anything that looks like a bearer token, even if not in the known-secret list.
    $Text = [regex]::Replace($Text, '(?i)(Bearer\s+)[A-Za-z0-9\._\-]+', '${1}***REDACTED***')
    return $Text
}

function Write-ToscaLog {
    param(
        [ValidateSet('Debug', 'Info', 'Warn', 'Error')][string]$Level = 'Info',
        [Parameter(Mandatory)][string]$Message
    )
    $safe = Protect-Text $Message
    $ts   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    if ($LogFormat -eq 'json') {
        $line = [pscustomobject]@{
            timestamp     = $ts
            level         = $Level.ToLowerInvariant()
            correlationId = $script:CorrelationId
            message       = $safe
        } | ConvertTo-Json -Compress
    } else {
        $line = "[{0}] [{1}] [{2}] {3}" -f $ts, $Level.ToUpperInvariant(), $script:CorrelationId, $safe
    }
    switch ($Level) {
        'Debug' { Write-Verbose     $line }
        'Info'  { Write-Information $line }
        'Warn'  { Write-Warning     $line }
        # Route error-level *logs* to the information stream so $ErrorActionPreference='Stop'
        # doesn't turn a log line into a terminating error. Real failures are thrown.
        'Error' { Write-Information $line }
    }
}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

# StrictMode-safe optional property read (JSON responses vary between versions/tenants).
function Get-Prop {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value } else { return $null }
}

function Get-BaseUri {
    return $BaseUrl.TrimEnd('/')
}

function Get-HttpErrorInfo {
    param($ErrorRecord)
    $status = $null
    $retryAfter = $null
    $ex = $ErrorRecord.Exception
    $resp = $null
    if ($ex -and $ex.PSObject.Properties['Response']) { $resp = $ex.Response }
    if ($resp) {
        try { if ($resp.PSObject.Properties['StatusCode']) { $status = [int]$resp.StatusCode } } catch { }
        try {
            $hdrs = $null
            if ($resp.PSObject.Properties['Headers']) { $hdrs = $resp.Headers }
            if ($hdrs) {
                # PowerShell 7 (HttpResponseMessage): Headers.RetryAfter.Delta
                if ($hdrs.PSObject.Properties['RetryAfter'] -and $hdrs.RetryAfter -and $hdrs.RetryAfter.Delta) {
                    $retryAfter = [int]$hdrs.RetryAfter.Delta.TotalSeconds
                } else {
                    # Windows PowerShell 5.1 (WebHeaderCollection)
                    try { $ra = $hdrs['Retry-After']; if ($ra) { $retryAfter = [int]$ra } } catch { }
                }
            }
        } catch { }
    }
    return [pscustomobject]@{ StatusCode = $status; RetryAfter = $retryAfter }
}

function Get-HttpErrorBody {
    param($ErrorRecord)
    try {
        # PowerShell 7+: the body is already on the ErrorDetails
        if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
            return (Protect-Text $ErrorRecord.ErrorDetails.Message)
        }
        # Windows PowerShell 5.1: read it off the response stream
        $resp = $ErrorRecord.Exception.Response
        if ($resp -and $resp.PSObject.Methods['GetResponseStream']) {
            $stream = $resp.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $text   = $reader.ReadToEnd()
            $reader.Dispose()
            if ($text) { return (Protect-Text $text) }
        }
    } catch { }
    return $null
}

# HTTP wrapper with exponential backoff + jitter. Retries transient failures only.
function Invoke-ToscaRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('Get', 'Post', 'Delete')][string]$Method = 'Get',
        [hashtable]$Headers,
        [string]$Body,
        [string]$ContentType,
        [int]$TimeoutSec = $RequestTimeout,
        [switch]$Raw
    )
    if (-not $Headers) { $Headers = @{} }
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $params = @{
                Uri             = $Uri
                Method          = $Method
                Headers         = $Headers
                TimeoutSec      = $TimeoutSec
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }
            if ($Body)        { $params.Body        = $Body }
            if ($ContentType) { $params.ContentType = $ContentType }

            if ($Raw) { return Invoke-WebRequest @params }
            else      { return Invoke-RestMethod @params }
		} catch {
					$info      = Get-HttpErrorInfo $_
					$status    = $info.StatusCode
					$transient = (-not $status) -or ($status -eq 408) -or ($status -eq 429) -or ($status -ge 500)

					if ((-not $transient) -or ($attempt -gt $MaxRetries)) {
						$bodyText = Get-HttpErrorBody $_
						if ($bodyText) {
							throw ("{0} | response body: {1}" -f $_.Exception.Message, $bodyText)
						}
						throw
					}

            if ($info.RetryAfter -and $info.RetryAfter -gt 0) {
                $delaySec = [math]::Min(120, $info.RetryAfter)
            } else {
                $delaySec = [math]::Min(60, [math]::Pow(2, $attempt - 1))
            }
            $jitterMs = Get-Random -Minimum 0 -Maximum 1000
            $totalMs  = [int](($delaySec * 1000) + $jitterMs)
            $statusText = if ($status) { "HTTP $status" } else { 'network error' }
            Write-ToscaLog -Level Warn -Message (
                "Request {0} {1} failed ({2}); retry {3}/{4} in {5:N1}s: {6}" -f `
                    $Method, $Uri, $statusText, $attempt, $MaxRetries, ($totalMs / 1000), $_.Exception.Message)
            Start-Sleep -Milliseconds $totalMs
        }
    }
}

# ----------------------------------------------------------------------------
# Authentication (token cache + proactive refresh)
# ----------------------------------------------------------------------------
function Get-AccessToken {
    $now = (Get-Date).ToUniversalTime()

    if ($script:Token.Value -and
        ($script:Token.Static -or $now -lt $script:Token.ExpiresAt.AddSeconds(-60))) {
        return $script:Token.Value
    }

    if ($BearerToken) {
        $script:Token.Value     = $BearerToken
        $script:Token.Static    = $true
        $script:Token.ExpiresAt = $now.AddYears(1)
        return $BearerToken
    }

    Write-ToscaLog -Level Info -Message 'Requesting access token via client credentials.'
    $parts = @(
        'grant_type=client_credentials',
        ('client_id='     + [uri]::EscapeDataString($ClientId)),
        ('client_secret=' + [uri]::EscapeDataString($ClientSecret))
    )
    if ($Scope) { $parts += ('scope=' + [uri]::EscapeDataString($Scope)) }
    $body = ($parts -join '&')

    $resp = Invoke-ToscaRequest -Uri $TokenUrl -Method Post `
        -Headers @{ Accept = 'application/json' } `
        -Body $body -ContentType 'application/x-www-form-urlencoded'

    $token = Get-Prop $resp 'access_token'
    if (-not $token) {
        throw [ToscaError]::new('Token endpoint response did not contain an access_token.', $EXIT_AUTH)
    }
    Add-Secret $token

    $expiresIn = Get-Prop $resp 'expires_in'
    if (-not $expiresIn) { $expiresIn = 3600 }

    $script:Token.Value     = $token
    $script:Token.Static    = $false
    $script:Token.ExpiresAt = $now.AddSeconds([int]$expiresIn)
    Write-ToscaLog -Level Info -Message ("Access token acquired; expires in {0}s." -f $expiresIn)
    return $token
}

function Get-AuthHeaders {
    param([string]$Accept = 'application/json')
    $token = Get-AccessToken
    return @{ Authorization = ("Bearer " + $token); Accept = $Accept }
}

# ----------------------------------------------------------------------------
# Playlist resolution (by id, or by name via the catalog endpoint)
# ----------------------------------------------------------------------------
function Resolve-PlaylistId {
    if ($PlaylistId) {
        Write-ToscaLog -Level Info -Message ("Using provided playlist id {0}." -f $PlaylistId)
        return $PlaylistId
    }

    Write-ToscaLog -Level Info -Message ("Resolving playlist by name '{0}' via catalog." -f $PlaylistName)
    $encoded   = [uri]::EscapeDataString($PlaylistName)
    $collected = New-Object System.Collections.Generic.List[object]
    $pageToken = $null
    $page      = 0

    do {
        $page++
        $u = "{0}/{1}/_playlists/api/v2/playlists?name={2}&itemsPerPage=200" -f (Get-BaseUri), $WorkspaceId, $encoded
        if ($pageToken) { $u = $u + '&pageToken=' + [uri]::EscapeDataString($pageToken) }

        try {
            $resp = Invoke-ToscaRequest -Uri $u -Method Get -Headers (Get-AuthHeaders 'application/json')
        } catch {
            throw [ToscaError]::new(
                "Playlist lookup failed: $((Protect-Text $_.Exception.Message))", $EXIT_PLAYLIST_NOT_FOUND)
        }

        $items = Get-Prop $resp 'items'
        if ($items) { foreach ($it in $items) { $collected.Add($it) | Out-Null } }
        $pageToken = Get-Prop $resp 'nextPageToken'
    } while ($pageToken -and $page -lt 50)

    # Names are matched case-sensitively for CI determinism; the server filter may be
    # case-insensitive, so re-verify client-side rather than trust the returned set.
    $exact = @($collected | Where-Object { (Get-Prop $_ 'name') -ceq $PlaylistName })

    if ($exact.Count -eq 0) {
        $ci = @($collected | Where-Object { (Get-Prop $_ 'name') -ieq $PlaylistName })
        if ($ci.Count -gt 0) {
            $names = ($ci | ForEach-Object { "'" + (Get-Prop $_ 'name') + "'" } | Select-Object -Unique) -join ', '
            throw [ToscaError]::new(
                "No playlist exactly named '$PlaylistName'. Case-variant match(es): $names. " +
                "Names are case-sensitive here; correct the name or pass -PlaylistId.", $EXIT_PLAYLIST_NOT_FOUND)
        }
        throw [ToscaError]::new("No playlist found with name '$PlaylistName'.", $EXIT_PLAYLIST_NOT_FOUND)
    }

    if ($exact.Count -gt 1) {
        $ids = ($exact | ForEach-Object { Get-Prop $_ 'id' }) -join ', '
        throw [ToscaError]::new(
            "Found $($exact.Count) playlists named '$PlaylistName' (ids: $ids). " +
            "Re-run with -PlaylistId to disambiguate.", $EXIT_PLAYLIST_NOT_FOUND)
    }

    $rid = Get-Prop $exact[0] 'id'
    if (-not $rid) { throw [ToscaError]::new('Matched playlist has no id.', $EXIT_PLAYLIST_NOT_FOUND) }
    Write-ToscaLog -Level Info -Message ("Resolved '{0}' to playlist id {1}." -f $PlaylistName, $rid)
    return $rid
}

# ----------------------------------------------------------------------------
# Run creation
# ----------------------------------------------------------------------------
function ConvertTo-ParameterOverrides {
	$list = @()
	if ($ParameterOverride) {
		foreach ($p in $ParameterOverride) {
			$idx = $p.IndexOf('=')
			if ($idx -lt 1) {
				throw [ToscaError]::new("Invalid -ParameterOverride '$p'. Expected format: name=value.", $EXIT_USAGE)
			}
			$list += [pscustomobject]@{ name = $p.Substring(0, $idx); value = $p.Substring($idx + 1) }
		}
	}
	return ,$list
}

function Start-PlaylistRun {
    param([Parameter(Mandatory)][string]$ResolvedPlaylistId)

    Write-ToscaLog -Level Info -Message (
        "Starting playlist run (playlistId={0}, private={1})." -f $ResolvedPlaylistId, [bool]$RunPrivate)

    $url  = "{0}/{1}/_playlists/api/v2/playlistRuns" -f (Get-BaseUri), $WorkspaceId
    $bodyObj = @{ playlistId = $ResolvedPlaylistId; private = [bool]$RunPrivate }

    # NOTE: do NOT wrap this in @(). ConvertTo-ParameterOverrides already returns the
    # array intact via `return ,$list`; adding @() here nests it one level deeper, so
    # ConvertTo-Json emits parameterOverrides as [[{...}]] and the API rejects
    # $.parameterOverrides[0] (array where an object is expected) with HTTP 400.
    $overrides = ConvertTo-ParameterOverrides
    if ($overrides.Count -gt 0) {
        $bodyObj.parameterOverrides = $overrides
        Write-ToscaLog -Level Info -Message ("Applying {0} parameter override(s)." -f $overrides.Count)
    }
    $json = $bodyObj | ConvertTo-Json -Depth 5
    Write-ToscaLog -Level Debug -Message ("Run request body: {0}" -f $json)

    try {
        $resp = Invoke-ToscaRequest -Uri $url -Method Post `
            -Headers (Get-AuthHeaders 'application/json') `
            -Body $json -ContentType 'application/json'
    } catch {
        throw [ToscaError]::new(
            "Failed to start playlist run: $((Protect-Text $_.Exception.Message))", $EXIT_RUN_START)
    }

    $runId = Get-Prop $resp 'id'
    if (-not $runId) { $runId = Get-Prop $resp 'executionId' }
    if (-not $runId) {
        throw [ToscaError]::new('Run creation response did not contain a run id.', $EXIT_RUN_START)
    }
    Write-ToscaLog -Level Info -Message ("Playlist run started; run id {0}." -f $runId)
    return $runId
}

# ----------------------------------------------------------------------------
# Monitoring
# ----------------------------------------------------------------------------
function Invoke-CancelRun {
    param([Parameter(Mandatory)][string]$RunId)
    Write-ToscaLog -Level Info -Message ("Requesting cancellation of run {0}." -f $RunId)
    $url  = "{0}/{1}/_playlists/api/v2/playlistRuns/{2}:cancel" -f (Get-BaseUri), $WorkspaceId, $RunId
    $body = @{ reason = 'Cancelled by CI client after monitoring timeout.'; hardCancel = $false } | ConvertTo-Json
    try {
        Invoke-ToscaRequest -Uri $url -Method Post `
            -Headers (Get-AuthHeaders 'application/json') `
            -Body $body -ContentType 'application/json' | Out-Null
        Write-ToscaLog -Level Info -Message 'Cancellation request accepted.'
    } catch {
        Write-ToscaLog -Level Warn -Message (
            "Failed to cancel run {0}: {1}" -f $RunId, (Protect-Text $_.Exception.Message))
    }
}

function Wait-PlaylistRun {
    param([Parameter(Mandatory)][string]$RunId)

    Write-ToscaLog -Level Info -Message (
        "Monitoring run {0}: poll every {1}s, timeout {2}s." -f $RunId, $PollingInterval, $MaxPollingTimeout)

    $url        = "{0}/{1}/_playlists/api/v2/playlistRuns/{2}" -f (Get-BaseUri), $WorkspaceId, $RunId
    $terminal   = @('succeeded', 'failed', 'canceled')
    $start      = Get-Date
    $deadline   = $start.AddSeconds($MaxPollingTimeout)
    $poll       = 0
    $consecErr  = 0
    $consecUnk  = 0

    while ((Get-Date) -lt $deadline) {
        $poll++
        try {
            $resp = Invoke-ToscaRequest -Uri $url -Method Get -Headers (Get-AuthHeaders 'application/json')
            $consecErr = 0

            $state   = Get-Prop $resp 'state'
            $stateL  = if ($state) { ([string]$state).ToLowerInvariant() } else { '' }
            $elapsed = [math]::Round(((Get-Date) - $start).TotalSeconds, 0)
            Write-ToscaLog -Level Info -Message ("Poll #{0} (elapsed {1}s): state={2}" -f $poll, $elapsed, $state)

            if ($terminal -contains $stateL) {
                return [pscustomobject]@{ RunId = $RunId; State = $stateL; TimedOut = $false; Response = $resp }
            }

            if ($stateL -eq 'unknown') {
                $consecUnk++
                if ($consecUnk -ge $MaxConsecutivePollErrors) {
                    throw [ToscaError]::new(
                        "Run $RunId reported 'unknown' state $consecUnk times in a row; aborting.", $EXIT_GENERIC)
                }
            } else {
                $consecUnk = 0
            }
        } catch {
            if ($_.Exception -is [ToscaError]) { throw }
            $consecErr++
            Write-ToscaLog -Level Warn -Message (
                "Poll #{0} failed ({1}/{2}): {3}" -f `
                    $poll, $consecErr, $MaxConsecutivePollErrors, (Protect-Text $_.Exception.Message))
            if ($consecErr -ge $MaxConsecutivePollErrors) {
                throw [ToscaError]::new("Aborting after $consecErr consecutive polling errors.", $EXIT_GENERIC)
            }
        }
        Start-Sleep -Seconds $PollingInterval
    }

    Write-ToscaLog -Level Warn -Message ("Monitoring timed out after {0}s." -f $MaxPollingTimeout)
    if ($CancelOnTimeout) { Invoke-CancelRun -RunId $RunId }
    return [pscustomobject]@{ RunId = $RunId; State = 'timeout'; TimedOut = $true; Response = $null }
}

# ----------------------------------------------------------------------------
# JUnit retrieval (Accept: application/xml -> byte-accurate, consistent UTF-8)
# ----------------------------------------------------------------------------
function Get-ResponseBytes {
    param($Response)
    if ($null -eq $Response) { return $null }

    $stream = $null
    try { if ($Response.PSObject.Properties['RawContentStream']) { $stream = $Response.RawContentStream } } catch { }
    if ($stream) {
        try {
            $ms = New-Object System.IO.MemoryStream
            try { $stream.Position = 0 } catch { }
            $stream.CopyTo($ms)
            $bytes = $ms.ToArray()
            $ms.Dispose()
            if ($bytes.Length -gt 0) { return $bytes }
        } catch { }
    }

    $content = Get-Prop $Response 'Content'
    if ($content -is [byte[]]) { return $content }
    if ($content)              { return [System.Text.Encoding]::UTF8.GetBytes([string]$content) }
    return $null
}

function Resolve-OutputPath {
    param([string]$File, [switch]$ForceXml)
    if ([string]::IsNullOrWhiteSpace($File)) { $File = 'junit_results.xml' }
    if ($ForceXml -and -not $File.EndsWith('.xml', [System.StringComparison]::OrdinalIgnoreCase)) {
        $File += '.xml'
    }
    if (-not [System.IO.Path]::IsPathRooted($File)) {
        $File = Join-Path -Path (Get-Location).Path -ChildPath $File
    }
    return $File
}

function Write-JUnitXml {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$EncodingChoice
    )
    $withBom = ($EncodingChoice -eq 'utf8bom')
    $enc     = New-Object System.Text.UTF8Encoding($withBom)

    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Parse, then re-serialize so the XML declaration always matches the on-disk
    # encoding (avoids the "declared utf-16 / written utf-8" class of parser errors).
    $xml = $null
    try {
        $xml = New-Object System.Xml.XmlDocument
        $xml.XmlResolver = $null
        $ms = New-Object System.IO.MemoryStream (, $Bytes)
        $xml.Load($ms)
        $ms.Dispose()
    } catch {
        Write-ToscaLog -Level Warn -Message (
            "Response was not well-formed XML ({0}); writing bytes verbatim." -f (Protect-Text $_.Exception.Message))
        $xml = $null
    }

    if ($xml) {
        $settings          = New-Object System.Xml.XmlWriterSettings
        $settings.Encoding = $enc
        $settings.Indent   = $true
        $sw = $null; $xw = $null
        try {
            $sw = New-Object System.IO.StreamWriter($Path, $false, $enc)
            $xw = [System.Xml.XmlWriter]::Create($sw, $settings)
            $xml.Save($xw)
        } finally {
            if ($xw) { $xw.Dispose() }
            if ($sw) { $sw.Dispose() }
        }
    } else {
        [System.IO.File]::WriteAllBytes($Path, $Bytes)
    }
}

function Save-JUnitResults {
    param([Parameter(Mandatory)][string]$RunId, [string]$OutFile)

    Write-ToscaLog -Level Info -Message ("Retrieving JUnit results for run {0}." -f $RunId)
    $url = "{0}/{1}/_playlists/api/v2/playlistRuns/{2}/junit" -f (Get-BaseUri), $WorkspaceId, $RunId

    try {
        $resp = Invoke-ToscaRequest -Uri $url -Method Get -Headers (Get-AuthHeaders 'application/xml') -Raw
    } catch {
        throw [ToscaError]::new(
            "Failed to retrieve JUnit results: $((Protect-Text $_.Exception.Message))", $EXIT_RESULTS)
    }

    $bytes = Get-ResponseBytes $resp
    if (-not $bytes -or $bytes.Length -eq 0) {
        throw [ToscaError]::new('JUnit response was empty.', $EXIT_RESULTS)
    }

    $path = Resolve-OutputPath -File $OutFile -ForceXml
    Write-JUnitXml -Bytes $bytes -Path $path -EncodingChoice $JUnitEncoding

    $fi = Get-Item -LiteralPath $path
    Write-ToscaLog -Level Info -Message ("Saved JUnit results to {0} ({1:N1} KB)." -f $path, ($fi.Length / 1024))
    return $path
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
function Complete-Run {
    param([Parameter(Mandatory)]$Summary)
    $Summary.finishedUtc = (Get-Date).ToUniversalTime().ToString('o')
    Write-ToscaLog -Level Info -Message (
        "Summary: state={0} runId={1} exitCode={2}" -f $Summary.state, $Summary.runId, $Summary.exitCode)

    if ($SummaryJsonFile) {
        try {
            $p    = Resolve-OutputPath -File $SummaryJsonFile
            $json = ([pscustomobject]$Summary | ConvertTo-Json -Depth 5)
            [System.IO.File]::WriteAllText($p, $json, (New-Object System.Text.UTF8Encoding($false)))
            Write-ToscaLog -Level Info -Message ("Wrote summary JSON to {0}." -f $p)
        } catch {
            Write-ToscaLog -Level Warn -Message (
                "Failed to write summary JSON: {0}" -f (Protect-Text $_.Exception.Message))
        }
    }
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
function Invoke-Main {
    Add-Secret $ClientSecret
    Add-Secret $BearerToken

    Write-ToscaLog -Level Info  -Message ("Tosca Cloud Execution Client (correlation {0})." -f $script:CorrelationId)
    Write-ToscaLog -Level Debug -Message ("BaseUrl={0} WorkspaceId={1} TokenUrl={2} ClientId={3}" -f $BaseUrl, $WorkspaceId, $TokenUrl, $ClientId)

    # --- Validate configuration (no interactive prompts in CI) ---
    $missing = @()
    if (-not $BaseUrl) { $missing += '-BaseUrl' }
    if (-not $WorkspaceId) { $missing += '-WorkspaceId' }
    if ($missing.Count -gt 0) {
        throw [ToscaError]::new("Missing required parameter(s): $($missing -join ', ').", $EXIT_USAGE)
    }

    if (-not $PlaylistId -and -not $PlaylistName) {
        throw [ToscaError]::new('Provide -PlaylistId or -PlaylistName.', $EXIT_USAGE)
    }
    if ($PlaylistId -and $PlaylistName) {
        Write-ToscaLog -Level Warn -Message 'Both -PlaylistId and -PlaylistName supplied; -PlaylistId takes precedence.'
    }

    if (-not $BearerToken) {
        $authMissing = @()
        if (-not $TokenUrl)     { $authMissing += '-TokenUrl' }
        if (-not $ClientId)     { $authMissing += '-ClientId' }
        if (-not $ClientSecret) { $authMissing += '-ClientSecret (or the TOSCA_CLIENT_SECRET env var)' }
        if ($authMissing.Count -gt 0) {
            throw [ToscaError]::new(
                "Missing authentication input: $($authMissing -join ', ') (or supply -BearerToken).", $EXIT_AUTH)
        }
    }

    # Requested actions (later switches imply earlier prerequisites).
    $doStart   = [bool]($StartNewRun -or $MonitorRun -or $RetrieveResults)
    $doMonitor = [bool]($MonitorRun -or $RetrieveResults)
    $doResults = [bool]$RetrieveResults

    $summary = [ordered]@{
        correlationId = $script:CorrelationId
        playlistId    = $null
        playlistName  = $PlaylistName
        runId         = $null
        state         = $null
        timedOut      = $false
        resultsFile   = $null
        startedUtc    = (Get-Date).ToUniversalTime().ToString('o')
        finishedUtc   = $null
        exitCode      = $EXIT_SUCCESS
    }

    # --- Authenticate up front (fail fast with a clean auth exit code) ---
    try { Get-AccessToken | Out-Null }
    catch {
        if ($_.Exception -is [ToscaError]) { throw }
        throw [ToscaError]::new("Authentication failed: $((Protect-Text $_.Exception.Message))", $EXIT_AUTH)
    }

    # --- Resolve playlist ---
    $resolvedId = Resolve-PlaylistId
    $summary.playlistId = $resolvedId

    if (-not $doStart) {
        Write-Output $resolvedId   # machine-readable stdout for the resolve-only use case
        $script:ExitCode = $EXIT_SUCCESS
        Complete-Run $summary
        return
    }

    # --- Start run ---
    $runId = Start-PlaylistRun -ResolvedPlaylistId $resolvedId
    $summary.runId = $runId

    if (-not $doMonitor) {
        $script:ExitCode = $EXIT_SUCCESS
        Complete-Run $summary
        return
    }

    # --- Monitor ---
    $watch = Wait-PlaylistRun -RunId $runId
    $summary.state    = $watch.State
    $summary.timedOut = $watch.TimedOut

    if ($watch.TimedOut) {
        $script:ExitCode = $EXIT_TIMEOUT
        Complete-Run $summary
        return
    }

    # --- Retrieve results (even on failure, so failing tests still get published) ---
    if ($doResults) {
        $path = Save-JUnitResults -RunId $runId -OutFile $JUnitResultsFile
        $summary.resultsFile = $path
    }

    if ($watch.State -eq 'succeeded') {
        $script:ExitCode = $EXIT_SUCCESS
    } else {
        Write-ToscaLog -Level Warn -Message ("Run did not succeed; final state: {0}." -f $watch.State)
        $script:ExitCode = $EXIT_TEST_FAILED
    }
    $summary.exitCode = $script:ExitCode
    Complete-Run $summary
}

# ----------------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------------
try {
    Invoke-Main
} catch {
    if ($_.Exception -is [ToscaError]) {
        Write-ToscaLog -Level Error -Message $_.Exception.Message
        $script:ExitCode = $_.Exception.ExitCode
    } else {
        Write-ToscaLog -Level Error -Message ("Unexpected error: {0}" -f (Protect-Text $_.Exception.Message))
        if ($_.ScriptStackTrace) { Write-ToscaLog -Level Debug -Message (Protect-Text $_.ScriptStackTrace) }
        $script:ExitCode = $EXIT_GENERIC
    }
}

exit $script:ExitCode