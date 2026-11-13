//
//  Escape.swift
//  Bench27
//
//  Shared pieces of the container-manager escape: which App Group to use, how to
//  ask for an extension, and how to read and write the MobileGestalt cache.
//

import Foundation

enum Escape {
    /// App Group identifiers available to a development-signed build.
    static let groups = [
        "group.b14c62c03230f578.1", "group.b14c62c03230f578.2",
        "group.b14c62c03230f578.3", "group.b14c62c03230f578.4",
        "group.b14c62c03230f578.5",
    ]

    /// Only this flag produces a token on 27.0.1; the 26.x value is refused.
    static let flags27: UInt64 = 0x0000_0080_0000_0000

    static var group: String? {
        for g in groups where g.withCString({ wq_group_available($0) }) != 0 {
            return g
        }
        return nil
    }

    /// Returns the extension handle, or a negative step code.
    @discardableResult
    static func grant(_ path: String, group: String? = nil) -> Int64 {
        guard let g = group ?? self.group else { return -1 }
        return path.withCString { t in g.withCString { gg in wq_grant(t, gg, flags27) } }
    }

    static func revoke(_ handle: Int64) {
        if handle >= 0 { wq_revoke(handle) }
    }

    /// Runs a body with the target granted, revoking afterwards.
    static func withAccess<T>(_ path: String, _ body: () -> T) -> T? {
        let h = grant(path)
        guard h >= 0 else { return nil }
        defer { revoke(h) }
        return body()
    }

    // MARK: cache

    static let cachePath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
    static var cacheDir: String { (cachePath as NSString).deletingLastPathComponent }

    static var backupURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("mg-cache-backup.plist")
    }

    static func cacheData() -> Data? {
        let nested: Data?? = withAccess(cacheDir) { FileManager.default.contents(atPath: cachePath) }
        return nested ?? nil
    }

    static func loadCache() -> [String: Any]? {
        guard let data = cacheData(),
              let any = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return any as? [String: Any]
    }

    static func saveCache(_ plist: [String: Any]) -> Bool {
        guard let out = try? PropertyListSerialization.data(fromPropertyList: plist,
                                                            format: .binary, options: 0) else {
            return false
        }
        let ok = withAccess(cacheDir) { () -> Bool in
            do {
                try out.write(to: URL(fileURLWithPath: cachePath))
                return true
            } catch { return false }
        }
        return ok ?? false
    }

    static func backupCache() -> Bool {
        guard let data = cacheData() else { return false }
        do {
            try data.write(to: backupURL)
            return true
        } catch { return false }
    }

    static func restoreCache() -> Bool {
        guard let data = try? Data(contentsOf: backupURL) else { return false }
        let ok = withAccess(cacheDir) { () -> Bool in
            do {
                try data.write(to: URL(fileURLWithPath: cachePath))
                return true
            } catch { return false }
        }
        return ok ?? false
    }

    // MARK: fields

    /// The About screen's Model Name lives inside a dictionary value.
    static func modelName() -> String? {
        guard let plist = loadCache(),
              let extra = plist["CacheExtra"] as? [String: Any] else { return nil }
        for (_, v) in extra {
            if let d = v as? [String: Any],
               let s = d["ArtworkDeviceProductDescription"] as? String { return s }
        }
        return nil
    }

    @discardableResult
    static func setModelName(_ value: String) -> Int {
        guard var plist = loadCache(),
              var extra = plist["CacheExtra"] as? [String: Any] else { return 0 }
        var n = 0
        for (k, v) in extra {
            guard var d = v as? [String: Any],
                  d["ArtworkDeviceProductDescription"] != nil else { continue }
            d["ArtworkDeviceProductDescription"] = value
            extra[k] = d
            n += 1
        }
        guard n > 0 else { return 0 }
        plist["CacheExtra"] = extra
        return saveCache(plist) ? n : 0
    }

    /// RegulatoryModelNumber, the About screen's Model Number.
    static let modelNumberKey = "97JDvERpVwO+GHtthIh7hA"

    static func modelNumber() -> String? {
        guard let plist = loadCache(),
              let extra = plist["CacheExtra"] as? [String: Any] else { return nil }
        return extra[modelNumberKey] as? String
    }

    @discardableResult
    static func setModelNumber(_ value: String) -> Bool {
        guard var plist = loadCache(),
              var extra = plist["CacheExtra"] as? [String: Any] else { return false }
        extra[modelNumberKey] = value
        plist["CacheExtra"] = extra
        return saveCache(plist)
    }
}

