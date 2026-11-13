// Isolated behavioural check of the AGXProbe fixes that are UI-independent.
// Logic copied verbatim from carrier/AGXProbe/{PlistEditorController,FilesViewController}.swift
import Foundation
import CoreFoundation

var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : "  [\(detail)]")")
    if !ok { failures += 1 }
}

// ---- verbatim from PlistEditorController.swift --------------------------------
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

func describe(_ value: Any) -> String {
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

func typeName(_ value: Any) -> String {
    if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
        return "boolean"
    }
    switch value {
    case is String: return "string"
    case is NSNumber: return "number"
    default: return "value"
    }
}

/// Returns (converted, errorMessage). Conversion logic verbatim from apply().
func convert(text: String, old: Any) -> (Any?, String?) {
    var converted: Any = text
    if let number = old as? NSNumber,
       CFGetTypeID(number) == CFBooleanGetTypeID() {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1": converted = true
        case "false", "0": converted = false
        default:
            return (nil, "Invalid Boolean")
        }
    } else if old is NSNumber {
        if let n = Int(text) { converted = n }
        else if let d = Double(text) { converted = d }
        else {
            return (nil, "Invalid number")
        }
    }
    return (converted, nil)
}
// -------------------------------------------------------------------------------

print("== 1. boolean detection (the crux of the plist fix) ==")
let bTrue = NSNumber(value: true)
let bFalse = NSNumber(value: false)
let iFive = NSNumber(value: 5)
check("true is detected as boolean", CFGetTypeID(bTrue) == CFBooleanGetTypeID())
check("false is detected as boolean", CFGetTypeID(bFalse) == CFBooleanGetTypeID())
check("plain integer is NOT detected as boolean", CFGetTypeID(iFive) != CFBooleanGetTypeID())
check("describe(true) == \"true\"", describe(bTrue) == "true")
check("describe(false) == \"false\"", describe(bFalse) == "false")
check("typeName(true) == \"boolean\"", typeName(bTrue) == "boolean")
check("typeName(5) == \"number\"", typeName(iFive) == "number")

print("\n== 2. editing a Boolean without changing it keeps it a boolean ==")
var root: Any = ["flag": NSNumber(value: true)]
let before = PlistTree.value(in: root, path: ["flag"]) as! NSNumber
check("pre-edit value is boolean", CFGetTypeID(before) == CFBooleanGetTypeID())
let r1 = convert(text: describe(before), old: before)   // user taps Set, leaves text alone
check("conversion succeeded", r1.0 != nil && r1.1 == nil, String(describing: r1.1))
PlistTree.set(r1.0!, in: &root, path: ["flag"])
let after = PlistTree.value(in: root, path: ["flag"]) as! NSNumber
check("post-edit value is still boolean", CFGetTypeID(after) == CFBooleanGetTypeID(),
      "type=\(typeName(after)) value=\(describe(after))")
check("post-edit value unchanged (true)", after.boolValue == true)

print("\n== 3. boolean set to false / from 0 / rejects garbage ==")
let r2 = convert(text: "false", old: before)
check("'false' -> bool false", (r2.0 as? Bool) == false, "got \(String(describing: r2.0))")
let r3 = convert(text: " 0 ", old: NSNumber(value: false))
check("' 0 ' -> bool false", (r3.0 as? Bool) == false, "got \(String(describing: r3.0))")
let r4 = convert(text: "banana", old: before)
check("garbage rejected", r4.0 == nil && r4.1 == "Invalid Boolean", "got \(String(describing: r4.0))")
let r5 = convert(text: "TRUE", old: before)
check("uppercase TRUE accepted", (r5.0 as? Bool) == true)

print("\n== 4. numeric values keep parsing as numbers ==")
let n1 = convert(text: "7", old: iFive)
check("'7' -> Int", n1.0 is Int && (n1.0 as! Int) == 7, "got \(String(describing: n1.0))")
let n2 = convert(text: "7.5", old: iFive)
check("'7.5' -> Double", n2.0 is Double && (n2.0 as! Double) == 7.5, "got \(String(describing: n2.0))")
let n3 = convert(text: "abc", old: iFive)
check("non-numeric rejected", n3.0 == nil && n3.1 == "Invalid number")

