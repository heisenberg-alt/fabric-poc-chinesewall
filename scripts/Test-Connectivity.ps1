<#
.SYNOPSIS
    Basic connectivity and API access validation for Microsoft Fabric POC

.DESCRIPTION
    This script validates basic connectivity requirements:
    - Fabric API access and authentication
    - Workspace accessibility
    - Item enumeration and basic metadata
    - Network connectivity to required endpoints

.PARAMETER ProviderWorkspaceId
    Provider workspace ID (Entity A)
    
.PARAMETER ConsumerWorkspaceId
    Consumer workspace ID (Entity B)
    
.PARAMETER TestEndpoints
    Test connectivity to various Fabric endpoints
    
.PARAMETER Verbose
    Enable verbose output

.EXAMPLE
    .\Test-Connectivity.ps1 -ProviderWorkspaceId "abc-123" -ConsumerWorkspaceId "def-456"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProviderWorkspaceId,
    
    [Parameter(Mandatory=$true)]
    [string]$ConsumerWorkspaceId,
    
    [switch]$TestEndpoints,
    [switch]$Verbose
)

$script:TestResults = @()

function Write-ConnectivityResult {
    param(
        [string]$TestName,
        [bool]$Success,
        [string]$Details = "",
        [string]$Error = ""
    )
    
    $status = if ($Success) { "PASS" } else { "FAIL" }
    $color = if ($Success) { "Green" } else { "Red" }
    
    Write-Host "[$status] $TestName" -ForegroundColor $color
    if ($Details) { Write-Host "  $Details" -ForegroundColor Gray }
    if ($Error) { Write-Host "  Error: $Error" -ForegroundColor Red }
    
    $script:TestResults += [PSCustomObject]@{
        Test = $TestName
        Status = $status
        Details = $Details
        Error = $Error
        Timestamp = Get-Date
    }
}

function Test-Environment {
    Write-Host "=== Environment Check ===" -ForegroundColor Cyan
    
    # Test ACCESS_TOKEN
    if ($env:ACCESS_TOKEN) {
        $tokenLength = $env:ACCESS_TOKEN.Length
        Write-ConnectivityResult "ACCESS_TOKEN Available" $true "Token length: $tokenLength characters"
        
        # Basic token validation (JWT format check)
        try {
            $tokenParts = $env:ACCESS_TOKEN.Split('.')
            if ($tokenParts.Count -eq 3) {
                Write-ConnectivityResult "ACCESS_TOKEN Format" $true "Valid JWT format detected"
            } else {
                Write-ConnectivityResult "ACCESS_TOKEN Format" $false "Token does not appear to be a valid JWT"
            }
        }
        catch {
            Write-ConnectivityResult "ACCESS_TOKEN Format" $false "" $_.Exception.Message
        }
    } else {
        Write-ConnectivityResult "ACCESS_TOKEN Available" $false "Environment variable not set"
    }
    
    # Test PowerShell version
    $psVersion = $PSVersionTable.PSVersion
    $isPS7Plus = $psVersion.Major -ge 7
    Write-ConnectivityResult "PowerShell Version" $isPS7Plus "Version: $psVersion $(if (-not $isPS7Plus) { '(Recommend PS 7+)' })"
    
    # Test required modules
    $requiredModules = @('Microsoft.PowerShell.Utility')
    foreach ($module in $requiredModules) {
        try {
            Import-Module $module -ErrorAction Stop
            Write-ConnectivityResult "Module: $module" $true "Successfully imported"
        }
        catch {
            Write-ConnectivityResult "Module: $module" $false "" $_.Exception.Message
        }
    }
}

