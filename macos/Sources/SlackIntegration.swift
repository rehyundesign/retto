// Slack 공식 Events API. 토큰은 키체인, 메시지는 실행 중 메모리에만 보관한다.
import AppKit
import Foundation
import Security

struct SlackPreferences: Codable {
    var directMessages = true
    var mentions = true
    var preview = true
    var channelIDs: Set<String> = []
    static func load() -> SlackPreferences {
        guard let data = UserDefaults.standard.data(forKey: "RettoSlackPreferences"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "RettoSlackPreferences") }
    }
}

struct SlackCredentials: Codable {
    let userToken: String
    let appToken: String
    func updating(userToken: String, appToken: String) -> SlackCredentials {
        let user = userToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let app = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return SlackCredentials(userToken: user.isEmpty ? self.userToken : user, appToken: app.isEmpty ? self.appToken : app)
    }
}

enum SlackKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.luxia.retto.slack",
         kSecAttrAccount as String: "connection"]
    }
    static func read() throws -> SlackCredentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = try? JSONDecoder().decode(SlackCredentials.self, from: data) else { throw SlackFailure.keychain }
        return value
    }
    static func write(_ value: SlackCredentials) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw SlackFailure.keychain }
        } else if status != errSecSuccess { throw SlackFailure.keychain }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SlackFailure.keychain }
    }
}

enum SlackFailure: Error, LocalizedError {
    case keychain, invalidTokens, response, api(String), rateLimit(Double)
    var errorDescription: String? {
        switch self {
        case .keychain: return "키체인에 접근하지 못했습니다. 맥을 잠금 해제한 뒤 다시 시도해 주세요."
        case .invalidTokens: return "같은 Slack 앱에서 발급한 사용자 토큰(xoxp-)과 앱 토큰(xapp-)을 입력해 주세요."
        case .response: return "Slack 응답을 확인하지 못했습니다. 연결 상태를 확인해 주세요."
        case .rateLimit: return "Slack 요청 한도에 도달했습니다. 잠시 후 자동으로 다시 연결합니다."
        case .api(let code):
            switch code {
            case "invalid_auth", "token_revoked", "token_expired", "account_inactive", "not_authed":
                return "Slack 인증이 만료되었거나 해제되었습니다. 새 토큰으로 연결해 주세요."
            case "missing_scope", "not_allowed_token_type": return "Slack 권한이 부족합니다. 연결 안내의 사용자 권한과 앱 토큰을 확인해 주세요."
            case "not_allowed": return "Slack에서 연결을 허용하지 않았습니다. Socket Mode 설정과 관리자 승인을 확인해 주세요."
            default: return "Slack 요청을 처리하지 못했습니다. 연결 안내와 앱 설정을 확인해 주세요."
            }
        }
    }
    var retryDelay: Double? {
        switch self {
        case .api(let code) where ["invalid_auth", "token_revoked", "token_expired", "account_inactive", "not_authed", "missing_scope", "not_allowed_token_type", "not_allowed"].contains(code): return nil
        case .invalidTokens, .keychain: return nil
        case .rateLimit(let seconds): return max(1, seconds)
        default: return 5
        }
    }
}

struct SlackChannel: Equatable {
    let id: String
    let name: String
}

// Slack ts는 소수점 아래 6자리까지 메시지를 구분한다. Double 반올림으로
// 바로 다음 메시지를 읽음 처리하지 않도록 Decimal로 비교한다.
func slackTimestamp(_ value: String) -> Decimal? {
    guard value.range(of: "^[0-9]{1,12}\\.[0-9]{1,6}$", options: .regularExpression) != nil else { return nil }
    return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
}

struct SlackReadTarget: Hashable {
    let team: String
    let channel: String
    let thread: String?

    var method: String { thread == nil ? "conversations.info" : "conversations.replies" }
    var parameters: [String: String] {
        if let thread { return ["channel": channel, "ts": thread, "limit": "1"] }
        return ["channel": channel]
    }
    func marker(in response: [String: Any]) -> String? {
        if let thread {
            return (response["messages"] as? [[String: Any]])?
                .first(where: { $0["ts"] as? String == thread })?["last_read"] as? String
        }
        guard let conversation = response["channel"] as? [String: Any],
              conversation["id"] as? String == channel else { return nil }
        return conversation["last_read"] as? String
    }
}

// 같은 대상은 15초 뒤에 재확인한다. 전체 HTTP 조회는 2초 간격이며,
// 스레드도 순환 조회한다. 실제 429 응답은 메서드별 Retry-After를 따른다.
struct SlackReadSchedule {
    private var nextChecks: [SlackReadTarget: Double] = [:]
    private var lastPrioritizedAt: [SlackReadTarget: Double] = [:]
    private var methodRetryAt: [String: Double] = [:]

