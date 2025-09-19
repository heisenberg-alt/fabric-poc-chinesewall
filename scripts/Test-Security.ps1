<#
.SYNOPSIS
    Security validation script for Microsoft Fabric POC "Chinese Wall" implementation

.DESCRIPTION
    This script validates security controls including:
    - Workspace isolation and access controls
    - OneLake security roles and data plane permissions
    - Row-Level Security (RLS) and Column-Level Security (CLS)
    - Power BI semantic model security
    - Cross-entity data access restrictions

.PARAMETER ProviderWorkspaceId
    Provider workspace ID (Entity A)
    
.PARAMETER ConsumerWorkspaceId
    Consumer workspace ID (Entity B)
    
.PARAMETER TestUserUpn
    UPN of test user for validation
    
.PARAMETER SqlConnectionString
    SQL connection string for testing RLS/CLS
    
.PARAMETER SkipSqlTests
    Skip SQL security tests
    
.PARAMETER Verbose
    Enable verbose output

.EXAMPLE
    .\Test-Security.ps1 -ProviderWorkspaceId "abc-123" -ConsumerWorkspaceId "def-456" -TestUserUpn "testuser@domain.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$ProviderWorkspaceId,
    
    [Parameter(Mandatory=$true)]
    [string]$ConsumerWorkspaceId,
    
    [string]$TestUserUpn,
    [string]$SqlConnectionString,
    [switch]$SkipSqlTests,
    [switch]$Verbose
)

$script:SecurityTests = @()

function Write-SecurityResult {
    param(
        [string]$TestName,
        [string]$Category,
        [bool]$Passed,
        [string]$Details = "",
        [string]$Risk = "",
        [string]$Recommendation = ""
    )
    
    $status = if ($Passed) { "PASS" } else { "FAIL" }
    $color = if ($Passed) { "Green" } else { "Red" }
    
    Write-Host "[$status] $TestName" -ForegroundColor $color
    if ($Details) { Write-Host "  Details: $Details" -ForegroundColor Gray }
    if ($Risk) { Write-Host "  Risk: $Risk" -ForegroundColor Yellow }
    if ($Recommendation) { Write-Host "  Recommendation: $Recommendation" -ForegroundColor Cyan }
    
    $script:SecurityTests += [PSCustomObject]@{
        Test = $TestName
        Category = $Category
        Status = $status
        Details = $Details
        Risk = $Risk
        Recommendation = $Recommendation
        Timestamp = Get-Date
    }
}

