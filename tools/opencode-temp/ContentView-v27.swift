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
            Text("AGXProbe v27 — deep shape sweep (13 Pro)").font(.headline)
            Text("AGXAcceleratorG14P type=1, sel 0x100-0x1FF, all shapes").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v27")
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

    private func tryShape(conn: io_connect_t, sel: UInt32,
                          scalars: [UInt64], sdata: [UInt8],
                          outSize: Int) -> (UInt32, Int) {
        var inScalar = [UInt64](repeating: 0, count: 4)
        for i in 0..<scalars.count { inScalar[i] = scalars[i] }
        var outScalar = [UInt64](repeating: 0, count: 5)
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
        return (UInt32(bitPattern: kr), Int(outSz))
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

        let sels: [UInt32] = Array(0x100...0x1FF)
        let shapes: [(String, [UInt64], [UInt8], Int)] = [
            ("sc0/st0", [], [], 32),
            ("sc3/st0", [0x11,0x22,0x33], [], 32),
            ("sc0/st8", [], [UInt8](repeating: 0x41, count: 8), 32),
            ("sc3/st8", [0x11,0x22,0x33], [UInt8](repeating: 0x41, count: 8), 32),
            ("sc0/st16", [], [UInt8](repeating: 0x41, count: 16), 32),
            ("sc3/st16", [0x11,0x22,0x33], [UInt8](repeating: 0x41, count: 16), 32),
            ("sc0/st72", [], [UInt8](repeating: 0x41, count: 72), 32),
            ("sc3/st72", [0x11,0x22,0x33], [UInt8](repeating: 0x41, count: 72), 32),
        ]

        var hits = 0
        for sel in sels {
            var selHits = 0
            for (shapeName, scalars, sdata, outSize) in shapes {
                let (k, outSz) = tryShape(conn: conn, sel: sel,
                                          scalars: scalars, sdata: sdata, outSize: outSize)
                if k != 0xe00002c2 {
                    hits += 1
                    selHits += 1
                    log("\(name) t=\(type) sel=0x\(String(sel, radix:16)) \(shapeName) kr=0x\(String(k, radix:16)) outSz=0x\(String(outSz, radix:16))")
                }
            }
            if selHits > 0 {
                log("  => sel=0x\(String(sel, radix:16)): \(selHits) shape(s) work")
            }
        }
        log("\(name) t=\(type): \(hits) total non-BadArgument hits")
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v27 — deep shape sweep (13 Pro) ===")

        probeService("AGXAcceleratorG14P", 1)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
