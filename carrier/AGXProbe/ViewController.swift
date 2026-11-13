//
//  ViewController.swift
//  Bench27
//
//  A bench for the findings in this repository: one row per direction,
//  each row runs its own probe and reports pass/fail.
//

import UIKit
import VideoToolbox
import Metal

@_cdecl("log_from_c")
public func log_from_c(_ msg: UnsafePointer<CChar>?) {
    guard let msg else { return }
    Logger.shared.log(String(cString: msg))
}

// MARK: - device

enum Device {
    /// Marketing name for a hardware identifier, best effort.
    static func marketingName(_ id: String) -> String {
        let table: [String: String] = [
            "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
            "iPhone14,6": "iPhone SE (3rd gen)",
            "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone15,4": "iPhone 14 Plus", "iPhone15,5": "iPhone 14",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone16,3": "iPhone 15", "iPhone16,4": "iPhone 15 Plus",
            "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",
            "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max",
            "iPhone18,3": "iPhone 17", "iPhone18,4": "iPhone 17 Air",
        ]
        return table[id] ?? id
    }

    /// Hardware identifier, e.g. iPhone18,1.
    static var identifier: String {
        var sys = utsname()
        uname(&sys)
        return withUnsafePointer(to: &sys.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
    }

    /// GPU name without the "Apple" prefix and "GPU" suffix, e.g. A19 Pro.
    static var chip: String {
        let name = MTLCreateSystemDefaultDevice()?.name ?? ""
        return name
            .replacingOccurrences(of: "Apple ", with: "")
            .replacingOccurrences(of: " GPU", with: "")
    }

    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// The configuration this bench was written and verified on.
    static let verifiedSystem = "27.0.1"
    static let verifiedChip = "A19 Pro"

    static var isVerifiedConfiguration: Bool {
        systemVersion == verifiedSystem
    }

    /// "iOS 27.0.1 ?? iPhone 17 Pro ?? A19 Pro"
    static var summary: String {
        "iOS \(systemVersion) ?? \(marketingName(identifier)) ?? \(chip)"
    }
}

// MARK: - logger

/// Writes a timestamped log for the whole session into <Documents>/,
/// one file per launch.
final class Logger {
    static let shared = Logger()

    private var handle: FileHandle?
    private let stamp: DateFormatter
    let logURL: URL
    var sink: ((String) -> Void)?

    private var testLines: [String] = []
    private var inTest = false

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let name = "session-\(f.string(from: Date())).log"
        logURL = docs.appendingPathComponent(name)

        stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss.SSS"

        _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: logURL)

        writeSessionHeader()
    }

    private func writeSessionHeader() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let bundle = Bundle.main.bundleIdentifier ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        var lines = [
            "",
            "========== Bench27 session ==========",
            "started   \(ISO().string(from: Date()))",
            "device    \(Device.marketingName(Device.identifier)) (\(Device.identifier))",
            "chip      \(Device.chip)",
            "system    \(os)",
            "app       \(version) (\(build))",
            "bundle    \(bundle)",
            "log       \(logURL.lastPathComponent)",
            "=====================================",
        ]
        if !Device.isVerifiedConfiguration {
            lines.append("WARNING   this bench was verified on iOS \(Device.verifiedSystem) with \(Device.verifiedChip)")
            lines.append("WARNING   findings may behave differently or not run on this configuration")
        }
        for l in lines { append(l, toScreen: false) }
        append("tests     01 IOSurface ?? 02 Metal ?? 03 FigXPC ?? 04 AVE ?? 05 ANE ?? 06 scan ?? 07 crash ?? 08 panic ?? 09 PDF ?? 10 AGX fields ?? 11 DPB",
               toScreen: false)
    }

    private func ISO() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
        return f
    }

    // MARK: test boundaries

    func beginTest(_ id: String, _ title: String) {
        inTest = true
        testLines.removeAll()
        append("", toScreen: false)
        append("--- TEST \(id) START  \(title)  [\(stamp.string(from: Date()))]")
    }

    /// Closes the current test, returns "ok", "fail" or "skipped".
    @discardableResult
    func endTest(_ id: String, elapsed: TimeInterval) -> String {
        let failed = testLines.contains { $0.contains("[NO]") }
        let produced = !testLines.isEmpty
        let result = !produced ? "skipped" : (failed ? "fail" : "ok")
        append("--- TEST \(id) END    result: \(result)   \(String(format: "%.2f", elapsed)) s")
        inTest = false
        return result
    }

    func note(_ text: String) { append(text) }

    func log(_ message: String) { append(message) }

    private func append(_ message: String, toScreen: Bool = true) {
        let line = message.isEmpty ? "" : "[\(stamp.string(from: Date()))] \(message)"
        if let data = (line + "\n").data(using: .utf8) {
            handle?.seekToEndOfFile()
            handle?.write(data)
            handle?.synchronizeFile()
        }
        if inTest && !message.isEmpty { testLines.append(message) }
        guard toScreen else { return }
        DispatchQueue.main.async { [weak self] in self?.sink?(line) }
    }
}

