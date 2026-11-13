from pathlib import Path
import re

for p in sorted(Path("analysis/pdf").glob("*.pdf")):
    d = p.read_bytes()
    text = d.decode("latin1")
    comps = re.search(r"/DeviceN \[[^\]]*\]", text)
    n = len(comps.group(0).split("/")) - 2 if comps else None  # crude
    m = re.search(r"/DeviceN \[[^\]]*\]", text)
    names = m.group(0) if m else ""
    # Count /C identifiers after /DeviceN [
    if m:
        inner = m.group(0).split("[", 1)[1].split("]", 1)[0]
        n = len([x for x in inner.split() if x.startswith("/C")])
    has_func = "/Function" in text or "/FunctionType" in text
    print(p.name, "components=", n, "has_Function=", has_func)
