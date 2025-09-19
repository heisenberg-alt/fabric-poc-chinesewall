
/* Apply Row-Level Security (RLS) on dbo.MarketData */
CREATE SCHEMA sec;
GO

CREATE FUNCTION sec.fnLimitToEntity(@EntityCode nvarchar(20))
RETURNS TABLE WITH SCHEMABINDING AS
RETURN SELECT 1 AS fn_result
WHERE @EntityCode = SESSION_CONTEXT(N'EntityCode');
GO

CREATE SECURITY POLICY sec.EntityRLS
ADD FILTER PREDICATE sec.fnLimitToEntity(EntityCode)
ON dbo.MarketData
WITH (STATE = ON);
GO

/* Optional: Column-Level Security via DENY/GRANT */
-- Example to hide Salary column from a role
-- CREATE ROLE rl_NoSensitiveCols;
-- DENY SELECT ON OBJECT::dbo.MarketData(Salary) TO rl_NoSensitiveCols;
