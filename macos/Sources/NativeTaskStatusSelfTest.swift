import Foundation
import Darwin

func checkNativeTaskStatus(_ check: (Bool, String) -> Void) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retto-native-status-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func write(_ id: String, _ status: String, time: Double = 100, pid: Int32 = 1,
               entrypoint: String = "claude-desktop", kind: String = "interactive", start: String = "fixture") {
        let value: [String: Any] = ["pid": pid, "sessionId": id, "status": status, "statusUpdatedAt": time,
            "kind": kind, "entrypoint": entrypoint, "pidDomain": "darwin", "procStart": start,
            "name": "never-log-title", "messagingSocketPath": "never-connect-socket"]
        try! JSONSerialization.data(withJSONObject: value).write(to: directory.appendingPathComponent("\(id).json"))
    }
    write("desktop", "waiting")
    write("vscode", "busy", entrypoint: "claude-vscode")
    write("idle", "idle")
    write("dead", "waiting", pid: 2)
    write("reused", "waiting", start: "wrong-start")
    write("worker", "waiting", kind: "subagent")
    write("unsupported", "new-status")
    write("future", "waiting", time: 100_000)
    let reader = ClaudeNativeStatusReader(directory: directory, processMatches: { $0 == 1 && $1 == "fixture" })
    reader.refresh(now: Date(timeIntervalSince1970: 1))
    check(reader.statuses.count == 3, "native reader rejects dead/reused PIDs, workers, future and unsupported records")
    check(reader.statuses["desktop"]?.state == .waiting, "Claude Desktop uses native waiting")
    check(reader.statuses["vscode"]?.state == .running, "VS Code uses native busy")
    func payload(_ state: String, source: String = "claude", event: String = "PermissionRequest") -> StatePayload {
        let object: [String: Any] = ["sessionId": "desktop", "state": state, "source": source,
            "client": source == "codex" ? "codex" : "claude", "event": event, "updatedAtMs": 500, "attention": true]
        return try! JSONDecoder().decode(StatePayload.self, from: JSONSerialization.data(withJSONObject: object))
    }
    let busy = ClaudeNativeStatus(state: .running, changedAtMs: 100)
    check(applyClaudeNativeStatus(busy, to: payload("waiting")).petState == .running,
          "late Claude permission hook cannot override current native busy")
    let idle = ClaudeNativeStatus(state: .idle, changedAtMs: 100)
    check(applyClaudeNativeStatus(idle, to: payload("waiting")).petState == .idle,
          "native idle clears stale Claude waiting")
    check(applyClaudeNativeStatus(reader.statuses["desktop"], to: payload("running")).petState == .waiting,
          "native Claude waiting is not cleared by unrelated tool activity")
    check(applyClaudeNativeStatus(nil, to: payload("waiting")).stateSource == "unavailable",
          "missing Claude native status is unknown instead of a blue hook fallback")
    check(applyClaudeNativeStatus(idle, to: payload("waving")).petState == .waving,
          "native idle preserves completed notification")
    check(applyClaudeNativeStatus(busy, to: payload("waving")).petState == .running,
          "native busy clears stale completion")
    check(applyClaudeNativeStatus(busy, to: payload("waiting", source: "codex")).petState == .waiting,
          "Claude native reader does not alter Codex")
    write("desktop", "busy", time: 200)
    reader.refresh(now: Date(timeIntervalSince1970: 2))
    check(reader.statuses["desktop"]?.state == .running, "approval completion updates before the tool finishes")
    try! FileManager.default.removeItem(at: directory.appendingPathComponent("desktop.json"))
    reader.refresh(now: Date(timeIntervalSince1970: 3))
    check(reader.statuses["desktop"] == nil, "removed native records do not leave cached waiting")
    check(!ClaudeNativeStatusReader.sameProcess(getpid(), "invalid-process-start"), "real process check rejects a mismatched creation time")
    let unknown = applyClaudeNativeStatus(nil, to: payload("waiting"))
    check(taskConnectionNotice(for: unknown, unreadablePaths: [], slackNotice: nil) != nil,
          "unconfirmed input state has an explicit connection notice")
    let log = directory.appendingPathComponent("diagnostic.json")
    let diagnostics = TaskStatusDiagnostics(url: log)
    let input = payload("waiting")
    diagnostics.record(input: input, output: unknown, live: nil)
    diagnostics.record(input: input, output: unknown, live: nil)
    diagnostics.flush()
    let records = try! JSONSerialization.jsonObject(with: Data(contentsOf: log)) as! [[String: Any]]
    check(records.count == 1 && records[0]["source"] as? String == "unavailable", "diagnostics record a transition once")
    check(Set(records[0].keys).isSubset(of: ["atMs", "sessionId", "client", "hookState", "displayState", "source", "requestIds", "requestMethods", "waitingFlags", "nativeTurnMessageId", "revision", "hookEvent", "turnId", "stateChangedAtMs", "nativeState"]),
          "diagnostic output contains only state metadata, never titles, prompts, arguments or sockets")
}
