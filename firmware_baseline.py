#!/usr/bin/env python3
"""Inventory iPhone 17 Pro restore archives without restoring or connecting a device."""
import argparse
import hashlib
import io
import json
import plistlib
import re
import struct
import subprocess
import sys
import urllib.request
import zipfile

BUILDS = {
    "24A446": ("2026FallFCS/8451c50e-8b6f-4f5c-94c2-81469528464e", "27.0.1", 12725905286),
    "24B119": ("2026FallFCS/f7e03864-9d1c-4854-8f15-440ee15f9114", "27.2", 13172779665),
    "24C5037i": ("2026FallSeed/3f2e8489-c23e-47a4-b3c8-11169fde3ee6", "27.3", 13527160953),
}
DEVICE = "iPhone18,1"
BOARD = "v53ap"
PROPERTY = b"verify-gmmu-tlbis-at-sync"
MAX_METADATA_SIZE = 4 * 1024 * 1024
MAX_KERNEL_ENTRY_SIZE = 32 * 1024 * 1024
MAX_KERNEL_PAYLOAD_SIZE = 128 * 1024 * 1024


class RangeReader(io.RawIOBase):
    def __init__(self, url, size, max_read=MAX_METADATA_SIZE):
        self.url = url
        self.size = size
        self.max_read = max_read
        self.position = 0
        self.cached_start = 0
        self.cached_data = b""

    def seekable(self):
        return True

    def tell(self):
        return self.position

    def seek(self, offset, whence=io.SEEK_SET):
        position = (0, self.position, self.size)[whence] + offset
        if position < 0:
            raise ValueError("Negative seek")
        self.position = position
        return position

    def read(self, count=-1):
        remaining = max(0, self.size - self.position)
        count = remaining if count < 0 else min(count, remaining)
        if not count:
            return b""
        if count > self.max_read:
            raise ValueError(f"Archive range exceeds size limit ({count} bytes)")
        start = self.position
        stop = start + count
        if start < self.cached_start or stop > self.cached_start + len(self.cached_data):
            fetch_start = max(0, start - 131072)
            fetch_stop = min(self.size, stop + 131072)
            expected = f"bytes {fetch_start}-{fetch_stop - 1}/{self.size}"
            request = urllib.request.Request(
                self.url, headers={
                    "Range": f"bytes={fetch_start}-{fetch_stop - 1}",
                    "Accept-Encoding": "identity",
                },
            )
            with urllib.request.urlopen(request, timeout=25) as response:
                if response.status != 206 or response.headers.get("Content-Range") != expected:
                    raise ValueError(f"Server did not return the requested range: {expected}")
                data = response.read(fetch_stop - fetch_start)
            if len(data) != fetch_stop - fetch_start:
                raise ValueError("Incomplete range")
            self.cached_start, self.cached_data = fetch_start, data
        self.position = stop
        return self.cached_data[start - self.cached_start:stop - self.cached_start]


def read_entry(archive, path, max_size=MAX_METADATA_SIZE):
    if archive.getinfo(path).file_size > max_size:
        raise ValueError(f"Archive entry is too large: {path}")
    return archive.read(path)


def der_fields(data):
    offset = 0
    while offset < len(data):
        tag, length = data[offset:offset + 2]
        offset += 2
        if length & 128:
            width = length & 127
            if not width or offset + width > len(data):
                raise ValueError("Invalid IMG4 field length")
            length = int.from_bytes(data[offset:offset + width], "big")
            offset += width
        end = offset + length
        if end > len(data):
            raise ValueError("Truncated IMG4 field")
        yield tag, data[offset:end]
        offset = end


def decode_im4p(raw, payload_type, lzfse, max_size=MAX_METADATA_SIZE):
    (tag, sequence), = der_fields(raw)
    fields = list(der_fields(sequence))
    if tag != 0x30 or fields[0] != (0x16, b"IM4P") or fields[1] != (0x16, payload_type):
        raise ValueError(f"Expected an IM4P of type {payload_type.decode('ascii')}")
    payload_tag, payload = fields[3]
    if payload_tag != 4:
        raise ValueError("Expected an IM4P octet-string payload")
    encoding = "raw"
    if payload[:4] in (b"bvx1", b"bvx2", b"bvxn", b"bvx-"):
        encoding = "LZFSE"
        if not lzfse:
            return encoding, None
        decoded = subprocess.run(
            [lzfse, "-decode"], input=payload, capture_output=True, check=True, timeout=30
        )
        payload = decoded.stdout
    if len(payload) > max_size:
        raise ValueError("Decoded IM4P payload exceeds size limit")
    return encoding, payload


