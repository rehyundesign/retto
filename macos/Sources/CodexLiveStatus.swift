// Codex 데스크탑의 로컬 상태 스트림을 읽기 전용으로 구독한다.
// lifecycle 훅에 없는 MCP 파일 첨부 승인도 여기서 확인한다.
import Foundation
import CoreFoundation
import Network

private let codexWaitingMethods: Set<String> = [
    "mcpServer/elicitation/request", "item/commandExecution/requestApproval",
    "item/fileChange/requestApproval", "item/permissions/requestApproval",
    "item/tool/requestUserInput", "item/tool/requestOptionPicker"
]
// 복원된 권한 요청은 앱의 waitingOnApproval로 확인한다. 현재 대화의 입력 요청은 별도로 유지한다.
private let codexUserInputMethods: Set<String> = [
    "mcpServer/elicitation/request", "item/tool/requestUserInput", "item/tool/requestOptionPicker"
]

struct CodexLiveStatus: Equatable {
    let state: PetState
    let observedAtMs: Double
    // 같은 상태의 새 snapshot은 이전 훅보다 나중에 확인한 근거가 된다.
    // 상태 전환 시각과 분리해, 완료 알림 시각까지 계속 새로 만들지 않는다.
    var confirmedAtMs: Double? = nil
    var lastConfirmedAtMs: Double { confirmedAtMs ?? observedAtMs }
    // 다른 도구의 patch는 남아 있는 승인 요청을 다시 확인한 근거가 아니다.
    // 전체 snapshot을 받은 시각으로 입력 대기 재확인 주기를 관리한다.
    var snapshotConfirmedAtMs: Double? = nil
    var requestIDs: [String] = []
    var requestMethods: [String] = []
    var waitingFlags: [String] = []
    var turnStartMessageID: String? = nil
    var revision: Int? = nil
    var hasUnreadTurn: Bool? = nil
    var readConfirmedAtMs: Double? = nil

    // revision은 진단용이다. 본문 패치마다 오버레이 전체를 다시 갱신하지 않는다.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.state == rhs.state && lhs.observedAtMs == rhs.observedAtMs
            && lhs.confirmedAtMs == rhs.confirmedAtMs && lhs.snapshotConfirmedAtMs == rhs.snapshotConfirmedAtMs
            && lhs.requestIDs == rhs.requestIDs && lhs.requestMethods == rhs.requestMethods
            && lhs.hasUnreadTurn == rhs.hasUnreadTurn && lhs.readConfirmedAtMs == rhs.readConfirmedAtMs
            && lhs.waitingFlags == rhs.waitingFlags && lhs.turnStartMessageID == rhs.turnStartMessageID
    }
}

func needsCodexHookConfirmation(_ status: CodexLiveStatus, since: Double, requestedAt: Double) -> Bool {
    // 일반 도구 patch가 새 질문 뒤에 도착해도 전체 상태 재확인을 생략하지 않는다.
    (status.snapshotConfirmedAtMs ?? status.lastConfirmedAtMs) < since && requestedAt < since
}

/// snapshot 의 conversationState 는 대화 전체라 한 건에 16~30MB 다. 입력 대기 확인으로 몇 초마다 다시 받으므로,
/// 전부 객체로 만들지 않고 statusProjection 이 읽는 필드만 남긴다. 나머지 모양과 값의 타입은 JSONSerialization 과 같다.
private let liveStateKeys: Set<String> = ["id", "threadRuntimeStatus", "requests", "latestTurnStartMessageId", "resumeState", "hasUnreadTurn"]

