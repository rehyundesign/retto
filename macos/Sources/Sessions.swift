// Claude Code와 Codex 훅이 적어 둔 세션 상태를 읽고 무엇을 먼저 보여줄지 정한다.

import AppKit
import CoreText
import Foundation

@discardableResult
func registerRettoFont() -> Bool {
    if NSFont(name: rettoHandwritingFontName, size: 18) != nil { return true }
    guard let fontURL = Bundle.main.url(forResource: "NanumMiNiSonGeurSsi", withExtension: "ttf") else { return false }
    var registrationError: Unmanaged<CFError>?
    CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError)
    return NSFont(name: rettoHandwritingFontName, size: 18) != nil
}

let allSpacesBehavior: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces,
    .fullScreenAuxiliary,
    .stationary,
    .ignoresCycle
]

enum PetState: String, CaseIterable {
    case idle, running, review, waiting, failed, waving, jumping, sleeping
}

/// 아무 세션도 일하지 않고, 마지막 소식마저 오래된 상태.
///
/// 전부 회색인 채로 이만큼 지나면 레토도 잔다. 깨우는 것은 다음 훅 한 번이다.
let sleepAfter: TimeInterval = 600

func shouldSleep(newestUpdatedAtMs: Double?, nowMs: Double, hasBusySession: Bool) -> Bool {
    guard !hasBusySession, let newestUpdatedAtMs, newestUpdatedAtMs > 0 else { return false }
    return nowMs - newestUpdatedAtMs > sleepAfter * 1000
}

/// 다 끝내 놓고 아무도 보러 오지 않은 채 이만큼 지나면, 기다리다 잠든 모습이 된다.
let dozeAfter: TimeInterval = 1800

/// 위와 다르다. 여기서는 말풍선·이름표·배지를 그대로 두고 그림만 잠든다.
/// 알릴 것이 남아 있으니 지우지 않고, 다만 레토가 기다리다 졸았다는 뜻이다.
func shouldDozeWhileWaiting(newestAttentionAtMs: Double?, nowMs: Double, everythingDone: Bool) -> Bool {
    guard everythingDone, let newestAttentionAtMs, newestAttentionAtMs > 0 else { return false }
    return nowMs - newestAttentionAtMs > dozeAfter * 1000
}

/// Claude Code 확장은 세션 상태를 `idle`·`running`·`waiting_input` 셋으로만 보고하고,
/// 세션 목록 뷰에 `waiting_input` 개수를 배지로 띄운다(활동 바에 파랗게 뜨는 그 숫자).
/// 그 묶음은 권한·질문 대기(`waiting`)뿐 아니라 턴이 끝나 답을 기다리는 상태(`waving`)와
/// 실패(`failed`)까지 포함한다. 그래서 이 셋을 작업 중(`running`·`review`)보다 위에 둔다.
let needsInputStates: Set<PetState> = [.waiting, .failed, .waving]

/// 내가 그 세션에 다녀온 시점이 세션의 마지막 갱신보다 뒤면 "읽음"이다.
/// 읽고 아무것도 하지 않았다면 더 알릴 것이 없으므로 조용한 상태로 내려앉힌다.
/// 그 뒤에 새 소식이 오면 갱신 시각이 앞서므로 다시 알림으로 올라온다.
/// 작업 중이라고 적혀 있는데 오래 소식이 없으면 유령이다. 창이 죽었거나 Stop 훅이 유실된 경우.
/// 손이 필요한 상태(대기·완료·실패)는 아무리 오래돼도 그대로 둔다 — 내가 다녀와야 사라진다.
let staleWorkingTimeout: TimeInterval = 600

func isStaleWorking(state: PetState, updatedAtMs: Double?, nowMs: Double) -> Bool {
    guard state == .running || state == .review || state == .jumping else { return false }
    guard let updatedAtMs, updatedAtMs > 0 else { return false }
    return nowMs - updatedAtMs > staleWorkingTimeout * 1000
}

func isSeen(updatedAtMs: Double?, seenAtMs: Double?) -> Bool {
    guard let seenAtMs else { return false }
    return seenAtMs >= (updatedAtMs ?? 0)
}

/// 트랜스크립트가 마지막으로 자란 시각. 파일을 열지 않으므로 흔적을 남기지 않는다.
func transcriptModifiedAtMs(path: String?) -> Double? {
    guard let path, !path.isEmpty else { return nil }
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return TimeInterval(info.st_mtimespec.tv_sec) * 1000 + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000
}

/// 화면에 그릴 상태. 훅이 준 상태를 두 가지 사정으로 손본다.
///
/// 1. 읽음은 **알림만** 내려놓는다. 예전에는 상태와 무관하게 회색으로 덮어서, 한번 읽음으로
///    표시한 세션이 다시 일을 시작해도 회색으로 남았다.
/// 2. 작업 중인데 오래 소식이 없으면 조용한 상태로 본다. 이때 "소식" 은 훅만이 아니라
///    트랜스크립트가 자란 시각까지 본다 — 훅은 도구를 부를 때만 돌기 때문에, 도구 없이
///    오래 생각하는 동안 살아 있는 세션이 유령으로 몰렸다.
func displayState(state: PetState, updatedAtMs: Double?, seenAtMs: Double?, transcriptModifiedAtMs: Double?, nowMs: Double) -> PetState {
    if state != .waiting, needsInputStates.contains(state), isSeen(updatedAtMs: updatedAtMs, seenAtMs: seenAtMs) { return .idle }
    let lastActivity = max(updatedAtMs ?? 0, transcriptModifiedAtMs ?? 0)
    if isStaleWorking(state: state, updatedAtMs: lastActivity, nowMs: nowMs) { return .idle }
    return state
}

func selectionPriority(state: PetState, isClosed: Bool, source: String? = nil) -> Int {
    if isClosed { return -100 }
    if source == "slack", state == .waving { return 70 }
    switch state {
    // 1순위는 내 답을 기다리는 세션이다. 다른 무엇보다 먼저 보여준다.
    // 실패를 완료보다 먼저 보여준다.
    case .waiting: return 80
    case .waving: return 55
    case .failed: return 75
    case .running: return 40
    case .review: return 35
    case .jumping: return 20
    case .idle: return 10
    // 자는 상태는 세션이 아니라 레토 자신의 모습이다. 고를 대상이 될 일이 없다.
    case .sleeping: return 0
    }
}