// MARK: - one article

/// A card for one research article. The whole card is the button: tapping it runs
/// every probe of that article. No separate RUN control, so the list keeps its
/// space for the log.
final class ArticleCard: UIView {

    enum Danger {
        case none
        /// Crashes a daemon or this app; the system recovers on its own.
        case crash(String)
        /// Kernel panic; the device reboots.
        case panic(String)
    }

    private let status = UILabel()
    private let chevron = UILabel()
    private let danger: Danger

    init(id: String, title: String, summary: String, probes: Int, danger: Danger = .none) {
        self.danger = danger
        super.init(frame: .zero)

        backgroundColor = Theme.surface
        layer.cornerRadius = 10
        Theme.outline(self)

        let number = UILabel()
        number.text = id
        number.font = Theme.mono(13, .bold)
        number.textColor = Theme.green
        number.setContentHuggingPriority(.required, for: .horizontal)

        let head = UILabel()
        head.text = title
        head.font = Theme.sans(14.5, .semibold)
        head.textColor = Theme.text
        head.numberOfLines = 1

        chevron.text = "???"
        chevron.font = Theme.mono(11, .bold)
        chevron.textColor = Theme.greenDim
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let top = UIStackView(arrangedSubviews: [number, head, chevron])
        top.axis = .horizontal
        top.spacing = 8
        top.alignment = .firstBaseline

        let detail = UILabel()
        detail.text = summary
        detail.font = Theme.sans(11, .regular)
        detail.textColor = Theme.textDim
        detail.numberOfLines = 2

        var rows: [UIView] = [top, detail]

        switch danger {
        case .none:
            break
        case .crash(let text):
            rows.append(warningRow("??????  " + text, colour: Theme.warn))
            backgroundColor = Theme.warnSurface
            Theme.outline(self, colour: Theme.warn)
        case .panic(let text):
            rows.append(warningRow("??????  " + text, colour: Theme.danger))
            backgroundColor = Theme.dangerSurface
            Theme.outline(self, colour: Theme.danger)
        }

        let count = UILabel()
        count.text = "\(probes) probes"
        count.font = Theme.mono(10)
        count.textColor = Theme.textFaint

        status.text = "tap to run"
        status.font = Theme.mono(10, .medium)
        status.textColor = Theme.textFaint
        status.textAlignment = .right

        let footer = UIStackView(arrangedSubviews: [count, status])
        footer.axis = .horizontal
        footer.spacing = 8
        footer.alignment = .center
        rows.append(footer)

        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func warningRow(_ text: String, colour: UIColor) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = Theme.sans(10.5, .semibold)
        label.textColor = colour
        label.numberOfLines = 2
        return label
    }

    func setStatus(_ text: String, color: UIColor) {
        status.text = text
        status.textColor = color
    }

    func setRunning(_ running: Bool) {
        chevron.text = running ? "???" : "???"
        chevron.textColor = running ? Theme.green : Theme.greenDim
        alpha = running ? 0.85 : 1
    }

    func setEnabled(_ enabled: Bool) {
        isUserInteractionEnabled = enabled
    }
}

// MARK: - view controller

final class ViewController: UIViewController {

    private let logView = UITextView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let caption = UILabel()
    private let scroll = UIScrollView()
    private let list = UIStackView()

