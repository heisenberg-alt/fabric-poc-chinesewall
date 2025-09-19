
<#
 Assigns workspace roles using Power BI REST API (Fabric uses the same workspace model).

 Prereqs:
 - $env:ACCESS_TOKEN contains a valid token with Power BI scope (Tenant/Group admin as needed)
 - You have workspace IDs from 01 script
 - Replace group UPNs/objectIds in the assignments below
#>

param(
  [Parameter(Mandatory=$true)][string]$ProviderWorkspaceId,
  [Parameter(Mandatory=$true)][string]$ConsumerWorkspaceId
)

$headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN"; 'Content-Type' = 'application/json' }

# Map Entra groups to roles
$assignments = @(
  @{ workspaceId=$ProviderWorkspaceId; principalType='Group'; identifier='REPLACE-ENTITYA-ADMINS-OBJECTID'; accessRight='Admin' },
  @{ workspaceId=$ProviderWorkspaceId; principalType='Group'; identifier='REPLACE-ENTITYA-ENGINEERS-OBJECTID'; accessRight='Contributor' },
  @{ workspaceId=$ProviderWorkspaceId; principalType='Group'; identifier='REPLACE-ENTITYA-ANALYSTS-OBJECTID'; accessRight='Viewer' },
  @{ workspaceId=$ConsumerWorkspaceId; principalType='Group'; identifier='REPLACE-ENTITYB-ADMINS-OBJECTID'; accessRight='Admin' },
  @{ workspaceId=$ConsumerWorkspaceId; principalType='Group'; identifier='REPLACE-ENTITYB-ENGINEERS-OBJECTID'; accessRight='Contributor' },
  @{ workspaceId=$ConsumerWorkspaceId; principalType='Group'; identifier='REPLACE-ENTITYB-ANALYSTS-OBJECTID'; accessRight='Viewer' }
)

foreach ($a in $assignments) {
  $body = @{ identifier=$a.identifier; principalType=$a.principalType; groupUserAccessRight=$a.accessRight } | ConvertTo-Json
  $uri = "https://api.powerbi.com/v1.0/myorg/groups/$($a.workspaceId)/users"
  Write-Host "Assigning $($a.accessRight) to $($a.identifier) on $($a.workspaceId)"
  Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body
}
