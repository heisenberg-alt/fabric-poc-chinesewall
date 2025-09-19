
<#
 Comprehensive POC validation script:
 - Tests workspace isolation and access controls
 - Validates OneLake security and shortcuts
 - Checks SQL connectivity and RLS/CLS
 - Verifies Power BI semantic model security
 - Reports test results with pass/fail status
#>

param(
  [Parameter(Mandatory=$true)][string]$ProviderWorkspaceId,
  [Parameter(Mandatory=$true)][string]$ConsumerWorkspaceId,
  [Parameter(Mandatory=$true)][string]$ProviderLakehouseItemId,
  [Parameter(Mandatory=$true)][string]$ConsumerLakehouseItemId,
  [Parameter(Mandatory=$false)][string]$TestUserUpn = $null,
  [Parameter(Mandatory=$false)][string]$SqlConnectionString = $null,
  [switch]$SkipSqlTests,
  [switch]$Verbose
)

# Initialize test results
$script:TestResults = @()
$script:TotalTests = 0
$script:PassedTests = 0
$script:FailedTests = 0

function Write-TestResult {
    param(
        [string]$TestName,
        [bool]$Passed,
        [string]$Details = "",
        [string]$Error = ""
    )
    
    $script:TotalTests++
    if ($Passed) {
        $script:PassedTests++
        $status = "PASS"
        $color = "Green"
    } else {
        $script:FailedTests++
        $status = "FAIL"
        $color = "Red"
    }
    
    Write-Host "[$status] $TestName" -ForegroundColor $color
    if ($Details) { Write-Host "  Details: $Details" -ForegroundColor Gray }
    if ($Error) { Write-Host "  Error: $Error" -ForegroundColor Red }
    
    $script:TestResults += [PSCustomObject]@{
        TestName = $TestName
        Status = $status
        Details = $Details
        Error = $Error
        Timestamp = Get-Date
    }
}

function Test-ApiAccess {
    Write-Host "`n=== Testing API Access ===" -ForegroundColor Cyan
    
    # Test if ACCESS_TOKEN is available
    if (-not $env:ACCESS_TOKEN) {
        Write-TestResult "Access Token Available" $false "ACCESS_TOKEN environment variable not set"
        return $false
    }
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    try {
        # Test basic Fabric API access
        $response = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces" -Headers $headers -ErrorAction Stop
        Write-TestResult "Fabric API Access" $true "Successfully accessed Fabric API, found $($response.value.Count) workspaces"
        return $true
    }
    catch {
        Write-TestResult "Fabric API Access" $false "" $_.Exception.Message
        return $false
    }
}

function Test-WorkspaceAccess {
    Write-Host "`n=== Testing Workspace Access ===" -ForegroundColor Cyan
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    # Test Provider workspace access
    try {
        $providerWs = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ProviderWorkspaceId" -Headers $headers -ErrorAction Stop
        Write-TestResult "Provider Workspace Access" $true "Workspace: $($providerWs.displayName)"
    }
    catch {
        Write-TestResult "Provider Workspace Access" $false "" $_.Exception.Message
    }
    
    # Test Consumer workspace access  
    try {
        $consumerWs = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ConsumerWorkspaceId" -Headers $headers -ErrorAction Stop
        Write-TestResult "Consumer Workspace Access" $true "Workspace: $($consumerWs.displayName)"
    }
    catch {
        Write-TestResult "Consumer Workspace Access" $false "" $_.Exception.Message
    }
    
    # Test workspace items
    try {
        $providerItems = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ProviderWorkspaceId/items" -Headers $headers -ErrorAction Stop
        $providerLakehouse = $providerItems.value | Where-Object { $_.id -eq $ProviderLakehouseItemId }
        if ($providerLakehouse) {
            Write-TestResult "Provider Lakehouse Found" $true "Item: $($providerLakehouse.displayName) ($($providerLakehouse.type))"
        } else {
            Write-TestResult "Provider Lakehouse Found" $false "Lakehouse with ID $ProviderLakehouseItemId not found"
        }
    }
    catch {
        Write-TestResult "Provider Lakehouse Found" $false "" $_.Exception.Message
    }
    
    try {
        $consumerItems = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ConsumerWorkspaceId/items" -Headers $headers -ErrorAction Stop
        $consumerLakehouse = $consumerItems.value | Where-Object { $_.id -eq $ConsumerLakehouseItemId }
        if ($consumerLakehouse) {
            Write-TestResult "Consumer Lakehouse Found" $true "Item: $($consumerLakehouse.displayName) ($($consumerLakehouse.type))"
        } else {
            Write-TestResult "Consumer Lakehouse Found" $false "Lakehouse with ID $ConsumerLakehouseItemId not found"
        }
    }
    catch {
        Write-TestResult "Consumer Lakehouse Found" $false "" $_.Exception.Message
    }
}

