-- Golden record joined with its LEI. Runs after both the pipeline and the LEI lookup.

CREATE OR REPLACE TABLE workspace.six_data.gold_ca_event_lei AS
SELECT g.isin, g.caev, g.ex_date, i.entity_name, i.lei
FROM workspace.six_data.gold_ca_event g
LEFT JOIN workspace.six_data.instrument_lei i ON i.isin = g.isin;