    mutating func next(in targets: Set<SlackReadTarget>, now: Double) -> SlackReadTarget? {
        nextChecks = nextChecks.filter { targets.contains($0.key) }
        lastPrioritizedAt = lastPrioritizedAt.filter { targets.contains($0.key) }
        let eligible = targets.filter { (nextChecks[$0] ?? 0) <= now && (methodRetryAt[$0.method] ?? 0) <= now }
        let target = eligible.sorted {
            let left = nextChecks[$0] ?? 0, right = nextChecks[$1] ?? 0
            if left != right { return left < right }
            return ($0.channel + ":" + ($0.thread ?? "")) < ($1.channel + ":" + ($1.thread ?? ""))
        }.first
        guard let target else { return nil }
        nextChecks[target] = now + 15
        methodRetryAt[target.method] = now + 2
        return target
    }
    mutating func prioritize(_ targets: Set<SlackReadTarget>, now: Double) {
        for target in targets where now - (lastPrioritizedAt[target] ?? -.greatestFiniteMagnitude) >= 5 {
            // Prioritize one ordinary read request; never bypass method Retry-After.
            lastPrioritizedAt[target] = now
            nextChecks[target] = -1
        }
    }
    mutating func retry(_ target: SlackReadTarget, after delay: Double, now: Double, rateLimited: Bool) {
        nextChecks[target] = max(nextChecks[target] ?? 0, now + delay)
        if rateLimited { methodRetryAt[target.method] = max(methodRetryAt[target.method] ?? 0, now + delay) }
    }
}

struct SlackNotice {
    let team: String
    let channel: String
    let timestamp: String
    let user: String
    let text: String
    let isDM: Bool
    let isMention: Bool
    var senderName: String? = nil
    var isGroupDM: Bool = false
    var threadTimestamp: String? = nil
    var revisionTimestamp: String? = nil
    var id: String { "slack:\(team):\(channel):\(timestamp)" }
    var notificationGroupID: String { "slack-group:\(team):\(channel):\(user):\(readTarget.thread ?? "channel")" }
    var readTarget: SlackReadTarget {
        SlackReadTarget(team: team, channel: channel,
                        thread: threadTimestamp == timestamp ? nil : threadTimestamp)
    }

    static func authorizedEvent(_ payload: [String: Any], userID: String, teamID: String) -> [String: Any]? {
        guard payload["type"] as? String == "event_callback",
              payload["team_id"] as? String == teamID,
              let authorizations = payload["authorizations"] as? [[String: Any]],
              authorizations.contains(where: { $0["user_id"] as? String == userID && $0["is_bot"] as? Bool == false }),
              let event = payload["event"] as? [String: Any], event["type"] as? String == "message" else { return nil }
        return event
    }
    static func parse(_ payload: [String: Any], userID: String, teamID: String, allowingOwnMessage: Bool = false) -> SlackNotice? {
        guard let event = authorizedEvent(payload, userID: userID, teamID: teamID),
              event["hidden"] as? Bool != true,
              event["subtype"] == nil || ["file_share", "bot_message", "thread_broadcast", "me_message"].contains(event["subtype"] as? String ?? ""),
              let channel = event["channel"] as? String,
              let ts = event["ts"] as? String, ts.range(of: "^[0-9]{1,12}\\.[0-9]{1,6}$", options: .regularExpression) != nil,
              let text = event["text"] as? String else { return nil }
        let user = event["user"] as? String ?? event["bot_id"] as? String ?? ""
        guard !user.isEmpty, user != userID || allowingOwnMessage else { return nil }
        return SlackNotice(team: teamID, channel: channel, timestamp: ts, user: user,
                           text: text, isDM: ["im", "mpim"].contains(event["channel_type"] as? String ?? ""),
                           isMention: text.contains("<@\(userID)>"),
                           senderName: event["username"] as? String, isGroupDM: event["channel_type"] as? String == "mpim",
                           threadTimestamp: event["thread_ts"] as? String,
                           revisionTimestamp: (event["edited"] as? [String: Any])?["ts"] as? String)
    }
    func matches(_ preferences: SlackPreferences) -> Bool {
        (isDM && preferences.directMessages) || (isMention && preferences.mentions) || preferences.channelIDs.contains(channel)
    }
    var nativeMessageURL: URL? {
        guard team.range(of: "^[TE][A-Z0-9]+$", options: .regularExpression) != nil,
              channel.range(of: "^[CDG][A-Z0-9]+$", options: .regularExpression) != nil,
              timestamp.range(of: "^[0-9]{1,12}\\.[0-9]{1,6}$", options: .regularExpression) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "slack"
        components.host = "channel"
        components.queryItems = [URLQueryItem(name: "team", value: team), URLQueryItem(name: "id", value: channel),
                                 URLQueryItem(name: "message", value: timestamp)]
        if let threadTimestamp,
           threadTimestamp.range(of: "^[0-9]{1,12}\\.[0-9]{1,6}$", options: .regularExpression) != nil {
            components.queryItems?.append(URLQueryItem(name: "thread_ts", value: threadTimestamp))
        }
        return components.url
    }
    func payload(preferences: SlackPreferences, channels: [SlackChannel], userNames: [String: String] = [:],
                 sessionID: String? = nil, messageCount: Int = 1) -> StatePayload? {
        let channelName = channels.first { $0.id == channel }?.name
        let sender = userNames[user] ?? senderName ?? user
        var title = isGroupDM ? "그룹 DM" : (isDM ? "DM · " + sender : channelName.map { "#" + $0 } ?? "#" + channel)
        if sessionID != nil, !isDM || isGroupDM { title += " · " + sender }
        if messageCount > 1 { title += " +\(messageCount)" }
        var content = text
        for (id, name) in userNames { content = content.replacingOccurrences(of: "<@" + id + ">", with: "@" + name) }
        content = content.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        let hiddenBody = messageCount > 1 ? "Slack에 새 메시지 \(messageCount)개가 도착했어요" : "Slack에 새 메시지가 도착했어요"
        let body = preferences.preview ? "@" + sender + " " + String(content.prefix(3000)) : hiddenBody
        let object: [String: Any] = ["state": "waving", "source": "slack", "sessionId": sessionID ?? id,
            "projectName": "Slack", "sessionTitle": title, "lastAssistantMessage": body,
            "updatedAtMs": (Double(timestamp) ?? 0) * 1000, "attention": true]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(StatePayload.self, from: data)
    }
}

