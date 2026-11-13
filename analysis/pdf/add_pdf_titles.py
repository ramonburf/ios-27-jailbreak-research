#!/usr/bin/env python3
"""Add a unique /Info /Title to every PDF in this directory."""
from pathlib import Path
import re

titles = {
    "devicen_axial.pdf": "Control Devicen Axial",
    "devicen_rect.pdf": "Control Devicen Rect",
    "devicen_rect_rgb.pdf": "Control Devicen Rect RGB",
    "type2_axial.pdf": "Control Type2 Axial",
    "type5_devicen16.pdf": "Type5 Devicen 16",
    "type5_devicen32.pdf": "Type5 Devicen 32",
    "type5_devicen4.pdf": "Type5 Devicen 4",
    "type5_devicen5.pdf": "Type5 Devicen 5",
    "type5_devicen8.pdf": "Type5 Devicen 8",
    "type5_devicen8_flags.pdf": "Type5 Devicen 8 Flags",
    "type5_rgb.pdf": "Type5 RGB",
    "type5_rgb_flags.pdf": "Type5 RGB Flags",
}

for p in sorted(Path(__file__).resolve().parent.glob("*.pdf")):
    data = p.read_bytes()
    text = data.decode("latin-1")
    m = re.search(r"trailer\n<< /Size (\d+) /Root 1 0 R >>", text)
    if not m:
        print(f"SKIP (no trailer match): {p.name}")
        continue
    size = m.group(1)
    title = titles.get(p.name, p.name)
    new_text = (
        text[: m.start()]
        + f"trailer\n<< /Size {size} /Root 1 0 R /Info << /Title ({title}) >> >>"
        + text[m.end() :]
    )
    p.write_bytes(new_text.encode("latin-1"))
    print(f"updated {p.name} -> {title}")