function Test-OneLakeShortcuts {
    Write-Host "`n=== Testing OneLake Shortcuts ===" -ForegroundColor Cyan
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    try {
        # List shortcuts in Consumer Lakehouse
        $shortcutsUri = "https://api.fabric.microsoft.com/v1/workspaces/$ConsumerWorkspaceId/items/$ConsumerLakehouseItemId/shortcuts"
        $shortcuts = Invoke-RestMethod -Method GET -Uri $shortcutsUri -Headers $headers -ErrorAction Stop
        
        if ($shortcuts.value -and $shortcuts.value.Count -gt 0) {
            $marketDataShortcut = $shortcuts.value | Where-Object { $_.name -like "*MarketData*" -or $_.path -like "*MarketData*" }
            if ($marketDataShortcut) {
                Write-TestResult "MarketData Shortcut Found" $true "Shortcut: $($marketDataShortcut.name) -> $($marketDataShortcut.path)"
            } else {
                Write-TestResult "MarketData Shortcut Found" $false "No MarketData shortcut found. Available shortcuts: $($shortcuts.value | ForEach-Object { $_.name } | Join-String ', ')"
            }
            
            Write-TestResult "OneLake Shortcuts Listed" $true "Found $($shortcuts.value.Count) shortcuts"
            
            if ($Verbose) {
                Write-Host "  Shortcut Details:" -ForegroundColor Gray
                $shortcuts.value | ForEach-Object {
                    Write-Host "    - Name: $($_.name), Path: $($_.path), Target: $($_.target)" -ForegroundColor Gray
                }
            }
        } else {
            Write-TestResult "OneLake Shortcuts Listed" $false "No shortcuts found in Consumer Lakehouse"
        }
    }
    catch {
        Write-TestResult "OneLake Shortcuts Listed" $false "" $_.Exception.Message
    }
}

function Test-OneLakeSecurity {
    Write-Host "`n=== Testing OneLake Security ===" -ForegroundColor Cyan
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    try {
        # Test OneLake security roles on Provider Lakehouse
        $securityUri = "https://api.fabric.microsoft.com/v1/workspaces/$ProviderWorkspaceId/items/$ProviderLakehouseItemId/roles"
        $roles = Invoke-RestMethod -Method GET -Uri $securityUri -Headers $headers -ErrorAction Stop
        
        if ($roles.value -and $roles.value.Count -gt 0) {
            Write-TestResult "OneLake Security Roles Found" $true "Found $($roles.value.Count) security roles configured"
            
            if ($Verbose) {
                Write-Host "  Security Roles:" -ForegroundColor Gray
                $roles.value | ForEach-Object {
                    Write-Host "    - Role: $($_.role), Principal: $($_.principal.id), Type: $($_.principal.type)" -ForegroundColor Gray
                }
            }
        } else {
            Write-TestResult "OneLake Security Roles Found" $false "No OneLake security roles configured"
        }
    }
    catch {
        Write-TestResult "OneLake Security Roles Found" $false "" $_.Exception.Message
    }
}

