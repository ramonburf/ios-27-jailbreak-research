//
//  DVPlayback.swift
//  Bench27
//
//  Plays the crafted Dolby Vision samples and records what happened.
//
//  Purpose: find out WHICH process parses the Dolby Vision RPU on iOS 27.0.1.
//  Two samples are played back to back, identical except for the fourcc of the
//  Dolby Vision configuration box (dvcC vs dvvC), because CoreMedia may accept
//  only one of them. The format description extensions are dumped in full so we
//  can see whether the DV configuration was picked up at all, and under what
//  key name.
//

import AVFoundation
import CoreMedia
import UIKit

final class DVPlayback {

    private let log: (String) -> Void
    private let stage: (String) -> Void

    private var player: AVPlayer?
    private var layer: AVPlayerLayer?
    private var item: AVPlayerItem?

    /// Files bundled with the app, played in order.
    private let samples = ["real_e1"]
    private var index = 0

    init(log: @escaping (String) -> Void, stage: @escaping (String) -> Void) {
        self.log = log
        self.stage = stage
    }

    // MARK: - entry point

    func run(on host: UIView) {
        index = 0
        playNext(on: host)
    }

    private func playNext(on host: UIView) {
        guard index < samples.count else {
            log("[*] all samples played, no crash")
            stage("playback completed")
            return
        }
        let name = samples[index]
        index += 1

        guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else {
            log("[-] \(name).mp4 is not in the app bundle")
            playNext(on: host)
            return
        }
        log("---- \(name).mp4 (\(fileSize(url)) bytes)")

        let asset = AVURLAsset(url: url)
        inspect(asset)

        stage("\(name): creating AVPlayerItem")
        let item = AVPlayerItem(asset: asset)
        self.item = item
        player?.pause()
        layer?.removeFromSuperlayer()

        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.frame = host.bounds
        layer.videoGravity = .resizeAspect
        host.layer.addSublayer(layer)
        self.layer = layer

        stage("\(name): starting playback")
        player.play()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.reportItemState(name)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) { [weak self] in
            guard let self else { return }
            let t = self.item.map { CMTimeGetSeconds($0.currentTime()) } ?? 0
            self.log("[*] \(name): reached \(String(format: "%.2f", t))s - alive")
            self.stage("\(name): completed")
            self.playNext(on: host)
        }
    }

    // MARK: - inspection

    private func inspect(_ asset: AVURLAsset) {
        let tracks = asset.tracks(withMediaType: .video)
        log("[*] video tracks: \(tracks.count)")
        for (i, track) in tracks.enumerated() {
            log("[*] track \(i): \(Int(track.naturalSize.width))x\(Int(track.naturalSize.height)), " +
                "\(String(format: "%.2f", track.nominalFrameRate)) fps")
            for case let fd as CMFormatDescription in track.formatDescriptions {
                log("[+] track \(i) codec fourcc: \(fourCC(CMFormatDescriptionGetMediaSubType(fd)))")

                guard let ext = CMFormatDescriptionGetExtensions(fd) as? [String: Any] else {
                    log("[*] no extensions at all in the format description")
                    continue
                }
                log("[*] extension key count: \(ext.count)")
                for key in ext.keys.sorted() {
                    let value = ext[key]
                    log("      \(key) = \(String(describing: value).prefix(80))")
                }
            }
        }
    }

    private func reportItemState(_ name: String) {
        guard let item = item else { return }
        let status: String
        switch item.status {
        case .readyToPlay: status = "readyToPlay"
        case .failed:      status = "failed"
        case .unknown:     status = "unknown"
        @unknown default:  status = "?"
        }
        log("[*] \(name): item status \(status)")
        if let error = item.error {
            log("[-] \(name): error \(error.localizedDescription)")
        }
    }

    // MARK: - helpers

    private func fourCC(_ code: FourCharCode) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
                     UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        let s = String(bytes: bytes, encoding: .isoLatin1) ?? "????"
        return "\(s) (\(String(format: "0x%08x", code)))"
    }

    private func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}

