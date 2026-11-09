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
            Text("AGXProbe v23 — sel11/sel46/sel26").font(.headline)
            Text("proper plist + scalar outputs + struct io").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v23")
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

    private func num(_ v: UInt64) -> Int64 { Int64(bitPattern: v) }

    private func surf(_ alloc: UInt64) -> [String: Any] {
        return [
            "IOSurfaceWidth": 64,
            "IOSurfaceHeight": 64,
            "IOSurfaceBytesPerElement": 4,
            "IOSurfaceBytesPerRow": 256,
            "IOSurfaceAllocSize": num(alloc),
            "IOSurfacePixelFormat": 0x42475241,
            "IOSurfacePlaneInfo": [[
                "IOSurfacePlaneWidth": 64,
                "IOSurfacePlaneHeight": 64,
                "IOSurfacePlaneBytesPerRow": 256,
                "IOSurfacePlaneBytesPerElement": 4,
                "IOSurfacePlaneOffset": num(0),
                "IOSurfacePlaneSize": num(0x4000),
            ]],
        ]
    }

    private func call(conn: io_connect_t, sel: UInt32, tag: String, scalarCount: UInt32,
                      payload: Data, outScalarCount: UInt32, outSize: Int) -> (UInt32, [UInt8], [UInt64]) {
        var inScalar: [UInt64] = [0, 0]
        var outScalar: [UInt64] = [0, 0, 0, 0]
        var out = [UInt8](repeating: 0xCC, count: max(outSize, 1))
        var outLen = outSize
        var osc: UInt32 = outScalarCount
        let kr: kern_return_t = payload.withUnsafeBytes { raw in
            out.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, sel,
                                    &inScalar, scalarCount,
                                    raw.baseAddress, payload.count,
                                    &outScalar, &osc,
                                    ob.baseAddress, &outLen)
            }
        }
        let u = UInt32(bitPattern: kr)
        var hex = ""
        for i in 0..<min(0x20, out.count) {
            if i % 16 == 0 { hex += String(format: "\n    %04x: ", i) }
            hex += String(format: "%02x ", out[i])
        }
        var shex = ""
        for i in 0..<min(4, Int(osc)) { shex += String(format: "%016llx ", outScalar[i]) }
        log(String(format: "%@ sel=%u sc=%u kr=0x%08x in=%lu outLen=0x%x osc=%u[%@]%@",
                   tag, sel, scalarCount, u, payload.count, outLen, osc, shex, hex))
        return (u, out, Array(outScalar.prefix(Int(osc))))
    }

    private func idFrom(_ out: [UInt8]) -> UInt32? {
        guard out.count >= 0x1C else { return nil }
        return UInt32(out[0x18]) | (UInt32(out[0x19]) << 8) | (UInt32(out[0x1A]) << 16) | (UInt32(out[0x1B]) << 24)
    }

    private func u32(_ out: [UInt8], _ o: Int) -> UInt32 {
        guard out.count >= o + 4 else { return 0 }
        return UInt32(out[o]) | (UInt32(out[o+1]) << 8) | (UInt32(out[o+2]) << 16) | (UInt32(out[o+3]) << 24)
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v23 — sel11/sel46/sel26 ===")

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOSurfaceRoot"))
        guard service != 0 else { log("IOSurfaceRoot service = NULL"); status = "Failed"; isRunning = false; return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        log(String(format: "IOServiceOpen type=0 kr=0x%x conn=0x%x", okr, conn))
        guard okr == 0 else { status = "Failed"; isRunning = false; return }
        defer { IOServiceClose(conn) }

        // create surface
        var inScalar: [UInt64] = [0]
        var outScalar: [UInt64] = [0]
        var osc: UInt32 = 0
        var out = [UInt8](repeating: 0xCC, count: 0xC68)
        var outLen: Int = 0xC68
        let pPlist: [String: Any] = surf(0x4000)
        guard let full = xmlNul(pPlist), let pPayload = stripNul(full, tag: "dict") else {
            log("serialize failed"); status = "Failed"; isRunning = false; return
        }
        let kr0: kern_return_t = pPayload.withUnsafeBytes { raw in
            out.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, 0, &inScalar, 1, raw.baseAddress, pPayload.count,
                                    &outScalar, &osc, ob.baseAddress, &outLen)
            }
        }
        let sid = UInt32(bitPattern: kr0) == 0 ? idFrom(out) : nil
        log(String(format: "sel0 kr=0x%08x sid=%@", UInt32(bitPattern: kr0), sid.map { String($0) } ?? "nil"))
        guard let sid = sid else { status = "Failed"; isRunning = false; return }

        // ---- sel11: setValue variant with proper plist ----
        log("\n--- sel11 (setValue variant) ---")
        // sel11 input: 12-byte header (sid u32 + 8 zero) + NUL-terminated plist array [key, value]
        func sel11payload(key: String, value: Any) -> Data {
            let arr: [Any] = [key, value]
            guard let full = xmlNul(arr), let p = stripNul(full, tag: "array") else { return Data() }
            var d = Data()
            withUnsafeBytes(of: sid.littleEndian) { d.append(contentsOf: $0) }
            d.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
            d.append(p)
            return d
        }

        _ = call(conn: conn, sel: 11, tag: "S11 name=string", scalarCount: 0,
                 payload: sel11payload(key: "IOSurfaceName", value: "hello"), outScalarCount: 0, outSize: 4)
        _ = call(conn: conn, sel: 11, tag: "S11 creation=dict", scalarCount: 0,
                 payload: sel11payload(key: "CreationProperties", value: ["foo": "bar"]), outScalarCount: 0, outSize: 4)
        _ = call(conn: conn, sel: 11, tag: "S11 junk=int", scalarCount: 0,
                 payload: sel11payload(key: "Bogus", value: 42), outScalarCount: 0, outSize: 4)

        // ---- sel46: 2 scalar outputs ----
        log("\n--- sel46 (2 scalar outputs) ---")
        _ = call(conn: conn, sel: 46, tag: "S46 out2", scalarCount: 0, payload: Data([0]),
                 outScalarCount: 2, outSize: 0)

        // ---- sel26: struct in/out ----
        log("\n--- sel26 (struct in/out) ---")
        _ = call(conn: conn, sel: 26, tag: "S26 nul-in", scalarCount: 0, payload: Data([0]),
                 outScalarCount: 0, outSize: 0xC68)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
