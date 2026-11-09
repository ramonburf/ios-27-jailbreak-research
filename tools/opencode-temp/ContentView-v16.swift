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
            Text("AGXProbe v16 — sel0 NUL-terminated XML").font(.headline)
            Text("gate: 1 scalar + structIn(var) + structOut 0xC68").font(.caption2).foregroundColor(.secondary)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runProbe() } }) {
                Text(vm.isRunning ? "Probing..." : "Run v16")
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
    private let PF_BGRA: UInt32 = 0x42475241

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

    // Full XML plist, C-string terminated (the kernel requires buffer[size-1] == 0).
    private func xmlNul(_ d: [String: Any]) -> Data? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: d, format: .xml, options: 0) else { return nil }
        return data + Data([0])
    }

    // Extract the top-level <dict>..</dict> and NUL-terminate it.
    private func stripDictNul(_ data: Data) -> Data? {
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        guard let a = s.range(of: "<dict"),
              let b = s.range(of: "</dict>", options: .backwards) else { return nil }
        return (String(s[a.lowerBound..<b.upperBound]).data(using: .utf8) ?? Data()) + Data([0])
    }

    private func benign() -> [String: Any] {
        let plane: [String: Any] = [
            "IOSurfacePlaneWidth": 64,
            "IOSurfacePlaneHeight": 64,
            "IOSurfacePlaneBytesPerRow": 256,
            "IOSurfacePlaneBytesPerElement": 4,
            "IOSurfacePlaneOffset": 0,
            "IOSurfacePlaneSize": 0x4000,
        ]
        return [
            "IOSurfaceWidth": 64,
            "IOSurfaceHeight": 64,
            "IOSurfaceBytesPerElement": 4,
            "IOSurfaceBytesPerRow": 256,
            "IOSurfaceAllocSize": 0x4000,
            "IOSurfacePixelFormat": PF_BGRA,
            "IOSurfacePlaneInfo": [plane],
        ]
    }

    private func call(conn: io_connect_t, tag: String, scalar: UInt64,
                      scalarCount: UInt32, payload: Data, outSize: Int) {
        var inScalar: [UInt64] = [scalar]
        var outScalar: [UInt64] = [0]
        var outScalarCount: UInt32 = 0
        var out = [UInt8](repeating: 0xCC, count: max(outSize, 1))
        var outLen = outSize
        let kr: kern_return_t = payload.withUnsafeBytes { raw in
            out.withUnsafeMutableBytes { ob in
                IOConnectCallMethod(conn, 0,
                                    &inScalar, scalarCount,
                                    raw.baseAddress, payload.count,
                                    &outScalar, &outScalarCount,
                                    ob.baseAddress, &outLen)
            }
        }
        let u = UInt32(bitPattern: kr)
        var hex = ""
        for i in 0..<min(0x60, out.count) {
            if i % 16 == 0 { hex += String(format: "\n    %04x: ", i) }
            hex += String(format: "%02x ", out[i])
        }
        log(String(format: "%@ scalar=%llu scCount=%u in=%lu kr=0x%08x outLen=0x%x%@",
                   tag, scalar, scalarCount, payload.count, u, outLen, hex))
    }

    func runProbe() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        log("=== AGXProbe v16 — NUL-terminated XML sel0 ===")
        log("gate: scalarInputCount=1, structInput=VAR, scalarOutputCount=0, structOutputSize=0xC68")

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOSurfaceRoot"))
        guard service != 0 else { log("IOSurfaceRoot service = NULL"); status = "Failed"; isRunning = false; return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let okr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        log(String(format: "IOServiceOpen type=0 kr=0x%x conn=0x%x", okr, conn))
        guard okr == 0 else { status = "Failed"; isRunning = false; return }
        defer { IOServiceClose(conn) }

        guard let fullNul = xmlNul(benign()) else { log("xml failed"); status = "Failed"; isRunning = false; return }
        let fullNoNul = fullNul.dropLast()
        guard let strippedNul = stripDictNul(fullNul) else { log("strip failed"); status = "Failed"; isRunning = false; return }
        let strippedNoNul = strippedNul.dropLast()
        log("fullNul=\(fullNul.count) strippedNul=\(strippedNul.count)")

        // --- gate controls: should be BadArgument (0xe00002c2) ---
        log("\n--- gate controls (expect 0xe00002c2) ---")
        call(conn: conn, tag: "G0 scCount=0 out=0xC68", scalar: 0, scalarCount: 0, payload: strippedNul, outSize: OUT_SIZE)
        call(conn: conn, tag: "G1 scCount=1 out=512  ", scalar: 0, scalarCount: 1, payload: strippedNul, outSize: 512)

        // --- format control: same dict, no NUL vs NUL ---
        log("\n--- format control (expect C2 then reach) ---")
        call(conn: conn, tag: "F0 stripped NO-NUL ", scalar: 0, scalarCount: 1, payload: Data(strippedNoNul), outSize: OUT_SIZE)
        call(conn: conn, tag: "F1 stripped NUL    ", scalar: 0, scalarCount: 1, payload: strippedNul, outSize: OUT_SIZE)

        log("\n--- real sel0 calls ---")
        call(conn: conn, tag: "R0 scalar=0 strip+0", scalar: 0, scalarCount: 1, payload: strippedNul, outSize: OUT_SIZE)
        call(conn: conn, tag: "R1 scalar=1 strip+0", scalar: 1, scalarCount: 1, payload: strippedNul, outSize: OUT_SIZE)
        call(conn: conn, tag: "R2 scalar=0 full+0 ", scalar: 0, scalarCount: 1, payload: fullNul, outSize: OUT_SIZE)
        call(conn: conn, tag: "R3 scalar=0 full-0 ", scalar: 0, scalarCount: 1, payload: Data(fullNoNul), outSize: OUT_SIZE)
        call(conn: conn, tag: "R4 scalar=0 empty  ", scalar: 0, scalarCount: 1, payload: Data(), outSize: OUT_SIZE)
        call(conn: conn, tag: "R5 scalar=0 justNUL", scalar: 0, scalarCount: 1, payload: Data([0]), outSize: OUT_SIZE)
        call(conn: conn, tag: "R6 scalar=0xFF..   ", scalar: 0xFFFFFFFF, scalarCount: 1, payload: strippedNul, outSize: OUT_SIZE)
        call(conn: conn, tag: "R7 scalar=0x1000   ", scalar: 0x1000, scalarCount: 1, payload: strippedNul, outSize: OUT_SIZE)

        log("\n=== done ===")
        status = "Complete"; isRunning = false
    }
}
