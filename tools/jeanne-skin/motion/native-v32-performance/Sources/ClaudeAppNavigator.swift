// Claude 데스크탑 앱에서 특정 세션으로 옮겨 가는 길.
//
// 딥링크로는 안 된다. 셋 다 재봤다(앱 1.37937.3).
//   resume?session=<UUID>          CLI 세션을 앱으로 "가져오는" 길이라 사본이 새 창으로 뜬다
//   code/continue?session=<UUID>   검증 정규식 /^local_[A-Za-z0-9-]{1,64}$/ 에 걸린다
//   code/continue?session=local_…  앱이 앞이든 뒤든 세션이 바뀌지 않는다. 앱만 앞으로 나온다
//
// 남은 길은 접근성으로 사이드바 행을 직접 누르는 것뿐이다. 스크린리더가 하는 일과 같다.
// 남의 앱 화면 구조에 기대는 방식이라 언제든 깨질 수 있다. 그래서 실패하면 조용히 물러나고,
// 부르는 쪽은 예전처럼 앱을 앞으로 보내는 것으로 끝낸다 — 지금보다 나빠지지 않는다.

import AppKit
import ApplicationServices

/// 사이드바 행 라벨이 이 세션을 가리키는가.
///
/// 라벨은 "<상태> <제목>" 꼴이다(예: `입력 대기 중 흠냐링`). 상태 접두어는 세션이 움직일 때마다
/// 실시간으로 바뀌므로 제목만 본다. 실제로 확인하는 사이에 `입력 대기 중` 이 `실행 중` 으로
/// 바뀌는 것을 봤다.
func claudeRowMatchesSession(rowLabel: String, sessionTitle: String) -> Bool {
    let label = rowLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    // 한 글자 제목은 아무 데나 걸린다. 그런 세션은 포기하는 편이 낫다.
    guard title.count >= 2, !label.isEmpty else { return false }
    if label == title { return true }
    // 접두어와 제목 사이에는 공백이 있다. 그냥 hasSuffix 로 보면 "링" 이 "흠냐링" 에 걸린다.
    return label.hasSuffix(" " + title)
}

