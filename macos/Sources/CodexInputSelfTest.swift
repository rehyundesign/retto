import Foundation

func runCodexInputSelfTest() -> Int32 {
    var failures: [String] = []
    var checks = 0
    func check(_ value: Bool, _ name: String) { checks += 1; if !value { failures.append(name) } }
    func record(_ second: Int, _ payload: [String: Any]) -> String {
        let value: [String: Any] = ["timestamp": String(format: "2026-10-26T06:11:%02d.000Z", second),
                                    "type": "response_item", "payload": payload]
        return String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
    }
    func request(_ id: String, _ count: Int = 1) -> String {
        let arguments = String(data: try! JSONSerialization.data(withJSONObject:
            ["questions": Array(repeating: ["title": "fixture"], count: count)]), encoding: .utf8)!
        return record(1, ["type": "function_call", "name": "request_user_input_async", "call_id": id, "arguments": arguments])
    }
    func answer(_ id: String, _ index: Int = 0) -> String {
        let itemId = String(data: try! JSONSerialization.data(withJSONObject: ["request_user_input_async", id, index]), encoding: .utf8)!
        let body = String(data: try! JSONSerialization.data(withJSONObject: [["questionItemId": itemId, "answer": "yes"]]), encoding: .utf8)!
        return record(4, ["type": "message", "role": "user", "content": [["text": "<send_user_message_question_reply>\(body)</send_user_message_question_reply>"]]])
    }
    let toolOutput = record(2, ["type": "function_call_output", "call_id": "a", "output": "request submitted"])
    let otherTool = record(3, ["type": "function_call", "name": "exec_command", "call_id": "other", "arguments": "{}"])
    let pending = codexTranscriptStatus(in: [request("a"), toolOutput, otherTool].joined(separator: "\n"))
    check(pending.pendingInputAtMs != nil, "async request survives immediate output and later tools")
    let answered = codexTranscriptStatus(in: [request("a"), toolOutput, answer("a")].joined(separator: "\n"))
    check(answered.pendingInputAtMs == nil, "matching reply resolves input")
    check(pending.merged(with: codexTranscriptStatus(in: answer("a"))).pendingInputAtMs == nil, "incremental reply resolves input")
    check(answered.merged(with: pending).pendingInputAtMs == nil, "overlapping scan does not resurrect input")
    check(codexTranscriptStatus(in: request("a", 2) + "\n" + answer("a")).pendingInputAtMs != nil, "partial answer remains pending")
    check(codexTranscriptStatus(in: request("a") + "\n" + answer("b")).pendingInputAtMs != nil, "unrelated reply does not dismiss input")
    check(codexTranscriptStatus(in: request("a") + "\n" + answer("a") + "\n" + request("b")).pendingInputAtMs != nil, "next request waits")
    check(displayState(state: .waiting, updatedAtMs: 1, seenAtMs: 100, transcriptModifiedAtMs: 1, nowMs: 100_000) == .waiting, "viewing never dismisses pending input")
    check(selectionPriority(state: .waiting, isClosed: false) > selectionPriority(state: .waving, isClosed: false, source: "slack"), "input before Slack")
    let payload = try! JSONDecoder().decode(StatePayload.self, from: Data("{\"state\":\"running\",\"sessionId\":\"fixture\",\"updatedAtMs\":1}".utf8))
    let reconciled = reconcileCodexTask(payload: payload, indexTitle: "fixture", transcriptStatus: pending)
    check(reconciled.state == .waiting && reconciled.needsAttention, "running hook reconciles to waiting")
    let waiting = try! JSONDecoder().decode(StatePayload.self, from: Data("{\"state\":\"waiting\",\"sessionId\":\"fixture\",\"updatedAtMs\":1}".utf8))
    check(reconcileCodexTask(payload: waiting, indexTitle: nil, transcriptStatus: answered).state == .running, "reply releases stale waiting hook")
    let attentionWaiting = try! JSONDecoder().decode(StatePayload.self, from: Data("{\"state\":\"waiting\",\"sessionId\":\"waiting\",\"attention\":true}".utf8))
    let slack = try! JSONDecoder().decode(StatePayload.self, from: Data("{\"state\":\"waving\",\"source\":\"slack\",\"sessionId\":\"slack\",\"attention\":true}".utf8))
    func priority(_ p: StatePayload) -> Int { selectionPriority(state: p.petState, isClosed: p.isClosed, source: p.source) }
    check(preferredPinnedSession(slack, attention: [attentionWaiting, slack], priority: priority, needsAttention: { $0.needsAttention }).id == attentionWaiting.id, "input overrides pinned Slack")
    check(preferredPinnedSession(attentionWaiting, attention: [slack], priority: priority, needsAttention: { $0.needsAttention }).id == attentionWaiting.id, "Slack cannot replace pinned input")
    let completedPending = CodexTranscriptStatus(completedAtMs: 100, latestPromptAtMs: 1, inputRequests: ["a:0": 2])
    check(!completedPending.isCompletedAfterLatestPrompt, "pending input survives task completion")
    let decoded = try! JSONDecoder().decode(CodexTranscriptStatus.self, from: JSONEncoder().encode(pending))
    check(decoded.pendingInputAtMs == pending.pendingInputAtMs, "pending state persists")
    func event(_ second: Int, _ payload: [String: Any]) -> String {
        let value: [String: Any] = ["timestamp": String(format: "2026-10-26T06:11:%02d.000Z", second), "type": "event_msg", "payload": payload]
        return String(data: try! JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
    }
    let abort = event(5, ["type": "turn_aborted", "turn_id": "turn-a", "reason": "interrupted"])
    let taggedRequest = record(1, ["type": "function_call", "name": "request_user_input_async", "call_id": "a",
        "arguments": "{\"questions\":[{\"title\":\"fixture\"}]}", "internal_chat_message_metadata_passthrough": ["turn_id": "turn-a"]])
    let tagged = codexTranscriptStatus(in: taggedRequest)
    let cancelled = tagged.merged(with: codexTranscriptStatus(in: abort))
    check(cancelled.pendingInputAtMs == nil, "turn interruption releases its question")
    check(cancelled.merged(with: tagged).pendingInputAtMs == nil, "overlap cannot restore cancelled question")
    let unrelatedAbort = event(5, ["type": "turn_aborted", "turn_id": "turn-b"])
    check(tagged.merged(with: codexTranscriptStatus(in: unrelatedAbort)).pendingInputAtMs != nil, "unrelated turn interruption preserves question")
    func start(_ second: Int, _ turn: String, _ trigger: String) -> String {
        event(second, ["type": "task_started", "turn_id": turn,
                       "turn_attribution": ["turn_id": turn, "turn_trigger": trigger]])
    }
    let nextStart = start(6, "turn-b", "composer")
    let nextTurn = codexTranscriptStatus(in: nextStart)
    let resumed = tagged.merged(with: nextTurn)
    check(resumed.pendingInputAtMs == nil, "new composer turn supersedes previous question")
    check(codexTranscriptStatus(in: taggedRequest + "\n" + nextStart).pendingInputAtMs == nil,
          "full transcript releases previous turn question")
    check(resumed.merged(with: tagged).pendingInputAtMs == nil, "overlap cannot restore superseded question")
    check(pending.merged(with: nextTurn).pendingInputAtMs == nil, "new turn releases legacy question without turn ID")
    check(tagged.merged(with: codexTranscriptStatus(in: start(6, "turn-a", "composer"))).pendingInputAtMs != nil,
          "same turn start preserves its pending question")
    check(tagged.merged(with: codexTranscriptStatus(in: start(6, "turn-b", "agent"))).pendingInputAtMs != nil,
          "automatic continuation preserves pending question")
    let laterQuestion = taggedRequest.replacingOccurrences(of: "turn-a", with: "turn-b")
        .replacingOccurrences(of: "06:11:01", with: "06:11:07")
    check(resumed.merged(with: codexTranscriptStatus(in: laterQuestion)).pendingInputAtMs != nil,
          "new turn question still requires input")
    check(reconcileCodexTask(payload: payload, indexTitle: nil, transcriptStatus: resumed).state == .running,
          "resumed running task no longer displays waiting")
    check(reconcileCodexTask(payload: waiting, indexTitle: nil, transcriptStatus: resumed).state == .running,
          "new turn releases stale waiting hook")
    let completedBeforeRestart = codexTranscriptStatus(in: event(5, ["type": "task_complete"]))
    check(!completedBeforeRestart.merged(with: nextTurn).isCompletedAfterLatestPrompt,
          "new turn start invalidates old completion before prompt arrives")
    let abortedBeforeRestart = codexTranscriptStatus(in: abort).merged(with: nextTurn)
    check(reconcileCodexTask(payload: waiting, indexTitle: nil, transcriptStatus: abortedBeforeRestart).state == .running,
          "new turn start invalidates old interruption before prompt arrives")
    let currentWaiting = try! JSONDecoder().decode(StatePayload.self, from: JSONSerialization.data(withJSONObject:
        ["state": "waiting", "sessionId": "fixture", "updatedAtMs": (nextTurn.latestComposerStartAtMs ?? 0) + 1]))
    check(reconcileCodexTask(payload: currentWaiting, indexTitle: nil, transcriptStatus: nextTurn).state == .waiting,
          "permission requested in current turn remains waiting")
    let unknownTrigger = codexTranscriptStatus(in: event(6, ["type": "task_started", "turn_id": "turn-b"]))
    check(tagged.merged(with: unknownTrigger).pendingInputAtMs != nil, "unknown turn trigger does not dismiss question")
    let resumedRoundtrip = try! JSONDecoder().decode(CodexTranscriptStatus.self, from: JSONEncoder().encode(resumed))
    check(resumedRoundtrip.pendingInputAtMs == nil, "superseded question remains resolved after restart")
    let completedResumed = resumed.merged(with: codexTranscriptStatus(in: event(8, ["type": "task_complete"])))
    check(reconcileCodexTask(payload: waiting, indexTitle: nil, transcriptStatus: completedResumed).state == .waving,
          "new turn completion replaces stale waiting hook")
    check(pending.merged(with: codexTranscriptStatus(in: abort)).pendingInputAtMs == nil, "legacy request without turn releases on interruption")
    check(reconcileCodexTask(payload: waiting, indexTitle: nil, transcriptStatus: cancelled).state == .idle, "interrupted hook waiting releases")
    let sync = request("sync").replacingOccurrences(of: "request_user_input_async", with: "functions.request_user_input")
    let syncPending = codexTranscriptStatus(in: sync)
    let syncOutput = record(3, ["type": "function_call_output", "call_id": "sync", "output": "{\"answers\":{}}"])
    check(syncPending.pendingInputAtMs != nil, "synchronous question detected")
    check(syncPending.merged(with: codexTranscriptStatus(in: syncOutput)).pendingInputAtMs == nil, "synchronous answer releases input across scans")
    check(reconcileCodexTask(payload: waiting, indexTitle: nil, transcriptStatus: syncPending.merged(with: codexTranscriptStatus(in: syncOutput))).state == .running, "synchronous reply releases old hook")
    let empty = CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
    check(reconcileCodexTask(payload: waiting, indexTitle: nil, transcriptStatus: empty).state == .waiting, "permission hook remains without reply evidence")
    check(IntegrationConnectionState.connected.notice(service: "Slack") == nil, "connected has no warning")
    check(IntegrationConnectionState.disabled.notice(service: "Slack") == nil, "unconfigured connection has no warning")
    check(IntegrationConnectionState.reconnecting.notice(service: "Slack")?.contains("재연결") == true, "reconnection distinguished from no messages")
    check(IntegrationConnectionState.failed.notice(service: "Slack")?.contains("확인 필요") == true, "terminal connection failure visible")
    let inputBadge = attentionBadgeSessions([attentionWaiting, slack], needsAttention: { $0.needsAttention })
    check(inputBadge.map(\.id) == [attentionWaiting.id] && attentionSummary(inputBadge) == "입력 필요 1개", "input badge count and list agree")
    check(attentionBadgeSessions([slack], needsAttention: { $0.needsAttention }).map(\.id) == [slack.id], "Slack returns after input resolved")
    let cancelledRoundtrip = try! JSONDecoder().decode(CodexTranscriptStatus.self, from: JSONEncoder().encode(cancelled))
    check(cancelledRoundtrip.pendingInputAtMs == nil, "cancelled input stays resolved after restart")
    let legacy = try! JSONDecoder().decode(CodexTranscriptStatus.self, from: Data("{\"completedAtMs\":1}".utf8))
    check(legacy.pendingInputAtMs == nil, "older status format remains decodable")
    let brokenPrefix = Data([0x80, 0x80, 10]) + Data(request("utf8").utf8)
    check(codexTranscriptStatus(in: codexTranscriptText(brokenPrefix, skipPartialFirstLine: true)).pendingInputAtMs != nil,
          "byte range beginning inside Korean character retains later requests")
    func healthFixture(_ source: String, _ state: String, _ path: String) -> StatePayload {
        let object = ["source": source, "state": state, "sessionId": "health-fixture", "transcriptPath": path]
        return try! JSONDecoder().decode(StatePayload.self, from: JSONSerialization.data(withJSONObject: object))
    }
    let currentWork = healthFixture("codex", "running", "/fixture/current.jsonl")
    let otherMissing: Set<String> = ["/fixture/other.jsonl"]
    check(taskConnectionNotice(for: currentWork, unreadablePaths: otherMissing, slackNotice: "Slack 재연결 중") == nil,
          "other session and Slack issues never appear on current Codex task")
    check(taskConnectionNotice(for: currentWork, unreadablePaths: ["/fixture/current.jsonl"], slackNotice: nil) != nil,
          "current active task read failure remains visible")
    let completedWork = healthFixture("codex", "waving", "/fixture/current.jsonl")
    check(taskConnectionNotice(for: completedWork, unreadablePaths: ["/fixture/current.jsonl"], slackNotice: nil) == nil,
          "missing completed task record does not produce bubble warning")
    check(taskConnectionNotice(for: nil, unreadablePaths: otherMissing, slackNotice: "Slack 연결 중") == nil,
          "empty task placeholder does not display unrelated diagnostics")
    check(taskConnectionNotice(for: slack, unreadablePaths: otherMissing, slackNotice: "Slack 재연결 중") == "Slack 재연결 중",
          "Slack warning only appears on selected Slack message")
    let claudeWork = healthFixture("claude", "running", "/fixture/current.jsonl")
    check(taskConnectionNotice(for: claudeWork, unreadablePaths: ["/fixture/current.jsonl"], slackNotice: "Slack 재연결 중") == nil,
          "Codex and Slack diagnostics do not appear on Claude tasks")
    print("Codex input self-test: \(checks) checks, \(failures.count) failures")
    for failure in failures { print("FAIL: \(failure)") }
    if let flag = CommandLine.arguments.firstIndex(of: "--input-transcript"), CommandLine.arguments.count > flag + 1 {
        let path = CommandLine.arguments[flag + 1]
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let status = codexTranscriptStatus(in: text)
        print("Transcript: requests=\(status.inputRequests?.count ?? 0), replies=\(status.inputReplies?.count ?? 0), pending=\(status.pendingInputAtMs != nil)")
        let lines = text.split(separator: "\n")
        if let lastReply = lines.lastIndex(where: { line in
            guard let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = record["payload"] as? [String: Any],
                  payload["role"] as? String == "user" else { return false }
            return String(describing: payload["content"] ?? "").contains("<send_user_message_question_reply>")
        }) {
            let beforeReply = codexTranscriptStatus(in: lines[..<lastReply].joined(separator: "\n"))
            print("Transcript before latest reply: pending=\(beforeReply.pendingInputAtMs != nil)")
        }
    }
    return failures.isEmpty ? 0 : 1
}