private struct LiveStatusJSON: Decodable {
    let value: Any?
    init(from decoder: Decoder) throws {
        let path = decoder.codingPath
        if path.count == 4, path[0].stringValue == "params", path[1].stringValue == "change",
           path[2].stringValue == "conversationState", !liveStateKeys.contains(path[3].stringValue) {
            value = nil
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { value = NSNull(); return }
        if let bool = try? single.decode(Bool.self) { value = NSNumber(value: bool); return }
        if let int = try? single.decode(Int.self) { value = NSNumber(value: int); return }
        if let double = try? single.decode(Double.self) { value = NSNumber(value: double); return }
        if let string = try? single.decode(String.self) { value = string; return }
        if let array = try? single.decode([LiveStatusJSON].self) { value = array.compactMap(\.value); return }
        let object = try single.decode([String: LiveStatusJSON].self)
        value = object.compactMapValues(\.value)
    }
}

/// 작은 메시지(패치·요청)는 JSONDecoder 가 25배 느리므로(1건 4.7µs → 120µs) 예전처럼 JSONSerialization 으로 읽는다.
/// 18MB snapshot 은 49ms → 8.7ms 다. 읽지 못하면 JSONSerialization 으로 다시 읽는다.
func decodeLiveStatusMessage(_ frame: Data) -> [String: Any]? {
    if frame.count > 1_000_000,
       let message = (try? JSONDecoder().decode(LiveStatusJSON.self, from: frame))?.value as? [String: Any] {
        return message
    }
    return try? JSONSerialization.jsonObject(with: frame) as? [String: Any]
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
    if let resume = state["resumeState"] { result["resumeState"] = resume }
    if let unread = state["hasUnreadTurn"] { result["hasUnreadTurn"] = unread }
    return result
}

private func validStatusShape(_ fields: [String: Any]) -> Bool {
    if let unread = fields["hasUnreadTurn"] {
        guard let value = unread as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
    }
    if let value = fields["threadRuntimeStatus"], !(value is NSNull) {
        guard let runtime = value as? [String: Any] else { return false }
        if let type = runtime["type"], !(type is String) { return false }
        if let flags = runtime["activeFlags"], !(flags is [String]) { return false }
    }
    if let value = fields["requests"] {
        guard let requests = value as? [[String: Any]] else { return false }
        for request in requests {
            if let method = request["method"], !(method is String) { return false }
            if let completed = request["completed"] {
                guard let number = completed as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
            }
        }
    }
    return true
}

private func waitingIdentity(_ fields: [String: Any]) -> NSDictionary {
    let runtime = fields["threadRuntimeStatus"] as? [String: Any]
    let requests = (fields["requests"] as? [[String: Any]] ?? []).filter {
        codexWaitingMethods.contains($0["method"] as? String ?? "") && $0["completed"] as? Bool != true
    }
    return NSDictionary(dictionary: ["requests": requests,
        "flags": (runtime?["activeFlags"] as? [String] ?? []).filter { ["waitingOnApproval", "waitingOnUserInput"].contains($0) },
        "turn": fields["latestTurnStartMessageId"] ?? ""])
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
    private struct Fence {
        var owner: String?
        var revisions: [String: Int] = [:]
        var retired: Set<String> = []
        var validateOwnerChanges = false
        var validationPending = false
    }
    private var entries: [String: Entry] = [:]
    private var fences: [String: Fence] = [:]
    private var disconnectedOwners: Set<String> = []
    private var validateNewOwners = false
    private(set) var ownerValidationRequests: Set<String> = []
    private var protocolValidationRequests: Set<String> = []
    private(set) var acceptedSnapshotID: String?
    var statuses: [String: CodexLiveStatus] { entries.compactMapValues(\.status) }
    mutating func reset() {
        entries.removeAll(); fences.removeAll(); disconnectedOwners.removeAll()
        ownerValidationRequests.removeAll(); protocolValidationRequests.removeAll()
        acceptedSnapshotID = nil; validateNewOwners = false
    }
    mutating func retain(_ ids: Set<String>) {
        entries = entries.filter { ids.contains($0.key) }
        fences = fences.filter { ids.contains($0.key) }
        ownerValidationRequests.formIntersection(ids)
        protocolValidationRequests.formIntersection(ids)
    }
    @discardableResult mutating func disconnect(owner: String) -> Set<String> {
        let affected = Set(fences.keys.filter { fences[$0]?.owner == owner })
        disconnectedOwners.insert(owner)
        if disconnectedOwners.count > 1024 {
            disconnectedOwners.removeAll(); validateNewOwners = true
        }
        for id in affected {
            fences[id]?.retired.insert(owner)
            entries.removeValue(forKey: id)
        }
        return affected
    }
    mutating func takeOwnerValidationRequests() -> Set<String> {
        let ids = ownerValidationRequests; ownerValidationRequests.removeAll(); return ids
    }
    mutating func requireProtocolValidation(_ id: String) {
        var fence = fences[id] ?? Fence()
        fence.validationPending = true
        fences[id] = fence
        entries.removeValue(forKey: id)
        protocolValidationRequests.insert(id)
    }
    mutating func takeProtocolValidationRequests() -> Set<String> {
        let ids = protocolValidationRequests; protocolValidationRequests.removeAll(); return ids
    }
    func metadataRequiresOwnerValidation(owner: String, threadID: String) -> Bool {
        if disconnectedOwners.contains(owner) { return true }
        guard let fence = fences[threadID] else { return validateNewOwners }
        return fence.validationPending || fence.retired.contains(owner) || (fence.owner != nil && fence.owner != owner)
            || (fence.validateOwnerChanges && fence.owner != owner)
    }
    mutating func invalidateOversized(_ id: String, owner: String, revision: Int) {
        remember(id, owner: owner, revision: revision, transfer: true)
        entries.removeValue(forKey: id)
    }
    func acceptsOversized(owner: String, threadID: String, revision: Int?) -> Bool {
        guard !disconnectedOwners.contains(owner) else { return false }
        guard let fence = fences[threadID] else { return !validateNewOwners }
        guard !fence.validationPending, !fence.retired.contains(owner), !(fence.validateOwnerChanges && fence.owner != owner) else { return false }
        if let revision, revision < (fence.revisions[owner] ?? -1) { return false }
        return true
    }
    private mutating func remember(_ id: String, owner: String, revision: Int, transfer: Bool) {
        var fence = fences[id] ?? Fence()
        if transfer {
            if let previous = fence.owner, previous != owner { fence.retired.insert(previous) }
            fence.owner = owner
        }
        fence.revisions[owner] = max(fence.revisions[owner] ?? -1, revision)
        if fence.revisions.count > 64 || fence.retired.count > 64 {
            fence.validateOwnerChanges = true
            let current = fence.owner
            fence.revisions = fence.revisions.filter { $0.key == current }
            fence.retired = Set(fence.retired.filter { $0 == current })
        }
        fences[id] = fence
    }
    mutating func invalidate(_ id: String) { entries.removeValue(forKey: id) }

    /// 반환한 ID는 누락된 차이를 다시 읽을 대상이다. 알 수 없는 버전은 상태를 추측하지 않는다.
    mutating func consume(_ message: [String: Any], nowMs: Double) -> String? {
        acceptedSnapshotID = nil
        guard message["method"] as? String == "thread-stream-state-changed",
              let params = message["params"] as? [String: Any], params["hostId"] as? String == "local",
              let id = params["conversationId"] as? String else { return nil }
        guard let owner = message["sourceClientId"] as? String, !owner.isEmpty, owner.utf8.count <= 256,
              !id.isEmpty, id.utf8.count <= 256 else { return nil }
        let fence = fences[id]
        if fence?.validationPending == true { return nil }
        // 지원하지 않는 버전의 revision 의미는 신뢰할 수 없다. 현재 관찰자 세대를
        // 격리하고, 새 관찰자가 지원 버전으로 확인할 때까지 같은 채널을 재사용하지 않는다.
        guard message["version"] as? Int == 11 else {
            requireProtocolValidation(id)
            return nil
        }
        guard let change = params["change"] as? [String: Any],
              let revision = change["revision"] as? Int, revision >= 0 else { return nil }
        let snapshot = change["type"] as? String == "snapshot"
        // 같은 관찰자 ID에 도착한 다른 소유자의 snapshot만으로 새 소유권을 확정하지 않는다.
        if snapshot, let currentOwner = fence?.owner, currentOwner != owner {
            fences[id]?.validationPending = true; entries.removeValue(forKey: id)
            ownerValidationRequests.insert(id)
            return nil
        }
        let blocked = disconnectedOwners.contains(owner) || fence?.retired.contains(owner) == true
            || (fence?.validateOwnerChanges == true && fence?.owner != owner)
            || (validateNewOwners && fence?.owner != owner)
        if blocked {
            if snapshot {
                var pending = fences[id] ?? Fence(); pending.validationPending = true; fences[id] = pending
                entries.removeValue(forKey: id); ownerValidationRequests.insert(id)
            }
            return nil
        }
        if let highest = fence?.revisions[owner], revision < highest {
            return entries[id] == nil && fence?.owner == owner ? id : nil
        }
        var fields: [String: Any]
        if change["type"] as? String == "snapshot", let state = change["conversationState"] as? [String: Any] {
            guard state["id"] as? String == id else { entries.removeValue(forKey: id); return nil }
            remember(id, owner: owner, revision: revision, transfer: true)
            guard validStatusShape(state) else { entries.removeValue(forKey: id); return id }
            fields = statusProjection(state)
        } else if change["type"] as? String == "patches" {
            if let currentOwner = fences[id]?.owner, currentOwner != owner { return nil }
            if let old = entries[id], revision <= old.revision { return nil }
            remember(id, owner: owner, revision: revision, transfer: false)
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
                        guard liveStateKeys.contains(root) else { continue }
                        if root == "requests", path.count > 2,
                           let key = path[2] as? String, !["id", "method", "completed"].contains(key) { continue }
                    }
                    let applied = try applyStatusPatch(fields, path: path[...], operation: op, value: patch["value"]) as? [String: Any] ?? [:]
                    guard validStatusShape(applied) else { throw StatusPatchError.invalid }
                    fields = statusProjection(applied)
                }
            } catch { entries.removeValue(forKey: id); return id }
        } else { entries.removeValue(forKey: id); return nil }
        let runtime = fields["threadRuntimeStatus"] as? [String: Any]
        let flags = runtime?["activeFlags"] as? [String] ?? []
        let resume = fields["resumeState"] as? String
        // Codex UI와 같이, 현재 소유 중인 대화의 요청과 복원된 대화의 과거 요청을 구분한다.
        // needs_resume의 요청은 앱의 activeFlags가 실제 대기를 확인한 경우에만 사용한다.
        let pending = (fields["requests"] as? [[String: Any]] ?? []).contains {
            let method = $0["method"] as? String ?? ""
            return $0["completed"] as? Bool != true && resume != "needs_resume"
                && (codexUserInputMethods.contains(method) || (resume == "resumed" && codexWaitingMethods.contains(method)))
        }
        let state: PetState?
        if pending || (runtime?["type"] as? String == "active" && (flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput"))) { state = .waiting }
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
        let sameWaiting = state == .waiting && oldStatus?.state == .waiting
            && entries[id].map { waitingIdentity($0.fields).isEqual(waitingIdentity(fields)) } == true
        let confirmedAt = change["type"] as? String == "snapshot" || !unchanged
            ? nowMs : (oldStatus?.lastConfirmedAtMs ?? nowMs)
        let status = state.map { CodexLiveStatus(state: $0,
            observedAtMs: unchanged || sameWaiting ? (oldStatus?.observedAtMs ?? nowMs) : nowMs,
            confirmedAtMs: confirmedAt,
            snapshotConfirmedAtMs: change["type"] as? String == "snapshot"
                ? nowMs : oldStatus?.snapshotConfirmedAtMs,
            requestIDs: (fields["requests"] as? [[String: Any]] ?? []).filter {
                codexWaitingMethods.contains($0["method"] as? String ?? "") && $0["completed"] as? Bool != true
            }.compactMap { request -> String? in
                if let id = request["id"] as? String { return String(id.prefix(256)) }
                return (request["id"] as? Int).map(String.init)
            }.sorted(),
            requestMethods: (fields["requests"] as? [[String: Any]] ?? []).filter {
                codexWaitingMethods.contains($0["method"] as? String ?? "") && $0["completed"] as? Bool != true
            }.compactMap { $0["method"] as? String }.sorted(),
            waitingFlags: flags.filter { ["waitingOnApproval", "waitingOnUserInput"].contains($0) },
            turnStartMessageID: fields["latestTurnStartMessageId"] as? String, revision: revision, hasUnreadTurn: fields["hasUnreadTurn"] as? Bool,
            readConfirmedAtMs: fields["hasUnreadTurn"] == nil ? nil
                : (snapshot || oldStatus?.hasUnreadTurn != fields["hasUnreadTurn"] as? Bool ? nowMs : oldStatus?.readConfirmedAtMs)) }
        entries[id] = Entry(fields: fields, owner: owner, revision: revision, status: status)
        if snapshot { acceptedSnapshotID = id }
        return nil
    }
}

