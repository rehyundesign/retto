import Foundation
import Darwin

/// 확인되지 않은 승인 훅은 사용자 입력을 요구한다는 근거로 사용하지 않는다.
func unconfirmedInputTask(_ task: ReconciledCodexTask) -> ReconciledCodexTask {
    guard task.state == .waiting else { return task }
    return ReconciledCodexTask(state: .idle, observedAtMs: task.observedAtMs,
        needsAttention: false, title: task.title, source: .unavailable)
}

struct ClaudeNativeStatus: Equatable {
    let state: PetState
    let changedAtMs: Double
}

/// Claude Code가 Desktop·VS Code·터미널에서 직접 쓰는 세션 메타데이터만 읽는다.
/// 대화 본문이나 메시징 소켓에 접근하지 않는다.
final class ClaudeNativeStatusReader {
    private struct Record: Decodable {
        let pid: Int32
        let sessionId: String
        let status: String?
        let statusUpdatedAt: Double?
        let procStart: String?
        let kind: String?
        let entrypoint: String?
        let pidDomain: String?
    }
    private let directory: URL
    private let processMatches: (Int32, String) -> Bool
    private var lastRefresh = Date.distantPast
    private var timer: Timer?
    private(set) var statuses: [String: ClaudeNativeStatus] = [:]

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions"),
         processMatches: @escaping (Int32, String) -> Bool = ClaudeNativeStatusReader.sameProcess) {
        self.directory = directory
        self.processMatches = processMatches
    }

    func refresh(now: Date = Date()) {
        guard now.timeIntervalSince(lastRefresh) >= 0.5 else { return }
        lastRefresh = now
        var next: [String: ClaudeNativeStatus] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            var info = stat()
            guard lstat(file.path, &info) == 0, info.st_uid == getuid(),
                  info.st_mode & S_IFMT == S_IFREG, info.st_size <= 64 * 1024,
                  let data = try? Data(contentsOf: file),
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  record.kind == "interactive", record.pidDomain == "darwin",
                  let start = record.procStart, processMatches(record.pid, start),
                  let changed = record.statusUpdatedAt, changed > 0,
                  changed <= now.timeIntervalSince1970 * 1000 + 5_000 else { continue }
            let state: PetState
            switch record.status {
            case "busy": state = .running
            case "waiting": state = .waiting
            case "idle": state = .idle
            default: continue
            }
            // 내부 작업자가 부모 채팅의 상태를 대신하지 않도록 대화형 세션만 사용한다.
            guard ["claude-vscode", "claude-desktop", "claude-desktop-3p", "local-agent", "cli"].contains(record.entrypoint ?? "") else { continue }
            if changed >= (next[record.sessionId]?.changedAtMs ?? 0) {
                next[record.sessionId] = ClaudeNativeStatus(state: state, changedAtMs: changed)
            }
        }
        statuses = next
    }

    func start(onChange: @escaping () -> Void) {
        timer?.invalidate()
        refresh()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let before = self.statuses
            self.refresh()
            if before != self.statuses { onChange() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit { timer?.invalidate() }

    static func sameProcess(_ pid: Int32, _ expected: String) -> Bool {
        guard pid > 0 else { return false }
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid() else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        // Claude의 프로세스 메타데이터는 실행 환경의 TZ를 사용한다.
        for zone in [TimeZone.current, TimeZone(secondsFromGMT: 0)!] {
            formatter.timeZone = zone
            if let start = formatter.date(from: expected),
               abs(start.timeIntervalSince1970 - Double(info.pbi_start_tvsec)) < 1 { return true }
        }
        return false
    }
}

func applyClaudeNativeStatus(_ native: ClaudeNativeStatus?, to payload: StatePayload) -> StatePayload {
    guard !payload.isClosed, payload.source != "slack", payload.source != "codex", payload.client != "codex" else { return payload }
    var result = payload
    guard let native else {
        if payload.petState == .waiting {
            result.state = PetState.idle.rawValue
            result.attention = false
            result.stateSource = TaskStateSource.unavailable.rawValue
        }
        return result
    }
    // idle은 완료 알림과 함께 존재한다. 새 작업·입력 대기가 시작되면 앱 상태가 우선한다.
    let state = native.state == .idle && [.waving, .failed].contains(payload.petState) ? payload.petState : native.state
    result.state = state.rawValue
    result.attention = needsInputStates.contains(state)
    result.updatedAtMs = state == .waving || state == .failed ? payload.updatedAtMs : native.changedAtMs
    result.stateSource = TaskStateSource.live.rawValue
    return result
}

/// 본문 없는 상태 전환 기록. 확인 시각·revision만 바뀌면 기록을 추가하지 않는다.
final class TaskStatusDiagnostics {
    private let url: URL
    private let queue = DispatchQueue(label: "retto.status-diagnostics", qos: .utility)
    private var keys: [String: String] = [:]
    private var records: [[String: Any]] = []
    private var stopped = false
    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/retto-pet/status-transitions.json")) {
        self.url = url
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber, size.intValue <= 512 * 1024,
           let data = try? Data(contentsOf: url),
           let previous = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            records = Array(previous.suffix(256))
        }
    }
    func record(input: StatePayload, output: StatePayload, live: CodexLiveStatus?, nativeState: PetState? = nil) {
        guard !stopped else { return }
        let ids = live?.requestIDs ?? []
        let key = [input.turnId ?? "", live?.turnStartMessageID ?? "", input.state, output.state,
            output.stateSource ?? "hook", ids.joined(separator: ","), (live?.waitingFlags ?? []).joined(separator: ",")].joined(separator: "|")
        guard keys[input.id] != key else { return }
        keys[input.id] = key
        if keys.count > 1024 { keys = [input.id: key] }
        var item: [String: Any] = ["atMs": Date().timeIntervalSince1970 * 1000,
            "sessionId": input.navigationSessionId, "client": input.client ?? input.source ?? "",
            "hookState": input.state, "displayState": output.state,
            "source": output.stateSource ?? "hook", "requestIds": ids]
        if let revision = live?.revision { item["revision"] = revision }
        if let live {
            item["requestMethods"] = live.requestMethods
            item["waitingFlags"] = live.waitingFlags
            if let turn = live.turnStartMessageID { item["nativeTurnMessageId"] = turn }
        }
        if let event = input.event { item["hookEvent"] = event }
        if let turn = input.turnId { item["turnId"] = turn }
        if let updated = output.updatedAtMs { item["stateChangedAtMs"] = updated }
        if let native = live?.state ?? nativeState { item["nativeState"] = native.rawValue }
        records.append(item)
        records = Array(records.suffix(256))
        let snapshot = records, url = self.url
        queue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
    func flush() { queue.sync {} }
    func stop() {
        stopped = true
        flush()
    }
}