/// 고정된 완료 알림보다 우선하는 새 알림은 먼저 표시한다.
func preferredPinnedSession(_ pinned: StatePayload, attention: [StatePayload],
                            priority: (StatePayload) -> Int, needsAttention: (StatePayload) -> Bool) -> StatePayload {
    guard let first = attention.first else { return pinned }
    return !needsAttention(pinned) || priority(first) > priority(pinned) ? first : pinned
}

struct StatePayload: Decodable, Equatable {
    var state: String
    let updatedAt: String?
    let event: String?
    let sessionId: String?
    let rawSessionId: String?
    let source: String?
    let cwd: String?
    let toolName: String?
    let notificationType: String?
    let error: String?
    let projectName: String?
    let displayTitle: String?
    var sessionTitle: String?
    let transcriptPath: String?
    let lastAssistantMessage: String?
    let activeTaskSubject: String?
    let backgroundTaskCount: Int?
    var attention: Bool?
    let closed: Bool?
    var updatedAtMs: Double?
    /// 훅 레지스트리 값인지, Codex 롤아웃에서 보정한 값인지. 파일에는 쓰지 않고 화면 상태에서만 쓴다.
    var stateSource: String?
    /// 훅이 환경변수에서 읽은 클라이언트 — `vscode` · `claude` · `cli`. 클릭했을 때 어느 앱을 띄울지 정한다.
    let client: String?

    var petState: PetState { PetState(rawValue: state) ?? .idle }
    var id: String { sessionId ?? "" }
    /// 레지스트리에서는 제품별 접두어를 붙이지만 딥링크에는 원래 세션 id가 들어간다.
    var navigationSessionId: String { rawSessionId ?? sessionId ?? "" }
    var sourceLabel: String {
        if source == "slack" { return "Slack" }
        return source == "codex" || client == "codex" ? "Codex" : "Claude"
    }
    var project: String {
        if let projectName, !projectName.isEmpty { return projectName }
        if let cwd, !cwd.isEmpty { return URL(fileURLWithPath: cwd).lastPathComponent }
        return sourceLabel == "Codex" ? "Codex" : "Claude Code"
    }
    /// 이름표에는 확인된 세션 제목만 쓴다. 입력 프롬프트와 진행 중 작업은 제목이 아니므로,
    /// 자동 제목이 아직 없을 때는 추측하지 않고 `No name`으로 표시한다.
    var title: String {
        if let sessionTitle, !sessionTitle.isEmpty { return sessionTitle }
        if let activeTaskSubject, !activeTaskSubject.isEmpty { return activeTaskSubject }
        // 훅이 대화 도중에 붙은 세션은 그때 친 짧은 답("B"·"재진행")이 displayTitle 로 굳어
        // 있을 수 있다. 이름표로는 뜻이 없으니 이름 없음으로 내린다. 훅도 같은 기준으로 거른다.
        if let displayTitle, displayTitle.trimmingCharacters(in: .whitespacesAndNewlines).count >= sessionNameMinLength {
            return displayTitle
        }
        // 메뉴 줄은 이름 뒤에 폴더를 따로 붙인다. 여기서 폴더를 또 내면 두 번 뜬다.
        return "No name"
    }
    var needsAttention: Bool { attention == true && closed != true }
    var isClosed: Bool { closed == true }
    /// 내부 Codex 세션과 제목 없는 task는 레토의 표시 대상에서 뺀다.
    var isRettoVisibleTask: Bool {
        guard source == "codex" || client == "codex" else { return true }
        guard sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return false }
        return !isCodexSubagentTranscript(path: transcriptPath ?? "")
    }
}

/// 세션 이름표로 받아들일 최소 길이. hook.cjs 의 NAME_MIN 과 같은 값이어야 한다.
let sessionNameMinLength = 4

private let codexSubagentCache: NSCache<NSString, NSNumber> = {
    let cache = NSCache<NSString, NSNumber>()
    cache.countLimit = 256
    return cache
}()

/// 이전 worker 파일명과 session_meta의 source를 함께 확인한다. Guardian 검토는 일반
/// 파일명으로 저장되므로 제목 대신 출처로 구분해야 같은 제목의 사용자 대화도 유지된다.
func isCodexSubagentTranscript(path: String) -> Bool {
    guard !path.isEmpty else { return false }
    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let pattern = "_[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
    if name.range(of: pattern, options: .regularExpression) != nil { return true }

    var info = stat()
    guard stat(path, &info) == 0 else { return false }
    let key = "\(path):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec)" as NSString
    if let cached = codexSubagentCache.object(forKey: key) { return cached.boolValue }
    guard let handle = FileHandle(forReadingAtPath: path) else { return false }
    defer { try? handle.close() }
    // 기본 지시문이 긴 기록도 읽되 첫 줄만 파싱하고, 전체 대화는 읽지 않는다.
    guard let data = try? handle.read(upToCount: 512 * 1024),
          let record = try? JSONSerialization.jsonObject(with: Data(data.prefix { $0 != 10 })) as? [String: Any],
          record["type"] as? String == "session_meta",
          let metadata = record["payload"] as? [String: Any] else { return false }
    let source = metadata["source"]
    let isSubagent = source as? String == "subagent" || (source as? [String: Any])?["subagent"] != nil
    codexSubagentCache.setObject(NSNumber(value: isSubagent), forKey: key)
    return isSubagent
}

