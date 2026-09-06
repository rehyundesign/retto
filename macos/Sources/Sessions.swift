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
    if needsInputStates.contains(state), isSeen(updatedAtMs: updatedAtMs, seenAtMs: seenAtMs) { return .idle }
    let lastActivity = max(updatedAtMs ?? 0, transcriptModifiedAtMs ?? 0)
    if isStaleWorking(state: state, updatedAtMs: lastActivity, nowMs: nowMs) { return .idle }
    return state
}

func selectionPriority(state: PetState, isClosed: Bool) -> Int {
    if isClosed { return -100 }
    switch state {
    // 1순위는 내 답을 기다리는 세션이다. 다른 무엇보다 먼저 보여준다.
    // 2순위는 답변이 끝난 세션. 내가 찾아 나서기 전에 레토가 먼저 알려줘야 하는 것이다.
    case .waiting: return 60
    case .waving: return 55
    case .failed: return 50
    case .running: return 40
    case .review: return 35
    case .jumping: return 20
    case .idle: return 10
    // 자는 상태는 세션이 아니라 레토 자신의 모습이다. 고를 대상이 될 일이 없다.
    case .sleeping: return 0
    }
}

struct StatePayload: Decodable {
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
    var sourceLabel: String { source == "codex" || client == "codex" ? "Codex" : "Claude" }
    var project: String {
        if let projectName, !projectName.isEmpty { return projectName }
        if let cwd, !cwd.isEmpty { return URL(fileURLWithPath: cwd).lastPathComponent }
        return sourceLabel == "Codex" ? "Codex" : "Claude Code"
    }
    /// 이름표에는 확인된 세션 제목만 쓴다. 입력 프롬프트와 진행 중 작업은 제목이 아니므로,
    /// 자동 제목이 아직 없을 때는 추측하지 않고 `No name`으로 표시한다.
    var title: String {
        if let sessionTitle, !sessionTitle.isEmpty { return sessionTitle }
        return "No name"
    }
    var needsAttention: Bool { attention == true && closed != true }
    var isClosed: Bool { closed == true }
}

