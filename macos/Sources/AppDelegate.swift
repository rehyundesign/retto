// 창·메뉴·세션 감시. 클릭을 실제 동작으로 옮긴다.

import AppKit
import CoreText
import Foundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: OverlayPanel!
    private var petView: RettoView!
    private var stateMonitor: StateMonitor!
    private var statusItem: NSStatusItem!
    private var visibilityItem: NSMenuItem!
    private var clickThroughItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var sizeItems: [NSMenuItem] = []
    private var openTargetItems: [NSMenuItem] = []
    private var currentScale: CGFloat = 1.0
    private var sessionsMenu = NSMenu(title: "Claude 세션")
    private var autoSelectionItem: NSMenuItem!
    private var sessions: [StatePayload] = []
    private var selectedPayload: StatePayload?
    private let transcriptReader = TranscriptReader()
    private var clearAttentionItem: NSMenuItem!
    private var typefaceItems: [NSMenuItem] = []
    private var skinItems: [NSMenuItem] = []
    /// 이 순간부터의 일만 새 소식으로 센다. 앱이 켜진 시각.
    private let trackingStartedAtMs = Date().timeIntervalSince1970 * 1000
    private var pinnedCorner: PetCorner {
        get { PetCorner(rawValue: UserDefaults.standard.string(forKey: cornerDefaultsKey) ?? "") ?? .free }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: cornerDefaultsKey) }
    }
    private var cornerItems: [NSMenuItem] = []
    /// 우리가 창을 옮기는 동안에는 windowDidMove 를 사용자의 드래그로 오해하지 않는다.
    private var isRepositioning = false
    /// 제거를 시작하면 켠다. 종료 직전에 설정을 한 번 더 지우는 근거다.
    private var isUninstalling = false
    /// 세션이 없을 때 쓰는 빈 껍데기. 상태·이름·멘트는 넘겨 주는 값으로 덮는다.
    private static let placeholderPayload: StatePayload? = {
        let fixture = "{\"state\":\"idle\",\"sessionId\":\"placeholder\"}".data(using: .utf8)!
        return try? JSONDecoder().decode(StatePayload.self, from: fixture)
    }()
    private var lookingApp: String?
    private var lookingSince: Date?
    /// 세션마다 마지막으로 다녀온 시각. 다음 실행에도 유지한다.
    private var seenSessions: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: seenSessionsDefaultsKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: seenSessionsDefaultsKey) }
    }

    private func markSeen(_ payload: StatePayload?) {
        guard let payload, !payload.id.isEmpty else { return }
        var seen = seenSessions
        seen[payload.id] = max(payload.updatedAtMs ?? 0, Date().timeIntervalSince1970 * 1000)
        // 닫힌 세션 기록은 버린다
        let live = Set(sessions.map(\.id))
        seenSessions = seen.filter { live.contains($0.key) || $0.key == payload.id }
        applySessions(sessions)
    }

    /// 읽고 넘어간 세션, 그리고 소식이 끊긴 "작업 중" 은 조용한 상태로 본다.
    private func effectiveState(_ payload: StatePayload) -> PetState {
        displayState(
            state: payload.petState,
            updatedAtMs: payload.updatedAtMs,
            seenAtMs: seenSessions[payload.id],
            transcriptModifiedAtMs: transcriptModifiedAtMs(path: payload.transcriptPath),
            nowMs: Date().timeIntervalSince1970 * 1000
        )
    }

    private func needsAttention(_ payload: StatePayload) -> Bool {
        guard payload.needsAttention else { return false }
        if isSeen(updatedAtMs: payload.updatedAtMs, seenAtMs: seenSessions[payload.id]) { return false }
        // 앱이 켜지기 한참 전에 끝난 일은 조용히 읽음으로 넘긴다. 첫 설치나 재시작 뒤에
        // 이레치 완료 세션이 한꺼번에 배지로 몰려오던 문제.
        if seenSessions[payload.id] == nil,
           isAncientNews(updatedAtMs: payload.updatedAtMs, trackingStartedAtMs: trackingStartedAtMs) {
            recordSeenFromAccess(payload)
            return false
        }
        // 레토를 누르지 않고 직접 세션에 들어가 읽은 경우. 트랜스크립트 접근 시각으로 알아낸다.
        if let accessed = transcriptAccessedAtMs(path: payload.transcriptPath),
           wasViewedElsewhere(accessedAtMs: accessed, updatedAtMs: payload.updatedAtMs) {
            // 한 번 판정하면 붙잡아 둔다. 나중에 atime 이 다시 밀려도 흔들리지 않는다.
            recordSeenFromAccess(payload)
            return false
        }
        return true
    }

    /// 밖에서 읽은 것을 읽음 기록에 옮긴다. 다음 폴링부터는 stat 없이 바로 걸러진다.
    private func recordSeenFromAccess(_ payload: StatePayload) {
        guard seenSessions[payload.id] == nil || seenSessions[payload.id]! < (payload.updatedAtMs ?? 0) else { return }
        var seen = seenSessions
        seen[payload.id] = max(payload.updatedAtMs ?? 0, Date().timeIntervalSince1970 * 1000)
        seenSessions = seen
    }

    /// 배지가 세는 집합. 배지를 눌렀을 때 나오는 목록도 반드시 같은 집합이어야 한다.
    /// 예전에는 배지는 완료만 세고 목록은 대기·실패까지 보여줘서, 배지에 1 이 떴는데
    /// 목록에 셋이 나오고 엉뚱한 세션이 열리는 일이 있었다.
    private func badgeSessions() -> [StatePayload] {
        sessions.filter { !$0.isClosed && needsAttention($0) && effectiveState($0) == .waving }
    }

    private var pinnedSessionId: String? {
        get { UserDefaults.standard.string(forKey: "RettoClaudePetPinnedSession") }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: "RettoClaudePetPinnedSession") }
            else { UserDefaults.standard.removeObject(forKey: "RettoClaudePetPinnedSession") }
        }
    }

    /// 레토의 겉모습. 고르면 아틀라스를 갈아 끼우고 다음 실행에도 남는다.
    private var skin: PetSkin {
        get { PetSkin(rawValue: UserDefaults.standard.string(forKey: skinDefaultsKey) ?? "") ?? .classic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: skinDefaultsKey) }
    }

    /// 스킨의 아틀라스를 읽는다. 파일이 없으면 기본 스킨으로 물러난다 —
    /// 옛 앱에 새 스킨 설정만 남아 있는 경우에도 레토가 사라지지 않게.
    private func loadSpriteSheet(_ skin: PetSkin) -> NSImage? {
        if let url = Bundle.main.url(forResource: skin.resourceName, withExtension: "webp"),
           let image = NSImage(contentsOf: url) { return image }
        guard skin != .classic else { return nil }
        return loadSpriteSheet(.classic)
    }

    /// 말풍선 글꼴. 고르면 바로 다시 그리고 다음 실행에도 남는다.
    private var typeface: PetTypeface {
        get { PetTypeface(rawValue: UserDefaults.standard.string(forKey: typefaceDefaultsKey) ?? "") ?? .handwriting }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: typefaceDefaultsKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 설정을 하나라도 읽기 전에 옮겨 와야 한다. createPanel 이 크기·위치를 바로 읽는다.
        migrateLegacyDefaults()
        registerRettoFont()
        guard let spriteSheet = loadSpriteSheet(skin) else {
            NSAlert(error: NSError(domain: "RettoClaudePet", code: 1, userInfo: [NSLocalizedDescriptionKey: "레토 스프라이트를 불러오지 못했어요."])).runModal()
            NSApp.terminate(nil)
            return
        }

        createPanel(spriteSheet: spriteSheet)
        createMenuBarItem()
        startStateMonitor()
        NotificationCenter.default.addObserver(self, selector: #selector(screenConfigurationChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Reto → Retto 로 이름을 바로잡으면서 번들 ID 와 설정 키가 함께 바뀌었다.
    /// macOS 는 번들 ID 로 설정 자리를 잡으므로, 그냥 두면 크기·위치·고정한 세션이 전부 초기값으로 돌아간다.
    /// 옛 자리에서 한 번만 끌어오고 지운다. 샌드박스가 아니라서 옛 도메인을 직접 읽을 수 있다.
    private func migrateLegacyDefaults() {
        let legacyDomain = "com.luxia.reto-claude-pet"
        let defaults = UserDefaults.standard
        guard let legacy = defaults.persistentDomain(forName: legacyDomain), !legacy.isEmpty else { return }

        for (legacyKey, value) in legacy {
            // 키 이름도 같이 바뀌었다. 접두사만 갈아 끼우고, 이미 새 값이 있으면 건드리지 않는다.
            let key = legacyKey.hasPrefix("RetoClaudePet")
                ? "RettoClaudePet" + legacyKey.dropFirst("RetoClaudePet".count)
                : legacyKey
            if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
        }
        defaults.removePersistentDomain(forName: legacyDomain)
    }

    private func createPanel(spriteSheet: NSImage) {
        let savedScale = UserDefaults.standard.double(forKey: "RettoClaudePetScale")
        currentScale = supportedScales.min(by: { abs($0 - CGFloat(savedScale == 0 ? 1 : savedScale)) < abs($1 - CGFloat(savedScale == 0 ? 1 : savedScale)) }) ?? 1
        let size = scaledWindowSize(currentScale)
        // 화면이 여럿이면 마지막에 있던 화면에 붙인다. main 화면은 키보드 초점을 따라 바뀌어서,
        // 그것만 보면 재시작할 때마다 레토가 다른 모니터로 건너간다.
        let origin = cornerOrigin(corner: pinnedCorner, size: size, visible: lastKnownScreen(for: size).visibleFrame)
            ?? initialOrigin(for: size)
        panel = OverlayPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = allSpacesBehavior
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.delegate = self

        petView = RettoView(
            frame: NSRect(origin: .zero, size: size),
            spriteSheet: spriteSheet,
            onOpenClaude: { [weak self] payload, windowOnly in
                self?.revealClaudeSession(payload, windowOnly: windowOnly)
            },
            onOpenAttention: { [weak self] point in self?.showAttentionMenu(at: point) }
        )
        petView.petScale = currentScale
        petView.typeface = typeface
        petView.onExpansionChanged = { [weak self] expanded in
            self?.applyRibbonExpansion(expanded)
        }
        panel.contentView = petView
        panel.orderFrontRegardless()
    }

    /// 메뉴에서 고른 값. 저장된 게 없거나 알 수 없는 값이면 자동.
    private var openTarget: OpenTarget {
        get { OpenTarget(rawValue: UserDefaults.standard.string(forKey: openTargetDefaultsKey) ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: openTargetDefaultsKey) }
    }

    /// 깔려 있지 않은 앱으로 보내지 않는다.
    private func availableOpenApp(_ preferred: OpenApp) -> OpenApp {
        installedOpenApp(preferred: preferred) { app in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) != nil
                || FileManager.default.fileExists(atPath: app.fallbackPath)
        }
    }

    private func resolveOpenApp(for payload: StatePayload?) -> OpenApp {
        switch openTarget {
        // 자동일 때만 되돌린다. 메뉴에서 직접 고른 것은 그 뜻을 지킨다.
        case .auto: return availableOpenApp(openApp(forClient: payload?.client))
        case .vscode: return .vscode
        case .claude: return .claude
        }
    }

    private func createMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // 이름을 주면 메뉴 막대에서의 자리를 macOS 가 기억한다. 안 주면 실행할 때마다 새로 배정받고,
        // 노치 있는 맥북처럼 자리가 빠듯하면 그대로 노치 뒤로 밀려 사라진 것처럼 보인다.
        // 번들 ID 와 무관한 고정 문자열이라, 다음에 ID 가 또 바뀌어도 자리는 남는다.
        statusItem.autosaveName = "RettoClaudePetStatusItem"
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: Retto.englishName)
        statusItem.button?.toolTip = Retto.englishName + " · " + Retto.character

        let menu = NSMenu(title: "Retto")
        // 항목의 isEnabled 를 우리가 정한다. 켜 두면 AppKit 이 target 유무만 보고 전부 켜 버린다.
        menu.autoenablesItems = false

        // 레토가 누구이고 누가 만들었는지가 맨 처음 눈에 들어와야 한다.
        // 메뉴 중간에 두면 크기·세션 항목에 묻혀서 아무도 찾지 못한다.
        let aboutItem = NSMenuItem(title: Retto.englishName + " · " + Retto.koreanName + " 정보", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        visibilityItem = NSMenuItem(title: "레토 숨기기", action: #selector(toggleVisibility), keyEquivalent: "")
        visibilityItem.target = self
        menu.addItem(visibilityItem)

        clickThroughItem = NSMenuItem(title: "클릭 통과 켜기", action: #selector(toggleClickThrough), keyEquivalent: "")
        clickThroughItem.target = self
        menu.addItem(clickThroughItem)

        launchAtLoginItem = NSMenuItem(title: "로그인할 때 자동 실행", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        // 여기부터 세션 묶음. 무엇을 보여줄지 고르는 항목들이다.
        menu.addItem(.separator())

        let sessionsItem = NSMenuItem(title: "Claude 세션", action: nil, keyEquivalent: "")
        sessionsItem.submenu = sessionsMenu
        menu.addItem(sessionsItem)
        rebuildSessionsMenu()

        let openTargetItem = NSMenuItem(title: "세션 열 곳", action: nil, keyEquivalent: "")
        let openTargetMenu = NSMenu(title: "세션 열 곳")
        openTargetItems = OpenTarget.allCases.map { target in
            let item = NSMenuItem(title: target.label, action: #selector(changeOpenTarget(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = target.rawValue
            item.state = target == openTarget ? .on : .off
            openTargetMenu.addItem(item)
            return item
        }
        openTargetItem.submenu = openTargetMenu
        menu.addItem(openTargetItem)

        // 레토를 누르지 않고 세션에 직접 다녀오는 경우가 있다. 그때 손으로 지울 길을 둔다.
        // 시간이 지나면 저절로 조용해지게 하지는 않는다 — 돌려놓고 한참 뒤에 오는 게 배지의 쓸모다.
        clearAttentionItem = NSMenuItem(title: "완료 표시 지우기", action: #selector(markAllSeen), keyEquivalent: "")
        clearAttentionItem.target = self
        menu.addItem(clearAttentionItem)

        // 여기부터 모양 묶음. 레토가 어떻게 보일지 정하는 항목들이다.
        menu.addItem(.separator())

        let sizeItem = NSMenuItem(title: "크기", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu(title: "크기")
        sizeItems = supportedScales.map { scale in
            let percent = Int((scale * 100).rounded())
            let label: String
            switch percent {
            case 39: label = "초소형 · 39%"
            case 50: label = "아주 작게 · 50%"
            case 65: label = "작게 · 65%"
            case 80: label = "조금 작게 · 80%"
            case 100: label = "보통 · 100%"
            case 120: label = "크게 · 120%"
            default: label = "가장 크게 · 140%"
            }
            let item = NSMenuItem(title: label, action: #selector(changeScale(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: Double(scale))
            item.state = abs(scale - currentScale) < 0.001 ? .on : .off
            sizeMenu.addItem(item)
            return item
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        // 겉모습. 아틀라스만 갈아 끼우므로 상태·말풍선 동작은 그대로다.
        let skinMenu = NSMenu(title: "스킨")
        skinMenu.autoenablesItems = false
        skinItems = PetSkin.allCases.map { value in
            let item = NSMenuItem(title: value.label, action: #selector(changeSkin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
            item.state = value == skin ? .on : .off
            skinMenu.addItem(item)
            return item
        }
        let skinItem = NSMenuItem(title: "스킨", action: nil, keyEquivalent: "")
        skinItem.submenu = skinMenu
        menu.addItem(skinItem)

        // 손글씨가 예쁘지만 작은 배율에서 읽기 힘들다는 사람이 있다. 골라 쓰게 둔다.
        let typefaceMenu = NSMenu(title: "서체")
        typefaceMenu.autoenablesItems = false
        typefaceItems = PetTypeface.allCases.map { face in
            let item = NSMenuItem(title: face.label, action: #selector(changeTypeface(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = face.rawValue
            item.state = face == typeface ? .on : .off
            typefaceMenu.addItem(item)
            return item
        }
        let typefaceItem = NSMenuItem(title: "서체", action: nil, keyEquivalent: "")
        typefaceItem.submenu = typefaceMenu
        menu.addItem(typefaceItem)

        let cornerMenu = NSMenu(title: "위치")
        cornerMenu.autoenablesItems = false
        cornerItems = PetCorner.allCases.map { corner in
            let item = NSMenuItem(title: corner.label, action: #selector(changeCorner(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = corner.rawValue
            item.state = corner == pinnedCorner ? .on : .off
            cornerMenu.addItem(item)
            return item
        }
        let cornerItem = NSMenuItem(title: "위치", action: nil, keyEquivalent: "")
        cornerItem.submenu = cornerMenu
        menu.addItem(cornerItem)

        // 여기부터 손볼 일 묶음. 평소에는 누를 일이 없는 항목들이다.
        menu.addItem(.separator())

        let stateItem = NSMenuItem(title: "Claude 상태 파일 보기", action: #selector(revealStateFile), keyEquivalent: "")
        stateItem.target = self
        menu.addItem(stateItem)

        let uninstallItem = NSMenuItem(title: "레토 제거…", action: #selector(uninstallRetto), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "레토 종료", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        petView.menu = menu
    }

    private func startStateMonitor() {
        let petDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/retto-pet")
        stateMonitor = StateMonitor(
            registryURL: petDirectory.appendingPathComponent("sessions.json"),
            fallbackStateURL: petDirectory.appendingPathComponent("state.json")
        ) { [weak self] sessions in
            self?.applySessions(sessions)
        }
        stateMonitor.start()
    }

    private func statePriority(_ payload: StatePayload) -> Int {
        selectionPriority(state: effectiveState(payload), isClosed: payload.isClosed)
    }

    private func applySessions(_ incoming: [StatePayload]) {
        sessions = incoming.sorted {
            let leftPriority = statePriority($0)
            let rightPriority = statePriority($1)
            if leftPriority != rightPriority { return leftPriority > rightPriority }
            return ($0.updatedAtMs ?? 0) > ($1.updatedAtMs ?? 0)
        }
        let openSessions = sessions.filter { !$0.isClosed }
        let attentionSessions = openSessions.filter { self.needsAttention($0) }
        if let pinnedSessionId,
           let pinned = openSessions.first(where: { $0.id == pinnedSessionId }) {
            // 고정은 지켜주되, 손이 필요한 세션이 생기면 그쪽을 먼저 보여준다.
            // Claude 사이드바에 파란 숫자가 떴는데 레토가 딴 데를 보고 있으면 배지가 무슨 뜻이 없다.
            // openSessions 는 이미 우선순위대로 정렬돼 있어 첫 항목이 가장 급한 세션이다.
            selectedPayload = needsAttention(pinned) ? pinned : (attentionSessions.first ?? pinned)
        } else {
            if pinnedSessionId != nil { self.pinnedSessionId = nil }
            selectedPayload = openSessions.first ?? sessions.first
        }
        guard let selectedPayload else {
            // 세션이 하나도 없다. 첫 실행이거나 Claude Code 를 아직 안 켠 것이다.
            // 예전에는 여기서 아무것도 하지 않아서, 받는 사람이 이름표에 "Claude Code" 만
            // 걸린 고양이를 보고 고장인지 아닌지 알 수 없었다.
            updateClearAttentionItem(count: 0)
            if let placeholder = Self.placeholderPayload {
                petView.apply(
                    placeholder,
                    state: .sleeping,
                    liveMessage: "Claude Code 를 켜면 여기서 알려줄게",
                    liveTitle: Retto.koreanName,
                    sessionCount: 0,
                    attentionCount: 0,
                    isPinned: false
                )
            }
            rebuildSessionsMenu()
            return
        }
        // 배지는 "답변이 끝났는데 아직 안 본" 세션만 센다. 대기·실패는 이름표 색이 이미 말해 준다.
        markSeenByLooking()
        let attention = badgeSessions()
        updateClearAttentionItem(count: attention.count)
        // 전부 회색인 채로 10분이 지나면 레토도 잔다. 그때는 세션 이름 대신 레토 이름을 걸고
        // 말풍선에도 잠꼬대만 남긴다 — 보여 줄 새 소식이 없다는 뜻이다.
        let nowMs = Date().timeIntervalSince1970 * 1000
        let asleep = shouldSleep(
            newestUpdatedAtMs: openSessions.compactMap(\.updatedAtMs).max(),
            nowMs: nowMs,
            hasBusySession: openSessions.contains { effectiveState($0) != .idle }
        )
        // 다 끝냈는데 아무도 보러 오지 않은 채 30분이 지난 경우. 알릴 것은 그대로 두고
        // 그림만 잠든다 — 기다리다 졸았다는 뜻이다.
        let dozing = !asleep && shouldDozeWhileWaiting(
            newestAttentionAtMs: attention.compactMap(\.updatedAtMs).max(),
            nowMs: nowMs,
            everythingDone: openSessions.allSatisfy {
                let live = effectiveState($0)
                return live == .idle || live == .waving
            }
        )
        petView.apply(
            selectedPayload,
            state: asleep ? .sleeping : effectiveState(selectedPayload),
            liveMessage: asleep ? "Zzz…" : transcriptReader.latestAssistantText(at: selectedPayload.transcriptPath),
            liveTitle: asleep ? "레토" : transcriptReader.latestTitle(at: selectedPayload.transcriptPath),
            sleepPose: dozing,
            sessionCount: openSessions.count,
            attentionCount: attention.count,
            attentionState: attention.max(by: { statePriority($0) < statePriority($1) })?.petState,
            isPinned: selectedPayload.id == pinnedSessionId
        )
        rebuildSessionsMenu()
    }

    private func stateMark(for payload: StatePayload) -> String {
        switch payload.petState {
        case .waiting: return "● 기다림"
        case .failed: return "● 실패"
        case .running, .review: return "● 작업 중"
        case .waving: return "● 완료"
        default: return "○ 쉬는 중"
        }
    }

    private func sessionLabel(for payload: StatePayload) -> String {
        "\(stateMark(for: payload))  \(payload.project) · \(String(payload.title.prefix(42)))"
    }

    /// 배지를 누르면 배지가 세던 세션들을 그대로 목록으로 보여준다. 하나뿐이면 묻지 않고 바로 연다.
    private func showAttentionMenu(at point: NSPoint) {
        let waiting = badgeSessions()
        guard let first = waiting.first else {
            revealClaudeSession(nil, windowOnly: false)
            return
        }
        if waiting.count == 1 {
            revealClaudeSession(first, windowOnly: false)
            return
        }
        let menu = NSMenu(title: "손이 필요한 세션")
        let header = NSMenuItem(title: "\(waiting.count)개 세션이 기다려요", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        for payload in waiting.prefix(12) {
            let item = NSMenuItem(title: sessionLabel(for: payload), action: #selector(openSessionFromBadge(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = payload.id
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: point, in: petView)
    }

    @objc private func openSessionFromBadge(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? String,
              let payload = sessions.first(where: { $0.id == sessionId }) else { return }
        // ⌥ 를 누른 채 고르면 창만 앞으로 보내고 탭은 건드리지 않는다.
        revealClaudeSession(payload, windowOnly: NSEvent.modifierFlags.contains(.option))
    }

    private func rebuildSessionsMenu() {
        sessionsMenu.removeAllItems()
        autoSelectionItem = NSMenuItem(title: "중요한 세션 자동으로 따라가기", action: #selector(selectAutomaticSession), keyEquivalent: "")
        autoSelectionItem.target = self
        autoSelectionItem.state = pinnedSessionId == nil ? .on : .off
        sessionsMenu.addItem(autoSelectionItem)
        sessionsMenu.addItem(.separator())

        let recent = sessions.filter { !$0.isClosed }.prefix(12)
        if recent.isEmpty {
            let emptyItem = NSMenuItem(title: "실행 중인 Claude 세션이 없어요", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            sessionsMenu.addItem(emptyItem)
            return
        }
        for payload in recent {
            let item = NSMenuItem(title: sessionLabel(for: payload), action: #selector(selectSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = payload.id
            item.state = pinnedSessionId == payload.id ? .on : .off
            sessionsMenu.addItem(item)
        }
    }

    private func initialOrigin(for size: NSSize) -> NSPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "RettoClaudePetOriginX") != nil,
           defaults.object(forKey: "RettoClaudePetOriginY") != nil {
            let saved = NSPoint(x: defaults.double(forKey: "RettoClaudePetOriginX"), y: defaults.double(forKey: "RettoClaudePetOriginY"))
            let savedFrame = NSRect(origin: saved, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(savedFrame) }) { return saved }
        }
        return defaultOrigin(for: size)
    }

    private func defaultOrigin(for size: NSSize) -> NSPoint {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24)
    }

    private func scaledWindowSize(_ scale: CGFloat) -> NSSize {
        petLayout(scale: scale).windowSize
    }

    /// 말풍선이 펼쳐지면 창을 아래로 늘린다. 위 변을 고정해야 레토가 화면에서 제자리에 있는다.
    private func applyRibbonExpansion(_ expanded: Bool) {
        let target = petLayout(scale: currentScale, expanded: expanded).windowSize
        let current = panel.frame
        guard abs(target.height - current.height) > 0.5 else { return }
        // 위 변을 고정하면 레토가 제자리에 있는다. 아래 모서리에 고정한 경우에는 반대로
        // 아래 변을 붙잡아야 창이 화면 밖으로 자라지 않는다.
        var next = NSRect(
            x: current.minX,
            y: pinnedCorner.anchorsToBottom ? current.minY : current.maxY - target.height,
            width: target.width,
            height: target.height
        )
        if let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame, next.minY < visible.minY {
            next.origin.y = visible.minY
        }
        isRepositioning = true
        panel.setFrame(next, display: true, animate: false)
        isRepositioning = false
        applyPinnedCorner()
    }

    /// VS Code 가 지금 열어 둔 창들의 폴더. 세션의 작업 폴더가 창 폴더의 하위일 때가 많아서,
    /// 그 하위 폴더를 그대로 열라고 하면 새 창이 생긴다. 그래서 조상이 되는 창 폴더로 바꿔 연다.
    /// 방금 연 창은 이 기록에 빠져 있을 수 있고, 그때는 nil 로 떨어져 폴더를 열지 않는다.
    private func editorWindowFolder(containing path: String) -> String? {
        let storage = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User/globalStorage/storage.json")
        guard let data = try? Data(contentsOf: storage),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let windows = root["windowsState"] as? [String: Any] else { return nil }

        var folders: [String] = []
        func collect(_ candidate: Any?) {
            guard let window = candidate as? [String: Any],
                  let folder = window["folder"] as? String,
                  let url = URL(string: folder),
                  url.isFileURL else { return }
            folders.append(url.path)
        }
        collect(windows["lastActiveWindow"])
        (windows["openedWindows"] as? [[String: Any]])?.forEach(collect)

        return folders
            .filter { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            .max(by: { $0.count < $1.count })
    }

    /// 목표 앱이 화면 맨 앞에 올 때까지 기다린다. 제한 시간을 넘기면 그냥 넘어간다 —
    /// 늦더라도 딥링크를 보내는 편이, 눌렀는데 아무 일도 없는 것보다 낫다.
    private func whenFrontmost(_ bundleIdentifier: String, timeout: TimeInterval, then next: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier || Date() >= deadline {
                next()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }
        poll()
    }

    /// 이미 그 폴더를 열어 둔 VS Code 창을 앞으로 보낸다.
    ///
    /// 예전에는 `NSWorkspace.open(폴더)` 를 썼는데, 바깥(LaunchServices)에서 폴더를 열면
    /// VS Code 는 `window.openFoldersInNewWindow` 기본값에 따라 **이미 열어 둔 창이 있어도 새 창**을 띄운다.
    /// 눌렀을 때 창이 하나 더 생기던 원인이 이것이다. 번들 안의 `code` CLI 는 같은 폴더를 연 창을 찾아
    /// 그 창을 앞으로 보내므로 이쪽을 쓴다. CLI 는 돌아오는 데 시간이 걸리니 메인 스레드를 잡지 않는다.
    private func focusEditorFolder(_ folder: String, editorURL: URL, then next: @escaping (Bool) -> Void) {
        let cli = editorURL.appendingPathComponent("Contents/Resources/app/bin/code")
        guard FileManager.default.isExecutableFile(atPath: cli.path) else {
            next(false)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = cli
            process.arguments = [folder]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            var ok = false
            do {
                try process.run()
                process.waitUntilExit()
                ok = process.terminationStatus == 0
            } catch {
                ok = false
            }
            DispatchQueue.main.async { next(ok) }
        }
    }

    /// `matchedWindow` 는 그 세션을 담은 창을 실제로 앞으로 보냈는지다.
    /// false 면 어느 창인지 모르므로 딥링크를 보내지 않는다 — 엉뚱한 창에 새 패널이 생기니까.
    private func focusHostApp(for payload: StatePayload?, app: OpenApp, then next: @escaping (_ matchedWindow: Bool) -> Void) {
        let editorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier)
            ?? URL(fileURLWithPath: app.fallbackPath)
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // 딥링크는 "지금 앞에 있는" 창으로 배달된다. 그래서 목표 앱이 실제로 앞에 온 뒤에 보내야 한다.
        // 예전에는 고정 시간(0.45초)만 세고 보냈는데, 그 안에 못 올라오면 딥링크가 직전에 보던 창에
        // 떨어져 엉뚱한 자리에 세션이 열렸다. 시간을 재는 대신 앞에 왔는지를 본다.
        let frontTimeout: TimeInterval = wasRunning ? 3 : 10
        // 앞에 온 뒤에도 창 전환과 확장 활성화에 잠깐 걸린다. 그만큼만 더 둔다.
        let settleDelay: TimeInterval = wasRunning ? 0.25 : 1.5

        let handler: (Error?, Bool) -> Void = { [weak self] error, matchedWindow in
            DispatchQueue.main.async {
                if error != nil {
                    NSSound.beep()
                    return
                }
                self?.whenFrontmost(app.bundleIdentifier, timeout: frontTimeout) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) { next(matchedWindow) }
                }
            }
        }

        if app.needsWindowFocusFirst,
           let cwd = payload?.cwd, !cwd.isEmpty,
           let folder = editorWindowFolder(containing: cwd),
           FileManager.default.fileExists(atPath: folder) {
            // 번들 안의 `code` 로 그 폴더의 창을 앞으로 보낸다. 실패하면 예전 방식으로 떨어진다 —
            // 창이 하나 더 뜰지언정 세션은 열리는 편이 아무 일도 안 일어나는 것보다 낫다.
            focusEditorFolder(folder, editorURL: editorURL) { focused in
                if focused {
                    // CLI 는 창을 고를 뿐 앱을 앞으로 보내지는 않는다. 그건 여기서 한다.
                    NSWorkspace.shared.openApplication(at: editorURL, configuration: configuration) { _, error in
                        handler(error, true)
                    }
                } else {
                    NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: editorURL, configuration: configuration) { _, error in
                        handler(error, true)
                    }
                }
            }
            return
        }
        // 창을 특정하지 못했다. 그래도 딥링크는 보낸다 — 확장이 지금 활성 창에서 세션을 열어 준다.
        // 예전에는 여기서 접었는데, 그러면 눌러도 아무 일이 없고 배지 숫자도 줄지 않았다.
        // Claude 앱은 세션이 창 하나에 모여 있어서, 앱을 앞으로 보낸 것이 곧 그 세션을 띄운 것이다.
        NSWorkspace.shared.openApplication(at: editorURL, configuration: configuration) { _, error in
            handler(error, true)
        }
    }

    private func openClaudeSession(_ payload: StatePayload?, app: OpenApp) {
        let target = payload ?? selectedPayload
        guard let url = claudeDeepLink(sessionId: target?.sessionId, app: app) else { return }
        if !NSWorkspace.shared.open(url) {
            NSSound.beep()
        }
    }

    /// 기본 동작: 세션을 가진 창을 앞으로 보낸 뒤 딥링크를 보내 그 탭까지 되살린다.
    /// ⌥ 를 누른 채면 창만 앞으로 보내고 탭은 건드리지 않는다.
    /// 읽음은 "그 세션을 실제로 눈앞에 띄웠을 때" 만 찍는다.
    /// 몸통·말풍선·배지 어느 쪽을 눌렀든 그 세션 탭이 앞으로 왔으면 다녀온 것이다.
    /// 반대로 ⌥(창만 앞으로)나 창을 특정하지 못해 딥링크를 못 보낸 경우는 아직 안 본 것으로 남긴다.
    private func revealClaudeSession(_ payload: StatePayload?, windowOnly: Bool) {
        let target = payload ?? selectedPayload
        let app = resolveOpenApp(for: target)
        focusHostApp(for: target, app: app) { [weak self] matchedWindow in
            guard let self, !windowOnly, matchedWindow else { return }
            self.openClaudeSession(target, app: app)
            self.markSeen(target)
        }
    }

    @objc private func changeSkin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let next = PetSkin(rawValue: raw) else { return }
        // 파일을 못 읽으면 설정을 바꾸지 않는다. 체크 표시만 옮겨 두면 다음 실행에 엉뚱한 모습이 뜬다.
        guard let sheet = loadSpriteSheet(next) else { return }
        skin = next
        petView.spriteSheet = sheet
        for item in skinItems {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
    }

    @objc private func changeTypeface(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let next = PetTypeface(rawValue: raw) else { return }
        typeface = next
        petView.typeface = next
        for item in typefaceItems {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
    }

    @objc private func changeOpenTarget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let next = OpenTarget(rawValue: raw) else { return }
        openTarget = next
        for item in openTargetItems {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
    }

    @objc private func selectAutomaticSession() {
        pinnedSessionId = nil
        applySessions(sessions)
    }

    @objc private func selectSession(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? String else { return }
        pinnedSessionId = sessionId
        applySessions(sessions)
        panel.orderFrontRegardless()
    }

    @objc private func toggleVisibility() {
        if panel.isVisible {
            panel.orderOut(nil)
            visibilityItem.title = "레토 보이기"
        } else {
            panel.orderFrontRegardless()
            visibilityItem.title = "레토 숨기기"
        }
    }

    @objc private func toggleClickThrough() {
        // 켜면 레토가 마우스를 아예 받지 않는다 — 우클릭 메뉴도 같이 막힌다.
        // 그래서 끄는 길이 메뉴 막대 발바닥 하나뿐인데, 그 아이콘은 메뉴 막대가 빠듯하면
        // 노치 뒤로 밀려 안 보인다. 둘이 겹치면 강제 종료 말고는 되돌릴 방법이 없다.
        // 켤 때만 한 번 알려 주고, 아는 사람은 다시 안 보게 한다.
        if !panel.ignoresMouseEvents, !UserDefaults.standard.bool(forKey: clickThroughNoticeDefaultsKey) {
            let notice = NSAlert()
            notice.messageText = "클릭 통과를 켤까요?"
            notice.informativeText = [
                "레토가 마우스를 받지 않게 됩니다. 뒤에 있는 창을 그대로 쓸 수 있는 대신,",
                "레토를 눌러 세션을 열거나 우클릭 메뉴를 여는 것도 안 됩니다.",
                "",
                "끄려면 메뉴 막대의 발바닥 → 「클릭 통과 끄기」 를 누르세요.",
                "발바닥이 안 보이면 ⌘ 를 누른 채 메뉴 막대 아이콘을 끌어 자리를 만들 수 있습니다."
            ].joined(separator: "\n")
            notice.addButton(withTitle: "켜기")
            notice.addButton(withTitle: "취소")
            notice.showsSuppressionButton = true
            notice.suppressionButton?.title = "다시 보지 않기"
            guard notice.runModal() == .alertFirstButtonReturn else { return }
            if notice.suppressionButton?.state == .on {
                UserDefaults.standard.set(true, forKey: clickThroughNoticeDefaultsKey)
            }
        }
        panel.ignoresMouseEvents.toggle()
        clickThroughItem.title = panel.ignoresMouseEvents ? "클릭 통과 끄기" : "클릭 통과 켜기"
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginItem.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "자동 실행 설정을 바꾸지 못했어요"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func changeScale(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        let nextScale = CGFloat(number.doubleValue)
        let nextSize = petLayout(scale: nextScale).windowSize
        let oldCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        var nextFrame = NSRect(
            x: oldCenter.x - nextSize.width / 2,
            y: oldCenter.y - nextSize.height / 2,
            width: nextSize.width,
            height: nextSize.height
        )
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        if let visible {
            nextFrame.origin.x = min(max(nextFrame.origin.x, visible.minX), visible.maxX - nextFrame.width)
            nextFrame.origin.y = min(max(nextFrame.origin.y, visible.minY), visible.maxY - nextFrame.height)
        }
        currentScale = nextScale
        petView.petScale = nextScale
        UserDefaults.standard.set(Double(nextScale), forKey: "RettoClaudePetScale")
        for item in sizeItems {
            let itemScale = CGFloat((item.representedObject as? NSNumber)?.doubleValue ?? 0)
            item.state = abs(itemScale - nextScale) < 0.001 ? .on : .off
        }
        isRepositioning = true
        panel.setFrame(nextFrame, display: true, animate: true)
        isRepositioning = false
        applyPinnedCorner()
    }

    @objc private func changeCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let corner = PetCorner(rawValue: raw) else { return }
        pinnedCorner = corner
        for item in cornerItems {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
        applyPinnedCorner()
        panel.orderFrontRegardless()
    }

    /// 저장된 자리가 걸쳐 있던 화면. 없으면 main 화면.
    private func lastKnownScreen(for size: NSSize) -> NSScreen {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "RettoClaudePetOriginX") != nil,
           defaults.object(forKey: "RettoClaudePetOriginY") != nil {
            let saved = NSRect(
                origin: NSPoint(x: defaults.double(forKey: "RettoClaudePetOriginX"), y: defaults.double(forKey: "RettoClaudePetOriginY")),
                size: size
            )
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(saved) }) { return screen }
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    /// 고정된 모서리로 창을 옮긴다. 자유 위치면 아무것도 하지 않는다.
    /// 배율을 바꾸거나 말풍선이 펼쳐져 창 크기가 변할 때도 불러서 모서리에 붙여 둔다.
    private func applyPinnedCorner() {
        guard panel != nil else { return }
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        guard let origin = cornerOrigin(corner: pinnedCorner, size: panel.frame.size, visible: visible) else { return }
        isRepositioning = true
        panel.setFrameOrigin(origin)
        isRepositioning = false
        // 고정 중에도 자리를 적어 둔다. 다음에 켤 때 어느 화면에 있었는지 알아야 한다.
        UserDefaults.standard.set(origin.x, forKey: "RettoClaudePetOriginX")
        UserDefaults.standard.set(origin.y, forKey: "RettoClaudePetOriginY")
    }

    @objc private func resetPosition() {
        pinnedCorner = .free
        for item in cornerItems {
            item.state = (item.representedObject as? String) == PetCorner.free.rawValue ? .on : .off
        }
        isRepositioning = true
        panel.setFrameOrigin(defaultOrigin(for: panel.frame.size))
        isRepositioning = false
        panel.orderFrontRegardless()
    }

    func windowDidMove(_ notification: Notification) {
        guard panel != nil, !isRepositioning else { return }
        // 사용자가 직접 끌었다. 모서리 고정은 그 순간 풀린다 — 끌어다 놓은 자리를 지켜 주는 게 맞다.
        if pinnedCorner != .free {
            pinnedCorner = .free
            for item in cornerItems {
                item.state = (item.representedObject as? String) == PetCorner.free.rawValue ? .on : .off
            }
        }
        UserDefaults.standard.set(panel.frame.origin.x, forKey: "RettoClaudePetOriginX")
        UserDefaults.standard.set(panel.frame.origin.y, forKey: "RettoClaudePetOriginY")
    }

    /// 사용자가 그 세션 창을 보고 있으면 읽음으로 센다.
    ///
    /// 레토를 누르지 않고 직접 세션에 다녀오는 경우를 잡는 유일한 길이다. 디스크에는
    /// "봤다" 는 기록이 없어서, 최상단 앱과 그 앱의 맨 앞 창 제목으로 알아낸다.
    /// 창 제목을 읽지 못하는 환경에서는 아무 일도 하지 않고 수동 지우기만 남는다.
    private func markSeenByLooking() {
        // 지울 것이 없으면 창 목록을 뒤질 이유가 없다. 0.25초마다 도는 자리다.
        let waiting = badgeSessions()
        guard !waiting.isEmpty else {
            lookingSince = nil
            lookingApp = nil
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleId = front.bundleIdentifier else {
            lookingSince = nil
            lookingApp = nil
            return
        }
        if bundleId != lookingApp {
            lookingApp = bundleId
            lookingSince = Date()
            return
        }
        guard let since = lookingSince, Date().timeIntervalSince(since) >= lookingDwell else { return }
        guard let title = frontWindowTitle(pid: front.processIdentifier), !title.isEmpty else { return }

        for payload in waiting where resolveOpenApp(for: payload).bundleIdentifier == bundleId {
            let folder = payload.cwd.map { ($0 as NSString).lastPathComponent }
            guard windowShowsSession(windowTitle: title, sessionTitle: payload.title, folderName: folder) else { continue }
            recordSeenFromAccess(payload)
        }
    }

    /// 다른 앱의 창 제목을 읽을 수 있나.
    ///
    /// macOS 는 창 제목 읽기를 화면 기록 권한으로 묶어 두었다. 권한이 없으면 제목이 빈 채로
    /// 와서 "그 세션 창을 보고 있으면 읽음" 판정이 조용히 꺼진다. 조용히 꺼지는 게 문제라
    /// 정보 창에서 상태를 보여 준다. 애드혹 서명이라 앱을 다시 빌드하면 권한이 풀릴 수 있다.
    private func canReadWindowTitles() -> Bool {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) != myPid,
                  let name = window[kCGWindowName as String] as? String else { return false }
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// 그 앱의 맨 앞 창 제목 하나. 뒤에 있는 창까지 보면 보고 있지 않은 세션도 지워진다.
    private func frontWindowTitle(pid: pid_t) -> String? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
            return window[kCGWindowName as String] as? String
        }
        return nil
    }

    /// 지울 것이 몇 개인지 메뉴에 그대로 보여 준다. 없으면 흐리게 둔다.
    private func updateClearAttentionItem(count: Int) {
        guard let item = clearAttentionItem else { return }
        item.title = count > 0 ? "완료 표시 지우기 (\(count)개)" : "완료 표시 지우기"
        item.isEnabled = count > 0
    }

    /// 배지가 세는 세션(답이 끝났는데 아직 안 본 것)을 모두 읽음으로 옮긴다.
    @objc private func markAllSeen() {
        let targets = badgeSessions()
        guard !targets.isEmpty else { return }
        var seen = seenSessions
        let now = Date().timeIntervalSince1970 * 1000
        for payload in targets {
            seen[payload.id] = max(payload.updatedAtMs ?? 0, now)
        }
        let live = Set(sessions.map(\.id))
        seenSessions = seen.filter { live.contains($0.key) }
        applySessions(sessions)
    }

    /// 레토가 누구이고 누가 만들었는지. 메일 주소는 눌러서 복사할 수 있게 둔다.
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = Retto.englishName + " · " + Retto.koreanName
        alert.informativeText = [
            Retto.character,
            "",
            "품종        " + Retto.sex + " " + Retto.breed,
            "생일        " + Retto.birthdayLabel + " · " + Retto.ageLabel,
            "",
            "만든 사람   " + Retto.creator,
            "메일        " + Retto.email,
            "링크드인    " + Retto.linkedIn,
            "버전        " + Retto.version,
            Retto.buildStamp.isEmpty ? nil : "빌드        " + Retto.buildStamp,
            "",
            "자동 읽음 판정   " + (canReadWindowTitles()
                ? "켜짐 — 세션 창을 3초 이상 보고 있으면 배지를 내려놓습니다"
                : "꺼짐 — 화면 기록 권한이 필요합니다"),
            "",
            "여러 Claude Code 세션을 대신 지켜보다가 내 답이 필요할 때",
            "알려 주고, 누르면 그 세션으로 데려다준다."
        ].compactMap { $0 }.joined(separator: "\n")
        if let icon = NSApp.applicationIconImage {
            alert.icon = icon
        }
        alert.addButton(withTitle: "닫기")
        alert.addButton(withTitle: "링크드인 열기")
        alert.addButton(withTitle: "메일 주소 복사")
        let needsPermission = !canReadWindowTitles()
        if needsPermission {
            alert.addButton(withTitle: "화면 기록 설정 열기")
        }
        // 알림창 글자는 눌러도 링크가 되지 않는다. 그래서 버튼으로 둔다.
        switch alert.runModal() {
        case .alertSecondButtonReturn:
            if let url = URL(string: Retto.linkedIn) { NSWorkspace.shared.open(url) }
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1) where needsPermission:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertThirdButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Retto.email, forType: .string)
        default:
            break
        }
    }

    @objc private func revealStateFile() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/retto-pet/state.json")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func screenConfigurationChanged() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        if pinnedCorner != .free {
            applyPinnedCorner()
        } else if !screens.contains(where: { $0.intersects(panel.frame) }) {
            resetPosition()
        }
    }

    /// 레토를 깨끗이 걷어낸다. 훅 등록·상태 파일·앱 설정·로그인 항목·앱 본체까지.
    /// 앱이 자기 번들을 지우는 일이라 되돌릴 수 없다. 그래서 먼저 묻는다.
    @objc private func uninstallRetto() {
        let confirm = NSAlert()
        confirm.messageText = Retto.koreanName + "를 제거할까요?"
        confirm.informativeText = [
            "아래를 정리하고 레토가 종료됩니다.",
            "",
            "· Claude Code 훅 등록 (~/.claude/settings.json)",
            "· 상태 파일과 훅 (~/.claude/retto-pet/)",
            "· 크기·위치 같은 앱 설정",
            "· 로그인할 때 자동 실행",
            "· 앱 본체 — 휴지통으로 갑니다",
            "",
            "Claude Code 자체와 다른 훅은 건드리지 않습니다."
        ].joined(separator: "\n")
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "제거")
        confirm.addButton(withTitle: "취소")
        // 엔터를 잘못 쳐서 지우는 일이 없게 기본 단추를 취소로 옮긴다.
        confirm.buttons[0].keyEquivalent = ""
        confirm.buttons[1].keyEquivalent = "\r"
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        // 지운 것이 되살아나지 않게 먼저 손을 뗀다.
        //   폴링 — 0.25초마다 도는 타이머가 알림창 중에도 살아 있어 읽음 기록을 되쓸 수 있다
        //   창 위치 — AppKit 이 종료할 때 프레임을 설정에 도로 쓴다. 이름을 비우면 쓰지 않는다
        isUninstalling = true
        stateMonitor?.stop()
        panel.setFrameAutosaveName("")

        // 훅 등록·상태 파일·자동 실행. 실제 작업은 `--uninstall` 과 같은 코드를 쓴다.
        let outcome = performUninstall()
        var report = outcome.lines

        // 4. 크기·위치·읽음 표시 같은 앱 설정. 실제로 지우는 것은 종료 직전이다 —
        //    여기서 지우면 알림창과 종료 사이에 AppKit 이 창 프레임을 도로 써 넣는다.
        report.append("· 앱 설정을 지웠습니다")

        let done = NSAlert()
        done.messageText = "정리했습니다"
        done.informativeText = (report + ["", "이제 앱을 휴지통으로 옮기고 종료합니다."]).joined(separator: "\n")
        done.addButton(withTitle: "확인")
        done.runModal()

        // 5. 앱 본체. 도는 중에 번들을 옮기는 건 macOS 가 허용한다 — 프로세스는 그대로 살아 있다.
        //    옮긴 뒤에 종료해야 앱이 자기 무덤을 다 파고 나갈 수 있다.
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([bundleURL]) { _, error in
            DispatchQueue.main.async { [weak self] in
                // 옮기지 못했으면 말해 준다. 앞에서 "휴지통으로 갑니다" 라고 해 놓고
                // 조용히 남겨 두면, 지운 줄 알았던 앱이 다음에 또 뜬다.
                if error != nil {
                    let failed = NSAlert()
                    failed.messageText = "앱을 휴지통으로 옮기지 못했어요"
                    failed.informativeText = "다른 건 정리했습니다. 아래 앱을 직접 지워 주세요.\n\n" + bundleURL.path
                    failed.addButton(withTitle: "위치 보기")
                    failed.addButton(withTitle: "닫기")
                    if failed.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
                    }
                }
                self?.clearDefaultsIfUninstalling()
                NSApp.terminate(nil)
            }
        }
    }

    /// 제거 중일 때만 설정을 지운다. 종료 직전과 종료 훅에서 두 번 부른다 —
    /// AppKit 이 마지막에 창 프레임을 써 넣어 지운 설정이 되살아나던 것을 막는다.
    private func clearDefaultsIfUninstalling() {
        guard isUninstalling, let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clearDefaultsIfUninstalling()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

