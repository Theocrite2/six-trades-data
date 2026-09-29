# Term sheet review card: a visual view over ts_checked (L9), for demo and review.
# Not part of the pipeline: it reads ts_checked and the source PDFs, writes nothing.
# Needs pymupdf in the notebook environment (Environment panel > Dependencies > pymupdf > Apply).
import base64
import contextlib
import html
import io

try:
    import pymupdf
except ImportError:
    pymupdf = None

TS_DIR = "/Volumes/workspace/six_data/raw/term_sheets"
GREEN, RED = "#1a7f37", "#cf222e"
SSPA = {"1230": "Barrier Reverse Convertible", "1260": "Express Certificate", "1300": "Tracker Certificate",
        "1320": "Bonus Certificate", "2100": "Warrant", "2210": "Mini-Future", "2300": "Constant Leverage Certificate"}


def pct(v):
    return f"{v:g}%"


def day(d):
    return d.strftime("%d %b %Y")


def product(code):
    if code is None:
        return None
    digits = "".join(ch for ch in str(code) if ch.isdigit())
    return SSPA.get(digits) or (f"SSPA {digits}" if digits else str(code))


# ts_checked column, label on the card, row label in the term sheet, display format
FIELDS = [
    ("issuer", "Issuer", "Issuer", str),
    ("isin", "ISIN", "ISIN", str),
    ("sspa_code", "Product type", "Product type", product),
    ("currency", "Currency", "Currency", str),
    ("coupon_pct", "Coupon", "Coupon", lambda v: f"{v:.2f}% p.a."),
    ("strike_pct", "Strike", "Strike", pct),
    ("barrier_pct", "Barrier", "Barrier", pct),
    ("initial_fixing", "Initial fixing", "Initial fixing", day),
    ("final_fixing", "Final fixing", "Final fixing", day),
    ("redemption", "Redemption", "Redemption", day),
]


def checks(r):
    """One line per rule in ts_checked: (passed, fields it flags, plain-English sentence)."""
    e = set(r["errors"] or [])
    b, s, c = r["barrier_pct"], r["strike_pct"], r["coupon_pct"]
    return [
        ("ISIN_INVALID" not in e, ["isin"],
         "ISIN check digit is valid" if "ISIN_INVALID" not in e else "ISIN missing or check digit wrong"),
        ("CCY_INVALID" not in e, ["currency"],
         f"{r['currency']} is a valid currency code" if "CCY_INVALID" not in e else "Currency missing or not a valid code"),
        ("COUPON_IMPLAUSIBLE" not in e, ["coupon_pct"],
         f"Coupon {c:.2f}% p.a. is within the plausible 0 to 30% range" if "COUPON_IMPLAUSIBLE" not in e
         else "Coupon missing or outside the plausible 0 to 30% range"),
        ("BARRIER_NOT_BELOW_STRIKE" not in e, ["barrier_pct"],
         f"Barrier {pct(b)} is below the strike {pct(s)}" if "BARRIER_NOT_BELOW_STRIKE" not in e
         else (f"Barrier {pct(b)} is not below the strike {pct(s)}" if b is not None and s is not None
               else "Barrier or strike not found")),
        ("DATES_MISSING_OR_ORDER" not in e, ["initial_fixing", "final_fixing", "redemption"],
         "Dates in order: initial fixing, final fixing, redemption" if "DATES_MISSING_OR_ORDER" not in e
         else "Dates missing or in the wrong order"),
    ]


def pdf_image(ts_id, flagged):
    """First page of the source PDF, Key Terms rows tinted: green = read and verified, red = failed a check."""
    if pymupdf is None:
        return None
    with open(f"{TS_DIR}/{ts_id.lower()}_final_terms.pdf", "rb") as f:
        doc = pymupdf.open(stream=f.read(), filetype="pdf")
    page = doc[0]
    with contextlib.redirect_stdout(io.StringIO()):  # silences PyMuPDF's layout-package notice
        tables = page.find_tables().tables
    if not tables:  # different layout: show the page as is
        png = page.get_pixmap(dpi=110).tobytes("png")
        return base64.b64encode(png).decode()
    table = tables[0]
    for row, cells in zip(table.rows, table.extract()):
        label = (cells[0] or "").strip().lower()
        for col, _, row_label, _ in FIELDS:
            if label.startswith(row_label.lower()):
                bad = col in flagged
                page.draw_rect(pymupdf.Rect(row.bbox), width=2.2 if bad else 0,
                               color=(0.81, 0.13, 0.18) if bad else None,
                               fill=(0.81, 0.13, 0.18) if bad else (0.10, 0.50, 0.22),
                               fill_opacity=0.22 if bad else 0.13)
    clip = pymupdf.Rect(40, 50, page.rect.width - 40, table.bbox[3] + 14)
    png = page.get_pixmap(dpi=130, clip=clip).tobytes("png")
    return base64.b64encode(png).decode()


