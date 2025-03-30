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
        $linkedIssues = $issue.fields.issuelinks
        $projectKey = $issue.fields.project.key.ToUpper()
        $issueLink = "$baseUrl/jira/software/c/projects/$projectKey/list?direction=DESC&selectedIssue=$($issue.key)&sortBy=priority"
        $issueLink += "&filter=status%20IN%20(%22In%20Progress%22%2C%20%22To%20Do%22%2C%20%22UAT%22)"
        $priorityColor = switch ($priority) {
            "Lowest"  { "38" }
            "Low"      { "36" }
            "Medium"    { "35" }  
            "High"     { "33" }
            "Highest" { "31" }
            "Critical" { "91" }
            default     { "0" }   
        }
        $table += [PSCustomObject]@{
            Key       = "`e]8;;$($issueLink)`e\$($issue.key)`e]8;;`e\" 
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
        $linkedIssues = $issue.fields.issuelinks
        $projectKey = $issue.fields.project.key.ToUpper()
        $issueLink = "$baseUrl/jira/software/c/projects/$projectKey/list?direction=DESC&selectedIssue=$($issue.key)&sortBy=priority"
        $issueLink += "&filter=status%20IN%20(%22In%20Progress%22%2C%20%22To%20Do%22%2C%20%22UAT%22)"
        $priorityColor = switch ($priority) {
            "Lowest"  { "38" }
            "Low"      { "36" }
            "Medium"    { "35" }  
            "High"     { "33" }
            "Highest" { "31" }
            "Critical" { "91" }
            default     { "0" }   
        }
        $table += [PSCustomObject]@{
            Key       = "`e]8;;$($issueLink)`e\$($issue.key)`e]8;;`e\" 
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

    PrintTable($issues)
}

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
        [string]$search = ""
    )

    if ($search -ne "") {
        $search = " AND text ~ '$search'"
    } else {
        $search = ""
    }

    $url = "$baseUrl/rest/api/3/search?jql=assignee = currentUser() AND projectType != business AND status not in (Done, Cancelled) $search ORDER BY priority DESC, status DESC &maxResults=100"
    Clear-Host
    Write-Host "Getting my assigned issues from Jira... @ $url"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}
    $issues = $response.issues
    PrintTable($issues)
}

function Select-MyIssues {
    param (
        [string]$search = "",
        [string]$OutputFile = ""
    )

    if ($search -ne "") {
        $search = " AND text ~ '$search'"
    } else {
        $search = ""
    }

    $url = "$baseUrl/rest/api/3/search?jql=assignee = currentUser() AND projectType != business AND status not in (Done, Cancelled) $search ORDER BY priority DESC, status DESC &maxResults=100"

    Clear-Host
    Write-Host "Getting my assigned issues from Jira... @ $url"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}
    $issues = $response.issues

    $issuesForSelection = $issues | ForEach-Object {
        [PSCustomObject]@{
            Key = $_.key
            Summary = $_.fields.summary
            Priority = $_.fields.priority.name
            Status = $_.fields.status.name
            Link = "$baseUrl/browse/$($_.key)"
        }
    }

    Write-Host "Please select one or more issues (use Ctrl or Shift for multiple selection)..."
    $selectedIssues = $issuesForSelection | Out-GridView -Title "Select Jira Issues (use Ctrl or Shift for multiple selection)" -OutputMode Multiple

    Out-String -InputObject $selectedIssues

    if (-not $selectedIssues -or $selectedIssues.Count -eq 0) {
        Write-Host "No issues selected." -ForegroundColor Yellow
        return
    }

    $workingLocation = Read-Host "Where are you working today? (*Home*/Office)"

    if ([string]::IsNullOrWhiteSpace($workingLocation)) {
        $workingLocation = "Home"
    }

    $selectedIssuesWithTime = @()
    foreach ($issue in $selectedIssues) {
        $timeEstimate = Read-Host "Enter time estimate (in hours) for $($issue.Key) [$($issue.Summary)]"
        
        if (-not [string]::IsNullOrWhiteSpace($timeEstimate)) {
            try {
                $timeEstimate = [float]$timeEstimate
            }
            catch {
                Write-Host "Invalid time estimate. Using default." -ForegroundColor Yellow
                $timeEstimate = 1
            }
        }
        else {
            $timeEstimate = 1
        }
        
        Write-Host "Enter tasks for $($issue.Key) (one per line, press Enter twice when done):" -ForegroundColor Cyan
        $tasks = @()
        $line = ""
        do {
            $line = Read-Host
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $tasks += $line
            }
        } while (-not [string]::IsNullOrWhiteSpace($line))
        
        $issue | Add-Member -NotePropertyName TimeEstimate -NotePropertyValue $timeEstimate
        $issue | Add-Member -NotePropertyName Tasks -NotePropertyValue $tasks
        $selectedIssuesWithTime += $issue
    }
    
    $issueMarkdown = ($selectedIssuesWithTime | ForEach-Object {
        $markdown = ""
        if ($_.TimeEstimate -gt 0) {
            $markdown = "* [$($_.Key)]($($_.Link)) $($_.Summary) - Estimate: $($_.TimeEstimate)h"
        }
        else {
            $markdown = "* [$($_.Key)]($($_.Link)) $($_.Summary)"
        }
        
        if ($_.Tasks -and $_.Tasks.Count -gt 0) {
            $taskList = ($_.Tasks | ForEach-Object { "  * $_" }) -join "`r`n"
            $markdown = "$markdown`r`n$taskList"
        }
        
        return $markdown
    }) -join "`r`n"
    
    $notes = @"
