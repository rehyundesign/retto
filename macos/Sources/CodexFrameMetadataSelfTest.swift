import Foundation

func checkCodexFrameMetadata(_ check: (Bool, String) -> Void) {
    let standard = #"{"type":"broadcast","method":"thread-stream-state-changed","sourceClientId":"owner","version":11,"targetClientIds":["reader"],"params":{"hostId":"local","conversationId":"thread","change":{"type":"snapshot","revision":7,"conversationState":{"title":"not retained"}}}}"#
    let expected = CodexFrameRoute(method: "thread-stream-state-changed", conversationID: "thread", hostID: "local",
        sourceClientID: "owner", targetClientIDs: ["reader"], version: 11, revision: 7, changeType: "snapshot", messageType: "broadcast")
    var scanner = CodexFrameMetadata()
    scanner.consume(Data(standard.utf8))
    check(scanner.route == expected, "frame metadata reads native route without retaining conversation fields")

    for width in [1, 2, 3, 7, 64, 4096] {
        var fragmented = CodexFrameMetadata()
        let data = Data(standard.utf8)
        for offset in stride(from: 0, to: data.count, by: width) {
            fragmented.consume(data.subdata(in: offset..<min(data.count, offset + width)))
        }
        check(fragmented.route == expected, "frame metadata survives \(width)-byte fragments")
    }

    let reordered = #"{"params":{"change":{"conversationState":{"conversationId":"spoof","hostId":"remote","sourceClientId":"fake","targetClientIds":["wrong"],"revision":999},"revision":7,"type":"snapshot"},"conversationId":"thread","hostId":"local"},"version":11,"sourceClientId":"owner","targetClientIds":["reader"],"method":"thread-stream-state-changed","type":"broadcast"}"#
    var orderIndependent = CodexFrameMetadata()
    for byte in reordered.utf8 { orderIndependent.consume(Data([byte])) }
    check(orderIndependent.route == expected, "body-before-header ordering and nested fake IDs do not change routing")

    let escaped = #"{"method":"thread-stream-state-changed","sourceClientId":"owner\\two","params":{"conversation\u0049d":"thread-\uD83D\uDE00","hostId":"local","change":{"type":"patches","revision":123}},"targetClientIds":["other-reader","r\"eader"],"version":11}"#
    var escapes = CodexFrameMetadata()
    for byte in escaped.utf8 { escapes.consume(Data([byte])) }
    check(escapes.route?.conversationID == "thread-😀", "metadata decodes escaped keys and surrogate pairs across fragments")
    check(escapes.route?.sourceClientID == "owner\\two" && escapes.route?.targetClientIDs == ["other-reader", "r\"eader"],
          "metadata preserves escaped owner and foreign target identities")
    check(escapes.route?.revision == 123 && escapes.route?.changeType == "patches", "patch routing captures numeric revision")

    var remote = CodexFrameMetadata()
    remote.consume(Data(#"{"method":"thread-stream-state-changed","params":{"hostId":"remote","conversationId":"thread"},"targetClientIds":[]}"#.utf8))
    check(remote.route?.hostID == "remote" && remote.route?.targetClientIDs == [], "remote and empty-target frames remain distinguishable from a local broadcast")
    var request = CodexFrameMetadata()
    request.consume(Data(#"{"method":"thread-stream-state-changed","params":{"hostId":"local","conversationId":"thread","change":{"type":"snapshot"}},"type":"request"}"#.utf8))
    check(request.route?.messageType == "request" && request.route?.changeType == "snapshot", "root request type cannot be confused with change type")

    let malformed = [
        standard + " {}",
        String(standard.dropLast()),
        #"{"method":"one","method":"two","params":{"hostId":"local","conversationId":"thread"}}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread","conversationId":"other"}}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"params":{"hostId":"local","conversationId":"other"}}"#,
        #"{"method":true,"params":{"hostId":"local","conversationId":"thread"}}"#,
        #"{"method":"one","params":{"hostId":7,"conversationId":"thread"}}"#,
        #"{"method":"one","params":"wrong"}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"targetClientIds":null}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"targetClientIds":["reader",false]}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"version":11.0}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"padding":[1,]}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"padding":01}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"padding":truefalse}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"padding":"\q"}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"padding":"\uD800"}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"padding":"\uDE00"}"#,
        #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"padding":{"a":2]}"#,
        "[]"
    ]
    for (index, value) in malformed.enumerated() {
        var invalid = CodexFrameMetadata()
        invalid.consume(Data(value.utf8))
        check(invalid.route == nil, "malformed or ambiguous frame metadata \(index) is rejected")
    }

    let future = standard.replacingOccurrences(of: "\"version\":11", with: "\"version\":12")
    for value in ["\"11\"", "null", "true", "1.5", "1e2", "[11]", "{\"value\":11}",
                  "\"" + String(repeating: "x", count: 5000) + "\""] {
        var metadata = CodexFrameMetadata()
        metadata.consume(Data(future.replacingOccurrences(of: "\"revision\":7", with: "\"revision\":" + value).utf8))
        check(metadata.route?.version == 12 && metadata.route?.conversationID == "thread" && metadata.route?.revision == nil,
              "future revision values preserve stable routing without assuming supported numeric semantics")
    }
    for value in ["null", "false", "{\"futureKind\":true}", "\"" + String(repeating: "x", count: 5000) + "\""] {
        var metadata = CodexFrameMetadata()
        metadata.consume(Data(future.replacingOccurrences(of: "\"type\":\"snapshot\"", with: "\"type\":" + value).utf8))
        check(metadata.route?.version == 12 && metadata.route?.conversationID == "thread" && metadata.route?.changeType == nil,
              "future change kinds do not erase stable protocol routing")
    }
    for value in ["null", "false", "\"future-change\"", "[1,2,3]"] {
        var object = try! JSONSerialization.jsonObject(with: Data(future.utf8)) as! [String: Any]
        var params = object["params"] as! [String: Any]
        params["change"] = try! JSONSerialization.jsonObject(with: Data(value.utf8), options: [.fragmentsAllowed])
        object["params"] = params
        var metadata = CodexFrameMetadata(); metadata.consume(try! JSONSerialization.data(withJSONObject: object))
        check(metadata.route?.version == 12 && metadata.route?.conversationID == "thread",
              "future change container shapes retain routing while JSON grammar remains validated")
    }

    var large = CodexFrameMetadata()
    large.consume(Data(#"{"params":{"change":{"conversationState":{"body":""#.utf8))
    let chunk = Data(repeating: 0x78, count: 16 * 1024)
    for _ in 0..<512 { large.consume(chunk) }
    check(large.route == nil, "large frame does not publish a route before its complete root object")
    large.consume(Data(#""},"type":"snapshot","revision":9},"hostId":"local","conversationId":"large"},"method":"thread-stream-state-changed","targetClientIds":["foreign"],"sourceClientId":"owner","version":11}"#.utf8))
    check(large.route?.conversationID == "large" && large.route?.targetClientIDs == ["foreign"],
          "eight MiB ignored body does not hide trailing routing fields")
    check(large.peakRetainedTokenBytes <= 4096, "large ignored body does not increase retained token memory")

    var nested = CodexFrameMetadata()
    let deep = #"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"padding":"#
        + String(repeating: "[", count: 129) + "0" + String(repeating: "]", count: 129) + "}"
    nested.consume(Data(deep.utf8))
    check(nested.route == nil, "excessive JSON depth is rejected with bounded container memory")

    var badUTF8 = CodexFrameMetadata()
    badUTF8.consume(Data(#"{"method":"one","params":{"hostId":"local","conversationId":"thread"},"padding":""#.utf8))
    badUTF8.consume(Data([0xED, 0xA0, 0x80]))
    badUTF8.consume(Data(#""}"#.utf8))
    check(badUTF8.route == nil, "invalid UTF-8 in ignored content cannot produce a trusted route")

    var longID = CodexFrameMetadata()
    longID.consume(Data((#"{"method":"one","params":{"hostId":"local","conversationId":""#
        + String(repeating: "x", count: 8192) + #""}}"#).utf8))
    check(longID.route == nil && longID.peakRetainedTokenBytes <= 4096, "oversized routing strings fail without retaining unbounded tokens")
    var manyTargets = CodexFrameMetadata()
    let targets: [String: Any] = ["method": "one", "params": ["hostId": "local", "conversationId": "thread"],
                                 "targetClientIds": (0..<257).map { "reader-\($0)" }]
    manyTargets.consume(try! JSONSerialization.data(withJSONObject: targets))
    check(manyTargets.route == nil, "target list size is bounded")
    var largeUnknownKey = CodexFrameMetadata()
    largeUnknownKey.consume(Data(("{\"" + String(repeating: "x", count: 8192)
        + #"":null,"method":"one","params":{"hostId":"local","conversationId":"thread"}}"#).utf8))
    check(largeUnknownKey.route?.conversationID == "thread" && largeUnknownKey.peakRetainedTokenBytes <= 4096,
          "large irrelevant keys do not retain body data or hide the actual route")

    let values: [Any] = [NSNull(), true, false, -12, 0, 1.25, "한글 😀 \" \\ /", [1, true, NSNull()],
                         ["method": "spoof", "params": ["conversationId": "fake"]]]
    for index in 0..<180 {
        let object: [String: Any] = ["type": "broadcast", "method": "thread-stream-state-changed", "sourceClientId": "owner", "version": 11,
            "targetClientIds": ["reader"], "params": ["hostId": "local", "conversationId": "thread",
                "change": ["type": "snapshot", "revision": 7,
                    "conversationState": ["one": values[index % values.count], "two": values[(index * 7) % values.count]]]]]
        let data = try! JSONSerialization.data(withJSONObject: object, options: index % 2 == 0 ? [.sortedKeys] : [.prettyPrinted])
        var generated = CodexFrameMetadata()
        let width = index % 31 + 1
        for offset in stride(from: 0, to: data.count, by: width) {
            generated.consume(data.subdata(in: offset..<min(data.count, offset + width)))
        }
        check(generated.route == expected, "generated valid metadata/body combination \(index) agrees with Foundation JSON")
    }
}