function Test-WorkspaceIsolation {
    Write-Host "`n=== Workspace Isolation Tests ===" -ForegroundColor Magenta
    
    if (-not $env:ACCESS_TOKEN) {
        Write-SecurityResult "Workspace Access Control" "Isolation" $false "ACCESS_TOKEN not available"
        return
    }
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    # Test workspace roles and permissions
    try {
        # Get Provider workspace users
        $providerUsersUri = "https://api.fabric.microsoft.com/v1/workspaces/$ProviderWorkspaceId/roleAssignments"
        $providerUsers = Invoke-RestMethod -Method GET -Uri $providerUsersUri -Headers $headers -ErrorAction Stop
        
        Write-SecurityResult "Provider Workspace Role Assignments" "Isolation" $true "Found $($providerUsers.value.Count) role assignments"
        
        if ($Verbose -and $providerUsers.value) {
            Write-Host "  Provider workspace roles:" -ForegroundColor Gray
            $providerUsers.value | ForEach-Object {
                Write-Host "    - $($_.principal.displayName) ($($_.principal.type)): $($_.role)" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-SecurityResult "Provider Workspace Role Assignments" "Isolation" $false "" "Cannot verify workspace access controls" "Review workspace permissions via Fabric portal"
    }
    
    try {
        # Get Consumer workspace users
        $consumerUsersUri = "https://api.fabric.microsoft.com/v1/workspaces/$ConsumerWorkspaceId/roleAssignments"
        $consumerUsers = Invoke-RestMethod -Method GET -Uri $consumerUsersUri -Headers $headers -ErrorAction Stop
        
        Write-SecurityResult "Consumer Workspace Role Assignments" "Isolation" $true "Found $($consumerUsers.value.Count) role assignments"
        
        if ($Verbose -and $consumerUsers.value) {
            Write-Host "  Consumer workspace roles:" -ForegroundColor Gray
            $consumerUsers.value | ForEach-Object {
                Write-Host "    - $($_.principal.displayName) ($($_.principal.type)): $($_.role)" -ForegroundColor Gray
            }
        }
        
        # Check for overlapping users between workspaces
        if ($providerUsers.value -and $consumerUsers.value) {
            $providerPrincipals = $providerUsers.value | ForEach-Object { $_.principal.id }
            $consumerPrincipals = $consumerUsers.value | ForEach-Object { $_.principal.id }
            $overlappingUsers = $providerPrincipals | Where-Object { $_ -in $consumerPrincipals }
            
            if ($overlappingUsers.Count -gt 0) {
                Write-SecurityResult "Cross-Workspace User Access" "Isolation" $false "Found $($overlappingUsers.Count) users with access to both workspaces" "Users may have excessive permissions" "Review and minimize cross-workspace access"
            } else {
                Write-SecurityResult "Cross-Workspace User Access" "Isolation" $true "No users have access to both workspaces"
            }
        }
    }
    catch {
        Write-SecurityResult "Consumer Workspace Role Assignments" "Isolation" $false "" "Cannot verify workspace access controls" "Review workspace permissions via Fabric portal"
    }
}

function Test-OneLakeSecurity {
    Write-Host "`n=== OneLake Security Tests ===" -ForegroundColor Magenta
    
    if (-not $env:ACCESS_TOKEN) {
        Write-SecurityResult "OneLake Security" "Data Access" $false "ACCESS_TOKEN not available"
        return
    }
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    # Test OneLake security roles on Provider workspace items
    try {
        $itemsUri = "https://api.fabric.microsoft.com/v1/workspaces/$ProviderWorkspaceId/items"
        $items = Invoke-RestMethod -Method GET -Uri $itemsUri -Headers $headers -ErrorAction Stop
        
        $lakehouses = $items.value | Where-Object { $_.type -eq "Lakehouse" }
        $warehouses = $items.value | Where-Object { $_.type -eq "Warehouse" }
        $dataItems = $lakehouses + $warehouses
        
        if ($dataItems.Count -gt 0) {
            Write-SecurityResult "Data Items Found" "Data Access" $true "Found $($dataItems.Count) data items (Lakehouses/Warehouses)"
            
            foreach ($item in $dataItems) {
                try {
                    # Check OneLake security roles for each item
                    $rolesUri = "https://api.fabric.microsoft.com/v1/workspaces/$ProviderWorkspaceId/items/$($item.id)/roles"
                    $roles = Invoke-RestMethod -Method GET -Uri $rolesUri -Headers $headers -ErrorAction Stop
                    
                    if ($roles.value -and $roles.value.Count -gt 0) {
                        Write-SecurityResult "OneLake Security Roles - $($item.displayName)" "Data Access" $true "Found $($roles.value.Count) security roles configured"
                        
                        # Check for specific role types
                        $readRoles = $roles.value | Where-Object { $_.role -eq "Read" }
                        $readWriteRoles = $roles.value | Where-Object { $_.role -eq "ReadWrite" }
                        
                        if ($readRoles.Count -gt 0) {
                            Write-SecurityResult "Read-Only Access Controls" "Data Access" $true "$($readRoles.Count) Read-only roles configured"
                        }
                        if ($readWriteRoles.Count -gt 0) {
                            Write-SecurityResult "Read-Write Access Controls" "Data Access" $true "$($readWriteRoles.Count) Read-Write roles configured" "Read-Write access may be excessive" "Review if Read-Write permissions are necessary"
                        }
                        
                        if ($Verbose) {
                            Write-Host "  Security roles for $($item.displayName):" -ForegroundColor Gray
                            $roles.value | ForEach-Object {
                                Write-Host "    - Principal: $($_.principal.id) ($($_.principal.type)), Role: $($_.role)" -ForegroundColor Gray
                            }
                        }
                    } else {
                        Write-SecurityResult "OneLake Security Roles - $($item.displayName)" "Data Access" $false "No security roles configured" "Unrestricted access to data" "Configure OneLake security roles"
                    }
                }
                catch {
                    Write-SecurityResult "OneLake Security Roles - $($item.displayName)" "Data Access" $false "" "Cannot verify OneLake security" "Check item permissions via Fabric portal"
                }
            }
        } else {
            Write-SecurityResult "Data Items Found" "Data Access" $false "No Lakehouses or Warehouses found in Provider workspace"
        }
    }
    catch {
        Write-SecurityResult "Provider Workspace Items" "Data Access" $false "" "Cannot enumerate workspace items" "Verify workspace access"
    }
}

function Test-OneLakeShortcuts {
    Write-Host "`n=== OneLake Shortcuts Security ===" -ForegroundColor Magenta
    
    if (-not $env:ACCESS_TOKEN) {
        Write-SecurityResult "Shortcut Security" "Data Access" $false "ACCESS_TOKEN not available"
        return
    }
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    try {
        # Get Consumer workspace items
        $itemsUri = "https://api.fabric.microsoft.com/v1/workspaces/$ConsumerWorkspaceId/items"
        $items = Invoke-RestMethod -Method GET -Uri $itemsUri -Headers $headers -ErrorAction Stop
        
        $lakehouses = $items.value | Where-Object { $_.type -eq "Lakehouse" }
        
        foreach ($lakehouse in $lakehouses) {
            try {
                # Check shortcuts in Consumer Lakehouse
                $shortcutsUri = "https://api.fabric.microsoft.com/v1/workspaces/$ConsumerWorkspaceId/items/$($lakehouse.id)/shortcuts"
                $shortcuts = Invoke-RestMethod -Method GET -Uri $shortcutsUri -Headers $headers -ErrorAction Stop
                
                if ($shortcuts.value -and $shortcuts.value.Count -gt 0) {
                    Write-SecurityResult "Shortcuts Found - $($lakehouse.displayName)" "Data Access" $true "Found $($shortcuts.value.Count) shortcuts"
                    
                    # Analyze shortcut targets
                    $internalShortcuts = $shortcuts.value | Where-Object { $_.target -like "*onelake*" -or $_.target -like "*fabric*" }
                    $externalShortcuts = $shortcuts.value | Where-Object { $_.target -notlike "*onelake*" -and $_.target -notlike "*fabric*" }
                    
                    if ($internalShortcuts.Count -gt 0) {
                        Write-SecurityResult "Internal OneLake Shortcuts" "Data Access" $true "$($internalShortcuts.Count) internal shortcuts (expected for POC)"
                    }
                    
                    if ($externalShortcuts.Count -gt 0) {
                        Write-SecurityResult "External Data Shortcuts" "Data Access" $false "$($externalShortcuts.Count) external shortcuts found" "External data may bypass security controls" "Review external shortcut targets and security"
                    }
                    
                    # Check for Provider workspace shortcuts
                    $providerShortcuts = $shortcuts.value | Where-Object { $_.target -like "*$ProviderWorkspaceId*" }
                    if ($providerShortcuts.Count -gt 0) {
                        Write-SecurityResult "Provider Data Access via Shortcuts" "Data Access" $true "Consumer has shortcut access to Provider data (expected)"
                        
                        if ($Verbose) {
                            Write-Host "  Provider shortcuts:" -ForegroundColor Gray
                            $providerShortcuts | ForEach-Object {
                                Write-Host "    - $($_.name): $($_.path)" -ForegroundColor Gray
                            }
                        }
                    }
                    
                } else {
                    Write-SecurityResult "Shortcuts Found - $($lakehouse.displayName)" "Data Access" $false "No shortcuts found" "Consumer may not have access to Provider data" "Verify shortcut configuration"
                }
            }
            catch {
                Write-SecurityResult "Shortcuts Check - $($lakehouse.displayName)" "Data Access" $false "" "Cannot enumerate shortcuts" "Check item permissions"
            }
        }
    }
    catch {
        Write-SecurityResult "Consumer Workspace Items" "Data Access" $false "" "Cannot enumerate Consumer workspace items" "Verify workspace access"
    }
}

function Test-SqlSecurity {
    if ($SkipSqlTests) {
        Write-Host "`n=== SQL Security Tests (Skipped) ===" -ForegroundColor Yellow
        return
    }
    
    Write-Host "`n=== SQL Security Tests ===" -ForegroundColor Magenta
    
    if (-not $SqlConnectionString) {
        Write-SecurityResult "SQL Security Configuration" "Data Access" $false "SQL connection string not provided" "Cannot validate SQL-level security" "Provide SQL connection string"
        return
    }
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($SqlConnectionString)
        $connection.Open()
        
        Write-SecurityResult "SQL Database Connection" "Data Access" $true "Successfully connected to SQL endpoint"
        
        # Test for Row-Level Security (RLS)
        $command = $connection.CreateCommand()
        $command.CommandText = @"
SELECT COUNT(*) as PolicyCount
FROM sys.security_policies sp
INNER JOIN sys.tables t ON sp.object_id = t.object_id
WHERE t.name = 'MarketData'
"@
        $rlsPolicyCount = $command.ExecuteScalar()
        
        if ($rlsPolicyCount -gt 0) {
            Write-SecurityResult "Row-Level Security (RLS) Policy" "Data Access" $true "RLS policy found on MarketData table"
            
            # Test RLS predicate function
            $command.CommandText = @"
SELECT COUNT(*) as FunctionCount
FROM sys.objects o
INNER JOIN sys.schemas s ON o.schema_id = s.schema_id  
WHERE o.type = 'FN' 
AND s.name = 'Security'
AND o.name LIKE '%MarketData%'
"@
            $rlsFunctionCount = $command.ExecuteScalar()
            
            if ($rlsFunctionCount -gt 0) {
                Write-SecurityResult "RLS Predicate Function" "Data Access" $true "Security function found for MarketData filtering"
            } else {
                Write-SecurityResult "RLS Predicate Function" "Data Access" $false "No security function found" "RLS may not be properly configured" "Verify RLS predicate function exists"
            }
        } else {
            Write-SecurityResult "Row-Level Security (RLS) Policy" "Data Access" $false "No RLS policy found on MarketData table" "Data access not restricted by RLS" "Implement RLS policy on MarketData"
        }
        
        # Test for Column-Level Security (CLS)
        $command.CommandText = @"
SELECT COUNT(*) as PermissionCount
FROM sys.column_permissions cp
INNER JOIN sys.tables t ON cp.major_id = t.object_id
WHERE t.name = 'MarketData'
"@
        $clsPermissionCount = $command.ExecuteScalar()
        
        if ($clsPermissionCount -gt 0) {
            Write-SecurityResult "Column-Level Security (CLS)" "Data Access" $true "Column permissions found on MarketData table"
        } else {
            Write-SecurityResult "Column-Level Security (CLS)" "Data Access" $false "No column permissions found" "Sensitive columns may be accessible" "Consider implementing CLS for sensitive data"
        }
        
        # Test for Dynamic Data Masking (DDM)
        $command.CommandText = @"
SELECT COUNT(*) as MaskedColumns
FROM sys.masked_columns mc
INNER JOIN sys.tables t ON mc.object_id = t.object_id
WHERE t.name = 'MarketData'
"@
        $ddmColumnCount = $command.ExecuteScalar()
        
        if ($ddmColumnCount -gt 0) {
            Write-SecurityResult "Dynamic Data Masking (DDM)" "Data Access" $true "$ddmColumnCount masked columns found on MarketData table"
        } else {
            Write-SecurityResult "Dynamic Data Masking (DDM)" "Data Access" $false "No data masking found" "Sensitive data may be exposed" "Consider implementing DDM for PII/sensitive columns"
        }
        
        # Test basic data access (should be filtered by RLS if properly configured)
        $command.CommandText = "SELECT COUNT(*) FROM dbo.MarketData"
        $visibleRows = $command.ExecuteScalar()
        Write-SecurityResult "Data Access Test" "Data Access" $true "Query executed successfully, $visibleRows rows visible to current user"
        
        $connection.Close()
    }
    catch {
        Write-SecurityResult "SQL Database Connection" "Data Access" $false "" "Cannot connect to SQL endpoint" "Verify SQL connection string and permissions"
    }
}

function Test-PowerBiSecurity {
    Write-Host "`n=== Power BI Security Tests ===" -ForegroundColor Magenta
    
    if (-not $env:ACCESS_TOKEN) {
        Write-SecurityResult "Power BI Security" "Semantic Model" $false "ACCESS_TOKEN not available"
        return
    }
    
    $headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
    
    try {
        # Test Consumer workspace datasets
        $datasetsUri = "https://api.powerbi.com/v1.0/myorg/groups/$ConsumerWorkspaceId/datasets"
        $datasets = Invoke-RestMethod -Method GET -Uri $datasetsUri -Headers $headers -ErrorAction Stop
        
        if ($datasets.value -and $datasets.value.Count -gt 0) {
            Write-SecurityResult "Power BI Datasets Found" "Semantic Model" $true "Found $($datasets.value.Count) datasets in Consumer workspace"
            
            foreach ($dataset in $datasets.value) {
                # Check dataset permissions
                try {
                    $permissionsUri = "https://api.powerbi.com/v1.0/myorg/groups/$ConsumerWorkspaceId/datasets/$($dataset.id)/users"
                    $permissions = Invoke-RestMethod -Method GET -Uri $permissionsUri -Headers $headers -ErrorAction Stop
                    
                    if ($permissions.value -and $permissions.value.Count -gt 0) {
                        Write-SecurityResult "Dataset Permissions - $($dataset.name)" "Semantic Model" $true "$($permissions.value.Count) permission entries found"
                        
                        # Check for Build permissions (should be restricted)
                        $buildPermissions = $permissions.value | Where-Object { $_.datasetUserAccessRight -eq "ReadWriteReshareExplore" -or $_.datasetUserAccessRight -like "*Build*" }
                        if ($buildPermissions.Count -gt 0) {
                            Write-SecurityResult "Build Permissions - $($dataset.name)" "Semantic Model" $false "$($buildPermissions.Count) users have Build permissions" "Users can create new artifacts from dataset" "Restrict Build permissions to prevent cross-entity reuse"
                        } else {
                            Write-SecurityResult "Build Permissions - $($dataset.name)" "Semantic Model" $true "No excessive Build permissions found"
                        }
                        
                        # Check for Reshare permissions
                        $resharePermissions = $permissions.value | Where-Object { $_.datasetUserAccessRight -like "*Reshare*" }
                        if ($resharePermissions.Count -gt 0) {
                            Write-SecurityResult "Reshare Permissions - $($dataset.name)" "Semantic Model" $false "$($resharePermissions.Count) users have Reshare permissions" "Users can share dataset with others" "Restrict Reshare permissions to maintain isolation"
                        } else {
                            Write-SecurityResult "Reshare Permissions - $($dataset.name)" "Semantic Model" $true "No Reshare permissions found"
                        }
                        
                        if ($Verbose) {
                            Write-Host "  Dataset permissions for $($dataset.name):" -ForegroundColor Gray
                            $permissions.value | ForEach-Object {
                                Write-Host "    - $($_.emailAddress): $($_.datasetUserAccessRight)" -ForegroundColor Gray
                            }
                        }
                    } else {
                        Write-SecurityResult "Dataset Permissions - $($dataset.name)" "Semantic Model" $false "No specific permissions configured" "Dataset may inherit workspace permissions" "Configure explicit dataset permissions"
                    }
                }
                catch {
                    Write-SecurityResult "Dataset Permissions - $($dataset.name)" "Semantic Model" $false "" "Cannot check dataset permissions" "Verify API access rights"
                }
            }
        } else {
            Write-SecurityResult "Power BI Datasets Found" "Semantic Model" $false "No datasets found in Consumer workspace" "No semantic models to secure" "Create and secure Power BI datasets"
        }
    }
    catch {
        Write-SecurityResult "Power BI API Access" "Semantic Model" $false "" "Cannot access Power BI API" "Verify Power BI API permissions"
    }
}

function Test-IdentityAndAccess {
    Write-Host "`n=== Identity and Access Tests ===" -ForegroundColor Magenta
    
    if ($TestUserUpn) {
        Write-SecurityResult "Test User Specified" "Identity" $true "Test user: $TestUserUpn"
        
        # If we had Azure AD Graph access, we could test:
        # - User group memberships
        # - Conditional access policies
        # - MFA requirements
        Write-SecurityResult "User Context Validation" "Identity" $false "Cannot validate user context via API" "Test user access manually" "Manually verify test user can access appropriate resources"
    } else {
        Write-SecurityResult "Test User Specified" "Identity" $false "No test user provided for validation" "Cannot test user-specific access" "Provide test user UPN for comprehensive validation"
    }
    
    # Test current token context
    if ($env:ACCESS_TOKEN) {
        try {
            # Try to decode token to see claims (basic JWT inspection)
            $tokenParts = $env:ACCESS_TOKEN.Split('.')
            if ($tokenParts.Count -eq 3) {
                $payload = $tokenParts[1]
                # Add padding if needed for base64 decoding
                while ($payload.Length % 4 -ne 0) { $payload += "=" }
                $decodedBytes = [System.Convert]::FromBase64String($payload)
                $decodedPayload = [System.Text.Encoding]::UTF8.GetString($decodedBytes) | ConvertFrom-Json
                
                if ($decodedPayload.upn) {
                    Write-SecurityResult "Token User Principal" "Identity" $true "Token issued for: $($decodedPayload.upn)"
                }
                if ($decodedPayload.aud) {
                    Write-SecurityResult "Token Audience" "Identity" $true "Token audience: $($decodedPayload.aud)"
                }
                if ($decodedPayload.scp) {
                    Write-SecurityResult "Token Scope" "Identity" $true "Token scope: $($decodedPayload.scp)"
                }
            }
        }
        catch {
            Write-SecurityResult "Token Analysis" "Identity" $false "" "Cannot decode access token" "Token may be encrypted or invalid format"
        }
    }
}

function Write-SecuritySummary {
    Write-Host "`n=== Security Test Summary ===" -ForegroundColor Magenta
    
    $totalTests = $script:SecurityTests.Count
    $passedTests = ($script:SecurityTests | Where-Object { $_.Status -eq "PASS" }).Count
    $failedTests = ($script:SecurityTests | Where-Object { $_.Status -eq "FAIL" }).Count
    
    Write-Host "Total Security Tests: $totalTests" -ForegroundColor White
    Write-Host "Passed: $passedTests" -ForegroundColor Green
    Write-Host "Failed: $failedTests" -ForegroundColor Red
    
    # Group by category
    $categories = $script:SecurityTests | Group-Object Category
    Write-Host "`nResults by Category:" -ForegroundColor Cyan
    foreach ($category in $categories) {
        $categoryPassed = ($category.Group | Where-Object { $_.Status -eq "PASS" }).Count
        $categoryFailed = ($category.Group | Where-Object { $_.Status -eq "FAIL" }).Count
        $categoryColor = if ($categoryFailed -eq 0) { "Green" } elseif ($categoryPassed -eq 0) { "Red" } else { "Yellow" }
        Write-Host "  $($category.Name): $categoryPassed passed, $categoryFailed failed" -ForegroundColor $categoryColor
    }
    
    # Show critical failures
    if ($failedTests -gt 0) {
        Write-Host "`nCritical Security Issues:" -ForegroundColor Red
        $script:SecurityTests | Where-Object { $_.Status -eq "FAIL" -and $_.Risk } | ForEach-Object {
            Write-Host "  ❌ $($_.Test)" -ForegroundColor Red
            Write-Host "     Risk: $($_.Risk)" -ForegroundColor Yellow
            if ($_.Recommendation) {
                Write-Host "     Fix: $($_.Recommendation)" -ForegroundColor Cyan
            }
        }
    }
    
    # Export detailed results
    $resultsFile = "security-test-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $script:SecurityTests | ConvertTo-Json -Depth 3 | Out-File $resultsFile
    Write-Host "`nDetailed security results saved to: $resultsFile" -ForegroundColor Gray
    
    return $failedTests -eq 0
}

# Main execution
Write-Host "Microsoft Fabric POC - Security Validation" -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "Provider Workspace: $ProviderWorkspaceId" -ForegroundColor Gray
Write-Host "Consumer Workspace: $ConsumerWorkspaceId" -ForegroundColor Gray
if ($TestUserUpn) { Write-Host "Test User: $TestUserUpn" -ForegroundColor Gray }
Write-Host ""

# Run all security tests
Test-WorkspaceIsolation
Test-OneLakeSecurity
Test-OneLakeShortcuts
Test-SqlSecurity
Test-PowerBiSecurity
Test-IdentityAndAccess

# Display summary and exit with appropriate code
$success = Write-SecuritySummary
exit $(if ($success) { 0 } else { 1 })