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
    let probeNonce = "72fe96d1-b628-4474-aeb0-28d5e4158518"
    var selfProbe = SlackReadProbe.fromArguments(["Retto", "--slack-read-probe", "D123", probeNonce], now: 10)!
    let probeEvent = event(text: selfProbe.text, user: "U_ME")
    check(SlackReadProbe.fromArguments(["Retto"]) == nil, "ordinary app launch never enables self-message probe")
    check(SlackReadProbe.fromArguments(["Retto", "--slack-read-probe", "C123", probeNonce]) == nil, "probe is restricted to a DM")
    check(SlackReadProbe.fromArguments(["Retto", "--slack-read-probe", "D123", "invalid"]) == nil, "probe requires a unique UUID")
    check(!selfProbe.consume(event(text: "different", user: "U_ME"), userID: "U_ME", now: 11), "probe never accepts another message")
    check(!selfProbe.consume(event(text: selfProbe.text, user: "U_OTHER"), userID: "U_ME", now: 11), "probe accepts only authenticated sender")
    var attributedProbe = SlackReadProbe.fromArguments(["Retto", "--slack-read-probe", "D123", probeNonce], now: 10)!
    check(attributedProbe.consume(event(text: attributedProbe.text + "\nSent using a Slack app", user: "U_ME"), userID: "U_ME", now: 11),
          "probe permits message provenance below its exact unique first line")
    check(selfProbe.consume(probeEvent, userID: "U_ME", now: 11), "exact self-DM probe is accepted once")
    check(!selfProbe.consume(probeEvent, userID: "U_ME", now: 12), "self-DM probe cannot be replayed")
    var expiredProbe = SlackReadProbe.fromArguments(["Retto", "--slack-read-probe", "D123", probeNonce], now: 10)!
    check(!expiredProbe.consume(probeEvent, userID: "U_ME", now: 191), "self-DM probe expires after three minutes")
    check(SlackNotice.parse(probeEvent, userID: "U_ME", teamID: "T123", allowingOwnMessage: true) != nil,
          "armed probe reaches normal message parsing")
    check(SlackNotice.parse(probeEvent, userID: "U_ME", teamID: "T123") == nil,
          "same self-DM is excluded in normal parsing")
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
    // Slack 앱에서 읽은 위치까지만 해제한다. 다른 대화·스레드는 유지한다.
    let readReply = SlackNotice(team: dm.team, channel: dm.channel, timestamp: "1800000000.123458",
                                user: dm.user, text: "reply", isDM: true, isMention: false, threadTimestamp: "1799999999.000001")
    let readTarget = dm.readTarget
    var readInbox = SlackInbox()
    _ = readInbox.accept(dm, preferences: enabled)
    let later = SlackNotice(team: dm.team, channel: dm.channel, timestamp: "1800000000.123457",
                                       user: dm.user, text: "later", isDM: true, isMention: false)
    _ = readInbox.accept(later, preferences: enabled)
    _ = readInbox.accept(readReply, preferences: enabled)
    let another = SlackNotice(team: "T123", channel: "D456", timestamp: dm.timestamp,
                              user: dm.user, text: "other", isDM: true, isMention: false)
    _ = readInbox.accept(another, preferences: enabled)
    check(!readInbox.applyReadMarker("nan", for: readTarget) && readInbox.notices.count == 4, "invalid read marker preserves notifications")
    check(!readInbox.applyReadMarker(dm.timestamp, for: SlackReadTarget(team: "T_OTHER", channel: dm.channel, thread: nil)), "other workspace read marker is isolated")
    check(readInbox.applyReadMarker(dm.timestamp, for: readTarget), "external Slack read removes matching message")
    check(readInbox.notices.map(\.id).contains(later.id), "next microsecond message remains unread")
    check(readInbox.notices.map(\.id).contains(another.id), "other conversation remains unread")
    // 채널 읽음 위치는 별도 스레드의 읽음으로 사용하지 않는다.
    check(readInbox.notices.map(\.id).contains(readReply.id), "channel read does not dismiss thread reply")
    check(!readInbox.applyReadMarker("1800000000.000001", for: readTarget), "older read position does not regress")
    check(readInbox.applyReadMarker(readReply.timestamp, for: readReply.readTarget), "thread read dismisses its reply")
    check(readInbox.notices.count == 2, "only read messages removed from badge source")
    let delayedNotice = SlackNotice(team: dm.team, channel: dm.channel, timestamp: "1800000000.123455",
                                   user: dm.user, text: "delayed", isDM: true, isMention: false)
    check(!readInbox.accept(delayedNotice, preferences: enabled), "delayed pre-read message is suppressed")
    check(!readInbox.accept(dm, preferences: enabled), "read message retry cannot restore notification")
    check(slackTimestamp("999999999999.999998")! < slackTimestamp("999999999999.999999")!, "timestamp comparison retains six-digit precision")
    let slackTitle = "general(채널) - Workspace - Slack"
    check(slackWindowShowsConversation(slackTitle, name: "general", workspace: "Workspace", isDM: false), "native Korean channel title matches")
    check(slackWindowShowsConversation("general (Channel) - Workspace - Slack", name: "general", workspace: "Workspace", isDM: false), "native English channel title matches")
    check(slackWindowShowsConversation("general(채널) - Workspace - 1개의 새 항목 - Slack", name: "general", workspace: "Workspace", isDM: false), "unread count suffix keeps focused channel identity")
    check(slackWindowShowsConversation("Alice(DM) - Workspace - 2 new items - Slack", name: "Alice", workspace: "Workspace", isDM: true), "English unread count suffix keeps DM identity")
    check(!slackWindowShowsConversation("general(채널) - Other - 1개의 새 항목 - Slack", name: "general", workspace: "Workspace", isDM: false), "unread suffix cannot hide mismatched workspace")
    check(!slackWindowShowsConversation(slackTitle, name: "general", workspace: "Other", isDM: false), "another workspace never clears alerts")
    check(!slackWindowShowsConversation(slackTitle, name: "gen", workspace: "Workspace", isDM: false), "partial channel title rejected")
    check(!slackWindowShowsConversation(slackTitle, name: "general", workspace: "Workspace", isDM: true), "DM cannot match channel")
    check(!slackWindowShowsConversation("Threads - Workspace - Slack", name: "general", workspace: "Workspace", isDM: false), "thread list cannot clear channel alerts")
    let focusedNotice = parse(event(type: "channel"))!
    let focusedChannels = [SlackChannel(id: focusedNotice.channel, name: "general")]
    let visibleIDs = slackVisibleConversationNoticeIDs([focusedNotice, readReply, another], windowTitle: slackTitle,
        team: "T123", workspace: "Workspace", channels: focusedChannels, userNames: [:])
    check(visibleIDs == [focusedNotice.id], "focused channel clears only its root notices, never thread or other DM")
    check(slackVisibleConversationNoticeIDs([focusedNotice], windowTitle: slackTitle,
        team: "T_OTHER", workspace: "Workspace", channels: focusedChannels, userNames: [:]).isEmpty, "focused workspace identity isolated")
    var sameNameEvent = event(type: "channel"); var sameNameMessage = sameNameEvent["event"] as! [String: Any]
    sameNameMessage["channel"] = "C_OTHER"; sameNameEvent["event"] = sameNameMessage
    let sameNameNotice = parse(sameNameEvent)!
    check(slackVisibleConversationNoticeIDs([focusedNotice, sameNameNotice], windowTitle: slackTitle,
        team: "T123", workspace: "Workspace", channels: focusedChannels + [SlackChannel(id: "C_OTHER", name: "general")], userNames: [:]).isEmpty,
        "ambiguous conversation names preserve all notices")
    check(slackVisibleConversationNoticeIDs([dm], windowTitle: "Alice(DM) - Workspace - Slack",
        team: "T123", workspace: "Workspace", channels: [], userNames: [dm.user: "Alice"]) == [dm.id], "direct DM opening matches resolved sender")
    var parent = dm; parent.threadTimestamp = parent.timestamp
    check(parent.readTarget == readTarget, "thread parent uses conversation read cursor")
    check(readTarget.method == "conversations.info" && readTarget.parameters == ["channel": dm.channel], "conversation sync uses read-only info request")
    check(readReply.readTarget.method == "conversations.replies" && readReply.readTarget.parameters["limit"] == "1", "thread sync requests parent only")
    check(readTarget.marker(in: ["channel": ["id": dm.channel, "last_read": dm.timestamp]]) == dm.timestamp, "conversation cursor parsed")
    check(readTarget.marker(in: ["channel": ["id": "D_OTHER", "last_read": dm.timestamp]]) == nil, "mismatched conversation cursor rejected")
    check(readTarget.marker(in: ["channel": ["id": dm.channel, "unread_count": 0]]) == nil, "unread count alone is not read evidence")
    check(readReply.readTarget.marker(in: ["messages": [["ts": readReply.threadTimestamp!, "last_read": dm.timestamp]]]) == dm.timestamp, "thread parent read cursor parsed")
    check(readReply.readTarget.marker(in: ["messages": [["ts": "other", "last_read": dm.timestamp]]]) == nil, "unrelated thread cursor rejected")
    var schedule = SlackReadSchedule()
    check(schedule.next(in: [readTarget], now: 100) == readTarget, "first pending conversation checked immediately")
    check(schedule.next(in: [readTarget], now: 114) == nil, "fresh conversation read not polled repeatedly")
    check(schedule.next(in: [readTarget], now: 115) == readTarget, "pending conversation checked again after fifteen seconds")
    schedule.retry(readTarget, after: 120, now: 116, rateLimited: true)
    check(schedule.next(in: [another.readTarget], now: 200) == nil, "rate limit delays entire info method")
    check(schedule.next(in: [another.readTarget], now: 237) == another.readTarget, "read sync resumes after retry-after")
    var focusSchedule = SlackReadSchedule()
    _ = focusSchedule.next(in: [readTarget], now: 100)
    focusSchedule.prioritize([readTarget], now: 103)
    check(focusSchedule.next(in: [readTarget], now: 103) == readTarget, "focused conversation advances server cursor check")
    focusSchedule.prioritize([readTarget], now: 104)
    check(focusSchedule.next(in: [readTarget], now: 106) == nil, "foreground polls remain bounded")
    focusSchedule.retry(readTarget, after: 120, now: 106, rateLimited: true)
    focusSchedule.prioritize([readTarget], now: 110)
    check(focusSchedule.next(in: [readTarget], now: 120) == nil, "focus never bypasses Slack Retry-After")
    var threadSchedule = SlackReadSchedule()
    check(threadSchedule.next(in: [readReply.readTarget], now: 100) == readReply.readTarget, "first pending thread checked")
    var otherThread = readReply; otherThread.threadTimestamp = "1799999998.000001"
    check(threadSchedule.next(in: [otherThread.readTarget], now: 101) == nil, "thread calls are spaced by two seconds")
    check(threadSchedule.next(in: [otherThread.readTarget], now: 102) == otherThread.readTarget, "next thread no longer waits a full minute")
    func mutation(_ subtype: String, timestamp: String = dm.timestamp, text: String = "edited",
                  version: String = "1800000010.000001", channel: String = "D123") -> [String: Any] {
        var value = event()
        value["event"] = ["type": "message", "subtype": subtype, "hidden": true,
                          "channel": channel, "ts": version, "event_ts": version,
                          "deleted_ts": timestamp,
                          "message": ["type": "message", "ts": timestamp, "text": text, "user": "U_OTHER"]]
        return value
    }
    var changes = SlackInbox()
    _ = changes.accept(dm, preferences: enabled)
    _ = changes.accept(another, preferences: enabled)
    check(changes.applyMessageChange(mutation("message_changed"), userID: "U_ME", teamID: "T123", preferences: enabled), "Slack edit updates pending notification")
    let edited = changes.notices.first(where: { $0.id == dm.id })!
    check(edited.text == "edited" && edited.id == dm.id, "edit replaces text without creating notification")
    check(edited.timestamp == dm.timestamp && edited.readTarget == dm.readTarget, "edit preserves read identity and time")
    check(edited.payload(preferences: enabled, channels: [])?.updatedAtMs == dm.payload(preferences: enabled, channels: [])?.updatedAtMs, "edit does not create a new attention timestamp")
    check(!changes.applyMessageChange(mutation("message_changed", text: "older", version: "1800000009.000001"), userID: "U_ME", teamID: "T123", preferences: enabled), "out-of-order edit cannot restore stale text")
    check(!changes.applyMessageChange(mutation("message_changed"), userID: "U_ME", teamID: "T123", preferences: enabled), "duplicate edit is ignored")
    var foreignMutation = mutation("message_deleted"); foreignMutation["team_id"] = "T_OTHER"
    check(!changes.applyMessageChange(foreignMutation, userID: "U_ME", teamID: "T123", preferences: enabled), "other workspace cannot delete notice")
    foreignMutation = mutation("message_deleted"); foreignMutation["authorizations"] = [["user_id": "U_OTHER", "is_bot": false]]
    check(!changes.applyMessageChange(foreignMutation, userID: "U_ME", teamID: "T123", preferences: enabled), "other authorization cannot delete notice")
    check(changes.applyMessageChange(mutation("message_deleted"), userID: "U_ME", teamID: "T123", preferences: enabled), "hidden deletion removes original message using deleted_ts")
    check(changes.notices.map(\.id) == [another.id], "deletion leaves other conversations intact")
    check(!changes.accept(dm, preferences: enabled), "deleted message retry stays suppressed")
    check(!changes.applyMessageChange(mutation("message_changed", version: "1800000011.000001"), userID: "U_ME", teamID: "T123", preferences: enabled), "edit cannot recreate deleted notice")
    var deleteBeforeDelivery = SlackInbox()
    _ = deleteBeforeDelivery.applyMessageChange(mutation("message_deleted"), userID: "U_ME", teamID: "T123", preferences: enabled)
    check(!deleteBeforeDelivery.accept(dm, preferences: enabled), "deletion before delivery prevents stale message")
    var mentionChanges = SlackInbox()
    _ = mentionChanges.accept(mention, preferences: enabled)
    check(mentionChanges.applyMessageChange(mutation("message_changed", text: "mention removed"), userID: "U_ME", teamID: "T123", preferences: enabled) && mentionChanges.notices.isEmpty, "removing personal mention clears unselected channel notice")
    var selectedPreferences = enabled; selectedPreferences.channelIDs.insert("D123")
    var selectedChanges = SlackInbox(); _ = selectedChanges.accept(mention, preferences: selectedPreferences)
    _ = selectedChanges.applyMessageChange(mutation("message_changed", text: "mention removed"), userID: "U_ME", teamID: "T123", preferences: selectedPreferences)
    check(selectedChanges.notices.count == 1 && !selectedChanges.notices[0].isMention, "selected channel keeps edited nonmention")
    var dismissed = SlackInbox(); _ = dismissed.accept(dm, preferences: enabled); _ = dismissed.accept(another, preferences: enabled)
    check(dismissed.dismiss([dm.id]) && dismissed.notices.map(\.id) == [another.id], "local read removes only chosen pending notice")
    check(!Set(dismissed.notices.map(\.readTarget)).contains(dm.readTarget), "locally read conversation no longer consumes read polls")
    check(!dismissed.accept(dm, preferences: enabled), "local read remains deduplicated on reconnect")
    check(!dismissed.applyMessageChange(mutation("message_changed"), userID: "U_ME", teamID: "T123", preferences: enabled), "edit cannot restore locally dismissed notice")
    check(dismissed.dismiss([another.id]) && dismissed.notices.isEmpty, "clear all removes pending Slack notices")
    check(!dismissed.dismiss([another.id]), "repeat dismissal has no side effect")
    let pair = SlackNoticeGroup.grouped([later, dm])
    check(pair.count == 1 && pair[0].messages.count == 2, "same sender in one conversation becomes one notification")
    check(pair[0].first.id == dm.id && pair[0].latest.id == later.id, "group opens earliest unread and previews latest message")
    let pairPayload = pair[0].payload(preferences: enabled, channels: [], userNames: [dm.user: "민수"])!
    check(pairPayload.title == "DM · 민수 +2", "plus two means two total messages")
    check(pairPayload.lastAssistantMessage == "@민수 later", "group preview contains latest message")
    check(pairPayload.id == pair[0].id && pairPayload.id != dm.id && pairPayload.id != later.id, "group has its own stable notification identity")
    check(pairPayload.updatedAtMs == later.payload(preferences: enabled, channels: [])?.updatedAtMs, "latest message controls group recency")
    check(sessionMenuLabel(for: pairPayload).contains("+2"), "menu uses grouped count")
    let singleGroup = SlackNoticeGroup.grouped([dm])[0]
    check(singleGroup.id == pair[0].id && !singleGroup.payload(preferences: enabled, channels: [])!.title.contains("+"), "single message has stable group ID without count suffix")
    let third = SlackNotice(team: dm.team, channel: dm.channel, timestamp: "1800000000.123459", user: dm.user, text: "third", isDM: true, isMention: false)
    let triple = SlackNoticeGroup.grouped([third, later, dm])[0]
    check(triple.payload(preferences: enabled, channels: [])!.title.hasSuffix("+3"), "third message increments total count")
    var privatePreferences = enabled; privatePreferences.preview = false
    let hiddenGroup = triple.payload(preferences: privatePreferences, channels: [])!
    check(hiddenGroup.lastAssistantMessage == "Slack에 새 메시지 3개가 도착했어요", "preview-off retains count and hides content")
    let otherSender = SlackNotice(team: dm.team, channel: dm.channel, timestamp: "1800000000.123460", user: "U_ANOTHER", text: "another sender", isDM: true, isMention: false)
    check(SlackNoticeGroup.grouped([dm, otherSender]).count == 2, "different senders remain separate")
    check(SlackNoticeGroup.grouped([dm, another]).count == 2, "same sender in different conversations stays separate")
    let otherWorkspace = SlackNotice(team: "T_OTHER", channel: dm.channel, timestamp: dm.timestamp, user: dm.user, text: "other team", isDM: true, isMention: false)
    check(SlackNoticeGroup.grouped([dm, otherWorkspace]).count == 2, "same sender ID in different workspaces stays separate")
    check(SlackNoticeGroup.grouped([dm, readReply]).count == 2, "channel and thread notices stay separate")
    check(SlackNoticeGroup.grouped([readReply, otherThread]).count == 2, "different threads stay separate")
    let namedChannelGroup = SlackNoticeGroup.grouped([mention])[0].payload(preferences: enabled,
        channels: [SlackChannel(id: mention.channel, name: "product")], userNames: [mention.user: "민수"])!
    check(namedChannelGroup.title == "#product · 민수", "channel groups identify sender in menu")
    var groupedInbox = SlackInbox()
    for notice in [dm, later, third, another] { _ = groupedInbox.accept(notice, preferences: enabled) }
    _ = groupedInbox.applyReadMarker(dm.timestamp, for: dm.readTarget)
    let partiallyRead = SlackNoticeGroup.grouped(groupedInbox.notices).first { $0.id == triple.id }!
    check(partiallyRead.messages.count == 2 && partiallyRead.payload(preferences: enabled, channels: [])!.title.hasSuffix("+2"), "partial external read reduces group count")
    _ = groupedInbox.applyMessageChange(mutation("message_deleted", timestamp: later.timestamp), userID: "U_ME", teamID: "T123", preferences: enabled)
    let afterDeletion = SlackNoticeGroup.grouped(groupedInbox.notices).first { $0.id == triple.id }!
    check(afterDeletion.messages.count == 1 && !afterDeletion.payload(preferences: enabled, channels: [])!.title.contains("+"), "deleting message updates grouped count")
    check(groupedInbox.dismissNotifications([triple.id]) && groupedInbox.notices.map(\.id) == [another.id], "dismissing group removes all its messages only")
    var arrivalDuringOpen = SlackInbox()
    _ = arrivalDuringOpen.accept(dm, preferences: enabled); _ = arrivalDuringOpen.accept(later, preferences: enabled)
    let openedIDs = SlackNoticeGroup.grouped(arrivalDuringOpen.notices)[0].messageIDs
    _ = arrivalDuringOpen.accept(third, preferences: enabled)
    _ = arrivalDuringOpen.dismissNotifications(openedIDs)
    check(arrivalDuringOpen.notices.map(\.id) == [third.id], "new arrival during Slack launch remains unread")
    var burst = SlackInbox()
    for offset in 1...40 {
        _ = burst.accept(SlackNotice(team: dm.team, channel: dm.channel, timestamp: "1800000001.\(String(format: "%06d", offset))",
                                    user: dm.user, text: "burst", isDM: true, isMention: false), preferences: enabled)
    }
    check(SlackNoticeGroup.grouped(burst.notices).count == 1 && SlackNoticeGroup.grouped(burst.notices)[0].messages.count == 40, "forty-message burst produces one notification row")
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
    var timedLoadCount = 0
    let timedRestore = SlackIntegration(loadCredentials: {
        timedLoadCount += 1
        Thread.sleep(forTimeInterval: 0.3)
        return nil
    }, credentialRestoreTimeout: 0.05)
    timedRestore.restore()
    let warningDeadline = Date().addingTimeInterval(0.2)
    while timedRestore.diagnosticsSnapshot["credentialRestoreTimedOut"] as? Bool != true, Date() < warningDeadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    check(timedRestore.connectionState == .failed, "keychain timeout stops showing an indefinite healthy connection attempt")
    check(timedRestore.diagnosticsSnapshot["credentialRestorePending"] as? Bool == true, "blocking keychain request remains observable")
    timedRestore.reconnect()
    check(timedLoadCount == 1, "keychain timeout never creates duplicate security requests")
    let lateDeadline = Date().addingTimeInterval(1)
    while timedRestore.connectionState != .disabled, Date() < lateDeadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    check(timedRestore.connectionState == .disabled && timedRestore.diagnosticsSnapshot["credentialRestoreTimedOut"] as? Bool == false,
          "late keychain completion recovers from timeout warning")
    timedRestore.stop()
    let window = SlackSettingsWindow(integration: integration)
    if let index = CommandLine.arguments.firstIndex(of: "--slack-settings-preview"), index + 1 < CommandLine.arguments.count {
        check(window.renderPreview(to: CommandLine.arguments[index + 1]), "settings rendering")
    }
    if let index = CommandLine.arguments.firstIndex(of: "--slack-notice-preview"), index + 1 < CommandLine.arguments.count {
        check(renderSlackNoticePreview(pairPayload, to: CommandLine.arguments[index + 1]), "grouped notification rendering")
    }
    checkSlackReadSyncIntegration(check)
    print("Slack: \(checks) checks, \(failures.count) failures")
    for failure in failures { print("FAIL: " + failure) }
    return failures.isEmpty ? 0 : 1
}

func renderSlackNoticePreview(_ payload: StatePayload, to path: String) -> Bool {
    _ = registerRettoFont()
    guard let url = Bundle.main.url(forResource: "spritesheet", withExtension: "webp"), let image = NSImage(contentsOf: url) else { return false }
    let size = petLayout(scale: 1).windowSize
    let view = RettoView(frame: NSRect(origin: .zero, size: size), spriteSheet: image, onOpenClaude: { _,_ in }, onOpenAttention: { _ in })
    view.apply(payload, sessionCount: 1, attentionCount: 1, attentionState: .waving, attentionSource: "slack", isPinned: false)
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
