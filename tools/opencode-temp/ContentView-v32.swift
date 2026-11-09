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
            Text("AGXProbe v32 — sel11/sel10 prop round-trip (13 Pro)").font(.headline)
            Text("setValue then getValue property test").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v32")
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

    private func xmlNul(_ d: Any) -> Data? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0) else { return nil }
        return data + Data([0])
    }

    private func stripNul(_ data: Data, tag: String) -> Data? {
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        guard let a = s.range(of: "<\(tag)"),
              let b = s.range(of: "</\(tag)>", options: .backwards) else { return nil }
        return (String(s[a.lowerBound..<b.upperBound]).data(using: .utf8) ?? Data()) + Data([0])
    }

    private func callIO(conn: io_connect_t, sel: UInt32, scalars: [UInt64], sdata: [UInt8],
                        outSize: Int) -> (UInt32, [UInt8], [UInt64]) {
        var inScalar = [UInt64](repeating: 0, count: 4)
        for i in 0..<scalars.count { inScalar[i] = scalars[i] }
        var outScalar = [UInt64](repeating: 0, count: 8)
        var outScalarCount: UInt32 = 0
        var outBuff = [UInt64](repeating: 0, count: outSize / 8)
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
        log("created surface id=\(sid)")

        // ---- sel11: setValue with various types ----
        func sel11Payload(key: String, value: Any) -> Data {
            let arr: [Any] = [key, value]
            guard let full = xmlNul(arr), let p = stripNul(full, tag: "array") else { return Data() }
            var d = Data()
            withUnsafeBytes(of: sid.littleEndian) { d.append(contentsOf: $0) }
            d.append(contentsOf: [0,0,0,0,0,0,0,0])
            d.append(p)
            return d
        }

        log("\n--- sel11 setValue round-trip ---")
        let testCases: [(String, String, Any)] = [
            ("string", "testKey", "testValue"),
            ("dict", "testDict", ["foo": "bar", "num": 42]),
            ("int", "testInt", 12345),
            ("array", "testArr", [1, 2, 3]),
            ("bool", "testBool", true),
        ]
        for (label, key, value) in testCases {
            let p = Array(sel11Payload(key: key, value: value))
            let (k, out, os) = callIO(conn: conn, sel: 11, scalars: [], sdata: p, outSize: 4)
            log("sel11 \(label): kr=0x\(String(k, radix:16)) out=\(out.map { String(format: "%02x", $0) }.joined())")
        }

        // ---- sel10: getValue ----
        log("\n--- sel10 getValue round-trip ---")
        func sel10Payload(key: String) -> Data {
            var d = Data()
            withUnsafeBytes(of: sid.littleEndian) { d.append(contentsOf: $0) }
            d.append(contentsOf: [0,0,0,0,0,0,0,0])
            d.append(contentsOf: key.utf8)
            d.append(0) // NUL terminator
            return d
        }

        for (label, key, _) in testCases {
            let p = Array(sel10Payload(key: key))
            let (k, out, os) = callIO(conn: conn, sel: 10, scalars: [], sdata: p, outSize: 256)
            if k == 0 && out.count > 0 {
                let hex = out.map { String(format: "%02x", $0) }.joined()
                let ascii = out.map { $0 >= 32 && $0 < 127 ? String(UnicodeScalar($0)) : "." }.joined()
                log("sel10 \(label): kr=0x\(String(k, radix:16)) outSz=\(out.count) hex=\(hex) ascii=\(ascii)")
            } else {
                log("sel10 \(label): kr=0x\(String(k, radix:16)) outSz=\(out.count)")
            }
        }

        // ---- sel10 on non-existent key ----
        let p = Array(sel10Payload(key: "NonExistentKey"))
        let (k, out, _) = callIO(conn: conn, sel: 10, scalars: [], sdata: p, outSize: 256)
        log("sel10 non-existent: kr=0x\(String(k, radix:16)) outSz=\(out.count)")

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v32 — sel11/sel10 prop round-trip (13 Pro) ===")

        probeService("IOSurfaceRoot", 0)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
