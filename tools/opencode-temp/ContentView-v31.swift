import SwiftUI
import Darwin

@main
struct AGXProbeApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @StateObject private var vm = ReachViewModel()
    var body: some View {
        VStack(spacing: 12) {
            Text("AGXProbe v31 — broad AGX + IOSurf corr").font(.headline)
            Text("AGX sel 0-255 + IOSurface corr").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v31")
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(10)
                    .background(vm.isRunning ? Color.gray : Color.blue).cornerRadius(8)
            }.disabled(vm.isRunning)
            Text("Status: \(vm.status)").font(.caption2).foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .padding().task { await vm.autoRunIfRequested() }
    }
}

@MainActor
final class ReachViewModel: ObservableObject {
    @Published var log = ""
    @Published var status = "Ready"
    @Published var isRunning = false
    private var didAutoRun = false

    private let logFileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reach.log")
    }()

    private func log(_ m: String) {
        log += m + "\n"; print(m); fflush(stdout)
        try? log.write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    func autoRunIfRequested() async {
        guard !didAutoRun else { return }
        didAutoRun = true
        if ProcessInfo.processInfo.arguments.contains("--autorun") { await runProbe() }
    }

    private func stripNul(_ data: Data, tag: String) -> Data? {
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        guard let a = s.range(of: "<\(tag)"),
              let b = s.range(of: "</\(tag)>", options: .backwards) else { return nil }
        return (String(s[a.lowerBound..<b.upperBound]).data(using: .utf8) ?? Data()) + Data([0])
    }

    private func xmlNul(_ d: Any) -> Data? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0) else { return nil }
        return data + Data([0])
    }

    private func num(_ v: UInt64) -> Int64 { Int64(bitPattern: v) }

    private func plane(off: UInt64, size: UInt64) -> [String: Any] {
        return [
            "IOSurfacePlaneWidth": 64,
            "IOSurfacePlaneHeight": 64,
            "IOSurfacePlaneBytesPerRow": 256,
            "IOSurfacePlaneBytesPerElement": 4,
            "IOSurfacePlaneOffset": num(off),
            "IOSurfacePlaneSize": num(size),
        ]
    }

    private func surf(_ alloc: UInt64, _ planes: [[String: Any]]) -> [String: Any] {
        return [
            "IOSurfaceWidth": 64,
            "IOSurfaceHeight": 64,
            "IOSurfaceBytesPerElement": 4,
            "IOSurfaceBytesPerRow": 256,
            "IOSurfaceAllocSize": num(alloc),
            "IOSurfacePixelFormat": 0x42475241,
            "IOSurfacePlaneInfo": planes,
        ]
    }

    private func callAGX(conn: io_connect_t, sel: UInt32, scalars: [UInt64], sdata: [UInt8],
                         outSize: Int) -> (UInt32, [UInt8]) {
        var inScalar = [UInt64](repeating: 0, count: 4)
        for i in 0..<scalars.count { inScalar[i] = scalars[i] }
        var outBuff = [UInt64](repeating: 0, count: outSize / 8)
        var outSz = outBuff.count * MemoryLayout<UInt64>.stride
        let kr: Int32 = sdata.withUnsafeBytes { raw in
            outBuff.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, sel,
                                    &inScalar, UInt32(scalars.count),
                                    raw.baseAddress, sdata.count,
                                    nil, nil,
                                    ob.baseAddress, &outSz)
            }
        }
        let k = UInt32(bitPattern: kr)
        var outBytes = [UInt8]()
        for i in 0..<outBuff.count {
            let v = outBuff[i]
            withUnsafeBytes(of: v.littleEndian) { b in outBytes.append(contentsOf: b) }
        }
        return (k, Array(outBytes.prefix(outSz)))
    }

    private func callIOSurf(conn: io_connect_t, sel: UInt32, parent: UInt32, _ d: [String: Any]) -> [UInt8]? {
        guard let full = xmlNul(d), let p = stripNul(full, tag: "dict") else { return nil }
        var inScalar = [UInt64](repeating: 0, count: 1)
        var outBuff = [UInt64](repeating: 0, count: 0xC68 / 8)
        var outSz = outBuff.count * MemoryLayout<UInt64>.stride
        let kr: Int32 = p.withUnsafeBytes { raw in
            outBuff.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, sel,
                                    &inScalar, 1,
                                    raw.baseAddress, p.count,
                                    nil, nil,
                                    ob.baseAddress, &outSz)
            }
        }
        let k = UInt32(bitPattern: kr)
        if k != 0 { return nil }
        var outBytes = [UInt8]()
        for i in 0..<outBuff.count {
            let v = outBuff[i]
            withUnsafeBytes(of: v.littleEndian) { b in outBytes.append(contentsOf: b) }
        }
        return Array(outBytes.prefix(outSz))
    }

    private func idFrom(_ out: [UInt8]) -> UInt32? {
        guard out.count >= 0x1C else { return nil }
        return UInt32(out[0x18]) | (UInt32(out[0x19]) << 8) | (UInt32(out[0x1A]) << 16) | (UInt32(out[0x1B]) << 24)
    }

    private func u64(_ out: [UInt8], _ o: Int) -> UInt64 {
        guard out.count >= o + 8 else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(out[o + i]) << (8 * i) }
        return v
    }

    private func openService(_ name: String, _ type: UInt32) -> io_connect_t? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
        guard service != 0 else { return nil }
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, type, &conn)
        IOObjectRelease(service)
        return okr == 0 ? conn : nil
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v31 — broad AGX + IOSurf corr ===")

        guard let agxConn = openService("AGXAcceleratorG18P", 1) else {
            log("AGXAcceleratorG18P not available"); status = "Failed"; isRunning = false; return
        }
        defer { IOServiceClose(agxConn) }
        log("AGXAcceleratorG18P type=1 conn=0x\(String(agxConn, radix:16))")

        log("\n--- AGX sel 0-255, sc0/st0 ---")
        for sel: UInt32 in 0...255 {
            let (k, out) = callAGX(conn: agxConn, sel: sel, scalars: [], sdata: [], outSize: 32)
            if k != 0xe00002c2 {
                log("sel=0x\(String(sel, radix:16)) kr=0x\(String(k, radix:16)) outSz=\(out.count)")
                if k == 0 && out.count >= 24 {
                    log("  p1=0x\(String(u64(out,8), radix:16)) p2=0x\(String(u64(out,16), radix:16)) sz=0x\(String(u64(out,24), radix:16)) tag=0x\(String(u64(out,0), radix:16))")
                }
            }
        }

        log("\n--- IOSurface create ---")
        if let iosConn = openService("IOSurfaceRoot", 0) {
            defer { IOServiceClose(iosConn) }
            if let iOut = callIOSurf(conn: iosConn, sel: 0, parent: 0, surf(0x4000, [plane(off: 0, size: 0x4000)])),
               let iID = idFrom(iOut) {
                let ia0 = u64(iOut, 0x00)
                log("IOSurface id=\(iID) a0=0x\(String(ia0, radix:16))")

                // sel0x4 with surface ID as scalar
                let (k4, out4) = callAGX(conn: agxConn, sel: 0x4, scalars: [UInt64(iID)], sdata: [], outSize: 32)
                if k4 == 0 && out4.count >= 24 {
                    log("sel0x4(scalar=sid): p1=0x\(String(u64(out4,8), radix:16)) p2=0x\(String(u64(out4,16), radix:16)) sz=0x\(String(u64(out4,24), radix:16))")
                    if u64(out4,8) == ia0 || u64(out4,16) == ia0 {
                        log("*** POINTER MATCH with IOSurface a0! ***")
                    }
                } else {
                    log("sel0x4(scalar=sid): kr=0x\(String(k4, radix:16))")
                }
            } else {
                log("IOSurface create failed")
            }
        }

        // sel0x4 plain on AGX
        let (k4, out4) = callAGX(conn: agxConn, sel: 0x4, scalars: [], sdata: [], outSize: 32)
        if k4 == 0 && out4.count >= 24 {
            log("sel0x4 plain: p1=0x\(String(u64(out4,8), radix:16)) p2=0x\(String(u64(out4,16), radix:16)) sz=0x\(String(u64(out4,24), radix:16)) tag=0x\(String(u64(out4,0), radix:16))")
        }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
