# iPhone 17 Pro firmware baseline

Recorded 5 November 2026 for iPhone18,1, board v53ap, platform t8150. The archive
contains the Python inspection tool and the JSON output for three Apple IPSWs.

## Reproduce

Use Python 3 and the [LZFSE command-line decoder](https://github.com/lzfse/lzfse).
The commands read bounded ranges from Apple's CDN. Each `--kernel` run reads
the kernelcache entry (roughly 23–24 MB) in addition to the metadata. Omit
`--kernel` for the DeviceTree and monitor checks only.

```bash
git clone https://github.com/lzfse/lzfse.git
make -C lzfse
for build in 24A446 24B119 24C5037i; do
  python3 firmware_baseline.py "$build" --lzfse ./lzfse/build/bin/lzfse --kernel
done
```

Decoder revision used: `e634ca58b4821d9f3d560cdc6df5dec02ffc93fd`.
To use a local archive, add `--ipsw /path/to/file.ipsw`. The tool validates
the build, supported product, and board from the manifest and reads archive
entries without extracting files to disk or interacting with an iPhone.

## Measurements

| Measurement | 24A446 | 24B119 | 24C5037i |
|---|---:|---:|---:|
| DeviceTree decoded bytes | 361,112 | 361,072 | 360,912 |
| SPTM decoded bytes | 1,261,600 | 1,327,136 | 1,327,136 |
| SPTM version tag | 820.0.22 | 820.40.24 | 820.60.12 |
| TXM decoded bytes | 557,088 | 557,088 | 557,088 |
| Kernelcache decoded bytes | 78,135,296 | 78,512,128 | 79,495,168 |
| Exclave bundle IM4P entry bytes | 31,490,282 | 31,719,658 | 32,112,874 |

JSON receipts contain the full SHA-256 values. The TXM payloads have the
same size and version tag (`txm-374`) and three different hashes. A hash
difference alone does not identify a change in executable logic.

## Research gates

- **DeviceTree configuration.** Each decoded tree has 448 nodes. The exact
  property `verify-gmmu-tlbis-at-sync` is absent, with
  `issue-gmmu-tlbis-at-retype` and `tlbi-flushes-smmu` present as controls.
  Runtime behavior and reachability remain unverified.
- **GPU driver.** The Mach-O fileset inventories list `com.apple.AGXG18P`
  in all three builds. The reference finding covers `AGXG17P` on a different
  device. The inventory identifies which driver must be independently
  analyzed. It does not establish whether an analogous change exists.
- **Jailbreak.** The evidence here is a static baseline. There is no
  demonstrated exploit primitive, privilege escalation, or installable jailbreak.

Reference methodology: [iOS-Research](https://github.com/AzozzALFiras/iOS-Research/tree/d0df826a6ccd8dca8ac014a6e7e5aadb53476d4a).
