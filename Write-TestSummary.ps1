<#
.SYNOPSIS
    Writes a JUnit results file to the GitHub Actions job summary as a table.

.DESCRIPTION
    Reads the JUnit XML produced by tosca_cloud_execution_client.ps1 and appends a
    Markdown report (totals plus one row per test case) to $env:GITHUB_STEP_SUMMARY,
    which GitHub shows on the run's Summary page. Outside Actions, prints to stdout.

.EXAMPLE
    ./Write-TestSummary.ps1 -ResultsFile test-results/results.xml
#>
param(
    [Parameter(Mandatory)] [string]$ResultsFile,
    [string]$Title = 'Tosca test results'
)

$ErrorActionPreference = 'Stop'

function Format-Duration([double]$Seconds) {
    $ts = [timespan]::FromSeconds($Seconds)
    if ($ts.TotalHours -ge 1) { return $ts.ToString('h\:mm\:ss') }
    return $ts.ToString('m\:ss')
}

$lines = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $ResultsFile)) {
    $lines.Add("## $Title")
    $lines.Add('')
    $lines.Add(":warning: No results file was produced (``$ResultsFile``). The playlist may not have run.")
} else {
    [xml]$xml = Get-Content -LiteralPath $ResultsFile -Raw
    $cases = @($xml.SelectNodes('//testcase'))

    # Tosca puts the playlist name on the root <testsuites> element.
    $playlist = $xml.DocumentElement.GetAttribute('name')
    $lines.Add($(if ($playlist) { "## ${Title}: $playlist" } else { "## $Title" }))
    $lines.Add('')

    $rows = @(foreach ($case in $cases) {
        $status =
            if ($case.SelectSingleNode('failure|error')) { 'Failed' }
            elseif ($case.SelectSingleNode('skipped'))   { 'Skipped' }
            else                                         { 'Passed' }
        [pscustomobject]@{
            Suite   = $case.ParentNode.GetAttribute('name')
            Name    = $case.GetAttribute('name')
            Status  = $status
            Seconds = [double]('0' + $case.GetAttribute('time'))
        }
    })

    $passed  = @($rows | Where-Object Status -eq 'Passed').Count
    $failed  = @($rows | Where-Object Status -eq 'Failed').Count
    $skipped = @($rows | Where-Object Status -eq 'Skipped').Count
    $total   = $rows.Count
    $rate    = if ($total) { [math]::Round(100 * $passed / $total) } else { 0 }
    $time    = ($rows | Measure-Object Seconds -Sum).Sum

    $icon = @{ Passed = ':white_check_mark:'; Failed = ':x:'; Skipped = ':fast_forward:' }
    $headline = if ($failed) { ':x: **Failed**' } elseif ($total) { ':white_check_mark: **Passed**' } else { ':warning: **No tests ran**' }

    $lines.Add("$headline &nbsp; $passed of $total passed ($rate%) &nbsp;&middot;&nbsp; $failed failed &nbsp;&middot;&nbsp; $skipped skipped &nbsp;&middot;&nbsp; $(Format-Duration $time)")
    $lines.Add('')

    if ($total) {
        $suites = @($rows.Suite | Select-Object -Unique)
        $lines.Add($(if ($suites.Count -gt 1) { '| | Suite | Test | Duration |' } else { '| | Test | Duration |' }))
        $lines.Add($(if ($suites.Count -gt 1) { '|---|---|---|---:|' }         else { '|---|---|---:|' }))
        # Failures first, then in run order. Escape '|' so test names don't split cells.
        $ordered = @($rows | Where-Object Status -eq 'Failed') + @($rows | Where-Object Status -ne 'Failed')
        foreach ($r in $ordered) {
            $name  = $r.Name  -replace '\|', '\|'
            $suite = $r.Suite -replace '\|', '\|'
            $cells = if ($suites.Count -gt 1) { "$suite | $name" } else { $name }
            $lines.Add("| $($icon[$r.Status]) | $cells | $(Format-Duration $r.Seconds) |")
        }
    }
}

$markdown = ($lines -join "`n") + "`n"
if ($env:GITHUB_STEP_SUMMARY) {
    Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $markdown -Encoding utf8
} else {
    $markdown
}
