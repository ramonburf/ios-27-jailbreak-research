//
//  FilesViewController.swift
//  Bench27
//
//  A file manager for what the container grant opens. Every directory is listed
//  while a fresh grant is alive; the badge shows whether that directory is
//  readable only or writable too, and where writing is allowed files and folders
//  can be created and deleted.
//

import UIKit

final class FilesViewController: UITableViewController {

    private struct Entry {
        let name: String
        let display: String
        let subtitle: String
        let isDir: Bool
        let writable: Bool
    }

    private let path: String
    private var entries: [Entry] = []

    init(path: String = "/private/var/containers/Shared/SystemGroup") {
        self.path = path
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let isRoot = path == "/private/var/containers/Shared/SystemGroup"
        navigationItem.title = isRoot ? "Files" : (path as NSString).lastPathComponent
        if !isRoot { title = (path as NSString).lastPathComponent }
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.greenDim.withAlphaComponent(0.25)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableFooterView = UIView()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(onAdd))
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Reload", style: .plain, target: self, action: #selector(load))

        load()
    }

    // MARK: listing

    @objc private func load() {
        entries = []

        // Inside a granted container the extension applies and opendir works.
        if Escape.group != nil {
            let handle = Escape.grant(path)
            if handle >= 0 {
                let dirWritable = access(path, W_OK) == 0
                var raw: [String] = []
                if let d = opendir(path) {
                    while let e = readdir(d) {
                        let name = withUnsafeBytes(of: e.pointee.d_name) { raw -> String in
                            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                        }
                        if name != "." && name != ".." { raw.append(name) }
                    }
                    closedir(d)
                }
                Escape.revoke(handle)

                // Labelling costs a grant per child; skip it for very long listings.
            let label = raw.count <= 60

            for name in raw.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
                    let full = (path as NSString).appendingPathComponent(name)
                    var sb = stat()
                    let isDir = stat(full, &sb) == 0 && (sb.st_mode & S_IFMT) == S_IFDIR
                    let writable = dirWritable && access(full, W_OK) == 0
                    let guess = (isDir && label) ? humanName(full) : nil
                    let display = guess ?? name
                    let anonymous = isDir && guess == nil && name.contains("-")
                    let kind = anonymous ? "anonymous group" : (isDir ? "folder" : sizeText(sb.st_size))
                    let subtitle = "\(kind) ?? \(writable ? "rw" : "r") ?? \(name.prefix(8))"
                    entries.append(Entry(name: name, display: display, subtitle: subtitle,
                                         isDir: isDir, writable: writable))
                }
                Logger.shared.note("files: \(path) ??? \(entries.count) entries (granted, writable=\(dirWritable))")
            }
        }

        // The parent of the shared groups cannot be granted; fsgetpath still
        // resolves the names of its children by inode.
        if entries.isEmpty {
            for name in inodeChildren(path) {
                let full = (path as NSString).appendingPathComponent(name)
                let label = humanName(full)
                let anonymous = label == nil && name.contains("-")
                entries.append(Entry(name: name, display: label ?? name,
                                     subtitle: "\(anonymous ? "anonymous group" : "folder") ?? r ?? \(name.prefix(8))",
                                     isDir: true, writable: false))
            }
            Logger.shared.note("files: \(path) ??? \(entries.count) entries (fsgetpath)")
        }

        tableView.reloadData()
    }

    /// The container's own metadata is unreadable: the sandbox allows listing it
    /// but returns EPERM on opening `.com.apple.mobile_container_manager.metadata
    /// .plist`. A readable name is derived from what the group actually stores.
    private func humanName(_ dir: String) -> String? {
        let base = (dir as NSString).lastPathComponent
        if base.contains(".") {
            return base.replacingOccurrences(of: "systemgroup.", with: "")
        }

        // Anonymous group: identify it by a file only it keeps.
        let markers: [(String, String)] = [
            ("Library/Database/com.apple.MobileBluetooth.ledevices.paired.db", "bluetooth"),
            ("Library/Database/com.apple.MobileBluetooth.ledevices.other.db", "bluetooth"),
            ("Library/com.apple.ManagedSettings.system", "managed settings"),
            ("Library/Preferences/com.apple.powerlogd.plist", "powerlog"),
            ("Library/analytics.sqlite", "analytics"),
            ("Library/ConfigurationProfiles", "configuration profiles"),
            ("Library/RegulatoryImages", "regulatory images"),
            ("Library/ProvenanceV2", "provenance"),
            ("Library/ucrt", "ucrt"),
            ("Library/region_info", "region info"),
            ("Library/dafsaData.bin", "url storage"),
            ("Library/Logs", "logs"),
            ("Library/BatteryLife", "battery"),
            ("Library/PerfPowerTelemetry", "power telemetry"),
        ]
        // The marker checks need the container's own grant: a bare stat inside
        // the folder is denied by the sandbox.
        let handle = Escape.grant(dir)
        defer { if handle >= 0 { Escape.revoke(handle) } }
        guard handle >= 0 else { return nil }

        for (marker, label) in markers {
            let full = (dir as NSString).appendingPathComponent(marker)
            var sb = stat()
            if stat(full, &sb) == 0 { return label }
        }

        // Last resort: the most distinctive thing the group stores. Generic
        // container folders carry no information, so they are skipped and the
        // search drops one level into Library.
        let generic: Set<String> = ["Library", "Documents", "Caches", "tmp", "SystemData",
                                    "Preferences", "CloudKit", "Logs"]
        func biggest(in folder: String) -> String? {
            var best: (name: String, size: off_t)?
            guard let d = opendir(folder) else { return nil }
            while let e = readdir(d) {
                let name = withUnsafeBytes(of: e.pointee.d_name) { raw -> String in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
                if name == "." || name == ".." || name.hasPrefix(".") { continue }
                if generic.contains(name) { continue }
                var sb = stat()
                let full = (folder as NSString).appendingPathComponent(name)
                if stat(full, &sb) == 0, sb.st_size > (best?.size ?? 0) {
                    best = (name, sb.st_size)
                }
            }
            closedir(d)
            return best?.name
        }

        if let name = biggest(in: dir) { return name }
        for sub in ["Library/Caches", "Library/Preferences", "Library"] {
            let full = (dir as NSString).appendingPathComponent(sub)
            if let name = biggest(in: full) { return name }
        }
        return nil
    }

    private func sizeText(_ bytes: off_t) -> String {
        if bytes >= 1 << 20 { return String(format: "%.1f MB", Double(bytes) / Double(1 << 20)) }
        if bytes >= 1 << 10 { return String(format: "%.1f KB", Double(bytes) / Double(1 << 10)) }
        return "\(bytes) B"
    }

    private func inodeChildren(_ path: String) -> [String] {
        var st = statfs()
        guard statfs(path, &st) == 0 else { return [] }
        var buf = [CChar](repeating: 0, count: 1024)
        let prefix = path.hasSuffix("/") ? path : path + "/"
        var names = Set<String>()
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
            if let first = rest.split(separator: "/").first { names.insert(String(first)) }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let e = entries[indexPath.row]
        var c = cell.defaultContentConfiguration()
        let symbol: String
        if e.isDir {
            symbol = e.writable ? "folder.fill" : "folder"
        } else {
            symbol = e.name.lowercased().hasSuffix(".plist") ? "doc.text" : "doc"
        }
        c.image = UIImage(systemName: symbol)
        c.imageProperties.tintColor = e.writable ? Theme.green : Theme.greenDim
        c.imageProperties.maximumSize = CGSize(width: 22, height: 22)
        c.text = e.display
        c.secondaryText = e.subtitle
        c.textProperties.color = Theme.text
        c.textProperties.font = Theme.sans(14.5, .semibold)
        c.textProperties.numberOfLines = 1
        c.textProperties.lineBreakMode = .byTruncatingMiddle
        c.secondaryTextProperties.color = e.writable ? Theme.green : Theme.textFaint
        c.secondaryTextProperties.font = Theme.sans(11)
        c.secondaryTextProperties.numberOfLines = 1
        c.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
        cell.contentConfiguration = c
        cell.backgroundColor = Theme.surface
        cell.accessoryType = e.isDir ? .disclosureIndicator : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let e = entries[indexPath.row]
        let full = (path as NSString).appendingPathComponent(e.name)
        if e.isDir {
            navigationController?.pushViewController(FilesViewController(path: full), animated: true)
        } else {
            navigationController?.pushViewController(FilePreviewController(path: full), animated: true)
        }
    }

    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        let e = entries[indexPath.row]
        guard e.writable else { return nil }

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else { return done(false) }
            let full = (self.path as NSString).appendingPathComponent(e.name)
            let handle = Escape.grant(self.path)
            guard handle >= 0 else { return done(false) }
            defer { Escape.revoke(handle) }
            let ok = (try? FileManager.default.removeItem(atPath: full)) != nil
            Logger.shared.note("files: delete \(e.name) ??? \(ok)")
            if ok { self.load() }
            done(ok)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    // MARK: write

    @objc private func onAdd() {
        let sheet = UIAlertController(title: "Create", message: path,
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "New file", style: .default) { [weak self] _ in
            self?.promptName(kind: .file)
        })
        sheet.addAction(UIAlertAction(title: "New folder", style: .default) { [weak self] _ in
            self?.promptName(kind: .folder)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItem
        present(sheet, animated: true)
    }

    private enum Kind { case file, folder }

    private func promptName(kind: Kind) {
        let alert = UIAlertController(
            title: kind == .file ? "New file" : "New folder",
            message: "Inside \((path as NSString).lastPathComponent)",
            preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = kind == .file ? "bench27.txt" : "bench27"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text, !name.isEmpty else { return }
            self.create(kind: kind, name: name)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func create(kind: Kind, name: String) {
        let handle = Escape.grant(path)
        guard handle >= 0 else {
            report("No write access here", detail: "the grant was refused")
            return
        }
        defer { Escape.revoke(handle) }

        let full = (path as NSString).appendingPathComponent(name)
        var ok = false
        switch kind {
        case .file:
            ok = FileManager.default.createFile(atPath: full, contents: Data("bench27\n".utf8))
        case .folder:
            ok = (try? FileManager.default.createDirectory(atPath: full,
                                                           withIntermediateDirectories: false)) != nil
        }
        Logger.shared.note("files: create \(kind == .file ? "file" : "folder") \(name) ??? \(ok)")
        if ok {
            load()
        } else {
            report("Could not create", detail: "errno \(errno)")
        }
    }

    private func report(_ title: String, detail: String) {
        let alert = UIAlertController(title: title, message: detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - preview

/// Shows a file and, where the grant allows, edits it ??? as text or by patching
/// bytes at an offset.
final class FilePreviewController: UIViewController {

    private let path: String
    private let textView = UITextView()
    private let mode = UISegmentedControl(items: ["Text", "Hex"])
    private var data: Data?
    private var editable = false

    init(path: String) {
        self.path = path
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.title = (path as NSString).lastPathComponent

        var actions = [
            UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(onDelete)),
            UIBarButtonItem(title: "Edit", style: .plain, target: self, action: #selector(toggleEdit)),
            UIBarButtonItem(title: "Patch", style: .plain, target: self, action: #selector(onPatch)),
        ]
        if path.lowercased().hasSuffix(".plist") {
            actions.insert(UIBarButtonItem(title: "Plist", style: .plain,
                                           target: self, action: #selector(onPlist)), at: 0)
        }
        navigationItem.rightBarButtonItems = actions

        mode.selectedSegmentIndex = 0
        mode.selectedSegmentTintColor = Theme.surfaceHigh
        mode.backgroundColor = Theme.surface
        mode.setTitleTextAttributes([.foregroundColor: Theme.text, .font: Theme.sans(12, .semibold)],
                                    for: .selected)
        mode.setTitleTextAttributes([.foregroundColor: Theme.textDim, .font: Theme.sans(12)],
                                    for: .normal)
        mode.addTarget(self, action: #selector(onMode), for: .valueChanged)

        textView.backgroundColor = Theme.surface
        textView.layer.cornerRadius = 10
        Theme.outline(textView, colour: Theme.greenDim)
        textView.isEditable = false
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.translatesAutoresizingMaskIntoConstraints = false

        mode.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mode)
        view.addSubview(textView)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            mode.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
            mode.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),
            mode.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            mode.heightAnchor.constraint(equalToConstant: 32),

            textView.topAnchor.constraint(equalTo: mode.bottomAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            textView.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -8),
        ])

        load()
    }

    // MARK: data

    private func load() {
        let parent = (path as NSString).deletingLastPathComponent
        let maybe: Data?? = Escape.withAccess(parent) { FileManager.default.contents(atPath: path) }
        guard let whole = maybe ?? nil else {
            data = nil
            textView.text = "cannot read this file\n\nno grant, or the file is not readable"
            mode.isHidden = true
            navigationItem.rightBarButtonItems = nil
            return
        }
        data = whole
        render()
        Logger.shared.note("files: read \(path) (\(whole.count) bytes)")
    }

    private func writable() -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        let handle = Escape.grant(parent)
        defer { Escape.revoke(handle) }
        return handle >= 0 && access(path, W_OK) == 0
    }

    private func save(_ bytes: Data) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        let handle = Escape.grant(parent)
        guard handle >= 0 else { return false }
        defer { Escape.revoke(handle) }
        do {
            try bytes.write(to: URL(fileURLWithPath: path))
            data = bytes
            Logger.shared.note("files: wrote \(bytes.count) bytes to \(path)")
            return true
        } catch {
            Logger.shared.note("files: write failed \(error.localizedDescription)")
            return false
        }
    }

    // MARK: render

    @objc private func onMode() {
        if editable { toggleEdit() }
        render()
    }

    private func render() {
        guard let data else { return }
        textView.isEditable = false
        editable = false

        if mode.selectedSegmentIndex == 0, let text = String(data: data, encoding: .utf8) {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            textView.attributedText = NSAttributedString(string: text, attributes: [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: Theme.text,
                .paragraphStyle: style,
            ])
            navigationItem.rightBarButtonItems?.first(where: { $0.title == "Edit" })?.isEnabled = true
            return
        }

        // Hex: eight bytes per line so nothing wraps on an iPhone.
        let bytes = [UInt8](data)
        let limit = min(bytes.count, 8192)
        var out = ""
        var offset = 0
        while offset < limit {
            let end = min(offset + 8, limit)
            var hex = ""
            var ascii = ""
            for i in offset..<end {
                hex += String(format: "%02x ", bytes[i])
                let c = bytes[i]
                ascii += (c >= 32 && c < 127) ? String(UnicodeScalar(c)) : "."
            }
            let pad = String(repeating: "   ", count: 8 - (end - offset))
            out += String(format: "%06x", offset) + "  " + hex + pad + " " + ascii + "\n"
            offset += 8
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        textView.attributedText = NSAttributedString(string: out, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: Theme.greenSoft,
            .paragraphStyle: style,
        ])
    }

    // MARK: edit

    @objc private func toggleEdit() {
        guard var data else { return }
        guard mode.selectedSegmentIndex == 0 else {
            // Byte editing goes through Patch, the text view stays read-only here.
            report("Hex is read-only", detail: "use Patch to change bytes at an offset")
            return
        }
        guard writable() else {
            report("Not writable", detail: "the grant on this directory is read-only")
            return
        }

        if editable {
            // Finish: take the text as the new content.
            let text = textView.text ?? ""
            data = Data(text.utf8)
            if save(data) {
                render()
                report("Saved", detail: "\(data.count) bytes written")
            } else {
                report("Write failed", detail: "the file was not changed")
            }
            return
        }

        editable = true
        textView.isEditable = true
        textView.becomeFirstResponder()
        navigationItem.rightBarButtonItems?.first(where: { $0.title == "Edit" })?.title = "Save"
    }

    @objc private func onPlist() {
        guard let editor = PlistEditorController.make(file: path) else {
            report("Not a property list", detail: "the file could not be parsed")
            return
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func onPatch() {
        guard let data, writable() else {
            report("Not writable", detail: "the grant on this directory is read-only")
            return
        }
        let alert = UIAlertController(title: "Patch bytes",
                                      message: "offset in hex, then the bytes",
                                      preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "offset ?? e.g. 40"; $0.autocapitalizationType = .none }
        alert.addTextField { $0.placeholder = "bytes ?? e.g. de ad be ef"; $0.autocapitalizationType = .none }
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self, weak alert] _ in
            guard let self, let data = self.data else { return }
            let offsetText = alert?.textFields?.first?.text ?? ""
            let bytesText = alert?.textFields?.last?.text ?? ""
            guard let offset = UInt64(offsetText.trimmingCharacters(in: .whitespaces), radix: 16) else {
                self.report("Bad offset", detail: "expected hex, e.g. 40"); return
            }
            let cleaned = bytesText.replacingOccurrences(of: " ", with: "")
            guard cleaned.count % 2 == 0, !cleaned.isEmpty else {
                self.report("Bad bytes", detail: "expected pairs, e.g. deadbeef"); return
            }
            var patch = Data()
            var index = cleaned.startIndex
            while index < cleaned.endIndex {
                let next = cleaned.index(index, offsetBy: 2)
                guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                    self.report("Bad bytes", detail: "not hexadecimal"); return
                }
                patch.append(byte)
                index = next
            }
            guard Int(offset) + patch.count <= data.count else {
                self.report("Out of range", detail: "file is \(data.count) bytes"); return
            }
            var updated = data
            updated.replaceSubrange(Int(offset)..<(Int(offset) + patch.count), with: patch)
            if self.save(updated) {
                self.render()
                self.report("Patched", detail: "\(patch.count) byte(s) at 0x\(String(offset, radix: 16))")
            } else {
                self.report("Write failed", detail: "the file was not changed")
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: delete

    @objc private func onDelete() {
        let confirm = UIAlertController(title: "Delete?",
                                        message: (path as NSString).lastPathComponent,
                                        preferredStyle: .alert)
        confirm.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            let parent = (self.path as NSString).deletingLastPathComponent
            let handle = Escape.grant(parent)
            guard handle >= 0 else { return }
            defer { Escape.revoke(handle) }
            let ok = (try? FileManager.default.removeItem(atPath: self.path)) != nil
            Logger.shared.note("files: delete \(self.path) ??? \(ok)")
            if ok { self.navigationController?.popViewController(animated: true) }
        })
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(confirm, animated: true)
    }

    private func report(_ title: String, detail: String) {
        let alert = UIAlertController(title: title, message: detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