/// 메뉴 막대의 AI 세션 목록과 자동 검사가 같은 문자열을 쓴다. 훅 없이 찾은 Codex task도
/// 일반 세션과 똑같이 한 행으로 보여야 한다.
func sessionMenuLabel(for payload: StatePayload) -> String {
    if payload.source == "slack" { return "● 새 메시지  \(payload.title) · Slack" }
    let stateMark: String
    switch payload.petState {
    case .waiting: stateMark = "● 기다림"
    case .failed: stateMark = "● 실패"
    case .running, .review: stateMark = "● 작업 중"
    case .waving: stateMark = "● 완료"
    default: stateMark = "○ 쉬는 중"
    }
    let origin: String
    switch payload.client {
    case "vscode": origin = " · VS Code"
    case "claude": origin = " · Claude 앱"
    case "cli": origin = " · Claude Code CLI"
    case "codex": origin = " · Codex"
    default: origin = payload.sourceLabel == "Codex" ? " · Codex" : ""
    }
    return "\(stateMark)  \(String(payload.title.prefix(42))) · \(payload.project)\(origin)"
}

enum TaskStateSource: String {
    case hook
    case rollout
    case live
}

/// Retto가 화면에 쓰는 Codex task 상태. 훅은 즉시성, 롤아웃은 완료 사실, 인덱스는 제목을 맡는다.
/// 어느 원천이 마지막 상태를 확인했는지도 함께 남겨 오래된 훅 값과 구분한다.
struct ReconciledCodexTask {
    let state: PetState
    let observedAtMs: Double?
    let needsAttention: Bool
    let title: String?
    let source: TaskStateSource
}

func reconcileCodexTask(payload: StatePayload, indexTitle: String?, transcriptStatus: CodexTranscriptStatus) -> ReconciledCodexTask {
    let title = indexTitle?.isEmpty == false ? indexTitle : payload.sessionTitle
    if let requestedAt = transcriptStatus.pendingInputAtMs {
        return ReconciledCodexTask(state: .waiting, observedAtMs: requestedAt,
                                   needsAttention: true, title: title, source: .rollout)
    }
    if let abortedAt = transcriptStatus.latestAbortAtMs,
       abortedAt >= (payload.updatedAtMs ?? 0),
       abortedAt >= (transcriptStatus.latestPromptAtMs ?? 0),
       abortedAt >= (transcriptStatus.latestComposerStartAtMs ?? 0),
       abortedAt >= (transcriptStatus.completedAtMs ?? 0) {
        return ReconciledCodexTask(state: .idle, observedAtMs: abortedAt,
                                   needsAttention: false, title: title, source: .rollout)
    }
    if payload.petState == .waiting,
       let startedAt = transcriptStatus.latestComposerStartAtMs,
       startedAt > (payload.updatedAtMs ?? 0) {
        return ReconciledCodexTask(state: transcriptStatus.isCompletedAfterLatestPrompt ? .waving : .running,
                                   observedAtMs: max(startedAt, transcriptStatus.completedAtMs ?? 0),
                                   needsAttention: transcriptStatus.isCompletedAfterLatestPrompt,
                                   title: title, source: .rollout)
    }
    // 비동기 질문은 답변 뒤에도 훅의 waiting 값이 남을 수 있다.
    if payload.petState == .waiting,
       let answeredAt = transcriptStatus.latestInputReplyAtMs,
       answeredAt >= (payload.updatedAtMs ?? 0) {
        return ReconciledCodexTask(state: transcriptStatus.isCompletedAfterLatestPrompt ? .waving : .running,
                                   observedAtMs: max(answeredAt, transcriptStatus.completedAtMs ?? 0),
                                   needsAttention: transcriptStatus.isCompletedAfterLatestPrompt,
                                   title: title, source: .rollout)
    }
    // 질문 대기는 위에서 유지한다. 권한 훅 이후 턴이 끝났다면 권한 대기도 끝난 상태다.
    let completedAttention = (payload.petState == .waiting || payload.petState == .failed)
        && (transcriptStatus.completedAtMs ?? 0) >= (payload.updatedAtMs ?? 0)
    guard (payload.petState == .running || payload.petState == .review || completedAttention),
          transcriptStatus.isCompletedAfterLatestPrompt,
          let completedAtMs = transcriptStatus.completedAtMs else {
        return ReconciledCodexTask(
            state: payload.petState,
            observedAtMs: payload.updatedAtMs,
            needsAttention: payload.needsAttention,
            title: title,
            source: .hook
        )
    }
    return ReconciledCodexTask(
        state: .waving,
        observedAtMs: completedAtMs,
        needsAttention: true,
        title: title,
        source: .rollout
    )
}

/// Codex는 제목을 롤아웃이 아니라 별도 인덱스에 쓴다. 같은 task가 완료된 뒤에도
/// 훅이 다시 오지 않을 수 있으므로, 앱이 인덱스가 바뀔 때 최신 제목을 다시 읽는다.
func codexThreadTitles(in text: String) -> [String: String] {
    var titles: [String: String] = [:]
    for line in text.split(separator: "\n") {
        guard let data = line.data(using: .utf8),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = record["id"] as? String,
              let title = record["thread_name"] as? String,
              !title.isEmpty else { continue }
        titles[id] = String(title.prefix(80))
    }
    return titles
}

final class CodexThreadTitleReader {
    private let indexURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/session_index.jsonl")
    private var cachedModified = Date.distantPast
    private var cachedSize: UInt64 = 0
    private var titles: [String: String] = [:]

    func title(for threadId: String) -> String? {
        refresh()
        return titles[threadId]
    }

    func allTitles() -> [String: String] {
        refresh()
        return titles
    }

    private func refresh() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: indexURL.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber else { return }
        let bytes = size.uint64Value
        guard modified != cachedModified || bytes != cachedSize else { return }
        guard let text = try? String(contentsOf: indexURL, encoding: .utf8) else { return }
        cachedModified = modified
        cachedSize = bytes
        titles = codexThreadTitles(in: text)
    }
}

/// `task_complete`와 사용자 요청의 순서가 훅 콜백의 실행 시각보다 신뢰할 만하다.
/// 비동기 콜백이 늦게 상태 파일을 덮어써도, 완료 뒤에 새 요청이 있으면 완료로 보지 않는다.
struct CodexTranscriptStatus: Codable {
    let completedAtMs: Double?
    let latestPromptAtMs: Double?
    // 질문 본문은 저장하지 않고 질문 ID와 시각만 기록한다.
    var inputRequests: [String: Double]? = nil
    var inputReplies: [String: Double]? = nil
    var inputRequestTurns: [String: String]? = nil
    var synchronousRequests: [String: Double]? = nil
    var toolOutputs: [String: Double]? = nil
    var abortedTurns: [String: Double]? = nil
    var latestAbortAtMs: Double? = nil
    var composerTurns: [String: Double]? = nil