    /// Probe registry: id ??? (title, closure). The UI exposes only the ten articles;
    /// individual probes stay addressable from code.
    private lazy var probes: [String: (String, () -> Void)] = [
        "01": ("IOSurface size validation", { XPCProbe.shared.bench01IOSurface() }),
        "02": ("Metal GPU VA access", { XPCProbe.shared.f1ControlProbe() }),
        "03": ("mediaplaybackd ?? FigXPC", { XPCProbe.shared.bench03Media() }),
        "04": ("AppleAVE2 properties", { XPCProbe.shared.bench04EncoderProps() }),
        "05": ("ANE reachability", { XPCProbe.shared.bench05ANE() }),
        "06": ("GPU VA scan", { XPCProbe.shared.bigScanProbe() }),
        "07": ("mediaplaybackd crash", { XPCProbe.shared.sandboxCre8Probe() }),
        "08": ("AppleAVE2 panic", { XPCProbe.shared.ntlBoundaryProbe() }),
        "09": ("CoreGraphics PDF shading", { XPCProbe.shared.bench09PDFShading() }),
        "10": ("AGX response fields", { XPCProbe.shared.bench10AGXFields() }),
        "11": ("AppleAVE2 DPB reach", { XPCProbe.shared.bench11AVE_DPB() }),
        "12": ("AppleAVE2 usage sweep", { XPCProbe.shared.bench12AVE_Usage() }),
        "13": ("AppleAVE2 property order", { XPCProbe.shared.bench13AVE_Order() }),
        "14": ("Scaler reachability", { XPCProbe.shared.bench14Scaler() }),
        "20": ("Scaler call shapes", { XPCProbe.shared.bench20ScalerShapes() }),
        "21": ("Scaler ABI map", { XPCProbe.shared.bench21ScalerABI() }),
        "22": ("Scaler client types", { XPCProbe.shared.bench22ScalerTypes() }),
        "23": ("Scaler setup", { XPCProbe.shared.bench23ScalerSetup() }),
        "24": ("Scaler pointer", { XPCProbe.shared.bench24ScalerAddr() }),
        "25": ("Scaler marker", { XPCProbe.shared.bench25ScalerMarker() }),
        "26": ("Scaler inventory", { XPCProbe.shared.bench26ScalerInventory() }),
        "27": ("Scaler notify port", { XPCProbe.shared.bench27ScalerNotify() }),
        "28": ("Scaler async call", { XPCProbe.shared.bench28ScalerAsync() }),
        "29": ("Scaler surface field", { XPCProbe.shared.bench29ScalerSurfaceField() }),
        "30": ("Scaler read-back", { XPCProbe.shared.bench30ScalerReadBack() }),
        "31": ("Scaler warm-up", { XPCProbe.shared.bench31ScalerWarm() }),
        "33": ("Scaler ring", { XPCProbe.shared.bench33ScalerRing() }),
        "34": ("Scaler transform variants", { XPCProbe.shared.bench34ScalerTransformVariants() }),
        "35": ("Scaler ring fill", { XPCProbe.shared.bench35ScalerRingFill() }),
        "36": ("Scaler live ABI", { XPCProbe.shared.bench36ScalerLiveABI() }),
        "37": ("Scaler field sweep", { XPCProbe.shared.bench37ScalerLogOracle() }),
        "38": ("Scaler extra surfaces", { XPCProbe.shared.bench38ScalerExtraSurfaces() }),
        "39": ("Scaler teardown", { XPCProbe.shared.bench39ScalerTeardown() }),
        "40": ("Scaler race", { XPCProbe.shared.bench40ScalerRace() }),
        "41": ("Scaler lying surface", { XPCProbe.shared.bench41ScalerAccelerator() }),
        "42": ("Scaler overflow", { XPCProbe.shared.bench42ScalerOverflow() }),
        "43": ("Scaler pointer effect", { XPCProbe.shared.bench43ScalerPointerEffect() }),
        "44": ("Scaler pointer data", { XPCProbe.shared.bench44ScalerPointerData() }),
        "45": ("Scaler pointer after warm", { XPCProbe.shared.bench45ScalerPointerAfterWarm() }),
        "46": ("Multitouch client", { XPCProbe.shared.bench46Multitouch() }),
        "47": ("Image decoder surfaces", { XPCProbe.shared.bench47JPEGSurface() }),
        "48": ("Image parser campaign", { XPCProbe.shared.bench48ImageCampaign() }),
        "49": ("Container path leak", { XPCProbe.shared.bench49PathLeak() }),
        "50": ("Container access", { XPCProbe.shared.bench50ContainerAccess() }),
        "55": ("MobileGestalt cache", { XPCProbe.shared.bench55MobileGestalt() }),
        "56": ("App group extension", { XPCProbe.shared.bench56AppGroupPath() }),
        "58": ("Grant in use", { XPCProbe.shared.bench58GrantInUse() }),
        "59": ("Find gestalt", { XPCProbe.shared.bench59FindGestalt() }),
        "60": ("Gestalt read", { XPCProbe.shared.bench60GestaltRead() }),
        "61": ("Gestalt values", { XPCProbe.shared.bench61GestaltValues() }),
        "63": ("Gestalt restore", { XPCProbe.shared.bench63GestaltRestore() }),
        "66": ("Gestalt persist", { XPCProbe.shared.bench66GestaltPersist() }),
        "70": ("Gestalt stage", { XPCProbe.shared.bench70GestaltStage() }),
        "71": ("Gestalt fresh", { XPCProbe.shared.bench71GestaltFresh() }),
        "74": ("Gestalt product description", { XPCProbe.shared.bench74GestaltProductDescription() }),
        "75": ("Gestalt product restore", { XPCProbe.shared.bench75GestaltProductDescriptionRestore() }),
        "76": ("SystemGroup inventory", { XPCProbe.shared.bench76SystemGroupInventory() }),
        "77": ("Container classes", { XPCProbe.shared.bench77ContainerClasses() }),
        "78": ("Foreign container write", { XPCProbe.shared.bench78ForeignContainer() }),
        "79": ("Which class issues a token", { XPCProbe.shared.bench79ContainerClasses() }),
        "80": ("Class reach", { XPCProbe.shared.bench80ClassReach() }),
        "81": ("Class-2 fallback", { XPCProbe.shared.bench81ClassTwoFallback() }),
        "82": ("JPEG dispatch", { XPCProbe.shared.bench82JPEGDispatch() }),
        "83": ("JPEG fields", { XPCProbe.shared.bench83JPEGFields() }),
        "84": ("JPEG setup", { XPCProbe.shared.bench84JPEGSetup() }),
        "85": ("JPEG warm-up", { XPCProbe.shared.bench85JPEGWarm() }),
        "86": ("Container metadata", { XPCProbe.shared.bench86ContainerMetadata() }),
        "87": ("Surface adjacency", { XPCProbe.shared.bench87SurfaceAdjacency() }),
        "88": ("App container metadata", { XPCProbe.shared.bench88AppContainerMetadata() }),
        "89": ("Surface regions", { XPCProbe.shared.bench89SurfaceRegions() }),
        "90": ("AGX command path", { XPCProbe.shared.bench90AGXCommandPath() }),
        "91": ("ANE interface", { XPCProbe.shared.bench91ANEInterface() }),
        "92": ("Surface primitives", { XPCProbe.shared.bench92SurfacePrimitives() }),
        "93": ("Notify teardown", { XPCProbe.shared.bench93NotifyTeardown() }),
        "94": ("Surface exports", { XPCProbe.shared.bench94SurfaceExports() }),
        "95": ("Service map", { XPCProbe.shared.bench95ServiceMap() }),
        "96": ("Surface client", { XPCProbe.shared.bench96SurfaceClient() }),
        "97": ("HID reach", { XPCProbe.shared.bench97HIDReach() }),
        "98": ("Notify race", { XPCProbe.shared.bench98NotifyRace() }),
        "99": ("Notify shape", { XPCProbe.shared.bench99SurfaceNotifyShape() }),
        "100": ("HID selectors", { XPCProbe.shared.bench100HIDSelectors() }),
        "101": ("ANE load balancer", { XPCProbe.shared.bench101ANELoadBalancer() }),
        "102": ("Surface exact sizes", { XPCProbe.shared.bench102SurfaceExactSizes() }),
        "103": ("HID drivers", { XPCProbe.shared.bench103HIDDrivers() }),
        "104": ("ANE balancer detail", { XPCProbe.shared.bench104ANELoadBalancerDeep() }),
        "105": ("HID properties", { XPCProbe.shared.bench105HIDProperties() }),
        "106": ("Media exact sizes", { XPCProbe.shared.bench106MediaExactSizes() }),
        "107": ("Key store", { XPCProbe.shared.bench107KeyStore() }),
    ]

