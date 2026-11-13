// 빌드마다 도는 자체 검사와 배율별 미리보기.

import AppKit
import CoreText
import Foundation
import SQLite3

/// 흰 배경에서 머리 위에 회색 안개가 없는지 잰다.
///
/// 예전에는 실루엣 드롭 섀도(blur 16)를 써서 흐림이 사방으로 퍼졌다. 어두운 배경에서는
/// 안 보였지만 흰 배경에서는 머리 위가 투명한 사각형처럼 도드라졌다. 다시 들어오면 여기서 걸린다.
/// 돌려주는 값은 (머리 위 회색 줄 수, 가장 진한 정도 0~255). 창 전체 후광 픽셀 수는
/// haloFaintPixels 에 담는다 — 어두운 배경에서는 안 보이니 숫자로만 지켜본다.
var haloFaintPixels = 0

func headroomHalo(spriteSheet: NSImage) -> (rows: Int, deepest: Int) {
    let layout = petLayout(scale: 1)
    let size = layout.windowSize
    let width = Int(size.width.rounded()), height = Int(size.height.rounded())
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return (0, 0) }

    let view = RettoView(frame: NSRect(origin: .zero, size: size), spriteSheet: spriteSheet, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
    view.petScale = 1
    let fixture = "{\"state\":\"idle\",\"sessionId\":\"halo\",\"projectName\":\"p\",\"lastAssistantMessage\":\"ㄱ\"}".data(using: .utf8)!
    guard let payload = try? JSONDecoder().decode(StatePayload.self, from: fixture) else { return (0, 0) }
    view.apply(payload, sessionCount: 1, attentionCount: 0, isPinned: false)
    view.settleAnimations()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()

    // 창 전체에서 옅고 넓은 회색이 얼마나 깔리는지. 후광은 몸 옆·어깨 위로 가장 넓게 퍼진다.
    var faint = 0
    for y in 0..<height {
        for x in 0..<width {
            guard let color = rep.colorAt(x: x, y: y) else { continue }
            let d = Int((1 - color.redComponent) * 255)
            if d >= 4 && d < 40 { faint += 1 }
        }
    }
    haloFaintPixels = faint

    // 머리 위쪽만 본다. 좌우 20% 는 배지 자리라 뺀다.
    let xLow = Int(size.width * 0.3), xHigh = Int(size.width * 0.7)
    var rows = 0, deepest = 0
    var bodyFound = false
    // rep 의 y=0 은 위쪽이다. 위에서 아래로 훑어 몸통 윤곽이 나오기 전까지가 머리 위다.
    for y in 0..<height {
        var wide = 0, darkest = 0
        for x in xLow...xHigh {
            guard let color = rep.colorAt(x: x, y: y) else { continue }
            let d = Int((1 - color.redComponent) * 255)
            if d >= 4 { wide += 1 }
            darkest = max(darkest, d)
        }
        if ProcessInfo.processInfo.environment["RETO_HALO_DEBUG"] != nil, y < 40 {
            fputs("  y=\(y) 폭\(wide) 진하기\(darkest)\n", stderr)
        }
        if darkest >= 60 { bodyFound = true; break }
        // 귀 끝 안티에일리어싱은 좁고 금방 진해진다. 후광은 옅으면서 넓다.
        if wide >= 35 && darkest <= 40 { rows += 1; deepest = max(deepest, darkest) }
    }
    return bodyFound ? (rows, deepest) : (rows, deepest)
}

/// 그 상태에서 창에 어떤 단추가 나오는지. 그림으로는 라벨이 잡히지 않아 이걸로 본다.
private func setupButtons(for status: ClaudeIntegrationStatus) -> [String] {
    let window = SetupWindow(firstRun: true, onReinstall: {})
    window.refresh(status: status, environment: RettoHostEnvironment())
    return window.visibleButtonTitles
}