    var latestComposerStartAtMs: Double? { composerTurns?.values.max() }

    var pendingInputAtMs: Double? {
        (inputRequests ?? [:]).filter { id, requestedAt in
            if (inputReplies?[id] ?? 0) >= requestedAt { return false }
            // 새 사용자 요청은 이전 턴의 질문을 대체한다. 같은 턴의 답변·도구 실행이나
            // 자동 재개는 질문을 해제하지 않는다.
            if (composerTurns ?? [:]).contains(where: { turn, startedAt in
                turn != inputRequestTurns?[id] && startedAt > requestedAt
            }) { return false }
            let callId = String(id.split(separator: ":").dropLast().joined(separator: ":"))
            if synchronousRequests?[callId] != nil, (toolOutputs?[callId] ?? 0) >= requestedAt { return false }
            if let turn = inputRequestTurns?[id] {
                return (abortedTurns?[turn] ?? 0) < requestedAt
            }
            // 과거 기록에 턴 ID가 없으면 이후 중단 시각으로 해제한다.
            return (latestAbortAtMs ?? 0) < requestedAt
        }.values.max()
    }

    var latestInputReplyAtMs: Double? {
        let latest = max(inputReplies?.values.max() ?? 0, toolOutputs?.filter { synchronousRequests?[$0.key] != nil }.values.max() ?? 0)
        return latest > 0 ? latest : nil
    }

    var isCompletedAfterLatestPrompt: Bool {
        guard pendingInputAtMs == nil, let completedAtMs else { return false }
        return completedAtMs > max(latestPromptAtMs ?? 0, latestAbortAtMs ?? 0, latestComposerStartAtMs ?? 0)
    }

    func merged(with newer: CodexTranscriptStatus) -> CodexTranscriptStatus {
        CodexTranscriptStatus(
            completedAtMs: max(completedAtMs ?? 0, newer.completedAtMs ?? 0),
            latestPromptAtMs: max(latestPromptAtMs ?? 0, newer.latestPromptAtMs ?? 0),
            inputRequests: (inputRequests ?? [:]).merging(newer.inputRequests ?? [:], uniquingKeysWith: max),
            inputReplies: (inputReplies ?? [:]).merging(newer.inputReplies ?? [:], uniquingKeysWith: max),
            inputRequestTurns: (inputRequestTurns ?? [:]).merging(newer.inputRequestTurns ?? [:], uniquingKeysWith: { _, new in new }),
            synchronousRequests: (synchronousRequests ?? [:]).merging(newer.synchronousRequests ?? [:], uniquingKeysWith: max),
            toolOutputs: (toolOutputs ?? [:]).merging(newer.toolOutputs ?? [:], uniquingKeysWith: max),
            abortedTurns: (abortedTurns ?? [:]).merging(newer.abortedTurns ?? [:], uniquingKeysWith: max),
            latestAbortAtMs: max(latestAbortAtMs ?? 0, newer.latestAbortAtMs ?? 0),
            composerTurns: (composerTurns ?? [:]).merging(newer.composerTurns ?? [:], uniquingKeysWith: max)
        )
    }
}

func codexTranscriptStatus(in text: String) -> CodexTranscriptStatus {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plainFormatter = ISO8601DateFormatter()
    plainFormatter.formatOptions = [.withInternetDateTime]
    var completion: Double?
    var latestPrompt: Double?
    var requests: [String: Double] = [:]
    var replies: [String: Double] = [:]
    var requestTurns: [String: String] = [:]
    var syncRequests: [String: Double] = [:]
    var outputs: [String: Double] = [:]
    var aborted: [String: Double] = [:]
    var latestAbort: Double?
    var activeTurn: String?
    var composerTurns: [String: Double] = [:]
    for line in text.split(separator: "\n") {
        guard let data = line.data(using: .utf8),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = record["payload"] as? [String: Any],
              let timestamp = record["timestamp"] as? String,
              let date = fractionalFormatter.date(from: timestamp) ?? plainFormatter.date(from: timestamp) else { continue }
        let timestampMs = date.timeIntervalSince1970 * 1000
        if record["type"] as? String == "event_msg" {
            if payload["type"] as? String == "task_started" {
                let attribution = payload["turn_attribution"] as? [String: Any]
                activeTurn = attribution?["turn_id"] as? String ?? payload["turn_id"] as? String
                if attribution?["turn_trigger"] as? String == "composer", let turn = activeTurn {
                    composerTurns[turn] = max(composerTurns[turn] ?? 0, timestampMs)
                }
            }
            if payload["type"] as? String == "turn_aborted" {
                latestAbort = max(latestAbort ?? 0, timestampMs)
                if let turn = payload["turn_id"] as? String ?? activeTurn { aborted[turn] = timestampMs }
            }
        }
        if record["type"] as? String == "response_item",
           ["function_call_output", "custom_tool_call_output"].contains(payload["type"] as? String ?? ""),
           let callId = payload["call_id"] as? String { outputs[callId] = timestampMs }
        if record["type"] as? String == "event_msg", payload["type"] as? String == "task_complete" {
            completion = max(completion ?? 0, timestampMs)
        }
        if record["type"] as? String == "response_item",
           payload["type"] as? String == "function_call",
           let name = (payload["name"] as? String)?.split(separator: ".").last,
           ["request_user_input_async", "request_user_input"].contains(String(name)),
           let callId = payload["call_id"] as? String,
           let arguments = payload["arguments"] as? String,
           let argumentData = arguments.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: argumentData) as? [String: Any],
           let questions = object["questions"] as? [Any] {
            let turn = (payload["internal_chat_message_metadata_passthrough"] as? [String: Any])?["turn_id"] as? String
                ?? (record["metadata"] as? [String: Any])?["turn_id"] as? String ?? activeTurn
            for index in questions.indices {
                let id = "\(callId):\(index)"
                requests[id] = timestampMs
                requestTurns[id] = turn
            }
            if name == "request_user_input" { syncRequests[callId] = timestampMs }
        }
        if record["type"] as? String == "response_item",
           payload["type"] as? String == "message",
           payload["role"] as? String == "user" {
            latestPrompt = max(latestPrompt ?? 0, timestampMs)
            for part in payload["content"] as? [[String: Any]] ?? [] {
                guard let body = part["text"] as? String,
                      let start = body.range(of: "<send_user_message_question_reply>"),
                      let end = body.range(of: "</send_user_message_question_reply>", range: start.upperBound..<body.endIndex),
                      let data = String(body[start.upperBound..<end.lowerBound]).data(using: .utf8),
                      let answers = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
                for answer in answers {
                    guard let encoded = answer["questionItemId"] as? String,
                          let idData = encoded.data(using: .utf8),
                          let id = try? JSONSerialization.jsonObject(with: idData) as? [Any],
                          id.count == 3, let name = id[0] as? String,
                          ["request_user_input_async", "request_user_input"].contains(String(name.split(separator: ".").last ?? "")),
                          let callId = id[1] as? String, let index = id[2] as? Int else { continue }
                    replies["\(callId):\(index)"] = timestampMs
                }
            }
        }
    }
    return CodexTranscriptStatus(completedAtMs: completion, latestPromptAtMs: latestPrompt,
                                 inputRequests: requests, inputReplies: replies,
                                 inputRequestTurns: requestTurns, synchronousRequests: syncRequests,
                                 toolOutputs: outputs, abortedTurns: aborted, latestAbortAtMs: latestAbort,
                                 composerTurns: composerTurns)
}

