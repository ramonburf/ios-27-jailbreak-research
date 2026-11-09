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
            Text("AGXProbe v36 — sel9 exact outSz (13 Pro)").font(.headline)
            Text("sel9 with exact output size + scalar variants").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v36")
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

    private func u64(_ out: [UInt8], _ o: Int) -> UInt64 {
        guard out.count >= o + 8 else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(out[o + i]) << (8 * i) }
        return v
    }

    private func callIOExact(conn: io_connect_t, sel: UInt32, scalars: [UInt64], sdata: [UInt8],
                           outSize: Int) -> (UInt32, [UInt8], [UInt64]) {
        var inScalar = [UInt64](repeating: 0, count: 4)
        for i in 0..<scalars.count { inScalar[i] = scalars[i] }
        var outScalar = [UInt64](repeating: 0, count: 8)
        var outScalarCount: UInt32 = 0
        var outBuff = [UInt8](repeating: 0, count: max(outSize, 1))
        var outSz: Int = outSize
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
        var outBytes = [UInt8](outBuff.prefix(Int(outSz)))
        let os = Array(outScalar.prefix(Int(outScalarCount)))
        return (k, outBytes, os)
    }

    private func idFrom(_ out: [UInt8]) -> UInt32? {
        guard out.count >= 0x1C else { return nil }
        return UInt32(out[0x18]) | (UInt32(out[0x19]) << 8) | (UInt32(out[0x1A]) << 16) | (UInt32(out[0x1B]) << 24)
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
        log("created surface id=\(sid) a0=0x\(String(u64(iOut, 0x00), radix:16))")

        // ---- sel9 variants ----
        log("\n--- sel9 variants ---")
        func sel9PayloadStruct(key: String, value: Any) -> [UInt8] {
            let arr: [Any] = [key, value]
            guard let full = xmlNul(arr), let p = stripNul(full, tag: "array") else { return [] }
            var d = Data()
            withUnsafeBytes(of: sid.littleEndian) { d.append(contentsOf: $0) }
            d.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
            d.append(p)
            return Array(d)
        }
        func sel9PayloadPlistOnly(key: String, value: Any) -> [UInt8] {
            let arr: [Any] = [key, value]
            guard let full = xmlNul(arr), let p = stripNul(full, tag: "array") else { return [] }
            return Array(p)
        }

        // A: struct input header+plist, scalarCount=0, outSz=4
        let (kA, outA, osA) = callIOExact(conn: conn, sel: 9, scalars: [], sdata: sel9PayloadStruct(key: "IOSurfaceName", value: "testname"), outSize: 4)
        log("sel9 struct-in sc0: kr=0x\(String(kA, radix:16)) out=\(outA.map { String(format: "%02x", $0) }.joined()) osc=\(osA.count)")
        if osA.count > 0 { log("  scalar: \(osA.map { String(format: "0x%016llx", $0) }.joined(separator: " "))") }

        // B: struct input header+plist, scalarCount=1 scalar=sid, outSz=4
        var inScalarB = [UInt64](repeating: 0, count: 4)
        inScalarB[0] = UInt64(sid)
        var outScalarB = [UInt64](repeating: 0, count: 8)
        var outScalarCountB: UInt32 = 0
        var outBuffB = [UInt8](repeating: 0, count: 4)
        var outSzB: Int = 4
        let pB = sel9PayloadStruct(key: "IOSurfaceName", value: "testname")
        let krB: Int32 = pB.withUnsafeBytes { raw in
            outBuffB.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, 9,
                                    &inScalarB, 1,
                                    raw.baseAddress, pB.count,
                                    &outScalarB, &outScalarCountB,
                                    ob.baseAddress, &outSzB)
            }
        }
        let kB = UInt32(bitPattern: krB)
        log("sel9 struct-in sc1(sid): kr=0x\(String(kB, radix:16)) out=\(outBuffB.prefix(Int(outSzB)).map { String(format: "%02x", $0) }.joined()) osc=\(outScalarCountB)")
        if outScalarCountB > 0 { log("  scalar: \(outScalarB.prefix(Int(outScalarCountB)).map { String(format: "0x%016llx", $0) }.joined(separator: " "))") }

        // C: plist-only struct input, scalarCount=1 scalar=sid, outSz=4
        var inScalarC = [UInt64](repeating: 0, count: 4)
        inScalarC[0] = UInt64(sid)
        var outScalarC = [UInt64](repeating: 0, count: 8)
        var outScalarCountC: UInt32 = 0
        var outBuffC = [UInt8](repeating: 0, count: 4)
        var outSzC: Int = 4
        let pC = sel9PayloadPlistOnly(key: "IOSurfaceName", value: "testname")
        let krC: Int32 = pC.withUnsafeBytes { raw in
            outBuffC.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, 9,
                                    &inScalarC, 1,
                                    raw.baseAddress, pC.count,
                                    &outScalarC, &outScalarCountC,
                                    ob.baseAddress, &outSzC)
            }
        }
        let kC = UInt32(bitPattern: krC)
        log("sel9 plist-in sc1(sid): kr=0x\(String(kC, radix:16)) out=\(outBuffC.prefix(Int(outSzC)).map { String(format: "%02x", $0) }.joined()) osc=\(outScalarCountC)")
        if outScalarCountC > 0 { log("  scalar: \(outScalarC.prefix(Int(outScalarCountC)).map { String(format: "0x%016llx", $0) }.joined(separator: " "))") }

        // D: scalarCount=0, plist-only input, outSz=4
        let (kD, outD, osD) = callIOExact(conn: conn, sel: 9, scalars: [], sdata: sel9PayloadPlistOnly(key: "IOSurfaceName", value: "testname"), outSize: 4)
        log("sel9 plist-in sc0: kr=0x\(String(kD, radix:16)) out=\(outD.map { String(format: "%02x", $0) }.joined()) osc=\(osD.count)")

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v36 — sel9 exact outSz (13 Pro) ===")

        probeService("IOSurfaceRoot", 0)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
