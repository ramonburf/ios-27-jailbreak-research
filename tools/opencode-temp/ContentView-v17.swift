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
            Text("AGXProbe v17 — IOSurface edge cases").font(.headline)
            Text("sel0 create fields + sel9 setValue").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v17")
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
    private let OUT_SIZE = 0xC68
    private let PF_BGRA: UInt64 = 0x42475241

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

    private func plane(_ over: [String: Any] = [:]) -> [String: Any] {
        var p: [String: Any] = [
            "IOSurfacePlaneWidth": 64,
            "IOSurfacePlaneHeight": 64,
            "IOSurfacePlaneBytesPerRow": 256,
            "IOSurfacePlaneBytesPerElement": 4,
            "IOSurfacePlaneOffset": 0,
            "IOSurfacePlaneSize": 0x4000,
        ]
        for (k, v) in over { p[k] = v }
        return p
    }

    private func base(_ over: [String: Any] = [:], planeOver: [String: Any] = [:], planes: Int = 1) -> [String: Any] {
        var d: [String: Any] = [
            "IOSurfaceWidth": 64,
            "IOSurfaceHeight": 64,
            "IOSurfaceBytesPerElement": 4,
            "IOSurfaceBytesPerRow": 256,
            "IOSurfaceAllocSize": 0x4000,
            "IOSurfacePixelFormat": PF_BGRA,
            "IOSurfacePlaneInfo": (0..<planes).map { _ in plane(planeOver) },
        ]
        for (k, v) in over { d[k] = v }
        return d
    }

    private func call(conn: io_connect_t, sel: UInt32, tag: String, scalar: UInt64,
                      scalarCount: UInt32, payload: Data, outSize: Int) -> [UInt8] {
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
        var hex = ""
        for i in 0..<min(0x60, out.count) {
            if i % 16 == 0 { hex += String(format: "\n    %04x: ", i) }
            hex += String(format: "%02x ", out[i])
        }
        log(String(format: "%@ sel=%u kr=0x%08x in=%lu outLen=0x%x%@",
                   tag, sel, u, payload.count, outLen, hex))
        return out
    }

    private func create(conn: io_connect_t, tag: String, _ d: [String: Any]) -> [UInt8]? {
        guard let full = xmlNul(d), let p = stripNul(full, tag: "dict") else {
            log("\(tag): serialize failed"); return nil
        }
        return call(conn: conn, sel: 0, tag: tag, scalar: 0, scalarCount: 1, payload: p, outSize: OUT_SIZE)
    }

    private func sel9(conn: io_connect_t, tag: String, surfaceID: UInt32, key: Any, value: Any) {
        let arr: [Any] = [key, value]
        guard let full = xmlNul(arr), let p = stripNul(full, tag: "array") else {
            log("\(tag): serialize failed"); return
        }
        var d = Data()
        withUnsafeBytes(of: surfaceID.littleEndian) { d.append(contentsOf: $0) }
        d.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 0])
        d.append(p)
        _ = call(conn: conn, sel: 9, tag: tag, scalar: 0, scalarCount: 0, payload: d, outSize: 4)
    }

    private func idFrom(_ out: [UInt8]) -> UInt32? {
        guard out.count >= 0x1C else { return nil }
        return UInt32(out[0x18]) | (UInt32(out[0x19]) << 8) | (UInt32(out[0x1A]) << 16) | (UInt32(out[0x1B]) << 24)
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v17 — IOSurface edge cases ===")

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOSurfaceRoot"))
        guard service != 0 else { log("IOSurfaceRoot service = NULL"); status = "Failed"; isRunning = false; return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        log(String(format: "IOServiceOpen type=0 kr=0x%x conn=0x%x", okr, conn))
        guard okr == 0 else { status = "Failed"; isRunning = false; return }
        defer { IOServiceClose(conn) }

        let ctrl = create(conn: conn, tag: "C0 benign", base())
        let sid = ctrl.flatMap(idFrom)
        log("control surface id = \(sid.map { String($0) } ?? "nil")")

        log("\n--- no/empty/many planes ---")
        _ = create(conn: conn, tag: "C1 noPlaneInfo", base(["IOSurfacePlaneInfo": [String: Any]()]))
        _ = create(conn: conn, tag: "C2 emptyPlanes", base(["IOSurfacePlaneInfo": [Any]()]))
        _ = create(conn: conn, tag: "C3 many21", base(planes: 21))
        _ = create(conn: conn, tag: "C4 many64", base(planes: 64))

        log("\n--- scalar extremes ---")
        _ = create(conn: conn, tag: "C5 w0", base(["IOSurfaceWidth": 0]))
        _ = create(conn: conn, tag: "C6 h0", base(["IOSurfaceHeight": 0]))
        _ = create(conn: conn, tag: "C7 bpe0", base(["IOSurfaceBytesPerElement": 0]))
        _ = create(conn: conn, tag: "C8 bpr0", base(["IOSurfaceBytesPerRow": 0]))
        _ = create(conn: conn, tag: "C9 wmax", base(["IOSurfaceWidth": num(0xFFFFFFFF), "IOSurfaceBytesPerRow": num(0xFFFFFFFF)]))
        _ = create(conn: conn, tag: "C10 allocmax", base(["IOSurfaceAllocSize": num(0xFFFFFFFFFFFFFFFF)]))
        _ = create(conn: conn, tag: "C11 alloc0", base(["IOSurfaceAllocSize": 0]))
        _ = create(conn: conn, tag: "C12 pix0", base(["IOSurfacePixelFormat": 0]))

        log("\n--- plane extremes ---")
        _ = create(conn: conn, tag: "C13 offmax", base(planeOver: ["IOSurfacePlaneOffset": num(0xFFFFFFFFFFFFFFFF)]))
        _ = create(conn: conn, tag: "C14 sizemax", base(planeOver: ["IOSurfacePlaneSize": num(0xFFFFFFFFFFFFFFFF)]))
        _ = create(conn: conn, tag: "C15 base1000", base(planeOver: ["IOSurfacePlaneBase": 0x1000, "IOSurfacePlaneSize": 0x4000]))
        _ = create(conn: conn, tag: "C16 baseHuge", base(planeOver: ["IOSurfacePlaneBase": num(0xFFFFFFFFFFFFF000)]))
        _ = create(conn: conn, tag: "C17 baseEnd", base(planeOver: ["IOSurfacePlaneBase": 0x4000, "IOSurfacePlaneSize": 0x4000]))

        log("\n--- address / superbuffer ---")
        _ = create(conn: conn, tag: "C18 addr", base(["IOSurfaceAddress": 0x1000,
                                                      "IOSurfaceAddressRanges": [0x1000, 0x4000] as [Any],
                                                      "IOSurfaceAddressFormat": 0]))
        _ = create(conn: conn, tag: "C19 addrNoRanges", base(["IOSurfaceAddress": 0x1000]))
        _ = create(conn: conn, tag: "C20 superbuffer", base(["IOSurfaceSuperbuffer": 1]))
        _ = create(conn: conn, tag: "C21 allocFromSuper", base(["IOSurfaceAllocateFromSuperbuffer": 1]))

        if let sid = sid {
            log("\n--- sel9 setValue on id \(sid) ---")
            sel9(conn: conn, tag: "S0 name", surfaceID: sid, key: "IOSurfaceName", value: "testname")
            sel9(conn: conn, tag: "S1 creationDict", surfaceID: sid, key: "CreationProperties", value: base())
            sel9(conn: conn, tag: "S2 junkKey", surfaceID: sid, key: "Bogus", value: 1)
        }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