func codexTaskCompletionAtMs(in text: String) -> Double? {
    codexTranscriptStatus(in: text).completedAtMs
}

struct SessionRegistry: Decodable {
    let sessions: [String: StatePayload]
}

// 상태 색은 뜻 단위로 넷만 쓴다. 배경과 글자를 한 쌍으로 묶어 사용자가 지정한 값을 그대로 쓴다.
//   초록 = 진행 중 · 파랑 = 내 답을 기다림 · 주황 = 완료 · 빨강 = 문제

/// 창 제목이 이 세션을 보고 있다는 뜻인가.
///
/// VS Code 창 제목은 "세션 이름 — 폴더" 꼴이다(예: "백오피스 기획 — planning").
/// 그래서 세션 이름이나 폴더 이름이 제목에 있으면 그 세션을 열어 놓고 있다고 본다.
/// 제목을 읽을 수 없는 환경(화면 기록 권한이 없을 때)에서는 빈 문자열이 오므로 아무 일도 하지 않는다.
func windowShowsSession(windowTitle: String, sessionTitle: String?, folderName: String?) -> Bool {
    let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, let sessionTitle, sessionTitle.count >= 2,
          sessionTitle != "No name", sessionTitle != folderName else { return false }
    if title == sessionTitle { return true }
    return [" — ", " - ", " | "].contains { separator in
        title.hasPrefix(sessionTitle + separator) || title.hasSuffix(separator + sessionTitle)
    }
}

/// 그 창을 이만큼 보고 있어야 "읽었다" 로 센다. 스쳐 지나간 것과 구분한다.
let lookingDwell: TimeInterval = 3

/// 앱 안에서 다른 대화로 이동하거나 새 알림이 오면 확인 시간을 다시 센다.
struct SessionReadDwell {
    private var key: String?
    private var sinceMs: Double?

    mutating func observe(key nextKey: String?, nowMs: Double) -> Bool {
        guard let nextKey else { key = nil; sinceMs = nil; return false }
        if key != nextKey { key = nextKey; sinceMs = nowMs; return false }
        return sinceMs.map { nowMs - $0 >= lookingDwell * 1000 } ?? false
    }
}

/// 앱이 지켜보기 시작하기 한참 전에 끝난 일인지.
///
/// 첫 설치·재시작·읽음 기록 유실 뒤에는 레지스트리에 남은 이레치 완료 세션이 한꺼번에
/// 배지로 몰려온다. 오래전에 끝난 일을 지금 처음 본 것처럼 알리면, 이미 확인한 답을
/// 다시 확인하러 가게 만든다. 30분 여유를 둬서 앱이 잠깐 꺼졌다 켜진 사이에 끝난
/// 일은 그대로 알린다.
let trackingGrace: TimeInterval = 1800

func isAncientNews(updatedAtMs: Double?, trackingStartedAtMs: Double) -> Bool {
    guard let updatedAtMs, updatedAtMs > 0 else { return false }
    return updatedAtMs < trackingStartedAtMs - trackingGrace * 1000
}

