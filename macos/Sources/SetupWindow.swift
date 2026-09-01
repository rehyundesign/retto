// 레토와 Claude Code 를 잇는 자리. 처음 켰을 때 저절로 뜨고, 발바닥 메뉴로도 연다.
//
// 있는 이유는 설치기가 터미널 창에만 말하기 때문이다. node 가 없어 훅을 건너뛰어도
// 그 창을 닫고 나면 아무 데도 남지 않고, 고양이는 똑같이 앉아 있다. 받아 간 사람이
// 알려 줄 수 있는 건 "쳐다만 보고 있다" 뿐이었다.
//
// 묻지 않고 살펴본다. "Claude 를 쓰나 Codex 를 쓰나" · "VS Code 인가 Claude 앱인가" 는
// 물어봐야 답이 우리가 이미 아는 것이다. 앞엣것은 홈 폴더를 보면 알고, 뒤엣것은 물으면
// 오히려 나빠진다 — 세션마다 어디서 왔는지 훅이 적어 두므로 자동이 항상 맞고,
// 하나로 고정하면 섞어 쓰는 순간 절반이 틀린다.

import AppKit

/// 이 사람이 무엇을 깔아 두었나. 마지막 안내 문구를 그 사람 것으로 바꾸는 데 쓴다.
struct RettoHostEnvironment {
    var hasClaudeApp = false
    var hasVSCode = false
    var hasVSCodeExtension = false
    var hasClaudeCLI = false
    var hasCodex = false

    static func detect() -> RettoHostEnvironment {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        var found = RettoHostEnvironment()

        found.hasClaudeApp = ["/Applications/Claude.app", home.path + "/Applications/Claude.app"]
            .contains { manager.fileExists(atPath: $0) }
        found.hasVSCode = ["/Applications/Visual Studio Code.app", home.path + "/Applications/Visual Studio Code.app"]
            .contains { manager.fileExists(atPath: $0) }
        if let extensions = try? manager.contentsOfDirectory(atPath: home.path + "/.vscode/extensions") {
            found.hasVSCodeExtension = extensions.contains { $0.hasPrefix("anthropic.claude-code") }
        }
        found.hasClaudeCLI = [
            home.path + "/.local/share/claude/versions",
            home.path + "/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ].contains { manager.fileExists(atPath: $0) }
        found.hasCodex = manager.fileExists(atPath: home.path + "/.codex")
        return found
    }

    /// 아직 소식이 없을 때 무엇을 해 보라고 할지. 깔려 있는 것만 말한다 —
    /// 없는 앱을 켜 보라고 하면 그 줄부터 믿지 않게 된다.
    var whatToTry: [String] {
        var lines: [String] = []
        if hasClaudeApp {
            lines.append("Claude 앱에서 폴더를 열고 Claude Code 세션을 시작해 보세요."
                + " 평소 대화창은 코드 세션이 아니라서 레토에게 보이지 않습니다.")
        }
        if hasVSCode {
            lines.append(hasVSCodeExtension
                ? "VS Code 에서 Claude Code 를 열어 보세요."
                : "VS Code 를 쓰신다면 Claude Code 확장을 먼저 설치해 주세요.")
        }
        if hasClaudeCLI {
            lines.append("터미널에서 claude 를 실행해도 됩니다.")
        }
        if hasCodex {
            lines.append("Codex 는 한 번 다시 켜서 훅 승인 화면이 나오면 허용해 주세요."
                + " 승인 전에는 Codex task 가 레토에게 보이지 않습니다.")
        }
        // 아무것도 못 찾았을 때도 할 말은 있어야 한다. 빈 자리는 고장으로 읽힌다.
        if lines.isEmpty {
            lines.append("Claude Code 를 먼저 설치해 주세요 — 터미널·VS Code·Claude 앱 어디서든 됩니다.")
        }
        return lines
    }
}

let setupSeenDefaultsKey = "RettoPetSetupSeen"

/// 창 폭. 상태에 따라 높이만 달라지고 폭은 그대로다.
let setupWindowWidth: CGFloat = 460

/// 처음 설정 창을 띄울 자리인가.
///
/// 한 번 본 사람에게는 다시 띄우지 않고, 이미 소식이 오고 있는 사람에게도 띄우지 않는다 —
/// 잘 돌고 있는데 설정 창이 뜨면 무언가 잘못된 줄 안다. 업데이트로 새로 깐 경우가 그렇다.
func shouldShowSetupOnLaunch(hasSeen: Bool, status: ClaudeIntegrationStatus) -> Bool {
    !hasSeen && status.lastNews.isEmpty
}

/// 상태 한 줄. 기호로 먼저 읽히고 글로 확인한다.
private struct StepRow {
    enum Mark { case ok, warn, waiting }
    var mark: Mark
    var title: String
    var detail: String

