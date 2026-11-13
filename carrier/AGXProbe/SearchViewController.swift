//
//  SearchViewController.swift
//  Bench27
//
//  Name search across every container the escape reaches. Each directory is
//  opened under its own grant and released as the walk moves on. Results with the
//  same name are grouped, because the same file exists in many containers.
//

import UIKit

final class SearchResultsController: UITableViewController {

    private struct Group {
        let name: String
        let isDir: Bool
        var paths: [String]
    }

    private let roots = [
        "/private/var/containers/Shared/SystemGroup",
        "/private/var/mobile/Containers/Data/Application",
        "/private/var/mobile/Containers/Shared/AppGroup",
        "/private/var/mobile/Containers/Data/InternalDaemon",
        "/private/var/mobile/Containers/Data/PluginKitPlugin",
        "/private/var/containers/Data/System",
    ]

    private var groups: [Group] = []
    private var workItem: DispatchWorkItem?
    private var visited = 0
    private let visitCap = 20_000
    private let hitCap = 400

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.greenDim.withAlphaComponent(0.2)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableFooterView = UIView()
        tableView.keyboardDismissMode = .onDrag
    }

    // MARK: search

    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        workItem?.cancel()
        guard query.count >= 2 else {
            groups = []
            tableView.reloadData()
            return
        }
        let item = DispatchWorkItem { [weak self] in self?.run(query: query) }
        workItem = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func run(query: String) {
        visited = 0
        var buckets: [String: Group] = [:]
        var order: [String] = []

        for root in roots where visited < visitCap && order.count < hitCap {
            walk(root, depth: 0, query: query) { name, full, isDir in
                if var group = buckets[name] {
                    group.paths.append(full)
                    buckets[name] = group
                } else {
                    buckets[name] = Group(name: name, isDir: isDir, paths: [full])
                    order.append(name)
                }
            }
        }

        let result = order.compactMap { buckets[$0] }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        DispatchQueue.main.async {
            self.groups = result
            self.tableView.reloadData()
            Logger.shared.note("search: \"\(query)\" ??? \(result.count) name(s), visited \(self.visited)")
        }
    }

    /// Depth 5 covers SystemGroup/<id>/Library/Caches/file; the cap keeps a search
    /// over hundreds of containers from running away.
    private func walk(_ dir: String, depth: Int, query: String,
                      found: (String, String, Bool) -> Void) {
        guard depth <= 5, visited < visitCap else { return }

        // The root of each place is not a container, so no grant is issued for it.
        // Its children are still resolvable by inode, and each child *is* a
        // container ??? the walk continues from there under a real grant.
        let handle = Escape.grant(dir)
        var names: [String] = []
        if handle >= 0 {
            defer { Escape.revoke(handle) }
            if let d = opendir(dir) {
                while let e = readdir(d) {
                    let name = withUnsafeBytes(of: e.pointee.d_name) { raw -> String in
                        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                    }
                    if name == "." || name == ".." { continue }
                    names.append(name)
                }
                closedir(d)
            }
        } else {
            names = inodeChildren(dir)
        }

        for name in names {
            if visited >= visitCap { return }
            visited += 1
            let full = (dir as NSString).appendingPathComponent(name)
            var sb = stat()
            guard stat(full, &sb) == 0 else { continue }
            let isDir = (sb.st_mode & S_IFMT) == S_IFDIR

            if name.lowercased().contains(query) {
                found(name, full, isDir)
            }
            if isDir && !name.hasPrefix(".") {
                walk(full, depth: depth + 1, query: query, found: found)
            }
        }
    }

    /// Children of a directory that cannot be granted, resolved by inode.
    private func inodeChildren(_ path: String) -> [String] {
        var st = statfs()
        guard statfs(path, &st) == 0 else { return [] }
        var buf = [CChar](repeating: 0, count: 1024)
        let prefix = path.hasSuffix("/") ? path : path + "/"
        var names = Set<String>()
        for inode in UInt64(1)...UInt64(250_000) {
            if names.count > 400 { break }
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
        return Array(names)
    }

    // MARK: table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let group = groups[indexPath.row]
        var c = cell.defaultContentConfiguration()
        c.text = group.name
        c.secondaryText = group.paths.count == 1
            ? group.paths[0].replacingOccurrences(of: "/private", with: "")
            : "\(group.paths.count) locations ?? tap to choose"
        c.textProperties.color = Theme.text
        c.textProperties.font = Theme.sans(13.5, .medium)
        c.textProperties.lineBreakMode = .byTruncatingMiddle
        c.secondaryTextProperties.color = Theme.textFaint
        c.secondaryTextProperties.font = Theme.sans(10.5)
        c.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
        c.image = UIImage(systemName: group.isDir ? "folder" : "doc")
        c.imageProperties.tintColor = Theme.greenDim
        c.imageProperties.maximumSize = CGSize(width: 18, height: 18)
        cell.contentConfiguration = c
        cell.backgroundColor = Theme.surface
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let group = groups[indexPath.row]
        if group.paths.count == 1 {
            open(group.paths[0], isDir: group.isDir)
        } else {
            let list = PathListController(name: group.name, paths: group.paths, isDir: group.isDir)
            navigationController?.pushViewController(list, animated: true)
        }
    }

    private func open(_ path: String, isDir: Bool) {
        if isDir {
            navigationController?.pushViewController(FilesViewController(path: path), animated: true)
        } else {
            navigationController?.pushViewController(FilePreviewController(path: path), animated: true)
        }
    }
}

/// Every location of one name, so identical files in different containers can be
/// told apart by their path.
final class PathListController: UITableViewController {

    private let name: String
    private let paths: [String]
    private let isDir: Bool

    init(name: String, paths: [String], isDir: Bool) {
        self.name = name
        self.paths = paths
        self.isDir = isDir
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = name
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.greenDim.withAlphaComponent(0.2)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableFooterView = UIView()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        paths.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var c = cell.defaultContentConfiguration()
        c.text = paths[indexPath.row].replacingOccurrences(of: "/private", with: "")
        c.textProperties.color = Theme.text
        c.textProperties.font = Theme.sans(12)
        c.textProperties.numberOfLines = 3
        c.textProperties.lineBreakMode = .byTruncatingMiddle
        cell.contentConfiguration = c
        cell.backgroundColor = Theme.surface
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let path = paths[indexPath.row]
        if isDir {
            navigationController?.pushViewController(FilesViewController(path: path), animated: true)
        } else {
            navigationController?.pushViewController(FilePreviewController(path: path), animated: true)
        }
    }
}