/// 완료된 세션을 사용자가 레토 밖에서 열어 읽었는지.
///
/// 두 클라이언트는 같은 말을 다른 모양으로 적는다. 훅의 `assistantTextIn` 과 같은 규칙이다.
///   Claude : {"type":"assistant","message":{"content":[{"type":"text","text":…}]}}
///   Codex  : {"type":"response_item","payload":{"type":"message","role":"assistant",
///                                               "content":[{"type":"output_text","text":…}]}}
func assistantText(in record: [String: Any]) -> String {
    let message: [String: Any]?
    if record["type"] as? String == "assistant" {
        message = record["message"] as? [String: Any]
    } else if record["type"] as? String == "response_item",
              let payload = record["payload"] as? [String: Any],
              payload["type"] as? String == "message",
              payload["role"] as? String == "assistant" {
        message = payload
    } else {
        message = nil
    }
    guard let content = message?["content"] as? [[String: Any]] else { return "" }
    return content
        .filter { $0["type"] as? String == "text" || $0["type"] as? String == "output_text" }
        .compactMap { $0["text"] as? String }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 트랜스크립트에서 Claude 가 가장 최근에 쓴 문장을 집는다.
///
/// 훅도 같은 일을 하지만 훅은 도구를 부를 때만 돈다. 도구 없이 긴 글을 쓰는 동안에는
/// 말풍선이 멈춰 있으므로, 앱이 표시 중인 세션의 파일만 직접 들여다본다.
/// 파일이 커도 끝 512KB 만 읽고, 크기·수정 시각이 그대로면 다시 읽지 않는다.
final class TranscriptReader {
    private var cachedPath = ""
    private var cachedSize: UInt64 = 0
    private var cachedModified = Date.distantPast
    private var cachedText = ""
    private var cachedTitle = ""

    func latestAssistantText(at path: String?) -> String? {
        refresh(at: path)
        return cachedText.isEmpty ? nil : cachedText
    }

    /// 세션 이름. 사용자가 붙인 이름이 있으면 그게 우선, 없으면 Claude 가 붙인 이름.
    /// 훅도 같은 값을 적지만 훅은 도구 호출 때만 돈다. 쉬는 세션의 이름을 바꾸면
    /// 다음 도구 호출까지 옛 이름이 남아 있었다.
    func latestTitle(at path: String?) -> String? {
        refresh(at: path)
        return cachedTitle.isEmpty ? nil : cachedTitle
    }

    /// 파일이 그대로면 다시 읽지 않는다. 0.25초마다 불리므로 stat 만 보고 넘긴다.
    ///
    /// 읽고 나면 접근 시각(atime)을 원래대로 되돌린다. 레토는 "누가 이 세션을 열어 읽었나" 를
    /// atime 으로 판단하는데, 우리가 읽은 흔적을 남기면 자기가 자기를 읽음 처리해 버린다.
    private func refresh(at path: String?) {
        guard let path, !path.isEmpty else {
            cachedPath = ""; cachedText = ""; cachedTitle = ""
            return
        }
        var info = stat()
        guard stat(path, &info) == 0 else {
            cachedPath = ""; cachedText = ""; cachedTitle = ""
            return
        }
        let size = UInt64(info.st_size)
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        if path == cachedPath, size == cachedSize, modified == cachedModified { return }

        let before = info.st_atimespec
        let parsed = Self.readTail(path: path, size: size)
        var times = [before, info.st_mtimespec]
        _ = utimensat(AT_FDCWD, path, &times, 0)

        cachedPath = path
        cachedSize = size
        cachedModified = modified
        cachedText = parsed.message
        cachedTitle = parsed.title
    }

    private static func readTail(path: String, size: UInt64) -> (message: String, title: String) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return ("", "") }
        defer { try? handle.close() }
        let span: UInt64 = 512 * 1024
        if size > span {
            try? handle.seek(toOffset: size - span)
        }
        guard let data = try? handle.readToEnd(),
              let chunk = String(data: data, encoding: .utf8) else { return ("", "") }

        var message = ""
        var customTitle: String?
        var aiTitle = ""
        // 뒤에서부터 훑는다. 문장과 이름 둘 다 가장 최근 것이 먼저 나온다.
        for line in chunk.split(separator: "\n").reversed() {
            if message.isEmpty, line.contains("\"assistant\"") {
                if let lineData = line.data(using: .utf8),
                   let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    let text = assistantText(in: record)
                    if !text.isEmpty { message = String(text.prefix(400)) }
                }
            }
            if customTitle == nil || aiTitle.isEmpty, line.contains("-title") {
                if let lineData = line.data(using: .utf8),
                   let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                    // 사용자가 이름을 지우면 빈 custom-title 이 적힌다. 그 경우도 최신 뜻으로 받아야 한다.
                    if customTitle == nil, record["type"] as? String == "custom-title" {
                        customTitle = (record["customTitle"] as? String) ?? ""
                    }
                    if aiTitle.isEmpty, record["type"] as? String == "ai-title" {
                        aiTitle = (record["aiTitle"] as? String) ?? ""
                    }
                }
            }
            if !message.isEmpty, customTitle != nil, !aiTitle.isEmpty { break }
        }
        let title = (customTitle?.isEmpty == false ? customTitle! : aiTitle)
        return (message, String(title.prefix(80)))
    }
}

/// 완료 상태를 확인할 때는 화면에 선택된 한 세션만 쓰는 `TranscriptReader` 캐시와 분리한다.
/// 각 Codex 롤아웃의 크기·나노초 단위 수정 시각을 보관해, 세션이 여러 개여도 바뀐 파일만 다시 읽는다.
final class CodexTranscriptStatusReader {
    private struct CachedStatus {
        let size: UInt64
        let modifiedAtMs: Double
        let status: CodexTranscriptStatus
    }

    private var cache: [String: CachedStatus] = [:]
    private let lifecycleIndex = CodexLifecycleIndex()
    private(set) var unreadablePaths: Set<String> = []
    private var trackedPaths: Set<String> = []
    var connectionIssue: String? {
        let count = unreadablePaths.intersection(trackedPaths).count
        return count == 0 ? nil : "Codex 기록 읽기 실패 \(count)개"
    }
    func retainTrackedPaths(_ paths: Set<String>) {
        trackedPaths = paths
        unreadablePaths.formIntersection(paths)
    }

    func status(at path: String?) -> CodexTranscriptStatus {
        guard let path, !path.isEmpty else {
            return CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
        }
        var info = stat()
        guard stat(path, &info) == 0 else {
            unreadablePaths.insert(path)
            return cache[path]?.status ?? CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            unreadablePaths.insert(path)
            return cache[path]?.status ?? CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
        }
        unreadablePaths.remove(path)
        let size = UInt64(info.st_size)
        let modifiedAtMs = TimeInterval(info.st_mtimespec.tv_sec) * 1000
            + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000
        if let indexed = lifecycleIndex.status(path: path, size: size, modifiedAtMs: modifiedAtMs) {
            cache[path] = CachedStatus(size: size, modifiedAtMs: modifiedAtMs, status: indexed)
            return indexed
        }
        if let cached = cache[path], cached.size == size, cached.modifiedAtMs == modifiedAtMs {
            return cached.status
        }

        let before = info.st_atimespec
        guard let tailStatus = Self.readStatusTail(path: path, size: size) else {
            unreadablePaths.insert(path)
            return cache[path]?.status ?? CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
        }
        let status = cache[path]?.status.merged(with: tailStatus) ?? tailStatus
        var times = [before, info.st_mtimespec]
        _ = utimensat(AT_FDCWD, path, &times, 0)
        cache[path] = CachedStatus(size: size, modifiedAtMs: modifiedAtMs, status: status)
        lifecycleIndex.refresh(path: path, size: size, modifiedAtMs: modifiedAtMs, fallback: status)
        return status
    }

