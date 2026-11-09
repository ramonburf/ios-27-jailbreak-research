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
            Text("AGXProbe v19 — plane struct + PlaneBase").font(.headline)
            Text("dump per-plane base/size; user-address base test").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v19")
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
    private var ubuf: UnsafeMutableRawPointer?

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

    private func planeFull(off: UInt64, size: UInt64, base: UInt64? = nil) -> [String: Any] {
        var p: [String: Any] = [
            "IOSurfacePlaneWidth": 64,
            "IOSurfacePlaneHeight": 64,
            "IOSurfacePlaneBytesPerRow": 256,
            "IOSurfacePlaneBytesPerElement": 4,
            "IOSurfacePlaneOffset": num(off),
            "IOSurfacePlaneSize": num(size),
        ]
        if let b = base { p["IOSurfacePlaneBase"] = num(b) }
        return p
    }

    private func surf(_ alloc: UInt64, _ planes: [[String: Any]]) -> [String: Any] {
        return [
            "IOSurfaceWidth": 64,
            "IOSurfaceHeight": 64,
            "IOSurfaceBytesPerElement": 4,
            "IOSurfaceBytesPerRow": 256,
            "IOSurfaceAllocSize": num(alloc),
            "IOSurfacePixelFormat": PF_BGRA,
            "IOSurfacePlaneInfo": planes,
        ]
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
        log(String(format: "%@ sel=%u scalar=%llu kr=0x%08x in=%lu outLen=0x%x",
                   tag, sel, scalar, u, payload.count, outLen))
        return out
    }

    private func create(conn: io_connect_t, tag: String, parent: UInt32, _ d: [String: Any]) -> [UInt8]? {
        guard let full = xmlNul(d), let p = stripNul(full, tag: "dict") else {
            log("\(tag): serialize failed"); return nil
        }
        return call(conn: conn, sel: 0, tag: tag, scalar: UInt64(parent), scalarCount: 1, payload: p, outSize: OUT_SIZE)
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

    private func u32(_ out: [UInt8], _ o: Int) -> UInt32 {
        guard out.count >= o + 4 else { return 0 }
        return UInt32(out[o]) | (UInt32(out[o+1]) << 8) | (UInt32(out[o+2]) << 16) | (UInt32(out[o+3]) << 24)
    }

    private func dumpPlanes(_ out: [UInt8], _ tag: String) {
        let n = Int(u32(out, 0x58))
        log("  \(tag): planes=\(n) alloc=0x\(String(u64(out,0x20), radix:16)) planeSize=0x\(String(u64(out,0x50), radix:16))")
        for i in 0..<min(n, 20) {
            let o = 0x88 + i * 0x98
            log(String(format: "    p[%02d] q00=0x%016llx q08=0x%016llx q10=0x%016llx q18=0x%016llx q20=0x%016llx q28=0x%016llx q30=0x%08x",
                       i, u64(out,o), u64(out,o+0x08), u64(out,o+0x10),
                       u64(out,o+0x18), u64(out,o+0x20), u64(out,o+0x28), u32(out,o+0x30)))
        }
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v19 — plane struct + PlaneBase ===")

        ubuf = UnsafeMutableRawPointer.allocate(byteCount: 0x4000, alignment: 0x4000)
        let uaddr = UInt64(UInt(bitPattern: ubuf))
        log("user buffer = 0x\(String(uaddr, radix: 16))")

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOSurfaceRoot"))
        guard service != 0 else { log("IOSurfaceRoot service = NULL"); status = "Failed"; isRunning = false; return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        log(String(format: "IOServiceOpen type=0 kr=0x%x conn=0x%x", okr, conn))
        guard okr == 0 else { status = "Failed"; isRunning = false; return }
        defer { IOServiceClose(conn) }

        if let o = create(conn: conn, tag: "B0 benign 1p", parent: 0, surf(0x4000, [planeFull(off: 0, size: 0x4000)])) {
            dumpPlanes(o, "B0")
        }

        if let o = create(conn: conn, tag: "B1 base=user", parent: 0, surf(0x4000, [planeFull(off: 0, size: 0x4000, base: uaddr)])) {
            dumpPlanes(o, "B1")
        }
        if let o = create(conn: conn, tag: "B2 base=0x1000 sz=0x1000", parent: 0, surf(0x4000, [planeFull(off: 0, size: 0x1000, base: 0x1000)])) {
            dumpPlanes(o, "B2")
        }
        if let o = create(conn: conn, tag: "B3 base=0 sz=0x4000", parent: 0, surf(0x4000, [planeFull(off: 0, size: 0x4000, base: 0)])) {
            dumpPlanes(o, "B3")
        }

        // 20-plane parent
        let pPlanes = (0..<20).map { planeFull(off: UInt64($0) * 0x4000, size: 0x4000) }
        guard let p = create(conn: conn, tag: "P20 parent", parent: 0, surf(0x50000, pPlanes)), let pid = idFrom(p) else {
            log("parent failed"); status = "Failed"; isRunning = false; return
        }
        dumpPlanes(p, "P20 id=\(pid)")

        // child all offset 0
        var cOver: [String: Any] = surf(0x4000, (0..<20).map { _ in planeFull(off: 0, size: 0x4000) })
        cOver["IOSurfaceAllocateFromSuperbuffer"] = 1
        if let o = create(conn: conn, tag: "A10 20x overlap", parent: pid, cOver) { dumpPlanes(o, "A10") }

        // child distinct offsets
        var cDist: [String: Any] = surf(0x4000, (0..<20).map { planeFull(off: UInt64($0) * 0x4000, size: 0x4000) })
        cDist["IOSurfaceAllocateFromSuperbuffer"] = 1
        if let o = create(conn: conn, tag: "A11 20x distinct", parent: pid, cDist) { dumpPlanes(o, "A11") }

        // child 1 plane at 0x4000
        var cOne: [String: Any] = surf(0x4000, [planeFull(off: 0x4000, size: 0x4000)])
        cOne["IOSurfaceAllocateFromSuperbuffer"] = 1
        if let o = create(conn: conn, tag: "A12 1p off=4000", parent: pid, cOne) { dumpPlanes(o, "A12") }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