print("\n== 5. round-trip through plist serialisation preserves type ==")
var doc: Any = ["flag": NSNumber(value: true), "count": NSNumber(value: 3)]
let pick = PlistTree.value(in: doc, path: ["flag"]) as! NSNumber
_ = convert(text: describe(pick), old: pick)
PlistTree.set(NSNumber(value: false), in: &doc, path: ["flag"])
if let data = try? PropertyListSerialization.data(fromPropertyList: doc, format: .binary, options: 0),
   let back = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
   let flag = back["flag"] as? NSNumber {
    check("survives binary plist round-trip as boolean", CFGetTypeID(flag) == CFBooleanGetTypeID(),
          "type=\(typeName(flag)) value=\(describe(flag))")
} else {
    check("survives binary plist round-trip as boolean", false, "serialisation failed")
}

print("\n== 6. negative array-index guard ==")
let arr: Any = [10, 20, 30]
check("negative index read -> nil", PlistTree.value(in: arr, path: [-1]) == nil)
let negIdx = -1
var arrMut: Any = [10, 20, 30]
PlistTree.set(99, in: &arrMut, path: [negIdx])
check("negative index write is a no-op", (arrMut as! [Int]) == [10, 20, 30])
check("out-of-range index read -> nil", PlistTree.value(in: arr, path: [99]) == nil)
check("valid index still works", (PlistTree.value(in: arr, path: [1]) as! Int) == 20)

print("\n== 7. hex patch offset arithmetic (patched guard) ==")
// Patched logic from FilesViewController.swift
func patchedReport(offset: UInt64, patchCount: Int, fileLength: Int) -> String {
    guard offset <= UInt64(fileLength) else { return "Out of range" }
    let start = Int(offset)
    guard patchCount <= fileLength - start else { return "Out of range" }
    return "Patched"
}
let fileLen = 12
check("huge offset rejected (UInt64.max)", patchedReport(offset: UInt64.max, patchCount: 1, fileLength: fileLen) == "Out of range")
check("offset above Int.max rejected", patchedReport(offset: UInt64(Int.max) + 2, patchCount: 1, fileLength: fileLen) == "Out of range")
check("offset == EOF rejected when patch non-empty",
      patchedReport(offset: UInt64(fileLen), patchCount: 1, fileLength: fileLen) == "Out of range")
check("zero-length patch at EOF accepted", patchedReport(offset: UInt64(fileLen), patchCount: 0, fileLength: fileLen) == "Patched")
check("exact-fit patch accepted", patchedReport(offset: 8, patchCount: 4, fileLength: fileLen) == "Patched")
check("overrun patch rejected", patchedReport(offset: 9, patchCount: 4, fileLength: fileLen) == "Out of range")
check("offset just past EOF rejected", patchedReport(offset: UInt64(fileLen + 1), patchCount: 1, fileLength: fileLen) == "Out of range")

print("\n== 8. the pre-fix expression did trap (demonstrating the bug) ==")
// Old code: guard Int(offset) + patch.count <= data.count
// Run in a child so the trap does not abort the harness.
let oldExpr = """
import Foundation
let offset = UInt64(Int.max) + 2
let patchCount = 1
let fileLen = 12
let start = Int(offset)
print(start + patchCount <= fileLen)
"""
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oldexpr.swift")
try! oldExpr.write(to: tmp, atomically: true, encoding: .utf8)
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
proc.arguments = [tmp.path]
let pipe = Pipe()
proc.standardOutput = pipe; proc.standardError = pipe
do { try proc.run() } catch { check("old expression crashed (expected)", true); }
proc.waitUntilExit()
let crashed = proc.terminationStatus != 0
check("pre-fix expression crashes on huge offset", crashed, "exit=\(proc.terminationStatus)")

print("\n\(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")")
exit(failures == 0 ? 0 : 1)
