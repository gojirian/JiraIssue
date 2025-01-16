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
    clear-host
    Write-Host "Getting issue $issueKey from Jira... @ $url"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}

    # $projectUrl = "$baseUrl/rest/api/3/project/$($response.fields.project.id)"

    # $projectResponse = Invoke-RestMethod -Uri $projectUrl -Method Get -Headers @{Authorization = $authHeader}

    # get rules/automations 
    # $rulesUrl = "$baseUrl/rest/api/3/project/$($response.fields.project.key)/automation"
    # Write-Host "Getting rules from Jira... @ $rulesUrl"
    # $rulesResponse = Invoke-RestMethod -Uri $rulesUrl -Method Get -Headers @{Authorization = $authHeader}

    $issue = $response.fields.summary
    clear-host
    Write-Host "Issue Details:" -ForegroundColor Cyan -BackgroundColor Black
    Write-Host "    Issue: $issue" -ForegroundColor Yellow -BackgroundColor Black
    $priority = $response.fields.priority.name
    $priorityColor = switch ($priority) {
        "Lowest" { "LightBlue" }
        "Low" { "Cyan" }
        "Medium" { "Yellow" }
        "High" { "DarkYellow" }
        "Highest" { "Red" }
        "Critical" { "DarkRed" }
        default { "White" }
    }
    Write-Host "    Priority: $priority" -ForegroundColor $priorityColor -BackgroundColor Black
    "    Project Key: $($response.fields.project.key)"
    "    Description: $($response.fields.description)"
    "    Status: $($response.fields.status.name)"
    "    Assignee: $($response.fields.assignee.displayName)"
    "    Created: $($response.fields.created)"
    $link = $baseUrl + "/browse/$issueKey"
    "    🔗 Link: $link"
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
    Clear-Host
    Write-Host "Getting issues from epic $epicKey from Jira... @ $url"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}

    $issues = $response.issues

    PrintTable($issues)
}

function PrintTable($issues) {
    Clear-Host
    $table = @()
    foreach ($issue in $issues) {
        $priority = $issue.fields.priority.name
        # Assign colors based on priority
        $priorityColor = switch ($priority) {
            # Light Blue
            "Lowest"  { "38" }
            # Cyan
            "Low"      { "36" }
            # Green
            "Medium"    { "35" }  
            # Yellow
            "High"     { "33" }
            # Magenta
            "Highest" { "31" }
            # Bright Red
            "Critical" { "91" }
            # Default (No color)
            default     { "0" }   
        }
        $table += [PSCustomObject]@{
            Key       = $issue.key
            Issue     = $issue.fields.summary.Substring(0, [Math]::Min(75, $issue.fields.summary.Length))
            Priority  = $priority
            PriorityColor = $priorityColor
            Status    = $issue.fields.status.name
        }
    }
    
    $table | ForEach-Object {
        $priorityColor = $_.PriorityColor
        $priority = $_.Priority
        $coloredPriority = "`e[38;5;$priorityColor`m$priority`e[0m"
        
        [PSCustomObject]@{
            Key       = $_.Key
            Issue     = $_.Issue
            Color     = $priorityColor
            Priority  = $coloredPriority
            Status    = $_.Status
            Link      = $_.Link
        }
    } | Format-Table -Property Key, Issue, Color, Priority, Status, Link -AutoSize
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
    Clear-Host
    Write-Host "Getting issues from project $projectKey from Jira... @ $url"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}

    $issues = $response.issues

    # clear the terminal/console
    PrintTable($issues)
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
