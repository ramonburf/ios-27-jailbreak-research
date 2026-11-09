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
            Text("AGXProbe v28 — AGX output analysis (13 Pro)").font(.headline)
            Text("sel=0x4 and sel=0x103 output dumping").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v28")
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
            outBytes.append(UInt8(v & 0xFF))
            outBytes.append(UInt8((v >> 8) & 0xFF))
            outBytes.append(UInt8((v >> 16) & 0xFF))
            outBytes.append(UInt8((v >> 24) & 0xFF))
            outBytes.append(UInt8((v >> 32) & 0xFF))
            outBytes.append(UInt8((v >> 40) & 0xFF))
            outBytes.append(UInt8((v >> 48) & 0xFF))
            outBytes.append(UInt8((v >> 56) & 0xFF))
        }
        let os = Array(outScalar.prefix(Int(outScalarCount)))
        return (k, Array(outBytes.prefix(outSz)), os)
    }

    private func hexDump(_ data: [UInt8]) -> String {
        var s = ""
        for i in stride(from: 0, to: data.count, by: 16) {
            s += String(format: "  %04x: ", i)
            for j in 0..<min(16, data.count - i) {
                s += String(format: "%02x ", data[i + j])
            }
            s += "\n"
        }
        return s
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

        // sel=0x4 with various shapes
        log("\n--- sel=0x4 ---")
        for scalars in [[UInt64]]([[], [1], [1,2,3], [0x41,0x42,0x43]]) {
            for sdata in [[UInt8]]([[], [0x01], [0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48]]) {
                let (k, out, os) = callIO(conn: conn, sel: 0x4, scalars: scalars, sdata: sdata, outSize: 256)
                log("sc=\(scalars.count) st=\(sdata.count) kr=0x\(String(k, radix:16)) outSz=\(out.count) osc=\(os.count)")
                if k == 0 && out.count > 0 {
                    log(hexDump(Array(out)))
                }
                if os.count > 0 {
                    let osStr = os.map { String(format: "0x%016llx", $0) }.joined(separator: " ")
                    log("  outScalar: \(osStr)")
                }
            }
        }

        // sel=0x103
        log("\n--- sel=0x103 ---")
        for scalars in [[UInt64]]([[], [1], [1,2,3], [0x41,0x42,0x43]]) {
            for sdata in [[UInt8]]([[], [0x01], [UInt8](repeating: 0x41, count: 16)]) {
                let (k, out, os) = callIO(conn: conn, sel: 0x103, scalars: scalars, sdata: sdata, outSize: 256)
                log("sc=\(scalars.count) st=\(sdata.count) kr=0x\(String(k, radix:16)) outSz=\(out.count) osc=\(os.count)")
                if k == 0 && out.count > 0 {
                    log(hexDump(Array(out.prefix(64))))
                }
                if os.count > 0 {
                    let osStr = os.map { String(format: "0x%016llx", $0) }.joined(separator: " ")
                    log("  outScalar: \(osStr)")
                }
            }
        }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v28 — AGX output analysis (13 Pro) ===")

        probeService("AGXAcceleratorG14P", 1)
        probeService("AGXAcceleratorG14P", 0)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
