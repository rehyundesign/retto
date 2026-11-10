import Foundation

/// Real SlackIntegration scheduling and URLSession parsing, with all HTTP isolated locally.
private final class SlackReadFixtureProtocol: URLProtocol {
    static let lock = NSLock()
    static var mode = "read"
    static var methods: [String] = []
    static var infoStarted = false
    private let requestLock = NSLock()
    private var cancelled = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "slack.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let method = request.url!.lastPathComponent
        Self.lock.lock()
        Self.methods.append(method)
        let mode = Self.mode
        if method == "conversations.info" { Self.infoStarted = true }
        Self.lock.unlock()
        let body: [String: Any]
        switch method {
        case "auth.test": body = ["ok": true, "user_id": "U_FIXTURE_ME", "team_id": "T_FIXTURE", "team": "Fixture"]
        // A stopped Socket transport must not stop independent HTTP read reconciliation.
        case "apps.connections.open": body = ["ok": false, "error": "invalid_auth"]
        case "users.info": body = ["ok": true, "user": ["id": "U_FIXTURE_OTHER", "name": "Fixture"]]
        case "conversations.info":
            if mode == "missing_scope" { body = ["ok": false, "error": "missing_scope"] }
            else if mode == "missing_marker" { body = ["ok": true, "channel": ["id": "D_FIXTURE", "unread_count": 0]] }
            else { body = ["ok": true, "channel": ["id": "D_FIXTURE", "last_read": "1800000000.000001"]] }
        default: body = ["ok": false, "error": "unexpected_method"]
        }
        let deliver = { [self] in
            requestLock.lock(); let stopped = cancelled; requestLock.unlock()
            guard !stopped else { return }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
            client?.urlProtocolDidFinishLoading(self)
        }
        if mode == "delayed", method == "conversations.info" { DispatchQueue.global().asyncAfter(deadline: .now() + 0.5, execute: deliver) }
        else { deliver() }
    }
    override func stopLoading() { requestLock.lock(); cancelled = true; requestLock.unlock() }
    static func reset(_ value: String) { lock.lock(); mode = value; methods = []; infoStarted = false; lock.unlock() }
    static func snapshot() -> ([String], Bool) { lock.lock(); defer { lock.unlock() }; return (methods, infoStarted) }
}

func checkSlackReadSyncIntegration(_ check: (Bool, String) -> Void) {
    let defaultsBefore = UserDefaults.standard.data(forKey: "RettoSlackPreferences")
    func wait(_ seconds: TimeInterval, until condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        return condition()
    }
    let event: [String: Any] = ["type": "event_callback", "team_id": "T_FIXTURE",
        "authorizations": [["user_id": "U_FIXTURE_ME", "team_id": "T_FIXTURE", "is_bot": false]],
        "event": ["type": "message", "channel": "D_FIXTURE", "channel_type": "im", "user": "U_FIXTURE_OTHER",
                  "ts": "1800000000.000001", "text": "synthetic read fixture"]]
    for mode in ["read", "missing_marker", "missing_scope", "delayed"] {
        SlackReadFixtureProtocol.reset(mode)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SlackReadFixtureProtocol.self]
        let session = URLSession(configuration: config)
        let integration = SlackIntegration(session: session,
            loadCredentials: { SlackCredentials(userToken: "xoxp-synthetic-fixture", appToken: "xapp-synthetic-fixture") },
            preferences: SlackPreferences())
        integration.restore()
        check(wait(2, until: { if case .failed = integration.connectionState { return true }; return false }), "\(mode): fixture Socket failure reached")
        integration.accept(event)
        check(integration.notices.count == 1, "\(mode): message enters production inbox")
        integration.prioritizeReadSync(Set(integration.notices.map(\.id)))
        check(integration.notices.count == 1, "\(mode): focused title alone never acknowledges unread messages")
        if mode == "read" {
            check(wait(4, until: { integration.notices.isEmpty }), "HTTP read clears production inbox while Socket is unavailable")
            check(integration.payloads.isEmpty, "HTTP read removes real badge payload")
        } else if mode == "delayed" {
            check(wait(4, until: { SlackReadFixtureProtocol.snapshot().1 }), "delayed read request started")
            integration.stop()
            RunLoop.main.run(until: Date().addingTimeInterval(0.7))
            check(integration.notices.count == 1, "cancelled generation cannot clear retained alerts")
        } else {
            check(wait(4, until: { integration.readSyncIssue != nil }), "\(mode): production read error is visible")
            check(integration.notices.count == 1, "\(mode): unconfirmed read preserves badge")
        }
        let metadata = String(data: try! JSONSerialization.data(withJSONObject: integration.diagnosticsSnapshot), encoding: .utf8)!
        check(!metadata.contains("synthetic read fixture") && !metadata.contains("xoxp-") && !metadata.contains("xapp-"), "\(mode): diagnostics exclude messages and credentials")
        integration.stop(); session.invalidateAndCancel()
        let methods = SlackReadFixtureProtocol.snapshot().0
        check(methods.contains("conversations.info"), "\(mode): actual read request was made")
        check(Set(methods).isSubset(of: ["auth.test", "apps.connections.open", "users.info", "conversations.info"]), "\(mode): no write API was invoked")
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [SlackReadFixtureProtocol.self]
    let session = URLSession(configuration: config)
    let integration = SlackIntegration(session: session,
        loadCredentials: { SlackCredentials(userToken: "xoxp-synthetic-fixture", appToken: "xapp-synthetic-fixture") },
        preferences: SlackPreferences())
    SlackReadFixtureProtocol.reset("missing_marker")
    integration.restore()
    _ = wait(2, until: { if case .failed = integration.connectionState { return true }; return false })
    integration.accept(event)
    let visibleIDs = Set(integration.notices.map(\.id))
    var newer = event
    var newerMessage = event["event"] as! [String: Any]
    newerMessage["ts"] = "1800000000.000002"
    newer["event"] = newerMessage
    integration.accept(newer)
    check(integration.acknowledgeVisibleDirectMessages(visibleIDs), "focused DM acknowledges displayed messages without server marker")
    check(integration.notices.count == 1 && integration.notices[0].timestamp == "1800000000.000002",
          "arrival after focus observation remains unread")
    integration.accept(event)
    check(integration.notices.count == 1, "acknowledged DM retransmission cannot restore its bubble")
    check(integration.dismissNotices(Set(integration.notices.map(\.id))) && integration.payloads.isEmpty,
          "successful Slack open clears both message and grouped bubble")
    integration.stop(); session.invalidateAndCancel()
    check(UserDefaults.standard.data(forKey: "RettoSlackPreferences") == defaultsBefore, "HTTP fixtures preserve user preferences")
}