def card(r):
    lines = checks(r)
    failed = [ln for ln in lines if not ln[0]]
    flagged = {col for ok, cols, _ in lines if not ok for col in cols}
    ok = not failed
    esc = html.escape

    fields = "".join(
        f'<div class="k">{label}</div>'
        f'<div class="v{" flag" if col in flagged else ""}">'
        f'{esc(fmt(r[col])) if r[col] is not None else "not found"}</div>'
        for col, label, _, fmt in FIELDS)
    rules = "".join(
        f'<li class="{"ok" if passed else "bad"}"><span class="ic">{"&#10003;" if passed else "&#10007;"}</span>'
        f'<span>{esc(text)}</span></li>'
        for passed, _, text in lines)
    img = pdf_image(r["ts_id"], flagged)
    pdf = (f'<img src="data:image/png;base64,{img}" alt="Term sheet">' if img
           else '<div class="noimg">Install PyMuPDF (%pip install pymupdf) to show the document here</div>')
    verdict = "Accepted automatically" if ok else "Sent to analyst review"
    detail = f"All {len(lines)} checks passed" if ok else f"{len(failed)} of {len(lines)} checks failed"
    title = product(r["sspa_code"]) or "Structured product"

    return f"""
<div class="card {'ok' if ok else 'bad'}">
  <div class="head">
    <div><div class="t">{esc(title)}</div>
      <div class="s">{esc(r['isin'] or 'ISIN not found')} &middot; {esc(r['ts_id'].lower())}_final_terms.pdf</div></div>
    <div class="verdict"><div class="pill">{verdict}</div><div class="s">{detail}</div></div>
  </div>
  <div class="body">
    <div class="pdf">{pdf}
      <div class="legend"><span class="sw g"></span>read by AI, verified <span class="sw r"></span>failed a check</div></div>
    <div>
      <div class="sec">Read from the PDF by AI</div>
      <div class="fields">{fields}</div>
      <div class="sec">Checked by rules</div>
      <ul class="checks">{rules}</ul>
    </div>
  </div>
</div>"""


CSS = f"""
.wrap {{ background:#f3f5f8; padding:24px; color:#1f2328;
        font-family:-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }}
.h1 {{ font-size:22px; font-weight:700; }}
.sub {{ font-size:14px; color:#57606a; margin-top:4px; }}
.tiles {{ display:flex; gap:12px; margin:16px 0 20px; flex-wrap:wrap; }}
.tile {{ background:#fff; border-radius:12px; padding:12px 18px; min-width:170px; box-shadow:0 1px 3px rgba(0,0,0,.08); }}
.tile .n {{ font-size:30px; font-weight:700; }}
.tile .l {{ font-size:13px; color:#57606a; }}
.tile.ok .n {{ color:{GREEN}; }} .tile.bad .n {{ color:{RED}; }}
.card {{ background:#fff; border-radius:14px; box-shadow:0 2px 8px rgba(0,0,0,.08); margin-bottom:22px;
        overflow:hidden; border-left:8px solid var(--c); }}
.card.ok {{ --c:{GREEN}; --bg:#dafbe1; }} .card.bad {{ --c:{RED}; --bg:#ffebe9; }}
.head {{ display:flex; justify-content:space-between; align-items:center; gap:16px;
        padding:16px 20px; border-bottom:1px solid #eaeef2; background:linear-gradient(90deg,var(--bg),#fff 60%); }}
.head .t {{ font-size:19px; font-weight:700; }}
.s {{ font-size:13px; color:#57606a; margin-top:2px; }}
.verdict {{ text-align:right; }}
.pill {{ display:inline-block; padding:8px 16px; border-radius:999px; font-weight:700; font-size:15px;
        color:#fff; background:var(--c); }}
.body {{ display:grid; grid-template-columns:1.15fr 1fr; gap:22px; padding:18px 20px 20px; }}
.pdf img {{ width:100%; border:1px solid #d0d7de; border-radius:8px; display:block; }}
.noimg {{ border:1px dashed #d0d7de; border-radius:8px; padding:40px 16px; color:#57606a; font-size:13px; text-align:center; }}
.legend {{ font-size:12px; color:#57606a; margin-top:8px; display:flex; align-items:center; gap:6px; }}
.sw {{ width:12px; height:12px; border-radius:3px; display:inline-block; margin-left:8px; }}
.sw.g {{ background:rgba(26,127,55,.25); margin-left:0; }} .sw.r {{ background:rgba(207,34,46,.45); }}
.sec {{ font-size:12px; font-weight:700; letter-spacing:.06em; text-transform:uppercase; color:#57606a; margin:2px 0 10px; }}
.fields {{ display:grid; grid-template-columns:auto 1fr; gap:7px 16px; font-size:14px; margin-bottom:20px; }}
.fields .k {{ color:#57606a; }}
.fields .v {{ font-weight:600; justify-self:start; }}
.fields .v.flag {{ color:{RED}; background:#ffebe9; border-radius:5px; padding:0 8px; }}
.checks {{ list-style:none; margin:0; padding:0; }}
.checks li {{ display:flex; gap:10px; align-items:center; font-size:14px; padding:7px 0; border-top:1px solid #f0f2f4; }}
.checks li.bad {{ color:{RED}; font-weight:700; }}
.ic {{ flex:none; width:22px; height:22px; border-radius:50%; color:#fff; font-size:13px; font-weight:700;
      display:flex; align-items:center; justify-content:center; }}
li.ok .ic {{ background:{GREEN}; }} li.bad .ic {{ background:{RED}; }}
"""


def review_page(rows):
    n_ok = sum(1 for r in rows if not r["errors"])
    tiles = (f'<div class="tile"><div class="n">{len(rows)}</div><div class="l">Term sheets read</div></div>'
             f'<div class="tile ok"><div class="n">{n_ok}</div><div class="l">Accepted automatically</div></div>'
             f'<div class="tile bad"><div class="n">{len(rows) - n_ok}</div><div class="l">Sent to analyst review</div></div>')
    return (f"<style>{CSS}</style><div class='wrap'>"
            f"<div class='h1'>Structured product term sheets</div>"
            f"<div class='sub'>AI reads each PDF, rules check every field, only clean term sheets are accepted automatically.</div>"
            f"<div class='tiles'>{tiles}</div>{''.join(card(r) for r in rows)}</div>")


rows = [r.asDict() for r in spark.table("workspace.six_data.ts_checked").orderBy("ts_id").collect()]
displayHTML(review_page(rows))
