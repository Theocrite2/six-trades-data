-- Lakeflow declarative pipeline source (catalog: workspace, schema: six_data).

-- Bronze: one streaming table per source, incremental file ingestion (Auto Loader underneath)

CREATE OR REFRESH STREAMING TABLE bronze_ca_depositary
AS SELECT
  -- CRLF normalised to LF first: a Windows-edited or git-autocrlf'd MT564 file uses \r\n,
  -- and the separator pattern below would otherwise never match, collapsing every message
  -- in the file into a single unsplit block.
  explode(filter(split(regexp_replace(value, '\\r\\n', '\\n'), '\\n-\\n'), b -> trim(b) != '')) AS block,
  _metadata.file_path AS _source_file, current_timestamp() AS _ingest_ts
FROM STREAM read_files(
  '/Volumes/workspace/six_data/raw/depositary/',
  format => 'text', wholetext => true);

CREATE OR REFRESH STREAMING TABLE bronze_ca_issuer
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingest_ts
FROM STREAM read_files(
  '/Volumes/workspace/six_data/raw/issuer/',
  format => 'csv', header => true, sep => ';',
  schema => 'source_ref STRING, isin STRING, event_code STRING, ex_date STRING, record_date STRING,
             pay_date STRING, gross_rate STRING, currency STRING, received_ts STRING');

CREATE OR REFRESH STREAMING TABLE bronze_ca_exchange
AS SELECT *, _metadata.file_path AS _source_file, current_timestamp() AS _ingest_ts
FROM STREAM read_files(
  '/Volumes/workspace/six_data/raw/exchange/',
  format => 'csv', header => true, sep => ',',
  schema => 'source_ref STRING, isin STRING, event_code STRING, ex_date STRING, record_date STRING,
             pay_date STRING, gross_rate STRING, currency STRING, received_ts STRING');

-- Silver: one target table, fed by three named flows, one per source, each doing its own parsing/typing
CREATE OR REFRESH STREAMING TABLE silver_ca;

CREATE FLOW silver_ca_from_depositary AS INSERT INTO silver_ca BY NAME
SELECT
  'DEPOSITARY' AS source,
  regexp_extract(block, ':20C::CORP//(\\S+)', 1) AS source_ref,
  upper(regexp_extract(block, ':35B:ISIN (\\S+)', 1)) AS isin,
  regexp_extract(block, ':22F::CAEV//(\\S+)', 1) AS event_code,
  to_date(regexp_extract(block, ':98A::XDTE//(\\d{8})', 1), 'yyyyMMdd') AS ex_date,
  to_date(regexp_extract(block, ':98A::RDTE//(\\d{8})', 1), 'yyyyMMdd') AS record_date,
  to_date(regexp_extract(block, ':98A::PAYD//(\\d{8})', 1), 'yyyyMMdd') AS pay_date,
  try_cast(replace(regexp_extract(block, ':92F::GRSS//[A-Z]{3}([0-9,\\.]+)', 1), ',', '.') AS DECIMAL(18,6)) AS gross_rate,
  regexp_extract(block, ':92F::GRSS//([A-Z]{3})', 1) AS currency,
  _ingest_ts AS received_ts
FROM STREAM(bronze_ca_depositary);

CREATE FLOW silver_ca_from_issuer AS INSERT INTO silver_ca BY NAME
SELECT
  'ISSUER' AS source, trim(source_ref) AS source_ref, upper(trim(isin)) AS isin, trim(event_code) AS event_code,
  to_date(try_to_timestamp(ex_date, 'dd/MM/yyyy')) AS ex_date,
  to_date(try_to_timestamp(record_date, 'dd/MM/yyyy')) AS record_date,
  to_date(try_to_timestamp(pay_date, 'dd/MM/yyyy')) AS pay_date,
  try_cast(replace(gross_rate, ',', '.') AS DECIMAL(18,6)) AS gross_rate,
  upper(trim(currency)) AS currency,
  try_to_timestamp(received_ts) AS received_ts
FROM STREAM(bronze_ca_issuer);

CREATE FLOW silver_ca_from_exchange AS INSERT INTO silver_ca BY NAME
SELECT
  'EXCHANGE' AS source, trim(source_ref) AS source_ref, upper(trim(isin)) AS isin, trim(event_code) AS event_code,
  to_date(try_to_timestamp(ex_date, 'yyyyMMdd')) AS ex_date,
  to_date(try_to_timestamp(record_date, 'yyyyMMdd')) AS record_date,
  to_date(try_to_timestamp(pay_date, 'yyyyMMdd')) AS pay_date,
  try_cast(replace(gross_rate, ',', '.') AS DECIMAL(18,6)) AS gross_rate,
  upper(trim(currency)) AS currency,
  try_to_timestamp(received_ts) AS received_ts
FROM STREAM(bronze_ca_exchange);

-- Validation + quarantine: a materialized view, not a streaming table, because the QUALIFY dedupe
-- (latest version per source_ref) needs a full recompute each refresh, not a once-per-row pass.
CREATE OR REFRESH MATERIALIZED VIEW ca_checked AS
WITH latest AS (
  SELECT * FROM silver_ca
  QUALIFY row_number() OVER (PARTITION BY source, source_ref ORDER BY received_ts DESC) = 1
)
SELECT l.*, m.caev, p.priority,
  filter(array(
    CASE WHEN NOT workspace.six_data.is_valid_isin(l.isin) THEN 'ISIN_INVALID' END,
    CASE WHEN m.caev IS NULL THEN 'UNMAPPED_EVENT' END,
    CASE WHEN l.ex_date IS NULL OR l.record_date IS NULL OR l.pay_date IS NULL THEN 'DATE_MISSING' END,
    CASE WHEN l.record_date < l.ex_date OR l.pay_date < l.record_date THEN 'DATE_ORDER' END,
    CASE WHEN dayofweek(l.ex_date) IN (1, 7) THEN 'EX_DATE_WEEKEND' END,
    CASE WHEN m.caev IN ('DVCA', 'LIQU') AND coalesce(l.gross_rate, 0) <= 0 THEN 'RATE_INVALID' END,
    CASE WHEN NOT coalesce(l.currency RLIKE '^[A-Z]{3}$', false) THEN 'CCY_INVALID' END
  ), x -> x IS NOT NULL) AS errors
FROM latest l
LEFT JOIN workspace.six_data.map_event_type m ON m.source = l.source AND m.source_code = l.event_code
LEFT JOIN workspace.six_data.source_priority p ON p.source = l.source;

CREATE OR REFRESH MATERIALIZED VIEW ca_valid AS
SELECT * FROM ca_checked WHERE size(errors) = 0;

CREATE OR REFRESH MATERIALIZED VIEW ca_quarantine AS
SELECT *, current_timestamp() AS quarantined_at FROM ca_checked WHERE size(errors) > 0;

-- Gold: golden record by source priority, then recency. A materialized view, same reasoning as ca_checked:
-- QUALIFY needs a full recompute, this isn't an incremental append.
CREATE OR REFRESH MATERIALIZED VIEW gold_ca_event AS
SELECT isin, caev, ex_date, record_date, pay_date, gross_rate, currency,
       source AS golden_source, source_ref
FROM ca_valid
QUALIFY row_number() OVER (PARTITION BY isin, caev, ex_date ORDER BY priority, received_ts DESC) = 1;

-- What each source actually reported, for the conflict report / walkthrough
CREATE OR REFRESH MATERIALIZED VIEW ca_reconciliation AS
SELECT isin, caev, ex_date,
       collect_list(named_struct('source', source, 'gross_rate', gross_rate, 'currency', currency)) AS reported_values,
       count(DISTINCT gross_rate) > 1 AS in_conflict
FROM ca_valid
GROUP BY isin, caev, ex_date;