# Selected Jira Issues Notes
Date: $(Get-Date -Format "dddd dd'th' MMMM") - $workingLocation

## Selected Issues

$issueMarkdown

## Notes

----------------------



----------------------

"@

    $tempFile = [System.IO.Path]::GetTempFileName() + ".md"
    $notes | Out-File -FilePath $tempFile -Encoding UTF8

    Write-Host "Opening editor for notes. Please add your notes and save/close the file when done."
    try {
        Start-Process -FilePath "code" -ArgumentList $tempFile -Wait
    }
    catch {
        Write-Host "Could not open Visual Studio Code. Falling back to Notepad." -ForegroundColor Yellow
        Start-Process -FilePath "notepad.exe" -ArgumentList $tempFile -Wait
    }

    $editedNotes = Get-Content -Path $tempFile -Raw
    
    if ($OutputFile -ne "") {
        $editedNotes | Out-File -FilePath $OutputFile -Encoding UTF8
        Write-Host "Notes saved to: $OutputFile" -ForegroundColor Green
    } else {
        Write-Host "`n------------------ NOTES ------------------`n" -ForegroundColor Cyan
        Write-Host $editedNotes
        Write-Host "`n------------------------------------------`n" -ForegroundColor Cyan
        
        $saveToFile = Read-Host "Would you like to save these notes to a file? (y/n)"
        if ($saveToFile -eq "y") {
            $defaultPath = Join-Path -Path ([Environment]::GetFolderPath("MyDocuments")) -ChildPath "JiraNotes_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
            $outputPath = Read-Host "Enter file path or press Enter for default [$defaultPath]"
            if ([string]::IsNullOrWhiteSpace($outputPath)) {
                $outputPath = $defaultPath
            }
            $editedNotes | Out-File -FilePath $outputPath -Encoding UTF8
            Write-Host "Notes saved to: $outputPath" -ForegroundColor Green
        }
    }

    Remove-Item -Path $tempFile -Force

    return @{
        Issues = $selectedIssuesWithTime
        Notes = $editedNotes
    }
}

function Get-ServiceDesk {
    param (
        [string]$search = "",
        [switch]$MyRequests = $false,
        [string]$ProjectType = "service_desk"
    )

    if ($search -ne "") {
        $search = " AND text ~ '$search'"
    }

    $search += " AND status not in (Cancelled)"

    if ($MyRequests) {
        $search += " AND assignee = currentUser()"
    }

    $jql = "projectType = $ProjectType $search"
    $currentMonth = (Get-Date).ToString("yyyy-MM")
    $jql += " AND created >= $currentMonth-01 AND created <= $currentMonth-31"
    $url = "$baseUrl/rest/api/3/search?jql=$jql&maxResults=100&fields=summary,priority,status,issuelinks,project,timetracking,timespent"
    
    Write-Host "Getting Service Desk requests from Jira..."
    Write-Host "URL: $url" -ForegroundColor DarkGray

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}

    $issues = $response.issues
    PrintTableWithHours($issues)
}

