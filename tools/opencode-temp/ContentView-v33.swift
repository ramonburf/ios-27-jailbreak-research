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
            Text("AGXProbe v33 — sel1 release + sel10 proper (13 Pro)").font(.headline)
            Text("sel1 struct input + sel10 outSize=13").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v33")
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

    private func callIO(conn: io_connect_t, sel: UInt32, scalars: [UInt64], sdata: [UInt8],
                        outSize: Int) -> (UInt32, [UInt8], [UInt64]) {
        var inScalar = [UInt64](repeating: 0, count: 4)
        for i in 0..<scalars.count { inScalar[i] = scalars[i] }
        var outScalar = [UInt64](repeating: 0, count: 8)
        var outScalarCount: UInt32 = 0
        var outBuff = [UInt64](repeating: 0, count: max(outSize / 8, 1))
        var outSz = outBuff.count * MemoryLayout<UInt64>.stride
        let kr: Int32 = sdata.withUnsafeBytes { raw in
            outBuff.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, sel,
                                    &inScalar, UInt32(scalars.count),
                                    raw.baseAddress, sdata.count,
                                    &outScalar, &outScalarCount,
                                    ob.baseAddress, &outSz)
            }
        }
        let k = UInt32(bitPattern: kr)
        var outBytes = [UInt8]()
        for i in 0..<outBuff.count {
            let v = outBuff[i]
            withUnsafeBytes(of: v.littleEndian) { b in outBytes.append(contentsOf: b) }
        }
        let os = Array(outScalar.prefix(Int(outScalarCount)))
        return (k, Array(outBytes.prefix(outSz)), os)
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

        // Create surface
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
        guard let full = xmlNul(surfDict), let payload = stripNul(full, tag: "dict") else {
            log("serialize failed"); return
        }
        var inScalar = [UInt64](repeating: 0, count: 1)
        var outScalar = [UInt64](repeating: 0, count: 8)
        var outScalarCount: UInt32 = 0
        var outBuff = [UInt64](repeating: 0, count: 0xC68 / 8)
        var outSz = outBuff.count * MemoryLayout<UInt64>.stride
        let kr0: Int32 = payload.withUnsafeBytes { raw in
            outBuff.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, 0,
                                    &inScalar, 1,
                                    raw.baseAddress, payload.count,
                                    &outScalar, &outScalarCount,
                                    ob.baseAddress, &outSz)
            }
        }
        guard UInt32(bitPattern: kr0) == 0 else {
            log("sel0 create failed kr=0x\(String(UInt32(bitPattern: kr0), radix:16))"); return
        }
        let iOut = Array(outBuff.prefix(outSz / 8).flatMap { v in
            withUnsafeBytes(of: v.littleEndian) { Array($0) }
        })
        guard let sid = idFrom(iOut) else {
            log("no surface id"); return
        }
        let ia0 = u64(iOut, 0x00)
        log("created surface id=\(sid) a0=0x\(String(ia0, radix:16))")

        // ---- sel1 release with structure input (4 bytes = surface ID) ----
        log("\n--- sel1 release (struct input = surface ID) ---")
        var idBytes: [UInt8] = []
        withUnsafeBytes(of: sid.littleEndian) { idBytes.append(contentsOf: $0) }
        let (k1, out1, os1) = callIO(conn: conn, sel: 1, scalars: [], sdata: idBytes, outSize: 0)
        log("sel1 release id=\(sid): kr=0x\(String(k1, radix:16)) osc=\(os1.count)")

        // Check if surface memory still accessible
        log("  read via old a0 after release")
        // Can't easily read without mapping, but check if ID still valid via sel10

        // ---- sel10 getValue with outSize=13 ----
        log("\n--- sel10 getValue (outSize=13) ---")
        func sel10Payload(key: String) -> [UInt8] {
            var d = Data()
            withUnsafeBytes(of: sid.littleEndian) { d.append(contentsOf: $0) }
            d.append(contentsOf: [0,0,0,0,0,0,0,0])
            d.append(contentsOf: key.utf8)
            d.append(0)
            return Array(d)
        }

        for key in ["IOSurfaceName", "IOSurfaceWidth", "NonExistentKey"] {
            let p = sel10Payload(key: key)
            let (k, out, os) = callIO(conn: conn, sel: 10, scalars: [], sdata: p, outSize: 13)
            if k == 0 && out.count > 0 {
                let hex = out.map { String(format: "%02x", $0) }.joined()
                let osStr = os.map { String(format: "0x%016llx", $0) }.joined(separator: " ")
                log("sel10 \(key): kr=0x\(String(k, radix:16)) outSz=\(out.count) hex=\(hex) osc=\(os.count) scalar=\(osStr)")
            } else {
                log("sel10 \(key): kr=0x\(String(k, radix:16)) outSz=\(out.count) osc=\(os.count)")
            }
        }

        // ---- sel10 with scalar output capture (outSize=0) ----
        log("\n--- sel10 getValue (outSize=0, scalar output) ---")
        let p = sel10Payload(key: "IOSurfaceName")
        let (k2, out2, os2) = callIO(conn: conn, sel: 10, scalars: [], sdata: p, outSize: 0)
        log("sel10 name: kr=0x\(String(k2, radix:16)) outSz=\(out2.count) osc=\(os2.count)")
        if os2.count > 0 {
            let osStr = os2.map { String(format: "0x%016llx", $0) }.joined(separator: " ")
            log("  scalar output: \(osStr)")
        }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v33 — sel1 release + sel10 proper (13 Pro) ===")

        probeService("IOSurfaceRoot", 0)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