/// 일반 파일명으로 저장된 내부 검토도 제외하고, 같은 제목의 사용자 대화는 유지한다.
func codexInternalSessionFilterSelfTest() -> Bool {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("retto-codex-filter-\(UUID().uuidString)")
    do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    catch { return false }
    defer { try? FileManager.default.removeItem(at: directory) }

    func fixture(_ name: String, source: Any) -> String? {
        let url = directory.appendingPathComponent("rollout-\(name).jsonl")
        let record: [String: Any] = ["type": "session_meta", "payload": [
            "id": name, "source": source, "base_instructions": String(repeating: "가", count: 60000)
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              (try? (data + Data("\n".utf8)).write(to: url)) != nil else { return nil }
        return url.path
    }
    func visible(_ path: String, source: String = "codex") -> Bool {
        let record: [String: Any] = ["state": "waving", "source": source,
            "sessionTitle": "Guardian review", "transcriptPath": path, "attention": true]
        guard let data = try? JSONSerialization.data(withJSONObject: record),
              let payload = try? JSONDecoder().decode(StatePayload.self, from: data) else { return false }
        return payload.isRettoVisibleTask
    }

    guard let guardian = fixture("guardian", source: ["subagent": ["other": "guardian"]]),
          let worker = fixture("worker", source: ["subagent": ["thread_spawn": ["parent_thread_id": "parent"]]]),
          let legacy = fixture("legacy", source: "subagent"),
          let user = fixture("user", source: "vscode") else { return false }
    return isCodexSubagentTranscript(path: guardian)
        && isCodexSubagentTranscript(path: worker)
        && isCodexSubagentTranscript(path: legacy)
        && !isCodexSubagentTranscript(path: user)
        && !isCodexSubagentTranscript(path: directory.appendingPathComponent("missing.jsonl").path)
        && !visible(guardian) && !visible(worker) && !visible(legacy)
        && visible(user) && visible(guardian, source: "claude")
}

func runSelfTest() -> Int32 {
    let fontOK = registerRettoFont()
    guard let imageURL = Bundle.main.url(forResource: "spritesheet", withExtension: "webp"),
          let image = NSImage(contentsOf: imageURL) else {
        fputs("{\"ok\":false,\"error\":\"missing spritesheet\"}\n", stderr)
        return 1
    }
    let assetOK = SpriteSheetLayout.forImage(size: image.size) == .retto
    // 기본 스킨은 레토 규격이고, 개인 스킨은 Codex v2 규격도 쓸 수 있다.
    // 번들에 없는 스킨은 앱이 기본으로 물러나므로 통과로 본다.
    let sixFrameThinkingTimingOK = [PetSkin.classic, .angelWings, .bee, .bunny, .rilakkuma, .rilakkumaCape].allSatisfy { skin in
        (Array(animationCatalog.values) + Array(dragRunAnimations.values)).allSatisfy { original in
            [8, 16].allSatisfy { columns in
                let playback = skinAnimation(original, skin: skin, columns: columns)
                return playback.frames == (columns == 8 && original.row == 7 ? 6 : original.frames)
                    && playback.interval == original.interval && playback.row == original.row
                    && playback.cycleLimit == original.cycleLimit
            }
        }
    }
    let skinsOK = PetSkin.selectableCases.count == PetSkin.allCases.count
        && Set(PetSkin.selectableCases) == Set(PetSkin.allCases)
        && PetSkin.selection(rawValue: "magicalHeart") == .classic
        && PetSkin.selection(rawValue: nil) == .classic
        && PetSkin.selection(rawValue: "unknown") == .classic
        && PetSkin.selectableCases.allSatisfy { PetSkin.selection(rawValue: $0.rawValue) == $0 }
        && PetSkin.selectableCases.allSatisfy { skin in
        skin.isAvailable
    }
    let christmasTimingOK = (Array(animationCatalog.values) + Array(dragRunAnimations.values)).allSatisfy { original in
        let extended = skinAnimation(original, skin: .christmas, columns: 16)
        let legacy = skinAnimation(original, skin: .christmas, columns: 8)
        let other = skinAnimation(original, skin: .classic, columns: 16)
        return extended.frames == 16
            && Christmas16Timing.duration(row: original.row) != nil
            && abs(extended.interval * 16 - (Christmas16Timing.duration(row: original.row) ?? 0)) < 0.000001
            && extended.interval >= 0.04
            && Christmas16Timing.frameDurations(row: original.row)?.count == 16
            && abs((Christmas16Timing.frameDurations(row: original.row) ?? []).reduce(0, +) - extended.interval * 16) < 0.000001
            && (Christmas16Timing.frameDurations(row: original.row) ?? []).allSatisfy { $0 >= 0.04 }
            && abs(legacy.interval - original.interval) < 0.000001
            && abs(other.interval - original.interval) < 0.000001
            && extended.cycleLimit == original.cycleLimit
            && legacy.frames == original.frames && other.frames == original.frames
    }
    let christmasOK = christmasTimingOK && christmasEffectsSelfTest()
    let personalV2LayoutOK = SpriteSheetLayout.forImage(size: NSSize(width: 1536, height: 2288)) == .codexV2
        && SpriteSheetLayout.codexV2.rows == 11
    // 자는 행이 실제로 아틀라스에 있는지. 행을 새로 붙였는데 sheetHeight 를 안 고치면
    // 엉뚱한 자리를 그린다.
    let sleepRow = animationCatalog[.sleeping]?.row ?? -1
    let sleepRowOK = sleepRow >= 0 && CGFloat(sleepRow + 1) * cellHeight <= sheetHeight
    // 끌 때 쓰는 달리기 두 행. 아틀라스 안에 있고 칸 수가 한 행을 넘지 않아야 한다.
    let dragRunOK = Set(dragRunAnimations.keys) == Set<DragRun>([.right, .left])
        && dragRunAnimations.values.allSatisfy { run in
            run.row >= 0 && CGFloat(run.row + 1) * cellHeight <= sheetHeight
                && run.frames > 0 && CGFloat(run.frames) * cellWidth <= sheetWidth
        }
    let behaviorsOK = allSpacesBehavior.contains(.canJoinAllSpaces)
        && allSpacesBehavior.contains(.fullScreenAuxiliary)
        && allSpacesBehavior.contains(.stationary)
    let statesOK = Set(animationCatalog.keys) == Set(PetState.allCases)
    // VS Code 딥링크는 확장 규격 그대로여야 한다. 한 글자만 틀려도 클릭이 조용히 아무 일도 안 한다.
    // Claude 앱에는 세션을 집어 띄우는 길이 없으므로 링크를 만들지 않는다 —
    // 예전에 쓰던 `claude://resume` 은 세션을 앱으로 가져오는 길이라 누를 때마다 새 창이 떴다.
    let deepLinkOK = sessionDeepLink(sessionId: "session-test", app: .vscode)?.absoluteString == "vscode://anthropic.claude-code/open?session=session-test"
        && sessionDeepLink(sessionId: "session-test", app: .claude) == nil
        && sessionDeepLink(sessionId: "thread-test", app: .codex)?.absoluteString == "codex://threads/thread-test"
        && OpenApp.vscode.hasSessionDeepLink
        && !OpenApp.claude.hasSessionDeepLink
        && OpenApp.codex.hasSessionDeepLink
    // 훅이 적어 둔 클라이언트가 앱으로 옳게 풀리는지. 모르는 값은 예전 동작인 VS Code 로 남아야 한다.
    // 말풍선 본문은 두 클라이언트의 트랜스크립트에서 온다. Codex 롤아웃은 한 겹 더 싸여 있고
    // 글 조각 이름도 `output_text` 라, 한쪽 모양만 읽으면 그 클라이언트 말풍선이 빈 채로 남는다.
    let claudeRecord: [String: Any] = ["type": "assistant", "message": ["content": [["type": "text", "text": "클로드가 하는 말"]]]]
    let codexRecord: [String: Any] = ["type": "response_item", "payload": ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "코덱스가 하는 말"]]]]
    let userRecord: [String: Any] = ["type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "사람이 한 말"]]]]
    let transcriptShapesOK = assistantText(in: claudeRecord) == "클로드가 하는 말"
        && assistantText(in: codexRecord) == "코덱스가 하는 말"
        && assistantText(in: userRecord).isEmpty
    let codexTitles = codexThreadTitles(in: [
        "{\"id\":\"thread-one\",\"thread_name\":\"처음 이름\"}",
        "{\"id\":\"thread-two\",\"thread_name\":\"다른 작업\"}",
        "{\"id\":\"thread-one\",\"thread_name\":\"완료된 작업의 최신 이름\"}"
    ].joined(separator: "\n"))
    let codexTitleRefreshOK = codexTitles["thread-one"] == "완료된 작업의 최신 이름"
        && codexTitles["thread-two"] == "다른 작업"
    let codexCompletionRefreshOK = codexTaskCompletionAtMs(in: [
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\"},\"timestamp\":\"2026-09-02T05:32:00.000Z\"}",
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"},\"timestamp\":\"2026-09-02T05:32:30.178Z\"}"
    ].joined(separator: "\n")) == 1_788_327_150_178
        && codexTaskCompletionAtMs(in: "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"},\"timestamp\":\"2026-09-02T05:32:30Z\"}") == 1_788_327_150_000
    let completedTranscriptStatus = codexTranscriptStatus(in: [
        "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\"},\"timestamp\":\"2026-09-02T05:31:00Z\"}",
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"},\"timestamp\":\"2026-09-02T05:32:30Z\"}"
    ].joined(separator: "\n"))
    let restartedTranscriptStatus = codexTranscriptStatus(in: [
        "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\"},\"timestamp\":\"2026-09-02T05:32:30Z\"}",
        "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"role\":\"user\"},\"timestamp\":\"2026-09-02T05:33:00Z\"}"
    ].joined(separator: "\n"))
    let codexTranscriptOrderingOK = completedTranscriptStatus.isCompletedAfterLatestPrompt
        && !restartedTranscriptStatus.isCompletedAfterLatestPrompt
    let discoveredCodexTask = StatePayload(
        state: PetState.waving.rawValue, updatedAt: nil, event: "task_complete",
        sessionId: "codex:thread-one", rawSessionId: "thread-one", source: "codex", cwd: "/tmp/project",
        toolName: nil, notificationType: nil, error: nil, projectName: nil, displayTitle: nil,
        sessionTitle: "훅 없이 찾은 task", transcriptPath: "/tmp/rollout.jsonl", lastAssistantMessage: nil,
        activeTaskSubject: nil, backgroundTaskCount: nil, attention: true, closed: false,
        updatedAtMs: 2000, stateSource: "rollout", client: "codex"
    )
    let rolloutDiscoveryPayloadOK = codexInternalSessionFilterSelfTest()
        && discoveredCodexTask.sourceLabel == "Codex"
        && discoveredCodexTask.navigationSessionId == "thread-one"
        && discoveredCodexTask.needsAttention
        && sessionMenuLabel(for: discoveredCodexTask) == "● 완료  훅 없이 찾은 task · project · Codex"
        && discoveredCodexTask.isRettoVisibleTask
        && isCodexSubagentTranscript(path: "/tmp/rollout-parent_12345678-1234-1234-1234-123456789abc.jsonl")
        && !isCodexSubagentTranscript(path: "/tmp/rollout-parent.jsonl")
        && !(StatePayload(
            state: PetState.running.rawValue, updatedAt: nil, event: nil,
            sessionId: "codex:unnamed", rawSessionId: "unnamed", source: "codex", cwd: nil,
            toolName: nil, notificationType: nil, error: nil, projectName: nil, displayTitle: "첫 요청",
            sessionTitle: nil, transcriptPath: "/tmp/rollout.jsonl", lastAssistantMessage: nil,
            activeTaskSubject: nil, backgroundTaskCount: nil, attention: nil, closed: false,
            updatedAtMs: nil, stateSource: nil, client: "codex"
        ).isRettoVisibleTask)
        && !StatePayload(
            state: PetState.running.rawValue, updatedAt: nil, event: nil,
            sessionId: "codex:previously-recorded", rawSessionId: "previously-recorded", source: "codex", cwd: nil,
            toolName: nil, notificationType: nil, error: nil, projectName: nil, displayTitle: nil,
            sessionTitle: "상위 작업", transcriptPath: "/tmp/rollout-parent_12345678-1234-1234-1234-123456789abc.jsonl", lastAssistantMessage: nil,
            activeTaskSubject: nil, backgroundTaskCount: nil, attention: nil, closed: false,
            updatedAtMs: nil, stateSource: nil, client: "codex"
        ).isRettoVisibleTask
    let unnamedPayload = StatePayload(
        state: PetState.running.rawValue, updatedAt: nil, event: nil,
        sessionId: "unnamed", rawSessionId: nil, source: "claude", cwd: "/tmp/project",
        toolName: nil, notificationType: nil, error: nil, projectName: nil,
        displayTitle: "사용자가 입력한 프롬프트", sessionTitle: nil, transcriptPath: nil,
        lastAssistantMessage: nil, activeTaskSubject: "진행 중 작업", backgroundTaskCount: nil,
        attention: nil, closed: false, updatedAtMs: nil, stateSource: nil, client: "cli"
    )
    // ⚠️ 병합 판단(2026-09-06). 260902 는 "세션명이 아니면 무조건 No name" 이었고
    // 260906 은 "작업 주제 → 세션을 연 첫 요청 → No name" 이다. 뒤엣것을 남겼다 —
    // 훅이 답을 이름으로 쓰지 않게 고쳐서 대타가 이제 믿을 만하고, 이름 없는 세션이
    // 여럿이면 목록에서 구분이 안 되기 때문이다. 되돌리려면 Sessions.swift 의 title 을 줄인다.
    let unnamedTitleOK = unnamedPayload.title == "진행 중 작업"
    // Orca 에서 띄운 세션. 누르면 Orca 의 그 탭으로 가야 하고, 다른 앱으로 떨어지면 안 된다.
    // Claude 채팅은 훅이 Orca 세션 ID 를 적고, Codex 채팅은 훅이 꺼져 있어 롤아웃 originator 로 알아본다.
    let orcaChat = try! JSONDecoder().decode(StatePayload.self, from: """
        {"state":"waving","sessionId":"s-orca","source":"claude","client":"orca","orcaSessionId":"claude_abc","cwd":"/tmp/ws","sessionTitle":"Orca 작업"}
        """.data(using: .utf8)!)
    let orcaTerminal = try! JSONDecoder().decode(StatePayload.self, from: """
        {"state":"running","sessionId":"s-term","source":"claude","client":"cli","orcaTerminalHandle":"term_abc","cwd":"/tmp/ws","sessionTitle":"터미널 작업"}
        """.data(using: .utf8)!)
    let plainCode = try! JSONDecoder().decode(StatePayload.self, from: """
        {"state":"running","sessionId":"s-code","source":"claude","client":"vscode","cwd":"/tmp/ws","sessionTitle":"코드 작업"}
        """.data(using: .utf8)!)
    var orcaCodex = discoveredCodexTask
    orcaCodex.orcaHosted = true
    let orcaOK = openApp(forClient: "orca") == .orca
        && sessionDeepLink(sessionId: "claude_abc", app: .orca) == nil
        && !OpenApp.orca.hasSessionDeepLink && !OpenApp.orca.needsWindowFocusFirst
        && installedOpenApp(preferred: .orca) { $0 != .orca } == .orca
        && codexSessionMetaIsFromOrca("{\"type\":\"session_meta\",\"payload\":{\"id\":\"t\",\"originator\":\"orca_desktop\"}}")
        && !codexSessionMetaIsFromOrca("{\"type\":\"session_meta\",\"payload\":{\"id\":\"t\",\"originator\":\"Codex Desktop\"}}")
        && !codexSessionMetaIsFromOrca("{\"type\":\"session_meta\",\"payload\":")
        && orcaChat.isOrca && orcaTerminal.isOrca && orcaCodex.isOrca && !plainCode.isOrca && !discoveredCodexTask.isOrca
        && sessionMenuLabel(for: orcaChat) == "● 완료  Orca 작업 · ws · Orca"
        && sessionMenuLabel(for: orcaCodex) == "● 완료  훅 없이 찾은 task · project · Orca"
        && sessionMenuLabel(for: plainCode) == "● 작업 중  코드 작업 · ws · VS Code"
        && orcaOpenRequest(for: orcaChat) == OrcaOpenRequest(sessionId: "claude_abc", terminalHandle: nil, workspacePath: "/tmp/ws", agent: "claude")
        && orcaOpenRequest(for: orcaTerminal) == OrcaOpenRequest(sessionId: nil, terminalHandle: "term_abc", workspacePath: "/tmp/ws", agent: "claude")
        && orcaOpenRequest(for: orcaCodex) == OrcaOpenRequest(sessionId: nil, terminalHandle: nil, workspacePath: "/tmp/project", agent: "codex", codexThreadId: "thread-one")
        && orcaOpenRequest(for: plainCode) == nil
        && NewsChannel.of(client: "orca", source: nil) == .orca
        && orcaRevealOutcome("{\"opened\":\"chat\"}\n") == .chat
        && orcaRevealOutcome("{\"opened\":\"workspace\"}") == .workspace
        && orcaRevealOutcome("{\"opened\":\"none\"}") == nil
        && orcaRevealOutcome("") == nil
    // Orca 의 Codex 채팅은 훅이 꺼져 있다. Orca 가 탭에 붙인 상태가 `blocked`·`waiting` 이면 입력 대기다.
    // 스레드를 이을 수 없거나 두 탭이 한 스레드를 가리키면 추측하지 않고 버린다.
    let orcaStatuses = orcaChatStatuses(fromOutput: """
        {"chats":[{"sessionId":"codex_a","threadId":"thread-a","state":"blocked","since":5000},
        {"sessionId":"codex_b","threadId":"thread-b","state":"working","since":4000},
        {"sessionId":"codex_c","threadId":null,"state":"blocked","since":4000},
        {"sessionId":"codex_d","threadId":"thread-d","state":"waiting","since":4000},
        {"sessionId":"codex_e","threadId":"thread-d","state":"done","since":4000},
        {"sessionId":"bad id","threadId":"thread-f","state":"blocked","since":4000}]}
        """.replacingOccurrences(of: "\n", with: ""))
    var orcaRunning = orcaCodex
    orcaRunning.state = "running"
    orcaRunning.updatedAtMs = 3000
    var orcaFinished = orcaCodex
    orcaFinished.state = "waving"
    orcaFinished.updatedAtMs = 6000
    let blockedChat = orcaStatuses?["thread-a"]
    let orcaRecord = "{\"conversationName\":\" Orca 제목 \",\"providerHandleChain\":[{\"handle\":{\"provider\":\"codex\",\"threadId\":\"thread-old\"}},{\"handle\":{\"provider\":\"codex\",\"threadId\":\"thread-t\"}}]}"
    var untitledOrcaRollout = discoveredCodexTask
    untitledOrcaRollout.sessionTitle = nil
    // 실제 SQLite 파일로 읽는다. 한 스레드를 두 채팅이 가리키면 탭 ID 는 비운다.
    let orcaIndexURL = FileManager.default.temporaryDirectory.appendingPathComponent("retto-orca-index-\(UUID().uuidString).db")
    do {
        var db: OpaquePointer?
        sqlite3_open(orcaIndexURL.path, &db)
        let dup = "{\"conversationName\":\"둘\",\"providerHandleChain\":[{\"handle\":{\"provider\":\"codex\",\"threadId\":\"thread-dup\"}}]}"
        sqlite3_exec(db, "CREATE TABLE agent_session_records (session_id TEXT PRIMARY KEY, record_json TEXT NOT NULL);"
            + "INSERT INTO agent_session_records VALUES ('codex_t', '\(orcaRecord)'), ('codex_d1', '\(dup)'), ('codex_d2', '\(dup)'),"
            + "('claude_x', '\(orcaRecord)'), ('codex_bad', '{');", nil, nil, nil)
        sqlite3_close(db)
    }
    let orcaIndex = OrcaCodexThreadIndex(url: orcaIndexURL)
    orcaIndex.refresh(now: 100)
    let orcaIndexThreads = orcaIndex.threads
    try? FileManager.default.removeItem(at: orcaIndexURL)
    let orcaFailedChat = orcaChatStatuses(fromOutput: "{\"chats\":[{\"sessionId\":\"codex_f\",\"threadId\":\"thread-f\",\"state\":\"done\",\"outcome\":\"failure\",\"since\":5500}]}")?["thread-f"]
    let orcaCancelledChat = orcaChatStatuses(fromOutput: "{\"chats\":[{\"sessionId\":\"codex_c\",\"threadId\":\"thread-c\",\"state\":\"done\",\"outcome\":\"cancellation\",\"since\":6500}]}")?["thread-c"]
    var orcaRunningAfterFailure = orcaRunning
    orcaRunningAfterFailure.updatedAtMs = 7000
    let orcaWaiting = applyOrcaChatStatus(blockedChat, to: orcaRunning)
    let orcaChatStatusOK = orcaStatuses?.keys.sorted() == ["thread-a", "thread-b"]
        && blockedChat == OrcaChatStatus(orcaSessionId: "codex_a", threadId: "thread-a", needsInput: true, sinceMs: 5000)
        && orcaStatuses?["thread-b"]?.needsInput == false
        && orcaChatStatuses(fromOutput: "{\"error\":\"session.tabs.listAll\"}") == nil
        && orcaChatStatuses(fromOutput: "") == nil
        && orcaWaiting.petState == .waiting && orcaWaiting.needsAttention && orcaWaiting.updatedAtMs == 5000
        && orcaWaiting.stateSource == "orca" && orcaWaiting.orcaSessionId == "codex_a"
        && orcaOpenRequest(for: orcaWaiting)?.sessionId == "codex_a"
        // 대기가 아니면 롤아웃 상태를 그대로 두고, 탭 ID 만 채운다.
        && applyOrcaChatStatus(orcaStatuses?["thread-b"], to: orcaRunning).petState == .running
        && applyOrcaChatStatus(orcaStatuses?["thread-b"], to: orcaRunning).orcaSessionId == "codex_b"
        // 내 답을 기다리며 끝난 턴도 `blocked` 다. 롤아웃 완료가 더 새로워도 대기로 둔다.
        && applyOrcaChatStatus(blockedChat, to: orcaFinished).petState == .waiting
        // 조회가 실패해 회색으로 내려가도 묻기를 멈추지 않도록 원래 상태와 마지막 활동으로 고른다.
        && orcaChatNeedsWatching(state: .running, lastActivityMs: 0.5, nowMs: 0.5 + 30 * 60 * 1000)
        && !orcaChatNeedsWatching(state: .running, lastActivityMs: 1, nowMs: 1 + 3 * 60 * 60 * 1000)
        && orcaChatNeedsWatching(state: .waving, lastActivityMs: 1, nowMs: 1 + 5 * 60 * 1000)
        && !orcaChatNeedsWatching(state: .waving, lastActivityMs: 1, nowMs: 1 + 20 * 60 * 1000)
        && !orcaChatNeedsWatching(state: .idle, lastActivityMs: 1, nowMs: 2)
        && !orcaChatNeedsWatching(state: .running, lastActivityMs: nil, nowMs: 2)
        && applyOrcaChatStatus(nil, to: orcaRunning) == orcaRunning
        // 실패는 `done` + `outcome: failure`. 롤아웃에는 실패 표시가 없어 완료로 보이던 것을 실패로 바꾼다.
        && orcaFailedChat?.failed == true && orcaFailedChat?.needsInput == false
        && orcaChatStatuses(fromOutput: "{\"chats\":[{\"sessionId\":\"codex_g\",\"threadId\":\"thread-g\",\"state\":\"done\",\"outcome\":\"cancellation\",\"since\":1}]}")?["thread-g"]?.failed == false
        && applyOrcaChatStatus(orcaFailedChat, to: orcaFinished).petState == .failed
        && applyOrcaChatStatus(orcaFailedChat, to: orcaFinished).needsAttention
        // 실패 뒤 새 턴이 시작됐으면 지난 실패를 띄우지 않는다.
        && applyOrcaChatStatus(orcaFailedChat, to: orcaRunningAfterFailure, turnStartedAtMs: 7000).petState == .running
        // 롤아웃 파일 시각이 실패 뒤라도 새 요청이 없으면 실패다(실패 기록을 쓰는 순간 파일 시각이 바뀐다).
        && applyOrcaChatStatus(orcaFailedChat, to: orcaRunningAfterFailure, turnStartedAtMs: 5000).petState == .failed
        // 멈춘 턴은 롤아웃에 완료가 없어 작업 중으로 보인다. Orca 의 cancellation 으로 쉬는 중이 된다.
        && orcaCancelledChat?.cancelled == true && orcaCancelledChat?.failed == false
        && applyOrcaChatStatus(orcaCancelledChat, to: orcaRunningAfterFailure, turnStartedAtMs: 5000).petState == .idle
        && !applyOrcaChatStatus(orcaCancelledChat, to: orcaRunningAfterFailure, turnStartedAtMs: 5000).needsAttention
        && applyOrcaChatStatus(orcaCancelledChat, to: orcaRunningAfterFailure, turnStartedAtMs: 7000).petState == .running
        && applyOrcaChatStatus(orcaCancelledChat, to: orcaFinished).petState == .waving
        // Orca 의 Codex 채팅은 Codex 쪽 제목이 없어 숨겨졌다. Orca 기록의 제목과 탭 ID 를 붙여 보인다.
        && orcaCodexThread(fromRecord: orcaRecord, sessionId: "codex_t")?.threadId == "thread-t"
        && orcaCodexThread(fromRecord: orcaRecord, sessionId: "codex_t")?.thread == OrcaCodexThread(orcaSessionId: "codex_t", title: "Orca 제목")
        && orcaCodexThread(fromRecord: "{\"providerHandleChain\":[]}", sessionId: "codex_u") == nil
        && orcaCodexThread(fromRecord: "{", sessionId: "codex_u") == nil
        // 제목은 Codex 색인이 먼저고, 비었을 때만 Orca 제목을 쓴다.
        && codexDiscoveryTitles(index: ["a": "색인", "b": ""], extra: ["a": "Orca", "b": "Orca 비", "c": "Orca 만"])
            == ["a": "색인", "b": "Orca 비", "c": "Orca 만"]
        && linkOrcaCodexTask(untitledOrcaRollout, thread: OrcaCodexThread(orcaSessionId: "codex_t", title: "Orca 제목")).orcaHosted == true
        && orcaOpenRequest(for: linkOrcaCodexTask(untitledOrcaRollout, thread: OrcaCodexThread(orcaSessionId: "codex_t", title: "Orca 제목")))?.sessionId == "codex_t"
        && linkOrcaCodexTask(untitledOrcaRollout, thread: OrcaCodexThread(orcaSessionId: "", title: "둘")).orcaSessionId == nil
        && linkOrcaCodexTask(untitledOrcaRollout, thread: nil) == untitledOrcaRollout
        && orcaIndexThreads["thread-t"] == OrcaCodexThread(orcaSessionId: "codex_t", title: "Orca 제목")
        && orcaIndexThreads["thread-dup"] == OrcaCodexThread(orcaSessionId: "", title: "둘")
        && orcaIndexThreads.count == 2
    let runningCodexPayload = try! JSONDecoder().decode(StatePayload.self, from: "{\"state\":\"running\",\"sessionId\":\"thread-one\",\"source\":\"codex\",\"sessionTitle\":\"예전 제목\",\"updatedAtMs\":1000}".data(using: .utf8)!)
    let completedCodexTask = reconcileCodexTask(
        payload: runningCodexPayload,
        indexTitle: "완료된 task의 현재 제목",
        transcriptStatus: CodexTranscriptStatus(completedAtMs: 2000, latestPromptAtMs: 1000)
    )
    let restartedCodexTask = reconcileCodexTask(
        payload: runningCodexPayload,
        indexTitle: "새 요청의 제목",
        transcriptStatus: CodexTranscriptStatus(completedAtMs: 999, latestPromptAtMs: 1000)
    )
    let codexStateReconciliationOK = completedCodexTask.state == .waving
        && completedCodexTask.observedAtMs == 2000
        && completedCodexTask.needsAttention
        && completedCodexTask.title == "완료된 task의 현재 제목"
        && completedCodexTask.source == .rollout
        && restartedCodexTask.state == .running
        && restartedCodexTask.source == .hook
        && codexTranscriptOrderingOK

    let clientRoutingOK = openApp(forClient: "claude") == .claude
        && openApp(forClient: "vscode") == .vscode
        && openApp(forClient: "codex") == .codex
        && openApp(forClient: "cli") == .vscode
        && openApp(forClient: nil) == .vscode
        && openApp(forClient: "") == .vscode
    // 창을 먼저 앞으로 보내는 단계는 VS Code 에만 있다. Claude 앱에서 이걸 켜면 딥링크가 영영 안 나간다.
        && OpenApp.vscode.needsWindowFocusFirst && !OpenApp.claude.needsWindowFocusFirst && !OpenApp.codex.needsWindowFocusFirst
        && OpenTarget.allCases.map(\.rawValue) == ["auto", "vscode", "claude"]
    let codexMenuOK = aiSessionOpenMenuTitle == "기본 열기 방식"
        && emptyClaudeSessionLabel == "Claude · 실행 중인 세션 없음"
        && emptyCodexSessionLabel == "Codex · 실행 중인 task 없음"
        && codexOpenTargetMenuLabel(isRegistered: true) == "Codex 연결 확인 · 실시간 연결됨"
        && codexOpenTargetMenuLabel(isRegistered: false) == "Codex 연결 확인 · 기본 표시 중"
    // 연동 확인이 실제로 셋을 가려내는지. 이게 틀리면 "정상" 이라고 말해 놓고 아무 소식도 안 온다.
    // 훅 세는 규칙은 지금의 command 한 줄과 0.7.0 까지의 command+args 를 함께 알아봐야 한다 —
    // 갱신 전에 열어 본 사람에게 "훅 없음" 이라고 말하면 안 된다.
    let hookFixture: [String: Any] = ["hooks": [
        "Stop": [["hooks": [
            ["type": "command", "command": "'/Users/x/.claude/retto-pet/hook.sh' 'waving'"],
            ["type": "command", "command": "announce"]
        ]]],
        "SessionStart": [["hooks": [
            ["type": "command", "command": "node", "args": ["/Users/x/.claude/retto-pet/hook.cjs", "idle"]]
        ]]],
        "PreToolUse": [["hooks": [["type": "command", "command": "/Users/x/.claude/reto-pet/hook.cjs"]]]]
    ]]
    let codexHookFixture: [String: Any] = ["hooks": [
        "SessionStart": [["hooks": [
            ["type": "command", "command": "'/Users/x/.claude/retto-pet/hook.sh' 'idle' 'codex'"]
        ]]],
        "Stop": [["hooks": [
            ["type": "command", "command": "'/Users/x/.claude/retto-pet/hook.sh' 'waving' 'codex'"],
            ["type": "command", "command": "'/Users/x/.claude/retto-pet/hook.sh' 'waving'"]
        ]]]
    ]]
    let newsFixture = [
        "{\"state\":\"running\",\"sessionId\":\"a\",\"client\":\"vscode\",\"updatedAtMs\":1000}",
        "{\"state\":\"idle\",\"sessionId\":\"b\",\"client\":\"vscode\",\"updatedAtMs\":5000}",
        "{\"state\":\"idle\",\"sessionId\":\"c\",\"source\":\"codex\",\"updatedAtMs\":3000}",
        "{\"state\":\"idle\",\"sessionId\":\"d\",\"updatedAtMs\":9000}"
    ].compactMap { try? JSONDecoder().decode(StatePayload.self, from: $0.data(using: .utf8)!) }
    let news = ClaudeIntegration.lastNews(in: newsFixture)
    var missingHooks = ClaudeIntegrationStatus()
    missingHooks.shimInstalled = true
    missingHooks.hookInstalled = true
    missingHooks.nodePath = "/opt/homebrew/bin/node"
    var quiet = missingHooks
    quiet.registeredEvents = 17
    var healthy = quiet
    healthy.lastNews = [.vscode: Date()]
    var outdated = quiet
    outdated.outdatedEvents = 1
    let countedHooks = ClaudeIntegration.countRegisteredEvents(in: hookFixture)
    let emptyHooks = ClaudeIntegration.countRegisteredEvents(in: ["hooks": [String: Any]()])
    let countedCodexHooks = ClaudeIntegration.countRegisteredCodexEvents(in: codexHookFixture)
    var currentCodex = healthy
    currentCodex.codexRegisteredEvents = 9
    currentCodex.lastNews = [.codex: Date(timeIntervalSinceNow: -5)]
    currentCodex.hookUpdatedAt = Date(timeIntervalSinceNow: -10)
    var staleCodex = currentCodex
    staleCodex.hookUpdatedAt = Date()
    let integrationOK = countedHooks.total == 3
        && countedHooks.outdated == 1
        && emptyHooks.total == 0
        && emptyHooks.outdated == 0
        && countedCodexHooks == 2
        && NewsChannel.of(client: "claude", source: nil) == .claudeApp
        && NewsChannel.of(client: "cli", source: nil) == .cli
        && NewsChannel.of(client: "vscode", source: "codex") == .codex
        // client 를 못 읽은 옛 기록은 어느 채널로도 세지 않는다. 셌다가는 없는 소식을 있다고 한다.
        && NewsChannel.of(client: nil, source: nil) == nil
        && news.count == 2
        && news[.vscode] == Date(timeIntervalSince1970: 5)
        && news[.claudeApp] == nil
        && missingHooks.menuTitle == "AI 연동 확인 — 훅 없음"
        && quiet.menuTitle == "AI 연동 확인 — 소식 없음"
        && outdated.menuTitle == "AI 연동 확인 — 훅 갱신 필요"
        && healthy.menuTitle == "AI 연동 확인"
        && healthy.isHealthy && !quiet.isHealthy && !outdated.isHealthy
        && currentCodex.hasCurrentCodexNews && !staleCodex.hasCurrentCodexNews
        && staleCodex.menuTitle == "AI 연동 확인 — Codex 확인 필요"
        && elapsedLabel(since: Date(timeIntervalSinceNow: -30)) == "방금"
        && elapsedLabel(since: Date(timeIntervalSinceNow: -180)) == "3분 전"
        && elapsedLabel(since: Date(timeIntervalSinceNow: -7200)) == "2시간 전"
    // 처음 설정 창. 이미 소식이 오는 사람에게 뜨면 잘 돌고 있는데도 고장인 줄 안다.
    // 안내 문구는 깔려 있는 것만 말해야 한다 — 없는 앱을 켜 보라고 하면 그 줄부터 믿지 않는다.
    var connected = ClaudeIntegrationStatus()
    connected.lastNews = [.vscode: Date()]
    // 훅은 멀쩡한데 아직 소식이 없는 상태. 처음 켠 사람이 보는 화면이다.
    var blank = ClaudeIntegrationStatus()
    blank.registeredEvents = 17
    blank.shimInstalled = true
    blank.hookInstalled = true
    blank.nodePath = "/opt/homebrew/bin/node"
    // 설치기가 node 를 못 찾아 훅을 건너뛴 상태. 고칠 것이 둘이다.
    let broken = ClaudeIntegrationStatus()
    var claudeAppOnly = RettoHostEnvironment()
    claudeAppOnly.hasClaudeApp = true
    var codexToo = claudeAppOnly
    codexToo.hasCodex = true
    let nothing = RettoHostEnvironment()
    let setupOK = shouldShowSetupOnLaunch(hasSeen: false, status: blank)
        && !shouldShowSetupOnLaunch(hasSeen: true, status: blank)
        && !shouldShowSetupOnLaunch(hasSeen: false, status: connected)
        && claudeAppOnly.whatToTry.count == 1
        && claudeAppOnly.whatToTry[0].contains("대화창")
        && !claudeAppOnly.whatToTry.joined().contains("VS Code")
        && codexToo.whatToTry.count == 2
        && codexToo.whatToTry.last!.contains("Codex")
        // 아무것도 못 찾았을 때도 할 말은 있어야 한다. 빈 창은 고장으로 읽힌다.
        && nothing.whatToTry.count == 1
        && nothing.whatToTry[0].contains("먼저 설치")
        // 고칠 것이 있을 때만 단추가 나온다. 멀쩡한데 「훅 지금 붙이기」가 보이면
        // 눌러야 하는 줄 알고 멀쩡한 설정을 다시 쓴다.
        && setupButtons(for: blank) == []
        && setupButtons(for: broken) == ["훅 지금 붙이기", "Node.js 받기"]
    // 옛 앱 정리. 자기 자신을 옛 것으로 보면 켜자마자 자기를 종료하고 휴지통에 넣는다 —
    // 이름이나 번들 ID 를 또 바꿀 때 여기서 걸려야 한다.
    let legacyOK = !legacyAppNames.contains(Bundle.main.bundleURL.lastPathComponent)
        && !legacyBundleIdentifiers.contains(Bundle.main.bundleIdentifier ?? "")
        && legacyAppNames.allSatisfy { $0.hasSuffix(".app") }
        && legacyBundleIdentifiers.allSatisfy { $0.hasPrefix("com.luxia.") }
        // 지금 이름이 옛 목록에 없다는 것만으로는 부족하다. 옛 이름 둘을 실제로 들고 있어야
        // 0.7.0 을 쓰던 사람의 앱이 걷힌다.
        && legacyAppNames.count == 2 && legacyBundleIdentifiers.count == 2
    let scalesOK = supportedScales.first == 0.39 && supportedScales.last == 1.4
    // 배율 1에서는 예전 창 크기를 그대로 유지한다.
    let baseline = petLayout(scale: 1)
    // 상수를 바꿔도 관계가 유지되는지 본다. 숫자를 박아두면 값 조정마다 검사가 거짓으로 깨진다.
    let baseChrome = chromeScale(for: 1)
    let baselineOK = baseline.chromeScale == baseChrome
        && baseline.petRect.width == basePetWidth
        && baseline.ribbonRect.height == baseRibbonHeight * baseChrome
        && abs(baseline.windowSize.width - max(basePetWidth + 2 * petSideMargin, (baseRibbonWidth + 2 * ribbonSideInset) * baseChrome)) < 0.01
        && abs(baseline.windowSize.height - (baseline.petRect.maxY + petBadgeHeadroom)) < 0.01
        && abs(baseline.ribbonRect.maxY - (baseline.petRect.minY + petRibbonOverlap)) < 0.01
    // 가장 작은 배율에서 몸은 프리셋을 그대로 따르지만, 말풍선은 글이 읽히는 하한 아래로 내려가지
    // 않고 창은 말풍선 폭을 따라간다. 곡선의 기준점(chromeScaleAnchor)은 프리셋 목록과 따로 두므로
    // 가장 작은 프리셋을 올려도 하한만 지키면 된다 — 기준점과 같아야 할 이유는 없다.
    let smallest = petLayout(scale: supportedScales[0])
    let decoupledOK = smallest.petRect.width == basePetWidth * supportedScales[0]
        && smallest.chromeScale >= chromeScaleAtMin
        && abs(smallest.chromeScale - chromeScale(for: supportedScales[0])) < 0.0001
        && smallest.ribbonRect.height == baseRibbonHeight * smallest.chromeScale
        && smallest.windowSize.width > smallest.petRect.width
        // 프리셋을 한 칸 올리면 말풍선도 반드시 커져야 한다. 레토만 커지면 뜻이 없다.
        && zip(supportedScales, supportedScales.dropFirst()).allSatisfy { small, large in
            petLayout(scale: large).ribbonRect.height > petLayout(scale: small).ribbonRect.height + 1
        }
    // 완료는 모션을 유지하고, 시선 행으로 완료 자세를 덮으면 안 된다.
    // 시선은 코덱스와 같은 세 상태에서만 걸린다.
    let gazePathsOK = (0..<gazeDirectionCount).allSatisfy { start in
        (0..<gazeDirectionCount).allSatisfy { target in
            var current = start
            var steps = 0
            while current != target && steps <= gazeDirectionCount / 2 {
                let next = nextGazeDirection(from: current, toward: target)
                let distance = (next - current + gazeDirectionCount) % gazeDirectionCount
                guard distance == 1 || distance == gazeDirectionCount - 1 else { return false }
                current = next
                steps += 1
            }
            let clockwise = (target - start + gazeDirectionCount) % gazeDirectionCount
            return current == target && steps == min(clockwise, gazeDirectionCount - clockwise)
        }
    }
    let gazeStatesOK = gazePathsOK && gazeStates == [.idle, .running, .waving]
        && allowsGazeForTask(displayed: displayState(state: .waving, updatedAtMs: 100,
            seenAtMs: 200, transcriptModifiedAtMs: nil, nowMs: 200), reported: .waving)
        && PetState.allCases.allSatisfy { allowsGazeForTask(displayed: $0, reported: nil) == gazeStates.contains($0) }
        && allowsGazeForTask(displayed: .idle, reported: .idle)
        && allowsGazeForTask(displayed: .running, reported: .running)
        && christmasGazeStepDuration * Double(gazeDirectionCount / 2) < gazeHoldDuration
        && nextGazeDirection(from: 15, toward: 1) == 0
        && nextGazeDirection(from: 1, toward: 15) == 0
        && nextGazeDirection(from: 3, toward: 3) == 3
        && gazeHoldDuration > 0
        && gazeHoldDuration <= 1
        && gazeDirectionCount == 16
        && gazeDirection(dx: 0, dy: 1, previous: nil) == 0
        && gazeDirection(dx: 1, dy: 0, previous: nil) == 4
        && gazeDirection(dx: 0, dy: -1, previous: nil) == 8
        && gazeDirection(dx: -1, dy: 0, previous: nil) == 12
        // 11.25도 경계 바로 옆의 미세한 이동은 현재 고개 방향을 유지한다.
        && gazeDirection(dx: 0.22, dy: 1, previous: 0) == 0
        // 히스테리시스 바깥에서는 다음 방향으로 넘어간다.
        && gazeDirection(dx: 0.34, dy: 1, previous: 0) == 1
    // 배지는 말풍선 오른쪽 위에 고정이고, 왼쪽 이름표와 같은 만큼 위로 솟는다.
    let badge = attentionBadgeRect(ribbon: baseline.ribbonRect, scale: baseline.chromeScale)
    let badgeLayoutOK = badge.width == attentionBadgeSide * baseline.chromeScale
        && badge.maxX < baseline.ribbonRect.maxX
        && badge.maxY > baseline.ribbonRect.maxY
        && badge.minY < baseline.ribbonRect.maxY
        && badge.midX > baseline.ribbonRect.midX
        && attentionBadgeRect(ribbon: baseline.ribbonRect, scale: 1.4).width == attentionBadgeSide * 1.4
    // 배지가 떠 있을 때만 배지로 간다.
    let clickRoutingOK = petClickTarget(layout: baseline, badgeFrame: badge, point: NSPoint(x: badge.midX, y: badge.midY), attentionCount: 2) == .badge
        && petClickTarget(layout: baseline, badgeFrame: .zero, point: NSPoint(x: baseline.ribbonRect.midX, y: baseline.ribbonRect.midY), attentionCount: 2) == .ribbon
        && petClickTarget(layout: baseline, badgeFrame: badge, point: NSPoint(x: baseline.petRect.midX, y: baseline.petRect.midY), attentionCount: 2) == .body
        && petClickTarget(layout: baseline, badgeFrame: badge, point: NSPoint(x: 2, y: baseline.windowSize.height - 2), attentionCount: 2) == nil
    // 내 답 대기 → 실패 → 답변 완료 순서이며, 셋 다 작업 중보다 먼저 표시한다.
    let priorityOK = selectionPriority(state: .waiting, isClosed: false) > selectionPriority(state: .waving, isClosed: false)
        && selectionPriority(state: .waiting, isClosed: false) > selectionPriority(state: .failed, isClosed: false)
        && selectionPriority(state: .failed, isClosed: false) > selectionPriority(state: .waving, isClosed: false)
        && needsInputStates.allSatisfy {
            selectionPriority(state: $0, isClosed: false) > selectionPriority(state: .running, isClosed: false)
                && selectionPriority(state: $0, isClosed: false) > selectionPriority(state: .review, isClosed: false)
        }
        && selectionPriority(state: .idle, isClosed: true) < 0
    // 펼치면 말풍선만 자라고 창도 그만큼만 커진다.
    let expanded = petLayout(scale: 1, expanded: true)
    let grown = ribbonBodyHeight * baseline.chromeScale
    let expandOK = abs(expanded.ribbonRect.height - (baseline.ribbonRect.height + grown)) < 0.01
        && abs(expanded.windowSize.height - (baseline.windowSize.height + grown)) < 0.01
        && expanded.windowSize.width == baseline.windowSize.width
        && expanded.petRect.width == baseline.petRect.width
        && expanded.ribbonRect.maxY - expanded.petRect.minY == baseline.ribbonRect.maxY - baseline.petRect.minY
    // 접으면 두 줄, 펼치면 네 줄까지 보여야 한다. 실제 폰트 메트릭으로 잰다.
    let bodyFont = NSFont(name: rettoHandwritingFontName, size: 18 * baseline.chromeScale)
        ?? NSFont.systemFont(ofSize: 18 * baseline.chromeScale)
    let bodyLineHeight = bodyFont.ascender - bodyFont.descender + bodyFont.leading
    let bodySpacing = 0.875 * baseline.chromeScale
    func lineBudget(_ areaHeight: CGFloat) -> Int {
        max(0, Int(((areaHeight + bodySpacing) / (bodyLineHeight + bodySpacing)).rounded(.down)))
    }
    let compactArea = baseline.ribbonRect.height - 30 * baseline.chromeScale
    let expandedArea = expanded.ribbonRect.height - 30 * baseline.chromeScale
    let lineBudgetOK = lineBudget(compactArea) == 2 && lineBudget(expandedArea) == 4
    // 서체 두 종. 기본 서체는 손글씨보다 3pt 작게 그려지므로 같은 칸에 줄이 더 들어간다 —
    // 그 여분이 둥근 말풍선의 아래 곡선에 걸려 반토막으로 그려졌던 적이 있다. 지금은 그리기 쪽에서
    // 허용한 줄 수 밖을 잘라내므로, 여기서는 "기본 서체가 손글씨보다 작다"는 전제만 지켜지는지 본다.
    func typefaceLine(_ face: PetTypeface) -> CGFloat {
        let font = petFont(face, size: 18 * baseline.chromeScale)
        return font.ascender - font.descender + font.leading
    }
    let typefaceOK = PetTypeface.allCases.count == 2
        && PetTypeface(rawValue: "handwriting") == .handwriting
        && PetTypeface(rawValue: "system") == .system
        && PetTypeface(rawValue: "없는값") == nil
        && petFont(.handwriting, size: 18).fontName.contains("Nanum")
        && !petFont(.system, size: 18).fontName.contains("Nanum")
        // 기본 서체는 -3pt 로 잡혀 있어야 한다. 이 전제가 깨지면 크기 선택이 무의미해진다.
        && petFont(.system, size: 18).pointSize == 18 + systemTypefaceDelta
        && typefaceLine(.system) < typefaceLine(.handwriting)
    // 프리셋별 글자 깎기: 말풍선 치수는 그대로 두고 글자만 줄여야 한다.
    func bodyLines(at scale: CGFloat) -> Int {
        let layout = petLayout(scale: scale)
        let size = 18 * layout.chromeScale + layout.textDelta
        let font = NSFont(name: rettoHandwritingFontName, size: size) ?? NSFont.systemFont(ofSize: size)
        let line = font.ascender - font.descender + font.leading
        let spacing = 0.875 * layout.chromeScale
        let area = layout.ribbonRect.height - 30 * layout.chromeScale
        return max(0, Int(((area + spacing) / (line + spacing)).rounded(.down)))
    }
    let half = petLayout(scale: 0.5)
    let textDeltaOK = half.textDelta == -1.5
        // 초소형은 반 픽셀만 깎는다. 손글씨가 이 크기에서 뭉개지기 시작한다.
        && petLayout(scale: 0.39).textDelta == -0.5
        && baseline.textDelta == 0
        // 말풍선·창은 깎기 전과 같은 크기다. 글자만 줄인 것이지 칸을 줄인 게 아니다.
        && half.ribbonRect.height == baseRibbonHeight * chromeScale(for: 0.5)
        && abs(half.windowSize.width - max(basePetWidth * 0.5 + 2 * petSideMargin * 0.5, (baseRibbonWidth + 2 * ribbonSideInset) * chromeScale(for: 0.5))) < 0.01
        // 글자가 작아졌다고 두 줄이 세 줄로 늘면 말풍선이 달라 보인다.
        && bodyLines(at: 0.5) == 2
    // 레토 크기와 글자 크기를 서로 바꿔도 상대 설정과 말풍선 치수는 유지한다.
    let chatReference: CGFloat = 0.5
    let chatBaseline = petLayout(scale: chatReference)
    let independentChatOK = supportedScales.allSatisfy { scale in
        ChatFontSize.allCases.allSatisfy { size in
            let layout = petLayout(scale: scale, chatScale: chatReference, fontSize: size)
            let bodySize = 18 * layout.chromeScale + layout.textDelta
            let expected = (18 * chatBaseline.chromeScale + chatBaseline.textDelta) * size.factor
            return abs(bodySize - expected) < 0.0001
                && layout.petRect.width == basePetWidth * scale
                && layout.ribbonRect.height == chatBaseline.ribbonRect.height
                && layout.ribbonRect.width == chatBaseline.ribbonRect.width
                && PetTypeface.allCases.allSatisfy { face in
                    let font = petFont(face, size: bodySize)
                    return font.pointSize > 0 && font.ascender - font.descender + font.leading
                        < layout.ribbonRect.height - 30 * layout.chromeScale
                }
        }
    } && petLayout(scale: chatReference, chatScale: chatReference).textDelta == chatBaseline.textDelta
        && zip(ChatFontSize.allCases, ChatFontSize.allCases.dropFirst()).allSatisfy { $0.factor < $1.factor }
    // 색은 뜻 단위 넷(+조용함)으로만 쓰고, 뜻이 섞이지 않아야 한다.
    let tonesOK = animationCatalog[.running]?.tone.key == toneWorking.key
        && animationCatalog[.review]?.tone.key == toneWorking.key
        && animationCatalog[.jumping]?.tone.key == toneWorking.key
        && animationCatalog[.waiting]?.tone.key == toneNeedsYou.key
        && animationCatalog[.waving]?.tone.key == toneDone.key
        && animationCatalog[.failed]?.tone.key == toneFailed.key
        && animationCatalog[.idle]?.tone.key == toneQuiet.key
        && Set(animationCatalog.values.map(\.tone.key)).count == 5
    // 말풍선은 Figma 도형을 그대로 옮긴 것이어야 한다. 원본 비율과 칸 채우기를 확인한다.
    let template = bubbleTemplate.bounds
    let filled = bubblePath(in: NSRect(x: 5, y: 7, width: 200, height: 60)).bounds
    let bubbleShapeOK = abs(template.width / template.height - 3.1129) < 0.01
        && abs(filled.minX - 5) < 0.5 && abs(filled.minY - 7) < 0.5
        && abs(filled.width - 200) < 0.5 && abs(filled.height - 60) < 0.5
        && bubbleTemplate.elementCount > 20
    // 손 흔들기는 두 바퀴로 끝나지만 그건 그림 이야기다. 완료 상태의 우선순위·색은 그대로 남아야 한다.
    let doneStaysOK = animationCatalog[.waving]?.cycleLimit == 2
        && selectionPriority(state: .waving, isClosed: false) > selectionPriority(state: .idle, isClosed: false)
        && animationCatalog[.waving]?.tone.key != animationCatalog[.idle]?.tone.key
    // 유령 규칙: 작업 중은 10분 뒤 조용해지고, 손이 필요한 상태는 아무리 오래돼도 남는다.
    let nowFixture: Double = 1_000_000_000
    let longAgo = nowFixture - staleWorkingTimeout * 1000 - 1
    let staleOK = isStaleWorking(state: .running, updatedAtMs: longAgo, nowMs: nowFixture)
        && isStaleWorking(state: .review, updatedAtMs: longAgo, nowMs: nowFixture)
        && !isStaleWorking(state: .running, updatedAtMs: nowFixture - 1000, nowMs: nowFixture)
        && !isStaleWorking(state: .waving, updatedAtMs: longAgo, nowMs: nowFixture)
        && !isStaleWorking(state: .waiting, updatedAtMs: longAgo, nowMs: nowFixture)
        && !isStaleWorking(state: .failed, updatedAtMs: longAgo, nowMs: nowFixture)
    // 읽음 규칙: 다녀온 시각이 마지막 갱신보다 뒤면 조용해지고, 새 소식이 오면 다시 올라온다.
    let seenOK = isSeen(updatedAtMs: 100, seenAtMs: 200)
        && isSeen(updatedAtMs: 100, seenAtMs: 100)
        && !isSeen(updatedAtMs: 300, seenAtMs: 200)
        && !isSeen(updatedAtMs: 100, seenAtMs: nil)
    // 이름표는 한글 12자 폭에서 접힌다. 폭이 좁은 영문은 12자를 넘어도 잘리지 않아야 한다.
    let labelFont = NSFont(name: rettoHandwritingFontName, size: 16.5) ?? NSFont.boldSystemFont(ofSize: 16.5)
    let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont]
    let labelBudgetWidth = (sectionLabelWidthSample as NSString).size(withAttributes: labelAttributes).width
    func labelWidth(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: labelAttributes).width }
    let labelOK = sectionLabelWidthSample.count == 12
        && labelWidth(sectionLabelWidthSample) <= labelBudgetWidth + 0.01
        && labelWidth("session-title-abc") < labelBudgetWidth
        && labelWidth("백오피스 조직별 화면 목업 다시 봐줘") > labelBudgetWidth
    // 세션 폴더 → 창 폴더 접기. 하위 폴더를 그대로 열면 새 창이 생기므로 조상으로 바꿔야 한다.
    let folderFixture = ["/a/planning", "/a/git-rehyundesign", "/a"]
    func deepestAncestor(_ path: String) -> String? {
        folderFixture.filter { path == $0 || path.hasPrefix($0 + "/") }.max(by: { $0.count < $1.count })
    }
    let folderFoldOK = deepestAncestor("/a/planning/mockups/apps/mockup-hub") == "/a/planning"
        && deepestAncestor("/a/planning") == "/a/planning"
        && deepestAncestor("/b/other") == nil
    let registryFixture = "{\"sessions\":{\"one\":{\"state\":\"running\",\"sessionId\":\"one\",\"displayTitle\":\"A\"},\"two\":{\"state\":\"waiting\",\"sessionId\":\"two\",\"displayTitle\":\"B\"}}}".data(using: .utf8)!
    let registryOK = (try? JSONDecoder().decode(SessionRegistry.self, from: registryFixture).sessions.count) == 2
    // 이름표 우선순위: 세션명 > 작업 주제 > 쓸 만한 길이의 프롬프트 > 이름 없음.
    // 폴더는 메뉴 줄이 이름 뒤에 따로 붙이므로 여기서 내면 두 번 뜬다.
    // ⚠️ 짧은 답("B"·"재진행")은 이름이 아니다. 훅이 대화 도중 붙으면 그 답이 displayTitle 로
    // 굳는데, 그대로 띄우면 세션명 자리에 내가 친 답이 뜬다. 실제로 그렇게 났다.
    func titleOf(_ json: String) -> String {
        guard let d = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(StatePayload.self, from: d) else { return "" }
        return p.title
    }
    let titleOK = titleOf("{\"state\":\"running\",\"sessionTitle\":\"서치서울 문서\",\"displayTitle\":\"아주 긴 프롬프트입니다\",\"projectName\":\"planning\"}") == "서치서울 문서"
        && titleOf("{\"state\":\"running\",\"activeTaskSubject\":\"토큰 정리\",\"displayTitle\":\"아주 긴 프롬프트입니다\",\"projectName\":\"planning\"}") == "토큰 정리"
        && titleOf("{\"state\":\"running\",\"displayTitle\":\"아주 긴 프롬프트입니다\",\"projectName\":\"planning\"}") == "아주 긴 프롬프트입니다"
        && titleOf("{\"state\":\"running\",\"displayTitle\":\"B\",\"projectName\":\"planning\"}") == "No name"
        && titleOf("{\"state\":\"running\",\"displayTitle\":\"재진행\",\"projectName\":\"planning\"}") == "No name"
    // 같은 대화를 3초 확인해야 읽음으로 처리한다.
    var readDwell = SessionReadDwell()
    let viewedOK = !readDwell.observe(key: "session-a", nowMs: 0)
        && !readDwell.observe(key: "session-b", nowMs: 3000)
        && readDwell.observe(key: "session-b", nowMs: 6000)
        && !readDwell.observe(key: nil, nowMs: 7000)

    // 전부 조용한 채로 10분이 지나면 자는지. 하나라도 일하고 있으면 안 잔다.
    let nowFixed: Double = 100_000_000
    let sleepOK = shouldSleep(newestUpdatedAtMs: nowFixed - sleepAfter * 1000 - 1, nowMs: nowFixed, hasBusySession: false)
        && !shouldSleep(newestUpdatedAtMs: nowFixed - sleepAfter * 1000 - 1, nowMs: nowFixed, hasBusySession: true)
        && !shouldSleep(newestUpdatedAtMs: nowFixed - 60_000, nowMs: nowFixed, hasBusySession: false)
        && !shouldSleep(newestUpdatedAtMs: nil, nowMs: nowFixed, hasBusySession: false)
        && animationCatalog[.sleeping]?.tone.key == "quiet"

    // 읽음 표시가 일하는 중을 회색으로 덮지 않는지, 트랜스크립트가 자라면 유령이 아닌지.
    let displayOK = displayState(state: .running, updatedAtMs: 1_000, seenAtMs: 9_999_999, transcriptModifiedAtMs: nil, nowMs: 1_500) == .running
        && displayState(state: .waving, updatedAtMs: 1_000, seenAtMs: 2_000, transcriptModifiedAtMs: nil, nowMs: 2_500) == .idle
        && displayState(state: .waving, updatedAtMs: 3_000, seenAtMs: 2_000, transcriptModifiedAtMs: nil, nowMs: 3_500) == .waving
        // 훅은 조용하지만 파일이 자라고 있으면 살아 있다
        && displayState(state: .running, updatedAtMs: 1_000, seenAtMs: nil,
                        transcriptModifiedAtMs: 1_000_000, nowMs: 1_000_100) == .running
        // 훅도 파일도 오래 조용하면 유령
        && displayState(state: .running, updatedAtMs: 1_000, seenAtMs: nil,
                        transcriptModifiedAtMs: 2_000, nowMs: 2_000 + staleWorkingTimeout * 1000 + 1) == .idle

    // 깔려 있지 않은 앱으로 보내지 않는지.
    let fallbackOK = installedOpenApp(preferred: .vscode) { $0 == .claude } == .claude
        && installedOpenApp(preferred: .claude) { $0 == .vscode } == .vscode
        && installedOpenApp(preferred: .codex) { $0 == .claude } == .claude
        && installedOpenApp(preferred: .vscode) { _ in true } == .vscode
        && installedOpenApp(preferred: .claude) { _ in false } == .claude

    // 네 모서리 좌표가 맞는지. 화면 900×600, 창 200×150, 여백 24 로 계산해 본다.
    let visibleTest = NSRect(x: 100, y: 50, width: 900, height: 600)
    let boxTest = NSSize(width: 200, height: 150)
    let cornerOK = cornerOrigin(corner: .free, size: boxTest, visible: visibleTest) == nil
        && cornerOrigin(corner: .bottomLeft, size: boxTest, visible: visibleTest) == NSPoint(x: 124, y: 74)
        && cornerOrigin(corner: .bottomRight, size: boxTest, visible: visibleTest) == NSPoint(x: 776, y: 74)
        && cornerOrigin(corner: .topLeft, size: boxTest, visible: visibleTest) == NSPoint(x: 124, y: 476)
        && cornerOrigin(corner: .topRight, size: boxTest, visible: visibleTest) == NSPoint(x: 776, y: 476)
        && PetCorner.bottomRight.anchorsToBottom && !PetCorner.topRight.anchorsToBottom
        && PetCorner.allCases.count == 5

    // 창 제목으로 "그 세션을 보고 있다" 를 알아내는지. 짧은 폴더 이름에 낚이지 않아야 한다.
    let lookingOK = windowShowsSession(windowTitle: "백오피스 기획 — planning", sessionTitle: "백오피스 기획", folderName: "planning")
        && !windowShowsSession(windowTitle: "hook.cjs — git-rehyundesign", sessionTitle: "레토 공식", folderName: "git-rehyundesign")
        && !windowShowsSession(windowTitle: "hook.cjs — other-repo", sessionTitle: "레토 공식", folderName: "git-rehyundesign")
        && !windowShowsSession(windowTitle: "", sessionTitle: "레토 공식", folderName: "git-rehyundesign")
        && !windowShowsSession(windowTitle: "a — b", sessionTitle: nil, folderName: "ui")   // 두 글자 폴더는 안 믿는다
        && lookingDwell >= 2

    // 다 끝내 놓고 30분 아무도 안 오면 그림만 잠드는지. 하나라도 일하면 안 잔다.
    let dozeOK = shouldDozeWhileWaiting(newestAttentionAtMs: nowFixed - dozeAfter * 1000 - 1, nowMs: nowFixed, everythingDone: true)
        && !shouldDozeWhileWaiting(newestAttentionAtMs: nowFixed - dozeAfter * 1000 - 1, nowMs: nowFixed, everythingDone: false)
        && !shouldDozeWhileWaiting(newestAttentionAtMs: nowFixed - 60_000, nowMs: nowFixed, everythingDone: true)
        && !shouldDozeWhileWaiting(newestAttentionAtMs: nil, nowMs: nowFixed, everythingDone: true)
        && dozeAfter > sleepAfter   // 다 자는 것보다 늦게 졸아야 한다

    // 앱이 켜지기 한참 전에 끝난 일을 새 소식으로 알리지 않는지.
    let launchMs: Double = 10_000_000
    let ancientOK = isAncientNews(updatedAtMs: launchMs - trackingGrace * 1000 - 1, trackingStartedAtMs: launchMs)
        && !isAncientNews(updatedAtMs: launchMs - 60_000, trackingStartedAtMs: launchMs)  // 1분 전 완료는 알린다
        && !isAncientNews(updatedAtMs: launchMs + 60_000, trackingStartedAtMs: launchMs)  // 켜진 뒤 완료는 당연히 알린다
        && !isAncientNews(updatedAtMs: nil, trackingStartedAtMs: launchMs)

    // 흰 배경 머리 위: 옅은 회색이 세 줄 넘게 깔리면 사각형처럼 보인다.
    let halo = headroomHalo(spriteSheet: image)
    let haloOK = halo.rows <= 3 && halo.deepest <= 12

    // Claude 앱 사이드바 행 매칭. 라벨은 "<상태> <제목>" 꼴이고 상태는 실시간으로 바뀐다.
    // 부분 일치를 허용하면 엉뚱한 세션을 연다 — 그게 이 기능에서 가장 나쁜 실패다.
    let claudeRowOK = claudeRowMatchesSession(rowLabel: "입력 대기 중 흠냐링", sessionTitle: "흠냐링")
        && claudeRowMatchesSession(rowLabel: "실행 중 흠냐링", sessionTitle: "흠냐링")
        && claudeRowMatchesSession(rowLabel: "유휴 General coding session", sessionTitle: "General coding session")
        && claudeRowMatchesSession(rowLabel: "흠냐링", sessionTitle: "흠냐링")
        && !claudeRowMatchesSession(rowLabel: "입력 대기 중 흠냐링", sessionTitle: "냐링")
        && !claudeRowMatchesSession(rowLabel: "실행 중 클로드앱에서 해보자", sessionTitle: "흠냐링")
        && !claudeRowMatchesSession(rowLabel: "입력 대기 중 흠냐링", sessionTitle: "링")
        && !claudeRowMatchesSession(rowLabel: "", sessionTitle: "흠냐링")
        && !claudeRowMatchesSession(rowLabel: "입력 대기 중 흠냐링", sessionTitle: "")

    // ⚠️ ok 에 넣은 항목은 아래 print 에도 반드시 넣는다. 안 그러면 그 항목이 실패해도
    // ok:false 만 뜨고 무엇이 깨졌는지 알 수 없다 — 실제로 두 번 헤맸다.
    // scripts/check.sh 가 두 줄을 대조해서 빠진 게 있으면 막는다.
    let ok = sixFrameThinkingTimingOK && christmasOK && claudeRowOK && fallbackOK && cornerOK && lookingOK && sleepRowOK && displayOK && dozeOK && sleepOK && ancientOK && viewedOK && haloOK && assetOK && skinsOK && dragRunOK && behaviorsOK && statesOK && deepLinkOK && clientRoutingOK && codexMenuOK && integrationOK && setupOK && legacyOK && transcriptShapesOK && scalesOK && baselineOK && decoupledOK && fontOK && priorityOK && registryOK && titleOK && badgeLayoutOK && clickRoutingOK && gazeStatesOK && expandOK && lineBudgetOK && typefaceOK && textDeltaOK && independentChatOK && tonesOK && folderFoldOK && labelOK && doneStaysOK && bubbleShapeOK && seenOK && staleOK && personalV2LayoutOK && codexTitleRefreshOK && codexCompletionRefreshOK && codexStateReconciliationOK && rolloutDiscoveryPayloadOK && unnamedTitleOK && orcaOK && orcaChatStatusOK
    print("{\"ok\":\(ok),\"asset\":\"\(Int(image.size.width))x\(Int(image.size.height))\",\"skins\":\(PetSkin.selectableCases.count),\"skinsOK\":\(skinsOK),\"christmasEffects\":\(christmasOK),\"dragRun\":\(dragRunOK),\"canJoinAllSpaces\":\(behaviorsOK),\"states\":\(animationCatalog.count),\"deepLink\":\(deepLinkOK),\"clientRouting\":\(clientRoutingOK),\"codexMenu\":\(codexMenuOK),\"integration\":\(integrationOK),\"setup\":\(setupOK),\"legacy\":\(legacyOK),\"transcriptShapes\":\(transcriptShapesOK),\"sizePresets\":\(supportedScales.count),\"baselineLayout\":\(baselineOK),\"scaleDecoupled\":\(decoupledOK),\"badgePlacement\":\(badgeLayoutOK),\"ribbonExpand\":\(expandOK),\"lineBudget\":\(lineBudgetOK),\"typefaces\":\(PetTypeface.allCases.count),\"typefaceOK\":\(typefaceOK),\"textDelta\":\(textDeltaOK),\"independentChat\":\(independentChatOK),\"tones\":\(tonesOK),\"folderFold\":\(folderFoldOK),\"doneStays\":\(doneStaysOK),\"bubbleShape\":\(bubbleShapeOK),\"seenRule\":\(seenOK),\"staleWorking\":\(staleOK),\"headroomClean\":\(haloOK),\"viewedElsewhere\":\(viewedOK),\"ancientNews\":\(ancientOK),\"sleeps\":\(sleepOK),\"sleepRow\":\(sleepRow),\"dozes\":\(dozeOK),\"displayState\":\(displayOK),\"seenByLooking\":\(lookingOK),\"corners\":\(cornerOK),\"appFallback\":\(fallbackOK),\"haloRows\":\(halo.rows),\"haloDeepest\":\(halo.deepest),\"haloFaint\":\(haloFaintPixels),\"claudeRow\":\(claudeRowOK),\"font\":\"\(rettoHandwritingFontName)\",\"fontLoaded\":\(fontOK),\"multiSession\":\(registryOK),\"sessionTitleFallback\":\(titleOK),\"prioritySelection\":\(priorityOK),\"badgeLayout\":\(badgeLayoutOK),\"clickRouting\":\(clickRoutingOK),\"sleepRowOK\":\(sleepRowOK),\"assetOK\":\(assetOK),\"statesOK\":\(statesOK),\"scales\":\(scalesOK),\"gazeStates\":\(gazeStatesOK),\"label\":\(labelOK),\"personalV2Layout\":\(personalV2LayoutOK),\"codexTitleRefresh\":\(codexTitleRefreshOK),\"codexCompletionRefresh\":\(codexCompletionRefreshOK),\"codexStateReconciliation\":\(codexStateReconciliationOK),\"rolloutDiscoveryPayload\":\(rolloutDiscoveryPayloadOK),\"sixFrameThinkingTiming\":\(sixFrameThinkingTimingOK),\"unnamedTitle\":\(unnamedTitleOK),\"orca\":\(orcaOK),\"orcaChatStatus\":\(orcaChatStatusOK)}")
    return ok ? 0 : 1
}

