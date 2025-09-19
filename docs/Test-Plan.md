
# Test Plan

## A. Access Isolation
- Consumer user cannot open Provider workspace.
- Consumer user can open shortcut and read only `MarketData` (no other Provider folders).

## B. SQL Layer
- RLS returns only allowed rows when querying `dbo.MarketData`.
- CLS/DDM hides masked columns as designed.

## C. Power BI
- Report respects RLS per user.
- Users without **Build** cannot create new artifacts from the model; without **Reshare** cannot grant others.

## D. Governance
- New items inherit default domain label; exports carry labels.
- DLP triggers alert/action on sensitive data in wrong domain.
- Audit logs show access, label edits, and exports.
