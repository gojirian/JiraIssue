@{
    ModuleVersion = '1.0.0'
    Author        = 'Your Name'
    Description   = 'A PowerShell module to display a Jira issue'
    RootModule    = 'JiraIssue.psm1'
    FunctionsToExport = @(
    'Get-JiraIssue',
    'Get-Issue',
    'Get-EpicIssues',
    'Get-ProjectIssues',
    'Get-Projects',
    'Get-MyIssues',
    'Get-ServiceDesk',
    'Select-MyIssues',
    'Show-IssueReference'
    )
}
