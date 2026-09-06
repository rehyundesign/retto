// 빌드마다 도는 자체 검사와 배율별 미리보기.

import AppKit
import CoreText
import Foundation

/// 흰 배경에서 머리 위에 회색 안개가 없는지 잰다.
///
/// 예전에는 실루엣 드롭 섀도(blur 16)를 써서 흐림이 사방으로 퍼졌다. 어두운 배경에서는
/// 안 보였지만 흰 배경에서는 머리 위가 투명한 사각형처럼 도드라졌다. 다시 들어오면 여기서 걸린다.
/// 돌려주는 값은 (머리 위 회색 줄 수, 가장 진한 정도 0~255). 창 전체 후광 픽셀 수는
/// haloFaintPixels 에 담는다 — 어두운 배경에서는 안 보이니 숫자로만 지켜본다.
var haloFaintPixels = 0

func headroomHalo(spriteSheet: NSImage) -> (rows: Int, deepest: Int) {
    let layout = petLayout(scale: 1)
    let size = layout.windowSize
    let width = Int(size.width.rounded()), height = Int(size.height.rounded())
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return (0, 0) }

    let view = RettoView(frame: NSRect(origin: .zero, size: size), spriteSheet: spriteSheet, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
    view.petScale = 1
    let fixture = "{\"state\":\"idle\",\"sessionId\":\"halo\",\"projectName\":\"p\",\"lastAssistantMessage\":\"ㄱ\"}".data(using: .utf8)!
    guard let payload = try? JSONDecoder().decode(StatePayload.self, from: fixture) else { return (0, 0) }
    view.apply(payload, sessionCount: 1, attentionCount: 0, isPinned: false)
    view.settleAnimations()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()

    // 창 전체에서 옅고 넓은 회색이 얼마나 깔리는지. 후광은 몸 옆·어깨 위로 가장 넓게 퍼진다.
    var faint = 0
    for y in 0..<height {
        for x in 0..<width {
            guard let color = rep.colorAt(x: x, y: y) else { continue }
            let d = Int((1 - color.redComponent) * 255)
            if d >= 4 && d < 40 { faint += 1 }
        }
    }
    haloFaintPixels = faint

    // 머리 위쪽만 본다. 좌우 20% 는 배지 자리라 뺀다.
    let xLow = Int(size.width * 0.3), xHigh = Int(size.width * 0.7)
    var rows = 0, deepest = 0
    var bodyFound = false
    // rep 의 y=0 은 위쪽이다. 위에서 아래로 훑어 몸통 윤곽이 나오기 전까지가 머리 위다.
    for y in 0..<height {
        var wide = 0, darkest = 0
        for x in xLow...xHigh {
            guard let color = rep.colorAt(x: x, y: y) else { continue }
            let d = Int((1 - color.redComponent) * 255)
            if d >= 4 { wide += 1 }
            darkest = max(darkest, d)
        }
        if ProcessInfo.processInfo.environment["RETO_HALO_DEBUG"] != nil, y < 40 {
            fputs("  y=\(y) 폭\(wide) 진하기\(darkest)\n", stderr)
        }
        if darkest >= 60 { bodyFound = true; break }
        // 귀 끝 안티에일리어싱은 좁고 금방 진해진다. 후광은 옅으면서 넓다.
        if wide >= 35 && darkest <= 40 { rows += 1; deepest = max(deepest, darkest) }
    }
    return bodyFound ? (rows, deepest) : (rows, deepest)
}

/// 그 상태에서 창에 어떤 단추가 나오는지. 그림으로는 라벨이 잡히지 않아 이걸로 본다.
private func setupButtons(for status: ClaudeIntegrationStatus) -> [String] {
    let window = SetupWindow(firstRun: true, onReinstall: {})
    window.refresh(status: status, environment: RettoHostEnvironment())
    return window.visibleButtonTitles
}