    var symbolName: String {
        switch mark {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .waiting: return "clock"
        }
    }

    var tint: NSColor {
        switch mark {
        case .ok: return NSColor.systemGreen
        case .warn: return NSColor.systemOrange
        case .waiting: return NSColor.secondaryLabelColor
        }
    }
}

/// 연결 상태를 보여주는 창. 알림창이 아니라 창인 이유는, 소식이 들어오는 것을
/// 그 자리에서 지켜봐야 하기 때문이다. 알림창은 떠 있는 동안 갱신할 수 없다.
final class SetupWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let rows = NSStackView()
    private let guidance = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(wrappingLabelWithString: "")
    private let fixButton = NSButton()
    private let nodeButton = NSButton()
    /// 처음 켜서 저절로 뜬 창만 첫 소식이 오면 스스로 닫는다.
    /// 메뉴로 연 창은 사람이 보러 온 것이므로 마음대로 닫지 않는다.
    private let closesOnFirstNews: Bool
    private let onReinstall: () -> Void
    private var closed = false

    init(firstRun: Bool, onReinstall: @escaping () -> Void) {
        self.closesOnFirstNews = firstRun
        self.onReinstall = onReinstall
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = firstRun ? "레토와 Claude Code 잇기" : "Claude 연동 확인"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 10

        guidance.font = NSFont.systemFont(ofSize: 12)
        guidance.textColor = .secondaryLabelColor
        guidance.preferredMaxLayoutWidth = setupWindowWidth - 44

        footer.font = NSFont.systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.preferredMaxLayoutWidth = setupWindowWidth - 44

        for (button, title, action) in [
            (fixButton, "훅 지금 붙이기", #selector(reinstall)),
            (nodeButton, "Node.js 받기", #selector(openNodeSite))
        ] as [(NSButton, String, Selector)] {
            button.title = title
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
        }

        let buttonRow = NSStackView(views: [fixButton, nodeButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let content = NSStackView(views: [rows, guidance, buttonRow, footer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)
        content.translatesAutoresizingMaskIntoConstraints = false

        let host = NSView()
        host.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            content.topAnchor.constraint(equalTo: host.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor),
            // 폭을 고정한다. 상태가 바뀔 때마다 폭이 따라 변하면 창이 튀어서,
            // 무엇이 바뀌었는지가 아니라 창이 움직인 것만 눈에 남는다.
            content.widthAnchor.constraint(equalToConstant: setupWindowWidth)
        ])
        window.contentView = host
    }

    var isOpen: Bool { !closed && window.isVisible }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        closed = true
        window.close()
    }

    /// 상태가 바뀔 때마다 부른다. 세션이 갱신될 때와 창을 열 때 모두 여기로 온다.
    func refresh(status: ClaudeIntegrationStatus, environment: RettoHostEnvironment) {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for row in steps(status: status) { rows.addArrangedSubview(view(for: row)) }

        let connected = !status.lastNews.isEmpty
        if connected {
            guidance.stringValue = status.lastNews
                .sorted { $0.key.label < $1.key.label }
                .map { "\($0.key.label) · \(elapsedLabel(since: $0.value))" }
                .joined(separator: "     ")
            footer.stringValue = "발바닥 메뉴 > 「Claude 연동 확인」에서 언제든 다시 볼 수 있습니다."
        } else {
            guidance.stringValue = environment.whatToTry.map { "· " + $0 }.joined(separator: "\n")
            footer.stringValue = "레토가 첫 소식을 받으면 이 창이 알려줍니다."
        }

        fixButton.isHidden = status.registeredEvents > 0 && status.shimInstalled && status.hookInstalled
        nodeButton.isHidden = status.nodePath != nil
        window.setContentSize(window.contentView?.fittingSize ?? window.frame.size)

        if connected, closesOnFirstNews, !closed {
            // 사람이 읽을 틈은 준다. 곧바로 닫으면 무엇이 지나갔는지 알 수 없다.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.close() }
        }
    }

    private func steps(status: ClaudeIntegrationStatus) -> [StepRow] {
        var list: [StepRow] = []

        if !status.settingsReadable {
            list.append(StepRow(mark: .warn, title: "훅 연결",
                                detail: "설정 파일을 읽지 못했습니다 — ~/.claude/settings.json 의 JSON 이 깨졌습니다"))
        } else if status.registeredEvents == 0 {
            list.append(StepRow(mark: .warn, title: "훅 연결", detail: "아직 등록되지 않았습니다"))
        } else if !status.shimInstalled || !status.hookInstalled {
            list.append(StepRow(mark: .warn, title: "훅 연결", detail: "등록은 됐는데 훅 파일이 없습니다"))
        } else {
            list.append(StepRow(mark: .ok, title: "훅 연결", detail: "\(status.registeredEvents)개 이벤트"))
        }

        list.append(status.nodePath.map { StepRow(mark: .ok, title: "node", detail: $0) }
            ?? StepRow(mark: .warn, title: "node", detail: "찾지 못했습니다 — 훅이 이걸로 돕니다"))

        list.append(status.lastNews.isEmpty
            ? StepRow(mark: .waiting, title: "첫 소식", detail: "기다리는 중…")
            : StepRow(mark: .ok, title: "연결됐어요", detail: "레토가 세션을 지켜보고 있습니다"))
        return list
    }

    private func view(for row: StepRow) -> NSView {
        let symbol = NSImageView()
        symbol.image = NSImage(systemSymbolName: row.symbolName, accessibilityDescription: row.title)
        symbol.contentTintColor = row.tint
        symbol.setContentHuggingPriority(.required, for: .horizontal)

        let title = NSTextField(labelWithString: row.title)
        title.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.widthAnchor.constraint(greaterThanOrEqualToConstant: 66).isActive = true

        let detail = NSTextField(labelWithString: row.detail)
        detail.font = NSFont.systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle

        let line = NSStackView(views: [symbol, title, detail])
        line.orientation = .horizontal
        line.spacing = 8
        line.alignment = .firstBaseline
        return line
    }

    /// 지금 보이는 단추. 그림으로는 라벨이 잡히지 않아서 검사는 이걸로 한다.
    var visibleButtonTitles: [String] {
        [fixButton, nodeButton].filter { !$0.isHidden }.map(\.title)
    }

    /// 창을 그림으로 뜬다. 화면 없이 배치를 확인하는 데 쓴다.
    func snapshot() -> NSBitmapImageRep? {
        guard let view = window.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        window.setContentSize(view.fittingSize)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    @objc private func reinstall() { onReinstall() }

    @objc private func openNodeSite() {
        if let url = URL(string: "https://nodejs.org") { NSWorkspace.shared.open(url) }
    }

    func windowWillClose(_ notification: Notification) {
        closed = true
        UserDefaults.standard.set(true, forKey: setupSeenDefaultsKey)
    }
}

/// 처음 설정 창을 화면 없이 그림으로 뽑는다. 창은 사람이 눌러야만 뜨는 것이라
/// 그러지 않으면 시험해 볼 방법이 없다 — 글자가 잘리거나 단추가 겹쳐도 모른다.
///
///     RettoClaudePet --setup-preview /tmp/setup.png
func renderSetupPreview(to path: String) -> Int32 {
    // 아직 아무 소식도 없는 첫 실행과, 방금 이어진 순간을 나란히 그린다.
    var blank = ClaudeIntegrationStatus()
    blank.shimInstalled = true
    blank.hookInstalled = true
    blank.registeredEvents = 17
    blank.nodePath = ClaudeIntegration.resolveNodePath()

    var broken = ClaudeIntegrationStatus()
    broken.lastNews = [:]

    var connected = blank
    connected.lastNews = [.vscode: Date(timeIntervalSinceNow: -180), .claudeApp: Date()]

    let environment = RettoHostEnvironment.detect()
    var shots: [NSBitmapImageRep] = []
    for status in [blank, broken, connected] {
        let window = SetupWindow(firstRun: true, onReinstall: {})
        window.refresh(status: status, environment: environment)
        guard let shot = window.snapshot() else { return 1 }
        shots.append(shot)
    }

    let gap: CGFloat = 16
    let width = shots.map { $0.size.width }.reduce(0, +) + gap * CGFloat(shots.count + 1)
    let height = (shots.map { $0.size.height }.max() ?? 0) + gap * 2
    let sheet = NSImage(size: NSSize(width: width, height: height))
    sheet.lockFocus()
    NSColor.windowBackgroundColor.setFill()
    NSRect(origin: .zero, size: sheet.size).fill()
    var x = gap
    for shot in shots {
        shot.draw(at: NSPoint(x: x, y: height - gap - shot.size.height))
        x += shot.size.width + gap
    }
    sheet.unlockFocus()

    guard let tiff = sheet.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return 1 }
    do { try png.write(to: URL(fileURLWithPath: path)) } catch { return 1 }
    print(path)
    return 0
}
