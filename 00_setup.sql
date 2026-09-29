-- Run once, before anything else: schema, volumes, and the reference objects the pipeline uses.

CREATE SCHEMA IF NOT EXISTS workspace.six_data;
CREATE VOLUME IF NOT EXISTS workspace.six_data.raw;   -- landing zone for source files
CREATE VOLUME IF NOT EXISTS workspace.six_data.checkpoints;   -- streaming checkpoints and schema locations

CREATE OR REPLACE TABLE workspace.six_data.map_event_type AS
SELECT * FROM VALUES
  ('DEPOSITARY', 'DVCA', 'DVCA'), ('DEPOSITARY', 'LIQU', 'LIQU'),
  ('ISSUER', 'CASH_DIV', 'DVCA'), ('ISSUER', 'LIQUIDATION', 'LIQU'),
  ('EXCHANGE', '10', 'DVCA')
AS t(source, source_code, caev);

CREATE OR REPLACE TABLE workspace.six_data.source_priority AS
SELECT * FROM VALUES ('DEPOSITARY', 1), ('ISSUER', 2), ('EXCHANGE', 3)
AS t(source, priority);

CREATE OR REPLACE FUNCTION workspace.six_data.is_valid_isin(isin STRING)
RETURNS BOOLEAN
LANGUAGE PYTHON
AS $$
if isin is None or len(isin) != 12 or not isin.isascii() or isin != isin.upper():
    return False
if not (isin[:2].isalpha() and isin[:11].isalnum() and isin[11].isdigit()):
    return False
digits = "".join(str(int(ch, 36)) for ch in isin[:11])
total = 0
for i, d in enumerate(reversed(digits)):
    n = int(d) * (2 if i % 2 == 0 else 1)
    total += n - 9 if n > 9 else n
return (10 - total % 10) % 10 == int(isin[11])
$$;