/// 배율별 레이아웃을 화면 없이 PNG 한 장으로 뽑는다. 몸과 리본이 따로 자라는지 눈으로 확인하는 용도.
func renderPreview(to path: String, skin: PetSkin = .classic, chatFonts: Bool = false) -> Int32 {
    registerRettoFont()
    guard let imageURL = Bundle.main.url(forResource: skin.resourceName, withExtension: "webp"),
          let spriteSheet = NSImage(contentsOf: imageURL) else { return 1 }
    let scales: [CGFloat] = chatFonts ? [0.5, 0.5, 0.5, 0.5] : [0.39, 0.5, 0.65, 1.0, 1.4]
    // 칸마다 다른 상태로 그려 색 넷이 한 장에서 비교되게 한다.
    let previewStates = ["idle", "running", "waiting", "sleeping", "failed"]
    // 배지 모서리 네 곳을 한 장에서 다 보이게 돌려 쓴다.
    let gap: CGFloat = 24
    // 마지막 칸은 말풍선을 펼친 모습으로 그린다.
    let expandedFlags = scales.indices.map { $0 == scales.count - 1 }
    let layouts = zip(scales, expandedFlags).enumerated().map { index, pair in
        petLayout(scale: pair.0, expanded: pair.1, chatScale: chatFonts ? 0.5 : nil, fontSize: chatFonts ? ChatFontSize.allCases[index] : .medium)
    }
    let totalWidth = layouts.reduce(0) { $0 + $1.windowSize.width } + gap * CGFloat(layouts.count + 1)
    let bandHeight = (layouts.map(\.windowSize.height).max() ?? 0) + gap * 2 + 22
    // 어두운 배경만 보다가 흰 배경에서 머리 위 그림자를 놓친 적이 있다. 두 줄로 같이 본다.
    let bands: [(background: NSColor, card: NSColor, ink: NSColor)] = [
        (NSColor(calibratedWhite: 0.22, alpha: 1), NSColor(calibratedWhite: 1, alpha: 0.10), .white),
        (NSColor(calibratedWhite: 1.0, alpha: 1), NSColor(calibratedWhite: 0, alpha: 0.04), .black)
    ]
    let totalHeight = bandHeight * CGFloat(bands.count)

    let sheet = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
    sheet.lockFocus()
    for (bandIndex, band) in bands.enumerated() {
    let bandOrigin = totalHeight - bandHeight * CGFloat(bandIndex + 1)
    band.background.setFill()
    NSRect(x: 0, y: bandOrigin, width: totalWidth, height: bandHeight).fill()
    var x = gap
    for (index, (scale, layout)) in zip(scales, layouts).enumerated() {
        let view = RettoView(frame: NSRect(origin: .zero, size: layout.windowSize), spriteSheet: spriteSheet, skin: skin, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        // 서체를 바꿔 놓고 미리보기를 뽑아 눈으로 비교할 수 있어야 한다.
        view.typeface = PetTypeface(rawValue: UserDefaults.standard.string(forKey: typefaceDefaultsKey) ?? "") ?? .handwriting
        view.petScale = scale
        if chatFonts {
            view.chatScale = 0.5
            view.chatFontSize = ChatFontSize.allCases[index]
            view.typeface = bandIndex == 0 ? .handwriting : .system
        }
        let petState = chatFonts ? "waiting" : previewStates[min(index, previewStates.count - 1)]
        let body = "그 파란 숫자의 정체를 코드에서 확인하고 맞췄어. Claude Code 확장이 세션 목록 뷰에 붙이는 배지고, 기준 상태는 waiting_input 이야. 권한 요청만이 아니라 턴이 끝나 답을 기다리는 상태까지 포함해."
        let fixture = "{\"state\":\"\(petState)\",\"sessionId\":\"preview\",\"projectName\":\"platform-web-next\",\"displayTitle\":\"백오피스 조직별 화면 목업 다시 봐줘\",\"lastAssistantMessage\":\"\(body)\"}".data(using: .utf8)!
        guard let payload = try? JSONDecoder().decode(StatePayload.self, from: fixture) else { continue }
        view.apply(payload, sessionCount: 3, attentionCount: 2, attentionState: .waiting, isPinned: true)
        view.setExpandedForPreview(expandedFlags[index])
        view.settleAnimations()
        if skin == .christmas { view.setChristmasTimeForPreview(0.37) }
        // 실제 창은 투명하므로 캐시 캡처(불투명 배경) 대신 뷰를 직접 그린다.
        let card = NSRect(x: x, y: bandOrigin + gap + 22, width: layout.windowSize.width, height: layout.windowSize.height)
        band.card.setFill()
        card.fill()
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: card.minX, yBy: card.minY)
        transform.concat()
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let label = chatFonts ? ChatFontSize.allCases[index].label : String(format: "%.0f%%  %@  %@", scale * 100, petState, expandedFlags[index] ? "말풍선 펼침" : "접힘")
        (label as NSString).draw(at: NSPoint(x: x, y: bandOrigin + 6), withAttributes: [
            .foregroundColor: band.ink,
            .font: NSFont.boldSystemFont(ofSize: 12)
        ])
        x += layout.windowSize.width + gap
    }
    }
    sheet.unlockFocus()
    guard let tiff = sheet.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return 1 }
    do { try png.write(to: URL(fileURLWithPath: path)) } catch { return 1 }
    print(path)
    return 0
}