func runSelfTest() -> Int32 {
    let fontOK = registerRettoFont()
    guard let imageURL = Bundle.main.url(forResource: "spritesheet", withExtension: "webp"),
          let image = NSImage(contentsOf: imageURL) else {
        fputs("{\"ok\":false,\"error\":\"missing spritesheet\"}\n", stderr)
        return 1
    }
    let assetOK = Int(image.size.width) == Int(sheetWidth) && Int(image.size.height) == Int(sheetHeight)
    // 스킨 아틀라스는 기본과 칸 규격이 같아야 한다. 크기가 다르면 그리는 자리가 통째로 어긋난다.
    // 번들에 없는 스킨은 앱이 기본으로 물러나므로 통과로 본다.
    let skinsOK = PetSkin.allCases.allSatisfy { skin in
        guard let url = Bundle.main.url(forResource: skin.resourceName, withExtension: "webp"),
              let sheet = NSImage(contentsOf: url) else { return skin != .classic }
        return Int(sheet.size.width) == Int(sheetWidth) && Int(sheet.size.height) == Int(sheetHeight)
    }
    // 자는 행이 실제로 아틀라스에 있는지. 행을 새로 붙였는데 sheetHeight 를 안 고치면
    // 엉뚱한 자리를 그린다.
    let sleepRow = animationCatalog[.sleeping]?.row ?? -1
    let sleepRowOK = sleepRow >= 0 && CGFloat(sleepRow + 1) * cellHeight <= sheetHeight
    // 끌 때 쓰는 달리기 두 행. 아틀라스 안에 있고 칸 수가 한 행을 넘지 않아야 한다.
    let dragRunOK = Set(dragRunAnimations.keys) == Set<DragRun>([.right, .left])
        && dragRunAnimations.values.allSatisfy { run in
            run.row >= 0 && CGFloat(run.row + 1) * cellHeight <= sheetHeight
                && run.frames > 0 && CGFloat(run.frames) * cellWidth <= sheetWidth
        }
    let behaviorsOK = allSpacesBehavior.contains(.canJoinAllSpaces)
        && allSpacesBehavior.contains(.fullScreenAuxiliary)
        && allSpacesBehavior.contains(.stationary)
    let statesOK = Set(animationCatalog.keys) == Set(PetState.allCases)
    // VS Code 딥링크는 확장 규격 그대로여야 한다. 한 글자만 틀려도 클릭이 조용히 아무 일도 안 한다.
    // Claude 앱에는 세션을 집어 띄우는 길이 없으므로 링크를 만들지 않는다 —
    // 예전에 쓰던 `claude://resume` 은 세션을 앱으로 가져오는 길이라 누를 때마다 새 창이 떴다.
    let deepLinkOK = sessionDeepLink(sessionId: "session-test", app: .vscode)?.absoluteString == "vscode://anthropic.claude-code/open?session=session-test"
        && sessionDeepLink(sessionId: "session-test", app: .claude) == nil
        && sessionDeepLink(sessionId: "thread-test", app: .codex)?.absoluteString == "codex://threads/thread-test"
        && OpenApp.vscode.hasSessionDeepLink
        && !OpenApp.claude.hasSessionDeepLink
        && OpenApp.codex.hasSessionDeepLink
    // 훅이 적어 둔 클라이언트가 앱으로 옳게 풀리는지. 모르는 값은 예전 동작인 VS Code 로 남아야 한다.
    // 말풍선 본문은 두 클라이언트의 트랜스크립트에서 온다. Codex 롤아웃은 한 겹 더 싸여 있고
    // 글 조각 이름도 `output_text` 라, 한쪽 모양만 읽으면 그 클라이언트 말풍선이 빈 채로 남는다.
    let claudeRecord: [String: Any] = ["type": "assistant", "message": ["content": [["type": "text", "text": "클로드가 하는 말"]]]]
    let codexRecord: [String: Any] = ["type": "response_item", "payload": ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "코덱스가 하는 말"]]]]
    let userRecord: [String: Any] = ["type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "사람이 한 말"]]]]
    let transcriptShapesOK = assistantText(in: claudeRecord) == "클로드가 하는 말"
        && assistantText(in: codexRecord) == "코덱스가 하는 말"
        && assistantText(in: userRecord).isEmpty

    let clientRoutingOK = openApp(forClient: "claude") == .claude
        && openApp(forClient: "vscode") == .vscode
        && openApp(forClient: "codex") == .codex
        && openApp(forClient: "cli") == .vscode
        && openApp(forClient: nil) == .vscode
        && openApp(forClient: "") == .vscode
    // 창을 먼저 앞으로 보내는 단계는 VS Code 에만 있다. Claude 앱에서 이걸 켜면 딥링크가 영영 안 나간다.
        && OpenApp.vscode.needsWindowFocusFirst && !OpenApp.claude.needsWindowFocusFirst && !OpenApp.codex.needsWindowFocusFirst
        && OpenTarget.allCases.map(\.rawValue) == ["auto", "vscode", "claude"]
    let codexMenuOK = aiSessionOpenMenuTitle == "AI 세션 열 곳"
        && emptyClaudeSessionLabel == "Claude · 실행 중인 세션 없음"
        && emptyCodexSessionLabel == "Codex · 실행 중인 task 없음"
        && codexOpenTargetMenuLabel(isRegistered: true) == "Codex task → Codex 앱 · 자동"
        && codexOpenTargetMenuLabel(isRegistered: false) == "Codex task → Codex 앱 · 훅 확인 필요"
    // 연동 확인이 실제로 셋을 가려내는지. 이게 틀리면 "정상" 이라고 말해 놓고 아무 소식도 안 온다.
    // 훅 세는 규칙은 지금의 command 한 줄과 0.7.0 까지의 command+args 를 함께 알아봐야 한다 —
    // 갱신 전에 열어 본 사람에게 "훅 없음" 이라고 말하면 안 된다.
    let hookFixture: [String: Any] = ["hooks": [
        "Stop": [["hooks": [
            ["type": "command", "command": "'/Users/x/.claude/retto-pet/hook.sh' 'waving'"],
            ["type": "command", "command": "announce"]
        ]]],
        "SessionStart": [["hooks": [
            ["type": "command", "command": "node", "args": ["/Users/x/.claude/retto-pet/hook.cjs", "idle"]]
        ]]],
        "PreToolUse": [["hooks": [["type": "command", "command": "/Users/x/.claude/reto-pet/hook.cjs"]]]]
    ]]
    let newsFixture = [
        "{\"state\":\"running\",\"sessionId\":\"a\",\"client\":\"vscode\",\"updatedAtMs\":1000}",
        "{\"state\":\"idle\",\"sessionId\":\"b\",\"client\":\"vscode\",\"updatedAtMs\":5000}",
        "{\"state\":\"idle\",\"sessionId\":\"c\",\"source\":\"codex\",\"updatedAtMs\":3000}",
        "{\"state\":\"idle\",\"sessionId\":\"d\",\"updatedAtMs\":9000}"
    ].compactMap { try? JSONDecoder().decode(StatePayload.self, from: $0.data(using: .utf8)!) }
    let news = ClaudeIntegration.lastNews(in: newsFixture)
    var missingHooks = ClaudeIntegrationStatus()
    missingHooks.shimInstalled = true
    missingHooks.hookInstalled = true
    missingHooks.nodePath = "/opt/homebrew/bin/node"
    var quiet = missingHooks
    quiet.registeredEvents = 17
    var healthy = quiet
    healthy.lastNews = [.vscode: Date()]
    let integrationOK = ClaudeIntegration.countRegisteredEvents(in: hookFixture) == 3
        && ClaudeIntegration.countRegisteredEvents(in: ["hooks": [String: Any]()]) == 0
        && NewsChannel.of(client: "claude", source: nil) == .claudeApp
        && NewsChannel.of(client: "cli", source: nil) == .cli
        && NewsChannel.of(client: "vscode", source: "codex") == .codex
        // client 를 못 읽은 옛 기록은 어느 채널로도 세지 않는다. 셌다가는 없는 소식을 있다고 한다.
        && NewsChannel.of(client: nil, source: nil) == nil
        && news.count == 2
        && news[.vscode] == Date(timeIntervalSince1970: 5)
        && news[.claudeApp] == nil
        && missingHooks.menuTitle == "Claude 연동 확인 — 훅 없음"
        && quiet.menuTitle == "Claude 연동 확인 — 소식 없음"
        && healthy.menuTitle == "Claude 연동 확인"
        && healthy.isHealthy && !quiet.isHealthy
        && elapsedLabel(since: Date(timeIntervalSinceNow: -30)) == "방금"
        && elapsedLabel(since: Date(timeIntervalSinceNow: -180)) == "3분 전"
        && elapsedLabel(since: Date(timeIntervalSinceNow: -7200)) == "2시간 전"
    // 처음 설정 창. 이미 소식이 오는 사람에게 뜨면 잘 돌고 있는데도 고장인 줄 안다.
    // 안내 문구는 깔려 있는 것만 말해야 한다 — 없는 앱을 켜 보라고 하면 그 줄부터 믿지 않는다.
    var connected = ClaudeIntegrationStatus()
    connected.lastNews = [.vscode: Date()]
    // 훅은 멀쩡한데 아직 소식이 없는 상태. 처음 켠 사람이 보는 화면이다.
    var blank = ClaudeIntegrationStatus()
    blank.registeredEvents = 17
    blank.shimInstalled = true
    blank.hookInstalled = true
    blank.nodePath = "/opt/homebrew/bin/node"
    // 설치기가 node 를 못 찾아 훅을 건너뛴 상태. 고칠 것이 둘이다.
    let broken = ClaudeIntegrationStatus()
    var claudeAppOnly = RettoHostEnvironment()
    claudeAppOnly.hasClaudeApp = true
    var codexToo = claudeAppOnly
    codexToo.hasCodex = true
    let nothing = RettoHostEnvironment()
    let setupOK = shouldShowSetupOnLaunch(hasSeen: false, status: blank)
        && !shouldShowSetupOnLaunch(hasSeen: true, status: blank)
        && !shouldShowSetupOnLaunch(hasSeen: false, status: connected)
        && claudeAppOnly.whatToTry.count == 1
        && claudeAppOnly.whatToTry[0].contains("대화창")
        && !claudeAppOnly.whatToTry.joined().contains("VS Code")
        && codexToo.whatToTry.count == 2
        && codexToo.whatToTry.last!.contains("Codex")
        // 아무것도 못 찾았을 때도 할 말은 있어야 한다. 빈 창은 고장으로 읽힌다.
        && nothing.whatToTry.count == 1
        && nothing.whatToTry[0].contains("먼저 설치")
        // 고칠 것이 있을 때만 단추가 나온다. 멀쩡한데 「훅 지금 붙이기」가 보이면
        // 눌러야 하는 줄 알고 멀쩡한 설정을 다시 쓴다.
        && setupButtons(for: blank) == []
        && setupButtons(for: broken) == ["훅 지금 붙이기", "Node.js 받기"]
    let scalesOK = supportedScales.first == 0.39 && supportedScales.last == 1.4
    // 배율 1에서는 예전 창 크기를 그대로 유지한다.
    let baseline = petLayout(scale: 1)
    // 상수를 바꿔도 관계가 유지되는지 본다. 숫자를 박아두면 값 조정마다 검사가 거짓으로 깨진다.
    let baseChrome = chromeScale(for: 1)
    let baselineOK = baseline.chromeScale == baseChrome
        && baseline.petRect.width == basePetWidth
        && baseline.ribbonRect.height == baseRibbonHeight * baseChrome
        && abs(baseline.windowSize.width - max(basePetWidth + 2 * petSideMargin, (baseRibbonWidth + 2 * ribbonSideInset) * baseChrome)) < 0.01
        && abs(baseline.windowSize.height - (baseline.petRect.maxY + petBadgeHeadroom)) < 0.01
        && abs(baseline.ribbonRect.maxY - (baseline.petRect.minY + petRibbonOverlap)) < 0.01
    // 가장 작은 배율에서 몸은 프리셋을 그대로 따르지만, 말풍선은 글이 읽히는 하한 아래로 내려가지
    // 않고 창은 말풍선 폭을 따라간다. 곡선의 기준점(chromeScaleAnchor)은 프리셋 목록과 따로 두므로
    // 가장 작은 프리셋을 올려도 하한만 지키면 된다 — 기준점과 같아야 할 이유는 없다.
    let smallest = petLayout(scale: supportedScales[0])
    let decoupledOK = smallest.petRect.width == basePetWidth * supportedScales[0]
        && smallest.chromeScale >= chromeScaleAtMin
        && abs(smallest.chromeScale - chromeScale(for: supportedScales[0])) < 0.0001
        && smallest.ribbonRect.height == baseRibbonHeight * smallest.chromeScale
        && smallest.windowSize.width > smallest.petRect.width
        // 프리셋을 한 칸 올리면 말풍선도 반드시 커져야 한다. 레토만 커지면 뜻이 없다.
        && zip(supportedScales, supportedScales.dropFirst()).allSatisfy { small, large in
            petLayout(scale: large).ribbonRect.height > petLayout(scale: small).ribbonRect.height + 1
        }
    // 시선은 코덱스와 같은 세 상태에서만 걸린다.
    let gazeStatesOK = gazeStates == [.idle, .running, .waving]
    // 배지는 말풍선 오른쪽 위에 고정이고, 왼쪽 이름표와 같은 만큼 위로 솟는다.
    let badge = attentionBadgeRect(ribbon: baseline.ribbonRect, scale: baseline.chromeScale)
    let badgeLayoutOK = badge.width == attentionBadgeSide * baseline.chromeScale
        && badge.maxX < baseline.ribbonRect.maxX
        && badge.maxY > baseline.ribbonRect.maxY
        && badge.minY < baseline.ribbonRect.maxY
        && badge.midX > baseline.ribbonRect.midX
        && attentionBadgeRect(ribbon: baseline.ribbonRect, scale: 1.4).width == attentionBadgeSide * 1.4
    // 배지가 떠 있을 때만 배지로 간다.
    let clickRoutingOK = petClickTarget(layout: baseline, badgeFrame: badge, point: NSPoint(x: badge.midX, y: badge.midY), attentionCount: 2) == .badge
        && petClickTarget(layout: baseline, badgeFrame: .zero, point: NSPoint(x: baseline.ribbonRect.midX, y: baseline.ribbonRect.midY), attentionCount: 2) == .ribbon
        && petClickTarget(layout: baseline, badgeFrame: badge, point: NSPoint(x: baseline.petRect.midX, y: baseline.petRect.midY), attentionCount: 2) == .body
        && petClickTarget(layout: baseline, badgeFrame: badge, point: NSPoint(x: 2, y: baseline.windowSize.height - 2), attentionCount: 2) == nil
    // 내 답 대기 → 답변 완료 → 실패 순서를 지키면서, 셋 다 작업 중보다 위에 있어야 한다.
    let priorityOK = selectionPriority(state: .waiting, isClosed: false) > selectionPriority(state: .waving, isClosed: false)
        && selectionPriority(state: .waving, isClosed: false) > selectionPriority(state: .failed, isClosed: false)
        && needsInputStates.allSatisfy {
            selectionPriority(state: $0, isClosed: false) > selectionPriority(state: .running, isClosed: false)
                && selectionPriority(state: $0, isClosed: false) > selectionPriority(state: .review, isClosed: false)
        }
        && selectionPriority(state: .idle, isClosed: true) < 0
    // 펼치면 말풍선만 자라고 창도 그만큼만 커진다.
    let expanded = petLayout(scale: 1, expanded: true)
    let grown = ribbonBodyHeight * baseline.chromeScale
    let expandOK = abs(expanded.ribbonRect.height - (baseline.ribbonRect.height + grown)) < 0.01
        && abs(expanded.windowSize.height - (baseline.windowSize.height + grown)) < 0.01
        && expanded.windowSize.width == baseline.windowSize.width
        && expanded.petRect.width == baseline.petRect.width
        && expanded.ribbonRect.maxY - expanded.petRect.minY == baseline.ribbonRect.maxY - baseline.petRect.minY
    // 접으면 두 줄, 펼치면 네 줄까지 보여야 한다. 실제 폰트 메트릭으로 잰다.
    let bodyFont = NSFont(name: rettoHandwritingFontName, size: 18 * baseline.chromeScale)
        ?? NSFont.systemFont(ofSize: 18 * baseline.chromeScale)
    let bodyLineHeight = bodyFont.ascender - bodyFont.descender + bodyFont.leading
    let bodySpacing = 0.875 * baseline.chromeScale
    func lineBudget(_ areaHeight: CGFloat) -> Int {
        max(0, Int(((areaHeight + bodySpacing) / (bodyLineHeight + bodySpacing)).rounded(.down)))
    }
    let compactArea = baseline.ribbonRect.height - 30 * baseline.chromeScale
    let expandedArea = expanded.ribbonRect.height - 30 * baseline.chromeScale
    let lineBudgetOK = lineBudget(compactArea) == 2 && lineBudget(expandedArea) == 4
    // 서체 두 종. 기본 서체는 손글씨보다 3pt 작게 그려지므로 같은 칸에 줄이 더 들어간다 —
    // 그 여분이 둥근 말풍선의 아래 곡선에 걸려 반토막으로 그려졌던 적이 있다. 지금은 그리기 쪽에서
    // 허용한 줄 수 밖을 잘라내므로, 여기서는 "기본 서체가 손글씨보다 작다"는 전제만 지켜지는지 본다.
    func typefaceLine(_ face: PetTypeface) -> CGFloat {
        let font = petFont(face, size: 18 * baseline.chromeScale)
        return font.ascender - font.descender + font.leading
    }
    let typefaceOK = PetTypeface.allCases.count == 2
        && PetTypeface(rawValue: "handwriting") == .handwriting
        && PetTypeface(rawValue: "system") == .system
        && PetTypeface(rawValue: "없는값") == nil
        && petFont(.handwriting, size: 18).fontName.contains("Nanum")
        && !petFont(.system, size: 18).fontName.contains("Nanum")
        // 기본 서체는 -3pt 로 잡혀 있어야 한다. 이 전제가 깨지면 크기 선택이 무의미해진다.
        && petFont(.system, size: 18).pointSize == 18 + systemTypefaceDelta
        && typefaceLine(.system) < typefaceLine(.handwriting)
    // 프리셋별 글자 깎기: 말풍선 치수는 그대로 두고 글자만 줄여야 한다.
    func bodyLines(at scale: CGFloat) -> Int {
        let layout = petLayout(scale: scale)
        let size = 18 * layout.chromeScale + layout.textDelta
        let font = NSFont(name: rettoHandwritingFontName, size: size) ?? NSFont.systemFont(ofSize: size)
        let line = font.ascender - font.descender + font.leading
        let spacing = 0.875 * layout.chromeScale
        let area = layout.ribbonRect.height - 30 * layout.chromeScale
        return max(0, Int(((area + spacing) / (line + spacing)).rounded(.down)))
    }
    let half = petLayout(scale: 0.5)
    let textDeltaOK = half.textDelta == -1.5
        // 초소형은 반 픽셀만 깎는다. 손글씨가 이 크기에서 뭉개지기 시작한다.
        && petLayout(scale: 0.39).textDelta == -0.5
        && baseline.textDelta == 0
        // 말풍선·창은 깎기 전과 같은 크기다. 글자만 줄인 것이지 칸을 줄인 게 아니다.
        && half.ribbonRect.height == baseRibbonHeight * chromeScale(for: 0.5)
        && abs(half.windowSize.width - max(basePetWidth * 0.5 + 2 * petSideMargin * 0.5, (baseRibbonWidth + 2 * ribbonSideInset) * chromeScale(for: 0.5))) < 0.01
        // 글자가 작아졌다고 두 줄이 세 줄로 늘면 말풍선이 달라 보인다.
        && bodyLines(at: 0.5) == 2
    // 색은 뜻 단위 넷(+조용함)으로만 쓰고, 뜻이 섞이지 않아야 한다.
    let tonesOK = animationCatalog[.running]?.tone.key == toneWorking.key
        && animationCatalog[.review]?.tone.key == toneWorking.key
        && animationCatalog[.jumping]?.tone.key == toneWorking.key
        && animationCatalog[.waiting]?.tone.key == toneNeedsYou.key
        && animationCatalog[.waving]?.tone.key == toneDone.key
        && animationCatalog[.failed]?.tone.key == toneFailed.key
        && animationCatalog[.idle]?.tone.key == toneQuiet.key
        && Set(animationCatalog.values.map(\.tone.key)).count == 5
    // 말풍선은 Figma 도형을 그대로 옮긴 것이어야 한다. 원본 비율과 칸 채우기를 확인한다.
    let template = bubbleTemplate.bounds
    let filled = bubblePath(in: NSRect(x: 5, y: 7, width: 200, height: 60)).bounds
    let bubbleShapeOK = abs(template.width / template.height - 3.1129) < 0.01
        && abs(filled.minX - 5) < 0.5 && abs(filled.minY - 7) < 0.5
        && abs(filled.width - 200) < 0.5 && abs(filled.height - 60) < 0.5
        && bubbleTemplate.elementCount > 20
    // 손 흔들기는 두 바퀴로 끝나지만 그건 그림 이야기다. 완료 상태의 우선순위·색은 그대로 남아야 한다.
    let doneStaysOK = animationCatalog[.waving]?.cycleLimit == 2
        && selectionPriority(state: .waving, isClosed: false) > selectionPriority(state: .idle, isClosed: false)
        && animationCatalog[.waving]?.tone.key != animationCatalog[.idle]?.tone.key
    // 유령 규칙: 작업 중은 10분 뒤 조용해지고, 손이 필요한 상태는 아무리 오래돼도 남는다.
    let nowFixture: Double = 1_000_000_000
    let longAgo = nowFixture - staleWorkingTimeout * 1000 - 1
    let staleOK = isStaleWorking(state: .running, updatedAtMs: longAgo, nowMs: nowFixture)
        && isStaleWorking(state: .review, updatedAtMs: longAgo, nowMs: nowFixture)
        && !isStaleWorking(state: .running, updatedAtMs: nowFixture - 1000, nowMs: nowFixture)
        && !isStaleWorking(state: .waving, updatedAtMs: longAgo, nowMs: nowFixture)
        && !isStaleWorking(state: .waiting, updatedAtMs: longAgo, nowMs: nowFixture)
        && !isStaleWorking(state: .failed, updatedAtMs: longAgo, nowMs: nowFixture)
    // 읽음 규칙: 다녀온 시각이 마지막 갱신보다 뒤면 조용해지고, 새 소식이 오면 다시 올라온다.
    let seenOK = isSeen(updatedAtMs: 100, seenAtMs: 200)
        && isSeen(updatedAtMs: 100, seenAtMs: 100)
        && !isSeen(updatedAtMs: 300, seenAtMs: 200)
        && !isSeen(updatedAtMs: 100, seenAtMs: nil)
    // 이름표는 한글 12자 폭에서 접힌다. 폭이 좁은 영문은 12자를 넘어도 잘리지 않아야 한다.
    let labelFont = NSFont(name: rettoHandwritingFontName, size: 16.5) ?? NSFont.boldSystemFont(ofSize: 16.5)
    let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont]
    let labelBudgetWidth = (sectionLabelWidthSample as NSString).size(withAttributes: labelAttributes).width
    func labelWidth(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: labelAttributes).width }
    let labelOK = sectionLabelWidthSample.count == 12
        && labelWidth(sectionLabelWidthSample) <= labelBudgetWidth + 0.01
        && labelWidth("session-title-abc") < labelBudgetWidth
        && labelWidth("백오피스 조직별 화면 목업 다시 봐줘") > labelBudgetWidth
    // 세션 폴더 → 창 폴더 접기. 하위 폴더를 그대로 열면 새 창이 생기므로 조상으로 바꿔야 한다.
    let folderFixture = ["/a/planning", "/a/git-rehyundesign", "/a"]
    func deepestAncestor(_ path: String) -> String? {
        folderFixture.filter { path == $0 || path.hasPrefix($0 + "/") }.max(by: { $0.count < $1.count })
    }
    let folderFoldOK = deepestAncestor("/a/planning/mockups/apps/mockup-hub") == "/a/planning"
        && deepestAncestor("/a/planning") == "/a/planning"
        && deepestAncestor("/b/other") == nil
    let registryFixture = "{\"sessions\":{\"one\":{\"state\":\"running\",\"sessionId\":\"one\",\"displayTitle\":\"A\"},\"two\":{\"state\":\"waiting\",\"sessionId\":\"two\",\"displayTitle\":\"B\"}}}".data(using: .utf8)!
    let registryOK = (try? JSONDecoder().decode(SessionRegistry.self, from: registryFixture).sessions.count) == 2
    // 레토를 누르지 않고 직접 세션에 들어가 읽은 경우를 접근 시각으로 잡아내는지.
    let viewedOK = wasViewedElsewhere(accessedAtMs: 10_000, updatedAtMs: 5_000)
        && !wasViewedElsewhere(accessedAtMs: 6_000, updatedAtMs: 5_000)   // 2초 여유 안쪽은 훅이 읽은 것
        && !wasViewedElsewhere(accessedAtMs: 4_000, updatedAtMs: 5_000)   // 완료보다 앞이면 안 본 것
        && !wasViewedElsewhere(accessedAtMs: 10_000, updatedAtMs: nil)

    // 전부 조용한 채로 10분이 지나면 자는지. 하나라도 일하고 있으면 안 잔다.
    let nowFixed: Double = 100_000_000
    let sleepOK = shouldSleep(newestUpdatedAtMs: nowFixed - sleepAfter * 1000 - 1, nowMs: nowFixed, hasBusySession: false)
        && !shouldSleep(newestUpdatedAtMs: nowFixed - sleepAfter * 1000 - 1, nowMs: nowFixed, hasBusySession: true)
        && !shouldSleep(newestUpdatedAtMs: nowFixed - 60_000, nowMs: nowFixed, hasBusySession: false)
        && !shouldSleep(newestUpdatedAtMs: nil, nowMs: nowFixed, hasBusySession: false)
        && animationCatalog[.sleeping]?.tone.key == "quiet"

    // 읽음 표시가 일하는 중을 회색으로 덮지 않는지, 트랜스크립트가 자라면 유령이 아닌지.
    let displayOK = displayState(state: .running, updatedAtMs: 1_000, seenAtMs: 9_999_999, transcriptModifiedAtMs: nil, nowMs: 1_500) == .running
        && displayState(state: .waving, updatedAtMs: 1_000, seenAtMs: 2_000, transcriptModifiedAtMs: nil, nowMs: 2_500) == .idle
        && displayState(state: .waving, updatedAtMs: 3_000, seenAtMs: 2_000, transcriptModifiedAtMs: nil, nowMs: 3_500) == .waving
        // 훅은 조용하지만 파일이 자라고 있으면 살아 있다
        && displayState(state: .running, updatedAtMs: 1_000, seenAtMs: nil,
                        transcriptModifiedAtMs: 1_000_000, nowMs: 1_000_100) == .running
        // 훅도 파일도 오래 조용하면 유령
        && displayState(state: .running, updatedAtMs: 1_000, seenAtMs: nil,
                        transcriptModifiedAtMs: 2_000, nowMs: 2_000 + staleWorkingTimeout * 1000 + 1) == .idle

    // 깔려 있지 않은 앱으로 보내지 않는지.
    // 이름표 우선순위: 세션명 > 작업 주제 > 쓸 만한 길이의 프롬프트 > 폴더 이름.
    // ⚠️ 짧은 답("B"·"재진행")은 이름이 아니다. 훅이 대화 도중 붙으면 그 답이 displayTitle 로
    // 굳는데, 그대로 띄우면 세션명 자리에 내가 친 답이 뜬다. 실제로 그렇게 났다.
    func titleOf(_ json: String) -> String {
        guard let d = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(StatePayload.self, from: d) else { return "" }
        return p.title
    }
    let titleOK = titleOf("{\"state\":\"running\",\"sessionTitle\":\"서치서울 문서\",\"displayTitle\":\"아주 긴 프롬프트입니다\",\"projectName\":\"planning\"}") == "서치서울 문서"
        && titleOf("{\"state\":\"running\",\"activeTaskSubject\":\"토큰 정리\",\"displayTitle\":\"아주 긴 프롬프트입니다\",\"projectName\":\"planning\"}") == "토큰 정리"
        && titleOf("{\"state\":\"running\",\"displayTitle\":\"아주 긴 프롬프트입니다\",\"projectName\":\"planning\"}") == "아주 긴 프롬프트입니다"
        && titleOf("{\"state\":\"running\",\"displayTitle\":\"B\",\"projectName\":\"planning\"}") == "planning"
        && titleOf("{\"state\":\"running\",\"displayTitle\":\"재진행\",\"projectName\":\"planning\"}") == "planning"
    let fallbackOK = installedOpenApp(preferred: .vscode) { $0 == .claude } == .claude
        && installedOpenApp(preferred: .claude) { $0 == .vscode } == .vscode
        && installedOpenApp(preferred: .codex) { $0 == .claude } == .claude
        && installedOpenApp(preferred: .vscode) { _ in true } == .vscode
        && installedOpenApp(preferred: .claude) { _ in false } == .claude

    // 네 모서리 좌표가 맞는지. 화면 900×600, 창 200×150, 여백 24 로 계산해 본다.
    let visibleTest = NSRect(x: 100, y: 50, width: 900, height: 600)
    let boxTest = NSSize(width: 200, height: 150)
    let cornerOK = cornerOrigin(corner: .free, size: boxTest, visible: visibleTest) == nil
        && cornerOrigin(corner: .bottomLeft, size: boxTest, visible: visibleTest) == NSPoint(x: 124, y: 74)
        && cornerOrigin(corner: .bottomRight, size: boxTest, visible: visibleTest) == NSPoint(x: 776, y: 74)
        && cornerOrigin(corner: .topLeft, size: boxTest, visible: visibleTest) == NSPoint(x: 124, y: 476)
        && cornerOrigin(corner: .topRight, size: boxTest, visible: visibleTest) == NSPoint(x: 776, y: 476)
        && PetCorner.bottomRight.anchorsToBottom && !PetCorner.topRight.anchorsToBottom
        && PetCorner.allCases.count == 5

    // 창 제목으로 "그 세션을 보고 있다" 를 알아내는지. 짧은 폴더 이름에 낚이지 않아야 한다.
    let lookingOK = windowShowsSession(windowTitle: "백오피스 기획 — planning", sessionTitle: "백오피스 기획", folderName: "planning")
        && windowShowsSession(windowTitle: "hook.cjs — git-rehyundesign", sessionTitle: "레토 공식", folderName: "git-rehyundesign")
        && !windowShowsSession(windowTitle: "hook.cjs — other-repo", sessionTitle: "레토 공식", folderName: "git-rehyundesign")
        && !windowShowsSession(windowTitle: "", sessionTitle: "레토 공식", folderName: "git-rehyundesign")
        && !windowShowsSession(windowTitle: "a — b", sessionTitle: nil, folderName: "ui")   // 두 글자 폴더는 안 믿는다
        && lookingDwell >= 2

    // 다 끝내 놓고 30분 아무도 안 오면 그림만 잠드는지. 하나라도 일하면 안 잔다.
    let dozeOK = shouldDozeWhileWaiting(newestAttentionAtMs: nowFixed - dozeAfter * 1000 - 1, nowMs: nowFixed, everythingDone: true)
        && !shouldDozeWhileWaiting(newestAttentionAtMs: nowFixed - dozeAfter * 1000 - 1, nowMs: nowFixed, everythingDone: false)
        && !shouldDozeWhileWaiting(newestAttentionAtMs: nowFixed - 60_000, nowMs: nowFixed, everythingDone: true)
        && !shouldDozeWhileWaiting(newestAttentionAtMs: nil, nowMs: nowFixed, everythingDone: true)
        && dozeAfter > sleepAfter   // 다 자는 것보다 늦게 졸아야 한다

    // 앱이 켜지기 한참 전에 끝난 일을 새 소식으로 알리지 않는지.
    let launchMs: Double = 10_000_000
    let ancientOK = isAncientNews(updatedAtMs: launchMs - trackingGrace * 1000 - 1, trackingStartedAtMs: launchMs)
        && !isAncientNews(updatedAtMs: launchMs - 60_000, trackingStartedAtMs: launchMs)  // 1분 전 완료는 알린다
        && !isAncientNews(updatedAtMs: launchMs + 60_000, trackingStartedAtMs: launchMs)  // 켜진 뒤 완료는 당연히 알린다
        && !isAncientNews(updatedAtMs: nil, trackingStartedAtMs: launchMs)

    // 흰 배경 머리 위: 옅은 회색이 세 줄 넘게 깔리면 사각형처럼 보인다.
    let halo = headroomHalo(spriteSheet: image)
    let haloOK = halo.rows <= 3 && halo.deepest <= 12

    // Claude 앱 사이드바 행 매칭. 라벨은 "<상태> <제목>" 꼴이고 상태는 실시간으로 바뀐다.
    // 부분 일치를 허용하면 엉뚱한 세션을 연다 — 그게 이 기능에서 가장 나쁜 실패다.
    let claudeRowOK = claudeRowMatchesSession(rowLabel: "입력 대기 중 흠냐링", sessionTitle: "흠냐링")
        && claudeRowMatchesSession(rowLabel: "실행 중 흠냐링", sessionTitle: "흠냐링")
        && claudeRowMatchesSession(rowLabel: "유휴 General coding session", sessionTitle: "General coding session")
        && claudeRowMatchesSession(rowLabel: "흠냐링", sessionTitle: "흠냐링")
        && !claudeRowMatchesSession(rowLabel: "입력 대기 중 흠냐링", sessionTitle: "냐링")
        && !claudeRowMatchesSession(rowLabel: "실행 중 클로드앱에서 해보자", sessionTitle: "흠냐링")
        && !claudeRowMatchesSession(rowLabel: "입력 대기 중 흠냐링", sessionTitle: "링")
        && !claudeRowMatchesSession(rowLabel: "", sessionTitle: "흠냐링")
        && !claudeRowMatchesSession(rowLabel: "입력 대기 중 흠냐링", sessionTitle: "")

    let ok = claudeRowOK && fallbackOK && cornerOK && lookingOK && sleepRowOK && displayOK && dozeOK && sleepOK && ancientOK && viewedOK && haloOK && assetOK && skinsOK && dragRunOK && behaviorsOK && statesOK && deepLinkOK && clientRoutingOK && codexMenuOK && integrationOK && setupOK && transcriptShapesOK && scalesOK && baselineOK && decoupledOK && fontOK && priorityOK && registryOK && titleOK && badgeLayoutOK && clickRoutingOK && gazeStatesOK && expandOK && lineBudgetOK && typefaceOK && textDeltaOK && tonesOK && folderFoldOK && labelOK && doneStaysOK && bubbleShapeOK && seenOK && staleOK
    print("{\"ok\":\(ok),\"asset\":\"\(Int(image.size.width))x\(Int(image.size.height))\",\"skins\":\(PetSkin.allCases.count),\"skinsOK\":\(skinsOK),\"dragRun\":\(dragRunOK),\"canJoinAllSpaces\":\(behaviorsOK),\"states\":\(animationCatalog.count),\"deepLink\":\(deepLinkOK),\"clientRouting\":\(clientRoutingOK),\"codexMenu\":\(codexMenuOK),\"integration\":\(integrationOK),\"setup\":\(setupOK),\"transcriptShapes\":\(transcriptShapesOK),\"sizePresets\":\(supportedScales.count),\"baselineLayout\":\(baselineOK),\"scaleDecoupled\":\(decoupledOK),\"badgePlacement\":\(badgeLayoutOK),\"ribbonExpand\":\(expandOK),\"lineBudget\":\(lineBudgetOK),\"typefaces\":\(PetTypeface.allCases.count),\"typefaceOK\":\(typefaceOK),\"textDelta\":\(textDeltaOK),\"tones\":\(tonesOK),\"folderFold\":\(folderFoldOK),\"doneStays\":\(doneStaysOK),\"bubbleShape\":\(bubbleShapeOK),\"seenRule\":\(seenOK),\"staleWorking\":\(staleOK),\"headroomClean\":\(haloOK),\"viewedElsewhere\":\(viewedOK),\"ancientNews\":\(ancientOK),\"sleeps\":\(sleepOK),\"sleepRow\":\(sleepRow),\"dozes\":\(dozeOK),\"displayState\":\(displayOK),\"seenByLooking\":\(lookingOK),\"corners\":\(cornerOK),\"appFallback\":\(fallbackOK),\"haloRows\":\(halo.rows),\"haloDeepest\":\(halo.deepest),\"haloFaint\":\(haloFaintPixels),\"claudeRow\":\(claudeRowOK),\"font\":\"\(rettoHandwritingFontName)\",\"fontLoaded\":\(fontOK),\"multiSession\":\(registryOK),\"sessionTitleFallback\":\(titleOK),\"prioritySelection\":\(priorityOK),\"badgeLayout\":\(badgeLayoutOK),\"clickRouting\":\(clickRoutingOK)}")
    return ok ? 0 : 1
}

