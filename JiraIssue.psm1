# get baseUrl, username and token from $PROFILE file
$profilePath = $PROFILE
$profileContent = Get-Content $profilePath
$baseUrl = $profileContent | Select-String -Pattern 'baseUrl = "(.*)"' | ForEach-Object { $_.Matches.Groups[1].Value }
$username = $profileContent | Select-String -Pattern 'username = "(.*)"' | ForEach-Object { $_.Matches.Groups[1].Value }
$token = $profileContent | Select-String -Pattern 'token = "(.*)"' | ForEach-Object { $_.Matches.Groups[1].Value }


[string]$authHeader = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($username):$($token)")))"
function Get-JiraIssue {
    param (
        [string]$issueKey
    )
    
    $url = "$baseUrl/rest/api/3/issue/$issueKey"

    Write-Host "Getting issue $issueKey from Jira... @ $url"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}
    
    $issue = $response.fields.summary

    Write-Host "Issue: $issue"
    Write-Host "Description: $($response.fields.description)"
    Write-Host "Status: $($response.fields.status.name)"
    Write-Host "Assignee: $($response.fields.assignee.displayName)"
    Write-Host "Remaining Estimate: $($response.fields.timetracking.remainingEstimate)"
    Write-Host "Time Spent: $($response.fields.timetracking.timeSpent)"
}

function Get-EpicIssues {
    param (
        [string]$epicKey,
        # optional search parameter
        [string]$search = ""
    )

    if ($search -ne "") {
        $search = " AND text ~ '$search'"
    } else {
        $search = ""
    }

    $url = "$baseUrl/rest/api/3/search?jql=parentEpic = $epicKey and status not in (Done, Cancelled) $search ORDER BY priority DESC, status DESC &maxResults=100"

    Write-Host "Getting issues from epic $epicKey from Jira... @ $url"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}

    $issues = $response.issues

    $table = @()
    foreach ($issue in $issues) {
        $table += [PSCustomObject]@{
            Key       = $issue.key
            Issue     = $issue.fields.summary.Substring(0, [Math]::Min(75, $issue.fields.summary.Length))
            Priority  = $issue.fields.priority.name
            Status    = $issue.fields.status.name
            Link      = $issue.self
        }
    }

    $table | Format-Table -AutoSize
}

function Get-ProjectIssues {
    param (
        [string]$projectKey,
        # optional search parameter
        [string]$search = "",
        [switch]$MeMode
    )

    if ($search -ne "") {
        $search = " AND text ~ '$search'"
    } else {
        $search = ""
    }

    if ($MeMode) {
        $search += " AND assignee = currentUser()"
    }

    $url = "$baseUrl/rest/api/3/search?jql=project = $projectKey and status not in (Done, Cancelled) $search ORDER BY priority DESC, status DESC &maxResults=100"

    Write-Host "Getting issues from project $projectKey from Jira... @ $url"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}

    $issues = $response.issues

    $table = @()
    foreach ($issue in $issues) {
        $table += [PSCustomObject]@{
            Key       = $issue.key
            Issue     = $issue.fields.summary.Substring(0, [Math]::Min(75, $issue.fields.summary.Length))
            Assignee  = $issue.fields.assignee.displayName
            Priority  = $issue.fields.priority.name
            Status    = $issue.fields.status.name
            Link      = $issue.self
        }
    }

    $table | Format-Table -AutoSize
}

<#
.SYNOPSIS
Retrieves a list of projects from Jira.

.DESCRIPTION
The Get-Projects function connects to a Jira instance and retrieves a list of all projects available. This function is useful for obtaining project information for further processing or reporting.

.EXAMPLE
Get-Projects

This example retrieves all projects from the Jira instance and displays them.

.NOTES
Make sure you have the necessary permissions to access the Jira instance and retrieve project information.

#>
function Get-Projects {
    $url = "$baseUrl/rest/api/3/project"

    Write-Host "Getting projects from Jira... @ $url"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}

    $projects = $response

    $table = @()
    foreach ($project in $projects) {
        $table += [PSCustomObject]@{
            Key       = $project.key
            Name      = $project.name
            Link      = $project.self
        }
    }

    $table | Format-Table -AutoSize
}
