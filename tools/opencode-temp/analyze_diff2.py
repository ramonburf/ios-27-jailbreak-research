import json
d = json.load(open("G:/iOS 27.0.1/iOS/tools/opencode-temp/kc_diff_all.json"))

def show(name, limit=40):
    for r in d:
        if r["kext"] == name:
            print("\n===== %s: %d changed =====" % (name, len(r["changed"])))
            for c in r["changed"][:limit]:
                print("%#014x -> %#014x sim=%.3f sz %d->%d %s" % (
                    c["a_addr"], c["b_addr"], c["sim"], c["a_size"], c["b_size"], c["delta"]))

show("com.apple.iokit.IOSurface")
show("com.apple.iokit.IOHIDFamily", 25)

# kernel: look for UAF-fix idioms
print("\n===== kernel: new state-flag checks / bounds checks =====")
for r in d:
    if r["kext"] != "com.apple.kernel":
        continue
    for c in r["changed"]:
        dl = c["delta"]
        flags = ("tbz", "tbnz")
        bounds = ("b.ge", "b.hs", "b.gt", "b.ls", "b.lo")
        newflag = dl.get("tbz", 0) + dl.get("tbnz", 0)
        newbnd = sum(dl.get(k, 0) for k in bounds)
        if newflag >= 1 and dl.get("ldrb", 0) >= 1:
            print("FLAG %014x -> %014x sim=%.3f sz %d->%d %s" % (
                c["a_addr"], c["b_addr"], c["sim"], c["a_size"], c["b_size"], dl))
        elif newbnd >= 2 and dl.get("cmp", 0) >= 2:
            print("BOUND %014x -> %014x sim=%.3f sz %d->%d %s" % (
                c["a_addr"], c["b_addr"], c["sim"], c["a_size"], c["b_size"], dl))
