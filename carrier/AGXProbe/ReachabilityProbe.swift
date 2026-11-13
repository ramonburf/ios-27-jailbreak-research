//
//  ReachabilityProbe.swift
//  Bench27
//
//  A batch of probes that answer one question together: which kernel entry
//  points can a sandboxed application actually drive on this build?
//
//   95 ?? IOKit service map      ??? every published service, and which clients open
//   96 ?? IOSurfaceRoot methods  ??? the surface user client, selector by selector
//   97 ?? HID reachability       ??? HID services in IOKit and the event-system path
//   98 ?? IOSurface notify race  ??? the teardown window, when reached at all
//

import Foundation

extension XPCProbe {

    // MARK: - helpers

    private func krName(_ kr: kern_return_t) -> String {
        switch kr {
        case 0: return "ok"
        case -536870206: return "BadArgument"
        case -536870201: return "Unsupported"
        case -536870199: return "NotPermitted"
        case -536870207: return "NotPrivileged"
        case -536870212: return "Error"
        case -536870160: return "NotReady"
        case -536870174: return "NotAttached"
        case -536870203: return "Exclusive"
        default: return "kr=\(kr)"
        }
    }

    private func className(_ service: io_service_t) -> String {
        var buffer = [CChar](repeating: 0, count: 128)
        let kr = buffer.withUnsafeMutableBufferPointer { bp -> kern_return_t in
            guard let base = bp.baseAddress else { return kern_return_t(-1) }
            return xq_IOObjectGetClass(service, base)
        }
        guard kr == KERN_SUCCESS else { return "?" }
        return String(cString: buffer)
    }

    /// Opens the service under the first client type that accepts, or returns nil.
    private func openClient(_ service: io_service_t, types: ClosedRange<UInt32> = 0...3) -> (UInt32, io_connect_t)? {
        for type in types {
            var conn: io_connect_t = 0
            if xq_IOServiceOpen(service, mach_task_self_, type, &conn) == KERN_SUCCESS {
                return (type, conn)
            }
        }
        return nil
    }

    private func call(_ conn: io_connect_t, selector: UInt32, inSize: Int, outSize: Int) -> kern_return_t {
        var input = [UInt8](repeating: 0, count: max(inSize, 1))
        var output = [UInt8](repeating: 0, count: max(outSize, 1))
        var outCnt = outSize
        var scalarCount: UInt32 = 0
        var scalars = [UInt64](repeating: 0, count: 4)
        var kr: kern_return_t = -1
        input.withUnsafeBytes { ib in
            output.withUnsafeMutableBytes { ob in
                scalars.withUnsafeMutableBufferPointer { sb in
                    kr = xq_IOConnectCallMethod(conn, selector, nil, 0,
                                                inSize > 0 ? ib.baseAddress : nil, inSize,
                                                sb.baseAddress, &scalarCount,
                                                outSize > 0 ? ob.baseAddress : nil, &outCnt)
                }
            }
        }
        return kr
    }

    // MARK: - 95 ?? every published service, and what opens

