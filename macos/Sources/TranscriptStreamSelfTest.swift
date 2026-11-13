import Foundation
import Darwin

func runTranscriptStreamSelfTest() -> Int32 {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    func record(_ type: String, _ payload: [String: Any]) -> String {
        let object: [String: Any] = ["timestamp": "2026-11-10T00:00:00Z", "type": type, "payload": payload]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
    let start = record("event_msg", ["type":"task_started", "turn_id":"a", "turn_attribution":["turn_id":"a", "turn_trigger":"composer"]])
    let question = record("response_item", ["type":"function_call", "name":"request_user_input_async", "call_id":"q", "arguments":"{\"questions\":[{}]}"])
    let large = record("response_item", ["type":"function_call_output", "call_id":"other", "output":String(repeating:"가나다", count:100000)])
    let abort = record("event_msg", ["type":"turn_aborted"])
    let done = record("event_msg", ["type":"task_complete"])
    let fixtures = ["", start + "\n" + question, [start, question, large, "malformed", abort, done].joined(separator:"\n")]
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    do {
        for text in fixtures {
            try Data(text.utf8).write(to:url)
            let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }
            let actual = codexTranscriptStatus(from:handle), expected = codexTranscriptStatus(in:text)
            guard try encoder.encode(actual) == encoder.encode(expected) else { return 1 }
        }
        try Data(("partial-json-line\n" + start + "\n" + question + "\n" + abort + "\n" + done).utf8).write(to:url)
        let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }
        let status = codexTranscriptStatus(from:handle, skippingFirstLine:true)
        guard status.pendingInputAtMs == nil, status.completedAtMs != nil,
              status.inputRequestTurns?["q:0"] == "a", status.abortedTurns?["a"] != nil else { return 1 }
        print("PASS streaming rollout: chunk/UTF8 boundaries, large record, invalid JSON, unterminated EOF, partial first line, turn attribution and abort/completion")
        return 0
    } catch { print(error); return 1 }
}

func benchmarkTranscriptScan(path: String, wholeFile: Bool) -> Int32 {
    let start = clock()
    do {
        let status: CodexTranscriptStatus
        if wholeFile {
            let data = try Data(contentsOf:URL(fileURLWithPath:path))
            status = codexTranscriptStatus(in:String(decoding:data, as:UTF8.self))
        } else {
            let handle = try FileHandle(forReadingFrom:URL(fileURLWithPath:path)); defer { try? handle.close() }
            status = codexTranscriptStatus(from:handle)
        }
        print("{\"cpuSeconds\":\(Double(clock()-start)/Double(CLOCKS_PER_SEC)),\"completed\":\(status.completedAtMs != nil)}")
        return 0
    } catch { print(error); return 1 }
}
