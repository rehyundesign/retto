import Foundation

func checkCodexLiveStatus(_ check: (Bool, String) -> Void) {
    var store = CodexLiveStatusStore()
    func snapshot(_ state: String = "active", flags: [String] = [], requests: [[String: Any]] = [], revision: Int = 1, owner: String = "owner", resume: String = "") -> [String: Any] {
        ["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": owner,
         "params": ["hostId": "local", "conversationId": "fixture", "change": ["type": "snapshot", "revision": revision,
         "conversationState": ["id": "fixture", "threadRuntimeStatus": ["type": state, "activeFlags": flags], "requests": requests, "resumeState": resume]]]]
    }
    func patch(_ patches: [[String: Any]], base: Int, revision: Int, owner: String = "owner") -> [String: Any] {
        ["type": "broadcast", "method": "thread-stream-state-changed", "version": 11, "sourceClientId": owner,
         "params": ["hostId": "local", "conversationId": "fixture", "change": ["type": "patches", "baseRevision": base, "revision": revision, "patches": patches]]]
    }
    func request(_ method: String, completed: Bool = false) -> [String: Any] { ["method": method, "completed": completed] }
    _ = store.consume(snapshot(), nowMs: 100)
    check(store.statuses["fixture"]?.state == .running, "live active without requests is running")
    _ = store.consume(snapshot(flags: ["waitingOnApproval"], revision: 2), nowMs: 200)
    check(store.statuses["fixture"]?.state == .waiting, "live approval flag is waiting")
    _ = store.consume(snapshot(requests: [request("mcpServer/elicitation/request")], revision: 3), nowMs: 300)
    check(store.statuses["fixture"]?.state == .waiting, "file upload MCP elicitation is waiting even without runtime flag")
    _ = store.consume(patch([["op": "replace", "path": ["requests", 0, "completed"], "value": true]], base: 3, revision: 4), nowMs: 400)
    check(store.statuses["fixture"]?.state == .running, "elicitation response releases blue state")
    _ = store.consume(patch([["op": "add", "path": ["requests", 1], "value": request("item/tool/requestUserInput")]], base: 4, revision: 5), nowMs: 500)
    check(store.statuses["fixture"]?.state == .waiting, "array insertion detects a second approval")
    _ = store.consume(patch([["op": "replace", "path": ["title"], "value": "ignored"],
                             ["op": "add", "path": ["requests", 1, "params", "arbitrary"], "value": "ignored"]], base: 5, revision: 6), nowMs: 600)
    check(store.statuses["fixture"]?.observedAtMs == 500, "unrelated updates preserve approval identity and timestamp")
    _ = store.consume(patch([["op": "remove", "path": ["requests", 1]]], base: 6, revision: 7), nowMs: 700)
    check(store.statuses["fixture"]?.state == .running, "resolved request removal releases waiting")
    _ = store.consume(patch([["op": "replace", "path": ["threadRuntimeStatus", "activeFlags"], "value": ["waitingOnUserInput"]]], base: 7, revision: 8), nowMs: 800)
    check(store.statuses["fixture"]?.state == .waiting, "nested runtime user input flag is waiting")
    _ = store.consume(snapshot(revision: 4), nowMs: 900)
    check(store.statuses["fixture"]?.state == .waiting, "older snapshot cannot overwrite a newer approval")
    check(store.consume(patch([], base: 6, revision: 7), nowMs: 900) == nil && store.statuses["fixture"]?.state == .waiting,
          "duplicate patch does not discard newer approval")
    check(store.consume(patch([], base: 8, revision: 9, owner: "previous-owner"), nowMs: 900) == nil
          && store.statuses["fixture"]?.state == .waiting, "previous owner patch cannot overwrite current owner snapshot")
    let gap = store.consume(patch([], base: 20, revision: 21), nowMs: 900)
    check(gap == "fixture" && store.statuses.isEmpty, "revision gap discards stale state and requests snapshot")
    _ = store.consume(snapshot(requests: [request("item/tool/call")]), nowMs: 1000)
    check(store.statuses["fixture"]?.state == .running, "ordinary in-progress tool never becomes blue")
    _ = store.consume(snapshot(requests: [request("mcpServer/elicitation/request", completed: true)], revision: 2), nowMs: 1100)
    check(store.statuses["fixture"]?.state == .running, "completed elicitation in a snapshot remains resolved")
    _ = store.consume(snapshot(flags: ["waitingOnApproval"], revision: 3), nowMs: 1200)
    store.disconnect(owner: "other")
    check(store.statuses["fixture"]?.state == .waiting, "unrelated client disconnect cannot clear approval")
    store.disconnect(owner: "owner")
    check(store.statuses.isEmpty, "owner disconnect discards cached live state")
    var unsupported = snapshot(flags: ["waitingOnApproval"])
    unsupported["version"] = 12
    _ = store.consume(unsupported, nowMs: 1300)
    check(store.statuses.isEmpty, "unknown stream version is not guessed")
    _ = store.consume(snapshot(flags: ["waitingOnApproval"]), nowMs: 1400)
    store.retain([])
    check(store.statuses.isEmpty, "untracked sessions are removed")
    _ = store.consume(snapshot(flags: ["waitingOnApproval"]), nowMs: 1500)
    store.reset()
    check(store.statuses.isEmpty, "connection reset does not leave phantom approval")
    _ = store.consume(snapshot(), nowMs: 1600)
    let malformed = store.consume(patch([["op": "remove", "path": ["requests", 99]]], base: 1, revision: 2), nowMs: 1700)
    check(malformed == "fixture" && store.statuses.isEmpty, "invalid array patch requests a fresh snapshot")
    let empty = CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
    let waiting = ReconciledCodexTask(state: .waiting, observedAtMs: 1, needsAttention: true, title: nil, source: .hook)
    let running = ReconciledCodexTask(state: .running, observedAtMs: 1, needsAttention: false, title: nil, source: .hook)
    let liveRunning = CodexLiveStatus(state: .running, observedAtMs: 20)
    let liveWaiting = CodexLiveStatus(state: .waiting, observedAtMs: 20)
    check(applyCodexLiveStatus(liveWaiting, to: running, transcriptStatus: empty).state == .waiting,
          "live approval overrides running hook")
    check(applyCodexLiveStatus(liveRunning, to: waiting, transcriptStatus: empty).state == .running,
          "live response releases stale permission hook before turn completion")
    check(applyCodexLiveStatus(nil, to: waiting, transcriptStatus: empty).source == .unavailable,
          "unavailable live connection does not turn an unconfirmed permission hook blue")
    let newerWaiting = ReconciledCodexTask(state: .waiting, observedAtMs: 30, needsAttention: true, title: nil, source: .hook)
    check(applyCodexLiveStatus(liveRunning, to: newerWaiting, transcriptStatus: empty).state == .running,
          "a late permission hook cannot override the app's current running state")
    let newerCompletion = CodexTranscriptStatus(completedAtMs: 30, latestPromptAtMs: 1)
    let done = ReconciledCodexTask(state: .waving, observedAtMs: 30, needsAttention: true, title: nil, source: .rollout)
    check(applyCodexLiveStatus(liveWaiting, to: done, transcriptStatus: newerCompletion).state == .waving,
          "older live approval cannot overwrite later completion")
    let nextTurn = CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil, composerTurns: ["new-turn": 30])
    check(applyCodexLiveStatus(liveWaiting, to: running, transcriptStatus: nextTurn).state == .running,
          "older live approval cannot overwrite a new composer turn")
    store.reset()
    _ = store.consume(snapshot(requests: [["id": "first", "method": "mcpServer/elicitation/request"]]), nowMs: 1800)
    _ = store.consume(snapshot(requests: [["id": "second", "method": "mcpServer/elicitation/request"]], revision: 2), nowMs: 1900)
    check(store.statuses["fixture"]?.observedAtMs == 1900, "a different request refreshes waiting observation even with the same method")
    store.reset()
    _ = store.consume(snapshot(), nowMs: 100)
    let autoApprovedHook = ReconciledCodexTask(state: .waiting, observedAtMs: 150, needsAttention: true, title: nil, source: .hook)
    _ = store.consume(snapshot(revision: 2), nowMs: 200)
    check(applyCodexLiveStatus(store.statuses["fixture"], to: autoApprovedHook, transcriptStatus: empty).state == .running,
          "fresh unchanged active snapshot releases auto-approved permission hook")
    check(store.statuses["fixture"]?.observedAtMs == 100,
          "fresh confirmation keeps original state transition timestamp")
    _ = store.consume(snapshot("idle", revision: 3), nowMs: 250)
    check(applyCodexLiveStatus(store.statuses["fixture"], to: autoApprovedHook, transcriptStatus: empty).state == .idle,
          "fresh idle confirmation clears stale waiting without creating completion")
    let freshIdle = CodexLiveStatus(state: .idle, observedAtMs: 20, confirmedAtMs: 40)
    let confirmedCompletion = applyCodexLiveStatus(freshIdle, to: waiting,
        transcriptStatus: CodexTranscriptStatus(completedAtMs: 15, latestPromptAtMs: 1))
    check(confirmedCompletion.state == .waving && confirmedCompletion.observedAtMs == 15,
          "confirmation does not refresh already completed notification timestamp")
    let sameApproval = CodexLiveStatus(state: .waiting, observedAtMs: 20, confirmedAtMs: 40)
    check(applyCodexLiveStatus(sameApproval, to: done, transcriptStatus: newerCompletion).state == .waving,
          "fresh snapshot cannot resurrect an approval predating completion")
    let attentionFixture: (String, String, Double, String) -> StatePayload = { id, state, time, source in
        try! JSONDecoder().decode(StatePayload.self, from: JSONSerialization.data(withJSONObject:
            ["sessionId": id, "state": state, "updatedAtMs": time, "source": source, "attention": true]))
    }
    let olderInput = attentionFixture("input", "waiting", 1, "codex")
    let newerDone = attentionFixture("done", "waving", 100, "codex")
    let newerSlack = attentionFixture("slack", "waving", 200, "slack")
    let mixed = [newerDone, newerSlack, olderInput].sorted {
        selectionPriority(state: $0.petState, isClosed: $0.isClosed, source: $0.source)
            > selectionPriority(state: $1.petState, isClosed: $1.isClosed, source: $1.source)
    }
    let priority: (StatePayload) -> Int = { selectionPriority(state: $0.petState, isClosed: $0.isClosed, source: $0.source) }
    check(mixed.first?.id == olderInput.id, "older input precedes newer orange completion and Slack in task list")
    check(preferredPinnedSession(newerDone, attention: mixed, priority: priority, needsAttention: { $0.needsAttention }).id == olderInput.id,
          "input preempts pinned orange completion")
    check(attentionBadgeSessions(mixed, needsAttention: { $0.needsAttention }).map(\.id) == [olderInput.id],
          "input badge uses the same first-priority task as selection and list")
    let question = CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil, inputRequests: ["question:0": 2])
    check(applyCodexLiveStatus(liveRunning, to: waiting, transcriptStatus: question).state == .running,
          "fresh app state resolves an obsolete transcript question")
    let unconfirmedQuestion = CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil, inputRequests: ["new-question:0": 30])
    check(applyCodexLiveStatus(liveRunning, to: newerWaiting, transcriptStatus: unconfirmedQuestion).source == .unavailable,
          "a question newer than the app snapshot requests confirmation without guessing input state")
    check(applyCodexLiveStatus(liveWaiting, to: waiting, transcriptStatus: question).state == .waiting,
          "app-confirmed pending question remains waiting during other tool activity")
    check(applyCodexLiveStatus(liveRunning, to: done, transcriptStatus: newerCompletion).state == .running,
          "app running overrides stale rollout completion")
    store.reset()
    let approval = request("item/commandExecution/requestApproval")
    _ = store.consume(snapshot(requests: [approval]), nowMs: 2000)
    check(store.statuses["fixture"]?.state == .running,
          "automatic permission review without the app waiting flag is not user input")
    _ = store.consume(snapshot(flags: ["waitingOnApproval"], requests: [approval], revision: 2), nowMs: 2100)
    check(store.statuses["fixture"]?.state == .waiting, "app approval flag confirms a real approval wait")
    _ = store.consume(snapshot(requests: [approval], revision: 3), nowMs: 2200)
    check(store.statuses["fixture"]?.state == .running, "cleared app flag releases approval before tool completion")
    _ = store.consume(snapshot(requests: [request("item/tool/requestUserInput")], revision: 4), nowMs: 2300)
    check(store.statuses["fixture"]?.state == .waiting, "native pending user-input request is preserved without a blocking runtime flag")
    _ = store.consume(snapshot(requests: [approval], revision: 5, resume: "resumed"), nowMs: 2400)
    check(store.statuses["fixture"]?.state == .waiting, "owned conversation preserves an actual approval dialog even without a runtime flag")
    _ = store.consume(snapshot(requests: [approval], revision: 6, resume: "needs_resume"), nowMs: 2500)
    check(store.statuses["fixture"]?.state == .running, "restored historical requests do not override the app's running status")
    store.reset()
    _ = store.consume(snapshot(flags: ["waitingOnApproval"]), nowMs: 20)
    _ = store.consume(patch([["op": "add", "path": ["requests", 0], "value": request("item/tool/call")]], base: 1, revision: 2), nowMs: 40)
    check(store.statuses["fixture"]?.observedAtMs == 20,
          "ordinary tool patches cannot turn an old wait into a new input event")
    check(applyCodexLiveStatus(store.statuses["fixture"], to: done, transcriptStatus: newerCompletion).state == .waving,
          "unrelated activity cannot resurrect a wait from a completed turn")
    let activeWithToolPatch = CodexLiveStatus(state: .running, observedAtMs: 100,
        confirmedAtMs: 200, snapshotConfirmedAtMs: 100)
    check(needsCodexHookConfirmation(activeWithToolPatch, since: 150, requestedAt: 0),
          "a tool patch after a question does not replace full app confirmation")
    check(!needsCodexHookConfirmation(activeWithToolPatch, since: 150, requestedAt: 150),
          "the same hook does not continuously request confirmation")
    let largeHeader = Data(#"{"type":"broadcast","method":"thread-stream-state-changed","params":{"hostId":"local","conversationId":"large","change":{"type":"snapshot","conversationState":{"ignored":""#.utf8)
    check(oversizedCodexThreadID(in: largeHeader) == "large", "oversized frame header identifies its own thread without parsing the body")
    check(oversizedCodexThreadID(in: Data(largeHeader.prefix(40))) == nil, "fragmented oversized header waits for complete metadata")
    check(CodexLiveStatus(state: .running, observedAtMs: 1, revision: 1)
          == CodexLiveStatus(state: .running, observedAtMs: 1, revision: 2),
          "diagnostic-only revision changes do not refresh the whole overlay")
    let completed = CodexTranscriptStatus(completedAtMs: 10, latestPromptAtMs: 1)
    check(applyCodexLiveStatus(CodexLiveStatus(state: .idle, observedAtMs: 20), to: waiting, transcriptStatus: completed).state == .waving,
          "idle stream preserves confirmed completion")
    var dwell = SessionReadDwell()
    check(!dwell.observe(key: "a", nowMs: 0), "read dwell starts on first observation")
    check(!dwell.observe(key: "a", nowMs: 2999), "short view does not mark read")
    check(!dwell.observe(key: "b", nowMs: 3000), "switching conversations resets read dwell")
    check(dwell.observe(key: "b", nowMs: 6000), "same conversation held for dwell marks read")
    check(!dwell.observe(key: nil, nowMs: 6001) && !dwell.observe(key: "b", nowMs: 6002), "unreadable title resets dwell")
    check(!dwell.observe(key: "b-new-notification", nowMs: 10000), "new notification resets read dwell")
}