    private struct Article {
        let id: String
        let title: String
        let summary: String
        let probes: [String]
        var danger: ArticleCard.Danger = .none
    }

    private lazy var articles: [Article] = [
        Article(id: "01", title: "IOSurface size validation",
                summary: "A 4 GiB header region is accepted for a 64 KiB surface.",
                probes: ["01", "92", "93", "94"],
                danger: .crash("probe 93 races a teardown ?? the device may panic")),
        Article(id: "02", title: "Metal GPU VA",
                summary: "Access beyond a buffer reaches other GPU pages of the same context.",
                probes: ["02", "06", "10", "87", "89", "90"]),
        Article(id: "03", title: "mediaplaybackd ?? FigXPC",
                summary: "The protocol is reproduced end to end; one message crashes the daemon.",
                probes: ["03", "07", "09"],
                danger: .crash("crashes sandboxserver ?? it restarts after ~90 s")),
        Article(id: "04", title: "AppleAVE2",
                summary: "Two defects reachable through VideoToolbox, both denial of service.",
                probes: ["04", "08", "11", "12", "13"],
                danger: .panic("kernel panic ?? the device reboots")),
        Article(id: "05", title: "ANE reachability",
                summary: "No client type is supported and no daemon accepts a connection.",
                probes: ["05", "91"]),
        Article(id: "06", title: "AppleM2ScalerCSCDriver",
                summary: "The ABI is mapped and the transform works after a warm-up; the read-back is static.",
                probes: ["14", "20", "21", "22", "23", "24", "25", "26", "27", "28", "29",
                         "30", "31", "33", "34", "35", "36", "37", "38", "39", "40", "41",
                         "42", "43", "44", "45"]),
        Article(id: "07", title: "Container path disclosure",
                summary: "fsgetpath discloses container paths; their contents are not readable.",
                probes: ["49", "50", "86", "88"]),
        Article(id: "08", title: "Image parser surfaces",
                summary: "The driver opens, the dispatch sizes are known, the methods are gated.",
                probes: ["47", "48", "82", "83", "84", "85"]),
        Article(id: "09", title: "Closed external leads",
                summary: "Published directions tested against this build and found out of reach.",
                probes: ["46"],
                danger: .crash("one probe may crash this app")),
        Article(id: "10", title: "Sandbox escape",
                summary: "Read and write in other containers; the gestalt cache can be edited.",
                probes: ["55", "56", "58", "59", "60", "61", "63", "66", "70", "71",
                         "74", "75", "76", "77", "78", "79", "80", "81"],
                danger: .crash("rewrites system identity values ?? a backup is taken first")),
        Article(id: "11", title: "Reachability map",
                summary: "Which user clients a sandboxed app can open on this build.",
                probes: ["95", "96", "97", "99", "100", "101", "102", "103", "104", "105", "106", "107"]),
        Article(id: "12", title: "IOSurface notify race",
                summary: "Registration against teardown, through the private entry points.",
                probes: ["98"],
                danger: .panic("probe 98 races a teardown ?? the device can reboot")),
    ]