func applyCodexLiveStatus(_ live: CodexLiveStatus?, to task: ReconciledCodexTask,
                         transcriptStatus: CodexTranscriptStatus) -> ReconciledCodexTask {
    guard let live else { return unconfirmedInputTask(task) }
    if live.state == .waiting {
        // 완료·새 사용자 턴은 그보다 먼저 관측한 도구 승인을 종료한다.
        let endedAt = max(transcriptStatus.completedAtMs ?? 0, transcriptStatus.latestAbortAtMs ?? 0,
                          transcriptStatus.latestComposerStartAtMs ?? 0)
        if endedAt > live.observedAtMs { return unconfirmedInputTask(task) }
        return ReconciledCodexTask(state: .waiting, observedAtMs: live.observedAtMs,
                                   needsAttention: true, title: task.title, source: .live)
    }
    // 훅 수신 시각은 앱의 상태 버전이 아니다. 실제 입력 여부는 앱 상태를 우선한다.
    // 새 질문 이후 전체 상태를 아직 받지 않았다면 재확인하는 동안 파란색으로 단정하지 않는다.
    if let pending = transcriptStatus.pendingInputAtMs,
       pending > (live.snapshotConfirmedAtMs ?? live.lastConfirmedAtMs) {
        return unconfirmedInputTask(task)
    }
    let state: PetState
    if live.state == .idle, transcriptStatus.isCompletedAfterLatestPrompt { state = .waving }
    else if live.state == .idle, task.state == .waving || task.state == .failed { state = task.state }
    else { state = live.state }
    return ReconciledCodexTask(state: state,
        observedAtMs: state == .waving ? (transcriptStatus.completedAtMs ?? task.observedAtMs) : live.observedAtMs,
        needsAttention: needsInputStates.contains(state), title: task.title, source: .live)
}

/// 연결에서 허용하는 발신은 초기화, 상태 구독과 미지원 요청 회신뿐이다.
/// 승인 응답·대화 조작·소유권 획득 메서드는 보내지 않는다.
struct CodexDedicatedSlot {
    let id: String
    let state: PetState?
    let servedAt: TimeInterval
}

struct CodexDedicatedSlotPlan {
    let id: String
    let eligibleAt: TimeInterval
    let parkAfterEviction: Bool
}

/// 유휴 기록을 먼저 회수하고, 모두 활성 상태이면 가장 오래 제공한 슬롯을 순환한다.
func codexDedicatedSlotPlan(_ candidates: [CodexDedicatedSlot], now: TimeInterval,
                            lease: TimeInterval) -> CodexDedicatedSlotPlan? {
    func inactive(_ state: PetState?) -> Bool {
        guard let state else { return true }
        return state == .idle || state == .waving || state == .failed
    }
    let ordered = candidates.sorted {
        let left = inactive($0.state), right = inactive($1.state)
        if left != right { return left }
        if $0.servedAt != $1.servedAt { return $0.servedAt < $1.servedAt }
        return $0.id < $1.id
    }
    guard let first = ordered.first else { return nil }
    let park = inactive(first.state)
    return CodexDedicatedSlotPlan(id: first.id, eligibleAt: park ? now : first.servedAt + lease,
                                   parkAfterEviction: park)
}

/// 이전 연결의 ID는 새 main observer가 확인될 때까지 유지한다.
struct CodexObserverHistory {
    private(set) var ids: Set<String> = []
    private(set) var rolling = false
    let limit: Int
    func needsRollover(pending: Int = 0) -> Bool { !rolling && ids.count + pending >= limit - 1 }
    mutating func beginRollover() { rolling = true }
    mutating func acceptMain(_ id: String) -> Bool {
        guard !ids.contains(id), rolling || ids.count < limit else { return false }
        if rolling { ids.removeAll(); rolling = false }
        ids.insert(id); return true
    }
    mutating func recordChild(_ id: String) -> Bool {
        guard !rolling, !ids.contains(id), ids.count < limit else { return false }
        ids.insert(id); return true
    }
}

