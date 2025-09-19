
#!/usr/bin/env bash
# setup-poc.sh
# Interactive script to configure Fabric POC placeholders dynamically.
# Works on macOS/Linux with BSD/GNU sed. Creates .bak backups.

set -euo pipefail

banner(){ echo "
=== Microsoft Fabric POC Setup ===
$1
"; }

banner "This script updates placeholders in PowerShell and JSON templates."

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

banner "Updating placeholders..."

# Workspace role assignments
sed -i.bak "s/REPLACE-ENTITYA-ADMINS-OBJECTID/${ENTITYA_ADMINS}/g" scripts/02-assign-workspace-roles.ps1
sed -i.bak "s/REPLACE-ENTITYA-ENGINEERS-OBJECTID/${ENTITYA_ENGINEERS}/g" scripts/02-assign-workspace-roles.ps1
sed -i.bak "s/REPLACE-ENTITYA-ANALYSTS-OBJECTID/${ENTITYA_ANALYSTS}/g" scripts/02-assign-workspace-roles.ps1
sed -i.bak "s/REPLACE-ENTITYB-ADMINS-OBJECTID/${ENTITYB_ADMINS}/g" scripts/02-assign-workspace-roles.ps1
sed -i.bak "s/REPLACE-ENTITYB-ENGINEERS-OBJECTID/${ENTITYB_ENGINEERS}/g" scripts/02-assign-workspace-roles.ps1
sed -i.bak "s/REPLACE-ENTITYB-ANALYSTS-OBJECTID/${ENTITYB_ANALYSTS}/g" scripts/02-assign-workspace-roles.ps1

# OneLake security JSON
sed -i.bak "s/REPLACE-ENTITYB-MarketData-READERS-OBJECTID/${ENTITYB_READERS}/g" scripts/03-onelake-security-roles.json

# OneLake security PS (apply workspace/item ids)
sed -i.bak "s/<REPLACE>/${PROVIDER_WS}/" scripts/04-configure-onelake-security.ps1
sed -i.bak "s/<REPLACE>/${PROVIDER_ITEM}/" scripts/04-configure-onelake-security.ps1

# Shortcut PS (insert provider/consumer identifiers where executed)
# These are provided at run-time via parameters, so we don't replace inside the file.

banner "Placeholders updated successfully!"
echo "Next steps:"
echo " 1) Ensure $ACCESS_TOKEN is set (see README)."
echo " 2) Run scripts/02-assign-workspace-roles.ps1"
echo " 3) Run scripts/04-configure-onelake-security.ps1"
echo " 4) Run scripts/05-create-shortcut.ps1"