function Test-NetworkConnectivity {
    if (-not $TestEndpoints) {
        Write-Host "`n=== Network Connectivity (Skipped) ===" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n=== Network Connectivity ===" -ForegroundColor Cyan
    
    $endpoints = @(
        @{ Name = "Fabric API"; Url = "https://api.fabric.microsoft.com" },
        @{ Name = "Power BI API"; Url = "https://api.powerbi.com" },
        @{ Name = "Azure AD"; Url = "https://login.microsoftonline.com" },
        @{ Name = "Microsoft Graph"; Url = "https://graph.microsoft.com" }
    )
    
    foreach ($endpoint in $endpoints) {
        try {
            $response = Invoke-WebRequest -Uri $endpoint.Url -Method HEAD -TimeoutSec 10 -ErrorAction Stop
            Write-ConnectivityResult "Endpoint: $($endpoint.Name)" $true "HTTP $($response.StatusCode) - $($endpoint.Url)"
        }
        catch {
            $errorMsg = if ($_.Exception.Response) {
                "HTTP $($_.Exception.Response.StatusCode)"
            } else {
                $_.Exception.Message
            }
            Write-ConnectivityResult "Endpoint: $($endpoint.Name)" $false $endpoint.Url $errorMsg
        }
    }
}

function Test-FabricApiAccess {
    Write-Host "`n=== Fabric API Access ===" -ForegroundColor Cyan
    
    if (-not $env:ACCESS_TOKEN) {
        Write-ConnectivityResult "Fabric API Authentication" $false "ACCESS_TOKEN not available"
        return
    }
    
    $headers = @{ 
        Authorization = "Bearer $env:ACCESS_TOKEN"
        'Content-Type' = 'application/json'
    }
    
    try {
        # Test basic API access
        $workspaces = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces" -Headers $headers -ErrorAction Stop
        Write-ConnectivityResult "Fabric API Access" $true "Successfully retrieved $($workspaces.value.Count) workspaces"
        
        # Test capacities endpoint
        try {
            $capacities = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/capacities" -Headers $headers -ErrorAction Stop
            Write-ConnectivityResult "Capacities API" $true "Found $($capacities.value.Count) capacities"
        }
        catch {
            Write-ConnectivityResult "Capacities API" $false "" $_.Exception.Message
        }
        
    }
    catch {
        $errorDetails = if ($_.Exception.Response) {
            "HTTP $($_.Exception.Response.StatusCode): $($_.Exception.Response.StatusDescription)"
        } else {
            $_.Exception.Message
        }
        Write-ConnectivityResult "Fabric API Access" $false "" $errorDetails
    }
}

function Test-WorkspaceConnectivity {
    Write-Host "`n=== Workspace Connectivity ===" -ForegroundColor Cyan
    
    if (-not $env:ACCESS_TOKEN) {
        Write-ConnectivityResult "Workspace Access" $false "ACCESS_TOKEN not available"
        return
    }
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    # Test Provider workspace
    try {
        $providerWorkspace = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ProviderWorkspaceId" -Headers $headers -ErrorAction Stop
        Write-ConnectivityResult "Provider Workspace Access" $true "Name: '$($providerWorkspace.displayName)'"
        
        # Test items in Provider workspace
        try {
            $providerItems = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ProviderWorkspaceId/items" -Headers $headers -ErrorAction Stop
            $itemCounts = $providerItems.value | Group-Object type | ForEach-Object { "$($_.Count) $($_.Name)" }
            Write-ConnectivityResult "Provider Items Enumeration" $true "Items: $($itemCounts -join ', ')"
        }
        catch {
            Write-ConnectivityResult "Provider Items Enumeration" $false "" $_.Exception.Message
        }
    }
    catch {
        Write-ConnectivityResult "Provider Workspace Access" $false "ID: $ProviderWorkspaceId" $_.Exception.Message
    }
    
    # Test Consumer workspace
    try {
        $consumerWorkspace = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ConsumerWorkspaceId" -Headers $headers -ErrorAction Stop
        Write-ConnectivityResult "Consumer Workspace Access" $true "Name: '$($consumerWorkspace.displayName)'"
        
        # Test items in Consumer workspace
        try {
            $consumerItems = Invoke-RestMethod -Method GET -Uri "https://api.fabric.microsoft.com/v1/workspaces/$ConsumerWorkspaceId/items" -Headers $headers -ErrorAction Stop
            $itemCounts = $consumerItems.value | Group-Object type | ForEach-Object { "$($_.Count) $($_.Name)" }
            Write-ConnectivityResult "Consumer Items Enumeration" $true "Items: $($itemCounts -join ', ')"
        }
        catch {
            Write-ConnectivityResult "Consumer Items Enumeration" $false "" $_.Exception.Message
        }
    }
    catch {
        Write-ConnectivityResult "Consumer Workspace Access" $false "ID: $ConsumerWorkspaceId" $_.Exception.Message
    }
}

function Test-PowerBiApiAccess {
    Write-Host "`n=== Power BI API Access ===" -ForegroundColor Cyan
    
    if (-not $env:ACCESS_TOKEN) {
        Write-ConnectivityResult "Power BI API" $false "ACCESS_TOKEN not available"
        return
    }
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    try {
        # Test Power BI groups endpoint
        $groups = Invoke-RestMethod -Method GET -Uri "https://api.powerbi.com/v1.0/myorg/groups" -Headers $headers -ErrorAction Stop
        Write-ConnectivityResult "Power BI Groups API" $true "Found $($groups.value.Count) groups"
        
        # Test if our workspaces are accessible via Power BI API
        $providerGroup = $groups.value | Where-Object { $_.id -eq $ProviderWorkspaceId }
        if ($providerGroup) {
            Write-ConnectivityResult "Provider via Power BI API" $true "Group name: '$($providerGroup.name)'"
        } else {
            Write-ConnectivityResult "Provider via Power BI API" $false "Workspace not found in Power BI groups"
        }
        
        $consumerGroup = $groups.value | Where-Object { $_.id -eq $ConsumerWorkspaceId }
        if ($consumerGroup) {
            Write-ConnectivityResult "Consumer via Power BI API" $true "Group name: '$($consumerGroup.name)'"
        } else {
            Write-ConnectivityResult "Consumer via Power BI API" $false "Workspace not found in Power BI groups"
        }
        
    }
    catch {
        Write-ConnectivityResult "Power BI Groups API" $false "" $_.Exception.Message
    }
}

function Test-ApiPermissions {
    Write-Host "`n=== API Permissions Check ===" -ForegroundColor Cyan
    
    if (-not $env:ACCESS_TOKEN) {
        Write-ConnectivityResult "API Permissions" $false "ACCESS_TOKEN not available"
        return
    }
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    # Test various API endpoints to determine permission scope
    $permissionTests = @(
        @{ Name = "Read Workspaces"; Uri = "https://api.fabric.microsoft.com/v1/workspaces"; Method = "GET" },
        @{ Name = "Read Capacities"; Uri = "https://api.fabric.microsoft.com/v1/capacities"; Method = "GET" },
        @{ Name = "Power BI Admin"; Uri = "https://api.powerbi.com/v1.0/myorg/admin/workspaces"; Method = "GET" }
    )
    
    foreach ($test in $permissionTests) {
        try {
            $response = Invoke-RestMethod -Method $test.Method -Uri $test.Uri -Headers $headers -ErrorAction Stop
            Write-ConnectivityResult "Permission: $($test.Name)" $true "Access granted"
        }
        catch {
            $statusCode = if ($_.Exception.Response.StatusCode) { $_.Exception.Response.StatusCode } else { "Unknown" }
            if ($statusCode -eq 403) {
                Write-ConnectivityResult "Permission: $($test.Name)" $false "Access denied (403 Forbidden)"
            } else {
                Write-ConnectivityResult "Permission: $($test.Name)" $false "" $_.Exception.Message
            }
        }
    }
}

function Write-ConnectivitySummary {
    Write-Host "`n=== Connectivity Test Summary ===" -ForegroundColor Cyan
    
    $totalTests = $script:TestResults.Count
    $passedTests = ($script:TestResults | Where-Object { $_.Status -eq "PASS" }).Count
    $failedTests = ($script:TestResults | Where-Object { $_.Status -eq "FAIL" }).Count
    
    Write-Host "Total Tests: $totalTests" -ForegroundColor White
    Write-Host "Passed: $passedTests" -ForegroundColor Green  
    Write-Host "Failed: $failedTests" -ForegroundColor Red
    
    if ($failedTests -gt 0) {
        Write-Host "`nFailed Tests:" -ForegroundColor Red
        $script:TestResults | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
            Write-Host "  - $($_.Test)" -ForegroundColor Red
            if ($_.Error) { Write-Host "    $($_.Error)" -ForegroundColor Gray }
        }
        
        Write-Host "`nRecommendations:" -ForegroundColor Yellow
        if (($script:TestResults | Where-Object { $_.Test -like "*ACCESS_TOKEN*" -and $_.Status -eq "FAIL" })) {
            Write-Host "  • Set ACCESS_TOKEN environment variable with a valid Fabric/Power BI API token" -ForegroundColor Yellow
        }
        if (($script:TestResults | Where-Object { $_.Test -like "*Workspace Access*" -and $_.Status -eq "FAIL" })) {
            Write-Host "  • Verify workspace IDs are correct and you have access to them" -ForegroundColor Yellow
        }
        if (($script:TestResults | Where-Object { $_.Test -like "*Permission*" -and $_.Status -eq "FAIL" })) {
            Write-Host "  • Check that your account has sufficient permissions for Fabric and Power BI APIs" -ForegroundColor Yellow
        }
    } else {
        Write-Host "`n✅ All connectivity tests passed!" -ForegroundColor Green
    }
    
    # Export results
    $resultsFile = "connectivity-test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $script:TestResults | ConvertTo-Json -Depth 3 | Out-File $resultsFile
    Write-Host "`nDetailed results saved to: $resultsFile" -ForegroundColor Gray
    
    return $failedTests -eq 0
}

# Main execution
Write-Host "Microsoft Fabric POC - Connectivity Tests" -ForegroundColor Magenta
Write-Host "=========================================" -ForegroundColor Magenta
Write-Host "Provider Workspace: $ProviderWorkspaceId" -ForegroundColor Gray
Write-Host "Consumer Workspace: $ConsumerWorkspaceId" -ForegroundColor Gray
Write-Host ""

# Run all connectivity tests
Test-Environment
Test-NetworkConnectivity  
Test-FabricApiAccess
Test-WorkspaceConnectivity
Test-PowerBiApiAccess
Test-ApiPermissions

# Display summary and exit with appropriate code
$success = Write-ConnectivitySummary
exit $(if ($success) { 0 } else { 1 })