final class CodexLiveStatusReader {
    var onChange: (() -> Void)?
    private(set) var statuses: [String: CodexLiveStatus] = [:] // main queue
    private(set) var oversizedThreadIDs: Set<String> = [] // main queue
    private(set) var unavailableThreadIDs: Set<String> = [] // main queue
    private var confirmedUnknownThreadIDs: Set<String> = [] // main queue
    private let queue = DispatchQueue(label: "retto.codex-status", qos: .utility)
    private var connection: NWConnection?
    private var generation = 0
    private let publicationLock = NSLock()
    private var publicationEpoch = 0
    private var clientID: String?
    private var initializationRequestID: String?
    private var observerHistory: CodexObserverHistory
    private var forbiddenClientIDs: Set<String> = []
    private var initializedObserver: ((String) -> Void)?
    private var buffer = Data()
    private let maximumFrameBytes: Int
    private var discardedBytesRemaining = 0
    private var discardedMetadata = CodexFrameMetadata()
    private var oversizedThreads: Set<String> = []
    private var unavailableThreads: Set<String> = []
    private var tracked: Set<String> = []
    private var seenSubscriptions: Set<String> = []
    private var validateEveryAddition = false
    private var store = CodexLiveStatusStore()
    private var running = false
    private var lastResync: [String: TimeInterval] = [:]
    private var snapshotConfirmedAt: [String: TimeInterval] = [:]
    private var requestedHookConfirmation: [String: Double] = [:]
    private struct Confirmation {
        let started: TimeInterval
        var lastSent: TimeInterval
        var expired = false
    }
    private var confirmations: [String: Confirmation] = [:]
    private let pendingConfirmationInterval: TimeInterval
    private let confirmationTimeout: TimeInterval
    private let retryInterval: TimeInterval
    private let resyncInterval: TimeInterval
    private let validationOnly: Bool
    private let maximumPendingValidations: Int
    private let maximumDedicatedReaders: Int
    private let maximumRecoveryAttempts: Int
    private let dedicatedReaderLease: TimeInterval
    private var activeValidations: Set<String> = []
    private var slotWaiters: Set<String> = []
    private var slotWaitOrder: [String: UInt64] = [:]
    private var nextSlotWaitOrder: UInt64 = 0
    private var slotRotation: DispatchWorkItem?
    private var slotRotationAt: TimeInterval?
    private var confirmedUnknownThreads: Set<String> = []
    private var lastKnownValidatedState: [String: PetState] = [:]
    private var parkedThreads: Set<String> = []
    private var recoveryAttempts: [String: Int] = [:]
    private var lastSeenHookHint: [String: Double] = [:]
    private var lastSeenActivityHint: [String: Double] = [:]
    private var initialValidatedSnapshots: Set<String> = []
    private var ownerAmbiguity: ((String, Bool) -> Void)?
    private struct Validation {
        let token: UUID
        let reader: CodexLiveStatusReader
    }
    private var validations: [String: Validation] = [:]
    private var validationThreads: Set<String> = []
    private var validatedStatuses: [String: CodexLiveStatus] = [:]
    private var validatedOversized: Set<String> = []
    private var lastValidation: [String: TimeInterval] = [:]
    private var validationJobs: [String: DispatchWorkItem] = [:]
    private var scheduledResync: [String: DispatchWorkItem] = [:]
    private var readAfter: [String: Double] = [:]
    private var lastReadCheck: [String: TimeInterval] = [:]
    private var lastReadRequest: TimeInterval = -.greatestFiniteMagnitude
    private var readRecheck: DispatchWorkItem?
    private let readConfirmationInterval: TimeInterval
    private let readRequestInterval: TimeInterval
    private var pendingRecheck: DispatchWorkItem?
    private var retry: DispatchWorkItem?
    private var initializationTimeout: DispatchWorkItem?