    /// Walks the whole IORegistry, records each service's class, and tries to open
    /// a user client. The result is the map of what this sandbox can talk to.
    func bench95ServiceMap() {
        benchLine("??? 95 ?? IOKit service map")

        guard let matching = "IOService".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] matching dictionary"); return
        }
        var iterator: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else {
            benchLine("[NO] the registry cannot be enumerated"); return
        }
        defer { xq_IOObjectRelease(iterator) }

        var total = 0
        var opened: [(String, UInt32)] = []
        var classes = Set<String>()
        let deadline = Date().addingTimeInterval(4.0)

        while true {
            let service = xq_IOIteratorNext(iterator)
            if service == 0 { break }
            defer { xq_IOObjectRelease(service) }
            total += 1
            if Date() > deadline || total > 1200 { break }

            let name = className(service)
            classes.insert(name)
            if let (type, conn) = openClient(service) {
                opened.append((name, type))
                xq_IOServiceClose(conn)
            }
        }

        benchLine("     services seen \(total) ?? distinct classes \(classes.count) ?? openable \(opened.count)")
        for (name, type) in opened.prefix(40) {
            benchLine("          open  \(name) ?? type \(type)")
        }
        let interesting = opened.filter {
            let lower = $0.0.lowercased()
            return lower.contains("hid") || lower.contains("surface") || lower.contains("gpu")
                || lower.contains("agx") || lower.contains("ane") || lower.contains("jpeg")
                || lower.contains("scaler") || lower.contains("ave")
        }
        if !interesting.isEmpty {
            benchLine("     of those, on our candidate list:")
            for (name, type) in interesting { benchLine("          ??? \(name) ?? type \(type)") }
        }
        benchLine("??? done")
    }

    // MARK: - 96 ?? the surface user client, selector by selector

    /// The notification API is not exported by the framework, but the user client
    /// behind it may still be openable. This sweeps its selectors.
    func bench96SurfaceClient() {
        benchLine("??? 96 ?? IOSurfaceRoot user client")

        var found = 0
        for candidate in ["IOSurfaceRoot", "IOSurface", "IOSurfaceRootUserClient"] {
            guard let matching = candidate.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var iterator: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { continue }
            defer { xq_IOObjectRelease(iterator) }

            var service = xq_IOIteratorNext(iterator)
            while service != 0 {
                found += 1
                let name = className(service)
                if let (type, conn) = openClient(service, types: 0...4) {
                    benchLine("     service \(candidate) ?? class \(name) ?? opened type \(type)")

                    var answers: [(UInt32, String)] = []
                    for selector in UInt32(0)...0x30 {
                        var hit: String?
                        for inSize in [0, 8, 0x10, 0x20, 0x40] {
                            for outSize in [0, 0x10, 0x40] {
                                let kr = call(conn, selector: selector, inSize: inSize, outSize: outSize)
                                if kr != -536870206, hit == nil {
                                    hit = "in 0x\(String(inSize, radix: 16))/out 0x\(String(outSize, radix: 16)) ??? \(krName(kr))"
                                }
                            }
                        }
                        if let hit { answers.append((selector, hit)) }
                    }
                    benchLine("     selectors that answered: \(answers.count)")
                    for (selector, text) in answers.prefix(24) {
                        benchLine("          sel 0x\(String(selector, radix: 16)): \(text)")
                    }
                    // The two notification methods the framework uses.
                    for selector in [UInt32(0x11), UInt32(0x12)] {
                        let kr = call(conn, selector: selector, inSize: 0x18, outSize: 0)
                        benchLine("          notify sel 0x\(String(selector, radix: 16)): \(krName(kr))")
                    }
                    xq_IOServiceClose(conn)
                } else {
                    benchLine("     service \(candidate) ?? class \(name) ?? no client type accepted")
                }
                xq_IOObjectRelease(service)
                service = xq_IOIteratorNext(iterator)
            }
        }
        if found == 0 { benchLine("[NO] no surface service is published to this process") }
        benchLine("??? done")
    }

    // MARK: - 97 ?? HID reachability

    /// The 27.2 diff added an index bound inside IOHIDFamily. This asks whether any
    /// HID path is reachable: the IOKit services first, then the event-system API
    /// applications normally use.
    func bench97HIDReach() {
        benchLine("??? 97 ?? HID reachability")

        // IOKit side
        var hidServices: [(String, Bool)] = []
        for candidate in ["IOHIDSystem", "IOHIDEventDriver", "IOHIDResource", "IOHIDDevice",
                          "AppleMultitouchDevice", "IOHIDEventService", "IOHIDInterface"] {
            guard let matching = candidate.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var iterator: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { continue }
            defer { xq_IOObjectRelease(iterator) }
            var service = xq_IOIteratorNext(iterator)
            while service != 0 {
                let name = className(service)
                let opened = openClient(service, types: 0...4)
                if let (type, conn) = opened {
                    benchLine("     \(candidate) ?? class \(name) ?? opened type \(type)")
                    xq_IOServiceClose(conn)
                }
                hidServices.append((name, opened != nil))
                xq_IOObjectRelease(service)
                service = xq_IOIteratorNext(iterator)
            }
        }
        benchLine("     IOKit HID services \(hidServices.count) ?? openable \(hidServices.filter { $0.1 }.count)")

        // Event-system side, the path apps normally take.
        let path = "/System/Library/Frameworks/IOKit.framework/IOKit"
        guard let handle = dlopen(path, RTLD_LAZY) else {
            benchLine("     IOKit does not dlopen"); benchLine("??? done"); return
        }
        defer { dlclose(handle) }

        typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
        typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer) -> CFArray?
        typealias CopyPropertyFn = @convention(c) (UnsafeMutableRawPointer, CFString) -> CFTypeRef?

        guard let createSym = dlsym(handle, "IOHIDEventSystemClientCreate") else {
            benchLine("     IOHIDEventSystemClientCreate absent"); benchLine("??? done"); return
        }
        let create = unsafeBitCast(createSym, to: CreateFn.self)
        guard let client = create(kCFAllocatorDefault) else {
            benchLine("     the event system client was refused"); benchLine("??? done"); return
        }
        benchLine("     IOHIDEventSystemClientCreate: ok")

        if let copySym = dlsym(handle, "IOHIDEventSystemClientCopyServices") {
            let copy = unsafeBitCast(copySym, to: CopyServicesFn.self)
            if let services = copy(client) {
                let count = CFArrayGetCount(services)
                benchLine("     HID services via the event system: \(count)")
                let propertySym = dlsym(handle, "IOHIDServiceClientCopyProperty")
                if let propertySym {
                    let property = unsafeBitCast(propertySym, to: CopyPropertyFn.self)
                    for index in 0..<min(count, 6) {
                        guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
                        let service = UnsafeMutableRawPointer(mutating: raw)
                        let product = property(service, "Product" as CFString) as? String
                        let transport = property(service, "Transport" as CFString) as? String
                        benchLine("          [\(index)] \(product ?? "?") ?? \(transport ?? "?")")
                    }
                }
            } else {
                benchLine("     CopyServices returned nil")
            }
        } else {
            benchLine("     IOHIDEventSystemClientCopyServices absent")
        }

        benchLine("     a reachable HID service is a precondition for the HID candidate")
        benchLine("??? done")
    }

    // MARK: - 98 ?? the notification teardown race

    /// The harness in IOSurfaceNotifyProbe.c: it resolves the private notify entry
    /// points, then races registration against removal.
    ///
    /// A hit is a kernel fault ??? the device can panic.
    func bench98NotifyRace() {
        benchLine("??? 98 ?? IOSurface notify race")
        benchLine("     this races a teardown; a hit is a kernel fault, not a kr")
        run_iosurface_notify_probe()
        benchLine("     the probe returned ?? the process is still here")
        benchLine("??? done")
    }
    // MARK: - 99 ?? the shape of the surface notification methods

    /// Selectors 0x11 and 0x12 on IOSurfaceRoot answer BadArgument, which means the
    /// dispatch entry exists and only the input is wrong. This sweeps scalar counts
    /// and struct layouts for both.
    func bench99SurfaceNotifyShape() {
        benchLine("??? 99 ?? surface notify input shape")

        guard let matching = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return }
        var iterator: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return }
        defer { xq_IOObjectRelease(iterator) }
        let service = xq_IOIteratorNext(iterator)
        guard service != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(service) }

        guard let (_, conn) = openClient(service, types: 0...2) else {
            benchLine("[NO] the client does not open"); return
        }
        defer { xq_IOServiceClose(conn) }

        guard let handle = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_LAZY) else {
            benchLine("[NO] framework"); return
        }
        defer { dlclose(handle) }
        typealias CreateFn = @convention(c) (CFDictionary) -> UnsafeMutableRawPointer?
        typealias GetIDFn = @convention(c) (UnsafeMutableRawPointer) -> UInt32
        guard let createSym = dlsym(handle, "IOSurfaceCreate"),
              let idSym = dlsym(handle, "IOSurfaceGetID") else {
            benchLine("[NO] symbols"); return
        }
        let create = unsafeBitCast(createSym, to: CreateFn.self)
        let getID = unsafeBitCast(idSym, to: GetIDFn.self)

        let props = [
            "IOSurfaceWidth": 64, "IOSurfaceHeight": 64,
            "IOSurfaceBytesPerElement": 4,
        ] as CFDictionary
        guard let surface = create(props) else {
            benchLine("[NO] surface"); return
        }
        let surfaceID = UInt32(getID(surface))
        var port: mach_port_t = 0
        _ = mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &port)
        benchLine("     surface id 0x\(String(surfaceID, radix: 16)) ?? port 0x\(String(port, radix: 16))")

        func callScalars(_ selector: UInt32, _ scalars: [UInt64], outSize: Int) -> kern_return_t {
            var out = [UInt8](repeating: 0, count: max(outSize, 1))
            var outCnt = outSize
            var answer = [UInt64](repeating: 0, count: 4)
            var count: UInt32 = 0
            var kr: kern_return_t = -1
            out.withUnsafeMutableBytes { ob in
                answer.withUnsafeMutableBufferPointer { ab in
                    kr = xq_IOConnectCallMethod(conn, selector,
                                                scalars.isEmpty ? nil : scalars, UInt32(scalars.count),
                                                nil, 0,
                                                ab.baseAddress, &count,
                                                outSize > 0 ? ob.baseAddress : nil, &outCnt)
                }
            }
            return kr
        }

        func callStruct(_ selector: UInt32, _ bytes: [UInt8], outSize: Int) -> kern_return_t {
            var out = [UInt8](repeating: 0, count: max(outSize, 1))
            var outCnt = outSize
            var answer = [UInt64](repeating: 0, count: 4)
            var count: UInt32 = 0
            var kr: kern_return_t = -1
            bytes.withUnsafeBytes { ib in
                out.withUnsafeMutableBytes { ob in
                    answer.withUnsafeMutableBufferPointer { ab in
                        kr = xq_IOConnectCallMethod(conn, selector, nil, 0,
                                                    ib.baseAddress, bytes.count,
                                                    ab.baseAddress, &count,
                                                    outSize > 0 ? ob.baseAddress : nil, &outCnt)
                    }
                }
            }
            return kr
        }

        let id64 = UInt64(surfaceID)
        let port64 = UInt64(port)
        let kind: UInt64 = 1

        for selector in [UInt32(0x11), UInt32(0x12)] {
            benchLine("     selector 0x\(String(selector, radix: 16))")
            var hits = 0
            let orders: [[UInt64]] = [
                [id64], [port64], [kind],
                [id64, kind], [kind, id64], [id64, port64], [port64, id64],
                [port64, kind], [kind, port64],
                [id64, kind, port64], [id64, port64, kind], [port64, kind, id64],
                [kind, id64, port64], [port64, id64, kind], [kind, port64, id64],
            ]
            for scalars in orders {
                for outSize in [0, 8, 0x10] {
                    let kr = callScalars(selector, scalars, outSize: outSize)
                    if kr != -536870206 {
                        hits += 1
                        benchLine("          scalars \(scalars.count) out 0x\(String(outSize, radix: 16)) ??? \(krName(kr))")
                    }
                }
            }
            for size in [0x8, 0x10, 0x18, 0x20] {
                for layout in 0...2 {
                    var bytes = [UInt8](repeating: 0, count: size)
                    func put(_ value: UInt64, at offset: Int, wide: Bool) {
                        guard offset + (wide ? 8 : 4) <= size else { return }
                        if wide {
                            for i in 0..<8 { bytes[offset + i] = UInt8((value >> (8 * UInt64(i))) & 0xFF) }
                        } else {
                            let v = UInt32(truncatingIfNeeded: value)
                            for i in 0..<4 { bytes[offset + i] = UInt8((v >> (8 * UInt32(i))) & 0xFF) }
                        }
                    }
                    switch layout {
                    case 0:
                        put(id64, at: 0, wide: size >= 0x10)
                        put(kind, at: size >= 0x10 ? 8 : 4, wide: size >= 0x10)
                        if size >= 0x18 { put(port64, at: 0x10, wide: true) }
                    case 1:
                        put(kind, at: 0, wide: size >= 0x10)
                        put(id64, at: size >= 0x10 ? 8 : 4, wide: size >= 0x10)
                        if size >= 0x18 { put(port64, at: 0x10, wide: true) }
                    default:
                        put(port64, at: 0, wide: size >= 0x10)
                        put(id64, at: size >= 0x10 ? 8 : 4, wide: size >= 0x10)
                        if size >= 0x18 { put(kind, at: 0x10, wide: true) }
                    }
                    let kr = callStruct(selector, bytes, outSize: 0x10)
                    if kr != -536870206 {
                        hits += 1
                        benchLine("          struct 0x\(String(size, radix: 16)) layout \(layout) ??? \(krName(kr))")
                    }
                }
            }
            if hits == 0 { benchLine("          every shape BadArgument") }
        }
        benchLine("??? done")
    }

    // MARK: - 100 ?? HID user client selectors

    /// Seventy-nine HID event services accept a client. This sweeps their selectors
    /// and reports the ones that answer anything other than BadArgument.
    func bench100HIDSelectors() {
        benchLine("??? 100 ?? HID client selectors")

        guard let matching = "IOHIDEventService".withCString({ xq_IOServiceMatching($0) }) else { return }
        var iterator: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return }
        defer { xq_IOObjectRelease(iterator) }

        var examined = 0
        let deadline = Date().addingTimeInterval(5.0)
        var service = xq_IOIteratorNext(iterator)
        while service != 0 && examined < 6 && Date() < deadline {
            let name = className(service)
            if let (type, conn) = openClient(service, types: 0...3) {
                examined += 1
                benchLine("     \(name) ?? type \(type)")

                var answers: [(UInt32, String)] = []
                for selector in UInt32(0)...0x30 {
                    var hit: String?
                    for inSize in [0, 8, 0x10, 0x18, 0x20, 0x40] {
                        for outSize in [0, 0x8, 0x40] {
                            let kr = call(conn, selector: selector, inSize: inSize, outSize: outSize)
                            if kr != -536870206, hit == nil {
                                hit = "in 0x\(String(inSize, radix: 16))/out 0x\(String(outSize, radix: 16)) ??? \(krName(kr))"
                            }
                        }
                    }
                    if let hit { answers.append((selector, hit)) }
                }
                benchLine("          selectors answering: \(answers.count)")
                for (selector, text) in answers.prefix(16) {
                    benchLine("               sel 0x\(String(selector, radix: 16)): \(text)")
                }
                xq_IOServiceClose(conn)
            }
            xq_IOObjectRelease(service)
            service = xq_IOIteratorNext(iterator)
        }
        benchLine("     services examined \(examined)")
        benchLine("??? done")
    }

    // MARK: - 101 ?? the ANE load balancer

    /// `H1xANELoadBalancer` opened under client type 1 in the service map. This asks
    /// what its selectors answer.
    func bench101ANELoadBalancer() {
        benchLine("??? 101 ?? ANE load balancer")

        guard let matching = "H1xANELoadBalancer".withCString({ xq_IOServiceMatching($0) }) else { return }
        var iterator: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return }
        defer { xq_IOObjectRelease(iterator) }
        let service = xq_IOIteratorNext(iterator)
        guard service != 0 else { benchLine("[NO] service"); return }
        defer { xq_IOObjectRelease(service) }

        guard let (type, conn) = openClient(service, types: 0...4) else {
            benchLine("     no client type accepted"); benchLine("??? done"); return
        }
        benchLine("     class \(className(service)) ?? type \(type)")

        var answers: [(UInt32, String)] = []
        for selector in UInt32(0)...0x20 {
            var hit: String?
            for inSize in [0, 8, 0x10, 0x18, 0x20, 0x40] {
                for outSize in [0, 0x8, 0x40] {
                    let kr = call(conn, selector: selector, inSize: inSize, outSize: outSize)
                    if kr != -536870206, hit == nil {
                        hit = "in 0x\(String(inSize, radix: 16))/out 0x\(String(outSize, radix: 16)) ??? \(krName(kr))"
                    }
                }
            }
            if let hit { answers.append((selector, hit)) }
        }
        benchLine("     selectors answering: \(answers.count)")
        for (selector, text) in answers.prefix(20) {
            benchLine("          sel 0x\(String(selector, radix: 16)): \(text)")
        }
        xq_IOServiceClose(conn)
        benchLine("??? done")
    }
    // MARK: - shared: exact-size search

    /// IOExternalMethodDispatch2022 compares the input and output sizes exactly, so
    /// a method that exists answers BadArgument for every wrong size. This walks
    /// input sizes byte by byte and reports the first that is accepted.
    private func searchInSize(_ conn: io_connect_t, selector: UInt32,
                              upTo limit: Int, outSizes: [Int] = [0, 8, 0x10]) -> [(Int, Int, kern_return_t)] {
        var hits: [(Int, Int, kern_return_t)] = []
        var size = 0
        while size <= limit {
            for outSize in outSizes {
                let kr = call(conn, selector: selector, inSize: size, outSize: outSize)
                if kr != -536870206 {
                    hits.append((size, outSize, kr))
                }
            }
            size += 4
        }
        return hits
    }

    // MARK: - 102 ?? the exact shape of the surface methods

    /// Test 99 tried plausible layouts and every one was rejected. This walks the
    /// input size from 0 to 0x100 for every selector on the surface client, on each
    /// client type, and prints the sizes that are actually accepted.
    func bench102SurfaceExactSizes() {
        benchLine("??? 102 ?? IOSurfaceRoot exact method sizes")

        guard let matching = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return }
        var iterator: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return }
        defer { xq_IOObjectRelease(iterator) }
        let service = xq_IOIteratorNext(iterator)
        guard service != 0 else { benchLine("[NO] service"); return }
        defer { xq_IOObjectRelease(service) }

        for type in UInt32(0)...3 {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(service, mach_task_self_, type, &conn) == KERN_SUCCESS else {
                benchLine("     type \(type): does not open")
                continue
            }
            benchLine("     type \(type): open, walking selectors")
            var accepted = 0
            for selector in UInt32(0)...0x30 {
                let hits = searchInSize(conn, selector: selector, upTo: 0x80)
                if !hits.isEmpty {
                    accepted += 1
                    let text = hits.prefix(4).map { "in 0x\(String($0.0, radix: 16))/out 0x\(String($0.1, radix: 16)) ??? \(krName($0.2))" }
                    benchLine("          sel 0x\(String(selector, radix: 16)): \(text.joined(separator: " ?? "))")
                }
            }
            benchLine("          accepted selectors on type \(type): \(accepted)")
            xq_IOServiceClose(conn)
        }
        benchLine("??? done")
    }

    // MARK: - 103 ?? HID, on the drivers rather than the sensors

    /// The first six HID services are temperature sensors that answer nothing. This
    /// picks the event drivers by class name and walks their selectors the same way.
    func bench103HIDDrivers() {
        benchLine("??? 103 ?? HID event drivers, exact sizes")

        let wanted = ["IOHIDEventDriver", "AppleSPUHIDDriver", "AppleSphinxProxHIDEventDriver",
                      "AppleM68Buttons", "EXBrightKext"]
        for name in wanted {
            guard let matching = name.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var iterator: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { continue }
            defer { xq_IOObjectRelease(iterator) }
            var service = xq_IOIteratorNext(iterator)
            var done = false
            while service != 0 && !done {
                let klass = className(service)
                if let (type, conn) = openClient(service, types: 0...3) {
                    done = true
                    benchLine("     \(klass) ?? type \(type)")
                    var accepted = 0
                    for selector in UInt32(0)...0x24 {
                        let hits = searchInSize(conn, selector: selector, upTo: 0x60)
                        if !hits.isEmpty {
                            accepted += 1
                            let text = hits.prefix(3).map { "in 0x\(String($0.0, radix: 16))/out 0x\(String($0.1, radix: 16)) ??? \(krName($0.2))" }
                            benchLine("          sel 0x\(String(selector, radix: 16)): \(text.joined(separator: " ?? "))")
                        }
                    }
                    benchLine("          accepted selectors: \(accepted)")
                    xq_IOServiceClose(conn)
                }
                xq_IOObjectRelease(service)
                service = xq_IOIteratorNext(iterator)
            }
        }
        benchLine("??? done")
    }

    // MARK: - 104 ?? what the ANE load balancer does with selector 1

    /// Selector 1 answered `ok` with no arguments at all. This asks what it returns
    /// and whether its neighbours behave the same way.
    func bench104ANELoadBalancerDeep() {
        benchLine("??? 104 ?? ANE load balancer in detail")

        guard let matching = "H1xANELoadBalancer".withCString({ xq_IOServiceMatching($0) }) else { return }
        var iterator: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return }
        defer { xq_IOObjectRelease(iterator) }
        let service = xq_IOIteratorNext(iterator)
        guard service != 0 else { benchLine("[NO] service"); return }
        defer { xq_IOObjectRelease(service) }

        for type in UInt32(0)...3 {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(service, mach_task_self_, type, &conn) == KERN_SUCCESS else { continue }
            benchLine("     type \(type): open")
            for selector in UInt32(0)...0x0c {
                let hits = searchInSize(conn, selector: selector, upTo: 0x40, outSizes: [0, 8, 0x10, 0x40])
                if !hits.isEmpty {
                    let text = hits.prefix(3).map { "in 0x\(String($0.0, radix: 16))/out 0x\(String($0.1, radix: 16)) ??? \(krName($0.2))" }
                    benchLine("          sel 0x\(String(selector, radix: 16)): \(text.joined(separator: " ?? "))")
                }
            }
            // Ask what selector 1 returns, if it answers.
            var output = [UInt64](repeating: 0, count: 8)
            var count: UInt32 = 8
            var bytes = [UInt8](repeating: 0, count: 0x40)
            var bytesCount = 0x40
            let kr = output.withUnsafeMutableBufferPointer { ob in
                bytes.withUnsafeMutableBytes { bb in
                    xq_IOConnectCallMethod(conn, 1, nil, 0, nil, 0,
                                           ob.baseAddress, &count,
                                           bb.baseAddress, &bytesCount)
                }
            }
            if kr == KERN_SUCCESS {
                let scalars = output.prefix(Int(count)).map { String($0, radix: 16) }.joined(separator: ", ")
                benchLine("          selector 1 answered: scalars [\(scalars)] ?? bytes \(bytesCount)")
            }
            xq_IOServiceClose(conn)
        }
        benchLine("??? done")
    }
    // MARK: - 105 ?? HID properties, the path the event system actually uses

    /// The HID user clients open but expose no external methods (test 103). The path
    /// applications really use is the event system: it sends properties to the
    /// drivers over Mach. This pushes values of our choosing at every HID service and
    /// records what the kernel answers.
    ///
    /// Property injection can upset the HID stack; the device may misbehave.
    func bench105HIDProperties() {
        benchLine("??? 105 ?? HID property injection")

        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            benchLine("[NO] IOKit"); return
        }
        defer { dlclose(handle) }

        typealias CreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
        typealias CopyServicesFn = @convention(c) (UnsafeMutableRawPointer) -> CFArray?
        typealias SetPropertyFn = @convention(c) (UnsafeMutableRawPointer, CFString, CFTypeRef?) -> Void
        typealias CopyPropertyFn = @convention(c) (UnsafeMutableRawPointer, CFString) -> CFTypeRef?

        guard let createSym = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let copySym = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let setSym = dlsym(handle, "IOHIDServiceClientSetProperty") else {
            benchLine("     the event-system symbols are not all present"); return
        }
        let create = unsafeBitCast(createSym, to: CreateFn.self)
        let copy = unsafeBitCast(copySym, to: CopyServicesFn.self)
        let setProperty = unsafeBitCast(setSym, to: SetPropertyFn.self)
        let copyProperty: CopyPropertyFn? = dlsym(handle, "IOHIDServiceClientCopyProperty").map {
            unsafeBitCast($0, to: CopyPropertyFn.self)
        }

        guard let client = create(kCFAllocatorDefault), let services = copy(client) else {
            benchLine("[NO] no client or no services"); return
        }
        let count = CFArrayGetCount(services)
        benchLine("     services \(count) ?? setProperty present ?? copyProperty \(copyProperty != nil)")

        // Keys a driver is likely to read, and values that stress an index.
        let keys = ["ReportInterval", "InputMode", "PrimaryUsage", "PrimaryUsagePage",
                    "MaxInputReportSize", "MaxOutputReportSize", "DeviceUsagePairs",
                    "ProductID", "VendorID", "Transport"]
        let numbers: [NSNumber] = [0, 1, 2, 0xFFFF, 0xFFFFFFFF, -1, 0x7FFFFFFF]

        var sent = 0
        var before: [(Int, String, String)] = []

        for index in 0..<min(count, 8) {
            guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = UnsafeMutableRawPointer(mutating: raw)

            // Record what the service reports before we touch it.
            if let copyProperty {
                for key in ["Product", "Transport", "PrimaryUsagePage"] {
                    if let value = copyProperty(service, key as CFString) {
                        before.append((index, key, "\(value)"))
                    }
                }
            }

            for key in keys {
                for number in numbers {
                    setProperty(service, key as CFString, number)
                    sent += 1
                }
                setProperty(service, key as CFString, "bench27" as CFString)
                sent += 1
            }
        }

        benchLine("     properties written \(sent) across \(min(count, 8)) services")
        for (index, key, value) in before.prefix(6) {
            benchLine("          before [\(index)] \(key) = \(value)")
        }

        // Re-read after the writes, so a change or a refusal is visible.
        var after: [(Int, String, String)] = []
        if let copyProperty {
            for index in 0..<min(count, 8) {
                guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
                let service = UnsafeMutableRawPointer(mutating: raw)
                for key in ["Product", "Transport", "PrimaryUsagePage"] {
                    if let value = copyProperty(service, key as CFString) {
                        after.append((index, key, "\(value)"))
                    }
                }
            }
        }
        benchLine("     after the writes:")
        for (index, key, value) in after.prefix(6) {
            benchLine("          after  [\(index)] \(key) = \(value)")
        }
        benchLine("     the process survived the property writes")
        benchLine("??? done")
    }

    // MARK: - 106 ?? exact sizes on the media drivers

    /// The JPEG and Scaler clients open, but their selectors reject the shapes we
    /// tried earlier. This walks the input size for every selector on both.
    func bench106MediaExactSizes() {
        benchLine("??? 106 ?? JPEG and Scaler exact method sizes")

        for className in ["AppleJPEGDriver", "AppleM2ScalerCSCDriver"] {
            guard let matching = className.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var iterator: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { continue }
            defer { xq_IOObjectRelease(iterator) }
            let service = xq_IOIteratorNext(iterator)
            guard service != 0 else { benchLine("     \(className): no service"); continue }
            defer { xq_IOObjectRelease(service) }

            guard let (type, conn) = openClient(service, types: 0...2) else {
                benchLine("     \(className): does not open"); continue
            }
            benchLine("     \(className) ?? type \(type)")
            var accepted = 0
            for selector in UInt32(0)...0x28 {
                let hits = searchInSize(conn, selector: selector, upTo: 0x60, outSizes: [0, 8, 0x10, 0x40])
                if !hits.isEmpty {
                    accepted += 1
                    let text = hits.prefix(3).map { "in 0x\(String($0.0, radix: 16))/out 0x\(String($0.1, radix: 16)) ??? \(krName($0.2))" }
                    benchLine("          sel 0x\(String(selector, radix: 16)): \(text.joined(separator: " ?? "))")
                }
            }
            benchLine("          accepted selectors: \(accepted)")
            xq_IOServiceClose(conn)
        }
        benchLine("??? done")
    }

    // MARK: - 107 ?? the key store

    /// `AppleKeyStore` opened under type 0 in the service map. This only asks which
    /// of its selectors answer at all ??? no key material is touched.
    func bench107KeyStore() {
        benchLine("??? 107 ?? AppleKeyStore selectors")

        guard let matching = "AppleKeyStore".withCString({ xq_IOServiceMatching($0) }) else { return }
        var iterator: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, matching, &iterator) == KERN_SUCCESS else { return }
        defer { xq_IOObjectRelease(iterator) }
        let service = xq_IOIteratorNext(iterator)
        guard service != 0 else { benchLine("[NO] service"); return }
        defer { xq_IOObjectRelease(service) }

        guard let (type, conn) = openClient(service, types: 0...2) else {
            benchLine("     does not open"); benchLine("??? done"); return
        }
        benchLine("     type \(type)")
        var accepted = 0
        for selector in UInt32(0)...0x24 {
            let hits = searchInSize(conn, selector: selector, upTo: 0x40, outSizes: [0, 8, 0x10])
            if !hits.isEmpty {
                accepted += 1
                let text = hits.prefix(3).map { "in 0x\(String($0.0, radix: 16))/out 0x\(String($0.1, radix: 16)) ??? \(krName($0.2))" }
                benchLine("          sel 0x\(String(selector, radix: 16)): \(text.joined(separator: " ?? "))")
            }
        }
        benchLine("     accepted selectors: \(accepted)")
        xq_IOServiceClose(conn)
        benchLine("??? done")
    }
}

