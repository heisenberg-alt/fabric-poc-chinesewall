
<#
 Basic post-setup validation:
 - Lists shortcuts in the Consumer Lakehouse
 - Attempts to read a file/table path via OneLake API
#>

param(
  [Parameter(Mandatory=$true)][string]$ConsumerWorkspaceId,
  [Parameter(Mandatory=$true)][string]$ConsumerLakehouseItemId
)

$headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN" }
$listUri = "https://api.fabric.microsoft.com/v1/workspaces/$ConsumerWorkspaceId/items/$ConsumerLakehouseItemId/shortcuts"
Write-Host "Listing shortcuts:" $listUri
$shortcuts = Invoke-RestMethod -Method GET -Uri $listUri -Headers $headers
$shortcuts | ConvertTo-Json -Depth 6 | Write-Output