enum ClaudeAppNavigator {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    /// 무슨 일이 있었는지 한 줄씩 남긴다. 이 기능은 남의 앱 화면에 기대는 것이라
    /// 실패해도 화면에 아무 표시가 남지 않는다 — 그때 여기를 보면 어디서 멈췄는지 알 수 있다.
    static func log(_ message: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/retto-pet")
        let file = directory.appendingPathComponent("navigator.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            let end = (try? handle.seekToEnd()) ?? 0
            // 눌릴 때마다 세 줄씩 쌓인다. 진단에 쓰는 것이니 최근 것만 있으면 된다.
            if end > 64 * 1024 {
                try? handle.truncate(atOffset: 0)
            }
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file)
        }
    }

    /// 접근성 권한이 있는가. 없으면 이 기능 전체가 조용히 꺼진다.
    static var isPermitted: Bool { AXIsProcessTrusted() }

    /// 권한을 한 번 물어본다. 앱을 켤 때가 아니라 사용자가 Claude 앱 세션을 실제로 누를 때만 부른다.
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    /// 앱이 자기 세션과 CLI 세션을 이어 둔 파일에서 앱 쪽 제목을 찾는다.
    ///
    /// 앱은 `~/Library/Application Support/Claude/claude-code-sessions/<a>/<b>/local_<id>.json` 에
    /// `{ sessionId, cliSessionId, title, cwd }` 를 적어 둔다. 훅이 아는 제목과 앱이 띄우는 제목이
    /// 어긋날 수 있어서(한쪽에서만 이름을 바꾼 경우) 앱 쪽 값을 먼저 쓴다.
    static func appSideTitle(cliSessionId: String) -> String? {
        guard !cliSessionId.isEmpty else { return nil }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in walker {
            guard url.lastPathComponent.hasPrefix("local_"), url.pathExtension == "json" else { continue }
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  record["cliSessionId"] as? String == cliSessionId,
                  let title = record["title"] as? String,
                  !title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            return title
        }
        return nil
    }

    /// 세션 id 로 옮겨 간다. 앱 쪽 제목을 먼저 찾고, 없으면 훅이 아는 제목으로 시도한다.
    static func focusSession(cliSessionId: String?, fallbackTitle: String?, completion: @escaping (Bool) -> Void) {
        guard isPermitted else {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let appTitle = cliSessionId.flatMap { appSideTitle(cliSessionId: $0) }
            let title = appTitle ?? fallbackTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            log("요청 · id=\(cliSessionId ?? "없음") 앱제목=\(appTitle ?? "못찾음") 훅제목=\(fallbackTitle ?? "없음")")
            guard let title, !title.isEmpty else {
                log("중단 · 쓸 제목이 없다")
                DispatchQueue.main.async { completion(false) }
                return
            }
            let result = pressRow(titled: title)
            log("결과 · \(result ? "눌렀다" : "누르지 못했다") (제목 ‘\(title)’)")
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// 사이드바에서 그 세션을 눌러 준다. 성공 여부를 돌려준다.
    ///
    /// 접근성 호출은 다른 앱의 응답을 기다리므로 주 스레드에서 하면 레토가 멈춘다.
    /// 배경에서 돌리고 결과만 주 스레드로 돌려준다.
    static func focusSession(titled title: String, completion: @escaping (Bool) -> Void) {
        guard isPermitted else {
            completion(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = pressRow(titled: title)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - 안쪽

    private static func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
    }

    private static func role(_ element: AXUIElement) -> String {
        attribute(element, kAXRoleAttribute as String) as? String ?? ""
    }

    private static func label(_ element: AXUIElement) -> String {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] as [String] {
            if let text = attribute(element, name) as? String,
               !text.trimmingCharacters(in: .whitespaces).isEmpty {
                return text
            }
        }
        return ""
    }

    private static func rows(in application: AXUIElement) -> [(element: AXUIElement, label: String)] {
        var found: [(AXUIElement, String)] = []
        var visited = 0
        func walk(_ element: AXUIElement, _ depth: Int) {
            visited += 1
            // 트리가 예상보다 깊거나 넓을 때 여기서 멈춘다. 남의 앱이라 크기를 장담할 수 없다.
            if depth > 30 || visited > 20000 { return }
            if role(element) == "AXButton" {
                let text = label(element)
                if !text.isEmpty { found.append((element, text)) }
            }
            for child in children(element) { walk(child, depth + 1) }
        }
        walk(application, 0)
        return found
    }

    private static func pressRow(titled title: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else { return false }
        let application = AXUIElementCreateApplication(app.processIdentifier)

        // Electron 은 보조기술이 붙었다는 신호를 받아야 웹 화면의 접근성 트리를 만든다.
        // 이 줄이 없으면 창 껍데기만 보이고 세션 목록은 아예 없다.
        _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        // 트리가 만들어질 때까지 기다린다. 처음 켤 때는 2초 넘게 걸리는 것을 봤다.
        // 다만 행이 이미 보이는데 그중에 없는 것이라면 더 기다릴 이유가 없다 — 바로 포기한다.
        // 그러지 않으면 목록에 없는 세션마다 5초씩 트리를 헛되이 훑는다.
        var matches: [(element: AXUIElement, label: String)] = []
        for _ in 0..<16 {
            let all = rows(in: application)
            matches = all.filter { claudeRowMatchesSession(rowLabel: $0.label, sessionTitle: title) }
            if !matches.isEmpty || !all.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.25)
        }

        // 하나로 좁혀지지 않으면 누르지 않는다. 엉뚱한 세션을 여는 것이 아무것도 안 하는 것보다 나쁘다.
        guard matches.count == 1, let row = matches.first else {
            let all = rows(in: application)
            log("행 고르기 실패 · 일치 \(matches.count)개 · 보이는 버튼 \(all.count)개: \(all.prefix(12).map { $0.label }.joined(separator: " | "))")
            return false
        }

        // 목록이 길면 화면 밖에 있을 수 있다. 눌리기 전에 보이는 자리로 끌어온다.
        // 상수가 SDK 에 없어 문자열을 그대로 쓴다. 행이 제공하는 동작 이름이다.
        _ = AXUIElementPerformAction(row.element, "AXScrollToVisible" as CFString)
        return AXUIElementPerformAction(row.element, kAXPressAction as CFString) == .success
    }
}
