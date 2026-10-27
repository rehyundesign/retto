// Codex 데스크탑의 로컬 상태 스트림을 읽기 전용으로 구독한다.
// lifecycle 훅에 없는 MCP 파일 첨부 승인도 여기서 확인한다.
import Foundation
import Network

private let codexWaitingMethods: Set<String> = [
    "mcpServer/elicitation/request", "item/commandExecution/requestApproval",
    "item/fileChange/requestApproval", "item/permissions/requestApproval",
    "item/tool/requestUserInput", "item/tool/requestOptionPicker"
]

struct CodexLiveStatus: Equatable {
    let state: PetState
    let observedAtMs: Double
}

/// 대화 본문·명령·도구 인수는 보관하지 않는다. 상태와 요청 종류만 남긴다.
private func statusProjection(_ state: [String: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    if let runtime = state["threadRuntimeStatus"] as? [String: Any] {
        result["threadRuntimeStatus"] = runtime.filter { ["type", "activeFlags"].contains($0.key) }
    }
    if let requests = state["requests"] as? [[String: Any]] {
        result["requests"] = requests.map { $0.filter { ["id", "method", "completed"].contains($0.key) } }
    }
    if let turn = state["latestTurnStartMessageId"] { result["latestTurnStartMessageId"] = turn }
    return result
}

private enum StatusPatchError: Error { case invalid }

/// 상태에 해당하는 Immer patch만 적용한다. 배열 삽입·삭제와 중첩 갱신을 지원한다.
private func applyStatusPatch(_ current: Any, path: ArraySlice<Any>, operation: String, value: Any?) throws -> Any {
    guard let first = path.first else {
        guard operation != "remove", let value else { throw StatusPatchError.invalid }
        return value
    }
    let remaining = path.dropFirst()
    if let key = first as? String, var object = current as? [String: Any] {
        if remaining.isEmpty {
            if operation == "remove" { object.removeValue(forKey: key) }
            else { guard let value else { throw StatusPatchError.invalid }; object[key] = value }
        } else {
            guard let child = object[key] else { throw StatusPatchError.invalid }
            object[key] = try applyStatusPatch(child, path: remaining, operation: operation, value: value)
        }
        return object
    }
    if let index = first as? Int, var array = current as? [Any], index >= 0 {
        if remaining.isEmpty {
            if operation == "add", index <= array.count, let value { array.insert(value, at: index) }
            else if operation == "remove", index < array.count { array.remove(at: index) }
            else if operation == "replace", index < array.count, let value { array[index] = value }
            else { throw StatusPatchError.invalid }
        } else {
            guard index < array.count else { throw StatusPatchError.invalid }
            array[index] = try applyStatusPatch(array[index], path: remaining, operation: operation, value: value)
        }
        return array
    }
    throw StatusPatchError.invalid
}

struct CodexLiveStatusStore {
    private struct Entry {
        var fields: [String: Any]
        let owner: String
        var revision: Int
        var status: CodexLiveStatus?
    }
    private var entries: [String: Entry] = [:]
    var statuses: [String: CodexLiveStatus] { entries.compactMapValues(\.status) }
    mutating func reset() { entries.removeAll() }
    mutating func retain(_ ids: Set<String>) { entries = entries.filter { ids.contains($0.key) } }
    mutating func disconnect(owner: String) { entries = entries.filter { $0.value.owner != owner } }

    /// 반환한 ID는 누락된 차이를 다시 읽을 대상이다. 알 수 없는 버전은 상태를 추측하지 않는다.
    mutating func consume(_ message: [String: Any], nowMs: Double) -> String? {
        guard message["method"] as? String == "thread-stream-state-changed",
              let params = message["params"] as? [String: Any], params["hostId"] as? String == "local",
              let id = params["conversationId"] as? String else { return nil }
        guard message["version"] as? Int == 11,
              let owner = message["sourceClientId"] as? String,
              let change = params["change"] as? [String: Any], let revision = change["revision"] as? Int else {
            entries.removeValue(forKey: id); return nil
        }
        var fields: [String: Any]
        if change["type"] as? String == "snapshot", let state = change["conversationState"] as? [String: Any] {
            guard state["id"] as? String == id else { entries.removeValue(forKey: id); return nil }
            if let old = entries[id], old.owner == owner, revision < old.revision { return nil }
            fields = statusProjection(state)
        } else if change["type"] as? String == "patches" {
            if let old = entries[id], old.owner != owner || revision <= old.revision { return nil }
            guard let old = entries[id], old.owner == owner,
                  change["baseRevision"] as? Int == old.revision, revision > old.revision,
                  let patches = change["patches"] as? [[String: Any]] else {
                entries.removeValue(forKey: id); return id
            }
            fields = old.fields
            do {
                for patch in patches {
                    guard let path = patch["path"] as? [Any], let op = patch["op"] as? String,
                          ["add", "remove", "replace"].contains(op) else { throw StatusPatchError.invalid }
                    if let root = path.first as? String {
                        guard ["threadRuntimeStatus", "requests", "latestTurnStartMessageId"].contains(root) else { continue }
                        if root == "requests", path.count > 2,
                           let key = path[2] as? String, !["id", "method", "completed"].contains(key) { continue }
                    }
                    fields = statusProjection(try applyStatusPatch(fields, path: path[...], operation: op, value: patch["value"]) as? [String: Any] ?? [:])
                }
            } catch { entries.removeValue(forKey: id); return id }
        } else { entries.removeValue(forKey: id); return nil }
        let runtime = fields["threadRuntimeStatus"] as? [String: Any]
        let flags = runtime?["activeFlags"] as? [String] ?? []
        let pending = (fields["requests"] as? [[String: Any]] ?? []).contains {
            codexWaitingMethods.contains($0["method"] as? String ?? "") && $0["completed"] as? Bool != true
        }
        let state: PetState?
        if pending || flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput") { state = .waiting }
        else {
            switch runtime?["type"] as? String {
            case "active": state = .running
            case "idle": state = .idle
            case "systemError": state = .failed
            default: state = nil
            }
        }
        let oldStatus = entries[id]?.status
        let unchanged = entries[id].map { NSDictionary(dictionary: $0.fields).isEqual(to: fields) } ?? false
        let status = state.map { CodexLiveStatus(state: $0, observedAtMs: unchanged ? (oldStatus?.observedAtMs ?? nowMs) : nowMs) }
        entries[id] = Entry(fields: fields, owner: owner, revision: revision, status: status)
        return nil
    }
}

func applyCodexLiveStatus(_ live: CodexLiveStatus?, to task: ReconciledCodexTask,
                         transcriptStatus: CodexTranscriptStatus) -> ReconciledCodexTask {
    guard let live else { return task }
    if live.state == .waiting {
        // 완료·새 사용자 턴은 그보다 먼저 관측한 도구 승인을 종료한다.
        let endedAt = max(transcriptStatus.completedAtMs ?? 0, transcriptStatus.latestAbortAtMs ?? 0,
                          transcriptStatus.latestComposerStartAtMs ?? 0)
        if endedAt > live.observedAtMs { return task }
        return ReconciledCodexTask(state: .waiting, observedAtMs: live.observedAtMs,
                                   needsAttention: true, title: task.title, source: .live)
    }
    // 비동기 질문은 도구가 반환돼도 사용자 답변까지 유지한다.
    guard transcriptStatus.pendingInputAtMs == nil else { return task }
    if task.state == .waiting, live.observedAtMs >= (task.observedAtMs ?? 0) {
        let state: PetState = transcriptStatus.isCompletedAfterLatestPrompt && live.state == .idle ? .waving : live.state
        return ReconciledCodexTask(state: state, observedAtMs: live.observedAtMs,
                                   needsAttention: needsInputStates.contains(state), title: task.title, source: .live)
    }
    return task
}

/// 연결에서 허용하는 발신은 초기화, 상태 구독과 미지원 요청 회신뿐이다.
/// 승인 응답·대화 조작·소유권 획득 메서드는 보내지 않는다.
final class CodexLiveStatusReader {
    var onChange: (() -> Void)?
    private(set) var statuses: [String: CodexLiveStatus] = [:] // main queue
    private let queue = DispatchQueue(label: "retto.codex-status", qos: .utility)
    private var connection: NWConnection?
    private var generation = 0
    private var clientID: String?
    private var buffer = Data()
    private var tracked: Set<String> = []
    private var store = CodexLiveStatusStore()
    private var running = false
    private var lastResync: [String: Date] = [:]
    private var scheduledResync: [String: DispatchWorkItem] = [:]
    private var retry: DispatchWorkItem?
    private var initializationTimeout: DispatchWorkItem?

    func track(_ ids: Set<String>) {
        queue.async { [weak self] in
            guard let self else { return }
            let removed = self.tracked.subtracting(ids), added = ids.subtracting(self.tracked)
            self.tracked = ids; self.store.retain(ids); self.publish()
            if !self.running { self.running = true; self.connect() }
            guard self.clientID != nil else { return }
            for id in removed { self.follow(id, following: false) }
            for id in added { self.follow(id, following: true) }
        }
    }
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false; self.retry?.cancel(); self.initializationTimeout?.cancel()
            self.scheduledResync.values.forEach { $0.cancel() }; self.scheduledResync.removeAll()
            self.generation += 1; self.connection?.cancel(); self.connection = nil
            self.store.reset(); self.publish()
        }
    }
    private func connect() {
        guard running, connection == nil else { return }
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let path = URL(fileURLWithPath: home).appendingPathComponent("ipc/ipc.sock").path
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(), (info.st_mode & 0o022) == 0 else { scheduleRetry(); return }
        generation += 1
        let current = generation
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, current == self.generation else { return }
            switch state {
            case .ready:
                self.send(["type": "request", "requestId": UUID().uuidString, "sourceClientId": "initializing-client",
                           "version": 0, "method": "initialize", "params": ["clientType": "retto-status-observer"]])
                self.receive(current)
            case .failed, .cancelled, .waiting: self.disconnected(current)
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self] in self?.disconnected(current) }
        initializationTimeout = timeout
        queue.asyncAfter(deadline: .now() + 15, execute: timeout)
        connection.start(queue: queue)
    }
    private func scheduleRetry() {
        guard running else { return }
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        retry = work; queue.asyncAfter(deadline: .now() + 5, execute: work)
    }
    private func disconnected(_ current: Int) {
        guard current == generation else { return }
        generation += 1; initializationTimeout?.cancel()
        connection?.cancel(); connection = nil; clientID = nil; buffer.removeAll()
        store.reset(); lastResync.removeAll(); publish(); scheduleRetry()
        scheduledResync.values.forEach { $0.cancel() }; scheduledResync.removeAll()
    }
    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        var size = UInt32(data.count).littleEndian
        let framed = withUnsafeBytes(of: &size) { Data($0) } + data
        let current = generation
        connection?.send(content: framed, completion: .contentProcessed { [weak self] error in
            if error != nil { self?.disconnected(current) }
        })
    }
    private func follow(_ id: String, following: Bool) {
        guard let clientID else { return }
        send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
              "sourceClientId": clientID, "params": ["conversationId": id, "hostId": "local", "following": following]])
    }
    private func resync(_ id: String) {
        guard scheduledResync[id] == nil else { return }
        let delay = max(0, 2 - Date().timeIntervalSince(lastResync[id] ?? .distantPast))
        let current = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }
            self.scheduledResync.removeValue(forKey: id)
            guard self.tracked.contains(id), self.clientID != nil else { return }
            self.lastResync[id] = Date(); self.follow(id, following: true)
        }
        scheduledResync[id] = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func receive(_ current: Int) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, done, error in
            guard let self, current == self.generation else { return }
            if let data { self.buffer.append(data) }
            while self.buffer.count >= 4 {
                let size = self.buffer.prefix(4).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
                guard size > 0, size <= 64 * 1024 * 1024 else { self.disconnected(current); return }
                guard self.buffer.count >= size + 4 else { break }
                let frame = self.buffer.subdata(in: 4..<(size + 4)); self.buffer.removeSubrange(0..<(size + 4))
                guard let message = try? JSONSerialization.jsonObject(with: frame) as? [String: Any] else { self.disconnected(current); return }
                self.handle(message)
            }
            if done || error != nil { self.disconnected(current) } else { self.receive(current) }
        }
    }
    private func handle(_ message: [String: Any]) {
        let type = message["type"] as? String
        if type == "client-discovery-request", let id = message["requestId"] {
            send(["type": "client-discovery-response", "requestId": id, "response": ["canHandle": false]])
            return
        }
        if type == "request", let id = message["requestId"] {
            send(["type": "response", "requestId": id, "resultType": "error", "error": "no-handler-for-request"])
            return
        }
        if type == "response", message["method"] as? String == "initialize", message["resultType"] as? String == "success",
           let result = message["result"] as? [String: Any], let id = result["clientId"] as? String {
            initializationTimeout?.cancel(); clientID = id
            for thread in tracked { follow(thread, following: true) }
            return
        }
        guard type == "broadcast", let params = message["params"] as? [String: Any] else { return }
        if let targets = message["targetClientIds"] as? [String], !targets.contains(clientID ?? "") { return }
        if message["method"] as? String == "client-status-changed", let owner = params["clientId"] as? String {
            if params["status"] as? String == "disconnected" { store.disconnect(owner: owner); publish() }
            else if owner != clientID { for id in tracked { follow(id, following: true) } }
            return
        }
        guard let id = params["conversationId"] as? String, tracked.contains(id) else { return }
        if message["method"] as? String == "thread-stream-following-status-requested" { follow(id, following: true); return }
        if let id = store.consume(message, nowMs: Date().timeIntervalSince1970 * 1000) { resync(id) }
        publish()
    }
    private func publish() {
        let next = store.statuses
        DispatchQueue.main.async { [weak self] in
            guard let self, next != self.statuses else { return }
            self.statuses = next; self.onChange?()
        }
    }
}
