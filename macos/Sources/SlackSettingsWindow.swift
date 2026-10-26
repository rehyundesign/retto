import AppKit

// 기존 AppKit 설정 창과 같은 방식으로 유지한다. 비밀 값은 저장 후 필드에서도 지운다.
final class SlackSettingsWindow: NSObject {
    private let integration: SlackIntegration
    private let window: NSWindow
    private let status = NSTextField(wrappingLabelWithString: "")
    private let userToken = NSSecureTextField()
    private let appToken = NSSecureTextField()
    private let dm = NSButton(checkboxWithTitle: "DM 알림 (그룹 DM 포함)", target: nil, action: nil)
    private let mentions = NSButton(checkboxWithTitle: "내 멘션 알림", target: nil, action: nil)
    private let preview = NSButton(checkboxWithTitle: "메시지 내용 미리보기", target: nil, action: nil)
    private let channelRows = NSStackView()
    private var channelHeight: NSLayoutConstraint!
    private var renderedChannels: [SlackChannel] = []

    init(integration: SlackIntegration) {
        self.integration = integration
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 650),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Slack 설정"
        window.isReleasedWhenClosed = false
        window.center()
        let root = NSStackView()
        root.orientation = .vertical; root.alignment = .leading; root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -16)
        ])
        func label(_ text: String, bold: Bool = false) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = bold ? .boldSystemFont(ofSize: 14) : .systemFont(ofSize: 12)
            field.preferredMaxLayoutWidth = 470
            return field
        }
        func add(_ view: NSView) {
            root.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        add(label("Slack 연결", bold: true))
        add(status)
        add(label("처음 연결할 때는 두 토큰을 입력해 주세요. 연결 후 비워 둔 토큰은 기존 값을 유지합니다. 토큰은 키체인에서 관리합니다."))
        userToken.placeholderString = "사용자 OAuth 토큰 · xoxp-"
        appToken.placeholderString = "앱 수준 토큰 · xapp-"
        userToken.setAccessibilityLabel("Slack 사용자 OAuth 토큰")
        appToken.setAccessibilityLabel("Slack 앱 수준 토큰")
        add(userToken); add(appToken)
        let connect = NSButton(title: "저장하고 연결", target: self, action: #selector(connectSlack))
        let disconnect = NSButton(title: "연결 해제", target: self, action: #selector(disconnectSlack))
        let guide = NSButton(title: "연결 안내", target: self, action: #selector(showGuide))
        let actions = NSStackView(views: [connect, disconnect, guide]); actions.spacing = 8
        root.addArrangedSubview(actions)
        add(label("알림 받을 메시지", bold: true))
        for button in [dm, mentions, preview] {
            button.target = self; button.action = #selector(savePreferences)
            root.addArrangedSubview(button)
        }
        add(label("추가로 선택한 채널에서는 모든 새 메시지를 알려줍니다. 선택하지 않은 채널의 내 멘션도 위 설정을 따릅니다."))
        let reload = NSButton(title: "채널 목록 새로고침", target: self, action: #selector(refreshChannels))
        let retry = NSButton(title: "연결 다시 시도", target: self, action: #selector(reconnectSlack))
        let tools = NSStackView(views: [reload, retry]); tools.spacing = 8
        root.addArrangedSubview(tools)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        channelRows.orientation = .vertical; channelRows.alignment = .leading; channelRows.spacing = 6
        channelRows.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = channelRows
        add(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 140).isActive = true
        channelRows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        channelHeight = channelRows.heightAnchor.constraint(equalToConstant: 24)
        channelHeight.isActive = true
        channelRows.setContentHuggingPriority(.required, for: .vertical)
        channelRows.topAnchor.constraint(equalTo: scroll.contentView.topAnchor).isActive = true
        channelRows.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor).isActive = true
        add(label("레토가 실행 중일 때 도착한 새 메시지를 표시합니다. 레토에서 메시지를 열거나 알림을 지우면 표시가 사라지며, Slack의 읽음 상태는 바꾸지 않습니다."))
        refresh(forceChannels: true)
    }
    func show() {
        refresh(forceChannels: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func refresh(forceChannels: Bool = false) {
        status.stringValue = integration.status
        dm.state = integration.preferences.directMessages ? .on : .off
        mentions.state = integration.preferences.mentions ? .on : .off
        preview.state = integration.preferences.preview ? .on : .off
        guard forceChannels || renderedChannels != integration.channels else { return }
        renderedChannels = integration.channels
        channelHeight.constant = CGFloat(max(1, renderedChannels.count)) * 24
        for view in channelRows.arrangedSubviews { channelRows.removeArrangedSubview(view); view.removeFromSuperview() }
        if renderedChannels.isEmpty {
            channelRows.addArrangedSubview(NSTextField(wrappingLabelWithString: "연결 후 참여 중인 채널을 불러옵니다."))
        }
        for channel in renderedChannels {
            let button = NSButton(checkboxWithTitle: "#" + channel.name, target: self, action: #selector(toggleChannel(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(channel.id)
            button.state = integration.preferences.channelIDs.contains(channel.id) ? .on : .off
            channelRows.addArrangedSubview(button)
        }
    }
    func renderPreview(to path: String) -> Bool {
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let source = bitmap.cgImage,
              let context = CGContext(data: nil, width: source.width, height: source.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        context.setFillColor(CGColor(gray: 0.96, alpha: 1))
        context.fill(rect)
        context.draw(source, in: rect)
        guard let rendered = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else { return false }
        defer { window.orderOut(nil) }
        do { try data.write(to: URL(fileURLWithPath: path)); return true } catch { return false }
    }
    @objc private func connectSlack() {
        do {
            try integration.connect(userToken: userToken.stringValue, appToken: appToken.stringValue)
            userToken.stringValue = ""; appToken.stringValue = ""
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func disconnectSlack() {
        do {
            try integration.disconnect()
            userToken.stringValue = ""; appToken.stringValue = ""
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func savePreferences() {
        var value = integration.preferences
        value.directMessages = dm.state == .on
        value.mentions = mentions.state == .on
        value.preview = preview.state == .on
        integration.preferences = value
    }
    @objc private func toggleChannel(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        var value = integration.preferences
        if sender.state == .on { value.channelIDs.insert(id) } else { value.channelIDs.remove(id) }
        integration.preferences = value
    }
    @objc private func reconnectSlack() { integration.reconnect() }
    @objc private func refreshChannels() {
        Task { @MainActor [weak self] in await self?.integration.refreshChannels() }
    }
    @objc private func showGuide() {
        let alert = NSAlert()
        alert.messageText = "Slack 연결 준비"
        alert.informativeText = """
        1. api.slack.com/apps에서 개인용 Slack 앱을 만드세요. 워크스페이스에 따라 관리자 승인이 필요합니다.
        2. OAuth & Permissions → User Token Scopes에 channels:read, groups:read, users:read, channels:history, groups:history, im:history, mpim:history를 추가하고 워크스페이스에 설치하세요. 사용자 토큰(xoxp-)을 복사하세요.
        3. Event Subscriptions → Subscribe to events on behalf of users에 message.channels, message.groups, message.im, message.mpim을 추가하세요. 봇의 app_mention은 내 멘션과 다릅니다.
        4. Socket Mode를 켜고 Basic Information → App-Level Tokens에서 connections:write 권한의 토큰(xapp-)을 만드세요.
        5. 같은 앱의 두 토큰을 이 창에 입력하고 연결하세요. 권한을 변경했다면 앱을 다시 설치하세요.

        토큰은 이 채팅에 보내지 마세요. 한 Slack 앱에 여러 사용자가 설치한 경우 이벤트가 공유될 수 있으므로 본인만 설치하는 전용 앱을 사용하세요. 앱의 다른 Socket Mode 연결을 함께 실행하지 마세요.
        """
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "Slack 앱 관리 열기")
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(URL(string: "https://api.slack.com/apps")!) }
    }
}
