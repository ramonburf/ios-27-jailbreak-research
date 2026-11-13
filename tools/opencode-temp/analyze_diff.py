import json
d = json.load(open("G:/iOS 27.0.1/iOS/tools/opencode-temp/kc_diff_all.json"))
print("kexts with changes:", len(d))
print("\n=== top 20 by changed count ===")
for r in sorted(d, key=lambda r: -len(r["changed"]))[:20]:
    print("%-58s %4d changed (funcs %d/%d)" % (r["kext"], len(r["changed"]), r["n_funcs_a"], r["n_funcs_b"]))

for r in d:
    if r["kext"] == "com.apple.kernel":
        print("\n=== com.apple.kernel: %d changed ===" % len(r["changed"]))
        for c in r["changed"]:
            delta = {k: v for k, v in c["delta"].items() if v}
            # focus on structurally interesting deltas: new branches/checks
            interesting = {k: v for k, v in delta.items() if k in
                           ("cmp", "b", "bl", "cbz", "cbnz", "tbz", "tbnz", "ldr", "str",
                            "ldrb", "strb", "ldrh", "strh", "mov", "movz", "movk", "ret",
                            "adrp", "add", "sub", "and", "orr", "eor", "mrs", "msr")}
            print("%#014x -> %#014x  sim=%.3f  sz %d->%d  delta=%s" % (
                c["a_addr"], c["b_addr"], c["sim"], c["a_size"], c["b_size"], delta))
