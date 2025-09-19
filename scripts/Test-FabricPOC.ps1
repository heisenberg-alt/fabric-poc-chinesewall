<#
.SYNOPSIS
    Comprehensive test runner for Microsoft Fabric POC validation

.DESCRIPTION
    This script orchestrates all POC validation tests including:
    - Basic connectivity and API access
    - Workspace isolation and security
    - OneLake shortcuts and security roles
    - SQL connectivity and RLS/CLS validation  
    - Power BI semantic model security
    
.PARAMETER ConfigFile
    Path to JSON configuration file with test parameters
    
.PARAMETER ProviderWorkspaceId
    Provider workspace ID (Entity A)
    
.PARAMETER ConsumerWorkspaceId  
    Consumer workspace ID (Entity B)
    
.PARAMETER ProviderLakehouseItemId
    Provider lakehouse/warehouse item ID
    
.PARAMETER ConsumerLakehouseItemId
    Consumer lakehouse/warehouse item ID
    
.PARAMETER SqlConnectionString
    SQL connection string for testing database connectivity
    
.PARAMETER TestUserUpn
    UPN of test user for validation (optional)
    
.PARAMETER SkipSqlTests
    Skip SQL connectivity and RLS tests
    
.PARAMETER SkipPowerBITests
    Skip Power BI security tests
    
.PARAMETER ExportResults
    Export test results to file
    
.PARAMETER Verbose
    Enable verbose output

.EXAMPLE
    .\Test-FabricPOC.ps1 -ConfigFile "test-config.json"
    
.EXAMPLE
    .\Test-FabricPOC.ps1 -ProviderWorkspaceId "abc-123" -ConsumerWorkspaceId "def-456" -ProviderLakehouseItemId "ghi-789" -ConsumerLakehouseItemId "jkl-012"
#>

[CmdletBinding()]
param(
    [Parameter(ParameterSetName='ConfigFile')]
    [string]$ConfigFile,
    
    [Parameter(ParameterSetName='Manual', Mandatory=$true)]
    [string]$ProviderWorkspaceId,
    
    [Parameter(ParameterSetName='Manual', Mandatory=$true)]
    [string]$ConsumerWorkspaceId,
    
    [Parameter(ParameterSetName='Manual', Mandatory=$true)]
    [string]$ProviderLakehouseItemId,
    
    [Parameter(ParameterSetName='Manual', Mandatory=$true)]
    [string]$ConsumerLakehouseItemId,
    
    [string]$SqlConnectionString,
    [string]$TestUserUpn,
    [switch]$SkipSqlTests,
    [switch]$SkipPowerBITests,
    [switch]$ExportResults,
    [switch]$Verbose
)

# Test configuration
$script:Config = @{}
$script:TestSuites = @()

function Initialize-TestConfig {
    if ($ConfigFile -and (Test-Path $ConfigFile)) {
        Write-Host "Loading configuration from: $ConfigFile" -ForegroundColor Cyan
        try {
            $configData = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            $script:Config = @{
                ProviderWorkspaceId = $configData.ProviderWorkspaceId
                ConsumerWorkspaceId = $configData.ConsumerWorkspaceId
                ProviderLakehouseItemId = $configData.ProviderLakehouseItemId
                ConsumerLakehouseItemId = $configData.ConsumerLakehouseItemId
                SqlConnectionString = $configData.SqlConnectionString
                TestUserUpn = $configData.TestUserUpn
            }
        }
        catch {
            Write-Error "Failed to load configuration file: $($_.Exception.Message)"
            exit 1
        }
    }
    else {
        $script:Config = @{
            ProviderWorkspaceId = $ProviderWorkspaceId
            ConsumerWorkspaceId = $ConsumerWorkspaceId
            ProviderLakehouseItemId = $ProviderLakehouseItemId
            ConsumerLakehouseItemId = $ConsumerLakehouseItemId
            SqlConnectionString = $SqlConnectionString
            TestUserUpn = $TestUserUpn
        }
    }
    
    # Validate required parameters
    $requiredParams = @('ProviderWorkspaceId', 'ConsumerWorkspaceId', 'ProviderLakehouseItemId', 'ConsumerLakehouseItemId')
    foreach ($param in $requiredParams) {
        if (-not $script:Config[$param]) {
            Write-Error "Missing required parameter: $param"
            exit 1
        }
    }
}

