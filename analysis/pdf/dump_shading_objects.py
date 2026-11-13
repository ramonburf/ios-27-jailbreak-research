from pathlib import Path

for name in [
    "type5_devicen4.pdf",
    "type5_devicen5.pdf",
    "type5_devicen8.pdf",
    "type5_devicen16.pdf",
    "type5_devicen32.pdf",
]:
    p = Path("analysis/pdf") / name
    text = p.read_bytes().decode("latin1")
    print(f"===== {name} =====")
    # print printable-ish content between "5 0 obj" and "endobj"
    start = text.find("5 0 obj")
    end = text.find("endobj", start)
    print(text[start:end])
    print()
