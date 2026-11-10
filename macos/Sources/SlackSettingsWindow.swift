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
        let heading = label("Slack 연결", bold: true)
        let guide = NSButton(title: "처음 연결하시나요? 연결 안내 ↗", target: self, action: #selector(showGuide))
        guide.bezelStyle = .rounded
        guide.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        guide.imagePosition = .imageLeading
        guide.contentTintColor = .linkColor
        guide.toolTip = "브라우저에서 단계별 연결 안내를 엽니다. 설정 JSON 복사와 토큰 발급 위치를 확인할 수 있습니다."
        guide.setAccessibilityLabel("Slack 연결 안내 열기")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let headingRow = NSStackView(views: [heading, spacer, guide])
        headingRow.spacing = 8
        add(headingRow)
        add(status)
        add(label("처음 연결할 때는 두 토큰을 입력해 주세요. 연결 후 비워 둔 토큰은 기존 값을 유지합니다. 토큰은 키체인에서 관리합니다."))
        userToken.placeholderString = "사용자 OAuth 토큰 · xoxp-"
        appToken.placeholderString = "앱 수준 토큰 · xapp-"
        userToken.setAccessibilityLabel("Slack 사용자 OAuth 토큰")
        appToken.setAccessibilityLabel("Slack 앱 수준 토큰")
        userToken.toolTip = "OAuth & Permissions → User OAuth Token에서 복사합니다. xoxp-로 시작하는 값입니다."
        appToken.toolTip = "Basic Information → App-Level Tokens에서 발급합니다. xapp-로 시작하며 connections:write 권한이 필요합니다."
        add(userToken); add(appToken)
        let connect = NSButton(title: "저장하고 연결", target: self, action: #selector(connectSlack))
        let disconnect = NSButton(title: "연결 해제", target: self, action: #selector(disconnectSlack))
        let actions = NSStackView(views: [connect, disconnect]); actions.spacing = 8
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
        add(label("Slack에서 읽은 메시지는 읽음 위치를 확인한 뒤 레토에서도 해제합니다. 대상별 15초 간격으로 순환 조회합니다. 같은 워크스페이스의 DM·채널 창을 3초 이상 보고 있으면 읽음 조회를 앞당깁니다. Slack이 제공한 읽음 위치까지 알림을 해제합니다. 스레드는 API 읽음 위치로 확인합니다. Slack의 읽음 상태는 바꾸지 않습니다."))
        refresh(forceChannels: true)
    }
    func show() {
        refresh(forceChannels: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func refresh(forceChannels: Bool = false) {
        status.stringValue = [integration.status, integration.readSyncIssue].compactMap { $0 }.joined(separator: "\n")
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
        do {
            let url = try SlackConnectionGuide.writeDocument()
            guard NSWorkspace.shared.open(url) else {
                throw NSError(domain: "RettoSlackGuide", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "기본 브라우저에서 안내를 열지 못했습니다."])
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "연결 안내를 열지 못했습니다"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "확인")
            alert.beginSheetModal(for: window)
        }
    }
}
