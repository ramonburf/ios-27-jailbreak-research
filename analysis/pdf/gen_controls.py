#!/usr/bin/env python3
"""Generate small control PDFs for shading syntax validation."""
from pathlib import Path

OUT = Path(__file__).resolve().parent


def build(path, shading_dict, data):
    objs = []
    objs.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    objs.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    objs.append(
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] "
        b"/Resources << /Shading << /Sh1 5 0 R >> >> /Contents 4 0 R >>"
    )
    content = b"q\n/Sh1 sh\nQ\n"
    objs.append(b"<< /Length %d >>\nstream\n" % len(content) + content + b"endstream")
    objs.append(shading_dict + b"\nstream\n" + data + b"\nendstream")
    out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
    offs = [0]
    for i, o in enumerate(objs, 1):
        offs.append(len(out))
        out += f"{i} 0 obj\n".encode() + o + b"\nendobj\n"
    x = len(out)
    out += f"xref\n0 {len(objs)+1}\n".encode() + b"0000000000 65535 f \n"
    for o in offs[1:]:
        out += f"{o:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objs)+1} /Root 1 0 R >>\nstartxref\n{x}\n%%EOF\n".encode()
    path.write_bytes(out)
    print(f"wrote {path} ({len(out)} bytes)")


# Axial shading control: should paint a red-to-blue gradient.
build(
    OUT / "type2_axial.pdf",
    b"<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 200 200] "
    b"/Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> "
    b"/Extend [true true] /Length 0 >>",
    b"",
)

# Type 5 lattice, DeviceRGB, 2x2 vertices, no flag bytes.
data = bytes(
    [
        0, 0, 255, 0, 0, 0,
        255, 0, 255, 0, 0, 0,
        0, 255, 0, 255, 0, 0,
        255, 255, 255, 255, 0, 0,
    ]
)
build(
    OUT / "type5_rgb.pdf",
    b"<< /ShadingType 5 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 "
    b"/BitsPerComponent 8 /Decode [0 200 0 200 0 1 0 1 0 1] "
    b"/VerticesPerRow 2 /Length %d >>" % len(data),
    data,
)

# Type 5 lattice, DeviceRGB, flag byte before each vertex.
data_flags = bytes(
    [
        0, 0, 0, 255, 0, 0, 0,
        0, 255, 0, 255, 0, 0, 0,
        0, 0, 255, 0, 255, 0, 0,
        0, 255, 255, 255, 255, 0, 0,
    ]
)
build(
    OUT / "type5_rgb_flags.pdf",
    b"<< /ShadingType 5 /ColorSpace /DeviceRGB /BitsPerCoordinate 8 "
    b"/BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 200 0 200 0 1 0 1 0 1] "
    b"/VerticesPerRow 2 /Length %d >>" % len(data_flags),
    data_flags,
)
