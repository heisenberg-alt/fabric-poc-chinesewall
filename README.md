
# Microsoft Fabric POC – Data Segregation ("Chinese Wall")

This repository provides a **generic**, customer/industry‑neutral proof‑of‑concept to enforce a strict segregation of data and duties between two logical entities in a **single Microsoft Entra tenant and one Fabric capacity**.

## Key Capabilities
- Separate **workspaces** and **domains** for two entities (e.g., `Entity A` and `Entity B`).
- **OneLake security roles** to enforce data‑plane permissions at tables/folders.
- **Internal OneLake shortcut** (passthrough identity) to expose only a curated subset from Provider → Consumer.
- **SQL security**: Row‑Level Security (RLS) and optional Column‑Level Security (CLS)/Dynamic Data Masking (DDM).
- **Power BI** semantic model security (RLS/OLS) and restricted **Build/Reshare** to prevent cross‑entity reuse.
- **Microsoft Purview** sensitivity labels (with downstream inheritance) and **DLP** policy templates.

> This repo contains **scripts and templates** only. No customer data is included.

---

## Repository Structure

```
fabric-poc-chinesewall/
├── README.md
├── LICENSE
├── .gitignore
├── scripts/
│   ├── 01-create-workspaces.ps1
│   ├── 02-assign-workspace-roles.ps1
│   ├── 03-onelake-security-roles.json
│   ├── 04-configure-onelake-security.ps1
│   ├── 05-create-shortcut.ps1
│   ├── 06-sql-rls-cls.sql
│   ├── 06b-sql-ddm.sql
│   ├── 07-purview-labels-dlp.json
│   └── 09-validate.ps1
└── docs/
    ├── POC-Architecture.md
    ├── Security-Model.md
    ├── Governance-Checklist.md
    └── Test-Plan.md
```

---

## Prerequisites

- **Microsoft Fabric** enabled in your tenant and a capacity available.
- **PowerShell 7+**.
- Ability to obtain an **access token** for the Fabric/Power BI REST APIs (e.g., `Connect-PowerBIServiceAccount` or Azure CLI/Graph and set `ACCESS_TOKEN`).
- SQL connectivity to Fabric Warehouse or Lakehouse SQL endpoint (e.g., SSMS/Azure Data Studio).
- **Microsoft Purview** (Information Protection + DLP) available.

> ⚠️ This POC assumes two logical entities **Entity A** (Provider) and **Entity B** (Consumer). Replace placeholders accordingly.

---

## Quick Start

1. **Clone** and update placeholders in `scripts/*.ps1`, `scripts/*.json`, and `scripts/*.sql`.
2. **Create two workspaces** (Provider & Consumer) using `01-create-workspaces.ps1` and note their IDs.
3. **Assign workspace roles** to your Entra groups using `02-assign-workspace-roles.ps1`.
4. In the Provider workspace, create a **Lakehouse/Warehouse** and load a sample table `dbo.MarketData` (no PII).
5. Apply **OneLake security** with `04-configure-onelake-security.ps1` using `03-onelake-security-roles.json`.
6. From the Consumer workspace, **create an internal OneLake shortcut** to Provider’s `MarketData` using `05-create-shortcut.ps1`.
7. Apply **SQL RLS/CLS** on `dbo.MarketData` with `06-sql-rls-cls.sql` (optional `06b-sql-ddm.sql`).
8. Publish a **Power BI** semantic model in the Consumer workspace, set **RLS/OLS** and restrict **Build/Reshare**.
9. Import **Purview** label & **DLP** templates from `07-purview-labels-dlp.json` (adjust to your taxonomy).
10. Run **validation** via `docs/Test-Plan.md` and optional `09-validate.ps1`.

---

## References (Microsoft Learn)
- Fabric governance & domains: https://learn.microsoft.com/fabric/governance/ ; https://learn.microsoft.com/fabric/governance/domains
- Admin portal & tenant settings: https://learn.microsoft.com/fabric/admin/admin-center ; https://learn.microsoft.com/fabric/admin/about-tenant-settings
- OneLake shortcuts & security: https://learn.microsoft.com/fabric/onelake/onelake-shortcuts ; https://learn.microsoft.com/fabric/onelake/onelake-shortcut-security ; https://learn.microsoft.com/fabric/onelake/security/data-access-control-model
- Data warehousing security & RLS: https://learn.microsoft.com/fabric/data-warehouse/security ; https://learn.microsoft.com/sql/t-sql/statements/create-security-policy-transact-sql
- Power BI RLS/permissions: https://learn.microsoft.com/fabric/security/service-admin-row-level-security ; https://learn.microsoft.com/power-bi/connect-data/service-datasets-permissions ; https://learn.microsoft.com/power-bi/connect-data/service-datasets-build-permissions
- Purview labels/DLP for Fabric: https://learn.microsoft.com/fabric/governance/information-protection ; https://learn.microsoft.com/fabric/governance/service-security-sensitivity-label-downstream-inheritance ; https://learn.microsoft.com/microsoft-365/compliance/dlp-learn-about-dlp?view=o365-worldwide ; https://learn.microsoft.com/purview/dlp-data-loss-prevention

---

## Testing the POC

After deployment, validate that the POC works correctly using the provided test scripts.

### Prerequisites for Testing

