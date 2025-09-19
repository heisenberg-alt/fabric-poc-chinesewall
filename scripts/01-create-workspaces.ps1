
<#
 Creates two Fabric workspaces (Provider and Consumer).

 Prereqs:
 - Set an access token in env var ACCESS_TOKEN with Fabric/Power BI API scope.
   Example (PowerShell):
     $token = (Get-PowerBIAccessToken).AccessToken
     $env:ACCESS_TOKEN = $token
#>

param(
  [string]$ProviderName = "POC EntityA Provider",
  [string]$ConsumerName = "POC EntityB Consumer"
)

$headers = @{ Authorization = "Bearer $env:ACCESS_TOKEN"; 'Content-Type' = 'application/json' }

function New-FabricWorkspace($name) {
  $body = @{ displayName = $name; description = "POC workspace" } | ConvertTo-Json
  $res = Invoke-RestMethod -Method POST -Uri "https://api.fabric.microsoft.com/v1/workspaces" -Headers $headers -Body $body
  return $res
}

$provider = New-FabricWorkspace -name $ProviderName
Write-Host "Provider workspace created: $($provider.id)  $($provider.displayName)"

$consumer = New-FabricWorkspace -name $ConsumerName
Write-Host "Consumer workspace created: $($consumer.id)  $($consumer.displayName)"
