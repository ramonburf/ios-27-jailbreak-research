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
            Text("AGXProbe v22 — VAR selector sweep").font(.headline)
            Text("sel 11,19,24,26,46,47,48,50,54").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v22")
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
                      payload: Data, outSize: Int) -> (UInt32, [UInt8]) {
        var inScalar: [UInt64] = [0, 0]
        var outScalar: [UInt64] = [0, 0]
        var outScalarCount: UInt32 = 0
        var out = [UInt8](repeating: 0xCC, count: max(outSize, 1))
        var outLen = outSize
        let kr: kern_return_t = payload.withUnsafeBytes { raw in
            out.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, sel,
                                    &inScalar, scalarCount,
                                    raw.baseAddress, payload.count,
                                    &outScalar, &outScalarCount,
                                    ob.baseAddress, &outLen)
            }
        }
        let u = UInt32(bitPattern: kr)
        var hex = ""
        for i in 0..<min(0x20, out.count) {
            if i % 16 == 0 { hex += String(format: "\n    %04x: ", i) }
            hex += String(format: "%02x ", out[i])
        }
        log(String(format: "%@ sel=%u sc=%u kr=0x%08x in=%lu outLen=0x%x%@", tag, sel, scalarCount, u, payload.count, outLen, hex))
        return (u, out)
    }

    private func idFrom(_ out: [UInt8]) -> UInt32? {
        guard out.count >= 0x1C else { return nil }
        return UInt32(out[0x18]) | (UInt32(out[0x19]) << 8) | (UInt32(out[0x1A]) << 16) | (UInt32(out[0x1B]) << 24)
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v22 — VAR selector sweep ===")

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOSurfaceRoot"))
        guard service != 0 else { log("IOSurfaceRoot service = NULL"); status = "Failed"; isRunning = false; return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        log(String(format: "IOServiceOpen type=0 kr=0x%x conn=0x%x", okr, conn))
        guard okr == 0 else { status = "Failed"; isRunning = false; return }
        defer { IOServiceClose(conn) }

        // create a surface to get IDs for sIn>=1 selectors
        let pPlist: [String: Any] = surf(0x4000)
        guard let full = xmlNul(pPlist), let pPayload = stripNul(full, tag: "dict") else {
            log("serialize failed"); status = "Failed"; isRunning = false; return
        }
        var inScalar: [UInt64] = [0]
        var outScalar: [UInt64] = [0]
        var outScalarCount: UInt32 = 0
        var out = [UInt8](repeating: 0xCC, count: 0xC68)
        var outLen = 0xC68
        let kr0: kern_return_t = pPayload.withUnsafeBytes { raw in
            out.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, 0, &inScalar, 1, raw.baseAddress, pPayload.count,
                                    &outScalar, &outScalarCount, ob.baseAddress, &outLen)
            }
        }
        let sid = UInt32(bitPattern: kr0) == 0 ? idFrom(out) : nil
        log(String(format: "sel0 kr=0x%08x sid=%@", UInt32(bitPattern: kr0), sid.map { String($0) } ?? "nil"))

        // selectors to probe: (sel, sIn, stOut)
        let probes: [(UInt32, UInt32, Int)] = [
            (11, 0, 4),
            (19, 0, 0),
            (24, 0, 0),
            (26, 0, 0xC68),
            (46, 0, 0),
            (47, 1, 0),
            (48, 1, 0),
            (50, 2, 0),
            (54, 0, 0),
        ]

        for (sel, sIn, stOut) in probes {
            var scalars: [UInt64] = [0, 0]
            if sIn >= 1 { scalars[0] = UInt64(sid ?? 0) }
            if sIn >= 2 { scalars[1] = UInt64(sid ?? 0) }
            let payload = Data([0])   // just NUL
            _ = call(conn: conn, sel: sel, tag: "sel\(sel)", scalarCount: sIn, payload: payload, outSize: stOut)
        }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
