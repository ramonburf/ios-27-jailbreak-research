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
            Text("AGXProbe v25 — AGX dispatch surface (13 Pro)").font(.headline)
            Text("AGXAcceleratorG14P + AGXDeviceUserClient").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v25")
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

        // Selectors to test: dispatch-table range + low range
        let sels: [UInt32] = [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,
                              0x100,0x101,0x102,0x103,0x104,0x105,0x110]
        for sel in sels {
            // minimal: no scalar, 1-byte struct input
            var sdata: [UInt8] = [0x01]
            var outBuff = [UInt64](repeating: 0, count: 4)
            var outSz: Int = outBuff.count * MemoryLayout<UInt64>.stride
            let kr: Int32 = sdata.withUnsafeBytes { raw in
                outBuff.withUnsafeMutableBytes { ob in
                    IOConnectCallMethod(conn, sel,
                                        nil, 0,
                                        raw.baseAddress, raw.count,
                                        nil, nil,
                                        ob.baseAddress, &outSz)
                }
            }
            let k = UInt32(bitPattern: kr)
            if k != 0xe00002c2 {
                log("\(name) t=\(type) sel=0x\(String(sel, radix:16)) kr=0x\(String(k, radix:16)) outSz=0x\(String(outSz, radix:16))")
            }
        }
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v25 — AGX dispatch surface (13 Pro) ===")

        probeService("AGXAcceleratorG14P", 0)
        probeService("AGXAcceleratorG14P", 1)
        probeService("AGXDeviceUserClient", 0)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