    private static func readStatusTail(path: String, size: UInt64) -> CodexTranscriptStatus? {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return nil
        }
        defer { try? handle.close() }
        let span: UInt64 = 512 * 1024
        if size > span { try? handle.seek(toOffset: size - span) }
        guard let data = try? handle.readToEnd() else { return nil }
        return codexTranscriptStatus(in: codexTranscriptText(data, skipPartialFirstLine: size > span))
    }
}

/// 파일 끝 일부에 없는 종료 이벤트도 잃지 않도록, 작업별 lifecycle을 로컬에 보관한다.
/// 첫 색인은 백그라운드에서 읽고 이후에는 마지막 64KB를 겹쳐 새로 추가된 JSONL만 반영한다.
final class CodexLifecycleIndex {
    private struct Entry: Codable {
        let size: UInt64
        let modifiedAtMs: Double
        let status: CodexTranscriptStatus
    }
    private struct Store: Codable { var entries: [String: Entry] }

    private let storeURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/retto-pet/codex-lifecycle-input-v4.json")
    private let stateQueue = DispatchQueue(label: "retto.codex-lifecycle.state")
    private let scanQueue = DispatchQueue(label: "retto.codex-lifecycle.scan")
    private var entries: [String: Entry]
    private var pending: Set<String> = []

    init() {
        let stored = (try? Data(contentsOf: storeURL))
            .flatMap { try? JSONDecoder().decode(Store.self, from: $0) }
        entries = stored?.entries ?? [:]
    }

    func status(path: String, size: UInt64, modifiedAtMs: Double) -> CodexTranscriptStatus? {
        stateQueue.sync {
            guard let entry = entries[path], entry.size == size, entry.modifiedAtMs == modifiedAtMs else { return nil }
            return entry.status
        }
    }

    func refresh(path: String, size: UInt64, modifiedAtMs: Double, fallback: CodexTranscriptStatus) {
        let request = stateQueue.sync { () -> (accepted: Bool, previous: Entry?) in
            if pending.contains(path) { return (false, nil) }
            pending.insert(path)
            return (true, entries[path])
        }
        guard request.accepted else { return }
        scanQueue.async { [weak self] in
            guard let self else { return }
            let scanned = Self.scan(path: path, from: request.previous?.size, previous: request.previous?.status ?? fallback)
            self.stateQueue.sync {
                self.entries[path] = Entry(size: size, modifiedAtMs: modifiedAtMs, status: scanned)
                self.pending.remove(path)
                self.save()
            }
        }
    }

    private static func scan(path: String, from previousSize: UInt64?, previous: CodexTranscriptStatus) -> CodexTranscriptStatus {
        var before = stat()
        let hadStat = stat(path, &before) == 0
        guard let handle = FileHandle(forReadingAtPath: path) else { return previous }
        defer {
            if hadStat {
                var after = stat()
                if fstat(handle.fileDescriptor, &after) == 0 {
                    var times = [before.st_atimespec, after.st_mtimespec]
                    _ = futimens(handle.fileDescriptor, &times)
                }
            }
            try? handle.close()
        }
        let overlap: UInt64 = 64 * 1024
        let offset = (previousSize ?? 0) > overlap ? (previousSize ?? 0) - overlap : 0
        if offset > 0 { try? handle.seek(toOffset: offset) }
        guard let data = try? handle.readToEnd() else { return previous }
        return previous.merged(with: codexTranscriptStatus(in: codexTranscriptText(data, skipPartialFirstLine: offset > 0)))
    }

    private func save() {
        let directory = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Store(entries: entries)) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

/// 훅이 꺼져 있어도 Codex가 남긴 최근 롤아웃에서 task를 찾는다. 훅은 권한 대기·도구 실패처럼
/// 즉시 알려야 하는 상태를 보강하고, 이 경로는 task 발견·완료 확인을 맡는다.
final class CodexRolloutDiscovery {
    private let sessionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions")
    private let titles = CodexThreadTitleReader()
    private let recentWindow: TimeInterval = 24 * 60 * 60
    private(set) var diagnostic = ""
    private(set) var connectionIssue: String?
    private struct CachedTask {
        let size: UInt64
        let modified: Date
        let payload: StatePayload
    }
    private var taskCache: [String: CachedTask] = [:]

    func recentTasks(now: Date = Date()) -> [StatePayload] {
        let knownTitles = titles.allTitles()
        var tasks: [String: StatePayload] = [:]
        let paths: [String]
        do { paths = try FileManager.default.subpathsOfDirectory(atPath: sessionsURL.path) }
        catch {
            diagnostic = "\(sessionsURL.path): \(error.localizedDescription)"
            connectionIssue = "Codex 작업 목록 읽기 실패"
            return []
        }
        connectionIssue = nil
        diagnostic = "\(sessionsURL.path): \(paths.count) entries"
        for relative in paths where relative.hasSuffix(".jsonl") {
            let url = sessionsURL.appendingPathComponent(relative)
            // 하위 에이전트는 상위 작업과 동일한 ID를 기록한다. 이 파일을 읽으면 최신
            // 수정 시각 때문에 상위 대화가 worker 실행 내역으로 바뀐다.
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) <= recentWindow,
                  !isCodexSubagentTranscript(path: url.path),
                  let task = task(at: url, modifiedAt: modified, titles: knownTitles) else { continue }
            if let old = tasks[task.id], (old.updatedAtMs ?? 0) >= (task.updatedAtMs ?? 0) { continue }
            tasks[task.id] = task
        }
        return tasks.values.sorted { ($0.updatedAtMs ?? 0) > ($1.updatedAtMs ?? 0) }
    }

