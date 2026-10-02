-- Monitoring: a dashboard page for the manager, a dashboard page for the analysts, the alert for the team.
-- Dashboard: in Dashboards, add each "Dataset" query below on the Data tab, then one widget per dataset.
-- Alert: in Alerts, use the alert query with the condition stp_pct < 80, scheduled after the job, email to the team.
-- Analyst page: the last two queries are the datasets of the dashboard's second page, "Analyst queue".

-- Dataset "kpi": three counters (straight-through rate, records in quarantine, golden records)
SELECT stp_pct, records_in, records_valid, records_quarantined, golden_events
FROM workspace.six_data.dq_kpi
ORDER BY run_ts DESC
LIMIT 1;

-- Dataset "failures_by_rule": bar chart, why records failed
SELECT err AS rule, count(*) AS records
FROM (SELECT explode(errors) AS err FROM workspace.six_data.ca_checked)
GROUP BY err
ORDER BY records DESC;

-- Dataset "source_conflicts": table, where the sources disagree
SELECT isin, inline(reported_values)
FROM workspace.six_data.ca_reconciliation
WHERE in_conflict;

-- Dataset "golden_with_lei": table, golden records with their LEI
SELECT g.isin, i.entity_name, g.caev, g.ex_date, g.gross_rate, g.currency, g.golden_source, i.lei
FROM workspace.six_data.gold_ca_event g
LEFT JOIN workspace.six_data.instrument_lei i ON i.isin = g.isin
ORDER BY g.ex_date;

-- Alert "Straight-through rate below 80%": condition stp_pct < 80
SELECT stp_pct
FROM workspace.six_data.dq_kpi
ORDER BY run_ts DESC
LIMIT 1;

-- Analyst page dataset: the quarantine queue, what failed and why
SELECT source, source_ref, isin, event_code, ex_date, errors, quarantined_at
FROM workspace.six_data.ca_quarantine
ORDER BY source, source_ref;

-- Analyst page dataset: events only one source reported
SELECT isin, caev, ex_date, collect_set(source) AS sources
FROM workspace.six_data.ca_valid
GROUP BY isin, caev, ex_date
HAVING count(DISTINCT source) < 2;
