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
            Text("AGXProbe v26 — arg shape sweep (13 Pro)").font(.headline)
            Text("AGXAcceleratorG14P type=1, sel 0x00-0x0F + 0x100-0x10F").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v26")
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

        let sels: [UInt32] = Array(0x00...0x0F) + Array(0x100...0x10F)
        let shapes: [(String, [UInt64], [UInt8], Int)] = [
            ("sc0/st0", [], [], 32),
            ("sc3/st0", [0x1,0x2,0x3], [], 32),
            ("sc0/st8", [], [0x01,0,0,0,0,0,0,0], 32),
            ("sc3/st8", [0x1,0x2,0x3], [0x01,0,0,0,0,0,0,0], 32),
            ("sc0/st16", [], [UInt8](repeating: 0x01, count: 16), 32),
            ("sc0/st72", [], [UInt8](repeating: 0x01, count: 72), 32),
            ("sc3/st72", [0x1,0x2,0x3], [UInt8](repeating: 0x01, count: 72), 32),
        ]

        var hits = 0
        for sel in sels {
            for (shapeName, scalars, sdata, outSize) in shapes {
                let (k, outSz) = tryShape(conn: conn, sel: sel,
                                          scalars: scalars, sdata: sdata, outSize: outSize)
                if k != 0xe00002c2 {
                    hits += 1
                    log("\(name) t=\(type) sel=0x\(String(sel, radix:16)) \(shapeName) kr=0x\(String(k, radix:16)) outSz=0x\(String(outSz, radix:16))")
                }
            }
        }
        log("\(name) t=\(type): \(hits) non-BadArgument hits")
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v26 — arg shape sweep (13 Pro) ===")

        probeService("AGXAcceleratorG14P", 1)
        probeService("AGXAcceleratorG14P", 0)
        probeService("AGXAcceleratorG13P", 1)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