// 표시만 묶는다. 개별 메시지의 읽음 위치·삭제·수정과 중복 검사는 그대로 유지한다.
struct SlackNoticeGroup {
    let messages: [SlackNotice]
    private init(messages: [SlackNotice]) { self.messages = messages }
    var first: SlackNotice { messages[0] }
    var latest: SlackNotice { messages[messages.count - 1] }
    var id: String { latest.notificationGroupID }
    var messageIDs: Set<String> { Set(messages.map(\.id)) }
    static func grouped(_ notices: [SlackNotice]) -> [SlackNoticeGroup] {
        Dictionary(grouping: notices, by: \.notificationGroupID).values.map {
            SlackNoticeGroup(messages: $0.sorted { (slackTimestamp($0.timestamp) ?? 0) < (slackTimestamp($1.timestamp) ?? 0) })
        }.sorted {
            let left = slackTimestamp($0.latest.timestamp) ?? 0, right = slackTimestamp($1.latest.timestamp) ?? 0
            return left == right ? $0.id < $1.id : left > right
        }
    }
    func payload(preferences: SlackPreferences, channels: [SlackChannel], userNames: [String: String] = [:]) -> StatePayload? {
        latest.payload(preferences: preferences, channels: channels, userNames: userNames,
                       sessionID: id, messageCount: messages.count)
    }
}

