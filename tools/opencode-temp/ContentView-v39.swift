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
            Text("AGXProbe v39 — AGX full surface sweep (13 Pro)").font(.headline)
            Text("all services × types × selectors × shapes").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v39")
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
        var outBuff = [UInt8](repeating: 0, count: max(outSize, 1))
        var outSz: Int = outSize
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
        var outBytes = [UInt8](outBuff.prefix(Int(outSz)))
        let os = Array(outScalar.prefix(Int(outScalarCount)))
        return (k, outBytes, os)
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

        let sels: [UInt32] = Array(0...255)
        let shapes: [(String, [UInt64], [UInt8])] = [
            ("sc0/st0", [], []),
            ("sc3/st0", [0x11,0x22,0x33], []),
            ("sc0/st8", [], [UInt8](repeating: 0x41, count: 8)),
            ("sc3/st8", [0x11,0x22,0x33], [UInt8](repeating: 0x41, count: 8)),
            ("sc0/st16", [], [UInt8](repeating: 0x41, count: 16)),
            ("sc3/st16", [0x11,0x22,0x33], [UInt8](repeating: 0x41, count: 16)),
        ]

        var hits: [(UInt32, UInt32, UInt32)] = []
        for sel in sels {
            for (shapeName, scalars, sdata) in shapes {
                let (k, out, os) = callIO(conn: conn, sel: sel, scalars: scalars, sdata: sdata, outSize: 32)
                if k != 0xe00002c2 {
                    hits.append((sel, k, UInt32(out.count)))
                    let osStr = os.count > 0 ? " osc=\(os.count)" : ""
                    log("\(name) t=\(type) sel=0x\(String(sel, radix:16)) \(shapeName) kr=0x\(String(k, radix:16)) outSz=\(out.count)\(osStr)")
                    if k == 0 && out.count > 0 && out.count <= 64 {
                        let hex = out.map { String(format: "%02x", $0) }.joined()
                        log("  data: \(hex)")
                    }
                }
            }
        }
        log("\(name) t=\(type): \(hits.count) hits")
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v39 — AGX full surface sweep (13 Pro) ===")

        let services: [(String, UInt32)] = [
            ("AGXAcceleratorG14P", 0),
            ("AGXAcceleratorG14P", 1),
            ("AGXAcceleratorG13P", 0),
            ("AGXAcceleratorG13P", 1),
            ("AGXDeviceUserClient", 0),
            ("AGXDeviceUserClient", 1),
            ("AGXCLChannel", 0),
            ("AGXCLChannel", 1),
            ("AGX3DChannel", 0),
            ("AGX3DChannel", 1),
            ("AGXTAChannel", 0),
            ("AGXTAChannel", 1),
            ("AGXInvalidChannel", 0),
            ("AGXInvalidChannel", 1),
        ]

        for (name, type) in services {
            probeService(name, type)
        }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
