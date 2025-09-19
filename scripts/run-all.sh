
#!/usr/bin/env bash
# run-all.sh
# Full runner: collects inputs, acquires token via Azure CLI, updates placeholders, and executes key steps.
# Requires: Azure CLI (az), PowerShell 7+ (pwsh), sed

set -euo pipefail

info(){ echo -e "[1;34m[INFO][0m $*"; }
err(){ echo -e "[1;31m[ERROR][0m $*" 1>&2; }

# --- Checks ---
command -v az >/dev/null 2>&1 || { err "Azure CLI (az) is required. Install from https://aka.ms/azcli"; exit 1; }
command -v pwsh >/dev/null 2>&1 || { err "PowerShell 7+ (pwsh) is required. Install from https://aka.ms/pwsh"; exit 1; }

# --- Inputs ---
read -p "Enter Provider Workspace ID: " PROVIDER_WS
read -p "Enter Consumer Workspace ID: " CONSUMER_WS
read -p "Enter Provider Lakehouse/Warehouse Item ID: " PROVIDER_ITEM
read -p "Enter Consumer Lakehouse/Warehouse Item ID: " CONSUMER_ITEM
read -p "Enter Entra Group Object ID for Entity A Admins: " ENTITYA_ADMINS
read -p "Enter Entra Group Object ID for Entity A Engineers: " ENTITYA_ENGINEERS
read -p "Enter Entra Group Object ID for Entity A Analysts: " ENTITYA_ANALYSTS
read -p "Enter Entra Group Object ID for Entity B Admins: " ENTITYB_ADMINS
read -p "Enter Entra Group Object ID for Entity B Engineers: " ENTITYB_ENGINEERS
read -p "Enter Entra Group Object ID for Entity B Analysts: " ENTITYB_ANALYSTS
read -p "Enter Entra Group Object ID for Entity B MarketData Readers: " ENTITYB_READERS

# --- Token acquisition ---
get_token(){
  local resource="$1"
  az account get-access-token --resource "$resource" --query accessToken -o tsv 2>/dev/null || true
}

info "Acquiring access token via Azure CLI..."
TOKEN="$(get_token https://api.fabric.microsoft.com)"
if [ -z "$TOKEN" ]; then
  info "Retrying with Power BI resource audience..."
  TOKEN="$(get_token https://analysis.windows.net/powerbi/api)"
fi
if [ -z "$TOKEN" ]; then
  err "Failed to obtain an access token. Run 'az login' and try again, or export ACCESS_TOKEN manually."
  exit 1
fi
export ACCESS_TOKEN="$TOKEN"
info "Access token acquired and exported to ACCESS_TOKEN."

# --- Update placeholders (same as setup-poc.sh) ---
info "Updating placeholders in templates..."
sed -i.bak "s/REPLACE-ENTITYA-ADMINS-OBJECTID/${ENTITYA_ADMINS}/g" scripts/02-assign-workspace-roles.ps1
sed -i.bak "s/REPLACE-ENTITYA-ENGINEERS-OBJECTID/${ENTITYA_ENGINEERS}/g" scripts/02-assign-workspace-roles.ps1
sed -i.bak "s/REPLACE-ENTITYA-ANALYSTS-OBJECTID/${ENTITYA_ANALYSTS}/g" scripts/02-assign-workspace-roles.ps1
sed -i.bak "s/REPLACE-ENTITYB-ADMINS-OBJECTID/${ENTITYB_ADMINS}/g" scripts/02-assign-workspace-roles.ps1
sed -i.bak "s/REPLACE-ENTITYB-ENGINEERS-OBJECTID/${ENTITYB_ENGINEERS}/g" scripts/02-assign-workspace-roles.ps1
sed -i.bak "s/REPLACE-ENTITYB-ANALYSTS-OBJECTID/${ENTITYB_ANALYSTS}/g" scripts/02-assign-workspace-roles.ps1

sed -i.bak "s/REPLACE-ENTITYB-MarketData-READERS-OBJECTID/${ENTITYB_READERS}/g" scripts/03-onelake-security-roles.json

# Apply workspace/item ids for OneLake security PS (it expects placeholders)
sed -i.bak "s/<REPLACE>/${PROVIDER_WS}/" scripts/04-configure-onelake-security.ps1
sed -i.bak "s/<REPLACE>/${PROVIDER_ITEM}/" scripts/04-configure-onelake-security.ps1

info "Placeholders updated."

# --- Execute steps ---
info "Assigning workspace roles..."
pwsh -NoProfile -File scripts/02-assign-workspace-roles.ps1 -ProviderWorkspaceId "$PROVIDER_WS" -ConsumerWorkspaceId "$CONSUMER_WS"

info "Applying OneLake security on Provider item..."
pwsh -NoProfile -File scripts/04-configure-onelake-security.ps1 -WorkspaceId "$PROVIDER_WS" -ItemId "$PROVIDER_ITEM"

info "Creating internal OneLake shortcut in Consumer workspace..."
pwsh -NoProfile -File scripts/05-create-shortcut.ps1   -ConsumerWorkspaceId "$CONSUMER_WS"   -ConsumerLakehouseItemId "$CONSUMER_ITEM"   -ProviderWorkspaceId "$PROVIDER_WS"   -ProviderLakehouseItemId "$PROVIDER_ITEM"   -ShortcutName "MarketDataShortcut"

info "Done. Next steps:"
echo " - Run SQL RLS/CLS: scripts/06-sql-rls-cls.sql against the Provider Warehouse/Lakehouse SQL endpoint."
echo " - Set Power BI RLS/OLS and restrict Build/Reshare on the Consumer semantic model."
echo " - Import Purview templates (scripts/07-purview-labels-dlp.json) and enable DLP/labels per README."