// 수신 순서와 재전송 여부를 분리한다. 설정에 맞지 않는 이벤트도 재전송 중복에서 제외한다.
struct SlackInbox {
    private(set) var notices: [SlackNotice] = []
    private var seenIDs: Set<String> = []
    private var seenOrder: [String] = []
    private var readMarkers: [SlackReadTarget: Decimal] = [:]
    private mutating func remember(_ id: String) -> Bool {
        guard seenIDs.insert(id).inserted else { return false }
        seenOrder.append(id)
        if seenOrder.count > 2000 { seenIDs.remove(seenOrder.removeFirst()) }
        return true
    }
    mutating func accept(_ notice: SlackNotice, preferences: SlackPreferences) -> Bool {
        guard remember(notice.id) else { return false }
        guard notice.matches(preferences) else { return false }
        if let marker = readMarkers[notice.readTarget], let timestamp = slackTimestamp(notice.timestamp), timestamp <= marker { return false }
        notices.append(notice)
        notices.sort { (Double($0.timestamp) ?? 0) < (Double($1.timestamp) ?? 0) }
        if notices.count > 100 { notices.removeFirst(notices.count - 100) }
        return true
    }
    mutating func filter(preferences: SlackPreferences) { notices.removeAll { !$0.matches(preferences) } }
    @discardableResult
    mutating func dismiss(_ ids: Set<String>) -> Bool {
        let count = notices.count
        notices.removeAll { ids.contains($0.id) }
        return notices.count != count
    }
    mutating func dismissNotifications(_ ids: Set<String>) -> Bool {
        let messageIDs = SlackNoticeGroup.grouped(notices).filter { ids.contains($0.id) }
            .reduce(into: ids) { $0.formUnion($1.messageIDs) }
        return dismiss(messageIDs)
    }
    mutating func applyMessageChange(_ payload: [String: Any], userID: String, teamID: String,
                                    preferences: SlackPreferences) -> Bool {
        guard let event = SlackNotice.authorizedEvent(payload, userID: userID, teamID: teamID),
              let channel = event["channel"] as? String else { return false }
        if event["subtype"] as? String == "message_deleted",
           let timestamp = event["deleted_ts"] as? String, slackTimestamp(timestamp) != nil {
            let id = "slack:\(teamID):\(channel):\(timestamp)"
            // 삭제가 먼저 도착해도 뒤늦게 받은 원문을 다시 표시하지 않는다.
            _ = remember(id)
            return dismiss([id])
        }
        guard event["subtype"] as? String == "message_changed",
              let message = event["message"] as? [String: Any],
              let timestamp = message["ts"] as? String, slackTimestamp(timestamp) != nil,
              let index = notices.firstIndex(where: { $0.team == teamID && $0.channel == channel && $0.timestamp == timestamp }),
              let text = message["text"] as? String else { return false }
        let previous = notices[index]
        let revision = event["event_ts"] as? String ?? (message["edited"] as? [String: Any])?["ts"] as? String ?? event["ts"] as? String
        guard let revision, let version = slackTimestamp(revision),
              version > (slackTimestamp(previous.revisionTimestamp ?? previous.timestamp) ?? 0) else { return false }
        if let author = message["user"] as? String, author != previous.user { return false }
        var updated = SlackNotice(team: previous.team, channel: previous.channel, timestamp: previous.timestamp,
                                  user: previous.user, text: text, isDM: previous.isDM,
                                  isMention: text.contains("<@\(userID)>"), senderName: previous.senderName,
                                  isGroupDM: previous.isGroupDM, threadTimestamp: previous.threadTimestamp)
        updated.revisionTimestamp = revision
        if updated.matches(preferences) { notices[index] = updated }
        else { notices.remove(at: index) }
        return true
    }
    @discardableResult
    mutating func applyReadMarker(_ value: String, for target: SlackReadTarget) -> Bool {
        guard let marker = slackTimestamp(value) else { return false }
        if let previous = readMarkers[target], marker <= previous { return false }
        // 읽은 대상의 기록은 수신한 ID와 같은 상한으로 보관한다.
        if readMarkers.count >= 2000, readMarkers[target] == nil { readMarkers.removeAll() }
        readMarkers[target] = marker
        let count = notices.count
        notices.removeAll { $0.readTarget == target && slackTimestamp($0.timestamp).map { $0 <= marker } == true }
        return count != notices.count
    }
}

func slackVisibleConversationNoticeIDs(_ notices: [SlackNotice], windowTitle: String, team: String,
                                      workspace: String, channels: [SlackChannel], userNames: [String: String]) -> Set<String> {
    let candidates = notices.filter { $0.team == team && $0.readTarget.thread == nil }
    let matches = candidates.filter { notice in
        let name = notice.isDM
            ? (userNames[notice.user] ?? notice.senderName ?? "")
            : (channels.first { $0.id == notice.channel }?.name ?? "")
        guard !notice.isGroupDM else { return false }
        return slackWindowShowsConversation(windowTitle, name: name, workspace: workspace, isDM: notice.isDM)
    }
    // Names may collide. Never clear two distinct conversations from one title.
    guard Set(matches.map(\.channel)).count == 1 else { return [] }
    return Set(matches.map(\.id))
}

/// An explicit, one-message, three-minute self-DM probe for real read-cursor QA.
/// Normal launches never enable this; no credential or server read state is changed.
struct SlackReadProbe {
    let channel: String
    let text: String
    let expiresAt: TimeInterval
    private(set) var consumed = false
    static func fromArguments(_ args: [String], now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Self? {
        guard let flag = args.firstIndex(of: "--slack-read-probe"), args.count > flag + 2,
              args[flag + 1].range(of: "^D[A-Z0-9]{3,30}$", options: .regularExpression) != nil,
              let nonce = UUID(uuidString: args[flag + 2]) else { return nil }
        return Self(channel: args[flag + 1], text: "[Retto 읽음 테스트 \(nonce.uuidString.lowercased())]", expiresAt: now + 180)
    }
    func isActive(now: TimeInterval) -> Bool { !consumed && now <= expiresAt }
    mutating func consume(_ payload: [String: Any], userID: String, now: TimeInterval) -> Bool {
        guard isActive(now: now), !userID.isEmpty, let event = payload["event"] as? [String: Any],
              event["user"] as? String == userID, event["channel"] as? String == channel,
              event["channel_type"] as? String == "im", event["subtype"] == nil,
              (event["text"] as? String)?.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) == text else { return false }
        consumed = true
        return true
    }
}