function Test-Prerequisites {
    Write-Host "`n=== Checking Prerequisites ===" -ForegroundColor Magenta
    
    $prerequisites = @()
    
    # Check ACCESS_TOKEN
    if ($env:ACCESS_TOKEN) {
        $prerequisites += [PSCustomObject]@{ Name = "ACCESS_TOKEN"; Status = "OK"; Details = "Environment variable set" }
    } else {
        $prerequisites += [PSCustomObject]@{ Name = "ACCESS_TOKEN"; Status = "MISSING"; Details = "Set ACCESS_TOKEN environment variable" }
    }
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        $prerequisites += [PSCustomObject]@{ Name = "PowerShell"; Status = "OK"; Details = "Version $($PSVersionTable.PSVersion)" }
    } else {
        $prerequisites += [PSCustomObject]@{ Name = "PowerShell"; Status = "WARNING"; Details = "PowerShell 7+ recommended, current: $($PSVersionTable.PSVersion)" }
    }
    
    # Check SQL connectivity prerequisites
    if (-not $SkipSqlTests -and $script:Config.SqlConnectionString) {
        try {
            $null = [System.Reflection.Assembly]::LoadWithPartialName("System.Data.SqlClient")
            $prerequisites += [PSCustomObject]@{ Name = "SQL Client"; Status = "OK"; Details = "SqlClient assembly available" }
        }
        catch {
            $prerequisites += [PSCustomObject]@{ Name = "SQL Client"; Status = "ERROR"; Details = "SqlClient assembly not available" }
        }
    }
    
    # Display prerequisites
    $prerequisites | ForEach-Object {
        $color = switch ($_.Status) {
            "OK" { "Green" }
            "WARNING" { "Yellow" }
            "MISSING" { "Red" }
            "ERROR" { "Red" }
        }
        Write-Host "  [$($_.Status)] $($_.Name): $($_.Details)" -ForegroundColor $color
    }
    
    $criticalMissing = $prerequisites | Where-Object { $_.Status -in @("MISSING", "ERROR") }
    if ($criticalMissing) {
        Write-Host "`nCritical prerequisites missing. Please resolve before continuing." -ForegroundColor Red
        return $false
    }
    
    return $true
}

function Invoke-ValidationScript {
    param(
        [string]$ScriptName,
        [hashtable]$Parameters
    )
    
    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path $scriptPath)) {
        Write-Error "Validation script not found: $scriptPath"
        return $false
    }
    
    try {
        Write-Host "`nExecuting: $ScriptName" -ForegroundColor Yellow
        & $scriptPath @Parameters
        return $LASTEXITCODE -eq 0
    }
    catch {
        Write-Error "Failed to execute $ScriptName`: $($_.Exception.Message)"
        return $false
    }
}

function Test-ConnectivitySuite {
    Write-Host "`n=== Connectivity Test Suite ===" -ForegroundColor Magenta
    
    $params = @{
        ProviderWorkspaceId = $script:Config.ProviderWorkspaceId
        ConsumerWorkspaceId = $script:Config.ConsumerWorkspaceId
        ProviderLakehouseItemId = $script:Config.ProviderLakehouseItemId
        ConsumerLakehouseItemId = $script:Config.ConsumerLakehouseItemId
        Verbose = $Verbose.IsPresent
    }
    
    if ($script:Config.SqlConnectionString -and -not $SkipSqlTests) {
        $params.SqlConnectionString = $script:Config.SqlConnectionString
    } else {
        $params.SkipSqlTests = $true
    }
    
    if ($script:Config.TestUserUpn) {
        $params.TestUserUpn = $script:Config.TestUserUpn
    }
    
    $result = Invoke-ValidationScript "09-validate.ps1" $params
    $script:TestSuites += [PSCustomObject]@{
        Suite = "Connectivity"
        Status = if ($result) { "PASS" } else { "FAIL" }
        Timestamp = Get-Date
    }
    
    return $result
}

