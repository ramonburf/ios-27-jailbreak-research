//
//  PlistEditorController.swift
//  Bench27
//
//  A structured editor for property lists: keys on the left, values on the right,
//  nested containers push one level deeper, and Save writes the whole tree back
//  through the container grant.
//

import UIKit
import CoreFoundation

/// Shared mutable state: the parsed tree, where it lives, and how it was stored.
final class PlistDocument {
    var root: Any
    let path: String
    let binary: Bool

    init(root: Any, path: String, binary: Bool) {
        self.root = root
        self.path = path
        self.binary = binary
    }
}

/// Walks the tree along a path of dictionary keys and array indices.
enum PlistTree {

    static func value(in root: Any, path: [Any]) -> Any? {
        var node: Any = root
        for step in path {
            if let key = step as? String, let dict = node as? [String: Any] {
                guard let next = dict[key] else { return nil }
                node = next
            } else if let index = step as? Int, let array = node as? [Any],
                      index >= 0, index < array.count {
                node = array[index]
            } else {
                return nil
            }
        }
        return node
    }

    static func set(_ value: Any, in root: inout Any, path: [Any]) {
        guard let first = path.first else {
            root = value
            return
        }
        if let key = first as? String, var dict = root as? [String: Any] {
            var child = dict[key] ?? ""
            set(value, in: &child, path: Array(path.dropFirst()))
            dict[key] = child
            root = dict
        } else if let index = first as? Int, var array = root as? [Any],
                  index >= 0, index < array.count {
            var child = array[index]
            set(value, in: &child, path: Array(path.dropFirst()))
            array[index] = child
            root = array
        }
    }
}

final class PlistEditorController: UITableViewController {

    private let doc: PlistDocument
    private let path: [Any]
    private let heading: String

    /// Loads a file and builds the editor for its root.
    static func make(file: String) -> UIViewController? {
        let parent = (file as NSString).deletingLastPathComponent
        let maybe: Data?? = Escape.withAccess(parent) { FileManager.default.contents(atPath: file) }
        guard let data = maybe ?? nil,
              let any = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return nil
        }
        let binary = data.starts(with: [0x62, 0x70, 0x6C, 0x69, 0x73, 0x74])
        let doc = PlistDocument(root: any, path: file, binary: binary)
        return PlistEditorController(doc: doc, path: [], heading: (file as NSString).lastPathComponent)
    }

    init(doc: PlistDocument, path: [Any], heading: String) {
        self.doc = doc
        self.path = path
        self.heading = heading
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var node: Any { PlistTree.value(in: doc.root, path: path) ?? [:] }
    private var dict: [String: Any]? { node as? [String: Any] }
    private var array: [Any]? { node as? [Any] }
    private var keys: [String] { dict.map { $0.keys.sorted() } ?? [] }
    private var items: [Any] { array ?? [] }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = heading
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.greenDim.withAlphaComponent(0.2)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableFooterView = UIView()

        if path.isEmpty {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "Save", style: .done, target: self, action: #selector(save))
        }
    }

    // MARK: table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        dict != nil ? keys.count : items.count
    }

    private func step(at row: Int) -> Any {
        if dict != nil { return keys[row] }
        return row
    }

    private func value(at row: Int) -> Any? {
        if let dict {
            return dict[keys[row]]
        }
        return items[row]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var c = cell.defaultContentConfiguration()

        let step = step(at: indexPath.row)
        let value = value(at: indexPath.row)
        c.text = (step as? String) ?? "[\(step)]"
        c.secondaryText = value.map(describe) ?? "???"
        c.textProperties.color = Theme.greenSoft
        c.textProperties.font = Theme.mono(12)
        c.secondaryTextProperties.color = Theme.text
        c.secondaryTextProperties.font = Theme.sans(12.5)
        c.secondaryTextProperties.numberOfLines = 2
        c.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle

        let nested = value is [String: Any] || value is [Any]
        if value is [String: Any] {
            c.image = UIImage(systemName: "square.grid.2x2")
        } else if value is [Any] {
            c.image = UIImage(systemName: "list.bullet")
        } else {
            c.image = UIImage(systemName: "text.cursor")
        }
        c.imageProperties.tintColor = Theme.greenDim
        c.imageProperties.maximumSize = CGSize(width: 18, height: 18)

        cell.contentConfiguration = c
        cell.backgroundColor = Theme.surface
        cell.accessoryType = nested ? .disclosureIndicator : .none
        return cell
    }

    private func describe(_ value: Any) -> String {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        switch value {
        case let s as String: return s.isEmpty ? "???" : s
        case let n as NSNumber: return n.stringValue
        case let d as Data: return "\(d.count) bytes of data"
        case let a as [Any]: return "array ?? \(a.count) items"
        case let d as [String: Any]: return "dictionary ?? \(d.count) keys"
        default: return String(describing: value)
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let step = step(at: indexPath.row)

        if let value = value(at: indexPath.row), value is [String: Any] || value is [Any] {
            let next = PlistEditorController(doc: doc, path: path + [step],
                                             heading: (step as? String) ?? "[\(step)]")
            navigationController?.pushViewController(next, animated: true)
        } else if let value = value(at: indexPath.row) {
            edit(step: step, value: value)
        }
    }

    // MARK: edit

    private func edit(step: Any, value: Any) {
        guard !(value is Data) else {
            report("Data value", detail: "binary values are edited with Patch in the hex view")
            return
        }
        let alert = UIAlertController(title: (step as? String) ?? "[\(step)]",
                                      message: typeName(value), preferredStyle: .alert)
        alert.addTextField { field in
            field.text = self.describe(value)
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Set", style: .default) { [weak self, weak alert] _ in
            guard let self, let text = alert?.textFields?.first?.text else { return }
            self.apply(step: step, text: text, old: value)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func typeName(_ value: Any) -> String {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return "boolean"
        }
        switch value {
        case is String: return "string"
        case is NSNumber: return "number"
        default: return "value"
        }
    }

    private func apply(step: Any, text: String, old: Any) {
        var converted: Any = text
        if let number = old as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1": converted = true
            case "false", "0": converted = false
            default:
                report("Invalid Boolean", detail: "enter true, false, 1, or 0")
                return
            }
        } else if old is NSNumber {
            if let n = Int(text) { converted = n }
            else if let d = Double(text) { converted = d }
            else {
                report("Invalid number", detail: "enter a valid integer or decimal number")
                return
            }
        }
        var root = doc.root
        PlistTree.set(converted, in: &root, path: path + [step])
        doc.root = root
        commit()
    }

    @objc private func save() { commit() }

    private func commit() {
        guard let out = try? PropertyListSerialization.data(
            fromPropertyList: doc.root,
            format: doc.binary ? .binary : .xml,
            options: 0) else {
            report("Cannot serialise", detail: "the edit was not saved")
            return
        }
        let parent = (doc.path as NSString).deletingLastPathComponent
        let handle = Escape.grant(parent)
        guard handle >= 0 else {
            report("Not writable", detail: "the grant on this directory is read-only")
            return
        }
        defer { Escape.revoke(handle) }
        do {
            try out.write(to: URL(fileURLWithPath: doc.path))
            Logger.shared.note("plist: wrote \(out.count) bytes to \(doc.path)")
            tableView.reloadData()
        } catch {
            report("Write failed", detail: error.localizedDescription)
        }
    }

    private func report(_ title: String, detail: String) {
        let alert = UIAlertController(title: title, message: detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

