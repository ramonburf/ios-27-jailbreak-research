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
            Text("AGXProbe v30 — sel0x4 correlation (both devices)").font(.headline)
            Text("sel0x4 repeat + IOSurface ID input + pointer match").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v30")
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
        guard let full = try? PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0),
              var xml = String(data: full, encoding: .utf8) else { return nil }
        xml += "\0"
        // strip <dict> wrapper
        guard let a = xml.range(of: "<dict>"),
              let b = xml.range(of: "</dict>", options: .backwards) else { return nil }
        let stripped = String(xml[a.lowerBound..<b.upperBound]) + "\0"
        guard let payload = stripped.data(using: .utf8) else { return nil }
        var inScalar = [UInt64](repeating: 0, count: 1)
        var outBuff = [UInt64](repeating: 0, count: 0xC68 / 8)
        var outSz = outBuff.count * MemoryLayout<UInt64>.stride
        let kr: Int32 = payload.withUnsafeBytes { raw in
            outBuff.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, sel,
                                    &inScalar, 1,
                                    raw.baseAddress, payload.count,
                                    nil, nil,
                                    ob.baseAddress, &outSz)
            }
        }
        let k = UInt32(bitPattern: kr)
        if k != 0 { log("  IOSurf create kr=0x\(String(k, radix:16))"); return nil }
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

    private func probeService(_ name: String, _ type: UInt32) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(name))
        guard service != 0 else { log("\(name): service NOT FOUND"); return }
        log("\(name): service found")
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, type, &conn)
        IOObjectRelease(service)
        if okr != 0 { log("\(name) type=\(type): IOServiceOpen kr=0x\(String(okr, radix:16))"); return }
        log("\(name) type=\(type): IOServiceOpen ok conn=0x\(String(conn, radix:16))")
        defer { IOServiceClose(conn) }

        // sel=0x4 repeated 5 times
        log("\n--- sel=0x4 x5 ---")
        var agxPtrs: [UInt64] = []
        for i in 0..<5 {
            let (k, out) = callAGX(conn: conn, sel: 0x4, scalars: [], sdata: [], outSize: 32)
            if k == 0 && out.count >= 24 {
                let p1 = u64(out, 8)
                let p2 = u64(out, 16)
                let sz = u64(out, 24)
                agxPtrs.append(p1)
                log("  call \(i): p1=0x\(String(p1, radix:16)) p2=0x\(String(p2, radix:16)) sz=0x\(String(sz, radix:16)) tag=0x\(String(u64(out,0), radix:16))")
            } else {
                log("  call \(i): kr=0x\(String(k, radix:16))")
            }
        }

        // sel=0x4 with scalar inputs
        log("\n--- sel=0x4 with scalar inputs ---")
        for s in [UInt64]([1, 2, 3, 0x10, 0x100, 0x1000]) {
            let (k, out) = callAGX(conn: conn, sel: 0x4, scalars: [s], sdata: [], outSize: 32)
            if k == 0 && out.count >= 24 {
                log("  scalar=0x\(String(s, radix:16)): p1=0x\(String(u64(out,8), radix:16)) p2=0x\(String(u64(out,16), radix:16)) sz=0x\(String(u64(out,24), radix:16))")
            } else {
                log("  scalar=0x\(String(s, radix:16)): kr=0x\(String(k, radix:16))")
            }
        }

        // Create IOSurface + call sel=0x4, check for pointer match
        log("\n--- IOSurface + sel0x4 correlation ---")
        let surfDict: [String: Any] = [
            "IOSurfaceWidth": 64,
            "IOSurfaceHeight": 64,
            "IOSurfaceBytesPerElement": 4,
            "IOSurfaceBytesPerRow": 256,
            "IOSurfaceAllocSize": 0x4000,
            "IOSurfacePixelFormat": 0x42475241,
            "IOSurfacePlaneInfo": [[
                "IOSurfacePlaneWidth": 64,
                "IOSurfacePlaneHeight": 64,
                "IOSurfacePlaneBytesPerRow": 256,
                "IOSurfacePlaneBytesPerElement": 4,
                "IOSurfacePlaneOffset": 0,
                "IOSurfacePlaneSize": 0x4000,
            ]],
        ]
        guard let iOut = callIOSurf(conn: conn, sel: 0, parent: 0, surfDict),
              let iID = idFrom(iOut) else {
            log("  IOSurface create failed")
            return
        }
        let iA0 = u64(iOut, 0x00)
        log("  IOSurface id=\(iID) a0=0x\(String(iA0, radix:16))")

        // sel0x4 with surface ID as scalar
        let (k4, out4) = callAGX(conn: conn, sel: 0x4, scalars: [UInt64(iID)], sdata: [], outSize: 32)
        if k4 == 0 && out4.count >= 24 {
            log("  sel0x4(scalar=sid): p1=0x\(String(u64(out4,8), radix:16)) p2=0x\(String(u64(out4,16), radix:16)) sz=0x\(String(u64(out4,24), radix:16))")
            if u64(out4,8) == iA0 || u64(out4,16) == iA0 {
                log("  *** POINTER MATCH with IOSurface a0! ***")
            }
        }

        // Check if any agxPtr matches iA0
        for p in agxPtrs {
            if p == iA0 { log("  *** AGX p1 matches IOSurface a0! ***") }
        }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v30 — sel0x4 correlation ===")

        // Try both AGX service names
        probeService("AGXAcceleratorG18P", 1)
        probeService("AGXAcceleratorG14P", 1)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
