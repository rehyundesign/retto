import Foundation
import Darwin

func checkNativeTaskStatus(_ check: (Bool, String) -> Void) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retto-native-status-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    func write(_ id: String, _ status: String, time: Double = 100, pid: Int32 = 1,
               entrypoint: String = "claude-desktop", kind: String = "interactive", start: String = "fixture", fileName: String? = nil) {
        let value: [String: Any] = ["pid": pid, "sessionId": id, "status": status, "statusUpdatedAt": time,
            "kind": kind, "entrypoint": entrypoint, "pidDomain": "darwin", "procStart": start,
            "name": "never-log-title", "messagingSocketPath": "never-connect-socket"]
        try! JSONSerialization.data(withJSONObject: value).write(to: directory.appendingPathComponent("\(fileName ?? id).json"))
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
    let completed = reconcileCodexTask(payload: payload("waiting", source: "codex"), indexTitle: nil,
        transcriptStatus: CodexTranscriptStatus(completedAtMs: 600, latestPromptAtMs: 400))
    let disconnectedCompletion = unavailableCodexTask(completed)
    check(disconnectedCompletion.state == .waving && disconnectedCompletion.needsAttention
        && disconnectedCompletion.source == .rollout,
          "unavailable live owner preserves transcript-confirmed unread completion")
    let failure = ReconciledCodexTask(state: .failed, observedAtMs: 600,
        needsAttention: true, title: nil, source: .hook)
    check(unavailableCodexTask(failure).state == .failed && unavailableCodexTask(failure).needsAttention,
          "transport loss preserves independently reported failure alerts")
    for state in [PetState.waiting, .running] {
        let uncertain = unavailableCodexTask(ReconciledCodexTask(state: state, observedAtMs: 500,
            needsAttention: true, title: nil, source: .hook))
        check(uncertain.state == .idle && !uncertain.needsAttention && uncertain.source == .unavailable,
              "unavailable live state does not preserve an unconfirmed \(state.rawValue) hook")
    }
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
    let currentLog = directory.appendingPathComponent("status-current.json")
    let current = try! JSONSerialization.jsonObject(with: Data(contentsOf: currentLog)) as! [[String: Any]]
    check(current.count == 1 && current[0]["displayState"] as? String == "idle", "current state is inspectable independently of bounded transition history")
    check(Set(records[0].keys).isSubset(of: ["atMs", "sessionId", "client", "hookState", "displayState", "source", "requestIds", "requestMethods", "waitingFlags", "nativeTurnMessageId", "revision", "hookEvent", "turnId", "stateChangedAtMs", "nativeState"]),
          "diagnostic output contains only state metadata, never titles, prompts, arguments or sockets")
    write("vscode", "waiting", time: 250, entrypoint: "claude-vscode")
    reader.refresh(now: Date(timeIntervalSince1970: 1))
    check(reader.statuses["vscode"]?.state == .waiting, "wall clock rollback re-reads native state rather than retaining cached working or waiting")
    write("desktop", "waiting", time: 300, fileName: "shared-desktop")
    write("desktop", "busy", time: 400, entrypoint: "claude-vscode", fileName: "shared-vscode")
    reader.refresh(now: Date(timeIntervalSince1970: 4))
    check(reader.statuses["desktop"] == nil, "ambiguous clients do not produce a session-only native fallback")
    let desktopPayload = payload("running")
    let vscodePayload = try! JSONDecoder().decode(StatePayload.self, from: Data(#"{"sessionId":"desktop","state":"waiting","source":"claude","client":"vscode"}"#.utf8))
    check(reader.status(for: desktopPayload)?.state == .waiting, "Desktop uses its own native waiting when VS Code holds the same session")
    check(reader.status(for: vscodePayload)?.state == .running, "VS Code does not inherit Desktop waiting for the same session")
    check(applyClaudeNativeStatus(reader.status(for: desktopPayload), to: vscodePayload).stateSource == "unavailable", "a mismatched native client cannot turn another app's task blue")
    write("desktop", "idle", time: 500, fileName: "second-desktop")
    reader.refresh(now: Date(timeIntervalSince1970: 5))
    check(reader.status(for: desktopPayload) == nil, "conflicting live holders in one app are unconfirmed instead of chosen by timestamp")
    try! Data("{truncated".utf8).write(to: directory.appendingPathComponent("shared-vscode.json"))
    reader.refresh(now: Date(timeIntervalSince1970: 6))
    check(reader.status(for: vscodePayload) == nil && reader.statuses["idle"]?.state == .idle,
          "a malformed native record does not retain its old state or erase another healthy session")
    diagnostics.retain([])
    diagnostics.flush()
    let emptyCurrent = try! JSONSerialization.jsonObject(with: Data(contentsOf: currentLog)) as! [[String: Any]]
    check(emptyCurrent.isEmpty, "closed or untracked tasks do not leave current diagnostic state behind")
    diagnostics.stop()
    try! FileManager.default.removeItem(at: log)
    try! FileManager.default.removeItem(at: currentLog)
    diagnostics.retain([input.id])
    diagnostics.record(input: input, output: unknown, live: nil)
    diagnostics.flush()
    check(!FileManager.default.fileExists(atPath: log.path) && !FileManager.default.fileExists(atPath: currentLog.path),
          "late callbacks after diagnostics stop cannot recreate removed state files")
}
