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

    # dump it all so i can see linked issues
    # $response.fields | Format-List

    # issues linked to this issue
    $linkedIssues = $response.fields.issuelinks
    if ($linkedIssues) {
        Write-Host "Linked Issues:" -ForegroundColor Cyan -BackgroundColor Black
        foreach ($linkedIssue in $linkedIssues) {
            $outwardIssue = $linkedIssue.outwardIssue
            $inwardIssue = $linkedIssue.inwardIssue
            if ($outwardIssue) {
                Write-Host "    Outward Issue: $($outwardIssue.key) - $($outwardIssue.fields.summary)" -ForegroundColor Yellow -BackgroundColor Black
            }
            if ($inwardIssue) {
                Write-Host "    Inward Issue: $($inwardIssue.key) - $($inwardIssue.fields.summary)" -ForegroundColor Yellow -BackgroundColor Black
            }
        }
    }
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
        $linkedIssues = $issue.fields.issuelinks
        $projectKey = $issue.fields.project.key.ToUpper()
        $issueLink = "$baseUrl/jira/software/c/projects/$projectKey/list?direction=DESC&selectedIssue=$($issue.key)&sortBy=priority"
        $issueLink += "&filter=status%20IN%20(%22In%20Progress%22%2C%20%22To%20Do%22%2C%20%22UAT%22)"
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
            Key       = "`e]8;;$($issueLink)`e\$($issue.key)`e]8;;`e\" # Hyperlink formatting
            Issue     = $issue.fields.summary.Substring(0, [Math]::Min(85, $issue.fields.summary.Length))
            Priority  = $priority
            PriorityColor = $priorityColor
            Status    = $issue.fields.status.name
            LinkedIssues = $linkedIssues
        }
    }
    
    $table | ForEach-Object {
        $priorityColor = $_.PriorityColor
        $priority = $_.Priority
        $coloredPriority = "`e[38;5;$priorityColor`m$priority`e[0m"
        $linkedIssueKeys = if ($_.LinkedIssues) {
            ($_.LinkedIssues | ForEach-Object {
                if ($_.inwardIssue) {
                    $link = $baseUrl + "/browse/$_.inwardIssue.key"
                    # "[`e[38;5;32m$($_.inwardIssue.key)`e[0m]($link)"
                    # Hyperlink formatting
                    "`e[38;5;35m`e]8;;$link`e\$($_.inwardIssue.key)`e]8;;`e\"

                } elseif ($_.outwardIssue) {
                    $link = $baseUrl + "/browse/$_.outwardIssue.key"
                    "`e[38;5;33m`e]8;;$link`e\$($_.outwardIssue.key)`e]8;;`e\"
                }
            } | Where-Object { $_ }) -join ", "
        } else {
            ""
        }
    
        [PSCustomObject]@{
            Key       = $_.Key
            Issue     = $_.Issue
            Color     = $_.Color
            Priority  = $_.Priority
            Status    = $_.Status
            LinkedIssues = $linkedIssueKeys
        }
    } | Format-Table -Property Key, Issue, Color, Priority, Status, LinkedIssues -AutoSize
}

function GetLinkedIssueDetails($issueKey) {
    $url = "$baseUrl/rest/api/3/issue/$issueKey"
    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}
    return @{
        TimeSpent = if ($response.fields.timespent) { [math]::Round($response.fields.timespent / 3600, 1) } else { 0 }
        TimeEstimate = if ($response.fields.timetracking.originalEstimateSeconds) { 
            [math]::Round($response.fields.timetracking.originalEstimateSeconds / 3600, 1) 
        } else { 0 }
    }
}