/// 배율별 레이아웃을 화면 없이 PNG 한 장으로 뽑는다. 몸과 리본이 따로 자라는지 눈으로 확인하는 용도.
func renderPreview(to path: String) -> Int32 {
    registerRettoFont()
    guard let imageURL = Bundle.main.url(forResource: "spritesheet", withExtension: "webp"),
          let spriteSheet = NSImage(contentsOf: imageURL) else { return 1 }
    let scales: [CGFloat] = [0.39, 0.5, 0.65, 1.0, 1.4]
    // 칸마다 다른 상태로 그려 색 넷이 한 장에서 비교되게 한다.
    let previewStates = ["idle", "running", "waiting", "sleeping", "failed"]
    // 배지 모서리 네 곳을 한 장에서 다 보이게 돌려 쓴다.
    let gap: CGFloat = 24
    // 마지막 칸은 말풍선을 펼친 모습으로 그린다.
    let expandedFlags = scales.indices.map { $0 == scales.count - 1 }
    let layouts = zip(scales, expandedFlags).map { petLayout(scale: $0, expanded: $1) }
    let totalWidth = layouts.reduce(0) { $0 + $1.windowSize.width } + gap * CGFloat(layouts.count + 1)
    let bandHeight = (layouts.map(\.windowSize.height).max() ?? 0) + gap * 2 + 22
    // 어두운 배경만 보다가 흰 배경에서 머리 위 그림자를 놓친 적이 있다. 두 줄로 같이 본다.
    let bands: [(background: NSColor, card: NSColor, ink: NSColor)] = [
        (NSColor(calibratedWhite: 0.22, alpha: 1), NSColor(calibratedWhite: 1, alpha: 0.10), .white),
        (NSColor(calibratedWhite: 1.0, alpha: 1), NSColor(calibratedWhite: 0, alpha: 0.04), .black)
    ]
    let totalHeight = bandHeight * CGFloat(bands.count)

    let sheet = NSImage(size: NSSize(width: totalWidth, height: totalHeight))
    sheet.lockFocus()
    for (bandIndex, band) in bands.enumerated() {
    let bandOrigin = totalHeight - bandHeight * CGFloat(bandIndex + 1)
    band.background.setFill()
    NSRect(x: 0, y: bandOrigin, width: totalWidth, height: bandHeight).fill()
    var x = gap
    for (index, (scale, layout)) in zip(scales, layouts).enumerated() {
        let view = RettoView(frame: NSRect(origin: .zero, size: layout.windowSize), spriteSheet: spriteSheet, onOpenClaude: { _, _ in }, onOpenAttention: { _ in })
        // 서체를 바꿔 놓고 미리보기를 뽑아 눈으로 비교할 수 있어야 한다.
        view.typeface = PetTypeface(rawValue: UserDefaults.standard.string(forKey: typefaceDefaultsKey) ?? "") ?? .handwriting
        view.petScale = scale
        let petState = previewStates[min(index, previewStates.count - 1)]
        let body = "그 파란 숫자의 정체를 코드에서 확인하고 맞췄어. Claude Code 확장이 세션 목록 뷰에 붙이는 배지고, 기준 상태는 waiting_input 이야. 권한 요청만이 아니라 턴이 끝나 답을 기다리는 상태까지 포함해."
        let fixture = "{\"state\":\"\(petState)\",\"sessionId\":\"preview\",\"projectName\":\"platform-web-next\",\"displayTitle\":\"백오피스 조직별 화면 목업 다시 봐줘\",\"lastAssistantMessage\":\"\(body)\"}".data(using: .utf8)!
        guard let payload = try? JSONDecoder().decode(StatePayload.self, from: fixture) else { continue }
        view.apply(payload, sessionCount: 3, attentionCount: 2, attentionState: .waiting, isPinned: true)
        view.setExpandedForPreview(expandedFlags[index])
        view.settleAnimations()
        // 실제 창은 투명하므로 캐시 캡처(불투명 배경) 대신 뷰를 직접 그린다.
        let card = NSRect(x: x, y: bandOrigin + gap + 22, width: layout.windowSize.width, height: layout.windowSize.height)
        band.card.setFill()
        card.fill()
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: card.minX, yBy: card.minY)
        transform.concat()
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let label = String(format: "%.0f%%  %@  %@", scale * 100, petState, expandedFlags[index] ? "말풍선 펼침" : "접힘")
        (label as NSString).draw(at: NSPoint(x: x, y: bandOrigin + 6), withAttributes: [
            .foregroundColor: band.ink,
            .font: NSFont.boldSystemFont(ofSize: 12)
        ])
        x += layout.windowSize.width + gap
    }
    }
    sheet.unlockFocus()
    guard let tiff = sheet.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return 1 }
    do { try png.write(to: URL(fileURLWithPath: path)) } catch { return 1 }
    print(path)
    return 0
}