def inspect_tree(raw, lzfse):
    encoding, payload = decode_im4p(raw, b"dtre", lzfse)
    if payload is None:
        return {"payload_encoding": encoding, "property_verdict": "unverified (requires --lzfse)"}
    result = {"payload_bytes": len(payload), "payload_sha256": hashlib.sha256(payload).hexdigest()}
    properties = set()
    node_count = 0

    def walk(offset, depth=0):
        nonlocal node_count
        node_count += 1
        if depth > 128 or offset + 8 > len(payload):
            raise ValueError("Invalid DeviceTree node")
        count = int.from_bytes(payload[offset:offset + 4], "little")
        children = int.from_bytes(payload[offset + 4:offset + 8], "little")
        offset += 8
        for _ in range(count):
            if offset + 36 > len(payload):
                raise ValueError("Truncated DeviceTree property")
            name = payload[offset:offset + 32].split(b"\0", 1)[0]
            if not name or not re.fullmatch(rb"[ -~]+", name):
                raise ValueError("Invalid DeviceTree property name")
            properties.add(name)
            length = int.from_bytes(payload[offset + 32:offset + 36], "little") & 0x7FFFFFFF
            offset += 36 + ((length + 3) & ~3)
            if offset > len(payload):
                raise ValueError("DeviceTree property exceeds payload")
        for _ in range(children):
            offset = walk(offset, depth + 1)
        return offset

    end = walk(0)
    if any(payload[end:]) or b"name" not in properties:
        raise ValueError("Unrecognized DeviceTree payload")
    result.update(
        payload_encoding=encoding,
        nodes=node_count,
        distinct_properties=len(properties),
        property_verdict="present" if PROPERTY in properties else "absent",
        related_properties=sorted(
            name.decode("ascii") for name in properties
            if b"gmmu" in name.lower() or b"tlbi" in name.lower()
        ),
    )
    return result


def inspect_monitor(archive, path, payload_type, version_pattern, lzfse):
    raw = read_entry(archive, path)
    encoding, payload = decode_im4p(raw, payload_type, lzfse)
    result = {"path": path, "im4p_sha256": hashlib.sha256(raw).hexdigest(), "payload_encoding": encoding}
    if payload is not None:
        result.update(
            payload_bytes=len(payload),
            payload_sha256=hashlib.sha256(payload).hexdigest(),
            version_tags=sorted({tag.decode("ascii") for tag in re.findall(version_pattern, payload)}),
        )
    return result


def inspect_kernel(archive, path, lzfse):
    raw = read_entry(archive, path, MAX_KERNEL_ENTRY_SIZE)
    _, payload = decode_im4p(raw, b"krnl", lzfse, MAX_KERNEL_PAYLOAD_SIZE)
    magic, _, _, file_type, count, command_bytes, _, _ = struct.unpack_from("<8I", payload)
    end = 32 + command_bytes
    if magic != 0xfeedfacf or file_type != 0xC or end > len(payload):
        raise ValueError("Expected a 64-bit Mach-O fileset")
    gpu_entries = []
    offset = 32
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError("Truncated Mach-O load command")
        command, size = struct.unpack_from("<II", payload, offset)
        if not 8 <= size <= end - offset:
            raise ValueError("Invalid Mach-O load command size")
        if command == 0x80000035:  # LC_FILESET_ENTRY
            if size < 32:
                raise ValueError("Truncated fileset command")
            name_offset, = struct.unpack_from("<I", payload, offset + 24)
            if not 32 <= name_offset < size:
                raise ValueError("Invalid fileset name offset")
            name = payload[offset + name_offset:offset + size].split(b"\0", 1)[0].decode("ascii")
            if "agx" in name.lower() or "iogpu" in name.lower():
                gpu_entries.append(name)
        offset += size
    if offset != end:
        raise ValueError("Mach-O command length mismatch")
    return {
        "path": path,
        "payload_bytes": len(payload),
        "payload_sha256": hashlib.sha256(payload).hexdigest(),
        "gpu_fileset_entries": sorted(gpu_entries),
    }