    static func validateTaskCache() -> Bool {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("retto-cache-test-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:folder) }
            let url = folder.appendingPathComponent("fixture.jsonl")
            func write(_ cwd: String) throws {
                let data = try JSONSerialization.data(withJSONObject:["type":"session_meta","payload":["id":"cache-test","cwd":cwd]])
                try data.write(to:url)
            }
            try write("/tmp/a")
            let reader = CodexRolloutDiscovery(), first = Date(timeIntervalSince1970:100)
            guard let a = reader.task(at:url,modifiedAt:first,titles:["cache-test":"first"]), a.cwd == "/tmp/a" else { return false }
            guard reader.task(at:url,modifiedAt:first,titles:["cache-test":"first"])?.sessionTitle == "first" else { return false }
            guard reader.task(at:url,modifiedAt:first,titles:["cache-test":"renamed"])?.sessionTitle == "renamed" else { return false }
            try write("/tmp/b")
            guard reader.task(at:url,modifiedAt:first.addingTimeInterval(1),titles:["cache-test":"renamed"])?.cwd == "/tmp/b" else { return false }
            try write("/tmp/a-longer-path")
            guard reader.task(at:url,modifiedAt:first.addingTimeInterval(1),titles:["cache-test":"renamed"])?.cwd == "/tmp/a-longer-path" else { return false }
            try FileManager.default.removeItem(at:url)
            return reader.task(at:url,modifiedAt:first,titles:["cache-test":"first"]) == nil
        } catch { return false }
    }

    private func task(at url: URL, modifiedAt: Date, titles: [String: String]) -> StatePayload? {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
        if let cached = taskCache[url.path], cached.size == fileSize, cached.modified == modifiedAt,
           let id = cached.payload.rawSessionId, cached.payload.sessionTitle == titles[id] {
            return cached.payload
        }
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }
        // session_meta 첫 줄에는 기본 지시문이 함께 들어가 16KB를 넘는다. 중간에서 끊어 JSON
        // 파싱이 실패하면 task ID를 하나도 찾지 못하므로, 첫 줄 전체가 들어올 범위를 읽는다.
        let metadataData = try? handle.read(upToCount: 512 * 1024)
        guard let metadataData,
              let metadata = String(data: metadataData, encoding: .utf8),
              let firstLine = metadata.split(separator: "\n").first,
              let data = firstLine.data(using: .utf8),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = record["payload"] as? [String: Any],
              let threadId = (payload["id"] as? String) ?? (payload["session_id"] as? String),
              !threadId.isEmpty,
              let title = titles[threadId], !title.isEmpty else { return nil }

        // 앞에서 session_meta를 읽었으므로 작은 파일도 반드시 처음으로 되돌린다. 안 그러면
        // 첫 16KB 안의 마지막 사용자 요청을 놓쳐, 오래된 완료를 새 요청의 완료로 오해한다.
        try? handle.seek(toOffset: fileSize > 512 * 1024 ? fileSize - 512 * 1024 : 0)
        let tail = (try? handle.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let transcript = codexTranscriptStatus(in: tail)
        let updatedAtMs = max(
            transcript.completedAtMs ?? 0,
            transcript.latestPromptAtMs ?? 0,
            modifiedAt.timeIntervalSince1970 * 1000
        )
        let completed = transcript.isCompletedAfterLatestPrompt
        let cwd = payload["cwd"] as? String
        let result = StatePayload(
            state: completed ? PetState.waving.rawValue : PetState.running.rawValue,
            updatedAt: nil,
            event: completed ? "task_complete" : "rollout",
            sessionId: "codex:\(threadId)",
            rawSessionId: threadId,
            source: "codex",
            cwd: cwd,
            toolName: nil,
            notificationType: nil,
            error: nil,
            projectName: nil,
            displayTitle: nil,
            sessionTitle: title,
            transcriptPath: url.path,
            lastAssistantMessage: nil,
            activeTaskSubject: nil,
            backgroundTaskCount: nil,
            attention: completed,
            closed: false,
            updatedAtMs: updatedAtMs,
            stateSource: TaskStateSource.rollout.rawValue,
            client: "codex"
        )
        if taskCache.count >= 512 { taskCache.removeAll(keepingCapacity: true) }
        taskCache[url.path] = CachedTask(size: fileSize, modified: modifiedAt, payload: result)
        return result
    }
}

/// 화면이 접근성 트리에 task 목록을 내보내지 않는 환경에서도, 같은 발견 결과를 검증하는
/// 읽기 전용 진단 출력이다. `Retto --codex-rollouts-json`은 파일을 고치지 않는다.
func codexRolloutReport() -> String {
    let discovery = CodexRolloutDiscovery()
    let tasks = discovery.recentTasks().map { task in
        [
            "id": task.id,
            "navigationId": task.navigationSessionId,
            "title": task.title,
            "state": task.state,
            "source": task.stateSource ?? "rollout"
        ]
    }
    let report: [String: Any] = ["home": FileManager.default.homeDirectoryForCurrentUser.path, "diagnostic": discovery.diagnostic, "tasks": tasks]
    guard JSONSerialization.isValidJSONObject(report),
          let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { return "[]" }
    return text
}

/// 입력 대기는 읽음 처리 대상에서 제외하고 별도 배지로 먼저 표시한다.
func attentionBadgeSessions(_ sessions: [StatePayload], needsAttention: (StatePayload) -> Bool) -> [StatePayload] {
    let unread = sessions.filter { !$0.isClosed && needsAttention($0) }
    let input = unread.filter { $0.petState == .waiting }
    return input.isEmpty ? unread.filter { $0.petState == .waving || $0.petState == .failed } : input
}

func attentionSummary(_ sessions: [StatePayload]) -> String {
    let input = sessions.filter { $0.petState == .waiting }.count
    return input > 0 ? "입력 필요 \(input)개" : "새 알림 \(sessions.count)개"
}

/// 바이트 단위로 읽은 범위가 한글 문자 중간에서 시작해도 이후 JSONL 기록은 파싱한다.
func codexTranscriptText(_ data: Data, skipPartialFirstLine: Bool) -> String {
    if skipPartialFirstLine {
        guard let newline = data.firstIndex(of: 10) else { return "" }
        return String(decoding: data[data.index(after: newline)...], as: UTF8.self)
    }
    return String(decoding: data, as: UTF8.self)
}
