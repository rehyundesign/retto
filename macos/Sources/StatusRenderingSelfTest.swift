import AppKit
import Foundation

/// 원본 상태 보정부터 실제 배지·접근성 표시까지 같은 뷰에서 반복 검증한다.
func runStatusRenderingSelfTest(outputDirectory: URL? = nil) -> Int32 {
    _ = registerRettoFont()
    let output = outputDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("retto-status-render-" + UUID().uuidString)
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    defer { if outputDirectory == nil { try? FileManager.default.removeItem(at: output) } }
    let image = NSImage(contentsOf: Bundle.main.url(forResource: "spritesheet", withExtension: "webp")!)!
    let size = petLayout(scale: 1).windowSize
    // The same production view receives every transition, including duplicate values.
    let view = RettoView(frame: NSRect(origin: .zero, size: size), spriteSheet: image,
                         onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
    var checks = 0
    var failures: [String] = []
    func check(_ ok: Bool, _ name: String) {
        checks += 1
        if !ok { failures.append(name); print("FAIL: \(name)") }
    }
    func payload(_ client: String = "codex") -> StatePayload {
        let value: [String: Any] = ["sessionId": "render-fixture", "state": "waiting",
            "source": client == "codex" ? "codex" : "claude", "client": client,
            "updatedAtMs": 1, "attention": true, "sessionTitle": "상태 전환 검사"]
        return try! JSONDecoder().decode(StatePayload.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func paint(_ name: String) {
        view.settleAnimations()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor.white.setFill(); view.bounds.fill(); view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        try! rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
    }
    func display(_ result: StatePayload, input expectedInput: Int, attention expectedAttention: Int, name: String, render: Bool = false) {
        let attention = attentionBadgeSessions([result], needsAttention: { $0.needsAttention })
        let input = attention.filter { $0.petState == .waiting }.count
        check(input == expectedInput && attention.count == expectedAttention, name + " aggregate")
        view.apply(result, state: result.petState, liveMessage: name, sessionCount: 1,
            attentionCount: attention.count, attentionState: attention.first?.petState,
            attentionSource: attention.first?.source, inputCount: input,
            connectionStatus: result.stateSource == "unavailable" ? "상태 확인 중" : nil, isPinned: false)
        let label = view.accessibilityLabel() ?? ""
        check(label.contains("입력 필요") == (expectedInput > 0), name + " real view input label")
        check(label.contains("새 알림") == (expectedInput == 0 && expectedAttention > 0), name + " real view terminal label")
        if render { paint(name) }
    }
    func snapshot(_ revision: Int, _ runtime: String, flags: [String] = [], requests: [[String: Any]] = []) -> [String: Any] {
        ["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": "owner",
         "params": ["hostId": "local", "conversationId": "render-fixture", "change": ["type": "snapshot",
            "revision": revision, "conversationState": ["id": "render-fixture", "resumeState": "resumed",
                "threadRuntimeStatus": ["type": runtime, "activeFlags": flags], "requests": requests]]]]
    }
    let original = payload()
    let empty = CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
    var store = CodexLiveStatusStore()
    func codex(_ event: [String: Any], _ name: String, input: Int, attention: Int, render: Bool = false) {
        _ = store.consume(event, nowMs: Double(checks + 1000))
        let base = reconcileCodexTask(payload: original, indexTitle: nil, transcriptStatus: empty)
        let task = applyCodexLiveStatus(store.statuses["render-fixture"], to: base, transcriptStatus: empty)
        var result = original
        result.state = task.state.rawValue; result.attention = task.needsAttention; result.stateSource = task.source.rawValue
        display(result, input: input, attention: attention, name: name, render: render)
    }
    codex(snapshot(1, "active", flags: ["waitingOnApproval"]), "01-native-waiting", input: 1, attention: 1, render: true)
    codex(snapshot(2, "active"), "02-native-working", input: 0, attention: 0, render: true)
    codex(snapshot(3, "idle"), "03-native-idle", input: 0, attention: 0)
    var revision = 3
    for method in ["mcpServer/elicitation/request", "item/commandExecution/requestApproval", "item/fileChange/requestApproval",
                   "item/permissions/requestApproval", "item/tool/requestUserInput", "item/tool/requestOptionPicker"] {
        revision += 1
        codex(snapshot(revision, "active", requests: [["id": method, "method": method, "completed": false]]), method + " pending", input: 1, attention: 1)
        revision += 1
        codex(snapshot(revision, "active", requests: [["id": method, "method": method, "completed": true]]), method + " completed", input: 0, attention: 0)
    }
    codex(snapshot(1, "active", flags: ["waitingOnApproval"]), "delayed-waiting", input: 0, attention: 0)
    var unsupported = snapshot(revision + 1, "active"); unsupported["version"] = 12
    codex(unsupported, "04-protocol-unknown", input: 0, attention: 0, render: true)
    codex(snapshot(revision + 100, "active", flags: ["waitingOnApproval"]), "quarantined-late-waiting", input: 0, attention: 0)

    let nativeDirectory = output.appendingPathComponent("native-fixtures")
    try! FileManager.default.createDirectory(at: nativeDirectory, withIntermediateDirectories: true)
    let native = ClaudeNativeStatusReader(directory: nativeDirectory, processMatches: { $0 == 1 && $1 == "fixture" })
    var tick = 1000.0
    for (client, entrypoint) in [("claude", "claude-desktop"), ("vscode", "claude-vscode")] {
        let recordURL = nativeDirectory.appendingPathComponent(client + ".json")
        for step in 0..<30 {
            let state = ["waiting", "busy", "idle"][step % 3]
            tick += 1
            let row: [String: Any] = ["pid": 1, "sessionId": "render-fixture", "status": state,
                "statusUpdatedAt": tick * 1000, "procStart": "fixture", "kind": "interactive",
                "entrypoint": entrypoint, "pidDomain": "darwin"]
            try! JSONSerialization.data(withJSONObject: row).write(to: recordURL, options: .atomic)
            native.refresh(now: Date(timeIntervalSince1970: tick))
            let input = payload(client)
            let result = applyClaudeNativeStatus(native.status(for: input), to: input)
            display(result, input: state == "waiting" ? 1 : 0, attention: state == "waiting" ? 1 : 0,
                    name: client + "-" + state + "-" + String(step))
        }
        try! FileManager.default.removeItem(at: recordURL)
        tick += 1; native.refresh(now: Date(timeIntervalSince1970: tick))
        let input = payload(client)
        display(applyClaudeNativeStatus(native.status(for: input), to: input), input: 0, attention: 0, name: client + "-native-record-removed")
    }
    let completed = unavailableCodexTask(reconcileCodexTask(payload: original, indexTitle: nil,
        transcriptStatus: CodexTranscriptStatus(completedAtMs: 600, latestPromptAtMs: 400)))
    var terminal = original; terminal.state = completed.state.rawValue; terminal.attention = completed.needsAttention
    display(terminal, input: 0, attention: 1, name: "05-completed-during-disconnect", render: true)
    let report: [String: Any] = ["checks": checks, "failures": failures,
        "sameProductionViewReused": true, "syntheticNativeRecords": true, "realNativeDialogsExercised": false]
    try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("results.json"))
    print("Native reconciliation to production badge rendering: \(checks) checks, \(failures.count) failures")
    return failures.isEmpty ? 0 : 1
}