1. **Set Access Token**: Obtain a valid access token for Fabric/Power BI API:
   ```powershell
   # Using Power BI PowerShell module
   Connect-PowerBIServiceAccount
   $token = (Get-PowerBIAccessToken).AccessToken
   $env:ACCESS_TOKEN = $token
   
   # OR using Azure CLI
   $token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv
   $env:ACCESS_TOKEN = $token
   ```

2. **Gather Required IDs**: You'll need:
   - Provider workspace ID
   - Consumer workspace ID  
   - Provider lakehouse/warehouse item ID
   - Consumer lakehouse/warehouse item ID
   - SQL connection string (for database tests)

### Quick Test Method

Use the comprehensive test runner with a configuration file:

1. **Create test configuration**:
   ```powershell
   cp scripts/test-config-sample.json scripts/test-config.json
   # Edit test-config.json with your actual IDs
   ```

2. **Run all tests**:
   ```powershell
   cd scripts
   .\Test-FabricPOC.ps1 -ConfigFile "test-config.json" -ExportResults -Verbose
   ```

### Individual Test Scripts

Run specific test categories:

1. **Connectivity Tests** - Basic API access and workspace connectivity:
   ```powershell
   .\Test-Connectivity.ps1 -ProviderWorkspaceId "your-provider-id" -ConsumerWorkspaceId "your-consumer-id" -TestEndpoints
   ```

2. **Security Tests** - Workspace isolation, OneLake security, RLS/CLS:
   ```powershell
   .\Test-Security.ps1 -ProviderWorkspaceId "your-provider-id" -ConsumerWorkspaceId "your-consumer-id" -SqlConnectionString "your-sql-connection"
   ```

3. **Comprehensive Validation** - All POC components:
   ```powershell
   .\09-validate.ps1 -ProviderWorkspaceId "your-provider-id" -ConsumerWorkspaceId "your-consumer-id" -ProviderLakehouseItemId "your-provider-item" -ConsumerLakehouseItemId "your-consumer-item" -SqlConnectionString "your-sql-connection" -Verbose
   ```

### Manual Test Scenarios

Beyond automated tests, manually verify these scenarios:

#### A. Workspace Isolation
- **Test**: Consumer user attempts to access Provider workspace directly
- **Expected**: Access denied, workspace not visible
- **Validation**: Log in as Entity B user, check workspace list

#### B. OneLake Data Access
- **Test**: Consumer user accesses MarketData via shortcut
- **Expected**: Can read shortcut data, cannot access other Provider folders
- **Validation**: Browse Consumer lakehouse, verify shortcut works but other paths are inaccessible

#### C. SQL Row-Level Security
- **Test**: Query MarketData table as different users
- **Expected**: Each user sees only their authorized data rows
- **Validation**: 
   ```sql
   -- Connect as Entity A user
   SELECT DISTINCT EntityId FROM dbo.MarketData; -- Should see only Entity A data
   
   -- Connect as Entity B user  
   SELECT DISTINCT EntityId FROM dbo.MarketData; -- Should see only Entity B data
   ```

#### D. Power BI Semantic Model Security
- **Test**: Attempt to create new reports from Consumer workspace dataset
- **Expected**: Users without Build permission cannot create new artifacts
- **Validation**: Try "Analyze in Excel" or "Create Report" - should be restricted

#### E. Data Export Controls
- **Test**: Export data from Power BI report or Fabric notebook
- **Expected**: Purview labels applied, DLP policies triggered if configured
- **Validation**: Check audit logs for export events and policy actions

### Expected Test Results

**Successful POC should show**:
- ✅ All connectivity tests pass
- ✅ Workspace isolation confirmed (no cross-entity access)
- ✅ OneLake security roles properly configured
- ✅ Shortcuts working with limited scope
- ✅ RLS filtering data by entity
- ✅ Power BI permissions properly restricted
- ✅ No users with excessive cross-workspace access

**Common Issues**:
- ❌ Missing OneLake security roles → Unrestricted data access
- ❌ No RLS policy → All users see all data
- ❌ Overly permissive workspace roles → Cross-entity access
- ❌ Missing Power BI dataset permissions → Unrestricted report creation

### Test Result Files

Test scripts generate detailed reports:
- `connectivity-test-results-YYYYMMDD-HHMMSS.json` - API and workspace connectivity
- `security-test-results-YYYYMMDD-HHMMSS.json` - Security controls validation  
- `test-results-YYYYMMDD-HHMMSS.json` - Comprehensive validation results
- `fabric-poc-test-report-YYYYMMDD-HHMMSS.json` - Full test execution summary

Review these files for detailed findings and recommendations.

---

## License
This project is licensed under the MIT License – see [LICENSE](LICENSE).


## One-command setup (interactive)

```bash
chmod +x scripts/setup-poc.sh
./scripts/setup-poc.sh
```
This will prompt for workspace IDs, item IDs and Entra group object IDs, then update the templates in-place.


## Full runner (interactive with Azure CLI)
```bash
chmod +x scripts/run-all.sh
./scripts/run-all.sh
```
This will:
1) Prompt for workspace/item/group IDs
2) Acquire an access token via `az account get-access-token`
3) Update templates and run role assignment, OneLake security, and shortcut creation.
2) Acquire an access token via `az account get-access-token`
3) Update templates and run role assignment, OneLake security, and shortcut creation.
```
