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
    var id: String { "slack:\(team):\(channel):\(timestamp)" }

    static func parse(_ payload: [String: Any], userID: String, teamID: String) -> SlackNotice? {
        guard payload["type"] as? String == "event_callback",
              payload["team_id"] as? String == teamID,
              let authorizations = payload["authorizations"] as? [[String: Any]],
              authorizations.contains(where: { $0["user_id"] as? String == userID && $0["is_bot"] as? Bool == false }),
              let event = payload["event"] as? [String: Any],
              event["type"] as? String == "message",
              event["hidden"] as? Bool != true,
              event["subtype"] == nil || ["file_share", "bot_message", "thread_broadcast", "me_message"].contains(event["subtype"] as? String ?? ""),
              let channel = event["channel"] as? String,
              let ts = event["ts"] as? String, ts.range(of: "^[0-9]{1,12}\\.[0-9]{1,6}$", options: .regularExpression) != nil,
              let text = event["text"] as? String else { return nil }
        let user = event["user"] as? String ?? event["bot_id"] as? String ?? ""
        guard !user.isEmpty, user != userID else { return nil }
        return SlackNotice(team: teamID, channel: channel, timestamp: ts, user: user,
                           text: text, isDM: ["im", "mpim"].contains(event["channel_type"] as? String ?? ""),
                           isMention: text.contains("<@\(userID)>"),
                           senderName: event["username"] as? String, isGroupDM: event["channel_type"] as? String == "mpim",
                           threadTimestamp: event["thread_ts"] as? String)
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
    func payload(preferences: SlackPreferences, channels: [SlackChannel], userNames: [String: String] = [:]) -> StatePayload? {
        let channelName = channels.first { $0.id == channel }?.name
        let sender = userNames[user] ?? senderName ?? user
        let title = isGroupDM ? "그룹 DM" : (isDM ? "DM · " + sender : channelName.map { "#" + $0 } ?? "#" + channel)
        var content = text
        for (id, name) in userNames { content = content.replacingOccurrences(of: "<@" + id + ">", with: "@" + name) }
        content = content.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        let body = preferences.preview ? "@" + sender + " " + String(content.prefix(3000)) : "Slack에 새 메시지가 도착했어요"
        let object: [String: Any] = ["state": "waving", "source": "slack", "sessionId": id,
            "projectName": "Slack", "sessionTitle": title, "lastAssistantMessage": body,
            "updatedAtMs": (Double(timestamp) ?? 0) * 1000, "attention": true]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(StatePayload.self, from: data)
    }
}

// 수신 순서와 재전송 여부를 분리한다. 설정에 맞지 않는 이벤트도 재전송 중복에서 제외한다.
struct SlackInbox {
    private(set) var notices: [SlackNotice] = []
    private var seenIDs: Set<String> = []
    private var seenOrder: [String] = []
    mutating func accept(_ notice: SlackNotice, preferences: SlackPreferences) -> Bool {
        guard !seenIDs.contains(notice.id) else { return false }
        seenIDs.insert(notice.id); seenOrder.append(notice.id)
        if seenOrder.count > 2000 { seenIDs.remove(seenOrder.removeFirst()) }
        guard notice.matches(preferences) else { return false }
        notices.append(notice)
        notices.sort { (Double($0.timestamp) ?? 0) < (Double($1.timestamp) ?? 0) }
        if notices.count > 100 { notices.removeFirst(notices.count - 100) }
        return true
    }
    mutating func filter(preferences: SlackPreferences) { notices.removeAll { !$0.matches(preferences) } }
}

// 상태와 수신 처리는 메인 큐에서만 변경한다. 재연결 전의 비동기 결과는 generation으로 제외한다.
final class SlackIntegration {
    var onChange: (() -> Void)?
    private(set) var status = "연결되지 않음"
    private(set) var connectionState: IntegrationConnectionState = .disabled
    var connectionIssue: String? { connectionState.notice(service: "Slack") }
    private(set) var channels: [SlackChannel] = []
    private var inbox = SlackInbox()
    var notices: [SlackNotice] { inbox.notices }
    private(set) var userID = ""
    private(set) var teamID = ""
    private var userNames: [String: String] = [:]
    private var metadataPending: Set<String> = []
    private var metadataRetryAt: [String: Date] = [:]
    private var credentials: SlackCredentials?
    private var socket: URLSessionWebSocketTask?
    private var worker: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var generation = UUID()
    private let session: URLSession
    private let loadCredentials: () throws -> SlackCredentials?
    private var restoringCredentials = false
    var preferences = SlackPreferences.load() {
        didSet { preferences.save(); inbox.filter(preferences: preferences); onChange?() }
    }
    var payloads: [StatePayload] { notices.compactMap { $0.payload(preferences: preferences, channels: channels, userNames: userNames) } }
    var hasCredentials: Bool { credentials != nil }
    init(session: URLSession = .shared, loadCredentials: @escaping () throws -> SlackCredentials? = SlackKeychain.read) {
        self.session = session
        self.loadCredentials = loadCredentials
    }

    func restore() {
        guard !restoringCredentials else { return }
        restoringCredentials = true
        let current = generation
        let load = loadCredentials
        connectionState = .connecting
        status = "Slack 키체인 확인 중…"
        onChange?()
        // 앱 업데이트 후 키체인 승인을 기다려도 Codex 상태 감시와 화면은 계속 동작한다.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Result { try load() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == current else { return }
                self.restoringCredentials = false
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
    private func stop() {
        generation = UUID()
        restoringCredentials = false
        metadataPending = []; metadataRetryAt = [:]
        worker?.cancel(); heartbeat?.cancel()
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
    private func accept(_ payload: [String: Any]) {
        guard let notice = SlackNotice.parse(payload, userID: userID, teamID: teamID),
              inbox.accept(notice, preferences: preferences) else { return }
        onChange?()
        Task { @MainActor [weak self] in await self?.resolveMetadata(for: notice) }
    }
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