/// 16컷의 처음·중간·마지막을 모든 상태와 좌우 이동에서 실제 PetView로 확인한다.
func renderChristmas16Preview(to path: String) -> Int32 {
    registerRettoFont()
    guard let url = Bundle.main.url(forResource: PetSkin.christmas.resourceName, withExtension: "webp"),
          let atlas = NSImage(contentsOf: url) else { return 1 }
    let states = PetState.allCases
    let samples: [(PetState, DragRun?)] = states.map { ($0, nil) } + [(.idle, .right), (.idle, .left)]
    let layout = petLayout(scale: 0.65), gap: CGFloat = 18, label: CGFloat = 22
    let size = NSSize(width: (layout.windowSize.width + gap) * 4 + gap,
                      height: (layout.windowSize.height + label + gap) * CGFloat(samples.count) + gap)
    let board = NSImage(size: size); board.lockFocus()
    NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
    for (row, sample) in samples.enumerated() {
        for (column, index) in [0, 5, 10, 15].enumerated() {
            let view = RettoView(frame: NSRect(origin: .zero, size: layout.windowSize), spriteSheet: atlas,
                                 skin: .christmas, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
            view.petScale = 0.65
            let fixture = "{\"state\":\"\(sample.0.rawValue)\",\"sessionId\":\"preview\",\"projectName\":\"Retto\",\"displayTitle\":\"크리스마스 16프레임\"}".data(using: .utf8)!
            guard let payload = try? JSONDecoder().decode(StatePayload.self, from: fixture) else { continue }
            view.apply(payload, sessionCount: 1, attentionCount: 0, attentionState: nil, isPinned: false)
            view.settleAnimations()
            if let drag = sample.1 { view.setDragRunForPreview(drag) }
            view.setFrameForPreview(index); view.setChristmasTimeForPreview(Double(index) * 0.06)
            let x = gap + CGFloat(column) * (layout.windowSize.width + gap)
            let y = size.height - gap - CGFloat(row + 1) * (layout.windowSize.height + label + gap)
            NSGraphicsContext.saveGraphicsState(); let tr = NSAffineTransform(); tr.translateX(by: x, yBy: y + label); tr.concat()
            view.draw(view.bounds); NSGraphicsContext.restoreGraphicsState()
            let title = "\(sample.1.map { String(describing: $0) } ?? sample.0.rawValue) · \(index + 1)/16"
            (title as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
        }
    }
    board.unlockFocus()
    guard let tiff = board.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return 1 }
    do { try png.write(to: URL(fileURLWithPath: path)) } catch { return 1 }
    return 0
}
