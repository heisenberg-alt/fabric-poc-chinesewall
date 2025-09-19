<#
.SYNOPSIS
    Quick start script for testing Microsoft Fabric POC deployment

.DESCRIPTION
    This script helps users get started with POC testing by:
    - Guiding through prerequisite setup
    - Collecting required configuration
    - Running basic validation tests
    - Providing next steps for comprehensive testing

.PARAMETER Interactive
    Run in interactive mode with prompts

.PARAMETER SkipPrerequisites
    Skip prerequisite checks

.EXAMPLE
    .\Quick-Test.ps1 -Interactive
#>

[CmdletBinding()]
param(
    [switch]$Interactive,
    [switch]$SkipPrerequisites
)

function Write-Header {
    param([string]$Title)
    Write-Host "`n$('=' * 50)" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host $('=' * 50) -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n► $Message" -ForegroundColor Yellow
}

function Test-Prerequisites {
    Write-Header "Checking Prerequisites"
    
    $issues = @()
    
    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $issues += "PowerShell 5.0+ required (current: $($PSVersionTable.PSVersion))"
    }
    
    # Check ACCESS_TOKEN
    if (-not $env:ACCESS_TOKEN) {
        $issues += "ACCESS_TOKEN environment variable not set"
    }
    
    # Check for Azure CLI (optional)
    try {
        $azVersion = az version 2>$null | ConvertFrom-Json
        Write-Host "✅ Azure CLI found: $($azVersion.'azure-cli')" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️  Azure CLI not found (optional but recommended)" -ForegroundColor Yellow
    }
    
    # Check for Power BI PowerShell module (optional)
    try {
        $module = Get-Module -ListAvailable -Name MicrosoftPowerBIMgmt
        if ($module) {
            Write-Host "✅ Power BI PowerShell module found" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Power BI PowerShell module not found (optional)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "⚠️  Power BI PowerShell module not found (optional)" -ForegroundColor Yellow
    }
    
    if ($issues.Count -gt 0) {
        Write-Host "`n❌ Issues found:" -ForegroundColor Red
        $issues | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
        return $false
    } else {
        Write-Host "`n✅ All critical prerequisites met!" -ForegroundColor Green
        return $true
    }
}

function Get-AccessToken {
    Write-Header "Access Token Setup"
    
    if ($env:ACCESS_TOKEN) {
        Write-Host "✅ ACCESS_TOKEN already set" -ForegroundColor Green
        return $true
    }
    
    Write-Host "You need an access token to test the Fabric APIs." -ForegroundColor White
    Write-Host "`nChoose a method to obtain an access token:" -ForegroundColor White
    Write-Host "1. Azure CLI (recommended)" -ForegroundColor Cyan
    Write-Host "2. Power BI PowerShell module" -ForegroundColor Cyan
    Write-Host "3. Manual entry" -ForegroundColor Cyan
    Write-Host "4. Skip (use existing token)" -ForegroundColor Gray
    
    if ($Interactive) {
        do {
            $choice = Read-Host "`nEnter your choice (1-4)"
        } while ($choice -notin @('1','2','3','4'))
        
        switch ($choice) {
            '1' {
                Write-Step "Getting token via Azure CLI..."
                try {
                    $token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
                    if ($token) {
                        $env:ACCESS_TOKEN = $token
                        Write-Host "✅ Token obtained and set" -ForegroundColor Green
                        return $true
                    } else {
                        Write-Host "❌ Failed to get token. Try 'az login' first." -ForegroundColor Red
                    }
                } catch {
                    Write-Host "❌ Azure CLI error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            '2' {
                Write-Step "Getting token via Power BI PowerShell..."
                try {
                    Connect-PowerBIServiceAccount -ErrorAction Stop
                    $token = (Get-PowerBIAccessToken).AccessToken
                    $env:ACCESS_TOKEN = $token
                    Write-Host "✅ Token obtained and set" -ForegroundColor Green
                    return $true
                } catch {
                    Write-Host "❌ Power BI module error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            '3' {
                Write-Step "Manual token entry..."
                $token = Read-Host "Paste your access token" -AsSecureString
                $env:ACCESS_TOKEN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token))
                Write-Host "✅ Token set manually" -ForegroundColor Green
                return $true
            }
            '4' {
                Write-Host "⚠️  Skipping token setup" -ForegroundColor Yellow
                return $false
            }
        }
    }
    
    Write-Host "`nTo set up an access token manually, use one of these commands:" -ForegroundColor White
    Write-Host "# Azure CLI:" -ForegroundColor Gray
    Write-Host '$env:ACCESS_TOKEN = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv' -ForegroundColor Gray
    Write-Host "`n# Power BI PowerShell:" -ForegroundColor Gray
    Write-Host 'Connect-PowerBIServiceAccount; $env:ACCESS_TOKEN = (Get-PowerBIAccessToken).AccessToken' -ForegroundColor Gray
    
    return $false
}