function Get-Issue {
    param (
        [Parameter(Mandatory = $true)]
        [string]$issueKey
    )
    
    $url = "$baseUrl/rest/api/3/issue/$issueKey"
    Write-Host "Getting issue $issueKey from Jira..."

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}

    $issueData = @(
        [PSCustomObject]@{
            Field = "Summary"
            Value = $response.fields.summary
            Category = "Basic Info"
            Icon = "📝"
        }
        [PSCustomObject]@{
            Field = "Status"
            Value = $response.fields.status.name
            Category = "Basic Info"
            Icon = "🔄"
        }
        [PSCustomObject]@{
            Field = "Priority"
            Value = $response.fields.priority.name
            Category = "Basic Info"
            Icon = "⚡"
        }
        [PSCustomObject]@{
            Field = "Assignee"
            Value = $response.fields.assignee.displayName
            Category = "People"
            Icon = "👤"
        }
        [PSCustomObject]@{
            Field = "Reporter"
            Value = $response.fields.reporter.displayName
            Category = "People"
            Icon = "📢"
        }
        [PSCustomObject]@{
            Field = "Created"
            Value = [DateTime]::ParseExact($response.fields.created.Split("T")[0], "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture).ToString("g")
            Category = "Dates"
            Icon = "📅"
        }
        [PSCustomObject]@{
            Field = "Updated"
            Value = [DateTime]::ParseExact($response.fields.updated.Split("T")[0], "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture).ToString("g")
            Category = "Dates"
            Icon = "🔄"
        }
        [PSCustomObject]@{
            Field = "Description"
            Value = if ($response.fields.description) { $response.fields.description.ToString() } else { "" }
            Category = "Content"
            Icon = "📋"
        }
    )

    if ($response.fields.issuelinks) {
        foreach ($link in $response.fields.issuelinks) {
            $linkedIssue = if ($link.outwardIssue) { $link.outwardIssue } else { $link.inwardIssue }
            $direction = if ($link.outwardIssue) { "Outward" } else { "Inward" }
            $issueData += [PSCustomObject]@{
                Field = "Linked Issue ($direction)"
                Value = "$($linkedIssue.key): $($linkedIssue.fields.summary)"
                Category = "Links"
                Icon = "🔗"
            }
        }
    }

    $issueData | Sort-Object Category, Field | 
        Out-GridView -Title "Issue Details: $issueKey" -PassThru

    $openInBrowser = Read-Host "Open in browser? (y/n)"
    if ($openInBrowser -eq 'y') {
        Start-Process "$baseUrl/browse/$issueKey"
    }
}

function Show-IssueReference {
    param (
        [Parameter(Mandatory = $false)]
        [string]$ProjectKey,
        [string]$Search = "",
        [switch]$MyIssues,
        [switch]$ServiceDesk
    )

    if ($Search -ne "") {
        $Search = " AND text ~ '$Search'"
    }

    $jql = if ($ServiceDesk) {
        "projectType = service_desk AND status not in (Cancelled, Done)"
    } elseif ($ProjectKey) {
        "project = $ProjectKey AND status not in (Done, Cancelled)"
    } elseif ($MyIssues) {
        "assignee = currentUser() AND projectType != business AND status not in (Done, Cancelled)"
    } else {
        "assignee = currentUser() AND projectType != business AND status not in (Done, Cancelled)"
    }

    $jql += "$Search ORDER BY priority DESC, status DESC"
    $url = "$baseUrl/rest/api/3/search?jql=$jql&maxResults=100"

    $response = Invoke-RestMethod -Uri $url -Method Get -Headers @{Authorization = $authHeader}
    
    Clear-Host
    Write-Host "Daily Reference Table - $(Get-Date -Format 'dddd, MMMM dd')" -ForegroundColor Cyan
    Write-Host "----------------------------------------`n" -ForegroundColor DarkGray

    $response.issues | ForEach-Object {
        $priority = $_.fields.priority.name
        $priorityColor = switch ($priority) {
            "Lowest" { "Blue" }
            "Low" { "Cyan" }
            "Medium" { "Green" }
            "High" { "Yellow" }
            "Highest" { "Red" }
            "Critical" { "DarkRed" }
            default { "White" }
        }
        
        $browserLink = "$baseUrl/browse/$($_.key)"
        Write-Host "`e]8;;$browserLink`e\$($_.key)`e]8;;`e\" -NoNewline
        Write-Host " | " -NoNewline -ForegroundColor DarkGray
        Write-Host $priority.PadRight(8) -NoNewline -ForegroundColor $priorityColor
        Write-Host " | " -NoNewline -ForegroundColor DarkGray
        Write-Host "$($_.fields.status.name.PadRight(15)) | " -NoNewline
        Write-Host $_.fields.summary
    }

    Write-Host "`n----------------------------------------" -ForegroundColor DarkGray
    Write-Host "Click any issue key to open in browser" -ForegroundColor DarkGray
}