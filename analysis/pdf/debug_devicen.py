#!/usr/bin/env python3
"""Debug DeviceN colour space / tint transform syntax (correct object refs)."""
from pathlib import Path

OUT = Path(__file__).resolve().parent


def build(path, objs):
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


def stream(data):
    return b"<< /Length %d >>\nstream\n" % len(data) + data + b"\nendstream"


catalog = b"<< /Type /Catalog /Pages 2 0 R >>"
pages = b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"


def page(content, resources):
    return (
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] "
        b"/Resources " + resources + b" /Contents 4 0 R >>"
    )


# DeviceN fill control: 4 components -> DeviceCMYK, Type 4 tint.
res = b"<< /ColorSpace << /CS1 [/DeviceN [/C1 /C2 /C3 /C4] /DeviceCMYK 5 0 R] >> >>"
content = b"/CS1 cs\n0 0 0 0 scn\n0 0 200 200 re f\n"
func = b"<< /FunctionType 4 /Domain [0 1 0 1 0 1 0 1] /Range [0 1 0 1 0 1 0 1] /Length 30 >>\nstream\n{ pop pop pop pop 0 0 0 0 }\nendstream"
build(OUT / "devicen_rect.pdf", [catalog, pages, page(content, res), stream(content), func])

# DeviceN fill control: 3 components -> DeviceRGB.
res3 = b"<< /ColorSpace << /CS1 [/DeviceN [/C1 /C2 /C3] /DeviceRGB 5 0 R] >> >>"
content3 = b"/CS1 cs\n0 0 0 scn\n0 0 200 200 re f\n"
func3 = b"<< /FunctionType 4 /Domain [0 1 0 1 0 1] /Range [0 1 0 1 0 1] /Length 27 >>\nstream\n{ pop pop pop 1 0 0 }\nendstream"
build(OUT / "devicen_rect_rgb.pdf", [catalog, pages, page(content3, res3), stream(content3), func3])

# Type 2 axial with DeviceN ColorSpace (4 components), function object 6.
res_sh = b"<< /Shading << /Sh1 5 0 R >> >>"
ctype = b"/Sh1 sh\n"
sh = (
    b"<< /ShadingType 2 /ColorSpace [/DeviceN [/C1 /C2 /C3 /C4] /DeviceCMYK 6 0 R] "
    b"/Coords [0 0 200 200] /Function << /FunctionType 2 /Domain [0 1] "
    b"/C0 [0 0 0 0] /C1 [1 1 1 1] /N 1 >> /Extend [true true] /Length 0 >>"
)
build(OUT / "devicen_axial.pdf", [catalog, pages, page(ctype, res_sh), stream(ctype), sh, func])
