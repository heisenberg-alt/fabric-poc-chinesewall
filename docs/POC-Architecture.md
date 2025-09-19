
# POC Architecture

**Goal:** enforce a data wall between two entities in a single Fabric tenant/capacity while allowing a controlled Provider → Consumer share.

## Logical View

- **Entity A (Provider)** workspace hosts Lakehouse/Warehouse with `dbo.MarketData`.
- **OneLake security** grants `Read` to only `Entity B MarketData Readers` on `Tables/MarketData`.
- **Internal OneLake shortcut** is created in **Entity B (Consumer)** workspace → `Tables/MarketDataShortcut`.
- **SQL RLS/CLS** further restricts row/column access as needed.
- **Power BI** model in Consumer applies RLS; Build/Reshare limited.
- **Purview** labels + DLP applied (default/mandatory labels recommended per domain).

## Identity & Authorization

1. Workspace roles → control-plane access to items.
2. OneLake security → data-plane access to folders/tables.
3. SQL RLS/CLS/DDM → row/column shaping.
4. Power BI RLS/OLS → model-level shaping for BI.

## Shortcuts & Identity Modes
- Internal OneLake→OneLake shortcuts use **passthrough identity**.
- If using SQL analytics endpoints, set mode to **User identity** to avoid owner delegation.