// 상태와 수신 처리는 메인 큐에서만 변경한다. 재연결 전의 비동기 결과는 generation으로 제외한다.
final class SlackIntegration {
    var onChange: (() -> Void)?
    var onDiagnosticsChange: (() -> Void)?
    private var receivedEvents = 0
    private var acceptedEvents = 0
    private var lastEventDisposition = "none"
    private var lastReadEvidence: [String: String] = [:]
    var diagnosticsSnapshot: [String: Any] {
        ["connection": String(describing: connectionState), "hasCredentials": hasCredentials,
         "receivedEvents": receivedEvents, "acceptedEvents": acceptedEvents,
         "selfReadProbeActive": readProbe?.isActive(now: ProcessInfo.processInfo.systemUptime) == true,
         "credentialRestorePending": restoringCredentials, "credentialRestoreTimedOut": credentialRestoreTimedOut,
         "lastEventDisposition": lastEventDisposition, "lastReadEvidence": lastReadEvidence,
         "readIssue": readSyncIssue ?? "", "pending": notices.map {
             ["id": $0.id, "channel": $0.channel, "timestamp": $0.timestamp, "thread": $0.readTarget.thread ?? ""]
         }]
    }
    private(set) var status = "연결되지 않음"
    private(set) var connectionState: IntegrationConnectionState = .disabled
    var connectionIssue: String? { connectionState.notice(service: "Slack") ?? readSyncIssue }
    var readSyncIssue: String? { readSyncIssues.values.sorted().first }
    private(set) var channels: [SlackChannel] = []
    private var inbox = SlackInbox()
    var notices: [SlackNotice] { inbox.notices }
    var groups: [SlackNoticeGroup] { SlackNoticeGroup.grouped(notices) }
    private(set) var userID = ""
    private(set) var teamID = ""
    private var workspaceName = ""
    private var userNames: [String: String] = [:]
    private var metadataPending: Set<String> = []
    private var metadataRetryAt: [String: Date] = [:]
    private var credentials: SlackCredentials?
    private var socket: URLSessionWebSocketTask?
    private var worker: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var readSyncWorker: Task<Void, Never>?
    private var readSchedule = SlackReadSchedule()
    private var readSyncIssues: [SlackReadTarget: String] = [:]
    private var generation = UUID()
    private let session: URLSession
    private let loadCredentials: () throws -> SlackCredentials?
    private var readProbe: SlackReadProbe?
    private var restoringCredentials = false
    private var credentialRestoreTimedOut = false
    private var credentialRestoreDeadline: DispatchWorkItem?
    private let credentialRestoreTimeout: TimeInterval
    var preferences = SlackPreferences.load() {
        didSet { preferences.save(); inbox.filter(preferences: preferences); onChange?() }
    }
    var payloads: [StatePayload] { groups.compactMap { $0.payload(preferences: preferences, channels: channels, userNames: userNames) } }
    var hasCredentials: Bool { credentials != nil }
    @discardableResult
    func dismissNotices(_ ids: Set<String>) -> Bool {
        guard inbox.dismissNotifications(ids) else { return false }
        readSyncIssues = readSyncIssues.filter { target, _ in notices.contains { $0.readTarget == target } }
        onChange?()
        return true
    }
    init(session: URLSession = .shared, loadCredentials: @escaping () throws -> SlackCredentials? = SlackKeychain.read,
         preferences: SlackPreferences? = nil, credentialRestoreTimeout: TimeInterval = 10, readProbe: SlackReadProbe? = nil) {
        self.session = session
        self.loadCredentials = loadCredentials
        self.credentialRestoreTimeout = max(0.05, credentialRestoreTimeout)
        self.readProbe = readProbe
        if let preferences { self.preferences = preferences }
    }

