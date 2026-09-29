-- Term sheets: AI parsing and extraction, then rule checks and routing (accept or review).

-- Parse: two real PDF files (landed by L0), read straight from the volume, not a text string standing in for one.
-- ai_parse_document returns VARIANT. Navigating with `:` (e.g. :document:elements) stays VARIANT even where the
-- underlying value is a JSON array, so transform() rejects it with DATATYPE_MISMATCH.UNEXPECTED_INPUT_TYPE
-- ("requires the ARRAY type, however ... has the type VARIANT") until it's explicitly cast to ARRAY<VARIANT>.
-- The text itself lives in document.elements[].content, not document.pages: pages only carries {id, image_uri}.
-- Both confirmed by running it and inspecting the raw output (SELECT ai_parse_document(content) ... LIMIT 1),
-- not assumed; a first attempt at :document:pages / :representation:markdown returned empty ts_text (length 0)
-- because that path doesn't exist in the actual response shape.
CREATE OR REPLACE TABLE workspace.six_data.term_sheets AS
SELECT
  upper(regexp_extract(_metadata.file_path, '/(ts[0-9]+)_', 1)) AS ts_id,  -- ts1_final_terms.pdf -> TS1
  array_join(transform(
    CAST(ai_parse_document(content):document:elements AS ARRAY<VARIANT>),
    e -> CAST(e:content AS STRING)
  ), '\n') AS ts_text
FROM read_files('/Volumes/workspace/six_data/raw/term_sheets/', format => 'binaryFile');

-- element.content comes back HTML-ish (the Key Terms table as <table>...<td>), not plain markdown.
-- ai_extract reads markdown/HTML mixed text so this is passed through as-is, not stripped; if extraction
-- accuracy on a real document suffers because of the table markup, stripping tags first is the next thing to try.
CREATE OR REPLACE TABLE workspace.six_data.ts_extracted AS
SELECT ts_id,
       ai_extract(ts_text, array('isin', 'issuer', 'sspa_code', 'currency', 'coupon_pct_pa',
                                 'strike_pct', 'barrier_pct', 'initial_fixing_date',
                                 'final_fixing_date', 'redemption_date')) AS f
FROM workspace.six_data.term_sheets;

CREATE OR REPLACE TABLE workspace.six_data.ts_checked AS
WITH p AS (
  SELECT ts_id, f.isin AS isin, f.issuer AS issuer, f.sspa_code AS sspa_code, upper(f.currency) AS currency,
    try_cast(regexp_extract(replace(f.coupon_pct_pa, ',', '.'), '([0-9]+[.]?[0-9]*)', 1) AS DOUBLE) AS coupon_pct,
    try_cast(regexp_extract(replace(f.strike_pct, ',', '.'), '([0-9]+[.]?[0-9]*)', 1) AS DOUBLE) AS strike_pct,
    try_cast(regexp_extract(replace(f.barrier_pct, ',', '.'), '([0-9]+[.]?[0-9]*)', 1) AS DOUBLE) AS barrier_pct,
    to_date(coalesce(try_to_timestamp(f.initial_fixing_date, 'dd.MM.yyyy'),
                     try_to_timestamp(f.initial_fixing_date, 'yyyy-MM-dd'))) AS initial_fixing,
    to_date(coalesce(try_to_timestamp(f.final_fixing_date, 'dd.MM.yyyy'),
                     try_to_timestamp(f.final_fixing_date, 'yyyy-MM-dd'))) AS final_fixing,
    to_date(coalesce(try_to_timestamp(f.redemption_date, 'dd.MM.yyyy'),
                     try_to_timestamp(f.redemption_date, 'yyyy-MM-dd'))) AS redemption
  FROM workspace.six_data.ts_extracted
)
SELECT *,
  filter(array(
    CASE WHEN NOT coalesce(workspace.six_data.is_valid_isin(isin), false) THEN 'ISIN_INVALID' END,
    CASE WHEN currency IS NULL OR NOT currency RLIKE '^[A-Z]{3}$' THEN 'CCY_INVALID' END,
    CASE WHEN coupon_pct IS NULL OR coupon_pct <= 0 OR coupon_pct > 30 THEN 'COUPON_IMPLAUSIBLE' END,
    CASE WHEN barrier_pct IS NULL OR strike_pct IS NULL OR barrier_pct >= strike_pct THEN 'BARRIER_NOT_BELOW_STRIKE' END,
    CASE WHEN initial_fixing IS NULL OR final_fixing IS NULL OR redemption IS NULL
           OR NOT (initial_fixing < final_fixing AND final_fixing <= redemption) THEN 'DATES_MISSING_OR_ORDER' END
  ), x -> x IS NOT NULL) AS errors
FROM p;

-- Routing
SELECT ts_id, CASE WHEN size(errors) = 0 THEN 'AUTO_ACCEPT' ELSE 'REVIEW' END AS route, errors
FROM workspace.six_data.ts_checked;