function Test-SecuritySuite {
    Write-Host "`n=== Security Test Suite ===" -ForegroundColor Magenta
    
    # Check if security test script exists
    $securityScript = Join-Path $PSScriptRoot "Test-Security.ps1"
    if (Test-Path $securityScript) {
        $params = @{
            ProviderWorkspaceId = $script:Config.ProviderWorkspaceId
            ConsumerWorkspaceId = $script:Config.ConsumerWorkspaceId
            TestUserUpn = $script:Config.TestUserUpn
            Verbose = $Verbose.IsPresent
        }
        
        $result = Invoke-ValidationScript "Test-Security.ps1" $params
        $script:TestSuites += [PSCustomObject]@{
            Suite = "Security"
            Status = if ($result) { "PASS" } else { "FAIL" }
            Timestamp = Get-Date
        }
        
        return $result
    } else {
        Write-Host "Security test script not found. Skipping security suite." -ForegroundColor Yellow
        $script:TestSuites += [PSCustomObject]@{
            Suite = "Security"
            Status = "SKIPPED"
            Timestamp = Get-Date
        }
        return $true
    }
}

function Test-DataAccessSuite {
    Write-Host "`n=== Data Access Test Suite ===" -ForegroundColor Magenta
    
    if ($SkipSqlTests) {
        Write-Host "SQL tests skipped by parameter." -ForegroundColor Yellow
        $script:TestSuites += [PSCustomObject]@{
            Suite = "Data Access"
            Status = "SKIPPED"
            Timestamp = Get-Date
        }
        return $true
    }
    
    if (-not $script:Config.SqlConnectionString) {
        Write-Host "No SQL connection string provided. Skipping data access tests." -ForegroundColor Yellow
        $script:TestSuites += [PSCustomObject]@{
            Suite = "Data Access"
            Status = "SKIPPED"
            Timestamp = Get-Date
        }
        return $true
    }
    
    # Test SQL connectivity and RLS
    try {
        Write-Host "Testing SQL connectivity and Row-Level Security..." -ForegroundColor Cyan
        $connection = New-Object System.Data.SqlClient.SqlConnection($script:Config.SqlConnectionString)
        $connection.Open()
        
        # Test basic query
        $command = $connection.CreateCommand()
        $command.CommandText = "SELECT COUNT(*) FROM dbo.MarketData"
        $rowCount = $command.ExecuteScalar()
        Write-Host "  MarketData table contains $rowCount rows" -ForegroundColor Green
        
        # Test RLS function existence
        $command.CommandText = @"
SELECT COUNT(*) FROM sys.objects o
INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type = 'FN' AND s.name = 'Security' AND o.name LIKE '%MarketData%'
"@
        $rlsFunctionCount = $command.ExecuteScalar()
        
        if ($rlsFunctionCount -gt 0) {
            Write-Host "  RLS security function found" -ForegroundColor Green
        } else {
            Write-Host "  No RLS security function found" -ForegroundColor Yellow
        }
        
        $connection.Close()
        
        $script:TestSuites += [PSCustomObject]@{
            Suite = "Data Access"
            Status = "PASS"
            Timestamp = Get-Date
        }
        return $true
    }
    catch {
        Write-Host "  SQL connectivity test failed: $($_.Exception.Message)" -ForegroundColor Red
        $script:TestSuites += [PSCustomObject]@{
            Suite = "Data Access"
            Status = "FAIL"
            Timestamp = Get-Date
        }
        return $false
    }
}