    init(pendingConfirmationInterval: TimeInterval = 1, maximumFrameBytes: Int = 128 * 1024 * 1024,
         confirmationTimeout: TimeInterval = 15, retryInterval: TimeInterval = 5,
         resyncInterval: TimeInterval = 2, validationOnly: Bool = false,
         maximumPendingValidations: Int = 2, maximumDedicatedReaders: Int = 16,
         maximumRecoveryAttempts: Int = 3, dedicatedReaderLease: TimeInterval = 30,
         maximumObserverHistory: Int = 4096, readConfirmationInterval: TimeInterval = 5,
         readRequestInterval: TimeInterval = 2) {
        self.readConfirmationInterval = max(0.1, readConfirmationInterval)
        self.readRequestInterval = max(0.05, readRequestInterval)
        self.pendingConfirmationInterval = max(0.05, pendingConfirmationInterval)
        self.maximumFrameBytes = max(1024, maximumFrameBytes)
        self.confirmationTimeout = max(0.1, confirmationTimeout)
        self.retryInterval = max(0.05, retryInterval)
        self.resyncInterval = max(0.05, resyncInterval)
        self.validationOnly = validationOnly
        self.maximumPendingValidations = max(1, min(8, maximumPendingValidations))
        self.maximumDedicatedReaders = max(1, min(64, maximumDedicatedReaders))
        self.maximumRecoveryAttempts = max(1, min(8, maximumRecoveryAttempts))
        self.dedicatedReaderLease = max(0.1, dedicatedReaderLease)
        self.observerHistory = CodexObserverHistory(limit: max(4, maximumObserverHistory))
    }
    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
    @discardableResult private func advanceGeneration() -> Int {
        generation += 1
        publicationLock.lock(); publicationEpoch = generation; publicationLock.unlock()
        return generation
    }
    func track(_ ids: Set<String>, refreshAfter: [String: Double] = [:], activityAfter: [String: Double] = [:], readAfter: [String: Double] = [:]) {
        queue.async { [weak self] in
            guard let self else { return }
            let removed = self.tracked.subtracting(ids), added = ids.subtracting(self.tracked)
            for id in removed { self.removeValidation(id) }
            let retracked = Set(added.filter { self.validateEveryAddition || self.seenSubscriptions.contains($0) })
            self.tracked = ids; self.store.retain(ids)
            self.readAfter = readAfter.filter { ids.contains($0.key) }
            self.lastReadCheck = self.lastReadCheck.filter { ids.contains($0.key) }
            self.initialValidatedSnapshots.formIntersection(ids)
            self.oversizedThreads.formIntersection(ids); self.unavailableThreads.formIntersection(ids)
            self.confirmations = self.confirmations.filter { ids.contains($0.key) }
            self.snapshotConfirmedAt = self.snapshotConfirmedAt.filter { ids.contains($0.key) }
            self.requestedHookConfirmation = self.requestedHookConfirmation.filter { ids.contains($0.key) }
            self.lastSeenHookHint = self.lastSeenHookHint.filter { ids.contains($0.key) }
            self.lastSeenActivityHint = self.lastSeenActivityHint.filter { ids.contains($0.key) }
            self.confirmedUnknownThreads.formIntersection(ids)
            self.parkedThreads.formIntersection(ids); self.slotWaiters.formIntersection(ids)
            self.recoveryAttempts = self.recoveryAttempts.filter { ids.contains($0.key) }
            self.resumeSlotWaiters()
            self.publish()
            if !self.running { self.running = true; self.connect() }
            for id in retracked { self.validateOwner(id) }
            for (id, since) in activityAfter where ids.contains(id) {
                let previous = self.lastSeenActivityHint[id] ?? 0
                self.lastSeenActivityHint[id] = max(previous, since)
                if self.parkedThreads.contains(id), since > previous { self.validateOwner(id, wake: true) }
            }
            guard self.clientID != nil else { return }
            for id in removed { self.follow(id, following: false) }
            for id in added { self.follow(id, following: true) }
            for (id, since) in refreshAfter where ids.contains(id) {
                let previousHint = self.lastSeenHookHint[id] ?? 0
                self.lastSeenHookHint[id] = max(previousHint, since)
                if self.parkedThreads.contains(id), since > previousHint {
                    self.validateOwner(id, wake: true); continue
                }
                guard !self.validationThreads.contains(id), let status = self.store.statuses[id] else { continue }
                let newHook = needsCodexHookConfirmation(status, since: since,
                    requestedAt: self.requestedHookConfirmation[id] ?? 0)
                let stale = status.state == .waiting && self.uptime - (self.snapshotConfirmedAt[id] ?? 0) >= self.pendingConfirmationInterval
                guard newHook || stale else { continue }
                if newHook { self.requestedHookConfirmation[id] = since }
                self.resync(id)
            }
        }
    }
    func stop() {
        queue.async { [self] in
            self.running = false
            self.retry?.cancel(); self.initializationTimeout?.cancel()
            self.clearConnectionState()
            self.advanceGeneration(); self.connection?.cancel(); self.connection = nil; self.clientID = nil
            self.store.reset(); self.oversizedThreads.removeAll(); self.unavailableThreads.removeAll()
            self.publish()
        }
    }
    private func clearConnectionState() {
        scheduledResync.values.forEach { $0.cancel() }; scheduledResync.removeAll()
        validationJobs.values.forEach { $0.cancel() }; validationJobs.removeAll()
        for item in validations.values { item.reader.stop() }
        validations.removeAll(); validationThreads.removeAll(); validatedStatuses.removeAll(); validatedOversized.removeAll()
        lastValidation.removeAll(); activeValidations.removeAll(); slotWaiters.removeAll()
        slotWaitOrder.removeAll(); nextSlotWaitOrder = 0; lastKnownValidatedState.removeAll()
        slotRotation?.cancel(); slotRotation = nil; slotRotationAt = nil; confirmedUnknownThreads.removeAll()
        parkedThreads.removeAll(); recoveryAttempts.removeAll(); lastSeenHookHint.removeAll(); lastSeenActivityHint.removeAll()
        pendingRecheck?.cancel(); pendingRecheck = nil
        readRecheck?.cancel(); readRecheck = nil; lastReadCheck.removeAll(); lastReadRequest = -.greatestFiniteMagnitude
        buffer = Data(); discardedBytesRemaining = 0; discardedMetadata = CodexFrameMetadata()
        lastResync.removeAll(); snapshotConfirmedAt.removeAll(); confirmations.removeAll()
        requestedHookConfirmation.removeAll(); initialValidatedSnapshots.removeAll(); initializationRequestID = nil
        seenSubscriptions.removeAll(); validateEveryAddition = false
    }
    private func connect() {
        guard running, connection == nil else { return }
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let path = URL(fileURLWithPath: home).appendingPathComponent("ipc/ipc.sock").path
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(), (info.st_mode & 0o022) == 0 else { scheduleRetry(); return }
        let current = advanceGeneration()
        let connection = NWConnection(to: .unix(path: path), using: .tcp)
        self.connection = connection
        publish()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, current == self.generation else { return }
            switch state {
            case .ready:
                let requestID = UUID().uuidString
                self.initializationRequestID = requestID
                self.send(["type": "request", "requestId": requestID, "sourceClientId": "initializing-client",
                           "version": 0, "method": "initialize", "params": ["clientType": "retto-status-observer"]])
                self.receive(current)
            case .failed, .cancelled, .waiting: self.disconnected(current)
            default: break
            }
        }
        let timeout = DispatchWorkItem { [weak self] in self?.disconnected(current) }
        initializationTimeout = timeout
        queue.asyncAfter(deadline: .now() + confirmationTimeout, execute: timeout)
        connection.start(queue: queue)
    }
    private func rolloverObserverEpoch() {
        guard !validationOnly, !observerHistory.rolling else { return }
        observerHistory.beginRollover()
        retry?.cancel(); initializationTimeout?.cancel()
        advanceGeneration()
        connection?.cancel(); connection = nil; clientID = nil
        clearConnectionState(); store.reset(); oversizedThreads.removeAll()
        unavailableThreads = tracked
        publish()
        connect()
    }
    private func scheduleRetry() {
        guard running else { return }
        retry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        retry = work; queue.asyncAfter(deadline: .now() + retryInterval, execute: work)
    }
    private func disconnected(_ current: Int) {
        guard current == generation else { return }
        advanceGeneration(); initializationTimeout?.cancel()
        connection?.cancel(); connection = nil; clientID = nil
        clearConnectionState(); store.reset()
        unavailableThreads.formUnion(tracked.subtracting(oversizedThreads))
        publish()
        if validationOnly {
            running = false
            for id in tracked { ownerAmbiguity?(id, true) }
        } else { scheduleRetry() }
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
        guard !following || (!oversizedThreads.contains(id) && !validationThreads.contains(id) && !parkedThreads.contains(id)) else { return }
        if following {
            if seenSubscriptions.count < 1024 { seenSubscriptions.insert(id) }
            else { validateEveryAddition = true }
            let now = uptime
            if var existing = confirmations[id] { existing.lastSent = now; confirmations[id] = existing }
            else { confirmations[id] = Confirmation(started: now, lastSent: now) }
        } else { confirmations.removeValue(forKey: id) }
        send(["type": "broadcast", "method": "thread-stream-following-changed", "version": 1,
              "sourceClientId": clientID, "params": ["conversationId": id, "hostId": "local", "following": following]])
        schedulePendingRecheck()
    }
    private func resync(_ id: String) {
        guard scheduledResync[id] == nil, !oversizedThreads.contains(id), !validationThreads.contains(id), !parkedThreads.contains(id) else { return }
        let delay = max(0, resyncInterval - (uptime - (lastResync[id] ?? -.greatestFiniteMagnitude)))
        let current = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current else { return }
            self.scheduledResync.removeValue(forKey: id)
            guard self.tracked.contains(id), self.clientID != nil else { return }
            self.lastResync[id] = self.uptime; self.follow(id, following: true)
        }
        scheduledResync[id] = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func schedulePendingRecheck() {
        let waiting = store.statuses.contains { tracked.contains($0.key) && $0.value.state == .waiting }
        guard running, clientID != nil, waiting || !confirmations.isEmpty else {
            pendingRecheck?.cancel(); pendingRecheck = nil; return
        }
        guard pendingRecheck == nil else { return }
        let current = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, current == self.generation else { return }
            self.pendingRecheck = nil
            let now = self.uptime
            var changed = false
            for id in Array(self.confirmations.keys) {
                guard var confirmation = self.confirmations[id], self.tracked.contains(id) else { continue }
                if !confirmation.expired && now - confirmation.started >= self.confirmationTimeout {
                    confirmation.expired = true; self.confirmations[id] = confirmation
                    self.store.invalidate(id); self.unavailableThreads.insert(id); changed = true
                    if self.validationOnly || self.initialValidatedSnapshots.contains(id) {
                        self.validateOwner(id, failure: true)
                    } else {
                        // 한번도 확인되지 않은 과거 세션은 별도 연결을 무한히 만들지 않는다.
                        self.confirmations.removeValue(forKey: id); self.parkedThreads.insert(id)
                    }
                }
                if now - confirmation.lastSent >= self.resyncInterval { self.resync(id) }
            }
            for (id, status) in self.store.statuses where self.tracked.contains(id) && status.state == .waiting {
                if now - (self.snapshotConfirmedAt[id] ?? 0) >= self.pendingConfirmationInterval { self.resync(id) }
            }
            if changed { self.publish() }
            self.schedulePendingRecheck()
        }
        pendingRecheck = work
        queue.asyncAfter(deadline: .now() + min(pendingConfirmationInterval, confirmationTimeout / 3), execute: work)
    }
    // Read changes are not always broadcast by Codex. Refresh only unread completed alerts,
    // one request at a time across the reader and its dedicated observers.
    private func scheduleReadRecheck() {
        guard running, clientID != nil, !readAfter.isEmpty else {
            readRecheck?.cancel(); readRecheck = nil; return
        }
        guard readRecheck == nil else { return }
        let current = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, current == self.generation else { return }
            self.readRecheck = nil
            let now = self.uptime
            if now - self.lastReadRequest >= self.readRequestInterval {
                let statuses = self.store.statuses.merging(self.validatedStatuses) { _, child in child }
                let candidates = self.readAfter.keys.filter { id in
                    guard self.tracked.contains(id), !self.unavailableThreads.contains(id),
                          !self.oversizedThreads.contains(id), !self.parkedThreads.contains(id),
                          !self.activeValidations.contains(id), self.confirmations[id] == nil,
                          let status = statuses[id], status.state == .idle else { return false }
                    let covered = status.hasUnreadTurn == false && (status.readConfirmedAtMs ?? 0) >= self.readAfter[id]!
                    let last = self.lastReadCheck[id] ?? self.snapshotConfirmedAt[id] ?? self.lastValidation[id] ?? now
                    return !covered && now - last >= self.readConfirmationInterval
                }.sorted {
                    let a = self.lastReadCheck[$0] ?? self.snapshotConfirmedAt[$0] ?? self.lastValidation[$0] ?? 0
                    let b = self.lastReadCheck[$1] ?? self.snapshotConfirmedAt[$1] ?? self.lastValidation[$1] ?? 0
                    return a == b ? $0 < $1 : a < b
                }
                if let id = candidates.first {
                    self.lastReadCheck[id] = now; self.lastReadRequest = now
                    if let child = self.validations[id]?.reader {
                        child.queue.async { [weak child] in
                            guard let child, child.running, child.tracked.contains(id), child.confirmations[id] == nil else { return }
                            child.resync(id)
                        }
                    } else { self.resync(id) }
                }
            }
            self.scheduleReadRecheck()
        }
        readRecheck = work
        queue.asyncAfter(deadline: .now() + min(readRequestInterval, readConfirmationInterval), execute: work)
    }

    private func removeValidation(_ id: String) {
        validations.removeValue(forKey: id)?.reader.stop()
        validationJobs.removeValue(forKey: id)?.cancel()
        validationThreads.remove(id); validatedStatuses.removeValue(forKey: id); validatedOversized.remove(id)
        lastValidation.removeValue(forKey: id); activeValidations.remove(id); slotWaiters.remove(id)
        parkedThreads.remove(id); recoveryAttempts.removeValue(forKey: id)
        slotWaitOrder.removeValue(forKey: id); lastKnownValidatedState.removeValue(forKey: id)
        confirmedUnknownThreads.remove(id); lastSeenActivityHint.removeValue(forKey: id)
    }
    private func enqueueSlotWaiter(_ id: String) {
        slotWaiters.insert(id)
        if slotWaitOrder[id] == nil {
            slotWaitOrder[id] = nextSlotWaitOrder; nextSlotWaitOrder &+= 1
        }
    }
    private func scheduleSlotRotation(at deadline: TimeInterval) {
        if let existing = slotRotationAt, existing <= deadline { return }
        slotRotation?.cancel()
        let current = generation
        let job = DispatchWorkItem { [weak self] in
            guard let self, current == self.generation else { return }
            self.slotRotation = nil; self.slotRotationAt = nil; self.resumeSlotWaiters()
        }
        slotRotation = job; slotRotationAt = deadline
        queue.asyncAfter(deadline: .now() + max(0.05, deadline - uptime), execute: job)
    }
    private func reclaimDedicatedSlot(_ plan: CodexDedicatedSlotPlan) {
        validations.removeValue(forKey: plan.id)?.reader.stop()
        validatedStatuses.removeValue(forKey: plan.id); validatedOversized.remove(plan.id)
        activeValidations.remove(plan.id); unavailableThreads.insert(plan.id)
        // validationThreads를 유지해 이전 메인 연결의 늦은 패킷을 계속 차단한다.
        if plan.parkAfterEviction {
            parkedThreads.insert(plan.id); slotWaiters.remove(plan.id); slotWaitOrder.removeValue(forKey: plan.id)
        } else {
            parkedThreads.remove(plan.id); slotWaitOrder.removeValue(forKey: plan.id); enqueueSlotWaiter(plan.id)
        }
        publish()
    }
    private func resumeSlotWaiters() {
        slotWaiters.formIntersection(tracked)
        guard !slotWaiters.isEmpty else {
            slotRotation?.cancel(); slotRotation = nil; slotRotationAt = nil; return
        }
        guard activeValidations.count < maximumPendingValidations else { return }
        if validations.count >= maximumDedicatedReaders {
            let candidates = validations.keys.filter { !activeValidations.contains($0) }.map {
                CodexDedicatedSlot(id: $0, state: validatedStatuses[$0]?.state ?? lastKnownValidatedState[$0],
                    servedAt: lastValidation[$0] ?? uptime)
            }
            guard let plan = codexDedicatedSlotPlan(candidates, now: uptime, lease: dedicatedReaderLease) else { return }
            if plan.eligibleAt > uptime { scheduleSlotRotation(at: plan.eligibleAt); return }
            reclaimDedicatedSlot(plan)
        }
        let slots = min(maximumPendingValidations - activeValidations.count, maximumDedicatedReaders - validations.count)
        let ordered = slotWaiters.filter { tracked.contains($0) }.sorted {
            let left = slotWaitOrder[$0] ?? .max, right = slotWaitOrder[$1] ?? .max
            return left == right ? $0 < $1 : left < right
        }
        for id in ordered.prefix(slots) {
            slotWaiters.remove(id); validateOwner(id)
        }
    }

    private func validateOwner(_ id: String, failure: Bool = false, wake: Bool = false) {
        guard tracked.contains(id) else { return }
        if validationOnly {
            guard validationThreads.insert(id).inserted else { return }
            confirmations.removeValue(forKey: id); scheduledResync.removeValue(forKey: id)?.cancel()
            store.invalidate(id); unavailableThreads.insert(id); publish(); ownerAmbiguity?(id, failure); return
        }
        validationThreads.insert(id); validatedStatuses.removeValue(forKey: id); unavailableThreads.insert(id)
        oversizedThreads.remove(id); validatedOversized.remove(id)
        confirmations.removeValue(forKey: id); scheduledResync.removeValue(forKey: id)?.cancel()
        follow(id, following: false)
        validations.removeValue(forKey: id)?.reader.stop(); activeValidations.remove(id)
        if wake { parkedThreads.remove(id); recoveryAttempts[id] = 0 }
        if failure { recoveryAttempts[id, default: 0] += 1 }
        if recoveryAttempts[id, default: 0] >= maximumRecoveryAttempts {
            parkedThreads.insert(id); publish(); resumeSlotWaiters(); return
        }
        guard !parkedThreads.contains(id), validationJobs[id] == nil else { publish(); return }
        let attempt = recoveryAttempts[id, default: 0]
        let backoff = min(60, resyncInterval * pow(2, Double(max(0, attempt - 1))))
        let delay = max(0, backoff - (uptime - (lastValidation[id] ?? -.greatestFiniteMagnitude)))
        let current = generation
        let job = DispatchWorkItem { [weak self] in
            guard let self, current == self.generation, self.tracked.contains(id) else { return }
            self.validationJobs.removeValue(forKey: id)
            guard self.activeValidations.count < self.maximumPendingValidations,
                  self.validations.count < self.maximumDedicatedReaders else {
                self.enqueueSlotWaiter(id); self.resumeSlotWaiters(); return
            }
            // 미확정 observer도 예산에 포함해 동시 초기화가 한도를 넘지 않게 한다.
            if self.observerHistory.needsRollover(pending: self.activeValidations.count) {
                self.rolloverObserverEpoch(); return
            }
            self.slotWaiters.remove(id); self.slotWaitOrder.removeValue(forKey: id)
            self.activeValidations.insert(id)
            self.lastValidation[id] = self.uptime
            let token = UUID()
            let reader = CodexLiveStatusReader(pendingConfirmationInterval: self.pendingConfirmationInterval,
                maximumFrameBytes: self.maximumFrameBytes, confirmationTimeout: self.confirmationTimeout,
                retryInterval: self.retryInterval, resyncInterval: self.resyncInterval, validationOnly: true,
                dedicatedReaderLease: self.dedicatedReaderLease, maximumObserverHistory: self.observerHistory.limit)
            reader.forbiddenClientIDs = self.observerHistory.ids
            reader.initializedObserver = { [weak self] observer in
                self?.queue.async { [weak self] in
                    guard let self, current == self.generation else { return }
                    // 같은 epoch에서 중단된 probe의 ID도 기록한다. 이전 epoch 콜백은 위에서 차단한다.
                    let fresh = self.observerHistory.recordChild(observer)
                    if !fresh && !self.observerHistory.ids.contains(observer) {
                        // 취소된 초기화의 늦은 콜백이 예약을 초과해도 복구 능력을 유지한다.
                        self.rolloverObserverEpoch(); return
                    }
                    guard self.validations[id]?.token == token else { return }
                    if !fresh { self.validateOwner(id, failure: true) }
                }
            }
            reader.onChange = { [weak self, weak reader] in
                guard let self, let reader else { return }
                let status = reader.statuses[id], unavailable = reader.unavailableThreadIDs.contains(id)
                let oversized = reader.oversizedThreadIDs.contains(id)
                let confirmedUnknown = reader.confirmedUnknownThreadIDs.contains(id)
                self.queue.async { [weak self] in
                    guard let self, current == self.generation, self.validations[id]?.token == token else { return }
                    if let status, !unavailable && !oversized {
                        self.validatedStatuses[id] = status; self.lastKnownValidatedState[id] = status.state
                        self.unavailableThreads.remove(id)
                        self.activeValidations.remove(id); self.recoveryAttempts[id] = 0; self.parkedThreads.remove(id)
                        self.resumeSlotWaiters()
                    } else {
                        self.validatedStatuses.removeValue(forKey: id); self.unavailableThreads.insert(id)
                        if confirmedUnknown { self.activeValidations.remove(id); self.resumeSlotWaiters() }
                    }
                    if oversized { self.validatedOversized.insert(id) } else { self.validatedOversized.remove(id) }
                    self.publish()
                }
            }
            reader.ownerAmbiguity = { [weak self] requested, failed in
                self?.queue.async { [weak self] in
                    guard let self, current == self.generation, requested == id, self.validations[id]?.token == token else { return }
                    self.validateOwner(id, failure: failed)
                }
            }
            self.validations[id] = Validation(token: token, reader: reader)
            reader.track([id])
        }
        validationJobs[id] = job
        queue.asyncAfter(deadline: .now() + delay, execute: job)
        queue.async { [weak self] in self?.resumeSlotWaiters() }
        publish()
    }
    private func consumeOversized(_ route: CodexFrameRoute?) {
        guard let route, route.messageType == "broadcast", route.method == "thread-stream-state-changed",
              route.hostID == "local", tracked.contains(route.conversationID),
              let owner = route.sourceClientID, !owner.isEmpty, owner.utf8.count <= 256,
              route.targetClientIDs.map({ $0.contains(clientID ?? "") }) ?? true,
              !validationThreads.contains(route.conversationID) else { return }
        let id = route.conversationID
        guard initialValidatedSnapshots.contains(id) || route.targetClientIDs?.contains(clientID ?? "") == true else { return }
        guard route.version == 11 else {
            store.requireProtocolValidation(id)
            for requested in store.takeProtocolValidationRequests() { validateOwner(requested, failure: true) }
            return
        }
        guard let revision = route.revision, revision >= 0,
              ["snapshot", "patches"].contains(route.changeType ?? "") else { return }
        if !initialValidatedSnapshots.contains(id) {
            guard route.changeType == "snapshot" else { return }
        }
        if store.metadataRequiresOwnerValidation(owner: owner, threadID: id) {
            validateOwner(id); return
        }
        guard store.acceptsOversized(owner: owner, threadID: id, revision: revision) else { return }
        // 프레임을 읽을 수 없어도 관측한 revision은 남겨 이전 snapshot의 재유입을 막는다.
        store.invalidateOversized(id, owner: owner, revision: revision)
        initialValidatedSnapshots.insert(id)
        oversizedThreads.insert(id); confirmations.removeValue(forKey: id)
        unavailableThreads.insert(id); follow(id, following: false); publish()
    }

    private func receive(_ current: Int) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 262144) { [weak self] data, _, done, error in
            guard let self, current == self.generation else { return }
            if let data { self.buffer.append(data) }
            while !self.buffer.isEmpty {
                if self.discardedBytesRemaining > 0 {
                    let count = min(self.buffer.count, self.discardedBytesRemaining)
                    self.discardedMetadata.consume(Data(self.buffer.prefix(count)))
                    self.buffer.removeSubrange(0..<count); self.discardedBytesRemaining -= count
                    if self.discardedBytesRemaining == 0 {
                        self.consumeOversized(self.discardedMetadata.route)
                        self.discardedMetadata = CodexFrameMetadata()
                    }
                    continue
                }
                guard self.buffer.count >= 4 else { break }
                let size = self.buffer.prefix(4).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
                guard size > 0 else { self.disconnected(current); return }
                if size > self.maximumFrameBytes {
                    self.buffer.removeSubrange(0..<4); self.discardedBytesRemaining = size
                    self.discardedMetadata = CodexFrameMetadata(); continue
                }
                guard self.buffer.count >= size + 4 else { break }
                let frame = self.buffer.subdata(in: 4..<(size + 4)); self.buffer.removeSubrange(0..<(size + 4))
                // 길이로 구분된 한 건의 잘못된 본문이 다른 채팅의 연결을 종료하지 않는다.
                // 해당 채팅의 확인 응답이 없으면 별도 deadline이 확인 불가로 전환한다.
                guard let message = decodeLiveStatusMessage(frame) else { continue }
                self.handle(message)
            }
            if self.buffer.isEmpty { self.buffer = Data() }
            if done || error != nil { self.disconnected(current) } else { self.receive(current) }
        }
    }
    private func handle(_ message: [String: Any]) {
        let type = message["type"] as? String
        if type == "client-discovery-request", let id = message["requestId"] {
            send(["type": "client-discovery-response", "requestId": id, "response": ["canHandle": false]]); return
        }
        if type == "request", let id = message["requestId"] {
            send(["type": "response", "requestId": id, "resultType": "error", "error": "no-handler-for-request"]); return
        }
        if type == "response", message["method"] as? String == "initialize", message["resultType"] as? String == "success",
           let expected = initializationRequestID, message["requestId"] as? String == expected, clientID == nil,
           let result = message["result"] as? [String: Any], let id = result["clientId"] as? String {
            guard clientID == nil, !id.isEmpty, id.utf8.count <= 256,
                  !forbiddenClientIDs.contains(id) else {
                disconnected(generation); return
            }
            // 재연결도 예산 소진 전에 전체 epoch를 바꾼다. 새 ID 확인 전에는 이력을 지우지 않는다.
            if !validationOnly && observerHistory.needsRollover() { observerHistory.beginRollover() }
            guard observerHistory.acceptMain(id) else { disconnected(generation); return }
            initializationTimeout?.cancel(); initializationRequestID = nil; clientID = id
            initializedObserver?(id)
            for thread in tracked { follow(thread, following: true) }
            return
        }
        guard type == "broadcast", let params = message["params"] as? [String: Any] else { return }
        if let rawTargets = message["targetClientIds"] {
            guard let targets = rawTargets as? [String], targets.contains(clientID ?? "") else { return }
        }
        if message["method"] as? String == "client-status-changed", let owner = params["clientId"] as? String {
            if params["status"] as? String == "disconnected" {
                let affected = store.disconnect(owner: owner)
                for id in affected.intersection(tracked) where !validationThreads.contains(id) {
                    unavailableThreads.insert(id); resync(id)
                }
                publish()
            }
            return
        }
        guard let id = params["conversationId"] as? String, tracked.contains(id) else { return }
        if message["method"] as? String == "thread-stream-following-status-requested" {
            if parkedThreads.contains(id) { validateOwner(id, wake: true) }
            else if !validationThreads.contains(id) { follow(id, following: true) }
            return
        }
        if parkedThreads.contains(id) {
            if (message["targetClientIds"] as? [String])?.contains(clientID ?? "") == true,
               message["method"] as? String == "thread-stream-state-changed",
               message["version"] as? Int == 11,
               (params["change"] as? [String: Any])?["type"] as? String == "snapshot" {
                validateOwner(id, wake: true)
            }
            return
        }
        guard !validationThreads.contains(id) else { return }
        let change = params["change"] as? [String: Any]
        // 늦은 응답 처리가 deadline 타이머보다 먼저 실행돼도 만료된 채널을 신뢰하지 않는다.
        if let confirmation = confirmations[id], uptime - confirmation.started >= confirmationTimeout {
            store.invalidate(id); unavailableThreads.insert(id)
            if validationOnly || initialValidatedSnapshots.contains(id) { validateOwner(id, failure: true) }
            else { confirmations.removeValue(forKey: id); parkedThreads.insert(id); publish() }
            return
        }
        if !initialValidatedSnapshots.contains(id) {
            guard (message["targetClientIds"] as? [String])?.contains(clientID ?? "") == true else { return }
            if message["version"] as? Int == 11, change?["type"] as? String != "snapshot" { return }
        }
        if let repair = store.consume(message, nowMs: Date().timeIntervalSince1970 * 1000) { resync(repair) }
        let protocolFailures = store.takeProtocolValidationRequests()
        let ambiguities = store.takeOwnerValidationRequests()
        for requested in protocolFailures { validateOwner(requested, failure: true) }
        for requested in ambiguities.subtracting(protocolFailures) { validateOwner(requested) }
        if store.statuses[id] == nil { unavailableThreads.insert(id) }
        if store.acceptedSnapshotID == id {
            confirmations.removeValue(forKey: id); snapshotConfirmedAt[id] = uptime
            initialValidatedSnapshots.insert(id)
            oversizedThreads.remove(id)
            if store.statuses[id] != nil { unavailableThreads.remove(id); confirmedUnknownThreads.remove(id) }
            else { unavailableThreads.insert(id); confirmedUnknownThreads.insert(id) }
        }
        if store.statuses[id] != nil { confirmedUnknownThreads.remove(id) }
        publish()
    }
    private func publish() {
        schedulePendingRecheck()
        scheduleReadRecheck()
        var next = store.statuses.filter { !validationThreads.contains($0.key) && !unavailableThreads.contains($0.key) }
        for (id, status) in validatedStatuses where !unavailableThreads.contains(id) { next[id] = status }
        let excluded = oversizedThreads.union(validatedOversized), unavailable = unavailableThreads.union(excluded)
        let confirmedUnknown = confirmedUnknownThreads
        let epoch = generation
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.publicationLock.lock(); let valid = self.publicationEpoch == epoch; self.publicationLock.unlock()
            guard valid, next != self.statuses || excluded != self.oversizedThreadIDs || unavailable != self.unavailableThreadIDs
                || confirmedUnknown != self.confirmedUnknownThreadIDs else { return }
            self.statuses = next; self.oversizedThreadIDs = excluded; self.unavailableThreadIDs = unavailable
            self.confirmedUnknownThreadIDs = confirmedUnknown; self.onChange?()
        }
    }
}

/// 본문을 보관하지 않는 스트리밍 메타데이터 검사. 완전한 프레임만 식별한다.
func oversizedCodexThreadID(in frame: Data) -> String? {
    var metadata = CodexFrameMetadata(); metadata.consume(frame)
    guard let route = metadata.route, route.messageType == "broadcast", route.method == "thread-stream-state-changed", route.hostID == "local" else { return nil }
    return route.conversationID
}
