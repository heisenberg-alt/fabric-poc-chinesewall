
/* Dynamic Data Masking examples (optional) */
ALTER TABLE dbo.MarketData
ALTER COLUMN PIINumber ADD MASKED WITH (FUNCTION = 'partial(0,"***-***-",4)');

-- Note: DDM is a convenience obfuscation and does not replace RLS.
