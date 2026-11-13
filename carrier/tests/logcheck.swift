// Concurrency check for the patched Logger design (ViewController.swift, finding #3).
// Structure copied verbatim: NSRecursiveLock + beginTest/note/endTest/append.
import Foundation

final class LockedLogger {
    private var handle: FileHandle?
    private let lock = NSRecursiveLock()
    private var testLines: [String] = []
    private var inTest = false
    private(set) var written: [String] = []

    init(path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path))
    }

    func beginTest(_ id: String, _ title: String) {
        lock.lock(); defer { lock.unlock() }
        inTest = true
        testLines.removeAll()
        append("", toScreen: false)
        append("--- TEST \(id) START  \(title)")
    }

    @discardableResult
    func endTest(_ id: String, elapsed: TimeInterval) -> String {
        lock.lock(); defer { lock.unlock() }
        let failed = testLines.contains { $0.contains("[NO]") }
        let produced = !testLines.isEmpty
        let result = !produced ? "skipped" : (failed ? "fail" : "ok")
        append("--- TEST \(id) END    result: \(result)")
        inTest = false
        return result
    }

    func note(_ text: String) { append(text) }

    private func append(_ message: String, toScreen: Bool = true) {
        lock.lock(); defer { lock.unlock() }
        let line = message.isEmpty ? "" : "[\(message)]"
        written.append(line)
        if let data = (line + "\n").data(using: .utf8) {
            handle?.seekToEndOfFile()
            handle?.write(data)
        }
        if inTest && !message.isEmpty { testLines.append(message) }
    }
}

var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : "  [\(detail)]")")
    if !ok { failures += 1 }
}

print("== A. beginTest()->append() nesting must not deadlock (needs a recursive lock) ==")
let l1 = LockedLogger(path: "/tmp/logcheck_a.log")
l1.beginTest("01", "IOSurface")
l1.note("hello")
check("nested lock acquisition returned", l1.endTest("01", elapsed: 0.1) == "ok")

print("\n== B. plain NSLock WOULD deadlock here (why the recursive lock is required) ==")
final class PlainLockLogger {
    private let lock = NSLock()
    func beginTest(_ appendInside: () -> Void) {
        lock.lock()
        appendInside()          // calls append(), which also locks -> deadlock under NSLock
        lock.unlock()
    }
    func append() { lock.lock(); lock.unlock() }
}
let p = PlainLockLogger()
let done = DispatchSemaphore(value: 0)
DispatchQueue.global().async {
    p.beginTest { p.append() }
    done.signal()
}
let resumed = done.wait(timeout: .now() + 2)
check("NSLock variant hangs (as predicted)", resumed == .timedOut,
      resumed == .timedOut ? "still blocked after 2 s" : "completed unexpectedly")

print("\n== C. serial runs attribute results correctly ==")
let l2 = LockedLogger(path: "/tmp/logcheck_c.log")
for i in 1...4 {
    l2.beginTest(String(format: "%02d", i), "probe \(i)")
    l2.note("note-\(i)-a"); l2.note("note-\(i)-b")
    if i == 3 { l2.note("[NO] deliberate failure") }
    let r = l2.endTest(String(format: "%02d", i), elapsed: 0.5)
    check("run \(i) result", r == (i == 3 ? "fail" : "ok"), "got \(r)")
}
let noteCount = l2.written.filter { $0.hasPrefix("[note-") }.count
check("all 8 notes recorded exactly once", noteCount == 8, "got \(noteCount)")

print("\n== D. concurrent runs: nothing lost or corrupted ==")
let l3 = LockedLogger(path: "/tmp/logcheck_d.log")
let wg = DispatchGroup()
for t in 1...6 {
    wg.enter()
    DispatchQueue.global().async {
        l3.beginTest("T\(t)", "concurrent \(t)")
        for j in 1...40 { l3.note("T\(t)-\(j)") }
        l3.endTest("T\(t)", elapsed: 0.2)
        wg.leave()
    }
}
_ = wg.wait(timeout: .now() + 30)
let expected = 6 * (2 + 40)   // start + end + 40 notes per run
let actual = l3.written.filter { !$0.isEmpty }.count
check("every line survived concurrency", actual == expected, "expected \(expected), got \(actual)")
let nonBlank = l3.written.filter { !$0.isEmpty }
let dupes = Set(nonBlank).count != nonBlank.count
check("no duplicated lines", !dupes, "\(nonBlank.count) non-blank, \(Set(nonBlank).count) distinct")
let broken = l3.written.contains { $0.hasPrefix("[note-") && $0.hasSuffix("][") }
check("no interleaved/mangled lines", !broken)
let allNotes = l3.written.filter { $0.hasPrefix("[T") && $0.contains("-") && !$0.contains("TEST") }.count
check("all 240 notes present", allNotes == 240, "got \(allNotes)")

print("\n== E. file contents match in-memory record ==")
if let onDisk = try? String(contentsOfFile: "/tmp/logcheck_d.log", encoding: .utf8) {
    let diskLines = onDisk.split(separator: "\n").filter { !$0.isEmpty }.count
    check("on-disk line count == in-memory", diskLines == expected, "disk=\(diskLines) mem=\(expected)")
} else {
    check("on-disk log readable", false)
}

print("\n\(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")")
exit(failures == 0 ? 0 : 1)