def audit(archive, expected_build, lzfse, kernel):
    raw = read_entry(archive, "BuildManifest.plist")
    manifest = plistlib.loads(raw)
    build = manifest["ProductBuildVersion"]
    if build != expected_build or DEVICE not in manifest["SupportedProductTypes"]:
        raise ValueError(f"Wrong firmware: {build} {manifest['SupportedProductTypes']}")
    identities = [
        identity for identity in manifest["BuildIdentities"]
        if identity["Info"].get("DeviceClass", "").lower() == BOARD
    ]
    if not identities:
        raise ValueError("No v53ap identity")
    trees = {identity["Manifest"]["DeviceTree"]["Info"]["Path"] for identity in identities}
    if len(trees) != 1:
        raise ValueError(f"Conflicting DeviceTree paths: {trees}")
    tree_path, = trees
    entries = sorted(
        (entry.filename, entry.file_size) for entry in archive.infolist()
        if entry.filename == tree_path or any(
            name in entry.filename.lower() for name in ("sptm.", "txm.", "exclavecore", "kernelcache")
        )
    )
    tree = read_entry(archive, tree_path)
    result = {
        "device": DEVICE,
        "board": BOARD,
        "build": build,
        "version": manifest["ProductVersion"],
        "manifest_sha256": hashlib.sha256(raw).hexdigest(),
        "archive_entry_bytes": dict(entries),
        "monitors": {
            "SPTM": inspect_monitor(archive, "Firmware/sptm.t8150.release.im4p", b"sptm", rb"SPTM-[0-9]+(?:\.[0-9]+)*", lzfse),
            "TXM": inspect_monitor(archive, "Firmware/txm.iphoneos.release.im4p", b"trxm", rb"txm-[0-9]+(?:\.[0-9]+)*", lzfse),
        },
        "device_tree": {
            "path": tree_path,
            "im4p_sha256": hashlib.sha256(tree).hexdigest(),
            **inspect_tree(tree, lzfse),
        },
    }
    if kernel:
        kernels = {identity["Manifest"]["KernelCache"]["Info"]["Path"] for identity in identities}
        if len(kernels) != 1:
            raise ValueError(f"Conflicting kernelcache paths: {kernels}")
        kernel_path, = kernels
        result["kernelcache"] = inspect_kernel(archive, kernel_path, lzfse)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", help="Expected firmware build, e.g. 24A446")
    parser.add_argument("--ipsw", help="Read an existing local archive instead of Apple's CDN")
    parser.add_argument("--lzfse", help="Path to the lzfse executable for compressed DeviceTrees")
    parser.add_argument("--kernel", action="store_true", help="Inventory GPU entries in the kernelcache")
    args = parser.parse_args()
    if args.kernel and not args.lzfse:
        parser.error("--kernel requires --lzfse")
    try:
        if args.ipsw:
            with zipfile.ZipFile(args.ipsw) as archive:
                result = audit(archive, args.build, args.lzfse, args.kernel)
        else:
            if args.build not in BUILDS:
                parser.error("this build requires --ipsw")
            folder, version, size = BUILDS[args.build]
            url = (
                f"https://updates.cdn-apple.com/{folder}/"
                f"iPhone18%2C1_{version}_{args.build}_Restore.ipsw"
            )
            max_read = MAX_KERNEL_ENTRY_SIZE if args.kernel else MAX_METADATA_SIZE
            with RangeReader(url, size, max_read) as stream, zipfile.ZipFile(stream) as archive:
                result = audit(archive, args.build, args.lzfse, args.kernel)
        print(json.dumps(result, indent=2, sort_keys=True))
    except (OSError, ValueError, KeyError, IndexError, struct.error, zipfile.BadZipFile, subprocess.SubprocessError) as exc:
        print(f"Firmware audit failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