    private var cards: [String: ArticleCard] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bench"
        buildUI()
        Logger.shared.sink = { [weak self] line in self?.appendLog(line) }
        Logger.shared.note("app launched ?? \(articles.count) articles ?? \(totalProbes) probes")

        let publisher = Bundle.main.url(forResource: "publisher", withExtension: "flag") != nil
            || (Bundle.main.bundleIdentifier ?? "").contains("publisher")
        if publisher {
            logView.text = ""
            DispatchQueue.global(qos: .userInitiated).async { XPCProbe.shared.publisherProbe() }
        }
    }

    private var totalProbes: Int { articles.reduce(0) { $0 + $1.probes.count } }

    private func buildUI() {
        view.backgroundColor = Theme.background

        let backdrop = MatrixBackdrop()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)

        // Compact header: title and device line share the top, nothing wasted.

        let sub = UILabel()
        sub.text = Device.summary
        sub.font = Theme.mono(10.5)
        sub.textColor = Theme.greenFaint
        sub.numberOfLines = 2

        let hint = UILabel()
        hint.text = "tap a card ?? it runs every probe of that article"
        hint.font = Theme.mono(9.5)
        hint.textColor = Theme.textFaint

        let warn = UILabel()
        warn.text = "?????? verified on iOS \(Device.verifiedSystem) ?? \(Device.verifiedChip) ??? findings may not reproduce here"
        warn.font = Theme.mono(9.5, .medium)
        warn.textColor = Theme.warn
        warn.numberOfLines = 2
        warn.isHidden = Device.isVerifiedConfiguration

        list.axis = .vertical
        list.spacing = 7
        list.translatesAutoresizingMaskIntoConstraints = false

        for (index, article) in articles.enumerated() {
            let card = ArticleCard(id: article.id, title: article.title,
                                   summary: article.summary, probes: article.probes.count,
                                   danger: article.danger)
            card.translatesAutoresizingMaskIntoConstraints = false
            card.tag = index
            let tap = UITapGestureRecognizer(target: self, action: #selector(onTapCard(_:)))
            card.addGestureRecognizer(tap)
            cards[article.id] = card
            list.addArrangedSubview(card)
        }

        logView.backgroundColor = UIColor(red: 0.01, green: 0.03, blue: 0.02, alpha: 1)
        logView.layer.cornerRadius = 8
        Theme.outline(logView, colour: Theme.greenDim)
        logView.textColor = Theme.greenSoft
        logView.font = Theme.mono(10)
        logView.isEditable = false
        logView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        caption.text = "sandboxed ?? no kernel entitlements ?? userland"
        caption.font = Theme.mono(9.5)
        caption.textColor = Theme.textFaint
        caption.textAlignment = .center

        spinner.color = Theme.green
        spinner.hidesWhenStopped = true

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.addSubview(list)

        [sub, hint, warn, scroll, logView, caption, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Header pulled to the very top of the safe area.
            sub.topAnchor.constraint(equalTo: g.topAnchor, constant: 6),
            sub.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            sub.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),

            hint.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 3),
            hint.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),

            warn.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 2),
            warn.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            warn.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: warn.bottomAnchor, constant: 5),
            scroll.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            scroll.heightAnchor.constraint(equalToConstant: 396),

            list.topAnchor.constraint(equalTo: scroll.topAnchor),
            list.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            list.widthAnchor.constraint(equalTo: scroll.widthAnchor),

            logView.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            logView.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),
            logView.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            logView.bottomAnchor.constraint(equalTo: caption.topAnchor, constant: -4),

            caption.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            caption.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            caption.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -2),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: log

    private func appendLog(_ line: String) {
        let text = NSMutableAttributedString(attributedString: logView.attributedText ?? NSAttributedString())
        let colour: UIColor
        let font: UIFont
        let payload = line.hasPrefix("[") && line.contains("] ")
            ? String(line[line.range(of: "] ")!.upperBound...])
            : line
        let trimmed = payload.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("[OK]") || trimmed.contains("CONFIRMED") || trimmed.contains("result: ok") {
            colour = Theme.green
            font = Theme.mono(10, .bold)
        } else if trimmed.hasPrefix("[NO]") || trimmed.contains("result: fail") || trimmed.contains("result: skipped") {
            colour = Theme.danger
            font = Theme.mono(10, .semibold)
        } else if trimmed.hasPrefix("???") || trimmed.hasPrefix("---") {
            colour = Theme.greenSoft
            font = Theme.mono(10, .bold)
        } else {
            colour = Theme.greenDim
            font = Theme.mono(10)
        }

        text.append(NSAttributedString(string: line + "\n",
                                       attributes: [.foregroundColor: colour, .font: font]))
        logView.attributedText = text
        if text.length > 0 {
            logView.scrollRangeToVisible(NSRange(location: text.length - 1, length: 1))
        }
    }

    // MARK: run

    @objc private func onTapCard(_ gr: UITapGestureRecognizer) {
        guard let card = gr.view as? ArticleCard,
              card.tag < articles.count else { return }
        let article = articles[card.tag]

        card.setEnabled(false)
        card.setRunning(true)
        spinner.startAnimating()
        logView.text = ""
        Logger.shared.note("article \(article.id) \(article.title): run all (\(article.probes.count) probes)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var okCount = 0, failCount = 0, skipCount = 0

            for (index, id) in article.probes.enumerated() {
                guard let probe = self.probes[id] else { continue }
                DispatchQueue.main.async {
                    card.setStatus("running \(index + 1)/\(article.probes.count)", color: Theme.greenSoft)
                }
                Logger.shared.beginTest(id, probe.0)
                let started = Date()
                probe.1()
                let elapsed = Date().timeIntervalSince(started)
                switch Logger.shared.endTest(id, elapsed: elapsed) {
                case "ok": okCount += 1
                case "fail": failCount += 1
                default: skipCount += 1
                }
            }

            let summary = "ok \(okCount) ?? fail \(failCount)" + (skipCount > 0 ? " ?? n/a \(skipCount)" : "")
            let colour = failCount == 0 ? Theme.green : Theme.warn
            DispatchQueue.main.async {
                self.spinner.stopAnimating()
                card.setRunning(false)
                card.setEnabled(true)
                card.setStatus(summary, color: colour)
            }
        }
    }
}

