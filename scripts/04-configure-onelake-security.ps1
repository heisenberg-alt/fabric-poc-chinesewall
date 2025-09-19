
<#
 Applies OneLake security roles to a Lakehouse or Warehouse item.

 Prereqs:
 - $env:ACCESS_TOKEN set
 - Obtain workspaceId and itemId (Lakehouse/Warehouse)
 - Update 03-onelake-security-roles.json members with your group object IDs
#>

param(
  [Parameter(Mandatory=$true)][string]$WorkspaceId,
  [Parameter(Mandatory=$true)][string]$ItemId,
  [string]$RolesFile = "./03-onelake-security-roles.json"
)

$headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN"; 'Content-Type' = 'application/json' }
$body = Get-Content $RolesFile -Raw
$uri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$ItemId/dataAccessRoles"
Write-Host "Applying OneLake roles to item: $ItemId"
Invoke-RestMethod -Method PUT -Uri $uri -Headers $headers -Body $body