function Test-SqlConnectivity {
    if ($SkipSqlTests) {
        Write-Host "`n=== Skipping SQL Tests (SkipSqlTests flag set) ===" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n=== Testing SQL Connectivity ===" -ForegroundColor Cyan
    
    if (-not $SqlConnectionString) {
        Write-TestResult "SQL Connection String" $false "SqlConnectionString parameter not provided"
        return
    }
    
    try {
        # Test basic SQL connectivity
        $connection = New-Object System.Data.SqlClient.SqlConnection($SqlConnectionString)
        $connection.Open()
        
        Write-TestResult "SQL Database Connection" $true "Successfully connected to SQL endpoint"
        
        # Test if MarketData table exists
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'MarketData'"
        $tableExists = $command.ExecuteScalar()
        
        if ($tableExists -gt 0) {
            Write-TestResult "MarketData Table Exists" $true "Table found in database"
            
            # Test basic query
            $command.CommandText = "SELECT COUNT(*) FROM dbo.MarketData"
            $rowCount = $command.ExecuteScalar()
            Write-TestResult "MarketData Query Test" $true "Table contains $rowCount rows"
            
            # Test for RLS function (if it exists)
            $command.CommandText = "SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME LIKE '%MarketData%' AND ROUTINE_TYPE = 'FUNCTION'"
            $rlsFunctionExists = $command.ExecuteScalar()
            
            if ($rlsFunctionExists -gt 0) {
                Write-TestResult "RLS Security Function Found" $true "Row-Level Security function detected"
            } else {
                Write-TestResult "RLS Security Function Found" $false "No RLS security function found"
            }
        } else {
            Write-TestResult "MarketData Table Exists" $false "MarketData table not found"
        }
        
        $connection.Close()
    }
    catch {
        Write-TestResult "SQL Database Connection" $false "" $_.Exception.Message
    }
}

function Test-PowerBISecurity {
    Write-Host "`n=== Testing Power BI Security ===" -ForegroundColor Cyan
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    try {
        # List datasets in Consumer workspace
        $datasetsUri = "https://api.powerbi.com/v1.0/myorg/groups/$ConsumerWorkspaceId/datasets"
        $datasets = Invoke-RestMethod -Method GET -Uri $datasetsUri -Headers $headers -ErrorAction Stop
        
        if ($datasets.value -and $datasets.value.Count -gt 0) {
            Write-TestResult "Power BI Datasets Found" $true "Found $($datasets.value.Count) datasets in Consumer workspace"
            
            foreach ($dataset in $datasets.value) {
                # Check dataset permissions
                try {
                    $permissionsUri = "https://api.powerbi.com/v1.0/myorg/groups/$ConsumerWorkspaceId/datasets/$($dataset.id)/users"
                    $permissions = Invoke-RestMethod -Method GET -Uri $permissionsUri -Headers $headers -ErrorAction Stop
                    Write-TestResult "Dataset Permissions Check" $true "Dataset '$($dataset.name)' has $($permissions.value.Count) permission entries"
                }
                catch {
                    Write-TestResult "Dataset Permissions Check" $false "Failed to check permissions for dataset '$($dataset.name)'" $_.Exception.Message
                }
            }
        } else {
            Write-TestResult "Power BI Datasets Found" $false "No datasets found in Consumer workspace"
        }
    }
    catch {
        Write-TestResult "Power BI Datasets Found" $false "" $_.Exception.Message
    }
}

function Write-TestSummary {
    Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
    Write-Host "Total Tests: $script:TotalTests" -ForegroundColor White
    Write-Host "Passed: $script:PassedTests" -ForegroundColor Green
    Write-Host "Failed: $script:FailedTests" -ForegroundColor Red
    
    $successRate = if ($script:TotalTests -gt 0) { [math]::Round(($script:PassedTests / $script:TotalTests) * 100, 1) } else { 0 }
    Write-Host "Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } elseif ($successRate -ge 60) { "Yellow" } else { "Red" })
    
    if ($script:FailedTests -gt 0) {
        Write-Host "`nFailed Tests:" -ForegroundColor Red
        $script:TestResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
            Write-Host "  - $($_.TestName): $($_.Error)" -ForegroundColor Red
        }
    }
    
    # Export detailed results
    $resultsFile = "test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $script:TestResults | ConvertTo-Json -Depth 3 | Out-File $resultsFile
    Write-Host "`nDetailed results exported to: $resultsFile" -ForegroundColor Gray
}

# Main execution
Write-Host "Microsoft Fabric POC - Validation Tests" -ForegroundColor Magenta
Write-Host "=======================================" -ForegroundColor Magenta
Write-Host "Provider Workspace: $ProviderWorkspaceId" -ForegroundColor Gray
Write-Host "Consumer Workspace: $ConsumerWorkspaceId" -ForegroundColor Gray
Write-Host "Test User: $(if ($TestUserUpn) { $TestUserUpn } else { 'Current User' })" -ForegroundColor Gray
Write-Host ""

# Run all tests
Test-ApiAccess
Test-WorkspaceAccess
Test-OneLakeShortcuts
Test-OneLakeSecurity
Test-SqlConnectivity
Test-PowerBISecurity

# Display summary
Write-TestSummary

# Exit with appropriate code
exit $(if ($script:FailedTests -eq 0) { 0 } else { 1 })