    func restore() {
        guard !restoringCredentials else { return }
        restoringCredentials = true; credentialRestoreTimedOut = false
        let current = generation
        let load = loadCredentials
        connectionState = .connecting
        status = "Slack 키체인 확인 중…"
        onChange?()
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current, self.restoringCredentials else { return }
            self.credentialRestoreTimedOut = true
            self.connectionState = .failed
            self.status = "Slack 키체인 확인이 지연되고 있습니다. macOS의 키체인 접근 대화상자와 맥 잠금 상태를 확인해 주세요. 기존 요청을 기다리는 중이며 중복 요청하지 않습니다."
            self.onChange?()
        }
        credentialRestoreDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + credentialRestoreTimeout, execute: deadline)
        // 앱 업데이트 후 키체인 승인을 기다려도 Codex 상태 감시와 화면은 계속 동작한다.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try load() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == current else { return }
                self.restoringCredentials = false; self.credentialRestoreTimedOut = false
                self.credentialRestoreDeadline?.cancel(); self.credentialRestoreDeadline = nil
                switch result {
                case .success(let saved):
                    self.credentials = saved
                    if saved != nil { self.start() }
                    else { self.connectionState = .disabled; self.status = "연결되지 않음"; self.onChange?() }
                case .failure(let error):
                    self.status = error.localizedDescription
                    self.connectionState = .failed
                    self.onChange?()
                }
            }
        }
    }
    func reconnect() {
        if credentials != nil { start() } else { restore() }
    }
    func connect(userToken: String, appToken: String) throws {
        let value = (credentials ?? SlackCredentials(userToken: "", appToken: "")).updating(userToken: userToken, appToken: appToken)
        guard value.userToken.hasPrefix("xoxp-"), value.appToken.hasPrefix("xapp-"),
              !value.userToken.contains(where: { $0.isWhitespace }), !value.appToken.contains(where: { $0.isWhitespace }) else { throw SlackFailure.invalidTokens }
        try SlackKeychain.write(value)
        stop()
        credentials = value
        inbox = SlackInbox(); channels = []; userNames = [:]
        start()
    }
    func disconnect() throws {
        try SlackKeychain.delete()
        stop()
        credentials = nil
        inbox = SlackInbox(); channels = []; userNames = [:]; userID = ""; teamID = ""
        connectionState = .disabled
        status = "연결 해제됨 · 이 맥에 저장한 토큰을 삭제했습니다"
        onChange?()
    }
    func stop() {
        generation = UUID()
        restoringCredentials = false; credentialRestoreTimedOut = false
        credentialRestoreDeadline?.cancel(); credentialRestoreDeadline = nil
        metadataPending = []; metadataRetryAt = [:]
        worker?.cancel(); heartbeat?.cancel(); readSyncWorker?.cancel(); readSyncWorker = nil
        readSchedule = SlackReadSchedule(); readSyncIssues = [:]
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }
    func start() {
        stop()
        guard let credentials else { return }
        let current = generation
        connectionState = .connecting
        status = "Slack 연결 중…"; onChange?()
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            var delay: Double = 1
            while !Task.isCancelled && self.generation == current {
                do {
                    let auth = try await self.call("auth.test", token: credentials.userToken)
                    guard self.generation == current, !Task.isCancelled else { return }
                    guard let user = auth["user_id"] as? String, let team = auth["team_id"] as? String else { throw SlackFailure.response }
                    self.userID = user; self.teamID = team
                    self.workspaceName = auth["team"] as? String ?? ""
                    // Read-only HTTP sync remains alive while Socket Mode reconnects.
                    if self.readSyncWorker == nil { self.startReadSync(generation: current) }
                    // 먼저 이벤트 수신을 시작한다. 채널 목록은 별도 요청으로 갱신한다.
                    let connection = try await self.call("apps.connections.open", token: credentials.appToken)
                    guard self.generation == current, !Task.isCancelled else { return }
                    guard let rawURL = connection["url"] as? String, let url = URL(string: rawURL),
                          url.scheme == "wss", let host = url.host, host == "wss.slack.com" || host.hasSuffix(".slack.com") else { throw SlackFailure.response }
                    let ws = self.session.webSocketTask(with: url)
                    self.socket = ws; ws.resume()
                    self.heartbeat = Task { @MainActor [weak self, weak ws] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                            guard !Task.isCancelled, let self, self.generation == current, let ws else { return }
                            ws.sendPing { error in
                                if error != nil { ws.cancel(with: .goingAway, reason: nil) }
                            }
                        }
                    }
                    while !Task.isCancelled && self.generation == current {
                        let frame = try await ws.receive()
                        guard self.generation == current, !Task.isCancelled else { return }
                        let data: Data
                        switch frame { case .string(let value): data = Data(value.utf8); case .data(let value): data = value; @unknown default: continue }
                        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let envelope = object["envelope_id"] as? String {
                            let ack = try JSONSerialization.data(withJSONObject: ["envelope_id": envelope])
                            try await ws.send(.data(ack))
                            guard self.generation == current, !Task.isCancelled else { return }
                        }
                        switch object["type"] as? String {
                        case "hello":
                            delay = 1
                            self.connectionState = .connected
                            self.status = "연결됨 · \(auth["team"] as? String ?? "Slack") · 새 메시지 수신 대기"
                            self.onChange?()
                            Task { @MainActor [weak self] in await self?.refreshChannels() }
                        case "disconnect": throw SlackFailure.response
                        case "events_api":
                            if let payload = object["payload"] as? [String: Any] { self.accept(payload) }
                        default: break
                        }
                    }
                } catch {
                    guard self.generation == current, !Task.isCancelled else { return }
                    self.heartbeat?.cancel()
                    self.socket?.cancel(with: .goingAway, reason: nil); self.socket = nil
                    let failure = error as? SlackFailure
                    self.connectionState = failure?.retryDelay == nil && failure != nil ? .failed : .reconnecting
                    self.status = failure?.localizedDescription ?? "Slack 연결이 끊겼습니다. 자동으로 다시 연결합니다."
                    self.onChange?()
                    if let failure, failure.retryDelay == nil { return }
                    let wait = max(delay, failure?.retryDelay ?? 5)
                    do { try await Task.sleep(nanoseconds: UInt64(min(wait, 3600) * 1_000_000_000)) } catch { return }
                    delay = min(delay * 2, 60)
                }
            }
        }
    }
    func accept(_ payload: [String: Any]) {
        receivedEvents += 1
        defer { onDiagnosticsChange?() }
        if inbox.applyMessageChange(payload, userID: userID, teamID: teamID, preferences: preferences) {
            lastEventDisposition = "message-update"
            onChange?()
            return
        }
        lastEventDisposition = "filtered-or-duplicate"
        if let event = payload["event"] as? [String: Any], event["user"] as? String == userID {
            lastEventDisposition = "own-message-excluded"
        }
        let authorized = SlackNotice.authorizedEvent(payload, userID: userID, teamID: teamID) != nil
        let probe = authorized ? (readProbe?.consume(payload, userID: userID, now: ProcessInfo.processInfo.systemUptime) ?? false) : false
        guard let notice = SlackNotice.parse(payload, userID: userID, teamID: teamID, allowingOwnMessage: probe),
              inbox.accept(notice, preferences: preferences) else { return }
        acceptedEvents += 1; lastEventDisposition = probe ? "accepted-read-probe" : "accepted"
        onChange?()
        Task { @MainActor [weak self] in await self?.resolveMetadata(for: notice) }
    }
    func visibleConversationNoticeIDs(windowTitle: String) -> Set<String> {
        slackVisibleConversationNoticeIDs(notices, windowTitle: windowTitle, team: teamID,
                                          workspace: workspaceName, channels: channels, userNames: userNames)
    }
    /// 정확히 식별한 DM 창을 확인한 시점의 메시지만 해제한다. 서버 읽음 위치는 변경하지 않는다.
    @discardableResult
    func acknowledgeVisibleDirectMessages(_ noticeIDs: Set<String>) -> Bool {
        let ids = Set(notices.filter {
            noticeIDs.contains($0.id) && $0.team == teamID && $0.isDM && !$0.isGroupDM && $0.readTarget.thread == nil
        }.map(\.id))
        return dismissNotices(ids)
    }
    func prioritizeReadSync(_ noticeIDs: Set<String>) {
        let targets = Set(notices.filter { noticeIDs.contains($0.id) && $0.team == teamID }.map(\.readTarget))
        readSchedule.prioritize(targets, now: ProcessInfo.processInfo.systemUptime)
    }
    private func startReadSync(generation current: UUID) {
        readSyncWorker?.cancel()
        readSyncWorker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == current else { return }
                await self.refreshReadState()
                // 읽음 동기화 요청은 분당 최대 30회로 제한한다.
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }
    @MainActor
    private func refreshReadState() async {
        guard let credentials, !userID.isEmpty else { return }
        let current = generation
        let previousIssue = readSyncIssue
        let targets = Set(notices.filter { $0.team == teamID }.map(\.readTarget))
        readSyncIssues = readSyncIssues.filter { targets.contains($0.key) }
        guard let target = readSchedule.next(in: targets, now: ProcessInfo.processInfo.systemUptime) else {
            if previousIssue != readSyncIssue { onChange?() }
            return
        }
        var changed = false
        lastReadEvidence = ["channel": target.channel, "thread": target.thread ?? "", "result": "requested"]
        onDiagnosticsChange?()
        do {
            let result = try await call(target.method, token: credentials.userToken, parameters: target.parameters)
            guard generation == current, !Task.isCancelled else { return }
            if let marker = target.marker(in: result), slackTimestamp(marker) != nil {
                changed = inbox.applyReadMarker(marker, for: target)
                lastReadEvidence["result"] = "read-marker"; lastReadEvidence["marker"] = marker
                readSyncIssues.removeValue(forKey: target)
            } else {
                lastReadEvidence["result"] = "missing-marker"
                readSyncIssues[target] = "Slack에서 읽음 위치를 제공하지 않아 일부 알림을 유지합니다."
            }
        } catch {
            guard generation == current, !Task.isCancelled else { return }
            lastReadEvidence["result"] = "read-error"
            let failure = error as? SlackFailure
            let limited: Bool
            if case .rateLimit? = failure { limited = true } else { limited = false }
            let delay = failure?.retryDelay ?? 300
            readSchedule.retry(target, after: max(15, delay), now: ProcessInfo.processInfo.systemUptime, rateLimited: limited)
            if case .api("missing_scope")? = failure {
                readSyncIssues[target] = "Slack 읽음 동기화 권한이 부족합니다. 연결 안내의 im:read·mpim:read 등을 추가하고 Slack 앱을 다시 설치해 주세요."
            } else {
                readSyncIssues[target] = "Slack 읽음 상태를 확인하지 못했습니다. 알림을 유지하며 다시 확인합니다."
            }
        }
        onDiagnosticsChange?()
        if changed || previousIssue != readSyncIssue { onChange?() }
    }
    @MainActor
    private func resolveMetadata(for notice: SlackNotice) async {
        guard let credentials else { return }
        let current = generation
        var requests: [(String, String, [String: String])] = []
        var ids: Set<String> = [notice.user]
        if let regex = try? NSRegularExpression(pattern: "<@([A-Z0-9]+)>") {
            let range = NSRange(notice.text.startIndex..., in: notice.text)
            for match in regex.matches(in: notice.text, range: range).prefix(10) {
                if let range = Range(match.range(at: 1), in: notice.text) { ids.insert(String(notice.text[range])) }
            }
        }
        for id in ids where userNames[id] == nil && !id.hasPrefix("B") {
            requests.append(("user:" + id, "users.info", ["user": id]))
        }
        if !notice.isDM && !channels.contains(where: { $0.id == notice.channel }) {
            requests.append(("channel:" + notice.channel, "conversations.info", ["channel": notice.channel]))
        }
        for (key, method, parameters) in requests {
            guard generation == current else { return }
            if metadataPending.contains(key) || (metadataRetryAt[key] ?? .distantPast) > Date() { continue }
            metadataPending.insert(key)
            do {
                let result = try await call(method, token: credentials.userToken, parameters: parameters)
                guard generation == current else { return }
                if method == "users.info", let user = result["user"] as? [String: Any], let id = user["id"] as? String {
                    let profile = user["profile"] as? [String: Any] ?? [:]
                    let names = [profile["display_name"], profile["real_name"], user["name"]].compactMap { $0 as? String }
                    if let name = names.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                        if userNames.count >= 1000 { userNames.removeAll() }
                        userNames[id] = name
                    }
                } else if let channel = result["channel"] as? [String: Any], let id = channel["id"] as? String, let name = channel["name"] as? String,
                          !channels.contains(where: { $0.id == id }) {
                    channels.append(SlackChannel(id: id, name: name))
                }
                metadataPending.remove(key)
                onChange?()
            } catch {
                guard generation == current else { return }
                metadataPending.remove(key)
                let wait = (error as? SlackFailure)?.retryDelay ?? 300
                metadataRetryAt[key] = Date().addingTimeInterval(max(60, wait))
            }
        }
    }
    @MainActor
    func refreshChannels() async {
        guard let credentials, !userID.isEmpty else { return }
        let current = generation
        do {
            var cursor = ""
            var result: [SlackChannel] = []
            repeat {
                let page = try await call("users.conversations", token: credentials.userToken,
                    parameters: ["types": "public_channel,private_channel", "exclude_archived": "true", "limit": "200", "cursor": cursor])
                guard generation == current, !Task.isCancelled else { return }
                for item in page["channels"] as? [[String: Any]] ?? [] {
                    if let id = item["id"] as? String, let name = item["name"] as? String { result.append(SlackChannel(id: id, name: name)) }
                }
                cursor = (page["response_metadata"] as? [String: Any])?["next_cursor"] as? String ?? ""
            } while !cursor.isEmpty
            channels = result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            onChange?()
        } catch {
            guard generation == current else { return }
            status = "채널 목록을 불러오지 못했습니다. DM·멘션 수신은 유지됩니다. 권한을 확인하고 목록을 새로고침해 주세요."
            onChange?()
        }
    }
    func nativeMessageURL(for notice: SlackNotice) throws -> URL {
        guard notice.team == teamID, let url = notice.nativeMessageURL else { throw SlackFailure.response }
        return url
    }
    private func call(_ method: String, token: String, parameters: [String: String] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://slack.com/api/" + method)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SlackFailure.response }
        if http.statusCode == 429 { throw SlackFailure.rateLimit(Double(http.value(forHTTPHeaderField: "Retry-After") ?? "30") ?? 30) }
        guard http.statusCode == 200, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SlackFailure.response }
        guard object["ok"] as? Bool == true else { throw SlackFailure.api(object["error"] as? String ?? "unknown") }
        return object
    }
}
