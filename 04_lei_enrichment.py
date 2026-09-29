# LEI lookup from GLEIF's public API (no key needed), by ISIN, for every instrument in gold_ca_event.

import time
import requests

GLEIF_BASE = "https://api.gleif.org/api/v1/lei-records"
RETRYABLE = {429, 500, 502, 503, 504}

def gleif_lookup_by_isin(isin, session, max_retries=3):
    for attempt in range(max_retries):
        r = session.get(GLEIF_BASE, params={"filter[isin]": isin}, timeout=15)
        if r.status_code in RETRYABLE:
            time.sleep(2 ** attempt)
            continue
        r.raise_for_status()
        data = r.json().get("data", [])
        break
    else:
        data = []
    if data:
        rec = data[0]
        return {"isin": isin, "lei": rec["attributes"]["lei"],
                "entity_name": rec["attributes"]["entity"]["legalName"]["name"],
                "match_count": len(data)}
    return {"isin": isin, "lei": None, "entity_name": None, "match_count": 0}

isins = [r["isin"] for r in spark.sql(
    "SELECT DISTINCT isin FROM workspace.six_data.gold_ca_event").collect()]

with requests.Session() as s:
    results = [gleif_lookup_by_isin(i, s) for i in isins]

spark.createDataFrame(results).write.mode("overwrite").saveAsTable("workspace.six_data.instrument_lei")
