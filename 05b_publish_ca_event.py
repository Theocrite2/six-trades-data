# Publish: merge the golden records with their LEI into published_ca_event, the table other systems read.
# Runs last in the job, after the KPI and the LEI join. A new event is inserted; an existing event is
# updated only if its rate, pay date or LEI changed; nothing is deleted. Reruns change nothing, and every
# change is a new version of the table (DESCRIBE HISTORY).

from delta.tables import DeltaTable

spark.sql("""CREATE TABLE IF NOT EXISTS workspace.six_data.published_ca_event
             AS SELECT * FROM workspace.six_data.gold_ca_event_lei WHERE 1 = 0""")

src = spark.table("workspace.six_data.gold_ca_event_lei")
tgt = DeltaTable.forName(spark, "workspace.six_data.published_ca_event")
(tgt.alias("t").merge(src.alias("s"), "t.isin = s.isin AND t.caev = s.caev AND t.ex_date = s.ex_date")
    .whenMatchedUpdateAll(condition="NOT (t.gross_rate <=> s.gross_rate) OR NOT (t.pay_date <=> s.pay_date) OR NOT (t.lei <=> s.lei)")
    .whenNotMatchedInsertAll()
    .execute())
