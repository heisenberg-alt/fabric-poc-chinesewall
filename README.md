
# Microsoft Fabric POC – Data Segregation ("Chinese Wall")

This repository provides a **generic**, customer‑neutral proof‑of‑concept to enforce a strict segregation of data and duties between two logical entities in a **single Microsoft Entra tenant and one Fabric capacity**.

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
```
