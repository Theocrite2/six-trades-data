-- Data-quality KPI after each pipeline run: straight-through rate and failures by rule.

CREATE TABLE IF NOT EXISTS workspace.six_data.dq_kpi (
  run_ts TIMESTAMP, records_in BIGINT, records_valid BIGINT,
  records_quarantined BIGINT, stp_pct DOUBLE, golden_events BIGINT);

INSERT INTO workspace.six_data.dq_kpi
SELECT current_timestamp(), count(*), count_if(size(errors) = 0), count_if(size(errors) > 0),
       round(100.0 * count_if(size(errors) = 0) / count(*), 2),
       (SELECT count(*) FROM workspace.six_data.gold_ca_event)
FROM workspace.six_data.ca_checked;

-- Quarantine breakdown by rule
SELECT err, count(*) AS n
FROM (SELECT explode(errors) AS err FROM workspace.six_data.ca_checked)
GROUP BY err
ORDER BY n DESC, err;