function PrintTableWithHours($issues) {
    Clear-Host
    $table = @()
    foreach ($issue in $issues) {
        $priority = $issue.fields.priority.name
        # Assign colors based on priority
        $linkedIssues = $issue.fields.issuelinks
        $projectKey = $issue.fields.project.key.ToUpper()
        $issueLink = "$baseUrl/jira/software/c/projects/$projectKey/list?direction=DESC&selectedIssue=$($issue.key)&sortBy=priority"
        $issueLink += "&filter=status%20IN%20(%22In%20Progress%22%2C%20%22To%20Do%22%2C%20%22UAT%22)"
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
            Key       = "`e]8;;$($issueLink)`e\$($issue.key)`e]8;;`e\" # Hyperlink formatting
            Issue     = $issue.fields.summary.Substring(0, [Math]::Min(85, $issue.fields.summary.Length))
            Priority  = $priority
            PriorityColor = $priorityColor
            Status    = $issue.fields.status.name
            LinkedIssues = $linkedIssues
        }
    }
    
    $table | ForEach-Object {
        $priorityColor = $_.PriorityColor
        $priority = $_.Priority
        $coloredPriority = "`e[38;5;$priorityColor`m$priority`e[0m"
        $linkedIssueKeys = if ($_.LinkedIssues) {
            ($_.LinkedIssues | ForEach-Object {
                if ($_.inwardIssue) {
                    $link = $baseUrl + "/browse/$_.inwardIssue.key"
                    # "[`e[38;5;32m$($_.inwardIssue.key)`e[0m]($link)"
                    # Hyperlink formatting
                    # $timeSpent = if ($_.inwardIssue.fields.timespent) { [math]::Round($_.inwardIssue.fields.time_spent / 3600, 1) } else { 0 }
                    $timeDetails = GetLinkedIssueDetails($_.inwardIssue.key)
                    "`e[38;5;35m`e]8;;$link`e\$($_.inwardIssue.key) [$($timeDetails.TimeSpent)h/$($timeDetails.TimeEstimate)h]`e]8;;`e\"

                } elseif ($_.outwardIssue) {
                    $link = $baseUrl + "/browse/$_.outwardIssue.key"
                    $timeDetails = GetLinkedIssueDetails($_.outwardIssue.key)
                    "`e[38;5;33m`e]8;;$link`e\$($_.outwardIssue.key) [$($timeDetails.TimeSpent)h/$($timeDetails.TimeEstimate)h]`e]8;;`e\"
                }
            } | Where-Object { $_ }) -join ", "
        } else {
            ""
        }
    
        [PSCustomObject]@{
            Key       = $_.Key
            Issue     = $_.Issue
            Color     = $_.Color
            Priority  = $_.Priority
            Status    = $_.Status
            LinkedIssues = $linkedIssueKeys
        }
    } | Format-Table -Property Key, Issue, Color, Priority, Status, LinkedIssues -AutoSize
}

function Get-ProjectIssues {
    param (
        [string]$projectKey,
        # optional search parameter
        [string]$search = "",
        [switch]$MeMode,
        [string]$date = "",
        [switch]$monthAll = $false
    )

    if ($search -ne "") {
        $search = " AND text ~ '$search'"
    } else {
        $search = ""
    }

    # make $projectKey uppercase
    $projectKey = $projectKey.ToUpper()

    if ($MeMode) {
        $search += " AND assignee = currentUser()"
    }

    if ($monthAll) {
        $dateFilter = " AND updated >= startOfMonth(-1) and status not in (Cancelled) "
    } elseif ($date) {
        $dateFilter = " AND updated >= '$date' and status not in (Done, Cancelled) "
    } else {
        $dateFilter = " and status not in (Done, Cancelled) "
    }

    $url = "$baseUrl/rest/api/3/search?jql=project=$projectKey $dateFilter $search ORDER BY priority DESC, status DESC &maxResults=100"
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

function Get-MyIssues {
    param (
        # optional search parameter
        [string]$search = ""
    )

    if ($search -ne "") {
        $search = " AND text ~ '$search'"
    } else {
        $search = ""
    }

    $url = "$baseUrl/rest/api/3/search?jql=assignee = currentUser() AND status not in (Done, Cancelled) $search ORDER BY priority DESC, status DESC &maxResults=100"
    Clear-Host
    Write-Host "Getting my assigned issues from Jira... @ $url"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}
    $issues = $response.issues
    PrintTable($issues)
}

function Get-ServiceDesk {
    param (
        # optional search parameter
        [string]$search = "",
        # optional switch to show only my requests
        [switch]$MyRequests = $false,
        # optional switch to show only active requests
        [string]$ProjectType = "service_desk"
    )

    if ($search -ne "") {
        $search = " AND text ~ '$search'"
    }

    if ($MyRequests) {
        $search += " AND assignee = currentUser()"
    }

    $jql = "projectType = $ProjectType $search"
    $url = "$baseUrl/rest/api/3/search?jql=$jql&maxResults=100&fields=summary,priority,status,issuelinks,project,timetracking,timespent"
    
    Write-Host "Getting Service Desk requests from Jira..."
    Write-Host "URL: $url" -ForegroundColor DarkGray

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}

    # i just want to see all the json return from this request 
    # $response | ConvertTo-Json -Depth 10 | Out-Host

    # dump the json 
    $response | Format-List

    $issues = $response.issues
    PrintTableWithHours($issues)
}