/// 메뉴 막대의 AI 세션 목록과 자동 검사가 같은 문자열을 쓴다. 훅 없이 찾은 Codex task도
/// 일반 세션과 똑같이 한 행으로 보여야 한다.
func sessionMenuLabel(for payload: StatePayload) -> String {
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
    guard (payload.petState == .running || payload.petState == .review),
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
struct CodexTranscriptStatus {
    let completedAtMs: Double?
    let latestPromptAtMs: Double?

    var isCompletedAfterLatestPrompt: Bool {
        guard let completedAtMs else { return false }
        return completedAtMs > (latestPromptAtMs ?? 0)
    }
}

func codexTranscriptStatus(in text: String) -> CodexTranscriptStatus {
    let fractionalFormatter = ISO8601DateFormatter()
    fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plainFormatter = ISO8601DateFormatter()
    plainFormatter.formatOptions = [.withInternetDateTime]
    var completion: Double?
    var latestPrompt: Double?
    for line in text.split(separator: "\n") {
        guard let data = line.data(using: .utf8),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = record["payload"] as? [String: Any],
              let timestamp = record["timestamp"] as? String,
              let date = fractionalFormatter.date(from: timestamp) ?? plainFormatter.date(from: timestamp) else { continue }
        let timestampMs = date.timeIntervalSince1970 * 1000
        if record["type"] as? String == "event_msg", payload["type"] as? String == "task_complete" {
            completion = max(completion ?? 0, timestampMs)
        }
        if record["type"] as? String == "response_item",
           payload["type"] as? String == "message",
           payload["role"] as? String == "user" {
            latestPrompt = max(latestPrompt ?? 0, timestampMs)
        }
    }
    return CodexTranscriptStatus(completedAtMs: completion, latestPromptAtMs: latestPrompt)
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
    guard !title.isEmpty else { return false }
    if let sessionTitle, sessionTitle.count >= 2, title.contains(sessionTitle) { return true }
    // 폴더 이름은 짧으면 우연히 겹친다. 세 글자 이상만 믿는다.
    if let folderName, folderName.count >= 3, title.contains(folderName) { return true }
    return false
}

/// 그 창을 이만큼 보고 있어야 "읽었다" 로 센다. 스쳐 지나간 것과 구분한다.
let lookingDwell: TimeInterval = 3

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
/// Claude Code 는 "사용자가 봤다" 를 어디에도 적지 않는다. 남는 흔적은 접근 시각(atime) 하나뿐이다.
///
/// 다만 재보니 Claude 앱과 VS Code 는 세션을 열 때 이 파일을 다시 읽지 않는다 — 자체 캐시에서
/// 불러온다. 그래서 이 규칙이 잡아내는 건 CLI 로 `claude --resume` 한 경우 정도다.
/// GUI 에서 읽은 것은 이걸로 알 수 없다. 2초 여유는 완료를 적을 때 훅이 같은 파일을 읽어
/// 생기는 오차를 덮는다.
func wasViewedElsewhere(accessedAtMs: Double, updatedAtMs: Double?) -> Bool {
    guard let updatedAtMs, updatedAtMs > 0 else { return false }
    return accessedAtMs > updatedAtMs + 2000
}

/// 트랜스크립트의 접근 시각. 파일을 열지 않으므로 흔적을 남기지 않는다.
func transcriptAccessedAtMs(path: String?) -> Double? {
    guard let path, !path.isEmpty else { return nil }
    var info = stat()
    guard stat(path, &info) == 0 else { return nil }
    return TimeInterval(info.st_atimespec.tv_sec) * 1000 + TimeInterval(info.st_atimespec.tv_nsec) / 1_000_000
}

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

    func status(at path: String?) -> CodexTranscriptStatus {
        guard let path, !path.isEmpty else {
            return CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
        }
        var info = stat()
        guard stat(path, &info) == 0 else {
            cache.removeValue(forKey: path)
            return CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
        }
        let size = UInt64(info.st_size)
        let modifiedAtMs = TimeInterval(info.st_mtimespec.tv_sec) * 1000
            + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000
        if let cached = cache[path], cached.size == size, cached.modifiedAtMs == modifiedAtMs {
            return cached.status
        }

        let before = info.st_atimespec
        let status = Self.readStatusTail(path: path, size: size)
        var times = [before, info.st_mtimespec]
        _ = utimensat(AT_FDCWD, path, &times, 0)
        cache[path] = CachedStatus(size: size, modifiedAtMs: modifiedAtMs, status: status)
        return status
    }

    private static func readStatusTail(path: String, size: UInt64) -> CodexTranscriptStatus {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            return CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
        }
        defer { try? handle.close() }
        let span: UInt64 = 512 * 1024
        if size > span { try? handle.seek(toOffset: size - span) }
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else {
            return CodexTranscriptStatus(completedAtMs: nil, latestPromptAtMs: nil)
        }
        return codexTranscriptStatus(in: text)
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

    func recentTasks(now: Date = Date()) -> [StatePayload] {
        let knownTitles = titles.allTitles()
        var tasks: [String: StatePayload] = [:]
        let paths: [String]
        do { paths = try FileManager.default.subpathsOfDirectory(atPath: sessionsURL.path) }
        catch { diagnostic = "\(sessionsURL.path): \(error.localizedDescription)"; return [] }
        diagnostic = "\(sessionsURL.path): \(paths.count) entries"
        for relative in paths where relative.hasSuffix(".jsonl") {
            let url = sessionsURL.appendingPathComponent(relative)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modified = attributes[.modificationDate] as? Date,
                  now.timeIntervalSince(modified) <= recentWindow,
                  let task = task(at: url, modifiedAt: modified, titles: knownTitles) else { continue }
            if let old = tasks[task.id], (old.updatedAtMs ?? 0) >= (task.updatedAtMs ?? 0) { continue }
            tasks[task.id] = task
        }
        return tasks.values.sorted { ($0.updatedAtMs ?? 0) > ($1.updatedAtMs ?? 0) }
    }

    private func task(at url: URL, modifiedAt: Date, titles: [String: String]) -> StatePayload? {
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
              !threadId.isEmpty else { return nil }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value ?? 0
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
        return StatePayload(
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
            sessionTitle: titles[threadId],
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