function Get-Configuration {
    Write-Header "Configuration Setup"
    
    $config = @{}
    
    if ($Interactive) {
        Write-Host "Please provide the following workspace and item IDs:" -ForegroundColor White
        Write-Host "(You can find these in the Fabric portal URLs)" -ForegroundColor Gray
        
        $config.ProviderWorkspaceId = Read-Host "`nProvider Workspace ID (Entity A)"
        $config.ConsumerWorkspaceId = Read-Host "Consumer Workspace ID (Entity B)"
        $config.ProviderLakehouseItemId = Read-Host "Provider Lakehouse/Warehouse Item ID"
        $config.ConsumerLakehouseItemId = Read-Host "Consumer Lakehouse/Warehouse Item ID"
        
        $includeSql = Read-Host "`nInclude SQL tests? (y/n)" 
        if ($includeSql -eq 'y' -or $includeSql -eq 'yes') {
            $config.SqlConnectionString = Read-Host "SQL Connection String"
        }
        
        $testUser = Read-Host "`nTest user UPN (optional, press Enter to skip)"
        if ($testUser) {
            $config.TestUserUpn = $testUser
        }
        
        # Save configuration
        $configFile = "test-config.json"
        $config | ConvertTo-Json -Depth 2 | Out-File $configFile
        Write-Host "`n✅ Configuration saved to: $configFile" -ForegroundColor Green
        return $config
    } else {
        Write-Host "To set up configuration, either:" -ForegroundColor White
        Write-Host "1. Copy and edit scripts/test-config-sample.json" -ForegroundColor Cyan
        Write-Host "2. Run this script with -Interactive parameter" -ForegroundColor Cyan
        Write-Host "3. Provide parameters directly to test scripts" -ForegroundColor Cyan
        return $null
    }
}

function Run-QuickTests {
    param($Config)
    
    Write-Header "Running Quick Tests"
    
    if (-not $Config) {
        Write-Host "❌ No configuration provided. Skipping tests." -ForegroundColor Red
        return
    }
    
    # Test basic connectivity
    Write-Step "Testing basic connectivity..."
    try {
        $connectivityParams = @{
            ProviderWorkspaceId = $Config.ProviderWorkspaceId
            ConsumerWorkspaceId = $Config.ConsumerWorkspaceId
        }
        
        & ".\Test-Connectivity.ps1" @connectivityParams
        $connectivitySuccess = $LASTEXITCODE -eq 0
        
        if ($connectivitySuccess) {
            Write-Host "✅ Connectivity tests passed" -ForegroundColor Green
        } else {
            Write-Host "❌ Connectivity tests failed" -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Connectivity test error: $($_.Exception.Message)" -ForegroundColor Red
        $connectivitySuccess = $false
    }
    
    if ($connectivitySuccess) {
        Write-Step "Running comprehensive validation..."
        try {
            $validationParams = @{
                ProviderWorkspaceId = $Config.ProviderWorkspaceId
                ConsumerWorkspaceId = $Config.ConsumerWorkspaceId
                ProviderLakehouseItemId = $Config.ProviderLakehouseItemId
                ConsumerLakehouseItemId = $Config.ConsumerLakehouseItemId
            }
            
            if ($Config.SqlConnectionString) {
                $validationParams.SqlConnectionString = $Config.SqlConnectionString
            } else {
                $validationParams.SkipSqlTests = $true
            }
            
            if ($Config.TestUserUpn) {
                $validationParams.TestUserUpn = $Config.TestUserUpn
            }
            
            & ".\09-validate.ps1" @validationParams
            $validationSuccess = $LASTEXITCODE -eq 0
            
            if ($validationSuccess) {
                Write-Host "✅ Validation tests passed" -ForegroundColor Green
            } else {
                Write-Host "❌ Some validation tests failed" -ForegroundColor Red
            }
        } catch {
            Write-Host "❌ Validation test error: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

function Show-NextSteps {
    Write-Header "Next Steps"
    
    Write-Host "For comprehensive testing, run:" -ForegroundColor White
    Write-Host "  .\Test-FabricPOC.ps1 -ConfigFile 'test-config.json' -ExportResults" -ForegroundColor Cyan
    
    Write-Host "`nFor security-focused testing, run:" -ForegroundColor White  
    Write-Host "  .\Test-Security.ps1 -ProviderWorkspaceId 'your-id' -ConsumerWorkspaceId 'your-id'" -ForegroundColor Cyan
    
    Write-Host "`nFor manual testing scenarios, see:" -ForegroundColor White
    Write-Host "  README.md - 'Manual Test Scenarios' section" -ForegroundColor Cyan
    Write-Host "  docs/Test-Plan.md - Detailed test procedures" -ForegroundColor Cyan
    
    Write-Host "`nGenerated test report files will contain detailed findings." -ForegroundColor Gray
}

# Main execution
Write-Host "Microsoft Fabric POC - Quick Test Setup" -ForegroundColor Magenta
Write-Host "=======================================" -ForegroundColor Magenta

if (-not $SkipPrerequisites) {
    $prereqOk = Test-Prerequisites
    if (-not $prereqOk) {
        Write-Host "`n❌ Please resolve prerequisites before continuing." -ForegroundColor Red
        exit 1
    }
}

$tokenOk = Get-AccessToken
if (-not $tokenOk -and -not $env:ACCESS_TOKEN) {
    Write-Host "`n❌ Access token required for testing. Please set up authentication." -ForegroundColor Red
    exit 1
}

$config = Get-Configuration

if ($config) {
    Run-QuickTests -Config $config
}

Show-NextSteps

Write-Host "`n🎉 Quick test setup complete!" -ForegroundColor Green
Write-Host "Use the commands above to run comprehensive POC validation." -ForegroundColor White