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
            Text("AGXProbe v29 — AGX sel 0x4 / 0x103 output dump (13 Pro)").font(.headline)
            Text("outSize sweep + input variation + output hexdump").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v29")
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
                        outSize: Int) -> (UInt32, [UInt8], [UInt64], UInt32) {
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
            withUnsafeBytes(of: v.littleEndian) { b in outBytes.append(contentsOf: b) }
        }
        let os = Array(outScalar.prefix(Int(outScalarCount)))
        return (k, Array(outBytes.prefix(outSz)), os, UInt32(outSz))
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

        for sel: UInt32 in [0x4, 0x103] {
            log("\n--- sel=0x\(String(sel, radix:16)) ---")
            for outSize in [16, 32, 48, 64, 128] {
                for scalars in [[UInt64]]([[], [1], [1,2,3]]) {
                    for sdata in [[UInt8]]([[], [UInt8](repeating: 0x41, count: 16)]) {
                        let (k, out, os, outSz) = callIO(conn: conn, sel: sel, scalars: scalars, sdata: sdata, outSize: outSize)
                        if k != 0xe00002c2 {
                            log("outSz=\(outSize) sc=\(scalars.count) st=\(sdata.count) kr=0x\(String(k, radix:16)) outSz_ret=\(outSz) osc=\(os.count)")
                            if k == 0 && out.count > 0 {
                                log(hexDump(out))
                            }
                            if os.count > 0 {
                                let osStr = os.map { String(format: "0x%016llx", $0) }.joined(separator: " ")
                                log("  outScalar: \(osStr)")
                            }
                        }
                    }
                }
            }
        }

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v29 — AGX sel 0x4 / 0x103 output dump (13 Pro) ===")

        probeService("AGXAcceleratorG18P", 1)
        probeService("AGXAcceleratorG18P", 0)
        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
