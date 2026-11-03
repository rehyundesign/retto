import AppKit
import Foundation

func runSlackSelfTest() -> Int32 {
    var checks = 0
    var failures: [String] = []
    func check(_ value: Bool, _ name: String) { checks += 1; if !value { failures.append(name) } }
    func event(text: String = "hello", user: String = "U_OTHER", type: String = "im", subtype: String? = nil) -> [String: Any] {
        var message: [String: Any] = ["type": "message", "channel": "D123", "channel_type": type,
                                      "user": user, "ts": "1800000000.123456", "text": text]
        if let subtype { message["subtype"] = subtype }
        return ["type": "event_callback", "team_id": "T123", "event": message,
                "authorizations": [["user_id": "U_ME", "is_bot": false, "team_id": "T123"]]]
    }
    func parse(_ value: [String: Any]) -> SlackNotice? { SlackNotice.parse(value, userID: "U_ME", teamID: "T123") }
    let dm = parse(event())!
    var prefs = SlackPreferences()
    check(dm.matches(prefs), "DM enabled")
    prefs.directMessages = false
    check(!dm.matches(prefs), "DM disabled")
    let mention = parse(event(text: "hello <@U_ME>", type: "channel"))!
    check(mention.matches(prefs), "personal mention")
    check(!parse(event(text: "hello <@U_ME_OTHER>", type: "channel"))!.matches(prefs), "exact user ID")
    prefs.mentions = false
    check(!mention.matches(prefs), "mentions disabled")
    prefs.channelIDs.insert("D123")
    check(mention.matches(prefs), "selected channel")
    check(parse(event(type: "channel"))!.matches(prefs), "all selected channel messages")
    check(parse(event(user: "U_ME")) == nil, "own message ignored")
    check(parse(event(subtype: "message_changed")) == nil, "edit ignored")
    check(parse(event(subtype: "message_deleted")) == nil, "delete ignored")
    check(parse(event(subtype: "channel_join")) == nil, "system event ignored")
    check(parse(event(subtype: "file_share")) != nil, "file share accepted")
    check(parse(event(subtype: "thread_broadcast")) != nil, "thread broadcast accepted")
    check(parse(event(subtype: "me_message")) != nil, "action message accepted")
    check(parse(event(type: "mpim"))?.isDM == true, "group DM")
    var otherTeam = event(); otherTeam["team_id"] = "T_OTHER"
    check(parse(otherTeam) == nil, "other workspace excluded")
    var otherAuthorization = event(); otherAuthorization["authorizations"] = [["user_id": "U_OTHER", "is_bot": false]]
    check(parse(otherAuthorization) == nil, "other user's authorization excluded")
    var noAuthorization = event(); noAuthorization.removeValue(forKey: "authorizations")
    check(parse(noAuthorization) == nil, "missing authorization excluded")
    var malformed = event(); var malformedMessage = malformed["event"] as! [String: Any]
    malformedMessage["ts"] = "nan"; malformed["event"] = malformedMessage
    check(parse(malformed) == nil, "non-finite timestamp excluded")
    let payload = dm.payload(preferences: prefs, channels: [])!
    check(payload.sourceLabel == "Slack" && payload.needsAttention && payload.petState == .waving, "overlay state")
    check(payload.id == dm.id && payload.lastAssistantMessage == "@U_OTHER hello", "message identity")
    check(sessionMenuLabel(for: payload).contains("새 메시지"), "Slack menu label")
    prefs.preview = false
    check(dm.payload(preferences: prefs, channels: [])?.lastAssistantMessage == "Slack에 새 메시지가 도착했어요", "preview hides content")
    let native = URLComponents(url: dm.nativeMessageURL!, resolvingAgainstBaseURL: false)!
    check(native.scheme == "slack" && native.host == "channel", "native app scheme only")
    check(native.queryItems?.first(where: { $0.name == "team" })?.value == dm.team, "native workspace")
    check(native.queryItems?.first(where: { $0.name == "id" })?.value == dm.channel, "native DM conversation")
    check(native.queryItems?.first(where: { $0.name == "message" })?.value == dm.timestamp, "native message timestamp")
    var replyEvent = event(); var reply = replyEvent["event"] as! [String: Any]
    reply["thread_ts"] = "1799999999.000001"; replyEvent["event"] = reply
    let threadNotice = parse(replyEvent)!
    let threadURL = URLComponents(url: threadNotice.nativeMessageURL!, resolvingAgainstBaseURL: false)!
    check(threadURL.queryItems?.first(where: { $0.name == "thread_ts" })?.value == "1799999999.000001", "native thread context")
    let malformedTarget = SlackNotice(team: "T123&id=OTHER", channel: "D123", timestamp: dm.timestamp, user: "U_OTHER", text: "test", isDM: true, isMention: false)
    check(malformedTarget.nativeMessageURL == nil, "invalid native target rejected")
    let channelTarget = SlackNotice(team: "T123", channel: "C123", timestamp: dm.timestamp, user: "U_OTHER", text: "test", isDM: false, isMention: true)
    check(channelTarget.nativeMessageURL?.scheme == "slack", "channel never uses HTTPS")
    let roundTrip = try! JSONDecoder().decode(SlackPreferences.self, from: JSONEncoder().encode(prefs))
    check(roundTrip.channelIDs == prefs.channelIDs && !roundTrip.preview, "preferences serialization")
    check(SlackFailure.api("token_revoked").retryDelay == nil, "invalid auth stops retry")
    check(SlackFailure.rateLimit(120).retryDelay == 120, "rate limit delay")
    check(!SlackFailure.api("xoxp-secret").localizedDescription.contains("secret"), "error redaction")
    var inbox = SlackInbox()
    let enabled = SlackPreferences()
    check(inbox.accept(dm, preferences: enabled), "new notice accepted")
    check(!inbox.accept(dm, preferences: enabled) && inbox.notices.count == 1, "Slack retry deduplicated")
    for offset in 1...110 {
        let notice = SlackNotice(team: dm.team, channel: dm.channel, timestamp: "1800000001.\(offset)", user: dm.user,
                                 text: "message", isDM: true, isMention: false)
        _ = inbox.accept(notice, preferences: enabled)
    }
    check(inbox.notices.count == 100 && !inbox.notices.contains(where: { $0.id == dm.id }), "bounded inbox")
    var disabled = SlackPreferences(); disabled.directMessages = false; disabled.mentions = false
    inbox.filter(preferences: disabled)
    check(inbox.notices.isEmpty, "disabled notifications removed")
    var suppressed = SlackInbox()
    check(!suppressed.accept(dm, preferences: disabled), "disabled event suppressed")
    check(!suppressed.accept(dm, preferences: enabled), "retry does not restore suppressed event")
    let channelNotice = parse(event(text: "<@U_ME> 확인해 주세요", type: "channel"))!
    let named = channelNotice.payload(preferences: enabled, channels: [SlackChannel(id: "D123", name: "product")],
                                      userNames: ["U_OTHER": "민수", "U_ME": "나"])!
    check(named.title == "#product", "channel title")
    check(named.lastAssistantMessage == "@민수 @나 확인해 주세요", "sender prefix and mention names")
    check(dm.payload(preferences: enabled, channels: [], userNames: ["U_OTHER": "민수"])?.title == "DM · 민수", "DM partner title")
    check(notificationTone(source: "slack", state: .waving, fallback: toneDone).key == "slack", "Slack purple")
    check(notificationTone(source: "slack", state: .idle, fallback: toneQuiet).key == "quiet", "read Slack quiet")
    check(notificationTone(source: "codex", state: .waving, fallback: toneDone).key == "done", "AI completion orange")
    let slackPriority = selectionPriority(state: .waving, isClosed: false, source: "slack")
    check(slackPriority > selectionPriority(state: .waving, isClosed: false), "Slack before completion")
    check(selectionPriority(state: .waiting, isClosed: false) > slackPriority, "input required before Slack")
    check(selectionPriority(state: .idle, isClosed: false, source: "slack") < selectionPriority(state: .waving, isClosed: false), "read Slack does not preempt completion")
    // 실제 Codex 완료 payload를 고정해도 읽지 않은 Slack 알림이 우선한다.
    let doneData = Data("{\"state\":\"waving\",\"source\":\"codex\",\"sessionId\":\"done\",\"attention\":true}".utf8)
    let done = try! JSONDecoder().decode(StatePayload.self, from: doneData)
    func priority(_ p: StatePayload) -> Int { selectionPriority(state: p.petState, isClosed: p.isClosed, source: p.source) }
    check(preferredPinnedSession(done, attention: [named, done], priority: priority, needsAttention: { $0.needsAttention }).id == named.id,
          "Slack overrides pinned completion")
    check(preferredPinnedSession(done, attention: [], priority: priority, needsAttention: { $0.needsAttention }).id == done.id,
          "pinned completion remains without Slack")
    // 키체인과 네트워크에 접근하지 않는 검사.
    let original = SlackCredentials(userToken: "xoxp-existing", appToken: "xapp-existing")
    let updated = original.updating(userToken: "xoxp-new", appToken: " ")
    check(updated.userToken == "xoxp-new" && updated.appToken == "xapp-existing", "refresh user auth preserves socket auth")
    let integration = SlackIntegration()
    check(!integration.hasCredentials && integration.payloads.isEmpty, "disconnected state")
    var loadCount = 0
    let delayed = SlackIntegration(loadCredentials: {
        loadCount += 1
        Thread.sleep(forTimeInterval: 0.25)
        return nil
    })
    var callbacksOnMain = true
    delayed.onChange = { callbacksOnMain = callbacksOnMain && Thread.isMainThread }
    let restoreStarted = Date()
    delayed.restore()
    check(Date().timeIntervalSince(restoreStarted) < 0.15, "keychain wait does not block app startup")
    delayed.restore()
    let restoreDeadline = Date().addingTimeInterval(2)
    while delayed.connectionState == .connecting && Date() < restoreDeadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    check(loadCount == 1, "reconnect while keychain is pending does not duplicate requests")
    check(callbacksOnMain && delayed.connectionState == .disabled, "credential result returns to main queue")
    let window = SlackSettingsWindow(integration: integration)
    if let index = CommandLine.arguments.firstIndex(of: "--slack-settings-preview"), index + 1 < CommandLine.arguments.count {
        check(window.renderPreview(to: CommandLine.arguments[index + 1]), "settings rendering")
    }
    if let index = CommandLine.arguments.firstIndex(of: "--slack-notice-preview"), index + 1 < CommandLine.arguments.count {
        check(renderSlackNoticePreview(named, to: CommandLine.arguments[index + 1]), "notification rendering")
    }
    print("Slack: \(checks) checks, \(failures.count) failures")
    for failure in failures { print("FAIL: " + failure) }
    return failures.isEmpty ? 0 : 1
}

func renderSlackNoticePreview(_ payload: StatePayload, to path: String) -> Bool {
    _ = registerRettoFont()
    guard let url = Bundle.main.url(forResource: "spritesheet", withExtension: "webp"), let image = NSImage(contentsOf: url) else { return false }
    let size = petLayout(scale: 1).windowSize
    let view = RettoView(frame: NSRect(origin: .zero, size: size), spriteSheet: image, onOpenClaude: { _,_ in }, onOpenAttention: { _ in })
    view.apply(payload, sessionCount: 3, attentionCount: 3, attentionState: .waving, attentionSource: "slack", isPinned: false)
    view.settleAnimations()
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep) else { return false }
    rep.size = size
    context.cgContext.scaleBy(x: 2, y: 2)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    NSColor.white.setFill(); view.bounds.fill(); view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else { return false }
    do { try data.write(to: URL(fileURLWithPath: path)); return true } catch { return false }
}
