
<#
 Creates an internal OneLake shortcut (Provider → Consumer).

 Notes:
 - This script targets the OneLake "shortcuts" endpoint for a Lakehouse in the Consumer workspace.
 - API shapes evolve; verify the latest schema at Microsoft Learn for OneLake shortcuts.
#>

param(
  [Parameter(Mandatory=$true)][string]$ConsumerWorkspaceId,
  [Parameter(Mandatory=$true)][string]$ConsumerLakehouseItemId,
  [Parameter(Mandatory=$true)][string]$ShortcutName = "MarketDataShortcut",
  [Parameter(Mandatory=$true)][string]$ProviderWorkspaceId,
  [Parameter(Mandatory=$true)][string]$ProviderLakehouseItemId,
  [string]$TargetPath = "Tables/MarketData"  # provider path
)

$headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN"; 'Content-Type' = 'application/json' }

$body = @{
  name = $ShortcutName
  target = @{
    type = "OneLake"
    oneLake = @{
      workspaceId = $ProviderWorkspaceId
      itemId      = $ProviderLakehouseItemId
      path        = $TargetPath
    }
  }
  path = "Tables/$ShortcutName"
} | ConvertTo-Json -Depth 6

$uri = "https://api.fabric.microsoft.com/v1/workspaces/$ConsumerWorkspaceId/items/$ConsumerLakehouseItemId/shortcuts"
Write-Host "Creating internal shortcut $ShortcutName"
Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body
