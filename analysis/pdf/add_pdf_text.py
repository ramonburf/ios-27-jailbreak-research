#!/usr/bin/env python3
"""Add a visible filename text label to the first page of every PDF."""
from pathlib import Path
import fitz

out_dir = Path(__file__).resolve().parent
for p in sorted(out_dir.glob("*.pdf")):
    doc = fitz.open(p)
    if len(doc) == 0:
        print(f"SKIP (no pages): {p.name}")
        doc.close()
        continue
    page = doc[0]
    text = p.stem
    page.insert_text((10, 20), text, fontsize=12, fontname="Helvetica")
    data = doc.tobytes()
    p.write_bytes(data)
    doc.close()
    print(f"updated {p.name}")
