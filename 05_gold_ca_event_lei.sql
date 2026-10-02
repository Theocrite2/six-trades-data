-- Golden record joined with its LEI and legal name. Runs after the LEI lookup.
-- A left join: an event without an LEI (the ETF) stays, with entity_name and lei empty.

CREATE OR REPLACE TABLE workspace.six_data.gold_ca_event_lei AS
SELECT g.*, i.entity_name, i.lei
FROM workspace.six_data.gold_ca_event g
LEFT JOIN workspace.six_data.instrument_lei i ON i.isin = g.isin;
