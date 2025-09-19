
# Security Model

- **Workspace roles:** Admin/Member/Contributor/Viewer, scoped per entity workspace.
- **OneLake security:** Role-based (Read/ReadWrite) on Tables/Files paths.
- **SQL:** RLS via `CREATE SECURITY POLICY`; optional CLS and DDM for column masking.
- **Power BI:** RLS/OLS; tightly control **Build** and **Reshare**.
- **Purview:** Sensitivity labels with downstream inheritance; DLP to detect and restrict sensitive data exposure.
