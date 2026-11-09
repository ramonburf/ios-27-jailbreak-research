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
            Text("AGXProbe v21 — sel1 release ID space").font(.headline)
            Text("probe sel1 with IDs 0-20 + fresh surface").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v21")
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

    private func call(conn: io_connect_t, sel: UInt32, tag: String, scalar: UInt64,
                      scalarCount: UInt32, payload: Data, outSize: Int) -> UInt32 {
        var inScalar: [UInt64] = [scalar]
        var outScalar: [UInt64] = [0]
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
        log(String(format: "%@ sel=%u scalar=%llu kr=0x%08x", tag, sel, scalar, u))
        return u
    }

    private func release(conn: io_connect_t, tag: String, id: UInt32) {
        var inScalar: [UInt64] = [UInt64(id)]
        var outScalar: [UInt64] = [0]
        var outScalarCount: UInt32 = 0
        let kr = IOConnectCallScalarMethod(conn, 1, &inScalar, 1, &outScalar, &outScalarCount)
        log(String(format: "%@ release id=%u kr=0x%08x", tag, id, UInt32(bitPattern: kr)))
    }

    private func idFrom(_ out: [UInt8]) -> UInt32? {
        guard out.count >= 0x1C else { return nil }
        return UInt32(out[0x18]) | (UInt32(out[0x19]) << 8) | (UInt32(out[0x1A]) << 16) | (UInt32(out[0x1B]) << 24)
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v21 — sel1 release ID space ===")

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOSurfaceRoot"))
        guard service != 0 else { log("IOSurfaceRoot service = NULL"); status = "Failed"; isRunning = false; return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        log(String(format: "IOServiceOpen type=0 kr=0x%x conn=0x%x", okr, conn))
        guard okr == 0 else { status = "Failed"; isRunning = false; return }
        defer { IOServiceClose(conn) }

        log("\n--- sel1 on IDs 0..20 (none created yet) ---")
        for id in 0...20 {
            release(conn: conn, tag: "id \(id)", id: UInt32(id))
        }

        log("\n--- create fresh surface, then sel1 its ID ---")
        guard let (_, po) = callAndCreate(conn: conn, tag: "fresh", parent: 0,
                                          surf(0x4000, [plane(off: 0, size: 0x4000)])),
              let pid = idFrom(po) else {
            log("create failed"); status = "Failed"; isRunning = false; return
        }
        log("fresh surface id = \(pid)")
        release(conn: conn, tag: "release fresh \(pid)", id: pid)
        release(conn: conn, tag: "release fresh again \(pid)", id: pid)

        log("\n--- sel1 on fresh+superbuffer child ---")
        var c: [String: Any] = surf(0x4000, [plane(off: 0, size: 0x4000)])
        c["IOSurfaceAllocateFromSuperbuffer"] = 1
        guard let (_, co) = callAndCreate(conn: conn, tag: "child", parent: pid, c),
              let cid = idFrom(co) else {
            log("child create failed"); status = "Failed"; isRunning = false; return
        }
        log("child id = \(cid)")
        release(conn: conn, tag: "release child \(cid)", id: cid)
        release(conn: conn, tag: "release parent \(pid)", id: pid)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }

    private func callAndCreate(conn: io_connect_t, tag: String, parent: UInt32, _ d: [String: Any]) -> (UInt32, [UInt8])? {
        guard let full = xmlNul(d), let p = stripNul(full, tag: "dict") else { return nil }
        var inScalar: [UInt64] = [UInt64(parent)]
        var outScalar: [UInt64] = [0]
        var outScalarCount: UInt32 = 0
        var out = [UInt8](repeating: 0xCC, count: 0xC68)
        var outLen = 0xC68
        let kr: kern_return_t = p.withUnsafeBytes { raw in
            out.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, 0,
                                    &inScalar, 1,
                                    raw.baseAddress, p.count,
                                    &outScalar, &outScalarCount,
                                    ob.baseAddress, &outLen)
            }
        }
        let u = UInt32(bitPattern: kr)
        log(String(format: "%@ create kr=0x%08x", tag, u))
        return u == 0 ? (idFrom(out) ?? 0, out) : nil
    }
}
