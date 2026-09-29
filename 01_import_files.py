# Extract: pull the source files from GitHub into the raw volume
import urllib.request, os

GITHUB_RAW = "https://raw.githubusercontent.com/Theocrite2/six-trades-data/main"
BASE = "/Volumes/workspace/six_data/raw"

FILES = [
    "depositary/depo_20260925.mt564",
    "issuer/iss_20260925.csv",
    "exchange/exch_20260925.csv",
    "instruments/instruments_20260924.csv",
    "instruments/instruments_20260925.csv",
    "term_sheets/ts1_final_terms.pdf",
    "term_sheets/ts2_final_terms.pdf",
]

for rel in FILES:
    dest = f"{BASE}/{rel}"
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    urllib.request.urlretrieve(f"{GITHUB_RAW}/{rel}", dest)