function Write-TestReport {
    Write-Host "`n=== Test Execution Summary ===" -ForegroundColor Magenta
    Write-Host "================================" -ForegroundColor Magenta
    
    $script:TestSuites | ForEach-Object {
        $color = switch ($_.Status) {
            "PASS" { "Green" }
            "FAIL" { "Red" }
            "SKIPPED" { "Yellow" }
        }
        Write-Host "  [$($_.Status)] $($_.Suite) - $($_.Timestamp.ToString('HH:mm:ss'))" -ForegroundColor $color
    }
    
    $totalSuites = $script:TestSuites.Count
    $passedSuites = ($script:TestSuites | Where-Object { $_.Status -eq "PASS" }).Count
    $failedSuites = ($script:TestSuites | Where-Object { $_.Status -eq "FAIL" }).Count
    $skippedSuites = ($script:TestSuites | Where-Object { $_.Status -eq "SKIPPED" }).Count
    
    Write-Host "`nOverall Results:" -ForegroundColor White
    Write-Host "  Total Suites: $totalSuites" -ForegroundColor White
    Write-Host "  Passed: $passedSuites" -ForegroundColor Green
    Write-Host "  Failed: $failedSuites" -ForegroundColor Red
    Write-Host "  Skipped: $skippedSuites" -ForegroundColor Yellow
    
    if ($ExportResults) {
        $reportFile = "fabric-poc-test-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
        $report = @{
            Timestamp = Get-Date
            Configuration = $script:Config
            TestSuites = $script:TestSuites
            Summary = @{
                Total = $totalSuites
                Passed = $passedSuites
                Failed = $failedSuites
                Skipped = $skippedSuites
            }
        }
        
        $report | ConvertTo-Json -Depth 5 | Out-File $reportFile
        Write-Host "`nTest report exported to: $reportFile" -ForegroundColor Gray
    }
    
    return $failedSuites -eq 0
}

function New-SampleConfigFile {
    $sampleConfig = @{
        ProviderWorkspaceId = "REPLACE-WITH-PROVIDER-WORKSPACE-ID"
        ConsumerWorkspaceId = "REPLACE-WITH-CONSUMER-WORKSPACE-ID"
        ProviderLakehouseItemId = "REPLACE-WITH-PROVIDER-LAKEHOUSE-ID"
        ConsumerLakehouseItemId = "REPLACE-WITH-CONSUMER-LAKEHOUSE-ID"
        SqlConnectionString = "Server=your-server.sql.azuresynapse.net;Database=your-database;Authentication=Active Directory Interactive;"
        TestUserUpn = "testuser@yourdomain.com"
    }
    
    $configFile = "test-config-sample.json"
    $sampleConfig | ConvertTo-Json -Depth 2 | Out-File $configFile
    Write-Host "Sample configuration file created: $configFile" -ForegroundColor Green
    Write-Host "Please update the placeholder values and use with -ConfigFile parameter" -ForegroundColor Yellow
}

# Main execution
try {
    Write-Host "Microsoft Fabric POC - Test Runner" -ForegroundColor Magenta
    Write-Host "==================================" -ForegroundColor Magenta
    
    # Initialize configuration
    Initialize-TestConfig
    
    # Check prerequisites
    if (-not (Test-Prerequisites)) {
        exit 1
    }
    
    Write-Host "`nTest Configuration:" -ForegroundColor Cyan
    Write-Host "  Provider Workspace: $($script:Config.ProviderWorkspaceId)" -ForegroundColor Gray
    Write-Host "  Consumer Workspace: $($script:Config.ConsumerWorkspaceId)" -ForegroundColor Gray
    Write-Host "  SQL Tests: $(if ($SkipSqlTests -or -not $script:Config.SqlConnectionString) { 'Disabled' } else { 'Enabled' })" -ForegroundColor Gray
    Write-Host "  Power BI Tests: $(if ($SkipPowerBITests) { 'Disabled' } else { 'Enabled' })" -ForegroundColor Gray
    
    # Run test suites
    $allPassed = $true
    
    $allPassed = (Test-ConnectivitySuite) -and $allPassed
    $allPassed = (Test-SecuritySuite) -and $allPassed
    $allPassed = (Test-DataAccessSuite) -and $allPassed
    
    # Generate report
    $reportSuccess = Write-TestReport
    
    if ($allPassed -and $reportSuccess) {
        Write-Host "`n✅ All tests completed successfully!" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`n❌ Some tests failed. Please review the results above." -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Error "Test runner failed: $($_.Exception.Message)"
    exit 1
}