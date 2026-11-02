import Foundation

func checkStatusReliability(_ check: (Bool, String) -> Void) {
    func snapshot(_ owner: String, _ revision: Int, _ state: String = "active",
                  flags: [String] = [], id: String = "fixture") -> [String: Any] {
        ["type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
         "sourceClientId": owner, "params": ["hostId": "local", "conversationId": id,
         "change": ["type": "snapshot", "revision": revision, "conversationState": ["id": id,
         "threadRuntimeStatus": ["type": state, "activeFlags": flags], "requests": []]]]]
    }
    func gap(_ owner: String, _ base: Int, _ revision: Int) -> [String: Any] {
        ["type": "broadcast", "method": "thread-stream-state-changed", "version": 11,
         "sourceClientId": owner, "params": ["hostId": "local", "conversationId": "fixture",
         "change": ["type": "patches", "baseRevision": base, "revision": revision, "patches": []]]]
    }
    let hook = ReconciledCodexTask(state: .waiting, observedAtMs: 50, needsAttention: true, title: nil, source: .hook)
    let old = CodexLiveStatus(state: .waiting, observedAtMs: 20)
    let turn = CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil, composerTurns: ["new": 40])
    check(applyCodexLiveStatus(old, to: hook, transcriptStatus: turn).source == .unavailable,
          "new composer cannot re-expose an old permission hook as current input")
    let done = CodexTranscriptStatus(completedAtMs: 40, latestPromptAtMs: 1)
    check(applyCodexLiveStatus(old, to: hook, transcriptStatus: done).state != .waiting,
          "completed turn cannot re-expose an old permission hook")

    var store = CodexLiveStatusStore()
    _ = store.consume(snapshot("A", 100), nowMs: 100)
    _ = store.consume(snapshot("B", 1, flags: ["waitingOnApproval"]), nowMs: 200)
    check(store.statuses["fixture"] == nil, "first-seen foreign owner makes old observer unconfirmed instead of promoting waiting")
    check(store.takeOwnerValidationRequests() == ["fixture"], "first owner change requires a fresh observer barrier")
    // The reader opens a new explicitly targeted observer; its state store is a new epoch.
    store.reset()
    _ = store.consume(snapshot("B", 1), nowMs: 200)
    _ = store.consume(snapshot("A", 101, flags: ["waitingOnApproval"]), nowMs: 300)
    check(store.statuses["fixture"] == nil, "late previous-owner snapshot cannot override freshly validated current owner")
    check(store.takeOwnerValidationRequests() == ["fixture"], "owner return requires fresh observer validation")
    _ = store.consume(snapshot("B", 2, flags: ["waitingOnApproval"]), nowMs: 350)
    check(store.statuses["fixture"] == nil, "once ownership is ambiguous even current-owner packets wait for a fresh epoch")
    _ = store.consume(snapshot("A", 1, flags: ["waitingOnApproval"], id: "other"), nowMs: 400)
    check(store.statuses["other"]?.state == .waiting, "ownership ambiguity is scoped to one conversation")
    store.disconnect(owner: "B")
    _ = store.consume(snapshot("B", 2, flags: ["waitingOnApproval"]), nowMs: 500)
    check(store.statuses["fixture"] == nil, "disconnected owner cannot restore waiting from a buffered snapshot")
    check(store.statuses["other"]?.state == .waiting, "unrelated owner disconnect preserves healthy waiting")

    store.reset()
    _ = store.consume(snapshot("owner", 100), nowMs: 100)
    _ = store.consume(gap("owner", 110, 111), nowMs: 200)
    check(store.statuses["fixture"] == nil, "revision gap invalidates the cached value")
    _ = store.consume(snapshot("owner", 99, flags: ["waitingOnApproval"]), nowMs: 300)
    check(store.statuses["fixture"] == nil, "old snapshot cannot recreate waiting after gap removed the cache")
    _ = store.consume(snapshot("owner", 110, flags: ["waitingOnApproval"]), nowMs: 400)
    check(store.statuses["fixture"] == nil, "gap revision floor includes the dropped patch itself")
    _ = store.consume(snapshot("owner", 111), nowMs: 500)
    check(store.statuses["fixture"]?.state == .running, "current full snapshot repairs the gap")
    store.invalidate("fixture")
    _ = store.consume(snapshot("owner", 100, flags: ["waitingOnApproval"]), nowMs: 600)
    check(store.statuses["fixture"] == nil, "timeout invalidation retains the revision fence")
    store.retain([])
    _ = store.consume(snapshot("owner", 1), nowMs: 700)
    check(store.statuses["fixture"]?.state == .running, "untracked task metadata is removed before a later new subscription")

    store.reset()
    _ = store.consume(snapshot("owner", 1, "idle", flags: ["waitingOnApproval"]), nowMs: 100)
    check(store.statuses["fixture"]?.state == .idle, "idle runtime does not use active-only waiting flags")
    _ = store.consume(snapshot("owner", 2, "systemError", flags: ["waitingOnUserInput"]), nowMs: 200)
    check(store.statuses["fixture"]?.state == .failed, "error runtime does not become input waiting from stale active flags")

    store.reset()
    _ = store.consume(snapshot("owner", 100), nowMs: 100)
    store.invalidateOversized("fixture", owner: "owner", revision: 101)
    _ = store.consume(snapshot("owner", 100, flags: ["waitingOnApproval"]), nowMs: 200)
    check(store.statuses["fixture"] == nil, "oversized invalidation retains the oversized revision, not only the old cached one")
    _ = store.consume(snapshot("owner", 101), nowMs: 300)
    check(store.statuses["fixture"]?.state == .running, "current bounded snapshot can recover after oversized invalidation")
    var malformed = snapshot("owner", 102)
    var params = malformed["params"] as! [String: Any]
    var change = params["change"] as! [String: Any]
    var fields = change["conversationState"] as! [String: Any]
    fields["requests"] = [["method": "item/tool/requestUserInput", "completed": "true"]]
    change["conversationState"] = fields; params["change"] = change; malformed["params"] = params
    _ = store.consume(malformed, nowMs: 400)
    check(store.statuses["fixture"] == nil, "malformed completed string cannot manufacture waiting")
    _ = store.consume(snapshot("owner", 101, flags: ["waitingOnApproval"]), nowMs: 500)
    check(store.statuses["fixture"] == nil, "malformed known fields retain a revision fence")
    fields["requests"] = []
    fields["threadRuntimeStatus"] = ["type": "active", "activeFlags": "waitingOnApproval"]
    change["conversationState"] = fields; change["revision"] = 103
    params["change"] = change; malformed["params"] = params
    _ = store.consume(malformed, nowMs: 600)
    check(store.statuses["fixture"] == nil, "malformed activeFlags string is unconfirmed")
    _ = store.consume(snapshot("owner", 104), nowMs: 700)
    var unrelated = snapshot("owner", 105); unrelated["method"] = "unrelated-event"
    _ = store.consume(unrelated, nowMs: 800)
    check(store.acceptedSnapshotID == nil && store.statuses["fixture"]?.state == .running,
          "unrelated events do not count as a fresh confirmation")

    var seed: UInt64 = 0xA11CE5EED
    func random() -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 32) & 0xffff)
    }
    var staleRevived = false, ownerReplaced = false, crossTaskLost = false
    for _ in 0..<1000 {
        var epoch = CodexLiveStatusStore()
        let initial = 10 + random(), floor = initial + 2 + random() % 20
        _ = epoch.consume(snapshot("A", initial), nowMs: 1)
        _ = epoch.consume(snapshot("shared", 1, flags: ["waitingOnApproval"], id: "healthy"), nowMs: 2)
        _ = epoch.consume(gap("A", floor - 1, floor), nowMs: 3)
        _ = epoch.consume(snapshot("A", floor - 1, flags: ["waitingOnApproval"]), nowMs: 4)
        staleRevived = staleRevived || epoch.statuses["fixture"] != nil
        _ = epoch.consume(snapshot("A", floor), nowMs: 5)
        _ = epoch.consume(snapshot("B", 1, flags: ["waitingOnApproval"]), nowMs: 6)
        ownerReplaced = ownerReplaced || epoch.statuses["fixture"] != nil
        _ = epoch.consume(snapshot("A", floor + 1, flags: ["waitingOnApproval"]), nowMs: 7)
        ownerReplaced = ownerReplaced || epoch.statuses["fixture"] != nil
        epoch.disconnect(owner: "A")
        _ = epoch.consume(snapshot("A", floor + 2, flags: ["waitingOnApproval"]), nowMs: 8)
        staleRevived = staleRevived || epoch.statuses["fixture"] != nil
        crossTaskLost = crossTaskLost || epoch.statuses["healthy"]?.state != .waiting
    }
    check(!staleRevived, "1,000 deterministic fault traces never revive discarded waiting")
    check(!ownerReplaced, "1,000 deterministic fault traces preserve the current owner")
    check(!crossTaskLost, "1,000 deterministic fault traces preserve an unrelated healthy task")

    var history = CodexObserverHistory(limit: 4)
    check(history.acceptMain("main-0") && history.recordChild("child-0") && history.recordChild("child-1")
          && history.needsRollover(), "observer budget requests rollover before exhausting its bounded history")
    history.beginRollover()
    check(!history.acceptMain("child-1") && history.rolling && history.ids.count == 3,
          "rollover retains prior IDs and rejects a reused main observer before clearing history")
    check(history.acceptMain("main-1") && !history.rolling && history.ids == ["main-1"],
          "a genuinely new main observer starts a bounded fresh epoch")
    var rolloverRecovered = true
    for epoch in 2...100 {
        rolloverRecovered = rolloverRecovered && history.recordChild("child-\(epoch)-a")
            && history.recordChild("child-\(epoch)-b") && history.needsRollover()
        history.beginRollover()
        rolloverRecovered = rolloverRecovered && history.acceptMain("main-\(epoch)") && history.ids.count == 1
    }
    check(rolloverRecovered, "100 bounded observer epochs retain recovery capacity without exhausting fresh-ID admission")

    let mixedSlots = [CodexDedicatedSlot(id: "active", state: .waiting, servedAt: 1),
                      CodexDedicatedSlot(id: "history", state: .idle, servedAt: 99)]
    let idlePlan = codexDedicatedSlotPlan(mixedSlots, now: 100, lease: 30)
    check(idlePlan?.id == "history" && idlePlan?.eligibleAt == 100 && idlePlan?.parkAfterEviction == true,
          "idle dedicated history immediately yields capacity to an active recovery")
    let activeSlots = [CodexDedicatedSlot(id: "new", state: .running, servedAt: 90),
                       CodexDedicatedSlot(id: "old", state: .waiting, servedAt: 80)]
    let activePlan = codexDedicatedSlotPlan(activeSlots, now: 100, lease: 30)
    check(activePlan?.id == "old" && activePlan?.eligibleAt == 110 && activePlan?.parkAfterEviction == false,
          "saturated active readers yield by oldest lease and remain eligible for FIFO recovery")
    let unknownPlan = codexDedicatedSlotPlan([CodexDedicatedSlot(id: "unknown", state: nil, servedAt: 100)],
                                            now: 101, lease: 30)
    check(unknownPlan?.eligibleAt == 101 && unknownPlan?.parkAfterEviction == true,
          "conclusive unknown history cannot permanently reserve a dedicated reader")
    check(codexDedicatedSlotPlan([], now: 100, lease: 30) == nil,
          "unconfirmed in-flight readers are never manufactured as eviction candidates")

    // A new observer epoch may legitimately return ownership to A; the reader enforces targeting.
    store.reset()
    _ = store.consume(snapshot("A", 1, flags: ["waitingOnApproval"]), nowMs: 1000)
    check(store.statuses["fixture"]?.state == .waiting, "a fresh observer epoch can legitimately receive returning owner A")
}
